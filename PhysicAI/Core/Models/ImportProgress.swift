import Foundation
import SwiftUI

/// Real-time progress tracker for the SPC file import pipeline.
/// Follows the same `@MainActor @Observable` pattern as `TrainingDataDownloader`.
@MainActor @Observable
final class ImportProgress {

    // MARK: - Stage Enum

    enum Stage: Equatable {
        case idle
        case parsing(parsed: Int, total: Int, currentFile: String)
        case validating(valid: Int, invalid: Int, total: Int)
        case persisting(stored: Int, duplicates: Int, total: Int)
        case completed(spectra: Int, datasets: Int, duplicates: Int,
                       invalid: Int, duration: TimeInterval)
        case failed(String)
    }

    // MARK: - State

    var stage: Stage = .idle

    // MARK: - Computed Properties

    var isActive: Bool {
        switch stage {
        case .parsing, .validating, .persisting: return true
        default: return false
        }
    }

    var isCompleted: Bool {
        if case .completed = stage { return true }
        return false
    }

    var isFailed: Bool {
        if case .failed = stage { return true }
        return false
    }

    /// Overall progress fraction 0...1 across all stages.
    /// Parsing = 0–0.6, Validating = 0.6–0.8, Persisting = 0.8–1.0
    var overallProgress: Double {
        switch stage {
        case .idle: return 0
        case .parsing(let parsed, let total, _):
            guard total > 0 else { return 0 }
            return 0.6 * Double(parsed) / Double(total)
        case .validating(_, _, let total):
            guard total > 0 else { return 0.6 }
            return 0.7  // validation is fast, show as a midpoint
        case .persisting(let stored, _, let total):
            guard total > 0 else { return 0.8 }
            return 0.8 + 0.2 * Double(stored) / Double(total)
        case .completed: return 1.0
        case .failed: return 0
        }
    }

    /// Human-readable label for the current stage.
    var stageLabel: String {
        switch stage {
        case .idle:
            return ""
        case .parsing(let parsed, let total, let file):
            let name = file.isEmpty ? "" : ": \(file)"
            return "Parsing \(parsed)/\(total)\(name)"
        case .validating(let valid, let invalid, _):
            return "Validating — \(valid) valid, \(invalid) flagged"
        case .persisting(let stored, let dups, _):
            let dupText = dups > 0 ? ", \(dups) duplicate\(dups == 1 ? "" : "s")" : ""
            return "Storing \(stored) dataset\(stored == 1 ? "" : "s")\(dupText)"
        case .completed(let spectra, let datasets, let dups, let invalid, let duration):
            var parts: [String] = []
            parts.append("\(spectra) spectra from \(datasets) file\(datasets == 1 ? "" : "s")")
            if dups > 0 { parts.append("\(dups) duplicate\(dups == 1 ? "" : "s")") }
            if invalid > 0 { parts.append("\(invalid) invalid") }
            let time = String(format: "%.1fs", duration)
            return "Imported \(parts.joined(separator: " · ")) in \(time)"
        case .failed(let message):
            return message
        }
    }

    /// Tint color for the progress bar.
    var tintColor: Color {
        switch stage {
        case .idle: return .secondary
        case .parsing: return .blue
        case .validating: return .orange
        case .persisting: return .purple
        case .completed: return .green
        case .failed: return .red
        }
    }

    /// SF Symbol for the current stage.
    var iconName: String {
        switch stage {
        case .idle: return "tray"
        case .parsing: return "doc.text.magnifyingglass"
        case .validating: return "checkmark.shield"
        case .persisting: return "externaldrive.badge.plus"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    // MARK: - Actions

    func reset() {
        stage = .idle
    }
}
