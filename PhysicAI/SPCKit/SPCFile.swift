// SPCFile.swift
// SPCKit
//
// Root value types that mirror the binary SPC format exactly.
// All types are Sendable structs — safe to cross actor boundaries
// without copying shared mutable state.

@preconcurrency import Foundation

// MARK: - Top-level file

/// The fully parsed, immutable representation of one SPC file on disk.
/// Never mutated after parsing; the EditSession holds all in-flight changes.
nonisolated public struct SPCFile: Sendable {

    /// Decoded 512-byte (new) or 256-byte (legacy) main header.
    public let header: SPCMainHeader

    /// Axis labelling resolved from both numeric code and custom string fields.
    public let axisMetadata: AxisMetadata

    /// All subfiles in file order. Single files have exactly one element.
    public let subfiles: [Subfile]

    /// Decoded ASCII audit log lines, in file order.
    public let auditLog: [AuditLogEntry]

    /// Raw binary log data (e.g. NMR imaginary component). Nil when absent.
    public let binaryLogData: Data?

    // MARK: Convenience

    public var isSingleFile: Bool { subfiles.count == 1 }
    public var isMultifile:  Bool { subfiles.count > 1 }

    public var fileType: SPCFileType {
        // Use literal bit masks to avoid OptionSet Equatable isolation issues.
        let raw = header.flags.rawValue
        if raw & 0x40 != 0 { return .xyxy }  // bit 6 = XYXY
        if raw & 0x80 != 0 { return .xyy  }  // bit 7 = XY
        return .yOnly
    }
}

// MARK: - File type

nonisolated public enum SPCFileType: Sendable, Equatable {
    /// Y-only: evenly spaced X, only Y stored. X computed from ffp/flp.
    case yOnly
    /// XYY: shared unevenly-spaced X array, one Y array per subfile.
    case xyy
    /// XYXY: each subfile has its own independent X and Y arrays.
    case xyxy

    public static func == (lhs: SPCFileType, rhs: SPCFileType) -> Bool {
        switch (lhs, rhs) {
        case (.yOnly, .yOnly), (.xyy, .xyy), (.xyxy, .xyxy): return true
        default: return false
        }
    }
}

// MARK: - Main header

/// Decoded representation of the 512-byte SPC main header block.
/// Field names and byte offsets match the spec document exactly.
nonisolated public struct SPCMainHeader: Sendable {

    // Byte 0 — file type flag byte decoded into an OptionSet
    public let flags: SPCFileFlags

    // Byte 1 — format version
    public let version: SPCVersion

    // Byte 2 — experiment type
    public let experimentType: UInt8

    // Byte 3 — Y exponent. 0x80 means stored as IEEE 754 float.
    public let yExponent: UInt8

    // Bytes 4–7 — point count (not used for XYXY; each subfile has its own)
    public let pointCount: UInt32

    // Bytes 8–15 — first X coordinate (double)
    public let firstX: Double

    // Bytes 16–23 — last X coordinate (double)
    public let lastX: Double

    // Bytes 24–27 — number of subfiles
    public let subfileCount: UInt32

    // Bytes 28–30 — axis unit codes
    public let xUnitsCode: UInt8
    public let yUnitsCode: UInt8
    public let zUnitsCode: UInt8

    // Byte 31–34 — compressed date: 6-bit minute, 5-bit hour, 5-bit day,
    //              4-bit month, 12-bit year packed into a UInt32
    public let compressedDate: UInt32

    /// Decoded from compressedDate. Nil if the packed value is zero (unset).
    public var fileDate: Date? {
        guard compressedDate != 0 else { return nil }
        let minute = Int((compressedDate >>  0) & 0x3F)
        let hour   = Int((compressedDate >>  6) & 0x1F)
        let day    = Int((compressedDate >> 11) & 0x1F)
        let month  = Int((compressedDate >> 16) & 0x0F)
        let year   = Int((compressedDate >> 20) & 0xFFF)
        guard year > 0, month > 0, day > 0 else { return nil }
        var comps        = DateComponents()
        comps.year       = year
        comps.month      = month
        comps.day        = day
        comps.hour       = hour
        comps.minute     = minute
        return Calendar(identifier: .gregorian).date(from: comps)
    }

    // Bytes 35–43 — resolution description (9 chars, null-padded)
    public let resolutionDescription: String

    // Bytes 43–52 — source instrument description (9 chars, null-padded)
    public let sourceInstrument: String

    // Byte 52–53 — peak point for interferograms
    public let peakPoint: UInt16

    // Bytes 86–215 — memo (130 chars)
    public let memo: String

    // Bytes 216–245 — custom axis label strings (combined 30-char block)
    public let customAxisLabels: String

    // Bytes 246–249 — byte offset into file where Log Block starts. 0 = no log.
    public let logOffset: UInt32

    // Bytes 250–253 — file modification flag
    public let modificationFlag: UInt32

    // Bytes 258–261 — floating multiplier concentration factor
    public let concentrationFactor: Float

    // Bytes 262–309 — method file path (48 chars)
    public let methodFile: String

    // Bytes 310–313 — Z increment for evenly-spaced multifiles
    public let zIncrement: Float

    // Bytes 314–317 — number of W planes (4-D data)
    public let wPlaneCount: UInt32

    // Bytes 318–321 — W plane increment
    public let wIncrement: Float

    // Byte 322 — W axis units code
    public let wUnitsCode: UInt8
}

