import AppKit
import Darwin
import Foundation

/// Keeps hardware transport controls assigned to the installed music player.
/// No synthetic keys or playback commands are sent when claiming ownership.
@MainActor
final class SystemMediaPriority {
    private let setOverride: (String?) -> Void
    private let isRunning: (Int32) -> Bool
    private var selectedBundle: String?
    private var selectedPID: Int32 = 0

    init(
        setOverride: @escaping (String?) -> Void = SystemMediaPriority.setNativeOverride,
        isRunning: @escaping (Int32) -> Bool = {
            NSRunningApplication(processIdentifier: $0).map { !$0.isTerminated } ?? false
        }
    ) {
        self.setOverride = setOverride
        self.isRunning = isRunning
    }

    func update(_ source: NowPlaying?) {
        if let source,
           YouTubeMusicSource.matches(bundle: source.sourceBundle, pid: source.sourcePID),
           source.sourceBundle != "app_mode_loader", source.sourcePID > 0,
           isRunning(source.sourcePID) {
            selectedPID = source.sourcePID
            guard selectedBundle != source.sourceBundle else { return }
            selectedBundle = source.sourceBundle
            setOverride(source.sourceBundle)
        } else if selectedBundle != nil && !isRunning(selectedPID) {
            // A missing sample or pause must not give the headset back to a video.
            release()
        }
    }

    func release() {
        guard selectedBundle != nil else { return }
        setOverride(nil)
        selectedBundle = nil
        selectedPID = 0
    }

    private nonisolated static func setNativeOverride(_ bundle: String?) {
        // Resolve dynamically: unavailable private APIs must not prevent launch
        // on macOS 13 or a future OS. Return value is not a success indicator.
        guard let handle = dlopen(
            "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY
        ) else { return }
        defer { dlclose(handle) }
        guard let symbol = dlsym(handle, "MRMediaRemoteSetOverriddenNowPlayingApplication") else { return }
        typealias SetOverride = @convention(c) (CFString?) -> Int32
        let function = unsafeBitCast(symbol, to: SetOverride.self)
        _ = function(bundle.map { $0 as CFString })
    }
}
