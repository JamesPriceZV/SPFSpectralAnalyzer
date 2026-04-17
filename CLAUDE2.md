# Universal Physical Spectral Data Analyzer — PINN Training System
## Part 2 of 2 — Modalities 12–25, Universal Coordinator, UI, Manifest

> **CONTINUATION of CLAUDE.md** — Read and fully implement all phases in CLAUDE.md
> (Phases 0–11) before executing any phase here. All foundation types
> (SpectralModality, TrainingRecord, StoredTrainingRecord, JCAMPDXParser, etc.)
> are already defined there. Do not redefine them.

Swift 6 rules apply throughout: actors, async/await, no DispatchQueue, no @unchecked Sendable.

---

## PHASE 12 — Atmospheric UV/Vis Cross-Sections PINN

**Physics:** Beer-Lambert with wavelength-dependent cross-sections and temperature dependence.
σ_eff(λ,T) = σ₀(λ) + σ₁(λ)·(T−295) + σ₂(λ)·(T−295)²
Photolysis rate: J = ∫ σ(λ,T)·Φ(λ,T)·F(λ) dλ

**Data source:** MPI-Mainz UV/Vis Spectral Atlas — https://uv-vis-spectral-atlas-mainz.org
~800 atmospheric species, free JCAMP-DX download.
Direct download base: https://uv-vis-spectral-atlas-mainz.org/jcamp/

**Target columns:** `log_sigma_peak`, `lambda_peak_nm`, `temp_coeff_1`, `temp_coeff_2`, `j_value_clear_sky`
**Feature count:** 651 (600 σ values at 1 nm intervals 200–800 nm + 51 auxiliary)

Create `Training/Sources/MPIMainzSource.swift`:

```swift
import Foundation

actor MPIMainzSource: TrainingDataSourceProtocol {
    static let baseURL = "https://uv-vis-spectral-atlas-mainz.org/jcamp/"

    func fetchSpectra(species: [String]) async throws -> AsyncThrowingStream<ReferenceSpectrum, Error> {
        AsyncThrowingStream { continuation in
            Task {
                for name in species {
                    let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
                    let url = URL(string: Self.baseURL + encoded + ".jdx")!
                    do {
                        let (data, _) = try await URLSession.shared.data(from: url)
                        let raw = String(decoding: data, as: UTF8.self)
                        let spectrum = try JCAMPDXParser.parse(raw, modality: .atmosphericUVVis)
                        continuation.yield(spectrum)
                    } catch {
                        continuation.yield(with: .failure(error))
                        return
                    }
                }
                continuation.finish()
            }
        }
    }
}
```

Create `Training/Synthesis/AtmosphericUVVisSynthesizer.swift`:

```swift
import Foundation
import Accelerate

actor AtmosphericUVVisSynthesizer {

    // Grid: 200–800 nm in 1 nm steps = 601 points
    static let lambdaGrid: [Double] = stride(from: 200.0, through: 800.0, by: 1.0).map { $0 }

    func synthesize(from spectrum: ReferenceSpectrum,
                    temperatures: [Double] = [220, 250, 273, 295, 320, 350]) async throws -> [TrainingRecord] {
        guard spectrum.modality == .atmosphericUVVis else { return [] }

        // Interpolate cross-sections onto canonical 1-nm grid
        let sigma0 = interpolateToGrid(xs: spectrum.xValues, ys: spectrum.yValues,
                                       grid: Self.lambdaGrid)
        guard sigma0.count == Self.lambdaGrid.count else { return [] }

        var records: [TrainingRecord] = []

        for T in temperatures {
            // Simplified linear temperature coefficient (placeholder; real data provides σ(T) pairs)
            let dT = T - 295.0
            let sigmaT = sigma0.map { s in max(s + s * 0.001 * dT, 1e-30) }

            // Peak wavelength
            let peakIdx = sigmaT.indices.max(by: { sigmaT[$0] < sigmaT[$1] }) ?? 0
            let lambdaPeak = Self.lambdaGrid[peakIdx]

            // Approximate J-value (clear sky actinic flux ~10^13 photons/cm²/s/nm at 300nm)
            let jValue = zip(Self.lambdaGrid, sigmaT).map { (lam, sig) in
                actinicFlux(nm: lam) * sig * 1.0 // quantum yield = 1 simplified
            }.reduce(0, +)

            var features = sigmaT.map { Float($0) }
            features.append(Float(T))
            features.append(Float(lambdaPeak))
            features.append(Float(log10(max(sigmaT.max() ?? 1e-30, 1e-30))))
            features.append(Float(dT))
            // Pad/trim to 651
            while features.count < 651 { features.append(0) }
            features = Array(features.prefix(651))

            let targets: [String: Double] = [
                "log_sigma_peak": log10(max(sigmaT.max() ?? 1e-30, 1e-30)),
                "lambda_peak_nm": lambdaPeak,
                "temp_coeff_1": 0.001,
                "temp_coeff_2": 0.0,
                "j_value_clear_sky": jValue
            ]

            records.append(TrainingRecord(
                modality: .atmosphericUVVis,
                sourceID: spectrum.sourceID,
                features: features,
                targets: targets,
                metadata: ["temperature_K": String(T), "species": spectrum.sourceID]
            ))
        }
        return records
    }

    // Very rough actinic flux model (photons/cm²/s/nm)
    private func actinicFlux(nm: Double) -> Double {
        guard nm >= 280 else { return 0 }
        let peak = 1e13
        return peak * exp(-0.02 * (nm - 310) * (nm - 310) / (100 * 100))
    }

    private func interpolateToGrid(xs: [Double], ys: [Double], grid: [Double]) -> [Double] {
        guard xs.count >= 2, xs.count == ys.count else { return Array(repeating: 0, count: grid.count) }
        return grid.map { x -> Double in
            guard let hi = xs.firstIndex(where: { $0 >= x }), hi > 0 else {
                return x < xs[0] ? ys[0] : (ys.last ?? 0)
            }
            let lo = hi - 1
            let t = (x - xs[lo]) / (xs[hi] - xs[lo])
            return ys[lo] + t * (ys[hi] - ys[lo])
        }
    }
}
```

---

## PHASE 13 — USGS Reflectance PINN

**Physics:** Kubelka-Munk reflectance theory.
F(R) = (1 − R)² / (2R)   where R = diffuse reflectance (0–1)
Continuum removal: R_cr(λ) = R(λ) / R_hull(λ)
Band depth: BD = 1 − R_cr(λ_centre)

**Data source:** USGS Spectral Library splib07
DOI: 10.5066/F7RR1WDJ
Direct ASCII download: https://crustal.usgs.gov/speclab/data/splib07a_ASCII_data.zip
2800+ spectra (minerals, vegetation, man-made materials)

**Target columns:** `band_depth_primary`, `band_centre_nm`, `km_k_over_s`, `continuum_slope`
**Feature count:** 1086 (480-nm range at 0.4 nm spacing 350–2500 nm subsampled to 1086 points + 6 aux)

Create `Training/Parsers/USGSTXTParser.swift`:

```swift
import Foundation

enum USGSTXTParser {
    struct USGSSpectrum: Sendable {
        let name: String
        let wavelengths: [Double]  // µm
        let reflectances: [Double] // 0–1
    }

    // Parse USGS ASCII two-column format (wavelength µm, reflectance)
    nonisolated static func parse(_ text: String) throws -> USGSSpectrum {
        var name = "unknown"
        var wavelengths: [Double] = []
        var reflectances: [Double] = []

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Name:") {
                name = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                continue
            }
            guard !trimmed.isEmpty, !trimmed.hasPrefix(";"), !trimmed.hasPrefix("#") else { continue }
            let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            if parts.count >= 2,
               let w = Double(parts[0]),
               let r = Double(parts[1]),
               r > -0.1 {           // USGS uses -1.23 as nodata sentinel
                wavelengths.append(w * 1000.0)  // µm → nm
                reflectances.append(max(r, 0.001))
            }
        }
        guard wavelengths.count > 10 else { throw ParserError.insufficientData }
        return USGSSpectrum(name: name, wavelengths: wavelengths, reflectances: reflectances)
    }

    enum ParserError: Error { case insufficientData }
}
```

Create `Training/Synthesis/USGSSynthesizer.swift`:

```swift
import Foundation
import Accelerate

actor USGSSynthesizer {

    // Canonical grid: 350–2500 nm, ~2 nm spacing, 1080 points
    static let grid: [Double] = stride(from: 350.0, through: 2500.0, by: 2.0).map { $0 }

    func synthesize(from parsed: USGSTXTParser.USGSSpectrum) async throws -> TrainingRecord {
        let R = interpolate(xs: parsed.wavelengths, ys: parsed.reflectances, grid: Self.grid)

        // Kubelka-Munk
        let kmValues = R.map { r -> Double in
            let rc = max(r, 0.001)
            return (1 - rc) * (1 - rc) / (2 * rc)
        }

        // Convex hull continuum removal (simplified linear hull between local maxima)
        let Rcr = continuumRemoval(wavelengths: Self.grid, reflectances: R)

        // Primary absorption band: deepest trough in Rcr
        let minIdx = Rcr.indices.min(by: { Rcr[$0] < Rcr[$1] }) ?? 0
        let bandDepth = 1.0 - Rcr[minIdx]
        let bandCentre = Self.grid[minIdx]

        // Continuum slope (linear fit)
        let slope = linearSlope(xs: Self.grid, ys: R)

        var features = R.map { Float($0) }
        // Append KM mean, band depth, band centre, slope, plus pad
        features.append(Float(kmValues.reduce(0,+) / Double(kmValues.count)))
        features.append(Float(bandDepth))
        features.append(Float(bandCentre))
        features.append(Float(slope))
        while features.count < 1086 { features.append(0) }
        features = Array(features.prefix(1086))

        let targets: [String: Double] = [
            "band_depth_primary": bandDepth,
            "band_centre_nm": bandCentre,
            "km_k_over_s": kmValues.max() ?? 0,
            "continuum_slope": slope
        ]

        return TrainingRecord(
            modality: .usgsReflectance,
            sourceID: parsed.name,
            features: features,
            targets: targets,
            metadata: ["material": parsed.name]
        )
    }

    private func interpolate(xs: [Double], ys: [Double], grid: [Double]) -> [Double] {
        guard xs.count >= 2 else { return Array(repeating: 0, count: grid.count) }
        return grid.map { x in
            guard let hi = xs.firstIndex(where: { $0 >= x }), hi > 0 else {
                return x < xs[0] ? ys[0] : (ys.last ?? 0)
            }
            let lo = hi - 1
            let t = (x - xs[lo]) / (xs[hi] - xs[lo])
            return ys[lo] + t * (ys[hi] - ys[lo])
        }
    }

    private func continuumRemoval(wavelengths: [Double], reflectances: [Double]) -> [Double] {
        // Upper convex hull then divide
        let hull = upperConvexHull(xs: wavelengths, ys: reflectances)
        return zip(wavelengths, reflectances).map { (x, r) in
            let h = hullValue(at: x, hull: hull)
            return r / max(h, 0.001)
        }
    }

    private func upperConvexHull(xs: [Double], ys: [Double]) -> [(Double, Double)] {
        var hull: [(Double, Double)] = []
        for (x, y) in zip(xs, ys) {
            while hull.count >= 2 {
                let (x1, y1) = hull[hull.count - 2]
                let (x2, y2) = hull[hull.count - 1]
                let cross = (x2 - x1) * (y - y1) - (x - x1) * (y2 - y1)
                if cross >= 0 { hull.removeLast() } else { break }
            }
            hull.append((x, y))
        }
        return hull
    }

    private func hullValue(at x: Double, hull: [(Double, Double)]) -> Double {
        guard hull.count >= 2 else { return hull.first?.1 ?? 1 }
        for i in 1..<hull.count {
            if hull[i].0 >= x {
                let t = (x - hull[i-1].0) / (hull[i].0 - hull[i-1].0)
                return hull[i-1].1 + t * (hull[i].1 - hull[i-1].1)
            }
        }
        return hull.last?.1 ?? 1
    }

    private func linearSlope(xs: [Double], ys: [Double]) -> Double {
        let n = Double(xs.count)
        let sumX = xs.reduce(0, +)
        let sumY = ys.reduce(0, +)
        let sumXY = zip(xs, ys).map(*).reduce(0, +)
        let sumX2 = xs.map { $0 * $0 }.reduce(0, +)
        return (n * sumXY - sumX * sumY) / max(n * sumX2 - sumX * sumX, 1e-30)
    }
}
```

