import Foundation

/// Computes structured diffs between ingredient lists and generates HTML diff reports.
enum IngredientDiffService {

    // MARK: - Types

    enum ChangeType: Sendable { case added, removed, modified }

    struct FieldChange: Sendable {
        let fieldName: String
        let oldValue: String
        let newValue: String
    }

    struct DiffEntry: Sendable {
        let ingredientName: String
        let inciName: String?
        let changeType: ChangeType
        let details: [FieldChange]
    }

    // MARK: - Diff

    /// Compare two ingredient lists and return structured diff entries.
    /// Matches by (name, inciName) pair (case-insensitive). Unmatched old → removed, unmatched new → added.
    static func diff(old: [FormulaIngredient], new: [FormulaIngredient]) -> [DiffEntry] {
        var entries: [DiffEntry] = []

        // Build lookup from old ingredients keyed by normalized (name, inci)
        typealias Key = String
        func makeKey(_ name: String, _ inci: String?) -> Key {
            "\(name.lowercased().trimmingCharacters(in: .whitespaces))|\((inci ?? "").lowercased().trimmingCharacters(in: .whitespaces))"
        }

        var oldMap: [Key: FormulaIngredient] = [:]
        var oldKeys: [Key] = []
        for ing in old {
            let key = makeKey(ing.name, ing.inciName)
            oldMap[key] = ing
            oldKeys.append(key)
        }

        var matchedOldKeys: Set<Key> = []

        // Process new ingredients
        for newIng in new {
            let key = makeKey(newIng.name, newIng.inciName)

            if let oldIng = oldMap[key] {
                matchedOldKeys.insert(key)
                // Compare fields
                var changes: [FieldChange] = []
                if !valuesEqual(oldIng.quantity, newIng.quantity) {
                    changes.append(FieldChange(
                        fieldName: "quantity",
                        oldValue: formatOptionalDouble(oldIng.quantity),
                        newValue: formatOptionalDouble(newIng.quantity)
                    ))
                }
                if !valuesEqual(oldIng.percentage, newIng.percentage) {
                    changes.append(FieldChange(
                        fieldName: "percentage",
                        oldValue: formatOptionalDouble(oldIng.percentage),
                        newValue: formatOptionalDouble(newIng.percentage)
                    ))
                }
                if (oldIng.category ?? "") != (newIng.category ?? "") {
                    changes.append(FieldChange(
                        fieldName: "category",
                        oldValue: oldIng.category ?? "—",
                        newValue: newIng.category ?? "—"
                    ))
                }
                if (oldIng.unit ?? "mg") != (newIng.unit ?? "mg") {
                    changes.append(FieldChange(
                        fieldName: "unit",
                        oldValue: oldIng.unit ?? "mg",
                        newValue: newIng.unit ?? "mg"
                    ))
                }
                if !changes.isEmpty {
                    entries.append(DiffEntry(
                        ingredientName: newIng.name,
                        inciName: newIng.inciName,
                        changeType: .modified,
                        details: changes
                    ))
                }
            } else {
                entries.append(DiffEntry(
                    ingredientName: newIng.name,
                    inciName: newIng.inciName,
                    changeType: .added,
                    details: []
                ))
            }
        }

        // Remaining old ingredients are removed
        for key in oldKeys where !matchedOldKeys.contains(key) {
            if let oldIng = oldMap[key] {
                entries.append(DiffEntry(
                    ingredientName: oldIng.name,
                    inciName: oldIng.inciName,
                    changeType: .removed,
                    details: []
                ))
            }
        }

        return entries
    }

    // MARK: - HTML Generation

    /// Generate a standalone HTML diff page with inline CSS.
    static func generateHTML(diff: [DiffEntry], providerName: String, timestamp: Date) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        let dateStr = dateFormatter.string(from: timestamp)

        let added = diff.filter { $0.changeType == .added }.count
        let removed = diff.filter { $0.changeType == .removed }.count
        let modified = diff.filter { $0.changeType == .modified }.count

