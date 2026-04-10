import Foundation
import os

struct ShimadzuSPCRawSpectrum: Sendable {
    let name: String
    let x: [Double]
    let y: [Double]
}

final class ShimadzuSpectrum: Identifiable, @unchecked Sendable {
    let id = UUID()
    let name: String

    /// The StoredDataset ID this spectrum was loaded from, used to keep the
    /// session-restore file in sync when individual spectra are removed.
    private nonisolated(unsafe) var _sourceDatasetID: UUID?
    var sourceDatasetID: UUID? {
        get { lock.withLockUnchecked { _sourceDatasetID } }
        set { lock.withLockUnchecked { _sourceDatasetID = newValue } }
    }

    private nonisolated(unsafe) var xCache: [Double]?
    private nonisolated(unsafe) var yCache: [Double]?
    private let xData: Data?
    private let yData: Data?
    private let lock = OSAllocatedUnfairLock()

    init(name: String, x: [Double], y: [Double]) {
        self.name = name
        self.xCache = x
        self.yCache = y
        self.xData = nil
        self.yData = nil
    }

    init(name: String, xData: Data, yData: Data) {
        self.name = name
        // Eagerly decode so .x/.y getters are lock-free in the common path
        self.xCache = SpectrumBinaryCodec.decodeDoubles(from: xData)
        self.yCache = SpectrumBinaryCodec.decodeDoubles(from: yData)
        self.xData = xData
        self.yData = yData
    }

    var x: [Double] {
        if let cached = xCache { return cached }
        // Fallback for after unloadCachedData() — re-decode from binary
        return lock.withLockUnchecked {
            if let cached = xCache { return cached }
            if let xData {
                let decoded = SpectrumBinaryCodec.decodeDoubles(from: xData)
                xCache = decoded
                return decoded
            }
            return []
        }
    }

    var y: [Double] {
        if let cached = yCache { return cached }
        // Fallback for after unloadCachedData() — re-decode from binary
        return lock.withLockUnchecked {
            if let cached = yCache { return cached }
            if let yData {
                let decoded = SpectrumBinaryCodec.decodeDoubles(from: yData)
                yCache = decoded
                return decoded
            }
            return []
        }
    }

    func unloadCachedData() {
        lock.withLockUnchecked {
            if xData != nil { xCache = nil }
            if yData != nil { yCache = nil }
        }
    }
}

enum ShimadzuSPCError: Error, CustomStringConvertible {
    case missingDataSetGroup
    case missingDataStream(String)
    case invalidDoubleData

    var description: String {
        switch self {
        case .missingDataSetGroup:
            return "Missing DataSetGroup in SPC file"
        case .missingDataStream(let name):
            return "Missing data stream: \(name)"
        case .invalidDoubleData:
            return "Invalid double data stream"
        }
    }
}

struct ShimadzuSPCParseResult: Sendable {
    let spectra: [ShimadzuSPCRawSpectrum]
    let skippedDataSets: [String]
    let metadata: ShimadzuSPCMetadata
    let headerInfoData: Data
}

struct ShimadzuSPCMetadata: Codable, Sendable {
    let fileName: String
    let fileSizeBytes: Int
    let directoryEntryNames: [String]
    let dataSetNames: [String]
    let headerInfoByteCount: Int
    let mainHeader: SPCMainHeader?
}

