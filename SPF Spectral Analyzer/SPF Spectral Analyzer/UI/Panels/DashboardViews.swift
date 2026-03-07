import SwiftUI
import Charts

extension ContentView {

    var summaryStrip: some View {
        let selectionCount = analysis.selectedSpectra.count
        let selectedLabel = selectionCount == 1 ? (analysis.selectedSpectrum?.name ?? "None") : "\(selectionCount) samples"

        return glassGroup(spacing: 12) {
            HStack(spacing: 10) {
                metricChip(title: "Spectra", value: "\(displayedSpectra.count)")
                metricChip(title: "Selected", value: selectedLabel)

                if selectionCount == 1, let metrics = analysis.selectedMetrics {
                    metricChip(title: "UVA/UVB", value: String(format: "%.3f", metrics.uvaUvbRatio), status: metrics.uvaUvbRatio >= 0.33 ? .pass : .fail)
                    metricChip(title: "Critical λ", value: String(format: "%.1f nm", metrics.criticalWavelength), status: metrics.criticalWavelength >= 370 ? .pass : .warn)
                }

                if selectionCount > 1, let stats = analysis.selectedMetricsStats {
                    metricChip(title: "Avg UVA/UVB", value: String(format: "%.3f", stats.avgUvaUvb), status: stats.avgUvaUvb >= 0.33 ? .pass : .fail)
                    metricChip(title: "Avg Critical λ", value: String(format: "%.1f nm", stats.avgCritical), status: stats.avgCritical >= 370 ? .pass : .warn)
                    metricChip(title: "UVA/UVB Range", value: String(format: "%.3f–%.3f", stats.uvaUvbRange.lowerBound, stats.uvaUvbRange.upperBound))
                    metricChip(title: "Critical λ Range", value: String(format: "%.1f–%.1f nm", stats.criticalRange.lowerBound, stats.criticalRange.upperBound))
                }

                if selectionCount == 1, let estimation = analysis.cachedSPFEstimation {
                    metricChip(
                        title: "SPF (\(estimation.tier.shortLabel))",
                        value: String(format: "%.1f", estimation.value),
                        status: estimation.value >= 30 ? .pass : (estimation.value >= 15 ? .warn : .fail)
                    )
                }

                metricChip(title: "Metrics Range", value: "290–400 nm")

                Spacer(minLength: 0)
            }
        }
    }

