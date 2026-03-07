import Foundation

struct MetricsComputationResult: Sendable {
    let selectedMetrics: SpectralMetrics?
    let metricsStats: (avgUvaUvb: Double, avgCritical: Double, uvaUvbRange: ClosedRange<Double>, criticalRange: ClosedRange<Double>)?
    let calibration: CalibrationResult?
    let nearestMatch: NearestReferenceMatch?
    let colipaSpf: Double?
    let dashboard: DashboardMetrics?
    let spfEstimation: SPFEstimationResult?
    var calibrationLogDetails: String = ""
}

struct DashboardMetrics: Sendable {
    let totalCount: Int
    let compliancePercent: Double
    let complianceCount: Int
    let avgUvaUvb: Double
    let uvaUvbRange: ClosedRange<Double>
    let avgCritical: Double
    let criticalRange: ClosedRange<Double>
    let postIncubationDropPercent: Double?
    let lowCriticalCount: Int
    let heatmapBins: [HeatmapBin]
    let heatmapXRange: ClosedRange<Double>
    let heatmapYRange: ClosedRange<Double>
    let spfEstimationTier: SPFEstimationTier?
}

struct HeatmapBin: Identifiable, Sendable {
    let id = UUID()
    let xIndex: Int
    let yIndex: Int
    let count: Int
    let xRange: ClosedRange<Double>
    let yRange: ClosedRange<Double>
}

struct BatchCompareRow: Identifiable {
    let id = UUID()
    let name: String
    let spf: Double?
    let deltaSpf: Double?
    let uvaUvb: Double?
    let deltaUvaUvb: Double?
    let critical: Double?
    let deltaCritical: Double?
}
