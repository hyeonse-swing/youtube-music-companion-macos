import Cocoa
import SwiftUI

/// Hosting view that forwards vertical scroll-wheel input — used to calibrate
/// the lyric sync offset by scrolling over the overlay.
final class ScrollHostingView<V: View>: NSHostingView<V> {
    var onScroll: ((CGFloat) -> Void)?
    var onDragEnded: ((NSPoint) -> Void)?

    override func scrollWheel(with event: NSEvent) {
        let dy = event.scrollingDeltaY != 0 ? event.scrollingDeltaY : event.deltaY
        if dy != 0 { onScroll?(dy) }
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        window.performDrag(with: event)
        onDragEnded?(window.frame.origin)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .openHand)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private let discord = DiscordRPC(clientID: AppConfiguration.discordClientID)
    private lazy var model = PlayerModel(
        presenceController: DiscordPresenceController(publisher: discord)
    )
    private var hoverTimer: Timer?
    private var activity: NSObjectProtocol?
    private var menuBar: MenuBar?
    private let overlayPositionStore = OverlayPositionStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Prevent App Nap from throttling our polling + network while unfocused,
        // but still allow the Mac to idle-sleep normally — a passive overlay has
        // no business keeping the machine awake. (.userInitiated would imply
        // .idleSystemSleepDisabled; the …AllowingIdleSystemSleep variant doesn't.)
        activity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "Live lyrics overlay"
        )

        let width = OverlayStyle.windowWidth
        let height = OverlayStyle.windowHeight

        let windowSize = NSSize(width: width, height: height)
        let frame = overlayPositionStore.initialFrame(size: windowSize)

        window = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.ignoresMouseEvents = true   // click-through HUD
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        let host = ScrollHostingView(rootView: LyricsView().environmentObject(model))
        host.onScroll = { [weak self] dy in
            // Scale the correction by how hard you scroll: a gentle nudge fine-tunes
            // (~0.02s), a firm flick covers whole seconds — so a 3–4s shift is a quick
            // gesture, not 70 ticks. Magnitude clamped per-event to stay controllable.
            let step = min(0.5, max(0.02, abs(dy) * 0.02))
            MainActor.assumeIsolated { self?.model.nudgeSync(by: dy > 0 ? step : -step) }
        }
        host.onDragEnded = { [weak self] origin in
            self?.overlayPositionStore.save(origin: origin)
        }
        host.frame = NSRect(origin: .zero, size: frame.size)
        host.autoresizingMask = [.width, .height]
        window.contentView = host
        // Stays hidden until there's something to show; the timer below brings it
        // on/off screen as music + lyrics come and go.

        // Cheap, permission-free hover detection: poll the cursor position and
        // check whether it's inside the overlay's frame.
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {       // Timer fires on the main run loop
                guard let self else { return }

                // Show the window only when there's something to display AND the
                // user hasn't disabled the overlay from the menubar; otherwise take
                // it off screen entirely so it can't catch hover or scroll.
                let show = self.model.hasContent && self.model.overlayEnabled
                if self.window.isVisible != show {
                    if show {
                        self.window.orderFrontRegardless()
                    } else {
                        self.window.orderOut(nil)
                        self.model.isHovering = false
                        self.window.ignoresMouseEvents = true
                    }
                }
                guard show else { return }

                // Only the current line's visible text is interactive: a centred band
                // sized to the rendered glyphs (see currentLineRect). The cursor there
                // captures scroll (to calibrate) and brightens the overlay; everywhere
                // else — including the empty margins beside the text — the window stays
                // click-through, so it never blocks the large area it covers.
                let onText = self.currentLineRect(in: self.window.frame)?
                    .contains(NSEvent.mouseLocation) ?? false
                if onText != self.model.isHovering {
                    self.model.isHovering = onText
                    self.window.ignoresMouseEvents = !onText
                }
            }
        }

        // Retain the menubar status item — without a strong reference it vanishes.
        menuBar = MenuBar(model: model) { [weak self] in
            self?.resetOverlayPosition()
        }

        model.start()

        // QA helper for a menu-bar agent whose status item is otherwise difficult to
        // drive in automated UI checks: launch with `--show-about` to open the same
        // information panel as the menu item.
        if CommandLine.arguments.contains("--show-about") {
            DispatchQueue.main.async {
                self.menuBar?.showAppInformation()
            }
        }
        if CommandLine.arguments.contains("--show-now-playing") {
            DispatchQueue.main.async {
                self.menuBar?.showNowPlayingPanel()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
    }

    private func resetOverlayPosition() {
        overlayPositionStore.reset()
        let size = NSSize(width: OverlayStyle.windowWidth, height: OverlayStyle.windowHeight)
        window.setFrame(OverlayPositionStore.defaultFrame(size: size), display: true, animate: true)
    }

    /// Screen-space rect of the current lyric line's visible text: a centred band
    /// just wide enough for the rendered glyphs (clamped to the text area, plus a
    /// little slack), one row tall, at the current-line position. `nil` when there's
    /// no line to target (no lyrics yet / still loading) — then nothing is interactive
    /// and the whole window is click-through.
    private func currentLineRect(in frame: NSRect) -> NSRect? {
        let lines = model.lines
        guard !lines.isEmpty else { return nil }
        // Before the first line starts (currentIndex == -1) the upcoming line 0 is the
        // sensible target; otherwise clamp into range defensively.
        let idx = max(0, min(model.currentIndex, lines.count - 1))
        let text = lines[idx].text.isEmpty ? "♪" : lines[idx].text

        let maxContentWidth = frame.width - 2 * OverlayStyle.horizontalPadding
        let measured = (text as NSString).size(withAttributes: [.font: OverlayStyle.currentLineFont]).width
        // minimumScaleFactor shrinks an over-long line to fit the text area, so the
        // rendered width never exceeds maxContentWidth.
        let width = min(measured, maxContentWidth) + 2 * OverlayStyle.hitMargin

        return NSRect(
            x: frame.midX - width / 2,
            y: frame.minY + OverlayStyle.currentLineFromBottom - OverlayStyle.rowHeight / 2,
            width: width,
            height: OverlayStyle.rowHeight
        )
    }
}

