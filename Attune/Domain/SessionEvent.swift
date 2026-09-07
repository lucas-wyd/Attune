import Foundation

enum SoftReturnHideResult: Equatable, Sendable {
    case hidden
    case applicationEnded
    case failed
}

enum EnforcementHideResult: Equatable, Sendable {
    case hidden
    case applicationEnded
    case failed
}

enum SessionEvent: Equatable, Sendable {
    case start(
        configuration: FocusConfiguration,
        sessionID: UUID,
        wallTime: Date
    )
    case applicationActivated(
        sessionID: UUID,
        application: AppIdentity,
        wallTime: Date,
        elapsedTime: Duration
    )
    case applicationDeactivated(
        sessionID: UUID,
        bundleIdentifier: String,
        wallTime: Date,
        elapsedTime: Duration
    )
    case softReturnRequested(
        sessionID: UUID,
        wallTime: Date,
        elapsedTime: Duration
    )
    case softReturnHideCompleted(
        sessionID: UUID,
        bundleIdentifier: String,
        fallbackBundleIdentifier: String,
        result: SoftReturnHideResult,
        wallTime: Date
    )
    case softOpenRequested(
        sessionID: UUID,
        wallTime: Date,
        elapsedTime: Duration
    )
    case mediumInterventionHideCompleted(
        sessionID: UUID,
        bundleIdentifier: String,
        result: EnforcementHideResult,
        wallTime: Date
    )
    case mediumUseAllowanceRequested(
        sessionID: UUID,
        wallTime: Date,
        elapsedTime: Duration
    )
    case mediumReturnRequested(
        sessionID: UUID,
        wallTime: Date
    )
    case mediumMeterCheckpoint(
        sessionID: UUID,
        wallTime: Date,
        elapsedTime: Duration
    )
    case mediumMeterSuspended(
        sessionID: UUID,
        wallTime: Date,
        elapsedTime: Duration
    )
    case mediumMeterResumed(
        sessionID: UUID,
        wallTime: Date,
        elapsedTime: Duration
    )
    case strictReconciliationRequested(
        sessionID: UUID,
        wallTime: Date,
        elapsedTime: Duration
    )
    case enforcementCompleted(
        sessionID: UUID,
        application: AppIdentity,
        attemptedProcessIdentifiers: Set<Int32>,
        hideResult: EnforcementHideResult,
        stillRunning: Bool,
        presentsStatus: Bool,
        wallTime: Date
    )
    case deadlineReached(sessionID: UUID, wallTime: Date)
    case goalCompletionConfirmed(sessionID: UUID, wallTime: Date)
    case earlyStopConfirmed(
        sessionID: UUID,
        reason: EarlyStopReason,
        wallTime: Date
    )
    case mediumAllowanceDepleted(
        sessionID: UUID,
        wallTime: Date,
        elapsedTime: Duration
    )
    case returnTargetActivationFailed(
        sessionID: UUID,
        wallTime: Date
    )
}
