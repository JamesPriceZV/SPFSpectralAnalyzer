import SwiftUI
import SwiftData
import WebKit

/// Detail/edit view for a formula card's parsed ingredient data.
/// Presented as a sheet when the user taps a formula card link.
struct FormulaCardDetailView: View {
    let formulaCardID: UUID
    @Bindable var datasets: DatasetViewModel
    var storedDatasets: [StoredDataset]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    // AI provider settings
    @AppStorage("aiOpenAIEndpoint") private var aiOpenAIEndpoint = "https://api.openai.com/v1/responses"
    @AppStorage("aiOpenAIModel") private var aiOpenAIModel = "gpt-5.4"
    @AppStorage("aiProviderPreference") private var aiProviderPreferenceRawValue = AIProviderPreference.auto.rawValue
    @AppStorage("aiClaudeModel") private var aiClaudeModel = "claude-sonnet-4-5-20250514"
    @AppStorage("aiGrokModel") private var aiGrokModel = "grok-3"
    @AppStorage("aiGeminiModel") private var aiGeminiModel = "gemini-2.5-flash"
    @AppStorage("aiTemperature") private var aiTemperature = 0.3
    @AppStorage("aiMaxTokens") private var aiMaxTokens = 800

    // Multi-provider routing
    @AppStorage("aiProviderPriorityOrder") private var aiProviderPriorityOrderJSON = ""
    @AppStorage("aiAdvancedRoutingEnabled") private var aiAdvancedRoutingEnabled = false
    @AppStorage("aiFunctionRoutingJSON") private var aiFunctionRoutingJSON = ""

    @State private var cardName: String = ""
    @State private var ingredients: [FormulaIngredient] = []
    @State private var ph: Double?
    @State private var notes: String = ""
    @State private var isParsing: Bool = false
    @State private var parseError: String?
    @State private var usedProvider: AIProviderID?
    @State private var lastDiffURL: URL?
    @State private var showDiffWebView = false

