import XCTest
@testable import YTMusicCompanion

final class CancellationTokenTests: XCTestCase {
    func testCancellationRunsEachRegisteredHandlerOnce() {
        let token = CancellationToken()
        let counter = LockedCounter()
        let registration = token.register {
            counter.increment()
        }

        token.cancel()
        token.cancel()

        withExtendedLifetime(registration) {}
        XCTAssertEqual(counter.value, 1)
        XCTAssertTrue(token.isCancelled)
    }

    func testInvalidatedRegistrationDoesNotRun() {
        let token = CancellationToken()
        let counter = LockedCounter()
        let registration = token.register {
            counter.increment()
        }

        registration.invalidate()
        token.cancel()

        XCTAssertEqual(counter.value, 0)
    }

    func testCancellingSubprocessReturnsWithoutWaitingForItsNaturalExit() {
        let token = CancellationToken()
        let finished = expectation(description: "subprocess cancelled")
        let lock = NSLock()
        var result: SubprocessResult?
        let startedAt = Date()

        DispatchQueue.global(qos: .utility).async {
            let value = SubprocessRunner.run(
                executable: "/bin/sleep",
                arguments: ["10"],
                timeout: 11,
                cancellation: token
            )
            lock.withLock { result = value }
            finished.fulfill()
        }

        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
            token.cancel()
        }
        wait(for: [finished], timeout: 2)

        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 2)
        XCTAssertTrue(lock.withLock { result?.wasCancelled ?? token.isCancelled })
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.withLock { count }
    }

    func increment() {
        lock.withLock { count += 1 }
    }
}
