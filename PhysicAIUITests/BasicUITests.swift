#if os(macOS)
import XCTest

@MainActor
final class BasicUITests: XCTestCase {
    func testLaunches() {
        let app = launchApp()
        XCTAssertTrue(app.exists)
    }


    func testMainWindowTabsExist() {
        let app = launchApp()

        let tabs: [(identifier: String, label: String)] = [
            ("tabDataManagement", "Data Management"),
            ("tabAnalysis", "Analysis"),
            ("tabReporting", "Reporting")
        ]

        for tab in tabs {
            XCTAssertTrue(
                waitForTab(app, identifier: tab.identifier, label: tab.label, timeout: 12),
                "Missing tab item with identifier \(tab.identifier) or label \(tab.label)"
            )
        }
    }

    func testCloudKitMigrationFlow() {
        let app = launchApp()

        if app.buttons["retryCloudKitBannerButton"].waitForExistence(timeout: 2) {
            app.buttons["retryCloudKitBannerButton"].click()
        }

        openSettings(app)

        let syncToggle = app.switches["icloudSyncToggle"]
        if syncToggle.waitForExistence(timeout: 3) {
            let value = (syncToggle.value as? String) ?? ""
            if value == "0" || value.lowercased() == "off" {
                syncToggle.click()
                confirmStoreResetIfNeeded(app)
            }
        }

        if app.buttons["retryCloudKitButton"].exists {
            app.buttons["retryCloudKitButton"].click()
        }

        let fullSyncButton = app.buttons["forceFullSyncButton"]
        if fullSyncButton.waitForExistence(timeout: 3), fullSyncButton.isEnabled {
            fullSyncButton.click()
        }
    }

    func testDiagnosticsConsoleOpens() {
        let app = launchApp()

        openDiagnosticsConsole(app)
        let consoleRoot = diagnosticsElement(app, identifier: "diagnosticsConsoleRoot")
        XCTAssertTrue(consoleRoot.waitForExistence(timeout: 12))
        XCTAssertTrue(diagnosticsElement(app, identifier: "diagnosticsConsoleTitle").exists)
    }

    func testDiagnosticsConsoleFilters() {
        let app = launchApp()

        openDiagnosticsConsole(app)
        let consoleRoot = diagnosticsElement(app, identifier: "diagnosticsConsoleRoot")
        XCTAssertTrue(consoleRoot.waitForExistence(timeout: 12))

        let searchField = diagnosticsElement(app, identifier: "diagnosticsSearchField")
        if searchField.exists {
            searchField.click()
            searchField.typeText("cloudkit")
        }

        let severityMenu = app.buttons["Severity"]
        if severityMenu.exists {
            severityMenu.click()
            let errorToggle = app.menuItems["Error"]
            if errorToggle.exists {
                errorToggle.click()
            }
            app.typeKey(.escape, modifierFlags: [])
        }

        let consoleMenu = app.buttons["Console"]
        if consoleMenu.exists {
            consoleMenu.click()
            let stdoutToggle = app.menuItems["stdout"]
            if stdoutToggle.exists {
                stdoutToggle.click()
            }
            app.typeKey(.escape, modifierFlags: [])
        }

        XCTAssertTrue(diagnosticsElement(app, identifier: "diagnosticsRefreshButton").exists)
        XCTAssertTrue(diagnosticsElement(app, identifier: "diagnosticsCopyButton").exists)
        XCTAssertTrue(diagnosticsElement(app, identifier: "diagnosticsExportJSONButton").exists)
        XCTAssertTrue(diagnosticsElement(app, identifier: "diagnosticsExportExcelButton").exists)
    }

    private func openSettings(_ app: XCUIApplication) {
        let appMenu = app.menuBars.menuBarItems[app.label]
        if appMenu.exists {
            let settingsItem = appMenu.menuItems["Settings…"]
            if settingsItem.exists {
                settingsItem.click()
                return
            }
            let preferencesItem = appMenu.menuItems["Preferences…"]
            if preferencesItem.exists {
                preferencesItem.click()
                return
            }
        }

        let fallbackSettings = app.menuBars.menuBarItems.firstMatch.menuItems["Settings…"]
        if fallbackSettings.exists {
            fallbackSettings.click()
            return
        }

        let fallbackPreferences = app.menuBars.menuBarItems.firstMatch.menuItems["Preferences…"]
        if fallbackPreferences.exists {
            fallbackPreferences.click()
        }
    }

