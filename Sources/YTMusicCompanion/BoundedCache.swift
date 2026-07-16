import Foundation

enum SessionCacheLimits {
    static let metadata = 48
    static let retryState = 48
    static let artwork = 12
    static let lyrics = 24
    static let lyricCandidates = 12
    static let negativeResults = 48
    static let discordArtwork = 32
    static let processIdentity = 16
}

/// A small deterministic LRU cache for session-only, re-derivable data.
struct LRUCache<Key: Hashable, Value> {
    let capacity: Int

    private var values: [Key: Value] = [:]
    private var recency: [Key] = []

    init(capacity: Int) {
        precondition(capacity > 0)
        self.capacity = capacity
    }

    var count: Int { values.count }

    subscript(key: Key) -> Value? {
        mutating get {
            guard let value = values[key] else { return nil }
            markRecentlyUsed(key)
            return value
        }
        set {
            guard let newValue else {
                removeValue(forKey: key)
                return
            }
            insert(newValue, forKey: key)
        }
    }

    mutating func insert(_ value: Value, forKey key: Key) {
        values[key] = value
        markRecentlyUsed(key)
        evictIfNeeded()
    }

    @discardableResult
    mutating func removeValue(forKey key: Key) -> Value? {
        recency.removeAll { $0 == key }
        return values.removeValue(forKey: key)
    }

    private mutating func markRecentlyUsed(_ key: Key) {
        recency.removeAll { $0 == key }
        recency.append(key)
    }

    private mutating func evictIfNeeded() {
        while values.count > capacity, let oldest = recency.first {
            recency.removeFirst()
            values.removeValue(forKey: oldest)
        }
    }
}

struct BoundedSet<Element: Hashable> {
    private var cache: LRUCache<Element, Bool>

    init(capacity: Int) {
        cache = LRUCache(capacity: capacity)
    }

    var count: Int { cache.count }

    mutating func contains(_ element: Element) -> Bool {
        cache[element] != nil
    }

    @discardableResult
    mutating func insert(_ element: Element) -> Bool {
        let isNew = cache[element] == nil
        cache[element] = true
        return isNew
    }

    mutating func remove(_ element: Element) {
        cache.removeValue(forKey: element)
    }
}
