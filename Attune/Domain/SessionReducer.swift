import Foundation

struct SessionReduction: Equatable, Sendable {
    let state: FocusState
    let runtime: SessionRuntime
    let effects: [SessionEffect]
}

struct SessionReducer {
    private static let softDelay: Duration = .seconds(8)
    private static let mediumUseDelay: Duration = .seconds(5)
    private static let duplicateActivationWindow: Duration = .seconds(1)
    private static let finderBundleIdentifier = "com.apple.finder"

    static func reduce(
        state: FocusState,
        runtime: SessionRuntime,
        event: SessionEvent
    ) -> SessionReduction {
        switch event {
        case let .start(configuration, sessionID, wallTime):
            guard !state.isActive else {
                return unchanged(state: state, runtime: runtime)
            }

            let durationSeconds = configuration.completion.durationSeconds
            let session = RunningSession(
                id: sessionID,
                configuration: configuration,
                startedAt: wallTime,
                deadline: wallTime.addingTimeInterval(TimeInterval(durationSeconds)),
                lastKnownRemainingSeconds: durationSeconds,
                mediumConsumedSeconds: 0,
                wasInterrupted: false,
                status: .running,
                metrics: SessionMetrics()
            )

            return SessionReduction(
                state: .active(session),
                runtime: SessionRuntime(),
                effects: [
                    .scheduleDeadline(sessionID: session.id, deadline: session.deadline),
                    .enqueuePersistence(session)
                ]
            )

        case let .applicationActivated(
            sessionID,
            application,
            wallTime,
            elapsedTime
        ):
            guard case var .active(session) = state, session.id == sessionID else {
                return unchanged(state: state, runtime: runtime)
            }
            if wallTime >= session.deadline {
                return deadlineReduction(session: session, runtime: runtime)
            }

            let isSelected = session.configuration.selectedApps.contains {
                $0.bundleIdentifier == application.bundleIdentifier
            }
            guard isSelected else {
                var nextRuntime = runtime
                var nextSession = session
                let checkpoint = checkpointMediumMeter(
                    session: &nextSession,
                    runtime: &nextRuntime,
                    elapsedTime: elapsedTime
                )
                nextRuntime.lastAllowedBundleIdentifier = application.bundleIdentifier
                if nextRuntime.softAllowedBundleIdentifier != application.bundleIdentifier {
                    nextRuntime.softAllowedBundleIdentifier = nil
                }
                return SessionReduction(
                    state: .active(nextSession),
                    runtime: nextRuntime,
                    effects: checkpoint.didConsume ? [.enqueuePersistence(nextSession)] : []
                )
            }

            switch session.configuration.mode {
            case .soft:
                guard runtime.softAllowedBundleIdentifier != application.bundleIdentifier else {
                    return unchanged(state: state, runtime: runtime)
                }
                guard runtime.intervention?.application.bundleIdentifier
                    != application.bundleIdentifier else {
                    return unchanged(state: state, runtime: runtime)
                }
                guard !isDuplicateActivation(
                    application: application,
                    elapsedTime: elapsedTime,
                    runtime: runtime
                ) else {
                    return unchanged(state: state, runtime: runtime)
                }

            case let .medium(allowanceSeconds):
                if runtime.mediumForegroundBundleIdentifier == application.bundleIdentifier {
                    return unchanged(state: state, runtime: runtime)
                }
                var mediumRuntime = runtime
                let checkpoint = checkpointMediumMeter(
                    session: &session,
                    runtime: &mediumRuntime,
                    elapsedTime: elapsedTime
                )
                if session.mediumConsumedSeconds >= allowanceSeconds {
                    guard !isDuplicateActivation(
                        application: application,
                        elapsedTime: elapsedTime,
                        runtime: mediumRuntime
                    ) else {
                        return unchanged(state: state, runtime: runtime)
                    }
                    return strictEnforcementReduction(
                        session: session,
                        runtime: mediumRuntime,
                        application: application,
                        elapsedTime: elapsedTime,
                        countIntervention: true
                    )
                }
                if let intervention = mediumRuntime.intervention,
                   intervention.application.bundleIdentifier
                    == application.bundleIdentifier {
                    guard !isDuplicateActivation(
                        application: application,
                        elapsedTime: elapsedTime,
                        runtime: mediumRuntime
                    ) else {
                        return unchanged(state: state, runtime: runtime)
                    }
                    var nextRuntime = mediumRuntime
                    nextRuntime.lastSelectedApplicationActivation =
                        SelectedApplicationActivation(
                            bundleIdentifier: application.bundleIdentifier,
                            occurredAt: elapsedTime
                        )
                    var effects: [SessionEffect] = [
                        .attemptMediumInterventionHide(intervention)
                    ]
                    if checkpoint.didConsume {
                        effects.append(.enqueuePersistence(session))
                    }
                    return SessionReduction(
                        state: .active(session),
                        runtime: nextRuntime,
                        effects: effects
                    )
                }
                guard !isDuplicateActivation(
                    application: application,
                    elapsedTime: elapsedTime,
                    runtime: mediumRuntime
                ) else {
                    return unchanged(state: state, runtime: runtime)
                }

                session.lastKnownRemainingSeconds = remainingSeconds(for: session, at: wallTime)
                session.metrics.interventionCount += 1
                let intervention = SessionIntervention(
                    sessionID: session.id,
                    application: application,
                    presentedAt: elapsedTime
                )
                var nextRuntime = mediumRuntime
                nextRuntime.intervention = intervention
                nextRuntime.lastSelectedApplicationActivation = SelectedApplicationActivation(
                    bundleIdentifier: application.bundleIdentifier,
                    occurredAt: elapsedTime
                )
                return SessionReduction(
                    state: .active(session),
                    runtime: nextRuntime,
                    effects: [
                        .attemptMediumInterventionHide(intervention),
                        .enqueuePersistence(session)
                    ]
                )

            case .strict:
                guard !isDuplicateActivation(
                    application: application,
                    elapsedTime: elapsedTime,
                    runtime: runtime
                ) else {
                    return unchanged(state: state, runtime: runtime)
                }
                return strictEnforcementReduction(
                    session: session,
                    runtime: runtime,
                    application: application,
                    elapsedTime: elapsedTime,
                    countIntervention: true
                )
            }

            session.lastKnownRemainingSeconds = remainingSeconds(
                for: session,
                at: wallTime
            )
            session.metrics.interventionCount += 1

            let intervention = SessionIntervention(
                sessionID: session.id,
                application: application,
                presentedAt: elapsedTime
            )
            var nextRuntime = runtime
            nextRuntime.intervention = intervention
            nextRuntime.softReturnInProgress = false
            nextRuntime.softReturnFailed = false
            nextRuntime.lastSelectedApplicationActivation = SelectedApplicationActivation(
                bundleIdentifier: application.bundleIdentifier,
                occurredAt: elapsedTime
            )

            return SessionReduction(
                state: .active(session),
                runtime: nextRuntime,
                effects: [
                    .presentSoftIntervention(intervention),
                    .enqueuePersistence(session)
                ]
            )

        case let .applicationDeactivated(
            sessionID,
            bundleIdentifier,
            wallTime,
            elapsedTime
        ):
            guard case let .active(session) = state, session.id == sessionID else {
                return unchanged(state: state, runtime: runtime)
            }
            if wallTime >= session.deadline {
                return deadlineReduction(session: session, runtime: runtime)
            }

            var nextRuntime = runtime
            var nextSession = session
            let checkpoint = checkpointMediumMeter(
                session: &nextSession,
                runtime: &nextRuntime,
                elapsedTime: elapsedTime,
                matchingBundleIdentifier: bundleIdentifier
            )
            if nextRuntime.softAllowedBundleIdentifier == bundleIdentifier {
                nextRuntime.softAllowedBundleIdentifier = nil
            }
            if nextRuntime.lastSelectedApplicationActivation?.bundleIdentifier
                == bundleIdentifier {
                nextRuntime.lastSelectedApplicationActivation = nil
            }
            return SessionReduction(
                state: .active(nextSession),
                runtime: nextRuntime,
                effects: checkpoint.didConsume ? [.enqueuePersistence(nextSession)] : []
            )

        case let .softReturnRequested(sessionID, wallTime, _):
            guard case let .active(session) = state,
                  session.id == sessionID,
                  case .soft = session.configuration.mode,
                  let intervention = runtime.intervention,
                  intervention.sessionID == sessionID,
                  !runtime.softReturnInProgress else {
                return unchanged(state: state, runtime: runtime)
            }
            if wallTime >= session.deadline {
                return deadlineReduction(session: session, runtime: runtime)
            }

            let fallbackBundleIdentifier = runtime.lastAllowedBundleIdentifier
                ?? finderBundleIdentifier

            var nextRuntime = runtime
            nextRuntime.softReturnInProgress = true
            return SessionReduction(
                state: state,
                runtime: nextRuntime,
                effects: [
                    .attemptSoftReturn(
                        sessionID: session.id,
                        bundleIdentifier: intervention.application.bundleIdentifier,
                        fallbackBundleIdentifier: fallbackBundleIdentifier
                    )
                ]
            )

        case let .softReturnHideCompleted(
            sessionID,
            bundleIdentifier,
            fallbackBundleIdentifier,
            result,
            wallTime
        ):
            guard case var .active(session) = state,
                  session.id == sessionID,
                  case .soft = session.configuration.mode,
                  let intervention = runtime.intervention,
                  intervention.sessionID == sessionID,
                  intervention.application.bundleIdentifier == bundleIdentifier else {
                return unchanged(state: state, runtime: runtime)
            }
            if wallTime >= session.deadline {
                return deadlineReduction(session: session, runtime: runtime)
            }

            session.lastKnownRemainingSeconds = remainingSeconds(
                for: session,
                at: wallTime
            )
            var nextRuntime = runtime

            switch result {
            case .hidden, .applicationEnded:
                session.metrics.softReturnCount += 1
                nextRuntime.intervention = nil
                nextRuntime.softAllowedBundleIdentifier = nil
                nextRuntime.softReturnInProgress = false
                nextRuntime.softReturnFailed = false

                return SessionReduction(
                    state: .active(session),
                    runtime: nextRuntime,
                    effects: [
                        .dismissIntervention(sessionID: session.id),
                        .reactivateApplication(
                            sessionID: session.id,
                            bundleIdentifier: fallbackBundleIdentifier
                        ),
                        .enqueuePersistence(session)
                    ]
                )

            case .failed:
                session.metrics.enforcementFailureCount += 1
                nextRuntime.softReturnInProgress = false
                nextRuntime.softReturnFailed = true
                return SessionReduction(
                    state: .active(session),
                    runtime: nextRuntime,
                    effects: [
                        .presentSoftIntervention(intervention),
                        .enqueuePersistence(session)
                    ]
                )
            }

        case let .softOpenRequested(sessionID, wallTime, elapsedTime):
            guard case var .active(session) = state,
                  session.id == sessionID,
                  case .soft = session.configuration.mode,
                  let intervention = runtime.intervention,
                  intervention.sessionID == sessionID else {
                return unchanged(state: state, runtime: runtime)
            }
            if wallTime >= session.deadline {
                return deadlineReduction(session: session, runtime: runtime)
            }
            guard elapsedTime >= intervention.presentedAt + softDelay else {
                return unchanged(state: state, runtime: runtime)
            }

            session.lastKnownRemainingSeconds = remainingSeconds(
                for: session,
                at: wallTime
            )
            session.metrics.softOpenCount += 1

            var nextRuntime = runtime
            nextRuntime.intervention = nil
            nextRuntime.softAllowedBundleIdentifier = intervention.application.bundleIdentifier
            nextRuntime.softReturnInProgress = false
            nextRuntime.softReturnFailed = false

            return SessionReduction(
                state: .active(session),
                runtime: nextRuntime,
                effects: [
                    .dismissIntervention(sessionID: session.id),
                    .enqueuePersistence(session)
                ]
            )

        case let .mediumInterventionHideCompleted(
            sessionID,
            bundleIdentifier,
            result,
            wallTime
        ):
            guard case var .active(session) = state,
                  session.id == sessionID,
                  case .medium = session.configuration.mode,
                  let intervention = runtime.intervention,
                  intervention.application.bundleIdentifier == bundleIdentifier else {
                return unchanged(state: state, runtime: runtime)
            }
            if wallTime >= session.deadline {
                return deadlineReduction(session: session, runtime: runtime)
            }
            switch result {
            case .hidden, .applicationEnded:
                return SessionReduction(
                    state: state,
                    runtime: runtime,
                    effects: [.presentMediumIntervention(intervention)]
                )
            case .failed:
                session.metrics.enforcementFailureCount += 1
                return SessionReduction(
                    state: .active(session),
                    runtime: runtime,
                    effects: [
                        .presentMediumIntervention(intervention),
                        .enqueuePersistence(session)
                    ]
                )
            }

        case let .mediumUseAllowanceRequested(sessionID, wallTime, elapsedTime):
            guard case let .active(session) = state,
                  session.id == sessionID,
                  case let .medium(allowanceSeconds) = session.configuration.mode,
                  session.mediumConsumedSeconds < allowanceSeconds,
                  let intervention = runtime.intervention,
                  elapsedTime >= intervention.presentedAt + mediumUseDelay else {
                return unchanged(state: state, runtime: runtime)
            }
            if wallTime >= session.deadline {
                return deadlineReduction(session: session, runtime: runtime)
            }
            var nextRuntime = runtime
            nextRuntime.intervention = nil
            nextRuntime.mediumForegroundBundleIdentifier = intervention.application.bundleIdentifier
            nextRuntime.mediumForegroundStartedAt = elapsedTime
            return SessionReduction(
                state: state,
                runtime: nextRuntime,
                effects: [
                    .dismissIntervention(sessionID: sessionID),
                    .reactivateApplication(
                        sessionID: sessionID,
                        bundleIdentifier: intervention.application.bundleIdentifier
                    )
                ]
            )

        case let .mediumReturnRequested(sessionID, wallTime):
            guard case let .active(session) = state,
                  session.id == sessionID,
                  case .medium = session.configuration.mode,
                  runtime.intervention != nil else {
                return unchanged(state: state, runtime: runtime)
            }
            if wallTime >= session.deadline {
                return deadlineReduction(session: session, runtime: runtime)
            }
            var nextRuntime = runtime
            nextRuntime.intervention = nil
            return SessionReduction(
                state: state,
                runtime: nextRuntime,
                effects: [
                    .dismissIntervention(sessionID: sessionID),
                    .reactivateApplication(
                        sessionID: sessionID,
                        bundleIdentifier: runtime.lastAllowedBundleIdentifier
                            ?? finderBundleIdentifier
                    )
                ]
            )

        case let .mediumMeterCheckpoint(sessionID, wallTime, elapsedTime):
            guard case var .active(session) = state,
                  session.id == sessionID,
                  case let .medium(allowanceSeconds) = session.configuration.mode else {
                return unchanged(state: state, runtime: runtime)
            }
            if wallTime >= session.deadline {
                return deadlineReduction(session: session, runtime: runtime)
            }
            var nextRuntime = runtime
            let meteredBundleIdentifier = nextRuntime.mediumForegroundBundleIdentifier
            let before = session.mediumConsumedSeconds
            _ = checkpointMediumMeter(
                session: &session,
                runtime: &nextRuntime,
                elapsedTime: elapsedTime,
                keepMeterRunning: true
            )
            let depleted = session.mediumConsumedSeconds >= allowanceSeconds
            var effects: [SessionEffect] = []
            if session.mediumConsumedSeconds != before,
               session.mediumConsumedSeconds.isMultiple(of: 5) || depleted {
                effects.append(.enqueuePersistence(session))
            }
            if !nextRuntime.mediumAllowanceWarningShown,
               allowanceSeconds - session.mediumConsumedSeconds <= 60,
               allowanceSeconds - session.mediumConsumedSeconds > 0,
               let bundleIdentifier = nextRuntime.mediumForegroundBundleIdentifier,
               let application = session.configuration.selectedApps.first(where: {
                   $0.bundleIdentifier == bundleIdentifier
               }) {
                nextRuntime.mediumAllowanceWarningShown = true
                effects.append(.presentEnforcementStatus(
                    sessionID: sessionID,
                    application: application,
                    hideFailed: false,
                    stillRunning: false
                ))
            }
            if depleted,
               let bundleIdentifier = meteredBundleIdentifier,
               let application = session.configuration.selectedApps.first(where: {
                   $0.bundleIdentifier == bundleIdentifier
               }) {
                nextRuntime.mediumForegroundBundleIdentifier = nil
                nextRuntime.mediumForegroundStartedAt = nil
                effects.append(.enforceSelectedApplication(
                    sessionID: sessionID,
                    application: application,
                    fallbackBundleIdentifier: nextRuntime.lastAllowedBundleIdentifier
                        ?? finderBundleIdentifier,
                    excludingProcessIdentifiers: nextRuntime.normalQuitRequestedProcessIdentifiers,
                    presentsStatus: true
                ))
            }
            return SessionReduction(
                state: .active(session),
                runtime: nextRuntime,
                effects: effects
            )

        case let .mediumMeterSuspended(sessionID, wallTime, elapsedTime):
            guard case var .active(session) = state,
                  session.id == sessionID,
                  case .medium = session.configuration.mode else {
                return unchanged(state: state, runtime: runtime)
            }
            if wallTime >= session.deadline {
                return deadlineReduction(session: session, runtime: runtime)
            }
            var nextRuntime = runtime
            let approvedBundleIdentifier = nextRuntime.mediumForegroundBundleIdentifier
            let checkpoint = checkpointMediumMeter(
                session: &session,
                runtime: &nextRuntime,
                elapsedTime: elapsedTime
            )
            nextRuntime.mediumForegroundBundleIdentifier = approvedBundleIdentifier
            nextRuntime.mediumForegroundStartedAt = nil
            return SessionReduction(
                state: .active(session),
                runtime: nextRuntime,
                effects: checkpoint.didConsume ? [.enqueuePersistence(session)] : []
            )

        case let .mediumMeterResumed(sessionID, wallTime, elapsedTime):
            guard case let .active(session) = state,
                  session.id == sessionID,
                  case let .medium(allowanceSeconds) = session.configuration.mode,
                  session.mediumConsumedSeconds < allowanceSeconds,
                  runtime.mediumForegroundBundleIdentifier != nil else {
                return unchanged(state: state, runtime: runtime)
            }
            if wallTime >= session.deadline {
                return deadlineReduction(session: session, runtime: runtime)
            }
            var nextRuntime = runtime
            nextRuntime.mediumForegroundStartedAt = elapsedTime
            return SessionReduction(state: state, runtime: nextRuntime, effects: [])

        case let .strictReconciliationRequested(sessionID, wallTime, _):
            guard case let .active(session) = state,
                  session.id == sessionID,
                  isStrictEnforcementActive(session) else {
                return unchanged(state: state, runtime: runtime)
            }
            if wallTime >= session.deadline {
                return deadlineReduction(session: session, runtime: runtime)
            }
            let fallback = runtime.lastAllowedBundleIdentifier ?? finderBundleIdentifier
            return SessionReduction(
                state: state,
                runtime: runtime,
                effects: session.configuration.selectedApps.map {
                    .enforceSelectedApplication(
                        sessionID: sessionID,
                        application: $0,
                        fallbackBundleIdentifier: fallback,
                        excludingProcessIdentifiers: runtime.normalQuitRequestedProcessIdentifiers,
                        presentsStatus: false
                    )
                }
            )

        case let .enforcementCompleted(
            sessionID,
            application,
            attemptedProcessIdentifiers,
            hideResult,
            stillRunning,
            presentsStatus,
            wallTime
        ):
            guard case var .active(session) = state, session.id == sessionID else {
                return unchanged(state: state, runtime: runtime)
            }
            if wallTime >= session.deadline {
                return deadlineReduction(session: session, runtime: runtime)
            }
            var nextRuntime = runtime
            nextRuntime.normalQuitRequestedProcessIdentifiers.formUnion(
                attemptedProcessIdentifiers
            )
            let hideFailed = hideResult == .failed
            if hideFailed {
                session.metrics.enforcementFailureCount += 1
            }
            var effects: [SessionEffect] = [.enqueuePersistence(session)]
            if presentsStatus, hideResult != .applicationEnded {
                effects.insert(
                    .presentEnforcementStatus(
                        sessionID: sessionID,
                        application: application,
                        hideFailed: hideFailed,
                        stillRunning: stillRunning
                    ),
                    at: 0
                )
            }
            return SessionReduction(
                state: .active(session),
                runtime: nextRuntime,
                effects: effects
            )

        case let .deadlineReached(sessionID, wallTime):
            guard case let .active(session) = state,
                  session.id == sessionID,
                  wallTime >= session.deadline else {
                return unchanged(state: state, runtime: runtime)
            }
            return deadlineReduction(session: session, runtime: runtime)

        case let .goalCompletionConfirmed(sessionID, wallTime):
            guard case let .active(session) = state,
                  session.id == sessionID,
                  case .goal = session.configuration.completion else {
                return unchanged(state: state, runtime: runtime)
            }
            if wallTime >= session.deadline {
                return deadlineReduction(session: session, runtime: runtime)
            }
            return terminalReduction(
                session: session,
                runtime: runtime,
                outcome: .goalComplete,
                endedAt: wallTime,
                earlyStopReason: nil
            )

        case let .earlyStopConfirmed(sessionID, reason, wallTime):
            guard case let .active(session) = state, session.id == sessionID else {
                return unchanged(state: state, runtime: runtime)
            }
            if wallTime >= session.deadline {
                return deadlineReduction(session: session, runtime: runtime)
            }
            return terminalReduction(
                session: session,
                runtime: runtime,
                outcome: .endedEarly,
                endedAt: wallTime,
                earlyStopReason: reason
            )

        case let .mediumAllowanceDepleted(sessionID, wallTime, _):
            guard case let .active(session) = state, session.id == sessionID else {
                return unchanged(state: state, runtime: runtime)
            }
            if wallTime >= session.deadline {
                return deadlineReduction(session: session, runtime: runtime)
            }
            guard case var .active(updatedSession) = state,
                  case let .medium(allowanceSeconds) = updatedSession.configuration.mode else {
                return unchanged(state: state, runtime: runtime)
            }
            updatedSession.mediumConsumedSeconds = allowanceSeconds
            return SessionReduction(
                state: .active(updatedSession),
                runtime: runtime,
                effects: [.enqueuePersistence(updatedSession)]
            )

        case let .returnTargetActivationFailed(sessionID, wallTime):
            guard case var .active(session) = state, session.id == sessionID else {
                return unchanged(state: state, runtime: runtime)
            }
            if wallTime >= session.deadline {
                return deadlineReduction(session: session, runtime: runtime)
            }

            session.metrics.enforcementFailureCount += 1
            session.lastKnownRemainingSeconds = remainingSeconds(for: session, at: wallTime)

            return SessionReduction(
                state: .active(session),
                runtime: runtime,
                effects: [.enqueuePersistence(session)]
            )
        }
    }

