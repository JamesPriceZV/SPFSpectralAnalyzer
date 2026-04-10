import SwiftUI

// MARK: - Concept Categories for Semantic Diff

/// Predefined concept categories for grouping structured AI outputs.
/// Items from each provider's insights/risks/actions are tagged to categories
/// based on keyword matching against common spectral analysis terms.
enum SemanticDiffCategory: String, CaseIterable, Identifiable {
    case spfValue = "SPF Value"
    case criticalWavelength = "Critical Wavelength"
    case uvaProtection = "UVA Protection"
    case uvbProtection = "UVB Protection"
    case photostability = "Photostability"
    case formulation = "Formulation"
    case compliance = "Compliance"
    case methodology = "Methodology"
    case general = "General"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .spfValue: return "sun.max.fill"
        case .criticalWavelength: return "waveform.path.ecg"
        case .uvaProtection: return "shield.lefthalf.filled"
        case .uvbProtection: return "shield.righthalf.filled"
        case .photostability: return "clock.arrow.circlepath"
        case .formulation: return "flask.fill"
        case .compliance: return "checkmark.seal.fill"
        case .methodology: return "scope"
        case .general: return "info.circle"
        }
    }

    var color: Color {
        switch self {
        case .spfValue: return .orange
        case .criticalWavelength: return .purple
        case .uvaProtection: return .blue
        case .uvbProtection: return .cyan
        case .photostability: return .yellow
        case .formulation: return .green
        case .compliance: return .mint
        case .methodology: return .indigo
        case .general: return .gray
        }
    }

    /// Keywords used to match structured output items to this category.
    var keywords: [String] {
        switch self {
        case .spfValue:
            return ["spf", "sun protection factor", "spf value", "spf estimation", "spf prediction", "estimated spf", "predicted spf"]
        case .criticalWavelength:
            return ["critical wavelength", "critical λ", "λc", "370 nm", "broad-spectrum", "broad spectrum"]
        case .uvaProtection:
            return ["uva", "uv-a", "uva protection", "uva ratio", "uva/uvb", "320-400", "long-wave"]
        case .uvbProtection:
            return ["uvb", "uv-b", "uvb protection", "290-320", "short-wave", "erythemal"]
        case .photostability:
            return ["photostab", "photo-stab", "irradiation", "post-irrad", "degradation", "light exposure", "stability"]
        case .formulation:
            return ["formula", "ingredient", "concentration", "emollient", "emulsifier", "active", "zinc oxide", "titanium", "avobenzone", "octocrylene", "filter"]
        case .compliance:
            return ["comply", "compliance", "colipa", "iso", "regulation", "fda", "eu ", "standard", "requirement", "pass", "fail"]
        case .methodology:
            return ["method", "technique", "measurement", "procedure", "protocol", "substrate", "pmma", "plate", "application"]
        case .general:
            return []  // Catch-all for unmatched items
        }
    }

    /// Match a text string to this category by checking for keyword overlap.
    func matches(_ text: String) -> Bool {
        let lower = text.lowercased()
        return keywords.contains { lower.contains($0) }
    }
}

// MARK: - Categorized Item

/// An item (insight, risk, or action) from a provider, tagged with its category.
struct CategorizedItem: Identifiable {
    let id = UUID()
    let text: String
    let providerName: String
    let providerID: AIProviderID
    let itemType: ItemType

    enum ItemType: String {
        case insight
        case risk
        case action
    }
}

/// Agreement level across providers for a given concept category.
enum AgreementLevel {
    case fullConsensus   // All providers mention items in this category
    case partialAgreement // Some providers mention, some don't
    case singleProvider  // Only one provider mentions this category

    var color: Color {
        switch self {
        case .fullConsensus: return .green
        case .partialAgreement: return .yellow
        case .singleProvider: return .orange
        }
    }

    var label: String {
        switch self {
        case .fullConsensus: return "Consensus"
        case .partialAgreement: return "Partial"
        case .singleProvider: return "Single"
        }
    }

    var iconName: String {
        switch self {
        case .fullConsensus: return "checkmark.circle.fill"
        case .partialAgreement: return "exclamationmark.triangle.fill"
        case .singleProvider: return "person.fill"
        }
    }
}

// MARK: - Semantic Diff View

/// Concept-level comparison of ensemble provider responses.
/// Groups items by category (SPF, UVA, formulation, etc.) and shows
/// which providers agree, partially agree, or are unique.
struct EnsembleSemanticDiffView: View {
    let ensemble: EnsembleAnalysisResult
    let arbitratedResult: ArbitratedEnsembleResult?

