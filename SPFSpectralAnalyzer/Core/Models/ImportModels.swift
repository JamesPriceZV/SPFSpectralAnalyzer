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

// MARK: - SPCKit Adapter

/// Converts a fully-parsed SPCFile (SPCKit) into the ShimadzuSPCParseResult
/// format that SpectrumParsingWorker and DatasetPersistenceService expect.
enum SPCKitAdapter {

    nonisolated static func toParseResult(
        _ file: SPCFile,
        url: URL
    ) -> ShimadzuSPCParseResult {
        let ffp = file.header.firstX
        let flp = file.header.lastX
        let baseName = url.deletingPathExtension().lastPathComponent
        let subfileCount = file.subfiles.count

        let spectra: [ShimadzuSPCRawSpectrum] = file.subfiles.map { sub in
            let xDoubles = sub.resolvedXPoints(ffp: ffp, flp: flp).map { Double($0) }
            let yDoubles = sub.yPoints.map { Double($0) }
            let name: String
            if subfileCount == 1 {
                name = baseName
            } else {
                let label = file.header.memo.trimmingCharacters(in: .whitespaces)
                let sfName = label.isEmpty ? baseName : label
                name = "\(sfName)_\(sub.id + 1)"
            }
            return ShimadzuSPCRawSpectrum(name: name, x: xDoubles, y: yDoubles)
        }

        let h = file.header
        let sdaHeader = SDAMainHeader(
            fileTypeFlags: h.flags.rawValue,
            spcVersion: h.version.rawValue,
            experimentTypeCode: h.experimentType,
            yExponent: Int8(bitPattern: h.yExponent),
            pointCount: Int32(h.pointCount),
            firstX: h.firstX,
            lastX: h.lastX,
            subfileCount: Int32(h.subfileCount),
            xUnitsCode: h.xUnitsCode,
            yUnitsCode: h.yUnitsCode,
            zUnitsCode: h.zUnitsCode,
            postingDisposition: 0,
            compressedDate: SDACompressedDate(rawValue: Int32(bitPattern: h.compressedDate)),
            resolutionText: h.resolutionDescription,
            sourceInstrumentText: h.sourceInstrument,
            peakPointNumber: h.peakPoint,
            memo: h.memo,
            customAxisCombined: h.customAxisLabels,
            customAxisX: "",
            customAxisY: "",
            customAxisZ: "",
            logBlockOffset: Int32(bitPattern: h.logOffset),
            fileModificationFlag: Int32(bitPattern: h.modificationFlag),
            processingCode: 0,
            calibrationLevelPlusOne: 0,
            subMethodInjectionNumber: 0,
            concentrationFactor: h.concentrationFactor,
            methodFile: h.methodFile,
            zSubfileIncrement: h.zIncrement,
            wPlaneCount: Int32(h.wPlaneCount),
            wPlaneIncrement: h.wIncrement,
            wAxisUnitsCode: h.wUnitsCode
        )

        let metadata = ShimadzuSPCMetadata(
            fileName: url.lastPathComponent,
            fileSizeBytes: 0,
            directoryEntryNames: [],
            dataSetNames: spectra.map(\.name),
            headerInfoByteCount: 512,
            mainHeader: sdaHeader
        )

        return ShimadzuSPCParseResult(
            spectra: spectra,
            skippedDataSets: [],
            metadata: metadata,
            headerInfoData: Data()
        )
    }
}
