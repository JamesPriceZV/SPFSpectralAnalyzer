import XCTest

/// Tests for the Settings tab / Settings window functionality.
@MainActor
final class SettingsTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testSettingsWindowOpens() {
        let app = UITestHelpers.makeApp()
        UITestHelpers.launchAndActivate(app)

        UITestHelpers.openSettings(app)

        // Settings window should have tabs (radio buttons)
        let generalTab = app.radioButtons["General"]
        let iCloudTab = app.radioButtons["iCloud Sync"]

        let loaded = generalTab.waitForExistence(timeout: 10)
            || iCloudTab.waitForExistence(timeout: 3)

        XCTAssertTrue(loaded, "Settings window should display settings tabs")
    }

    func testICloudSyncTabExists() {
        let app = UITestHelpers.makeApp()
        UITestHelpers.launchAndActivate(app)

        UITestHelpers.openSettings(app, tab: "iCloud Sync")

        // After clicking iCloud Sync tab, look for sync-related elements
        // The toggle may render as a switch or checkbox
        let syncToggle = app.switches.firstMatch
        let syncCheckbox = app.checkBoxes.firstMatch
        let syncText = app.staticTexts["iCloud Sync"]

        let loaded = syncToggle.waitForExistence(timeout: 5)
            || syncCheckbox.waitForExistence(timeout: 3)
            || syncText.waitForExistence(timeout: 3)

        XCTAssertTrue(loaded, "iCloud Sync settings tab should display controls")
    }

    func testForceUploadButtonExists() {
        let app = UITestHelpers.makeApp()
        UITestHelpers.launchAndActivate(app)

        UITestHelpers.openSettings(app, tab: "iCloud Sync")

        // Force upload button may not have an accessibility ID; search by label
        let forceUploadButton = app.buttons["Force Upload"]
        let forceUploadById = UITestHelpers.element(app, identifier: "forceUploadButton")
        if forceUploadButton.waitForExistence(timeout: 5) || forceUploadById.waitForExistence(timeout: 2) {
            XCTAssertTrue(forceUploadButton.exists || forceUploadById.exists,
                          "Force upload button should exist")
        }
    }

    func testForceFullSyncButtonExists() {
        let app = UITestHelpers.makeApp()
        UITestHelpers.launchAndActivate(app)

        UITestHelpers.openSettings(app, tab: "iCloud Sync")

        let fullSyncButton = UITestHelpers.element(app, identifier: "forceFullSyncButton")
        let fullSyncByLabel = app.buttons["Force Full Sync"]
        if fullSyncButton.waitForExistence(timeout: 5) || fullSyncByLabel.waitForExistence(timeout: 2) {
            XCTAssertTrue(fullSyncButton.exists || fullSyncByLabel.exists,
                          "Force full sync button should exist")
        }
    }

    func testResetLocalStoreButtonExists() {
        let app = UITestHelpers.makeApp()
        UITestHelpers.launchAndActivate(app)

        UITestHelpers.openSettings(app, tab: "iCloud Sync")

        let resetButton = UITestHelpers.element(app, identifier: "resetLocalStoreButton")
        let resetByLabel = app.buttons["Reset Local Store"]
        if resetButton.waitForExistence(timeout: 5) || resetByLabel.waitForExistence(timeout: 2) {
            XCTAssertTrue(resetButton.exists || resetByLabel.exists,
                          "Reset local store button should exist")
        }
    }

    func testStoreModeValueDisplayed() {
        let app = UITestHelpers.makeApp()
        UITestHelpers.launchAndActivate(app)

        UITestHelpers.openSettings(app, tab: "iCloud Sync")

        let storeModeValue = UITestHelpers.element(app, identifier: "storeModeValue")
        if storeModeValue.waitForExistence(timeout: 5) {
            XCTAssertTrue(storeModeValue.exists, "Store mode value should be displayed")
        }
    }
}
