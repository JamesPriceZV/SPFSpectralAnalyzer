import Foundation

nonisolated enum RefractiveIndexYAMLParser {

    struct OpticalData: Sendable {
        let material: String
        let wavelengths_um: [Double]
        let n: [Double]
        let k: [Double]
    }

    enum ParseError: Error { case insufficient }

    static func parse(_ text: String, material: String) throws -> OpticalData {
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
            let cleaned = t.replacingOccurrences(of: "[", with: "")
                           .replacingOccurrences(of: "]", with: "")
                           .replacingOccurrences(of: ",", with: " ")
                           .replacingOccurrences(of: "- ", with: "")
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
}
