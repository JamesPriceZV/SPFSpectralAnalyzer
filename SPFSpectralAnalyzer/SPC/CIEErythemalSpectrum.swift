import Foundation

/// CIE standard erythemal action spectrum (ISO/CIE 17166:2019) and reference
/// solar spectral irradiance for ISO 23675:2024 SPF calculation.
///
/// The erythemal action spectrum is the internationally standardized weighting
/// function for UV-induced erythema (sunburn). The piecewise definition is:
///   s_er(λ) = 1.0                       for 250 ≤ λ ≤ 298 nm
///   s_er(λ) = 10^(0.094 × (298 − λ))   for 298 < λ ≤ 328 nm
///   s_er(λ) = 10^(0.015 × (140 − λ))   for 328 < λ ≤ 400 nm
///
/// The solar spectral irradiance is the reference spectrum specified in
/// ISO 23675:2024: mid-summer sunlight at latitude 40°N, solar zenith
/// angle 20°, ozone layer thickness 0.305 cm, wavelength range 290–400 nm.
/// Values are sourced from the COLIPA (Cosmetics Europe) reference tables
/// which are consistent with ISO 24443:2021 Annex A.
enum CIEErythemalSpectrum {

    // MARK: - CIE Erythemal Action Spectrum

    /// Returns the CIE erythemal effectiveness at the given wavelength (nm).
    /// Implements the piecewise function from ISO/CIE 17166:2019.
    nonisolated static func erythema(at wavelength: Double) -> Double {
        if wavelength <= 298.0 {
            return 1.0
        } else if wavelength <= 328.0 {
            return pow(10.0, 0.094 * (298.0 - wavelength))
        } else {
            return pow(10.0, 0.015 * (140.0 - wavelength))
        }
    }

    // MARK: - Reference Solar Spectral Irradiance

    /// Returns the reference solar spectral irradiance at the given wavelength.
    /// Uses linear interpolation on the tabulated data from ISO 23675 / COLIPA
    /// reference tables (290–400 nm). Returns 0 outside range.
    nonisolated static func solarIrradiance(at wavelength: Double) -> Double {
        guard wavelength >= 290.0, wavelength <= 400.0 else { return 0.0 }

        // Find bracketing entries for interpolation
        let table = solarIrradianceTable
        guard let firstWL = table.first?.0, let lastWL = table.last?.0 else { return 0.0 }
        guard wavelength >= firstWL, wavelength <= lastWL else { return 0.0 }

        for i in 1..<table.count {
            let (wl0, val0) = table[i - 1]
            let (wl1, val1) = table[i]
            if wavelength >= wl0 && wavelength <= wl1 {
                let t = (wavelength - wl0) / (wl1 - wl0)
                return val0 + (val1 - val0) * t
            }
        }
        return 0.0
    }

    /// Reference solar spectral irradiance (W·m⁻²·nm⁻¹) at 1 nm intervals,
    /// 290–400 nm. Source: COLIPA in vitro UVA Method (March 2011) / ISO 24443
    /// reference solar simulator spectrum, consistent with ISO 23675:2024.
    /// These values represent mid-summer sunlight at 40°N latitude, 20° zenith
    /// angle, through a standard atmosphere with 0.305 cm ozone.
    nonisolated static let solarIrradianceTable: [(Double, Double)] = [
        // (wavelength nm, relative irradiance)
        // UVB region 290–320 nm
        (290, 8.741e-06),
        (291, 1.450e-05),
        (292, 2.659e-05),
        (293, 4.575e-05),
        (294, 1.006e-04),
        (295, 2.589e-04),
        (296, 7.035e-04),
        (297, 1.678e-03),
        (298, 3.727e-03),
        (299, 7.938e-03),
        (300, 1.478e-02),
        (301, 2.514e-02),
        (302, 4.176e-02),
        (303, 6.223e-02),
        (304, 8.690e-02),
        (305, 1.216e-01),
        (306, 1.615e-01),
        (307, 1.989e-01),
        (308, 2.483e-01),
        (309, 2.894e-01),
        (310, 3.358e-01),
        (311, 3.872e-01),
        (312, 4.311e-01),
        (313, 4.884e-01),
        (314, 5.122e-01),
        (315, 5.567e-01),
        (316, 5.957e-01),
        (317, 6.256e-01),
        (318, 6.565e-01),
        (319, 6.879e-01),
        // UVA region 320–400 nm
        (320, 7.236e-01),
        (321, 7.371e-01),
        (322, 7.677e-01),
        (323, 7.955e-01),
        (324, 7.987e-01),
        (325, 8.290e-01),
        (326, 8.435e-01),
        (327, 8.559e-01),
        (328, 8.791e-01),
        (329, 8.951e-01),
        (330, 9.010e-01),
        (331, 9.161e-01),
        (332, 9.434e-01),
        (333, 9.444e-01),
        (334, 9.432e-01),
        (335, 9.571e-01),
        (336, 9.663e-01),
        (337, 9.771e-01),
        (338, 9.770e-01),
        (339, 9.967e-01),
        (340, 9.939e-01),
        (341, 1.0069),
        (342, 1.0118),
        (343, 1.0114),
        (344, 1.0214),
        (345, 1.0251),
        (346, 1.0328),
        (347, 1.0344),
        (348, 1.0395),
        (349, 1.0269),
        (350, 1.0454),
        (351, 1.0419),
        (352, 1.0398),
        (353, 1.0392),
        (354, 1.0428),
        (355, 1.0457),
        (356, 1.0353),
        (357, 1.0393),
        (358, 1.0266),
        (359, 1.0353),
        (360, 1.0371),
        (361, 1.0254),
        (362, 1.0230),
        (363, 1.0162),
        (364, 0.9984),
        (365, 0.9960),
        (366, 0.9675),
        (367, 0.9648),
        (368, 0.9389),
        (369, 0.9191),
        (370, 0.8977),
        (371, 0.8725),
        (372, 0.8473),
        (373, 0.8123),
        (374, 0.7840),
        (375, 0.7416),
        (376, 0.7149),
        (377, 0.6687),
        (378, 0.6280),
        (379, 0.5863),
        (380, 0.5341),
        (381, 0.4925),
        (382, 0.4482),
        (383, 0.3932),
        (384, 0.3428),
        (385, 0.2985),
        (386, 0.2567),
        (387, 0.2148),
        (388, 0.1800),
        (389, 0.1486),
        (390, 0.1193),
        (391, 0.0940),
        (392, 0.0727),
        (393, 0.0553),
        (394, 0.0401),
        (395, 0.0288),
        (396, 0.0207),
        (397, 0.0140),
        (398, 0.0095),
        (399, 0.0062),
        (400, 0.0042)
    ]
}
