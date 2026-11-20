import XCTest
import Darwin
@testable import YTMusicCompanion

final class DiscordRPCTests: XCTestCase {
    func testRejectedStatusFieldFallsBackAndClearAcknowledges() async throws {
        // A private Unix socket stands in for Discord; no real account is contacted.
        let (listener, path) = try makeRPCListener()
        defer {
            Darwin.close(listener)
            unlink(path)
        }

        let serverDone = expectation(description: "fake Discord finished")
        let observed = CapturedRPCCommands()
        DispatchQueue.global().async {
            defer { serverDone.fulfill() }
            let client = Darwin.accept(listener, nil, nil)
            guard client >= 0 else { return }
            defer { Darwin.close(client) }
            var timeout = timeval(tv_sec: 2, tv_usec: 0)
            setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

            guard let handshake = readRPCFrame(client), handshake.opcode == 0,
                  writeRPCFrame(client, object: ["evt": "READY"]) else { return }
            for index in 0..<4 {
                guard let frame = readRPCFrame(client), frame.opcode == 1,
                      let command = try? JSONSerialization.jsonObject(with: frame.body) as? [String: Any],
                      let nonce = command["nonce"] as? String else { return }
                observed.append(command)
                let event: Any = index == 0 ? "ERROR" : NSNull()
                guard writeRPCFrame(client, object: [
                    "cmd": "SET_ACTIVITY", "nonce": nonce, "evt": event,
                ]) else { return }
            }
        }

        let rpc = DiscordRPC(clientID: "test-client", socketPaths: [path])
        let activity = PresenceActivity(
            name: "YouTube Music", details: "Test Song", state: "Test Artist",
            start: nil, end: nil, largeImage: nil, largeImageText: nil,
            smallImage: nil, smallImageText: nil, statusDisplayType: .details
        )
        let first = expectation(description: "fallback activity accepted")
        rpc.setActivity(activity) { accepted in
            XCTAssertTrue(accepted)
            first.fulfill()
        }
        await fulfillment(of: [first], timeout: 5)

        var next = activity
        next.details = "Next Song"
        let second = expectation(description: "next activity uses legacy payload")
        rpc.setActivity(next) { accepted in
            XCTAssertTrue(accepted)
            second.fulfill()
        }
        await fulfillment(of: [second], timeout: 5)

        let cleared = expectation(description: "activity cleared")
        rpc.clear { accepted in
            XCTAssertTrue(accepted)
            cleared.fulfill()
        }
        await fulfillment(of: [cleared, serverDone], timeout: 5)

        let commands = observed.all
        XCTAssertEqual(commands.count, 4)
        let activities = commands.compactMap {
            ($0["args"] as? [String: Any])?["activity"] as? [String: Any]
        }
        XCTAssertEqual(activities.count, 3)
        XCTAssertEqual(activities[0]["status_display_type"] as? Int, 2)
        XCTAssertEqual(activities[0]["name"] as? String, "YouTube Music")
        XCTAssertNil(activities[1]["status_display_type"])
        XCTAssertEqual(activities[1]["name"] as? String, "Test Song")
        XCTAssertNil(activities[2]["status_display_type"])
        XCTAssertEqual(activities[2]["name"] as? String, "Next Song")
        XCTAssertTrue((commands[3]["args"] as? [String: Any])?["activity"] is NSNull)
    }

    func testProbeRequiresMatchingAcknowledgement() async throws {
        let (listener, path) = try makeRPCListener()
        defer {
            Darwin.close(listener)
            unlink(path)
        }
        let serverDone = expectation(description: "silent client finished")
        let releaseClient = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            defer { serverDone.fulfill() }
            let client = Darwin.accept(listener, nil, nil)
            guard client >= 0 else { return }
            defer { Darwin.close(client) }
            var timeout = timeval(tv_sec: 2, tv_usec: 0)
            setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            guard let handshake = readRPCFrame(client), handshake.opcode == 0,
                  writeRPCFrame(client, object: ["evt": "READY"]),
                  let command = readRPCFrame(client), command.opcode == 1 else { return }
            // Deliberately leave the socket open without acknowledging SET_ACTIVITY.
            _ = releaseClient.wait(timeout: .now() + 4)
        }

