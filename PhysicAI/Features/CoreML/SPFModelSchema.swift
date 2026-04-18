import Foundation

/// Documents the expected CoreML model schema for the SPF predictor.
///
/// ## Model Specification
///
/// **Name:** SPFPredictor
/// **Type:** Boosted Tree Regressor (Create ML `MLBoostedTreeRegressor`)
///
/// ### Inputs (Hybrid Feature Set)
///
/// **Spectral features (111):**
/// - `abs_290` through `abs_400`: Absorbance values at 290–400 nm in 1 nm steps.
///   Interpolated to exactly 111 points. Values in absorbance units (not transmittance).
///
/// **Derived spectral metrics (7):**
/// - `critical_wavelength`: λc where 90% of absorbance integral is reached (nm)
/// - `uva_uvb_ratio`: Ratio of UVA (320–400nm) to UVB (290–320nm) area
/// - `uvb_area`: Integrated absorbance 290–320 nm
/// - `uva_area`: Integrated absorbance 320–400 nm
/// - `mean_uvb_transmittance`: Mean transmittance in UVB range
/// - `mean_uva_transmittance`: Mean transmittance in UVA range
/// - `peak_absorbance_wavelength`: λmax in 290–400 nm
///
/// **Auxiliary features (4):**
/// - `plate_type`: Substrate plate (0=PMMA, 1=quartz, 2=other)
/// - `application_quantity_mg`: Application mass in mg
/// - `formulation_type`: Filter category (0=mineral, 1=organic, 2=combination, 3=unknown)
/// - `is_post_irradiation`: Post-irradiation flag (0 or 1)
///
/// ### Output
/// - **`spf`** (`Double`): Predicted in-vivo SPF value
///
/// Confidence intervals are computed post-hoc via conformal prediction on
/// calibration-set residuals (not a separate model output).
///
/// ### Training Data Requirements (ISO 24443)
/// - Paired in-vitro UV absorbance spectra (PMMA plate, Shimadzu or compatible)
///   with known in-vivo SPF values.
/// - Spectra measured in absorbance mode, 290–400 nm range.
/// - Minimum recommended: 5+ reference datasets (more is better).
/// - Include diverse formulation types: mineral, organic, combination.
///
/// ### Preprocessing Pipeline (applied before prediction)
/// 1. Ensure absorbance mode (convert from transmittance if needed)
/// 2. Resample to 290–400 nm at 1 nm spacing (111 points) via linear interpolation
/// 3. Compute 7 derived spectral metrics
/// 4. Encode auxiliary metadata as numeric features
///
/// ### In-App Training
/// - Trained on-device using Create ML `MLBoostedTreeRegressor` (macOS only)
/// - Conformal prediction intervals from 80/20 calibration split
/// - Target metric: R² ≥ 0.85 on validation set
enum SPFModelSchema {

    /// Expected input wavelength range (ISO 24443 compliant).
    static let wavelengthRange: ClosedRange<Double> = 290.0...400.0

    /// Number of spectral absorbance features (1 nm spacing, 290–400 nm).
    static let spectralFeatureCount = 111

    /// Column names for the 111 spectral absorbance features.
    static let spectralFeatureColumns: [String] = (290...400).map { "abs_\($0)" }

    /// Column names for the 7 derived spectral metrics.
    static let derivedMetricColumns: [String] = [
        "critical_wavelength",
        "uva_uvb_ratio",
        "uvb_area",
        "uva_area",
        "mean_uvb_transmittance",
        "mean_uva_transmittance",
        "peak_absorbance_wavelength"
    ]

    /// Column names for the 4 auxiliary features.
    static let auxiliaryFeatureColumns: [String] = [
        "plate_type",
        "application_quantity_mg",
        "formulation_type",
        "is_post_irradiation"
    ]

    /// The target column name.
    static let targetColumn = "spf"

    /// All feature column names (spectral + derived + auxiliary).
    static var allFeatureColumns: [String] {
        spectralFeatureColumns + derivedMetricColumns + auxiliaryFeatureColumns
    }

    /// Total number of input features.
    static var totalFeatureCount: Int { allFeatureColumns.count }

    /// Model file name (without extension) expected in the app bundle or app support.
    static let modelResourceName = "SPFPredictor"

    /// Model file extension for compiled CoreML models.
    static let modelExtension = "mlmodelc"
}
