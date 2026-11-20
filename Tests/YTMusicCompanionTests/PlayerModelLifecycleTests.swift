import XCTest
import Combine
@testable import YTMusicCompanion

@MainActor
final class PlayerModelLifecycleTests: XCTestCase {
    func testDiscordPresenceIsDisabledWhenNoPreferenceIsSaved() {
        let suiteName = "PlayerModelDiscordDefaultTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let model = PlayerModel(
            presenceController: DiscordPresenceController(
                publisher: LifecyclePresencePublisher()
            ),
            defaults: defaults
        )

        XCTAssertFalse(model.discordEnabled)
        XCTAssertNil(defaults.object(forKey: "discordEnabled"))
    }

    func testDiscordPresenceUsesSavedEnabledPreference() {
        let suiteName = "PlayerModelDiscordEnabledTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: "discordEnabled")

        let model = PlayerModel(
            presenceController: DiscordPresenceController(
                publisher: LifecyclePresencePublisher()
            ),
            defaults: defaults
        )

        XCTAssertTrue(model.discordEnabled)
    }

    func testDiscordPresenceUsesSavedDisabledPreference() {
        let suiteName = "PlayerModelDiscordDisabledTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(false, forKey: "discordEnabled")

        let model = PlayerModel(
            presenceController: DiscordPresenceController(
                publisher: LifecyclePresencePublisher()
            ),
            defaults: defaults
        )

        XCTAssertFalse(model.discordEnabled)
    }

    func testStartIsIdempotentAndStopCancelsTheActivePoll() {
        let started = expectation(description: "poll started")
        let cancelled = expectation(description: "poll cancelled")
        let query = BlockingNowPlayingQuery(started: started, cancelled: cancelled)
        let suiteName = "PlayerModelLifecycleTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = PlayerModel(
            presenceController: DiscordPresenceController(
                publisher: LifecyclePresencePublisher()
            ),
            nowPlayingQuery: query,
            defaults: defaults
        )

        model.start()
        model.start()
        wait(for: [started], timeout: 1)
        model.stop()
        wait(for: [cancelled], timeout: 1)

        XCTAssertEqual(query.callCount, 1)
        XCTAssertTrue(model.runtimeDiagnostics.activeOperations.isEmpty)
    }

    func testStopReleasesModelWhileANonCooperativePollIsStillBlocked() {
        let started = expectation(description: "non-cooperative poll started")
        let query = NonCooperativeNowPlayingQuery(started: started)
        let suiteName = "PlayerModelRetentionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            query.release()
            defaults.removePersistentDomain(forName: suiteName)
        }
        weak var weakModel: PlayerModel?
        var model: PlayerModel? = PlayerModel(
            presenceController: DiscordPresenceController(
                publisher: LifecyclePresencePublisher()
            ),
            nowPlayingQuery: query,
            defaults: defaults
        )
        weakModel = model

        model?.start()
        wait(for: [started], timeout: 1)
        model?.stop()
        model = nil

        XCTAssertNil(weakModel)
    }

    func testUnchangedRuntimeDiagnosticsAreNotRepublished() {
        let suiteName = "PlayerModelDiagnosticsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = PlayerModel(
            presenceController: DiscordPresenceController(
                publisher: LifecyclePresencePublisher()
            ),
            defaults: defaults
        )
        model.clearSavedLyricsCache()
        var publicationCount = 0
        let observation = model.$runtimeDiagnostics
            .dropFirst()
            .sink { _ in publicationCount += 1 }

        model.clearSavedLyricsCache()

        withExtendedLifetime(observation) {}
        XCTAssertEqual(publicationCount, 0)
    }

    func testTrackChangeCancelsThePreviousMetadataLookup() {
        let firstLookupStarted = expectation(description: "first metadata lookup started")
        let firstLookupCancelled = expectation(description: "first metadata lookup cancelled")
        let first = track(title: "First")
        let second = track(title: "Second")
        let query = SequenceNowPlayingQuery(tracks: [first, second])
        let resolver = BlockingMetadataResolver(
            blockedTitle: first.title,
            started: firstLookupStarted,
            cancelled: firstLookupCancelled
        )
        let suiteName = "PlayerModelTrackChangeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(suiteName, isDirectory: true)
        LyricsCache.overrideDirectory = tempDirectory
        LyricsCache.save([LyricLine(time: 0, text: "cached")], for: second.trackKey)
        defer {
            LyricsCache.overrideDirectory = nil
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let model = PlayerModel(
            presenceController: DiscordPresenceController(
                publisher: LifecyclePresencePublisher()
            ),
            metadataResolver: resolver,
            nowPlayingQuery: query,
            artworkQuery: EmptyArtworkQuery(),
            defaults: defaults
        )

        model.start()
        wait(for: [firstLookupStarted, firstLookupCancelled], timeout: 2)
        model.stop()

        XCTAssertGreaterThanOrEqual(query.callCount, 2)
        XCTAssertTrue(resolver.cancelledTitles.contains(first.title))
    }

    func testCustomLyricsTakePriorityAndCanRestoreSavedOnlineLyrics() throws {
        let current = track(title: "Pinned")
        let suiteName = "PlayerModelCustomLyricsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(suiteName, isDirectory: true)
        LyricsCache.overrideDirectory = tempDirectory.appendingPathComponent("cache")
        CustomLyricsStore.overrideDirectory = tempDirectory.appendingPathComponent("custom")
        LyricsCache.save(
            [LyricLine(time: 0, text: "online")],
            for: current.trackKey
        )
        try CustomLyricsStore.save(
            CustomLyricsDocument(
                sourceName: "pinned.lrc",
                lines: [LyricLine(time: 0, text: "custom")]
            ),
            for: current.trackKey
        )
        defer {
            LyricsCache.overrideDirectory = nil
            CustomLyricsStore.overrideDirectory = nil
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let model = PlayerModel(
            presenceController: DiscordPresenceController(
                publisher: LifecyclePresencePublisher()
            ),
            metadataResolver: ImmediateMetadataResolver(),
            nowPlayingQuery: SequenceNowPlayingQuery(tracks: [current]),
            artworkQuery: EmptyArtworkQuery(),
            defaults: defaults
        )
        let loaded = expectation(description: "custom lyrics loaded")
        model.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            XCTAssertEqual(model.lines.first?.text, "custom")
            XCTAssertEqual(model.customLyricsSourceName, "pinned.lrc")
            loaded.fulfill()
        }
        wait(for: [loaded], timeout: 1)

        try model.removeCustomLyrics()

        XCTAssertEqual(model.lines.first?.text, "online")
        XCTAssertNil(model.customLyricsSourceName)
        XCTAssertNil(CustomLyricsStore.load(current.trackKey))
        model.stop()
    }

    func testRomanizationPublishesOnlyTheNewestLyricSnapshot() {
        let suiteName = "PlayerModelRomanizationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = PlayerModel(
            presenceController: DiscordPresenceController(
                publisher: LifecyclePresencePublisher()
            ),
            defaults: defaults
        )

        model.showsRomanizedLyrics = true
        model.lines = [LyricLine(time: 0, text: "안녕하세요")]
        model.lines = [LyricLine(time: 0, text: "Привет мир")]

        let newestResult = expectation(description: "newest romanization published")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            XCTAssertEqual(model.romanizedLines, ["Privet mir"])
            newestResult.fulfill()
        }
        wait(for: [newestResult], timeout: 1)
    }

    func testResetLyricLayersReturnsToOriginalOnlyAndPersists() {
        let suiteName = "PlayerModelLayerResetTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = PlayerModel(
            presenceController: DiscordPresenceController(
                publisher: LifecyclePresencePublisher()
            ),
            defaults: defaults
        )
        model.showsRomanizedLyrics = true
        model.showsTranslatedLyrics = true
        model.translationTargetLanguage = .korean
        model.translationTone = .system

        model.resetLyricLayers()

        XCTAssertFalse(model.showsRomanizedLyrics)
        XCTAssertFalse(model.showsTranslatedLyrics)
        XCTAssertEqual(model.translationTargetLanguage, .system)
        XCTAssertEqual(model.translationTone, .naturalLyrics)
        let restored = CompanionPreferences(defaults: defaults)
        XCTAssertFalse(restored.showsRomanizedLyrics)
        XCTAssertFalse(restored.showsTranslatedLyrics)
        XCTAssertEqual(restored.translationTargetLanguage, .system)
        XCTAssertEqual(restored.translationTone, .naturalLyrics)
    }

    func testManualDiscordPresencePublishesAndReturnsToLiveWithoutPersistence() throws {
        let suiteName = "PlayerModelManualPresenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: "discordEnabled")
        let publisher = RecordingLifecyclePresencePublisher()
        let model = PlayerModel(
            presenceController: DiscordPresenceController(publisher: publisher),
            defaults: defaults
        )
        var weeklyConfiguration = DiscordPresenceConfiguration.standard
        weeklyConfiguration.showsWeeklyArtistCount = true
        model.applyDiscordPresenceConfiguration(weeklyConfiguration)

        XCTAssertNil(model.publishManualDiscordPresence(.example))
        let session = try XCTUnwrap(model.manualDiscordPresenceSession)
        XCTAssertEqual(publisher.activities.last?.details, ManualDiscordPresence.example.title)
        XCTAssertGreaterThan(session.expiresAt, session.startedAt)
        XCTAssertNil(defaults.data(forKey: "weeklyListeningSnapshot"))

        model.returnToLiveDiscordPresence()

        XCTAssertNil(model.manualDiscordPresenceSession)
        XCTAssertEqual(publisher.clearCount, 1)

        let restored = PlayerModel(
            presenceController: DiscordPresenceController(
                publisher: RecordingLifecyclePresencePublisher()
            ),
            defaults: defaults
        )
        XCTAssertNil(restored.manualDiscordPresenceSession)
    }

    func testInvalidManualDiscordPresenceNeverStartsASession() {
        let suiteName = "PlayerModelInvalidManualPresenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let publisher = RecordingLifecyclePresencePublisher()
        let model = PlayerModel(
            presenceController: DiscordPresenceController(publisher: publisher),
            defaults: defaults
        )
        var invalid = ManualDiscordPresence.example
        invalid.songURL = "http://example.com/song"

        XCTAssertNotNil(model.publishManualDiscordPresence(invalid))
        XCTAssertNil(model.manualDiscordPresenceSession)
        XCTAssertTrue(publisher.activities.isEmpty)
    }

    func testWeeklySummaryCountsLocalPlaybackBeforeSharingAndDropsHiddenTrack() {
        let suiteName = "PlayerModelWeeklySummaryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let current = track(title: "First")
        let publisher = RecordingLifecyclePresencePublisher()
        let model = PlayerModel(
            presenceController: DiscordPresenceController(publisher: publisher),
            metadataResolver: ImmediateMetadataResolver(),
            nowPlayingQuery: SequenceNowPlayingQuery(tracks: [current]),
            artworkQuery: EmptyArtworkQuery(),
            defaults: defaults
        )
        model.appLanguage = .english
        var configuration = DiscordPresenceConfiguration.standard
        configuration.showsWeeklyArtistCount = true
        model.applyDiscordPresenceConfiguration(configuration)
        model.start()

        let checked = expectation(description: "local weekly count and privacy")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            XCTAssertEqual(model.discordPreviewWeeklyArtistCount, 1)
            XCTAssertTrue(publisher.activities.isEmpty)

            model.discordEnabled = true
            XCTAssertEqual(publisher.activities.last?.state, "Artist · 1 song this week")

            model.setCurrentDiscordTrackPrivate(true)
            XCTAssertNil(model.discordPreviewWeeklyArtistCount)
            XCTAssertEqual(WeeklyListeningStore(defaults: defaults).count(for: current), 0)
            XCTAssertEqual(model.privateDiscordTrackCount, 1)

            model.setCurrentDiscordTrackPrivate(false)
            XCTAssertEqual(model.discordPreviewWeeklyArtistCount, 1)
            XCTAssertEqual(model.privateDiscordTrackCount, 0)

            configuration.showsWeeklyArtistCount = false
            model.applyDiscordPresenceConfiguration(configuration)
            XCTAssertEqual(WeeklyListeningStore(defaults: defaults).count(for: current), 0)
            XCTAssertEqual(publisher.activities.last?.state, "Artist")
            model.stop()
            checked.fulfill()
        }
        wait(for: [checked], timeout: 2)
    }

    func testWeeklySummaryUsesCanonicalSourceArtistWithEnrichedScreenLabels() {
        let suiteName = "PlayerModelWeeklyArtistAliasTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let source = track(title: "Source Song")
        let publisher = RecordingLifecyclePresencePublisher()
        let model = PlayerModel(
            presenceController: DiscordPresenceController(publisher: publisher),
            metadataResolver: FixedMetadataResolver(metadata: TrackMetadata(
                title: "Screen Song", artist: "Screen Artist", album: "Screen Album"
            )),
            nowPlayingQuery: SequenceNowPlayingQuery(tracks: [source]),
            artworkQuery: EmptyArtworkQuery(),
            defaults: defaults
        )
        model.appLanguage = .english
        var configuration = DiscordPresenceConfiguration.standard
        configuration.showsWeeklyArtistCount = true
        model.applyDiscordPresenceConfiguration(configuration)
        model.discordEnabled = true
        model.start()

        let checked = expectation(description: "screen label and source weekly bucket")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            XCTAssertEqual(publisher.activities.last?.details, "Screen Song")
            XCTAssertEqual(publisher.activities.last?.name, "Screen Song - Screen Artist")
            XCTAssertEqual(publisher.activities.last?.state, "Artist · 1 song this week")
            XCTAssertEqual(model.discordPreviewWeeklyArtistCount, 1)
            XCTAssertEqual(WeeklyListeningStore(defaults: defaults).count(for: source), 1)
            model.stop()
            checked.fulfill()
        }
        wait(for: [checked], timeout: 2)
    }

    func testLegacyURLOnlyPrivacyDefersUnresolvedSongAndMigratesExactMatch() {
        let suiteName = "PlayerModelLegacyDiscordPrivacyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let url = URL(string: "https://music.youtube.com/watch?v=private-song")!
        var preferences = CompanionPreferences(defaults: defaults)
        preferences.setDiscordTrackPrivate(true, identifier: url.absoluteString)
        let current = track(title: "Private Song")
        var configuration = DiscordPresenceConfiguration.standard
        configuration.showsWeeklyArtistCount = true

        let unresolvedPublisher = RecordingLifecyclePresencePublisher()
        let unresolved = PlayerModel(
            presenceController: DiscordPresenceController(publisher: unresolvedPublisher),
            metadataResolver: ImmediateMetadataResolver(),
            nowPlayingQuery: SequenceNowPlayingQuery(tracks: [current]),
            artworkQuery: EmptyArtworkQuery(),
            defaults: defaults
        )
        unresolved.applyDiscordPresenceConfiguration(configuration)
        unresolved.discordEnabled = true
        unresolved.start()

        let checkedUnresolved = expectation(description: "unknown legacy URL stays private")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            XCTAssertTrue(unresolvedPublisher.activities.isEmpty)
            XCTAssertNil(unresolved.discordPreviewWeeklyArtistCount)
            XCTAssertEqual(WeeklyListeningStore(defaults: defaults).count(for: current), 0)
            unresolved.stop()
            checkedUnresolved.fulfill()
        }
        wait(for: [checkedUnresolved], timeout: 2)

        let resolvedPublisher = RecordingLifecyclePresencePublisher()
        let resolved = PlayerModel(
            presenceController: DiscordPresenceController(publisher: resolvedPublisher),
            metadataResolver: FixedMetadataResolver(metadata: TrackMetadata(
                title: current.title, artist: current.artist, album: current.album,
                trackURL: url
            )),
            nowPlayingQuery: SequenceNowPlayingQuery(tracks: [current]),
            artworkQuery: EmptyArtworkQuery(),
            defaults: defaults
        )
        resolved.discordEnabled = true
        resolved.start()

        let checkedResolved = expectation(description: "exact URL stays hidden after migration")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            XCTAssertTrue(resolvedPublisher.activities.isEmpty)
            XCTAssertNil(resolved.discordPreviewWeeklyArtistCount)
            XCTAssertEqual(resolved.privateDiscordTrackCount, 1)
            XCTAssertFalse(CompanionPreferences(defaults: defaults).hasUnboundDiscordPrivateTracks)
            XCTAssertTrue(CompanionPreferences(defaults: defaults).isDiscordTrackPrivate(
                identifier: url.absoluteString
            ))
            resolved.stop()
            checkedResolved.fulfill()
        }
        wait(for: [checkedResolved], timeout: 2)

        let publicPublisher = RecordingLifecyclePresencePublisher()
        let publicTrack = track(title: "Unrelated Public Song")
        let publicModel = PlayerModel(
            presenceController: DiscordPresenceController(publisher: publicPublisher),
            metadataResolver: ImmediateMetadataResolver(),
            nowPlayingQuery: SequenceNowPlayingQuery(tracks: [publicTrack]),
            artworkQuery: EmptyArtworkQuery(),
            defaults: defaults
        )
        publicModel.discordEnabled = true
        publicModel.start()
        let checkedPublic = expectation(description: "known private song does not block another song")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            XCTAssertEqual(publicPublisher.activities.last?.details, "Unrelated Public Song")
            XCTAssertEqual(publicPublisher.activities.last?.name,
                           "Unrelated Public Song - Artist")
            XCTAssertEqual(publicModel.discordPreviewWeeklyArtistCount, 1)
            publicModel.stop()
            checkedPublic.fulfill()
        }
        wait(for: [checkedPublic], timeout: 2)
    }

    func testOverlayPresetAppliesRecommendedSizeAndCanResetAppearance() {
        let suiteName = "PlayerModelOverlayAppearanceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = PlayerModel(
            presenceController: DiscordPresenceController(
                publisher: LifecyclePresencePublisher()
            ),
            defaults: defaults
        )

        model.applyOverlayPreset(.focused)
        model.karaokeModeEnabled = true

        XCTAssertEqual(model.overlayPreset, .focused)
        XCTAssertEqual(model.lyricsFontSize, 36)
        XCTAssertTrue(model.karaokeModeEnabled)

        model.resetOverlayAppearance()

        XCTAssertEqual(model.overlayPreset, .balanced)
        XCTAssertEqual(model.lyricsFontSize, 30)
        XCTAssertFalse(model.karaokeModeEnabled)
    }

    private func track(title: String) -> NowPlaying {
        NowPlaying(
            title: title,
            artist: "Artist",
            album: "Album",
            duration: 180,
            elapsed: 10,
            timestamp: Date().timeIntervalSince1970,
            isPlaying: true,
            rate: 1,
            sourceBundle: "com.google.Chrome.app.cinhimbnkkaeohfgghhklpknlkffjgod",
            sourcePID: 0
        )
    }
    func testSongLinkAppearsWhenTheSameTrackGainsAWatchURL() {
        let suiteName = "PlayerModelSongLinkRetryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let source = track(title: "Source Song")
        let url = URL(string: "https://music.youtube.com/watch?v=abc123")!
        let resolver = LinkAfterPlayerPageMetadataResolver(url: url)
        let publisher = RecordingLifecyclePresencePublisher()
        let model = PlayerModel(
            presenceController: DiscordPresenceController(publisher: publisher),
            metadataResolver: resolver,
            nowPlayingQuery: SequenceNowPlayingQuery(tracks: [source]),
            artworkQuery: EmptyArtworkQuery(),
            defaults: defaults,
            metadataRetryInterval: 0
        )
        model.discordEnabled = true
        model.start()
        defer { model.stop() }

        wait(for: [resolver.secondResolution], timeout: 4)
        let published = expectation(description: "same-track link republished")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            XCTAssertNil(publisher.activities.first?.detailsURL)
            XCTAssertEqual(publisher.activities.last?.detailsURL, url)
            XCTAssertEqual(model.discordPreviewTrack?.trackURL, url)
            published.fulfill()
        }
        wait(for: [published], timeout: 2)
    }
}

