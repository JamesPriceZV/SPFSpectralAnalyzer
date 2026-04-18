import Foundation

enum QM9XYZParser {

    struct QM9Molecule: Sendable {
        let tag: String
        let smiles: String
        let atomCount: Int
        let atomicNumbers: [Int]
        let positions: [[Double]]
        let rotationalConsts: [Double]
        let dipoleMoment: Double
        let polarisability: Double
        let homoEV: Double
        let lumoEV: Double
        let gapEV: Double
        let r2: Double
        let zpve: Double
        let u0: Double
        let u298: Double
        let h298: Double
        let g298: Double
        let cv: Double
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

        let propParts = lines[1].components(separatedBy: CharacterSet.whitespaces)
                                .filter { !$0.isEmpty }
        guard propParts.count >= 16 else {
            throw ParserError.invalidFormat("property line too short")
        }

        let tag    = propParts[0]
        let rotA   = Double(propParts[1]) ?? 0
        let rotB   = Double(propParts[2]) ?? 0
        let rotC   = Double(propParts[3]) ?? 0
        let mu     = Double(propParts[4]) ?? 0
        let alpha  = Double(propParts[5]) ?? 0
        let eHOMO  = (Double(propParts[6]) ?? 0) * 27.2114
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
            "H": 1, "C": 6, "N": 7, "O": 8, "F": 9, "P": 15, "S": 16, "Cl": 17, "Br": 35, "I": 53
        ]

        var atomicNumbers: [Int] = []
        var positions: [[Double]] = []

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
