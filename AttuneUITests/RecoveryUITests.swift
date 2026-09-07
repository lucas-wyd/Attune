import Foundation
import XCTest

final class RecoveryUITests: XCTestCase {
    private var stateDirectoryURL: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        stateDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Attune-Recovery-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        if let stateDirectoryURL {
            try? FileManager.default.removeItem(at: stateDirectoryURL)
        }
    }

    @MainActor
    func testInterruptedFocusResumesFromItsSavedRemainingTime() {
        let application = XCUIApplication()
        application.launchArguments = [
            "--attune-test-state-directory",
            stateDirectoryURL.path,
            "--attune-test-app-bundle-identifier",
            "com.lucaswyd.AttuneFixture",
            "--attune-test-app-display-name",
            "Attune Fixture",
            "--attune-test-interrupted-seconds",
            "120"
        ]
        application.launch()

        XCTAssertTrue(
            application.otherElements["interrupted-session-view"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(application.staticTexts["02:00"].exists)
        application.buttons["interrupted-session-resume"].click()

        XCTAssertTrue(
            application.otherElements["active-session-view"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(application.staticTexts["Finish the test focus"].exists)

        application.buttons["active-session-end-focus"].click()
        let stopGateElapsed = XCTWaiter.wait(
            for: [XCTestExpectation(description: "Soft recovery stop gate")],
            timeout: 10.2
        )
        XCTAssertEqual(stopGateElapsed, .timedOut)

        application.buttons["stop-focus-reason-taskOrPlanChanged"].click()
        application.buttons["stop-focus-confirm-end"].click()
        XCTAssertTrue(
            application.otherElements["completion-view"]
                .waitForExistence(timeout: 3)
        )

        let done = application.buttons["completion-done"]
        let expectation = expectation(
            for: NSPredicate(format: "enabled == true"),
            evaluatedWith: done
        )
        wait(for: [expectation], timeout: 3)
        done.click()
        application.terminate()
    }
}
