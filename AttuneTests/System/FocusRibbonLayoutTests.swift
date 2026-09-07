import AppKit
import Testing
@testable import Attune

@Suite("Focus ribbon layout")
struct FocusRibbonLayoutTests {
    private let builtIn = FocusRibbonScreenDescriptor(
        id: 1,
        frame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
        visibleFrame: CGRect(x: 0, y: 25, width: 1_440, height: 875)
    )
    private let external = FocusRibbonScreenDescriptor(
        id: 2,
        frame: CGRect(x: 1_440, y: 0, width: 1_920, height: 1_080),
        visibleFrame: CGRect(x: 1_440, y: 0, width: 1_920, height: 1_055)
    )

    @Test("Pointer display wins over the main display")
    func selectsPointerDisplay() {
        #expect(FocusRibbonLayout.targetScreenID(
            screens: [builtIn, external],
            pointerLocation: CGPoint(x: 2_200, y: 500),
            mainScreenID: builtIn.id
        ) == external.id)
    }

    @Test("Main display is only the fallback when the pointer is outside every display")
    func fallsBackToMainDisplay() {
        #expect(FocusRibbonLayout.targetScreenID(
            screens: [builtIn, external],
            pointerLocation: CGPoint(x: 8_000, y: 8_000),
            mainScreenID: builtIn.id
        ) == builtIn.id)
    }

    @Test("First display is the final fallback when the main display is unavailable")
    func fallsBackToFirstDisplay() {
        #expect(FocusRibbonLayout.targetScreenID(
            screens: [external],
            pointerLocation: CGPoint(x: 8_000, y: 8_000),
            mainScreenID: builtIn.id
        ) == external.id)
    }

    @Test("Displays with negative coordinates are selectable")
    func selectsNegativeCoordinateDisplay() {
        let leftDisplay = FocusRibbonScreenDescriptor(
            id: 3,
            frame: CGRect(x: -1_280, y: -180, width: 1_280, height: 800),
            visibleFrame: CGRect(x: -1_280, y: -180, width: 1_280, height: 775)
        )

        #expect(FocusRibbonLayout.targetScreenID(
            screens: [builtIn, leftDisplay],
            pointerLocation: CGPoint(x: -640, y: 200),
            mainScreenID: builtIn.id
        ) == leftDisplay.id)
    }

    @Test("Compact and expanded ribbons are top-centered in the visible frame")
    func topCentersFrames() {
        let compact = FocusRibbonLayout.frame(
            for: .compact,
            on: builtIn
        )
        let expanded = FocusRibbonLayout.frame(
            for: .expanded,
            on: builtIn
        )

        #expect(compact.size == FocusRibbonLayout.compactSize)
        #expect(expanded.size == FocusRibbonLayout.expandedSize)
        #expect(compact.midX == builtIn.visibleFrame.midX)
        #expect(expanded.midX == builtIn.visibleFrame.midX)
        #expect(compact.maxY == builtIn.visibleFrame.maxY - FocusRibbonLayout.topInset)
        #expect(expanded.maxY == builtIn.visibleFrame.maxY - FocusRibbonLayout.topInset)
    }

    @Test("Ribbon width is clamped inside narrow visible frames")
    func clampsNarrowDisplays() {
        let narrowDisplay = FocusRibbonScreenDescriptor(
            id: 4,
            frame: CGRect(x: -320, y: 100, width: 300, height: 700),
            visibleFrame: CGRect(x: -310, y: 120, width: 280, height: 650)
        )

        let compact = FocusRibbonLayout.frame(for: .compact, on: narrowDisplay)
        let expanded = FocusRibbonLayout.frame(for: .expanded, on: narrowDisplay)
        let expectedWidth = narrowDisplay.visibleFrame.width
            - FocusRibbonLayout.horizontalInset * 2

        #expect(compact.width == expectedWidth)
        #expect(expanded.width == expectedWidth)
        #expect(compact.minX == narrowDisplay.visibleFrame.minX + FocusRibbonLayout.horizontalInset)
        #expect(expanded.minX == narrowDisplay.visibleFrame.minX + FocusRibbonLayout.horizontalInset)
    }

    @Test("Countdown updates preserve the panel host and fixed frame")
    @MainActor
    func countdownUpdatesInPlace() throws {
        let panel = FocusRibbonPanel()
        let fixedFrame = CGRect(x: 100, y: 200, width: 520, height: 230)
        panel.updateContent(view(status: "Open Anyway is available in 8 seconds."))
        panel.setFrame(fixedFrame, display: false)
        let initialController = try #require(panel.contentViewController)

        panel.updateContent(view(status: "Open Anyway is available in 7 seconds."))

        #expect(panel.contentViewController === initialController)
        #expect(panel.frame == fixedFrame)
    }

    @Test("Presenting a ribbon preserves the app activation policy")
    @MainActor
    func presentationPreservesActivationPolicy() {
        let application = NSApplication.shared
        let originalPolicy = application.activationPolicy()
        _ = application.setActivationPolicy(.regular)
        let coordinator = OverlayCoordinator()
        defer {
            coordinator.dismiss()
            _ = application.setActivationPolicy(originalPolicy)
        }

        coordinator.present(
            OverlayIntent(
                title: "Blocked Example",
                message: "Back to focus.",
                primaryActionTitle: "Return to Focus"
            ),
            onAction: { _ in }
        )

        #expect(application.activationPolicy() == .regular)
        #expect(coordinator.presentedDisplayCount == NSScreen.screens.count)

        coordinator.dismiss()
        coordinator.present(
            OverlayIntent(
                title: "Blocked Example",
                message: "Back to focus.",
                primaryActionTitle: "Return to Focus"
            ),
            onAction: { _ in }
        )

        #expect(application.activationPolicy() == .regular)
        #expect(coordinator.presentedDisplayCount == NSScreen.screens.count)
    }

    @MainActor
    private func view(status: String) -> FocusOverlayView {
        FocusOverlayView(
            intent: OverlayIntent(
                title: "You chose to focus",
                message: "Example is outside the current intention.",
                primaryActionTitle: "Return to Focus",
                secondaryActionTitle: "Open Anyway",
                secondaryActionStatus: status,
                isSecondaryActionEnabled: false
            ),
            presentation: .expanded,
            onExpand: {},
            onAction: { _ in }
        )
    }
}
