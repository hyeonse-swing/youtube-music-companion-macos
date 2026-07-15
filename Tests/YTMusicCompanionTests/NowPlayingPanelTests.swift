import XCTest
@testable import YTMusicCompanion

final class NowPlayingPanelTests: XCTestCase {
    func testPlaybackTimeUsesMinutesAndZeroPaddedSeconds() {
        XCTAssertEqual(PlaybackTimeFormatter.string(seconds: 0), "0:00")
        XCTAssertEqual(PlaybackTimeFormatter.string(seconds: 65.9), "1:05")
        XCTAssertEqual(PlaybackTimeFormatter.string(seconds: 3_661), "61:01")
    }

    func testPlaybackTimeRejectsInvalidValues() {
        XCTAssertEqual(PlaybackTimeFormatter.string(seconds: -.infinity), "0:00")
        XCTAssertEqual(PlaybackTimeFormatter.string(seconds: .nan), "0:00")
    }
}
