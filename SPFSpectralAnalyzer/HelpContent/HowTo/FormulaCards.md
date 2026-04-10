@Article(
    title: "Formula Card Parsing"
)

## Overview
Use AI-powered parsing to extract structured ingredient lists from sunscreen formula cards. The app analyzes formula card text (from PDFs, images, or pasted text) and returns a structured breakdown of each ingredient with its INCI name, quantity, percentage, and functional category.

## How It Works
1. Open the Formula Card detail view from the Analysis tab or Data Management.
2. Provide formula card content by pasting text, importing a PDF, or capturing an image.
3. The app sends the content to your configured AI provider for structured extraction.
4. Review the parsed ingredient list in a table with columns for name, INCI name, quantity, percentage, and category.

## Extracted Information
For each ingredient, the parser identifies:
- Ingredient name: The common or trade name
- INCI name: The International Nomenclature of Cosmetic Ingredients identifier
- Quantity: The amount specified in the formula
- Percentage: The weight percentage in the formulation
- Category: Functional classification such as UV filter, emollient, preservative, surfactant, thickener, antioxidant, or fragrance

## Provider Routing
Formula card parsing routes through the multi-provider AI system. You can configure which provider handles formula parsing separately from spectral analysis using function-specific routing in Settings. The parser works with all supported providers:
- OpenAI (GPT models)
- Anthropic Claude
- xAI Grok
- Google Gemini
- On-Device (Apple Intelligence, no network required)

## Enterprise Grounding
When Microsoft 365 Enterprise integration is enabled, formula card parsing can optionally incorporate enterprise context from your organization's SharePoint and OneDrive content. This enriches ingredient identification with internal formulation databases and proprietary naming conventions.

## Tips
- For best results, ensure formula card text is clearly legible before parsing.
- The on-device provider works well for standard formula cards and requires no API key.
- Use function-specific routing to assign a specialized provider for formula parsing while keeping a different provider for spectral analysis.
