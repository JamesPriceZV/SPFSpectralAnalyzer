import SwiftUI

private enum PreviewData {
    static func loadSpectra() -> [ShimadzuSpectrum] {
        let paths = [
            "/Users/zincoverdeinc./Library/CloudStorage/OneDrive-Personal/4_Xcode Projects/Shimadzu File Converter/SPF Spectral Analyzer/SPCSampleFiles/File_260207_131047.CVS 50 15.2 mg tio2 zno2 combospc.spc",
            "/Users/zincoverdeinc./Library/CloudStorage/OneDrive-Personal/4_Xcode Projects/Shimadzu File Converter/SPF Spectral Analyzer/SPCSampleFiles/File_260207_131235. CVS 50 16.1 mg tio2 zno2 combo spc.spc"
        ]

        var spectra: [ShimadzuSpectrum] = []
        for path in paths {
            let url = URL(fileURLWithPath: path)
            if let parser = try? ShimadzuSPCParser(fileURL: url),
               let result = try? parser.extractSpectraResult() {
                let converted = result.spectra.map { ShimadzuSpectrum(name: $0.name, x: $0.x, y: $0.y) }
                spectra.append(contentsOf: converted)
            }
        }

        return spectra.isEmpty ? mockSpectra() : spectra
    }

    static func mockSpectra() -> [ShimadzuSpectrum] {
        let x = stride(from: 280.0, through: 420.0, by: 2.0).map { $0 }
        let y1 = x.map { 0.4 - 0.001 * ($0 - 280.0) }
        let y2 = x.map { 0.35 - 0.0008 * ($0 - 280.0) + 0.02 * sin($0 / 12.0) }
        let y3 = x.map { 0.3 - 0.0007 * ($0 - 280.0) + 0.015 * cos($0 / 10.0) }

        return [
            ShimadzuSpectrum(name: "Preview Sample A", x: x, y: y1),
            ShimadzuSpectrum(name: "Preview Sample B", x: x, y: y2),
            ShimadzuSpectrum(name: "Preview Sample C", x: x, y: y3)
        ]
    }
}

#Preview {
    ContentView(authManager: MSALAuthManager(), previewSpectra: PreviewData.loadSpectra(), previewMode: .analyze)
}

