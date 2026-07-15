import ApplicationServices
import AppKit
import Foundation

/// Reads the labels rendered by YouTube Music's player bar. MediaRemote exposes
/// playback timing reliably, but Chrome can publish an English-only title there
/// while the page displays the original and English labels together.
final class YouTubeMusicPageMetadataResolver: TrackMetadataResolving, @unchecked Sendable {
    private let promptsForAccessibilityPermission: Bool

    init(promptsForAccessibilityPermission: Bool = true) {
        self.promptsForAccessibilityPermission = promptsForAccessibilityPermission
    }

    func resolve(for track: NowPlaying) -> TrackMetadata? {
        guard track.sourcePID > 0 else { return nil }
        guard AccessibilityPermission.ensureGranted(
            promptingOnce: promptsForAccessibilityPermission
        ) else { return nil }
        guard let snapshot = YouTubeMusicAccessibility.snapshot(pid: track.sourcePID) else {
            return nil
        }
        return Self.metadata(
            documentTitle: snapshot.documentTitle,
            playerLinks: snapshot.playerLinks,
            source: track
        )
    }

    static func metadata(
        documentTitle: String,
        playerLinks: [String],
        source: NowPlaying
    ) -> TrackMetadata? {
        guard let title = trackTitle(from: documentTitle) else { return nil }
        guard isCurrentPageTitle(title, sourceTitle: source.title) else { return nil }

        return TrackMetadata(
            title: title,
            artist: playerLinks.first ?? source.artist,
            album: playerLinks.dropFirst().first ?? source.album
        )
    }

    private static func trackTitle(from documentTitle: String) -> String? {
        let suffix = " | \(YouTubeMusicSource.displayName)"
        guard documentTitle.hasSuffix(suffix) else { return nil }
        let title = documentTitle.dropLast(suffix.count)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }

    private static func isCurrentPageTitle(_ pageTitle: String, sourceTitle: String) -> Bool {
        let page = Artwork.normalizeSearchTerm(pageTitle)
        let source = Artwork.normalizeSearchTerm(sourceTitle)
        guard !page.isEmpty, !source.isEmpty else { return false }
        return page.contains(source) || source.contains(page)
    }
}

enum AccessibilityPermission {
    private static let lock = NSLock()
    private static var hasPrompted = false

    static var isGranted: Bool { AXIsProcessTrusted() }

    static func ensureGranted(promptingOnce shouldPrompt: Bool) -> Bool {
        if isGranted { return true }

        let prompt = lock.withLock { () -> Bool in
            guard shouldPrompt, !hasPrompted else { return false }
            hasPrompted = true
            return true
        }
        guard prompt else { return false }

        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        return false
    }

    @MainActor
    static func requestFromMenu() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        guard
            !isGranted,
            let settingsURL = URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
            )
        else { return }
        NSWorkspace.shared.open(settingsURL)
    }
}

private struct YouTubeMusicAccessibilitySnapshot {
    let documentTitle: String
    let playerLinks: [String]
}

private enum YouTubeMusicAccessibility {
    private static let linkRole = "AXLink"
    private static let webAreaRole = "AXWebArea"
    private static let childrenAttribute = kAXChildrenAttribute as String
    private static let descriptionAttribute = kAXDescriptionAttribute as String
    private static let roleAttribute = kAXRoleAttribute as String
    private static let titleAttribute = kAXTitleAttribute as String
    private static let windowsAttribute = kAXWindowsAttribute as String

    static func snapshot(pid: Int32) -> YouTubeMusicAccessibilitySnapshot? {
        let application = AXUIElementCreateApplication(pid)
        let roots = elements(application, attribute: windowsAttribute)
            + elements(application, attribute: childrenAttribute)

        for root in roots {
            let descendants = descendants(of: root)
            guard let documentTitle = documentTitle(in: descendants) else { continue }
            let playerLinks = playerLinkLabels(in: descendants)
            return YouTubeMusicAccessibilitySnapshot(
                documentTitle: documentTitle,
                playerLinks: playerLinks
            )
        }
        return nil
    }

    private static func documentTitle(in elements: [AXUIElement]) -> String? {
        elements.first { role(of: $0) == webAreaRole }
            .flatMap { string($0, attribute: titleAttribute) }
    }

    private static func playerLinkLabels(in elements: [AXUIElement]) -> [String] {
        let toolbars = elements.filter { role(of: $0) == kAXToolbarRole as String }
        for toolbar in toolbars {
            let elements = descendants(of: toolbar)
            guard elements.contains(where: {
                role(of: $0) == kAXProgressIndicatorRole as String
            }) else { continue }

            return elements
                .filter { role(of: $0) == linkRole }
                .compactMap(linkLabel)
        }
        return []
    }

    private static func linkLabel(_ element: AXUIElement) -> String? {
        for attribute in [titleAttribute, descriptionAttribute] {
            if let label = string(element, attribute: attribute), !label.isEmpty {
                return label
            }
        }
        return nil
    }

    private static func descendants(of root: AXUIElement, limit: Int = 2_000) -> [AXUIElement] {
        var result: [AXUIElement] = []
        var pending = [root]
        var index = 0

        while index < pending.count, result.count < limit {
            let element = pending[index]
            index += 1
            result.append(element)
            pending.append(contentsOf: elements(element, attribute: childrenAttribute))
        }
        return result
    }

    private static func elements(_ element: AXUIElement, attribute: String) -> [AXUIElement] {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
            let elements = value as? [AXUIElement]
        else { return [] }
        return elements
    }

    private static func role(of element: AXUIElement) -> String? {
        string(element, attribute: roleAttribute)
    }

    private static func string(_ element: AXUIElement, attribute: String) -> String? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
            let string = value as? String
        else { return nil }
        return string
    }
}
