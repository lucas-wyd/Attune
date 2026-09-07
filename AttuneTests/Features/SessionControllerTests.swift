import Foundation
import Testing
@testable import Attune

@Suite("Session controller")
@MainActor
struct SessionControllerTests {
    private let startTime = Date(timeIntervalSince1970: 2_100_000_000)
    private let sessionID = UUID(uuidString: "10101010-2020-3030-4040-505050505050")!
    private let selectedApplication = AppIdentity(
        bundleIdentifier: "test.distraction",
        displayName: "Distraction"
    )

    @Test("Reduced state presents the warning before persistence without hiding")
    func publishesBeforeVisibilityEffectsAndPersistence() async throws {
        let recorder = LockedEventRecorder()
        let fixture = makeFixture(recorder: recorder)

        _ = fixture.controller.start(timerConfiguration())
        _ = await fixture.controller.waitForPendingPersistence()
        await fixture.repository.clearOperations()
        recorder.clear()

        fixture.controller.handleWorkspaceEvent(.activated(selectedApplication))
        await drainTasks()

        #expect(recorder.snapshot().first == "panel:Return to Focus")
        #expect(recorder.snapshot().contains("persist:state"))
        #expect(fixture.applications.hiddenBundleIdentifiers.isEmpty)
        #expect(fixture.applications.normalTerminationBundleIdentifiers.isEmpty)
        #expect(fixture.controller.activeSession?.metrics.interventionCount == 1)
        #expect(fixture.overlays.lastIntent?.compactTitle == "Focus check: Distraction")
        #expect(
            fixture.overlays.lastIntent?.primaryActionDetail
                == "Attune won’t hide Distraction unless you choose Return to Focus."
        )
        fixture.controller.stopWorkspaceObservation()
    }

    @Test("Soft intervention enables Open Anyway after eight monotonic seconds")
    func softOpenGateAndActions() async {
        let fixture = makeFixture()
        _ = fixture.controller.start(timerConfiguration())
        await drainTasks()

        fixture.controller.handleWorkspaceEvent(.activated(selectedApplication))
        await drainTasks()
        #expect(fixture.overlays.lastIntent?.isSecondaryActionEnabled == false)
        #expect(
            fixture.overlays.lastIntent?.secondaryActionStatus
                == "Open Anyway is available in 8 seconds."
        )
        #expect(fixture.controller.softOpenAvailable == false)

        fixture.elapsedClock.advance(by: .seconds(1))
        await drainTasks()
        #expect(
            fixture.overlays.lastIntent?.secondaryActionStatus
                == "Open Anyway is available in 7 seconds."
        )

        fixture.elapsedClock.advance(by: .seconds(6))
        await drainTasks()
        #expect(fixture.controller.softOpenAvailable == false)

        fixture.elapsedClock.advance(by: .seconds(1))
        await drainTasks()
        #expect(fixture.controller.softOpenAvailable)
        #expect(fixture.overlays.lastIntent?.isSecondaryActionEnabled == true)

        fixture.overlays.perform(.secondary)
        #expect(fixture.applications.activationBundleIdentifiers.isEmpty)
        #expect(fixture.applications.hiddenBundleIdentifiers.isEmpty)
        #expect(fixture.controller.activeSession?.metrics.softOpenCount == 1)
        #expect(fixture.controller.runtime.softAllowedBundleIdentifier == "test.distraction")
        fixture.controller.stopWorkspaceObservation()
    }

    @Test("Revisiting one selected app keeps its unresolved countdown moving")
    func sameSelectedAppReactivationKeepsCountdownMoving() async {
        let fixture = makeFixture()
        let editor = AppIdentity(
            bundleIdentifier: "test.editor",
            displayName: "Editor"
        )
        _ = fixture.controller.start(timerConfiguration())
        await drainTasks()

        fixture.controller.handleWorkspaceEvent(.activated(selectedApplication))
        await drainTasks()
        fixture.elapsedClock.advance(by: .seconds(2))
        await drainTasks()
        #expect(
            fixture.overlays.lastIntent?.secondaryActionStatus
                == "Open Anyway is available in 6 seconds."
        )

        fixture.controller.handleWorkspaceEvent(.activated(editor))
        fixture.controller.handleWorkspaceEvent(.activated(selectedApplication))
        await drainTasks()
        #expect(fixture.controller.activeSession?.metrics.interventionCount == 1)
        #expect(
            fixture.overlays.lastIntent?.secondaryActionStatus
                == "Open Anyway is available in 6 seconds."
        )

        fixture.controller.handleWorkspaceEvent(.activated(editor))
        fixture.elapsedClock.advance(by: .seconds(1))
        await drainTasks()
        #expect(
            fixture.overlays.lastIntent?.secondaryActionStatus
                == "Open Anyway is available in 5 seconds."
        )
        fixture.controller.stopWorkspaceObservation()
    }

    @Test("A different selected app replaces the unresolved countdown with a fresh gate")
    func differentSelectedAppStartsFreshCountdown() async {
        let fixture = makeFixture()
        let secondSelectedApplication = AppIdentity(
            bundleIdentifier: "test.second-distraction",
            displayName: "Second Distraction"
        )
        _ = fixture.controller.start(timerConfiguration(selectedApps: [
            selectedApplication,
            secondSelectedApplication
        ]))
        await drainTasks()

        fixture.controller.handleWorkspaceEvent(.activated(selectedApplication))
        await drainTasks()
        fixture.elapsedClock.advance(by: .seconds(2))
        await drainTasks()

        fixture.controller.handleWorkspaceEvent(.activated(secondSelectedApplication))
        await drainTasks()
        #expect(
            fixture.overlays.lastIntent?.compactTitle
                == "Focus check: Second Distraction"
        )
        #expect(
            fixture.overlays.lastIntent?.secondaryActionStatus
                == "Open Anyway is available in 8 seconds."
        )

        fixture.elapsedClock.advance(by: .seconds(1))
        await drainTasks()
        #expect(
            fixture.overlays.lastIntent?.secondaryActionStatus
                == "Open Anyway is available in 7 seconds."
        )
        fixture.controller.stopWorkspaceObservation()
    }

    @Test("Return hides the selected app, switches to the fallback, and later warns again")
    func softReturnUsesRuntimeFallbackAfterHiding() async {
        let fixture = makeFixture()
        _ = fixture.controller.start(timerConfiguration())
        await drainTasks()
        fixture.controller.handleWorkspaceEvent(.activated(AppIdentity(
            bundleIdentifier: "test.editor",
            displayName: "Editor"
        )))
        fixture.controller.handleWorkspaceEvent(.activated(selectedApplication))
        await drainTasks()

        let dismissCountBeforeReturn = fixture.overlays.dismissCount
        fixture.overlays.perform(.primary)
        fixture.controller.returnToFocus()
        await drainTasks()

        #expect(fixture.applications.hiddenBundleIdentifiers == ["test.distraction"])
        #expect(fixture.applications.normalTerminationBundleIdentifiers.isEmpty)
        #expect(fixture.overlays.dismissCount == dismissCountBeforeReturn + 1)
        #expect(fixture.applications.activationBundleIdentifiers == ["test.editor"])
        #expect(fixture.controller.activeSession?.metrics.softReturnCount == 1)

        let presentationCountBeforeRepeat = fixture.overlays.presentCount
        fixture.elapsedClock.advance(by: .seconds(2))
        fixture.controller.handleWorkspaceEvent(.activated(selectedApplication))
        await drainTasks()

        #expect(fixture.overlays.presentCount == presentationCountBeforeRepeat + 1)
        #expect(fixture.controller.activeSession?.metrics.interventionCount == 2)
        #expect(fixture.applications.hiddenBundleIdentifiers == ["test.distraction"])

        fixture.overlays.perform(.primary)
        await drainTasks()
        #expect(fixture.applications.hiddenBundleIdentifiers == [
            "test.distraction",
            "test.distraction"
        ])
        #expect(fixture.applications.activationBundleIdentifiers == [
            "test.editor",
            "test.editor"
        ])
        #expect(fixture.controller.activeSession?.metrics.softReturnCount == 2)
        fixture.controller.stopWorkspaceObservation()
    }

    @Test("An unavailable Return target records failure after hiding the selected app")
    func unavailableReturnTargetRecordsFailureAfterHiding() async {
        let fixture = makeFixture()
        fixture.applications.activationSummary = .missingApplication
        _ = fixture.controller.start(timerConfiguration())
        await drainTasks()

        fixture.controller.handleWorkspaceEvent(.activated(selectedApplication))
        await drainTasks()
        fixture.overlays.perform(.primary)
        await drainTasks()

        #expect(fixture.applications.activationBundleIdentifiers == ["com.apple.finder"])
        #expect(fixture.applications.hiddenBundleIdentifiers == ["test.distraction"])
        #expect(fixture.applications.normalTerminationBundleIdentifiers.isEmpty)
        #expect(fixture.controller.activeSession?.metrics.enforcementFailureCount == 1)
        #expect(fixture.controller.runtime.intervention == nil)
        fixture.controller.stopWorkspaceObservation()
    }

    @Test("A failed Return hide keeps the ribbon open and never switches or quits")
    func failedReturnHideKeepsRibbonOpen() async {
        let fixture = makeFixture()
        fixture.applications.hideSummary = .failed
        _ = fixture.controller.start(timerConfiguration())
        await drainTasks()

        fixture.controller.handleWorkspaceEvent(.activated(selectedApplication))
        await drainTasks()
        let dismissCountBeforeReturn = fixture.overlays.dismissCount
        fixture.overlays.perform(.primary)
        await drainTasks()

        #expect(fixture.applications.hiddenBundleIdentifiers == ["test.distraction"])
        #expect(fixture.applications.activationBundleIdentifiers.isEmpty)
        #expect(fixture.applications.normalTerminationBundleIdentifiers.isEmpty)
        #expect(fixture.overlays.dismissCount == dismissCountBeforeReturn)
        #expect(fixture.controller.runtime.intervention != nil)
        #expect(fixture.controller.runtime.softReturnFailed)
        #expect(fixture.controller.activeSession?.metrics.enforcementFailureCount == 1)
        #expect(fixture.overlays.lastIntent?.tone == .warning)
        fixture.controller.stopWorkspaceObservation()
    }

    @Test("The Open Anyway countdown pauses while displays sleep")
    func softOpenCountdownPauses() async {
        let fixture = makeFixture()
        _ = fixture.controller.start(timerConfiguration())
        await drainTasks()
        fixture.controller.handleWorkspaceEvent(.activated(selectedApplication))
        await drainTasks()

        fixture.elapsedClock.advance(by: .seconds(2))
        await drainTasks()
        #expect(
            fixture.overlays.lastIntent?.secondaryActionStatus
                == "Open Anyway is available in 6 seconds."
        )

        fixture.controller.handleWorkspaceEvent(.screensDidSleep)
        fixture.elapsedClock.advance(by: .seconds(20))
        await drainTasks()
        #expect(
            fixture.overlays.lastIntent?.secondaryActionStatus
                == "Open Anyway is available in 6 seconds."
        )

        fixture.controller.handleWorkspaceEvent(.screensDidWake)
        await drainTasks()
        fixture.elapsedClock.advance(by: .seconds(1))
        await drainTasks()
        #expect(
            fixture.overlays.lastIntent?.secondaryActionStatus
                == "Open Anyway is available in 5 seconds."
        )
        fixture.controller.stopWorkspaceObservation()
    }

    @Test("Attune becoming active for its panel does not replace the return target")
    func selfActivationDoesNotReplaceRuntimeFallback() async {
        let fixture = makeFixture(selfBundleIdentifier: "test.attune.self")
        _ = fixture.controller.start(timerConfiguration())
        await drainTasks()

        fixture.controller.handleWorkspaceEvent(.activated(AppIdentity(
            bundleIdentifier: "test.editor",
            displayName: "Editor"
        )))
        fixture.controller.handleWorkspaceEvent(.activated(selectedApplication))
        fixture.controller.handleWorkspaceEvent(.activated(AppIdentity(
            bundleIdentifier: "test.attune.self",
            displayName: "Attune"
        )))
        await drainTasks()
        fixture.overlays.perform(.primary)
        await drainTasks()

        #expect(fixture.applications.activationBundleIdentifiers == ["test.editor"])
        fixture.controller.stopWorkspaceObservation()
    }

    @Test("Periodic snapshots clamp remaining time through rollback and deadline completes once")
    func snapshotsRollbackAndDeadline() async {
        let fixture = makeFixture()
        _ = fixture.controller.start(timerConfiguration())
        _ = await fixture.controller.waitForPendingPersistence()
        await fixture.repository.clearOperations()
        await drainTasks()

        fixture.wallClock.advance(by: 15)
        fixture.elapsedClock.advance(by: .seconds(15))
        await drainTasks()
        _ = await fixture.controller.waitForPendingPersistence()
        #expect(fixture.controller.remainingSeconds == 285)
        #expect(await fixture.repository.stateSaveCount == 1)

        fixture.wallClock.advance(by: -60)
        fixture.controller.handleWorkspaceEvent(.systemClockChanged)
        #expect(fixture.controller.remainingSeconds == 285)

        fixture.wallClock.setNow(startTime.addingTimeInterval(300))
        fixture.controller.handleWorkspaceEvent(.systemClockChanged)
        await drainTasks()
        _ = await fixture.controller.waitForPendingPersistence()

        #expect(fixture.controller.completedSummary?.outcome == .timedComplete)
        #expect(fixture.completionReminders.lastIntent == CompletionReminderIntent(
            sessionID: sessionID,
            title: "Focus complete",
            message: "Write the release note"
        ))
        #expect(await fixture.repository.terminalCommitCount == 1)
        fixture.controller.handleWorkspaceEvent(.systemClockChanged)
        #expect(await fixture.repository.terminalCommitCount == 1)
        fixture.controller.stopWorkspaceObservation()
    }

    @Test("Soft goal review requires three active monotonic seconds and pauses while asleep")
    func goalReviewGatePauses() async {
        let fixture = makeFixture()
        _ = fixture.controller.start(goalConfiguration())
        await drainTasks()
        fixture.controller.requestGoalReview()
        await drainTasks()

        fixture.elapsedClock.advance(by: .seconds(2))
        await drainTasks()
        fixture.controller.handleWorkspaceEvent(.screensDidSleep)
        fixture.elapsedClock.advance(by: .seconds(20))
        await drainTasks()
        #expect(fixture.controller.goalReview?.isPaused == true)
        #expect(fixture.controller.goalReview?.isUnlocked == false)

        fixture.controller.handleWorkspaceEvent(.screensDidWake)
        await drainTasks()
        fixture.elapsedClock.advance(by: .seconds(1))
        await drainTasks()
        #expect(fixture.controller.goalReview?.isUnlocked == true)

        fixture.controller.confirmGoalCompletion()
        #expect(fixture.controller.completedSummary?.outcome == .goalComplete)
        #expect(fixture.completionReminders.lastIntent?.title == "Goal complete")
        #expect(
            fixture.completionReminders.lastIntent?.message
                == "Write the release note"
        )
        fixture.controller.stopWorkspaceObservation()
    }

    @Test("Soft stop requires ten seconds, a fixed reason, and one confirmation")
    func stopChallengeGateAndReason() async {
        let fixture = makeFixture()
        _ = fixture.controller.start(timerConfiguration())
        await drainTasks()
        fixture.controller.requestStop()
        fixture.controller.selectStopReason(.taskOrPlanChanged)
        await drainTasks()

        fixture.elapsedClock.advance(by: .seconds(9))
        await drainTasks()
        fixture.controller.confirmStop()
        #expect(fixture.controller.completedSummary == nil)
        #expect(fixture.controller.stopCooldownRemainingSeconds == 1)

        fixture.elapsedClock.advance(by: .seconds(1))
        await drainTasks()
        #expect(fixture.controller.stopChallenge?.isUnlocked == true)
        fixture.controller.confirmStop()
        #expect(fixture.controller.completedSummary?.outcome == .endedEarly)
        #expect(fixture.controller.completedSummary?.earlyStopReason == .taskOrPlanChanged)
        #expect(fixture.completionReminders.lastIntent == nil)
        fixture.controller.stopWorkspaceObservation()
    }

    @Test("Loaded activity becomes interrupted before observation and resumes from its snapshot")
    func interruptionLoadAndResume() async {
        let snapshot = RunningSession(
            id: sessionID,
            configuration: timerConfiguration(),
            startedAt: startTime.addingTimeInterval(-600),
            deadline: startTime.addingTimeInterval(-300),
            lastKnownRemainingSeconds: 120,
            mediumConsumedSeconds: 37,
            wasInterrupted: false,
            status: .running,
            metrics: SessionMetrics(interventionCount: 4)
        )
        let fixture = makeFixture(initialSession: snapshot)

        await fixture.controller.initialize()

        #expect(fixture.controller.activeSession?.status == .interrupted)
        #expect(fixture.controller.activeSession?.wasInterrupted == true)
        #expect(fixture.controller.interruptionState == .awaitingDecision(sessionID: sessionID))
        #expect(fixture.controller.isWorkspaceObservationActive == false)

        fixture.controller.resumeInterruptedSession()
        #expect(fixture.controller.activeSession?.status == .running)
        #expect(fixture.controller.activeSession?.deadline == startTime.addingTimeInterval(120))
        #expect(fixture.controller.activeSession?.mediumConsumedSeconds == 37)
        #expect(fixture.controller.activeSession?.metrics.interventionCount == 4)
        #expect(fixture.controller.isWorkspaceObservationActive)
        fixture.controller.stopWorkspaceObservation()
    }

    @Test("A zero remaining recovery records interrupted, never timed complete")
    func expiredInterruption() async {
        let snapshot = RunningSession(
            id: sessionID,
            configuration: timerConfiguration(),
            startedAt: startTime.addingTimeInterval(-300),
            deadline: startTime,
            lastKnownRemainingSeconds: 0,
            mediumConsumedSeconds: 0,
            wasInterrupted: false,
            status: .running,
            metrics: SessionMetrics()
        )
        let fixture = makeFixture(initialSession: snapshot)

        await fixture.controller.initialize()
        _ = await fixture.controller.waitForPendingPersistence()

        #expect(fixture.controller.completedSummary?.outcome == .interrupted)
        #expect(fixture.controller.completedSummary?.wasInterrupted == true)
        #expect(await fixture.repository.terminalCommitCount == 1)
        fixture.controller.stopWorkspaceObservation()
    }

    @Test("A resumed session carries interruption into its terminal summary")
    func resumedSessionRetainsInterruptionMarker() async {
        let snapshot = RunningSession(
            id: sessionID,
            configuration: timerConfiguration(),
            startedAt: startTime.addingTimeInterval(-600),
            deadline: startTime.addingTimeInterval(-300),
            lastKnownRemainingSeconds: 5,
            mediumConsumedSeconds: 0,
            wasInterrupted: false,
            status: .running,
            metrics: SessionMetrics()
        )
        let fixture = makeFixture(initialSession: snapshot)

        await fixture.controller.initialize()
        fixture.controller.resumeInterruptedSession()
        fixture.wallClock.advance(by: 5)
        fixture.controller.handleWorkspaceEvent(.systemClockChanged)
        _ = await fixture.controller.waitForPendingPersistence()

        #expect(fixture.controller.completedSummary?.outcome == .timedComplete)
        #expect(fixture.controller.completedSummary?.wasInterrupted == true)
        #expect(await fixture.repository.terminalCommitCount == 1)
        fixture.controller.stopWorkspaceObservation()
    }

    @Test("A blocked repository never delays a selected-app warning")
    func blockedPersistenceDoesNotDelayIntervention() async {
        let recorder = LockedEventRecorder()
        let fixture = makeFixture(recorder: recorder)
        await fixture.repository.setBlocksStateSaves(true)
        _ = fixture.controller.start(timerConfiguration())
        await waitUntil { recorder.snapshot().contains("persist:state-started") }

        fixture.controller.handleWorkspaceEvent(.activated(selectedApplication))
        await drainTasks()

        #expect(fixture.applications.hiddenBundleIdentifiers.isEmpty)
        #expect(fixture.overlays.lastIntent?.primaryActionTitle == "Return to Focus")
        await fixture.repository.releaseStateSaves()
        _ = await fixture.controller.waitForPendingPersistence()
        fixture.controller.stopWorkspaceObservation()
    }

    @Test("Repository failure is user-visible and can be retried")
    func persistenceFailureAndRetry() async {
        let fixture = makeFixture()
        await fixture.repository.setFailsStateSaves(true)
        _ = fixture.controller.start(timerConfiguration())
        _ = await fixture.controller.waitForPendingPersistence()

        guard case let .failed(failure) = fixture.controller.persistenceStatus else {
            Issue.record("Expected a visible persistence failure")
            return
        }
        #expect(failure.operation == .activeSession)
        #expect(fixture.controller.persistenceStatus.userMessage != nil)

        await fixture.repository.setFailsStateSaves(false)
        fixture.controller.retryPersistence()
        _ = await fixture.controller.waitForPendingPersistence()
        #expect(fixture.controller.persistenceStatus == .saved)
        fixture.controller.stopWorkspaceObservation()
    }

    @Test("Completion review updates satisfaction before returning to idle")
    func completionReviewLifecycle() async {
        let fixture = makeFixture()
        _ = fixture.controller.start(timerConfiguration())
        fixture.wallClock.advance(by: 300)
        fixture.controller.handleWorkspaceEvent(.systemClockChanged)
        _ = await fixture.controller.waitForPendingPersistence()

        #expect(fixture.controller.recordSatisfaction(4))
        _ = await fixture.controller.waitForPendingPersistence()
        #expect(fixture.controller.completedSummary?.satisfaction == 4)
        #expect(await fixture.repository.terminalCommitCount == 2)

        #expect(fixture.controller.acknowledgeCompletion())
        #expect(fixture.controller.completedSummary == nil)
        #expect(fixture.controller.canStartSession)
        #expect(fixture.completionReminders.lastIntent == nil)
        fixture.controller.stopWorkspaceObservation()
    }

    @Test("A failed terminal commit blocks replacement until retry succeeds")
    func terminalPersistenceIsAReplacementBarrier() async {
        let fixture = makeFixture()
        _ = fixture.controller.start(timerConfiguration())
        _ = await fixture.controller.waitForPendingPersistence()
        await fixture.repository.setFailsTerminalCommits(true)

        fixture.controller.requestStop()
        fixture.controller.selectStopReason(.urgentNeed)
        await drainTasks()
        fixture.elapsedClock.advance(by: .seconds(10))
        await drainTasks()
        fixture.controller.confirmStop()
        _ = await fixture.controller.waitForPendingPersistence()

        #expect(fixture.controller.terminalPersistenceStatus == .failed(sessionID: sessionID))
        #expect(fixture.controller.canStartSession == false)
        #expect(fixture.controller.start(timerConfiguration()) == nil)

        await fixture.repository.setFailsTerminalCommits(false)
        fixture.controller.retryPersistence()
        _ = await fixture.controller.waitForPendingPersistence()
        #expect(fixture.controller.terminalPersistenceStatus == .committed(sessionID: sessionID))
        #expect(fixture.controller.canStartSession)
        fixture.controller.stopWorkspaceObservation()
    }

    @Test("Medium hides before consent and meters only after Use Allowance")
    func mediumConsentAndMetering() async {
        let fixture = makeFixture()
        _ = fixture.controller.start(timerConfiguration(
            mode: .medium(allowanceSeconds: 60)
        ))
        await drainTasks()

        fixture.controller.handleWorkspaceEvent(.activated(selectedApplication))
        await drainTasks()
        #expect(fixture.applications.hiddenBundleIdentifiers.contains("test.distraction"))
        #expect(fixture.controller.activeSession?.mediumConsumedSeconds == 0)
        #expect(fixture.overlays.lastIntent?.primaryActionTitle == "Return to Focus")

        fixture.elapsedClock.advance(by: .seconds(5))
        await drainTasks()
        #expect(fixture.controller.mediumUseAvailable)
        fixture.overlays.perform(.secondary)
        await drainTasks()
        #expect(fixture.applications.activationBundleIdentifiers.contains("test.distraction"))

        fixture.elapsedClock.advance(by: .seconds(1))
        await drainTasks()
        #expect(fixture.controller.activeSession?.mediumConsumedSeconds == 1)
        #expect(fixture.controller.mediumAllowanceRemainingSeconds == 59)
        fixture.controller.stopWorkspaceObservation()
    }

    @Test("Medium allowance countdown redraws after switching away")
    func mediumCountdownUpdatesAfterWindowSwitch() async {
        let fixture = makeFixture()
        let editor = AppIdentity(
            bundleIdentifier: "test.editor",
            displayName: "Editor"
        )
        _ = fixture.controller.start(timerConfiguration(
            mode: .medium(allowanceSeconds: 60)
        ))
        await drainTasks()

        fixture.controller.handleWorkspaceEvent(.activated(selectedApplication))
        await drainTasks()
        #expect(
            fixture.overlays.lastIntent?.secondaryActionStatus
                == "Use Allowance is available in 5 seconds."
        )

        fixture.controller.handleWorkspaceEvent(.activated(editor))
        fixture.elapsedClock.advance(by: .seconds(1))
        await drainTasks()

        #expect(
            fixture.overlays.lastIntent?.secondaryActionStatus
                == "Use Allowance is available in 4 seconds."
        )
        #expect(fixture.controller.mediumUseAvailable == false)
        fixture.controller.stopWorkspaceObservation()
    }

    @Test("Strict hides, refocuses, and requests only normal termination")
    func strictEnforcementPath() async {
        let fixture = makeFixture()
        _ = fixture.controller.start(timerConfiguration(mode: .strict))
        await drainTasks()
        fixture.applications.hiddenBundleIdentifiers.removeAll()
        fixture.applications.activationBundleIdentifiers.removeAll()
        fixture.applications.normalTerminationBundleIdentifiers.removeAll()

        fixture.controller.handleWorkspaceEvent(.activated(selectedApplication))
        await drainTasks()

        #expect(fixture.applications.hiddenBundleIdentifiers == ["test.distraction"])
        #expect(fixture.applications.activationBundleIdentifiers == ["com.apple.finder"])
        #expect(fixture.applications.normalTerminationBundleIdentifiers == ["test.distraction"])
        #expect(fixture.controller.activeSession?.metrics.interventionCount == 1)
        fixture.controller.stopWorkspaceObservation()
    }

    @Test("Strict moves focus away before observing the selected app hide")
    func strictRefocusesBeforeHideObservation() async {
        let recorder = LockedEventRecorder()
        let fixture = makeFixture(recorder: recorder)
        _ = fixture.controller.start(timerConfiguration(mode: .strict))
        await drainTasks()
        recorder.clear()

        fixture.controller.handleWorkspaceEvent(.activated(selectedApplication))
        await drainTasks()

        #expect(Array(recorder.snapshot().prefix(2)) == [
            "activate:com.apple.finder",
            "hide:test.distraction"
        ])
        fixture.controller.stopWorkspaceObservation()
    }

    @Test("Strict reconciliation does not steal focus from Attune")
    func strictReconciliationPreservesForegroundApp() async {
        let fixture = makeFixture()

        _ = fixture.controller.start(timerConfiguration(mode: .strict))
        await drainTasks()

        #expect(
            fixture.applications.hiddenBundleIdentifiers
                == [selectedApplication.bundleIdentifier]
        )
        #expect(fixture.applications.activationBundleIdentifiers.isEmpty)
        fixture.controller.stopWorkspaceObservation()
    }

    @Test("Strict reconciliation refocuses after catching an active selected app")
    func strictReconciliationRefocusesActiveSelectedApp() async {
        let fixture = makeFixture()
        fixture.applications.hideWasActiveBeforeHide = true

        _ = fixture.controller.start(timerConfiguration(mode: .strict))
        await drainTasks()

        #expect(
            fixture.applications.activationBundleIdentifiers
                == ["com.apple.finder"]
        )
        fixture.controller.stopWorkspaceObservation()
    }

    @Test("Strict Return dismisses a hide failure without presenting a retry loop")
    func strictFailureReturnDismissesOnce() async {
        let fixture = makeFixture()
        fixture.applications.hideSummary = .failed
        _ = fixture.controller.start(timerConfiguration(mode: .strict))
        await drainTasks()

        fixture.controller.handleWorkspaceEvent(.activated(selectedApplication))
        await drainTasks()

        #expect(fixture.overlays.lastIntent?.primaryActionTitle == "Return to Focus")
        #expect(fixture.overlays.lastIntent?.secondaryActionTitle == nil)
        #expect(fixture.overlays.lastIntent?.tertiaryActionTitle == nil)
        let hideCountBeforeReturn = fixture.applications.hiddenBundleIdentifiers.count
        let presentationCountBeforeReturn = fixture.overlays.presentCount
        let dismissCountBeforeReturn = fixture.overlays.dismissCount
        fixture.overlays.perform(.primary)
        await drainTasks()
        #expect(fixture.overlays.dismissCount == dismissCountBeforeReturn + 1)
        #expect(fixture.overlays.presentCount == presentationCountBeforeReturn)
        #expect(
            fixture.applications.hiddenBundleIdentifiers.count == hideCountBeforeReturn
        )
        fixture.controller.stopWorkspaceObservation()
    }

    @Test("Successful Strict status remains until Return to Focus")
    func strictStatusRequiresUserAction() async {
        let fixture = makeFixture()
        _ = fixture.controller.start(timerConfiguration(mode: .strict))
        await drainTasks()

        fixture.controller.handleWorkspaceEvent(.activated(selectedApplication))
        await drainTasks()
        let presentationCount = fixture.overlays.presentCount
        let dismissCount = fixture.overlays.dismissCount

        try? await Task.sleep(for: .milliseconds(3_200))

        #expect(fixture.overlays.presentCount == presentationCount)
        #expect(fixture.overlays.dismissCount == dismissCount)
        fixture.overlays.perform(.primary)
        #expect(fixture.overlays.dismissCount == dismissCount + 1)
        fixture.controller.stopWorkspaceObservation()
    }

    @Test("Medium re-hides an immediate banned-app return from End Focus")
    func mediumRehidesReturnFromEndFocus() async {
        let fixture = makeFixture()
        _ = fixture.controller.start(timerConfiguration(
            mode: .medium(allowanceSeconds: 60)
        ))
        await drainTasks()
        let editor = AppIdentity(
            bundleIdentifier: "test.editor",
            displayName: "Editor"
        )
        fixture.applications.hiddenBundleIdentifiers.removeAll()
        fixture.applications.activationBundleIdentifiers.removeAll()
        fixture.applications.normalTerminationBundleIdentifiers.removeAll()

        fixture.controller.handleWorkspaceEvent(.activated(editor))
        fixture.controller.handleWorkspaceEvent(.activated(selectedApplication))
        await drainTasks()
        let originalIntervention = fixture.controller.runtime.intervention
        fixture.controller.handleWorkspaceEvent(
            .deactivated(bundleIdentifier: selectedApplication.bundleIdentifier)
        )
        fixture.controller.requestStop()
        fixture.controller.handleWorkspaceEvent(.activated(selectedApplication))
        await drainTasks()

        #expect(fixture.controller.stopChallenge != nil)
        #expect(
            fixture.applications.hiddenBundleIdentifiers
                == ["test.distraction", "test.distraction"]
        )
        #expect(fixture.overlays.presentCount == 2)
        #expect(fixture.controller.runtime.intervention == originalIntervention)
        #expect(fixture.controller.activeSession?.metrics.interventionCount == 1)
        fixture.controller.stopWorkspaceObservation()
    }

    private func makeFixture(
        initialSession: RunningSession? = nil,
        recorder: LockedEventRecorder = LockedEventRecorder(),
        selfBundleIdentifier: String? = "test.attune.self"
    ) -> ControllerFixture {
        let wallClock = TestWallClock(now: startTime)
        let elapsedClock = TestElapsedClock()
        let workspace = FakeWorkspaceClient()
        let applications = FakeApplicationController(recorder: recorder)
        let overlays = FakeOverlayPresenter(recorder: recorder)
        let completionReminders = FakeCompletionReminderPresenter(recorder: recorder)
        let repository = FakeStateRepository(
            state: AppStateDocument(activeSession: initialSession),
            recorder: recorder
        )
        let controller = SessionController(
            wallClock: wallClock,
            elapsedClock: elapsedClock,
            workspaceClient: workspace,
            applicationController: applications,
            overlayPresenter: overlays,
            completionReminderPresenter: completionReminders,
            repository: repository,
            makeSessionID: { sessionID },
            selfBundleIdentifier: selfBundleIdentifier
        )
        return ControllerFixture(
            controller: controller,
            wallClock: wallClock,
            elapsedClock: elapsedClock,
            workspace: workspace,
            applications: applications,
            overlays: overlays,
            completionReminders: completionReminders,
            repository: repository
        )
    }

    private func timerConfiguration(
        selectedApps: [AppIdentity]? = nil,
        mode: FocusMode = .soft
    ) -> FocusConfiguration {
        FocusConfiguration(
            intention: "Write the release note",
            selectedApps: selectedApps ?? [selectedApplication],
            mode: mode,
            completion: .timer(durationSeconds: 300)
        )
    }

    private func goalConfiguration() -> FocusConfiguration {
        FocusConfiguration(
            intention: "Write the release note",
            selectedApps: [selectedApplication],
            mode: .soft,
            completion: .goal(
                definitionOfDone: "A reviewed draft exists",
                safetyDurationSeconds: 900
            )
        )
    }

    private func drainTasks() async {
        for _ in 0..<20 {
            await Task.yield()
        }
    }

    private func waitUntil(
        _ condition: () -> Bool
    ) async {
        for _ in 0..<100 where !condition() {
            await Task.yield()
        }
    }
}

