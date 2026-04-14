// SPCParser.swift
// SPCKit
//
// Actor that reads raw SPC binary data from disk into an SPCFile struct.
// Handles both new format (0x4B, 512-byte header) and legacy LabCalc
// (0x4D, 256-byte header). Supports Y-only, XYY, and XYXY file types.

import Foundation
import Accelerate

// MARK: - SPCParserError

nonisolated public enum SPCParserError: Error, LocalizedError {
    case fileTooSmall(Int)
    case unsupportedVersion(UInt8)
    case invalidPointCount
    case subheaderOutOfBounds(index: Int)
    case dataOutOfBounds(offset: Int, needed: Int, available: Int)
    case invalidLogBlock
    case shimadzuNoSpectra
    case shimadzuMissingDataGroup

    public var errorDescription: String? {
        switch self {
        case let .fileTooSmall(size):
            return "File is too small to be a valid SPC file (\(size) bytes)."
        case let .unsupportedVersion(v):
            return "Unsupported SPC version byte: 0x\(String(v, radix: 16))."
        case .invalidPointCount:
            return "Invalid point count in SPC header."
        case let .subheaderOutOfBounds(i):
            return "Subfile \(i) header extends beyond file data."
        case let .dataOutOfBounds(offset, needed, available):
            return "Data read at offset \(offset) needs \(needed) bytes but only \(available) available."
        case .invalidLogBlock:
            return "Log block header is invalid or corrupt."
        case .shimadzuNoSpectra:
            return "No spectral data found in Shimadzu SPC file."
        case .shimadzuMissingDataGroup:
            return "Missing DataSetGroup in Shimadzu SPC file."
        }
    }
}

// MARK: - SPCParser

public actor SPCParser {

    // MARK: Public entry point

    /// Parses an SPC file at the given URL and returns the fully decoded SPCFile.
    public static func parse(url: URL) async throws -> SPCFile {
        let data = try Data(contentsOf: url)
        return try parse(data: data)
    }

    /// Parses raw SPC data synchronously. Nonisolated because no actor state is used.
    nonisolated public static func parse(data: Data) throws -> SPCFile {
        try SPCParserImpl.parseData(data)
    }
}

// MARK: - Implementation (nonisolated)

