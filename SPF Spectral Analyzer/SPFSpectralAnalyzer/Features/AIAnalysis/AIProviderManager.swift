import Foundation
import Observation

// MARK: - AI Provider Manager

/// Manages AI provider selection with automatic fallback.
/// Observable so SwiftUI views can react to provider state changes.
@MainActor @Observable
final class AIProviderManager {

    // MARK: - State

    /// The provider that was actually used for the most recent analysis.
    private(set) var activeProviderName: String?

    /// Whether the on-device model is currently available.
    var isOnDeviceAvailable: Bool {
        onDeviceProvider.isAvailable()
    }

    /// Human-readable status of the on-device model.
    var onDeviceStatusText: String {
        onDeviceProvider.statusText
    }

    // MARK: - Providers

    private let onDeviceProvider = FoundationModelsProvider()

    // MARK: - Provider Resolution

    /// Returns the best available provider based on user preference and availability.
    /// For `.auto`: tries on-device first, falls back to OpenAI.
    /// For `.onDevice` / `.openAI`: uses only the selected provider.
    func bestAvailableProvider(
        preference: AIProviderPreference,
        openAIEndpoint: String,
        openAIModel: String,
        openAIAPIKey: String?,
        temperature: Double,
        maxTokens: Int
    ) throws -> AIAnalysisProvider {
        switch preference {
        case .auto:
            if onDeviceProvider.isAvailable() {
                return onDeviceProvider
            }
            let openAI = makeOpenAIProvider(
                endpoint: openAIEndpoint,
                model: openAIModel,
                apiKey: openAIAPIKey,
                temperature: temperature,
                maxTokens: maxTokens
            )
            if openAI.isAvailable() {
                return openAI
            }
            throw AIProviderError.noProviderAvailable

        case .onDevice:
            guard onDeviceProvider.isAvailable() else {
                throw AIProviderError.onDeviceModelUnavailable(onDeviceStatusText)
            }
            return onDeviceProvider

        case .openAI:
            let openAI = makeOpenAIProvider(
                endpoint: openAIEndpoint,
                model: openAIModel,
                apiKey: openAIAPIKey,
                temperature: temperature,
                maxTokens: maxTokens
            )
            guard openAI.isAvailable() else {
                throw AIProviderError.noProviderAvailable
            }
            return openAI
        }
    }

    /// Run analysis using the resolved provider. Updates `activeProviderName`.
    func analyze(
        preference: AIProviderPreference,
        payload: AIRequestPayload,
        prompt: String,
        structuredOutputEnabled: Bool,
        openAIEndpoint: String,
        openAIModel: String,
        openAIAPIKey: String?,
        temperature: Double,
        maxTokens: Int
    ) async throws -> ParsedAIResponse {
        let provider = try bestAvailableProvider(
            preference: preference,
            openAIEndpoint: openAIEndpoint,
            openAIModel: openAIModel,
            openAIAPIKey: openAIAPIKey,
            temperature: temperature,
            maxTokens: maxTokens
        )

        activeProviderName = provider.displayName

        Instrumentation.log(
            "AI analysis using \(provider.displayName)",
            area: .aiAnalysis,
            level: .info,
            details: "preference=\(preference.rawValue)"
        )

        return try await provider.analyze(
            payload: payload,
            prompt: prompt,
            structuredOutputEnabled: structuredOutputEnabled
        )
    }

    // MARK: - Helpers

    private func makeOpenAIProvider(
        endpoint: String,
        model: String,
        apiKey: String?,
        temperature: Double,
        maxTokens: Int
    ) -> OpenAIProvider {
        OpenAIProvider(
            endpoint: endpoint,
            model: model,
            apiKey: apiKey ?? "",
            temperature: temperature,
            maxTokens: maxTokens
        )
    }
}
