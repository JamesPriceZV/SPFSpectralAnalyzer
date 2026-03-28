import Foundation

enum ExportFormat: String, CaseIterable, Identifiable {
    case csv = "CSV"
    case jcamp = "JCAMP"
    case excel = "Excel (.xlsx)"
    case wordReport = "Word (.docx)"
    case pdfReport = "PDF Report"
    case htmlReport = "HTML Report"

    var id: String { rawValue }
}
