import AppKit
import Testing
@testable import Attune

@Suite("Completion ribbon layout")
struct CompletionRibbonLayoutTests {
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

    @Test("Success reminder targets the display containing the pointer")
    func selectsPointerDisplay() {
        #expect(CompletionRibbonLayout.targetScreenID(
            screens: [builtIn, external],
            pointerLocation: CGPoint(x: 2_200, y: 500),
            mainScreenID: builtIn.id
        ) == external.id)
    }

    @Test("Success reminder falls back to the main display")
    func fallsBackToMainDisplay() {
        #expect(CompletionRibbonLayout.targetScreenID(
            screens: [builtIn, external],
            pointerLocation: CGPoint(x: 8_000, y: 8_000),
            mainScreenID: builtIn.id
        ) == builtIn.id)
    }

    @Test("Success reminder supports displays with negative coordinates")
    func selectsNegativeCoordinateDisplay() {
        let leftDisplay = FocusRibbonScreenDescriptor(
            id: 3,
            frame: CGRect(x: -1_280, y: -180, width: 1_280, height: 800),
            visibleFrame: CGRect(x: -1_280, y: -180, width: 1_280, height: 775)
        )

        #expect(CompletionRibbonLayout.targetScreenID(
            screens: [builtIn, leftDisplay],
            pointerLocation: CGPoint(x: -640, y: 200),
            mainScreenID: builtIn.id
        ) == leftDisplay.id)
    }

    @Test("Success reminder is top-centered with a stable size")
    func topCentersFrame() {
        let frame = CompletionRibbonLayout.frame(on: builtIn)

        #expect(frame.size == CompletionRibbonLayout.preferredSize)
        #expect(frame.midX == builtIn.visibleFrame.midX)
        #expect(
            frame.maxY
                == builtIn.visibleFrame.maxY - CompletionRibbonLayout.topInset
        )
    }

    @Test("Success reminder stays inside a narrow visible frame")
    func clampsNarrowDisplay() {
        let narrow = FocusRibbonScreenDescriptor(
            id: 4,
            frame: CGRect(x: -320, y: 100, width: 300, height: 700),
            visibleFrame: CGRect(x: -310, y: 120, width: 280, height: 650)
        )

        let frame = CompletionRibbonLayout.frame(on: narrow)

        #expect(
            frame.width
                == narrow.visibleFrame.width
                    - CompletionRibbonLayout.horizontalInset * 2
        )
        #expect(
            frame.minX
                == narrow.visibleFrame.minX + CompletionRibbonLayout.horizontalInset
        )
    }

    @Test("Success panel is click-through and never takes key focus")
    @MainActor
    func panelInteractionContract() {
        let panel = CompletionRibbonPanel()

        #expect(panel.ignoresMouseEvents)
        #expect(!panel.canBecomeKey)
        #expect(!panel.canBecomeMain)
        #expect(panel.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(panel.collectionBehavior.contains(.fullScreenAuxiliary))
    }

    @Test("Success animation fades and drifts gently in normal motion mode")
    func normalMotionProfile() {
        let profile = CompletionRibbonAnimationProfile.make(reduceMotion: false)

        #expect(profile.fadeInDuration > 0)
        #expect(profile.fadeOutDuration > 0)
        #expect(profile.entranceOffset > 0)
        #expect(profile.exitOffset > 0)
    }

    @Test("Reduce Motion preserves fades without vertical movement")
    func reducedMotionProfile() {
        let normal = CompletionRibbonAnimationProfile.make(reduceMotion: false)
        let reduced = CompletionRibbonAnimationProfile.make(reduceMotion: true)

        #expect(reduced.fadeInDuration > 0)
        #expect(reduced.fadeOutDuration > 0)
        #expect(reduced.fadeInDuration < normal.fadeInDuration)
        #expect(reduced.fadeOutDuration < normal.fadeOutDuration)
        #expect(reduced.entranceOffset == 0)
        #expect(reduced.exitOffset == 0)
    }

    @Test("Success reminder automatically dismisses after its display duration")
    @MainActor
    func automaticallyDismisses() async {
        let coordinator = CompletionReminderCoordinator(displayDuration: .zero)
        coordinator.present(CompletionReminderIntent(
            sessionID: UUID(),
            title: "Focus complete",
            message: "Write the release note"
        ))

        #expect(coordinator.isPresented)
        for _ in 0..<20 where coordinator.isPresented {
            await Task.yield()
        }
        #expect(!coordinator.isPresented)
    }
}
