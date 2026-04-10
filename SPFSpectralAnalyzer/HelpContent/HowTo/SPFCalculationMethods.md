@Article(
    title: "SPF Calculation Methods"
)

## Overview
The app supports three analytical in-vitro SPF calculation methods plus a machine learning prediction model. Each uses a different approach to estimate the Sun Protection Factor from absorbance or transmittance data. You can switch between analytical methods using the dropdown next to the Inspector heading in the Analysis tab.

## COLIPA 2011
The COLIPA in-vitro UVA Method (March 2011) uses the COLIPA erythemal action spectrum and UV source irradiance from 290-400 nm at 1 nm intervals.

Formula: SPF = Sum of E(wavelength) times S(wavelength) divided by Sum of E(wavelength) times S(wavelength) times T(wavelength)

Where E(wavelength) is the CIE erythemal action spectrum weighting (how effectively each wavelength causes sunburn), S(wavelength) is the solar spectral irradiance, and T(wavelength) is the spectral transmittance of the sample.

Reference: COLIPA (2011). In Vitro Method for the Determination of the UVA Protection Factor. Cosmetics Europe, March 2011.

## ISO 23675:2024
The ISO 23675:2024 Double Plate Method uses the CIE standard erythemal action spectrum from ISO/CIE 17166:2019 combined with a reference mid-summer solar irradiance spectrum at 40 degrees N latitude, from 290-400 nm.

Formula: SPF = Integral from 290 to 400 of E(wavelength) times I(wavelength) d(wavelength) divided by Integral from 290 to 400 of E(wavelength) times I(wavelength) times T(wavelength) d(wavelength)

Reference: ISO 23675:2024. Cosmetics - Sun protection test methods - In-vitro determination of sun protection factor. ISO/CIE 17166:2019. Erythema reference action spectrum.

## Mansur (EE x I)
The Mansur method (1986) is a simplified spectrophotometric approach using pre-calculated normalized EE times I (erythemal effect times solar intensity) constants at 5 nm intervals from 290-320 nm only.

Formula: SPF = CF times Sum from 290 to 320 of EE(wavelength) times I(wavelength) times Abs(wavelength)

Where CF is a correction factor (typically 10). This is a rapid screening method suitable for formulation development but less accurate than full-spectrum methods for final product claims.

Reference: Mansur, J.S. et al. (1986). Determinacao do fator de protecao solar por espectrofotometria. An. Bras. Dermatol., 61, 121-124. Sayre, R.M. et al. (1979). Photochem. Photobiol., 29, 559-566.

## CoreML Prediction Model
When a trained machine learning model is available, the app provides an additional ML-based SPF prediction that complements the analytical methods above.

The CoreML model uses a 122-feature hybrid input schema:
- 111 spectral absorbance features at 1 nm intervals from 290-400 nm
- 7 derived spectral metrics (critical wavelength, UVA/UVB ratio, UVB area, UVA area, mean UVB transmittance, mean UVA transmittance, peak absorbance wavelength)
- 4 auxiliary features (plate type, application quantity, formulation type, post-irradiation flag)

The default model is a boosted tree regressor trained on-device using Create ML from your own reference datasets (labeled in-vitro spectra paired with known in-vivo SPF values). Predictions include conformal prediction intervals computed from an 80/20 calibration split, providing a statistically calibrated 90% confidence range.

A physics-informed neural network (PINN) inference pathway is also available in beta for specific data types. PINN models encode Beer-Lambert absorption physics directly into the network architecture, producing hyper-accurate predictions that respect known spectral relationships.

ML predictions appear in the Inspector panel alongside analytical SPF estimates, enabling cross-validation between methods. See <doc:MLModelTraining> for training instructions and model management.

## Additional Metrics

### Critical Wavelength
The wavelength at which cumulative absorbance from 290 nm reaches 90% of the total absorbance integrated from 290-400 nm. A critical wavelength >= 370 nm indicates broad-spectrum UVA protection.

Reference: Diffey, B.L. (1994). A method for broad-spectrum classification of sunscreens. Int. J. Cosmet. Sci., 16, 47-52.

### UVA/UVB Ratio
The ratio of integrated absorbance in the UVA band (320-400 nm) to the UVB band (290-320 nm). Values >= 0.33 satisfy the COLIPA UVA seal requirement.

### Mean UVB Transmittance
The arithmetic mean of transmittance values across the UVB band (290-320 nm). Lower values indicate stronger UVB absorption.

## Calibration Regression Model
When labeled samples with known SPF values are loaded, the app builds a multivariate ordinary-least-squares regression model. Spectral metrics (UVB area, UVA area, critical wavelength, UVA/UVB ratio, and mean UVB transmittance) serve as predictor features. The model reports R-squared (goodness-of-fit) and RMSE (typical prediction error).

Reference: Draper, N.R. and Smith, H. (1998). Applied Regression Analysis, 3rd ed., Wiley.

## How to View Math Details
Click the Math button in the SPF Estimation section of the Inspector panel to open the Math Details sheet. This sheet shows all formulas, plain-language descriptions, computed values, and inline academic citations for each method.
