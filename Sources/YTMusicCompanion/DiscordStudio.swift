import Foundation

enum DiscordPresencePreset: String, CaseIterable, Identifiable {
    case originalFirst
    case titleFocused
    case artistFocused
    case minimal
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .originalFirst: "Original First"
        case .titleFocused: "Title Focused"
        case .artistFocused: "Artist Focused"
        case .minimal: "Minimal"
        case .custom: "Custom"
        }
    }

    var helpText: String {
        switch self {
        case .originalFirst:
            "Shows the source title, artist, and album without rewriting them."
        case .titleFocused:
            "Emphasizes the song title while retaining the artist and album."
        case .artistFocused:
            "Leads with the artist and places the title in the status line."
        case .minimal:
            "Shows only the title and artist, without time or links."
        case .custom:
            "Uses your own detail and status templates."
        }
    }

    func applying(to configuration: DiscordPresenceConfiguration) -> DiscordPresenceConfiguration {
        var result = configuration
        result.preset = self

        switch self {
        case .originalFirst:
            result.detailsTemplate = "{title}"
            result.stateTemplate = "{artist}"
            result.imageTextTemplate = "{album}"
            result.showsPlaybackTime = true
            result.showsSongLink = true
        case .titleFocused:
            result.detailsTemplate = "♫ {title}"
            result.stateTemplate = "{artist} · {album}"
            result.imageTextTemplate = "{album}"
            result.showsPlaybackTime = true
            result.showsSongLink = true
        case .artistFocused:
            result.detailsTemplate = "{artist}"
            result.stateTemplate = "{title}"
            result.imageTextTemplate = "{album}"
            result.showsPlaybackTime = true
            result.showsSongLink = true
        case .minimal:
            result.detailsTemplate = "{title}"
            result.stateTemplate = "{artist}"
            result.imageTextTemplate = "{album}"
            result.showsPlaybackTime = false
            result.showsSongLink = false
            result.linksDetailsToSong = false
            result.linksStateToSong = false
            result.linksCoverToSong = false
            result.secondaryButtonLabel = ""
            result.secondaryButtonURL = ""
        case .custom:
            break
        }

        return result
    }
}

enum DiscordPausePolicy: String, CaseIterable, Identifiable {
    case hideImmediately
    case keepForFiveMinutes
    case keepForFifteenMinutes
    case keepVisible

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hideImmediately: "Hide Immediately"
        case .keepForFiveMinutes: "Keep for 5 Minutes"
        case .keepForFifteenMinutes: "Keep for 15 Minutes"
        case .keepVisible: "Keep Until the Next Song"
        }
    }

    var retentionInterval: TimeInterval? {
        switch self {
        case .keepForFiveMinutes: 5 * 60
        case .keepForFifteenMinutes: 15 * 60
        case .hideImmediately, .keepVisible: nil
        }
    }
}

enum ManualPresenceLifetime: Int, CaseIterable, Identifiable {
    case fifteenMinutes = 15
    case thirtyMinutes = 30
    case oneHour = 60
    case twoHours = 120

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .fifteenMinutes: "15 Minutes"
        case .thirtyMinutes: "30 Minutes"
        case .oneHour: "1 Hour"
        case .twoHours: "2 Hours"
        }
    }

    var interval: TimeInterval { TimeInterval(rawValue * 60) }
}

enum DiscordURLValidator {
    static func httpsURL(_ rawValue: String) -> URL? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              value.utf8.count <= 512,
              let url = URL(string: value),
              url.scheme?.lowercased() == "https",
              url.host?.isEmpty == false
        else {
            return nil
        }
        return url
    }

    static func optionalURLIsValid(_ rawValue: String) -> Bool {
        rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || httpsURL(rawValue) != nil
    }
}

struct ManualDiscordPresence: Equatable {
    var title: String
    var artist: String
    var album: String
    var coverURL: String
    var songURL: String
    var durationMinutes: Int
    var showsPlaybackTime: Bool
    var lifetime: ManualPresenceLifetime
    var secondaryButtonLabel: String
    var secondaryButtonURL: String

    static let example = ManualDiscordPresence(
        title: "Sample Song",
        artist: "Sample Artist",
        album: "Sample Album",
        coverURL: "",
        songURL: "https://music.youtube.com/",
        durationMinutes: 4,
        showsPlaybackTime: true,
        lifetime: .thirtyMinutes,
        secondaryButtonLabel: "",
        secondaryButtonURL: ""
    )

    var validationMessage: String? {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Enter a song title."
        }
        if artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Enter an artist."
        }
        if !(1 ... 1_440).contains(durationMinutes) {
            return "Duration must be between 1 and 1,440 minutes."
        }
        if !DiscordURLValidator.optionalURLIsValid(coverURL) {
            return "Cover URL must be a valid HTTPS URL."
        }
        if !DiscordURLValidator.optionalURLIsValid(songURL) {
            return "Song URL must be a valid HTTPS URL."
        }

        let label = secondaryButtonLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = secondaryButtonURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if label.isEmpty != url.isEmpty {
            return "Enter both a secondary button label and URL."
        }
        if label.count > 32 {
            return "Button labels can contain up to 32 characters."
        }
        if !DiscordURLValidator.optionalURLIsValid(url) {
            return "Secondary button URL must be a valid HTTPS URL."
        }
        return nil
    }

    func activity(startedAt: Date) -> PresenceActivity? {
        guard validationMessage == nil else { return nil }

        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanAlbum = album.trimmingCharacters(in: .whitespacesAndNewlines)
        let songLink = DiscordURLValidator.httpsURL(songURL)
        let coverLink = DiscordURLValidator.httpsURL(coverURL)
        let secondaryLabel = secondaryButtonLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let secondaryLink = DiscordURLValidator.httpsURL(secondaryButtonURL)
        var buttons: [PresenceButton] = []

        if let songLink {
            buttons.append(PresenceButton(label: "Listen on YouTube Music", url: songLink))
        }
        if !secondaryLabel.isEmpty, let secondaryLink {
            buttons.append(PresenceButton(label: secondaryLabel, url: secondaryLink))
        }

        return PresenceActivity(
            name: cleanArtist.isEmpty ? cleanTitle : "\(cleanTitle) - \(cleanArtist)",
            details: cleanTitle,
            state: cleanArtist,
            start: showsPlaybackTime ? startedAt : nil,
            end: showsPlaybackTime
                ? startedAt.addingTimeInterval(TimeInterval(durationMinutes * 60))
                : nil,
            largeImage: coverLink?.absoluteString ?? YouTubeMusicSource.discordAssetKey,
            largeImageText: cleanAlbum.isEmpty ? cleanArtist : cleanAlbum,
            smallImage: YouTubeMusicSource.discordAssetKey,
            smallImageText: "Manual presence · YT Music Companion",
            detailsURL: songLink,
            stateURL: nil,
            largeImageURL: songLink,
            smallImageURL: nil,
            buttons: Array(buttons.prefix(2))
        )
    }
}

struct ManualDiscordPresenceSession: Equatable {
    var presence: ManualDiscordPresence
    var startedAt: Date
    var expiresAt: Date
    var sessionKey: String
}
