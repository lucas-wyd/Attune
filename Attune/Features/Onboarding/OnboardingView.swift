import SwiftUI

struct OnboardingView: View {
    @Binding var selectedApps: [AppIdentity]

    let applicationPicker: any ApplicationPicker
    let onQuit: () -> Void
    let onCreateFirstFocus: () -> Void
    let onExploreAttune: () -> Void

    @State private var step = OnboardingStep.introduction
    @State private var browserWarningAcknowledged = false

    init(
        selectedApps: Binding<[AppIdentity]>,
        applicationPicker: any ApplicationPicker,
        onQuit: @escaping () -> Void,
        onCreateFirstFocus: @escaping () -> Void,
        onExploreAttune: @escaping () -> Void
    ) {
        _selectedApps = selectedApps
        self.applicationPicker = applicationPicker
        self.onQuit = onQuit
        self.onCreateFirstFocus = onCreateFirstFocus
        self.onExploreAttune = onExploreAttune
    }

    var body: some View {
        VStack(spacing: 0) {
            onboardingHeader
            Divider()

            ScrollView {
                stepContent
                    .frame(maxWidth: 760, alignment: .leading)
                    .padding(.horizontal, 42)
                    .padding(.vertical, 34)
            }

            Divider()
            footer
                .padding(.horizontal, 32)
                .padding(.vertical, 18)
        }
        .frame(minWidth: 720, minHeight: 620)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityIdentifier("onboarding-view")
    }

    private var onboardingHeader: some View {
        HStack(spacing: 14) {
            Image(systemName: "scope")
                .font(.title2)
                .accessibilityHidden(true)

            Text("Attune")
                .font(.headline)

            Spacer()

            Text("Step \(step.rawValue + 1) of \(OnboardingStep.allCases.count)")
                .font(.callout)
                .foregroundStyle(.secondary)
                .accessibilityLabel(
                    "Onboarding step \(step.rawValue + 1) of \(OnboardingStep.allCases.count)"
                )
                .accessibilityIdentifier("onboarding-progress")
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 18)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .introduction:
            introduction
        case .privacy:
            privacy
        case .applications:
            applications
        case .modes:
            modes
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 22) {
            onboardingTitle(
                "A pause between impulse and action",
                subtitle: "Attune adds adjustable friction to the Mac applications you choose during a voluntary focus session."
            )

            VStack(alignment: .leading, spacing: 14) {
                OnboardingModeExplanation(
                    title: "Soft — Pause",
                    symbol: "pause.circle",
                    description: "Reminds you what you chose, then lets you return or open the app after a short pause."
                )
                OnboardingModeExplanation(
                    title: "Medium — Budget",
                    symbol: "hourglass",
                    description: "Shares a time allowance across all selected apps, then blocks foreground use when it runs out."
                )
                OnboardingModeExplanation(
                    title: "Strict — Block",
                    symbol: "hand.raised",
                    description: "Keeps selected apps out of the foreground while Attune is running."
                )
            }

            Label(
                "Strict is best-effort, not tamper-proof. A selected app may appear briefly before Attune hides it.",
                systemImage: "info.circle"
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(14)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
        }
        .accessibilityIdentifier("onboarding-introduction")
    }

    private var privacy: some View {
        VStack(alignment: .leading, spacing: 22) {
            onboardingTitle(
                "Private by design",
                subtitle: "Attune observes only the small amount of local system state needed to apply your chosen rule."
            )

            disclosureGroup(
                title: "Observed briefly while Attune runs",
                symbol: "eye",
                items: [
                    "Foreground application identity",
                    "Active-Space changes and system sleep or session state",
                    "Coarse time since the last input event, only if you later enable inactivity check-ins"
                ]
            )

            disclosureGroup(
                title: "Never accessed",
                symbol: "lock.shield",
                items: [
                    "Screen pixels, screenshots, camera, or microphone",
                    "Window titles, documents, typed text, clipboard, or URLs",
                    "Network traffic, cloud services, or analytics",
                    "Ordered activity from applications you did not select"
                ]
            )

            Text("No system privacy permission is requested during onboarding.")
                .font(.callout.weight(.medium))
                .accessibilityIdentifier("onboarding-no-permission-disclosure")
        }
        .accessibilityIdentifier("onboarding-privacy")
    }

