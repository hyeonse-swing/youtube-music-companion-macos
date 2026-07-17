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
        XCTAssertFalse(preferences.showsRomanizedLyrics)
        XCTAssertFalse(preferences.showsTranslatedLyrics)
        XCTAssertEqual(preferences.translationTargetLanguage, .system)
        XCTAssertEqual(preferences.translationTone, .naturalLyrics)
        XCTAssertEqual(preferences.displayMetadataSource, .youtubeMusic)
        XCTAssertEqual(preferences.discordMetadataSource, .youtubeMusic)
        XCTAssertEqual(preferences.discordPresenceConfiguration, .standard)
        XCTAssertEqual(preferences.overlayPreset, .balanced)
        XCTAssertFalse(preferences.karaokeModeEnabled)
    }

    func testOverlayAppearanceChoicesPersist() {
        var preferences = CompanionPreferences(defaults: defaults)
        preferences.overlayPreset = .stage
        preferences.karaokeModeEnabled = true

        preferences = CompanionPreferences(defaults: defaults)

        XCTAssertEqual(preferences.overlayPreset, .stage)
        XCTAssertTrue(preferences.karaokeModeEnabled)
    }

    func testLyricLayerChoicesPersist() {
        var preferences = CompanionPreferences(defaults: defaults)
        preferences.showsRomanizedLyrics = true
        preferences.showsTranslatedLyrics = true
        preferences.translationTargetLanguage = .korean
        preferences.translationTone = .system

        preferences = CompanionPreferences(defaults: defaults)

        XCTAssertTrue(preferences.showsRomanizedLyrics)
        XCTAssertTrue(preferences.showsTranslatedLyrics)
        XCTAssertEqual(preferences.translationTargetLanguage, .korean)
        XCTAssertEqual(preferences.translationTone, .system)
    }

    func testDiscordPresenceCustomizationPersists() {
        var customized = DiscordPresenceConfiguration(
            detailsTemplate: "Listening to {title}",
            stateTemplate: "by {artist}",
            imageTextTemplate: "from {album}",
            showsPlaybackTime: false,
            showsSongLink: false
        )
        customized.preset = .custom
        customized.pausePolicy = .keepForFifteenMinutes
        customized.linksDetailsToSong = true
        customized.linksStateToSong = true
        customized.linksCoverToSong = false
        customized.primaryButtonLabel = "Listen"
        customized.secondaryButtonLabel = "Artist"
        customized.secondaryButtonURL = "https://example.com/artist"
        var preferences = CompanionPreferences(defaults: defaults)
        preferences.discordPresenceConfiguration = customized

        preferences = CompanionPreferences(defaults: defaults)

        XCTAssertEqual(preferences.discordPresenceConfiguration, customized)
    }

    func testDiscordPrivateTrackIdentifiersAreHashedAndPersisted() {
        var preferences = CompanionPreferences(defaults: defaults)
        let identifier = "https://music.youtube.com/watch?v=private-song"

        preferences.setDiscordTrackPrivate(true, identifier: identifier)
        preferences = CompanionPreferences(defaults: defaults)

        XCTAssertTrue(preferences.isDiscordTrackPrivate(identifier: identifier))
        XCTAssertEqual(preferences.privateDiscordTrackCount, 1)
        let stored = defaults.stringArray(
            forKey: "discordPrivateTrackFingerprints"
        )
        XCTAssertEqual(stored?.count, 1)
        XCTAssertFalse(stored?.contains(identifier) == true)

        preferences.setDiscordTrackPrivate(false, identifier: identifier)
        XCTAssertFalse(preferences.isDiscordTrackPrivate(identifier: identifier))
        XCTAssertEqual(preferences.privateDiscordTrackCount, 0)
    }

    func testResetDiscordPresenceCustomizationReturnsToOriginalDefaults() {
        var preferences = CompanionPreferences(defaults: defaults)
        preferences.discordPresenceConfiguration = DiscordPresenceConfiguration(
            detailsTemplate: "Custom {title}",
            stateTemplate: "Custom {artist}",
            imageTextTemplate: "Custom {album}",
            showsPlaybackTime: false,
            showsSongLink: false
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
            sourceBundle: "com.google.Chrome", sourcePID: 1,
            trackURL: URL(string: "https://music.youtube.com/watch?v=abc123")
        )
        var macOSWithTrackURL = macOS
        macOSWithTrackURL.trackURL = youtubeMusic.trackURL

        XCTAssertEqual(
            MetadataSourcePreference.youtubeMusic.select(
                youtubeMusic: youtubeMusic,
                macOS: macOS
            ),
            youtubeMusic
        )
        XCTAssertEqual(
            MetadataSourcePreference.macOS.select(youtubeMusic: youtubeMusic, macOS: macOS),
            macOSWithTrackURL
        )
        XCTAssertEqual(
            MetadataSourcePreference.youtubeMusic.select(youtubeMusic: nil, macOS: macOS),
            macOS
        )
    }

    func testResetCurrentTimingRemovesTheSongEntryWithoutChangingOtherTracks() {
        var preferences = CompanionPreferences(defaults: defaults)
        preferences.saveTimingOffset(1.25, for: "artist|song|album")
        preferences.saveTimingOffset(-0.75, for: "other|song|album")

        preferences.resetTimingOffset(for: "artist|song|album")

        XCTAssertEqual(preferences.timingOffset(for: "artist|song|album"), 0)
        XCTAssertEqual(preferences.timingOffset(for: "other|song|album"), -0.75)
        let stored = defaults.dictionary(forKey: "syncTrackOffsets")
        XCTAssertNil(stored?["artist|song|album"])
        XCTAssertNotNil(stored?["other|song|album"])
    }

    func testUnknownTracksStartAtZeroAndRemoveTheLegacyLearnedBaseline() {
        defaults.set(-1.26, forKey: "syncLearnedOffset")
        var preferences = CompanionPreferences(defaults: defaults)
        preferences.saveTimingOffset(0.75, for: "known|song|album")

        XCTAssertEqual(preferences.timingOffset(for: "unknown|song|album"), 0)
        XCTAssertEqual(preferences.timingOffset(for: "known|song|album"), 0.75)
        XCTAssertNil(defaults.object(forKey: "syncLearnedOffset"))
    }

    func testResetAllTimingClearsSongOffsetsAndLegacyBaseline() {
        var preferences = CompanionPreferences(defaults: defaults)
        preferences.saveTimingOffset(0.8, for: "artist|song|album")
        defaults.set(0.35, forKey: "syncLearnedOffset")

        preferences.resetAllTimingOffsets()

        XCTAssertEqual(preferences.timingOffset(for: "artist|song|album"), 0)
        XCTAssertNil(defaults.object(forKey: "syncLearnedOffset"))
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
