import SwiftUI
import UniformTypeIdentifiers
#if canImport(AppKit)
import AppKit
#endif
import Foundation

// MARK: - AI Analysis Functions

extension ContentView {

    func runAIAnalysis() {
        guard aiEnabled else { return }

        if aiStructuredOutputEnabled && !isStructuredOutputSupported(aiOpenAIModel) {
            Instrumentation.log(
                "Structured output compatibility mode",
                area: .aiAnalysis,
                level: .warning,
                details: "model=\(aiOpenAIModel)"
            )
        }

        Instrumentation.log(
            "AI analysis requested",
            area: .aiAnalysis,
            level: .info,
            details: "scope=\(effectiveAIScope.rawValue) spectra=\(aiSpectraForScope().count)"
        )

        let cacheKey = aiCacheKey()
        if let cached = aiVM.cache[cacheKey] {
            Instrumentation.log("AI cache hit", area: .aiAnalysis, level: .info)
            aiVM.result = cached
            aiVM.structuredOutput = aiVM.structuredCache[cacheKey]
            aiVM.errorMessage = nil
            appendAIHistory(result: cached)
            updateSidebarFromAIResult(cached)
            return
        }

        Task {
            await MainActor.run {
                aiVM.isRunning = true
                aiVM.errorMessage = nil
                aiVM.structuredOutput = nil
            }
            do {
                let payload = await buildAIRequestPayload()
                let apiKey = KeychainStore.readPassword(account: KeychainKeys.openAIAPIKey)

                let parsed = try await aiVM.providerManager.analyze(
                    preference: aiProviderPreference,
                    payload: payload,
                    prompt: effectiveAIPrompt,
                    structuredOutputEnabled: aiStructuredOutputEnabled,
                    openAIEndpoint: aiOpenAIEndpoint,
                    openAIModel: aiOpenAIModel,
                    openAIAPIKey: apiKey,
                    temperature: aiTemperature,
                    maxTokens: aiMaxTokens
                )

                await MainActor.run {
                    let result = AIAnalysisResult(text: parsed.text, createdAt: Date(), preset: aiPromptPreset, selectionScope: effectiveAIScope)
                    aiVM.result = result
                    aiVM.structuredOutput = parsed.structured
                    aiVM.cache[cacheKey] = result
                    if let structured = parsed.structured {
                        aiVM.structuredCache[cacheKey] = structured
                    } else {
                        aiVM.structuredCache[cacheKey] = nil
                    }
                    appendAIHistory(result: result)
                    updateSidebarFromAIResult(result)
                    aiVM.showSavePrompt = true
                }

                logAIDiagnostics("AI analysis completed via \(aiVM.providerManager.activeProviderName ?? "unknown")")
            } catch {
                logAIDiagnostics("AI analysis failed", error: error)
                await MainActor.run {
                    aiVM.errorMessage = error.localizedDescription
                }
            }
            await MainActor.run {
                aiVM.isRunning = false
            }
        }
    }

    func resolvedOpenAIEndpointURL(from endpoint: String) -> URL? {
        if let url = URL(string: endpoint), url.scheme != nil {
            return url
        }
        return URL(string: "https://\(endpoint)")
    }

    func logAIDiagnostics(_ message: String, error: Error? = nil, endpoint: String? = nil, payloadSize: Int? = nil) {
        var detailParts: [String] = []
        if let endpoint { detailParts.append("endpoint=\(endpoint)") }
        if let error { detailParts.append("error=\(error.localizedDescription)") }
        let details = detailParts.isEmpty ? nil : detailParts.joined(separator: " ")
        let level: InstrumentationLevel = (error == nil) ? .info : .warning
        Instrumentation.log(message, area: .aiAnalysis, level: level, details: details, payloadBytes: payloadSize)
    }

