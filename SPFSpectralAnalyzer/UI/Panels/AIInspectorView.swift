import SwiftUI

// MARK: - AI Tab View

/// Full-width AI analysis tab content.
/// Defined as a ContentView extension to access @AppStorage properties
/// and existing AI helper methods without passing dozens of bindings.
extension ContentView {

    var aiTabContent: some View {
        NavigationStack {
            ScrollView {
                aiTabLayout
                    .padding(.vertical, 12)
            }
            .scrollEdgeEffectStyle(.soft, for: .bottom)
            .navigationTitle("AI Analysis")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        .sheet(isPresented: $aiVM.showEnsembleComparison) {
            if let ensemble = aiVM.providerManager.ensembleResult {
                NavigationStack {
                    ScrollView {
                        EnsembleAnalysisView(ensemble: ensemble) { selectedResult in
                            let result = AIAnalysisResult(
                                text: selectedResult.response.text,
                                createdAt: Date(),
                                preset: aiPromptPreset,
                                selectionScope: effectiveAIScope
                            )
                            aiVM.result = result
                            aiVM.structuredOutput = selectedResult.response.structured
                            aiVM.providerManager.adoptProviderResult(
                                providerName: selectedResult.providerID.displayName,
                                providerID: selectedResult.providerID
                            )
                            aiVM.showEnsembleComparison = false
                        }
                        .padding()
                    }
                    .navigationTitle("Ensemble Comparison")
                    #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") {
                                aiVM.showEnsembleComparison = false
                            }
                        }
                    }
                }
                .presentationDetents([.large])
            }
        }
        .sheet(isPresented: $aiVM.showResponsePopup) {
            aiResponsePopupView
        }
    }

    // MARK: - Adaptive Layout

    @ViewBuilder
    private var aiTabLayout: some View {
        #if os(iOS)
        if horizontalSizeClass == .regular {
            // iPad: two-column
            aiTabTwoColumn
        } else {
            // iPhone compact: single column
            aiTabSingleColumn
        }
        #else
        // macOS: two-column grid
        aiTabTwoColumn
        #endif
    }

    private var aiTabTwoColumn: some View {
        HStack(alignment: .top, spacing: 16) {
            // Left column: controls + PINN
            VStack(spacing: 16) {
                aiTabProviderBadge
                aiTabQuickAnalysis
                aiTabCustomPrompt
                aiTabPINNSection
                aiTabTokenBudget
                Spacer(minLength: 0)
            }
            .frame(minWidth: 300, idealWidth: 380, maxWidth: 480)

            // Right column: results
            VStack(spacing: 16) {
                if aiVM.result != nil || aiVM.isRunning {
                    aiTabResponse
                }
                if let structured = aiVM.structuredOutput {
                    aiTabStructuredOutput(structured)
                }
                if aiVM.result != nil {
                    aiTabKeyInsights
                }
                if let ensemble = aiVM.ensembleResult,
                   ensemble.providerResults.count > 1 {
                    aiTabEnsembleSection(ensemble)
                }
                if aiVM.isEnterpriseGrounded && !aiVM.groundingCitations.isEmpty {
                    EnterpriseCitationsPanel(citations: aiVM.groundingCitations)
                        .padding(.horizontal, 12)
                }
                if aiVM.result == nil && !aiVM.isRunning {
                    aiTabEmptyState
                }
                Spacer(minLength: 0)
            }
            .frame(minWidth: 400, idealWidth: 500)
        }
        .padding(.horizontal, 16)
    }

    private var aiTabSingleColumn: some View {
        VStack(spacing: 16) {
            aiTabProviderBadge
            aiTabQuickAnalysis

            if aiVM.result != nil || aiVM.isRunning {
                aiTabResponse
            }
            if let structured = aiVM.structuredOutput {
                aiTabStructuredOutput(structured)
            }
            if aiVM.result != nil {
                aiTabKeyInsights
            }
            if let ensemble = aiVM.ensembleResult,
               ensemble.providerResults.count > 1 {
                aiTabEnsembleSection(ensemble)
            }
            if aiVM.isEnterpriseGrounded && !aiVM.groundingCitations.isEmpty {
                EnterpriseCitationsPanel(citations: aiVM.groundingCitations)
                    .padding(.horizontal, 12)
            }

            aiTabPINNSection
            aiTabCustomPrompt
            aiTabTokenBudget
        }
    }

    // MARK: - Empty State

    private var aiTabEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("No AI output yet")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Select datasets in the Analysis tab, then run AI analysis to get insights, structured recommendations, and physics-informed predictions.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    // MARK: - Provider Badge

    private var aiTabProviderBadge: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if let providerName = aiVM.providerManager.activeProviderName {
                    Image(systemName: providerName == "Apple Intelligence" ? "apple.intelligence" : "cloud")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(providerName)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else {
                    let isOnDevice = aiVM.providerManager.isOnDeviceAvailable
                    Circle()
                        .fill(isOnDevice ? Color.green : Color.orange)
                        .frame(width: 6, height: 6)
                    Text(isOnDevice ? "On-device ready" : "Cloud only")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
                EnterpriseGroundingBadge(
                    isSignedIn: aiVM.m365AuthManager.isSignedIn,
                    isGrounded: aiVM.isEnterpriseGrounded,
                    citationCount: aiVM.groundingCitations.count
                )
            }

            // Provider key status indicators (shown after startup verification)
            if aiVM.startupVerificationComplete {
                HStack(spacing: 8) {
                    ForEach(aiVM.providerKeyStatuses) { status in
                        HStack(spacing: 3) {
                            Circle()
                                .fill(providerStatusColor(status))
                                .frame(width: 5, height: 5)
                            Text(providerShortName(status.id))
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                        .help("\(status.name): \(status.detail)")
                    }
                }
            }
        }
        .padding(.horizontal, 12)
    }

    private func providerStatusColor(_ status: AIViewModel.ProviderKeyStatus) -> Color {
        if !status.hasKey { return .gray }
        if let connected = status.connectionVerified {
            return connected ? .green : .orange
        }
        return .yellow
    }

    private func providerShortName(_ id: AIProviderID) -> String {
        switch id {
        case .onDevice: return "Local"
        case .pinnOnDevice: return "PINN"
        case .openAI: return "GPT"
        case .claude: return "Claude"
        case .grok: return "Grok"
        case .gemini: return "Gemini"
        case .microsoft: return "M365"
        }
    }

    // MARK: - Quick Analysis

    private var aiTabQuickAnalysis: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick Analysis")
                .font(.headline)

            if !aiEnabled {
                Text("AI analysis is disabled. Enable it in Settings.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Picker("Scope", selection: Binding(
                get: { effectiveAIScope },
                set: { aiVM.scopeOverride = $0 }
            )) {
                ForEach(AISelectionScope.allCases) { scope in
                    Text(scope.label).tag(scope)
                }
            }
            .pickerStyle(.segmented)

            Picker("Preset", selection: Binding(
                get: { aiPromptPreset },
                set: { aiPromptPreset = $0 }
            )) {
                ForEach(AIPromptPreset.allCases) { preset in
                    Text(preset.label).tag(preset)
                }
            }
            .disabled(aiVM.useCustomPrompt)

            Button(aiVM.isRunning ? "Running..." : "Run AI Analysis") {
                runAIAnalysis()
            }
            .disabled(!aiCanRunAnalysis || aiVM.isRunning)
            .frame(maxWidth: .infinity)
            .buttonStyle(.glassProminent)

            if aiVM.isRunning {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }

            if let aiError = aiVM.errorMessage {
                Text(aiError)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            // Compare Providers button
            if let ensemble = aiVM.providerManager.ensembleResult,
               ensemble.successfulResults.count > 1 {
                Button {
                    aiVM.showEnsembleComparison = true
                } label: {
                    Label("Compare Providers", systemImage: "rectangle.split.3x1")
                }
                .frame(maxWidth: .infinity)
                .buttonStyle(.glass)
            }
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .padding(.horizontal, 12)
    }

    // MARK: - AI Response

    private var aiTabResponse: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("AI Response")
                    .font(.headline)
                Spacer()
                if aiVM.result != nil {
                    Button {
                        aiVM.showResponsePopup = true
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .help("Open AI response in a larger pop-up window")

                    if let result = aiVM.result {
                        ShareButton(items: [result.text], label: "Share", systemImage: "square.and.arrow.up")
                            .font(.caption)
                            .buttonStyle(.bordered)
                    }
                }
            }

            if aiVM.isRunning {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }

            if let aiResult = aiVM.result {
                ScrollView {
                    Text(aiResult.text)
                        .font(.system(size: aiResponseTextSize))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 160, maxHeight: 400)
            } else {
                Text("No AI output yet.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .padding(.horizontal, 12)
    }

    // MARK: - Structured Output

    private func aiTabStructuredOutput(_ structured: AIStructuredOutput) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Structured Summary")
                .font(.headline)
            if let summary = structured.summary, !summary.isEmpty {
                Text(summary)
                    .font(.callout)
            }

            if let recommendations = structured.recommendations, !recommendations.isEmpty {
                Text("Recommendations")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                ForEach(recommendations) { rec in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(rec.ingredient) \u{2022} \(rec.amount)")
                            .font(.subheadline)
                        if let rationale = rec.rationale, !rationale.isEmpty {
                            Text(rationale)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(8)
                    .background(Color.white.opacity(0.04))
                    .cornerRadius(8)
                }
            }
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .padding(.horizontal, 12)
    }

    // MARK: - Key Insights

    private var aiTabKeyInsights: some View {
        VStack(alignment: .leading, spacing: 8) {
            aiSidebarEditableSection("Key Insights", text: $aiVM.sidebarInsightsText)
            aiSidebarEditableSection("Risks/Warnings", text: $aiVM.sidebarRisksText)
            aiSidebarEditableSection("Next Steps", text: $aiVM.sidebarActionsText)

            HStack(spacing: 8) {
                Button("Sync back to response") {
                    syncSidebarToAIResponse()
                }
                .buttonStyle(.bordered)
                .font(.caption)

                if !aiVM.sidebarHasStructuredSections {
                    Text("No structured headings found.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .padding(.horizontal, 12)
        .onAppear {
            if let result = aiVM.result {
                updateSidebarFromAIResult(result)
            }
        }
        .onChange(of: aiVM.result?.text) { _, _ in
            if let result = aiVM.result {
                updateSidebarFromAIResult(result)
            }
        }
    }

    // MARK: - Ensemble Section

    private func aiTabEnsembleSection(_ ensemble: EnsembleAnalysisResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ensemble Comparison")
                .font(.headline)
            Text("\(ensemble.successfulResults.count) providers responded")
                .font(.caption)
                .foregroundColor(.secondary)

            EnsembleAnalysisView(ensemble: ensemble) { selectedResult in
                aiVM.selectedEnsembleProviderID = selectedResult.providerID
                let result = AIAnalysisResult(
                    text: selectedResult.response.text,
                    createdAt: Date(),
                    preset: aiPromptPreset,
                    selectionScope: effectiveAIScope
                )
                aiVM.result = result
                aiVM.structuredOutput = selectedResult.response.structured
                updateSidebarFromAIResult(result)
            }
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .padding(.horizontal, 12)
    }

    // MARK: - Custom Prompt

    private var aiTabCustomPrompt: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Custom Prompt")
                    .font(.headline)
                Spacer()
                Toggle("Use", isOn: $aiVM.useCustomPrompt)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            if aiVM.useCustomPrompt {
                ZStack(alignment: .topLeading) {
                    if aiVM.customPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Describe the analysis you want...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 8)
                            .padding(.horizontal, 6)
                    }
                    TextEditor(text: $aiVM.customPrompt)
                        .frame(minHeight: 80, maxHeight: 160)
                }
                .padding(8)
                .glassEffect(.regular, in: .rect(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
            }
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .padding(.horizontal, 12)
    }

    // MARK: - PINN Domain Status

    private var aiTabPINNSection: some View {
        let pinnService = PINNPredictionService.shared
        // Read loadVersion to trigger re-render when models finish loading.
        // Domain models are reference types (not @Observable), so their
        // status mutations are invisible to SwiftUI without this.
        let _ = pinnService.registry.loadVersion

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("PINN Physics Models")
                    .font(.headline)
                Spacer()
                Text("\(pinnService.readyModelCount)/\(PINNDomain.allCases.count) ready")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            ForEach(PINNDomain.allCases) { domain in
                let model = pinnService.registry.models[domain]
                let status = model?.status ?? .notTrained
                HStack(spacing: 8) {
                    Image(systemName: domain.iconName)
                        .frame(width: 20)
                        .foregroundColor(status.isReady ? .accentColor : .secondary)
                    Text(domain.displayName)
                        .font(.subheadline)
                    Spacer()
                    pinnStatusBadge(status)
                }
                .padding(.vertical, 2)
            }
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .padding(.horizontal, 12)
    }

    @ViewBuilder
    private func pinnStatusBadge(_ status: PINNModelStatus) -> some View {
        switch status {
        case .ready:
            Label("Ready", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundColor(.green)
        case .loading:
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.mini)
                Text("Loading")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        case .notTrained:
            Text("Not Trained")
                .font(.caption)
                .foregroundColor(.secondary)
        case .error(let msg):
            Label(msg, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundColor(.red)
                .lineLimit(1)
        }
    }

    // MARK: - Token Budget

    private var aiTabTokenBudget: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Token Budget")
                .font(.headline)
            ProgressView(value: min(Double(aiVM.estimatedTokens), Double(aiMaxTokens)), total: Double(max(aiMaxTokens, 1)))
            Text("Estimated tokens: \(aiVM.estimatedTokens) / \(aiMaxTokens)")
                .font(.caption)
                .foregroundColor(.secondary)
            if aiVM.estimatedTokens > aiMaxTokens {
                Text("Warning: estimated output may be truncated.")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
            HStack(spacing: 12) {
                Slider(value: $aiCostPerThousandTokens, in: 0.0...0.2, step: 0.005)
                Text(String(format: "$%.3f/1K", aiCostPerThousandTokens))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 70, alignment: .trailing)
            }
            let estimatedCost = (Double(aiVM.estimatedTokens) / 1000.0) * aiCostPerThousandTokens
            Text(String(format: "Estimated cost: $%.3f", estimatedCost))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .padding(.horizontal, 12)
    }
}
