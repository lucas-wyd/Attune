import Foundation

enum SessionStatus: Codable, Equatable, Sendable {
    case running
    case interrupted
}

enum SessionOutcome: String, Codable, Equatable, Sendable {
    case timedComplete
    case goalComplete
    case goalWindowEnded
    case endedEarly
    case interrupted
}

enum EarlyStopReason: String, Codable, Equatable, Sendable {
    case urgentNeed
    case selectedApplicationNeeded
    case taskOrPlanChanged
    case setupNotHelping
    case other
}

struct RunningSession: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let configuration: FocusConfiguration
    let startedAt: Date
    let deadline: Date
    var lastKnownRemainingSeconds: Int
    var mediumConsumedSeconds: Int
    var wasInterrupted: Bool
    var status: SessionStatus
    var metrics: SessionMetrics
}

struct SessionSummary: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let outcome: SessionOutcome
    let startedAt: Date
    let endedAt: Date
    let configuration: FocusConfiguration
    let mediumConsumedSeconds: Int
    let wasInterrupted: Bool
    let metrics: SessionMetrics
    let earlyStopReason: EarlyStopReason?
    var satisfaction: Int?

    var scheduledElapsedSeconds: Int {
        max(0, Int(endedAt.timeIntervalSince(startedAt)))
    }
}

enum FocusState: Equatable, Sendable {
    case idle
    case active(RunningSession)
    case completed(SessionSummary)
}

struct SessionIntervention: Equatable, Sendable {
    let sessionID: UUID
    let application: AppIdentity
    let presentedAt: Duration
}

struct SelectedApplicationActivation: Equatable, Sendable {
    let bundleIdentifier: String
    let occurredAt: Duration
}

struct SessionRuntime: Equatable, Sendable {
    var lastAllowedBundleIdentifier: String?
    var softAllowedBundleIdentifier: String?
    var mediumForegroundBundleIdentifier: String?
    var mediumForegroundStartedAt: Duration?
    var mediumFractionalRemainder: Duration
    var mediumAllowanceWarningShown: Bool
    var normalQuitRequestedProcessIdentifiers: Set<Int32>
    var recentSpaceChangeTimes: [Duration]
    var lastContextCheckInAt: Duration?
    var idleEpisodePrompted: Bool
    var intervention: SessionIntervention?
    var softReturnInProgress: Bool
    var softReturnFailed: Bool
    var lastSelectedApplicationActivation: SelectedApplicationActivation?

    init(
        lastAllowedBundleIdentifier: String? = nil,
        softAllowedBundleIdentifier: String? = nil,
        mediumForegroundBundleIdentifier: String? = nil,
        mediumForegroundStartedAt: Duration? = nil,
        mediumFractionalRemainder: Duration = .zero,
        mediumAllowanceWarningShown: Bool = false,
        normalQuitRequestedProcessIdentifiers: Set<Int32> = [],
        recentSpaceChangeTimes: [Duration] = [],
        lastContextCheckInAt: Duration? = nil,
        idleEpisodePrompted: Bool = false,
        intervention: SessionIntervention? = nil,
        softReturnInProgress: Bool = false,
        softReturnFailed: Bool = false,
        lastSelectedApplicationActivation: SelectedApplicationActivation? = nil
    ) {
        self.lastAllowedBundleIdentifier = lastAllowedBundleIdentifier
        self.softAllowedBundleIdentifier = softAllowedBundleIdentifier
        self.mediumForegroundBundleIdentifier = mediumForegroundBundleIdentifier
        self.mediumForegroundStartedAt = mediumForegroundStartedAt
        self.mediumFractionalRemainder = mediumFractionalRemainder
        self.mediumAllowanceWarningShown = mediumAllowanceWarningShown
        self.normalQuitRequestedProcessIdentifiers = normalQuitRequestedProcessIdentifiers
        self.recentSpaceChangeTimes = recentSpaceChangeTimes
        self.lastContextCheckInAt = lastContextCheckInAt
        self.idleEpisodePrompted = idleEpisodePrompted
        self.intervention = intervention
        self.softReturnInProgress = softReturnInProgress
        self.softReturnFailed = softReturnFailed
        self.lastSelectedApplicationActivation = lastSelectedApplicationActivation
    }
}
