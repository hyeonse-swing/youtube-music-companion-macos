import Foundation

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
        guard let json = curlJSON(comps.url),
              let dict = json as? [String: Any],
              let results = dict["results"] as? [[String: Any]] else { return nil }

        for result in results {
            guard let art = result["artworkUrl100"] as? String, !art.isEmpty else { continue }
            let resultArtist = (result["artistName"] as? String) ?? ""
            let resultTitle = (result["trackName"] as? String) ?? ""
            if matchesResult(artist: artist, title: title,
                             resultArtist: resultArtist, resultTitle: resultTitle) {
                // Upgrade resolution: the API hands back a 100×100 thumbnail.
                return art.replacingOccurrences(of: "100x100", with: "512x512")
            }
        }
        return nil
    }

    // MARK: - Pure helpers (testable)

    /// NFD-normalize, strip diacritics, strip punctuation, collapse whitespace,
    /// lowercase. Ports the sibling project's `normalizeSearchTerm`.
    static func normalizeSearchTerm(_ s: String) -> String {
        // Decompose then drop combining marks (diacritics).
        let decomposed = s.decomposedStringWithCanonicalMapping
        let noDiacritics = String(decomposed.unicodeScalars.filter {
            !CharacterSet.nonBaseCharacters.contains($0)
        })
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
    private static func fieldMatches(_ a: String, _ b: String) -> Bool {
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

    // MARK: - networking

    /// One curl invocation. Returns parsed JSON, or nil on a non-JSON/empty body or a
    /// curl/network error. Mirrors `LRCLIB.curlJSON`: stdout pipe, stderr → nullDevice
    /// (an undrained full stderr pipe would deadlock the child), `JSONSerialization`.
    private static func curlJSON(_ url: URL?) -> Any? {
        guard let url else { return nil }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        proc.arguments = ["-s", "--max-time", "10", "-H", "User-Agent: \(LRCLIB.userAgent)", url.absoluteString]

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice

        do { try proc.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()

        return try? JSONSerialization.jsonObject(with: data)
    }

}
