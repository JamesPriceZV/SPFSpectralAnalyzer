@Article(
    title: "Run AI Analysis"
)

## Overview
AI Analysis summarizes and compares spectra using your configured OpenAI-compatible endpoint.

## Enable AI Analysis
1. Open Settings (Command + ,).
2. Turn on AI Analysis.
3. Enter and store your API key (stored securely in the Keychain).
4. Confirm connectivity with the Test OpenAI action.

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

## How AI Integration Works
- The app packages spectral data, metrics, and metadata from the current selection.
- Requests are sent to the configured endpoint with the selected model name.
- Structured output (JSON schema) is used when the model supports it.
- Responses are stored in a history for later review and comparison.

## Privacy Notes
AI analysis transmits spectral data to the configured endpoint. Use only approved data and endpoints for your organization.
