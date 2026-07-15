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
    private static let sampleDimension = 24
    private static let maximumMeanDifference = 0.12

    static func isSameArtwork(_ left: Data, _ right: Data) -> Bool {
        guard
            let leftPixels = normalizedPixels(from: left),
            let rightPixels = normalizedPixels(from: right),
            leftPixels.count == rightPixels.count
        else { return false }

        var totalDifference = 0
        var comparedChannels = 0
        for index in stride(from: 0, to: leftPixels.count, by: 4) {
            for channel in 0..<3 {
                totalDifference += abs(Int(leftPixels[index + channel]) - Int(rightPixels[index + channel]))
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
}

struct DefaultNowPlayingArtworkQuery: NowPlayingArtworkQuerying {
    func query() -> NowPlayingArtwork? {
        MediaRemoteArtworkBridge.query()
    }
}

/// Fetches the current artwork through MediaRemote's dedicated artwork request.
/// macOS denies this request to third-party app processes, so a tiny Objective-C
/// bridge is loaded by Apple's platform-signed Perl interpreter. The bridge prints
/// base64 to stdout; no artwork is written to disk.
enum MediaRemoteArtworkBridge {
    static func query(timeout: TimeInterval = 6) -> NowPlayingArtwork? {
        guard let helpers = helperPaths() else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [
            helpers.script.path,
            helpers.library.path,
            "YTMCPrintNowPlayingArtworkBase64",
        ]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }

        let watchdog = DispatchWorkItem { process.terminate() }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
        let encoded = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()

        guard
            process.terminationStatus == 0,
            let base64 = String(data: encoded, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters)
        else { return nil }
        return NowPlayingArtwork(data: data, width: 0, height: 0)
    }

    private static func helperPaths() -> (script: URL, library: URL)? {
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
