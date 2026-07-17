import Foundation

struct DiscordPresenceContent: Equatable {
    let details: String
    let state: String
    let imageText: String
}

/// User-editable Discord text templates. Tokens deliberately mirror the three
/// metadata fields the app can verify, keeping customization predictable.
struct DiscordPresenceConfiguration: Equatable {
    static let standard = DiscordPresenceConfiguration(
        detailsTemplate: "{title}",
        stateTemplate: "{artist}",
        imageTextTemplate: "{album}",
        showsPlaybackTime: true,
        showsSongLink: true,
        preset: .originalFirst,
        pausePolicy: .hideImmediately,
        linksDetailsToSong: false,
        linksStateToSong: false,
        linksCoverToSong: true,
        primaryButtonLabel: "Listen on YouTube Music",
        secondaryButtonLabel: "",
        secondaryButtonURL: ""
    )

    static let supportedTokens = ["{title}", "{artist}", "{album}"]

    var detailsTemplate: String
    var stateTemplate: String
    var imageTextTemplate: String
    var showsPlaybackTime: Bool
    var showsSongLink: Bool = true
    var preset: DiscordPresencePreset = .originalFirst
    var pausePolicy: DiscordPausePolicy = .hideImmediately
    var linksDetailsToSong = false
    var linksStateToSong = false
    var linksCoverToSong = true
    var primaryButtonLabel = "Listen on YouTube Music"
    var secondaryButtonLabel = ""
    var secondaryButtonURL = ""

    func content(for track: NowPlaying) -> DiscordPresenceContent {
        DiscordPresenceContent(
            details: render(detailsTemplate, track: track, fallback: track.title),
            state: render(stateTemplate, track: track, fallback: track.artist),
            imageText: render(
                imageTextTemplate,
                track: track,
                fallback: track.album.isEmpty ? track.title : track.album
            )
        )
    }

    var publicationKey: String {
        [
            detailsTemplate,
            stateTemplate,
            imageTextTemplate,
            showsPlaybackTime ? "time" : "no-time",
            showsSongLink ? "link" : "no-link",
            preset.rawValue,
            pausePolicy.rawValue,
            linksDetailsToSong ? "details-link" : "no-details-link",
            linksStateToSong ? "state-link" : "no-state-link",
            linksCoverToSong ? "cover-link" : "no-cover-link",
            primaryButtonLabel,
            secondaryButtonLabel,
            secondaryButtonURL,
        ].joined(separator: "\u{1F}")
    }

    func links(for track: NowPlaying) -> DiscordPresenceLinks {
        let songURL = showsSongLink ? track.trackURL : nil
        let secondaryURL = DiscordURLValidator.httpsURL(secondaryButtonURL)
        let primaryLabel = primaryButtonLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let secondaryLabel = secondaryButtonLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        var buttons: [PresenceButton] = []

        if let songURL, !primaryLabel.isEmpty {
            buttons.append(PresenceButton(label: primaryLabel, url: songURL))
        }
        if let secondaryURL, !secondaryLabel.isEmpty {
            buttons.append(PresenceButton(label: secondaryLabel, url: secondaryURL))
        }

        return DiscordPresenceLinks(
            detailsURL: linksDetailsToSong ? songURL : nil,
            stateURL: linksStateToSong ? songURL : nil,
            coverURL: linksCoverToSong ? songURL : nil,
            buttons: Array(buttons.prefix(2))
        )
    }

    private func render(_ template: String, track: NowPlaying, fallback: String) -> String {
        let replacements = [
            "{title}": track.title,
            "{artist}": track.artist,
            "{album}": track.album,
        ]
        let rendered = replacements.reduce(template) { partial, replacement in
            partial.replacingOccurrences(of: replacement.key, with: replacement.value)
        }.trimmingCharacters(in: .whitespacesAndNewlines)
        return rendered.isEmpty ? fallback : rendered
    }
}

struct DiscordPresenceLinks: Equatable {
    var detailsURL: URL?
    var stateURL: URL?
    var coverURL: URL?
    var buttons: [PresenceButton]
}
