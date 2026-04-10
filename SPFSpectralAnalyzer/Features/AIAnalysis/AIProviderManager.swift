import Foundation
import Observation

// MARK: - AI Provider Manager

/// Manages AI provider selection with custom priority queue, function-specific routing,
/// smart routing, ensemble mode, and cost-aware filtering.
@MainActor @Observable
final class AIProviderManager {

    // MARK: - State

    /// The provider that was actually used for the most recent analysis.
    private(set) var activeProviderName: String?

    /// The provider ID that was actually used for the most recent analysis.
    private(set) var activeProviderID: AIProviderID?

    /// Ensemble results for side-by-side comparison (Option D).
    var ensembleResult: EnsembleAnalysisResult?

    /// The arbitrated synthesis from on-device AI, combining all ensemble responses.
    var arbitratedResult: ArbitratedEnsembleResult?

    /// Set when a requested specific provider was unavailable and we fell back.
    /// e.g. "xAI Grok unavailable (no API key) — using Apple Intelligence"
    var fallbackNotice: String?

    /// Whether the on-device model is currently available.
    var isOnDeviceAvailable: Bool {
        onDeviceProvider.isAvailable()
    }

    /// Human-readable status of the on-device model.
    var onDeviceStatusText: String {
        onDeviceProvider.statusText
    }

    // MARK: - Providers

    let onDeviceProvider = FoundationModelsProvider()

    /// Token usage and budget tracking.
    let usageTracker = ProviderUsageTracker()

    // MARK: - Provider Adoption

    /// Called when the user selects a specific provider result from the Ensemble Comparison view.
    func adoptProviderResult(providerName: String, providerID: AIProviderID) {
        activeProviderName = providerName
        activeProviderID = providerID
    }

    // MARK: - Provider Factory

    /// Create a provider instance by ID. Returns nil if credentials are insufficient.
    func makeProvider(for id: AIProviderID, credentials: ProviderCredentials) -> AIAnalysisProvider? {
        switch id {
        case .onDevice:
            return onDeviceProvider.isAvailable() ? onDeviceProvider : nil
        case .pinnOnDevice:
            let p = PINNAnalysisProvider(predictionService: PINNPredictionService.shared)
            return p.isAvailable() ? p : nil
        case .claude:
            let p = ClaudeProvider(
                model: credentials.claudeModel,
                apiKey: credentials.claudeAPIKey ?? "",
                maxTokens: credentials.maxTokens
            )
            return p.isAvailable() ? p : nil
        case .openAI:
            let p = OpenAIProvider(
                endpoint: credentials.openAIEndpoint,
                model: credentials.openAIModel,
                apiKey: credentials.openAIAPIKey ?? "",
                temperature: credentials.temperature,
                maxTokens: credentials.maxTokens
            )
            return p.isAvailable() ? p : nil
        case .grok:
            let p = GrokProvider(
                model: credentials.grokModel,
                apiKey: credentials.grokAPIKey ?? "",
                maxTokens: credentials.maxTokens
            )
            return p.isAvailable() ? p : nil
        case .gemini:
            let p = GeminiProvider(
                model: credentials.geminiModel,
                apiKey: credentials.geminiAPIKey ?? "",
                maxTokens: credentials.maxTokens
            )
            return p.isAvailable() ? p : nil
        case .microsoft:
            return nil  // Microsoft Enterprise uses Graph API, not a generative AI provider
        }
    }

    // MARK: - Priority Queue Resolution (Option A)

    /// Walk the user's custom priority order, skipping unavailable or over-budget providers.
    func resolveFromPriorityQueue(
        priorityOrder: [AIProviderID],
        credentials: ProviderCredentials,
        overBudgetIDs: Set<AIProviderID> = []
    ) throws -> (AIAnalysisProvider, AIProviderID) {
        for providerID in priorityOrder {
            if overBudgetIDs.contains(providerID) { continue }
            if let provider = makeProvider(for: providerID, credentials: credentials) {
                return (provider, providerID)
            }
        }
        throw AIProviderError.noProviderAvailable
    }

    // MARK: - Smart Routing (Option C)

    /// Re-rank the priority order based on task characteristics, then resolve.
    func resolveSmartProvider(
        function: AIAppFunction,
        priorityOrder: [AIProviderID],
        credentials: ProviderCredentials,
        overBudgetIDs: Set<AIProviderID> = []
    ) throws -> (AIAnalysisProvider, AIProviderID) {
        let ranked = smartRank(providers: priorityOrder, characteristics: function.taskCharacteristics)
        return try resolveFromPriorityQueue(
            priorityOrder: ranked,
            credentials: credentials,
            overBudgetIDs: overBudgetIDs
        )
    }

