import Foundation
import Testing
@testable import Attune

@Suite("Session reducer lifecycle")
struct SessionReducerCoreTests {
    private let startTime = Date(timeIntervalSince1970: 1_800_000_000)
    private let sessionID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

    @Test("Start creates a deterministic running session and ordered effects")
    func start() throws {
        let configuration = try configuration()
        let staleRuntime = SessionRuntime(
            lastAllowedBundleIdentifier: "com.example.Private",
            softAllowedBundleIdentifier: "com.example.Distraction"
        )

        let reduction = SessionReducer.reduce(
            state: .idle,
            runtime: staleRuntime,
            event: .start(
                configuration: configuration,
                sessionID: sessionID,
                wallTime: startTime
            )
        )

        let session = try activeSession(from: reduction.state)
        #expect(session.id == sessionID)
        #expect(session.configuration == configuration)
        #expect(session.startedAt == startTime)
        #expect(session.deadline == startTime.addingTimeInterval(2_700))
        #expect(session.lastKnownRemainingSeconds == 2_700)
        #expect(session.mediumConsumedSeconds == 0)
        #expect(session.status == .running)
        #expect(!session.wasInterrupted)
        #expect(session.metrics == SessionMetrics())
        #expect(reduction.runtime == SessionRuntime())
        #expect(
            reduction.effects == [
                .scheduleDeadline(sessionID: sessionID, deadline: session.deadline),
                .enqueuePersistence(session)
            ]
        )
    }

    @Test("Start cannot replace an active session")
    func activeSessionIsNotReplaced() throws {
        let initial = try startedReduction()
        let otherID = UUID(uuidString: "BBBBBBBB-CCCC-DDDD-EEEE-FFFFFFFFFFFF")!

        let reduction = SessionReducer.reduce(
            state: initial.state,
            runtime: initial.runtime,
            event: .start(
                configuration: try configuration(),
                sessionID: otherID,
                wallTime: startTime.addingTimeInterval(1)
            )
        )

        #expect(reduction == SessionReduction(
            state: initial.state,
            runtime: initial.runtime,
            effects: []
        ))
    }

    @Test("Deadline fires only at or after the configured wall time")
    func deadlineBoundary() throws {
        let initial = try startedReduction()
        let session = try activeSession(from: initial.state)

        let early = SessionReducer.reduce(
            state: initial.state,
            runtime: initial.runtime,
            event: .deadlineReached(
                sessionID: sessionID,
                wallTime: session.deadline.addingTimeInterval(-0.001)
            )
        )
        #expect(early.effects.isEmpty)
        #expect(early.state == initial.state)

        let onTime = SessionReducer.reduce(
            state: initial.state,
            runtime: initial.runtime,
            event: .deadlineReached(sessionID: sessionID, wallTime: session.deadline)
        )
        let summary = try completedSummary(from: onTime.state)
        #expect(summary.outcome == .timedComplete)
        #expect(!summary.wasInterrupted)
        #expect(summary.endedAt == session.deadline)
        #expect(summary.scheduledElapsedSeconds == 2_700)
        #expect(onTime.runtime == SessionRuntime())
        #expect(onTime.effects.first == .cancelSessionWork(sessionID: sessionID))
        #expect(onTime.effects.contains(.presentCompletionReminder(summary)))
        #expect(
            onTime.effects.last
                == .commitTerminal(summary: summary, clearingSessionID: sessionID)
        )
    }

    @Test("Goal safety deadline never reports goal completion")
    func goalSafetyDeadline() throws {
        let initial = try startedReduction(
            completion: .goal(
                definitionOfDone: "A draft exists",
                safetyDurationSeconds: 3_600
            )
        )
        let session = try activeSession(from: initial.state)

        let reduction = SessionReducer.reduce(
            state: initial.state,
            runtime: initial.runtime,
            event: .deadlineReached(sessionID: sessionID, wallTime: session.deadline)
        )

        let summary = try completedSummary(from: reduction.state)
        #expect(summary.outcome == .goalWindowEnded)
        #expect(!reduction.effects.contains(.presentCompletionReminder(summary)))
    }

    @Test("Confirmed goal completion presents a success reminder")
    func confirmedGoalPresentsSuccessReminder() throws {
        let initial = try startedReduction(
            completion: .goal(
                definitionOfDone: "A draft exists",
                safetyDurationSeconds: 3_600
            )
        )

        let reduction = SessionReducer.reduce(
            state: initial.state,
            runtime: initial.runtime,
            event: .goalCompletionConfirmed(
                sessionID: sessionID,
                wallTime: startTime.addingTimeInterval(30)
            )
        )
        let summary = try completedSummary(from: reduction.state)

        #expect(summary.outcome == .goalComplete)
        #expect(reduction.effects.contains(.presentCompletionReminder(summary)))
    }

    @Test("Early stop does not present a success reminder")
    func earlyStopDoesNotPresentSuccessReminder() throws {
        let initial = try startedReduction()

        let reduction = SessionReducer.reduce(
            state: initial.state,
            runtime: initial.runtime,
            event: .earlyStopConfirmed(
                sessionID: sessionID,
                reason: .taskOrPlanChanged,
                wallTime: startTime.addingTimeInterval(30)
            )
        )
        let summary = try completedSummary(from: reduction.state)

        #expect(summary.outcome == .endedEarly)
        #expect(!reduction.effects.contains(.presentCompletionReminder(summary)))
    }

    @Test("Deadline wins a tie with early stop")
    func deadlinePrecedesEarlyStop() throws {
        let initial = try startedReduction()
        let session = try activeSession(from: initial.state)

        let reduction = SessionReducer.reduce(
            state: initial.state,
            runtime: initial.runtime,
            event: .earlyStopConfirmed(
                sessionID: sessionID,
                reason: .taskOrPlanChanged,
                wallTime: session.deadline
            )
        )
        let summary = try completedSummary(from: reduction.state)

        #expect(summary.outcome == .timedComplete)
        #expect(summary.earlyStopReason == nil)
    }

    @Test("Deadline wins a tie with goal confirmation")
    func deadlinePrecedesGoalConfirmation() throws {
        let initial = try startedReduction(
            completion: .goal(
                definitionOfDone: "A draft exists",
                safetyDurationSeconds: 3_600
            )
        )
        let session = try activeSession(from: initial.state)

        let reduction = SessionReducer.reduce(
            state: initial.state,
            runtime: initial.runtime,
            event: .goalCompletionConfirmed(
                sessionID: sessionID,
                wallTime: session.deadline
            )
        )

        #expect(try completedSummary(from: reduction.state).outcome == .goalWindowEnded)
    }

    @Test("Deadline wins a tie with Medium depletion")
    func deadlinePrecedesMediumDepletion() throws {
        let initial = try startedReduction(mode: .medium(allowanceSeconds: 300))
        let session = try activeSession(from: initial.state)

        let reduction = SessionReducer.reduce(
            state: initial.state,
            runtime: initial.runtime,
            event: .mediumAllowanceDepleted(
                sessionID: sessionID,
                wallTime: session.deadline,
                elapsedTime: .seconds(300)
            )
        )

        #expect(try completedSummary(from: reduction.state).outcome == .timedComplete)
    }

    @Test("Wrong-session callbacks are ignored")
    func staleSessionIDIsIgnored() throws {
        let initial = try startedReduction()
        let staleID = UUID(uuidString: "FFFFFFFF-EEEE-DDDD-CCCC-BBBBBBBBBBBB")!

        let reduction = SessionReducer.reduce(
            state: initial.state,
            runtime: initial.runtime,
            event: .applicationActivated(
                sessionID: staleID,
                application: selectedApplication,
                wallTime: startTime.addingTimeInterval(1),
                elapsedTime: .seconds(1)
            )
        )

        #expect(reduction.state == initial.state)
        #expect(reduction.runtime == initial.runtime)
        #expect(reduction.effects.isEmpty)
    }

    @Test("Delayed enforcement and repeated terminal callbacks cannot mutate completion")
    func callbacksAfterCompletionAreIgnored() throws {
        let initial = try startedReduction()
        let session = try activeSession(from: initial.state)
        let completed = SessionReducer.reduce(
            state: initial.state,
            runtime: initial.runtime,
            event: .deadlineReached(sessionID: sessionID, wallTime: session.deadline)
        )

        let delayedResult = SessionReducer.reduce(
            state: completed.state,
            runtime: completed.runtime,
            event: .returnTargetActivationFailed(
                sessionID: sessionID,
                wallTime: session.deadline.addingTimeInterval(1)
            )
        )
        #expect(delayedResult.state == completed.state)
        #expect(delayedResult.effects.isEmpty)

        let repeatedDeadline = SessionReducer.reduce(
            state: completed.state,
            runtime: completed.runtime,
            event: .deadlineReached(
                sessionID: sessionID,
                wallTime: session.deadline.addingTimeInterval(2)
            )
        )
        #expect(repeatedDeadline.state == completed.state)
        #expect(repeatedDeadline.effects.isEmpty)
    }

    private var selectedApplication: AppIdentity {
        AppIdentity(
            bundleIdentifier: "com.example.Distraction",
            displayName: "Distraction"
        )
    }

    private func configuration(
        mode: FocusMode = .soft,
        completion: CompletionRule = .timer(durationSeconds: 2_700)
    ) throws -> FocusConfiguration {
        try FocusDraft(
            intention: "Write the launch brief",
            selectedApps: [selectedApplication],
            mode: mode,
            completion: completion
        ).validated()
    }

    private func startedReduction(
        mode: FocusMode = .soft,
        completion: CompletionRule = .timer(durationSeconds: 2_700)
    ) throws -> SessionReduction {
        SessionReducer.reduce(
            state: .idle,
            runtime: SessionRuntime(),
            event: .start(
                configuration: try configuration(mode: mode, completion: completion),
                sessionID: sessionID,
                wallTime: startTime
            )
        )
    }

    private func activeSession(from state: FocusState) throws -> RunningSession {
        guard case let .active(session) = state else {
            throw TestError.expectedActiveSession
        }
        return session
    }

    private func completedSummary(from state: FocusState) throws -> SessionSummary {
        guard case let .completed(summary) = state else {
            throw TestError.expectedCompletedSession
        }
        return summary
    }

    private enum TestError: Error {
        case expectedActiveSession
        case expectedCompletedSession
    }
}
