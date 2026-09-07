import Testing
@testable import Attune

@Suite("Focus setup")
struct FocusSetupTests {
    private let application = AppIdentity(
        bundleIdentifier: "com.example.Distraction",
        displayName: "Distraction"
    )

    @Test("First use starts empty with the exact Soft 45-minute default")
    @MainActor
    func firstUseDefaults() {
        let draft = FocusSetupView.firstUseDraft()

        #expect(draft.intention.isEmpty)
        #expect(draft.selectedApps.isEmpty)
        #expect(draft.mode == .soft)
        #expect(draft.completion == .timer(durationSeconds: 45 * 60))
    }

    @Test("Saved defaults prefill apps, mode, and timer without intention text")
    @MainActor
    func mapsSavedDefaults() {
        let defaults = FocusDefaults(
            selectedApps: [application],
            mode: .medium(allowanceSeconds: 7 * 60),
            timerDurationSeconds: 60 * 60,
            goalSafetyDurationSeconds: 150 * 60,
            mediumAllowanceSeconds: 7 * 60
        )

        let draft = FocusSetupView.draft(from: defaults)

        #expect(draft.intention.isEmpty)
        #expect(draft.selectedApps == [application])
        #expect(draft.mode == .medium(allowanceSeconds: 7 * 60))
        #expect(draft.completion == .timer(durationSeconds: 60 * 60))
    }

    @Test("Valid available Soft setup has no UI validation issues")
    @MainActor
    func acceptsValidSoftSetup() {
        let issues = FocusSetupValidator.issues(
            for: validDraft(),
            browserWarningAcknowledged: false,
            isApplicationAvailable: { _ in true }
        )

        #expect(issues.isEmpty)
    }

    @Test("Required setup fields expose specific validation issues")
    @MainActor
    func requiresIntentionAndApplication() {
        let draft = FocusDraft(
            intention: " \n ",
            selectedApps: [],
            mode: .soft,
            completion: .timer(durationSeconds: 45 * 60)
        )

        let issues = FocusSetupValidator.issues(
            for: draft,
            browserWarningAcknowledged: false,
            isApplicationAvailable: { _ in true }
        )

        #expect(issues == [.intentionRequired, .applicationRequired])
        #expect(issues.map(\.message) == [
            "Enter what you’re focusing on.",
            "Select at least one available application."
        ])
    }

    @Test("A missing saved application blocks Start with its display name")
    @MainActor
    func requiresAvailableApplication() {
        let issues = FocusSetupValidator.issues(
            for: validDraft(),
            browserWarningAcknowledged: false,
            isApplicationAvailable: { _ in false }
        )

        #expect(issues == [.noAvailableApplication(["Distraction"])])
        #expect(issues.first?.message ==
            "Distraction is unavailable. Select at least one available application before starting.")
    }

    @Test("One available application allows Start while a missing saved app is disclosed")
    @MainActor
    func allowsAvailableApplicationAlongsideMissingSelection() {
        var draft = validDraft()
        draft.selectedApps.append(AppIdentity(
            bundleIdentifier: "com.example.Missing",
            displayName: "Missing"
        ))

        let issues = FocusSetupValidator.issues(
            for: draft,
            browserWarningAcknowledged: false,
            isApplicationAvailable: { application in
                application.bundleIdentifier == "com.example.Distraction"
            }
        )

        #expect(issues.isEmpty)
    }

    @Test("A browser requires the whole-browser acknowledgement")
    @MainActor
    func requiresBrowserAcknowledgement() {
        var draft = validDraft()
        draft.selectedApps = [
            AppIdentity(
                bundleIdentifier: "com.apple.Safari",
                displayName: "Safari"
            )
        ]

        let unacknowledgedIssues = FocusSetupValidator.issues(
            for: draft,
            browserWarningAcknowledged: false,
            isApplicationAvailable: { _ in true }
        )
        let acknowledgedIssues = FocusSetupValidator.issues(
            for: draft,
            browserWarningAcknowledged: true,
            isApplicationAvailable: { _ in true }
        )

        #expect(unacknowledgedIssues == [.browserAcknowledgementRequired])
        #expect(acknowledgedIssues.isEmpty)
    }

    @Test("Goal setup requires observable done text and an exact safety range")
    @MainActor
    func validatesGoalFields() {
        var draft = validDraft()
        draft.completion = .goal(
            definitionOfDone: " ",
            safetyDurationSeconds: 14 * 60
        )

        let missingIssues = FocusSetupValidator.issues(
            for: draft,
            browserWarningAcknowledged: false,
            isApplicationAvailable: { _ in true }
        )

        draft.completion = .goal(
            definitionOfDone: String(repeating: "x", count: 161),
            safetyDurationSeconds: 240 * 60
        )
        let longDefinitionIssues = FocusSetupValidator.issues(
            for: draft,
            browserWarningAcknowledged: false,
            isApplicationAvailable: { _ in true }
        )

        #expect(missingIssues == [
            .goalDefinitionRequired,
            .goalSafetyDurationOutOfRange
        ])
        #expect(longDefinitionIssues == [.goalDefinitionTooLong])
    }

    @Test("Medium and Strict are valid setup modes")
    @MainActor
    func acceptsImplementedModes() {
        var draft = validDraft()
        draft.mode = .medium(allowanceSeconds: 5 * 60)
        let mediumIssues = FocusSetupValidator.issues(
            for: draft,
            browserWarningAcknowledged: false,
            isApplicationAvailable: { _ in true }
        )

        draft.mode = .strict
        let strictIssues = FocusSetupValidator.issues(
            for: draft,
            browserWarningAcknowledged: false,
            isApplicationAvailable: { _ in true }
        )

        #expect(mediumIssues.isEmpty)
        #expect(strictIssues.isEmpty)
    }

    private func validDraft() -> FocusDraft {
        FocusDraft(
            intention: "Write the launch brief",
            selectedApps: [application],
            mode: .soft,
            completion: .timer(durationSeconds: 45 * 60)
        )
    }
}
