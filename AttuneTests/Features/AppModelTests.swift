import Foundation
import Testing
@testable import Attune

@Suite("App model")
@MainActor
struct AppModelTests {
    @Test("A fresh model starts on the dashboard")
    func startsOnDashboard() {
        let model = AppModel()

        #expect(model.route == .dashboard)
    }

    @Test("The adapter lab is enabled only by its Debug launch argument")
    func adapterLabLaunchArgument() {
        #if DEBUG
        #expect(DebugLaunchConfiguration.current(arguments: ["Attune"]).adapterLabEnabled == false)
        #expect(DebugLaunchConfiguration.current(
            arguments: ["Attune", "--adapter-lab"]
        ).adapterLabEnabled)
        #else
        #expect(DebugLaunchConfiguration.current(
            arguments: ["Attune", "--adapter-lab"]
        ).adapterLabEnabled == false)
        #endif
    }

    @Test("Hosted unit tests use isolated state unless a fixture path is explicit")
    func hostedUnitTestStateIsolation() {
        #if DEBUG
        let temporaryDirectory = URL(
            fileURLWithPath: "/tmp/AttuneConfigurationTests",
            isDirectory: true
        )
        let testEnvironment = [
            "XCTestConfigurationFilePath": "/tmp/AttuneTests.xctestconfiguration"
        ]

        let isolated = DebugLaunchConfiguration.current(
            arguments: ["Attune"],
            environment: testEnvironment,
            processIdentifier: 42,
            temporaryDirectory: temporaryDirectory
        )
        #expect(
            isolated.stateDirectoryURL
                == temporaryDirectory.appendingPathComponent(
                    "Attune-UnitTestHost-42",
                    isDirectory: true
                )
        )

        let explicit = DebugLaunchConfiguration.current(
            arguments: [
                "Attune",
                "--attune-test-state-directory",
                "/tmp/AttuneExplicitFixture"
            ],
            environment: testEnvironment,
            processIdentifier: 42,
            temporaryDirectory: temporaryDirectory
        )
        #expect(
            explicit.stateDirectoryURL
                == URL(
                    fileURLWithPath: "/tmp/AttuneExplicitFixture",
                    isDirectory: true
                ).standardizedFileURL
        )
        #endif
    }
}