---

## PHASE 14 — Optical Constants PINN

**Physics:** Sellmeier dispersion equation:
n²(λ) = 1 + Σᵢ Bᵢλ²/(λ² − Cᵢ)
Extinction coefficient k(λ) related to absorption: α = 4πk/λ
Kramers-Kronig consistency: n(ω) and k(ω) are Hilbert transform pairs.

**Data source:** refractiveindex.info — hosted on GitHub
https://github.com/polyanskiy/refractiveindex.info-database
YAML files; 1000+ materials, completely free.

**Target columns:** `n_at_589nm`, `k_at_589nm`, `abbe_number`, `sellmeier_B1`, `sellmeier_C1`
**Feature count:** 403 (200 n-values + 200 k-values at 200–1100 nm + 3 aux)

Create `Training/Parsers/RefractiveIndexYAMLParser.swift`:

```swift
import Foundation

enum RefractiveIndexYAMLParser {
    struct OpticalData: Sendable {
        let material: String
        let wavelengths_um: [Double]
        let n: [Double]
        let k: [Double]
    }

    // Minimal YAML parser for refractiveindex.info tabulated format
    // Expects lines like: "  - [0.300, 1.523, 0.00001]"
    nonisolated static func parse(_ text: String, material: String) throws -> OpticalData {
        var wavelengths: [Double] = []
        var nValues: [Double] = []
        var kValues: [Double] = []

        var inNKSection = false
        for line in text.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.contains("type: tabulated nk") || t.contains("type: tabulated n") {
                inNKSection = true
                continue
            }
            guard inNKSection else { continue }
            // Parse "  - [0.300, 1.523, 0.00001]" or "    0.300 1.523 0.00001"
            let cleaned = t.replacingOccurrences(of: "[", with: "")
                           .replacingOccurrences(of: "]", with: "")
                           .replacingOccurrences(of: ",", with: " ")
                           .replacingOccurrences(of: "-", with: "")
                           .trimmingCharacters(in: .whitespaces)
            let parts = cleaned.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            if parts.count >= 2, let w = Double(parts[0]), let n = Double(parts[1]) {
                wavelengths.append(w)
                nValues.append(n)
                kValues.append(parts.count >= 3 ? (Double(parts[2]) ?? 0) : 0)
            }
        }
        guard wavelengths.count >= 5 else { throw ParseError.insufficient }
        return OpticalData(material: material, wavelengths_um: wavelengths, n: nValues, k: kValues)
    }

    enum ParseError: Error { case insufficient }
}
```

Create `Training/Synthesis/OpticalConstantsSynthesizer.swift`:

```swift
import Foundation
import Accelerate

actor OpticalConstantsSynthesizer {

    // Grid: 200–1100 nm (0.2–1.1 µm), 200 points at 4.5 nm spacing
    static let gridNM: [Double] = stride(from: 200.0, through: 1100.0, by: 4.5).map { $0 }

    func synthesize(from data: RefractiveIndexYAMLParser.OpticalData) async throws -> TrainingRecord {
        let gridUM = Self.gridNM.map { $0 / 1000.0 }

        let nGrid = interpolate(xs: data.wavelengths_um, ys: data.n, grid: gridUM)
        let kGrid = interpolate(xs: data.wavelengths_um, ys: data.k, grid: gridUM)

        // n at 589.3 nm (sodium D line) = index 86 on our grid
        let idx589 = Self.gridNM.firstIndex(where: { $0 >= 589.0 }) ?? 86
        let nD = nGrid[min(idx589, nGrid.count-1)]
        let kD = kGrid[min(idx589, kGrid.count-1)]

        // Abbe number Vd = (nD−1)/(nF−nC)  F=486nm, C=656nm
        let idxF = Self.gridNM.firstIndex(where: { $0 >= 486.0 }) ?? 0
        let idxC = Self.gridNM.firstIndex(where: { $0 >= 656.0 }) ?? 0
        let nF = nGrid[min(idxF, nGrid.count-1)]
        let nC = nGrid[min(idxC, nGrid.count-1)]
        let abbe = abs(nF - nC) > 1e-6 ? (nD - 1.0) / abs(nF - nC) : 0

        // Sellmeier fit: just return B1 and C1 from a single-term approximation
        // B1 ≈ n²(λ_peak)−1,  C1 ≈ λ_peak² − [n²(λ_peak)−1]·λ_peak²/[n²(λ_peak)−1+...] (simplified)
        let b1 = nD * nD - 1.0
        let c1 = 0.01  // placeholder; real Sellmeier needs least-squares fit

        var features = nGrid.map { Float($0) } + kGrid.map { Float($0) }
        features.append(Float(nD))
        features.append(Float(abbe))
        features.append(Float(kD))
        while features.count < 403 { features.append(0) }
        features = Array(features.prefix(403))

        let targets: [String: Double] = [
            "n_at_589nm": nD,
            "k_at_589nm": kD,
            "abbe_number": abbe,
            "sellmeier_B1": b1,
            "sellmeier_C1": c1
        ]

        return TrainingRecord(
            modality: .opticalConstants,
            sourceID: data.material,
            features: features,
            targets: targets,
            metadata: ["material": data.material]
        )
    }

    private func interpolate(xs: [Double], ys: [Double], grid: [Double]) -> [Double] {
        guard xs.count >= 2 else { return Array(repeating: 1.5, count: grid.count) }
        return grid.map { x in
            guard let hi = xs.firstIndex(where: { $0 >= x }), hi > 0 else {
                return x < xs[0] ? ys[0] : (ys.last ?? 0)
            }
            let lo = hi - 1
            let t = (x - xs[lo]) / (xs[hi] - xs[lo])
            return ys[lo] + t * (ys[hi] - ys[lo])
        }
    }
}
```

---

## PHASE 15 — EELS PINN

**Physics:** Electron energy-loss spectroscopy.
Core-loss onset energy E_edge (element/shell specific).
ELNES (Energy-Loss Near-Edge Structure): fine structure within ~50 eV of edge.
Zero-loss peak and plasmon peak at E_p = ℏ·√(ne²/ε₀m).

**Data source:** EELS Data Base — https://eelsdb.eu
290 spectra, Open Database Licence (ODbL).
JSON API: https://eelsdb.eu/api/spectrum/?format=json&limit=100

**Target columns:** `edge_onset_eV`, `plasmon_energy_eV`, `edge_element`, `coordination_number`
**Feature count:** 612 (600 eV bins 0–3000 eV at 5 eV spacing + 12 aux)

Create `Training/Parsers/EELSDBParser.swift`:

```swift
import Foundation

enum EELSDBParser {
    struct EELSSpectrum: Sendable {
        let id: Int
        let element: String
        let edge: String          // e.g. "K", "L23", "M45"
        let edgeOnsetEV: Double
        let energies: [Double]
        let intensities: [Double]
    }

    nonisolated static func parseJSON(_ data: Data) throws -> [EELSSpectrum] {
        struct APIResult: Decodable {
            struct Entry: Decodable {
                let id: Int
                let title: String
                let edge: String?
                let onset: Double?
                let data: [[Double]]?
            }
            let results: [Entry]
        }
        let decoded = try JSONDecoder().decode(APIResult.self, from: data)
        return decoded.results.compactMap { entry in
            guard let pts = entry.data, pts.count >= 5 else { return nil }
            let energies = pts.map { $0[0] }
            let intensities = pts.map { $0.count > 1 ? $0[1] : 0 }
            // Extract element from title (first word usually)
            let element = entry.title.components(separatedBy: " ").first ?? "?"
            return EELSSpectrum(
                id: entry.id,
                element: element,
                edge: entry.edge ?? "?",
                edgeOnsetEV: entry.onset ?? 0,
                energies: energies,
                intensities: intensities
            )
        }
    }
}
```

Create `Training/Synthesis/EELSSynthesizer.swift`:

```swift
import Foundation
import Accelerate

actor EELSSynthesizer {

    // Canonical grid: 0–3000 eV at 5 eV spacing = 601 points
    static let grid: [Double] = stride(from: 0.0, through: 3000.0, by: 5.0).map { $0 }

    func synthesize(from spectrum: EELSDBParser.EELSSpectrum) async throws -> TrainingRecord {
        let ints = interpolate(xs: spectrum.energies, ys: spectrum.intensities, grid: Self.grid)

        // Plasmon peak: maximum in 0–100 eV range
        let plasmonRange = Self.grid.indices.filter { Self.grid[$0] <= 100 }
        let plasmonIdx = plasmonRange.max(by: { ints[$0] < ints[$1] }) ?? 0
        let plasmonEnergy = Self.grid[plasmonIdx]

        // Edge onset from metadata or detect as first large jump above 100 eV
        let edgeOnset = spectrum.edgeOnsetEV > 0 ? spectrum.edgeOnsetEV : detectEdgeOnset(grid: Self.grid, ints: ints)

        // ELNES region: extract 50 eV window above edge
        var elnesFeatures: [Float] = []
        if let edgeIdx = Self.grid.firstIndex(where: { $0 >= edgeOnset }) {
            let window = min(10, Self.grid.count - edgeIdx)
            elnesFeatures = (0..<window).map { Float(ints[edgeIdx + $0]) }
        }

        // Element encoding (atomic number 1–94)
        let elementMap = buildElementMap()
        let Z = Double(elementMap[spectrum.element] ?? 0)

        var features = ints.map { Float($0) }
        features.append(Float(plasmonEnergy))
        features.append(Float(edgeOnset))
        features.append(Float(Z))
        features += elnesFeatures
        while features.count < 612 { features.append(0) }
        features = Array(features.prefix(612))

        let targets: [String: Double] = [
            "edge_onset_eV": edgeOnset,
            "plasmon_energy_eV": plasmonEnergy,
            "edge_element": Z,
            "coordination_number": 6  // placeholder; derive from ELNES shape
        ]

        return TrainingRecord(
            modality: .eels,
            sourceID: "eelsdb_\(spectrum.id)",
            features: features,
            targets: targets,
            metadata: ["element": spectrum.element, "edge": spectrum.edge]
        )
    }

    private func detectEdgeOnset(grid: [Double], ints: [Double]) -> Double {
        // Find first large jump > 100 eV
        let startIdx = grid.firstIndex(where: { $0 > 100 }) ?? 0
        for i in startIdx..<(ints.count - 1) {
            if ints[i+1] > ints[i] * 3.0 { return grid[i] }
        }
        return 200.0
    }

    private func interpolate(xs: [Double], ys: [Double], grid: [Double]) -> [Double] {
        guard xs.count >= 2 else { return Array(repeating: 0, count: grid.count) }
        return grid.map { x in
            guard let hi = xs.firstIndex(where: { $0 >= x }), hi > 0 else {
                return x < xs[0] ? ys[0] : (ys.last ?? 0)
            }
            let lo = hi - 1
            let t = (x - xs[lo]) / (xs[hi] - xs[lo])
            return ys[lo] + t * (ys[hi] - ys[lo])
        }
    }

    private func buildElementMap() -> [String: Int] {
        let symbols = ["H","He","Li","Be","B","C","N","O","F","Ne",
                       "Na","Mg","Al","Si","P","S","Cl","Ar","K","Ca",
                       "Sc","Ti","V","Cr","Mn","Fe","Co","Ni","Cu","Zn",
                       "Ga","Ge","As","Se","Br","Kr","Rb","Sr","Y","Zr",
                       "Nb","Mo","Tc","Ru","Rh","Pd","Ag","Cd","In","Sn",
                       "Sb","Te","I","Xe","Cs","Ba","La","Ce","Pr","Nd",
                       "Pm","Sm","Eu","Gd","Tb","Dy","Ho","Er","Tm","Yb",
                       "Lu","Hf","Ta","W","Re","Os","Ir","Pt","Au","Hg",
                       "Tl","Pb","Bi","Po","At","Rn","Fr","Ra","Ac","Th",
                       "Pa","U","Np","Pu"]
        return Dictionary(uniqueKeysWithValues: symbols.enumerated().map { ($1, $0 + 1) })
    }
}
```

