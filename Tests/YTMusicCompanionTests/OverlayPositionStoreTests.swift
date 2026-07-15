import AppKit
import XCTest
@testable import YTMusicCompanion

final class OverlayPositionStoreTests: XCTestCase {
    func testSavedVisiblePositionIsRestored() throws {
        let defaults = try makeDefaults()
        let store = OverlayPositionStore(defaults: defaults)
        store.save(origin: NSPoint(x: 240, y: 180))

        let frame = store.initialFrame(
            size: NSSize(width: 1_000, height: 180),
            displays: [display()]
        )

        XCTAssertEqual(frame.origin, NSPoint(x: 240, y: 180))
    }

    func testOffscreenPositionFallsBackToPrimaryDisplay() throws {
        let defaults = try makeDefaults()
        let store = OverlayPositionStore(defaults: defaults)
        store.save(origin: NSPoint(x: 8_000, y: 8_000))

        let frame = store.initialFrame(
            size: NSSize(width: 1_000, height: 180),
            displays: [display()]
        )

        XCTAssertEqual(frame.origin, NSPoint(x: 220, y: 2))
    }

    func testResetRemovesSavedPosition() throws {
        let defaults = try makeDefaults()
        let store = OverlayPositionStore(defaults: defaults)
        store.save(origin: NSPoint(x: 240, y: 180))
        store.reset()

        let frame = store.initialFrame(
            size: NSSize(width: 1_000, height: 180),
            displays: [display()]
        )

        XCTAssertEqual(frame.origin, NSPoint(x: 220, y: 2))
    }

    private func makeDefaults() throws -> UserDefaults {
        let suite = "OverlayPositionStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    private func display() -> OverlayDisplay {
        OverlayDisplay(
            frame: NSRect(x: 0, y: 0, width: 1_440, height: 900),
            visibleFrame: NSRect(x: 0, y: 0, width: 1_440, height: 900)
        )
    }
}
