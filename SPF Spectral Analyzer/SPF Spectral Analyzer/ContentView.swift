import SwiftUI
import Charts
import UniformTypeIdentifiers
import AppKit
import Foundation
import SwiftData
import CryptoKit

enum SmoothingMethod: String, CaseIterable, Identifiable {
    case none = "None"
    case movingAverage = "Moving Avg"
    case savitzkyGolay = "Savitzky-Golay"

    var id: String { rawValue }
}

enum SpectrumPalette: String, CaseIterable, Identifiable {
    case vivid = "Vivid"
    case cool = "Cool"
    case warm = "Warm"
    case mono = "Mono"

    var id: String { rawValue }

    var colors: [Color] {
        switch self {
        case .vivid:
            return [.red, .blue, .green, .orange, .pink, .teal, .purple, .indigo, .mint, .cyan, .brown]
        case .cool:
            return [.blue, .teal, .cyan, .mint, .indigo, .purple]
        case .warm:
            return [.red, .orange, .yellow, .pink, .brown]
        case .mono:
            return [.black, .gray, .gray.opacity(0.7), .gray.opacity(0.5)]
        }
    }
}

enum ExportFormat: String, CaseIterable, Identifiable {
    case csv = "CSV"
    case jcamp = "JCAMP"
    case excel = "Excel (.xlsx)"
    case wordReport = "Word (.docx)"
    case pdfReport = "PDF Report"
    case htmlReport = "HTML Report"

    var id: String { rawValue }
}

enum SpfDisplayMode: String, CaseIterable, Identifiable {
    case colipa
    case calibrated

    var id: String { rawValue }

    var label: String {
        switch self {
        case .colipa:
            return "COLIPA SPF"
        case .calibrated:
            return "Estimated SPF (calibrated)"
        }
    }
}

struct AILogEntry: Identifiable, Hashable {
    let id = UUID()
    let timestamp: Date
    let message: String
}

struct AIHistoryEntry: Identifiable, Hashable {
    let id = UUID()
    let timestamp: Date
    let preset: AIPromptPreset
    let scope: AISelectionScope
    let text: String
}

struct InstrumentationLogEntry: Identifiable, Hashable {
    let id = UUID()
    let timestamp: Date
    let message: String
}

struct LogEntryPayload: Codable {
    let timestamp: Date
    let message: String
}

struct InvalidSpectrumItem: Identifiable, Sendable {
    let id = UUID()
    let spectrum: ShimadzuSpectrum
    let fileName: String
    let reason: String

    var name: String { spectrum.name }
}

private struct StoredSpectrumInput {
    let name: String
    let x: [Double]
    let y: [Double]
    let isInvalid: Bool
    let invalidReason: String?
}

private struct RawSpectrumInput: Sendable {
    let name: String
    let x: [Double]
    let y: [Double]
    let fileName: String
}

private struct ParsedFileResult: Sendable {
    let url: URL
    let rawSpectra: [RawSpectrumInput]
    let skippedDataSets: [String]
    let warnings: [String]
    let metadata: ShimadzuSPCMetadata
    let headerInfoData: Data
    let fileData: Data?
}

private struct ParseBatchResult: Sendable {
    let loaded: [RawSpectrumInput]
    let failures: [String]
    let skippedTotal: Int
    let filesWithSkipped: Int
    let warnings: [String]
    let parsedFiles: [ParsedFileResult]
}

private struct MetricsComputationResult: Sendable {
    let selectedMetrics: SpectralMetrics?
    let metricsStats: (avgUvaUvb: Double, avgCritical: Double, uvaUvbRange: ClosedRange<Double>, criticalRange: ClosedRange<Double>)?
    let calibration: CalibrationResult?
    let colipaSpf: Double?
    let dashboard: DashboardMetrics?
}

private struct DashboardMetrics: Sendable {
    let totalCount: Int
    let compliancePercent: Double
    let complianceCount: Int
    let avgUvaUvb: Double
    let uvaUvbRange: ClosedRange<Double>
    let avgCritical: Double
    let criticalRange: ClosedRange<Double>
    let postIncubationDropPercent: Double?
    let lowCriticalCount: Int
    let heatmapBins: [HeatmapBin]
    let heatmapXRange: ClosedRange<Double>
    let heatmapYRange: ClosedRange<Double>
}

private struct HeatmapBin: Identifiable, Sendable {
    let id = UUID()
    let xIndex: Int
    let yIndex: Int
    let count: Int
    let xRange: ClosedRange<Double>
    let yRange: ClosedRange<Double>
}

private struct BatchCompareRow: Identifiable {
    let id = UUID()
    let name: String
    let spf: Double?
    let deltaSpf: Double?
    let uvaUvb: Double?
    let deltaUvaUvb: Double?
    let critical: Double?
    let deltaCritical: Double?
}

