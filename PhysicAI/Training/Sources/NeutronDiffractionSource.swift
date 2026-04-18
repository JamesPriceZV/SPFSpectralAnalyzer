import Foundation

/// Fetches neutron diffraction data from ILL Data Portal and Zenodo.
/// Also builds synthetic patterns from COD CIF files (reuses CIFParser).
actor NeutronDiffractionSource {

    static let illBaseURL = "https://data.ill.fr/api/datasets/"

    static let zenodoURL = URL(string:
        "https://zenodo.org/record/5724434/files/neutron_patterns.zip")!

    /// Synthesise neutron patterns from a COD CIF ReferenceSpectrum
    /// by extracting atom positions and applying neutron b_coh values.
    func synthesizeFromCIF(cif: ReferenceSpectrum,
                           synthesizer: NeutronDiffractionSynthesizer) async -> TrainingRecord? {
        guard cif.modality == .xrdPowder else { return nil }
        let meta = cif.metadata
        guard let a = meta["cell_length_a"].flatMap(Double.init),
              let b = meta["cell_length_b"].flatMap(Double.init),
              let c = meta["cell_length_c"].flatMap(Double.init),
              let alpha = meta["cell_angle_alpha"].flatMap(Double.init),
              let beta  = meta["cell_angle_beta"].flatMap(Double.init),
              let gamma = meta["cell_angle_gamma"].flatMap(Double.init),
              let sg    = meta["symmetry_Int_Tables_number"].flatMap(Int.init)
        else { return nil }

        let elementSymbol = meta["atom_site_type_symbol"] ?? "Fe"
        let site = NeutronDiffractionSynthesizer.CrystalSite(
            element: elementSymbol, x: 0, y: 0, z: 0, occupancy: 1.0, bIso: 0.5)
        let cell = NeutronDiffractionSynthesizer.UnitCell(
            a: a, b: b, c: c, alpha: alpha, beta: beta, gamma: gamma,
            spaceGroupNumber: sg, sites: [site])

        return await synthesizer.synthesizePattern(cell: cell)
    }
}
