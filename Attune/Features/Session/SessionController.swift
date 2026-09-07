import Foundation
import Observation

enum ControllerPersistenceOperation: Equatable, Sendable {
    case load
    case activeSession
    case terminalOutcome
}

struct ControllerPersistenceFailure: Equatable, Sendable {
    let operation: ControllerPersistenceOperation
    let message: String
}

enum ControllerPersistenceStatus: Equatable, Sendable {
    case loading
    case saved
    case saving
    case failed(ControllerPersistenceFailure)

    var userMessage: String? {
        guard case let .failed(failure) = self else {
            return nil
        }

        switch failure.operation {
        case .load:
            return "Attune could not load saved focus data. You can keep using the app, but recovery is unavailable."
        case .activeSession:
            return "This focus is still active, but recovery is unavailable until Attune can save it."
        case .terminalOutcome:
            return "This focus ended in memory, but its history and recovery state have not been saved yet."
        }
    }
}

enum TerminalPersistenceStatus: Equatable, Sendable {
    case none
    case committing(sessionID: UUID)
    case committed(sessionID: UUID)
    case failed(sessionID: UUID)
}

enum InterruptionRecoveryState: Equatable, Sendable {
    case none
    case awaitingDecision(sessionID: UUID)
}

struct GoalReviewState: Equatable, Sendable {
    let sessionID: UUID
    let requestedAt: Duration
    var unlockAt: Duration
    var isUnlocked: Bool
    var isPaused: Bool
}

enum StopIntent: Equatable, Sendable {
    case endFocus
    case quit
}

struct StopChallenge: Equatable, Sendable {
    let sessionID: UUID
    var intent: StopIntent
    let requestedAt: Duration
    var unlockAt: Duration
    var selectedReason: EarlyStopReason?
    var isUnlocked: Bool
    var isPaused: Bool
}

@MainActor
@Observable
final class SessionController {
    private static let finderBundleIdentifier = "com.apple.finder"
    private static let softOpenDelay: Duration = .seconds(8)
    private static let mediumUseDelay: Duration = .seconds(5)
    private static let strictReconciliationInterval: Duration = .seconds(2)
    private static let snapshotInterval: Duration = .seconds(15)

    private(set) var state: FocusState = .idle
    private(set) var runtime = SessionRuntime()
    private(set) var preferences = AppPreferences.initial
    private(set) var interruptionState: InterruptionRecoveryState = .none
    private(set) var goalReview: GoalReviewState?
    private(set) var stopChallenge: StopChallenge?
    private(set) var softOpenAvailable = false
    private(set) var mediumUseAvailable = false
    private(set) var persistenceStatus: ControllerPersistenceStatus = .saved
    private(set) var terminalPersistenceStatus: TerminalPersistenceStatus = .none
    private(set) var isWorkspaceObservationActive = false
    private(set) var isInitialized = false

    var activeSession: RunningSession? {
        guard case let .active(session) = state else {
            return nil
        }
        return session
    }

    var completedSummary: SessionSummary? {
        guard case let .completed(summary) = state else {
            return nil
        }
        return summary
    }

    var canStartSession: Bool {
        activeSession == nil && !terminalPersistenceBlocksStateReplacement
    }

    var remainingSeconds: Int? {
        guard let session = activeSession else {
            return nil
        }
        guard session.status == .running else {
            return session.lastKnownRemainingSeconds
        }
        let calculated = max(
            0,
            Int(session.deadline.timeIntervalSince(wallClock.now()).rounded(.up))
        )
        return min(session.lastKnownRemainingSeconds, calculated)
    }

    var goalReviewRemainingSeconds: Int? {
        guard let review = goalReview else {
            return nil
        }
        guard !review.isUnlocked else {
            return 0
        }
        let remaining = review.isPaused
            ? goalRemainingWhenPaused ?? .zero
            : max(.zero, review.unlockAt - elapsedClock.now())
        return wholeSecondsRoundedUp(remaining)
    }

    var mediumAllowanceRemainingSeconds: Int? {
        guard let session = activeSession,
              case let .medium(allowanceSeconds) = session.configuration.mode else {
            return nil
        }
        return max(0, allowanceSeconds - session.mediumConsumedSeconds)
    }

    var stopCooldownRemainingSeconds: Int? {
        guard let challenge = stopChallenge else {
            return nil
        }
        guard !challenge.isUnlocked else {
            return 0
        }
        let remaining = challenge.isPaused
            ? stopRemainingWhenPaused ?? .zero
            : max(.zero, challenge.unlockAt - elapsedClock.now())
        return wholeSecondsRoundedUp(remaining)
    }

    @ObservationIgnored private let wallClock: any WallClock
    @ObservationIgnored private let elapsedClock: any ElapsedClock
    @ObservationIgnored private let workspaceClient: any WorkspaceClient
    @ObservationIgnored private let applicationController: any ApplicationController
    @ObservationIgnored private let overlayPresenter: any OverlayPresenting
    @ObservationIgnored private let completionReminderPresenter: any CompletionReminderPresenting
    @ObservationIgnored private let repository: any StateRepository
    @ObservationIgnored private let makeSessionID: () -> UUID
    @ObservationIgnored private let selfBundleIdentifier: String?
    @ObservationIgnored private var isInitializing = false

    @ObservationIgnored private var workspaceObservationTask: Task<Void, Never>?
    @ObservationIgnored private var frontmostReconciliationTask: Task<Void, Never>?
    @ObservationIgnored private var deadlineTask: Task<Void, Never>?
    @ObservationIgnored private var snapshotTask: Task<Void, Never>?
    @ObservationIgnored private var softGateTask: Task<Void, Never>?
    @ObservationIgnored private var mediumGateTask: Task<Void, Never>?
    @ObservationIgnored private var mediumMeterTask: Task<Void, Never>?
    @ObservationIgnored private var strictReconciliationTask: Task<Void, Never>?
    @ObservationIgnored private var enforcementTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var enforcementStatusRequestedBundles: Set<String> = []
    @ObservationIgnored private var goalGateTask: Task<Void, Never>?
    @ObservationIgnored private var stopGateTask: Task<Void, Never>?
    @ObservationIgnored private var persistenceTail: Task<Void, Never>?

    @ObservationIgnored private var sessionGeneration: UInt64 = 0
    @ObservationIgnored private var persistenceSequence: UInt64 = 0
    @ObservationIgnored private var softGateIntervention: SessionIntervention?
    @ObservationIgnored private var softUnlockAt: Duration?
    @ObservationIgnored private var softRemainingWhenPaused: Duration?
    @ObservationIgnored private var mediumGateIntervention: SessionIntervention?
    @ObservationIgnored private var mediumUnlockAt: Duration?
    @ObservationIgnored private var mediumRemainingWhenPaused: Duration?
    @ObservationIgnored private var goalRemainingWhenPaused: Duration?
    @ObservationIgnored private var stopRemainingWhenPaused: Duration?
    @ObservationIgnored private var suspensionReasons: Set<SuspensionReason> = []
    @ObservationIgnored private var pendingPersistence: PendingPersistence?

