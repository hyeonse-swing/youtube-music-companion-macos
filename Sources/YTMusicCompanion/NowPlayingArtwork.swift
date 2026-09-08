import CoreGraphics
import Foundation
import ImageIO

struct NowPlayingArtwork: Equatable, Sendable {
    let data: Data
    let width: Int
    let height: Int

    init?(data: Data, width: Int, height: Int) {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }

        self.data = data
        self.width = width > 0 ? width : image.width
        self.height = height > 0 ? height : image.height
    }

    var memoryCacheKey: String {
        "\(data.count):\(data.hashValue)"
    }
}

enum ArtworkImageMatcher {
    struct Fingerprint {
        fileprivate let pixels: [UInt8]
    }

    private static let sampleDimension = 24
    private static let maximumMeanDifference = 0.12

    static func isSameArtwork(_ left: Data, _ right: Data) -> Bool {
        guard
            let leftFingerprint = fingerprint(from: left)
        else { return false }
        return isSameArtwork(leftFingerprint, right)
    }

    static func fingerprint(from data: Data) -> Fingerprint? {
        normalizedPixels(from: data).map(Fingerprint.init(pixels:))
    }

    static func isSameArtwork(_ left: Fingerprint, _ right: Data) -> Bool {
        guard
            let rightPixels = normalizedPixels(from: right),
            left.pixels.count == rightPixels.count
        else { return false }

        var totalDifference = 0
        var comparedChannels = 0
        for index in stride(from: 0, to: left.pixels.count, by: 4) {
            for channel in 0..<3 {
                totalDifference += abs(
                    Int(left.pixels[index + channel]) - Int(rightPixels[index + channel])
                )
                comparedChannels += 1
            }
        }
        let maximumDifference = Double(comparedChannels * 255)
        return Double(totalDifference) / maximumDifference <= maximumMeanDifference
    }

    private static func normalizedPixels(from data: Data) -> [UInt8]? {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }

        let dimension = sampleDimension
        var pixels = [UInt8](repeating: 0, count: dimension * dimension * 4)
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue
            | CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: &pixels,
            width: dimension,
            height: dimension,
            bitsPerComponent: 8,
            bytesPerRow: dimension * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo
        ) else { return nil }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: dimension, height: dimension))
        return pixels
    }
}

protocol NowPlayingArtworkQuerying: Sendable {
    /// Blocking MediaRemote request. Call from a background task.
    func query() -> NowPlayingArtwork?
    func query(cancellation: CancellationToken) -> NowPlayingArtwork?
}

extension NowPlayingArtworkQuerying {
    func query(cancellation: CancellationToken) -> NowPlayingArtwork? {
        guard !cancellation.isCancelled else { return nil }
        return query()
    }
}

struct DefaultNowPlayingArtworkQuery: NowPlayingArtworkQuerying {
    func query() -> NowPlayingArtwork? {
        MediaRemoteArtworkBridge.query()
    }

    func query(cancellation: CancellationToken) -> NowPlayingArtwork? {
        MediaRemoteArtworkBridge.query(cancellation: cancellation)
    }
}

/// Fetches the current artwork through MediaRemote's dedicated artwork request.
/// macOS denies this request to third-party app processes, so a tiny Objective-C
/// bridge is loaded by Apple's platform-signed Perl interpreter. The bridge prints
/// base64 to stdout; no artwork is written to disk.
enum MediaRemoteArtworkBridge {
    static func query(timeout: TimeInterval = 6) -> NowPlayingArtwork? {
        query(timeout: timeout, cancellation: CancellationToken())
    }

    static func query(
        timeout: TimeInterval = 6,
        cancellation: CancellationToken
    ) -> NowPlayingArtwork? {
        guard let helpers = helperPaths() else { return nil }
        guard let result = SubprocessRunner.run(
            executable: "/usr/bin/perl",
            arguments: [
                helpers.script.path,
                helpers.library.path,
                "YTMCPrintNowPlayingArtworkBase64",
            ],
            timeout: timeout,
            cancellation: cancellation
        ), result.succeeded else { return nil }
        guard
            let base64 = String(data: result.output, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters)
        else { return nil }
        return NowPlayingArtwork(data: data, width: 0, height: 0)
    }

    static func helperPaths() -> (script: URL, library: URL)? {
        let fileManager = FileManager.default
        let resourceDirectory = Bundle.main.resourceURL
        let currentDirectory = URL(
            fileURLWithPath: fileManager.currentDirectoryPath,
            isDirectory: true
        )
        let searchDirectories = [
            resourceDirectory,
            currentDirectory.appendingPathComponent(".build/artwork-bridge"),
        ].compactMap { $0 }

        for directory in searchDirectories {
            let bundledScript = directory.appendingPathComponent("artwork-bridge.pl")
            let developmentScript = currentDirectory
                .appendingPathComponent("Support/ArtworkBridge/artwork-bridge.pl")
            let script = fileManager.isReadableFile(atPath: bundledScript.path)
                ? bundledScript
                : developmentScript
            let library = directory.appendingPathComponent("YTMusicArtworkBridge.dylib")
            if
                fileManager.isReadableFile(atPath: script.path),
                fileManager.isReadableFile(atPath: library.path)
            {
                return (script, library)
            }
        }
        return nil
    }
}
