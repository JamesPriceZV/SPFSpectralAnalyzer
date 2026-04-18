import Foundation
import SwiftUI
import Observation

@MainActor @Observable
final class AnalysisViewModel {

    // MARK: - Spectra Data

    var spectra: [ShimadzuSpectrum] = []
    var alignedSpectra: [ShimadzuSpectrum] = []
    var processedSpectra: [ShimadzuSpectrum] = []

    // MARK: - Unload by Dataset

    /// Remove all spectra that were loaded from a given stored dataset,
    /// clearing dependent caches and syncing session state.
    /// - Returns: The number of spectra removed.
    @discardableResult
    func unloadSpectra(forDatasetID datasetID: UUID) -> Int {
        let beforeCount = spectra.count
        spectra.removeAll { $0.sourceDatasetID == datasetID }
        let removedCount = beforeCount - spectra.count
        guard removedCount > 0 else { return 0 }

        alignedSpectra = []
        processedSpectra = []
        pointCache = [:]

        DatasetViewModel.syncSessionDatasetIDs(from: spectra)

        if spectra.isEmpty {
            selectedSpectrumIndex = 0
            selectedSpectrumIndices = []
            statusMessage = "No spectra loaded."
            warningMessage = nil
            warningDetails = []
        } else {
            selectedSpectrumIndex = min(selectedSpectrumIndex, spectra.count - 1)
            selectedSpectrumIndices = Set(selectedSpectrumIndices.filter { $0 < spectra.count })
            statusMessage = "Unloaded \(removedCount) spectra. \(spectra.count) remaining."
        }

        applyAlignmentIfNeeded()
        updatePeaks()
        return removedCount
    }

    // MARK: - Processing Settings

    var useAlignment = true
    var smoothingMethod: SmoothingMethod = .none
    var smoothingWindow = 11
    var sgWindow = 11
    var sgOrder = 3
    var baselineMethod: BaselineMethod = .none
    var normalizationMethod: NormalizationMethod = .none

    // MARK: - Display Options

    var showAllSpectra = true
    var yAxisMode: SpectralYAxisMode = .absorbance
    var showAverage = false
    var showSelectedOnly = false
    var overlayLimit = 10
    var showLegend = true
    var showLabels = false
    var palette: SpectrumPalette = .vivid

    // MARK: - Peak Detection

    var detectPeaks = true
    var peakMinHeight = 0.01
    var peakMinDistance = 5
    var peaks: [PeakPoint] = []
    var showPeaks = true

    // MARK: - Selection State

    var selectedSpectrumIndex = 0
    var selectedSpectrumIndices: Set<Int> = [] {
        didSet { _sortedIndicesCache = nil }
    }
    var isRecalculating = false
    private var _sortedIndicesCache: [Int]?

    // MARK: - Chart State

    let chartWavelengthRange: ClosedRange<Double> = 280.0...420.0
    var chartVisibleDomain: Double = 130.0
    var chartVisibleYDomain: Double = 0.4
    var chartSelectionX: Double?
    var chartHoverLocation: CGPoint?

    // MARK: - HDRS (ISO 23675) State

    var hdrsSpectrumTags: [UUID: HDRSSpectrumTag] = [:]
    var hdrsProductType: HDRSProductType = .emulsion
    var hdrsResults: [String: HDRSResult] = [:]
    var hdrsMode: Bool = false

    // MARK: - Caching

    var cachedSeries: [SpectrumSeries] = []
    var cachedAverageSpectrum: ShimadzuSpectrum?
    var cachedSelectedMetrics: SpectralMetrics?
    var cachedSelectedMetricsStats: (avgUvaUvb: Double, avgCritical: Double, uvaUvbRange: ClosedRange<Double>, criticalRange: ClosedRange<Double>)?
    var cachedColipaSpf: Double?
    var cachedCalibration: CalibrationResult?
    var cachedNearestMatch: NearestReferenceMatch?
    var cachedDashboardMetrics: DashboardMetrics?
    var cachedSPFEstimation: SPFEstimationResult?
    var coreMLPrediction: SPFMLPrediction?
    var pointCache: [String: [SpectrumPoint]] = [:]

