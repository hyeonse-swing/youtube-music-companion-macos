import XCTest
@testable import YTMusicCompanion

final class NowPlayingPresentationTests: XCTestCase {
    func testPresentationComparisonIgnoresOnlyMovingClockValues() {
        let first = makeTrack(elapsed: 12, timestamp: 100)
        let later = makeTrack(elapsed: 42, timestamp: 130)

        XCTAssertTrue(first.hasSamePresentation(as: later))
    }

    func testPresentationComparisonDetectsVisibleAndPlaybackStateChanges() {
        let original = makeTrack()

        var renamed = original
        renamed.title = "Another Song"
        XCTAssertFalse(original.hasSamePresentation(as: renamed))

        var paused = original
        paused.isPlaying = false
        paused.rate = 0
        XCTAssertFalse(original.hasSamePresentation(as: paused))

        var longer = original
        longer.duration += 1
        XCTAssertFalse(original.hasSamePresentation(as: longer))
    }

    private func makeTrack(
        elapsed: Double = 10,
        timestamp: Double = 100
    ) -> NowPlaying {
        NowPlaying(
            title: "Song",
            artist: "Artist",
            album: "Album",
            duration: 180,
            elapsed: elapsed,
            timestamp: timestamp,
            isPlaying: true,
            rate: 1,
            sourceBundle: "com.example.YouTubeMusic",
            sourcePID: 42
        )
    }
}