    private static func deadlineReduction(
        session: RunningSession,
        runtime: SessionRuntime
    ) -> SessionReduction {
        let outcome: SessionOutcome
        switch session.configuration.completion {
        case .timer:
            outcome = .timedComplete
        case .goal:
            outcome = .goalWindowEnded
        }

        return terminalReduction(
            session: session,
            runtime: runtime,
            outcome: outcome,
            endedAt: session.deadline,
            earlyStopReason: nil
        )
    }

    private static func terminalReduction(
        session: RunningSession,
        runtime: SessionRuntime,
        outcome: SessionOutcome,
        endedAt: Date,
        earlyStopReason: EarlyStopReason?
    ) -> SessionReduction {
        let summary = SessionSummary(
            id: session.id,
            outcome: outcome,
            startedAt: session.startedAt,
            endedAt: endedAt,
            configuration: session.configuration,
            mediumConsumedSeconds: session.mediumConsumedSeconds,
            wasInterrupted: session.wasInterrupted,
            metrics: session.metrics,
            earlyStopReason: earlyStopReason,
            satisfaction: nil
        )

        var effects: [SessionEffect] = [
            .cancelSessionWork(sessionID: session.id)
        ]
        if runtime.intervention != nil {
            effects.append(.dismissIntervention(sessionID: session.id))
        }
        if outcome == .timedComplete || outcome == .goalComplete {
            effects.append(.presentCompletionReminder(summary))
        }
        effects.append(
            .commitTerminal(summary: summary, clearingSessionID: session.id)
        )

        return SessionReduction(
            state: .completed(summary),
            runtime: SessionRuntime(),
            effects: effects
        )
    }

