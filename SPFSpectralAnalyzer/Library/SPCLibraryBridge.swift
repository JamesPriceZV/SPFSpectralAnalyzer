// SPCLibraryBridge.swift
// SPFSpectralAnalyzer
//
// @MainActor bridge between the Library's DatasetViewModel and SPCKit's
// SPCDocumentStore. One SPCDocumentStore per open editor session.

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

@MainActor
@Observable
final class SPCLibraryBridge {

    // MARK: - Public state

    private(set) var activeStore: SPCDocumentStore?
    private(set) var editingDataset: StoredDataset?
    var isEditorPresented: Bool = false
    var isCombining: Bool = false
    var presentedError: String?

    // MARK: - Open for editing

    func openForEditing(_ dataset: StoredDataset) async {
        guard let data = dataset.fileData else {
            presentedError = "No file data available for \(dataset.fileName)."
            return
        }
        do {
            let spcFile = try SPCParser.parse(data: data)
            let store = SPCDocumentStore()
            store.loadParsed(spcFile)
            store.documentName = dataset.fileName
                .replacingOccurrences(of: ".spc", with: "", options: .caseInsensitive)
            activeStore = store
            editingDataset = dataset
            isEditorPresented = true
        } catch {
            presentedError = "Cannot open \(dataset.fileName): \(error.localizedDescription)"
        }
    }

    // MARK: - Combine multiple datasets into one SPC file

    func combineDatasets(_ datasets: [StoredDataset]) async {
        guard datasets.count >= 2 else {
            presentedError = "Select at least 2 datasets to combine."
            return
        }
        isCombining = true
        defer { isCombining = false }

        guard let firstData = datasets.first?.fileData else {
            presentedError = "First dataset has no file data."
            return
        }
        do {
            let baseFile = try SPCParser.parse(data: firstData)
            let store = SPCDocumentStore()
            store.loadParsed(baseFile)
            store.documentName = "Combined"

            for dataset in datasets.dropFirst() {
                guard let data = dataset.fileData else { continue }
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(dataset.fileName)
                try data.write(to: tempURL)
                await store.importSubfiles(from: tempURL)
                try? FileManager.default.removeItem(at: tempURL)
            }

            activeStore = store
            editingDataset = nil
            isEditorPresented = true
        } catch {
            presentedError = "Combine failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Save As

    func handleSaveAs(
        data: Data,
        format: SPCExportFormat,
        suggestedName: String,
        modelContext: ModelContext
    ) {
        let newDataset = StoredDataset(
            fileName: suggestedName,
            sourcePath: nil,
            fileHash: nil,
            fileData: data,
            metadataJSON: nil,
            headerInfoData: nil,
            skippedDataJSON: nil,
            warningsJSON: nil
        )
        newDataset.spcKitEdited = true
        newDataset.spcFileFormat = format.rawValue
        modelContext.insert(newDataset)
        do {
            try modelContext.save()
        } catch {
            presentedError = "Failed to save dataset: \(error.localizedDescription)"
        }
    }

    // MARK: - Dismiss editor

    func dismissEditor() {
        isEditorPresented = false
        activeStore = nil
        editingDataset = nil
    }

    // MARK: - Helpers

    static func canOpen(_ dataset: StoredDataset) -> Bool {
        guard let data = dataset.fileData, data.count >= 256 else { return false }
        let versionByte = data[1]
        if versionByte == 0x4B || versionByte == 0x4D { return true }
        if data.count >= 8 {
            let magic: [UInt8] = [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]
            return zip(magic, data.prefix(8)).allSatisfy { $0 == $1 }
        }
        return false
    }
}
