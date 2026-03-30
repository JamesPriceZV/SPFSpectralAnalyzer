import SwiftUI

extension ContentView {

    var spfMathSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("SPF Math Details")
                    .font(.headline)
                Spacer()
                Button("Copy Math") {
                    copySpfMathToPasteboard()
                }
                #if os(macOS)
                .buttonStyle(.link)
                #else
                .buttonStyle(.borderless)
                #endif
                Button("Close") { showSpfMathDetails = false }
            }

            if let spectrum = analysis.selectedSpectrum, let metrics = analysis.selectedMetrics {
                let calibration = analysis.calibrationResult
                let activeMethod = SPFCalculationMethod(rawValue: spfCalculationMethodRawValue) ?? .colipa
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Spectrum info
                        GroupBox {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Spectrum: \(spectrum.name)")
                                    .font(.subheadline).bold()
                                Text("Y-Axis Mode: \(analysis.yAxisMode.rawValue)")
                                    .foregroundColor(.secondary)
                                Text("Calculation Method: \(activeMethod.label)")
                                    .foregroundColor(.secondary)
                                Text("UVB: 290–320 nm  |  UVA: 320–400 nm  |  Total: 290–400 nm")
                                    .foregroundColor(.secondary)
                            }
                        }

                        // Conversions
                        GroupBox("Absorbance / Transmittance Conversion") {
                            VStack(alignment: .leading, spacing: 6) {
                                if analysis.yAxisMode == .absorbance {
                                    Text("T(λ) = 10^(−A(λ))")
                                        .font(.system(.body, design: .monospaced))
                                    Text("Transmittance is the fraction of incident light passing through the sample. Absorbance and transmittance are related by the Beer-Lambert Law: higher absorbance means less light transmitted.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("A(λ) = −log₁₀(max(T(λ), 1×10⁻⁹))")
                                        .font(.system(.body, design: .monospaced))
                                    Text("Absorbance quantifies how much light the sample absorbs. The floor value (1×10⁻⁹) prevents log-of-zero errors for fully opaque samples.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Text("[Beer, A. (1852). Annalen der Physik, 162(5), 78–88; Swinehart, D.F. (1962). J. Chem. Educ., 39(7), 333.]")
                                    .font(.caption2).italic()
                                    .foregroundColor(.secondary)
                            }
                        }

                        // Integrated areas
                        GroupBox("Integrated Areas — Trapezoidal Rule") {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Area = Σᵢ ½ · (λᵢ₊₁ − λᵢ) · (A(λᵢ) + A(λᵢ₊₁))")
                                    .font(.system(.body, design: .monospaced))
                                Text("The absorbance curve is integrated over the UVB (290–320 nm) and UVA (320–400 nm) bands using the composite trapezoidal rule — each adjacent pair of data points forms a trapezoid whose area is summed. This numerical integration approximates the true integral of the spectral curve.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                HStack(spacing: 16) {
                                    Text(String(format: "UVB Area: %.4f", metrics.uvbArea))
                                    Text(String(format: "UVA Area: %.4f", metrics.uvaArea))
                                }
                                Text(String(format: "UVA/UVB Ratio: %.4f", metrics.uvaUvbRatio))
                                Text("The UVA/UVB ratio indicates the balance of UV protection. Values ≥ 0.33 satisfy the COLIPA UVA seal requirement.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("[COLIPA (2011). In Vitro UVA Method, Section 4.2; Atkinson, R. & Posner, B. (1993). Numerical Methods Using MATLAB.]")
                                    .font(.caption2).italic()
                                    .foregroundColor(.secondary)
                            }
                        }

                        // Critical wavelength
                        GroupBox("Critical Wavelength (λc)") {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("∫₂₉₀^λc A(λ) dλ  =  0.9 × ∫₂₉₀^400 A(λ) dλ")
                                    .font(.system(.body, design: .monospaced))
                                Text("The critical wavelength is the wavelength at which the cumulative absorbance from 290 nm reaches 90% of the total absorbance integrated from 290–400 nm. A λc ≥ 370 nm indicates broad-spectrum UVA protection, as required by EU, FDA, and COLIPA standards.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(String(format: "λc = %.2f nm", metrics.criticalWavelength))
                                    .font(.headline)
                                Text("[Diffey, B.L. (1994). 'A method for broad-spectrum classification of sunscreens.' Int. J. Cosmet. Sci., 16, 47–52; COLIPA (2011). In Vitro UVA Method, Section 5.1.]")
                                    .font(.caption2).italic()
                                    .foregroundColor(.secondary)
                            }
                        }

                        // Mean UVB transmittance
                        GroupBox("Mean UVB Transmittance") {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("T̄_UVB = (1/N) × Σ T(λᵢ)  for λ ∈ [290, 320]")
                                    .font(.system(.body, design: .monospaced))
                                Text("The arithmetic mean of transmittance values across the UVB band. Lower values indicate stronger UVB absorption. This value is used as a quick indicator of UVB protection efficiency.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(String(format: "Mean UVB T: %.4f", metrics.meanUVBTransmittance))
                            }
                        }

                        // SPF calculation (method-specific)
                        GroupBox("SPF Calculation — \(activeMethod.label)") {
                            VStack(alignment: .leading, spacing: 6) {
                                switch activeMethod {
                                case .colipa:
                                    Text("SPF = Σ E(λ)·S(λ) / Σ E(λ)·S(λ)·T(λ)")
                                        .font(.system(.body, design: .monospaced))
                                    Text("E(λ) is the CIE erythemal action spectrum weighting (how effectively each wavelength causes sunburn), and S(λ) is the solar spectral irradiance. T(λ) is the spectral transmittance of the sample. The ratio gives the protection factor: how much longer a person can stay in the sun without erythema compared to unprotected skin. Summation is performed at 1 nm intervals from 290–400 nm.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("[COLIPA (2011). 'In Vitro Method for the Determination of the UVA Protection Factor.' Cosmetics Europe, March 2011, Sections 3–5.]")
                                        .font(.caption2).italic()
                                        .foregroundColor(.secondary)
                                case .iso23675:
                                    Text("SPF = ∫₂₉₀⁴⁰⁰ E(λ)·I(λ) dλ  /  ∫₂₉₀⁴⁰⁰ E(λ)·I(λ)·T(λ) dλ")
                                        .font(.system(.body, design: .monospaced))
                                    Text("Uses the CIE standard erythemal action spectrum from ISO/CIE 17166:2019 combined with a reference mid-summer solar irradiance spectrum at 40°N latitude. The continuous integral is approximated numerically at 1 nm intervals. This method is aligned with the ISO 23675:2024 double-plate in-vitro test procedure.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("[ISO 23675:2024. 'Cosmetics — Sun protection test methods — In-vitro determination of sun protection factor'; ISO/CIE 17166:2019. 'Erythema reference action spectrum'.]")
                                        .font(.caption2).italic()
                                        .foregroundColor(.secondary)
                                case .mansur:
                                    Text("SPF = CF × Σ₂₉₀³²⁰ EE(λ)·I(λ)·Abs(λ)")
                                        .font(.system(.body, design: .monospaced))
                                    Text("A simplified spectrophotometric method using pre-calculated normalized EE×I (erythemal effect × solar intensity) constants at 5 nm intervals from 290–320 nm only. CF is a correction factor (typically 10). This is a rapid screening method suitable for formulation development but less accurate than full-spectrum methods for final product claims.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("[Mansur, J.S. et al. (1986). 'Determinação do fator de proteção solar por espectrofotometria.' An. Bras. Dermatol., 61, 121–124; Sayre, R.M. et al. (1979). Photochem. Photobiol., 29, 559–566.]")
                                        .font(.caption2).italic()
                                        .foregroundColor(.secondary)
                                }

                                Divider()
                                if let colipa = analysis.colipaSpfValue {
                                    Text(String(format: "Computed SPF: %.2f", colipa))
                                        .font(.headline)
                                } else {
                                    Text("SPF unavailable (requires data across \(activeMethod.wavelengthRange)).")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }

                        // Resolved SPF estimation
                        if let estimation = analysis.cachedSPFEstimation {
                            GroupBox("Resolved SPF Estimation") {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                                        Text(String(format: "SPF: %.1f", estimation.value))
                                            .font(.title2.bold())
                                        Text(estimation.tier.label)
                                            .font(.caption.bold())
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(estimation.tier.badgeColor.opacity(0.2))
                                            .foregroundColor(estimation.tier.badgeColor)
                                            .clipShape(RoundedRectangle(cornerRadius: 4))
                                    }
                                    if let raw = estimation.rawColipaValue {
                                        Text(String(format: "Raw %@ SPF: %.2f", activeMethod.label, raw))
                                            .foregroundColor(.secondary)
                                    }
                                    Text(estimation.details.explanation)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }

                        // Show only the calibration method that was actually used
                        if let estimation = analysis.cachedSPFEstimation,
                           estimation.details.nearestMatchDistance != nil,
                           let nm = analysis.cachedNearestMatch {
                            // C-coefficient nearest-reference was the active method
                            GroupBox("C-Coefficient Nearest-Reference Calibration (ISO 24443)") {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("C·A_ref(λ) → SPF_in_vitro(C·A_ref) = Label_SPF")
                                        .font(.system(.body, design: .monospaced))
                                    Text("SPF_sample = SPF_in_vitro(C·A_sample)")
                                        .font(.system(.body, design: .monospaced))
                                    Text("Finds the reference sample with the most similar spectral shape (cosine similarity on 111-point resampled absorbance, 290–400 nm at 1 nm intervals). Solves for C such that the in-vitro SPF of C × reference absorbance equals the reference's known label SPF, then applies the same C to the sample's absorbance.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("[ISO 24443:2021. 'Determination of sunscreen UVA photoprotection in vitro'; COLIPA (2011). In Vitro UVA Method, Annex B.]")
                                        .font(.caption2).italic()
                                        .foregroundColor(.secondary)

                                    Divider()
                                    Text("Nearest Reference: \(nm.matchedReferenceName.isEmpty ? "Unknown" : nm.matchedReferenceName)")
                                        .font(.subheadline.bold())
                                    Text(String(format: "Reference Label SPF: %.0f  •  Reference Raw SPF: %.2f", nm.matchedReferenceSPF, nm.matchedReferenceRawSPF))
                                        .foregroundColor(.secondary)
                                    Text(String(format: "Cosine Similarity: %.4f  •  Distance: %.4f", 1.0 - nm.distance, nm.distance))
                                        .foregroundColor(.secondary)
                                    if let c = nm.cCoefficient {
                                        Text(String(format: "C-Coefficient: %.4f", c))
                                            .font(.headline)
                                        Text(String(format: "C-Calibrated SPF: %.2f", nm.estimatedSPF))
                                            .font(.headline)
                                    } else {
                                        Text(String(format: "Proportional SPF: %.2f", nm.estimatedSPF))
                                            .font(.headline)
                                        Text("C-coefficient solver did not converge; using proportional scaling fallback.")
                                            .font(.caption)
                                            .foregroundColor(.orange)
                                    }
                                    Text(String(format: "References considered: %d", nm.sampleCount))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        } else if calibration != nil {
                            // OLS regression was the active method (or fallback)
                            GroupBox("OLS Regression Model") {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("ln(SPF) = b₀ + b₁·UVB_Area + b₂·UVA_Area + b₃·λc + b₄·(UVA/UVB) + b₅·T̄_UVB + b₆·T̄_UVA + b₇·Peak_λ")
                                        .font(.system(.body, design: .monospaced))
                                    Text("SPF_calibrated = exp(ln(SPF))")
                                        .font(.system(.body, design: .monospaced))
                                    Text("A multivariate ordinary-least-squares regression trained on your labeled samples. Each spectral metric serves as a predictor feature. The model fits coefficients (bᵢ) to minimize squared error between predicted log-SPF and actual log-SPF. R² measures goodness-of-fit (1.0 = perfect); RMSE measures typical prediction error in SPF units.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("[Draper, N.R. & Smith, H. (1998). Applied Regression Analysis, 3rd ed., Wiley; Montgomery, D.C. et al. (2012). Introduction to Linear Regression Analysis, 5th ed., Wiley.]")
                                        .font(.caption2).italic()
                                        .foregroundColor(.secondary)

                                    Divider()
                                    let features: [Double] = [
                                        1.0,
                                        metrics.uvbArea,
                                        metrics.uvaArea,
                                        metrics.criticalWavelength,
                                        metrics.uvaUvbRatio,
                                        metrics.meanUVBTransmittance,
                                        metrics.meanUVATransmittance,
                                        metrics.peakAbsorbanceWavelength
                                    ]
                                    let logSpf = zip(calibration!.coefficients, features).map(*).reduce(0, +)
                                    let predicted = max(exp(logSpf), 0.0)

                                    Text(String(format: "OLS Calibrated SPF: %.2f", predicted))
                                        .font(.headline)
                                    Text(String(format: "R² = %.3f  •  RMSE = %.2f  •  n = %d samples", calibration!.r2, calibration!.rmse, calibration!.sampleCount))
                                        .foregroundColor(.secondary)

                                    DisclosureGroup("Coefficients") {
                                        VStack(alignment: .leading, spacing: 4) {
                                            ForEach(Array(zip(calibration!.featureNames, calibration!.coefficients).enumerated()), id: \.offset) { _, item in
                                                Text(String(format: "%@: %.6f", item.0, item.1))
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                    }
                                    .font(.caption)
                                }
                            }
                        }
                    }
                    .padding(.bottom, 16)
                }
            } else {
                Text("No spectrum selected for correlation.")
                    .foregroundColor(.secondary)
            }
        }
        .padding(20)
        .frame(minWidth: 620, idealWidth: 720, minHeight: 560, idealHeight: 700)
    }

    var exportSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Export \(exportFormat.rawValue)")
                .font(.headline)
            exportFormFields
            HStack {
                Button("Cancel") { showExportSheet = false }
                Button("Export") {
                    let options = ExportOptions(
                        title: exportTitle,
                        operatorName: exportOperator,
                        notes: exportNotes,
                        includeProcessing: exportIncludeProcessing,
                        includeMetadata: exportIncludeMetadata
                    )
                    switch exportFormat {
                    case .csv:
                        exportCSV(options: options)
                    case .jcamp:
                        exportJCAMP(options: options)
                    case .excel:
                        exportExcelXLSX(options: options)
                    case .wordReport:
                        exportWordDOCX(options: options)
                    case .pdfReport:
                        exportPDFReport(options: options)
                    case .htmlReport:
                        exportHTMLReport(options: options)
                    }
                    showExportSheet = false
                }
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    var warningDetailsSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Skipped Datasets")
                .font(.headline)
            if analysis.warningDetails.isEmpty {
                Text("No skipped datasets reported.")
                    .foregroundColor(.secondary)
            } else {
                List(analysis.warningDetails, id: \.self) { detail in
                    Text(detail)
                }
            }
            HStack {
                Spacer()
                Button("Close") { showWarningDetails = false }
            }
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 360)
    }

    var invalidDetailsSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Invalid Spectra")
                .font(.headline)
            if analysis.invalidItems.isEmpty {
                Text("No invalid spectra reported.")
                    .foregroundColor(.secondary)
            } else {
                List(analysis.invalidItems) { item in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                                .font(.caption)
                            Text(item.fileName)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(item.reason)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        tagChip("Invalid")
                    }
                }
            }
            HStack {
                Spacer()
                Button("Close") { showInvalidDetails = false }
            }
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 360)
    }

    // MARK: - Sample Plate Type Sheet (HDRS)

    var samplePlateTypeSheet: some View {
        VStack(spacing: 16) {
            Text("Set as Prototype Sample")
                .font(.headline)

            Text("Enter the ISO 24443 metadata and HDRS plate type for this prototype sample dataset.")
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            // ISO 24443 Metadata
            VStack(spacing: 12) {
                Text("ISO 24443 Metadata")
                    .font(.subheadline.bold())
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)

                Grid(alignment: .trailing, verticalSpacing: 10) {
                    GridRow {
                        Text("Plate Type:")
                            .font(.subheadline)
                            .gridColumnAlignment(.trailing)
                        Picker("", selection: $datasets.pendingPlateType) {
                            ForEach(SubstratePlateType.allCases) { type in
                                Text(type.label).tag(type)
                            }
                        }
                        .labelsHidden()
                        #if os(macOS)
                        .pickerStyle(.segmented)
                        #endif
                        .gridColumnAlignment(.leading)
                    }

                    if datasets.pendingPlateType == .pmma {
                        GridRow {
                            Text("PMMA Subtype:")
                                .font(.subheadline)
                            Picker("", selection: $datasets.pendingPMMASubtype) {
                                ForEach(PMMAPlateSubtype.allCases) { subtype in
                                    Text(subtype.label).tag(subtype)
                                }
                            }
                            .labelsHidden()
                            #if os(macOS)
                            .pickerStyle(.segmented)
                            #endif
                        }
                    }

                    GridRow {
                        Text("Application (mg):")
                            .font(.subheadline)
                        HStack(spacing: 6) {
                            TextField("e.g. 14.5", value: $datasets.pendingApplicationQuantityMg, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 100)
                            Text("mg/cm²")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    GridRow {
                        Text("Formulation:")
                            .font(.subheadline)
                        Picker("", selection: $datasets.pendingFormulationType) {
                            ForEach(FormulationType.allCases.filter { $0 != .unknown }) { type in
                                Text(type.label).tag(type)
                            }
                        }
                        .labelsHidden()
                        #if os(macOS)
                        .pickerStyle(.menu)
                        #endif
                        .frame(width: 180, alignment: .leading)
                    }
                }
            }

            Divider()

            // HDRS Plate Type
            VStack(spacing: 8) {
                Text("HDRS Plate Type")
                    .font(.subheadline.bold())
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)

                Picker("Plate Type", selection: $datasets.pendingHDRSPlateType) {
                    ForEach(HDRSPlateType.allCases) { plateType in
                        Text(plateType.label).tag(plateType)
                    }
                }
                #if os(macOS)
                .pickerStyle(.radioGroup)
                #else
                .pickerStyle(.inline)
                #endif
            }

            Divider()

            // Formula Card
            VStack(spacing: 8) {
                Text("Formula Card")
                    .font(.subheadline.bold())
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)

                if let cardID = datasets.pendingFormulaCardID,
                   let card = datasets.formulaCards.first(where: { $0.id == cardID }) {
                    // Show attached card summary
                    HStack(spacing: 8) {
                        Image(systemName: "doc.text.fill")
                            .foregroundColor(.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(card.displayName)
                                .font(.subheadline)
                            if card.isParsed {
                                let count = card.ingredients.count
                                Text("\(count) ingredient\(count == 1 ? "" : "s") parsed")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                Text("Pending AI parsing")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                        Spacer()
                        Button("Remove") {
                            datasets.pendingFormulaCardID = nil
                        }
                        .foregroundColor(.red)
                        .font(.caption)
                    }
                    .padding(8)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                } else {
                    // Picker for existing formula cards + import new
                    HStack(spacing: 8) {
                        if !datasets.formulaCards.isEmpty {
                            Picker("", selection: $datasets.pendingFormulaCardID) {
                                Text("None").tag(UUID?.none)
                                ForEach(datasets.formulaCards) { card in
                                    Text(card.displayName).tag(Optional(card.id))
                                }
                            }
                            .labelsHidden()
                            #if os(macOS)
                            .pickerStyle(.menu)
                            #endif
                        }

                        Button {
                            datasets.showFormulaCardImporter = true
                        } label: {
                            Label("Import New...", systemImage: "doc.badge.plus")
                                .font(.subheadline)
                        }
                    }
                }
            }

            HStack(spacing: 12) {
                Button("Cancel") {
                    datasets.showSamplePlateTypeSheet = false
                    datasets.pendingRoleDatasetID = nil
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    if let datasetID = datasets.pendingRoleDatasetID {
                        datasets.setDatasetRole(
                            .prototype,
                            knownInVivoSPF: nil,
                            for: datasetID,
                            storedDatasets: storedDatasets
                        )
                        datasets.setDatasetMetadata(
                            plateType: datasets.pendingPlateType,
                            pmmaPlateSubtype: datasets.pendingPlateType == .pmma ? datasets.pendingPMMASubtype : nil,
                            applicationQuantityMg: datasets.pendingApplicationQuantityMg,
                            formulationType: datasets.pendingFormulationType,
                            for: datasetID,
                            storedDatasets: storedDatasets
                        )
                        datasets.setDatasetHDRSMetadata(
                            plateType: datasets.pendingHDRSPlateType,
                            for: datasetID,
                            storedDatasets: storedDatasets
                        )
                        if let cardID = datasets.pendingFormulaCardID {
                            datasets.setFormulaCard(
                                id: cardID,
                                for: datasetID,
                                storedDatasets: storedDatasets
                            )
                        }
                    }
                    datasets.showSamplePlateTypeSheet = false
                    datasets.pendingRoleDatasetID = nil
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 420, idealWidth: 480)
    }

    // MARK: - Assign Instrument Sheet

    var assignInstrumentSheet: some View {
        let datasetID = datasets.pendingInstrumentAssignDatasetID ?? UUID()
        let record = datasets.searchableRecordCache[datasetID]
        return AssignInstrumentSheet(
            datasetID: datasetID,
            sourceInstrumentText: record?.sourceInstrumentText,
            sourcePath: record?.sourcePath,
            storedDatasets: storedDatasets,
            onAssign: { instrumentID, batchAssign in
                if batchAssign {
                    datasets.assignInstrumentToBatch(instrumentID, for: datasetID, storedDatasets: storedDatasets)
                } else {
                    datasets.assignInstrument(instrumentID, to: datasetID, storedDatasets: storedDatasets)
                }
            }
        )
    }

    // MARK: - Reference SPF Assignment Sheet

    var referenceSpfSheet: some View {
        VStack(spacing: 16) {
            Text("Set as Reference Dataset")
                .font(.headline)

            Text("Enter the validated in-vivo SPF value and ISO 24443 metadata for this reference dataset.")
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            // Known SPF
            Grid(alignment: .trailing, verticalSpacing: 10) {
                GridRow {
                    Text("Known In-Vivo SPF:")
                        .font(.subheadline)
                        .gridColumnAlignment(.trailing)
                    TextField("SPF", value: $datasets.pendingKnownSPF, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                        .gridColumnAlignment(.leading)
                }
            }

            Divider()

            // ISO 24443 Metadata
            VStack(spacing: 12) {
                Text("ISO 24443 Metadata")
                    .font(.subheadline.bold())
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)

                Grid(alignment: .trailing, verticalSpacing: 10) {
                    GridRow {
                        Text("Plate Type:")
                            .font(.subheadline)
                            .gridColumnAlignment(.trailing)
                        Picker("", selection: $datasets.pendingPlateType) {
                            ForEach(SubstratePlateType.allCases) { type in
                                Text(type.label).tag(type)
                            }
                        }
                        .labelsHidden()
                        #if os(macOS)
                        .pickerStyle(.segmented)
                        #endif
                        .gridColumnAlignment(.leading)
                    }

                    if datasets.pendingPlateType == .pmma {
                        GridRow {
                            Text("PMMA Subtype:")
                                .font(.subheadline)
                            Picker("", selection: $datasets.pendingPMMASubtype) {
                                ForEach(PMMAPlateSubtype.allCases) { subtype in
                                    Text(subtype.label).tag(subtype)
                                }
                            }
                            .labelsHidden()
                            #if os(macOS)
                            .pickerStyle(.segmented)
                            #endif
                        }
                    }

                    GridRow {
                        Text("Application (mg):")
                            .font(.subheadline)
                        HStack(spacing: 6) {
                            TextField("e.g. 14.5", value: $datasets.pendingApplicationQuantityMg, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 100)
                            Text("mg/cm²")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    GridRow {
                        Text("Formulation:")
                            .font(.subheadline)
                        Picker("", selection: $datasets.pendingFormulationType) {
                            ForEach(FormulationType.allCases.filter { $0 != .unknown }) { type in
                                Text(type.label).tag(type)
                            }
                        }
                        .labelsHidden()
                        #if os(macOS)
                        .pickerStyle(.menu)
                        #endif
                        .frame(width: 180, alignment: .leading)
                    }
                }
            }

            HStack(spacing: 12) {
                Button("Cancel") {
                    datasets.showReferenceSpfSheet = false
                    datasets.pendingRoleDatasetID = nil
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    if let datasetID = datasets.pendingRoleDatasetID {
                        datasets.setDatasetRole(
                            .reference,
                            knownInVivoSPF: datasets.pendingKnownSPF,
                            for: datasetID,
                            storedDatasets: storedDatasets
                        )
                        datasets.setDatasetMetadata(
                            plateType: datasets.pendingPlateType,
                            pmmaPlateSubtype: datasets.pendingPlateType == .pmma ? datasets.pendingPMMASubtype : nil,
                            applicationQuantityMg: datasets.pendingApplicationQuantityMg,
                            formulationType: datasets.pendingFormulationType,
                            for: datasetID,
                            storedDatasets: storedDatasets
                        )
                    }
                    datasets.showReferenceSpfSheet = false
                    datasets.pendingRoleDatasetID = nil
                }
                .keyboardShortcut(.defaultAction)
                .disabled(datasets.pendingKnownSPF <= 0)
            }
        }
        .padding(24)
        .frame(minWidth: 420, idealWidth: 480)
    }

}
