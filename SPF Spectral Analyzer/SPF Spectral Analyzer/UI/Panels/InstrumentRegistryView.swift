import SwiftUI
import SwiftData

/// View displaying registered instruments in the Data Management tab.
///
/// Embedded in the right pane of the import panel. Shows a list of
/// registered instruments with Add/Edit/Delete actions.
struct InstrumentRegistryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StoredInstrument.createdAt, order: .reverse)
    private var instruments: [StoredInstrument]

    @State private var showEditorSheet = false
    @State private var editingInstrumentID: UUID?
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // MARK: Header
            HStack {
                Button {
                    withAnimation { isExpanded.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("Instrument Registry")
                            .font(.headline)
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                if isExpanded {
                    Text("\(instruments.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15))
                        .cornerRadius(4)

                    Button("Add Instrument") {
                        editingInstrumentID = nil
                        showEditorSheet = true
                    }
                    .registryGlassButtonStyle(isProminent: true)
                }
            }

            if isExpanded {
                if instruments.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "cpu")
                            .font(.system(size: 24))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("No instruments registered yet.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Register instruments to track which spectrophotometer produced each dataset.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                } else {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(instruments) { instrument in
                            instrumentRow(instrument)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showEditorSheet) {
            InstrumentEditorSheet(editingInstrumentID: editingInstrumentID)
        }
    }

    private func instrumentRow(_ instrument: StoredInstrument) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(instrument.displayName)
                        .font(.subheadline)
                        .lineLimit(1)
                    Text(instrument.instrumentType)
                        .font(.caption2.bold())
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(typeColor(instrument.instrumentType).opacity(0.2))
                        .foregroundColor(typeColor(instrument.instrumentType))
                        .cornerRadius(3)
                }

                HStack(spacing: 8) {
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

                if let address = instrument.locationAddress, !address.isEmpty {
                    Text(address)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
        }
        .padding(8)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
        .contextMenu {
            Button {
                editingInstrumentID = instrument.id
                showEditorSheet = true
            } label: {
                Label("Edit Instrument", systemImage: "pencil")
            }
            Divider()
            Button(role: .destructive) {
                deleteInstrument(instrument)
            } label: {
                Label("Delete Instrument", systemImage: "trash")
            }
        }
    }

    private func typeColor(_ type: String) -> Color {
        switch type {
        case "UV-Vis": return .blue
        case "UV-Vis-NIR": return .purple
        case "FTIR": return .orange
        default: return .secondary
        }
    }

    private func deleteInstrument(_ instrument: StoredInstrument) {
        let restoreAutoSave = modelContext.autosaveEnabled
        modelContext.autosaveEnabled = false

        do {
            try ObjCExceptionCatcher.try {
                self.modelContext.delete(instrument)
            }
        } catch {
            print("[InstrumentRegistry] ObjC exception during delete: \(error.localizedDescription)")
        }

        let context = modelContext
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            context.autosaveEnabled = restoreAutoSave
        }
    }
}

// MARK: - Glass Button Style (local copy for registry view)

private extension View {
    @ViewBuilder
    func registryGlassButtonStyle(isProminent: Bool = false) -> some View {
        if #available(macOS 15.0, *) {
            if isProminent {
                self.buttonStyle(.borderedProminent)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                self.buttonStyle(.glass)
            }
        } else {
            if isProminent {
                self.buttonStyle(.borderedProminent)
            } else {
                self.buttonStyle(.bordered)
            }
        }
    }
}
