// SPCEditorSheet.swift
// PhysicAI
//
// Full-featured SPC editor presented as a sheet from the Library.
// Wraps SPCKit's SPCDocumentStore + views inside a NavigationSplitView.

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SPCEditorSheet: View {

    @Bindable var bridge: SPCLibraryBridge
    var storedDatasets: [StoredDataset] = []
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var showFileImporter = false
    @State private var showLibraryPicker = false
    #if os(iOS)
    @State private var showDataTable = false
    #else
    @State private var showDataTable = true
    #endif

    var body: some View {
        Group {
            if let store = bridge.activeStore {
                editorContent(store: store)
            } else {
                loadingView
            }
        }
        .sheet(isPresented: Binding(
            get: { bridge.activeStore?.showExportFormatPicker ?? false },
            set: { bridge.activeStore?.showExportFormatPicker = $0 }
        )) {
            if let store = bridge.activeStore {
                SPCLibraryExportView(store: store)
            }
        }
        .sheet(isPresented: Binding(
            get: { bridge.activeStore?.showTransformPanel ?? false },
            set: { bridge.activeStore?.showTransformPanel = $0 }
        )) {
            if let store = bridge.activeStore {
                TransformPanel(store: store)
                    .presentationDetents([.medium, .large])
            }
        }
        .sheet(isPresented: Binding(
            get: { bridge.activeStore?.showMetadataEditor ?? false },
            set: { bridge.activeStore?.showMetadataEditor = $0 }
        )) {
            if let store = bridge.activeStore {
                MetadataEditorView(store: store)
                    .presentationDetents([.medium, .large])
            }
        }
        .fileExporter(
            isPresented: Binding(
                get: { bridge.activeStore?.isExporting ?? false },
                set: { bridge.activeStore?.isExporting = $0 }
            ),
            document: bridge.activeStore?.exportDocument,
            contentType: .spcFile,
            defaultFilename: bridge.activeStore?.exportFilename ?? "spectrum.spc"
        ) { result in
            handleExportResult(result)
        }
        .alert("Error", isPresented: Binding(
            get: { bridge.presentedError != nil },
            set: { if !$0 { bridge.presentedError = nil } }
        )) {
            Button("OK", role: .cancel) { bridge.presentedError = nil }
        } message: {
            Text(bridge.presentedError ?? "")
        }
        .alert("Error", isPresented: Binding(
            get: { bridge.activeStore?.presentedError != nil },
            set: { if !$0 { bridge.activeStore?.presentedError = nil } }
        )) {
            Button("OK", role: .cancel) { bridge.activeStore?.presentedError = nil }
        } message: {
            Text(bridge.activeStore?.presentedError?.message ?? "")
        }
        // Import SPC file from disk
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.spcFile, .data],
            allowsMultipleSelection: true
        ) { result in
            guard let store = bridge.activeStore else { return }
            switch result {
            case .success(let urls):
                for url in urls {
                    Task { await store.importSubfiles(from: url) }
                }
            case .failure(let error):
                bridge.presentedError = "Import failed: \(error.localizedDescription)"
            }
        }
        // Add subfiles from Library stored datasets
        .sheet(isPresented: $showLibraryPicker) {
            SPCLibraryDatasetPicker(bridge: bridge, availableDatasets: storedDatasets)
        }
    }

    // MARK: - Editor content

    @ViewBuilder
    private func editorContent(store: SPCDocumentStore) -> some View {
        NavigationSplitView {
            SubfileTreeView(store: store)
                .navigationTitle(bridge.editingDataset?.fileName ?? bridge.activeStore?.documentName ?? "SPC Editor")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
        } detail: {
            HStack(spacing: 0) {
                SpectrumChartView(store: store)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if showDataTable {
                    Divider()
                    #if os(iOS)
                    iOSXYDataTableView(store: store)
                        .frame(minWidth: 200, idealWidth: 280, maxWidth: 360)
                    #else
                    XYDataTableView(store: store)
                        .frame(minWidth: 240, idealWidth: 300, maxWidth: 400)
                    #endif
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") {
                    bridge.dismissEditor()
                    dismiss()
                }
            }

            ToolbarItem(placement: .automatic) {
                Button {
                    Task { await store.undo() }
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .disabled(!store.canUndo)
                .keyboardShortcut("z", modifiers: .command)
            }

            ToolbarItem(placement: .automatic) {
                Button {
                    Task { await store.redo() }
                } label: {
                    Label("Redo", systemImage: "arrow.uturn.forward")
                }
                .disabled(!store.canRedo)
                .keyboardShortcut("z", modifiers: [.command, .shift])
            }

            ToolbarItem(placement: .automatic) {
                Button {
                    store.showTransformPanel = true
                } label: {
                    Label("Transform", systemImage: "function")
                }
                .disabled(store.isTransforming)
            }

            ToolbarItem(placement: .automatic) {
                Button {
                    store.showMetadataEditor = true
                } label: {
                    Label("Edit Metadata", systemImage: "info.circle")
                }
            }

            // Toggle X,Y data table
            ToolbarItem(placement: .automatic) {
                Button {
                    withAnimation { showDataTable.toggle() }
                } label: {
                    Label("Data Table", systemImage: showDataTable ? "tablecells.fill" : "tablecells")
                }
                .help(showDataTable ? "Hide Data Table" : "Show Data Table")
            }

            // Import from file
            ToolbarItem(placement: .automatic) {
                Button {
                    showFileImporter = true
                } label: {
                    Label("Import File…", systemImage: "doc.badge.plus")
                }
            }

            // Add from Library
            ToolbarItem(placement: .automatic) {
                Button {
                    showLibraryPicker = true
                } label: {
                    Label("Add from Library…", systemImage: "tray.and.arrow.down")
                }
                .disabled(storedDatasets.isEmpty)
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    store.requestExport()
                } label: {
                    Label("Save As…", systemImage: "square.and.arrow.down")
                }
                .disabled(store.resolvedSubfiles.isEmpty)
            }
        }
    }

    // MARK: - Loading placeholder

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Opening SPC file...")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Export result handler

    private func handleExportResult(_ result: Result<URL, Error>) {
        guard let store = bridge.activeStore else { return }
        switch result {
        case .success(let url):
            if let data = try? Data(contentsOf: url) {
                bridge.handleSaveAs(
                    data: data,
                    format: store.selectedExportFormat,
                    suggestedName: url.lastPathComponent,
                    modelContext: modelContext
                )
            }
            Task { await store.handleExportResult(.success(url)) }

        case .failure(let error):
            bridge.presentedError = "Save failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Library Dataset Picker

/// Picker sheet that lets the user add subfiles from stored Library datasets
/// into the currently open SPC editor session.
struct SPCLibraryDatasetPicker: View {
    @Bindable var bridge: SPCLibraryBridge
    var availableDatasets: [StoredDataset]
    @Environment(\.dismiss) private var dismiss
    @State private var selectedIDs: Set<UUID> = []
    @State private var filterText = ""

    private var filteredDatasets: [StoredDataset] {
        let nonArchived = availableDatasets.filter { !$0.isArchived }
        guard !filterText.isEmpty else { return nonArchived }
        let query = filterText.lowercased()
        return nonArchived.filter { $0.fileName.lowercased().contains(query) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredDatasets, id: \.id) { dataset in
                    datasetPickerRow(dataset)
                }
            }
            .searchable(text: $filterText, prompt: "Filter datasets…")
            .navigationTitle("Add from Library")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Add \(selectedIDs.count) Dataset\(selectedIDs.count == 1 ? "" : "s")") {
                        let selected = availableDatasets.filter { selectedIDs.contains($0.id) }
                        Task {
                            await bridge.addDatasetsToEditor(selected)
                        }
                        dismiss()
                    }
                    .disabled(selectedIDs.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private func datasetPickerRow(_ dataset: StoredDataset) -> some View {
        let isSelected = selectedIDs.contains(dataset.id)
        Button {
            if isSelected {
                selectedIDs.remove(dataset.id)
            } else {
                selectedIDs.insert(dataset.id)
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(dataset.fileName)
                    Text(dataset.importedAt, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundColor(.accentColor)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
