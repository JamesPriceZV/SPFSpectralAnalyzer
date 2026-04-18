import Foundation
import SwiftUI

// MARK: - Estimation Tier

/// Describes which SPF estimation method produced a result.
enum SPFEstimationTier: String, CaseIterable, Identifiable, Sendable {
    case fullColipa   // Tier 1: COLIPA × C_factor × substrate correction
    case calibrated   // Tier 2: Regression model from labeled samples
    case adjusted     // Tier 3: COLIPA × user-configurable adjustment factor

    var id: String { rawValue }

    var rank: Int {
        switch self {
        case .fullColipa: return 1
        case .calibrated: return 2
        case .adjusted:   return 3
        }
    }

    var label: String {
        switch self {
        case .fullColipa: return "Full COLIPA"
        case .calibrated: return "Calibrated"
        case .adjusted:   return "Adjusted"
        }
    }

    var shortLabel: String {
        switch self {
        case .fullColipa: return "Full"
        case .calibrated: return "Cal."
        case .adjusted:   return "Adj."
        }
    }

    var badgeColor: Color {
        switch self {
        case .fullColipa: return .green
        case .calibrated: return .blue
        case .adjusted:   return .orange
        }
    }

    var qualityDescription: String {
        switch self {
        case .fullColipa:
            return "Best estimate. Uses the COLIPA in-vitro formula with experimentally determined correction factors (C_factor and substrate correction)."
        case .calibrated:
            return "Good estimate. Matches the sample's spectral profile to the closest reference dataset with a known in-vivo SPF, then estimates SPF proportionally from in-vitro measurements."
        case .adjusted:
            return "Approximate estimate. Multiplies the raw in-vitro COLIPA value by an adjustment factor. Less reliable than calibrated or full methods."
        }
    }
}

// MARK: - HDRS Estimation Result

/// ISO 23675 HDRS-specific estimation result, separate from the tier system.
/// The HDRS workflow produces a multi-plate, statistically validated result that
/// does not fit neatly into the single-spectrum tier hierarchy.
struct HDRSEstimationResult: Sendable {
    let hdrsResult: HDRSResult
    let explanation: String
    let formulaBreakdown: [String]  // Per-pair formula step descriptions
}

// MARK: - Override Mode

/// User-selectable override for the estimation method.
enum SPFEstimationOverride: String, CaseIterable, Identifiable, Sendable {
    case automatic
    case fullColipa
    case calibrated
    case adjusted
    case rawColipa

    var id: String { rawValue }

    var label: String {
        switch self {
        case .automatic:  return "Automatic (Best Available)"
        case .fullColipa: return "Full COLIPA (requires correction factors)"
        case .calibrated: return "Calibrated (requires labeled samples)"
        case .adjusted:   return "Adjusted COLIPA"
        case .rawColipa:  return "Raw COLIPA (uncorrected)"
        }
    }
}

// MARK: - Result Types

/// The resolved SPF estimation with provenance metadata.
struct SPFEstimationResult: Sendable {
    let value: Double
    let tier: SPFEstimationTier
    let rawColipaValue: Double?
    let calculationMethod: SPFCalculationMethod
    let details: SPFEstimationDetails
}

struct SPFEstimationDetails: Sendable {
    let cFactor: Double?
    let substrateCorrection: Double?
    let adjustmentFactor: Double?
    let calibrationR2: Double?
    let calibrationSampleCount: Int?
    let calculationMethod: SPFCalculationMethod
    let explanation: String
    let missingDataHints: [String]
    let nearestMatchDistance: Double?
    let nearestMatchReferenceSPF: Double?
    let nearestMatchReferenceName: String?

