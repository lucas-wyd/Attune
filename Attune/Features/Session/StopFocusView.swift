import SwiftUI

enum StopFocusPhase: Equatable, Sendable {
    case coolingDown(message: String)
    case ready(message: String)
    case saving(message: String)
    case saveFailed(message: String)

    var message: String {
        switch self {
        case let .coolingDown(message),
             let .ready(message),
             let .saving(message),
             let .saveFailed(message):
            message
        }
    }

    var isCooldownComplete: Bool {
        if case .ready = self {
            true
        } else {
            false
        }
    }

    var isSaveFailure: Bool {
        if case .saveFailed = self {
            true
        } else {
            false
        }
    }

    var isSaving: Bool {
        if case .saving = self {
            true
        } else {
            false
        }
    }
}

struct StopReasonOption: Equatable, Identifiable, Sendable {
    let reason: EarlyStopReason
    let title: String

    var id: EarlyStopReason {
        reason
    }

    static let all: [StopReasonOption] = [
        StopReasonOption(reason: .urgentNeed, title: "Urgent need"),
        StopReasonOption(
            reason: .selectedApplicationNeeded,
            title: "Need a selected app for the task"
        ),
        StopReasonOption(reason: .taskOrPlanChanged, title: "Task or plan changed"),
        StopReasonOption(reason: .setupNotHelping, title: "This setup is not helping"),
        StopReasonOption(reason: .other, title: "Other")
    ]
}

struct StopFocusViewModel: Equatable, Sendable {
    let intention: String
    let modeLabel: String
    let remainingTimeLabel: String
    let remainingTimeText: String
    let phase: StopFocusPhase
    let selectedReason: EarlyStopReason?

    var canConfirmEnd: Bool {
        phase.isCooldownComplete && selectedReason != nil
    }
}

struct StopFocusView: View {
    let model: StopFocusViewModel
    let onSelectReason: @MainActor (EarlyStopReason) -> Void
    let onKeepFocusing: @MainActor () -> Void
    let onConfirmEnd: @MainActor () -> Void
    let onRetrySave: @MainActor () -> Void
    let onStayOpen: @MainActor () -> Void
    let onShowForceQuitHelp: @MainActor () -> Void

    @SwiftUI.FocusState private var defaultActionFocused: Bool

    var body: some View {
        ZStack {
            AttunePageBackground()

            ScrollView {
                VStack(spacing: 24) {
                    AttuneModeBadge(title: model.modeLabel)
                        .accessibilityIdentifier("stop-focus-mode")

                    VStack(spacing: 9) {
                        Text(model.phase.isSaveFailure ? "Attune is staying open." : "Pause before ending.")
                            .font(.system(size: 34, weight: .medium, design: .serif))
                            .multilineTextAlignment(.center)
                            .accessibilityIdentifier("stop-focus-title")

                        Text(model.intention)
                            .font(.title3)
                            .foregroundStyle(AttuneTheme.muted)
                            .multilineTextAlignment(.center)
                            .textSelection(.enabled)
                            .accessibilityIdentifier("stop-focus-intention")
                    }

                    HStack(spacing: 8) {
                        Text(model.remainingTimeLabel)
                            .foregroundStyle(AttuneTheme.muted)
                        Text(model.remainingTimeText)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                    }
                    .font(.callout)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("stop-focus-remaining-time")

                    phaseStatus

                    reasonSelection

                    actionRow

                    Button("Need to stop immediately? Learn about macOS Force Quit") {
                        onShowForceQuitHelp()
                    }
                    .buttonStyle(.link)
                    .accessibilityIdentifier("stop-focus-force-quit-help")
                    .accessibilityHint("Explains the operating-system emergency escape. It does not stop the session in Attune.")

                    AttunePrivacyNote(
                        message: "Your selected reason is stored only in the compact session record on this Mac."
                    )
                    .accessibilityIdentifier("stop-focus-privacy")
                }
                .frame(maxWidth: 620)
                .padding(.horizontal, 48)
                .padding(.vertical, 40)
                .frame(maxWidth: .infinity)
            }
        }
        .foregroundStyle(AttuneTheme.ink)
        .accessibilityIdentifier("stop-focus-view")
        .onAppear {
            defaultActionFocused = true
        }
    }

