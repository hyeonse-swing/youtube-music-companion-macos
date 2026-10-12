import XCTest
@testable import YTMusicCompanion

final class MediaRemoteBridgeTests: XCTestCase {
    private let music: [String: Any] = [
        "Title": "Current song", "Artist": "Artist", "PlaybackRate": 1,
        "isPlaying": true, "ElapsedTime": 42,
        "Bundle": "com.google.Chrome.app.cinhimbnkkaeohfgghhklpknlkffjgod",
    ]

    func testDirectMusicSnapshotWinsOverAnotherSystemPlayer() {
        let result = MediaRemoteBridge.query(
            cancellation: CancellationToken(),
            preferredQuery: { self.music },
            fallbackQuery: { XCTFail("Valid direct snapshot must not query the elected player"); return nil }
        )
        XCTAssertEqual(result?.title, "Current song")
        XCTAssertEqual(result?.elapsed, 42)
    }

    func testEmptyAndIncompleteDirectResponsesAllowMusicFallback() {
        for response in [[:], ["Title": "Incomplete"], ["error": "query failed"]] {
            let result = MediaRemoteBridge.query(
                cancellation: CancellationToken(),
                preferredQuery: { response },
                fallbackQuery: { self.music }
            )
            XCTAssertEqual(result?.title, "Current song")
        }
    }

    func testAnotherSystemPlayerIsNeverReturnedAfterDirectLookupFails() {
        var video = music
        video["Bundle"] = "com.google.Chrome"
        video["Title"] = "Unrelated video"
        let result = MediaRemoteBridge.query(
            cancellation: CancellationToken(),
            preferredQuery: { ["error": "query failed"] },
            fallbackQuery: { video }
        )
        XCTAssertNil(result)
    }

    func testNonMusicDirectResponseCannotSuppressValidMusicFallback() {
        var other = music
        other["Bundle"] = "com.apple.Music"
        let result = MediaRemoteBridge.query(
            cancellation: CancellationToken(),
            preferredQuery: { other },
            fallbackQuery: { self.music }
        )
        XCTAssertEqual(result?.sourceBundle, music["Bundle"] as? String)
    }

    func testPartialFallbackDoesNotExposeAnInvalidTrack() {
        var partial = music
        partial["Artist"] = ""
        XCTAssertNil(MediaRemoteBridge.query(
            cancellation: CancellationToken(),
            preferredQuery: { nil },
            fallbackQuery: { partial }
        ))
    }

    func testGenericBrowserParentDoesNotHideInstalledMusicBundle() {
        var response = music
        response["ParentBundle"] = "com.google.Chrome"
        let result = MediaRemoteBridge.query(
            cancellation: CancellationToken(),
            preferredQuery: { nil },
            fallbackQuery: { response }
        )
        XCTAssertEqual(result?.sourceBundle, music["Bundle"] as? String)
    }

    func testMusicParentIdentifiesAHelperClient() {
        var response = music
        response["ParentBundle"] = music["Bundle"]
        response["Bundle"] = "com.google.Chrome.helper"
        XCTAssertEqual(MediaRemoteBridge.decode(response)?.sourceBundle, music["Bundle"] as? String)
    }

    func testCancelledQueryDoesNotStartAnySubprocess() {
        let cancellation = CancellationToken()
        cancellation.cancel()
        XCTAssertNil(MediaRemoteBridge.query(
            cancellation: cancellation,
            preferredQuery: { XCTFail("Cancelled"); return nil },
            fallbackQuery: { XCTFail("Cancelled"); return nil }
        ))
    }

    func testCancellationDuringDirectQueryPreventsFallback() {
        let cancellation = CancellationToken()
        XCTAssertNil(MediaRemoteBridge.query(
            cancellation: cancellation,
            preferredQuery: { cancellation.cancel(); return self.music },
            fallbackQuery: { XCTFail("Cancelled"); return nil }
        ))
    }
}
