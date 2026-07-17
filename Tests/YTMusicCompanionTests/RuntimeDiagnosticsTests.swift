import XCTest
@testable import YTMusicCompanion

final class RuntimeDiagnosticsTests: XCTestCase {
    func testPollingScheduleSlowsDownOutsideActivePlayback() {
        XCTAssertEqual(PlaybackPollingSchedule.interval(for: nil), 10)
        XCTAssertEqual(
            PlaybackPollingSchedule.interval(for: track(isPlaying: false, rate: 0)),
            4
        )
        XCTAssertEqual(
            PlaybackPollingSchedule.interval(for: track(isPlaying: true, rate: 1)),
            1
        )
    }

    func testLyricTimelineUsesTheLastStartedLine() {
        let lines = [
            LyricLine(time: 2, text: "A"),
            LyricLine(time: 4, text: "B"),
            LyricLine(time: 8, text: "C"),
        ]

        XCTAssertEqual(LyricTimeline.index(at: 1.9, in: lines), -1)
        XCTAssertEqual(LyricTimeline.index(at: 2, in: lines), 0)
        XCTAssertEqual(LyricTimeline.index(at: 7.9, in: lines), 1)
        XCTAssertEqual(LyricTimeline.index(at: 20, in: lines), 2)
        XCTAssertEqual(LyricTimeline.index(at: 20, in: []), -1)
    }

    private func track(isPlaying: Bool, rate: Double) -> NowPlaying {
        NowPlaying(
            title: "Song",
            artist: "Artist",
            album: "Album",
            duration: 180,
            elapsed: 10,
            timestamp: 100,
            isPlaying: isPlaying,
            rate: rate,
            sourceBundle: "com.google.Chrome",
            sourcePID: 1
        )
    }
}
