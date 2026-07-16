import XCTest
@testable import YTMusicCompanion

final class LyricRenderWindowTests: XCTestCase {
    func testBeforeFirstLineRendersOnlyTheUpcomingLine() {
        XCTAssertEqual(LyricRenderWindow.indices(lineCount: 10, currentIndex: -1), [0])
    }

    func testMiddleOfTrackRendersPreviousCurrentAndNextLines() {
        XCTAssertEqual(LyricRenderWindow.indices(lineCount: 10, currentIndex: 5), [4, 5, 6])
    }

    func testTrackEdgesStayInsideBounds() {
        XCTAssertEqual(LyricRenderWindow.indices(lineCount: 10, currentIndex: 0), [0, 1])
        XCTAssertEqual(LyricRenderWindow.indices(lineCount: 10, currentIndex: 9), [8, 9])
        XCTAssertEqual(LyricRenderWindow.indices(lineCount: 0, currentIndex: 0), [])
    }
}
