import SwiftUI

// MARK: - Document Type Icon

/// Shared utility for mapping file extensions to SF Symbols and accent colors.
/// Used in Enterprise File Browser, Teams file attachments, and any file listing UI.
enum DocumentTypeIcon {

    /// An SF Symbol name and its associated accent color for a file type.
    struct IconInfo: Sendable {
        let systemName: String
        let color: Color
    }

    // MARK: - Public API

    /// Returns the icon info for a given file extension (without the dot).
    static func icon(forExtension ext: String) -> IconInfo {
        switch ext.lowercased() {
        case "pdf":
            IconInfo(systemName: "doc.richtext.fill", color: .red)
        case "doc", "docx":
            IconInfo(systemName: "doc.text.fill", color: .blue)
        case "xls", "xlsx":
            IconInfo(systemName: "tablecells.fill", color: .green)
        case "csv":
            IconInfo(systemName: "tablecells", color: .green)
        case "ppt", "pptx":
            IconInfo(systemName: "play.rectangle.fill", color: .orange)
        case "txt", "rtf":
            IconInfo(systemName: "doc.plaintext", color: .secondary)
        case "jpg", "jpeg", "png", "gif", "tiff", "bmp", "heic", "webp":
            IconInfo(systemName: "photo.fill", color: .purple)
        case "zip", "gz", "tar", "rar", "7z":
            IconInfo(systemName: "doc.zipper", color: .secondary)
        case "spc", "spf", "jcamp", "dx":
            IconInfo(systemName: "waveform.path.ecg", color: .teal)
        case "mp4", "mov", "avi", "mkv":
            IconInfo(systemName: "film.fill", color: .pink)
        case "mp3", "wav", "m4a", "aac":
            IconInfo(systemName: "waveform", color: .indigo)
        case "html", "htm":
            IconInfo(systemName: "globe", color: .blue)
        case "json", "xml", "yaml", "yml":
            IconInfo(systemName: "curlybraces", color: .orange)
        case "swift", "py", "js", "ts", "c", "cpp", "h":
            IconInfo(systemName: "chevron.left.forwardslash.chevron.right", color: .cyan)
        default:
            IconInfo(systemName: "doc", color: .secondary)
        }
    }

    /// Returns icon info for a `GraphDriveItem`.
    static func icon(for item: GraphDriveItem) -> IconInfo {
        if item.isFolder {
            return IconInfo(systemName: "folder.fill", color: .blue)
        }
        return icon(forFilename: item.name)
    }

    /// Returns icon info for a filename string (extracts the extension).
    static func icon(forFilename filename: String) -> IconInfo {
        let ext = (filename as NSString).pathExtension
        return icon(forExtension: ext)
    }
}
