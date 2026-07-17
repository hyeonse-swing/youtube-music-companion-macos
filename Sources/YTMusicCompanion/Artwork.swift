import Foundation

protocol ArtworkCatalogSearching: Sendable {
    /// Returns publicly reachable artwork thumbnails ordered from most to least likely.
    func candidateURLs(for track: NowPlaying) -> [URL]
    func candidateURLs(for track: NowPlaying, cancellation: CancellationToken) -> [URL]
}

extension ArtworkCatalogSearching {
    func candidateURLs(for track: NowPlaying, cancellation: CancellationToken) -> [URL] {
        guard !cancellation.isCancelled else { return [] }
        return candidateURLs(for: track)
    }
}

protocol ArtworkDataLoading: Sendable {
    func data(from url: URL) -> Data?
    func data(from url: URL, cancellation: CancellationToken) -> Data?
}

extension ArtworkDataLoading {
    func data(from url: URL, cancellation: CancellationToken) -> Data? {
        guard !cancellation.isCancelled else { return nil }
        return data(from: url)
    }
}

struct ITunesArtworkCatalog: ArtworkCatalogSearching {
    func candidateURLs(for track: NowPlaying) -> [URL] {
        Artwork.iTunesCandidateURLs(for: track)
    }

    func candidateURLs(for track: NowPlaying, cancellation: CancellationToken) -> [URL] {
        Artwork.iTunesCandidateURLs(for: track, cancellation: cancellation)
    }
}

struct CurlArtworkDataLoader: ArtworkDataLoading {
    func data(from url: URL) -> Data? {
        data(from: url, cancellation: CancellationToken())
    }

    func data(from url: URL, cancellation: CancellationToken) -> Data? {
        guard let result = SubprocessRunner.run(
            executable: "/usr/bin/curl",
            arguments: [
                "-fsSL",
                "--max-time", "8",
                "-H", "User-Agent: \(AppConfiguration.userAgent)",
                url.absoluteString,
            ],
            timeout: 9,
            cancellation: cancellation
        ), result.succeeded, !result.output.isEmpty else { return nil }
        return result.output
    }
}

/// Discord needs a public URL, while MediaRemote supplies private in-memory bytes.
/// A catalog URL is therefore accepted only when its decoded pixels match those bytes.
struct VerifiedArtworkResolver: ArtworkResolving {
    private let catalog: ArtworkCatalogSearching
    private let loader: ArtworkDataLoading

    init(
        catalog: ArtworkCatalogSearching = ITunesArtworkCatalog(),
        loader: ArtworkDataLoading = CurlArtworkDataLoader()
    ) {
        self.catalog = catalog
        self.loader = loader
    }

    func coverURL(for track: NowPlaying, sourceArtwork: NowPlayingArtwork) -> String? {
        coverURL(
            for: track,
            sourceArtwork: sourceArtwork,
            cancellation: CancellationToken()
        )
    }

    func coverURL(
        for track: NowPlaying,
        sourceArtwork: NowPlayingArtwork,
        cancellation: CancellationToken
    ) -> String? {
        for candidateURL in catalog.candidateURLs(for: track, cancellation: cancellation) {
            guard !cancellation.isCancelled else { return nil }
            guard
                let candidateData = loader.data(from: candidateURL, cancellation: cancellation),
                ArtworkImageMatcher.isSameArtwork(sourceArtwork.data, candidateData)
            else { continue }
            return Artwork.upgradedURL(candidateURL).absoluteString
        }
        return nil
    }
}

/// Resolves album cover art for a track via the iTunes Search API.
///
/// Discord's `large_image` can't take local artwork bytes — it needs a pre-uploaded
/// asset key OR an external `https://` URL. So instead of shipping the system's local
/// artwork we look up a publicly-reachable cover URL per track and hand that to the
/// Rich Presence activity. This is a faithful port of how the sibling
/// `telegram-audio-discord` project resolves art.
///
/// Like `LRCLIB`, networking shells out to `/usr/bin/curl`: `URLSession` (every
/// variant) stalls ~8s under this app's AppKit run loop, but a subprocess returns
/// normally (see CLAUDE.md). Call `coverURL` from a background queue — it blocks.
enum Artwork {
    /// Resolve a cover URL for a track. We intentionally do not scrape YouTube search:
    /// the first video result may be unrelated to the track that is actually playing.
    static func coverURL(title: String, artist: String, album: String) -> String? {
        iTunesCoverURL(title: title, artist: artist, album: album)
    }

