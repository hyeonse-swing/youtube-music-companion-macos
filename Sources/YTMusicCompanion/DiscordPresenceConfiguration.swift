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
        showsPlaybackTime: true
    )

    static let supportedTokens = ["{title}", "{artist}", "{album}"]

    var detailsTemplate: String
    var stateTemplate: String
    var imageTextTemplate: String
    var showsPlaybackTime: Bool

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
        ].joined(separator: "\u{1F}")
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
