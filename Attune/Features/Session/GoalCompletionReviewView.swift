import SwiftUI

struct GoalCompletionReviewViewModel: Equatable, Sendable {
    let intention: String
    let definitionOfDone: String
    let modeLabel: String
    let reviewStatusText: String
    let isConfirmationEnabled: Bool
    let privacyMessage: String
}

struct GoalCompletionReviewView: View {
    let model: GoalCompletionReviewViewModel
    let onKeepFocusing: @MainActor () -> Void
    let onCompleteFocus: @MainActor () -> Void

    @SwiftUI.FocusState private var completionActionFocused: Bool

    var body: some View {
        ZStack {
            AttunePageBackground()

            ScrollView {
                VStack(spacing: 24) {
                    AttuneModeBadge(title: model.modeLabel)
                        .accessibilityIdentifier("goal-review-mode")

                    VStack(spacing: 10) {
                        Text("Review what you chose.")
                            .font(.system(size: 34, weight: .medium, design: .serif))
                            .multilineTextAlignment(.center)
                            .accessibilityIdentifier("goal-review-title")

                        Text(model.intention)
                            .font(.title3)
                            .foregroundStyle(AttuneTheme.muted)
                            .multilineTextAlignment(.center)
                            .textSelection(.enabled)
                            .accessibilityIdentifier("goal-review-intention")
                    }

                    AttuneCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Done means")
                                .font(.caption.weight(.bold))
                                .tracking(1.1)
                                .foregroundStyle(AttuneTheme.lavender)
                            Text(model.definitionOfDone)
                                .font(.title2)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("goal-review-definition-of-done")

                    AttuneStatusLabel(
                        message: model.reviewStatusText,
                        isReady: model.isConfirmationEnabled
                    )
                    .accessibilityIdentifier("goal-review-status")

                    HStack(spacing: 10) {
                        Button("Keep Focusing") {
                            onKeepFocusing()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .keyboardShortcut(.cancelAction)
                        .accessibilityIdentifier("goal-review-keep-focusing")

                        completionButton
                    }

                    Text("Completion is your deliberate confirmation. Attune does not inspect your work or ask for proof.")
                        .font(.caption)
                        .foregroundStyle(AttuneTheme.muted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("goal-review-attestation-note")

                    AttunePrivacyNote(message: model.privacyMessage)
                        .accessibilityIdentifier("goal-review-privacy")
                }
                .frame(maxWidth: 600)
                .padding(.horizontal, 48)
                .padding(.vertical, 44)
                .frame(maxWidth: .infinity)
            }
        }
        .foregroundStyle(AttuneTheme.ink)
        .accessibilityIdentifier("goal-completion-review-view")
        .onAppear {
            completionActionFocused = model.isConfirmationEnabled
        }
        .onChange(of: model.isConfirmationEnabled) { _, isEnabled in
            if isEnabled {
                completionActionFocused = true
            }
        }
    }

    @ViewBuilder
    private var completionButton: some View {
        if model.isConfirmationEnabled {
            Button("Complete Focus") {
                onCompleteFocus()
            }
            .buttonStyle(.borderedProminent)
            .tint(AttuneTheme.ink)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .focused($completionActionFocused)
            .accessibilityIdentifier("goal-review-complete-focus")
            .accessibilityHint("Ends enforcement and records Goal complete.")
        } else {
            Button("Complete Focus") {}
                .buttonStyle(.borderedProminent)
                .tint(AttuneTheme.ink)
                .controlSize(.large)
                .disabled(true)
                .accessibilityIdentifier("goal-review-complete-focus")
                .accessibilityHint(model.reviewStatusText)
        }
    }
}