    init(
        wallClock: any WallClock = LiveWallClock(),
        elapsedClock: any ElapsedClock = LiveElapsedClock(),
        workspaceClient: any WorkspaceClient,
        applicationController: any ApplicationController,
        overlayPresenter: any OverlayPresenting,
        completionReminderPresenter: any CompletionReminderPresenting,
        repository: any StateRepository = FileStateRepository(),
        makeSessionID: @escaping () -> UUID = { UUID() },
        selfBundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) {
        self.wallClock = wallClock
        self.elapsedClock = elapsedClock
        self.workspaceClient = workspaceClient
        self.applicationController = applicationController
        self.overlayPresenter = overlayPresenter
        self.completionReminderPresenter = completionReminderPresenter
        self.repository = repository
        self.makeSessionID = makeSessionID
        self.selfBundleIdentifier = selfBundleIdentifier
    }

    func initialize() async {
        guard !isInitialized, !isInitializing else {
            return
        }
        isInitializing = true
        defer { isInitializing = false }

        persistenceStatus = .loading
        do {
            let document = try await repository.loadState()
            preferences = document.preferences
            isInitialized = true

            guard var session = document.activeSession else {
                state = .idle
                persistenceStatus = .saved
                startWorkspaceObservation()
                return
            }

            session.status = .interrupted
            session.wasInterrupted = true
            runtime = SessionRuntime()
            beginNewSessionGeneration()

            if session.lastKnownRemainingSeconds <= 0 {
                publishInterruptedOutcome(for: session, at: wallClock.now())
                startWorkspaceObservation()
            } else {
                state = .active(session)
                interruptionState = .awaitingDecision(sessionID: session.id)
                enqueueStateSave(session)
            }
        } catch {
            isInitialized = true
            state = .idle
            runtime = SessionRuntime()
            recordPersistenceFailure(error, operation: .load)
            startWorkspaceObservation()
        }
    }

    @discardableResult
    func start(_ configuration: FocusConfiguration) -> UUID? {
        guard canStartSession else {
            return nil
        }

        beginNewSessionGeneration()
        interruptionState = .none
        terminalPersistenceStatus = .none
        let sessionID = makeSessionID()
        send(.start(
            configuration: configuration,
            sessionID: sessionID,
            wallTime: wallClock.now()
        ))
        startWorkspaceObservation()
        reconcileFrontmostApplication()
        updateModeWork()
        reconcileStrictApplications()
        return activeSession?.id == sessionID ? sessionID : nil
    }

    func startWorkspaceObservation() {
        guard workspaceObservationTask == nil else {
            return
        }

        isWorkspaceObservationActive = true
        let workspaceClient = workspaceClient
        workspaceObservationTask = Task { @MainActor [weak self, workspaceClient] in
            for await event in workspaceClient.events() {
                guard !Task.isCancelled, let self else {
                    return
                }
                self.handleWorkspaceEvent(event)
            }
        }
    }

    func completeOnboarding(selectedApps: [AppIdentity]) {
        guard !terminalPersistenceBlocksStateReplacement else {
            return
        }
        preferences.hasCompletedOnboarding = true
        preferences.focusDefaults.selectedApps = selectedApps
        enqueuePreferencesSave()
    }

    func updateFocusDefaults(_ defaults: FocusDefaults) {
        guard !terminalPersistenceBlocksStateReplacement else {
            return
        }
        preferences.focusDefaults = defaults
        enqueuePreferencesSave()
    }

    @discardableResult
    func recordSatisfaction(_ rating: Int) -> Bool {
        guard (1...5).contains(rating),
              var summary = completedSummary else {
            return false
        }

        summary.satisfaction = rating
        state = .completed(summary)
        enqueuePersistence(.terminal(summary, summary.id))
        return true
    }

    @discardableResult
    func acknowledgeCompletion() -> Bool {
        guard let summary = completedSummary,
              terminalPersistenceStatus == .committed(sessionID: summary.id) else {
            return false
        }

        preferences.focusDefaults.mode = summary.configuration.mode
        state = .idle
        runtime = SessionRuntime()
        terminalPersistenceStatus = .none
        completionReminderPresenter.dismiss()
        enqueuePreferencesSave()
        return true
    }

    func stopWorkspaceObservation() {
        workspaceObservationTask?.cancel()
        workspaceObservationTask = nil
        isWorkspaceObservationActive = false
    }

    func handleWorkspaceEvent(_ event: WorkspaceEvent) {
        switch event {
        case let .activated(application):
            guard application.bundleIdentifier != selfBundleIdentifier else {
                return
            }
            guard let session = runningSession else {
                return
            }
            send(.applicationActivated(
                sessionID: session.id,
                application: application,
                wallTime: wallClock.now(),
                elapsedTime: elapsedClock.now()
            ))

        case let .deactivated(bundleIdentifier), let .terminated(bundleIdentifier):
            guard let session = runningSession else {
                return
            }
            send(.applicationDeactivated(
                sessionID: session.id,
                bundleIdentifier: bundleIdentifier,
                wallTime: wallClock.now(),
                elapsedTime: elapsedClock.now()
            ))
            updateModeWork()

        case .activeSpaceChanged, .screenParametersChanged:
            reconcileFrontmostApplication()

        case .systemClockChanged:
            synchronizeWallDeadline(persistBoundary: true)

        case .screensDidSleep:
            enterSuspension(.screens)

        case .willSleep:
            enterSuspension(.system)

        case .sessionResigned:
            enterSuspension(.userSession)

        case .screensDidWake:
            leaveSuspension(.screens)

        case .didWake:
            leaveSuspension(.system)

        case .sessionBecameActive:
            leaveSuspension(.userSession)

        case .launched:
            reconcileStrictApplications()
        }
    }

    func returnToFocus() {
        guard let session = runningSession else {
            return
        }
        switch session.configuration.mode {
        case .soft:
            send(.softReturnRequested(
                sessionID: session.id,
                wallTime: wallClock.now(),
                elapsedTime: elapsedClock.now()
            ))
        case .medium:
            send(.mediumReturnRequested(
                sessionID: session.id,
                wallTime: wallClock.now()
            ))
        case .strict:
            break
        }
    }

    func openAnyway() {
        guard softOpenAvailable, let session = runningSession else {
            return
        }
        send(.softOpenRequested(
            sessionID: session.id,
            wallTime: wallClock.now(),
            elapsedTime: elapsedClock.now()
        ))
    }

