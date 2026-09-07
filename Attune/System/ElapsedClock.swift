import Foundation

protocol ElapsedClock: Sendable {
    func now() -> Duration
    func sleep(for duration: Duration) async throws
}

struct LiveElapsedClock: ElapsedClock {
    private let clock: SuspendingClock
    private let origin: SuspendingClock.Instant

    init() {
        let clock = SuspendingClock()
        self.clock = clock
        origin = clock.now
    }

    func now() -> Duration {
        origin.duration(to: clock.now)
    }

    func sleep(for duration: Duration) async throws {
        guard duration > .zero else {
            return
        }
        try await clock.sleep(for: duration)
    }
}

/// A manually advanced suspending clock for deterministic coordinator tests.
final class TestElapsedClock: ElapsedClock, @unchecked Sendable {
    private struct Waiter {
        let deadline: Duration
        let continuation: CheckedContinuation<Void, any Error>
    }

    private let lock = NSLock()
    private var currentTime: Duration
    private var waiters: [UUID: Waiter] = [:]
    private var cancelledWaiters: Set<UUID> = []

    init(now: Duration = .zero) {
        currentTime = now
    }

    func now() -> Duration {
        lock.withLock { currentTime }
    }

    func sleep(for duration: Duration) async throws {
        try Task.checkCancellation()
        guard duration > .zero else {
            return
        }

        let waiterID = UUID()
        let deadline = now() + duration
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let immediateResult: Result<Void, any Error>? = lock.withLock {
                    if cancelledWaiters.remove(waiterID) != nil || Task.isCancelled {
                        return .failure(CancellationError())
                    }
                    if deadline <= currentTime {
                        return .success(())
                    }
                    waiters[waiterID] = Waiter(
                        deadline: deadline,
                        continuation: continuation
                    )
                    return nil
                }

                if let immediateResult {
                    continuation.resume(with: immediateResult)
                }
            }
        } onCancel: {
            let continuation: CheckedContinuation<Void, any Error>? = self.lock.withLock {
                if let waiter = self.waiters.removeValue(forKey: waiterID) {
                    return waiter.continuation
                }
                self.cancelledWaiters.insert(waiterID)
                return nil
            }
            continuation?.resume(throwing: CancellationError())
        }
    }

    func advance(by duration: Duration) {
        precondition(duration >= .zero, "Elapsed test time cannot move backward")
        let readyWaiters: [Waiter] = lock.withLock {
            currentTime += duration
            let readyIDs = waiters.compactMap { key, waiter in
                waiter.deadline <= currentTime ? key : nil
            }
            return readyIDs.compactMap { waiters.removeValue(forKey: $0) }
        }
        readyWaiters.forEach { $0.continuation.resume() }
    }
}
