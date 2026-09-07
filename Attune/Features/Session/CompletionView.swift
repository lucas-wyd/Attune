import SwiftUI

struct CompletionMetric: Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let value: String
    let systemImage: String

    init(
        id: String? = nil,
        title: String,
        value: String,
        systemImage: String
    ) {
        self.id = id ?? title
        self.title = title
        self.value = value
        self.systemImage = systemImage
    }
}

enum CompletionRecoveryAction: String, Equatable, Identifiable, Sendable {
    case tryTenMinuteSoftFocus
    case adjustSelectedApps

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .tryTenMinuteSoftFocus:
            "Try 10 minutes in Soft mode"
        case .adjustSelectedApps:
            "Adjust selected apps"
        }
    }

    var systemImage: String {
        switch self {
        case .tryTenMinuteSoftFocus:
            "timer"
        case .adjustSelectedApps:
            "square.grid.2x2"
        }
    }
}

struct CompletionViewModel: Equatable, Sendable {
    let outcomeTitle: String
    let outcomeMessage: String
    let outcomeSymbolName: String
    let intention: String
    let scheduledElapsedText: String
    let modeLabel: String
    let interventionCount: Int
    let additionalMetrics: [CompletionMetric]
    let showsSatisfactionPrompt: Bool
    let selectedSatisfaction: Int?
    let recoveryActions: [CompletionRecoveryAction]
    let privacyMessage: String
    var isReadyToLeave: Bool = true

    var interventionText: String {
        interventionCount == 1 ? "1" : "\(interventionCount)"
    }
}

struct CompletionView: View {
    let model: CompletionViewModel
    let onSelectSatisfaction: @MainActor (Int) -> Void
    let onSkipSatisfaction: @MainActor () -> Void
    let onRecoveryAction: @MainActor (CompletionRecoveryAction) -> Void
    let onDone: @MainActor () -> Void
    let onStartAnotherFocus: @MainActor () -> Void

    @SwiftUI.FocusState private var doneActionFocused: Bool