    @ViewBuilder
    private var phaseStatus: some View {
        if model.phase.isSaveFailure {
            Label(model.phase.message, systemImage: "exclamationmark.triangle.fill")
                .font(.callout.weight(.medium))
                .foregroundStyle(AttuneTheme.ink)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AttuneTheme.warmSoft)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("stop-focus-status")
        } else {
            AttuneStatusLabel(
                message: model.phase.message,
                isReady: model.phase.isCooldownComplete
            )
            .accessibilityIdentifier("stop-focus-status")
        }
    }

    private var reasonSelection: some View {
        AttuneCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Why are you ending this focus?")
                    .font(.headline)
                    .accessibilityIdentifier("stop-focus-reason-heading")

                Text(reasonGuidance)
                .font(.caption)
                .foregroundStyle(AttuneTheme.muted)

                VStack(spacing: 7) {
                    ForEach(StopReasonOption.all) { option in
                        reasonButton(option)
                    }
                }
            }
        }
        .accessibilityIdentifier("stop-focus-reasons")
    }

    private func reasonButton(_ option: StopReasonOption) -> some View {
        let isSelected = model.selectedReason == option.reason

        return Button {
            onSelectReason(option.reason)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? AttuneTheme.sage : AttuneTheme.muted)
                    .accessibilityHidden(true)

                Text(option.title)
                    .foregroundStyle(AttuneTheme.ink)

                Spacer()

                if isSelected {
                    Text("Selected")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AttuneTheme.sage)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isSelected ? AttuneTheme.sageSoft : AttuneTheme.paper)
            .clipShape(RoundedRectangle(cornerRadius: 11))
            .overlay {
                RoundedRectangle(cornerRadius: 11)
                    .stroke(isSelected ? AttuneTheme.sage : AttuneTheme.line, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!model.phase.isCooldownComplete)
        .accessibilityLabel(option.title)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint(
            model.phase.isCooldownComplete
                ? "Selects this reason."
                : "Available after the pause."
        )
        .accessibilityIdentifier("stop-focus-reason-\(option.reason.rawValue)")
    }

    @ViewBuilder
    private var actionRow: some View {
        if model.phase.isSaveFailure {
            HStack(spacing: 10) {
                Button("Stay Open") {
                    onStayOpen()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("stop-focus-stay-open")

                Button("Retry") {
                    onRetrySave()
                }
                .buttonStyle(.borderedProminent)
                .tint(AttuneTheme.ink)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .focused($defaultActionFocused)
                .accessibilityIdentifier("stop-focus-retry")
            }
        } else if model.phase.isSaving {
            Button("Saving Session…") {}
                .buttonStyle(.borderedProminent)
                .tint(AttuneTheme.ink)
                .controlSize(.large)
                .disabled(true)
                .accessibilityIdentifier("stop-focus-saving")
                .accessibilityHint(model.phase.message)
        } else {
            HStack(spacing: 10) {
                Button("Keep Focusing") {
                    onKeepFocusing()
                }
                .buttonStyle(.borderedProminent)
                .tint(AttuneTheme.ink)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .focused($defaultActionFocused)
                .accessibilityIdentifier("stop-focus-keep-focusing")

                Button("End Focus") {
                    onConfirmEnd()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(!model.canConfirmEnd)
                .accessibilityIdentifier("stop-focus-confirm-end")
                .accessibilityHint(endFocusHint)
            }
        }
    }

    private var endFocusHint: String {
        if !model.phase.isCooldownComplete {
            model.phase.message
        } else if model.selectedReason == nil {
            "Choose a reason first."
        } else {
            "Ends enforcement and records Ended early."
        }
    }

    private var reasonGuidance: String {
        if model.phase.isSaveFailure {
            "Your selection is kept while Attune stays open."
        } else if model.phase.isSaving {
            "Your selection is being saved locally."
        } else if model.phase.isCooldownComplete {
            "Choose one reason to continue."
        } else {
            "Reason choices become available after the pause."
        }
    }
}
