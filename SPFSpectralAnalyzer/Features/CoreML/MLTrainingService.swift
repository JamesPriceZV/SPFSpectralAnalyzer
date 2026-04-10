import Foundation
import SwiftData
import Observation
import CoreML
#if os(macOS)
import CreateML
import TabularData
#endif

/// In-app Create ML training orchestrator (macOS only for training; cross-platform for status).
@MainActor @Observable
final class MLTrainingService {

    // MARK: - Singleton

    static let shared = MLTrainingService()

    // MARK: - State

    var status: MLTrainingStatus = .idle
    var lastResult: MLTrainingResult?

    /// Number of reference spectra available for training.
    var availableSpectrumCount: Int = 0

    /// Minimum reference spectra required to train.
    static let minimumSpectra = 5

    var canTrain: Bool {
        !status.isInProgress && availableSpectrumCount >= Self.minimumSpectra
    }

    // MARK: - Init

    private init() {
        loadPersistedResult()
    }

    // MARK: - Storage Paths

    static var modelDirectoryURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport
            .appendingPathComponent("com.zincoverde.SPFSpectralAnalyzer", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
    }

    static var compiledModelURL: URL {
        modelDirectoryURL.appendingPathComponent("SPFPredictor.mlmodelc", isDirectory: true)
    }

    static var sourceModelURL: URL {
        modelDirectoryURL.appendingPathComponent("SPFPredictor.mlmodel")
    }

    static var trainingResultURL: URL {
        modelDirectoryURL.appendingPathComponent("SPFPredictor_training.json")
    }

