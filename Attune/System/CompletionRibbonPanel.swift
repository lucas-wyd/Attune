import AppKit
import SwiftUI

final class CompletionRibbonPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .screenSaver
        isFloatingPanel = true
        collectionBehavior = [
            .canJoinAllApplications,
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle,
        ]
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        animationBehavior = .none
        ignoresMouseEvents = true
    }

    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
    }

    func updateContent(_ view: CompletionRibbonView) {
        if let hostingController = contentViewController
            as? NSHostingController<CompletionRibbonView> {
            hostingController.rootView = view
        } else {
            contentViewController = NSHostingController(rootView: view)
        }
    }
}
