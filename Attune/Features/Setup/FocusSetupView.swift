import SwiftUI

enum FocusSetupValidationIssue: Equatable {
    case intentionRequired
    case intentionTooLong
    case applicationRequired
    case invalidApplication
    case duplicateApplication
    case protectedApplication
    case noAvailableApplication([String])
    case browserAcknowledgementRequired
    case timerDurationOutOfRange
    case goalDefinitionRequired
    case goalDefinitionTooLong
    case goalSafetyDurationOutOfRange
    case mediumAllowanceOutOfRange
    case mediumAllowanceMustBeShorterThanSession
    case strictReadinessRequired

    enum Section {
        case intention
        case completion
        case applications
        case mode
    }

    var section: Section {
        switch self {
        case .intentionRequired, .intentionTooLong:
            .intention
        case .timerDurationOutOfRange,
             .goalDefinitionRequired,
             .goalDefinitionTooLong,
             .goalSafetyDurationOutOfRange:
            .completion
        case .applicationRequired,
             .invalidApplication,
             .duplicateApplication,
             .protectedApplication,
             .noAvailableApplication,
             .browserAcknowledgementRequired:
            .applications
        case .mediumAllowanceOutOfRange,
             .mediumAllowanceMustBeShorterThanSession,
             .strictReadinessRequired:
            .mode
        }
    }

    var message: String {
        switch self {
        case .intentionRequired:
            "Enter what you’re focusing on."
        case .intentionTooLong:
            "Keep the focus intention to 120 characters or fewer."
        case .applicationRequired:
            "Select at least one available application."
        case .invalidApplication:
            "Remove the application without a stable bundle identifier."
        case .duplicateApplication:
            "Remove the duplicate application selection."
        case .protectedApplication:
            "Remove the protected application so Attune remains recoverable."
        case let .noAvailableApplication(names):
            if names.count == 1, let name = names.first {
                "\(name) is unavailable. Select at least one available application before starting."
            } else {
                "None of the selected applications are available. Select an available application before starting."
            }
        case .browserAcknowledgementRequired:
            "Acknowledge that Attune affects the entire browser before starting."
        case .timerDurationOutOfRange:
            "Choose a timer between 5 minutes and 4 hours."
        case .goalDefinitionRequired:
            "Describe an observable definition of done."
        case .goalDefinitionTooLong:
            "Keep “Done means” to 160 characters or fewer."
        case .goalSafetyDurationOutOfRange:
            "Choose a goal safety window between 15 minutes and 4 hours."
        case .mediumAllowanceOutOfRange:
            "Choose a shared allowance between 1 and 30 minutes."
        case .mediumAllowanceMustBeShorterThanSession:
            "Choose an allowance shorter than the focus duration or goal safety window."
        case .strictReadinessRequired:
            "Confirm that you saved work in selected apps before starting Strict mode."
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .intentionRequired:
            "focus-setup-error-intention-required"
        case .intentionTooLong:
            "focus-setup-error-intention-too-long"
        case .applicationRequired:
            "focus-setup-error-application-required"
        case .invalidApplication:
            "focus-setup-error-application-invalid"
        case .duplicateApplication:
            "focus-setup-error-application-duplicate"
        case .protectedApplication:
            "focus-setup-error-application-protected"
        case .noAvailableApplication:
            "focus-setup-error-application-unavailable"
        case .browserAcknowledgementRequired:
            "focus-setup-error-browser-acknowledgement"
        case .timerDurationOutOfRange:
            "focus-setup-error-timer-duration"
        case .goalDefinitionRequired:
            "focus-setup-error-goal-definition-required"
        case .goalDefinitionTooLong:
            "focus-setup-error-goal-definition-too-long"
        case .goalSafetyDurationOutOfRange:
            "focus-setup-error-goal-safety-duration"
        case .mediumAllowanceOutOfRange:
            "focus-setup-error-medium-allowance"
        case .mediumAllowanceMustBeShorterThanSession:
            "focus-setup-error-medium-allowance-duration"
        case .strictReadinessRequired:
            "focus-setup-error-strict-readiness"
        }
    }
}

