import Foundation
import SwiftData

/// SwiftData model for a registered laboratory instrument.
///
/// Linked to `StoredDataset` via `instrumentID: UUID?` on the dataset side
/// (not a SwiftData @Relationship) to avoid CloudKit sync crash risk.
@Model
public final class StoredInstrument {
    public var id: UUID = UUID()
    /// Manufacturer name, e.g. "Shimadzu", "PerkinElmer"
    var manufacturer: String = ""
    /// Model name, e.g. "UV-2600i Plus", "Cary 5000"
    var modelName: String = ""
    /// Optional serial number
    var serialNumber: String?
    /// Optional lab identification number
    var labNumber: String?
    /// Free-text address string
    var locationAddress: String?
    /// Latitude from MapKit geocoding
    var locationLatitude: Double?
    /// Longitude from MapKit geocoding
    var locationLongitude: Double?
    /// Instrument type category: "UV-Vis", "UV-Vis-NIR", "FTIR"
    var instrumentType: String = "UV-Vis"
    /// When this instrument record was created
    var createdAt: Date = Date()
    /// Optional user notes
    var notes: String?

    public init(
        id: UUID = UUID(),
        manufacturer: String = "",
        modelName: String = "",
        serialNumber: String? = nil,
        labNumber: String? = nil,
        locationAddress: String? = nil,
        locationLatitude: Double? = nil,
        locationLongitude: Double? = nil,
        instrumentType: String = "UV-Vis",
        createdAt: Date = Date(),
        notes: String? = nil
    ) {
        self.id = id
        self.manufacturer = manufacturer
        self.modelName = modelName
        self.serialNumber = serialNumber
        self.labNumber = labNumber
        self.locationAddress = locationAddress
        self.locationLatitude = locationLatitude
        self.locationLongitude = locationLongitude
        self.instrumentType = instrumentType
        self.createdAt = createdAt
        self.notes = notes
    }

    /// Display label combining manufacturer and model.
    var displayName: String {
        if manufacturer.isEmpty && modelName.isEmpty { return "Unknown Instrument" }
        if manufacturer.isEmpty { return modelName }
        if modelName.isEmpty { return manufacturer }
        return "\(manufacturer) \(modelName)"
    }
}
