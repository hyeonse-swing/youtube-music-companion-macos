import XCTest
@testable import YTMusicCompanion

final class BoundedCacheTests: XCTestCase {
    func testEvictsLeastRecentlyUsedValueAtCapacity() {
        var cache = LRUCache<String, Int>(capacity: 2)
        cache["first"] = 1
        cache["second"] = 2
        XCTAssertEqual(cache["first"], 1)

        cache["third"] = 3

        XCTAssertEqual(cache.count, 2)
        XCTAssertEqual(cache["first"], 1)
        XCTAssertNil(cache["second"])
        XCTAssertEqual(cache["third"], 3)
    }

    func testReplacingAValueDoesNotConsumeAnotherSlot() {
        var cache = LRUCache<String, Int>(capacity: 2)
        cache["track"] = 1
        cache["track"] = 2

        XCTAssertEqual(cache.count, 1)
        XCTAssertEqual(cache["track"], 2)
    }

    func testBoundedSetEvictsItsOldestMember() {
        var set = BoundedSet<String>(capacity: 2)
        set.insert("first")
        set.insert("second")
        XCTAssertTrue(set.contains("first"))

        set.insert("third")

        XCTAssertTrue(set.contains("first"))
        XCTAssertFalse(set.contains("second"))
        XCTAssertTrue(set.contains("third"))
    }
}
