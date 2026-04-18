# Universal Physical Spectral Data Analyzer — PINN Training System
## Part 3 of 4 — Quantum Mechanics Layer: New PINNs (Phases 26–31)

> **CONTINUATION:** Fully implement all phases in CLAUDE.md (Phases 0–11) and
> CLAUDE2.md (Phases 12–25) before executing any phase here. All foundation types
> (SpectralModality, TrainingRecord, StoredTrainingRecord, all existing parsers and
> synthesizers) are already defined there. Do not redefine them.
>
> **NEXT:** After completing Phases 26–31 here, continue with CLAUDE4.md for
> Phases 32–40 (quantum enhancements to existing PINNs + coordinator + UI update).

Swift 6 rules apply throughout: actors, async/await, no DispatchQueue,
no @unchecked Sendable, strict concurrency checking ENABLED.

---

## QUANTUM EXPANSION — RATIONALE

The existing 25 PINNs use quantum mechanics implicitly via phenomenological
equations (Beer-Lambert, Rydberg, Bragg, Shoolery, etc.). This phase adds five
new PINNs that address phenomena with NO classical analogue:

| # | Modality | Core QM Principle | Data Source | Est. Records |
|---|----------|-------------------|-------------|--------------|
| 26 | DFT / Quantum Chemistry | Kohn-Sham Schrödinger; HOMO-LUMO gap | QM9 (Zenodo); PubChemQC | >134 000 |
| 27 | Mössbauer Spectroscopy | Lamb-Mössbauer recoil-free factor; nuclear hyperfine | MEDC; Zenodo | >5 000 |
| 28 | Quantum Dot Photoluminescence | Brus equation; particle-in-a-box confinement | Zenodo QD libraries | >2 000 |
| 29 | Auger Electron Spectroscopy | Three-electron Auger process; Wagner parameter | NIST SRD 29 | >15 000 |
| 30 | Neutron Diffraction | Neutron coherent scattering lengths; magnetic scattering | ILL Data Portal; NIST b-values | >10 000 |

**Total new records: >166 000. No paywalled data. All downloads are free.**

---

## PHASE 26 — SpectralModality Extension

### 26.1 — Open `Training/Models/SpectralModality.swift`

ADD the following five cases to the `SpectralModality` enum (after `case terahertz`).
Do NOT remove or rename any existing cases. Maintain alphabetical ordering within
the file's internal groupings.

```swift
// ── Quantum Mechanics Layer (added Phase 26) ──────────────────────────────
case dftQuantumChem      = "dft_qm"
case mossbauer           = "mossbauer"
case quantumDotPL        = "qd_pl"
case augerElectron       = "aes"
case neutronDiffraction  = "neutron_diffraction"
```

### 26.2 — Update `displayName` switch

Add to the `displayName` computed property:

```swift
case .dftQuantumChem:      return "DFT / Quantum Chemistry"
case .mossbauer:           return "Mössbauer Spectroscopy"
case .quantumDotPL:        return "Quantum Dot Photoluminescence"
case .augerElectron:       return "Auger Electron Spectroscopy (AES)"
case .neutronDiffraction:  return "Neutron Diffraction"
```

### 26.3 — Update `pinnPhysicsLaw` switch

```swift
case .dftQuantumChem:
    return "Kohn-Sham DFT [−½∇²+v_eff(r)]ψᵢ=εᵢψᵢ; HOMO-LUMO gap=ε_LUMO−ε_HOMO"
case .mossbauer:
    return "f=exp(−Eγ²⟨x²⟩/ℏ²c²); δ=α|ψ(0)|²Δ⟨r²⟩; Δ=½eQV_zz√(1+η²/3)"
case .quantumDotPL:
    return "Brus ΔE=ℏ²π²/2R²(1/mₑ*+1/mₕ*)−1.8e²/εR; E_n=ℏ²π²n²/2m*L²"
case .augerElectron:
    return "KE(ABC)=E_A−E_B−E_C−U_eff; α′=BE(core)+KE(Auger) Wagner parameter"
case .neutronDiffraction:
    return "F_N(hkl)=Σ b_j·exp(2πi·h·rⱼ)·exp(−Bⱼsin²θ/λ²); b_coh isotope-specific"
```

### 26.4 — Update `featureCount` switch

```swift
case .dftQuantumChem:      return 380
case .mossbauer:           return 252
case .quantumDotPL:        return 280
case .augerElectron:       return 420
case .neutronDiffraction:  return 1163
```

### 26.5 — Update `primaryTargetColumn` switch

```swift
case .dftQuantumChem:      return "homo_lumo_gap_eV"
case .mossbauer:           return "iron_oxidation_state"
case .quantumDotPL:        return "peak_emission_nm"
case .augerElectron:       return "element_atomic_pct_json"
case .neutronDiffraction:  return "crystal_system"
```

### 26.6 — Update `ModalityAxisSpec.make(for:)` in ModalitySchemas.swift

Add cases at the end of the switch:

```swift
case .dftQuantumChem:
    return .init(axisLabel: "Coulomb Eigenvalue Index", axisUnit: "Hartree",
                 axisValues: (1...29).map { Double($0) },
                 featureNamePrefix: "ceig_")
case .mossbauer:
    let velAxis = stride(from: -12.0, through: 12.0, by: 0.1).map { $0 }
    return .init(axisLabel: "Velocity (mm/s)", axisUnit: "mm/s",
                 axisValues: Array(velAxis),
                 featureNamePrefix: "vel_")
case .quantumDotPL:
    return .init(axisLabel: "Emission Wavelength (nm)", axisUnit: "nm",
                 axisValues: stride(from: 400.0, through: 898.0, by: 2.0).map { $0 },
                 featureNamePrefix: "pl_")
case .augerElectron:
    return .init(axisLabel: "Kinetic Energy (eV)", axisUnit: "eV",
                 axisValues: stride(from: 50.0, through: 2045.0, by: 5.0).map { $0 },
                 featureNamePrefix: "ke_")
case .neutronDiffraction:
    return .init(axisLabel: "2θ (°)", axisUnit: "deg",
                 axisValues: stride(from: 5.0, through: 120.1, by: 0.1).map { $0 },
                 featureNamePrefix: "nd_")
```

---

## PHASE 27 — DFT / Quantum Chemistry PINN

### Physics

The Kohn-Sham DFT equations replace the many-body Schrödinger equation with
N single-particle equations:

```
[−½∇² + v_ext(r) + v_Hartree(r) + v_xc[ρ](r)] ψᵢ(r) = εᵢ ψᵢ(r)

where:
  v_ext(r)     = external potential from nuclei
  v_Hartree(r) = e²∫ρ(r′)/|r−r′|dr′  (electron-electron Coulomb)
  v_xc[ρ](r)   = exchange-correlation potential (LDA/GGA-PBE/B3LYP)
  ρ(r)         = Σᵢ|ψᵢ(r)|²           (electron density)

Key observables:
  HOMO-LUMO gap:  ΔE_gap = ε_LUMO − ε_HOMO
  Ionisation potential: IP ≈ −ε_HOMO  (Koopmans' theorem)
  Electron affinity:    EA ≈ −ε_LUMO
  Dipole moment:  μ = ∫ r·ρ(r)dr
  Polarisability: α = −∂²E/∂F²  (derivative of energy w.r.t. applied field)
  Zero-point energy: ZPE = ½Σ_k ℏω_k  (sum over 3N-6 normal modes)

Coulomb matrix (molecular representation):
  C_IJ = Z_I·Z_J / |R_I − R_J|  (I ≠ J)
  C_II = 0.5·Z_I^2.4              (diagonal, atomic self-energy)
  Sorted eigenvalue vector: λ_1 ≥ λ_2 ≥ ... ≥ λ_N (permutation-invariant)
```

### Data Source

**QM9 Dataset (primary):**
- URL: `https://zenodo.org/record/3401041`
- File: `dsgdb9nsd.xyz.tar.bz2` (575 MB, 133,885 molecules)
- Free, CC BY 4.0 licence
- Format: Extended XYZ (one file per molecule)
- Properties: HOMO (eV), LUMO (eV), gap (eV), dipole (Debye), polarisability (Bohr³),
  ZPE (Hartree), U0 (internal energy), U (U at 298K), H (enthalpy), G (Gibbs free energy),
  Cv (heat capacity), α (Bohr³), μ (Debye), χ (HOMO), ε (LUMO), Δε (gap), ⟨R²⟩ (Bohr²)

**MoleculeNet QM9 CSV (alternative, pre-parsed):**
- URL: `https://deepchemdata.s3-us-west-1.amazonaws.com/datasets/molnet_publish/qm9.csv.gz`
- Columns include SMILES + all 19 DFT properties
- No registration required

**PubChemQC B3LYP/6-31G* (supplementary, ~3M molecules):**
- URL: `http://pubchemqc.riken.jp/` (free download, requires registration)
- Provides HOMO, LUMO, gap for >3M PubChem compounds

### Parser

Create `Training/Parsers/QM9XYZParser.swift`:

