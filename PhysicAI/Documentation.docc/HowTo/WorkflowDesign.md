@Article(
    title: "App Workflow Design"
)

## Overview
The app is structured around a linear workflow that maps to the main tabs in ``ContentView``:

1. Import: load SPC files and review parse metadata.
2. Analyze: process, align, and compare spectra.
3. AI Analysis: generate summaries and comparisons.
4. Export: produce reports and share results.

## Why This Design
The workflow keeps data provenance clear. Each stage produces artifacts used by later stages:
- Import produces parsed spectra and metadata.
- Analyze produces processed spectra and metrics.
- AI Analysis uses selected spectra and metadata.
- Export packages spectra, metrics, and processing settings.

## Key Types
- ``ShimadzuSPCParser`` and ``ShimadzuSPCMetadata`` for import parsing.
- ``ProcessingSettings`` and ``SpectralMetrics`` for analysis.
- ``AIAnalysisResult`` for AI output.
- ``ExportFormat`` for export configuration.
