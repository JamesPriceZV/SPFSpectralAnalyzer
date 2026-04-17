import Foundation

/// Library of common UV filter molar absorptivities for Beer-Lambert SPF synthesis.
nonisolated enum UVFilterLibrary {

    struct UVFilter: Sendable {
        let name: String
        let casNumber: String
        let lambdaMax: Double          // nm
        let molarAbsorptivity: Double  // L/(mol·cm) at lambdaMax
        let category: FilterCategory
    }

    enum FilterCategory: String, Sendable {
        case uvbOrganic = "UVB Organic"
        case uvaOrganic = "UVA Organic"
        case broadSpectrum = "Broad Spectrum"
        case inorganic = "Inorganic"
    }

    /// Common UV filters with published molar absorptivities.
    static let filters: [UVFilter] = [
        // UVB Organic Filters
        UVFilter(name: "Octinoxate (OMC)", casNumber: "5466-77-3",
                 lambdaMax: 311, molarAbsorptivity: 23_300, category: .uvbOrganic),
        UVFilter(name: "Octisalate", casNumber: "118-60-5",
                 lambdaMax: 307, molarAbsorptivity: 5_200, category: .uvbOrganic),
        UVFilter(name: "Homosalate", casNumber: "118-56-9",
                 lambdaMax: 306, molarAbsorptivity: 4_740, category: .uvbOrganic),
        UVFilter(name: "Octocrylene", casNumber: "6197-30-4",
                 lambdaMax: 303, molarAbsorptivity: 12_250, category: .uvbOrganic),
        UVFilter(name: "Ensulizole (PBSA)", casNumber: "27503-81-7",
                 lambdaMax: 302, molarAbsorptivity: 27_000, category: .uvbOrganic),
        UVFilter(name: "Padimate O", casNumber: "21245-02-3",
                 lambdaMax: 311, molarAbsorptivity: 27_500, category: .uvbOrganic),

        // UVA Organic Filters
        UVFilter(name: "Avobenzone", casNumber: "70356-09-1",
                 lambdaMax: 357, molarAbsorptivity: 31_200, category: .uvaOrganic),
        UVFilter(name: "Meradimate", casNumber: "1041-00-5",
                 lambdaMax: 340, molarAbsorptivity: 6_000, category: .uvaOrganic),

        // Broad Spectrum
        UVFilter(name: "Bemotrizinol (BEMT)", casNumber: "187393-00-6",
                 lambdaMax: 343, molarAbsorptivity: 49_200, category: .broadSpectrum),
        UVFilter(name: "Ecamsule (Mexoryl SX)", casNumber: "92761-26-7",
                 lambdaMax: 345, molarAbsorptivity: 46_700, category: .broadSpectrum),
        UVFilter(name: "Bisoctrizole (MBBT)", casNumber: "103597-45-1",
                 lambdaMax: 353, molarAbsorptivity: 43_500, category: .broadSpectrum),

        // Inorganic
        UVFilter(name: "Zinc Oxide", casNumber: "1314-13-2",
                 lambdaMax: 370, molarAbsorptivity: 0, category: .inorganic),
        UVFilter(name: "Titanium Dioxide", casNumber: "13463-67-7",
                 lambdaMax: 350, molarAbsorptivity: 0, category: .inorganic),
    ]

    /// Lookup filter by CAS number.
    static func filter(byCAS cas: String) -> UVFilter? {
        filters.first { $0.casNumber == cas }
    }

    /// All filters in a given category.
    static func filters(in category: FilterCategory) -> [UVFilter] {
        filters.filter { $0.category == category }
    }
}
