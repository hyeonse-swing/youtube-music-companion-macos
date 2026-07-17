import Foundation
import OSLog
import Darwin

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
    private static let forceTerminationDelay: TimeInterval = 0.25

    private let lock = NSLock()
    private let process: Process
    private var finished = false
    private var timedOut = false
    private var outputLimitExceeded = false

    init(process: Process) {
        self.process = process
    }

    func terminate(
        markingTimeout: Bool = false,
        markingOutputLimitExceeded: Bool = false
    ) {
        let shouldTerminate = lock.withLock { () -> Bool in
            guard !finished else { return false }
            if markingTimeout { timedOut = true }
            if markingOutputLimitExceeded { outputLimitExceeded = true }
            return true
        }
        guard shouldTerminate, process.isRunning else { return }

        let processIdentifier = process.processIdentifier
        process.terminate()
        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + Self.forceTerminationDelay
        ) { [process] in
            guard process.isRunning else { return }
            Darwin.kill(processIdentifier, SIGKILL)
        }
    }

    func markFinished() {
        lock.withLock { finished = true }
    }

    var didTimeOut: Bool {
        lock.withLock { timedOut }
    }

    var didExceedOutputLimit: Bool {
        lock.withLock { outputLimitExceeded }
    }
}

struct SubprocessResult {
    let output: Data
    let terminationStatus: Int32
    let wasCancelled: Bool
    let timedOut: Bool
    let outputLimitExceeded: Bool

    var succeeded: Bool {
        terminationStatus == 0 && !wasCancelled && !timedOut && !outputLimitExceeded
    }
}

/// Runs a child process with bounded lifetime and real cancellation.
///
/// Every existing bridge reads stdout synchronously. Centralizing that pattern
/// prevents an abandoned track from leaving `curl`, `osascript`, or the artwork
/// bridge alive until its normal timeout.
enum SubprocessRunner {
    private static let defaultMaximumOutputBytes = 16 * 1_024 * 1_024
    private static let readChunkSize = 64 * 1_024

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
        maximumOutputBytes: Int = defaultMaximumOutputBytes,
        cancellation: CancellationToken
    ) -> SubprocessResult? {
        guard !cancellation.isCancelled else { return nil }
        precondition(maximumOutputBytes > 0)

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

        let data = readOutput(
            from: output.fileHandleForReading,
            maximumBytes: maximumOutputBytes,
            termination: termination
        )
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
        } else if termination.didExceedOutputLimit {
            logger.warning(
                "Stopped \(executable, privacy: .public) after stdout exceeded \(maximumOutputBytes, privacy: .public) bytes"
            )
        }

        return SubprocessResult(
            output: data,
            terminationStatus: process.terminationStatus,
            wasCancelled: wasCancelled,
            timedOut: timedOut,
            outputLimitExceeded: termination.didExceedOutputLimit
        )
    }

    private static func readOutput(
        from handle: FileHandle,
        maximumBytes: Int,
        termination: ProcessTerminationController
    ) -> Data {
        var output = Data()
        output.reserveCapacity(min(maximumBytes, readChunkSize))

        while true {
            let chunk = autoreleasepool {
                try? handle.read(upToCount: readChunkSize)
            }
            guard let chunk, !chunk.isEmpty else { break }

            let remaining = maximumBytes - output.count
            if chunk.count <= remaining {
                output.append(chunk)
                continue
            }

            if remaining > 0 {
                output.append(chunk.prefix(remaining))
            }
            termination.terminate(markingOutputLimitExceeded: true)
        }
        return output
    }
}
