import Foundation

struct ValidationLogEntry: Identifiable, Hashable {
    let id = UUID()
    let timestamp: Date
    let message: String
}
