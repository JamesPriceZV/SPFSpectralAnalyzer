import SwiftUI
import SwiftData

/// Sheet for assigning a registered instrument to one or more datasets.
///
/// Shows auto-detection suggestions based on the SPC header's `sourceInstrumentText`,
/// a list of registered instruments to pick from, and batch-assignment options.
struct AssignInstrumentSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \StoredInstrument.createdAt, order: .reverse)
    private var instruments: [StoredInstrument]

    /// The dataset ID for the primary assignment target.
    let datasetID: UUID
    /// The SPC `sourceInstrumentText` for auto-detection (from the search record cache).
    let sourceInstrumentText: String?
    /// The `sourcePath` of the target dataset (for batch matching).
    let sourcePath: String?
    /// All stored datasets (passed from the query).
    let storedDatasets: [StoredDataset]
    /// Callback when assignment completes.
    var onAssign: ((_ instrumentID: UUID, _ batchAssign: Bool) -> Void)?

    @State private var selectedInstrumentID: UUID?
    @State private var showEditorSheet = false
    @State private var showBatchConfirm = false

    private var autoDetectedEntry: InstrumentCatalog.CatalogEntry? {
        guard let text = sourceInstrumentText else { return nil }
        return InstrumentCatalog.detectMatch(from: text)
    }

    /// Instruments that match the auto-detected catalog entry.
    private var suggestedInstruments: [StoredInstrument] {
        guard let detected = autoDetectedEntry else { return [] }
        return instruments.filter {
            $0.manufacturer == detected.manufacturer && $0.modelName == detected.model
        }
    }

    /// Number of sibling datasets from the same import source path.
    private var siblingCount: Int {
        guard let path = sourcePath, !path.isEmpty else { return 0 }
        let directory = (path as NSString).deletingLastPathComponent
        guard !directory.isEmpty else { return 0 }
        return storedDatasets.filter { dataset in
            guard let dPath = dataset.sourcePath, dataset.id != datasetID else { return false }
            return (dPath as NSString).deletingLastPathComponent == directory
        }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Assign Instrument")
                .font(.title3)
                .bold()

            if let text = sourceInstrumentText, !text.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "cpu")
                        .foregroundColor(.secondary)
                    Text("SPC Header: \"\(text)\"")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let detected = autoDetectedEntry {
                        Text("→ \(detected.manufacturer) \(detected.model)")
                            .font(.caption.bold())
                            .foregroundColor(.blue)
                    }
                }
                .padding(8)
                .background(Color.blue.opacity(0.08))
                .cornerRadius(8)
            }

            if instruments.isEmpty {
                VStack(spacing: 12) {
                    Text("No instruments registered yet.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                    Text("Register an instrument first, then assign it to datasets.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                Text("Select an instrument:")
                    .font(.subheadline)

                // Auto-detected suggestions first
                if !suggestedInstruments.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Suggested Match")
                            .font(.caption.bold())
                            .foregroundColor(.blue)
                        ForEach(suggestedInstruments) { instrument in
                            instrumentPickerRow(instrument, isSuggested: true)
                        }
                    }
                    Divider()
                }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        let nonSuggested = instruments.filter { inst in
                            !suggestedInstruments.contains(where: { $0.id == inst.id })
                        }
                        ForEach(nonSuggested) { instrument in
                            instrumentPickerRow(instrument, isSuggested: false)
                        }
                    }
                }
                .frame(minHeight: 120, maxHeight: 240)
            }

            HStack(spacing: 12) {
                Button("Register New Instrument") {
                    showEditorSheet = true
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Assign") {
                    guard selectedInstrumentID != nil else { return }
                    if siblingCount > 0 {
                        showBatchConfirm = true
                    } else {
                        completeAssignment(batchAssign: false)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedInstrumentID == nil)
            }
        }
        .padding(24)
        .frame(minWidth: 520, idealWidth: 600, minHeight: 360, idealHeight: 480)
        .sheet(isPresented: $showEditorSheet) {
            InstrumentEditorSheet(editingInstrumentID: nil)
        }
        .alert("Batch Assignment", isPresented: $showBatchConfirm) {
            Button("This Dataset Only") {
                completeAssignment(batchAssign: false)
            }
            Button("All \(siblingCount + 1) Datasets") {
                completeAssignment(batchAssign: true)
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Found \(siblingCount) other dataset(s) from the same import session. Apply this instrument to all of them?")
        }
    }

    private func instrumentPickerRow(_ instrument: StoredInstrument, isSuggested: Bool) -> some View {
        let isSelected = selectedInstrumentID == instrument.id
        return Button {
            selectedInstrumentID = instrument.id
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(instrument.displayName)
                        .font(.subheadline)
                    HStack(spacing: 6) {
                        Text(instrument.instrumentType)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        if let serial = instrument.serialNumber, !serial.isEmpty {
                            Text("S/N: \(serial)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        if let lab = instrument.labNumber, !lab.isEmpty {
                            Text("Lab: \(lab)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                Spacer()
                if isSuggested {
                    Text("Suggested")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.15))
                        .foregroundColor(.blue)
                        .cornerRadius(4)
                }
            }
            .padding(8)
            .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            .cornerRadius(8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func completeAssignment(batchAssign: Bool) {
        guard let instrumentID = selectedInstrumentID else { return }
        onAssign?(instrumentID, batchAssign)
        dismiss()
    }
}
