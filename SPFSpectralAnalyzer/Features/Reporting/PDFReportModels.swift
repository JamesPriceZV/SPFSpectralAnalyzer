import SwiftUI

struct PDFReportData: Sendable {
    var title: String
    var generatedAt: Date
    var metadataLines: [String]
    var metricRows: [ReportMetricRow]
    var aiSummary: String
    var aiFullText: String
    var insights: [String]
    var risks: [String]
    var actions: [String]
    var recommendations: [ReportRecommendation]
    var series: [ReportSpectrumSeries]
    var spfEstimation: SPFEstimationResult?
}

struct ReportMetricRow: Identifiable, Sendable {
    let id = UUID()
    let label: String
    let value: String
}

struct ReportRecommendation: Identifiable, Sendable {
    let id = UUID()
    let ingredient: String
    let amount: String
    let rationale: String?
}

struct ReportSpectrumPoint: Identifiable, Sendable {
    let id = UUID()
    let x: Double
    let y: Double
}

struct ReportSpectrumSeries: Identifiable, @unchecked Sendable {
    let id = UUID()
    let name: String
    let points: [ReportSpectrumPoint]
    let color: Color
}
