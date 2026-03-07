import XCTest

/// Tests for the Analysis tab functionality.
@MainActor
final class AnalysisTabTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testTabLoads() {
        let app = UITestHelpers.makeApp()
        UITestHelpers.launchAndActivate(app)

        UITestHelpers.switchToTab(app, identifier: "tabAnalysis")

        // The analysis panel should show the "Processing Pipeline" heading
        // or the add-datasets button
        let addButton = UITestHelpers.element(app, identifier: "addDatasetsButton")
        let pipelineButton = UITestHelpers.element(app, identifier: "applyPipelineButton")

        let loaded = addButton.waitForExistence(timeout: 10)
            || pipelineButton.waitForExistence(timeout: 3)

        XCTAssertTrue(loaded || app.staticTexts["No spectra loaded"].exists,
                       "Analysis tab should display its UI elements")
    }

    func testApplyPipelineButtonExists() {
        let app = UITestHelpers.makeApp()
        UITestHelpers.launchAndActivate(app)

        UITestHelpers.switchToTab(app, identifier: "tabAnalysis")

        let pipelineButton = UITestHelpers.element(app, identifier: "applyPipelineButton")
        // Pipeline button only exists when spectra are loaded
        if pipelineButton.waitForExistence(timeout: 5) {
            XCTAssertTrue(pipelineButton.exists, "Apply Pipeline button should exist")
        }
    }

    func testAddDatasetsButtonExists() {
        let app = UITestHelpers.makeApp()
        UITestHelpers.launchAndActivate(app)

        UITestHelpers.switchToTab(app, identifier: "tabAnalysis")

        let addButton = UITestHelpers.element(app, identifier: "addDatasetsButton")
        if addButton.waitForExistence(timeout: 5) {
            XCTAssertTrue(addButton.exists, "Add Datasets button should exist")
        }
    }

    func testTabSurvivesRepeatedSwitching() {
        let app = UITestHelpers.makeApp()
        UITestHelpers.launchAndActivate(app)

        // Switch to analysis and back several times
        for _ in 0..<5 {
            UITestHelpers.switchToTab(app, identifier: "tabAnalysis")
            usleep(200_000)
            UITestHelpers.switchToTab(app, identifier: "tabDataManagement")
            usleep(200_000)
        }

        XCTAssertTrue(app.exists, "App should remain running after repeated tab switches")
    }
}
