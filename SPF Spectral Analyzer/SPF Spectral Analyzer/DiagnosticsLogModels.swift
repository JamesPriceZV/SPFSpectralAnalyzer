import Foundation

struct DiagnosticsLogEntryPayload: Codable {
    let timestamp: Date
    let message: String
}
