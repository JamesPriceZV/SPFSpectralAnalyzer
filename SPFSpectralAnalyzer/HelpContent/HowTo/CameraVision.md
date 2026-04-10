@Article(
    title: "Camera and Vision Analysis"
)

## Overview
On iPhone and iPad, use the built-in camera to capture photos of sunscreen samples on PMMA plates and analyze their color properties using the Vision framework. This feature supplements spectral measurements with visual inspection data including RGB values, color temperature, and dominant hue analysis.

## Availability
Camera and Vision analysis is available on iOS and iPadOS only. On macOS, spectral data is analyzed using SPC file imports and the processing pipeline.

## Capturing a Photo
1. Switch to the Camera tab in the main navigation.
2. Point the camera at a sunscreen sample on a PMMA plate.
3. The live preview shows the camera feed.
4. Tap the capture button to take a photo.
5. The captured image is immediately analyzed.

## Importing from Photo Library
1. In the Camera tab, tap the photo picker button.
2. Select a photo from your library.
3. The selected image is analyzed using the same Vision pipeline.

## Color Analysis Results
The Vision analyzer extracts:
- RGB values: Red, green, and blue channel intensities
- HSV values: Hue, saturation, and value (brightness)
- Dominant hue: The primary color component
- Saturation level: Color intensity
- Brightness: Overall luminance
- Color temperature: Warm/cool tone estimation

## Sunscreen-Specific Interpretation
The app provides context-specific interpretation of color analysis results for sunscreen formulations:
- Yellow/amber tones may indicate organic UV filters or oxidation
- White/opaque samples suggest mineral (ZnO/TiO2) formulations
- Transparency changes between pre- and post-irradiation photos can indicate photostability

## Important Notes
- Camera analysis supplements but does not replace spectrophotometric measurements.
- Color analysis provides qualitative visual data, not quantitative SPF values.
- For accurate SPF determination, use spectral data from a UV-Vis spectrophotometer.
- Consistent lighting conditions improve color analysis reproducibility.