// Debug: resolve the current MediaRemote snapshot exactly as the running app will.
if CommandLine.arguments.contains("--now-original") {
    guard let source = MediaRemoteBridge.query() else {
        print("NOW → nothing playing")
        exit(1)
    }
    let metadata = OriginalScriptMetadataResolver().resolve(for: source) ?? source.metadata
    print("SOURCE   → \(source.artist) — \(source.title) [\(source.album)]")
    print("ORIGINAL → \(metadata.artist) — \(metadata.title) [\(metadata.album)]")
    exit(0)
}

// Debug: `YTMusicCompanion --now` → print the current MediaRemote read once, exit.
if CommandLine.arguments.contains("--now") {
    if let np = MediaRemoteBridge.query() {
        print("NOW → \(np.artist) — \(np.title)  [playing=\(np.isPlaying) rate=\(np.rate) " +
              "elapsed=\(np.elapsed) dur=\(np.duration) source=\(np.sourceBundle.isEmpty ? "?" : np.sourceBundle)]")
    } else {
        print("NOW → nothing playing")
    }
    exit(0)
}

// Debug: fetch the same MediaRemote image bytes used by the panel, then verify a
// public Discord-compatible URL against them. No image is written to disk.
if CommandLine.arguments.contains("--now-artwork") {
    guard let artwork = DefaultNowPlayingArtworkQuery().query() else {
        print("ARTWORK → unavailable")
        exit(1)
    }
    print("ARTWORK → \(artwork.width)x\(artwork.height), \(artwork.data.count) bytes")

    guard let source = MediaRemoteBridge.query() else {
        print("DISCORD → no current track")
        exit(1)
    }
    let metadata = OriginalScriptMetadataResolver().resolve(for: source) ?? source.metadata
    let display = source.applying(metadata)
    let candidates = ITunesArtworkCatalog().candidateURLs(for: display)
    print("CATALOG → \(candidates.count) plausible public cover(s)")
    if let url = VerifiedArtworkResolver().coverURL(for: display, sourceArtwork: artwork) {
        print("DISCORD → \(url)")
        exit(0)
    }
    print("DISCORD → no pixel-verified public match; using app icon")
    exit(0)
}

