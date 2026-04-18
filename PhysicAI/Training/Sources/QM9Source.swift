import Foundation

actor QM9Source {

    static let csvURL = URL(string:
        "https://deepchemdata.s3-us-west-1.amazonaws.com/datasets/molnet_publish/qm9.csv.gz")!

    func streamCSV() -> AsyncThrowingStream<QM9XYZParser.QM9Molecule, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let (data, _) = try await URLSession.shared.data(from: Self.csvURL)
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

                    lines.removeFirst()
                    for line in lines {
                        guard !line.isEmpty else { continue }
                        let parts = line.components(separatedBy: ",")
                        guard parts.count > max(smilesIdx, homoIdx, lumoIdx) else { continue }
                        func d(_ i: Int) -> Double { Double(parts[i]) ?? 0 }
                        let mol = QM9XYZParser.QM9Molecule(
                            tag: "qm9_csv", smiles: parts[smilesIdx],
                            atomCount: 0, atomicNumbers: [], positions: [],
                            rotationalConsts: [0, 0, 0],
                            dipoleMoment: d(muIdx), polarisability: d(alphaIdx),
                            homoEV: d(homoIdx), lumoEV: d(lumoIdx), gapEV: d(gapIdx),
                            r2: d(r2Idx), zpve: d(zpveIdx), u0: d(u0Idx),
                            u298: 0, h298: 0, g298: d(g298Idx), cv: d(cvIdx))
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
