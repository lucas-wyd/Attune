import AppKit
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import Attune

@Suite("Application picker")
struct ApplicationPickerTests {
    @Test("A valid application maps to stable identity only")
    @MainActor
    func mapsValidApplication() {
        let applicationURL = URL(fileURLWithPath: "/Applications/Example.app")
        let resolver = resolver { url in
            #expect(url == applicationURL)
            return ApplicationBundleInformation(
                bundleIdentifier: "com.example.Application",
                displayName: "Example"
            )
        }

        let result = resolver.resolve(
            urls: [applicationURL],
            excludingBundleIdentifiers: []
        )

        #expect(result == ApplicationPickerResult(
            acceptedApplications: [
                AppIdentity(
                    bundleIdentifier: "com.example.Application",
                    displayName: "Example"
                )
            ],
            rejections: [],
            wasCancelled: false
        ))
    }

    @Test("An application without a stable bundle identifier is rejected")
    @MainActor
    func rejectsMissingBundleIdentifier() {
        let resolver = resolver { _ in
            ApplicationBundleInformation(
                bundleIdentifier: " \n ",
                displayName: nil
            )
        }

        let result = resolver.resolve(
            urls: [URL(fileURLWithPath: "/Applications/No Identifier.app")],
            excludingBundleIdentifiers: []
        )

        #expect(result.acceptedApplications.isEmpty)
        #expect(result.rejections == [
            ApplicationPickerRejection(
                displayName: "No Identifier",
                reason: .missingStableBundleIdentifier
            )
        ])
    }

    @Test("Static protected identifiers and the running Attune identifier are rejected")
    @MainActor
    func rejectsProtectedApplications() {
        let identifiers = [
            "com.apple.finder",
            "com.example.CurrentAttune"
        ]
        var nextIdentifier = identifiers.makeIterator()
        let resolver = ApplicationSelectionResolver(
            selfBundleIdentifier: "com.example.CurrentAttune",
            bundleInformationLoader: { url in
                ApplicationBundleInformation(
                    bundleIdentifier: nextIdentifier.next(),
                    displayName: url.deletingPathExtension().lastPathComponent
                )
            }
        )

        let result = resolver.resolve(
            urls: [
                URL(fileURLWithPath: "/Applications/Finder Copy.app"),
                URL(fileURLWithPath: "/Applications/Attune Copy.app")
            ],
            excludingBundleIdentifiers: []
        )

        #expect(result.acceptedApplications.isEmpty)
        #expect(result.rejections.map(\.reason) == [
            .protectedApplication,
            .protectedApplication
        ])
    }

    @Test("CoreServices checks use the resolved symlink destination")
    @MainActor
    func resolvesSymlinkBeforeCoreServicesCheck() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let coreServicesDirectory = temporaryDirectory
            .appendingPathComponent("CoreServices", isDirectory: true)
        let targetURL = coreServicesDirectory
            .appendingPathComponent("Recovery Agent.app", isDirectory: true)
        let symlinkURL = temporaryDirectory
            .appendingPathComponent("Looks Safe.app", isDirectory: false)
        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        try FileManager.default.createDirectory(
            at: targetURL,
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            at: symlinkURL,
            withDestinationURL: targetURL
        )

        let resolver = ApplicationSelectionResolver(
            selfBundleIdentifier: "com.example.Attune",
            coreServicesDirectoryURL: coreServicesDirectory,
            bundleInformationLoader: { resolvedURL in
                #expect(resolvedURL == targetURL.standardizedFileURL)
                return ApplicationBundleInformation(
                    bundleIdentifier: "com.example.RecoveryAgent",
                    displayName: "Recovery Agent"
                )
            }
        )

        let result = resolver.resolve(
            urls: [symlinkURL],
            excludingBundleIdentifiers: []
        )

        #expect(result.acceptedApplications.isEmpty)
        #expect(result.rejections.map(\.reason) == [.recoveryCriticalLocation])
    }

    @Test("Duplicate installations and already selected identifiers are rejected")
    @MainActor
    func rejectsDuplicateBundleIdentifiers() {
        let resolver = resolver { url in
            ApplicationBundleInformation(
                bundleIdentifier: "com.example.Duplicate",
                displayName: url.deletingPathExtension().lastPathComponent
            )
        }
        let urls = [
            URL(fileURLWithPath: "/Applications/First.app"),
            URL(fileURLWithPath: "/Volumes/Other/Second.app")
        ]

        let duplicateInstallationResult = resolver.resolve(
            urls: urls,
            excludingBundleIdentifiers: []
        )
        let alreadySelectedResult = resolver.resolve(
            urls: [urls[0]],
            excludingBundleIdentifiers: ["com.example.Duplicate"]
        )

        #expect(duplicateInstallationResult.acceptedApplications.count == 1)
        #expect(duplicateInstallationResult.rejections.map(\.reason) == [
            .duplicateApplication
        ])
        #expect(alreadySelectedResult.acceptedApplications.isEmpty)
        #expect(alreadySelectedResult.rejections.map(\.reason) == [
            .duplicateApplication
        ])
    }

    @Test("Browser detection is computed without changing persisted identity")
    @MainActor
    func identifiesWholeBrowserSelection() {
        let resolver = resolver { _ in
            ApplicationBundleInformation(
                bundleIdentifier: "com.apple.Safari",
                displayName: "Safari"
            )
        }

        let result = resolver.resolve(
            urls: [URL(fileURLWithPath: "/Applications/Safari.app")],
            excludingBundleIdentifiers: []
        )

        #expect(result.containsBrowser)
        #expect(result.acceptedApplications == [
            AppIdentity(bundleIdentifier: "com.apple.Safari", displayName: "Safari")
        ])
        #expect(BrowserApplications.isBrowser(bundleIdentifier: "com.google.Chrome"))
        #expect(!BrowserApplications.isBrowser(bundleIdentifier: "com.example.Editor"))
    }

    @Test("Open panel accepts multiple application bundles and no directories")
    @MainActor
    func configuresOpenPanelExactly() {
        let panel = NSOpenPanel()

        NSOpenPanelApplicationPicker.configure(panel)

        #expect(panel.allowedContentTypes == [.applicationBundle])
        #expect(panel.canChooseFiles)
        #expect(!panel.canChooseDirectories)
        #expect(panel.allowsMultipleSelection)
    }

    @Test("Availability uses stable bundle identifier lookup")
    @MainActor
    func checksAvailabilityByBundleIdentifier() {
        var receivedIdentifiers: [String] = []
        let picker = NSOpenPanelApplicationPicker(
            selfBundleIdentifier: "com.example.Attune",
            availabilityLookup: { identifier in
                receivedIdentifiers.append(identifier)
                return identifier == "com.example.Available"
                    ? URL(fileURLWithPath: "/Applications/Available.app")
                    : nil
            },
            bundleInformationLoader: { _ in nil }
        )

        let available = picker.isAvailable(AppIdentity(
            bundleIdentifier: "com.example.Available",
            displayName: "Available"
        ))
        let missing = picker.isAvailable(AppIdentity(
            bundleIdentifier: "com.example.Missing",
            displayName: "Missing"
        ))

        #expect(available)
        #expect(!missing)
        #expect(receivedIdentifiers == [
            "com.example.Available",
            "com.example.Missing"
        ])
    }

    @MainActor
    private func resolver(
        bundleInformationLoader: @escaping ApplicationSelectionResolver.BundleInformationLoader
    ) -> ApplicationSelectionResolver {
        ApplicationSelectionResolver(
            selfBundleIdentifier: "com.example.Attune",
            bundleInformationLoader: bundleInformationLoader
        )
    }
}