    /// Retained so that internal rebuildCaches() calls (from alignment,
    /// processing, peak detection) can reuse the last-known configuration
    /// instead of losing calibration data.
    private var lastSPFConfig: SPFConfiguration?
    private var lastCalibrationSnapshots: [(labelSPF: Double, name: String, x: [Double], y: [Double])]?

    // MARK: - Validation & Errors

    var validationLogEntries: [ValidationLogEntry] = []
    var invalidItems: [InvalidSpectrumItem] = []
    var selectedInvalidItemIDs: Set<UUID> = []
    var includeInvalidInPlots = false
    var activeMetadata: ShimadzuSPCMetadata?
    var activeMetadataSource: String?
    var warningMessage: String?
    var warningDetails: [String] = []
    var errorMessage: String?
    var statusMessage = "No files loaded"
    var lastAppliedSettings: ProcessingSettings?

    // MARK: - Initialization

    init(spectra: [ShimadzuSpectrum] = []) {
        self.spectra = spectra
    }

    // MARK: - Derived Spectra (Computed Properties)

    var displayedSpectra: [ShimadzuSpectrum] {
        if !processedSpectra.isEmpty { return processedSpectra }
        if useAlignment, !alignedSpectra.isEmpty { return alignedSpectra }
        return spectra
    }

    /// All non-reference spectra available for analysis.
    /// Since references are no longer loaded into the spectra array, this
    /// returns all displayed spectra.
    var analysisSpectra: [ShimadzuSpectrum] {
        displayedSpectra
    }

    /// Analysis spectra scoped to the current sidebar selection.
    /// When `selectedSpectrumIndices` is non-empty, only those spectra are returned.
    /// When empty, falls back to all spectra.
    var selectionScopedAnalysisSpectra: [ShimadzuSpectrum] {
        let all = displayedSpectra
        guard !selectedSpectrumIndices.isEmpty else { return all }
        let sorted = sortedSelectedIndices
        return sorted.compactMap { index in
            guard index >= 0, index < all.count else { return nil }
            return all[index]
        }
    }

    private var sortedSelectedIndices: [Int] {
        if let cached = _sortedIndicesCache { return cached }
        let sorted = selectedSpectrumIndices.sorted()
        _sortedIndicesCache = sorted
        return sorted
    }