    /// Score and re-rank providers based on task characteristics.
    private func smartRank(
        providers: [AIProviderID],
        characteristics: TaskCharacteristics
    ) -> [AIProviderID] {
        var scored: [(AIProviderID, Double)] = providers.map { id in
            var score = 0.0
            switch id {
            case .claude:
                if characteristics.isStructuredExtraction { score += 3 }
                if characteristics.requiresJSON { score += 2 }
                if characteristics.isLongQualitative { score += 1 }
            case .openAI:
                if characteristics.isStructuredExtraction { score += 2 }
                if characteristics.requiresJSON { score += 2 }
            case .onDevice:
                if characteristics.isNumericalAnalysis { score += 3 }
                score += 1 // free bonus
            case .pinnOnDevice:
                if characteristics.isNumericalAnalysis { score += 4 }
                score += 1 // free, physics-informed bonus
            case .gemini:
                if characteristics.isLongQualitative { score += 3 }
            case .grok:
                score += 0.5
            case .microsoft:
                score += 0  // Not a generative AI provider
            }
            return (id, score)
        }
        scored.sort { $0.1 > $1.1 }
        return scored.map(\.0)
    }

    // MARK: - Function-Specific Resolution (Option B)

    /// Resolve the provider for a specific function based on routing config.
    func resolveProvider(
        for function: AIAppFunction,
        functionRouting: [AIAppFunction: FunctionRoutingMode],
        priorityOrder: [AIProviderID],
        credentials: ProviderCredentials,
        overBudgetIDs: Set<AIProviderID> = []
    ) throws -> (AIAnalysisProvider, AIProviderID) {
        let mode = functionRouting[function] ?? .auto
        switch mode {
        case .auto:
            return try resolveFromPriorityQueue(
                priorityOrder: priorityOrder,
                credentials: credentials,
                overBudgetIDs: overBudgetIDs
            )
        case .smart:
            return try resolveSmartProvider(
                function: function,
                priorityOrder: priorityOrder,
                credentials: credentials,
                overBudgetIDs: overBudgetIDs
            )
        case .specific(let providerID):
            if let provider = makeProvider(for: providerID, credentials: credentials) {
                return (provider, providerID)
            }
            // Requested provider unavailable — fall back to priority queue
            let fallback = try resolveFromPriorityQueue(
                priorityOrder: priorityOrder,
                credentials: credentials,
                overBudgetIDs: overBudgetIDs
            )
            fallbackNotice = "\(providerID.displayName) unavailable (no API key) — using \(fallback.1.displayName)"
            return fallback
        }
    }

    // MARK: - Ensemble Mode (Option D)

    /// Run analysis on multiple providers in parallel via TaskGroup.
    func analyzeEnsemble(
        config: EnsembleConfig,
        function: AIAppFunction,
        payload: AIRequestPayload,
        prompt: String,
        structuredOutputEnabled: Bool,
        credentials: ProviderCredentials
    ) async -> EnsembleAnalysisResult {
        let providerIDs = Array(config.selectedProviders)

        // Log which providers were requested and which are available
        var unavailableProviders: [String] = []
        let providers: [(AIProviderID, AIAnalysisProvider)] = providerIDs.compactMap { id in
            if let p = makeProvider(for: id, credentials: credentials) { return (id, p) }
            unavailableProviders.append(id.displayName)
            return nil
        }

        if !unavailableProviders.isEmpty {
            Instrumentation.log(
                "Ensemble: \(unavailableProviders.count) providers unavailable",
                area: .aiAnalysis, level: .warning,
                details: "unavailable=[\(unavailableProviders.joined(separator: ", "))] available=[\(providers.map(\.0.displayName).joined(separator: ", "))]"
            )
            fallbackNotice = "\(unavailableProviders.count) ensemble providers unavailable (\(unavailableProviders.joined(separator: ", "))) — check API keys in Settings"
        }

        let results = await withTaskGroup(of: EnsembleProviderResult.self) { group in
            for (id, provider) in providers {
                group.addTask { @Sendable [provider] in
                    let start = CFAbsoluteTimeGetCurrent()
                    do {
                        let response = try await provider.analyze(
                            payload: payload,
                            prompt: prompt,
                            structuredOutputEnabled: structuredOutputEnabled
                        )
                        let duration = CFAbsoluteTimeGetCurrent() - start
                        return EnsembleProviderResult(
                            providerID: id,
                            response: response,
                            durationSeconds: duration,
                            tokenUsage: response.tokenUsage,
                            error: nil
                        )
                    } catch {
                        let duration = CFAbsoluteTimeGetCurrent() - start
                        return EnsembleProviderResult(
                            providerID: id,
                            response: ParsedAIResponse(text: "", structured: nil),
                            durationSeconds: duration,
                            tokenUsage: nil,
                            error: error.localizedDescription
                        )
                    }
                }
            }
            var collected: [EnsembleProviderResult] = []
            for await result in group {
                collected.append(result)
            }
            return collected
        }

        var ensemble = EnsembleAnalysisResult(providerResults: results, timestamp: Date())

        // Arbitration: if enabled and 2+ providers succeeded with structured output,
        // use on-device AI to synthesize a unified analysis.
        if config.arbitrationEnabled && ensemble.successfulResults.count >= 2 {
            let arbitrated = await arbitrateResponses(ensemble.successfulResults)
            ensemble.arbitratedResult = arbitrated
            arbitratedResult = arbitrated
        } else {
            arbitratedResult = nil
        }

        ensembleResult = ensemble
        return ensemble
    }