    private var applications: some View {
        VStack(alignment: .leading, spacing: 22) {
            onboardingTitle(
                "Choose applications that tend to pull you away",
                subtitle: "Pick regular Mac applications. You can skip this now and choose them when you create a focus."
            )

            AppSelectionView(
                selectedApps: $selectedApps,
                browserWarningAcknowledged: $browserWarningAcknowledged,
                applicationPicker: applicationPicker
            )

            Text("Attune will never let you select itself or recovery-critical macOS applications.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("onboarding-applications")
    }

    private var modes: some View {
        VStack(alignment: .leading, spacing: 22) {
            onboardingTitle(
                "Choose the amount of friction each time",
                subtitle: "Every session shows its rule before it begins. Attune never escalates the mode silently."
            )

            OnboardingModeExplanation(
                title: "Soft — Pause",
                symbol: "pause.circle",
                description: "Return immediately, or open the selected app after an 8-second pause. Early stop uses a 10-second cooldown."
            )
            OnboardingModeExplanation(
                title: "Medium — Budget",
                symbol: "hourglass",
                description: "Use one shared allowance, then selected apps receive Strict behavior. Early stop uses a 30-second cooldown."
            )
            OnboardingModeExplanation(
                title: "Strict — Block",
                symbol: "hand.raised",
                description: "Hide selected apps, request normal termination, and re-hide an app that refuses. Early stop uses a 60-second cooldown."
            )

            VStack(alignment: .leading, spacing: 8) {
                Text("What Strict can — and cannot — promise")
                    .font(.headline)
                Text(
                    "Strict is best-effort enforcement from one ordinary application while Attune is running. Force Quit, logout, reboot, or quitting Attune ends enforcement. Attune never force-closes another app, so unsaved work is not destroyed; an app may remain running with its windows hidden."
                )
                .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("onboarding-strict-guarantee")
        }
        .accessibilityIdentifier("onboarding-modes")
    }

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: 12) {
            switch step {
            case .introduction:
                Button("Quit", action: onQuit)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("onboarding-quit")

                Spacer()

                Button("Continue") {
                    step = .privacy
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("onboarding-continue")

            case .privacy:
                backButton
                Spacer()
                continueButton(to: .applications)

            case .applications:
                backButton
                Spacer()
                Button(selectedApps.isEmpty ? "Skip for Now" : "Continue") {
                    step = .modes
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier(
                    selectedApps.isEmpty
                        ? "onboarding-skip-applications"
                        : "onboarding-continue"
                )

            case .modes:
                backButton
                Spacer()
                Button("Explore Attune", action: onExploreAttune)
                    .accessibilityIdentifier("onboarding-explore")
                Button("Create First Focus", action: onCreateFirstFocus)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("onboarding-create-first-focus")
            }
        }
    }

    private var backButton: some View {
        Button("Back") {
            guard let previousStep = OnboardingStep(rawValue: step.rawValue - 1) else {
                return
            }
            step = previousStep
        }
        .accessibilityIdentifier("onboarding-back")
    }

    private func continueButton(to nextStep: OnboardingStep) -> some View {
        Button("Continue") {
            step = nextStep
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.defaultAction)
        .accessibilityIdentifier("onboarding-continue")
    }

    private func onboardingTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.largeTitle.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("onboarding-title")
            Text(subtitle)
                .font(.title3)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func disclosureGroup(
        title: String,
        symbol: String,
        items: [String]
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol)
                .font(.headline)
            ForEach(items, id: \.self) { item in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .accessibilityHidden(true)
                    Text(item)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
    }
}

private enum OnboardingStep: Int, CaseIterable {
    case introduction
    case privacy
    case applications
    case modes
}

private struct OnboardingModeExplanation: View {
    let title: String
    let symbol: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}
