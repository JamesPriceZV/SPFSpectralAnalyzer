import Foundation

struct AIHistoryEntry: Identifiable, Hashable {
    let id = UUID()
    let timestamp: Date
    let preset: AIPromptPreset
    let scope: AISelectionScope
    let text: String
}
