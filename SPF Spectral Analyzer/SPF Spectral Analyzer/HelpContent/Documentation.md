@Article(
    title: "Spectral Analyzer Documentation"
)

## Overview
Spectral Analyzer imports SPC spectral files, validates spectra, and exports results in standard formats suitable for reporting and downstream analysis. The main UI is ``ContentView`` and most workflows occur inside the Import, Analyze, AI Analysis, and Export tabs.

## What You Can Do
- Import SPC files and review parse metadata
- Inspect and compare spectra with alignment, smoothing, and baseline options
- Calculate spectral metrics such as critical wavelength and UVA/UVB ratio
- Run AI summaries and comparisons over selected or all loaded spectra
- Export CSV, JCAMP, Excel, and Word report outputs

## Tutorials
- <doc:Workflow>

## How-To Guides
- <doc:WorkflowDesign>
- <doc:ImportSPC>
- <doc:AnalyzeAndCombine>
- <doc:AIAnalysis>
- <doc:ExportData>
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
- ``AIPromptPreset``
- ``AISelectionScope``
- ``ExportFormat``
