import AppKit
import SwiftUI

private struct CompanionSettingsView: View {
    @ObservedObject var model: PlayerModel

    var body: some View {
        TabView {
            LyricsSettingsView(model: model)
                .tabItem { Label("Lyrics", systemImage: "captions.bubble") }

            MetadataSettingsView(model: model)
                .tabItem { Label("Metadata", systemImage: "list.bullet.rectangle") }

            DiscordSettingsView(model: model)
                .tabItem {
                    Label("Discord", systemImage: "antenna.radiowaves.left.and.right")
                }
        }
        .padding(20)
        .frame(minWidth: 640, idealWidth: 680, minHeight: 600, idealHeight: 650)
    }
}

private struct LyricsSettingsView: View {
    @ObservedObject var model: PlayerModel
    @State private var confirmsResetAllTiming = false

    var body: some View {
        Form {
            Section("Appearance") {
                HStack(spacing: 12) {
                    Image(systemName: "textformat.size.smaller")
                        .accessibilityHidden(true)
                    Slider(
                        value: $model.lyricsFontSize,
                        in: CompanionPreferences.minimumLyricsFontSize...CompanionPreferences.maximumLyricsFontSize,
                        step: 1
                    )
                    .accessibilityLabel("Lyrics size")
                    Image(systemName: "textformat.size.larger")
                        .accessibilityHidden(true)
                    Text("\(Int(model.lyricsFontSize)) pt")
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                    Button("Reset") { model.resetLyricsFontSize() }
                }
            }

            Section("Timing") {
                LabeledContent("Current adjustment") {
                    Text(String(format: "%+.2f seconds", model.syncOffset))
                        .monospacedDigit()
                }

                HStack {
                    Text("Scroll over the visible lyric to fine-tune its timing.")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset Current Song") { model.resetCurrentLyricsTiming() }
                        .disabled(!model.hasNowPlaying)
                    Button("Reset All…") { confirmsResetAllTiming = true }
                }
            }

            Section("Lyric Version") {
                lyricVersionContent
            }
        }
        .formStyle(.grouped)
        .alert("Reset all lyric timing?", isPresented: $confirmsResetAllTiming) {
            Button("Cancel", role: .cancel) {}
            Button("Reset All", role: .destructive) { model.resetAllLyricsTiming() }
        } message: {
            Text("This clears the timing adjustment for every song and the learned default.")
        }
    }

    @ViewBuilder
    private var lyricVersionContent: some View {
        if !model.hasNowPlaying {
            ContentUnavailableView(
                "Nothing Playing",
                systemImage: "captions.bubble",
                description: Text("Start a song in YouTube Music to choose its synced lyrics.")
            )
            .frame(height: 180)
        } else if model.lyricCandidates.isEmpty {
            VStack(spacing: 12) {
                if model.isFetchingLyricCandidates {
                    ProgressView("Finding synced lyrics…")
                        .controlSize(.small)
                } else {
                    ContentUnavailableView(
                        "No Lyric Choices",
                        systemImage: "text.badge.xmark",
                        description: Text(
                            model.lyricCandidateStatusMessage
                                ?? "No synced lyrics have been loaded for this song."
                        )
                    )
                }
                Button("Try Again") { model.reloadLyricCandidates() }
                    .disabled(model.isFetchingLyricCandidates)
            }
            .frame(maxWidth: .infinity, minHeight: 180)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Choose the LRCLIB result used for this song. Your choice is remembered.")
                        .foregroundStyle(.secondary)
                    Spacer()
                    if model.isFetchingLyricCandidates {
                        ProgressView().controlSize(.small)
                    }
                    Button("Refresh") { model.reloadLyricCandidates() }
                        .disabled(model.isFetchingLyricCandidates)
                }

                List(selection: lyricSelection) {
                    ForEach(Array(model.lyricCandidates.enumerated()), id: \.element.id) { index, candidate in
                        LyricCandidateRow(
                            candidate: candidate,
                            isRecommended: index == 0,
                            isSelected: model.selectedLyricCandidateID == candidate.id
                        )
                        .tag(candidate.id)
                    }
                }
                .frame(minHeight: 180)
                .accessibilityLabel("Available lyric versions")
            }
        }
    }

    private var lyricSelection: Binding<String?> {
        Binding(
            get: { model.selectedLyricCandidateID },
            set: { if let id = $0 { model.selectLyricCandidate(id) } }
        )
    }
}

