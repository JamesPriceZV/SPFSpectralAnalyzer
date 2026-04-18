import SwiftUI
import UniformTypeIdentifiers

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
        // Re-parse file picker — shown when a dataset has no stored source data
        .fileImporter(
            isPresented: $datasets.showReparseFilePicker,
            allowedContentTypes: [UTType(filenameExtension: "spc") ?? .data],
            allowsMultipleSelection: false
        ) { result in
            datasets.handleReparseFileImport(result: result, storedDatasets: storedDatasets)
        }
        .sheet(isPresented: $datasets.showPermanentDeleteSheet) {
            permanentDeleteSheet
        }
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
                    #if os(macOS)
                    Button("Add to Library") {
                        browseForSPCFiles()
                    }
                    .accessibilityIdentifier("browseFilesButton")
                    .buttonStyle(.glassProminent)
                    #else
                    Button("Add to Library") {
                        datasets.appendOnImport = false
                        datasets.showImporter = true
                    }
                    .accessibilityIdentifier("browseFilesButton")
                    .buttonStyle(.glassProminent)
                    #endif
                }

                ImportProgressDashboard(
                    progress: datasets.importProgress,
                    datasetCount: storedDatasets.count,
                    spectrumCount: analysis.spectra.count,
                    dropTargeted: dropTargeted
                )
                .contentShape(Rectangle())
                .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
                    let ds = datasets
                    Task { @MainActor in
                        var spcURLs: [URL] = []
                        for provider in providers {
                            guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else { continue }
                            if let url = await Self.extractFileURL(from: provider) {
                                if url.pathExtension.lowercased() == "spc" {
                                    spcURLs.append(url)
                                }
                            }
                        }
                        guard !spcURLs.isEmpty else { return }
                        await ds.loadSpectra(from: spcURLs, append: false)
                    }
                    return true
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            if !storedDatasets.isEmpty || !archivedDatasets.isEmpty {
                Divider()
                    .padding(.horizontal, 12)

                // MARK: Action buttons — conditional on active tab
                VStack(alignment: .leading, spacing: 6) {
                    if datasets.datasetTab == .archived {
                        HStack(alignment: .top, spacing: 16) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("ARCHIVE")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                ControlGroup {
                                    Button("Restore Selected") {
                                        datasets.restoreArchivedSelection(archivedDatasets: archivedDatasets)
                                    }
                                    .accessibilityIdentifier("restoreArchivedButton")
                                    .disabled(datasets.archivedDatasetSelection.isEmpty)
                                    .help("Restore selected archived datasets back to the active list.")

                                    Button("Delete Permanently") {
                                        datasets.requestPermanentDeleteSelection()
                                    }
                                    .accessibilityIdentifier("deleteArchivedButton")
                                    .disabled(datasets.archivedDatasetSelection.isEmpty)
                                    .help("Permanently delete selected archived datasets.")
                                }
                            }
                            Spacer()
                        }
                    } else {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("LOAD")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                ControlGroup {
                                    Button("Load") {
                                        datasets.loadStoredDatasetSelection(append: false, storedDatasets: storedDatasets)
                                    }
                                    .accessibilityIdentifier("loadSelectedButton")
                                    .help("Replace current spectra with the selected datasets.")

                                    Button("Append") {
                                        datasets.loadStoredDatasetSelection(append: true, storedDatasets: storedDatasets)
                                    }
                                    .accessibilityIdentifier("appendSelectedButton")
                                    .help("Add selected datasets to the current spectra without clearing.")
                                }
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                Text("VALIDATE")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                ControlGroup {
                                    Button("Headers") {
                                        datasets.validateStoredDatasetSelection(storedDatasets: storedDatasets)
                                    }
                                    .accessibilityIdentifier("validateHeadersButton")
                                    .help("Check SPC header consistency across selected stored datasets.")

                                    Button("Loaded") {
                                        datasets.validateLoadedSpectra(activeHeader: activeHeader)
                                    }
                                    .accessibilityIdentifier("validateLoadedButton")
                                    .help("Run validation checks on currently loaded spectra (empty data, non-finite values).")
                                }
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                Text("MANAGE")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                ControlGroup {
                                    Button("Archive") {
                                        datasets.deleteStoredDatasetSelection(storedDatasets: storedDatasets)
                                    }
                                    .accessibilityIdentifier("archiveSelectedButton")
                                    .disabled(datasets.selectedStoredDatasetIDs.isEmpty)
                                    .help("Move selected datasets to the archive. They can be restored later.")

                                    Button("Dedup") {
                                        datasets.prepareDuplicateCleanup(storedDatasets: storedDatasets, archivedDatasets: archivedDatasets)
                                    }
                                    .accessibilityIdentifier("removeDuplicatesButton")
                                    .help("Find and remove duplicate datasets based on content hashing.")
                                }
                            }

                            Spacer()
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Divider()
                    .padding(.horizontal, 12)

                // MARK: Dataset tabs + list — fills remaining space
                VStack(alignment: .leading, spacing: 8) {
                    // Tab picker with counts
                    let sampleCount = datasets.searchableRecordCache.values.filter {
                        $0.datasetRole != DatasetRole.reference.rawValue
                    }.count
                    let refCount = datasets.searchableRecordCache.values.filter {
                        $0.datasetRole == DatasetRole.reference.rawValue
                    }.count

                    Picker("", selection: $datasets.datasetTab) {
                        Text("Samples (\(sampleCount))").tag(DatasetTab.samples)
                        Text("References (\(refCount))").tag(DatasetTab.references)
                        Text("Archived (\(archivedDatasets.count))").tag(DatasetTab.archived)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)

                    // Search field
                    HStack(spacing: 6) {
                        ZStack(alignment: .trailing) {
                            TextField("Search", text: datasets.datasetTab == .archived
                                ? $datasets.archivedSearchText
                                : $datasets.datasetSearchText)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityIdentifier("datasetSearchField")
                            if !(datasets.datasetTab == .archived
                                 ? datasets.archivedSearchText
                                 : datasets.datasetSearchText).isEmpty {
                                Button {
                                    if datasets.datasetTab == .archived {
                                        datasets.archivedSearchText = ""
                                    } else {
                                        datasets.datasetSearchText = ""
                                    }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                        .font(.caption)
                                }
                                .buttonStyle(.plain)
                                .padding(.trailing, 6)
                            }
                        }
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

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            switch datasets.datasetTab {
                            case .samples:
                                let sampleIDs = storedDatasets
                                    .filter { datasets.searchableRecordCache[$0.id]?.datasetRole != DatasetRole.reference.rawValue }
                                    .map(\.id)
                                let filteredIDs = datasets.filteredDatasetIDs(from: sampleIDs)
                                ForEach(filteredIDs, id: \.self) { datasetID in
                                    storedDatasetRow(datasetID)
                                }
                            case .references:
                                let refIDs = storedDatasets
                                    .filter { datasets.searchableRecordCache[$0.id]?.datasetRole == DatasetRole.reference.rawValue }
                                    .map(\.id)
                                let filteredIDs = datasets.filteredDatasetIDs(from: refIDs)
                                ForEach(filteredIDs, id: \.self) { datasetID in
                                    storedDatasetRow(datasetID)
                                }
                            case .archived:
                                let archivedIDs = archivedDatasets.map(\.id)
                                let filteredIDs = datasets.filteredArchivedDatasetIDs(from: archivedIDs)
                                ForEach(filteredIDs, id: \.self) { datasetID in
                                    archivedDatasetRow(datasetID)
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                    }
                    // Force ScrollView re-creation when search text changes.
                    // LazyVStack can fail to re-evaluate @Observable property
                    // accesses inside ViewBuilder closures on some SwiftUI versions.
                    .id(datasets.datasetTab == .archived
                        ? datasets.archivedSearchText
                        : datasets.datasetSearchText)
                }
            }
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
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
                    .glassEffect(.regular, in: .rect(cornerRadius: 16))
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
                    .glassEffect(.regular, in: .rect(cornerRadius: 16))
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
                    .glassEffect(.regular, in: .rect(cornerRadius: 16))
                    .cornerRadius(12)
            }
            .padding(12)
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
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
                .buttonStyle(.glass)
            }

            if storedDatasets.isEmpty {
                Text("No stored datasets available. Import new spectra in the Import tab.")
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
                if !archivedDatasets.isEmpty {
                    Button("View Archived Datasets") {
                        datasets.showArchivedDatasetSheet = true
                    }
                    .buttonStyle(.glass)
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

                        // Group by role: Samples, References, Prototypes
                        let sampleIDs = filteredPickerIDs.filter { id in
                            let role = datasets.searchableRecordCache[id]?.datasetRole
                            return role == nil || (role != DatasetRole.reference.rawValue && role != DatasetRole.prototype.rawValue)
                        }
                        let referenceIDs = filteredPickerIDs.filter { id in
                            datasets.searchableRecordCache[id]?.datasetRole == DatasetRole.reference.rawValue
                        }
                        let prototypeIDs = filteredPickerIDs.filter { id in
                            datasets.searchableRecordCache[id]?.datasetRole == DatasetRole.prototype.rawValue
                        }

                        if !sampleIDs.isEmpty {
                            pickerSectionHeader("Samples", count: sampleIDs.count, color: .primary)
                            ForEach(sampleIDs, id: \.self) { datasetID in
                                storedDatasetPickerRow(datasetID)
                            }
                        }
                        if !referenceIDs.isEmpty {
                            pickerSectionHeader("References", count: referenceIDs.count, color: .blue)
                            ForEach(referenceIDs, id: \.self) { datasetID in
                                storedDatasetPickerRow(datasetID)
                            }
                        }
                        if !prototypeIDs.isEmpty {
                            pickerSectionHeader("Prototypes", count: prototypeIDs.count, color: .green)
                            ForEach(prototypeIDs, id: \.self) { datasetID in
                                storedDatasetPickerRow(datasetID)
                            }
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
                    .buttonStyle(.glassProminent)
                    .disabled(count == 0)

                    Button(count > 0 ? "Append Selected (\(count))" : "Append Selected") {
                        datasets.loadStoredDatasetPickerSelection(append: true, storedDatasets: storedDatasets)
                        datasets.showStoredDatasetPicker = false
                        datasets.storedDatasetPickerSelection.removeAll()
                    }
                    .buttonStyle(.glass)
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
                .buttonStyle(.glass)
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
                    .buttonStyle(.glassProminent)
                    .disabled(datasets.archivedDatasetSelection.isEmpty)

                    Button("Delete Permanently") {
                        datasets.requestPermanentDeleteSelection()
                    }
                    .buttonStyle(.glass)
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
                .buttonStyle(.glass)
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
        let irradiationOverride = record?.isPostIrradiation
        let instrumentLabel: String? = {
            guard let instID = record?.instrumentID else { return nil }
            return datasets.instrumentCache[instID]
        }()

        return VStack(alignment: .leading, spacing: 0) {
            // Main row — tappable for selection
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(displayName)
                            .font(.subheadline)
                            .lineLimit(1)
                        if record?.hasCameraPhoto ?? false {
                            Image(systemName: "camera.fill")
                                .font(.caption2)
                                .foregroundColor(.orange)
                        }
                        if storedDatasets.first(where: { $0.id == datasetID })?.spcKitEdited == true {
                            Text("SPC\u{270F}")
                                .font(.system(size: 7, weight: .bold, design: .rounded))
                                .padding(.horizontal, 3)
                                .padding(.vertical, 1)
                                .background(Color.blue.opacity(0.15))
                                .foregroundColor(.blue)
                                .cornerRadius(2)
                        }
                        if isRef {
                            Text("REF")
                                .font(.caption2.bold())
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.blue.opacity(0.2))
                                .foregroundColor(.blue)
                                .cornerRadius(3)
                            if let spf = spfValue {
                                Text("SPF \(Int(spf))")
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
                        if let isPost = irradiationOverride {
                            Text(isPost ? "POST" : "PRE")
                                .font(.caption2.bold())
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(isPost ? Color.red.opacity(0.2) : Color.green.opacity(0.2))
                                .foregroundColor(isPost ? .red : .green)
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
            .contentShape(Rectangle())
            .onTapGesture {
                if isSelected {
                    datasets.selectedStoredDatasetIDs.remove(datasetID)
                } else {
                    datasets.selectedStoredDatasetIDs.insert(datasetID)
                }
            }

            // Formula card link — separate from the selection tap area.
            // The .sheet is attached here (not in the global chain) to avoid
            // the macOS limitation where too many .sheet modifiers on a single
            // view causes later ones to silently fail.
            if isProt, let cardID = record?.formulaCardID {
                Button {
                    datasets.selectedFormulaCardID = cardID
                    datasets.showFormulaCardDetail = true
                } label: {
                    Label("Formula Card", systemImage: "doc.text")
                        .font(.caption2)
                }
                .buttonStyle(.borderless)
                .foregroundColor(.accentColor)
                .padding(.leading, 4)
                .padding(.top, 2)
                .sheet(isPresented: $datasets.showFormulaCardDetail) {
                    if let activeCardID = datasets.selectedFormulaCardID {
                        FormulaCardDetailView(
                            formulaCardID: activeCardID,
                            datasets: datasets,
                            storedDatasets: storedDatasets
                        )
                    }
                }
            }
        }
        .padding(8)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        .cornerRadius(10)
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
                datasets.pendingIrradiationOverride = record?.isPostIrradiation
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
            Menu {
                Button {
                    datasets.setIrradiationStatus(false, for: datasetID, storedDatasets: storedDatasets)
                } label: {
                    Label("Pre-Irradiation", systemImage: irradiationOverride == false ? "checkmark" : "sun.max")
                }
                Button {
                    datasets.setIrradiationStatus(true, for: datasetID, storedDatasets: storedDatasets)
                } label: {
                    Label("Post-Irradiation", systemImage: irradiationOverride == true ? "checkmark" : "sun.max.fill")
                }
                Divider()
                Button {
                    datasets.setIrradiationStatus(nil, for: datasetID, storedDatasets: storedDatasets)
                } label: {
                    Label("Auto-Detect from Filename", systemImage: "wand.and.stars")
                }
            } label: {
                Label("Irradiation Status", systemImage: "sun.max.trianglebadge.exclamationmark")
            }
            if hasRole {
                Divider()
                Button(role: .destructive) {
                    datasets.setDatasetRole(nil, knownInVivoSPF: nil, for: datasetID, storedDatasets: storedDatasets)
                } label: {
                    Label("Clear Role", systemImage: "xmark.circle")
                }
            }
            Divider()
            // SPCKit menu: Create, Edit, Duplicate
            Menu {
                Button {
                    spcLibraryBridge.createNewDataset()
                } label: {
                    Label("Create New Dataset…", systemImage: "plus.rectangle")
                }
                if let dataset = storedDatasets.first(where: { $0.id == datasetID }),
                   SPCLibraryBridge.canOpen(dataset) {
                    let selectedCount = datasets.selectedStoredDatasetIDs.count
                    if selectedCount >= 2, datasets.selectedStoredDatasetIDs.contains(datasetID) {
                        Button {
                            let selected = storedDatasets.filter { datasets.selectedStoredDatasetIDs.contains($0.id) }
                            Task { await spcLibraryBridge.combineDatasets(selected) }
                        } label: {
                            Label("Edit \(selectedCount) Combined…", systemImage: "arrow.triangle.merge")
                        }
                    } else {
                        Button {
                            Task { await spcLibraryBridge.openForEditing(dataset) }
                        } label: {
                            Label("Edit…", systemImage: "pencil.and.outline")
                        }
                    }
                    Button {
                        Task { await spcLibraryBridge.duplicateDataset(dataset) }
                    } label: {
                        Label("Duplicate…", systemImage: "doc.on.doc")
                    }
                }
            } label: {
                Label("SPCKit", systemImage: "waveform.and.magnifyingglass")
            }
            Divider()
            let isPartOfMultiSelection = datasets.selectedStoredDatasetIDs.contains(datasetID)
                && datasets.selectedStoredDatasetIDs.count > 1
            let affectedIDs: Set<UUID> = isPartOfMultiSelection
                ? datasets.selectedStoredDatasetIDs
                : [datasetID]
            let affectedCount = affectedIDs.count
            Button {
                datasets.selectedStoredDatasetIDs = affectedIDs
                datasets.deleteStoredDatasetSelection(storedDatasets: storedDatasets)
            } label: {
                Label(affectedCount > 1 ? "Archive \(affectedCount) Datasets" : "Archive",
                      systemImage: "archivebox")
            }
            Button {
                for id in affectedIDs {
                    analysis.unloadSpectra(forDatasetID: id)
                }
            } label: {
                Label(affectedCount > 1 ? "Unload \(affectedCount) from Analysis" : "Unload from Analysis",
                      systemImage: "arrow.uturn.up")
            }
            Button {
                datasets.reparseDatasets(Array(affectedIDs), storedDatasets: storedDatasets)
            } label: {
                Label(affectedCount > 1 ? "Re-parse \(affectedCount) from Source" : "Re-parse from Source",
                      systemImage: "arrow.triangle.2.circlepath")
            }
            Divider()
            Button(role: .destructive) {
                datasets.requestPermanentDeleteFromActive(ids: affectedIDs)
            } label: {
                Label(affectedCount > 1 ? "Delete \(affectedCount) Permanently" : "Delete Permanently",
                      systemImage: "trash")
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
        .contextMenu {
            let isPartOfMultiSelection = datasets.archivedDatasetSelection.contains(datasetID)
                && datasets.archivedDatasetSelection.count > 1
            let affectedIDs: Set<UUID> = isPartOfMultiSelection
                ? datasets.archivedDatasetSelection
                : [datasetID]
            let affectedCount = affectedIDs.count

            Button {
                datasets.archivedDatasetSelection = affectedIDs
                datasets.restoreArchivedSelection(archivedDatasets: archivedDatasets)
            } label: {
                Label(affectedCount > 1 ? "Unarchive \(affectedCount) Datasets" : "Unarchive",
                      systemImage: "tray.and.arrow.up")
            }
            Divider()
            // SPCKit menu: Edit, Duplicate
            Menu {
                if let dataset = archivedDatasets.first(where: { $0.id == datasetID }),
                   SPCLibraryBridge.canOpen(dataset) {
                    Button {
                        Task { await spcLibraryBridge.openForEditing(dataset) }
                    } label: {
                        Label("Edit…", systemImage: "pencil.and.outline")
                    }
                    Button {
                        Task { await spcLibraryBridge.duplicateDataset(dataset) }
                    } label: {
                        Label("Duplicate…", systemImage: "doc.on.doc")
                    }
                }
                Button {
                    spcLibraryBridge.createNewDataset()
                } label: {
                    Label("Create New Dataset…", systemImage: "plus.rectangle")
                }
            } label: {
                Label("SPCKit", systemImage: "waveform.and.magnifyingglass")
            }
            Divider()
            Button(role: .destructive) {
                datasets.pendingPermanentDeleteIDs = affectedIDs
                datasets.showPermanentDeleteSheet = true
            } label: {
                Label(affectedCount > 1 ? "Delete \(affectedCount) Permanently" : "Delete Permanently",
                      systemImage: "trash")
            }
        }
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
                                    Text("SPF \(Int(spf))")
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
        .contextMenu {
            Button {
                datasets.selectedStoredDatasetIDs = [datasetID]
                datasets.deleteStoredDatasetSelection(storedDatasets: storedDatasets)
            } label: {
                Label("Archive", systemImage: "archivebox")
            }
            Button {
                analysis.unloadSpectra(forDatasetID: datasetID)
            } label: {
                Label("Unload from Analysis", systemImage: "arrow.uturn.up")
            }
        }
    }

    private func pickerSectionHeader(_ title: String, count: Int, color: Color) -> some View {
        HStack(spacing: 6) {
            Text(title.uppercased())
                .font(.caption2.bold())
                .foregroundColor(color.opacity(0.8))
            Text("\(count)")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.secondary.opacity(0.12))
                .cornerRadius(3)
            Spacer()
        }
        .padding(.top, 8)
        .padding(.bottom, 2)
        .padding(.horizontal, 4)
    }

    // MARK: - Browse Files (NSOpenPanel fallback for macOS)

    #if os(macOS)
    /// Opens NSOpenPanel directly — more reliable than .fileImporter when
    /// the exported UTType (com.thermogalactic.spc) hasn't been registered
    /// yet by the system (e.g. first launch after project rename).
    private func browseForSPCFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [
            UTType(filenameExtension: "spc") ?? .data
        ]
        panel.title = "Select SPC Spectral Files"
        panel.message = "Choose one or more .spc files to import."

        guard panel.runModal() == .OK else { return }
        let urls = panel.urls
        guard !urls.isEmpty else { return }

        datasets.appendOnImport = false
        Task { @MainActor in
            await datasets.loadSpectra(from: urls, append: false)
        }
    }
    #endif

    // MARK: - Drop URL Extraction

    /// Extracts a file URL from an NSItemProvider, handling all possible
    /// return types (Data, NSURL, NSString) across macOS versions.
    @MainActor
    private static func extractFileURL(from provider: NSItemProvider) async -> URL? {
        // Modern approach: use loadTransferable if available
        // Fallback: loadItem with multiple type handling
        let identifier = UTType.fileURL.identifier
        guard let item = try? await provider.loadItem(forTypeIdentifier: identifier) else {
            return nil
        }

        // macOS may return any of these types for file URL drops
        if let url = item as? URL {
            return url
        }
        if let nsURL = item as? NSURL {
            return nsURL as URL
        }
        if let data = item as? Data,
           let path = String(data: data, encoding: .utf8)?
               .trimmingCharacters(in: .whitespacesAndNewlines) {
            // Percent-decode file:// URLs to handle paths with spaces
            if path.hasPrefix("file://") {
                if let url = URL(string: path) {
                    return url
                }
                // If URL(string:) fails (e.g. spaces not encoded), try stripping prefix
                let filePath = String(path.dropFirst("file://".count))
                    .removingPercentEncoding ?? String(path.dropFirst("file://".count))
                return URL(fileURLWithPath: filePath)
            }
            return URL(fileURLWithPath: path)
        }
        if let str = item as? String {
            let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("file://") {
                return URL(string: trimmed) ?? URL(fileURLWithPath: String(trimmed.dropFirst("file://".count)))
            }
            return URL(fileURLWithPath: trimmed)
        }
        return nil
    }

}
