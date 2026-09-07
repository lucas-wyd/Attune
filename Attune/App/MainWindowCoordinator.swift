import AppKit
import SwiftUI

@MainActor
final class MainWindowCoordinator: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func open(model: AppModel, environment: AppEnvironment) {
        let window = window ?? makeWindow(model: model, environment: environment)
        self.window = window

        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow,
              closingWindow === window else {
            return
        }

        window = nil
    }

    private func makeWindow(model: AppModel, environment: AppEnvironment) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Attune"
        window.minSize = NSSize(width: 760, height: 620)
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentViewController = NSHostingController(
            rootView: DashboardView(model: model, environment: environment)
        )
        return window
    }
}
