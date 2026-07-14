import Foundation

protocol ArtworkResolving: Sendable {
    func coverURL(for track: NowPlaying) -> String?
}

struct DefaultArtworkResolver: ArtworkResolving {
    func coverURL(for track: NowPlaying) -> String? {
        Artwork.coverURL(title: track.title, artist: track.artist, album: track.album)
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
    private var lastPublishedKey: String?
    private var lastPublishedStart: Double = 0
    private var pendingKey: String?
    private var stateVersion = 0

    private var artworkCache: [String: String?] = [:]
    private var artworkResolving: Set<String> = []

    init(
        publisher: PresencePublishing,
        artworkResolver: ArtworkResolving = DefaultArtworkResolver()
    ) {
        self.publisher = publisher
        self.artworkResolver = artworkResolver
    }

    var isConfigured: Bool { publisher.isConfigured }

    func update(for track: NowPlaying) {
        lastTrack = track
        guard track.isPlaying, track.rate > 0 else {
            clear()
            return
        }

        let reference = track.timestamp > 0
            ? track.timestamp
            : Date().timeIntervalSince1970
        let startEpoch = reference - track.elapsed
        let artworkURL = resolvedArtwork(for: track)
        let publicationKey = "\(track.trackKey)|\(track.duration > 0)|\(artworkURL != nil)"
        let seeked = track.timestamp > 0 && abs(startEpoch - lastPublishedStart) > 3

        guard pendingKey != publicationKey else { return }
        guard publicationKey != lastPublishedKey || seeked else { return }

        let activity = makeActivity(
            for: track,
            startEpoch: startEpoch,
            artworkURL: artworkURL
        )
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

    func clear() {
        let hadPublishedOrPendingActivity = lastPublishedKey != nil || pendingKey != nil
        stateVersion += 1
        lastTrack = nil
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
        artworkURL: String?
    ) -> PresenceActivity {
        let end = track.duration > 0
            ? Date(timeIntervalSince1970: startEpoch + track.duration)
            : nil
        let title = track.artist.isEmpty
            ? track.title
            : "\(track.title) - \(track.artist)"
        let image = artworkURL ?? YouTubeMusicSource.discordAssetKey
        let imageText = track.album.isEmpty ? track.title : track.album

        return PresenceActivity(
            name: title,
            details: track.title,
            state: track.artist,
            start: Date(timeIntervalSince1970: startEpoch),
            end: end,
            largeImage: image,
            largeImageText: imageText,
            smallImage: YouTubeMusicSource.discordAssetKey,
            smallImageText: YouTubeMusicSource.displayName
        )
    }

    private func resolvedArtwork(for track: NowPlaying) -> String? {
        if let cached = artworkCache[track.trackKey] {
            return cached
        }
        guard !artworkResolving.contains(track.trackKey) else { return nil }
        artworkResolving.insert(track.trackKey)

        let resolver = artworkResolver
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let url = resolver.coverURL(for: track)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.artworkResolving.remove(track.trackKey)
                    self.artworkCache[track.trackKey] = url
                    guard url != nil, self.lastTrack?.trackKey == track.trackKey else { return }
                    self.lastPublishedKey = nil
                    self.update(for: track)
                }
            }
        }
        return nil
    }
}
