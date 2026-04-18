import SwiftUI

/// Centralizes Knowledge-vs-Information interpretation logic for spectral metrics.
/// All threshold constants and human-readable assessments live here to keep
/// ContentView focused on layout and state management.
enum SpectralInterpretation {

    // MARK: - COLIPA Thresholds

    static let colipaUvaUvbMinimum = 0.33
    static let broadSpectrumCriticalWL = 370.0
    static let spfComplianceThreshold = 30.0
    static let spfModeratThreshold = 15.0
    static let photoStabilityAcceptable = 20.0
    static let photoStabilityExcellent = 10.0

    // MARK: - Dashboard Interpretations

    static func complianceInterpretation(percent: Double) -> String {
        if percent >= 80 {
            return "Strong compliance — most samples meet in-vitro SPF ≥30."
        } else if percent >= 50 {
            return "Moderate compliance — consider reformulation for failing samples."
        } else if percent > 0 {
            return "Low compliance — majority below in-vitro SPF 30."
        } else {
            return "No samples reach in-vitro SPF 30. Note: uncalibrated COLIPA values are typically much lower than label SPF — add calibration samples to improve estimates."
        }
    }

    static func uvaUvbInterpretation(ratio: Double) -> String {
        if ratio >= colipaUvaUvbMinimum {
            return "Meets COLIPA broad-spectrum requirement (≥0.33)."
        } else {
            return "Below 0.33 — does not meet COLIPA UVA/UVB requirement."
        }
    }

    static func criticalWavelengthInterpretation(wavelength: Double) -> String {
        if wavelength >= broadSpectrumCriticalWL {
            return "Broad-spectrum (≥370 nm) — good UVA coverage."
        } else {
            return "Below 370 nm — insufficient UVA protection for broad-spectrum claim."
        }
    }

    static func trendsInterpretation(drop: Double?, lowCriticalCount: Int) -> String {
        var parts: [String] = []
        if let drop {
            if drop < photoStabilityExcellent {
                parts.append("Excellent photo-stability (<10% SPF loss).")
            } else if drop < photoStabilityAcceptable {
                parts.append("Acceptable photo-stability (<20% loss).")
            } else {
                parts.append("Significant SPF drop (≥20%) — photo-stability concern.")
            }
        }
        if lowCriticalCount > 0 {
            parts.append("\(lowCriticalCount) sample\(lowCriticalCount == 1 ? "" : "s") below 370 nm critical λ.")
        }
        return parts.isEmpty ? "No trend data available." : parts.joined(separator: " ")
    }

    static func trendsColor(drop: Double?) -> Color {
        guard let drop else { return .secondary }
        if drop < photoStabilityExcellent { return .green }
        if drop < photoStabilityAcceptable { return .orange }
        return .red
    }

    // MARK: - Inspector Single-Sample Assessments

    static func singleSampleAssessments(metrics: SpectralMetrics) -> [String] {
        var lines: [String] = []

        if metrics.criticalWavelength >= broadSpectrumCriticalWL {
            lines.append("✓ Broad-spectrum: critical λ ≥370 nm — adequate UVA coverage.")
        } else {
            lines.append("✗ Not broad-spectrum: critical λ below 370 nm — UVA protection is insufficient.")
        }

        if metrics.uvaUvbRatio >= colipaUvaUvbMinimum {
            lines.append("✓ UVA/UVB ratio meets COLIPA minimum (≥0.33).")
        } else {
            lines.append("✗ UVA/UVB ratio below 0.33 — fails COLIPA requirement. Consider boosting UVA filters.")
        }

        if metrics.meanUVBTransmittance < 0.01 {
            lines.append("Strong UVB blocking (mean transmittance <1%).")
        } else if metrics.meanUVBTransmittance < 0.05 {
            lines.append("Good UVB blocking (mean transmittance <5%).")
        } else {
            lines.append("Moderate UVB transmittance — verify SPF adequacy.")
        }

        return lines
    }

    // MARK: - Inspector Batch Assessments

    static func batchAssessments(avgUvaUvb: Double, avgCritical: Double, uvaUvbRange: ClosedRange<Double>, criticalRange: ClosedRange<Double>) -> [String] {
        var lines: [String] = []

        if avgCritical >= broadSpectrumCriticalWL {
            lines.append("✓ Average critical λ meets broad-spectrum threshold.")
        } else {
            lines.append("✗ Average critical λ below 370 nm — batch does not qualify as broad-spectrum.")
        }

        if avgUvaUvb >= colipaUvaUvbMinimum {
            lines.append("✓ Average UVA/UVB ratio meets COLIPA requirement.")
        } else {
            lines.append("✗ Average UVA/UVB below 0.33 — batch fails COLIPA requirement.")
        }

        let uvaSpread = uvaUvbRange.upperBound - uvaUvbRange.lowerBound
        if uvaSpread > 0.15 {
            lines.append("High variability in UVA/UVB ratio (spread: \(String(format: "%.3f", uvaSpread))) — check formulation consistency.")
        }

        let critSpread = criticalRange.upperBound - criticalRange.lowerBound
        if critSpread > 10 {
            lines.append("Wide critical λ range (\(String(format: "%.0f", critSpread)) nm) — review outlier samples.")
        }

        return lines
    }

