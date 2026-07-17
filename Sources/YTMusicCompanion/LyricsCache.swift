import Foundation
import CryptoKit

struct LyricsCacheStatistics: Equatable {
    let fileCount: Int
    let totalBytes: Int

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(totalBytes), countStyle: .file)
    }
}

/// On-disk persistence for resolved lyrics, layered behind `PlayerModel`'s
/// in-memory `lyricsCache`. We mostly replay our own library, and LRCLIB is
/// often slow (and 504s under concurrent load), so a track resolved once should
/// load instantly — and offline — on every later play, across app restarts.
///
/// One JSON file per track under Caches, named by a SHA-256 of the `trackKey`
/// (which is free-form `"artist|title|album"` and can't be a filename directly). This
/// is a generic key→`[LyricLine]` store; the *policy* of what's worth persisting
/// lives in the caller (`PlayerModel`), which writes only tracks it actually
/// found lyrics for — real lyrics never go stale, whereas an empty result can
/// (a new release gets lyrics added later), so empties stay in memory only and
/// transient failures (504/non-JSON/network) are never written at all.
///
/// Caches (not Application Support) is deliberate: this is re-derivable data, so
/// it's fine for the OS to purge it under disk pressure — we just refetch.
enum LyricsCache {
    private static let maximumFileCount = 1_000
    private static let maximumTotalBytes = 50 * 1_024 * 1_024

    /// Storage directory override for tests. nil → the default Caches location.
    static var overrideDirectory: URL?

    /// The default Caches location, resolved and created exactly once per process
    /// (lazy `static let` is thread-safe). nil only if the Caches directory itself
    /// can't be located, in which case caching no-ops silently.
    private static let defaultDirectory: URL? = {
        guard let base = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent(
            "\(AppConfiguration.cacheDirectoryName)/lyrics",
            isDirectory: true
        )
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Resolve (and ensure) the cache directory. The default path is created once
    /// (above); a test `overrideDirectory` is created on demand since it changes
    /// per test. Returns nil only when no Caches directory exists.
    private static func directory() -> URL? {
        guard let dir = overrideDirectory else { return defaultDirectory }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func fileURL(for trackKey: String) -> URL? {
        guard let dir = directory() else { return nil }
        let digest = SHA256.hash(data: Data(trackKey.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return dir.appendingPathComponent(name).appendingPathExtension("json")
    }

    /// The cached lyrics for a track, or nil if no result was ever stored for it.
    /// A stored empty array is a real cached answer ("no synced lyrics") and
    /// returns `[]`; only a missing/unreadable file returns nil. Reading a small
    /// JSON file is cheap enough to call on the main thread on a track change.
    static func load(_ trackKey: String) -> [LyricLine]? {
        guard let url = fileURL(for: trackKey),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([LyricLine].self, from: data)
    }

    /// Persist a definitive result (lyrics, or a genuine empty). Best-effort and
    /// atomic: a write failure just means the next session refetches.
    static func save(_ lines: [LyricLine], for trackKey: String) {
        guard let url = fileURL(for: trackKey),
              let data = try? JSONEncoder().encode(lines) else { return }
        try? data.write(to: url, options: .atomic)
        pruneIfNeeded()
    }

    static func statistics() -> LyricsCacheStatistics {
        let files = cachedFiles()
        return LyricsCacheStatistics(
            fileCount: files.count,
            totalBytes: files.reduce(0) { $0 + $1.size }
        )
    }

    static func clear() {
        cachedFiles().forEach { try? FileManager.default.removeItem(at: $0.url) }
    }

    private struct CachedFile {
        let url: URL
        let size: Int
        let modifiedAt: Date
    }

    private static func cachedFiles() -> [CachedFile] {
        guard let directory = directory() else { return [] }
        let keys: Set<URLResourceKey> = [
            .contentModificationDateKey,
            .fileSizeKey,
            .isRegularFileKey,
        ]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return urls.compactMap { url in
            guard url.pathExtension == "json",
                  let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true else { return nil }
            return CachedFile(
                url: url,
                size: values.fileSize ?? 0,
                modifiedAt: values.contentModificationDate ?? .distantPast
            )
        }
    }

    private static func pruneIfNeeded() {
        var files = cachedFiles().sorted { $0.modifiedAt < $1.modifiedAt }
        var totalBytes = files.reduce(0) { $0 + $1.size }

        while files.count > maximumFileCount || totalBytes > maximumTotalBytes {
            let oldest = files.removeFirst()
            try? FileManager.default.removeItem(at: oldest.url)
            totalBytes = max(0, totalBytes - oldest.size)
        }
    }
}