// Debug: resolve a localized/romanized label through the Japanese storefront.
// `YTMusicCompanion --metadata "Artist" "Title" duration ["Album"]`
if let index = CommandLine.arguments.firstIndex(of: "--metadata") {
    let arguments = CommandLine.arguments
    guard index + 3 < arguments.count else {
        FileHandle.standardError.write(
            "usage: YTMusicCompanion --metadata \"Artist\" \"Title\" <duration> [\"Album\"]\n"
                .data(using: .utf8)!
        )
        exit(2)
    }

    let source = NowPlaying(
        title: arguments[index + 2],
        artist: arguments[index + 1],
        album: index + 4 < arguments.count ? arguments[index + 4] : "",
        duration: Double(arguments[index + 3]) ?? 0,
        elapsed: 0,
        timestamp: 0,
        isPlaying: true,
        rate: 1,
        sourceBundle: "",
        sourcePID: 0
    )
    let metadata = OriginalScriptMetadataResolver().resolve(for: source) ?? source.metadata
    print("SOURCE   → \(source.artist) — \(source.title) [\(source.album)]")
    print("ORIGINAL → \(metadata.artist) — \(metadata.title) [\(metadata.album)]")
    exit(0)
}

// Debug: `YTMusicCompanion --probe "Artist" "Title" duration` → fetch + print, exit.
if CommandLine.arguments.first(where: { $0 == "--probe" }) != nil {
    let a = CommandLine.arguments
    guard a.count >= 5 else {
        FileHandle.standardError.write("usage: YTMusicCompanion --probe \"Artist\" \"Title\" <duration>\n".data(using: .utf8)!)
        exit(2)
    }
    let np = NowPlaying(title: a[3], artist: a[2], album: "",
                        duration: Double(a[4]) ?? 0, elapsed: 0, timestamp: 0,
                        isPlaying: true, rate: 1, sourceBundle: "", sourcePID: 0)
    // nil = transient failure (504/non-JSON/network) — distinct from a definitive
    // empty result, which prints "0 lines".
    guard let lines = LRCLIB.fetchSynced(for: np) else {
        FileHandle.standardError.write("PROBE → FAILED (transient: 504/non-JSON/network)\n".data(using: .utf8)!)
        exit(1)
    }
    FileHandle.standardError.write("PROBE → \(lines.count) lines\n".data(using: .utf8)!)
    for l in lines.prefix(4) {
        FileHandle.standardError.write("  [\(l.time)] \(l.text)\n".data(using: .utf8)!)
    }
    exit(0)
}

// Debug: `YTMusicCompanion --art "Artist" "Title"` → print the cover lookup result.
if CommandLine.arguments.contains("--art") {
    let a = CommandLine.arguments
    guard a.count >= 4, let i = a.firstIndex(of: "--art"), i + 2 < a.count else {
        FileHandle.standardError.write("usage: YTMusicCompanion --art \"Artist\" \"Title\"\n".data(using: .utf8)!)
        exit(2)
    }
    let artist = a[i + 1], title = a[i + 2]
    print("iTunes → \(Artwork.iTunesCoverURL(title: title, artist: artist, album: "") ?? "no match")")
    if let url = Artwork.coverURL(title: title, artist: artist, album: "") {
        print("resolved → \(url)")
        exit(0)
    } else {
        FileHandle.standardError.write("resolved → no match\n".data(using: .utf8)!)
        exit(1)
    }
}

// Debug: `YTMusicCompanion --discord` → connect, send a test activity, hold ~3s so you
// can eyeball Discord, then clear + exit. End-to-end IPC check.
if CommandLine.arguments.contains("--discord") {
    guard let clientID = AppConfiguration.discordClientID else {
        print("Discord client ID is not configured")
        exit(2)
    }
    let rpc = DiscordRPC(clientID: clientID)
    let group = DispatchGroup()
    group.enter()
    rpc.connect { found, ready in
        print("socket found: \(found)")
        print("READY received: \(ready)")
        guard found, ready else {
            print(found ? "handshake failed" : "Discord not running")
            group.leave()
            return
        }
        let now = Date()
        rpc.setActivity(.init(
            name: "Test Title - Test Artist",
            details: "Test Title",
            state: "Test Artist",
            start: now,
            end: now.addingTimeInterval(180),
            largeImage: YouTubeMusicSource.discordAssetKey,
            largeImageText: "Test Album",
            smallImage: YouTubeMusicSource.discordAssetKey,
            smallImageText: YouTubeMusicSource.displayName
        )) { sent in
            print("activity sent: \(sent)")
            group.leave()
        }
    }
    group.wait()
    // Hold briefly so the presence is visible in Discord, then clear and exit.
    Thread.sleep(forTimeInterval: 3)
    rpc.clear()
    Thread.sleep(forTimeInterval: 0.3)   // let the clear flush before we exit
    rpc.disconnect()
    exit(0)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)   // no Dock icon; pure overlay agent
    app.run()
}
