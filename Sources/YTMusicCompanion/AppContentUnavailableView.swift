import SwiftUI

/// Keeps the native macOS 14 empty-state presentation while providing the same
/// hierarchy on macOS 13, where `ContentUnavailableView` does not exist yet.
struct AppContentUnavailableView: View {
    private let title: Text
    private let systemImage: String
    private let description: Text

    init(
        _ title: LocalizedStringKey,
        systemImage: String,
        description: Text
    ) {
        self.title = Text(title)
        self.systemImage = systemImage
        self.description = description
    }

    init(
        verbatimTitle title: String,
        systemImage: String,
        description: Text
    ) {
        self.title = Text(verbatim: title)
        self.systemImage = systemImage
        self.description = description
    }

    @ViewBuilder
    var body: some View {
        if #available(macOS 14.0, *) {
            ContentUnavailableView {
                Label {
                    title
                } icon: {
                    Image(systemName: systemImage)
                }
            } description: {
                description
            }
        } else {
            VStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 34, weight: .regular))
                    .foregroundStyle(.secondary)
                title
                    .font(.title2.weight(.semibold))
                description
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .padding(20)
            .accessibilityElement(children: .combine)
        }
    }
}
