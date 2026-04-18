@Article(
    title: "Spectral Analyzer Documentation"
)

## Overview
Spectral Analyzer imports Shimadzu SPC spectral files, processes and validates spectra, computes SPF metrics using industry-standard methods and machine learning models, and exports results as PDF, HTML, Excel, Word, CSV, or JCAMP reports. The app runs natively on macOS, iOS, and iPadOS with iCloud sync across devices.

## What You Can Do
- Import SPC files and review parse metadata and header details
- Inspect and compare spectra with alignment, smoothing, baseline, and normalization pipelines
- Calculate spectral metrics including critical wavelength, UVA/UVB ratio, and mean UVB transmittance
- Compute SPF estimates using COLIPA 2011, ISO 23675:2024, or Mansur (EE x I) methods
- Train custom CoreML models from reference datasets and get ML-predicted SPF with confidence intervals
- Use physics-informed neural network (PINN) inference across 30 spectral modalities including quantum chemistry, Mössbauer, and neutron diffraction
- Build calibration regression models from labeled samples with known SPF values
- Run AI-powered summaries and comparisons using five providers: OpenAI, Claude, Grok, Gemini, or On-Device (Apple Intelligence)
- Compare AI results from multiple providers side by side with Ensemble Mode
- Track AI usage costs and set monthly budget caps per provider
- Parse formula cards to extract structured ingredient lists with AI
- Connect to Microsoft 365 for enterprise-grounded AI analysis with document citations
- Upload reports to SharePoint and share results to Microsoft Teams
- Search your organization's M365 content from the Enterprise tab
- Track instruments from 80+ spectrophotometer models across 8 manufacturers
- Schedule calibration reminders and incubation timers via the system calendar
- Capture and analyze sunscreen samples with the camera on iOS
- Share data packages, chart snapshots, and reports via Messages, AirDrop, Teams, and more
- Export PDF reports with charts, metrics, ML predictions, and AI recommendations
- Export HTML, Excel, Word, CSV, and JCAMP formats
- View detailed mathematical derivations with inline academic citations

## Tutorials
- <doc:Workflow>

## How-To Guides
- <doc:WorkflowDesign>
- <doc:ImportSPC>
- <doc:AnalyzeAndCombine>
- <doc:AIAnalysis>
- <doc:MLModelTraining>
- <doc:PINNTrainingData>
- <doc:FormulaCards>
- <doc:ExportData>
- <doc:SPFCalculationMethods>
- <doc:M365Enterprise>
- <doc:InstrumentRegistry>
- <doc:CameraVision>
- <doc:SharingPackages>
- <doc:CalendarScheduling>
- <doc:MultiplatformSupport>
- <doc:PrivacySupport>
- <doc:KeyboardShortcuts>
- <doc:SearchSyntax>

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
- ``AIProviderManager``
- ``SPFPredictionService``
- ``MLTrainingService``
- ``ShareService``
- ``AIPromptPreset``
- ``AISelectionScope``
- ``ExportFormat``