@MainActor
private struct ControllerFixture {
    let controller: SessionController
    let wallClock: TestWallClock
    let elapsedClock: TestElapsedClock
    let workspace: FakeWorkspaceClient
    let applications: FakeApplicationController
    let overlays: FakeOverlayPresenter
    let completionReminders: FakeCompletionReminderPresenter
    let repository: FakeStateRepository
}

private final class LockedEventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [String] = []

    func append(_ event: String) {
        lock.withLock { events.append(event) }
    }

    func snapshot() -> [String] {
        lock.withLock { events }
    }

    func clear() {
        lock.withLock { events.removeAll() }
    }
}

private final class FakeWorkspaceClient: WorkspaceClient, @unchecked Sendable {
    private let lock = NSLock()
    private let stream: AsyncStream<WorkspaceEvent>
    private let continuation: AsyncStream<WorkspaceEvent>.Continuation
    private var frontmost: AppIdentity?
    private var running: [AppIdentity] = []

    init() {
        let pair = AsyncStream<WorkspaceEvent>.makeStream()
        stream = pair.stream
        continuation = pair.continuation
    }

    func events() -> AsyncStream<WorkspaceEvent> {
        stream
    }

    func runningApplications() async -> [AppIdentity] {
        lock.withLock { running }
    }