    func useMediumAllowance() {
        guard mediumUseAvailable, let session = runningSession else {
            return
        }
        send(.mediumUseAllowanceRequested(
            sessionID: session.id,
            wallTime: wallClock.now(),
            elapsedTime: elapsedClock.now()
        ))
        updateModeWork()
    }

    func requestGoalReview() {
        guard let session = runningSession,
              case .goal = session.configuration.completion else {
            return
        }
        guard ensureDeadlineHasNotPassed(for: session) else {
            return
        }

        cancelStopChallenge()
        let now = elapsedClock.now()
        let delay = goalReviewDelay(for: session.configuration.mode)
        goalReview = GoalReviewState(
            sessionID: session.id,
            requestedAt: now,
            unlockAt: now + delay,
            isUnlocked: false,
            isPaused: !suspensionReasons.isEmpty
        )
        goalRemainingWhenPaused = suspensionReasons.isEmpty ? nil : delay
        if suspensionReasons.isEmpty {
            scheduleGoalGate(after: delay, sessionID: session.id)
        }
    }

    func cancelGoalReview() {
        goalGateTask?.cancel()
        goalGateTask = nil
        goalReview = nil
        goalRemainingWhenPaused = nil
    }

    func confirmGoalCompletion() {
        guard let review = goalReview,
              review.isUnlocked,
              let session = runningSession,
              session.id == review.sessionID else {
            return
        }
        send(.goalCompletionConfirmed(
            sessionID: session.id,
            wallTime: wallClock.now()
        ))
    }

    func requestStop(intent: StopIntent = .endFocus) {
        guard let session = activeSession else {
            return
        }
        if session.status == .running, !ensureDeadlineHasNotPassed(for: session) {
            return
        }

        if var existing = stopChallenge, existing.sessionID == session.id {
            if intent == .quit {
                existing.intent = .quit
                stopChallenge = existing
            }
            return
        }

        cancelGoalReview()
        let now = elapsedClock.now()
        let delay = stopDelay(for: session.configuration.mode)
        stopChallenge = StopChallenge(
            sessionID: session.id,
            intent: intent,
            requestedAt: now,
            unlockAt: now + delay,
            selectedReason: nil,
            isUnlocked: false,
            isPaused: !suspensionReasons.isEmpty
        )
        stopRemainingWhenPaused = suspensionReasons.isEmpty ? nil : delay
        if suspensionReasons.isEmpty {
            scheduleStopGate(after: delay, sessionID: session.id)
        }
    }

    func selectStopReason(_ reason: EarlyStopReason) {
        guard var challenge = stopChallenge else {
            return
        }
        challenge.selectedReason = reason
        stopChallenge = challenge
    }

    func keepFocusing() {
        cancelStopChallenge()
    }

    func confirmStop() {
        guard let challenge = stopChallenge,
              challenge.isUnlocked,
              let reason = challenge.selectedReason,
              let session = activeSession,
              session.id == challenge.sessionID else {
            return
        }

        if session.status == .interrupted {
            publishInterruptedOutcome(for: session, at: wallClock.now())
            return
        }

        send(.earlyStopConfirmed(
            sessionID: session.id,
            reason: reason,
            wallTime: wallClock.now()
        ))
    }

    func resumeInterruptedSession() {
        guard case let .awaitingDecision(sessionID) = interruptionState,
              let interrupted = activeSession,
              interrupted.id == sessionID,
              interrupted.status == .interrupted else {
            return
        }

        guard interrupted.lastKnownRemainingSeconds > 0 else {
            publishInterruptedOutcome(for: interrupted, at: wallClock.now())
            return
        }

        beginNewSessionGeneration()
        let now = wallClock.now()
        let resumed = RunningSession(
            id: interrupted.id,
            configuration: interrupted.configuration,
            startedAt: interrupted.startedAt,
            deadline: now.addingTimeInterval(
                TimeInterval(interrupted.lastKnownRemainingSeconds)
            ),
            lastKnownRemainingSeconds: interrupted.lastKnownRemainingSeconds,
            mediumConsumedSeconds: interrupted.mediumConsumedSeconds,
            wasInterrupted: true,
            status: .running,
            metrics: interrupted.metrics
        )
        state = .active(resumed)
        runtime = SessionRuntime()
        interruptionState = .none
        scheduleDeadline(for: resumed)
        enqueueStateSave(resumed)
        startWorkspaceObservation()
        reconcileFrontmostApplication()
        updateModeWork()
    }

    func retryPersistence() {
        if let pendingPersistence {
            switch pendingPersistence {
            case let .state(document):
                enqueuePersistence(.state(document))
            case let .terminal(summary, sessionID):
                enqueuePersistence(.terminal(summary, sessionID))
            }
            return
        }

        if let session = activeSession {
            enqueueStateSave(session)
        }
    }

    func waitForPendingPersistence() async -> ControllerPersistenceStatus {
        let task = persistenceTail
        await task?.value
        return persistenceStatus
    }

    private var runningSession: RunningSession? {
        guard let session = activeSession, session.status == .running else {
            return nil
        }
        return session
    }

    private var terminalPersistenceBlocksStateReplacement: Bool {
        switch terminalPersistenceStatus {
        case .committing, .failed:
            true
        case .none, .committed:
            false
        }
    }

    private func send(_ event: SessionEvent) {
        let reduction = SessionReducer.reduce(
            state: state,
            runtime: runtime,
            event: event
        )

        state = reduction.state
        runtime = reduction.runtime

        var persistenceEffects: [SessionEffect] = []
        var followUpEvents: [SessionEvent] = []
        for effect in reduction.effects {
            switch effect {
            case .enqueuePersistence, .commitTerminal:
                persistenceEffects.append(effect)
            default:
                if let followUp = execute(effect) {
                    followUpEvents.append(followUp)
                }
            }
        }

        for effect in persistenceEffects {
            _ = execute(effect)
        }
        for followUp in followUpEvents {
            send(followUp)
        }
        updateModeWork()
    }