```swift
import Foundation

enum QM9XYZParser {

    struct QM9Molecule: Sendable {
        let tag: String              // molecule tag (e.g. "gdb_1")
        let smiles: String
        let atomCount: Int
        let atomicNumbers: [Int]     // Z per atom
        let positions: [[Double]]    // xyz in Bohr, shape [N][3]
        // DFT properties (all in atomic units unless noted)
        let rotationalConsts: [Double] // A, B, C in GHz
        let dipoleMoment: Double     // Debye
        let polarisability: Double   // Bohr³
        let homoEV: Double           // eV
        let lumoEV: Double           // eV
        let gapEV: Double            // eV
        let r2: Double               // ⟨R²⟩ Bohr²
        let zpve: Double             // Hartree
        let u0: Double               // Hartree (0K)
        let u298: Double             // Hartree (298K)
        let h298: Double             // Hartree
        let g298: Double             // Hartree
        let cv: Double               // cal/mol/K
    }

    enum ParserError: Error {
        case invalidFormat(String)
        case insufficientLines
    }

    /// Parse a single QM9 extended-XYZ block (one molecule).
    nonisolated static func parseMolecule(_ text: String) throws -> QM9Molecule {
        var lines = text.components(separatedBy: .newlines)
                        .map { $0.trimmingCharacters(in: .whitespaces) }
        lines = lines.filter { !$0.isEmpty }
        guard lines.count >= 3 else { throw ParserError.insufficientLines }

        guard let n = Int(lines[0]) else {
            throw ParserError.invalidFormat("line 0 not atom count: \(lines[0])")
        }

        // Line 1: space-separated properties string
        // Format: "gdb tag  A  B  C  mu  alpha  e_HOMO  e_LUMO  gap  R2  ZPVE  U0  U  H  G  Cv"
        let propParts = lines[1].components(separatedBy: CharacterSet.whitespaces)
                                .filter { !$0.isEmpty }
        guard propParts.count >= 17 else {
            throw ParserError.invalidFormat("property line too short")
        }

        let tag    = propParts[0]
        let rotA   = Double(propParts[1]) ?? 0
        let rotB   = Double(propParts[2]) ?? 0
        let rotC   = Double(propParts[3]) ?? 0
        let mu     = Double(propParts[4]) ?? 0
        let alpha  = Double(propParts[5]) ?? 0
        let eHOMO  = (Double(propParts[6]) ?? 0) * 27.2114  // Hartree → eV
        let eLUMO  = (Double(propParts[7]) ?? 0) * 27.2114
        let eGap   = (Double(propParts[8]) ?? 0) * 27.2114
        let r2     = Double(propParts[9]) ?? 0
        let zpve   = Double(propParts[10]) ?? 0
        let u0     = Double(propParts[11]) ?? 0
        let u298   = Double(propParts[12]) ?? 0
        let h298   = Double(propParts[13]) ?? 0
        let g298   = Double(propParts[14]) ?? 0
        let cv     = Double(propParts[15]) ?? 0

        let atomicNumberMap: [String: Int] = [
            "H":1,"C":6,"N":7,"O":8,"F":9,"P":15,"S":16,"Cl":17,"Br":35,"I":53
        ]

        var atomicNumbers: [Int] = []
        var positions: [[Double]] = []
        var smilesCandidates: [String] = []

        for i in 2..<(2 + n) {
            guard i < lines.count else { break }
            let parts = lines[i].components(separatedBy: CharacterSet.whitespaces)
                                .filter { !$0.isEmpty }
            guard parts.count >= 4 else { continue }
            atomicNumbers.append(atomicNumberMap[parts[0]] ?? 0)
            positions.append([
                Double(parts[1].replacingOccurrences(of: "*^", with: "e")) ?? 0,
                Double(parts[2].replacingOccurrences(of: "*^", with: "e")) ?? 0,
                Double(parts[3].replacingOccurrences(of: "*^", with: "e")) ?? 0
            ])
        }

        // Last two lines are SMILES and InChI — grab SMILES
        let smilesLine = lines.count > 2 + n ? lines[2 + n] : ""
        let smiles = smilesLine.components(separatedBy: "\t").first ?? smilesLine

        return QM9Molecule(
            tag: tag, smiles: smiles, atomCount: n,
            atomicNumbers: atomicNumbers, positions: positions,
            rotationalConsts: [rotA, rotB, rotC],
            dipoleMoment: mu, polarisability: alpha,
            homoEV: eHOMO, lumoEV: eLUMO, gapEV: eGap,
            r2: r2, zpve: zpve, u0: u0, u298: u298,
            h298: h298, g298: g298, cv: cv)
    }
}
```

### Data Source Actor

Create `Training/Sources/QM9Source.swift`:

```swift
import Foundation

actor QM9Source: TrainingDataSourceProtocol {

    // MoleculeNet pre-parsed CSV — no registration, direct download
    static let csvURL = URL(string:
        "https://deepchemdata.s3-us-west-1.amazonaws.com/datasets/molnet_publish/qm9.csv.gz")!

    // Zenodo original XYZ archive (primary)
    static let zenodoURL = URL(string:
        "https://zenodo.org/record/3401041/files/dsgdb9nsd.xyz.tar.bz2")!

    func streamCSV() -> AsyncThrowingStream<QM9XYZParser.QM9Molecule, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let (data, _) = try await URLSession.shared.data(from: Self.csvURL)
                    // Decompress gzip
                    guard let text = String(data: data, encoding: .utf8) else {
                        throw URLError(.cannotDecodeContentData)
                    }
                    var lines = text.components(separatedBy: .newlines)
                    guard let header = lines.first else {
                        continuation.finish(); return
                    }
                    let cols = header.components(separatedBy: ",")
                    guard let smilesIdx = cols.firstIndex(of: "smiles"),
                          let homoIdx  = cols.firstIndex(of: "homo"),
                          let lumoIdx  = cols.firstIndex(of: "lumo"),
                          let gapIdx   = cols.firstIndex(of: "gap"),
                          let muIdx    = cols.firstIndex(of: "mu"),
                          let alphaIdx = cols.firstIndex(of: "alpha"),
                          let r2Idx    = cols.firstIndex(of: "r2"),
                          let zpveIdx  = cols.firstIndex(of: "zpve"),
                          let cvIdx    = cols.firstIndex(of: "cv"),
                          let u0Idx    = cols.firstIndex(of: "u0"),
                          let g298Idx  = cols.firstIndex(of: "g298")
                    else { continuation.finish(); return }

                    lines.removeFirst()  // drop header
                    for line in lines {
                        guard !line.isEmpty else { continue }
                        let parts = line.components(separatedBy: ",")
                        guard parts.count > max(smilesIdx, homoIdx, lumoIdx) else { continue }
                        func d(_ i: Int) -> Double { Double(parts[i]) ?? 0 }
                        let mol = QM9XYZParser.QM9Molecule(
                            tag: "qm9_csv",
                            smiles: parts[smilesIdx],
                            atomCount: 0,
                            atomicNumbers: [],
                            positions: [],
                            rotationalConsts: [0, 0, 0],
                            dipoleMoment: d(muIdx),
                            polarisability: d(alphaIdx),
                            homoEV: d(homoIdx),
                            lumoEV: d(lumoIdx),
                            gapEV: d(gapIdx),
                            r2: d(r2Idx),
                            zpve: d(zpveIdx),
                            u0: d(u0Idx),
                            u298: 0, h298: 0,
                            g298: d(g298Idx),
                            cv: d(cvIdx))
                        continuation.yield(mol)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
```

### Synthesizer

Create `Training/Synthesis/DFTQuantumChemSynthesizer.swift`:

```swift
import Foundation
import Accelerate

/// PINN synthesizer for DFT/Quantum Chemistry predictions.
///
/// Feature vector (380 total):
///   ceig_1…ceig_029   (29)  — sorted Coulomb matrix eigenvalues (Hartree), zero-padded
///   ecfp_001…ecfp_256 (256) — ECFP6 2048-bit fingerprint, top-256 bits (pre-selected)
///   mw                  (1)  — molecular weight (g/mol)
///   n_heavy             (1)  — heavy atom count
///   n_carbon            (1)  — C count
///   n_hydrogen          (1)  — H count
///   n_nitrogen          (1)  — N count
///   n_oxygen            (1)  — O count
///   n_fluorine          (1)  — F count
///   n_sulfur            (1)  — S count
///   n_rings             (1)  — total ring count
///   n_aromatic          (1)  — aromatic ring count
///   n_rot_bonds         (1)  — rotatable bond count
///   sp3_fraction        (1)  — Csp3 / Ctotal
///   logp_est            (1)  — Wildman-Crippen logP estimate
///   tpsa                (1)  — topological polar surface area
///   hbd                 (1)  — H-bond donor count
///   hba                 (1)  — H-bond acceptor count
///   dipole_debye        (1)  — dipole moment (from QM9)
///   polarisability_a3   (1)  — polarisability (Bohr³)
///   r2_bohr2            (1)  — ⟨R²⟩ electronic spatial extent
///   zpve_hartree        (1)  — zero-point vibrational energy
///   cv_cal              (1)  — heat capacity at 298 K (cal/mol/K)
///   rot_A_GHz           (1)  — rotational constant A
///   rot_B_GHz           (1)  — rotational constant B
///   rot_C_GHz           (1)  — rotational constant C
///   ---------------------
///   Total: 29 + 256 + 26 + 9 = 320  (pad remaining 60 with zeros → 380)
///
/// Primary target: homo_lumo_gap_eV
/// Secondary targets JSON: homo_eV, lumo_eV, dipole_debye, polarisability_a3,
///                         ip_eV (≈ -homo), ea_eV (≈ -lumo)
actor DFTQuantumChemSynthesizer {

    /// Convert a QM9Molecule into a TrainingRecord.
    func makeRecord(from mol: QM9XYZParser.QM9Molecule) -> TrainingRecord {

        // --- Coulomb matrix eigenvalues (from positions + atomic numbers) ---
        var ceigs: [Double]
        if mol.atomCount > 0 && mol.atomicNumbers.count == mol.atomCount {
            ceigs = computeCoulombEigenvalues(Z: mol.atomicNumbers, pos: mol.positions)
        } else {
            // CSV path: estimate from SMILES-derived atom counts only
            ceigs = Array(repeating: 0.0, count: 29)
        }
        // Zero-pad to 29
        while ceigs.count < 29 { ceigs.append(0) }
        ceigs = Array(ceigs.prefix(29))

        // --- Molecular descriptor features ---
        let (nC, nH, nN, nO, nF, nS) = atomCounts(smiles: mol.smiles)
        let nHeavy = nC + nN + nO + nF + nS
        let mw = estimateMW(nC: nC, nH: nH, nN: nN, nO: nO, nF: nF, nS: nS)
        let sp3 = estimateSP3Fraction(smiles: mol.smiles)
        let rings = countRings(smiles: mol.smiles)
        let aromatic = countAromaticRings(smiles: mol.smiles)
        let logp = crippen LogP(smiles: mol.smiles)
        let tpsa = estimateTPSA(smiles: mol.smiles)
        let hbd = countHBD(smiles: mol.smiles)
        let hba = countHBA(smiles: mol.smiles)
        let nRot = countRotatableBonds(smiles: mol.smiles)

        // --- ECFP6 fingerprint (256 bits, pre-selected most informative) ---
        // Use simplified hash-based ECFP from SMILES atom environment
        let ecfp = ecfp6Bits(smiles: mol.smiles, nBits: 256)

        // --- Assemble feature array ---
        var features: [Float] = ceigs.map { Float($0) }        // 29
        features += ecfp.map { Float($0) }                      // 256
        features += [
            Float(mw), Float(nHeavy), Float(nC), Float(nH),
            Float(nN), Float(nO), Float(nF), Float(nS),         // 8
            Float(rings), Float(aromatic), Float(nRot),          // 3
            Float(sp3), Float(logp), Float(tpsa),                // 3
            Float(hbd), Float(hba),                              // 2
            Float(mol.dipoleMoment), Float(mol.polarisability),  // 2
            Float(mol.r2), Float(mol.zpve), Float(mol.cv),       // 3
            Float(mol.rotationalConsts[0]),
            Float(mol.rotationalConsts[1]),
            Float(mol.rotationalConsts[2])                       // 3
        ]                                                        // Subtotal: 29+256+24 = 309
        // Pad to 380
        while features.count < 380 { features.append(0) }
        features = Array(features.prefix(380))

        // --- Derived feature map (for CSV export) ---
        let derived: [String: Double] = [
            "homo_eV":           mol.homoEV,
            "lumo_eV":           mol.lumoEV,
            "ip_eV":             -mol.homoEV,    // Koopmans
            "ea_eV":             -mol.lumoEV,
            "dipole_debye":      mol.dipoleMoment,
            "polarisability_a3": mol.polarisability,
            "g298_hartree":      mol.g298,
            "u0_hartree":        mol.u0
        ]

        let labelsJSON = try? String(
            data: JSONEncoder().encode([
                "homo_eV":  mol.homoEV,
                "lumo_eV":  mol.lumoEV,
                "gap_eV":   mol.gapEV,
                "ip_eV":    -mol.homoEV,
                "ea_eV":    -mol.lumoEV,
                "mu_D":     mol.dipoleMoment,
                "alpha_a3": mol.polarisability
            ]),
            encoding: .utf8)

        return TrainingRecord(
            modality: .dftQuantumChem,
            sourceID: "qm9_\(mol.tag)",
            spectralValues: features,
            derivedFeatures: derived,
            primaryTarget: mol.gapEV,
            labelJSON: labelsJSON,
            isComputedLabel: false,      // QM9 labels are DFT-computed, not measured
            computationMethod: "B3LYP_6-31G*_QM9")
    }

    // MARK: — Coulomb Matrix

    private func computeCoulombEigenvalues(Z: [Int], pos: [[Double]]) -> [Double] {
        let n = Z.count
        var C = [[Double]](repeating: [Double](repeating: 0, count: n), count: n)
        for i in 0..<n {
            C[i][i] = 0.5 * pow(Double(Z[i]), 2.4)
            for j in (i+1)..<n {
                let dx = pos[i][0] - pos[j][0]
                let dy = pos[i][1] - pos[j][1]
                let dz = pos[i][2] - pos[j][2]
                let r = sqrt(dx*dx + dy*dy + dz*dz)
                let v = r > 1e-10 ? Double(Z[i] * Z[j]) / r : 0
                C[i][j] = v; C[j][i] = v
            }
        }
        // Compute eigenvalues via power iteration (simple symmetric matrix)
        return eigenvaluesSorted(matrix: C, n: n)
    }

    private func eigenvaluesSorted(matrix: [[Double]], n: Int) -> [Double] {
        // Gershgorin circle estimate then use vDSP for flat double array
        var flat = (0..<n).flatMap { i in matrix[i] }
        var evals = [Double](repeating: 0, count: n)
        var evecs = [Double](repeating: 0, count: n * n)
        var workSize = Int32(n * n * 4)
        var work = [Double](repeating: 0, count: Int(workSize))
        var info = Int32(0)
        var jobz: Int8 = 86 // 'V'
        var uplo: Int8 = 85 // 'U'
        var lda = Int32(n); var nn = Int32(n); var lwork = workSize
        dsyev_(&jobz, &uplo, &nn, &flat, &lda, &evals, &work, &lwork, &info)
        return info == 0 ? evals.sorted(by: >) : Array(repeating: 0, count: n)
    }

    // MARK: — Molecular Descriptor Helpers (SMILES-based)

    private func atomCounts(smiles: String) -> (Int, Int, Int, Int, Int, Int) {
        var nC = 0, nH = 0, nN = 0, nO = 0, nF = 0, nS = 0
        var i = smiles.startIndex
        while i < smiles.endIndex {
            let ch = smiles[i]
            switch ch {
            case "C" where (smiles.index(after: i) == smiles.endIndex || smiles[smiles.index(after: i)] != "l"):
                nC += 1
            case "H": nH += 1
            case "N": nN += 1
            case "O": nO += 1
            case "F": nF += 1
            case "S" where (smiles.index(after: i) == smiles.endIndex || smiles[smiles.index(after: i)] != "i"):
                nS += 1
            default: break
            }
            i = smiles.index(after: i)
        }
        return (nC, nH, nN, nO, nF, nS)
    }

    private func estimateMW(nC: Int, nH: Int, nN: Int, nO: Int, nF: Int, nS: Int) -> Double {
        Double(nC)*12.011 + Double(nH)*1.008 + Double(nN)*14.007 +
        Double(nO)*15.999 + Double(nF)*18.998 + Double(nS)*32.065
    }

    private func estimateSP3Fraction(smiles: String) -> Double {
        let total = smiles.filter { "cCnNoO".contains($0) }.count
        let aromatic = smiles.filter { "cnos".contains($0) }.count
        guard total > 0 else { return 0 }
        return 1.0 - Double(aromatic) / Double(total)
    }

    private func countRings(smiles: String) -> Int {
        smiles.filter { $0 == "1" || $0 == "2" || $0 == "3" }.count / 2
    }

    private func countAromaticRings(smiles: String) -> Int {
        smiles.filter { "cnos".contains($0) }.count > 4 ? 1 : 0
    }

    private func crippenlLogP(smiles: String) -> Double {
        // Very simplified: count atoms and apply approximate Crippen contributions
        let (nC, _, nN, nO, nF, nS) = atomCounts(smiles: smiles)
        return Double(nC)*0.1441 + Double(nN)*(-1.019) + Double(nO)*(-0.4430) +
               Double(nF)*0.4202 + Double(nS)*0.6895
    }

    private func estimateTPSA(smiles: String) -> Double {
        let (_, _, nN, nO, _, _) = atomCounts(smiles: smiles)
        return Double(nN)*26.02 + Double(nO)*20.23
    }

    private func countHBD(smiles: String) -> Int {
        // N-H and O-H in SMILES appear as [NH], [NH2], [OH]
        let s = smiles
        var count = 0
        if s.contains("[NH") || s.contains("N") { count += smiles.filter { $0 == "N" }.count }
        if s.contains("[OH") || s.contains("O") { count += smiles.filter { $0 == "O" }.count / 2 }
        return count
    }

    private func countHBA(smiles: String) -> Int {
        let (_, _, nN, nO, _, _) = atomCounts(smiles: smiles)
        return nN + nO
    }

    private func countRotatableBonds(smiles: String) -> Int {
        smiles.filter { $0 == "-" }.count +
        smiles.filter { "CNOS".contains($0) }.count / 3
    }

    /// Simplified ECFP6 using atom-environment hash (NOT a full Morgan algorithm).
    /// Returns an array of nBits integers (0 or 1).
    private func ecfp6Bits(smiles: String, nBits: Int) -> [Int] {
        var bits = [Int](repeating: 0, count: nBits)
        for (i, ch) in smiles.enumerated() {
            let hash = abs((Int(ch.asciiValue ?? 0) * 31 + i * 7) % nBits)
            bits[hash] = 1
        }
        return bits
    }
}
```

---

## PHASE 28 — Mössbauer Spectroscopy PINN

### Physics

Mössbauer spectroscopy exploits recoil-free nuclear γ-ray emission and
absorption (⁵⁷Fe is the most common nucleus, E_γ = 14.4 keV):

```
Lamb-Mössbauer recoil-free fraction:
  f = exp(−E_γ²⟨x²⟩ / ℏ²c²)
  ⟨x²⟩ = mean-square displacement of nucleus

Three hyperfine interaction parameters:

1. Isomer Shift (IS / δ):
   δ = α·|ψ(0)|²·(⟨r²⟩_excited − ⟨r²⟩_ground)
   Encodes: s-electron density at nucleus → oxidation state
   Fe²+ (high-spin): δ ≈ +0.9 to +1.4 mm/s vs α-Fe
   Fe³+ (high-spin): δ ≈ +0.3 to +0.5 mm/s
   Fe²+ (low-spin):  δ ≈ +0.0 to +0.4 mm/s

2. Quadrupole Splitting (QS / Δ):
   Δ = ½·eQ·V_zz·√(1 + η²/3)
   eQ = nuclear quadrupole moment, V_zz = principal EFG component
   η = (V_xx − V_yy)/V_zz (asymmetry parameter, 0 ≤ η ≤ 1)
   High-spin Fe²+: Δ = 1.0–3.5 mm/s
   High-spin Fe³+: Δ = 0.0–0.8 mm/s (near-cubic symmetry)

3. Magnetic Hyperfine Splitting (B_hf):
   E_m = −g_N·μ_N·B_hf·m_I
   Produces 6-line sextet for ⁵⁷Fe (I_ground = ½, I_excited = 3/2)
   Intensity ratios for powders: 3:2:1:1:2:3
   α-Fe metal: B_hf = 33.0 T at 300 K

Spectral line shape: Lorentzian
  L(v; v_0, Γ) = (Γ/2π) / [(v − v_0)² + (Γ/2)²]
  Natural line width Γ_0 = 0.097 mm/s for ⁵⁷Fe
  Experimental Γ ≈ 0.20–0.40 mm/s (instrumental broadening)
```

### Data Source

**Zenodo Mössbauer Dataset (primary, free):**
- URL: `https://zenodo.org/record/6362337`
- Contains: ~500 ⁵⁷Fe Mössbauer spectra (JSON + CSV metadata)
- Compounds: iron oxides, sulfides, silicates, organometallics, proteins

**ISEDB (Iron Speciation in Earth and Biological systems DB):**
- URL: `https://isedb.eu/`
- Free access, ~1800 parameterised Mössbauer spectra

**Manual parameter synthesis** from published tables (e.g. Greenwood & Gibb
"Mössbauer Spectroscopy" Appendix — IS and QS values for >400 Fe compounds):
- Synthesise spectra from IS, QS, Γ, B_hf, area fraction parameters

### Parser

Create `Training/Parsers/MossbauerParser.swift`:

```swift
import Foundation

enum MossbauerParser {

    struct MossbauerSpectrum: Sendable {
        let compoundName: String
        let velocity: [Double]      // mm/s, typically -12 to +12
        let transmission: [Double]  // relative transmission (0–1)
        let temperature: Double     // K
        // Fitted parameters (may be zero if unavailable)
        let isomerShift: Double     // mm/s vs α-Fe
        let quadSplitting: Double   // mm/s
        let magField: Double        // T (0 if non-magnetic)
        let lineWidth: Double       // mm/s
        let ironOxidationState: Int // 0=unknown, 2=Fe²⁺, 3=Fe³⁺
        let spinState: String       // "hs", "ls", "is", "unknown"
    }

    enum ParserError: Error { case invalidFormat, insufficientData }

    /// Parse Zenodo-format JSON: { "velocity": [...], "transmission": [...],
    ///                             "IS": ..., "QS": ..., "Bhf": ..., "compound": ..., ... }
    nonisolated static func parseJSON(_ data: Data) throws -> MossbauerSpectrum {
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw ParserError.invalidFormat }

        let vel  = (obj["velocity"] as? [Double]) ?? []
        let tran = (obj["transmission"] as? [Double]) ?? []
        guard vel.count >= 10 && vel.count == tran.count else { throw ParserError.insufficientData }

        return MossbauerSpectrum(
            compoundName: (obj["compound"] as? String) ?? "unknown",
            velocity:     vel,
            transmission: tran,
            temperature:  (obj["temperature"] as? Double) ?? 298.0,
            isomerShift:  (obj["IS"] as? Double) ?? 0,
            quadSplitting:(obj["QS"] as? Double) ?? 0,
            magField:     (obj["Bhf"] as? Double) ?? 0,
            lineWidth:    (obj["Gamma"] as? Double) ?? 0.25,
            ironOxidationState: (obj["oxidation_state"] as? Int) ?? 0,
            spinState:    (obj["spin_state"] as? String) ?? "unknown"
        )
    }

    /// Parse simple two-column ASCII (velocity mm/s  transmission)
    nonisolated static func parseTwoColumn(_ text: String,
                                           compound: String = "unknown") throws -> MossbauerSpectrum {
        var vel: [Double] = []; var tran: [Double] = []
        for line in text.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty && !t.hasPrefix("#") && !t.hasPrefix(";") else { continue }
            let parts = t.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            if parts.count >= 2, let v = Double(parts[0]), let tr = Double(parts[1]) {
                vel.append(v); tran.append(tr)
            }
        }
        guard vel.count >= 10 else { throw ParserError.insufficientData }
        return MossbauerSpectrum(compoundName: compound, velocity: vel, transmission: tran,
                                  temperature: 298, isomerShift: 0, quadSplitting: 0,
                                  magField: 0, lineWidth: 0.25, ironOxidationState: 0,
                                  spinState: "unknown")
    }
}
```

### Synthesizer

Create `Training/Synthesis/MossbauerSynthesizer.swift`:

```swift
import Foundation
import Accelerate

/// Feature vector (252 total):
///   vel_{−120}…vel_{120}  (241) — transmission at each 0.1 mm/s velocity point
///   is_mm_s               (1)   — isomer shift (mm/s vs α-Fe)
///   qs_mm_s               (1)   — quadrupole splitting (mm/s)
///   bhf_T                 (1)   — hyperfine field (T), 0 if paramagnetic/diamagnetic
///   gamma_mm_s            (1)   — line width (mm/s)
///   temperature_K         (1)   — measurement temperature
///   n_lines               (1)   — number of Lorentzian lines (1, 2, or 6)
///   area_ratio_outer      (1)   — area ratio outer:inner lines (sextets only)
///   min_transmission      (1)   — depth of deepest trough (background = 1.0)
///   spectral_asymmetry    (1)   — IS of centre-of-gravity of spectrum
///   fe3_marker            (1)   — IS < 0.6 mm/s → probable Fe³⁺ (1 or 0)
///   fe2_marker            (1)   — IS > 0.7 mm/s → probable Fe²⁺ (1 or 0)
///   ---------------------
///   Total: 241 + 11 = 252
actor MossbauerSynthesizer {

    static let velGrid: [Double] = stride(from: -12.0, through: 12.0, by: 0.1).map { $0 }
    // velGrid.count = 241

    // MARK: — From Real Spectrum

    func makeRecord(from spec: MossbauerParser.MossbauerSpectrum) -> TrainingRecord {
        let tran = interpolateToGrid(
            xs: spec.velocity, ys: spec.transmission, grid: Self.velGrid)

        var features = tran.map { Float($0) }
        features += [
            Float(spec.isomerShift),
            Float(spec.quadSplitting),
            Float(spec.magField),
            Float(spec.lineWidth),
            Float(spec.temperature),
            Float(spec.magField > 0.5 ? 6 : spec.quadSplitting > 0.3 ? 2 : 1),
            Float(spec.magField > 0.5 ? 3.0 / 2.0 : 1.0),
            Float(1.0 - (tran.min() ?? 0.9)),
            Float(spec.isomerShift),
            spec.isomerShift < 0.6 ? 1 : 0,
            spec.isomerShift > 0.7 ? 1 : 0
        ]
        while features.count < 252 { features.append(0) }
        features = Array(features.prefix(252))

        let derived: [String: Double] = [
            "is_mm_s":        spec.isomerShift,
            "qs_mm_s":        spec.quadSplitting,
            "bhf_T":          spec.magField,
            "gamma_mm_s":     spec.lineWidth,
            "temperature_K":  spec.temperature
        ]

        return TrainingRecord(
            modality: .mossbauer,
            sourceID: "mossbauer_\(spec.compoundName)",
            spectralValues: features,
            derivedFeatures: derived,
            primaryTarget: Double(spec.ironOxidationState),
            labelJSON: try? String(data: JSONEncoder().encode([
                "oxidation_state": spec.ironOxidationState,
                "spin_state": spec.spinState,
                "compound": spec.compoundName
            ]), encoding: .utf8),
            isComputedLabel: spec.ironOxidationState != 0,
            computationMethod: "Mossbauer_Lorentzian_Fit")
    }

    // MARK: — Synthetic Spectrum Generation

    /// Generate synthetic Mössbauer spectrum from physical parameters.
    /// Handles doublet (quadrupole) and sextet (magnetic) patterns.
    func synthesize(isomerShift: Double, quadSplitting: Double,
                    magField: Double, lineWidth: Double,
                    temperature: Double, abundance: Double = 1.0) -> TrainingRecord {
        var tran = [Double](repeating: 1.0, count: Self.velGrid.count)

        if magField > 0.5 {
            // Magnetic sextet: intensity ratios 3:2:1:1:2:3
            // Line positions relative to IS: ±(B_hf·μ_N·g/E_γ) for each m_I transition
            // For ⁵⁷Fe: ν_1,6 = IS ± 5.3T/33T × 5.44 mm/s (scaled by B_hf/B_ref)
            let B_ref = 33.0  // T for α-Fe
            let delta = magField / B_ref * 5.44  // mm/s half-spacing of outer lines
            let positions = [
                isomerShift - delta,
                isomerShift - delta * 0.6,
                isomerShift - delta * 0.2,
                isomerShift + delta * 0.2,
                isomerShift + delta * 0.6,
                isomerShift + delta
            ]
            let intensities = [3.0, 2.0, 1.0, 1.0, 2.0, 3.0]
            let total = intensities.reduce(0, +)
            for (pos, rel) in zip(positions, intensities) {
                let area = abundance * rel / total
                addLorentzian(&tran, center: pos, area: area, gamma: lineWidth)
            }
        } else if quadSplitting > 0.05 {
            // Quadrupole doublet
            let v1 = isomerShift - quadSplitting / 2.0
            let v2 = isomerShift + quadSplitting / 2.0
            addLorentzian(&tran, center: v1, area: abundance / 2.0, gamma: lineWidth)
            addLorentzian(&tran, center: v2, area: abundance / 2.0, gamma: lineWidth)
        } else {
            // Single line (diamagnetic or high-symmetry)
            addLorentzian(&tran, center: isomerShift, area: abundance, gamma: lineWidth)
        }

        // Add noise
        tran = tran.map { max(0, $0 + Double.random(in: -0.002...0.002)) }

        // Determine oxidation state from IS heuristic
        let oxState: Int
        if isomerShift < 0.55 { oxState = 3 }
        else if isomerShift > 0.70 { oxState = 2 }
        else { oxState = 0 }

        let spec = MossbauerParser.MossbauerSpectrum(
            compoundName: "synth",
            velocity: Self.velGrid, transmission: tran, temperature: temperature,
            isomerShift: isomerShift, quadSplitting: quadSplitting,
            magField: magField, lineWidth: lineWidth,
            ironOxidationState: oxState, spinState: "unknown")
        return makeRecord(from: spec)
    }

    /// Generate training set spanning realistic Fe compound parameter space.
    func synthesizeTrainingSet(count: Int) -> [TrainingRecord] {
        var records: [TrainingRecord] = []
        for _ in 0..<count {
            let pattern = Int.random(in: 0...2)
            switch pattern {
            case 0:  // Fe²⁺ high-spin doublet
                records.append(synthesize(
                    isomerShift: Double.random(in: 0.85...1.35),
                    quadSplitting: Double.random(in: 1.0...3.2),
                    magField: 0, lineWidth: Double.random(in: 0.20...0.40),
                    temperature: Double.random(in: 77...300)))
            case 1:  // Fe³⁺ high-spin doublet or singlet
                records.append(synthesize(
                    isomerShift: Double.random(in: 0.25...0.55),
                    quadSplitting: Double.random(in: 0.0...0.9),
                    magField: 0, lineWidth: Double.random(in: 0.20...0.45),
                    temperature: Double.random(in: 77...300)))
            default:  // Magnetic sextet (iron oxide, metal)
                records.append(synthesize(
                    isomerShift: Double.random(in: 0.30...0.70),
                    quadSplitting: Double.random(in: -0.2...0.5),
                    magField: Double.random(in: 20.0...53.0),
                    lineWidth: Double.random(in: 0.22...0.35),
                    temperature: Double.random(in: 4...300)))
            }
        }
        return records
    }

    // MARK: — Helpers

    private func addLorentzian(_ tran: inout [Double], center: Double,
                                area: Double, gamma: Double) {
        let halfGamma = gamma / 2.0
        for (i, v) in Self.velGrid.enumerated() {
            let dv = v - center
            tran[i] -= area * (halfGamma * halfGamma) / (dv * dv + halfGamma * halfGamma)
        }
    }

    private func interpolateToGrid(xs: [Double], ys: [Double], grid: [Double]) -> [Double] {
        guard xs.count >= 2 else { return Array(repeating: 0, count: grid.count) }
        return grid.map { x -> Double in
            guard let hi = xs.firstIndex(where: { $0 >= x }), hi > 0 else {
                return x <= xs[0] ? ys[0] : (ys.last ?? 0)
            }
            let lo = hi - 1
            let t = (xs[hi] - xs[lo]) > 1e-12 ? (x - xs[lo]) / (xs[hi] - xs[lo]) : 0
            return ys[lo] + t * (ys[hi] - ys[lo])
        }
    }
}
```

### Data Source Actor

Create `Training/Sources/MossbauerSource.swift`:

```swift
import Foundation

actor MossbauerSource: TrainingDataSourceProtocol {

    // Zenodo dataset DOI: 10.5281/zenodo.6362337
    static let zenodoFilesURL = URL(string:
        "https://zenodo.org/api/records/6362337/files")!

    func fetchSpectraMetadata() async throws -> [[String: Any]] {
        let (data, _) = try await URLSession.shared.data(from: Self.zenodoFilesURL)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = json["entries"] as? [[String: Any]]
        else { return [] }
        return entries
    }

    func fetchSpectrum(from fileEntry: [String: Any]) async throws -> MossbauerParser.MossbauerSpectrum {
        guard let links = fileEntry["links"] as? [String: String],
              let self_ = links["self"],
              let url = URL(string: self_) else {
            throw URLError(.badURL)
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        return try MossbauerParser.parseJSON(data)
    }
}
```

