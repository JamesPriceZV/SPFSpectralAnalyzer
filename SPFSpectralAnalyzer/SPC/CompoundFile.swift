import Foundation

enum CompoundFileError: Error, CustomStringConvertible {
    case invalidSignature
    case unsupportedSectorSize(Int)
    case unsupportedMiniSectorSize(Int)
    case readOutOfBounds
    case invalidSectorIndex(Int)
    case chainLoopDetected
    case directoryNotFound
    case streamNotFound(String)
    case invalidStreamSize

    var description: String {
        switch self {
        case .invalidSignature:
            return "Invalid Compound File signature"
        case .unsupportedSectorSize(let size):
            return "Unsupported sector size: \(size)"
        case .unsupportedMiniSectorSize(let size):
            return "Unsupported mini sector size: \(size)"
        case .readOutOfBounds:
            return "Read out of bounds"
        case .invalidSectorIndex(let index):
            return "Invalid sector index: \(index)"
        case .chainLoopDetected:
            return "Sector chain loop detected"
        case .directoryNotFound:
            return "Directory not found"
        case .streamNotFound(let name):
            return "Stream not found: \(name)"
        case .invalidStreamSize:
            return "Invalid stream size"
        }
    }
}

private struct BinaryReader {
    let data: Data

    nonisolated func readUInt16LE(at offset: Int) throws -> UInt16 {
        let end = offset + 2
        guard end <= data.count else { throw CompoundFileError.readOutOfBounds }
        return data.subdata(in: offset..<end).withUnsafeBytes { ptr in
            ptr.load(as: UInt16.self)
        }.littleEndian
    }

    nonisolated func readUInt32LE(at offset: Int) throws -> UInt32 {
        let end = offset + 4
        guard end <= data.count else { throw CompoundFileError.readOutOfBounds }
        return data.subdata(in: offset..<end).withUnsafeBytes { ptr in
            ptr.load(as: UInt32.self)
        }.littleEndian
    }

    nonisolated func readInt32LE(at offset: Int) throws -> Int32 {
        return Int32(bitPattern: try readUInt32LE(at: offset))
    }

    nonisolated func readUInt64LE(at offset: Int) throws -> UInt64 {
        let end = offset + 8
        guard end <= data.count else { throw CompoundFileError.readOutOfBounds }
        return data.subdata(in: offset..<end).withUnsafeBytes { ptr in
            ptr.load(as: UInt64.self)
        }.littleEndian
    }
}

struct CompoundFileDirectoryEntry: Sendable {
    let name: String
    let objectType: UInt8
    let leftSibling: Int32
    let rightSibling: Int32
    let child: Int32
    let startSector: Int32
    let streamSize: UInt64
}