private struct LyricCandidateRow: View {
    let candidate: LyricCandidate
    let isRecommended: Bool
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(candidate.title)
                        .font(.headline)
                        .lineLimit(1)
                    if isRecommended {
                        Text("Recommended")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                Text(candidateSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(candidate.script.displayName)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var candidateSubtitle: String {
        let album = candidate.album.isEmpty ? "Unknown album" : candidate.album
        return "\(candidate.artist) · \(album) · "
            + PlaybackTimeFormatter.string(seconds: candidate.duration)
    }
}

private struct MetadataSettingsView: View {
    @ObservedObject var model: PlayerModel

    var body: some View {
        Form {
            Section("App and Now Playing Panel") {
                MetadataSourcePicker(selection: $model.displayMetadataSource)
                Text(model.displayMetadataSource.helpText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Available Data") {
                if model.hasNowPlaying {
                    MetadataPreviewRow(
                        title: "YouTube Music screen",
                        track: model.youtubeMusicNowPlaying,
                        unavailableText: model.hasExactMetadataAccess
                            ? "Reading the player bar…"
                            : "Screen access is not enabled."
                    )
                    MetadataPreviewRow(
                        title: "macOS playback info",
                        track: model.sourceNowPlaying,
                        unavailableText: "Unavailable"
                    )
                } else {
                    ContentUnavailableView(
                        "Nothing Playing",
                        systemImage: "music.note",
                        description: Text("Start a song to compare the available metadata.")
                    )
                    .frame(height: 160)
                }
            }

            if !model.hasExactMetadataAccess {
                Section {
                    HStack {
                        Label(
                            "Screen access lets the app read the exact labels visible in YouTube Music.",
                            systemImage: "accessibility"
                        )
                        Spacer()
                        Button("Enable Access…") { model.requestExactMetadataAccess() }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct DiscordSettingsView: View {
    @ObservedObject var model: PlayerModel
    @State private var draft: DiscordPresenceConfiguration

    init(model: PlayerModel) {
        self.model = model
        _draft = State(initialValue: model.discordPresenceConfiguration)
    }

    var body: some View {
        Form {
            Section("Status") {
                Toggle("Enable Discord Rich Presence", isOn: $model.discordEnabled)
                    .disabled(!model.isDiscordConfigured)
                if !model.isDiscordConfigured {
                    Label(
                        "Discord is not configured in this build.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(.secondary)
                }
            }

            Section("Metadata Source") {
                MetadataSourcePicker(selection: $model.discordMetadataSource)
                Text(model.discordMetadataSource.helpText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Custom Text") {
                TextField("Top line", text: $draft.detailsTemplate)
                    .accessibilityHint("Supports title, artist, and album tokens")
                TextField("Second line", text: $draft.stateTemplate)
                    .accessibilityHint("Supports title, artist, and album tokens")
                TextField("Cover description", text: $draft.imageTextTemplate)
                    .accessibilityHint("Supports title, artist, and album tokens")
                Toggle("Show playback time", isOn: $draft.showsPlaybackTime)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Available tokens: " + DiscordPresenceConfiguration.supportedTokens.joined(separator: "  "))
                        .font(.caption.monospaced())
                    Text("Blank fields automatically use the original title, artist, or album value.")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)

                HStack {
                    Spacer()
                    Button("Revert Changes") {
                        draft = model.discordPresenceConfiguration
                    }
                    .disabled(!hasUnsavedChanges)

                    Button("Reset to Defaults") {
                        draft = .standard
                        model.resetDiscordPresenceConfiguration()
                    }
                    .disabled(!hasCustomization)

                    Button("Apply") {
                        model.applyDiscordPresenceConfiguration(draft)
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!hasUnsavedChanges)
                }
            }

            Section("Preview") {
                DiscordPresencePreview(
                    configuration: draft,
                    track: model.discordPreviewTrack
                )
            }
        }
        .formStyle(.grouped)
        .onChange(of: model.discordPresenceConfiguration) { oldValue, newValue in
            if draft == oldValue { draft = newValue }
        }
    }

    private var hasUnsavedChanges: Bool {
        draft != model.discordPresenceConfiguration
    }

    private var hasCustomization: Bool {
        draft != .standard || model.discordPresenceConfiguration != .standard
    }
}

private struct MetadataSourcePicker: View {
    @Binding var selection: MetadataSourcePreference

    var body: some View {
        Picker("Metadata source", selection: $selection) {
            ForEach(MetadataSourcePreference.allCases) { source in
                Text(source.displayName).tag(source)
            }
        }
        .pickerStyle(.radioGroup)
    }
}

private struct DiscordPresencePreview: View {
    let configuration: DiscordPresenceConfiguration
    let track: NowPlaying?

    private static let exampleTrack = NowPlaying(
        title: "Song Title",
        artist: "Artist",
        album: "Album",
        duration: 180,
        elapsed: 30,
        timestamp: 0,
        isPlaying: true,
        rate: 1,
        sourceBundle: "",
        sourcePID: 0
    )

    var body: some View {
        let previewTrack = track ?? Self.exampleTrack
        let content = configuration.content(for: previewTrack)

        HStack(spacing: 14) {
            Image(systemName: "music.note")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 58, height: 58)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(content.details)
                    .font(.headline)
                    .lineLimit(1)
                Text(content.state)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(content.imageText)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            Label(
                configuration.showsPlaybackTime ? "Time shown" : "Time hidden",
                systemImage: configuration.showsPlaybackTime ? "clock" : "clock.badge.xmark"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription(content: content))
    }

    private func accessibilityDescription(content: DiscordPresenceContent) -> String {
        let kind = track == nil ? "Example Discord preview" : "Current Discord preview"
        let time = configuration.showsPlaybackTime ? "playback time shown" : "playback time hidden"
        return "\(kind), \(content.details), \(content.state), \(content.imageText), \(time)"
    }
}

private struct MetadataPreviewRow: View {
    let title: String
    let track: NowPlaying?
    let unavailableText: String

    var body: some View {
        LabeledContent(title) {
            if let track {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(track.title).fontWeight(.medium)
                    Text([track.artist, track.album].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .textSelection(.enabled)
            } else {
                Text(unavailableText)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

@MainActor
final class SettingsWindowController: NSWindowController {
    init(model: PlayerModel) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 650),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init(window: panel)

        panel.title = "Settings"
        panel.isFloatingPanel = true
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.animationBehavior = .documentWindow
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.minSize = NSSize(width: 640, height: 600)
        panel.contentView = NSHostingView(rootView: CompanionSettingsView(model: model))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    func show() {
        NSApp.activate()
        if window?.isVisible != true { window?.center() }
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }
}