    var body: some View {
        ZStack {
            AttunePageBackground()

            ScrollView {
                VStack(spacing: 26) {
                    outcomeHeader
                    summaryGrid

                    if model.showsSatisfactionPrompt {
                        satisfactionPrompt
                    }

                    if !model.recoveryActions.isEmpty {
                        recoverySuggestions
                    }

                    if !model.isReadyToLeave {
                        AttuneStatusLabel(
                            message: "Saving this outcome locally before continuing…",
                            isReady: false
                        )
                        .accessibilityIdentifier("completion-saving")
                    }

                    HStack(spacing: 10) {
                        Button("Start Another Focus") {
                            onStartAnotherFocus()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .disabled(!model.isReadyToLeave)
                        .accessibilityIdentifier("completion-start-another")

                        Button("Done") {
                            onDone()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AttuneTheme.ink)
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                        .focused($doneActionFocused)
                        .disabled(!model.isReadyToLeave)
                        .accessibilityIdentifier("completion-done")
                    }

                    AttunePrivacyNote(message: model.privacyMessage)
                        .accessibilityIdentifier("completion-privacy")
                }
                .frame(maxWidth: 760)
                .padding(.horizontal, 48)
                .padding(.vertical, 40)
                .frame(maxWidth: .infinity)
            }
        }
        .foregroundStyle(AttuneTheme.ink)
        .accessibilityIdentifier("completion-view")
        .onAppear {
            doneActionFocused = true
        }
    }

    private var outcomeHeader: some View {
        VStack(spacing: 13) {
            Image(systemName: model.outcomeSymbolName)
                .font(.title2.weight(.semibold))
                .foregroundStyle(AttuneTheme.sage)
                .frame(width: 52, height: 52)
                .background(AttuneTheme.sageSoft)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .accessibilityHidden(true)

            Text(model.outcomeTitle)
                .font(.system(size: 38, weight: .medium, design: .serif))
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("completion-outcome")

            Text(model.outcomeMessage)
                .font(.body)
                .foregroundStyle(AttuneTheme.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("completion-message")

            Text(model.intention)
                .font(.headline)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
                .accessibilityIdentifier("completion-intention")
        }
    }

    private var summaryGrid: some View {
        AttuneCard {
            VStack(spacing: 0) {
                summaryRow(
                    title: "Scheduled elapsed",
                    value: model.scheduledElapsedText,
                    systemImage: "clock"
                )
                Divider().padding(.vertical, 12)
                summaryRow(
                    title: "Mode",
                    value: model.modeLabel,
                    systemImage: "circle.lefthalf.filled"
                )
                Divider().padding(.vertical, 12)
                summaryRow(
                    title: "Interventions",
                    value: model.interventionText,
                    systemImage: "arrow.uturn.backward.circle"
                )

                ForEach(model.additionalMetrics) { metric in
                    Divider().padding(.vertical, 12)
                    summaryRow(
                        title: metric.title,
                        value: metric.value,
                        systemImage: metric.systemImage
                    )
                }

                Text("Scheduled elapsed is wall-clock session time. It is not a measurement of attention or productivity.")
                    .font(.caption)
                    .foregroundStyle(AttuneTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("completion-scheduled-elapsed-explanation")
            }
        }
        .accessibilityIdentifier("completion-summary")
    }

    private func summaryRow(
        title: String,
        value: String,
        systemImage: String
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(AttuneTheme.sage)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(title)
                .foregroundStyle(AttuneTheme.muted)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }

    private var satisfactionPrompt: some View {
        AttuneCard {
            VStack(spacing: 14) {
                VStack(spacing: 4) {
                    Text("How satisfied are you with this focus?")
                        .font(.headline)
                    Text("Optional · choose 1–5 or skip")
                        .font(.caption)
                        .foregroundStyle(AttuneTheme.muted)
                }

                HStack(spacing: 8) {
                    ForEach(1...5, id: \.self) { rating in
                        satisfactionButton(rating)
                    }
                }

                HStack {
                    Text("Not satisfied")
                    Spacer()
                    Text("Very satisfied")
                }
                .font(.caption2)
                .foregroundStyle(AttuneTheme.muted)
                .frame(maxWidth: 320)

                Button("Skip") {
                    onSkipSatisfaction()
                }
                .buttonStyle(.link)
                .accessibilityIdentifier("completion-satisfaction-skip")
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("completion-satisfaction")
    }

    private func satisfactionButton(_ rating: Int) -> some View {
        let isSelected = model.selectedSatisfaction == rating

        return Button {
            onSelectSatisfaction(rating)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .accessibilityHidden(true)
                Text("\(rating)")
                    .fontWeight(.semibold)
            }
            .frame(width: 46, height: 46)
            .foregroundStyle(isSelected ? AttuneTheme.sage : AttuneTheme.ink)
            .background(isSelected ? AttuneTheme.sageSoft : AttuneTheme.paper)
            .clipShape(RoundedRectangle(cornerRadius: 11))
            .overlay {
                RoundedRectangle(cornerRadius: 11)
                    .stroke(isSelected ? AttuneTheme.sage : AttuneTheme.line, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Satisfaction \(rating) of 5")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityIdentifier("completion-satisfaction-\(rating)")
    }

    private var recoverySuggestions: some View {
        VStack(spacing: 10) {
            Text("A smaller next step")
                .font(.headline)

            Text("Nothing was lost. You can make the next focus easier to keep.")
                .font(.callout)
                .foregroundStyle(AttuneTheme.muted)
                .multilineTextAlignment(.center)

            HStack(spacing: 10) {
                ForEach(model.recoveryActions) { action in
                    Button {
                        onRecoveryAction(action)
                    } label: {
                        Label(action.title, systemImage: action.systemImage)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("completion-recovery-\(action.rawValue)")
                }
            }
        }
        .accessibilityIdentifier("completion-recovery")
    }
}