    /// iCloud ubiquity container URL for syncing the trained model across devices.
    static var iCloudModelDirectoryURL: URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: "iCloud.com.zincoverde.SPFSpectralAnalyzer")?
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
    }

    static var iCloudCompiledModelURL: URL? {
        iCloudModelDirectoryURL?.appendingPathComponent("SPFPredictor.mlmodelc", isDirectory: true)
    }

    static var iCloudTrainingResultURL: URL? {
        iCloudModelDirectoryURL?.appendingPathComponent("SPFPredictor_training.json")
    }

    /// Copy trained model to iCloud for cross-device availability.
    func syncModelToiCloud() {
        guard let iCloudDir = Self.iCloudModelDirectoryURL,
              let iCloudModel = Self.iCloudCompiledModelURL,
              let iCloudResult = Self.iCloudTrainingResultURL else {
            Instrumentation.log("iCloud container not available for model sync", area: .mlTraining, level: .warning)
            return
        }

        let fm = FileManager.default
        do {
            try fm.createDirectory(at: iCloudDir, withIntermediateDirectories: true)

            // Copy compiled model
            let localModel = Self.compiledModelURL
            if fm.fileExists(atPath: localModel.path) {
                if fm.fileExists(atPath: iCloudModel.path) {
                    try fm.removeItem(at: iCloudModel)
                }
                try fm.copyItem(at: localModel, to: iCloudModel)
            }

            // Copy training result
            let localResult = Self.trainingResultURL
            if fm.fileExists(atPath: localResult.path) {
                if fm.fileExists(atPath: iCloudResult.path) {
                    try fm.removeItem(at: iCloudResult)
                }
                try fm.copyItem(at: localResult, to: iCloudResult)
            }

            Instrumentation.log("ML model synced to iCloud", area: .mlTraining, level: .info)
        } catch {
            Instrumentation.log("Failed to sync ML model to iCloud", area: .mlTraining, level: .warning,
                                details: "error=\(error.localizedDescription)")
        }
    }

    // MARK: - Persisted Result

    private func loadPersistedResult() {
        // Try local App Support first
        if FileManager.default.fileExists(atPath: Self.trainingResultURL.path) {
            do {
                let data = try Data(contentsOf: Self.trainingResultURL)
                lastResult = try JSONDecoder().decode(MLTrainingResult.self, from: data)
                return
            } catch {
                Instrumentation.log("Failed to load ML training result", area: .mlTraining, level: .warning,
                                    details: "error=\(error.localizedDescription)")
            }
        }

        // Fall back to iCloud synced result (e.g. model trained on macOS, viewed on iPad)
        if let iCloudURL = Self.iCloudTrainingResultURL {
            if FileManager.default.fileExists(atPath: iCloudURL.path) {
                do {
                    let data = try Data(contentsOf: iCloudURL)
                    lastResult = try JSONDecoder().decode(MLTrainingResult.self, from: data)
                    return
                } catch {
                    Instrumentation.log("Failed to load iCloud training result", area: .mlTraining, level: .warning,
                                        details: "error=\(error.localizedDescription)")
                }
            } else {
                // Trigger download if file is in iCloud but not yet local
                try? FileManager.default.startDownloadingUbiquitousItem(at: iCloudURL)
            }
        }
    }

    private func persistResult(_ result: MLTrainingResult) {
        do {
            let data = try JSONEncoder().encode(result)
            try data.write(to: Self.trainingResultURL, options: .atomic)
            lastResult = result
        } catch {
            Instrumentation.log("Failed to persist ML training result", area: .mlTraining, level: .warning,
                                details: "error=\(error.localizedDescription)")
        }
    }

    // MARK: - Count Available Data

    /// Updates the count of available reference spectra for training.
    /// Uses a single batch query instead of per-dataset queries to avoid
    /// blocking the main thread with N+1 SwiftData fetches.
    func updateAvailableCount(modelContext: ModelContext) {
        let descriptor = FetchDescriptor<StoredDataset>(
            predicate: #Predicate<StoredDataset> { dataset in
                !dataset.isArchived && dataset.datasetRole == "reference" && dataset.knownInVivoSPF != nil
            }
        )
        do {
            let datasets = try modelContext.fetch(descriptor)
            let datasetIDs = Set(datasets.compactMap { $0.modelContext != nil ? $0.id : nil })
            guard !datasetIDs.isEmpty else {
                availableSpectrumCount = 0
                return
            }

            // Single batch fetch of all valid spectra, then count per dataset
            let allSpectra = try modelContext.fetch(FetchDescriptor<StoredSpectrum>())
            let count = allSpectra.count(where: { !$0.isInvalid && datasetIDs.contains($0.datasetID) })
            availableSpectrumCount = count
        } catch {
            availableSpectrumCount = 0
        }
    }

    // MARK: - Training

    /// Trains a boosted tree regressor from reference datasets.
    func train(modelContext: ModelContext) async {
        #if os(macOS)
        guard canTrain else { return }

        status = .preparingData
        Instrumentation.log("ML training started", area: .mlTraining, level: .info)

        // 1. Build training data on a background thread
        let buildResult: TrainingDataBuildResult
        do {
            buildResult = try await buildTrainingData(modelContext: modelContext)
        } catch {
            status = .failed("Data preparation failed: \(error.localizedDescription)")
            return
        }

        guard buildResult.rows.count >= Self.minimumSpectra else {
            status = .failed("Only \(buildResult.rows.count) spectra available, need at least \(Self.minimumSpectra)")
            return
        }

        // 2. Build DataFrame
        status = .training(progress: 0.1)
        let dataFrame: DataFrame
        do {
            dataFrame = try buildDataFrame(from: buildResult.rows)
        } catch {
            status = .failed("DataFrame build failed: \(error.localizedDescription)")
            return
        }

        // 3. Split for conformal calibration: 80% train, 20% calibration
        let shuffled = dataFrame.randomSplit(by: 0.8)
        let trainDF = shuffled.0
        let calibrationDF = shuffled.1

        // 4. Train the model
        status = .training(progress: 0.3)
        let regressor: MLBoostedTreeRegressor
        do {
            let params = MLBoostedTreeRegressor.ModelParameters(
                validation: .split(strategy: .automatic),
                maxDepth: 6,
                maxIterations: 200
            )
            regressor = try MLBoostedTreeRegressor(
                trainingData: DataFrame(trainDF),
                targetColumn: SPFModelSchema.targetColumn,
                featureColumns: SPFModelSchema.allFeatureColumns,
                parameters: params
            )
        } catch {
            status = .failed("Training failed: \(error.localizedDescription)")
            return
        }

        // 5. Evaluate
        status = .evaluating
        let trainMetrics = regressor.trainingMetrics
        let validationMetrics = regressor.validationMetrics

        let r2 = validationMetrics.isValid
            ? max(1.0 - (validationMetrics.rootMeanSquaredError * validationMetrics.rootMeanSquaredError)
                  / max(trainMetrics.rootMeanSquaredError * trainMetrics.rootMeanSquaredError, 1e-10), 0)
            : trainMetrics.isValid ? 0.0 : 0.0
        let rmse = validationMetrics.isValid ? validationMetrics.rootMeanSquaredError : trainMetrics.rootMeanSquaredError
        let maxErr = validationMetrics.isValid ? validationMetrics.maximumError : trainMetrics.maximumError

        // 6. Compute conformal residuals on calibration set
        let conformalResiduals = computeConformalResiduals(
            regressor: regressor,
            calibrationData: DataFrame(calibrationDF)
        )

        // 7. Save model
        do {
            let dir = Self.modelDirectoryURL
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            // Write .mlmodel source
            try regressor.write(to: Self.sourceModelURL)

            // Compile to .mlmodelc
            let compiledURL = try await MLModel.compileModel(at: Self.sourceModelURL)

            // Move compiled model to our models directory
            let targetURL = Self.compiledModelURL
            if FileManager.default.fileExists(atPath: targetURL.path) {
                try FileManager.default.removeItem(at: targetURL)
            }
            try FileManager.default.moveItem(at: compiledURL, to: targetURL)

            // Clean up source .mlmodel
            try? FileManager.default.removeItem(at: Self.sourceModelURL)
        } catch {
            status = .failed("Model save failed: \(error.localizedDescription)")
            return
        }

        // 8. Persist training result
        let result = MLTrainingResult(
            trainedAt: Date(),
            datasetCount: buildResult.datasetCount,
            spectrumCount: buildResult.rows.count,
            r2: r2,
            rmse: rmse,
            maxError: maxErr,
            conformalResiduals: conformalResiduals,
            featureColumns: SPFModelSchema.allFeatureColumns
        )
        persistResult(result)

        // 9. Notify prediction service to reload
        SPFPredictionService.shared.loadModelIfAvailable()

        // 10. Sync model to iCloud for cross-device availability (iPadOS/iOS)
        syncModelToiCloud()

        status = .complete
        Instrumentation.log("ML training complete", area: .mlTraining, level: .info,
                            details: "spectra=\(buildResult.rows.count) R²=\(String(format: "%.3f", r2)) RMSE=\(String(format: "%.2f", rmse))")

        #else
        status = .failed("Model training is only available on macOS")
        #endif
    }

    // MARK: - Reset

    /// Deletes the trained model and resets status.
    func resetModel() {
        let fm = FileManager.default
        try? fm.removeItem(at: Self.compiledModelURL)
        try? fm.removeItem(at: Self.sourceModelURL)
        try? fm.removeItem(at: Self.trainingResultURL)
        lastResult = nil
        status = .idle
        SPFPredictionService.shared.loadModelIfAvailable()
    }

    // MARK: - Training Data Builder

    #if os(macOS)

    private struct TrainingRow {
        let absorbance111: [Double]      // 111 spectral values
        let metrics: SpectralMetrics     // 7 derived metrics
        let plateType: Int
        let applicationQuantityMg: Double
        let formulationType: Int
        let isPostIrradiation: Int
        let spf: Double                  // target
    }

    private struct TrainingDataBuildResult {
        let rows: [TrainingRow]
        let datasetCount: Int
    }

    private func buildTrainingData(modelContext: ModelContext) async throws -> TrainingDataBuildResult {
        // Fetch reference datasets
        let descriptor = FetchDescriptor<StoredDataset>(
            predicate: #Predicate<StoredDataset> { dataset in
                !dataset.isArchived && dataset.datasetRole == "reference" && dataset.knownInVivoSPF != nil
            }
        )
        let datasets = try modelContext.fetch(descriptor)

        var rows: [TrainingRow] = []
        var datasetCount = 0

        for dataset in datasets {
            guard dataset.modelContext != nil else { continue }
            guard let labelSPF = dataset.knownInVivoSPF, labelSPF > 0 else { continue }
            let dsID = dataset.id
            let spectraPredicate = #Predicate<StoredSpectrum> { $0.datasetID == dsID && !$0.isInvalid }
            let spectra = (try? modelContext.fetch(FetchDescriptor<StoredSpectrum>(predicate: spectraPredicate))) ?? []
            guard !spectra.isEmpty else { continue }

            datasetCount += 1
            let plateTypeValue = (SubstratePlateType(rawValue: dataset.plateType ?? "") ?? .pmma)
            let formulationValue = (FormulationType(rawValue: dataset.formulationType ?? "") ?? .unknown)
            let appQty = dataset.applicationQuantityMg ?? 15.0  // Default ~15mg if not parsed

            for spectrum in spectra {
                let x = spectrum.xValues
                let y = spectrum.yValues

                // Resample to 290-400nm at 1nm (111 points)
                guard let resampled = SPFCalibration.resampleAbsorbance(
                    x: x, y: y, yAxisMode: .absorbance
                ) else { continue }

                // Compute spectral metrics
                guard let metrics = SpectralMetricsCalculator.metrics(
                    x: x, y: y, yAxisMode: .absorbance
                ) else { continue }

                // Use dataset manual override if set, else auto-detect from spectrum/dataset name
                let isPost = dataset.isPostIrradiation
                    ?? (FilenameMetadataParser.parse(filename: spectrum.name).isPostIrradiation
                        || FilenameMetadataParser.parse(filename: dataset.fileName).isPostIrradiation)

                rows.append(TrainingRow(
                    absorbance111: resampled,
                    metrics: metrics,
                    plateType: plateTypeValue == .pmma ? 0 : (plateTypeValue == .quartz ? 1 : 2),
                    applicationQuantityMg: appQty,
                    formulationType: formulationValue.featureValue,
                    isPostIrradiation: isPost ? 1 : 0,
                    spf: labelSPF
                ))
            }
        }

        return TrainingDataBuildResult(rows: rows, datasetCount: datasetCount)
    }

    private func buildDataFrame(from rows: [TrainingRow]) throws -> DataFrame {
        var columns: [String: [Double]] = [:]

        // Initialize all columns
        let allCols = SPFModelSchema.allFeatureColumns + [SPFModelSchema.targetColumn]
        for col in allCols {
            columns[col] = []
        }

        for row in rows {
            // 111 spectral features
            for i in 0..<SPFModelSchema.spectralFeatureCount {
                let colName = SPFModelSchema.spectralFeatureColumns[i]
                columns[colName]?.append(i < row.absorbance111.count ? row.absorbance111[i] : 0)
            }

            // 7 derived metrics
            columns["critical_wavelength"]?.append(row.metrics.criticalWavelength)
            columns["uva_uvb_ratio"]?.append(row.metrics.uvaUvbRatio)
            columns["uvb_area"]?.append(row.metrics.uvbArea)
            columns["uva_area"]?.append(row.metrics.uvaArea)
            columns["mean_uvb_transmittance"]?.append(row.metrics.meanUVBTransmittance)
            columns["mean_uva_transmittance"]?.append(row.metrics.meanUVATransmittance)
            columns["peak_absorbance_wavelength"]?.append(row.metrics.peakAbsorbanceWavelength)

            // 4 auxiliary features
            columns["plate_type"]?.append(Double(row.plateType))
            columns["application_quantity_mg"]?.append(row.applicationQuantityMg)
            columns["formulation_type"]?.append(Double(row.formulationType))
            columns["is_post_irradiation"]?.append(Double(row.isPostIrradiation))

            // Target
            columns["spf"]?.append(row.spf)
        }

        // Build DataFrame
        var dataFrame = DataFrame()
        for col in allCols {
            guard let values = columns[col] else { continue }
            dataFrame.append(column: Column<Double>(name: col, contents: values))
        }
        return dataFrame
    }

    private func computeConformalResiduals(regressor: MLBoostedTreeRegressor, calibrationData: DataFrame) -> [Double] {
        let model = regressor.model
        var residuals: [Double] = []

        let targetColumn = SPFModelSchema.targetColumn
        guard calibrationData.columns.contains(where: { $0.name == targetColumn }) else {
            return []
        }

        for rowIndex in 0..<calibrationData.rows.count {
            let row = calibrationData.rows[rowIndex]

            // Build feature dictionary for this row
            var featureDict: [String: MLFeatureValue] = [:]
            for col in SPFModelSchema.allFeatureColumns {
                if let value = row[col, Double.self] {
                    featureDict[col] = MLFeatureValue(double: value)
                } else {
                    featureDict[col] = MLFeatureValue(double: 0)
                }
            }

            do {
                let provider = try MLDictionaryFeatureProvider(dictionary: featureDict)
                let prediction = try model.prediction(from: provider)
                if let predicted = prediction.featureValue(for: targetColumn)?.doubleValue,
                   let actual = row[targetColumn, Double.self] {
                    residuals.append(abs(predicted - actual))
                }
            } catch {
                continue
            }
        }

        return residuals.sorted()
    }

    #endif
}