@MainActor
enum FocusSetupValidator {
    static func issues(
        for draft: FocusDraft,
        browserWarningAcknowledged: Bool,
        isApplicationAvailable: (AppIdentity) -> Bool
    ) -> [FocusSetupValidationIssue] {
        var issues: [FocusSetupValidationIssue] = []
        let trimmedIntention = draft.intention
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedIntention.isEmpty {
            issues.append(.intentionRequired)
        } else if trimmedIntention.count > FocusConfiguration.maximumIntentionLength {
            issues.append(.intentionTooLong)
        }

        switch draft.completion {
        case let .timer(durationSeconds):
            if !FocusConfiguration.timerDurationRange.contains(durationSeconds) {
                issues.append(.timerDurationOutOfRange)
            }

        case let .goal(definitionOfDone, safetyDurationSeconds):
            let trimmedDefinition = definitionOfDone
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedDefinition.isEmpty {
                issues.append(.goalDefinitionRequired)
            } else if trimmedDefinition.count
                > FocusConfiguration.maximumGoalDefinitionLength {
                issues.append(.goalDefinitionTooLong)
            }
            if !FocusConfiguration.goalSafetyDurationRange
                .contains(safetyDurationSeconds) {
                issues.append(.goalSafetyDurationOutOfRange)
            }
        }

        if draft.selectedApps.isEmpty {
            issues.append(.applicationRequired)
        } else {
            var bundleIdentifiers = Set<String>()
            var unavailableApplicationNames: [String] = []
            var availableApplicationCount = 0

            for application in draft.selectedApps {
                let identifier = application.bundleIdentifier
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if identifier.isEmpty {
                    appendOnce(.invalidApplication, to: &issues)
                    continue
                }
                if !bundleIdentifiers.insert(identifier).inserted {
                    appendOnce(.duplicateApplication, to: &issues)
                }
                if ProtectedApplications.isProtected(bundleIdentifier: identifier) {
                    appendOnce(.protectedApplication, to: &issues)
                }
                if !isApplicationAvailable(application) {
                    unavailableApplicationNames.append(application.displayName)
                } else {
                    availableApplicationCount += 1
                }
            }

            if availableApplicationCount == 0 {
                issues.append(.noAvailableApplication(unavailableApplicationNames))
            }

            let containsBrowser = draft.selectedApps.contains { application in
                BrowserApplications.isBrowser(
                    bundleIdentifier: application.bundleIdentifier
                )
            }
            if containsBrowser, !browserWarningAcknowledged {
                issues.append(.browserAcknowledgementRequired)
            }
        }

        if case let .medium(allowanceSeconds) = draft.mode {
            if !FocusConfiguration.mediumAllowanceRange.contains(allowanceSeconds) {
                issues.append(.mediumAllowanceOutOfRange)
            } else if allowanceSeconds >= draft.completion.durationSeconds {
                issues.append(.mediumAllowanceMustBeShorterThanSession)
            }
        }

        return issues
    }

    private static func appendOnce(
        _ issue: FocusSetupValidationIssue,
        to issues: inout [FocusSetupValidationIssue]
    ) {
        if !issues.contains(issue) {
            issues.append(issue)
        }
    }
}

struct FocusSetupView: View {
    @Binding var draft: FocusDraft
    @Binding var browserWarningAcknowledged: Bool

    let applicationPicker: any ApplicationPicker
    let runningApplications: any RunningApplicationClient
    let onCancel: () -> Void
    let onStart: (FocusConfiguration) -> Void

    private let timerDefaultSeconds: Int
    private let goalSafetyDefaultSeconds: Int
    private let mediumAllowanceDefaultSeconds: Int

    @State private var completionChoice: FocusCompletionChoice
    @State private var timerDurationSeconds: Int
    @State private var goalDefinition: String
    @State private var goalSafetyDurationSeconds: Int
    @State private var mediumAllowanceSeconds: Int
    @State private var strictReadinessConfirmed = false

