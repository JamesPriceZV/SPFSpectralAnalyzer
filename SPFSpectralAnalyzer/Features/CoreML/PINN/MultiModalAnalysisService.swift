import Foundation
import Observation

/// Orchestrates multi-domain PINN analysis synthesis via AI providers.
///
/// Given predictions from 2+ spectral domains for the same sample material,
/// builds a combined prompt and routes through AIProviderManager to produce
/// a unified cross-domain analysis report.
@MainActor @Observable
final class MultiModalAnalysisService {

    // MARK: - Status

    enum Status: Equatable, Sendable {
        case idle
        case gathering
        case analyzing
        case completed
        case failed(String)

        var isActive: Bool {
            switch self {
            case .gathering, .analyzing: return true
            default: return false
            }
        }
    }

    // MARK: - State

    var status: Status = .idle
    var report: MultiModalReport?

    // MARK: - Report Generation

    /// Generate a multi-modal ensemble analysis report.
    ///
    /// - Parameters:
    ///   - domains: The set of domains to include (must be >= 2)
    ///   - sampleName: User-provided sample/material name
    ///   - predictions: Pre-computed PINN predictions keyed by domain
    ///   - providerManager: The AI provider manager for routing the synthesis prompt
    ///   - credentials: Provider credentials for API access
    ///   - priorityOrder: Provider priority order
    ///   - functionRouting: Per-function routing config
    ///   - ensembleConfig: Ensemble configuration
    func generateReport(
        domains: Set<PINNDomain>,
        sampleName: String,
        predictions: [PINNDomain: PINNPredictionResult],
        providerManager: AIProviderManager,
        credentials: ProviderCredentials,
        priorityOrder: [AIProviderID],
        functionRouting: [AIAppFunction: FunctionRoutingMode],
        ensembleConfig: EnsembleConfig
    ) async {
        guard domains.count >= 2 else {
            status = .failed("Select at least 2 domains for multi-modal analysis.")
            return
        }

        // Filter to domains that actually have predictions
        let validDomains = domains.filter { predictions[$0] != nil }
        guard validDomains.count >= 2 else {
            status = .failed("At least 2 domains must have valid predictions. Only \(validDomains.count) domain(s) have results.")
            return
        }

        status = .gathering

        // Build the combined analysis prompt
        let prompt = buildMultiModalPrompt(
            sampleName: sampleName,
            predictions: predictions,
            domains: validDomains
        )

        // Build a payload for the AI provider
        let payload = AIRequestPayload(
            preset: "multimodal_analysis",
            prompt: prompt,
            temperature: 0.3,
            maxTokens: 4096,
            selectionScope: "multi-modal",
            yAxisMode: "absorbance",
            metricsRange: [],
            spectra: []
        )

        status = .analyzing

        do {
            let response = try await providerManager.analyze(
                function: .spectralAnalysis,
                payload: payload,
                prompt: prompt,
                structuredOutputEnabled: true,
                priorityOrder: priorityOrder,
                functionRouting: functionRouting,
                ensembleConfig: ensembleConfig,
                credentials: credentials
            )

            // Parse the AI response into a MultiModalReport
            report = parseResponse(
                response,
                sampleName: sampleName,
                predictions: predictions,
                domains: validDomains
            )
            status = .completed
        } catch {
            status = .failed("AI analysis failed: \(error.localizedDescription)")
            Instrumentation.log(
                "Multi-modal analysis failed",
                area: .mlTraining, level: .error,
                details: error.localizedDescription
            )
        }
    }

    // MARK: - Prompt Building

