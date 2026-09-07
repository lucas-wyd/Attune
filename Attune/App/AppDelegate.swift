import AppKit
import Observation

enum QuitTerminalPersistenceState: Equatable, Sendable {
    case awaitingCommit
    case committing
    case committed
    case failed
}

enum QuitSessionSnapshot: Equatable, Sendable {
    case idle
    case active(sessionID: UUID, hasStopChallenge: Bool)
    case terminal(sessionID: UUID, persistence: QuitTerminalPersistenceState)
}

/// Owns the single outstanding AppKit termination reply while a focus outcome is made durable.
///
/// Keeping this state separate from `AppDelegate` makes the exact-once reply contract explicit:
/// retrying persistence changes only the snapshot, while cancelling or committing consumes the
/// pending reply token.
@MainActor
final class QuitPersistenceBarrier {
    private struct PendingQuit {
        let sessionID: UUID
        let reply: @MainActor (Bool) -> Void
    }

    private var pendingQuit: PendingQuit?

    var pendingSessionID: UUID? {
        pendingQuit?.sessionID
    }

    func requestOrdinaryQuit(
        snapshot: QuitSessionSnapshot,
        beginStop: () -> Void,
        openFlow: () -> Void,
        reply: @escaping @MainActor (Bool) -> Void
    ) -> NSApplication.TerminateReply {
        guard pendingQuit == nil else {
            return .terminateLater
        }

        switch snapshot {
        case .idle:
            return .terminateNow

        case let .active(sessionID, _):
            pendingQuit = PendingQuit(sessionID: sessionID, reply: reply)
            beginStop()
            openFlow()
            return .terminateLater

        case let .terminal(sessionID, persistence):
            guard persistence != .committed else {
                return .terminateNow
            }
            pendingQuit = PendingQuit(sessionID: sessionID, reply: reply)
            openFlow()
            return .terminateLater
        }
    }

    func update(_ snapshot: QuitSessionSnapshot) {
        guard let pendingQuit else {
            return
        }

        switch snapshot {
        case .idle:
            resolve(shouldTerminate: false)

        case let .active(sessionID, hasStopChallenge):
            guard sessionID == pendingQuit.sessionID else {
                resolve(shouldTerminate: false)
                return
            }
            if !hasStopChallenge {
                resolve(shouldTerminate: false)
            }

        case let .terminal(sessionID, persistence):
            guard sessionID == pendingQuit.sessionID else {
                resolve(shouldTerminate: false)
                return
            }
            if persistence == .committed {
                resolve(shouldTerminate: true)
            }
        }
    }

    func cancel() {
        resolve(shouldTerminate: false)
    }

    func allowSystemTermination() {
        resolve(shouldTerminate: true)
    }

    private func resolve(shouldTerminate: Bool) {
        guard let pendingQuit else {
            return
        }
        self.pendingQuit = nil
        pendingQuit.reply(shouldTerminate)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var environment: AppEnvironment?
    private var model: AppModel?
    private weak var sessionController: SessionController?
    private let quitBarrier = QuitPersistenceBarrier()
    private var quitObservationGeneration: UInt64 = 0
    private var isSystemTerminationInProgress = false

    func configure(environment: AppEnvironment, model: AppModel) {
        self.environment = environment
        self.model = model
        sessionController = environment.sessionController
        model.configureQuitCancellation { [weak self] in
            self?.cancelPendingQuit()
        }
    }

    func configureQuitHandling(sessionController: SessionController) {
        self.sessionController = sessionController
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(workspaceWillPowerOff(_:)),
            name: NSWorkspace.willPowerOffNotification,
            object: nil
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let shouldOpenWindow = LaunchContext.current() == .userInitiated
            || environment?.debugLaunchConfiguration.adapterLabEnabled == true
        if shouldOpenWindow {
            openMainWindow()
        }

        if let sessionController {
            Task { @MainActor in
                await sessionController.initialize()
            }
        }
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        openMainWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isSystemTerminationInProgress else {
            quitBarrier.allowSystemTermination()
            return .terminateNow
        }

        guard let sessionController else {
            return .terminateNow
        }

        let reply = quitBarrier.requestOrdinaryQuit(
            snapshot: quitSnapshot(for: sessionController),
            beginStop: {
                sessionController.requestStop(intent: .quit)
            },
            openFlow: { [weak self] in
                self?.openMainWindow()
            },
            reply: { shouldTerminate in
                sender.reply(toApplicationShouldTerminate: shouldTerminate)
            }
        )

        if reply == .terminateLater {
            observePendingQuit()
        }
        return reply
    }

    /// Cancels an outstanding ordinary-Quit request from an explicit “Stay Open” action.
    /// “Keep Focusing” is also detected automatically when the shared stop challenge closes.
    func cancelPendingQuit() {
        quitBarrier.cancel()
        invalidateQuitObservation()
    }

    func openMainWindow() {
        guard let environment, let model else {
            assertionFailure("AttuneApp must configure AppDelegate before launch finishes")
            return
        }

        environment.mainWindowCoordinator.open(model: model, environment: environment)
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc
    private func workspaceWillPowerOff(_ notification: Notification) {
        isSystemTerminationInProgress = true
        quitBarrier.allowSystemTermination()
        invalidateQuitObservation()
    }

    private func observePendingQuit() {
        guard quitBarrier.pendingSessionID != nil,
              let sessionController else {
            invalidateQuitObservation()
            return
        }

        quitObservationGeneration &+= 1
        let generation = quitObservationGeneration
        let snapshot = withObservationTracking {
            quitSnapshot(for: sessionController)
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self,
                      self.quitObservationGeneration == generation else {
                    return
                }
                self.observePendingQuit()
            }
        }

        quitBarrier.update(snapshot)
        if quitBarrier.pendingSessionID == nil {
            invalidateQuitObservation()
        }
    }

    private func invalidateQuitObservation() {
        quitObservationGeneration &+= 1
    }

    private func quitSnapshot(for controller: SessionController) -> QuitSessionSnapshot {
        if let session = controller.activeSession {
            return .active(
                sessionID: session.id,
                hasStopChallenge: controller.stopChallenge?.sessionID == session.id
            )
        }

        guard let summary = controller.completedSummary else {
            return .idle
        }

        let persistence: QuitTerminalPersistenceState
        switch controller.terminalPersistenceStatus {
        case let .committing(sessionID) where sessionID == summary.id:
            persistence = .committing
        case let .committed(sessionID) where sessionID == summary.id:
            persistence = .committed
        case let .failed(sessionID) where sessionID == summary.id:
            persistence = .failed
        default:
            persistence = .awaitingCommit
        }
        return .terminal(sessionID: summary.id, persistence: persistence)
    }
}