    private func execute(_ effect: SessionEffect) -> SessionEvent? {
        switch effect {
        case let .scheduleDeadline(sessionID, deadline):
            guard let session = runningSession,
                  session.id == sessionID,
                  session.deadline == deadline else {
                return nil
            }
            scheduleDeadline(for: session)

        case let .cancelSessionWork(sessionID):
            cancelSessionWork(for: sessionID)

        case let .attemptSoftReturn(
            sessionID,
            bundleIdentifier,
            fallbackBundleIdentifier
        ):
            guard isCurrentRunningSession(sessionID) else {
                return nil
            }
            let applicationController = applicationController
            let wallClock = wallClock
            let generation = sessionGeneration
            Task { @MainActor [weak self, applicationController, wallClock] in
                let hideResult = await applicationController.hide(
                    bundleIdentifier: bundleIdentifier
                )
                guard let self,
                      self.sessionGeneration == generation,
                      self.isCurrentRunningSession(sessionID) else {
                    return
                }

                let result: SoftReturnHideResult
                switch hideResult.summary {
                case .succeeded:
                    result = .hidden
                case .missingApplication:
                    result = .applicationEnded
                case .protectedApplication,
                     .noNewProcesses,
                     .partiallySucceeded,
                     .failed:
                    result = .failed
                }
                self.send(.softReturnHideCompleted(
                    sessionID: sessionID,
                    bundleIdentifier: bundleIdentifier,
                    fallbackBundleIdentifier: fallbackBundleIdentifier,
                    result: result,
                    wallTime: wallClock.now()
                ))
            }

        case let .reactivateApplication(sessionID, bundleIdentifier):
            guard isCurrentRunningSession(sessionID) else {
                return nil
            }
            let result = applicationController.activateRecoveryTarget(
                bundleIdentifier: bundleIdentifier
            )
            if result.summary != .succeeded,
               result.summary != .partiallySucceeded {
                return .returnTargetActivationFailed(
                    sessionID: sessionID,
                    wallTime: wallClock.now()
                )
            }

        case let .presentSoftIntervention(intervention):
            guard isCurrentRunningSession(intervention.sessionID) else {
                return nil
            }
            if softGateIntervention != intervention {
                beginSoftGate(for: intervention)
            }
            presentSoftIntervention(intervention)

        case let .attemptMediumInterventionHide(intervention):
            guard isCurrentRunningSession(intervention.sessionID) else {
                return nil
            }
            let applicationController = applicationController
            let wallClock = wallClock
            let generation = sessionGeneration
            Task { @MainActor [weak self, applicationController, wallClock] in
                let hide = await applicationController.hide(
                    bundleIdentifier: intervention.application.bundleIdentifier
                )
                guard let self,
                      self.sessionGeneration == generation,
                      self.isCurrentRunningSession(intervention.sessionID) else {
                    return
                }
                self.send(.mediumInterventionHideCompleted(
                    sessionID: intervention.sessionID,
                    bundleIdentifier: intervention.application.bundleIdentifier,
                    result: Self.enforcementHideResult(hide.summary),
                    wallTime: wallClock.now()
                ))
            }

        case let .presentMediumIntervention(intervention):
            guard isCurrentRunningSession(intervention.sessionID) else {
                return nil
            }
            if mediumGateIntervention != intervention {
                beginMediumGate(for: intervention)
            }
            presentMediumIntervention(intervention)

        case let .enforceSelectedApplication(
            sessionID,
            application,
            fallbackBundleIdentifier,
            excludingProcessIdentifiers,
            presentsStatus
        ):
            beginEnforcement(
                sessionID: sessionID,
                application: application,
                fallbackBundleIdentifier: fallbackBundleIdentifier,
                excludingProcessIdentifiers: excludingProcessIdentifiers,
                presentsStatus: presentsStatus
            )

        case let .presentEnforcementStatus(
            sessionID,
            application,
            hideFailed,
            stillRunning
        ):
            presentEnforcementStatus(
                sessionID: sessionID,
                application: application,
                hideFailed: hideFailed,
                stillRunning: stillRunning
            )

        case .dismissIntervention:
            dismissIntervention()

        case let .presentCompletionReminder(summary):
            presentCompletionReminder(summary)

        case let .enqueuePersistence(session):
            enqueueStateSave(session)

        case let .commitTerminal(summary, sessionID):
            enqueuePersistence(.terminal(summary, sessionID))
        }
        return nil
    }

    private func presentSoftIntervention(_ intervention: SessionIntervention) {
        guard let session = runningSession,
              session.id == intervention.sessionID else {
            return
        }

        let generation = sessionGeneration
        let secondaryStatus: String
        if softOpenAvailable {
            secondaryStatus = "Open Anyway is now available."
        } else {
            let remaining = softRemainingWhenPaused
                ?? softUnlockAt.map { max(.zero, $0 - elapsedClock.now()) }
                ?? Self.softOpenDelay
            secondaryStatus = "Open Anyway is available in \(wholeSecondsRoundedUp(remaining)) seconds."
        }
        let applicationName = intervention.application.displayName
        let returnFailed = runtime.softReturnFailed
        let intent = OverlayIntent(
            interventionID: OverlayInterventionID(
                sessionID: intervention.sessionID,
                bundleIdentifier: intervention.application.bundleIdentifier,
                presentedAt: intervention.presentedAt
            ),
            compactTitle: "Focus check: \(applicationName)",
            title: returnFailed ? "Couldn’t return yet" : "You chose to focus",
            message: returnFailed
                ? "Attune couldn’t hide \(applicationName)."
                : "\(applicationName) is outside “\(session.configuration.intention)”.",
            symbolName: returnFailed ? "exclamationmark.triangle.fill" : "sparkles",
            primaryActionDetail: returnFailed
                ? "Try Return to Focus again. Attune will never quit \(applicationName)."
                : "Attune won’t hide \(applicationName) unless you choose Return to Focus.",
            primaryActionTitle: "Return to Focus",
            secondaryActionTitle: "Open Anyway",
            secondaryActionStatus: secondaryStatus,
            isSecondaryActionEnabled: softOpenAvailable,
            tone: returnFailed ? .warning : .standard
        )
        overlayPresenter.present(
            intent,
            onAction: { [weak self] action in
                guard let self,
                      self.sessionGeneration == generation,
                      self.runtime.intervention == intervention else {
                    return
                }
                switch action {
                case .primary:
                    self.returnToFocus()
                case .secondary:
                    self.openAnyway()
                case .tertiary:
                    break
                }
            }
        )
    }

    private func beginSoftGate(for intervention: SessionIntervention) {
        softGateTask?.cancel()
        softGateIntervention = intervention
        softOpenAvailable = false
        let now = elapsedClock.now()
        let remaining = max(
            .zero,
            intervention.presentedAt + Self.softOpenDelay - now
        )
        softUnlockAt = now + remaining
        softRemainingWhenPaused = suspensionReasons.isEmpty ? nil : remaining
        if suspensionReasons.isEmpty {
            scheduleSoftGate(after: remaining, intervention: intervention)
        }
    }

