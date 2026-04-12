import Foundation

enum GalacticSPCError: Error, CustomStringConvertible {
    case fileTooSmall
    case unsupportedVersion(UInt8)
    case noSubfiles
    case noPointsInSubfile
    case invalidYData

    var description: String {
        switch self {
        case .fileTooSmall:
            return "File too small for SPC format"
        case .unsupportedVersion(let v):
            return "Unsupported SPC version: 0x\(String(v, radix: 16))"
        case .noSubfiles:
            return "No subfiles found in SPC file"
        case .noPointsInSubfile:
            return "Subfile contains no data points"
        case .invalidYData:
            return "Invalid Y data in subfile"
        }
    }
}

/// Parser for standard Galactic/Thermo SPC spectral files.
/// Supports new format (version 0x4B) and old format (version 0x4D).
nonisolated final class GalacticSPCParser {
    private let data: Data
    private let fileURL: URL

    private static let headerSize = 512
    private static let subfileHeaderSize = 32

    /// Check if data begins with a recognized Galactic SPC version byte.
    static func canParse(_ data: Data) -> Bool {
        guard data.count >= headerSize else { return false }
        let version = data[1]
        return version == 0x4B || version == 0x4D || version == 0xCF
    }

    init(fileURL: URL) throws {
        self.fileURL = fileURL
        self.data = try Data(contentsOf: fileURL)
        guard data.count >= GalacticSPCParser.headerSize else {
            throw GalacticSPCError.fileTooSmall
        }
        let version = data[1]
        guard version == 0x4B || version == 0x4D || version == 0xCF else {
            throw GalacticSPCError.unsupportedVersion(version)
        }
    }

    func extractSpectraResult() throws -> ShimadzuSPCParseResult {
        let ftflgs = data[0]
        let fexp = Int8(bitPattern: data[3])
        let fnpts = readInt32(at: 4)
        let ffirst = readDouble(at: 8)
        let flast = readDouble(at: 16)
        let fnsub = readInt32(at: 24)

        let hasTXVALS = (ftflgs & 0x80) != 0       // shared X array after header
        let is16Bit = (ftflgs & 0x01) != 0
        let hasTXYXYS = (ftflgs & 0x40) != 0       // per-subfile X arrays

        let subfileCount = max(Int(fnsub), 1)
        let headerPointCount = Int(fnpts)

        // Read shared X array if TXVALS is set BUT TXYXYS is NOT set.
        // When TXYXYS is set, each subfile carries its own X — no shared array exists.
        var offset = GalacticSPCParser.headerSize
        var sharedXFromHeader: [Double]?
        if hasTXVALS && !hasTXYXYS && headerPointCount > 0 {
            let byteCount = headerPointCount * 4
            if offset + byteCount <= data.count {
                sharedXFromHeader = readFloats(at: offset, count: headerPointCount)
                offset += byteCount
            }
        }

        // Generate evenly-spaced X values when no explicit X data
        let evenX: [Double]? = (!hasTXVALS && !hasTXYXYS && headerPointCount > 1) ? generateEvenX(first: ffirst, last: flast, count: headerPointCount) : nil

        var spectra: [ShimadzuSPCRawSpectrum] = []

        for subIdx in 0..<subfileCount {
            guard offset + GalacticSPCParser.subfileHeaderSize <= data.count else { break }

            // Subfile header: 32 bytes
            // subexp at offset +1: per-subfile Y exponent (0x80 = use main fexp)
            // subnpts at offset +16: per-subfile point count
            let subexp = Int8(bitPattern: data[offset + 1])
            let subNpts = readInt32(at: offset + 16)
            let subPts: Int
            if subNpts > 0 {
                subPts = Int(subNpts)
            } else if headerPointCount > 0 {
                subPts = headerPointCount
            } else {
                // Both are zero — skip this subfile
                offset += GalacticSPCParser.subfileHeaderSize
                continue
            }

            offset += GalacticSPCParser.subfileHeaderSize

            // Determine effective Y exponent for this subfile:
            // - If fexp != 0, use fexp (main header controls all subfiles)
            // - If fexp == 0, use subexp per-subfile
            // - Effective exponent of -128 (0x80) means IEEE 32-bit floats
            let effectiveExp: Int8 = (fexp != 0) ? fexp : subexp

            let xValues: [Double]
            let yValues: [Double]

            if hasTXYXYS {
                // Per SPC spec: TXYXYS subfiles store X array FIRST, then Y array
                let xByteCount = subPts * 4
                guard offset + xByteCount <= data.count else { break }
                xValues = readFloats(at: offset, count: subPts)
                offset += xByteCount

                // Y data follows X data
                if effectiveExp == -128 { // 0x80: IEEE 32-bit floats
                    let byteCount = subPts * 4
                    guard offset + byteCount <= data.count else { break }
                    yValues = readFloats(at: offset, count: subPts)
                    offset += byteCount
                } else if is16Bit {
                    let byteCount = subPts * 2
                    guard offset + byteCount <= data.count else { break }
                    yValues = readInt16Y(at: offset, count: subPts, exponent: Int(effectiveExp))
                    offset += byteCount
                } else {
                    let byteCount = subPts * 4
                    guard offset + byteCount <= data.count else { break }
                    yValues = readInt32Y(at: offset, count: subPts, exponent: Int(effectiveExp))
                    offset += byteCount
                }
            } else {
                // Non-TXYXYS: Y data in subfile, X from shared array or evenly spaced
                if effectiveExp == -128 { // 0x80: IEEE 32-bit floats
                    let byteCount = subPts * 4
                    guard offset + byteCount <= data.count else { break }
                    yValues = readFloats(at: offset, count: subPts)
                    offset += byteCount
                } else if is16Bit {
                    let byteCount = subPts * 2
                    guard offset + byteCount <= data.count else { break }
                    yValues = readInt16Y(at: offset, count: subPts, exponent: Int(effectiveExp))
                    offset += byteCount
                } else {
                    let byteCount = subPts * 4
                    guard offset + byteCount <= data.count else { break }
                    yValues = readInt32Y(at: offset, count: subPts, exponent: Int(effectiveExp))
                    offset += byteCount
                }

                if let shared = sharedXFromHeader {
                    xValues = (subPts == shared.count) ? shared : generateEvenX(first: ffirst, last: flast, count: subPts)
                } else if let even = evenX {
                    xValues = (subPts == even.count) ? even : generateEvenX(first: ffirst, last: flast, count: subPts)
                } else {
                    xValues = generateEvenX(first: ffirst, last: flast, count: subPts)
                }
            }

            guard !yValues.isEmpty, xValues.count == yValues.count else { continue }

            let name: String
            if subfileCount == 1 {
                name = fileURL.deletingPathExtension().lastPathComponent
            } else {
                name = "\(fileURL.deletingPathExtension().lastPathComponent)_\(subIdx + 1)"
            }
            spectra.append(ShimadzuSPCRawSpectrum(name: name, x: xValues, y: yValues))
        }

        guard !spectra.isEmpty else { throw GalacticSPCError.noSubfiles }

        let mainHeader = SPCHeaderParser.parseMainHeader(from: data)
        let metadata = ShimadzuSPCMetadata(
            fileName: fileURL.lastPathComponent,
            fileSizeBytes: data.count,
            directoryEntryNames: [],
            dataSetNames: spectra.map(\.name),
            headerInfoByteCount: GalacticSPCParser.headerSize,
            mainHeader: mainHeader
        )

        return ShimadzuSPCParseResult(
            spectra: spectra,
            skippedDataSets: [],
            metadata: metadata,
            headerInfoData: data.prefix(GalacticSPCParser.headerSize)
        )
    }

    // MARK: - Private helpers

    private func generateEvenX(first: Double, last: Double, count: Int) -> [Double] {
        guard count > 1 else { return [first] }
        let step = (last - first) / Double(count - 1)
        return (0..<count).map { first + Double($0) * step }
    }

    private func readInt32(at offset: Int) -> Int32 {
        guard offset + 4 <= data.count else { return 0 }
        return data.withUnsafeBytes { ptr in
            Int32(bitPattern: ptr.load(fromByteOffset: offset, as: UInt32.self).littleEndian)
        }
    }

    private func readDouble(at offset: Int) -> Double {
        guard offset + 8 <= data.count else { return 0 }
        return data.withUnsafeBytes { ptr in
            Double(bitPattern: ptr.load(fromByteOffset: offset, as: UInt64.self).littleEndian)
        }
    }

    private func readFloats(at offset: Int, count: Int) -> [Double] {
        data.withUnsafeBytes { ptr in
            (0..<count).map { i in
                let bits = ptr.load(fromByteOffset: offset + i * 4, as: UInt32.self).littleEndian
                return Double(Float(bitPattern: bits))
            }
        }
    }

    private func readInt32Y(at offset: Int, count: Int, exponent: Int) -> [Double] {
        let scale = pow(2.0, Double(exponent)) / pow(2.0, 32.0)
        return data.withUnsafeBytes { ptr in
            (0..<count).map { i in
                let raw = Int32(bitPattern: ptr.load(fromByteOffset: offset + i * 4, as: UInt32.self).littleEndian)
                return Double(raw) * scale
            }
        }
    }

    private func readInt16Y(at offset: Int, count: Int, exponent: Int) -> [Double] {
        let scale = pow(2.0, Double(exponent)) / pow(2.0, 16.0)
        return data.withUnsafeBytes { ptr in
            (0..<count).map { i in
                let raw = Int16(bitPattern: ptr.load(fromByteOffset: offset + i * 2, as: UInt16.self).littleEndian)
                return Double(raw) * scale
            }
        }
    }
}
