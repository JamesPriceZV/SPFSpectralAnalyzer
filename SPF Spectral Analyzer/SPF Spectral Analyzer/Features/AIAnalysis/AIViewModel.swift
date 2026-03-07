import Foundation
import Observation

/// Observable view model that owns AI analysis runtime state.
/// Persisted preferences remain as @AppStorage properties on ContentView
/// because @AppStorage only works inside SwiftUI View types.
@Observable
final class AIViewModel {
    // MARK: - Runtime State

    var scopeOverride: AISelectionScope?
    var isRunning = false
    var result: AIAnalysisResult?
    var structuredOutput: AIStructuredOutput?
    var errorMessage: String?
    var cache: [String: AIAnalysisResult] = [:]
    var structuredCache: [String: AIStructuredOutput] = [:]
    var estimatedTokens: Int = 0

    // MARK: - UI State

    var showSavePrompt = false
    var showDetails = true
    var showSection = false
    var showResponsePopup = false

    // MARK: - Custom Prompt

    var useCustomPrompt = false
    var customPrompt = ""

    // MARK: - History

    var historyEntries: [AIHistoryEntry] = []
    var historySelectionA: UUID?
    var historySelectionB: UUID?
    let historyMaxEntries = 20

    // MARK: - Sidebar Structured Sections

    var sidebarInsightsText = ""
    var sidebarRisksText = ""
    var sidebarActionsText = ""
    var sidebarHasStructuredSections = false
}
