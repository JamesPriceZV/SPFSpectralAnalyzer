import Foundation
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

/// Handles exporting Multi-Modal Analysis Reports to DOCX (local or SharePoint).
enum MultiModalExportService {

    // MARK: - Local Export

    /// Export a multi-modal report as a DOCX file to a user-chosen location.
    /// - Parameter report: The multi-modal report to export.
    /// - Returns: The URL where the file was saved, or nil if the user cancelled.
    #if os(macOS)
    @MainActor
    static func exportLocally(_ report: MultiModalReport) throws -> URL? {
        let markdown = report.toMarkdown()
        let suggestedName = report.suggestedFileName

        let panel = NSSavePanel()
        panel.title = "Save Multi-Modal Analysis Report"
        panel.nameFieldStringValue = suggestedName
        panel.allowedContentTypes = [.init(filenameExtension: "docx")!]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }

        try OOXMLWriter.writeDocx(report: markdown, to: url)

        Instrumentation.log(
            "Multi-modal report exported locally",
            area: .mlTraining, level: .info,
            details: "path=\(url.path)"
        )

        return url
    }
    #endif

    /// Export a multi-modal report to a temporary file (for programmatic use or iOS).
    /// - Parameter report: The multi-modal report to export.
    /// - Returns: The URL of the temporary DOCX file.
    static func exportToTempFile(_ report: MultiModalReport) throws -> URL {
        let markdown = report.toMarkdown()
        let tempDir = FileManager.default.temporaryDirectory
        let url = tempDir.appendingPathComponent(report.suggestedFileName)

        try OOXMLWriter.writeDocx(report: markdown, to: url)

        return url
    }

    // MARK: - SharePoint Export

    /// Upload a multi-modal report to SharePoint.
    ///
    /// - Parameters:
    ///   - report: The multi-modal report to export.
    ///   - siteId: The resolved SharePoint site ID.
    ///   - folderPath: The target folder path on SharePoint.
    ///   - token: The OAuth access token.
    ///   - onProgress: Optional progress callback (0.0 ... 1.0).
    /// - Returns: The uploaded DriveItem metadata.
    @discardableResult
    static func uploadToSharePoint(
        _ report: MultiModalReport,
        siteId: String,
        folderPath: String,
        token: String,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> GraphDriveItem {
        // Generate DOCX data via temp file
        let tempURL = try exportToTempFile(report)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let fileData = try Data(contentsOf: tempURL)
        let fileName = report.suggestedFileName

        let result = try await GraphUploadService.upload(
            fileData: fileData,
            fileName: fileName,
            siteId: siteId,
            folderPath: folderPath,
            token: token,
            session: .shared,
            onProgress: onProgress
        )

        Instrumentation.log(
            "Multi-modal report uploaded to SharePoint",
            area: .mlTraining, level: .info,
            details: "site=\(siteId) folder=\(folderPath) file=\(fileName)"
        )

        return result
    }
}