// MARK: - File flags

/// Bit-field at byte 0 of the main header, decoded as an OptionSet.
nonisolated public struct SPCFileFlags: OptionSet, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    /// Bit 0 — Y data is stored in 16-bit precision (not 32-bit).
    public static let y16Bit       = SPCFileFlags(rawValue: 1 << 0)
    /// Bit 2 — Use experiment extension, not .spc.
    public static let useExperimentExtension = SPCFileFlags(rawValue: 1 << 2)
    /// Bit 4 — File is a Multifile.
    public static let multifile    = SPCFileFlags(rawValue: 1 << 4)
    /// Bit 8 — Multifile Z values are randomly ordered.
    public static let zRandom      = SPCFileFlags(rawValue: 1 << 3)  // bit 3 in the byte
    /// Bit 16 — Multifile Z values are ordered but not evenly spaced.
    public static let zOrdered     = SPCFileFlags(rawValue: 1 << 4)  // reused via zType
    /// Bit 64 — XYXY: each subfile has its own X array.
    public static let xyxyMultifile = SPCFileFlags(rawValue: 1 << 6)
    /// Bit 128 — XY file (unevenly spaced X).
    public static let xyFile       = SPCFileFlags(rawValue: 1 << 7)
}

// MARK: - SPC version

nonisolated public enum SPCVersion: UInt8, Sendable {
    /// New format (GRAMS, 512-byte header).
    case newFormat    = 0x4B
    /// Old LabCalc format (256-byte header, no multifile, no audit log).
    case labCalcLegacy = 0x4D
    /// Unknown — parser will attempt best-effort read.
    case unknown      = 0x00
}

// MARK: - Subfile

/// One spectrum within an SPC file. Single files have exactly one subfile.
nonisolated public struct Subfile: Sendable, Identifiable {

    /// Zero-based index in the file's subfile array.
    public let id: Int

    /// Decoded 32-byte subheader.
    public let subheader: SPCSubheader

    /// X values. Nil for Y-only files (X is computed from ffp/flp on demand).
    /// Non-nil for XYY (shared X) and XYXY (per-subfile X) files.
    public let xPoints: [Float]?

    /// Y values. Always present. Count matches xPoints.count (XY) or
    /// matches header.pointCount (Y-only).
    public let yPoints: [Float]

    // MARK: Convenience

    public var pointCount: Int { yPoints.count }

    /// Computes X array for Y-only files using the given header limits.
    /// Returns xPoints directly for XY files.
    public func resolvedXPoints(ffp: Double, flp: Double) -> [Float] {
        if let x = xPoints { return x }
        guard pointCount > 1 else { return [Float(ffp)] }
        let step = (flp - ffp) / Double(pointCount - 1)
        return (0 ..< pointCount).map { Float(ffp + Double($0) * step) }
    }

    /// Z start time/temperature/etc. for this subfile.
    public var zStart: Float { subheader.zStart }

    /// Z end for this subfile (allows for scan duration).
    public var zEnd:   Float { subheader.zEnd   }

    /// W axis value for 4-D data. Zero when W planes are not used.
    public var wValue: Float { subheader.wValue }
}

// MARK: - Subheader

