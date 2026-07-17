import Foundation

protocol ArtworkResolving: Sendable {
    func coverURL(for track: NowPlaying, sourceArtwork: NowPlayingArtwork) -> String?
    func coverURL(
        for track: NowPlaying,
        sourceArtwork: NowPlayingArtwork,
        cancellation: CancellationToken
    ) -> String?
}

extension ArtworkResolving {
    func coverURL(
        for track: NowPlaying,
        sourceArtwork: NowPlayingArtwork,
        cancellation: CancellationToken
    ) -> String? {
        guard !cancellation.isCancelled else { return nil }
        return coverURL(for: track, sourceArtwork: sourceArtwork)
    }
}

/// Converts YouTube Music snapshots into Discord activity and owns delivery state.
/// A failed send is deliberately not deduplicated, so launching Discord later causes
/// the next poll to retry the same track.
@MainActor
final class DiscordPresenceController {
    private let publisher: PresencePublishing
    private let artworkResolver: ArtworkResolving

    private var lastTrack: NowPlaying?
    private var lastArtwork: NowPlayingArtwork?
    private var lastConfiguration = DiscordPresenceConfiguration.standard
    private var lastPublishedKey: String?
    private var lastPublishedStart: Double = 0
    private var pendingKey: String?
    private var stateVersion = 0

    private var artworkCache = LRUCache<String, String>(
        capacity: SessionCacheLimits.discordArtwork
    )
    private var artworkMisses = BoundedSet<String>(
        capacity: SessionCacheLimits.negativeResults
    )
    private var artworkOperation: CancellableTaskOperation?
    private var pauseTimer: Timer?

    private(set) var connectionStatus: DiscordConnectionStatus
    var onConnectionStatusChange: ((DiscordConnectionStatus) -> Void)?

    init(
        publisher: PresencePublishing,
        artworkResolver: ArtworkResolving = VerifiedArtworkResolver()
    ) {
        self.publisher = publisher
        self.artworkResolver = artworkResolver
        connectionStatus = publisher.connectionStatus
        publisher.setConnectionStatusHandler { [weak self] status in
            Task { @MainActor in
                guard let self else { return }
                self.connectionStatus = status
                self.onConnectionStatusChange?(status)
            }
        }
    }

    var isConfigured: Bool { publisher.isConfigured }

    func update(
        for track: NowPlaying,
        sourceArtwork: NowPlayingArtwork? = nil,
        configuration: DiscordPresenceConfiguration = .standard
    ) {
        let previousTrackKey = lastTrack?.trackKey
        lastTrack = track
        lastArtwork = sourceArtwork
        lastConfiguration = configuration
        guard track.isPlaying, track.rate > 0 else {
            handlePausedTrack(
                track,
                previousTrackKey: previousTrackKey,
                policy: configuration.pausePolicy
            )
            return
        }
        cancelPauseTimer()

        let reference = track.timestamp > 0
            ? track.timestamp
            : Date().timeIntervalSince1970
        let startEpoch = reference - track.elapsed
        let artworkURL = resolvedArtwork(for: track, sourceArtwork: sourceArtwork)
        let publicationKey = [
            track.trackKey,
            track.duration > 0 ? "duration" : "no-duration",
            track.trackURL?.absoluteString ?? "no-link",
            artworkURL ?? "fallback",
            configuration.publicationKey,
        ].joined(separator: "|")
        let seeked = track.timestamp > 0 && abs(startEpoch - lastPublishedStart) > 3

        guard pendingKey != publicationKey else { return }
        guard publicationKey != lastPublishedKey || seeked else { return }

        let activity = makeActivity(
            for: track,
            startEpoch: startEpoch,
            artworkURL: artworkURL,
            configuration: configuration
        )
        publish(activity, publicationKey: publicationKey, startEpoch: startEpoch)
    }

    func publishManual(_ activity: PresenceActivity, sessionKey: String) {
        cancelPauseTimer()
        artworkOperation?.cancel()
        artworkOperation = nil
        stateVersion += 1
        pendingKey = nil
        lastTrack = nil
        lastArtwork = nil
        lastConfiguration = .standard
        let publicationKey = "manual|\(sessionKey)"
        guard pendingKey != publicationKey, lastPublishedKey != publicationKey else { return }
        publish(
            activity,
            publicationKey: publicationKey,
            startEpoch: activity.start?.timeIntervalSince1970 ?? 0
        )
    }

    func clear() {
        cancelPauseTimer()
        artworkOperation?.cancel()
        artworkOperation = nil
        let hadPublishedOrPendingActivity = lastPublishedKey != nil || pendingKey != nil
        stateVersion += 1
        lastTrack = nil
        lastArtwork = nil
        lastConfiguration = .standard
        pendingKey = nil
        lastPublishedKey = nil
        lastPublishedStart = 0
        guard hadPublishedOrPendingActivity else { return }
        publisher.clear()
    }

