import AppKit
import Foundation

/// Finds launchable Chromium web-app bundles for the same application ID that
/// MediaRemote recognizes. LaunchServices covers user-installed apps in other
/// profiles or locations without reading browser profile data.
enum YouTubeMusicSetup {
    static let webAppID = YouTubeMusicSource.webAppID
    static let musicURL = URL(string: "https://music.youtube.com/")!
    static let helpURL = URL(string: "https://support.google.com/youtubemusic/answer/9231765")!
    static let chromeDownloadURL = URL(string: "https://www.google.com/chrome/")!

    struct InstalledApp: Identifiable, Equatable {
        let browserName: String
        let profileName: String?
        let url: URL

        var id: URL { url }
    }

    enum Browser: String, CaseIterable, Identifiable {
        case chrome
        case brave
        case edge

        var id: String { rawValue }

        var name: String {
            switch self {
            case .chrome: "Google Chrome"
            case .brave: "Brave"
            case .edge: "Microsoft Edge"
            }
        }

        var bundleID: String {
            switch self {
            case .chrome: "com.google.Chrome"
            case .brave: "com.brave.Browser"
            case .edge: "com.microsoft.edgemac"
            }
        }

        func installInstruction(korean: Bool) -> String {
            switch self {
            case .chrome:
                korean ? "주소창의 설치 아이콘 또는 ⋮ → 전송, 저장 및 공유 → 페이지를 앱으로 설치" :
                    "Select the install icon, or ⋮ → Cast, save, and share → Install page as app"
            case .brave:
                korean ? "주소창의 설치 아이콘 또는 메뉴 → 저장 및 공유 → 페이지를 앱으로 설치" :
                    "Select the install icon, or Menu → Save and Share → Install page as app"
            case .edge:
                korean ? "주소창의 설치 아이콘 또는 ⋯ → 기타 도구 → 앱 → 이 사이트를 앱으로 설치" :
                    "Select the install icon, or ⋯ → More tools → Apps → Install this site as an app"
            }
        }
    }

    @MainActor
    static func discover(workspace: NSWorkspace = .shared) -> [InstalledApp] {
        var installed: [InstalledApp] = []
        for browser in Browser.allCases {
            let bundleID = "\(browser.bundleID).app.\(webAppID)"
            for url in workspace.urlsForApplications(withBundleIdentifier: bundleID) {
                if isSupportedApp(at: url, bundleID: bundleID) {
                    installed.append(InstalledApp(browserName: browser.name,
                                                  profileName: profileName(at: url), url: url))
                }
            }
        }
        return installed.sorted {
            $0.browserName == $1.browserName
                ? $0.url.path < $1.url.path
                : $0.browserName < $1.browserName
        }
    }

    @MainActor
    static func availableBrowsers(workspace: NSWorkspace = .shared) -> [Browser] {
        Browser.allCases.filter { workspace.urlForApplication(withBundleIdentifier: $0.bundleID) != nil }
    }

    private static func profileName(at url: URL) -> String? {
        guard let bundle = Bundle(url: url),
              let path = bundle.object(forInfoDictionaryKey: "CrAppModeUserDataDir") as? String
        else { return nil }
        let appData = URL(fileURLWithPath: path)
        let applications = appData.deletingLastPathComponent()
        guard applications.lastPathComponent == "Web Applications" else { return nil }
        let profile = applications.deletingLastPathComponent().lastPathComponent
        return profile == "-" ? nil : profile
    }

    /// The bundle ID is the playback identity; the shortcut URL confirms that
    /// a registered wrapper still points at the YouTube Music service.
    static func isSupportedApp(at url: URL, bundleID: String) -> Bool {
        guard url.isFileURL, url.pathExtension == "app",
              let bundle = Bundle(url: url),
              bundle.bundleIdentifier == bundleID,
              let shortcut = bundle.object(forInfoDictionaryKey: "CrAppModeShortcutURL") as? String,
              let target = URL(string: shortcut),
              target.scheme == "https", target.host == "music.youtube.com",
              target.port == nil || target.port == 443,
              target.user == nil, target.password == nil,
              bundle.object(forInfoDictionaryKey: "CrAppModeShortcutID") as? String == webAppID,
              FileManager.default.isExecutableFile(atPath: bundle.executableURL?.path ?? "")
        else { return false }
        return true
    }

    @MainActor
    static func launch(_ app: InstalledApp, workspace: NSWorkspace = .shared,
                       completion: @escaping (Bool) -> Void) {
        guard let browser = Browser.allCases.first(where: { $0.name == app.browserName }),
              isSupportedApp(at: app.url, bundleID: "\(browser.bundleID).app.\(webAppID)")
        else {
            completion(false)
            return
        }
        workspace.openApplication(at: app.url, configuration: NSWorkspace.OpenConfiguration()) {
            runningApp, error in
            DispatchQueue.main.async { completion(runningApp != nil && error == nil) }
        }
    }

    @MainActor
    static func openInstallPage(in browser: Browser = .chrome,
                                workspace: NSWorkspace = .shared,
                                completion: @escaping (Bool) -> Void) -> Bool {
        guard let browserURL = workspace.urlForApplication(withBundleIdentifier: browser.bundleID) else {
            return false
        }
        workspace.open([musicURL], withApplicationAt: browserURL,
                       configuration: NSWorkspace.OpenConfiguration()) { apps, error in
            DispatchQueue.main.async { completion(apps != nil && error == nil) }
        }
        return true
    }

    @MainActor
    static func openHelp(workspace: NSWorkspace = .shared) {
        workspace.open(helpURL)
    }

    @MainActor
    static func openChromeDownload(workspace: NSWorkspace = .shared) {
        workspace.open(chromeDownloadURL)
    }
}