    func frontmostApplication() async -> AppIdentity? {
        lock.withLock { frontmost }
    }

    func emit(_ event: WorkspaceEvent) {
        continuation.yield(event)
    }

    func setFrontmost(_ application: AppIdentity?) {
        lock.withLock { frontmost = application }
    }
}

@MainActor
private final class FakeApplicationController: ApplicationController {
    let recorder: LockedEventRecorder
    var hiddenBundleIdentifiers: [String] = []
    var activationBundleIdentifiers: [String] = []
    var normalTerminationBundleIdentifiers: [String] = []
    var activationSummary: ApplicationCommandSummary = .succeeded
    var hideSummary: ApplicationCommandSummary = .succeeded
    var hideWasActiveBeforeHide = false

    init(recorder: LockedEventRecorder) {
        self.recorder = recorder
    }

    func hide(bundleIdentifier: String) async -> HideResult {
        hiddenBundleIdentifiers.append(bundleIdentifier)
        recorder.append("hide:\(bundleIdentifier)")
        return HideResult(
            bundleIdentifier: bundleIdentifier,
            summary: hideSummary,
            processes: [],
            wasActiveBeforeHide: hideWasActiveBeforeHide
        )
    }

    func activate(bundleIdentifier: String) -> ActivationResult {
        activationBundleIdentifiers.append(bundleIdentifier)
        recorder.append("activate:\(bundleIdentifier)")
        return ActivationResult(
            bundleIdentifier: bundleIdentifier,
            summary: activationSummary,
            processes: []
        )
    }

