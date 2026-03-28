import Foundation

struct ProductSPFLabel: Identifiable {
    let id = UUID()
    let name: String
    let spf: Double
}

struct SPFLabelStore {
    static let labels: [ProductSPFLabel] = [
        // Inferred from sample filenames + public product labels. Please verify.
        ProductSPFLabel(name: "Neutrogena SPF 30", spf: 30),
        ProductSPFLabel(name: "Neutrogena Sheer Zinc SPF 30", spf: 30),
        ProductSPFLabel(name: "Neutrogena Mineral SPF 50", spf: 50),
        ProductSPFLabel(name: "Cetaphil Everyday Sunscreen Tinted Face Lotion SPF 40", spf: 40),
        ProductSPFLabel(name: "CeraVe Hydrating Sheer Sunscreen SPF 30", spf: 30),
        ProductSPFLabel(name: "CVS Health Mineral Sunscreen for Face SPF 50", spf: 50)
    ]

    static func matchLabel(for sampleName: String) -> ProductSPFLabel? {
        let normalizedSample = normalize(sampleName)
        guard !normalizedSample.isEmpty else { return nil }

        var bestMatch: ProductSPFLabel?
        var bestScore = 0

        for label in labels {
            let normalizedLabel = normalize(label.name)
            if normalizedLabel.isEmpty { continue }

            let score: Int
            if normalizedSample == normalizedLabel {
                score = normalizedLabel.count + 1000
            } else if normalizedSample.contains(normalizedLabel) || normalizedLabel.contains(normalizedSample) {
                score = min(normalizedSample.count, normalizedLabel.count)
            } else {
                score = tokenOverlapScore(sampleName, label.name)
            }

            if score > bestScore {
                bestScore = score
                bestMatch = label
            }
        }

        return bestScore > 0 ? bestMatch : nil
    }

    private static func normalize(_ value: String) -> String {
        let folded = value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let allowed = folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
        return String(String.UnicodeScalarView(allowed))
    }

    private static func tokenOverlapScore(_ a: String, _ b: String) -> Int {
        let tokensA = tokenize(a)
        let tokensB = tokenize(b)
        if tokensA.isEmpty || tokensB.isEmpty { return 0 }
        return tokensA.intersection(tokensB).count * 10
    }

    private static func tokenize(_ value: String) -> Set<String> {
        let folded = value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let spaced = folded.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        let tokens = String(spaced).split(whereSeparator: { $0 == " " })
        return Set(tokens.map(String.init))
    }
}
