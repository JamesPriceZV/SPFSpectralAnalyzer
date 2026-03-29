import SwiftUI

/// Describes the content types that can be shared from the app.
enum ShareableContent: Identifiable, Sendable {
    case text(String)
    case chartImage(Image, title: String)
    case pdfData(Data, filename: String)

    var id: String {
        switch self {
        case .text(let t): return "text-\(t.prefix(20).hashValue)"
        case .chartImage(_, let title): return "image-\(title)"
        case .pdfData(_, let filename): return "pdf-\(filename)"
        }
    }

    /// Returns the items suitable for the system share sheet.
    var shareItems: [Any] {
        switch self {
        case .text(let text):
            return [text]
        case .chartImage(_, let title):
            // The actual UIImage/NSImage must be resolved by the caller
            return [title]
        case .pdfData(let data, let filename):
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            try? data.write(to: tempURL)
            return [tempURL]
        }
    }
}
