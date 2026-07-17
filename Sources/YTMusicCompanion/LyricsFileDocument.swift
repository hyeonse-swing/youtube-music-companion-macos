import Foundation

enum LyricsFileError: Error, Equatable, LocalizedError {
    case invalidEncoding
    case noSyncedLines
    case noCurrentTrack
    case noLyricsToExport

    var errorDescription: String? {
        switch self {
        case .invalidEncoding:
            "The selected file is not valid UTF-8 text."
        case .noSyncedLines:
            "The selected file has no timestamped LRC lines."
        case .noCurrentTrack:
            "Start a song before importing or exporting lyrics."
        case .noLyricsToExport:
            "There are no synced lyrics to export for this song."
        }
    }
}

enum LyricsFileDocument {
    static func imported(from url: URL) throws -> CustomLyricsDocument {
        try imported(
            from: Data(contentsOf: url),
            sourceName: url.lastPathComponent
        )
    }

    static func imported(from data: Data, sourceName: String) throws -> CustomLyricsDocument {
        guard let raw = String(data: data, encoding: .utf8) else {
            throw LyricsFileError.invalidEncoding
        }
        let lines = LRCLIB.parseLRC(raw)
        guard !lines.isEmpty else { throw LyricsFileError.noSyncedLines }
        return CustomLyricsDocument(sourceName: sourceName, lines: lines)
    }

    static func write(lines: [LyricLine], track: NowPlaying, to url: URL) throws {
        guard !lines.isEmpty else { throw LyricsFileError.noLyricsToExport }
        try Data(exportedText(lines: lines, track: track).utf8)
            .write(to: url, options: .atomic)
    }

    static func exportedText(lines: [LyricLine], track: NowPlaying) -> String {
        var output: [String] = []
        appendMetadata("ar", value: track.artist, to: &output)
        appendMetadata("ti", value: track.title, to: &output)
        appendMetadata("al", value: track.album, to: &output)
        if !output.isEmpty { output.append("") }

        output.append(contentsOf: lines.sorted { $0.time < $1.time }.map { line in
            "\(timestamp(line.time)) \(singleLine(line.text))"
                .trimmingCharacters(in: .whitespaces)
        })
        return output.joined(separator: "\n") + "\n"
    }

    static func suggestedFilename(for track: NowPlaying) -> String {
        let raw = [track.artist, track.title]
            .filter { !$0.isEmpty }
            .joined(separator: " - ")
        let base = raw.isEmpty ? "Lyrics" : raw
        let safe = base
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(safe.isEmpty ? "Lyrics" : safe).lrc"
    }

    private static func appendMetadata(
        _ key: String,
        value: String,
        to output: inout [String]
    ) {
        let value = singleLine(value).trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty { output.append("[\(key):\(value)]") }
    }

    private static func timestamp(_ time: Double) -> String {
        let totalCentiseconds = max(0, Int((time * 100).rounded()))
        let minutes = totalCentiseconds / 6_000
        let seconds = totalCentiseconds / 100 % 60
        let centiseconds = totalCentiseconds % 100
        return String(format: "[%02d:%02d.%02d]", minutes, seconds, centiseconds)
    }

    private static func singleLine(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
    }
}