    private func beginMediumGate(for intervention: SessionIntervention) {
        mediumGateTask?.cancel()
        mediumGateIntervention = intervention
        mediumUseAvailable = false
        let now = elapsedClock.now()
        let remaining = max(
            .zero,
            intervention.presentedAt + Self.mediumUseDelay - now
        )
        mediumUnlockAt = now + remaining
        mediumRemainingWhenPaused = suspensionReasons.isEmpty ? nil : remaining
        if suspensionReasons.isEmpty {
            scheduleMediumGate(after: remaining, intervention: intervention)
        }
    }

    private func scheduleMediumGate(
        after delay: Duration,
        intervention: SessionIntervention
    ) {
        let clock = elapsedClock
        let generation = sessionGeneration
        let unlockAt = clock.now() + delay
        var displayedSeconds = wholeSecondsRoundedUp(delay)
        mediumUnlockAt = unlockAt
        mediumGateTask = Task { @MainActor [weak self, clock] in
            while true {
                let remaining = max(.zero, unlockAt - clock.now())
                guard remaining > .zero else {
                    break
                }
                do {
                    try await clock.sleep(for: min(.seconds(1), remaining))
                } catch {
                    return
                }
                guard let self,
                      self.sessionGeneration == generation,
                      self.suspensionReasons.isEmpty,
                      self.mediumGateIntervention == intervention,
                      self.runtime.intervention == intervention else {
                    return
                }

                let updatedRemaining = max(.zero, unlockAt - clock.now())
                let updatedSeconds = self.wholeSecondsRoundedUp(updatedRemaining)
                if updatedRemaining > .zero, updatedSeconds != displayedSeconds {
                    displayedSeconds = updatedSeconds
                    self.presentMediumIntervention(intervention)
                }
            }
            guard let self,
                  self.sessionGeneration == generation,
                  self.suspensionReasons.isEmpty,
                  self.mediumGateIntervention == intervention,
                  self.runtime.intervention == intervention else {
                return
            }
            self.mediumGateTask = nil
            self.mediumUseAvailable = true
            self.mediumUnlockAt = nil
            self.mediumRemainingWhenPaused = nil
            self.presentMediumIntervention(intervention)
        }
    }

    private func presentMediumIntervention(_ intervention: SessionIntervention) {
        guard let session = runningSession,
              session.id == intervention.sessionID,
              let remaining = mediumAllowanceRemainingSeconds else {
            return
        }
        let generation = sessionGeneration
        let status: String
        if mediumUseAvailable {
            status = "Use Allowance is now available."
        } else {
            let delay = mediumRemainingWhenPaused
                ?? mediumUnlockAt.map { max(.zero, $0 - elapsedClock.now()) }
                ?? Self.mediumUseDelay
            status = "Use Allowance is available in \(wholeSecondsRoundedUp(delay)) seconds."
        }
        overlayPresenter.present(
            OverlayIntent(
                interventionID: OverlayInterventionID(
                    sessionID: intervention.sessionID,
                    bundleIdentifier: intervention.application.bundleIdentifier,
                    presentedAt: intervention.presentedAt
                ),
                compactTitle: "Allowance check: \(intervention.application.displayName)",
                title: "Use your allowance?",
                message: "\(durationLabel(remaining)) remains across all selected apps — back to “\(session.configuration.intention)” or spend some now.",
                symbolName: "hourglass",
                primaryActionDetail: "Time counts only while a selected app is in the foreground.",
                primaryActionTitle: "Return to Focus",
                secondaryActionTitle: "Use Allowance",
                secondaryActionStatus: status,
                isSecondaryActionEnabled: mediumUseAvailable
            ),
            onAction: { [weak self] action in
                guard let self,
                      self.sessionGeneration == generation,
                      self.runtime.intervention == intervention else {
                    return
                }
                switch action {
                case .primary:
                    self.returnToFocus()
                case .secondary:
                    self.useMediumAllowance()
                case .tertiary:
                    break
                }
            }
        )
    }

    private func beginEnforcement(
        sessionID: UUID,
        application: AppIdentity,
        fallbackBundleIdentifier: String,
        excludingProcessIdentifiers: Set<Int32>,
        presentsStatus: Bool
    ) {
        guard isCurrentRunningSession(sessionID) else {
            return
        }
        let bundleIdentifier = application.bundleIdentifier
        if presentsStatus {
            enforcementStatusRequestedBundles.insert(bundleIdentifier)
            _ = applicationController.activateRecoveryTarget(
                bundleIdentifier: fallbackBundleIdentifier
            )
        }
        guard enforcementTasks[bundleIdentifier] == nil else { return }
        let applicationController = applicationController
        let wallClock = wallClock
        let generation = sessionGeneration
        enforcementTasks[bundleIdentifier] = Task { @MainActor [weak self, applicationController, wallClock] in
            let hide = await applicationController.hide(bundleIdentifier: bundleIdentifier)
            guard let self,
                  self.sessionGeneration == generation,
                  self.isCurrentRunningSession(sessionID) else {
                return
            }
            if !presentsStatus, hide.wasActiveBeforeHide {
                _ = applicationController.activateRecoveryTarget(
                    bundleIdentifier: fallbackBundleIdentifier
                )
            }
            let termination = await applicationController.requestNormalTermination(
                bundleIdentifier: bundleIdentifier,
                excludingProcessIdentifiers: excludingProcessIdentifiers
            )
            guard self.sessionGeneration == generation,
                  self.isCurrentRunningSession(sessionID) else {
                return
            }
            self.enforcementTasks[bundleIdentifier] = nil
            let shouldPresentStatus = self.enforcementStatusRequestedBundles.remove(
                bundleIdentifier
            ) != nil
            let attempted = Set(termination.processes.map(\.processIdentifier))
            self.send(.enforcementCompleted(
                sessionID: sessionID,
                application: application,
                attemptedProcessIdentifiers: attempted,
                hideResult: Self.enforcementHideResult(hide.summary),
                stillRunning: termination.processes.contains { $0.outcome == .stillRunning },
                presentsStatus: shouldPresentStatus,
                wallTime: wallClock.now()
            ))
        }
    }

    private func presentEnforcementStatus(
        sessionID: UUID,
        application: AppIdentity,
        hideFailed: Bool,
        stillRunning: Bool
    ) {
        guard let session = runningSession, session.id == sessionID else {
            return
        }
        let message: String
        if hideFailed {
            message = "Attune couldn’t keep \(application.displayName) hidden. Strict mode will keep trying quietly in the background."
        } else if stillRunning {
            message = "\(application.displayName) refused a normal quit and is hidden but still running. Attune will keep re-hiding it."
        } else if case let .medium(allowanceSeconds) = session.configuration.mode,
                  session.mediumConsumedSeconds < allowanceSeconds {
            message = "One minute of shared allowance remains."
        } else {
            message = "Back to “\(session.configuration.intention)”."
        }
        overlayPresenter.present(
            OverlayIntent(
                compactTitle: hideFailed ? "Couldn’t block \(application.displayName)" : "Blocked \(application.displayName)",
                title: hideFailed ? "Blocking needs attention" : "Blocked \(application.displayName)",
                message: message,
                symbolName: hideFailed ? "exclamationmark.triangle.fill" : "hand.raised.fill",
                primaryActionTitle: "Return to Focus",
                tone: hideFailed ? .warning : .standard
            ),
            onAction: { [weak self] _ in
                self?.overlayPresenter.dismiss()
            }
        )
    }

