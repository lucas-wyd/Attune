import Foundation
import Testing
@testable import Attune

@Suite("Strict session reducer")
struct SessionReducerStrictTests {
    private let startTime = Date(timeIntervalSince1970: 1_800_000_000)
    private let sessionID = UUID(uuidString: "99999999-8888-7777-6666-555555555555")!
    private let selected = AppIdentity(
        bundleIdentifier: "com.example.Distraction",
        displayName: "Distraction"
    )

    @Test("Activation emits immediate best-effort enforcement")
    func activationEnforces() throws {
        let started = try startedReduction()
        let activated = SessionReducer.reduce(
            state: started.state,
            runtime: started.runtime,
            event: activation(elapsed: .seconds(2))
        )
        let session = try activeSession(activated.state)

        #expect(session.metrics.interventionCount == 1)
        #expect(activated.effects == [
            .enforceSelectedApplication(
                sessionID: sessionID,
                application: selected,
                fallbackBundleIdentifier: "com.apple.finder",
                excludingProcessIdentifiers: [],
                presentsStatus: true
            ),
            .enqueuePersistence(session)
        ])
    }

    @Test("Duplicate activation notifications are coalesced")
    func duplicateActivationIsIgnored() throws {
        let started = try startedReduction()
        let first = SessionReducer.reduce(
            state: started.state,
            runtime: started.runtime,
            event: activation(elapsed: .seconds(2))
        )
        let duplicate = SessionReducer.reduce(
            state: first.state,
            runtime: first.runtime,
            event: activation(elapsed: .seconds(2.5))
        )

        #expect(duplicate.effects.isEmpty)
        #expect(try activeSession(duplicate.state).metrics.interventionCount == 1)
    }

    @Test("A real deactivation makes an immediate return enforce again")
    func deactivationEndsDuplicateWindow() throws {
        let started = try startedReduction()
        let first = SessionReducer.reduce(
            state: started.state,
            runtime: started.runtime,
            event: activation(elapsed: .seconds(2))
        )
        let deactivated = SessionReducer.reduce(
            state: first.state,
            runtime: first.runtime,
            event: .applicationDeactivated(
                sessionID: sessionID,
                bundleIdentifier: selected.bundleIdentifier,
                wallTime: startTime.addingTimeInterval(2.25),
                elapsedTime: .seconds(2.25)
            )
        )
        let returned = SessionReducer.reduce(
            state: deactivated.state,
            runtime: deactivated.runtime,
            event: activation(elapsed: .seconds(2.5))
        )

        #expect(
            returned.effects.first == .enforceSelectedApplication(
                sessionID: sessionID,
                application: selected,
                fallbackBundleIdentifier: "com.apple.finder",
                excludingProcessIdentifiers: [],
                presentsStatus: true
            )
        )
        #expect(try activeSession(returned.state).metrics.interventionCount == 2)
    }

    @Test("Reconciliation is silent and excludes live processes already asked to quit")
    func reconciliationIsSilent() throws {
        let started = try startedReduction()
        var runtime = started.runtime
        runtime.normalQuitRequestedProcessIdentifiers = [42]
        let reduction = SessionReducer.reduce(
            state: started.state,
            runtime: runtime,
            event: .strictReconciliationRequested(
                sessionID: sessionID,
                wallTime: startTime.addingTimeInterval(2),
                elapsedTime: .seconds(2)
            )
        )

        #expect(reduction.effects == [
            .enforceSelectedApplication(
                sessionID: sessionID,
                application: selected,
                fallbackBundleIdentifier: "com.apple.finder",
                excludingProcessIdentifiers: [42],
                presentsStatus: false
            )
        ])
    }

    @Test("Enforcement results remember attempted PIDs without force termination policy")
    func enforcementResultTracksProcess() throws {
        let started = try startedReduction()
        let reduction = SessionReducer.reduce(
            state: started.state,
            runtime: started.runtime,
            event: .enforcementCompleted(
                sessionID: sessionID,
                application: selected,
                attemptedProcessIdentifiers: [42],
                hideResult: .hidden,
                stillRunning: true,
                presentsStatus: true,
                wallTime: startTime.addingTimeInterval(3)
            )
        )

        #expect(reduction.runtime.normalQuitRequestedProcessIdentifiers == [42])
        #expect(reduction.effects.first == .presentEnforcementStatus(
            sessionID: sessionID,
            application: selected,
            hideFailed: false,
            stillRunning: true
        ))
    }

    private func startedReduction() throws -> SessionReduction {
        let configuration = try FocusDraft(
            intention: "Write the launch brief",
            selectedApps: [selected],
            mode: .strict,
            completion: .timer(durationSeconds: 300)
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

    private func activation(elapsed: Duration) -> SessionEvent {
        .applicationActivated(
            sessionID: sessionID,
            application: selected,
            wallTime: startTime.addingTimeInterval(1),
            elapsedTime: elapsed
        )
    }

    private func activeSession(_ state: FocusState) throws -> RunningSession {
        guard case let .active(session) = state else {
            throw TestError.expectedActiveSession
        }
        return session
    }

    private enum TestError: Error {
        case expectedActiveSession
    }
}
