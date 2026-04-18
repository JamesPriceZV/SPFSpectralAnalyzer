import Foundation

nonisolated enum CDMSParser {

    struct CatalogLine: Sendable {
        let freqMHz: Double
        let logIntensity: Double
        let lowerEnergyPerCm: Double
        let upperDegeneracy: Int
    }

    static func parseCatalog(_ text: String) -> [CatalogLine] {
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
            return CatalogLine(freqMHz: freq, logIntensity: logI,
                               lowerEnergyPerCm: ener, upperDegeneracy: deg)
        }
    }
}
