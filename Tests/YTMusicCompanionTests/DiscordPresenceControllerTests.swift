import XCTest
@testable import YTMusicCompanion

@MainActor
final class DiscordPresenceControllerTests: XCTestCase {
    func testFailedPublicationIsRetriedForTheSameTrack() {
        let publisher = StubPublisher()
        let controller = DiscordPresenceController(
            publisher: publisher,
            artworkResolver: StubArtworkResolver()
        )
        let track = makeTrack()

        controller.update(for: track)
        XCTAssertEqual(publisher.activities.count, 1)

        publisher.completeNext(with: false)
        drainMainQueue()
        controller.update(for: track)

        XCTAssertEqual(publisher.activities.count, 2)
    }

    func testSuccessfulPublicationDeduplicatesTheSameTrack() {
        let publisher = StubPublisher()
        let controller = DiscordPresenceController(
            publisher: publisher,
            artworkResolver: StubArtworkResolver()
        )
        let track = makeTrack()

        controller.update(for: track)
        publisher.completeNext(with: true)
        drainMainQueue()
        controller.update(for: track)

        XCTAssertEqual(publisher.activities.count, 1)
    }

    func testClearRemovesPublishedPresence() {
        let publisher = StubPublisher()
        let controller = DiscordPresenceController(
            publisher: publisher,
            artworkResolver: StubArtworkResolver()
        )

        controller.update(for: makeTrack())
        publisher.completeNext(with: true)
        drainMainQueue()
        controller.clear()

        XCTAssertEqual(publisher.clearCount, 1)
    }

    func testClearAlsoCancelsAnInFlightPublication() {
        let publisher = StubPublisher()
        let controller = DiscordPresenceController(
            publisher: publisher,
            artworkResolver: StubArtworkResolver()
        )

        controller.update(for: makeTrack())
        controller.clear()

        XCTAssertEqual(publisher.clearCount, 1)
    }

    func testMissingSourceArtworkNeverStartsAnUnverifiedCoverLookup() {
        let publisher = StubPublisher()
        let resolver = CountingArtworkResolver()
        let controller = DiscordPresenceController(
            publisher: publisher,
            artworkResolver: resolver
        )

        controller.update(for: makeTrack(), sourceArtwork: nil)

        XCTAssertEqual(resolver.callCount, 0)
        XCTAssertEqual(publisher.activities.first?.largeImage, YouTubeMusicSource.discordAssetKey)
    }

    func testCustomTextAndHiddenPlaybackTimeArePublished() {
        let publisher = StubPublisher()
        let controller = DiscordPresenceController(
            publisher: publisher,
            artworkResolver: StubArtworkResolver()
        )
        let configuration = DiscordPresenceConfiguration(
            detailsTemplate: "Listening: {title}",
            stateTemplate: "{artist} — {album}",
            imageTextTemplate: "Cover: {album}",
            showsPlaybackTime: false,
            showsSongLink: false
        )

        controller.update(for: makeTrack(), configuration: configuration)

        XCTAssertEqual(publisher.activities.first?.details, "Listening: Test Song")
        XCTAssertEqual(publisher.activities.first?.state, "Test Artist — Test Album")
        XCTAssertEqual(publisher.activities.first?.largeImageText, "Cover: Test Album")
        XCTAssertNil(publisher.activities.first?.start)
        XCTAssertNil(publisher.activities.first?.end)
        XCTAssertEqual(publisher.activities.first?.buttons, [])
    }

    func testChangingCustomizationRepublishesTheSameTrack() {
        let publisher = StubPublisher()
        let controller = DiscordPresenceController(
            publisher: publisher,
            artworkResolver: StubArtworkResolver()
        )
        let track = makeTrack()

        controller.update(for: track, configuration: .standard)
        publisher.completeNext(with: true)
        drainMainQueue()
        var customized = DiscordPresenceConfiguration.standard
        customized.detailsTemplate = "🎵 {title}"
        controller.update(for: track, configuration: customized)

        XCTAssertEqual(publisher.activities.count, 2)
        XCTAssertEqual(publisher.activities.last?.details, "🎵 Test Song")
    }

