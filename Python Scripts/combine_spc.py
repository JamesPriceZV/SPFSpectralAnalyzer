import tkinter as tk
from tkinter import filedialog, messagebox
import pandas as pd
from pathlib import Path
import os

# Import the Shimadzu-specific parser (must be in same folder)
from spcparser import SpcParser


class ShimadzuSPCCombiner:
    def __init__(self):
        self.root = tk.Tk()
        self.root.title("Shimadzu .spc Combiner — 94 Files → 1 File")
        self.root.geometry("700x500")
        self.root.configure(padx=20, pady=20)

        tk.Label(self.root, text="Shimadzu SolidSpec-3700i SPC Combiner",
                 font=("Helvetica", 16, "bold")).pack(pady=10)
        tk.Label(self.root, text="Select folder or files → Combine into one clean Excel/CSV",
                 font=("Helvetica", 11)).pack(pady=5)

        tk.Button(self.root, text="1. Select Folder (recommended)",
                  command=self.select_folder, bg="#4CAF50", fg="white",
                  font=("Helvetica", 12), height=2).pack(pady=15, fill="x")

        tk.Button(self.root, text="Or Select Individual Files",
                  command=self.select_files, font=("Helvetica", 12)).pack(pady=5, fill="x")

        self.status = tk.Label(self.root, text="No files selected yet",
                               font=("Helvetica", 11), fg="gray")
        self.status.pack(pady=20)

        tk.Label(self.root, text="Output filename (without extension):").pack(anchor="w")
        self.name_var = tk.StringVar(value="Combined_Spectra")
        tk.Entry(self.root, textvariable=self.name_var, width=60).pack(pady=5)

        tk.Button(self.root, text="2. Combine & Save as Excel (.xlsx)",
                  command=lambda: self.combine("xlsx"), bg="#2196F3", fg="white",
                  font=("Helvetica", 12, "bold"), height=2).pack(pady=10, fill="x")
        tk.Button(self.root, text="Or Save as CSV",
                  command=lambda: self.combine("csv"), font=("Helvetica", 11)).pack()

        self.files = []

    def update_status(self):
        count = len(self.files)
        self.status.config(text=f"✅ {count} .spc files ready", fg="green")

    def select_folder(self):
        folder = filedialog.askdirectory(title="Select folder containing your .spc files")
        if folder:
            self.files = list(Path(folder).rglob("*.spc"))
            self.update_status()

    def select_files(self):
        files = filedialog.askopenfilenames(
            title="Select .spc files",
            filetypes=[("SPC files", "*.spc")]
        )
        if files:
            self.files = [Path(f) for f in files]
            self.update_status()

    def combine(self, fmt):
        if not self.files:
            messagebox.showerror("Error", "Please select files or a folder first!")
            return

        try:
            data = {}
            x_ref = None

            for i, file in enumerate(self.files, 1):
                print(f"Reading {i}/{len(self.files)}: {file.name}")
                parser = SpcParser(str(file))
                parser.extract_data()
                x, y = parser.get_data()

                if x_ref is None:
                    x_ref = x
                elif len(x) != len(x_ref):
                    messagebox.showwarning("Warning",
                                           f"{file.name} has different wavelength points — using first file's axis.")

                data[file.stem] = y

            # Build final DataFrame
            df = pd.DataFrame({"Wavelength_nm": x_ref})
            for name, yvals in data.items():
                df[name] = yvals

            # Ask where to save
            ext = ".xlsx" if fmt == "xlsx" else ".csv"
            initial = self.name_var.get() + ext
            save_path = filedialog.asksaveasfilename(
                initialfile=initial,
                defaultextension=ext,
                filetypes=[("Excel", "*.xlsx"), ("CSV", "*.csv")] if fmt == "xlsx" else [("CSV", "*.csv")]
            )

            if save_path:
                if fmt == "xlsx":
                    df.to_excel(save_path, index=False)
                else:
                    df.to_csv(save_path, index=False)

                messagebox.showinfo("Success!",
                                    f"✅ Combined {len(self.files)} spectra into:\n{save_path}\n\nOpen it in Excel!")
                self.root.quit()

        except Exception as e:
            messagebox.showerror("Error",
                                 f"Failed to read a file:\n{str(e)}\n\nMake sure spcparser.py is in the same folder as this script.")


if __name__ == "__main__":
    app = ShimadzuSPCCombiner()
    app.root.mainloop()