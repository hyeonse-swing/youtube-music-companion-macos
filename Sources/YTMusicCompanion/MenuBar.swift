import Cocoa

/// The menubar status item and its dropdown menu. Mirrors the sibling project's
/// systray: a template music-note icon, a disabled now-playing status row at the
/// top, then the actionable items, then Quit. Adapted for this overlay app — the
/// original's Pause/Resume of presence updates becomes a "Show Overlay" toggle.
///
/// Owned (and retained) by `AppDelegate`; an `NSStatusItem` with no strong
/// reference is released and silently vanishes from the menubar.
@MainActor
final class MenuBar: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let model: PlayerModel
    private let appInformationWindow = AppInformationWindowController()
    private var nowPlayingWindow: NowPlayingWindowController?
    private var settingsWindow: SettingsWindowController?
    private let resetOverlayPosition: () -> Void

    // Menu items we mutate from state — kept as references so we don't rebuild the
    // menu each time. The status row shows the current track; the toggle reflects
    // model.overlayEnabled.
    private let nowPlayingItem: NSMenuItem
    private let showNowPlayingItem: NSMenuItem
    private let exactMetadataItem: NSMenuItem
    private let showOverlayItem: NSMenuItem
    private let discordItem: NSMenuItem
    private let resetOverlayItem: NSMenuItem
    private let settingsItem: NSMenuItem
    private let quitItem: NSMenuItem
    private let aboutItem: NSMenuItem

    init(model: PlayerModel, resetOverlayPosition: @escaping () -> Void) {
        self.model = model
        self.resetOverlayPosition = resetOverlayPosition
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        nowPlayingItem = NSMenuItem(
            title: AppLocalization.string(
                "No YouTube Music playing",
                language: model.appLanguage
            ),
            action: nil,
            keyEquivalent: ""
        )
        nowPlayingItem.isEnabled = false

        showNowPlayingItem = NSMenuItem(
            title: AppLocalization.string(
                "Show Now Playing…",
                language: model.appLanguage
            ),
            action: #selector(showNowPlaying(_:)),
            keyEquivalent: ""
        )

        exactMetadataItem = NSMenuItem(
            title: AppLocalization.string(
                "Enable Exact YouTube Music Metadata…",
                language: model.appLanguage
            ),
            action: #selector(requestExactMetadataAccess(_:)),
            keyEquivalent: ""
        )

        showOverlayItem = NSMenuItem(
            title: AppLocalization.string("Show Overlay", language: model.appLanguage),
            action: #selector(toggleOverlay(_:)),
            keyEquivalent: ""
        )

        discordItem = NSMenuItem(
            title: AppLocalization.string(
                "Discord Rich Presence",
                language: model.appLanguage
            ),
            action: #selector(toggleDiscord(_:)),
            keyEquivalent: ""
        )

        resetOverlayItem = NSMenuItem(
            title: AppLocalization.string(
                "Reset Overlay Position",
                language: model.appLanguage
            ),
            action: #selector(resetLyricsPosition(_:)),
            keyEquivalent: ""
        )

        settingsItem = NSMenuItem(
            title: AppLocalization.string("Settings…", language: model.appLanguage),
            action: #selector(showSettings(_:)),
            keyEquivalent: ","
        )

        quitItem = NSMenuItem(
            title: AppLocalization.string("Quit", language: model.appLanguage),
            action: #selector(quit(_:)),
            keyEquivalent: "q"
        )

        aboutItem = NSMenuItem(
            title: AppLocalization.format(
                "About %@…",
                language: model.appLanguage,
                arguments: AppConfiguration.productName
            ),
            action: #selector(showAbout(_:)),
            keyEquivalent: ""
        )

        super.init()

        // The tray icon (a 44x44 template PNG, the music note from the sibling
        // telegram-audio-discord project), bundled via SwiftPM resources. It's
        // square, so it never squashes; isTemplate lets macOS tint it for light/dark
        // menubars. Size below is tuned to the original's menubar footprint.
        if let button = statusItem.button {
            let image = AppResources.url(
                forResource: "tray-icon",
                withExtension: "png"
            )
                .flatMap { NSImage(contentsOf: $0) }
            image?.isTemplate = true
            image?.size = NSSize(width: 16, height: 16)
            button.image = image
            button.toolTip = AppConfiguration.productName
        }

        let menu = NSMenu()
        menu.delegate = self

        showOverlayItem.target = self
        showOverlayItem.state = model.overlayEnabled ? .on : .off

        discordItem.target = self
        discordItem.isEnabled = model.isDiscordConfigured
        discordItem.state = model.discordEnabled ? .on : .off

        showNowPlayingItem.target = self
        showNowPlayingItem.isEnabled = model.hasNowPlaying
        exactMetadataItem.target = self
        resetOverlayItem.target = self
        settingsItem.target = self
        quitItem.target = self
        aboutItem.target = self
        updateLocalizedTitles()

        menu.addItem(nowPlayingItem)
        menu.addItem(.separator())
        menu.addItem(showNowPlayingItem)
        menu.addItem(exactMetadataItem)
        menu.addItem(showOverlayItem)
        menu.addItem(resetOverlayItem)
        menu.addItem(discordItem)
        menu.addItem(.separator())
        menu.addItem(settingsItem)
        menu.addItem(aboutItem)
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    /// Refresh the now-playing row and toggle state right before the menu opens —
    /// cheaper than a continuous loop, and the menu is the only place they're seen.
    func menuNeedsUpdate(_ menu: NSMenu) {
        updateLocalizedTitles()
        nowPlayingItem.title = model.nowPlayingDescription
        showNowPlayingItem.isEnabled = model.hasNowPlaying
        showOverlayItem.state = model.overlayEnabled ? .on : .off
        discordItem.state = model.discordEnabled ? .on : .off
    }

    func showAppInformation() {
        appInformationWindow.show(language: model.appLanguage)
    }

    func showNowPlayingPanel() {
        if let nowPlayingWindow {
            nowPlayingWindow.show()
            return
        }

        let controller = NowPlayingWindowController(model: model) { [weak self] in
            self?.nowPlayingWindow = nil
        }
        nowPlayingWindow = controller
        controller.show()
    }

    func showSettingsPanel() {
        if let settingsWindow {
            settingsWindow.show()
            return
        }

        let controller = SettingsWindowController(model: model) { [weak self] in
            self?.settingsWindow = nil
        }
        settingsWindow = controller
        controller.show()
    }

    @objc private func toggleOverlay(_ sender: NSMenuItem) {
        model.overlayEnabled.toggle()
        sender.state = model.overlayEnabled ? .on : .off
    }

    @objc private func toggleDiscord(_ sender: NSMenuItem) {
        // PlayerModel reacts in discordEnabled.didSet: OFF clears presence, ON
        // re-publishes the current track.
        model.discordEnabled.toggle()
        sender.state = model.discordEnabled ? .on : .off
    }

    @objc private func showNowPlaying(_ sender: NSMenuItem) {
        showNowPlayingPanel()
    }

    @objc private func requestExactMetadataAccess(_ sender: NSMenuItem) {
        model.requestExactMetadataAccess()
        updateExactMetadataItem()
    }

    @objc private func resetLyricsPosition(_ sender: NSMenuItem) {
        resetOverlayPosition()
    }

    @objc private func showAbout(_ sender: NSMenuItem) {
        showAppInformation()
    }

    @objc private func showSettings(_ sender: NSMenuItem) {
        showSettingsPanel()
    }

    @objc private func quit(_ sender: NSMenuItem) {
        NSApp.terminate(nil)
    }

    private func updateExactMetadataItem() {
        if model.hasExactMetadataAccess {
            exactMetadataItem.title = AppLocalization.string(
                "Exact YouTube Music Metadata",
                language: model.appLanguage
            )
            exactMetadataItem.state = .on
        } else {
            exactMetadataItem.title = AppLocalization.string(
                "Enable Exact YouTube Music Metadata…",
                language: model.appLanguage
            )
            exactMetadataItem.state = .off
        }
    }

    private func updateLocalizedTitles() {
        let language = model.appLanguage
        showNowPlayingItem.title = AppLocalization.string(
            "Show Now Playing…",
            language: language
        )
        showOverlayItem.title = AppLocalization.string(
            "Show Overlay",
            language: language
        )
        resetOverlayItem.title = AppLocalization.string(
            "Reset Overlay Position",
            language: language
        )
        discordItem.title = AppLocalization.string(
            model.isDiscordConfigured
                ? "Discord Rich Presence"
                : "Discord Rich Presence (Not Configured)",
            language: language
        )
        settingsItem.title = AppLocalization.string(
            "Settings…",
            language: language
        )
        quitItem.title = AppLocalization.string("Quit", language: language)
        aboutItem.title = AppLocalization.format(
            "About %@…",
            language: language,
            arguments: AppConfiguration.productName
        )
        updateExactMetadataItem()
    }
}
