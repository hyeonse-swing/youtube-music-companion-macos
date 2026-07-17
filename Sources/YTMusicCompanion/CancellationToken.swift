import Foundation

/// Cooperative cancellation shared by Swift tasks and the blocking child processes
/// they launch. `Task.cancel()` alone cannot interrupt `readDataToEndOfFile()`, so
/// subprocess users register a handler that terminates the current process.
final class CancellationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var handlers: [UUID: @Sendable () -> Void] = [:]

    var isCancelled: Bool {
        lock.withLock { cancelled }
    }

    @discardableResult
    func register(_ handler: @escaping @Sendable () -> Void) -> CancellationRegistration {
        let id = UUID()
        let shouldCancelImmediately = lock.withLock { () -> Bool in
            guard !cancelled else { return true }
            handlers[id] = handler
            return false
        }
        if shouldCancelImmediately { handler() }
        return CancellationRegistration(token: self, id: id)
    }

    func cancel() {
        let pending = lock.withLock { () -> [@Sendable () -> Void] in
            guard !cancelled else { return [] }
            cancelled = true
            let pending = Array(handlers.values)
            handlers.removeAll()
            return pending
        }
        pending.forEach { $0() }
    }

    fileprivate func unregister(_ id: UUID) {
        _ = lock.withLock { handlers.removeValue(forKey: id) }
    }
}

final class CancellationRegistration: @unchecked Sendable {
    private let lock = NSLock()
    private weak var token: CancellationToken?
    private var id: UUID?

    fileprivate init(token: CancellationToken, id: UUID) {
        self.token = token
        self.id = id
    }

    func invalidate() {
        let registration = lock.withLock { () -> (CancellationToken, UUID)? in
            guard let token, let id else { return nil }
            self.token = nil
            self.id = nil
            return (token, id)
        }
        if let registration {
            registration.0.unregister(registration.1)
        }
    }

    deinit {
        invalidate()
    }
}

/// One keyed background operation owned by a higher-level component.
///
/// The owner installs this object before attaching the task. That ordering avoids
/// a very fast stub or cache hit completing before the owner can record its ID.
final class CancellableTaskOperation: @unchecked Sendable {
    let id: UUID
    let key: String
    let cancellation: CancellationToken
    private let lock = NSLock()
    private var task: Task<Void, Never>?

    init(id: UUID = UUID(), key: String, cancellation: CancellationToken) {
        self.id = id
        self.key = key
        self.cancellation = cancellation
    }

    func attach(_ task: Task<Void, Never>) {
        let shouldCancel = lock.withLock { () -> Bool in
            self.task = task
            return cancellation.isCancelled
        }
        if shouldCancel { task.cancel() }
    }

    func cancel() {
        cancellation.cancel()
        lock.withLock { task }?.cancel()
    }
}
