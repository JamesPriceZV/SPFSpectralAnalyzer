@Article(
    title: "App Workflow Design"
)

## Overview
The app is structured around a linear workflow mapped to three main tabs in ``ContentView``:

1. Data Management: load SPC files, manage stored datasets, and review parse metadata.
2. Analysis: process spectra with the pipeline, inspect metrics, change SPF calculation methods, and run AI analysis.
3. Reporting: export PDF, HTML, Excel, Word, CSV, and JCAMP reports.

Settings are accessed separately via the menu bar (Command + ,) and cover API keys, SPF estimation parameters, and diagnostics configuration.

## Why This Design
The workflow keeps data provenance clear. Each stage produces artifacts used by later stages:
- Data Management produces parsed spectra and metadata.
- Analysis produces processed spectra, metrics, SPF estimates, and AI output.
- Reporting packages spectra, metrics, charts, and recommendations into export formats.

## Inspector Panel
The Inspector panel in the Analysis tab shows computed metrics for the selected spectrum or batch. The calculation method dropdown next to the Inspector heading lets you switch between COLIPA 2011, ISO 23675:2024, and Mansur (EE x I) methods. Press the recalculate button to recompute all statistics with the new method.

## Processing Pipeline
The Processing Pipeline panel controls alignment, smoothing, baseline correction, normalization, and peak detection. The Apply Pipeline button is located next to the Processing Pipeline heading for quick access.

## SPF Estimation
SPF values are computed using the selected ``SPFCalculationMethod``. The app supports three methods:
- COLIPA 2011: Full erythemal action spectrum weighting (290-400 nm).
- ISO 23675:2024: CIE standard erythemal spectrum with mid-summer solar irradiance.
- Mansur (EE x I): Simplified screening method using pre-calculated constants (290-320 nm).

The Math Details sheet (accessible from the SPF Estimation section) shows all formulas, explanations of how the mathematics work, and inline academic citations.

## Key Types
- SPC parsing and metadata models for import parsing.
- ``ProcessingSettings`` and ``SpectralMetrics`` for analysis.
- ``SPFCalculationMethod`` for method selection.
- ``SPFEstimationResult`` for resolved SPF values with quality tiers.
- ``AIAnalysisResult`` for AI output.
- ``ExportFormat`` for export configuration.
