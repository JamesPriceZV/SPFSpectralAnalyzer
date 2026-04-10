@Article(
    title: "Training Machine Learning Models"
)

## Overview
SPF Spectral Analyzer includes two types of machine learning models you can train on your own data. The **CreateML SPF Predictor** estimates Sun Protection Factor from UV-Vis spectra and trains entirely on-device — no coding required. **PINN Physics Models** are advanced physics-informed neural networks for 10 spectral domains that require Python and PyTorch on macOS.

Both systems produce CoreML models that sync automatically to iOS and iPadOS via iCloud.

## What Are the Models?

### CreateML SPF Predictor (Beginner-Friendly)
A boosted tree regressor that learns to predict SPF from UV-Vis spectral features. It trains entirely within the app using Apple's Create ML framework. No Python, no terminal commands — just tag your reference data and click a button.

**Best for:** Users who want quick, practical SPF predictions from their in-vitro spectral data.

### PINN Physics Models (Advanced)
Ten domain-specific physics-informed neural networks that encode spectral physics (Beer-Lambert law, Kramers-Kronig relations, etc.) directly into the model architecture. Each domain covers a different spectral technique: UV-Vis, FTIR, Raman, Mass Spec, NMR, Fluorescence, XRD, Chromatography, NIR, and Atomic Emission.

**Best for:** Researchers who need physics-constrained predictions that respect known spectral relationships.

---

## Training the CreateML SPF Predictor

### What You Need
- At least **5 reference datasets** with known in-vivo SPF values (more is better)
- Spectra measured in absorbance mode, 290–400 nm range
- A mix of low-SPF (5–15) and high-SPF (30–50+) samples for best accuracy
- ISO 24443 compliant in-vitro UV absorbance spectra on PMMA plates (recommended)

### Step-by-Step Guide

**Step 1: Import your SPC files**
Go to the Library tab and import SPC files containing UV-Vis spectral data. Each file typically contains one or more spectra from an in-vitro sunscreen measurement.

**Step 2: Tag datasets as references**
Right-click a dataset in the sidebar and select **"Set as Reference..."**. Enter the known in-vivo SPF value for that formulation. This is the SPF measured on human subjects that the model will learn to predict.

> **Tip:** You need at least 5 tagged references. For best accuracy, aim for 15–30 covering a range of SPF values and formulation types (mineral, organic, combination).

**Step 3: Check the reference count**
Go to the **ML Training** tab. Select **SPF Predictor** in the sidebar. The detail pane shows how many reference spectra are available. The count must be at least 5.

**Step 4: Train the model**
Click **"Train CreateML Model"**. Training typically takes 10–30 seconds depending on dataset size. You'll see a progress indicator with three stages:
1. **Preparing data** — Fetching and resampling spectra to the standard 290–400 nm grid
2. **Training** — Fitting the boosted tree regressor on your features
3. **Evaluating** — Computing R-squared and RMSE on a held-out validation set

**Step 5: Review the results**
After training, the detail pane shows:
- **R-squared (R²):** How well the model fits. Values above 0.85 are good; above 0.95 is excellent.
- **RMSE:** Root mean squared error — the average prediction error in SPF units.
- **Datasets / Spectra:** How much training data was used.

**Step 6: Use your model**
The model is now active. Select any dataset in the Library and open the Analysis tab — you'll see an ML-predicted SPF with a confidence interval alongside the traditional COLIPA/ISO estimates.

### Feature Schema
The model uses a 122-feature hybrid input:
- **111 spectral features:** Absorbance at 290–400 nm in 1 nm steps
- **7 derived metrics:** Critical wavelength, UVA/UVB ratio, UVB area, UVA area, mean UVB/UVA transmittance, peak absorbance wavelength
- **4 auxiliary features:** Plate type, application quantity, formulation type, post-irradiation flag

### Conformal Prediction Intervals
Instead of point estimates, the model provides calibrated confidence intervals:
- Training data is split 80/20: 80% for training, 20% for calibration
- Calibration residuals compute prediction intervals at 90% coverage
- Results display as: "SPF 32.5 (28.1–36.9)"
- The coverage level is configurable in Settings → ML Training → CreateML Defaults

---

## Training PINN Physics Models

### Prerequisites
- **macOS** (PINN training is not available on iOS/iPadOS)
- **Python 3.10+** installed on your system
- **PyTorch** and **coremltools v7+** (`pip install torch coremltools`)
- Training scripts placed in the app's Scripts directory

