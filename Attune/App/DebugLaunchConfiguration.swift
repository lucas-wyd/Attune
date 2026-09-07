import Foundation

struct DebugBootstrapConfiguration: Equatable, Sendable {
    let selectedApplication: AppIdentity
    let interruptedRemainingSeconds: Int?
}

struct DebugLaunchConfiguration: Equatable, Sendable {
    let adapterLabEnabled: Bool
    let stateDirectoryURL: URL?
    let bootstrap: DebugBootstrapConfiguration?

    init(
        adapterLabEnabled: Bool,
        stateDirectoryURL: URL? = nil,
        bootstrap: DebugBootstrapConfiguration? = nil
    ) {
        self.adapterLabEnabled = adapterLabEnabled
        self.stateDirectoryURL = stateDirectoryURL
        self.bootstrap = bootstrap
    }

    static func current(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        processIdentifier: Int32 = ProcessInfo.processInfo.processIdentifier,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory
    ) -> DebugLaunchConfiguration {
        #if DEBUG
        let explicitStateDirectoryURL = value(
            after: "--attune-test-state-directory",
            in: arguments
        ).map {
            URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL
        }
        let stateDirectoryURL: URL?
        if let explicitStateDirectoryURL {
            stateDirectoryURL = explicitStateDirectoryURL
        } else if environment["XCTestConfigurationFilePath"] != nil {
            stateDirectoryURL = temporaryDirectory.appendingPathComponent(
                "Attune-UnitTestHost-\(processIdentifier)",
                isDirectory: true
            )
        } else {
            stateDirectoryURL = nil
        }

        let bundleIdentifier = value(
            after: "--attune-test-app-bundle-identifier",
            in: arguments
        )
        let displayName = value(
            after: "--attune-test-app-display-name",
            in: arguments
        )
        let remainingSeconds = value(
            after: "--attune-test-interrupted-seconds",
            in: arguments
        ).flatMap(Int.init)

        let bootstrap: DebugBootstrapConfiguration?
        if let bundleIdentifier, let displayName {
            bootstrap = DebugBootstrapConfiguration(
                selectedApplication: AppIdentity(
                    bundleIdentifier: bundleIdentifier,
                    displayName: displayName
                ),
                interruptedRemainingSeconds: remainingSeconds
            )
        } else {
            bootstrap = nil
        }

        return DebugLaunchConfiguration(
            adapterLabEnabled: arguments.contains("--adapter-lab"),
            stateDirectoryURL: stateDirectoryURL,
            bootstrap: bootstrap
        )
        #else
        return DebugLaunchConfiguration(adapterLabEnabled: false)
        #endif
    }

    #if DEBUG
    private static func value(
        after flag: String,
        in arguments: [String]
    ) -> String? {
        guard let index = arguments.firstIndex(of: flag) else {
            return nil
        }
        let valueIndex = arguments.index(after: index)
        guard arguments.indices.contains(valueIndex) else {
            return nil
        }
        let value = arguments[valueIndex]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
    #endif
}