    /// Resolve a 512×512 cover URL for a track via the iTunes Search API, or nil when
    /// nothing suitable is found. Builds an iTunes search term from the title + first
    /// artist, queries the Search API, and returns the first result whose artwork exists
    /// AND plausibly matches the track (see `matchesResult`), upgraded from the API's
    /// 100×100 thumbnail to 512×512.
    ///
    /// Resilient by design: a transient curl/JSON failure (or no match) returns nil —
    /// the caller simply falls through to the next source.
    static func iTunesCoverURL(title: String, artist: String, album: String) -> String? {
        // Use the shared lead-artist extractor so art and lyrics search the same act.
        let first = LRCLIB.primaryArtist(artist)
        // Search term mirrors the sibling project: "<title> <firstArtist>", normalized.
        let term = normalizeSearchTerm("\(title) \(first)")
        guard !term.isEmpty else { return nil }

        var comps = URLComponents(string: "https://itunes.apple.com/search")!
        comps.queryItems = [
            .init(name: "term", value: term),
            .init(name: "media", value: "music"),
            .init(name: "entity", value: "song"),
            .init(name: "limit", value: "10"),
        ]
        guard let json = curlJSON(comps.url, cancellation: CancellationToken()),
              let dict = json as? [String: Any],
              let results = dict["results"] as? [[String: Any]] else { return nil }

        for result in results {
            guard let art = result["artworkUrl100"] as? String, !art.isEmpty else { continue }
            let resultArtist = (result["artistName"] as? String) ?? ""
            let resultTitle = (result["trackName"] as? String) ?? ""
            if matchesResult(artist: artist, title: title,
                             resultArtist: resultArtist, resultTitle: resultTitle) {
                // Upgrade resolution: the API hands back a 100×100 thumbnail.
                return upgradedURLString(art)
            }
        }
        return nil
    }

    /// Returns a small, ordered set of plausible public covers. Pixel verification is
    /// deliberately performed by `VerifiedArtworkResolver`, not by this text search.
    static func iTunesCandidateURLs(for track: NowPlaying) -> [URL] {
        iTunesCandidateURLs(for: track, cancellation: CancellationToken())
    }

    static func iTunesCandidateURLs(
        for track: NowPlaying,
        cancellation: CancellationToken
    ) -> [URL] {
        guard !cancellation.isCancelled else { return [] }
        let firstArtist = LRCLIB.primaryArtist(track.artist)
        let term = normalizeSearchTerm("\(track.title) \(firstArtist)")
        guard !term.isEmpty else { return [] }

        var scored: [(url: URL, score: CandidateScore)] = []
        for storefront in [("JP", "ja_jp"), ("US", "en_us")] {
            guard !cancellation.isCancelled else { return [] }
            var components = URLComponents(string: "https://itunes.apple.com/search")
            components?.queryItems = [
                .init(name: "term", value: term),
                .init(name: "country", value: storefront.0),
                .init(name: "lang", value: storefront.1),
                .init(name: "media", value: "music"),
                .init(name: "entity", value: "song"),
                .init(name: "limit", value: "15"),
            ]
            guard
                let json = curlJSON(
                    components?.url,
                    cancellation: cancellation
                ) as? [String: Any],
                let results = json["results"] as? [[String: Any]]
            else { continue }

            for (index, result) in results.enumerated() {
                guard
                    let rawURL = result["artworkUrl100"] as? String,
                    let url = URL(string: rawURL),
                    let resultTitle = result["trackName"] as? String,
                    let resultArtist = result["artistName"] as? String,
                    matchesResult(
                        artist: track.artist,
                        title: track.title,
                        resultArtist: resultArtist,
                        resultTitle: resultTitle
                    )
                else { continue }

                let resultAlbum = (result["collectionName"] as? String) ?? ""
                let millis = (result["trackTimeMillis"] as? NSNumber)?.doubleValue ?? 0
                let durationDelta = track.duration > 0 && millis > 0
                    ? abs(track.duration - millis / 1_000)
                    : .infinity
                scored.append((
                    url,
                    CandidateScore(
                        albumMatches: !track.album.isEmpty && fieldMatches(track.album, resultAlbum),
                        durationDelta: durationDelta,
                        resultIndex: index
                    )
                ))
            }
        }

        let sorted = scored.sorted { left, right in
            if left.score.albumMatches != right.score.albumMatches {
                return left.score.albumMatches
            }
            if left.score.durationDelta != right.score.durationDelta {
                return left.score.durationDelta < right.score.durationDelta
            }
            return left.score.resultIndex < right.score.resultIndex
        }

        var seen = Set<String>()
        return sorted.compactMap { item in
            let key = upgradedURL(item.url).absoluteString
            guard seen.insert(key).inserted else { return nil }
            return item.url
        }.prefix(12).map { $0 }
    }

