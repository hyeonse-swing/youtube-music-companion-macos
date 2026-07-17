import SwiftUI
import Translation

/// Hosts Apple's on-device Translation task for the active lyric snapshot.
/// Replacing the request identity cancels the old SwiftUI task when a song,
/// lyric version, or target language changes.
struct LyricTranslationCoordinator: View {
    @ObservedObject var model: PlayerModel

    @ViewBuilder
    var body: some View {
        if #available(macOS 15.0, *), let request = model.lyricTranslationRequest {
            LyricTranslationTaskHost(model: model, request: request)
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
    @ObservedObject var model: PlayerModel
    let request: LyricTranslationRequest
    @State private var configuration: TranslationSession.Configuration?

    init(model: PlayerModel, request: LyricTranslationRequest) {
        self.model = model
        self.request = request
        _configuration = State(
            initialValue: TranslationSession.Configuration(
                source: nil,
                target: Locale.Language(identifier: request.targetLanguage)
            )
        )
    }

    var body: some View {
        Color.clear
            .translationTask(configuration) { session in
                await model.translateLyrics(using: session, request: request)
            }
    }
}