/// All parsing logic lives here as static methods so it can be called
/// synchronously from both the actor and FileDocument.init.
nonisolated private enum SPCParserImpl {

    static func parseData(_ data: Data) throws -> SPCFile {
        guard data.count >= 256 else {
            throw SPCParserError.fileTooSmall(data.count)
        }

        // Detect OLE2 Compound File (Shimadzu SPC) by magic signature
        if data.count >= 512,
           data[0] == 0xD0, data[1] == 0xCF, data[2] == 0x11, data[3] == 0xE0,
           data[4] == 0xA1, data[5] == 0xB1, data[6] == 0x1A, data[7] == 0xE1 {
            return try parseShimadzuFormat(data)
        }

        let version = data[1]
        switch version {
        case SPCVersion.newFormat.rawValue:
            guard data.count >= 512 else {
                throw SPCParserError.fileTooSmall(data.count)
            }
            return try parseNewFormat(data)
        case SPCVersion.labCalcLegacy.rawValue:
            return try parseLegacyFormat(data)
        default:
            // Try new format as best-effort for unknown version bytes
            if data.count >= 512 {
                return try parseNewFormat(data)
            }
            throw SPCParserError.unsupportedVersion(version)
        }
    }

    // MARK: - New format (0x4B, 512-byte header)

    private static func parseNewFormat(_ data: Data) throws -> SPCFile {
        let reader = BinaryReader(data: data)

        // --- Main header ---
        let header = try readMainHeader(reader, isLegacy: false)
        let fileType = resolveFileType(flags: header.flags)

        // --- Shared X block (XYY only) ---
        var cursor = 512
        var sharedX: [Float]?
        if fileType == .xyy {
            let xCount = Int(header.pointCount)
            let xBytes = xCount * 4
            guard cursor + xBytes <= data.count else {
                throw SPCParserError.dataOutOfBounds(
                    offset: cursor, needed: xBytes, available: data.count - cursor
                )
            }
            sharedX = reader.readFloatArray(at: cursor, count: xCount)
            cursor += xBytes
        }

        // --- Subfiles ---
        // Empty files (pointCount=0, subfileCount=0) are valid — return no subfiles.
        let subfileCount: Int
        if header.pointCount == 0 && header.subfileCount == 0 {
            subfileCount = 0
        } else {
            subfileCount = max(Int(header.subfileCount), 1)
        }
        var subfiles: [Subfile] = []
        subfiles.reserveCapacity(subfileCount)

        for i in 0 ..< subfileCount {
            guard cursor + 32 <= data.count else {
                throw SPCParserError.subheaderOutOfBounds(index: i)
            }
            let subhdr = readSubheader(reader, at: cursor)
            cursor += 32

            // Determine Y exponent for this subfile
            let effectiveExp = subhdr.yExponent != 0 ? subhdr.yExponent : header.yExponent

            // Determine point count
            let ptCount: Int
            if fileType == .xyxy {
                ptCount = subhdr.xyxyPointCount > 0
                    ? Int(subhdr.xyxyPointCount)
                    : Int(header.pointCount)
            } else {
                ptCount = Int(header.pointCount)
            }

            guard ptCount > 0 else {
                throw SPCParserError.invalidPointCount
            }

            // Per-subfile X array (XYXY only)
            var xPoints: [Float]?
            if fileType == .xyxy {
                let xBytes = ptCount * 4
                guard cursor + xBytes <= data.count else {
                    throw SPCParserError.dataOutOfBounds(
                        offset: cursor, needed: xBytes, available: data.count - cursor
                    )
                }
                xPoints = reader.readFloatArray(at: cursor, count: ptCount)
                cursor += xBytes
            } else if fileType == .xyy {
                xPoints = sharedX
            }

            // Y data
            let is16Bit = header.flags.contains(.y16Bit)
            let isFloat = effectiveExp == 0x80
            let yBytesPerPoint = is16Bit && !isFloat ? 2 : 4
            let yBytes = ptCount * yBytesPerPoint
            guard cursor + yBytes <= data.count else {
                throw SPCParserError.dataOutOfBounds(
                    offset: cursor, needed: yBytes, available: data.count - cursor
                )
            }

            let yPoints: [Float]
            if isFloat {
                yPoints = reader.readFloatArray(at: cursor, count: ptCount)
            } else if is16Bit {
                yPoints = decodeFixedPoint16(
                    reader: reader, at: cursor, count: ptCount, exponent: effectiveExp
                )
            } else {
                yPoints = decodeFixedPoint32(
                    reader: reader, at: cursor, count: ptCount, exponent: effectiveExp
                )
            }
            cursor += yBytes

            subfiles.append(Subfile(
                id: i,
                subheader: subhdr,
                xPoints: xPoints,
                yPoints: yPoints
            ))
        }

        // --- Log block (non-fatal: corrupt log should not prevent file open) ---
        var auditLog: [AuditLogEntry] = []
        var binaryLogData: Data?
        if header.logOffset > 0, Int(header.logOffset) + 64 <= data.count {
            do {
                let (entries, binData) = try readLogBlock(reader, at: Int(header.logOffset))
                auditLog = entries
                binaryLogData = binData
            } catch {
                // Log block is damaged but core spectral data is intact — continue
            }
        }

        // --- Axis metadata ---
        let (customX, customY, customZ) = parseCustomAxisLabels(header.customAxisLabels)
        let axisMetadata = AxisMetadata(
            xUnitsCode:   header.xUnitsCode,
            yUnitsCode:   header.yUnitsCode,
            zUnitsCode:   header.zUnitsCode,
            wUnitsCode:   header.wUnitsCode,
            customXLabel: customX,
            customYLabel: customY,
            customZLabel: customZ,
            firstX:       header.firstX,
            lastX:        header.lastX
        )

        return SPCFile(
            header:        header,
            axisMetadata:  axisMetadata,
            subfiles:      subfiles,
            auditLog:      auditLog,
            binaryLogData: binaryLogData
        )
    }

    // MARK: - Legacy format (0x4D, 256-byte header)

    private static func parseLegacyFormat(_ data: Data) throws -> SPCFile {
        let reader = BinaryReader(data: data)

        // Legacy header is 256 bytes with a different layout.
        // Map it into the same SPCMainHeader struct.
        let header = try readMainHeader(reader, isLegacy: true)

        let ptCount = Int(header.pointCount)
        guard ptCount > 0 else {
            throw SPCParserError.invalidPointCount
        }

        // Legacy files are always single-subfile, Y-only.
        let cursor = 256
        let isFloat = header.yExponent == 0x80
        let is16Bit = header.flags.contains(.y16Bit)
        let yBytesPerPoint = is16Bit && !isFloat ? 2 : 4
        let yBytes = ptCount * yBytesPerPoint
        guard cursor + yBytes <= data.count else {
            throw SPCParserError.dataOutOfBounds(
                offset: cursor, needed: yBytes, available: data.count - cursor
            )
        }

        let yPoints: [Float]
        if isFloat {
            yPoints = reader.readFloatArray(at: cursor, count: ptCount)
        } else if is16Bit {
            yPoints = decodeFixedPoint16(
                reader: reader, at: cursor, count: ptCount, exponent: header.yExponent
            )
        } else {
            yPoints = decodeFixedPoint32(
                reader: reader, at: cursor, count: ptCount, exponent: header.yExponent
            )
        }

        let subhdr = SPCSubheader(
            flags:          SPCSubfileFlags(rawValue: 0),
            yExponent:      header.yExponent,
            index:          0,
            zStart:         0,
            zEnd:           0,
            noiseValue:     0,
            xyxyPointCount: 0,
            coAddedScans:   0,
            wValue:         0
        )

        let subfile = Subfile(
            id:        0,
            subheader: subhdr,
            xPoints:   nil,
            yPoints:   yPoints
        )

        let axisMetadata = AxisMetadata(
            xUnitsCode:   header.xUnitsCode,
            yUnitsCode:   header.yUnitsCode,
            zUnitsCode:   header.zUnitsCode,
            wUnitsCode:   header.wUnitsCode,
            customXLabel: nil,
            customYLabel: nil,
            customZLabel: nil,
            firstX:       header.firstX,
            lastX:        header.lastX
        )

        return SPCFile(
            header:        header,
            axisMetadata:  axisMetadata,
            subfiles:      [subfile],
            auditLog:      [],
            binaryLogData: nil
        )
    }

    // MARK: - Shimadzu OLE2 format

    private static func parseShimadzuFormat(_ data: Data) throws -> SPCFile {
        let compound = try CompoundFileReader(data: data)

        // Navigate: Root Entry (0) → DataStorage1 → DataSetGroup
        guard let dataSetGroupIdx = compound.navigatePath(
            ["DataStorage1", "DataSetGroup"], from: 0
        ) else {
            throw SPCParserError.shimadzuMissingDataGroup
        }

        // Enumerate datasets within DataSetGroup
        let groupChildren = compound.childEntries(of: dataSetGroupIdx)
        let entries = compound.allDirectoryEntries()

        var subfiles: [Subfile] = []
        var subfileIndex = 0

        for childIdx in groupChildren {
            let childName = entries[childIdx].name
            // Skip the header info entry
            if childName == "DataSetGroupHeaderInfo" { continue }

            // Navigate: dataset → DataSpectrumStorage → Data
            guard let dataStorageIdx = compound.findChild(
                named: "DataSpectrumStorage", inStorageAt: childIdx
            ) else { continue }

            guard let dataIdx = compound.findChild(
                named: "Data", inStorageAt: dataStorageIdx
            ) else { continue }

            // Find X Data.1 and Y Data.1 streams
            let dataChildren = compound.childEntries(of: dataIdx)
            var xDoubles: [Double]?
            var yDoubles: [Double]?

            for streamIdx in dataChildren {
                let streamName = entries[streamIdx].name
                if streamName == "X Data.1" {
                    let streamData = try compound.streamData(at: streamIdx)
                    xDoubles = decodeDoubleArray(from: streamData)
                } else if streamName == "Y Data.1" {
                    let streamData = try compound.streamData(at: streamIdx)
                    yDoubles = decodeDoubleArray(from: streamData)
                }
            }

            guard let x = xDoubles, let y = yDoubles, !x.isEmpty, !y.isEmpty else {
                continue
            }

            // Convert [Double] to [Float] for our model
            let xFloats = x.map { Float($0) }
            let yFloats = y.map { Float($0) }

            let subhdr = SPCSubheader(
                flags:          SPCSubfileFlags(rawValue: 0),
                yExponent:      0x80,  // IEEE float
                index:          UInt16(subfileIndex),
                zStart:         0,
                zEnd:           0,
                noiseValue:     0,
                xyxyPointCount: UInt32(yFloats.count),
                coAddedScans:   0,
                wValue:         0
            )

            subfiles.append(Subfile(
                id:        subfileIndex,
                subheader: subhdr,
                xPoints:   xFloats,
                yPoints:   yFloats
            ))
            subfileIndex += 1
        }

        guard !subfiles.isEmpty else {
            throw SPCParserError.shimadzuNoSpectra
        }

        // Build axis metadata from the first subfile's X range
        let firstX = Double(subfiles[0].xPoints?.first ?? 0)
        let lastX  = Double(subfiles[0].xPoints?.last ?? 0)

        let header = SPCMainHeader(
            flags:                 SPCFileFlags(rawValue: 0x80 | 0x40),  // XY + XYXY
            version:               .newFormat,
            experimentType:        0,
            yExponent:             0x80,
            pointCount:            UInt32(subfiles[0].yPoints.count),
            firstX:                firstX,
            lastX:                 lastX,
            subfileCount:          UInt32(subfiles.count),
            xUnitsCode:            0,
            yUnitsCode:            0,
            zUnitsCode:            0,
            compressedDate:        0,
            resolutionDescription: "",
            sourceInstrument:      "Shimadzu",
            peakPoint:             0,
            memo:                  "Shimadzu OLE2 SPC file",
            customAxisLabels:      "",
            logOffset:             0,
            modificationFlag:      0,
            concentrationFactor:   0,
            methodFile:            "",
            zIncrement:            0,
            wPlaneCount:           0,
            wIncrement:            0,
            wUnitsCode:            0
        )

        let axisMetadata = AxisMetadata(
            xUnitsCode:   0,
            yUnitsCode:   0,
            zUnitsCode:   0,
            wUnitsCode:   0,
            customXLabel: nil,
            customYLabel: nil,
            customZLabel: nil,
            firstX:       firstX,
            lastX:        lastX
        )

        return SPCFile(
            header:        header,
            axisMetadata:  axisMetadata,
            subfiles:      subfiles,
            auditLog:      [],
            binaryLogData: nil
        )
    }

    /// Decodes raw Data as an array of little-endian Double values.
    private static func decodeDoubleArray(from data: Data) -> [Double] {
        guard data.count >= 8, data.count % 8 == 0 else { return [] }
        let count = data.count / 8
        var values: [Double] = []
        values.reserveCapacity(count)
        data.withUnsafeBytes { buf in
            for i in 0..<count {
                let bits = buf.loadUnaligned(fromByteOffset: i * 8, as: UInt64.self).littleEndian
                values.append(Double(bitPattern: bits))
            }
        }
        return values
    }

    // MARK: - Main header reading

    private static func readMainHeader(_ reader: BinaryReader, isLegacy: Bool) throws -> SPCMainHeader {
        if isLegacy {
            return readLegacyMainHeader(reader)
        }

        let flags              = SPCFileFlags(rawValue: reader.uint8(at: 0))
        let version            = SPCVersion(rawValue: reader.uint8(at: 1)) ?? .unknown
        let experimentType     = reader.uint8(at: 2)
        let yExponent          = reader.uint8(at: 3)
        let pointCount         = reader.uint32(at: 4)
        let firstX             = reader.float64(at: 8)
        let lastX              = reader.float64(at: 16)
        let subfileCount       = reader.uint32(at: 24)
        let xUnitsCode         = reader.uint8(at: 28)
        let yUnitsCode         = reader.uint8(at: 29)
        let zUnitsCode         = reader.uint8(at: 30)
        // Byte 31 is fpost (posting disposition) — skip it
        let compressedDate     = reader.uint32(at: 32)
        let resDesc            = reader.nullPaddedString(at: 36, length: 9)
        let sourceInst         = reader.nullPaddedString(at: 45, length: 9)
        let peakPoint          = reader.uint16(at: 54)
        let memo               = reader.nullPaddedString(at: 86, length: 130)
        let customAxisLabels   = reader.nullPaddedString(at: 216, length: 30)
        let logOffset          = reader.uint32(at: 246)
        let modificationFlag   = reader.uint32(at: 250)
        let concentrationFactor = reader.float32(at: 258)
        let methodFile         = reader.nullPaddedString(at: 262, length: 48)
        let zIncrement         = reader.float32(at: 310)
        let wPlaneCount        = reader.uint32(at: 314)
        let wIncrement         = reader.float32(at: 318)
        let wUnitsCode         = reader.uint8(at: 322)

        return SPCMainHeader(
            flags:                 flags,
            version:               version,
            experimentType:        experimentType,
            yExponent:             yExponent,
            pointCount:            pointCount,
            firstX:                firstX,
            lastX:                 lastX,
            subfileCount:          subfileCount,
            xUnitsCode:            xUnitsCode,
            yUnitsCode:            yUnitsCode,
            zUnitsCode:            zUnitsCode,
            compressedDate:        compressedDate,
            resolutionDescription: resDesc,
            sourceInstrument:      sourceInst,
            peakPoint:             peakPoint,
            memo:                  memo,
            customAxisLabels:      customAxisLabels,
            logOffset:             logOffset,
            modificationFlag:      modificationFlag,
            concentrationFactor:   concentrationFactor,
            methodFile:            methodFile,
            zIncrement:            zIncrement,
            wPlaneCount:           wPlaneCount,
            wIncrement:            wIncrement,
            wUnitsCode:            wUnitsCode
        )
    }

    private static func readLegacyMainHeader(_ reader: BinaryReader) -> SPCMainHeader {
        // Legacy LabCalc: 256-byte header, different layout.
        // Key offsets (from LabCalc spec):
        // 0: flags, 1: version (0x4D), 2: experiment, 3: yExponent
        // 4-7: pointCount (UInt32)
        // 8-15: firstX (Double), 16-23: lastX (Double)
        // 24-27: subfileCount (typically 1)
        // 28-30: axis codes
        // 86-215: memo (130 bytes)
        let flags           = SPCFileFlags(rawValue: reader.uint8(at: 0))
        let experimentType  = reader.uint8(at: 2)
        let yExponent       = reader.uint8(at: 3)
        let pointCount      = reader.uint32(at: 4)
        let firstX          = reader.float64(at: 8)
        let lastX           = reader.float64(at: 16)
        let xUnitsCode      = reader.uint8(at: 28)
        let yUnitsCode      = reader.uint8(at: 29)
        let zUnitsCode      = reader.uint8(at: 30)
        let memo            = reader.nullPaddedString(at: 86, length: 130)

        return SPCMainHeader(
            flags:                 flags,
            version:               .labCalcLegacy,
            experimentType:        experimentType,
            yExponent:             yExponent,
            pointCount:            pointCount,
            firstX:                firstX,
            lastX:                 lastX,
            subfileCount:          1,
            xUnitsCode:            xUnitsCode,
            yUnitsCode:            yUnitsCode,
            zUnitsCode:            zUnitsCode,
            compressedDate:        0,
            resolutionDescription: "",
            sourceInstrument:      "",
            peakPoint:             0,
            memo:                  memo,
            customAxisLabels:      "",
            logOffset:             0,
            modificationFlag:      0,
            concentrationFactor:   0,
            methodFile:            "",
            zIncrement:            0,
            wPlaneCount:           0,
            wIncrement:            0,
            wUnitsCode:            0
        )
    }

    // MARK: - Subheader reading

    private static func readSubheader(_ reader: BinaryReader, at offset: Int) -> SPCSubheader {
        SPCSubheader(
            flags:          SPCSubfileFlags(rawValue: reader.uint8(at: offset + 0)),
            yExponent:      reader.uint8(at: offset + 1),
            index:          reader.uint16(at: offset + 2),
            zStart:         reader.float32(at: offset + 4),
            zEnd:           reader.float32(at: offset + 8),
            noiseValue:     reader.float32(at: offset + 12),
            xyxyPointCount: reader.uint32(at: offset + 16),
            coAddedScans:   reader.uint32(at: offset + 20),
            wValue:         reader.float32(at: offset + 24)
        )
    }

    // MARK: - Fixed-point Y decoding

    private static func decodeFixedPoint32(
        reader: BinaryReader,
        at offset: Int,
        count: Int,
        exponent: UInt8
    ) -> [Float] {
        let exp = Int8(bitPattern: exponent)
        let scale = Float(pow(2.0, Double(exp) - 32.0))
        var result = [Float](repeating: 0, count: count)

        reader.data.withUnsafeBytes { buf in
            for i in 0 ..< count {
                let raw = Int32(littleEndian: buf.loadUnaligned(
                    fromByteOffset: offset + i * 4, as: Int32.self
                ))
                result[i] = Float(raw) * scale
            }
        }

        return result
    }

    private static func decodeFixedPoint16(
        reader: BinaryReader,
        at offset: Int,
        count: Int,
        exponent: UInt8
    ) -> [Float] {
        let exp = Int8(bitPattern: exponent)
        let scale = Float(pow(2.0, Double(exp) - 16.0))
        var result = [Float](repeating: 0, count: count)

        reader.data.withUnsafeBytes { buf in
            for i in 0 ..< count {
                let raw = Int16(littleEndian: buf.loadUnaligned(
                    fromByteOffset: offset + i * 2, as: Int16.self
                ))
                result[i] = Float(raw) * scale
            }
        }

        return result
    }

    // MARK: - Log block reading

    private static func readLogBlock(
        _ reader: BinaryReader,
        at logStart: Int
    ) throws -> ([AuditLogEntry], Data?) {
        guard logStart + 64 <= reader.data.count else {
            throw SPCParserError.invalidLogBlock
        }

        let logSize    = reader.uint32(at: logStart + 0)
        let textOffset = reader.uint32(at: logStart + 8)
        let binarySize = reader.uint32(at: logStart + 12)
        let textSize   = reader.uint32(at: logStart + 16)

        // Binary log data (e.g. NMR imaginary)
        var binaryLogData: Data?
        if binarySize > 0 {
            let binStart = logStart + 64
            let binEnd   = binStart + Int(binarySize)
            guard binEnd <= reader.data.count else {
                throw SPCParserError.invalidLogBlock
            }
            binaryLogData = reader.data[binStart ..< binEnd]
        }

        // ASCII audit log text
        var auditEntries: [AuditLogEntry] = []
        if textSize > 0, textOffset > 0 {
            let txtStart = logStart + Int(textOffset)
            let txtEnd   = min(txtStart + Int(textSize), reader.data.count)
            guard txtStart < txtEnd, txtStart < reader.data.count else {
                return (auditEntries, binaryLogData)
            }
            let textData = reader.data[txtStart ..< txtEnd]
            if let text = String(data: textData, encoding: .utf8)
                ?? String(data: textData, encoding: .ascii) {
                let lines = text.components(separatedBy: CharacterSet.newlines)
                for line in lines {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { continue }
                    auditEntries.append(AuditLogEntry(text: trimmed))
                }
            }
        }

        // Silence unused variable warning
        _ = logSize

        return (auditEntries, binaryLogData)
    }

    // MARK: - Helpers

    private static func resolveFileType(flags: SPCFileFlags) -> SPCFileType {
        if flags.contains(.xyxyMultifile) { return .xyxy }
        if flags.contains(.xyFile)        { return .xyy  }
        return .yOnly
    }

    private static func parseCustomAxisLabels(_ block: String) -> (String?, String?, String?) {
        guard !block.isEmpty else { return (nil, nil, nil) }
        let parts = block.split(separator: "\0", maxSplits: 2, omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
        let x = parts.count > 0 && !parts[0].isEmpty ? parts[0] : nil
        let y = parts.count > 1 && !parts[1].isEmpty ? parts[1] : nil
        let z = parts.count > 2 && !parts[2].isEmpty ? parts[2] : nil
        return (x, y, z)
    }
}

// MARK: - BinaryReader

/// Position-aware binary reader over a Data buffer using withUnsafeBytes.
nonisolated private struct BinaryReader: Sendable {
    let data: Data

    func uint8(at offset: Int) -> UInt8 {
        data[offset]
    }

    func uint16(at offset: Int) -> UInt16 {
        data.withUnsafeBytes { buf in
            buf.loadUnaligned(fromByteOffset: offset, as: UInt16.self).littleEndian
        }
    }

    func uint32(at offset: Int) -> UInt32 {
        data.withUnsafeBytes { buf in
            buf.loadUnaligned(fromByteOffset: offset, as: UInt32.self).littleEndian
        }
    }

    func float32(at offset: Int) -> Float {
        let bits = uint32(at: offset)
        return Float(bitPattern: bits)
    }

    func float64(at offset: Int) -> Double {
        data.withUnsafeBytes { buf in
            let bits = buf.loadUnaligned(fromByteOffset: offset, as: UInt64.self).littleEndian
            return Double(bitPattern: bits)
        }
    }

    func readFloatArray(at offset: Int, count: Int) -> [Float] {
        var result = [Float](repeating: 0, count: count)
        data.withUnsafeBytes { buf in
            let src = buf.baseAddress!.advanced(by: offset)
            _ = result.withUnsafeMutableBufferPointer { dst in
                memcpy(dst.baseAddress!, src, count * 4)
            }
        }
        // Convert from little-endian if needed (no-op on Apple platforms)
        #if _endian(big)
        for i in 0 ..< count {
            result[i] = Float(bitPattern: result[i].bitPattern.littleEndian)
        }
        #endif
        return result
    }

    func nullPaddedString(at offset: Int, length: Int) -> String {
        let end = min(offset + length, data.count)
        guard offset < end else { return "" }
        let slice = data[offset ..< end]
        // Find first null byte
        let nullIdx = slice.firstIndex(of: 0) ?? slice.endIndex
        let trimmed = slice[slice.startIndex ..< nullIdx]
        return String(data: Data(trimmed), encoding: .utf8)
            ?? String(data: Data(trimmed), encoding: .ascii)
            ?? ""
    }
}
