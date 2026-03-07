import tkinter as tk
from tkinter import filedialog, messagebox, ttk
import pandas as pd
from pathlib import Path
import matplotlib.pyplot as plt
from matplotlib.backends.backend_tkagg import FigureCanvasTkAgg
import numpy as np
from scipy.signal import savgol_filter, find_peaks
from spcparser import SpcParser  # Must be in same folder
import matplotlib
matplotlib.use('TkAgg')   # Ensures plots work perfectly inside the .app

class ShimadzuSPCAnalyzer:
    def __init__(self):
        self.root = tk.Tk()
        self.root.title("Shimadzu SPC Analyzer — Combine + Full Analysis")
        self.root.geometry("900x700")

        self.df = None  # Combined DataFrame
        self.x = None
        self.y_columns = None

        self.setup_ui()

    def setup_ui(self):
        tk.Label(self.root, text="Shimadzu SolidSpec-3700i Analyzer",
                 font=("Helvetica", 18, "bold")).pack(pady=10)

        tk.Button(self.root, text="1. Select Folder with .spc Files",
                  command=self.select_folder, bg="#4CAF50", fg="white",
                  font=("Helvetica", 12), height=2).pack(pady=10, fill="x", padx=20)

        tk.Button(self.root, text="Or Select Individual .spc Files",
                  command=self.select_files).pack(pady=5, fill="x", padx=20)

        self.status = tk.Label(self.root, text="No files loaded", fg="gray")
        self.status.pack(pady=10)

        # Analysis buttons (disabled until data loaded)
        self.btn_frame = tk.Frame(self.root)
        self.btn_frame.pack(pady=20)

        buttons = [
            ("Plot All Spectra", self.plot_raw),
            ("Plot Average Spectrum", self.plot_average),
            ("Apply Smoothing (Savitzky-Golay)", self.apply_smoothing),
            ("Baseline Correction", self.apply_baseline),
            ("Normalize Spectra", self.apply_normalization),
            ("Detect Peaks & Export Table", self.find_peaks),
            ("Export Processed Data", self.export_data)
        ]

        for text, cmd in buttons:
            tk.Button(self.btn_frame, text=text, command=cmd,
                      font=("Helvetica", 11), width=30, state="disabled").pack(pady=4)

        tk.Button(self.root, text="Quit", command=self.root.quit, bg="red", fg="white").pack(pady=20)

    def enable_buttons(self):
        for child in self.btn_frame.winfo_children():
            child.config(state="normal")

    def update_status(self, count):
        self.status.config(text=f"✅ {count} spectra loaded — ready for analysis!", fg="green")

    def load_files(self, file_list):
        try:
            data = {}
            x_ref = None
            for i, file in enumerate(file_list, 1):
                print(f"Reading {i}/{len(file_list)}: {file.name}")
                parser = SpcParser(str(file))
                parser.extract_data()
                x, y = parser.get_data()
                if x_ref is None:
                    x_ref = x
                data[file.stem] = y

            self.df = pd.DataFrame({"Wavelength_nm": x_ref})
            for name, yvals in data.items():
                self.df[name] = yvals
            self.x = self.df["Wavelength_nm"].values
            self.y_columns = [col for col in self.df.columns if col != "Wavelength_nm"]

            self.update_status(len(file_list))
            self.enable_buttons()
            messagebox.showinfo("Success", f"Loaded {len(file_list)} spectra!\nClick any analysis button below.")
        except Exception as e:
            messagebox.showerror("Error", f"Failed to read file:\n{str(e)}")

    def select_folder(self):
        folder = filedialog.askdirectory(title="Select folder with .spc files")
        if folder:
            files = list(Path(folder).rglob("*.spc"))
            if files:
                self.load_files(files)
            else:
                messagebox.showwarning("No files", "No .spc files found in folder.")

    def select_files(self):
        files = filedialog.askopenfilenames(title="Select .spc files", filetypes=[("SPC", "*.spc")])
        if files:
            self.load_files([Path(f) for f in files])

    def plot_raw(self):
        plt.figure(figsize=(10, 6))
        for col in self.y_columns:
            plt.plot(self.x, self.df[col], label=col, alpha=0.7)
        plt.xlabel("Wavelength (nm)")
        plt.ylabel("Absorbance / Intensity")
        plt.title("All Spectra Overlaid")
        plt.legend(bbox_to_anchor=(1.05, 1), loc='upper left')
        plt.grid(True, alpha=0.3)
        plt.tight_layout()
        plt.show()

    def plot_average(self):
        avg = self.df[self.y_columns].mean(axis=1)
        plt.figure(figsize=(10, 6))
        plt.plot(self.x, avg, 'b-', linewidth=2, label="Average Spectrum")
        plt.xlabel("Wavelength (nm)")
        plt.ylabel("Absorbance / Intensity")
        plt.title("Average of All Spectra")
        plt.legend()
        plt.grid(True, alpha=0.3)
        plt.show()

    def apply_smoothing(self):
        window = 11  # odd number
        poly = 2
        for col in self.y_columns:
            self.df[col] = savgol_filter(self.df[col], window, poly)
        messagebox.showinfo("Done", "Smoothing applied to all spectra!\nRe-plot to see changes.")

    def apply_baseline(self):
        # Simple polynomial baseline (degree 3) — works great for UV-Vis
        degree = 3
        for col in self.y_columns:
            y = self.df[col].values
            coeffs = np.polyfit(self.x, y, degree)
            baseline = np.polyval(coeffs, self.x)
            self.df[col] = y - baseline
        messagebox.showinfo("Done", "Polynomial baseline correction applied!\nRe-plot to see changes.")

    def apply_normalization(self):
        method = tk.simpledialog.askstring("Normalize", "Choose: min-max, area, or peak", initialvalue="min-max")
        if not method:
            return
        for col in self.y_columns:
            y = self.df[col].values
            if method.lower() == "min-max":
                self.df[col] = (y - y.min()) / (y.max() - y.min())
            elif method.lower() == "area":
                area = np.trapz(y, self.x)
                self.df[col] = y / area if area != 0 else y
            elif method.lower() == "peak":
                self.df[col] = y / y.max()
        messagebox.showinfo("Done", f"{method} normalization applied!")

    def find_peaks(self):
        peaks_data = []
        for col in self.y_columns:
            y = self.df[col].values
            peaks, _ = find_peaks(y, height=0.01, distance=5)
            for p in peaks:
                peaks_data.append({"Spectrum": col, "Wavelength": self.x[p], "Intensity": y[p]})

        peak_df = pd.DataFrame(peaks_data)
        save_path = filedialog.asksaveasfilename(defaultextension=".xlsx", filetypes=[("Excel", "*.xlsx")])
        if save_path:
            peak_df.to_excel(save_path, index=False)
            messagebox.showinfo("Peaks Exported", f"{len(peak_df)} peaks saved to:\n{save_path}")

    def export_data(self):
        ext = tk.simpledialog.askstring("Export", "Choose format: xlsx, csv, or jcamp", initialvalue="xlsx")
        if not ext:
            return
        initial = "Processed_Spectra"
        save_path = filedialog.asksaveasfilename(initialfile=initial, defaultextension=f".{ext}")
        if not save_path:
            return

        if ext == "xlsx":
            self.df.to_excel(save_path, index=False)
        elif ext == "csv":
            self.df.to_csv(save_path, index=False)
        elif ext == "jcamp":
            self.export_jcamp(save_path)

        messagebox.showinfo("Export Complete", f"Data saved to:\n{save_path}")

    def export_jcamp(self, path):
        with open(path, 'w') as f:
            f.write("##JCAMP-DX=5.00\n##TITLE=Combined Shimadzu Spectra\n")
            f.write(f"##NPOINTS={len(self.x)}\n")
            for col in self.y_columns:
                f.write(f"##XYDATA= {col}\n")
                for xi, yi in zip(self.x, self.df[col]):
                    f.write(f"{xi:.2f}, {yi:.6f}\n")
            f.write("##END=\n")
        messagebox.showinfo("JCAMP Exported", "JCAMP-DX file created (readable by most spectroscopy software)")


if __name__ == "__main__":
    app = ShimadzuSPCAnalyzer()
    app.root.mainloop()