@Article(
    title: "App Workflow Design"
)

## Overview
The app is structured around a workflow mapped to main tabs in ``ContentView``. On macOS, these appear as a tab bar. On iOS and iPadOS, the interface uses adaptive navigation optimized for touch.

## Main Tabs

1. Data Management: Load SPC files, manage stored datasets, assign instruments, review parse metadata, and configure dataset roles and labels.
2. Analysis: Process spectra with the pipeline, inspect metrics, change SPF calculation methods, view CoreML predictions, and run AI analysis.
3. Camera (iOS/iPadOS only): Capture photos of sunscreen samples and analyze color properties using the Vision framework. See <doc:CameraVision>.
4. Reporting: Export PDF, HTML, Excel, Word, CSV, and JCAMP reports. View chart overlays and configure export options.
5. Enterprise: Search Microsoft 365 content, browse SharePoint/OneDrive files, interact with Teams channels and chats, and view enterprise grounding citations. See <doc:M365Enterprise>.
6. Settings: Configure AI providers, SPF calculation parameters, enterprise integration, iCloud sync, instrumentation, and diagnostics.

## Why This Design
The workflow keeps data provenance clear. Each stage produces artifacts used by later stages:
- Data Management produces parsed spectra, metadata, and instrument assignments.
- Analysis produces processed spectra, metrics, SPF estimates, CoreML predictions, and AI output.
- Reporting packages spectra, metrics, charts, predictions, and recommendations into export formats.
- Enterprise connects organizational knowledge and collaboration tools throughout the workflow.

## Inspector Panel
The Inspector panel in the Analysis tab shows computed metrics for the selected spectrum or batch. The calculation method dropdown next to the Inspector heading lets you switch between COLIPA 2011, ISO 23675:2024, and Mansur (EE x I) methods. Press the recalculate button to recompute all statistics with the new method.

When a trained CoreML model is available, the Inspector also displays the ML-predicted SPF with a confidence interval alongside the traditional calculation.

## Processing Pipeline
The Processing Pipeline panel controls alignment, smoothing, baseline correction, normalization, and peak detection. The Apply Pipeline button is located next to the Processing Pipeline heading for quick access.

## SPF Estimation
SPF values are computed using the selected ``SPFCalculationMethod``. The app supports three analytical methods:
- COLIPA 2011: Full erythemal action spectrum weighting (290-400 nm).
- ISO 23675:2024: CIE standard erythemal spectrum with mid-summer solar irradiance.
- Mansur (EE x I): Simplified screening method using pre-calculated constants (290-320 nm).

Additionally, a CoreML prediction model can provide ML-based SPF estimates with conformal prediction intervals. See <doc:MLModelTraining>.

The Math Details sheet (accessible from the SPF Estimation section) shows all formulas, explanations of how the mathematics work, and inline academic citations.

## AI Analysis
AI analysis is available from the Analysis tab sidebar. The app supports five AI providers with configurable routing, ensemble comparison, and cost tracking. See <doc:AIAnalysis> for full details.

## Key Types
- SPC parsing and metadata models for import parsing.
- ``ProcessingSettings`` and ``SpectralMetrics`` for analysis.
- ``SPFCalculationMethod`` for method selection.
- ``SPFEstimationResult`` for resolved SPF values with quality tiers.
- ``AIAnalysisResult`` and ``AIProviderManager`` for AI output and provider routing.
- ``SPFPredictionService`` for CoreML predictions with conformal intervals.
- ``ExportFormat`` for export configuration.
- ``ShareService`` for sharing and data packages.