private actor SpectrumParsingWorker {
    static let shared = SpectrumParsingWorker()

    func parse(urls: [URL]) async -> ParseBatchResult {
        var loaded: [RawSpectrumInput] = []
        var failures: [String] = []
        var skippedTotal = 0
        var filesWithSkipped = 0
        var warnings: [String] = []
        var parsedFiles: [ParsedFileResult] = []

        for url in urls {
            let accessGranted = url.startAccessingSecurityScopedResource()
            defer {
                if accessGranted { url.stopAccessingSecurityScopedResource() }
            }

            let fileStart = Date()
            var fileRawSpectra: [RawSpectrumInput] = []
            var fileWarnings: [String] = []
            do {
                let parser = try ShimadzuSPCParser(fileURL: url)
                let result = try parser.extractSpectraResult()
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
                    fileData: fileData
                )
                parsedFiles.append(parsedResult)
                await MainActor.run {
                    ContentView.validateSPCHeaderConsistency(for: parsedResult)
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

private actor SpectralMetricsWorker {
    static let shared = SpectralMetricsWorker()

    func compute(
        selectedSnapshot: (x: [Double], y: [Double])?,
        selectedSpectraSnapshots: [(x: [Double], y: [Double])],
        calibrationSnapshots: [(labelSPF: Double, x: [Double], y: [Double])],
        dashboardSnapshots: [(name: String, x: [Double], y: [Double])],
        yAxisMode: SpectralYAxisMode
    ) -> MetricsComputationResult {
        let selectedMetrics = selectedSnapshot.flatMap { snapshot in
            SpectralMetricsCalculator.metrics(x: snapshot.x, y: snapshot.y, yAxisMode: yAxisMode)
        }

        let metricsList = selectedSpectraSnapshots.compactMap { snapshot in
            SpectralMetricsCalculator.metrics(x: snapshot.x, y: snapshot.y, yAxisMode: yAxisMode)
        }
        let metricsStats: (avgUvaUvb: Double, avgCritical: Double, uvaUvbRange: ClosedRange<Double>, criticalRange: ClosedRange<Double>)? = {
            guard !metricsList.isEmpty else { return nil }

            let uvaUvbValues = metricsList.map { $0.uvaUvbRatio }
            let criticalValues = metricsList.map { $0.criticalWavelength }

            let avgUvaUvb = uvaUvbValues.reduce(0, +) / Double(uvaUvbValues.count)
            let avgCritical = criticalValues.reduce(0, +) / Double(criticalValues.count)

            let uvaUvbRange = (uvaUvbValues.min() ?? 0)...(uvaUvbValues.max() ?? 0)
            let criticalRange = (criticalValues.min() ?? 0)...(criticalValues.max() ?? 0)

            return (avgUvaUvb, avgCritical, uvaUvbRange, criticalRange)
        }()

        let calibrationSamples: [CalibrationSample] = calibrationSnapshots.compactMap { snapshot in
            guard let metrics = SpectralMetricsCalculator.metrics(x: snapshot.x, y: snapshot.y, yAxisMode: yAxisMode) else { return nil }
            return CalibrationSample(labelSPF: snapshot.labelSPF, metrics: metrics)
        }
        let calibration = SPFCalibration.build(samples: calibrationSamples)

        let colipaSpf = selectedSnapshot.flatMap { snapshot in
            SpectralMetricsCalculator.colipaSpf(x: snapshot.x, y: snapshot.y, yAxisMode: yAxisMode)
        }

        let dashboard = buildDashboardMetrics(snapshots: dashboardSnapshots, yAxisMode: yAxisMode)

        return MetricsComputationResult(
            selectedMetrics: selectedMetrics,
            metricsStats: metricsStats,
            calibration: calibration,
            colipaSpf: colipaSpf,
            dashboard: dashboard
        )
    }

    private func buildDashboardMetrics(
        snapshots: [(name: String, x: [Double], y: [Double])],
        yAxisMode: SpectralYAxisMode
    ) -> DashboardMetrics? {
        guard !snapshots.isEmpty else { return nil }

        var metricsList: [(name: String, metrics: SpectralMetrics, spf: Double?)] = []
        metricsList.reserveCapacity(snapshots.count)

        for snapshot in snapshots {
            guard let metrics = SpectralMetricsCalculator.metrics(x: snapshot.x, y: snapshot.y, yAxisMode: yAxisMode) else { continue }
            let spf = SpectralMetricsCalculator.colipaSpf(x: snapshot.x, y: snapshot.y, yAxisMode: yAxisMode)
            metricsList.append((snapshot.name, metrics, spf))
        }

        guard !metricsList.isEmpty else { return nil }

        let uvaUvbValues = metricsList.map { $0.metrics.uvaUvbRatio }
        let criticalValues = metricsList.map { $0.metrics.criticalWavelength }
        let avgUvaUvb = uvaUvbValues.reduce(0, +) / Double(uvaUvbValues.count)
        let avgCritical = criticalValues.reduce(0, +) / Double(criticalValues.count)
        let uvaUvbRange = (uvaUvbValues.min() ?? 0)...(uvaUvbValues.max() ?? 0)
        let criticalRange = (criticalValues.min() ?? 0)...(criticalValues.max() ?? 0)

        let spfValues = metricsList.compactMap { $0.spf }
        let complianceCount = spfValues.filter { $0 >= 30.0 }.count
        let compliancePercent = spfValues.isEmpty ? 0.0 : (Double(complianceCount) / Double(spfValues.count)) * 100.0

        let lowCriticalCount = metricsList.filter { $0.metrics.criticalWavelength < 370.0 }.count

        let preSpf = metricsList.compactMap { entry in
            isPostIncubation(entry.name) ? nil : entry.spf
        }
        let postSpf = metricsList.compactMap { entry in
            isPostIncubation(entry.name) ? entry.spf : nil
        }
        let preAvg = preSpf.isEmpty ? nil : (preSpf.reduce(0, +) / Double(preSpf.count))
        let postAvg = postSpf.isEmpty ? nil : (postSpf.reduce(0, +) / Double(postSpf.count))
        let postIncubationDropPercent: Double? = {
            guard let preAvg, let postAvg, preAvg > 0 else { return nil }
            return max(((preAvg - postAvg) / preAvg) * 100.0, 0.0)
        }()

        let heatmapBins = buildHeatmapBins(metricsList: metricsList)
        let heatmapXRange = (heatmapBins.map { $0.xRange.lowerBound }.min() ?? uvaUvbRange.lowerBound)
            ...
            (heatmapBins.map { $0.xRange.upperBound }.max() ?? uvaUvbRange.upperBound)
        let heatmapYRange = (heatmapBins.map { $0.yRange.lowerBound }.min() ?? criticalRange.lowerBound)
            ...
            (heatmapBins.map { $0.yRange.upperBound }.max() ?? criticalRange.upperBound)

        return DashboardMetrics(
            totalCount: metricsList.count,
            compliancePercent: compliancePercent,
            complianceCount: complianceCount,
            avgUvaUvb: avgUvaUvb,
            uvaUvbRange: uvaUvbRange,
            avgCritical: avgCritical,
            criticalRange: criticalRange,
            postIncubationDropPercent: postIncubationDropPercent,
            lowCriticalCount: lowCriticalCount,
            heatmapBins: heatmapBins,
            heatmapXRange: heatmapXRange,
            heatmapYRange: heatmapYRange
        )
    }

    private func buildHeatmapBins(metricsList: [(name: String, metrics: SpectralMetrics, spf: Double?)]) -> [HeatmapBin] {
        let xBins = 5
        let yBins = 5
        let xValues = metricsList.map { $0.metrics.uvaUvbRatio }
        let yValues = metricsList.map { $0.metrics.criticalWavelength }

        let xMin = xValues.min() ?? 0
        let xMax = xValues.max() ?? 1
        let yMin = yValues.min() ?? 300
        let yMax = yValues.max() ?? 400

        let xSpan = max(xMax - xMin, 0.1)
        let ySpan = max(yMax - yMin, 1.0)

        var binCounts = Array(repeating: Array(repeating: 0, count: yBins), count: xBins)
        for entry in metricsList {
            let xIndex = min(max(Int(((entry.metrics.uvaUvbRatio - xMin) / xSpan) * Double(xBins)), 0), xBins - 1)
            let yIndex = min(max(Int(((entry.metrics.criticalWavelength - yMin) / ySpan) * Double(yBins)), 0), yBins - 1)
            binCounts[xIndex][yIndex] += 1
        }

        var bins: [HeatmapBin] = []
        for xIndex in 0..<xBins {
            let xStart = xMin + (Double(xIndex) / Double(xBins)) * xSpan
            let xEnd = xMin + (Double(xIndex + 1) / Double(xBins)) * xSpan
            for yIndex in 0..<yBins {
                let yStart = yMin + (Double(yIndex) / Double(yBins)) * ySpan
                let yEnd = yMin + (Double(yIndex + 1) / Double(yBins)) * ySpan
                let count = binCounts[xIndex][yIndex]
                if count > 0 {
                    bins.append(
                        HeatmapBin(
                            xIndex: xIndex,
                            yIndex: yIndex,
                            count: count,
                            xRange: xStart...xEnd,
                            yRange: yStart...yEnd
                        )
                    )
                }
            }
        }
        return bins
    }

    private func isPostIncubation(_ name: String) -> Bool {
        let normalized = name.lowercased()
        if normalized.contains("after incubation") { return true }
        if normalized.contains("post incubation") { return true }
        if normalized.contains("after incub") { return true }
        return false
    }
}

enum AppMode: String, CaseIterable, Identifiable {
    case `import` = "Import"
    case analyze = "Analyze"
    case aiAnalysis = "AI Analysis"
    case export = "Export"
    case instrument = "Instrument Control"

    var id: String { rawValue }
}


struct ExportOptions {
    var title: String
    var operatorName: String
    var notes: String
    var includeProcessing: Bool
    var includeMetadata: Bool
}

struct ProcessingSettings: Equatable {
    var useAlignment: Bool
    var smoothingMethod: SmoothingMethod
    var smoothingWindow: Int
    var sgWindow: Int
    var sgOrder: Int
    var baselineMethod: BaselineMethod
    var normalizationMethod: NormalizationMethod
    var showAllSpectra: Bool
    var showAverage: Bool
    var yAxisMode: SpectralYAxisMode
    var overlayLimit: Int
    var showLegend: Bool
    var showLabels: Bool
    var palette: SpectrumPalette
    var detectPeaks: Bool
    var peakMinHeight: Double
    var peakMinDistance: Int
    var showPeaks: Bool
}

struct ContentView: View {
    @EnvironmentObject private var dataStoreController: DataStoreController
    @State private var spectra: [ShimadzuSpectrum] = []
    @State private var alignedSpectra: [ShimadzuSpectrum] = []
    @State private var processedSpectra: [ShimadzuSpectrum] = []

    @State private var appMode: AppMode = .analyze
    @State private var showBottomTray = true
    @State private var showPipelineDetails = true
    @State private var showInspectorDetails = true
    @State private var lastAppliedSettings: ProcessingSettings?
    @Namespace private var glassNamespace
    @Environment(\.undoManager) private var undoManager
    @Environment(\.modelContext) private var modelContext
    @Query(
        filter: #Predicate<StoredDataset> { !$0.isArchived },
        sort: \StoredDataset.importedAt,
        order: .reverse
    ) private var storedDatasets: [StoredDataset]
    @Query(
        filter: #Predicate<StoredDataset> { $0.isArchived },
        sort: \StoredDataset.archivedAt,
        order: .reverse
    ) private var archivedDatasets: [StoredDataset]

    private let chartWavelengthRange: ClosedRange<Double> = 280.0...420.0
    private static let storedDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
    @State private var chartVisibleDomain: Double = 80.0
    @State private var chartVisibleYDomain: Double = 0.6
    @State private var chartSelectionX: Double?
    @State private var chartHoverLocation: CGPoint?

    @State private var useAlignment = true
    @State private var smoothingMethod: SmoothingMethod = .none
    @State private var smoothingWindow = 11
    @State private var sgWindow = 11
    @State private var sgOrder = 3
    @State private var baselineMethod: BaselineMethod = .none
    @State private var normalizationMethod: NormalizationMethod = .none

    @State private var showAllSpectra = true
    @State private var yAxisMode: SpectralYAxisMode = .absorbance
    @State private var showAverage = false
    @State private var showSelectedOnly = false
    @State private var overlayLimit = 10
    @State private var showLegend = true
    @State private var showLabels = false
    @State private var palette: SpectrumPalette = .vivid

    @State private var detectPeaks = false
    @State private var peakMinHeight = 0.01
    @State private var peakMinDistance = 5
    @State private var peaks: [PeakPoint] = []
    @State private var showPeaks = false

    @State private var selectedSpectrumIndex = 0
    @State private var selectedSpectrumIndices: Set<Int> = []
    @State private var expandChart = false

    @State private var showImporter = false
    @State private var appendOnImport = false
    @State private var showStoredDatasetPicker = false
    @State private var statusMessage = "No files loaded"
    @State private var selectedStoredDatasetIDs: Set<UUID> = []
    @State private var storedDatasetPickerSelection: Set<UUID> = []
    @State private var datasetDetailPopoverID: UUID?
    @State private var datasetSearchText = ""
    @State private var showArchivedDatasetSheet = false
    @State private var archivedDatasetSelection: Set<UUID> = []
    @State private var archivedSearchText = ""
    @State private var showArchiveConfirmation = false
    @State private var pendingArchiveDatasetIDs: Set<UUID> = []
    @State private var pendingPermanentDeleteIDs: Set<UUID> = []
    @State private var showPermanentDeleteSheet = false
    @State private var showDuplicateCleanupConfirm = false
    @State private var duplicateCleanupMessage = ""
    @State private var duplicateCleanupTargetIDs: Set<UUID> = []
    @State private var warningMessage: String?
    @State private var warningDetails: [String] = []
    @State private var showWarningDetails = false
    @State private var activeMetadata: ShimadzuSPCMetadata?
    @State private var activeMetadataSource: String?
    struct ValidationLogEntry: Identifiable, Hashable {
        let id = UUID()
        let timestamp: Date
        let message: String
    }

    @State private var validationLogEntries: [ValidationLogEntry] = []
    @State private var invalidItems: [InvalidSpectrumItem] = []
    @State private var selectedInvalidItemIDs: Set<UUID> = []
    @State private var showInvalidDetails = false
    @State private var showInvalidInline = false
    @State private var includeInvalidInPlots = false
    @State private var showSpfMathDetails = false
    @State private var errorMessage: String?

    @State private var showExportSheet = false
    @State private var exportFormat: ExportFormat = .csv
    @State private var exportTitle = ""
    @State private var exportOperator = ""
    @State private var exportNotes = ""
    @State private var exportIncludeProcessing = true
    @State private var exportIncludeMetadata = true

    @State private var cachedSeries: [SpectrumSeries] = []
    @State private var cachedAverageSpectrum: ShimadzuSpectrum?
    @State private var cachedSelectedMetrics: SpectralMetrics?
    @State private var cachedSelectedMetricsStats: (avgUvaUvb: Double, avgCritical: Double, uvaUvbRange: ClosedRange<Double>, criticalRange: ClosedRange<Double>)?
    @State private var cachedColipaSpf: Double?
    @State private var cachedCalibration: CalibrationResult?
    @State private var cachedDashboardMetrics: DashboardMetrics?
    @State private var pointCache: [String: [SpectrumPoint]] = [:]

    @AppStorage("aiEnabled") private var aiEnabled = false
    @AppStorage("aiTemperature") private var aiTemperature = 0.3
    @AppStorage("aiMaxTokens") private var aiMaxTokens = 800
    @AppStorage("aiPromptPreset") private var aiPromptPresetRawValue = AIPromptPreset.summary.rawValue
    @AppStorage("aiAutoRun") private var aiAutoRun = false
    @AppStorage("aiDefaultScope") private var aiDefaultScopeRawValue = AISelectionScope.selected.rawValue
    @AppStorage("aiOpenAIEndpoint") private var aiOpenAIEndpoint = "https://api.openai.com/v1/responses"
    @AppStorage("aiOpenAIModel") private var aiOpenAIModel = "gpt-5.4"
    @AppStorage("aiDiagnosticsEnabled") private var aiDiagnosticsEnabled = false
    @AppStorage("aiStructuredOutputEnabled") private var aiStructuredOutputEnabled = true
    @AppStorage("aiResponseTextSize") private var aiResponseTextSize = 12.0
    @AppStorage("aiCostPerThousandTokens") private var aiCostPerThousandTokens = 0.01

    @AppStorage("spfDisplayMode") private var spfDisplayModeRawValue = SpfDisplayMode.calibrated.rawValue

    @AppStorage("instrumentationOutputInApp") private var instrumentationOutputInApp = false
    @AppStorage("instrumentationShowLogWindow") private var showInstrumentationLogWindow = false
    @AppStorage("swiftDataStoreResetOccurred") private var storeResetOccurred = false
    @AppStorage("swiftDataStoreResetMessage") private var storeResetMessage = ""
    @AppStorage("icloudLastSyncStatus") private var icloudLastSyncStatus = "Not synced yet"
    @AppStorage("icloudLastSyncTimestamp") private var icloudLastSyncTimestamp = 0.0
    @AppStorage("icloudSyncInProgress") private var icloudSyncInProgress = false
    @AppStorage("icloudProgressCollapsed") private var icloudProgressCollapsed = true
    @AppStorage("icloudLastSyncTrigger") private var icloudLastSyncTrigger = ""
    @AppStorage("toolbarShowLabels") private var toolbarShowLabels = false

    @State private var aiScopeOverride: AISelectionScope?
    @State private var aiIsRunning = false
    @State private var aiResult: AIAnalysisResult?
    @State private var aiStructuredOutput: AIStructuredOutput?
    @State private var aiErrorMessage: String?
    @State private var aiCache: [String: AIAnalysisResult] = [:]
    @State private var aiEstimatedTokens: Int = 0
    @State private var showAISavePrompt = false
    @State private var showAIDetails = true
    @State private var useCustomPrompt = false
    @State private var aiCustomPrompt = ""
    @AppStorage("aiShowLogWindow") private var showAILogWindow = false
    @AppStorage("aiClearLogsOnQuit") private var aiClearLogsOnQuit = false
    @State private var aiLogEntries: [AILogEntry] = []
    @State private var aiLogAutoScroll = true
    private let aiLogStorageKey = "aiLogEntriesData"
    private let aiLogMaxEntries = 500

    @State private var aiHistoryEntries: [AIHistoryEntry] = []
    @State private var aiHistorySelectionA: UUID?
    @State private var aiHistorySelectionB: UUID?
    private let aiHistoryMaxEntries = 20

    @State private var aiSidebarInsightsText = ""
    @State private var aiSidebarRisksText = ""
    @State private var aiSidebarActionsText = ""
    @State private var aiSidebarHasStructuredSections = false

    @State private var instrumentationLogEntries: [InstrumentationLogEntry] = []
    @State private var instrumentationLogAutoScroll = true
    private let instrumentationLogStorageKey = "instrumentationLogEntriesData"
    private let instrumentationLogMaxEntries = 500

    @StateObject private var instrumentManager = InstrumentManager(driver: MockInstrumentDriver())
    @State private var selectedInstrumentID: UUID?

    init(previewSpectra: [ShimadzuSpectrum] = [], previewMode: AppMode = .analyze) {
        _spectra = State(initialValue: previewSpectra)
        _appMode = State(initialValue: previewMode)
    }

    var body: some View {
        applyDiagnosticsLogListeners(
            applyAIChangeHandlers(
                applySelectionChangeHandlers(
                    applyProcessingChangeHandlers(
                        applyAlertsAndSheets(
                            applyImporters(baseContent)
                        )
                    )
                )
            )
        )
    }

    private var baseContent: some View {
        ZStack {
            backgroundView
            VStack(spacing: 0) {
                if appMode == .import {
                    if dataStoreController.cloudKitUnavailable {
                        cloudKitBanner
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                    } else if dataStoreController.cloudSyncEnabled && isLocalStore {
                        localStoreBanner
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                    } else if dataStoreController.syncState.isActive {
                        cloudKitProgressBanner(state: dataStoreController.syncState)
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                    }
                    if shouldShowSyncStatusBar {
                        syncStatusBar
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                    }
                }
                contentArea
                if showBottomTray {
                    bottomTray
                }
            }
        }
        .onAppear {
            AppIconRenderer.applyRuntimeIcon()
            if spectra.isEmpty {
                appMode = .import
            } else {
                applyAlignmentIfNeeded()
                rebuildCaches()
                updatePeaks()
            }
            updateAIEstimate()
            loadPersistentAILog()
            loadPersistentInstrumentationLog()
        }
        .confirmationDialog("Save AI Analysis?", isPresented: $showAISavePrompt, titleVisibility: .visible) {
            Button("Save to File") { saveAIResultToDisk() }
            Button("Open") { saveAIResultToDefaultAndOpen() }
            Button("Not Now", role: .cancel) { }
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                HStack(spacing: 12) {
                    if isRunningUITests {
                        // UI tests anchor on this segmented control for mode switching.
                        modePicker
                    }
                    SettingsLink {
                        if toolbarShowLabels {
                            Label("Settings", systemImage: "gearshape")
                        } else {
                            Label("Settings", systemImage: "gearshape")
                                .labelStyle(.iconOnly)
                                .help("Settings")
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var modePicker: some View {
        Picker("Mode", selection: $appMode) {
            Text("Import")
                .tag(AppMode.import)
                .accessibilityIdentifier("tabImport")
            Text("Analysis")
                .tag(AppMode.analyze)
                .accessibilityIdentifier("tabAnalysis")
            Text("AI Analysis")
                .tag(AppMode.aiAnalysis)
                .accessibilityIdentifier("tabAIAnalysis")
            Text("Export")
                .tag(AppMode.export)
                .accessibilityIdentifier("tabExport")
            Text("Instrument")
                .tag(AppMode.instrument)
                .accessibilityIdentifier("tabInstrument")
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityLabel("Mode")
        .accessibilityIdentifier("appModePicker")
        .frame(maxWidth: 420)
    }

    private var isRunningUITests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    private var isLocalStore: Bool {
        dataStoreController.storeMode == "local"
    }


    private var iCloudStatusText: String {
        var lines: [String] = []
        let storageLabel = isLocalStore ? "Local storage" : "iCloud storage"
        lines.append("Storage: \(storageLabel)")

        if dataStoreController.syncState.isActive {
            lines.append("Sync: \(dataStoreController.syncState.message)")
            if dataStoreController.syncState.totalBytes > 0 {
                let percent = Int((dataStoreController.syncState.progress * 100).rounded())
                let transferred = ByteCountFormatter.string(
                    fromByteCount: dataStoreController.syncState.transferredBytes,
                    countStyle: .file
                )
                let total = ByteCountFormatter.string(
                    fromByteCount: dataStoreController.syncState.totalBytes,
                    countStyle: .file
                )
                lines.append("Progress: \(percent)% (\(transferred) / \(total))")
            } else {
                let percent = Int((dataStoreController.syncState.progress * 100).rounded())
                lines.append("Progress: \(percent)%")
            }
        } else if !dataStoreController.cloudSyncEnabled {
            lines.append("Sync: Off")
        } else if dataStoreController.cloudKitUnavailable {
            lines.append("CloudKit available: no")
        } else {
            lines.append("CloudKit available: yes")
            lines.append("Sync: \(icloudLastSyncStatus)")
        }

        if storeResetOccurred {
            lines.append("Notice: Storage was reset. See Settings for details.")
        }

        return lines.joined(separator: "\n")
    }

    private var iCloudCondensedErrorText: String? {
        let message = dataStoreController.cloudKitUnavailableMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return nil }
        return message.components(separatedBy: .newlines).first
    }

    private var shouldShowSyncStatusBar: Bool {
        dataStoreController.syncState.isActive
            || !dataStoreController.syncHistory.isEmpty
            || dataStoreController.queuedActionMessage != nil
            || dataStoreController.cloudSyncEnabled
            || icloudLastSyncTimestamp > 0
    }

    private var syncStatusMessage: String {
        if let latest = dataStoreController.syncHistory.first {
            return latest.message
        }
        return dataStoreController.syncState.message
    }

    private var syncEnabledLabel: String {
        dataStoreController.cloudSyncEnabled ? "On" : "Off"
    }

    private var cloudKitAccountSummary: String {
        let defaults = UserDefaults.standard
        let account = defaults.string(forKey: ICloudDefaultsKeys.cloudKitAccountStatus) ?? "unknown"
        let containerID = defaults.string(forKey: ICloudDefaultsKeys.cloudKitContainerIdentifier) ?? "unknown"
        let env = defaults.string(forKey: ICloudDefaultsKeys.cloudKitEnvironmentLabel) ?? "unknown"
        return "Account: \(account) • Env: \(env) • Container: \(containerID)"
    }

    private var lastSyncTimestampText: String {
        guard icloudLastSyncTimestamp > 0 else { return "Never" }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: Date(timeIntervalSince1970: icloudLastSyncTimestamp))
    }

    private var lastSyncStatusLabel: String {
        icloudSyncInProgress ? "In progress" : icloudLastSyncStatus
    }

    private var lastSyncTriggerLabel: String {
        let trimmed = icloudLastSyncTrigger.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "unknown" : trimmed
    }

    private var syncStatusBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("iCloud Sync")
                    .font(.caption)
                    .foregroundColor(.secondary)

                progressToggleButton()

                Spacer()
                if dataStoreController.queuedActionMessage != nil {
                    Text("Queued")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.trailing, 6)
                } else {
                    Text(syncStatusMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .padding(.trailing, 6)
                }
            }
            Text("Enabled: \(syncEnabledLabel) • Last: \(lastSyncStatusLabel) • \(lastSyncTimestampText) • Trigger: \(lastSyncTriggerLabel)")
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(cloudKitAccountSummary)
                .font(.caption2)
                .foregroundColor(.secondary)

            let queuedMessage = dataStoreController.queuedActionMessage ?? " "
            Text(queuedMessage)
                .font(.caption2)
                .foregroundColor(.secondary)
                .opacity(dataStoreController.queuedActionMessage == nil ? 0 : 1)

            HStack {
                Button("Sync Now") {
                    requestCloudSync(reason: "manual")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!dataStoreController.cloudSyncEnabled || icloudSyncInProgress)

                Button("Force Upload") {
                    requestForceUpload(reason: "manual")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!dataStoreController.cloudSyncEnabled || icloudSyncInProgress)

                Spacer()
            }

            if !icloudProgressCollapsed {
                CloudSyncProgressView(state: dataStoreController.syncState)
                    .frame(minHeight: 96)
            }
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private func progressToggleButton() -> some View {
        let label = Image(systemName: icloudProgressCollapsed ? "chevron.down" : "chevron.up")
            .font(.caption)
        let button = Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                icloudProgressCollapsed.toggle()
            }
        } label: {
            label
        }
        .accessibilityLabel(icloudProgressCollapsed ? "Show progress" : "Hide progress")
        .controlSize(.small)

        if #available(macOS 15.0, *) {
            button.buttonStyle(.glass(.clear))
        } else {
            button.buttonStyle(.bordered)
        }
    }

    private func copyICloudStatusDetails() {
        var lines: [String] = []
        let defaults = UserDefaults.standard
        lines.append("Storage: \(isLocalStore ? "Local" : "iCloud")")
        lines.append("CloudKit enabled: \(dataStoreController.cloudSyncEnabled ? "yes" : "no")")
        lines.append("CloudKit unavailable: \(dataStoreController.cloudKitUnavailable ? "yes" : "no")")
        if let account = defaults.string(forKey: ICloudDefaultsKeys.cloudKitAccountStatus), !account.isEmpty {
            lines.append("CloudKit account: \(account)")
        }
        if let containerID = defaults.string(forKey: ICloudDefaultsKeys.cloudKitContainerIdentifier), !containerID.isEmpty {
            lines.append("CloudKit container: \(containerID)")
        }
        if let env = defaults.string(forKey: ICloudDefaultsKeys.cloudKitEnvironmentLabel), !env.isEmpty {
            lines.append("CloudKit environment: \(env)")
        }
        if !dataStoreController.cloudKitUnavailableMessage.isEmpty {
            lines.append("Unavailable message: \(dataStoreController.cloudKitUnavailableMessage)")
        }
        if !dataStoreController.syncState.isActive,
           defaults.double(forKey: "icloudLastSyncEndTimestamp") > 0,
           defaults.bool(forKey: "icloudLastSyncChangesDetected") == false {
            lines.append("Sync: No changes to sync")
        } else {
            lines.append("Sync status: \(iCloudStatusText)")
        }
        if dataStoreController.syncState.isActive {
            let percent = Int((dataStoreController.syncState.progress * 100).rounded())
            let transferred = ByteCountFormatter.string(fromByteCount: dataStoreController.syncState.transferredBytes, countStyle: .file)
            let total = ByteCountFormatter.string(fromByteCount: dataStoreController.syncState.totalBytes, countStyle: .file)
            lines.append("Sync progress: \(percent)% (\(transferred) / \(total))")
            if !dataStoreController.syncState.detail.isEmpty {
                lines.append("Sync detail: \(dataStoreController.syncState.detail)")
            }
        }
        if !dataStoreController.syncHistory.isEmpty {
            let formatter = ContentView.storedDateFormatter
            lines.append("Sync history (latest 5):")
            for entry in dataStoreController.syncHistory.prefix(5) {
                let stamp = formatter.string(from: entry.timestamp)
                let detail = entry.detail.isEmpty ? "" : " • \(entry.detail)"
                lines.append("History: \(stamp) • \(entry.message)\(detail)")
            }
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(lines.joined(separator: "\n"), forType: .string)
    }

    private var cloudKitBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "icloud.slash")
                    .font(.title3)
                    .foregroundColor(.orange)
                Text(dataStoreController.cloudKitUnavailableMessage.isEmpty
                     ? "CloudKit is unavailable. The app is using local storage until it becomes available."
                     : dataStoreController.cloudKitUnavailableMessage
                )
                .font(.caption)
                .foregroundColor(.secondary)
                Spacer()
                Button("Enable iCloud Sync") {
                    dataStoreController.setCloudSyncEnabled(true)
                }
                .buttonStyle(.bordered)
                .disabled(dataStoreController.cloudSyncEnabled && !dataStoreController.cloudKitUnavailable)
                .accessibilityIdentifier("retryCloudKitBannerButton")
                SettingsLink {
                    Text("Settings")
                }
                .buttonStyle(.link)
            }

            if dataStoreController.syncState.isActive {
                VStack(alignment: .leading, spacing: 6) {
                    Text(dataStoreController.syncState.message)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    CloudSyncProgressView(state: dataStoreController.syncState)
                }
            }
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.08))
        )
    }

    private func cloudKitProgressBanner(state: CloudSyncState) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "icloud.and.arrow.up")
                .font(.title3)
                .foregroundColor(.accentColor)
            VStack(alignment: .leading, spacing: 6) {
                Text(state.message)
                    .font(.caption)
                    .foregroundColor(.secondary)
                CloudSyncProgressView(state: state)
            }
            Spacer()
            SettingsLink {
                Text("Settings")
            }
            .buttonStyle(.link)
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.08))
        )
    }

    private var localStoreBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "externaldrive")
                .font(.title3)
                .foregroundColor(.orange)
            VStack(alignment: .leading, spacing: 6) {
                Text("Local storage in use")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("iCloud sync is enabled, but this session is still using local storage. Migration will start automatically.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            SettingsLink {
                Text("Settings")
            }
            .buttonStyle(.link)
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.08))
        )
    }

    private func applyImporters<V: View>(_ view: V) -> some View {
        view
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [UTType(filenameExtension: "spc") ?? .data],
                allowsMultipleSelection: true,
                onCompletion: handleImport(result:)
            )
            .onOpenURL { url in
                guard url.pathExtension.lowercased() == "spc" else { return }
                Task { await loadSpectra(from: [url], append: false) }
            }
    }

    private func applyAlertsAndSheets<V: View>(_ view: V) -> some View {
        view
            .alert("Error", isPresented: Binding(get: {
                errorMessage != nil
            }, set: { isPresented in
                if !isPresented { errorMessage = nil }
            })) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
            .sheet(isPresented: $showExportSheet) {
                exportSheet
            }
            .sheet(isPresented: $showWarningDetails) {
                warningDetailsSheet
            }
            .sheet(isPresented: $showInvalidDetails) {
                invalidDetailsSheet
            }
            .sheet(isPresented: $showSpfMathDetails) {
                spfMathSheet
            }
            .sheet(isPresented: $showAILogWindow) {
                aiLogSheet
            }
            .sheet(isPresented: $showInstrumentationLogWindow) {
                instrumentationLogSheet
            }
            .sheet(isPresented: $showStoredDatasetPicker) {
                storedDatasetPickerSheet
            }
            .sheet(isPresented: $showArchivedDatasetSheet) {
                archivedDatasetSheet
            }
            .confirmationDialog(archiveConfirmationTitle, isPresented: $showArchiveConfirmation, titleVisibility: .visible) {
                Button("Archive", role: .destructive) {
                    archivePendingDatasets()
                }
                Button("Cancel", role: .cancel) {
                    pendingArchiveDatasetIDs.removeAll()
                }
            } message: {
                Text(archiveConfirmationMessage)
            }
            .confirmationDialog("Remove duplicate datasets?", isPresented: $showDuplicateCleanupConfirm, titleVisibility: .visible) {
                Button("Remove Duplicates", role: .destructive) {
                    removeDuplicateDatasets()
                }
                Button("Cancel", role: .cancel) {
                    duplicateCleanupTargetIDs.removeAll()
                    duplicateCleanupMessage = ""
                }
            } message: {
                Text(duplicateCleanupMessage)
            }
    }

    private func applyProcessingChangeHandlers<V: View>(_ view: V) -> some View {
        view
            .onChange(of: useAlignment) { _, _ in
                applyAlignmentIfNeeded()
            }
            .onChange(of: smoothingMethod) { _, _ in
                applyProcessing()
            }
            .onChange(of: smoothingWindow) { _, _ in
                applyProcessing()
            }
            .onChange(of: sgWindow) { _, _ in
                applyProcessing()
            }
            .onChange(of: sgOrder) { _, _ in
                applyProcessing()
            }
            .onChange(of: baselineMethod) { _, _ in
                applyProcessing()
            }
            .onChange(of: normalizationMethod) { _, _ in
                applyProcessing()
            }
            .onChange(of: spfDisplayModeRawValue) { _, _ in
                rebuildCaches()
            }
    }

    private func applySelectionChangeHandlers<V: View>(_ view: V) -> some View {
        view
            .onChange(of: yAxisMode) { _, _ in
                rebuildCaches()
                updatePeaks()
            }
            .onChange(of: detectPeaks) { _, _ in
                updatePeaks()
            }
            .onChange(of: peakMinHeight) { _, _ in
                updatePeaks()
            }
            .onChange(of: peakMinDistance) { _, _ in
                updatePeaks()
            }
            .onChange(of: selectedSpectrumIndex) { _, _ in
                rebuildCaches()
                updatePeaks()
                updateAIEstimate()
            }
            .onChange(of: selectedSpectrumIndices) { _, _ in
                if showSelectedOnly {
                    logSelectedOnlySelectionChange()
                }
                rebuildCaches()
                updatePeaks()
                updateAIEstimate()
            }
            .onChange(of: overlayLimit) { _, _ in
                rebuildCaches()
            }
            .onChange(of: palette) { _, _ in
                rebuildCaches()
            }
            .onChange(of: includeInvalidInPlots) { _, newValue in
                if !newValue {
                    selectedInvalidItemIDs.removeAll()
                }
                rebuildCaches()
            }
    }

    private func applyAIChangeHandlers<V: View>(_ view: V) -> some View {
        view
            .onChange(of: aiPromptPresetRawValue) { _, _ in
                updateAIEstimate()
            }
            .onChange(of: aiDefaultScopeRawValue) { _, _ in
                updateAIEstimate()
            }
            .onChange(of: aiScopeOverride) { _, _ in
                updateAIEstimate()
            }
            .onChange(of: useCustomPrompt) { _, _ in
                updateAIEstimate()
            }
            .onChange(of: aiCustomPrompt) { _, _ in
                updateAIEstimate()
            }
    }

    private func applyDiagnosticsLogListeners<V: View>(_ view: V) -> some View {
        view
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("AISettingsDiagnosticsLog"))) { notification in
                guard aiDiagnosticsEnabled else { return }
                guard let line = notification.object as? String else { return }
                appendAILogEntry(line)
            }
            .onReceive(NotificationCenter.default.publisher(for: .instrumentationLog)) { notification in
                guard instrumentationOutputInApp else { return }
                guard let line = notification.object as? String else { return }
                appendInstrumentationLogEntry(line)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                if aiClearLogsOnQuit {
                    aiLogEntries.removeAll()
                    persistAILogEntries()
                }
            }
    }

    private var contentArea: some View {
        TabView(selection: $appMode) {
            importPanel
                .tabItem {
                    Label("Import", systemImage: "tray.and.arrow.down")
                }
                .tag(AppMode.import)

            analysisPanel
                .tabItem {
                    Label("Analysis", systemImage: "waveform.path.ecg")
                }
                .tag(AppMode.analyze)

            aiAnalysisPanel
                .tabItem {
                    Label("AI Analysis", systemImage: "sparkles")
                }
                .tag(AppMode.aiAnalysis)

            exportPanel
                .tabItem {
                    Label("Export", systemImage: "tray.and.arrow.up")
                }
                .tag(AppMode.export)

            instrumentPanel
                .tabItem {
                    Label("Instrument", systemImage: "dial.medium")
                }
                .tag(AppMode.instrument)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var importPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Import SPC Files")
                        .font(.title3)
                        .bold()
                    Spacer()
                    Button("Browse Files") {
                        appendOnImport = false
                        showImporter = true
                    }
                        .glassButtonStyle(isProminent: true)
                }

                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6, 6]))
                    .foregroundColor(.secondary.opacity(0.4))
                    .frame(height: 180)
                    .overlay(
                        VStack(spacing: 8) {
                            Image(systemName: "waveform.path.ecg")
                                .font(.system(size: 32))
                                .foregroundColor(.secondary)
                            Text("Drop .spc files here or use Browse")
                                .foregroundColor(.secondary)
                        }
                    )

                if !storedDatasets.isEmpty {
                    Text("Stored Datasets: \(storedDatasets.count)")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Search stored datasets", text: $datasetSearchText)
                            .textFieldStyle(.roundedBorder)

                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 8) {
                                ForEach(filteredStoredDatasets) { dataset in
                                    storedDatasetRow(dataset)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .frame(minHeight: 120, maxHeight: 220)

                        HStack(spacing: 12) {
                            Button("Load Selected") {
                                loadStoredDatasetSelection(append: false)
                            }
                            .glassButtonStyle(isProminent: true)

                            Button("Append Selected") {
                                loadStoredDatasetSelection(append: true)
                            }
                            .glassButtonStyle()

                            Button("Validate Headers") {
                                validateStoredDatasetSelection()
                            }
                            .glassButtonStyle()

                            Button("Validate Loaded") {
                                validateLoadedSpectra()
                            }
                            .glassButtonStyle()

                            Button("Archive Selected") {
                                deleteStoredDatasetSelection()
                            }
                            .glassButtonStyle()
                            .disabled(selectedStoredDatasetIDs.isEmpty)

                            Button("Remove Duplicates") {
                                prepareDuplicateCleanup()
                            }
                            .glassButtonStyle()

                            Button("Archived…") {
                                showArchivedDatasetSheet = true
                            }
                            .glassButtonStyle()
                        }
                    }
                    .padding(12)
                    .background(panelBackground)
                    .cornerRadius(12)
                } else if !archivedDatasets.isEmpty {
                    Button("View Archived Datasets") {
                        showArchivedDatasetSheet = true
                    }
                    .glassButtonStyle()
                }

                if !validationLogEntries.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Validation Log")
                                .font(.headline)
                            Spacer()
                            Button("Copy") {
                                copyValidationLog()
                            }
                            .buttonStyle(.link)
                            Button("Save Log…") {
                                saveValidationLogToFile()
                            }
                            .buttonStyle(.link)
                            Button("Clear") {
                                validationLogEntries.removeAll()
                            }
                            .buttonStyle(.link)
                        }

                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 6) {
                                ForEach(validationLogEntries) { entry in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(formattedTimestamp(entry.timestamp))
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        Text(entry.message)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(minHeight: 80, maxHeight: 160)
                    }
                    .padding(12)
                    .background(panelBackground)
                    .cornerRadius(12)
                }

                if !spectra.isEmpty {
                    Text("Recent Imports")
                        .font(.headline)
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(displayedSpectra.prefix(12).indices, id: \.self) { index in
                            spectrumRow(for: index)
                        }
                    }
                }
            }
            .padding(24)
        }
    }

    private var storedDatasetPickerSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Add Stored Dataset")
                    .font(.title3)
                    .bold()
                Spacer()
                Button("Close") {
                    showStoredDatasetPicker = false
                    storedDatasetPickerSelection.removeAll()
                }
                .glassButtonStyle()
            }

            if storedDatasets.isEmpty {
                Text("No stored datasets available. Import new spectra in the Import tab.")
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
                if !archivedDatasets.isEmpty {
                    Button("View Archived Datasets") {
                        showArchivedDatasetSheet = true
                    }
                    .glassButtonStyle()
                    .padding(.top, 8)
                }
            } else {
                TextField("Search stored datasets", text: $datasetSearchText)
                    .textFieldStyle(.roundedBorder)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(filteredStoredDatasets) { dataset in
                            storedDatasetPickerRow(dataset)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(minHeight: 240)

                HStack(spacing: 12) {
                    Button("Load Selected") {
                        loadStoredDatasetPickerSelection(append: false)
                        showStoredDatasetPicker = false
                        storedDatasetPickerSelection.removeAll()
                    }
                    .glassButtonStyle(isProminent: true)
                    .disabled(storedDatasetPickerSelection.isEmpty)

                    Button("Append Selected") {
                        loadStoredDatasetPickerSelection(append: true)
                        showStoredDatasetPicker = false
                        storedDatasetPickerSelection.removeAll()
                    }
                    .glassButtonStyle()
                    .disabled(storedDatasetPickerSelection.isEmpty)
                }
            }
        }
        .padding(24)
        .frame(minWidth: 720, minHeight: 420)
    }

    private var archivedDatasetSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Archived Datasets")
                    .font(.title3)
                    .bold()
                Spacer()
                Button("Close") {
                    showArchivedDatasetSheet = false
                    archivedDatasetSelection.removeAll()
                }
                .glassButtonStyle()
            }

            if archivedDatasets.isEmpty {
                Text("No archived datasets available.")
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
            } else {
                TextField("Search archived datasets", text: $archivedSearchText)
                    .textFieldStyle(.roundedBorder)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(filteredArchivedDatasets) { dataset in
                            archivedDatasetRow(dataset)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(minHeight: 240)

                HStack(spacing: 12) {
                    Button("Restore Selected") {
                        restoreArchivedSelection()
                    }
                    .glassButtonStyle(isProminent: true)
                    .disabled(archivedDatasetSelection.isEmpty)

                    Button("Delete Permanently") {
                        requestPermanentDeleteSelection()
                    }
                    .glassButtonStyle()
                    .disabled(archivedDatasetSelection.isEmpty)
                }
            }
        }
        .padding(24)
        .frame(minWidth: 720, minHeight: 420)
        .sheet(isPresented: $showPermanentDeleteSheet) {
            permanentDeleteSheet
        }
    }

    private var permanentDeleteSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(permanentDeleteConfirmationTitle)
                .font(.title3)
                .bold()
            Text(permanentDeleteConfirmationMessage)
                .foregroundColor(.secondary)
            HStack {
                Button("Cancel") {
                    showPermanentDeleteSheet = false
                    pendingPermanentDeleteIDs.removeAll()
                }
                .glassButtonStyle()
                Spacer()
                Button("Delete Permanently") {
                    showPermanentDeleteSheet = false
                    deleteArchivedDatasets()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
        .padding(24)
        .frame(minWidth: 420)
    }

    private var analysisPanel: some View {
        HStack(alignment: .top, spacing: 16) {
            if !expandChart {
                leftPanel
                    .frame(width: 260)
            }

            centerPanel
                .frame(maxWidth: .infinity)

            if !expandChart {
                rightPanel
                    .frame(width: 320)
            }
        }
        .padding(16)
    }

    private var exportPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Export")
                        .font(.title3)
                        .bold()
                    Spacer()
                    Picker("Format", selection: $exportFormat) {
                        ForEach(ExportFormat.allCases) { value in
                            Text(value.rawValue).tag(value)
                        }
                    }
                    .pickerStyle(.menu)
                }

                exportFormFields

                HStack(spacing: 12) {
                    Button("Export") {
                        let options = ExportOptions(
                            title: exportTitle,
                            operatorName: exportOperator,
                            notes: exportNotes,
                            includeProcessing: exportIncludeProcessing,
                            includeMetadata: exportIncludeMetadata
                        )
                        switch exportFormat {
                        case .csv:
                            exportCSV(options: options)
                        case .jcamp:
                            exportJCAMP(options: options)
                        case .excel:
                            exportExcelXLSX(options: options)
                        case .wordReport:
                            exportWordDOCX(options: options)
                        case .pdfReport:
                            exportPDFReport(options: options)
                        case .htmlReport:
                            exportHTMLReport(options: options)
                        }
                    }
                    .disabled(displayedSpectra.isEmpty)
                    .glassButtonStyle(isProminent: true)

                    Button("Preview In Analyzer") {
                        appMode = .analyze
                    }
                    .glassButtonStyle()
                }

                spcHeaderPreviewPanel

                Text("Export Preview")
                    .font(.headline)
                chartSection
            }
            .padding(24)
        }
    }

    private var leftPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Datasets")
                    .font(.headline)
                Spacer()
                Button {
                    showStoredDatasetPicker = true
                } label: {
                    Image(systemName: "plus")
                }
                .help("Add stored spectra")
                .glassButtonStyle()

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        expandChart.toggle()
                    }
                } label: {
                    Image(systemName: expandChart ? "rectangle.arrowtriangle.2.inward" : "rectangle.arrowtriangle.2.outward")
                }
                .help(expandChart ? "Show Side Panels" : "Expand Chart")
                .glassButtonStyle()
            }

            if displayedSpectra.isEmpty {
                Text("No spectra loaded")
                    .foregroundColor(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(displayedSpectra.indices, id: \.self) { index in
                            spectrumRow(for: index)
                        }
                        if showInvalidInline {
                            ForEach(invalidItems) { item in
                                invalidSpectrumRow(item)
                            }
                        }
                    }
                }
            }

            if !invalidItems.isEmpty, !showInvalidInline {
                Divider()
                invalidItemsPanel
            }
        }
        .padding(12)
        .background(panelBackground)
        .cornerRadius(16)
    }

    private var centerPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let dashboardMetrics {
                dashboardPanel(dashboardMetrics)
            }
            summaryStrip
            chartSection
            pointReadoutPanel
            overlayControls
        }
        .padding(12)
        .background(panelBackground)
        .cornerRadius(16)
    }

    private var invalidItemsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Invalid Items")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Button("View All") { showInvalidDetails = true }
                    .buttonStyle(.link)
            }

            let preview = Array(invalidItems.prefix(4))
            ForEach(preview) { item in
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .font(.caption)
                            .lineLimit(1)
                        Text(item.fileName)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(item.reason)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer(minLength: 8)
                    tagChip("Invalid")
                }
                .padding(6)
                .background(Color.orange.opacity(0.08))
                .cornerRadius(8)
            }

            if invalidItems.count > preview.count {
                Text("\(invalidItems.count - preview.count) more…")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var rightPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                pipelinePanel
                batchComparePanel
                inspectorPanel
            }
            .padding(12)
        }
        .background(panelBackground)
        .cornerRadius(16)
    }

    private var aiAnalysisPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("AI Analysis Workspace")
                    .font(.title3)
                    .bold()
                Spacer()
                Button("Open Logs") {
                    showAILogWindow = true
                }
                .glassButtonStyle()
            }

            HSplitView {
                aiLeftPane
                    .frame(minWidth: 280, idealWidth: 320, maxWidth: 360)
                aiRightPane
                    .frame(minWidth: 420)
            }
        }
        .padding(24)
    }

    private var instrumentPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Instrument Control")
                        .font(.title3)
                        .bold()
                    Spacer()
                    Button("View Logs") {
                        showInstrumentationLogWindow = true
                    }
                    .glassButtonStyle()
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Status")
                        .font(.headline)
                    Text(instrumentManager.statusMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let connected = instrumentManager.connectedDevice {
                        Text("Connected: \(connected.model) • \(connected.address)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(12)
                .background(panelBackground)
                .cornerRadius(16)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Device Discovery")
                            .font(.headline)
                        Spacer()
                        if instrumentManager.isScanning {
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                    }

                    if instrumentManager.devices.isEmpty {
                        Text("No devices discovered yet.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(instrumentManager.devices) { device in
                            let isSelected = device.id == selectedInstrumentID
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(device.model)
                                        .font(.caption)
                                    Text(device.address)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                if isSelected {
                                    tagChip("Selected")
                                }
                            }
                            .padding(8)
                            .background(isSelected ? Color.blue.opacity(0.12) : Color.gray.opacity(0.08))
                            .cornerRadius(8)
                            .onTapGesture {
                                selectedInstrumentID = device.id
                            }
                        }
                    }

                    HStack(spacing: 8) {
                        Button("Scan") {
                            instrumentManager.scan()
                        }
                        Button("Add Manual Endpoint") {
                            errorMessage = "Manual endpoint entry is not implemented yet."
                        }
                    }
                    .glassButtonStyle()
                }
                .padding(12)
                .background(panelBackground)
                .cornerRadius(16)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Connection")
                        .font(.headline)
                    HStack(spacing: 8) {
                        Button("Connect") {
                            if let device = selectedInstrument {
                                instrumentManager.connect(to: device)
                            }
                        }
                        .disabled(selectedInstrument == nil || instrumentManager.isConnected)
                        Button("Disconnect") {
                            instrumentManager.disconnect()
                        }
                        .disabled(!instrumentManager.isConnected)
                    }
                    .glassButtonStyle()
                }
                .padding(12)
                .background(panelBackground)
                .cornerRadius(16)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Command Queue")
                        .font(.headline)
                    if instrumentManager.commandQueue.isEmpty {
                        Text("Queue is empty.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(instrumentManager.commandQueue) { command in
                            Text(command.name)
                                .font(.caption)
                        }
                    }
                    HStack(spacing: 8) {
                        Button("Get Status") {
                            instrumentManager.send(InstrumentCommand(name: "Get Status"))
                        }
                        Button("Start Scan") {
                            instrumentManager.send(InstrumentCommand(name: "Start Scan"))
                        }
                        Button("Stop") {
                            instrumentManager.send(InstrumentCommand(name: "Stop"))
                        }
                    }
                    .disabled(!instrumentManager.isConnected)
                    .glassButtonStyle()
                }
                .padding(12)
                .background(panelBackground)
                .cornerRadius(16)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Recent Responses")
                        .font(.headline)
                    if instrumentManager.responses.isEmpty {
                        Text("No responses yet.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(instrumentManager.responses.suffix(6), id: \.timestamp) { response in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(formattedTimestamp(response.timestamp))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(response.message)
                                    .font(.caption)
                            }
                        }
                    }
                }
                .padding(12)
                .background(panelBackground)
                .cornerRadius(16)
            }
            .padding(24)
        }
    }

    private var summaryStrip: some View {
        let selectionCount = selectedSpectra.count
        let selectedLabel = selectionCount == 1 ? (selectedSpectrum?.name ?? "None") : "\(selectionCount) samples"

        return glassGroup(spacing: 12) {
            HStack(spacing: 10) {
                metricChip(title: "Spectra", value: "\(displayedSpectra.count)")
                metricChip(title: "Selected", value: selectedLabel)

                if selectionCount == 1, let metrics = selectedMetrics {
                    metricChip(title: "UVA/UVB", value: String(format: "%.3f", metrics.uvaUvbRatio))
                    metricChip(title: "Critical λ", value: String(format: "%.1f nm", metrics.criticalWavelength))
                }

                if selectionCount > 1, let stats = selectedMetricsStats {
                    metricChip(title: "Avg UVA/UVB", value: String(format: "%.3f", stats.avgUvaUvb))
                    metricChip(title: "Avg Critical λ", value: String(format: "%.1f nm", stats.avgCritical))
                    metricChip(title: "UVA/UVB Range", value: String(format: "%.3f–%.3f", stats.uvaUvbRange.lowerBound, stats.uvaUvbRange.upperBound))
                    metricChip(title: "Critical λ Range", value: String(format: "%.1f–%.1f nm", stats.criticalRange.lowerBound, stats.criticalRange.upperBound))
                }

                if selectionCount == 1, let display = displaySpfMetric {
                    metricChip(title: display.label, value: String(format: "%.1f", display.value))
                }

                if selectionCount == 1 {
                    switch spfDisplayMode {
                    case .colipa:
                        if let estimated = estimatedSpfValue {
                            metricChip(title: SpfDisplayMode.calibrated.label, value: String(format: "%.1f", estimated))
                        }
                    case .calibrated:
                        if let colipa = colipaSpfValue {
                            metricChip(title: SpfDisplayMode.colipa.label, value: String(format: "%.1f", colipa))
                        }
                    }
                }

                metricChip(title: "Metrics Range", value: "290–400 nm")

                Spacer(minLength: 0)
            }
        }
    }

    private func dashboardPanel(_ metrics: DashboardMetrics) -> some View {
        let complianceText = String(format: "%.0f%%", metrics.compliancePercent)
        let complianceDetail = "\(metrics.complianceCount)/\(max(metrics.totalCount, 1)) SPF≥30"
        let uvaRangeText = String(format: "%.2f–%.2f", metrics.uvaUvbRange.lowerBound, metrics.uvaUvbRange.upperBound)
        let avgUvaText = String(format: "%.2f", metrics.avgUvaUvb)
        let criticalRangeText = String(format: "%.1f–%.1f nm", metrics.criticalRange.lowerBound, metrics.criticalRange.upperBound)
        let avgCriticalText = String(format: "%.1f nm", metrics.avgCritical)
        let trendText: String = {
            guard let drop = metrics.postIncubationDropPercent else { return "No incubation split" }
            return String(format: "%.1f%% drop", drop)
        }()

        let maxCount = metrics.heatmapBins.map { $0.count }.max() ?? 1

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Dataset Dashboard")
                    .font(.headline)
                Spacer()
                Text("Samples: \(metrics.totalCount)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 12) {
                dashboardCard(title: "Compliance", value: complianceText, detail: complianceDetail)
                dashboardCard(title: "Avg UVA/UVB", value: avgUvaText, detail: "Range: \(uvaRangeText)")
                dashboardCard(title: "Avg Critical λ", value: avgCriticalText, detail: "Range: \(criticalRangeText)")
                dashboardCard(title: "Trends", value: trendText, detail: "Low critical: \(metrics.lowCriticalCount)")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Batch UVA/UVB Heatmap")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Chart(metrics.heatmapBins) { bin in
                    RectangleMark(
                        xStart: .value("UVA/UVB Min", bin.xRange.lowerBound),
                        xEnd: .value("UVA/UVB Max", bin.xRange.upperBound),
                        yStart: .value("Critical Min", bin.yRange.lowerBound),
                        yEnd: .value("Critical Max", bin.yRange.upperBound)
                    )
                    .foregroundStyle(Color.accentColor.opacity(0.15 + (0.75 * (Double(bin.count) / Double(maxCount)))))
                }
                .chartXAxis {
                    AxisMarks(position: .bottom, values: .automatic(desiredCount: 5))
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 5))
                }
                .frame(height: 140)
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.02))
        .cornerRadius(12)
    }

    private func dashboardCard(title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.headline)
            Text(detail)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.03))
        .cornerRadius(10)
    }

    private var overlayControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Toggle("All Spectra", isOn: $showAllSpectra)
                    .toggleStyle(.switch)
                Toggle("Selected Only", isOn: $showSelectedOnly)
                    .toggleStyle(.switch)
                Toggle("Average", isOn: $showAverage)
                    .toggleStyle(.switch)
                Toggle("Legend", isOn: $showLegend)
                    .toggleStyle(.switch)
                Toggle("Labels", isOn: $showLabels)
                    .toggleStyle(.switch)
            }

            if !invalidItems.isEmpty {
                HStack(spacing: 12) {
                    Toggle("Show Invalid", isOn: $showInvalidInline)
                        .toggleStyle(.switch)
                    Toggle("Plot Invalid", isOn: $includeInvalidInPlots)
                        .toggleStyle(.switch)
                        .disabled(showSelectedOnly)
                        .help(showSelectedOnly ? "Plot invalid only in All Spectra mode." : "Overlay invalid spectra on the chart.")
                }
            }

            HStack(spacing: 12) {
                Text("Y Axis")
                Picker("Y Axis", selection: $yAxisMode) {
                    ForEach(SpectralYAxisMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Text("Palette")
                Picker("Palette", selection: $palette) {
                    ForEach(SpectrumPalette.allCases) { value in
                        Text(value.rawValue).tag(value)
                    }
                }
                .frame(width: 160)

                if showAllSpectra {
                    Text("Overlay")
                    Stepper(value: $overlayLimit, in: 1...200, step: 1) {
                        Text("\(overlayLimit)")
                            .frame(width: 40, alignment: .leading)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Text("X Zoom")
                        .frame(width: 60, alignment: .leading)
                    Slider(value: $chartVisibleDomain, in: 40...140, step: 5)
                    Text("\(Int(chartVisibleDomain)) nm")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 70, alignment: .trailing)
                }

                HStack(spacing: 12) {
                    Text("Y Zoom")
                        .frame(width: 60, alignment: .leading)
                    Slider(value: $chartVisibleYDomain, in: 0.2...1.2, step: 0.1)
                    Text(String(format: "%.1f", chartVisibleYDomain))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 70, alignment: .trailing)
                }
            }
        }
    }

    private var pipelinePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Processing Pipeline")
                    .font(.headline)
                Spacer()
                Button(showPipelineDetails ? "Collapse" : "Expand") {
                    showPipelineDetails.toggle()
                }
                .buttonStyle(.plain)
            }

            if showPipelineDetails {
                DisclosureGroup("Alignment", isExpanded: .constant(true)) {
                    Toggle("Align X-Axis", isOn: $useAlignment)
                        .toggleStyle(.switch)
                }

                DisclosureGroup("Smoothing", isExpanded: .constant(true)) {
                    Picker("Smoothing", selection: $smoothingMethod) {
                        ForEach(SmoothingMethod.allCases) { method in
                            Text(method.rawValue).tag(method)
                        }
                    }
                    .pickerStyle(.segmented)

                    if smoothingMethod == .movingAverage {
                        Stepper(value: $smoothingWindow, in: 3...51, step: 2) {
                            Text("Window: \(smoothingWindow)")
                        }
                    }

                    if smoothingMethod == .savitzkyGolay {
                        Stepper(value: $sgWindow, in: 5...51, step: 2) {
                            Text("SG Window: \(sgWindow)")
                        }
                        Stepper(value: $sgOrder, in: 2...6, step: 1) {
                            Text("Order: \(sgOrder)")
                        }
                    }
                }

                DisclosureGroup("Baseline", isExpanded: .constant(true)) {
                    Picker("Baseline", selection: $baselineMethod) {
                        ForEach(BaselineMethod.allCases) { method in
                            Text(method.rawValue).tag(method)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                DisclosureGroup("Normalization", isExpanded: .constant(true)) {
                    Picker("Normalization", selection: $normalizationMethod) {
                        ForEach(NormalizationMethod.allCases) { method in
                            Text(method.rawValue).tag(method)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                DisclosureGroup("Peaks", isExpanded: .constant(true)) {
                    Toggle("Detect Peaks", isOn: $detectPeaks)
                        .toggleStyle(.switch)
                    Toggle("Show Peaks", isOn: $showPeaks)
                        .toggleStyle(.switch)
                        .disabled(!detectPeaks)

                    if detectPeaks {
                        HStack(spacing: 8) {
                            Text("Min Height")
                            TextField("Min Height", value: $peakMinHeight, format: .number)
                                .frame(width: 80)
                            Text("Min Distance")
                            Stepper(value: $peakMinDistance, in: 1...100, step: 1) {
                                Text("\(peakMinDistance)")
                                    .frame(width: 40, alignment: .leading)
                            }
                        }
                        Button("Export Peaks CSV") { exportPeaksCSV() }
                            .disabled(peaks.isEmpty)
                    }
                }
            }

            Button("Apply Pipeline") {
                runPipeline()
            }
            .glassButtonStyle(isProminent: true)
        }
    }

    private var inspectorPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Inspector")
                    .font(.headline)
                Spacer()
                Button(showInspectorDetails ? "Collapse" : "Expand") {
                    showInspectorDetails.toggle()
                }
                .buttonStyle(.plain)
            }

            if showInspectorDetails {
                let selectionCount = selectedSpectra.count

                if selectionCount == 1, let spectrum = selectedSpectrum {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(spectrum.name)
                            .font(.subheadline)
                            .bold()
                        Text("Points: \(spectrum.y.count)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else if selectionCount > 1 {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Multiple samples selected")
                            .font(.subheadline)
                            .bold()
                        Text("Samples: \(selectionCount)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if selectionCount == 1, let metrics = selectedMetrics {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(format: "Critical Wavelength: %.1f nm", metrics.criticalWavelength))
                        Text(String(format: "UVA/UVB Ratio: %.3f", metrics.uvaUvbRatio))
                        Text(String(format: "Mean UVB Transmittance: %.3f", metrics.meanUVBTransmittance))
                        Text("Metrics Range: 290–400 nm")
                            .foregroundColor(.secondary)
                    }
                    .font(.caption)
                } else if selectionCount > 1, let stats = selectedMetricsStats {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(format: "Avg Critical Wavelength: %.1f nm", stats.avgCritical))
                        Text(String(format: "Avg UVA/UVB Ratio: %.3f", stats.avgUvaUvb))
                        Text(String(format: "Critical λ Range: %.1f–%.1f nm", stats.criticalRange.lowerBound, stats.criticalRange.upperBound))
                        Text(String(format: "UVA/UVB Range: %.3f–%.3f", stats.uvaUvbRange.lowerBound, stats.uvaUvbRange.upperBound))
                        Text("Metrics Range: 290–400 nm")
                            .foregroundColor(.secondary)
                    }
                    .font(.caption)
                }

                spcHeaderSection
                correlationSection
            }
        }
    }

    private var batchComparePanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Batch Compare")
                    .font(.headline)
                Spacer()
                Text("Baseline: first selected")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            let rows = batchCompareRows
            if rows.isEmpty {
                Text("Select at least 2 spectra to compare deltas.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text("Sample")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("SPF")
                            .frame(width: 60, alignment: .trailing)
                        Text("ΔSPF")
                            .frame(width: 60, alignment: .trailing)
                        Text("UVA/UVB")
                            .frame(width: 70, alignment: .trailing)
                        Text("ΔUVA")
                            .frame(width: 60, alignment: .trailing)
                        Text("Critical")
                            .frame(width: 70, alignment: .trailing)
                        Text("ΔCrit")
                            .frame(width: 60, alignment: .trailing)
                    }
                    .font(.caption2)
                    .foregroundColor(.secondary)

                    ForEach(rows) { row in
                        HStack(spacing: 8) {
                            Text(row.name)
                                .font(.caption)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(row.spf.map { String(format: "%.1f", $0) } ?? "—")
                                .font(.caption)
                                .frame(width: 60, alignment: .trailing)
                            Text(row.deltaSpf.map { String(format: "%+.1f", $0) } ?? "—")
                                .font(.caption)
                                .frame(width: 60, alignment: .trailing)
                            Text(row.uvaUvb.map { String(format: "%.2f", $0) } ?? "—")
                                .font(.caption)
                                .frame(width: 70, alignment: .trailing)
                            Text(row.deltaUvaUvb.map { String(format: "%+.2f", $0) } ?? "—")
                                .font(.caption)
                                .frame(width: 60, alignment: .trailing)
                            Text(row.critical.map { String(format: "%.1f", $0) } ?? "—")
                                .font(.caption)
                                .frame(width: 70, alignment: .trailing)
                            Text(row.deltaCritical.map { String(format: "%+.1f", $0) } ?? "—")
                                .font(.caption)
                                .frame(width: 60, alignment: .trailing)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.03))
        .cornerRadius(12)
    }

    private var batchCompareRows: [BatchCompareRow] {
        let spectra = selectedSpectra
        guard spectra.count >= 2 else { return [] }

        var rows: [BatchCompareRow] = []
        rows.reserveCapacity(spectra.count)

        var baselineMetrics: SpectralMetrics?
        var baselineSpf: Double?

        for spectrum in spectra {
            guard let metrics = SpectralMetricsCalculator.metrics(x: spectrum.x, y: spectrum.y, yAxisMode: yAxisMode) else { continue }
            let spfValue = spfValue(for: spectrum, metrics: metrics)

            if baselineMetrics == nil {
                baselineMetrics = metrics
                baselineSpf = spfValue
            }

            let deltaSpf = spfValue.flatMap { spf in
                baselineSpf.map { spf - $0 }
            }
            let deltaUva = baselineMetrics.map { metrics.uvaUvbRatio - $0.uvaUvbRatio }
            let deltaCritical = baselineMetrics.map { metrics.criticalWavelength - $0.criticalWavelength }

            rows.append(
                BatchCompareRow(
                    name: spectrum.name,
                    spf: spfValue,
                    deltaSpf: deltaSpf,
                    uvaUvb: metrics.uvaUvbRatio,
                    deltaUvaUvb: deltaUva,
                    critical: metrics.criticalWavelength,
                    deltaCritical: deltaCritical
                )
            )
        }

        return rows
    }

    private func spfValue(for spectrum: ShimadzuSpectrum, metrics: SpectralMetrics) -> Double? {
        switch spfDisplayMode {
        case .colipa:
            return SpectralMetricsCalculator.colipaSpf(x: spectrum.x, y: spectrum.y, yAxisMode: yAxisMode)
        case .calibrated:
            return calibrationResult?.predict(metrics: metrics)
        }
    }

    private var spcHeaderSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("SPC Header")
                .font(.caption)
                .foregroundColor(.secondary)

            if let header = activeHeader {
                if let fileName = activeHeaderFileName {
                    Text(fileName)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Text("Instrument: \(header.sourceInstrumentText.isEmpty ? "Unknown" : header.sourceInstrumentText)")
                    .font(.caption)
                Text("Experiment: \(header.experimentType.label) (code \(header.experimentType.rawValue))")
                    .font(.caption)
                Text("Points: \(header.pointCount)")
                    .font(.caption)
                Text(String(format: "X Range: %.4f – %.4f", header.firstX, header.lastX))
                    .font(.caption)
                Text("X Units: \(header.xUnit.formatted)")
                    .font(.caption)
                Text("Y Units: \(header.yUnit.formatted)")
                    .font(.caption)
                if !header.fileType.labels.isEmpty {
                    Text("Flags: \(header.fileType.labels.joined(separator: ", "))")
                        .font(.caption)
                }
                if !header.memo.isEmpty {
                    Text("Memo: \(header.memo)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            } else {
                Text("No SPC header loaded.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.top, 4)
    }

    private var spcHeaderPreviewPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SPC Header")
                .font(.headline)
            if let header = activeHeader {
                VStack(alignment: .leading, spacing: 4) {
                    if let fileName = activeHeaderFileName {
                        Text(fileName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Text("Instrument: \(header.sourceInstrumentText.isEmpty ? "Unknown" : header.sourceInstrumentText)")
                        .font(.caption)
                    Text("Experiment: \(header.experimentType.label) (code \(header.experimentType.rawValue))")
                        .font(.caption)
                    Text("Points: \(header.pointCount)")
                        .font(.caption)
                    Text(String(format: "X Range: %.4f – %.4f", header.firstX, header.lastX))
                        .font(.caption)
                    Text("X Units: \(header.xUnit.formatted)")
                        .font(.caption)
                    Text("Y Units: \(header.yUnit.formatted)")
                        .font(.caption)
                    if !header.fileType.labels.isEmpty {
                        Text("Flags: \(header.fileType.labels.joined(separator: ", "))")
                            .font(.caption)
                    }
                }
            } else {
                Text("No SPC header available for export.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(panelBackground)
        .cornerRadius(12)
    }

    private var aiLeftPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("AI Controls")
                            .font(.headline)
                        Spacer()
                        Button(showAIDetails ? "Collapse" : "Expand") {
                            showAIDetails.toggle()
                        }
                        .buttonStyle(.plain)
                    }

                    if showAIDetails {
                        if !aiEnabled {
                            Text("AI analysis is disabled. Enable it in Settings.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Picker("Scope", selection: Binding(
                            get: { effectiveAIScope },
                            set: { aiScopeOverride = $0 }
                        )) {
                            ForEach(AISelectionScope.allCases) { scope in
                                Text(scope.label).tag(scope)
                            }
                        }
                        .pickerStyle(.segmented)

                        HStack(spacing: 8) {
                            Button(aiIsRunning ? "Running…" : "Run AI Analysis") {
                                runAIAnalysis()
                            }
                            .disabled(!aiCanRunAnalysis || aiIsRunning)

                            Button("Save…") {
                                saveAIResultToDisk()
                            }
                            .disabled(aiResult == nil)

                            Button("Copy Output") {
                                copyAIOutput()
                            }
                            .disabled(aiResult == nil)
                        }
                        .glassButtonStyle(isProminent: true)

                        if aiIsRunning {
                            ProgressView()
                        }

                        if let aiErrorMessage {
                            Text(aiErrorMessage)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                }
                .padding(12)
                .background(panelBackground)
                .cornerRadius(16)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Template Gallery")
                        .font(.headline)
                    ForEach(aiPresetTemplates, id: \.preset) { item in
                        HStack(alignment: .top, spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.preset.label)
                                    .font(.subheadline)
                                Text(item.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button("Use") {
                                useCustomPrompt = false
                                aiPromptPreset = item.preset
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(8)
                        .background(Color.white.opacity(0.04))
                        .cornerRadius(8)
                    }
                }
                .padding(12)
                .background(panelBackground)
                .cornerRadius(16)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Token Budget")
                        .font(.headline)
                    ProgressView(value: min(Double(aiEstimatedTokens), Double(aiMaxTokens)), total: Double(max(aiMaxTokens, 1)))
                    Text("Estimated tokens: \(aiEstimatedTokens) / \(aiMaxTokens)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if aiEstimatedTokens > aiMaxTokens {
                        Text("Warning: estimated output may be truncated.")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    HStack(spacing: 12) {
                        Slider(value: $aiCostPerThousandTokens, in: 0.0...0.2, step: 0.005)
                        Text(String(format: "$%.3f/1K", aiCostPerThousandTokens))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 70, alignment: .trailing)
                    }
                    let estimatedCost = (Double(aiEstimatedTokens) / 1000.0) * aiCostPerThousandTokens
                    Text(String(format: "Estimated cost: $%.3f", estimatedCost))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(12)
                .background(panelBackground)
                .cornerRadius(16)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Response History")
                        .font(.headline)
                    if aiHistoryEntries.isEmpty {
                        Text("No prior AI responses yet.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(aiHistoryEntries) { entry in
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(formattedTimestamp(entry.timestamp)) • \(entry.preset.label)")
                                        .font(.caption)
                                    Text("Scope: \(entry.scope.label)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Button("A") { aiHistorySelectionA = entry.id }
                                    .buttonStyle(.bordered)
                                Button("B") { aiHistorySelectionB = entry.id }
                                    .buttonStyle(.bordered)
                            }
                            .padding(6)
                            .background(Color.white.opacity(0.04))
                            .cornerRadius(8)
                        }

                        if let diffText = aiHistoryDiffText {
                            ScrollView {
                                Text(diffText)
                                    .font(.system(.caption, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 160)
                            .padding(6)
                            .background(Color.black.opacity(0.15))
                            .cornerRadius(8)
                        }
                    }
                }
                .padding(12)
                .background(panelBackground)
                .cornerRadius(16)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Run Context")
                        .font(.headline)
                    Text("Scope: \(effectiveAIScope.label)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Spectra: \(aiSpectraForScope().count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Estimated tokens: \(aiEstimatedTokens)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(12)
                .background(panelBackground)
                .cornerRadius(16)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Source Context")
                        .font(.headline)
                    let spectra = aiSpectraForScope()
                    if spectra.isEmpty {
                        Text("No spectra included.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        let preview = spectra.prefix(6)
                        ForEach(Array(preview.enumerated()), id: \.offset) { _, item in
                            Text(item.name)
                                .font(.caption)
                        }
                        if spectra.count > preview.count {
                            Text("+\(spectra.count - preview.count) more")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    Text("YAxis: \(yAxisMode.rawValue)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Metrics Range: \(Int(chartWavelengthRange.lowerBound))–\(Int(chartWavelengthRange.upperBound)) nm")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let header = activeHeader {
                        if !header.sourceInstrumentText.isEmpty {
                            Text("Instrument: \(header.sourceInstrumentText)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Text("X Units: \(header.xUnit.formatted)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Y Units: \(header.yUnit.formatted)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(12)
                .background(panelBackground)
                .cornerRadius(16)

                HStack(spacing: 8) {
                    Button("Logs…") {
                        showAILogWindow = true
                    }
                    .glassButtonStyle()

                    if aiDiagnosticsEnabled {
                        Text("Diagnostics On")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(12)
        }
        .background(panelBackground)
        .cornerRadius(16)
    }

    private var aiRightPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Custom Prompt")
                            .font(.headline)
                        Spacer()
                        Toggle("Use", isOn: $useCustomPrompt)
                            .toggleStyle(.switch)
                    }

                    ZStack(alignment: .topLeading) {
                        if aiCustomPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("Describe the analysis you want, constraints, and preferred output format.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.top, 8)
                                .padding(.horizontal, 6)
                        }
                        TextEditor(text: $aiCustomPrompt)
                            .frame(minHeight: 100, maxHeight: 140)
                            .disabled(!useCustomPrompt)
                    }
                    .padding(8)
                    .background(panelBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                    .cornerRadius(12)
                }
                .padding(12)
                .background(panelBackground)
                .cornerRadius(16)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Preset")
                        .font(.headline)
                    Picker("Preset", selection: Binding(
                        get: { aiPromptPreset },
                        set: { aiPromptPreset = $0 }
                    )) {
                        ForEach(AIPromptPreset.allCases) { preset in
                            Text(preset.label).tag(preset)
                        }
                    }
                    .disabled(useCustomPrompt)
                }
                .padding(12)
                .background(panelBackground)
                .cornerRadius(16)

                VStack(alignment: .leading, spacing: 8) {
                    Text("AI Response")
                        .font(.headline)

                    if let aiResult {
                        HStack(alignment: .top, spacing: 12) {
                            ScrollView {
                                Text(aiResult.text)
                                    .font(.system(size: aiResponseTextSize))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(minHeight: 260)

                            VStack(alignment: .leading, spacing: 10) {
                                aiSidebarEditableSection("Key Insights", text: $aiSidebarInsightsText)
                                aiSidebarEditableSection("Risks/Warnings", text: $aiSidebarRisksText)
                                aiSidebarEditableSection("Next Steps", text: $aiSidebarActionsText)
                                Button("Sync back to response") {
                                    syncSidebarToAIResponse()
                                }
                                .buttonStyle(.bordered)
                                if !aiSidebarHasStructuredSections {
                                    Text("No structured headings found. Use explicit headings to auto-fill.")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .frame(minWidth: 220, maxWidth: 260, alignment: .leading)
                        }
                        .onAppear {
                            updateSidebarFromAIResult(aiResult)
                        }
                        .onChange(of: aiResult.text) { _, _ in
                            updateSidebarFromAIResult(aiResult)
                        }
                    } else {
                        Text("No AI output yet.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(12)
                .background(panelBackground)
                .cornerRadius(16)

                if let structured = aiStructuredOutput {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Structured Summary")
                            .font(.headline)
                        if let summary = structured.summary, !summary.isEmpty {
                            Text(summary)
                                .font(.caption)
                        }

                        if let recommendations = structured.recommendations, !recommendations.isEmpty {
                            Text("Recommendations")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            ForEach(recommendations) { rec in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(rec.ingredient) • \(rec.amount)")
                                        .font(.caption)
                                    if let rationale = rec.rationale, !rationale.isEmpty {
                                        Text(rationale)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(6)
                                .background(Color.white.opacity(0.04))
                                .cornerRadius(8)
                            }
                        }
                    }
                    .padding(12)
                    .background(panelBackground)
                    .cornerRadius(16)
                }
            }
            .padding(12)
        }
        .background(panelBackground)
        .cornerRadius(16)
    }

    private var aiLogSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("AI Diagnostics Log")
                    .font(.headline)
                Spacer()
                Toggle("Auto-scroll", isOn: $aiLogAutoScroll)
                    .toggleStyle(.switch)
            }

            if !aiDiagnosticsEnabled {
                Text("Enable Diagnostics in Settings to capture AI request and response logs.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(aiLogEntries) { entry in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(formattedTimestamp(entry.timestamp))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(entry.message)
                                    .font(.caption)
                            }
                            .id(entry.id)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: aiLogEntries.count) { _, _ in
                    guard aiLogAutoScroll, let last = aiLogEntries.last else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
                .onAppear {
                    guard aiLogAutoScroll, let last = aiLogEntries.last else { return }
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
            .padding(10)
            .background(panelBackground)
            .cornerRadius(12)

            HStack(spacing: 8) {
                Button("Clear") {
                    aiLogEntries.removeAll()
                    persistAILogEntries()
                }
                .disabled(aiLogEntries.isEmpty)

                Button("Copy") {
                    copyAILogToPasteboard()
                }
                .disabled(aiLogEntries.isEmpty)

                Button("Export…") {
                    exportAILogToFile()
                }
                .disabled(aiLogEntries.isEmpty)

                Spacer()

                Button("Close") {
                    showAILogWindow = false
                }
            }
            .glassButtonStyle()
        }
        .padding(16)
        .frame(minWidth: 720, minHeight: 420)
    }

    private var instrumentationLogSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Instrumentation Log")
                    .font(.headline)
                Spacer()
                Toggle("Auto-scroll", isOn: $instrumentationLogAutoScroll)
                    .toggleStyle(.switch)
            }

            if !instrumentationOutputInApp {
                Text("Enable In-App Logs in Settings to capture instrumentation output.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(instrumentationLogEntries) { entry in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(formattedTimestamp(entry.timestamp))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(entry.message)
                                    .font(.caption)
                            }
                            .id(entry.id)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: instrumentationLogEntries.count) { _, _ in
                    guard instrumentationLogAutoScroll, let last = instrumentationLogEntries.last else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
                .onAppear {
                    guard instrumentationLogAutoScroll, let last = instrumentationLogEntries.last else { return }
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
            .padding(10)
            .background(panelBackground)
            .cornerRadius(12)

            HStack(spacing: 8) {
                Button("Clear") {
                    instrumentationLogEntries.removeAll()
                    persistInstrumentationLogEntries()
                }
                .disabled(instrumentationLogEntries.isEmpty)

                Button("Copy") {
                    copyInstrumentationLogToPasteboard()
                }
                .disabled(instrumentationLogEntries.isEmpty)

                Button("Export…") {
                    exportInstrumentationLogToFile()
                }
                .disabled(instrumentationLogEntries.isEmpty)

                Spacer()

                Button("Close") {
                    showInstrumentationLogWindow = false
                }
            }
            .glassButtonStyle()
        }
        .padding(16)
        .frame(minWidth: 720, minHeight: 420)
    }

    private var bottomTray: some View {
        HStack(alignment: .center, spacing: 16) {
            statusPanel
            Spacer()
            HStack(spacing: 8) {
                Button("Export Excel") {
                    exportFormat = .excel
                    showExportSheet = true
                }
                .disabled(displayedSpectra.isEmpty)
                Button("Export JCAMP") {
                    exportFormat = .jcamp
                    showExportSheet = true
                }
                .disabled(displayedSpectra.isEmpty)
            }
            .glassButtonStyle(isProminent: true)
        }
        .padding(16)
        .background(panelBackground)
    }

    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(statusMessage)
                .foregroundColor(.secondary)
            if let warningMessage {
                HStack(spacing: 8) {
                    Text(warningMessage)
                        .font(.caption)
                        .foregroundColor(.orange)
                    if !warningDetails.isEmpty {
                        Button("Details") { showWarningDetails = true }
                            .buttonStyle(.link)
                    }
                }
            }
            if !invalidItems.isEmpty {
                HStack(spacing: 8) {
                    Text("Invalid spectra: \(invalidItems.count)")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Button("View") { showInvalidDetails = true }
                        .buttonStyle(.link)
                }
            }
            if !spectra.isEmpty {
                Text("Spectra loaded: \(spectra.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if detectPeaks {
                Text("Peaks detected: \(peaks.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var backgroundView: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(.windowBackgroundColor),
                    Color(.windowBackgroundColor).opacity(0.92)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.blue.opacity(0.08))
                .frame(width: 420, height: 420)
                .offset(x: 280, y: -220)

            Circle()
                .fill(Color.orange.opacity(0.08))
                .frame(width: 360, height: 360)
                .offset(x: -260, y: 220)
        }
        .ignoresSafeArea()
    }

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Color(.windowBackgroundColor).opacity(0.6))
    }

    private var exportFormFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Title", text: $exportTitle)
            TextField("Operator", text: $exportOperator)
            TextField("Notes", text: $exportNotes, axis: .vertical)
                .lineLimit(3, reservesSpace: true)
            Toggle("Include Processing Settings", isOn: $exportIncludeProcessing)
            Toggle("Include Metadata", isOn: $exportIncludeMetadata)
        }
        .padding(12)
        .background(panelBackground)
        .cornerRadius(12)
    }

    private func decodedMetadata(for dataset: StoredDataset) -> ShimadzuSPCMetadata? {
        guard let data = dataset.metadataJSON else { return nil }
        return try? JSONDecoder().decode(ShimadzuSPCMetadata.self, from: data)
    }

    private func datasetUniquenessKey(fileHash: String?, sourcePath: String?) -> String? {
        if let fileHash, !fileHash.isEmpty { return "hash:\(fileHash)" }
        if let sourcePath, !sourcePath.isEmpty { return "path:\(sourcePath.lowercased())" }
        return nil
    }

    private var filteredStoredDatasets: [StoredDataset] {
        let query = datasetSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return storedDatasets }
        let lowercased = query.lowercased()
        return storedDatasets.filter { dataset in
            if dataset.fileName.lowercased().contains(lowercased) { return true }
            if let metadata = decodedMetadata(for: dataset) {
                if metadata.dataSetNames.contains(where: { $0.lowercased().contains(lowercased) }) { return true }
                if metadata.directoryEntryNames.contains(where: { $0.lowercased().contains(lowercased) }) { return true }
            }
            if let hash = dataset.fileHash, hash.lowercased().contains(lowercased) { return true }
            return false
        }
    }

    private var filteredArchivedDatasets: [StoredDataset] {
        let query = archivedSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return archivedDatasets }
        let lowercased = query.lowercased()
        return archivedDatasets.filter { dataset in
            if dataset.fileName.lowercased().contains(lowercased) { return true }
            if let metadata = decodedMetadata(for: dataset) {
                if metadata.dataSetNames.contains(where: { $0.lowercased().contains(lowercased) }) { return true }
                if metadata.directoryEntryNames.contains(where: { $0.lowercased().contains(lowercased) }) { return true }
            }
            if let hash = dataset.fileHash, hash.lowercased().contains(lowercased) { return true }
            return false
        }
    }

    private func datasetNamePreview(_ datasets: [StoredDataset]) -> String {
        let names = datasets.map { $0.fileName }
        guard !names.isEmpty else { return "" }
        let preview = names.prefix(3).joined(separator: ", ")
        let remainder = names.count - 3
        if remainder > 0 {
            return "\(preview) (+\(remainder) more)"
        }
        return preview
    }

    private var archiveConfirmationTitle: String {
        let count = pendingArchiveDatasetIDs.count
        return count == 1 ? "Archive Stored Dataset?" : "Archive \(count) Stored Datasets?"
    }

    private var archiveConfirmationMessage: String {
        let datasets = storedDatasets.filter { pendingArchiveDatasetIDs.contains($0.id) }
        let preview = datasetNamePreview(datasets)
        let base = "Archived datasets can be restored from the Archived Datasets window."
        if preview.isEmpty {
            return base
        }
        return "\(base)\n\n\(preview)"
    }

    private var permanentDeleteConfirmationTitle: String {
        let count = effectivePermanentDeleteIDs.count
        return count == 1 ? "Delete Archived Dataset?" : "Delete \(count) Archived Datasets?"
    }

    private var permanentDeleteConfirmationMessage: String {
        let datasets = archivedDatasets.filter { effectivePermanentDeleteIDs.contains($0.id) }
        let preview = datasetNamePreview(datasets)
        let base = "This permanently deletes the archived datasets and cannot be undone."
        if preview.isEmpty {
            return base
        }
        return "\(base)\n\n\(preview)"
    }

    private var effectivePermanentDeleteIDs: Set<UUID> {
        pendingPermanentDeleteIDs.isEmpty ? archivedDatasetSelection : pendingPermanentDeleteIDs
    }

    private func sha256Hex(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func storedDatasetRow(_ dataset: StoredDataset) -> some View {
        let isSelected = selectedStoredDatasetIDs.contains(dataset.id)
        let spectrumCount = dataset.spectraItems.count
        let dataSetCount = decodedMetadata(for: dataset)?.dataSetNames.count ?? 0
        let detail = dataSetCount > 0
            ? "\(spectrumCount) spectra • \(dataSetCount) datasets"
            : "\(spectrumCount) spectra"
        let dateLabel = ContentView.storedDateFormatter.string(from: dataset.importedAt)

        return Button {
            if isSelected {
                selectedStoredDatasetIDs.remove(dataset.id)
            } else {
                selectedStoredDatasetIDs.insert(dataset.id)
            }
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(dataset.fileName)
                        .font(.subheadline)
                        .lineLimit(1)
                    Text(detail)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(dateLabel)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer(minLength: 8)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
                }
            }
            .padding(8)
            .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }

    private func archivedDatasetRow(_ dataset: StoredDataset) -> some View {
        let isSelected = archivedDatasetSelection.contains(dataset.id)
        let spectrumCount = dataset.spectraItems.count
        let dataSetCount = decodedMetadata(for: dataset)?.dataSetNames.count ?? 0
        let detail = dataSetCount > 0
            ? "\(spectrumCount) spectra • \(dataSetCount) datasets"
            : "\(spectrumCount) spectra"
        let archivedLabel = dataset.archivedAt.map { ContentView.storedDateFormatter.string(from: $0) } ?? "Unknown"

        return Button {
            if isSelected {
                archivedDatasetSelection.remove(dataset.id)
            } else {
                archivedDatasetSelection.insert(dataset.id)
            }
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(dataset.fileName)
                        .font(.subheadline)
                        .lineLimit(1)
                    Text(detail)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Archived \(archivedLabel)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer(minLength: 8)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
                }
            }
            .padding(8)
            .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }

    private func storedDatasetPickerRow(_ dataset: StoredDataset) -> some View {
        let isSelected = storedDatasetPickerSelection.contains(dataset.id)
        let spectrumCount = dataset.spectraItems.count
        let metadata = decodedMetadata(for: dataset)
        let dataSetCount = metadata?.dataSetNames.count ?? 0
        let summaryLines = metadataSummaryLines(metadata)
        let metadataLines = metadataDetailLines(metadata)

        return HStack(spacing: 10) {
            Button {
                if isSelected {
                    storedDatasetPickerSelection.remove(dataset.id)
                } else {
                    storedDatasetPickerSelection.insert(dataset.id)
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(isSelected ? .accentColor : .secondary)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(dataset.fileName)
                            .font(.subheadline)
                            .lineLimit(1)
                        Text("\(spectrumCount) spectra • \(dataSetCount) datasets")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        ForEach(summaryLines, id: \.self) { line in
                            Text(line)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 8)

            Button("Show Details") {
                datasetDetailPopoverID = dataset.id
            }
            .buttonStyle(.link)
            .popover(isPresented: Binding(
                get: { datasetDetailPopoverID == dataset.id },
                set: { isPresented in
                    if !isPresented { datasetDetailPopoverID = nil }
                }
            )) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Metadata Details")
                            .font(.headline)
                        ForEach(metadataLines, id: \.self) { line in
                            Text(line)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(16)
                }
                .frame(minWidth: 420, minHeight: 320)
            }
        }
        .padding(10)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.white.opacity(0.03))
        .cornerRadius(10)
    }

    private func formatBytes(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private func metadataSummaryLines(_ metadata: ShimadzuSPCMetadata?) -> [String] {
        guard let metadata else { return ["Metadata: unavailable"] }
        var lines: [String] = []
        lines.append("File Size: \(formatBytes(metadata.fileSizeBytes))")
        lines.append("Header Bytes: \(metadata.headerInfoByteCount)")
        if let header = metadata.mainHeader {
            lines.append("Experiment: \(header.experimentType) • X: \(header.xUnit) • Y: \(header.yUnit)")
        }
        let preview = metadata.dataSetNames.prefix(3).joined(separator: ", ")
        if !preview.isEmpty {
            let extra = max(0, metadata.dataSetNames.count - 3)
            lines.append("Datasets: \(preview)\(extra > 0 ? " +\(extra) more" : "")")
        }
        return lines
    }

    private func metadataDetailLines(_ metadata: ShimadzuSPCMetadata?) -> [String] {
        guard let metadata else { return ["Metadata: unavailable"] }
        var lines: [String] = []
        lines.append("File: \(metadata.fileName)")
        lines.append("File Size: \(formatBytes(metadata.fileSizeBytes))")
        lines.append("Header Bytes: \(metadata.headerInfoByteCount)")
        lines.append("Datasets: \(metadata.dataSetNames.joined(separator: ", "))")
        lines.append("Directory Entries: \(metadata.directoryEntryNames.joined(separator: ", "))")

        if let header = metadata.mainHeader {
            lines.append("SPC Version: \(header.spcVersion)")
            lines.append("File Type Flags: \(header.fileTypeFlags) (\(header.fileType))")
            lines.append("Experiment Type: \(header.experimentTypeCode) (\(header.experimentType))")
            lines.append("Y Exponent: \(header.yExponent)")
            lines.append("Point Count: \(header.pointCount)")
            lines.append(String(format: "First X: %.6f", header.firstX))
            lines.append(String(format: "Last X: %.6f", header.lastX))
            lines.append("Subfile Count: \(header.subfileCount)")
            lines.append("X Units: \(header.xUnitsCode) (\(header.xUnit))")
            lines.append("Y Units: \(header.yUnitsCode) (\(header.yUnit))")
            lines.append("Z Units: \(header.zUnitsCode) (\(header.zUnit))")
            lines.append("Posting Disposition: \(header.postingDisposition)")
            lines.append("Compressed Date: \(spcDateString(header.compressedDate))")
            lines.append("Resolution: \(header.resolutionText)")
            lines.append("Instrument: \(header.sourceInstrumentText)")
            lines.append("Peak Point #: \(header.peakPointNumber)")
            lines.append("Memo: \(header.memo)")
            lines.append("Custom Axis Combined: \(header.customAxisCombined)")
            lines.append("Custom Axis X: \(header.customAxisX)")
            lines.append("Custom Axis Y: \(header.customAxisY)")
            lines.append("Custom Axis Z: \(header.customAxisZ)")
            lines.append("Log Block Offset: \(header.logBlockOffset)")
            lines.append("File Modification Flag: \(header.fileModificationFlag)")
            lines.append("Processing Code: \(header.processingCode)")
            lines.append("Calibration Level + 1: \(header.calibrationLevelPlusOne)")
            lines.append("Submethod Injection #: \(header.subMethodInjectionNumber)")
            lines.append(String(format: "Concentration Factor: %.6f", header.concentrationFactor))
            lines.append("Method File: \(header.methodFile)")
            lines.append(String(format: "Z Subfile Increment: %.6f", header.zSubfileIncrement))
            lines.append("W Plane Count: \(header.wPlaneCount)")
            lines.append(String(format: "W Plane Increment: %.6f", header.wPlaneIncrement))
            lines.append("W Units: \(header.wAxisUnitsCode) (\(header.wUnit))")
        } else {
            lines.append("SPC Header: unavailable")
        }

        return lines
    }

    private func spcDateString(_ date: SPCCompressedDate) -> String {
        if date.year == 0 && date.month == 0 && date.day == 0 && date.hour == 0 && date.minute == 0 {
            return "Unknown"
        }
        return String(format: "%04d-%02d-%02d %02d:%02d", date.year, date.month, date.day, date.hour, date.minute)
    }

    private func spectrumRow(for index: Int) -> some View {
        let spectrum = displayedSpectra[index]
        let isSelected = selectedSpectrumIndices.contains(index)
        return HStack(spacing: 8) {
            Button {
                toggleSelection(for: index)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(spectrum.name)
                        .font(.caption)
                        .lineLimit(1)
                    tagRow(for: spectrum.name)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button(role: .destructive) {
                removeSpectrum(at: index)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Remove sample")
        }
        .padding(8)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        .cornerRadius(8)
    }

    private func invalidSpectrumRow(_ item: InvalidSpectrumItem) -> some View {
        let isSelected = selectedInvalidItemIDs.contains(item.id)
        return HStack(spacing: 8) {
            Button {
                toggleInvalidSelection(item)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.caption)
                        .lineLimit(1)
                    Text(item.fileName)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(item.reason)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .disabled(!includeInvalidInPlots)

            tagChip("Invalid")
        }
        .padding(8)
        .background(isSelected ? Color.orange.opacity(0.2) : Color.orange.opacity(0.1))
        .cornerRadius(8)
    }

    private func toggleSelection(for index: Int) {
        if selectedSpectrumIndices.contains(index) {
            selectedSpectrumIndices.remove(index)
        } else {
            selectedSpectrumIndices.insert(index)
            selectedSpectrumIndex = index
        }
    }

    private func removeSpectrum(at index: Int) {
        guard index >= 0, index < spectra.count else { return }

        spectra.remove(at: index)
        alignedSpectra = []
        processedSpectra = []
        pointCache = [:]

        var updatedSelection: Set<Int> = []
        for selected in selectedSpectrumIndices {
            if selected == index { continue }
            updatedSelection.insert(selected > index ? selected - 1 : selected)
        }
        selectedSpectrumIndices = updatedSelection

        if spectra.isEmpty {
            selectedSpectrumIndex = 0
            selectedSpectrumIndices = []
            statusMessage = "No spectra loaded."
            warningMessage = nil
            warningDetails = []
            updatePeaks()
            rebuildCaches()
            updateAIEstimate()
            return
        }

        selectedSpectrumIndex = min(max(selectedSpectrumIndex, 0), spectra.count - 1)
        statusMessage = "Loaded \(spectra.count) spectra."
        applyAlignmentIfNeeded()
        updatePeaks()
        updateAIEstimate()
    }

    private func tagRow(for name: String) -> some View {
        let tags = spectrumTags(for: name)
        return HStack(spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                tagChip(tag)
            }
        }
    }

    private func metricChip(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.caption)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassSurface(cornerRadius: 12)
    }

    private func tagChip(_ title: String) -> some View {
        Text(title)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .glassSurface(cornerRadius: 10)
    }



    private var chartSection: some View {
        Group {
            if hasRenderableSeries {
                let baseChart = Chart {
                    chartSeriesMarks
                    selectedPointMarks
                    peakMarks
                }
                .chartLegend(showLegend ? .visible : .hidden)
                .chartXAxisLabel("Wavelength (nm)")
                .chartYAxisLabel("Intensity")
                .chartXScale(domain: chartWavelengthRange)
                .chartScrollableAxes([.horizontal, .vertical])
                .chartXSelection(value: $chartSelectionX)
                .chartXVisibleDomain(length: max(chartVisibleDomain, 1))
                .chartYVisibleDomain(length: max(chartVisibleYDomain, 0.01))
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        let plotRect: CGRect = {
                            if let plotFrame = proxy.plotFrame {
                                return geo[plotFrame]
                            }
                            return .zero
                        }()

                        ZStack(alignment: .topLeading) {
                            let updateHover: (CGPoint) -> Void = { location in
                                guard plotRect.contains(location) else { return }
                                chartHoverLocation = location
                                let xPosition = location.x - plotRect.origin.x
                                if let xValue: Double = proxy.value(atX: xPosition) {
                                    chartSelectionX = xValue
                                }
                            }

                            let updateSelection: (CGPoint) -> Void = { location in
                                guard plotRect.contains(location) else { return }
                                let xPosition = location.x - plotRect.origin.x
                                let yPosition = location.y - plotRect.origin.y
                                guard let xValue: Double = proxy.value(atX: xPosition),
                                      let yValue: Double = proxy.value(atY: yPosition) else { return }
                                chartSelectionX = xValue
                                selectSpectrumNearest(toX: xValue, y: yValue)
                            }

                            Rectangle()
                                .fill(Color.clear)
                                .contentShape(Rectangle())
                                .onContinuousHover { phase in
                                    switch phase {
                                    case .active(let location):
                                        updateHover(location)
                                    case .ended:
                                        chartHoverLocation = nil
                                        chartSelectionX = nil
                                    }
                                }
                                .gesture(
                                    DragGesture(minimumDistance: 0)
                                        .onChanged { value in
                                            updateHover(value.location)
                                        }
                                        .onEnded { value in
                                            updateSelection(value.location)
                                        }
                                )

                            if let selectedPoint,
                               let hover = chartHoverLocation {
                                chartTooltipView(for: selectedPoint, plotRect: plotRect, location: hover)
                            }
                        }
                    }
                }
                .frame(minHeight: 320)

                if chartSeriesNames.isEmpty {
                    baseChart
                } else {
                    baseChart.chartForegroundStyleScale(
                        domain: chartSeriesNames,
                        range: chartPaletteRange
                    )
                }

                if showLabels && showAllSpectra {
                    labelsSection
                }

                if let first = displayedSpectra.first {
                    Text("Showing: \(first.name)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                Text("No spectrum loaded yet")
                    .foregroundColor(.secondary)
            }
        }
    }

    private var correlationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("COLIPA-Style Correlation")
                    .font(.headline)
                Spacer()
                if selectedSpectrum != nil, selectedMetrics != nil {
                    Button("Math…") {
                        showSpfMathDetails = true
                    }
                    .buttonStyle(.link)
                }
            }
            if let spectrum = selectedSpectrum, let metrics = selectedMetrics {
                let matched = SPFLabelStore.matchLabel(for: spectrum.name)
                let calibration = calibrationResult

                VStack(alignment: .leading, spacing: 4) {
                    Text("Sample: \(spectrum.name)")
                        .font(.subheadline)
                    Text("Matched Label: \(matched?.name ?? "None")")
                        .foregroundColor(.secondary)
                    if let spf = matched?.spf {
                        Text(String(format: "Label SPF: %.1f", spf))
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(String(format: "Critical Wavelength: %.1f nm", metrics.criticalWavelength))
                    Text(String(format: "UVA/UVB Ratio: %.3f", metrics.uvaUvbRatio))
                }

                if let colipa = colipaSpfValue {
                    Text(String(format: "COLIPA SPF: %.1f", colipa))
                        .font(.headline)
                }

                if let calibration = calibration, let estimated = estimatedSpfValue {
                    Text(String(format: "Estimated SPF (calibrated): %.1f", estimated))
                    Text(String(format: "Calibration: n=\(calibration.sampleCount), R²=%.3f, RMSE=%.2f", calibration.r2, calibration.rmse))
                        .foregroundColor(.secondary)
                } else {
                    Text("Calibration requires at least 2 labeled samples.")
                        .foregroundColor(.secondary)
                }
            } else {
                Text("No spectrum selected for correlation.")
                    .foregroundColor(.secondary)
            }
        }
        .padding(.top, 4)
    }

    private var spfMathSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SPF Math Details")
                .font(.headline)
            if let spectrum = selectedSpectrum, let metrics = selectedMetrics {
                let calibration = calibrationResult
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Spectrum: \(spectrum.name)")
                                .font(.subheadline)
                            Text("YAxis Mode: \(yAxisMode.rawValue)")
                                .foregroundColor(.secondary)
                            Text("UVB: 290–320 nm | UVA: 320–400 nm | Total: 290–400 nm")
                                .foregroundColor(.secondary)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Conversions")
                                .font(.subheadline)
                            if yAxisMode == .absorbance {
                                Text("Transmittance T = 10^(−Absorbance)")
                            } else {
                                Text("Absorbance A = −log10(max(T, 1e−9))")
                            }
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Integrated Areas (Trapezoid Rule)")
                                .font(.subheadline)
                            Text(String(format: "UVB Area: %.4f", metrics.uvbArea))
                            Text(String(format: "UVA Area: %.4f", metrics.uvaArea))
                            Text(String(format: "UVA/UVB Ratio: %.4f", metrics.uvaUvbRatio))
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Critical Wavelength")
                                .font(.subheadline)
                            Text("Wavelength where cumulative absorbance reaches 90% of total (290–400 nm)")
                                .foregroundColor(.secondary)
                            Text(String(format: "Critical Wavelength: %.2f nm", metrics.criticalWavelength))
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Mean UVB Transmittance")
                                .font(.subheadline)
                            Text(String(format: "Mean UVB T: %.4f", metrics.meanUVBTransmittance))
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("COLIPA-Style SPF")
                                .font(.subheadline)
                            Text("SPF = Σ E(λ)·I(λ) / Σ E(λ)·I(λ)·T(λ)")
                                .foregroundColor(.secondary)
                            if let colipa = colipaSpfValue {
                                Text(String(format: "COLIPA SPF: %.2f", colipa))
                            } else {
                                Text("COLIPA SPF unavailable for this spectrum.")
                                    .foregroundColor(.secondary)
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Calibration Model")
                                .font(.subheadline)
                            if let calibration {
                                let features: [Double] = [
                                    1.0,
                                    metrics.uvbArea,
                                    metrics.uvaArea,
                                    metrics.criticalWavelength,
                                    metrics.uvaUvbRatio,
                                    metrics.meanUVBTransmittance
                                ]
                                let logSpf = zip(calibration.coefficients, features).map(*).reduce(0, +)
                                let predicted = max(exp(logSpf), 0.0)

                                Text("log(SPF) = Σ(bᵢ × featureᵢ)")
                                Text("SPF = exp(log(SPF))")
                                Text(String(format: "Estimated SPF (calibrated): %.2f", predicted))

                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(Array(zip(calibration.featureNames, calibration.coefficients).enumerated()), id: \.offset) { _, item in
                                        Text(String(format: "%@: %.6f", item.0, item.1))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }

                                Text(String(format: "Calibration: n=%d, R²=%.3f, RMSE=%.2f", calibration.sampleCount, calibration.r2, calibration.rmse))
                                    .foregroundColor(.secondary)
                            } else {
                                Text("Calibration requires at least 2 labeled samples.")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            } else {
                Text("No spectrum selected for correlation.")
                    .foregroundColor(.secondary)
            }

            HStack {
                Button("Copy Math") {
                    copySpfMathToPasteboard()
                }
                .buttonStyle(.link)
                Spacer()
                Button("Close") { showSpfMathDetails = false }
            }
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 520)
    }

    private var labelsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(seriesToPlot) { series in
                HStack(spacing: 8) {
                    Circle()
                        .fill(series.color)
                        .frame(width: 8, height: 8)
                    Text(series.name)
                        .font(.caption)
                }
            }
        }
        .padding(.top, 6)
    }


    private var exportSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Export \(exportFormat.rawValue)")
                .font(.headline)
            exportFormFields
            HStack {
                Button("Cancel") { showExportSheet = false }
                Button("Export") {
                    let options = ExportOptions(
                        title: exportTitle,
                        operatorName: exportOperator,
                        notes: exportNotes,
                        includeProcessing: exportIncludeProcessing,
                        includeMetadata: exportIncludeMetadata
                    )
                    switch exportFormat {
                    case .csv:
                        exportCSV(options: options)
                    case .jcamp:
                        exportJCAMP(options: options)
                    case .excel:
                        exportExcelXLSX(options: options)
                    case .wordReport:
                        exportWordDOCX(options: options)
                    case .pdfReport:
                        exportPDFReport(options: options)
                    case .htmlReport:
                        exportHTMLReport(options: options)
                    }
                    showExportSheet = false
                }
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private var warningDetailsSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Skipped Datasets")
                .font(.headline)
            if warningDetails.isEmpty {
                Text("No skipped datasets reported.")
                    .foregroundColor(.secondary)
            } else {
                List(warningDetails, id: \.self) { detail in
                    Text(detail)
                }
            }
            HStack {
                Spacer()
                Button("Close") { showWarningDetails = false }
            }
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 360)
    }

    private var invalidDetailsSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Invalid Spectra")
                .font(.headline)
            if invalidItems.isEmpty {
                Text("No invalid spectra reported.")
                    .foregroundColor(.secondary)
            } else {
                List(invalidItems) { item in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                                .font(.caption)
                            Text(item.fileName)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(item.reason)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        tagChip("Invalid")
                    }
                }
            }
            HStack {
                Spacer()
                Button("Close") { showInvalidDetails = false }
            }
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 360)
    }

    private func runPipeline() {
        let start = Date()
        Instrumentation.log("Pipeline run started", area: .processing, level: .info, details: "spectra=\(spectra.count)")

        applyAlignmentIfNeeded()
        applyProcessing()
        updatePeaks()
        rebuildCaches()
        lastAppliedSettings = currentProcessingSettings()

        if aiEnabled && aiAutoRun {
            runAIAnalysis()
        }

        let duration = Date().timeIntervalSince(start)
        Instrumentation.log("Pipeline run completed", area: .processing, level: .info, duration: duration)
    }

    private func currentProcessingSettings() -> ProcessingSettings {
        ProcessingSettings(
            useAlignment: useAlignment,
            smoothingMethod: smoothingMethod,
            smoothingWindow: smoothingWindow,
            sgWindow: sgWindow,
            sgOrder: sgOrder,
            baselineMethod: baselineMethod,
            normalizationMethod: normalizationMethod,
            showAllSpectra: showAllSpectra,
            showAverage: showAverage,
            yAxisMode: yAxisMode,
            overlayLimit: overlayLimit,
            showLegend: showLegend,
            showLabels: showLabels,
            palette: palette,
            detectPeaks: detectPeaks,
            peakMinHeight: peakMinHeight,
            peakMinDistance: peakMinDistance,
            showPeaks: showPeaks
        )
    }

    private func applyProcessingSettings(_ settings: ProcessingSettings) {
        useAlignment = settings.useAlignment
        smoothingMethod = settings.smoothingMethod
        smoothingWindow = settings.smoothingWindow
        sgWindow = settings.sgWindow
        sgOrder = settings.sgOrder
        baselineMethod = settings.baselineMethod
        normalizationMethod = settings.normalizationMethod
        showAllSpectra = settings.showAllSpectra
        showAverage = settings.showAverage
        yAxisMode = settings.yAxisMode
        overlayLimit = settings.overlayLimit
        showLegend = settings.showLegend
        showLabels = settings.showLabels
        palette = settings.palette
        detectPeaks = settings.detectPeaks
        peakMinHeight = settings.peakMinHeight
        peakMinDistance = settings.peakMinDistance
        showPeaks = settings.showPeaks
        runPipeline()
    }

    private func runAIAnalysis() {
        guard aiEnabled else { return }

        Instrumentation.log(
            "AI analysis requested",
            area: .aiAnalysis,
            level: .info,
            details: "scope=\(effectiveAIScope.rawValue) spectra=\(aiSpectraForScope().count)"
        )

        let cacheKey = aiCacheKey()
        if let cached = aiCache[cacheKey] {
            Instrumentation.log("AI cache hit", area: .aiAnalysis, level: .info)
            aiResult = cached
            aiStructuredOutput = nil
            aiErrorMessage = nil
            appendAIHistory(result: cached)
            updateSidebarFromAIResult(cached)
            return
        }

        Task {
            await MainActor.run {
                aiIsRunning = true
                aiErrorMessage = nil
                aiStructuredOutput = nil
            }
            do {
                try await runOpenAIAnalysis(cacheKey: cacheKey)
            } catch {
                logAIDiagnostics("AI analysis failed", error: error)
                await MainActor.run {
                    aiErrorMessage = error.localizedDescription
                }
            }
            await MainActor.run {
                aiIsRunning = false
            }
        }
    }

    private func resolvedOpenAIEndpointURL(from endpoint: String) -> URL? {
        if let url = URL(string: endpoint), url.scheme != nil {
            return url
        }
        return URL(string: "https://\(endpoint)")
    }

    private func logAIDiagnostics(_ message: String, error: Error? = nil, endpoint: String? = nil, payloadSize: Int? = nil) {
        var detailParts: [String] = []
        if let endpoint { detailParts.append("endpoint=\(endpoint)") }
        if let error { detailParts.append("error=\(error.localizedDescription)") }
        let details = detailParts.isEmpty ? nil : detailParts.joined(separator: " ")
        let level: InstrumentationLevel = (error == nil) ? .info : .warning
        Instrumentation.log(message, area: .aiAnalysis, level: level, details: details, payloadBytes: payloadSize)

        guard aiDiagnosticsEnabled else { return }
        var parts: [String] = ["[AI Diagnostics] \(message)"]
        if let endpoint { parts.append("endpoint=\(endpoint)") }
        if let payloadSize { parts.append("payloadBytes=\(payloadSize)") }
        if let error { parts.append("error=\(error.localizedDescription)") }
        let line = parts.joined(separator: " ")
        Task { @MainActor in
            appendAILogEntry(line)
        }
        print(line)
    }

    private var openAISession: URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        return URLSession(configuration: configuration)
    }

    private func runOpenAIAnalysis(cacheKey: String) async throws {
        guard let apiKey = KeychainStore.readPassword(account: KeychainKeys.openAIAPIKey) else {
            throw AIAuthError.missingAPIKey
        }

        let endpoint = aiOpenAIEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !endpoint.isEmpty else {
            throw AIAuthError.missingOpenAIEndpoint
        }

        guard let url = resolvedOpenAIEndpointURL(from: endpoint) else {
            throw AIAuthError.invalidOpenAIEndpoint
        }

        guard !aiOpenAIModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIAuthError.missingOpenAIModel
        }

        let body = try await buildOpenAIResponsesBody()
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = body

        do {
            logAIDiagnostics("OpenAI request sending (model \(aiOpenAIModel))", endpoint: url.absoluteString, payloadSize: body.count)
            let (data, response) = try await openAISession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                logAIDiagnostics("OpenAI response missing HTTP status", endpoint: url.absoluteString)
                throw URLError(.badServerResponse)
            }
            if !(200...299).contains(httpResponse.statusCode) {
                logAIDiagnostics("OpenAI response failed (status \(httpResponse.statusCode))", endpoint: url.absoluteString, payloadSize: data.count)
                throw URLError(.badServerResponse)
            }

            let parsed = parseAIResponse(data)
            let result = AIAnalysisResult(text: parsed.text, createdAt: Date(), preset: aiPromptPreset, selectionScope: effectiveAIScope)
            aiResult = result
            aiStructuredOutput = parsed.structured
            aiCache[cacheKey] = result
            appendAIHistory(result: result)
            updateSidebarFromAIResult(result)
            showAISavePrompt = true

            logAIDiagnostics("OpenAI response received (status \(httpResponse.statusCode))", endpoint: url.absoluteString, payloadSize: data.count)
        } catch let error as URLError {
            logAIDiagnostics("OpenAI request failed", error: error, endpoint: url.absoluteString)
            if error.code == .cannotFindHost {
                throw AIAuthError.openAIConnectionFailed("DNS lookup failed for \(url.host ?? "api.openai.com"). Check network or DNS settings.")
            }
            throw AIAuthError.openAIConnectionFailed("\(error.localizedDescription) (\(url.absoluteString))")
        }
    }

    private func buildAIRequestPayload() async -> AIRequestPayload {
        let spectra = aiSpectraForScope()
        let totalSpectra = spectra.count
        let yAxis = yAxisMode
        let payloadSpectra = await withTaskGroup(of: AISpectrumPayload.self) { group in
            for spectrum in spectra {
                let name = spectrum.name
                let points = points(for: spectrum).map { AIPointPayload(x: $0.x, y: $0.y) }
                let x = spectrum.x
                let y = spectrum.y
                group.addTask {
                    let metrics = SpectralMetricsCalculator.metrics(x: x, y: y, yAxisMode: yAxis)
                    let payloadMetrics = metrics.map { AIMetricsPayload(criticalWavelength: $0.criticalWavelength, uvaUvbRatio: $0.uvaUvbRatio, meanUVB: $0.meanUVBTransmittance) }
                    return AISpectrumPayload(name: name, points: points, metrics: payloadMetrics)
                }
            }

            var results: [AISpectrumPayload] = []
            results.reserveCapacity(totalSpectra)
            for await payload in group {
                results.append(payload)
            }
            return results
        }

        return AIRequestPayload(
            preset: useCustomPrompt ? "custom" : aiPromptPreset.rawValue,
            prompt: effectiveAIPrompt,
            temperature: aiTemperature,
            maxTokens: aiMaxTokens,
            selectionScope: effectiveAIScope.rawValue,
            yAxisMode: yAxisMode.rawValue,
            metricsRange: [chartWavelengthRange.lowerBound, chartWavelengthRange.upperBound],
            spectra: payloadSpectra
        )
    }

    private func buildOpenAIResponsesBody() async throws -> Data {
        let payload = await buildAIRequestPayload()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let payloadData = try encoder.encode(payload)
        let payloadString = String(data: payloadData, encoding: .utf8) ?? "{}"

        let systemText: String = {
            if aiStructuredOutputEnabled {
                return "You are a spectral analysis assistant. Respond only with valid JSON that matches the provided schema. Do not wrap JSON in markdown."
            }
            return "You are a spectral analysis assistant. Respond in clear, concise paragraphs with actionable insights."
        }()

        let userText: String = {
            if aiStructuredOutputEnabled {
                return """
\(effectiveAIPrompt)

Return JSON only.

Spectra payload (JSON):
\(payloadString)
"""
            }
            return """
\(effectiveAIPrompt)

Spectra payload (JSON):
\(payloadString)
"""
        }()

        let input: [OpenAIInputMessage] = [
            OpenAIInputMessage(role: "system", content: [OpenAIInputContent(text: systemText)]),
            OpenAIInputMessage(role: "user", content: [OpenAIInputContent(text: userText)])
        ]

        let request = OpenAIResponsesRequest(
            model: aiOpenAIModel.trimmingCharacters(in: .whitespacesAndNewlines),
            input: input,
            temperature: aiTemperature,
            maxOutputTokens: aiMaxTokens,
            text: aiStructuredOutputEnabled ? OpenAIResponseText(format: structuredOutputFormat()) : nil
        )

        return try JSONEncoder().encode(request)
    }

    private func structuredOutputFormat() -> OpenAIResponseTextFormat {
        let recommendationSchema = JSONSchema(
            type: "object",
            properties: [
                "ingredient": JSONSchema(type: "string", properties: nil, items: nil, required: nil, description: "Ingredient or active component", additionalProperties: nil, enumValues: nil),
                "amount": JSONSchema(type: "string", properties: nil, items: nil, required: nil, description: "Suggested amount or delta", additionalProperties: nil, enumValues: nil),
                "rationale": JSONSchema(type: "string", properties: nil, items: nil, required: nil, description: "Reasoning", additionalProperties: nil, enumValues: nil)
            ],
            items: nil,
            required: ["ingredient", "amount"],
            description: nil,
            additionalProperties: false,
            enumValues: nil
        )

        let schema = JSONSchema(
            type: "object",
            properties: [
                "summary": JSONSchema(type: "string", properties: nil, items: nil, required: nil, description: "One-paragraph summary", additionalProperties: nil, enumValues: nil),
                "insights": JSONSchema(type: "array", properties: nil, items: JSONSchema(type: "string", properties: nil, items: nil, required: nil, description: nil, additionalProperties: nil, enumValues: nil), required: nil, description: "Key insights", additionalProperties: nil, enumValues: nil),
                "risks": JSONSchema(type: "array", properties: nil, items: JSONSchema(type: "string", properties: nil, items: nil, required: nil, description: nil, additionalProperties: nil, enumValues: nil), required: nil, description: "Risks or warnings", additionalProperties: nil, enumValues: nil),
                "actions": JSONSchema(type: "array", properties: nil, items: JSONSchema(type: "string", properties: nil, items: nil, required: nil, description: nil, additionalProperties: nil, enumValues: nil), required: nil, description: "Next steps", additionalProperties: nil, enumValues: nil),
                "recommendations": JSONSchema(type: "array", properties: nil, items: recommendationSchema, required: nil, description: "Formulation recommendations", additionalProperties: nil, enumValues: nil)
            ],
            items: nil,
            required: ["insights", "risks", "actions"],
            description: nil,
            additionalProperties: false,
            enumValues: nil
        )

        return OpenAIResponseTextFormat(
            type: "json_schema",
            name: "spectral_analysis",
            strict: true,
            schema: schema
        )
    }

    private func aiSpectraForScope() -> [ShimadzuSpectrum] {
        switch effectiveAIScope {
        case .all:
            return displayedSpectra
        case .selected:
            return selectedSpectra
        }
    }

    private func updateAIEstimate() {
        let spectra = aiSpectraForScope()
        let totalPoints = spectra.reduce(0) { $0 + points(for: $1).count }
        let baseTokens = Int(Double(effectiveAIPrompt.count) / 4.0)
        let estimate = baseTokens + (totalPoints * 2) + 200
        aiEstimatedTokens = max(estimate, 0)
    }

    private func formattedTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }

    private var aiPresetTemplates: [(preset: AIPromptPreset, description: String)] {
        AIPromptPreset.allCases.map { preset in
            switch preset {
            case .summary:
                return (preset, "Concise findings, key metrics, and quick conclusions.")
            case .compareSelected:
                return (preset, "Compare selected spectra and highlight differences.")
            case .spfReport:
                return (preset, "SPF-focused report with UVA/UVB context and guidance.")
            case .getPrototypeSpf:
                return (preset, "Estimate prototype SPF vs named commercial references.")
            }
        }
    }

    private enum AISidebarSection {
        case insights
        case risks
        case actions
    }

    private func aiResponseSections(from text: String) -> (insights: [String], risks: [String], actions: [String], hasSections: Bool) {
        let lines = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }

        var current: AISidebarSection?
        var insights: [String] = []
        var risks: [String] = []
        var actions: [String] = []
        var hasSections = false

        for line in lines {
            guard !line.isEmpty else { continue }
            if let section = sectionHeading(from: line) {
                current = section
                hasSections = true
                continue
            }

            guard current != nil else { continue }

            let cleaned = line
                .replacingOccurrences(of: "•", with: "")
                .replacingOccurrences(of: "-", with: "")
                .trimmingCharacters(in: .whitespaces)

            guard !cleaned.isEmpty else { continue }

            switch current {
            case .insights:
                insights.append(cleaned)
            case .risks:
                risks.append(cleaned)
            case .actions:
                actions.append(cleaned)
            case .none:
                break
            }
        }

        return (insights, risks, actions, hasSections)
    }

    private func sectionHeading(from line: String) -> AISidebarSection? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutHashes = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let normalized = withoutHashes
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: ":-"))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if normalized == "key insights" || normalized == "insights" {
            return .insights
        }
        if normalized == "risks" || normalized == "warnings" || normalized == "risks/warnings" {
            return .risks
        }
        if normalized == "next actions" || normalized == "next steps" || normalized == "actions" || normalized == "steps" {
            return .actions
        }
        return nil
    }

    private func isListItemLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed.hasPrefix("• ") || trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
            return true
        }
        return trimmed.range(of: "^\\d+[\\.)]\\s+", options: .regularExpression) != nil
    }

    private func updateSidebarFromAIResult(_ result: AIAnalysisResult) {
        if let structured = aiStructuredOutput {
            aiSidebarHasStructuredSections = true
            aiSidebarInsightsText = structured.insights.joined(separator: "\n")
            aiSidebarRisksText = structured.risks.joined(separator: "\n")
            aiSidebarActionsText = structured.actions.joined(separator: "\n")
            return
        }

        let sections = aiResponseSections(from: result.text)
        aiSidebarHasStructuredSections = sections.hasSections
        aiSidebarInsightsText = sections.insights.joined(separator: "\n")
        aiSidebarRisksText = sections.risks.joined(separator: "\n")
        aiSidebarActionsText = sections.actions.joined(separator: "\n")
    }

    private func syncSidebarToAIResponse() {
        guard var result = aiResult else { return }
        let sectionsBlock = buildSidebarBlock()
        let introLines = introLinesBeforeSections(in: result.text)
        let cleaned = stripStructuredSections(from: result.text)
        let tail = removeIntroPrefix(from: cleaned, introLines: introLines)
        let introText = trimTrailingWhitespace(introLines.joined(separator: "\n"))

        var parts: [String] = []
        if !introText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(introText)
        }
        parts.append(sectionsBlock)
        if !tail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(tail)
        }

        result.text = parts.joined(separator: "\n\n")
        aiResult = result
        updateSidebarFromAIResult(result)
    }

    private func introLinesBeforeSections(in text: String) -> [String] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var intro: [String] = []
        for line in lines {
            if sectionHeading(from: line) != nil {
                break
            }
            intro.append(line)
        }
        while intro.last?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            intro.removeLast()
        }
        return intro
    }

    private func removeIntroPrefix(from text: String, introLines: [String]) -> String {
        guard !introLines.isEmpty else { return text }
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let introCount = introLines.count
        if lines.count >= introCount && Array(lines.prefix(introCount)) == introLines {
            lines.removeFirst(introCount)
        }
        while lines.first?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            lines.removeFirst()
        }
        return lines.joined(separator: "\n")
    }

    private func stripStructuredSections(from text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var output: [String] = []
        var skipping = false
        var sawHeading = false
        for line in lines {
            if sectionHeading(from: line) != nil {
                skipping = true
                sawHeading = true
                continue
            }

            if skipping {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    continue
                }
                if sectionHeading(from: line) != nil {
                    continue
                }
                if isListItemLine(line) {
                    continue
                }
                skipping = false
                output.append(line)
                continue
            }

            output.append(line)
        }

        let cleaned = output.joined(separator: "\n")
        if sawHeading {
            return trimTrailingWhitespace(cleaned)
        }
        return text
    }

    private func trimTrailingWhitespace(_ value: String) -> String {
        var text = value
        while text.last?.isWhitespace == true {
            text.removeLast()
        }
        return text
    }

    private func buildSidebarBlock() -> String {
        let insights = aiSidebarInsightsText
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { "• \($0.trimmingCharacters(in: .whitespacesAndNewlines))" }
            .joined(separator: "\n")
        let risks = aiSidebarRisksText
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { "• \($0.trimmingCharacters(in: .whitespacesAndNewlines))" }
            .joined(separator: "\n")
        let actions = aiSidebarActionsText
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { "• \($0.trimmingCharacters(in: .whitespacesAndNewlines))" }
            .joined(separator: "\n")

        return [
            "Key Insights:",
            insights,
            "",
            "Risks/Warnings:",
            risks,
            "",
            "Next Steps:",
            actions
        ].joined(separator: "\n")
    }

    @ViewBuilder
    private func aiSidebarEditableSection(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            TextEditor(text: text)
                .frame(minHeight: 70, maxHeight: 100)
                .font(.caption)
                .padding(6)
                .background(Color.white.opacity(0.04))
                .cornerRadius(8)
        }
    }

    private var aiHistoryDiffText: String? {
        guard let idA = aiHistorySelectionA,
              let idB = aiHistorySelectionB,
              idA != idB,
              let entryA = aiHistoryEntries.first(where: { $0.id == idA }),
              let entryB = aiHistoryEntries.first(where: { $0.id == idB }) else { return nil }
        let diffLines = diffLines(a: entryA.text, b: entryB.text)
        return diffLines.joined(separator: "\n")
    }

    private func diffLines(a: String, b: String) -> [String] {
        let aLines = a.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let bLines = b.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let count = max(aLines.count, bLines.count)
        var output: [String] = []
        for index in 0..<count {
            let left = index < aLines.count ? aLines[index] : ""
            let right = index < bLines.count ? bLines[index] : ""
            if left == right {
                output.append("  \(left)")
            } else {
                if !left.isEmpty { output.append("- \(left)") }
                if !right.isEmpty { output.append("+ \(right)") }
            }
        }
        return output
    }

    private func appendAIHistory(result: AIAnalysisResult) {
        if let last = aiHistoryEntries.first, last.text == result.text {
            return
        }
        var updated = aiHistoryEntries
        updated.insert(AIHistoryEntry(timestamp: Date(), preset: result.preset, scope: result.selectionScope, text: result.text), at: 0)
        if updated.count > aiHistoryMaxEntries {
            updated.removeLast(updated.count - aiHistoryMaxEntries)
        }
        aiHistoryEntries = updated
    }

    private func buildSpfMathLines(
        spectrum: ShimadzuSpectrum,
        metrics: SpectralMetrics,
        calibration: CalibrationResult?
    ) -> [String] {
        var lines: [String] = []
        lines.append("SPF Math Details")
        lines.append("Spectrum: \(spectrum.name)")
        lines.append("YAxis Mode: \(yAxisMode.rawValue)")
        lines.append("Ranges: UVB 290–320 nm, UVA 320–400 nm, Total 290–400 nm")
        lines.append("Conversions:")
        if yAxisMode == .absorbance {
            lines.append("  T = 10^(−A)")
        } else {
            lines.append("  A = −log10(max(T, 1e−9))")
        }
        lines.append(String(format: "UVB Area: %.4f", metrics.uvbArea))
        lines.append(String(format: "UVA Area: %.4f", metrics.uvaArea))
        lines.append(String(format: "UVA/UVB Ratio: %.4f", metrics.uvaUvbRatio))
        lines.append(String(format: "Critical Wavelength: %.2f nm", metrics.criticalWavelength))
        lines.append(String(format: "Mean UVB Transmittance: %.4f", metrics.meanUVBTransmittance))
        lines.append("COLIPA SPF:")
        lines.append("  SPF = Σ E(λ)·I(λ) / Σ E(λ)·I(λ)·T(λ)")
        if let colipa = cachedColipaSpf {
            lines.append(String(format: "  Value: %.2f", colipa))
        } else {
            lines.append("  Value: unavailable (requires 290–400 nm data)")
        }
        if let calibration {
            let features: [Double] = [
                1.0,
                metrics.uvbArea,
                metrics.uvaArea,
                metrics.criticalWavelength,
                metrics.uvaUvbRatio,
                metrics.meanUVBTransmittance
            ]
            let logSpf = zip(calibration.coefficients, features).map(*).reduce(0, +)
            let predicted = max(exp(logSpf), 0.0)
            lines.append("Model:")
            lines.append("  log(SPF) = Σ(bᵢ × featureᵢ)")
            lines.append("  SPF = exp(log(SPF))")
            lines.append(String(format: "Estimated SPF (calibrated): %.2f", predicted))
            lines.append("Coefficients:")
            for (name, coeff) in zip(calibration.featureNames, calibration.coefficients) {
                lines.append(String(format: "  %@: %.6f", name, coeff))
            }
            lines.append(String(format: "Calibration: n=%d, R²=%.3f, RMSE=%.2f", calibration.sampleCount, calibration.r2, calibration.rmse))
        } else {
            lines.append("Calibration: not available (need at least 2 labeled samples)")
        }
        return lines
    }

    private func copyValidationLog() {
        let text = validationLogEntries
            .map { "\(formattedTimestamp($0.timestamp)) \($0.message)" }
            .joined(separator: "\n")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func copySpfMathToPasteboard() {
        guard let spectrum = selectedSpectrum, let metrics = selectedMetrics else { return }
        let calibration = calibrationResult
        let lines = buildSpfMathLines(spectrum: spectrum, metrics: metrics, calibration: calibration)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(lines.joined(separator: "\n"), forType: .string)
    }

    private func saveValidationLogToFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.plainText]
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateStamp = dateFormatter.string(from: Date())
        panel.nameFieldStringValue = "validation-log-\(dateStamp).txt"
        if let directory = lastSaveDirectoryURL(for: .aiReports) {
            panel.directoryURL = directory
        }
        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            let text = validationLogEntries
                .map { "\(formattedTimestamp($0.timestamp)) \($0.message)" }
                .joined(separator: "\n")
            do {
                try text.write(to: url, atomically: true, encoding: .utf8)
                storeLastSaveDirectory(from: url, key: .aiReports)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func copyAILogToPasteboard() {
        let text = aiLogEntries
            .map { "\(formattedTimestamp($0.timestamp)) \($0.message)" }
            .joined(separator: "\n")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func appendAILogEntry(_ message: String) {
        var updated = aiLogEntries
        updated.append(AILogEntry(timestamp: Date(), message: message))
        if updated.count > aiLogMaxEntries {
            updated.removeFirst(updated.count - aiLogMaxEntries)
        }
        aiLogEntries = updated
        persistAILogEntries()
        NotificationCenter.default.post(name: .aiLog, object: message)
    }

    private func persistAILogEntries() {
        let payload = aiLogEntries.map { LogEntryPayload(timestamp: $0.timestamp, message: $0.message) }
        guard let data = try? JSONEncoder().encode(payload) else { return }
        UserDefaults.standard.set(data, forKey: aiLogStorageKey)
    }

    private func loadPersistentAILog() {
        guard let data = UserDefaults.standard.data(forKey: aiLogStorageKey),
              let payload = try? JSONDecoder().decode([LogEntryPayload].self, from: data) else { return }
        aiLogEntries = payload.map { AILogEntry(timestamp: $0.timestamp, message: $0.message) }
    }

    private func exportAILogToFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.plainText]
        panel.nameFieldStringValue = "ai-log.txt"
        if let directory = lastSaveDirectoryURL(for: .validationLogs) {
            panel.directoryURL = directory
        }
        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            let text = aiLogEntries
                .map { "\(formattedTimestamp($0.timestamp)) \($0.message)" }
                .joined(separator: "\n")
            do {
                try text.write(to: url, atomically: true, encoding: .utf8)
                storeLastSaveDirectory(from: url, key: .aiReports)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func copyInstrumentationLogToPasteboard() {
        let text = instrumentationLogEntries
            .map { "\(formattedTimestamp($0.timestamp)) \($0.message)" }
            .joined(separator: "\n")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func appendInstrumentationLogEntry(_ message: String) {
        var updated = instrumentationLogEntries
        updated.append(InstrumentationLogEntry(timestamp: Date(), message: message))
        if updated.count > instrumentationLogMaxEntries {
            updated.removeFirst(updated.count - instrumentationLogMaxEntries)
        }
        instrumentationLogEntries = updated
        persistInstrumentationLogEntries()
    }

    private func persistInstrumentationLogEntries() {
        let payload = instrumentationLogEntries.map { LogEntryPayload(timestamp: $0.timestamp, message: $0.message) }
        guard let data = try? JSONEncoder().encode(payload) else { return }
        UserDefaults.standard.set(data, forKey: instrumentationLogStorageKey)
    }

    private func loadPersistentInstrumentationLog() {
        guard let data = UserDefaults.standard.data(forKey: instrumentationLogStorageKey),
              let payload = try? JSONDecoder().decode([LogEntryPayload].self, from: data) else { return }
        instrumentationLogEntries = payload.map { InstrumentationLogEntry(timestamp: $0.timestamp, message: $0.message) }
    }

    private func exportInstrumentationLogToFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.plainText]
        panel.nameFieldStringValue = "instrumentation-log.txt"
        if let directory = lastSaveDirectoryURL(for: .instrumentationLogs) {
            panel.directoryURL = directory
        }
        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            let text = instrumentationLogEntries
                .map { "\(formattedTimestamp($0.timestamp)) \($0.message)" }
                .joined(separator: "\n")
            do {
                try text.write(to: url, atomically: true, encoding: .utf8)
                storeLastSaveDirectory(from: url, key: .instrumentationLogs)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func parseAIResponse(_ data: Data) -> ParsedAIResponse {
        if let decoded = try? JSONDecoder().decode(AIResponse.self, from: data) {
            return parseStructuredOutput(text: decoded.text)
        }
        if let decoded = try? JSONDecoder().decode(OpenAIResponsesResponse.self, from: data),
           let text = decoded.outputText {
            return parseStructuredOutput(text: text)
        }
        if let structured = try? JSONDecoder().decode(AIStructuredOutput.self, from: data) {
            return ParsedAIResponse(text: structuredText(from: structured), structured: structured)
        }
        let fallback = String(data: data, encoding: .utf8) ?? "Empty response"
        return parseStructuredOutput(text: fallback)
    }

    private func parseStructuredOutput(text: String) -> ParsedAIResponse {
        if let structured = decodeStructuredOutput(from: text) {
            return ParsedAIResponse(text: structuredText(from: structured), structured: structured)
        }
        return ParsedAIResponse(text: text, structured: nil)
    }

    private func decodeStructuredOutput(from text: String) -> AIStructuredOutput? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.first == "{" else { return nil }
        guard let data = trimmed.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(AIStructuredOutput.self, from: data)
    }

    private func structuredText(from structured: AIStructuredOutput) -> String {
        var sections: [String] = []

        if let summary = structured.summary, !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append(summary.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        sections.append("Key Insights")
        if structured.insights.isEmpty {
            sections.append("- None provided")
        } else {
            sections.append(contentsOf: structured.insights.map { "- \($0)" })
        }

        sections.append("")
        sections.append("Risks/Warnings")
        if structured.risks.isEmpty {
            sections.append("- None provided")
        } else {
            sections.append(contentsOf: structured.risks.map { "- \($0)" })
        }

        sections.append("")
        sections.append("Next Steps")
        if structured.actions.isEmpty {
            sections.append("- None provided")
        } else {
            sections.append(contentsOf: structured.actions.map { "- \($0)" })
        }

        if let recommendations = structured.recommendations, !recommendations.isEmpty {
            sections.append("")
            sections.append("Recommendations")
            for rec in recommendations {
                var line = "- \(rec.ingredient): \(rec.amount)"
                if let rationale = rec.rationale, !rationale.isEmpty {
                    line += " (\(rationale))"
                }
                sections.append(line)
            }
        }

        return sections.joined(separator: "\n")
    }

    private func aiCacheKey() -> String {
        let scope = effectiveAIScope.rawValue
        let preset = useCustomPrompt ? "custom" : aiPromptPreset.rawValue
        let endpoint = aiOpenAIEndpoint
        let model = aiOpenAIModel
        let promptSignature = String(effectiveAIPrompt.prefix(120))
        let names = aiSpectraForScope().map { $0.name }.joined(separator: "|")
        let structuredFlag = aiStructuredOutputEnabled ? "structured" : "plain"
        return "\(endpoint)|\(model)|\(scope)|\(preset)|\(yAxisMode.rawValue)|\(structuredFlag)|\(promptSignature)|\(names)"
    }

    private func saveAIResultToDisk() {
        guard let aiResult else { return }
        let panel = NSSavePanel()
        let docx = UTType(filenameExtension: "docx") ?? .data
        panel.nameFieldStringValue = "AI Analysis.docx"
        panel.allowedContentTypes = [docx, .plainText]
        panel.canCreateDirectories = true
        if let directory = lastSaveDirectoryURL(for: .instrumentationLogs) {
            panel.directoryURL = directory
        }

        if panel.runModal() == .OK, let url = panel.url {
            do {
                if url.pathExtension.lowercased() == "docx" {
                    try OOXMLWriter.writeDocx(report: aiResult.text, to: url)
                } else {
                    try aiResult.text.write(to: url, atomically: true, encoding: .utf8)
                }
                storeLastSaveDirectory(from: url, key: .aiLogs)
            } catch {
                aiErrorMessage = error.localizedDescription
            }
        }
    }

    private func saveAIResultToDefaultAndOpen() {
        guard let aiResult else { return }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: Date())
        let fileName = "AI SPF Analysis_\(stamp).docx"

        let baseDirectory = lastSaveDirectoryURL(for: .aiReports)
            ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let url = baseDirectory.appendingPathComponent(fileName)

        do {
            try OOXMLWriter.writeDocx(report: aiResult.text, to: url)
            storeLastSaveDirectory(from: url, key: .aiReports)
            NSWorkspace.shared.open(url)
        } catch {
            aiErrorMessage = error.localizedDescription
        }
    }

    private func copyAIOutput() {
        guard let aiResult else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(aiResult.text, forType: .string)
    }

    nonisolated static func sampleDisplayName(from url: URL, spectrumName: String, index: Int, total: Int) -> String {
        let trimmed = spectrumName.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        let isGeneric = trimmed.isEmpty || lower.hasPrefix("dataset") || lower.hasPrefix("data set")

        let baseName = url.deletingPathExtension().lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        var name = isGeneric ? baseName : trimmed

        if total > 1 {
            name += " #\(index + 1)"
        }

        return name
    }

    private var selectedPoint: SpectrumPoint? {
        guard let chartSelectionX else { return nil }
        if let spectrum = selectedSpectra.first {
            return nearestPoint(in: spectrum, x: chartSelectionX)
        }
        return nil
    }

    private func nearestPoint(in spectrum: ShimadzuSpectrum, x target: Double) -> SpectrumPoint? {
        let points = points(for: spectrum)
        guard !points.isEmpty else { return nil }
        return points.min(by: { abs($0.x - target) < abs($1.x - target) })
    }

    @ChartContentBuilder
    private var chartSeriesMarks: some ChartContent {
        let selectedNames = Set(selectedSpectra.map { $0.name })

        if showAllSpectra && !showSelectedOnly {
            ForEach(seriesToPlot) { series in
                let isSelected = selectedNames.contains(series.name)
                let hasSelection = !selectedNames.isEmpty
                let emphasis = !hasSelection || isSelected

                ForEach(series.points) { point in
                    LineMark(
                        x: .value("Wavelength", point.x),
                        y: .value("Intensity", point.y),
                        series: .value("Sample", series.name)
                    )
                    .foregroundStyle(by: .value("Sample", series.name))
                    .lineStyle(StrokeStyle(lineWidth: isSelected ? 2.5 : 1))
                    .opacity(emphasis ? 1.0 : 0.25)
                }
            }
        } else if !showSelectedOnly, let first = displayedSpectra.first {
            let color = palette.colors[selectedSpectrumIndex % palette.colors.count]
            ForEach(points(for: first)) { point in
                LineMark(
                    x: .value("Wavelength", point.x),
                    y: .value("Intensity", point.y)
                )
                .foregroundStyle(color)
                .lineStyle(StrokeStyle(lineWidth: 1.8))
            }
        }

        if showSelectedOnly {
            ForEach(selectedSpectra.indices, id: \.self) { index in
                let spectrum = selectedSpectra[index]
                let points = points(for: spectrum)
                ForEach(points) { point in
                    LineMark(
                        x: .value("Wavelength", point.x),
                        y: .value("Intensity", point.y),
                        series: .value("Sample", spectrum.name)
                    )
                    .foregroundStyle(by: .value("Sample", spectrum.name))
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }
            }
        }

        if showAverage, let avg = averageSpectrum {
            ForEach(points(for: avg)) { point in
                LineMark(
                    x: .value("Wavelength", point.x),
                    y: .value("Intensity", point.y)
                )
                .foregroundStyle(Color.black)
                .lineStyle(StrokeStyle(lineWidth: 2))
            }
        }
    }

    @ChartContentBuilder
    private var selectedPointMarks: some ChartContent {
        if let selectedPoint {
            RuleMark(x: .value("Selected Wavelength", selectedPoint.x))
                .foregroundStyle(Color.secondary)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

            PointMark(
                x: .value("Selected Wavelength", selectedPoint.x),
                y: .value("Selected Intensity", selectedPoint.y)
            )
            .foregroundStyle(Color.white)
            .symbolSize(30)
        }
    }

    @ChartContentBuilder
    private var peakMarks: some ChartContent {
        if showPeaks {
            ForEach(peaks.filter { chartWavelengthRange.contains($0.x) }) { peak in
                PointMark(
                    x: .value("Wavelength", peak.x),
                    y: .value("Intensity", peak.y)
                )
                .foregroundStyle(Color.red)
            }
        }
    }

    private func pointAnnotation(for point: SpectrumPoint) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(String(format: "%.1f nm", point.x))
                .font(.caption)
                .bold()
            Text(String(format: "%.4f", point.y))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(6)
        .glassSurface(cornerRadius: 8)
    }

    private func chartTooltipView(for point: SpectrumPoint, plotRect: CGRect, location: CGPoint) -> some View {
        let tooltipWidth: CGFloat = 150
        let tooltipHeight: CGFloat = 48
        let rawX = location.x
        let rawY = location.y
        let clampedX = min(max(rawX + 8, plotRect.minX + 6), plotRect.maxX - tooltipWidth - 6)
        let clampedY = min(max(rawY - tooltipHeight - 8, plotRect.minY + 6), plotRect.maxY - tooltipHeight - 6)

        return VStack(alignment: .leading, spacing: 2) {
            Text(String(format: "%.1f nm", point.x))
                .font(.caption)
                .bold()
            Text(String(format: "%.4f", point.y))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(6)
        .frame(width: tooltipWidth, height: tooltipHeight, alignment: .leading)
        .glassSurface(cornerRadius: 8)
        .position(x: clampedX + tooltipWidth / 2, y: clampedY + tooltipHeight / 2)
    }

    private var pointReadoutPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Point Readout")
                .font(.caption)
                .foregroundColor(.secondary)

            if let selectedPoint {
                HStack(spacing: 12) {
                    Text("\(String(format: "%.1f", selectedPoint.x)) nm")
                    Text("\(String(format: "%.4f", selectedPoint.y))")
                }
                .font(.caption)
            } else {
                Text("Hover over the chart to see precise values.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(cornerRadius: 10)
    }

    private func spectrumTags(for name: String) -> [String] {
        let lower = name.lowercased()
        var tags: [String] = []

        if lower.contains("after incubation") { tags.append("Post Incubation") }
        if lower.contains("blank") { tags.append("Blank") }
        if lower.contains("control") { tags.append("Control") }
        if lower.contains("commercial") { tags.append("Commercial") }
        if lower.contains("in house") { tags.append("In House") }
        if lower.contains("project") { tags.append("Project") }
        if lower.contains("base") { tags.append("Base") }
        if lower.contains("neutragena") || lower.contains("neutrogena") { tags.append("Neutrogena") }
        if lower.contains("cetaphil") { tags.append("Cetaphil") }
        if lower.contains("cerva") { tags.append("CeraVe") }
        if lower.contains("cvs") { tags.append("CVS") }

        return tags.isEmpty ? ["Sample"] : Array(tags.prefix(3))
    }

    @ViewBuilder
    private func glassGroup<Content: View>(spacing: CGFloat = 12, @ViewBuilder content: () -> Content) -> some View {
        if #available(macOS 15.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content()
            }
        } else {
            content()
        }
    }

    private var displayedSpectra: [ShimadzuSpectrum] {
        if !processedSpectra.isEmpty { return processedSpectra }
        if useAlignment, !alignedSpectra.isEmpty { return alignedSpectra }
        return spectra
    }

    private var selectedSpectrum: ShimadzuSpectrum? {
        if !displayedSpectra.isEmpty {
            let index = min(max(selectedSpectrumIndex, 0), displayedSpectra.count - 1)
            if selectedSpectrumIndices.isEmpty,
               includeInvalidInPlots,
               let invalid = selectedInvalidSpectra.first {
                return invalid
            }
            return displayedSpectra[index]
        }
        if includeInvalidInPlots {
            return selectedInvalidSpectra.first
        }
        return nil
    }

    private var selectedSpectra: [ShimadzuSpectrum] {
        let indices = selectedSpectrumIndices.filter { $0 >= 0 && $0 < displayedSpectra.count }
        var result: [ShimadzuSpectrum] = []
        if indices.isEmpty, let selectedSpectrum {
            result.append(selectedSpectrum)
        } else {
            result.append(contentsOf: indices.sorted().map { displayedSpectra[$0] })
        }
        if includeInvalidInPlots {
            result.append(contentsOf: selectedInvalidSpectra)
        }
        return result
    }

    private var rawSelectedSpectra: [ShimadzuSpectrum] {
        let indices = selectedSpectrumIndices.filter { $0 >= 0 && $0 < spectra.count }
        var result: [ShimadzuSpectrum] = []
        if indices.isEmpty {
            let index = min(max(selectedSpectrumIndex, 0), max(spectra.count - 1, 0))
            if spectra.indices.contains(index) {
                result.append(spectra[index])
            }
        } else {
            result.append(contentsOf: indices.sorted().map { spectra[$0] })
        }
        return result
    }

    private var spectraForProcessing: [ShimadzuSpectrum] {
        if showSelectedOnly { return rawSelectedSpectra }
        return showAllSpectra ? spectra : rawSelectedSpectra
    }

    private var activeSpectra: [ShimadzuSpectrum] {
        if showSelectedOnly { return selectedSpectra }
        return showAllSpectra ? displayedSpectra : selectedSpectra
    }

    private var selectedMetrics: SpectralMetrics? {
        cachedSelectedMetrics
    }

    private var selectedMetricsStats: (avgUvaUvb: Double, avgCritical: Double, uvaUvbRange: ClosedRange<Double>, criticalRange: ClosedRange<Double>)? {
        cachedSelectedMetricsStats
    }

    private var dashboardMetrics: DashboardMetrics? {
        cachedDashboardMetrics
    }

    private var aiPromptPreset: AIPromptPreset {
        get { AIPromptPreset(rawValue: aiPromptPresetRawValue) ?? .summary }
        nonmutating set { aiPromptPresetRawValue = newValue.rawValue }
    }

    private var effectiveAIPrompt: String {
        if useCustomPrompt {
            let trimmed = aiCustomPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return aiPromptPreset.template
    }

    private var aiDefaultScope: AISelectionScope {
        get { AISelectionScope(rawValue: aiDefaultScopeRawValue) ?? .selected }
        nonmutating set { aiDefaultScopeRawValue = newValue.rawValue }
    }

    private var effectiveAIScope: AISelectionScope {
        aiScopeOverride ?? aiDefaultScope
    }

    private var hasAPIKey: Bool {
        KeychainStore.readPassword(account: KeychainKeys.openAIAPIKey) != nil
    }

    private var selectedInstrument: InstrumentDevice? {
        guard let selectedInstrumentID else { return nil }
        return instrumentManager.devices.first { $0.id == selectedInstrumentID }
    }

    private var activeMetadataFromSelection: ShimadzuSPCMetadata? {
        if let dataset = storedDatasets.first(where: { selectedStoredDatasetIDs.contains($0.id) }) {
            return decodedMetadata(for: dataset)
        }
        return activeMetadata
    }

    private var activeHeader: SPCMainHeader? {
        activeMetadataFromSelection?.mainHeader
    }

    private var activeHeaderFileName: String? {
        if let dataset = storedDatasets.first(where: { selectedStoredDatasetIDs.contains($0.id) }) {
            return dataset.fileName
        }
        return activeMetadataSource
    }

    private var aiCanRunAnalysis: Bool {
        guard aiEnabled else { return false }
        return hasAPIKey && !aiOpenAIEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !aiOpenAIModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var calibrationResult: CalibrationResult? {
        cachedCalibration
    }

    private var seriesToPlot: [SpectrumSeries] {
        cachedSeries
    }

    private var seriesToPlotNames: [String] {
        seriesToPlot.map { $0.name }
    }


    private var averageSpectrum: ShimadzuSpectrum? {
        cachedAverageSpectrum
    }

    private func handleImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            Instrumentation.log("Import selection confirmed", area: .uiInteraction, level: .info, details: "files=\(urls.count)")
            let shouldAppend = appendOnImport
            appendOnImport = false
            Task { await loadSpectra(from: urls, append: shouldAppend) }
        case .failure(let error):
            Instrumentation.log("Import failed", area: .uiInteraction, level: .warning, details: "error=\(error.localizedDescription)")
            appendOnImport = false
            errorMessage = error.localizedDescription
        }
    }

    private func loadSpectra(from urls: [URL], append: Bool) async {
        let started = Date()
        Instrumentation.log("Import started", area: .importParsing, level: .info, details: "files=\(urls.count) append=\(append)")

        let parseResult = await SpectrumParsingWorker.shared.parse(urls: urls)

        let loaded = parseResult.loaded
        let failures = parseResult.failures
        let skippedTotal = parseResult.skippedTotal
        let filesWithSkipped = parseResult.filesWithSkipped
        let warnings = parseResult.warnings
        let parsedFiles = parseResult.parsedFiles

        await MainActor.run {
            var validSpectra: [ShimadzuSpectrum] = []
            var parsedInvalidItems: [InvalidSpectrumItem] = []
            var invalidCounts: [String: Int] = [:]
            validSpectra.reserveCapacity(loaded.count)

            for spectrum in loaded {
                if let reason = SpectrumValidation.invalidReason(x: spectrum.x, y: spectrum.y) {
                    parsedInvalidItems.append(
                        InvalidSpectrumItem(
                            spectrum: ShimadzuSpectrum(name: spectrum.name, x: spectrum.x, y: spectrum.y),
                            fileName: spectrum.fileName,
                            reason: reason
                        )
                    )
                    invalidCounts[spectrum.fileName, default: 0] += 1
                } else {
                    validSpectra.append(ShimadzuSpectrum(name: spectrum.name, x: spectrum.x, y: spectrum.y))
                }
            }

            let invalidWarnings = invalidCounts
                .sorted(by: { $0.key < $1.key })
                .map { "\($0.key): flagged \($0.value) invalid spectra" }
            let combinedWarnings = warnings + invalidWarnings

            let wasEmpty = spectra.isEmpty
            updateActiveMetadata(from: parsedFiles, append: append)
            persistParsedFiles(parsedFiles)

            if append {
                spectra.append(contentsOf: validSpectra)
            } else {
                spectra = validSpectra
                selectedSpectrumIndex = 0
                selectedSpectrumIndices = []
            }

            alignedSpectra = []
            processedSpectra = []
            pointCache = [:]

            if append {
                selectedSpectrumIndices = selectedSpectrumIndices.filter { $0 >= 0 && $0 < spectra.count }
                if wasEmpty, !spectra.isEmpty {
                    selectedSpectrumIndex = 0
                    selectedSpectrumIndices = [0]
                } else {
                    selectedSpectrumIndex = min(max(selectedSpectrumIndex, 0), max(spectra.count - 1, 0))
                }
            } else if !spectra.isEmpty {
                selectedSpectrumIndices = [0]
            }

            updatePeaks()
            applyAlignmentIfNeeded()

            if spectra.isEmpty {
                statusMessage = "No spectra found."
            } else if append, !validSpectra.isEmpty {
                statusMessage = "Added \(validSpectra.count) spectra (total \(spectra.count))."
            } else {
                statusMessage = "Loaded \(spectra.count) spectra."
            }

            if !includeInvalidInPlots {
                selectedInvalidItemIDs.removeAll()
            }

            if skippedTotal > 0 {
                let message = append
                    ? "Skipped \(skippedTotal) dataset(s) while adding."
                    : "Skipped \(skippedTotal) dataset(s) across \(filesWithSkipped) file(s)."
                warningMessage = message
            } else {
                warningMessage = nil
            }

            if append, !combinedWarnings.isEmpty {
                warningDetails.append(contentsOf: combinedWarnings)
            } else {
                warningDetails = combinedWarnings
            }

            if append, !parsedInvalidItems.isEmpty {
                invalidItems.append(contentsOf: parsedInvalidItems)
            } else {
                invalidItems = parsedInvalidItems
            }

            if !failures.isEmpty {
                errorMessage = failures.joined(separator: "\n")
            }

            if !spectra.isEmpty {
                appMode = .analyze
            }

            updateAIEstimate()

            let duration = Date().timeIntervalSince(started)
            Instrumentation.log(
                "Import completed",
                area: .importParsing,
                level: .info,
                details: "loaded=\(validSpectra.count) failures=\(failures.count) skipped=\(skippedTotal)",
                duration: duration
            )
            if !failures.isEmpty {
                Instrumentation.log("Import failures", area: .importParsing, level: .warning, details: "count=\(failures.count)")
            }
            if skippedTotal > 0 {
                Instrumentation.log("Datasets skipped", area: .importParsing, level: .warning, details: "count=\(skippedTotal) files=\(filesWithSkipped)")
            }
        }
    }

    private func updateActiveMetadata(from parsedFiles: [ParsedFileResult], append: Bool) {
        guard !append else { return }
        if parsedFiles.count == 1 {
            activeMetadata = parsedFiles[0].metadata
            activeMetadataSource = parsedFiles[0].url.lastPathComponent
        } else {
            activeMetadata = nil
            activeMetadataSource = parsedFiles.isEmpty ? nil : "Multiple files loaded"
        }
    }

    private func updateActiveMetadata(from dataset: StoredDataset, append: Bool) {
        guard !append else { return }
        activeMetadata = decodedMetadata(for: dataset)
        activeMetadataSource = dataset.fileName
    }

    private func validateStoredDatasetSelection() {
        let datasets = storedDatasets.filter { selectedStoredDatasetIDs.contains($0.id) }
        guard !datasets.isEmpty else {
            statusMessage = "Select stored dataset(s) to validate."
            return
        }
        validationLogEntries.removeAll()
        for dataset in datasets {
            validateStoredDataset(dataset, appendLog: true)
        }
        statusMessage = "Header validation complete for \(datasets.count) dataset(s)."
    }

    private func validateStoredDataset(_ dataset: StoredDataset, appendLog: Bool = false) {
        guard let header = decodedMetadata(for: dataset)?.mainHeader else {
            Instrumentation.log(
                "SPC header missing",
                area: .importParsing,
                level: .warning,
                details: "file=\(dataset.fileName)"
            )
            statusMessage = "No SPC header found for \(dataset.fileName)."
            return
        }

        if !appendLog {
            validationLogEntries.removeAll()
        }
        let sortedSpectra = dataset.spectraItems.sorted { $0.orderIndex < $1.orderIndex }
        let xFetcher: (StoredSpectrum) -> [Double] = { SpectrumBinaryCodec.decodeDoubles(from: $0.xData) }
        let yFetcher: (StoredSpectrum) -> [Double] = { SpectrumBinaryCodec.decodeDoubles(from: $0.yData) }
        let mismatchCount = validateHeader(
            header,
            spectra: sortedSpectra,
            spectrumName: { $0.name },
            xProvider: xFetcher,
            yProvider: yFetcher,
            logPrefix: "file=\(dataset.fileName)",
            logSink: { message in
                validationLogEntries.append(ValidationLogEntry(timestamp: Date(), message: message))
            }
        )

        if !appendLog {
            statusMessage = "Header validation complete (mismatches: \(mismatchCount))."
        }
    }

    private func validateLoadedSpectra() {
        guard !spectra.isEmpty else {
            statusMessage = "No loaded spectra to validate."
            return
        }
        guard let header = activeHeader else {
            statusMessage = "No SPC header available for loaded spectra."
            return
        }

        validationLogEntries.removeAll()
        let xFetcher: (ShimadzuSpectrum) -> [Double] = { $0.x }
        let yFetcher: (ShimadzuSpectrum) -> [Double] = { $0.y }
        let mismatchCount = validateHeader(
            header,
            spectra: spectra,
            spectrumName: { $0.name },
            xProvider: xFetcher,
            yProvider: yFetcher,
            logPrefix: "loaded",
            logSink: { message in
                validationLogEntries.append(ValidationLogEntry(timestamp: Date(), message: message))
            }
        )
        statusMessage = "Loaded header validation complete (mismatches: \(mismatchCount))."
    }

    private func axesMatch(_ lhs: [Double], _ rhs: [Double]) -> Bool {
        if lhs.count != rhs.count { return false }
        guard let lhsFirst = lhs.first, let lhsLast = lhs.last,
              let rhsFirst = rhs.first, let rhsLast = rhs.last else {
            return false
        }
        let tolerance = 1e-6
        return abs(lhsFirst - rhsFirst) < tolerance && abs(lhsLast - rhsLast) < tolerance
    }

    private func validateHeader<T>(
        _ header: SPCMainHeader,
        spectra: [T],
        spectrumName: (T) -> String,
        xProvider: (T) -> [Double],
        yProvider: (T) -> [Double],
        logPrefix: String,
        logSink: ((String) -> Void)? = nil
    ) -> Int {
        var mismatches = 0
        let expectedPoints = Int(header.pointCount)

        func record(_ message: String) {
            Instrumentation.log(
                "SPC validation",
                area: .importParsing,
                level: .warning,
                details: message
            )
            logSink?(message)
        }

        if expectedPoints > 0 {
            for spectrum in spectra {
                let x = xProvider(spectrum)
                let y = yProvider(spectrum)
                let count = min(x.count, y.count)
                if count != expectedPoints {
                    mismatches += 1
                    record("\(logPrefix) spectrum=\(spectrumName(spectrum)) expected=\(expectedPoints) actual=\(count)")
                }
            }
        }

        if header.fileType.isMultiFile, spectra.count <= 1 {
            mismatches += 1
            record("\(logPrefix) spectra=\(spectra.count) flag=multifile")
        } else if !header.fileType.isMultiFile, spectra.count > 1 {
            mismatches += 1
            record("\(logPrefix) spectra=\(spectra.count) flag=single")
        }

        if !header.fileType.hasPerSubfileX, spectra.count > 1 {
            let referenceX = xProvider(spectra[0])
            for spectrum in spectra.dropFirst() {
                let currentX = xProvider(spectrum)
                if !axesMatch(referenceX, currentX) {
                    mismatches += 1
                    record("\(logPrefix) spectrum=\(spectrumName(spectrum)) xAxis=mismatch")
                    break
                }
            }
        }

        return mismatches
    }

    fileprivate static func validateSPCHeaderConsistency(for parsed: ParsedFileResult) {
        guard let header = parsed.metadata.mainHeader else {
            Instrumentation.log(
                "SPC header missing",
                area: .importParsing,
                level: .warning,
                details: "file=\(parsed.url.lastPathComponent)"
            )
            return
        }

        let expectedPoints = Int(header.pointCount)
        if expectedPoints > 0 {
            for spectrum in parsed.rawSpectra {
                let count = min(spectrum.x.count, spectrum.y.count)
                if count != expectedPoints {
                    Instrumentation.log(
                        "SPC point count mismatch",
                        area: .importParsing,
                        level: .warning,
                        details: "file=\(parsed.url.lastPathComponent) spectrum=\(spectrum.name) expected=\(expectedPoints) actual=\(count)"
                    )
                }
            }
        }

        if header.fileType.isMultiFile, parsed.rawSpectra.count <= 1 {
            Instrumentation.log(
                "SPC multifile flag mismatch",
                area: .importParsing,
                level: .warning,
                details: "file=\(parsed.url.lastPathComponent) spectra=\(parsed.rawSpectra.count)"
            )
        } else if !header.fileType.isMultiFile, parsed.rawSpectra.count > 1 {
            Instrumentation.log(
                "SPC single-file flag mismatch",
                area: .importParsing,
                level: .warning,
                details: "file=\(parsed.url.lastPathComponent) spectra=\(parsed.rawSpectra.count)"
            )
        }

        if !header.fileType.hasPerSubfileX, parsed.rawSpectra.count > 1 {
            let firstX = parsed.rawSpectra.first?.x ?? []
            for spectrum in parsed.rawSpectra.dropFirst() {
                if spectrum.x != firstX {
                    Instrumentation.log(
                        "SPC X-axis mismatch",
                        area: .importParsing,
                        level: .warning,
                        details: "file=\(parsed.url.lastPathComponent) spectrum=\(spectrum.name)"
                    )
                    break
                }
            }
        }
    }

    private func persistParsedFiles(_ parsedFiles: [ParsedFileResult]) {
        guard !parsedFiles.isEmpty else { return }
        do {
            var importedBytes: Int64 = 0
            var existingDatasetKeys = Set(
                (storedDatasets + archivedDatasets)
                    .compactMap { datasetUniquenessKey(fileHash: $0.fileHash, sourcePath: $0.sourcePath) }
            )
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
                let metadataJSON = try? JSONEncoder().encode(parsed.metadata)

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
                    warningsJSON: nil,
                    spectra: spectraModels
                )
                dataset.skippedDataSets = parsed.skippedDataSets
                dataset.warnings = datasetWarnings
                for spectrum in spectraModels {
                    spectrum.dataset = dataset
                }
                modelContext.insert(dataset)
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
            try modelContext.save()
            if importedBytes > 0 {
                dataStoreController.noteLocalChange(bytes: importedBytes)
            }
        } catch {
            Instrumentation.log(
                "SwiftData save failed",
                area: .importParsing,
                level: .warning,
                details: "error=\(error.localizedDescription)"
            )
        }
    }

    private func loadStoredDatasetSelection(append: Bool) {
        let datasets = storedDatasets.filter { selectedStoredDatasetIDs.contains($0.id) }
        guard !datasets.isEmpty else {
            statusMessage = "Select stored dataset(s) to load."
            return
        }
        if append {
            for dataset in datasets {
                loadStoredDataset(dataset, append: true)
            }
            return
        }

        if let first = datasets.first {
            loadStoredDataset(first, append: false)
            for dataset in datasets.dropFirst() {
                loadStoredDataset(dataset, append: true)
            }
        }
    }

    private func loadStoredDatasetPickerSelection(append: Bool) {
        let datasets = storedDatasets.filter { storedDatasetPickerSelection.contains($0.id) }
        guard !datasets.isEmpty else {
            statusMessage = "Select stored datasets to load."
            return
        }

        if append {
            for dataset in datasets {
                loadStoredDataset(dataset, append: true)
            }
            return
        }

        if let first = datasets.first {
            loadStoredDataset(first, append: false)
            for dataset in datasets.dropFirst() {
                loadStoredDataset(dataset, append: true)
            }
        }
    }

    private func loadStoredDataset(_ dataset: StoredDataset, append: Bool) {
        let sortedSpectra = dataset.spectraItems.sorted { $0.orderIndex < $1.orderIndex }
        updateActiveMetadata(from: dataset, append: append)
        var validSpectra: [ShimadzuSpectrum] = []
        var loadedInvalidItems: [InvalidSpectrumItem] = []

        for stored in sortedSpectra {
            let spectrum = ShimadzuSpectrum(name: stored.name, xData: stored.xData, yData: stored.yData)
            if stored.isInvalid {
                let reason = stored.invalidReason ?? "Invalid spectrum"
                loadedInvalidItems.append(
                    InvalidSpectrumItem(
                        spectrum: spectrum,
                        fileName: dataset.fileName,
                        reason: reason
                    )
                )
            } else {
                validSpectra.append(spectrum)
            }
        }

        let wasEmpty = spectra.isEmpty
        if append {
            spectra.append(contentsOf: validSpectra)
        } else {
            spectra = validSpectra
            selectedSpectrumIndex = 0
            selectedSpectrumIndices = []
        }

        alignedSpectra = []
        processedSpectra = []
        pointCache = [:]

        if append {
            selectedSpectrumIndices = selectedSpectrumIndices.filter { $0 >= 0 && $0 < spectra.count }
            if wasEmpty, !spectra.isEmpty {
                selectedSpectrumIndex = 0
                selectedSpectrumIndices = [0]
            } else {
                selectedSpectrumIndex = min(max(selectedSpectrumIndex, 0), max(spectra.count - 1, 0))
            }
        } else if !spectra.isEmpty {
            selectedSpectrumIndices = [0]
        }

        updatePeaks()
        applyAlignmentIfNeeded()

        if spectra.isEmpty {
            statusMessage = "No spectra found."
        } else if append, !validSpectra.isEmpty {
            statusMessage = "Added \(validSpectra.count) spectra from stored dataset."
        } else {
            statusMessage = "Loaded \(spectra.count) spectra from stored dataset."
        }

        if !includeInvalidInPlots {
            selectedInvalidItemIDs.removeAll()
        }

        let skippedCount = dataset.skippedDataSets.count
        if skippedCount > 0 {
            warningMessage = append
                ? "Skipped \(skippedCount) dataset(s) while adding."
                : "Skipped \(skippedCount) dataset(s) in stored file."
        } else {
            warningMessage = nil
        }

        let datasetWarnings = dataset.warnings
        let warningLines = datasetWarnings.map { "\(dataset.fileName): \($0)" }
        if append, !warningLines.isEmpty {
            warningDetails.append(contentsOf: warningLines)
        } else {
            warningDetails = warningLines
        }

        if append, !loadedInvalidItems.isEmpty {
            invalidItems.append(contentsOf: loadedInvalidItems)
        } else {
            invalidItems = loadedInvalidItems
        }
        selectedInvalidItemIDs = []

        if !spectra.isEmpty {
            appMode = .analyze
        }

        updateAIEstimate()
    }

    private func deleteStoredDatasetSelection() {
        let datasets = storedDatasets.filter { selectedStoredDatasetIDs.contains($0.id) }
        guard !datasets.isEmpty else {
            statusMessage = "Select stored dataset(s) to archive."
            return
        }
        pendingArchiveDatasetIDs = Set(datasets.map { $0.id })
        showArchiveConfirmation = true
    }

    private func prepareDuplicateCleanup() {
        let allDatasets = storedDatasets + archivedDatasets
        guard allDatasets.count > 1 else {
            statusMessage = "No duplicates detected."
            return
        }

        var duplicates: [StoredDataset] = []
        var seenKeys = Set<String>()
        for dataset in allDatasets.sorted(by: { $0.importedAt < $1.importedAt }) {
            guard let key = datasetUniquenessKey(fileHash: dataset.fileHash, sourcePath: dataset.sourcePath) else {
                continue
            }
            if seenKeys.contains(key) {
                duplicates.append(dataset)
            } else {
                seenKeys.insert(key)
            }
        }

        guard !duplicates.isEmpty else {
            statusMessage = "No duplicates detected."
            return
        }

        duplicateCleanupTargetIDs = Set(duplicates.map { $0.id })
        let preview = datasetNamePreview(duplicates)
        let base = "This will permanently delete \(duplicates.count) duplicate stored dataset(s)."
        duplicateCleanupMessage = preview.isEmpty ? base : "\(base)\n\n\(preview)"
        showDuplicateCleanupConfirm = true
    }

    private func removeDuplicateDatasets() {
        let datasets = (storedDatasets + archivedDatasets).filter { duplicateCleanupTargetIDs.contains($0.id) }
        guard !datasets.isEmpty else {
            duplicateCleanupTargetIDs.removeAll()
            duplicateCleanupMessage = ""
            return
        }

        for dataset in datasets {
            modelContext.delete(dataset)
        }

        do {
            try modelContext.save()
            let preview = datasetNamePreview(datasets)
            let details = preview.isEmpty ? "count=\(datasets.count)" : "count=\(datasets.count) names=\(preview)"
            Instrumentation.log("Duplicate stored datasets deleted", area: .uiInteraction, level: .warning, details: details)
            statusMessage = "Removed \(datasets.count) duplicate dataset(s)."
            requestCloudSync(reason: "datasetDuplicateCleanup")
        } catch {
            errorMessage = error.localizedDescription
        }

        duplicateCleanupTargetIDs.removeAll()
        duplicateCleanupMessage = ""
    }

    private func archivePendingDatasets() {
        let datasets = storedDatasets.filter { pendingArchiveDatasetIDs.contains($0.id) }
        guard !datasets.isEmpty else {
            pendingArchiveDatasetIDs.removeAll()
            return
        }
        let now = Date()
        for dataset in datasets {
            dataset.isArchived = true
            dataset.archivedAt = now
        }
        do {
            try modelContext.save()
            let preview = datasetNamePreview(datasets)
            let details = preview.isEmpty ? "count=\(datasets.count)" : "count=\(datasets.count) names=\(preview)"
            Instrumentation.log("Stored datasets archived", area: .uiInteraction, level: .info, details: details)
            statusMessage = "Archived \(datasets.count) stored dataset(s)."
            requestCloudSync(reason: "datasetArchive")
        } catch {
            errorMessage = error.localizedDescription
        }
        pendingArchiveDatasetIDs.removeAll()
        selectedStoredDatasetIDs.removeAll()
    }

    private func restoreArchivedSelection() {
        let datasets = archivedDatasets.filter { archivedDatasetSelection.contains($0.id) }
        guard !datasets.isEmpty else { return }
        for dataset in datasets {
            dataset.isArchived = false
            dataset.archivedAt = nil
        }
        do {
            try modelContext.save()
            let preview = datasetNamePreview(datasets)
            let details = preview.isEmpty ? "count=\(datasets.count)" : "count=\(datasets.count) names=\(preview)"
            Instrumentation.log("Stored datasets restored", area: .uiInteraction, level: .info, details: details)
            statusMessage = "Restored \(datasets.count) archived dataset(s)."
            requestCloudSync(reason: "datasetRestore")
        } catch {
            errorMessage = error.localizedDescription
        }
        archivedDatasetSelection.removeAll()
    }

    private func requestPermanentDeleteSelection() {
        let ids = archivedDatasetSelection
        guard !ids.isEmpty else { return }
        pendingPermanentDeleteIDs = ids
        showPermanentDeleteSheet = true
    }

    private func deleteArchivedDatasets() {
        let ids = effectivePermanentDeleteIDs
        let datasets = archivedDatasets.filter { ids.contains($0.id) }
        guard !datasets.isEmpty else {
            pendingPermanentDeleteIDs.removeAll()
            return
        }
        for dataset in datasets {
            modelContext.delete(dataset)
        }
        do {
            try modelContext.save()
            let preview = datasetNamePreview(datasets)
            let details = preview.isEmpty ? "count=\(datasets.count)" : "count=\(datasets.count) names=\(preview)"
            Instrumentation.log("Archived datasets deleted", area: .uiInteraction, level: .warning, details: details)
            statusMessage = "Deleted \(datasets.count) archived dataset(s)."
            requestCloudSync(reason: "datasetDelete")
        } catch {
            errorMessage = error.localizedDescription
        }
        pendingPermanentDeleteIDs.removeAll()
        archivedDatasetSelection.removeAll()
    }

    private func requestCloudSync(reason: String) {
        statusMessage = "iCloud sync requested (\(reason))."
        Instrumentation.log("Requesting iCloud sync", area: .uiInteraction, level: .warning, details: "reason=\(reason)")
        Task {
            let result = await ICloudSyncCoordinator.shared.performBackupNow(reason: reason)
            if reason == "manual" && dataStoreController.cloudSyncEnabled {
                let uploadResult = await ICloudSyncCoordinator.shared.forceCloudKitUpload()
                statusMessage = "iCloud sync result (\(reason)): \(result). Force upload: \(uploadResult)."
            } else {
                statusMessage = "iCloud sync result (\(reason)): \(result)."
            }
            Instrumentation.log(
                "iCloud sync result",
                area: .uiInteraction,
                level: .warning,
                details: "reason=\(reason) result=\(result)"
            )
        }
    }

    private func requestForceUpload(reason: String) {
        statusMessage = "iCloud force upload requested (\(reason))."
        Instrumentation.log("Requesting CloudKit force upload", area: .uiInteraction, level: .warning, details: "reason=\(reason)")
        Task {
            let result = await ICloudSyncCoordinator.shared.forceCloudKitUpload()
            statusMessage = "iCloud force upload result (\(reason)): \(result)."
            Instrumentation.log(
                "CloudKit force upload result",
                area: .uiInteraction,
                level: .warning,
                details: "reason=\(reason) result=\(result)"
            )
        }
    }

    private func applyAlignmentIfNeeded() {
        let baseSpectra = spectraForProcessing
        guard let reference = baseSpectra.first else {
            alignedSpectra = []
            processedSpectra = []
            rebuildCaches()
            Instrumentation.log("Alignment skipped", area: .processing, level: .warning, details: "reason=no spectra")
            return
        }

        let refX = reference.x
        let mismatchDetected = baseSpectra.contains { !SpectraProcessing.axesMatch(refX, $0.x) }

        if !useAlignment {
            alignedSpectra = []
            if mismatchDetected {
                statusMessage = "Axes differ. Enable Align X-Axis to resample."
                Instrumentation.log("Alignment disabled with mismatched axes", area: .processing, level: .warning)
            } else {
                Instrumentation.log("Alignment disabled", area: .processing, level: .info)
            }
            applyProcessing()
            return
        }

        var result: [ShimadzuSpectrum] = []
        result.reserveCapacity(baseSpectra.count)

        for spectrum in baseSpectra {
            if SpectraProcessing.axesMatch(refX, spectrum.x) {
                result.append(spectrum)
            } else {
                let resampledY = SpectraProcessing.resampleLinear(x: spectrum.x, y: spectrum.y, onto: refX)
                let aligned = ShimadzuSpectrum(name: spectrum.name, x: refX, y: resampledY)
                result.append(aligned)
            }
        }

        alignedSpectra = result
        Instrumentation.log("Alignment applied", area: .processing, level: .info, details: "spectra=\(result.count) mismatch=\(mismatchDetected)")
        if mismatchDetected {
            statusMessage = "Axes differed. Resampled to match the first spectrum."
        }
        applyProcessing()
    }

    private func applyProcessing() {
        let started = Date()
        let base = (useAlignment && !alignedSpectra.isEmpty) ? alignedSpectra : spectraForProcessing
        guard !base.isEmpty else {
            processedSpectra = []
            rebuildCaches()
            Instrumentation.log("Processing skipped", area: .processing, level: .warning, details: "reason=no spectra")
            return
        }

        let needsProcessing = smoothingMethod != .none || baselineMethod != .none || normalizationMethod != .none
        guard needsProcessing else {
            processedSpectra = []
            updatePeaks()
            Instrumentation.log("Processing skipped", area: .processing, level: .info, details: "reason=no processing enabled")
            return
        }

        var smoothingDuration: TimeInterval = 0
        var baselineDuration: TimeInterval = 0
        var normalizationDuration: TimeInterval = 0

        processedSpectra = base.map { spectrum in
            var y = spectrum.y
            switch smoothingMethod {
            case .none:
                break
            case .movingAverage:
                let smoothingStart = Date()
                y = SpectraProcessing.movingAverage(y: y, window: smoothingWindow)
                smoothingDuration += Date().timeIntervalSince(smoothingStart)
            case .savitzkyGolay:
                let smoothingStart = Date()
                let order = min(sgOrder, sgWindow - 1)
                y = SpectraProcessing.savitzkyGolay(y: y, window: sgWindow, polynomialOrder: order)
                smoothingDuration += Date().timeIntervalSince(smoothingStart)
            }
            if baselineMethod != .none {
                let baselineStart = Date()
                y = SpectraProcessing.applyBaseline(y: y, x: spectrum.x, method: baselineMethod)
                baselineDuration += Date().timeIntervalSince(baselineStart)
            }
            if normalizationMethod != .none {
                let normalizationStart = Date()
                y = SpectraProcessing.applyNormalization(y: y, x: spectrum.x, method: normalizationMethod)
                normalizationDuration += Date().timeIntervalSince(normalizationStart)
            }
            return ShimadzuSpectrum(name: spectrum.name, x: spectrum.x, y: y)
        }
        updatePeaks()

        let duration = Date().timeIntervalSince(started)
        let stageDetails = String(
            format: "spectra=%d smoothing=%.3fs baseline=%.3fs normalization=%.3fs",
            processedSpectra.count,
            smoothingDuration,
            baselineDuration,
            normalizationDuration
        )
        Instrumentation.log(
            "Processing applied",
            area: .processing,
            level: .info,
            details: stageDetails,
            duration: duration
        )
    }

    private func updatePeaks() {
        guard detectPeaks else {
            peaks = []
            rebuildCaches()
            return
        }
        guard let spectrum = selectedSpectrum else {
            peaks = []
            rebuildCaches()
            return
        }
        peaks = SpectraProcessing.detectPeaks(
            x: spectrum.x,
            y: spectrum.y,
            minHeight: peakMinHeight,
            minDistance: peakMinDistance
        )
        rebuildCaches()
    }

    private func exportCSV(options: ExportOptions) {
        let spectraToExport = alignedForExport()
        guard let first = spectraToExport.first else { return }
        guard let url = savePanel(defaultName: "Spectra.csv", allowedTypes: [UTType.commaSeparatedText], directoryKey: .analysisExports) else { return }

        let started = Date()
        Instrumentation.log("Export CSV started", area: .export, level: .info, details: "spectra=\(spectraToExport.count)")

        var lines: [String] = []
        if options.includeMetadata {
            lines.append("# Title: \(options.title)")
            lines.append("# Operator: \(options.operatorName)")
            lines.append("# Notes: \(options.notes)")
            if let metrics = selectedMetrics {
                lines.append(String(format: "# CriticalWavelength: %.2f", metrics.criticalWavelength))
                lines.append(String(format: "# UVA/UVB Ratio: %.4f", metrics.uvaUvbRatio))
            }
            if let label = selectedSpectrum.flatMap({ SPFLabelStore.matchLabel(for: $0.name) }) {
                lines.append(String(format: "# Label SPF: %.1f", label.spf))
            }
            if let colipa = colipaSpfValue {
                lines.append(String(format: "# COLIPA SPF: %.1f", colipa))
            }
            if let display = displaySpfMetric {
                lines.append(String(format: "# SPF (display): %@ = %.1f", display.label, display.value))
            }
            if let calibration = calibrationResult, let metrics = selectedMetrics {
                let predicted = calibration.predict(metrics: metrics)
                lines.append(String(format: "# Estimated SPF (calibrated): %.1f", predicted))
                lines.append(String(format: "# Calibration R2: %.3f", calibration.r2))
                lines.append(String(format: "# Calibration RMSE: %.2f", calibration.rmse))
            }
        }
        if options.includeProcessing {
            lines.append("# Alignment: \(useAlignment ? "On" : "Off")")
            lines.append("# Smoothing: \(smoothingMethod.rawValue)")
            lines.append("# YAxis: \(yAxisMode.rawValue)")
            if smoothingMethod == .movingAverage {
                lines.append("# SmoothingWindow: \(smoothingWindow)")
            }
            if smoothingMethod == .savitzkyGolay {
                lines.append("# SGWindow: \(sgWindow)")
                lines.append("# SGOrder: \(sgOrder)")
            }
            lines.append("# Baseline: \(baselineMethod.rawValue)")
            lines.append("# Normalization: \(normalizationMethod.rawValue)")
        }

        var header = ["Wavelength (\(yAxisMode.rawValue))"]
        header.append(contentsOf: spectraToExport.map { sanitizeCSVField($0.name) })
        lines.append(header.joined(separator: ","))

        let count = first.x.count
        for i in 0..<count {
            var row = [String(format: "%.6f", first.x[i])]
            for spectrum in spectraToExport {
                let yVal = i < spectrum.y.count ? spectrum.y[i] : 0.0
                row.append(String(format: "%.6f", yVal))
            }
            lines.append(row.joined(separator: ","))
        }

        do {
            try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            let duration = Date().timeIntervalSince(started)
            Instrumentation.log("Export CSV completed", area: .export, level: .info, duration: duration)
        } catch {
            Instrumentation.log("Export CSV failed", area: .export, level: .error, details: "error=\(error.localizedDescription)")
            errorMessage = "Failed to export CSV: \(error.localizedDescription)"
        }
    }

    private func exportJCAMP(options: ExportOptions) {
        let spectraToExport = alignedForExport()
        let jdx = UTType(filenameExtension: "jdx") ?? .data
        let jcamp = UTType(filenameExtension: "jcamp") ?? .data
        guard let url = savePanel(defaultName: "Spectra.jdx", allowedTypes: [jdx, jcamp], directoryKey: .analysisExports) else { return }

        let started = Date()
        Instrumentation.log("Export JCAMP started", area: .export, level: .info, details: "spectra=\(spectraToExport.count)")

        var output = "##JCAMP-DX=5.00\n##DATA TYPE=UV/VIS SPECTRUM\n"
        if options.includeMetadata {
            if !options.title.isEmpty { output += "##TITLE=\(options.title)\n" }
            if !options.operatorName.isEmpty { output += "##OWNER=\(options.operatorName)\n" }
            if !options.notes.isEmpty { output += "##COMMENT=\(options.notes)\n" }
            if let metrics = selectedMetrics {
                output += String(format: "##CRITICALWAVELENGTH=%.2f\n", metrics.criticalWavelength)
                output += String(format: "##UVAUVBRATIO=%.4f\n", metrics.uvaUvbRatio)
            }
            if let label = selectedSpectrum.flatMap({ SPFLabelStore.matchLabel(for: $0.name) }) {
                output += String(format: "##LABELSPF=%.1f\n", label.spf)
            }
            if let colipa = colipaSpfValue {
                output += String(format: "##COLIPASPF=%.1f\n", colipa)
            }
            if let display = displaySpfMetric {
                output += "##SPFDISPLAY=\(display.label) \(String(format: "%.1f", display.value))\n"
            }
            if let calibration = calibrationResult, let metrics = selectedMetrics {
                let predicted = calibration.predict(metrics: metrics)
                output += String(format: "##ESTIMATEDSPF=%.1f\n", predicted)
                output += String(format: "##CALIBRATIONR2=%.3f\n", calibration.r2)
                output += String(format: "##CALIBRATIONRMSE=%.2f\n", calibration.rmse)
            }
        }
        if options.includeProcessing {
            output += "##SPECTRASETTINGS=Alignment=\(useAlignment ? "On" : "Off")\n"
            output += "##SPECTRASETTINGS=Smoothing=\(smoothingMethod.rawValue)\n"
            output += "##SPECTRASETTINGS=YAxis=\(yAxisMode.rawValue)\n"
            if smoothingMethod == .movingAverage {
                output += "##SPECTRASETTINGS=SmoothingWindow=\(smoothingWindow)\n"
            }
            if smoothingMethod == .savitzkyGolay {
                output += "##SPECTRASETTINGS=SGWindow=\(sgWindow)\n"
                output += "##SPECTRASETTINGS=SGOrder=\(sgOrder)\n"
            }
            output += "##SPECTRASETTINGS=Baseline=\(baselineMethod.rawValue)\n"
            output += "##SPECTRASETTINGS=Normalization=\(normalizationMethod.rawValue)\n"
        }

        for spectrum in spectraToExport {
            output += "##TITLE=\(spectrum.name)\n"
            output += "##NPOINTS=\(spectrum.x.count)\n"
            output += "##XYDATA= (X++(Y..Y))\n"
            for i in 0..<spectrum.x.count {
                let xVal = spectrum.x[i]
                let yVal = i < spectrum.y.count ? spectrum.y[i] : 0.0
                output += String(format: "%.6f, %.6f\n", xVal, yVal)
            }
            output += "##END=\n"
        }

        do {
            try output.write(to: url, atomically: true, encoding: .utf8)
            let duration = Date().timeIntervalSince(started)
            Instrumentation.log("Export JCAMP completed", area: .export, level: .info, duration: duration)
        } catch {
            Instrumentation.log("Export JCAMP failed", area: .export, level: .error, details: "error=\(error.localizedDescription)")
            errorMessage = "Failed to export JCAMP: \(error.localizedDescription)"
        }
    }

    private func exportExcelXLSX(options: ExportOptions) {
        let spectraToExport = alignedForExport()
        guard let first = spectraToExport.first else { return }
        let xlsx = UTType(filenameExtension: "xlsx") ?? .data
        guard let url = savePanel(defaultName: "Spectra.xlsx", allowedTypes: [xlsx], directoryKey: .analysisExports) else { return }

        let started = Date()
        Instrumentation.log("Export XLSX started", area: .export, level: .info, details: "spectra=\(spectraToExport.count)")

        var header = ["Wavelength (\(yAxisMode.rawValue))"]
        header.append(contentsOf: spectraToExport.map { $0.name })

        var rows: [[String]] = []
        if options.includeMetadata {
            let headerLines = spcHeaderExportLines()
            if !headerLines.isEmpty {
                rows.append(["SPC Header", ""]) 
                for line in headerLines {
                    let parts = line.split(separator: ":", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespaces) }
                    if parts.count == 2 {
                        rows.append([parts[0], parts[1]])
                    } else {
                        rows.append([line])
                    }
                }
                rows.append([])
            }

            let mathLines = spfMathExportLines()
            if !mathLines.isEmpty {
                rows.append(["SPF Math", ""]) 
                for line in mathLines {
                    let parts = line.split(separator: ":", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespaces) }
                    if parts.count == 2 {
                        rows.append([parts[0], parts[1]])
                    } else {
                        rows.append([line])
                    }
                }
                rows.append([])
            }
        }

        let count = first.x.count
        for i in 0..<count {
            var row = [String(format: "%.6f", first.x[i])]
            for spectrum in spectraToExport {
                let yVal = i < spectrum.y.count ? spectrum.y[i] : 0.0
                row.append(String(format: "%.6f", yVal))
            }
            rows.append(row)
        }

        do {
            try OOXMLWriter.writeXlsx(header: header, rows: rows, to: url)
            let duration = Date().timeIntervalSince(started)
            Instrumentation.log("Export XLSX completed", area: .export, level: .info, duration: duration)
        } catch {
            Instrumentation.log("Export XLSX failed", area: .export, level: .error, details: "error=\(error.localizedDescription)")
            errorMessage = "Failed to export XLSX: \(error.localizedDescription)"
        }
    }

    private func exportWordDOCX(options: ExportOptions) {
        let report = buildAnalysisReport(options: options)
        let docx = UTType(filenameExtension: "docx") ?? .data
        guard let url = savePanel(defaultName: "Analysis Report.docx", allowedTypes: [docx], directoryKey: .analysisExports) else { return }

        let started = Date()
        Instrumentation.log("Export DOCX started", area: .export, level: .info)

        do {
            try OOXMLWriter.writeDocx(report: report, to: url)
            let duration = Date().timeIntervalSince(started)
            Instrumentation.log("Export DOCX completed", area: .export, level: .info, duration: duration)
        } catch {
            Instrumentation.log("Export DOCX failed", area: .export, level: .error, details: "error=\(error.localizedDescription)")
            errorMessage = "Failed to export DOCX: \(error.localizedDescription)"
        }
    }

    private func exportPDFReport(options: ExportOptions) {
        let reportData = buildPDFReportData(options: options)
        guard let url = savePanel(defaultName: "Analysis Report.pdf", allowedTypes: [UTType.pdf], directoryKey: .analysisExports) else { return }

        let started = Date()
        Instrumentation.log("Export PDF started", area: .export, level: .info)

        let data = PDFReportRenderer.render(data: reportData)
        do {
            try data.write(to: url)
            let duration = Date().timeIntervalSince(started)
            Instrumentation.log("Export PDF completed", area: .export, level: .info, duration: duration)
        } catch {
            Instrumentation.log("Export PDF failed", area: .export, level: .error, details: "error=\(error.localizedDescription)")
            errorMessage = "Failed to export PDF: \(error.localizedDescription)"
        }
    }

    private func exportHTMLReport(options: ExportOptions) {
        let html = buildHTMLReport(options: options)
        guard let url = savePanel(defaultName: "Analysis Report.html", allowedTypes: [UTType.html], directoryKey: .analysisExports) else { return }

        let started = Date()
        Instrumentation.log("Export HTML started", area: .export, level: .info)

        do {
            try html.write(to: url, atomically: true, encoding: .utf8)
            let duration = Date().timeIntervalSince(started)
            Instrumentation.log("Export HTML completed", area: .export, level: .info, duration: duration)
        } catch {
            Instrumentation.log("Export HTML failed", area: .export, level: .error, details: "error=\(error.localizedDescription)")
            errorMessage = "Failed to export HTML: \(error.localizedDescription)"
        }
    }

    private func buildPDFReportData(options: ExportOptions) -> PDFReportData {
        let title = options.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "SPF Spectral Analyzer Report"
            : options.title
        let metadataLines = buildPDFReportMetadataLines(options: options)
        let metricRows = buildPDFReportMetricRows()
        let aiSummary = reportAISummary()
        let recommendations = (aiStructuredOutput?.recommendations ?? []).map {
            ReportRecommendation(ingredient: $0.ingredient, amount: $0.amount, rationale: $0.rationale)
        }
        let series = reportSeries()

        return PDFReportData(
            title: title,
            generatedAt: Date(),
            metadataLines: metadataLines,
            metricRows: metricRows,
            aiSummary: aiSummary,
            recommendations: recommendations,
            series: series
        )
    }

    private func buildPDFReportMetadataLines(options: ExportOptions) -> [String] {
        var lines: [String] = []
        if options.includeMetadata {
            if !options.operatorName.isEmpty {
                lines.append("Operator: \(options.operatorName)")
            }
            if !options.notes.isEmpty {
                lines.append("Notes: \(options.notes)")
            }
            lines.append("Scope: \(effectiveAIScope.label)")
            lines.append("Spectra count: \(aiSpectraForScope().count)")
            lines.append(contentsOf: spcHeaderExportLines())
        }

        if options.includeProcessing {
            lines.append("Alignment: \(useAlignment ? "On" : "Off")")
            lines.append("Smoothing: \(smoothingMethod.rawValue)")
            lines.append("Baseline: \(baselineMethod.rawValue)")
            lines.append("Normalization: \(normalizationMethod.rawValue)")
            lines.append("YAxis: \(yAxisMode.rawValue)")
        }

        return lines
    }

    private func buildPDFReportMetricRows() -> [ReportMetricRow] {
        var rows: [ReportMetricRow] = []

        if let metrics = selectedMetrics {
            rows.append(ReportMetricRow(label: "Critical wavelength", value: String(format: "%.1f nm", metrics.criticalWavelength)))
            rows.append(ReportMetricRow(label: "UVA/UVB ratio", value: String(format: "%.3f", metrics.uvaUvbRatio)))
            rows.append(ReportMetricRow(label: "Mean UVB transmittance", value: String(format: "%.3f", metrics.meanUVBTransmittance)))
        }

        if let colipa = colipaSpfValue {
            rows.append(ReportMetricRow(label: "COLIPA SPF", value: String(format: "%.1f", colipa)))
        }

        if let estimated = estimatedSpfValue {
            rows.append(ReportMetricRow(label: "Estimated SPF (calibrated)", value: String(format: "%.1f", estimated)))
        }

        if let calibration = calibrationResult {
            rows.append(ReportMetricRow(label: "Calibration R²", value: String(format: "%.3f", calibration.r2)))
            rows.append(ReportMetricRow(label: "Calibration RMSE", value: String(format: "%.2f", calibration.rmse)))
        }

        if let stats = selectedMetricsStats, selectedSpectra.count > 1 {
            rows.append(ReportMetricRow(label: "Avg UVA/UVB", value: String(format: "%.3f", stats.avgUvaUvb)))
            rows.append(ReportMetricRow(label: "Avg critical λ", value: String(format: "%.1f nm", stats.avgCritical)))
        }

        if let dashboard = dashboardMetrics {
            rows.append(ReportMetricRow(label: "Compliance SPF≥30", value: String(format: "%.0f%%", dashboard.compliancePercent)))
            rows.append(ReportMetricRow(label: "Low critical λ count", value: "\(dashboard.lowCriticalCount)"))
        }

        return rows
    }

    private func buildHTMLReport(options: ExportOptions) -> String {
        let title = options.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "SPF Spectral Analyzer Report"
            : options.title
        let metadataLines = buildPDFReportMetadataLines(options: options)
        let metricRows = buildPDFReportMetricRows()
        let aiSummary = reportAISummary()
        let recommendations = (aiStructuredOutput?.recommendations ?? [])

        let seriesTable = buildHTMLSeriesTable()
        let metadataHTML = metadataLines.map { "<li>\(htmlEscape($0))</li>" }.joined()
        let metricsHTML = metricRows.map { "<tr><td>\(htmlEscape($0.label))</td><td>\(htmlEscape($0.value))</td></tr>" }.joined()
        let recommendationsHTML = recommendations.map { rec in
            let rationale = rec.rationale?.isEmpty == false ? "<div class=\"muted\">\(htmlEscape(rec.rationale ?? ""))</div>" : ""
            return "<li><strong>\(htmlEscape(rec.ingredient))</strong> — \(htmlEscape(rec.amount))\(rationale)</li>"
        }.joined()

        return """
<!doctype html>
<html lang=\"en\">
<head>
<meta charset=\"utf-8\">
<title>\(htmlEscape(title))</title>
<style>
body { font-family: -apple-system, BlinkMacSystemFont, 'Helvetica Neue', sans-serif; margin: 24px; color: #222; }
header { margin-bottom: 16px; }
h1 { font-size: 20px; margin: 0; }
section { margin-top: 16px; }
.muted { color: #666; font-size: 12px; }
table { border-collapse: collapse; width: 100%; font-size: 12px; }
th, td { border: 1px solid #ddd; padding: 6px; text-align: left; }
.small { font-size: 11px; }
</style>
</head>
<body>
<header>
  <h1>\(htmlEscape(title))</h1>
  <div class=\"muted\">Generated: \(htmlEscape(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short)))</div>
</header>

<section>
  <h2 class=\"small\">Metadata</h2>
  <ul class=\"small\">\(metadataHTML)</ul>
</section>

<section>
  <h2 class=\"small\">Key Metrics</h2>
  <table>\(metricsHTML)</table>
</section>

<section>
  <h2 class=\"small\">AI Summary</h2>
  <p class=\"small\">\(htmlEscape(aiSummary))</p>
</section>

<section>
  <h2 class=\"small\">Recommendations</h2>
  <ul class=\"small\">\(recommendationsHTML.isEmpty ? "<li>None provided</li>" : recommendationsHTML)</ul>
</section>

<section>
  <h2 class=\"small\">Spectra (Downsampled)</h2>
  \(seriesTable)
</section>
</body>
</html>
"""
    }

    private func buildHTMLSeriesTable() -> String {
        let series = seriesToPlot
        guard !series.isEmpty else { return "<div class=\"muted\">No spectra available.</div>" }

        let downsampled = series.map { series in
            let points = downsampleReportPoints(series.points, targetCount: 120)
            return (name: series.name, points: points)
        }

        let header = (["Wavelength"] + downsampled.map { $0.name }).map { "<th>\(htmlEscape($0))</th>" }.joined()

        let count = downsampled.first?.points.count ?? 0
        var rows: [String] = []
        for index in 0..<count {
            var columns: [String] = []
            let xValue = downsampled[0].points[index].x
            columns.append("<td>\(String(format: "%.2f", xValue))</td>")
            for series in downsampled {
                let yValue = series.points.indices.contains(index) ? series.points[index].y : 0
                columns.append("<td>\(String(format: "%.4f", yValue))</td>")
            }
            rows.append("<tr>\(columns.joined())</tr>")
        }

        return "<table><tr>\(header)</tr>\(rows.joined())</table>"
    }

    private func htmlEscape(_ value: String) -> String {
        var escaped = value
        escaped = escaped.replacingOccurrences(of: "&", with: "&amp;")
        escaped = escaped.replacingOccurrences(of: "<", with: "&lt;")
        escaped = escaped.replacingOccurrences(of: ">", with: "&gt;")
        escaped = escaped.replacingOccurrences(of: "\"", with: "&quot;")
        return escaped
    }

    private func reportAISummary() -> String {
        if let summary = aiStructuredOutput?.summary, !summary.isEmpty {
            return summary
        }
        guard let text = aiResult?.text, !text.isEmpty else { return "No AI output available." }
        let paragraphs = text.components(separatedBy: "\n\n")
        return paragraphs.first ?? text
    }

    private func reportSeries() -> [ReportSpectrumSeries] {
        seriesToPlot.map { series in
            let points = downsampleReportPoints(series.points, targetCount: 200)
            return ReportSpectrumSeries(name: series.name, points: points, color: series.color)
        }
    }

    private func downsampleReportPoints(_ points: [SpectrumPoint], targetCount: Int) -> [ReportSpectrumPoint] {
        guard !points.isEmpty else { return [] }
        guard points.count > targetCount else {
            return points.map { ReportSpectrumPoint(x: $0.x, y: $0.y) }
        }

        let stride = max(points.count / targetCount, 1)
        var sampled: [ReportSpectrumPoint] = []
        sampled.reserveCapacity(targetCount + 1)
        for (index, point) in points.enumerated() where index % stride == 0 {
            sampled.append(ReportSpectrumPoint(x: point.x, y: point.y))
        }
        return sampled
    }

    private func spcHeaderExportLines() -> [String] {
        guard let header = activeHeader else { return [] }
        var lines: [String] = []
        if let fileName = activeHeaderFileName {
            lines.append("File: \(fileName)")
        }
        if !header.sourceInstrumentText.isEmpty {
            lines.append("Instrument: \(header.sourceInstrumentText)")
        }
        lines.append("Experiment: \(header.experimentType.label) (code \(header.experimentType.rawValue))")
        lines.append("Points: \(header.pointCount)")
        lines.append(String(format: "X Range: %.4f – %.4f", header.firstX, header.lastX))
        lines.append("X Units: \(header.xUnit.formatted)")
        lines.append("Y Units: \(header.yUnit.formatted)")
        if !header.fileType.labels.isEmpty {
            lines.append("Flags: \(header.fileType.labels.joined(separator: ", "))")
        }
        if !header.memo.isEmpty {
            lines.append("Memo: \(header.memo)")
        }
        return lines
    }

    private func spfMathExportLines() -> [String] {
        guard let spectrum = selectedSpectrum, let metrics = selectedMetrics else { return [] }
        return buildSpfMathLines(spectrum: spectrum, metrics: metrics, calibration: calibrationResult)
    }

    private func buildAnalysisReport(options: ExportOptions) -> String {
        var sections: [String] = []
        sections.append("SPC Analyzer Report")
        sections.append("Generated: \(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short))")
        sections.append("")

        if options.includeMetadata {
            sections.append("Metadata")
            sections.append("Title: \(options.title)")
            sections.append("Operator: \(options.operatorName)")
            if !options.notes.isEmpty {
                sections.append("Notes: \(options.notes)")
            }
            sections.append("")

            let headerLines = spcHeaderExportLines()
            if !headerLines.isEmpty {
                sections.append("SPC Header")
                sections.append(contentsOf: headerLines)
                sections.append("")
            }
        }

        sections.append("Selection")
        sections.append("Scope: \(effectiveAIScope.label)")
        sections.append("Spectra count: \(aiSpectraForScope().count)")
        if let selectedSpectrum {
            sections.append("Selected spectrum: \(selectedSpectrum.name)")
        }
        sections.append("")

        if options.includeProcessing {
            sections.append("Processing")
            sections.append("Alignment: \(useAlignment ? "On" : "Off")")
            sections.append("Smoothing: \(smoothingMethod.rawValue)")
            if smoothingMethod == .movingAverage {
                sections.append("Smoothing window: \(smoothingWindow)")
            }
            if smoothingMethod == .savitzkyGolay {
                sections.append("SG window: \(sgWindow)")
                sections.append("SG order: \(sgOrder)")
            }
            sections.append("Baseline: \(baselineMethod.rawValue)")
            sections.append("Normalization: \(normalizationMethod.rawValue)")
            sections.append("YAxis: \(yAxisMode.rawValue)")
            sections.append("")
        }

        if let metrics = selectedMetrics {
            sections.append("Metrics")
            sections.append(String(format: "Critical wavelength: %.2f nm", metrics.criticalWavelength))
            sections.append(String(format: "UVA/UVB ratio: %.4f", metrics.uvaUvbRatio))
            sections.append(String(format: "Mean UVB transmittance: %.4f", metrics.meanUVBTransmittance))
            if let label = selectedSpectrum.flatMap({ SPFLabelStore.matchLabel(for: $0.name) }) {
                sections.append(String(format: "Label SPF: %.1f", label.spf))
            }
            if let colipa = colipaSpfValue {
                sections.append(String(format: "COLIPA SPF: %.1f", colipa))
            }
            if let estimated = estimatedSpfValue {
                sections.append(String(format: "Estimated SPF (calibrated): %.1f", estimated))
            }
            if let calibration = calibrationResult {
                sections.append(String(format: "Calibration R2: %.3f", calibration.r2))
                sections.append(String(format: "Calibration RMSE: %.2f", calibration.rmse))
            }
            sections.append("")
        }

        let mathLines = spfMathExportLines()
        if !mathLines.isEmpty {
            sections.append("SPF Math")
            sections.append(contentsOf: mathLines)
            sections.append("")
        }

        sections.append("AI Analysis")
        if let aiResult {
            sections.append(aiResult.text)
        } else {
            sections.append("No AI output available.")
        }

        return sections.joined(separator: "\n")
    }

    private func exportPeaksCSV() {
        guard !peaks.isEmpty else { return }
        guard let url = savePanel(defaultName: "Peaks.csv", allowedTypes: [UTType.commaSeparatedText], directoryKey: .analysisExports) else { return }

        let started = Date()
        Instrumentation.log("Export Peaks CSV started", area: .export, level: .info, details: "peaks=\(peaks.count)")

        var lines: [String] = []
        lines.append("Wavelength,Intensity")
        for peak in peaks {
            lines.append(String(format: "%.6f,%.6f", peak.x, peak.y))
        }

        do {
            try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            let duration = Date().timeIntervalSince(started)
            Instrumentation.log("Export Peaks CSV completed", area: .export, level: .info, duration: duration)
        } catch {
            Instrumentation.log("Export Peaks CSV failed", area: .export, level: .error, details: "error=\(error.localizedDescription)")
            errorMessage = "Failed to export peaks CSV: \(error.localizedDescription)"
        }
    }

    private func alignedForExport() -> [ShimadzuSpectrum] {
        let base = displayedSpectra
        guard let reference = base.first else { return base }
        let refX = reference.x

        let mismatchDetected = base.contains { !SpectraProcessing.axesMatch(refX, $0.x) }
        if !mismatchDetected { return base }

        return base.map { spectrum in
            if SpectraProcessing.axesMatch(refX, spectrum.x) {
                return spectrum
            }
            let resampledY = SpectraProcessing.resampleLinear(x: spectrum.x, y: spectrum.y, onto: refX)
            return ShimadzuSpectrum(name: spectrum.name, x: refX, y: resampledY)
        }
    }

    private func savePanel(defaultName: String, allowedTypes: [UTType], directoryKey: SaveDirectoryKey) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = defaultName
        panel.allowedContentTypes = allowedTypes
        panel.canCreateDirectories = true
        if let directory = lastSaveDirectoryURL(for: directoryKey) {
            panel.directoryURL = directory
        }
        if panel.runModal() == .OK, let url = panel.url {
            storeLastSaveDirectory(from: url, key: directoryKey)
            return url
        }
        return nil
    }

    private enum SaveDirectoryKey: String {
        case analysisExports = "lastSaveDirectory.analysisExports"
        case aiReports = "lastSaveDirectory.aiReports"
        case aiLogs = "lastSaveDirectory.aiLogs"
        case instrumentationLogs = "lastSaveDirectory.instrumentationLogs"
        case validationLogs = "lastSaveDirectory.validationLogs"
    }

    private func lastSaveDirectoryURL(for key: SaveDirectoryKey) -> URL? {
        guard let path = UserDefaults.standard.string(forKey: key.rawValue) else { return nil }
        return URL(fileURLWithPath: path)
    }

    private func storeLastSaveDirectory(from url: URL, key: SaveDirectoryKey) {
        let directory = url.deletingLastPathComponent()
        UserDefaults.standard.set(directory.path, forKey: key.rawValue)
    }

    private func sanitizeCSVField(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return value
    }

    private func rebuildCaches() {
        let current = displayedSpectra
        let plotSpectra = spectraForPlotting
        cachedAverageSpectrum = averageSpectrum(from: current)

        let yAxis = yAxisMode
        let selectedSnapshot = selectedSpectrum.map { (x: $0.x, y: $0.y) }
        let selectedSpectraSnapshots = selectedSpectra.map { (x: $0.x, y: $0.y) }
        let calibrationSnapshots: [(labelSPF: Double, x: [Double], y: [Double])] = displayedSpectra.compactMap { spectrum in
            guard let label = SPFLabelStore.matchLabel(for: spectrum.name) else { return nil }
            return (labelSPF: label.spf, x: spectrum.x, y: spectrum.y)
        }
        let dashboardSnapshots = current.map { (name: $0.name, x: $0.x, y: $0.y) }

        Task {
            let result = await SpectralMetricsWorker.shared.compute(
                selectedSnapshot: selectedSnapshot,
                selectedSpectraSnapshots: selectedSpectraSnapshots,
                calibrationSnapshots: calibrationSnapshots,
                dashboardSnapshots: dashboardSnapshots,
                yAxisMode: yAxis
            )

            await MainActor.run {
                cachedSelectedMetrics = result.selectedMetrics
                cachedSelectedMetricsStats = result.metricsStats
                cachedCalibration = result.calibration
                cachedColipaSpf = result.colipaSpf
                cachedDashboardMetrics = result.dashboard
            }
        }

        var newCache: [String: [SpectrumPoint]] = [:]
        for spectrum in plotSpectra {
            let key = pointCacheKey(for: spectrum, range: chartWavelengthRange)
            newCache[key] = buildPoints(for: spectrum, range: chartWavelengthRange)
        }
        if let avg = cachedAverageSpectrum {
            let key = pointCacheKey(for: avg, range: chartWavelengthRange)
            newCache[key] = buildPoints(for: avg, range: chartWavelengthRange)
        }
        pointCache = newCache

        cachedSeries = seriesToPlot(from: plotSpectra)
        Instrumentation.log(
            "Chart cache rebuilt",
            area: .chartRendering,
            level: .info,
            details: "series=\(cachedSeries.count) cacheEntries=\(pointCache.count)"
        )
    }

    private func seriesToPlot(from spectra: [ShimadzuSpectrum]) -> [SpectrumSeries] {
        let limited = spectra.prefix(overlayLimit)
        return limited.enumerated().map { index, spectrum in
            SpectrumSeries(
                name: spectrum.name,
                points: points(for: spectrum),
                color: palette.colors[index % palette.colors.count]
            )
        }
    }

    private func averageSpectrum(from spectra: [ShimadzuSpectrum]) -> ShimadzuSpectrum? {
        guard let first = spectra.first else { return nil }
        let count = spectra.count
        if count == 0 { return nil }

        var sum = Array(repeating: 0.0, count: first.y.count)
        for spectrum in spectra {
            let n = min(sum.count, spectrum.y.count)
            for i in 0..<n {
                sum[i] += spectrum.y[i]
            }
        }
        let avg = sum.map { $0 / Double(count) }
        return ShimadzuSpectrum(name: "Average", x: first.x, y: avg)
    }


}

