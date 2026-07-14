import SwiftUI
import Combine

/// Ties together: polling MediaRemote → fetching lyrics → tracking the current line.
@MainActor
final class PlayerModel: ObservableObject {
    private static let overlayEnabledKey = "overlayEnabled"
    private static let discordEnabledKey = "discordEnabled"
    private static let trackOffsetsKey = "syncTrackOffsets"
    private static let offsetKey = "syncLearnedOffset"

    @Published var lines: [LyricLine] = []
    @Published var currentIndex: Int = -1
    @Published var isHovering = false
    @Published private(set) var isPlaying = false    // overlay hides when false (paused/stopped/finished)
    @Published private(set) var isFetching = false   // a lyrics fetch is in flight

    /// User-facing switch from the menubar: when false the overlay window stays off
    /// screen even while music plays (the hover timer in AppDelegate gates on this
    /// together with `hasContent`).
    @Published var overlayEnabled: Bool {
        didSet { defaults.set(overlayEnabled, forKey: Self.overlayEnabledKey) }
    }

    /// User-facing switch from the menubar: when false we stop publishing Discord
    /// Rich Presence and clear any existing one. Default ON. (Independent of the
    /// overlay — Discord is a parallel consumer of the now-playing engine.)
    @Published var discordEnabled: Bool {
        didSet {
            guard discordEnabled != oldValue else { return }
            defaults.set(discordEnabled, forKey: Self.discordEnabledKey)
            if discordEnabled {
                if let lastNowPlaying { presenceController.update(for: lastNowPlaying) }
            } else {
                presenceController.clear()
            }
        }
    }

    private let defaults: UserDefaults
    private let presenceController: DiscordPresenceController

    /// Current "Artist · Title" for the menubar readout, or nil when idle. Uses a
    /// middle dot (no em dash) per the app's text style.
    @Published private(set) var currentTrack: String?

    /// Menubar status-row text: the current track, or a "Nothing playing" idle state.
    var nowPlayingDescription: String {
        guard isPlaying, let currentTrack else { return "No YouTube Music playing" }
        return currentTrack
    }

    var isDiscordConfigured: Bool { presenceController.isConfigured }

    /// Whether the overlay window should be on screen at all: only when music is
    /// playing AND we either have lyrics or are still looking them up. No music,
    /// or a track with no synced lyrics → the window is hidden entirely (not just
    /// transparent) so it stops reacting to hover/scroll over empty space.
    var hasContent: Bool { isPlaying && (!lines.isEmpty || isFetching) }

    /// Live sync correction applied to the current track (seconds). + = lyrics
    /// earlier, − = later. Starts each track from `learnedOffset`; the user
    /// refines it by scrolling over the overlay.
    @Published var syncOffset: Double

    /// Per-song corrections, keyed by trackKey. The per-song latency is largely
    /// random (a remaster, an MV edit, a different upload), so a correction must
    /// stick to ITS song and nowhere else — otherwise fixing one outlier drags
    /// every other song off. A song replays with exactly the offset you last gave it.
    private var trackOffsets: [String: Double]

    /// Gentle global baseline that UNSEEN songs start from — the typical output
    /// latency. Only MODEST corrections feed it (see `commit`); large per-song
    /// outliers are remembered per-song above and never allowed to poison it.
    private var learnedOffset: Double

    // Interpolation state, refreshed on every poll.
    private var baseElapsed: Double = 0
    private var baseDate = Date()
    private var sampleTimestamp: Double = 0
    private var rate: Double = 1

    private var currentTrackKey: String?

    // The most recent valid snapshot, so the menubar toggle can re-publish presence
    // without waiting for the next poll.
    private var lastNowPlaying: NowPlaying?

    // What syncOffset was set to when the current track loaded. Lets `commit`
    // tell a deliberate adjustment from an untouched track, so only songs you
    // actually corrected ever take a slot in `trackOffsets`.
    private var loadedOffset: Double = 0

