import Foundation
import Testing
@testable import Attune

@Suite("Soft session reducer")
struct SessionReducerSoftTests {
    private let startTime = Date(timeIntervalSince1970: 1_800_000_000)
    private let sessionID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    @Test("Unselected activation changes runtime fallback only")
    func unselectedActivation() throws {
        let initial = try startedReduction()
        let application = AppIdentity(
            bundleIdentifier: "com.example.Editor",
            displayName: "Editor"
        )

        let reduction = SessionReducer.reduce(
            state: initial.state,
            runtime: initial.runtime,
            event: activation(
                application,
                wallOffset: 1,
                elapsedTime: .seconds(1)
            )
        )

        #expect(reduction.state == initial.state)
        #expect(reduction.runtime.lastAllowedBundleIdentifier == application.bundleIdentifier)
        #expect(reduction.runtime.intervention == nil)
        #expect(reduction.effects.isEmpty)
    }

    @Test("Selected activation presents a warning without hiding")
    func selectedActivation() throws {
        let initial = try startedReduction()
        let reduction = SessionReducer.reduce(
            state: initial.state,
            runtime: initial.runtime,
            event: activation(
                selectedApplication,
                wallOffset: 1,
                elapsedTime: .seconds(12)
            )
        )
        let session = try activeSession(from: reduction.state)
        let intervention = try #require(reduction.runtime.intervention)

        #expect(session.metrics.interventionCount == 1)
        #expect(intervention.application == selectedApplication)
        #expect(intervention.presentedAt == .seconds(12))
        #expect(
            reduction.effects == [
                .presentSoftIntervention(intervention),
                .enqueuePersistence(session)
            ]
        )
    }

    @Test("Return explicitly hides before switching to the fallback")
    func returnToFocusHidesBeforeSwitching() throws {
        let editor = AppIdentity(
            bundleIdentifier: "com.example.Editor",
            displayName: "Editor"
        )
        let initial = try startedReduction()
        let withFallback = SessionReducer.reduce(
            state: initial.state,
            runtime: initial.runtime,
            event: activation(editor, wallOffset: 1, elapsedTime: .seconds(1))
        )
        let prompted = SessionReducer.reduce(
            state: withFallback.state,
            runtime: withFallback.runtime,
            event: activation(selectedApplication, wallOffset: 2, elapsedTime: .seconds(2))
        )

        let requested = SessionReducer.reduce(
            state: prompted.state,
            runtime: prompted.runtime,
            event: .softReturnRequested(
                sessionID: sessionID,
                wallTime: startTime.addingTimeInterval(3),
                elapsedTime: .seconds(3)
            )
        )
        #expect(try activeSession(from: requested.state).metrics.softReturnCount == 0)
        #expect(requested.runtime.intervention != nil)
        #expect(requested.runtime.softReturnInProgress)
        #expect(requested.runtime.softAllowedBundleIdentifier == nil)
        #expect(
            requested.effects == [
                .attemptSoftReturn(
                    sessionID: sessionID,
                    bundleIdentifier: selectedApplication.bundleIdentifier,
                    fallbackBundleIdentifier: editor.bundleIdentifier
                )
            ]
        )

        let duplicateRequest = SessionReducer.reduce(
            state: requested.state,
            runtime: requested.runtime,
            event: .softReturnRequested(
                sessionID: sessionID,
                wallTime: startTime.addingTimeInterval(3),
                elapsedTime: .seconds(3)
            )
        )
        #expect(duplicateRequest.effects.isEmpty)

        let completed = SessionReducer.reduce(
            state: requested.state,
            runtime: requested.runtime,
            event: .softReturnHideCompleted(
                sessionID: sessionID,
                bundleIdentifier: selectedApplication.bundleIdentifier,
                fallbackBundleIdentifier: editor.bundleIdentifier,
                result: .hidden,
                wallTime: startTime.addingTimeInterval(3)
            )
        )
        let session = try activeSession(from: completed.state)

        #expect(session.metrics.softReturnCount == 1)
        #expect(session.metrics.softOpenCount == 0)
        #expect(completed.runtime.intervention == nil)
        #expect(!completed.runtime.softReturnInProgress)
        #expect(
            completed.effects == [
                .dismissIntervention(sessionID: sessionID),
                .reactivateApplication(
                    sessionID: sessionID,
                    bundleIdentifier: editor.bundleIdentifier
                ),
                .enqueuePersistence(session)
            ]
        )
    }

    @Test("The same selected app presents another warning after Return")
    func repeatedDistractionPresentsAgainWithoutHiding() throws {
        let editor = AppIdentity(
            bundleIdentifier: "com.example.Editor",
            displayName: "Editor"
        )
        let initial = try startedReduction()
        let withFallback = SessionReducer.reduce(
            state: initial.state,
            runtime: initial.runtime,
            event: activation(editor, wallOffset: 1, elapsedTime: .seconds(1))
        )
        let firstPrompt = SessionReducer.reduce(
            state: withFallback.state,
            runtime: withFallback.runtime,
            event: activation(selectedApplication, wallOffset: 2, elapsedTime: .seconds(2))
        )
        let returned = SessionReducer.reduce(
            state: firstPrompt.state,
            runtime: firstPrompt.runtime,
            event: .softReturnRequested(
                sessionID: sessionID,
                wallTime: startTime.addingTimeInterval(3),
                elapsedTime: .seconds(3)
            )
        )

        let completedReturn = SessionReducer.reduce(
            state: returned.state,
            runtime: returned.runtime,
            event: .softReturnHideCompleted(
                sessionID: sessionID,
                bundleIdentifier: selectedApplication.bundleIdentifier,
                fallbackBundleIdentifier: editor.bundleIdentifier,
                result: .hidden,
                wallTime: startTime.addingTimeInterval(3)
            )
        )
        let secondPrompt = SessionReducer.reduce(
            state: completedReturn.state,
            runtime: completedReturn.runtime,
            event: activation(selectedApplication, wallOffset: 4, elapsedTime: .seconds(4))
        )
        let session = try activeSession(from: secondPrompt.state)
        let intervention = try #require(secondPrompt.runtime.intervention)

        #expect(session.metrics.interventionCount == 2)
        #expect(session.metrics.softReturnCount == 1)
        #expect(
            secondPrompt.effects == [
                .presentSoftIntervention(intervention),
                .enqueuePersistence(session)
            ]
        )
    }

    @Test("Return uses Finder when no fallback has been observed")
    func finderFallback() throws {
        let prompted = try promptedReduction(presentedAt: .seconds(2))

        let reduction = SessionReducer.reduce(
            state: prompted.state,
            runtime: prompted.runtime,
            event: .softReturnRequested(
                sessionID: sessionID,
                wallTime: startTime.addingTimeInterval(3),
                elapsedTime: .seconds(3)
            )
        )
        #expect(
            reduction.effects == [
                .attemptSoftReturn(
                    sessionID: sessionID,
                    bundleIdentifier: selectedApplication.bundleIdentifier,
                    fallbackBundleIdentifier: "com.apple.finder"
                )
            ]
        )
    }

    @Test("A failed Return hide keeps the warning available for retry")
    func failedReturnKeepsIntervention() throws {
        let prompted = try promptedReduction(presentedAt: .seconds(2))
        let failed = SessionReducer.reduce(
            state: prompted.state,
            runtime: prompted.runtime,
            event: .softReturnHideCompleted(
                sessionID: sessionID,
                bundleIdentifier: selectedApplication.bundleIdentifier,
                fallbackBundleIdentifier: "com.apple.finder",
                result: .failed,
                wallTime: startTime.addingTimeInterval(3)
            )
        )
        let session = try activeSession(from: failed.state)
        let intervention = try #require(failed.runtime.intervention)

        #expect(session.metrics.softReturnCount == 0)
        #expect(session.metrics.enforcementFailureCount == 1)
        #expect(!failed.runtime.softReturnInProgress)
        #expect(failed.runtime.softReturnFailed)
        #expect(
            failed.effects == [
                .presentSoftIntervention(intervention),
                .enqueuePersistence(session)
            ]
        )
    }

    @Test("Open Anyway rejects before eight seconds and accepts the exact boundary")
    func openDelayBoundary() throws {
        let prompted = try promptedReduction(presentedAt: .seconds(10))

        let early = SessionReducer.reduce(
            state: prompted.state,
            runtime: prompted.runtime,
            event: .softOpenRequested(
                sessionID: sessionID,
                wallTime: startTime.addingTimeInterval(5),
                elapsedTime: .seconds(17.999)
            )
        )
        #expect(early.state == prompted.state)
        #expect(early.runtime == prompted.runtime)
        #expect(early.effects.isEmpty)

        let allowed = SessionReducer.reduce(
            state: prompted.state,
            runtime: prompted.runtime,
            event: .softOpenRequested(
                sessionID: sessionID,
                wallTime: startTime.addingTimeInterval(6),
                elapsedTime: .seconds(18)
            )
        )
        let session = try activeSession(from: allowed.state)

        #expect(session.metrics.softOpenCount == 1)
        #expect(allowed.runtime.intervention == nil)
        #expect(
            allowed.runtime.softAllowedBundleIdentifier
                == selectedApplication.bundleIdentifier
        )
        #expect(
            allowed.effects == [
                .dismissIntervention(sessionID: sessionID),
                .enqueuePersistence(session)
            ]
        )
    }

    @Test("An active Soft bypass suppresses prompts until deactivation")
    func bypassLifecycle() throws {
        let prompted = try promptedReduction(presentedAt: .seconds(1))
        let opened = SessionReducer.reduce(
            state: prompted.state,
            runtime: prompted.runtime,
            event: .softOpenRequested(
                sessionID: sessionID,
                wallTime: startTime.addingTimeInterval(9),
                elapsedTime: .seconds(9)
            )
        )

        let bypassedActivation = SessionReducer.reduce(
            state: opened.state,
            runtime: opened.runtime,
            event: activation(
                selectedApplication,
                wallOffset: 10,
                elapsedTime: .seconds(10)
            )
        )
        #expect(bypassedActivation.effects.isEmpty)
        #expect(
            try activeSession(from: bypassedActivation.state).metrics.interventionCount == 1
        )

        let deactivated = SessionReducer.reduce(
            state: bypassedActivation.state,
            runtime: bypassedActivation.runtime,
            event: .applicationDeactivated(
                sessionID: sessionID,
                bundleIdentifier: selectedApplication.bundleIdentifier,
                wallTime: startTime.addingTimeInterval(11),
                elapsedTime: .seconds(11)
            )
        )
        #expect(deactivated.runtime.softAllowedBundleIdentifier == nil)

        let promptedAgain = SessionReducer.reduce(
            state: deactivated.state,
            runtime: deactivated.runtime,
            event: activation(
                selectedApplication,
                wallOffset: 12,
                elapsedTime: .seconds(12)
            )
        )
        #expect(try activeSession(from: promptedAgain.state).metrics.interventionCount == 2)
        #expect(promptedAgain.runtime.intervention != nil)
    }

    @Test("After resolution, duplicate notifications strictly inside one second coalesce")
    func duplicateActivationWindow() throws {
        let first = try promptedReduction(presentedAt: .seconds(10))
        var resolvedRuntime = first.runtime
        resolvedRuntime.intervention = nil

        let duplicate = SessionReducer.reduce(
            state: first.state,
            runtime: resolvedRuntime,
            event: activation(
                selectedApplication,
                wallOffset: 2,
                elapsedTime: .seconds(10.999)
            )
        )
        #expect(duplicate.effects.isEmpty)
        #expect(try activeSession(from: duplicate.state).metrics.interventionCount == 1)

        let boundary = SessionReducer.reduce(
            state: first.state,
            runtime: resolvedRuntime,
            event: activation(
                selectedApplication,
                wallOffset: 3,
                elapsedTime: .seconds(11)
            )
        )
        #expect(try activeSession(from: boundary.state).metrics.interventionCount == 2)
        #expect(boundary.effects.count == 2)
    }

    @Test("A deadline reached during Open Anyway wins and never reactivates the app")
    func deadlinePrecedesOpenAnyway() throws {
        let prompted = try promptedReduction(presentedAt: .seconds(2))
        let session = try activeSession(from: prompted.state)

        let reduction = SessionReducer.reduce(
            state: prompted.state,
            runtime: prompted.runtime,
            event: .softOpenRequested(
                sessionID: sessionID,
                wallTime: session.deadline,
                elapsedTime: .seconds(2_700)
            )
        )

        guard case let .completed(summary) = reduction.state else {
            Issue.record("Expected a completed session")
            return
        }
        #expect(summary.outcome == .timedComplete)
        #expect(reduction.runtime == SessionRuntime())
        #expect(
            !reduction.effects.contains(
                .reactivateApplication(
                    sessionID: sessionID,
                    bundleIdentifier: selectedApplication.bundleIdentifier
                )
            )
        )
        #expect(reduction.effects.contains(.dismissIntervention(sessionID: sessionID)))
    }

    @Test("A selected activation at the deadline completes without an intervention")
    func activationAtDeadline() throws {
        let initial = try startedReduction()
        let session = try activeSession(from: initial.state)

        let reduction = SessionReducer.reduce(
            state: initial.state,
            runtime: initial.runtime,
            event: .applicationActivated(
                sessionID: sessionID,
                application: selectedApplication,
                wallTime: session.deadline,
                elapsedTime: .seconds(2_700)
            )
        )

        guard case let .completed(summary) = reduction.state else {
            Issue.record("Expected a completed session")
            return
        }
        #expect(summary.outcome == .timedComplete)
        #expect(reduction.effects == [
            .cancelSessionWork(sessionID: sessionID),
            .presentCompletionReminder(summary),
            .commitTerminal(summary: summary, clearingSessionID: sessionID)
        ])
    }

    private var selectedApplication: AppIdentity {
        AppIdentity(
            bundleIdentifier: "com.example.Distraction",
            displayName: "Distraction"
        )
    }

    private func startedReduction() throws -> SessionReduction {
        let configuration = try FocusDraft(
            intention: "Write the launch brief",
            selectedApps: [selectedApplication],
            mode: .soft,
            completion: .timer(durationSeconds: 2_700)
        ).validated()

        return SessionReducer.reduce(
            state: .idle,
            runtime: SessionRuntime(),
            event: .start(
                configuration: configuration,
                sessionID: sessionID,
                wallTime: startTime
            )
        )
    }

    private func promptedReduction(presentedAt: Duration) throws -> SessionReduction {
        let initial = try startedReduction()
        return SessionReducer.reduce(
            state: initial.state,
            runtime: initial.runtime,
            event: activation(
                selectedApplication,
                wallOffset: 1,
                elapsedTime: presentedAt
            )
        )
    }

    private func activation(
        _ application: AppIdentity,
        wallOffset: TimeInterval,
        elapsedTime: Duration
    ) -> SessionEvent {
        .applicationActivated(
            sessionID: sessionID,
            application: application,
            wallTime: startTime.addingTimeInterval(wallOffset),
            elapsedTime: elapsedTime
        )
    }

    private func activeSession(from state: FocusState) throws -> RunningSession {
        guard case let .active(session) = state else {
            throw TestError.expectedActiveSession
        }
        return session
    }

    private enum TestError: Error {
        case expectedActiveSession
    }
}
