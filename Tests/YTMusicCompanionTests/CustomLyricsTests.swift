import XCTest
@testable import YTMusicCompanion

final class CustomLyricsTests: XCTestCase {

    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CustomLyricsTests-\(UUID().uuidString)", isDirectory: true)
        CustomLyricsStore.overrideDirectory = tempDirectory
    }

    override func tearDownWithError() throws {
        CustomLyricsStore.overrideDirectory = nil
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    func testImportedDocumentRequiresSyncedLines() throws {
        XCTAssertThrowsError(try LyricsFileDocument.imported(
            from: Data("[ar: Artist]\nplain lyrics".utf8),
            sourceName: "plain.lrc"
        )) { error in
            XCTAssertEqual(error as? LyricsFileError, .noSyncedLines)
        }
    }

    func testImportedDocumentParsesUTF8AndPreservesSourceName() throws {
        let document = try LyricsFileDocument.imported(
            from: Data("[00:01.25] 一行目\n[00:03.50] 둘째 줄".utf8),
            sourceName: "mixed.lrc"
        )

        XCTAssertEqual(document.sourceName, "mixed.lrc")
        XCTAssertEqual(document.lines, [
            LyricLine(time: 1.25, text: "一行目"),
            LyricLine(time: 3.5, text: "둘째 줄"),
        ])
    }

    func testExportRoundTripsMetadataAndCentisecondTiming() throws {
        let track = NowPlaying(
            title: "鋼の羽根 - Iron Feather",
            artist: "RADWIMPS",
            album: "Forever Daze",
            duration: 318,
            elapsed: 0,
            timestamp: 0,
            isPlaying: true,
            rate: 1,
            sourceBundle: "",
            sourcePID: 0
        )
        let lines = [
            LyricLine(time: 1.236, text: "first"),
            LyricLine(time: 65.5, text: "second"),
        ]

        let exported = LyricsFileDocument.exportedText(lines: lines, track: track)

        XCTAssertTrue(exported.contains("[ar:RADWIMPS]"))
        XCTAssertTrue(exported.contains("[ti:鋼の羽根 - Iron Feather]"))
        XCTAssertTrue(exported.contains("[al:Forever Daze]"))
        XCTAssertTrue(exported.contains("[00:01.24] first"))
        XCTAssertTrue(exported.contains("[01:05.50] second"))
        XCTAssertEqual(LRCLIB.parseLRC(exported), lines.map {
            LyricLine(time: ($0.time * 100).rounded() / 100, text: $0.text)
        })
    }

    func testSuggestedFilenameRemovesPathSeparators() {
        let track = NowPlaying(
            title: "A/B: Live",
            artist: "Artist/Name",
            album: "",
            duration: 0,
            elapsed: 0,
            timestamp: 0,
            isPlaying: true,
            rate: 1,
            sourceBundle: "",
            sourcePID: 0
        )

        XCTAssertEqual(
            LyricsFileDocument.suggestedFilename(for: track),
            "Artist-Name - A-B- Live.lrc"
        )
    }

    func testCustomStoreRoundTripsAndRemovesUserLyrics() throws {
        let document = CustomLyricsDocument(
            sourceName: "mine.lrc",
            lines: [LyricLine(time: 2, text: "custom")]
        )

        try CustomLyricsStore.save(document, for: "Artist|Song|Album")
        XCTAssertEqual(CustomLyricsStore.load("Artist|Song|Album"), document)

        try CustomLyricsStore.remove(for: "Artist|Song|Album")
        XCTAssertNil(CustomLyricsStore.load("Artist|Song|Album"))
    }

    func testCustomStoreKeepsDistinctTrackKeysSeparate() throws {
        let first = CustomLyricsDocument(
            sourceName: "first.lrc",
            lines: [LyricLine(time: 1, text: "first")]
        )
        let second = CustomLyricsDocument(
            sourceName: "second.lrc",
            lines: [LyricLine(time: 2, text: "second")]
        )

        try CustomLyricsStore.save(first, for: "AC/DC|One|Album")
        try CustomLyricsStore.save(second, for: "AC/DC|Two|Album")

        XCTAssertEqual(CustomLyricsStore.load("AC/DC|One|Album"), first)
        XCTAssertEqual(CustomLyricsStore.load("AC/DC|Two|Album"), second)
    }

    func testClearingDownloadCacheDoesNotDeleteUserLyrics() throws {
        LyricsCache.overrideDirectory = tempDirectory.appendingPathComponent("download-cache")
        defer { LyricsCache.overrideDirectory = nil }
        let trackKey = "Artist|Song|Album"
        let custom = CustomLyricsDocument(
            sourceName: "keep-me.lrc",
            lines: [LyricLine(time: 1, text: "mine")]
        )
        LyricsCache.save([LyricLine(time: 1, text: "downloaded")], for: trackKey)
        try CustomLyricsStore.save(custom, for: trackKey)

        LyricsCache.clear()

        XCTAssertNil(LyricsCache.load(trackKey))
        XCTAssertEqual(CustomLyricsStore.load(trackKey), custom)
    }
}