nonisolated final class CompoundFile {
    private let fileURL: URL
    private let fileHandle: FileHandle
    private let fileSize: UInt64

    private let sectorSize: Int
    private let miniSectorSize: Int
    private let miniStreamCutoff: Int
    private let firstDirSector: Int32
    private let firstMiniFATSector: Int32
    private let numMiniFATSectors: Int32
    private let firstDIFATSector: Int32
    private let numDIFATSectors: Int32

    private let fat: [Int32]
    private let miniFAT: [Int32]
    private let directoryEntries: [CompoundFileDirectoryEntry]
    private let miniStreamData: Data

    private static let headerSize = 512
    private static let signature: [UInt8] = [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]

    private static let freeSect: Int32 = -1
    private static let endOfChain: Int32 = -2
    private static let fatSect: Int32 = -3
    private static let difSect: Int32 = -4

    init(fileURL: URL) throws {
        let fileHandle = try FileHandle(forReadingFrom: fileURL)
        let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let fileSize = (attrs[.size] as? NSNumber)?.uint64Value ?? 0

        func readData(at offset: UInt64, count: Int) throws -> Data {
            guard offset + UInt64(count) <= fileSize else { throw CompoundFileError.readOutOfBounds }
            try fileHandle.seek(toOffset: offset)
            if let data = try fileHandle.read(upToCount: count) {
                return data
            }
            return Data()
        }

        func readSector(_ index: Int32, sectorSize: Int) throws -> Data {
            if index < 0 { throw CompoundFileError.invalidSectorIndex(Int(index)) }
            let offset = UInt64(CompoundFile.headerSize + Int(index) * sectorSize)
            return try readData(at: offset, count: sectorSize)
        }

        let header = try readData(at: 0, count: CompoundFile.headerSize)
        let reader = BinaryReader(data: header)

        if Array(header.prefix(8)) != CompoundFile.signature {
            throw CompoundFileError.invalidSignature
        }

        let sectorShift = Int(try reader.readUInt16LE(at: 30))
        let miniSectorShift = Int(try reader.readUInt16LE(at: 32))
        let sectorSize = 1 << sectorShift
        let miniSectorSize = 1 << miniSectorShift

        if sectorSize != 512 && sectorSize != 4096 {
            throw CompoundFileError.unsupportedSectorSize(sectorSize)
        }
        if miniSectorSize != 64 {
            throw CompoundFileError.unsupportedMiniSectorSize(miniSectorSize)
        }

        let numFATSectors = Int32(bitPattern: try reader.readUInt32LE(at: 44))
        let firstDirSector = Int32(bitPattern: try reader.readUInt32LE(at: 48))
        let miniStreamCutoff = Int(try reader.readUInt32LE(at: 56))
        let firstMiniFATSector = Int32(bitPattern: try reader.readUInt32LE(at: 60))
        let numMiniFATSectors = Int32(bitPattern: try reader.readUInt32LE(at: 64))
        let firstDIFATSector = Int32(bitPattern: try reader.readUInt32LE(at: 68))
        let numDIFATSectors = Int32(bitPattern: try reader.readUInt32LE(at: 72))

        let difatEntries = try CompoundFile.readHeaderDIFAT(reader: reader)
        let fatSectorIndices = try CompoundFile.buildFATSectorList(
            difatHeader: difatEntries,
            firstDIFATSector: firstDIFATSector,
            numDIFATSectors: numDIFATSectors,
            sectorSize: sectorSize,
            readSector: { index in
                try readSector(index, sectorSize: sectorSize)
            }
        )

        let fat = try CompoundFile.readFAT(
            fatSectorIndices: fatSectorIndices,
            sectorSize: sectorSize,
            readSector: { index in
                try readSector(index, sectorSize: sectorSize)
            },
            expectedCount: Int(numFATSectors)
        )

        let directoryEntries = try CompoundFile.readDirectoryEntries(
            startSector: firstDirSector,
            sectorSize: sectorSize,
            fat: fat,
            readSector: { index in
                try readSector(index, sectorSize: sectorSize)
            }
        )

        let miniFAT = try CompoundFile.readMiniFAT(
            startSector: firstMiniFATSector,
            numSectors: numMiniFATSectors,
            sectorSize: sectorSize,
            fat: fat,
            readSector: { index in
                try readSector(index, sectorSize: sectorSize)
            }
        )

        let miniStreamData = try CompoundFile.readMiniStream(
            directoryEntries: directoryEntries,
            sectorSize: sectorSize,
            fat: fat,
            readSector: { index in
                try readSector(index, sectorSize: sectorSize)
            }
        )

        self.fileURL = fileURL
        self.fileHandle = fileHandle
        self.fileSize = fileSize
        self.sectorSize = sectorSize
        self.miniSectorSize = miniSectorSize
        self.miniStreamCutoff = miniStreamCutoff
        self.firstDirSector = firstDirSector
        self.firstMiniFATSector = firstMiniFATSector
        self.numMiniFATSectors = numMiniFATSectors
        self.firstDIFATSector = firstDIFATSector
        self.numDIFATSectors = numDIFATSectors
        self.fat = fat
        self.directoryEntries = directoryEntries
        self.miniFAT = miniFAT
        self.miniStreamData = miniStreamData
    }

    deinit {
        try? fileHandle.close()
    }

    var directoryEntryCount: Int {
        directoryEntries.count
    }

    func allDirectoryEntries() -> [CompoundFileDirectoryEntry] {
        directoryEntries
    }

    func directoryEntry(at index: Int32) throws -> CompoundFileDirectoryEntry {
        let idx = Int(index)
        guard idx >= 0 && idx < directoryEntries.count else {
            throw CompoundFileError.directoryNotFound
        }
        return directoryEntries[idx]
    }

    func streamData(for entry: CompoundFileDirectoryEntry) throws -> Data {
        let size = Int(entry.streamSize)
        if size < 0 { throw CompoundFileError.invalidStreamSize }
        if size == 0 { return Data() }

        if size < miniStreamCutoff && entry.objectType == 2 {
            return try readMiniStream(startSector: entry.startSector, size: size)
        }
        return try readStream(startSector: entry.startSector, size: size)
    }

    private func readStream(startSector: Int32, size: Int) throws -> Data {
        return try CompoundFile.readStream(
            startSector: startSector,
            size: size,
            sectorSize: sectorSize,
            fat: fat,
            readSector: { [unowned self] index in
                try self.readSector(index)
            }
        )
    }

    private func readMiniStream(startSector: Int32, size: Int) throws -> Data {
        return try CompoundFile.readMiniStreamData(
            startSector: startSector,
            size: size,
            miniSectorSize: miniSectorSize,
            miniFAT: miniFAT,
            miniStream: miniStreamData
        )
    }

    private func readData(at offset: UInt64, count: Int) throws -> Data {
        guard offset + UInt64(count) <= fileSize else { throw CompoundFileError.readOutOfBounds }
        try fileHandle.seek(toOffset: offset)
        if let data = try fileHandle.read(upToCount: count) {
            return data
        }
        return Data()
    }

    private func readSector(_ index: Int32) throws -> Data {
        if index < 0 { throw CompoundFileError.invalidSectorIndex(Int(index)) }
        let offset = UInt64(CompoundFile.headerSize + Int(index) * sectorSize)
        return try readData(at: offset, count: sectorSize)
    }

    private static func readHeaderDIFAT(reader: BinaryReader) throws -> [Int32] {
        var entries: [Int32] = []
        for i in 0..<109 {
            let offset = 76 + (i * 4)
            let value = Int32(bitPattern: try reader.readUInt32LE(at: offset))
            if value != freeSect {
                entries.append(value)
            }
        }
        return entries
    }

    private static func buildFATSectorList(
        difatHeader: [Int32],
        firstDIFATSector: Int32,
        numDIFATSectors: Int32,
        sectorSize: Int,
        readSector: (Int32) throws -> Data
    ) throws -> [Int32] {
        var fatSectorIndices = difatHeader
        guard numDIFATSectors > 0 else { return fatSectorIndices }

        var current = firstDIFATSector
        var sectorsRead: Int32 = 0
        let entriesPerSector = (sectorSize / 4) - 1

        while current != endOfChain && sectorsRead < numDIFATSectors {
            let sectorData = try readSector(current)
            let reader = BinaryReader(data: sectorData)
            for i in 0..<entriesPerSector {
                let value = Int32(bitPattern: try reader.readUInt32LE(at: i * 4))
                if value != freeSect {
                    fatSectorIndices.append(value)
                }
            }
            current = Int32(bitPattern: try reader.readUInt32LE(at: entriesPerSector * 4))
            sectorsRead += 1
        }

        return fatSectorIndices
    }

    private static func readFAT(
        fatSectorIndices: [Int32],
        sectorSize: Int,
        readSector: (Int32) throws -> Data,
        expectedCount: Int
    ) throws -> [Int32] {
        var fat: [Int32] = []
        for index in fatSectorIndices {
            let sectorData = try readSector(index)
            let reader = BinaryReader(data: sectorData)
            let entries = sectorSize / 4
            for i in 0..<entries {
                fat.append(Int32(bitPattern: try reader.readUInt32LE(at: i * 4)))
            }
        }
        if expectedCount > 0 && fat.count < expectedCount * (sectorSize / 4) {
            // Keep going with what we have; some files are permissive
        }
        return fat
    }

    private static func readDirectoryEntries(
        startSector: Int32,
        sectorSize: Int,
        fat: [Int32],
        readSector: (Int32) throws -> Data
    ) throws -> [CompoundFileDirectoryEntry] {
        let dirData = try readStream(startSector: startSector, size: Int.max, sectorSize: sectorSize, fat: fat, readSector: readSector, allowUnknownSize: true)
        let entrySize = 128
        let count = dirData.count / entrySize
        var entries: [CompoundFileDirectoryEntry] = []
        entries.reserveCapacity(count)

        for i in 0..<count {
            let offset = i * entrySize
            let slice = dirData.subdata(in: offset..<(offset + entrySize))
            let reader = BinaryReader(data: slice)

            let nameLength = Int(try reader.readUInt16LE(at: 64))
            var name = ""
            if nameLength >= 2 && nameLength <= 64 {
                let nameData = slice.subdata(in: 0..<(nameLength - 2))
                name = String(data: nameData, encoding: .utf16LittleEndian) ?? ""
            }

            let objectType = slice[66]
            let leftSibling = try reader.readInt32LE(at: 68)
            let rightSibling = try reader.readInt32LE(at: 72)
            let child = try reader.readInt32LE(at: 76)
            let startSector = try reader.readInt32LE(at: 116)
            let streamSize = try reader.readUInt64LE(at: 120)

            entries.append(CompoundFileDirectoryEntry(
                name: name,
                objectType: objectType,
                leftSibling: leftSibling,
                rightSibling: rightSibling,
                child: child,
                startSector: startSector,
                streamSize: streamSize
            ))
        }

        return entries
    }

    private static func readMiniFAT(
        startSector: Int32,
        numSectors: Int32,
        sectorSize: Int,
        fat: [Int32],
        readSector: (Int32) throws -> Data
    ) throws -> [Int32] {
        guard startSector != endOfChain && numSectors > 0 else { return [] }
        let data = try readStream(startSector: startSector, size: Int(numSectors) * sectorSize, sectorSize: sectorSize, fat: fat, readSector: readSector)
        let reader = BinaryReader(data: data)
        let entries = data.count / 4
        var miniFAT: [Int32] = []
        miniFAT.reserveCapacity(entries)
        for i in 0..<entries {
            miniFAT.append(Int32(bitPattern: try reader.readUInt32LE(at: i * 4)))
        }
        return miniFAT
    }

    private static func readMiniStream(
        directoryEntries: [CompoundFileDirectoryEntry],
        sectorSize: Int,
        fat: [Int32],
        readSector: (Int32) throws -> Data
    ) throws -> Data {
        guard let root = directoryEntries.first(where: { $0.objectType == 5 }) else {
            return Data()
        }
        let size = Int(root.streamSize)
        if size <= 0 { return Data() }
        return try readStream(startSector: root.startSector, size: size, sectorSize: sectorSize, fat: fat, readSector: readSector)
    }

    private static func readStream(
        startSector: Int32,
        size: Int,
        sectorSize: Int,
        fat: [Int32],
        readSector: (Int32) throws -> Data,
        allowUnknownSize: Bool = false
    ) throws -> Data {
        if startSector < 0 { return Data() }
        var data = Data()
        var remaining = size
        var current = startSector
        var visited: Set<Int32> = []
        let maxSectors = fat.count

        while current != endOfChain {
            if visited.contains(current) {
                throw CompoundFileError.chainLoopDetected
            }
            visited.insert(current)
            if Int(current) >= maxSectors {
                throw CompoundFileError.invalidSectorIndex(Int(current))
            }

            let sectorData = try readSector(current)
            if allowUnknownSize {
                data.append(sectorData)
            } else {
                let take = min(remaining, sectorSize)
                data.append(sectorData.prefix(take))
                remaining -= take
                if remaining <= 0 { break }
            }
            current = fat[Int(current)]
        }

        if !allowUnknownSize && remaining > 0 {
            throw CompoundFileError.invalidStreamSize
        }

        return data
    }

    private static func readMiniStreamData(
        startSector: Int32,
        size: Int,
        miniSectorSize: Int,
        miniFAT: [Int32],
        miniStream: Data
    ) throws -> Data {
        if startSector < 0 { return Data() }
        var data = Data()
        var remaining = size
        var current = startSector
        var visited: Set<Int32> = []

        while current != endOfChain {
            if visited.contains(current) {
                throw CompoundFileError.chainLoopDetected
            }
            visited.insert(current)
            let offset = Int(current) * miniSectorSize
            let end = offset + miniSectorSize
            if end > miniStream.count {
                throw CompoundFileError.readOutOfBounds
            }
            let take = min(remaining, miniSectorSize)
            data.append(miniStream.subdata(in: offset..<(offset + take)))
            remaining -= take
            if remaining <= 0 { break }
            if Int(current) >= miniFAT.count {
                throw CompoundFileError.invalidSectorIndex(Int(current))
            }
            current = miniFAT[Int(current)]
        }

        if remaining > 0 {
            throw CompoundFileError.invalidStreamSize
        }

        return data
    }
}
