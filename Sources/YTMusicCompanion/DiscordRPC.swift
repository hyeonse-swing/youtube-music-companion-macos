import Foundation

// IPC framing approach adapted from SwordRPC by Alejandro Alonso (MIT).

struct PresenceButton: Equatable {
    let label: String
    let url: URL
}

struct PresenceActivity: Equatable {
    var name: String
    var details: String
    var state: String
    var start: Date?
    var end: Date?
    var largeImage: String?
    var largeImageText: String?
    var smallImage: String?
    var smallImageText: String?
    var detailsURL: URL? = nil
    var stateURL: URL? = nil
    var largeImageURL: URL? = nil
    var smallImageURL: URL? = nil
    var buttons: [PresenceButton] = []
    var statusDisplayType: DiscordStatusDisplayType = .name
}

protocol PresencePublishing: AnyObject {
    var isConfigured: Bool { get }
    var connectionStatus: DiscordConnectionStatus { get }
    func setConnectionStatusHandler(
        _ handler: (@Sendable (DiscordConnectionStatus) -> Void)?
    )
    func setActivity(_ activity: PresenceActivity, completion: ((Bool) -> Void)?)
    func clear()
    func disconnect()
}

extension PresencePublishing {
    var connectionStatus: DiscordConnectionStatus {
        isConfigured ? .disconnected : .notConfigured
    }

    func setConnectionStatusHandler(
        _ handler: (@Sendable (DiscordConnectionStatus) -> Void)?
    ) {}
}

/// A dependency-free Discord Rich Presence client over Discord's local IPC.
///
/// Discord exposes a Unix domain socket at `$TMPDIR/discord-ipc-N` (N = 0..9) when
/// the desktop app is running. We speak its framed JSON protocol directly with raw
/// POSIX sockets — no OAuth, no client secret, no third-party socket library.
///
/// Frame format (one contiguous write each):
///   [UInt32 LE opcode][UInt32 LE length][UTF-8 JSON body]
/// Opcodes: 0 = HANDSHAKE, 1 = FRAME, 2 = CLOSE, 3 = PING, 4 = PONG.
///
/// All socket I/O runs on a private serial queue, so this type is safe to drive
/// from the main thread (PlayerModel) without blocking it. It degrades gracefully:
/// if Discord isn't running there's simply no socket to connect to and every call
/// is a quiet no-op until the next attempt.
final class DiscordRPC: PresencePublishing {
    private let clientID: String?
    private let requiresAcknowledgement: Bool
    private let socketPathsOverride: [String]?

    /// Activity type 2 makes Discord render this as a listening activity.
    /// (0 = Playing, 1 = Streaming, 2 = Listening, 3 = Watching.)
    private static let listeningType = 2

    private enum Opcode: UInt32 {
        case handshake = 0
        case frame = 1
        case close = 2
        case ping = 3
        case pong = 4
    }

    // All socket access is confined to this serial queue. fd is only touched here.
    private let queue = DispatchQueue(label: "DiscordRPC.ipc")
    private let statusLock = NSLock()
    private var fd: Int32 = -1
    private var isConnected = false
    private var statusDisplayTypeRejected = false
    private var storedConnectionStatus: DiscordConnectionStatus
    private var connectionStatusHandler: (@Sendable (DiscordConnectionStatus) -> Void)?

    var isConfigured: Bool { clientID != nil }
    var connectionStatus: DiscordConnectionStatus {
        statusLock.withLock { storedConnectionStatus }
    }

    init(
        clientID: String?,
        requiresAcknowledgement: Bool = false,
        socketPaths: [String]? = nil
    ) {
        self.clientID = clientID
        self.requiresAcknowledgement = requiresAcknowledgement
        socketPathsOverride = socketPaths
        storedConnectionStatus = clientID == nil ? .notConfigured : .disconnected
    }

    func setConnectionStatusHandler(
        _ handler: (@Sendable (DiscordConnectionStatus) -> Void)?
    ) {
        let current = statusLock.withLock { () -> DiscordConnectionStatus in
            connectionStatusHandler = handler
            return storedConnectionStatus
        }
        handler?(current)
    }

