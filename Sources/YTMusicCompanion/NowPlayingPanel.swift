import AppKit
import Combine
import SwiftUI

enum PlaybackTimeFormatter {
    static func string(seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct NowPlayingPanelView: View {
    @ObservedObject var model: PlayerModel
    let isCompact: Bool
    let toggleCompact: () -> Void
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 10 : 18) {
            HStack {
                Text("Now Playing")
                    .font(isCompact ? .headline : .title3.weight(.semibold))
                Spacer()
                Button {
                    toggleCompact()
                } label: {
                    Label(
                        isCompact ? "Expand Player" : "Pin to Side",
                        systemImage: isCompact ? "arrow.up.left.and.arrow.down.right" : "sidebar.right"
                    )
                }
                .labelStyle(.iconOnly)
                .help(isCompact ? "Expand Player" : "Pin to Side")
                .accessibilityLabel(isCompact ? "Expand Player" : "Pin to Side")
                if isCompact {
                    Button(action: close) {
                        Label("Close Now Playing", systemImage: "xmark")
                    }
                    .labelStyle(.iconOnly)
                    .help("Close Now Playing")
                    .accessibilityLabel("Close Now Playing")
                }
            }

            if let source = model.sourceNowPlaying {
                if isCompact {
                    compactTrackContent(source: source, display: model.displayNowPlaying ?? source)
                } else {
                    trackContent(source: source, display: model.displayNowPlaying ?? source)
                }
            } else {
                AppContentUnavailableView(
                    "Nothing Playing",
                    systemImage: "music.note",
                    description: Text("Start a song in YouTube Music to see it here.")
                )
                .frame(height: isCompact ? 125 : 230)
            }
        }
        .padding(isCompact ? 14 : 24)
        .frame(width: isCompact ? 310 : 500)
        .environment(\.locale, model.appLanguage.locale)
    }