    nonisolated init(cFactor: Double?, substrateCorrection: Double?, adjustmentFactor: Double?,
         calibrationR2: Double?, calibrationSampleCount: Int?,
         calculationMethod: SPFCalculationMethod, explanation: String,
         missingDataHints: [String],
         nearestMatchDistance: Double? = nil, nearestMatchReferenceSPF: Double? = nil,
         nearestMatchReferenceName: String? = nil) {
        self.cFactor = cFactor
        self.substrateCorrection = substrateCorrection
        self.adjustmentFactor = adjustmentFactor
        self.calibrationR2 = calibrationR2
        self.calibrationSampleCount = calibrationSampleCount
        self.calculationMethod = calculationMethod
        self.explanation = explanation
        self.missingDataHints = missingDataHints
        self.nearestMatchDistance = nearestMatchDistance
        self.nearestMatchReferenceSPF = nearestMatchReferenceSPF
        self.nearestMatchReferenceName = nearestMatchReferenceName
    }
}

// MARK: - Resolver

/// Pure function that selects the best available SPF estimation method.
/// All methods are nonisolated so they can be called from any actor context.
enum SPFEstimationResolver {

    nonisolated static func resolve(
        rawColipaSPF: Double?,
        calibrationResult: CalibrationResult?,
        nearestMatch: NearestReferenceMatch?,
        metrics: SpectralMetrics?,
        cFactor: Double?,
        substrateCorrection: Double?,
        adjustmentFactor: Double,
        override: SPFEstimationOverride,
        calculationMethod: SPFCalculationMethod = .colipa,
        calibrationMinR2: Double = 0.7,
        calibrationMinSamples: Int = 3
    ) -> SPFEstimationResult? {
        guard let rawColipa = rawColipaSPF else { return nil }

        switch override {
        case .rawColipa:
            return rawResult(rawColipa: rawColipa, method: calculationMethod)

        case .fullColipa:
            if let t1 = resolveTier1(rawColipa: rawColipa, cFactor: cFactor, substrateCorrection: substrateCorrection, method: calculationMethod) {
                return t1
            }
            return resolveTier3(rawColipa: rawColipa, adjustmentFactor: adjustmentFactor, method: calculationMethod, nearestMatch: nearestMatch)

        case .calibrated:
            if let t2 = resolveTier2(rawColipa: rawColipa, calibrationResult: calibrationResult, nearestMatch: nearestMatch, metrics: metrics,
                                      minR2: calibrationMinR2, minSamples: calibrationMinSamples, method: calculationMethod) {
                return t2
            }
            return resolveTier3(rawColipa: rawColipa, adjustmentFactor: adjustmentFactor, method: calculationMethod, nearestMatch: nearestMatch)

        case .adjusted:
            return resolveTier3(rawColipa: rawColipa, adjustmentFactor: adjustmentFactor, method: calculationMethod, nearestMatch: nearestMatch)

        case .automatic:
            if let t1 = resolveTier1(rawColipa: rawColipa, cFactor: cFactor, substrateCorrection: substrateCorrection, method: calculationMethod) {
                return t1
            }
            if let t2 = resolveTier2(rawColipa: rawColipa, calibrationResult: calibrationResult, nearestMatch: nearestMatch, metrics: metrics,
                                      minR2: calibrationMinR2, minSamples: calibrationMinSamples, method: calculationMethod) {
                return t2
            }
            return resolveTier3(rawColipa: rawColipa, adjustmentFactor: adjustmentFactor, method: calculationMethod, nearestMatch: nearestMatch)
        }
    }

    // MARK: - Private Tier Resolvers

    nonisolated private static func rawResult(rawColipa: Double, method: SPFCalculationMethod) -> SPFEstimationResult {
        SPFEstimationResult(
            value: rawColipa,
            tier: .adjusted,
            rawColipaValue: rawColipa,
            calculationMethod: method,
            details: SPFEstimationDetails(
                cFactor: nil, substrateCorrection: nil,
                adjustmentFactor: 1.0, calibrationR2: nil,
                calibrationSampleCount: nil,
                calculationMethod: method,
                explanation: "Raw in-vitro \(method.rawValue) value with no correction. This value is typically much lower than label SPF because correction factors have not been applied.",
                missingDataHints: []
            )
        )
    }

