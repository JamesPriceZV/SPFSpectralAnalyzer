import Foundation

/// A shareable data package that bundles selected spectral datasets with
/// analysis settings for transmission via Messages, AirDrop, etc.
///
/// The package is encoded as JSON with a `.spfpackage` file extension.
struct DataAnalysisPackage: Codable, Sendable {

    /// Package format version for forward compatibility.
    let version: Int

    /// Timestamp when the package was created.
    let createdAt: Date

    /// Human-readable title for the package.
    let title: String

    /// The spectral datasets included in the package.
    let datasets: [PackagedDataset]

    /// Analysis settings that were active when the package was created.
    let analysisSettings: PackagedAnalysisSettings

    /// Optional AI analysis summary, if one was generated.
    let aiSummary: String?

    /// Optional SPF estimation result.
    let spfEstimation: PackagedSPFEstimation?

    /// Current package format version.
    static let currentVersion = 1

    init(
        title: String,
        datasets: [PackagedDataset],
        analysisSettings: PackagedAnalysisSettings,
        aiSummary: String? = nil,
        spfEstimation: PackagedSPFEstimation? = nil
    ) {
        self.version = Self.currentVersion
        self.createdAt = Date()
        self.title = title
        self.datasets = datasets
        self.analysisSettings = analysisSettings
        self.aiSummary = aiSummary
        self.spfEstimation = spfEstimation
    }
}

// MARK: - Packaged Dataset

struct PackagedDataset: Codable, Sendable, Identifiable {
    let id: UUID
    let name: String
    let spectra: [PackagedSpectrum]
    let datasetRole: String?
}

struct PackagedSpectrum: Codable, Sendable {
    let name: String
    let x: [Double]
    let y: [Double]
}

// MARK: - Packaged Analysis Settings

struct PackagedAnalysisSettings: Codable, Sendable {
    let yAxisMode: String
    let smoothingMethod: String
    let smoothingWindow: Int
    let baselineMethod: String
    let normalizationMethod: String
    let calculationMethod: String
    let useAlignment: Bool
}

// MARK: - Packaged SPF Estimation

struct PackagedSPFEstimation: Codable, Sendable {
    let value: Double
    let tier: String
    let rawColipaValue: Double?
}

// MARK: - Serialization

extension DataAnalysisPackage {

    /// File extension for data analysis packages.
    static let fileExtension = "spfpackage"

    /// MIME type for data analysis packages.
    static let mimeType = "application/x-spfpackage+json"

    /// Encodes the package to JSON data.
    func encode() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    /// Decodes a package from JSON data.
    static func decode(from data: Data) throws -> DataAnalysisPackage {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(DataAnalysisPackage.self, from: data)
    }

    /// Writes the package to a temporary file and returns the URL.
    func writeToTemporaryFile(filename: String? = nil) throws -> URL {
        let data = try encode()
        let name = filename ?? "Analysis Package \(ISO8601DateFormatter().string(from: createdAt))"
        let sanitized = name.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(sanitized)
            .appendingPathExtension(Self.fileExtension)
        try data.write(to: url, options: .atomic)
        return url
    }
}
