import SwiftUI

extension ContentView {

    var overlayControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            #if os(iOS)
            if horizontalSizeClass == .compact {
                compactOverlayToggles
            } else {
                regularOverlayToggles
            }
            #else
            regularOverlayToggles
            #endif

            if !analysis.invalidItems.isEmpty {
                HStack(spacing: 12) {
                    Toggle("Show Invalid", isOn: $showInvalidInline)
                        .toggleStyle(.switch)
                    Toggle("Plot Invalid", isOn: $analysis.includeInvalidInPlots)
                        .toggleStyle(.switch)
                        .disabled(analysis.showSelectedOnly)
                        .help(analysis.showSelectedOnly ? "Plot invalid only in All Spectra mode." : "Overlay invalid spectra on the chart.")
                }
            }

            #if os(iOS)
            if horizontalSizeClass == .compact {
                compactOverlayPickers
            } else {
                regularOverlayPickers
            }
            #else
            regularOverlayPickers
            #endif

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Text("X Zoom")
                        .frame(width: 60, alignment: .leading)
                    Slider(value: $analysis.chartVisibleDomain, in: 40...140, step: 5)
                    Text("\(Int(analysis.chartVisibleDomain)) nm")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 70, alignment: .trailing)
                }

                HStack(spacing: 12) {
                    Text("Y Zoom")
                        .frame(width: 60, alignment: .leading)
                    Slider(value: $analysis.chartVisibleYDomain, in: 0.2...1.2, step: 0.1)
                    Text(String(format: "%.1f", analysis.chartVisibleYDomain))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 70, alignment: .trailing)
                }
            }
        }
    }

    // MARK: - Overlay Controls Variants

    private var regularOverlayToggles: some View {
        HStack(spacing: 12) {
            Toggle("All Spectra", isOn: $analysis.showAllSpectra)
                .toggleStyle(.switch)
            Toggle("Selected Only", isOn: $analysis.showSelectedOnly)
                .toggleStyle(.switch)
            Toggle("Average", isOn: $analysis.showAverage)
                .toggleStyle(.switch)
            Toggle("Legend", isOn: $analysis.showLegend)
                .toggleStyle(.switch)
            Toggle("Labels", isOn: $analysis.showLabels)
                .toggleStyle(.switch)
        }
    }

    private var compactOverlayToggles: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Toggle("All", isOn: $analysis.showAllSpectra)
                    .toggleStyle(.switch)
                Toggle("Selected", isOn: $analysis.showSelectedOnly)
                    .toggleStyle(.switch)
                Toggle("Avg", isOn: $analysis.showAverage)
                    .toggleStyle(.switch)
            }
            HStack(spacing: 12) {
                Toggle("Legend", isOn: $analysis.showLegend)
                    .toggleStyle(.switch)
                Toggle("Labels", isOn: $analysis.showLabels)
                    .toggleStyle(.switch)
            }
        }
    }

    private var regularOverlayPickers: some View {
        HStack(spacing: 12) {
            Text("Y Axis")
            Picker("Y Axis", selection: $analysis.yAxisMode) {
                ForEach(SpectralYAxisMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Text("Palette")
            Picker("Palette", selection: $analysis.palette) {
                ForEach(SpectrumPalette.allCases) { value in
                    Text(value.rawValue).tag(value)
                }
            }
            .frame(width: 160)

            if analysis.showAllSpectra {
                Text("Overlay")
                Stepper(value: $analysis.overlayLimit, in: 1...200, step: 1) {
                    Text("\(analysis.overlayLimit)")
                        .frame(width: 40, alignment: .leading)
                }
            }
        }
    }

    private var compactOverlayPickers: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Y Axis").font(.caption).foregroundColor(.secondary)
                Picker("Y Axis", selection: $analysis.yAxisMode) {
                    ForEach(SpectralYAxisMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            HStack(spacing: 12) {
                Text("Palette")
                Picker("Palette", selection: $analysis.palette) {
                    ForEach(SpectrumPalette.allCases) { value in
                        Text(value.rawValue).tag(value)
                    }
                }
            }

            if analysis.showAllSpectra {
                HStack(spacing: 8) {
                    Text("Overlay")
                    Stepper(value: $analysis.overlayLimit, in: 1...200, step: 1) {
                        Text("\(analysis.overlayLimit)")
                            .frame(width: 40, alignment: .leading)
                    }
                }
            }
        }
    }

    var pipelinePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Processing Pipeline")
                    .font(.headline)
                Spacer()
                Button("Apply Pipeline") {
                    runAnalysisPipeline()
                }
                .glassButtonStyle(isProminent: true)
                .accessibilityIdentifier("applyPipelineButton")
                Button(showPipelineDetails ? "Collapse" : "Expand") {
                    showPipelineDetails.toggle()
                }
                .buttonStyle(.plain)
            }

            if showPipelineDetails {
                DisclosureGroup("Alignment", isExpanded: .constant(true)) {
                    Toggle("Align X-Axis", isOn: $analysis.useAlignment)
                        .toggleStyle(.switch)
                        .help("Resamples all spectra onto a common wavelength axis so they can be compared point-by-point. Enable when spectra have different x-axis spacing.")
                }

                DisclosureGroup("Smoothing", isExpanded: .constant(true)) {
                    Picker("Smoothing", selection: $analysis.smoothingMethod) {
                        ForEach(SmoothingMethod.allCases) { method in
                            Text(method.rawValue).tag(method)
                        }
                    }
                    .pickerStyle(.segmented)
                    .help("Reduces high-frequency noise. Moving Average is simpler; Savitzky-Golay preserves peak shapes better.")

                    if analysis.smoothingMethod == .movingAverage {
                        Stepper(value: $analysis.smoothingWindow, in: 3...51, step: 2) {
                            Text("Window: \(analysis.smoothingWindow)")
                        }
                        .help("Number of points averaged. Larger windows = more smoothing but may flatten real peaks.")
                    }

                    if analysis.smoothingMethod == .savitzkyGolay {
                        Stepper(value: $analysis.sgWindow, in: 5...51, step: 2) {
                            Text("SG Window: \(analysis.sgWindow)")
                        }
                        .help("Polynomial fitting window. Must be odd and larger than the polynomial order.")
                        Stepper(value: $analysis.sgOrder, in: 2...6, step: 1) {
                            Text("Order: \(analysis.sgOrder)")
                        }
                        .help("Polynomial degree. Higher orders follow the data more closely but may over-fit noise.")
                    }
                }

                DisclosureGroup("Baseline", isExpanded: .constant(true)) {
                    Picker("Baseline", selection: $analysis.baselineMethod) {
                        ForEach(BaselineMethod.allCases) { method in
                            Text(method.rawValue).tag(method)
                        }
                    }
                    .pickerStyle(.segmented)
                    .help("Corrects for instrument drift or cuvette absorbance. Min Subtract shifts the minimum to zero; Poly Fit removes a curved baseline.")
                }

                DisclosureGroup("Normalization", isExpanded: .constant(true)) {
                    Picker("Normalization", selection: $analysis.normalizationMethod) {
                        ForEach(NormalizationMethod.allCases) { method in
                            Text(method.rawValue).tag(method)
                        }
                    }
                    .pickerStyle(.segmented)
                    .help("Scales spectra for comparison. Min-Max scales to 0–1; Area normalizes by integrated area; Peak divides by the maximum value.")
                }

                DisclosureGroup("Peaks", isExpanded: .constant(true)) {
                    Toggle("Detect Peaks", isOn: $analysis.detectPeaks)
                        .toggleStyle(.switch)
                        .help("Finds local maxima above the minimum height threshold. Useful for identifying absorption bands.")
                    Toggle("Show Peaks", isOn: $analysis.showPeaks)
                        .toggleStyle(.switch)
                        .disabled(!analysis.detectPeaks)
                        .help("Overlays detected peak markers on the chart.")

                    if analysis.detectPeaks {
                        HStack(spacing: 8) {
                            Text("Min Height")
                            TextField("Min Height", value: $analysis.peakMinHeight, format: .number)
                                .frame(width: 80)
                                .help("Only peaks above this absorbance value are reported.")
                            Text("Min Distance")
                            Stepper(value: $analysis.peakMinDistance, in: 1...100, step: 1) {
                                Text("\(analysis.peakMinDistance)")
                                    .frame(width: 40, alignment: .leading)
                            }
                            .help("Minimum number of data points between peaks to avoid detecting noise as separate peaks.")
                        }
                        Button("Export Peaks CSV") { exportPeaksCSV() }
                            .disabled(analysis.peaks.isEmpty)
                    }
                }
            }
        }
    }

    var inspectorPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Method")
                    .font(.headline)
                Picker("", selection: Binding(
                    get: { SPFCalculationMethod(rawValue: spfCalculationMethodRawValue) ?? .colipa },
                    set: { spfCalculationMethodRawValue = $0.rawValue }
                )) {
                    ForEach(SPFCalculationMethod.allCases) { method in
                        Text(method.label).tag(method)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: 160)
                if SPFCalculationMethod(rawValue: spfCalculationMethodRawValue) == .iso23675 {
                    Picker("", selection: $analysis.hdrsProductType) {
                        ForEach(HDRSProductType.allCases) { type in
                            Text(type.label).tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: 100)
                    .help("ISO 23675 product formulation type")
                }
                Button {
                    rebuildAnalysisCaches()
                } label: {
                    if analysis.isRecalculating {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 14, height: 14)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .help("Recalculate all statistics using the selected method")
                .buttonStyle(.plain)
                .disabled(analysis.isRecalculating)
                let refSummary = datasets.referenceDatasetSummary
                if refSummary.total > 0 {
                    Button {
                        showReferenceFilterPopover = true
                    } label: {
                        let label = refSummary.included == refSummary.total
                            ? "\(refSummary.included) ref\(refSummary.included == 1 ? "" : "s")"
                            : "\(refSummary.included)/\(refSummary.total) refs"
                        Text(label)
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundColor(.blue)
                            .underline()
                    }
                    .buttonStyle(.plain)
                    .help("\(refSummary.included) of \(refSummary.total) reference datasets included in calibration. Click to manage.")
                    .popover(isPresented: $showReferenceFilterPopover) {
                        referenceFilterPopover
                    }
                }
                Spacer()
                Button(showInspectorDetails ? "Collapse" : "Expand") {
                    showInspectorDetails.toggle()
                }
                .buttonStyle(.plain)
            }

            if showInspectorDetails {
                let selectionCount = analysis.selectedSpectra.count

                if selectionCount == 1, let spectrum = analysis.selectedSpectrum {
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

                if selectionCount == 1, let metrics = analysis.selectedMetrics {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(format: "Critical Wavelength: %.1f nm", metrics.criticalWavelength))
                        Text(String(format: "UVA/UVB Ratio: %.3f", metrics.uvaUvbRatio))
                        Text(String(format: "Mean UVB Transmittance: %.3f", metrics.meanUVBTransmittance))
                        Text("Metrics Range: 290–400 nm")
                            .foregroundColor(.secondary)
                    }
                    .font(.caption)

                    inspectorAssessment(metrics: metrics)
                } else if selectionCount > 1, let stats = analysis.selectedMetricsStats {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(format: "Avg Critical Wavelength: %.1f nm", stats.avgCritical))
                        Text(String(format: "Avg UVA/UVB Ratio: %.3f", stats.avgUvaUvb))
                        Text(String(format: "Critical λ Range: %.1f–%.1f nm", stats.criticalRange.lowerBound, stats.criticalRange.upperBound))
                        Text(String(format: "UVA/UVB Range: %.3f–%.3f", stats.uvaUvbRange.lowerBound, stats.uvaUvbRange.upperBound))
                        Text("Metrics Range: 290–400 nm")
                            .foregroundColor(.secondary)
                    }
                    .font(.caption)

                    inspectorBatchAssessment(stats: stats)
                }

                spcHeaderSection
                correlationSection
            }
        }
    }

    var batchComparePanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Batch Compare")
                    .font(.headline)
                Spacer()
                Text(batchCompareSourceLabel)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            let rows = batchCompareRows
            if rows.isEmpty {
                Text("Select at least 2 spectra to compare deltas.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ScrollView(.horizontal) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text("Sample")
                                .frame(width: 140, alignment: .leading)
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
                                    .frame(width: 140, alignment: .leading)
                                Text(row.spf.map { String(format: "%.1f", $0) } ?? "—")
                                    .font(.caption)
                                    .frame(width: 60, alignment: .trailing)
                                Text(row.deltaSpf.map { String(format: "%+.1f", $0) } ?? "—")
                                    .font(.caption)
                                    .foregroundColor(deltaColor(row.deltaSpf, positive: .green, negative: .red, threshold: 2.0))
                                    .frame(width: 60, alignment: .trailing)
                                Text(row.uvaUvb.map { String(format: "%.2f", $0) } ?? "—")
                                    .font(.caption)
                                    .frame(width: 70, alignment: .trailing)
                                Text(row.deltaUvaUvb.map { String(format: "%+.2f", $0) } ?? "—")
                                    .font(.caption)
                                    .foregroundColor(deltaColor(row.deltaUvaUvb, positive: .green, negative: .red, threshold: 0.03))
                                    .frame(width: 60, alignment: .trailing)
                                Text(row.critical.map { String(format: "%.1f", $0) } ?? "—")
                                    .font(.caption)
                                    .frame(width: 70, alignment: .trailing)
                                Text(row.deltaCritical.map { String(format: "%+.1f", $0) } ?? "—")
                                    .font(.caption)
                                    .foregroundColor(deltaColor(row.deltaCritical, positive: .green, negative: .red, threshold: 2.0))
                                    .frame(width: 60, alignment: .trailing)
                            }
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.03))
        .cornerRadius(12)
    }

    var batchCompareSourceLabel: String {
        if analysis.selectedSpectra.count >= 2 {
            return "Baseline: first selected"
        }
        if displayedSpectra.count >= 2 {
            return "Using all spectra"
        }
        return "Select at least 2"
    }

    var batchCompareRows: [BatchCompareRow] {
        let spectra = batchCompareSpectra
        guard spectra.count >= 2 else { return [] }

        var rows: [BatchCompareRow] = []
        rows.reserveCapacity(spectra.count)

        var baselineMetrics: SpectralMetrics?
        var baselineSpf: Double?

        for spectrum in spectra {
            guard let metrics = SpectralMetricsCalculator.metrics(x: spectrum.x, y: spectrum.y, yAxisMode: analysis.yAxisMode) else {
                Instrumentation.log(
                    "Batch compare: metrics nil",
                    area: .processing, level: .warning,
                    details: "spectrum=\(spectrum.name) xCount=\(spectrum.x.count) yCount=\(spectrum.y.count) xRange=\(spectrum.x.first ?? 0)–\(spectrum.x.last ?? 0)"
                )
                continue
            }
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

    var batchCompareSpectra: [ShimadzuSpectrum] {
        let selected = analysis.selectedSpectra
        if selected.count >= 2 { return selected }
        let all = displayedSpectra
        if all.count >= 2 { return all }
        return selected
    }

    var spcHeaderSection: some View {
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

    var spcHeaderPreviewPanel: some View {
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

}
