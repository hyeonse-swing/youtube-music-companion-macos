import XCTest
@testable import YTMusicCompanion

final class LyricsCacheTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LyricsCacheTests-\(UUID().uuidString)", isDirectory: true)
        LyricsCache.overrideDirectory = tempDir
    }

    override func tearDownWithError() throws {
        LyricsCache.overrideDirectory = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testMissReturnsNil() {
        XCTAssertNil(LyricsCache.load("Nobody|Nothing"))
    }

    func testRoundTripsLyrics() {
        let lines = [LyricLine(time: 1.5, text: "hello"), LyricLine(time: 65.5, text: "world")]
        LyricsCache.save(lines, for: "Band|Song")
        XCTAssertEqual(LyricsCache.load("Band|Song"), lines)
    }

    func testStoredEmptyIsDistinctFromAMiss() {
        // A genuine "no synced lyrics" empty must come back as [] (a real cached
        // answer), not nil (never stored) — otherwise lyric-less tracks refetch
        // every session.
        LyricsCache.save([], for: "Band|Instrumental")
        XCTAssertEqual(LyricsCache.load("Band|Instrumental"), [])
        XCTAssertNil(LyricsCache.load("Band|NeverSeen"))
    }

    func testKeysWithFilesystemMetacharsDoNotCollide() {
        // trackKey is free-form "artist|title" and can contain "/" etc.; the hash
        // filename must keep distinct keys in distinct files.
        LyricsCache.save([LyricLine(time: 0, text: "a")], for: "AC/DC|T.N.T")
        LyricsCache.save([LyricLine(time: 0, text: "b")], for: "AC/DC|Hells Bells")
        XCTAssertEqual(LyricsCache.load("AC/DC|T.N.T")?.first?.text, "a")
        XCTAssertEqual(LyricsCache.load("AC/DC|Hells Bells")?.first?.text, "b")
    }

    func testStatisticsAndClearCoverEverySavedTrack() {
        LyricsCache.save([LyricLine(time: 0, text: "a")], for: "A|One")
        LyricsCache.save([LyricLine(time: 0, text: "b")], for: "B|Two")

        let before = LyricsCache.statistics()
        XCTAssertEqual(before.fileCount, 2)
        XCTAssertGreaterThan(before.totalBytes, 0)

        LyricsCache.clear()

        XCTAssertEqual(LyricsCache.statistics(), LyricsCacheStatistics(fileCount: 0, totalBytes: 0))
        XCTAssertNil(LyricsCache.load("A|One"))
        XCTAssertNil(LyricsCache.load("B|Two"))
    }

    func testSavingIdenticalLyricsDoesNotRewriteTheCacheFile() throws {
        let lines = [LyricLine(time: 1, text: "same")]
        LyricsCache.save(lines, for: "A|Same")
        let file = try XCTUnwrap(cacheFiles().first)
        let firstModification = try file.resourceValues(
            forKeys: [.contentModificationDateKey]
        ).contentModificationDate

        Thread.sleep(forTimeInterval: 0.05)
        LyricsCache.save(lines, for: "A|Same")

        let secondModification = try file.resourceValues(
            forKeys: [.contentModificationDateKey]
        ).contentModificationDate
        XCTAssertEqual(secondModification, firstModification)
    }

    func testCorruptEntryIsRemovedAfterAReadFailure() throws {
        LyricsCache.save([LyricLine(time: 1, text: "valid")], for: "A|Corrupt")
        let file = try XCTUnwrap(cacheFiles().first)
        try Data("not json".utf8).write(to: file, options: .atomic)

        XCTAssertNil(LyricsCache.load("A|Corrupt"))
        XCTAssertTrue(try cacheFiles().isEmpty)
    }

    func testStatisticsRemainAccurateDuringConcurrentSaves() throws {
        DispatchQueue.concurrentPerform(iterations: 16) { index in
            LyricsCache.save(
                [LyricLine(time: Double(index), text: "line \(index)")],
                for: "Artist|\(index)"
            )
            _ = LyricsCache.statistics()
        }

        let files = try cacheFiles()
        let expectedBytes = try files.reduce(0) {
            $0 + (try $1.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
        }
        XCTAssertEqual(
            LyricsCache.statistics(),
            LyricsCacheStatistics(fileCount: files.count, totalBytes: expectedBytes)
        )
    }

    private func cacheFiles() throws -> [URL] {
        guard FileManager.default.fileExists(atPath: tempDir.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(
            at: tempDir,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )
    }
}