    private var aiProviderPreference: AIProviderPreference {
        AIProviderPreference(rawValue: aiProviderPreferenceRawValue) ?? .auto
    }

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
        .frame(minWidth: 680, minHeight: 480, idealHeight: 600)
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
                Grid(alignment: .leading, horizontalSpacing: 4, verticalSpacing: 2) {
                    // Header row
                    GridRow {
                        Text("Name")
                            .gridColumnAlignment(.leading)
                        HStack(spacing: 2) {
                            Text("INCI")
                            HelpButton("INCI Name", message: "**INCI (International Nomenclature of Cosmetic Ingredients)** is the standardized naming system used worldwide for cosmetic ingredients.\n\nEvery ingredient in a sunscreen or cosmetic product has an official INCI name (e.g., \u{201c}Ethylhexyl Methoxycinnamate\u{201d} instead of the brand name \u{201c}Octinoxate\u{201d}).\n\nINCI names ensure that the same ingredient is identified consistently regardless of manufacturer, brand, or country. They are required on product labels in most countries.")
                        }
                            .gridColumnAlignment(.leading)
                        Text("Qty (mg)")
                            .gridColumnAlignment(.trailing)
                        Text("%")
                            .gridColumnAlignment(.trailing)
                        Text("Category")
                            .gridColumnAlignment(.leading)
                        // Spacer column for delete button
                        Color.clear
                            .gridCellUnsizedAxes(.horizontal)
                            .frame(width: 20)
                    }
                    .font(.caption2.bold())
                    .foregroundColor(.secondary)

                    ForEach($ingredients) { $ingredient in
                        ingredientGridRow(ingredient: $ingredient)
                    }
                }
            }
        }
    }

    private func ingredientGridRow(ingredient: Binding<FormulaIngredient>) -> some View {
        GridRow {
            TextField("Name", text: ingredient.name)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
            TextField("INCI", text: Binding(
                get: { ingredient.wrappedValue.inciName ?? "" },
                set: { ingredient.wrappedValue.inciName = $0.isEmpty ? nil : $0 }
            ))
                .textFieldStyle(.roundedBorder)
                .font(.caption)
            HStack(spacing: 2) {
                TextField("mg", value: Binding(
                    get: {
                        guard let qty = ingredient.wrappedValue.quantity else { return nil as Double? }
                        let u = (ingredient.wrappedValue.unit ?? "mg").lowercased()
                        return u == "g" ? qty * 1000 : qty
                    },
                    set: { newValue in
                        ingredient.wrappedValue.quantity = newValue
                        ingredient.wrappedValue.unit = "mg"
                    }
                ), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                Text("mg")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(width: 80)
            if let pct = ingredient.wrappedValue.percentage {
                Text(String(format: "%.1f%%", pct))
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("—")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            TextField("Category", text: Binding(
                get: { ingredient.wrappedValue.category ?? "" },
                set: { ingredient.wrappedValue.category = $0.isEmpty ? nil : $0 }
            ))
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
            HStack {
                Text("Notes")
                    .font(.subheadline.bold())
                    .foregroundColor(.secondary)
                Spacer()
                if let diffURL = lastDiffURL {
                    Button {
                        #if os(macOS)
                        PlatformURLOpener.open(diffURL)
                        #else
                        showDiffWebView = true
                        #endif
                    } label: {
                        Label("View Last Diff", systemImage: "doc.text.magnifyingglass")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                }
            }
            TextEditor(text: $notes)
                .frame(minHeight: 60, maxHeight: 100)
                .font(.callout)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
        }
        .sheet(isPresented: $showDiffWebView) {
            if let diffURL = lastDiffURL {
                DiffWebViewSheet(url: diffURL)
            }
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

            if let provider = usedProvider, !isParsing {
                Text(provider.displayName)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.15))
                    .clipShape(Capsule())
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
        ingredients.append(FormulaIngredient(name: "", inciName: nil, quantity: nil, unit: "mg", percentage: nil, category: nil))
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

            // Step 2: Parse with AI using fallback chain
            let (priorityOrder, credentials) = resolveFormulaCardProviderChain()
            let result = try await FormulaCardParser.parseWithFallback(
                from: text,
                providerPriorityOrder: priorityOrder,
                credentials: credentials
            )

            await MainActor.run {
                ingredients = result.ingredients
                ph = result.ph
                usedProvider = result.usedProvider

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

        // Snapshot old ingredients before re-parse for diff generation
        let oldIngredients = ingredients

        isParsing = true
        parseError = nil
        usedProvider = nil

        do {
            let (priorityOrder, credentials) = resolveFormulaCardProviderChain()
            let result = try await FormulaCardParser.parseWithFallback(
                from: text,
                providerPriorityOrder: priorityOrder,
                credentials: credentials
            )

            await MainActor.run {
                ingredients = result.ingredients
                ph = result.ph
                usedProvider = result.usedProvider

                // Generate diff and append to notes
                appendDiffToNotes(
                    oldIngredients: oldIngredients,
                    newIngredients: result.ingredients,
                    providerID: result.usedProvider
                )

                isParsing = false
            }
        } catch {
            await MainActor.run {
                parseError = error.localizedDescription
                isParsing = false
            }
        }
    }

    private func appendDiffToNotes(
        oldIngredients: [FormulaIngredient],
        newIngredients: [FormulaIngredient],
        providerID: AIProviderID?
    ) {
        let diffEntries = IngredientDiffService.diff(old: oldIngredients, new: newIngredients)
        guard !diffEntries.isEmpty else { return }

        let providerName = providerID?.displayName ?? "AI"
        let now = Date()

        // Generate HTML diff file
        let html = IngredientDiffService.generateHTML(
            diff: diffEntries,
            providerName: providerName,
            timestamp: now
        )

        // Write to temp file
        let filename = "formula_card_diff_\(UUID().uuidString.prefix(8)).html"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? html.data(using: .utf8)?.write(to: tempURL)
        lastDiffURL = tempURL

        // Generate notes summary with link
        let summary = IngredientDiffService.generateNotesSummary(
            diff: diffEntries,
            providerName: providerName,
            timestamp: now
        )

        // Append to notes
        let separator = notes.isEmpty ? "" : "\n\n"
        notes += "\(separator)\(summary)\nDiff: \(tempURL.absoluteString)"
    }

    // MARK: - Provider Routing

    /// Build the provider priority chain for formula card parsing with fallback.
    /// Returns the ordered list of providers to try and the credentials bundle.
    private func resolveFormulaCardProviderChain() -> ([AIProviderID], ProviderCredentials) {
        let credentials = ProviderCredentials(
            openAIEndpoint: aiOpenAIEndpoint,
            openAIModel: aiOpenAIModel,
            openAIAPIKey: KeychainStore.readPassword(account: KeychainKeys.openAIAPIKey),
            claudeModel: aiClaudeModel,
            claudeAPIKey: KeychainStore.readPassword(account: KeychainKeys.anthropicAPIKey),
            grokModel: aiGrokModel,
            grokAPIKey: KeychainStore.readPassword(account: KeychainKeys.grokAPIKey),
            geminiModel: aiGeminiModel,
            geminiAPIKey: KeychainStore.readPassword(account: KeychainKeys.geminiAPIKey),
            temperature: aiTemperature,
            maxTokens: aiMaxTokens
        )

        // Decode priority order
        let priorityOrder: [AIProviderID]
        if !aiProviderPriorityOrderJSON.isEmpty,
           let data = aiProviderPriorityOrderJSON.data(using: .utf8),
           let rawValues = try? JSONDecoder().decode([String].self, from: data) {
            let decoded = rawValues.compactMap { AIProviderID(rawValue: $0) }
            priorityOrder = decoded.isEmpty ? AIProviderID.defaultPriorityOrder : decoded
        } else {
            priorityOrder = AIProviderID.defaultPriorityOrder
        }

        // If advanced routing specifies a particular provider, put it first
        if aiAdvancedRoutingEnabled,
           !aiFunctionRoutingJSON.isEmpty,
           let data = aiFunctionRoutingJSON.data(using: .utf8),
           let dict = try? JSONDecoder().decode([String: FunctionRoutingMode].self, from: data),
           let mode = dict[AIAppFunction.formulaCardParsing.rawValue],
           case .specific(let preferred) = mode {
            // Put the preferred provider first, then the rest of the priority order as fallback
            var ordered = [preferred]
            for id in priorityOrder where id != preferred {
                ordered.append(id)
            }
            return (ordered, credentials)
        }

        // Legacy preference mapping: put preferred first, rest as fallback
        let pref = aiProviderPreference
        if pref != .auto {
            let preferredID: AIProviderID
            switch pref {
            case .onDevice: preferredID = .onDevice
            case .claude:   preferredID = .claude
            case .openAI:   preferredID = .openAI
            case .grok:     preferredID = .grok
            case .gemini:   preferredID = .gemini
            case .auto:     preferredID = priorityOrder.first ?? .onDevice
            }
            var ordered = [preferredID]
            for id in priorityOrder where id != preferredID {
                ordered.append(id)
            }
            return (ordered, credentials)
        }

        return (priorityOrder, credentials)
    }
}

// MARK: - Diff WebView Sheet

/// In-app HTML diff viewer using WKWebView, for cross-platform diff viewing.
struct DiffWebViewSheet: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            DiffWebViewRepresentable(url: url)
                .navigationTitle("Re-Parse Diff")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                    #if os(macOS)
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            PlatformURLOpener.open(url)
                        } label: {
                            Label("Open in Browser", systemImage: "safari")
                        }
                    }
                    #endif
                }
        }
        #if os(macOS)
        .frame(minWidth: 600, minHeight: 400, idealHeight: 500)
        #endif
    }
}

#if os(macOS)
struct DiffWebViewRepresentable: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
#else
struct DiffWebViewRepresentable: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
#endif
