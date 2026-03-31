import Foundation

// MARK: - Anthropic Claude Provider

/// AI provider that sends requests to the Anthropic Messages API.
struct ClaudeProvider: AIAnalysisProvider {
    let displayName = "Anthropic Claude"

    let model: String
    let apiKey: String
    let maxTokens: Int

    func isAvailable() -> Bool {
        !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !apiKey.isEmpty
    }

    func analyze(payload: AIRequestPayload, prompt: String, structuredOutputEnabled: Bool) async throws -> ParsedAIResponse {
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModel.isEmpty else { throw AIAuthError.missingClaudeModel }
        guard !apiKey.isEmpty else { throw AIAuthError.missingAPIKey }

        let body = try buildRequestBody(payload: payload, prompt: prompt, structuredOutputEnabled: structuredOutputEnabled)

        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            throw AIAuthError.invalidClaudeEndpoint
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = body

        Instrumentation.log(
            "Claude request sending (model \(trimmedModel))",
            area: .aiAnalysis,
            level: .info,
            payloadBytes: body.count
        )

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            Instrumentation.log(
                "Claude response failed (status \(httpResponse.statusCode))",
                area: .aiAnalysis,
                level: .warning,
                payloadBytes: data.count
            )
            throw URLError(.badServerResponse)
        }

        Instrumentation.log(
            "Claude response received (status \(httpResponse.statusCode))",
            area: .aiAnalysis,
            level: .info,
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

    private func buildRequestBody(payload: AIRequestPayload, prompt: String, structuredOutputEnabled: Bool) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let payloadData = try encoder.encode(payload)
        let payloadString = String(data: payloadData, encoding: .utf8) ?? "{}"

        let systemText: String
        if structuredOutputEnabled {
            systemText = """
                You are a spectral analysis assistant. Respond only with valid JSON. Do not wrap JSON in markdown fences. \
                The JSON must have these keys: "summary" (string), "insights" (array of strings), \
                "risks" (array of strings), "actions" (array of strings), and optionally "recommendations" \
                (array of objects with "ingredient", "amount", "rationale" string fields).
                """
        } else {
            systemText = "You are a spectral analysis assistant. Respond in clear, concise paragraphs with actionable insights."
        }

        let userText: String
        if structuredOutputEnabled {
            userText = """
                \(prompt)

                Return JSON only.

                Spectra payload (JSON):
                \(payloadString)
                """
        } else {
            userText = """
                \(prompt)

                Spectra payload (JSON):
                \(payloadString)
                """
        }

        let requestDict: [String: Any] = [
            "model": model.trimmingCharacters(in: .whitespacesAndNewlines),
            "max_tokens": maxTokens,
            "system": systemText,
            "messages": [
                ["role": "user", "content": userText]
            ]
        ]

        return try JSONSerialization.data(withJSONObject: requestDict)
    }

    // MARK: - Response Parsing

    static func parseResponse(_ data: Data) -> ParsedAIResponse {
        let tokenUsage = extractTokenUsage(from: data)
        var response: ParsedAIResponse
        // Anthropic format: { "content": [ { "type": "text", "text": "..." } ] }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let content = json["content"] as? [[String: Any]],
           let first = content.first,
           let text = first["text"] as? String {
            response = OpenAIProvider.parseStructuredOutput(text: text)
        } else {
            let fallback = String(data: data, encoding: .utf8) ?? "Empty response"
            response = OpenAIProvider.parseStructuredOutput(text: fallback)
        }
        response.tokenUsage = tokenUsage
        return response
    }

    /// Extract token usage from Anthropic response: `usage.input_tokens`, `usage.output_tokens`.
    private static func extractTokenUsage(from data: Data) -> TokenUsage? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let usage = json["usage"] as? [String: Any] else { return nil }
        let input = usage["input_tokens"] as? Int ?? 0
        let output = usage["output_tokens"] as? Int ?? 0
        guard input > 0 || output > 0 else { return nil }
        return TokenUsage(promptTokens: input, completionTokens: output)
    }
}
