import XCTest
@testable import YTMusicCompanion

@MainActor
final class CompanionPreferencesTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "CompanionPreferencesTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testDefaultsFavorExactYouTubeMusicMetadataAndStandardLyricsSize() {
        let preferences = CompanionPreferences(defaults: defaults)

        XCTAssertEqual(preferences.lyricsFontSize, 30)
        XCTAssertEqual(preferences.displayMetadataSource, .youtubeMusic)
        XCTAssertEqual(preferences.discordMetadataSource, .youtubeMusic)
        XCTAssertEqual(preferences.discordPresenceConfiguration, .standard)
    }

    func testDiscordPresenceCustomizationPersists() {
        let customized = DiscordPresenceConfiguration(
            detailsTemplate: "Listening to {title}",
            stateTemplate: "by {artist}",
            imageTextTemplate: "from {album}",
            showsPlaybackTime: false
        )
        var preferences = CompanionPreferences(defaults: defaults)
        preferences.discordPresenceConfiguration = customized

        preferences = CompanionPreferences(defaults: defaults)

        XCTAssertEqual(preferences.discordPresenceConfiguration, customized)
    }

    func testResetDiscordPresenceCustomizationReturnsToOriginalDefaults() {
        var preferences = CompanionPreferences(defaults: defaults)
        preferences.discordPresenceConfiguration = DiscordPresenceConfiguration(
            detailsTemplate: "Custom {title}",
            stateTemplate: "Custom {artist}",
            imageTextTemplate: "Custom {album}",
            showsPlaybackTime: false
        )

        preferences.resetDiscordPresenceConfiguration()
        preferences = CompanionPreferences(defaults: defaults)

        XCTAssertEqual(preferences.discordPresenceConfiguration, .standard)
    }

    func testLyricsFontSizeIsClampedAndPersisted() {
        var preferences = CompanionPreferences(defaults: defaults)
        preferences.lyricsFontSize = 200

        preferences = CompanionPreferences(defaults: defaults)
        XCTAssertEqual(preferences.lyricsFontSize, CompanionPreferences.maximumLyricsFontSize)

        preferences.lyricsFontSize = 1
        XCTAssertEqual(preferences.lyricsFontSize, CompanionPreferences.minimumLyricsFontSize)
    }

    func testMetadataSourceChoicesPersistIndependently() {
        var preferences = CompanionPreferences(defaults: defaults)
        preferences.displayMetadataSource = .macOS
        preferences.discordMetadataSource = .youtubeMusic

        preferences = CompanionPreferences(defaults: defaults)
        XCTAssertEqual(preferences.displayMetadataSource, .macOS)
        XCTAssertEqual(preferences.discordMetadataSource, .youtubeMusic)
    }

    func testMetadataSourceSelectsRequestedSnapshotAndFallsBackSafely() {
        let macOS = NowPlaying(
            title: "English Title", artist: "Artist", album: "System Album",
            duration: 180, elapsed: 10, timestamp: 100, isPlaying: true, rate: 1,
            sourceBundle: "com.google.Chrome", sourcePID: 1
        )
        let youtubeMusic = NowPlaying(
            title: "原題 - English Title", artist: "アーティスト", album: "Original Album",
            duration: 180, elapsed: 10, timestamp: 100, isPlaying: true, rate: 1,
            sourceBundle: "com.google.Chrome", sourcePID: 1
        )

        XCTAssertEqual(
            MetadataSourcePreference.youtubeMusic.select(
                youtubeMusic: youtubeMusic,
                macOS: macOS
            ),
            youtubeMusic
        )
        XCTAssertEqual(
            MetadataSourcePreference.macOS.select(youtubeMusic: youtubeMusic, macOS: macOS),
            macOS
        )
        XCTAssertEqual(
            MetadataSourcePreference.youtubeMusic.select(youtubeMusic: nil, macOS: macOS),
            macOS
        )
    }

    func testResetCurrentTimingStoresAnExplicitZeroWithoutChangingOtherTracks() {
        var preferences = CompanionPreferences(defaults: defaults)
        preferences.saveTimingOffset(1.25, for: "artist|song|album")
        preferences.saveTimingOffset(-0.75, for: "other|song|album")

        preferences.resetTimingOffset(for: "artist|song|album")

        XCTAssertEqual(preferences.timingOffset(for: "artist|song|album"), 0)
        XCTAssertEqual(preferences.timingOffset(for: "other|song|album"), -0.75)
    }

    func testResetAllTimingClearsSongOffsetsAndLearnedBaseline() {
        var preferences = CompanionPreferences(defaults: defaults)
        preferences.saveTimingOffset(0.8, for: "artist|song|album")
        preferences.saveLearnedTimingOffset(0.35)

        preferences.resetAllTimingOffsets()

        XCTAssertEqual(preferences.timingOffset(for: "artist|song|album"), 0)
        XCTAssertEqual(preferences.learnedTimingOffset, 0)
    }

    func testLyricCandidateChoicePersistsPerTrack() {
        var preferences = CompanionPreferences(defaults: defaults)
        preferences.selectLyricCandidate("lrclib-42", for: "artist|song|album")

        preferences = CompanionPreferences(defaults: defaults)
        XCTAssertEqual(
            preferences.selectedLyricCandidate(for: "artist|song|album"),
            "lrclib-42"
        )
    }
}