---

## PHASE 16 — SAXS/SANS PINN

**Physics:**
Guinier approximation (low-q): I(q) = I₀ · exp(−q²Rg²/3)
Porod law (high-q): I(q) ∝ q⁻⁴ (for sharp interfaces)
Pair distance distribution p(r) = (2/π) ∫ I(q)·q·sin(qr) dq (indirect Fourier transform)

**Data source:** Small Angle Scattering Biological Data Bank (SASBDB)
https://www.sasbdb.org — free, 5000+ datasets
REST API: https://www.sasbdb.org/rest/entry/{accession}/

**Target columns:** `radius_of_gyration_nm`, `dmax_nm`, `porod_volume_nm3`, `mw_kda`
**Feature count:** 208 (200 I(q) bins log-spaced 0.001–0.5 Å⁻¹ + 8 aux)

Create `Training/Parsers/SASBDBParser.swift`:

```swift
import Foundation

enum SASBDBParser {
    struct SASProfile: Sendable {
        let accession: String
        let rg_nm: Double          // radius of gyration from SASBDB
        let dmax_nm: Double
        let mw_kda: Double
        let q: [Double]            // Å⁻¹
        let intensity: [Double]    // arbitrary units
        let error: [Double]
    }

    nonisolated static func parseAPIResponse(_ data: Data) throws -> SASProfile {
        struct Entry: Decodable {
            let code: String
            let rg: Double?
            let dmax: Double?
            let mw_kda: Double?
            let fits: [[Double]]?  // [[q, I, sigma], ...]
        }
        let entry = try JSONDecoder().decode(Entry.self, from: data)
        let pts = entry.fits ?? []
        let q = pts.map { $0.count > 0 ? $0[0] : 0 }
        let I = pts.map { $0.count > 1 ? $0[1] : 0 }
        let sig = pts.map { $0.count > 2 ? $0[2] : 0 }
        return SASProfile(
            accession: entry.code,
            rg_nm: entry.rg ?? 0,
            dmax_nm: entry.dmax ?? 0,
            mw_kda: entry.mw_kda ?? 0,
            q: q, intensity: I, error: sig
        )
    }

    // Parse plain 3-column dat file: q  I  sigma
    nonisolated static func parseDatFile(_ text: String, accession: String) -> SASProfile {
        var q: [Double] = [], I: [Double] = [], sig: [Double] = []
        for line in text.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty, !t.hasPrefix("#") else { continue }
            let parts = t.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            if parts.count >= 3,
               let qv = Double(parts[0]), let iv = Double(parts[1]), let sv = Double(parts[2]),
               iv > 0 {
                q.append(qv); I.append(iv); sig.append(sv)
            }
        }
        return SASProfile(accession: accession, rg_nm: 0, dmax_nm: 0, mw_kda: 0, q: q, intensity: I, error: sig)
    }
}
```

Create `Training/Synthesis/SAXSSynthesizer.swift`:

```swift
import Foundation
import Accelerate

actor SAXSSynthesizer {

    // Log-spaced grid: 200 points from 0.001 to 0.5 Å⁻¹
    static let qGrid: [Double] = {
        let logMin = log10(0.001), logMax = log10(0.5)
        return (0..<200).map { i in pow(10, logMin + Double(i) / 199.0 * (logMax - logMin)) }
    }()

    func synthesize(from profile: SASBDBParser.SASProfile) async throws -> TrainingRecord {
        guard profile.q.count >= 5 else { throw SAXSError.insufficient }

        // Log-interpolate I(q) onto canonical grid
        let logQ = profile.q.map { log10(max($0, 1e-10)) }
        let logI = profile.intensity.map { log10(max($0, 1e-30)) }
        let logQGrid = Self.qGrid.map { log10($0) }

        let logIGrid = interpolate(xs: logQ, ys: logI, grid: logQGrid)

        // Guinier fit: ln I = ln I₀ - q²Rg²/3  (low-q region q < 1.3/Rg)
        let guinierRegion = (0..<min(20, logIGrid.count))
        let qs = guinierRegion.map { Self.qGrid[$0] }
        let lIs = guinierRegion.map { pow(10, logIGrid[$0]) }.map { log($0) }
        let q2s = qs.map { $0 * $0 }
        let rg2 = max(linearSlope(xs: q2s, ys: lIs) * -3.0, 0)
        let rgFitted = sqrt(rg2)
        let rgNM = profile.rg_nm > 0 ? profile.rg_nm : rgFitted * 10  // Å→nm

        // Porod invariant Q* = ∫ I(q)q² dq
        let porodInvariant = zip(Self.qGrid, logIGrid.map { pow(10,$0) }).map { $0 * $0 * $1 }.reduce(0, +)
        // Porod volume Vp = 2π²I(0) / Q*
        let i0 = pow(10, logIGrid[0])
        let porodVol = porodInvariant > 0 ? 2 * .pi * .pi * i0 / porodInvariant : 0

        var features = logIGrid.map { Float($0) }
        features.append(Float(rgNM))
        features.append(Float(profile.dmax_nm))
        features.append(Float(porodVol))
        features.append(Float(profile.mw_kda))
        features.append(Float(porodInvariant))
        features.append(Float(i0))
        features.append(Float(rgFitted))
        features.append(Float(qs.first ?? 0))
        while features.count < 208 { features.append(0) }
        features = Array(features.prefix(208))

        let targets: [String: Double] = [
            "radius_of_gyration_nm": rgNM,
            "dmax_nm": profile.dmax_nm > 0 ? profile.dmax_nm : rgNM * 3.5,
            "porod_volume_nm3": porodVol,
            "mw_kda": profile.mw_kda
        ]

        return TrainingRecord(
            modality: .saxs,
            sourceID: profile.accession,
            features: features,
            targets: targets,
            metadata: ["accession": profile.accession]
        )
    }

    enum SAXSError: Error { case insufficient }

    private func interpolate(xs: [Double], ys: [Double], grid: [Double]) -> [Double] {
        guard xs.count >= 2 else { return Array(repeating: 0, count: grid.count) }
        return grid.map { x in
            guard let hi = xs.firstIndex(where: { $0 >= x }), hi > 0 else {
                return x <= xs[0] ? ys[0] : (ys.last ?? 0)
            }
            let lo = hi - 1
            let t = (x - xs[lo]) / (xs[hi] - xs[lo])
            return ys[lo] + t * (ys[hi] - ys[lo])
        }
    }

    private func linearSlope(xs: [Double], ys: [Double]) -> Double {
        let n = Double(xs.count)
        guard n > 1 else { return 0 }
        let mx = xs.reduce(0,+)/n, my = ys.reduce(0,+)/n
        let num = zip(xs,ys).map { ($0-mx)*($1-my) }.reduce(0,+)
        let den = xs.map { ($0-mx)*($0-mx) }.reduce(0,+)
        return den > 1e-30 ? num/den : 0
    }
}
```

---

## PHASE 17 — Circular Dichroism PINN

**Physics:**
Cotton effect: Δε(λ) = ε_L(λ) − ε_R(λ)  (molar circular dichroism)
Optical rotatory dispersion (Drude): [α]_D = Σ_k A_k / (λ² − λ_k²)
Secondary structure deconvolution: [θ] = Σ_i f_i · [θ]_i  (CDSSTR/Selcon basis sets)

**Data source:** Protein Circular Dichroism Data Bank (PCDDB)
https://pcddb.cryst.bbk.ac.uk — 1800+ spectra, free
Download as CSV via: https://pcddb.cryst.bbk.ac.uk/spectrum_download.php?accession=CD0000001000

**Target columns:** `helix_fraction`, `sheet_fraction`, `turn_fraction`, `ellipticity_at_222nm`
**Feature count:** 128 (121 Δε values at 1 nm spacing 178–298 nm + 7 aux)

Create `Training/Synthesis/CDSynthesizer.swift`:

```swift
import Foundation
import Accelerate

actor CDSynthesizer {

    // Canonical grid: 178–298 nm at 1 nm = 121 points
    static let grid: [Double] = stride(from: 178.0, through: 298.0, by: 1.0).map { $0 }

    // Basis spectra for alpha-helix, beta-sheet, turn, coil (molar ellipticity per residue)
    // Values approximate from literature (Greenfield 2006 Nat Protoc)
    static let basisHelix:  [Double] = Self.grid.map { lam -> Double in
        // α-helix: negative bands at 208, 222 nm; positive at 193 nm
        let g193 = gaussian(lam, centre: 193, sigma: 8, amp: 40000)
        let g208 = gaussian(lam, centre: 208, sigma: 6, amp: -33000)
        let g222 = gaussian(lam, centre: 222, sigma: 5, amp: -31000)
        return g193 + g208 + g222
    }

    static let basisSheet: [Double] = Self.grid.map { lam -> Double in
        let g198 = gaussian(lam, centre: 198, sigma: 9, amp: -16000)
        let g217 = gaussian(lam, centre: 217, sigma: 7, amp: 3500)
        return g198 + g217
    }

    static func gaussian(_ x: Double, centre: Double, sigma: Double, amp: Double) -> Double {
        amp * exp(-(x - centre) * (x - centre) / (2 * sigma * sigma))
    }

    func synthesize(helix: Double, sheet: Double, turn: Double, noiseLevel: Double = 0.01,
                    accession: String = "synthetic") async -> TrainingRecord {
        let coil = max(0, 1.0 - helix - sheet - turn)
        // Coil basis: featureless broad negative
        let basisCoil: [Double] = Self.grid.map { lam in
            Self.gaussian(lam, centre: 200, sigma: 15, amp: -5000)
        }
        // Turn basis: weak positive around 205 nm
        let basisTurn: [Double] = Self.grid.map { lam in
            Self.gaussian(lam, centre: 205, sigma: 8, amp: 2500)
        }

        var spectrum = zip(Self.grid.indices, Self.grid).map { (i, _) -> Double in
            helix * Self.basisHelix[i] +
            sheet * Self.basisSheet[i] +
            turn  * basisTurn[i] +
            coil  * basisCoil[i]
        }

        // Add Gaussian noise
        spectrum = spectrum.map { v in v + Double.random(in: -1...1) * noiseLevel * abs(v) }

        let theta222 = spectrum[Self.grid.firstIndex(where: { $0 >= 222 }) ?? 44]

        var features = spectrum.map { Float($0) }
        features.append(Float(helix))
        features.append(Float(sheet))
        features.append(Float(turn))
        features.append(Float(coil))
        features.append(Float(theta222))
        features.append(Float(spectrum.min() ?? 0))
        features.append(Float(spectrum.max() ?? 0))
        while features.count < 128 { features.append(0) }
        features = Array(features.prefix(128))

        let targets: [String: Double] = [
            "helix_fraction": helix,
            "sheet_fraction": sheet,
            "turn_fraction": turn,
            "ellipticity_at_222nm": theta222
        ]

        return TrainingRecord(
            modality: .circularDichroism,
            sourceID: accession,
            features: features,
            targets: targets,
            metadata: ["helix": String(helix), "sheet": String(sheet)]
        )
    }

    // Synthesize a grid of secondary structure compositions
    func synthesizeBatch(count: Int = 2000) async -> [TrainingRecord] {
        var records: [TrainingRecord] = []
        for _ in 0..<count {
            let h = Double.random(in: 0...0.9)
            let s = Double.random(in: 0...(1.0 - h))
            let t = Double.random(in: 0...(1.0 - h - s))
            let record = await synthesize(helix: h, sheet: s, turn: t,
                                          accession: "synth_\(records.count)")
            records.append(record)
        }
        return records
    }
}
```

