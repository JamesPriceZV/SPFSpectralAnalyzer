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

    // MARK: - Provider Factory

    /// Create a provider instance by ID. Returns nil if credentials are insufficient.
    func makeProvider(for id: AIProviderID, credentials: ProviderCredentials) -> AIAnalysisProvider? {
        switch id {
        case .onDevice:
            return onDeviceProvider.isAvailable() ? onDeviceProvider : nil
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
            case .gemini:
                if characteristics.isLongQualitative { score += 3 }
            case .grok:
                score += 0.5
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
            throw AIProviderError.noProviderAvailable
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
        let providers: [(AIProviderID, AIAnalysisProvider)] = providerIDs.compactMap { id in
            if let p = makeProvider(for: id, credentials: credentials) { return (id, p) }
            return nil
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

        let ensemble = EnsembleAnalysisResult(providerResults: results, timestamp: Date())
        ensembleResult = ensemble
        return ensemble
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
        // Ensemble mode (spectral analysis only)
        if function == .spectralAnalysis && ensembleConfig.isValid {
            let ensemble = await analyzeEnsemble(
                config: ensembleConfig,
                function: function,
                payload: payload,
                prompt: prompt,
                structuredOutputEnabled: structuredOutputEnabled,
                credentials: credentials
            )
            guard let first = ensemble.successfulResults.first else {
                throw AIProviderError.noProviderAvailable
            }
            activeProviderName = first.providerID.displayName
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
