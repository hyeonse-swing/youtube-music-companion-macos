import XCTest
@testable import YTMusicCompanion

final class AppInformationTests: XCTestCase {
    func testVersionTextIncludesReleaseAndBuildNumbers() {
        let information = AppInformation(
            version: "0.3.0",
            build: "3",
            bundleIdentifier: "com.hyeonseswing.YTMusicCompanion",
            isDiscordConfigured: true
        )

        XCTAssertEqual(information.versionText, "Version 0.3.0 (3)")
    }

    func testDiscordStatusDescribesBothStates() {
        let configured = information(isDiscordConfigured: true)
        let unconfigured = information(isDiscordConfigured: false)

        XCTAssertEqual(configured.discordStatus, "Configured")
        XCTAssertEqual(unconfigured.discordStatus, "Not Configured")
    }

    private func information(isDiscordConfigured: Bool) -> AppInformation {
        AppInformation(
            version: "Development",
            build: "—",
            bundleIdentifier: "com.hyeonseswing.YTMusicCompanion",
            isDiscordConfigured: isDiscordConfigured
        )
    }
}
