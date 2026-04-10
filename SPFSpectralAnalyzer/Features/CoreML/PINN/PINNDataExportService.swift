import Compression
import Foundation
import SwiftData

/// Exports and imports training data for PINN models.
/// Follows the stateless enum service pattern used throughout the project.
enum PINNDataExportService {

    // MARK: - Types

    /// A single training data entry containing spectral data and a known target value.
    struct TrainingDataEntry: Codable, Sendable {
        let datasetID: String
        let datasetName: String
        let wavelengths: [Double]
        let intensities: [Double]
        let knownValue: Double
        let plateType: String?
        let applicationQuantityMg: Double?
        let formulationType: String?
    }

    /// Container for exported training data with metadata.
    struct TrainingDataExport: Codable, Sendable {
        let domain: String
        let exportDate: Date
        let entryCount: Int
        let entries: [TrainingDataEntry]
    }

    // MARK: - Export

    /// Export reference datasets matching a domain's SPC type codes to JSON.
    ///
    /// **How it works (for beginners):**
    /// 1. Finds all datasets you've marked as "reference" with a known target value (e.g., in-vivo SPF)
    /// 2. For each dataset, reads the first valid spectrum's wavelengths and intensities
    /// 3. Packages everything into a JSON file the Python training script can read
    ///
    /// - Parameters:
    ///   - domain: The PINN domain to export data for
    ///   - modelContext: The SwiftData model context to query
    /// - Returns: JSON data ready for the training script
    @MainActor
    static func exportReferenceData(
        for domain: PINNDomain,
        modelContext: ModelContext
    ) throws -> Data {
        let descriptor = FetchDescriptor<StoredDataset>()
        let allDatasets = try modelContext.fetch(descriptor)

        // Filter to reference datasets with known target values
        let referenceDatasets = allDatasets.filter { dataset in
            dataset.datasetRole == DatasetRole.reference.rawValue
            && dataset.knownInVivoSPF != nil
        }

        // Build training entries from valid spectra
        var entries: [TrainingDataEntry] = []
        for dataset in referenceDatasets {
            guard let spf = dataset.knownInVivoSPF else { continue }

            // Use the first valid spectrum
            let validSpectra = dataset.spectraItems.filter { !$0.isInvalid }
            guard let spectrum = validSpectra.first else { continue }

            let xVals = spectrum.xValues
            let yVals = spectrum.yValues
            guard !xVals.isEmpty, xVals.count == yVals.count else { continue }

            entries.append(TrainingDataEntry(
                datasetID: dataset.id.uuidString,
                datasetName: dataset.fileName,
                wavelengths: xVals,
                intensities: yVals,
                knownValue: spf,
                plateType: dataset.plateType,
                applicationQuantityMg: dataset.applicationQuantityMg,
                formulationType: dataset.formulationType
            ))
        }

        let export = TrainingDataExport(
            domain: domain.rawValue,
            exportDate: Date(),
            entryCount: entries.count,
            entries: entries
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(export)
    }

    /// Save exported data to the PINN TrainingData directory.
    ///
    /// - Parameters:
    ///   - data: The JSON data to save
    ///   - domain: The PINN domain this data is for
    /// - Returns: The URL of the saved file
    @discardableResult
    static func saveToTrainingDirectory(data: Data, domain: PINNDomain) throws -> URL {
        let dir = PINNTrainingManager.trainingDataDirectory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let filename = "\(domain.rawValue.lowercased().replacingOccurrences(of: " ", with: "_"))_training_data.json"
        let fileURL = dir.appendingPathComponent(filename)
        try data.write(to: fileURL)

        Instrumentation.log(
            "Training data exported for \(domain.displayName)",
            area: .mlTraining, level: .info,
            details: "path=\(fileURL.path) bytes=\(data.count)"
        )

        return fileURL
    }

    // MARK: - Gather All Available Training Data

    /// Gathers training data from ALL available sources for a domain:
    /// 1. SwiftData reference datasets (marked with known target values)
    /// 2. Downloaded JSON/CSV files in the domain's Downloads directory
    /// 3. Previously imported files in the TrainingData directory
    ///
    /// Skips HTML files and files that fail to parse.
    /// Returns the merged entries ready for the Python training script.
    @MainActor
    static func gatherAllTrainingData(
        for domain: PINNDomain,
        modelContext: ModelContext
    ) -> (entries: [TrainingDataEntry], sources: [String]) {
        var allEntries: [TrainingDataEntry] = []
        var sources: [String] = []

        // 1. SwiftData reference datasets
        if let refData = try? exportReferenceData(for: domain, modelContext: modelContext),
           let container = try? JSONDecoder().decode(TrainingDataExport.self, from: refData),
           !container.entries.isEmpty {
            allEntries.append(contentsOf: container.entries)
            sources.append("\(container.entries.count) reference datasets from library")
        }

        // 2. Downloaded files in domain's Downloads directory
        let supportedExtensions: Set<String> = ["json", "csv", "jdx", "dx", "jcamp", "sdf", "sd", "txt", "msp", "mgf", "xy", "tsv", "gz"]
        let downloadedFiles = TrainingDataDownloader.downloadedFiles(for: domain)
        for file in downloadedFiles {
            // Skip metadata files
            if file.lastPathComponent.hasPrefix("_") { continue }
            let ext = file.pathExtension.lowercased()
            guard supportedExtensions.contains(ext) else { continue }
            do {
                let entries = try importTrainingData(from: file, domain: domain)
                if !entries.isEmpty {
                    allEntries.append(contentsOf: entries)
                    sources.append("\(entries.count) entries from \(file.lastPathComponent)")
                }
            } catch {
                // Skip files that can't be parsed (HTML pages, corrupt files, etc.)
                continue
            }
        }

        // 3. Previously imported files in TrainingData root directory
        let trainingDir = PINNTrainingManager.trainingDataDirectory
        let domainPrefix = domain.rawValue.lowercased().replacingOccurrences(of: " ", with: "_")
        if let rootFiles = try? FileManager.default.contentsOfDirectory(
            at: trainingDir, includingPropertiesForKeys: nil
        ) {
            for file in rootFiles {
                let name = file.lastPathComponent.lowercased()
                // Only read domain-specific imported files (not the export we'll create)
                guard name.contains(domainPrefix),
                      name.contains("imported"),
                      (name.hasSuffix(".json") || name.hasSuffix(".csv")) else { continue }
                do {
                    let entries = try importTrainingData(from: file, domain: domain)
                    if !entries.isEmpty {
                        allEntries.append(contentsOf: entries)
                        sources.append("\(entries.count) entries from \(file.lastPathComponent)")
                    }
                } catch {
                    continue
                }
            }
        }

        return (entries: allEntries, sources: sources)
    }

    // MARK: - Import

    /// Import external training data from a JSON or CSV file.
    ///
    /// **Supported formats:**
    /// - **JSON**: Array of `TrainingDataEntry` objects, or a `TrainingDataExport` container
    /// - **CSV**: Columns with headers. First column = known_value, remaining = wavelength intensities
    ///
    /// - Parameters:
    ///   - url: The file URL to import from
    ///   - domain: The PINN domain this data belongs to
    /// - Returns: Parsed training data entries
    static func importTrainingData(from url: URL, domain: PINNDomain) throws -> [TrainingDataEntry] {
        var data = try Data(contentsOf: url)
        var ext = url.pathExtension.lowercased()

        // Handle gzipped files
        if ext == "gz" {
            data = try decompressGzip(data)
            // Determine the inner extension (e.g., "file.csv.gz" → "csv")
            let stem = url.deletingPathExtension().pathExtension.lowercased()
            if !stem.isEmpty { ext = stem }
        }

        // Reject HTML masquerading as data — check first 512 bytes
        if let prefix = String(data: data.prefix(512), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) {
            if prefix.hasPrefix("<!") || prefix.hasPrefix("<html") || prefix.hasPrefix("<HTML")
                || prefix.lowercased().contains("<!doctype") || prefix.lowercased().contains("<head>") {
                throw PINNDataImportError.htmlNotJSON
            }
        }

        switch ext {
        case "json":
            return try importJSON(data: data)
        case "csv", "tsv":
            return try importCSV(data: data, domain: domain, separator: ext == "tsv" ? "\t" : ",")
        case "jdx", "dx", "jcamp":
            return try importJCAMPDX(data: data, domain: domain)
        case "sdf", "sd":
            return try importSDF(data: data, domain: domain)
        case "txt", "xy":
            return try importXYText(data: data, domain: domain)
        case "msp":
            return try importMSP(data: data, domain: domain)
        default:
            throw PINNDataImportError.unsupportedFormat(ext)
        }
    }

    /// Attempt gzip decompression. Returns original data if not actually gzipped.
    private static func decompressGzip(_ data: Data) throws -> Data {
        // Check gzip magic number (0x1F 0x8B)
        guard data.count >= 2, data[data.startIndex] == 0x1F, data[data.startIndex + 1] == 0x8B else {
            return data // Not gzipped, return as-is
        }
        // Use NSData's built-in decompression
        let nsData = data as NSData
        // Try using the compression framework
        guard let decompressed = try? (nsData as Data).gunzipped() else {
            throw PINNDataImportError.decompressionFailed
        }
        return decompressed
    }

    /// Copy an imported file to the TrainingData directory for Python script access.
    static func copyToTrainingDirectory(from sourceURL: URL, domain: PINNDomain) throws -> URL {
        let dir = PINNTrainingManager.trainingDataDirectory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let destFilename = "\(domain.rawValue.lowercased().replacingOccurrences(of: " ", with: "_"))_imported.\(sourceURL.pathExtension)"
        let destURL = dir.appendingPathComponent(destFilename)

        if FileManager.default.fileExists(atPath: destURL.path) {
            try FileManager.default.removeItem(at: destURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destURL)

        Instrumentation.log(
            "Training data imported for \(domain.displayName)",
            area: .mlTraining, level: .info,
            details: "source=\(sourceURL.lastPathComponent) dest=\(destURL.path)"
        )

        return destURL
    }

    // MARK: - Private Import Helpers

    private static func importJSON(data: Data) throws -> [TrainingDataEntry] {
        // Detect HTML masquerading as JSON (downloaded landing pages from data sources)
        if let prefix = String(data: data.prefix(512), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           prefix.hasPrefix("<!") || prefix.hasPrefix("<html") || prefix.hasPrefix("<HTML") || prefix.lowercased().contains("<!doctype") {
            throw PINNDataImportError.htmlNotJSON
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // Try container format first (exported from this app)
        if let container = try? decoder.decode(TrainingDataExport.self, from: data) {
            return container.entries
        }

        // Try array format
        if let entries = try? decoder.decode([TrainingDataEntry].self, from: data) {
            return entries
        }

        throw PINNDataImportError.invalidJSON
    }

    private static func importCSV(data: Data, domain: PINNDomain, separator: String = ",") throws -> [TrainingDataEntry] {
        guard let csvString = String(data: data, encoding: .utf8) else {
            throw PINNDataImportError.invalidEncoding
        }

        let lines = csvString.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard lines.count >= 2 else {
            throw PINNDataImportError.tooFewRows
        }

        // First line is header
        let headers = lines[0].components(separatedBy: separator).map { $0.trimmingCharacters(in: .whitespaces).lowercased() }

        // Find known_value column (first column or explicitly named)
        let valueIndex = headers.firstIndex(of: "known_value") ?? headers.firstIndex(of: "target") ?? headers.firstIndex(of: "spf") ?? 0

        var entries: [TrainingDataEntry] = []
        for i in 1..<lines.count {
            let values = lines[i].components(separatedBy: separator).map { $0.trimmingCharacters(in: .whitespaces) }
            guard values.count == headers.count else { continue }

            guard let knownValue = Double(values[valueIndex]) else { continue }

            // All other numeric columns are intensities
            var intensities: [Double] = []
            for (j, val) in values.enumerated() where j != valueIndex {
                if let d = Double(val) {
                    intensities.append(d)
                }
            }
            guard !intensities.isEmpty else { continue }

            // Generate wavelength array based on column count (assumes evenly spaced)
            let wavelengths = (0..<intensities.count).map { Double($0) }

            entries.append(TrainingDataEntry(
                datasetID: UUID().uuidString,
                datasetName: "CSV row \(i)",
                wavelengths: wavelengths,
                intensities: intensities,
                knownValue: knownValue,
                plateType: nil,
                applicationQuantityMg: nil,
                formulationType: nil
            ))
        }

        guard !entries.isEmpty else {
            throw PINNDataImportError.noValidRows
        }

        return entries
    }

    // MARK: - JCAMP-DX Parser

    /// Parses JCAMP-DX spectral data (.jdx, .dx, .jcamp).
    /// JCAMP-DX uses labeled data records: ##XYDATA=(X++(Y..Y)), ##PEAK TABLE, etc.
    private static func importJCAMPDX(data: Data, domain: PINNDomain) throws -> [TrainingDataEntry] {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else {
            throw PINNDataImportError.invalidEncoding
        }

        // JCAMP-DX files must start with ##TITLE= or ##JCAMP-DX=
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("##") else {
            throw PINNDataImportError.invalidJCAMP
        }

        var xValues: [Double] = []
        var yValues: [Double] = []
        var title = "JCAMP spectrum"
        var inXYData = false
        var xFactor = 1.0
        var yFactor = 1.0

        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            let stripped = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if stripped.isEmpty { continue }

            // Parse labeled data records
            if stripped.hasPrefix("##") {
                let upper = stripped.uppercased()
                if upper.hasPrefix("##TITLE=") {
                    title = String(stripped.dropFirst(8)).trimmingCharacters(in: .whitespaces)
                } else if upper.hasPrefix("##XFACTOR=") {
                    xFactor = Double(String(stripped.dropFirst(10)).trimmingCharacters(in: .whitespaces)) ?? 1.0
                } else if upper.hasPrefix("##YFACTOR=") {
                    yFactor = Double(String(stripped.dropFirst(10)).trimmingCharacters(in: .whitespaces)) ?? 1.0
                } else if upper.contains("XYDATA") || upper.contains("PEAK TABLE") || upper.contains("XYPOINTS") {
                    inXYData = true
                } else if upper.hasPrefix("##END") {
                    inXYData = false
                } else {
                    // Other ## labels end the data block
                    if inXYData && !upper.hasPrefix("##") { /* keep parsing */ }
                    else { inXYData = false }
                }
                // Don't parse ## lines as data
                if stripped.hasPrefix("##") { continue }
            }

            // Parse data lines
            if inXYData {
                // Split on whitespace, commas, or semicolons
                let tokens = stripped.components(separatedBy: CharacterSet(charactersIn: " \t,;"))
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }

                guard tokens.count >= 2, let x = Double(tokens[0]) else { continue }

                // First token is X, rest are Y values (packed format)
                let scaledX = x * xFactor
                for i in 1..<tokens.count {
                    if let y = Double(tokens[i]) {
                        xValues.append(scaledX + Double(i - 1))
                        yValues.append(y * yFactor)
                    }
                }
            }
        }

        guard !xValues.isEmpty else {
            throw PINNDataImportError.noValidRows
        }

        // Each JCAMP file is one spectrum → one training entry
        // Use a placeholder knownValue of 0 (user must assign targets later)
        let entry = TrainingDataEntry(
            datasetID: UUID().uuidString,
            datasetName: title,
            wavelengths: xValues,
            intensities: yValues,
            knownValue: 0.0,
            plateType: nil,
            applicationQuantityMg: nil,
            formulationType: nil
        )
        return [entry]
    }

    // MARK: - SDF/SD Parser

    /// Parses SDF (Structure-Data File) records commonly used by chemical databases.
    /// Each record contains molecule data and associated properties.
    private static func importSDF(data: Data, domain: PINNDomain) throws -> [TrainingDataEntry] {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else {
            throw PINNDataImportError.invalidEncoding
        }

        // SDF files use "$$$$" as record separator
        let records = text.components(separatedBy: "$$$$")
        var entries: [TrainingDataEntry] = []
        var recordIndex = 0

        for record in records {
            let trimmed = record.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            recordIndex += 1

            let lines = trimmed.components(separatedBy: .newlines)
            guard !lines.isEmpty else { continue }
            let title = lines[0].trimmingCharacters(in: .whitespaces)

            // Extract data fields (lines starting with "> <FIELD_NAME>")
            var properties: [String: String] = [:]
            var i = 0
            while i < lines.count {
                let line = lines[i].trimmingCharacters(in: .whitespaces)
                if line.hasPrefix("> <") {
                    let fieldName = line.replacingOccurrences(of: "> <", with: "")
                        .replacingOccurrences(of: ">", with: "")
                        .trimmingCharacters(in: .whitespaces)
                    // Next non-empty line is the value
                    if i + 1 < lines.count {
                        let value = lines[i + 1].trimmingCharacters(in: .whitespaces)
                        if !value.isEmpty {
                            properties[fieldName.lowercased()] = value
                        }
                    }
                }
                i += 1
            }

            // Try to extract spectral data from SDF properties
            // Common fields: "Spectrum", "Chemical Shift", "SHIFTS", "PEAK_LIST"
            var wavelengths: [Double] = []
            var intensities: [Double] = []
            var knownValue = 0.0

            // Check for NMR chemical shifts
            if let shifts = properties["spectrum 13c 0"] ?? properties["spectrum 1h 0"]
                ?? properties["shifts"] ?? properties["chemical shift"] {
                // Format: "shift1|intensity1;shift2|intensity2;..." or "shift1 intensity1\nshift2 intensity2"
                let pairs = shifts.components(separatedBy: CharacterSet(charactersIn: ";\n"))
                for pair in pairs {
                    let parts = pair.components(separatedBy: CharacterSet(charactersIn: "| \t"))
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                    if parts.count >= 1, let shift = Double(parts[0]) {
                        wavelengths.append(shift)
                        intensities.append(parts.count >= 2 ? (Double(parts[1]) ?? 1.0) : 1.0)
                    }
                }
            }

            // Check for a target/known value
            if let val = properties["known_value"] ?? properties["target"] ?? properties["spf"]
                ?? properties["activity"] ?? properties["value"] {
                knownValue = Double(val) ?? 0.0
            }

            guard !wavelengths.isEmpty else { continue }

            entries.append(TrainingDataEntry(
                datasetID: UUID().uuidString,
                datasetName: title.isEmpty ? "SDF record \(recordIndex)" : title,
                wavelengths: wavelengths,
                intensities: intensities,
                knownValue: knownValue,
                plateType: nil,
                applicationQuantityMg: nil,
                formulationType: nil
            ))

            // Limit to first 10,000 entries to avoid memory issues
            if entries.count >= 10_000 { break }
        }

        guard !entries.isEmpty else {
            throw PINNDataImportError.noValidRows
        }

        return entries
    }

    // MARK: - XY Text Parser

    /// Parses simple whitespace-delimited X Y text files (RRUFF format and similar).
    /// Lines with # are comments. Each data line has two numbers: wavelength and intensity.
    private static func importXYText(data: Data, domain: PINNDomain) throws -> [TrainingDataEntry] {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else {
            throw PINNDataImportError.invalidEncoding
        }

        var xValues: [Double] = []
        var yValues: [Double] = []
        var title = "XY spectrum"

        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            let stripped = line.trimmingCharacters(in: .whitespaces)
            if stripped.isEmpty { continue }
            // Comment lines
            if stripped.hasPrefix("#") || stripped.hasPrefix("//") || stripped.hasPrefix(";") {
                if title == "XY spectrum", stripped.hasPrefix("#") {
                    title = String(stripped.dropFirst(1)).trimmingCharacters(in: .whitespaces)
                }
                continue
            }
            // Data lines: X Y (whitespace or comma separated)
            let tokens = stripped.components(separatedBy: CharacterSet(charactersIn: " \t,"))
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            if tokens.count >= 2, let x = Double(tokens[0]), let y = Double(tokens[1]) {
                xValues.append(x)
                yValues.append(y)
            }
        }

        guard !xValues.isEmpty else {
            throw PINNDataImportError.noValidRows
        }

        let entry = TrainingDataEntry(
            datasetID: UUID().uuidString,
            datasetName: title,
            wavelengths: xValues,
            intensities: yValues,
            knownValue: 0.0,
            plateType: nil,
            applicationQuantityMg: nil,
            formulationType: nil
        )
        return [entry]
    }

    // MARK: - MSP Parser

    /// Parses NIST MSP (Mass Spectral Peak) format — used by NIST MS Search, MoNA, GNPS.
    /// Each record has Name:, MW:, Num Peaks:, then m/z intensity pairs.
    private static func importMSP(data: Data, domain: PINNDomain) throws -> [TrainingDataEntry] {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else {
            throw PINNDataImportError.invalidEncoding
        }

        var entries: [TrainingDataEntry] = []
        var currentName = "MSP spectrum"
        var currentMZ: [Double] = []
        var currentIntensities: [Double] = []
        var inPeaks = false

        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            let stripped = line.trimmingCharacters(in: .whitespaces)
            if stripped.isEmpty {
                // Empty line may end a record
                if !currentMZ.isEmpty {
                    entries.append(TrainingDataEntry(
                        datasetID: UUID().uuidString,
                        datasetName: currentName,
                        wavelengths: currentMZ,
                        intensities: currentIntensities,
                        knownValue: 0.0,
                        plateType: nil,
                        applicationQuantityMg: nil,
                        formulationType: nil
                    ))
                    if entries.count >= 10_000 { break }
                }
                currentName = "MSP spectrum"
                currentMZ = []
                currentIntensities = []
                inPeaks = false
                continue
            }

            let upper = stripped.uppercased()
            if upper.hasPrefix("NAME:") {
                currentName = String(stripped.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            } else if upper.hasPrefix("NUM PEAKS:") || upper.hasPrefix("NUMPEAKS:") || upper.hasPrefix("NUM PEAKS :") {
                inPeaks = true
            } else if inPeaks {
                // Parse peak lines: "m/z intensity" pairs, possibly multiple per line
                // Format: "85 999; 86 50; 87 200" or "85\t999"
                let pairs = stripped.components(separatedBy: ";")
                for pair in pairs {
                    let tokens = pair.components(separatedBy: CharacterSet(charactersIn: " \t"))
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                    if tokens.count >= 2, let mz = Double(tokens[0]), let intensity = Double(tokens[1]) {
                        currentMZ.append(mz)
                        currentIntensities.append(intensity)
                    }
                }
            }
        }

        // Flush last record
        if !currentMZ.isEmpty {
            entries.append(TrainingDataEntry(
                datasetID: UUID().uuidString,
                datasetName: currentName,
                wavelengths: currentMZ,
                intensities: currentIntensities,
                knownValue: 0.0,
                plateType: nil,
                applicationQuantityMg: nil,
                formulationType: nil
            ))
        }

        guard !entries.isEmpty else {
            throw PINNDataImportError.noValidRows
        }

        return entries
    }
}

// MARK: - Errors

enum PINNDataImportError: LocalizedError {
    case unsupportedFormat(String)
    case invalidJSON
    case invalidJCAMP
    case htmlNotJSON
    case invalidEncoding
    case tooFewRows
    case noValidRows
    case decompressionFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let ext):
            return "Unsupported file format: .\(ext). Supported: .json, .csv, .jdx, .dx, .sdf, .sd, .txt, .xy, .msp, .tsv"
        case .invalidJSON:
            return "Could not parse JSON. Expected an array of training entries or a training data export container."
        case .invalidJCAMP:
            return "Could not parse as JCAMP-DX format. File must start with ## labels."
        case .htmlNotJSON:
            return "This file is an HTML web page, not spectral data. The download URL may point to a landing page instead of a direct data file."
        case .invalidEncoding:
            return "Could not read file as UTF-8 or ASCII text."
        case .tooFewRows:
            return "CSV file needs at least a header row and one data row."
        case .noValidRows:
            return "No valid training data rows found in the file."
        case .decompressionFailed:
            return "Failed to decompress gzip file."
        }
    }
}

