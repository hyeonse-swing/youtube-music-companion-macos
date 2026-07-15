import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import YTMusicCompanion

final class NowPlayingArtworkTests: XCTestCase {
    func testAcceptsDecodableImageData() throws {
        let data = try makeArtworkData(accent: red, type: .png)

        let artwork = try XCTUnwrap(NowPlayingArtwork(data: data, width: 64, height: 64))

        XCTAssertEqual(artwork.width, 64)
        XCTAssertEqual(artwork.height, 64)
    }

    func testRejectsInvalidImageData() {
        XCTAssertNil(NowPlayingArtwork(data: Data("not an image".utf8), width: 64, height: 64))
    }

    func testVisualMatcherAcceptsSameCoverWithDifferentEncoding() throws {
        let png = try makeArtworkData(accent: red, type: .png)
        let jpeg = try makeArtworkData(accent: red, type: .jpeg)

        XCTAssertTrue(ArtworkImageMatcher.isSameArtwork(png, jpeg))
    }

    func testVisualMatcherRejectsDifferentCover() throws {
        let redArtwork = try makeArtworkData(accent: red, type: .png)
        let blueArtwork = try makeArtworkData(accent: blue, type: .jpeg)

        XCTAssertFalse(ArtworkImageMatcher.isSameArtwork(redArtwork, blueArtwork))
    }

    private var red: CGColor { CGColor(red: 0.9, green: 0.1, blue: 0.1, alpha: 1) }
    private var blue: CGColor { CGColor(red: 0.1, green: 0.2, blue: 0.9, alpha: 1) }

    private func makeArtworkData(accent: CGColor, type: UTType) throws -> Data {
        let size = 64
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
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
