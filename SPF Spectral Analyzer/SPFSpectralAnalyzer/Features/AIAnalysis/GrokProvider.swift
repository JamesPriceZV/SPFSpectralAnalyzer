import Foundation

// MARK: - xAI Grok Provider

/// AI provider that sends requests to the xAI Grok API (OpenAI-compatible format).
struct GrokProvider: AIAnalysisProvider {
    let displayName = "xAI Grok"

    let model: String
    let apiKey: String
    let maxTokens: Int

    func isAvailable() -> Bool {
        !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !apiKey.isEmpty
    }

    func analyze(payload: AIRequestPayload, prompt: String, structuredOutputEnabled: Bool) async throws -> ParsedAIResponse {
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModel.isEmpty else { throw AIAuthError.missingGrokModel }
        guard !apiKey.isEmpty else { throw AIAuthError.missingAPIKey }

        let body = try buildRequestBody(payload: payload, prompt: prompt, structuredOutputEnabled: structuredOutputEnabled)

        guard let url = URL(string: "https://api.x.ai/v1/chat/completions") else {
            throw AIAuthError.grokConnectionFailed("Invalid endpoint URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = body

        Instrumentation.log(
            "Grok request sending (model \(trimmedModel))",
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
                "Grok response failed (status \(httpResponse.statusCode))",
                area: .aiAnalysis,
                level: .warning,
                payloadBytes: data.count
            )
            throw URLError(.badServerResponse)
        }

        Instrumentation.log(
            "Grok response received (status \(httpResponse.statusCode))",
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

        // Grok uses OpenAI-compatible chat completions format
        let requestDict: [String: Any] = [
            "model": model.trimmingCharacters(in: .whitespacesAndNewlines),
            "max_tokens": maxTokens,
            "messages": [
                ["role": "system", "content": systemText],
                ["role": "user", "content": userText]
            ]
        ]

        return try JSONSerialization.data(withJSONObject: requestDict)
    }

    // MARK: - Response Parsing

    static func parseResponse(_ data: Data) -> ParsedAIResponse {
        // Reuse OpenAI's token extraction (Grok uses the same format)
        let tokenUsage = OpenAIProvider.extractTokenUsage(from: data)
        var response: ParsedAIResponse
        // Grok uses OpenAI-compatible format: { "choices": [ { "message": { "content": "..." } } ] }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let choices = json["choices"] as? [[String: Any]],
           let first = choices.first,
           let message = first["message"] as? [String: Any],
           let content = message["content"] as? String {
            response = OpenAIProvider.parseStructuredOutput(text: content)
        } else {
            let fallback = String(data: data, encoding: .utf8) ?? "Empty response"
            response = OpenAIProvider.parseStructuredOutput(text: fallback)
        }
        response.tokenUsage = tokenUsage
        return response
    }
}
