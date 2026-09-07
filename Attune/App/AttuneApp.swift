import AppKit
import SwiftUI

@main
@MainActor
struct AttuneApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private let environment: AppEnvironment
    private let model: AppModel

    init() {
        let environment = AppEnvironment()
        let model = AppModel()
        self.environment = environment
        self.model = model
        appDelegate.configure(environment: environment, model: model)
    }

    var body: some Scene {
        MenuBarExtra("Attune", systemImage: "scope") {
            if let session = environment.sessionController.activeSession {
                switch session.configuration.completion {
                case .timer:
                    Text("\(menuTimeText) remaining")
                case .goal:
                    Text("Goal active · \(menuTimeText) safety window")
                    Button("Mark Goal Complete") {
                        environment.sessionController.requestGoalReview()
                        appDelegate.openMainWindow()
                    }
                }
                if let allowance = environment.sessionController.mediumAllowanceRemainingSeconds {
                    Text("\(durationText(allowance)) shared allowance")
                }

                Divider()

                Button("Open Attune") {
                    appDelegate.openMainWindow()
                }
                .keyboardShortcut("o")

                Button("End Focus…") {
                    environment.sessionController.requestStop()
                    appDelegate.openMainWindow()
                }
            } else if environment.sessionController.completedSummary != nil {
                Text("Focus review ready")

                Button("Open Attune") {
                    appDelegate.openMainWindow()
                }
                .keyboardShortcut("o")
            } else {
                Button("New Focus") {
                    beginNewFocus()
                }

                Button("Open Attune") {
                    appDelegate.openMainWindow()
                }
                .keyboardShortcut("o")
            }

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .menuBarExtraStyle(.menu)
    }

    private var menuTimeText: String {
        let totalSeconds = max(
            0,
            environment.sessionController.remainingSeconds ?? 0
        )
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let secondPart = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secondPart)
        }
        return String(format: "%02d:%02d", minutes, secondPart)
    }

    private func durationText(_ totalSeconds: Int) -> String {
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func beginNewFocus() {
        appDelegate.openMainWindow()
        Task { @MainActor in
            await environment.sessionController.initialize()
            guard environment.sessionController.preferences.hasCompletedOnboarding,
                  environment.sessionController.activeSession == nil else {
                return
            }
            model.beginFocusSetup(
                using: environment.sessionController.preferences.focusDefaults
            )
        }
    }
}
