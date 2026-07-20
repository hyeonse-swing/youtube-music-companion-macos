import Foundation
import NaturalLanguage
import XCTest
@testable import YTMusicCompanion

final class LyricLayersTests: XCTestCase {
    func testRomanizationSupportsMultipleWritingSystems() {
        XCTAssertEqual(
            LyricRomanizer.romanized("안녕하세요", language: .korean),
            "annyeonghaseyo"
        )
        XCTAssertEqual(
            LyricRomanizer.romanized("Привет мир", language: .russian),
            "Privet mir"
        )
        XCTAssertNotNil(
            LyricRomanizer.romanized("你好世界", language: .simplifiedChinese)
        )
    }

    func testRomanizationHidesLatinAndEmptyText() {
        XCTAssertNil(LyricRomanizer.romanized("Hello world", language: .english))
        XCTAssertNil(
            LyricRomanizer.romanized(
                "I'm alive — don't stop!",
                language: .japanese
            )
        )
        XCTAssertNil(
            LyricRomanizer.romanized(
                "Tôi yêu tiếng Việt",
                language: .vietnamese
            )
        )
        XCTAssertNil(
            LyricRomanizer.romanized(
                "déjà vu · İstanbul · shōnen",
                language: nil
            )
        )
        XCTAssertNil(
            LyricRomanizer.romanized(
                "ɪŋɡlɪʃ",
                language: nil
            )
        )
        XCTAssertNil(LyricRomanizer.romanized("   ", language: nil))
    }

    func testMixedSongHidesAlreadyLatinLines() {
        let source = [
            LyricLine(time: 1, text: "鋼の羽根"),
            LyricLine(time: 4, text: "I can fly"),
        ]

        XCTAssertEqual(
            LyricRomanizer.romanizedLines(
                source,
                candidates: [],
                sourceLanguage: .japanese
            ),
            ["hagane no hane", ""]
        )
    }

    func testJapaneseKanaIsRomanizedWithoutTreatingKanjiAsChinese() {
        XCTAssertEqual(
            LyricRomanizer.romanized("こんにちは", language: .japanese),
            "kon'nichiha"
        )
        XCTAssertEqual(
            LyricRomanizer.romanized("鋼の羽根", language: .japanese),
            "hagane no hane"
        )
        XCTAssertEqual(
            LyricRomanizer.romanized(
                "何度失ったって 取り返してみせるよ",
                language: .japanese
            ),
            "nando ushinattatte torikaeshite miseru yo"
        )
        XCTAssertEqual(
            LyricRomanizer.romanized("全部貴方に", language: .japanese),
            "zenbu anata ni"
        )
    }

    func testJapaneseKanjiLinesAlwaysReceiveAReadablePronunciation() {
        let source = [
            LyricLine(time: 1, text: "雨上がり 虹が架かった空"),
            LyricLine(time: 4, text: "悪者は僕だけでいい"),
            LyricLine(time: 7, text: "学校へ行った"),
        ]

        let result = LyricRomanizer.romanizedLines(
            source,
            candidates: [],
            sourceLanguage: .japanese
        )

        XCTAssertEqual(result.count, source.count)
        XCTAssertTrue(result.allSatisfy { !$0.isEmpty })
        XCTAssertEqual(result.last, "gakkou he itta")
        XCTAssertEqual(
            LyricRomanizer.romanized("伝えたい 迷わない 気付いた", language: .japanese),
            "tsutaetai mayowanai kidzuita"
        )
    }

    func testAlignedCommunityRomanizationTakesPriorityOverAutomaticTransform() {
        let originals = [
            LyricLine(time: 1, text: "鋼の羽根"),
            LyricLine(time: 4, text: "空を飛ぶ"),
        ]
        let candidate = LyricCandidate(
            id: "romanized",
            title: "Iron Feather",
            artist: "Artist",
            album: "Album",
            duration: 180,
            lines: [
                LyricLine(time: 1.1, text: "Hagane no hane"),
                LyricLine(time: 4.1, text: "Sora wo tobu"),
            ]
        )

        XCTAssertEqual(
            LyricRomanizer.romanizedLines(
                originals,
                candidates: [candidate],
                sourceLanguage: .japanese
            ),
            ["Hagane no hane", "Sora wo tobu"]
        )
    }

    func testCommunityRomanizationHidesAlreadyLatinLines() {
        let originals = [
            LyricLine(time: 1, text: "鋼の羽根"),
            LyricLine(time: 4, text: "I can fly"),
        ]
        let candidate = LyricCandidate(
            id: "mixed-romanized",
            title: "Iron Feather",
            artist: "Artist",
            album: "Album",
            duration: 180,
            lines: [
                LyricLine(time: 1.1, text: "Hagane no hane"),
                LyricLine(time: 4.1, text: "I can fly"),
            ]
        )

        XCTAssertEqual(
            LyricRomanizer.romanizedLines(
                originals,
                candidates: [candidate],
                sourceLanguage: .japanese
            ),
            ["Hagane no hane", ""]
        )
    }

