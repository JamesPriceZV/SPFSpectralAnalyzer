#if os(iOS)
import SwiftUI
import SwiftData
import Charts

/// Standalone iOS view for the Analysis tab.
/// iPhone: ScrollView with sheet-based Pipeline/AI panels.
/// iPad: NavigationSplitView with dataset sidebar + chart detail.
struct iOSAnalysisView: View {
    @Bindable var analysis: AnalysisViewModel
    var datasets: DatasetViewModel
    var aiVM: AIViewModel
    var storedDatasets: [StoredDataset]
    var runAI: () -> Void

    @AppStorage("aiEnabled") private var aiEnabled = false
    @AppStorage("spfCalculationMethod") private var spfCalculationMethodRawValue = SPFCalculationMethod.colipa.rawValue

    @Environment(\.horizontalSizeClass) private var sizeClass

    // Sheet state — only one sheet at a time
    @State private var activeSheet: AnalysisSheet?
    @State private var spectraSearchText: String = ""
    @State private var showStoredDatasets: Bool = false
    @Namespace private var glassNamespace

    private enum AnalysisSheet: Identifiable {
        case pipeline, ai, datasets
        var id: String {
            switch self {
            case .pipeline: return "pipeline"
            case .ai: return "ai"
            case .datasets: return "datasets"
            }
        }
    }

    var body: some View {
        if sizeClass == .regular {
            iPadLayout
        } else {
            iPhoneLayout
        }
    }

    // MARK: - iPad Layout (NavigationSplitView)