    // MARK: - Ensemble Arbitration

    /// Use on-device FoundationModels to synthesize multiple provider responses
    /// into a single unified analysis identifying consensus, disputes, and outliers.
    private func arbitrateResponses(_ results: [EnsembleProviderResult]) async -> ArbitratedEnsembleResult? {
        guard onDeviceProvider.isAvailable() else {
            Instrumentation.log(
                "Ensemble arbitration skipped: on-device model unavailable",
                area: .aiAnalysis, level: .info,
                details: "statusText=\(onDeviceProvider.statusText)"
            )
            return nil
        }

        // Collect structured outputs from successful providers
        let providerResponses: [(providerName: String, structured: AIStructuredOutput)] = results.compactMap { result in
            guard let structured = result.response.structured else { return nil }
            return (providerName: result.providerID.displayName, structured: structured)
        }

        guard providerResponses.count >= 2 else {
            Instrumentation.log(
                "Ensemble arbitration skipped: fewer than 2 providers returned structured output",
                area: .aiAnalysis, level: .info
            )
            return nil
        }

        Instrumentation.log(
            "Starting ensemble arbitration with \(providerResponses.count) provider responses",
            area: .aiAnalysis, level: .info
        )

        do {
            let output = try await onDeviceProvider.synthesizeEnsemble(providerResponses: providerResponses)

            let disputes = output.disputedFindings.map { item in
                ArbitratedDispute(
                    claim: item.claim,
                    supportingProviders: item.supportingProviders,
                    opposingProviders: item.opposingProviders,
                    resolution: item.resolution
                )
            }

            let recommendations = output.unifiedRecommendations.map { rec in
                AIRecommendation(ingredient: rec.ingredient, amount: rec.amount, rationale: rec.rationale)
            }

            let result = ArbitratedEnsembleResult(
                unifiedSummary: output.unifiedSummary,
                consensusInsights: output.consensusInsights,
                disputedFindings: disputes,
                outlierObservations: output.outlierObservations,
                unifiedRisks: output.unifiedRisks,
                unifiedActions: output.unifiedActions,
                unifiedRecommendations: recommendations
            )

            Instrumentation.log(
                "Ensemble arbitration complete",
                area: .aiAnalysis, level: .info,
                details: "consensus=\(result.consensusInsights.count) disputed=\(result.disputedFindings.count) outliers=\(result.outlierObservations.count)"
            )

            return result
        } catch {
            Instrumentation.log(
                "Ensemble arbitration failed",
                area: .aiAnalysis, level: .warning,
                details: error.localizedDescription
            )
            return nil
        }
    }

    // MARK: - Unified Entry Point

