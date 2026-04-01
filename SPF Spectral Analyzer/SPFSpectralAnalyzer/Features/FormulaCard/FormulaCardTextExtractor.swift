import Foundation
import PDFKit
import Vision
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Extracts readable text from formula card file data (PDF, image, xlsx, docx).
/// Stateless service following the project's `enum` service pattern.
enum FormulaCardTextExtractor {

    enum ExtractionError: Error, LocalizedError {
        case unsupportedFileType(String)
        case noTextFound
        case extractionFailed(String)

        var errorDescription: String? {
            switch self {
            case .unsupportedFileType(let type): return "Unsupported file type: \(type)"
            case .noTextFound: return "No text could be extracted from the document"
            case .extractionFailed(let detail): return "Extraction failed: \(detail)"
            }
        }
    }

    /// Extract readable text from formula card file data.
    /// - Parameters:
    ///   - data: Raw file bytes
    ///   - fileType: File extension (e.g. "pdf", "xlsx", "docx", "jpeg", "png", "heic")
    /// - Returns: Extracted text suitable for AI parsing
    static func extractText(from data: Data, fileType: String) async throws -> String {
        let normalizedType = fileType.lowercased()

        switch normalizedType {
        case "pdf":
            return try extractFromPDF(data: data)
        case "xlsx":
            return try extractFromXLSX(data: data)
        case "docx":
            return try extractFromDOCX(data: data)
        case "jpeg", "jpg", "png", "heic", "tiff", "tif":
            return try await extractFromImage(data: data)
        default:
            throw ExtractionError.unsupportedFileType(normalizedType)
        }
    }

    // MARK: - PDF Extraction

