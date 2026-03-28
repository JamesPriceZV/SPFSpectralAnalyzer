import SwiftUI
import SwiftData

/// Sheet for adding or editing an instrument in the registry.
struct InstrumentEditorSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// If non-nil, we're editing an existing instrument; otherwise creating new.
    let editingInstrumentID: UUID?

    @State private var selectedManufacturer: String = InstrumentCatalog.manufacturers.first ?? ""
    @State private var selectedModel: String = ""
    @State private var customManufacturer: String = ""
    @State private var customModel: String = ""
    @State private var serialNumber: String = ""
    @State private var labNumber: String = ""
    @State private var locationAddress: String = ""
    @State private var locationLatitude: Double?
    @State private var locationLongitude: Double?
    @State private var instrumentType: String = "UV-Vis"
    @State private var notes: String = ""
    @State private var didLoadExisting = false

    private var isCustomManufacturer: Bool {
        selectedManufacturer == InstrumentCatalog.customOther
    }

    private var isCustomModel: Bool {
        selectedModel == InstrumentCatalog.customOther
    }

    private var availableModels: [InstrumentCatalog.CatalogEntry] {
        InstrumentCatalog.models(for: selectedManufacturer)
    }

    private var resolvedManufacturer: String {
        isCustomManufacturer ? customManufacturer : selectedManufacturer
    }

    private var resolvedModel: String {
        isCustomModel ? customModel : selectedModel
    }

    private var canSave: Bool {
        !resolvedManufacturer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !resolvedModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(editingInstrumentID != nil ? "Edit Instrument" : "Register New Instrument")
                .font(.title3)
                .bold()

            Form {
                // MARK: Manufacturer
                Section("Manufacturer") {
                    Picker("Manufacturer", selection: $selectedManufacturer) {
                        ForEach(InstrumentCatalog.manufacturers, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    if isCustomManufacturer {
                        TextField("Custom Manufacturer", text: $customManufacturer)
                    }
                }

                // MARK: Model
                Section("Model") {
                    if !isCustomManufacturer && !availableModels.isEmpty {
                        Picker("Model", selection: $selectedModel) {
                            Text("Select...").tag("")
                            ForEach(availableModels) { entry in
                                Text("\(entry.model) (\(entry.type))").tag(entry.model)
                            }
                            Divider()
                            Text(InstrumentCatalog.customOther).tag(InstrumentCatalog.customOther)
                        }
                    } else {
                        TextField("Model Name", text: $customModel)
                    }
                    if isCustomModel && !isCustomManufacturer {
                        TextField("Custom Model Name", text: $customModel)
                    }
                }

                // MARK: Type
                Section("Instrument Type") {
                    Picker("Type", selection: $instrumentType) {
                        Text("UV-Vis").tag("UV-Vis")
                        Text("UV-Vis-NIR").tag("UV-Vis-NIR")
                        Text("FTIR").tag("FTIR")
                    }
                    .pickerStyle(.segmented)
                }

                // MARK: Identification
                Section("Identification (Optional)") {
                    TextField("Serial Number", text: $serialNumber)
                    TextField("Lab No.", text: $labNumber)
                }

                // MARK: Location
                Section("Physical Location (Optional)") {
                    AddressSearchField(
                        addressText: $locationAddress,
                        latitude: $locationLatitude,
                        longitude: $locationLongitude
                    )
                }

                // MARK: Notes
                Section("Notes (Optional)") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .formStyle(.grouped)

            HStack(spacing: 12) {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(editingInstrumentID != nil ? "Save Changes" : "Register Instrument") {
                    saveInstrument()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
        }
        .padding(24)
        .frame(minWidth: 500, idealWidth: 560, minHeight: 500, idealHeight: 620)
        .onAppear {
            loadExistingIfNeeded()
        }
        .onChange(of: selectedManufacturer) { _, newValue in
            guard !didLoadExisting || newValue != selectedManufacturer else { return }
            // Reset model selection when manufacturer changes
            selectedModel = ""
            customModel = ""
            // Auto-set instrument type from catalog if available
            if let first = InstrumentCatalog.models(for: newValue).first {
                instrumentType = first.type
            }
        }
        .onChange(of: selectedModel) { _, newValue in
            // Auto-set type when model is selected from catalog
            if let entry = availableModels.first(where: { $0.model == newValue }) {
                instrumentType = entry.type
            }
        }
    }

    private func loadExistingIfNeeded() {
        guard let existingID = editingInstrumentID, !didLoadExisting else { return }
        didLoadExisting = true

        let descriptor = FetchDescriptor<StoredInstrument>(
            predicate: #Predicate { $0.id == existingID }
        )
        guard let instrument = try? modelContext.fetch(descriptor).first else { return }

        // Check if manufacturer is in the catalog
        if InstrumentCatalog.manufacturers.contains(instrument.manufacturer) {
            selectedManufacturer = instrument.manufacturer
        } else {
            selectedManufacturer = InstrumentCatalog.customOther
            customManufacturer = instrument.manufacturer
        }

        // Check if model is in the catalog for this manufacturer
        let catalogModels = InstrumentCatalog.models(for: instrument.manufacturer)
        if catalogModels.contains(where: { $0.model == instrument.modelName }) {
            selectedModel = instrument.modelName
        } else {
            selectedModel = InstrumentCatalog.customOther
            customModel = instrument.modelName
        }

        serialNumber = instrument.serialNumber ?? ""
        labNumber = instrument.labNumber ?? ""
        locationAddress = instrument.locationAddress ?? ""
        locationLatitude = instrument.locationLatitude
        locationLongitude = instrument.locationLongitude
        instrumentType = instrument.instrumentType
        notes = instrument.notes ?? ""
    }

    private func saveInstrument() {
        let manufacturer = resolvedManufacturer.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = resolvedModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !manufacturer.isEmpty, !model.isEmpty else { return }

        // Snapshot local values to avoid touching @State during mutation
        let serial: String? = serialNumber.isEmpty ? nil : serialNumber
        let lab: String? = labNumber.isEmpty ? nil : labNumber
        let address: String? = locationAddress.isEmpty ? nil : locationAddress
        let lat = locationLatitude
        let lon = locationLongitude
        let type = instrumentType
        let noteText: String? = notes.isEmpty ? nil : notes

        // Temporarily pause autosave so our writes don't race with
        // CloudKit WAL checkpoints (the same pattern as DatasetViewModel).
        let restoreAutoSave = modelContext.autosaveEnabled
        modelContext.autosaveEnabled = false

        do {
            try ObjCExceptionCatcher.try {
                if let existingID = self.editingInstrumentID {
                    let descriptor = FetchDescriptor<StoredInstrument>(
                        predicate: #Predicate { $0.id == existingID }
                    )
                    guard let instrument = try? self.modelContext.fetch(descriptor).first else { return }
                    instrument.manufacturer = manufacturer
                    instrument.modelName = model
                    instrument.serialNumber = serial
                    instrument.labNumber = lab
                    instrument.locationAddress = address
                    instrument.locationLatitude = lat
                    instrument.locationLongitude = lon
                    instrument.instrumentType = type
                    instrument.notes = noteText
                } else {
                    let instrument = StoredInstrument(
                        manufacturer: manufacturer,
                        modelName: model,
                        serialNumber: serial,
                        labNumber: lab,
                        locationAddress: address,
                        locationLatitude: lat,
                        locationLongitude: lon,
                        instrumentType: type,
                        notes: noteText
                    )
                    self.modelContext.insert(instrument)
                }
            }
        } catch {
            // NSException from Core Data during CloudKit sync — log and bail
            print("[InstrumentEditor] ObjC exception during save: \(error.localizedDescription)")
        }

        // Re-enable autosave after a brief delay. SwiftData will persist the
        // pending changes on its next autosave pass, coordinating safely with
        // CloudKit's history tracking.
        let context = modelContext
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            context.autosaveEnabled = restoreAutoSave
        }
    }
}