nonisolated final class ShimadzuSPCParser {
    private let compound: CompoundFile
    private let compoundFileURL: URL

    private let nameXData = "X Data.1"
    private let nameYData = "Y Data.1"
    private let name00 = "Root Entry"
    private let name05 = "DataStorage1"
    private let name08 = "DataSetGroup"
    private let name12 = "DataSetGroupHeaderInfo"
    private let setToDataPath = ["DataSpectrumStorage", "Data"]

    init(fileURL: URL) throws {
        self.compoundFileURL = fileURL
        self.compound = try CompoundFile(fileURL: fileURL)
        Task { @MainActor in
            Instrumentation.log(
                "SPC file opened",
                area: .importParsing,
                level: .info,
                details: "file=\(fileURL.lastPathComponent)"
            )
        }
    }

    func extractSpectra() throws -> [ShimadzuSPCRawSpectrum] {
        try extractSpectraResult().spectra
    }

    func extractSpectraResult() throws -> ShimadzuSPCParseResult {
        let started = Date()
        let dataSetGroupDir = try dirFromPath(rootIndex: 0, path: [name00, name05, name08])
        if dataSetGroupDir < 0 {
            Task { @MainActor in
                Instrumentation.log("SPC parse failed", area: .importParsing, level: .warning, details: "reason=missing DataSetGroup")
            }
            throw ShimadzuSPCError.missingDataSetGroup
        }

        let groupChild = try getDirLRC(dataSetGroupDir).child
        let groupContents = try traverseDirSiblings(startIndex: groupChild)
        let dataSets = try groupContents.filter { index in
            let name = try getDirName(index)
            return name != name12
        }
        let dataSetNames = try dataSets.map { try getDirName($0) }
        let headerInfoIndex = try groupContents.first { index in
            let name = try getDirName(index)
            return name == name12
        }
        let headerInfoData = try headerInfoIndex.map { try readRawStream($0) } ?? Data()

        var spectra: [ShimadzuSPCRawSpectrum] = []
        var skippedDataSets: [String] = []
        for ds in dataSets {
            let name = try getDirName(ds)
            let dataDir = try dirFromPath(rootIndex: ds, path: [name] + setToDataPath)
            if dataDir < 0 {
                continue
            }

            var xData: [Double] = []
            var yData: [Double] = []

            let child = try getDirLRC(dataDir).child
            let children = try traverseDirSiblings(startIndex: child)
            for childIndex in children {
                let childName = try getDirName(childIndex)
                if childName == nameXData {
                    xData = try readDoubleStream(childIndex)
                } else if childName == nameYData {
                    yData = try readDoubleStream(childIndex)
                }
            }

            if xData.isEmpty || yData.isEmpty {
                skippedDataSets.append(name)
                continue
            }

            spectra.append(ShimadzuSPCRawSpectrum(name: name, x: xData, y: yData))
        }

        if spectra.isEmpty, let firstSkipped = skippedDataSets.first {
            throw ShimadzuSPCError.missingDataStream(firstSkipped)
        }

        let directoryEntryNames = compound.allDirectoryEntries().map { $0.name }.filter { !$0.isEmpty }
        let fileSizeBytes = (try? FileManager.default.attributesOfItem(atPath: compoundFileURL.path)[.size] as? NSNumber)?.intValue ?? 0
        let mainHeader = SPCHeaderParser.parseMainHeader(from: headerInfoData)
        let metadata = ShimadzuSPCMetadata(
            fileName: compoundFileURL.lastPathComponent,
            fileSizeBytes: fileSizeBytes,
            directoryEntryNames: directoryEntryNames,
            dataSetNames: dataSetNames,
            headerInfoByteCount: headerInfoData.count,
            mainHeader: mainHeader
        )
        let result = ShimadzuSPCParseResult(
            spectra: spectra,
            skippedDataSets: skippedDataSets,
            metadata: metadata,
            headerInfoData: headerInfoData
        )
        let duration = Date().timeIntervalSince(started)
        let spectraCount = spectra.count
        let skippedCount = skippedDataSets.count
        Task { @MainActor in
            Instrumentation.log(
                "SPC parse completed",
                area: .importParsing,
                level: .info,
                details: "spectra=\(spectraCount) skipped=\(skippedCount)",
                duration: duration
            )
        }
        return result
    }

    private func readDoubleStream(_ index: Int32) throws -> [Double] {
        let entry = try compound.directoryEntry(at: index)
        let data = try compound.streamData(for: entry)
        if data.count % 8 != 0 { throw ShimadzuSPCError.invalidDoubleData }

        return data.withUnsafeBytes { rawPtr in
            let count = data.count / 8
            var values: [Double] = []
            values.reserveCapacity(count)
            for i in 0..<count {
                let offset = i * 8
                let val = rawPtr.load(fromByteOffset: offset, as: UInt64.self).littleEndian
                values.append(Double(bitPattern: val))
            }
            return values
        }
    }

    private func readRawStream(_ index: Int32) throws -> Data {
        let entry = try compound.directoryEntry(at: index)
        return try compound.streamData(for: entry)
    }

    private func getDirName(_ index: Int32) throws -> String {
        try compound.directoryEntry(at: index).name
    }

    private func getDirLRC(_ index: Int32) throws -> (left: Int32, right: Int32, child: Int32) {
        let entry = try compound.directoryEntry(at: index)
        return (entry.leftSibling, entry.rightSibling, entry.child)
    }

    private func strComp(_ lhs: String, _ rhs: String) -> Bool {
        if lhs.count != rhs.count {
            return lhs.count > rhs.count
        }
        return lhs > rhs
    }

    private func findInTree(_ name: String, startIndex: Int32) throws -> Int32 {
        var current = startIndex
        var visited: Set<Int32> = []

        while current != -1 {
            if visited.contains(current) {
                break
            }
            visited.insert(current)
            let nodeName = try getDirName(current)
            if nodeName == name {
                return current
            }
            let lrc = try getDirLRC(current)
            if strComp(name, nodeName) {
                current = lrc.right
            } else {
                current = lrc.left
            }
        }

        return -1
    }

    private func traverseDirSiblings(startIndex: Int32) throws -> [Int32] {
        if startIndex < 0 { return [] }
        var nodes: [Int32] = []
        var queue: [Int32] = [startIndex]
        var visited: Set<Int32> = []

        while let node = queue.popLast() {
            if visited.contains(node) { continue }
            visited.insert(node)
            nodes.append(node)

            let lrc = try getDirLRC(node)
            if lrc.left > -1 { queue.append(lrc.left) }
            if lrc.right > -1 { queue.append(lrc.right) }
        }
        return nodes
    }

    private func dirFromPath(rootIndex: Int32, path: [String]) throws -> Int32 {
        var node = rootIndex
        if path.isEmpty { return node }

        for name in path.dropLast() {
            node = try findInTree(name, startIndex: node)
            if node == -1 { return -1 }
            node = try getDirLRC(node).child
        }
        return try findInTree(path.last ?? "", startIndex: node)
    }
}
