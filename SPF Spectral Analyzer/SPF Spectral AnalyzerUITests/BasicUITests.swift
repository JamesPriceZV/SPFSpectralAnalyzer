import XCTest

@MainActor
final class BasicUITests: XCTestCase {
    func testLaunches() {
        let app = makeApp()
        app.launch()
        XCTAssertTrue(app.exists)
    }

    func testMainWindowTabsExist() {
        let app = makeApp()
        app.launch()

        let tabs: [(identifier: String, label: String)] = [
            ("tabImport", "Import"),
            ("tabAnalysis", "Analysis"),
            ("tabAIAnalysis", "AI Analysis"),
            ("tabExport", "Export"),
            ("tabInstrument", "Instrument")
        ]

        for tab in tabs {
            XCTAssertTrue(
                waitForTab(app, identifier: tab.identifier, label: tab.label, timeout: 12),
                "Missing tab item with identifier \(tab.identifier) or label \(tab.label)"
            )
        }
    }

    func testCloudKitMigrationFlow() {
        let app = makeApp()
        app.launch()

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
        let app = makeApp()
        app.launch()

        openDiagnosticsConsole(app)
        let consoleRoot = diagnosticsElement(app, identifier: "diagnosticsConsoleRoot")
        XCTAssertTrue(consoleRoot.waitForExistence(timeout: 12))
        XCTAssertTrue(diagnosticsElement(app, identifier: "diagnosticsConsoleTitle").exists)
    }

    func testDiagnosticsConsoleFilters() {
        let app = makeApp()
        app.launch()

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
        let predicate = NSPredicate(format: "identifier == %@ OR label CONTAINS[c] %@", identifier, label)
        let endTime = Date().addingTimeInterval(timeout)
        while Date() < endTime {
            if tabElementByLabel(app, label: label).exists {
                return true
            }
            if directTabElement(app, identifier: identifier).exists {
                return true
            }
            if matchTabElement(app, predicate: predicate).exists {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return tabElementByLabel(app, label: label).exists
            || directTabElement(app, identifier: identifier).exists
            || matchTabElement(app, predicate: predicate).exists
    }

    private func tabElementByLabel(_ app: XCUIApplication, label: String) -> XCUIElement {
        let directQueries: [XCUIElementQuery] = [
            app.segmentedControls.buttons,
            app.tabBars.buttons,
            app.radioButtons,
            app.buttons,
            app.staticTexts
        ]

        for query in directQueries {
            let candidate = query[label]
            if candidate.exists {
                return candidate
            }
        }
        return app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    private func directTabElement(_ app: XCUIApplication, identifier: String) -> XCUIElement {
        let direct = app.buttons[identifier]
        if direct.exists {
            return direct
        }
        return app.otherElements[identifier]
    }

    private func matchTabElement(_ app: XCUIApplication, predicate: NSPredicate) -> XCUIElement {
        let queries: [XCUIElementQuery] = [
            app.tabs.matching(predicate),
            app.tabBars.buttons.matching(predicate),
            app.toolbars.buttons.matching(predicate),
            app.segmentedControls.buttons.matching(predicate),
            app.radioButtons.matching(predicate),
            app.buttons.matching(predicate),
            app.staticTexts.matching(predicate),
            app.descendants(matching: .any).matching(predicate)
        ]

        for query in queries {
            let candidate = query.firstMatch
            if candidate.exists {
                return candidate
            }
        }
        return app.descendants(matching: .any).matching(predicate).firstMatch
    }

    private func diagnosticsElement(_ app: XCUIApplication, identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_MODE"] = "1"
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
