import SwiftUI
import Charts

extension ContentView {

    var chartSection: some View {
        Group {
            if analysis.hasRenderableSeries {
                let baseChart = Chart {
                    chartSeriesMarks
                    selectedPointMarks
                    peakMarks
                }
                .chartLegend(analysis.showLegend ? .visible : .hidden)
                .chartXAxisLabel("Wavelength (nm)")
                .chartYAxisLabel("Intensity")
                .chartXScale(domain: analysis.chartWavelengthRange)
                .chartScrollableAxes([.horizontal, .vertical])
                .chartXSelection(value: $analysis.chartSelectionX)
                .chartXVisibleDomain(length: max(analysis.chartVisibleDomain, 1))
                .chartYVisibleDomain(length: max(analysis.chartVisibleYDomain, 0.01))
                .chartOverlay { proxy in
                    ChartOverlayContent(analysis: analysis, proxy: proxy)
                }
                .frame(minHeight: 320)

                if analysis.chartSeriesNames.isEmpty {
                    baseChart
                } else {
                    baseChart.chartForegroundStyleScale(
                        domain: analysis.chartSeriesNames,
                        range: analysis.chartPaletteRange
                    )
                }

                if analysis.showLabels && analysis.showAllSpectra {
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

    var correlationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("SPF Estimation")
                    .font(.headline)
                Spacer()
                if analysis.selectedSpectrum != nil, analysis.selectedMetrics != nil {
                    Button("Math…") {
                        showSpfMathDetails = true
                    }
                    #if os(macOS)
                    .buttonStyle(.link)
                    #else
                    .buttonStyle(.borderless)
                    #endif
                }
            }
            if let spectrum = analysis.selectedSpectrum, let metrics = analysis.selectedMetrics {
                let matched = SPFLabelStore.matchLabel(for: spectrum.name)

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
                    HStack(spacing: 4) {
                        Text(String(format: "Critical Wavelength: %.1f nm", metrics.criticalWavelength))
                        HelpButton("Critical Wavelength (\u{03bb}c)", message: "The **critical wavelength** is the point in the UV spectrum where **90% of total absorbance** (from 290\u{2013}400 nm) has been reached.\n\nIt indicates how far into the UVA range a sunscreen provides protection:\n\n\u{2022} **\u{2265}370 nm** \u{2014} Classified as **broad-spectrum** (good UVA coverage)\n\u{2022} **<370 nm** \u{2014} Protection is concentrated in UVB; UVA protection is insufficient\n\nHigher values mean the sunscreen absorbs deeper into the UVA range, which is important because UVA causes skin aging and contributes to cancer risk.")
                    }
                    HStack(spacing: 4) {
                        Text(String(format: "UVA/UVB Ratio: %.3f", metrics.uvaUvbRatio))
                        HelpButton("UVA/UVB Ratio", message: "The **UVA/UVB ratio** compares the sunscreen\u{2019}s absorption across two UV wavelength ranges:\n\n\u{2022} **UVA** (320\u{2013}400 nm) \u{2014} Longer wavelengths that penetrate deeper into skin, causing aging and DNA damage\n\u{2022} **UVB** (290\u{2013}320 nm) \u{2014} Shorter wavelengths that cause sunburn\n\nThe **COLIPA standard** requires a ratio of **\u{2265}0.33** for a product to carry a \u{201c}broad-spectrum\u{201d} or \u{201c}UVA seal\u{201d} label. A ratio below 0.33 means the product protects primarily against sunburn but provides inadequate UVA protection.")
                    }
                }

                // Prominent resolved SPF with tier badge
                if let estimation = analysis.cachedSPFEstimation {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(String(format: "SPF: %.1f", estimation.value))
                                .font(.title2.bold())
                            Text(estimation.tier.label)
                                .font(.caption.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(estimation.tier.badgeColor.opacity(0.2))
                                .foregroundColor(estimation.tier.badgeColor)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }

                        if let raw = estimation.rawColipaValue {
                            Text(String(format: "Raw COLIPA: %.2f", raw))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        DisclosureGroup("Method Details") {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(estimation.tier.qualityDescription)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(estimation.details.explanation)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)

                                // Show sample spectral profile features
                                Divider()
                                Text("Sample Spectral Profile:")
                                    .font(.caption2.bold())
                                    .foregroundColor(.secondary)
                                Text(String(format: "UVB Area: %.3f  •  UVA Area: %.3f  •  Peak λ: %.0f nm", metrics.uvbArea, metrics.uvaArea, metrics.peakAbsorbanceWavelength))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(String(format: "Critical λ: %.1f nm  •  UVA/UVB: %.3f", metrics.criticalWavelength, metrics.uvaUvbRatio))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(String(format: "Mean UVB T: %.4f  •  Mean UVA T: %.4f", metrics.meanUVBTransmittance, metrics.meanUVATransmittance))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                if let raw = estimation.rawColipaValue {
                                    Text(String(format: "Raw in-vitro SPF: %.2f", raw))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }

                                // Show nearest match details
                                if let nm = analysis.cachedNearestMatch {
                                    Divider()
                                    Text("Nearest Reference: \(nm.matchedReferenceName.isEmpty ? "Unknown" : nm.matchedReferenceName) — SPF \(String(format: "%.0f", nm.matchedReferenceSPF)) (raw \(String(format: "%.2f", nm.matchedReferenceRawSPF))), distance = \(String(format: "%.3f", nm.distance))")
                                        .font(.caption2)
                                        .foregroundColor(nm.distance < 0.8 ? .secondary : .orange)
                                }

                                if !estimation.details.missingDataHints.isEmpty {
                                    Divider()
                                    Text("To improve accuracy:")
                                        .font(.caption2.bold())
                                        .foregroundColor(.orange)
                                    ForEach(estimation.details.missingDataHints, id: \.self) { hint in
                                        Text("• \(hint)")
                                            .font(.caption2)
                                            .foregroundColor(.orange)
                                    }
                                }
                            }
                            .padding(.top, 4)
                        }
                        .font(.caption)
                    }
                } else if let colipa = analysis.colipaSpfValue {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(format: "Raw COLIPA SPF: %.2f", colipa))
                            .font(.headline)
                        Text("No estimation method available.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                // Calibration model info — only show when the OLS regression model
                // was actually used for the estimation.  When the C-coefficient
                // nearest-reference method produced the result, the OLS R² is
                // irrelevant and its "poor fit" warning would be misleading.
                if let calibration = analysis.calibrationResult,
                   analysis.cachedSPFEstimation?.details.nearestMatchDistance == nil {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(String(format: "Calibration Model: R\u{00B2} = %.3f  \u{2022}  RMSE = %.2f  \u{2022}  n = %d", calibration.r2, calibration.rmse, calibration.sampleCount))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            HelpButton("Calibration Model Metrics", message: "These metrics describe how well the calibration model fits your reference data:\n\n**R\u{00B2} (R-squared)** \u{2014} Measures how much of the variation in SPF the model explains. Ranges from 0 to 1:\n\u{2022} \u{2265}0.90 \u{2014} Excellent fit\n\u{2022} 0.70\u{2013}0.89 \u{2014} Acceptable\n\u{2022} <0.70 \u{2014} Poor fit; add more diverse reference samples\n\n**RMSE (Root Mean Square Error)** \u{2014} The average prediction error in SPF units. Lower is better. An RMSE of 3.0 means predictions are typically within \u{00B1}3 SPF of the true value.\n\n**n** \u{2014} The number of reference samples used to build the model. More samples generally improve reliability.")
                        }
                        Text(SpectralInterpretation.calibrationQualityLabel(r2: calibration.r2))
                            .font(.caption2)
                            .foregroundColor(calibration.r2 >= 0.9 ? .green : (calibration.r2 >= 0.7 ? .orange : .red))
                    }
                } else if let estimation = analysis.cachedSPFEstimation, estimation.tier == .adjusted {
                    Text("Optional: Tag 3+ datasets as Reference with known in-vivo SPF in Data Management to enable calibrated estimation (Tier 2).")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                Text("No spectrum selected for correlation.")
                    .foregroundColor(.secondary)
            }