    func disconnect() {
        clear()
        publisher.disconnect()
    }

    private func makeActivity(
        for track: NowPlaying,
        startEpoch: Double,
        artworkURL: String?,
        configuration: DiscordPresenceConfiguration
    ) -> PresenceActivity {
        let end = configuration.showsPlaybackTime && track.duration > 0
            ? Date(timeIntervalSince1970: startEpoch + track.duration)
            : nil
        let start = configuration.showsPlaybackTime
            ? Date(timeIntervalSince1970: startEpoch)
            : nil
        let title = track.artist.isEmpty
            ? track.title
            : "\(track.title) - \(track.artist)"
        let image = artworkURL ?? YouTubeMusicSource.discordAssetKey
        let content = configuration.content(for: track)
        let links = configuration.links(for: track)

        return PresenceActivity(
            name: title,
            details: content.details,
            state: content.state,
            start: start,
            end: end,
            largeImage: image,
            largeImageText: content.imageText,
            smallImage: YouTubeMusicSource.discordAssetKey,
            smallImageText: YouTubeMusicSource.displayName,
            detailsURL: links.detailsURL,
            stateURL: links.stateURL,
            largeImageURL: links.coverURL,
            smallImageURL: nil,
            buttons: links.buttons
        )
    }

    private func publish(
        _ activity: PresenceActivity,
        publicationKey: String,
        startEpoch: Double
    ) {
        guard pendingKey != publicationKey else { return }
        guard lastPublishedKey != publicationKey else { return }
        pendingKey = publicationKey
        let version = stateVersion

        publisher.setActivity(activity) { [weak self] sent in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self,
                          self.stateVersion == version,
                          self.pendingKey == publicationKey else { return }
                    self.pendingKey = nil
                    guard sent else { return }
                    self.lastPublishedKey = publicationKey
                    self.lastPublishedStart = startEpoch
                }
            }
        }
    }

    private func handlePausedTrack(
        _ track: NowPlaying,
        previousTrackKey: String?,
        policy: DiscordPausePolicy
    ) {
        if let previousTrackKey, previousTrackKey != track.trackKey {
            clear()
            return
        }

        switch policy {
        case .hideImmediately:
            clear()
        case .keepVisible:
            cancelPauseTimer()
        case .keepForFiveMinutes, .keepForFifteenMinutes:
            guard pauseTimer == nil,
                  lastPublishedKey != nil || pendingKey != nil,
                  let interval = policy.retentionInterval
            else {
                return
            }
            pauseTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) {
                [weak self] _ in
                Task { @MainActor in
                    self?.clear()
                }
            }
        }
    }

    private func cancelPauseTimer() {
        pauseTimer?.invalidate()
        pauseTimer = nil
    }

    private func resolvedArtwork(
        for track: NowPlaying,
        sourceArtwork: NowPlayingArtwork?
    ) -> String? {
        guard let sourceArtwork else { return nil }
        let cacheKey = "\(track.trackKey)|\(sourceArtwork.memoryCacheKey)"
        if let cached = artworkCache[cacheKey] {
            return cached
        }
        guard
            !artworkMisses.contains(cacheKey),
            artworkOperation?.key != cacheKey
        else { return nil }

        artworkOperation?.cancel()
        let resolver = artworkResolver
        let operationID = UUID()
        let cancellation = CancellationToken()
        let operation = CancellableTaskOperation(
            id: operationID,
            key: cacheKey,
            cancellation: cancellation
        )
        artworkOperation = operation
        let task = Task.detached(priority: .utility) {
            let url = resolver.coverURL(
                for: track,
                sourceArtwork: sourceArtwork,
                cancellation: cancellation
            )
            await self.finishArtworkResolution(
                url,
                track: track,
                sourceArtwork: sourceArtwork,
                cacheKey: cacheKey,
                operationID: operationID,
                wasCancelled: cancellation.isCancelled
            )
        }
        operation.attach(task)
        return nil
    }

    private func finishArtworkResolution(
        _ url: String?,
        track: NowPlaying,
        sourceArtwork: NowPlayingArtwork,
        cacheKey: String,
        operationID: UUID,
        wasCancelled: Bool
    ) {
        guard artworkOperation?.id == operationID else { return }
        artworkOperation = nil
        guard !wasCancelled else { return }

        if let url {
            artworkCache[cacheKey] = url
        } else {
            artworkMisses.insert(cacheKey)
        }
        guard
            url != nil,
            lastTrack?.trackKey == track.trackKey,
            lastArtwork?.memoryCacheKey == sourceArtwork.memoryCacheKey
        else { return }
        lastPublishedKey = nil
        update(
            for: track,
            sourceArtwork: sourceArtwork,
            configuration: lastConfiguration
        )
    }
}
