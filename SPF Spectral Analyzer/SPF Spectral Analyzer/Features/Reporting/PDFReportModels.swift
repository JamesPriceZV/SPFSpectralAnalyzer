import SwiftUI

struct PDFReportData {
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

struct ReportMetricRow: Identifiable {
    let id = UUID()
    let label: String
    let value: String
}

struct ReportRecommendation: Identifiable {
    let id = UUID()
    let ingredient: String
    let amount: String
    let rationale: String?
}

struct ReportSpectrumPoint: Identifiable {
    let id = UUID()
    let x: Double
    let y: Double
}

struct ReportSpectrumSeries: Identifiable {
    let id = UUID()
    let name: String
    let points: [ReportSpectrumPoint]
    let color: Color
}
