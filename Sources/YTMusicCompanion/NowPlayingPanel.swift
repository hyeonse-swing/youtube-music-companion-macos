import AppKit
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

    var body: some View {
        Group {
            if let source = model.sourceNowPlaying {
                trackContent(source: source, display: model.displayNowPlaying ?? source)
            } else {
                ContentUnavailableView(
                    "Nothing Playing",
                    systemImage: "music.note",
                    description: Text("Start a song in YouTube Music to see it here.")
                )
                .frame(height: 230)
            }
        }
        .padding(24)
        .frame(width: 500)
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

    var body: some View {
        if
            let data = artwork?.data,
            let image = NSImage(data: data)
        {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityLabel("Album artwork for \(title)")
        } else {
            Image(systemName: "music.note")
                .font(.system(size: 36, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 72, height: 72)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel("Album artwork unavailable")
        }
    }
}

@MainActor
final class NowPlayingWindowController: NSWindowController, NSWindowDelegate {
    private let onClose: () -> Void

    init(model: PlayerModel, onClose: @escaping () -> Void = {}) {
        self.onClose = onClose
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 330),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        super.init(window: panel)

        panel.delegate = self
        panel.title = "Now Playing"
        panel.isFloatingPanel = true
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.animationBehavior = .documentWindow
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: NowPlayingPanelView(model: model))
        let fittingSize = panel.contentView?.fittingSize ?? NSSize(width: 500, height: 330)
        panel.setContentSize(NSSize(width: 500, height: max(280, fittingSize.height)))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    func show() {
        NSApp.activate()
        centerOnPrimaryDisplay()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    func windowWillClose(_ notification: Notification) {
        window?.contentView = nil
        onClose()
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
