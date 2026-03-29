#if os(iOS)
import SwiftUI
import SwiftData

/// Standalone iOS view for the Data Management tab.
/// Replaces the macOS-oriented `importPanel` ContentView extension on iPhone/iPad.
struct iOSDataManagementView: View {
    var analysis: AnalysisViewModel
    @Bindable var datasets: DatasetViewModel
    @Binding var appMode: AppMode

    @EnvironmentObject var dataStoreController: DataStoreController

    @Query(
        filter: #Predicate<StoredDataset> { !$0.isArchived },
        sort: \StoredDataset.importedAt,
        order: .reverse
    ) var storedDatasets: [StoredDataset]

    @Query(
        filter: #Predicate<StoredDataset> { $0.isArchived },
        sort: \StoredDataset.archivedAt,
        order: .reverse
    ) var archivedDatasets: [StoredDataset]

    @Query(sort: \StoredInstrument.createdAt, order: .reverse)
    var instruments: [StoredInstrument]

    @AppStorage("spfCalculationMethod") private var spfCalculationMethodRawValue = SPFCalculationMethod.colipa.rawValue

    @Environment(\.modelContext) var modelContext

    var body: some View {
        NavigationStack {
            List {
                // Import section
                Section {
                    Button {
                        datasets.appendOnImport = false
                        datasets.showImporter = true
                    } label: {
                        Label("Browse SPC Files", systemImage: "folder.badge.plus")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.borderedProminent)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }

                // Sync status
                if dataStoreController.cloudSyncEnabled {
                    Section {
                        HStack(spacing: 8) {
                            Image(systemName: "icloud.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                            Text("iCloud Sync Active")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Stored datasets — iterate over stable UUID values to avoid
                // SwiftData model faults when CloudKit sync deletes objects mid-render.
                if !storedDatasets.isEmpty {
                    let datasetIDs = storedDatasets.map(\.id)
                    let filteredIDs = datasets.filteredDatasetIDs(from: datasetIDs)
                    Section("Stored Datasets — \(storedDatasets.count)") {
                        ForEach(filteredIDs, id: \.self) { datasetID in
                            datasetRow(datasetID)
                        }
                    }
                } else if !archivedDatasets.isEmpty {
                    Section {
                        Button("View Archived Datasets") {
                            datasets.showArchivedDatasetSheet = true
                        }
                    }
                } else {
                    Section {
                        ContentUnavailableView(
                            "No Datasets",
                            systemImage: "doc.text.magnifyingglass",
                            description: Text("Import SPC files to get started.")
                        )
                        .listRowBackground(Color.clear)
                    }
                }

                // Validation log (if any)
                if !analysis.validationLogEntries.isEmpty {
                    Section("Validation Log") {
                        ForEach(analysis.validationLogEntries.prefix(10)) { entry in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.message)
                                    .font(.caption)
                                Text(DatasetViewModel.storedDateFormatter.string(from: entry.timestamp))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        if analysis.validationLogEntries.count > 10 {
                            Text("\(analysis.validationLogEntries.count - 10) more entries…")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Recent imports
                if !analysis.spectra.isEmpty {
                    Section("Loaded Spectra — \(analysis.spectra.count)") {
                        ForEach(Array(Array(analysis.spectra.prefix(12)).enumerated()), id: \.offset) { _, spectrum in
                            HStack {
                                Text(spectrum.name)
                                    .font(.subheadline)
                                    .lineLimit(1)
                                Spacer()
                                Text("\(spectrum.x.count) pts")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        if analysis.spectra.count > 12 {
                            Text("\(analysis.spectra.count - 12) more spectra…")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollDismissesKeyboard(.interactively)
            .searchable(text: $datasets.datasetSearchText, prompt: "Search datasets")
            .navigationTitle("Data Management")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    actionsMenu
                }
            }
        }
    }

    // MARK: - Actions Menu

    private var actionsMenu: some View {
        Menu {
            Section("Load") {
                Button {
                    datasets.loadStoredDatasetSelection(append: false, storedDatasets: storedDatasets)
                } label: {
                    Label("Load Selected", systemImage: "arrow.down.doc")
                }
                .disabled(datasets.selectedStoredDatasetIDs.isEmpty)

                Button {
                    datasets.loadStoredDatasetSelection(append: true, storedDatasets: storedDatasets)
                } label: {
                    Label("Append Selected", systemImage: "doc.badge.plus")
                }
                .disabled(datasets.selectedStoredDatasetIDs.isEmpty)
            }

            Section("Validate") {
                Button {
                    datasets.validateStoredDatasetSelection(storedDatasets: storedDatasets)
                } label: {
                    Label("Validate Headers", systemImage: "checkmark.shield")
                }

                Button {
                    datasets.validateLoadedSpectra(activeHeader: analysis.activeMetadata?.mainHeader)
                } label: {
                    Label("Validate Loaded", systemImage: "checkmark.circle")
                }
            }

            Section("Manage") {
                Button {
                    datasets.deleteStoredDatasetSelection(storedDatasets: storedDatasets)
                } label: {
                    Label("Archive Selected", systemImage: "archivebox")
                }
                .disabled(datasets.selectedStoredDatasetIDs.isEmpty)

                Button {
                    datasets.prepareDuplicateCleanup(storedDatasets: storedDatasets, archivedDatasets: archivedDatasets)
                } label: {
                    Label("Remove Duplicates", systemImage: "minus.circle")
                }

                Button {
                    datasets.showArchivedDatasetSheet = true
                } label: {
                    Label("View Archived", systemImage: "archivebox.fill")
                }
            }
        } label: {
            Label("Actions", systemImage: "ellipsis.circle")
        }
    }

    // MARK: - Dataset Row

    private func datasetRow(_ datasetID: UUID) -> some View {
        let record = datasets.searchableRecordCache[datasetID]
        let isSelected = datasets.selectedStoredDatasetIDs.contains(datasetID)
        let spectrumCount = record?.spectrumCount ?? 0
        let dataSetCount = record?.dataSetNames.count ?? 0
        let detail = dataSetCount > 0
            ? "\(spectrumCount) spectra \u{2022} \(dataSetCount) datasets"
            : "\(spectrumCount) spectra"
        let dateLabel = DatasetViewModel.storedDateFormatter.string(from: record?.importedAt ?? Date())
        let displayName = record?.fileName ?? datasetID.uuidString
        let isRef = record?.isReference ?? false
        let isProt = record?.isPrototype ?? false
        let spfValue = record?.knownInVivoSPF
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
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(displayName)
                            .font(.subheadline)
                            .lineLimit(3)
                            .foregroundColor(.primary)

                        if isRef {
                            Text("REF")
                                .font(.caption2.bold())
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.2))
                                .foregroundColor(.blue)
                                .cornerRadius(4)
                            if let spf = spfValue {
                                Text("SPF \(spf, specifier: "%.0f")")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.purple.opacity(0.2))
                                    .foregroundColor(.purple)
                                    .cornerRadius(4)
                            }
                        } else if isProt {
                            Text("SAMPLE")
                                .font(.caption2.bold())
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.2))
                                .foregroundColor(.green)
                                .cornerRadius(4)
                        }
                    }

                    HStack(spacing: 8) {
                        Text(detail)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if let inst = instrumentLabel {
                            Text(inst)
                                .font(.caption2)
                                .foregroundColor(.orange)
                        }
                    }

                    // ISO 24443 metadata for reference datasets
                    if isRef {
                        let pt = record?.plateType
                        let mg = record?.applicationQuantityMg
                        let ft = record?.formulationType
                        let hasMetadata = (pt != nil && !pt!.isEmpty) || mg != nil || (ft != nil && ft != FormulationType.unknown.rawValue)
                        if hasMetadata {
                            HStack(spacing: 4) {
                                if let pt, !pt.isEmpty {
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
                                if let mg {
                                    Text(String(format: "%.1f mg", mg))
                                        .font(.caption2)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Color.cyan.opacity(0.15))
                                        .foregroundColor(.cyan)
                                        .cornerRadius(3)
                                }
                                if let ft, ft != FormulationType.unknown.rawValue {
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

                    Text(dateLabel)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer()
            }
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                datasets.selectedStoredDatasetIDs = [datasetID]
                datasets.deleteStoredDatasetSelection(storedDatasets: storedDatasets)
            } label: {
                Label("Archive", systemImage: "archivebox")
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                datasets.selectedStoredDatasetIDs = [datasetID]
                datasets.loadStoredDatasetSelection(append: false, storedDatasets: storedDatasets)
                appMode = .analyze
            } label: {
                Label("Load", systemImage: "arrow.down.doc")
            }
            .tint(.blue)
        }
        .contextMenu {
            Section("Load") {
                Button {
                    datasets.selectedStoredDatasetIDs = [datasetID]
                    datasets.loadStoredDatasetSelection(append: false, storedDatasets: storedDatasets)
                    appMode = .analyze
                } label: {
                    Label("Load & Analyze", systemImage: "arrow.down.doc")
                }

                Button {
                    datasets.selectedStoredDatasetIDs = [datasetID]
                    datasets.loadStoredDatasetSelection(append: true, storedDatasets: storedDatasets)
                } label: {
                    Label("Append to Loaded", systemImage: "doc.badge.plus")
                }
            }
            Button {
                datasets.pendingRoleDatasetID = datasetID
                datasets.pendingKnownSPF = spfValue ?? 30.0
                datasets.pendingPlateType = SubstratePlateType(rawValue: record?.plateType ?? "") ?? .pmma
                datasets.pendingApplicationQuantityMg = record?.applicationQuantityMg
                datasets.pendingFormulationType = FormulationType(rawValue: record?.formulationType ?? "") ?? .unknown
                datasets.pendingPMMASubtype = PMMAPlateSubtype(rawValue: record?.pmmaPlateSubtype ?? "") ?? .moulded
                datasets.showReferenceSpfSheet = true
            } label: {
                Label("Set as Reference (Known SPF)", systemImage: "checkmark.seal.fill")
            }

            Button {
                let isHDRS = (SPFCalculationMethod(rawValue: spfCalculationMethodRawValue) ?? .colipa) == .iso23675
                if isHDRS {
                    datasets.pendingRoleDatasetID = datasetID
                    datasets.pendingHDRSPlateType = .moulded
                    datasets.showSamplePlateTypeSheet = true
                } else {
                    datasets.setDatasetRole(.prototype, knownInVivoSPF: nil, for: datasetID, storedDatasets: storedDatasets)
                }
            } label: {
                Label("Set as Prototype Sample", systemImage: "flask.fill")
            }

            if record?.datasetRole != nil {
                Divider()
                Button(role: .destructive) {
                    datasets.setDatasetRole(nil, knownInVivoSPF: nil, for: datasetID, storedDatasets: storedDatasets)
                } label: {
                    Label("Clear Role", systemImage: "xmark.circle")
                }
            }
        }
    }
}
#endif
