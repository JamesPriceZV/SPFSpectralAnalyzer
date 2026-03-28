import Foundation

// MARK: - AI Provider Protocol

/// Abstraction over different AI backends (OpenAI cloud, Apple FoundationModels on-device).
/// Each provider accepts a payload + prompt and returns a `ParsedAIResponse`.
protocol AIAnalysisProvider: Sendable {
    /// Human-readable name shown in the UI (e.g. "Apple Intelligence", "OpenAI").
    var displayName: String { get }

    /// Whether this provider is currently available for use.
    func isAvailable() -> Bool

    /// Run analysis and return a parsed response.
    func analyze(payload: AIRequestPayload, prompt: String, structuredOutputEnabled: Bool) async throws -> ParsedAIResponse
}

// MARK: - AI Provider Preference

/// User preference for which AI provider to use.
enum AIProviderPreference: String, CaseIterable, Identifiable, Codable {
    case auto
    case onDevice
    case openAI

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: return "Auto"
        case .onDevice: return "Apple Intelligence"
        case .openAI: return "OpenAI"
        }
    }

    var description: String {
        switch self {
        case .auto: return "Use Apple Intelligence when available, fall back to OpenAI"
        case .onDevice: return "Always use on-device Apple Intelligence (no network required)"
        case .openAI: return "Always use OpenAI cloud API"
        }
    }
}

// MARK: - AI Provider Error

enum AIProviderError: LocalizedError {
    case noProviderAvailable
    case onDeviceModelUnavailable(String)
    case onDeviceGenerationFailed(String)

    var errorDescription: String? {
        switch self {
        case .noProviderAvailable:
            return "No AI provider is available. Check that Apple Intelligence is enabled or configure an OpenAI API key."
        case .onDeviceModelUnavailable(let reason):
            return "On-device model unavailable: \(reason)"
        case .onDeviceGenerationFailed(let reason):
            return "On-device generation failed: \(reason)"
        }
    }
}