    init(
        draft: Binding<FocusDraft>,
        browserWarningAcknowledged: Binding<Bool>,
        applicationPicker: any ApplicationPicker,
        runningApplications: any RunningApplicationClient,
        timerDefaultSeconds: Int = 45 * 60,
        goalSafetyDefaultSeconds: Int = 120 * 60,
        mediumAllowanceDefaultSeconds: Int = 5 * 60,
        onCancel: @escaping () -> Void,
        onStart: @escaping (FocusConfiguration) -> Void
    ) {
        _draft = draft
        _browserWarningAcknowledged = browserWarningAcknowledged
        self.applicationPicker = applicationPicker
        self.runningApplications = runningApplications
        self.timerDefaultSeconds = timerDefaultSeconds
        self.goalSafetyDefaultSeconds = goalSafetyDefaultSeconds
        self.mediumAllowanceDefaultSeconds = mediumAllowanceDefaultSeconds
        self.onCancel = onCancel
        self.onStart = onStart
        if case let .medium(allowanceSeconds) = draft.wrappedValue.mode {
            _mediumAllowanceSeconds = State(initialValue: allowanceSeconds)
        } else {
            _mediumAllowanceSeconds = State(initialValue: mediumAllowanceDefaultSeconds)
        }

        switch draft.wrappedValue.completion {
        case let .timer(durationSeconds):
            _completionChoice = State(initialValue: .timer)
            _timerDurationSeconds = State(initialValue: durationSeconds)
            _goalDefinition = State(initialValue: "")
            _goalSafetyDurationSeconds = State(
                initialValue: goalSafetyDefaultSeconds
            )

        case let .goal(definitionOfDone, safetyDurationSeconds):
            _completionChoice = State(initialValue: .goal)
            _timerDurationSeconds = State(initialValue: timerDefaultSeconds)
            _goalDefinition = State(initialValue: definitionOfDone)
            _goalSafetyDurationSeconds = State(
                initialValue: safetyDurationSeconds
            )
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    setupHeader
                    intentionSection
                    completionSection
                    applicationsSection
                    modeSection
                    reviewSection
                }
                .frame(maxWidth: 780, alignment: .leading)
                .padding(.horizontal, 40)
                .padding(.vertical, 34)
            }

            Divider()

            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("focus-setup-cancel")

                Spacer()

