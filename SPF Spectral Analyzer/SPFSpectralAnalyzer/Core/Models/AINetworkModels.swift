import Foundation

// MARK: - AI Request Payloads

struct AIRequestPayload: Encodable {
    var preset: String
    var prompt: String
    var temperature: Double
    var maxTokens: Int
    var selectionScope: String
    var yAxisMode: String
    var metricsRange: [Double]
    var spectra: [AISpectrumPayload]
    var mlPrediction: AIMLPredictionPayload?
    var formulaIngredients: [AIFormulaIngredientPayload]?
}

struct AIMLPredictionPayload: Encodable {
    var spfEstimate: Double
    var confidenceLow: Double
    var confidenceHigh: Double
}

struct AIFormulaIngredientPayload: Encodable {
    var name: String
    var inciName: String?
    var percentage: Double?
    var category: String?
}

struct AISpectrumPayload: Encodable {
    var name: String
    var points: [AIPointPayload]
    var metrics: AIMetricsPayload?
}

struct AIPointPayload: Encodable {
    var x: Double
    var y: Double
}

struct AIMetricsPayload: Encodable {
    var criticalWavelength: Double
    var uvaUvbRatio: Double
    var meanUVB: Double
}

// MARK: - AI Auth

enum AIAuthError: LocalizedError {
    case missingAPIKey
    case missingOpenAIEndpoint
    case invalidOpenAIEndpoint
    case missingOpenAIModel
    case openAIConnectionFailed(String)
    case missingClaudeModel
    case invalidClaudeEndpoint
    case claudeConnectionFailed(String)
    case missingGrokModel
    case grokConnectionFailed(String)
    case missingGeminiModel
    case geminiConnectionFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "API key is not configured."
        case .missingOpenAIEndpoint:
            return "OpenAI endpoint is not configured."
        case .invalidOpenAIEndpoint:
            return "OpenAI endpoint is invalid."
        case .missingOpenAIModel:
            return "OpenAI model is not configured."
        case .openAIConnectionFailed(let message):
            return "OpenAI connection failed: \(message)"
        case .missingClaudeModel:
            return "Anthropic Claude model is not configured."
        case .invalidClaudeEndpoint:
            return "Anthropic API endpoint is invalid."
        case .claudeConnectionFailed(let message):
            return "Claude connection failed: \(message)"
        case .missingGrokModel:
            return "xAI Grok model is not configured."
        case .grokConnectionFailed(let message):
            return "Grok connection failed: \(message)"
        case .missingGeminiModel:
            return "Google Gemini model is not configured."
        case .geminiConnectionFailed(let message):
            return "Gemini connection failed: \(message)"
        }
    }
}

// MARK: - AI Structured Output

struct AIStructuredOutput: Codable, Sendable {
    var summary: String?
    var insights: [String]
    var risks: [String]
    var actions: [String]
    var recommendations: [AIRecommendation]?
}

struct AIRecommendation: Codable, Identifiable, Sendable {
    let id = UUID()
    var ingredient: String
    var amount: String
    var rationale: String?

    enum CodingKeys: String, CodingKey {
        case ingredient
        case amount
        case rationale
    }
}

struct ParsedAIResponse: Sendable {
    let text: String
    let structured: AIStructuredOutput?
    var tokenUsage: TokenUsage?
}

struct AIResponse: Decodable {
    var text: String
}

// MARK: - OpenAI Responses API

struct OpenAIResponsesRequest: Encodable {
    var model: String
    var input: [OpenAIInputMessage]
    var temperature: Double
    var maxOutputTokens: Int
    var text: OpenAIResponseText?

    enum CodingKeys: String, CodingKey {
        case model
        case input
        case temperature
        case maxOutputTokens = "max_output_tokens"
        case text
    }
}

struct OpenAIResponseText: Encodable {
    var format: OpenAIResponseTextFormat
}

struct OpenAIResponseTextFormat: Encodable {
    var type: String
    var name: String
    var strict: Bool
    var schema: JSONSchema
}

final class JSONSchema: Encodable {
    var type: String
    var properties: [String: JSONSchema]?
    var items: JSONSchema?
    var required: [String]?
    var description: String?
    var additionalProperties: Bool?
    var enumValues: [String]?

    init(
        type: String,
        properties: [String: JSONSchema]? = nil,
        items: JSONSchema? = nil,
        required: [String]? = nil,
        description: String? = nil,
        additionalProperties: Bool? = nil,
        enumValues: [String]? = nil
    ) {
        self.type = type
        self.properties = properties
        self.items = items
        self.required = required
        self.description = description
        self.additionalProperties = additionalProperties
        self.enumValues = enumValues
    }

    enum CodingKeys: String, CodingKey {
        case type
        case properties
        case items
        case required
        case description
        case additionalProperties
        case enumValues = "enum"
    }
}

struct OpenAIInputMessage: Encodable {
    var type: String = "message"
    var role: String
    var content: [OpenAIInputContent]
}

struct OpenAIInputContent: Encodable {
    var type: String = "input_text"
    var text: String

    init(text: String) {
        self.text = text
    }
}

struct OpenAIResponsesResponse: Decodable {
    var output: [OpenAIOutputItem]?

    var outputText: String? {
        let contents = output?.flatMap { $0.content ?? [] } ?? []
        let texts = contents.compactMap { content in
            if let type = content.type, type == "output_text" || type == "text" {
                return content.text
            }
            return content.text
        }
        return texts.first
    }
}

struct OpenAIOutputItem: Decodable {
    var type: String?
    var content: [OpenAIOutputContent]?
}

struct OpenAIOutputContent: Decodable {
    var type: String?
    var text: String?
}
