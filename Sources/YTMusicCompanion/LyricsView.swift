import SwiftUI

/// The karaoke overlay: current line bright & sharp, neighbors smaller,
/// dimmer and blurrier as they recede; lines spring upward as the song plays.
struct LyricsView: View {
    @EnvironmentObject var model: PlayerModel

    // Tweak these to restyle. design: .default (SF Pro) reads cleaner than .rounded;
    // try .serif (New York) for a classier look or .monospaced for something techy.
    private let fontDesign: Font.Design = .default

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(model.isHovering ? 1.0 : 0.62)
            .animation(.easeInOut(duration: 0.25), value: model.isHovering)
            .overlay(alignment: .bottom) { if model.isHovering { syncReadout } }
            .background { LyricTranslationCoordinator(model: model) }
    }

    /// Sync calibration HUD, shown only while hovering: scroll to adjust.
    private var syncReadout: some View {
        Text(String(format: "sync %+.2fs · scroll to adjust", model.syncOffset))
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(.black.opacity(0.45), in: Capsule())
            .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
            .padding(.bottom, 6)
    }

    @ViewBuilder
    private var content: some View {
        if !model.overlayEnabled || !model.isPlaying {
            Color.clear            // paused / stopped / finished → overlay disappears
        } else if model.lines.isEmpty {
            if model.isFetching {
                loadingIndicator  // looking up lyrics (distinct from "no match found")
            } else {
                Color.clear        // playing but no synced lyrics exist → stay invisible
            }
        } else {
            let fontSize = CGFloat(model.lyricsFontSize)
            let rowHeight = OverlayStyle.rowHeight(
                fontSize: fontSize,
                layerCount: model.visibleLyricLayerCount
            )
            let visibleIndices = LyricRenderWindow.indices(
                lineCount: model.lines.count,
                currentIndex: model.currentIndex
            )
            let firstVisibleIndex = visibleIndices.first ?? 0
            // -1 before the first line starts: line 0 then sits just below the
            // bottom edge and springs up into place the moment it begins.
            // Offset so the current line sits `currentLineFromBottom` up from the box
            // bottom; animating this translates the whole stack upward (real motion,
            // not a cross-fade). A fixed-size Color.clear sizes the box; the stack is
            // pinned to its TOP and shifted by `offset`, overflowing + clipped.
            let relativeCurrentIndex = model.currentIndex - firstVisibleIndex
            let offset = (OverlayStyle.windowHeight - OverlayStyle.currentLineFromBottom)
                - (CGFloat(relativeCurrentIndex) * rowHeight + rowHeight / 2)

            Color.clear
                .frame(height: OverlayStyle.windowHeight)
                .overlay(alignment: .top) {
                    VStack(spacing: 0) {
                        ForEach(visibleIndices, id: \.self) { idx in
                            lineView(idx: idx, line: model.lines[idx], fontSize: fontSize)
                                .frame(height: rowHeight)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                    .offset(y: offset)
                    .animation(.spring(response: 0.4, dampingFraction: 0.85), value: model.currentIndex)
                }
                .clipped()
                .mask(edgeFade)
        }
    }

    private func lineView(idx: Int, line: LyricLine, fontSize: CGFloat) -> some View {
        let cur = model.currentIndex   // -1 = not started → no line is "current" yet
        let isCurrent = idx == cur
        let d = abs(idx - cur)

        // Current line + 1 neighbour each side; everything further is hidden.
        let opacity: Double = isCurrent
            ? 1
            : (d == 1 ? model.overlayPreset.neighborOpacity : 0)
        let blur: Double = isCurrent
            ? 0
            : (d == 1 ? model.overlayPreset.neighborBlur : 0)
        // Size difference via scaleEffect (a smooth transform), NOT font size —
        // changing the font size re-lays-out and re-rasterises the text, which
        // pops instead of animating (very visible with CJK / Korean glyphs).
        let scale = isCurrent
            ? 1.0
            : model.overlayPreset.neighborScale

        return VStack(spacing: OverlayStyle.layerSpacing(fontSize)) {
            if isCurrent, model.karaokeModeEnabled, !line.text.isEmpty {
                KaraokeProgressText(
                    model: model,
                    lineIndex: idx,
                    text: line.text,
                    fontSize: fontSize,
                    fontDesign: fontDesign
                )
            } else {
                Text(line.text.isEmpty ? "♪" : line.text)
                    .font(.system(size: fontSize, weight: .bold, design: fontDesign))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.45)
            }

            if let romanized = model.romanizedText(at: idx) {
                Text(romanized)
                    .font(
                        .system(
                            size: OverlayStyle.romanizedFontSize(fontSize),
                            weight: .medium,
                            design: fontDesign
                        )
                    )
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
            }

            if let translated = model.translatedText(at: idx) {
                Text(translated)
                    .font(
                        .system(
                            size: OverlayStyle.translatedFontSize(fontSize),
                            weight: .regular,
                            design: fontDesign
                        )
                    )
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
            }
        }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, OverlayStyle.horizontalPadding)
            .opacity(opacity)
            .blur(radius: blur)
            .scaleEffect(scale, anchor: .center)
            .shadow(color: .black.opacity(0.65), radius: 5, y: 1)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: model.currentIndex)
    }

    /// Subtle "looking up lyrics" hint — three faint dots, no text.
    private var loadingIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { _ in
                Circle()
                    .frame(width: 7, height: 7)
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
    }

    /// Fades both edges so lines dissolve in/out. The bottom fade is kept SHALLOW
    /// (starts at 0.92) so the upcoming line just below the current one stays
    /// clearly visible — the old 0.72 stop was swallowing it.
    private var edgeFade: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.12),
                .init(color: .black, location: 0.92),
                .init(color: .clear, location: 1),
            ],
            startPoint: .top, endPoint: .bottom
        )
    }
}

private struct KaraokeProgressText: View {
    @ObservedObject var model: PlayerModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let lineIndex: Int
    let text: String
    let fontSize: CGFloat
    let fontDesign: Font.Design

    var body: some View {
        if reduceMotion {
            lyricText(AttributedString(text))
                .foregroundStyle(.white)
        } else {
            TimelineView(.periodic(from: .now, by: 1.0 / 10.0)) { context in
                lyricText(
                    highlightedText(
                        progress: model.karaokeProgress(
                            for: lineIndex,
                            at: context.date
                        )
                    )
                )
            }
        }
    }

    private func lyricText(_ attributedText: AttributedString) -> some View {
        Text(attributedText)
            .font(.system(size: fontSize, weight: .bold, design: fontDesign))
            .lineLimit(1)
            .minimumScaleFactor(0.45)
            .accessibilityLabel(text)
    }

    private func highlightedText(progress: Double) -> AttributedString {
        let highlightedCount = LyricKaraokeTimeline.highlightedCharacterCount(
            in: text,
            progress: progress
        )
        var highlighted = AttributedString(String(text.prefix(highlightedCount)))
        highlighted.foregroundColor = .white
        var upcoming = AttributedString(String(text.dropFirst(highlightedCount)))
        upcoming.foregroundColor = .white.opacity(0.42)
        highlighted.append(upcoming)
        return highlighted
    }
}
