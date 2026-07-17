import Foundation
import CryptoKit

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
        var selected = switch self {
        case .youtubeMusic:
            youtubeMusic ?? macOS
        case .macOS:
            macOS
        }
        if let trackURL = youtubeMusic?.trackURL {
            selected?.trackURL = trackURL
        }
        return selected
    }
}

/// Small, testable persistence boundary for user-selectable behavior. The live
/// playback model owns one value and publishes changes to SwiftUI after mutating it.
struct CompanionPreferences {
    static let defaultLyricsFontSize = 30.0
    static let minimumLyricsFontSize = 18.0
    static let maximumLyricsFontSize = 52.0

    private static let lyricsFontSizeKey = "lyricsFontSize"
    private static let overlayPresetKey = "overlayPreset"
    private static let karaokeModeEnabledKey = "karaokeModeEnabled"
    private static let showsRomanizedLyricsKey = "showsRomanizedLyrics"
    private static let showsTranslatedLyricsKey = "showsTranslatedLyrics"
    private static let translationTargetLanguageKey = "translationTargetLanguage"
    private static let translationToneKey = "translationTone"
    private static let appLanguageKey = "appLanguage"
    private static let displayMetadataSourceKey = "displayMetadataSource"
    private static let discordMetadataSourceKey = "discordMetadataSource"
    private static let trackOffsetsKey = "syncTrackOffsets"
    private static let learnedOffsetKey = "syncLearnedOffset"
    private static let lyricSelectionsKey = "lyricsCandidateSelections"
    private static let discordDetailsTemplateKey = "discordDetailsTemplate"
    private static let discordStateTemplateKey = "discordStateTemplate"
    private static let discordImageTextTemplateKey = "discordImageTextTemplate"
    private static let discordShowsPlaybackTimeKey = "discordShowsPlaybackTime"
    private static let discordShowsSongLinkKey = "discordShowsSongLink"
    private static let discordPresetKey = "discordPreset"
    private static let discordPausePolicyKey = "discordPausePolicy"
    private static let discordLinksDetailsToSongKey = "discordLinksDetailsToSong"
    private static let discordLinksStateToSongKey = "discordLinksStateToSong"
    private static let discordLinksCoverToSongKey = "discordLinksCoverToSong"
    private static let discordPrimaryButtonLabelKey = "discordPrimaryButtonLabel"
    private static let discordSecondaryButtonLabelKey = "discordSecondaryButtonLabel"
    private static let discordSecondaryButtonURLKey = "discordSecondaryButtonURL"
    private static let discordPrivateTrackFingerprintsKey = "discordPrivateTrackFingerprints"

    private let defaults: UserDefaults
    private var trackOffsets: [String: Double]
    private var lyricSelections: [String: String]
    private var discordPrivateTrackFingerprints: Set<String>

    var lyricsFontSize: Double {
        didSet {
            lyricsFontSize = Self.clampLyricsFontSize(lyricsFontSize)
            defaults.set(lyricsFontSize, forKey: Self.lyricsFontSizeKey)
        }
    }

    var overlayPreset: OverlayPreset {
        didSet {
            defaults.set(overlayPreset.rawValue, forKey: Self.overlayPresetKey)
        }
    }

    var karaokeModeEnabled: Bool {
        didSet {
            defaults.set(karaokeModeEnabled, forKey: Self.karaokeModeEnabledKey)
        }
    }

    var showsRomanizedLyrics: Bool {
        didSet {
            defaults.set(showsRomanizedLyrics, forKey: Self.showsRomanizedLyricsKey)
        }
    }

    var showsTranslatedLyrics: Bool {
        didSet {
            defaults.set(showsTranslatedLyrics, forKey: Self.showsTranslatedLyricsKey)
        }
    }

    var translationTargetLanguage: LyricTranslationLanguage {
        didSet {
            defaults.set(
                translationTargetLanguage.rawValue,
                forKey: Self.translationTargetLanguageKey
            )
        }
    }

    var translationTone: LyricTranslationTone {
        didSet {
            defaults.set(translationTone.rawValue, forKey: Self.translationToneKey)
        }
    }

