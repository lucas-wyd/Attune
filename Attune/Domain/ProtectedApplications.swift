import Foundation

enum ProtectedApplications {
    static let bundleIdentifiers: Set<String> = [
        "com.lucaswyd.Attune",
        "com.apple.finder",
        "com.apple.dock",
        "com.apple.systempreferences",
        "com.apple.ActivityMonitor",
        "com.apple.loginwindow",
        "com.apple.WindowManager",
        "com.apple.notificationcenterui"
    ]

    static func isProtected(
        bundleIdentifier: String,
        selfBundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) -> Bool {
        bundleIdentifiers.contains(bundleIdentifier)
            || bundleIdentifier == selfBundleIdentifier
    }

    static func isProtectedSelection(
        bundleIdentifier: String,
        applicationURL: URL,
        selfBundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) -> Bool {
        guard !isProtected(
            bundleIdentifier: bundleIdentifier,
            selfBundleIdentifier: selfBundleIdentifier
        ) else {
            return true
        }

        let resolvedPath = applicationURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
        let coreServicesPath = "/System/Library/CoreServices"

        return resolvedPath == coreServicesPath
            || resolvedPath.hasPrefix(coreServicesPath + "/")
    }
}
