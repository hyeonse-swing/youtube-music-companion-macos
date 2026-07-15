import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import YTMusicCompanion

final class VerifiedArtworkResolverTests: XCTestCase {
    func testReturnsPublicURLOnlyWhenCandidateMatchesSourceArtwork() throws {
        let candidate = try XCTUnwrap(URL(string: "https://example.com/100x100bb.jpg"))
        let sourceData = try makeArtworkData(accent: red, type: .png)
        let candidateData = try makeArtworkData(accent: red, type: .jpeg)
        let resolver = VerifiedArtworkResolver(
            catalog: StubArtworkCatalog(urls: [candidate]),
            loader: StubArtworkDataLoader(values: [candidate: candidateData])
        )

        let result = resolver.coverURL(
            for: makeTrack(),
            sourceArtwork: try XCTUnwrap(NowPlayingArtwork(
                data: sourceData,
                width: 64,
                height: 64
            ))
        )

        XCTAssertEqual(result, "https://example.com/512x512bb.jpg")
    }

    func testRejectsCandidateThatDoesNotMatchSourceArtwork() throws {
        let candidate = try XCTUnwrap(URL(string: "https://example.com/100x100bb.jpg"))
        let sourceData = try makeArtworkData(accent: red, type: .png)
        let candidateData = try makeArtworkData(accent: blue, type: .jpeg)
        let resolver = VerifiedArtworkResolver(
            catalog: StubArtworkCatalog(urls: [candidate]),
            loader: StubArtworkDataLoader(values: [candidate: candidateData])
        )

        let result = resolver.coverURL(
            for: makeTrack(),
            sourceArtwork: try XCTUnwrap(NowPlayingArtwork(
                data: sourceData,
                width: 64,
                height: 64
            ))
        )

        XCTAssertNil(result)
    }

    private func makeTrack() -> NowPlaying {
        NowPlaying(
            title: "Test Song",
            artist: "Test Artist",
            album: "Test Album",
            duration: 180,
            elapsed: 30,
            timestamp: 1_000,
            isPlaying: true,
            rate: 1,
            sourceBundle: "com.google.Chrome.app.cinhimbnkkaeohfgghhklpknlkffjgod",
            sourcePID: 0
        )
    }

    private var red: CGColor { CGColor(red: 0.9, green: 0.1, blue: 0.1, alpha: 1) }
    private var blue: CGColor { CGColor(red: 0.1, green: 0.2, blue: 0.9, alpha: 1) }

    private func makeArtworkData(accent: CGColor, type: UTType) throws -> Data {
        let size = 64
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(gray: 0.12, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        context.setFillColor(accent)
        context.fillEllipse(in: CGRect(x: 12, y: 12, width: 40, height: 40))
        let image = try XCTUnwrap(context.makeImage())
        let output = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(
            output,
            type.identifier as CFString,
            1,
            nil
        ))
        CGImageDestinationAddImage(destination, image, [
            kCGImageDestinationLossyCompressionQuality: 0.8,
        ] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }
}

private struct StubArtworkCatalog: ArtworkCatalogSearching {
    let urls: [URL]

    func candidateURLs(for track: NowPlaying) -> [URL] { urls }
}

private struct StubArtworkDataLoader: ArtworkDataLoading {
    let values: [URL: Data]

    func data(from url: URL) -> Data? { values[url] }
}
