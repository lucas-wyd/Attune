import AppKit
import SwiftUI

@main
struct AttuneFixtureApp: App {
    @NSApplicationDelegateAdaptor(FixtureAppDelegate.self) private var appDelegate

    private let behavior = FixtureBehavior.current()

    var body: some Scene {
        WindowGroup("Attune Fixture") {
            FixtureView(behavior: behavior)
        }
    }
}

@MainActor
final class FixtureAppDelegate: NSObject, NSApplicationDelegate {
    private let behavior = FixtureBehavior.current()

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        switch behavior {
        case .normal, .resistHiding:
            return .terminateNow
        case .refuseQuit:
            return .terminateCancel
        case .delayedQuit:
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                sender.reply(toApplicationShouldTerminate: true)
            }
            return .terminateLater
        }
    }

    func applicationWillHide(_ notification: Notification) {
        guard behavior == .resistHiding else {
            return
        }

        Task { @MainActor in
            await Task.yield()
            NSApplication.shared.unhide(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }
}