    func testLatinOnlyCommunityMatchesDoNotSelectARomanizationVersion() {
        let originals = [
            LyricLine(time: 1, text: "鋼の羽根"),
            LyricLine(time: 4, text: "I can fly"),
        ]
        let incompleteCandidate = LyricCandidate(
            id: "english-only",
            title: "Iron Feather",
            artist: "Artist",
            album: "Album",
            duration: 180,
            lines: [
                LyricLine(time: 4.1, text: "I can fly"),
            ]
        )

        XCTAssertEqual(
            LyricRomanizer.romanizedLines(
                originals,
                candidates: [incompleteCandidate],
                sourceLanguage: .japanese
            ),
            ["hagane no hane", ""]
        )
    }

    func testUnrelatedLatinCandidateIsNotUsedAsRomanization() {
        let originals = [
            LyricLine(time: 1, text: "안녕하세요"),
            LyricLine(time: 4, text: "다시 만나요"),
        ]
        let shifted = LyricCandidate(
            id: "wrong-version",
            title: "Wrong",
            artist: "Artist",
            album: "Album",
            duration: 180,
            lines: [
                LyricLine(time: 10, text: "unrelated"),
                LyricLine(time: 14, text: "lyrics"),
            ]
        )

        let result = LyricRomanizer.romanizedLines(
            originals,
            candidates: [shifted],
            sourceLanguage: .korean
        )

        XCTAssertEqual(result.first, "annyeonghaseyo")
        XCTAssertNotEqual(result, ["unrelated", "lyrics"])
    }

    func testTranslationResultAssemblerPreservesTimingAndBlankLines() {
        let source = [
            LyricLine(time: 1, text: "hello"),
            LyricLine(time: 2, text: ""),
            LyricLine(time: 3, text: "world"),
        ]

        XCTAssertEqual(
            LyricTranslationResultAssembler.alignedLines(
                source: source,
                translatedNonemptyLines: ["안녕", "세계"]
            ),
            ["안녕", "", "세계"]
        )
    }

    func testTranslationRequestCarriesTheDetectedSourceLanguage() throws {
        let lines = [
            LyricLine(time: 1, text: "鋼の羽根"),
            LyricLine(time: 4, text: "空を飛ぶ"),
        ]
        let sourceLanguage = LyricRomanizer.detectedLanguage(in: lines)?.rawValue

        XCTAssertEqual(sourceLanguage, "ja")
        let request = LyricTranslationRequest(
            id: UUID(),
            trackKey: "artist|song|album",
            sourceLanguage: try XCTUnwrap(sourceLanguage),
            targetLanguage: "ko",
            tone: .naturalLyrics,
            sourceLines: lines
        )
        XCTAssertEqual(request.sourceLanguage, "ja")
    }

    func testTranslationRequestAllowsAutomaticDetectionForAmbiguousLyrics() {
        let lines = [LyricLine(time: 1, text: "♪")]
        let sourceLanguage = LyricRomanizer.detectedLanguage(in: lines)?.rawValue

        XCTAssertNil(sourceLanguage)
        let request = LyricTranslationRequest(
            id: UUID(),
            trackKey: "artist|ambiguous|album",
            sourceLanguage: sourceLanguage,
            targetLanguage: "ko",
            tone: .naturalLyrics,
            sourceLines: lines
        )
        XCTAssertNil(request.sourceLanguage)
    }

    func testContextualTranslationRemovesTranslatorParagraphSpacing() {
        let translated = """
        첫 번째 줄

        두 번째 줄

        세 번째 줄
        """

        XCTAssertEqual(
            LyricTranslationResultAssembler.contextualNonemptyLines(
                translated,
                expectedCount: 3
            ),
            ["첫 번째 줄", "두 번째 줄", "세 번째 줄"]
        )
        XCTAssertNil(
            LyricTranslationResultAssembler.contextualNonemptyLines(
                "합쳐진 한 줄",
                expectedCount: 3
            )
        )
    }

    func testNaturalKoreanLyricsToneUsesConsistentConversationalEndings() {
        XCTAssertEqual(
            LyricTranslationStyler.styled(
                [
                    "사랑을 노래하다",
                    "연으로 돌아가는 냄새가 났다",
                    "우리는 몰두해서 그렸어.",
                    "게임도 하고 있으면 도망가 버린다",
                    "당연하게 있기를 바랍니다.",
                    "그건 사랑입니다",
                ],
                targetLanguage: "ko",
                tone: .naturalLyrics
            ),
            [
                "사랑을 노래해",
                "연으로 돌아가는 냄새가 났어",
                "우리는 몰두해서 그렸어.",
                "게임도 하고 있으면 도망가 버려",
                "당연하게 있기를 바라.",
                "그건 사랑이야",
            ]
        )
    }

