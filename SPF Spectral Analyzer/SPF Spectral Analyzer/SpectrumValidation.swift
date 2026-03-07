import Foundation

enum SpectrumValidation {
    static func invalidReason(x: [Double], y: [Double]) -> String? {
        let count = min(x.count, y.count)
        guard count > 0 else { return "Empty axis data" }
        for index in 0..<count {
            let xVal = x[index]
            let yVal = y[index]
            if !xVal.isFinite || !yVal.isFinite {
                return "Non-finite values in data"
            }
        }
        return nil
    }
}
