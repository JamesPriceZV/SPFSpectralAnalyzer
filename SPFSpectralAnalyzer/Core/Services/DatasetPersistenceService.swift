import Foundation
import SwiftData
import CryptoKit

/// Stateless helpers for dataset persistence and deduplication.
enum DatasetPersistenceService {

    static func sha256Hex(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func datasetUniquenessKey(fileHash: String?, sourcePath: String?) -> String? {
        if let fileHash, !fileHash.isEmpty { return "hash:\(fileHash)" }
        if let sourcePath, !sourcePath.isEmpty { return "path:\(sourcePath.lowercased())" }
        return nil
    }

    static func decodedMetadata(for dataset: StoredDataset) -> ShimadzuSPCMetadata? {
        guard let data = dataset.metadataJSON else { return nil }
        return try? JSONDecoder().decode(ShimadzuSPCMetadata.self, from: data)
    }

    static func datasetNamePreview(_ datasets: [StoredDataset]) -> String {
        guard !datasets.isEmpty else { return "" }
        let preview = datasets.lazy.prefix(3).map { $0.fileName }.joined(separator: ", ")
        let remainder = datasets.count - 3
        if remainder > 0 {
            return "\(preview) (+\(remainder) more)"
        }
        return preview
    }

    @MainActor @discardableResult
    static func persistParsedFiles(
        _ parsedFiles: [ParsedFileResult],
        modelContext: ModelContext,
        dataStoreController: DataStoreController?
    ) -> [String: UUID] {
        guard !parsedFiles.isEmpty else { return [:] }
        var fileNameToDatasetID: [String: UUID] = [:]

        // Read existing keys from the main context (read-only).
        let allDatasets = (try? modelContext.fetch(FetchDescriptor<StoredDataset>())) ?? []
        var existingDatasetKeys = Set(
            allDatasets
                .compactMap { dataset -> String? in
                    guard dataset.modelContext != nil else { return nil }
                    return datasetUniquenessKey(fileHash: dataset.fileHash, sourcePath: dataset.sourcePath)
                }
        )

        var importedBytes: Int64 = 0

        for parsed in parsedFiles {
            let fileData = parsed.fileData ?? (try? Data(contentsOf: parsed.url))
            let fileHash = fileData.map { sha256Hex($0) }
            let uniqueKey = datasetUniquenessKey(fileHash: fileHash, sourcePath: parsed.url.path)
            if let uniqueKey,
               existingDatasetKeys.contains(uniqueKey) {
                Instrumentation.log(
                    "Duplicate dataset skipped",
                    area: .importParsing,
                    level: .warning,
                    details: "file=\(parsed.url.lastPathComponent) key=\(uniqueKey.prefix(16))"
                )
                continue
            }

            let storedSpectraInputs = parsed.rawSpectra.map { raw in
                let reason = SpectrumValidation.invalidReason(x: raw.x, y: raw.y)
                return StoredSpectrumInput(
                    name: raw.name,
                    x: raw.x,
                    y: raw.y,
                    isInvalid: reason != nil,
                    invalidReason: reason
                )
            }
            let invalidCount = storedSpectraInputs.filter { $0.isInvalid }.count
            var datasetWarnings = parsed.warnings
            if invalidCount > 0 {
                datasetWarnings.append("flagged \(invalidCount) invalid spectra")
            }

            let datasetID = UUID()
            let spectraModels = storedSpectraInputs.enumerated().map { index, stored in
                StoredSpectrum(
                    datasetID: datasetID,
                    name: stored.name,
                    orderIndex: index,
                    xData: SpectrumBinaryCodec.encodeDoubles(stored.x),
                    yData: SpectrumBinaryCodec.encodeDoubles(stored.y),
                    isInvalid: stored.isInvalid,
                    invalidReason: stored.invalidReason
                )
            }
            let spectraBytes = spectraModels.reduce(Int64(0)) { $0 + Int64($1.xData.count + $1.yData.count) }
            let metadataJSON = parsed.metadataJSON ?? (try? JSONEncoder().encode(parsed.metadata))

            let dataset = StoredDataset(
                id: datasetID,
                fileName: parsed.url.lastPathComponent,
                sourcePath: parsed.url.path,
                importedAt: Date(),
                fileHash: fileHash,
                fileData: fileData,
                metadataJSON: metadataJSON,
                headerInfoData: parsed.headerInfoData,
                skippedDataJSON: nil,
                warningsJSON: nil, spectra: spectraModels
            )
            dataset.skippedDataSets = parsed.skippedDataSets
            dataset.warnings = datasetWarnings

            // Auto-populate ISO 24443 metadata from filename
            let parsedMeta = FilenameMetadataParser.parse(filename: parsed.url.lastPathComponent)
            dataset.plateType = parsedMeta.plateType.rawValue
            dataset.applicationQuantityMg = parsedMeta.applicationQuantityMg
            dataset.formulationType = parsedMeta.formulationType.rawValue
            for spectrum in spectraModels {
                spectrum.dataset = dataset
            }
            modelContext.insert(dataset)
            fileNameToDatasetID[parsed.url.lastPathComponent] = datasetID
            if let uniqueKey {
                existingDatasetKeys.insert(uniqueKey)
            }
            importedBytes += Int64(parsed.fileData?.count ?? 0)
            importedBytes += Int64(metadataJSON?.count ?? 0)
            importedBytes += Int64(parsed.headerInfoData.count)
            importedBytes += Int64(dataset.skippedDataJSON?.count ?? 0)
            importedBytes += Int64(dataset.warningsJSON?.count ?? 0)
            importedBytes += spectraBytes
        }

        if importedBytes > 0 {
            dataStoreController?.noteLocalChange(bytes: importedBytes)
        }
        return fileNameToDatasetID
    }
}
