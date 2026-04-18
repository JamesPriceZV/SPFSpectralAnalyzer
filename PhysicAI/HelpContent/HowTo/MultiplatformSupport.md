@Article(
    title: "Multiplatform Support"
)

## Overview
PhysicAI runs natively on macOS, iOS, and iPadOS from a single codebase. The interface adapts to each platform while providing access to the full analysis toolkit.

## macOS
The macOS version provides the full desktop experience:
- Split-view layout with resizable sidebar and detail panels
- Menu bar with keyboard shortcuts for all major actions
- Multi-window support (help window, AI response popup, math details sheet)
- CoreML model training using Create ML (macOS exclusive)
- Full file system access for SPC import and report export

## iOS and iPadOS
The mobile versions adapt the interface for touch interaction:
- Tab-based navigation optimized for smaller screens
- Camera tab for photo-based sample analysis (see <doc:CameraVision>)
- Touch-optimized controls for pipeline settings and chart interaction
- Native share sheet integration for Messages, AirDrop, and more
- Photo library access for importing sample images

## Feature Availability by Platform

### Available Everywhere
- SPC file import and parsing
- Spectral analysis pipeline (alignment, smoothing, baseline, normalization)
- SPF calculation (COLIPA 2011, ISO 23675:2024, Mansur)
- AI analysis with all providers (OpenAI, Claude, Grok, Gemini, On-Device)
- CoreML prediction (using trained or bundled models)
- Formula card parsing
- Microsoft 365 Enterprise integration
- iCloud sync across devices
- Report export (PDF, HTML, CSV, JCAMP, Excel, Word)
- Sharing and data packages
- Calendar scheduling
- Instrument registry

### macOS Only
- CoreML model training (Create ML framework)
- Multi-window support
- Menu bar keyboard shortcuts
- HSplitView layout

### iOS and iPadOS Only
- Camera and Vision analysis
- Photo library picker
- iMessage direct sharing

## iCloud Sync
Datasets and metadata sync automatically across all your devices via CloudKit. Changes made on one device appear on others within moments. Sync status is visible in Settings under the iCloud Sync section.

## Tips
- Train CoreML models on your Mac, then use them for prediction on iPhone or iPad.
- Use the Camera tab on iOS to capture sample photos in the lab, then analyze spectral data on your Mac.
- Data packages shared via AirDrop transfer instantly between nearby Apple devices.
