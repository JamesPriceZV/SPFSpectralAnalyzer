import Foundation

/// Stateless spectral processing pipeline operations.
enum SpectralProcessingService {

    struct AlignmentResult {
        var alignedSpectra: [ShimadzuSpectrum]
        var statusMessage: String?
        var mismatchDetected: Bool
    }

    static func align(
        spectra: [ShimadzuSpectrum],
        useAlignment: Bool
    ) -> AlignmentResult {
        guard let reference = spectra.first else {
            return AlignmentResult(alignedSpectra: [], statusMessage: nil, mismatchDetected: false)
        }

        let refX = reference.x
        let mismatchDetected = spectra.contains { !SpectraProcessing.axesMatch(refX, $0.x) }

        if !useAlignment {
            var message: String? = nil
            if mismatchDetected {
                message = "Axes differ. Enable Align X-Axis to resample."
                Instrumentation.log("Alignment disabled with mismatched axes", area: .processing, level: .warning)
            } else {
                Instrumentation.log("Alignment disabled", area: .processing, level: .info)
            }
            return AlignmentResult(alignedSpectra: [], statusMessage: message, mismatchDetected: mismatchDetected)
        }

        var result: [ShimadzuSpectrum] = []
        result.reserveCapacity(spectra.count)

        for spectrum in spectra {
            if SpectraProcessing.axesMatch(refX, spectrum.x) {
                result.append(spectrum)
            } else {
                let resampledY = SpectraProcessing.resampleLinear(x: spectrum.x, y: spectrum.y, onto: refX)
                let aligned = ShimadzuSpectrum(name: spectrum.name, x: refX, y: resampledY)
                result.append(aligned)
            }
        }

        Instrumentation.log("Alignment applied", area: .processing, level: .info, details: "spectra=\(result.count) mismatch=\(mismatchDetected)")
        let message = mismatchDetected ? "Axes differed. Resampled to match the first spectrum." : nil

        return AlignmentResult(alignedSpectra: result, statusMessage: message, mismatchDetected: mismatchDetected)
    }

    static func process(
        spectra: [ShimadzuSpectrum],
        smoothingMethod: SmoothingMethod,
        smoothingWindow: Int,
        sgWindow: Int,
        sgOrder: Int,
        baselineMethod: BaselineMethod,
        normalizationMethod: NormalizationMethod
    ) -> [ShimadzuSpectrum] {
        let started = Date()
        let needsProcessing = smoothingMethod != .none || baselineMethod != .none || normalizationMethod != .none
        guard needsProcessing else {
            Instrumentation.log("Processing skipped", area: .processing, level: .info, details: "reason=no processing enabled")
            return []
        }

        var smoothingDuration: TimeInterval = 0
        var baselineDuration: TimeInterval = 0
        var normalizationDuration: TimeInterval = 0

        let result = spectra.map { spectrum in
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

        let duration = Date().timeIntervalSince(started)
        let stageDetails = String(
            format: "spectra=%d smoothing=%.3fs baseline=%.3fs normalization=%.3fs",
            result.count,
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

        return result
    }

    @MainActor static func processParallel(
        spectra: [ShimadzuSpectrum],
        smoothingMethod: SmoothingMethod,
        smoothingWindow: Int,
        sgWindow: Int, sgOrder: Int,
        baselineMethod: BaselineMethod,
        normalizationMethod: NormalizationMethod
    ) async -> [ShimadzuSpectrum] {
        guard !spectra.isEmpty else { return [] }
        let needsProcessing = smoothingMethod != .none || baselineMethod != .none || normalizationMethod != .none
        guard needsProcessing else { return [] }

        let sm = smoothingMethod, sw = smoothingWindow
        let sgW = sgWindow, sgO = sgOrder
        let bm = baselineMethod, nm = normalizationMethod

        // Capture data on caller's actor before crossing into TaskGroup
        let snapshots = spectra.map { (name: $0.name, x: $0.x, y: $0.y) }

        let processed = await withTaskGroup(
            of: (index: Int, name: String, x: [Double], y: [Double]).self
        ) { group in
            for (i, snap) in snapshots.enumerated() {
                group.addTask(priority: .userInitiated) {
                    var y = snap.y
                    switch sm {
                    case .movingAverage:
                        y = SpectraProcessing.movingAverage(y: y, window: sw)
                    case .savitzkyGolay:
                        let order = min(sgO, sgW - 1)
                        y = SpectraProcessing.savitzkyGolay(y: y, window: sgW, polynomialOrder: order)
                    case .none:
                        break
                    }
                    if bm != .none {
                        y = SpectraProcessing.applyBaseline(y: y, x: snap.x, method: bm)
                    }
                    if nm != .none {
                        y = SpectraProcessing.applyNormalization(y: y, x: snap.x, method: nm)
                    }
                    return (index: i, name: snap.name, x: snap.x, y: y)
                }
            }
            var results = [(index: Int, name: String, x: [Double], y: [Double])]()
            results.reserveCapacity(snapshots.count)
            for await item in group { results.append(item) }
            return results.sorted { $0.index < $1.index }
        }
        // Create MainActor-isolated ShimadzuSpectrum objects back on MainActor
        return processed.map { ShimadzuSpectrum(name: $0.name, x: $0.x, y: $0.y) }
    }

    static func detectPeaks(
        spectrum: ShimadzuSpectrum,
        minHeight: Double,
        minDistance: Int
    ) -> [PeakPoint] {
        SpectraProcessing.detectPeaks(
            x: spectrum.x,
            y: spectrum.y,
            minHeight: minHeight,
            minDistance: minDistance
        )
    }
}