    func activateRecoveryTarget(bundleIdentifier: String) -> ActivationResult {
        activate(bundleIdentifier: bundleIdentifier)
    }

    func requestNormalTermination(
        bundleIdentifier: String,
        excludingProcessIdentifiers: Set<Int32>
    ) async -> NormalTerminationResult {
        normalTerminationBundleIdentifiers.append(bundleIdentifier)
        return NormalTerminationResult(
            bundleIdentifier: bundleIdentifier,
            summary: .noNewProcesses,
            processes: []
        )
    }
}

@MainActor
private final class FakeOverlayPresenter: OverlayPresenting {
    let recorder: LockedEventRecorder
    var lastIntent: OverlayIntent?
    var dismissCount = 0
    var presentCount = 0
    private var handler: OverlayActionHandler?

    init(recorder: LockedEventRecorder) {
        self.recorder = recorder
    }

    func present(
        _ intent: OverlayIntent,
        onAction: @escaping OverlayActionHandler
    ) {
        lastIntent = intent
        handler = onAction
        presentCount += 1
        recorder.append("panel:\(intent.primaryActionTitle)")
    }

    func dismiss() {
        dismissCount += 1
        handler = nil
        recorder.append("panel:dismiss")
    }

    func perform(_ action: OverlayAction) {
        if action == .secondary, lastIntent?.isSecondaryActionEnabled != true {
            return
        }
        let handler = handler
        self.handler = nil
        handler?(action)
    }
}

