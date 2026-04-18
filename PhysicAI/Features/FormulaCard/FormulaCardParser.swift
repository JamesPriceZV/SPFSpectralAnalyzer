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
            var inciName: String?
            var inciNames: [String]?
            var quantity: Double?
            var unit: String?
            var percentage: Double?
            var category: String?
        }
    }

    #if canImport(FoundationModels)
    @Generable(description: "A single ingredient in a sunscreen formula")
    struct OnDeviceIngredient {
        @Guide(description: "Trade name or common ingredient name (e.g. Parsol 1789, Zinc Oxide)")
        var name: String
        @Guide(description: "INCI name if different from the trade name (e.g. Butyl Methoxydibenzoylmethane)")
        var inciName: String?
        @Guide(description: "If this trade name contains multiple INCI ingredients, list all INCI names here")
        var inciNames: [String]?
        @Guide(description: "Quantity value (numeric). Interpret columns titled 'Actual' as weight in milligrams.")
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

    // MARK: - Fallback API

    /// Parse with automatic fallback across providers in priority order.
    /// Tries each provider in sequence; on failure, logs the error and moves to the next.
    /// Returns the result along with which provider succeeded.
    static func parseWithFallback(
        from text: String,
        providerPriorityOrder: [AIProviderID],
        credentials: ProviderCredentials,
        enterpriseContext: String? = nil
    ) async throws -> (ingredients: [FormulaIngredient], ph: Double?, totalWeightGrams: Double?, usedProvider: AIProviderID) {
        var errors: [(AIProviderID, String)] = []

        for providerID in providerPriorityOrder {
            // Skip providers without credentials
            guard isProviderAvailable(providerID, credentials: credentials) else { continue }

            do {
                let result = try await parseIngredients(
                    from: text,
                    providerID: providerID,
                    credentials: credentials,
                    enterpriseContext: enterpriseContext
                )
                return (result.ingredients, result.ph, result.totalWeightGrams, providerID)
            } catch {
                let detail = error.localizedDescription
                errors.append((providerID, detail))
                Instrumentation.log(
                    "FormulaCardParser: \(providerID.displayName) failed, trying next",
                    area: .processing, level: .warning,
                    details: "error=\(detail)"
                )
                continue
            }
        }

        // All providers failed
        if errors.isEmpty {
            throw FormulaCardParserError.noAIProviderAvailable
        }
        let summary = errors.map { "\($0.0.displayName): \($0.1)" }.joined(separator: "; ")
        throw FormulaCardParserError.allProvidersFailed(summary)
    }

    /// Check if a provider has the required credentials/availability.
    private static func isProviderAvailable(_ provider: AIProviderID, credentials: ProviderCredentials) -> Bool {
        switch provider {
        case .onDevice:
            #if canImport(FoundationModels)
            return SystemLanguageModel.default.isAvailable
            #else
            return false
            #endif
        case .claude:
            return credentials.claudeAPIKey != nil && !(credentials.claudeAPIKey?.isEmpty ?? true)
        case .openAI:
            return credentials.openAIAPIKey != nil && !(credentials.openAIAPIKey?.isEmpty ?? true)
        case .grok:
            return credentials.grokAPIKey != nil && !(credentials.grokAPIKey?.isEmpty ?? true)
        case .gemini:
            return credentials.geminiAPIKey != nil && !(credentials.geminiAPIKey?.isEmpty ?? true)
        case .pinnOnDevice:
            return false  // PINN models are for spectral analysis, not text parsing
        case .microsoft:
            return false  // Microsoft Enterprise is not an AI parsing provider
        }
    }

    // MARK: - Routing-Aware Public API

    /// Parse using a resolved provider ID from the routing system.
    /// Called by FormulaCardDetailView after resolving the provider via AIProviderManager.
    static func parseIngredients(
        from text: String,
        providerID: AIProviderID,
        credentials: ProviderCredentials,
        enterpriseContext: String? = nil
    ) async throws -> (ingredients: [FormulaIngredient], ph: Double?, totalWeightGrams: Double?) {
        // If enterprise context is provided, prepend it to the text for richer parsing
        let enrichedText: String
        if let context = enterpriseContext, !context.isEmpty {
            enrichedText = """
            \(text)

            --- ENTERPRISE REFERENCE DATA (from Microsoft 365) ---
            \(context)
            --- END ENTERPRISE REFERENCE DATA ---
            """
        } else {
            enrichedText = text
        }
        _ = enrichedText // Used by provider-specific methods below via text parameter
        switch providerID {
        case .onDevice:
            #if canImport(FoundationModels)
            guard SystemLanguageModel.default.isAvailable else {
                throw FormulaCardParserError.noAIProviderAvailable
            }
            return try await parseWithFoundationModels(text: text)
            #else
            throw FormulaCardParserError.noAIProviderAvailable
            #endif
        case .claude:
            guard let key = credentials.claudeAPIKey, !key.isEmpty else {
                throw FormulaCardParserError.noAIProviderAvailable
            }
            return try await parseWithClaude(text: text, model: credentials.claudeModel, apiKey: key)
        case .openAI:
            guard let key = credentials.openAIAPIKey, !key.isEmpty else {
                throw FormulaCardParserError.noAIProviderAvailable
            }
            return try await parseWithOpenAI(
                text: text, endpoint: credentials.openAIEndpoint,
                model: credentials.openAIModel, apiKey: key
            )
        case .grok:
            guard let key = credentials.grokAPIKey, !key.isEmpty else {
                throw FormulaCardParserError.noAIProviderAvailable
            }
            return try await parseWithGrok(text: text, model: credentials.grokModel, apiKey: key)
        case .gemini:
            guard let key = credentials.geminiAPIKey, !key.isEmpty else {
                throw FormulaCardParserError.noAIProviderAvailable
            }
            return try await parseWithGemini(text: text, model: credentials.geminiModel, apiKey: key)
        case .pinnOnDevice:
            throw FormulaCardParserError.noAIProviderAvailable  // PINN models don't parse text
        case .microsoft:
            throw FormulaCardParserError.noAIProviderAvailable  // Not an AI parsing provider
        }
    }

    // MARK: - Legacy Public API

    /// Parse extracted formula card text into structured ingredient data.
    /// Respects the user's AI provider preference for provider ordering.
    /// - Parameters:
    ///   - text: Extracted text from the formula card document
    ///   - preference: User's AI provider preference (auto, onDevice, openAI, claude)
    ///   - openAIEndpoint: OpenAI API endpoint URL
    ///   - openAIModel: OpenAI model name
    ///   - openAIAPIKey: OpenAI API key
    ///   - claudeModel: Anthropic Claude model name
    ///   - claudeAPIKey: Anthropic Claude API key
    /// - Returns: Tuple of parsed ingredients and optional pH value
    static func parseIngredients(
        from text: String,
        preference: AIProviderPreference = .auto,
        openAIEndpoint: String = "",
        openAIModel: String = "",
        openAIAPIKey: String? = nil,
        claudeModel: String = "",
        claudeAPIKey: String? = nil,
        grokModel: String = "",
        grokAPIKey: String? = nil,
        geminiModel: String = "",
        geminiAPIKey: String? = nil
    ) async throws -> (ingredients: [FormulaIngredient], ph: Double?, totalWeightGrams: Double?) {
        switch preference {
        case .auto:
            // Try on-device first, then Claude, then OpenAI, then Grok, then Gemini
            #if canImport(FoundationModels)
            if SystemLanguageModel.default.isAvailable {
                do {
                    return try await parseWithFoundationModels(text: text)
                } catch {
                    Instrumentation.log(
                        "FormulaCardParser: on-device parsing failed, trying cloud fallback",
                        area: .aiAnalysis, level: .info,
                        details: "error=\(error.localizedDescription)"
                    )
                }
            }
            #endif

            // Try Claude
            if let key = claudeAPIKey, !key.isEmpty, !claudeModel.isEmpty {
                do {
                    return try await parseWithClaude(text: text, model: claudeModel, apiKey: key)
                } catch {
                    Instrumentation.log(
                        "FormulaCardParser: Claude parsing failed, trying OpenAI",
                        area: .aiAnalysis, level: .info,
                        details: "error=\(error.localizedDescription)"
                    )
                }
            }

            // Try OpenAI
            if let key = openAIAPIKey, !key.isEmpty, !openAIEndpoint.isEmpty {
                do {
                    return try await parseWithOpenAI(
                        text: text, endpoint: openAIEndpoint,
                        model: openAIModel, apiKey: key
                    )
                } catch {
                    Instrumentation.log(
                        "FormulaCardParser: OpenAI parsing failed, trying Grok",
                        area: .aiAnalysis, level: .info,
                        details: "error=\(error.localizedDescription)"
                    )
                }
            }

            // Try Grok (OpenAI-compatible)
            if let key = grokAPIKey, !key.isEmpty, !grokModel.isEmpty {
                do {
                    return try await parseWithGrok(text: text, model: grokModel, apiKey: key)
                } catch {
                    Instrumentation.log(
                        "FormulaCardParser: Grok parsing failed, trying Gemini",
                        area: .aiAnalysis, level: .info,
                        details: "error=\(error.localizedDescription)"
                    )
                }
            }

            // Try Gemini
            if let key = geminiAPIKey, !key.isEmpty, !geminiModel.isEmpty {
                return try await parseWithGemini(text: text, model: geminiModel, apiKey: key)
            }

            throw FormulaCardParserError.noAIProviderAvailable

        case .onDevice:
            #if canImport(FoundationModels)
            guard SystemLanguageModel.default.isAvailable else {
                throw FormulaCardParserError.noAIProviderAvailable
            }
            return try await parseWithFoundationModels(text: text)
            #else
            throw FormulaCardParserError.noAIProviderAvailable
            #endif

        case .claude:
            guard let key = claudeAPIKey, !key.isEmpty, !claudeModel.isEmpty else {
                throw FormulaCardParserError.noAIProviderAvailable
            }
            return try await parseWithClaude(text: text, model: claudeModel, apiKey: key)

        case .openAI:
            guard let key = openAIAPIKey, !key.isEmpty, !openAIEndpoint.isEmpty else {
                throw FormulaCardParserError.noAIProviderAvailable
            }
            return try await parseWithOpenAI(
                text: text, endpoint: openAIEndpoint,
                model: openAIModel, apiKey: key
            )

        case .grok:
            guard let key = grokAPIKey, !key.isEmpty, !grokModel.isEmpty else {
                throw FormulaCardParserError.noAIProviderAvailable
            }
            return try await parseWithGrok(text: text, model: grokModel, apiKey: key)

        case .gemini:
            guard let key = geminiAPIKey, !key.isEmpty, !geminiModel.isEmpty else {
                throw FormulaCardParserError.noAIProviderAvailable
            }
            return try await parseWithGemini(text: text, model: geminiModel, apiKey: key)
        }
    }

    // MARK: - FoundationModels (On-Device)

    #if canImport(FoundationModels)
    private static func parseWithFoundationModels(text: String) async throws -> (ingredients: [FormulaIngredient], ph: Double?, totalWeightGrams: Double?) {
        let session = LanguageModelSession(instructions: "You are a cosmetic formulation expert that parses formula cards into structured ingredient data.")
        let prompt = buildPromptForOnDevice(text: text)

        let response = try await session.respond(to: prompt, generating: OnDeviceFormulaOutput.self)
        let output = response.content

        let raw = output.ingredients.map { entry in
            RawParsedIngredient(
                name: entry.name,
                inciName: entry.inciName,
                inciNames: entry.inciNames,
                quantity: entry.quantity,
                unit: entry.unit,
                percentage: entry.percentage,
                category: entry.category
            )
        }
        let ingredients = expandAndNormalize(raw)

        let totalWeight = calculateTotalWeight(from: ingredients)
        let withPercentages = calculatePercentages(ingredients: ingredients, totalWeight: totalWeight)

        return (ingredients: withPercentages, ph: output.ph, totalWeightGrams: totalWeight)
    }

    private static func buildPromptForOnDevice(text: String) -> String {
        """
        You are a cosmetic formulation expert. Parse the following formula card text and extract \
        all ingredients with their quantities, units, and functional categories.

        IMPORTANT RULES:
        - The "name" field should be the trade name or common name as written on the formula card.
        - The "inciName" field MUST be the official INCI (International Nomenclature of Cosmetic \
          Ingredients) name. Always use the canonical INCI name consistently — for example, always \
          use "Aqua" (never "Water"), "Glycerin" (never "Glycerine"), "Tocopherol" (never "Vitamin E"). \
          Do not mix common names with INCI names.
        - If a single trade name ingredient contains MULTIPLE distinct INCI-named sub-ingredients \
          (e.g. a commercial blend), list all INCI names in the "inciNames" array field instead of "inciName".
        - Columns titled "Actual" represent weight in milligrams (mg). Set unit to "mg" for those values.
        - Categories should be one of: UV filter, emollient, preservative, emulsifier, thickener, \
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
              "name": "trade or common name",
              "inciName": "INCI name if different from trade name, or null",
              "inciNames": ["INCI1", "INCI2"],
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

        IMPORTANT RULES:
        - "name" = the trade name or common name as written on the formula card.
        - "inciName" = the official INCI (International Nomenclature of Cosmetic Ingredients) name. \
          Always use the canonical INCI name consistently — for example, always use "Aqua" (never \
          "Water"), "Glycerin" (never "Glycerine"), "Tocopherol" (never "Vitamin E"). Do not mix \
          common names with INCI names. Use null only if the name is already the canonical INCI name.
        - "inciNames" = when a single trade-name ingredient is a blend of multiple INCI-named \
          sub-ingredients, list ALL canonical INCI names here. Use null or omit if not applicable.
        - Columns titled "Actual" represent weight in milligrams. Set "unit" to "mg" for those values.
        - Categories must be one of: UV filter, emollient, preservative, emulsifier, thickener, \
          solvent, fragrance, antioxidant, humectant, surfactant, chelating agent, pH adjuster, other.
        - If a value is not found, use null. Calculate percentages from quantities if total weight is known.

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

        let raw = output.ingredients.map { entry in
            RawParsedIngredient(
                name: entry.name,
                inciName: entry.inciName,
                inciNames: entry.inciNames,
                quantity: entry.quantity,
                unit: entry.unit,
                percentage: entry.percentage,
                category: entry.category
            )
        }
        let ingredients = expandAndNormalize(raw)

        let totalWeight = output.totalWeight ?? calculateTotalWeight(from: ingredients)
        let withPercentages = calculatePercentages(ingredients: ingredients, totalWeight: totalWeight)

        return (ingredients: withPercentages, ph: output.ph, totalWeightGrams: totalWeight)
    }

    // MARK: - 1:Many INCI Expansion

    /// Intermediate type for raw AI output before INCI expansion.
    private struct RawParsedIngredient {
        var name: String
        var inciName: String?
        var inciNames: [String]?
        var quantity: Double?
        var unit: String?
        var percentage: Double?
        var category: String?
    }

    /// Expand 1:many trade name → INCI mappings into individual FormulaIngredient rows.
    /// When a trade name maps to N INCIs without individual weights, divide equally.
    private static func expandAndNormalize(_ raw: [RawParsedIngredient]) -> [FormulaIngredient] {
        var result: [FormulaIngredient] = []

        for entry in raw {
            // Determine INCI list: prefer inciNames array, fall back to single inciName
            let inciList: [String]?
            if let names = entry.inciNames, !names.isEmpty {
                inciList = names
            } else if let single = entry.inciName {
                inciList = [single]
            } else {
                inciList = nil
            }

            // 1:Many expansion — divide quantity and percentage equally
            if let incis = inciList, incis.count > 1 {
                let n = Double(incis.count)
                let dividedQty = entry.quantity.map { $0 / n }
                let dividedPct = entry.percentage.map { $0 / n }

                for inci in incis {
                    result.append(FormulaIngredient(
                        name: entry.name,
                        inciName: inci,
                        quantity: dividedQty,
                        unit: entry.unit,
                        percentage: dividedPct,
                        category: entry.category
                    ))
                }
            } else {
                // 1:1 mapping (or no INCI known)
                result.append(FormulaIngredient(
                    name: entry.name,
                    inciName: inciList?.first,
                    quantity: entry.quantity,
                    unit: entry.unit,
                    percentage: entry.percentage,
                    category: entry.category
                ))
            }
        }

        return result
    }

    // MARK: - Percentage Calculation

    /// Calculate total weight from ingredient quantities (grams and milligrams).
    private static func calculateTotalWeight(from ingredients: [FormulaIngredient]) -> Double? {
        var totalGrams: Double = 0
        for ingredient in ingredients {
            guard let qty = ingredient.quantity else { continue }
            let u = ingredient.unit?.lowercased() ?? "g"
            switch u {
            case "g":  totalGrams += qty
            case "mg": totalGrams += qty / 1000.0
            default:   continue  // skip %, mL, etc.
            }
        }
        return totalGrams > 0 ? totalGrams : nil
    }

    // MARK: - Anthropic Claude

    private static func parseWithClaude(
        text: String,
        model: String,
        apiKey: String
    ) async throws -> (ingredients: [FormulaIngredient], ph: Double?, totalWeightGrams: Double?) {
        let prompt = buildPromptForOpenAI(text: text) // Same JSON schema works for Claude

        let messagesPayload: [[String: Any]] = [
            ["role": "user", "content": prompt]
        ]
        let requestBody: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "system": "You are a cosmetic formulation expert that parses formula cards into structured JSON. Return ONLY valid JSON, no markdown fences.",
            "messages": messagesPayload
        ]

        let bodyData = try JSONSerialization.data(withJSONObject: requestBody)

        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            throw FormulaCardParserError.invalidEndpoint
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = bodyData

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw FormulaCardParserError.apiError("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }

        // Anthropic response: { "content": [ { "type": "text", "text": "..." } ] }
        let jsonText = try extractTextFromClaudeResponse(data: data)
        return try parseJSONResponse(jsonText)
    }

    /// Extract text content from Anthropic Messages API response.
    private static func extractTextFromClaudeResponse(data: Data) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let first = content.first,
              let text = first["text"] as? String else {
            throw FormulaCardParserError.parseError("Could not extract text from Claude response")
        }
        return text
    }

    // MARK: - Grok (OpenAI-Compatible)

    private static func parseWithGrok(
        text: String,
        model: String,
        apiKey: String
    ) async throws -> (ingredients: [FormulaIngredient], ph: Double?, totalWeightGrams: Double?) {
        guard let url = URL(string: "https://api.x.ai/v1/chat/completions") else {
            throw FormulaCardParserError.invalidEndpoint
        }

        let prompt = buildPromptForOpenAI(text: text)
        let requestDict: [String: Any] = [
            "model": model.trimmingCharacters(in: .whitespacesAndNewlines),
            "max_tokens": 4096,
            "messages": [
                ["role": "system", "content": "You are a cosmetic formulation expert. Parse formula cards into structured JSON ingredient data."],
                ["role": "user", "content": prompt]
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestDict)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw FormulaCardParserError.apiError("Grok API returned status \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }

        // Grok uses OpenAI-compatible response format
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw FormulaCardParserError.parseError("Could not extract text from Grok response")
        }

        return try parseJSONResponse(content)
    }

    // MARK: - Gemini

    private static func parseWithGemini(
        text: String,
        model: String,
        apiKey: String
    ) async throws -> (ingredients: [FormulaIngredient], ph: Double?, totalWeightGrams: Double?) {
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(trimmedModel):generateContent?key=\(apiKey)") else {
            throw FormulaCardParserError.invalidEndpoint
        }

        let prompt = buildPromptForOpenAI(text: text)
        let requestDict: [String: Any] = [
            "systemInstruction": [
                "parts": [["text": "You are a cosmetic formulation expert. Parse formula cards into structured JSON ingredient data."]]
            ],
            "contents": [
                ["parts": [["text": prompt]]]
            ],
            "generationConfig": [
                "maxOutputTokens": 4096
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestDict)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw FormulaCardParserError.apiError("Gemini API returned status \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }

        // Gemini response format
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let responseText = firstPart["text"] as? String else {
            throw FormulaCardParserError.parseError("Could not extract text from Gemini response")
        }

        return try parseJSONResponse(responseText)
    }

    /// Fill in missing percentages from quantity/totalWeight (handles both g and mg).
    private static func calculatePercentages(ingredients: [FormulaIngredient], totalWeight: Double?) -> [FormulaIngredient] {
        guard let total = totalWeight, total > 0 else { return ingredients }

        return ingredients.map { ingredient in
            var updated = ingredient
            if updated.percentage == nil, let qty = updated.quantity {
                let u = updated.unit?.lowercased() ?? "g"
                let qtyInGrams: Double?
                switch u {
                case "g":  qtyInGrams = qty
                case "mg": qtyInGrams = qty / 1000.0
                default:   qtyInGrams = nil
                }
                if let g = qtyInGrams {
                    updated.percentage = (g / total) * 100.0
                }
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
    case allProvidersFailed(String)

    var errorDescription: String? {
        switch self {
        case .noAIProviderAvailable: return "No AI provider available. Enable Apple Intelligence or configure OpenAI."
        case .invalidEndpoint: return "Invalid OpenAI endpoint URL"
        case .apiError(let detail): return "AI API error: \(detail)"
        case .parseError(let detail): return "Failed to parse AI response: \(detail)"
        case .allProvidersFailed(let summary): return "All AI providers failed: \(summary)"
        }
    }
}