    nonisolated private static func resolveTier1(rawColipa: Double, cFactor: Double?, substrateCorrection: Double?, method: SPFCalculationMethod) -> SPFEstimationResult? {
        guard let cf = cFactor, cf > 0, let sc = substrateCorrection, sc > 0 else { return nil }
        let value = rawColipa * cf * sc
        return SPFEstimationResult(
            value: value,
            tier: .fullColipa,
            rawColipaValue: rawColipa,
            calculationMethod: method,
            details: SPFEstimationDetails(
                cFactor: cf, substrateCorrection: sc,
                adjustmentFactor: nil, calibrationR2: nil,
                calibrationSampleCount: nil,
                calculationMethod: method,
                explanation: String(format: "SPF = %@_raw × C_factor × substrate = %.2f × %.1f × %.2f = %.1f", method.rawValue, rawColipa, cf, sc, value),
                missingDataHints: []
            )
        )
    }

    nonisolated private static func resolveTier2(rawColipa: Double, calibrationResult: CalibrationResult?, nearestMatch: NearestReferenceMatch?,
                                      metrics: SpectralMetrics?,
                                      minR2: Double, minSamples: Int, method: SPFCalculationMethod) -> SPFEstimationResult? {
        // Priority 1: Nearest-reference matching — works even with few references.
        // When resampled absorbance curves are available, distance is (1 - cosine
        // similarity) on the full 290-400 nm curve; otherwise it is normalized
        // Euclidean distance in 8-D feature space.
        // Guards:
        //   • Cosine distance < 0.15 (i.e. similarity > 0.85).
        //   • When a C-coefficient was solved via ISO 24443, the result is trusted
        //     because the solver already validates convergence.  The ratio between
        //     corrected and raw in-vitro SPF routinely exceeds 5× for higher-SPF
        //     products — this is expected since raw in-vitro values are typically
        //     much lower than label SPF.
        //   • For proportional-scaling fallback (no C-coefficient), the ratio must
        //     be < 15× as an additional sanity check.
        let distanceThreshold = 0.15  // cosine distance (1 - similarity)
        if let nm = nearestMatch, nm.distance < distanceThreshold, nm.matchedReferenceRawSPF > 0 {
            let value = nm.estimatedSPF
            // When the ISO 24443 C-coefficient was successfully solved, trust the
            // result — the solver constrains C to a valid range and verifies
            // convergence within 5% of the reference label SPF.  Only apply a
            // plausibility ratio check for the proportional-scaling fallback.
            if nm.cCoefficient == nil {
                let ratio = rawColipa > 0 ? value / rawColipa : .infinity
                guard ratio < 15.0 else {
                    return nil
                }
            }
            let refLabel = nm.matchedReferenceName.isEmpty ? String(format: "SPF %.0f", nm.matchedReferenceSPF) : nm.matchedReferenceName
            let calibrationNote: String
            if let c = nm.cCoefficient {
                calibrationNote = String(
                    format: "ISO 24443 C-coefficient calibration (n=%d, spectral similarity=%.3f). Matched ref: %@ (SPF %.0f). C = %.3f applied to sample absorbance curve. SPF = %.1f",
                    nm.sampleCount, 1.0 - nm.distance, refLabel, nm.matchedReferenceSPF, c, value
                )
            } else {
                calibrationNote = String(
                    format: "Nearest-reference match (n=%d, distance=%.3f). Closest ref: %@ (SPF %.0f, raw in-vitro %.2f). SPF = %.0f × (%.2f / %.2f) = %.1f",
                    nm.sampleCount, nm.distance, refLabel, nm.matchedReferenceSPF, nm.matchedReferenceRawSPF,
                    nm.matchedReferenceSPF, rawColipa, nm.matchedReferenceRawSPF, value
                )
            }
            return SPFEstimationResult(
                value: value,
                tier: .calibrated,
                rawColipaValue: rawColipa,
                calculationMethod: method,
                details: SPFEstimationDetails(
                    cFactor: nm.cCoefficient, substrateCorrection: nil,
                    adjustmentFactor: nil,
                    calibrationR2: calibrationResult?.r2,
                    calibrationSampleCount: nm.sampleCount,
                    calculationMethod: method,
                    explanation: calibrationNote,
                    missingDataHints: [],
                    nearestMatchDistance: nm.distance,
                    nearestMatchReferenceSPF: nm.matchedReferenceSPF,
                    nearestMatchReferenceName: nm.matchedReferenceName
                )
            )
        }

        // Priority 2: OLS regression (requires high R²)
        guard let cal = calibrationResult,
              let met = metrics,
              cal.r2 >= minR2,
              cal.sampleCount >= minSamples else { return nil }
        let features = [1.0, met.uvbArea, met.uvaArea, met.criticalWavelength, met.uvaUvbRatio,
                        met.meanUVBTransmittance, met.meanUVATransmittance, met.peakAbsorbanceWavelength]
        let logSpf = zip(cal.coefficients, features).map(*).reduce(0, +)
        let value = max(exp(logSpf), 0.0)
        return SPFEstimationResult(
            value: value,
            tier: .calibrated,
            rawColipaValue: rawColipa,
            calculationMethod: method,
            details: SPFEstimationDetails(
                cFactor: nil, substrateCorrection: nil,
                adjustmentFactor: nil,
                calibrationR2: cal.r2,
                calibrationSampleCount: cal.sampleCount,
                calculationMethod: method,
                explanation: String(format: "Regression model (n=%d, R²=%.3f) predicts SPF from spectral features. Base: %@.", cal.sampleCount, cal.r2, method.rawValue),
                missingDataHints: []
            )
        )
    }

