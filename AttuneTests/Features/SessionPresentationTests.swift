import Foundation
import Testing
@testable import Attune

@Suite
struct SessionPresentationTests {
    @Test
    func stopReasonsMatchTheProductContract() {
        #expect(StopReasonOption.all.map(\.reason) == [
            .urgentNeed,
            .selectedApplicationNeeded,
            .taskOrPlanChanged,
            .setupNotHelping,
            .other
        ])
        #expect(StopReasonOption.all.map(\.title) == [
            "Urgent need",
            "Need a selected app for the task",
            "Task or plan changed",
            "This setup is not helping",
            "Other"
        ])
    }

    @Test
    func earlyStopRequiresBothThePassiveGateAndAReason() {
        let coolingDown = StopFocusViewModel(
            intention: "Write the brief",
            modeLabel: "Soft · Pause",
            remainingTimeLabel: "Time remaining",
            remainingTimeText: "24:12",
            phase: .coolingDown(message: "End Focus is available in 10 seconds."),
            selectedReason: .urgentNeed
        )
        let noReason = StopFocusViewModel(
            intention: coolingDown.intention,
            modeLabel: coolingDown.modeLabel,
            remainingTimeLabel: coolingDown.remainingTimeLabel,
            remainingTimeText: coolingDown.remainingTimeText,
            phase: .ready(message: "You can choose whether to end this focus."),
            selectedReason: nil
        )
        let ready = StopFocusViewModel(
            intention: noReason.intention,
            modeLabel: noReason.modeLabel,
            remainingTimeLabel: noReason.remainingTimeLabel,
            remainingTimeText: noReason.remainingTimeText,
            phase: noReason.phase,
            selectedReason: .taskOrPlanChanged
        )

        #expect(!coolingDown.canConfirmEnd)
        #expect(!noReason.canConfirmEnd)
        #expect(ready.canConfirmEnd)
    }

    @Test
    func activeProgressIsClampedForPresentation() {
        let model = ActiveSessionViewModel(
            intention: "Write the brief",
            modeLabel: "Soft · Pause",
            timeLabel: "Time remaining",
            remainingTimeText: "24:12",
            interventionCount: 0,
            progressFraction: 1.4,
            privacyMessage: "Stored locally on this Mac."
        )

        #expect(model.progressFraction == 1)
    }

    @Test
    func overlayCarriesRibbonCopyToneAndCallerOwnedGate() {
        let intent = OverlayIntent(
            compactTitle: "Focus check: Example",
            title: "You chose to focus",
            message: "Example is outside “Write the brief”.",
            primaryActionDetail: "Attune won’t hide Example unless you choose Return to Focus.",
            primaryActionTitle: "Return to Focus",
            secondaryActionTitle: "Open Anyway",
            secondaryActionStatus: "Open Anyway is available in 8 seconds.",
            isSecondaryActionEnabled: false,
            tone: .standard
        )

        #expect(intent.compactTitle == "Focus check: Example")
        #expect(
            intent.primaryActionDetail
                == "Attune won’t hide Example unless you choose Return to Focus."
        )
        #expect(intent.primaryActionTitle == "Return to Focus")
        #expect(intent.secondaryActionStatus == "Open Anyway is available in 8 seconds.")
        #expect(!intent.isSecondaryActionEnabled)
        #expect(intent.tone == .standard)
    }

    @Test
    func overlayRetargetsOnlyForANewIntervention() {
        let sessionID = UUID()
        let firstID = OverlayInterventionID(
            sessionID: sessionID,
            bundleIdentifier: "test.first",
            presentedAt: .seconds(1)
        )
        let secondID = OverlayInterventionID(
            sessionID: sessionID,
            bundleIdentifier: "test.second",
            presentedAt: .seconds(2)
        )
        let first = OverlayIntent(
            interventionID: firstID,
            title: "First",
            message: "First message",
            primaryActionTitle: "Return to Focus"
        )
        let updatedFirst = OverlayIntent(
            interventionID: firstID,
            title: "First updated",
            message: "First updated message",
            primaryActionTitle: "Return to Focus",
            tone: .warning
        )
        let second = OverlayIntent(
            interventionID: secondID,
            title: "Second",
            message: "Second message",
            primaryActionTitle: "Return to Focus"
        )

        #expect(first.startsNewIntervention(comparedTo: nil))
        #expect(!updatedFirst.startsNewIntervention(comparedTo: first))
        #expect(second.startsNewIntervention(comparedTo: updatedFirst))
    }

    @Test
    func overlayRepresentsTheExplicitReturnContract() {
        let intent = OverlayIntent(
            compactTitle: "Focus check: Example",
            title: "You chose to focus",
            message: "Example is outside “Write the brief”.",
            primaryActionDetail: "Attune won’t hide Example unless you choose Return to Focus.",
            primaryActionTitle: "Return to Focus",
            tone: .standard
        )

        #expect(intent.tone == .standard)
        #expect(intent.primaryActionDetail?.contains("won’t hide") == true)
        #expect(intent.primaryActionDetail?.contains("Return to Focus") == true)
        #expect(intent.primaryActionDetail?.contains("quit") == false)
    }
}
