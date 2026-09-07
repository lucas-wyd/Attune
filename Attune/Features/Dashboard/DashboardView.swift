import AppKit
import SwiftUI

struct DashboardView: View {
    @ObservedObject var model: AppModel
    let environment: AppEnvironment

    private var controller: SessionController {
        environment.sessionController
    }

    var body: some View {
        #if DEBUG
        if environment.debugLaunchConfiguration.adapterLabEnabled {
            AdapterLabView(environment: environment)
        } else {
            product
        }
        #else
        product
        #endif
    }

    private var product: some View {
        productContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task {
                await controller.initialize()
            }
            .alert(
                "macOS Force Quit is always available",
                isPresented: $model.isForceQuitHelpPresented
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(
                    "If you need to stop Attune immediately, press Option-Command-Escape and use macOS Force Quit. This emergency path can interrupt recovery, so ordinary End Focus is safer when you can use it."
                )
            }
    }

    @ViewBuilder
    private var productContent: some View {
        if !controller.isInitialized {
            loadingView
        } else if !controller.preferences.hasCompletedOnboarding {
            onboardingView
        } else if let challenge = controller.stopChallenge,
                  let session = controller.activeSession {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                stopView(session: session, challenge: challenge, now: context.date)
            }
        } else if case .awaitingDecision = controller.interruptionState,
                  let session = controller.activeSession {
            interruptedView(session: session)
        } else if let review = controller.goalReview,
                  let session = controller.activeSession {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                goalReviewView(session: session, review: review)
            }
        } else if let summary = controller.completedSummary {
            completionView(summary: summary)
        } else if let session = controller.activeSession {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                activeSessionView(session: session, now: context.date)
            }
        } else if model.isPresentingFocusSetup {
            focusSetupView
        } else {
            idleDashboard
        }
    }

    private var loadingView: some View {
        ZStack {
            AttunePageBackground()
            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                Text("Restoring Attune…")
                    .font(.headline)
                Text("Your focus data stays on this Mac.")
                    .font(.callout)
                    .foregroundStyle(AttuneTheme.muted)
            }
            .foregroundStyle(AttuneTheme.ink)
        }
        .accessibilityIdentifier("attune-loading")
    }

    private var onboardingView: some View {
        OnboardingView(
            selectedApps: $model.onboardingSelectedApps,
            applicationPicker: environment.applicationPicker,
            onQuit: {
                NSApplication.shared.terminate(nil)
            },
            onCreateFirstFocus: {
                let selectedApps = model.onboardingSelectedApps
                controller.completeOnboarding(selectedApps: selectedApps)
                model.beginFirstFocus(selectedApps: selectedApps)
            },
            onExploreAttune: {
                controller.completeOnboarding(
                    selectedApps: model.onboardingSelectedApps
                )
                model.dismissFocusSetup()
            }
        )
    }

    private var focusSetupView: some View {
        FocusSetupView(
            draft: $model.focusDraft,
            browserWarningAcknowledged: $model.browserWarningAcknowledged,
            applicationPicker: environment.applicationPicker,
            runningApplications: environment.runningApplications,
            timerDefaultSeconds: controller.preferences.focusDefaults.timerDurationSeconds,
            goalSafetyDefaultSeconds: controller.preferences.focusDefaults.goalSafetyDurationSeconds,
            mediumAllowanceDefaultSeconds: controller.preferences.focusDefaults.mediumAllowanceSeconds,
            onCancel: model.dismissFocusSetup,
            onStart: { configuration in
                guard controller.start(configuration) != nil else {
                    return
                }
                controller.updateFocusDefaults(defaults(afterStarting: configuration))
                model.focusDidStart()
            }
        )
    }

    private var idleDashboard: some View {
        ZStack {
            AttunePageBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Choose your focus.")
                                .font(.system(size: 42, weight: .medium, design: .serif))
                                .accessibilityAddTraits(.isHeader)
                                .accessibilityIdentifier("dashboard-title")

                            Text(
                                "Attune puts a calm pause between an impulse and the applications you choose."
                            )
                            .font(.title3)
                            .foregroundStyle(AttuneTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()

                        Button("New Focus") {
                            model.beginFocusSetup(
                                using: controller.preferences.focusDefaults
                            )
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AttuneTheme.ink)
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("dashboard-new-focus")
                    }

                    AttuneCard {
                        VStack(alignment: .leading, spacing: 14) {
                            Label("Soft — Pause", systemImage: "pause.circle.fill")
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(AttuneTheme.lavender)

                            Text(
                                "If a selected app comes forward, Attune reminds you what you chose. Return immediately, or wait 8 seconds to open it anyway."
                            )
                            .foregroundStyle(AttuneTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)

                            HStack(spacing: 12) {
                                Label("Local only", systemImage: "internaldrive")
                                Label("No screenshots", systemImage: "rectangle.slash")
                                Label("No force-closing", systemImage: "hand.raised")
                            }
                            .font(.caption.weight(.medium))
                            .foregroundStyle(AttuneTheme.sage)
                        }
                    }

                    HStack(spacing: 12) {
                        modeCard(
                            title: "Medium — Budget",
                            symbol: "hourglass",
                            message: "Spend one shared allowance across selected apps, then switch to Strict behavior."
                        )
                        modeCard(
                            title: "Strict — Block",
                            symbol: "hand.raised",
                            message: "Best-effort foreground blocking with normal quit requests and no force-closing."
                        )
                    }

                    if !controller.preferences.focusDefaults.selectedApps.isEmpty {
                        defaultAppsCard
                    }

                    persistenceBanner
                }
                .frame(maxWidth: 820, alignment: .leading)
                .padding(.horizontal, 48)
                .padding(.vertical, 42)
                .frame(maxWidth: .infinity)
            }
        }
        .foregroundStyle(AttuneTheme.ink)
        .accessibilityIdentifier("dashboard-view")
    }

    private func modeCard(
        title: String,
        symbol: String,
        message: String
    ) -> some View {
        AttuneCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(title, systemImage: symbol)
                        .font(.headline)
                    Spacer()
                }
                Text(message)
                    .font(.callout)
                    .foregroundStyle(AttuneTheme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var defaultAppsCard: some View {
        AttuneCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Your default selected apps")
                    .font(.headline)
                ForEach(
                    controller.preferences.focusDefaults.selectedApps,
                    id: \.bundleIdentifier
                ) { application in
                    Label(application.displayName, systemImage: "app")
                        .font(.callout)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func activeSessionView(
        session: RunningSession,
        now: Date
    ) -> some View {
        ActiveSessionView(
            model: ActiveSessionViewModel(
                intention: session.configuration.intention,
                modeLabel: modeLabel(session.configuration.mode),
                timeLabel: timeLabel(session.configuration.completion),
                remainingTimeText: durationText(
                    remainingSeconds(for: session, now: now)
                ),
                definitionOfDone: definitionOfDone(
                    session.configuration.completion
                ),
                allowanceText: controller.mediumAllowanceRemainingSeconds.map(durationText),
                statusText: controller.persistenceStatus.userMessage,
                interventionCount: session.metrics.interventionCount,
                progressFraction: progressFraction(for: session, now: now),
                privacyMessage: "Attune stores only this session’s compact summary on this Mac."
            ),
            onMarkGoalComplete: controller.requestGoalReview,
            onEndFocus: {
                controller.requestStop()
            }
        )
    }

    private func goalReviewView(
        session: RunningSession,
        review: GoalReviewState
    ) -> AnyView {
        guard case let .goal(definitionOfDone, _) = session.configuration.completion else {
            return AnyView(activeSessionView(session: session, now: Date()))
        }

        let remaining = controller.goalReviewRemainingSeconds ?? 0
        let status = review.isUnlocked
            ? "Review complete. Confirm when this observable outcome is true."
            : review.isPaused
                ? "Review paused while the Mac is inactive."
                : "Read your definition of done for \(remaining) more second\(remaining == 1 ? "" : "s")."

        return AnyView(GoalCompletionReviewView(
            model: GoalCompletionReviewViewModel(
                intention: session.configuration.intention,
                definitionOfDone: definitionOfDone,
                modeLabel: modeLabel(session.configuration.mode),
                reviewStatusText: status,
                isConfirmationEnabled: review.isUnlocked,
                privacyMessage: "Attune does not inspect your work or ask for external proof."
            ),
            onKeepFocusing: controller.cancelGoalReview,
            onCompleteFocus: controller.confirmGoalCompletion
        ))
    }

    private func stopView(
        session: RunningSession,
        challenge: StopChallenge,
        now: Date
    ) -> some View {
        let cooldown = controller.stopCooldownRemainingSeconds ?? 0
        let phase: StopFocusPhase
        if challenge.isUnlocked {
            phase = .ready(message: "The pause is complete. Choose one reason, then confirm.")
        } else if challenge.isPaused {
            phase = .coolingDown(message: "The pause is suspended while the Mac is inactive.")
        } else {
            phase = .coolingDown(
                message: "Keep this choice visible for \(cooldown) more second\(cooldown == 1 ? "" : "s")."
            )
        }

        return StopFocusView(
            model: StopFocusViewModel(
                intention: session.configuration.intention,
                modeLabel: modeLabel(session.configuration.mode),
                remainingTimeLabel: timeLabel(session.configuration.completion),
                remainingTimeText: durationText(
                    remainingSeconds(for: session, now: now)
                ),
                phase: phase,
                selectedReason: challenge.selectedReason
            ),
            onSelectReason: controller.selectStopReason,
            onKeepFocusing: controller.keepFocusing,
            onConfirmEnd: controller.confirmStop,
            onRetrySave: controller.retryPersistence,
            onStayOpen: controller.keepFocusing,
            onShowForceQuitHelp: {
                model.isForceQuitHelpPresented = true
            }
        )
    }

    private func interruptedView(session: RunningSession) -> some View {
        InterruptedSessionView(
            model: InterruptedSessionViewModel(
                intention: session.configuration.intention,
                modeLabel: modeLabel(session.configuration.mode),
                remainingTimeLabel: timeLabel(session.configuration.completion),
                remainingTimeText: durationText(session.lastKnownRemainingSeconds),
                selectedApplicationNames: session.configuration.selectedApps.map(\.displayName),
                statusMessage: "Attune kept the last saved time remaining. Time away from the process was not counted as focused time.",
                canResume: session.lastKnownRemainingSeconds > 0,
                privacyMessage: "Recovery uses only the last local session snapshot."
            ),
            onResume: controller.resumeInterruptedSession,
            onEndWithNormalFriction: {
                controller.requestStop()
            },
            onShowForceQuitHelp: {
                model.isForceQuitHelpPresented = true
            }
        )
    }

    private func completionView(summary: SessionSummary) -> some View {
        VStack(spacing: 0) {
            if case .failed = controller.persistenceStatus {
                persistenceBanner
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
            }

            CompletionView(
                model: completionModel(summary),
                onSelectSatisfaction: { rating in
                    model.selectSatisfaction(rating)
                    controller.recordSatisfaction(rating)
                },
                onSkipSatisfaction: model.skipSatisfaction,
                onRecoveryAction: { action in
                    guard controller.acknowledgeCompletion() else {
                        return
                    }
                    switch action {
                    case .tryTenMinuteSoftFocus:
                        model.beginTenMinuteRecovery(from: summary)
                    case .adjustSelectedApps:
                        model.beginFirstFocus(
                            selectedApps: summary.configuration.selectedApps
                        )
                    }
                },
                onDone: {
                    if controller.acknowledgeCompletion() {
                        model.resetCompletionReview()
                    }
                },
                onStartAnotherFocus: {
                    guard controller.acknowledgeCompletion() else {
                        return
                    }
                    model.beginFocusSetup(using: controller.preferences.focusDefaults)
                }
            )
        }
        .background(AttuneTheme.paper)
    }

    private func completionModel(_ summary: SessionSummary) -> CompletionViewModel {
        let presentation = outcomePresentation(summary.outcome)
        let recoveryActions: [CompletionRecoveryAction]
        switch summary.outcome {
        case .endedEarly, .interrupted:
            recoveryActions = [.tryTenMinuteSoftFocus, .adjustSelectedApps]
        case .timedComplete, .goalComplete, .goalWindowEnded:
            recoveryActions = []
        }

        return CompletionViewModel(
            outcomeTitle: presentation.title,
            outcomeMessage: presentation.message,
            outcomeSymbolName: presentation.symbol,
            intention: summary.configuration.intention,
            scheduledElapsedText: durationText(summary.scheduledElapsedSeconds),
            modeLabel: modeLabel(summary.configuration.mode),
            interventionCount: summary.metrics.interventionCount,
            additionalMetrics: [
                CompletionMetric(
                    title: "Returned to focus",
                    value: "\(summary.metrics.softReturnCount)",
                    systemImage: "arrow.uturn.backward"
                ),
                CompletionMetric(
                    title: "Opened after pause",
                    value: "\(summary.metrics.softOpenCount)",
                    systemImage: "door.left.hand.open"
                )
            ],
            showsSatisfactionPrompt: !model.satisfactionWasSkipped,
            selectedSatisfaction: model.selectedSatisfaction ?? summary.satisfaction,
            recoveryActions: recoveryActions,
            privacyMessage: "This compact outcome is stored only on this Mac.",
            isReadyToLeave: terminalOutcomeIsCommitted(summary.id)
        )
    }

    @ViewBuilder
    private var persistenceBanner: some View {
        if let message = controller.persistenceStatus.userMessage {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(AttuneTheme.lavender)
                Text(message)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                if terminalOutcomeSaveFailed {
                    Button("Stay Open") {
                        model.stayOpenAfterPersistenceFailure()
                    }
                    .accessibilityIdentifier("persistence-stay-open")
                }
                Button("Retry", action: controller.retryPersistence)
                    .accessibilityIdentifier("persistence-retry")
            }
            .padding(14)
            .background(AttuneTheme.warmSoft, in: RoundedRectangle(cornerRadius: 12))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("persistence-failure")
        }
    }

    private func defaults(afterStarting configuration: FocusConfiguration) -> FocusDefaults {
        var defaults = controller.preferences.focusDefaults
        defaults.selectedApps = configuration.selectedApps
        switch configuration.completion {
        case let .timer(durationSeconds):
            defaults.timerDurationSeconds = durationSeconds
        case let .goal(_, safetyDurationSeconds):
            defaults.goalSafetyDurationSeconds = safetyDurationSeconds
        }
        return defaults
    }

    private var terminalOutcomeSaveFailed: Bool {
        guard let summary = controller.completedSummary,
              case let .failed(sessionID) = controller.terminalPersistenceStatus else {
            return false
        }
        return sessionID == summary.id
    }

    private func terminalOutcomeIsCommitted(_ sessionID: UUID) -> Bool {
        controller.terminalPersistenceStatus == .committed(sessionID: sessionID)
    }

    private func remainingSeconds(for session: RunningSession, now: Date) -> Int {
        guard session.status == .running else {
            return session.lastKnownRemainingSeconds
        }
        let wallRemaining = max(
            0,
            Int(session.deadline.timeIntervalSince(now).rounded(.up))
        )
        return min(session.lastKnownRemainingSeconds, wallRemaining)
    }

    private func progressFraction(for session: RunningSession, now: Date) -> Double {
        let duration = max(1, session.configuration.completion.durationSeconds)
        let remaining = remainingSeconds(for: session, now: now)
        return Double(duration - remaining) / Double(duration)
    }

    private func definitionOfDone(_ completion: CompletionRule) -> String? {
        guard case let .goal(definition, _) = completion else {
            return nil
        }
        return definition
    }

    private func modeLabel(_ mode: FocusMode) -> String {
        switch mode {
        case .soft:
            "Soft — Pause"
        case .medium:
            "Medium — Budget"
        case .strict:
            "Strict — Block"
        }
    }

    private func timeLabel(_ completion: CompletionRule) -> String {
        switch completion {
        case .timer:
            "Time remaining"
        case .goal:
            "Goal safety window remaining"
        }
    }

    private func durationText(_ seconds: Int) -> String {
        let clamped = max(0, seconds)
        let hours = clamped / 3_600
        let minutes = (clamped % 3_600) / 60
        let secondPart = clamped % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secondPart)
        }
        return String(format: "%02d:%02d", minutes, secondPart)
    }

    private func outcomePresentation(
        _ outcome: SessionOutcome
    ) -> (title: String, message: String, symbol: String) {
        switch outcome {
        case .timedComplete:
            ("Focus complete", "The time you chose has ended.", "checkmark")
        case .goalComplete:
            ("Goal complete", "You confirmed the outcome you defined.", "checkmark")
        case .goalWindowEnded:
            (
                "Goal window ended",
                "The safety deadline ended access restrictions without claiming the goal was complete.",
                "clock.badge.checkmark"
            )
        case .endedEarly:
            (
                "Focus ended early",
                "You made a deliberate change. A smaller next step is available whenever you want it.",
                "arrow.forward"
            )
        case .interrupted:
            (
                "Focus interrupted",
                "Attune recorded only the time it could safely recover. Nothing was treated as a failed streak.",
                "pause"
            )
        }
    }
}
