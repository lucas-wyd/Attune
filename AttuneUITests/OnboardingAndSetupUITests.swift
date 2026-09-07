import Foundation
import XCTest

final class OnboardingAndSetupUITests: XCTestCase {
    private var stateDirectoryURL: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        stateDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Attune-Onboarding-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        if let stateDirectoryURL {
            try? FileManager.default.removeItem(at: stateDirectoryURL)
        }
    }

    @MainActor
    func testOnboardingDisclosesPrivacyThenOpensSoftSetup() {
        let application = makeApplication()
        application.launch()

        XCTAssertTrue(
            application.otherElements["onboarding-introduction"]
                .waitForExistence(timeout: 5)
        )

        application.buttons["onboarding-continue"].click()
        XCTAssertTrue(
            application.otherElements["onboarding-privacy"]
                .waitForExistence(timeout: 2)
        )
        XCTAssertTrue(
            application.staticTexts["onboarding-no-permission-disclosure"].exists
        )

        application.buttons["onboarding-continue"].click()
        XCTAssertTrue(
            application.otherElements["onboarding-applications"]
                .waitForExistence(timeout: 2)
        )
        application.buttons["onboarding-skip-applications"].click()

        XCTAssertTrue(
            application.otherElements["onboarding-modes"]
                .waitForExistence(timeout: 2)
        )
        XCTAssertTrue(
            application.otherElements["onboarding-strict-guarantee"].exists
        )
        application.buttons["onboarding-explore"].click()

        XCTAssertTrue(
            application.staticTexts["dashboard-title"]
                .waitForExistence(timeout: 3)
        )
        application.buttons["dashboard-new-focus"].click()

        XCTAssertTrue(
            application.otherElements["focus-setup-view"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(application.buttons["focus-mode-soft"].isEnabled)
        XCTAssertTrue(application.buttons["focus-mode-medium"].isEnabled)
        XCTAssertTrue(application.buttons["focus-mode-strict"].isEnabled)
        XCTAssertFalse(application.buttons["focus-setup-start"].isEnabled)
    }

    @MainActor
    private func makeApplication() -> XCUIApplication {
        let application = XCUIApplication()
        application.launchArguments = [
            "--attune-test-state-directory",
            stateDirectoryURL.path
        ]
        return application
    }
}
