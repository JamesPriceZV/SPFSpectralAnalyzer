import SwiftUI

extension ContentView {

    var analysisPanel: some View {
        platformHSplit {
            if !expandChart {
                if datasetSidebarCollapsed {
                    // Collapsed sidebar: just a narrow strip with expand button
                    VStack {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                datasetSidebarCollapsed = false
                            }
                        } label: {
                            Image(systemName: "sidebar.left")
                        }
                        .help("Show Datasets Sidebar")
                        .glassButtonStyle()
                        .padding(.top, 8)

                        Spacer()
                    }
                    .frame(width: 32)
                    .background(panelBackground)
                    .cornerRadius(16)
                } else {
                    leftPanel
                        .frame(minWidth: 240, idealWidth: 260, maxWidth: 320)
                }
            }

            centerPanel
                .frame(minWidth: 520, maxWidth: .infinity)

            if !expandChart {
                rightPanel
                    .frame(minWidth: 300, idealWidth: 320, maxWidth: 380)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(16)
    }

    var leftPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
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

                Button {
                    datasets.showStoredDatasetPicker = true
                } label: {
                    Image(systemName: "plus")
                }
                .help("Add stored spectra")
                .glassButtonStyle()
                .accessibilityIdentifier("addDatasetsButton")

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        datasetSidebarCollapsed = true
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                }
                .help("Collapse Datasets Sidebar")
                .glassButtonStyle()

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        expandChart.toggle()
                    }
                } label: {
                    Image(systemName: expandChart ? "rectangle.arrowtriangle.2.inward" : "rectangle.arrowtriangle.2.outward")
                }
                .help(expandChart ? "Show Side Panels" : "Expand Chart")
                .glassButtonStyle()
            }

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

            if displayedSpectra.isEmpty {
                Text("No spectra loaded")
                    .foregroundColor(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if analysis.hdrsMode, !analysis.hdrsSpectrumTags.isEmpty {
                            // Grouped view: sections by sample name
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
                            ForEach(filteredSortedIndices, id: \.self) { index in
                                spectrumRow(for: index)
                            }
                        }
                        if showInvalidInline {
                            ForEach(analysis.invalidItems) { item in
                                invalidSpectrumRow(item)
                            }
                        }
                    }
                }
            }

            if !analysis.invalidItems.isEmpty, !showInvalidInline {
                Divider()
                invalidItemsPanel
            }
        }
        .padding(12)
        .background(panelBackground)
        .cornerRadius(16)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    var centerPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Spacer()
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            expandChart.toggle()
                        }
                    } label: {
                        Image(systemName: expandChart ? "rectangle.arrowtriangle.2.inward" : "rectangle.arrowtriangle.2.outward")
                    }
                    .help(expandChart ? "Show Side Panels" : "Expand Chart")
                    .glassButtonStyle()
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
        .background(panelBackground)
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
        .background(panelBackground)
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
                    .buttonStyle(.link)
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
