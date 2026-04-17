import Foundation
import SwiftData

@Model
final class StoredReferenceSpectrum {
    var id: UUID = UUID()
    var modalityRaw: String = ""
    var sourceID: String = ""
    var xData: Data = Data()
    var yData: Data = Data()
    var metadataJSON: [String: String] = [:]

    init() {}

    init(from ref: ReferenceSpectrum) {
        self.id = ref.id
        self.modalityRaw = ref.modality.rawValue
        self.sourceID = ref.sourceID
        self.xData = ref.xValues.withUnsafeBufferPointer { Data(buffer: $0) }
        self.yData = ref.yValues.withUnsafeBufferPointer { Data(buffer: $0) }
        self.metadataJSON = ref.metadata
    }
}
