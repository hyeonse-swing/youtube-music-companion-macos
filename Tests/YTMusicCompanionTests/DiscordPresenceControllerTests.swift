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
