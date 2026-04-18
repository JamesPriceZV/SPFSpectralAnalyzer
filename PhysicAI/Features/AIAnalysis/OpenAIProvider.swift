import Foundation

// MARK: - OpenAI Provider

/// AI provider that sends requests to the OpenAI Responses API (or compatible endpoint).
struct OpenAIProvider: AIAnalysisProvider {
    let displayName = "OpenAI"

    let endpoint: String
    let model: String
    let apiKey: String
    let temperature: Double
    let maxTokens: Int

    func isAvailable() -> Bool {
        !endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !apiKey.isEmpty
    }

    func analyze(payload: AIRequestPayload, prompt: String, structuredOutputEnabled: Bool) async throws -> ParsedAIResponse {
        let trimmedEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEndpoint.isEmpty else { throw AIAuthError.missingOpenAIEndpoint }
        guard let url = resolvedURL(from: trimmedEndpoint) else { throw AIAuthError.invalidOpenAIEndpoint }
        guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AIAuthError.missingOpenAIModel }

        let body = try buildRequestBody(payload: payload, prompt: prompt, structuredOutputEnabled: structuredOutputEnabled)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = body

        Instrumentation.log(
            "OpenAI request sending (model \(model))",
            area: .aiAnalysis,
            level: .info,
            details: "endpoint=\(url.absoluteString)",
            payloadBytes: body.count
        )

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            Instrumentation.log(
                "OpenAI response failed (status \(httpResponse.statusCode))",
                area: .aiAnalysis,
                level: .warning,
                details: "endpoint=\(url.absoluteString)",
                payloadBytes: data.count
            )
            throw URLError(.badServerResponse)
        }

        Instrumentation.log(
            "OpenAI response received (status \(httpResponse.statusCode))",
            area: .aiAnalysis,
            level: .info,
            details: "endpoint=\(url.absoluteString)",
            payloadBytes: data.count
        )

        return Self.parseResponse(data)
    }

    // MARK: - Internals

    private var session: URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        return URLSession(configuration: configuration)
    }

    private func resolvedURL(from endpoint: String) -> URL? {
        if let url = URL(string: endpoint), url.scheme != nil {
            return url
        }
        return URL(string: "https://\(endpoint)")
    }

    private func buildRequestBody(payload: AIRequestPayload, prompt: String, structuredOutputEnabled: Bool) throws -> Data {
        let payloadString = try payload.encodedJSONString()

        let structuredSupported = Self.isStructuredOutputSupported(model)
        let shouldUseSchema = structuredOutputEnabled && structuredSupported
        let shouldUseCompatibilityJSON = structuredOutputEnabled && !structuredSupported
        let schemaText = shouldUseCompatibilityJSON ? Self.structuredOutputSchemaString() : nil

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
                \(prompt)

                Return JSON only.

                Spectra payload (JSON):
                \(payloadString)
                """
            }
            if shouldUseCompatibilityJSON {
                return """
                \(prompt)

                Return JSON only that matches this schema:
                \(schemaText ?? "{}")

                Spectra payload (JSON):
                \(payloadString)
                """
            }
            return """
            \(prompt)

            Spectra payload (JSON):
            \(payloadString)
            """
        }()

        let input: [OpenAIInputMessage] = [
            OpenAIInputMessage(role: "system", content: [OpenAIInputContent(text: systemText)]),
            OpenAIInputMessage(role: "user", content: [OpenAIInputContent(text: userText)])
        ]

        let request = OpenAIResponsesRequest(
            model: model.trimmingCharacters(in: .whitespacesAndNewlines),
            input: input,
            temperature: temperature,
            maxOutputTokens: maxTokens,
            text: shouldUseSchema ? OpenAIResponseText(format: Self.structuredOutputFormat()) : nil
        )

        return try JSONEncoder().encode(request)
    }

    // MARK: - Response Parsing

    static func parseResponse(_ data: Data) -> ParsedAIResponse {
        let tokenUsage = extractTokenUsage(from: data)
        var response: ParsedAIResponse
        if let decoded = try? JSONDecoder().decode(AIResponse.self, from: data) {
            response = parseStructuredOutput(text: decoded.text)
        } else if let decoded = try? JSONDecoder().decode(OpenAIResponsesResponse.self, from: data),
           let text = decoded.outputText {
            response = parseStructuredOutput(text: text)
        } else if let structured = try? JSONDecoder().decode(AIStructuredOutput.self, from: data) {
            response = ParsedAIResponse(text: structuredText(from: structured), structured: structured)
        } else {
            let fallback = String(data: data, encoding: .utf8) ?? "Empty response"
            response = parseStructuredOutput(text: fallback)
        }
        response.tokenUsage = tokenUsage
        return response
    }

    /// Extract token usage from OpenAI response JSON.
    /// Works with both Responses API (`usage.input_tokens`/`output_tokens`)
    /// and Chat Completions API (`usage.prompt_tokens`/`completion_tokens`).
    static func extractTokenUsage(from data: Data) -> TokenUsage? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let usage = json["usage"] as? [String: Any] else { return nil }
        let prompt = (usage["prompt_tokens"] as? Int) ?? (usage["input_tokens"] as? Int) ?? 0
        let completion = (usage["completion_tokens"] as? Int) ?? (usage["output_tokens"] as? Int) ?? 0
        guard prompt > 0 || completion > 0 else { return nil }
        return TokenUsage(promptTokens: prompt, completionTokens: completion)
    }

    static func parseStructuredOutput(text: String) -> ParsedAIResponse {
        if let structured = decodeStructuredOutput(from: text) {
            return ParsedAIResponse(text: structuredText(from: structured), structured: structured)
        }
        return ParsedAIResponse(text: text, structured: nil)
    }

    static func decodeStructuredOutput(from text: String) -> AIStructuredOutput? {
        guard let jsonString = extractStructuredJSON(from: text) else { return nil }
        guard let data = jsonString.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(AIStructuredOutput.self, from: data)
    }

    static func extractStructuredJSON(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.first == "{" && trimmed.last == "}" {
            return trimmed
        }
        if let fenced = extractJSONFromFencedBlock(in: text) {
            return fenced
        }
        return extractFirstJSONObject(from: text)
    }

    static func extractJSONFromFencedBlock(in text: String) -> String? {
        let pattern = "```(?:json)?\\s*(\\{[\\s\\S]*?\\})\\s*```"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range), match.numberOfRanges > 1 else { return nil }
        guard let jsonRange = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[jsonRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func extractFirstJSONObject(from text: String) -> String? {
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

    static func structuredText(from structured: AIStructuredOutput) -> String {
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

    // MARK: - Structured Output Schema

    static func isStructuredOutputSupported(_ model: String) -> Bool {
        let normalized = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.isEmpty { return false }
        if normalized.hasPrefix("gpt-4o-mini") { return true }
        if normalized.hasPrefix("gpt-4o") { return true }
        return false
    }

    static func structuredOutputFormat() -> OpenAIResponseTextFormat {
        let recommendationSchema = JSONSchema(
            type: "object",
            properties: [
                "ingredient": JSONSchema(type: "string", description: "Ingredient or active component"),
                "amount": JSONSchema(type: "string", description: "Suggested amount or delta"),
                "rationale": JSONSchema(type: "string", description: "Reasoning")
            ],
            required: ["ingredient", "amount"],
            additionalProperties: false
        )

        let schema = JSONSchema(
            type: "object",
            properties: [
                "summary": JSONSchema(type: "string", description: "One-paragraph summary"),
                "insights": JSONSchema(type: "array", items: JSONSchema(type: "string"), description: "Key insights"),
                "risks": JSONSchema(type: "array", items: JSONSchema(type: "string"), description: "Risks or warnings"),
                "actions": JSONSchema(type: "array", items: JSONSchema(type: "string"), description: "Next steps"),
                "recommendations": JSONSchema(type: "array", items: recommendationSchema, description: "Formulation recommendations")
            ],
            required: ["insights", "risks", "actions"],
            additionalProperties: false
        )

        return OpenAIResponseTextFormat(
            type: "json_schema",
            name: "spectral_analysis",
            strict: true,
            schema: schema
        )
    }

    static func structuredOutputSchemaString() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(structuredOutputFormat().schema) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
