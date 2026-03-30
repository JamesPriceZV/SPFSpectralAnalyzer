import Foundation

/// A single ingredient entry in a sunscreen formula card.
struct FormulaIngredient: Codable, Sendable, Identifiable, Hashable {
    var id: UUID = UUID()
    /// Ingredient name (e.g. "Zinc Oxide", "Octocrylene")
    var name: String
    /// Quantity value (typically in grams)
    var quantity: Double?
    /// Unit string (e.g. "g", "mg", "%")
    var unit: String?
    /// Weight percentage of total formula (calculated or parsed)
    var percentage: Double?
    /// Functional category (e.g. "UV filter", "emollient", "preservative", "emulsifier")
    var category: String?
}