    func testPublishesTheExactYouTubeMusicSongLink() {
        let publisher = StubPublisher()
        let controller = DiscordPresenceController(
            publisher: publisher,
            artworkResolver: StubArtworkResolver()
        )
        var track = makeTrack()
        track.trackURL = URL(string: "https://music.youtube.com/watch?v=abc123")

        controller.update(for: track)

        XCTAssertEqual(
            publisher.activities.first?.buttons,
            [
                PresenceButton(
                    label: "Listen on YouTube Music",
                    url: URL(string: "https://music.youtube.com/watch?v=abc123")!
                ),
            ]
        )
        XCTAssertEqual(
            publisher.activities.first?.largeImageURL,
            URL(string: "https://music.youtube.com/watch?v=abc123")
        )
    }

    func testPausedTrackUsesTheConfiguredVisibilityPolicy() {
        let hiddenPublisher = StubPublisher()
        let hiddenController = DiscordPresenceController(
            publisher: hiddenPublisher,
            artworkResolver: StubArtworkResolver()
        )
        var playing = makeTrack()
        hiddenController.update(for: playing)
        hiddenPublisher.completeNext(with: true)
        drainMainQueue()

        playing.isPlaying = false
        playing.rate = 0
        var hiddenConfiguration = DiscordPresenceConfiguration.standard
        hiddenConfiguration.pausePolicy = .hideImmediately
        hiddenController.update(
            for: playing,
            configuration: hiddenConfiguration
        )
        XCTAssertEqual(hiddenPublisher.clearCount, 1)

        let retainedPublisher = StubPublisher()
        let retainedController = DiscordPresenceController(
            publisher: retainedPublisher,
            artworkResolver: StubArtworkResolver()
        )
        var retainedConfiguration = DiscordPresenceConfiguration.standard
        retainedConfiguration.pausePolicy = .keepVisible
        playing.isPlaying = true
        playing.rate = 1
        retainedController.update(
            for: playing,
            configuration: retainedConfiguration
        )
        retainedPublisher.completeNext(with: true)
        drainMainQueue()
        playing.isPlaying = false
        playing.rate = 0
        retainedController.update(
            for: playing,
            configuration: retainedConfiguration
        )
        XCTAssertEqual(retainedPublisher.clearCount, 0)
        XCTAssertEqual(retainedPublisher.activities.count, 1)
    }

    func testManualActivityReplacesLiveAndDeduplicatesTheSameSession() throws {
        let publisher = StubPublisher()
        let controller = DiscordPresenceController(
            publisher: publisher,
            artworkResolver: StubArtworkResolver()
        )
        controller.update(for: makeTrack())
        publisher.completeNext(with: true)
        drainMainQueue()

        let manual = ManualDiscordPresence.example
        let activity = try XCTUnwrap(
            manual.activity(startedAt: Date(timeIntervalSince1970: 2_000))
        )
        controller.publishManual(activity, sessionKey: "session-1")
        publisher.completeNext(with: true)
        drainMainQueue()
        controller.publishManual(activity, sessionKey: "session-1")

        XCTAssertEqual(publisher.activities.count, 2)
        XCTAssertEqual(publisher.activities.last?.details, manual.title)
        XCTAssertEqual(
            publisher.activities.last?.smallImageText,
            "Manual presence · YT Music Companion"
        )
    }

    private func makeTrack() -> NowPlaying {
        NowPlaying(
            title: "Test Song",
            artist: "Test Artist",
            album: "Test Album",
            duration: 180,
            elapsed: 30,
            timestamp: 1_000,
            isPlaying: true,
            rate: 1,
            sourceBundle: "com.google.Chrome.app.cinhimbnkkaeohfgghhklpknlkffjgod",
            sourcePID: 0
        )
    }

    private func drainMainQueue() {
        let drained = expectation(description: "main queue drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 1)
    }
}

private final class StubPublisher: PresencePublishing {
    let isConfigured = true
    private(set) var activities: [PresenceActivity] = []
    private(set) var clearCount = 0
    private var completions: [((Bool) -> Void)?] = []

    func setActivity(_ activity: PresenceActivity, completion: ((Bool) -> Void)?) {
        activities.append(activity)
        completions.append(completion)
    }

    func completeNext(with result: Bool) {
        completions.removeFirst()?(result)
    }

    func clear() {
        clearCount += 1
    }

    func disconnect() {}
}

private struct StubArtworkResolver: ArtworkResolving {
    func coverURL(for track: NowPlaying, sourceArtwork: NowPlayingArtwork) -> String? { nil }
}

private final class CountingArtworkResolver: ArtworkResolving, @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0

    var callCount: Int { lock.withLock { calls } }

    func coverURL(for track: NowPlaying, sourceArtwork: NowPlayingArtwork) -> String? {
        lock.withLock { calls += 1 }
        return nil
    }
}
