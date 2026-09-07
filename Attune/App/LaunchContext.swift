import AppKit
import CoreServices

enum LaunchContext: Equatable, Sendable {
    case userInitiated
    case loginItem

    @MainActor
    static func current() -> LaunchContext {
        let event = NSAppleEventManager.shared().currentAppleEvent
        let launchProperty = event?.attributeDescriptor(forKeyword: keyAEPropData)
        return launchProperty?.enumCodeValue == keyAELaunchedAsLogInItem
            ? .loginItem
            : .userInitiated
    }
}
