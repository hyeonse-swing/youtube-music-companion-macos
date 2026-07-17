import Foundation

enum PlaybackPollMode: String, Equatable {
    case playing
    case paused
    case idle

    var displayName: String {
        switch self {
        case .playing: "Playing"
        case .paused: "Paused"
        case .idle: "Idle"
        }
    }
}

enum PlaybackPollingSchedule {
    static let playingInterval: TimeInterval = 1
    static let pausedInterval: TimeInterval = 4
    static let idleInterval: TimeInterval = 10

    static func mode(for track: NowPlaying?) -> PlaybackPollMode {
        guard let track else { return .idle }
        return track.isPlaying && track.rate > 0 ? .playing : .paused
    }

    static func interval(for track: NowPlaying?) -> TimeInterval {
        switch mode(for: track) {
        case .playing: playingInterval
        case .paused: pausedInterval
        case .idle: idleInterval
        }
    }
}

enum DiscordConnectionStatus: String, Equatable {
    case notConfigured
    case disconnected
    case connecting
    case connected
    case publishing
    case published
    case retrying

    var displayName: String {
        switch self {
        case .notConfigured: "Not configured"
        case .disconnected: "Disconnected"
        case .connecting: "Connecting"
        case .connected: "Connected"
        case .publishing: "Publishing"
        case .published: "Published"
        case .retrying: "Retrying"
        }
    }

    var systemImage: String {
        switch self {
        case .notConfigured: "questionmark.circle"
        case .disconnected: "bolt.slash"
        case .connecting, .publishing, .retrying: "arrow.triangle.2.circlepath"
        case .connected, .published: "checkmark.circle"
        }
    }
}

struct PlayerRuntimeDiagnostics: Equatable {
    var pollMode: PlaybackPollMode = .idle
    var nextPollInterval: TimeInterval = PlaybackPollingSchedule.idleInterval
    var lastPollDate: Date?
    var lastPollDuration: TimeInterval?
    var activeOperations: [String] = []
    var subprocesses = SubprocessMetricsSnapshot(
        activeCount: 0,
        totalLaunches: 0,
        cancelledCount: 0,
        timedOutCount: 0
    )
    var metadataCacheEntries = 0
    var artworkCacheEntries = 0
    var lyricsCacheEntries = 0
    var lyricCandidateCacheEntries = 0
    var discordStatus: DiscordConnectionStatus = .disconnected
}

enum LyricTimeline {
    /// Last line whose timestamp is at or before `time`.
    static func index(at time: Double, in lines: [LyricLine]) -> Int {
        guard !lines.isEmpty else { return -1 }

        var lower = 0
        var upper = lines.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if lines[middle].time <= time {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower - 1
    }
}
