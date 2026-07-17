import CoreFoundation
import Foundation
import NaturalLanguage

enum LyricTranslationTone: String, CaseIterable, Codable, Identifiable {
    case naturalLyrics
    case system

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .naturalLyrics:
            "Natural lyrics"
        case .system:
            "System translation"
        }
    }
}

enum LyricTranslationLanguage: String, CaseIterable, Identifiable {
    case system
    case arabic = "ar"
    case chineseSimplified = "zh-Hans"
    case chineseTraditional = "zh-Hant"
    case dutch = "nl"
    case english = "en"
    case french = "fr"
    case german = "de"
    case hindi = "hi"
    case indonesian = "id"
    case italian = "it"
    case japanese = "ja"
    case korean = "ko"
    case polish = "pl"
    case portuguese = "pt"
    case russian = "ru"
    case spanish = "es"
    case thai = "th"
    case turkish = "tr"
    case ukrainian = "uk"
    case vietnamese = "vi"

    var id: String { rawValue }

    var resolvedIdentifier: String {
        switch self {
        case .system:
            Locale.preferredLanguages.first ?? "en"
        default:
            rawValue
        }
    }

    var displayName: String {
        if self == .system {
            let language = Locale.current.localizedString(
                forIdentifier: resolvedIdentifier
            ) ?? resolvedIdentifier
            return "System Language (\(language))"
        }
        return Locale.current.localizedString(forIdentifier: rawValue)
            ?? Locale.current.localizedString(forLanguageCode: rawValue)
            ?? rawValue
    }
}

enum LyricTranslationStatus: Equatable {
    case disabled
    case waiting
    case translating
    case ready
    case unavailable
    case failed(String)

    var displayName: String {
        switch self {
        case .disabled:
            "Off"
        case .waiting:
            "Preparing translation…"
        case .translating:
            "Translating on this Mac…"
        case .ready:
            "Translation ready"
        case .unavailable:
            "Requires macOS 15 or later"
        case let .failed(message):
            message
        }
    }

    var systemImage: String {
        switch self {
        case .disabled:
            "character.book.closed"
        case .waiting:
            "clock"
        case .translating:
            "arrow.triangle.2.circlepath"
        case .ready:
            "checkmark.circle"
        case .unavailable, .failed:
            "exclamationmark.triangle"
        }
    }
}

struct LyricTranslationRequest: Identifiable, Equatable {
    let id: UUID
    let trackKey: String
    let targetLanguage: String
    let tone: LyricTranslationTone
    let sourceLines: [LyricLine]
}

enum LyricTranslationResultAssembler {
    static func alignedLines(
        source: [LyricLine],
        translatedNonemptyLines: [String]
    ) -> [String] {
        var iterator = translatedNonemptyLines.makeIterator()
        return source.map { line in
            guard !line.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return "" }
            return iterator.next() ?? ""
        }
    }

    /// Apple Translation may format newline-separated input as paragraphs and
    /// insert an empty line between every translated lyric. Removing only empty
    /// output lines preserves lyric order while keeping the original LRC timing.
    static func contextualNonemptyLines(
        _ translatedText: String,
        expectedCount: Int
    ) -> [String]? {
        let lines = translatedText
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return lines.count == expectedCount ? lines : nil
    }
}

/// Apple Translation does not expose a style prompt. Natural Lyrics therefore
/// keeps the system's wording and only normalizes clearly sentence-final Korean
/// endings to the conversational style commonly used by synced lyrics.
enum LyricTranslationStyler {
    static func styled(
        _ lines: [String],
        targetLanguage: String,
        tone: LyricTranslationTone
    ) -> [String] {
        let targetCode = targetLanguage
            .split(separator: "-")
            .first?
            .lowercased()
        guard tone == .naturalLyrics, targetCode == "ko" else { return lines }
        return lines.map(koreanConversationalLine)
    }

