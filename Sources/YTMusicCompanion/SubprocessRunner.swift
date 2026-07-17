import Foundation
import OSLog

struct SubprocessMetricsSnapshot: Equatable {
    let activeCount: Int
    let totalLaunches: Int
    let cancelledCount: Int
    let timedOutCount: Int
}

private enum SubprocessMetrics {
    private static let lock = NSLock()
    private static var activeCount = 0
    private static var totalLaunches = 0
    private static var cancelledCount = 0
    private static var timedOutCount = 0

    static func didLaunch() {
        lock.withLock {
            activeCount += 1
            totalLaunches += 1
        }
    }

    static func didFinish(cancelled: Bool, timedOut: Bool) {
        lock.withLock {
            activeCount = max(0, activeCount - 1)
            if cancelled { cancelledCount += 1 }
            if timedOut { timedOutCount += 1 }
        }
    }

    static var snapshot: SubprocessMetricsSnapshot {
        lock.withLock {
            SubprocessMetricsSnapshot(
                activeCount: activeCount,
                totalLaunches: totalLaunches,
                cancelledCount: cancelledCount,
                timedOutCount: timedOutCount
            )
        }
    }
}

private final class ProcessTerminationController: @unchecked Sendable {
    private let lock = NSLock()
    private let process: Process
    private var finished = false
    private var timedOut = false

    init(process: Process) {
        self.process = process
    }

    func terminate(markingTimeout: Bool = false) {
        let shouldTerminate = lock.withLock { () -> Bool in
            guard !finished else { return false }
            if markingTimeout { timedOut = true }
            return true
        }
        guard shouldTerminate, process.isRunning else { return }
        process.terminate()
    }

    func markFinished() {
        lock.withLock { finished = true }
    }

    var didTimeOut: Bool {
        lock.withLock { timedOut }
    }
}

struct SubprocessResult {
    let output: Data
    let terminationStatus: Int32
    let wasCancelled: Bool
    let timedOut: Bool

    var succeeded: Bool {
        terminationStatus == 0 && !wasCancelled && !timedOut
    }
}

/// Runs a child process with bounded lifetime and real cancellation.
///
/// Every existing bridge reads stdout synchronously. Centralizing that pattern
/// prevents an abandoned track from leaving `curl`, `osascript`, or the artwork
/// bridge alive until its normal timeout.
enum SubprocessRunner {
    private static let logger = Logger(
        subsystem: AppConfiguration.bundleIdentifier,
        category: "Subprocess"
    )

    static var metrics: SubprocessMetricsSnapshot {
        SubprocessMetrics.snapshot
    }

    static func run(
        executable: String,
        arguments: [String],
        timeout: TimeInterval,
        cancellation: CancellationToken
    ) -> SubprocessResult? {
        guard !cancellation.isCancelled else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            logger.error("Failed to launch \(executable, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }

        SubprocessMetrics.didLaunch()
        let termination = ProcessTerminationController(process: process)
        let cancellationRegistration = cancellation.register {
            termination.terminate()
        }
        let watchdog = DispatchWorkItem {
            termination.terminate(markingTimeout: true)
        }
        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + timeout,
            execute: watchdog
        )

        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        termination.markFinished()
        watchdog.cancel()
        cancellationRegistration.invalidate()

        let wasCancelled = cancellation.isCancelled
        let timedOut = termination.didTimeOut
        SubprocessMetrics.didFinish(cancelled: wasCancelled, timedOut: timedOut)
        if wasCancelled {
            logger.debug("Cancelled \(executable, privacy: .public)")
        } else if timedOut {
            logger.warning("Timed out \(executable, privacy: .public) after \(timeout, privacy: .public)s")
        }

        return SubprocessResult(
            output: data,
            terminationStatus: process.terminationStatus,
            wasCancelled: wasCancelled,
            timedOut: timedOut
        )
    }
}
