import Foundation

/// Bundled static catalog of spectrophotometer manufacturers and models.
struct InstrumentCatalog {

    struct CatalogEntry: Identifiable, Hashable, Sendable {
        let id: String  // stable identifier: "manufacturer|model"
        let manufacturer: String
        let model: String
        let type: String  // "UV-Vis", "UV-Vis-NIR", "FTIR"

        init(manufacturer: String, model: String, type: String) {
            self.id = "\(manufacturer)|\(model)"
            self.manufacturer = manufacturer
            self.model = model
            self.type = type
        }
    }

    /// All supported manufacturers, including "Custom / Other" as the last option.
    static let manufacturers: [String] = [
        "Shimadzu",
        "PerkinElmer",
        "Agilent",
        "JASCO",
        "Hitachi",
        "Thermo Fisher",
        "Anton Paar",
        "Custom / Other"
    ]

    /// The sentinel value used for custom/other selections.
    static let customOther = "Custom / Other"

    /// Complete catalog of known instrument models.
    static let entries: [CatalogEntry] = [
        // Shimadzu
        CatalogEntry(manufacturer: "Shimadzu", model: "UV-1900i Plus", type: "UV-Vis"),
        CatalogEntry(manufacturer: "Shimadzu", model: "UV-2600i Plus", type: "UV-Vis"),
        CatalogEntry(manufacturer: "Shimadzu", model: "UV-2700i Plus", type: "UV-Vis"),
        CatalogEntry(manufacturer: "Shimadzu", model: "UV-3600i Plus", type: "UV-Vis-NIR"),
        CatalogEntry(manufacturer: "Shimadzu", model: "SolidSpec-3700i", type: "UV-Vis-NIR"),
        CatalogEntry(manufacturer: "Shimadzu", model: "SolidSpec-3700i DUV", type: "UV-Vis-NIR"),
        // PerkinElmer
        CatalogEntry(manufacturer: "PerkinElmer", model: "LAMBDA 25", type: "UV-Vis"),
        CatalogEntry(manufacturer: "PerkinElmer", model: "LAMBDA 35", type: "UV-Vis"),
        CatalogEntry(manufacturer: "PerkinElmer", model: "LAMBDA 365+", type: "UV-Vis"),
        CatalogEntry(manufacturer: "PerkinElmer", model: "LAMBDA 950", type: "UV-Vis-NIR"),
        CatalogEntry(manufacturer: "PerkinElmer", model: "LAMBDA 1050+", type: "UV-Vis-NIR"),
        // Agilent (Cary)
        CatalogEntry(manufacturer: "Agilent", model: "Cary 60", type: "UV-Vis"),
        CatalogEntry(manufacturer: "Agilent", model: "Cary 100", type: "UV-Vis"),
        CatalogEntry(manufacturer: "Agilent", model: "Cary 300", type: "UV-Vis"),
        CatalogEntry(manufacturer: "Agilent", model: "Cary 3500", type: "UV-Vis"),
        CatalogEntry(manufacturer: "Agilent", model: "Cary 5000", type: "UV-Vis-NIR"),
        CatalogEntry(manufacturer: "Agilent", model: "Cary 6000i", type: "UV-Vis-NIR"),
        CatalogEntry(manufacturer: "Agilent", model: "Cary 7000 UMS", type: "UV-Vis-NIR"),
        // JASCO
        CatalogEntry(manufacturer: "JASCO", model: "V-730", type: "UV-Vis"),
        CatalogEntry(manufacturer: "JASCO", model: "V-750", type: "UV-Vis"),
        CatalogEntry(manufacturer: "JASCO", model: "V-760", type: "UV-Vis"),
        CatalogEntry(manufacturer: "JASCO", model: "V-770", type: "UV-Vis-NIR"),
        CatalogEntry(manufacturer: "JASCO", model: "V-780", type: "UV-Vis-NIR"),
        // Hitachi
        CatalogEntry(manufacturer: "Hitachi", model: "UH5700", type: "UV-Vis-NIR"),
        CatalogEntry(manufacturer: "Hitachi", model: "UH5300", type: "UV-Vis"),
        CatalogEntry(manufacturer: "Hitachi", model: "UH5200", type: "UV-Vis"),
        CatalogEntry(manufacturer: "Hitachi", model: "UH4150", type: "UV-Vis-NIR"),
        CatalogEntry(manufacturer: "Hitachi", model: "U-5100", type: "UV-Vis"),
        // Thermo Fisher
        CatalogEntry(manufacturer: "Thermo Fisher", model: "Evolution One", type: "UV-Vis"),
        CatalogEntry(manufacturer: "Thermo Fisher", model: "Evolution One Plus", type: "UV-Vis"),
        CatalogEntry(manufacturer: "Thermo Fisher", model: "Evolution Pro", type: "UV-Vis"),
        CatalogEntry(manufacturer: "Thermo Fisher", model: "GENESYS 150", type: "UV-Vis"),
        CatalogEntry(manufacturer: "Thermo Fisher", model: "GENESYS 180", type: "UV-Vis"),
        CatalogEntry(manufacturer: "Thermo Fisher", model: "NanoDrop One", type: "UV-Vis"),
        // Anton Paar (FTIR)
        CatalogEntry(manufacturer: "Anton Paar", model: "Lyza 3000", type: "FTIR"),
        CatalogEntry(manufacturer: "Anton Paar", model: "Lyza 7000", type: "FTIR"),
    ]

    /// Returns catalog entries for a specific manufacturer.
    static func models(for manufacturer: String) -> [CatalogEntry] {
        entries.filter { $0.manufacturer == manufacturer }
    }

    /// Attempt to auto-detect an instrument from the SPC `sourceInstrumentText` header field.
    ///
    /// The SPC header stores a 9-byte instrument identifier (e.g. "UV-2600i", "UV-3600").
    /// This tries substring matching against catalog model names.
    static func detectMatch(from spcInstrumentText: String) -> CatalogEntry? {
        let text = spcInstrumentText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return nil }

        // First pass: check if the SPC text contains a catalog model name or vice versa
        if let match = entries.first(where: { entry in
            let model = entry.model.lowercased()
            return text.contains(model) || model.contains(text)
        }) {
            return match
        }

        // Second pass: try matching with common abbreviation patterns
        // e.g. SPC might store "UV-2600" while catalog has "UV-2600i Plus"
        let alphanumeric = text.filter { $0.isLetter || $0.isNumber || $0 == "-" }
        if !alphanumeric.isEmpty {
            return entries.first { entry in
                let modelAlpha = entry.model.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "-" }
                return modelAlpha.hasPrefix(alphanumeric) || alphanumeric.hasPrefix(modelAlpha)
            }
        }

        return nil
    }

    /// Detect manufacturer from SPC text (for pre-selecting the manufacturer picker).
    static func detectManufacturer(from spcInstrumentText: String) -> String? {
        detectMatch(from: spcInstrumentText)?.manufacturer
    }
}
