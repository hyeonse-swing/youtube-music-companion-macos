import XCTest
@testable import YTMusicCompanion

final class YouTubeMusicPageMetadataTests: XCTestCase {
    func testUsesTheExactBilingualTitleAndPlayerLinks() {
        let metadata = YouTubeMusicPageMetadataResolver.metadata(
            documentTitle: "鋼の羽根 - Iron Feather | YouTube Music",
            playerLinks: ["Radwimps", "Forever Daze"],
            pageURL: URL(
                string: "https://music.youtube.com/watch?v=abc123&list=RDAMVMabc123"
            ),
            source: track(
                title: "Iron Feather",
                artist: "Radwimps",
                album: "Forever Daze"
            )
        )

        XCTAssertEqual(metadata?.title, "鋼の羽根 - Iron Feather")
        XCTAssertEqual(metadata?.artist, "Radwimps")
        XCTAssertEqual(metadata?.album, "Forever Daze")
        XCTAssertEqual(
            metadata?.trackURL,
            URL(string: "https://music.youtube.com/watch?v=abc123")
        )
    }

    func testUsesTheExactPlayerAlbumInsteadOfTheMediaRemoteCompilation() {
        let metadata = YouTubeMusicPageMetadataResolver.metadata(
            documentTitle: "ブレーメン - Bremen | YouTube Music",
            playerLinks: ["ヨルシカ", "幻燈"],
            source: track(
                title: "Bremen",
                artist: "Yorushika",
                album: "J-POP Viral Hits 2023 in China"
            )
        )

        XCTAssertEqual(metadata?.title, "ブレーメン - Bremen")
        XCTAssertEqual(metadata?.artist, "ヨルシカ")
        XCTAssertEqual(metadata?.album, "幻燈")
    }

    func testRejectsAStalePageFromThePreviousTrack() {
        let metadata = YouTubeMusicPageMetadataResolver.metadata(
            documentTitle: "前の曲 - Previous Song | YouTube Music",
            playerLinks: ["Previous Artist", "Previous Album"],
            source: track(
                title: "Iron Feather",
                artist: "Radwimps",
                album: "Forever Daze"
            )
        )

        XCTAssertNil(metadata)
    }

    func testFallsBackToMediaRemoteFieldsMissingFromThePlayerBar() {
        let metadata = YouTubeMusicPageMetadataResolver.metadata(
            documentTitle: "鋼の羽根 - Iron Feather | YouTube Music",
            playerLinks: [],
            source: track(
                title: "Iron Feather",
                artist: "Radwimps",
                album: "Forever Daze"
            )
        )

        XCTAssertEqual(metadata?.artist, "Radwimps")
        XCTAssertEqual(metadata?.album, "Forever Daze")
    }

    func testRejectsANonYouTubeMusicWatchURL() {
        let metadata = YouTubeMusicPageMetadataResolver.metadata(
            documentTitle: "鋼の羽根 - Iron Feather | YouTube Music",
            playerLinks: ["Radwimps", "Forever Daze"],
            pageURL: URL(string: "https://example.com/watch?v=abc123"),
            source: track(
                title: "Iron Feather",
                artist: "Radwimps",
                album: "Forever Daze"
            )
        )

        XCTAssertNil(metadata?.trackURL)
    }

    private func track(title: String, artist: String, album: String) -> NowPlaying {
        NowPlaying(
            title: title,
            artist: artist,
            album: album,
            duration: 321,
            elapsed: 0,
            timestamp: 0,
            isPlaying: true,
            rate: 1,
            sourceBundle: "com.google.Chrome.app.cinhimbnkkaeohfgghhklpknlkffjgod",
            sourcePID: 123
        )
    }
}