private struct SpectrumPoint: Identifiable {
    let id: Int
    let x: Double
    let y: Double
}

private struct SpectrumSeries: Identifiable {
    let id = UUID()
    let name: String
    let points: [SpectrumPoint]
    let color: Color
}

private struct PDFReportData {
    var title: String
    var generatedAt: Date
    var metadataLines: [String]
    var metricRows: [ReportMetricRow]
    var aiSummary: String
    var recommendations: [ReportRecommendation]
    var series: [ReportSpectrumSeries]
}

private struct ReportMetricRow: Identifiable {
    let id = UUID()
    let label: String
    let value: String
}

private struct ReportRecommendation: Identifiable {
    let id = UUID()
    let ingredient: String
    let amount: String
    let rationale: String?
}

private struct ReportSpectrumPoint: Identifiable {
    let id = UUID()
    let x: Double
    let y: Double
}

private struct ReportSpectrumSeries: Identifiable {
    let id = UUID()
    let name: String
    let points: [ReportSpectrumPoint]
    let color: Color
}

private struct AutoReportView: View {
    let data: PDFReportData

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            reportHeader
            Divider()
            reportMetrics
            Divider()
            reportChart
            Divider()
            reportSummary
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white)
    }

    private var reportHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(data.title)
                .font(.system(size: 20, weight: .bold))
            Text("Generated: \(formattedDate(data.generatedAt))")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            if !data.metadataLines.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(data.metadataLines, id: \.self) { line in
                        Text(line)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private var reportMetrics: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Key Metrics")
                .font(.system(size: 14, weight: .semibold))

            if data.metricRows.isEmpty {
                Text("No metrics available.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    ForEach(data.metricRows) { row in
                        GridRow {
                            Text(row.label)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Text(row.value)
                                .font(.system(size: 11, weight: .semibold))
                        }
                    }
                }
            }
        }
    }

    private var reportChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Spectra Overview")
                .font(.system(size: 14, weight: .semibold))

            if data.series.isEmpty {
                Text("No spectra available.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            } else {
                Chart {
                    ForEach(data.series) { series in
                        ForEach(series.points) { point in
                            LineMark(
                                x: .value("Wavelength", point.x),
                                y: .value("Intensity", point.y)
                            )
                            .foregroundStyle(series.color)
                        }
                    }
                }
                .frame(height: 220)
            }
        }
    }

    private var reportSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AI Summary")
                .font(.system(size: 14, weight: .semibold))
            Text(data.aiSummary)
                .font(.system(size: 11))

            if !data.recommendations.isEmpty {
                Text("Recommendations")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.top, 4)

                ForEach(data.recommendations) { rec in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(rec.ingredient): \(rec.amount)")
                            .font(.system(size: 11, weight: .semibold))
                        if let rationale = rec.rationale, !rationale.isEmpty {
                            Text(rationale)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

private enum PDFReportRenderer {
    static func render(data: PDFReportData, size: CGSize = CGSize(width: 612, height: 792)) -> Data {
        let view = AutoReportView(data: data)
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = CGRect(origin: .zero, size: size)
        hostingView.layoutSubtreeIfNeeded()
        return hostingView.dataWithPDF(inside: hostingView.bounds)
    }
}

private struct AIRequestPayload: Encodable {
    var preset: String
    var prompt: String
    var temperature: Double
    var maxTokens: Int
    var selectionScope: String
    var yAxisMode: String
    var metricsRange: [Double]
    var spectra: [AISpectrumPayload]
}

private struct AISpectrumPayload: Encodable {
    var name: String
    var points: [AIPointPayload]
    var metrics: AIMetricsPayload?
}

private struct AIPointPayload: Encodable {
    var x: Double
    var y: Double
}

private struct AIMetricsPayload: Encodable {
    var criticalWavelength: Double
    var uvaUvbRatio: Double
    var meanUVB: Double
}

private enum AIAuthError: LocalizedError {
    case missingAPIKey
    case missingOpenAIEndpoint
    case invalidOpenAIEndpoint
    case missingOpenAIModel
    case openAIConnectionFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "OpenAI API key is not configured."
        case .missingOpenAIEndpoint:
            return "OpenAI endpoint is not configured."
        case .invalidOpenAIEndpoint:
            return "OpenAI endpoint is invalid."
        case .missingOpenAIModel:
            return "OpenAI model is not configured."
        case .openAIConnectionFailed(let message):
            return "OpenAI connection failed: \(message)"
        }
    }
}