### Step-by-Step Guide

**Step 1: Install Python dependencies**
Open Terminal and run:
```
pip install torch coremltools
```
If you use a virtual environment or conda, configure the Python path in Settings → ML Training → Python Environment.

**Step 2: Locate the Scripts directory**
Go to Settings → ML Training → Python Environment and click **"Open Scripts Folder"**. This opens the directory where training scripts must be placed.

Each PINN domain expects a script named `train_pinn_{domain}.py` (e.g., `train_pinn_uv_vis.py`). Example scripts are available in the project repository.

**Step 3: Prepare reference data**
You have two options:
- **Internal data:** Import SPC files and tag datasets as "reference" with known target values (same as CreateML workflow)
- **External data:** Import a JSON or CSV file with pre-formatted training data

**Step 4: Export training data**
Go to the ML Training tab → select a PINN domain → click **"Export Training Data"**. This generates a JSON file containing wavelengths, intensities, and target values for all matching reference datasets.

**Step 5: Train the model**
Set your desired hyperparameters (epochs and learning rate) and click **"Train Model"**. Training progress shows multiple phases:
1. **Exporting data** — Writing reference data to JSON
2. **Training** — Running the Python script (epoch/loss updates in the loss chart)
3. **Converting** — Converting the trained PyTorch model to CoreML format
4. **Importing** — Loading the CoreML model into the app

**Step 6: Monitor the loss chart**
The Training Loss chart shows two curves:
- **Data Loss:** How well the model fits the training data
- **Physics Loss:** How well the model satisfies the physics constraints

Both should decrease during training. If physics loss increases, try a lower learning rate.

**Step 7: Use the trained model**
After training completes, the model loads automatically. Trained models sync to iOS/iPadOS via iCloud.

### Training Data Formats

**JSON format:**
```json
[
  {
    "wavelengths": [290, 291, 292, ...],
    "intensities": [0.45, 0.47, 0.49, ...],
    "knownValue": 32.0,
    "plateType": "PMMA",
    "applicationQuantityMg": 1.3
  }
]
```

**CSV format:**
Columns: `wavelength_1, wavelength_2, ..., target_value`
The first row should be a header. Each subsequent row is one spectrum.

---

## Configuring ML Training Settings

Go to **Settings → ML Training** to configure:

- **PINN Training Defaults:** Default epochs (100–2000) and learning rate (1e-5 to 1e-1)
- **Python Environment** (macOS): Python path and scripts folder location
- **CreateML Defaults:** Max iterations, max depth, conformal interval level
- **Model Storage:** Where trained models are stored on disk
- **ML Training Logging:** Enable structured logging for training events

---

## Model Management

- **Reset Model:** Deletes the trained CreateML model and clears metrics. Access from the CreateML detail pane.
- **Retrain:** Click "Train" again after adding more reference data for improved accuracy.
- **Storage:** Compiled models are stored in `Application Support/com.zincoverde.SPFSpectralAnalyzer/Models/` and persist across launches.
- **iCloud Sync:** Trained models sync automatically to all your devices.

---

## Troubleshooting

### "Not enough reference data"
You need at least 5 tagged reference datasets. Go to the Library, right-click datasets, and select "Set as Reference..." to tag them with known SPF values.

### "Python script not found"
Check that the training script exists in the Scripts directory with the correct filename. Go to Settings → ML Training → Python Environment → "Open Scripts Folder" to verify.

### "Training failed: Python process exited"
Verify your Python installation meets the requirements:
1. Open Terminal and run `python3 --version` (must be 3.10+)
2. Run `python3 -c "import torch; print(torch.__version__)"` to verify PyTorch
3. Run `python3 -c "import coremltools; print(coremltools.__version__)"` to verify coremltools (must be 7+)

### Model not appearing on iOS
Check iCloud sync status in Settings → iCloud & Data. Models sync through the app's CloudKit container and may take a few minutes to propagate.

### R-squared is low (< 0.70)
- Add more diverse reference samples (aim for 15–30+)
- Ensure spectra cover the full 290–400 nm range
- Include a mix of SPF values and formulation types
- Check that in-vivo SPF values are correctly entered

## Platform Notes
- **CreateML training:** macOS only (requires Create ML framework)
- **PINN training:** macOS only (requires Python + PyTorch)
- **Predictions:** Work on macOS, iOS, and iPadOS using the CoreML runtime
- **Model sync:** Automatic via iCloud to all devices signed into the same Apple Account