    private static func enforcementHideResult(
        _ summary: ApplicationCommandSummary
    ) -> EnforcementHideResult {
        switch summary {
        case .succeeded:
            .hidden
        case .missingApplication:
            .applicationEnded
        case .protectedApplication, .noNewProcesses, .partiallySucceeded, .failed:
            .failed
        }
    }

    private func durationLabel(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainder = seconds % 60
        if minutes > 0, remainder > 0 {
            return "\(minutes)m \(remainder)s"
        }
        if minutes > 0 {
            return "\(minutes) minute\(minutes == 1 ? "" : "s")"
        }
        return "\(remainder) second\(remainder == 1 ? "" : "s")"
    }

    private func scheduleSoftGate(
        after delay: Duration,
        intervention: SessionIntervention
    ) {
        let clock = elapsedClock
        let generation = sessionGeneration
        let unlockAt = clock.now() + delay
        var displayedSeconds = wholeSecondsRoundedUp(delay)
        softGateIntervention = intervention
        softUnlockAt = unlockAt
        softGateTask = Task { @MainActor [weak self, clock] in
            while true {
                let remaining = max(.zero, unlockAt - clock.now())
                guard remaining > .zero else {
                    break
                }
                do {
                    try await clock.sleep(for: min(.seconds(1), remaining))
                } catch {
                    return
                }
                guard let self,
                      self.sessionGeneration == generation,
                      self.suspensionReasons.isEmpty,
                      self.softGateIntervention == intervention,
                      self.runtime.intervention == intervention else {
                    return
                }

                let updatedRemaining = max(.zero, unlockAt - clock.now())
                let updatedSeconds = self.wholeSecondsRoundedUp(updatedRemaining)
                if updatedRemaining > .zero, updatedSeconds != displayedSeconds {
                    displayedSeconds = updatedSeconds
                    self.presentSoftIntervention(intervention)
                }
            }
            guard let self,
                  self.sessionGeneration == generation,
                  self.suspensionReasons.isEmpty,
                  self.softGateIntervention == intervention,
                  self.runtime.intervention == intervention else {
                return
            }
            self.softGateTask = nil
            self.softOpenAvailable = true
            self.softUnlockAt = nil
            self.softRemainingWhenPaused = nil
            self.presentSoftIntervention(intervention)
        }
    }

    private func dismissIntervention() {
        softGateTask?.cancel()
        softGateTask = nil
        softGateIntervention = nil
        softUnlockAt = nil
        softRemainingWhenPaused = nil
        softOpenAvailable = false
        mediumGateTask?.cancel()
        mediumGateTask = nil
        mediumGateIntervention = nil
        mediumUnlockAt = nil
        mediumRemainingWhenPaused = nil
        mediumUseAvailable = false
        overlayPresenter.dismiss()
    }

    private func presentCompletionReminder(_ summary: SessionSummary) {
        let title: String
        switch summary.outcome {
        case .timedComplete:
            title = "Focus complete"
        case .goalComplete:
            title = "Goal complete"
        case .goalWindowEnded, .endedEarly, .interrupted:
            return
        }

        completionReminderPresenter.present(CompletionReminderIntent(
            sessionID: summary.id,
            title: title,
            message: summary.configuration.intention
        ))
    }

    private func scheduleGoalGate(after delay: Duration, sessionID: UUID) {
        let clock = elapsedClock
        let generation = sessionGeneration
        let unlockAt = clock.now() + delay
        if var review = goalReview {
            review.unlockAt = unlockAt
            review.isPaused = false
            goalReview = review
        }
        goalGateTask = Task { @MainActor [weak self, clock] in
            do {
                try await clock.sleep(for: max(.zero, unlockAt - clock.now()))
            } catch {
                return
            }
            guard let self,
                  self.sessionGeneration == generation,
                  self.suspensionReasons.isEmpty,
                  var review = self.goalReview,
                  review.sessionID == sessionID else {
                return
            }
            review.isUnlocked = true
            review.isPaused = false
            self.goalReview = review
            self.goalGateTask = nil
            self.goalRemainingWhenPaused = nil
        }
    }

    private func scheduleStopGate(after delay: Duration, sessionID: UUID) {
        let clock = elapsedClock
        let generation = sessionGeneration
        let unlockAt = clock.now() + delay
        if var challenge = stopChallenge {
            challenge.unlockAt = unlockAt
            challenge.isPaused = false
            stopChallenge = challenge
        }
        stopGateTask = Task { @MainActor [weak self, clock] in
            do {
                try await clock.sleep(for: max(.zero, unlockAt - clock.now()))
            } catch {
                return
            }
            guard let self,
                  self.sessionGeneration == generation,
                  self.suspensionReasons.isEmpty,
                  var challenge = self.stopChallenge,
                  challenge.sessionID == sessionID else {
                return
            }
            challenge.isUnlocked = true
            challenge.isPaused = false
            self.stopChallenge = challenge
            self.stopGateTask = nil
            self.stopRemainingWhenPaused = nil
        }
    }

    private func cancelStopChallenge() {
        stopGateTask?.cancel()
        stopGateTask = nil
        stopChallenge = nil
        stopRemainingWhenPaused = nil
    }

    private func enterSuspension(_ reason: SuspensionReason) {
        let wasActive = !suspensionReasons.isEmpty
        suspensionReasons.insert(reason)
        if !wasActive, let session = runningSession {
            mediumMeterTask?.cancel()
            mediumMeterTask = nil
            send(.mediumMeterSuspended(
                sessionID: session.id,
                wallTime: wallClock.now(),
                elapsedTime: elapsedClock.now()
            ))
        }
        persistActiveBoundary()
        guard !wasActive else {
            return
        }
        pauseElapsedGates()
    }

    private func leaveSuspension(_ reason: SuspensionReason) {
        suspensionReasons.remove(reason)
        guard suspensionReasons.isEmpty else {
            return
        }
        if let session = runningSession {
            send(.mediumMeterResumed(
                sessionID: session.id,
                wallTime: wallClock.now(),
                elapsedTime: elapsedClock.now()
            ))
        }
        resumeElapsedGates()
        synchronizeWallDeadline(persistBoundary: true)
        reconcileFrontmostApplication()
    }

