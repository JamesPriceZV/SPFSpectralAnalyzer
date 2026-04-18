import Foundation

enum MossbauerParser {

    struct MossbauerSpectrum: Sendable {
        let compoundName: String
        let velocity: [Double]
        let transmission: [Double]
        let temperature: Double
        let isomerShift: Double
        let quadSplitting: Double
        let magField: Double
        let lineWidth: Double
        let ironOxidationState: Int
        let spinState: String
    }

    enum ParserError: Error { case invalidFormat, insufficientData }

    nonisolated static func parseJSON(_ data: Data) throws -> MossbauerSpectrum {
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw ParserError.invalidFormat }

        let vel  = (obj["velocity"] as? [Double]) ?? []
        let tran = (obj["transmission"] as? [Double]) ?? []
        guard vel.count >= 10 && vel.count == tran.count else { throw ParserError.insufficientData }

        return MossbauerSpectrum(
            compoundName: (obj["compound"] as? String) ?? "unknown",
            velocity: vel, transmission: tran,
            temperature: (obj["temperature"] as? Double) ?? 298.0,
            isomerShift: (obj["IS"] as? Double) ?? 0,
            quadSplitting: (obj["QS"] as? Double) ?? 0,
            magField: (obj["Bhf"] as? Double) ?? 0,
            lineWidth: (obj["Gamma"] as? Double) ?? 0.25,
            ironOxidationState: (obj["oxidation_state"] as? Int) ?? 0,
            spinState: (obj["spin_state"] as? String) ?? "unknown")
    }

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