    func testSystemTranslationToneAndNonKoreanTargetsAreNotRewritten() {
        let lines = ["사랑을 노래하다", "그 순간을 기억했다."]

        XCTAssertEqual(
            LyricTranslationStyler.styled(
                lines,
                targetLanguage: "ko",
                tone: .system
            ),
            lines
        )
        XCTAssertEqual(
            LyricTranslationStyler.styled(
                lines,
                targetLanguage: "en",
                tone: .naturalLyrics
            ),
            lines
        )
    }
}

final class LyricTranslationCacheTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "LyricTranslationCacheTests-\(UUID().uuidString)",
                isDirectory: true
            )
        LyricTranslationCache.overrideDirectory = tempDirectory
    }

    override func tearDownWithError() throws {
        LyricTranslationCache.overrideDirectory = nil
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    func testRoundTripRequiresTheSameTrackTargetAndSourceLyrics() {
        let lines = [
            LyricLine(time: 1, text: "hello"),
            LyricLine(time: 2, text: "world"),
        ]
        LyricTranslationCache.save(
            ["안녕", "세계"],
            for: "artist|song|album",
            targetLanguage: "ko",
            tone: .naturalLyrics,
            sourceLines: lines
        )

        XCTAssertEqual(
            LyricTranslationCache.load(
                for: "artist|song|album",
                targetLanguage: "ko",
                tone: .naturalLyrics,
                sourceLines: lines
            ),
            ["안녕", "세계"]
        )
        XCTAssertNil(
            LyricTranslationCache.load(
                for: "artist|song|album",
                targetLanguage: "en",
                tone: .naturalLyrics,
                sourceLines: lines
            )
        )
        XCTAssertNil(
            LyricTranslationCache.load(
                for: "artist|song|album",
                targetLanguage: "ko",
                tone: .naturalLyrics,
                sourceLines: [LyricLine(time: 1, text: "changed")]
            )
        )
        XCTAssertNil(
            LyricTranslationCache.load(
                for: "artist|song|album",
                targetLanguage: "ko",
                tone: .system,
                sourceLines: lines
            )
        )
    }

    func testClearRemovesCachedTranslations() {
        let lines = [LyricLine(time: 1, text: "hello")]
        LyricTranslationCache.save(
            ["안녕"],
            for: "artist|song|album",
            targetLanguage: "ko",
            tone: .naturalLyrics,
            sourceLines: lines
        )
        XCTAssertEqual(LyricTranslationCache.statistics().fileCount, 1)

        LyricTranslationCache.clear()

        XCTAssertEqual(
            LyricTranslationCache.statistics(),
            LyricsCacheStatistics(fileCount: 0, totalBytes: 0)
        )
        XCTAssertNil(
            LyricTranslationCache.load(
                for: "artist|song|album",
                targetLanguage: "ko",
                tone: .naturalLyrics,
                sourceLines: lines
            )
        )
    }

    func testSavingIdenticalTranslationDoesNotRewriteTheCacheFile() throws {
        let lines = [LyricLine(time: 1, text: "hello")]
        LyricTranslationCache.save(
            ["안녕"],
            for: "artist|song|album",
            targetLanguage: "ko",
            tone: .naturalLyrics,
            sourceLines: lines
        )
        let file = try XCTUnwrap(cacheFiles().first)
        let firstModification = try file.resourceValues(
            forKeys: [.contentModificationDateKey]
        ).contentModificationDate

        Thread.sleep(forTimeInterval: 0.05)
        LyricTranslationCache.save(
            ["안녕"],
            for: "artist|song|album",
            targetLanguage: "ko",
            tone: .naturalLyrics,
            sourceLines: lines
        )

        let secondModification = try file.resourceValues(
            forKeys: [.contentModificationDateKey]
        ).contentModificationDate
        XCTAssertEqual(secondModification, firstModification)
    }

    func testStatisticsRemainAccurateDuringConcurrentSaves() throws {
        DispatchQueue.concurrentPerform(iterations: 16) { index in
            let lines = [LyricLine(time: Double(index), text: "line \(index)")]
            LyricTranslationCache.save(
                ["번역 \(index)"],
                for: "artist|song|\(index)",
                targetLanguage: "ko",
                tone: .naturalLyrics,
                sourceLines: lines
            )
            _ = LyricTranslationCache.statistics()
        }

        let files = try cacheFiles()
        let expectedBytes = try files.reduce(0) {
            $0 + (try $1.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
        }
        XCTAssertEqual(
            LyricTranslationCache.statistics(),
            LyricsCacheStatistics(fileCount: files.count, totalBytes: expectedBytes)
        )
    }

    private func cacheFiles() throws -> [URL] {
        guard FileManager.default.fileExists(atPath: tempDirectory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(
            at: tempDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )
    }
}
