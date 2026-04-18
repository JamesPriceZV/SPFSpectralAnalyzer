@Article(
    title: "Run AI Analysis"
)

## Overview
AI Analysis summarizes, compares, and interprets spectra using one or more AI providers. The app supports five providers — OpenAI, Anthropic Claude, xAI Grok, Google Gemini, and Apple On-Device Intelligence — with configurable routing, ensemble comparison, and cost tracking.

## Configure AI Providers
1. Open Settings (Command + ,) and go to the AI tab.
2. For each cloud provider you want to use, enter and store the API key (stored securely in the Keychain) and select a model.
3. Use the Test button next to each provider to confirm connectivity.
4. On-Device AI (Apple Intelligence) requires no API key and works fully offline on supported hardware.

### Supported Providers
- OpenAI: GPT-4o, GPT-4, and other OpenAI models. Supports structured JSON output.
- Anthropic Claude: Claude 3.5 Sonnet, Claude 3 Opus, and other Claude models.
- xAI Grok: Grok models for analysis and comparison.
- Google Gemini: Gemini Pro and other Google models.
- On-Device: Apple Intelligence via the FoundationModels framework. Fully offline, no API key needed. Requires macOS 15.1 or later with Apple Intelligence enabled. Shows status: "Device not eligible", "Apple Intelligence disabled", or "Model downloading" when unavailable.

## Run an Analysis
1. Open the Analysis tab in ``ContentView``.
2. In the AI Analysis section of the sidebar, choose a prompt preset such as Summary, Compare Selected, or Formulation Advice.
3. Select a scope for selected spectra or all loaded spectra.
4. Click Run AI Analysis to start the request.
5. Review the response in the sidebar or open the full AI Response popup for a scrollable view.

## AI Response Popup
Click the expand button next to the AI Response header to open a resizable popup window. The entire popup scrolls as a single view, showing:
- Key Insights
- Risks/Warnings
- Next Steps
- Structured Summary (with ingredient recommendations when available)
- Full AI response text

The popup can be freely resized by dragging the window edges.

## Template Gallery
The Template Gallery provides pre-configured prompt templates for common tasks:
- Summary: Overview of spectral characteristics.
- Compare Selected: Side-by-side analysis of selected spectra.
- Formulation Advice: Ingredient and concentration recommendations.

## Provider Routing
Configure how the app selects which AI provider to use for each request.

### Priority Queue
In Settings, drag to reorder providers in the priority list. The app tries each provider in order until one succeeds. Providers that are over budget or have no configured API key are automatically skipped.

### Function-Specific Routing
Assign different providers for different tasks:
- Spectral analysis can use one provider (e.g., Claude for detailed scientific reasoning).
- Formula card parsing can use another (e.g., GPT-4o for structured extraction).
Configure this in Settings under Advanced Routing.

### Smart Routing
When enabled, the app automatically selects the best provider based on the task characteristics, available quotas, and provider strengths.

## Ensemble Mode
Run multiple providers in parallel and compare their outputs side by side:
1. In Settings, enable Ensemble Mode and select which providers to include.
2. When you run an analysis, all selected providers execute simultaneously.
3. The Ensemble Analysis view shows provider results in comparison cards.
4. Click "Use This" on the preferred result to adopt it as the active analysis.

### How Ensemble Determines the Final Analysis
When ensemble mode runs, all selected providers are queried simultaneously via parallel tasks. The first provider to return a successful response becomes the default analysis shown in the AI panel. However, all successful provider responses are preserved and available for comparison. There is no automatic merging, averaging, or voting across providers. Instead, you review each provider's response — including text, structured insights, response time, and token usage — in the Ensemble Comparison view, and manually select the analysis you prefer. Providers that fail (missing API key, network error, rate limit) are logged with diagnostic details and excluded from the comparison.

Ensemble mode is useful for validating results across providers or choosing the best interpretation for complex spectra.

## Cost Tracking
Monitor AI usage and set budget limits:
- The Cost Tracking dashboard in Settings shows token usage and estimated USD cost per provider.
- Monthly summaries break down usage by provider and time period.
- Set budget caps per provider. When a provider exceeds its budget, it is automatically filtered from the priority queue.
- Enable or disable cost tracking in Settings.

## Enterprise Grounding
When Microsoft 365 Enterprise is connected, AI analysis can be grounded in your organization's documents. Enterprise context from SharePoint, OneDrive, and Copilot Connectors is injected into the analysis prompt. Citations show which documents contributed to the response. See <doc:M365Enterprise> for setup instructions.

## How AI Integration Works
- The app packages spectral data, metrics, and metadata from the current selection.
- Requests are sent to the resolved provider based on routing configuration.
- Structured output (JSON schema) is used when the provider supports it. A compatibility mode is available for providers without structured output support.
- Responses are stored in a history for later review and comparison.

## Privacy Notes
- Cloud providers (OpenAI, Claude, Grok, Gemini) transmit spectral data to external API endpoints. Use only approved data and endpoints for your organization.
- On-Device AI processes all data locally on your device. No data leaves your machine.
- Enterprise grounding sends queries to Microsoft 365 under your organization's security policies.
- API keys are stored in the system Keychain, not in plain text.
