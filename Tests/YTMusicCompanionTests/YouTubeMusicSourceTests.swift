import XCTest
@testable import YTMusicCompanion

final class YouTubeMusicSourceTests: XCTestCase {
    func testRecognizesChromiumYouTubeMusicApps() {
        XCTAssertTrue(YouTubeMusicSource.matches(
            bundle: "com.google.Chrome.app.cinhimbnkkaeohfgghhklpknlkffjgod",
            pid: 0
        ))
        XCTAssertTrue(YouTubeMusicSource.matches(
            bundle: "com.brave.Browser.app.cinhimbnkkaeohfgghhklpknlkffjgod",
            pid: 0
        ))
        XCTAssertTrue(YouTubeMusicSource.matches(
            bundle: "com.microsoft.edgemac.app.cinhimbnkkaeohfgghhklpknlkffjgod",
            pid: 0
        ))
    }

    func testRejectsEveryOtherMediaSource() {
        XCTAssertFalse(YouTubeMusicSource.matches(bundle: "com.google.Chrome", pid: 0))
        XCTAssertFalse(YouTubeMusicSource.matches(bundle: "com.apple.Safari", pid: 0))
        XCTAssertFalse(YouTubeMusicSource.matches(bundle: "com.apple.Music", pid: 0))
        XCTAssertFalse(YouTubeMusicSource.matches(bundle: "com.spotify.client", pid: 0))
        XCTAssertFalse(YouTubeMusicSource.matches(bundle: "ru.keepcoder.Telegram", pid: 0))
        XCTAssertFalse(YouTubeMusicSource.matches(bundle: "", pid: 0))
    }

    func testLegacyLoaderRequiresAVerifiableProcess() {
        XCTAssertFalse(YouTubeMusicSource.matches(bundle: "app_mode_loader", pid: 0))
    }

    func testDiscordPresentationMetadataIsYouTubeMusicOnly() {
        XCTAssertEqual(YouTubeMusicSource.discordAssetKey, "youtube-music")
        XCTAssertEqual(YouTubeMusicSource.displayName, "YouTube Music")
    }
}
