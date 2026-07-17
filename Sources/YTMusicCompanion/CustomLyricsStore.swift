import CryptoKit
import Foundation

struct CustomLyricsDocument: Codable, Equatable {
    let sourceName: String
    let lines: [LyricLine]
}

/// User-owned lyrics are kept in Application Support, separately from the
/// re-downloadable LRCLIB cache. Clearing cached lyrics must never remove a file
/// the user explicitly attached to a song.
enum CustomLyricsStore {
    static var overrideDirectory: URL?

    private static let defaultDirectory: URL? = {
        guard let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let directory = base
            .appendingPathComponent(AppConfiguration.cacheDirectoryName, isDirectory: true)
            .appendingPathComponent("custom-lyrics", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }()

    static func load(_ trackKey: String) -> CustomLyricsDocument? {
        guard
            let url = try? fileURL(for: trackKey),
            let data = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONDecoder().decode(CustomLyricsDocument.self, from: data)
    }

    static func save(_ document: CustomLyricsDocument, for trackKey: String) throws {
        let data = try JSONEncoder().encode(document)
        try data.write(to: fileURL(for: trackKey), options: .atomic)
    }

    static func remove(for trackKey: String) throws {
        let url = try fileURL(for: trackKey)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    private static func fileURL(for trackKey: String) throws -> URL {
        guard let directory = try directory() else {
            throw CocoaError(.fileNoSuchFile)
        }
        let digest = SHA256.hash(data: Data(trackKey.utf8))
        let filename = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(filename).appendingPathExtension("json")
    }

    private static func directory() throws -> URL? {
        guard let overrideDirectory else { return defaultDirectory }
        try FileManager.default.createDirectory(
            at: overrideDirectory,
            withIntermediateDirectories: true
        )
        return overrideDirectory
    }
}
