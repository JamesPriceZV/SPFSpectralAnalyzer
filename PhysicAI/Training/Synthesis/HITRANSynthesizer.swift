import Foundation

actor HITRANSynthesizer {

    private let wnGrid = stride(from: 400.0, through: 4390.0, by: 10.0).map { $0 }

    // MARK: - Quantum HITRAN Features (Phase 38, 48 features)

    /// Computes 48 quantum-physics-informed features from HITRAN line parameters.
    ///
    /// Features cover:
    /// - Dicke narrowing correction (3)
    /// - Speed-dependent Voigt asymmetry (3)
    /// - Line mixing Rosenkranz Y coefficient (3)
    /// - Partition function temperature dependence (2)
    /// - Pressure broadening regime flags (3)
    /// - Line density and overlap (3)
    /// - Collision narrowing crossover (3)
    /// - Reserved/padding to 48
    nonisolated static func quantumHITRANFeatures(
        lines: [HITRANParser.Line],
        temperature: Double,
        pressure: Double,
        moleculeID: Int
    ) -> [String: Double] {
        var f: [String: Double] = [:]

        // Boltzmann constant in cm^-1/K
        let kB_cm = 0.695035  // cm^-1 / K
        let c_cgs = 2.99792458e10  // cm/s

        // Molecular mass estimate (AMU) from molecule ID — simplified lookup
        let massAMU: Double = {
            switch moleculeID {
            case 1: return 18.015   // H2O
            case 2: return 44.010   // CO2
            case 3: return 47.998   // O3
            case 4: return 44.013   // N2O
            case 5: return 28.010   // CO
            case 6: return 16.043   // CH4
            case 7: return 31.999   // O2
            case 8: return 30.006   // NO
            case 9: return 64.065   // SO2
            case 10: return 46.006  // NO2
            case 11: return 17.031  // NH3
            case 12: return 63.012  // HNO3
            case 13: return 17.007  // OH
            case 14: return 20.006  // HF
            case 15: return 36.461  // HCl
            case 16: return 80.912  // HBr
            case 17: return 127.912 // HI
            case 18: return 35.453  // ClO
            case 22: return 28.054  // C2H4
            case 23: return 26.038  // C2H2
            case 26: return 30.026  // H2CO
            default: return 30.0    // generic small molecule
            }
        }()

        let massKg = massAMU * 1.66054e-27

        // --- 1. Dicke narrowing correction (3 features) ---
        // Dicke narrowing parameter delta = optical diffusion coefficient / (2 * pi * nu_0)
        // Estimate optical diffusion coefficient D from kinetic theory
        // D ~ kT / (m * nu_vc), where nu_vc is velocity-changing collision frequency
        let meanNu0 = lines.isEmpty ? 1000.0 :
            lines.reduce(0.0) { $0 + $1.wavenumber } / Double(lines.count)
        let meanGammaAir = lines.isEmpty ? 0.05 :
            lines.reduce(0.0) { $0 + $1.airHalfWidth } / Double(lines.count)

        // Velocity-changing collision frequency ~ gamma_air * pressure (rough proxy)
        let nu_vc = meanGammaAir * pressure * c_cgs
        // Optical diffusion coefficient
        let D_opt = nu_vc > 0 ? (kB_cm * temperature) / (massAMU * nu_vc) : 0.0
        // Dicke narrowing parameter: delta_D = D_opt * (2 * pi * meanNu0 / c)^2
        let dickeNarrowingDelta = D_opt * pow(2.0 * .pi * meanNu0 / c_cgs, 2)
        f["qh_dicke_delta"] = dickeNarrowingDelta

        // Dicke regime flag: narrowing significant when mean free path >> wavelength
        // i.e., Knudsen number Kn = lambda_mfp / lambda_optical > 1
        let lambda_optical = meanNu0 > 0 ? 1.0 / meanNu0 : 1e-3  // cm
        let lambda_mfp = nu_vc > 0 ? sqrt(8.0 * kB_cm * temperature / (.pi * massAMU)) / nu_vc : 0
        let dickeRegimeFlag = lambda_mfp > lambda_optical ? 1.0 : 0.0
        f["qh_dicke_regime"] = dickeRegimeFlag

        // Optical diffusion proxy (dimensionless, normalized)
        f["qh_dicke_diffusion_proxy"] = min(D_opt * 1e6, 10.0)

        // --- 2. Speed-dependent Voigt asymmetry (3 features) ---
        // Speed-dependent parameter aw = (gamma_2 - gamma_0) / gamma_0
        // where gamma_2 is quadratic speed dependence of width
        // Approximate: aw ~ 0.1 * (massAMU / 30) for most molecules
        let aw = 0.1 * (massAMU / 30.0)
        f["qh_sdv_aw"] = aw

        // Speed-dependent Voigt asymmetry: proportional to aw * (gamma_L / gamma_D)
        let gamma_D_mean = meanNu0 > 0 ?
            (meanNu0 / c_cgs) * sqrt(2.0 * kB_cm * temperature * log(2.0) / massAMU) : 1e-6
        let gamma_L_mean = meanGammaAir * pressure * pow(296.0 / temperature, 0.75)
        let sdvAsymmetry = gamma_D_mean > 0 ? aw * (gamma_L_mean / gamma_D_mean) : 0.0
        f["qh_sdv_asymmetry"] = sdvAsymmetry

        // SDV correction flag: significant when aw > 0.05 and intermediate regime
        let sdvCorrectionFlag = (aw > 0.05 && gamma_L_mean > 0.1 * gamma_D_mean &&
                                  gamma_L_mean < 10.0 * gamma_D_mean) ? 1.0 : 0.0
        f["qh_sdv_correction_flag"] = sdvCorrectionFlag

        // --- 3. Line mixing Rosenkranz Y coefficient (3 features) ---
        // Y_i = sum_j!=i (d_ij * gamma_ij) / (nu_i - nu_j)
        // Approximate Y from nearest-neighbor lines
        var totalY = 0.0
        let sortedLines = lines.sorted { $0.wavenumber < $1.wavenumber }
        for i in 0..<sortedLines.count {
            var yi = 0.0
            // Consider nearest neighbors within 5 cm-1
            for j in 0..<sortedLines.count where j != i {
                let dnu = sortedLines[i].wavenumber - sortedLines[j].wavenumber
                guard abs(dnu) < 5.0 && abs(dnu) > 0.001 else { continue }
                // d_ij ~ sqrt(S_i * S_j) * gamma_air_j (simplified coupling)
                let coupling = sqrt(abs(sortedLines[i].intensity * sortedLines[j].intensity))
                let gamma_j = sortedLines[j].airHalfWidth * pressure
                yi += coupling * gamma_j / dnu
            }
            totalY += abs(yi)
        }
        let meanY = lines.isEmpty ? 0.0 : totalY / Double(lines.count)
        f["qh_rosenkranz_Y"] = min(meanY * 1e20, 10.0)  // Normalized

        // Line mixing active flag: significant for tightly spaced Q-branches
        let lineMixingActive = meanY * 1e20 > 0.01 ? 1.0 : 0.0
        f["qh_line_mixing_active"] = lineMixingActive

        // Q-branch flag: detect if many lines cluster within ~1 cm-1
        let qBranchFlag: Double = {
            guard sortedLines.count >= 3 else { return 0.0 }
            var maxCluster = 0
            for i in 0..<sortedLines.count {
                var cluster = 1
                for j in (i + 1)..<sortedLines.count {
                    if sortedLines[j].wavenumber - sortedLines[i].wavenumber < 1.0 {
                        cluster += 1
                    } else {
                        break
                    }
                }
                maxCluster = max(maxCluster, cluster)
            }
            return maxCluster >= 5 ? 1.0 : 0.0
        }()
        f["qh_q_branch_flag"] = qBranchFlag

        // --- 4. Partition function temperature dependence (2 features) ---
        // Q(T) / Q(T0) approximation using polynomial for common molecules
        // For linear molecules: Q(T) ~ T / (sigma * B * hc/k)
        // For nonlinear: Q(T) ~ (T/T0)^1.5
        let T0 = 296.0
        let isLinear = [2, 5, 7, 23].contains(moleculeID)  // CO2, CO, O2, C2H2
        let qRatio: Double
        if isLinear {
            qRatio = temperature / T0
        } else {
            qRatio = pow(temperature / T0, 1.5)
        }
        f["qh_partition_Q_ratio"] = qRatio

        // Temperature dependence of total band intensity: S_total(T) / S_total(T0)
        let meanLowerE = lines.isEmpty ? 0.0 :
            lines.reduce(0.0) { $0 + $1.lowerEnergy } / Double(lines.count)
        let boltzmannFactor = exp(-meanLowerE * 1.4388 * (1.0 / temperature - 1.0 / T0))
        let stimEmission = meanNu0 > 0 ?
            (1.0 - exp(-1.4388 * meanNu0 / temperature)) /
            (1.0 - exp(-1.4388 * meanNu0 / T0)) : 1.0
        let tempDepS = boltzmannFactor * stimEmission / qRatio
        f["qh_temperature_dep_S"] = tempDepS

        // --- 5. Pressure broadening regime flags (3 features) ---
        // Doppler regime: gamma_L << gamma_D
        // Voigt regime: gamma_L ~ gamma_D
        // Lorentz (collisional) regime: gamma_L >> gamma_D
        let ratio_L_D = gamma_D_mean > 0 ? gamma_L_mean / gamma_D_mean : 0.0
        f["qh_doppler_regime"] = ratio_L_D < 0.1 ? 1.0 : 0.0
        f["qh_voigt_regime"] = (ratio_L_D >= 0.1 && ratio_L_D <= 10.0) ? 1.0 : 0.0
        f["qh_lorentz_regime"] = ratio_L_D > 10.0 ? 1.0 : 0.0

        // --- 6. Line density and overlap (3 features) ---
        let lineCount = Double(lines.count)
        f["qh_line_count"] = lineCount

        // Strong lines (intensity > 1% of strongest)
        let maxIntensity = lines.map(\.intensity).max() ?? 0
        let strongCount = maxIntensity > 0 ?
            Double(lines.filter { $0.intensity > 0.01 * maxIntensity }.count) : 0.0
        f["qh_strong_line_count"] = strongCount

        // Line density per cm-1 in the active spectral range
        let wnRange: Double
        if let lo = sortedLines.first?.wavenumber, let hi = sortedLines.last?.wavenumber, hi > lo {
            wnRange = hi - lo
        } else {
            wnRange = 1.0
        }
        f["qh_line_density_per_cm"] = lineCount / wnRange

        // --- 7. Collision narrowing crossover (3 features) ---
        // Crossover pressure P* where Dicke narrowing transitions to pressure broadening
        // P* ~ gamma_D / gamma_air (rough estimate in atm)
        let pStar = meanGammaAir > 0 ? gamma_D_mean / meanGammaAir : 1.0
        f["qh_crossover_pressure_atm"] = pStar

        // Below crossover flag
        f["qh_below_crossover"] = pressure < pStar ? 1.0 : 0.0

        // Voigt parameter eta = gamma_L / (gamma_L + gamma_D)
        let voigtEta = (gamma_L_mean + gamma_D_mean) > 0 ?
            gamma_L_mean / (gamma_L_mean + gamma_D_mean) : 0.5
        f["qh_voigt_eta"] = voigtEta

        // --- 8. Pad remaining slots to 48 total ---
        // Additional physically motivated features

        // Mean Einstein A coefficient (spontaneous emission rate)
        let meanEinsteinA = lines.isEmpty ? 0.0 :
            lines.reduce(0.0) { $0 + $1.einsteinA } / Double(lines.count)
        f["qh_mean_einstein_A"] = meanEinsteinA

        // Self-broadening to air-broadening ratio (diagnostic of intermolecular forces)
        let meanGammaSelf = lines.isEmpty ? 0.0 :
            lines.reduce(0.0) { $0 + $1.selfHalfWidth } / Double(lines.count)
        let selfAirRatio = meanGammaAir > 0 ? meanGammaSelf / meanGammaAir : 1.0
        f["qh_self_air_ratio"] = selfAirRatio

        // Mean pressure shift (air-induced line shift)
        let meanPressureShift = lines.isEmpty ? 0.0 :
            lines.reduce(0.0) { $0 + $1.airPressureShift } / Double(lines.count)
        f["qh_mean_pressure_shift"] = meanPressureShift

        // Isotopologue abundance weighting (primary isotope assumed)
        f["qh_isotopologue_id"] = lines.first.map { Double($0.isotopeID) } ?? 1.0

        // Temperature exponent statistics
        let meanTempExp = lines.isEmpty ? 0.75 :
            lines.reduce(0.0) { $0 + $1.tempExponent } / Double(lines.count)
        f["qh_mean_temp_exponent"] = meanTempExp

        let tempExpVariance: Double = {
            guard lines.count > 1 else { return 0.0 }
            let mean = lines.reduce(0.0) { $0 + $1.tempExponent } / Double(lines.count)
            return lines.reduce(0.0) { $0 + ($1.tempExponent - mean) * ($1.tempExponent - mean) }
                / Double(lines.count - 1)
        }()
        f["qh_temp_exponent_variance"] = tempExpVariance

        // Band center of mass (intensity-weighted mean wavenumber)
        let totalIntensity = lines.reduce(0.0) { $0 + $1.intensity }
        let bandCenter = totalIntensity > 0 ?
            lines.reduce(0.0) { $0 + $1.intensity * $1.wavenumber } / totalIntensity :
            meanNu0
        f["qh_band_center_cm1"] = bandCenter

        // Band width (intensity-weighted standard deviation)
        let bandWidth = totalIntensity > 0 ?
            sqrt(lines.reduce(0.0) { $0 + $1.intensity * ($1.wavenumber - bandCenter) * ($1.wavenumber - bandCenter) }
                 / totalIntensity) : 0.0
        f["qh_band_width_cm1"] = bandWidth

        // Spectral line intensity dynamic range (log10)
        let minIntensity = lines.map(\.intensity).filter { $0 > 0 }.min() ?? 1e-30
        let dynamicRange = maxIntensity > 0 && minIntensity > 0 ?
            log10(maxIntensity / minIntensity) : 0.0
        f["qh_intensity_dynamic_range"] = dynamicRange

        // Lower-state energy statistics
        let meanLowerEnergy = meanLowerE
        f["qh_mean_lower_energy_cm1"] = meanLowerEnergy

        let maxLowerEnergy = lines.map(\.lowerEnergy).max() ?? 0.0
        f["qh_max_lower_energy_cm1"] = maxLowerEnergy

        // Hot band fraction (lines with lower energy > 500 cm-1)
        let hotBandCount = Double(lines.filter { $0.lowerEnergy > 500.0 }.count)
        f["qh_hot_band_fraction"] = lineCount > 0 ? hotBandCount / lineCount : 0.0

        // Molecular mass (used in Doppler width calculation)
        f["qh_molecular_mass_amu"] = massAMU

        // Doppler width at band center (HWHM, cm-1)
        f["qh_doppler_hwhm_cm1"] = gamma_D_mean

        // Lorentz width at current conditions (HWHM, cm-1)
        f["qh_lorentz_hwhm_cm1"] = gamma_L_mean

        // Optical depth at strongest line center (estimate)
        let maxS = lines.map(\.intensity).max() ?? 0.0
        let opticalDepthMax = maxS * pressure * 2.687e19 * 1e-4  // crude column density proxy
        f["qh_max_optical_depth_est"] = min(opticalDepthMax, 100.0)

        // Continuum absorption indicator (many weak overlapping lines)
        let weakLineCount = maxIntensity > 0 ?
            Double(lines.filter { $0.intensity < 0.001 * maxIntensity }.count) : 0.0
        let continuumIndicator = lineCount > 0 ? weakLineCount / lineCount : 0.0
        f["qh_continuum_indicator"] = continuumIndicator

        // Total: 48 features
        // qh_dicke_delta, qh_dicke_regime, qh_dicke_diffusion_proxy = 3
        // qh_sdv_aw, qh_sdv_asymmetry, qh_sdv_correction_flag = 3
        // qh_rosenkranz_Y, qh_line_mixing_active, qh_q_branch_flag = 3
        // qh_partition_Q_ratio, qh_temperature_dep_S = 2
        // qh_doppler_regime, qh_voigt_regime, qh_lorentz_regime = 3
        // qh_line_count, qh_strong_line_count, qh_line_density_per_cm = 3
        // qh_crossover_pressure_atm, qh_below_crossover, qh_voigt_eta = 3
        // qh_mean_einstein_A, qh_self_air_ratio, qh_mean_pressure_shift = 3
        // qh_isotopologue_id, qh_mean_temp_exponent, qh_temp_exponent_variance = 3
        // qh_band_center_cm1, qh_band_width_cm1, qh_intensity_dynamic_range = 3
        // qh_mean_lower_energy_cm1, qh_max_lower_energy_cm1, qh_hot_band_fraction = 3
        // qh_molecular_mass_amu, qh_doppler_hwhm_cm1, qh_lorentz_hwhm_cm1 = 3
        // qh_max_optical_depth_est, qh_continuum_indicator = 2
        // Subtotal: 3+3+3+2+3+3+3+3+3+3+3+3+3+2 = 42 ... pad remaining 6
        f["qh_reserved_1"] = 0.0
        f["qh_reserved_2"] = 0.0
        f["qh_reserved_3"] = 0.0
        f["qh_reserved_4"] = 0.0
        f["qh_reserved_5"] = 0.0
        f["qh_reserved_6"] = 0.0

        return f
    }

    // MARK: - Synthesize single record

    func synthesize(lines: [HITRANParser.Line], moleculeID: Int,
                    temperature: Double = 296, pressure: Double = 1.0,
                    pathlength: Double = 1.0) -> TrainingRecord {
        var spectrum = [Float](repeating: 0, count: wnGrid.count)

        for line in lines {
            // Temperature-scaled intensity (simplified)
            let S_T = line.intensity * exp(-line.lowerEnergy * 1.4388 * (1.0 / temperature - 1.0 / 296.0))
            let gamma_L = line.airHalfWidth * pressure * pow(296.0 / temperature, line.tempExponent)

            // Place on grid with Lorentzian profile
            if let idx = wnGrid.firstIndex(where: { $0 >= line.wavenumber }) {
                let window = min(10, wnGrid.count - idx)
                let startIdx = max(0, idx - 10)
                let endIdx = min(wnGrid.count - 1, idx + window)
                for j in startIdx...endIdx {
                    let dnu = wnGrid[j] - line.wavenumber
                    let lorentz = gamma_L / (.pi * (dnu * dnu + gamma_L * gamma_L))
                    spectrum[j] += Float(S_T * lorentz * pathlength)
                }
            }
        }

        var derived: [String: Double] = [
            "molecule_id": Double(moleculeID),
            "temperature_K": temperature,
            "pressure_atm": pressure,
            "pathlength_m": pathlength,
        ]

        // Merge quantum HITRAN features
        let quantumFeatures = Self.quantumHITRANFeatures(
            lines: lines, temperature: temperature,
            pressure: pressure, moleculeID: moleculeID)
        for (k, v) in quantumFeatures { derived[k] = v }

        var features = spectrum
        for (_, v) in derived.sorted(by: { $0.key < $1.key }) { features.append(Float(v)) }
        while features.count < SpectralModality.hitranMolecular.featureCount { features.append(0) }
        features = Array(features.prefix(SpectralModality.hitranMolecular.featureCount))

        return TrainingRecord(
            modality: .hitranMolecular, sourceID: "hitran_mol\(moleculeID)",
            features: features, targets: derived,
            metadata: ["molecule_id": String(moleculeID), "T_K": String(temperature)],
            isComputedLabel: true, computationMethod: "Voigt_HITRAN")
    }

    // MARK: - Batch synthesis for coordinator compatibility

    func synthesizeBatch(count: Int) -> [TrainingRecord] {
        // Molecular configs: (moleculeID, wavenumber range, typical line count, intensity scale)
        let moleculeConfigs: [(id: Int, wnLo: Double, wnHi: Double, lineCount: ClosedRange<Int>, intensityScale: Double)] = [
            (1,  1200, 2000, 20...80, 1e-20),   // H2O rotational-vibrational
            (2,  2200, 2400, 30...100, 5e-18),   // CO2 asymmetric stretch
            (2,   580,  750, 10...40, 1e-17),    // CO2 bending mode
            (3,   950, 1100, 15...50, 1e-17),    // O3
            (4,  2150, 2270, 20...60, 1e-17),    // N2O
            (5,  2050, 2200, 10...30, 1e-18),    // CO fundamental
            (6,  2900, 3100, 15...50, 2e-19),    // CH4 C-H stretch
            (6,  1200, 1400, 10...30, 5e-20),    // CH4 bending
            (7,  1550, 1660, 10...30, 1e-23),    // O2 magnetic dipole
            (9,  1100, 1200, 15...40, 4e-18),    // SO2
            (11, 3200, 3500, 20...60, 1e-18),    // NH3
            (26, 2700, 2900, 10...30, 3e-20),    // H2CO
        ]

        return (0..<count).map { i in
            let config = moleculeConfigs[i % moleculeConfigs.count]
            let nLines = Int.random(in: config.lineCount)
            let temperature = Double.random(in: 200...400)
            let pressure = Double.random(in: 0.01...2.0)
            let pathlength = Double.random(in: 0.1...100.0)

            // Generate synthetic HITRAN lines
            let lines: [HITRANParser.Line] = (0..<nLines).map { _ in
                let wn = Double.random(in: config.wnLo...config.wnHi)
                let intensity = config.intensityScale * pow(10.0, Double.random(in: -3...0))
                let einsteinA = Double.random(in: 0.01...100.0)
                let airHW = Double.random(in: 0.02...0.12)
                let selfHW = Double.random(in: 0.05...0.25)
                let lowerE = Double.random(in: 0...2000)
                let tempExp = Double.random(in: 0.4...0.85)
                let shift = Double.random(in: -0.01...0.005)
                return HITRANParser.Line(
                    moleculeID: config.id,
                    isotopeID: 1,
                    wavenumber: wn,
                    intensity: intensity,
                    einsteinA: einsteinA,
                    airHalfWidth: airHW,
                    selfHalfWidth: selfHW,
                    lowerEnergy: lowerE,
                    tempExponent: tempExp,
                    airPressureShift: shift)
            }

            return synthesize(lines: lines, moleculeID: config.id,
                              temperature: temperature, pressure: pressure,
                              pathlength: pathlength)
        }
    }
}
