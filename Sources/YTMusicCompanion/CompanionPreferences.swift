import Foundation

enum MetadataSourcePreference: String, CaseIterable, Identifiable {
    case youtubeMusic
    case macOS

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .youtubeMusic: "YouTube Music screen"
        case .macOS: "macOS playback info"
        }
    }

    var helpText: String {
        switch self {
        case .youtubeMusic:
            "Uses the title, artist, and album shown in the YouTube Music player. Falls back to macOS when screen access is unavailable."
        case .macOS:
            "Uses the metadata published to the macOS Now Playing system."
        }
    }

    func select(youtubeMusic: NowPlaying?, macOS: NowPlaying?) -> NowPlaying? {
        switch self {
        case .youtubeMusic:
            youtubeMusic ?? macOS
        case .macOS:
            macOS
        }
    }
}

/// Small, testable persistence boundary for user-selectable behavior. The live
/// playback model owns one value and publishes changes to SwiftUI after mutating it.
struct CompanionPreferences {
    static let defaultLyricsFontSize = 30.0
    static let minimumLyricsFontSize = 18.0
    static let maximumLyricsFontSize = 52.0

    private static let lyricsFontSizeKey = "lyricsFontSize"
    private static let displayMetadataSourceKey = "displayMetadataSource"
    private static let discordMetadataSourceKey = "discordMetadataSource"
    private static let trackOffsetsKey = "syncTrackOffsets"
    private static let learnedOffsetKey = "syncLearnedOffset"
    private static let lyricSelectionsKey = "lyricsCandidateSelections"

    private let defaults: UserDefaults
    private var trackOffsets: [String: Double]
    private var lyricSelections: [String: String]

    var lyricsFontSize: Double {
        didSet {
            lyricsFontSize = Self.clampLyricsFontSize(lyricsFontSize)
            defaults.set(lyricsFontSize, forKey: Self.lyricsFontSizeKey)
        }
    }

    var displayMetadataSource: MetadataSourcePreference {
        didSet {
            defaults.set(displayMetadataSource.rawValue, forKey: Self.displayMetadataSourceKey)
        }
    }

    var discordMetadataSource: MetadataSourcePreference {
        didSet {
            defaults.set(discordMetadataSource.rawValue, forKey: Self.discordMetadataSourceKey)
        }
    }

    private(set) var learnedTimingOffset: Double

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedFontSize = defaults.object(forKey: Self.lyricsFontSizeKey) as? Double
        lyricsFontSize = Self.clampLyricsFontSize(
            storedFontSize ?? Self.defaultLyricsFontSize
        )
        displayMetadataSource = MetadataSourcePreference(
            rawValue: defaults.string(forKey: Self.displayMetadataSourceKey) ?? ""
        ) ?? .youtubeMusic
        discordMetadataSource = MetadataSourcePreference(
            rawValue: defaults.string(forKey: Self.discordMetadataSourceKey) ?? ""
        ) ?? .youtubeMusic
        learnedTimingOffset = defaults.double(forKey: Self.learnedOffsetKey)
        trackOffsets = (defaults.dictionary(forKey: Self.trackOffsetsKey) ?? [:])
            .compactMapValues { ($0 as? NSNumber)?.doubleValue }
        lyricSelections = defaults.dictionary(forKey: Self.lyricSelectionsKey) as? [String: String] ?? [:]
    }

    func timingOffset(for trackKey: String) -> Double {
        trackOffsets[trackKey] ?? learnedTimingOffset
    }

    mutating func saveTimingOffset(_ offset: Double, for trackKey: String) {
        trackOffsets[trackKey] = offset
        defaults.set(trackOffsets, forKey: Self.trackOffsetsKey)
    }

    mutating func saveLearnedTimingOffset(_ offset: Double) {
        learnedTimingOffset = offset
        defaults.set(offset, forKey: Self.learnedOffsetKey)
    }

    mutating func resetTimingOffset(for trackKey: String) {
        // Keep an explicit zero so a non-zero learned baseline cannot reappear the
        // next time this particular song plays.
        saveTimingOffset(0, for: trackKey)
    }

    mutating func resetAllTimingOffsets() {
        trackOffsets.removeAll()
        learnedTimingOffset = 0
        defaults.removeObject(forKey: Self.trackOffsetsKey)
        defaults.removeObject(forKey: Self.learnedOffsetKey)
    }

    func selectedLyricCandidate(for trackKey: String) -> String? {
        lyricSelections[trackKey]
    }

    mutating func selectLyricCandidate(_ candidateID: String, for trackKey: String) {
        lyricSelections[trackKey] = candidateID
        defaults.set(lyricSelections, forKey: Self.lyricSelectionsKey)
    }

    private static func clampLyricsFontSize(_ value: Double) -> Double {
        min(maximumLyricsFontSize, max(minimumLyricsFontSize, value))
    }
}
