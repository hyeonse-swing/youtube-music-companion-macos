import Foundation

struct TrackMetadata: Equatable, Sendable {
    let title: String
    let artist: String
    let album: String
    var trackURL: URL? = nil
}

extension NowPlaying {
    var metadata: TrackMetadata {
        TrackMetadata(title: title, artist: artist, album: album, trackURL: trackURL)
    }

    func applying(_ metadata: TrackMetadata) -> NowPlaying {
        var copy = self
        copy.title = metadata.title
        copy.artist = metadata.artist
        copy.album = metadata.album
        copy.trackURL = metadata.trackURL
        return copy
    }
}

protocol TrackMetadataResolving: Sendable {
    /// Blocking network lookup. Call from a background task.
    /// `nil` means a transient network failure; a non-nil source-equivalent value
    /// means the lookup succeeded but found no verified original-script replacement.
    func resolve(for track: NowPlaying) -> TrackMetadata?
}

/// Replaces a localized YouTube Music label with its original-script counterpart.
///
/// Search order and a similar duration are not proof that two tracks are identical.
/// Romanized labels are verified by resolving the same catalog track ID in the US
/// storefront. Labels already in Japanese can be verified directly by title, artist,
/// and duration, which also lets us replace a compilation album with the artist's
/// canonical release.
final class OriginalScriptMetadataResolver: TrackMetadataResolving, @unchecked Sendable {
    private static let maximumDurationDelta: Double = 7
    private static let maximumCandidatesToVerify = 5

    private let cacheLock = NSLock()
    private var cache: [String: TrackMetadata] = [:]

    func resolve(for track: NowPlaying) -> TrackMetadata? {
        if let cached = cacheLock.withLock({ cache[track.trackKey] }) {
            return cached
        }

        guard let japaneseResults = fetchJSONResults(url: Self.queryURL(for: track)) else {
            return nil
        }

        let candidates = Self.rankedCandidates(for: track, from: japaneseResults)
        guard !candidates.isEmpty else {
            cache(track.metadata, for: track.trackKey)
            return track.metadata
        }

        if let directlyVerified = Self.chooseVerifiedMetadata(
            for: track,
            from: japaneseResults,
            localizedResultsByTrackID: [:]
        ) {
            cache(directlyVerified, for: track.trackKey)
            return directlyVerified
        }

        var completedLookup = false
        for candidate in candidates.prefix(Self.maximumCandidatesToVerify) {
            guard let results = fetchJSONResults(url: Self.lookupURL(trackID: candidate.trackID)) else {
                continue
            }
            completedLookup = true
            if let verified = Self.chooseVerifiedMetadata(
                for: track,
                from: japaneseResults,
                localizedResultsByTrackID: [candidate.trackID: results]
            ) {
                cache(verified, for: track.trackKey)
                return verified
            }
        }

        // A storefront outage is retryable. A completed lookup with no match is a
        // definitive result and keeps the exact MediaRemote metadata unchanged.
        guard completedLookup else { return nil }
        cache(track.metadata, for: track.trackKey)
        return track.metadata
    }

    static func queryURL(for track: NowPlaying) -> URL? {
        let artist = LRCLIB.primaryArtist(track.artist)
        let term = "\(artist) \(track.title)".trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return nil }