    /// Primary analysis method. Routes based on function routing, ensemble, and cost awareness.
    func analyze(
        function: AIAppFunction,
        payload: AIRequestPayload,
        prompt: String,
        structuredOutputEnabled: Bool,
        priorityOrder: [AIProviderID],
        functionRouting: [AIAppFunction: FunctionRoutingMode],
        ensembleConfig: EnsembleConfig,
        credentials: ProviderCredentials,
        overBudgetIDs: Set<AIProviderID> = []
    ) async throws -> ParsedAIResponse {
        // Clear stale state from previous analysis but show resolving feedback
        activeProviderName = "Resolving\u{2026}"
        activeProviderID = nil
        fallbackNotice = nil
        arbitratedResult = nil

        // Ensemble mode (spectral analysis only)
        //
        // How ensemble final analysis is determined:
        // 1. All selected providers are queried in parallel via TaskGroup.
        // 2. Providers that fail (no API key, network error, etc.) are logged
        //    and excluded; their failure reasons appear in the diagnostics log
        //    and in the fallbackNotice banner.
        // 3. If arbitration is enabled and 2+ providers return structured output,
        //    an on-device FoundationModels session synthesizes all responses into
        //    a unified analysis identifying consensus, disputes, and outliers.
        //    The arbitrated result becomes the primary display.
        // 4. If arbitration is unavailable or disabled, the FIRST successful
        //    provider result (arrival order) is used as the primary display.
        // 5. All successful results are stored in `ensembleResult` and
        //    presented side-by-side in the Ensemble Comparison view, where
        //    the user can review each provider's response and the arbitration.
        if function == .spectralAnalysis && ensembleConfig.isValid {
            let ensemble = await analyzeEnsemble(
                config: ensembleConfig,
                function: function,
                payload: payload,
                prompt: prompt,
                structuredOutputEnabled: structuredOutputEnabled,
                credentials: credentials
            )
            let successful = ensemble.successfulResults
            guard let first = successful.first else {
                throw AIProviderError.noProviderAvailable
            }

            // Use arbitrated result as primary if available
            if let arbitrated = ensemble.arbitratedResult {
                if successful.count > 1 {
                    activeProviderName = "Arbitrated Ensemble (\(successful.count) providers)"
                } else {
                    activeProviderName = first.providerID.displayName
                }
                activeProviderID = .onDevice
                return arbitrated.asParsedResponse
            }

            // Fallback: use first-arrived result
            if successful.count > 1 {
                let totalRequested = ensembleConfig.selectedProviders.count
                if successful.count < totalRequested {
                    activeProviderName = "Ensemble (\(successful.count)/\(totalRequested) providers)"
                } else {
                    activeProviderName = "Ensemble (\(successful.count) providers)"
                }
            } else {
                activeProviderName = first.providerID.displayName
            }
            activeProviderID = first.providerID
            return first.response
        }

        // Standard routing
        let (provider, providerID) = try resolveProvider(
            for: function,
            functionRouting: functionRouting,
            priorityOrder: priorityOrder,
            credentials: credentials,
            overBudgetIDs: overBudgetIDs
        )

        activeProviderName = provider.displayName
        activeProviderID = providerID

        Instrumentation.log(
            "AI analysis using \(provider.displayName)",
            area: .aiAnalysis,
            level: .info,
            details: "function=\(function.rawValue) preference=\(functionRouting[function]?.displayName ?? "auto")"
        )

        return try await provider.analyze(
            payload: payload,
            prompt: prompt,
            structuredOutputEnabled: structuredOutputEnabled
        )
    }

    // MARK: - Legacy Compatibility

    /// Legacy analyze method for backward compatibility. Builds ProviderCredentials and delegates.
    func analyze(
        preference: AIProviderPreference,
        payload: AIRequestPayload,
        prompt: String,
        structuredOutputEnabled: Bool,
        openAIEndpoint: String,
        openAIModel: String,
        openAIAPIKey: String?,
        claudeModel: String,
        claudeAPIKey: String?,
        grokModel: String,
        grokAPIKey: String?,
        geminiModel: String,
        geminiAPIKey: String?,
        temperature: Double,
        maxTokens: Int
    ) async throws -> ParsedAIResponse {
        let credentials = ProviderCredentials(
            openAIEndpoint: openAIEndpoint,
            openAIModel: openAIModel,
            openAIAPIKey: openAIAPIKey,
            claudeModel: claudeModel,
            claudeAPIKey: claudeAPIKey,
            grokModel: grokModel,
            grokAPIKey: grokAPIKey,
            geminiModel: geminiModel,
            geminiAPIKey: geminiAPIKey,
            temperature: temperature,
            maxTokens: maxTokens
        )

        // Map legacy preference to function routing
        let functionRouting: [AIAppFunction: FunctionRoutingMode]
        switch preference {
        case .auto:
            functionRouting = [:]
        case .onDevice:
            functionRouting = [.spectralAnalysis: .specific(.onDevice)]
        case .claude:
            functionRouting = [.spectralAnalysis: .specific(.claude)]
        case .openAI:
            functionRouting = [.spectralAnalysis: .specific(.openAI)]
        case .grok:
            functionRouting = [.spectralAnalysis: .specific(.grok)]
        case .gemini:
            functionRouting = [.spectralAnalysis: .specific(.gemini)]
        }

        return try await analyze(
            function: .spectralAnalysis,
            payload: payload,
            prompt: prompt,
            structuredOutputEnabled: structuredOutputEnabled,
            priorityOrder: AIProviderID.defaultPriorityOrder,
            functionRouting: functionRouting,
            ensembleConfig: EnsembleConfig(),
            credentials: credentials
        )
    }
}
