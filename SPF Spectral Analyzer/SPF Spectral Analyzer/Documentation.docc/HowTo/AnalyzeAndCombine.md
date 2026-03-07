@Article(
    title: "Analyze and Combine Spectra"
)

## Overview
Use the Analyze tab to process, compare, and combine multiple spectra before export or AI analysis.

## Steps
1. Open the Analyze tab in ``ContentView``.
2. Enable alignment to normalize wavelength grids across samples.
3. Choose a smoothing method to reduce noise.
4. Apply baseline correction and normalization if needed.
5. Toggle overlays, average spectrum, and labels to compare samples.
6. Review spectral metrics such as critical wavelength and UVA/UVB ratio from ``SpectralMetrics``.

## Combining Spectra
- Use overlays to visualize multiple spectra in a shared chart.
- Enable the average spectrum to create a representative curve for a group.
- Save processing settings using ``ProcessingSettings`` to repeat the workflow on new imports.

## Tips
- Use consistent processing settings when comparing samples across batches.
- If a spectrum looks inverted, check the ``SpectralYAxisMode`` selection.