    private static func remainingSeconds(
        for session: RunningSession,
        at wallTime: Date
    ) -> Int {
        let computedRemaining = max(
            0,
            Int(session.deadline.timeIntervalSince(wallTime).rounded(.up))
        )
        return min(session.lastKnownRemainingSeconds, computedRemaining)
    }

    private static func strictEnforcementReduction(
        session: RunningSession,
        runtime: SessionRuntime,
        application: AppIdentity,
        elapsedTime: Duration,
        countIntervention: Bool
    ) -> SessionReduction {
        var nextSession = session
        if countIntervention {
            nextSession.metrics.interventionCount += 1
        }
        var nextRuntime = runtime
        nextRuntime.lastSelectedApplicationActivation = SelectedApplicationActivation(
            bundleIdentifier: application.bundleIdentifier,
            occurredAt: elapsedTime
        )
        return SessionReduction(
            state: .active(nextSession),
            runtime: nextRuntime,
            effects: [
                .enforceSelectedApplication(
                    sessionID: session.id,
                    application: application,
                    fallbackBundleIdentifier: runtime.lastAllowedBundleIdentifier
                        ?? finderBundleIdentifier,
                    excludingProcessIdentifiers: runtime.normalQuitRequestedProcessIdentifiers,
                    presentsStatus: true
                ),
                .enqueuePersistence(nextSession)
            ]
        )
    }

