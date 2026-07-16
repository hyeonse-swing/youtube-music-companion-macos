import Foundation

enum AppConfiguration {
    static let productName = "YT Music Companion"
    static let bundleIdentifier = "com.hyeonseswing.YTMusicCompanion"
    static let repositoryURL = "https://github.com/hyeonse-swing/youtube-music-companion-macos"
    static let cacheDirectoryName = "YTMusicCompanion"
    static let userAgent = "youtube-music-companion-macos/0.8.1 (\(repositoryURL))"

    /// Discord application IDs are public identifiers, not secrets. Release builds
    /// receive the value through Info.plist; `swift run` can use the environment.
    static var discordClientID: String? {
        let environmentValue = ProcessInfo.processInfo.environment["DISCORD_CLIENT_ID"]
        let bundledValue = Bundle.main.object(forInfoDictionaryKey: "DiscordClientID") as? String
        return [environmentValue, bundledValue]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: isValidDiscordClientID)
    }

    private static func isValidDiscordClientID(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.allSatisfy { (48...57).contains($0) }
    }
}