private struct AIStructuredOutput: Codable {
    var summary: String?
    var insights: [String]
    var risks: [String]
    var actions: [String]
    var recommendations: [AIRecommendation]?
}

private struct AIRecommendation: Codable, Identifiable {
    let id = UUID()
    var ingredient: String
    var amount: String
    var rationale: String?

    enum CodingKeys: String, CodingKey {
        case ingredient
        case amount
        case rationale
    }
}

private struct ParsedAIResponse {
    let text: String
    let structured: AIStructuredOutput?
}

private struct AIResponse: Decodable {
    var text: String
}

private struct OpenAIResponsesRequest: Encodable {
    var model: String
    var input: [OpenAIInputMessage]
    var temperature: Double
    var maxOutputTokens: Int
    var text: OpenAIResponseText?

    enum CodingKeys: String, CodingKey {
        case model
        case input
        case temperature
        case maxOutputTokens = "max_output_tokens"
        case text
    }
}

private struct OpenAIResponseText: Encodable {
    var format: OpenAIResponseTextFormat
}

private struct OpenAIResponseTextFormat: Encodable {
    var type: String
    var name: String
    var strict: Bool
    var schema: JSONSchema
}

private final class JSONSchema: Encodable {
    var type: String
    var properties: [String: JSONSchema]?
    var items: JSONSchema?
    var required: [String]?
    var description: String?
    var additionalProperties: Bool?
    var enumValues: [String]?

