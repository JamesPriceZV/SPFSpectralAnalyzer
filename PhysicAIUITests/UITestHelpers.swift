#if os(macOS)
import XCTest

/// Shared helpers for all UI tests in this target.
enum UITestHelpers {

    /// Creates and configures the app with UITEST_MODE enabled.
    static func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_MODE"] = "1"
        return app
    }

    /// Known auxiliary window identifiers that should be closed before
    /// interacting with the main content window.
    private static let auxiliaryWindowIDs: Set<String> = [
        "diagnostics-console", "help", "instrument-control"
    ]

    /// Launches the app and ensures its main content window is visible
    /// and in the foreground. macOS may restore auxiliary windows (e.g.
    /// Diagnostics Console) from a previous session. Floating windows
    /// can obscure the main content and intercept clicks, so this helper
    /// closes them and ensures the main window is open and focused.
    static func launchAndActivate(_ app: XCUIApplication) {
        app.launch()
        app.activate()

        // Wait for any window to appear
        _ = app.windows.firstMatch.waitForExistence(timeout: 5)

        // Close auxiliary windows that may obscure the main content
        closeAuxiliaryWindows(app)

        // Check if the main content window is present
        if hasMainContentWindow(app) {
            // Bring the main window to the front
            focusMainWindow(app)
            return
        }

        // The main window may not have opened. Try Cmd+N (WindowGroup default).
        app.typeKey("n", modifierFlags: .command)
        _ = app.windows.firstMatch.waitForExistence(timeout: 5)
        closeAuxiliaryWindows(app)

        // If Cmd+N didn't work, try activating the app again
        if !hasMainContentWindow(app) {
            app.activate()
            sleep(2)
        }
    }

    /// Closes any auxiliary windows (diagnostics console, help, etc.)
    /// that may have been restored from a previous session.
    private static func closeAuxiliaryWindows(_ app: XCUIApplication) {
        let windows = app.windows.allElementsBoundByIndex
        for window in windows {
            if auxiliaryWindowIDs.contains(window.identifier)
                || window.identifier.hasPrefix("com_apple_SwiftUI_Settings") {
                // Close by clicking the close button
                let closeBtn = window.buttons["_XCUI:CloseWindow"]
                if closeBtn.exists, closeBtn.isHittable {
                    closeBtn.click()
                    usleep(200_000)
                }
            }
        }
    }

    /// Focuses the main content window by clicking on it.
    private static func focusMainWindow(_ app: XCUIApplication) {
        let windows = app.windows.allElementsBoundByIndex
        for window in windows {
            if !auxiliaryWindowIDs.contains(window.identifier)
                && !window.identifier.hasPrefix("com_apple_SwiftUI_Settings") {
                if window.exists {
                    // Click on the window's title bar area to bring it to focus
                    window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.02)).click()
                    usleep(300_000)
                    return
                }
            }
        }
    }

    /// Checks whether the main content window (not auxiliary windows like
    /// diagnostics console) is present.
    private static func hasMainContentWindow(_ app: XCUIApplication) -> Bool {
        let windows = app.windows.allElementsBoundByIndex
        for window in windows {
            let id = window.identifier
            // Skip known auxiliary window IDs
            if auxiliaryWindowIDs.contains(id)
                || id.hasPrefix("com_apple_SwiftUI_Settings") {
                continue
            }
            // Any other window is likely the main content window
            if window.exists {
                return true
            }
        }
        return false
    }

    /// Switches to the given tab.
    /// macOS SwiftUI TabView renders tabs as radio buttons in a radio group
    /// or as a segmented control depending on macOS version. This helper
    /// tries multiple strategies to reliably find and click the tab.
    @discardableResult
    static func switchToTab(_ app: XCUIApplication, identifier: String, timeout: TimeInterval = 5) -> Bool {
        let labelMap: [String: String] = [
            "tabDataManagement": "Data Management",
            "tabAnalysis": "Analysis",
            "tabReporting": "Reporting"
        ]

        guard let label = labelMap[identifier] else { return false }

        // Wait for the window to be ready
        _ = app.windows.firstMatch.waitForExistence(timeout: timeout)

        // Strategy 1: Native TabView tab bar as a radio group ("Navigation Tab Bar")
        let radioGroup = app.radioGroups["Navigation Tab Bar"]
        if radioGroup.waitForExistence(timeout: min(timeout, 3)) {
            let groupButton = radioGroup.radioButtons[label]
            if groupButton.exists {
                groupButton.click()
                return true
            }
        }

        // Strategy 2: appModePicker as a radio group (search by both identifier and label)
        let pickerRadioGroup = app.radioGroups["appModePicker"]
        if pickerRadioGroup.exists {
            // Try by label first (more reliable for segmented pickers)
            let byLabel = pickerRadioGroup.radioButtons[label]
            if byLabel.exists {
                byLabel.click()
                return true
            }
            // Try by accessibility identifier
            let byId = pickerRadioGroup.radioButtons[identifier]
            if byId.exists {
                byId.click()
                return true
            }
        }

        // Strategy 3: appModePicker as a segmented control (macOS 15+)
        let segmented = app.segmentedControls["appModePicker"]
        if segmented.exists {
            let segButton = segmented.buttons[label]
            if segButton.exists {
                segButton.click()
                return true
            }
        }

        // Strategy 4: Any segmented control containing the label
        for seg in app.segmentedControls.allElementsBoundByIndex {
            let btn = seg.buttons[label]
            if btn.exists {
                btn.click()
                return true
            }
        }

        // Strategy 5: Toolbar buttons matching label
        let toolbarButton = app.toolbars.buttons[label]
        if toolbarButton.exists {
            toolbarButton.click()
            return true
        }

        // Strategy 6: Any button matching label in the window
        let anyButton = app.buttons[label]
        if anyButton.exists {
            anyButton.click()
            return true
        }

        // Strategy 7: descendants matching by accessibility identifier
        let descendant = app.descendants(matching: .any)[identifier]
        if descendant.waitForExistence(timeout: 2) {
            descendant.click()
            return true
        }

        // Strategy 8: descendants matching by label
        let byLabelDescendant = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@", label)
        ).firstMatch
        if byLabelDescendant.exists, byLabelDescendant.isHittable {
            byLabelDescendant.click()
            return true
        }

        return false
    }

    /// Opens Settings via keyboard shortcut or menu bar.
    /// Optionally navigates to a specific settings tab by label.
    static func openSettings(_ app: XCUIApplication, tab: String? = nil) {
        let initialWindowCount = app.windows.count

        // Try Cmd+, first
        app.typeKey(",", modifierFlags: .command)
        sleep(2)

        // Check if a new window appeared
        if app.windows.count <= initialWindowCount {
            // Fallback: use menu bar
            let appMenu = app.menuBars.menuBarItems.firstMatch
            if appMenu.exists {
                appMenu.click()
                let settingsItem = appMenu.menuItems["Settings…"]
                if settingsItem.waitForExistence(timeout: 2) {
                    settingsItem.click()
                    sleep(1)
                } else {
                    let prefsItem = appMenu.menuItems["Preferences…"]
                    if prefsItem.waitForExistence(timeout: 1) {
                        prefsItem.click()
                        sleep(1)
                    } else {
                        app.typeKey(.escape, modifierFlags: [])
                    }
                }
            }
        }

        // Navigate to the requested tab if specified
        if let tab = tab {
            let tabButton = app.radioButtons[tab]
            if tabButton.waitForExistence(timeout: 3) {
                tabButton.click()
                sleep(1)
            }
        }
    }

    /// Opens the Diagnostics Console via keyboard shortcut.
    static func openDiagnosticsConsole(_ app: XCUIApplication) {
        app.typeKey("d", modifierFlags: [.command, .shift])
        let consoleRoot = app.descendants(matching: .any)["diagnosticsConsoleRoot"]
        _ = consoleRoot.waitForExistence(timeout: 4)
    }

    /// Confirms a store-reset alert sheet if it appears.
    static func confirmStoreResetIfNeeded(_ app: XCUIApplication) {
        let resetAlert = app.sheets.firstMatch
        if resetAlert.waitForExistence(timeout: 2) {
            if resetAlert.buttons["Continue"].exists {
                resetAlert.buttons["Continue"].click()
            } else if resetAlert.buttons["OK"].exists {
                resetAlert.buttons["OK"].click()
            }
        }
    }

    /// Returns any descendant element matching the given identifier.
    static func element(_ app: XCUIApplication, identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    /// Waits for an element identified by its accessibility identifier.
    @discardableResult
    static func waitForElement(_ app: XCUIApplication, identifier: String, timeout: TimeInterval = 5) -> Bool {
        element(app, identifier: identifier).waitForExistence(timeout: timeout)
    }
}
#endif
