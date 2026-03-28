@Article(
    title: "Run AI Analysis"
)

## Overview
AI Analysis summarizes and compares spectra using your configured analysis endpoint or OpenAI.

## Enable AI Analysis
1. Open Settings in ``SettingsView``.
2. Turn on AI Analysis.
3. Enter and store your API key (stored securely using ``KeychainStore``).
4. Confirm connectivity with the Test OpenAI action.

## Run an Analysis
1. Open the AI Analysis tab in ``ContentView``.
2. Choose a prompt preset (``AIPromptPreset``) such as Summary or Compare Selected.
3. Select a scope (``AISelectionScope``) for selected spectra or all loaded spectra.
4. Run the analysis and review the response.

## How AI Integration Works
- The app packages spectral data and metadata from the current selection.
- Requests are sent to the configured endpoint with the selected model name.
- Responses are stored as ``AIAnalysisResult`` entries for later review.

## Privacy Notes
AI analysis transmits spectral data to the configured endpoint. Use only approved data and endpoints for your organization.