                Button("Start Focus") {
                    startFocus()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!validationIssues.isEmpty)
                .accessibilityHint(startButtonAccessibilityHint)
                .accessibilityIdentifier("focus-setup-start")
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 18)
        }
        .frame(minWidth: 760, minHeight: 720)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityIdentifier("focus-setup-view")
    }

    static func firstUseDraft(
        selectedApps: [AppIdentity] = []
    ) -> FocusDraft {
        FocusDraft(
            intention: "",
            selectedApps: selectedApps,
            mode: .soft,
            completion: .timer(durationSeconds: 45 * 60)
        )
    }

    static func draft(from defaults: FocusDefaults) -> FocusDraft {
        FocusDraft(
            intention: "",
            selectedApps: defaults.selectedApps,
            mode: defaults.mode,
            completion: .timer(
                durationSeconds: defaults.timerDurationSeconds
            )
        )
    }

    private var setupHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("New Focus")
                .font(.largeTitle.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("focus-setup-title")
            Text("Choose one clear intention and the amount of support you want.")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private var intentionSection: some View {
        setupSection("Focus intention", identifier: "focus-setup-intention-section") {
            TextField(
                "What are you focusing on?",
                text: $draft.intention,
                axis: .vertical
            )
            .lineLimit(2...4)
            .textFieldStyle(.roundedBorder)
            .accessibilityIdentifier("focus-setup-intention")

            HStack {
                Text("Required. Be concrete enough that you can return to it at a glance.")
                Spacer()
                Text("\(draft.intention.count)/120")
                    .accessibilityLabel(
                        "\(draft.intention.count) of 120 characters"
                    )
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            validationMessages(for: .intention)
        }
    }

    private var completionSection: some View {
        setupSection("Completion rule", identifier: "focus-setup-completion-section") {
            Picker("Completion rule", selection: completionChoiceBinding) {
                ForEach(FocusCompletionChoice.allCases) { choice in
                    Text(choice.title).tag(choice)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityIdentifier("focus-setup-completion-rule")

            switch completionChoice {
            case .timer:
                timerConfiguration
            case .goal:
                goalConfiguration
            }

            validationMessages(for: .completion)
        }
    }

    private var timerConfiguration: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("The deadline continues through sleep, screen lock, and user switching.")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                ForEach([25, 45, 60], id: \.self) { minutes in
                    Button {
                        setTimerMinutes(minutes)
                    } label: {
                        Label(
                            "\(minutes) min",
                            systemImage: timerMinutes == minutes
                                ? "checkmark.circle.fill"
                                : "circle"
                        )
                    }
                    .accessibilityIdentifier("focus-setup-timer-preset-\(minutes)")
                }
            }

            Stepper(
                "Duration: \(timerMinutes) minutes",
                value: timerMinutesBinding,
                in: 5...240,
                step: 1
            )
            .accessibilityIdentifier("focus-setup-timer-minutes")
        }
    }

    private var goalConfiguration: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField(
                "Done means…",
                text: goalDefinitionBinding,
                axis: .vertical
            )
            .lineLimit(2...4)
            .textFieldStyle(.roundedBorder)
            .accessibilityIdentifier("focus-setup-goal-definition")

            HStack {
                Text("Use an observable outcome, such as “A reviewed first draft exists.”")
                Spacer()
                Text("\(goalDefinition.count)/160")
                    .accessibilityLabel(
                        "\(goalDefinition.count) of 160 characters"
                    )
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Stepper(
                "Safety window: \(goalSafetyMinutes) minutes",
                value: goalSafetyMinutesBinding,
                in: 15...240,
                step: 1
            )
            .accessibilityIdentifier("focus-setup-goal-safety-minutes")

            VStack(alignment: .leading, spacing: 6) {
                Text(
                    "You complete a goal deliberately. Attune shows “Done means” before confirmation: 3 seconds in Soft, 10 in Medium, and 30 in Strict."
                )
                Text(
                    "The safety deadline always unlocks your apps and records Goal window ended; it never claims the goal was complete. Choose a timer when you want a rule that cannot end by self-attestation."
                )
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("focus-setup-goal-safety-disclosure")
        }
    }

    private var applicationsSection: some View {
        setupSection("Applications", identifier: "focus-setup-applications-section") {
            Text("At least one currently available application is required.")
                .font(.callout)
                .foregroundStyle(.secondary)

            AppSelectionView(
                selectedApps: $draft.selectedApps,
                browserWarningAcknowledged: $browserWarningAcknowledged,
                applicationPicker: applicationPicker
            )

            validationMessages(for: .applications)
        }
    }

    private var modeSection: some View {
        setupSection("Mode", identifier: "focus-setup-mode-section") {
            modeOption(
                title: "Soft — Pause",
                description: "Return immediately, or open the selected app after an 8-second pause.",
                isSelected: draft.mode == .soft,
                accessibilityIdentifier: "focus-mode-soft"
            ) {
                draft.mode = .soft
            }

            modeOption(
                title: "Medium — Budget",
                description: "Use one shared allowance (\(mediumAllowanceDefaultSeconds / 60) minutes by default), then apply Strict behavior.",
                isSelected: isMediumMode,
                accessibilityIdentifier: "focus-mode-medium"
            ) {
                draft.mode = .medium(allowanceSeconds: mediumAllowanceSeconds)
                strictReadinessConfirmed = false
            }

            if isMediumMode {
                Stepper(
                    "Shared allowance: \(mediumAllowanceSeconds / 60) minutes",
                    value: mediumAllowanceMinutesBinding,
                    in: 1...30,
                    step: 1
                )
                .accessibilityIdentifier("focus-setup-medium-allowance")
            }

            modeOption(
                title: "Strict — Block",
                description: "Hide selected apps, request normal termination, and keep refusing apps out of the foreground without force-closing them.",
                isSelected: draft.mode == .strict,
                accessibilityIdentifier: "focus-mode-strict"
            ) {
                draft.mode = .strict
            }

            if draft.mode == .strict {
                if !strictRunningSelectedApps.isEmpty {
                    Label(
                        "Currently running: \(strictRunningSelectedApps.map(\.displayName).joined(separator: ", ")). Save your work first.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("focus-setup-strict-running-apps")
                }
                Toggle(
                    "I saved work in selected apps and I’m ready for Attune to hide them and ask them to quit.",
                    isOn: $strictReadinessConfirmed
                )
                .toggleStyle(.checkbox)
                .accessibilityIdentifier("focus-setup-strict-readiness")
            }

            Text(
                "Strict is best-effort while Attune runs. A selected app may appear briefly, remain running with hidden windows, or continue background audio and notifications. Force Quit, logout, reboot, or quitting Attune ends enforcement."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.top, 2)
            .accessibilityIdentifier("focus-setup-strict-guarantee")

            validationMessages(for: .mode)
        }
    }

    private var reviewSection: some View {
        setupSection("Review", identifier: "focus-setup-review-section") {
            Text(reviewSummary)
                .font(.headline)
                .accessibilityIdentifier("focus-setup-summary")

            if !unavailableSelectedApps.isEmpty, validationIssues.isEmpty {
                Label(
                    unavailableDisclosure,
                    systemImage: "exclamationmark.triangle"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("focus-setup-unavailable-disclosure")
            }

            if validationIssues.isEmpty {
                Label("Ready to start", systemImage: "checkmark.circle")
                    .font(.callout)
                    .accessibilityIdentifier("focus-setup-ready")
            } else {
                Text("Resolve the specific items above before starting.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("focus-setup-needs-attention")
            }
        }
    }

    private func setupSection<Content: View>(
        _ title: String,
        identifier: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityIdentifier(identifier)
    }

    private func modeOption(
        title: String,
        description: String,
        isSelected: Bool,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(
                    systemName: isSelected
                        ? "checkmark.circle.fill"
                        : "circle"
                )
                .font(.title3)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                    Text(description)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer()
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? Color.accentColor.opacity(0.1) : Color.clear,
                in: RoundedRectangle(cornerRadius: 11)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 11)
                    .stroke(
                        isSelected ? Color.accentColor : Color.secondary.opacity(0.25),
                        lineWidth: isSelected ? 2 : 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    @ViewBuilder
    private func validationMessages(
        for section: FocusSetupValidationIssue.Section
    ) -> some View {
        let sectionIssues = validationIssues.filter { issue in
            issue.section == section
        }

        ForEach(sectionIssues, id: \.accessibilityIdentifier) { issue in
            Label(issue.message, systemImage: "exclamationmark.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
                .focusable()
                .accessibilityLabel("Setup issue: \(issue.message)")
                .accessibilityIdentifier(issue.accessibilityIdentifier)
        }
    }

    private var completionChoiceBinding: Binding<FocusCompletionChoice> {
        Binding(
            get: { completionChoice },
            set: { newChoice in
                completionChoice = newChoice
                switch newChoice {
                case .timer:
                    draft.completion = .timer(
                        durationSeconds: timerDurationSeconds
                    )
                case .goal:
                    draft.completion = .goal(
                        definitionOfDone: goalDefinition,
                        safetyDurationSeconds: goalSafetyDurationSeconds
                    )
                }
            }
        )
    }

    private var timerMinutesBinding: Binding<Int> {
        Binding(
            get: { timerMinutes },
            set: { setTimerMinutes($0) }
        )
    }

    private var goalDefinitionBinding: Binding<String> {
        Binding(
            get: { goalDefinition },
            set: { newDefinition in
                goalDefinition = newDefinition
                draft.completion = .goal(
                    definitionOfDone: newDefinition,
                    safetyDurationSeconds: goalSafetyDurationSeconds
                )
            }
        )
    }

    private var goalSafetyMinutesBinding: Binding<Int> {
        Binding(
            get: { goalSafetyMinutes },
            set: { minutes in
                goalSafetyDurationSeconds = minutes * 60
                draft.completion = .goal(
                    definitionOfDone: goalDefinition,
                    safetyDurationSeconds: goalSafetyDurationSeconds
                )
            }
        )
    }

    private var validationIssues: [FocusSetupValidationIssue] {
        var issues = FocusSetupValidator.issues(
            for: draft,
            browserWarningAcknowledged: browserWarningAcknowledged,
            isApplicationAvailable: applicationPicker.isAvailable
        )
        if draft.mode == .strict, !strictReadinessConfirmed {
            issues.append(.strictReadinessRequired)
        }
        return issues
    }

    private var startButtonAccessibilityHint: String {
        guard let firstIssue = validationIssues.first else {
            return "Starts this focus with the selected mode and fixed configuration."
        }
        return "Unavailable. \(firstIssue.message)"
    }

    private var timerMinutes: Int {
        timerDurationSeconds / 60
    }

    private var goalSafetyMinutes: Int {
        goalSafetyDurationSeconds / 60
    }

    private var mediumAllowanceMinutesBinding: Binding<Int> {
        Binding(
            get: { mediumAllowanceSeconds / 60 },
            set: { minutes in
                mediumAllowanceSeconds = minutes * 60
                draft.mode = .medium(allowanceSeconds: mediumAllowanceSeconds)
            }
        )
    }

    private var isMediumMode: Bool {
        if case .medium = draft.mode {
            return true
        }
        return false
    }

    private var reviewSummary: String {
        let completionSummary: String
        switch draft.completion {
        case let .timer(durationSeconds):
            completionSummary = "\(durationSeconds / 60) minutes"
        case let .goal(_, safetyDurationSeconds):
            completionSummary = "Goal · \(safetyDurationSeconds / 60)-minute safety window"
        }

        let modeSummary: String
        switch draft.mode {
        case .soft:
            modeSummary = "Soft"
        case let .medium(allowanceSeconds):
            modeSummary = "Medium · \(allowanceSeconds / 60)-minute shared allowance"
        case .strict:
            modeSummary = "Strict"
        }

        let applicationWord = draft.selectedApps.count == 1 ? "application" : "applications"
        return "\(completionSummary) · \(modeSummary) · \(draft.selectedApps.count) selected \(applicationWord)"
    }

    private var unavailableSelectedApps: [AppIdentity] {
        draft.selectedApps.filter { application in
            !applicationPicker.isAvailable(application)
        }
    }

    private var strictRunningSelectedApps: [AppIdentity] {
        draft.selectedApps.filter { application in
            !runningApplications.instances(
                bundleIdentifier: application.bundleIdentifier
            ).isEmpty
        }
    }

    private var unavailableDisclosure: String {
        let names = unavailableSelectedApps.map(\.displayName)
        if names.count == 1, let name = names.first {
            return "\(name) is currently unavailable and will be ignored safely."
        }
        return "\(names.count) selected applications are currently unavailable and will be ignored safely."
    }

    private func setTimerMinutes(_ minutes: Int) {
        timerDurationSeconds = minutes * 60
        draft.completion = .timer(
            durationSeconds: timerDurationSeconds
        )
    }

    private func startFocus() {
        guard validationIssues.isEmpty,
              let configuration = try? draft.validated() else {
            return
        }
        onStart(configuration)
    }
}

private enum FocusCompletionChoice: String, CaseIterable, Identifiable {
    case timer
    case goal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .timer:
            "Timer"
        case .goal:
            "Goal"
        }
    }
}