private struct ImmediateMetadataResolver: TrackMetadataResolving {
    func resolve(for track: NowPlaying) -> TrackMetadata? {
        track.metadata
    }
}

private final class BlockingNowPlayingQuery: NowPlayingQuerying, @unchecked Sendable {
    private let lock = NSLock()
    private let started: XCTestExpectation
    private let cancelled: XCTestExpectation
    private var calls = 0

    init(started: XCTestExpectation, cancelled: XCTestExpectation) {
        self.started = started
        self.cancelled = cancelled
    }

    var callCount: Int {
        lock.withLock { calls }
    }

    func query(cancellation: CancellationToken) -> NowPlaying? {
        lock.withLock { calls += 1 }
        started.fulfill()

        let semaphore = DispatchSemaphore(value: 0)
        let registration = cancellation.register { [cancelled] in
            cancelled.fulfill()
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 5)
        registration.invalidate()
        return nil
    }
}

private final class NonCooperativeNowPlayingQuery: NowPlayingQuerying, @unchecked Sendable {
    private let started: XCTestExpectation
    private let semaphore = DispatchSemaphore(value: 0)

    init(started: XCTestExpectation) {
        self.started = started
    }

    func query(cancellation: CancellationToken) -> NowPlaying? {
        started.fulfill()
        semaphore.wait()
        return nil
    }