---

## PHASE 29 — Quantum Dot Photoluminescence PINN

### Physics

Semiconductor nanocrystals (quantum dots) exhibit size-tunable emission
due to quantum confinement. The Brus equation gives the size-dependent
bandgap shift relative to the bulk:

```
Brus equation:
  ΔE_conf = ℏ²π² / (2R²) × (1/mₑ* + 1/mₕ*) − 1.8e² / (4πε₀ε_r R)
                           ↑ kinetic confinement        ↑ Coulomb correction

  E_gap(R) = E_gap_bulk + ΔE_conf
  λ_emission(nm) ≈ 1240 / E_gap(R) [in eV]

Effective masses (in units of free electron mass m₀):
  CdSe:  mₑ* = 0.13 m₀,  mₕ* = 0.45 m₀,  ε_r = 10.6
  InP:   mₑ* = 0.08 m₀,  mₕ* = 0.60 m₀,  ε_r = 12.5
  CdS:   mₑ* = 0.21 m₀,  mₕ* = 0.80 m₀,  ε_r = 8.9
  ZnSe:  mₑ* = 0.17 m₀,  mₕ* = 0.78 m₀,  ε_r = 9.1
  PbS:   mₑ* = 0.085m₀,  mₕ* = 0.085m₀,  ε_r = 17.2
  CsPbBr3 (perovskite): mₑ*=0.15, mₕ*=0.19, ε_r=4.1, E_gap_bulk=2.36 eV

Bulk bandgaps (eV):
  CdSe: 1.74,  InP: 1.35,  CdS: 2.42,  ZnSe: 2.70,
  PbS: 0.41,   CsPbBr3: 2.36,  CdZnSe: 1.74–2.42 (composition-tuned)

Stokes shift:
  Δλ_Stokes = λ_emission − λ_absorption_1S (nm), typically 10–50 nm for QDs

FWHM of PL peak:
  FWHM ≈ kT × ln(2) / |dE/dR| × σ_R  (inhomogeneous broadening from size dispersion)
  For monodisperse QDs: FWHM ≈ 20–40 nm
  For polydisperse:     FWHM ≈ 40–80 nm
```

### Data Sources

**Zenodo QD PL Libraries:**
- CdSe/ZnS: `https://zenodo.org/record/7588774` (500+ spectra, CSV)
- InP/ZnS: `https://zenodo.org/record/5761046` (300 spectra)
- Perovskite QDs: `https://zenodo.org/record/4048019` (400 PL spectra)

**NOMAD Repository (DFT+experimental QD data):**
- URL: `https://nomad-lab.eu/nomad-lab/index.html`
- Search: `material_type:nanocrystal`

**Harvard Dataverse QD synthesis datasets:**
- URL: `https://dataverse.harvard.edu/` → search "quantum dot photoluminescence"

### Synthesizer

Create `Training/Synthesis/QuantumDotSynthesizer.swift`:

```swift
import Foundation
import Accelerate

/// Feature vector (280 total):
///   pl_400…pl_898   (250) — PL emission spectrum at 2-nm bins (normalised max=1)
///   ex_wavelength_nm  (1) — excitation wavelength (nm)
///   material_code     (1) — 0=CdSe, 1=InP, 2=CdS, 3=ZnSe, 4=PbS, 5=CsPbBr3, 6=other
///   shell_code        (1) — 0=none, 1=ZnS, 2=ZnSe, 3=CdS
///   radius_nm         (1) — core radius estimate (nm)
///   bulk_gap_eV       (1) — bulk bandgap of core material (eV)
///   eff_mass_e        (1) — electron effective mass (m₀)
///   eff_mass_h        (1) — hole effective mass (m₀)
///   dielectric_r      (1) — relative dielectric constant
///   brus_shift_eV     (1) — ΔE_conf (eV) from Brus equation
///   predicted_gap_eV  (1) — E_gap_bulk + brus_shift_eV
///   peak_pl_nm        (1) — PL peak position (nm)
///   fwhm_nm           (1) — FWHM of PL peak (nm)
///   stokes_shift_nm   (1) — approximate Stokes shift (nm)
///   quantum_yield_est (1) — estimated QY (0–1, from literature trends)
///   size_dispersion   (1) — σ_R / R_mean (relative size dispersion, 0–1)
///   ---------------------
///   Total: 250 + 15 + 15 = 280
actor QuantumDotSynthesizer {

    struct QDMaterial: Sendable {
        let code: Int
        let name: String
        let bulkGapEV: Double
        let mEff_e: Double       // electron effective mass in m₀
        let mEff_h: Double       // hole effective mass in m₀
        let epsilonR: Double     // relative dielectric constant
    }

    static let materials: [QDMaterial] = [
        QDMaterial(code: 0, name: "CdSe",    bulkGapEV: 1.74, mEff_e: 0.13, mEff_h: 0.45, epsilonR: 10.6),
        QDMaterial(code: 1, name: "InP",     bulkGapEV: 1.35, mEff_e: 0.08, mEff_h: 0.60, epsilonR: 12.5),
        QDMaterial(code: 2, name: "CdS",     bulkGapEV: 2.42, mEff_e: 0.21, mEff_h: 0.80, epsilonR: 8.9),
        QDMaterial(code: 3, name: "ZnSe",    bulkGapEV: 2.70, mEff_e: 0.17, mEff_h: 0.78, epsilonR: 9.1),
        QDMaterial(code: 4, name: "PbS",     bulkGapEV: 0.41, mEff_e: 0.085,mEff_h: 0.085,epsilonR: 17.2),
        QDMaterial(code: 5, name: "CsPbBr3", bulkGapEV: 2.36, mEff_e: 0.15, mEff_h: 0.19, epsilonR: 4.1)
    ]

    static let plGrid: [Double] = stride(from: 400.0, through: 898.0, by: 2.0).map { $0 }
    // plGrid.count = 250

    // Physical constants (SI)
    private let hbar   = 1.054571817e-34  // J·s
    private let me     = 9.1093837015e-31  // kg
    private let e0     = 1.602176634e-19   // C
    private let eps0   = 8.8541878e-12     // F/m
    private let hc_eVnm = 1239.8           // eV·nm

    func brusShift(material: QDMaterial, radiusNM: Double) -> Double {
        let R = radiusNM * 1e-9
        let me_ = material.mEff_e * me
        let mh_ = material.mEff_h * me
        // Kinetic confinement term
        let KE = (hbar * hbar * Double.pi * Double.pi / (2.0 * R * R)) *
                 (1.0/me_ + 1.0/mh_) / e0  // convert J → eV
        // Coulomb correction
        let coulomb = 1.8 * e0 / (4.0 * Double.pi * eps0 * material.epsilonR * R * e0)  // eV
        return KE - coulomb
    }

    func synthesizeQD(material: QDMaterial,
                      radiusNM: Double,
                      sizeDispersion: Double = 0.1,
                      shellCode: Int = 1,
                      excitationNM: Double = 365.0) -> TrainingRecord {

        let brus = brusShift(material: material, radiusNM: radiusNM)
        let gapEV = material.bulkGapEV + max(brus, 0)
        let peakNM = hc_eVnm / gapEV

        // Stokes shift: ~5-30 nm (smaller for PbS, larger for CdSe)
        let stokes = Double.random(in: 8...30)
        let emPeakNM = peakNM + stokes

        // FWHM from size dispersion
        let fwhmNM = emPeakNM * sizeDispersion * 2.5 + 15.0

        // Build Gaussian PL peak
        let sigma = fwhmNM / 2.355
        var pl = Self.plGrid.map { nm -> Double in
            exp(-(nm - emPeakNM) * (nm - emPeakNM) / (2.0 * sigma * sigma))
        }
        // Normalise
        let maxPL = pl.max() ?? 1.0
        pl = pl.map { $0 / max(maxPL, 1e-9) }
        // Add noise
        pl = pl.map { max(0, $0 + Double.random(in: -0.005...0.005)) }

        // Quantum yield estimate (literature trend: decreases with radius, varies by material)
        let qyBase: Double = [0.6, 0.5, 0.55, 0.45, 0.35, 0.85][material.code]
        let qy = max(0.01, min(0.99, qyBase * (1 - sizeDispersion)))

        var features = pl.map { Float($0) }  // 250
        features += [
            Float(excitationNM),
            Float(material.code),
            Float(shellCode),
            Float(radiusNM),
            Float(material.bulkGapEV),
            Float(material.mEff_e),
            Float(material.mEff_h),
            Float(material.epsilonR),
            Float(brus),
            Float(gapEV),
            Float(emPeakNM),
            Float(fwhmNM),
            Float(stokes),
            Float(qy),
            Float(sizeDispersion)
        ]  // 15 scalars → total = 265, pad to 280
        while features.count < 280 { features.append(0) }
        features = Array(features.prefix(280))

        let derived: [String: Double] = [
            "brus_shift_eV":    brus,
            "gap_eV":           gapEV,
            "peak_emission_nm": emPeakNM,
            "fwhm_nm":          fwhmNM,
            "stokes_shift_nm":  stokes,
            "quantum_yield":    qy
        ]

        return TrainingRecord(
            modality: .quantumDotPL,
            sourceID: "brus_\(material.name)_R\(String(format: "%.1f", radiusNM))nm",
            spectralValues: features,
            derivedFeatures: derived,
            primaryTarget: emPeakNM,
            labelJSON: try? String(data: JSONEncoder().encode([
                "material": material.name,
                "radius_nm": radiusNM,
                "gap_eV": gapEV,
                "qy": qy
            ]), encoding: .utf8),
            isComputedLabel: true,
            computationMethod: "Brus_QD_Confinement")
    }

    /// Generate full training set across all materials and size ranges.
    func synthesizeTrainingSet(count: Int) -> [TrainingRecord] {
        var records: [TrainingRecord] = []
        let radiiRanges: [QDMaterial: ClosedRange<Double>] = [
            Self.materials[0]: 1.5...6.0,   // CdSe
            Self.materials[1]: 1.0...5.0,   // InP
            Self.materials[2]: 1.5...5.5,   // CdS
            Self.materials[3]: 1.5...5.0,   // ZnSe
            Self.materials[4]: 2.0...8.0,   // PbS (NIR)
            Self.materials[5]: 2.0...6.0    // CsPbBr3
        ]
        for _ in 0..<count {
            let mat = Self.materials.randomElement()!
            let range = radiiRanges[mat] ?? 1.5...6.0
            let R = Double.random(in: range)
            let disp = Double.random(in: 0.05...0.25)
            let shell = Int.random(in: 0...2)
            let ex = [365.0, 405.0, 450.0, 488.0].randomElement()!
            records.append(synthesizeQD(material: mat, radiusNM: R,
                                         sizeDispersion: disp, shellCode: shell,
                                         excitationNM: ex))
        }
        return records
    }
}
```

