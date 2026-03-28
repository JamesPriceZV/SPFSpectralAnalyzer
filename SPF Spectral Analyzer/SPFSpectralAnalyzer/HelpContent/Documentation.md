@Article(
    title: "Spectral Analyzer Documentation"
)

## Overview
Spectral Analyzer imports Shimadzu SPC spectral files, processes and validates spectra, computes SPF metrics using industry-standard methods, and exports results as PDF, HTML, Excel, Word, CSV, or JCAMP reports. The main UI is organized into three tabs: Data Management, Analysis, and Reporting.

## What You Can Do
- Import SPC files and review parse metadata and header details
- Inspect and compare spectra with alignment, smoothing, baseline, and normalization pipelines
- Calculate spectral metrics including critical wavelength, UVA/UVB ratio, and mean UVB transmittance
- Compute SPF estimates using COLIPA 2011, ISO 23675:2024, or Mansur (EE x I) methods
- Build calibration regression models from labeled samples with known SPF values
- Run AI-powered summaries and comparisons over selected or all loaded spectra
- Export PDF reports with charts, metrics, and AI recommendations
- Export HTML, Excel, Word, CSV, and JCAMP formats
- View detailed mathematical derivations with inline academic citations

## Tutorials
- <doc:Workflow>

## How-To Guides
- <doc:WorkflowDesign>
- <doc:ImportSPC>
- <doc:AnalyzeAndCombine>
- <doc:AIAnalysis>
- <doc:ExportData>
- <doc:SPFCalculationMethods>
- <doc:PrivacySupport>
- <doc:KeyboardShortcuts>

## Key Symbols
- ``ContentView``
- ``SettingsView``
- ``Spectrum``
- ``SPCParser``
- ``SPCMetadata``
- ``StoredDataset``
- ``ProcessingSettings``
- ``SpectralMetrics``
- ``SPFCalculationMethod``
- ``SPFEstimationResult``
- ``AIPromptPreset``
- ``AISelectionScope``
- ``ExportFormat``
