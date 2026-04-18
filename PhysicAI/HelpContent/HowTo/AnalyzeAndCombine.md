@Article(
    title: "Analyze and Combine Spectra"
)

## Overview
Use the Analysis tab to process, compare, and combine multiple spectra before export or AI analysis.

## Processing Pipeline
1. Open the Analysis tab in ``ContentView``.
2. The Processing Pipeline panel provides controls for alignment, smoothing, baseline correction, normalization, and peak detection.
3. Click Apply Pipeline next to the Processing Pipeline heading to apply changes.

## Pipeline Steps
- Alignment: Resamples all spectra onto a common wavelength axis for point-by-point comparison.
- Smoothing: Reduces high-frequency noise. Choose Moving Average (simpler) or Savitzky-Golay (preserves peak shapes).
- Baseline: Corrects for instrument drift or cuvette absorbance. Min Subtract shifts the minimum to zero; Poly Fit removes a curved baseline.
- Normalization: Scales spectra for comparison. Min-Max scales to 0-1; Area normalizes by integrated area; Peak divides by the maximum value.
- Peak Detection: Finds local maxima above a minimum height threshold. Useful for identifying absorption bands.

## Inspector Panel
The Inspector panel shows metrics for the selected spectrum or batch:
- Critical wavelength, UVA/UVB ratio, and mean UVB transmittance.
- SPF estimation with quality tier badges.
- Calibration model details (when labeled samples are available).
- CoreML SPF prediction with confidence interval (when a trained model is loaded).

The CoreML prediction appears alongside traditional SPF estimates and shows the predicted value with a 90% confidence range (e.g., "32.5 (28.1-36.9)"). A model status indicator shows whether the ML model is ready, not yet trained, or loading. See <doc:MLModelTraining> for training instructions.

Use the calculation method dropdown next to the Inspector heading to switch between COLIPA 2011, ISO 23675:2024, and Mansur methods. Click the recalculate button to refresh all statistics.

## Math Details
Click the Math button in the SPF Estimation section to open a detailed sheet showing:
- All formulas used in monospaced font.
- Plain-language descriptions of how each calculation works.
- Inline academic citations for each method (Beer-Lambert, Diffey 1994, COLIPA 2011, ISO 23675:2024, Mansur 1986, etc.).

## Combining Spectra
- Use overlays to visualize multiple spectra in a shared chart.
- Enable the average spectrum to create a representative curve for a group.
- Save processing settings using ``ProcessingSettings`` to repeat the workflow on new imports.

## Tips
- Use consistent processing settings when comparing samples across batches.
- If a spectrum looks inverted, check the ``SpectralYAxisMode`` selection.
- A critical wavelength >= 370 nm indicates broad-spectrum UVA protection per COLIPA/EU standards.
- UVA/UVB ratio >= 0.33 satisfies the COLIPA UVA seal requirement.
- Compare the CoreML prediction against traditional SPF estimates as a cross-validation check.
