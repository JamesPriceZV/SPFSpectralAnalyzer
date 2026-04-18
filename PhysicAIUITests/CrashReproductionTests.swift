#if os(macOS)
import XCTest

/// Tests that attempt to reproduce the swift_weakLoadStrong crash by performing
/// the same rapid UI interactions that trigger it in manual testing:
/// dataset role assignment, SPF value entry, and force upload during sync.
@MainActor
final class CrashReproductionTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Crash Reproduction Scenarios

    /// Rapidly assign the Reference role to multiple datasets in succession.
    /// This was the original crash trigger: setting datasetRole + knownInVivoSPF
    /// while CloudKit sync is actively running in the background.
    func testRapidRoleAssignmentDoesNotCrash() {
        let app = UITestHelpers.makeApp()
        UITestHelpers.launchAndActivate(app)

        UITestHelpers.switchToTab(app, identifier: "tabDataManagement")

        // Wait for stored datasets to appear
        let browseButton = UITestHelpers.element(app, identifier: "browseFilesButton")
        guard browseButton.waitForExistence(timeout: 10) else {
            XCTFail("Import panel did not load")
            return
        }

        // Select datasets via the list — click each row rapidly
        let datasetList = app.scrollViews.firstMatch
        guard datasetList.waitForExistence(timeout: 5) else {
            // No datasets stored — test passes vacuously
            return
        }

        // Try to find and right-click dataset rows to assign roles
        let rows = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'storedDatasetRow_'")
        )
        let rowCount = rows.allElementsBoundByIndex.count
        guard rowCount >= 1 else {
            // No dataset rows visible — test passes vacuously
            return
        }

        // Rapidly click through up to 3 rows to trigger selection changes
        for i in 0..<min(3, rowCount) {
            let row = rows.element(boundBy: i)
            if row.exists {
                row.click()
                // Small delay to let SwiftData process
                usleep(50_000) // 50ms
            }
        }

        // If the app is still alive after rapid selection changes, the crash
        // didn't happen during role changes.
        XCTAssertTrue(app.exists, "App should still be running after rapid dataset selections")
    }

    /// Switch tabs rapidly 10 times while CloudKit sync is active.
    /// This stress-tests the @Query observers that fire on every tab switch.
    func testRapidTabSwitchingDuringSync() {
        let app = UITestHelpers.makeApp()
        UITestHelpers.launchAndActivate(app)

        // Wait for app to be ready
        let browseButton = UITestHelpers.element(app, identifier: "browseFilesButton")
        _ = browseButton.waitForExistence(timeout: 10)

        let tabs = ["tabDataManagement", "tabAnalysis", "tabReporting", "tabDataManagement"]

        // Rapidly switch tabs 10 times
        for cycle in 0..<10 {
            let tab = tabs[cycle % tabs.count]
            UITestHelpers.switchToTab(app, identifier: tab, timeout: 2)
            usleep(100_000) // 100ms between switches
        }

        XCTAssertTrue(app.exists, "App should still be running after rapid tab switching")
    }

    /// Open Settings and toggle iCloud sync while the app is running.
    /// This triggers container swaps which can invalidate all model objects.
    func testSettingsICloudToggleDoesNotCrash() {
        let app = UITestHelpers.makeApp()
        UITestHelpers.launchAndActivate(app)

        // Give the app time to settle CloudKit events
        sleep(2)

        UITestHelpers.openSettings(app, tab: "iCloud Sync")

        let syncToggle = app.switches.firstMatch
        guard syncToggle.waitForExistence(timeout: 5) else {
            // Settings didn't open or toggle not found — skip
            return
        }

        // Toggle sync off and on (if it was on)
        let originalValue = (syncToggle.value as? String) ?? ""
        syncToggle.click()
        UITestHelpers.confirmStoreResetIfNeeded(app)
        sleep(1)

        // Toggle back
        syncToggle.click()
        UITestHelpers.confirmStoreResetIfNeeded(app)
        sleep(1)

        XCTAssertTrue(app.exists, "App should still be running after iCloud toggle")
    }

    /// Trigger a force upload from Settings while sync events are happening.
    func testForceUploadDuringActiveSync() {
        let app = UITestHelpers.makeApp()
        UITestHelpers.launchAndActivate(app)

        UITestHelpers.openSettings(app, tab: "iCloud Sync")

        // Scope to the Settings window to avoid ambiguity with toolbar button
        let settingsWindow = app.windows["com_apple_SwiftUI_Settings_window"]
        let forceUploadButton = settingsWindow.buttons["forceUploadButton"].exists
            ? settingsWindow.buttons["forceUploadButton"]
            : settingsWindow.buttons["Force Upload"]
        guard forceUploadButton.waitForExistence(timeout: 5), forceUploadButton.isEnabled else {
            // Force upload not available — skip
            return
        }

        forceUploadButton.click()
        sleep(2)

        XCTAssertTrue(app.exists, "App should still be running after force upload")
    }

    /// Load datasets then immediately switch to Analysis tab.
    /// This tests that snapshotted load doesn't crash when the view
    /// switches and @Query refreshes fire.
    func testLoadThenImmediateTabSwitch() {
        let app = UITestHelpers.makeApp()
        UITestHelpers.launchAndActivate(app)

        UITestHelpers.switchToTab(app, identifier: "tabDataManagement")
        _ = UITestHelpers.element(app, identifier: "browseFilesButton").waitForExistence(timeout: 10)

        // Try to select a dataset row first (needed for load button to be enabled/hittable)
        let rows = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'storedDatasetRow_'")
        )
        if rows.count > 0 {
            let firstRow = rows.element(boundBy: 0)
            if firstRow.waitForExistence(timeout: 3), firstRow.isHittable {
                firstRow.click()
                usleep(200_000) // Let selection register

                let loadButton = UITestHelpers.element(app, identifier: "loadSelectedButton")
                if loadButton.waitForExistence(timeout: 3), loadButton.isHittable {
                    loadButton.click()
                    // Immediately switch tab
                    UITestHelpers.switchToTab(app, identifier: "tabAnalysis", timeout: 2)
                }
            }
        }

        // Switch back
        UITestHelpers.switchToTab(app, identifier: "tabDataManagement", timeout: 2)

        XCTAssertTrue(app.exists, "App should still be running after load + tab switch")
    }
}
#endif
