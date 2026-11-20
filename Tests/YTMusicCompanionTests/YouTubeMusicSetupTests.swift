import Foundation
import XCTest
@testable import YTMusicCompanion

final class YouTubeMusicSetupTests: XCTestCase {
    private var temporaryDirectory: URL!
    private let bundleID = "com.google.Chrome.app.cinhimbnkkaeohfgghhklpknlkffjgod"

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: temporaryDirectory)
    }

    private func wrapper(identifier: String, shortcut: String, executable: Bool = true) throws -> URL {
        let url = temporaryDirectory.appendingPathComponent(UUID().uuidString + ".app", isDirectory: true)
        let macOS = url.appendingPathComponent("Contents/MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        let info: [String: Any] = [
            "CFBundleIdentifier": identifier,
            "CFBundlePackageType": "APPL",
            "CFBundleExecutable": "app_mode_loader",
            "CrAppModeShortcutURL": shortcut,
            "CrAppModeShortcutID": YouTubeMusicSetup.webAppID
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: url.appendingPathComponent("Contents/Info.plist"))
        if executable {
            FileManager.default.createFile(
                atPath: macOS.appendingPathComponent("app_mode_loader").path,
                contents: Data("#!/bin/sh\n".utf8),
                attributes: [.posixPermissions: 0o755]
            )
        }
        return url
    }

    func testAcceptsRealChromiumIdentityAndMusicOrigin() throws {
        let app = try wrapper(identifier: bundleID,
                              shortcut: "https://music.youtube.com/?source=pwa")
        XCTAssertTrue(YouTubeMusicSetup.isSupportedApp(at: app, bundleID: bundleID))
    }

    func testRejectsOtherSitesBrowsersAndIncompleteWrappers() throws {
        let wrongSite = try wrapper(identifier: bundleID,
                                    shortcut: "https://music.youtube.com.attacker.example/")
        let wrongPort = try wrapper(identifier: bundleID,
                                    shortcut: "https://music.youtube.com:444/")
        let wrongBrowser = try wrapper(identifier: "com.example.Browser.app." + YouTubeMusicSetup.webAppID,
                                       shortcut: "https://music.youtube.com/")
        let missingLoader = try wrapper(identifier: bundleID,
                                        shortcut: "https://music.youtube.com/", executable: false)
        XCTAssertFalse(YouTubeMusicSetup.isSupportedApp(at: wrongSite, bundleID: bundleID))
        XCTAssertFalse(YouTubeMusicSetup.isSupportedApp(at: wrongPort, bundleID: bundleID))
        XCTAssertFalse(YouTubeMusicSetup.isSupportedApp(at: wrongBrowser, bundleID: bundleID))
        XCTAssertFalse(YouTubeMusicSetup.isSupportedApp(at: missingLoader, bundleID: bundleID))
    }

    @MainActor
    func testMissingBrowserRetryAndInstallationDiscovery() {
        var discovered: [YouTubeMusicSetup.InstalledApp] = []
        var browsers: [YouTubeMusicSetup.Browser] = []
        var openedBrowser: YouTubeMusicSetup.Browser?
        var openCompletion: ((Bool) -> Void)?
        let actions = YouTubeMusicSetupState.Actions(
            discover: { discovered },
            availableBrowsers: { browsers },
            openInstallPage: { browser, completion in
                guard browsers.contains(browser) else { return false }
                openedBrowser = browser
                openCompletion = completion
                return true
            },
            launch: { _, _ in XCTFail("No installed app should be launched") }
        )
        let state = YouTubeMusicSetupState(actions: actions)

        state.refresh()
        XCTAssertTrue(state.installedApps.isEmpty)
        XCTAssertTrue(state.availableBrowsers.isEmpty)
        state.openInstallPage()
        XCTAssertEqual(state.issue, .browserUnavailable)
        XCTAssertNil(openedBrowser)

        browsers = [.edge, .brave]
        state.refresh()
        XCTAssertEqual(state.selectedBrowser, .edge)
        XCTAssertEqual(state.issue, .browserUnavailable)
        state.openInstallPage()
        XCTAssertEqual(openedBrowser, .edge)
        XCTAssertNil(state.issue)
        openCompletion?(false)
        XCTAssertEqual(state.issue, .installPageFailed)

        state.openInstallPage()
        openCompletion?(true)
        XCTAssertNil(state.issue)

        let app = YouTubeMusicSetup.InstalledApp(
            browserName: YouTubeMusicSetup.Browser.edge.name,
            profileName: "Profile 2",
            url: URL(fileURLWithPath: "/tmp/YouTube Music.app")
        )
        discovered = [app]
        state.refresh()
        XCTAssertEqual(state.installedApps, [app])
    }

    @MainActor
    func testInstalledAppLaunchFailureAndSuccess() {
        let app = YouTubeMusicSetup.InstalledApp(
            browserName: YouTubeMusicSetup.Browser.chrome.name,
            profileName: nil,
            url: URL(fileURLWithPath: "/tmp/YouTube Music.app")
        )
        var launchCompletion: ((Bool) -> Void)?
        let actions = YouTubeMusicSetupState.Actions(
            discover: { [app] },
            availableBrowsers: { [.chrome] },
            openInstallPage: { _, _ in XCTFail("Install page should not open"); return false },
            launch: { _, completion in launchCompletion = completion }
        )
        let state = YouTubeMusicSetupState(actions: actions)
        state.refresh()
        state.open(app)
        launchCompletion?(false)
        XCTAssertEqual(state.issue, .appLaunchFailed)
        state.open(app)
        launchCompletion?(true)
        XCTAssertNil(state.issue)
    }

    func testBrowserInstructionsAreAvailableInKoreanAndEnglish() {
        for browser in YouTubeMusicSetup.Browser.allCases {
            XCTAssertFalse(browser.installInstruction(korean: true).isEmpty)
            XCTAssertFalse(browser.installInstruction(korean: false).isEmpty)
        }
        XCTAssertTrue(YouTubeMusicSetup.Browser.chrome.installInstruction(korean: false)
            .contains("Install page as app"))
        XCTAssertTrue(YouTubeMusicSetup.Browser.edge.installInstruction(korean: false)
            .contains("Install this site as an app"))
        XCTAssertTrue(YouTubeMusicSetup.Browser.brave.installInstruction(korean: false)
            .contains("Install page as app"))
    }

    @MainActor
    func testBrowserDisappearingKeepsErrorWhileSelectingReplacement() {
        var browsers: [YouTubeMusicSetup.Browser] = [.chrome, .edge]
        var attempted: [YouTubeMusicSetup.Browser] = []
        let state = YouTubeMusicSetupState(actions: .init(
            discover: { [] },
            availableBrowsers: { browsers },
            openInstallPage: { browser, completion in
                attempted.append(browser)
                guard browsers.contains(browser) else { return false }
                completion(true)
                return true
            },
            launch: { _, _ in XCTFail("No installed app should be launched") }
        ))

        state.refresh()
        XCTAssertEqual(state.selectedBrowser, .chrome)
        browsers = [.edge]
        state.openInstallPage()
        XCTAssertEqual(attempted, [.chrome])
        XCTAssertEqual(state.selectedBrowser, .edge)
        XCTAssertEqual(state.issue, .browserUnavailable)
        state.refresh()
        XCTAssertEqual(state.issue, .browserUnavailable)
        state.openInstallPage()
        XCTAssertEqual(attempted, [.chrome, .edge])
        XCTAssertNil(state.issue)
    }

    @MainActor
    func testSetupWindowTitleTracksSelectedLanguage() {
        let controller = YouTubeMusicSetupWindowController()
        XCTAssertTrue(controller.window?.styleMask.contains(.resizable) ?? false)
        XCTAssertEqual(controller.window?.contentMinSize, NSSize(width: 530, height: 390))
        controller.updateLanguage(.english)
        XCTAssertEqual(controller.window?.title, "Set up YouTube Music")
        controller.updateLanguage(.korean)
        XCTAssertEqual(controller.window?.title, "YouTube Music 설정")
    }
}
