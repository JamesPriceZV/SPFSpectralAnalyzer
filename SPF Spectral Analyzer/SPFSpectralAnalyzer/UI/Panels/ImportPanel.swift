import SwiftUI

extension ContentView {

    var importPanel: some View {
        platformHSplit {
            // MARK: Left Pane — Import & Stored Datasets
            importPanelLeftPane
                #if os(macOS)
                .frame(minWidth: 420, idealWidth: 520, maxWidth: 680)
                #else
                .frame(maxWidth: .infinity)
                #endif

            // MARK: Right Pane — Validation Log & Recent Imports
            importPanelRightPane
                #if os(macOS)
                .frame(minWidth: 280, maxWidth: .infinity)
                #else
                .frame(maxWidth: .infinity)
                #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(16)
    }

    private var importPanelLeftPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            // MARK: Fixed header — Import + Browse + Drop zone
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Import SPC Files")
                        .font(.title3)
                        .bold()
                    Spacer()
                    Button("Browse Files") {
                        datasets.appendOnImport = false
                        datasets.showImporter = true
                    }
                    .accessibilityIdentifier("browseFilesButton")
                    .glassButtonStyle(isProminent: true)
                }

                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6, 6]))
                    .foregroundColor(.secondary.opacity(0.4))
                    .frame(height: 72)
                    .overlay(
                        HStack(spacing: 10) {
                            Image(systemName: "waveform.path.ecg")
                                .font(.system(size: 22))
                                .foregroundColor(.secondary)
                            Text("Drop .spc files here or use Browse")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    )
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            if !storedDatasets.isEmpty {
                Divider()
                    .padding(.horizontal, 12)

                // MARK: Action buttons — pinned above dataset list
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Button("Load Selected") {
                            datasets.loadStoredDatasetSelection(append: false, storedDatasets: storedDatasets)
                        }
                        .accessibilityIdentifier("loadSelectedButton")
                        .glassButtonStyle(isProminent: true)
                        .help("Replace current spectra with the selected datasets.")

                        Button("Append Selected") {
                            datasets.loadStoredDatasetSelection(append: true, storedDatasets: storedDatasets)
                        }
                        .accessibilityIdentifier("appendSelectedButton")
                        .glassButtonStyle()
                        .help("Add selected datasets to the current spectra without clearing.")

                        Spacer()

                        Button("Validate Headers") {
                            datasets.validateStoredDatasetSelection(storedDatasets: storedDatasets)
                        }
                        .accessibilityIdentifier("validateHeadersButton")
                        .glassButtonStyle()
                        .help("Check SPC header consistency across selected stored datasets.")

                        Button("Validate Loaded") {
                            datasets.validateLoadedSpectra(activeHeader: activeHeader)
                        }
                        .accessibilityIdentifier("validateLoadedButton")
                        .glassButtonStyle()
                        .help("Run validation checks on currently loaded spectra (empty data, non-finite values).")
                    }

                    HStack(spacing: 8) {
                        Button("Archive Selected") {
                            datasets.deleteStoredDatasetSelection(storedDatasets: storedDatasets)
                        }
                        .accessibilityIdentifier("archiveSelectedButton")
                        .glassButtonStyle()
                        .disabled(datasets.selectedStoredDatasetIDs.isEmpty)
                        .help("Move selected datasets to the archive. They can be restored later.")

                        Button("Remove Duplicates") {
                            datasets.prepareDuplicateCleanup(storedDatasets: storedDatasets, archivedDatasets: archivedDatasets)
                        }
                        .accessibilityIdentifier("removeDuplicatesButton")
                        .glassButtonStyle()
                        .help("Find and remove duplicate datasets based on content hashing.")

                        Button("Archived\u{2026}") {
                            datasets.showArchivedDatasetSheet = true
                        }
                        .accessibilityIdentifier("archivedDatasetsButton")
                        .glassButtonStyle()
                        .help("View and restore previously archived datasets.")

                        Spacer()
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Divider()
                    .padding(.horizontal, 12)

                // MARK: Dataset list — fills remaining space
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text("Stored Datasets: \(storedDatasets.count)")
                            .font(.headline)
                        Spacer()
                        TextField("Search", text: $datasets.datasetSearchText)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 200)
                            .accessibilityIdentifier("datasetSearchField")
                        Button {
                            datasets.showDatasetSearchHelp.toggle()
                        } label: {
                            Image(systemName: "questionmark.circle")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .help("Search syntax help")
                        .popover(isPresented: $datasets.showDatasetSearchHelp) {
                            SearchSyntaxHelpView(context: .dataset)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            let datasetIDs = storedDatasets.map(\.id)
                            let filteredIDs = datasets.filteredDatasetIDs(from: datasetIDs)
                            ForEach(filteredIDs, id: \.self) { datasetID in
                                storedDatasetRow(datasetID)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                    }
                }
            } else if !archivedDatasets.isEmpty {
                Button("View Archived Datasets") {
                    datasets.showArchivedDatasetSheet = true
                }
                .glassButtonStyle()
                .padding(12)
            }
        }
        .background(panelBackground)
        .cornerRadius(16)
    }

    private var importPanelRightPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !analysis.validationLogEntries.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Validation Log")
                                .font(.headline)
                            Spacer()
                            Button("Copy") {
                                copyValidationLog()
                            }
                            #if os(macOS)
                            .buttonStyle(.link)
                            #else
                            .buttonStyle(.borderless)
                            #endif
                            Button("Save Log…") {
                                saveValidationLogToFile()
                            }
                            #if os(macOS)
                            .buttonStyle(.link)
                            #else
                            .buttonStyle(.borderless)
                            #endif
                            Button("Clear") {
                                analysis.validationLogEntries.removeAll()
                            }
                            #if os(macOS)
                            .buttonStyle(.link)
                            #else
                            .buttonStyle(.borderless)
                            #endif
                        }

                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 6) {
                                ForEach(analysis.validationLogEntries) { entry in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(formattedTimestamp(entry.timestamp))
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        Text(entry.message)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(minHeight: 80, maxHeight: 200)
                    }
                    .padding(12)
                    .background(panelBackground)
                    .cornerRadius(12)
                }

                if !analysis.spectra.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recent Imports")
                            .font(.headline)
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(displayedSpectra.prefix(12).enumerated()), id: \.offset) { index, _ in
                                spectrumRow(for: index)
                            }
                        }
                    }
                    .padding(12)
                    .background(panelBackground)
                    .cornerRadius(12)
                }

                if analysis.validationLogEntries.isEmpty && analysis.spectra.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 36))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("Validation results and recent imports will appear here.")
                            .font(.callout)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                }

                // MARK: Instrument Registry
                InstrumentRegistryView()
                    .padding(12)
                    .background(panelBackground)
                    .cornerRadius(12)
            }
            .padding(12)
        }
        .background(panelBackground)
        .cornerRadius(16)
    }

    var storedDatasetPickerSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Add Stored Dataset")
                    .font(.title3)
                    .bold()
                Spacer()
                Button("Close") {
                    datasets.showStoredDatasetPicker = false
                    datasets.storedDatasetPickerSelection.removeAll()
                }
                .glassButtonStyle()
            }

            if storedDatasets.isEmpty {
                Text("No stored datasets available. Import new spectra in the Import tab.")
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
                if !archivedDatasets.isEmpty {
                    Button("View Archived Datasets") {
                        datasets.showArchivedDatasetSheet = true
                    }
                    .glassButtonStyle()
                    .padding(.top, 8)
                }
            } else {
                HStack(spacing: 6) {
                    TextField("Search stored datasets", text: $datasets.datasetSearchText)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        datasets.showDatasetSearchHelp.toggle()
                    } label: {
                        Image(systemName: "questionmark.circle")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .help("Search syntax help")
                    .popover(isPresented: $datasets.showDatasetSearchHelp) {
                        SearchSyntaxHelpView(context: .dataset)
                    }
                }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        let pickerIDs = storedDatasets.map(\.id)
                        let filteredPickerIDs = datasets.filteredDatasetIDs(from: pickerIDs)
                        ForEach(filteredPickerIDs, id: \.self) { datasetID in
                            storedDatasetPickerRow(datasetID)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(minHeight: 240)

                HStack(spacing: 12) {
                    let count = datasets.storedDatasetPickerSelection.count
                    Button(count > 0 ? "Load Selected (\(count))" : "Load Selected") {
                        datasets.loadStoredDatasetPickerSelection(append: false, storedDatasets: storedDatasets)
                        datasets.showStoredDatasetPicker = false
                        datasets.storedDatasetPickerSelection.removeAll()
                    }
                    .glassButtonStyle(isProminent: true)
                    .disabled(count == 0)

                    Button(count > 0 ? "Append Selected (\(count))" : "Append Selected") {
                        datasets.loadStoredDatasetPickerSelection(append: true, storedDatasets: storedDatasets)
                        datasets.showStoredDatasetPicker = false
                        datasets.storedDatasetPickerSelection.removeAll()
                    }
                    .glassButtonStyle()
                    .disabled(count == 0)
                }
            }
        }
        .padding(24)
        .frame(minWidth: 720, idealWidth: 800, maxWidth: 1200,
               minHeight: 420, idealHeight: 600, maxHeight: 900)
    }

    var archivedDatasetSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Archived Datasets")
                    .font(.title3)
                    .bold()
                Spacer()
                Button("Close") {
                    datasets.showArchivedDatasetSheet = false
                    datasets.archivedDatasetSelection.removeAll()
                }
                .glassButtonStyle()
            }

            if archivedDatasets.isEmpty {
                Text("No archived datasets available.")
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
            } else {
                HStack(spacing: 6) {
                    TextField("Search archived datasets", text: $datasets.archivedSearchText)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        datasets.showArchivedSearchHelp.toggle()
                    } label: {
                        Image(systemName: "questionmark.circle")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .help("Search syntax help")
                    .popover(isPresented: $datasets.showArchivedSearchHelp) {
                        SearchSyntaxHelpView(context: .dataset)
                    }
                }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        let archivedIDs = archivedDatasets.map(\.id)
                        let filteredArchivedIDs = datasets.filteredArchivedDatasetIDs(from: archivedIDs)
                        ForEach(filteredArchivedIDs, id: \.self) { datasetID in
                            archivedDatasetRow(datasetID)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(minHeight: 240)

                HStack(spacing: 12) {
                    Button("Restore Selected") {
                        datasets.restoreArchivedSelection(archivedDatasets: archivedDatasets)
                    }
                    .glassButtonStyle(isProminent: true)
                    .disabled(datasets.archivedDatasetSelection.isEmpty)

                    Button("Delete Permanently") {
                        datasets.requestPermanentDeleteSelection()
                    }
                    .glassButtonStyle()
                    .disabled(datasets.archivedDatasetSelection.isEmpty)
                }
            }
        }
        .padding(24)
        .frame(minWidth: 720, minHeight: 420)
        .sheet(isPresented: $datasets.showPermanentDeleteSheet) {
            permanentDeleteSheet
        }
    }

    var permanentDeleteSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(datasets.permanentDeleteConfirmationTitle(archivedDatasets: archivedDatasets))
                .font(.title3)
                .bold()
            Text(datasets.permanentDeleteConfirmationMessage(archivedDatasets: archivedDatasets))
                .foregroundColor(.secondary)
            HStack {
                Button("Cancel") {
                    datasets.showPermanentDeleteSheet = false
                    datasets.pendingPermanentDeleteIDs.removeAll()
                }
                .glassButtonStyle()
                Spacer()
                Button("Delete Permanently") {
                    datasets.showPermanentDeleteSheet = false
                    datasets.deleteArchivedDatasets(archivedDatasets: archivedDatasets)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
        .padding(24)
        .frame(minWidth: 420)
    }

    func storedDatasetRow(_ datasetID: UUID) -> some View {
        // Read all display data from the snapshot cache to avoid touching SwiftData
        // model properties, which can be invalidated by CloudKit sync mid-render.
        let record = datasets.searchableRecordCache[datasetID]
        let isSelected = datasets.selectedStoredDatasetIDs.contains(datasetID)
        let spectrumCount = record?.spectrumCount ?? 0
        let dataSetCount = record?.dataSetNames.count ?? 0
        let detail = dataSetCount > 0
            ? "\(spectrumCount) spectra • \(dataSetCount) datasets"
            : "\(spectrumCount) spectra"
        let dateLabel = DatasetViewModel.storedDateFormatter.string(from: record?.importedAt ?? Date())
        let displayName = record?.fileName ?? datasetID.uuidString
        let isRef = record?.isReference ?? false
        let isProt = record?.isPrototype ?? false
        let spfValue = record?.knownInVivoSPF
        let hasRole = record?.datasetRole != nil
        let instrumentLabel: String? = {
            guard let instID = record?.instrumentID else { return nil }
            return datasets.instrumentCache[instID]
        }()

        return Button {
            if isSelected {
                datasets.selectedStoredDatasetIDs.remove(datasetID)
            } else {
                datasets.selectedStoredDatasetIDs.insert(datasetID)
            }
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(displayName)
                            .font(.subheadline)
                            .lineLimit(1)
                        if isRef {
                            Text("REF")
                                .font(.caption2.bold())
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.blue.opacity(0.2))
                                .foregroundColor(.blue)
                                .cornerRadius(3)
                            if let spf = spfValue {
                                Text("SPF \(spf, specifier: "%.0f")")
                                    .font(.caption2)
                                    .foregroundColor(.blue)
                            }
                        } else if isProt {
                            Text("PROTOTYPE")
                                .font(.caption2.bold())
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.green.opacity(0.2))
                                .foregroundColor(.green)
                                .cornerRadius(3)
                        }
                    }
                    Text(detail)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(dateLabel)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    if let instLabel = instrumentLabel {
                        HStack(spacing: 3) {
                            Image(systemName: "cpu")
                                .font(.caption2)
                            Text(instLabel)
                                .font(.caption2)
                        }
                        .foregroundColor(.teal)
                    }
                    // Formula card link for prototype samples
                    if isProt, let cardID = record?.formulaCardID {
                        Button {
                            datasets.selectedFormulaCardID = cardID
                            datasets.showFormulaCardDetail = true
                        } label: {
                            Label("Formula Card", systemImage: "doc.text")
                                .font(.caption2)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.accentColor)
                    }
                    // ISO 24443 metadata for reference/prototype datasets
                    if isRef || isProt {
                        HStack(spacing: 4) {
                            if let pt = record?.plateType, !pt.isEmpty {
                                let plateLabel: String = {
                                    guard let type = SubstratePlateType(rawValue: pt) else { return pt }
                                    if type == .pmma, let sub = record?.pmmaPlateSubtype,
                                       let subtype = PMMAPlateSubtype(rawValue: sub) {
                                        return "PMMA \(subtype == .moulded ? "HD6" : "SB6")"
                                    }
                                    return type.label
                                }()
                                Text(plateLabel)
                                    .font(.caption2)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.orange.opacity(0.15))
                                    .foregroundColor(.orange)
                                    .cornerRadius(3)
                            }
                            if let mg = record?.applicationQuantityMg {
                                Text(String(format: "%.1f mg", mg))
                                    .font(.caption2)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.cyan.opacity(0.15))
                                    .foregroundColor(.cyan)
                                    .cornerRadius(3)
                            }
                            if let ft = record?.formulationType, ft != FormulationType.unknown.rawValue {
                                Text(FormulationType(rawValue: ft)?.label ?? ft)
                                    .font(.caption2)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.purple.opacity(0.15))
                                    .foregroundColor(.purple)
                                    .cornerRadius(3)
                            }
                        }
                    }
                }
                Spacer(minLength: 8)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
                }
            }
            .padding(8)
            .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                datasets.pendingRoleDatasetID = datasetID
                datasets.pendingKnownSPF = spfValue ?? 30.0
                datasets.pendingPlateType = SubstratePlateType(rawValue: record?.plateType ?? "") ?? .pmma
                datasets.pendingApplicationQuantityMg = record?.applicationQuantityMg
                datasets.pendingFormulationType = FormulationType(rawValue: record?.formulationType ?? "") ?? .unknown
                datasets.pendingPMMASubtype = PMMAPlateSubtype(rawValue: record?.pmmaPlateSubtype ?? "") ?? .moulded
                datasets.showReferenceSpfSheet = true
            } label: {
                Label("Set as Reference...", systemImage: "star.fill")
            }
            Button {
                datasets.pendingRoleDatasetID = datasetID
                datasets.pendingPlateType = SubstratePlateType(rawValue: record?.plateType ?? "") ?? .pmma
                datasets.pendingApplicationQuantityMg = record?.applicationQuantityMg
                datasets.pendingFormulationType = FormulationType(rawValue: record?.formulationType ?? "") ?? .unknown
                datasets.pendingPMMASubtype = PMMAPlateSubtype(rawValue: record?.pmmaPlateSubtype ?? "") ?? .moulded
                datasets.pendingHDRSPlateType = .moulded
                datasets.pendingFormulaCardID = record?.formulaCardID
                datasets.showSamplePlateTypeSheet = true
            } label: {
                Label("Set as Prototype Sample...", systemImage: "flask.fill")
            }
            Divider()
            Button {
                datasets.pendingInstrumentAssignDatasetID = datasetID
                datasets.showAssignInstrumentSheet = true
            } label: {
                Label("Assign Instrument...", systemImage: "cpu")
            }
            if hasRole {
                Divider()
                Button(role: .destructive) {
                    datasets.setDatasetRole(nil, knownInVivoSPF: nil, for: datasetID, storedDatasets: storedDatasets)
                } label: {
                    Label("Clear Role", systemImage: "xmark.circle")
                }
            }
        }
    }

    func archivedDatasetRow(_ datasetID: UUID) -> some View {
        // Read all display data from the snapshot cache to avoid touching SwiftData
        // model properties, which can be invalidated by CloudKit sync mid-render.
        let record = datasets.archivedSearchableRecordCache[datasetID]
        let isSelected = datasets.archivedDatasetSelection.contains(datasetID)
        let spectrumCount = record?.spectrumCount ?? 0
        let dataSetCount = record?.dataSetNames.count ?? 0
        let detail = dataSetCount > 0
            ? "\(spectrumCount) spectra • \(dataSetCount) datasets"
            : "\(spectrumCount) spectra"
        let archivedLabel = record?.archivedAt.map { DatasetViewModel.storedDateFormatter.string(from: $0) } ?? "Unknown"
        let displayName = record?.fileName ?? datasetID.uuidString

        return Button {
            if isSelected {
                datasets.archivedDatasetSelection.remove(datasetID)
            } else {
                datasets.archivedDatasetSelection.insert(datasetID)
            }
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName)
                        .font(.subheadline)
                        .lineLimit(1)
                    Text(detail)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Archived \(archivedLabel)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer(minLength: 8)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
                }
            }
            .padding(8)
            .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }

    func storedDatasetPickerRow(_ datasetID: UUID) -> some View {
        // Read display data from cache to avoid touching SwiftData model properties.
        let record = datasets.searchableRecordCache[datasetID]
        let isSelected = datasets.storedDatasetPickerSelection.contains(datasetID)
        let spectrumCount = record?.spectrumCount ?? 0
        let dataSetCount = record?.dataSetNames.count ?? 0
        let displayName = record?.fileName ?? datasetID.uuidString
        let isRef = record?.isReference ?? false
        let isProt = record?.isPrototype ?? false
        let spfValue = record?.knownInVivoSPF

        // Build summary lines from cache — NO model access during rendering.
        let cacheSummaryLines: [String] = {
            guard let r = record else { return ["Metadata: unavailable"] }
            var lines: [String] = []
            if let instrument = r.sourceInstrumentText, !instrument.isEmpty {
                lines.append("Instrument: \(instrument)")
            }
            if let memo = r.memo, !memo.isEmpty {
                lines.append("Memo: \(memo)")
            }
            let dsPreview = r.dataSetNames.prefix(3).joined(separator: ", ")
            if !dsPreview.isEmpty {
                let extra = max(0, r.dataSetNames.count - 3)
                lines.append("Datasets: \(dsPreview)\(extra > 0 ? " +\(extra) more" : "")")
            }
            return lines.isEmpty ? ["Metadata: unavailable"] : lines
        }()

        return HStack(spacing: 10) {
            Button {
                if isSelected {
                    datasets.storedDatasetPickerSelection.remove(datasetID)
                } else {
                    datasets.storedDatasetPickerSelection.insert(datasetID)
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(isSelected ? .accentColor : .secondary)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Text(displayName)
                                .font(.subheadline)
                                .lineLimit(1)
                            if isRef {
                                Text("REF")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.blue.opacity(0.2))
                                    .foregroundColor(.blue)
                                    .cornerRadius(3)
                                if let spf = spfValue {
                                    Text("SPF \(spf, specifier: "%.0f")")
                                        .font(.caption2)
                                        .foregroundColor(.blue)
                                }
                            } else if isProt {
                                Text("PROTOTYPE")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.green.opacity(0.2))
                                    .foregroundColor(.green)
                                    .cornerRadius(3)
                            }
                        }
                        Text("\(spectrumCount) spectra • \(dataSetCount) datasets")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        ForEach(cacheSummaryLines, id: \.self) { line in
                            Text(line)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 8)

            Button("Show Details") {
                datasets.datasetDetailPopoverID = datasetID
            }
            #if os(macOS)
            .buttonStyle(.link)
            #else
            .buttonStyle(.borderless)
            #endif
            .popover(isPresented: Binding(
                get: { datasets.datasetDetailPopoverID == datasetID },
                set: { isPresented in
                    if !isPresented { datasets.datasetDetailPopoverID = nil }
                }
            )) {
                // Decode metadata on-demand only when the popover is opened.
                // Look up the model object by ID — safe here since it's user-initiated.
                let metadata: ShimadzuSPCMetadata? = {
                    guard let ds = storedDatasets.first(where: { $0.id == datasetID }) else { return nil }
                    return datasets.decodedMetadata(for: ds)
                }()
                let metadataLines = metadataDetailLines(metadata)
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Metadata Details")
                            .font(.headline)
                        ForEach(metadataLines, id: \.self) { line in
                            Text(line)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(16)
                }
                .frame(minWidth: 420, minHeight: 320)
            }
        }
        .padding(10)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.white.opacity(0.03))
        .cornerRadius(10)
    }

}
