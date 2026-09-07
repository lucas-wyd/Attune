import Foundation
import XCTest

final class SoftFocusUITests: XCTestCase {
    private var stateDirectoryURL: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        stateDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Attune-Soft-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        if let stateDirectoryURL {
            try? FileManager.default.removeItem(at: stateDirectoryURL)
        }
    }

    @MainActor
    func testSoftFocusReturnsThenAllowsOpeningAfterEightSeconds() {
        let fixture = XCUIApplication(
            bundleIdentifier: "com.lucaswyd.AttuneFixture"
        )
        fixture.launch()
        XCTAssertTrue(
            fixture.staticTexts["Attune Fixture"].waitForExistence(timeout: 5)
        )

        let application = XCUIApplication()
        application.launchArguments = [
            "--attune-test-state-directory",
            stateDirectoryURL.path,
            "--attune-test-app-bundle-identifier",
            "com.lucaswyd.AttuneFixture",
            "--attune-test-app-display-name",
            "Attune Fixture"
        ]
        application.launch()

        XCTAssertTrue(
            application.staticTexts["dashboard-title"].waitForExistence(timeout: 5)
        )
        application.buttons["dashboard-new-focus"].click()

        let intention = application.textFields["focus-setup-intention"]
        XCTAssertTrue(intention.waitForExistence(timeout: 3))
        intention.click()
        intention.typeText("Write the MVP release note")

        let start = application.buttons["focus-setup-start"]
        XCTAssertTrue(start.isEnabled)
        start.click()
        XCTAssertTrue(
            application.otherElements["active-session-view"]
                .waitForExistence(timeout: 3)
        )

        fixture.activate()
        let returnAction = application.buttons["focus-overlay-primary-action"]
        XCTAssertTrue(returnAction.waitForExistence(timeout: 2))
        XCTAssertFalse(application.buttons["focus-overlay-secondary-action"].isEnabled)
        returnAction.click()
        XCTAssertFalse(returnAction.waitForExistence(timeout: 2))
        XCTAssertTrue(application.staticTexts["1 intervention"].exists)

        let duplicateWindowElapsed = XCTWaiter.wait(
            for: [XCTestExpectation(description: "activation coalescing window")],
            timeout: 1.1
        )
        XCTAssertEqual(duplicateWindowElapsed, .timedOut)

        fixture.activate()
        let openAction = application.buttons["focus-overlay-secondary-action"]
        XCTAssertTrue(openAction.waitForExistence(timeout: 2))
        XCTAssertFalse(openAction.isEnabled)

        let gateElapsed = XCTWaiter.wait(
            for: [XCTestExpectation(description: "Soft Open Anyway gate")],
            timeout: 8.2
        )
        XCTAssertEqual(gateElapsed, .timedOut)
        XCTAssertTrue(openAction.isEnabled)
        openAction.click()
        XCTAssertFalse(openAction.waitForExistence(timeout: 2))
        XCTAssertTrue(application.staticTexts["2 interventions"].exists)

        application.activate()
        application.buttons["active-session-end-focus"].click()
        XCTAssertTrue(
            application.otherElements["stop-focus-view"]
                .waitForExistence(timeout: 2)
        )

        let stopGateElapsed = XCTWaiter.wait(
            for: [XCTestExpectation(description: "Soft stop gate")],
            timeout: 10.2
        )
        XCTAssertEqual(stopGateElapsed, .timedOut)

        let reason = application.buttons[
            "stop-focus-reason-taskOrPlanChanged"
        ]
        XCTAssertTrue(reason.isEnabled)
        reason.click()
        application.buttons["stop-focus-confirm-end"].click()
        XCTAssertTrue(
            application.otherElements["completion-view"]
                .waitForExistence(timeout: 3)
        )

        let done = application.buttons["completion-done"]
        let readyToLeave = NSPredicate(format: "enabled == true")
        let readyExpectation = expectation(
            for: readyToLeave,
            evaluatedWith: done
        )
        wait(for: [readyExpectation], timeout: 3)
        done.click()
        XCTAssertTrue(
            application.staticTexts["dashboard-title"].waitForExistence(timeout: 3)
        )

        application.terminate()
        fixture.terminate()
    }
}