    init(
        type: String,
        properties: [String: JSONSchema]? = nil,
        items: JSONSchema? = nil,
        required: [String]? = nil,
        description: String? = nil,
        additionalProperties: Bool? = nil,
        enumValues: [String]? = nil
    ) {
        self.type = type
        self.properties = properties
        self.items = items
        self.required = required
        self.description = description
        self.additionalProperties = additionalProperties
        self.enumValues = enumValues
    }

    enum CodingKeys: String, CodingKey {
        case type
        case properties
        case items
        case required
        case description
        case additionalProperties
        case enumValues = "enum"
    }
}

private struct OpenAIInputMessage: Encodable {
    var type: String = "message"
    var role: String
    var content: [OpenAIInputContent]
}

private struct OpenAIInputContent: Encodable {
    var type: String = "input_text"
    var text: String

    init(text: String) {
        self.text = text
    }
}

private struct OpenAIResponsesResponse: Decodable {
    var output: [OpenAIOutputItem]?

    var outputText: String? {
        let contents = output?.flatMap { $0.content ?? [] } ?? []
        let texts = contents.compactMap { content in
            if let type = content.type, type == "output_text" || type == "text" {
                return content.text
            }
            return content.text
        }
        return texts.first
    }
}

private struct OpenAIOutputItem: Decodable {
    var type: String?
    var content: [OpenAIOutputContent]?
}

