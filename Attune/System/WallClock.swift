import Foundation

protocol WallClock: Sendable {
    func now() -> Date
    func sleep(until deadline: Date) async throws
}

struct LiveWallClock: WallClock {
    private let clock = ContinuousClock()

    func now() -> Date {
        Date()
    }

    func sleep(until deadline: Date) async throws {
        let interval = deadline.timeIntervalSince(now())
        guard interval > 0 else {
            return
        }
        try await clock.sleep(for: .attuneSeconds(interval))
    }
}

/// A manually advanced wall clock for deterministic coordinator tests.
final class TestWallClock: WallClock, @unchecked Sendable {
    private struct Waiter {
        let deadline: Date
        let continuation: CheckedContinuation<Void, any Error>
    }

    private let lock = NSLock()
    private var currentTime: Date
    private var waiters: [UUID: Waiter] = [:]
    private var cancelledWaiters: Set<UUID> = []

    init(now: Date) {
        currentTime = now
    }

    func now() -> Date {
        lock.withLock { currentTime }
    }

    func sleep(until deadline: Date) async throws {
        try Task.checkCancellation()
        let waiterID = UUID()

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

    func setNow(_ date: Date) {
        let readyWaiters: [Waiter] = lock.withLock {
            currentTime = date
            let readyIDs = waiters.compactMap { key, waiter in
                waiter.deadline <= date ? key : nil
            }
            return readyIDs.compactMap { waiters.removeValue(forKey: $0) }
        }
        readyWaiters.forEach { $0.continuation.resume() }
    }

    func advance(by interval: TimeInterval) {
        setNow(now().addingTimeInterval(interval))
    }
}

extension Duration {
    fileprivate static func attuneSeconds(_ seconds: TimeInterval) -> Duration {
        .nanoseconds(Int64((seconds * 1_000_000_000).rounded()))
    }
}
