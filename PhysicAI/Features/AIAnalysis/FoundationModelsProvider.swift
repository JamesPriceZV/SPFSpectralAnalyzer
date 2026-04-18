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

// MARK: - Ensemble Arbitration Generable Types

@Generable(description: "A disputed finding where providers disagree")
struct DisputedItem {
    @Guide(description: "The disputed claim or finding")
    var claim: String
    @Guide(description: "Names of providers that support this claim", .maximumCount(6))
    var supportingProviders: [String]
    @Guide(description: "Names of providers that contradict this claim", .maximumCount(6))
    var opposingProviders: [String]
    @Guide(description: "Reasoned resolution of the disagreement")
    var resolution: String
}

@Generable(description: "Arbitrated synthesis of multiple AI provider analysis results")
struct ArbitratedOutput {
    @Guide(description: "Unified summary synthesizing all provider analyses into one coherent paragraph")
    var unifiedSummary: String
    @Guide(description: "Insights agreed upon by two or more providers", .maximumCount(8))
    var consensusInsights: [String]
    @Guide(description: "Findings where providers disagree", .maximumCount(5))
    var disputedFindings: [DisputedItem]
    @Guide(description: "Unique observations from only one provider worth noting", .maximumCount(5))
    var outlierObservations: [String]
    @Guide(description: "Unified risk warnings synthesized from all providers", .maximumCount(5))
    var unifiedRisks: [String]
    @Guide(description: "Unified recommended actions synthesized from all providers", .maximumCount(5))
    var unifiedActions: [String]
    @Guide(description: "Unified formulation recommendations", .maximumCount(3))
    var unifiedRecommendations: [OnDeviceRecommendation]
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

    // MARK: - Ensemble Arbitration

    /// Synthesize multiple provider responses into a unified arbitrated analysis.
    /// Uses on-device FoundationModels to identify consensus, disputes, and outliers.
    func synthesizeEnsemble(providerResponses: [(providerName: String, structured: AIStructuredOutput)]) async throws -> ArbitratedOutput {
        guard isAvailable() else {
            throw AIProviderError.onDeviceModelUnavailable("On-device model required for ensemble arbitration is unavailable.")
        }

        // Build compact prompt with each provider's structured output
        var promptLines: [String] = []
        promptLines.append("You are an expert scientific analysis arbitrator. Below are spectral analysis results from \(providerResponses.count) different AI providers. Your task is to synthesize these into a single unified analysis by:")
        promptLines.append("1. Identifying consensus findings shared by two or more providers")
        promptLines.append("2. Noting contradictions where providers disagree, with a reasoned resolution")
        promptLines.append("3. Flagging unique observations from only one provider that are worth noting")
        promptLines.append("4. Producing unified risks, actions, and formulation recommendations")
        promptLines.append("")

        for (name, output) in providerResponses {
            promptLines.append("--- \(name) ---")
            if let summary = output.summary {
                promptLines.append("Summary: \(summary)")
            }
            if !output.insights.isEmpty {
                promptLines.append("Insights: \(output.insights.joined(separator: "; "))")
            }
            if !output.risks.isEmpty {
                promptLines.append("Risks: \(output.risks.joined(separator: "; "))")
            }
            if !output.actions.isEmpty {
                promptLines.append("Actions: \(output.actions.joined(separator: "; "))")
            }
            if let recs = output.recommendations, !recs.isEmpty {
                let recText = recs.map { "\($0.ingredient): \($0.amount) (\($0.rationale ?? ""))" }.joined(separator: "; ")
                promptLines.append("Recommendations: \(recText)")
            }
            promptLines.append("")
        }

        let instructions = """
            You are a scientific analysis arbitrator specializing in UV spectroscopy \
            and sunscreen formulation. Synthesize multiple provider analyses into one \
            unified, authoritative response. Prioritize scientifically accurate claims \
            and note when providers contradict each other.
            """

        let session = LanguageModelSession(instructions: instructions)
        do {
            let response = try await session.respond(
                to: promptLines.joined(separator: "\n"),
                generating: ArbitratedOutput.self
            )
            return response.content
        } catch {
            throw AIProviderError.onDeviceGenerationFailed("Ensemble arbitration failed: \(error.localizedDescription)")
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

        // Include CoreML prediction if available
        if let ml = payload.mlPrediction {
            lines.append("")
            lines.append("On-device ML model prediction:")
            lines.append(String(format: "  Predicted SPF: %.1f (90%% confidence interval: %.1f–%.1f)", ml.spfEstimate, ml.confidenceLow, ml.confidenceHigh))
            lines.append("  This prediction is based on a boosted tree regressor trained on paired in-vivo/in-vitro data.")
        }

        // Include formula card ingredients if available
        if let ingredients = payload.formulaIngredients, !ingredients.isEmpty {
            lines.append("")
            lines.append("Prototype formula composition:")
            for ing in ingredients {
                var desc = "  \(ing.name)"
                if let inci = ing.inciName { desc += " (INCI: \(inci))" }
                if let pct = ing.percentage { desc += String(format: " — %.1f%%", pct) }
                if let cat = ing.category { desc += " [\(cat)]" }
                lines.append(desc)
            }
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
