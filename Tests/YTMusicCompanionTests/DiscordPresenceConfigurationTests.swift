import XCTest
@testable import YTMusicCompanion

final class DiscordPresenceConfigurationTests: XCTestCase {
    private let track = NowPlaying(
        title: "原題 - English Title",
        artist: "アーティスト",
        album: "Original Album",
        duration: 180,
        elapsed: 30,
        timestamp: 1_000,
        isPlaying: true,
        rate: 1,
        sourceBundle: "com.google.Chrome",
        sourcePID: 1
    )

    func testStandardConfigurationPreservesExistingDiscordText() {
        let content = DiscordPresenceConfiguration.standard.content(for: track)

        XCTAssertEqual(content.details, track.title)
        XCTAssertEqual(content.state, track.artist)
        XCTAssertEqual(content.imageText, track.album)
        XCTAssertTrue(DiscordPresenceConfiguration.standard.showsPlaybackTime)
    }

    func testTemplatesReplaceEverySupportedTrackToken() {
        let configuration = DiscordPresenceConfiguration(
            detailsTemplate: "🎵 {title}",
            stateTemplate: "{artist} · {album}",
            imageTextTemplate: "{title} / {artist} / {album}",
            showsPlaybackTime: false
        )

        let content = configuration.content(for: track)

        XCTAssertEqual(content.details, "🎵 原題 - English Title")
        XCTAssertEqual(content.state, "アーティスト · Original Album")
        XCTAssertEqual(
            content.imageText,
            "原題 - English Title / アーティスト / Original Album"
        )
    }

    func testBlankTemplatesFallBackToSafeStandardValues() {
        let configuration = DiscordPresenceConfiguration(
            detailsTemplate: "   ",
            stateTemplate: "",
            imageTextTemplate: "\n",
            showsPlaybackTime: true
        )

        let content = configuration.content(for: track)

        XCTAssertEqual(content.details, track.title)
        XCTAssertEqual(content.state, track.artist)
        XCTAssertEqual(content.imageText, track.album)
    }
}