    private var categorizedResults: [SemanticDiffCategory: [CategorizedItem]] {
        var result: [SemanticDiffCategory: [CategorizedItem]] = [:]

        for providerResult in ensemble.successfulResults {
            guard let structured = providerResult.response.structured else { continue }
            let name = providerResult.providerID.displayName
            let pid = providerResult.providerID

            for insight in structured.insights {
                let category = categorize(insight)
                result[category, default: []].append(
                    CategorizedItem(text: insight, providerName: name, providerID: pid, itemType: .insight)
                )
            }
            for risk in structured.risks {
                let category = categorize(risk)
                result[category, default: []].append(
                    CategorizedItem(text: risk, providerName: name, providerID: pid, itemType: .risk)
                )
            }
            for action in structured.actions {
                let category = categorize(action)
                result[category, default: []].append(
                    CategorizedItem(text: action, providerName: name, providerID: pid, itemType: .action)
                )
            }
        }

        return result
    }

    private var sortedCategories: [SemanticDiffCategory] {
        let results = categorizedResults
        return SemanticDiffCategory.allCases.filter { results[$0] != nil && !(results[$0]?.isEmpty ?? true) }
    }

    private var totalProviderCount: Int {
        ensemble.successfulResults.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Arbitration banner
            if let arbitrated = arbitratedResult {
                arbitrationBanner(arbitrated)
            }

            // Category grid
            if sortedCategories.isEmpty {
                ContentUnavailableView(
                    "No Structured Data",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Semantic diff requires structured output from at least one provider.")
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(sortedCategories) { category in
                            categoryRow(category)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
        }
        .padding(12)
    }

    // MARK: - Arbitration Banner

    @ViewBuilder
    private func arbitrationBanner(_ arbitrated: ArbitratedEnsembleResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "apple.logo")
                    .foregroundColor(.accentColor)
                Text("Arbitrated by Apple Intelligence")
                    .font(.subheadline.bold())
                Spacer()
            }

            Text(arbitrated.unifiedSummary)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(4)

            if !arbitrated.disputedFindings.isEmpty {
                Divider()
                Text("Disputed Findings")
                    .font(.caption.bold())
                    .foregroundColor(.red)
                ForEach(arbitrated.disputedFindings) { dispute in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(dispute.claim)
                            .font(.caption)
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.caption2)
                            Text(dispute.supportingProviders.joined(separator: ", "))
                                .font(.caption2)
                                .foregroundColor(.green)
                        }
                        HStack(spacing: 4) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                                .font(.caption2)
                            Text(dispute.opposingProviders.joined(separator: ", "))
                                .font(.caption2)
                                .foregroundColor(.red)
                        }
                        Text("Resolution: \(dispute.resolution)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .italic()
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(10)
        .background(Color.accentColor.opacity(0.08))
        .cornerRadius(10)
    }

    // MARK: - Category Row

    @ViewBuilder
    private func categoryRow(_ category: SemanticDiffCategory) -> some View {
        let items = categorizedResults[category] ?? []
        let providerIDs = Set(items.map(\.providerID))
        let agreement = agreementLevel(providerIDs: providerIDs)

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: category.iconName)
                    .foregroundColor(category.color)
                    .frame(width: 20)
                Text(category.rawValue)
                    .font(.subheadline.bold())
                Spacer()
                agreementBadge(agreement, providerCount: providerIDs.count)
            }

            // Group items by provider
            let byProvider = Dictionary(grouping: items) { $0.providerID }
            ForEach(Array(byProvider.keys.sorted(by: { $0.rawValue < $1.rawValue })), id: \.self) { pid in
                if let providerItems = byProvider[pid] {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Image(systemName: pid.iconName)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(pid.displayName)
                                .font(.caption2.bold())
                                .foregroundColor(.secondary)
                        }
                        ForEach(providerItems) { item in
                            HStack(alignment: .top, spacing: 4) {
                                Circle()
                                    .fill(itemTypeColor(item.itemType))
                                    .frame(width: 6, height: 6)
                                    .padding(.top, 4)
                                Text(item.text)
                                    .font(.caption)
                                    .lineLimit(3)
                            }
                        }
                    }
                    .padding(.leading, 28)
                }
            }
        }
        .padding(8)
        .background(.thinMaterial)
        .cornerRadius(10)
    }

    // MARK: - Helpers

    private func agreementBadge(_ agreement: AgreementLevel, providerCount: Int) -> some View {
        HStack(spacing: 3) {
            Image(systemName: agreement.iconName)
                .font(.caption2)
            Text("\(providerCount)/\(totalProviderCount)")
                .font(.caption2.bold())
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(agreement.color.opacity(0.2))
        .foregroundColor(agreement.color)
        .cornerRadius(6)
    }

    private func agreementLevel(providerIDs: Set<AIProviderID>) -> AgreementLevel {
        if providerIDs.count >= totalProviderCount {
            return .fullConsensus
        } else if providerIDs.count > 1 {
            return .partialAgreement
        } else {
            return .singleProvider
        }
    }

    private func categorize(_ text: String) -> SemanticDiffCategory {
        for category in SemanticDiffCategory.allCases where category != .general {
            if category.matches(text) {
                return category
            }
        }
        return .general
    }

    private func itemTypeColor(_ type: CategorizedItem.ItemType) -> Color {
        switch type {
        case .insight: return .blue
        case .risk: return .red
        case .action: return .green
        }
    }
}
