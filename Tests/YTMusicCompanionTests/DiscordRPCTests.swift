import XCTest
@testable import YTMusicCompanion

final class DiscordRPCTests: XCTestCase {
    func testActivityEncodingIncludesClickableSongLink() throws {
        let songURL = URL(string: "https://music.youtube.com/watch?v=abc123")!
        let activity = PresenceActivity(
            name: "YouTube Music",
            details: "Test Song",
            state: "Test Artist",
            start: nil,
            end: nil,
            largeImage: "https://example.com/cover.jpg",
            largeImageText: "Test Album",
            smallImage: "youtube-music",
            smallImageText: "YouTube Music",
            largeImageURL: songURL,
            buttons: [PresenceButton(label: "Listen on YouTube Music", url: songURL)]
        )

        let data = try XCTUnwrap(
            DiscordRPC.encodedSetActivityCommand(
                activity,
                pid: 42,
                nonce: "test-nonce"
            )
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let args = try XCTUnwrap(object["args"] as? [String: Any])
        let encodedActivity = try XCTUnwrap(args["activity"] as? [String: Any])
        let assets = try XCTUnwrap(encodedActivity["assets"] as? [String: Any])
        let buttons = try XCTUnwrap(encodedActivity["buttons"] as? [[String: Any]])

        XCTAssertEqual(assets["large_url"] as? String, songURL.absoluteString)
        XCTAssertEqual(buttons.count, 1)
        XCTAssertEqual(buttons.first?["label"] as? String, "Listen on YouTube Music")
        XCTAssertEqual(buttons.first?["url"] as? String, songURL.absoluteString)
    }

    func testActivityEncodingRejectsNonHTTPSButtons() throws {
        let activity = PresenceActivity(
            name: "YouTube Music",
            details: "Test Song",
            state: "Test Artist",
            start: nil,
            end: nil,
            largeImage: nil,
            largeImageText: nil,
            smallImage: nil,
            smallImageText: nil,
            buttons: [
                PresenceButton(
                    label: "Unsafe",
                    url: URL(string: "http://example.com")!
                ),
            ]
        )

        let data = try XCTUnwrap(
            DiscordRPC.encodedSetActivityCommand(
                activity,
                pid: 42,
                nonce: "test-nonce"
            )
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let args = try XCTUnwrap(object["args"] as? [String: Any])
        let encodedActivity = try XCTUnwrap(args["activity"] as? [String: Any])

        XCTAssertNil(encodedActivity["buttons"])
    }

    func testActivityEncodingIncludesFieldAndAssetURLs() throws {
        let detailsURL = URL(string: "https://example.com/details")!
        let stateURL = URL(string: "https://example.com/state")!
        let coverURL = URL(string: "https://example.com/cover")!
        let smallURL = URL(string: "https://example.com/source")!
        let activity = PresenceActivity(
            name: "YouTube Music",
            details: "Test Song",
            state: "Test Artist",
            start: nil,
            end: nil,
            largeImage: "cover",
            largeImageText: "Album",
            smallImage: "youtube-music",
            smallImageText: "YouTube Music",
            detailsURL: detailsURL,
            stateURL: stateURL,
            largeImageURL: coverURL,
            smallImageURL: smallURL
        )

        let data = try XCTUnwrap(
            DiscordRPC.encodedSetActivityCommand(
                activity,
                pid: 42,
                nonce: "test-nonce"
            )
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let args = try XCTUnwrap(object["args"] as? [String: Any])
        let encodedActivity = try XCTUnwrap(args["activity"] as? [String: Any])
        let assets = try XCTUnwrap(encodedActivity["assets"] as? [String: Any])

        XCTAssertEqual(encodedActivity["details_url"] as? String, detailsURL.absoluteString)
        XCTAssertEqual(encodedActivity["state_url"] as? String, stateURL.absoluteString)
        XCTAssertEqual(assets["large_url"] as? String, coverURL.absoluteString)
        XCTAssertEqual(assets["small_url"] as? String, smallURL.absoluteString)
    }

    func testActivityEncodingClampsUnicodeTextInLinearByteOrder() throws {
        let activity = PresenceActivity(
            name: "",
            details: String(repeating: "가", count: 100),
            state: "x",
            start: nil,
            end: nil,
            largeImage: nil,
            largeImageText: nil,
            smallImage: nil,
            smallImageText: nil
        )

        let data = try XCTUnwrap(
            DiscordRPC.encodedSetActivityCommand(
                activity,
                pid: 42,
                nonce: "test-nonce"
            )
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let args = try XCTUnwrap(object["args"] as? [String: Any])
        let encodedActivity = try XCTUnwrap(args["activity"] as? [String: Any])
        let name = try XCTUnwrap(encodedActivity["name"] as? String)
        let details = try XCTUnwrap(encodedActivity["details"] as? String)
        let state = try XCTUnwrap(encodedActivity["state"] as? String)

        XCTAssertEqual(name.utf8.count, 2)
        XCTAssertLessThanOrEqual(details.utf8.count, 128)
        XCTAssertEqual(details, String(repeating: "가", count: 42))
        XCTAssertEqual(state, "x ")
    }
}