    var openAISession: URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        return URLSession(configuration: configuration)
    }

    func runOpenAIAnalysis(cacheKey: String) async throws {
        guard let apiKey = KeychainStore.readPassword(account: KeychainKeys.openAIAPIKey) else {
            throw AIAuthError.missingAPIKey
        }

        let endpoint = aiOpenAIEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !endpoint.isEmpty else {
            throw AIAuthError.missingOpenAIEndpoint
        }

        guard let url = resolvedOpenAIEndpointURL(from: endpoint) else {
            throw AIAuthError.invalidOpenAIEndpoint
        }

        guard !aiOpenAIModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIAuthError.missingOpenAIModel
        }

        let body = try await buildOpenAIResponsesBody()
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = body

        do {
            logAIDiagnostics("OpenAI request sending (model \(aiOpenAIModel))", endpoint: url.absoluteString, payloadSize: body.count)
            let (data, response) = try await openAISession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                logAIDiagnostics("OpenAI response missing HTTP status", endpoint: url.absoluteString)
                throw URLError(.badServerResponse)
            }
            if !(200...299).contains(httpResponse.statusCode) {
                logAIDiagnostics("OpenAI response failed (status \(httpResponse.statusCode))", endpoint: url.absoluteString, payloadSize: data.count)
                throw URLError(.badServerResponse)
            }

            let parsed = parseAIResponse(data)
            let result = AIAnalysisResult(text: parsed.text, createdAt: Date(), preset: aiPromptPreset, selectionScope: effectiveAIScope)
            aiVM.result = result
            aiVM.structuredOutput = parsed.structured
            aiVM.cache[cacheKey] = result
            if let structured = parsed.structured {
                aiVM.structuredCache[cacheKey] = structured
            } else {
                aiVM.structuredCache[cacheKey] = nil
            }
            appendAIHistory(result: result)
            updateSidebarFromAIResult(result)
            aiVM.showSavePrompt = true

            logAIDiagnostics("OpenAI response received (status \(httpResponse.statusCode))", endpoint: url.absoluteString, payloadSize: data.count)
        } catch let error as URLError {
            logAIDiagnostics("OpenAI request failed", error: error, endpoint: url.absoluteString)
            if error.code == .cannotFindHost {
                throw AIAuthError.openAIConnectionFailed("DNS lookup failed for \(url.host ?? "api.openai.com"). Check network or DNS settings.")
            }
            throw AIAuthError.openAIConnectionFailed("\(error.localizedDescription) (\(url.absoluteString))")
        }
    }

    func buildAIRequestPayload() async -> AIRequestPayload {
        let spectra = aiSpectraForScope()
        let totalSpectra = spectra.count
        let yAxis = analysis.yAxisMode
        let payloadSpectra = await withTaskGroup(of: AISpectrumPayload.self) { group in
            for spectrum in spectra {
                let name = spectrum.name
                let points = analysis.points(for: spectrum).map { AIPointPayload(x: $0.x, y: $0.y) }
                let x = spectrum.x
                let y = spectrum.y
                group.addTask {
                    let metrics = SpectralMetricsCalculator.metrics(x: x, y: y, yAxisMode: yAxis)
                    let payloadMetrics = metrics.map { AIMetricsPayload(criticalWavelength: $0.criticalWavelength, uvaUvbRatio: $0.uvaUvbRatio, meanUVB: $0.meanUVBTransmittance) }
                    return AISpectrumPayload(name: name, points: points, metrics: payloadMetrics)
                }
            }

            var results: [AISpectrumPayload] = []
            results.reserveCapacity(totalSpectra)
            for await payload in group {
                results.append(payload)
            }
            return results
        }

        return AIRequestPayload(
            preset: aiVM.useCustomPrompt ? "custom" : aiPromptPreset.rawValue,
            prompt: effectiveAIPrompt,
            temperature: aiTemperature,
            maxTokens: aiMaxTokens,
            selectionScope: effectiveAIScope.rawValue,
            yAxisMode: analysis.yAxisMode.rawValue,
            metricsRange: [analysis.chartWavelengthRange.lowerBound, analysis.chartWavelengthRange.upperBound],
            spectra: payloadSpectra
        )
    }

    func buildOpenAIResponsesBody() async throws -> Data {
        let payload = await buildAIRequestPayload()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let payloadData = try encoder.encode(payload)
        let payloadString = String(data: payloadData, encoding: .utf8) ?? "{}"

        let structuredRequested = aiStructuredOutputEnabled
        let structuredSupported = isStructuredOutputSupported(aiOpenAIModel)
        let shouldUseSchema = structuredRequested && structuredSupported
        let shouldUseCompatibilityJSON = structuredRequested && !structuredSupported
        let schemaText = shouldUseCompatibilityJSON ? structuredOutputSchemaString() : nil

        let systemText: String = {
            if shouldUseSchema {
                return "You are a spectral analysis assistant. Respond only with valid JSON that matches the provided schema. Do not wrap JSON in markdown."
            }
            if shouldUseCompatibilityJSON {
                return "You are a spectral analysis assistant. Respond only with valid JSON. Do not wrap JSON in markdown. The response must conform to the provided schema."
            }
            return "You are a spectral analysis assistant. Respond in clear, concise paragraphs with actionable insights."
        }()

        let userText: String = {
            if shouldUseSchema {
                return """
\(effectiveAIPrompt)

Return JSON only.

Spectra payload (JSON):
\(payloadString)
"""
            }
            if shouldUseCompatibilityJSON {
                return """
\(effectiveAIPrompt)

Return JSON only that matches this schema:
\(schemaText ?? "{}")

Spectra payload (JSON):
\(payloadString)
"""
            }
            return """
\(effectiveAIPrompt)

Spectra payload (JSON):
\(payloadString)
"""
        }()

        let input: [OpenAIInputMessage] = [
            OpenAIInputMessage(role: "system", content: [OpenAIInputContent(text: systemText)]),
            OpenAIInputMessage(role: "user", content: [OpenAIInputContent(text: userText)])
        ]

        let request = OpenAIResponsesRequest(
            model: aiOpenAIModel.trimmingCharacters(in: .whitespacesAndNewlines),
            input: input,
            temperature: aiTemperature,
            maxOutputTokens: aiMaxTokens,
            text: shouldUseSchema ? OpenAIResponseText(format: structuredOutputFormat()) : nil
        )

        return try JSONEncoder().encode(request)
    }

    func structuredOutputFormat() -> OpenAIResponseTextFormat {
        let recommendationSchema = JSONSchema(
            type: "object",
            properties: [
                "ingredient": JSONSchema(type: "string", properties: nil, items: nil, required: nil, description: "Ingredient or active component", additionalProperties: nil, enumValues: nil),
                "amount": JSONSchema(type: "string", properties: nil, items: nil, required: nil, description: "Suggested amount or delta", additionalProperties: nil, enumValues: nil),
                "rationale": JSONSchema(type: "string", properties: nil, items: nil, required: nil, description: "Reasoning", additionalProperties: nil, enumValues: nil)
            ],
            items: nil,
            required: ["ingredient", "amount"],
            description: nil,
            additionalProperties: false,
            enumValues: nil
        )

        let schema = JSONSchema(
            type: "object",
            properties: [
                "summary": JSONSchema(type: "string", properties: nil, items: nil, required: nil, description: "One-paragraph summary", additionalProperties: nil, enumValues: nil),
                "insights": JSONSchema(type: "array", properties: nil, items: JSONSchema(type: "string", properties: nil, items: nil, required: nil, description: nil, additionalProperties: nil, enumValues: nil), required: nil, description: "Key insights", additionalProperties: nil, enumValues: nil),
                "risks": JSONSchema(type: "array", properties: nil, items: JSONSchema(type: "string", properties: nil, items: nil, required: nil, description: nil, additionalProperties: nil, enumValues: nil), required: nil, description: "Risks or warnings", additionalProperties: nil, enumValues: nil),
                "actions": JSONSchema(type: "array", properties: nil, items: JSONSchema(type: "string", properties: nil, items: nil, required: nil, description: nil, additionalProperties: nil, enumValues: nil), required: nil, description: "Next steps", additionalProperties: nil, enumValues: nil),
                "recommendations": JSONSchema(type: "array", properties: nil, items: recommendationSchema, required: nil, description: "Formulation recommendations", additionalProperties: nil, enumValues: nil)
            ],
            items: nil,
            required: ["insights", "risks", "actions"],
            description: nil,
            additionalProperties: false,
            enumValues: nil
        )

        return OpenAIResponseTextFormat(
            type: "json_schema",
            name: "spectral_analysis",
            strict: true,
            schema: schema
        )
    }

    func structuredOutputSchemaString() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(structuredOutputFormat().schema) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    func aiSpectraForScope() -> [ShimadzuSpectrum] {
        switch effectiveAIScope {
        case .all:
            return analysis.displayedSpectra
        case .selected:
            return analysis.selectedSpectra
        }
    }

    func updateAIEstimate() {
        let spectra = aiSpectraForScope()
        let totalPoints = spectra.reduce(0) { $0 + analysis.points(for: $1).count }
        let baseTokens = Int(Double(effectiveAIPrompt.count) / 4.0)
        let estimate = baseTokens + (totalPoints * 2) + 200
        aiVM.estimatedTokens = max(estimate, 0)
    }

    func formattedTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }

    var aiPresetTemplates: [(preset: AIPromptPreset, description: String)] {
        AIPromptPreset.allCases.map { preset in
            switch preset {
            case .summary:
                return (preset, "\"What do these spectra tell me?\" — Key insights, risks, and recommended next steps from the loaded data.")
            case .compareSelected:
                return (preset, "\"How do these samples differ?\" — Side-by-side comparison of UVA/UVB, critical λ, and absorbance profiles.")
            case .spfReport:
                return (preset, "\"Does this meet broad-spectrum requirements?\" — Critical wavelength, UVA/UVB ratio, and COLIPA compliance assessment.")
            case .getPrototypeSpf:
                return (preset, "\"What SPF can I expect from my prototype?\" — Estimates prototype SPF using known commercial samples as references.")
            }
        }
    }

    enum AISidebarSection {
        case insights
        case risks
        case actions
    }

    func aiResponseSections(from text: String) -> (insights: [String], risks: [String], actions: [String], hasSections: Bool) {
        let lines = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }

        var current: AISidebarSection?
        var insights: [String] = []
        var risks: [String] = []
        var actions: [String] = []
        var hasSections = false

        for line in lines {
            guard !line.isEmpty else { continue }
            if let section = sectionHeading(from: line) {
                current = section
                hasSections = true
                continue
            }

            guard current != nil else { continue }

            let cleaned = line
                .replacingOccurrences(of: "•", with: "")
                .replacingOccurrences(of: "-", with: "")
                .trimmingCharacters(in: .whitespaces)

            guard !cleaned.isEmpty else { continue }

            switch current {
            case .insights:
                insights.append(cleaned)
            case .risks:
                risks.append(cleaned)
            case .actions:
                actions.append(cleaned)
            case .none:
                break
            }
        }

        return (insights, risks, actions, hasSections)
    }

    func sectionHeading(from line: String) -> AISidebarSection? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutHashes = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let normalized = withoutHashes
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: ":-"))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if normalized == "key insights" || normalized == "insights" {
            return .insights
        }
        if normalized == "risks" || normalized == "warnings" || normalized == "risks/warnings" {
            return .risks
        }
        if normalized == "next actions" || normalized == "next steps" || normalized == "actions" || normalized == "steps" {
            return .actions
        }
        return nil
    }

    func isListItemLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed.hasPrefix("• ") || trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
            return true
        }
        return trimmed.range(of: "^\\d+[\\.)]\\s+", options: .regularExpression) != nil
    }

    func updateSidebarFromAIResult(_ result: AIAnalysisResult) {
        if let structured = aiVM.structuredOutput {
            aiVM.sidebarHasStructuredSections = true
            aiVM.sidebarInsightsText = structured.insights.joined(separator: "\n")
            aiVM.sidebarRisksText = structured.risks.joined(separator: "\n")
            aiVM.sidebarActionsText = structured.actions.joined(separator: "\n")
            return
        }

        let sections = aiResponseSections(from: result.text)
        aiVM.sidebarHasStructuredSections = sections.hasSections
        aiVM.sidebarInsightsText = sections.insights.joined(separator: "\n")
        aiVM.sidebarRisksText = sections.risks.joined(separator: "\n")
        aiVM.sidebarActionsText = sections.actions.joined(separator: "\n")
    }

    func syncSidebarToAIResponse() {
        guard var result = aiVM.result else { return }
        let sectionsBlock = buildSidebarBlock()
        let introLines = introLinesBeforeSections(in: result.text)
        let cleaned = stripStructuredSections(from: result.text)
        let tail = removeIntroPrefix(from: cleaned, introLines: introLines)
        let introText = trimTrailingWhitespace(introLines.joined(separator: "\n"))

        var parts: [String] = []
        if !introText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(introText)
        }
        parts.append(sectionsBlock)
        if !tail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(tail)
        }

        result.text = parts.joined(separator: "\n\n")
        aiVM.result = result
        updateSidebarFromAIResult(result)
    }

    func introLinesBeforeSections(in text: String) -> [String] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var intro: [String] = []
        for line in lines {
            if sectionHeading(from: line) != nil {
                break
            }
            intro.append(line)
        }
        while intro.last?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            intro.removeLast()
        }
        return intro
    }

    func removeIntroPrefix(from text: String, introLines: [String]) -> String {
        guard !introLines.isEmpty else { return text }
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let introCount = introLines.count
        if lines.count >= introCount && Array(lines.prefix(introCount)) == introLines {
            lines.removeFirst(introCount)
        }
        while lines.first?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            lines.removeFirst()
        }
        return lines.joined(separator: "\n")
    }

    func stripStructuredSections(from text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var output: [String] = []
        var skipping = false
        var sawHeading = false
        for line in lines {
            if sectionHeading(from: line) != nil {
                skipping = true
                sawHeading = true
                continue
            }

            if skipping {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    continue
                }
                if sectionHeading(from: line) != nil {
                    continue
                }
                if isListItemLine(line) {
                    continue
                }
                skipping = false
                output.append(line)
                continue
            }

            output.append(line)
        }

        let cleaned = output.joined(separator: "\n")
        if sawHeading {
            return trimTrailingWhitespace(cleaned)
        }
        return text
    }

    func trimTrailingWhitespace(_ value: String) -> String {
        var text = value
        while text.last?.isWhitespace == true {
            text.removeLast()
        }
        return text
    }

    func buildSidebarBlock() -> String {
        let insights = aiVM.sidebarInsightsText
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { "• \($0.trimmingCharacters(in: .whitespacesAndNewlines))" }
            .joined(separator: "\n")
        let risks = aiVM.sidebarRisksText
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { "• \($0.trimmingCharacters(in: .whitespacesAndNewlines))" }
            .joined(separator: "\n")
        let actions = aiVM.sidebarActionsText
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { "• \($0.trimmingCharacters(in: .whitespacesAndNewlines))" }
            .joined(separator: "\n")

        return [
            "Key Insights:",
            insights,
            "",
            "Risks/Warnings:",
            risks,
            "",
            "Next Steps:",
            actions
        ].joined(separator: "\n")
    }

    @ViewBuilder
    func aiSidebarEditableSection(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            TextEditor(text: text)
                .frame(minHeight: 70, maxHeight: 100)
                .font(.caption)
                .padding(6)
                .background(Color.white.opacity(0.04))
                .cornerRadius(8)
        }
    }

    var aiResponsePopupView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("AI Response")
                        .font(.title3)
                        .bold()
                    Spacer()
                    Button("Close") {
                        aiVM.showResponsePopup = false
                    }
                    .glassButtonStyle()
                }

                if !aiVM.sidebarInsightsText.isEmpty {
                    GroupBox("Key Insights") {
                        Text(aiVM.sidebarInsightsText)
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
                if !aiVM.sidebarRisksText.isEmpty {
                    GroupBox("Risks/Warnings") {
                        Text(aiVM.sidebarRisksText)
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
                if !aiVM.sidebarActionsText.isEmpty {
                    GroupBox("Next Steps") {
                        Text(aiVM.sidebarActionsText)
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }

                if let structured = aiVM.structuredOutput {
                    GroupBox("Structured Summary") {
                        VStack(alignment: .leading, spacing: 6) {
                            if let summary = structured.summary, !summary.isEmpty {
                                Text(summary).font(.body)
                            }
                            if let recommendations = structured.recommendations, !recommendations.isEmpty {
                                ForEach(recommendations) { rec in
                                    HStack(alignment: .top, spacing: 8) {
                                        Text("\(rec.ingredient) • \(rec.amount)")
                                            .font(.callout)
                                            .bold()
                                        if let rationale = rec.rationale, !rationale.isEmpty {
                                            Text(rationale)
                                                .font(.callout)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                    }
                }

                Divider()

                if let aiResult = aiVM.result {
                    Text(aiResult.text)
                        .font(.system(size: max(aiResponseTextSize, 13)))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("No AI output yet.")
                        .foregroundColor(.secondary)
                }
            }
            .padding(24)
        }
        .frame(minWidth: 500, idealWidth: 900, maxWidth: .infinity, minHeight: 400, idealHeight: 700, maxHeight: .infinity)
    }

    var aiHistoryDiffText: String? {
        guard let idA = aiVM.historySelectionA,
              let idB = aiVM.historySelectionB,
              idA != idB,
              let entryA = aiVM.historyEntries.first(where: { $0.id == idA }),
              let entryB = aiVM.historyEntries.first(where: { $0.id == idB }) else { return nil }
        let diffLines = diffLines(a: entryA.text, b: entryB.text)
        return diffLines.joined(separator: "\n")
    }

    func diffLines(a: String, b: String) -> [String] {
        let aLines = a.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let bLines = b.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let count = max(aLines.count, bLines.count)
        var output: [String] = []
        for index in 0..<count {
            let left = index < aLines.count ? aLines[index] : ""
            let right = index < bLines.count ? bLines[index] : ""
            if left == right {
                output.append("  \(left)")
            } else {
                if !left.isEmpty { output.append("- \(left)") }
                if !right.isEmpty { output.append("+ \(right)") }
            }
        }
        return output
    }

    func appendAIHistory(result: AIAnalysisResult) {
        if let last = aiVM.historyEntries.first, last.text == result.text {
            return
        }
        var updated = aiVM.historyEntries
        updated.insert(AIHistoryEntry(timestamp: Date(), preset: result.preset, scope: result.selectionScope, text: result.text), at: 0)
        if updated.count > aiVM.historyMaxEntries {
            updated.removeLast(updated.count - aiVM.historyMaxEntries)
        }
        aiVM.historyEntries = updated
    }

    func buildSpfMathLines(
        spectrum: ShimadzuSpectrum,
        metrics: SpectralMetrics,
        calibration: CalibrationResult?
    ) -> [String] {
        var lines: [String] = []
        lines.append("SPF Math Details")
        lines.append("Spectrum: \(spectrum.name)")
        lines.append("YAxis Mode: \(analysis.yAxisMode.rawValue)")
        lines.append("Ranges: UVB 290–320 nm, UVA 320–400 nm, Total 290–400 nm")
        lines.append("Conversions:")
        if analysis.yAxisMode == .absorbance {
            lines.append("  T = 10^(−A)")
        } else {
            lines.append("  A = −log10(max(T, 1e−9))")
        }
        lines.append(String(format: "UVB Area: %.4f", metrics.uvbArea))
        lines.append(String(format: "UVA Area: %.4f", metrics.uvaArea))
        lines.append(String(format: "UVA/UVB Ratio: %.4f", metrics.uvaUvbRatio))
        lines.append(String(format: "Critical Wavelength: %.2f nm", metrics.criticalWavelength))
        lines.append(String(format: "Mean UVB Transmittance: %.4f", metrics.meanUVBTransmittance))
        lines.append("COLIPA SPF:")
        lines.append("  SPF = Σ E(λ)·I(λ) / Σ E(λ)·I(λ)·T(λ)")
        if let colipa = analysis.cachedColipaSpf {
            lines.append(String(format: "  Value: %.2f", colipa))
        } else {
            lines.append("  Value: unavailable (requires 290–400 nm data)")
        }
        if let calibration {
            let features: [Double] = [
                1.0,
                metrics.uvbArea,
                metrics.uvaArea,
                metrics.criticalWavelength,
                metrics.uvaUvbRatio,
                metrics.meanUVBTransmittance,
                metrics.meanUVATransmittance,
                metrics.peakAbsorbanceWavelength
            ]
            let logSpf = zip(calibration.coefficients, features).map(*).reduce(0, +)
            let predicted = max(exp(logSpf), 0.0)
            lines.append("Model:")
            lines.append("  log(SPF) = Σ(bᵢ × featureᵢ)")
            lines.append("  SPF = exp(log(SPF))")
            lines.append(String(format: "Estimated SPF (calibrated): %.2f", predicted))
            lines.append("Coefficients:")
            for (name, coeff) in zip(calibration.featureNames, calibration.coefficients) {
                lines.append(String(format: "  %@: %.6f", name, coeff))
            }
            lines.append(String(format: "Calibration: n=%d, R²=%.3f, RMSE=%.2f", calibration.sampleCount, calibration.r2, calibration.rmse))
        } else {
            lines.append("Calibration: not available (need at least 2 labeled samples)")
        }
        return lines
    }

    func copyValidationLog() {
        let text = analysis.validationLogEntries
            .map { "\(formattedTimestamp($0.timestamp)) \($0.message)" }
            .joined(separator: "\n")
        PlatformPasteboard.copyString(text)
    }

    func copySpfMathToPasteboard() {
        guard let spectrum = analysis.selectedSpectrum, let metrics = analysis.selectedMetrics else { return }
        let calibration = analysis.calibrationResult
        let lines = buildSpfMathLines(spectrum: spectrum, metrics: metrics, calibration: calibration)
        PlatformPasteboard.copyString(lines.joined(separator: "\n"))
    }

    func saveValidationLogToFile() {
        let text = analysis.validationLogEntries
            .map { "\(formattedTimestamp($0.timestamp)) \($0.message)" }
            .joined(separator: "\n")
        guard let data = text.data(using: .utf8) else { return }
        Task { @MainActor in
            guard let url = await PlatformFileSaver.save(
                defaultName: timestampedFileName("validation-log.txt"),
                allowedTypes: [UTType.plainText],
                data: data,
                directoryKey: SaveDirectoryKey.aiReports.rawValue
            ) else { return }
            storeLastSaveDirectory(from: url, key: .aiReports)
        }
    }

    func parseAIResponse(_ data: Data) -> ParsedAIResponse {
        if let decoded = try? JSONDecoder().decode(AIResponse.self, from: data) {
            return parseStructuredOutput(text: decoded.text)
        }
        if let decoded = try? JSONDecoder().decode(OpenAIResponsesResponse.self, from: data),
           let text = decoded.outputText {
            return parseStructuredOutput(text: text)
        }
        if let structured = try? JSONDecoder().decode(AIStructuredOutput.self, from: data) {
            return ParsedAIResponse(text: structuredText(from: structured), structured: structured)
        }
        let fallback = String(data: data, encoding: .utf8) ?? "Empty response"
        return parseStructuredOutput(text: fallback)
    }

    func parseStructuredOutput(text: String) -> ParsedAIResponse {
        if let structured = decodeStructuredOutput(from: text) {
            return ParsedAIResponse(text: structuredText(from: structured), structured: structured)
        }
        return ParsedAIResponse(text: text, structured: nil)
    }

    func decodeStructuredOutput(from text: String) -> AIStructuredOutput? {
        guard let jsonString = extractStructuredJSON(from: text) else { return nil }
        guard let data = jsonString.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(AIStructuredOutput.self, from: data)
    }

    func extractStructuredJSON(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.first == "{" && trimmed.last == "}" {
            return trimmed
        }
        if let fenced = extractJSONFromFencedBlock(in: text) {
            return fenced
        }
        return extractFirstJSONObject(from: text)
    }

    func extractJSONFromFencedBlock(in text: String) -> String? {
        let pattern = "```(?:json)?\\s*(\\{[\\s\\S]*?\\})\\s*```"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range), match.numberOfRanges > 1 else { return nil }
        guard let jsonRange = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[jsonRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func extractFirstJSONObject(from text: String) -> String? {
        var startIndex: String.Index?
        var depth = 0
        var inString = false
        var escape = false

        var index = text.startIndex
        while index < text.endIndex {
            let char = text[index]
            if startIndex == nil {
                if char == "{" {
                    startIndex = index
                    depth = 1
                }
                index = text.index(after: index)
                continue
            }

            if inString {
                if escape {
                    escape = false
                } else if char == "\\" {
                    escape = true
                } else if char == "\"" {
                    inString = false
                }
            } else {
                if char == "\"" {
                    inString = true
                } else if char == "{" {
                    depth += 1
                } else if char == "}" {
                    depth -= 1
                    if depth == 0, let start = startIndex {
                        let end = index
                        return String(text[start...end]).trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
            }

            index = text.index(after: index)
        }

        return nil
    }

    func structuredText(from structured: AIStructuredOutput) -> String {
        var sections: [String] = []

        if let summary = structured.summary, !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append(summary.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        sections.append("Key Insights")
        if structured.insights.isEmpty {
            sections.append("- None provided")
        } else {
            sections.append(contentsOf: structured.insights.map { "- \($0)" })
        }

        sections.append("")
        sections.append("Risks/Warnings")
        if structured.risks.isEmpty {
            sections.append("- None provided")
        } else {
            sections.append(contentsOf: structured.risks.map { "- \($0)" })
        }

        sections.append("")
        sections.append("Next Steps")
        if structured.actions.isEmpty {
            sections.append("- None provided")
        } else {
            sections.append(contentsOf: structured.actions.map { "- \($0)" })
        }

        if let recommendations = structured.recommendations, !recommendations.isEmpty {
            sections.append("")
            sections.append("Recommendations")
            for rec in recommendations {
                var line = "- \(rec.ingredient): \(rec.amount)"
                if let rationale = rec.rationale, !rationale.isEmpty {
                    line += " (\(rationale))"
                }
                sections.append(line)
            }
        }

        return sections.joined(separator: "\n")
    }

    func aiCacheKey() -> String {
        let scope = effectiveAIScope.rawValue
        let preset = aiVM.useCustomPrompt ? "custom" : aiPromptPreset.rawValue
        let endpoint = aiOpenAIEndpoint
        let model = aiOpenAIModel
        let promptSignature = String(effectiveAIPrompt.prefix(120))
        let names = aiSpectraForScope().map { $0.name }.joined(separator: "|")
        let provider = aiProviderPreference.rawValue
        let structuredFlag: String = {
            guard aiStructuredOutputEnabled else { return "plain" }
            return isStructuredOutputSupported(model) ? "structured" : "structured_fallback"
        }()
        return "\(provider)|\(endpoint)|\(model)|\(scope)|\(preset)|\(analysis.yAxisMode.rawValue)|\(structuredFlag)|\(promptSignature)|\(names)"
    }

    func saveAIResultToDisk() {
        guard let aiResult = aiVM.result else { return }
        #if canImport(AppKit)
        let panel = NSSavePanel()
        let docx = UTType(filenameExtension: "docx") ?? .data
        panel.nameFieldStringValue = timestampedFileName("AI Analysis.docx")
        panel.allowedContentTypes = [docx, .plainText]
        panel.canCreateDirectories = true
        if let directory = lastSaveDirectoryURL(for: .instrumentationLogs) {
            panel.directoryURL = directory
        }

        if panel.runModal() == .OK, let url = panel.url {
            do {
                if url.pathExtension.lowercased() == "docx" {
                    try OOXMLWriter.writeDocx(report: aiResult.text, to: url)
                } else {
                    try aiResult.text.write(to: url, atomically: true, encoding: .utf8)
                }
                storeLastSaveDirectory(from: url, key: .aiLogs)
            } catch {
                aiVM.errorMessage = error.localizedDescription
            }
        }
        #else
        let docx = UTType(filenameExtension: "docx") ?? .data
        let fileName = timestampedFileName("AI Analysis.docx")
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try OOXMLWriter.writeDocx(report: aiResult.text, to: tempURL)
        } catch {
            aiVM.errorMessage = error.localizedDescription
            return
        }
        Task { @MainActor in
            let _ = await PlatformFileSaver.saveFile(
                at: tempURL,
                defaultName: fileName,
                allowedTypes: [docx],
                directoryKey: SaveDirectoryKey.instrumentationLogs.rawValue
            )
        }
        #endif
    }

    func saveAIResultToDefaultAndOpen() {
        guard let aiResult = aiVM.result else { return }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: Date())
        let fileName = "AI SPF Analysis_\(stamp).docx"

        let baseDirectory = lastSaveDirectoryURL(for: .aiReports)
            ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let url = baseDirectory.appendingPathComponent(fileName)

        do {
            try OOXMLWriter.writeDocx(report: aiResult.text, to: url)
            storeLastSaveDirectory(from: url, key: .aiReports)
            PlatformURLOpener.open(url)
        } catch {
            aiVM.errorMessage = error.localizedDescription
        }
    }

    func copyAIOutput() {
        guard let aiResult = aiVM.result else { return }
        PlatformPasteboard.copyString(aiResult.text)
    }

}
