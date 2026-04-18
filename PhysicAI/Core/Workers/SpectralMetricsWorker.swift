import Foundation

actor SpectralMetricsWorker {
    static let shared = SpectralMetricsWorker()

    // Heatmap bin cache — avoids recomputation when metrics list is unchanged
    private var cachedHeatmapBins: [HeatmapBin]?
    private var cachedHeatmapMetricsCount: Int = -1

    func compute(
        selectedSnapshot: (x: [Double], y: [Double])?,
        selectedSpectraSnapshots: [(x: [Double], y: [Double])],
        calibrationSnapshots: [(labelSPF: Double, name: String, x: [Double], y: [Double])],
        dashboardSnapshots: [(name: String, x: [Double], y: [Double], isPostIrradiation: Bool?)],
        yAxisMode: SpectralYAxisMode,
        cFactor: Double,
        substrateCorrection: Double,
        adjustmentFactor: Double,
        estimationOverride: SPFEstimationOverride,
        calculationMethod: SPFCalculationMethod = .colipa
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
            let rawSPF = SpectralMetricsCalculator.spf(x: snapshot.x, y: snapshot.y, yAxisMode: yAxisMode, method: calculationMethod)
            let resampled = SPFCalibration.resampleAbsorbance(x: snapshot.x, y: snapshot.y, yAxisMode: yAxisMode)
            return CalibrationSample(name: snapshot.name, labelSPF: snapshot.labelSPF, metrics: metrics, rawInVitroSPF: rawSPF, resampledAbsorbance: resampled)
        }
        let calibration = SPFCalibration.build(samples: calibrationSamples)
        let calibrationLogDetails = "snapshots=\(calibrationSnapshots.count) validSamples=\(calibrationSamples.count) model=\(calibration != nil) r2=\(calibration.map { String(format: "%.3f", $0.r2) } ?? "nil") n=\(calibration?.sampleCount ?? 0)"

        let colipaSpf = selectedSnapshot.flatMap { snapshot in
            SpectralMetricsCalculator.spf(x: snapshot.x, y: snapshot.y, yAxisMode: yAxisMode, method: calculationMethod)
        }

        // Resample the selected sample's absorbance for cosine similarity matching
        let sampleResampled: [Double]? = selectedSnapshot.flatMap { snapshot in
            SPFCalibration.resampleAbsorbance(x: snapshot.x, y: snapshot.y, yAxisMode: yAxisMode)
        }

        // Find the nearest reference match for the selected sample
        let nearestMatch: NearestReferenceMatch? = {
            guard let met = selectedMetrics, let rawSpf = colipaSpf else { return nil }
            return SPFCalibration.findNearestMatch(
                sampleMetrics: met,
                sampleRawSPF: rawSpf,
                sampleResampledAbsorbance: sampleResampled,
                references: calibrationSamples
            )
        }()

        let spfEstimation = SPFEstimationResolver.resolve(
            rawColipaSPF: colipaSpf,
            calibrationResult: calibration,
            nearestMatch: nearestMatch,
            metrics: selectedMetrics,
            cFactor: cFactor > 0 ? cFactor : nil,
            substrateCorrection: substrateCorrection > 0 ? substrateCorrection : nil,
            adjustmentFactor: adjustmentFactor,
            override: estimationOverride,
            calculationMethod: calculationMethod
        )

        let dashboard = buildDashboardMetrics(
            snapshots: dashboardSnapshots,
            yAxisMode: yAxisMode,
            calibration: calibration,
            calibrationSamples: calibrationSamples,
            cFactor: cFactor,
            substrateCorrection: substrateCorrection,
            adjustmentFactor: adjustmentFactor,
            estimationOverride: estimationOverride,
            calculationMethod: calculationMethod
        )

        return MetricsComputationResult(
            selectedMetrics: selectedMetrics,
            metricsStats: metricsStats,
            calibration: calibration,
            nearestMatch: nearestMatch,
            colipaSpf: colipaSpf,
            dashboard: dashboard,
            spfEstimation: spfEstimation,
            calibrationLogDetails: calibrationLogDetails
        )
    }

    func buildDashboardMetrics(
        snapshots: [(name: String, x: [Double], y: [Double], isPostIrradiation: Bool?)],
        yAxisMode: SpectralYAxisMode,
        calibration: CalibrationResult?,
        calibrationSamples: [CalibrationSample],
        cFactor: Double,
        substrateCorrection: Double,
        adjustmentFactor: Double,
        estimationOverride: SPFEstimationOverride,
        calculationMethod: SPFCalculationMethod = .colipa
    ) -> DashboardMetrics? {
        guard !snapshots.isEmpty else { return nil }

        var metricsList: [(name: String, metrics: SpectralMetrics, spf: Double?, isPostIrradiation: Bool?)] = []
        metricsList.reserveCapacity(snapshots.count)

        for snapshot in snapshots {
            guard let metrics = SpectralMetricsCalculator.metrics(x: snapshot.x, y: snapshot.y, yAxisMode: yAxisMode) else { continue }
            let rawSpf = SpectralMetricsCalculator.spf(x: snapshot.x, y: snapshot.y, yAxisMode: yAxisMode, method: calculationMethod)
            let perResampled = SPFCalibration.resampleAbsorbance(x: snapshot.x, y: snapshot.y, yAxisMode: yAxisMode)
            let perSpectrumMatch: NearestReferenceMatch? = {
                guard let raw = rawSpf else { return nil }
                return SPFCalibration.findNearestMatch(sampleMetrics: metrics, sampleRawSPF: raw,
                                                       sampleResampledAbsorbance: perResampled, references: calibrationSamples)
            }()
            let resolved = SPFEstimationResolver.resolve(
                rawColipaSPF: rawSpf,
                calibrationResult: calibration,
                nearestMatch: perSpectrumMatch,
                metrics: metrics,
                cFactor: cFactor > 0 ? cFactor : nil,
                substrateCorrection: substrateCorrection > 0 ? substrateCorrection : nil,
                adjustmentFactor: adjustmentFactor,
                override: estimationOverride,
                calculationMethod: calculationMethod
            )
            metricsList.append((snapshot.name, metrics, resolved?.value, snapshot.isPostIrradiation))
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

        // Cache isPostIncubation per name to avoid redundant string normalization
        var postIncubationCache: [String: Bool] = [:]
        func isPost(_ entry: (name: String, metrics: SpectralMetrics, spf: Double?, isPostIrradiation: Bool?)) -> Bool {
            if let explicit = entry.isPostIrradiation { return explicit }
            if let cached = postIncubationCache[entry.name] { return cached }
            let result = isPostIncubation(entry.name)
            postIncubationCache[entry.name] = result
            return result
        }
        let preSpf = metricsList.compactMap { entry -> Double? in
            isPost(entry) ? nil : entry.spf
        }
        let postSpf = metricsList.compactMap { entry -> Double? in
            isPost(entry) ? entry.spf : nil
        }
        let preAvg = preSpf.isEmpty ? nil : (preSpf.reduce(0, +) / Double(preSpf.count))
        let postAvg = postSpf.isEmpty ? nil : (postSpf.reduce(0, +) / Double(postSpf.count))
        let postIncubationDropPercent: Double? = {
            guard let preAvg, let postAvg, preAvg > 0 else { return nil }
            return max(((preAvg - postAvg) / preAvg) * 100.0, 0.0)
        }()

        let heatmapBins: [HeatmapBin]
        if metricsList.count == cachedHeatmapMetricsCount, let cached = cachedHeatmapBins {
            heatmapBins = cached
        } else {
            heatmapBins = buildHeatmapBins(metricsList: metricsList)
            cachedHeatmapBins = heatmapBins
            cachedHeatmapMetricsCount = metricsList.count
        }
        let heatmapXRange = (heatmapBins.map { $0.xRange.lowerBound }.min() ?? uvaUvbRange.lowerBound)
            ...
            (heatmapBins.map { $0.xRange.upperBound }.max() ?? uvaUvbRange.upperBound)
        let heatmapYRange = (heatmapBins.map { $0.yRange.lowerBound }.min() ?? criticalRange.lowerBound)
            ...
            (heatmapBins.map { $0.yRange.upperBound }.max() ?? criticalRange.upperBound)

        let representativeTier: SPFEstimationTier? = {
            guard let first = metricsList.first else { return nil }
            let rawSpf = SpectralMetricsCalculator.spf(x: snapshots[0].x, y: snapshots[0].y, yAxisMode: yAxisMode, method: calculationMethod)
            let repResampled = SPFCalibration.resampleAbsorbance(x: snapshots[0].x, y: snapshots[0].y, yAxisMode: yAxisMode)
            let repMatch: NearestReferenceMatch? = {
                guard let raw = rawSpf else { return nil }
                return SPFCalibration.findNearestMatch(sampleMetrics: first.metrics, sampleRawSPF: raw,
                                                       sampleResampledAbsorbance: repResampled, references: calibrationSamples)
            }()
            return SPFEstimationResolver.resolve(
                rawColipaSPF: rawSpf,
                calibrationResult: calibration,
                nearestMatch: repMatch,
                metrics: first.metrics,
                cFactor: cFactor > 0 ? cFactor : nil,
                substrateCorrection: substrateCorrection > 0 ? substrateCorrection : nil,
                adjustmentFactor: adjustmentFactor,
                override: estimationOverride,
                calculationMethod: calculationMethod
            )?.tier
        }()

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
            heatmapYRange: heatmapYRange,
            spfEstimationTier: representativeTier
        )
    }

    func buildHeatmapBins(metricsList: [(name: String, metrics: SpectralMetrics, spf: Double?, isPostIrradiation: Bool?)]) -> [HeatmapBin] {
        let xBins = 5
        let yBins = 5
        let xValues = metricsList.map { $0.metrics.uvaUvbRatio }
        let yValues = metricsList.map { $0.metrics.criticalWavelength }

        let dataXMin = xValues.min() ?? 0
        let dataXMax = xValues.max() ?? 1
        let dataYMin = yValues.min() ?? 300
        let dataYMax = yValues.max() ?? 400

        let xMin = min(dataXMin, 0.1)
        let xMax = max(dataXMax, 0.6)
        let yMin = min(dataYMin, 350.0)
        let yMax = max(dataYMax, 390.0)

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

    func isPostIncubation(_ name: String) -> Bool {
        let normalized = name.lowercased()
        if normalized.contains("after incubation") { return true }
        if normalized.contains("post incubation") { return true }
        if normalized.contains("after incub") { return true }
        return false
    }
}