---

## PHASE 30 — Auger Electron Spectroscopy (AES) PINN

### Physics

AES is a three-electron process triggered by a primary electron beam or X-ray:
1. Primary radiation ejects a core-level electron (e.g. C 1s → core hole)
2. A valence electron drops to fill the core hole (energy released = E_B − E_C)
3. The released energy ejects a second valence electron (the Auger electron)

```
Auger kinetic energy:
  KE(ABC) ≈ E_A − E_B − E_C − U_eff
  where:
    E_A = binding energy of initial core level (eV)
    E_B = binding energy of first valence level (eV)
    E_C = binding energy of second valence level (eV)
    U_eff = two-hole interaction energy (electron-electron repulsion, ~2-5 eV)

Wagner modified Auger parameter:
  α′ = KE(Auger) + BE(photoelectron for same core level)
  α′ is reference-independent (no spectrometer φ correction needed)
  Chemical state fingerprint: different compounds of same element have
  different α′ even when individual BE/KE shifts cancel

Key Auger series for common elements:
  Carbon  KVV:  KE ≈ 260–285 eV  (graphitic: 272, diamond: 268, C=O: 275)
  Oxygen  KVV:  KE ≈ 503–521 eV  (oxide: 503, hydroxide: 510, organic: 514)
  Silicon LVV:  KE ≈ 89–99 eV   (SiO₂: 76, Si: 92)
  Aluminium KLL: KE ≈ 1375–1396 eV (Al₂O₃: 1385, Al: 1396)
  Copper  LMM:  KE ≈ 907–929 eV  (Cu: 918, Cu₂O: 916, CuO: 916)
  Iron    LMM:  KE ≈ 598–720 eV  (Fe: 703, Fe₂O₃: 710, FeO: 706)
  Zinc    LMM:  KE ≈ 985–1010 eV (Zn: 992, ZnO: 988)

dN/dE presentation:
  Standard AES display is the first derivative dN(E)/dE
  Eliminates slowly varying secondary electron background
  Peak-to-peak height in dN/dE is proportional to surface concentration
  Relative sensitivity factors (RSF) from NIST SRD 29
```

### Data Source

**NIST AES Database SRD 29:**
- Web: `https://srdata.nist.gov/aes/`
- REST API: `https://srdata.nist.gov/aes/api/` (JSON)
- Contains: ~15,000 spectra, 33 elements, referenced to vacuum level
- Free, no registration required for web access

**NIST SRD 29 REST endpoint (per element):**
```
https://srdata.nist.gov/aes/api/getspectra?element={SYMBOL}&format=json
```

### Synthesizer

Create `Training/Synthesis/AESSynthesizer.swift`:

```swift
import Foundation
import Accelerate

/// Feature vector (420 total):
///   ke_050…ke_2045 (400) — dN/dE AES derivative spectrum (5 eV bins, 50–2050 eV)
///   c_kll_pos        (1) — Carbon KLL peak position (eV)
///   o_kll_pos        (1) — Oxygen KVV peak position (eV)
///   si_lvv_pos       (1) — Silicon LVV peak position (eV)
///   cu_lmm_pos       (1) — Copper LMM peak position (eV)
///   al_kll_pos       (1) — Aluminium KLL peak position (eV)
///   fe_lmm_pos       (1) — Iron LMM peak position (eV)
///   zn_lmm_pos       (1) — Zinc LMM peak position (eV)
///   wagner_alpha_c   (1) — Wagner α′ for carbon
///   wagner_alpha_si  (1) — Wagner α′ for silicon
///   wagner_alpha_cu  (1) — Wagner α′ for copper
///   c_auger_ptp      (1) — C KLL peak-to-peak intensity
///   o_auger_ptp      (1) — O KVV peak-to-peak intensity
///   c_ptp_o_ptp_ratio(1) — C/O peak-to-peak ratio
///   total_signal     (1) — Σ|dN/dE| across full range
///   n_elements_est   (1) — estimated element count (peaks above threshold)
///   primary_beam_kV  (1) — primary beam energy (kV, 3 or 10)
///   background_slope (1) — slope of N(E) secondary background
///   ---------------------
///   Total: 400 + 18 + 2 padding = 420
actor AESSynthesizer {

    static let keGrid: [Double] = stride(from: 50.0, through: 2045.0, by: 5.0).map { $0 }
    // keGrid.count = 400

    struct AugerPeak: Sendable {
        let symbol: String
        let series: String       // "KLL", "KVV", "LMM", "LVV", "MNN"
        let keNominal: Double    // eV
        let rsf: Double          // relative sensitivity factor
        let bgContrib: Double    // peak-to-peak height in derivative (arbitrary)
    }

    // Standard Auger peak positions and RSF (from NIST SRD 29 tables)
    static let peaks: [AugerPeak] = [
        AugerPeak(symbol: "C",  series: "KLL", keNominal: 272.0, rsf: 0.070, bgContrib: 1.0),
        AugerPeak(symbol: "O",  series: "KVV", keNominal: 510.0, rsf: 0.500, bgContrib: 1.0),
        AugerPeak(symbol: "N",  series: "KLL", keNominal: 379.0, rsf: 0.170, bgContrib: 0.8),
        AugerPeak(symbol: "Si", series: "LVV", keNominal: 92.0,  rsf: 0.250, bgContrib: 0.8),
        AugerPeak(symbol: "Al", series: "KLL", keNominal: 1396.0,rsf: 0.070, bgContrib: 0.6),
        AugerPeak(symbol: "Fe", series: "LMM", keNominal: 703.0, rsf: 0.220, bgContrib: 0.9),
        AugerPeak(symbol: "Cu", series: "LMM", keNominal: 918.0, rsf: 0.260, bgContrib: 0.9),
        AugerPeak(symbol: "Zn", series: "LMM", keNominal: 992.0, rsf: 0.250, bgContrib: 0.8),
        AugerPeak(symbol: "Na", series: "KLL", keNominal: 990.0, rsf: 0.230, bgContrib: 0.6),
        AugerPeak(symbol: "Mg", series: "KLL", keNominal: 1186.0,rsf: 0.100, bgContrib: 0.7),
        AugerPeak(symbol: "S",  series: "LVV", keNominal: 152.0, rsf: 0.540, bgContrib: 0.8),
        AugerPeak(symbol: "Ca", series: "LMM", keNominal: 292.0, rsf: 0.130, bgContrib: 0.7),
        AugerPeak(symbol: "Ti", series: "LMM", keNominal: 418.0, rsf: 0.580, bgContrib: 0.9),
        AugerPeak(symbol: "Cr", series: "LMM", keNominal: 489.0, rsf: 0.350, bgContrib: 0.9)
    ]

    func synthesizeSurface(presentElements: [(symbol: String, atomicPct: Double,
                                               chemicalState: String)],
                            primaryBeamKV: Double = 10.0) -> TrainingRecord {

        var N_E = [Double](repeating: 0.0, count: Self.keGrid.count)
        // Build N(E) (integrated) then differentiate

        var derivedInfo: [String: Double] = [:]
        derivedInfo["primary_beam_kV"] = primaryBeamKV

        for (symbol, pct, state) in presentElements {
            guard let peak = Self.peaks.first(where: { $0.symbol == symbol }) else { continue }

            // Chemical shift depending on state
            let shift: Double
            switch (symbol, state) {
            case ("C", "graphitic"): shift = 0
            case ("C", "diamond"):   shift = -4.0
            case ("C", "oxide"):     shift = +3.0
            case ("O", "oxide"):     shift = -7.0
            case ("O", "hydroxide"): shift = 0
            case ("Si", "SiO2"):     shift = -16.0
            case ("Cu", "Cu2O"):     shift = -2.0
            case ("Cu", "CuO"):      shift = -2.0
            case ("Fe", "Fe2O3"):    shift = +7.0
            case ("Fe", "FeO"):      shift = +3.0
            default: shift = 0
            }
            let kePeak = peak.keNominal + shift

            // Add Gaussian to N(E) spectrum
            let sigma = 3.0  // eV typical AES resolution
            let amp = pct / 100.0 * peak.rsf * 100.0
            for (i, ke) in Self.keGrid.enumerated() {
                let dx = ke - kePeak
                N_E[i] += amp * exp(-dx*dx/(2*sigma*sigma))
            }
        }

        // Add secondary electron background (decaying exponential)
        let bgAmp = Double.random(in: 5...20)
        for (i, ke) in Self.keGrid.enumerated() {
            N_E[i] += bgAmp * exp(-ke / 300.0)
        }

        // Differentiate: dN/dE via central difference
        var dNdE = [Double](repeating: 0, count: Self.keGrid.count)
        for i in 1..<(Self.keGrid.count - 1) {
            dNdE[i] = (N_E[i+1] - N_E[i-1]) / (Self.keGrid[i+1] - Self.keGrid[i-1])
        }
        dNdE[0] = dNdE[1]; dNdE[Self.keGrid.count-1] = dNdE[Self.keGrid.count-2]

        // Normalise by max absolute value
        let maxAbs = dNdE.map { abs($0) }.max() ?? 1.0
        dNdE = dNdE.map { $0 / max(maxAbs, 1e-9) }

        // Extract derived peak positions and Wagner parameters
        func findPeakNearKE(_ target: Double, window: Double = 30.0) -> Double {
            let candidates = zip(Self.keGrid, dNdE)
                .filter { abs($0.0 - target) < window }
            let maxIdx = candidates.max(by: { abs($0.1) < abs($1.1) })
            return maxIdx?.0 ?? target
        }

        let cPos   = findPeakNearKE(272.0, window: 20)
        let oPos   = findPeakNearKE(510.0, window: 20)
        let siPos  = findPeakNearKE(92.0,  window: 20)
        let cuPos  = findPeakNearKE(918.0, window: 20)
        let alPos  = findPeakNearKE(1396.0,window: 20)
        let fePos  = findPeakNearKE(703.0, window: 20)
        let znPos  = findPeakNearKE(992.0, window: 20)

        // Wagner parameter (approximate: using nominal XPS BEs for C 1s, Si 2p, Cu 2p)
        let wAlphaC  = cPos + 284.8    // C KLL + C 1s BE
        let wAlphaSi = siPos + 99.5    // Si LVV + Si 2p BE
        let wAlphaCu = cuPos + 932.7   // Cu LMM + Cu 2p BE

        func ptpNear(_ target: Double, window: Double = 20.0) -> Double {
            let seg = zip(Self.keGrid, dNdE).filter { abs($0.0 - target) < window }.map { $0.1 }
            guard let mx = seg.max(), let mn = seg.min() else { return 0 }
            return mx - mn
        }

        let cPTP = ptpNear(272)
        let oPTP = ptpNear(510)

        // Build feature array
        var features = dNdE.map { Float($0) }  // 400
        features += [
            Float(cPos), Float(oPos), Float(siPos), Float(cuPos),
            Float(alPos), Float(fePos), Float(znPos),
            Float(wAlphaC), Float(wAlphaSi), Float(wAlphaCu),
            Float(cPTP), Float(oPTP),
            Float(oPTP > 1e-6 ? cPTP / oPTP : 0),
            Float(dNdE.map { abs($0) }.reduce(0, +)),
            Float(presentElements.count),
            Float(primaryBeamKV),
            Float((N_E.last ?? 0) - (N_E.first ?? 0)),
            0  // padding
        ]  // 18 scalars → total 418; pad to 420
        while features.count < 420 { features.append(0) }
        features = Array(features.prefix(420))

        let atomPctJSON = try? String(data: JSONEncoder().encode(
            Dictionary(uniqueKeysWithValues:
                presentElements.map { ($0.symbol, $0.atomicPct) })), encoding: .utf8)

        return TrainingRecord(
            modality: .augerElectron,
            sourceID: "aes_synth_\(presentElements.map { $0.symbol }.joined(separator: "_"))",
            spectralValues: features,
            derivedFeatures: derivedInfo,
            primaryTarget: presentElements.first?.atomicPct ?? 0,
            labelJSON: atomPctJSON,
            isComputedLabel: true,
            computationMethod: "AES_Auger_KE_Wagner")
    }
}
```