    private static func koreanConversationalLine(_ line: String) -> String {
        var core = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !core.isEmpty else { return "" }

        var trailingPunctuation = ""
        while let character = core.last, trailingCharacters.contains(character) {
            trailingPunctuation.insert(character, at: trailingPunctuation.startIndex)
            core.removeLast()
        }
        core = core.trimmingCharacters(in: .whitespaces)
        guard !core.isEmpty else { return line }

        if core.hasSuffix("입니다") {
            core.removeLast("입니다".count)
            core += koreanCopulaEnding(after: core.last)
            return core + trailingPunctuation
        }

        for (ending, replacement) in koreanEndingReplacements {
            guard core.hasSuffix(ending) else { continue }
            core.removeLast(ending.count)
            return core + replacement + trailingPunctuation
        }

        if core.hasSuffix("는다") {
            core.removeLast("는다".count)
            return core + "어" + trailingPunctuation
        }

        // Korean past-tense syllables carry ㅆ as the final consonant
        // (갔다, 봤다, 났다). Appending 어 produces the matching casual ending.
        if core.last == "다" {
            let stem = core.dropLast()
            if let last = stem.last, hangulFinalConsonantIndex(last) == 20 {
                return String(stem) + "어" + trailingPunctuation
            }
        }

        return core + trailingPunctuation
    }

    private static let koreanEndingReplacements: [(String, String)] = [
        ("것이었습니다", "거였어"),
        ("것입니다", "거야"),
        ("것이었다", "거였어"),
        ("것이다", "거야"),
        ("아니었습니다", "아니었어"),
        ("아닙니다", "아니야"),
        ("있었습니다", "있었어"),
        ("없었습니다", "없었어"),
        ("되었습니다", "됐어"),
        ("하였습니다", "했어"),
        ("았습니다", "았어"),
        ("었습니다", "었어"),
        ("했습니다", "했어"),
        ("바랍니다", "바라"),
        ("있습니다", "있어"),
        ("없습니다", "없어"),
        ("싶습니다", "싶어"),
        ("같습니다", "같아"),
        ("좋습니다", "좋아"),
        ("싫습니다", "싫어"),
        ("됩니다", "돼"),
        ("이었습니다", "이었어"),
        ("였습니다", "였어"),
        ("있었다", "있었어"),
        ("없었다", "없었어"),
        ("되었다", "됐어"),
        ("하였다", "했어"),
        ("이었다", "이었어"),
        ("버린다", "버려"),
        ("원한다", "원해"),
        ("바란다", "바라"),
        ("합니다", "해"),
        ("됐습니다", "됐어"),
        ("했다", "했어"),
        ("됐다", "됐어"),
        ("였다", "였어"),
        ("한다", "해"),
        ("하다", "해"),
        ("아니다", "아니야"),
        ("바라다", "바라"),
        ("모르다", "몰라"),
        ("버리다", "버려"),
        ("원하다", "원해"),
        ("있다", "있어"),
        ("없다", "없어"),
        ("싶다", "싶어"),
        ("같다", "같아"),
        ("좋다", "좋아"),
        ("싫다", "싫어"),
        ("않다", "않아"),
        ("맞다", "맞아"),
        ("되다", "돼"),
        ("주다", "줘"),
        ("보다", "봐"),
        ("오다", "와"),
        ("가다", "가"),
        ("린다", "려"),
        ("긴다", "겨"),
        ("신다", "셔"),
        ("진다", "져"),
        ("친다", "쳐"),
        ("킨다", "켜"),
        ("된다", "돼"),
        ("았다", "았어"),
        ("었다", "었어"),
    ]

    private static let trailingCharacters = Set(
        ".!?…。！？~～\"'”’」』）)]}"
    )

    private static func koreanCopulaEnding(after character: Character?) -> String {
        guard let character else { return "야" }
        return hangulFinalConsonantIndex(character) == 0 ? "야" : "이야"
    }

    private static func hangulFinalConsonantIndex(_ character: Character) -> UInt32? {
        guard character.unicodeScalars.count == 1,
              let value = character.unicodeScalars.first?.value,
              (0xAC00...0xD7A3).contains(value)
        else { return nil }
        return (value - 0xAC00) % 28
    }
}

/// Produces an optional pronunciation layer without replacing the source lyrics.
/// A timing-compatible community romanization is preferred when one exists.
/// Core Foundation's language-aware tokenizer supplies native readings for
/// scripts such as Japanese Kanji; ICU transliteration remains a broad fallback.
enum LyricRomanizer {
    private static let communityTimingTolerance = 0.75
    private static let communityCoverageThreshold = 0.7

