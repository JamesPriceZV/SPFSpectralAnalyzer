import Foundation

#if canImport(FoundationModels)
import FoundationModels

// MARK: - Generable Output Types for On-Device AI

@Generable(description: "A formulation recommendation from spectral analysis")
struct OnDeviceRecommendation {
    @Guide(description: "Ingredient or active component name")
    var ingredient: String
    @Guide(description: "Suggested amount or adjustment")
    var amount: String
    @Guide(description: "Brief reasoning for this recommendation")
    var rationale: String
}

@Generable(description: "Structured spectral analysis output from on-device AI")
struct OnDeviceAnalysisOutput {
    @Guide(description: "One-paragraph summary of the spectral analysis")
    var summary: String
    @Guide(description: "Key findings from the spectral data", .maximumCount(5))
    var insights: [String]
    @Guide(description: "Risk items or warnings identified", .maximumCount(5))
    var risks: [String]
    @Guide(description: "Recommended next steps", .maximumCount(5))
    var actions: [String]
    @Guide(description: "Formulation recommendations if applicable", .maximumCount(3))
    var recommendations: [OnDeviceRecommendation]
}

// MARK: - FoundationModels Provider

/// AI provider that uses Apple's on-device FoundationModels framework.
/// Works fully offline — no network required.
struct FoundationModelsProvider: AIAnalysisProvider {
    let displayName = "Apple Intelligence"

    func isAvailable() -> Bool {
        SystemLanguageModel.default.isAvailable
    }

    /// Detailed availability status for UI display.
    var availabilityStatus: SystemLanguageModel.Availability {
        SystemLanguageModel.default.availability
    }

    /// Human-readable status text for the UI.
    var statusText: String {
        switch availabilityStatus {
        case .available:
            return "Available"
        case .unavailable(.deviceNotEligible):
            return "Device not eligible"
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Apple Intelligence disabled"
        case .unavailable(.modelNotReady):
            return "Model downloading…"
        case .unavailable(_):
            return "Unavailable"
        }
    }

    func analyze(payload: AIRequestPayload, prompt: String, structuredOutputEnabled: Bool) async throws -> ParsedAIResponse {
        guard isAvailable() else {
            let reason: String
            switch availabilityStatus {
            case .available:
                reason = "Unknown"
            case .unavailable(.deviceNotEligible):
                reason = "This device does not support Apple Intelligence."
            case .unavailable(.appleIntelligenceNotEnabled):
                reason = "Apple Intelligence is not enabled. Enable it in Settings."
            case .unavailable(.modelNotReady):
                reason = "The on-device model is still downloading."
            case .unavailable(_):
                reason = "The on-device model is unavailable."
            }
            throw AIProviderError.onDeviceModelUnavailable(reason)
        }

        let payloadSummary = buildPayloadSummary(payload)

        let instructions = """
            You are a spectral analysis assistant for UV/visible spectroscopy data \
            used in sunscreen (SPF) formulation analysis. Provide clear, actionable \
            insights about spectral data including UVA/UVB characteristics, critical \
            wavelength analysis, and formulation recommendations.
            """

        let fullPrompt = """
            \(prompt)

            Spectral data summary:
            \(payloadSummary)
            """

        if structuredOutputEnabled {
            return try await analyzeStructured(fullPrompt: fullPrompt, instructions: instructions)
        } else {
            return try await analyzePlainText(fullPrompt: fullPrompt, instructions: instructions)
        }
    }

    // MARK: - Structured Generation

    private func analyzeStructured(fullPrompt: String, instructions: String) async throws -> ParsedAIResponse {
        let session = LanguageModelSession(instructions: instructions)
        do {
            let response = try await session.respond(
                to: fullPrompt,
                generating: OnDeviceAnalysisOutput.self
            )
            let output = response.content
            let structured = AIStructuredOutput(
                summary: output.summary,
                insights: output.insights,
                risks: output.risks,
                actions: output.actions,
                recommendations: output.recommendations.map { rec in
                    AIRecommendation(ingredient: rec.ingredient, amount: rec.amount, rationale: rec.rationale)
                }
            )
            let text = OpenAIProvider.structuredText(from: structured)
            return ParsedAIResponse(text: text, structured: structured)
        } catch {
            throw AIProviderError.onDeviceGenerationFailed(error.localizedDescription)
        }
    }

    // MARK: - Plain Text Generation

    private func analyzePlainText(fullPrompt: String, instructions: String) async throws -> ParsedAIResponse {
        let session = LanguageModelSession(instructions: instructions)
        do {
            let response = try await session.respond(to: fullPrompt)
            let text = response.content
            // Attempt to extract structured sections from the plain text
            if let structured = OpenAIProvider.decodeStructuredOutput(from: text) {
                return ParsedAIResponse(text: OpenAIProvider.structuredText(from: structured), structured: structured)
            }
            return ParsedAIResponse(text: text, structured: nil)
        } catch {
            throw AIProviderError.onDeviceGenerationFailed(error.localizedDescription)
        }
    }

    // MARK: - Payload Summary

    /// Build a compact text summary of spectral data for the on-device model.
    /// On-device models have a limited context window, so we summarize rather
    /// than sending the full JSON payload.
    private func buildPayloadSummary(_ payload: AIRequestPayload) -> String {
        var lines: [String] = []
        lines.append("Analysis preset: \(payload.preset)")
        lines.append("Y-axis mode: \(payload.yAxisMode)")
        lines.append("Wavelength range: \(Int(payload.metricsRange.first ?? 290))–\(Int(payload.metricsRange.last ?? 400)) nm")
        lines.append("Number of spectra: \(payload.spectra.count)")
        lines.append("")

        for (index, spectrum) in payload.spectra.prefix(10).enumerated() {
            lines.append("Spectrum \(index + 1): \(spectrum.name)")
            lines.append("  Data points: \(spectrum.points.count)")
            if let metrics = spectrum.metrics {
                lines.append(String(format: "  Critical wavelength: %.1f nm", metrics.criticalWavelength))
                lines.append(String(format: "  UVA/UVB ratio: %.3f", metrics.uvaUvbRatio))
                lines.append(String(format: "  Mean UVB transmittance: %.4f", metrics.meanUVB))
            }

            // Include a few representative data points rather than all
            let points = spectrum.points
            if points.count > 6 {
                let step = max(points.count / 5, 1)
                let sampled = stride(from: 0, to: points.count, by: step).prefix(6).map { points[$0] }
                let formatted = sampled.map { String(format: "%.0f:%.4f", $0.x, $0.y) }.joined(separator: ", ")
                lines.append("  Sample points (nm:value): \(formatted)")
            }
            lines.append("")
        }

        if payload.spectra.count > 10 {
            lines.append("... and \(payload.spectra.count - 10) more spectra")
        }

        return lines.joined(separator: "\n")
    }
}

#else

// MARK: - Stub for platforms without FoundationModels

/// Placeholder provider when FoundationModels is not available.
struct FoundationModelsProvider: AIAnalysisProvider {
    let displayName = "Apple Intelligence"

    var statusText: String { "Not supported on this platform" }

    func isAvailable() -> Bool { false }

    func analyze(payload: AIRequestPayload, prompt: String, structuredOutputEnabled: Bool) async throws -> ParsedAIResponse {
        throw AIProviderError.onDeviceModelUnavailable("FoundationModels framework is not available on this platform.")
    }
}

#endif
