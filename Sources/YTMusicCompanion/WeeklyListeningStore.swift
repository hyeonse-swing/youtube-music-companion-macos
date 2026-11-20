import CryptoKit
import Foundation

/// Counts distinct YouTube Music songs for each artist in the current local week.
/// Preferences retain salted hashes instead of song or artist text.
@MainActor
final class WeeklyListeningStore {
    private static let snapshotKey = "weeklyListeningSnapshot"
    private static let saltKey = "weeklyListeningSalt"

    private struct Snapshot: Codable {
        let week: String
        var tracksByArtist: [String: Set<String>]
    }

    private let defaults: UserDefaults
    private let calendar: Calendar
    private var cachedSnapshot: Snapshot?
    private var cachedSalt: String?
    private var hasLoadedSalt = false
    private var cachedTrackIDs: (artist: String, title: String, salt: String,
                                 artistID: String, trackID: String)?

    init(defaults: UserDefaults = .standard, calendar: Calendar = .autoupdatingCurrent) {
        self.defaults = defaults
        self.calendar = calendar
    }

    @discardableResult
    func record(track: NowPlaying, now: Date = Date()) -> Int {
        guard let identity = Self.identity(for: track) else { return 0 }
        guard track.isPlaying, track.rate > 0 else { return count(for: track, now: now) }

        let salt = existingSalt() ?? createSalt()
        let (artistID, trackID) = ids(for: identity, salt: salt)
        var snapshot = currentSnapshot(now: now)
        var artistTracks = snapshot.tracksByArtist[artistID] ?? []

        guard !artistTracks.contains(trackID) else { return artistTracks.count }
        artistTracks.insert(trackID)
        snapshot.tracksByArtist[artistID] = artistTracks
        return save(snapshot) ? artistTracks.count : artistTracks.count - 1
    }

    func count(for track: NowPlaying, now: Date = Date()) -> Int {
        guard let identity = Self.identity(for: track), let salt = existingSalt() else { return 0 }
        let (artistID, _) = ids(for: identity, salt: salt)
        return currentSnapshot(now: now).tracksByArtist[artistID]?.count ?? 0
    }

    func remove(track: NowPlaying) {
        guard let identity = Self.identity(for: track), let salt = existingSalt() else { return }
        var snapshot = currentSnapshot(now: Date())
        let (artistID, trackID) = ids(for: identity, salt: salt)
        guard var artistTracks = snapshot.tracksByArtist[artistID],
              artistTracks.remove(trackID) != nil else { return }
        if artistTracks.isEmpty {
            snapshot.tracksByArtist.removeValue(forKey: artistID)
        } else {
            snapshot.tracksByArtist[artistID] = artistTracks
        }
        _ = save(snapshot)
    }

    func reset() {
        cachedSnapshot = nil
        cachedSalt = nil
        cachedTrackIDs = nil
        hasLoadedSalt = true
        defaults.removeObject(forKey: Self.snapshotKey)
        defaults.removeObject(forKey: Self.saltKey)
    }

    private func currentSnapshot(now: Date) -> Snapshot {
        let week = weekIdentifier(for: now)
        if let cachedSnapshot, cachedSnapshot.week == week { return cachedSnapshot }

        if let cachedSnapshot, cachedSnapshot.week != week {
            if defaults.object(forKey: Self.snapshotKey) != nil {
                defaults.removeObject(forKey: Self.snapshotKey)
            }
        } else if let data = defaults.data(forKey: Self.snapshotKey) {
            if let stored = try? PropertyListDecoder().decode(Snapshot.self, from: data),
               stored.week == week {
                cachedSnapshot = stored
                return stored
            }
            defaults.removeObject(forKey: Self.snapshotKey)
        }

        let fresh = Snapshot(week: week, tracksByArtist: [:])
        cachedSnapshot = fresh
        return fresh
    }

    @discardableResult
    private func save(_ snapshot: Snapshot) -> Bool {
        guard let data = try? PropertyListEncoder().encode(snapshot) else { return false }
        defaults.set(data, forKey: Self.snapshotKey)
        cachedSnapshot = snapshot
        return true
    }

    private func existingSalt() -> String? {
        if !hasLoadedSalt {
            cachedSalt = defaults.string(forKey: Self.saltKey)
            hasLoadedSalt = true
        }
        return cachedSalt
    }

    private func createSalt() -> String {
        // A missing salt makes any previously stored hashes unusable.
        defaults.removeObject(forKey: Self.snapshotKey)
        cachedSnapshot = nil
        cachedTrackIDs = nil
        let salt = UUID().uuidString
        defaults.set(salt, forKey: Self.saltKey)
        cachedSalt = salt
        hasLoadedSalt = true
        return salt
    }

    private func weekIdentifier(for date: Date) -> String {
        var mondayCalendar = Calendar(identifier: .iso8601)
        mondayCalendar.timeZone = calendar.timeZone
        let monday = mondayCalendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
        let components = mondayCalendar.dateComponents([.year, .month, .day], from: monday)
        return String(format: "%04d-%02d-%02d",
                      components.year ?? 0,
                      components.month ?? 0,
                      components.day ?? 0)
    }

    private func digest(_ components: [String], salt: String) -> String {
        let input = ([salt] + components).map { "\($0.utf8.count):\($0)" }.joined()
        return SHA256.hash(data: Data(input.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func ids(for identity: (artist: String, title: String),
                     salt: String) -> (artistID: String, trackID: String) {
        if let cachedTrackIDs,
           cachedTrackIDs.artist == identity.artist,
           cachedTrackIDs.title == identity.title,
           cachedTrackIDs.salt == salt {
            return (cachedTrackIDs.artistID, cachedTrackIDs.trackID)
        }
        let artistID = digest(["artist", identity.artist], salt: salt)
        let trackID = digest(["track", identity.artist, identity.title], salt: salt)
        cachedTrackIDs = (identity.artist, identity.title, salt, artistID, trackID)
        return (artistID, trackID)
    }

    private static func identity(for track: NowPlaying) -> (artist: String, title: String)? {
        let artist = normalize(track.artist)
        let title = normalize(track.title)
        guard !artist.isEmpty, !title.isEmpty else { return nil }
        return (artist, title)
    }

    private static func normalize(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .precomposedStringWithCanonicalMapping
            .lowercased(with: Locale(identifier: "en_US_POSIX"))
    }
}
