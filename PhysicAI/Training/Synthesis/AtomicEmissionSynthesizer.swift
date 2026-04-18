import Foundation

actor AtomicEmissionSynthesizer {

    private let grid = (200...899).map { Double($0) }
    private let kB_eV: Double = 8.617e-5

    struct EmissionLine: Sendable {
        let wavelengthNM: Double
        let Aki: Double
        let EkEV: Double
        let gk: Int
    }

    // MARK: - Phase 39 Quantum Constants

    /// Fine-structure doublet data: (lambda1_nm, lambda2_nm, spin_orbit_J_ratio)
    /// for alkali and alkaline-earth elements with resolved D-line doublets.
    private static let fineStructureSplit: [String: (Double, Double, Double)] = [
        "Na": (589.0, 589.6, 2.0), "K": (766.5, 769.9, 2.0),
        "Li": (670.8, 670.8, 1.0), "Rb": (780.0, 794.8, 2.0),
        "Cs": (852.1, 894.3, 2.0), "Ca": (393.4, 396.8, 2.0),
        "Ba": (553.5, 455.4, 1.0), "Sr": (460.7, 407.8, 1.0)
    ]

    /// H-alpha wavelength for Stark broadening electron density estimation.
    private static let hAlphaWavelength: Double = 656.28

    // MARK: - Quantum Feature Extraction (shared with LIBSSynthesizer)

    /// Computes 54 quantum-mechanical emission features from a 700-bin
    /// spectrum on the standard 200-899 nm grid.
    ///
    /// Features breakdown:
    /// - Fine structure doublet detection: 8 elements x 4 features = 32
    /// - H-alpha Stark broadening -> ne: 5 features
    /// - Saha ionisation balance: 3 features
    /// - Zeeman splitting proxy: 3 features
    /// - Spectral quantum metrics: 11 features
    /// - Padding to 54 total
    nonisolated static func quantumEmissionFeatures(
        spectrum: [Float],
        grid: [Double],
        temperature: Double,
        elements: [String] = []
    ) -> [String: Double] {
        var qf: [String: Double] = [:]
        let a = spectrum.map { Double($0) }
        let gridCount = grid.count

        // ── 1. Fine-structure doublet detection (32 features: 8 elements x 4) ──
        let doubletElements = ["Na", "K", "Li", "Rb", "Cs", "Ca", "Ba", "Sr"]
        for elem in doubletElements {
            guard let (lam1, lam2, jRatio) = fineStructureSplit[elem] else { continue }
            let prefix = "fs_\(elem.lowercased())_"

            // Find indices closest to doublet wavelengths
            let idx1 = Self.closestIndex(in: grid, to: lam1)
            let idx2 = Self.closestIndex(in: grid, to: lam2)

            let peak1 = (idx1 >= 0 && idx1 < gridCount) ? a[idx1] : 0.0
            let peak2 = (idx2 >= 0 && idx2 < gridCount) ? a[idx2] : 0.0

            // Feature 1: doublet detected (both peaks above noise threshold)
            let noiseFloor = a.reduce(0, +) / max(Double(gridCount), 1.0) * 0.1
            let detected: Double = (peak1 > noiseFloor && peak2 > noiseFloor) ? 1.0 : 0.0
            qf["\(prefix)detected"] = detected

            // Feature 2: doublet intensity ratio (should match 2J+1 ratio)
            let ratio = peak2 > 1e-12 ? peak1 / peak2 : 0.0
            qf["\(prefix)ratio"] = ratio

            // Feature 3: splitting energy (cm^-1)
            let splitting_cm1 = abs(lam1 - lam2) > 0.01
                ? abs(1e7 / lam1 - 1e7 / lam2) : 0.0
            qf["\(prefix)split_cm1"] = splitting_cm1

            // Feature 4: deviation from expected J-ratio
            let expectedRatio = jRatio  // 2J+1 upper / 2J+1 lower
            qf["\(prefix)j_deviation"] = detected > 0.5 ? abs(ratio - expectedRatio) : 0.0
        }

        // ── 2. H-alpha Stark broadening -> electron density (5 features) ──
        let hAlphaIdx = Self.closestIndex(in: grid, to: hAlphaWavelength)
        var hAlphaPeak = 0.0
        var hAlphaFWHM_nm = 0.0
        var ne_stark = 0.0

        if hAlphaIdx >= 0 && hAlphaIdx < gridCount {
            hAlphaPeak = a[hAlphaIdx]
            let halfMax = hAlphaPeak / 2.0

            // Measure FWHM by walking left and right from peak
            var leftIdx = hAlphaIdx
            while leftIdx > 0 && a[leftIdx] > halfMax { leftIdx -= 1 }
            var rightIdx = hAlphaIdx
            while rightIdx < gridCount - 1 && a[rightIdx] > halfMax { rightIdx += 1 }
            hAlphaFWHM_nm = (rightIdx > leftIdx) ? (grid[rightIdx] - grid[leftIdx]) : 0.0

            // Griem's Stark broadening formula for H-alpha:
            // FWHM(nm) ~ 0.04 * (ne / 1e16)^(2/3)  at ~10000 K
            // Inverted: ne = 1e16 * (FWHM / 0.04)^(3/2)
            if hAlphaFWHM_nm > 0.01 {
                ne_stark = 1e16 * pow(hAlphaFWHM_nm / 0.04, 1.5)
            }
        }
        qf["stark_h_alpha_peak"] = hAlphaPeak
        qf["stark_h_alpha_fwhm_nm"] = hAlphaFWHM_nm
        qf["stark_ne_cm3"] = ne_stark
        qf["stark_log_ne"] = ne_stark > 0 ? log10(ne_stark) : 0.0
        qf["stark_h_alpha_detected"] = hAlphaPeak > 1e-6 ? 1.0 : 0.0

        // ── 3. Saha ionisation balance (3 features) ──
        // Saha equation: ne * n(i+1)/n(i) = (2/lambda_dB^3) * (U(i+1)/U(i)) * exp(-chi_i/kT)
        // Simplified estimation from spectrum: ionisation fraction from
        // ratio of ion lines (shorter wavelength) to neutral lines (longer wavelength)
        let kT_eV = temperature * 8.617e-5
        let shortWaveIntegral = zip(grid, a)
            .filter { $0.0 >= 200 && $0.0 < 400 }
            .map { $0.1 }.reduce(0, +)
        let longWaveIntegral = zip(grid, a)
            .filter { $0.0 >= 500 && $0.0 <= 899 }
            .map { $0.1 }.reduce(0, +)
        let totalEmission = a.reduce(0, +)

        let ionNeutralRatio = longWaveIntegral > 1e-12
            ? shortWaveIntegral / longWaveIntegral : 0.0
        qf["saha_ion_neutral_ratio"] = ionNeutralRatio
        qf["saha_kT_eV"] = kT_eV
        // Estimated ionisation fraction: sigmoid-like from ratio and temperature
        let ionFraction = 1.0 / (1.0 + exp(-(ionNeutralRatio * kT_eV - 0.5) * 4.0))
        qf["saha_ionisation_fraction"] = ionFraction

        // ── 4. Zeeman splitting proxy (3 features) ──
        // In magnetic fields, spectral lines broaden due to Zeeman effect.
        // Proxy: average peak width across strongest lines compared to
        // instrumental broadening (~0.3 nm). Excess => magnetic field present.
        var peakWidths: [Double] = []
        let threshold = (a.max() ?? 0) * 0.3
        var inPeak = false
        var peakStart = 0
        for i in 0..<gridCount {
            if !inPeak && a[i] > threshold {
                inPeak = true
                peakStart = i
            } else if inPeak && (a[i] <= threshold || i == gridCount - 1) {
                inPeak = false
                let width = grid[i] - grid[peakStart]
                if width > 0.1 { peakWidths.append(width) }
            }
        }
        let avgWidth = peakWidths.isEmpty ? 0.0 : peakWidths.reduce(0, +) / Double(peakWidths.count)
        let instrumentalWidth = 0.3  // nm
        let zeemanExcess = max(0, avgWidth - instrumentalWidth)

        qf["zeeman_avg_line_width_nm"] = avgWidth
        qf["zeeman_excess_broadening_nm"] = zeemanExcess
        // Zeeman splitting: delta_lambda ~ 4.67e-8 * lambda^2 * B (Tesla)
        // Invert: B ~ excess / (4.67e-8 * lambda_avg^2)
        let lambdaAvg = totalEmission > 0
            ? zip(grid, a).map { $0.0 * $0.1 }.reduce(0, +) / totalEmission
            : 550.0
        let bFieldProxy = zeemanExcess > 0.01
            ? zeemanExcess / (4.67e-8 * lambdaAvg * lambdaAvg)
            : 0.0
        qf["zeeman_b_field_proxy_T"] = bFieldProxy

        // ── 5. Additional spectral quantum metrics (11 features) ──
        // Boltzmann plot slope proxy (two-region ratio for temperature)
        let highE_integral = zip(grid, a)
            .filter { $0.0 >= 200 && $0.0 < 350 }
            .map { $0.1 }.reduce(0, +)
        let lowE_integral = zip(grid, a)
            .filter { $0.0 >= 600 && $0.0 <= 800 }
            .map { $0.1 }.reduce(0, +)
        qf["boltzmann_slope_proxy"] = lowE_integral > 1e-12
            ? log(max(highE_integral, 1e-20) / lowE_integral) : 0.0

        // Line-to-continuum ratio (quality of discrete emission)
        let maxVal = a.max() ?? 0
        let medianApprox = a.sorted()[gridCount / 2]
        qf["line_continuum_ratio"] = medianApprox > 1e-12
            ? maxVal / medianApprox : 0.0

        // Spectral entropy of emission distribution
        let normA = totalEmission > 0 ? a.map { $0 / totalEmission } : a
        let entropy = -normA.filter { $0 > 1e-15 }.map { $0 * log($0) }.reduce(0, +)
        qf["emission_spectral_entropy"] = entropy

        // Number of resolved emission lines (peaks above 10% of max)
        let lineThreshold = maxVal * 0.1
        var lineCount = 0
        var wasAbove = false
        for val in a {
            if val > lineThreshold && !wasAbove {
                lineCount += 1
                wasAbove = true
            } else if val <= lineThreshold {
                wasAbove = false
            }
        }
        qf["resolved_line_count"] = Double(lineCount)

        // UV fraction (200-400 nm) - indicates high-energy transitions
        qf["uv_emission_fraction"] = totalEmission > 0
            ? shortWaveIntegral / totalEmission : 0.0

        // Visible fraction (400-700 nm)
        let visIntegral = zip(grid, a)
            .filter { $0.0 >= 400 && $0.0 < 700 }
            .map { $0.1 }.reduce(0, +)
        qf["visible_emission_fraction"] = totalEmission > 0
            ? visIntegral / totalEmission : 0.0

        // NIR fraction (700-900 nm) - low-energy / recombination
        let nirIntegral = zip(grid, a)
            .filter { $0.0 >= 700 && $0.0 <= 899 }
            .map { $0.1 }.reduce(0, +)
        qf["nir_emission_fraction"] = totalEmission > 0
            ? nirIntegral / totalEmission : 0.0

        // Peak wavelength centroid
        qf["emission_centroid_nm"] = lambdaAvg

        // Emission bandwidth (std dev of weighted distribution)
        let variance = totalEmission > 0
            ? zip(grid, a).map { ($0.0 - lambdaAvg) * ($0.0 - lambdaAvg) * $0.1 }.reduce(0, +) / totalEmission
            : 0.0
        qf["emission_bandwidth_nm"] = sqrt(max(variance, 0))

        // Element complexity indicator (number of distinct elements detected)
        qf["element_complexity"] = Double(elements.count)

        return qf
    }

    // MARK: - Helper

    private nonisolated static func closestIndex(in grid: [Double], to value: Double) -> Int {
        guard !grid.isEmpty else { return -1 }
        var bestIdx = 0
        var bestDist = abs(grid[0] - value)
        for i in 1..<grid.count {
            let dist = abs(grid[i] - value)
            if dist < bestDist {
                bestDist = dist
                bestIdx = i
            }
        }
        return bestIdx
    }

    // MARK: - Synthesize (single)

    func synthesize(element: String, lines: [EmissionLine],
                    temperature: Double = 5000) -> TrainingRecord {
        var spectrum = [Float](repeating: 0, count: grid.count)
        let Te = temperature * kB_eV
        let U = lines.map { Double($0.gk) * exp(-$0.EkEV / Te) }.reduce(0, +)
        guard U > 0 else {
            return emptyRecord(element: element)
        }

        for line in lines {
            let intensity = line.Aki * Double(line.gk) * exp(-line.EkEV / Te) / U
            if let idx = grid.firstIndex(where: { $0 >= line.wavelengthNM }) {
                let sigma = 0.3
                let window = min(5, grid.count - idx)
                let startIdx = max(0, idx - 5)
                let endIdx = min(grid.count - 1, idx + window)
                for j in startIdx...endIdx {
                    let d = grid[j] - line.wavelengthNM
                    spectrum[j] += Float(intensity * exp(-(d * d) / (2 * sigma * sigma)))
                }
            }
        }

        for i in 0..<spectrum.count {
            spectrum[i] += Float.random(in: 0...0.001)
        }

        let peakIdx = spectrum.enumerated().max(by: { $0.1 < $1.1 })?.0 ?? 0
        var derived: [String: Double] = [
            "plasma_temperature_est_K": temperature,
            "strongest_line_nm": grid[peakIdx],
            "total_integrated_emission": Double(spectrum.reduce(0, +)),
        ]

        // Phase 39: Merge quantum emission features
        let quantumFeats = Self.quantumEmissionFeatures(
            spectrum: spectrum, grid: grid,
            temperature: temperature, elements: [element])
        for (k, v) in quantumFeats { derived[k] = v }

        var features = spectrum
        for (_, v) in derived.sorted(by: { $0.key < $1.key }) { features.append(Float(v)) }
        while features.count < SpectralModality.atomicEmission.featureCount { features.append(0) }
        features = Array(features.prefix(SpectralModality.atomicEmission.featureCount))

        return TrainingRecord(
            modality: .atomicEmission, sourceID: "synth_\(element)",
            features: features, targets: derived, metadata: ["element": element],
            isComputedLabel: true, computationMethod: "Boltzmann_OES_Quantum")
    }

    // MARK: - Batch Synthesis

    /// Generates a batch of random atomic emission training records with
    /// randomised elements, temperatures, and synthetic emission lines.
    func synthesizeBatch(count: Int) -> [TrainingRecord] {
        let elementPool: [(symbol: String, lines: [EmissionLine])] = [
            ("Na", [
                EmissionLine(wavelengthNM: 589.0, Aki: 6.16e7, EkEV: 2.104, gk: 4),
                EmissionLine(wavelengthNM: 589.6, Aki: 6.14e7, EkEV: 2.102, gk: 2),
                EmissionLine(wavelengthNM: 330.2, Aki: 2.84e6, EkEV: 3.754, gk: 2),
                EmissionLine(wavelengthNM: 568.8, Aki: 1.37e6, EkEV: 3.618, gk: 6),
            ]),
            ("Ca", [
                EmissionLine(wavelengthNM: 393.4, Aki: 1.47e8, EkEV: 3.151, gk: 4),
                EmissionLine(wavelengthNM: 396.8, Aki: 1.40e8, EkEV: 3.123, gk: 2),
                EmissionLine(wavelengthNM: 422.7, Aki: 2.18e8, EkEV: 2.933, gk: 3),
                EmissionLine(wavelengthNM: 445.5, Aki: 8.70e7, EkEV: 4.680, gk: 7),
                EmissionLine(wavelengthNM: 612.2, Aki: 3.80e5, EkEV: 4.441, gk: 3),
            ]),
            ("Fe", [
                EmissionLine(wavelengthNM: 371.9, Aki: 1.62e7, EkEV: 3.332, gk: 11),
                EmissionLine(wavelengthNM: 373.5, Aki: 9.02e6, EkEV: 3.369, gk: 9),
                EmissionLine(wavelengthNM: 374.6, Aki: 5.40e6, EkEV: 3.396, gk: 7),
                EmissionLine(wavelengthNM: 385.9, Aki: 9.69e6, EkEV: 3.211, gk: 9),
                EmissionLine(wavelengthNM: 404.6, Aki: 8.62e6, EkEV: 4.549, gk: 9),
                EmissionLine(wavelengthNM: 438.4, Aki: 5.00e7, EkEV: 3.686, gk: 7),
            ]),
            ("K", [
                EmissionLine(wavelengthNM: 766.5, Aki: 3.87e7, EkEV: 1.617, gk: 4),
                EmissionLine(wavelengthNM: 769.9, Aki: 3.82e7, EkEV: 1.610, gk: 2),
                EmissionLine(wavelengthNM: 404.4, Aki: 1.05e6, EkEV: 3.064, gk: 2),
            ]),
            ("Li", [
                EmissionLine(wavelengthNM: 670.8, Aki: 3.69e7, EkEV: 1.848, gk: 6),
                EmissionLine(wavelengthNM: 610.4, Aki: 3.37e5, EkEV: 3.834, gk: 10),
                EmissionLine(wavelengthNM: 323.3, Aki: 3.25e5, EkEV: 3.834, gk: 2),
            ]),
            ("H", [
                EmissionLine(wavelengthNM: 656.28, Aki: 4.41e7, EkEV: 12.088, gk: 18),
                EmissionLine(wavelengthNM: 486.13, Aki: 8.42e6, EkEV: 12.749, gk: 32),
                EmissionLine(wavelengthNM: 434.05, Aki: 2.53e6, EkEV: 13.055, gk: 50),
            ]),
            ("Mg", [
                EmissionLine(wavelengthNM: 285.2, Aki: 4.91e8, EkEV: 4.346, gk: 3),
                EmissionLine(wavelengthNM: 383.8, Aki: 1.61e8, EkEV: 5.946, gk: 3),
                EmissionLine(wavelengthNM: 518.4, Aki: 5.61e7, EkEV: 5.108, gk: 5),
            ]),
            ("Ba", [
                EmissionLine(wavelengthNM: 553.5, Aki: 1.19e8, EkEV: 2.239, gk: 3),
                EmissionLine(wavelengthNM: 455.4, Aki: 1.10e8, EkEV: 2.722, gk: 5),
                EmissionLine(wavelengthNM: 614.2, Aki: 4.12e7, EkEV: 3.024, gk: 3),
            ]),
        ]

        var records: [TrainingRecord] = []
        records.reserveCapacity(count)

        for _ in 0..<count {
            let pool = elementPool.randomElement()!
            let temperature = Double.random(in: 3000...20000)
            // Randomly select a subset of lines to simulate partial observations
            let lineSubset = pool.lines.count > 2
                ? Array(pool.lines.shuffled().prefix(Int.random(in: 2...pool.lines.count)))
                : pool.lines
            records.append(synthesize(element: pool.symbol, lines: lineSubset,
                                      temperature: temperature))
        }
        return records
    }

    // MARK: - Private Helpers

    private func emptyRecord(element: String) -> TrainingRecord {
        TrainingRecord(
            modality: .atomicEmission, sourceID: "synth_\(element)_empty",
            features: [Float](repeating: 0, count: SpectralModality.atomicEmission.featureCount),
            targets: [:], metadata: ["element": element])
    }
}
