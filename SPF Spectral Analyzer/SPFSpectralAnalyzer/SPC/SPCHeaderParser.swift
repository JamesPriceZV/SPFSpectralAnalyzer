import Foundation

struct SPCFileTypeFlags: Codable {
    let rawValue: UInt8

    var yIs16Bit: Bool { (rawValue & 0x01) != 0 }
    var usesExperimentExtension: Bool { (rawValue & 0x02) != 0 }
    var isMultiFile: Bool { (rawValue & 0x04) != 0 }
    var hasRandomZValues: Bool { (rawValue & 0x08) != 0 }
    var hasPerSubfileX: Bool { (rawValue & 0x40) != 0 }
    var isXYFile: Bool { (rawValue & 0x80) != 0 }

    var labels: [String] {
        var output: [String] = []
        output.append(yIs16Bit ? "Y 16-bit" : "Y 32-bit")
        if usesExperimentExtension { output.append("Experiment ext") }
        if isMultiFile { output.append("Multifile") }
        if hasRandomZValues { output.append("Random Z") }
        if hasPerSubfileX { output.append("Per-subfile X") }
        if isXYFile { output.append("XY file") }
        return output
    }
}

struct SPCUnitCode: Codable {
    let rawValue: UInt8

    var label: String {
        SPCUnitCode.label(for: rawValue)
    }

    var formatted: String {
        "\(label) (code \(rawValue))"
    }

    static func label(for code: UInt8) -> String {
        switch code {
        case 0: return "Arbitrary"
        case 1: return "Wavenumber (cm-1)"
        case 2: return "Micrometers (um)"
        case 3: return "Nanometers (nm)"
        case 4: return "Seconds"
        case 5: return "Minutes"
        case 6: return "Hertz (Hz)"
        case 7: return "Kilohertz (kHz)"
        case 8: return "Megahertz (MHz)"
        case 9: return "Mass (m/z)"
        case 10: return "Parts per million (PPM)"
        case 11: return "Days"
        case 12: return "Years"
        case 13: return "Raman Shift (cm-1)"
        case 14: return "eV"
        case 15: return "XYZ text labels"
        case 16: return "Diode Number"
        case 17: return "Channel"
        case 18: return "Degrees"
        case 19: return "Temperature (F)"
        case 20: return "Temperature (C)"
        case 21: return "Temperature (K)"
        case 22: return "Data Points"
        case 23: return "Milliseconds"
        case 24: return "Microseconds"
        case 25: return "Nanoseconds"
        case 26: return "Gigahertz (GHz)"
        case 27: return "Centimeters (cm)"
        case 28: return "Meters (m)"
        case 29: return "Millimeters (mm)"
        case 30: return "Hours"
        default: return "Unknown"
        }
    }
}

struct SPCYUnitCode: Codable {
    let rawValue: UInt8

    var label: String {
        SPCYUnitCode.label(for: rawValue)
    }

    var formatted: String {
        "\(label) (code \(rawValue))"
    }

    static func label(for code: UInt8) -> String {
        switch code {
        case 0: return "Arbitrary Intensity"
        case 1: return "Interferogram"
        case 2: return "Absorbance"
        case 3: return "Kubelka-Munk"
        case 4: return "Counts"
        case 5: return "Volts"
        case 6: return "Degrees"
        case 7: return "Milliamps"
        case 8: return "Millimeters"
        case 9: return "Millivolts"
        case 10: return "Log(1/R)"
        case 11: return "Percent"
        case 12: return "Intensity"
        case 13: return "Relative Intensity"
        case 14: return "Energy"
        case 16: return "Decibel"
        case 19: return "Temperature (F)"
        case 20: return "Temperature (C)"
        case 21: return "Temperature (K)"
        case 22: return "Index of Refraction [N]"
        case 23: return "Extinction Coeff. [K]"
        case 24: return "Real"
        case 25: return "Imaginary"
        case 26: return "Complex"
        case 128: return "Transmission"
        case 129: return "Reflectance"
        case 130: return "Arbitrary or Single Beam with Valley Peaks"
        case 131: return "Emission"
        default: return "Unknown"
        }
    }
}

struct SPCExperimentTypeCode: Codable {
    let rawValue: UInt8

