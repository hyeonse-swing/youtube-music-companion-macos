import AppKit
import Combine
import SwiftUI

@MainActor
final class YouTubeMusicSetupState: ObservableObject {
    @MainActor
    struct Actions {
        let discover: () -> [YouTubeMusicSetup.InstalledApp]
        let availableBrowsers: () -> [YouTubeMusicSetup.Browser]
        let openInstallPage: (YouTubeMusicSetup.Browser, @escaping (Bool) -> Void) -> Bool
        let launch: (YouTubeMusicSetup.InstalledApp, @escaping (Bool) -> Void) -> Void

        static var live: Actions {
            Actions(discover: { YouTubeMusicSetup.discover() },
                    availableBrowsers: { YouTubeMusicSetup.availableBrowsers() },
                    openInstallPage: { browser, completion in
                        YouTubeMusicSetup.openInstallPage(in: browser, completion: completion)
                    },
                    launch: { app, completion in YouTubeMusicSetup.launch(app, completion: completion) })
        }
    }

    enum Issue: Equatable {
        case browserUnavailable
        case installPageFailed
        case appLaunchFailed
    }

    private let actions: Actions
    @Published private(set) var installedApps: [YouTubeMusicSetup.InstalledApp] = []
    @Published private(set) var availableBrowsers: [YouTubeMusicSetup.Browser] = []
    @Published var selectedBrowser: YouTubeMusicSetup.Browser = .chrome
    @Published var issue: Issue?

    init(actions: Actions? = nil) {
        self.actions = actions ?? .live
    }

    func refresh() {
        installedApps = actions.discover()
        availableBrowsers = actions.availableBrowsers()
        if !availableBrowsers.contains(selectedBrowser), let first = availableBrowsers.first {
            selectedBrowser = first
        }
    }

    func open(_ app: YouTubeMusicSetup.InstalledApp) {
        issue = nil
        actions.launch(app) { [weak self] launched in
            if !launched {
                self?.issue = .appLaunchFailed
                self?.refresh()
            }
        }
    }

    func openInstallPage() {
        issue = nil
        if !actions.openInstallPage(selectedBrowser, { [weak self] opened in
            if !opened { self?.issue = .installPageFailed }
        }) {
            issue = .browserUnavailable
            refresh()
        }
    }
}

private struct YouTubeMusicSetupView: View {
    @ObservedObject var state: YouTubeMusicSetupState
    let language: AppLanguage

    private var korean: Bool { language.resolvedIdentifier == "ko" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label("YouTube Music", systemImage: "music.note")
                .font(.title2.weight(.semibold))
                .padding(.bottom, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if state.installedApps.isEmpty {
                        missingAppContent
                    } else {
                        installedAppContent
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
                .padding(.trailing, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let issue = state.issue {
                Text(issueText(issue))
                    .foregroundStyle(.red)
                    .accessibilityAddTraits(.updatesFrequently)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }

            Divider().padding(.top, 12)
            footer.padding(.top, 12)
        }
        .padding(24)
        .frame(minWidth: 530, minHeight: 390)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.locale, language.locale)
    }

    private var missingAppContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(korean ? "YouTube Music 앱 설치" : "Install the YouTube Music app")
                .font(.headline)
            Text(korean
                ? "브라우저에서 YouTube Music을 열고 설치를 확인하세요. 설치가 끝나면 이 창에서 앱을 찾아 바로 열 수 있습니다."
                : "Open YouTube Music in a browser and confirm installation. This window will find the app so you can open it directly.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if state.availableBrowsers.isEmpty {
                Text(korean ? "지원하는 브라우저를 찾지 못했습니다." : "No supported browser was found.")
            } else {
                Picker(korean ? "브라우저" : "Browser", selection: $state.selectedBrowser) {
                    ForEach(state.availableBrowsers) { browser in
                        Text(browser.name).tag(browser)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 8) {
                    Text(korean ? "1. 선택한 브라우저에서 YouTube Music 열기" : "1. Open YouTube Music in the selected browser")
                    Text("2. " + state.selectedBrowser.installInstruction(korean: korean))
                    Text(korean ? "3. 설치를 확인하고 YouTube Music 앱에서 재생" : "3. Confirm installation and play music in the YouTube Music app")
                }
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var installedAppContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(korean ? "설치된 YouTube Music 앱" : "Installed YouTube Music apps")
                .font(.headline)
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(state.installedApps) { app in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading) {
                            Text("YouTube Music").fontWeight(.medium)
                            Text(app.profileName.map { "\(app.browserName) · \($0)" } ?? app.browserName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Button(korean ? "앱 열기" : "Open app") { state.open(app) }
                    }
                }
            }
        }
    }

    private var footer: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                primaryAction.fixedSize()
                refreshAction.fixedSize()
                Spacer(minLength: 8)
                helpAction.fixedSize()
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    primaryAction.fixedSize()
                    refreshAction.fixedSize()
                }
                helpAction
            }
            VStack(alignment: .leading, spacing: 8) {
                primaryAction
                refreshAction
                helpAction
            }
        }
    }

    @ViewBuilder
    private var primaryAction: some View {
        if state.installedApps.isEmpty {
            if state.availableBrowsers.isEmpty {
                Button(korean ? "Chrome 다운로드" : "Get Chrome") {
                    YouTubeMusicSetup.openChromeDownload()
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button(korean ? "설치 시작" : "Start installation") { state.openInstallPage() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private var refreshAction: some View {
        Button(korean ? "다시 확인" : "Check again") { state.refresh() }
    }

    private var helpAction: some View {
        Button(korean ? "YouTube Music 설치 도움말" : "YouTube Music installation help") {
            YouTubeMusicSetup.openHelp()
        }
    }

    private func issueText(_ issue: YouTubeMusicSetupState.Issue) -> String {
        switch issue {
        case .browserUnavailable:
            korean ? "선택한 브라우저를 열지 못했습니다. 다시 확인하세요." : "The selected browser is unavailable. Check again."
        case .installPageFailed:
            korean ? "설치 페이지를 열지 못했습니다. 다시 시도하세요." : "Could not open the installation page. Try again."
        case .appLaunchFailed:
            korean ? "설치된 앱을 열지 못했습니다. 다시 확인하세요." : "Could not open the installed app. Check again."
        }
    }
}

@MainActor
final class YouTubeMusicSetupWindowController: NSWindowController, NSWindowDelegate {
    private let state = YouTubeMusicSetupState()
    private var refreshTimer: Timer?

    init() {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 530, height: 390),
                            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        super.init(window: panel)
        panel.delegate = self
        panel.isReleasedWhenClosed = false
        panel.contentMinSize = NSSize(width: 530, height: 390)
        panel.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    func show(language: AppLanguage = .system) {
        guard let window else { return }
        updateLanguage(language)
        refresh()
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func updateLanguage(_ language: AppLanguage) {
        guard let window else { return }
        window.title = language.resolvedIdentifier == "ko" ? "YouTube Music 설정" : "Set up YouTube Music"
        window.contentView = NSHostingView(rootView: YouTubeMusicSetupView(state: state, language: language))
    }

    func refresh() { state.refresh() }

    func windowWillClose(_ notification: Notification) {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
}