    // Synced lyrics already fetched this session, keyed by trackKey. Avoids
    // re-hitting LRCLIB when the user replays or skips back to a track. A genuine
    // "LRCLIB has no synced lyrics for this track" empty IS cached (so lyric-less
    // tracks aren't refetched forever); a transient fetch failure (504/non-JSON/
    // network) is NOT cached, so the next 1s poll retries and self-heals.
    // Backed by `LyricsCache` on disk: a miss here falls through to the disk cache
    // before any LRCLIB fetch. Only tracks we found *lyrics* for are written to disk
    // (those never go stale); a genuine empty is kept in memory only, so a song that
    // simply has no lyrics on LRCLIB *yet* (e.g. a new release) is re-checked next
    // session instead of being cached empty forever.
    private var lyricsCache: [String: [LyricLine]] = [:]

    // True while a MediaRemote query is in flight, so the 1s poll never stacks
    // overlapping subprocess spawns if a query outruns the interval.
    private var isPolling = false

    private var pollTimer: Timer?
    private var tickTimer: Timer?

    init(
        presenceController: DiscordPresenceController,
        defaults: UserDefaults = .standard
    ) {
        self.presenceController = presenceController
        self.defaults = defaults
        overlayEnabled = defaults.object(forKey: Self.overlayEnabledKey) as? Bool ?? true
        discordEnabled = defaults.object(forKey: Self.discordEnabledKey) as? Bool ?? true
        syncOffset = defaults.double(forKey: Self.offsetKey)
        learnedOffset = defaults.double(forKey: Self.offsetKey)
        trackOffsets = defaults.dictionary(forKey: Self.trackOffsetsKey) as? [String: Double] ?? [:]
    }

