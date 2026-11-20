import AppKit
import XCTest
@testable import YTMusicCompanion

final class CompactPlayerPositionTests: XCTestCase {
    func testCompactCardRestoresSavedVisibleScreenAndFallsBackAfterDisconnect() {
        let suite = "CompactPlayerPositionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let position = CompactPlayerPosition(defaults: defaults)
        let size = NSSize(width: 310, height: 180)
        let primary = OverlayDisplay(
            frame: NSRect(x: 0, y: 0, width: 1440, height: 900),
            visibleFrame: NSRect(x: 0, y: 24, width: 1440, height: 840)
        )
        let external = OverlayDisplay(
            frame: NSRect(x: 1440, y: 0, width: 1920, height: 1080),
            visibleFrame: NSRect(x: 1440, y: 24, width: 1920, height: 1000)
        )
        XCTAssertEqual(
            position.initialOrigin(size: size, displays: [primary, external]),
            NSPoint(x: 1118, y: 672)
        )
        let saved = NSPoint(x: 3000, y: 500)
        position.save(origin: saved)
        XCTAssertEqual(position.initialOrigin(size: size, displays: [primary, external]), saved)
        XCTAssertEqual(
            position.initialOrigin(size: size, displays: [primary]),
            NSPoint(x: 1118, y: 672)
        )
    }
}