    var appLanguage: AppLanguage {
        didSet {
            defaults.set(appLanguage.rawValue, forKey: Self.appLanguageKey)
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

    var discordPresenceConfiguration: DiscordPresenceConfiguration {
        didSet {
            defaults.set(
                discordPresenceConfiguration.detailsTemplate,
                forKey: Self.discordDetailsTemplateKey
            )
            defaults.set(
                discordPresenceConfiguration.stateTemplate,
                forKey: Self.discordStateTemplateKey
            )
            defaults.set(
                discordPresenceConfiguration.imageTextTemplate,
                forKey: Self.discordImageTextTemplateKey
            )
            defaults.set(
                discordPresenceConfiguration.showsPlaybackTime,
                forKey: Self.discordShowsPlaybackTimeKey
            )
            defaults.set(
                discordPresenceConfiguration.showsSongLink,
                forKey: Self.discordShowsSongLinkKey
            )
            defaults.set(
                discordPresenceConfiguration.preset.rawValue,
                forKey: Self.discordPresetKey
            )
            defaults.set(
                discordPresenceConfiguration.pausePolicy.rawValue,
                forKey: Self.discordPausePolicyKey
            )
            defaults.set(
                discordPresenceConfiguration.linksDetailsToSong,
                forKey: Self.discordLinksDetailsToSongKey
            )
            defaults.set(
                discordPresenceConfiguration.linksStateToSong,
                forKey: Self.discordLinksStateToSongKey
            )
            defaults.set(
                discordPresenceConfiguration.linksCoverToSong,
                forKey: Self.discordLinksCoverToSongKey
            )
            defaults.set(
                discordPresenceConfiguration.primaryButtonLabel,
                forKey: Self.discordPrimaryButtonLabelKey
            )
            defaults.set(
                discordPresenceConfiguration.secondaryButtonLabel,
                forKey: Self.discordSecondaryButtonLabelKey
            )
            defaults.set(
                discordPresenceConfiguration.secondaryButtonURL,
                forKey: Self.discordSecondaryButtonURLKey
            )
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedFontSize = defaults.object(forKey: Self.lyricsFontSizeKey) as? Double
        lyricsFontSize = Self.clampLyricsFontSize(
            storedFontSize ?? Self.defaultLyricsFontSize
        )
        overlayPreset = OverlayPreset(
            rawValue: defaults.string(forKey: Self.overlayPresetKey) ?? ""
        ) ?? .balanced
        karaokeModeEnabled =
            defaults.object(forKey: Self.karaokeModeEnabledKey) as? Bool ?? false
        showsRomanizedLyrics =
            defaults.object(forKey: Self.showsRomanizedLyricsKey) as? Bool ?? false
        showsTranslatedLyrics =
            defaults.object(forKey: Self.showsTranslatedLyricsKey) as? Bool ?? false
        translationTargetLanguage = LyricTranslationLanguage(
            rawValue: defaults.string(forKey: Self.translationTargetLanguageKey) ?? ""
        ) ?? .system
        translationTone = LyricTranslationTone(
            rawValue: defaults.string(forKey: Self.translationToneKey) ?? ""
        ) ?? .naturalLyrics
        appLanguage = AppLanguage(
            rawValue: defaults.string(forKey: Self.appLanguageKey) ?? ""
        ) ?? .system
        displayMetadataSource = MetadataSourcePreference(
            rawValue: defaults.string(forKey: Self.displayMetadataSourceKey) ?? ""
        ) ?? .youtubeMusic
        discordMetadataSource = MetadataSourcePreference(
            rawValue: defaults.string(forKey: Self.discordMetadataSourceKey) ?? ""
        ) ?? .youtubeMusic
        let standardPresence = DiscordPresenceConfiguration.standard
        discordPresenceConfiguration = DiscordPresenceConfiguration(
            detailsTemplate: defaults.string(forKey: Self.discordDetailsTemplateKey)
                ?? standardPresence.detailsTemplate,
            stateTemplate: defaults.string(forKey: Self.discordStateTemplateKey)
                ?? standardPresence.stateTemplate,
            imageTextTemplate: defaults.string(forKey: Self.discordImageTextTemplateKey)
                ?? standardPresence.imageTextTemplate,
            showsPlaybackTime: defaults.object(forKey: Self.discordShowsPlaybackTimeKey) as? Bool
                ?? standardPresence.showsPlaybackTime,
            showsSongLink: defaults.object(forKey: Self.discordShowsSongLinkKey) as? Bool
                ?? standardPresence.showsSongLink,
            preset: DiscordPresencePreset(
                rawValue: defaults.string(forKey: Self.discordPresetKey) ?? ""
            ) ?? standardPresence.preset,
            pausePolicy: DiscordPausePolicy(
                rawValue: defaults.string(forKey: Self.discordPausePolicyKey) ?? ""
            ) ?? standardPresence.pausePolicy,
            linksDetailsToSong: defaults.object(
                forKey: Self.discordLinksDetailsToSongKey
            ) as? Bool ?? standardPresence.linksDetailsToSong,
            linksStateToSong: defaults.object(
                forKey: Self.discordLinksStateToSongKey
            ) as? Bool ?? standardPresence.linksStateToSong,
            linksCoverToSong: defaults.object(
                forKey: Self.discordLinksCoverToSongKey
            ) as? Bool ?? standardPresence.linksCoverToSong,
            primaryButtonLabel: defaults.string(
                forKey: Self.discordPrimaryButtonLabelKey
            ) ?? standardPresence.primaryButtonLabel,
            secondaryButtonLabel: defaults.string(
                forKey: Self.discordSecondaryButtonLabelKey
            ) ?? standardPresence.secondaryButtonLabel,
            secondaryButtonURL: defaults.string(
                forKey: Self.discordSecondaryButtonURLKey
            ) ?? standardPresence.secondaryButtonURL
        )
        trackOffsets = (defaults.dictionary(forKey: Self.trackOffsetsKey) ?? [:])
            .compactMapValues { ($0 as? NSNumber)?.doubleValue }
        lyricSelections = defaults.dictionary(forKey: Self.lyricSelectionsKey) as? [String: String] ?? [:]
        discordPrivateTrackFingerprints = Set(
            defaults.stringArray(forKey: Self.discordPrivateTrackFingerprintsKey) ?? []
        )
        defaults.removeObject(forKey: Self.learnedOffsetKey)
    }

    func timingOffset(for trackKey: String) -> Double {
        trackOffsets[trackKey] ?? 0
    }

    mutating func saveTimingOffset(_ offset: Double, for trackKey: String) {
        trackOffsets[trackKey] = offset
        defaults.set(trackOffsets, forKey: Self.trackOffsetsKey)
    }

    mutating func resetTimingOffset(for trackKey: String) {
        trackOffsets.removeValue(forKey: trackKey)
        if trackOffsets.isEmpty {
            defaults.removeObject(forKey: Self.trackOffsetsKey)
        } else {
            defaults.set(trackOffsets, forKey: Self.trackOffsetsKey)
        }
    }

    mutating func resetAllTimingOffsets() {
        trackOffsets.removeAll()
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

    mutating func resetDiscordPresenceConfiguration() {
        discordPresenceConfiguration = .standard
        [
            Self.discordDetailsTemplateKey,
            Self.discordStateTemplateKey,
            Self.discordImageTextTemplateKey,
            Self.discordShowsPlaybackTimeKey,
            Self.discordShowsSongLinkKey,
            Self.discordPresetKey,
            Self.discordPausePolicyKey,
            Self.discordLinksDetailsToSongKey,
            Self.discordLinksStateToSongKey,
            Self.discordLinksCoverToSongKey,
            Self.discordPrimaryButtonLabelKey,
            Self.discordSecondaryButtonLabelKey,
            Self.discordSecondaryButtonURLKey,
        ].forEach(defaults.removeObject(forKey:))
    }

    func isDiscordTrackPrivate(identifier: String) -> Bool {
        discordPrivateTrackFingerprints.contains(Self.fingerprint(identifier))
    }

    var privateDiscordTrackCount: Int {
        discordPrivateTrackFingerprints.count
    }

    mutating func setDiscordTrackPrivate(_ isPrivate: Bool, identifier: String) {
        let fingerprint = Self.fingerprint(identifier)
        if isPrivate {
            discordPrivateTrackFingerprints.insert(fingerprint)
        } else {
            discordPrivateTrackFingerprints.remove(fingerprint)
        }
        persistPrivateDiscordTracks()
    }

    mutating func clearPrivateDiscordTracks() {
        discordPrivateTrackFingerprints.removeAll()
        defaults.removeObject(forKey: Self.discordPrivateTrackFingerprintsKey)
    }

    private static func clampLyricsFontSize(_ value: Double) -> Double {
        min(maximumLyricsFontSize, max(minimumLyricsFontSize, value))
    }

    private static func fingerprint(_ identifier: String) -> String {
        SHA256.hash(data: Data(identifier.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func persistPrivateDiscordTracks() {
        if discordPrivateTrackFingerprints.isEmpty {
            defaults.removeObject(forKey: Self.discordPrivateTrackFingerprintsKey)
        } else {
            defaults.set(
                discordPrivateTrackFingerprints.sorted(),
                forKey: Self.discordPrivateTrackFingerprintsKey
            )
        }
    }
}
