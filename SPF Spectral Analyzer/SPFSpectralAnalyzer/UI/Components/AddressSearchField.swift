import SwiftUI
@preconcurrency import MapKit

/// A text field with address autocomplete powered by MapKit.
///
/// Displays completion suggestions as the user types, resolves coordinates
/// on selection, and shows a small map preview of the resolved location.
struct AddressSearchField: View {
    @Binding var addressText: String
    @Binding var latitude: Double?
    @Binding var longitude: Double?

    @State private var completer = AddressCompleterCoordinator()
    @State private var showSuggestions = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("Address (start typing...)", text: $addressText)
                .textFieldStyle(.roundedBorder)
                .onChange(of: addressText) { _, newValue in
                    completer.updateQuery(newValue)
                    showSuggestions = !newValue.isEmpty
                }

            if showSuggestions && !completer.suggestions.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(completer.suggestions, id: \.self) { completion in
                            Button {
                                let title = completion.title
                                let subtitle = completion.subtitle
                                addressText = subtitle.isEmpty ? title : "\(title), \(subtitle)"
                                showSuggestions = false
                                resolveCoordinates(for: completion)
                            } label: {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(completion.title)
                                        .font(.caption)
                                        .foregroundColor(.primary)
                                    if !completion.subtitle.isEmpty {
                                        Text(completion.subtitle)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                        }
                    }
                }
                .frame(maxHeight: 150)
                .background(Color.platformBackground)
                .cornerRadius(8)
                .shadow(radius: 2)
            }

            if let lat = latitude, let lon = longitude {
                mapPreview(latitude: lat, longitude: lon)
            }
        }
        .onDisappear {
            completer.cancel()
        }
    }

    @ViewBuilder
    private func mapPreview(latitude: Double, longitude: Double) -> some View {
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let region = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )

        Map(initialPosition: .region(region)) {
            Marker(addressText, coordinate: coordinate)
        }
        .frame(height: 120)
        .cornerRadius(8)
        .allowsHitTesting(false)
    }

    private func resolveCoordinates(for completion: MKLocalSearchCompletion) {
        let request = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: request)
        Task {
            guard let response = try? await search.start(),
                  let mapItem = response.mapItems.first else { return }
            latitude = mapItem.location.coordinate.latitude
            longitude = mapItem.location.coordinate.longitude
        }
    }
}

// MARK: - MKLocalSearchCompleter Coordinator

@MainActor
@Observable
final class AddressCompleterCoordinator: NSObject, MKLocalSearchCompleterDelegate {
    private let searchCompleter = MKLocalSearchCompleter()
    private(set) var suggestions: [MKLocalSearchCompletion] = []

    override init() {
        super.init()
        searchCompleter.delegate = self
        searchCompleter.resultTypes = .address
    }

    func updateQuery(_ query: String) {
        searchCompleter.queryFragment = query
    }

    /// Cancel the completer to stop CLLocationManager polling.
    func cancel() {
        searchCompleter.cancel()
        searchCompleter.delegate = nil
        suggestions = []
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let results = completer.results
        Task { @MainActor in
            self.suggestions = results
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in
            self.suggestions = []
        }
    }
}
