import Foundation
import XCTest
@testable import YTMusicCompanion

@MainActor
final class WeeklyListeningStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        suiteName = "WeeklyListeningStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        calendar = nil
        super.tearDown()
    }

    func testDistinctSongsPersistAcrossRestartWithoutSavingNames() {
        let friday = date("2026-11-20T10:00:00Z")
        let store = WeeklyListeningStore(defaults: defaults, calendar: calendar)
        var first = track(title: "  First   Song ", artist: " Test   Artist ")

        XCTAssertEqual(store.record(track: first, now: friday), 1)
        first.title = "first song"
        first.artist = "TEST ARTIST"
        first.album = "Another release"
        first.duration = 250
        first.elapsed = 90
        XCTAssertEqual(store.record(track: first, now: friday), 1)
        XCTAssertEqual(store.record(track: track(title: "Second Song"), now: friday), 2)
        XCTAssertEqual(store.record(track: track(title: "First Song", artist: "Other Artist"), now: friday), 1)

        let restarted = WeeklyListeningStore(defaults: defaults, calendar: calendar)
        XCTAssertEqual(restarted.count(for: first, now: friday), 2)
        let storedData = defaults.dictionaryRepresentation().values.compactMap { $0 as? Data }
        XCTAssertFalse(storedData.isEmpty)
        for value in storedData {
            XCTAssertNil(value.range(of: Data("First Song".utf8)))
            XCTAssertNil(value.range(of: Data("Test Artist".utf8)))
        }
    }

    func testPausedOrIncompleteSnapshotsDoNotIncreaseTheCount() {
        let store = WeeklyListeningStore(defaults: defaults, calendar: calendar)
        let now = Date()
        var snapshot = track()
        snapshot.isPlaying = false
        XCTAssertEqual(store.record(track: snapshot, now: now), 0)
        snapshot.isPlaying = true
        snapshot.rate = 0
        XCTAssertEqual(store.record(track: snapshot, now: now), 0)
        snapshot.rate = 1
        snapshot.title = "   "
        XCTAssertEqual(store.record(track: snapshot, now: now), 0)
        snapshot.title = "First Song"
        XCTAssertEqual(store.record(track: snapshot, now: now), 1)
        snapshot.isPlaying = false
        XCTAssertEqual(store.record(track: snapshot, now: now), 1)
    }

    func testLocalMondayBoundaryDropsThePreviousWeek() {
        let store = WeeklyListeningStore(defaults: defaults, calendar: calendar)
        let sunday = date("2026-11-22T14:59:59Z")
        let monday = date("2026-11-22T15:00:00Z")
        let first = track()

        XCTAssertEqual(store.record(track: first, now: sunday), 1)
        XCTAssertEqual(store.count(for: first, now: monday), 0)
        XCTAssertEqual(store.record(track: first, now: monday), 1)
        XCTAssertEqual(store.record(track: track(title: "Second Song"), now: monday), 2)
    }

    func testRemovingOneSongAndResettingTheWeek() {
        let store = WeeklyListeningStore(defaults: defaults, calendar: calendar)
        let first = track()
        let second = track(title: "Second Song")

        XCTAssertEqual(store.record(track: first), 1)
        XCTAssertEqual(store.record(track: second), 2)
        store.remove(track: first)
        XCTAssertEqual(store.count(for: second), 1)
        XCTAssertEqual(store.record(track: first), 2)
        store.reset()
        XCTAssertEqual(store.count(for: first), 0)
        XCTAssertEqual(store.record(track: second), 1)
    }

    private func track(title: String = "First Song", artist: String = "Test Artist") -> NowPlaying {
        NowPlaying(
            title: title,
            artist: artist,
            album: "Test Album",
            duration: 180,
            elapsed: 30,
            timestamp: 1_000,
            isPlaying: true,
            rate: 1,
            sourceBundle: "com.google.Chrome.app.\(YouTubeMusicSource.webAppID)",
            sourcePID: 0
        )
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}