        var components = URLComponents(string: "https://itunes.apple.com/search")
        components?.queryItems = [
            .init(name: "term", value: term),
            .init(name: "country", value: "JP"),
            .init(name: "lang", value: "ja_jp"),
            .init(name: "media", value: "music"),
            .init(name: "entity", value: "song"),
            .init(name: "limit", value: "10"),
        ]
        return components?.url
    }

    static func lookupURL(trackID: Int64) -> URL? {
        var components = URLComponents(string: "https://itunes.apple.com/lookup")
        components?.queryItems = [
            .init(name: "id", value: String(trackID)),
            .init(name: "country", value: "US"),
            .init(name: "lang", value: "en_us"),
            .init(name: "entity", value: "song"),
        ]
        return components?.url
    }

    /// Pure selection logic used by tests and the network-backed resolver. A Japanese
    /// result can win either by directly matching an already-original source label,
    /// or when its ID has a localized result matching the source label and duration.
    static func chooseVerifiedMetadata(
        for track: NowPlaying,
        from japaneseResults: [[String: Any]],
        localizedResultsByTrackID: [Int64: [[String: Any]]]
    ) -> TrackMetadata? {
        for candidate in rankedCandidates(for: track, from: japaneseResults) {
            if candidateDirectlyMatchesSource(candidate, track: track) {
                return candidate.metadata
            }
            guard let localizedResults = localizedResultsByTrackID[candidate.trackID] else {
                continue
            }
            let isSameTrack = localizedResults.contains { localized in
                guard trackID(in: localized) == candidate.trackID else { return false }
                return localizedResult(localized, matches: track)
            }
            if isSameTrack { return candidate.metadata }
        }
        return nil
    }

    private struct Candidate {
        let trackID: Int64
        let metadata: TrackMetadata
        let durationDelta: Double
        let resultIndex: Int
        let artistMatchesDirectly: Bool
        let albumMatchesSource: Bool
        let isCompilation: Bool
    }

    private static func rankedCandidates(
        for track: NowPlaying,
        from results: [[String: Any]]
    ) -> [Candidate] {
        results.enumerated().compactMap { index, result -> Candidate? in
            guard
                let trackID = trackID(in: result),
                let title = result["trackName"] as? String,
                let artist = result["artistName"] as? String,
                !title.isEmpty,
                !artist.isEmpty
            else { return nil }

            let metadata = TrackMetadata(
                title: title,
                artist: artist,
                album: (result["collectionName"] as? String) ?? track.album
            )
            // Keep an exact source candidate in the ranking. It protects an already
            // correct artist album from being replaced by a near-identical single;
            // compilation candidates are still demoted below canonical releases.
            guard containsJapaneseScript(metadata) else { return nil }

            let durationDelta = durationDelta(for: track, result: result)
            if track.duration > 0, durationDelta > maximumDurationDelta { return nil }

            return Candidate(
                trackID: trackID,
                metadata: metadata,
                durationDelta: durationDelta,
                resultIndex: index,
                artistMatchesDirectly: fieldsMatch(track.artist, metadata.artist),
                albumMatchesSource: fieldsMatch(track.album, metadata.album),
                isCompilation: isCompilation(result)
            )
        }
        .sorted { left, right in
            if left.artistMatchesDirectly != right.artistMatchesDirectly {
                return left.artistMatchesDirectly
            }
            if left.isCompilation != right.isCompilation {
                return !left.isCompilation
            }
            if left.albumMatchesSource != right.albumMatchesSource {
                return left.albumMatchesSource
            }
            if left.durationDelta != right.durationDelta {
                return left.durationDelta < right.durationDelta
            }
            return left.resultIndex < right.resultIndex
        }
    }

    private static func candidateDirectlyMatchesSource(
        _ candidate: Candidate,
        track: NowPlaying
    ) -> Bool {
        guard
            fieldsMatch(track.title, candidate.metadata.title),
            fieldsMatch(
                LRCLIB.primaryArtist(track.artist),
                LRCLIB.primaryArtist(candidate.metadata.artist)
            )
        else { return false }
        return track.duration <= 0 || candidate.durationDelta <= maximumDurationDelta
    }

    private static func isCompilation(_ result: [String: Any]) -> Bool {
        guard let collectionArtist = result["collectionArtistName"] as? String else {
            return false
        }
        let normalized = Artwork.normalizeSearchTerm(collectionArtist)
        if normalized == "various artists" || normalized == "various artist" {
            return true
        }
        let japaneseCompilationLabels = ["ヴァリアスアーティスト", "オムニバス"]
        if japaneseCompilationLabels.contains(where: { collectionArtist.contains($0) }) {
            return true
        }
        guard let trackArtist = result["artistName"] as? String else { return false }
        return !fieldsMatch(collectionArtist, trackArtist)
    }

    private static func localizedResult(_ result: [String: Any], matches track: NowPlaying) -> Bool {
        guard
            let title = result["trackName"] as? String,
            let artist = result["artistName"] as? String,
            fieldsMatch(track.title, title),
            fieldsMatch(LRCLIB.primaryArtist(track.artist), LRCLIB.primaryArtist(artist))
        else { return false }

        return track.duration <= 0 || durationDelta(for: track, result: result) <= maximumDurationDelta
    }

    private static func durationDelta(for track: NowPlaying, result: [String: Any]) -> Double {
        let resultDuration = (result["trackTimeMillis"] as? NSNumber)?.doubleValue ?? 0
        guard track.duration > 0, resultDuration > 0 else { return .infinity }
        return abs(resultDuration / 1_000 - track.duration)
    }

    private static func trackID(in result: [String: Any]) -> Int64? {
        (result["trackId"] as? NSNumber)?.int64Value
    }

    private static func containsJapaneseScript(_ metadata: TrackMetadata) -> Bool {
        [metadata.title, metadata.artist, metadata.album].contains(where: containsJapaneseScript)
    }

    private static func containsJapaneseScript(_ value: String) -> Bool {
        value.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3040...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF:
                return true
            default:
                return false
            }
        }
    }

    /// Conservative equality for a catalog label. Parenthetical release qualifiers
    /// are tolerated through containment, but a single shared word is never enough.
    private static func fieldsMatch(_ left: String, _ right: String) -> Bool {
        let normalizedLeft = Artwork.normalizeSearchTerm(left)
        let normalizedRight = Artwork.normalizeSearchTerm(right)
        guard !normalizedLeft.isEmpty, !normalizedRight.isEmpty else { return false }
        if normalizedLeft == normalizedRight { return true }

        let shorter = min(normalizedLeft.count, normalizedRight.count)
        let longer = max(normalizedLeft.count, normalizedRight.count)
        guard Double(shorter) / Double(longer) >= 0.6 else { return false }
        return normalizedLeft.contains(normalizedRight) || normalizedRight.contains(normalizedLeft)
    }

    private func cache(_ metadata: TrackMetadata, for key: String) {
        cacheLock.withLock { cache[key] = metadata }
    }

    private func fetchJSONResults(url: URL?) -> [[String: Any]]? {
        guard let url else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        process.arguments = [
            "-fsSL",
            "--max-time", "6",
            "-H", "User-Agent: \(AppConfiguration.userAgent)",
            url.absoluteString,
        ]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard
            process.terminationStatus == 0,
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return json["results"] as? [[String: Any]]
    }
}