    // MARK: - Public API

    /// Discover the socket, connect, handshake and await READY. Idempotent and safe
    /// to call when Discord isn't running (it simply stays disconnected). Async work;
    /// the optional completion reports the outcome (used by the `--discord` probe).
    func connect(completion: ((_ socketFound: Bool, _ ready: Bool) -> Void)? = nil) {
        queue.async {
            if self.isConnected {
                self.updateConnectionStatusLocked(.connected)
                completion?(true, true)
                return
            }
            self.updateConnectionStatusLocked(.connecting)
            let (found, ready) = self.connectLocked()
            self.updateConnectionStatusLocked(ready ? .connected : (found ? .retrying : .disconnected))
            completion?(found, ready)
        }
    }

    /// Send a SET_ACTIVITY frame, auto-connecting first if needed. A no-op (without
    /// error) when Discord isn't reachable.
    func setActivity(_ activity: PresenceActivity, completion: ((Bool) -> Void)? = nil) {
        queue.async {
            if !self.isConnected {
                self.updateConnectionStatusLocked(.connecting)
                let (found, ready) = self.connectLocked()
                guard ready else {
                    self.updateConnectionStatusLocked(found ? .retrying : .disconnected)
                    completion?(false)
                    return
                }
                self.updateConnectionStatusLocked(.connected)
            }
            self.updateConnectionStatusLocked(.publishing)
            let ok = self.sendActivityLocked(activity)
            self.updateConnectionStatusLocked(ok ? .published : .retrying)
            completion?(ok)
        }
    }

    /// Clear the presence (send `activity: null`). No-op when not connected.
    func clear() {
        clear(completion: nil)
    }

    /// Reports whether the clear command was accepted by the connected client.
    /// Used by the one-shot Discord probe to confirm its test activity was removed.
    func clear(completion: ((Bool) -> Void)?) {
        queue.async {
            guard self.isConnected else {
                completion?(false)
                return
            }
            let cleared = self.sendActivityLocked(nil)
            self.updateConnectionStatusLocked(cleared ? .connected : .retrying)
            completion?(cleared)
        }
    }

    /// Close the socket and mark disconnected.
    func disconnect() {
        queue.async {
            self.disconnectLocked()
            self.updateConnectionStatusLocked(
                self.clientID == nil ? .notConfigured : .disconnected
            )
        }
    }

    // MARK: - Codable activity model (snake_case wire keys)

    private struct ActivityPayload: Encodable {
        let type: Int
        let name: String
        let statusDisplayType: Int?
        let details: String
        let state: String
        let detailsURL: String?
        let stateURL: String?
        let timestamps: Timestamps?
        // Built whenever ANY asset field is set (so a track with no cover
        // still ships its source badge); omitted entirely only when all are nil. Each
        // wire key is itself optional and drops out of the JSON when nil.
        let assets: Assets?
        let buttons: [Button]?

        enum CodingKeys: String, CodingKey {
            case type
            case name
            case statusDisplayType = "status_display_type"
            case details
            case state
            case detailsURL = "details_url"
            case stateURL = "state_url"
            case timestamps
            case assets
            case buttons
        }

        struct Timestamps: Encodable {
            // Unix epoch SECONDS. Omitted keys (nil) drop out of the JSON.
            let start: Int?
            let end: Int?
        }

        struct Assets: Encodable {
            // `large_image` accepts an external https URL OR a pre-uploaded asset key;
            // `small_image` is always an asset key. The `*_text` fields are hover
            // labels. snake_case is the Discord wire format; nil keys drop out.
            let largeImage: String?
            let largeText: String?
            let smallImage: String?
            let smallText: String?
            let largeURL: String?
            let smallURL: String?
            enum CodingKeys: String, CodingKey {
                case largeImage = "large_image"
                case largeText = "large_text"
                case smallImage = "small_image"
                case smallText = "small_text"
                case largeURL = "large_url"
                case smallURL = "small_url"
            }
        }

        struct Button: Encodable {
            let label: String
            let url: String
        }
    }

