import CryptoKit
import Foundation

/// Re-derivable, per-song translations. Source lyrics are fingerprinted so a
/// different LRC version or edited local file can never receive stale text.
enum LyricTranslationCache {
    private static let maximumFileCount = 500
    private static let maximumTotalBytes = 25 * 1_024 * 1_024
    private static let statisticsLock = NSLock()
    private static var cachedStatistics: LyricsCacheStatistics?

    static var overrideDirectory: URL? {
        didSet { invalidateStatistics() }
    }

    private struct Entry: Codable {
        let sourceFingerprint: String
        let targetLanguage: String
        let tone: String
        let translations: [String]
    }

    private static let defaultDirectory: URL? = {
        guard let base = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask).first
        else { return nil }
        let directory = base.appendingPathComponent(
            "\(AppConfiguration.cacheDirectoryName)/translated-lyrics",
            isDirectory: true
        )
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }()

    static func load(
        for trackKey: String,
        targetLanguage: String,
        tone: LyricTranslationTone,
        sourceLines: [LyricLine]
    ) -> [String]? {
        guard
            let url = fileURL(
                for: trackKey,
                targetLanguage: targetLanguage,
                tone: tone
            ),
            let data = try? Data(contentsOf: url)
        else { return nil }

        guard
            let entry = try? JSONDecoder().decode(Entry.self, from: data),
            entry.targetLanguage == targetLanguage,
            entry.tone == tone.rawValue,
            entry.sourceFingerprint == fingerprint(sourceLines),
            entry.translations.count == sourceLines.count
        else {
            statisticsLock.withLock {
                try? FileManager.default.removeItem(at: url)
                cachedStatistics = nil
            }
            return nil
        }
        return entry.translations
    }

    static func save(
        _ translations: [String],
        for trackKey: String,
        targetLanguage: String,
        tone: LyricTranslationTone,
        sourceLines: [LyricLine]
    ) {
        guard translations.count == sourceLines.count,
              let url = fileURL(
                  for: trackKey,
                  targetLanguage: targetLanguage,
                  tone: tone
              )
        else { return }
        let entry = Entry(
            sourceFingerprint: fingerprint(sourceLines),
            targetLanguage: targetLanguage,
            tone: tone.rawValue,
            translations: translations
        )
        guard let data = encodedData(entry) else { return }
        if let existing = try? Data(contentsOf: url), existing == data {
            return
        }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            return
        }
        statisticsLock.withLock {
            cachedStatistics = nil
            pruneIfNeededLocked()
        }
    }

    static func clear() {
        statisticsLock.withLock {
            cachedFiles().forEach { try? FileManager.default.removeItem(at: $0.url) }
            cachedStatistics = nil
        }
    }

    static func statistics() -> LyricsCacheStatistics {
        statisticsLock.withLock {
            if let cachedStatistics {
                return cachedStatistics
            }
            let files = cachedFiles()
            let statistics = LyricsCacheStatistics(
                fileCount: files.count,
                totalBytes: files.reduce(0) { $0 + $1.size }
            )
            cachedStatistics = statistics
            return statistics
        }
    }

    private static func directory() -> URL? {
        guard let directory = overrideDirectory else { return defaultDirectory }
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    private static func fileURL(
        for trackKey: String,
        targetLanguage: String,
        tone: LyricTranslationTone
    ) -> URL? {
        guard let directory = directory() else { return nil }
        let key = "\(trackKey)|\(targetLanguage)|\(tone.rawValue)"
        return directory
            .appendingPathComponent(hexDigest(Data(key.utf8)))
            .appendingPathExtension("json")
    }

    private static func fingerprint(_ lines: [LyricLine]) -> String {
        guard let data = encodedData(lines) else { return "" }
        return hexDigest(data)
    }

    private static func hexDigest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
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
                  values.isRegularFile == true
            else { return nil }
            return CachedFile(
                url: url,
                size: values.fileSize ?? 0,
                modifiedAt: values.contentModificationDate ?? .distantPast
            )
        }
    }

    /// Caller must hold `statisticsLock` so an older directory scan cannot
    /// overwrite statistics produced by a newer save or clear.
    private static func pruneIfNeededLocked() {
        var files = cachedFiles()
        var totalBytes = files.reduce(0) { $0 + $1.size }
        guard files.count > maximumFileCount || totalBytes > maximumTotalBytes else {
            cachedStatistics = LyricsCacheStatistics(
                fileCount: files.count,
                totalBytes: totalBytes
            )
            return
        }

        files.sort { $0.modifiedAt < $1.modifiedAt }
        var remainingFileCount = files.count
        var index = 0
        while
            (remainingFileCount > maximumFileCount || totalBytes > maximumTotalBytes),
            index < files.count
        {
            let oldest = files[index]
            index += 1
            do {
                try FileManager.default.removeItem(at: oldest.url)
                remainingFileCount -= 1
                totalBytes = max(0, totalBytes - oldest.size)
            } catch {
                continue
            }
        }
        cachedStatistics = LyricsCacheStatistics(
            fileCount: remainingFileCount,
            totalBytes: totalBytes
        )
    }

    private static func invalidateStatistics() {
        statisticsLock.withLock { cachedStatistics = nil }
    }

    private static func encodedData<T: Encodable>(_ value: T) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(value)
    }
}
