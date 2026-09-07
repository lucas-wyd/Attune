import CoreGraphics

struct FocusRibbonScreenDescriptor: Equatable, Sendable {
    let id: CGDirectDisplayID
    let frame: CGRect
    let visibleFrame: CGRect
}

enum FocusRibbonLayout {
    static let compactSize = CGSize(width: 360, height: 72)
    static let expandedSize = CGSize(width: 520, height: 230)
    static let horizontalInset: CGFloat = 12
    static let topInset: CGFloat = 8

    static func targetScreenID(
        screens: [FocusRibbonScreenDescriptor],
        pointerLocation: CGPoint,
        mainScreenID: CGDirectDisplayID?
    ) -> CGDirectDisplayID? {
        if let pointerScreen = screens.first(where: {
            $0.frame.contains(pointerLocation)
        }) {
            return pointerScreen.id
        }

        if let mainScreenID,
           screens.contains(where: { $0.id == mainScreenID }) {
            return mainScreenID
        }

        return screens.first?.id
    }

    static func frame(
        for presentation: FocusOverlayPresentation,
        on screen: FocusRibbonScreenDescriptor
    ) -> CGRect {
        let preferredSize = switch presentation {
        case .compact:
            compactSize
        case .expanded:
            expandedSize
        }
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
