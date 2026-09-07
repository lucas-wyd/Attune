import AppKit
import Foundation
import Testing
@testable import Attune

@Suite("Command-Q persistence barrier")
@MainActor
struct AppDelegateQuitBarrierTests {
    private let sessionID = UUID(uuidString: "12121212-3434-5656-7878-909090909090")!

    @Test("Idle Quit terminates immediately without opening a flow")
    func idleQuitTerminatesImmediately() {
        let barrier = QuitPersistenceBarrier()
        var beganStop = false
        var openedFlow = false
        var replies: [Bool] = []

        let result = barrier.requestOrdinaryQuit(
            snapshot: .idle,
            beginStop: { beganStop = true },
            openFlow: { openedFlow = true },
            reply: { replies.append($0) }
        )

        #expect(result == .terminateNow)
        #expect(!beganStop)
        #expect(!openedFlow)
        #expect(replies.isEmpty)
        #expect(barrier.pendingSessionID == nil)
    }

    @Test("Active repeated Quit reuses one token and one shared stop flow")
    func repeatedQuitReusesPendingToken() {
        let barrier = QuitPersistenceBarrier()
        var stopCount = 0
        var openCount = 0
        var firstReplies: [Bool] = []
        var secondReplies: [Bool] = []
        let snapshot = QuitSessionSnapshot.active(
            sessionID: sessionID,
            hasStopChallenge: false
        )

        let first = barrier.requestOrdinaryQuit(
            snapshot: snapshot,
            beginStop: { stopCount += 1 },
            openFlow: { openCount += 1 },
            reply: { firstReplies.append($0) }
        )
        let second = barrier.requestOrdinaryQuit(
            snapshot: snapshot,
            beginStop: { stopCount += 1 },
            openFlow: { openCount += 1 },
            reply: { secondReplies.append($0) }
        )

        #expect(first == .terminateLater)
        #expect(second == .terminateLater)
        #expect(stopCount == 1)
        #expect(openCount == 1)
        #expect(barrier.pendingSessionID == sessionID)
        #expect(firstReplies.isEmpty)
        #expect(secondReplies.isEmpty)
    }

    @Test("Commit success allows termination exactly once")
    func committedOutcomeRepliesOnce() {
        var replies: [Bool] = []
        let barrier = makePendingBarrier {
            replies.append($0)
        }

        barrier.update(.active(sessionID: sessionID, hasStopChallenge: true))
        barrier.update(.terminal(sessionID: sessionID, persistence: .committing))
        barrier.update(.terminal(sessionID: sessionID, persistence: .committed))
        barrier.update(.terminal(sessionID: sessionID, persistence: .committed))

        #expect(replies == [true])
        #expect(barrier.pendingSessionID == nil)
    }

    @Test("Keep Focusing and Stay Open each cancel once")
    func cancellationRepliesOnce() {
        var keepFocusingReplies: [Bool] = []
        let keepFocusingBarrier = makePendingBarrier {
            keepFocusingReplies.append($0)
        }
        keepFocusingBarrier.update(.active(
            sessionID: sessionID,
            hasStopChallenge: true
        ))
        keepFocusingBarrier.update(.active(
            sessionID: sessionID,
            hasStopChallenge: false
        ))
        keepFocusingBarrier.cancel()

        var stayOpenReplies: [Bool] = []
        let stayOpenBarrier = makePendingBarrier {
            stayOpenReplies.append($0)
        }
        stayOpenBarrier.update(.terminal(sessionID: sessionID, persistence: .failed))
        stayOpenBarrier.cancel()
        stayOpenBarrier.cancel()

        #expect(keepFocusingReplies == [false])
        #expect(stayOpenReplies == [false])
    }

    @Test("Persistence failure and retry retain the token until commit")
    func retryRetainsToken() {
        var replies: [Bool] = []
        let barrier = makePendingBarrier {
            replies.append($0)
        }

        barrier.update(.terminal(sessionID: sessionID, persistence: .failed))
        #expect(barrier.pendingSessionID == sessionID)
        #expect(replies.isEmpty)

        barrier.update(.terminal(sessionID: sessionID, persistence: .committing))
        #expect(barrier.pendingSessionID == sessionID)
        #expect(replies.isEmpty)

        barrier.update(.terminal(sessionID: sessionID, persistence: .committed))
        #expect(replies == [true])
    }

    @Test("Logout or shutdown releases an ordinary-Quit barrier immediately")
    func systemTerminationIsBestEffort() {
        var replies: [Bool] = []
        let barrier = makePendingBarrier {
            replies.append($0)
        }

        barrier.allowSystemTermination()
        barrier.allowSystemTermination()

        #expect(replies == [true])
        #expect(barrier.pendingSessionID == nil)
    }

    @Test("A committed completion needs no barrier")
    func committedCompletionTerminatesImmediately() {
        let barrier = QuitPersistenceBarrier()
        var replies: [Bool] = []

        let result = barrier.requestOrdinaryQuit(
            snapshot: .terminal(sessionID: sessionID, persistence: .committed),
            beginStop: {},
            openFlow: {},
            reply: { replies.append($0) }
        )

        #expect(result == .terminateNow)
        #expect(replies.isEmpty)
    }

    private func makePendingBarrier(
        reply: @escaping @MainActor (Bool) -> Void
    ) -> QuitPersistenceBarrier {
        let barrier = QuitPersistenceBarrier()
        _ = barrier.requestOrdinaryQuit(
            snapshot: .active(sessionID: sessionID, hasStopChallenge: false),
            beginStop: {},
            openFlow: {},
            reply: reply
        )
        return barrier
    }
}
