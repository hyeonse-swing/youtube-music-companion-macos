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
        XCTAssertTrue(DiscordPresenceConfiguration.standard.showsSongLink)
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

    func testLivePresetsApplyDistinctContentAndVisibilityRules() {
        let titleFocused = DiscordPresencePreset.titleFocused.applying(
            to: .standard
        )
        XCTAssertEqual(titleFocused.preset, .titleFocused)
        XCTAssertEqual(titleFocused.detailsTemplate, "♫ {title}")
        XCTAssertEqual(titleFocused.stateTemplate, "{artist} · {album}")
        XCTAssertTrue(titleFocused.showsPlaybackTime)

        let minimal = DiscordPresencePreset.minimal.applying(to: titleFocused)
        XCTAssertEqual(minimal.preset, .minimal)
        XCTAssertFalse(minimal.showsPlaybackTime)
        XCTAssertFalse(minimal.showsSongLink)
        XCTAssertFalse(minimal.linksDetailsToSong)
        XCTAssertFalse(minimal.linksStateToSong)
        XCTAssertFalse(minimal.linksCoverToSong)
        XCTAssertEqual(minimal.secondaryButtonLabel, "")
        XCTAssertEqual(minimal.secondaryButtonURL, "")
    }

    func testLiveConfigurationBuildsFieldLinksAndTwoButtons() {
        var linkedTrack = track
        linkedTrack.trackURL = URL(
            string: "https://music.youtube.com/watch?v=abc123"
        )
        var configuration = DiscordPresenceConfiguration.standard
        configuration.linksDetailsToSong = true
        configuration.linksStateToSong = true
        configuration.linksCoverToSong = true
        configuration.primaryButtonLabel = "Play this song"
        configuration.secondaryButtonLabel = "Artist site"
        configuration.secondaryButtonURL = "https://example.com/artist"

        let links = configuration.links(for: linkedTrack)

        XCTAssertEqual(links.detailsURL, linkedTrack.trackURL)
        XCTAssertEqual(links.stateURL, linkedTrack.trackURL)
        XCTAssertEqual(links.coverURL, linkedTrack.trackURL)
        XCTAssertEqual(
            links.buttons,
            [
                PresenceButton(label: "Play this song", url: linkedTrack.trackURL!),
                PresenceButton(
                    label: "Artist site",
                    url: URL(string: "https://example.com/artist")!
                ),
            ]
        )
    }

    func testManualPresenceCreatesExplicitTimedActivityAndRejectsUnsafeURLs() throws {
        let startedAt = Date(timeIntervalSince1970: 1_000)
        let manual = ManualDiscordPresence(
            title: "Manual Song",
            artist: "Manual Artist",
            album: "Manual Album",
            coverURL: "https://example.com/cover.jpg",
            songURL: "https://music.youtube.com/watch?v=manual",
            durationMinutes: 4,
            showsPlaybackTime: true,
            lifetime: .thirtyMinutes,
            secondaryButtonLabel: "Artist",
            secondaryButtonURL: "https://example.com/artist"
        )

        let activity = try XCTUnwrap(manual.activity(startedAt: startedAt))

        XCTAssertEqual(activity.details, "Manual Song")
        XCTAssertEqual(activity.state, "Manual Artist")
        XCTAssertEqual(activity.largeImage, "https://example.com/cover.jpg")
        XCTAssertEqual(activity.largeImageText, "Manual Album")
        XCTAssertEqual(activity.start, startedAt)
        XCTAssertEqual(
            activity.end,
            startedAt.addingTimeInterval(4 * 60)
        )
        XCTAssertEqual(activity.detailsURL?.absoluteString, manual.songURL)
        XCTAssertEqual(activity.largeImageURL?.absoluteString, manual.songURL)
        XCTAssertEqual(activity.buttons.count, 2)

        var unsafe = manual
        unsafe.coverURL = "http://example.com/cover.jpg"
        XCTAssertNotNil(unsafe.validationMessage)
        XCTAssertNil(unsafe.activity(startedAt: startedAt))
    }
}
