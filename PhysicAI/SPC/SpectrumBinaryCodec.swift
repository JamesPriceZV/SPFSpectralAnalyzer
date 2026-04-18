import Foundation

enum SpectrumBinaryCodec {
    static nonisolated func encodeDoubles(_ values: [Double]) -> Data {
        values.withUnsafeBytes { buffer in
            Data(bytes: buffer.baseAddress!, count: buffer.count)
        }
    }

    static nonisolated func decodeDoubles(from data: Data) -> [Double] {
        guard !data.isEmpty, data.count % MemoryLayout<Double>.stride == 0 else {
            return []
        }
        return data.withUnsafeBytes { rawBuffer in
            let typedBuffer = rawBuffer.bindMemory(to: Double.self)
            return Array(typedBuffer)
        }
    }
}