    var label: String {
        switch rawValue {
        case 0: return "General SPC"
        case 1: return "Gas Chromatogram"
        case 2: return "General Chromatogram"
        case 3: return "HPLC Chromatogram"
        case 4: return "FT-IR/FT-NIR/FT-Raman Spectrum or Igram"
        case 5: return "NIR Spectrum"
        case 6: return "UV-VIS Spectrum"
        case 7: return "X-ray Diffraction Spectrum"
        case 8: return "Mass Spectrum"
        case 9: return "NMR Spectrum or FID"
        case 10: return "Raman Spectrum"
        case 11: return "Fluorescence Spectrum"
        case 12: return "Atomic Spectrum"
        case 13: return "Chromatography Diode Array Spectra"
        default: return "Unknown"
        }
    }
}

struct SPCCompressedDate: Codable, Sendable {
    let rawValue: Int32
    let year: Int
    let month: Int
    let day: Int
    let hour: Int
    let minute: Int

    nonisolated init(rawValue: Int32) {
        self.rawValue = rawValue
        let value = UInt32(bitPattern: rawValue)
        minute = Int(value & 0x3F)
        hour = Int((value >> 6) & 0x1F)
        day = Int((value >> 11) & 0x1F)
        month = Int((value >> 16) & 0x0F)
        year = Int((value >> 20) & 0x0FFF)
    }
}

struct SPCMainHeader: Codable, Sendable {
    let fileTypeFlags: UInt8
    let spcVersion: UInt8
    let experimentTypeCode: UInt8
    let yExponent: Int8
    let pointCount: Int32
    let firstX: Double
    let lastX: Double
    let subfileCount: Int32
    let xUnitsCode: UInt8
    let yUnitsCode: UInt8
    let zUnitsCode: UInt8
    let postingDisposition: UInt8
    let compressedDate: SPCCompressedDate
    let resolutionText: String
    let sourceInstrumentText: String
    let peakPointNumber: UInt16
    let memo: String
    let customAxisCombined: String
    let customAxisX: String
    let customAxisY: String
    let customAxisZ: String
    let logBlockOffset: Int32
    let fileModificationFlag: Int32
    let processingCode: UInt8
    let calibrationLevelPlusOne: UInt8
    let subMethodInjectionNumber: UInt16
    let concentrationFactor: Float
    let methodFile: String
    let zSubfileIncrement: Float
    let wPlaneCount: Int32
    let wPlaneIncrement: Float
    let wAxisUnitsCode: UInt8

    var fileType: SPCFileTypeFlags { SPCFileTypeFlags(rawValue: fileTypeFlags) }
    var experimentType: SPCExperimentTypeCode { SPCExperimentTypeCode(rawValue: experimentTypeCode) }
    var xUnit: SPCUnitCode { SPCUnitCode(rawValue: xUnitsCode) }
    var yUnit: SPCYUnitCode { SPCYUnitCode(rawValue: yUnitsCode) }
    var zUnit: SPCUnitCode { SPCUnitCode(rawValue: zUnitsCode) }
    var wUnit: SPCUnitCode { SPCUnitCode(rawValue: wAxisUnitsCode) }
}