    private static func isStrictEnforcementActive(_ session: RunningSession) -> Bool {
        switch session.configuration.mode {
        case .strict:
            true
        case let .medium(allowanceSeconds):
            session.mediumConsumedSeconds >= allowanceSeconds
        case .soft:
            false
        }
    }

    private struct MediumCheckpoint {
        let didConsume: Bool
    }

    private static func checkpointMediumMeter(
        session: inout RunningSession,
        runtime: inout SessionRuntime,
        elapsedTime: Duration,
        matchingBundleIdentifier: String? = nil,
        keepMeterRunning: Bool = false
    ) -> MediumCheckpoint {
        guard case let .medium(allowanceSeconds) = session.configuration.mode,
              let bundleIdentifier = runtime.mediumForegroundBundleIdentifier,
              matchingBundleIdentifier == nil || matchingBundleIdentifier == bundleIdentifier,
              let startedAt = runtime.mediumForegroundStartedAt else {
            return MediumCheckpoint(didConsume: false)
        }

        let interval = elapsedTime >= startedAt ? elapsedTime - startedAt : .zero
        let accumulated = runtime.mediumFractionalRemainder + interval
        let components = accumulated.components
        let wholeSeconds = max(0, Int(components.seconds))
        let clampedConsumption = min(
            allowanceSeconds,
            session.mediumConsumedSeconds + wholeSeconds
        )
        let consumed = clampedConsumption - session.mediumConsumedSeconds
        session.mediumConsumedSeconds = clampedConsumption
        runtime.mediumFractionalRemainder = Duration(
            secondsComponent: 0,
            attosecondsComponent: components.attoseconds
        )

        if keepMeterRunning, session.mediumConsumedSeconds < allowanceSeconds {
            runtime.mediumForegroundStartedAt = elapsedTime
        } else {
            runtime.mediumForegroundBundleIdentifier = nil
            runtime.mediumForegroundStartedAt = nil
        }
        return MediumCheckpoint(didConsume: consumed > 0)
    }

    private static func isDuplicateActivation(
        application: AppIdentity,
        elapsedTime: Duration,
        runtime: SessionRuntime
    ) -> Bool {
        guard let previous = runtime.lastSelectedApplicationActivation,
              previous.bundleIdentifier == application.bundleIdentifier else {
            return false
        }

        guard elapsedTime >= previous.occurredAt else {
            return true
        }
        return elapsedTime - previous.occurredAt < duplicateActivationWindow
    }

    private static func unchanged(
        state: FocusState,
        runtime: SessionRuntime
    ) -> SessionReduction {
        SessionReduction(state: state, runtime: runtime, effects: [])
    }
}

private extension FocusState {
    var isActive: Bool {
        if case .active = self {
            true
        } else {
            false
        }
    }
}
