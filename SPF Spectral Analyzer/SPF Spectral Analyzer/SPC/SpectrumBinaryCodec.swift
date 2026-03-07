import Foundation

enum SpectrumBinaryCodec {
    static nonisolated func encodeDoubles(_ values: [Double]) -> Data {
        var data = Data()
        data.reserveCapacity(values.count * 8)
        for value in values {
            var bits = value.bitPattern.littleEndian
            withUnsafeBytes(of: &bits) { buffer in
                data.append(contentsOf: buffer)
            }
        }
        return data
    }

    static nonisolated func decodeDoubles(from data: Data) -> [Double] {
        guard !data.isEmpty else { return [] }
        let count = data.count / 8
        var values: [Double] = []
        values.reserveCapacity(count)
        data.withUnsafeBytes { rawPtr in
            for i in 0..<count {
                let offset = i * 8
                let bits = rawPtr.load(fromByteOffset: offset, as: UInt64.self).littleEndian
                values.append(Double(bitPattern: bits))
            }
        }
        return values
    }
}