    private struct SetActivityArgs: Encodable {
        let pid: Int32
        // A clear must send an explicit null; synthesized Optional encoding
        // would omit the key entirely.
        let activity: ActivityPayload?

        enum CodingKeys: String, CodingKey {
            case pid, activity
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(pid, forKey: .pid)
            if let activity {
                try container.encode(activity, forKey: .activity)
            } else {
                try container.encodeNil(forKey: .activity)
            }
        }
    }

    private struct SetActivityCommand: Encodable {
        let cmd: String
        let args: SetActivityArgs
        let nonce: String

        enum CodingKeys: String, CodingKey {
            case cmd, args, nonce
        }
    }

    private struct Handshake: Encodable {
        let v: Int
        let clientID: String
        enum CodingKeys: String, CodingKey {
            case v
            case clientID = "client_id"
        }
    }

    // MARK: - Connection (all on `queue`)

    /// Returns (socketFound, ready). Leaves `isConnected`/`fd` set on success.
    private func connectLocked() -> (Bool, Bool) {
        guard let clientID else { return (false, false) }
        var socketFound = false
        for path in socketPathsOverride ?? Self.socketPaths()
        where FileManager.default.fileExists(atPath: path) {
            socketFound = true
            if connectLocked(path: path, clientID: clientID) {
                return (true, true)
            }
        }
        return (socketFound, false)
    }

