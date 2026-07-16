import AppKit

struct OverlayDisplay {
    let frame: NSRect
    let visibleFrame: NSRect
}

struct OverlayPositionStore {
    private static let xKey = "lyricsOverlayOriginX"
    private static let yKey = "lyricsOverlayOriginY"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func initialFrame(size: NSSize, screens: [NSScreen] = NSScreen.screens) -> NSRect {
        initialFrame(size: size, displays: screens.map {
            OverlayDisplay(frame: $0.frame, visibleFrame: $0.visibleFrame)
        })
    }

    func initialFrame(size: NSSize, displays: [OverlayDisplay]) -> NSRect {
        let fallback = Self.defaultFrame(size: size, displays: displays)
        guard
            defaults.object(forKey: Self.xKey) != nil,
            defaults.object(forKey: Self.yKey) != nil
        else { return fallback }

        let savedOrigin = NSPoint(
            x: defaults.double(forKey: Self.xKey),
            y: defaults.double(forKey: Self.yKey)
        )
        let visibleFrames = displays.map(\.visibleFrame)
        guard Self.isUsable(origin: savedOrigin, size: size, visibleFrames: visibleFrames) else {
            return fallback
        }
        return NSRect(origin: savedOrigin, size: size)
    }

    func save(origin: NSPoint) {
        defaults.set(origin.x, forKey: Self.xKey)
        defaults.set(origin.y, forKey: Self.yKey)
    }

    func reset() {
        defaults.removeObject(forKey: Self.xKey)
        defaults.removeObject(forKey: Self.yKey)
    }

    static func defaultFrame(size: NSSize, screens: [NSScreen] = NSScreen.screens) -> NSRect {
        defaultFrame(size: size, displays: screens.map {
            OverlayDisplay(frame: $0.frame, visibleFrame: $0.visibleFrame)
        })
    }

    static func defaultFrame(size: NSSize, displays: [OverlayDisplay]) -> NSRect {
        let bounds = displays.first?.frame ?? NSRect(x: 0, y: 0, width: 1_440, height: 900)
        let visible = displays.first?.visibleFrame ?? bounds
        return NSRect(
            x: bounds.midX - size.width / 2,
            y: visible.minY + 2,
            width: size.width,
            height: size.height
        )
    }

    /// Keep at least a practical grab area on one display. Merely touching a screen
    /// edge is not enough because the lyric line would still be impossible to grab.
    static func isUsable(origin: NSPoint, size: NSSize, visibleFrames: [NSRect]) -> Bool {
        let frame = NSRect(origin: origin, size: size)
        return visibleFrames.contains { visibleFrame in
            let intersection = frame.intersection(visibleFrame)
            return intersection.width >= 120
                && intersection.height >= OverlayStyle.rowHeight(
                    fontSize: OverlayStyle.defaultFontSize
                )
        }
    }
}
