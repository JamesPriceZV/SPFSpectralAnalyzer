import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// AI-powered parser that extracts structured ingredient data from formula card text.
/// Stateless service following the project's `enum` service pattern.
///
/// Uses FoundationModels (on-device AI) when available, falls back to OpenAI.
enum FormulaCardParser {

    /// Intermediate JSON structure matching the AI output format.
    private struct AIIngredientOutput: Codable {
        var ingredients: [IngredientEntry]
        var ph: Double?
        var totalWeight: Double?
        var totalWeightUnit: String?

        struct IngredientEntry: Codable {
            var name: String
            var quantity: Double?
            var unit: String?
            var percentage: Double?
            var category: String?
        }
    }

    #if canImport(FoundationModels)
    @Generable(description: "A single ingredient in a sunscreen formula")
    struct OnDeviceIngredient {
        @Guide(description: "Ingredient name (e.g. Zinc Oxide, Octocrylene)")
        var name: String
        @Guide(description: "Quantity value (numeric)")
        var quantity: Double?
        @Guide(description: "Unit of measurement (g, mg, %)")
        var unit: String?
        @Guide(description: "Weight percentage of total formula")
        var percentage: Double?
        @Guide(description: "Functional category (UV filter, emollient, preservative, emulsifier, thickener, solvent, fragrance, other)")
        var category: String?
    }

    @Generable(description: "Parsed formula card data with ingredients and pH")
    struct OnDeviceFormulaOutput {
        @Guide(description: "List of ingredients with quantities and categories", .maximumCount(50))
        var ingredients: [OnDeviceIngredient]
        @Guide(description: "Formula pH value if found")
        var ph: Double?
    }
    #endif

    // MARK: - Public API

    /// Parse extracted formula card text into structured ingredient data.
    /// Tries on-device AI first, falls back to OpenAI if configured.
    /// - Parameters:
    ///   - text: Extracted text from the formula card document
    ///   - openAIEndpoint: OpenAI API endpoint URL
    ///   - openAIModel: OpenAI model name
    ///   - openAIAPIKey: OpenAI API key
    /// - Returns: Tuple of parsed ingredients and optional pH value
    static func parseIngredients(
        from text: String,
        openAIEndpoint: String = "",
        openAIModel: String = "",
        openAIAPIKey: String? = nil
    ) async throws -> (ingredients: [FormulaIngredient], ph: Double?, totalWeightGrams: Double?) {
        // Try on-device first
        #if canImport(FoundationModels)
        if SystemLanguageModel.default.isAvailable {
            do {
                return try await parseWithFoundationModels(text: text)
            } catch {
                Instrumentation.log(
                    "FormulaCardParser: on-device parsing failed, trying OpenAI",
                    area: .aiAnalysis, level: .info,
                    details: "error=\(error.localizedDescription)"
                )
            }
        }
        #endif

        // Fall back to OpenAI
        if let apiKey = openAIAPIKey, !apiKey.isEmpty, !openAIEndpoint.isEmpty {
            return try await parseWithOpenAI(
                text: text,
                endpoint: openAIEndpoint,
                model: openAIModel,
                apiKey: apiKey
            )
        }

        throw FormulaCardParserError.noAIProviderAvailable
    }

    // MARK: - FoundationModels (On-Device)

    #if canImport(FoundationModels)
    private static func parseWithFoundationModels(text: String) async throws -> (ingredients: [FormulaIngredient], ph: Double?, totalWeightGrams: Double?) {
        let session = LanguageModelSession(instructions: "You are a cosmetic formulation expert that parses formula cards into structured ingredient data.")
        let prompt = buildPromptForOnDevice(text: text)

        let response = try await session.respond(to: prompt, generating: OnDeviceFormulaOutput.self)
        let output = response.content

        let ingredients = output.ingredients.map { entry in
            FormulaIngredient(
                name: entry.name,
                quantity: entry.quantity,
                unit: entry.unit,
                percentage: entry.percentage,
                category: entry.category
            )
        }

        let totalWeight = calculateTotalWeight(from: ingredients)
        let withPercentages = calculatePercentages(ingredients: ingredients, totalWeight: totalWeight)

        return (ingredients: withPercentages, ph: output.ph, totalWeightGrams: totalWeight)
    }

    private static func buildPromptForOnDevice(text: String) -> String {
        """
        You are a cosmetic formulation expert. Parse the following formula card text and extract \
        all ingredients with their quantities, units, and functional categories.

        Categories should be one of: UV filter, emollient, preservative, emulsifier, thickener, \
        solvent, fragrance, antioxidant, humectant, surfactant, chelating agent, pH adjuster, other.

        Also extract the pH value if mentioned.

        Formula card text:
        \(text)
        """
    }
    #endif

    // MARK: - OpenAI Fallback

