import XCTest
@testable import YTMusicCompanion

final class SystemMediaPriorityTests: XCTestCase {
    @MainActor
    func testMusicKeepsHeadsetWhilePausedOrAnotherSourceAppears() {
        var overrides: [String?] = []
        var running = true
        let priority = SystemMediaPriority(setOverride: { overrides.append($0) }, isRunning: { _ in running })
        var music = snapshot()
        priority.update(music)
        music.isPlaying = false
        music.rate = 0
        priority.update(music)
        priority.update(nil)
        var video = music
        video.sourceBundle = "com.google.Chrome"
        priority.update(video)
        XCTAssertEqual(overrides.count, 1)
        XCTAssertEqual(overrides.first!, music.sourceBundle)
        running = false
        priority.update(nil)
        XCTAssertEqual(overrides.count, 2)
        XCTAssertNil(overrides.last!)
        priority.release()
        XCTAssertEqual(overrides.count, 2)
    }

    @MainActor
    func testOtherAppsNeverClaimPriorityAndShutdownReleasesIt() {
        var overrides: [String?] = []
        let priority = SystemMediaPriority(setOverride: { overrides.append($0) }, isRunning: { _ in true })
        var video = snapshot()
        video.sourceBundle = "com.google.Chrome"
        priority.update(video)
        XCTAssertTrue(overrides.isEmpty)
        priority.update(snapshot())
        priority.release()
        XCTAssertEqual(overrides.count, 2)
        XCTAssertNil(overrides.last!)
    }

    func testTargetedSnapshotUsesItsOwnTimingAndPausedState() {
        let result = MediaRemoteBridge.decode([
            "Title": "Music", "Artist": "Artist", "PlaybackRate": 0,
            "ElapsedTime": 42, "Timestamp": 100, "isPlaying": false,
            "Bundle": "com.google.Chrome.app.cinhimbnkkaeohfgghhklpknlkffjgod", "SourcePID": 123
        ])
        XCTAssertEqual(result?.elapsed, 42)
        XCTAssertEqual(result?.timestamp, 100)
        XCTAssertEqual(result?.isPlaying, false)
        XCTAssertEqual(result?.sourcePID, 123)
        XCTAssertNil(MediaRemoteBridge.decode([:]))
        XCTAssertNil(MediaRemoteBridge.decode(["error": "unsupported"]))
    }

    private func snapshot() -> NowPlaying {
        NowPlaying(title: "Music", artist: "Artist", album: "", duration: 100,
                   elapsed: 10, timestamp: 100, isPlaying: true, rate: 1,
                   sourceBundle: "com.google.Chrome.app.cinhimbnkkaeohfgghhklpknlkffjgod", sourcePID: 123)
    }
}