---

## PHASE 18 — Microwave / Rotational Spectroscopy PINN

**Physics:**
Rigid rotor energy levels: E_J = hcB·J(J+1) − hcD·J²(J+1)²
where B = h/(8π²Ic) is the rotational constant, D is centrifugal distortion.
Transition frequency: ν_J→J+1 = 2B(J+1) − 4D(J+1)³
Partition function: Q(T) = Σ_J (2J+1)·exp(−E_J/kT)

**Data source:** Cologne Database for Molecular Spectroscopy (CDMS)
https://cdms.astro.uni-koeln.de — ~750 species, free
Catalog files: https://cdms.astro.uni-koeln.de/classic/entries/partition_function.html
Download: https://cdms.astro.uni-koeln.de/cgi-bin/cdmsinfo?file=e{tag}.cat

**Target columns:** `rotational_constant_B_MHz`, `centrifugal_D_kHz`, `dipole_moment_debye`, `partition_Q_300K`
**Feature count:** 212 (200 frequency-domain spectral bins 1–1000 GHz + 12 aux)

Create `Training/Parsers/CDMSParser.swift`:

```swift
import Foundation

enum CDMSParser {
    // CDMS .cat format: fixed-width columns
    // Col 1-13: frequency (MHz), 15-22: uncertainty, 23-29: intensity log10(CDMS)
    // 30-35: DoF, 36-43: lower state energy (cm⁻¹), 44-46: upper state degeneracy
    // 47-53: tag, 54-59: QNFMT, 60-67: Quanta...

    struct CatalogLine: Sendable {
        let freqMHz: Double
        let logIntensity: Double  // log10(nm²·MHz)
        let lowerEnergyPerCm: Double
        let upperDegeneracy: Int
    }

    nonisolated static func parseCatalog(_ text: String) -> [CatalogLine] {
        text.components(separatedBy: .newlines).compactMap { line in
            guard line.count >= 46 else { return nil }
            let freqStr = String(line[line.startIndex..<line.index(line.startIndex, offsetBy: 13)])
            let intStr  = String(line[line.index(line.startIndex, offsetBy: 22)..<line.index(line.startIndex, offsetBy: 29)])
            let enerStr = String(line[line.index(line.startIndex, offsetBy: 35)..<line.index(line.startIndex, offsetBy: 43)])
            let degStr  = String(line[line.index(line.startIndex, offsetBy: 43)..<line.index(line.startIndex, offsetBy: 46)])
            guard let freq = Double(freqStr.trimmingCharacters(in: .whitespaces)),
                  let logI = Double(intStr.trimmingCharacters(in: .whitespaces)),
                  let ener = Double(enerStr.trimmingCharacters(in: .whitespaces)),
                  let deg  = Int(degStr.trimmingCharacters(in: .whitespaces)) else { return nil }
            return CatalogLine(freqMHz: freq, logIntensity: logI, lowerEnergyPerCm: ener, upperDegeneracy: deg)
        }
    }
}
```

Create `Training/Synthesis/MicrowaveSynthesizer.swift`:

```swift
import Foundation
import Accelerate

actor MicrowaveSynthesizer {

    // Canonical grid: 1–1000 GHz, 200 bins (log-spaced)
    static let freqGridGHz: [Double] = {
        let logMin = log10(1.0), logMax = log10(1000.0)
        return (0..<200).map { i in pow(10, logMin + Double(i) / 199.0 * (logMax - logMin)) }
    }()

    func synthesize(from lines: [CDMSParser.CatalogLine],
                    speciesTag: String, T: Double = 300.0) async throws -> TrainingRecord {
        guard !lines.isEmpty else { throw MWError.empty }

        // Build stick spectrum then bin onto grid
        var spectrum = Array(repeating: 0.0, count: Self.freqGridGHz.count)
        for line in lines {
            let freqGHz = line.freqMHz / 1000.0
            guard let idx = Self.freqGridGHz.firstIndex(where: { $0 >= freqGHz }) else { continue }
            let intensity = pow(10, line.logIntensity) * temperatureCorrection(E: line.lowerEnergyPerCm, T: T)
            spectrum[idx] += intensity
        }

        // Derive rotational constant B: dominant spacing pattern ν = 2B(J+1)
        // Estimate B from most intense transition frequency
        let sortedByInt = lines.sorted { abs($0.logIntensity) > abs($1.logIntensity) }
        let dominantFreqMHz = sortedByInt.first?.freqMHz ?? 0
        // B ≈ ν_J→J+1 / (2(J+1)) — estimate J from relative energy
        let bEstMHz = dominantFreqMHz / 4.0  // rough estimate assuming J=1→2
        let bEstMHzFine = bEstMHz > 0 ? bEstMHz : 1000.0

        // Dipole moment proxy: not available from catalog; encode 0
        let dipoleMoment = 0.0

        // Partition function at 300 K
        let Qval = lines.map { line in
            Double(line.upperDegeneracy) * exp(-line.lowerEnergyPerCm * 1.4388 / T)
        }.reduce(0, +)

        let maxInt = spectrum.max() ?? 1e-30
        let normSpectrum = spectrum.map { $0 / max(maxInt, 1e-30) }

        var features = normSpectrum.map { Float($0) }
        features.append(Float(bEstMHzFine))
        features.append(Float(Qval))
        features.append(Float(dipoleMoment))
        features.append(Float(T))
        features.append(Float(lines.count))
        features.append(Float(dominantFreqMHz / 1000.0))
        features.append(Float(maxInt))
        features.append(Float(sortedByInt.first?.lowerEnergyPerCm ?? 0))
        // Centrifugal distortion D — approximate from second-order spacing deviation
        let dEst = estimateCentrifugalD(lines: sortedByInt.prefix(20).map { $0 }, B_MHz: bEstMHzFine)
        features.append(Float(dEst))
        features.append(Float(lines.filter { $0.freqMHz < 300000 }.count))   // sub-mm count
        features.append(Float(lines.filter { $0.freqMHz >= 300000 }.count))  // THz count
        while features.count < 212 { features.append(0) }
        features = Array(features.prefix(212))

        let targets: [String: Double] = [
            "rotational_constant_B_MHz": bEstMHzFine,
            "centrifugal_D_kHz": dEst * 1000,
            "dipole_moment_debye": dipoleMoment,
            "partition_Q_300K": Qval
        ]

        return TrainingRecord(
            modality: .microwaveRotational,
            sourceID: "cdms_\(speciesTag)",
            features: features,
            targets: targets,
            metadata: ["species": speciesTag, "temperature_K": String(T)]
        )
    }

    private func temperatureCorrection(E: Double, T: Double) -> Double {
        exp(-E * 1.4388 / T)  // Boltzmann factor: E in cm⁻¹, kT = T/1.4388 cm⁻¹
    }

    private func estimateCentrifugalD(lines: [CDMSParser.CatalogLine], B_MHz: Double) -> Double {
        // D from deviation: ν_obs − 2B(J+1) = −4D(J+1)³
        guard lines.count >= 3 else { return 0 }
        // Simplified: D ≈ B³ / ν_e² (harmonic oscillator approximation)
        return B_MHz * B_MHz * B_MHz / (1e12)  // very rough estimate in MHz
    }

    enum MWError: Error { case empty }
}
```

---

## PHASE 19 — Thermogravimetric Analysis (TGA) PINN

**Physics:**
Coats-Redfern integral method (most common TGA kinetic analysis):
ln(−dα/dT / (1−α)ⁿ) = ln(A/β) − Eₐ/RT
where α = conversion fraction, β = heating rate (K/min), n = reaction order.
Activation energy Eₐ from slope of ln(-dα/dT) vs 1/T.

**Data source:**
1. NIST JANAF Thermochemical Tables (SRD 13) — Cp, ΔHf, S for 2000 species
   https://webbook.nist.gov/cgi/cbook.cgi?ID={CAS}&Units=SI&Type=JANAFG&Table=on
2. Zenodo TGA datasets — search: https://zenodo.org/search?q=thermogravimetric
   (DOI: 10.5281/zenodo.3629 series; various polymer and pharmaceutical TGA CSV files)

**Target columns:** `activation_energy_kJ_mol`, `pre_exponential_A`, `reaction_order_n`, `onset_temp_K`, `peak_deriv_temp_K`
**Feature count:** 214 (200 α(T) or dα/dT bins 300–1300 K at 5 K spacing + 14 aux)

Create `Training/Synthesis/TGASynthesizer.swift`:

```swift
import Foundation
import Accelerate

actor TGASynthesizer {

    // Canonical temperature grid: 300–1300 K at 5 K spacing = 201 points
    static let tempGrid: [Double] = stride(from: 300.0, through: 1300.0, by: 5.0).map { $0 }

    // Synthesize TGA curve from kinetic parameters using Coats-Redfern model
    func synthesize(Ea_kJ: Double, logA: Double, n: Double = 1.0,
                    beta: Double = 10.0, T_onset: Double = 500.0) async -> TrainingRecord {
        let Ea = Ea_kJ * 1000.0  // J/mol
        let A = pow(10, logA)    // min⁻¹
        let R = 8.314

        // Numerical integration of d alpha/dT = A/beta * exp(-Ea/RT) * (1-alpha)^n
        var alpha = Array(repeating: 0.0, count: Self.tempGrid.count)
        var dAlpha = Array(repeating: 0.0, count: Self.tempGrid.count)
        var alphaVal = 0.0

        for (i, T) in Self.tempGrid.enumerated() {
            let rate = (A / beta) * exp(-Ea / (R * T)) * pow(max(1.0 - alphaVal, 1e-10), n)
            dAlpha[i] = rate
            alpha[i] = alphaVal
            if i + 1 < Self.tempGrid.count {
                alphaVal = min(alphaVal + rate * 5.0, 1.0)  // Δ = 5 K
            }
        }

        // Onset temperature: α = 0.05
        let onsetIdx = alpha.firstIndex(where: { $0 >= 0.05 }) ?? 0
        let onsetT = Self.tempGrid[onsetIdx]

        // Peak derivative temperature (maximum dα/dT)
        let peakIdx = dAlpha.indices.max(by: { dAlpha[$0] < dAlpha[$1] }) ?? 0
        let peakT = Self.tempGrid[peakIdx]

        var features = dAlpha.map { Float($0) }
        features.append(Float(Ea_kJ))
        features.append(Float(logA))
        features.append(Float(n))
        features.append(Float(beta))
        features.append(Float(onsetT))
        features.append(Float(peakT))
        features.append(Float(T_onset))
        features.append(Float(alpha.last ?? 1.0))  // final conversion
        features.append(Float(dAlpha.max() ?? 0))
        features.append(Float(R))
        features.append(Float(Ea / R))   // Ea/R
        features.append(Float(logA))
        features.append(Float(log10(max(A, 1e-30))))
        features.append(Float(n))
        while features.count < 214 { features.append(0) }
        features = Array(features.prefix(214))

        let targets: [String: Double] = [
            "activation_energy_kJ_mol": Ea_kJ,
            "pre_exponential_A": logA,
            "reaction_order_n": n,
            "onset_temp_K": onsetT,
            "peak_deriv_temp_K": peakT
        ]

        return TrainingRecord(
            modality: .thermogravimetric,
            sourceID: "tga_Ea\(Int(Ea_kJ))_n\(String(format:"%.1f",n))",
            features: features,
            targets: targets,
            metadata: ["Ea_kJ": String(Ea_kJ), "logA": String(logA), "n": String(n), "beta": String(beta)]
        )
    }

    // Grid synthesis over Ea 50–300 kJ/mol, logA 5–20, n 0.5–2
    func synthesizeBatch(count: Int = 3000) async -> [TrainingRecord] {
        var records: [TrainingRecord] = []
        for _ in 0..<count {
            let Ea  = Double.random(in: 50...300)
            let lA  = Double.random(in: 5...20)
            let n   = Double.random(in: 0.5...2.5)
            let beta = [5.0, 10.0, 20.0].randomElement()!
            let record = await synthesize(Ea_kJ: Ea, logA: lA, n: n, beta: beta)
            records.append(record)
        }
        return records
    }
}
```

---

## PHASE 20 — Terahertz (THz) Spectroscopy PINN

**Physics:**
Drude model free-carrier response:
σ₁(ω) = σ₀/(1 + ω²τ²)   (real conductivity)
σ₂(ω) = σ₀ωτ/(1 + ω²τ²)  (imaginary conductivity)
Lorentz oscillator for phonon modes:
ε(ω) = ε_∞ + Σ_k f_k·ω_k²/(ω_k² − ω² − iγ_kω)
Absorption: α(ω) = ω·Im[√ε(ω)]/c

**Data source:** Zenodo THz pharmaceutical spectral datasets
Search: https://zenodo.org/search?q=terahertz+spectra
Key datasets:
- DOI 10.5281/zenodo.4106081 (pharmaceutical solids, 500+ spectra)
- DOI 10.5281/zenodo.5561549 (explosive compounds THz)
Format: CSV with frequency (THz) and absorbance columns.

**Target columns:** `drude_sigma0`, `drude_tau_ps`, `lorentz_peak1_THz`, `lorentz_gamma1_THz`
**Feature count:** 208 (200 α(ν) bins 0.1–3.0 THz at 0.0145 THz spacing + 8 aux)

Create `Training/Synthesis/THz Synthesizer.swift`:

> NOTE: filename has a space as per file structure in CLAUDE.md. Xcode handles this correctly.

```swift
import Foundation
import Accelerate

actor THz_Synthesizer {  // Swift identifier avoids space

    // Canonical grid: 0.1–3.0 THz, 200 points
    static let freqGrid: [Double] = stride(from: 0.1, through: 3.0, by: 0.01450).map { $0 }

    // Synthesize from Drude + Lorentz parameters
    func synthesize(sigma0: Double, tau_ps: Double,
                    lorentzPeaks: [(nu0: Double, strength: Double, gamma: Double)],
                    sourceID: String = "synthetic") async -> TrainingRecord {

        let c_cm = 2.998e10   // cm/s
        let tau_s = tau_ps * 1e-12

        var absorption = Self.freqGrid.map { nu_THz -> Double in
            let omega = 2 * .pi * nu_THz * 1e12  // rad/s
            // Drude absorption
            let drudeAlpha = (sigma0 * omega * tau_s) / (1 + omega * omega * tau_s * tau_s)

            // Lorentz contribution
            var lorentzAlpha = 0.0
            for peak in lorentzPeaks {
                let omega0 = 2 * .pi * peak.nu0 * 1e12
                let gamma  = 2 * .pi * peak.gamma * 1e12
                let denom  = (omega0 * omega0 - omega * omega) * (omega0 * omega0 - omega * omega) + omega * omega * gamma * gamma
                lorentzAlpha += peak.strength * omega * gamma / max(denom, 1e10)
            }
            return max(drudeAlpha + lorentzAlpha * 1e25, 0) // scale to cm⁻¹ units
        }

        // Add noise
        absorption = absorption.map { $0 + Double.random(in: -0.01...0.01) * ($0 + 0.1) }

        let peak1THz = lorentzPeaks.first?.nu0 ?? 0
        let gamma1   = lorentzPeaks.first?.gamma ?? 0

        var features = absorption.map { Float($0) }
        features.append(Float(sigma0))
        features.append(Float(tau_ps))
        features.append(Float(peak1THz))
        features.append(Float(gamma1))
        features.append(Float(lorentzPeaks.count))
        features.append(Float(absorption.max() ?? 0))
        features.append(Float(absorption.prefix(20).reduce(0,+) / 20.0))  // low-freq mean
        features.append(Float(absorption.suffix(20).reduce(0,+) / 20.0))  // high-freq mean
        while features.count < 208 { features.append(0) }
        features = Array(features.prefix(208))

        let targets: [String: Double] = [
            "drude_sigma0": sigma0,
            "drude_tau_ps": tau_ps,
            "lorentz_peak1_THz": peak1THz,
            "lorentz_gamma1_THz": gamma1
        ]

        return TrainingRecord(
            modality: .terahertz,
            sourceID: sourceID,
            features: features,
            targets: targets,
            metadata: ["sigma0": String(sigma0), "tau_ps": String(tau_ps)]
        )
    }

    func synthesizeBatch(count: Int = 2000) async -> [TrainingRecord] {
        var records: [TrainingRecord] = []
        for i in 0..<count {
            let sigma0 = Double.random(in: 10...1000)
            let tau    = Double.random(in: 0.01...2.0)
            let peaks: [(Double, Double, Double)] = (0..<Int.random(in: 0...3)).map { _ in
                (Double.random(in: 0.3...2.8), Double.random(in: 0.1...10), Double.random(in: 0.05...0.5))
            }
            let record = await synthesize(sigma0: sigma0, tau_ps: tau,
                                          lorentzPeaks: peaks.map { (nu0: $0.0, strength: $0.1, gamma: $0.2) },
                                          sourceID: "thz_synth_\(i)")
            records.append(record)
        }
        return records
    }
}
```

---

## PHASE 21 — LIBS PINN

**Physics:**
Saha-Boltzmann equation for plasma:
Nᵢ₊₁/Nᵢ = (2Zᵢ₊₁(T)/Zᵢ(T)) · (2πmₑkT/h²)^(3/2) · exp(−Eᵢₒₙᵢ/kT)
Boltzmann line intensity: I_ki = (hc/4π) · (A_ki · g_k / U(T)) · N · exp(−E_k/kT)
Stark broadening: Δλ_Stark ≈ 2w(nₑ/10¹⁶) in nm, where nₑ is electron density.
Electron temperature from Boltzmann plot slope: T_e = −1/(k·slope)

**Data source:** NIST Atomic Spectra Database (same as atomic emission, Phase 8 in Part 1)
https://physics.nist.gov/PhysRefData/ASD/lines_form.html
CSV download with Aki, Ek, gk for all elements.

**Target columns:** `electron_temp_eV`, `electron_density_cm3`, `element_1`, `element_2`, `plasma_pH`
**Feature count:** 716 (700 spectral bins 200–900 nm at ~1 nm + 16 aux)

> NOTE: LIBSSynthesizer extends AtomicEmissionSynthesizer with plasma physics.
> AtomicEmissionSynthesizer is defined in Part 1 (Phase 8). Read it before implementing LIBS.

Create `Training/Synthesis/LIBSSynthesizer.swift`:

```swift
import Foundation
import Accelerate

actor LIBSSynthesizer {

    // Canonical grid: 200–900 nm at 1 nm spacing = 701 points
    static let grid: [Double] = stride(from: 200.0, through: 900.0, by: 1.0).map { $0 }
    static let kB_eV: Double = 8.617e-5   // eV/K

    // Synthesize LIBS spectrum from elemental composition at given plasma conditions
    func synthesize(elements: [(symbol: String, fraction: Double)],
                    Te_eV: Double, ne_cm3: Double,
                    lineDatabase: [String: [(lambda_nm: Double, Aki: Double, Ek_eV: Double, gk: Int)]]) async -> TrainingRecord {

        var spectrum = Array(repeating: 0.0, count: Self.grid.count)

        for (symbol, fraction) in elements {
            guard let lines = lineDatabase[symbol] else { continue }
            let T_K = Te_eV / Self.kB_eV

            // Partition function (simplified sum over known levels)
            let U = lines.map { Double($0.gk) * exp(-$0.Ek_eV / Te_eV) }.reduce(0, +)
            guard U > 0 else { continue }

            for line in lines {
                let intensity = fraction * line.Aki * Double(line.gk) * exp(-line.Ek_eV / Te_eV) / U

                // Stark broadening FWHM (approximate; use hydrogen-like scaling)
                let starkFWHM = 0.04 * (ne_cm3 / 1e16)  // nm

                // Voigt profile (approximate as Lorentzian for Stark-dominated)
                if let idx = Self.grid.firstIndex(where: { $0 >= line.lambda_nm }) {
                    let window = max(3, Int(starkFWHM * 5))
                    let startIdx = max(0, idx - window)
                    let endIdx   = min(Self.grid.count - 1, idx + window)
                    for j in startIdx...endIdx {
                        let d = Self.grid[j] - line.lambda_nm
                        let lorentz = (starkFWHM / 2) / (.pi * (d * d + (starkFWHM/2) * (starkFWHM/2)))
                        spectrum[j] += intensity * lorentz
                    }
                }
            }
        }

        // Bremsstrahlung continuum (thermal background)
        let bremss = Self.grid.map { lam -> Double in
            let hnu_eV = 1240.0 / lam  // eV
            return ne_cm3 * ne_cm3 * 1e-40 * exp(-hnu_eV / Te_eV)
        }
        spectrum = zip(spectrum, bremss).map { $0 + $1 }

        let elementCodes = elements.prefix(2).map { (Double(atomicNumber(symbol: $0.symbol)), $0.fraction) }
        let elem1 = elementCodes.first?.0 ?? 0
        let elem2 = elementCodes.count > 1 ? elementCodes[1].0 : 0

        var features = spectrum.map { Float($0) }
        features.append(Float(Te_eV))
        features.append(Float(log10(max(ne_cm3, 1))))
        features.append(Float(elem1))
        features.append(Float(elem2))
        features.append(Float(elements.first?.fraction ?? 0))
        features.append(Float(elements.count))
        features.append(Float(spectrum.max() ?? 0))
        features.append(Float(spectrum.prefix(100).reduce(0,+)))
        features.append(Float(spectrum.suffix(100).reduce(0,+)))
        features += Array(repeating: Float(0), count: 7)
        while features.count < 716 { features.append(0) }
        features = Array(features.prefix(716))

        let targets: [String: Double] = [
            "electron_temp_eV": Te_eV,
            "electron_density_cm3": ne_cm3,
            "element_1": elem1,
            "element_2": elem2,
            "plasma_pH": 7.0  // placeholder; real pH from emission ratio
        ]

        return TrainingRecord(
            modality: .libs,
            sourceID: "libs_\(elements.map { $0.symbol }.joined())",
            features: features,
            targets: targets,
            metadata: ["Te_eV": String(Te_eV), "ne_cm3": String(ne_cm3)]
        )
    }

    private func atomicNumber(symbol: String) -> Int {
        let table = ["H":1,"He":2,"Li":3,"Be":4,"B":5,"C":6,"N":7,"O":8,"F":9,"Ne":10,
                     "Na":11,"Mg":12,"Al":13,"Si":14,"P":15,"S":16,"Cl":17,"Ar":18,"K":19,"Ca":20,
                     "Fe":26,"Cu":29,"Zn":30,"Pb":82,"Ba":56,"Sr":38,"Cr":24,"Mn":25,"Ni":28,"Ti":22]
        return table[symbol] ?? 0
    }
}
```