private struct OpenAIOutputContent: Decodable {
    var type: String?
    var text: String?
}

private extension ContentView {
    func points(for spectrum: ShimadzuSpectrum) -> [SpectrumPoint] {
        let key = pointCacheKey(for: spectrum, range: chartWavelengthRange)
        return pointCache[key] ?? buildPoints(for: spectrum, range: chartWavelengthRange)
    }

    func selectSpectrumNearest(toX xValue: Double, y yValue: Double) {
        let candidates = showSelectedOnly ? selectedSpectra : displayedSpectra
        guard !candidates.isEmpty else { return }

        var bestName: String?
        var bestDistance = Double.greatestFiniteMagnitude

        for spectrum in candidates {
            let points = points(for: spectrum)
            guard let nearest = points.min(by: { abs($0.x - xValue) < abs($1.x - xValue) }) else { continue }
            let distance = abs(nearest.y - yValue)
            if distance < bestDistance {
                bestDistance = distance
                bestName = spectrum.name
            }
        }

        guard let bestName,
              let bestIndex = displayedSpectra.firstIndex(where: { $0.name == bestName }) else { return }
        selectedSpectrumIndex = bestIndex
        selectedSpectrumIndices = [bestIndex]
    }

    func buildPoints(for spectrum: ShimadzuSpectrum, range: ClosedRange<Double>) -> [SpectrumPoint] {
        let count = min(spectrum.x.count, spectrum.y.count)
        var points: [SpectrumPoint] = []
        points.reserveCapacity(count)

        for index in 0..<count {
            let x = spectrum.x[index]
            let y = spectrum.y[index]
            guard x.isFinite, y.isFinite, range.contains(x) else { continue }
            points.append(SpectrumPoint(id: index, x: x, y: y))
        }
        return points
    }