    private static func parseWithOpenAI(
        text: String,
        endpoint: String,
        model: String,
        apiKey: String
    ) async throws -> (ingredients: [FormulaIngredient], ph: Double?, totalWeightGrams: Double?) {
        let prompt = buildPromptForOpenAI(text: text)

        guard let url = URL(string: endpoint) else {
            throw FormulaCardParserError.invalidEndpoint
        }

        let requestBody: [String: Any] = [
            "model": model,
            "input": [
                ["role": "system", "content": "You are a cosmetic formulation expert that parses formula cards into structured JSON."],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.1,
            "text": ["format": ["type": "json_object"]]
        ]

        let bodyData = try JSONSerialization.data(withJSONObject: requestBody)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = bodyData

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw FormulaCardParserError.apiError("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }

        // Parse the OpenAI Responses API response format
        let jsonText = try extractTextFromOpenAIResponse(data: data)
        return try parseJSONResponse(jsonText)
    }

    private static func buildPromptForOpenAI(text: String) -> String {
        """
        Parse the following formula card text and extract all ingredients. Return ONLY valid JSON in this exact format:
        {
          "ingredients": [
            {
              "name": "ingredient name",
              "quantity": 5.0,
              "unit": "g",
              "percentage": null,
              "category": "UV filter"
            }
          ],
          "ph": 7.0,
          "totalWeight": 100.0,
          "totalWeightUnit": "g"
        }

        Categories must be one of: UV filter, emollient, preservative, emulsifier, thickener, \
        solvent, fragrance, antioxidant, humectant, surfactant, chelating agent, pH adjuster, other.

        If a value is not found, use null. Calculate percentages from quantities if total weight is known.

        Formula card text:
        \(text)
        """
    }

    /// Extract text content from OpenAI Responses API JSON.
    private static func extractTextFromOpenAIResponse(data: Data) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FormulaCardParserError.parseError("Invalid JSON response")
        }

        // Responses API format: { "output": [ { "content": [ { "text": "..." } ] } ] }
        if let output = json["output"] as? [[String: Any]],
           let first = output.first,
           let content = first["content"] as? [[String: Any]],
           let textItem = content.first,
           let text = textItem["text"] as? String {
            return text
        }

        // Chat completions fallback: { "choices": [ { "message": { "content": "..." } } ] }
        if let choices = json["choices"] as? [[String: Any]],
           let first = choices.first,
           let message = first["message"] as? [String: Any],
           let content = message["content"] as? String {
            return content
        }

        throw FormulaCardParserError.parseError("Could not extract text from AI response")
    }

    /// Parse the JSON response into FormulaIngredient array.
    private static func parseJSONResponse(_ jsonText: String) throws -> (ingredients: [FormulaIngredient], ph: Double?, totalWeightGrams: Double?) {
        guard let data = jsonText.data(using: .utf8) else {
            throw FormulaCardParserError.parseError("Invalid UTF-8 in response")
        }

        let output = try JSONDecoder().decode(AIIngredientOutput.self, from: data)

        let ingredients = output.ingredients.map { entry in
            FormulaIngredient(
                name: entry.name,
                quantity: entry.quantity,
                unit: entry.unit,
                percentage: entry.percentage,
                category: entry.category
            )
        }

        let totalWeight = output.totalWeight ?? calculateTotalWeight(from: ingredients)
        let withPercentages = calculatePercentages(ingredients: ingredients, totalWeight: totalWeight)

        return (ingredients: withPercentages, ph: output.ph, totalWeightGrams: totalWeight)
    }

    // MARK: - Percentage Calculation

    /// Calculate total weight from ingredient quantities (only those in grams).
    private static func calculateTotalWeight(from ingredients: [FormulaIngredient]) -> Double? {
        let gramIngredients = ingredients.filter { ($0.unit?.lowercased() ?? "g") == "g" }
        let total = gramIngredients.compactMap(\.quantity).reduce(0, +)
        return total > 0 ? total : nil
    }

    /// Fill in missing percentages from quantity/totalWeight.
    private static func calculatePercentages(ingredients: [FormulaIngredient], totalWeight: Double?) -> [FormulaIngredient] {
        guard let total = totalWeight, total > 0 else { return ingredients }

        return ingredients.map { ingredient in
            var updated = ingredient
            if updated.percentage == nil, let qty = updated.quantity,
               (updated.unit?.lowercased() ?? "g") == "g" {
                updated.percentage = (qty / total) * 100.0
            }
            return updated
        }
    }
}

// MARK: - Errors

enum FormulaCardParserError: Error, LocalizedError {
    case noAIProviderAvailable
    case invalidEndpoint
    case apiError(String)
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .noAIProviderAvailable: return "No AI provider available. Enable Apple Intelligence or configure OpenAI."
        case .invalidEndpoint: return "Invalid OpenAI endpoint URL"
        case .apiError(let detail): return "AI API error: \(detail)"
        case .parseError(let detail): return "Failed to parse AI response: \(detail)"
        }
    }
}