    func release() {
        semaphore.signal()
    }
}

private final class LifecyclePresencePublisher: PresencePublishing {
    let isConfigured = true

    func setActivity(_ activity: PresenceActivity, completion: ((Bool) -> Void)?) {
        completion?(true)
    }

    func clear() {}
    func disconnect() {}

}

private final class RecordingLifecyclePresencePublisher: PresencePublishing {
    let isConfigured = true
    private(set) var activities: [PresenceActivity] = []
    private(set) var clearCount = 0

    func setActivity(_ activity: PresenceActivity, completion: ((Bool) -> Void)?) {
        activities.append(activity)
        completion?(true)
    }

    func clear() {
        clearCount += 1
    }

    func disconnect() {}
}

private final class SequenceNowPlayingQuery: NowPlayingQuerying, @unchecked Sendable {
    private let lock = NSLock()
    private let tracks: [NowPlaying]
    private var calls = 0

    init(tracks: [NowPlaying]) {
        self.tracks = tracks
    }

    var callCount: Int {
        lock.withLock { calls }
    }

    func query(cancellation: CancellationToken) -> NowPlaying? {
        lock.withLock {
            let index = min(calls, tracks.count - 1)
            calls += 1
            return tracks[index]
        }
    }
}

private struct FixedMetadataResolver: TrackMetadataResolving {
    let metadata: TrackMetadata

