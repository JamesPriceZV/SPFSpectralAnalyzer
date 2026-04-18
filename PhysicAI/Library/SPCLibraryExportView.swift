// SPCLibraryExportView.swift
// PhysicAI
//
// Format picker shown before the fileExporter Save As sheet.

import SwiftUI

struct SPCLibraryExportView: View {

    @Bindable var store: SPCDocumentStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    formatRow(.thermoGalactic, description: "Standard binary SPC (0x4B header). Compatible with GRAMS and most instruments.")
                    formatRow(.shimadzuCFB, description: "OLE2 Compound Binary. Required for Shimadzu software compatibility.")
                } header: {
                    Text("Output Format")
                } footer: {
                    Text("The edited file will be saved as a new dataset in your Library. The original is preserved.")
                }
            }
            .navigationTitle("Save As SPC")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Save") {
                        store.showExportFormatPicker = false
                        Task { await store.prepareExport() }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
    }

    @ViewBuilder
    private func formatRow(_ format: SPCExportFormat, description: String) -> some View {
        let isSelected = store.selectedExportFormat == format
        Button {
            store.selectedExportFormat = format
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(format.rawValue)
                        .foregroundStyle(.primary)
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
