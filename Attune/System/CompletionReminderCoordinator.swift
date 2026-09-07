import AppKit

struct CompletionRibbonAnimationProfile: Equatable, Sendable {
    let fadeInDuration: TimeInterval
    let fadeOutDuration: TimeInterval
    let entranceOffset: CGFloat
    let exitOffset: CGFloat

    static func make(reduceMotion: Bool) -> Self {
        if reduceMotion {
            return Self(
                fadeInDuration: 0.14,
                fadeOutDuration: 0.12,
                entranceOffset: 0,
                exitOffset: 0
            )
        }

        return Self(
            fadeInDuration: 0.32,
            fadeOutDuration: 0.24,
            entranceOffset: 10,
            exitOffset: 6
        )
    }
}

@MainActor
final class CompletionReminderCoordinator: NSObject, CompletionReminderPresenting {
    private let displayDuration: Duration
    private let panel = CompletionRibbonPanel()
    private var intent: CompletionReminderIntent?
    private var targetScreenID: CGDirectDisplayID?
    private var dismissalTask: Task<Void, Never>?
    private var exitAnimationTask: Task<Void, Never>?
    private(set) var isPresented = false

    init(displayDuration: Duration = .seconds(5)) {
        self.displayDuration = displayDuration
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    func present(_ intent: CompletionReminderIntent) {
        self.intent = intent
        isPresented = true
        dismissalTask?.cancel()
        exitAnimationTask?.cancel()
        exitAnimationTask = nil

        let screens = screenDescriptors()
        targetScreenID = CompletionRibbonLayout.targetScreenID(
            screens: screens,
            pointerLocation: NSEvent.mouseLocation,
            mainScreenID: screenDescriptor(for: NSScreen.main)?.id
        )
        render(on: screens, animateEntrance: true)
        scheduleDismissal()
    }

    func dismiss() {
        dismissalTask?.cancel()
        dismissalTask = nil
        intent = nil
        targetScreenID = nil
        isPresented = false

        exitAnimationTask?.cancel()
        exitAnimationTask = nil
        guard panel.isVisible else {
            panel.alphaValue = 1
            panel.orderOut(nil)
            return
        }

        let profile = CompletionRibbonAnimationProfile.make(
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )
        let exitFrame = panel.frame.offsetBy(dx: 0, dy: profile.exitOffset)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = profile.fadeOutDuration
            context.allowsImplicitAnimation = true
            panel.animator().alphaValue = 0
            if profile.exitOffset != 0 {
                panel.animator().setFrame(exitFrame, display: true)
            }
        }

        let fadeOutMilliseconds = Int64(profile.fadeOutDuration * 1_000)
        exitAnimationTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(fadeOutMilliseconds))
            } catch {
                return
            }
            guard let self, !Task.isCancelled else {
                return
            }
            self.panel.orderOut(nil)
            self.panel.alphaValue = 1
            self.exitAnimationTask = nil
        }
    }

    @objc
    private func screenParametersChanged() {
        guard intent != nil else {
            return
        }

        let screens = screenDescriptors()
        if !screens.contains(where: { $0.id == targetScreenID }) {
            targetScreenID = CompletionRibbonLayout.targetScreenID(
                screens: screens,
                pointerLocation: NSEvent.mouseLocation,
                mainScreenID: screenDescriptor(for: NSScreen.main)?.id
            )
        }
        render(on: screens, animateEntrance: false)
    }

    private func render(
        on screens: [FocusRibbonScreenDescriptor],
        animateEntrance: Bool
    ) {
        guard let intent,
              let targetScreenID,
              let targetScreen = screens.first(where: { $0.id == targetScreenID }) else {
            panel.orderOut(nil)
            return
        }

        panel.updateContent(CompletionRibbonView(intent: intent))
        let frame = CompletionRibbonLayout.frame(on: targetScreen)
        present(panel, at: frame, animateEntrance: animateEntrance)
    }

    private func present(
        _ panel: CompletionRibbonPanel,
        at frame: NSRect,
        animateEntrance: Bool
    ) {
        guard animateEntrance else {
            panel.alphaValue = 1
            panel.setFrame(frame, display: panel.isVisible)
            panel.orderFrontRegardless()
            return
        }

        let profile = CompletionRibbonAnimationProfile.make(
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )
        panel.alphaValue = 0
        panel.setFrame(
            frame.offsetBy(dx: 0, dy: profile.entranceOffset),
            display: false
        )
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = profile.fadeInDuration
            context.allowsImplicitAnimation = true
            panel.animator().alphaValue = 1
            if profile.entranceOffset != 0 {
                panel.animator().setFrame(frame, display: true)
            }
        }
    }

    private func scheduleDismissal() {
        let displayDuration = displayDuration
        dismissalTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: displayDuration)
            } catch {
                return
            }
            guard !Task.isCancelled else {
                return
            }
            self?.dismiss()
        }
    }

    private func screenDescriptors() -> [FocusRibbonScreenDescriptor] {
        NSScreen.screens.compactMap(screenDescriptor(for:))
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
