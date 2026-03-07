@Article(
    title: "Shimadzu Data Analyser Documentation"
)

## Overview
Shimadzu Data Analyser imports Shimadzu SPC spectral files, validates spectra, and exports results in standard formats suitable for reporting and downstream analysis. The main UI is ``ContentView`` and most workflows occur inside the Import, Analyze, AI Analysis, and Export tabs.

## What You Can Do
- Import SPC files and review parse metadata
- Inspect and compare spectra with alignment, smoothing, and baseline options
- Calculate spectral metrics such as critical wavelength and UVA/UVB ratio
- Run AI summaries and comparisons over selected or all loaded spectra
- Export CSV, JCAMP, Excel, and Word report outputs

## Tutorials
- <doc:Overview>

## How-To Guides
- <doc:WorkflowDesign>
- <doc:ImportSPC>
- <doc:AnalyzeAndCombine>
- <doc:AIAnalysis>
- <doc:ExportData>
- <doc:PrivacySupport>

## Key Symbols
- ``ContentView``
- ``SettingsView``
- ``ShimadzuSpectrum``
- ``ShimadzuSPCParser``
- ``ShimadzuSPCMetadata``
- ``StoredDataset``
- ``ProcessingSettings``
- ``SpectralMetrics``
- ``AIPromptPreset``
- ``AISelectionScope``
- ``ExportFormat``