    var selectedSpectrum: ShimadzuSpectrum? {
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

    var selectedSpectra: [ShimadzuSpectrum] {
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

    var rawSelectedSpectra: [ShimadzuSpectrum] {
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

    /// Spectra to feed into alignment and processing pipeline.
    /// Always returns ALL loaded spectra so that `alignedSpectra` / `processedSpectra`
    /// (and therefore `displayedSpectra`) always contain every loaded spectrum.
    /// Visibility filtering (`showAllSpectra`, `showSelectedOnly`) is applied
    /// only at the chart-rendering layer via `spectraForPlotting` / `activeSpectra`.
    var spectraForProcessing: [ShimadzuSpectrum] {
        spectra
    }

    var activeSpectra: [ShimadzuSpectrum] {
        if showSelectedOnly { return selectedSpectra }
        return showAllSpectra ? displayedSpectra : selectedSpectra
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
            guard let sanitized = AnalysisViewModel.sanitizedSpectrum(item.spectrum) else { return nil }
            return ShimadzuSpectrum(name: "Invalid: \(item.name)", x: sanitized.x, y: sanitized.y)
        }
    }

    var sanitizedInvalidSpectra: [ShimadzuSpectrum] {
        invalidItems.compactMap { item in
            guard let sanitized = AnalysisViewModel.sanitizedSpectrum(item.spectrum) else { return nil }
            return ShimadzuSpectrum(name: "Invalid: \(item.name)", x: sanitized.x, y: sanitized.y)
        }
    }

    // MARK: - Cache Accessors

    var selectedMetrics: SpectralMetrics? {
        cachedSelectedMetrics
    }

    var selectedMetricsStats: (avgUvaUvb: Double, avgCritical: Double, uvaUvbRange: ClosedRange<Double>, criticalRange: ClosedRange<Double>)? {
        cachedSelectedMetricsStats
    }

    var dashboardMetrics: DashboardMetrics? {
        cachedDashboardMetrics
    }

    var calibrationResult: CalibrationResult? {
        cachedCalibration
    }

    var seriesToPlot: [SpectrumSeries] {
        cachedSeries
    }

    var seriesToPlotNames: [String] {
        seriesToPlot.map { $0.name }
    }

    var averageSpectrum: ShimadzuSpectrum? {
        cachedAverageSpectrum
    }

    var colipaSpfValue: Double? {
        cachedColipaSpf
    }

    var estimatedSpfValue: Double? {
        guard let metrics = selectedMetrics, let calibration = calibrationResult else { return nil }
        return calibration.predict(metrics: metrics)
    }

    var displaySpfMetric: (label: String, value: Double)? {
        if let estimation = cachedSPFEstimation {
            return ("SPF (\(estimation.tier.shortLabel))", estimation.value)
        }
        return nil
    }

    // MARK: - Chart Helpers

    var selectedPoint: SpectrumPoint? {
        guard let chartSelectionX else { return nil }
        if let spectrum = selectedSpectra.first {
            return nearestPoint(in: spectrum, x: chartSelectionX)
        }
        return nil
    }

    var hasRenderableSeries: Bool {
        if showAverage, let avg = averageSpectrum, AnalysisViewModel.isValidSpectrum(avg) {
            return true
        }
        let spectra = spectraForPlotting
        for spectrum in spectra {
            if AnalysisViewModel.isValidSpectrum(spectrum) {
                return true
            }
        }
        return false
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

    // MARK: - Sidebar Filtering

    func filteredSortedIndices(filterText: String, sortMode: SidebarSortMode) -> [Int] {
        let spectra = displayedSpectra
        var indices = Array(spectra.indices)

        // Filter using boolean search engine
        let query = SearchQuery.parse(filterText)
        if !query.isEmpty {
            indices = indices.filter { i in
                let spectrum = spectra[i]
                let tags = spectrumTags(for: spectrum.name)
                let hdrsTag = hdrsSpectrumTags[spectrum.id]
                let record = SpectrumSearchRecord(
                    name: spectrum.name,
                    tags: tags,
                    hdrsPlateType: hdrsTag?.plateType.rawValue,
                    hdrsIrradiationState: hdrsTag?.irradiationState.rawValue,
                    hdrsSampleName: hdrsTag?.sampleName
                )
                return query.matches(record)
            }
        }

        // Sort
        switch sortMode {
        case .importOrder:
            break
        case .nameAZ:
            indices.sort { spectra[$0].name.localizedCaseInsensitiveCompare(spectra[$1].name) == .orderedAscending }
        case .nameZA:
            indices.sort { spectra[$0].name.localizedCaseInsensitiveCompare(spectra[$1].name) == .orderedDescending }
        case .tag:
            indices.sort { a, b in
                let tagsA = spectrumTags(for: spectra[a].name).first ?? ""
                let tagsB = spectrumTags(for: spectra[b].name).first ?? ""
                return tagsA.localizedCaseInsensitiveCompare(tagsB) == .orderedAscending
            }
        }

        return indices
    }

    // MARK: - Processing Pipeline

    func runPipeline() {
        let start = Date()
        Instrumentation.log("Pipeline run started", area: .processing, level: .info, details: "spectra=\(spectra.count)")

        applyAlignmentIfNeeded()
        applyProcessing()
        updatePeaks()
        rebuildCaches()
        lastAppliedSettings = currentProcessingSettings()

        let duration = Date().timeIntervalSince(start)
        Instrumentation.log("Pipeline run completed", area: .processing, level: .info, duration: duration)
    }

    func currentProcessingSettings() -> ProcessingSettings {
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

    func applyProcessingSettings(_ settings: ProcessingSettings) {
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

    func nearestPoint(in spectrum: ShimadzuSpectrum, x target: Double) -> SpectrumPoint? {
        let points = points(for: spectrum)
        guard !points.isEmpty else { return nil }
        return points.min(by: { abs($0.x - target) < abs($1.x - target) })
    }

    var isProcessing: Bool = false

    // MARK: - Alignment & Processing

    func applyAlignmentIfNeeded() {
        isProcessing = true
        Task(priority: .userInitiated) {
            // Capture all Sendable inputs BEFORE the hop off @MainActor
            let base = await MainActor.run { self.spectraForProcessing }
            let useAlign = await MainActor.run { self.useAlignment }
            let sm = await MainActor.run { self.smoothingMethod }
            let sw = await MainActor.run { self.smoothingWindow }
            let sgW = await MainActor.run { self.sgWindow }
            let sgO = await MainActor.run { self.sgOrder }
            let bm = await MainActor.run { self.baselineMethod }
            let nm = await MainActor.run { self.normalizationMethod }
            let minH = await MainActor.run { self.peakMinHeight }
            let minD = await MainActor.run { self.peakMinDistance }
            let shouldDetect = await MainActor.run { self.detectPeaks }

            guard !base.isEmpty else {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.alignedSpectra = []
                    self.processedSpectra = []
                    self.isProcessing = false
                    self.rebuildCaches()
                    Instrumentation.log("Alignment skipped", area: .processing, level: .warning, details: "reason=no spectra")
                }
                return
            }

            Instrumentation.log(
                "Alignment input",
                area: .processing, level: .info,
                details: "spectraForProcessing=\(base.count)"
            )

            // All heavy computation on P-Core, off @MainActor
            let alignResult = SpectralProcessingService.align(
                spectra: base, useAlignment: useAlign)

            let source = alignResult.alignedSpectra.isEmpty ? base : alignResult.alignedSpectra
            let processed = await SpectralProcessingService.processParallel(
                spectra: source,
                smoothingMethod: sm, smoothingWindow: sw,
                sgWindow: sgW, sgOrder: sgO,
                baselineMethod: bm, normalizationMethod: nm)

            let peaks: [PeakPoint]
            if shouldDetect, let first = processed.first {
                peaks = SpectralProcessingService.detectPeaks(
                    spectrum: first, minHeight: minH, minDistance: minD)
            } else {
                peaks = []
            }

            // ONE main-thread state write at the end — no intermediate redraws
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.alignedSpectra = alignResult.alignedSpectra
                if let message = alignResult.statusMessage {
                    self.statusMessage = message
                }
                self.processedSpectra = processed
                self.peaks = peaks
                self.isProcessing = false
                self.rebuildCaches()
            }
        }
    }

    func applyProcessing() {
        applyAlignmentIfNeeded()
    }

    func updatePeaks() {
        guard detectPeaks, let spectrum = selectedSpectrum else {
            peaks = []
            rebuildCaches()
            return
        }
        peaks = SpectralProcessingService.detectPeaks(
            spectrum: spectrum,
            minHeight: peakMinHeight,
            minDistance: peakMinDistance
        )
        rebuildCaches()
    }

    // MARK: - Cache Management

    func rebuildCaches(spfConfig: SPFConfiguration? = nil,
                       externalCalibrationSnapshots: [(labelSPF: Double, name: String, x: [Double], y: [Double])]? = nil,
                       datasetIrradiationOverrides: [UUID: Bool] = [:]) {
        // Persist provided values so internal calls (from alignment,
        // processing, peak detection) reuse the last-known configuration.
        if let spfConfig { lastSPFConfig = spfConfig }
        if let externalCalibrationSnapshots { lastCalibrationSnapshots = externalCalibrationSnapshots }

        isRecalculating = true
        let analysis = selectionScopedAnalysisSpectra
        let plotSpectra = spectraForPlotting
        cachedAverageSpectrum = CacheComputationService.computeAverageSpectrum(from: analysis)

        let yAxis = yAxisMode
        let selectedSnapshot = analysis.first.map { (x: $0.x, y: $0.y) }
        let selectedSpectraSnapshots = analysis.map { (x: $0.x, y: $0.y) }

        // Use provided calibration data, or fall back to the last-known set
        // from a prior rebuildAnalysisCaches() call.
        let calibrationSnapshots = externalCalibrationSnapshots ?? lastCalibrationSnapshots ?? []
        let irradiationMap = datasetIrradiationOverrides
        let dashboardSnapshots = analysis.map { spectrum in
            (name: spectrum.name, x: spectrum.x, y: spectrum.y,
             isPostIrradiation: spectrum.sourceDatasetID.flatMap { irradiationMap[$0] })
        }

        let effectiveConfig = spfConfig ?? lastSPFConfig
        let cf = effectiveConfig?.cFactor ?? 0.0
        let sc = effectiveConfig?.substrateCorrection ?? 0.0
        let af = effectiveConfig?.adjustmentFactor ?? 1.0
        let overrideMode = effectiveConfig?.estimationOverride ?? .automatic
        let calcMethod = effectiveConfig?.calculationMethod ?? .colipa

        hdrsMode = (calcMethod == .iso23675)

        if calcMethod == .iso23675, !hdrsSpectrumTags.isEmpty {
            computeHDRSResults()
        } else {
            hdrsResults = [:]
        }

        Task(priority: .userInitiated) {
            let result = await SpectralMetricsWorker.shared.compute(
                selectedSnapshot: selectedSnapshot,
                selectedSpectraSnapshots: selectedSpectraSnapshots,
                calibrationSnapshots: calibrationSnapshots,
                dashboardSnapshots: dashboardSnapshots,
                yAxisMode: yAxis,
                cFactor: cf,
                substrateCorrection: sc,
                adjustmentFactor: af,
                estimationOverride: overrideMode,
                calculationMethod: calcMethod
            )

            await MainActor.run {
                cachedSelectedMetrics = result.selectedMetrics
                cachedSelectedMetricsStats = result.metricsStats
                cachedCalibration = result.calibration
                cachedNearestMatch = result.nearestMatch
                cachedColipaSpf = result.colipaSpf
                cachedDashboardMetrics = result.dashboard
                cachedSPFEstimation = result.spfEstimation

                // CoreML prediction
                if let firstSpectrum = analysis.first {
                    coreMLPrediction = SPFPredictionService.shared.predict(
                        x: firstSpectrum.x,
                        y: firstSpectrum.y,
                        yAxisMode: yAxis
                    )
                } else {
                    coreMLPrediction = nil
                }

                isRecalculating = false
                if !result.calibrationLogDetails.isEmpty {
                    Instrumentation.log("Calibration build", area: .processing, level: .info, details: result.calibrationLogDetails)
                }
            }
        }

        pointCache = CacheComputationService.buildPointCache(
            plotSpectra: plotSpectra,
            averageSpectrum: cachedAverageSpectrum,
            range: chartWavelengthRange
        )

        cachedSeries = CacheComputationService.computeSeriesToPlot(
            from: plotSpectra,
            overlayLimit: overlayLimit,
            palette: palette,
            pointProvider: { self.points(for: $0) }
        )
        Instrumentation.log(
            "Chart cache rebuilt",
            area: .chartRendering,
            level: .info,
            details: "series=\(cachedSeries.count) cacheEntries=\(pointCache.count) analysis=\(analysis.count) calibration=\(calibrationSnapshots.count)"
        )
    }

    // MARK: - Point Cache

    func points(for spectrum: ShimadzuSpectrum) -> [SpectrumPoint] {
        let key = CacheComputationService.pointCacheKey(for: spectrum, range: chartWavelengthRange)
        return pointCache[key] ?? CacheComputationService.buildPoints(for: spectrum, range: chartWavelengthRange)
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

    // Point building and cache key generation delegated to CacheComputationService

    // MARK: - Tags

    func spectrumTags(for name: String) -> [String] {
        let lower = name.lowercased()
        var tags: [String] = []

        if lower.contains("after incubation") { tags.append("Post-Irr") }
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
        if lower.contains("moulded") || lower.contains("molded") { tags.append("Moulded") }
        if lower.contains("sandblast") { tags.append("Sandblasted") }

        return tags.isEmpty ? ["Sample"] : Array(tags.prefix(4))
    }

    // MARK: - Validation Helpers

    static func invalidReason(for spectrum: ShimadzuSpectrum) -> String? {
        ValidationService.invalidReason(for: spectrum)
    }

    static func sanitizedSpectrum(_ spectrum: ShimadzuSpectrum) -> ShimadzuSpectrum? {
        ValidationService.sanitizedSpectrum(spectrum)
    }

    static func isValidSpectrum(_ spectrum: ShimadzuSpectrum) -> Bool {
        ValidationService.isValidSpectrum(spectrum)
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

    // MARK: - HDRS Helpers

    func hdrsSampleGroups(filterText: String, sortMode: SidebarSortMode) -> [String: [Int]] {
        var groups: [String: [Int]] = [:]
        for index in filteredSortedIndices(filterText: filterText, sortMode: sortMode) {
            let spectrum = displayedSpectra[index]
            if let tag = hdrsSpectrumTags[spectrum.id] {
                groups[tag.sampleName, default: []].append(index)
            }
        }
        return groups
    }

    func hdrsUngroupedIndices(filterText: String, sortMode: SidebarSortMode) -> [Int] {
        filteredSortedIndices(filterText: filterText, sortMode: sortMode).filter { index in
            hdrsSpectrumTags[displayedSpectra[index].id] == nil
        }
    }

    func setHDRSPlateType(_ plateType: HDRSPlateType, for index: Int) {
        let spectrum = displayedSpectra[index]
        var tag = hdrsSpectrumTags[spectrum.id] ?? HDRSSpectrumTag(
            plateType: plateType,
            irradiationState: .preIrradiation,
            plateIndex: 1,
            sampleName: HDRSComputationService.parseSampleName(from: spectrum.name)
        )
        tag.plateType = plateType
        hdrsSpectrumTags[spectrum.id] = tag
    }

    func setHDRSIrradiationState(_ state: HDRSIrradiationState, for index: Int) {
        let spectrum = displayedSpectra[index]
        var tag = hdrsSpectrumTags[spectrum.id] ?? HDRSSpectrumTag(
            plateType: .moulded,
            irradiationState: state,
            plateIndex: 1,
            sampleName: HDRSComputationService.parseSampleName(from: spectrum.name)
        )
        tag.irradiationState = state
        hdrsSpectrumTags[spectrum.id] = tag
    }

    func parseSampleName(from name: String) -> String {
        HDRSComputationService.parseSampleName(from: name)
    }

    func computeHDRSResults() {
        hdrsResults = HDRSComputationService.computeResults(
            displayedSpectra: displayedSpectra,
            hdrsSpectrumTags: hdrsSpectrumTags,
            yAxisMode: yAxisMode,
            hdrsProductType: hdrsProductType
        )
    }

    func autoAssignHDRSTags(datasetIrradiationOverrides: [UUID: Bool] = [:]) {
        hdrsSpectrumTags = HDRSComputationService.autoAssignTags(
            displayedSpectra: displayedSpectra,
            datasetIrradiationOverrides: datasetIrradiationOverrides
        )
    }
}
