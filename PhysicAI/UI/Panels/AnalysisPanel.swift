import SwiftUI

extension ContentView {

    var analysisPanel: some View {
        regularAnalysisPanel
    }

    /// Full 3-pane layout for macOS and iPad regular width
    private var regularAnalysisPanel: some View {
        platformHSplit {
            if !expandChart {
                if datasetSidebarCollapsed {
                    VStack {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                datasetSidebarCollapsed = false
                            }
                        } label: {
                            Image(systemName: "sidebar.left")
                        }
                        .help("Show Datasets Sidebar")
                        .buttonStyle(.glass)
                        .padding(.top, 8)

                        Spacer()
                    }
                    .frame(width: 32)
                    .glassEffect(.regular, in: .rect(cornerRadius: 16))
                    .cornerRadius(16)
                } else {
                    leftPanel
                        #if os(macOS)
                        .frame(minWidth: 280, idealWidth: 340, maxWidth: 420)
                        #else
                        .frame(minWidth: 240, idealWidth: 320, maxWidth: 420)
                        #endif
                }
            }

            centerPanel
                #if os(macOS)
                .frame(minWidth: 520, maxWidth: .infinity)
                #else
                .frame(minWidth: 300, maxWidth: .infinity)
                #endif

            if !expandChart {
                rightPanel
                    #if os(macOS)
                    .frame(minWidth: 300, idealWidth: 320, maxWidth: 380)
                    #else
                    .frame(minWidth: 200, idealWidth: 280, maxWidth: 380)
                    #endif
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(16)
    }