    func resolve(for track: NowPlaying) -> TrackMetadata? { metadata }
}

private final class LinkAfterPlayerPageMetadataResolver: TrackMetadataResolving, @unchecked Sendable {
    let secondResolution = XCTestExpectation(description: "watch URL resolved")
    private let lock = NSLock()
    private let url: URL
    private var calls = 0

    init(url: URL) { self.url = url }

    func resolve(for track: NowPlaying) -> TrackMetadata? {
        let call = lock.withLock { () -> Int in
            calls += 1
            return calls
        }
        if call == 2 { secondResolution.fulfill() }
        return TrackMetadata(
            title: "Screen Song",
            artist: "Screen Artist",
            album: "Screen Album",
            trackURL: call == 1 ? nil : url
        )
    }
}

private final class BlockingMetadataResolver: TrackMetadataResolving, @unchecked Sendable {
    private let lock = NSLock()
    private let blockedTitle: String
    private let started: XCTestExpectation
    private let cancelled: XCTestExpectation
    private var cancelledValues: Set<String> = []

    init(
        blockedTitle: String,
        started: XCTestExpectation,
        cancelled: XCTestExpectation
    ) {
        self.blockedTitle = blockedTitle
        self.started = started
        self.cancelled = cancelled
    }

    var cancelledTitles: Set<String> {
        lock.withLock { cancelledValues }
    }

    func resolve(for track: NowPlaying) -> TrackMetadata? {
        track.metadata
    }

    func resolve(for track: NowPlaying, cancellation: CancellationToken) -> TrackMetadata? {
        guard track.title == blockedTitle else { return track.metadata }

        started.fulfill()
        let semaphore = DispatchSemaphore(value: 0)
        let registration = cancellation.register { [weak self, cancelled] in
            _ = self?.lock.withLock { self?.cancelledValues.insert(track.title) }
            cancelled.fulfill()
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 5)
        registration.invalidate()
        return nil
    }
}

private struct EmptyArtworkQuery: NowPlayingArtworkQuerying {
    func query() -> NowPlayingArtwork? { nil }

    func query(cancellation: CancellationToken) -> NowPlayingArtwork? {
        nil
    }
}