    private func compactTrackContent(source: NowPlaying, display: NowPlaying) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ArtworkThumbnailView(artwork: model.nowPlayingArtwork, title: display.title, size: 52)
                    .equatable()
                VStack(alignment: .leading, spacing: 2) {
                    Text(display.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                    Text(display.artist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                let elapsed = model.playbackElapsed
                VStack(spacing: 5) {
                    ProgressView(
                        value: min(elapsed, max(source.duration, 1)),
                        total: max(source.duration, 1)
                    )
                    .accessibilityLabel("Playback progress")
                    HStack {
                        Text(PlaybackTimeFormatter.string(seconds: elapsed))
                        Spacer()
                        Text(model.isPlaying ? "Playing" : "Paused")
                        Spacer()
                        Text(PlaybackTimeFormatter.string(seconds: source.duration))
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func trackContent(source: NowPlaying, display: NowPlaying) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                ArtworkThumbnailView(
                    artwork: model.nowPlayingArtwork,
                    title: display.title
                )
                .equatable()

                VStack(alignment: .leading, spacing: 4) {
                    Text(display.title)
                        .font(.title2.weight(.semibold))
                        .lineLimit(2)
                        .textSelection(.enabled)
                    Text(display.artist)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .textSelection(.enabled)
                    if !display.album.isEmpty {
                        Text(display.album)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .textSelection(.enabled)
                    }
                }
                Spacer(minLength: 0)
            }

            TimelineView(.periodic(from: .now, by: 1)) { _ in
                let elapsed = model.playbackElapsed
                VStack(spacing: 7) {
                    ProgressView(
                        value: min(elapsed, max(source.duration, 1)),
                        total: max(source.duration, 1)
                    )
                    .accessibilityLabel("Playback progress")

                    HStack {
                        Text(PlaybackTimeFormatter.string(seconds: elapsed))
                        Spacer()
                        Text(PlaybackTimeFormatter.string(seconds: source.duration))
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
            }

            HStack {
                Label(
                    model.isPlaying ? "Playing" : "Paused",
                    systemImage: model.isPlaying ? "play.fill" : "pause.fill"
                )
                Spacer()
                Label("YouTube Music", systemImage: "music.note.list")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

        }
    }
}

/// Artwork decoding is intentionally isolated in an equatable child view. Playback
/// clock publications can refresh the panel several times per second, while the
/// cover normally changes only once per track.
private struct ArtworkThumbnailView: View, Equatable {
    let artwork: NowPlayingArtwork?
    let title: String
    var size: CGFloat = 72

    var body: some View {
        if
            let data = artwork?.data,
            let image = NSImage(data: data)
        {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityLabel("Album artwork for \(title)")
        } else {
            Image(systemName: "music.note")
                .font(.system(size: size / 2, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel("Album artwork unavailable")
        }
    }
}

struct CompactPlayerPosition {
    private static let xKey = "compactNowPlayingOriginX"
    private static let yKey = "compactNowPlayingOriginY"

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func initialOrigin(size: NSSize, displays: [OverlayDisplay]) -> NSPoint {
        if defaults.object(forKey: Self.xKey) != nil,
           defaults.object(forKey: Self.yKey) != nil {
            let saved = NSPoint(
                x: defaults.double(forKey: Self.xKey),
                y: defaults.double(forKey: Self.yKey)
            )
            if displays.contains(where: { $0.visibleFrame.contains(NSRect(origin: saved, size: size)) }) {
                return saved
            }
        }
        return Self.sideOrigin(size: size, visibleFrame: displays.first?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900))
    }

    func save(origin: NSPoint) {
        defaults.set(origin.x, forKey: Self.xKey)
        defaults.set(origin.y, forKey: Self.yKey)
    }

    static func sideOrigin(size: NSSize, visibleFrame: NSRect) -> NSPoint {
        NSPoint(
            x: max(visibleFrame.minX, visibleFrame.maxX - size.width - 12),
            y: max(visibleFrame.minY, visibleFrame.maxY - size.height - 12)
        )
    }
}

@MainActor
final class NowPlayingWindowController: NSWindowController, NSWindowDelegate {
    private static let compactKey = "nowPlayingCompactMode"
    private let onClose: () -> Void
    private let model: PlayerModel
    private let position = CompactPlayerPosition()
    private var isCompact: Bool
    private var hasPlacedWindow = false
    private var changingFrame = false
    private var languageCancellable: AnyCancellable?

    init(model: PlayerModel, onClose: @escaping () -> Void = {}) {
        self.onClose = onClose
        self.model = model
        isCompact = UserDefaults.standard.bool(forKey: Self.compactKey)
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: isCompact ? 310 : 500, height: 330),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        super.init(window: panel)

        panel.delegate = self
        panel.title = AppLocalization.string(
            "Now Playing",
            language: model.appLanguage
        )
        panel.isFloatingPanel = true
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.animationBehavior = .documentWindow
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.contentView = makeContentView()
        languageCancellable = model.$appLanguage
            .removeDuplicates()
            .sink { [weak panel] language in
                panel?.title = AppLocalization.string(
                    "Now Playing",
                    language: language
                )
            }
        let fittingSize = panel.contentView?.fittingSize ?? NSSize(width: 500, height: 330)
        panel.setContentSize(NSSize(
            width: isCompact ? 310 : 500,
            height: max(isCompact ? 150 : 280, fittingSize.height)
        ))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        if !hasPlacedWindow {
            if isCompact { positionOnSide() }
            else { centerOnPrimaryDisplay() }
            hasPlacedWindow = true
        }
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    func showCompact() {
        if !isCompact { setCompact(true) }
        show()
    }

    func windowWillClose(_ notification: Notification) {
        window?.contentView = nil
        onClose()
    }

    func windowDidMove(_ notification: Notification) {
        guard isCompact, hasPlacedWindow, !changingFrame, let window else { return }
        position.save(origin: window.frame.origin)
    }

    private func makeContentView() -> NSView {
        NSHostingView(rootView: NowPlayingPanelView(
            model: model,
            isCompact: isCompact,
            toggleCompact: { [weak self] in self?.setCompact(!(self?.isCompact ?? false)) },
            close: { [weak self] in self?.close() }
        ))
    }

    private func setCompact(_ compact: Bool) {
        guard let window, compact != isCompact else { return }
        isCompact = compact
        UserDefaults.standard.set(compact, forKey: Self.compactKey)
        changingFrame = true
        window.contentView = makeContentView()
        let fitting = window.contentView?.fittingSize ?? NSSize(width: compact ? 310 : 500, height: 330)
        window.setContentSize(NSSize(
            width: compact ? 310 : 500,
            height: max(compact ? 150 : 280, fitting.height)
        ))
        if compact { positionOnSide() }
        else { centerOnCurrentDisplay() }
        changingFrame = false
        hasPlacedWindow = true
    }

    private func positionOnSide() {
        guard let window else { return }
        changingFrame = true
        let displays = NSScreen.screens.map {
            OverlayDisplay(frame: $0.frame, visibleFrame: $0.visibleFrame)
        }
        window.setFrameOrigin(position.initialOrigin(size: window.frame.size, displays: displays))
        changingFrame = false
    }

    private func centerOnCurrentDisplay() {
        guard let window else { return }
        let visible = window.screen?.visibleFrame ?? NSScreen.screens.first?.visibleFrame
        guard let visible else { return }
        window.setFrameOrigin(NSPoint(
            x: visible.midX - window.frame.width / 2,
            y: visible.midY - window.frame.height / 2
        ))
    }

    private func centerOnPrimaryDisplay() {
        guard let window, let screen = NSScreen.screens.first else { return }
        let visibleFrame = screen.visibleFrame
        window.setFrameOrigin(NSPoint(
            x: visibleFrame.midX - window.frame.width / 2,
            y: visibleFrame.midY - window.frame.height / 2
        ))
    }
}
