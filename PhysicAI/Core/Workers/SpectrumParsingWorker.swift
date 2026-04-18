import Foundation

actor SpectrumParsingWorker {
    static let shared = SpectrumParsingWorker()

    /// Callback reporting (parsedSoFar, totalFiles, currentFileName) after each file.
    typealias ProgressCallback = @Sendable (Int, Int, String) async -> Void

    func parse(urls: [URL],
               onProgress: ProgressCallback? = nil) async -> ParseBatchResult {
        var loaded: [RawSpectrumInput] = []
        var failures: [String] = []
        var skippedTotal = 0
        var filesWithSkipped = 0
        var warnings: [String] = []
        var parsedFiles: [ParsedFileResult] = []

        for (index, url) in urls.enumerated() {
            // Report progress before parsing each file
            await onProgress?(index, urls.count, url.lastPathComponent)
            let accessGranted = url.startAccessingSecurityScopedResource()
            defer {
                if accessGranted { url.stopAccessingSecurityScopedResource() }
            }

            let fileStart = Date()
            var fileRawSpectra: [RawSpectrumInput] = []
            var fileWarnings: [String] = []
            do {
                let result: ShimadzuSPCParseResult
                // Phase 2: Use SPCKit's unified SPCParser for all SPC file formats.
                let spcFile = try await SPCParser.parse(url: url)
                result = SPCKitAdapter.toParseResult(spcFile, url: url)
                let namedSpectra = result.spectra.enumerated().map { index, spectrum in
                    let name = ContentView.sampleDisplayName(
                        from: url,
                        spectrumName: spectrum.name,
                        index: index,
                        total: result.spectra.count
                    )
                    return RawSpectrumInput(name: name, x: spectrum.x, y: spectrum.y, fileName: url.lastPathComponent)
                }

                fileRawSpectra = namedSpectra
                loaded.append(contentsOf: namedSpectra)
                if !result.skippedDataSets.isEmpty {
                    filesWithSkipped += 1
                    skippedTotal += result.skippedDataSets.count
                    let warning = "skipped \(result.skippedDataSets.count)"
                    fileWarnings.append(warning)
                    warnings.append("\(url.lastPathComponent): \(warning)")
                }

                let fileData = try? Data(contentsOf: url)
                let parsedResult = ParsedFileResult(
                    url: url,
                    rawSpectra: fileRawSpectra,
                    skippedDataSets: result.skippedDataSets,
                    warnings: fileWarnings,
                    metadata: result.metadata,
                    headerInfoData: result.headerInfoData,
                    fileData: fileData,
                    metadataJSON: nil
                )
                parsedFiles.append(parsedResult)
                await MainActor.run {
                    DatasetViewModel.validateSPCHeaderConsistency(for: parsedResult)
                }

                let duration = Date().timeIntervalSince(fileStart)
                let fileName = url.lastPathComponent
                let spectraCount = namedSpectra.count
                let skippedCount = result.skippedDataSets.count
                await MainActor.run {
                    Instrumentation.log(
                        "File parsed",
                        area: .importParsing,
                        level: .info,
                        details: "file=\(fileName) spectra=\(spectraCount) skipped=\(skippedCount)",
                        duration: duration
                    )
                }
            } catch {
                let duration = Date().timeIntervalSince(fileStart)
                let fileName = url.lastPathComponent
                let errorMessage = error.localizedDescription
                await MainActor.run {
                    Instrumentation.log(
                        "File parse failed",
                        area: .importParsing,
                        level: .warning,
                        details: "file=\(fileName) error=\(errorMessage)",
                        duration: duration
                    )
                }
                failures.append("\(url.lastPathComponent): \(error)")
            }
        }

        // Report parsing complete
        await onProgress?(urls.count, urls.count, "")

        return ParseBatchResult(
            loaded: loaded,
            failures: failures,
            skippedTotal: skippedTotal,
            filesWithSkipped: filesWithSkipped,
            warnings: warnings,
            parsedFiles: parsedFiles
        )
    }

}
