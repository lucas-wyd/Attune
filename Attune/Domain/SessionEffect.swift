import Foundation

enum SessionEffect: Equatable, Sendable {
    case scheduleDeadline(sessionID: UUID, deadline: Date)
    case cancelSessionWork(sessionID: UUID)
    case attemptSoftReturn(
        sessionID: UUID,
        bundleIdentifier: String,
        fallbackBundleIdentifier: String
    )
    case reactivateApplication(sessionID: UUID, bundleIdentifier: String)
    case presentSoftIntervention(SessionIntervention)
    case attemptMediumInterventionHide(SessionIntervention)
    case presentMediumIntervention(SessionIntervention)
    case enforceSelectedApplication(
        sessionID: UUID,
        application: AppIdentity,
        fallbackBundleIdentifier: String,
        excludingProcessIdentifiers: Set<Int32>,
        presentsStatus: Bool
    )
    case presentEnforcementStatus(
        sessionID: UUID,
        application: AppIdentity,
        hideFailed: Bool,
        stillRunning: Bool
    )
    case dismissIntervention(sessionID: UUID)
    case presentCompletionReminder(SessionSummary)
    case enqueuePersistence(RunningSession)
    case commitTerminal(summary: SessionSummary, clearingSessionID: UUID)
}