@MainActor
private final class FakeCompletionReminderPresenter: CompletionReminderPresenting {
    let recorder: LockedEventRecorder
    var lastIntent: CompletionReminderIntent?
    var presentCount = 0
    var dismissCount = 0

    init(recorder: LockedEventRecorder) {
        self.recorder = recorder
    }

    func present(_ intent: CompletionReminderIntent) {
        lastIntent = intent
        presentCount += 1
        recorder.append("completion:\(intent.title)")
    }

    func dismiss() {
        lastIntent = nil
        dismissCount += 1
        recorder.append("completion:dismiss")
    }
}

private actor FakeStateRepository: StateRepository {
    enum FakeError: Error {
        case writeFailed
    }

    private var state: AppStateDocument
    private var history = HistoryDocument.initial
    private let recorder: LockedEventRecorder
    private var stateSaves: [AppStateDocument] = []
    private var terminalCommits: [SessionSummary] = []
    private var blocksStateSaves = false
    private var failsStateSaves = false
    private var failsTerminalCommits = false
    private var stateSaveWaiters: [CheckedContinuation<Void, Never>] = []

    init(state: AppStateDocument, recorder: LockedEventRecorder) {
        self.state = state
        self.recorder = recorder
    }

    var stateSaveCount: Int {
        stateSaves.count
    }

    var terminalCommitCount: Int {
        terminalCommits.count
    }

    func loadState() async throws -> AppStateDocument {
        state
    }

    func saveState(_ document: AppStateDocument) async throws {
        recorder.append("persist:state-started")
        if blocksStateSaves {
            await withCheckedContinuation { continuation in
                stateSaveWaiters.append(continuation)
            }
        }
        if failsStateSaves {
            throw FakeError.writeFailed
        }
        state = document
        stateSaves.append(document)
        recorder.append("persist:state")
    }

    func loadHistory() async throws -> HistoryDocument {
        history
    }

    func saveHistory(_ document: HistoryDocument) async throws {
        history = document
    }

    func commitTerminal(_ summary: SessionSummary, clearing sessionID: UUID) async throws {
        if failsTerminalCommits {
            throw FakeError.writeFailed
        }
        history.upsert(summary)
        if state.activeSession?.id == sessionID {
            state.activeSession = nil
        }
        terminalCommits.append(summary)
        recorder.append("persist:terminal")
    }

    func setBlocksStateSaves(_ blocks: Bool) {
        blocksStateSaves = blocks
    }

    func releaseStateSaves() {
        blocksStateSaves = false
        let waiters = stateSaveWaiters
        stateSaveWaiters = []
        waiters.forEach { $0.resume() }
    }

    func setFailsStateSaves(_ fails: Bool) {
        failsStateSaves = fails
    }

    func setFailsTerminalCommits(_ fails: Bool) {
        failsTerminalCommits = fails
    }

    func clearOperations() {
        stateSaves = []
        terminalCommits = []
    }
}
