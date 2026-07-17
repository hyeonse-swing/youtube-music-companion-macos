import SwiftUI
import Combine
import Translation

/// Ties together: polling MediaRemote → fetching lyrics → tracking the current line.
@MainActor
final class PlayerModel: ObservableObject {
    private static let overlayEnabledKey = "overlayEnabled"
    private static let discordEnabledKey = "discordEnabled"

    @Published var lines: [LyricLine] = [] {
        didSet {
            updateTickTimerState()
            guard lines != oldValue else { return }
            refreshLyricLayers()
        }
    }
    @Published var currentIndex: Int = -1
    @Published var isHovering = false
    @Published private(set) var isPlaying = false {  // overlay hides when false (paused/stopped/finished)
        didSet { updateTickTimerState() }
    }
    @Published private(set) var isFetching = false   // metadata or lyrics fetch is in flight
    @Published private(set) var sourceNowPlaying: NowPlaying?
    @Published private(set) var youtubeMusicNowPlaying: NowPlaying?
    @Published private(set) var displayNowPlaying: NowPlaying?
    @Published private(set) var nowPlayingArtwork: NowPlayingArtwork?
    @Published private(set) var lyricCandidates: [LyricCandidate] = [] {
        didSet {
            guard lyricCandidates != oldValue, showsRomanizedLyrics else { return }
            refreshRomanizedLyrics()
        }
    }
    @Published private(set) var selectedLyricCandidateID: String?
    @Published private(set) var isFetchingLyricCandidates = false
    @Published private(set) var lyricCandidateStatusMessage: String?
    @Published private(set) var customLyricsSourceName: String?
    @Published private(set) var lyricsDiskCacheStatistics: LyricsCacheStatistics
    @Published private(set) var translationDiskCacheStatistics: LyricsCacheStatistics
    @Published private(set) var discordConnectionStatus: DiscordConnectionStatus
    @Published private(set) var runtimeDiagnostics: PlayerRuntimeDiagnostics
    @Published private(set) var romanizedLines: [String] = []
    @Published private(set) var translatedLines: [String] = []
    @Published private(set) var lyricTranslationStatus: LyricTranslationStatus = .disabled
    @Published private(set) var lyricTranslationRequest: LyricTranslationRequest?
    @Published private(set) var manualDiscordPresenceSession: ManualDiscordPresenceSession?

    /// User-facing switch from the menubar: when false the overlay window stays off
    /// screen even while music plays (the hover timer in AppDelegate gates on this
    /// together with `hasContent`).
    @Published var overlayEnabled: Bool {
        didSet {
            defaults.set(overlayEnabled, forKey: Self.overlayEnabledKey)
            updateTickTimerState()
        }
    }