    // MARK: - SPF Tier Explanation

    static func tierExplanation(tier: SPFEstimationTier, details: SPFEstimationDetails) -> String {
        var parts: [String] = [details.explanation]
        if !details.missingDataHints.isEmpty {
            parts.append("To improve: " + details.missingDataHints.joined(separator: " "))
        }
        return parts.joined(separator: "\n")
    }

    static func complianceInterpretation(percent: Double, tier: SPFEstimationTier?) -> String {
        let tierNote: String
        if let tier {
            tierNote = " Method: \(tier.label)."
        } else {
            tierNote = ""
        }
        if percent >= 80 {
            return "Strong compliance — most samples meet estimated SPF ≥30.\(tierNote)"
        } else if percent >= 50 {
            return "Moderate compliance — consider reformulation for failing samples.\(tierNote)"
        } else if percent > 0 {
            return "Low compliance — majority below estimated SPF 30.\(tierNote)"
        } else {
            return "No samples reach estimated SPF 30. \(tier == .adjusted ? "Values are approximate (adjusted COLIPA). Add calibration samples or correction factors to improve accuracy." : "Add calibration samples to improve estimates.")"
        }
    }

    // MARK: - Calibration Quality

    static func calibrationQualityLabel(r2: Double) -> String {
        if r2 >= 0.95 {
            return "Excellent fit — predictions are highly reliable."
        } else if r2 >= 0.9 {
            return "Good fit — predictions are generally reliable."
        } else if r2 >= 0.7 {
            return "Moderate fit — use estimates with caution."
        } else {
            return "Poor fit — add more calibration samples or review data quality."
        }
    }

    // MARK: - Delta Color

    static func deltaColor(_ value: Double?, positive: Color, negative: Color, threshold: Double) -> Color {
        guard let value, abs(value) > 0.001 else { return .primary }
        if abs(value) < threshold { return .primary }
        return value > 0 ? positive : negative
    }

    // MARK: - Metric Status

    enum MetricStatus {
        case pass
        case warn
        case fail

        var iconName: String {
            switch self {
            case .pass: return "checkmark.circle.fill"
            case .warn: return "exclamationmark.triangle.fill"
            case .fail: return "xmark.circle.fill"
            }
        }

        var color: Color {
            switch self {
            case .pass: return .green
            case .warn: return .orange
            case .fail: return .red
            }
        }

        static func forUvaUvb(_ ratio: Double) -> MetricStatus {
            ratio >= SpectralInterpretation.colipaUvaUvbMinimum ? .pass : .fail
        }

        static func forCriticalWavelength(_ wl: Double) -> MetricStatus {
            wl >= SpectralInterpretation.broadSpectrumCriticalWL ? .pass : .warn
        }

        static func forSpf(_ value: Double) -> MetricStatus {
            if value >= SpectralInterpretation.spfComplianceThreshold { return .pass }
            if value >= SpectralInterpretation.spfModeratThreshold { return .warn }
            return .fail
        }
    }

    // MARK: - ISO 23675 HDRS Interpretation

    /// Maximum allowed 95% CI as percentage of mean (ISO 23675 requirement).
    static let hdrsMaxCI = 17.0
    /// Minimum number of plate pairs required by ISO 23675.
    static let hdrsMinPlatePairs = 3

    /// Human-readable compliance assessment for an HDRS result.
    static func hdrsComplianceAssessment(result: HDRSResult) -> String {
        if result.isValid {
            return String(format: "ISO 23675 compliant — SPF %.1f ± %.1f (95%% CI: %.1f%% of mean, %d plate pairs).",
                          result.meanSPF, result.standardDeviation,
                          result.confidenceInterval95Percent, result.pairResults.count)
        }

        var issues: [String] = []
        if result.confidenceInterval95Percent > hdrsMaxCI {
            issues.append(String(format: "95%% CI (%.1f%%) exceeds maximum 17%%", result.confidenceInterval95Percent))
        }
        if result.pairResults.count < hdrsMinPlatePairs {
            issues.append("fewer than 3 plate pairs (\(result.pairResults.count) provided)")
        }
        let joined = issues.joined(separator: "; ")
        return String(format: "Does not meet ISO 23675 — SPF %.1f: %@.", result.meanSPF, joined)
    }

    /// Per-pair interpretation for HDRS results.
    static func hdrsPairAssessment(pair: HDRSPairResult) -> String {
        if let post = pair.spfPost {
            return String(format: "Pair %d: Pre-irradiation SPF = %.1f, dose = %.0f J/m², post-irradiation SPF = %.1f → final SPF = %.1f",
                          pair.plateIndex, pair.spfPre, pair.irradiationDose, post, pair.spfFinal)
        } else {
            return String(format: "Pair %d: Pre-irradiation SPF = %.1f (no post-irradiation data) → SPF = %.1f",
                          pair.plateIndex, pair.spfPre, pair.spfFinal)
        }
    }

    /// HDRS SPF metric status.
    static func hdrsStatus(result: HDRSResult) -> MetricStatus {
        if result.isValid && result.meanSPF >= spfComplianceThreshold { return .pass }
        if result.isValid && result.meanSPF >= spfModeratThreshold { return .warn }
        return .fail
    }
}
