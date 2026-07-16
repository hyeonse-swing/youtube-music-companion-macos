import SwiftUI
import Combine

/// Ties together: polling MediaRemote → fetching lyrics → tracking the current line.
@MainActor
final class PlayerModel: ObservableObject {
    private static let overlayEnabledKey = "overlayEnabled"
    private static let discordEnabledKey = "discordEnabled"

    @Published var lines: [LyricLine] = []
    @Published var currentIndex: Int = -1
    @Published var isHovering = false
    @Published private(set) var isPlaying = false    // overlay hides when false (paused/stopped/finished)
    @Published private(set) var isFetching = false   // metadata or lyrics fetch is in flight
    @Published private(set) var sourceNowPlaying: NowPlaying?
    @Published private(set) var youtubeMusicNowPlaying: NowPlaying?
    @Published private(set) var displayNowPlaying: NowPlaying?
    @Published private(set) var nowPlayingArtwork: NowPlayingArtwork?
    @Published private(set) var playbackElapsed: Double = 0
    @Published private(set) var lyricCandidates: [LyricCandidate] = []
    @Published private(set) var selectedLyricCandidateID: String?
    @Published private(set) var isFetchingLyricCandidates = false
    @Published private(set) var lyricCandidateStatusMessage: String?

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
                if let lastDiscordNowPlaying {
                    presenceController.update(
                        for: lastDiscordNowPlaying,
                        sourceArtwork: nowPlayingArtwork,
                        configuration: discordPresenceConfiguration
                    )
                }
            } else {
                presenceController.clear()
            }
        }
    }

    @Published var lyricsFontSize: Double {
        didSet {
            guard lyricsFontSize != oldValue else { return }
            preferences.lyricsFontSize = lyricsFontSize
            if lyricsFontSize != preferences.lyricsFontSize {
                lyricsFontSize = preferences.lyricsFontSize
            }
        }
    }

    @Published var displayMetadataSource: MetadataSourcePreference {
        didSet {
            guard displayMetadataSource != oldValue else { return }
            preferences.displayMetadataSource = displayMetadataSource
            refreshSelectedMetadataOutputs()
        }
    }

    @Published var discordMetadataSource: MetadataSourcePreference {
        didSet {
            guard discordMetadataSource != oldValue else { return }
            preferences.discordMetadataSource = discordMetadataSource
            refreshSelectedMetadataOutputs()
        }
    }

    @Published private(set) var discordPresenceConfiguration: DiscordPresenceConfiguration

    private let defaults: UserDefaults
    private let presenceController: DiscordPresenceController
    private let metadataResolver: TrackMetadataResolving
    private let artworkQuery: NowPlayingArtworkQuerying
    private var preferences: CompanionPreferences

    /// Current "Artist · Title" for the menubar readout, or nil when idle. Uses a
    /// middle dot (no em dash) per the app's text style.
    @Published private(set) var currentTrack: String?

    /// Menubar status-row text: the current track, or a "Nothing playing" idle state.
    var nowPlayingDescription: String {
        guard let currentTrack else { return "No YouTube Music playing" }
        return currentTrack
    }

    var hasNowPlaying: Bool { sourceNowPlaying != nil }

    var isDiscordConfigured: Bool { presenceController.isConfigured }

    var discordPreviewTrack: NowPlaying? { lastDiscordNowPlaying }

    var hasExactMetadataAccess: Bool { AccessibilityPermission.isGranted }

    func requestExactMetadataAccess() {
        AccessibilityPermission.requestFromMenu()
    }

    /// Whether the overlay window should be on screen at all: only when music is
    /// playing AND we either have lyrics or are still looking them up. No music,
    /// or a track with no synced lyrics → the window is hidden entirely (not just
    /// transparent) so it stops reacting to hover/scroll over empty space.
    var hasContent: Bool { isPlaying && (!lines.isEmpty || isFetching) }

    /// Live sync correction applied to the current track (seconds). + = lyrics
    /// earlier, − = later. Starts each track from `learnedOffset`; the user
    /// refines it by scrolling over the overlay.
    @Published var syncOffset: Double

    // Interpolation state, refreshed on every poll.
    private var baseElapsed: Double = 0
    private var baseDate = Date()
    private var sampleTimestamp: Double = 0
    private var rate: Double = 1

    private var currentTrackKey: String?

    // The most recent valid snapshot, so the menubar toggle can re-publish presence
    // without waiting for the next poll.
    private var lastDiscordNowPlaying: NowPlaying?

    // MediaRemote remains the stable playback identity. YouTube Music's player bar
    // supplies the exact visible labels used for display, lyrics, and Discord.
    private var latestSourceSnapshot: NowPlaying?
    private var metadataCache: [String: TrackMetadata] = [:]
    private var resolvingMetadataKeys: Set<String> = []
    private var metadataRetryAfter: [String: Date] = [:]
    private var activatedTrackKey: String?

    // Artwork is requested exactly once when a track begins. Successful bytes and
    // definitive misses are retained for this app session, so one-second playback
    // polling never performs image work and replaying a track is instant.
    private var artworkCache: [String: NowPlayingArtwork] = [:]
    private var missingArtworkKeys: Set<String> = []
    private var resolvingArtworkKeys: Set<String> = []

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
    private var lyricCandidateCache: [String: [LyricCandidate]] = [:]
    private var resolvingLyricCandidateKeys: Set<String> = []

    // True while a MediaRemote query is in flight, so the 1s poll never stacks
    // overlapping subprocess spawns if a query outruns the interval.
    private var isPolling = false

    private var pollTimer: Timer?
    private var tickTimer: Timer?

    init(
        presenceController: DiscordPresenceController,
        metadataResolver: TrackMetadataResolving = YouTubeMusicPageMetadataResolver(),
        artworkQuery: NowPlayingArtworkQuerying = DefaultNowPlayingArtworkQuery(),
        defaults: UserDefaults = .standard
    ) {
        let preferences = CompanionPreferences(defaults: defaults)
        self.presenceController = presenceController
        self.metadataResolver = metadataResolver
        self.artworkQuery = artworkQuery
        self.defaults = defaults
        self.preferences = preferences
        overlayEnabled = defaults.object(forKey: Self.overlayEnabledKey) as? Bool ?? true
        discordEnabled = defaults.object(forKey: Self.discordEnabledKey) as? Bool ?? true
        lyricsFontSize = preferences.lyricsFontSize
        displayMetadataSource = preferences.displayMetadataSource
        discordMetadataSource = preferences.discordMetadataSource
        discordPresenceConfiguration = preferences.discordPresenceConfiguration
        syncOffset = preferences.learnedTimingOffset
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

    private func apply(_ source: NowPlaying?) {
        guard let source, source.isValid,
              YouTubeMusicSource.matches(bundle: source.sourceBundle, pid: source.sourcePID) else {
            clearPlayback()
            return
        }

        updatePlaybackClock(from: source)
        latestSourceSnapshot = source
        sourceNowPlaying = source

        let sourceKey = source.trackKey
        if sourceKey != currentTrackKey {
            beginTrack(source, sourceKey: sourceKey)
        }

        if let metadata = metadataCache[sourceKey] {
            updateActiveTrack(
                source: source,
                youtubeMusicTrack: source.applying(metadata),
                sourceKey: sourceKey
            )
        } else if let retryAfter = metadataRetryAfter[sourceKey], retryAfter > Date() {
            updateActiveTrack(source: source, youtubeMusicTrack: nil, sourceKey: sourceKey)
        } else {
            metadataRetryAfter.removeValue(forKey: sourceKey)
            resolveMetadata(for: source, sourceKey: sourceKey)
        }
    }

    private func clearPlayback() {
        isPlaying = false
        isFetching = false
        currentTrack = nil
        lastDiscordNowPlaying = nil
        latestSourceSnapshot = nil
        sourceNowPlaying = nil
        youtubeMusicNowPlaying = nil
        displayNowPlaying = nil
        nowPlayingArtwork = nil
        playbackElapsed = 0
        activatedTrackKey = nil
        presenceController.clear()
        if let leaving = currentTrackKey {
            commit(for: leaving)
        }
        currentTrackKey = nil
        lines = []
        currentIndex = -1
        lyricCandidates = []
        selectedLyricCandidateID = nil
        isFetchingLyricCandidates = false
        lyricCandidateStatusMessage = nil
    }

    private func updatePlaybackClock(from source: NowPlaying) {
        baseElapsed = source.elapsed
        baseDate = Date()
        sampleTimestamp = source.timestamp
        isPlaying = source.isPlaying && source.rate > 0
        rate = source.rate > 0 ? source.rate : 1
        playbackElapsed = clampedElapsed(baseElapsed, duration: source.duration)
    }

    private func beginTrack(_ source: NowPlaying, sourceKey: String) {
        if let leaving = currentTrackKey { commit(for: leaving) }

        currentTrackKey = sourceKey
        activatedTrackKey = nil
        lastDiscordNowPlaying = nil
        youtubeMusicNowPlaying = nil
        displayNowPlaying = source
        currentTrack = trackDescription(for: source)
        syncOffset = preferences.timingOffset(for: sourceKey)
        loadedOffset = syncOffset
        currentIndex = -1
        lines = []
        lyricCandidates = []
        selectedLyricCandidateID = nil
        lyricCandidateStatusMessage = nil
        isFetchingLyricCandidates = false
        isFetching = true
        presenceController.clear()
        loadArtwork(sourceKey: sourceKey)
    }

    private func resolveMetadata(for source: NowPlaying, sourceKey: String) {
        guard resolvingMetadataKeys.insert(sourceKey).inserted else { return }
        let resolver = metadataResolver

        Task.detached(priority: .utility) {
            let metadata = resolver.resolve(for: source)
            await self.finishMetadataResolution(metadata, sourceKey: sourceKey)
        }
    }

    private func finishMetadataResolution(_ metadata: TrackMetadata?, sourceKey: String) {
        resolvingMetadataKeys.remove(sourceKey)
        guard
            currentTrackKey == sourceKey,
            let latest = latestSourceSnapshot,
            latest.trackKey == sourceKey
        else { return }

        guard let metadata else {
            // Keep playback functional while offline, then retry at a restrained
            // interval instead of either giving up for the session or hammering the
            // storefront once per one-second playback poll.
            metadataRetryAfter[sourceKey] = Date().addingTimeInterval(15)
            updateActiveTrack(source: latest, youtubeMusicTrack: nil, sourceKey: sourceKey)
            return
        }

        metadataCache[sourceKey] = metadata
        updateActiveTrack(
            source: latest,
            youtubeMusicTrack: latest.applying(metadata),
            sourceKey: sourceKey
        )
    }

    private func updateActiveTrack(
        source: NowPlaying,
        youtubeMusicTrack: NowPlaying?,
        sourceKey: String
    ) {
        sourceNowPlaying = source
        youtubeMusicNowPlaying = youtubeMusicTrack
        refreshSelectedMetadataOutputs()

        guard activatedTrackKey != sourceKey else { return }
        activatedTrackKey = sourceKey
        loadLyrics(for: youtubeMusicTrack ?? source, cacheKey: sourceKey)
    }

    private func refreshSelectedMetadataOutputs() {
        guard let source = sourceNowPlaying else { return }

        let display = displayMetadataSource.select(
            youtubeMusic: youtubeMusicNowPlaying,
            macOS: source
        ) ?? source
        displayNowPlaying = display
        currentTrack = trackDescription(for: display)

        let discordTrack = discordMetadataSource.select(
            youtubeMusic: youtubeMusicNowPlaying,
            macOS: source
        ) ?? source
        lastDiscordNowPlaying = discordTrack
        if discordEnabled {
            presenceController.update(
                for: discordTrack,
                sourceArtwork: nowPlayingArtwork,
                configuration: discordPresenceConfiguration
            )
        }
    }

    private func loadArtwork(sourceKey: String) {
        if let cached = artworkCache[sourceKey] {
            nowPlayingArtwork = cached
            return
        }
        nowPlayingArtwork = nil
        guard
            !missingArtworkKeys.contains(sourceKey),
            resolvingArtworkKeys.insert(sourceKey).inserted
        else { return }

        let query = artworkQuery
        Task.detached(priority: .utility) {
            let artwork = query.query()
            await self.finishArtworkLoad(artwork, sourceKey: sourceKey)
        }
    }

    private func finishArtworkLoad(_ artwork: NowPlayingArtwork?, sourceKey: String) {
        resolvingArtworkKeys.remove(sourceKey)
        guard
            currentTrackKey == sourceKey,
            latestSourceSnapshot?.trackKey == sourceKey
        else { return }

        if let artwork {
            artworkCache[sourceKey] = artwork
            nowPlayingArtwork = artwork
            if discordEnabled, let lastDiscordNowPlaying {
                presenceController.update(
                    for: lastDiscordNowPlaying,
                    sourceArtwork: artwork,
                    configuration: discordPresenceConfiguration
                )
            }
        } else {
            missingArtworkKeys.insert(sourceKey)
            nowPlayingArtwork = nil
        }
    }

    private func trackDescription(for track: NowPlaying) -> String {
        track.artist.isEmpty ? track.title : "\(track.artist) · \(track.title)"
    }

    private func loadLyrics(for track: NowPlaying, cacheKey: String) {
        if let candidates = lyricCandidateCache[cacheKey] {
            applyLyricCandidates(candidates, cacheKey: cacheKey)
            isFetching = false
            return
        }

        if let cached = lyricsCache[cacheKey] {
            lines = cached
            isFetching = false
            fetchLyricCandidates(for: track, cacheKey: cacheKey, preservesCurrentLines: true)
            return
        }

        // In-memory miss → try the disk cache before fetching. A track resolved in an
        // earlier session loads instantly and offline. The source metadata key stays
        // stable even when its displayed title was replaced with the page label.
        if let disk = LyricsCache.load(cacheKey) {
            lyricsCache[cacheKey] = disk
            lines = disk
            isFetching = false
            fetchLyricCandidates(for: track, cacheKey: cacheKey, preservesCurrentLines: true)
            return
        }

        lines = []
        isFetching = true
        fetchLyricCandidates(for: track, cacheKey: cacheKey, preservesCurrentLines: false)
    }

    private func fetchLyricCandidates(
        for track: NowPlaying,
        cacheKey: String,
        preservesCurrentLines: Bool
    ) {
        guard resolvingLyricCandidateKeys.insert(cacheKey).inserted else { return }
        isFetchingLyricCandidates = true
        lyricCandidateStatusMessage = nil
        if !preservesCurrentLines { isFetching = true }

        DispatchQueue.global(qos: .userInitiated).async {
            let fetched = LRCLIB.fetchCandidates(for: track)
            DispatchQueue.main.async {
                self.resolvingLyricCandidateKeys.remove(cacheKey)
                guard cacheKey == self.currentTrackKey else { return }
                self.isFetchingLyricCandidates = false
                guard let fetched else {
                    // A transient LRCLIB failure retries on the next playback poll,
                    // without throwing away the already-resolved page metadata.
                    if self.lines.isEmpty { self.activatedTrackKey = nil }
                    self.isFetching = false
                    self.lyricCandidateStatusMessage =
                        "Couldn’t load lyric choices. Check your connection and try again."
                    return
                }

                self.lyricCandidateCache[cacheKey] = fetched
                self.applyLyricCandidates(fetched, cacheKey: cacheKey)
                self.isFetching = false
            }
        }
    }

    private func applyLyricCandidates(_ candidates: [LyricCandidate], cacheKey: String) {
        lyricCandidates = candidates
        guard !candidates.isEmpty else {
            selectedLyricCandidateID = nil
            lines = []
            lyricsCache[cacheKey] = []
            lyricCandidateStatusMessage = "No synced lyric choices were found for this song."
            return
        }

        let preferredID = preferences.selectedLyricCandidate(for: cacheKey)
        let selected = candidates.first(where: { $0.id == preferredID }) ?? candidates[0]
        selectedLyricCandidateID = selected.id
        lines = selected.lines
        lyricsCache[cacheKey] = selected.lines
        LyricsCache.save(selected.lines, for: cacheKey)
        lyricCandidateStatusMessage = nil
        tick()
    }

    func selectLyricCandidate(_ candidateID: String) {
        guard
            let cacheKey = currentTrackKey,
            let selected = lyricCandidates.first(where: { $0.id == candidateID })
        else { return }

        preferences.selectLyricCandidate(candidateID, for: cacheKey)
        selectedLyricCandidateID = candidateID
        lines = selected.lines
        lyricsCache[cacheKey] = selected.lines
        LyricsCache.save(selected.lines, for: cacheKey)
        tick()
    }

    func reloadLyricCandidates() {
        guard
            let cacheKey = currentTrackKey,
            let track = youtubeMusicNowPlaying ?? sourceNowPlaying
        else { return }
        fetchLyricCandidates(for: track, cacheKey: cacheKey, preservesCurrentLines: true)
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

    func resetCurrentLyricsTiming() {
        guard let currentTrackKey else { return }
        preferences.resetTimingOffset(for: currentTrackKey)
        syncOffset = 0
        loadedOffset = 0
        tick()
    }

    func resetAllLyricsTiming() {
        preferences.resetAllTimingOffsets()
        syncOffset = 0
        loadedOffset = 0
        tick()
    }

    func resetLyricsFontSize() {
        lyricsFontSize = CompanionPreferences.defaultLyricsFontSize
    }

    func applyDiscordPresenceConfiguration(_ configuration: DiscordPresenceConfiguration) {
        guard configuration != discordPresenceConfiguration else { return }
        discordPresenceConfiguration = configuration
        preferences.discordPresenceConfiguration = configuration
        republishDiscordPresenceIfNeeded()
    }

    func resetDiscordPresenceConfiguration() {
        let changed = discordPresenceConfiguration != .standard
        preferences.resetDiscordPresenceConfiguration()
        discordPresenceConfiguration = .standard
        if changed { republishDiscordPresenceIfNeeded() }
    }

    private func republishDiscordPresenceIfNeeded() {
        guard discordEnabled, let lastDiscordNowPlaying else { return }
        presenceController.update(
            for: lastDiscordNowPlaying,
            sourceArtwork: nowPlayingArtwork,
            configuration: discordPresenceConfiguration
        )
    }

    /// Persist a just-finished track's correction. The offset is saved per-song
    /// (so it's exact next replay), and ONLY modest corrections ease the global
    /// baseline — a large outlier like −5s stays with its song and can't drag the
    /// songs that already play correctly.
    private func commit(for trackKey: String) {
        // Untouched track → leave the store alone (don't add a slot for every song
        // that merely played through).
        guard abs(syncOffset - loadedOffset) >= 0.05 else { return }

        preferences.saveTimingOffset(syncOffset, for: trackKey)

        guard abs(syncOffset) <= 2.5 else { return }              // outlier → per-song only
        var learnedOffset = preferences.learnedTimingOffset
        if learnedOffset == 0 {
            learnedOffset = syncOffset                            // first calibration → adopt
        } else if syncOffset != learnedOffset {
            learnedOffset += 0.4 * (syncOffset - learnedOffset)   // ease toward the new value
        }
        preferences.saveLearnedTimingOffset(learnedOffset)
    }

    private func tick() {
        playbackElapsed = clampedElapsed(
            virtualElapsed,
            duration: sourceNowPlaying?.duration ?? 0
        )
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

    private func clampedElapsed(_ elapsed: Double, duration: Double) -> Double {
        guard duration > 0 else { return max(0, elapsed) }
        return min(duration, max(0, elapsed))
    }
}