    /// User-facing switch from the menubar: when false we stop publishing Discord
    /// Rich Presence and clear any existing one. Default ON. (Independent of the
    /// overlay — Discord is a parallel consumer of the now-playing engine.)
    @Published var discordEnabled: Bool {
        didSet {
            guard discordEnabled != oldValue else { return }
            defaults.set(discordEnabled, forKey: Self.discordEnabledKey)
            if discordEnabled {
                if let session = manualDiscordPresenceSession,
                   let activity = session.presence.activity(startedAt: session.startedAt)
                {
                    presenceController.publishManual(
                        activity,
                        sessionKey: session.sessionKey
                    )
                } else if let lastDiscordNowPlaying,
                          !isDiscordTrackPrivate(lastDiscordNowPlaying)
                {
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

    @Published var overlayPreset: OverlayPreset {
        didSet {
            guard overlayPreset != oldValue else { return }
            preferences.overlayPreset = overlayPreset
        }
    }

    @Published var karaokeModeEnabled: Bool {
        didSet {
            guard karaokeModeEnabled != oldValue else { return }
            preferences.karaokeModeEnabled = karaokeModeEnabled
        }
    }

    @Published var showsRomanizedLyrics: Bool {
        didSet {
            guard showsRomanizedLyrics != oldValue else { return }
            preferences.showsRomanizedLyrics = showsRomanizedLyrics
            refreshRomanizedLyrics()
        }
    }

    @Published var showsTranslatedLyrics: Bool {
        didSet {
            guard showsTranslatedLyrics != oldValue else { return }
            preferences.showsTranslatedLyrics = showsTranslatedLyrics
            refreshTranslationLayer()
        }
    }

    @Published var translationTargetLanguage: LyricTranslationLanguage {
        didSet {
            guard translationTargetLanguage != oldValue else { return }
            preferences.translationTargetLanguage = translationTargetLanguage
            refreshTranslationLayer()
        }
    }

    @Published var translationTone: LyricTranslationTone {
        didSet {
            guard translationTone != oldValue else { return }
            preferences.translationTone = translationTone
            refreshTranslationLayer()
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
    private let nowPlayingQuery: NowPlayingQuerying
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

    var hasCustomLyrics: Bool { customLyricsSourceName != nil }

    var canExportLyrics: Bool { hasNowPlaying && !lines.isEmpty }

    var visibleLyricLayerCount: Int {
        var count = 1
        if showsRomanizedLyrics, !romanizedLines.isEmpty {
            count += 1
        }
        if showsTranslatedLyrics,
           lyricTranslationRequest != nil
               || lyricTranslationStatus == .translating
               || !translatedLines.isEmpty
        {
            count += 1
        }
        return count
    }

    func romanizedText(at index: Int) -> String? {
        guard showsRomanizedLyrics, romanizedLines.indices.contains(index) else { return nil }
        let text = romanizedLines[index]
        return text.isEmpty ? nil : text
    }

    func translatedText(at index: Int) -> String? {
        guard showsTranslatedLyrics, translatedLines.indices.contains(index) else { return nil }
        let text = translatedLines[index]
        return text.isEmpty ? nil : text
    }

    var suggestedLyricsFilename: String {
        guard let track = displayNowPlaying ?? youtubeMusicNowPlaying ?? sourceNowPlaying else {
            return "Lyrics.lrc"
        }
        return LyricsFileDocument.suggestedFilename(for: track)
    }

    var isDiscordConfigured: Bool { presenceController.isConfigured }

    var discordPreviewTrack: NowPlaying? { lastDiscordNowPlaying }

    var isCurrentDiscordTrackPrivate: Bool {
        guard let lastDiscordNowPlaying else { return false }
        return isDiscordTrackPrivate(lastDiscordNowPlaying)
    }

    var privateDiscordTrackCount: Int {
        preferences.privateDiscordTrackCount
    }

    var playbackElapsed: Double {
        clampedElapsed(virtualElapsed, duration: sourceNowPlaying?.duration ?? 0)
    }

    func karaokeProgress(for lineIndex: Int, at date: Date) -> Double {
        guard karaokeModeEnabled, lineIndex == currentIndex else { return 0 }
        let duration = sourceNowPlaying?.duration ?? 0
        let timelineElapsed = clampedElapsed(
            virtualElapsed(at: date),
            duration: duration
        ) + leadTime + syncOffset
        return LyricKaraokeTimeline.progress(
            elapsed: timelineElapsed,
            currentIndex: lineIndex,
            lines: lines,
            trackDuration: duration
        )
    }

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
    /// earlier, − = later. New tracks start at zero; a deliberately adjusted
    /// track restores only its own saved value.
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
    private var latestYouTubeMusicSnapshot: NowPlaying?
    private var metadataCache = LRUCache<String, TrackMetadata>(
        capacity: SessionCacheLimits.metadata
    )
    private var metadataRetryAfter = LRUCache<String, Date>(
        capacity: SessionCacheLimits.retryState
    )
    private var activatedTrackKey: String?

    // Artwork is requested when a track begins. Successful bytes and definitive
    // misses live in small session caches, so one-second playback polling never
    // performs image work while long listening sessions stay memory-bounded.
    private var artworkCache = LRUCache<String, NowPlayingArtwork>(
        capacity: SessionCacheLimits.artwork
    )
    private var missingArtworkKeys = BoundedSet<String>(
        capacity: SessionCacheLimits.negativeResults
    )

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
    private var lyricsCache = LRUCache<String, [LyricLine]>(
        capacity: SessionCacheLimits.lyrics
    )
    private var lyricCandidateCache = LRUCache<String, [LyricCandidate]>(
        capacity: SessionCacheLimits.lyricCandidates
    )

    private var pollTimer: Timer?
    private var tickTimer: Timer?
    private var isStarted = false
    private var pollOperation: CancellableTaskOperation?
    private var metadataOperation: CancellableTaskOperation?
    private var artworkOperation: CancellableTaskOperation?
    private var lyricsOperation: CancellableTaskOperation?
    private var romanizationTask: Task<Void, Never>?
    private var romanizationRequestID = UUID()
    private var manualPresenceTimer: Timer?

    init(
        presenceController: DiscordPresenceController,
        metadataResolver: TrackMetadataResolving = YouTubeMusicPageMetadataResolver(),
        nowPlayingQuery: NowPlayingQuerying = DefaultNowPlayingQuery(),
        artworkQuery: NowPlayingArtworkQuerying = DefaultNowPlayingArtworkQuery(),
        defaults: UserDefaults = .standard
    ) {
        let preferences = CompanionPreferences(defaults: defaults)
        self.presenceController = presenceController
        self.metadataResolver = metadataResolver
        self.nowPlayingQuery = nowPlayingQuery
        self.artworkQuery = artworkQuery
        self.defaults = defaults
        self.preferences = preferences
        overlayEnabled = defaults.object(forKey: Self.overlayEnabledKey) as? Bool ?? true
        discordEnabled = defaults.object(forKey: Self.discordEnabledKey) as? Bool ?? true
        lyricsFontSize = preferences.lyricsFontSize
        overlayPreset = preferences.overlayPreset
        karaokeModeEnabled = preferences.karaokeModeEnabled
        showsRomanizedLyrics = preferences.showsRomanizedLyrics
        showsTranslatedLyrics = preferences.showsTranslatedLyrics
        translationTargetLanguage = preferences.translationTargetLanguage
        translationTone = preferences.translationTone
        displayMetadataSource = preferences.displayMetadataSource
        discordMetadataSource = preferences.discordMetadataSource
        discordPresenceConfiguration = preferences.discordPresenceConfiguration
        lyricsDiskCacheStatistics = LyricsCache.statistics()
        translationDiskCacheStatistics = LyricTranslationCache.statistics()
        discordConnectionStatus = presenceController.connectionStatus
        runtimeDiagnostics = PlayerRuntimeDiagnostics(
            discordStatus: presenceController.connectionStatus
        )
        if preferences.showsTranslatedLyrics {
            if #available(macOS 15.0, *) {
                lyricTranslationStatus = .waiting
            } else {
                lyricTranslationStatus = .unavailable
            }
        }
        syncOffset = 0
        presenceController.onConnectionStatusChange = { [weak self] status in
            self?.discordConnectionStatus = status
            self?.refreshRuntimeDiagnostics()
        }
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        schedulePoll(after: 0)
        updateTickTimerState()
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        pollTimer?.invalidate()
        pollTimer = nil
        tickTimer?.invalidate()
        tickTimer = nil
        pollOperation?.cancel()
        pollOperation = nil
        cancelTrackOperations()
        manualPresenceTimer?.invalidate()
        manualPresenceTimer = nil
        presenceController.disconnect()
        refreshRuntimeDiagnostics()
    }

    /// Live playback position. `elapsed` is sampled at `sampleTimestamp` (the
    /// player's clock) and doesn't tick on its own — especially for web players —
    /// so we project forward from that timestamp. Falls back to our own poll time
    /// if the player didn't supply a timestamp.
    private var virtualElapsed: Double {
        virtualElapsed(at: Date())
    }

    private func virtualElapsed(at date: Date) -> Double {
        guard isPlaying else { return baseElapsed }
        let reference = sampleTimestamp > 0 ? sampleTimestamp : baseDate.timeIntervalSince1970
        return baseElapsed + (date.timeIntervalSince1970 - reference) * rate
    }

    private func poll() {
        guard isStarted, pollOperation == nil else { return }
        let operationID = UUID()
        let cancellation = CancellationToken()
        let startedAt = Date()
        let query = nowPlayingQuery
        let operation = CancellableTaskOperation(
            id: operationID,
            key: "now-playing",
            cancellation: cancellation
        )
        pollOperation = operation
        let task = Task.detached(priority: .utility) {
            let nowPlaying = query.query(cancellation: cancellation)
            await self.finishPoll(
                nowPlaying,
                operationID: operationID,
                startedAt: startedAt,
                wasCancelled: cancellation.isCancelled
            )
        }
        operation.attach(task)
        refreshRuntimeDiagnostics()
    }

    private func finishPoll(
        _ source: NowPlaying?,
        operationID: UUID,
        startedAt: Date,
        wasCancelled: Bool
    ) {
        guard pollOperation?.id == operationID else { return }
        pollOperation = nil
        guard isStarted, !wasCancelled else {
            refreshRuntimeDiagnostics()
            return
        }

        let previousTrack = sourceNowPlaying
        apply(source)
        runtimeDiagnostics.lastPollDate = Date()
        runtimeDiagnostics.lastPollDuration = Date().timeIntervalSince(startedAt)

        // One transient nil receives one quick recovery poll before the fully idle
        // cadence takes over. This avoids a ten-second gap after a single bridge miss.
        let cadenceTrack = sourceNowPlaying ?? (source == nil ? previousTrack : nil)
        schedulePoll(after: PlaybackPollingSchedule.interval(for: cadenceTrack))
        refreshRuntimeDiagnostics()
    }

    private func schedulePoll(after interval: TimeInterval) {
        guard isStarted else { return }
        pollTimer?.invalidate()
        pollTimer = nil

        let modeTrack = sourceNowPlaying
        runtimeDiagnostics.pollMode = PlaybackPollingSchedule.mode(for: modeTrack)
        runtimeDiagnostics.nextPollInterval = interval

        if interval <= 0 {
            poll()
            return
        }
        pollTimer = Timer.scheduledTimer(
            withTimeInterval: interval,
            repeats: false
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
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
        if sourceNowPlaying?.hasSamePresentation(as: source) != true {
            sourceNowPlaying = source
        }

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
        guard
            currentTrackKey != nil || sourceNowPlaying != nil || currentTrack != nil
                || isPlaying || isFetching
        else { return }

        cancelTrackOperations()
        isPlaying = false
        isFetching = false
        currentTrack = nil
        lastDiscordNowPlaying = nil
        latestSourceSnapshot = nil
        latestYouTubeMusicSnapshot = nil
        sourceNowPlaying = nil
        youtubeMusicNowPlaying = nil
        displayNowPlaying = nil
        nowPlayingArtwork = nil
        activatedTrackKey = nil
        if manualDiscordPresenceSession == nil {
            presenceController.clear()
        }
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
        customLyricsSourceName = nil
    }

    private func updatePlaybackClock(from source: NowPlaying) {
        baseElapsed = source.elapsed
        baseDate = Date()
        sampleTimestamp = source.timestamp
        let sourceIsPlaying = source.isPlaying && source.rate > 0
        if isPlaying != sourceIsPlaying {
            isPlaying = sourceIsPlaying
        }
        rate = source.rate > 0 ? source.rate : 1
    }

    private func beginTrack(_ source: NowPlaying, sourceKey: String) {
        if let leaving = currentTrackKey { commit(for: leaving) }
        cancelTrackOperations()

        currentTrackKey = sourceKey
        activatedTrackKey = nil
        lastDiscordNowPlaying = nil
        latestYouTubeMusicSnapshot = nil
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
        customLyricsSourceName = nil
        isFetchingLyricCandidates = false
        isFetching = true
        if manualDiscordPresenceSession == nil {
            presenceController.clear()
        }
        loadArtwork(sourceKey: sourceKey)
    }

    private func resolveMetadata(for source: NowPlaying, sourceKey: String) {
        if metadataOperation?.key == sourceKey { return }
        metadataOperation?.cancel()
        let resolver = metadataResolver
        let operationID = UUID()
        let cancellation = CancellationToken()
        let operation = CancellableTaskOperation(
            id: operationID,
            key: sourceKey,
            cancellation: cancellation
        )
        metadataOperation = operation
        let task = Task.detached(priority: .utility) {
            let metadata = resolver.resolve(for: source, cancellation: cancellation)
            await self.finishMetadataResolution(
                metadata,
                sourceKey: sourceKey,
                operationID: operationID,
                wasCancelled: cancellation.isCancelled
            )
        }
        operation.attach(task)
        refreshRuntimeDiagnostics()
    }

    private func finishMetadataResolution(
        _ metadata: TrackMetadata?,
        sourceKey: String,
        operationID: UUID,
        wasCancelled: Bool
    ) {
        guard metadataOperation?.id == operationID else { return }
        metadataOperation = nil
        refreshRuntimeDiagnostics()
        guard !wasCancelled else { return }
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
        latestYouTubeMusicSnapshot = youtubeMusicTrack
        if sourceNowPlaying?.hasSamePresentation(as: source) != true {
            sourceNowPlaying = source
        }
        if !hasSamePresentation(youtubeMusicNowPlaying, youtubeMusicTrack) {
            youtubeMusicNowPlaying = youtubeMusicTrack
        }
        refreshSelectedMetadataOutputs()

        guard activatedTrackKey != sourceKey else { return }
        activatedTrackKey = sourceKey
        loadLyrics(for: youtubeMusicTrack ?? source, cacheKey: sourceKey)
    }

    private func refreshSelectedMetadataOutputs() {
        guard let source = latestSourceSnapshot else { return }

        let display = displayMetadataSource.select(
            youtubeMusic: latestYouTubeMusicSnapshot,
            macOS: source
        ) ?? source
        if displayNowPlaying?.hasSamePresentation(as: display) != true {
            displayNowPlaying = display
        }
        let description = trackDescription(for: display)
        if currentTrack != description {
            currentTrack = description
        }

        let discordTrack = discordMetadataSource.select(
            youtubeMusic: latestYouTubeMusicSnapshot,
            macOS: source
        ) ?? source
        lastDiscordNowPlaying = discordTrack
        if discordEnabled,
           manualDiscordPresenceSession == nil,
           !isDiscordTrackPrivate(discordTrack)
        {
            presenceController.update(
                for: discordTrack,
                sourceArtwork: nowPlayingArtwork,
                configuration: discordPresenceConfiguration
            )
        }
    }

    private func hasSamePresentation(_ lhs: NowPlaying?, _ rhs: NowPlaying?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            true
        case let (lhs?, rhs?):
            lhs.hasSamePresentation(as: rhs)
        default:
            false
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
            artworkOperation?.key != sourceKey
        else { return }

        artworkOperation?.cancel()
        let query = artworkQuery
        let operationID = UUID()
        let cancellation = CancellationToken()
        let operation = CancellableTaskOperation(
            id: operationID,
            key: sourceKey,
            cancellation: cancellation
        )
        artworkOperation = operation
        let task = Task.detached(priority: .utility) {
            let artwork = query.query(cancellation: cancellation)
            await self.finishArtworkLoad(
                artwork,
                sourceKey: sourceKey,
                operationID: operationID,
                wasCancelled: cancellation.isCancelled
            )
        }
        operation.attach(task)
        refreshRuntimeDiagnostics()
    }

    private func finishArtworkLoad(
        _ artwork: NowPlayingArtwork?,
        sourceKey: String,
        operationID: UUID,
        wasCancelled: Bool
    ) {
        guard artworkOperation?.id == operationID else { return }
        artworkOperation = nil
        refreshRuntimeDiagnostics()
        guard !wasCancelled else { return }
        guard
            currentTrackKey == sourceKey,
            latestSourceSnapshot?.trackKey == sourceKey
        else { return }

        if let artwork {
            artworkCache[sourceKey] = artwork
            nowPlayingArtwork = artwork
            if discordEnabled,
               manualDiscordPresenceSession == nil,
               let lastDiscordNowPlaying,
               !isDiscordTrackPrivate(lastDiscordNowPlaying)
            {
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
        if let custom = CustomLyricsStore.load(cacheKey) {
            applyCustomLyrics(custom)
            isFetching = false
            refreshRuntimeDiagnostics()
            return
        }
        customLyricsSourceName = nil

        if let candidates = lyricCandidateCache[cacheKey] {
            applyLyricCandidates(candidates, cacheKey: cacheKey)
            isFetching = false
            refreshRuntimeDiagnostics()
            return
        }

        if let cached = lyricsCache[cacheKey] {
            lines = cached
            isFetching = false
            lyricCandidateStatusMessage =
                "Using saved lyrics. Refresh to load the available lyric choices."
            refreshRuntimeDiagnostics()
            return
        }

        // In-memory miss → try the disk cache before fetching. A track resolved in an
        // earlier session loads instantly and offline. The source metadata key stays
        // stable even when its displayed title was replaced with the page label.
        if let disk = LyricsCache.load(cacheKey) {
            lyricsCache[cacheKey] = disk
            lines = disk
            isFetching = false
            lyricCandidateStatusMessage =
                "Using saved lyrics. Refresh to load the available lyric choices."
            refreshRuntimeDiagnostics()
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
        if lyricsOperation?.key == cacheKey { return }
        lyricsOperation?.cancel()
        isFetchingLyricCandidates = true
        lyricCandidateStatusMessage = nil
        if !preservesCurrentLines { isFetching = true }

        let operationID = UUID()
        let cancellation = CancellationToken()
        let operation = CancellableTaskOperation(
            id: operationID,
            key: cacheKey,
            cancellation: cancellation
        )
        lyricsOperation = operation
        let task = Task.detached(priority: .userInitiated) {
            let fetched = LRCLIB.fetchCandidates(
                for: track,
                cancellation: cancellation
            )
            await self.finishLyricCandidates(
                fetched,
                cacheKey: cacheKey,
                operationID: operationID,
                wasCancelled: cancellation.isCancelled
            )
        }
        operation.attach(task)
        refreshRuntimeDiagnostics()
    }

    private func finishLyricCandidates(
        _ fetched: [LyricCandidate]?,
        cacheKey: String,
        operationID: UUID,
        wasCancelled: Bool
    ) {
        guard lyricsOperation?.id == operationID else { return }
        lyricsOperation = nil
        refreshRuntimeDiagnostics()
        guard !wasCancelled, cacheKey == currentTrackKey else { return }
        isFetchingLyricCandidates = false
        guard let fetched else {
            // A transient LRCLIB failure retries only when a fresh activation or an
            // explicit Refresh asks for it; cached lyrics never trigger hidden work.
            if lines.isEmpty { activatedTrackKey = nil }
            isFetching = false
            lyricCandidateStatusMessage =
                "Couldn’t load lyric choices. Check your connection and try again."
            return
        }

        lyricCandidateCache[cacheKey] = fetched
        applyLyricCandidates(fetched, cacheKey: cacheKey)
        isFetching = false
        refreshRuntimeDiagnostics()
    }

    private func applyLyricCandidates(_ candidates: [LyricCandidate], cacheKey: String) {
        lyricCandidates = candidates
        if hasCustomLyrics {
            selectedLyricCandidateID = nil
            lyricCandidateStatusMessage =
                "Imported lyrics remain active until you choose an online version."
            return
        }
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
        lyricsDiskCacheStatistics = LyricsCache.statistics()
        lyricCandidateStatusMessage = nil
        tick()
    }

    func selectLyricCandidate(_ candidateID: String) {
        guard
            let cacheKey = currentTrackKey,
            let selected = lyricCandidates.first(where: { $0.id == candidateID })
        else { return }

        try? CustomLyricsStore.remove(for: cacheKey)
        customLyricsSourceName = nil
        preferences.selectLyricCandidate(candidateID, for: cacheKey)
        selectedLyricCandidateID = candidateID
        lyricCandidateStatusMessage = nil
        lines = selected.lines
        lyricsCache[cacheKey] = selected.lines
        LyricsCache.save(selected.lines, for: cacheKey)
        lyricsDiskCacheStatistics = LyricsCache.statistics()
        tick()
    }

    func reloadLyricCandidates() {
        guard
            let cacheKey = currentTrackKey,
            let track = youtubeMusicNowPlaying ?? sourceNowPlaying
        else { return }
        fetchLyricCandidates(for: track, cacheKey: cacheKey, preservesCurrentLines: true)
    }

    func importCustomLyrics(from url: URL) throws {
        guard let cacheKey = currentTrackKey else {
            throw LyricsFileError.noCurrentTrack
        }
        let document = try LyricsFileDocument.imported(from: url)
        try CustomLyricsStore.save(document, for: cacheKey)

        lyricsOperation?.cancel()
        lyricsOperation = nil
        isFetching = false
        isFetchingLyricCandidates = false
        applyCustomLyrics(document)
        refreshRuntimeDiagnostics()
    }

    func exportCurrentLyrics(to url: URL) throws {
        guard let track = displayNowPlaying ?? youtubeMusicNowPlaying ?? sourceNowPlaying else {
            throw LyricsFileError.noCurrentTrack
        }
        try LyricsFileDocument.write(lines: lines, track: track, to: url)
    }

    func removeCustomLyrics() throws {
        guard
            let cacheKey = currentTrackKey,
            let track = youtubeMusicNowPlaying ?? sourceNowPlaying
        else {
            throw LyricsFileError.noCurrentTrack
        }

        try CustomLyricsStore.remove(for: cacheKey)
        customLyricsSourceName = nil
        selectedLyricCandidateID = nil
        lyricCandidateStatusMessage = nil
        lines = []
        currentIndex = -1
        loadLyrics(for: track, cacheKey: cacheKey)
    }

    private func applyCustomLyrics(_ document: CustomLyricsDocument) {
        customLyricsSourceName = document.sourceName
        selectedLyricCandidateID = nil
        lyricCandidateStatusMessage =
            "Using \(document.sourceName). Imported lyrics stay on this Mac."
        lines = document.lines
        tick()
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

    func applyOverlayPreset(_ preset: OverlayPreset) {
        overlayPreset = preset
        lyricsFontSize = preset.recommendedFontSize
    }

    func resetOverlayAppearance() {
        overlayPreset = .balanced
        lyricsFontSize = OverlayPreset.balanced.recommendedFontSize
        karaokeModeEnabled = false
    }

    func resetLyricLayers() {
        showsRomanizedLyrics = false
        showsTranslatedLyrics = false
        translationTargetLanguage = .system
        translationTone = .naturalLyrics
    }

    func clearSavedLyricsCache() {
        LyricsCache.clear()
        LyricTranslationCache.clear()
        lyricsCache = LRUCache(capacity: SessionCacheLimits.lyrics)
        lyricsDiskCacheStatistics = LyricsCache.statistics()
        translationDiskCacheStatistics = LyricTranslationCache.statistics()
        refreshRuntimeDiagnostics()
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

    @discardableResult
    func publishManualDiscordPresence(_ presence: ManualDiscordPresence) -> String? {
        if let validationMessage = presence.validationMessage {
            return validationMessage
        }
        guard discordEnabled else {
            return "Turn on Discord Rich Presence first."
        }

        let startedAt = Date()
        guard let activity = presence.activity(startedAt: startedAt) else {
            return "The manual presence could not be created."
        }
        let session = ManualDiscordPresenceSession(
            presence: presence,
            startedAt: startedAt,
            expiresAt: startedAt.addingTimeInterval(presence.lifetime.interval),
            sessionKey: UUID().uuidString
        )
        manualDiscordPresenceSession = session
        scheduleManualPresenceExpiry(for: session)
        presenceController.publishManual(
            activity,
            sessionKey: session.sessionKey
        )
        return nil
    }

    func returnToLiveDiscordPresence() {
        manualPresenceTimer?.invalidate()
        manualPresenceTimer = nil
        manualDiscordPresenceSession = nil
        republishDiscordPresenceIfNeeded(clearsWhenUnavailable: true)
    }

    func setCurrentDiscordTrackPrivate(_ isPrivate: Bool) {
        guard let track = lastDiscordNowPlaying else { return }
        preferences.setDiscordTrackPrivate(
            isPrivate,
            identifier: discordPrivacyIdentifier(for: track)
        )
        objectWillChange.send()
        guard manualDiscordPresenceSession == nil else { return }
        if isPrivate {
            presenceController.clear()
        } else {
            republishDiscordPresenceIfNeeded()
        }
    }

    func clearPrivateDiscordTracks() {
        preferences.clearPrivateDiscordTracks()
        objectWillChange.send()
        republishDiscordPresenceIfNeeded()
    }

    private func republishDiscordPresenceIfNeeded(clearsWhenUnavailable: Bool = false) {
        guard discordEnabled,
              manualDiscordPresenceSession == nil,
              let lastDiscordNowPlaying,
              !isDiscordTrackPrivate(lastDiscordNowPlaying)
        else {
            if clearsWhenUnavailable {
                presenceController.clear()
            }
            return
        }
        presenceController.update(
            for: lastDiscordNowPlaying,
            sourceArtwork: nowPlayingArtwork,
            configuration: discordPresenceConfiguration
        )
    }

    private func scheduleManualPresenceExpiry(for session: ManualDiscordPresenceSession) {
        manualPresenceTimer?.invalidate()
        manualPresenceTimer = Timer.scheduledTimer(
            withTimeInterval: max(0.1, session.expiresAt.timeIntervalSinceNow),
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor in
                guard self?.manualDiscordPresenceSession?.sessionKey == session.sessionKey
                else {
                    return
                }
                self?.returnToLiveDiscordPresence()
            }
        }
    }

    private func isDiscordTrackPrivate(_ track: NowPlaying) -> Bool {
        preferences.isDiscordTrackPrivate(
            identifier: discordPrivacyIdentifier(for: track)
        )
    }

    private func discordPrivacyIdentifier(for track: NowPlaying) -> String {
        track.trackURL?.absoluteString ?? track.trackKey
    }

    /// Persist a just-finished track's correction for that track only.
    private func commit(for trackKey: String) {
        // Untouched track → leave the store alone (don't add a slot for every song
        // that merely played through).
        guard abs(syncOffset - loadedOffset) >= 0.05 else { return }

        preferences.saveTimingOffset(syncOffset, for: trackKey)
    }

    private func tick() {
        guard !lines.isEmpty else { return }
        let t = virtualElapsed + leadTime + syncOffset
        let idx = LyricTimeline.index(at: t, in: lines)
        // Let the view's .animation(value: currentIndex) drive the motion.
        if idx != currentIndex { currentIndex = idx }
    }

    private func updateTickTimerState() {
        guard isStarted else {
            tickTimer?.invalidate()
            tickTimer = nil
            return
        }
        let shouldTick = overlayEnabled && isPlaying && !lines.isEmpty
        if shouldTick, tickTimer == nil {
            tickTimer = Timer.scheduledTimer(
                withTimeInterval: 0.08,
                repeats: true
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            tick()
        } else if !shouldTick {
            tickTimer?.invalidate()
            tickTimer = nil
        }
    }

    private func cancelTrackOperations() {
        metadataOperation?.cancel()
        artworkOperation?.cancel()
        lyricsOperation?.cancel()
        romanizationTask?.cancel()
        metadataOperation = nil
        artworkOperation = nil
        lyricsOperation = nil
        romanizationTask = nil
        romanizationRequestID = UUID()
        lyricTranslationRequest = nil
        isFetchingLyricCandidates = false
        refreshRuntimeDiagnostics()
    }

    private func refreshLyricLayers() {
        refreshRomanizedLyrics()
        refreshTranslationLayer()
    }

    private func refreshRomanizedLyrics() {
        defer { refreshRuntimeDiagnostics() }
        romanizationTask?.cancel()
        romanizationTask = nil
        romanizationRequestID = UUID()

        guard showsRomanizedLyrics, !lines.isEmpty else {
            romanizedLines = []
            return
        }

        let requestID = romanizationRequestID
        let source = lines
        let candidates = lyricCandidates
        romanizationTask = Task.detached(priority: .utility) { [weak self] in
            guard !Task.isCancelled else { return }
            let language = LyricRomanizer.detectedLanguage(in: source)
            let result = LyricRomanizer.romanizedLines(
                source,
                candidates: candidates,
                sourceLanguage: language
            )
            guard !Task.isCancelled else { return }
            await self?.finishRomanization(
                result,
                source: source,
                requestID: requestID
            )
        }
    }

    private func finishRomanization(
        _ result: [String],
        source: [LyricLine],
        requestID: UUID
    ) {
        guard
            requestID == romanizationRequestID,
            source == lines,
            showsRomanizedLyrics
        else { return }
        romanizationTask = nil
        romanizedLines = result.contains(where: { !$0.isEmpty }) ? result : []
        refreshRuntimeDiagnostics()
    }

    private func refreshTranslationLayer() {
        defer { refreshRuntimeDiagnostics() }
        lyricTranslationRequest = nil
        translatedLines = []

        guard showsTranslatedLyrics else {
            lyricTranslationStatus = .disabled
            return
        }
        guard #available(macOS 15.0, *) else {
            lyricTranslationStatus = .unavailable
            return
        }
        guard let trackKey = currentTrackKey, !lines.isEmpty else {
            lyricTranslationStatus = .waiting
            return
        }

        let target = translationTargetLanguage.resolvedIdentifier
        if sourceLanguageMatchesTarget(target) {
            lyricTranslationStatus = .ready
            return
        }
        if let cached = LyricTranslationCache.load(
            for: trackKey,
            targetLanguage: target,
            tone: translationTone,
            sourceLines: lines
        ) {
            translatedLines = cached
            lyricTranslationStatus = .ready
            return
        }

        lyricTranslationStatus = .waiting
        lyricTranslationRequest = LyricTranslationRequest(
            id: UUID(),
            trackKey: trackKey,
            targetLanguage: target,
            tone: translationTone,
            sourceLines: lines
        )
    }

    private func sourceLanguageMatchesTarget(_ target: String) -> Bool {
        guard let source = LyricRomanizer.detectedLanguage(in: lines)?.rawValue
        else { return false }
        let sourceCode = source.split(separator: "-").first?.lowercased()
        let targetCode = target.split(separator: "-").first?.lowercased()
        return sourceCode == targetCode
    }

    @available(macOS 15.0, *)
    func translateLyrics(
        using session: TranslationSession,
        request: LyricTranslationRequest
    ) async {
        guard request == lyricTranslationRequest, showsTranslatedLyrics else { return }
        defer { refreshRuntimeDiagnostics() }
        lyricTranslationStatus = .translating

        let sourceTexts = request.sourceLines.compactMap { line -> String? in
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : line.text
        }
        guard !sourceTexts.isEmpty else {
            translatedLines = Array(repeating: "", count: request.sourceLines.count)
            lyricTranslationStatus = .ready
            lyricTranslationRequest = nil
            return
        }

        do {
            let contextualLines: [String]?
            do {
                let contextualResponse = try await session.translate(
                    sourceTexts.joined(separator: "\n")
                )
                contextualLines =
                    LyricTranslationResultAssembler.contextualNonemptyLines(
                        contextualResponse.targetText,
                        expectedCount: sourceTexts.count
                    )
            } catch is CancellationError {
                return
            } catch {
                // Very long songs can exceed a contextual request even though
                // each line remains translatable. The per-line path below keeps
                // translation available in that case.
                contextualLines = nil
            }
            guard request == lyricTranslationRequest, showsTranslatedLyrics else {
                return
            }

            let rawTranslations: [String]
            if let contextualLines {
                rawTranslations = contextualLines
            } else {
                let translationRequests = sourceTexts.enumerated().map {
                    TranslationSession.Request(
                        sourceText: $0.element,
                        clientIdentifier: String($0.offset)
                    )
                }
                let responses = try await session.translations(from: translationRequests)
                rawTranslations = responses.sorted {
                    let lhs = Int($0.clientIdentifier ?? "") ?? .max
                    let rhs = Int($1.clientIdentifier ?? "") ?? .max
                    return lhs < rhs
                }
                .map(\.targetText)
            }
            guard request == lyricTranslationRequest, showsTranslatedLyrics else { return }

            let styledTranslations = LyricTranslationStyler.styled(
                rawTranslations,
                targetLanguage: request.targetLanguage,
                tone: request.tone
            )
            let aligned = LyricTranslationResultAssembler.alignedLines(
                source: request.sourceLines,
                translatedNonemptyLines: styledTranslations
            )
            translatedLines = aligned.contains(where: { !$0.isEmpty }) ? aligned : []
            lyricTranslationStatus = .ready
            lyricTranslationRequest = nil

            Task.detached(priority: .utility) { [weak self] in
                LyricTranslationCache.save(
                    aligned,
                    for: request.trackKey,
                    targetLanguage: request.targetLanguage,
                    tone: request.tone,
                    sourceLines: request.sourceLines
                )
                let statistics = LyricTranslationCache.statistics()
                await self?.updateTranslationCacheStatistics(statistics)
            }
        } catch is CancellationError {
            return
        } catch {
            guard request == lyricTranslationRequest else { return }
            lyricTranslationStatus = .failed(error.localizedDescription)
            lyricTranslationRequest = nil
        }
    }

    private func updateTranslationCacheStatistics(
        _ statistics: LyricsCacheStatistics
    ) {
        translationDiskCacheStatistics = statistics
    }

    private func refreshRuntimeDiagnostics() {
        var activeOperations: [String] = []
        if pollOperation != nil { activeOperations.append("Now Playing") }
        if metadataOperation != nil { activeOperations.append("Metadata") }
        if artworkOperation != nil { activeOperations.append("Artwork") }
        if lyricsOperation != nil { activeOperations.append("Lyrics") }
        if romanizationTask != nil { activeOperations.append("Romanization") }
        if lyricTranslationRequest != nil { activeOperations.append("Translation") }

        runtimeDiagnostics.activeOperations = activeOperations
        runtimeDiagnostics.subprocesses = SubprocessRunner.metrics
        runtimeDiagnostics.metadataCacheEntries = metadataCache.count
        runtimeDiagnostics.artworkCacheEntries = artworkCache.count
        runtimeDiagnostics.lyricsCacheEntries = lyricsCache.count
        runtimeDiagnostics.lyricCandidateCacheEntries = lyricCandidateCache.count
        runtimeDiagnostics.discordStatus = discordConnectionStatus
    }

    private func clampedElapsed(_ elapsed: Double, duration: Double) -> Double {
        guard duration > 0 else { return max(0, elapsed) }
        return min(duration, max(0, elapsed))
    }
}
