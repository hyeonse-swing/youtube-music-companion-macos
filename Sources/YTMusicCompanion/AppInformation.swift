import AppKit
import SwiftUI

struct AppInformation: Equatable {
    let version: String
    let build: String
    let bundleIdentifier: String
    let isDiscordConfigured: Bool

    var versionText: String { "Version \(version) (\(build))" }
    var discordStatus: String { isDiscordConfigured ? "Configured" : "Not Configured" }

    static func current(
        bundle: Bundle = .main,
        discordClientID: String? = AppConfiguration.discordClientID
    ) -> AppInformation {
        AppInformation(
            version: value(for: "CFBundleShortVersionString", in: bundle) ?? "Development",
            build: value(for: "CFBundleVersion", in: bundle) ?? "—",
            bundleIdentifier: bundle.bundleIdentifier ?? AppConfiguration.bundleIdentifier,
            isDiscordConfigured: discordClientID != nil
        )
    }

    private static func value(for key: String, in bundle: Bundle) -> String? {
        guard let value = bundle.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct AppInformationView: View {
    let information: AppInformation
    let appIcon: NSImage
    let language: AppLanguage
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 16) {
                Image(nsImage: appIcon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(AppConfiguration.productName)
                        .font(.title2.weight(.semibold))
                    Text(
                        AppLocalization.format(
                            "Version %@ (%@)",
                            language: language,
                            arguments: information.version,
                            information.build
                        )
                    )
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 12) {
                GridRow {
                    Text(AppLocalization.string("Discord", language: language))
                        .foregroundStyle(.secondary)
                    Label(
                        AppLocalization.string(
                            information.discordStatus,
                            language: language
                        ),
                        systemImage: information.isDiscordConfigured
                            ? "checkmark.circle.fill"
                            : "exclamationmark.circle"
                    )
                }
                GridRow {
                    Text(AppLocalization.string("Bundle ID", language: language))
                        .foregroundStyle(.secondary)
                    Text(information.bundleIdentifier)
                        .textSelection(.enabled)
                }
            }

            Divider()

            HStack {
                if let repositoryURL = URL(string: AppConfiguration.repositoryURL) {
                    Link(
                        AppLocalization.string("View on GitHub", language: language),
                        destination: repositoryURL
                    )
                }
                Spacer()
                Button(
                    AppLocalization.string("Done", language: language),
                    action: close
                )
                    .keyboardShortcut(.defaultAction)
            }

            Text("Copyright © 2026 Hyeonse Im")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(24)
        .frame(width: 440)
        .environment(\.locale, language.locale)
    }
}

@MainActor
final class AppInformationWindowController: NSWindowController {
    private let information: AppInformation

    init(
        information: AppInformation = .current(),
        language: AppLanguage = .system
    ) {
        self.information = information
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 310),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        super.init(window: panel)

        panel.title = AppLocalization.format(
            "About %@",
            language: language,
            arguments: AppConfiguration.productName
        )
        panel.isFloatingPanel = true
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.animationBehavior = .documentWindow
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: AppInformationView(
            information: information,
            appIcon: NSApp.applicationIconImage ?? NSImage(size: NSSize(width: 64, height: 64)),
            language: language,
            close: { [weak panel] in panel?.close() }
        ))
        panel.setContentSize(panel.contentView?.fittingSize ?? NSSize(width: 440, height: 310))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    func show(language: AppLanguage = .system) {
        update(language: language)
        NSApp.activate()
        centerOnPrimaryDisplay()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    private func update(language: AppLanguage) {
        guard let panel = window else { return }
        panel.title = AppLocalization.format(
            "About %@",
            language: language,
            arguments: AppConfiguration.productName
        )
        panel.contentView = NSHostingView(rootView: AppInformationView(
            information: information,
            appIcon: NSApp.applicationIconImage
                ?? NSImage(size: NSSize(width: 64, height: 64)),
            language: language,
            close: { [weak panel] in panel?.close() }
        ))
        panel.setContentSize(
            panel.contentView?.fittingSize ?? NSSize(width: 440, height: 310)
        )
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