    private var iPadLayout: some View {
        NavigationSplitView {
            datasetSidebar
                .navigationTitle("Datasets")
                .navigationSplitViewColumnWidth(min: 280, ideal: 400, max: .infinity)
                .searchable(text: $spectraSearchText, prompt: "Filter spectra")
                .toolbar {
                    ToolbarItem(placement: .secondaryAction) {
                        Button {
                            withAnimation { showStoredDatasets.toggle() }
                        } label: {
                            Label(
                                showStoredDatasets ? "Hide Stored" : "Browse Stored",
                                systemImage: showStoredDatasets ? "folder.fill" : "folder"
                            )
                        }
                    }
                }
        } detail: {
            ScrollView {
                VStack(spacing: 16) {
                    if let metrics = analysis.dashboardMetrics {
                        dashboardSection(metrics)
                    }
                    chartCard
                    chartControls
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Analysis")
            .toolbar { analysisToolbar }
        }
        .navigationSplitViewStyle(.prominentDetail)
        .sheet(item: $activeSheet) { sheet in
            sheetContent(for: sheet)
        }
    }

    // MARK: - iPhone Layout (ScrollView)

    private var iPhoneLayout: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let metrics = analysis.dashboardMetrics {
                        dashboardSection(metrics)
                    }
                    chartCard
                    chartControls

                    // Datasets quick-access button
                    Button {
                        activeSheet = .datasets
                    } label: {
                        HStack {
                            Label("Datasets (\(analysis.spectra.count))", systemImage: "list.bullet")
                            Spacer()
                            Image(systemName: "chevron.up")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(12)
                        .glassSurface(cornerRadius: 12, isInteractive: true)
                    }
                    .buttonStyle(.plain)
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Analysis")
            .toolbar { analysisToolbar }
            .sheet(item: $activeSheet) { sheet in
                sheetContent(for: sheet)
            }
        }
    }

    // MARK: - Shared Toolbar

    @ToolbarContentBuilder
    private var analysisToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            if aiEnabled {
                Button {
                    runAI()
                    activeSheet = .ai
                } label: {
                    Label("AI Analysis", systemImage: "sparkles")
                }
                .disabled(aiVM.isRunning || analysis.spectra.isEmpty)
                .accessibilityLabel("Run AI analysis")
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button {
                    analysis.runPipeline()
                } label: {
                    Label("Apply Pipeline", systemImage: "wand.and.stars")
                }
                .disabled(analysis.spectra.isEmpty)

                Button {
                    activeSheet = .pipeline
                } label: {
                    Label("Pipeline Settings", systemImage: "slider.horizontal.3")
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
            .accessibilityLabel("More options")
        }
    }

    // MARK: - Sheet Content

    @ViewBuilder
    private func sheetContent(for sheet: AnalysisSheet) -> some View {
        switch sheet {
        case .pipeline:
            NavigationStack {
                ScrollView {
                    pipelineControls
                        .padding()
                }
                .navigationTitle("Processing Pipeline")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { activeSheet = nil }
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)

        case .ai:
            NavigationStack {
                ScrollView {
                    aiSection
                        .padding()
                }
                .navigationTitle("AI Analysis")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { activeSheet = nil }
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)

        case .datasets:
            NavigationStack {
                ScrollView {
                    datasetList
                        .padding()
                }
                .navigationTitle("Datasets (\(analysis.spectra.count))")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { activeSheet = nil }
                    }
                }
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Dataset Sidebar (iPad)

    private var filteredSpectra: [(offset: Int, element: ShimadzuSpectrum)] {
        let spectraSnapshot = Array(analysis.spectra)
        let enumerated = Array(spectraSnapshot.enumerated())
        guard !spectraSearchText.isEmpty else { return enumerated }
        return enumerated.filter { $0.element.name.localizedCaseInsensitiveContains(spectraSearchText) }
    }

    private var datasetSidebar: some View {
        List {
            // MARK: Loaded Spectra
            Section("Loaded Spectra — \(analysis.spectra.count)") {
                if analysis.spectra.isEmpty {
                    ContentUnavailableView(
                        "No Spectra",
                        systemImage: "waveform.path.ecg",
                        description: Text("Load datasets from the Data tab or browse stored datasets below.")
                    )
                } else {
                    ForEach(filteredSpectra, id: \.offset) { index, spectrum in
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
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(spectrum.name)
                                        .font(.subheadline)
                                        .lineLimit(2)
                                        .foregroundColor(.primary)
                                    Text("\(spectrum.x.count) pts")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // MARK: Stored Datasets (Load & Append)
            if showStoredDatasets {
                Section("Stored Datasets — \(storedDatasets.count)") {
                    if storedDatasets.isEmpty {
                        Text("No stored datasets available.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(storedDatasets) { dataset in
                            let record = datasets.searchableRecordCache[dataset.id]
                            let isChecked = datasets.selectedStoredDatasetIDs.contains(dataset.id)
                            Button {
                                if isChecked {
                                    datasets.selectedStoredDatasetIDs.remove(dataset.id)
                                } else {
                                    datasets.selectedStoredDatasetIDs.insert(dataset.id)
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(isChecked ? .blue : .secondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 4) {
                                            Text(record?.fileName ?? dataset.id.uuidString)
                                                .font(.subheadline)
                                                .lineLimit(2)
                                                .foregroundColor(.primary)
                                            if record?.isReference == true {
                                                Text("REF")
                                                    .font(.caption2.bold())
                                                    .padding(.horizontal, 4)
                                                    .padding(.vertical, 1)
                                                    .background(Color.blue.opacity(0.2))
                                                    .foregroundColor(.blue)
                                                    .cornerRadius(3)
                                            } else if record?.isPrototype == true {
                                                Text("PROTO")
                                                    .font(.caption2.bold())
                                                    .padding(.horizontal, 4)
                                                    .padding(.vertical, 1)
                                                    .background(Color.green.opacity(0.2))
                                                    .foregroundColor(.green)
                                                    .cornerRadius(3)
                                            }
                                        }
                                        Text("\(record?.spectrumCount ?? 0) spectra")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button {
                                    datasets.selectedStoredDatasetIDs = [dataset.id]
                                    datasets.loadStoredDatasetSelection(append: false, storedDatasets: storedDatasets)
                                } label: {
                                    Label("Load (Replace)", systemImage: "arrow.down.doc")
                                }
                                Button {
                                    datasets.selectedStoredDatasetIDs = [dataset.id]
                                    datasets.loadStoredDatasetSelection(append: true, storedDatasets: storedDatasets)
                                } label: {
                                    Label("Append to Loaded", systemImage: "doc.badge.plus")
                                }
                            }
                        }

                        // Bulk Load/Append buttons for checked datasets
                        if !datasets.selectedStoredDatasetIDs.isEmpty {
                            HStack(spacing: 12) {
                                Button {
                                    datasets.loadStoredDatasetSelection(append: false, storedDatasets: storedDatasets)
                                } label: {
                                    Label("Load", systemImage: "arrow.down.doc")
                                        .font(.caption)
                                }
                                .buttonStyle(.bordered)

                                Button {
                                    datasets.loadStoredDatasetSelection(append: true, storedDatasets: storedDatasets)
                                } label: {
                                    Label("Append", systemImage: "doc.badge.plus")
                                        .font(.caption)
                                }
                                .buttonStyle(.bordered)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Dashboard (Liquid Glass Cards)

    private func dashboardSection(_ metrics: DashboardMetrics) -> some View {
        GlassEffectContainer(spacing: 12) {
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
    }

    private func dashboardCard(title: String, value: String, detail: String, statusColor: Color = .secondary) -> some View {
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
        .glassClearSurface(cornerRadius: 12, tint: statusColor.opacity(0.15))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value), \(detail)")
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

    // MARK: - Chart Controls (Glass Toggle Bar)

    private var chartControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Chart display toggles — interactive glass capsules
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    glassToggle("All", isOn: $analysis.showAllSpectra)
                    glassToggle("Sel", isOn: $analysis.showSelectedOnly)
                    glassToggle("Avg", isOn: $analysis.showAverage)
                    glassToggle("Legend", isOn: $analysis.showLegend)
                    glassToggle("Labels", isOn: $analysis.showLabels)
                }
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

    private func glassToggle(_ label: String, isOn: Binding<Bool>) -> some View {
        Button {
            withAnimation(.smooth(duration: 0.25)) {
                isOn.wrappedValue.toggle()
            }
        } label: {
            Text(label)
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .foregroundColor(isOn.wrappedValue ? .white : .secondary)
        }
        .buttonStyle(.plain)
        .glassEffect(
            isOn.wrappedValue ? .regular.interactive().tint(.accentColor) : .regular.interactive(),
            in: Capsule()
        )
        .accessibilityLabel("\(label) \(isOn.wrappedValue ? "on" : "off")")
        .accessibilityAddTraits(isOn.wrappedValue ? .isSelected : [])
    }

    // MARK: - Dataset List (shared by iPhone sheet + iPad sidebar)

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
    }

    // MARK: - Pipeline Controls

    private var pipelineControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Align X-Axis", isOn: $analysis.useAlignment)
                .toggleStyle(.switch)

            Divider()

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

            VStack(alignment: .leading, spacing: 6) {
                Toggle("Detect Peaks", isOn: $analysis.detectPeaks)
                    .toggleStyle(.switch)
                if analysis.detectPeaks {
                    Toggle("Show Peaks on Chart", isOn: $analysis.showPeaks)
                        .toggleStyle(.switch)
                }
            }

            Button {
                analysis.runPipeline()
            } label: {
                Label("Apply Pipeline", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .disabled(analysis.spectra.isEmpty)
        }
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
                    aiVM.isRunning ? "Analyzing\u{2026}" : "Run AI Analysis",
                    systemImage: "sparkles"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
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
    }
}
#endif
