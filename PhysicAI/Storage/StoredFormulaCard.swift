import Foundation
import SwiftData

/// SwiftData model for a formula card containing sunscreen formulation data.
///
/// Linked to `StoredDataset` via `formulaCardID: UUID?` on the dataset side
/// (not a SwiftData @Relationship) to avoid CloudKit sync crash risk.
/// Multiple prototype sample datasets can share the same formula card (many-to-one).
@Model
public final class StoredFormulaCard {
    public var id: UUID = UUID()
    /// User-facing name for this formula card
    var name: String = ""
    /// When this formula card was created
    var createdAt: Date = Date()
    /// Original imported file data (Excel, Word, PDF, or image)
    var sourceFileData: Data?
    /// Original filename
    var sourceFileName: String?
    /// File type identifier (e.g. "xlsx", "docx", "pdf", "jpeg")
    var sourceFileType: String?
    /// Parsed ingredients stored as JSON array of FormulaIngredient
    var ingredientsJSON: Data?
    /// Extracted pH value
    var parsedPH: Double?
    /// Total formula weight in grams (sum of all ingredient quantities)
    var totalWeightGrams: Double?
    /// User notes
    var notes: String?
    /// Whether AI parsing has completed
    var isParsed: Bool = false
    /// Raw extracted text from the document (intermediate, used for AI parsing)
    var extractedText: String?

    public init(
        id: UUID = UUID(),
        name: String = "",
        createdAt: Date = Date(),
        sourceFileData: Data? = nil,
        sourceFileName: String? = nil,
        sourceFileType: String? = nil,
        ingredientsJSON: Data? = nil,
        parsedPH: Double? = nil,
        totalWeightGrams: Double? = nil,
        notes: String? = nil,
        isParsed: Bool = false,
        extractedText: String? = nil
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.sourceFileData = sourceFileData
        self.sourceFileName = sourceFileName
        self.sourceFileType = sourceFileType
        self.ingredientsJSON = ingredientsJSON
        self.parsedPH = parsedPH
        self.totalWeightGrams = totalWeightGrams
        self.notes = notes
        self.isParsed = isParsed
        self.extractedText = extractedText
    }

    /// Display label combining name and source file.
    var displayName: String {
        if !name.isEmpty { return name }
        if let sourceFileName { return sourceFileName }
        return "Formula Card"
    }

    /// Decoded ingredients from JSON storage.
    var ingredients: [FormulaIngredient] {
        get {
            guard let data = ingredientsJSON,
                  let decoded = try? JSONDecoder().decode([FormulaIngredient].self, from: data) else {
                return []
            }
            return decoded
        }
        set {
            ingredientsJSON = try? JSONEncoder().encode(newValue)
        }
    }
}