    func pointCacheKey(for spectrum: ShimadzuSpectrum, range: ClosedRange<Double>) -> String {
        let count = min(spectrum.x.count, spectrum.y.count)
        guard count > 0 else { return "\(spectrum.name)::empty" }
        let firstX = spectrum.x[0]
        let lastX = spectrum.x[count - 1]
        let firstY = spectrum.y[0]
        let lastY = spectrum.y[count - 1]
        return "\(spectrum.name)::\(count)::\(firstX)::\(lastX)::\(firstY)::\(lastY)::\(range.lowerBound)::\(range.upperBound)"
    }
}

private extension ContentView {
    static func invalidReason(for spectrum: ShimadzuSpectrum) -> String? {
        SpectrumValidation.invalidReason(x: spectrum.x, y: spectrum.y)
    }

    static func sanitizedSpectrum(_ spectrum: ShimadzuSpectrum) -> ShimadzuSpectrum? {
        let count = min(spectrum.x.count, spectrum.y.count)
        guard count > 0 else { return nil }
        var xVals: [Double] = []
        var yVals: [Double] = []
        xVals.reserveCapacity(count)
        yVals.reserveCapacity(count)
        for index in 0..<count {
            let xVal = spectrum.x[index]
            let yVal = spectrum.y[index]
            guard xVal.isFinite, yVal.isFinite else { continue }
            xVals.append(xVal)
            yVals.append(yVal)
        }
        guard !xVals.isEmpty else { return nil }
        return ShimadzuSpectrum(name: spectrum.name, x: xVals, y: yVals)
    }