    static func upgradedURL(_ url: URL) -> URL {
        URL(string: upgradedURLString(url.absoluteString)) ?? url
    }

    // MARK: - Pure helpers (testable)

    /// NFD-normalize, strip diacritics, strip punctuation, collapse whitespace,
    /// lowercase. Ports the sibling project's `normalizeSearchTerm`.
    static func normalizeSearchTerm(_ s: String) -> String {
        // Foundation's locale-aware fold removes Latin diacritics without stripping
        // Japanese dakuten/handakuten (a raw NFD combining-mark filter corrupts
        // パレード into ハレート and makes the catalog query miss).
        let noDiacritics = s.folding(
            options: [.diacriticInsensitive, .caseInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        // Keep letters/numbers/whitespace; everything else becomes a space.
        let cleaned = String(noDiacritics.unicodeScalars.map {
            (CharacterSet.alphanumerics.contains($0) || CharacterSet.whitespaces.contains($0))
                ? Character($0) : " "
        })
        let collapsed = cleaned.replacingOccurrences(
            of: #"\s+"#, with: " ", options: .regularExpression)
        return collapsed.trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// Does an iTunes result plausibly match the track? Ports `matchesResult`:
    /// artist matches if one contains the other or they share a >2-char word; title
    /// matches if any >2-char word overlaps or one contains the other. Both must hold.
    static func matchesResult(artist: String, title: String,
                              resultArtist: String, resultTitle: String) -> Bool {
        return fieldMatches(
            LRCLIB.primaryArtist(artist),
            LRCLIB.primaryArtist(resultArtist)
        ) && fieldMatches(title, resultTitle)
    }

    /// Conservative field match. A single shared word is not enough: that was able
    /// to attach artwork from an unrelated search result.
    static func fieldMatches(_ a: String, _ b: String) -> Bool {
        let na = normalizeSearchTerm(a)
        let nb = normalizeSearchTerm(b)
        if na.isEmpty || nb.isEmpty { return false }
        if na == nb { return true }

        let wordsA = significantWords(in: na)
        let wordsB = significantWords(in: nb)
        guard !wordsA.isEmpty, !wordsB.isEmpty else { return false }

        let smaller = wordsA.count <= wordsB.count ? wordsA : wordsB
        let larger = wordsA.count <= wordsB.count ? wordsB : wordsA
        guard smaller.isSubset(of: larger) else { return false }
        if smaller.count >= 2 { return true }

        let shorterLength = min(na.count, nb.count)
        let longerLength = max(na.count, nb.count)
        return Double(shorterLength) / Double(longerLength) >= 0.6
    }

    private static func significantWords(in value: String) -> Set<String> {
        let ignored = Set(["a", "an", "and", "feat", "featuring", "ft", "the"])
        return Set(value.split(separator: " ").map(String.init).filter {
            $0.count > 1 && !ignored.contains($0)
        })
    }

    private struct CandidateScore {
        let albumMatches: Bool
        let durationDelta: Double
        let resultIndex: Int
    }

    private static func upgradedURLString(_ value: String) -> String {
        value.replacingOccurrences(
            of: #"\d+x\d+(?=[a-z]*\.)"#,
            with: "512x512",
            options: .regularExpression
        )
    }

    // MARK: - networking

    /// One curl invocation. Returns parsed JSON, or nil on a non-JSON/empty body or a
    /// curl/network error. Mirrors `LRCLIB.curlJSON`: stdout pipe, stderr → nullDevice
    /// (an undrained full stderr pipe would deadlock the child), `JSONSerialization`.
    private static func curlJSON(
        _ url: URL?,
        cancellation: CancellationToken
    ) -> Any? {
        guard let url else { return nil }
        guard let result = SubprocessRunner.run(
            executable: "/usr/bin/curl",
            arguments: [
                "-s",
                "--max-time", "10",
                "-H", "User-Agent: \(LRCLIB.userAgent)",
                url.absoluteString,
            ],
            timeout: 11,
            cancellation: cancellation
        ), result.succeeded else { return nil }
        return try? JSONSerialization.jsonObject(with: result.output)
    }

}
