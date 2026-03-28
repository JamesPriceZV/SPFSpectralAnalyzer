#if os(iOS)
import SwiftUI
import Charts

/// Standalone iOS view for the Analysis tab.
/// Replaces the macOS-oriented 3-pane `analysisPanel` ContentView extension on iPhone/iPad.
struct iOSAnalysisView: View {
    @Bindable var analysis: AnalysisViewModel
    var datasets: DatasetViewModel
    var aiVM: AIViewModel
    var runAI: () -> Void

    @AppStorage("aiEnabled") private var aiEnabled = false
    @AppStorage("spfCalculationMethod") private var spfCalculationMethodRawValue = SPFCalculationMethod.colipa.rawValue

    @State private var showDatasets = false
    @State private var showPipeline = false
    @State private var showAI = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // MARK: - Dashboard Metrics
                    if let metrics = analysis.dashboardMetrics {
                        dashboardSection(metrics)
                    }

                    // MARK: - Spectral Chart
                    chartCard

                    // MARK: - Chart Controls
                    chartControls

                    // MARK: - Collapsible Sections
                    DisclosureGroup("Datasets (\(analysis.spectra.count))", isExpanded: $showDatasets) {
                        datasetList
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemGroupedBackground)))

                    DisclosureGroup("Processing Pipeline", isExpanded: $showPipeline) {
                        pipelineControls
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemGroupedBackground)))

                    if aiEnabled {
                        DisclosureGroup("AI Analysis", isExpanded: $showAI) {
                            aiSection
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemGroupedBackground)))
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Analysis")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        analysis.runPipeline()
                    } label: {
                        Label("Apply Pipeline", systemImage: "wand.and.stars")
                    }
                    .disabled(analysis.spectra.isEmpty)
                }
            }
        }
    }

    // MARK: - Dashboard

    private func dashboardSection(_ metrics: DashboardMetrics) -> some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8)
        ], spacing: 8) {
            dashboardCard(
                title: "SPF Compliance",
                value: String(format: "%.0f%%", metrics.compliancePercent),
                detail: "\(metrics.complianceCount)/\(metrics.totalCount) samples",
                statusColor: metrics.compliancePercent >= 80 ? .green : (metrics.compliancePercent >= 50 ? .orange : .red)
            )
            dashboardCard(
                title: "Avg UVA/UVB",
                value: String(format: "%.3f", metrics.avgUvaUvb),
                detail: metrics.avgUvaUvb >= 0.33 ? "Passes \u{2265} 0.33" : "Below 0.33",
                statusColor: metrics.avgUvaUvb >= 0.33 ? .green : .orange
            )
            dashboardCard(
                title: "Avg Critical \u{03BB}",
                value: String(format: "%.1f nm", metrics.avgCritical),
                detail: metrics.avgCritical >= 370 ? "Passes \u{2265} 370" : "Below 370",
                statusColor: metrics.avgCritical >= 370 ? .green : .orange
            )
            if let drop = metrics.postIncubationDropPercent {
                dashboardCard(
                    title: "SPF Drop",
                    value: String(format: "%.1f%%", drop),
                    detail: "Post-incubation",
                    statusColor: drop < 10 ? .green : (drop < 20 ? .orange : .red)
                )
            }
        }
    }

    private func dashboardCard(title: String, value: String, detail: String, interpretation: String? = nil, statusColor: Color = .secondary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Text(value)
                .font(.title3.bold())
                .foregroundColor(statusColor == .secondary ? .primary : statusColor)
            Text(detail)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemGroupedBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(statusColor.opacity(0.3), lineWidth: 1)
                )
        )
    }

    // MARK: - Chart

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if analysis.hasRenderableSeries {
                Chart {
                    chartMarks
                }
                .chartLegend(analysis.showLegend ? .visible : .hidden)
                .chartXAxisLabel("Wavelength (nm)")
                .chartYAxisLabel("Intensity")
                .chartXScale(domain: analysis.chartWavelengthRange)
                .chartScrollableAxes([.horizontal])
                .chartXVisibleDomain(length: max(analysis.chartVisibleDomain, 1))
                .chartYVisibleDomain(length: max(analysis.chartVisibleYDomain, 0.01))
                .frame(minHeight: 280)

                // Labels section (color-coded spectrum names below chart)
                if analysis.showLabels && analysis.showAllSpectra {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(analysis.seriesToPlot) { series in
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(series.color)
                                    .frame(width: 8, height: 8)
                                Text(series.name)
                                    .font(.caption2)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .padding(.top, 4)
                }

                if let spectrum = analysis.selectedSpectrum,
                   let metrics = analysis.selectedMetrics {
                    Divider()
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(spectrum.name)
                                .font(.caption.bold())
                                .lineLimit(1)
                            Text(String(format: "Critical \u{03BB}: %.1f nm", metrics.criticalWavelength))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(String(format: "UVA/UVB: %.3f", metrics.uvaUvbRatio))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if let estimation = analysis.cachedSPFEstimation {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(String(format: "SPF %.1f", estimation.value))
                                    .font(.title3.bold())
                                Text(estimation.tier.label)
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(estimation.tier.badgeColor.opacity(0.2))
                                    .foregroundColor(estimation.tier.badgeColor)
                                    .cornerRadius(4)
                            }
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "No Spectra Loaded",
                    systemImage: "waveform.path.ecg",
                    description: Text("Load datasets from the Data Management tab.")
                )
                .frame(minHeight: 200)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemGroupedBackground)))
    }

    @ChartContentBuilder
    private var chartMarks: some ChartContent {
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
        } else if !analysis.showSelectedOnly, let first = analysis.displayedSpectra.first {
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
            ForEach(Array(selectedSnapshot.enumerated()), id: \.offset) { _, spectrum in
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
                    y: .value("Intensity", point.y),
                    series: .value("Sample", "Average")
                )
                .foregroundStyle(.black)
                .lineStyle(StrokeStyle(lineWidth: 2, dash: [6, 4]))
            }
        }
    }

    // MARK: - Chart Controls

    private var chartControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Chart display toggles — compact button style for iPhone
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 8) {
                compactToggle("All", isOn: $analysis.showAllSpectra)
                compactToggle("Sel", isOn: $analysis.showSelectedOnly)
                compactToggle("Avg", isOn: $analysis.showAverage)
                compactToggle("Legend", isOn: $analysis.showLegend)
                compactToggle("Labels", isOn: $analysis.showLabels)
            }

            // Y Axis picker
            Picker("Y Axis", selection: $analysis.yAxisMode) {
                ForEach(SpectralYAxisMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            // Zoom sliders
            HStack(spacing: 6) {
                Text("X")
                    .font(.caption.bold())
                    .frame(width: 14, alignment: .leading)
                Slider(value: $analysis.chartVisibleDomain, in: 40...140, step: 5)
                Text("\(Int(analysis.chartVisibleDomain)) nm")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(width: 48, alignment: .trailing)
            }

            HStack(spacing: 6) {
                Text("Y")
                    .font(.caption.bold())
                    .frame(width: 14, alignment: .leading)
                Slider(value: $analysis.chartVisibleYDomain, in: 0.2...1.2, step: 0.1)
                Text(String(format: "%.1f", analysis.chartVisibleYDomain))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(width: 48, alignment: .trailing)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemGroupedBackground)))
    }

    private func compactToggle(_ label: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            Text(label)
                .font(.caption2.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isOn.wrappedValue ? Color.accentColor.opacity(0.2) : Color(.tertiarySystemGroupedBackground))
                )
                .foregroundColor(isOn.wrappedValue ? .accentColor : .secondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isOn.wrappedValue ? Color.accentColor.opacity(0.4) : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Dataset List

    private var datasetList: some View {
        let spectraSnapshot = Array(analysis.spectra)
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(spectraSnapshot.enumerated()), id: \.offset) { index, spectrum in
                let isSelected = analysis.selectedSpectrumIndices.contains(index)
                Button {
                    if analysis.selectedSpectrumIndices.contains(index) {
                        analysis.selectedSpectrumIndices.remove(index)
                    } else {
                        analysis.selectedSpectrumIndices.insert(index)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(isSelected ? .accentColor : .secondary)
                        Text(spectrum.name)
                            .font(.subheadline)
                            .lineLimit(1)
                            .foregroundColor(.primary)
                        Spacer()
                        Text("\(spectrum.x.count) pts")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Pipeline Controls

    private var pipelineControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Alignment
            Toggle("Align X-Axis", isOn: $analysis.useAlignment)
                .toggleStyle(.switch)

            Divider()

            // Smoothing
            VStack(alignment: .leading, spacing: 6) {
                Text("Smoothing")
                    .font(.subheadline.bold())
                Picker("Method", selection: $analysis.smoothingMethod) {
                    ForEach(SmoothingMethod.allCases) { method in
                        Text(method.rawValue).tag(method)
                    }
                }
                .pickerStyle(.segmented)

                Stepper("Window: \(analysis.smoothingWindow)", value: $analysis.smoothingWindow, in: 3...51, step: 2)
                    .font(.caption)

                if analysis.smoothingMethod == .savitzkyGolay {
                    Stepper("Order: \(analysis.sgOrder)", value: $analysis.sgOrder, in: 2...6)
                        .font(.caption)
                }
            }

            Divider()

            // Baseline
            VStack(alignment: .leading, spacing: 6) {
                Text("Baseline")
                    .font(.subheadline.bold())
                Picker("Method", selection: $analysis.baselineMethod) {
                    ForEach(BaselineMethod.allCases) { method in
                        Text(method.rawValue).tag(method)
                    }
                }
                .pickerStyle(.segmented)
            }

            Divider()

            // Normalization
            VStack(alignment: .leading, spacing: 6) {
                Text("Normalization")
                    .font(.subheadline.bold())
                Picker("Method", selection: $analysis.normalizationMethod) {
                    ForEach(NormalizationMethod.allCases) { method in
                        Text(method.rawValue).tag(method)
                    }
                }
                .pickerStyle(.segmented)
            }

            Divider()

            // Peak Detection
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Detect Peaks", isOn: $analysis.detectPeaks)
                    .toggleStyle(.switch)
                if analysis.detectPeaks {
                    Toggle("Show Peaks on Chart", isOn: $analysis.showPeaks)
                        .toggleStyle(.switch)
                }
            }

            // Apply button
            Button {
                analysis.runPipeline()
            } label: {
                Label("Apply Pipeline", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(analysis.spectra.isEmpty)
        }
        .padding(.top, 8)
    }

    // MARK: - AI Section

    private var aiSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Provider: \(aiVM.providerManager.activeProviderName ?? "None")")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }

            Button {
                runAI()
            } label: {
                Label(
                    aiVM.isRunning ? "Analyzing…" : "Run AI Analysis",
                    systemImage: "sparkles"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)
            .disabled(aiVM.isRunning || analysis.spectra.isEmpty)

            if aiVM.isRunning {
                ProgressView()
                    .progressViewStyle(.linear)
            } else if let result = aiVM.result {
                Text(result.text)
                    .font(.caption)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(.tertiarySystemGroupedBackground)))
            }
        }
        .padding(.top, 8)
    }
}
#endif
