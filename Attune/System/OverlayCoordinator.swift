import AppKit
import SwiftUI

@MainActor
final class OverlayCoordinator: NSObject, OverlayPresenting {
    private var panels: [CGDirectDisplayID: FocusRibbonPanel] = [:]
    private var intent: OverlayIntent?
    private var expandedScreenID: CGDirectDisplayID?
    private var actionHandler: OverlayActionHandler?

    var presentedDisplayCount: Int {
        panels.values.count(where: \.isVisible)
    }

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    func present(
        _ intent: OverlayIntent,
        onAction: @escaping OverlayActionHandler
    ) {
        let isNewIntervention = intent.startsNewIntervention(comparedTo: self.intent)
        self.intent = intent
        actionHandler = onAction

        let screens = reconcilePanels()
        if isNewIntervention || !screens.contains(where: {
            $0.descriptor.id == expandedScreenID
        }) {
            expandedScreenID = FocusRibbonLayout.targetScreenID(
                screens: screens.map(\.descriptor),
                pointerLocation: NSEvent.mouseLocation,
                mainScreenID: screenDescriptor(for: NSScreen.main)?.id
            )
        }

        render(
            intent: intent,
            screens: screens,
            animateEntrance: isNewIntervention
        )
    }

    func dismiss() {
        intent = nil
        expandedScreenID = nil
        actionHandler = nil
        panels.values.forEach { $0.orderOut(nil) }
    }

    @objc
    private func screenParametersChanged() {
        let screens = reconcilePanels()
        guard let intent else {
            return
        }

        if !screens.contains(where: { $0.descriptor.id == expandedScreenID }) {
            expandedScreenID = FocusRibbonLayout.targetScreenID(
                screens: screens.map(\.descriptor),
                pointerLocation: NSEvent.mouseLocation,
                mainScreenID: screenDescriptor(for: NSScreen.main)?.id
            )
        }
        render(intent: intent, screens: screens, animateEntrance: false)
    }

    private func reconcilePanels() -> [ScreenPanel] {
        let screens = NSScreen.screens.compactMap { screen -> ScreenPanel? in
            guard let descriptor = screenDescriptor(for: screen) else {
                return nil
            }

            let panel: FocusRibbonPanel
            if let existingPanel = panels[descriptor.id] {
                panel = existingPanel
            } else {
                panel = FocusRibbonPanel()
                panels[descriptor.id] = panel
            }
            return ScreenPanel(descriptor: descriptor, panel: panel)
        }

        let activeScreenIDs = Set(screens.map(\.descriptor.id))
        let disconnectedScreenIDs = panels.keys.filter {
            !activeScreenIDs.contains($0)
        }
        for screenID in disconnectedScreenIDs {
            panels.removeValue(forKey: screenID)?.orderOut(nil)
        }

        return screens
    }

    private func render(
        intent: OverlayIntent,
        screens: [ScreenPanel],
        animateEntrance: Bool
    ) {
        for screen in screens {
            let presentation: FocusOverlayPresentation = screen.descriptor.id
                == expandedScreenID ? .expanded : .compact
            let screenID = screen.descriptor.id
            screen.panel.updateContent(
                FocusOverlayView(
                    intent: intent,
                    presentation: presentation,
                    onExpand: { [weak self] in
                        self?.expand(on: screenID)
                    },
                    onAction: { [weak self] action in
                        self?.handle(action)
                    }
                )
            )
            let frame = FocusRibbonLayout.frame(
                for: presentation,
                on: screen.descriptor
            )
            present(
                screen.panel,
                at: frame,
                animateEntrance: animateEntrance && !screen.panel.isVisible
            )
        }

        if let expandedScreenID,
           let expandedPanel = panels[expandedScreenID] {
            // A nonactivating panel can receive keyboard input without making
            // Attune the active application. Keep compact cues click-only.
            expandedPanel.makeKey()
        }
    }

    private func present(
        _ panel: FocusRibbonPanel,
        at frame: NSRect,
        animateEntrance: Bool
    ) {
        guard animateEntrance else {
            panel.alphaValue = 1
            if panel.isVisible,
               panel.frame != frame,
               !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                panel.orderFrontRegardless()
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.2
                    context.allowsImplicitAnimation = true
                    panel.animator().setFrame(frame, display: true)
                }
            } else {
                panel.setFrame(frame, display: panel.isVisible)
                panel.orderFrontRegardless()
            }
            return
        }

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.alphaValue = 0
        panel.setFrame(
            reduceMotion ? frame : frame.offsetBy(dx: 0, dy: 12),
            display: false
        )
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0.12 : 0.28
            context.allowsImplicitAnimation = true
            panel.animator().alphaValue = 1
            if !reduceMotion {
                panel.animator().setFrame(frame, display: true)
            }
        }
    }

    private func expand(on screenID: CGDirectDisplayID) {
        guard expandedScreenID != screenID,
              panels[screenID] != nil,
              let intent else {
            return
        }
        expandedScreenID = screenID
        render(
            intent: intent,
            screens: currentScreenPanels(),
            animateEntrance: false
        )
    }

    private func handle(_ action: OverlayAction) {
        guard let actionHandler else {
            return
        }

        // Clear before delivery so a double click cannot deliver the same action
        // twice. A failed Return re-presents and installs a new one after its
        // asynchronous hide observation completes.
        self.actionHandler = nil
        actionHandler(action)
    }

    private func currentScreenPanels() -> [ScreenPanel] {
        NSScreen.screens.compactMap { screen in
            guard let descriptor = screenDescriptor(for: screen),
                  let panel = panels[descriptor.id] else {
                return nil
            }
            return ScreenPanel(descriptor: descriptor, panel: panel)
        }
    }

    private func screenDescriptor(
        for screen: NSScreen?
    ) -> FocusRibbonScreenDescriptor? {
        guard let screen,
              let screenNumber = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
              ] as? NSNumber else {
            return nil
        }

        return FocusRibbonScreenDescriptor(
            id: CGDirectDisplayID(screenNumber.uint32Value),
            frame: screen.frame,
            visibleFrame: screen.visibleFrame
        )
    }
}

private struct ScreenPanel {
    let descriptor: FocusRibbonScreenDescriptor
    let panel: FocusRibbonPanel
}