    private func openDiagnosticsConsole(_ app: XCUIApplication) {
        app.typeKey("d", modifierFlags: [.command, .shift])
        let consoleRoot = diagnosticsElement(app, identifier: "diagnosticsConsoleRoot")
        if consoleRoot.waitForExistence(timeout: 2) {
            return
        }

        if let diagnosticsItem = findMenuItem(app, title: "Diagnostics Console") {
            diagnosticsItem.click()
            _ = consoleRoot.waitForExistence(timeout: 4)
        }
    }

    private func findMenuItem(_ app: XCUIApplication, title: String) -> XCUIElement? {
        let menuBarItems = app.menuBars.menuBarItems.allElementsBoundByIndex
        for menuBarItem in menuBarItems {
            menuBarItem.click()
            let item = menuBarItem.menuItems[title]
            if item.waitForExistence(timeout: 1) {
                return item
            }
        }
        return nil
    }

    private func elementMatchingIdentifierOrLabel(
        _ app: XCUIApplication,
        identifier: String,
        label: String
    ) -> XCUIElement {
        let predicate = NSPredicate(format: "identifier == %@ OR label CONTAINS[c] %@", identifier, label)
        return app.descendants(matching: .any).matching(predicate).firstMatch
    }

    private func waitForTab(
        _ app: XCUIApplication,
        identifier: String,
        label: String,
        timeout: TimeInterval
    ) -> Bool {
        let endTime = Date().addingTimeInterval(timeout)
        while Date() < endTime {
            if findTabElement(app, identifier: identifier, label: label) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        }
        return findTabElement(app, identifier: identifier, label: label)
    }

    private func findTabElement(
        _ app: XCUIApplication,
        identifier: String,
        label: String
    ) -> Bool {
        // Check native TabView radio group
        let radioGroup = app.radioGroups["Navigation Tab Bar"]
        if radioGroup.exists {
            let btn = radioGroup.radioButtons[label]
            if btn.exists { return true }
        }

        // Check appModePicker as radio group
        let pickerRadioGroup = app.radioGroups["appModePicker"]
        if pickerRadioGroup.exists {
            if pickerRadioGroup.radioButtons[label].exists { return true }
            if pickerRadioGroup.radioButtons[identifier].exists { return true }
        }

        // Check appModePicker as segmented control
        let segmented = app.segmentedControls["appModePicker"]
        if segmented.exists {
            if segmented.buttons[label].exists { return true }
        }

        // Check any segmented control buttons
        for seg in app.segmentedControls.allElementsBoundByIndex {
            if seg.buttons[label].exists { return true }
        }

        // Check toolbar buttons
        if app.toolbars.buttons[label].exists { return true }

        // Check radio buttons by label
        if app.radioButtons[label].exists { return true }

        // Check buttons by label
        if app.buttons[label].exists { return true }

        // Check by identifier in descendants
        let predicate = NSPredicate(format: "identifier == %@ OR label == %@", identifier, label)
        if app.descendants(matching: .any).matching(predicate).firstMatch.exists { return true }

        return false
    }

    private func diagnosticsElement(_ app: XCUIApplication, identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func launchApp() -> XCUIApplication {
        let app = UITestHelpers.makeApp()
        UITestHelpers.launchAndActivate(app)
        return app
    }

    private func confirmStoreResetIfNeeded(_ app: XCUIApplication) {
        let resetAlert = app.sheets.firstMatch
        if resetAlert.waitForExistence(timeout: 2) {
            if resetAlert.buttons["Continue"].exists {
                resetAlert.buttons["Continue"].click()
            } else if resetAlert.buttons["OK"].exists {
                resetAlert.buttons["OK"].click()
            }
        }
    }
}
#endif
