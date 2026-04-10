import Foundation

struct StoredSpectrumInput: Sendable {
    let name: String
    let x: [Double]
    let y: [Double]
    let isInvalid: Bool
    let invalidReason: String?
}

struct RawSpectrumInput: Sendable {
    let name: String
    let x: [Double]
    let y: [Double]
    let fileName: String
}

struct ParsedFileResult: Sendable {
    let url: URL
    let rawSpectra: [RawSpectrumInput]
    let skippedDataSets: [String]
    let warnings: [String]
    let metadata: ShimadzuSPCMetadata
    let headerInfoData: Data
    let fileData: Data?
    /// Pre-encoded metadata JSON (encoded in the background parser to avoid
    /// blocking the main thread during persistence).
    let metadataJSON: Data?
}

struct ParseBatchResult: Sendable {
    let loaded: [RawSpectrumInput]
    let failures: [String]
    let skippedTotal: Int
    let filesWithSkipped: Int
    let warnings: [String]
    let parsedFiles: [ParsedFileResult]
}
