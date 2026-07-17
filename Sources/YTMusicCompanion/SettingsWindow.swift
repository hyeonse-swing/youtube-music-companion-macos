import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum SettingsTab: String, CaseIterable, Identifiable {
    case lyrics = "Lyrics"
    case metadata = "Metadata"
    case discord = "Discord"
    case diagnostics = "Diagnostics"

    var id: Self { self }
}

private struct CompanionSettingsView: View {
    @ObservedObject var model: PlayerModel
    @State private var selectedTab = SettingsTab.lyrics

    var body: some View {
        VStack(spacing: 12) {
            Picker("Settings section", selection: $selectedTab) {
                ForEach(SettingsTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 420)

            selectedContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(20)
        .frame(minWidth: 640, idealWidth: 680, minHeight: 600, idealHeight: 650)
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch selectedTab {
        case .lyrics:
            LyricsSettingsView(model: model)
        case .metadata:
            MetadataSettingsView(model: model)
        case .discord:
            DiscordSettingsView(model: model)
        case .diagnostics:
            DiagnosticsSettingsView(model: model)
        }
    }
}

private struct SettingsEmptyState: View {
    let title: String
    let systemImage: String
    let description: String

    var body: some View {
        ContentUnavailableView(
            title,
            systemImage: systemImage,
            description: Text(description)
        )
        .frame(maxWidth: .infinity)
        .frame(height: 180)
    }
}

private struct LyricsSettingsView: View {
    @ObservedObject var model: PlayerModel
    @State private var confirmsResetAllTiming = false
    @State private var confirmsRemoveCustomLyrics = false
    @State private var fileAlert: LyricsFileAlert?

    var body: some View {
        Form {
            Section("Appearance") {
                Picker(
                    "Overlay preset",
                    selection: Binding(
                        get: { model.overlayPreset },
                        set: { model.applyOverlayPreset($0) }
                    )
                ) {
                    ForEach(OverlayPreset.allCases) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }

                Text(model.overlayPreset.helpText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

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
                    Button("Reset Size") { model.resetLyricsFontSize() }
                }

                Toggle(
                    "Show karaoke line progress",
                    isOn: $model.karaokeModeEnabled
                )
                Text(
                    "Highlights the current line from left to right using line timestamps. "
                        + "It estimates the pacing because standard LRC files do not "
                        + "contain word-level timing."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                HStack {
                    Spacer()
                    Button("Reset Appearance") {
                        model.resetOverlayAppearance()
                    }
                    .disabled(
                        model.overlayPreset == .balanced
                            && model.lyricsFontSize
                                == CompanionPreferences.defaultLyricsFontSize
                            && !model.karaokeModeEnabled
                    )
                }
            }

            Section("Lyric Layers") {
                LabeledContent("Original lyrics") {
                    Label("Always shown", systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                }

                Toggle("Show romanization", isOn: $model.showsRomanizedLyrics)
                Text(
                    "Adds a pronunciation line only when it differs from the original. "
                        + "A timing-matched lyric version is preferred when available."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                if #available(macOS 15.0, *) {
                    Toggle("Show translation", isOn: $model.showsTranslatedLyrics)

                    Picker(
                        "Translate to",
                        selection: $model.translationTargetLanguage
                    ) {
                        ForEach(LyricTranslationLanguage.allCases) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                    .disabled(!model.showsTranslatedLyrics)

                    Picker(
                        "Translation style",
                        selection: $model.translationTone
                    ) {
                        ForEach(LyricTranslationTone.allCases) { tone in
                            Text(tone.displayName).tag(tone)
                        }
                    }
                    .disabled(!model.showsTranslatedLyrics)

                    Text(
                        "Natural lyrics keeps Korean sentence endings in one "
                            + "conversational tone. Other target languages keep "
                            + "the system translator’s wording."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .disabled(!model.showsTranslatedLyrics)

                    if model.showsTranslatedLyrics {
                        HStack(spacing: 8) {
                            if model.lyricTranslationStatus == .translating {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(
                                    systemName: model.lyricTranslationStatus.systemImage
                                )
                                .accessibilityHidden(true)
                            }
                            Text(model.lyricTranslationStatus.displayName)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .font(.caption)
                        .accessibilityElement(children: .combine)
                    }
                } else {
                    Toggle(
                        "Show translation",
                        isOn: $model.showsTranslatedLyrics
                    )
                    .disabled(true)
                    Text("On-device lyric translation requires macOS 15 or later.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Spacer()
                    Button("Use Original Only") {
                        model.resetLyricLayers()
                    }
                    .disabled(
                        !model.showsRomanizedLyrics
                            && !model.showsTranslatedLyrics
                            && model.translationTargetLanguage == .system
                            && model.translationTone == .naturalLyrics
                    )
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

            Section("Local Lyrics") {
                LabeledContent("Current source") {
                    Label(
                        model.customLyricsSourceName ?? "Online or saved lyrics",
                        systemImage: model.hasCustomLyrics
                            ? "doc.badge.checkmark"
                            : "network"
                    )
                    .lineLimit(1)
                    .help(model.customLyricsSourceName ?? "Lyrics selected from LRCLIB")
                }

                HStack {
                    Text(
                        model.hasNowPlaying
                            ? "Imported LRC files are copied to this Mac and pinned to this song."
                            : "Start a song to import or export its synced lyrics."
                    )
                    .foregroundStyle(.secondary)
                    Spacer()
                    Button(model.hasCustomLyrics ? "Replace LRC…" : "Import LRC…") {
                        importLyrics()
                    }
                    .disabled(!model.hasNowPlaying)
                    Button("Export Current…") {
                        exportLyrics()
                    }
                    .disabled(!model.canExportLyrics)
                    if model.hasCustomLyrics {
                        Button("Use Online…", role: .destructive) {
                            confirmsRemoveCustomLyrics = true
                        }
                    }
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
        .alert("Use online lyrics instead?", isPresented: $confirmsRemoveCustomLyrics) {
            Button("Cancel", role: .cancel) {}
            Button("Remove Imported Lyrics", role: .destructive) {
                do {
                    try model.removeCustomLyrics()
                } catch {
                    fileAlert = LyricsFileAlert(
                        title: "Couldn’t Remove Lyrics",
                        message: error.localizedDescription
                    )
                }
            }
        } message: {
            Text("The imported file for this song will be removed from the app.")
        }
        .alert(item: $fileAlert) { item in
            Alert(
                title: Text(item.title),
                message: Text(item.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    @ViewBuilder
    private var lyricVersionContent: some View {
        if !model.hasNowPlaying {
            SettingsEmptyState(
                title: "Nothing Playing",
                systemImage: "captions.bubble",
                description: "Start a song in YouTube Music to choose its synced lyrics."
            )
        } else if model.lyricCandidates.isEmpty {
            VStack(spacing: 12) {
                if model.isFetchingLyricCandidates {
                    ProgressView("Finding synced lyrics…")
                        .controlSize(.small)
                } else if model.hasCustomLyrics {
                    ContentUnavailableView(
                        "Using Imported Lyrics",
                        systemImage: "doc.badge.checkmark",
                        description: Text(
                            model.lyricCandidateStatusMessage
                                ?? "The imported LRC file is pinned to this song."
                        )
                    )
                } else if !model.lines.isEmpty {
                    ContentUnavailableView(
                        "Using Saved Lyrics",
                        systemImage: "checkmark.circle",
                        description: Text(
                            model.lyricCandidateStatusMessage
                                ?? "Saved lyrics are active for this song."
                        )
                    )
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
                Button(model.lines.isEmpty ? "Try Again" : "Load Lyric Choices") {
                    model.reloadLyricCandidates()
                }
                    .disabled(model.isFetchingLyricCandidates)
            }
            .frame(maxWidth: .infinity, minHeight: 180)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(
                        model.hasCustomLyrics
                            ? "Imported lyrics are active. Choose an online version to replace them."
                            : "Choose the LRCLIB result used for this song. Your choice is remembered."
                    )
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

    private func importLyrics() {
        let panel = NSOpenPanel()
        panel.title = model.hasCustomLyrics ? "Replace Imported Lyrics" : "Import Synced Lyrics"
        panel.message = "Choose a UTF-8 LRC file with timestamped lyric lines."
        panel.prompt = model.hasCustomLyrics ? "Replace" : "Import"
        panel.allowedContentTypes = [UTType(filenameExtension: "lrc") ?? .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        let completion: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try model.importCustomLyrics(from: url)
            } catch {
                fileAlert = LyricsFileAlert(
                    title: "Couldn’t Import Lyrics",
                    message: error.localizedDescription
                )
            }
        }
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(panel.runModal())
        }
    }

    private func exportLyrics() {
        let panel = NSSavePanel()
        panel.title = "Export Synced Lyrics"
        panel.message = "Save the currently displayed lyrics as a UTF-8 LRC file."
        panel.prompt = "Export"
        panel.allowedContentTypes = [UTType(filenameExtension: "lrc") ?? .plainText]
        panel.nameFieldStringValue = model.suggestedLyricsFilename
        panel.canCreateDirectories = true

        let completion: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try model.exportCurrentLyrics(to: url)
            } catch {
                fileAlert = LyricsFileAlert(
                    title: "Couldn’t Export Lyrics",
                    message: error.localizedDescription
                )
            }
        }
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(panel.runModal())
        }
    }
}

private struct LyricsFileAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
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
                    SettingsEmptyState(
                        title: "Nothing Playing",
                        systemImage: "music.note",
                        description: "Start a song to compare the available metadata."
                    )
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
    private enum EditorMode: String, CaseIterable, Identifiable {
        case live = "Live"
        case manual = "Manual"

        var id: Self { self }
    }

    @ObservedObject var model: PlayerModel
    @State private var draft: DiscordPresenceConfiguration
    @State private var manualDraft: ManualDiscordPresence
    @State private var editorMode = EditorMode.live
    @State private var manualError: String?
    @State private var confirmsClearPrivacy = false

    init(model: PlayerModel) {
        self.model = model
        _draft = State(initialValue: model.discordPresenceConfiguration)
        _manualDraft = State(initialValue: Self.manualDraft(from: model.discordPreviewTrack))
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
                } else {
                    Label(
                        model.discordConnectionStatus.displayName,
                        systemImage: model.discordConnectionStatus.systemImage
                    )
                    .foregroundStyle(.secondary)
                }
                if let session = model.manualDiscordPresenceSession {
                    LabeledContent("Active mode") {
                        Label("Manual until \(session.expiresAt.formatted(date: .omitted, time: .shortened))",
                              systemImage: "slider.horizontal.3")
                    }
                } else {
                    LabeledContent("Active mode") {
                        Label("Live playback", systemImage: "waveform")
                    }
                }
            }

            Picker("Presence editor", selection: $editorMode) {
                ForEach(EditorMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if editorMode == .live {
                liveEditor
            } else {
                manualEditor
            }
        }
        .formStyle(.grouped)
        .onChange(of: model.discordPresenceConfiguration) { oldValue, newValue in
            if draft == oldValue { draft = newValue }
        }
        .alert("Clear all private songs?", isPresented: $confirmsClearPrivacy) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                model.clearPrivateDiscordTracks()
            }
        } message: {
            Text("Songs in the privacy list will be allowed on Discord again.")
        }
    }

    @ViewBuilder
    private var liveEditor: some View {
        Section("Live Preset") {
            Picker("Preset", selection: $draft.preset) {
                ForEach(DiscordPresencePreset.allCases) { preset in
                    Text(preset.displayName).tag(preset)
                }
            }
            .onChange(of: draft.preset) { oldValue, newValue in
                guard oldValue != newValue, newValue != .custom else { return }
                draft = newValue.applying(to: draft)
            }
            Text(draft.preset.helpText)
                .font(.caption)
                .foregroundStyle(.secondary)

            MetadataSourcePicker(selection: $model.discordMetadataSource)
            Text(model.discordMetadataSource.helpText)
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("When playback pauses", selection: $draft.pausePolicy) {
                ForEach(DiscordPausePolicy.allCases) { policy in
                    Text(policy.displayName).tag(policy)
                }
            }
        }

        Section("Text") {
            TextField("Top line", text: customText(\.detailsTemplate))
                .accessibilityHint("Supports title, artist, and album tokens")
            TextField("Second line", text: customText(\.stateTemplate))
                .accessibilityHint("Supports title, artist, and album tokens")
            TextField("Cover description", text: customText(\.imageTextTemplate))
                .accessibilityHint("Supports title, artist, and album tokens")
            Toggle("Show playback time", isOn: $draft.showsPlaybackTime)
            Toggle("Include song links", isOn: $draft.showsSongLink)

            Text(
                "Available tokens: "
                    + DiscordPresenceConfiguration.supportedTokens.joined(separator: "  ")
            )
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
        }

        Section("Links and Buttons") {
            Toggle("Link the top line to the song", isOn: $draft.linksDetailsToSong)
                .disabled(!draft.showsSongLink)
            Toggle("Link the second line to the song", isOn: $draft.linksStateToSong)
                .disabled(!draft.showsSongLink)
            Toggle("Link the cover to the song", isOn: $draft.linksCoverToSong)
                .disabled(!draft.showsSongLink)
            TextField("Primary button label", text: $draft.primaryButtonLabel)
                .disabled(!draft.showsSongLink)
            TextField("Secondary button label", text: $draft.secondaryButtonLabel)
            TextField("Secondary button HTTPS URL", text: $draft.secondaryButtonURL)

            if let liveValidationMessage {
                Label(liveValidationMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(
                    "Discord supports at most two buttons. Buttons appear to other "
                        + "people, so your own profile card may not show them."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }

        Section("Privacy") {
            Toggle(
                "Hide this song from Discord",
                isOn: Binding(
                    get: { model.isCurrentDiscordTrackPrivate },
                    set: { model.setCurrentDiscordTrackPrivate($0) }
                )
            )
            .disabled(model.discordPreviewTrack == nil)

            HStack {
                Text(
                    model.discordPreviewTrack == nil
                        ? "Start a song to add it to the private list."
                        : "Only a one-way fingerprint is saved; the title and URL are not stored."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                Spacer()
                Button("Clear \(model.privateDiscordTrackCount) Private Songs…") {
                    confirmsClearPrivacy = true
                }
                .disabled(model.privateDiscordTrackCount == 0)
            }
        }

        Section("Preview") {
            DiscordPresencePreview(
                activity: livePreviewActivity,
                artwork: model.nowPlayingArtwork,
                remoteCoverURL: nil,
                modeLabel: "Live",
                usesExample: model.discordPreviewTrack == nil
            )
        }

        Section {
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
                .disabled(!hasUnsavedChanges || liveValidationMessage != nil)
            }
        }
    }

    @ViewBuilder
    private var manualEditor: some View {
        Section("Manual Presence") {
            TextField("Song title", text: $manualDraft.title)
            TextField("Artist", text: $manualDraft.artist)
            TextField("Album", text: $manualDraft.album)
            TextField("Cover image HTTPS URL", text: $manualDraft.coverURL)
            TextField("Song HTTPS URL", text: $manualDraft.songURL)

            Stepper(
                "Song duration: \(manualDraft.durationMinutes) min",
                value: $manualDraft.durationMinutes,
                in: 1 ... 1_440
            )
            Toggle("Show playback time", isOn: $manualDraft.showsPlaybackTime)
            Picker("Return to live after", selection: $manualDraft.lifetime) {
                ForEach(ManualPresenceLifetime.allCases) { lifetime in
                    Text(lifetime.displayName).tag(lifetime)
                }
            }
        }

        Section("Optional Second Button") {
            TextField("Button label", text: $manualDraft.secondaryButtonLabel)
            TextField("Button HTTPS URL", text: $manualDraft.secondaryButtonURL)

            Text(
                "Manual presence is clearly marked inside the app, expires automatically, "
                    + "and is not restored after the app quits."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Section("Preview") {
            DiscordPresencePreview(
                activity: manualPreviewActivity,
                artwork: nil,
                remoteCoverURL: DiscordURLValidator.httpsURL(manualDraft.coverURL),
                modeLabel: "Manual",
                usesExample: false
            )
        }

        Section {
            if let message = manualDraft.validationMessage ?? manualError {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Use Current Song") {
                    manualDraft = Self.manualDraft(from: model.discordPreviewTrack)
                    manualError = nil
                }
                .disabled(model.discordPreviewTrack == nil)

                Spacer()

                Button("Return to Live") {
                    model.returnToLiveDiscordPresence()
                    manualError = nil
                }
                .disabled(model.manualDiscordPresenceSession == nil)

                Button("Publish Manual") {
                    manualError = model.publishManualDiscordPresence(manualDraft)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(
                    manualDraft.validationMessage != nil
                        || !model.discordEnabled
                        || !model.isDiscordConfigured
                )
            }
        }
    }

    private var hasUnsavedChanges: Bool {
        draft != model.discordPresenceConfiguration
    }

    private var hasCustomization: Bool {
        draft != .standard || model.discordPresenceConfiguration != .standard
    }

    private var liveValidationMessage: String? {
        let primary = draft.primaryButtonLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if draft.showsSongLink && primary.isEmpty {
            return "Enter a primary button label or turn off song links."
        }
        if primary.count > 32 {
            return "Button labels can contain up to 32 characters."
        }

        let secondaryLabel = draft.secondaryButtonLabel
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let secondaryURL = draft.secondaryButtonURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if secondaryLabel.isEmpty != secondaryURL.isEmpty {
            return "Enter both a secondary button label and URL."
        }
        if secondaryLabel.count > 32 {
            return "Button labels can contain up to 32 characters."
        }
        if !DiscordURLValidator.optionalURLIsValid(secondaryURL) {
            return "The secondary button URL must be a valid HTTPS URL."
        }
        return nil
    }

    private var livePreviewActivity: PresenceActivity {
        let track = model.discordPreviewTrack ?? Self.exampleTrack
        let content = draft.content(for: track)
        let links = draft.links(for: track)
        let start = draft.showsPlaybackTime
            ? Date().addingTimeInterval(-track.elapsed)
            : nil
        return PresenceActivity(
            name: track.artist.isEmpty ? track.title : "\(track.title) - \(track.artist)",
            details: content.details,
            state: content.state,
            start: start,
            end: start.flatMap {
                track.duration > 0 ? $0.addingTimeInterval(track.duration) : nil
            },
            largeImage: YouTubeMusicSource.discordAssetKey,
            largeImageText: content.imageText,
            smallImage: YouTubeMusicSource.discordAssetKey,
            smallImageText: YouTubeMusicSource.displayName,
            detailsURL: links.detailsURL,
            stateURL: links.stateURL,
            largeImageURL: links.coverURL,
            smallImageURL: nil,
            buttons: links.buttons
        )
    }

    private var manualPreviewActivity: PresenceActivity {
        manualDraft.activity(
            startedAt: model.manualDiscordPresenceSession?.startedAt ?? Date()
        ) ?? PresenceActivity(
            name: "Manual Presence",
            details: manualDraft.title.isEmpty ? "Song Title" : manualDraft.title,
            state: manualDraft.artist.isEmpty ? "Artist" : manualDraft.artist,
            start: nil,
            end: nil,
            largeImage: YouTubeMusicSource.discordAssetKey,
            largeImageText: manualDraft.album,
            smallImage: YouTubeMusicSource.discordAssetKey,
            smallImageText: "Manual presence · YT Music Companion"
        )
    }

    private func customText(
        _ keyPath: WritableKeyPath<DiscordPresenceConfiguration, String>
    ) -> Binding<String> {
        Binding(
            get: { draft[keyPath: keyPath] },
            set: {
                draft[keyPath: keyPath] = $0
                draft.preset = .custom
            }
        )
    }

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
        sourcePID: 0,
        trackURL: URL(string: "https://music.youtube.com/")
    )

    private static func manualDraft(from track: NowPlaying?) -> ManualDiscordPresence {
        guard let track else { return .example }
        return ManualDiscordPresence(
            title: track.title,
            artist: track.artist,
            album: track.album,
            coverURL: "",
            songURL: track.trackURL?.absoluteString ?? "",
            durationMinutes: max(1, Int(ceil(track.duration / 60))),
            showsPlaybackTime: true,
            lifetime: .thirtyMinutes,
            secondaryButtonLabel: "",
            secondaryButtonURL: ""
        )
    }
}

private struct DiagnosticsSettingsView: View {
    @ObservedObject var model: PlayerModel
    @State private var confirmsCacheClear = false

    var body: some View {
        let diagnostics = model.runtimeDiagnostics
        Form {
            Section("Playback Engine") {
                LabeledContent("Polling") {
                    Text(
                        "\(diagnostics.pollMode.displayName) · "
                            + "\(format(diagnostics.nextPollInterval)) seconds"
                    )
                    .monospacedDigit()
                }
                LabeledContent("Last poll") {
                    if let date = diagnostics.lastPollDate {
                        Text(date, style: .time)
                    } else {
                        Text("Not yet")
                    }
                }
                LabeledContent("Last poll duration") {
                    Text(
                        diagnostics.lastPollDuration.map {
                            "\(Int(($0 * 1_000).rounded())) ms"
                        } ?? "—"
                    )
                    .monospacedDigit()
                }
                LabeledContent("Active work") {
                    Text(
                        diagnostics.activeOperations.isEmpty
                            ? "None"
                            : diagnostics.activeOperations.joined(separator: ", ")
                    )
                }
            }

            Section("Child Processes") {
                LabeledContent("Currently running") {
                    Text("\(diagnostics.subprocesses.activeCount)")
                }
                LabeledContent("Launched this session") {
                    Text("\(diagnostics.subprocesses.totalLaunches)")
                }
                LabeledContent("Cancelled after track change") {
                    Text("\(diagnostics.subprocesses.cancelledCount)")
                }
                LabeledContent("Timed out") {
                    Text("\(diagnostics.subprocesses.timedOutCount)")
                }
            }

            Section("Session Cache") {
                LabeledContent("Metadata") {
                    Text("\(diagnostics.metadataCacheEntries) / \(SessionCacheLimits.metadata)")
                }
                LabeledContent("Artwork") {
                    Text("\(diagnostics.artworkCacheEntries) / \(SessionCacheLimits.artwork)")
                }
                LabeledContent("Lyrics") {
                    Text("\(diagnostics.lyricsCacheEntries) / \(SessionCacheLimits.lyrics)")
                }
                LabeledContent("Lyric choices") {
                    Text(
                        "\(diagnostics.lyricCandidateCacheEntries) / "
                            + "\(SessionCacheLimits.lyricCandidates)"
                    )
                }
                LabeledContent("Saved lyrics on disk") {
                    Text(
                        "\(model.lyricsDiskCacheStatistics.fileCount) files · "
                            + model.lyricsDiskCacheStatistics.formattedSize
                    )
                }
                LabeledContent("Saved translations on disk") {
                    Text(
                        "\(model.translationDiskCacheStatistics.fileCount) files · "
                            + model.translationDiskCacheStatistics.formattedSize
                    )
                }
                HStack {
                    Text("Saved lyrics and translations are reproducible and safe to clear.")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear Caches…") {
                        confirmsCacheClear = true
                    }
                    .disabled(
                        model.lyricsDiskCacheStatistics.fileCount == 0
                            && model.translationDiskCacheStatistics.fileCount == 0
                    )
                }
            }

            Section("Discord") {
                Label(
                    diagnostics.discordStatus.displayName,
                    systemImage: diagnostics.discordStatus.systemImage
                )
            }

            Section {
                Text(
                    "Diagnostics stay on this Mac. Track titles are not written "
                        + "to the diagnostic counters shown here."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .alert("Clear saved lyrics and translations?", isPresented: $confirmsCacheClear) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                model.clearSavedLyricsCache()
            }
        } message: {
            Text(
                "Lyrics will be downloaded again and translations will be regenerated "
                    + "when those songs are played."
            )
        }
    }

    private func format(_ interval: TimeInterval) -> String {
        interval.rounded() == interval
            ? String(Int(interval))
            : String(format: "%.1f", interval)
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
    let activity: PresenceActivity
    let artwork: NowPlayingArtwork?
    let remoteCoverURL: URL?
    let modeLabel: String
    let usesExample: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(modeLabel, systemImage: modeLabel == "Manual" ? "slider.horizontal.3" : "waveform")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                if usesExample {
                    Text("Example")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                if activity.start != nil {
                    Label("Time", systemImage: "clock")
                }
                if activity.detailsURL != nil || activity.stateURL != nil
                    || activity.largeImageURL != nil
                {
                    Label("Linked fields", systemImage: "link")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack(spacing: 14) {
                cover
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(activity.details)
                        .font(.headline)
                        .lineLimit(1)
                    Text(activity.state)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let imageText = activity.largeImageText, !imageText.isEmpty {
                        Text(imageText)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 12)
            }

            if !activity.buttons.isEmpty {
                HStack(spacing: 8) {
                    ForEach(Array(activity.buttons.enumerated()), id: \.offset) { _, button in
                        Label(button.label, systemImage: "arrow.up.right")
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    @ViewBuilder
    private var cover: some View {
        if let artwork, let image = NSImage(data: artwork.data) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
        } else if let remoteCoverURL {
            AsyncImage(url: remoteCoverURL) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    coverPlaceholder
                }
            }
        } else {
            coverPlaceholder
        }
    }

    private var coverPlaceholder: some View {
        Image(systemName: "music.note")
            .font(.system(size: 28, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.quaternary)
    }

    private var accessibilityDescription: String {
        let time = activity.start == nil ? "playback time hidden" : "playback time shown"
        return "\(modeLabel) Discord preview, \(activity.details), \(activity.state), \(time), \(activity.buttons.count) buttons"
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
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let onClose: () -> Void

    init(model: PlayerModel, onClose: @escaping () -> Void = {}) {
        self.onClose = onClose
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 650),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init(window: panel)

        panel.delegate = self
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

    func windowWillClose(_ notification: Notification) {
        window?.contentView = nil
        onClose()
    }
}
