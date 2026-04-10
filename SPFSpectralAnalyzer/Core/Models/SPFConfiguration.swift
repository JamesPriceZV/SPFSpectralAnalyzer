import Foundation

/// Bridge struct for @AppStorage SPF values that cannot move into @Observable classes.
/// ContentView constructs this from its @AppStorage properties and passes it to AnalysisViewModel.
struct SPFConfiguration: Equatable {
    var cFactor: Double
    var substrateCorrection: Double
    var adjustmentFactor: Double
    var estimationOverride: SPFEstimationOverride
    var calculationMethod: SPFCalculationMethod
}
