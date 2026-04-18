import SwiftUI

extension Color {
    /// Platform-adaptive background color.
    /// macOS: `.windowBackgroundColor` — iOS: `.systemBackground`
    static var platformBackground: Color {
        #if canImport(AppKit)
        Color(.windowBackgroundColor)
        #elseif canImport(UIKit)
        Color(.systemBackground)
        #endif
    }

    /// Platform-adaptive secondary background color.
    /// macOS: `.controlBackgroundColor` — iOS: `.secondarySystemBackground`
    static var platformSecondaryBackground: Color {
        #if canImport(AppKit)
        Color(.controlBackgroundColor)
        #elseif canImport(UIKit)
        Color(.secondarySystemBackground)
        #endif
    }
}
