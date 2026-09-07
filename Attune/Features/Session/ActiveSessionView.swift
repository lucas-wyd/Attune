import SwiftUI

struct ActiveSessionViewModel: Equatable, Sendable {
    let intention: String
    let modeLabel: String
    let timeLabel: String
    let remainingTimeText: String
    let definitionOfDone: String?
    let allowanceText: String?
    let statusText: String?
    let interventionCount: Int
    let progressFraction: Double?
    let privacyMessage: String

    init(
        intention: String,
        modeLabel: String,
        timeLabel: String,
        remainingTimeText: String,
        definitionOfDone: String? = nil,
        allowanceText: String? = nil,
        statusText: String? = nil,
        interventionCount: Int,
        progressFraction: Double? = nil,
        privacyMessage: String
    ) {
        self.intention = intention
        self.modeLabel = modeLabel
        self.timeLabel = timeLabel
        self.remainingTimeText = remainingTimeText
        self.definitionOfDone = definitionOfDone
        self.allowanceText = allowanceText
        self.statusText = statusText
        self.interventionCount = interventionCount
        self.progressFraction = progressFraction.map { min(max($0, 0), 1) }
        self.privacyMessage = privacyMessage
    }

    var isGoalSession: Bool {
        definitionOfDone != nil
    }

    var interventionText: String {
        interventionCount == 1 ? "1 intervention" : "\(interventionCount) interventions"
    }
}

struct ActiveSessionView: View {
    let model: ActiveSessionViewModel
    let onMarkGoalComplete: @MainActor () -> Void
    let onEndFocus: @MainActor () -> Void

    @SwiftUI.FocusState private var goalActionFocused: Bool

    var body: some View {
        ZStack {
            AttunePageBackground()

            ScrollView {
                VStack(spacing: 28) {
                    header
                    focusContent
                    sessionDetails

                    AttunePrivacyNote(message: model.privacyMessage)
                        .accessibilityIdentifier("active-session-privacy")
                }
                .frame(maxWidth: 760)
                .padding(.horizontal, 48)
                .padding(.vertical, 36)
                .frame(maxWidth: .infinity)
            }
        }
        .foregroundStyle(AttuneTheme.ink)
        .accessibilityIdentifier("active-session-view")
        .onAppear {
            goalActionFocused = model.isGoalSession
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            AttuneModeBadge(title: model.modeLabel)
                .accessibilityIdentifier("active-session-mode")

            Spacer()

            Button("End Focus…") {
                onEndFocus()
            }
            .buttonStyle(.plain)
            .foregroundStyle(AttuneTheme.muted)
            .accessibilityIdentifier("active-session-end-focus")
            .accessibilityHint("Opens the deliberate early-stop review.")
        }
    }

    private var focusContent: some View {
        VStack(spacing: 16) {
            Text("STAY WITH WHAT YOU CHOSE")
                .font(.caption.weight(.bold))
                .tracking(1.6)
                .foregroundStyle(AttuneTheme.lavender)
                .accessibilityHidden(true)

            Text(model.intention)
                .font(.system(size: 42, weight: .medium, design: .serif))
                .tracking(-1.2)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
                .accessibilityIdentifier("active-session-intention")

            if let definitionOfDone = model.definitionOfDone {
                VStack(spacing: 5) {
                    Text("Done means")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AttuneTheme.muted)
                    Text(definitionOfDone)
                        .font(.title3)
                        .multilineTextAlignment(.center)
                        .textSelection(.enabled)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("active-session-definition-of-done")
            }

            VStack(spacing: 5) {
                Text(model.remainingTimeText)
                    .font(.system(size: 76, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.identity)
                    .accessibilityHidden(true)

                Text(model.timeLabel)
                    .font(.callout)
                    .foregroundStyle(AttuneTheme.muted)
                    .accessibilityHidden(true)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(model.timeLabel)
            .accessibilityValue(model.remainingTimeText)
            .accessibilityIdentifier("active-session-time")

            if let progressFraction = model.progressFraction {
                ProgressView(value: progressFraction)
                    .progressViewStyle(.linear)
                    .tint(AttuneTheme.sage)
                    .frame(maxWidth: 430)
                    .accessibilityLabel("Session progress")
                    .accessibilityValue(
                        Text("\(Int((progressFraction * 100).rounded())) percent")
                    )
                    .accessibilityIdentifier("active-session-progress")
            }

            if let statusText = model.statusText {
                Text(statusText)
                    .font(.callout)
                    .foregroundStyle(AttuneTheme.muted)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("active-session-status")
            }

            if model.isGoalSession {
                Button("Mark Goal Complete") {
                    onMarkGoalComplete()
                }
                .buttonStyle(.borderedProminent)
                .tint(AttuneTheme.ink)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .focused($goalActionFocused)
                .accessibilityIdentifier("active-session-mark-goal-complete")
                .accessibilityHint("Opens the required completion review.")
            }
        }
    }

    private var sessionDetails: some View {
        HStack(spacing: 12) {
            metric(
                title: "Selected-app activity",
                value: model.interventionText,
                systemImage: "arrow.uturn.backward.circle"
            )

            if let allowanceText = model.allowanceText {
                metric(
                    title: "Shared allowance",
                    value: allowanceText,
                    systemImage: "hourglass"
                )
            }
        }
        .accessibilityIdentifier("active-session-details")
    }

    private func metric(
        title: String,
        value: String,
        systemImage: String
    ) -> some View {
        AttuneCard {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(AttuneTheme.sage)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(AttuneTheme.muted)
                    Text(value)
                        .font(.body.weight(.semibold))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }
}
