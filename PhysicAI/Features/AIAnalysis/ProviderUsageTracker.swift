import Foundation
import Observation

/// Tracks per-provider token usage and enforces monthly budget caps.
/// Persists usage logs to Application Support JSON files.
@MainActor @Observable
final class ProviderUsageTracker {

    // MARK: - State

    private(set) var usageLog: [UsageLogEntry] = []
    var budgetCaps: [AIProviderID: ProviderBudgetCap] = [:]

    // MARK: - Persistence Paths

    private static var appSupportDirectory: URL {
        let fm = FileManager.default
        let dir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("com.zincoverde.PhysicAI", isDirectory: true)
            .appendingPathComponent("UsageTracking", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static var usageLogURL: URL {
        appSupportDirectory.appendingPathComponent("usage_log.json")
    }

    private static var budgetCapsURL: URL {
        appSupportDirectory.appendingPathComponent("budget_caps.json")
    }

    // MARK: - Init

    init() {
        loadFromDisk()
    }

    // MARK: - Budget Queries

    /// Monthly summaries per provider for the current calendar month.
    var currentMonthSummaries: [MonthlyUsageSummary] {
        let calendar = Calendar.current
        let now = Date()
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!

        let thisMonthEntries = usageLog.filter { $0.timestamp >= startOfMonth }
        var grouped: [AIProviderID: [UsageLogEntry]] = [:]
        for entry in thisMonthEntries {
            grouped[entry.providerID, default: []].append(entry)
        }

        return AIProviderID.allCases.map { id in
            let entries = grouped[id] ?? []
            return MonthlyUsageSummary(
                providerID: id,
                month: startOfMonth,
                totalPromptTokens: entries.reduce(0) { $0 + $1.usage.promptTokens },
                totalCompletionTokens: entries.reduce(0) { $0 + $1.usage.completionTokens },
                totalCostUSD: entries.reduce(0) { $0 + $1.estimatedCostUSD },
                callCount: entries.count
            )
        }
    }

    /// Check if a provider has exceeded its monthly budget.
    func isOverBudget(_ providerID: AIProviderID) -> Bool {
        guard let cap = budgetCaps[providerID], cap.monthlyBudgetUSD > 0 else { return false }
        let summary = currentMonthSummaries.first { $0.providerID == providerID }
        return (summary?.totalCostUSD ?? 0) >= cap.monthlyBudgetUSD
    }

    /// Remaining budget for a provider, or nil if no cap is set.
    func remainingBudget(_ providerID: AIProviderID) -> Double? {
        guard let cap = budgetCaps[providerID], cap.monthlyBudgetUSD > 0 else { return nil }
        let spent = currentMonthSummaries.first { $0.providerID == providerID }?.totalCostUSD ?? 0
        return max(cap.monthlyBudgetUSD - spent, 0)
    }

    /// Set of provider IDs that are currently over budget.
    var overBudgetProviderIDs: Set<AIProviderID> {
        Set(AIProviderID.allCases.filter { isOverBudget($0) })
    }

    // MARK: - Recording

    /// Record a usage event after an analysis call.
    func recordUsage(providerID: AIProviderID, function: AIAppFunction, usage: TokenUsage) {
        let cap = budgetCaps[providerID] ?? ProviderBudgetCap.defaults(for: providerID)
        let cost = cap.estimatedCost(usage: usage)
        let entry = UsageLogEntry(
            providerID: providerID,
            function: function,
            timestamp: Date(),
            usage: usage,
            estimatedCostUSD: cost
        )
        usageLog.append(entry)
        saveToDisk()
    }

    // MARK: - Management

    /// Remove entries older than 3 months.
    func pruneOldEntries() {
        let calendar = Calendar.current
        let cutoff = calendar.date(byAdding: .month, value: -3, to: Date())!
        usageLog.removeAll { $0.timestamp < cutoff }
        saveToDisk()
    }

    /// Reset all usage data for the current month.
    func resetCurrentMonth() {
        let calendar = Calendar.current
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: Date()))!
        usageLog.removeAll { $0.timestamp >= startOfMonth }
        saveToDisk()
    }

    // MARK: - Persistence

    private func loadFromDisk() {
        let decoder = JSONDecoder()

        if let data = try? Data(contentsOf: Self.usageLogURL),
           let entries = try? decoder.decode([UsageLogEntry].self, from: data) {
            usageLog = entries
        }

        if let data = try? Data(contentsOf: Self.budgetCapsURL),
           let caps = try? decoder.decode([ProviderBudgetCap].self, from: data) {
            budgetCaps = Dictionary(uniqueKeysWithValues: caps.map { ($0.providerID, $0) })
        } else {
            // Initialize with defaults
            budgetCaps = Dictionary(uniqueKeysWithValues: AIProviderID.allCases.map {
                ($0, ProviderBudgetCap.defaults(for: $0))
            })
        }
    }

    private func saveToDisk() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        if let data = try? encoder.encode(usageLog) {
            try? data.write(to: Self.usageLogURL, options: .atomic)
        }

        let capsArray = Array(budgetCaps.values)
        if let data = try? encoder.encode(capsArray) {
            try? data.write(to: Self.budgetCapsURL, options: .atomic)
        }
    }
}
