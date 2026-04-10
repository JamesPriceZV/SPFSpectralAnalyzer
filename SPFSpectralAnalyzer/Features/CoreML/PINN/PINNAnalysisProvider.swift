import Foundation

/// Wraps the PINN prediction service as an `AIAnalysisProvider` for ensemble participation.
/// Extracts spectral data from the AI request payload, runs the appropriate domain PINN model,
/// and formats the physics-informed prediction as a structured analysis response.
final class PINNAnalysisProvider: AIAnalysisProvider, @unchecked Sendable {

    let displayName = "PINN On-Device"

    private let predictionService: PINNPredictionService

    init(predictionService: PINNPredictionService) {
        self.predictionService = predictionService
    }

    func isAvailable() -> Bool {
        MainActor.assumeIsolated {
            predictionService.readyModelCount > 0
        }
    }

    func analyze(
        payload: AIRequestPayload,
        prompt: String,
        structuredOutputEnabled: Bool
    ) async throws -> ParsedAIResponse {
        // Extract spectral data from the first spectrum in the payload
        guard let spectrum = payload.spectra.first, !spectrum.points.isEmpty else {
            throw AIProviderError.onDeviceGenerationFailed("No spectral data in payload")
        }

        let wavelengths = spectrum.points.map(\.x)
        let intensities = spectrum.points.map(\.y)

        // Try to determine the domain from the spectral range
        let experimentTypeCode = inferExperimentType(wavelengths: wavelengths)

        let result: PINNPredictionResult? = await MainActor.run {
            predictionService.predict(
                experimentTypeCode: experimentTypeCode,
                wavelengths: wavelengths,
                intensities: intensities
            )
        }

        guard let prediction = result else {
            throw AIProviderError.onDeviceGenerationFailed(
                "No PINN model available for experiment type \(experimentTypeCode)"
            )
        }

        // Format as structured analysis response
        let domain = await MainActor.run {
            predictionService.domain(for: experimentTypeCode)
        }
        let domainName = domain?.displayName ?? "Unknown"
        let physics = domain?.physicsDescription ?? ""

        let summary = buildSummary(prediction: prediction, domainName: domainName, spectrumName: spectrum.name)
        let insights = buildInsights(prediction: prediction, domainName: domainName, physics: physics)
        let risks = buildRisks(prediction: prediction)
        let actions = buildActions(prediction: prediction, domainName: domainName)

        let structured = AIStructuredOutput(
            summary: summary,
            insights: insights,
            risks: risks,
            actions: actions,
            recommendations: nil
        )

        let text = """
        **PINN \(domainName) Analysis** (Physics-Informed Neural Network)

        \(summary)

        **Key Insights:**
        \(insights.map { "• \($0)" }.joined(separator: "\n"))

        **Physics Constraints:** \(physics)

        **Physics Consistency Score:** \(String(format: "%.1f%%", prediction.physicsConsistencyScore * 100))
        """

        return ParsedAIResponse(text: text, structured: structured)
    }

    // MARK: - Experiment Type Inference

    /// Infer experiment type from wavelength range when not explicitly provided.
    private func inferExperimentType(wavelengths: [Double]) -> UInt8 {
        guard let minWL = wavelengths.min(), let maxWL = wavelengths.max() else {
            return 6 // Default to UV-Vis
        }

        let range = maxWL - minWL

        // UV-Vis: typically 190-900nm, but our SPF range is 290-400nm
        if minWL >= 190 && maxWL <= 900 && range < 800 {
            return 6
        }
        // FTIR: typically 400-4000 cm⁻¹ (reported as wavenumber)
        if minWL >= 400 && maxWL >= 2000 {
            return 4
        }
        // Raman: typically 100-4000 cm⁻¹ shift
        if minWL >= 0 && maxWL <= 4500 && range > 500 {
            return 10
        }
        // Mass Spec: m/z ratios, typically 0-2000+
        if minWL >= 0 && maxWL <= 3000 && range > 100 {
            return 8
        }

        return 6 // Default to UV-Vis
    }

    // MARK: - Response Formatting

    private func buildSummary(prediction: PINNPredictionResult, domainName: String, spectrumName: String) -> String {
        let confidence = prediction.confidenceLow > 0 && prediction.confidenceHigh > 0
            ? " (95% CI: \(String(format: "%.1f", prediction.confidenceLow))–\(String(format: "%.1f", prediction.confidenceHigh)))"
            : ""
        let consistency = String(format: "%.0f%%", prediction.physicsConsistencyScore * 100)

        return "Physics-informed \(domainName) analysis of \"\(spectrumName)\" yields " +
            "\(prediction.primaryLabel) = \(String(format: "%.2f", prediction.primaryValue))\(confidence). " +
            "The prediction satisfies embedded physics constraints at \(consistency) consistency, " +
            "indicating \(prediction.physicsConsistencyScore >= 0.9 ? "excellent" : prediction.physicsConsistencyScore >= 0.7 ? "good" : "moderate") " +
            "agreement with the governing equations for this domain."
    }

    private func buildInsights(prediction: PINNPredictionResult, domainName: String, physics: String) -> [String] {
        var insights: [String] = []

        insights.append("\(prediction.primaryLabel): \(prediction.formatted)")

        if prediction.physicsConsistencyScore >= 0.9 {
            insights.append("Prediction strongly consistent with \(domainName) physics constraints (\(physics))")
        } else if prediction.physicsConsistencyScore >= 0.7 {
            insights.append("Prediction reasonably consistent with \(domainName) physics constraints")
        } else {
            insights.append("Prediction shows moderate deviation from expected physics — verify sample preparation")
        }

        if let decomposition = prediction.decomposition, !decomposition.isEmpty {
            let components = decomposition.keys.sorted().prefix(3)
            insights.append("Component decomposition available: \(components.joined(separator: ", "))")
        }

        if prediction.confidenceLow > 0 && prediction.confidenceHigh > 0 {
            let width = prediction.confidenceHigh - prediction.confidenceLow
            let relative = width / max(prediction.primaryValue, 1.0) * 100
            insights.append(String(format: "Conformal prediction interval width: %.1f (%.0f%% relative)", width, relative))
        }

        return insights
    }

    private func buildRisks(prediction: PINNPredictionResult) -> [String] {
        var risks: [String] = []

        if prediction.physicsConsistencyScore < 0.7 {
            risks.append("Low physics consistency score may indicate measurement artifacts or unusual sample composition")
        }

        if prediction.confidenceLow > 0 && prediction.confidenceHigh > 0 {
            let width = prediction.confidenceHigh - prediction.confidenceLow
            let relative = width / max(prediction.primaryValue, 1.0)
            if relative > 0.5 {
                risks.append("Wide prediction interval suggests high uncertainty — more reference data may improve precision")
            }
        }

        if risks.isEmpty {
            risks.append("No significant risks identified — prediction confidence is within acceptable bounds")
        }

        return risks
    }

    private func buildActions(prediction: PINNPredictionResult, domainName: String) -> [String] {
        var actions: [String] = []

        actions.append("Review PINN \(domainName) prediction alongside cloud provider analyses for consensus")

        if prediction.physicsConsistencyScore < 0.8 {
            actions.append("Consider re-measuring sample to confirm spectral integrity")
        }

        actions.append("Compare with known reference standards for this \(domainName.lowercased()) domain")

        return actions
    }
}
