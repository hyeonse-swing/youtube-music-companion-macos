import Foundation

/// Recognizes the installed YouTube Music web app while rejecting every other
/// system media source. A regular browser tab is intentionally not accepted because
/// MediaRemote only reports the browser bundle, which is not enough to distinguish
/// YouTube Music from arbitrary videos.
enum YouTubeMusicSource {
    static let discordAssetKey = "youtube-music"
    static let displayName = "YouTube Music"

    private static let extensionID = "cinhimbnkkaeohfgghhklpknlkffjgod"
    private static let legacyLoaderBundle = "app_mode_loader"
    private static let cacheTTL: TimeInterval = 30

    private struct CacheEntry {
        let isYouTubeMusic: Bool
        let createdAt: Date
    }

    private static let cacheLock = NSLock()
    private static var processCache = LRUCache<Int32, CacheEntry>(
        capacity: SessionCacheLimits.processIdentity
    )

    static func matches(bundle: String, pid: Int32) -> Bool {
        if bundle.hasSuffix(".\(extensionID)") {
            return true
        }

        guard bundle == legacyLoaderBundle, pid > 0 else {
            return false
        }
        return isLegacyYouTubeMusicProcess(pid: pid)
    }

    private static func isLegacyYouTubeMusicProcess(pid: Int32) -> Bool {
        let now = Date()
        cacheLock.lock()
        if let cached = processCache[pid], now.timeIntervalSince(cached.createdAt) < cacheTTL {
            cacheLock.unlock()
            return cached.isYouTubeMusic
        }
        cacheLock.unlock()

        let isYouTubeMusic = processArguments(pid: pid)?
            .localizedCaseInsensitiveContains("youtube music.app") ?? false

        cacheLock.lock()
        processCache[pid] = CacheEntry(isYouTubeMusic: isYouTubeMusic, createdAt: now)
        cacheLock.unlock()
        return isYouTubeMusic
    }

    private static func processArguments(pid: Int32) -> String? {
        guard let result = SubprocessRunner.run(
            executable: "/bin/ps",
            arguments: ["-p", String(pid), "-o", "args="],
            timeout: 2,
            maximumOutputBytes: 64 * 1_024,
            cancellation: CancellationToken()
        ), result.succeeded else { return nil }
        return String(data: result.output, encoding: .utf8)
    }
}