        let rpc = DiscordRPC(
            clientID: "test-client", requiresAcknowledgement: true, socketPaths: [path]
        )
        let activity = PresenceActivity(
            name: "YouTube Music", details: "Test Song", state: "Test Artist",
            start: nil, end: nil, largeImage: nil, largeImageText: nil,
            smallImage: nil, smallImageText: nil, statusDisplayType: .details
        )
        let unconfirmed = expectation(description: "unacknowledged send was rejected")
        rpc.setActivity(activity) { accepted in
            XCTAssertFalse(accepted)
            unconfirmed.fulfill()
        }
        await fulfillment(of: [unconfirmed], timeout: 5)
        releaseClient.signal()
        await fulfillment(of: [serverDone], timeout: 5)
    }

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

        XCTAssertNil(encodedActivity["status_display_type"])
        XCTAssertEqual(assets["large_url"] as? String, songURL.absoluteString)
        XCTAssertEqual(buttons.count, 1)
        XCTAssertEqual(buttons.first?["label"] as? String, "Listen on YouTube Music")
        XCTAssertEqual(buttons.first?["url"] as? String, songURL.absoluteString)
    }

    func testListeningActivityShowsItsDetailsInTheMemberList() throws {
        let activity = PresenceActivity(
            name: "YouTube Music",
            details: "Test Song",
            state: "Test Artist",
            start: Date(timeIntervalSince1970: 1_000),
            end: Date(timeIntervalSince1970: 1_180),
            largeImage: "youtube-music",
            largeImageText: "Test Album",
            smallImage: nil,
            smallImageText: nil,
            statusDisplayType: .details
        )
        let data = try XCTUnwrap(DiscordRPC.encodedSetActivityCommand(activity))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let args = try XCTUnwrap(object["args"] as? [String: Any])
        let payload = try XCTUnwrap(args["activity"] as? [String: Any])
        XCTAssertEqual(payload["type"] as? Int, 2)
        XCTAssertEqual(payload["name"] as? String, "YouTube Music")
        XCTAssertEqual(payload["status_display_type"] as? Int, 2)
        XCTAssertEqual(payload["details"] as? String, "Test Song")
        XCTAssertEqual(payload["state"] as? String, "Test Artist")
        let timestamps = try XCTUnwrap(payload["timestamps"] as? [String: Any])
        XCTAssertEqual(timestamps["start"] as? Int, 1_000)
        XCTAssertEqual(timestamps["end"] as? Int, 1_180)
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

private final class CapturedRPCCommands: @unchecked Sendable {
    private let lock = NSLock()
    private var commands: [[String: Any]] = []

    func append(_ command: [String: Any]) {
        lock.withLock { commands.append(command) }
    }

    var all: [[String: Any]] { lock.withLock { commands } }
}

private func makeRPCListener() throws -> (Int32, String) {
    let path = "/tmp/ytm-rpc-\(UUID().uuidString.prefix(8)).sock"
    let listener = socket(AF_UNIX, SOCK_STREAM, 0)
    guard listener >= 0 else { throw POSIXError(.EIO) }

    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let pathBytes = Array(path.utf8)
    guard pathBytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
        Darwin.close(listener)
        throw POSIXError(.ENAMETOOLONG)
    }
    withUnsafeMutablePointer(to: &address.sun_path) { pointer in
        pointer.withMemoryRebound(to: CChar.self, capacity: pathBytes.count + 1) { bytes in
            for (index, byte) in pathBytes.enumerated() {
                bytes[index] = CChar(bitPattern: byte)
            }
            bytes[pathBytes.count] = 0
        }
    }
    let bound = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
            Darwin.bind(listener, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    guard bound == 0, Darwin.listen(listener, 1) == 0 else {
        let code = errno
        Darwin.close(listener)
        unlink(path)
        throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
    }
    return (listener, path)
}

private func readRPCFrame(_ descriptor: Int32) -> (opcode: UInt32, body: Data)? {
    func readBytes(_ count: Int) -> Data? {
        var buffer = [UInt8](repeating: 0, count: count)
        var offset = 0
        while offset < count {
            let amount = buffer.withUnsafeMutableBytes { bytes -> Int in
                guard let base = bytes.baseAddress else { return -1 }
                return Darwin.read(descriptor, base + offset, count - offset)
            }
            guard amount > 0 else { return nil }
            offset += amount
        }
        return Data(buffer)
    }

    guard let header = readBytes(8) else { return nil }
    let opcode = header.withUnsafeBytes {
        UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: 0, as: UInt32.self))
    }
    let length = header.withUnsafeBytes {
        UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self))
    }
    guard length < 100_000, let body = readBytes(Int(length)) else { return nil }
    return (opcode, body)
}

private func writeRPCFrame(_ descriptor: Int32, object: [String: Any]) -> Bool {
    guard let body = try? JSONSerialization.data(withJSONObject: object) else { return false }
    var packet = Data()
    var opcode = UInt32(1).littleEndian
    var length = UInt32(body.count).littleEndian
    withUnsafeBytes(of: &opcode) { packet.append(contentsOf: $0) }
    withUnsafeBytes(of: &length) { packet.append(contentsOf: $0) }
    packet.append(body)
    return packet.withUnsafeBytes { bytes in
        guard let base = bytes.baseAddress else { return false }
        var offset = 0
        while offset < bytes.count {
            let amount = Darwin.write(descriptor, base + offset, bytes.count - offset)
            guard amount > 0 else { return false }
            offset += amount
        }
        return true
    }
}
