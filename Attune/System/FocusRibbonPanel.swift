import AppKit
import SwiftUI

final class FocusRibbonPanel: NSPanel {
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
        becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }

    func updateContent(_ view: FocusOverlayView) {
        if let hostingController = contentViewController
            as? NSHostingController<FocusOverlayView> {
            hostingController.rootView = view
        } else {
            contentViewController = NSHostingController(rootView: view)
        }
    }
}
