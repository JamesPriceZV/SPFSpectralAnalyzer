import SwiftUI
import SwiftData

struct ReferenceLibraryView: View {
    @Query private var spectra: [StoredReferenceSpectrum]
    @State private var selectedModality: SpectralModality? = nil
    @State private var searchText = ""

    var filtered: [StoredReferenceSpectrum] {
        spectra.filter { s in
            (selectedModality == nil || s.modalityRaw == selectedModality?.rawValue) &&
            (searchText.isEmpty || s.sourceID.localizedCaseInsensitiveContains(searchText))
        }
    }

    var body: some View {
        NavigationSplitView {
            List(SpectralModality.allCases, selection: $selectedModality) { modality in
                Label(modality.displayName, systemImage: modality.systemImage)
                    .tag(Optional(modality))
            }
            .listStyle(.sidebar)
            .navigationTitle("Modalities")
        } detail: {
            List(filtered, id: \.sourceID) { spectrum in
                VStack(alignment: .leading) {
                    Text(spectrum.sourceID).font(.headline)
                    Text(spectrum.modalityRaw).font(.caption).foregroundStyle(.secondary)
                }
            }
            .searchable(text: $searchText)
            .navigationTitle(selectedModality?.displayName ?? "All Spectra")
        }
    }
}
