import Foundation
import PDFKit
import Vision
import Compression
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
        let entries = try ZIPReader.extractEntries(from: data, matching: [
            "xl/sharedStrings.xml",
            "xl/worksheets/sheet1.xml"
        ])
        return try parseXLSXContentFromEntries(entries)
    }

    private static func parseXLSXContentFromEntries(_ entries: [String: Data]) throws -> String {
        var lines: [String] = []

        // Parse shared strings (cell string values are referenced by index)
        var sharedStrings: [String] = []
        if let sharedData = entries["xl/sharedStrings.xml"],
           let xmlString = String(data: sharedData, encoding: .utf8) {
            sharedStrings = parseSharedStrings(from: xmlString)
        }

        // Parse sheet1 (primary worksheet)
        if let sheetData = entries["xl/worksheets/sheet1.xml"],
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
        let entries = try ZIPReader.extractEntries(from: data, matching: ["word/document.xml"])

        guard let docData = entries["word/document.xml"],
              let xmlString = String(data: docData, encoding: .utf8) else {
            throw ExtractionError.noTextFound
        }

        // Extract text from <w:t> elements, treating <w:p> as paragraph breaks
        let text = parseDocxContent(from: xmlString)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ExtractionError.noTextFound
        }
        return text
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

// MARK: - Minimal ZIP Reader (Cross-Platform)

/// Pure-Swift ZIP reader that extracts specific files from a ZIP archive.
/// Uses the Compression framework for deflate decompression (no external dependencies).
/// Supports both Stored (method 0) and Deflated (method 8) entries.
private enum ZIPReader {

    enum ZIPError: Error, LocalizedError {
        case invalidArchive
        case entryNotFound(String)
        case decompressionFailed(String)
        case unsupportedCompression(UInt16)

        var errorDescription: String? {
            switch self {
            case .invalidArchive: return "Not a valid ZIP archive"
            case .entryNotFound(let name): return "Entry not found in archive: \(name)"
            case .decompressionFailed(let name): return "Failed to decompress: \(name)"
            case .unsupportedCompression(let method): return "Unsupported compression method: \(method)"
            }
        }
    }

    /// Extract specific named entries from a ZIP archive.
    /// - Parameters:
    ///   - data: Raw ZIP file bytes.
    ///   - matching: File paths within the archive to extract (e.g. "xl/sharedStrings.xml").
    /// - Returns: Dictionary mapping matched file paths to their decompressed data.
    static func extractEntries(from data: Data, matching paths: Set<String>) throws -> [String: Data] {
        guard data.count > 22 else { throw ZIPError.invalidArchive }

        // Find the End of Central Directory record (search backwards for signature 0x06054b50)
        let eocdSignature: [UInt8] = [0x50, 0x4B, 0x05, 0x06]
        var eocdOffset = -1
        let bytes = [UInt8](data)
        let searchStart = max(0, bytes.count - 65557) // max comment size is 65535
        for i in stride(from: bytes.count - 4, through: searchStart, by: -1) {
            if bytes[i] == eocdSignature[0] && bytes[i+1] == eocdSignature[1] &&
               bytes[i+2] == eocdSignature[2] && bytes[i+3] == eocdSignature[3] {
                eocdOffset = i
                break
            }
        }
        guard eocdOffset >= 0, eocdOffset + 22 <= bytes.count else {
            throw ZIPError.invalidArchive
        }

        // Parse EOCD to find central directory
        let cdEntryCount = readUInt16(bytes, at: eocdOffset + 10)
        let cdOffset = Int(readUInt32(bytes, at: eocdOffset + 16))

        guard cdOffset >= 0, cdOffset < bytes.count else {
            throw ZIPError.invalidArchive
        }

        // Walk central directory entries
        var results: [String: Data] = [:]
        var offset = cdOffset
        let remaining = paths

        for _ in 0..<cdEntryCount {
            guard offset + 46 <= bytes.count else { break }
            // Central directory file header signature: 0x02014b50
            guard bytes[offset] == 0x50, bytes[offset+1] == 0x4B,
                  bytes[offset+2] == 0x01, bytes[offset+3] == 0x02 else { break }

            let compressionMethod = readUInt16(bytes, at: offset + 10)
            let compressedSize = Int(readUInt32(bytes, at: offset + 20))
            let uncompressedSize = Int(readUInt32(bytes, at: offset + 24))
            let fileNameLength = Int(readUInt16(bytes, at: offset + 28))
            let extraFieldLength = Int(readUInt16(bytes, at: offset + 30))
            let commentLength = Int(readUInt16(bytes, at: offset + 32))
            let localHeaderOffset = Int(readUInt32(bytes, at: offset + 42))

            guard offset + 46 + fileNameLength <= bytes.count else { break }
            let fileNameBytes = Array(bytes[(offset + 46)..<(offset + 46 + fileNameLength)])
            let fileName = String(bytes: fileNameBytes, encoding: .utf8) ?? ""

            // Move to next central directory entry
            offset += 46 + fileNameLength + extraFieldLength + commentLength

            guard remaining.contains(fileName) else { continue }

            // Read from local file header to get actual data offset
            guard localHeaderOffset + 30 <= bytes.count else { continue }
            guard bytes[localHeaderOffset] == 0x50, bytes[localHeaderOffset+1] == 0x4B,
                  bytes[localHeaderOffset+2] == 0x03, bytes[localHeaderOffset+3] == 0x04 else { continue }

            let localNameLength = Int(readUInt16(bytes, at: localHeaderOffset + 26))
            let localExtraLength = Int(readUInt16(bytes, at: localHeaderOffset + 28))
            let dataStart = localHeaderOffset + 30 + localNameLength + localExtraLength

            guard dataStart + compressedSize <= bytes.count else { continue }
            let compressedData = Data(bytes[dataStart..<(dataStart + compressedSize)])

            switch compressionMethod {
            case 0: // Stored
                results[fileName] = compressedData
            case 8: // Deflated
                if let decompressed = inflateData(compressedData, expectedSize: uncompressedSize) {
                    results[fileName] = decompressed
                } else {
                    throw ZIPError.decompressionFailed(fileName)
                }
            default:
                throw ZIPError.unsupportedCompression(compressionMethod)
            }

            // Early exit if we found all requested entries
            if results.count == remaining.count { break }
        }

        return results
    }

    // MARK: - Helpers

    private static func readUInt16(_ bytes: [UInt8], at offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }

    private static func readUInt32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        UInt32(bytes[offset]) |
        (UInt32(bytes[offset + 1]) << 8) |
        (UInt32(bytes[offset + 2]) << 16) |
        (UInt32(bytes[offset + 3]) << 24)
    }

    /// Decompress deflated data using the Compression framework (raw DEFLATE, no zlib header).
    private static func inflateData(_ compressedData: Data, expectedSize: Int) -> Data? {
        // Allocate output buffer — use expectedSize if reasonable, otherwise cap at 10 MB
        let outputSize = min(max(expectedSize, compressedData.count * 4), 10_485_760)
        let outputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: outputSize)
        defer { outputBuffer.deallocate() }

        let decompressedSize = compressedData.withUnsafeBytes { rawBuffer -> Int in
            guard let baseAddress = rawBuffer.baseAddress else { return 0 }
            return compression_decode_buffer(
                outputBuffer,
                outputSize,
                baseAddress.assumingMemoryBound(to: UInt8.self),
                compressedData.count,
                nil,
                COMPRESSION_ZLIB
            )
        }

        guard decompressedSize > 0 else { return nil }
        return Data(bytes: outputBuffer, count: decompressedSize)
    }
}
