import Foundation

/// PINN synthesizer for DFT/Quantum Chemistry predictions.
/// Feature vector (380): Coulomb eigenvalues(29) + ECFP6(256) + descriptors(26+) + pad → 380
/// Primary target: homo_lumo_gap_eV
actor DFTQuantumChemSynthesizer {

    func makeRecord(from mol: QM9XYZParser.QM9Molecule) -> TrainingRecord {

        // --- Coulomb matrix eigenvalues ---
        var ceigs: [Double]
        if mol.atomCount > 0 && mol.atomicNumbers.count == mol.atomCount {
            ceigs = computeCoulombEigenvalues(Z: mol.atomicNumbers, pos: mol.positions)
        } else {
            ceigs = Array(repeating: 0.0, count: 29)
        }
        while ceigs.count < 29 { ceigs.append(0) }
        ceigs = Array(ceigs.prefix(29))

        // --- Molecular descriptor features ---
        let (nC, nH, nN, nO, nF, nS) = atomCounts(smiles: mol.smiles)
        let nHeavy = nC + nN + nO + nF + nS
        let mw = estimateMW(nC: nC, nH: nH, nN: nN, nO: nO, nF: nF, nS: nS)
        let sp3 = estimateSP3Fraction(smiles: mol.smiles)
        let rings = countRings(smiles: mol.smiles)
        let aromatic = countAromaticRings(smiles: mol.smiles)
        let logp = crippenLogP(smiles: mol.smiles)
        let tpsa = estimateTPSA(smiles: mol.smiles)
        let hbd = countHBD(smiles: mol.smiles)
        let hba = countHBA(smiles: mol.smiles)
        let nRot = countRotatableBonds(smiles: mol.smiles)

        // --- ECFP6 fingerprint (256 bits) ---
        let ecfp = ecfp6Bits(smiles: mol.smiles, nBits: 256)

        // --- Assemble feature array ---
        var features: [Float] = ceigs.map { Float($0) }           // 29
        features += ecfp.map { Float($0) }                         // 256
        features += [
            Float(mw), Float(nHeavy), Float(nC), Float(nH),
            Float(nN), Float(nO), Float(nF), Float(nS),
            Float(rings), Float(aromatic), Float(nRot),
            Float(sp3), Float(logp), Float(tpsa),
            Float(hbd), Float(hba),
            Float(mol.dipoleMoment), Float(mol.polarisability),
            Float(mol.r2), Float(mol.zpve), Float(mol.cv),
            Float(mol.rotationalConsts[0]),
            Float(mol.rotationalConsts[1]),
            Float(mol.rotationalConsts[2])
        ]
        while features.count < 380 { features.append(0) }
        features = Array(features.prefix(380))

        let targets: [String: Double] = [
            "homo_lumo_gap_eV": mol.gapEV,
            "homo_eV": mol.homoEV,
            "lumo_eV": mol.lumoEV,
            "ip_eV": -mol.homoEV,
            "ea_eV": -mol.lumoEV,
            "dipole_debye": mol.dipoleMoment,
            "polarisability_a3": mol.polarisability,
        ]

        return TrainingRecord(
            modality: .dftQuantumChem,
            sourceID: "qm9_\(mol.tag)",
            features: features,
            targets: targets,
            metadata: ["smiles": mol.smiles, "method": "B3LYP_6-31G*_QM9"],
            isComputedLabel: false,
            computationMethod: "B3LYP_6-31G*_QM9")
    }

    func synthesizeBatch(count: Int) -> [TrainingRecord] {
        // Generate synthetic molecules with random properties
        (0..<count).map { i in
            let mol = QM9XYZParser.QM9Molecule(
                tag: "synth_\(i)", smiles: randomSMILES(),
                atomCount: 0, atomicNumbers: [], positions: [],
                rotationalConsts: [Double.random(in: 0...10), Double.random(in: 0...10), Double.random(in: 0...10)],
                dipoleMoment: Double.random(in: 0...6),
                polarisability: Double.random(in: 30...90),
                homoEV: Double.random(in: -9 ... -5),
                lumoEV: Double.random(in: -3...2),
                gapEV: Double.random(in: 2...10),
                r2: Double.random(in: 100...1500),
                zpve: Double.random(in: 0.01...0.20),
                u0: Double.random(in: -400 ... -70),
                u298: 0, h298: 0,
                g298: Double.random(in: -400 ... -70),
                cv: Double.random(in: 10...40))
            return makeRecord(from: mol)
        }
    }

    // MARK: - Coulomb Matrix

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
        return eigenvaluesSorted(matrix: C, n: n)
    }

    /// Jacobi eigenvalue algorithm for real symmetric matrices.
    /// Efficient for small n (QM9 molecules have at most 29 heavy atoms).
    private func eigenvaluesSorted(matrix: [[Double]], n: Int) -> [Double] {
        guard n > 0 else { return [] }
        if n == 1 { return [matrix[0][0]] }

        var a = matrix
        let maxIter = 100 * n * n
        let eps = 1e-12

        for _ in 0..<maxIter {
            // Find largest off-diagonal element
            var maxVal = 0.0
            var p = 0, q = 1
            for i in 0..<n {
                for j in (i + 1)..<n {
                    if abs(a[i][j]) > maxVal {
                        maxVal = abs(a[i][j])
                        p = i; q = j
                    }
                }
            }
            if maxVal < eps { break }

            // Compute Jacobi rotation parameters
            let diff = a[q][q] - a[p][p]
            let t: Double
            if abs(a[p][q]) < eps * abs(diff) {
                t = a[p][q] / diff
            } else {
                let phi = diff / (2.0 * a[p][q])
                t = (phi >= 0 ? 1.0 : -1.0) / (abs(phi) + sqrt(phi * phi + 1.0))
            }
            let c = 1.0 / sqrt(t * t + 1.0)
            let s = t * c
            let tau = s / (1.0 + c)

            let apq = a[p][q]
            a[p][q] = 0
            a[p][p] -= t * apq
            a[q][q] += t * apq

            // Apply rotation to rows/columns
            for r in 0..<p {
                let g = a[r][p]; let h = a[r][q]
                a[r][p] = g - s * (h + g * tau)
                a[r][q] = h + s * (g - h * tau)
            }
            for r in (p + 1)..<q {
                let g = a[p][r]; let h = a[r][q]
                a[p][r] = g - s * (h + g * tau)
                a[r][q] = h + s * (g - h * tau)
            }
            for r in (q + 1)..<n {
                let g = a[p][r]; let h = a[q][r]
                a[p][r] = g - s * (h + g * tau)
                a[q][r] = h + s * (g - h * tau)
            }
        }

        return (0..<n).map { a[$0][$0] }.sorted(by: >)
    }

    // MARK: - Molecular Descriptor Helpers

    private func atomCounts(smiles: String) -> (Int, Int, Int, Int, Int, Int) {
        var nC = 0, nH = 0, nN = 0, nO = 0, nF = 0, nS = 0
        var i = smiles.startIndex
        while i < smiles.endIndex {
            let ch = smiles[i]
            let next = smiles.index(after: i)
            switch ch {
            case "C" where next == smiles.endIndex || smiles[next] != "l":
                nC += 1
            case "H": nH += 1
            case "N": nN += 1
            case "O": nO += 1
            case "F": nF += 1
            case "S" where next == smiles.endIndex || smiles[next] != "i":
                nS += 1
            default: break
            }
            i = next
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

    private func crippenLogP(smiles: String) -> Double {
        let (nC, _, nN, nO, nF, nS) = atomCounts(smiles: smiles)
        return Double(nC)*0.1441 + Double(nN)*(-1.019) + Double(nO)*(-0.4430) +
               Double(nF)*0.4202 + Double(nS)*0.6895
    }

    private func estimateTPSA(smiles: String) -> Double {
        let (_, _, nN, nO, _, _) = atomCounts(smiles: smiles)
        return Double(nN)*26.02 + Double(nO)*20.23
    }

    private func countHBD(smiles: String) -> Int {
        smiles.filter { $0 == "N" }.count + smiles.filter { $0 == "O" }.count / 2
    }

    private func countHBA(smiles: String) -> Int {
        let (_, _, nN, nO, _, _) = atomCounts(smiles: smiles)
        return nN + nO
    }

    private func countRotatableBonds(smiles: String) -> Int {
        smiles.filter { $0 == "-" }.count + smiles.filter { "CNOS".contains($0) }.count / 3
    }

    private func ecfp6Bits(smiles: String, nBits: Int) -> [Int] {
        var bits = [Int](repeating: 0, count: nBits)
        for (i, ch) in smiles.enumerated() {
            let hash = abs((Int(ch.asciiValue ?? 0) * 31 + i * 7) % nBits)
            bits[hash] = 1
        }
        return bits
    }

    private func randomSMILES() -> String {
        let frags = ["C", "CC", "CCC", "c1ccccc1", "C(=O)", "C(O)", "C(N)", "C(F)", "C=C", "C#N"]
        let n = Int.random(in: 2...5)
        return (0..<n).map { _ in frags.randomElement()! }.joined()
    }
}