    /// Tries one candidate. A stale `discord-ipc-0` must not prevent a healthy
    /// `discord-ipc-1` from being discovered.
    private func connectLocked(path: String, clientID: String) -> Bool {
        let sock = socket(AF_UNIX, SOCK_STREAM, 0)
        guard sock >= 0 else { return false }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        // Copy the path into the fixed sun_path buffer. macOS sun_path is 104 bytes,
        // comfortably larger than "$TMPDIR/discord-ipc-9".
        let pathBytes = Array(path.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: addr.sun_path) else {
            close(sock)
            return false
        }
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            // Capacity is pathBytes.count + 1 so the trailing NUL write at index
            // pathBytes.count stays within the rebound buffer (the guard above already
            // ensured count < sun_path size, so +1 still fits).
            ptr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count + 1) { dst in
                for (i, b) in pathBytes.enumerated() { dst[i] = CChar(bitPattern: b) }
                dst[pathBytes.count] = 0
            }
        }

        let connectResult = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                // Darwin.connect: our own connect() method shadows the global here.
                Darwin.connect(sock, sa, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectResult == 0 else {
            close(sock)
            return false
        }

        // macOS can otherwise deliver SIGPIPE when Discord closes the peer between
        // our liveness check and write(), terminating the whole companion process.
        var noSignal: Int32 = 1
        setsockopt(
            sock,
            SOL_SOCKET,
            SO_NOSIGPIPE,
            &noSignal,
            socklen_t(MemoryLayout<Int32>.size)
        )

        fd = sock
        isConnected = true

        // Bound every blocking read with a receive timeout so a quiet-but-live socket
        // can never hang the serial queue forever. If Discord accepts a SET_ACTIVITY
        // but sends no reply, the post-send drain read would otherwise block the queue
        // indefinitely. On Darwin SO_RCVTIMEO takes a `timeval`; a timed-out read
        // returns -1 with errno EAGAIN/EWOULDBLOCK, which the read path treats as a
        // (healthy) timeout rather than EOF.
        var tv = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        // Handshake: opcode 0 with {"v":1,"client_id":...}. Discord answers with a
        // FRAME whose evt == "READY".
        guard let body = try? JSONEncoder().encode(Handshake(v: 1, clientID: clientID)),
              writeFrame(.handshake, body) else {
            disconnectLocked()
            return false
        }

        // Await READY. A timeout or a closed/error socket here is a handshake failure
        // (we have nothing usable), so disconnect and report not-ready.
        guard case .frame(_, let replyBody) = readFrame() else {
            disconnectLocked()
            return false
        }
        let parsed = (try? JSONSerialization.jsonObject(with: replyBody)) as? [String: Any]
        let ready = (parsed?["evt"] as? String) == "READY"
        if !ready {
            disconnectLocked()
            return false
        }
        statusDisplayTypeRejected = false
        return true
    }

    private func disconnectLocked() {
        if fd >= 0 { close(fd) }
        fd = -1
        isConnected = false
    }

    /// Candidate socket paths discord-ipc-0 .. discord-ipc-9 in $TMPDIR (falling
    /// back to /tmp). First that exists/connects wins.
    private static func socketPaths() -> [String] {
        let base = ProcessInfo.processInfo.environment["TMPDIR"] ?? "/tmp/"
        let dir = base.hasSuffix("/") ? base : base + "/"
        return (0...9).map { "\(dir)discord-ipc-\($0)" }
    }

    /// Discord measures its 2..128 activity-text limits in UTF-8 BYTES, not grapheme
    /// clusters, so we clamp by byte length. Truncate by dropping whole Characters from
    /// the end until the UTF-8 byte count is <= 128 (never split a character — that
    /// would emit invalid UTF-8). Then pad a too-short value (< 2 bytes) with a trailing
    /// space so it satisfies the 2-byte minimum.
    private static func clamp(_ s: String) -> String {
        var capped: String
        if s.utf8.count <= 128 {
            capped = s
        } else {
            var byteCount = 0
            var end = s.startIndex
            while end < s.endIndex {
                let next = s.index(after: end)
                let characterByteCount = s[end..<next].utf8.count
                guard byteCount + characterByteCount <= 128 else { break }
                byteCount += characterByteCount
                end = next
            }
            capped = String(s[..<end])
        }
        while capped.utf8.count < 2 {
            capped.append(" ")
        }
        return capped
    }

    // MARK: - Activity send (on `queue`)

    static func encodedSetActivityCommand(
        _ activity: PresenceActivity?,
        pid: Int32 = ProcessInfo.processInfo.processIdentifier,
        nonce: String = UUID().uuidString
    ) -> Data? {
        let command = SetActivityCommand(
            cmd: "SET_ACTIVITY",
            args: SetActivityArgs(
                pid: pid,
                activity: activity.map(Self.activityPayload)
            ),
            nonce: nonce
        )
        return try? JSONEncoder().encode(command)
    }

    /// Build + send a SET_ACTIVITY frame. A client that rejects the newer
    /// status_display_type field gets one retry with the older activity shape.
    private func sendActivityLocked(_ activity: PresenceActivity?) -> Bool {
        let outgoing = statusDisplayTypeRejected
            ? activity.map(Self.legacyStatusActivity) : activity
        let result = sendActivityFrameLocked(outgoing)
        if result == .accepted { return true }
        guard result == .rejected,
              let activity,
              activity.statusDisplayType != .name,
              !statusDisplayTypeRejected,
              !requiresAcknowledgement else { return false }

        let fallback = sendActivityFrameLocked(Self.legacyStatusActivity(activity))
        if fallback == .accepted {
            statusDisplayTypeRejected = true
            return true
        }
        return false
    }

    private static func legacyStatusActivity(_ activity: PresenceActivity) -> PresenceActivity {
        var fallback = activity
        switch activity.statusDisplayType {
        case .name: break
        case .details: fallback.name = activity.details
        case .state: fallback.name = activity.state
        }
        fallback.statusDisplayType = .name
        return fallback
    }

    private enum ActivitySendResult {
        case accepted
        case rejected
        case unconfirmed
        case disconnected
    }

    private func sendActivityFrameLocked(_ activity: PresenceActivity?) -> ActivitySendResult {
        let nonce = UUID().uuidString
        guard
            let body = Self.encodedSetActivityCommand(activity, nonce: nonce),
            writeFrame(.frame, body)
        else {
            disconnectLocked()
            updateConnectionStatusLocked(.retrying)
            return .disconnected
        }
        return servicePendingFrame(expectedNonce: nonce)
    }

    private static func activityPayload(from activity: PresenceActivity) -> ActivityPayload {
        // TIMESTAMP UNIT: Discord's LOCAL IPC SET_ACTIVITY takes Unix epoch
        // SECONDS (the Gateway/REST API uses milliseconds — different transport).
        let start = activity.start.map { Int($0.timeIntervalSince1970) }
        let end = activity.end.map { Int($0.timeIntervalSince1970) }
        let timestamps = (start != nil || end != nil)
            ? ActivityPayload.Timestamps(start: start, end: end) : nil

        let hasAnyAsset = activity.largeImage != nil || activity.largeImageText != nil
            || activity.smallImage != nil || activity.smallImageText != nil
            || activity.largeImageURL != nil
            || activity.smallImageURL != nil
        let assets = hasAnyAsset
            ? ActivityPayload.Assets(
                largeImage: activity.largeImage,
                largeText: activity.largeImageText.map(Self.clamp),
                smallImage: activity.smallImage,
                smallText: activity.smallImageText.map(Self.clamp),
                largeURL: validatedHTTPSURLString(activity.largeImageURL),
                smallURL: validatedHTTPSURLString(activity.smallImageURL)
            )
            : nil

        return ActivityPayload(
            type: Self.listeningType,
            name: Self.clamp(activity.name),
            statusDisplayType: activity.statusDisplayType == .name ? nil : activity.statusDisplayType.rawValue,
            details: Self.clamp(activity.details),
            state: Self.clamp(activity.state),
            detailsURL: validatedHTTPSURLString(activity.detailsURL),
            stateURL: validatedHTTPSURLString(activity.stateURL),
            timestamps: timestamps,
            assets: assets,
            buttons: Self.buttonPayloads(from: activity.buttons)
        )
    }

    private static func validatedHTTPSURLString(_ url: URL?) -> String? {
        guard let url,
              url.scheme?.lowercased() == "https",
              url.host?.isEmpty == false,
              url.absoluteString.utf8.count <= 512
        else {
            return nil
        }
        return url.absoluteString
    }

    private static func buttonPayloads(
        from buttons: [PresenceButton]
    ) -> [ActivityPayload.Button]? {
        let payloads = buttons.prefix(2).compactMap { button -> ActivityPayload.Button? in
            guard let url = validatedHTTPSURLString(button.url) else { return nil }
            let label = button.label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !label.isEmpty else { return nil }
            return ActivityPayload.Button(
                label: String(label.prefix(32)),
                url: url
            )
        }
        return payloads.isEmpty ? nil : payloads
    }

    /// Discord may acknowledge a command with evt: ERROR. Treat that as a failed
    /// publication, and skip unrelated frames while waiting for this command's nonce.
    /// Normal playback accepts a timeout because some clients send no ACK. The
    /// explicit probe requires a matching ACK before claiming publication or clear.
    private func servicePendingFrame(expectedNonce: String) -> ActivitySendResult {
        for _ in 0..<8 {
            switch readFrame() {
            case .timedOut:
                return requiresAcknowledgement ? .unconfirmed : .accepted
            case .closed:
                disconnectLocked()
                updateConnectionStatusLocked(.retrying)
                return .disconnected
            case .frame(.ping, let body):
                guard writeFrame(.pong, body) else {
                    disconnectLocked()
                    updateConnectionStatusLocked(.retrying)
                    return .disconnected
                }
            case .frame(.close, _):
                disconnectLocked()
                updateConnectionStatusLocked(.retrying)
                return .disconnected
            case .frame(.frame, let body):
                guard let reply = Self.activityReply(body, expectedNonce: expectedNonce) else {
                    continue
                }
                return reply
            case .frame(.handshake, _), .frame(.pong, _):
                continue
            }
        }
        return requiresAcknowledgement ? .unconfirmed : .accepted
    }

    private static func activityReply(
        _ body: Data,
        expectedNonce: String
    ) -> ActivitySendResult? {
        guard let reply = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
              reply["nonce"] as? String == expectedNonce else { return nil }
        return reply["evt"] as? String == "ERROR" ? .rejected : .accepted
    }

    // MARK: - Framing (on `queue`)

    /// Write one frame: [opcode LE][length LE][body], contiguous. Endianness explicit.
    private func writeFrame(_ op: Opcode, _ body: Data) -> Bool {
        var packet = Data(capacity: 8 + body.count)
        var opLE = op.rawValue.littleEndian
        var lenLE = UInt32(body.count).littleEndian
        withUnsafeBytes(of: &opLE) { packet.append(contentsOf: $0) }
        withUnsafeBytes(of: &lenLE) { packet.append(contentsOf: $0) }
        packet.append(body)
        return writeAll(packet)
    }

    /// Result of a single bounded read: a full payload, a (healthy) receive timeout on
    /// a quiet socket, or a closed/errored socket. Distinguishing timeout from EOF lets
    /// the post-send drain stay connected on a quiet socket while still tearing down a
    /// genuinely dead one.
    private enum ReadOutcome {
        case ok(Data)
        case timedOut
        case closed
    }

    /// A decoded frame, a timeout, or a closed/errored socket. Mirrors `ReadOutcome`
    /// but carries the decoded opcode + body on success.
    private enum FrameOutcome {
        case frame(Opcode, Data)
        case timedOut
        case closed
    }

    /// Read one frame, looping until the full 8-byte header then the full body are
    /// consumed (a stream socket can short-read). Propagates timeout vs. closed/error.
    private func readFrame() -> FrameOutcome {
        switch readExactly(8) {
        case .timedOut: return .timedOut
        case .closed: return .closed
        case .ok(let header):
            let opRaw = header.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: 0, as: UInt32.self)) }
            let length = header.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self)) }
            guard let op = Opcode(rawValue: opRaw) else { return .closed }
            // Reject absurd frame lengths from an untrusted/desynced peer: Discord IPC
            // frames are tiny, so anything over 1 MB means we've lost framing. Treat as
            // a protocol error (caller disconnects) rather than allocating Int(length).
            guard length <= 1_000_000 else { return .closed }
            if length == 0 { return .frame(op, Data()) }
            switch readExactly(Int(length)) {
            // The header has already been consumed. Even a zero-byte body timeout
            // leaves the stream midway through a frame, so reconnect.
            case .timedOut: return .closed
            case .closed: return .closed
            case .ok(let body): return .frame(op, body)
            }
        }
    }

    /// Write every byte, looping over short writes. nil/error → false.
    private func writeAll(_ data: Data) -> Bool {
        guard fd >= 0 else { return false }
        return data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Bool in
            guard let base = raw.baseAddress else { return false }
            var offset = 0
            let total = raw.count
            while offset < total {
                let n = write(fd, base + offset, total - offset)
                if n < 0 && errno == EINTR { continue }
                if n <= 0 { return false }   // error or closed
                offset += n
            }
            return true
        }
    }

    /// Read exactly `count` bytes, looping over short reads. Distinguishes a receive
    /// timeout (read() < 0 with errno EAGAIN/EWOULDBLOCK, from SO_RCVTIMEO) from EOF
    /// (read() == 0, peer closed) and other errors.
    private func readExactly(_ count: Int) -> ReadOutcome {
        guard fd >= 0 else { return .closed }
        guard count > 0 else { return .ok(Data()) }
        var buffer = [UInt8](repeating: 0, count: count)
        var offset = 0
        while offset < count {
            let n = buffer.withUnsafeMutableBytes { raw -> Int in
                guard let base = raw.baseAddress else { return -1 }
                return read(fd, base + offset, count - offset)
            }
            if n > 0 {
                offset += n
                continue
            }
            if n < 0 && errno == EINTR {
                continue
            }
            if n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) {
                // A timeout before reading anything is a quiet socket. Timing out
                // midway through a frame loses byte alignment, so force reconnect.
                return offset == 0 ? .timedOut : .closed
            }
            return .closed         // 0 = EOF (peer closed), <0 = error
        }
        return .ok(Data(buffer))
    }

    private func updateConnectionStatusLocked(_ status: DiscordConnectionStatus) {
        let handler: (@Sendable (DiscordConnectionStatus) -> Void)? = statusLock.withLock {
            guard storedConnectionStatus != status else { return nil }
            storedConnectionStatus = status
            return connectionStatusHandler
        }
        handler?(status)
    }
}