    static func detectedLanguage(in lines: [LyricLine]) -> NLLanguage? {
        let sample = lines.lazy
            .map(\.text)
            .filter { !$0.isEmpty }
            .prefix(80)
            .joined(separator: "\n")
        guard !sample.isEmpty else { return nil }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sample)
        return recognizer.dominantLanguage
    }

    static func romanizedLines(
        _ source: [LyricLine],
        candidates: [LyricCandidate],
        sourceLanguage: NLLanguage? = nil
    ) -> [String] {
        guard !source.isEmpty else { return [] }
        let language = sourceLanguage ?? detectedLanguage(in: source)

        if containsNonLatinScript(source),
           let community = bestCommunityRomanization(
               for: source,
               candidates: candidates
           )
        {
            return community
        }

        return source.map {
            romanized($0.text, language: language) ?? ""
        }
    }

    static func romanized(_ text: String, language: NLLanguage?) -> String? {
        let original = normalized(text)
        guard !original.isEmpty else { return nil }

        let transformed = languageAwareLatinTranscription(
            text,
            language: language
        ) ?? text.applyingTransform(.toLatin, reverse: false)
        guard let transformed else { return nil }
        let result = normalized(transformed)
        guard !result.isEmpty, result != original else { return nil }
        return result
    }

    private struct TranscribedToken {
        let source: String
        var latin: String
        let location: Int
        let length: Int

        var endLocation: Int { location + length }
    }

    private static func languageAwareLatinTranscription(
        _ text: String,
        language: NLLanguage?
    ) -> String? {
        let source = text as CFString
        let tokenizer = CFStringTokenizerCreate(
            kCFAllocatorDefault,
            source,
            CFRange(location: 0, length: CFStringGetLength(source)),
            CFOptionFlags(kCFStringTokenizerUnitWord),
            Locale(identifier: language?.rawValue ?? "und") as CFLocale
        )
        let sourceNSString = text as NSString
        var tokens: [TranscribedToken] = []

        while !CFStringTokenizerAdvanceToNextToken(tokenizer).isEmpty {
            let range = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            guard range.location != kCFNotFound, range.length > 0 else { continue }
            let sourceToken = sourceNSString.substring(
                with: NSRange(location: range.location, length: range.length)
            )
            let latinAttribute = CFStringTokenizerCopyCurrentTokenAttribute(
                tokenizer,
                kCFStringTokenizerAttributeLatinTranscription
            ) as? String
            let latin = normalized(latinAttribute ?? sourceToken)
            guard !latin.isEmpty else { continue }
            tokens.append(
                TranscribedToken(
                    source: sourceToken,
                    latin: latin,
                    location: range.location,
                    length: range.length
                )
            )
        }

        guard !tokens.isEmpty else { return nil }
        if language == .japanese {
            tokens = normalizedJapaneseTokens(tokens)
        }
        let transcription = normalized(tokens.map(\.latin).joined(separator: " "))
        guard !transcription.isEmpty, transcription != normalized(text) else {
            return nil
        }
        return transcription
    }

    private static func normalizedJapaneseTokens(
        _ tokens: [TranscribedToken]
    ) -> [TranscribedToken] {
        var result: [TranscribedToken] = []
        var index = 0

        while index < tokens.count {
            var current = tokens[index]

            if current.latin.hasSuffix("~tsu"), index + 1 < tokens.count {
                let next = tokens[index + 1]
                let base = current.latin.dropLast("~tsu".count)
                let doubledConsonant = next.latin.first.map {
                    isLatinConsonant($0) ? String($0) : ""
                } ?? ""
                current = TranscribedToken(
                    source: current.source + next.source,
                    latin: String(base) + doubledConsonant + next.latin,
                    location: current.location,
                    length: next.endLocation - current.location
                )
                index += 1
            }

            if var previous = result.last,
               shouldJoinJapaneseTokens(previous, current)
            {
                previous = TranscribedToken(
                    source: previous.source + current.source,
                    latin: previous.latin + current.latin,
                    location: previous.location,
                    length: current.endLocation - previous.location
                )
                result[result.count - 1] = previous
            } else {
                result.append(current)
            }
            index += 1
        }
        return result
    }

    private static func shouldJoinJapaneseTokens(
        _ previous: TranscribedToken,
        _ current: TranscribedToken
    ) -> Bool {
        guard previous.endLocation == current.location else { return false }
        if containsOnlyHan(previous.source),
           japaneseCounterSuffixes.contains(current.source)
        {
            return true
        }
        return japaneseAttachedSuffixes.contains(current.source)
            && !japaneseStandaloneParticles.contains(previous.source)
    }

    private static let japaneseCounterSuffixes: Set<String> = [
        "度", "回", "人", "日", "年", "月", "時", "分", "秒",
        "本", "枚", "個", "匹", "曲", "階", "歳", "才", "円",
        "百", "千", "万", "億",
    ]

    private static let japaneseAttachedSuffixes: Set<String> = [
        "た", "たい", "たく", "たかった", "て", "ない", "なく",
        "なかった", "ます", "ました", "ません", "ませんでした",
        "れる", "られる", "せる", "させる", "そう", "すぎる",
        "ながら", "みたい", "らしい", "っぽい", "ず", "ぬ",
        "ん", "だった", "でした", "たり", "だり",
    ]

    private static let japaneseStandaloneParticles: Set<String> = [
        "は", "が", "を", "に", "へ", "と", "で", "の", "も",
        "や", "か", "ね", "よ", "ぞ", "さ", "から", "まで",
        "より", "だけ", "しか", "ばかり", "ほど", "くらい",
        "ぐらい",
    ]

    private static func isLatinConsonant(_ character: Character) -> Bool {
        guard let scalar = character.lowercased().unicodeScalars.first,
              (0x61...0x7A).contains(scalar.value)
        else { return false }
        return !"aeiou".unicodeScalars.contains(scalar)
    }

    private static func containsOnlyHan(_ text: String) -> Bool {
        !text.isEmpty && text.unicodeScalars.allSatisfy {
            (0x3400...0x4DBF).contains($0.value)
                || (0x4E00...0x9FFF).contains($0.value)
                || (0xF900...0xFAFF).contains($0.value)
        }
    }

    private static func bestCommunityRomanization(
        for source: [LyricLine],
        candidates: [LyricCandidate]
    ) -> [String]? {
        let eligible = candidates.filter {
            $0.script == .latin && $0.lines != source
        }
        let requiredCount = max(
            1,
            Int(
                ceil(
                    Double(
                        source.filter {
                            !$0.text.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            ).isEmpty
                        }.count
                    )
                        * communityCoverageThreshold
                )
            )
        )

        return eligible.compactMap { candidate -> (lines: [String], matches: Int, drift: Double)? in
            let aligned = align(source: source, candidate: candidate.lines)
            let matches = aligned.values.compactMap { $0 }.count
            guard matches >= requiredCount else { return nil }
            let lines = source.indices.map { aligned.values[$0] ?? "" }
            return (lines, matches, aligned.totalDrift)
        }
        .sorted {
            if $0.matches == $1.matches { return $0.drift < $1.drift }
            return $0.matches > $1.matches
        }
        .first?
        .lines
    }

    private static func align(
        source: [LyricLine],
        candidate: [LyricLine]
    ) -> (values: [String?], totalDrift: Double) {
        let usableCandidates = candidate.filter {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        var values = Array<String?>(repeating: nil, count: source.count)
        var totalDrift = 0.0
        var candidateIndex = 0

        for (sourceIndex, line) in source.enumerated() {
            guard !line.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  candidateIndex < usableCandidates.count
            else { continue }

            while candidateIndex + 1 < usableCandidates.count,
                  abs(usableCandidates[candidateIndex + 1].time - line.time)
                    < abs(usableCandidates[candidateIndex].time - line.time)
            {
                candidateIndex += 1
            }

            let match = usableCandidates[candidateIndex]
            let drift = abs(match.time - line.time)
            if drift <= communityTimingTolerance {
                values[sourceIndex] = match.text
                totalDrift += drift
                candidateIndex += 1
            }
        }
        return (values, totalDrift)
    }

    private static func containsNonLatinScript(_ lines: [LyricLine]) -> Bool {
        containsNonLatinScript(lines.map(\.text).joined())
    }

    private static func containsNonLatinScript(_ text: String) -> Bool {
        text.unicodeScalars.contains {
            CharacterSet.letters.contains($0) && $0.value > 0x024F
        }
    }

    private static func normalized(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
