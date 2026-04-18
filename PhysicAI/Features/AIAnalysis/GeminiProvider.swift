import Foundation

// MARK: - Google Gemini Provider

/// AI provider that sends requests to the Google Gemini API.
struct GeminiProvider: AIAnalysisProvider {
    let displayName = "Google Gemini"

    let model: String
    let apiKey: String
    let maxTokens: Int

    func isAvailable() -> Bool {
        !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !apiKey.isEmpty
    }

    func analyze(payload: AIRequestPayload, prompt: String, structuredOutputEnabled: Bool) async throws -> ParsedAIResponse {
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModel.isEmpty else { throw AIAuthError.missingGeminiModel }
        guard !apiKey.isEmpty else { throw AIAuthError.missingAPIKey }

        let body = try buildRequestBody(payload: payload, prompt: prompt, structuredOutputEnabled: structuredOutputEnabled)

        // Gemini uses API key as query parameter, not in headers
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(trimmedModel):generateContent?key=\(apiKey)") else {
            throw AIAuthError.geminiConnectionFailed("Invalid endpoint URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        Instrumentation.log(
            "Gemini request sending (model \(trimmedModel))",
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
                "Gemini response failed (status \(httpResponse.statusCode))",
                area: .aiAnalysis,
                level: .warning,
                payloadBytes: data.count
            )
            throw URLError(.badServerResponse)
        }

        Instrumentation.log(
            "Gemini response received (status \(httpResponse.statusCode))",
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
        let payloadString = try payload.encodedJSONString()
        let systemText = AIRequestPayload.systemPrompt(structured: structuredOutputEnabled)
        let userText = AIRequestPayload.userMessage(prompt: prompt, payloadJSON: payloadString, structured: structuredOutputEnabled)

        // Gemini API format: contents array with parts
        let requestDict: [String: Any] = [
            "systemInstruction": [
                "parts": [["text": systemText]]
            ],
            "contents": [
                ["parts": [["text": userText]]]
            ],
            "generationConfig": [
                "maxOutputTokens": maxTokens
            ]
        ]

        return try JSONSerialization.data(withJSONObject: requestDict)
    }

    // MARK: - Response Parsing

    static func parseResponse(_ data: Data) -> ParsedAIResponse {
        let tokenUsage = extractTokenUsage(from: data)
        var response: ParsedAIResponse
        // Gemini format: { "candidates": [ { "content": { "parts": [ { "text": "..." } ] } } ] }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let candidates = json["candidates"] as? [[String: Any]],
           let first = candidates.first,
           let content = first["content"] as? [String: Any],
           let parts = content["parts"] as? [[String: Any]],
           let firstPart = parts.first,
           let text = firstPart["text"] as? String {
            response = OpenAIProvider.parseStructuredOutput(text: text)
        } else {
            let fallback = String(data: data, encoding: .utf8) ?? "Empty response"
            response = OpenAIProvider.parseStructuredOutput(text: fallback)
        }
        response.tokenUsage = tokenUsage
        return response
    }

    /// Extract token usage from Gemini response: `usageMetadata.promptTokenCount`, `candidatesTokenCount`.
    private static func extractTokenUsage(from data: Data) -> TokenUsage? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let metadata = json["usageMetadata"] as? [String: Any] else { return nil }
        let prompt = metadata["promptTokenCount"] as? Int ?? 0
        let completion = metadata["candidatesTokenCount"] as? Int ?? 0
        guard prompt > 0 || completion > 0 else { return nil }
        return TokenUsage(promptTokens: prompt, completionTokens: completion)
    }
}