/// Decoded 32-byte per-subfile header block.
nonisolated public struct SPCSubheader: Sendable {

    // Byte 1 — subfile flags
    public let flags: SPCSubfileFlags

    // Byte 2 — per-subfile Y exponent (overrides main header when non-zero)
    public let yExponent: UInt8

    // Bytes 3–4 — subfile index number
    public let index: UInt16

    // Bytes 5–8 — starting Z value (float)
    public let zStart: Float

    // Bytes 9–12 — ending Z value (float)
    public let zEnd: Float

    // Bytes 13–16 — noise value for peak picking
    public let noiseValue: Float

    // Bytes 17–20 — point count override for XYXY subfiles
    public let xyxyPointCount: UInt32

    // Bytes 21–24 — number of co-added scans
    public let coAddedScans: UInt32

    // Bytes 25–28 — W axis value for this subfile
    public let wValue: Float
}

// MARK: - Subfile flags

nonisolated public struct SPCSubfileFlags: OptionSet, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    /// Bit 1 — subfile has been changed.
    public static let changed       = SPCSubfileFlags(rawValue: 1 << 0)
    /// Bit 8 — do not use peak table file.
    public static let noPeakTable  = SPCSubfileFlags(rawValue: 1 << 3)
    /// Bit 128 — subfile modified by arithmetic.
    public static let arithmeticModified = SPCSubfileFlags(rawValue: 1 << 7)
}

// MARK: - Axis metadata

/// Resolved axis labels and unit codes for all three axes.
nonisolated public struct AxisMetadata: Sendable {

    public let xUnitsCode: UInt8
    public let yUnitsCode: UInt8
    public let zUnitsCode: UInt8
    public let wUnitsCode: UInt8

    /// Custom label strings parsed from the 30-byte combined block.
    /// These override the numeric codes when present.
    public let customXLabel: String?
    public let customYLabel: String?
    public let customZLabel: String?

    public let firstX: Double
    public let lastX:  Double

    /// Human-readable X axis label, preferring custom string over code lookup.
    public var xLabel: String { customXLabel ?? SPCAxisUnits.label(for: xUnitsCode, axis: .x) }
    public var yLabel: String { customYLabel ?? SPCAxisUnits.label(for: yUnitsCode, axis: .y) }
    public var zLabel: String { customZLabel ?? SPCAxisUnits.label(for: zUnitsCode, axis: .z) }
}

// MARK: - Axis unit code lookup

nonisolated public enum SPCAxisAxis { case x, y, z }

nonisolated public enum SPCAxisUnits {
    /// Returns a human-readable label for a SPC axis unit code.
    /// Codes are defined in SPC.H; common values are listed here.
    public static func label(for code: UInt8, axis: SPCAxisAxis) -> String {
        switch code {
        case 0:  return axis == .y ? "Arbitrary units" : "Arbitrary"
        case 1:  return "Wavenumber (cm⁻¹)"
        case 2:  return "Micrometers (μm)"
        case 3:  return "Nanometers (nm)"
        case 4:  return "Seconds"
        case 5:  return "Minutes"
        case 6:  return "Hertz (Hz)"
        case 7:  return "Kilohertz (kHz)"
        case 8:  return "Megahertz (MHz)"
        case 9:  return "Mass (M/z)"
        case 10: return "Parts per million (PPM)"
        case 11: return "Days"
        case 12: return "Years"
        case 13: return "Raman shift (cm⁻¹)"
        case 14: return "Electron volts (eV)"
        case 15: return "Real number"
        case 16: return "Imaginary number"
        case 17: return "Complex number"
        case 32: return "Transmission"
        case 33: return "Reflectance"
        case 34: return "Absorbance (log 1/R)"
        case 35: return "Kubelka-Munk"
        case 36: return "Counts"
        case 37: return "Volts"
        case 38: return "Degrees"
        case 39: return "Milliamps"
        case 40: return "Millimeters"
        case 41: return "Millivolts"
        case 42: return "Log(1/R)"
        case 43: return "Percent"
        case 44: return "Intensity"
        case 45: return "Relative intensity"
        case 46: return "Energy"
        case 48: return "Decibel (dB)"
        case 255: return "User defined"
        default: return "Unknown (\(code))"
        }
    }
}

// MARK: - Audit log

/// One decoded line from the ASCII Log Text block.
nonisolated public struct AuditLogEntry: Sendable, Identifiable {
    public let id: UUID
    public let text: String
    /// Detected ISO-8601 or common date prefix, if present in the line.
    public let detectedDate: Date?

    public init(text: String) {
        self.id   = UUID()
        self.text = text
        self.detectedDate = nil
    }

    public init(text: String, detectedDate: Date?) {
        self.id           = UUID()
        self.text         = text
        self.detectedDate = detectedDate
    }
}