---

## PHASE 22 — Universal TrainingDataCoordinator

This `@MainActor @Observable` class is the single entry point for all 25 modalities.
It owns one SwiftData ModelContainer, dispatches synthesis tasks to each modality's
actor, tracks progress, and surfaces errors to the UI.

Create `Training/Curation/TrainingDataCoordinator.swift`:

```swift
import Foundation
import SwiftData
import Observation

@MainActor
@Observable
final class TrainingDataCoordinator {

    // MARK: - Observable state
    var modalityStatus: [SpectralModality: ModalityStatus] = {
        var d: [SpectralModality: ModalityStatus] = [:]
        SpectralModality.allCases.forEach { d[$0] = .idle }
        return d
    }()

    var totalRecordCount: Int = 0
    var activeDownloads: Set<SpectralModality> = []
    var lastError: (SpectralModality, Error)? = nil

    // MARK: - Dependencies (injected)
    let modelContainer: ModelContainer
    private let session = URLSession(configuration: .ephemeral)

    enum ModalityStatus: Equatable {
        case idle
        case downloading(progress: Double)
        case synthesizing(progress: Double)
        case training
        case ready(recordCount: Int)
        case error(String)
    }

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    // MARK: - Start all
    func prepareAll() async {
        await withTaskGroup(of: Void.self) { group in
            for modality in SpectralModality.allCases {
                group.addTask { [weak self] in
                    await self?.prepare(modality: modality)
                }
            }
        }
    }

    // MARK: - Per-modality dispatch
    func prepare(modality: SpectralModality) async {
        guard modalityStatus[modality] == .idle else { return }
        activeDownloads.insert(modality)
        modalityStatus[modality] = .downloading(progress: 0)

        do {
            let records: [TrainingRecord]
            switch modality {
            case .atmosphericUVVis:
                records = try await prepareAtmosphericUVVis()
            case .usgsReflectance:
                records = try await prepareUSGS()
            case .opticalConstants:
                records = try await prepareOpticalConstants()
            case .eels:
                records = try await prepareEELS()
            case .saxs:
                records = try await prepareSAXS()
            case .circularDichroism:
                records = await prepareCD()
            case .microwaveRotational:
                records = try await prepareMicrowave()
            case .thermogravimetric:
                records = await prepareTGA()
            case .terahertz:
                records = await prepareTHz()
            case .libs:
                records = await prepareLIBS()
            default:
                // Modalities covered in Part 1 (Phases 2–11) have their own prepare functions
                records = []
            }

            modalityStatus[modality] = .synthesizing(progress: 0.5)
            try await persistRecords(records, modality: modality)
            totalRecordCount += records.count
            modalityStatus[modality] = .ready(recordCount: records.count)
        } catch {
            lastError = (modality, error)
            modalityStatus[modality] = .error(error.localizedDescription)
        }
        activeDownloads.remove(modality)
    }

    // MARK: - Atmospheric UV/Vis
    private func prepareAtmosphericUVVis() async throws -> [TrainingRecord] {
        let species = AtmosphericSpeciesList.all
        let source = MPIMainzSource()
        let synth  = AtmosphericUVVisSynthesizer()
        var records: [TrainingRecord] = []
        let stream = try await source.fetchSpectra(species: Array(species.prefix(50)))
        for try await spectrum in stream {
            let r = try await synth.synthesize(from: spectrum)
            records += r
        }
        return records
    }

    // MARK: - USGS
    private func prepareUSGS() async throws -> [TrainingRecord] {
        // Download USGS splib07 index (ASCII manifest)
        let indexURL = URL(string: "https://crustal.usgs.gov/speclab/data/splib07a_ASCII_data.zip")!
        let (data, _) = try await session.data(from: indexURL)
        // Unzip and parse (shell: unzip to temp dir, enumerate .txt files)
        // Simplified: process first 100 files
        let text = String(decoding: data, as: UTF8.self)
        let synth = USGSSynthesizer()
        var records: [TrainingRecord] = []
        // Parse concatenated spectra if available, else synthesize from known materials
        let parsed = try USGSTXTParser.parse(text)
        let record = try await synth.synthesize(from: parsed)
        records.append(record)
        return records
    }

    // MARK: - Optical Constants
    private func prepareOpticalConstants() async throws -> [TrainingRecord] {
        // Clone or download refractiveindex.info database
        // For initial training, use known Sellmeier coefficients for common glasses
        let materials: [(String, [Double], [Double])] = OpticalMaterialLibrary.commonMaterials
        let synth = OpticalConstantsSynthesizer()
        var records: [TrainingRecord] = []
        for (name, nVals, kVals) in materials {
            let data = RefractiveIndexYAMLParser.OpticalData(
                material: name,
                wavelengths_um: OpticalConstantsSynthesizer.gridNM.map { $0/1000 },
                n: nVals, k: kVals
            )
            let record = try await synth.synthesize(from: data)
            records.append(record)
        }
        return records
    }

    // MARK: - EELS
    private func prepareEELS() async throws -> [TrainingRecord] {
        let url = URL(string: "https://eelsdb.eu/api/spectrum/?format=json&limit=100")!
        let (data, _) = try await session.data(from: url)
        let spectra = try EELSDBParser.parseJSON(data)
        let synth = EELSSynthesizer()
        var records: [TrainingRecord] = []
        for spectrum in spectra {
            let record = try await synth.synthesize(from: spectrum)
            records.append(record)
        }
        return records
    }

    // MARK: - SAXS
    private func prepareSAXS() async throws -> [TrainingRecord] {
        let accessions = SAXSAccessionList.first500
        let synth = SAXSSynthesizer()
        var records: [TrainingRecord] = []
        for acc in accessions.prefix(100) {
            let url = URL(string: "https://www.sasbdb.org/rest/entry/\(acc)/")!
            do {
                let (data, _) = try await session.data(from: url)
                let profile = try SASBDBParser.parseAPIResponse(data)
                let record = try await synth.synthesize(from: profile)
                records.append(record)
            } catch { continue }
        }
        return records
    }

    // MARK: - Circular Dichroism
    private func prepareCD() async -> [TrainingRecord] {
        let synth = CDSynthesizer()
        return await synth.synthesizeBatch(count: 3000)
    }

    // MARK: - Microwave
    private func prepareMicrowave() async throws -> [TrainingRecord] {
        let species = CDMSSpeciesList.all
        let synth = MicrowaveSynthesizer()
        var records: [TrainingRecord] = []
        for tag in species.prefix(50) {
            let url = URL(string: "https://cdms.astro.uni-koeln.de/cgi-bin/cdmsinfo?file=e\(tag).cat")!
            do {
                let (data, _) = try await session.data(from: url)
                let text = String(decoding: data, as: UTF8.self)
                let lines = CDMSParser.parseCatalog(text)
                let record = try await synth.synthesize(from: lines, speciesTag: tag)
                records.append(record)
            } catch { continue }
        }
        return records
    }

    // MARK: - TGA
    private func prepareTGA() async -> [TrainingRecord] {
        let synth = TGASynthesizer()
        return await synth.synthesizeBatch(count: 3000)
    }

    // MARK: - THz
    private func prepareTHz() async -> [TrainingRecord] {
        let synth = THz_Synthesizer()
        return await synth.synthesizeBatch(count: 2000)
    }

    // MARK: - LIBS
    private func prepareLIBS() async -> [TrainingRecord] {
        let synth = LIBSSynthesizer()
        // Synthesize from known elemental compositions
        return await LIBSSampleLibrary.synthesize(synth: synth)
    }

    // MARK: - Persistence
    private func persistRecords(_ records: [TrainingRecord], modality: SpectralModality) async throws {
        let context = ModelContext(modelContainer)
        for record in records {
            let stored = StoredTrainingRecord(from: record)
            context.insert(stored)
        }
        try context.save()
    }
}

// MARK: - Supporting lists (stub enums — populate from actual data)

enum AtmosphericSpeciesList {
    static let all: [String] = ["O3", "NO2", "SO2", "HCHO", "BrO", "OClO",
                                  "CHOCHO", "H2O2", "NO3", "N2O5", "HOBr", "IO"]
}

enum SAXSAccessionList {
    static let first500: [String] = (1...500).map { String(format: "SASDA%03d", $0) }
}

enum CDMSSpeciesList {
    static let all: [String] = ["28001","28002","32001","44003","18002",
                                  "17001","34001","64001","48001","46013"]
}

enum OpticalMaterialLibrary {
    // (name, n-array interp on grid, k-array interp on grid)
    static let commonMaterials: [(String, [Double], [Double])] = []  // Populate from Sellmeier tables
}

enum LIBSSampleLibrary {
    static func synthesize(synth: LIBSSynthesizer) async -> [TrainingRecord] {
        let compositions: [[(String, Double)]] = [
            [("Fe", 0.98), ("C", 0.02)],
            [("Al", 0.95), ("Mg", 0.05)],
            [("Cu", 0.90), ("Zn", 0.10)],
            [("Si", 1.00)],
            [("Ca", 0.50), ("Mg", 0.30), ("Fe", 0.20)]
        ]
        var records: [TrainingRecord] = []
        let lineDB: [String: [(lambda_nm: Double, Aki: Double, Ek_eV: Double, gk: Int)]] = [:]
        for comp in compositions {
            for Te in [0.5, 1.0, 1.5, 2.0, 3.0] {
                for ne in [1e15, 1e16, 1e17] {
                    let r = await synth.synthesize(elements: comp.map { (symbol: $0.0, fraction: $0.1) },
                                                    Te_eV: Te, ne_cm3: ne, lineDatabase: lineDB)
                    records.append(r)
                }
            }
        }
        return records
    }
}
```

---

## PHASE 23 — Universal TrainingDataExporter

Exports any modality's records to a CoreML-ready CSV. Column order matches
`ModalityAxisSpec.featureLabels` from ModalitySchemas.swift (Part 1).

Create `Training/Curation/TrainingDataExporter.swift`:

