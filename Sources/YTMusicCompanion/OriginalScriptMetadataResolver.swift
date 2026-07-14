import Foundation

struct TrackMetadata: Equatable, Sendable {
    let title: String
    let artist: String
    let album: String
}

extension NowPlaying {
    var metadata: TrackMetadata {
        TrackMetadata(title: title, artist: artist, album: album)
    }

    func applying(_ metadata: TrackMetadata) -> NowPlaying {
        var copy = self
        copy.title = metadata.title
        copy.artist = metadata.artist
        copy.album = metadata.album
        return copy
    }
}

protocol TrackMetadataResolving: Sendable {
    /// Blocking network lookup. Call from a background task.
    /// `nil` means a transient network failure; a non-nil source-equivalent value
    /// means the lookup succeeded but found no safer original-script replacement.
    func resolve(for track: NowPlaying) -> TrackMetadata?
}

/// Replaces YouTube Music's localized or romanized labels with the Japanese-storefront
/// metadata when the result can be matched confidently to the same recording.
final class OriginalScriptMetadataResolver: TrackMetadataResolving, @unchecked Sendable {
    private static let maximumDurationDelta: Double = 7
    private static let maximumUnverifiedDurationDelta: Double = 2.5

    private let cacheLock = NSLock()
    private var cache: [String: TrackMetadata] = [:]

    func resolve(for track: NowPlaying) -> TrackMetadata? {
        if let cached = cacheLock.withLock({ cache[track.trackKey] }) {
            return cached
        }

        guard let results = fetchResults(for: track) else { return nil }
        let resolved = Self.chooseMetadata(for: track, from: results) ?? track.metadata
        cacheLock.withLock { cache[track.trackKey] = resolved }
        return resolved
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

    /// Pure selection logic kept separate from networking so false-positive handling
    /// is covered by unit tests. Textual matches are strongest; when both title and
    /// artist were transliterated, a top search result must instead match the exact
    /// recording length within a narrow tolerance.
    static func chooseMetadata(
        for track: NowPlaying,
        from results: [[String: Any]]
    ) -> TrackMetadata? {
        let candidates = results.enumerated().compactMap { index, result -> Candidate? in
            guard
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
            guard metadata != track.metadata, containsJapaneseScript(metadata) else { return nil }

            let resultDuration = (result["trackTimeMillis"] as? NSNumber)?.doubleValue ?? 0
            let durationDelta = track.duration > 0 && resultDuration > 0
                ? abs(resultDuration / 1_000 - track.duration)
                : .infinity
            let artistMatches = fieldsMatch(track.artist, metadata.artist)
            let titleMatches = fieldsMatch(track.title, metadata.title)
            let albumMatches = !track.album.isEmpty && fieldsMatch(track.album, metadata.album)
            let hasTextualMatch = artistMatches || titleMatches || albumMatches

            if track.duration > 0 {
                guard durationDelta <= maximumDurationDelta else { return nil }
                if !hasTextualMatch {
                    guard index < 5, durationDelta <= maximumUnverifiedDurationDelta else {
                        return nil
                    }
                }
            } else {
                guard hasTextualMatch, index < 5 else { return nil }
            }

            var score = Double(max(0, 10 - index))
            if artistMatches { score += 100 }
            if titleMatches { score += 50 }
            if albumMatches { score += 25 }
            if durationDelta.isFinite {
                score += max(0, 30 - durationDelta * 5)
            }
            return Candidate(
                metadata: metadata,
                score: score,
                durationDelta: durationDelta,
                resultIndex: index
            )
        }

        return candidates.max { left, right in
            if left.score != right.score { return left.score < right.score }
            if left.durationDelta != right.durationDelta {
                return left.durationDelta > right.durationDelta
            }
            return left.resultIndex > right.resultIndex
        }?.metadata
    }

    private struct Candidate {
        let metadata: TrackMetadata
        let score: Double
        let durationDelta: Double
        let resultIndex: Int
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

    private static func fieldsMatch(_ left: String, _ right: String) -> Bool {
        let normalizedLeft = Artwork.normalizeSearchTerm(left)
        let normalizedRight = Artwork.normalizeSearchTerm(right)
        guard !normalizedLeft.isEmpty, !normalizedRight.isEmpty else { return false }
        if normalizedLeft.contains(normalizedRight) || normalizedRight.contains(normalizedLeft) {
            return true
        }

        let leftWords = significantWords(in: normalizedLeft)
        let rightWords = significantWords(in: normalizedRight)
        return !leftWords.isDisjoint(with: rightWords)
    }

    private static func significantWords(in value: String) -> Set<String> {
        Set(value.split(separator: " ").map(String.init).filter { $0.count > 2 })
    }

    private func fetchResults(for track: NowPlaying) -> [[String: Any]]? {
        guard let url = Self.queryURL(for: track) else { return nil }

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