    private static func extractFromPDF(data: Data) throws -> String {
        guard let document = PDFDocument(data: data) else {
            throw ExtractionError.extractionFailed("Could not create PDF document")
        }

        var pages: [String] = []
        for i in 0..<document.pageCount {
            if let page = document.page(at: i), let text = page.string {
                pages.append(text)
            }
        }

        let result = pages.joined(separator: "\n\n")
        guard !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ExtractionError.noTextFound
        }
        return result
    }

    // MARK: - Image OCR Extraction

    private static func extractFromImage(data: Data) async throws -> String {
        #if canImport(UIKit)
        guard let image = UIImage(data: data), let cgImage = image.cgImage else {
            throw ExtractionError.extractionFailed("Could not create image from data")
        }
        #elseif canImport(AppKit)
        guard let image = NSImage(data: data),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw ExtractionError.extractionFailed("Could not create image from data")
        }
        #endif

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: ExtractionError.extractionFailed(error.localizedDescription))
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(throwing: ExtractionError.noTextFound)
                    return
                }

                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                let result = lines.joined(separator: "\n")

                if result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    continuation.resume(throwing: ExtractionError.noTextFound)
                } else {
                    continuation.resume(returning: result)
                }
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: ExtractionError.extractionFailed(error.localizedDescription))
            }
        }
    }

    // MARK: - XLSX Extraction (ZIP → XML parsing)

    private static func extractFromXLSX(data: Data) throws -> String {
        // XLSX files are ZIP archives containing XML files.
        // We extract xl/sharedStrings.xml for string values and xl/worksheets/sheet1.xml for cell layout.
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let zipURL = tempDir.appendingPathComponent("file.xlsx")
        try data.write(to: zipURL)

        // Use Process (macOS) or manual extraction
        let extractDir = tempDir.appendingPathComponent("extracted")
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)

        #if os(macOS)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", "-q", zipURL.path, "-d", extractDir.path]
        try process.run()
        process.waitUntilExit()
        return try parseXLSXContent(at: extractDir)
        #else
        // On iOS, use Archive from Foundation (available in Apple Archive)
        // Fall back to treating the raw data as text if unzip is unavailable
        return try extractXLSXUsingFoundation(data: data, extractDir: extractDir)
        #endif
    }

    #if os(iOS) || os(visionOS)
    private static func extractXLSXUsingFoundation(data: Data, extractDir: URL) throws -> String {
        // iOS fallback: use minizip-compatible approach via FileManager
        // For now, attempt to read with a basic ZIP header scan
        // This is a simplified approach; full ZIP parsing would need a library
        throw ExtractionError.extractionFailed("XLSX extraction on iOS requires the file to be opened in a spreadsheet app first. Please export as PDF or take a photo instead.")
    }
    #endif

    private static func parseXLSXContent(at extractDir: URL) throws -> String {
        var lines: [String] = []

        // Parse shared strings (cell string values are referenced by index)
        var sharedStrings: [String] = []
        let sharedStringsURL = extractDir.appendingPathComponent("xl/sharedStrings.xml")
        if let sharedData = try? Data(contentsOf: sharedStringsURL),
           let xmlString = String(data: sharedData, encoding: .utf8) {
            sharedStrings = parseSharedStrings(from: xmlString)
        }

        // Parse sheet1 (primary worksheet)
        let sheet1URL = extractDir.appendingPathComponent("xl/worksheets/sheet1.xml")
        if let sheetData = try? Data(contentsOf: sheet1URL),
           let xmlString = String(data: sheetData, encoding: .utf8) {
            lines = parseWorksheet(from: xmlString, sharedStrings: sharedStrings)
        }

        let result = lines.joined(separator: "\n")
        guard !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ExtractionError.noTextFound
        }
        return result
    }

    /// Parse <si><t>...</t></si> elements from sharedStrings.xml
    private static func parseSharedStrings(from xml: String) -> [String] {
        var strings: [String] = []
        var scanner = xml[xml.startIndex...]

        while let siStart = scanner.range(of: "<si>") {
            guard let siEnd = scanner.range(of: "</si>") else { break }
            let siContent = scanner[siStart.upperBound..<siEnd.lowerBound]

            // Extract all <t> elements within this <si> (handles rich text with multiple <r><t> blocks)
            var cellText = ""
            var tScanner = siContent[siContent.startIndex...]
            while let tStart = tScanner.range(of: "<t") {
                // Skip attributes like <t xml:space="preserve">
                guard let tagClose = tScanner[tStart.upperBound...].range(of: ">") else { break }
                guard let tEnd = tScanner[tagClose.upperBound...].range(of: "</t>") else { break }
                cellText += String(tScanner[tagClose.upperBound..<tEnd.lowerBound])
                tScanner = tScanner[tEnd.upperBound...]
            }
            strings.append(cellText)
            scanner = scanner[siEnd.upperBound...]
        }
        return strings
    }

    /// Parse cell values from worksheet XML, producing tab-separated rows.
    private static func parseWorksheet(from xml: String, sharedStrings: [String]) -> [String] {
        var rows: [String] = []
        var scanner = xml[xml.startIndex...]

        while let rowStart = scanner.range(of: "<row") {
            guard let rowEnd = scanner[rowStart.upperBound...].range(of: "</row>") else { break }
            let rowContent = String(scanner[rowStart.upperBound..<rowEnd.lowerBound])

            var cells: [String] = []
            var cellScanner = rowContent[rowContent.startIndex...]

            while let cStart = cellScanner.range(of: "<c ") {
                let isSharedString = cellScanner[cStart.upperBound...].prefix(200).contains("t=\"s\"")

                guard let vStart = cellScanner[cStart.upperBound...].range(of: "<v>"),
                      let vEnd = cellScanner[vStart.upperBound...].range(of: "</v>") else {
                    // Cell with no <v> value — skip
                    if let nextC = cellScanner[cStart.upperBound...].range(of: "<c ") {
                        cellScanner = cellScanner[nextC.lowerBound...]
                    } else {
                        break
                    }
                    continue
                }

                let value = String(cellScanner[vStart.upperBound..<vEnd.lowerBound])

                if isSharedString, let index = Int(value), index < sharedStrings.count {
                    cells.append(sharedStrings[index])
                } else {
                    cells.append(value)
                }

                cellScanner = cellScanner[vEnd.upperBound...]
            }

            if !cells.isEmpty {
                rows.append(cells.joined(separator: "\t"))
            }
            scanner = scanner[rowEnd.upperBound...]
        }
        return rows
    }

    // MARK: - DOCX Extraction (ZIP → XML parsing)

    private static func extractFromDOCX(data: Data) throws -> String {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let zipURL = tempDir.appendingPathComponent("file.docx")
        try data.write(to: zipURL)

        let extractDir = tempDir.appendingPathComponent("extracted")
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)

        #if os(macOS)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", "-q", zipURL.path, "-d", extractDir.path]
        try process.run()
        process.waitUntilExit()

        let documentURL = extractDir.appendingPathComponent("word/document.xml")
        guard let docData = try? Data(contentsOf: documentURL),
              let xmlString = String(data: docData, encoding: .utf8) else {
            throw ExtractionError.noTextFound
        }

        // Extract text from <w:t> elements, treating <w:p> as paragraph breaks
        let text = parseDocxContent(from: xmlString)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ExtractionError.noTextFound
        }
        return text
        #else
        throw ExtractionError.extractionFailed("DOCX extraction on iOS requires the file to be exported as PDF or photo first.")
        #endif
    }

    /// Parse text content from Word document.xml, extracting <w:t> elements.
    private static func parseDocxContent(from xml: String) -> String {
        var paragraphs: [String] = []
        var scanner = xml[xml.startIndex...]

        while let pStart = scanner.range(of: "<w:p") {
            let pEndTag: Range<Substring.Index>
            if let selfClose = scanner[pStart.upperBound...].range(of: "/>"),
               let fullClose = scanner[pStart.upperBound...].range(of: "</w:p>") {
                pEndTag = selfClose.lowerBound < fullClose.lowerBound ? selfClose : fullClose
            } else if let fullClose = scanner[pStart.upperBound...].range(of: "</w:p>") {
                pEndTag = fullClose
            } else {
                break
            }

            let paraContent = scanner[pStart.upperBound..<pEndTag.lowerBound]

            // Extract all <w:t> text runs
            var paraText = ""
            var tScanner = paraContent[paraContent.startIndex...]
            while let tStart = tScanner.range(of: "<w:t") {
                guard let tagClose = tScanner[tStart.upperBound...].range(of: ">") else { break }
                guard let tEnd = tScanner[tagClose.upperBound...].range(of: "</w:t>") else { break }
                paraText += String(tScanner[tagClose.upperBound..<tEnd.lowerBound])
                tScanner = tScanner[tEnd.upperBound...]
            }

            if !paraText.isEmpty {
                paragraphs.append(paraText)
            }

            scanner = scanner[pEndTag.upperBound...]
        }

        return paragraphs.joined(separator: "\n")
    }
}