    private func pauseElapsedGates() {
        let now = elapsedClock.now()
        if !softOpenAvailable, let softUnlockAt {
            softRemainingWhenPaused = max(.zero, softUnlockAt - now)
            softGateTask?.cancel()
            softGateTask = nil
        }
        if var review = goalReview, !review.isUnlocked {
            goalRemainingWhenPaused = max(.zero, review.unlockAt - now)
            review.isPaused = true
            goalReview = review
            goalGateTask?.cancel()
            goalGateTask = nil
        }
        if var challenge = stopChallenge, !challenge.isUnlocked {
            stopRemainingWhenPaused = max(.zero, challenge.unlockAt - now)
            challenge.isPaused = true
            stopChallenge = challenge
            stopGateTask?.cancel()
            stopGateTask = nil
        }
        if !mediumUseAvailable, let mediumUnlockAt {
            mediumRemainingWhenPaused = max(.zero, mediumUnlockAt - now)
            mediumGateTask?.cancel()
            mediumGateTask = nil
        }
    }

    private func resumeElapsedGates() {
        if let remaining = softRemainingWhenPaused,
           let intervention = runtime.intervention {
            softRemainingWhenPaused = nil
            scheduleSoftGate(after: remaining, intervention: intervention)
        }
        if let remaining = goalRemainingWhenPaused,
           let review = goalReview {
            goalRemainingWhenPaused = nil
            scheduleGoalGate(after: remaining, sessionID: review.sessionID)
        }
        if let remaining = stopRemainingWhenPaused,
           let challenge = stopChallenge {
            stopRemainingWhenPaused = nil
            scheduleStopGate(after: remaining, sessionID: challenge.sessionID)
        }
        if let remaining = mediumRemainingWhenPaused,
           let intervention = runtime.intervention {
            mediumRemainingWhenPaused = nil
            scheduleMediumGate(after: remaining, intervention: intervention)
        }
    }

    private func scheduleDeadline(for session: RunningSession) {
        deadlineTask?.cancel()
        snapshotTask?.cancel()
        let wallClock = wallClock
        let generation = sessionGeneration
        let sessionID = session.id
        let deadline = session.deadline
        deadlineTask = Task { @MainActor [weak self, wallClock] in
            do {
                try await wallClock.sleep(until: deadline)
            } catch {
                return
            }
            guard let self,
                  self.sessionGeneration == generation,
                  self.isCurrentRunningSession(sessionID) else {
                return
            }
            self.send(.deadlineReached(
                sessionID: sessionID,
                wallTime: wallClock.now()
            ))
            if self.isCurrentRunningSession(sessionID) {
                self.scheduleDeadlineForRollback(sessionID: sessionID)
            }
        }
        scheduleSnapshotLoop(sessionID: sessionID, generation: generation)
    }

    private func scheduleDeadlineForRollback(sessionID: UUID) {
        guard let session = runningSession, session.id == sessionID else {
            return
        }
        scheduleDeadline(for: session)
    }

    private func scheduleSnapshotLoop(sessionID: UUID, generation: UInt64) {
        let elapsedClock = elapsedClock
        snapshotTask = Task { @MainActor [weak self, elapsedClock] in
            while !Task.isCancelled {
                do {
                    try await elapsedClock.sleep(for: Self.snapshotInterval)
                } catch {
                    return
                }
                guard let self,
                      self.sessionGeneration == generation,
                      self.isCurrentRunningSession(sessionID) else {
                    return
                }
                self.updateRemainingAndPersist(force: true)
            }
        }
    }

    private func synchronizeWallDeadline(persistBoundary: Bool) {
        guard let session = runningSession else {
            return
        }
        if wallClock.now() >= session.deadline {
            send(.deadlineReached(sessionID: session.id, wallTime: wallClock.now()))
            return
        }
        updateRemainingAndPersist(force: persistBoundary)
        if let current = runningSession, current.id == session.id {
            scheduleDeadline(for: current)
        }
    }

    @discardableResult
    private func ensureDeadlineHasNotPassed(for session: RunningSession) -> Bool {
        let now = wallClock.now()
        guard now < session.deadline else {
            send(.deadlineReached(sessionID: session.id, wallTime: now))
            return false
        }
        return true
    }

    private func updateRemainingAndPersist(force: Bool) {
        guard var session = runningSession else {
            return
        }
        let now = wallClock.now()
        guard now < session.deadline else {
            send(.deadlineReached(sessionID: session.id, wallTime: now))
            return
        }

        let calculated = max(
            0,
            Int(session.deadline.timeIntervalSince(now).rounded(.up))
        )
        let remaining = min(session.lastKnownRemainingSeconds, calculated)
        let changed = remaining != session.lastKnownRemainingSeconds
        session.lastKnownRemainingSeconds = remaining
        state = .active(session)
        if force || changed {
            enqueueStateSave(session)
        }
    }

    private func persistActiveBoundary() {
        guard runningSession != nil else {
            return
        }
        updateRemainingAndPersist(force: true)
    }

    private func reconcileFrontmostApplication() {
        guard let session = runningSession else {
            return
        }
        frontmostReconciliationTask?.cancel()
        let workspaceClient = workspaceClient
        let generation = sessionGeneration
        let sessionID = session.id
        frontmostReconciliationTask = Task { @MainActor [weak self, workspaceClient] in
            let application = await workspaceClient.frontmostApplication()
            guard !Task.isCancelled,
                  let self,
                  self.sessionGeneration == generation,
                  self.isCurrentRunningSession(sessionID),
                  let application else {
                return
            }
            self.handleWorkspaceEvent(.activated(application))
        }
    }

    private func updateModeWork() {
        guard let session = runningSession else {
            mediumMeterTask?.cancel()
            mediumMeterTask = nil
            strictReconciliationTask?.cancel()
            strictReconciliationTask = nil
            return
        }

        if runtime.mediumForegroundBundleIdentifier != nil,
           suspensionReasons.isEmpty {
            startMediumMeterIfNeeded(sessionID: session.id)
        } else {
            mediumMeterTask?.cancel()
            mediumMeterTask = nil
        }

        let strictActive: Bool
        switch session.configuration.mode {
        case .strict:
            strictActive = true
        case let .medium(allowanceSeconds):
            strictActive = session.mediumConsumedSeconds >= allowanceSeconds
        case .soft:
            strictActive = false
        }
        if strictActive {
            startStrictReconciliationIfNeeded(sessionID: session.id)
        } else {
            strictReconciliationTask?.cancel()
            strictReconciliationTask = nil
        }
    }

