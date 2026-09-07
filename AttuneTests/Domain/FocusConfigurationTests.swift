import Foundation
import Testing
@testable import Attune

@Suite("Focus configuration validation")
struct FocusConfigurationTests {
    @Test("Intention uses trimmed one through 120 character boundaries")
    func intentionBoundaries() throws {
        var draft = validDraft()
        draft.intention = "  a  "
        #expect(try draft.validated().intention == "a")

        draft.intention = String(repeating: "a", count: 120)
        #expect(try draft.validated().intention.count == 120)

        draft.intention = " \n\t "
        #expect(throws: FocusValidationError.intentionRequired) {
            try draft.validated()
        }

        draft.intention = String(repeating: "a", count: 121)
        #expect(throws: FocusValidationError.intentionTooLong) {
            try draft.validated()
        }
    }

    @Test("Timer accepts only five minutes through four hours")
    func timerBoundaries() throws {
        var draft = validDraft()

        for duration in [300, 14_400] {
            draft.completion = .timer(durationSeconds: duration)
            #expect(try draft.validated().completion == .timer(durationSeconds: duration))
        }

        for duration in [299, 14_401] {
            draft.completion = .timer(durationSeconds: duration)
            #expect(throws: FocusValidationError.timerDurationOutOfRange) {
                try draft.validated()
            }
        }
    }

    @Test("Goal definition and safety window use their exact boundaries")
    func goalBoundaries() throws {
        var draft = validDraft()

        draft.completion = .goal(definitionOfDone: "  x  ", safetyDurationSeconds: 900)
        #expect(
            try draft.validated().completion
                == .goal(definitionOfDone: "x", safetyDurationSeconds: 900)
        )

        let maximumDefinition = String(repeating: "x", count: 160)
        draft.completion = .goal(
            definitionOfDone: maximumDefinition,
            safetyDurationSeconds: 14_400
        )
        #expect(try draft.validated().completion == draft.completion)

        draft.completion = .goal(definitionOfDone: " \n ", safetyDurationSeconds: 900)
        #expect(throws: FocusValidationError.goalDefinitionRequired) {
            try draft.validated()
        }

        draft.completion = .goal(
            definitionOfDone: String(repeating: "x", count: 161),
            safetyDurationSeconds: 900
        )
        #expect(throws: FocusValidationError.goalDefinitionTooLong) {
            try draft.validated()
        }

        for duration in [899, 14_401] {
            draft.completion = .goal(definitionOfDone: "Shipped", safetyDurationSeconds: duration)
            #expect(throws: FocusValidationError.goalSafetyDurationOutOfRange) {
                try draft.validated()
            }
        }
    }

    @Test("Medium allowance is bounded and shorter than the session")
    func mediumBoundaries() throws {
        var draft = validDraft()
        draft.completion = .timer(durationSeconds: 3_600)

        for allowance in [60, 1_800] {
            draft.mode = .medium(allowanceSeconds: allowance)
            #expect(try draft.validated().mode == .medium(allowanceSeconds: allowance))
        }

        for allowance in [59, 1_801] {
            draft.mode = .medium(allowanceSeconds: allowance)
            #expect(throws: FocusValidationError.mediumAllowanceOutOfRange) {
                try draft.validated()
            }
        }

        draft.completion = .timer(durationSeconds: 300)
        draft.mode = .medium(allowanceSeconds: 300)
        #expect(throws: FocusValidationError.mediumAllowanceMustBeShorterThanSession) {
            try draft.validated()
        }

        draft.completion = .goal(definitionOfDone: "Draft complete", safetyDurationSeconds: 900)
        draft.mode = .medium(allowanceSeconds: 900)
        #expect(throws: FocusValidationError.mediumAllowanceMustBeShorterThanSession) {
            try draft.validated()
        }
    }

    @Test("At least one unique, valid, non-protected application is required")
    func selectedApplicationValidation() throws {
        var draft = validDraft()

        draft.selectedApps = []
        #expect(throws: FocusValidationError.applicationRequired) {
            try draft.validated()
        }

        let application = AppIdentity(
            bundleIdentifier: "com.example.Distraction",
            displayName: "Distraction"
        )
        draft.selectedApps = [application, application]
        #expect(throws: FocusValidationError.duplicateApplication) {
            try draft.validated()
        }

        draft.selectedApps = [AppIdentity(bundleIdentifier: "", displayName: "Missing ID")]
        #expect(throws: FocusValidationError.invalidApplicationIdentifier) {
            try draft.validated()
        }

        for identifier in ProtectedApplications.bundleIdentifiers {
            draft.selectedApps = [
                AppIdentity(bundleIdentifier: identifier, displayName: "Protected")
            ]
            #expect(throws: FocusValidationError.protectedApplication) {
                try draft.validated()
            }
        }
    }

    @Test("Validation returns an immutable trimmed snapshot")
    func immutableSnapshot() throws {
        let originalApplication = AppIdentity(
            bundleIdentifier: "com.example.Distraction",
            displayName: "Distraction"
        )
        var draft = FocusDraft(
            intention: "  Write the launch brief  ",
            selectedApps: [originalApplication],
            mode: .soft,
            completion: .goal(
                definitionOfDone: "  A reviewed first draft exists  ",
                safetyDurationSeconds: 3_600
            )
        )

        let configuration = try draft.validated()
        draft.intention = "Changed later"
        draft.selectedApps = []
        draft.completion = .timer(durationSeconds: 300)

        #expect(configuration.intention == "Write the launch brief")
        #expect(configuration.selectedApps == [originalApplication])
        #expect(
            configuration.completion == .goal(
                definitionOfDone: "A reviewed first draft exists",
                safetyDurationSeconds: 3_600
            )
        )
    }

    private func validDraft() -> FocusDraft {
        FocusDraft(
            intention: "Write the launch brief",
            selectedApps: [
                AppIdentity(
                    bundleIdentifier: "com.example.Distraction",
                    displayName: "Distraction"
                )
            ],
            mode: .soft,
            completion: .timer(durationSeconds: 2_700)
        )
    }
}
