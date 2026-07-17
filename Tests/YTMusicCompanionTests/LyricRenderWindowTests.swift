import XCTest
@testable import YTMusicCompanion

final class LyricRenderWindowTests: XCTestCase {
    func testBeforeFirstLineRendersOnlyTheUpcomingLine() {
        XCTAssertEqual(LyricRenderWindow.indices(lineCount: 10, currentIndex: -1), 0..<1)
    }

    func testMiddleOfTrackRendersPreviousCurrentAndNextLines() {
        XCTAssertEqual(LyricRenderWindow.indices(lineCount: 10, currentIndex: 5), 4..<7)
    }

    func testTrackEdgesStayInsideBounds() {
        XCTAssertEqual(LyricRenderWindow.indices(lineCount: 10, currentIndex: 0), 0..<2)
        XCTAssertEqual(LyricRenderWindow.indices(lineCount: 10, currentIndex: 9), 8..<10)
        XCTAssertEqual(LyricRenderWindow.indices(lineCount: 0, currentIndex: 0), 0..<0)
    }
}