// MARK: - Data Decompression

extension Data {
    /// Simple gzip decompression using the Compression framework.
    func gunzipped() throws -> Data {
        // Minimal gzip: 10-byte header + compressed data + 8-byte trailer
        guard self.count >= 18 else { throw PINNDataImportError.decompressionFailed }

        // Skip the 10-byte gzip header (more if FEXTRA/FNAME/FCOMMENT flags are set)
        var offset = 10
        let flags = self[3]
        if flags & 0x04 != 0 { // FEXTRA
            guard offset + 2 <= self.count else { throw PINNDataImportError.decompressionFailed }
            let extraLen = Int(self[offset]) | (Int(self[offset + 1]) << 8)
            offset += 2 + extraLen
        }
        if flags & 0x08 != 0 { // FNAME — null-terminated string
            while offset < self.count && self[offset] != 0 { offset += 1 }
            offset += 1
        }
        if flags & 0x10 != 0 { // FCOMMENT — null-terminated string
            while offset < self.count && self[offset] != 0 { offset += 1 }
            offset += 1
        }
        if flags & 0x02 != 0 { offset += 2 } // FHCRC

        guard offset < self.count - 8 else { throw PINNDataImportError.decompressionFailed }

        // The raw deflate data is between the header and the 8-byte trailer
        var deflateData = Data(self[offset..<(self.count - 8)])

        // Use Compression framework for decompression
        let bufferSize = 1024 * 1024 * 32 // 32 MB max
        let outputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { outputBuffer.deallocate() }

        let decodedSize = deflateData.withUnsafeMutableBytes { rawPtr -> Int in
            guard let baseAddress = rawPtr.baseAddress else { return 0 }
            return compression_decode_buffer(
                outputBuffer, bufferSize,
                baseAddress.assumingMemoryBound(to: UInt8.self), rawPtr.count,
                nil,
                COMPRESSION_ZLIB
            )
        }

        guard decodedSize > 0 else { throw PINNDataImportError.decompressionFailed }
        return Data(bytes: outputBuffer, count: decodedSize)
    }
}
