import AppKit
import SwiftUI
import Translation

/// A persistent translation host that is independent from the transparent lyric
/// overlay. The small panel is shown only while macOS needs to prepare or download
/// a language pair, so the system sheet never dims the 1,000-point overlay window.
@MainActor
final class TranslationHostWindowController: NSWindowController {
    private var presentedRequestID: UUID?

    init(model: PlayerModel) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 140),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        super.init(window: panel)

        panel.title = "Lyric Translation"
        panel.isFloatingPanel = true
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(
            rootView: LyricTranslationHostView(model: model) { [weak self] requestID, show in
                self?.setPanelVisible(show, for: requestID)
            }
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    private func setPanelVisible(_ visible: Bool, for requestID: UUID) {
        guard let window else { return }
        if visible {
            presentedRequestID = requestID
            if !window.isVisible { window.center() }
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        } else if presentedRequestID == requestID {
            presentedRequestID = nil
            window.orderOut(nil)
        }
    }
}

private struct LyricTranslationHostView: View {
    @ObservedObject var model: PlayerModel
    let setPanelVisible: (UUID, Bool) -> Void

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            Text("Preparing on-device lyric translation…")
                .font(.headline)
            Text("macOS may ask to download the required languages.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            LyricTranslationCoordinator(
                model: model,
                request: model.lyricTranslationRequest,
                setPanelVisible: setPanelVisible
            )
        }
    }
}

/// Hosts Apple's on-device Translation task for the active lyric snapshot.
/// Replacing the request identity cancels the old task when a song, lyric
/// version, or target language changes.
struct LyricTranslationCoordinator: View {
    let model: PlayerModel
    let request: LyricTranslationRequest?
    let setPanelVisible: (UUID, Bool) -> Void

    @ViewBuilder
    var body: some View {
        if #available(macOS 15.0, *), let request {
            LyricTranslationTaskHost(
                model: model,
                request: request,
                setPanelVisible: setPanelVisible
            )
                .id(request.id)
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        } else {
            Color.clear
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

@available(macOS 15.0, *)
private struct LyricTranslationTaskHost: View {
    let model: PlayerModel
    let request: LyricTranslationRequest
    let setPanelVisible: (UUID, Bool) -> Void
    @State private var configuration: TranslationSession.Configuration?

    var body: some View {
        Color.clear
            .task(id: request.id) {
                await prepareTranslation()
            }
            .translationTask(configuration) { session in
                do {
                    try await session.prepareTranslation()
                    await model.translateLyrics(using: session, request: request)
                } catch is CancellationError {
                    // A replacement request owns the next task and panel state.
                } catch {
                    model.failLyricTranslation(
                        request: request,
                        message: error.localizedDescription
                    )
                }
                setPanelVisible(request.id, false)
            }
            .onDisappear {
                setPanelVisible(request.id, false)
            }
    }

    private func prepareTranslation() async {
        let target = Locale.Language(identifier: request.targetLanguage)
        guard let sourceIdentifier = request.sourceLanguage else {
            // Short or mostly-symbolic lyrics can be valid even when
            // NLLanguageRecognizer has no confident result. Keep the preparation
            // UI off the overlay and let Translation perform its own detection.
            setPanelVisible(request.id, true)
            await Task.yield()
            guard !Task.isCancelled else { return }
            configuration = TranslationSession.Configuration(
                source: nil,
                target: target
            )
            return
        }

        let source = Locale.Language(identifier: sourceIdentifier)
        let status = await LanguageAvailability().status(from: source, to: target)
        guard !Task.isCancelled else { return }

        switch status {
        case .installed:
            setPanelVisible(request.id, false)
        case .supported:
            setPanelVisible(request.id, true)
            await Task.yield()
            guard !Task.isCancelled else { return }
        case .unsupported:
            model.failLyricTranslation(
                request: request,
                message: "This language pair is not supported by macOS Translation."
            )
            return
        @unknown default:
            model.failLyricTranslation(
                request: request,
                message: "Could not prepare this language pair."
            )
            return
        }

        configuration = TranslationSession.Configuration(
            source: source,
            target: target
        )
    }
}
