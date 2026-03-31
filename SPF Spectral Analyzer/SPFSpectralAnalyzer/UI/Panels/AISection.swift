import SwiftUI

extension ContentView {

    var aiAnalysisSection: some View {
        DisclosureGroup("AI Analysis", isExpanded: $aiVM.showSection) {
            VStack(alignment: .leading, spacing: 12) {
                // AI Controls (from aiLeftPane)
                aiLeftPane

                Divider()

                // Custom prompt & response (from aiRightPane)
                aiRightPane
            }
        }
        .padding(12)
        .background(panelBackground)
        .cornerRadius(16)
    }

    var aiLeftPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("AI Controls")
                            .font(.headline)
                        Spacer()
                        Button(aiVM.showDetails ? "Collapse" : "Expand") {
                            aiVM.showDetails.toggle()
                        }
                        .buttonStyle(.plain)
                    }

                    if aiVM.showDetails {
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

                        Toggle("Structured JSON Output", isOn: $aiStructuredOutputEnabled)
                            .toggleStyle(.switch)
                            .help("Use JSON schema responses for structured insights and recommendations.")

                        if aiStructuredOutputEnabled {
                            let supported = isStructuredOutputSupported(aiOpenAIModel)
                            HStack(spacing: 8) {
                                Text(supported
                                     ? "Structured output is enabled and will populate recommendations when available."
                                     : "Structured output will use compatibility mode for this model; JSON parsing may be less reliable.")
                                    .font(.caption2)
                                    .foregroundColor(supported ? .secondary : .orange)

                                if !supported {
                                    Text("Compatibility")
                                        .font(.caption2)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 2)
                                        .background(Color.orange.opacity(0.2))
                                        .foregroundColor(.orange)
                                        .cornerRadius(6)
                                        .help("Compatibility mode: this model does not support JSON schema output natively. The app will prompt for JSON and extract it heuristically; occasional parsing issues are possible.")
                                }
                            }
                        }

                        Button(aiVM.isRunning ? "Running…" : "Run AI Analysis") {
                            runAIAnalysis()
                        }
                        .disabled(!aiCanRunAnalysis || aiVM.isRunning)
                        .frame(maxWidth: .infinity)
                        .glassButtonStyle(isProminent: true)

                        // Active provider badge
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
                        }

                        if aiVM.isRunning {
                            ProgressView()
                        }

                        if let aiError = aiVM.errorMessage {
                            Text(aiError)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                }
                .padding(12)
                .background(panelBackground)
                .cornerRadius(16)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Template Gallery")
                        .font(.headline)
                    ForEach(aiPresetTemplates, id: \.preset) { item in
                        HStack(alignment: .top, spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.preset.label)
                                    .font(.subheadline)
                                Text(item.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button("Use") {
                                aiVM.useCustomPrompt = false
                                aiPromptPreset = item.preset
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(8)
                        .background(Color.white.opacity(0.04))
                        .cornerRadius(8)
                    }
                }
                .padding(12)
                .background(panelBackground)
                .cornerRadius(16)

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
                .background(panelBackground)
                .cornerRadius(16)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Response History")
                        .font(.headline)
                    if aiVM.historyEntries.isEmpty {
                        Text("No prior AI responses yet.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(aiVM.historyEntries) { entry in
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(formattedTimestamp(entry.timestamp)) • \(entry.preset.label)")
                                        .font(.caption)
                                    Text("Scope: \(entry.scope.label)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Button("A") { aiVM.historySelectionA = entry.id }
                                    .buttonStyle(.bordered)
                                Button("B") { aiVM.historySelectionB = entry.id }
                                    .buttonStyle(.bordered)
                            }
                            .padding(6)
                            .background(Color.white.opacity(0.04))
                            .cornerRadius(8)
                        }

                        if let diffText = aiHistoryDiffText {
                            ScrollView {
                                Text(diffText)
                                    .font(.system(.caption, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 160)
                            .padding(6)
                            .background(Color.black.opacity(0.15))
                            .cornerRadius(8)
                        }
                    }
                }
                .padding(12)
                .background(panelBackground)
                .cornerRadius(16)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Run Context")
                        .font(.headline)
                    Text("Scope: \(effectiveAIScope.label)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Spectra: \(aiSpectraForScope().count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Estimated tokens: \(aiVM.estimatedTokens)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(12)
                .background(panelBackground)
                .cornerRadius(16)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Source Context")
                        .font(.headline)
                    let spectra = aiSpectraForScope()
                    if spectra.isEmpty {
                        Text("No spectra included.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        let preview = spectra.prefix(6)
                        ForEach(Array(preview.enumerated()), id: \.offset) { _, item in
                            Text(item.name)
                                .font(.caption)
                        }
                        if spectra.count > preview.count {
                            Text("+\(spectra.count - preview.count) more")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    Text("YAxis: \(analysis.yAxisMode.rawValue)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Metrics Range: \(Int(analysis.chartWavelengthRange.lowerBound))–\(Int(analysis.chartWavelengthRange.upperBound)) nm")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let header = activeHeader {
                        if !header.sourceInstrumentText.isEmpty {
                            Text("Instrument: \(header.sourceInstrumentText)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Text("X Units: \(header.xUnit.formatted)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Y Units: \(header.yUnit.formatted)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(12)
                .background(panelBackground)
                .cornerRadius(16)

                HStack(spacing: 8) {
                    Button("Logs…") {
                        openWindow(id: "diagnostics-console")
                    }
                    .glassButtonStyle()

                    if aiDiagnosticsEnabled {
                        Text("Diagnostics On")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(12)
        }
        .background(panelBackground)
        .cornerRadius(16)
    }

    var aiRightPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Custom Prompt")
                            .font(.headline)
                        Spacer()
                        Toggle("Use", isOn: $aiVM.useCustomPrompt)
                            .toggleStyle(.switch)
                    }

                    ZStack(alignment: .topLeading) {
                        if aiVM.customPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("Describe the analysis you want, constraints, and preferred output format.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.top, 8)
                                .padding(.horizontal, 6)
                        }
                        TextEditor(text: $aiVM.customPrompt)
                            .frame(minHeight: 100, maxHeight: 140)
                            .disabled(!aiVM.useCustomPrompt)
                    }
                    .padding(8)
                    .background(panelBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                    .cornerRadius(12)
                }
                .padding(12)
                .background(panelBackground)
                .cornerRadius(16)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Preset")
                        .font(.headline)
                    Picker("Preset", selection: Binding(
                        get: { aiPromptPreset },
                        set: { aiPromptPreset = $0 }
                    )) {
                        ForEach(AIPromptPreset.allCases) { preset in
                            Text(preset.label).tag(preset)
                        }
                    }
                    .disabled(aiVM.useCustomPrompt)
                }
                .padding(12)
                .background(panelBackground)
                .cornerRadius(16)

                // MARK: Ensemble Comparison
                if let ensemble = aiVM.ensembleResult, ensemble.providerResults.count > 1 {
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

                // MARK: Key Insights / Risks / Next Steps (full-width)
                if aiVM.result != nil {
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
                    .background(panelBackground)
                    .cornerRadius(16)
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

                // MARK: Structured Summary
                if let structured = aiVM.structuredOutput {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Structured Summary")
                            .font(.headline)
                        if let summary = structured.summary, !summary.isEmpty {
                            Text(summary)
                                .font(.caption)
                        }

                        if let recommendations = structured.recommendations, !recommendations.isEmpty {
                            Text("Recommendations")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            ForEach(recommendations) { rec in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(rec.ingredient) • \(rec.amount)")
                                        .font(.caption)
                                    if let rationale = rec.rationale, !rationale.isEmpty {
                                        Text(rationale)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(6)
                                .background(Color.white.opacity(0.04))
                                .cornerRadius(8)
                            }
                        }
                    }
                    .padding(12)
                    .background(panelBackground)
                    .cornerRadius(16)
                } else if aiStructuredOutputEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Structured Summary")
                            .font(.headline)
                        Text("Structured output is enabled. Run AI analysis to populate recommendations.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(12)
                    .background(panelBackground)
                    .cornerRadius(16)
                }

                // MARK: AI Response
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("AI Response")
                            .font(.headline)
                        Spacer()
                        if aiVM.result != nil {
                            Button {
                                aiVM.showResponsePopup = true
                            } label: {
                                Label("Expand", systemImage: "arrow.up.left.and.arrow.down.right")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .help("Open AI response in a larger pop-up window")

                            if let result = aiVM.result {
                                ShareButton(items: [result.text], label: "Share", systemImage: "square.and.arrow.up")
                                    .font(.caption)
                                    .buttonStyle(.bordered)
                                    .help("Share AI analysis results")
                            }
                        }
                    }

                    if let aiResult = aiVM.result {
                        ScrollView {
                            Text(aiResult.text)
                                .font(.system(size: aiResponseTextSize))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(minHeight: 160, maxHeight: 300)
                    } else {
                        Text("No AI output yet.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(12)
                .background(panelBackground)
                .cornerRadius(16)
                .sheet(isPresented: $aiVM.showResponsePopup) {
                    aiResponsePopupView
                }
            }
            .padding(12)
        }
        .background(panelBackground)
        .cornerRadius(16)
    }

}