    nonisolated private static func resolveTier3(rawColipa: Double, adjustmentFactor: Double, method: SPFCalculationMethod,
                                      nearestMatch: NearestReferenceMatch? = nil) -> SPFEstimationResult {
        let factor = max(adjustmentFactor, 1.0)
        let value = rawColipa * factor
        var hints = [
            "Provide C_factor and substrate correction for Full correction (Tier 1)."
        ]
        var explanationSuffix = ""
        if let nm = nearestMatch {
            let ratio = rawColipa > 0 ? nm.estimatedSPF / rawColipa : .infinity
            if nm.distance >= 0.15 {
                hints.append(String(format: "Nearest reference was too distant (spectral similarity %.3f < 0.85 threshold) to use for calibration. Add more reference datasets that are spectrally similar to this sample.", 1.0 - nm.distance))
                explanationSuffix = String(format: " Nearest reference (SPF %.0f) rejected: spectral similarity %.3f below 0.85 threshold.", nm.matchedReferenceSPF, 1.0 - nm.distance)
            } else if ratio >= 15.0 {
                hints.append(String(format: "Nearest reference (SPF %.0f) would amplify the raw value by %.1f×, which exceeds the 15× plausibility limit. Add reference datasets with SPF values closer to this sample.", nm.matchedReferenceSPF, ratio))
                explanationSuffix = String(format: " Nearest reference (SPF %.0f, similarity %.3f) rejected: calibration ratio %.1f× exceeds plausibility limit.", nm.matchedReferenceSPF, 1.0 - nm.distance, ratio)
            } else {
                hints.append("Add more calibration datasets to improve data quality.")
            }
        } else {
            hints.append("Add reference datasets with known in-vivo SPF for Nearest-Reference estimate (Tier 2).")
        }
        return SPFEstimationResult(
            value: value,
            tier: .adjusted,
            rawColipaValue: rawColipa,
            calculationMethod: method,
            details: SPFEstimationDetails(
                cFactor: nil, substrateCorrection: nil,
                adjustmentFactor: factor,
                calibrationR2: nil, calibrationSampleCount: nil,
                calculationMethod: method,
                explanation: String(format: "SPF = %@_raw × adjustment = %.2f × %.0f = %.1f.%@", method.rawValue, rawColipa, factor, value, explanationSuffix),
                missingDataHints: hints
            )
        )
    }
}
