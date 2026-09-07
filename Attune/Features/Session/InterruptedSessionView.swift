import SwiftUI

struct InterruptedSessionViewModel: Equatable, Sendable {
    let intention: String
    let modeLabel: String
    let remainingTimeLabel: String
    let remainingTimeText: String
    let selectedApplicationNames: [String]
    let statusMessage: String
    let canResume: Bool
    let privacyMessage: String
}

struct InterruptedSessionView: View {
    let model: InterruptedSessionViewModel
    let onResume: @MainActor () -> Void
    let onEndWithNormalFriction: @MainActor () -> Void
    let onShowForceQuitHelp: @MainActor () -> Void

    @SwiftUI.FocusState private var defaultActionFocused: Bool

    var body: some View {
        ZStack {
            AttunePageBackground()

            ScrollView {
                VStack(spacing: 24) {
                    Image(systemName: "pause.circle.fill")
                        .font(.system(size: 46))
                        .foregroundStyle(AttuneTheme.lavender)
                        .accessibilityHidden(true)

                    VStack(spacing: 9) {
                        Text("This focus was interrupted.")
                            .font(.system(size: 36, weight: .medium, design: .serif))
                            .multilineTextAlignment(.center)
                            .accessibilityIdentifier("interrupted-session-title")

                        Text(model.statusMessage)
                            .font(.body)
                            .foregroundStyle(AttuneTheme.muted)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("interrupted-session-status")
                    }

                    AttuneCard {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                AttuneModeBadge(title: model.modeLabel)
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(model.remainingTimeLabel)
                                        .font(.caption)
                                        .foregroundStyle(AttuneTheme.muted)
                                    Text(model.remainingTimeText)
                                        .font(.title3.weight(.semibold))
                                        .monospacedDigit()
                                }
                                .accessibilityElement(children: .combine)
                            }

                            Divider()

                            VStack(alignment: .leading, spacing: 5) {
                                Text("Your intention")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(AttuneTheme.muted)
                                Text(model.intention)
                                    .font(.title3)
                                    .textSelection(.enabled)
                            }

                            if !model.selectedApplicationNames.isEmpty {
                                VStack(alignment: .leading, spacing: 7) {
                                    Text("Selected apps")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(AttuneTheme.muted)

                                    ForEach(
                                        Array(model.selectedApplicationNames.enumerated()),
                                        id: \.offset
                                    ) { _, name in
                                        Label(name, systemImage: "app")
                                            .font(.callout)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .accessibilityIdentifier("interrupted-session-summary")

                    actionRow

                    Button("Need to stop immediately? Learn about macOS Force Quit") {
                        onShowForceQuitHelp()
                    }
                    .buttonStyle(.link)
                    .accessibilityIdentifier("interrupted-session-force-quit-help")
                    .accessibilityHint("Explains the operating-system emergency escape. It does not end the session in Attune.")

                    AttunePrivacyNote(message: model.privacyMessage)
                        .accessibilityIdentifier("interrupted-session-privacy")
                }
                .frame(maxWidth: 620)
                .padding(.horizontal, 48)
                .padding(.vertical, 42)
                .frame(maxWidth: .infinity)
            }
        }
        .foregroundStyle(AttuneTheme.ink)
        .accessibilityIdentifier("interrupted-session-view")
        .onAppear {
            defaultActionFocused = true
        }
    }

    @ViewBuilder
    private var actionRow: some View {
        HStack(spacing: 10) {
            if model.canResume {
                Button("End with Normal Friction") {
                    onEndWithNormalFriction()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityIdentifier("interrupted-session-end")
                .accessibilityHint("Opens the same deliberate stop flow used during an active focus.")
            } else {
                Button("End with Normal Friction") {
                    onEndWithNormalFriction()
                }
                .buttonStyle(.borderedProminent)
                .tint(AttuneTheme.ink)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .focused($defaultActionFocused)
                .accessibilityIdentifier("interrupted-session-end")
                .accessibilityHint("Opens the same deliberate stop flow used during an active focus.")
            }

            if model.canResume {
                Button("Resume Focus") {
                    onResume()
                }
                .buttonStyle(.borderedProminent)
                .tint(AttuneTheme.ink)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .focused($defaultActionFocused)
                .accessibilityIdentifier("interrupted-session-resume")
                .accessibilityHint("Restores this focus using the last saved time remaining.")
            }
        }
    }
}
