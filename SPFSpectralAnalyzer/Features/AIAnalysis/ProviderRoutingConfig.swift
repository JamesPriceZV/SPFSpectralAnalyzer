import Foundation

// MARK: - Provider Identity

/// Canonical identifier for each AI provider.
/// Used as stable keys in priority queues, function assignments, and usage tracking.
enum AIProviderID: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case onDevice
    case pinnOnDevice
    case claude
    case openAI
    case grok
    case gemini
    case microsoft

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .onDevice:      return "Apple Intelligence"
        case .pinnOnDevice:  return "PINN On-Device"
        case .claude:        return "Anthropic Claude"
        case .openAI:        return "OpenAI"
        case .grok:          return "xAI Grok"
        case .gemini:        return "Google Gemini"
        case .microsoft:     return "Microsoft Enterprise"
        }
    }

    var iconName: String {
        switch self {
        case .onDevice:      return "apple.logo"
        case .pinnOnDevice:  return "brain"
        case .claude:        return "cloud.fill"
        case .openAI:        return "cloud"
        case .grok:          return "bolt.fill"
        case .gemini:        return "sparkles"
        case .microsoft:     return "building.2.fill"
        }
    }

    /// The API hostname used for DNS reachability checks.
    var apiHostname: String? {
        switch self {
        case .onDevice:      return nil  // on-device, no network needed
        case .pinnOnDevice:  return nil  // on-device CoreML, no network needed
        case .claude:        return "api.anthropic.com"
        case .openAI:        return "api.openai.com"
        case .grok:          return "api.x.ai"
        case .gemini:        return "generativelanguage.googleapis.com"
        case .microsoft:     return "graph.microsoft.com"
        }
    }

    /// Default priority order used when the user hasn't customized.
    static var defaultPriorityOrder: [AIProviderID] {
        [.onDevice, .pinnOnDevice, .claude, .openAI, .grok, .gemini, .microsoft]
    }
}

// MARK: - App Functions (Option B)

/// Each distinct AI function in the app that can have its own provider assignment.
enum AIAppFunction: String, CaseIterable, Identifiable, Codable, Sendable {
    case spectralAnalysis
    case formulaCardParsing

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .spectralAnalysis:   return "Spectral Analysis"
        case .formulaCardParsing: return "Formula Card Parsing"
        }
    }

    var description: String {
        switch self {
        case .spectralAnalysis:
            return "AI analysis of UV spectral data for SPF estimation and formulation insights"
        case .formulaCardParsing:
            return "Extracting structured ingredient data from formula card documents"
        }
    }

    /// Task characteristics used by Smart routing (Option C).
    var taskCharacteristics: TaskCharacteristics {
        switch self {
        case .spectralAnalysis:
            return TaskCharacteristics(
                isStructuredExtraction: false,
                isNumericalAnalysis: true,
                isLongQualitative: true,
                requiresJSON: false
            )
        case .formulaCardParsing:
            return TaskCharacteristics(
                isStructuredExtraction: true,
                isNumericalAnalysis: false,
                isLongQualitative: false,
                requiresJSON: true
            )
        }
    }
}

/// Characteristics of a task used by Smart routing to pick the best provider.
struct TaskCharacteristics: Sendable {
    let isStructuredExtraction: Bool
    let isNumericalAnalysis: Bool
    let isLongQualitative: Bool
    let requiresJSON: Bool
}

// MARK: - Function-Specific Routing Preference (Option B + C)

/// What routing mode a specific function uses.
enum FunctionRoutingMode: Codable, Equatable, Hashable, Sendable {
    case auto
    case smart
    case specific(AIProviderID)

    enum CodingKeys: String, CodingKey {
        case type, providerID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "auto":  self = .auto
        case "smart": self = .smart
        case "specific":
            let id = try container.decode(AIProviderID.self, forKey: .providerID)
            self = .specific(id)
        default:
            self = .auto
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .auto:
            try container.encode("auto", forKey: .type)
        case .smart:
            try container.encode("smart", forKey: .type)
        case .specific(let id):
            try container.encode("specific", forKey: .type)
            try container.encode(id, forKey: .providerID)
        }
    }

    var displayName: String {
        switch self {
        case .auto: return "Auto (Priority Queue)"
        case .smart: return "Smart (Task-Based)"
        case .specific(let id): return id.displayName
        }
    }
}

// MARK: - Ensemble Configuration (Option D)

/// Configuration for ensemble/cross-validation mode.
struct EnsembleConfig: Codable, Sendable {
    var isEnabled: Bool = false
    var selectedProviders: Set<AIProviderID> = [.claude, .openAI]
    /// When true, an on-device AI arbitrator synthesizes all provider responses
    /// into a single unified analysis identifying consensus, disputes, and outliers.
    var arbitrationEnabled: Bool = true

    var isValid: Bool {
        isEnabled && selectedProviders.count >= 2
    }
}

/// Result from a single provider in ensemble mode.
struct EnsembleProviderResult: Identifiable, Sendable {
    let id = UUID()
    let providerID: AIProviderID
    let response: ParsedAIResponse
    let durationSeconds: Double
    let tokenUsage: TokenUsage?
    let error: String?

    var isSuccess: Bool { error == nil }
}

