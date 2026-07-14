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
    private static var processCache: [Int32: CacheEntry] = [:]

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
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-p", String(pid), "-o", "args="]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }

        let watchdog = DispatchWorkItem { process.terminate() }
        DispatchQueue.global().asyncAfter(deadline: .now() + 2, execute: watchdog)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()
        return String(data: data, encoding: .utf8)
    }
}
