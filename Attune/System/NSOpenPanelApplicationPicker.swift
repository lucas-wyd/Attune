import AppKit
import Foundation
import UniformTypeIdentifiers

struct ApplicationBundleInformation: Equatable {
    let bundleIdentifier: String?
    let displayName: String?
}

@MainActor
struct ApplicationSelectionResolver {
    typealias BundleInformationLoader = (URL) -> ApplicationBundleInformation?

    private let selfBundleIdentifier: String?
    private let coreServicesDirectoryURL: URL
    private let bundleInformationLoader: BundleInformationLoader

    init(
        selfBundleIdentifier: String?,
        coreServicesDirectoryURL: URL = URL(
            fileURLWithPath: "/System/Library/CoreServices",
            isDirectory: true
        ),
        bundleInformationLoader: @escaping BundleInformationLoader = Self.loadBundleInformation
    ) {
        self.selfBundleIdentifier = selfBundleIdentifier
        self.coreServicesDirectoryURL = coreServicesDirectoryURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
        self.bundleInformationLoader = bundleInformationLoader
    }

    func resolve(
        urls: [URL],
        excludingBundleIdentifiers: Set<String>
    ) -> ApplicationPickerResult {
        var acceptedApplications: [AppIdentity] = []
        var rejections: [ApplicationPickerRejection] = []
        var encounteredBundleIdentifiers = excludingBundleIdentifiers

        for selectedURL in urls {
            let resolvedURL = selectedURL
                .resolvingSymlinksInPath()
                .standardizedFileURL
            let fallbackDisplayName = Self.fallbackDisplayName(for: resolvedURL)
            let bundleInformation = bundleInformationLoader(resolvedURL)
            let bundleIdentifier = bundleInformation?.bundleIdentifier?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName = Self.displayName(
                bundleInformation?.displayName,
                fallback: fallbackDisplayName
            )

            guard let bundleIdentifier, !bundleIdentifier.isEmpty else {
                rejections.append(ApplicationPickerRejection(
                    displayName: displayName,
                    reason: .missingStableBundleIdentifier
                ))
                continue
            }

            if ProtectedApplications.isProtected(
                bundleIdentifier: bundleIdentifier,
                selfBundleIdentifier: selfBundleIdentifier
            ) {
                rejections.append(ApplicationPickerRejection(
                    displayName: displayName,
                    reason: .protectedApplication
                ))
                continue
            }

            if isInsideCoreServices(resolvedURL) {
                rejections.append(ApplicationPickerRejection(
                    displayName: displayName,
                    reason: .recoveryCriticalLocation
                ))
                continue
            }

            guard encounteredBundleIdentifiers.insert(bundleIdentifier).inserted else {
                rejections.append(ApplicationPickerRejection(
                    displayName: displayName,
                    reason: .duplicateApplication
                ))
                continue
            }

            acceptedApplications.append(AppIdentity(
                bundleIdentifier: bundleIdentifier,
                displayName: displayName
            ))
        }

        return ApplicationPickerResult(
            acceptedApplications: acceptedApplications,
            rejections: rejections,
            wasCancelled: false
        )
    }

    private func isInsideCoreServices(_ applicationURL: URL) -> Bool {
        let applicationPath = applicationURL.path
        let coreServicesPath = coreServicesDirectoryURL.path
        return applicationPath == coreServicesPath
            || applicationPath.hasPrefix(coreServicesPath + "/")
    }

    nonisolated static func loadBundleInformation(
        at applicationURL: URL
    ) -> ApplicationBundleInformation? {
        guard let bundle = Bundle(url: applicationURL) else {
            return nil
        }

        let displayName = bundle.object(
            forInfoDictionaryKey: "CFBundleDisplayName"
        ) as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String

        return ApplicationBundleInformation(
            bundleIdentifier: bundle.bundleIdentifier,
            displayName: displayName
        )
    }

    private static func fallbackDisplayName(for applicationURL: URL) -> String {
        let name = applicationURL.deletingPathExtension().lastPathComponent
        return name.isEmpty ? "Selected application" : name
    }

    private static func displayName(_ candidate: String?, fallback: String) -> String {
        guard let candidate else {
            return fallback
        }
        let trimmedCandidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedCandidate.isEmpty ? fallback : trimmedCandidate
    }
}

@MainActor
final class NSOpenPanelApplicationPicker: ApplicationPicker {
    typealias PanelFactory = () -> NSOpenPanel
    typealias AvailabilityLookup = (String) -> URL?

    private let panelFactory: PanelFactory
    private let availabilityLookup: AvailabilityLookup
    private let resolver: ApplicationSelectionResolver

    init(
        selfBundleIdentifier: String? = Bundle.main.bundleIdentifier,
        panelFactory: @escaping PanelFactory = { NSOpenPanel() },
        availabilityLookup: @escaping AvailabilityLookup = { bundleIdentifier in
            NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: bundleIdentifier
            )
        },
        bundleInformationLoader: @escaping ApplicationSelectionResolver.BundleInformationLoader = ApplicationSelectionResolver.loadBundleInformation
    ) {
        self.panelFactory = panelFactory
        self.availabilityLookup = availabilityLookup
        resolver = ApplicationSelectionResolver(
            selfBundleIdentifier: selfBundleIdentifier,
            bundleInformationLoader: bundleInformationLoader
        )
    }

    func pickApplications(
        excludingBundleIdentifiers: Set<String>
    ) async -> ApplicationPickerResult {
        let panel = panelFactory()
        Self.configure(panel)

        guard panel.runModal() == .OK else {
            return .cancelled
        }

        return resolver.resolve(
            urls: panel.urls,
            excludingBundleIdentifiers: excludingBundleIdentifiers
        )
    }

    func isAvailable(_ application: AppIdentity) -> Bool {
        availabilityLookup(application.bundleIdentifier) != nil
    }

    static func configure(_ panel: NSOpenPanel) {
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
    }
}