    static func isValidSpectrum(_ spectrum: ShimadzuSpectrum) -> Bool {
        invalidReason(for: spectrum) == nil
    }

    var spfDisplayMode: SpfDisplayMode {
        SpfDisplayMode(rawValue: spfDisplayModeRawValue) ?? .calibrated
    }

    var colipaSpfValue: Double? {
        cachedColipaSpf
    }

    var estimatedSpfValue: Double? {
        guard let metrics = selectedMetrics, let calibration = calibrationResult else { return nil }
        return calibration.predict(metrics: metrics)
    }

    var displaySpfMetric: (label: String, value: Double)? {
        switch spfDisplayMode {
        case .colipa:
            if let value = colipaSpfValue {
                return (SpfDisplayMode.colipa.label, value)
            }
        case .calibrated:
            if let value = estimatedSpfValue {
                return (SpfDisplayMode.calibrated.label, value)
            }
        }
        return nil
    }

    var hasRenderableSeries: Bool {
        if showAverage, let avg = averageSpectrum, ContentView.isValidSpectrum(avg) {
            return true
        }
        let spectra = spectraForPlotting
        for spectrum in spectra {
            if ContentView.isValidSpectrum(spectrum) {
                return true
            }
        }
        return false
    }

    var spectraForPlotting: [ShimadzuSpectrum] {
        if showSelectedOnly {
            return selectedSpectra
        }
        if showAllSpectra {
            if includeInvalidInPlots {
                return displayedSpectra + sanitizedInvalidSpectra
            }
            return displayedSpectra
        }
        return selectedSpectra
    }

    var selectedInvalidSpectra: [ShimadzuSpectrum] {
        guard includeInvalidInPlots else { return [] }
        return invalidItems.compactMap { item in
            guard selectedInvalidItemIDs.contains(item.id) else { return nil }
            guard let sanitized = ContentView.sanitizedSpectrum(item.spectrum) else { return nil }
            return ShimadzuSpectrum(name: "Invalid: \(item.name)", x: sanitized.x, y: sanitized.y)
        }
    }

    var chartSeriesNames: [String] {
        spectraForPlotting.map { $0.name }
    }

    var chartPaletteRange: [Color] {
        let names = chartSeriesNames
        guard !names.isEmpty else { return [] }
        let paletteColors = palette.colors
        guard !paletteColors.isEmpty else { return [] }
        return names.indices.map { paletteColors[$0 % paletteColors.count] }
    }

    var sanitizedInvalidSpectra: [ShimadzuSpectrum] {
        invalidItems.compactMap { item in
            guard let sanitized = ContentView.sanitizedSpectrum(item.spectrum) else { return nil }
            return ShimadzuSpectrum(name: "Invalid: \(item.name)", x: sanitized.x, y: sanitized.y)
        }
    }

    func logSelectedOnlySelectionChange() {
        let count = selectedSpectra.count
        Instrumentation.log("Selection changed", area: .uiInteraction, level: .info, details: "selected=\(count)")
    }

    func toggleInvalidSelection(_ item: InvalidSpectrumItem) {
        guard includeInvalidInPlots else { return }
        if selectedInvalidItemIDs.contains(item.id) {
            selectedInvalidItemIDs.remove(item.id)
        } else {
            selectedInvalidItemIDs.insert(item.id)
        }
    }
}

private extension View {
    @ViewBuilder
    func glassSurface(cornerRadius: CGFloat) -> some View {
        if #available(macOS 15.0, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            self.background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color(.windowBackgroundColor).opacity(0.85))
            )
        }
    }

    @ViewBuilder
    func glassButtonStyle(isProminent: Bool = false) -> some View {
        if #available(macOS 15.0, *) {
            if isProminent {
                self.buttonStyle(GlassProminentButtonStyle())
            } else {
                self.buttonStyle(.glass)
            }
        } else {
            if isProminent {
                self.buttonStyle(.borderedProminent)
            } else {
                self.buttonStyle(.bordered)
            }
        }
    }
}

private enum PreviewData {
    static func loadSpectra() -> [ShimadzuSpectrum] {
        let paths = [
            "/Users/zincoverdeinc./Library/CloudStorage/OneDrive-Personal/4_Xcode Projects/Shimadzu File Converter/Shimadzu Data Analyser/SPC Sample Files/File_260207_131047.CVS 50 15.2 mg tio2 zno2 combospc.spc",
            "/Users/zincoverdeinc./Library/CloudStorage/OneDrive-Personal/4_Xcode Projects/Shimadzu File Converter/Shimadzu Data Analyser/SPC Sample Files/File_260207_131235. CVS 50 16.1 mg tio2 zno2 combo spc.spc"
        ]

        var spectra: [ShimadzuSpectrum] = []
        for path in paths {
            let url = URL(fileURLWithPath: path)
            if let parser = try? ShimadzuSPCParser(fileURL: url),
               let result = try? parser.extractSpectraResult() {
                let converted = result.spectra.map { ShimadzuSpectrum(name: $0.name, x: $0.x, y: $0.y) }
                spectra.append(contentsOf: converted)
            }
        }

        return spectra.isEmpty ? mockSpectra() : spectra
    }

    static func mockSpectra() -> [ShimadzuSpectrum] {
        let x = stride(from: 280.0, through: 420.0, by: 2.0).map { $0 }
        let y1 = x.map { 0.4 - 0.001 * ($0 - 280.0) }
        let y2 = x.map { 0.35 - 0.0008 * ($0 - 280.0) + 0.02 * sin($0 / 12.0) }
        let y3 = x.map { 0.3 - 0.0007 * ($0 - 280.0) + 0.015 * cos($0 / 10.0) }

        return [
            ShimadzuSpectrum(name: "Preview Sample A", x: x, y: y1),
            ShimadzuSpectrum(name: "Preview Sample B", x: x, y: y2),
            ShimadzuSpectrum(name: "Preview Sample C", x: x, y: y3)
        ]
    }
}

#Preview {
    ContentView(previewSpectra: PreviewData.loadSpectra(), previewMode: .analyze)
}