        var html = """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Formula Card Re-Parse Diff</title>
        <style>
            body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
                   margin: 20px; background: #1c1c1e; color: #e5e5e7; }
            h1 { font-size: 1.3em; color: #f5f5f7; }
            .meta { color: #98989d; font-size: 0.85em; margin-bottom: 16px; }
            .summary { display: flex; gap: 16px; margin-bottom: 16px; }
            .badge { padding: 4px 10px; border-radius: 6px; font-size: 0.85em; font-weight: 600; }
            .badge-added { background: #0a3d0a; color: #30d158; }
            .badge-removed { background: #3d0a0a; color: #ff453a; }
            .badge-modified { background: #3d3a0a; color: #ffd60a; }
            table { width: 100%; border-collapse: collapse; margin-top: 12px; }
            th { text-align: left; padding: 8px 12px; background: #2c2c2e; color: #98989d;
                 font-size: 0.8em; text-transform: uppercase; letter-spacing: 0.5px; }
            td { padding: 8px 12px; border-bottom: 1px solid #38383a; font-size: 0.9em; }
            tr.added { background: rgba(48, 209, 88, 0.08); }
            tr.removed { background: rgba(255, 69, 58, 0.08); }
            tr.modified { background: rgba(255, 214, 10, 0.05); }
            .change-tag { font-size: 0.75em; font-weight: 600; padding: 2px 8px;
                          border-radius: 4px; display: inline-block; }
            .tag-added { background: #0a3d0a; color: #30d158; }
            .tag-removed { background: #3d0a0a; color: #ff453a; }
            .tag-modified { background: #3d3a0a; color: #ffd60a; }
            del { color: #ff453a; text-decoration: line-through; }
            ins { color: #30d158; text-decoration: none; font-weight: 600; }
            .field-change { font-size: 0.85em; color: #98989d; }
            @media (prefers-color-scheme: light) {
                body { background: #f2f2f7; color: #1c1c1e; }
                h1 { color: #000; }
                .meta { color: #6e6e73; }
                th { background: #e5e5ea; color: #6e6e73; }
                td { border-bottom-color: #d1d1d6; }
                tr.added { background: #e6ffe6; }
                tr.removed { background: #ffe6e6; }
                tr.modified { background: #fffbe6; }
                .badge-added { background: #d4edda; color: #155724; }
                .badge-removed { background: #f8d7da; color: #721c24; }
                .badge-modified { background: #fff3cd; color: #856404; }
                .tag-added { background: #d4edda; color: #155724; }
                .tag-removed { background: #f8d7da; color: #721c24; }
                .tag-modified { background: #fff3cd; color: #856404; }
                del { color: #dc3545; }
                ins { color: #28a745; }
                .field-change { color: #6e6e73; }
            }
        </style>
        </head>
        <body>
        <h1>Formula Card Re-Parse Diff</h1>
        <div class="meta">\(dateStr) &mdash; Re-parsed with \(escapeHTML(providerName))</div>
        <div class="summary">
        """

        if added > 0 { html += "<span class=\"badge badge-added\">+\(added) added</span>" }
        if removed > 0 { html += "<span class=\"badge badge-removed\">&minus;\(removed) removed</span>" }
        if modified > 0 { html += "<span class=\"badge badge-modified\">\(modified) modified</span>" }

        html += """
        </div>
        <table>
        <thead><tr><th>Name</th><th>INCI</th><th>Change</th><th>Details</th></tr></thead>
        <tbody>
        """

        for entry in diff {
            let rowClass: String
            let tagClass: String
            let tagLabel: String
            switch entry.changeType {
            case .added:
                rowClass = "added"; tagClass = "tag-added"; tagLabel = "Added"
            case .removed:
                rowClass = "removed"; tagClass = "tag-removed"; tagLabel = "Removed"
            case .modified:
                rowClass = "modified"; tagClass = "tag-modified"; tagLabel = "Modified"
            }

            var detailHTML = ""
            for change in entry.details {
                detailHTML += "<span class=\"field-change\">\(escapeHTML(change.fieldName)): <del>\(escapeHTML(change.oldValue))</del> &rarr; <ins>\(escapeHTML(change.newValue))</ins></span><br>"
            }
            if detailHTML.isEmpty && entry.changeType == .added {
                detailHTML = "<span class=\"field-change\">New ingredient</span>"
            } else if detailHTML.isEmpty && entry.changeType == .removed {
                detailHTML = "<span class=\"field-change\">Ingredient removed</span>"
            }

            html += """
            <tr class="\(rowClass)">
            <td>\(escapeHTML(entry.ingredientName))</td>
            <td>\(escapeHTML(entry.inciName ?? "—"))</td>
            <td><span class="change-tag \(tagClass)">\(tagLabel)</span></td>
            <td>\(detailHTML)</td>
            </tr>
            """
        }

        html += "</tbody></table></body></html>"
        return html
    }

    // MARK: - Notes Summary

    /// Generate a plain-text summary for the notes field.
    static func generateNotesSummary(diff: [DiffEntry], providerName: String, timestamp: Date) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"
        let dateStr = dateFormatter.string(from: timestamp)

        let added = diff.filter { $0.changeType == .added }.count
        let removed = diff.filter { $0.changeType == .removed }.count
        let modified = diff.filter { $0.changeType == .modified }.count

        var parts: [String] = []
        if added > 0 { parts.append("\(added) added") }
        if removed > 0 { parts.append("\(removed) removed") }
        if modified > 0 { parts.append("\(modified) modified") }

        return "[\(dateStr)] Re-parsed with \(providerName). \(parts.joined(separator: ", "))."
    }

    // MARK: - Helpers

    private static func valuesEqual(_ a: Double?, _ b: Double?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case (nil, _), (_, nil): return false
        case let (a?, b?): return abs(a - b) < 0.001
        }
    }

    private static func formatOptionalDouble(_ value: Double?) -> String {
        guard let v = value else { return "—" }
        return String(format: "%.2f", v)
    }

    private static func escapeHTML(_ str: String) -> String {
        str.replacingOccurrences(of: "&", with: "&amp;")
           .replacingOccurrences(of: "<", with: "&lt;")
           .replacingOccurrences(of: ">", with: "&gt;")
           .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