    func start() {
        // Poll MediaRemote once a second (cheap; runs the JXA query off-main).
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }   // Timer fires on the main run loop
        }
        // Advance the highlighted line smoothly between polls.
        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        poll()
    }

    func stop() {
        pollTimer?.invalidate()
        tickTimer?.invalidate()
        presenceController.disconnect()
    }

    /// Live playback position. `elapsed` is sampled at `sampleTimestamp` (the
    /// player's clock) and doesn't tick on its own — especially for web players —
    /// so we project forward from that timestamp. Falls back to our own poll time
    /// if the player didn't supply a timestamp.
    private var virtualElapsed: Double {
        guard isPlaying else { return baseElapsed }
        let reference = sampleTimestamp > 0 ? sampleTimestamp : baseDate.timeIntervalSince1970
        return baseElapsed + (Date().timeIntervalSince1970 - reference) * rate
    }

    private func poll() {
        guard !isPolling else { return }   // previous query hasn't returned yet
        isPolling = true
        Task.detached(priority: .utility) {
            let np = MediaRemoteBridge.query()
            await MainActor.run {
                self.isPolling = false
                self.apply(np)
            }
        }
    }

    private func apply(_ np: NowPlaying?) {
        guard let np, np.isValid,
              YouTubeMusicSource.matches(bundle: np.sourceBundle, pid: np.sourcePID) else {
            isPlaying = false
            isFetching = false
            currentTrack = nil
            lastNowPlaying = nil
            presenceController.clear()
            if let leaving = currentTrackKey {
                commit(for: leaving)           // remember the track that just ended
                currentTrackKey = nil
                lines = []
                currentIndex = -1
            }
            return
        }

        // Re-sync interpolation baseline.
        baseElapsed = np.elapsed
        baseDate = Date()
        sampleTimestamp = np.timestamp
        isPlaying = np.isPlaying && np.rate > 0
        rate = np.rate > 0 ? np.rate : 1

        lastNowPlaying = np
        if discordEnabled {
            presenceController.update(for: np)
        }

        // New track? Serve from cache, otherwise fetch its lyrics.
        if np.trackKey != currentTrackKey {
            if let leaving = currentTrackKey { commit(for: leaving) }  // remember the track we're leaving
            // Menubar readout (middle dot separator, no em dash). Track identity is
            // (artist, title) — the same inputs as trackKey — so it only changes here.
            currentTrack = np.artist.isEmpty ? np.title : "\(np.artist) · \(np.title)"
            // Known song → its own saved offset; unseen song → the gentle baseline.
            syncOffset = trackOffsets[np.trackKey] ?? learnedOffset
            loadedOffset = syncOffset
            currentTrackKey = np.trackKey
            currentIndex = -1

            if let cached = lyricsCache[np.trackKey] {
                lines = cached
                isFetching = false
                return
            }
            // In-memory miss → try the disk cache before fetching. A track resolved
            // in an earlier session loads instantly and offline, dodging LRCLIB's
            // latency. Promote the hit into the in-memory cache so we read disk at
            // most once per track per session.
            if let disk = LyricsCache.load(np.trackKey) {
                lyricsCache[np.trackKey] = disk
                lines = disk
                isFetching = false
                return
            }

            lines = []
            isFetching = true
            // Fetch on a plain GCD background queue. The Swift-concurrency +
            // URLSession bridge stalls under AppKit's run loop, so we avoid it.
            DispatchQueue.global(qos: .userInitiated).async {
                let fetched = LRCLIB.fetchSynced(for: np)
                DispatchQueue.main.async {
                    guard np.trackKey == self.currentTrackKey else { return }
                    guard let fetched else {
                        // Transient failure (504/non-JSON/network). Don't cache, and
                        // clear currentTrackKey so the next 1s poll re-enters this
                        // branch and retries — self-healing instead of stuck on the
                        // loading dots forever. isFetching stays true so hasContent
                        // keeps the overlay alive across the retry.
                        self.currentTrackKey = nil
                        return
                    }
                    // Definitive result (lyrics, or a genuine empty). Cache in memory
                    // either way so replaying the track this session doesn't refetch.
                    // Persist to disk ONLY when we actually found lyrics: real lyrics
                    // never go stale, but an empty means "LRCLIB has none *yet*" — which
                    // is wrong for a newly released track that gets lyrics added days
                    // later. Keeping the empty in memory only lets the next session
                    // re-check and pick them up, instead of poisoning the song forever.
                    self.lyricsCache[np.trackKey] = fetched
                    if !fetched.isEmpty { LyricsCache.save(fetched, for: np.trackKey) }
                    self.lines = fetched
                    self.isFetching = false
                }
            }
        }
    }

    /// Switch to a line slightly BEFORE its timestamp so it finishes gliding to
    /// the centre right as it's sung — compensates for the spring's settle time
    /// (and a little for loose LRC files / audio latency). Bump if still late.
    private let leadTime: Double = 0.2

    /// Apply a live user correction from the scroll wheel. Responsive (takes
    /// effect immediately); the value is folded into `learnedOffset` when the
    /// track ends so it persists and converges.
    func nudgeSync(by delta: Double) {
        syncOffset = (min(15, max(-15, syncOffset + delta)) * 100).rounded() / 100
    }

    /// Persist a just-finished track's correction. The offset is saved per-song
    /// (so it's exact next replay), and ONLY modest corrections ease the global
    /// baseline — a large outlier like −5s stays with its song and can't drag the
    /// songs that already play correctly.
    private func commit(for trackKey: String) {
        // Untouched track → leave the store alone (don't add a slot for every song
        // that merely played through).
        guard abs(syncOffset - loadedOffset) >= 0.05 else { return }

        if abs(syncOffset) < 0.05 {
            trackOffsets.removeValue(forKey: trackKey)            // correction cleared → reclaim the slot
        } else {
            trackOffsets[trackKey] = syncOffset
        }
        defaults.set(trackOffsets, forKey: Self.trackOffsetsKey)

        guard abs(syncOffset) <= 2.5 else { return }              // outlier → per-song only
        if learnedOffset == 0 {
            learnedOffset = syncOffset                            // first calibration → adopt
        } else if syncOffset != learnedOffset {
            learnedOffset += 0.4 * (syncOffset - learnedOffset)   // ease toward the new value
        }
        defaults.set(learnedOffset, forKey: Self.offsetKey)
    }

    private func tick() {
        guard !lines.isEmpty else { return }
        let t = virtualElapsed + leadTime + syncOffset
        // Last line whose timestamp is at or before the current position.
        // Before the first line is reached we stay at -1 ("not started"): the
        // view then renders line 0 as the dimmed upcoming neighbour instead of
        // highlighting it at centre.
        var idx = -1
        // lines are sorted by time, so stop at the first one still in the future.
        for (i, line) in lines.enumerated() {
            if line.time <= t { idx = i } else { break }
        }
        // Let the view's .animation(value: currentIndex) drive the motion.
        if idx != currentIndex { currentIndex = idx }
    }
}
