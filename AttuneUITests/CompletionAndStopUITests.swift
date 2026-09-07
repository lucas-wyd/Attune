import Foundation
import XCTest

final class CompletionAndStopUITests: XCTestCase {
    private var stateDirectoryURL: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        stateDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Attune-Goal-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        if let stateDirectoryURL {
            try? FileManager.default.removeItem(at: stateDirectoryURL)
        }
    }

    @MainActor
    func testSoftGoalRequiresThreeSecondReviewBeforeCompletion() {
        let fixture = XCUIApplication(
            bundleIdentifier: "com.lucaswyd.AttuneFixture"
        )
        fixture.launch()
        XCTAssertTrue(
            fixture.staticTexts["Attune Fixture"].waitForExistence(timeout: 5)
        )

        let application = bootstrappedApplication()
        application.launch()
        XCTAssertTrue(
            application.staticTexts["dashboard-title"].waitForExistence(timeout: 5)
        )

        application.buttons["dashboard-new-focus"].click()
        let intention = application.textFields["focus-setup-intention"]
        XCTAssertTrue(intention.waitForExistence(timeout: 3))
        intention.click()
        intention.typeText("Finish the release note")

        application.buttons["Goal"].click()
        let definition = application.textFields["focus-setup-goal-definition"]
        XCTAssertTrue(definition.waitForExistence(timeout: 2))
        definition.click()
        definition.typeText("A reviewed draft exists")

        let start = application.buttons["focus-setup-start"]
        XCTAssertTrue(start.isEnabled)
        start.click()
        application.buttons["active-session-mark-goal-complete"].click()

        let complete = application.buttons["goal-review-complete-focus"]
        XCTAssertTrue(complete.waitForExistence(timeout: 2))
        XCTAssertFalse(complete.isEnabled)

        let reviewElapsed = XCTWaiter.wait(
            for: [XCTestExpectation(description: "Soft goal review")],
            timeout: 3.2
        )
        XCTAssertEqual(reviewElapsed, .timedOut)
        XCTAssertTrue(complete.isEnabled)
        complete.click()

        XCTAssertTrue(
            application.staticTexts["completion-outcome"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertEqual(
            application.staticTexts["completion-outcome"].label,
            "Goal complete"
        )
        finishCompletion(in: application)
        fixture.terminate()
    }

    @MainActor
    private func bootstrappedApplication() -> XCUIApplication {
        let application = XCUIApplication()
        application.launchArguments = [
            "--attune-test-state-directory",
            stateDirectoryURL.path,
            "--attune-test-app-bundle-identifier",
            "com.lucaswyd.AttuneFixture",
            "--attune-test-app-display-name",
            "Attune Fixture"
        ]
        return application
    }

    @MainActor
    private func finishCompletion(in application: XCUIApplication) {
        let done = application.buttons["completion-done"]
        let expectation = expectation(
            for: NSPredicate(format: "enabled == true"),
            evaluatedWith: done
        )
        wait(for: [expectation], timeout: 3)
        done.click()
        XCTAssertTrue(
            application.staticTexts["dashboard-title"].waitForExistence(timeout: 3)
        )
        application.terminate()
    }
}