            // MARK: - ISO 23675 HDRS Results
            if !analysis.hdrsResults.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text("ISO 23675 HDRS Results")
                            .font(.subheadline.bold())
                        HelpButton("ISO 23675 HDRS", message: "**HDRS** (High Dynamic Range SPF) is the method defined in **ISO 23675:2024** for measuring in-vitro SPF with improved accuracy.\n\nUnlike traditional methods that use a single measurement, HDRS uses **multiple plate pairs** at different UV doses to build a dose-response curve. This reduces measurement noise and produces a more reliable SPF value.\n\n**95% CI** is the confidence interval \u{2014} it must be \u{2264}17% of the mean SPF to pass ISO requirements.\n\n**Plate pairs** show individual pre- and post-irradiation SPF values and the UV dose applied.")
                        Spacer()
                        Text(analysis.hdrsProductType.label)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    ForEach(analysis.hdrsResults.values.sorted(by: { $0.sampleName < $1.sampleName }), id: \.sampleName) { result in
                        VStack(alignment: .leading, spacing: 4) {
                            if !result.sampleName.isEmpty {
                                Text(result.sampleName)
                                    .font(.caption.bold())
                            }
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(String(format: "SPF: %.1f ± %.1f", result.meanSPF, result.standardDeviation))
                                    .font(.title3.bold())
                                Image(systemName: result.isValid ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundColor(result.isValid ? .green : .red)
                                    .font(.caption)
                            }
                            Text(String(format: "95%% CI: %.1f%% of mean", result.confidenceInterval95Percent))
                                .font(.caption)
                                .foregroundColor(result.confidenceInterval95Percent <= 17.0 ? .green : .red)

                            DisclosureGroup("Plate Pairs (\(result.pairResults.count))") {
                                ForEach(result.pairResults, id: \.plateIndex) { pair in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(String(format: "Pair %d: SPF_pre = %.1f", pair.plateIndex, pair.spfPre))
                                            .font(.caption2)
                                        Text(String(format: "  Dose = %.0f J/m²", pair.irradiationDose))
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        if let post = pair.spfPost {
                                            Text(String(format: "  SPF_post = %.1f → SPF_final = %.1f", post, pair.spfFinal))
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        } else {
                                            Text(String(format: "  SPF_final = %.1f (no post-irradiation data)", pair.spfFinal))
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                            }
                            .font(.caption)

                            ForEach(result.warnings, id: \.self) { warning in
                                HStack(spacing: 4) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.orange)
                                    Text(warning)
                                }
                                .font(.caption2)
                                .foregroundColor(.orange)
                            }

                            if result.pairResults.count > 1 {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    var labelsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(analysis.seriesToPlot) { series in
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

    @ChartContentBuilder
    var chartSeriesMarks: some ChartContent {
        let selectedNames = Set(analysis.selectedSpectra.map { $0.name })

        if analysis.showAllSpectra && !analysis.showSelectedOnly {
            ForEach(analysis.seriesToPlot) { series in
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
        } else if !analysis.showSelectedOnly, let first = displayedSpectra.first {
            let color = analysis.palette.colors[analysis.selectedSpectrumIndex % analysis.palette.colors.count]
            ForEach(analysis.points(for: first)) { point in
                LineMark(
                    x: .value("Wavelength", point.x),
                    y: .value("Intensity", point.y)
                )
                .foregroundStyle(color)
                .lineStyle(StrokeStyle(lineWidth: 1.8))
            }
        }

        if analysis.showSelectedOnly {
            let selectedSnapshot = Array(analysis.selectedSpectra)
            ForEach(selectedSnapshot) { spectrum in
                let points = analysis.points(for: spectrum)
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

        if analysis.showAverage, let avg = analysis.averageSpectrum {
            ForEach(analysis.points(for: avg)) { point in
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
    var selectedPointMarks: some ChartContent {
        if let selectedPoint = analysis.selectedPoint {
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
    var peakMarks: some ChartContent {
        if analysis.showPeaks {
            ForEach(analysis.peaks.filter { analysis.chartWavelengthRange.contains($0.x) }) { peak in
                PointMark(
                    x: .value("Wavelength", peak.x),
                    y: .value("Intensity", peak.y)
                )
                .foregroundStyle(Color.red)
            }
        }
    }

    func pointAnnotation(for point: SpectrumPoint) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(String(format: "%.1f nm", point.x))
                .font(.caption)
                .bold()
            Text(String(format: "%.4f", point.y))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(6)
        .glassEffect(.regular, in: .rect(cornerRadius: 8))
    }


    var pointReadoutPanel: some View {
        PointReadoutContent(analysis: analysis)
    }

}

// MARK: - Chart Overlay (isolated view to limit re-renders on hover)

/// Separate View struct so that `chartHoverLocation` and `chartSelectionX`
/// observations are isolated — only this overlay re-renders on every hover
/// event, not the entire ContentView body.
private struct ChartOverlayContent: View {
    let analysis: AnalysisViewModel
    let proxy: ChartProxy

    var body: some View {
        GeometryReader { geo in
            let plotRect: CGRect = {
                if let plotFrame = proxy.plotFrame {
                    return geo[plotFrame]
                }
                return .zero
            }()

            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            updateHover(location, plotRect: plotRect)
                        case .ended:
                            analysis.chartHoverLocation = nil
                            analysis.chartSelectionX = nil
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                updateHover(value.location, plotRect: plotRect)
                            }
                            .onEnded { value in
                                updateSelection(value.location, plotRect: plotRect)
                            }
                    )

                if let selectedPoint = analysis.selectedPoint,
                   let hover = analysis.chartHoverLocation {
                    tooltipView(for: selectedPoint, plotRect: plotRect, location: hover)
                }
            }
        }
    }

    private func updateHover(_ location: CGPoint, plotRect: CGRect) {
        guard plotRect.contains(location) else { return }
        analysis.chartHoverLocation = location
        let xPosition = location.x - plotRect.origin.x
        if let xValue: Double = proxy.value(atX: xPosition) {
            analysis.chartSelectionX = xValue
        }
    }

    private func updateSelection(_ location: CGPoint, plotRect: CGRect) {
        guard plotRect.contains(location) else { return }
        let xPosition = location.x - plotRect.origin.x
        let yPosition = location.y - plotRect.origin.y
        guard let xValue: Double = proxy.value(atX: xPosition),
              let yValue: Double = proxy.value(atY: yPosition) else { return }
        analysis.chartSelectionX = xValue
        analysis.selectSpectrumNearest(toX: xValue, y: yValue)
    }

    private func tooltipView(for point: SpectrumPoint, plotRect: CGRect, location: CGPoint) -> some View {
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
        .glassEffect(.regular, in: .rect(cornerRadius: 8))
        .position(x: clampedX + tooltipWidth / 2, y: clampedY + tooltipHeight / 2)
    }
}

// MARK: - Point Readout (isolated view to limit re-renders on selection)

/// Separate View struct so that `selectedPoint` observation is isolated.
private struct PointReadoutContent: View {
    let analysis: AnalysisViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Point Readout")
                .font(.caption)
                .foregroundColor(.secondary)

            if let selectedPoint = analysis.selectedPoint {
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
        .glassEffect(.regular, in: .rect(cornerRadius: 10))
    }
}