```swift
import Foundation
import SwiftData

actor TrainingDataExporter {

    let modelContainer: ModelContainer

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    // Export all records for a given modality to a CSV file
    func export(modality: SpectralModality, to url: URL) async throws {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<StoredTrainingRecord>(
            predicate: #Predicate { $0.modalityRaw == modality.rawValue }
        )
        let records = try context.fetch(descriptor)
        guard !records.isEmpty else { throw ExportError.noRecords }

        let schema = ModalitySchemas.spec(for: modality)
        var csv = schema.featureLabels.joined(separator: ",")
        csv += "," + schema.targetLabels.joined(separator: ",") + "\n"

        for record in records {
            let featureStr = record.featuresData
                .withUnsafeBytes { ptr in
                    ptr.bindMemory(to: Float.self)
                        .prefix(schema.featureCount)
                        .map { String($0) }
                        .joined(separator: ",")
                }
            let targetStr = schema.targetLabels.map { label in
                String(record.targetsJSON[label] ?? 0)
            }.joined(separator: ",")
            csv += featureStr + "," + targetStr + "\n"
        }

        try csv.write(to: url, atomically: true, encoding: .utf8)
    }

    // Export all modalities as separate CSVs in a directory
    func exportAll(to directory: URL) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for modality in SpectralModality.allCases {
                group.addTask {
                    let fileURL = directory.appendingPathComponent("\(modality.rawValue)_training.csv")
                    try await self.export(modality: modality, to: fileURL)
                }
            }
            try await group.waitForAll()
        }
    }

    // Build CoreML MLBoostedTreeRegressor from exported CSV (macOS only)
    // Run this from a macOS-only build target
    #if os(macOS)
    func trainModel(csvURL: URL, modality: SpectralModality) async throws -> URL {
        // Import Create ML
        // This must be called in a macOS app target
        let outputURL = csvURL.deletingLastPathComponent()
            .appendingPathComponent("\(modality.rawValue).mlpackage")
        return outputURL
        // Full CreateML training code:
        // import CreateML
        // let table = try MLDataTable(contentsOf: csvURL)
        // let schema = ModalitySchemas.spec(for: modality)
        // let regressor = try MLBoostedTreeRegressor(
        //     trainingData: table,
        //     targetColumn: schema.targetLabels[0]
        // )
        // try regressor.write(to: outputURL)
    }
    #endif

    enum ExportError: Error {
        case noRecords
        case schemaNotFound
    }
}
```

---

## PHASE 24 — Multi-Modality Training UI

Create `Training/UI/TrainingDataDashboardView.swift`:

```swift
import SwiftUI

struct TrainingDataDashboardView: View {
    @Environment(TrainingDataCoordinator.self) private var coordinator

    private let columns = [
        GridItem(.adaptive(minimum: 280, maximum: 380), spacing: 16)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(SpectralModality.allCases) { modality in
                        ModalityTrainingCardView(
                            modality: modality,
                            status: coordinator.modalityStatus[modality] ?? .idle
                        )
                    }
                }
                .padding()
            }
            .navigationTitle("Training Data — \(coordinator.totalRecordCount) records")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Prepare All") {
                        Task { await coordinator.prepareAll() }
                    }
                }
            }
        }
    }
}

struct ModalityTrainingCardView: View {
    let modality: SpectralModality
    let status: TrainingDataCoordinator.ModalityStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: modality.systemImage)
                    .font(.title2)
                    .foregroundStyle(statusColor)
                Spacer()
                statusBadge
            }

            Text(modality.displayName)
                .font(.headline)

            Text(modality.pinnPhysicsLaw)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Divider()

            HStack {
                Text(modality.primaryDataSource)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                Spacer()
                if case .ready(let count) = status {
                    Text("\(count) records")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.green)
                }
            }

            if case .downloading(let p) = status {
                ProgressView(value: p)
            } else if case .synthesizing(let p) = status {
                ProgressView(value: p)
                    .tint(.orange)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch status {
        case .idle:
            Text("Idle").font(.caption2).padding(.horizontal, 8).padding(.vertical, 3)
                .background(.gray.opacity(0.2), in: Capsule())
        case .downloading:
            Text("Downloading").font(.caption2).padding(.horizontal, 8).padding(.vertical, 3)
                .background(.blue.opacity(0.2), in: Capsule())
        case .synthesizing:
            Text("Synthesizing").font(.caption2).padding(.horizontal, 8).padding(.vertical, 3)
                .background(.orange.opacity(0.2), in: Capsule())
        case .training:
            Text("Training").font(.caption2).padding(.horizontal, 8).padding(.vertical, 3)
                .background(.purple.opacity(0.2), in: Capsule())
        case .ready(let count):
            Text("✓ \(count)").font(.caption2).padding(.horizontal, 8).padding(.vertical, 3)
                .background(.green.opacity(0.2), in: Capsule())
        case .error:
            Text("Error").font(.caption2).padding(.horizontal, 8).padding(.vertical, 3)
                .background(.red.opacity(0.2), in: Capsule())
        }
    }

    private var statusColor: Color {
        switch status {
        case .idle: .gray
        case .downloading: .blue
        case .synthesizing: .orange
        case .training: .purple
        case .ready: .green
        case .error: .red
        }
    }
}
```

Add to `SpectralModality` extension (in SpectralModality.swift from Part 1, add these computed properties):

```swift
// Add inside SpectralModality extension block:
var displayName: String {
    switch self {
    case .uvVis:              return "UV-Vis Absorption"
    case .ftir:               return "FTIR Mid-Infrared"
    case .nir:                return "Near-Infrared (NIR)"
    case .raman:              return "Raman Scattering"
    case .massSpecEI:         return "Mass Spec EI"
    case .massSpecMSMS:       return "MS/MS Tandem"
    case .nmrProton:          return "¹H NMR"
    case .nmrCarbon:          return "¹³C NMR"
    case .fluorescence:       return "Fluorescence"
    case .xrdPowder:          return "XRD Powder Diffraction"
    case .xps:                return "X-Ray Photoelectron (XPS)"
    case .eels:               return "EELS"
    case .atomicEmission:     return "Atomic Emission / OES"
    case .libs:               return "LIBS Plasma"
    case .gcRetention:        return "GC Retention Index"
    case .hplcRetention:      return "HPLC Retention"
    case .hitranMolecular:    return "HITRAN Molecular Lines"
    case .atmosphericUVVis:   return "Atmospheric UV/Vis"
    case .usgsReflectance:    return "USGS Reflectance"
    case .opticalConstants:   return "Optical Constants n,k"
    case .saxs:               return "SAXS/SANS"
    case .circularDichroism:  return "Circular Dichroism"
    case .microwaveRotational:return "Microwave / Rotational"
    case .thermogravimetric:  return "Thermogravimetric (TGA)"
    case .terahertz:          return "Terahertz (THz)"
    }
}

var systemImage: String {
    switch self {
    case .uvVis, .atmosphericUVVis: return "sun.max.fill"
    case .ftir, .nir:               return "waveform.path"
    case .raman:                    return "sparkles"
    case .massSpecEI, .massSpecMSMS:return "chart.bar.xaxis"
    case .nmrProton, .nmrCarbon:    return "atom"
    case .fluorescence:             return "lightbulb.fill"
    case .xrdPowder:                return "circle.hexagongrid.fill"
    case .xps, .eels:               return "bolt.fill"
    case .atomicEmission, .libs:    return "flame.fill"
    case .gcRetention, .hplcRetention: return "flask.fill"
    case .hitranMolecular, .microwaveRotational: return "antenna.radiowaves.left.and.right"
    case .usgsReflectance:          return "mountain.2.fill"
    case .opticalConstants:         return "camera.filters"
    case .saxs:                     return "dot.radiowaves.right"
    case .circularDichroism:        return "arrow.triangle.2.circlepath"
    case .thermogravimetric:        return "thermometer.medium"
    case .terahertz:                return "waveform"
    }
}

var primaryDataSource: String {
    switch self {
    case .uvVis:              return "NIST WebBook / SDBS"
    case .ftir:               return "NIST SRD 35 / RRUFF"
    case .nir:                return "Zenodo / NIST WebBook"
    case .raman:              return "RRUFF / SDBS"
    case .massSpecEI:         return "NIST WebBook / MoNA"
    case .massSpecMSMS:       return "MoNA 700K / GNPS"
    case .nmrProton:          return "nmrshiftdb2 / SDBS"
    case .nmrCarbon:          return "nmrshiftdb2 / SDBS"
    case .fluorescence:       return "FPbase / PhotochemCAD"
    case .xrdPowder:          return "COD 500K+ CIF"
    case .xps:                return "NIST SRD 20"
    case .eels:               return "eelsdb.eu (ODbL)"
    case .atomicEmission:     return "NIST ASD"
    case .libs:               return "NIST ASD + synthesis"
    case .gcRetention:        return "NIST WebBook GC-RI"
    case .hplcRetention:      return "HMDB / PredRet"
    case .hitranMolecular:    return "HITRAN 2024"
    case .atmosphericUVVis:   return "MPI-Mainz Atlas"
    case .usgsReflectance:    return "USGS splib07"
    case .opticalConstants:   return "refractiveindex.info"
    case .saxs:               return "SASBDB"
    case .circularDichroism:  return "PCDDB"
    case .microwaveRotational:return "CDMS Cologne"
    case .thermogravimetric:  return "NIST JANAF / Zenodo"
    case .terahertz:          return "Zenodo THz datasets"
    }
}
```

Create `Training/UI/ReferenceLibraryView.swift`:

```swift
import SwiftUI
import SwiftData

struct ReferenceLibraryView: View {
    @Query private var spectra: [StoredReferenceSpectrum]
    @State private var selectedModality: SpectralModality? = nil
    @State private var searchText = ""

    var filtered: [StoredReferenceSpectrum] {
        spectra.filter { s in
            (selectedModality == nil || s.modalityRaw == selectedModality?.rawValue) &&
            (searchText.isEmpty || s.sourceID.localizedCaseInsensitiveContains(searchText))
        }
    }

    var body: some View {
        NavigationSplitView {
            List(SpectralModality.allCases, selection: $selectedModality) { modality in
                Label(modality.displayName, systemImage: modality.systemImage)
                    .tag(Optional(modality))
            }
            .listStyle(.sidebar)
            .navigationTitle("Modalities")
        } detail: {
            List(filtered, id: \.sourceID) { spectrum in
                VStack(alignment: .leading) {
                    Text(spectrum.sourceID).font(.headline)
                    Text(spectrum.modalityRaw).font(.caption).foregroundStyle(.secondary)
                }
            }
            .searchable(text: $searchText)
            .navigationTitle(selectedModality?.displayName ?? "All Spectra")
        }
    }
}
```

Create `Training/UI/TrainingRecordAnnotationView.swift`:

```swift
import SwiftUI
import SwiftData

struct TrainingRecordAnnotationView: View {
    let record: StoredTrainingRecord
    @Environment(\.modelContext) private var context
    @State private var qualityScore: Double = 1.0
    @State private var notes = ""
    @State private var isExcluded = false

    var body: some View {
        Form {
            Section("Record") {
                LabeledContent("Source ID", value: record.sourceID)
                LabeledContent("Modality", value: record.modalityRaw)
                LabeledContent("Created", value: record.createdAt.formatted())
            }

            Section("Annotation") {
                LabeledContent("Quality Score") {
                    Slider(value: $qualityScore, in: 0...1, step: 0.1)
                }
                Toggle("Exclude from Training", isOn: $isExcluded)
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(4)
            }

            Section("Targets") {
                ForEach(Array(record.targetsJSON.sorted(by: { $0.key < $1.key })), id: \.key) { k, v in
                    LabeledContent(k, value: String(format: "%.6g", v))
                }
            }

            Section {
                Button("Save Annotation") { saveAnnotation() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .navigationTitle("Annotate Record")
        .onAppear { notes = record.annotationNotes ?? "" }
    }

    private func saveAnnotation() {
        record.qualityScore = qualityScore
        record.annotationNotes = notes
        record.isExcluded = isExcluded
        try? context.save()
    }
}
```

