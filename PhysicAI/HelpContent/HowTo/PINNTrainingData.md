@Article(
    title: "PINN Training Data System"
)

## Overview
The PINN Training Data System is a universal physics-informed spectral data pipeline that covers 30 spectral modalities. It downloads free reference spectra from public databases, applies physics-based synthesis to generate training records, and exports datasets for CoreML model training.

Access the Training Data Dashboard from the ML Training tab to monitor progress across all modalities.

## Supported Modalities (30)

The system spans every major branch of spectroscopy and physical measurement:

### Molecular Spectroscopy
- **UV-Vis Absorption** — Beer-Lambert law, COLIPA SPF calculation
- **FTIR (Mid-IR)** — Beer-Lambert in wavenumber space, functional group identification
- **Near-Infrared (NIR)** — Anharmonic overtone positions, moisture/protein analysis
- **Raman Scattering** — Bose-Einstein thermal correction, mineral identification
- **Fluorescence** — Jablonski model, Stokes shift, quantum yield prediction

### Mass Spectrometry
- **Mass Spec (EI)** — Isotope patterns, fragmentation rules
- **MS/MS (Tandem)** — CID fragmentation, neutral loss detection

### Nuclear Magnetic Resonance
- **1H NMR** — Shoolery additive rules, Karplus coupling
- **13C NMR** — Grant-Paul increments, HOSE code predictions

### X-ray and Electron Methods
- **XRD Powder** — Bragg diffraction, Scherrer crystallite sizing
- **XPS** — Photoelectric equation, Scofield cross-sections
- **EELS** — Core-loss edge detection, Kramers-Kronig analysis

### Atomic and Plasma Spectroscopy
- **Atomic Emission (OES)** — Boltzmann population, Rydberg formula
- **LIBS** — Saha-Boltzmann plasma model, Stark broadening

### Chromatography
- **GC Retention Index** — Kovats RI, Abraham LSER descriptors
- **HPLC Retention** — Martin-Synge LFER, molecular descriptor features

### Atmospheric and Environmental
- **HITRAN Molecular Lines** — Voigt profile simulation, temperature scaling
- **Atmospheric UV/Vis** — Cross-section databases, photolysis J-values
- **USGS Reflectance** — Kubelka-Munk transform, mineral reflectance

### Materials and Condensed Matter
- **Optical Constants (n, k)** — Sellmeier dispersion, Abbe number
- **SAXS / SANS** — Guinier approximation, radius of gyration
- **Circular Dichroism** — Basis spectrum decomposition, secondary structure
- **Microwave / Rotational** — Rigid rotor model, rotational constants
- **Thermogravimetric (TGA)** — Arrhenius/Coats-Redfern kinetics
- **Terahertz (THz)** — Drude-Lorentz oscillator model

### Quantum Mechanics Layer
- **DFT / Quantum Chemistry** — Kohn-Sham DFT, Coulomb matrix eigenvalues, HOMO-LUMO gap prediction
- **Mössbauer Spectroscopy** — Recoil-free fraction, isomer shift, quadrupole splitting, magnetic hyperfine field
- **Quantum Dot Photoluminescence** — Brus equation, size-dependent quantum confinement bandgap
- **Auger Electron Spectroscopy (AES)** — Kinetic energy derivative spectra, Wagner parameter, element quantification
- **Neutron Diffraction** — Bragg diffraction with isotope-specific coherent scattering lengths

## How It Works

### 1. Reference Data Sources
Each modality has one or more free, public data sources:
- NIST WebBook, SRD 20, SRD 35, ASD
- RRUFF mineral database
- MoNA, MassBank, GNPS (mass spectrometry)
- nmrshiftdb2, SDBS (NMR)
- FPbase, PhotochemCAD (fluorescence)
- COD, AMCSD (crystallography)
- HITRAN (molecular lines)
- MPI-Mainz Atlas (atmospheric UV/Vis)
- USGS splib07 (reflectance)
- refractiveindex.info (optical constants)
- eelsdb.eu, SASBDB, PCDDB, CDMS (specialized databases)
- QM9 / PubChemQC (quantum chemistry computed properties)
- Zenodo / ISEDB (Mössbauer spectroscopy)
- ILL Data Portal (neutron diffraction patterns)
- NIST SRD 29 (Auger electron spectroscopy)

### 2. Physics-Informed Synthesis
Each modality has a dedicated synthesizer that encodes domain-specific physics:
- Spectra are mixed according to physical laws (Beer-Lambert, Bragg, Boltzmann, etc.)
- Noise, background, and instrument effects are added realistically
- Derived features (band ratios, peak positions, integrals) are computed automatically
- Labels are computed from the physics model, not manual annotation

### 3. Training Record Storage
Synthesized records are stored in SwiftData as `StoredTrainingRecord` objects:
- Feature vectors are stored as binary `Data` for efficiency
- Target values and metadata are stored as JSON dictionaries
- Records are tagged by modality for selective export

### 4. CSV Export
The exporter writes one CSV file per modality with columns matching the modality's feature schema. These CSVs can be used directly with CreateML or external training pipelines.

## Using the Dashboard

The Training Data Dashboard shows a card for each modality displaying:
- **Status** — Idle, Downloading, Synthesizing, Training, Ready, or Error
- **Record count** — Number of training records generated
- **Physics law** — The governing equation for that modality
- **Data source** — Where the reference data comes from

### Preparing Data
1. Open the ML Training tab
2. Select "Training Data Dashboard"
3. Click "Prepare All" to begin downloading references and synthesizing training records for all 30 modalities
4. Each modality runs independently — you can monitor progress per card

### Exporting for Training
1. After records are synthesized, click "Export All" in the dashboard toolbar
2. Choose a destination folder
3. One CSV per modality is written, ready for model training

## Reference Library

The Reference Library view lets you browse all downloaded reference spectra:
- Filter by modality using the sidebar
- Search by source ID or metadata
- Preview spectral data before synthesis

## Technical Details

### Feature Vectors
Each modality defines a fixed-size feature vector (52 to 1272 features depending on the technique). Several modalities include expanded quantum-mechanical features such as orbital occupation fractions, electron density metrics, and DFT-derived descriptors. Features include:
- Spectral bin values on a canonical grid
- Derived physics metrics (band ratios, peak positions, integrals, indices)
- Condition parameters (temperature, pressure, concentration)

### Parsers
Nine specialized parsers handle different data formats:
- **JCAMP-DX** — Universal format for UV, IR, Raman, NMR, MS
- **CIF** — Crystallographic Information File for XRD and neutron diffraction
- **HITRAN .par** — Fixed-width 160-character line parameters
- **USGS .txt** — Two-column wavelength/reflectance ASCII
- **Refractive Index YAML** — Tabulated n,k from refractiveindex.info
- **EELS JSON** — eelsdb.eu API format
- **SASBDB JSON** — Small-angle scattering profiles
- **CDMS .cat** — Microwave spectroscopy catalog format
- **Mössbauer JSON** — Velocity-transmission spectra with hyperfine parameters
- **QM9 Extended-XYZ** — Molecular geometry and DFT-computed thermochemistry from QM9

### Concurrency
All synthesizers are Swift actors for thread-safe concurrent operation. The coordinator uses TaskGroup to run independent modalities in parallel.
