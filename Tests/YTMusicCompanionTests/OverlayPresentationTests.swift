import XCTest
@testable import YTMusicCompanion

final class OverlayPresentationTests: XCTestCase {
    func testPresetsProvideDistinctReadablePresentationValues() {
        XCTAssertEqual(OverlayPreset.balanced.recommendedFontSize, 30)
        XCTAssertEqual(OverlayPreset.focused.recommendedFontSize, 36)
        XCTAssertEqual(OverlayPreset.compact.recommendedFontSize, 24)
        XCTAssertEqual(OverlayPreset.stage.recommendedFontSize, 42)

        XCTAssertGreaterThan(
            OverlayPreset.compact.neighborOpacity,
            OverlayPreset.focused.neighborOpacity
        )
        XCTAssertGreaterThan(
            OverlayPreset.stage.neighborBlur,
            OverlayPreset.compact.neighborBlur
        )
    }

    func testKaraokeProgressUsesTheCurrentAndNextLineTimestamps() {
        let lines = [
            LyricLine(time: 0, text: "First"),
            LyricLine(time: 4, text: "Second"),
            LyricLine(time: 10, text: "Third"),
        ]

        XCTAssertEqual(
            LyricKaraokeTimeline.progress(
                elapsed: 2,
                currentIndex: 0,
                lines: lines,
                trackDuration: 20
            ),
            0.5,
            accuracy: 0.001
        )
        XCTAssertEqual(
            LyricKaraokeTimeline.progress(
                elapsed: 6,
                currentIndex: 1,
                lines: lines,
                trackDuration: 20
            ),
            1.0 / 3.0,
            accuracy: 0.001
        )
    }

    func testKaraokeProgressClampsLongInstrumentalGapsAndTrackEdges() {
        let lines = [
            LyricLine(time: 5, text: "Long gap"),
            LyricLine(time: 30, text: "Next"),
        ]

        XCTAssertEqual(
            LyricKaraokeTimeline.progress(
                elapsed: 4,
                currentIndex: 0,
                lines: lines,
                trackDuration: 40
            ),
            0
        )
        XCTAssertEqual(
            LyricKaraokeTimeline.progress(
                elapsed: 13,
                currentIndex: 0,
                lines: lines,
                trackDuration: 40
            ),
            1
        )
        XCTAssertEqual(
            LyricKaraokeTimeline.progress(
                elapsed: 40,
                currentIndex: 1,
                lines: lines,
                trackDuration: 40
            ),
            1
        )
        XCTAssertEqual(
            LyricKaraokeTimeline.progress(
                elapsed: 10,
                currentIndex: -1,
                lines: lines,
                trackDuration: 40
            ),
            0
        )
    }

    func testHighlightedCharacterCountUsesExtendedGraphemeClusters() {
        XCTAssertEqual(
            LyricKaraokeTimeline.highlightedCharacterCount(
                in: "가나다라",
                progress: 0.5
            ),
            2
        )
        XCTAssertEqual(
            LyricKaraokeTimeline.highlightedCharacterCount(
                in: "👨‍👩‍👧‍👦🎵",
                progress: 0.5
            ),
            1
        )
        XCTAssertEqual(
            LyricKaraokeTimeline.highlightedCharacterCount(
                in: "abc",
                progress: 2
            ),
            3
        )
    }
}
