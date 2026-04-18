#if os(macOS)
import XCTest

/// Tests that verify workflows spanning multiple tabs work correctly.
@MainActor
final class CrossTabWorkflowTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Visit every tab in order and verify the app remains stable.
    func testVisitAllTabs() {
        let app = UITestHelpers.makeApp()
        UITestHelpers.launchAndActivate(app)

        let tabs = ["tabDataManagement", "tabAnalysis", "tabReporting"]

        for tab in tabs {
            UITestHelpers.switchToTab(app, identifier: tab)
            sleep(1)
        }

        XCTAssertTrue(app.exists, "App should remain running after visiting all tabs")
    }

    /// Switch from Data Management to Analysis back-to-back.
    /// This simulates a user loading data then analyzing it.
    func testDataManagementToAnalysisWorkflow() {
        let app = UITestHelpers.makeApp()
        UITestHelpers.launchAndActivate(app)

        // Go to Data Management
        UITestHelpers.switchToTab(app, identifier: "tabDataManagement")
        _ = UITestHelpers.element(app, identifier: "browseFilesButton").waitForExistence(timeout: 10)

        // Switch to Analysis
        UITestHelpers.switchToTab(app, identifier: "tabAnalysis")
        sleep(1)

        // Switch back to Data Management
        UITestHelpers.switchToTab(app, identifier: "tabDataManagement")
        sleep(1)

        XCTAssertTrue(app.exists, "App should handle Data Management ↔ Analysis switching")
    }

    /// Switch from Analysis to Reporting, simulating export after analysis.
    func testAnalysisToReportingWorkflow() {
        let app = UITestHelpers.makeApp()
        UITestHelpers.launchAndActivate(app)

        UITestHelpers.switchToTab(app, identifier: "tabAnalysis")
        sleep(1)

        UITestHelpers.switchToTab(app, identifier: "tabReporting")

        let titleField = UITestHelpers.element(app, identifier: "exportTitleField")
        _ = titleField.waitForExistence(timeout: 10)

        XCTAssertTrue(titleField.exists, "Reporting tab should load after switching from Analysis")
    }

    /// Open Settings window, close it, then switch to Data Management.
    /// Verifies that opening Settings doesn't leave stale state.
    func testSettingsToDataManagementSwitch() {
        let app = UITestHelpers.makeApp()
        UITestHelpers.launchAndActivate(app)

        UITestHelpers.openSettings(app)
        sleep(1)
        // Close settings window with Cmd+W
        app.typeKey("w", modifierFlags: .command)
        sleep(1)

        UITestHelpers.switchToTab(app, identifier: "tabDataManagement")

        let browseButton = UITestHelpers.element(app, identifier: "browseFilesButton")
        XCTAssertTrue(browseButton.waitForExistence(timeout: 10),
                       "Data Management should load after closing Settings")
    }

    /// Rapidly cycle through all tabs multiple times.
    func testRapidFullTabCycle() {
        let app = UITestHelpers.makeApp()
        UITestHelpers.launchAndActivate(app)

        let tabs = ["tabDataManagement", "tabAnalysis", "tabReporting"]

        for _ in 0..<3 {
            for tab in tabs {
                UITestHelpers.switchToTab(app, identifier: tab, timeout: 3)
                usleep(150_000) // 150ms
            }
        }

        XCTAssertTrue(app.exists, "App should survive 3 full rapid tab cycles")
    }

    /// Open Settings, toggle something, close, then switch to Data Management.
    func testSettingsInteractionThenTabSwitch() {
        let app = UITestHelpers.makeApp()
        UITestHelpers.launchAndActivate(app)

        UITestHelpers.openSettings(app, tab: "iCloud Sync")

        // Check if iCloud settings sync toggle exists and interact with it
        let settingsSyncToggle = app.switches.firstMatch
        if settingsSyncToggle.waitForExistence(timeout: 5) {
            settingsSyncToggle.click()
            sleep(1)
            // Toggle back to original state
            settingsSyncToggle.click()
            sleep(1)
        }

        // Close settings window
        app.typeKey("w", modifierFlags: .command)
        sleep(1)

        // Switch to Data Management
        UITestHelpers.switchToTab(app, identifier: "tabDataManagement")
        let browseButton = UITestHelpers.element(app, identifier: "browseFilesButton")

        XCTAssertTrue(browseButton.waitForExistence(timeout: 10),
                       "Data Management should work normally after Settings interaction")
    }
}
#endif
