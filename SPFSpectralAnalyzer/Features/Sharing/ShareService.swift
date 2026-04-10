import SwiftUI

/// Describes the content types that can be shared from the app.
enum ShareableContent: Identifiable, Sendable {
    case text(String)
    case chartImage(Image, title: String)
    case pdfData(Data, filename: String)
    case dataPackage(Data, filename: String)
    case viewScreenshot(PlatformImage, title: String)

    var id: String {
        switch self {
        case .text(let t): return "text-\(t.prefix(20).hashValue)"
        case .chartImage(_, let title): return "image-\(title)"
        case .pdfData(_, let filename): return "pdf-\(filename)"
        case .dataPackage(_, let filename): return "package-\(filename)"
        case .viewScreenshot(_, let title): return "screenshot-\(title)"
        }
    }

    /// Returns the items suitable for the system share sheet.
    @MainActor
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
        case .dataPackage(let data, let filename):
            let sanitized = filename.replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: ":", with: "-")
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(sanitized)
                .appendingPathExtension(DataAnalysisPackage.fileExtension)
            try? data.write(to: tempURL)
            return [tempURL]
        case .viewScreenshot(let image, _):
            return [image]
        }
    }
}