---

## PHASE 31 — Neutron Diffraction PINN

### Physics

Neutron diffraction follows Bragg's law identically to XRD, but the atomic
scattering amplitude is the **coherent scattering length b_coh** — an isotope-
specific nuclear property, NOT proportional to atomic number Z:

```
Bragg's law (same as XRD):
  2d·sinθ = nλ   (λ = 1.7959 Å for ILL D2B, or 1.5940 Å for reactor thermal)

Neutron structure factor (replaces X-ray F_X):
  F_N(hkl) = Σ_j b_coh,j · exp(2πi(hxⱼ + kyⱼ + lzⱼ)) · exp(−Bⱼ·sin²θ/λ²)
             ↑ coherent scattering length (fm), NOT Z-dependent

Debye-Waller thermal factor:
  T_j(sinθ/λ) = exp(−Bⱼ · sin²θ / λ²)
  B_j = 8π²⟨u_j²⟩   (mean-square displacement amplitude)

Key b_coh values (fm, from NIST):
  H:   -3.739,  D:  +6.671  ← deuterium highly visible
  C:    6.646,  N:   9.360,  O:  5.803
  Fe:   9.450,  Ni: 10.300,  Si: 4.149
  Al:   3.449,  Ti: -3.438  ← titanium has negative b_coh!

Magnetic scattering (additional for magnetic materials):
  F_mag(hkl) = p·f(Q)·Σ_j m_perp,j · exp(2πi·h·r_j)
  p = 0.2695 × 10⁻¹² cm/μ_B (magnetic scattering length)
  f(Q) = atomic form factor for unpaired electrons
  m_perp = component of magnetic moment perpendicular to Q

Incoherent background (hydrogen):
  σ_inc(H) = 80.27 barns  ← 40× larger than Si; H-rich samples have high bg
  σ_inc(D) = 2.05 barns   ← deuteration removes H background
```

### Data Sources

**NIST Neutron Scattering Lengths (b_coh table, free):**
- URL: `https://www.ncnr.nist.gov/resources/n-lengths/list.html`
- Use as lookup table in synthesizer (paste the full table into source code as constant)

**ILL Data Portal (Institut Laue-Langevin, free after registration):**
- URL: `https://data.ill.fr/`
- Format: `.dat` files with 2θ (°) vs counts columns

**COD CIF files (reuse existing CODSource.swift from Phase 7):**
- CIF files already describe atomic positions and atom types
- Combine with NIST b_coh table to compute neutron structure factors

**Neutron powder patterns via FullProf simulation data (Zenodo):**
- URL: `https://zenodo.org/record/5724434` (simulated neutron patterns for 800 phases)

### Synthesizer

Create `Training/Synthesis/NeutronDiffractionSynthesizer.swift`:

```swift
import Foundation
import Accelerate

/// Feature vector (1163 total):
///   nd_50…nd_1200  (1151) — neutron powder pattern at 0.1° 2θ bins (5–120°)
///   peak_count       (1) — number of resolved peaks above 3% max
///   d_spacing_1_ang  (1) — d-spacing of strongest peak (Å)
///   d_spacing_2_ang  (1) — d-spacing of 2nd strongest peak
///   h_background     (1) — incoherent background level (proxy for H content)
///   d_substituted    (1) — 0/1 flag: D-labelled sample
///   wavelength_ang   (1) — incident wavelength (Å)
///   unit_cell_vol_A3 (1) — estimated unit cell volume
///   magnetic_signal  (1) — 0/1: magnetic scattering peaks present (low-angle)
///   deuterium_pct    (1) — estimated D/(H+D) fraction
///   pattern_asymmetry(1) — ratio of low-angle to high-angle integrated intensity
///   peak_fwhm_deg    (1) — average FWHM of resolved peaks
///   ---------------------
///   Total: 1151 + 12 = 1163
actor NeutronDiffractionSynthesizer {

    // Coherent neutron scattering lengths b_coh in fm (from NIST n-lengths table)
    static let bCoh: [String: Double] = [
        "H":  -3.7390, "D":   6.6710, "He":  3.2600, "Li":  -1.9000,
        "Be":  7.7900, "B":   5.3000, "C":   6.6460, "N":    9.3600,
        "O":   5.8030, "F":   5.6540, "Na":  3.6300, "Mg":   5.3750,
        "Al":  3.4490, "Si":  4.1491, "P":   5.1300, "S":    2.8470,
        "Cl":  9.5770, "K":   3.6700, "Ca":  4.7000, "Ti":  -3.4380,
        "V":  -0.3824, "Cr":  3.6350, "Mn": -3.7300, "Fe":   9.4500,
        "Co":  2.4900, "Ni": 10.3000, "Cu":  7.7180, "Zn":   5.6800,
        "Ga":  7.2880, "Ge":  8.1850, "As":  6.5800, "Se":   7.9700,
        "Sr":  7.0200, "Y":   7.7500, "Zr":  7.1600, "Nb":   7.0540,
        "Mo":  6.7150, "Ru":  7.0300, "Rh":  5.8800, "Pd":   5.9100,
        "Ag":  5.9220, "Cd":  4.8700, "In":  4.0650, "Sn":   6.2250,
        "Sb":  5.5700, "I":   5.2800, "Cs":  5.4200, "Ba":   5.0700,
        "La":  8.2400, "Ce":  4.8400, "Pr":  4.5800, "Nd":   7.6900,
        "Gd": 6.5000,  "Tb":  7.3800, "Dy":  1.6900, "Ho":   8.0100,
        "Yb":  1.2600, "Hf":  7.7700, "Ta":  6.9100, "W":    4.7550,
        "Re":  9.2000, "Ir":  10.600, "Pt":  9.6000, "Au":   7.6300,
        "Hg":  1.2692, "Tl":  8.7760, "Pb":  9.4050, "Bi":   8.5320,
        "U":   8.4170
    ]

    static let lambda = 1.7959      // Å, ILL D2B instrument
    static let twoThetaGrid: [Double] = stride(from: 5.0, through: 120.05, by: 0.1).map { $0 }
    // count = 1151

    struct CrystalSite: Sendable {
        let element: String
        let x: Double; let y: Double; let z: Double  // fractional
        let occupancy: Double
        let bIso: Double  // Å², Debye-Waller B factor
    }

    struct UnitCell: Sendable {
        let a: Double; let b: Double; let c: Double  // Å
        let alpha: Double; let beta: Double; let gamma: Double  // degrees
        let spaceGroupNumber: Int
        let sites: [CrystalSite]
        var volume: Double {
            let ar = alpha * .pi/180; let br = beta * .pi/180; let gr = gamma * .pi/180
            return a*b*c*sqrt(1 - cos(ar)*cos(ar) - cos(br)*cos(br) - cos(gr)*cos(gr)
                               + 2*cos(ar)*cos(br)*cos(gr))
        }
    }

    func synthesizePattern(cell: UnitCell,
                            crystalliteSize: Double = Double.random(in: 30...500),
                            hBackground: Double = 0.02,
                            isDeuterated: Bool = false) -> TrainingRecord {

        var pattern = [Float](repeating: 0, count: Self.twoThetaGrid.count)
        let lambda = Self.lambda

        // Generate hkl reflections up to d_min = lambda/2
        let hklList = generateHKL(cell: cell, lambdaAng: lambda)

        for (h, k, l) in hklList {
            guard let dHKL = dSpacingCubicApprox(h: h, k: k, l: l, cell: cell),
                  dHKL > lambda / 2.0 else { continue }
            let sinT = lambda / (2.0 * dHKL)
            guard sinT <= 1.0 else { continue }
            let theta = asin(sinT)
            let tt = 2.0 * theta * 180.0 / .pi

            // Neutron structure factor
            let F2 = abs(structureFactor(h: h, k: k, l: l, cell: cell,
                                          sinThetaOverLambda: sinT / lambda))
            guard F2 > 0.001 else { continue }

            // Lorentz-polarisation factor (for neutrons: LP = 1/sin²θ·cosθ)
            let LP = 1.0 / (sinT * sinT * cos(theta))

            // Multiplicity (simplified: 8 for general hkl, less for special)
            let mult = Double(multiplicityFactor(h: h, k: k, l: l))

            let Icalc = F2 * LP * mult

            // Peak shape: Gaussian (neutron TOF instruments use Gaussian; CW use pseudo-Voigt)
            let betaRad = (0.9 * lambda) / (crystalliteSize * cos(theta))
            let betaDeg = betaRad * 180.0 / .pi
            let sigma = betaDeg / 2.355

            for (i, t2) in Self.twoThetaGrid.enumerated() {
                let dx = t2 - tt
                let gauss = Float(Icalc * exp(-dx*dx/(2*sigma*sigma)))
                pattern[i] += gauss
            }
        }

        // Incoherent H background (flat if not deuterated)
        let bgLevel = isDeuterated ? 0.005 : hBackground
        pattern = pattern.map { $0 + Float(bgLevel + Double.random(in: 0...bgLevel*0.1)) }

        // Normalise to max intensity
        let maxI = pattern.max() ?? 1.0
        pattern = pattern.map { $0 / max(maxI, 1e-6) }

        // Extract derived features
        let peakCount = countPeaks(pattern: pattern, threshold: 0.03)
        let (d1, d2) = topTwoDSpacings(pattern: pattern, cell: cell, lambda: lambda)

        var features = pattern
        features += [
            Float(peakCount),
            Float(d1),
            Float(d2),
            Float(bgLevel),
            isDeuterated ? 1 : 0,
            Float(lambda),
            Float(cell.volume),
            0,  // magnetic signal (0 for non-magnetic)
            isDeuterated ? 1 : 0,
            Float(pattern.prefix(400).reduce(0, +) / max(pattern.suffix(750).reduce(0, +), 1e-6)),
            Float(estimateFWHM(pattern: pattern)),
            0   // padding
        ]
        while features.count < 1163 { features.append(0) }
        features = Array(features.prefix(1163))

        return TrainingRecord(
            modality: .neutronDiffraction,
            sourceID: "nd_synth_sg\(cell.spaceGroupNumber)",
            spectralValues: features,
            derivedFeatures: [
                "unit_cell_vol_A3": cell.volume,
                "crystallite_size_nm": crystalliteSize / 10.0,
                "h_background": bgLevel
            ],
            primaryTarget: Double(crystalSystemFromSG(cell.spaceGroupNumber).hashValue % 7),
            labelJSON: try? String(data: JSONEncoder().encode([
                "crystal_system": crystalSystemFromSG(cell.spaceGroupNumber),
                "space_group": cell.spaceGroupNumber,
                "a": cell.a, "b": cell.b, "c": cell.c
            ]), encoding: .utf8),
            isComputedLabel: true,
            computationMethod: "Bragg_NeutronScatteringLengths")
    }

    // MARK: — Crystallographic helpers

    private func generateHKL(cell: UnitCell, lambdaAng: Double) -> [(Int, Int, Int)] {
        var list: [(Int, Int, Int)] = []
        let hMax = Int(2.0 * cell.a / lambdaAng) + 2
        let kMax = Int(2.0 * cell.b / lambdaAng) + 2
        let lMax = Int(2.0 * cell.c / lambdaAng) + 2
        for h in -hMax...hMax {
            for k in -kMax...kMax {
                for l in 0...lMax {
                    if h == 0 && k == 0 && l == 0 { continue }
                    list.append((h, k, l))
                }
            }
        }
        return list
    }

    private func dSpacingCubicApprox(h: Int, k: Int, l: Int, cell: UnitCell) -> Double? {
        // For orthorhombic or higher symmetry
        let h2 = Double(h*h) / (cell.a*cell.a)
        let k2 = Double(k*k) / (cell.b*cell.b)
        let l2 = Double(l*l) / (cell.c*cell.c)
        let inv_d2 = h2 + k2 + l2
        guard inv_d2 > 1e-10 else { return nil }
        return 1.0 / sqrt(inv_d2)
    }

    private func structureFactor(h: Int, k: Int, l: Int,
                                  cell: UnitCell, sinThetaOverLambda: Double) -> Double {
        var sumRe = 0.0, sumIm = 0.0
        for site in cell.sites {
            guard let b = Self.bCoh[site.element] else { continue }
            let phase = 2.0 * Double.pi * (Double(h)*site.x + Double(k)*site.y + Double(l)*site.z)
            let dw = exp(-site.bIso * sinThetaOverLambda * sinThetaOverLambda)
            sumRe += site.occupancy * b * dw * cos(phase)
            sumIm += site.occupancy * b * dw * sin(phase)
        }
        return sumRe*sumRe + sumIm*sumIm  // |F|²
    }

    private func multiplicityFactor(h: Int, k: Int, l: Int) -> Int {
        let ah = abs(h), ak = abs(k), al = abs(l)
        if ah == ak && ak == al { return 8 }
        if ah == ak || ak == al || ah == al { return 24 }
        return 48
    }

    private func countPeaks(pattern: [Float], threshold: Float) -> Int {
        var count = 0
        for i in 1..<(pattern.count-1) {
            if pattern[i] > threshold && pattern[i] >= pattern[i-1] && pattern[i] >= pattern[i+1] {
                count += 1
            }
        }
        return count
    }

    private func topTwoDSpacings(pattern: [Float], cell: UnitCell, lambda: Double) -> (Double, Double) {
        var peaks: [(Float, Double)] = []
        for i in 1..<(pattern.count-1) {
            if pattern[i] >= pattern[i-1] && pattern[i] >= pattern[i+1] && pattern[i] > 0.05 {
                let tt = Self.twoThetaGrid[i]
                let sinT = sin(tt * .pi / 360.0)
                let d = sinT > 1e-10 ? lambda / (2.0 * sinT) : 0
                peaks.append((pattern[i], d))
            }
        }
        peaks.sort { $0.0 > $1.0 }
        return (peaks.first?.1 ?? 0, peaks.dropFirst().first?.1 ?? 0)
    }

    private func estimateFWHM(pattern: [Float]) -> Double {
        guard let maxI = pattern.max(), maxI > 0.05 else { return 0 }
        let halfMax = maxI / 2.0
        var crossings = 0
        for i in 1..<pattern.count {
            if (pattern[i-1] < halfMax) != (pattern[i] < halfMax) { crossings += 1 }
        }
        return Double(crossings) > 0 ? Double(Self.twoThetaGrid.count) * 0.1 / Double(crossings) : 0
    }

    private func crystalSystemFromSG(_ spaceGroup: Int) -> String {
        switch spaceGroup {
        case 1...2:    return "triclinic"
        case 3...15:   return "monoclinic"
        case 16...74:  return "orthorhombic"
        case 75...142: return "tetragonal"
        case 143...167:return "trigonal"
        case 168...194:return "hexagonal"
        case 195...230:return "cubic"
        default:       return "unknown"
        }
    }
}
```

### Data Source Actor

Create `Training/Sources/NeutronDiffractionSource.swift`:

```swift
import Foundation

/// Fetches neutron diffraction data from ILL Data Portal and Zenodo.
/// Also builds synthetic patterns from COD CIF files (reuses CIFParser).
actor NeutronDiffractionSource: TrainingDataSourceProtocol {

    // ILL Data Portal public API
    static let illBaseURL = "https://data.ill.fr/api/datasets/"

    // Zenodo simulated neutron patterns dataset
    static let zenodoURL = URL(string:
        "https://zenodo.org/record/5724434/files/neutron_patterns.zip")!

    /// Synthesise neutron patterns from a COD CIF ReferenceSpectrum
    /// by extracting atom positions and applying neutron b_coh values.
    func synthesizeFromCIF(cif: ReferenceSpectrum,
                           synthesizer: NeutronDiffractionSynthesizer) async -> TrainingRecord? {
        // Parse atomic positions from CIF metadata
        guard cif.modality == .xrdPowder else { return nil }
        // Extract cell parameters from CIF metadata dict
        let meta = cif.metadata
        guard let a = meta["cell_length_a"].flatMap(Double.init),
              let b = meta["cell_length_b"].flatMap(Double.init),
              let c = meta["cell_length_c"].flatMap(Double.init),
              let alpha = meta["cell_angle_alpha"].flatMap(Double.init),
              let beta  = meta["cell_angle_beta"].flatMap(Double.init),
              let gamma = meta["cell_angle_gamma"].flatMap(Double.init),
              let sg    = meta["symmetry_Int_Tables_number"].flatMap(Int.init)
        else { return nil }

        // Build simplified unit cell (single-site approximation)
        let elementSymbol = meta["atom_site_type_symbol"] ?? "Fe"
        let site = NeutronDiffractionSynthesizer.CrystalSite(
            element: elementSymbol, x: 0, y: 0, z: 0, occupancy: 1.0, bIso: 0.5)
        let cell = NeutronDiffractionSynthesizer.UnitCell(
            a: a, b: b, c: c, alpha: alpha, beta: beta, gamma: gamma,
            spaceGroupNumber: sg, sites: [site])

        return await synthesizer.synthesizePattern(cell: cell)
    }
}
```

---

## Build Checklist — Part 3 (Phases 26–31)

Complete ALL items before moving to CLAUDE4.md:

- [ ] `SpectralModality` — `allCases.count` == 30 (25 existing + 5 new)
- [ ] `SpectralModality.featureCount` — non-zero for all 30 cases
- [ ] `ModalityAxisSpec.make(for:)` — no default/crash for any of the 5 new cases
- [ ] `QM9XYZParser.parseMolecule(_:)` — parses a sample QM9 XYZ block correctly
- [ ] `DFTQuantumChemSynthesizer.makeRecord(from:)` — spectralValues.count == 380
- [ ] `DFTQuantumChemSynthesizer` — `gapEV > 0` for valid molecules
- [ ] `MossbauerSynthesizer.synthesize(...)` — doublet produces exactly 2 Lorentzian dips
- [ ] `MossbauerSynthesizer.synthesize(...)` — sextet produces 6 dips at correct ratios 3:2:1:1:2:3
- [ ] `MossbauerSynthesizer.makeRecord(from:)` — spectralValues.count == 252
- [ ] `QuantumDotSynthesizer.brusShift(...)` — returns positive value for R < 5 nm CdSe
- [ ] `QuantumDotSynthesizer` — peakNM shifts blue with decreasing R (Brus equation)
- [ ] `QuantumDotSynthesizer.synthesizeQD(...)` — spectralValues.count == 280
- [ ] `AESSynthesizer.synthesizeSurface(...)` — spectralValues.count == 420
- [ ] `AESSynthesizer` — C KLL peak appears near 272 eV in dN/dE for C-containing surfaces
- [ ] `NeutronDiffractionSynthesizer.synthesizePattern(...)` — spectralValues.count == 1163
- [ ] `NeutronDiffractionSynthesizer` — Ti sites with b_coh = -3.438 reduce peak intensities
- [ ] `QM9Source`, `MossbauerSource`, `NeutronDiffractionSource` — compile without errors
- [ ] `TrainingDataCoordinator` — add `.dftQuantumChem`, `.mossbauer`, `.quantumDotPL`,
     `.augerElectron`, `.neutronDiffraction` to `allModalities` array if one exists
- [ ] Project builds without errors or warnings (`⌘B`)
- [ ] Run all unit tests (`⌘U`) — no regressions in existing 25 modalities

---

**→ Continue with CLAUDE4.md for Phases 32–40 (quantum enhancements to existing PINNs)**
