// SPCFileWriter.swift
// SPCKit
//
// Writes a valid SPC binary file from a resolved EditSession.
// Always writes to a new path — the source file is never overwritten.
//
// Write order (per spec):
//   1. 512-byte main header
//   2. XYY shared X block (if XYY)
//   3. For each subfile: 32-byte subheader + Y values (+ X if XYXY)
//   4. Directory block (if XYXY)
//   5. Log block header (64 bytes)
//   6. Binary log data (if any)
//   7. ASCII audit log text

import Foundation

// MARK: - SPCFileWriter

nonisolated public struct SPCFileWriter: Sendable {

    // MARK: - Public entry point

    /// Writes the fully resolved file to `url`.
    /// Appends all pending audit log entries.
    /// Throws on any I/O or data-integrity error.
    public static func write(
        session: EditSession,
        to url: URL
    ) async throws {
        // 1. Gather all resolved data from the session (actor-isolated calls)
        let subfiles     = await session.allResolvedSubfiles()
        let axisMeta     = await session.resolvedAxisMetadata()
        let memo         = await session.resolvedMemo()
        let auditEntries = await session.resolvedAuditLog()
        let source       = await session.sourcefile()
        let resolvedHdr  = await session.resolvedHeader()

        // 2. Determine output file type
        //    If any subfile now has an xPoints array and the source was Y-only,
        //    promote to XYY or XYXY as appropriate.
        let outputType = resolveOutputFileType(source: source, subfiles: subfiles)

        // 3. Build binary blocks
        var data = Data()

        let logOffset = computeLogOffset(subfiles: subfiles, fileType: outputType)
        let mainHeader = buildMainHeader(
            source:     source,
            resolvedHeader: resolvedHdr,
            subfiles:   subfiles,
            axisMeta:   axisMeta,
            memo:       memo,
            fileType:   outputType,
            logOffset:  logOffset
        )
        data.append(mainHeader)

        // XYY shared X block
        if outputType == .xyy, let firstX = subfiles.first?.xPoints {
            data.append(floatArrayToData(firstX))
        }

        // Per-subfile blocks + directory offset tracking for XYXY
        var directoryEntries: [(offset: UInt32, size: UInt32)] = []

        for subfile in subfiles {
            if outputType == .xyxy {
                let offsetBefore = UInt32(data.count)
                data.append(buildSubheader(subfile: subfile, fileType: outputType))
                let xyxyX = subfile.xPoints ?? []
                data.append(floatArrayToData(xyxyX))
                data.append(floatArrayToData(subfile.yPoints))
                let size = UInt32(data.count) - offsetBefore
                directoryEntries.append((offset: offsetBefore, size: size))
            } else {
                data.append(buildSubheader(subfile: subfile, fileType: outputType))
                data.append(floatArrayToData(subfile.yPoints))
            }
        }

        // Directory block for XYXY
        if outputType == .xyxy {
            data.append(buildDirectoryBlock(entries: directoryEntries))
        }

        // Log block
        let auditText  = auditEntries.map(\.text).joined(separator: "\r\n")
        let binaryData = source.binaryLogData ?? Data()
        data.append(buildLogBlock(binaryData: binaryData, auditText: auditText))

        // 4. Atomic write
        try data.write(to: url, options: .atomic)
    }

    /// Builds the SPC binary in memory and returns it as Data.
    /// Used by the cross-platform `.fileExporter` flow.
    public static func writeToData(
        session: EditSession
    ) async throws -> Data {
        let subfiles     = await session.allResolvedSubfiles()
        let axisMeta     = await session.resolvedAxisMetadata()
        let memo         = await session.resolvedMemo()
        let auditEntries = await session.resolvedAuditLog()
        let source       = await session.sourcefile()
        let resolvedHdr  = await session.resolvedHeader()

        let outputType = resolveOutputFileType(source: source, subfiles: subfiles)

        var data = Data()

        let logOffset = computeLogOffset(subfiles: subfiles, fileType: outputType)
        let mainHeader = buildMainHeader(
            source:     source,
            resolvedHeader: resolvedHdr,
            subfiles:   subfiles,
            axisMeta:   axisMeta,
            memo:       memo,
            fileType:   outputType,
            logOffset:  logOffset
        )
        data.append(mainHeader)

        if outputType == .xyy, let firstX = subfiles.first?.xPoints {
            data.append(floatArrayToData(firstX))
        }

        var directoryEntries: [(offset: UInt32, size: UInt32)] = []

        for subfile in subfiles {
            if outputType == .xyxy {
                let offsetBefore = UInt32(data.count)
                data.append(buildSubheader(subfile: subfile, fileType: outputType))
                let xyxyX = subfile.xPoints ?? []
                data.append(floatArrayToData(xyxyX))
                data.append(floatArrayToData(subfile.yPoints))
                let size = UInt32(data.count) - offsetBefore
                directoryEntries.append((offset: offsetBefore, size: size))
            } else {
                data.append(buildSubheader(subfile: subfile, fileType: outputType))
                data.append(floatArrayToData(subfile.yPoints))
            }
        }

        if outputType == .xyxy {
            data.append(buildDirectoryBlock(entries: directoryEntries))
        }

        let auditText  = auditEntries.map(\.text).joined(separator: "\r\n")
        let binaryData = source.binaryLogData ?? Data()
        data.append(buildLogBlock(binaryData: binaryData, auditText: auditText))

        return data
    }

    // MARK: - File type resolution

    private static func resolveOutputFileType(
        source: SPCFile,
        subfiles: [Subfile]
    ) -> SPCFileType {
        // If the source was XYXY, stay XYXY.
        if source.fileType == .xyxy { return .xyxy }
        // If any subfile now has an xPoints array (Y-only promoted), use XYY.
        if subfiles.contains(where: { $0.xPoints != nil }) { return .xyy }
        // Otherwise keep original type.
        return source.fileType
    }

    // MARK: - Main header builder

    private static func buildMainHeader(
        source:         SPCFile,
        resolvedHeader: SPCMainHeader,
        subfiles:       [Subfile],
        axisMeta:       AxisMetadata,
        memo:           String,
        fileType:       SPCFileType,
        logOffset:      UInt32
    ) -> Data {
        let rh = resolvedHeader
        var buf = Data(count: 512)

        // Byte 0 — file type flags
        var flags: UInt8 = 0
        if source.header.flags.contains(.y16Bit)         { flags |= 1 }
        if fileType == .xyxy                             { flags |= (1 << 6) }
        if fileType == .xyy || fileType == .xyxy         { flags |= (1 << 7) }
        if subfiles.count > 1                            { flags |= (1 << 4) }
        buf[0] = flags

        // Byte 1 — version (always write new format)
        buf[1] = SPCVersion.newFormat.rawValue

        // Byte 2 — experiment type (from resolved header)
        buf[2] = rh.experimentType

        // Byte 3 — Y exponent: 0x80 = floating point (GSPCIO always writes float)
        buf[3] = 0x80

        // Bytes 4–7 — point count (0 for XYXY; per-subfile in subheader)
        let pointCount: UInt32 = fileType == .xyxy ? 0 : UInt32(subfiles.first?.pointCount ?? 0)
        buf.replaceSubrange(4..<8, with: pointCount.littleEndianBytes)

        // Bytes 8–15 — first X (double)
        buf.replaceSubrange(8..<16, with: axisMeta.firstX.littleEndianBytes)

        // Bytes 16–23 — last X (double)
        buf.replaceSubrange(16..<24, with: axisMeta.lastX.littleEndianBytes)

        // Bytes 24–27 — subfile count
        buf.replaceSubrange(24..<28, with: UInt32(subfiles.count).littleEndianBytes)

        // Bytes 28–30 — axis unit codes
        buf[28] = axisMeta.xUnitsCode
        buf[29] = axisMeta.yUnitsCode
        buf[30] = axisMeta.zUnitsCode

        // Byte 31 — fpost (posting disposition, preserve as zero)

        // Bytes 32–35 — compressed date: preserve original
        buf.replaceSubrange(32..<36, with: rh.compressedDate.littleEndianBytes)

        // Bytes 36–44 — resolution description (9 bytes, null-padded)
        buf.writeNullPaddedString(rh.resolutionDescription, at: 36, length: 9)

        // Bytes 45–53 — source instrument (9 bytes)
        buf.writeNullPaddedString(rh.sourceInstrument, at: 45, length: 9)

        // Bytes 54–55 — peak point
        buf.replaceSubrange(54..<56, with: rh.peakPoint.littleEndianBytes)

        // Bytes 86–215 — memo (130 bytes, null-padded)
        buf.writeNullPaddedString(String(memo.prefix(130)), at: 86, length: 130)

        // Bytes 216–245 — custom axis labels (30 bytes, null-padded)
        let combined = buildCustomAxisLabelBlock(axisMeta: axisMeta)
        buf.writeNullPaddedString(combined, at: 216, length: 30)

        // Bytes 246–249 — log block offset
        buf.replaceSubrange(246..<250, with: logOffset.littleEndianBytes)

        // Bytes 250–253 — modification flag (increment)
        let newModFlag = rh.modificationFlag &+ 1
        buf.replaceSubrange(250..<254, with: newModFlag.littleEndianBytes)

        // Bytes 258–261 — concentration factor
        buf.replaceSubrange(258..<262, with: rh.concentrationFactor.littleEndianBytes)

        // Bytes 262–309 — method file (48 bytes)
        buf.writeNullPaddedString(rh.methodFile, at: 262, length: 48)

        // Bytes 310–313 — Z increment
        buf.replaceSubrange(310..<314, with: rh.zIncrement.littleEndianBytes)

        // Bytes 314–317 — W plane count
        buf.replaceSubrange(314..<318, with: rh.wPlaneCount.littleEndianBytes)

        // Bytes 318–321 — W increment
        buf.replaceSubrange(318..<322, with: rh.wIncrement.littleEndianBytes)

        // Byte 322 — W units code
        buf[322] = axisMeta.wUnitsCode

        return buf
    }

    // MARK: - Subheader builder

    private static func buildSubheader(subfile: Subfile, fileType: SPCFileType) -> Data {
        var buf = Data(count: 32)

        // Byte 0 — flags: mark as arithmetic-modified
        buf[0] = SPCSubfileFlags.arithmeticModified.rawValue

        // Byte 1 — Y exponent: 0x80 = IEEE 754 float
        buf[1] = 0x80

        // Bytes 2–3 — subfile index
        buf.replaceSubrange(2..<4, with: UInt16(subfile.id).littleEndianBytes)

        // Bytes 4–7 — Z start
        buf.replaceSubrange(4..<8, with: subfile.zStart.littleEndianBytes)

        // Bytes 8–11 — Z end
        buf.replaceSubrange(8..<12, with: subfile.zEnd.littleEndianBytes)

        // Bytes 12–15 — noise (preserve)
        buf.replaceSubrange(12..<16, with: subfile.subheader.noiseValue.littleEndianBytes)

        // Bytes 16–19 — XYXY point count (only meaningful for XYXY)
        let ptCount: UInt32 = fileType == .xyxy ? UInt32(subfile.pointCount) : 0
        buf.replaceSubrange(16..<20, with: ptCount.littleEndianBytes)

        // Bytes 20–23 — co-added scans (preserve)
        buf.replaceSubrange(20..<24, with: subfile.subheader.coAddedScans.littleEndianBytes)

        // Bytes 24–27 — W value (preserve)
        buf.replaceSubrange(24..<28, with: subfile.wValue.littleEndianBytes)

        return buf
    }

    // MARK: - Directory block (XYXY only)

    private static func buildDirectoryBlock(
        entries: [(offset: UInt32, size: UInt32)]
    ) -> Data {
        var buf = Data()
        for entry in entries {
            buf.append(contentsOf: entry.offset.littleEndianBytes)
            buf.append(contentsOf: entry.size.littleEndianBytes)
            buf.append(contentsOf: UInt32(0).littleEndianBytes) // reserved
        }
        return buf
    }

    // MARK: - Log block builder

    private static func buildLogBlock(binaryData: Data, auditText: String) -> Data {
        let textData    = Data((auditText + "\r\n").utf8)
        let textOffset  = UInt32(64 + binaryData.count)   // 64 = log header size
        let logSize     = UInt32(64 + binaryData.count + textData.count)
        // Round up to nearest 4096-byte multiple
        let memSize     = (logSize + 4095) & ~4095

        var header = Data(count: 64)
        header.replaceSubrange(0..<4,  with: logSize.littleEndianBytes)
        header.replaceSubrange(4..<8,  with: memSize.littleEndianBytes)
        header.replaceSubrange(8..<12, with: textOffset.littleEndianBytes)
        header.replaceSubrange(12..<16, with: UInt32(binaryData.count).littleEndianBytes)
        header.replaceSubrange(16..<20, with: UInt32(textData.count).littleEndianBytes)

        var block = Data()
        block.append(header)
        block.append(binaryData)
        block.append(textData)
        return block
    }

    // MARK: - Helpers

    private static func computeLogOffset(
        subfiles: [Subfile],
        fileType: SPCFileType
    ) -> UInt32 {
        var offset: UInt32 = 512  // main header

        if fileType == .xyy {
            let xCount = UInt32(subfiles.first?.xPoints?.count ?? 0)
            offset += xCount * 4  // single-precision floats
        }

        for subfile in subfiles {
            offset += 32  // subheader
            if fileType == .xyxy {
                offset += UInt32(subfile.pointCount) * 4  // X array
            }
            offset += UInt32(subfile.pointCount) * 4      // Y array
        }

        if fileType == .xyxy {
            offset += UInt32(subfiles.count) * 12  // directory: 3 × UInt32 per entry
        }

        return offset
    }

    private static func floatArrayToData(_ floats: [Float]) -> Data {
        var copy = floats
        return Data(bytes: &copy, count: copy.count * MemoryLayout<Float>.size)
    }

    private static func buildCustomAxisLabelBlock(axisMeta: AxisMetadata) -> String {
        // Spec packs X, Y, Z custom labels into a combined 30-char block.
        let x = axisMeta.customXLabel ?? ""
        let y = axisMeta.customYLabel ?? ""
        let z = axisMeta.customZLabel ?? ""
        return "\(x)\0\(y)\0\(z)"
    }

    // MARK: - Shimadzu CFB writer

    /// Builds Shimadzu OLE2/CFB binary in memory and returns it as Data.
    /// Structure mirrors the Shimadzu SPC layout:
    ///   Root Entry → DataStorage1 → DataSetGroup → [datasets]
    ///   Each dataset → DataSpectrumStorage → Data → X Data.1, Y Data.1
    public static func writeToShimadzuData(
        session: EditSession
    ) async throws -> Data {
        let subfiles = await session.allResolvedSubfiles()
        let axisMeta = await session.resolvedAxisMetadata()

        guard !subfiles.isEmpty else {
            throw ShimadzuWriterError.noSubfiles
        }

        // Resolve X arrays (Y-only subfiles get their X computed)
        let ffp = axisMeta.firstX
        let flp = axisMeta.lastX
        let resolved: [(x: [Double], y: [Double])] = subfiles.map { sub in
            let xFloats = sub.xPoints ?? sub.resolvedXPoints(ffp: ffp, flp: flp)
            return (xFloats.map { Double($0) }, sub.yPoints.map { Double($0) })
        }

        return try buildCFB(subfiles: resolved)
    }

    /// Builds a minimal CFB (Compound File Binary) file with Version 3 (512-byte sectors).
    private static func buildCFB(subfiles: [(x: [Double], y: [Double])]) throws -> Data {
        let sectorSize = 512
        let miniSectorSize = 64
        let miniStreamCutoff = 4096

        // Streams we need to write: for each subfile, X Data.1 and Y Data.1
        var streamDatas: [(dirIdx: Int, data: Data)] = []
        var dirs: [CFBDirEntry] = []

        // 0: Root Entry
        dirs.append(CFBDirEntry(name: "Root Entry", objectType: 5, childIndex: 1))
        // 1: DataStorage1
        dirs.append(CFBDirEntry(name: "DataStorage1", objectType: 1))
        // 2: DataSetGroup
        dirs.append(CFBDirEntry(name: "DataSetGroup", objectType: 1))

        dirs[0].childIndex = 1
        dirs[1].childIndex = 2

        // 3: DataSetGroupHeaderInfo (empty stream)
        let headerInfoIdx = dirs.count
        dirs.append(CFBDirEntry(name: "DataSetGroupHeaderInfo", objectType: 2))

        var datasetRootIndices: [Int] = []

        for (i, sub) in subfiles.enumerated() {
            let datasetIdx = dirs.count
            datasetRootIndices.append(datasetIdx)
            dirs.append(CFBDirEntry(name: "DataSet\(i)", objectType: 1))

            let specStorageIdx = dirs.count
            dirs.append(CFBDirEntry(name: "DataSpectrumStorage", objectType: 1))

            let dataStorageIdx = dirs.count
            dirs.append(CFBDirEntry(name: "Data", objectType: 1))

            let xStreamIdx = dirs.count
            let xData = doubleArrayToData(sub.x)
            dirs.append(CFBDirEntry(name: "X Data.1", objectType: 2, streamSize: UInt64(xData.count)))
            streamDatas.append((dirIdx: xStreamIdx, data: xData))

            let yStreamIdx = dirs.count
            let yData = doubleArrayToData(sub.y)
            dirs.append(CFBDirEntry(name: "Y Data.1", objectType: 2, streamSize: UInt64(yData.count)))
            streamDatas.append((dirIdx: yStreamIdx, data: yData))

            dirs[datasetIdx].childIndex = Int32(specStorageIdx)
            dirs[specStorageIdx].childIndex = Int32(dataStorageIdx)
            dirs[dataStorageIdx].childIndex = Int32(xStreamIdx)
            dirs[xStreamIdx].rightSibling = Int32(yStreamIdx)
        }

        // Wire DataSetGroup's children as a balanced binary tree
        var groupChildren = [headerInfoIdx] + datasetRootIndices
        let rootChild = assignBalancedTree(&dirs, children: &groupChildren)
        dirs[2].childIndex = Int32(rootChild)

        // Separate streams into regular (>= miniStreamCutoff) and mini
        var regularStreams: [(dirIdx: Int, data: Data)] = []
        var miniStreams: [(dirIdx: Int, data: Data)] = []
        for s in streamDatas {
            if s.data.count >= miniStreamCutoff {
                regularStreams.append(s)
            } else {
                miniStreams.append(s)
            }
        }

        // Build mini-stream blob
        var miniStreamBlob = Data()
        for i in 0..<miniStreams.count {
            let miniSectorStart = miniStreamBlob.count / miniSectorSize
            dirs[miniStreams[i].dirIdx].startSector = UInt32(miniSectorStart)
            miniStreamBlob.append(miniStreams[i].data)
            let remainder = miniStreamBlob.count % miniSectorSize
            if remainder != 0 {
                miniStreamBlob.append(Data(count: miniSectorSize - remainder))
            }
        }

        // Calculate sector layout
        var nextSector: UInt32 = 0

        // Regular streams
        for i in 0..<regularStreams.count {
            dirs[regularStreams[i].dirIdx].startSector = nextSector
            let count = (regularStreams[i].data.count + sectorSize - 1) / sectorSize
            nextSector += UInt32(count)
        }

        // Mini-stream blob → Root Entry's chain
        let miniStreamBlobStartSector = nextSector
        let miniStreamBlobSectorCount = miniStreamBlob.isEmpty
            ? 0
            : (miniStreamBlob.count + sectorSize - 1) / sectorSize
        if !miniStreamBlob.isEmpty {
            dirs[0].startSector = miniStreamBlobStartSector
            dirs[0].streamSize = UInt64(miniStreamBlob.count)
            nextSector += UInt32(miniStreamBlobSectorCount)
        }

        // Directory sectors
        let directorySectorStart = nextSector
        let entriesPerSector = sectorSize / 128
        let dirSectorCount = (dirs.count + entriesPerSector - 1) / entriesPerSector
        nextSector += UInt32(dirSectorCount)

        // Mini-FAT sectors
        let miniFATSectorStart = nextSector
        let totalMiniSectors = miniStreamBlob.count / miniSectorSize
        let miniFATSectorCount = totalMiniSectors > 0
            ? (totalMiniSectors * 4 + sectorSize - 1) / sectorSize
            : 0
        nextSector += UInt32(miniFATSectorCount)

        // FAT sectors (iterate to find stable count)
        let fatSectorStart = nextSector
        var fatSectorCount: UInt32 = 1
        while true {
            let total = nextSector + fatSectorCount
            let needed = (total * 4 + UInt32(sectorSize) - 1) / UInt32(sectorSize)
            if needed <= fatSectorCount { break }
            fatSectorCount = needed
        }
        let totalSectors = nextSector + fatSectorCount

        // Build FAT
        let endOfChain: UInt32 = 0xFFFFFFFE
        let fatSpecial: UInt32 = 0xFFFFFFFD
        let freeSect: UInt32   = 0xFFFFFFFF
        var fat = [UInt32](repeating: freeSect, count: Int(totalSectors))

        for rs in regularStreams {
            let start = dirs[rs.dirIdx].startSector
            let count = (rs.data.count + sectorSize - 1) / sectorSize
            for j in 0..<count {
                let s = Int(start) + j
                fat[s] = j < count - 1 ? UInt32(s + 1) : endOfChain
            }
        }

        if miniStreamBlobSectorCount > 0 {
            for j in 0..<miniStreamBlobSectorCount {
                let s = Int(miniStreamBlobStartSector) + j
                fat[s] = j < miniStreamBlobSectorCount - 1 ? UInt32(s + 1) : endOfChain
            }
        }

        for j in 0..<dirSectorCount {
            let s = Int(directorySectorStart) + j
            fat[s] = j < dirSectorCount - 1 ? UInt32(s + 1) : endOfChain
        }

        for j in 0..<miniFATSectorCount {
            let s = Int(miniFATSectorStart) + j
            fat[s] = j < miniFATSectorCount - 1 ? UInt32(s + 1) : endOfChain
        }

        for j in 0..<Int(fatSectorCount) {
            fat[Int(fatSectorStart) + j] = fatSpecial
        }

        // Build mini-FAT
        var miniFAT = [UInt32]()
        if totalMiniSectors > 0 {
            for ms in miniStreams {
                let startMiniSect = Int(dirs[ms.dirIdx].startSector)
                let count = (ms.data.count + miniSectorSize - 1) / miniSectorSize
                for j in 0..<count {
                    let idx = startMiniSect + j
                    while miniFAT.count <= idx { miniFAT.append(freeSect) }
                    miniFAT[idx] = j < count - 1 ? UInt32(idx + 1) : endOfChain
                }
            }
            let perSector = sectorSize / 4
            let padded = ((miniFAT.count + perSector - 1) / perSector) * perSector
            while miniFAT.count < padded { miniFAT.append(freeSect) }
        }

        // Assemble file
        var fileData = Data()
        fileData.reserveCapacity(512 + Int(totalSectors) * sectorSize)

        // CFB Header (512 bytes)
        var hdr = Data(count: 512)
        let magic: [UInt8] = [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]
        hdr.replaceSubrange(0..<8, with: magic)
        hdr.replaceSubrange(24..<26, with: UInt16(0x003E).littleEndianBytes)
        hdr.replaceSubrange(26..<28, with: UInt16(3).littleEndianBytes)
        hdr.replaceSubrange(28..<30, with: UInt16(0xFFFE).littleEndianBytes)
        hdr.replaceSubrange(30..<32, with: UInt16(9).littleEndianBytes)
        hdr.replaceSubrange(32..<34, with: UInt16(6).littleEndianBytes)
        hdr.replaceSubrange(40..<44, with: UInt32(0).littleEndianBytes)
        hdr.replaceSubrange(44..<48, with: fatSectorCount.littleEndianBytes)
        hdr.replaceSubrange(48..<52, with: UInt32(directorySectorStart).littleEndianBytes)
        hdr.replaceSubrange(52..<56, with: UInt32(0).littleEndianBytes)
        hdr.replaceSubrange(56..<60, with: UInt32(miniStreamCutoff).littleEndianBytes)
        let firstMiniFAT: UInt32 = miniFATSectorCount > 0 ? UInt32(miniFATSectorStart) : endOfChain
        hdr.replaceSubrange(60..<64, with: firstMiniFAT.littleEndianBytes)
        hdr.replaceSubrange(64..<68, with: UInt32(miniFATSectorCount).littleEndianBytes)
        hdr.replaceSubrange(68..<72, with: endOfChain.littleEndianBytes)
        hdr.replaceSubrange(72..<76, with: UInt32(0).littleEndianBytes)
        for i in 0..<109 {
            hdr.replaceSubrange(76 + i*4 ..< 80 + i*4, with: freeSect.littleEndianBytes)
        }
        for i in 0..<Int(fatSectorCount) {
            let sIdx = fatSectorStart + UInt32(i)
            hdr.replaceSubrange(76 + i*4 ..< 80 + i*4, with: sIdx.littleEndianBytes)
        }
        fileData.append(hdr)

        // Regular stream sectors
        for rs in regularStreams {
            fileData.append(rs.data)
            let remainder = rs.data.count % sectorSize
            if remainder != 0 { fileData.append(Data(count: sectorSize - remainder)) }
        }

        // Mini-stream blob sectors
        if !miniStreamBlob.isEmpty {
            fileData.append(miniStreamBlob)
            let remainder = miniStreamBlob.count % sectorSize
            if remainder != 0 { fileData.append(Data(count: sectorSize - remainder)) }
        }

        // Directory sectors
        var dirData = Data()
        for dir in dirs {
            dirData.append(encodeCFBDirEntry(dir))
        }
        let totalDirBytes = dirSectorCount * sectorSize
        if dirData.count < totalDirBytes {
            dirData.append(Data(count: totalDirBytes - dirData.count))
        }
        fileData.append(dirData)

        // Mini-FAT sectors
        if !miniFAT.isEmpty {
            var mfData = Data()
            for entry in miniFAT { mfData.append(contentsOf: entry.littleEndianBytes) }
            let totalMFBytes = miniFATSectorCount * sectorSize
            if mfData.count < totalMFBytes { mfData.append(Data(count: totalMFBytes - mfData.count)) }
            fileData.append(mfData)
        }

        // FAT sectors
        var fatData = Data()
        for entry in fat { fatData.append(contentsOf: entry.littleEndianBytes) }
        let totalFATBytes = Int(fatSectorCount) * sectorSize
        if fatData.count < totalFATBytes { fatData.append(Data(count: totalFATBytes - fatData.count)) }
        fileData.append(fatData)

        return fileData
    }

    // MARK: - CFB directory entry type

    private struct CFBDirEntry {
        let name: String
        let objectType: UInt8
        var childIndex: Int32 = -1
        var leftSibling: Int32 = -1
        var rightSibling: Int32 = -1
        var startSector: UInt32 = 0
        var streamSize: UInt64 = 0
    }

    /// Encodes a CFBDirEntry as a 128-byte OLE2 directory entry.
    private static func encodeCFBDirEntry(_ dir: CFBDirEntry) -> Data {
        var entry = Data(count: 128)

        let nameChars = Array(dir.name.utf16.prefix(31))
        for (i, ch) in nameChars.enumerated() {
            entry[i * 2]     = UInt8(ch & 0xFF)
            entry[i * 2 + 1] = UInt8(ch >> 8)
        }
        // Null terminator already present (Data is zero-initialized)

        let nameSize = UInt16((nameChars.count + 1) * 2)
        entry[64] = UInt8(nameSize & 0xFF)
        entry[65] = UInt8(nameSize >> 8)

        entry[66] = dir.objectType
        entry[67] = 1  // color: black

        entry.replaceSubrange(68..<72, with: UInt32(bitPattern: dir.leftSibling).littleEndianBytes)
        entry.replaceSubrange(72..<76, with: UInt32(bitPattern: dir.rightSibling).littleEndianBytes)
        entry.replaceSubrange(76..<80, with: UInt32(bitPattern: dir.childIndex).littleEndianBytes)

        entry.replaceSubrange(116..<120, with: dir.startSector.littleEndianBytes)
        entry.replaceSubrange(120..<124, with: UInt32(dir.streamSize & 0xFFFFFFFF).littleEndianBytes)

        return entry
    }

    /// Assigns balanced binary tree pointers for OLE2 directory children.
    /// Returns the index of the root node.
    @discardableResult
    private static func assignBalancedTree(
        _ dirs: inout [CFBDirEntry],
        children: inout [Int]
    ) -> Int {
        children.sort { a, b in
            let na = dirs[a].name
            let nb = dirs[b].name
            if na.count != nb.count { return na.count < nb.count }
            return na < nb
        }
        func buildTree(_ range: Range<Int>) -> Int? {
            guard !range.isEmpty else { return nil }
            let mid = range.lowerBound + range.count / 2
            let dirIdx = children[mid]
            if let left = buildTree(range.lowerBound..<mid) {
                dirs[dirIdx].leftSibling = Int32(left)
            }
            if let right = buildTree((mid + 1)..<range.upperBound) {
                dirs[dirIdx].rightSibling = Int32(right)
            }
            return dirIdx
        }
        return buildTree(0..<children.count) ?? children[0]
    }

    private static func doubleArrayToData(_ doubles: [Double]) -> Data {
        var copy = doubles
        return Data(bytes: &copy, count: copy.count * MemoryLayout<Double>.size)
    }
}

// MARK: - ShimadzuWriterError

nonisolated enum ShimadzuWriterError: Error, LocalizedError {
    case noSubfiles

    var errorDescription: String? {
        switch self {
        case .noSubfiles: return "No subfiles to export."
        }
    }
}

// MARK: - Data / numeric helpers

nonisolated extension Data {
    mutating func writeNullPaddedString(_ s: String, at offset: Int, length: Int) {
        let bytes = Array(s.utf8.prefix(length))
        replaceSubrange(offset ..< offset + bytes.count, with: bytes)
        // remaining bytes stay 0 from Data(count:) initialisation
    }
}

nonisolated extension UInt32 {
    var littleEndianBytes: [UInt8] {
        withUnsafeBytes(of: littleEndian, Array.init)
    }
}
nonisolated extension UInt16 {
    var littleEndianBytes: [UInt8] {
        withUnsafeBytes(of: littleEndian, Array.init)
    }
}
nonisolated extension Double {
    var littleEndianBytes: [UInt8] {
        withUnsafeBytes(of: self.bitPattern.littleEndian, Array.init)
    }
}
nonisolated extension Float {
    var littleEndianBytes: [UInt8] {
        withUnsafeBytes(of: self.bitPattern.littleEndian, Array.init)
    }
}
