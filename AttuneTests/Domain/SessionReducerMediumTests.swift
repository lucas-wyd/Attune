import Foundation
import Testing
@testable import Attune

@Suite("Medium session reducer")
struct SessionReducerMediumTests {
    private let startTime = Date(timeIntervalSince1970: 1_800_000_000)
    private let sessionID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    private let selected = AppIdentity(
        bundleIdentifier: "com.example.Distraction",
        displayName: "Distraction"
    )

    @Test("Activation hides before presenting the shared allowance choice")
    func activationHidesBeforeConsent() throws {
        let started = try startedReduction()
        let activated = activate(started, elapsed: .seconds(2))
        let session = try activeSession(activated.state)
        let intervention = try #require(activated.runtime.intervention)

        #expect(session.metrics.interventionCount == 1)
        #expect(activated.runtime.mediumForegroundStartedAt == nil)
        #expect(activated.effects == [
            .attemptMediumInterventionHide(intervention),
            .enqueuePersistence(session)
        ])

        let hidden = SessionReducer.reduce(
            state: activated.state,
            runtime: activated.runtime,
            event: .mediumInterventionHideCompleted(
                sessionID: sessionID,
                bundleIdentifier: selected.bundleIdentifier,
                result: .hidden,
                wallTime: startTime.addingTimeInterval(2)
            )
        )
        #expect(hidden.effects == [.presentMediumIntervention(intervention)])
    }

    @Test("Use Allowance rejects before five seconds and starts one shared meter at the boundary")
    func consentBoundary() throws {
        let activated = activate(try startedReduction(), elapsed: .seconds(2))
        let early = SessionReducer.reduce(
            state: activated.state,
            runtime: activated.runtime,
            event: .mediumUseAllowanceRequested(
                sessionID: sessionID,
                wallTime: startTime.addingTimeInterval(6),
                elapsedTime: .seconds(6.999)
            )
        )
        #expect(early.state == activated.state)
        #expect(early.runtime == activated.runtime)
        #expect(early.effects.isEmpty)

        let allowed = SessionReducer.reduce(
            state: activated.state,
            runtime: activated.runtime,
            event: .mediumUseAllowanceRequested(
                sessionID: sessionID,
                wallTime: startTime.addingTimeInterval(7),
                elapsedTime: .seconds(7)
            )
        )
        #expect(allowed.runtime.intervention == nil)
        #expect(allowed.runtime.mediumForegroundBundleIdentifier == selected.bundleIdentifier)
        #expect(allowed.runtime.mediumForegroundStartedAt == .seconds(7))
        #expect(allowed.effects == [
            .dismissIntervention(sessionID: sessionID),
            .reactivateApplication(
                sessionID: sessionID,
                bundleIdentifier: selected.bundleIdentifier
            )
        ])
    }

    @Test("Foreground checkpoints consume whole seconds and preserve the fractional remainder")
    func meteringPreservesFraction() throws {
        let activated = activate(try startedReduction(), elapsed: .zero)
        let allowed = SessionReducer.reduce(
            state: activated.state,
            runtime: activated.runtime,
            event: .mediumUseAllowanceRequested(
                sessionID: sessionID,
                wallTime: startTime.addingTimeInterval(5),
                elapsedTime: .seconds(5)
            )
        )
        let checkpoint = SessionReducer.reduce(
            state: allowed.state,
            runtime: allowed.runtime,
            event: .mediumMeterCheckpoint(
                sessionID: sessionID,
                wallTime: startTime.addingTimeInterval(6),
                elapsedTime: .seconds(6.2)
            )
        )

        #expect(try activeSession(checkpoint.state).mediumConsumedSeconds == 1)
        #expect(
            abs(seconds(checkpoint.runtime.mediumFractionalRemainder) - 0.2)
                < 0.000_001
        )
        #expect(checkpoint.runtime.mediumForegroundStartedAt == .seconds(6.2))
    }

    @Test("Depletion immediately enters Strict enforcement")
    func depletionEnforces() throws {
        let started = try startedReduction()
        var session = try activeSession(started.state)
        session.mediumConsumedSeconds = 59
        var runtime = started.runtime
        runtime.mediumForegroundBundleIdentifier = selected.bundleIdentifier
        runtime.mediumForegroundStartedAt = .seconds(10)

        let depleted = SessionReducer.reduce(
            state: .active(session),
            runtime: runtime,
            event: .mediumMeterCheckpoint(
                sessionID: sessionID,
                wallTime: startTime.addingTimeInterval(11),
                elapsedTime: .seconds(11)
            )
        )
        let updated = try activeSession(depleted.state)
        #expect(updated.mediumConsumedSeconds == 60)
        #expect(depleted.runtime.mediumForegroundBundleIdentifier == nil)
        #expect(depleted.effects.contains(.enforceSelectedApplication(
            sessionID: sessionID,
            application: selected,
            fallbackBundleIdentifier: "com.apple.finder",
            excludingProcessIdentifiers: [],
            presentsStatus: true
        )))
    }

    @Test("Suspension checkpoints use and resumes the approved interval without counting time away")
    func suspensionPreservesConsent() throws {
        let activated = activate(try startedReduction(), elapsed: .zero)
        let allowed = SessionReducer.reduce(
            state: activated.state,
            runtime: activated.runtime,
            event: .mediumUseAllowanceRequested(
                sessionID: sessionID,
                wallTime: startTime.addingTimeInterval(5),
                elapsedTime: .seconds(5)
            )
        )
        let suspended = SessionReducer.reduce(
            state: allowed.state,
            runtime: allowed.runtime,
            event: .mediumMeterSuspended(
                sessionID: sessionID,
                wallTime: startTime.addingTimeInterval(7),
                elapsedTime: .seconds(7)
            )
        )
        #expect(try activeSession(suspended.state).mediumConsumedSeconds == 2)
        #expect(suspended.runtime.mediumForegroundBundleIdentifier == selected.bundleIdentifier)
        #expect(suspended.runtime.mediumForegroundStartedAt == nil)

        let resumed = SessionReducer.reduce(
            state: suspended.state,
            runtime: suspended.runtime,
            event: .mediumMeterResumed(
                sessionID: sessionID,
                wallTime: startTime.addingTimeInterval(27),
                elapsedTime: .seconds(27)
            )
        )
        #expect(try activeSession(resumed.state).mediumConsumedSeconds == 2)
        #expect(resumed.runtime.mediumForegroundStartedAt == .seconds(27))
    }

    private func startedReduction() throws -> SessionReduction {
        let configuration = try FocusDraft(
            intention: "Write the launch brief",
            selectedApps: [selected],
            mode: .medium(allowanceSeconds: 60),
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

    private func activate(
        _ reduction: SessionReduction,
        elapsed: Duration
    ) -> SessionReduction {
        SessionReducer.reduce(
            state: reduction.state,
            runtime: reduction.runtime,
            event: .applicationActivated(
                sessionID: sessionID,
                application: selected,
                wallTime: startTime.addingTimeInterval(1),
                elapsedTime: elapsed
            )
        )
    }

    private func activeSession(_ state: FocusState) throws -> RunningSession {
        guard case let .active(session) = state else {
            throw TestError.expectedActiveSession
        }
        return session
    }

    private func seconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds)
            + Double(components.attoseconds) / 1_000_000_000_000_000_000
    }

    private enum TestError: Error {
        case expectedActiveSession
    }
}