    private func startMediumMeterIfNeeded(sessionID: UUID) {
        guard mediumMeterTask == nil else { return }
        let clock = elapsedClock
        let generation = sessionGeneration
        mediumMeterTask = Task { @MainActor [weak self, clock] in
            while !Task.isCancelled {
                do {
                    try await clock.sleep(for: .seconds(1))
                } catch {
                    return
                }
                guard let self,
                      self.sessionGeneration == generation,
                      self.isCurrentRunningSession(sessionID),
                      self.suspensionReasons.isEmpty else {
                    return
                }
                self.send(.mediumMeterCheckpoint(
                    sessionID: sessionID,
                    wallTime: self.wallClock.now(),
                    elapsedTime: clock.now()
                ))
            }
        }
    }

    private func startStrictReconciliationIfNeeded(sessionID: UUID) {
        guard strictReconciliationTask == nil else { return }
        let clock = elapsedClock
        let generation = sessionGeneration
        strictReconciliationTask = Task { @MainActor [weak self, clock] in
            while !Task.isCancelled {
                do {
                    try await clock.sleep(for: Self.strictReconciliationInterval)
                } catch {
                    return
                }
                guard let self,
                      self.sessionGeneration == generation,
                      self.isCurrentRunningSession(sessionID) else {
                    return
                }
                self.reconcileStrictApplications()
            }
        }
    }

    private func reconcileStrictApplications() {
        guard let session = runningSession else { return }
        send(.strictReconciliationRequested(
            sessionID: session.id,
            wallTime: wallClock.now(),
            elapsedTime: elapsedClock.now()
        ))
    }

    private func publishInterruptedOutcome(for session: RunningSession, at endedAt: Date) {
        let summary = SessionSummary(
            id: session.id,
            outcome: .interrupted,
            startedAt: session.startedAt,
            endedAt: endedAt,
            configuration: session.configuration,
            mediumConsumedSeconds: session.mediumConsumedSeconds,
            wasInterrupted: true,
            metrics: session.metrics,
            earlyStopReason: nil,
            satisfaction: nil
        )
        state = .completed(summary)
        runtime = SessionRuntime()
        interruptionState = .none
        cancelSessionWork(for: session.id)
        enqueuePersistence(.terminal(summary, session.id))
    }

    private func beginNewSessionGeneration() {
        sessionGeneration &+= 1
        cancelScheduledSessionTasks()
        completionReminderPresenter.dismiss()
        runtime = SessionRuntime()
        interruptionState = .none
        suspensionReasons = []
    }

    private func cancelSessionWork(for sessionID: UUID) {
        if activeSession?.id != sessionID {
            sessionGeneration &+= 1
        }
        cancelScheduledSessionTasks()
    }

    private func cancelScheduledSessionTasks() {
        deadlineTask?.cancel()
        deadlineTask = nil
        snapshotTask?.cancel()
        snapshotTask = nil
        frontmostReconciliationTask?.cancel()
        frontmostReconciliationTask = nil
        mediumMeterTask?.cancel()
        mediumMeterTask = nil
        strictReconciliationTask?.cancel()
        strictReconciliationTask = nil
        enforcementTasks.values.forEach { $0.cancel() }
        enforcementTasks.removeAll()
        enforcementStatusRequestedBundles.removeAll()
        cancelGoalReview()
        cancelStopChallenge()
        dismissIntervention()
        suspensionReasons = []
    }

    private func isCurrentRunningSession(_ sessionID: UUID) -> Bool {
        runningSession?.id == sessionID
    }

    private func enqueueStateSave(_ session: RunningSession) {
        let document = AppStateDocument(
            preferences: preferences,
            activeSession: session
        )
        enqueuePersistence(.state(document))
    }

    private func enqueuePreferencesSave() {
        enqueuePersistence(.state(AppStateDocument(
            preferences: preferences,
            activeSession: activeSession
        )))
    }

    private func enqueuePersistence(_ request: PendingPersistence) {
        persistenceSequence &+= 1
        let sequence = persistenceSequence
        let previous = persistenceTail
        let repository = repository
        pendingPersistence = request
        persistenceStatus = .saving

        if case let .terminal(summary, _) = request {
            terminalPersistenceStatus = .committing(sessionID: summary.id)
        }

        persistenceTail = Task { @MainActor [weak self, repository, previous] in
            await previous?.value
            do {
                switch request {
                case let .state(document):
                    try await repository.saveState(document)
                case let .terminal(summary, sessionID):
                    try await repository.commitTerminal(summary, clearing: sessionID)
                }
                guard let self else {
                    return
                }
                self.persistenceDidSucceed(request, sequence: sequence)
            } catch {
                guard let self else {
                    return
                }
                self.persistenceDidFail(request, error: error, sequence: sequence)
            }
        }
    }

    private func persistenceDidSucceed(
        _ request: PendingPersistence,
        sequence: UInt64
    ) {
        if case let .terminal(summary, _) = request {
            terminalPersistenceStatus = .committed(sessionID: summary.id)
        }
        guard sequence == persistenceSequence else {
            return
        }
        pendingPersistence = nil
        persistenceStatus = .saved
    }

    private func persistenceDidFail(
        _ request: PendingPersistence,
        error: any Error,
        sequence: UInt64
    ) {
        if case let .terminal(summary, _) = request {
            terminalPersistenceStatus = .failed(sessionID: summary.id)
        }
        guard sequence == persistenceSequence else {
            return
        }
        pendingPersistence = request
        let operation: ControllerPersistenceOperation
        switch request {
        case .state:
            operation = .activeSession
        case .terminal:
            operation = .terminalOutcome
        }
        recordPersistenceFailure(error, operation: operation)
    }

    private func recordPersistenceFailure(
        _ error: any Error,
        operation: ControllerPersistenceOperation
    ) {
        persistenceStatus = .failed(ControllerPersistenceFailure(
            operation: operation,
            message: String(describing: error)
        ))
    }

    private func goalReviewDelay(for mode: FocusMode) -> Duration {
        switch mode {
        case .soft:
            .seconds(3)
        case .medium:
            .seconds(10)
        case .strict:
            .seconds(30)
        }
    }

    private func stopDelay(for mode: FocusMode) -> Duration {
        switch mode {
        case .soft:
            .seconds(10)
        case .medium:
            .seconds(30)
        case .strict:
            .seconds(60)
        }
    }

    private func wholeSecondsRoundedUp(_ duration: Duration) -> Int {
        let components = duration.components
        let seconds = Double(components.seconds)
            + Double(components.attoseconds) / 1_000_000_000_000_000_000
        return max(0, Int(seconds.rounded(.up)))
    }
}

private extension SessionController {
    enum PendingPersistence: Sendable {
        case state(AppStateDocument)
        case terminal(SessionSummary, UUID)
    }

    enum SuspensionReason: Hashable {
        case screens
        case system
        case userSession
    }
}
