// SPCEditorSheet.swift
// SPFSpectralAnalyzer
//
// Full-featured SPC editor presented as a sheet from the Library.
// Wraps SPCKit's SPCDocumentStore + views inside a NavigationSplitView.

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SPCEditorSheet: View {

    @Bindable var bridge: SPCLibraryBridge
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

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
    }

    // MARK: - Editor content

    @ViewBuilder
    private func editorContent(store: SPCDocumentStore) -> some View {
        NavigationSplitView {
            SubfileTreeView(store: store)
                .navigationTitle(bridge.editingDataset?.fileName ?? "SPC Editor")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
        } detail: {
            SpectrumChartView(store: store)
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

            ToolbarItem(placement: .primaryAction) {
                Button {
                    store.requestExport()
                } label: {
                    Label("Save As...", systemImage: "square.and.arrow.down")
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
