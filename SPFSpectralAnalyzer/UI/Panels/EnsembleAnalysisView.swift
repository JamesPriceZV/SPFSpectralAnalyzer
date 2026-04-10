import SwiftUI

/// Tabs for the ensemble comparison view.
enum EnsembleComparisonTab: String, CaseIterable, Identifiable {
    case providers = "Providers"
    case semanticDiff = "Semantic Diff"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .providers: return "rectangle.split.3x1"
        case .semanticDiff: return "text.magnifyingglass"
        }
    }
}

/// Side-by-side comparison view for ensemble mode results.
/// Shows cards for each provider's response with timing, token usage, and a "Use This" button.
/// Includes a "Semantic Diff" tab for concept-level comparison across providers.
struct EnsembleAnalysisView: View {
    let ensemble: EnsembleAnalysisResult
    let onSelectResult: (EnsembleProviderResult) -> Void

    @State private var selectedProviderID: AIProviderID?
    @State private var selectedTab: EnsembleComparisonTab = .providers

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: "rectangle.split.3x1")
                    .foregroundColor(.accentColor)
                Text("Ensemble Comparison")
                    .font(.headline)
                Spacer()
                Text("\(ensemble.successfulResults.count)/\(ensemble.providerResults.count) providers succeeded")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Arbitration badge
            if ensemble.arbitratedResult != nil {
                HStack(spacing: 4) {
                    Image(systemName: "apple.logo")
                        .font(.caption2)
                        .foregroundColor(.accentColor)
                    Text("Arbitrated by Apple Intelligence")
                        .font(.caption2.bold())
                        .foregroundColor(.accentColor)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.accentColor.opacity(0.1))
                .cornerRadius(6)
            }

            // Tab picker
            Picker("View", selection: $selectedTab) {
                ForEach(EnsembleComparisonTab.allCases) { tab in
                    Label(tab.rawValue, systemImage: tab.iconName)
                        .tag(tab)
                }
            }
            .pickerStyle(.segmented)

            // Tab content
            switch selectedTab {
            case .providers:
                ScrollView(.horizontal, showsIndicators: true) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(ensemble.providerResults) { result in
                            ensembleCard(for: result)
                        }
                    }
                    .padding(.vertical, 4)
                }
            case .semanticDiff:
                EnsembleSemanticDiffView(
                    ensemble: ensemble,
                    arbitratedResult: ensemble.arbitratedResult
                )
            }
        }
        .padding(12)
        .background(.regularMaterial)
        .cornerRadius(16)
    }

    @ViewBuilder
    private func ensembleCard(for result: EnsembleProviderResult) -> some View {
        let isSelected = selectedProviderID == result.providerID
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: result.providerID.iconName)
                    .foregroundColor(result.isSuccess ? .accentColor : .red)
                Text(result.providerID.displayName)
                    .font(.subheadline.bold())
                Spacer()
            }

            if let error = result.error {
                // Error state
                HStack(spacing: 4) {
                    Image(systemName: "xmark.circle")
                        .foregroundColor(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .lineLimit(3)
                }
            } else {
                // Success metrics
                HStack(spacing: 12) {
                    Label(String(format: "%.1fs", result.durationSeconds), systemImage: "clock")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let tokens = result.tokenUsage {
                        Label("\(tokens.totalTokens) tokens", systemImage: "number")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Structured output summary
                if let structured = result.response.structured {
                    VStack(alignment: .leading, spacing: 4) {
                        if let summary = structured.summary, !summary.isEmpty {
                            Text(summary)
                                .font(.caption)
                                .lineLimit(4)
                        }
                        HStack(spacing: 8) {
                            countBadge(count: structured.insights.count, label: "Insights", color: .blue)
                            countBadge(count: structured.risks.count, label: "Risks", color: .orange)
                            countBadge(count: structured.actions.count, label: "Actions", color: .green)
                        }
                    }
                } else if !result.response.text.isEmpty {
                    Text(result.response.text)
                        .font(.caption)
                        .lineLimit(6)
                        .foregroundColor(.primary)
                }

                // Use This button
                Button("Use This") {
                    selectedProviderID = result.providerID
                    onSelectResult(result)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(12)
        .frame(width: 240, alignment: .topLeading)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .background(.thinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.accentColor : Color.white.opacity(0.1), lineWidth: isSelected ? 2 : 1)
        )
        .cornerRadius(12)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(result.providerID.displayName) result")
        .accessibilityIdentifier("ensembleCard_\(result.providerID.rawValue)")
    }

    private func countBadge(count: Int, label: String, color: Color) -> some View {
        HStack(spacing: 2) {
            Text("\(count)")
                .font(.caption2.bold())
            Text(label)
                .font(.caption2)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.15))
        .foregroundColor(color)
        .cornerRadius(6)
    }
}