/// Aggregated ensemble results for display.
struct EnsembleAnalysisResult: Sendable {
    let providerResults: [EnsembleProviderResult]
    let timestamp: Date
    /// The arbitrated synthesis produced by the on-device model, if arbitration was enabled and succeeded.
    var arbitratedResult: ArbitratedEnsembleResult?

    var successfulResults: [EnsembleProviderResult] {
        providerResults.filter(\.isSuccess)
    }
}

/// Result of on-device arbitration synthesizing multiple provider responses.
struct ArbitratedEnsembleResult: Sendable {
    let unifiedSummary: String
    let consensusInsights: [String]
    let disputedFindings: [ArbitratedDispute]
    let outlierObservations: [String]
    let unifiedRisks: [String]
    let unifiedActions: [String]
    let unifiedRecommendations: [AIRecommendation]

    /// Converts to standard structured output for display in the AI Analysis panel.
    var asStructuredOutput: AIStructuredOutput {
        AIStructuredOutput(
            summary: unifiedSummary,
            insights: consensusInsights,
            risks: unifiedRisks,
            actions: unifiedActions,
            recommendations: unifiedRecommendations
        )
    }

    /// Converts to standard ParsedAIResponse for use as primary analysis result.
    var asParsedResponse: ParsedAIResponse {
        let structured = asStructuredOutput
        let text = OpenAIProvider.structuredText(from: structured)
        return ParsedAIResponse(text: text, structured: structured)
    }
}

/// A disputed finding between providers, resolved by the arbitrator.
struct ArbitratedDispute: Sendable, Identifiable {
    let id = UUID()
    let claim: String
    let supportingProviders: [String]
    let opposingProviders: [String]
    let resolution: String
}

// MARK: - Provider Credentials Bundle

/// Consolidates all provider credentials into a single Sendable value.
/// Replaces the 12+ parameters that were passed individually.
struct ProviderCredentials: Sendable {
    let openAIEndpoint: String
    let openAIModel: String
    let openAIAPIKey: String?
    let claudeModel: String
    let claudeAPIKey: String?
    let grokModel: String
    let grokAPIKey: String?
    let geminiModel: String
    let geminiAPIKey: String?
    let temperature: Double
    let maxTokens: Int
}

// MARK: - Token Usage & Cost Tracking (Option E)

/// Token usage from a single API call.
struct TokenUsage: Codable, Sendable {
    let promptTokens: Int
    let completionTokens: Int
    var totalTokens: Int { promptTokens + completionTokens }
}

/// Per-provider monthly budget cap.
struct ProviderBudgetCap: Codable, Identifiable, Sendable {
    var providerID: AIProviderID
    var monthlyBudgetUSD: Double
    var costPerInputToken: Double
    var costPerOutputToken: Double

    var id: AIProviderID { providerID }

    func estimatedCost(usage: TokenUsage) -> Double {
        Double(usage.promptTokens) * costPerInputToken
        + Double(usage.completionTokens) * costPerOutputToken
    }

    /// Sensible defaults per provider.
    static func defaults(for providerID: AIProviderID) -> ProviderBudgetCap {
        switch providerID {
        case .onDevice:
            return ProviderBudgetCap(providerID: providerID, monthlyBudgetUSD: 0, costPerInputToken: 0, costPerOutputToken: 0)
        case .claude:
            return ProviderBudgetCap(providerID: providerID, monthlyBudgetUSD: 10, costPerInputToken: 0.000003, costPerOutputToken: 0.000015)
        case .openAI:
            return ProviderBudgetCap(providerID: providerID, monthlyBudgetUSD: 10, costPerInputToken: 0.0000025, costPerOutputToken: 0.000010)
        case .grok:
            return ProviderBudgetCap(providerID: providerID, monthlyBudgetUSD: 10, costPerInputToken: 0.000003, costPerOutputToken: 0.000015)
        case .gemini:
            return ProviderBudgetCap(providerID: providerID, monthlyBudgetUSD: 10, costPerInputToken: 0.0000001, costPerOutputToken: 0.0000004)
        case .pinnOnDevice:
            return ProviderBudgetCap(providerID: providerID, monthlyBudgetUSD: 0, costPerInputToken: 0, costPerOutputToken: 0) // on-device, free
        case .microsoft:
            return ProviderBudgetCap(providerID: providerID, monthlyBudgetUSD: 0, costPerInputToken: 0, costPerOutputToken: 0) // M365 licensing, not per-token
        }
    }
}

/// A single usage log entry, persisted for monthly aggregation.
struct UsageLogEntry: Codable, Identifiable, Sendable {
    let id: UUID
    let providerID: AIProviderID
    let function: AIAppFunction
    let timestamp: Date
    let usage: TokenUsage
    let estimatedCostUSD: Double

    init(providerID: AIProviderID, function: AIAppFunction, timestamp: Date, usage: TokenUsage, estimatedCostUSD: Double) {
        self.id = UUID()
        self.providerID = providerID
        self.function = function
        self.timestamp = timestamp
        self.usage = usage
        self.estimatedCostUSD = estimatedCostUSD
    }
}

/// Monthly usage summary per provider, computed from log entries.
struct MonthlyUsageSummary: Sendable {
    let providerID: AIProviderID
    let month: Date
    let totalPromptTokens: Int
    let totalCompletionTokens: Int
    let totalCostUSD: Double
    let callCount: Int
}
