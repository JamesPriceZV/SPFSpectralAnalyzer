// CompoundFileReader.swift
// SPCKit
//
// Minimal OLE2 Compound Binary File reader for parsing Shimadzu SPC files.
// Implements just enough of the Microsoft Compound File Binary Format
// specification to navigate directory entries and read stream data.

import Foundation

// MARK: - Errors

nonisolated enum CompoundFileError: Error, LocalizedError {
    case notCompoundFile
    case fileTooSmall
    case invalidSectorSize
    case corruptFAT
    case corruptDirectory
    case streamNotFound(String)
    case invalidStreamData

    var errorDescription: String? {
        switch self {
        case .notCompoundFile:     return "Not an OLE2 Compound File."
        case .fileTooSmall:        return "File is too small for a valid compound file."
        case .invalidSectorSize:   return "Invalid sector size in compound file header."
        case .corruptFAT:          return "Corrupt FAT chain in compound file."
        case .corruptDirectory:    return "Corrupt directory structure in compound file."
        case .streamNotFound(let n): return "Stream '\(n)' not found in compound file."
        case .invalidStreamData:   return "Invalid stream data in compound file."
        }
    }
}

// MARK: - CompoundFileReader

/// Reads an OLE2/CFB (Compound File Binary) from a Data blob.
/// Supports version 3 (512-byte sectors) and version 4 (4096-byte sectors).
nonisolated struct CompoundFileReader: Sendable {

    // MARK: Constants

    private static let magic: [UInt8] = [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]
    private static let endOfChain: UInt32  = 0xFFFFFFFE
    private static let freeSector: UInt32  = 0xFFFFFFFF
    private static let noStream: Int32     = -1

    // MARK: Stored properties

    private let data: Data
    private let sectorSize: Int
    private let miniSectorSize: Int
    private let miniStreamCutoff: Int
    private let fat: [UInt32]
    private let miniFAT: [UInt32]
    private let directories: [DirectoryEntry]
    private let miniStreamData: Data

    // MARK: Directory entry

    struct DirectoryEntry: Sendable {
        let name: String
        let objectType: UInt8   // 0=empty, 1=storage, 2=stream, 5=root
        let leftSibling: Int32
        let rightSibling: Int32
        let child: Int32
        let startSector: UInt32
        let streamSize: UInt64
    }

    // MARK: Init

    init(data: Data) throws {
        guard data.count >= 512 else {
            throw CompoundFileError.fileTooSmall
        }

        // Verify magic signature
        let magicSlice = [UInt8](data[0..<8])
        guard magicSlice == Self.magic else {
            throw CompoundFileError.notCompoundFile
        }

        self.data = data

        // Parse header
        let _ = data.loadUInt16(at: 26)  // major version (unused)
        let sectorPower  = data.loadUInt16(at: 30)
        let miniPower    = data.loadUInt16(at: 32)

        guard sectorPower == 9 || sectorPower == 12 else {
            throw CompoundFileError.invalidSectorSize
        }

        self.sectorSize      = 1 << Int(sectorPower)    // 512 or 4096
        self.miniSectorSize  = 1 << Int(miniPower)       // typically 64
        self.miniStreamCutoff = Int(data.loadUInt32(at: 56))  // typically 4096

        let fatSectorCount      = Int(data.loadUInt32(at: 44))
        let firstDirSector      = data.loadUInt32(at: 48)
        let firstMiniFATSector  = data.loadUInt32(at: 60)
        let miniFATSectorCount  = Int(data.loadUInt32(at: 64))
        let firstDIFATSector    = data.loadUInt32(at: 68)
        let difatSectorCount    = Int(data.loadUInt32(at: 72))

        // Build list of FAT sector indices from DIFAT
        var fatSectorIndices: [UInt32] = []
        // First 109 DIFAT entries are in the header at bytes 76..
        let headerDIFATCount = min(fatSectorCount, 109)
        for i in 0..<headerDIFATCount {
            let idx = data.loadUInt32(at: 76 + i * 4)
            fatSectorIndices.append(idx)
        }

        // Additional DIFAT sectors (rare, for very large files)
        if difatSectorCount > 0, firstDIFATSector != Self.endOfChain {
            var difatSect = firstDIFATSector
            var remaining = fatSectorCount - headerDIFATCount
            var safety = 0
            while difatSect != Self.endOfChain, remaining > 0, safety < 10000 {
                safety += 1
                let base = Self.sectorOffset(difatSect, sectorSize: sectorSize)
                let entriesPerSector = (sectorSize / 4) - 1  // last UInt32 is chain pointer
                for i in 0..<min(remaining, entriesPerSector) {
                    let idx = data.loadUInt32(at: base + i * 4)
                    fatSectorIndices.append(idx)
                    remaining -= 1
                }
                difatSect = data.loadUInt32(at: base + entriesPerSector * 4)
            }
        }

        // Build FAT array
        var fat: [UInt32] = []
        for sectIdx in fatSectorIndices {
            let base = Self.sectorOffset(sectIdx, sectorSize: sectorSize)
            let count = sectorSize / 4
            for i in 0..<count {
                let off = base + i * 4
                guard off + 4 <= data.count else { break }
                fat.append(data.loadUInt32(at: off))
            }
        }
        self.fat = fat

        // Read directory entries
        self.directories = try Self.readDirectories(
            data: data, fat: fat, firstSector: firstDirSector, sectorSize: sectorSize
        )

        // Build mini-FAT
        var miniFAT: [UInt32] = []
        if miniFATSectorCount > 0, firstMiniFATSector != Self.endOfChain {
            let chain = Self.followChain(fat: fat, start: firstMiniFATSector)
            for sectIdx in chain {
                let base = Self.sectorOffset(sectIdx, sectorSize: sectorSize)
                let count = sectorSize / 4
                for i in 0..<count {
                    let off = base + i * 4
                    guard off + 4 <= data.count else { break }
                    miniFAT.append(data.loadUInt32(at: off))
                }
            }
        }
        self.miniFAT = miniFAT

        // Read mini-stream data from root entry's chain
        if !directories.isEmpty, directories[0].objectType == 5 {
            let rootStart = directories[0].startSector
            if rootStart != Self.endOfChain {
                let chain = Self.followChain(fat: fat, start: rootStart)
                var miniData = Data()
                miniData.reserveCapacity(chain.count * sectorSize)
                for sectIdx in chain {
                    let base = Self.sectorOffset(sectIdx, sectorSize: sectorSize)
                    let end = min(base + sectorSize, data.count)
                    if base < end {
                        miniData.append(data[base..<end])
                    }
                }
                self.miniStreamData = miniData
            } else {
                self.miniStreamData = Data()
            }
        } else {
            self.miniStreamData = Data()
        }
    }

    // MARK: Public API

    /// Returns all directory entries.
    func allDirectoryEntries() -> [DirectoryEntry] { directories }

    /// Reads stream data for a given directory entry index.
    func streamData(at index: Int) throws -> Data {
        guard index >= 0, index < directories.count else {
            throw CompoundFileError.corruptDirectory
        }
        let entry = directories[index]
        guard entry.objectType == 2 else {
            throw CompoundFileError.streamNotFound("Entry \(index) is not a stream")
        }
        let size = Int(entry.streamSize)
        if size == 0 { return Data() }

        if size < miniStreamCutoff {
            return readMiniStream(start: entry.startSector, size: size)
        } else {
            return readRegularStream(start: entry.startSector, size: size)
        }
    }

    /// Finds a child entry by name within a storage entry's children.
    func findChild(named name: String, inStorageAt index: Int) -> Int? {
        guard index >= 0, index < directories.count else { return nil }
        let entry = directories[index]
        let childIdx = entry.child
        guard childIdx >= 0 else { return nil }
        return searchTree(name: name, startIndex: Int(childIdx))
    }

    /// Navigates a path of directory names starting from a root entry index.
    /// Returns the index of the final entry, or nil if not found.
    func navigatePath(_ path: [String], from rootIndex: Int = 0) -> Int? {
        var current = rootIndex
        for name in path {
            guard let found = findChild(named: name, inStorageAt: current) else {
                return nil
            }
            current = found
        }
        return current
    }

    /// Collects all children of a storage entry (traverses the red-black tree).
    func childEntries(of storageIndex: Int) -> [Int] {
        guard storageIndex >= 0, storageIndex < directories.count else { return [] }
        let childIdx = directories[storageIndex].child
        guard childIdx >= 0 else { return [] }
        return collectTreeNodes(startIndex: Int(childIdx))
    }

    // MARK: Private - sector offset

    private static func sectorOffset(_ sector: UInt32, sectorSize: Int) -> Int {
        // Sector 0 starts immediately after the 512-byte header
        Int(sector) * sectorSize + 512
    }

    // MARK: Private - chain following

    private static func followChain(fat: [UInt32], start: UInt32) -> [UInt32] {
        var chain: [UInt32] = []
        var current = start
        var visited = Set<UInt32>()
        while current != endOfChain, current != freeSector, current < fat.count {
            guard !visited.contains(current) else { break }
            visited.insert(current)
            chain.append(current)
            current = fat[Int(current)]
        }
        return chain
    }

    // MARK: Private - directory reading

    private static func readDirectories(
        data: Data, fat: [UInt32], firstSector: UInt32, sectorSize: Int
    ) throws -> [DirectoryEntry] {
        let chain = followChain(fat: fat, start: firstSector)
        var entries: [DirectoryEntry] = []
        let entriesPerSector = sectorSize / 128

        for sectIdx in chain {
            let base = sectorOffset(sectIdx, sectorSize: sectorSize)
            for i in 0..<entriesPerSector {
                let entryBase = base + i * 128
                guard entryBase + 128 <= data.count else { break }

                let objectType = data[entryBase + 66]
                if objectType == 0 { // empty entry
                    entries.append(DirectoryEntry(
                        name: "", objectType: 0,
                        leftSibling: -1, rightSibling: -1, child: -1,
                        startSector: 0, streamSize: 0
                    ))
                    continue
                }

                // Name: UTF-16LE, length in bytes at offset 64
                let nameByteCount = Int(data.loadUInt16(at: entryBase + 64))
                let nameBytes = min(nameByteCount, 64)
                // Strip trailing null chars (2 bytes for UTF-16 null)
                let effectiveBytes = max(nameBytes - 2, 0)
                let name: String
                if effectiveBytes > 0 {
                    name = String(data: data[entryBase..<(entryBase + effectiveBytes)], encoding: .utf16LittleEndian) ?? ""
                } else {
                    name = ""
                }

                let left  = Int32(bitPattern: data.loadUInt32(at: entryBase + 68))
                let right = Int32(bitPattern: data.loadUInt32(at: entryBase + 72))
                let child = Int32(bitPattern: data.loadUInt32(at: entryBase + 76))
                let startSector = data.loadUInt32(at: entryBase + 116)

                let streamSize: UInt64
                if sectorSize == 4096 {
                    streamSize = data.loadUInt64(at: entryBase + 120)
                } else {
                    // Version 3: only lower 32 bits
                    streamSize = UInt64(data.loadUInt32(at: entryBase + 120))
                }

                entries.append(DirectoryEntry(
                    name: name, objectType: objectType,
                    leftSibling: left, rightSibling: right, child: child,
                    startSector: startSector, streamSize: streamSize
                ))
            }
        }

        return entries
    }

    // MARK: Private - stream reading

    private func readRegularStream(start: UInt32, size: Int) -> Data {
        let chain = Self.followChain(fat: fat, start: start)
        var result = Data()
        result.reserveCapacity(size)
        var remaining = size
        for sectIdx in chain {
            let base = Self.sectorOffset(sectIdx, sectorSize: sectorSize)
            let toRead = min(remaining, sectorSize)
            let end = min(base + toRead, data.count)
            if base < end {
                result.append(data[base..<end])
            }
            remaining -= toRead
            if remaining <= 0 { break }
        }
        return result.prefix(size)
    }

    private func readMiniStream(start: UInt32, size: Int) -> Data {
        var chain: [UInt32] = []
        var current = start
        var visited = Set<UInt32>()
        while current != Self.endOfChain, current != Self.freeSector, current < miniFAT.count {
            guard !visited.contains(current) else { break }
            visited.insert(current)
            chain.append(current)
            current = miniFAT[Int(current)]
        }

        var result = Data()
        result.reserveCapacity(size)
        var remaining = size
        for miniSectIdx in chain {
            let offset = Int(miniSectIdx) * miniSectorSize
            let toRead = min(remaining, miniSectorSize)
            let end = min(offset + toRead, miniStreamData.count)
            if offset < end {
                result.append(miniStreamData[offset..<end])
            }
            remaining -= toRead
            if remaining <= 0 { break }
        }
        return result.prefix(size)
    }

    // MARK: Private - tree traversal

    private func searchTree(name: String, startIndex: Int) -> Int? {
        var current = startIndex
        var visited = Set<Int>()
        while current >= 0, current < directories.count {
            guard !visited.contains(current) else { return nil }
            visited.insert(current)
            let entry = directories[current]
            if entry.name == name { return current }
            // OLE2 uses case-insensitive comparison with length-first ordering
            if name.count > entry.name.count || (name.count == entry.name.count && name > entry.name) {
                current = Int(entry.rightSibling)
            } else {
                current = Int(entry.leftSibling)
            }
        }
        return nil
    }

    private func collectTreeNodes(startIndex: Int) -> [Int] {
        var nodes: [Int] = []
        var queue: [Int] = [startIndex]
        var visited = Set<Int>()
        while let node = queue.popLast() {
            guard node >= 0, node < directories.count else { continue }
            guard !visited.contains(node) else { continue }
            visited.insert(node)
            let entry = directories[node]
            if entry.objectType != 0 {
                nodes.append(node)
            }
            if entry.leftSibling >= 0  { queue.append(Int(entry.leftSibling)) }
            if entry.rightSibling >= 0 { queue.append(Int(entry.rightSibling)) }
        }
        return nodes
    }
}

// MARK: - Data helpers for unaligned reads

nonisolated private extension Data {
    func loadUInt16(at offset: Int) -> UInt16 {
        withUnsafeBytes { buf in
            buf.loadUnaligned(fromByteOffset: offset, as: UInt16.self).littleEndian
        }
    }

    func loadUInt32(at offset: Int) -> UInt32 {
        withUnsafeBytes { buf in
            buf.loadUnaligned(fromByteOffset: offset, as: UInt32.self).littleEndian
        }
    }

    func loadUInt64(at offset: Int) -> UInt64 {
        withUnsafeBytes { buf in
            buf.loadUnaligned(fromByteOffset: offset, as: UInt64.self).littleEndian
        }
    }
}
