import CoreGraphics

enum CompletionRibbonLayout {
    static let preferredSize = CGSize(width: 440, height: 96)
    static let horizontalInset: CGFloat = 12
    static let topInset: CGFloat = 8

    static func targetScreenID(
        screens: [FocusRibbonScreenDescriptor],
        pointerLocation: CGPoint,
        mainScreenID: CGDirectDisplayID?
    ) -> CGDirectDisplayID? {
        FocusRibbonLayout.targetScreenID(
            screens: screens,
            pointerLocation: pointerLocation,
            mainScreenID: mainScreenID
        )
    }

    static func frame(on screen: FocusRibbonScreenDescriptor) -> CGRect {
        let availableWidth = max(
            0,
            screen.visibleFrame.width - horizontalInset * 2
        )
        let availableHeight = max(
            0,
            screen.visibleFrame.height - topInset
        )
        let size = CGSize(
            width: min(preferredSize.width, availableWidth),
            height: min(preferredSize.height, availableHeight)
        )

        return CGRect(
            x: screen.visibleFrame.midX - size.width / 2,
            y: screen.visibleFrame.maxY - topInset - size.height,
            width: size.width,
            height: size.height
        )
    }
}
