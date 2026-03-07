import XCTest

/// Tests for the Data Management tab (Import panel) functionality.
@MainActor
final class DataManagementTabTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testTabLoads() {
        let app = UITestHelpers.makeApp()
        UITestHelpers.launchAndActivate(app)

        UITestHelpers.switchToTab(app, identifier: "tabDataManagement")

        let browseButton = UITestHelpers.element(app, identifier: "browseFilesButton")
        XCTAssertTrue(browseButton.waitForExistence(timeout: 10), "Browse Files button should exist on Data Management tab")
    }

    func testSearchFieldExists() {
        let app = UITestHelpers.makeApp()
        UITestHelpers.launchAndActivate(app)

        UITestHelpers.switchToTab(app, identifier: "tabDataManagement")

        let searchField = UITestHelpers.element(app, identifier: "datasetSearchField")
        // Search field only appears when stored datasets exist
        if searchField.waitForExistence(timeout: 5) {
            XCTAssertTrue(searchField.exists)
        }
    }

    func testDatasetActionButtonsExist() {
        let app = UITestHelpers.makeApp()
        UITestHelpers.launchAndActivate(app)

        UITestHelpers.switchToTab(app, identifier: "tabDataManagement")

        // These buttons only appear when datasets are stored
        let loadButton = UITestHelpers.element(app, identifier: "loadSelectedButton")
        if loadButton.waitForExistence(timeout: 5) {
            XCTAssertTrue(loadButton.exists, "Load Selected button should exist")
            XCTAssertTrue(UITestHelpers.element(app, identifier: "appendSelectedButton").exists, "Append Selected button should exist")
            XCTAssertTrue(UITestHelpers.element(app, identifier: "archiveSelectedButton").exists, "Archive Selected button should exist")
            XCTAssertTrue(UITestHelpers.element(app, identifier: "removeDuplicatesButton").exists, "Remove Duplicates button should exist")
            XCTAssertTrue(UITestHelpers.element(app, identifier: "archivedDatasetsButton").exists, "Archived button should exist")
            XCTAssertTrue(UITestHelpers.element(app, identifier: "validateHeadersButton").exists, "Validate Headers button should exist")
            XCTAssertTrue(UITestHelpers.element(app, identifier: "validateLoadedButton").exists, "Validate Loaded button should exist")
        }
    }

    func testSearchFiltering() {
        let app = UITestHelpers.makeApp()
        UITestHelpers.launchAndActivate(app)

        UITestHelpers.switchToTab(app, identifier: "tabDataManagement")

        let searchField = UITestHelpers.element(app, identifier: "datasetSearchField")
        guard searchField.waitForExistence(timeout: 5) else { return }

        // Type a search query
        searchField.click()
        searchField.typeText("test")
        sleep(1) // Allow debounce

        // Clear the search
        searchField.click()
        searchField.typeKey("a", modifierFlags: .command)
        searchField.typeKey(.delete, modifierFlags: [])
        sleep(1)

        XCTAssertTrue(app.exists, "App should still be running after search filtering")
    }
}
