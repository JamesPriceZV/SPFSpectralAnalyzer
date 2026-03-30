import SwiftUI
import SwiftData

/// Detail/edit view for a formula card's parsed ingredient data.
/// Presented as a sheet when the user taps a formula card link.
struct FormulaCardDetailView: View {
    let formulaCardID: UUID
    @Bindable var datasets: DatasetViewModel
    var storedDatasets: [StoredDataset]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var cardName: String = ""
    @State private var ingredients: [FormulaIngredient] = []
    @State private var ph: Double?
    @State private var notes: String = ""
    @State private var isParsing: Bool = false
    @State private var parseError: String?

    private var card: StoredFormulaCard? {
        datasets.formulaCards.first(where: { $0.id == formulaCardID })
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Formula Card")
                    .font(.headline)
                Spacer()
                Button("Done") { saveAndDismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Name and source
                    nameSection

                    Divider()

                    // Ingredients table
                    ingredientsSection

                    Divider()

                    // pH and totals
                    phSection

                    Divider()

                    // Notes
                    notesSection

                    // Parse status
                    parseStatusSection
                }
                .padding()
            }
        }
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 480, idealHeight: 600)
        #endif
        .onAppear { loadCardData() }
    }

    // MARK: - Sections

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Name")
                .font(.subheadline.bold())
                .foregroundColor(.secondary)
            TextField("Formula card name", text: $cardName)
                .textFieldStyle(.roundedBorder)
            if let source = card?.sourceFileName {
                HStack(spacing: 4) {
                    Image(systemName: "doc")
                        .font(.caption)
                    Text("Source: \(source)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var ingredientsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Ingredients")
                    .font(.subheadline.bold())
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(ingredients.count) total")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Button {
                    addIngredient()
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.subheadline)
                }
                .buttonStyle(.plain)
            }

            if ingredients.isEmpty {
                Text("No ingredients parsed yet.")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .italic()
                    .padding(.vertical, 8)
            } else {
                // Header row
                HStack(spacing: 4) {
                    Text("Name")
                        .frame(minWidth: 120, alignment: .leading)
                    Text("Qty")
                        .frame(width: 60, alignment: .trailing)
                    Text("Unit")
                        .frame(width: 40, alignment: .center)
                    Text("%")
                        .frame(width: 50, alignment: .trailing)
                    Text("Category")
                        .frame(minWidth: 80, alignment: .leading)
                    Spacer()
                }
                .font(.caption2.bold())
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)

                ForEach($ingredients) { $ingredient in
                    ingredientRow(ingredient: $ingredient)
                }
            }
        }
    }

    private func ingredientRow(ingredient: Binding<FormulaIngredient>) -> some View {
        HStack(spacing: 4) {
            TextField("Name", text: ingredient.name)
                .frame(minWidth: 120)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
            TextField("Qty", value: ingredient.quantity, format: .number)
                .frame(width: 60)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
            TextField("g", text: Binding(
                get: { ingredient.wrappedValue.unit ?? "" },
                set: { ingredient.wrappedValue.unit = $0.isEmpty ? nil : $0 }
            ))
                .frame(width: 40)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
            if let pct = ingredient.wrappedValue.percentage {
                Text(String(format: "%.1f%%", pct))
                    .frame(width: 50, alignment: .trailing)
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("—")
                    .frame(width: 50, alignment: .trailing)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            TextField("Category", text: Binding(
                get: { ingredient.wrappedValue.category ?? "" },
                set: { ingredient.wrappedValue.category = $0.isEmpty ? nil : $0 }
            ))
                .frame(minWidth: 80)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
            Button {
                removeIngredient(id: ingredient.wrappedValue.id)
            } label: {
                Image(systemName: "minus.circle")
                    .foregroundColor(.red)
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 1)
    }

    private var phSection: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("pH")
                    .font(.subheadline.bold())
                    .foregroundColor(.secondary)
                TextField("e.g. 7.0", value: $ph, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Total Weight")
                    .font(.subheadline.bold())
                    .foregroundColor(.secondary)
                let total = ingredients.compactMap(\.quantity).reduce(0, +)
                Text(total > 0 ? String(format: "%.2f g", total) : "—")
                    .font(.callout)
                    .foregroundColor(total > 0 ? .primary : .secondary)
            }

            Spacer()
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Notes")
                .font(.subheadline.bold())
                .foregroundColor(.secondary)
            TextEditor(text: $notes)
                .frame(minHeight: 60, maxHeight: 100)
                .font(.callout)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
        }
    }

    private var parseStatusSection: some View {
        HStack {
            if isParsing {
                ProgressView()
                    .controlSize(.small)
                Text("Parsing with AI...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if let error = parseError {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundColor(.orange)
                Text(error)
                    .font(.caption)
                    .foregroundColor(.orange)
            }

            Spacer()

            if !isParsing, card?.extractedText != nil {
                Button("Re-parse with AI") {
                    Task { await reparseWithAI() }
                }
                .font(.caption)
            }
        }
    }

    // MARK: - Actions

    private func loadCardData() {
        guard let card else { return }
        cardName = card.name
        notes = card.notes ?? ""
        ph = card.parsedPH
        ingredients = card.ingredients

        // If not parsed yet and we have file data, start extraction + parsing
        if !card.isParsed, card.sourceFileData != nil, card.extractedText == nil {
            Task { await extractAndParse() }
        }
    }

    private func addIngredient() {
        ingredients.append(FormulaIngredient(name: "", quantity: nil, unit: "g", percentage: nil, category: nil))
    }

    private func removeIngredient(id: UUID) {
        ingredients.removeAll { $0.id == id }
    }

    private func saveAndDismiss() {
        guard let card else {
            dismiss()
            return
        }

        do {
            try ObjCExceptionCatcher.try {
                card.name = cardName
                card.ingredientsJSON = try? JSONEncoder().encode(ingredients)
                card.parsedPH = ph
                card.notes = notes.isEmpty ? nil : notes
                let total = ingredients.compactMap(\.quantity).reduce(0, +)
                card.totalWeightGrams = total > 0 ? total : nil
            }
        } catch {
            Instrumentation.log(
                "FormulaCardDetailView save caught NSException",
                area: .processing, level: .error,
                details: "error=\(error.localizedDescription)"
            )
        }

        datasets.dataStoreController?.noteLocalChange(bytes: 256)
        datasets.dataVersion += 1
        dismiss()
    }

    private func extractAndParse() async {
        guard let card, let fileData = card.sourceFileData, let fileType = card.sourceFileType else { return }

        isParsing = true
        parseError = nil

        do {
            // Step 1: Extract text
            let text = try await FormulaCardTextExtractor.extractText(from: fileData, fileType: fileType)

            // Save extracted text
            do {
                try ObjCExceptionCatcher.try {
                    card.extractedText = text
                }
            } catch {
                Instrumentation.log(
                    "FormulaCardDetailView: save extractedText caught NSException",
                    area: .processing, level: .warning,
                    details: "error=\(error.localizedDescription)"
                )
            }

            // Step 2: Parse with AI
            let result = try await FormulaCardParser.parseIngredients(from: text)

            await MainActor.run {
                ingredients = result.ingredients
                ph = result.ph

                // Save parsed results
                do {
                    try ObjCExceptionCatcher.try {
                        card.ingredientsJSON = try? JSONEncoder().encode(result.ingredients)
                        card.parsedPH = result.ph
                        card.totalWeightGrams = result.totalWeightGrams
                        card.isParsed = true
                    }
                } catch {
                    Instrumentation.log(
                        "FormulaCardDetailView: save parsed results caught NSException",
                        area: .processing, level: .warning,
                        details: "error=\(error.localizedDescription)"
                    )
                }

                datasets.dataStoreController?.noteLocalChange(bytes: 256)
                datasets.dataVersion += 1
                isParsing = false
            }
        } catch {
            await MainActor.run {
                parseError = error.localizedDescription
                isParsing = false
            }
        }
    }

    private func reparseWithAI() async {
        guard let card, let text = card.extractedText else { return }

        isParsing = true
        parseError = nil

        do {
            let result = try await FormulaCardParser.parseIngredients(from: text)

            await MainActor.run {
                ingredients = result.ingredients
                ph = result.ph
                isParsing = false
            }
        } catch {
            await MainActor.run {
                parseError = error.localizedDescription
                isParsing = false
            }
        }
    }
}
