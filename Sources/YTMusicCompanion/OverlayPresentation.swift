import CoreGraphics
import Foundation

enum OverlayPreset: String, CaseIterable, Identifiable {
    case balanced
    case focused
    case compact
    case stage

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .balanced: "Balanced"
        case .focused: "Focused"
        case .compact: "Compact"
        case .stage: "Stage"
        }
    }

    var helpText: String {
        switch self {
        case .balanced:
            "Keeps the current line clear with a softly receding line on each side."
        case .focused:
            "Makes the current line larger and reduces nearby visual detail."
        case .compact:
            "Uses a smaller type size and keeps neighboring lines easy to scan."
        case .stage:
            "Uses large type and strongly fades neighboring lines for distant viewing."
        }
    }

    var recommendedFontSize: Double {
        switch self {
        case .balanced: 30
        case .focused: 36
        case .compact: 24
        case .stage: 42
        }
    }

    var neighborOpacity: Double {
        switch self {
        case .balanced: 0.42
        case .focused: 0.24
        case .compact: 0.60
        case .stage: 0.14
        }
    }

    var neighborBlur: CGFloat {
        switch self {
        case .balanced: 1.5
        case .focused: 2.2
        case .compact: 0
        case .stage: 2.8
        }
    }

    var neighborScale: CGFloat {
        switch self {
        case .balanced: 19 / 30
        case .focused: 0.56
        case .compact: 0.80
        case .stage: 0.52
        }
    }
}

enum LyricKaraokeTimeline {
    static let maximumLineFillDuration = 8.0
    static let fallbackLineFillDuration = 4.0

    static func progress(
        elapsed: Double,
        currentIndex: Int,
        lines: [LyricLine],
        trackDuration: Double
    ) -> Double {
        guard lines.indices.contains(currentIndex) else { return 0 }
        let start = lines[currentIndex].time
        guard elapsed > start else { return 0 }

        let nextStart = lines.indices.contains(currentIndex + 1)
            ? lines[currentIndex + 1].time
            : nil
        let naturalEnd: Double
        if let nextStart, nextStart > start {
            naturalEnd = nextStart
        } else if trackDuration > start {
            naturalEnd = trackDuration
        } else {
            naturalEnd = start + fallbackLineFillDuration
        }
        let end = min(naturalEnd, start + maximumLineFillDuration)
        let duration = max(0.25, end - start)
        return min(1, max(0, (elapsed - start) / duration))
    }

    static func highlightedCharacterCount(in text: String, progress: Double) -> Int {
        highlightedCharacterCount(
            characterCount: text.count,
            progress: progress
        )
    }

    static func highlightedCharacterCount(
        characterCount: Int,
        progress: Double
    ) -> Int {
        guard characterCount > 0 else { return 0 }
        let clampedProgress = min(1, max(0, progress))
        return min(
            characterCount,
            max(0, Int((Double(characterCount) * clampedProgress).rounded(.down)))
        )
    }
}
