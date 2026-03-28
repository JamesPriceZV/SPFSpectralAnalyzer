import Foundation

/// A key-value record that the boolean search engine can evaluate against.
///
/// Concrete types adapt different data contexts (datasets, spectra) to this
/// uniform interface, enabling a single search engine for all search boxes.
protocol SearchableRecord {
    /// Return the text value(s) for a given field.
    /// Return nil if the field is not applicable to this record type.
    func values(for field: SearchField) -> [String]?

    /// All searchable text concatenated, lowercased. Used for unqualified search terms.
    var allText: String { get }

    /// Return the numeric value for a numeric field (spf, spectra), or nil.
    func numericValue(for field: SearchField) -> Double?

    /// Return the date value for a date field (date/importedAt), or nil.
    func dateValue(for field: SearchField) -> Date?
}
