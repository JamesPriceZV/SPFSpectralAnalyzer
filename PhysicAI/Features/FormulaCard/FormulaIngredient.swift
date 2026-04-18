import Foundation

/// A single ingredient entry in a sunscreen formula card.
struct FormulaIngredient: Codable, Sendable, Identifiable, Hashable {
    var id: UUID = UUID()
    /// Trade name or common ingredient name (e.g. "Parsol 1789", "Zinc Oxide")
    var name: String
    /// INCI (International Nomenclature of Cosmetic Ingredients) name, if different from trade name
    var inciName: String?
    /// Quantity value (typically in grams or milligrams)
    var quantity: Double?
    /// Unit string (e.g. "g", "mg", "%")
    var unit: String?
    /// Weight percentage of total formula (calculated or parsed)
    var percentage: Double?
    /// Functional category (e.g. "UV filter", "emollient", "preservative", "emulsifier")
    var category: String?
}
