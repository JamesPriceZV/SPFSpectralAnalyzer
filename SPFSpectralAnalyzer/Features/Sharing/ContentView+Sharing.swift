import SwiftUI

// MARK: - Data Analysis Package & View Sharing

extension ContentView {

    /// Builds a `DataAnalysisPackage` from the currently loaded spectra and analysis settings.
    func buildDataAnalysisPackage() -> DataAnalysisPackage? {
        let spectra = analysis.displayedSpectra
        guard !spectra.isEmpty else { return nil }

        // Group spectra by source dataset
        var datasetMap: [UUID: [ShimadzuSpectrum]] = [:]
        var untagged: [ShimadzuSpectrum] = []
        for spectrum in spectra {
            if let dsID = spectrum.sourceDatasetID {
                datasetMap[dsID, default: []].append(spectrum)
            } else {
                untagged.append(spectrum)
            }
        }

        var packagedDatasets: [PackagedDataset] = []

        // Build packaged datasets from the cache (CloudKit-safe)
        for (dsID, dsSpectra) in datasetMap {
            let record = datasets.searchableRecordCache[dsID]
            let name = record?.fileName ?? "Dataset"
            let role = record?.isReference == true ? "reference" : nil
            let packaged = dsSpectra.map { PackagedSpectrum(name: $0.name, x: $0.x, y: $0.y) }
            packagedDatasets.append(PackagedDataset(id: dsID, name: name, spectra: packaged, datasetRole: role))
        }

        // Add untagged spectra as a single unnamed dataset
        if !untagged.isEmpty {
            let packaged = untagged.map { PackagedSpectrum(name: $0.name, x: $0.x, y: $0.y) }
            packagedDatasets.append(PackagedDataset(id: UUID(), name: "Imported Spectra", spectra: packaged, datasetRole: nil))
        }

        let calcMethod = SPFCalculationMethod(rawValue: spfCalculationMethodRawValue) ?? .colipa
        let settings = PackagedAnalysisSettings(
            yAxisMode: analysis.yAxisMode.rawValue,
            smoothingMethod: analysis.smoothingMethod.rawValue,
            smoothingWindow: analysis.smoothingWindow,
            baselineMethod: analysis.baselineMethod.rawValue,
            normalizationMethod: analysis.normalizationMethod.rawValue,
            calculationMethod: calcMethod.rawValue,
            useAlignment: analysis.useAlignment
        )

        var spfEstimation: PackagedSPFEstimation?
        if let est = analysis.cachedSPFEstimation {
            spfEstimation = PackagedSPFEstimation(
                value: est.value,
                tier: est.tier.label,
                rawColipaValue: est.rawColipaValue
            )
        }

        let aiSummary = aiVM.structuredOutput?.summary

        let totalSpectra = packagedDatasets.reduce(0) { $0 + $1.spectra.count }
        let title = "SPF Analysis — \(packagedDatasets.count) dataset\(packagedDatasets.count == 1 ? "" : "s"), \(totalSpectra) spectra"

        return DataAnalysisPackage(
            title: title,
            datasets: packagedDatasets,
            analysisSettings: settings,
            aiSummary: aiSummary,
            spfEstimation: spfEstimation
        )
    }

    /// Shares the current analysis as a data package via the system share sheet.
    func shareDataPackage() {
        guard let package = buildDataAnalysisPackage(),
              let data = try? package.encode() else {
            analysis.errorMessage = "No spectral data available to share."
            return
        }
        let filename = "SPF Analysis \(DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short))"
        pendingShareContent = .dataPackage(data, filename: filename)
    }

    /// Captures the analysis chart as a screenshot and shares it.
    func shareAnalysisScreenshot() {
        let chartView = chartSection
            .frame(width: 900, height: 600)
            .padding()
            .background(Color.white)

        guard let pngData = ViewSnapshotService.snapshotToPNG(chartView, size: CGSize(width: 960, height: 660)) else {
            analysis.errorMessage = "Failed to capture chart screenshot."
            return
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SPF Analysis Chart")
            .appendingPathExtension("png")
        do {
            try pngData.write(to: tempURL, options: .atomic)
        } catch {
            analysis.errorMessage = "Failed to write screenshot: \(error.localizedDescription)"
            return
        }

        // Use the platform image for sharing
        #if os(macOS)
        if let image = NSImage(data: pngData) {
            pendingShareContent = .viewScreenshot(image, title: "SPF Analysis Chart")
        }
        #else
        if let image = UIImage(data: pngData) {
            pendingShareContent = .viewScreenshot(image, title: "SPF Analysis Chart")
        }
        #endif
    }
}