    func dashboardPanel(_ metrics: DashboardMetrics) -> some View {
        let complianceText = String(format: "%.0f%%", metrics.compliancePercent)
        let tierLabel = metrics.spfEstimationTier?.label ?? "in-vitro"
        let complianceDetail = "\(metrics.complianceCount)/\(max(metrics.totalCount, 1)) \(tierLabel) SPF≥30"
        let uvaRangeText = String(format: "%.2f–%.2f", metrics.uvaUvbRange.lowerBound, metrics.uvaUvbRange.upperBound)
        let avgUvaText = String(format: "%.2f", metrics.avgUvaUvb)
        let criticalRangeText = String(format: "%.1f–%.1f nm", metrics.criticalRange.lowerBound, metrics.criticalRange.upperBound)
        let avgCriticalText = String(format: "%.1f nm", metrics.avgCritical)
        let trendText: String = {
            guard let drop = metrics.postIncubationDropPercent else { return "No incubation split" }
            return String(format: "%.1f%% drop", drop)
        }()

        let maxCount = metrics.heatmapBins.map { $0.count }.max() ?? 1

        let cardColumns = [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ]

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Dataset Dashboard")
                    .font(.headline)
                Spacer()
                Text("Samples: \(metrics.totalCount)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            LazyVGrid(columns: cardColumns, spacing: 12) {
                dashboardCard(
                    title: "Compliance",
                    value: complianceText,
                    detail: complianceDetail,
                    interpretation: SpectralInterpretation.complianceInterpretation(percent: metrics.compliancePercent, tier: metrics.spfEstimationTier),
                    interpretationColor: metrics.compliancePercent >= 80 ? .green : (metrics.compliancePercent >= 50 ? .orange : .red),
                    hint: metrics.spfEstimationTier == .adjusted
                        ? "Using adjusted COLIPA SPF (×\(String(format: "%.0f", spfAdjustmentFactor))). Provide correction factors or calibration samples for better accuracy."
                        : metrics.spfEstimationTier == .calibrated
                            ? "Using calibrated regression model. Accuracy depends on model quality (R², sample count)."
                            : metrics.spfEstimationTier == .fullColipa
                                ? "Using full COLIPA method with correction factors."
                                : "SPF estimation from 290–400 nm spectral data."
                )
                dashboardCard(
                    title: "Avg UVA/UVB",
                    value: avgUvaText,
                    detail: "Range: \(uvaRangeText)",
                    interpretation: uvaUvbInterpretation(ratio: metrics.avgUvaUvb),
                    interpretationColor: metrics.avgUvaUvb >= 0.33 ? .green : .orange,
                    hint: "Computed from 320–400 nm (UVA) vs 290–320 nm (UVB). COLIPA requires ≥0.33 for broad-spectrum."
                )
                dashboardCard(
                    title: "Avg Critical λ",
                    value: avgCriticalText,
                    detail: "Range: \(criticalRangeText)",
                    interpretation: criticalWavelengthInterpretation(wavelength: metrics.avgCritical),
                    interpretationColor: metrics.avgCritical >= 370 ? .green : .orange,
                    hint: "Critical wavelength is where cumulative absorbance reaches 90% of total (290–400 nm). ≥370 nm = broad-spectrum."
                )
                dashboardCard(
                    title: "Trends",
                    value: trendText,
                    detail: "Low critical: \(metrics.lowCriticalCount)",
                    interpretation: trendsInterpretation(drop: metrics.postIncubationDropPercent, lowCriticalCount: metrics.lowCriticalCount),
                    interpretationColor: trendsInterpretationColor(drop: metrics.postIncubationDropPercent),
                    hint: "Trends compare pre- vs post-incubation averages based on sample name keywords."
                )
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Batch UVA/UVB Heatmap")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .help("Heatmap bins UVA/UVB (x-axis) vs Critical λ (y-axis). Requires valid metrics for the loaded spectra.")
                if metrics.heatmapBins.isEmpty {
                    Text("Heatmap data unavailable for current spectra.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .frame(height: 180, alignment: .center)
                } else {
                    Chart {
                        ForEach(metrics.heatmapBins) { bin in
                            RectangleMark(
                                xStart: .value("UVA/UVB Min", bin.xRange.lowerBound),
                                xEnd: .value("UVA/UVB Max", bin.xRange.upperBound),
                                yStart: .value("Critical Min", bin.yRange.lowerBound),
                                yEnd: .value("Critical Max", bin.yRange.upperBound)
                            )
                            .foregroundStyle(Color.accentColor.opacity(0.3 + (0.7 * (Double(bin.count) / Double(maxCount)))))
                        }

                        // COLIPA UVA/UVB threshold (x = 0.33)
                        RuleMark(x: .value("COLIPA UVA/UVB", 0.33))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .foregroundStyle(.orange.opacity(0.7))
                            .annotation(position: .bottom, alignment: .leading) {
                                Text("UVA/UVB 0.33")
                                    .font(.system(size: 8))
                                    .foregroundColor(.orange)
                            }

                        // Broad-spectrum critical wavelength threshold (y = 370 nm)
                        RuleMark(y: .value("Broad-Spectrum", 370))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .foregroundStyle(.green.opacity(0.7))
                            .annotation(position: .trailing, alignment: .bottom) {
                                Text("λc 370 nm")
                                    .font(.system(size: 8))
                                    .foregroundColor(.green)
                            }
                    }
                    .chartXAxis {
                        AxisMarks(position: .bottom, values: .automatic(desiredCount: 5))
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading, values: .automatic(desiredCount: 5))
                    }
                    .frame(height: 180)
                }
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.02))
        .cornerRadius(12)
    }

    var dashboardEmptyPanel: some View {
        let message = displayedSpectra.isEmpty
            ? "Load spectra to populate compliance, heatmaps, and trends."
            : "Metrics unavailable for the current spectra selection."

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Dataset Dashboard")
                    .font(.headline)
                Spacer()
                Text("Samples: \(displayedSpectra.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(Color.white.opacity(0.02))
        .cornerRadius(12)
    }

    func dashboardCard(title: String, value: String, detail: String, interpretation: String? = nil, interpretationColor: Color = .secondary, hint: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.headline)
            Text(detail)
                .font(.caption2)
                .foregroundColor(.secondary)
            if let interpretation {
                Text(interpretation)
                    .font(.caption2)
                    .foregroundColor(interpretationColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.03))
        .cornerRadius(10)
        .help(hint ?? "")
    }

    func complianceInterpretation(percent: Double) -> String {
        if percent >= 80 {
            return "Strong compliance — most samples meet SPF ≥30."
        } else if percent >= 50 {
            return "Moderate compliance — consider reformulation for failing samples."
        } else {
            return "Low compliance — majority of samples below SPF 30 threshold."
        }
    }

    func uvaUvbInterpretation(ratio: Double) -> String {
        if ratio >= 0.33 {
            return "Meets COLIPA broad-spectrum requirement (≥0.33)."
        } else {
            return "Below 0.33 — does not meet COLIPA UVA/UVB requirement."
        }
    }

    func criticalWavelengthInterpretation(wavelength: Double) -> String {
        if wavelength >= 370 {
            return "Broad-spectrum (≥370 nm) — good UVA coverage."
        } else {
            return "Below 370 nm — insufficient UVA protection for broad-spectrum claim."
        }
    }

    func trendsInterpretation(drop: Double?, lowCriticalCount: Int) -> String {
        var parts: [String] = []
        if let drop {
            if drop < 10 {
                parts.append("Excellent photo-stability (<10% SPF loss).")
            } else if drop < 20 {
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

    func trendsInterpretationColor(drop: Double?) -> Color {
        guard let drop else { return .secondary }
        if drop < 10 { return .green }
        if drop < 20 { return .orange }
        return .red
    }

    func calibrationQualityLabel(r2: Double, rmse: Double) -> String {
        SpectralInterpretation.calibrationQualityLabel(r2: r2)
    }

    func deltaColor(_ value: Double?, positive: Color, negative: Color, threshold: Double) -> Color {
        SpectralInterpretation.deltaColor(value, positive: positive, negative: negative, threshold: threshold)
    }

    func inspectorAssessment(metrics: SpectralMetrics) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Assessment")
                .font(.caption)
                .bold()
            ForEach(SpectralInterpretation.singleSampleAssessments(metrics: metrics), id: \.self) { line in
                Text(line)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(8)
        .background(Color.white.opacity(0.03))
        .cornerRadius(8)
    }

    func inspectorBatchAssessment(stats: (avgUvaUvb: Double, avgCritical: Double, uvaUvbRange: ClosedRange<Double>, criticalRange: ClosedRange<Double>)) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Assessment")
                .font(.caption)
                .bold()
            ForEach(SpectralInterpretation.batchAssessments(avgUvaUvb: stats.avgUvaUvb, avgCritical: stats.avgCritical, uvaUvbRange: stats.uvaUvbRange, criticalRange: stats.criticalRange), id: \.self) { line in
                Text(line)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(8)
        .background(Color.white.opacity(0.03))
        .cornerRadius(8)
    }

}
