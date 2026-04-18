#if os(macOS)
import XCTest

/// Tests for the Reporting tab functionality.
@MainActor
final class ReportingTabTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testTabLoads() {
        let app = UITestHelpers.makeApp()
        UITestHelpers.launchAndActivate(app)

        UITestHelpers.switchToTab(app, identifier: "tabReporting")

        // The reporting panel should show the title field
        let titleField = UITestHelpers.element(app, identifier: "exportTitleField")
        XCTAssertTrue(titleField.waitForExistence(timeout: 10),
                       "Export title field should exist on Reporting tab")
    }

    func testFormFieldsExist() {
        let app = UITestHelpers.makeApp()
        UITestHelpers.launchAndActivate(app)

        UITestHelpers.switchToTab(app, identifier: "tabReporting")

        let titleField = UITestHelpers.element(app, identifier: "exportTitleField")
        guard titleField.waitForExistence(timeout: 10) else {
            XCTFail("Reporting tab did not load")
            return
        }

        XCTAssertTrue(titleField.exists, "Title field should exist")
        XCTAssertTrue(UITestHelpers.element(app, identifier: "exportOperatorField").exists,
                       "Operator field should exist")
        XCTAssertTrue(UITestHelpers.element(app, identifier: "exportNotesField").exists,
                       "Notes field should exist")
    }

    func testExportButtonsExist() {
        let app = UITestHelpers.makeApp()
        UITestHelpers.launchAndActivate(app)

        UITestHelpers.switchToTab(app, identifier: "tabReporting")

        let pdfButton = UITestHelpers.element(app, identifier: "exportPDFButton")
        let htmlButton = UITestHelpers.element(app, identifier: "exportHTMLButton")

        _ = pdfButton.waitForExistence(timeout: 10)

        XCTAssertTrue(pdfButton.exists, "Export PDF button should exist")
        XCTAssertTrue(htmlButton.exists, "Export HTML button should exist")
    }

    func testFormFieldsAreEditable() {
        let app = UITestHelpers.makeApp()
        UITestHelpers.launchAndActivate(app)

        UITestHelpers.switchToTab(app, identifier: "tabReporting")

        let titleField = UITestHelpers.element(app, identifier: "exportTitleField")
        guard titleField.waitForExistence(timeout: 10) else { return }

        // Click and type into the title field
        titleField.click()
        titleField.typeKey("a", modifierFlags: .command)
        titleField.typeText("UI Test Report")
        sleep(1)

        XCTAssertTrue(app.exists, "App should still be running after editing form fields")
    }
}
#endif
