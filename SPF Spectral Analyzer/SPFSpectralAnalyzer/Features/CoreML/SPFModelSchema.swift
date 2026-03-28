import Foundation

/// Documents the expected CoreML model schema for the SPF predictor.
/// This file serves as a reference for model training — no runtime code.
///
/// ## Model Specification
///
/// **Name:** SPFPredictor
/// **Type:** Neural Network Regressor (or Tabular Regressor)
///
/// ### Input
/// - **Feature name:** `absorbance_spectrum`
/// - **Type:** `MLMultiArray` with shape `[1, 221]`
/// - **Description:** Absorbance values at wavelengths 290–510 nm in 1 nm steps.
///   The input must be interpolated to exactly 221 points before prediction.
///   Values should be in absorbance units (not transmittance or reflectance).
///
/// ### Outputs
/// - **`spf_estimate`** (`Double`): Predicted SPF value
/// - **`confidence_low`** (`Double`): Lower bound of 95% prediction interval
/// - **`confidence_high`** (`Double`): Upper bound of 95% prediction interval
///
/// ### Training Data Requirements
/// - Paired in-vitro UV absorbance spectra (from Shimadzu or compatible instruments)
///   with known in-vivo SPF values from human clinical studies.
/// - Minimum recommended: 200+ samples across SPF 2–100 range.
/// - Spectra should be PMMA plate measurements in absorbance mode.
/// - Include diverse formulation types: chemical, mineral, combination filters.
///
/// ### Preprocessing Pipeline (applied before prediction)
/// 1. Trim spectrum to 290–510 nm range
/// 2. Interpolate to 1 nm spacing (linear interpolation)
/// 3. Baseline correction (if not already applied)
/// 4. No normalization (absolute absorbance values are meaningful)
///
/// ### Model Training Notes
/// - Use CreateML `MLRegressor` or a custom `MLNeuralNetworkClassifier` via coremltools.
/// - Cross-validate with leave-one-formulation-out strategy.
/// - Target metric: R² ≥ 0.90 on held-out test set.
/// - Consider ensemble of gradient boosted trees + 1D-CNN for best accuracy.

enum SPFModelSchema {

    /// Expected input wavelength range.
    static let wavelengthRange: ClosedRange<Double> = 290.0...510.0

    /// Expected number of input features (1 nm spacing).
    static let inputFeatureCount = 221

    /// Model file name (without extension) expected in the app bundle.
    static let modelResourceName = "SPFPredictor"

    /// Model file extension for compiled CoreML models.
    static let modelExtension = "mlmodelc"
}