    private func buildMultiModalPrompt(
        sampleName: String,
        predictions: [PINNDomain: PINNPredictionResult],
        domains: Set<PINNDomain>
    ) -> String {
        var sections: [String] = []

        sections.append("""
        You are analyzing a material sample named "\(sampleName)" that has been tested using multiple spectral instruments. \
        Each instrument's data has been processed through a Physics-Informed Neural Network (PINN) model specific to that spectral domain. \
        Your task is to synthesize all domain results into a comprehensive multi-modal material characterization.
        """)

        sections.append("## PINN Domain Results\n")

        for domain in PINNDomain.allCases where domains.contains(domain) {
            guard let prediction = predictions[domain] else { continue }
            var domainSection = "### \(domain.displayName)\n"
            domainSection += "- Primary Value: \(prediction.primaryLabel) = \(prediction.formatted)\n"
            domainSection += "- Physics Consistency Score: \(String(format: "%.1f%%", prediction.physicsConsistencyScore * 100))\n"
            domainSection += "- Confidence Interval: \(String(format: "%.2f", prediction.confidenceLow)) – \(String(format: "%.2f", prediction.confidenceHigh))\n"
            domainSection += "- Physics Constraints: \(domain.physicsDescription)\n"
            sections.append(domainSection)
        }

        sections.append("""
        ## Instructions

        Provide a structured analysis with these sections:
        1. **Material Characterization**: A 2-3 sentence overview of what the combined results tell us about this material.
        2. **Cross-Domain Insights**: Bullet points identifying correlations, confirmations, or contradictions between domains.
        3. **Consistency Assessment**: Do the domain results agree? Are there anomalies or conflicts?
        4. **Recommendations**: Actionable next steps for the analyst.
        5. **Risks & Limitations**: Caveats about the analysis, data quality, or model constraints.

        Focus on cross-domain correlations that single-domain analysis would miss.
        """)

        return sections.joined(separator: "\n\n")
    }

    // MARK: - Response Parsing

    private func parseResponse(
        _ response: ParsedAIResponse,
        sampleName: String,
        predictions: [PINNDomain: PINNPredictionResult],
        domains: Set<PINNDomain>
    ) -> MultiModalReport {
        // Build domain result summaries
        let domainResults: [MultiModalReport.DomainResultSummary] = PINNDomain.allCases
            .filter { domains.contains($0) }
            .compactMap { domain in
                guard let prediction = predictions[domain] else { return nil }
                // Extract domain-specific findings from the structured output if available
                let findings: [String]
                if let structured = response.structured {
                    findings = structured.insights.filter {
                        $0.localizedCaseInsensitiveContains(domain.displayName)
                    }
                } else {
                    findings = []
                }
                return MultiModalReport.DomainResultSummary(
                    domain: domain,
                    prediction: prediction,
                    keyFindings: findings
                )
            }

        // Extract structured fields from the AI response
        let structured = response.structured
        let crossDomainInsights = structured?.insights ?? extractBulletPoints(from: response.text, section: "Cross-Domain Insights")
        let recommendations = structured?.actions ?? extractBulletPoints(from: response.text, section: "Recommendations")
        let risks = structured?.risks ?? extractBulletPoints(from: response.text, section: "Risks")

        // Extract longer-form sections from text
        let characterization = extractSection(from: response.text, section: "Material Characterization")
            ?? structured?.summary
            ?? "Multi-modal analysis of \(sampleName) across \(domains.count) spectral domains."

        let consistency = extractSection(from: response.text, section: "Consistency Assessment")
            ?? "Assessment pending — review individual domain results for agreement patterns."

        return MultiModalReport(
            sampleName: sampleName,
            generatedAt: Date(),
            domainResults: domainResults,
            crossDomainInsights: crossDomainInsights,
            materialCharacterization: characterization,
            consistencyAssessment: consistency,
            recommendations: recommendations,
            risks: risks
        )
    }

    // MARK: - Text Parsing Helpers

    /// Extract bullet points from a specific section of the AI text response.
    private func extractBulletPoints(from text: String, section: String) -> [String] {
        let lines = text.components(separatedBy: .newlines)
        var inSection = false
        var points: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.localizedCaseInsensitiveContains(section) && (trimmed.hasPrefix("#") || trimmed.hasSuffix(":")) {
                inSection = true
                continue
            }
            if inSection {
                if trimmed.hasPrefix("#") || (trimmed.isEmpty && !points.isEmpty) {
                    break
                }
                if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("• ") {
                    let point = String(trimmed.dropFirst(2))
                    if !point.isEmpty {
                        points.append(point)
                    }
                }
            }
        }
        return points
    }

    /// Extract a paragraph section from the AI text response.
    private func extractSection(from text: String, section: String) -> String? {
        let lines = text.components(separatedBy: .newlines)
        var inSection = false
        var content: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.localizedCaseInsensitiveContains(section) && (trimmed.hasPrefix("#") || trimmed.hasSuffix(":")) {
                inSection = true
                continue
            }
            if inSection {
                if trimmed.hasPrefix("#") && !content.isEmpty {
                    break
                }
                if !trimmed.isEmpty {
                    content.append(trimmed)
                }
            }
        }

        let result = content.joined(separator: " ")
        return result.isEmpty ? nil : result
    }
}