    var leftPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Datasets")
                    .font(.headline)
                Text("\(displayedSpectra.count)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.15))
                    .cornerRadius(4)
                Spacer()

                // Select All / Deselect All
                Button {
                    let allIndices = Set(0..<analysis.displayedSpectra.count)
                    if analysis.selectedSpectrumIndices == allIndices {
                        analysis.selectedSpectrumIndices.removeAll()
                    } else {
                        analysis.selectedSpectrumIndices = allIndices
                    }
                } label: {
                    let allSelected = !analysis.displayedSpectra.isEmpty &&
                        analysis.selectedSpectrumIndices.count == analysis.displayedSpectra.count
                    Image(systemName: allSelected ? "checkmark.circle.fill" : "checkmark.circle")
                }
                .help(analysis.selectedSpectrumIndices.count == analysis.displayedSpectra.count
                      ? "Deselect All" : "Select All")
                .buttonStyle(.glass)
                .disabled(analysis.displayedSpectra.isEmpty)

                Button {
                    datasets.showStoredDatasetPicker = true
                } label: {
                    Image(systemName: "plus")
                }
                .help("Add stored spectra")
                .buttonStyle(.glass)
                .accessibilityIdentifier("addDatasetsButton")

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        datasetSidebarCollapsed = true
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                }
                .help("Collapse Datasets Sidebar")
                .buttonStyle(.glass)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        expandChart.toggle()
                    }
                } label: {
                    Image(systemName: expandChart ? "rectangle.arrowtriangle.2.inward" : "rectangle.arrowtriangle.2.outward")
                }
                .help(expandChart ? "Show Side Panels" : "Expand Chart")
                .buttonStyle(.glass)
            }

            // Category tabs
            Picker("", selection: $analysisSidebarTab) {
                ForEach(AnalysisSidebarTab.allCases) { tab in
                    Text(analysisSidebarTabLabel(tab)).tag(tab)
                }
            }
            .pickerStyle(.segmented)

            // Sort and filter controls
            HStack(spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.caption2)
                    TextField("Filter...", text: $sidebarFilterText)
                        .textFieldStyle(.plain)
                        .font(.caption)
                    if !sidebarFilterText.isEmpty {
                        Button {
                            sidebarFilterText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.caption2)
                        }
                        .buttonStyle(.plain)
                    }
                    Button {
                        showSidebarSearchHelp.toggle()
                    } label: {
                        Image(systemName: "questionmark.circle")
                            .foregroundColor(.secondary)
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .help("Search syntax help")
                    .popover(isPresented: $showSidebarSearchHelp) {
                        SearchSyntaxHelpView(context: .spectrum)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.05))
                .cornerRadius(6)

                Picker("", selection: $sidebarSortMode) {
                    ForEach(SidebarSortMode.allCases) { mode in
                        Label(mode.label, systemImage: mode.icon).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 28)
                .help("Sort datasets")
            }

            if tabFilteredIndices.isEmpty {
                ContentUnavailableView {
                    Label(analysisSidebarTab == .all ? "No Spectra Loaded" : "No \(analysisSidebarTab.rawValue)",
                          systemImage: "waveform.path.ecg")
                        .font(.subheadline)
                } description: {
                    if analysisSidebarTab == .all {
                        Text("Import or load datasets to get started.")
                    } else {
                        Text("No loaded spectra match this category.")
                    }
                }
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if analysis.hdrsMode, !analysis.hdrsSpectrumTags.isEmpty, analysisSidebarTab == .all {
                            // Grouped view: sections by sample name (only in All tab)
                            let groups = analysis.hdrsSampleGroups(filterText: sidebarFilterText, sortMode: sidebarSortMode)
                            ForEach(groups.keys.sorted(), id: \.self) { sampleName in
                                DisclosureGroup(sampleName) {
                                    ForEach(groups[sampleName] ?? [], id: \.self) { index in
                                        spectrumRow(for: index)
                                    }
                                }
                                .font(.caption.bold())
                            }
                            // Ungrouped spectra
                            let ungrouped = analysis.hdrsUngroupedIndices(filterText: sidebarFilterText, sortMode: sidebarSortMode)
                            if !ungrouped.isEmpty {
                                DisclosureGroup("Unassigned") {
                                    ForEach(ungrouped, id: \.self) { index in
                                        spectrumRow(for: index)
                                    }
                                }
                                .font(.caption.bold())
                                .foregroundColor(.secondary)
                            }
                        } else {
                            ForEach(tabFilteredIndices, id: \.self) { index in
                                spectrumRow(for: index)
                            }
                        }
                        if showInvalidInline, analysisSidebarTab == .all {
                            ForEach(analysis.invalidItems) { item in
                                invalidSpectrumRow(item)
                            }
                        }
                    }
                }
            }

            if !analysis.invalidItems.isEmpty, !showInvalidInline, analysisSidebarTab == .all {
                Divider()
                invalidItemsPanel
            }
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .cornerRadius(16)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    var centerPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Spacer()

                    Menu {
                        Button {
                            shareDataPackage()
                        } label: {
                            Label("Send Data Package", systemImage: "shippingbox")
                        }

                        Button {
                            shareAnalysisScreenshot()
                        } label: {
                            Label("Send Chart Screenshot", systemImage: "camera")
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .help("Share analysis via Messages, AirDrop, etc.")
                    .buttonStyle(.glass)
                    .disabled(analysis.displayedSpectra.isEmpty)

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            expandChart.toggle()
                        }
                    } label: {
                        Image(systemName: expandChart ? "rectangle.arrowtriangle.2.inward" : "rectangle.arrowtriangle.2.outward")
                    }
                    .help(expandChart ? "Show Side Panels" : "Expand Chart")
                    .buttonStyle(.glass)
                }

                if let dashboardMetrics = analysis.dashboardMetrics {
                    dashboardPanel(dashboardMetrics)
                } else {
                    dashboardEmptyPanel
                }
                summaryStrip
                chartSection
                pointReadoutPanel
                overlayControls
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.visible)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .cornerRadius(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    var rightPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                pipelinePanel
                batchComparePanel
                inspectorPanel
                aiAnalysisSection
            }
            .padding(12)
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .cornerRadius(16)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    var invalidItemsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Invalid Items")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Button("View All") { showInvalidDetails = true }
                    #if os(macOS)
                    .buttonStyle(.link)
                    #else
                    .buttonStyle(.borderless)
                    #endif
            }

            let preview = Array(analysis.invalidItems.prefix(4))
            ForEach(preview) { item in
                let validation = SpectrumValidation.validate(x: item.spectrum.x, y: item.spectrum.y)
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .font(.caption)
                            .lineLimit(1)
                        Text(item.fileName)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(item.reason)
                            .font(.caption2)
                            .foregroundColor(.orange)
                        if let validation {
                            Text(validation.explanation)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("→ \(validation.suggestion)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .italic()
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 8)
                    tagChip("Invalid")
                }
                .padding(6)
                .background(Color.orange.opacity(0.08))
                .cornerRadius(8)
            }

            if analysis.invalidItems.count > preview.count {
                Text("\(analysis.invalidItems.count - preview.count) more…")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    var filteredSortedIndices: [Int] { analysis.filteredSortedIndices(filterText: sidebarFilterText, sortMode: sidebarSortMode) }

    /// Indices filtered by the active category tab then by text filter + sort.
    var tabFilteredIndices: [Int] {
        let base = filteredSortedIndices
        switch analysisSidebarTab {
        case .all:
            return base
        case .samples:
            return base.filter { index in
                spectrumRoleCategory(at: index) == nil
            }
        case .references:
            return base.filter { index in
                spectrumRoleCategory(at: index) == DatasetRole.reference.rawValue
            }
        case .prototypes:
            return base.filter { index in
                spectrumRoleCategory(at: index) == DatasetRole.prototype.rawValue
            }
        }
    }

    /// Returns the dataset role string for the spectrum at the given index,
    /// by looking up its `sourceDatasetID` in the searchable record cache.
    private func spectrumRoleCategory(at index: Int) -> String? {
        let spectra = displayedSpectra
        guard index >= 0, index < spectra.count else { return nil }
        guard let dsID = spectra[index].sourceDatasetID,
              let record = datasets.searchableRecordCache[dsID] else {
            return nil
        }
        return record.datasetRole
    }

    /// Tab label with count badge.
    func analysisSidebarTabLabel(_ tab: AnalysisSidebarTab) -> String {
        let base = filteredSortedIndices
        let count: Int
        switch tab {
        case .all: count = base.count
        case .samples: count = base.filter { spectrumRoleCategory(at: $0) == nil }.count
        case .references: count = base.filter { spectrumRoleCategory(at: $0) == DatasetRole.reference.rawValue }.count
        case .prototypes: count = base.filter { spectrumRoleCategory(at: $0) == DatasetRole.prototype.rawValue }.count
        }
        return "\(tab.rawValue) (\(count))"
    }

    var displayedSpectra: [ShimadzuSpectrum] { analysis.displayedSpectra }

    var exportPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                exportFormFields
                quickReportPanel

                spcHeaderPreviewPanel

                Text("Export Preview")
                    .font(.headline)
                chartSection
            }
            .padding(24)
        }
    }

}
