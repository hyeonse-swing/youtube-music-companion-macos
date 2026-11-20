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
        resolve(for: track, cancellation: CancellationToken())
    }

    func resolve(for track: NowPlaying, cancellation: CancellationToken) -> TrackMetadata? {
        guard !cancellation.isCancelled else { return nil }
        guard track.sourcePID > 0 else { return nil }
        guard AccessibilityPermission.ensureGranted(
            promptingOnce: promptsForAccessibilityPermission
        ) else { return nil }
        guard let snapshot = YouTubeMusicAccessibility.snapshot(
            pid: track.sourcePID,
            sourceTitle: track.title,
            cancellation: cancellation
        ) else {
            return nil
        }
        guard !cancellation.isCancelled else { return nil }
        let metadata = Self.metadata(
            documentTitle: snapshot.documentTitle,
            playerLinks: snapshot.playerLinks,
            pageURL: snapshot.pageURL,
            source: track
        )
        if metadata != nil {
            YouTubeMusicAccessibility.remember(snapshot.webArea, pid: track.sourcePID)
        }
        return metadata
    }

    static func metadata(
        documentTitle: String,
        playerLinks: [String],
        pageURL: URL? = nil,
        source: NowPlaying
    ) -> TrackMetadata? {
        guard let title = trackTitle(from: documentTitle) else { return nil }
        guard isCurrentPageTitle(title, sourceTitle: source.title) else { return nil }

        return TrackMetadata(
            title: title,
            artist: playerLinks.first ?? source.artist,
            album: playerLinks.dropFirst().first ?? source.album,
            trackURL: normalizedTrackURL(from: pageURL)
        )
    }

    private static func normalizedTrackURL(from pageURL: URL?) -> URL? {
        guard
            let pageURL,
            let components = URLComponents(url: pageURL, resolvingAgainstBaseURL: false),
            components.scheme?.lowercased() == "https",
            components.host?.lowercased() == "music.youtube.com",
            components.path == "/watch",
            let videoID = components.queryItems?
                .first(where: { $0.name == "v" })?.value,
            !videoID.isEmpty
        else { return nil }

        var normalized = URLComponents(string: "https://music.youtube.com/watch")
        normalized?.queryItems = [URLQueryItem(name: "v", value: videoID)]
        return normalized?.url
    }

    private static func trackTitle(from documentTitle: String) -> String? {
        let suffix = " | \(YouTubeMusicSource.displayName)"
        guard documentTitle.hasSuffix(suffix) else { return nil }
        let title = documentTitle.dropLast(suffix.count)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }

    fileprivate static func isCurrentPageTitle(_ pageTitle: String, sourceTitle: String) -> Bool {
        let source = Artwork.normalizeSearchTerm(sourceTitle)
        guard !source.isEmpty else { return false }
        if Artwork.normalizeSearchTerm(pageTitle) == source { return true }
        // The page can show "original - translated" while MediaRemote sends
        // one of those labels. A substring also matches another recording such
        // as "Band (Live)", which must never receive the previous song's URL.
        let labels = pageTitle.components(separatedBy: " - ")
        return labels.contains { Artwork.normalizeSearchTerm($0) == source }
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
    let webArea: AXUIElement
    let documentTitle: String
    let playerLinks: [String]
    let pageURL: URL?
}

private enum YouTubeMusicAccessibility {
    private static let cacheLock = NSLock()
    private static var cachedWebArea: (pid: Int32, element: AXUIElement)?
    private static let linkRole = "AXLink"
    private static let webAreaRole = "AXWebArea"
    private static let childrenAttribute = kAXChildrenAttribute as String
    private static let descriptionAttribute = kAXDescriptionAttribute as String
    private static let focusedWindowAttribute = kAXFocusedWindowAttribute as String
    private static let mainWindowAttribute = kAXMainWindowAttribute as String
    private static let roleAttribute = kAXRoleAttribute as String
    private static let titleAttribute = kAXTitleAttribute as String
    private static let urlAttribute = kAXURLAttribute as String
    private static let windowsAttribute = kAXWindowsAttribute as String

    static func snapshot(
        pid: Int32,
        sourceTitle: String,
        cancellation: CancellationToken
    ) -> YouTubeMusicAccessibilitySnapshot? {
        let application = AXUIElementCreateApplication(pid)
        // Chromium web apps can expose their window through AXFocusedWindow or
        // AXMainWindow while AXWindows is empty, even when the page is visible.
        let roots = [focusedWindowAttribute, mainWindowAttribute]
            .compactMap { element(application, attribute: $0) }
            + elements(application, attribute: windowsAttribute)
            + elements(application, attribute: childrenAttribute)

        for root in roots {
            guard !cancellation.isCancelled else { return nil }
            let descendants = descendants(of: root, cancellation: cancellation)
            guard let page = snapshot(in: descendants, sourceTitle: sourceTitle) else { continue }
            return page
        }

        // Chromium can remove every application-level window from AX when its
        // app shim goes into the background. The already verified web area stays
        // live and updates its title and URL as playback advances.
        if let cached = cachedWebArea(for: pid) {
            if let page = snapshot(in: descendants(of: cached, cancellation: cancellation),
                                   sourceTitle: sourceTitle) {
                return page
            }
            // MediaRemote often announces the next track before the page title
            // updates. Keep the live element for the next restrained retry.
            if role(of: cached) != webAreaRole || string(cached, attribute: titleAttribute) == nil {
                forgetWebArea(for: pid)
            }
        }
        return nil
    }

    static func remember(_ webArea: AXUIElement, pid: Int32) {
        cacheLock.withLock { cachedWebArea = (pid, webArea) }
    }

    private static func cachedWebArea(for pid: Int32) -> AXUIElement? {
        cacheLock.withLock {
            guard cachedWebArea?.pid == pid else {
                cachedWebArea = nil
                return nil
            }
            return cachedWebArea?.element
        }
    }

    private static func forgetWebArea(for pid: Int32) {
        cacheLock.withLock {
            if cachedWebArea?.pid == pid { cachedWebArea = nil }
        }
    }

    private static func snapshot(
        in elements: [AXUIElement],
        sourceTitle: String
    ) -> YouTubeMusicAccessibilitySnapshot? {
        guard let webArea = elements.first(where: { role(of: $0) == webAreaRole }) else {
            return nil
        }
        guard let documentTitle = string(webArea, attribute: titleAttribute),
              let songTitle = documentTitle.components(separatedBy: " | YouTube Music").first,
              YouTubeMusicPageMetadataResolver.isCurrentPageTitle(songTitle, sourceTitle: sourceTitle)
        else { return nil }

        return YouTubeMusicAccessibilitySnapshot(
            webArea: webArea,
            documentTitle: documentTitle,
            playerLinks: playerLinkLabels(in: elements),
            pageURL: pageURL(of: webArea)
        )
    }

    private static func pageURL(of webArea: AXUIElement) -> URL? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                webArea,
                urlAttribute as CFString,
                &value
            ) == .success
        else { return nil }
        if let url = value as? URL { return url }
        if let string = value as? String { return URL(string: string) }
        return nil
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

    private static func descendants(
        of root: AXUIElement,
        limit: Int = 2_000,
        cancellation: CancellationToken? = nil
    ) -> [AXUIElement] {
        var result: [AXUIElement] = []
        var pending = [root]
        var index = 0

        while index < pending.count, result.count < limit {
            if cancellation?.isCancelled == true { break }
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

    private static func element(_ application: AXUIElement, attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
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
