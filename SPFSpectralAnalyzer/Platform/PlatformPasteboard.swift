import Foundation

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Cross-platform clipboard abstraction.
/// Replaces direct NSPasteboard / UIPasteboard usage throughout the app.
enum PlatformPasteboard {
    /// Copies a string to the system pasteboard.
    static func copyString(_ text: String) {
        #if canImport(AppKit)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        #elseif canImport(UIKit)
        UIPasteboard.general.string = text
        #endif
    }

    /// Copies data with a specified UTI to the system pasteboard.
    static func copyData(_ data: Data, type: String) {
        #if canImport(AppKit)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(data, forType: NSPasteboard.PasteboardType(type))
        #elseif canImport(UIKit)
        UIPasteboard.general.setData(data, forPasteboardType: type)
        #endif
    }
}
