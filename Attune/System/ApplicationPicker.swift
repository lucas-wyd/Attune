import Foundation

@MainActor
protocol ApplicationPicker {
    func pickApplications(
        excludingBundleIdentifiers: Set<String>
    ) async -> ApplicationPickerResult

    func isAvailable(_ application: AppIdentity) -> Bool
}

struct ApplicationPickerResult: Equatable, Sendable {
    let acceptedApplications: [AppIdentity]
    let rejections: [ApplicationPickerRejection]
    let wasCancelled: Bool

    static let cancelled = ApplicationPickerResult(
        acceptedApplications: [],
        rejections: [],
        wasCancelled: true
    )

    var containsBrowser: Bool {
        acceptedApplications.contains { application in
            BrowserApplications.isBrowser(
                bundleIdentifier: application.bundleIdentifier
            )
        }
    }
}

struct ApplicationPickerRejection: Equatable, Sendable {
    let displayName: String
    let reason: ApplicationPickerRejectionReason

    var message: String {
        switch reason {
        case .missingStableBundleIdentifier:
            "\(displayName) could not be selected because it has no stable bundle identifier."
        case .protectedApplication:
            "\(displayName) is protected so Attune remains recoverable."
        case .recoveryCriticalLocation:
            "\(displayName) is part of macOS recovery services and cannot be selected."
        case .duplicateApplication:
            "\(displayName) is already selected."
        }
    }
}

enum ApplicationPickerRejectionReason: Equatable, Sendable {
    case missingStableBundleIdentifier
    case protectedApplication
    case recoveryCriticalLocation
    case duplicateApplication
}

enum BrowserApplications {
    static let wholeBrowserWarning =
        "Attune affects the entire browser. It cannot distinguish work sites from TikTok, Bilibili, or another tab."

    private static let bundleIdentifiers: Set<String> = [
        "com.apple.Safari",
        "com.apple.SafariTechnologyPreview",
        "com.brave.Browser",
        "com.google.Chrome",
        "com.google.Chrome.beta",
        "com.google.Chrome.canary",
        "com.kagi.kagimacOS",
        "com.microsoft.edgemac",
        "com.microsoft.edgemac.Beta",
        "com.microsoft.edgemac.Canary",
        "com.microsoft.edgemac.Dev",
        "com.operasoftware.Opera",
        "com.vivaldi.Vivaldi",
        "company.thebrowser.Browser",
        "org.chromium.Chromium",
        "org.mozilla.firefox",
        "org.mozilla.firefoxdeveloperedition"
    ]

    static func isBrowser(bundleIdentifier: String) -> Bool {
        bundleIdentifiers.contains(bundleIdentifier)
    }
}
