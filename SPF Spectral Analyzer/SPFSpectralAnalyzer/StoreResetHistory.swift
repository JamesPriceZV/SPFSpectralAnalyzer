import Foundation

struct StoreResetHistoryEntry: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let message: String

    init(timestamp: Date = Date(), message: String) {
        self.id = UUID()
        self.timestamp = timestamp
        self.message = message
    }

    static func decode(from data: Data) -> [StoreResetHistoryEntry] {
        guard !data.isEmpty,
              let decoded = try? JSONDecoder().decode([StoreResetHistoryEntry].self, from: data) else {
            return []
        }
        return decoded
    }

    static func encode(_ entries: [StoreResetHistoryEntry]) -> Data? {
        try? JSONEncoder().encode(entries)
    }
}