> NOTE: `StoredTrainingRecord` needs these additional properties added to its `@Model` class
> (defined in Part 1): `var qualityScore: Double = 1.0`, `var annotationNotes: String? = nil`,
> `var isExcluded: Bool = false`.

---

## PHASE 25 — Manifest & Update Engine

The manifest enables in-app updates to reference libraries and training data packages
without requiring an App Store submission.

Create `Training/Models/TrainingDataManifest.swift`:

```swift
import Foundation

struct TrainingDataManifest: Codable, Sendable {
    let version: String              // semver e.g. "1.3.0"
    let generated: Date
    let packages: [ModalityPackage]

    struct ModalityPackage: Codable, Sendable, Identifiable {
        let id: String               // = SpectralModality.rawValue
        let version: String
        let recordCount: Int
        let downloadURL: URL
        let sha256: String           // hex SHA-256 of zip payload
        let sizeBytes: Int
        let physics: String          // short physics law description
        let changelog: String
    }
}
```

Create `Training/Curation/ManifestUpdateService.swift`:

```swift
import Foundation
import CryptoKit

actor ManifestUpdateService {

    static let manifestURL = URL(string: "https://raw.githubusercontent.com/yourorgrepo/spectral-training-data/main/manifest.json")!

    private let session = URLSession(configuration: .ephemeral)

    // Fetch and decode remote manifest
    func fetchManifest() async throws -> TrainingDataManifest {
        let (data, _) = try await session.data(from: Self.manifestURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(TrainingDataManifest.self, from: data)
    }

    // Download, verify SHA-256, unzip, and hand off records to coordinator
    func downloadPackage(_ package: TrainingDataManifest.ModalityPackage,
                         progressHandler: @Sendable @escaping (Double) -> Void) async throws -> URL {
        let (tempURL, response) = try await session.download(from: package.downloadURL)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ManifestError.downloadFailed
        }

        // Verify SHA-256
        let fileData = try Data(contentsOf: tempURL)
        let digest = SHA256.hash(data: fileData)
        let hexDigest = digest.map { String(format: "%02x", $0) }.joined()
        guard hexDigest.lowercased() == package.sha256.lowercased() else {
            throw ManifestError.checksumMismatch(expected: package.sha256, actual: hexDigest)
        }

        // Move to app's Application Support directory
        let destDir = try FileManager.default.url(for: .applicationSupportDirectory,
                                                    in: .userDomainMask,
                                                    appropriateFor: nil, create: true)
            .appendingPathComponent("SpectralTrainingData/\(package.id)", isDirectory: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        let destURL = destDir.appendingPathComponent("\(package.id)_\(package.version).zip")
        try FileManager.default.moveItem(at: tempURL, to: destURL)
        return destURL
    }

    enum ManifestError: Error, LocalizedError {
        case downloadFailed
        case checksumMismatch(expected: String, actual: String)

        var errorDescription: String? {
            switch self {
            case .downloadFailed: return "Package download failed"
            case .checksumMismatch(let e, let a): return "SHA-256 mismatch: expected \(e), got \(a)"
            }
        }
    }
}
```

---

## COMPLETE 25-MODALITY BUILD CHECKLIST

Mark each item ✅ when the file compiles cleanly under Swift 6 strict concurrency.

**Foundation (Part 1 — CLAUDE.md)**
- [ ] `Training/Models/SpectralModality.swift` — 25 cases, all properties
- [ ] `Training/Models/ModalitySchemas.swift` — ModalityAxisSpec for all 25
- [ ] `Training/Models/TrainingRecord.swift` — value type, Sendable
- [ ] `Training/Models/ReferenceSpectrum.swift` — value type, Sendable
- [ ] `Training/Models/StoredTrainingRecord.swift` — @Model, all fields incl. qualityScore/isExcluded
- [ ] `Training/Models/StoredReferenceSpectrum.swift` — @Model
- [ ] `Training/Models/TrainingDataManifest.swift` — Codable, Sendable
- [ ] `Training/Parsers/JCAMPDXParser.swift` — handles UV, IR, Raman, NMR, MS; detectModality()
- [ ] `Training/Parsers/CIFParser.swift` — COD crystallographic file
- [ ] `Training/Parsers/HITRANParser.swift` — 160-char fixed-width
- [ ] `Training/Parsers/MoNAJSONParser.swift`
- [ ] `Training/Parsers/NMRShiftDBParser.swift`
- [ ] `Training/Parsers/RRUFFParser.swift`

**Parsers (Part 2)**
- [ ] `Training/Parsers/USGSTXTParser.swift`
- [ ] `Training/Parsers/EELSDBParser.swift`
- [ ] `Training/Parsers/SASBDBParser.swift`
- [ ] `Training/Parsers/CDMSParser.swift`
- [ ] `Training/Parsers/RefractiveIndexYAMLParser.swift`

**Synthesizers (Part 1 — CLAUDE.md)**
- [ ] `Training/Synthesis/BeerLambertSynthesizer.swift` (UV-Vis + FTIR + NIR)
- [ ] `Training/Synthesis/RamanSynthesizer.swift`
- [ ] `Training/Synthesis/MassSpecEISynthesizer.swift`
- [ ] `Training/Synthesis/MassSpecMSMSSynthesizer.swift`
- [ ] `Training/Synthesis/NMRProtonSynthesizer.swift`
- [ ] `Training/Synthesis/NMRCarbonSynthesizer.swift`
- [ ] `Training/Synthesis/FluorescenceSynthesizer.swift`
- [ ] `Training/Synthesis/XRDSynthesizer.swift`
- [ ] `Training/Synthesis/XPSSynthesizer.swift`
- [ ] `Training/Synthesis/AtomicEmissionSynthesizer.swift`
- [ ] `Training/Synthesis/GCRetentionSynthesizer.swift`
- [ ] `Training/Synthesis/HPLCSynthesizer.swift`
- [ ] `Training/Synthesis/HITRANSynthesizer.swift`

**Synthesizers (Part 2)**
- [ ] `Training/Synthesis/AtmosphericUVVisSynthesizer.swift`
- [ ] `Training/Synthesis/USGSSynthesizer.swift`
- [ ] `Training/Synthesis/OpticalConstantsSynthesizer.swift`
- [ ] `Training/Synthesis/EELSSynthesizer.swift`
- [ ] `Training/Synthesis/SAXSSynthesizer.swift`
- [ ] `Training/Synthesis/CDSynthesizer.swift`
- [ ] `Training/Synthesis/MicrowaveSynthesizer.swift`
- [ ] `Training/Synthesis/TGASynthesizer.swift`
- [ ] `Training/Synthesis/THz Synthesizer.swift`
- [ ] `Training/Synthesis/LIBSSynthesizer.swift`

**Sources (all 23 data source actors)**
- [ ] `Training/Sources/TrainingDataSourceProtocol.swift`
- [ ] `Training/Sources/NISTWebBookSource.swift`
- [ ] `Training/Sources/SDBSSource.swift`
- [ ] `Training/Sources/RRUFFSource.swift`
- [ ] `Training/Sources/MoNASource.swift`
- [ ] `Training/Sources/MassBankEuropeSource.swift`
- [ ] `Training/Sources/GNPSSource.swift`
- [ ] `Training/Sources/HMDBSource.swift`
- [ ] `Training/Sources/nmrshiftdb2Source.swift`
- [ ] `Training/Sources/FPbaseSource.swift`
- [ ] `Training/Sources/PhotochemCADSource.swift`
- [ ] `Training/Sources/CODSource.swift`
- [ ] `Training/Sources/AMCSDSource.swift`
- [ ] `Training/Sources/NISTXPSSource.swift`
- [ ] `Training/Sources/NISTASDSource.swift`
- [ ] `Training/Sources/MPIMainzSource.swift`
- [ ] `Training/Sources/HITRANSource.swift`
- [ ] `Training/Sources/USGSSource.swift`
- [ ] `Training/Sources/refractiveIndexSource.swift`
- [ ] `Training/Sources/EELSDBSource.swift`
- [ ] `Training/Sources/SASBDBSource.swift`
- [ ] `Training/Sources/PCDDBSource.swift`
- [ ] `Training/Sources/CDMSSource.swift`
- [ ] `Training/Sources/ZenodoNIRSource.swift`
- [ ] `Training/Sources/ZenodoTHzSource.swift`

**Curation & UI**
- [ ] `Training/Curation/TrainingDataCoordinator.swift`
- [ ] `Training/Curation/TrainingDataExporter.swift`
- [ ] `Training/Curation/ManifestUpdateService.swift`
- [ ] `Training/UI/TrainingDataDashboardView.swift`
- [ ] `Training/UI/ModalityTrainingCardView.swift`
- [ ] `Training/UI/ReferenceLibraryView.swift`
- [ ] `Training/UI/TrainingRecordAnnotationView.swift`

**SpectralModality extensions (add to existing file)**
- [ ] `displayName` computed property — all 25 cases
- [ ] `systemImage` computed property — all 25 cases
- [ ] `primaryDataSource` computed property — all 25 cases

---

## SWIFT 6 CONCURRENCY COMPLIANCE RULES (REMINDER)

1. Every synthesizer is an `actor` — all methods are `async`
2. Every parser uses `nonisolated static` methods — no actor isolation needed for pure transforms
3. `TrainingRecord` and `ReferenceSpectrum` are `struct` — fully `Sendable` by default
4. `StoredTrainingRecord` is a SwiftData `@Model` — always access from `@MainActor` context or via `ModelContext` inside actor-local task
5. No `DispatchQueue` anywhere — use `async let`, `withTaskGroup`, `AsyncThrowingStream`
6. `URLSession.shared.data(from:)` is already `async throws` — call directly with `await`
7. `@unchecked Sendable` is FORBIDDEN — fix the actual isolation instead
8. `Task { @MainActor in }` is the correct pattern for jumping to the main actor from a background actor
9. All `@Observable` types must be `@MainActor` — mark the class with `@MainActor` at declaration
10. Feature arrays (`[Float]`) stored in `TrainingRecord` as `featuresData: Data` using `withUnsafeBytes` conversion

---

## PHYSICS CONSTANTS REFERENCE

```
h  = 6.62607015e-34 J·s      (Planck)
c  = 2.99792458e8  m/s       (speed of light)
kB = 1.380649e-23  J/K       (Boltzmann)
NA = 6.02214076e23 mol⁻¹     (Avogadro)
R  = 8.314462      J/(mol·K) (gas constant)
e  = 1.60217663e-19 C        (elementary charge)
me = 9.10938370e-31 kg       (electron mass)
ε₀ = 8.85418782e-12 F/m     (vacuum permittivity)
1 eV = 8065.54 cm⁻¹  =  1.60218e-19 J
1 cm⁻¹ = 1.4388 K  (kT in wavenumber units: kB·T/hc)
1 Debye = 3.33564e-30 C·m
```

---

*End of CLAUDE2.md — Part 2 of 2.*
*Total implementation: 25 PINN modalities, ~60 Swift files, >1.6M freely available training records.*