enum SPCHeaderParser {
    nonisolated static func parseMainHeader(from data: Data) -> SPCMainHeader? {
        guard data.count >= 324 else { return nil }

        let fileTypeFlags = data.readUInt8(at: 0)
        let spcVersion = data.readUInt8(at: 1)
        let experimentTypeCode = data.readUInt8(at: 2)
        let yExponent = data.readInt8(at: 3)
        let pointCount = data.readInt32LE(at: 4)
        let firstX = data.readDoubleLE(at: 8)
        let lastX = data.readDoubleLE(at: 15)
        let subfileCount = data.readInt32LE(at: 23)
        let xUnitsCode = data.readUInt8(at: 27)
        let yUnitsCode = data.readUInt8(at: 28)
        let zUnitsCode = data.readUInt8(at: 29)
        let postingDisposition = data.readUInt8(at: 30)
        let compressedDateRaw = data.readInt32LE(at: 31)
        let resolutionText = data.readString(at: 35, length: 9)
        let sourceInstrumentText = data.readString(at: 43, length: 9)
        let peakPointNumber = data.readUInt16LE(at: 52)
        let memo = data.readString(at: 86, length: 130)
        let customAxisCombined = data.readString(at: 216, length: 30)
        let axisParts = customAxisCombined.chunked(into: 10)
        let customAxisX = axisParts.indices.contains(0) ? axisParts[0] : ""
        let customAxisY = axisParts.indices.contains(1) ? axisParts[1] : ""
        let customAxisZ = axisParts.indices.contains(2) ? axisParts[2] : ""
        let logBlockOffset = data.readInt32LE(at: 246)
        let fileModificationFlag = data.readInt32LE(at: 250)
        let processingCode = data.readUInt8(at: 254)
        let calibrationLevelPlusOne = data.readUInt8(at: 255)
        let subMethodInjectionNumber = data.readUInt16LE(at: 256)
        let concentrationFactor = data.readFloatLE(at: 258)
        let methodFile = data.readString(at: 262, length: 48)
        let zSubfileIncrement = data.readFloatLE(at: 310)
        let wPlaneCount = data.readInt32LE(at: 314)
        let wPlaneIncrement = data.readFloatLE(at: 318)
        let wAxisUnitsCode = data.readUInt8(at: 322)

        return SPCMainHeader(
            fileTypeFlags: fileTypeFlags,
            spcVersion: spcVersion,
            experimentTypeCode: experimentTypeCode,
            yExponent: yExponent,
            pointCount: pointCount,
            firstX: firstX,
            lastX: lastX,
            subfileCount: subfileCount,
            xUnitsCode: xUnitsCode,
            yUnitsCode: yUnitsCode,
            zUnitsCode: zUnitsCode,
            postingDisposition: postingDisposition,
            compressedDate: SPCCompressedDate(rawValue: compressedDateRaw),
            resolutionText: resolutionText,
            sourceInstrumentText: sourceInstrumentText,
            peakPointNumber: peakPointNumber,
            memo: memo,
            customAxisCombined: customAxisCombined,
            customAxisX: customAxisX,
            customAxisY: customAxisY,
            customAxisZ: customAxisZ,
            logBlockOffset: logBlockOffset,
            fileModificationFlag: fileModificationFlag,
            processingCode: processingCode,
            calibrationLevelPlusOne: calibrationLevelPlusOne,
            subMethodInjectionNumber: subMethodInjectionNumber,
            concentrationFactor: concentrationFactor,
            methodFile: methodFile,
            zSubfileIncrement: zSubfileIncrement,
            wPlaneCount: wPlaneCount,
            wPlaneIncrement: wPlaneIncrement,
            wAxisUnitsCode: wAxisUnitsCode
        )
    }
}

private extension Data {
    nonisolated func readUInt8(at offset: Int) -> UInt8 {
        guard offset < count else { return 0 }
        return self[offset]
    }

    nonisolated func readInt8(at offset: Int) -> Int8 {
        Int8(bitPattern: readUInt8(at: offset))
    }

    nonisolated func readUInt16LE(at offset: Int) -> UInt16 {
        guard offset + 1 < count else { return 0 }
        return withUnsafeBytes { rawPtr in
            rawPtr.load(fromByteOffset: offset, as: UInt16.self).littleEndian
        }
    }

    nonisolated func readInt32LE(at offset: Int) -> Int32 {
        guard offset + 3 < count else { return 0 }
        return withUnsafeBytes { rawPtr in
            Int32(bitPattern: rawPtr.load(fromByteOffset: offset, as: UInt32.self).littleEndian)
        }
    }

    nonisolated func readFloatLE(at offset: Int) -> Float {
        guard offset + 3 < count else { return 0 }
        return withUnsafeBytes { rawPtr in
            let bits = rawPtr.load(fromByteOffset: offset, as: UInt32.self).littleEndian
            return Float(bitPattern: bits)
        }
    }

    nonisolated func readDoubleLE(at offset: Int) -> Double {
        guard offset + 7 < count else { return 0 }
        return withUnsafeBytes { rawPtr in
            let bits = rawPtr.load(fromByteOffset: offset, as: UInt64.self).littleEndian
            return Double(bitPattern: bits)
        }
    }

    nonisolated func readString(at offset: Int, length: Int) -> String {
        guard offset < count else { return "" }
        let end = Swift.min(offset + length, count)
        let sub = self[offset..<end]
        if let string = String(data: sub, encoding: .ascii) {
            return string.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet.controlCharacters)
        }
        return ""
    }
}

private extension String {
    nonisolated func chunked(into size: Int) -> [String] {
        guard size > 0 else { return [] }
        var result: [String] = []
        var start = startIndex
        while start < endIndex {
            let end = index(start, offsetBy: size, limitedBy: endIndex) ?? endIndex
            result.append(String(self[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines))
            start = end
        }
        return result
    }
}
