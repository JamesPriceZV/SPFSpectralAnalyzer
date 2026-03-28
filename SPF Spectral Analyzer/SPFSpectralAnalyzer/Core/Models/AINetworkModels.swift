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

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "OpenAI API key is not configured."
        case .missingOpenAIEndpoint:
            return "OpenAI endpoint is not configured."
        case .invalidOpenAIEndpoint:
            return "OpenAI endpoint is invalid."
        case .missingOpenAIModel:
            return "OpenAI model is not configured."
        case .openAIConnectionFailed(let message):
            return "OpenAI connection failed: \(message)"
        }
    }
}

// MARK: - AI Structured Output

struct AIStructuredOutput: Codable {
    var summary: String?
    var insights: [String]
    var risks: [String]
    var actions: [String]
    var recommendations: [AIRecommendation]?
}

struct AIRecommendation: Codable, Identifiable {
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

struct ParsedAIResponse {
    let text: String
    let structured: AIStructuredOutput?
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
