#!/usr/bin/env python3
"""swissALTI3D-Kacheln -> 16-Bit-Heightmap (PNG) für den Roblox-Terrain-Import.

Liest alle GeoTIFF-Kacheln (*.tif / *.tiff) aus einem Ordner, fügt sie zusammen,
schneidet optional einen Ausschnitt aus (LV95-Koordinaten), glättet optional und
speichert eine 16-Bit-Graustufen-PNG (tiefster Punkt = schwarz, höchster = weiss).
Im Terminal steht danach, welche Grösse (X, Y, Z in Studs) im Roblox-Importdialog
eingestellt werden muss, damit die Proportionen echt bleiben.

Beispiele:
    python swissalti_to_heightmap.py kacheln
    python swissalti_to_heightmap.py kacheln -o huegel.png --blur 1.5
    python swissalti_to_heightmap.py kacheln --bbox 2600000 1199000 2601500 1200000
    python swissalti_to_heightmap.py kacheln --target-width 2000 --max-pixels 1024

Benötigt: pip install rasterio numpy pillow
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

try:
    import numpy as np
    import rasterio
    from rasterio.merge import merge
    from PIL import Image
except ImportError as err:
    # Pakete für genau dieses Python installieren (auf dem Mac gibt es oft mehrere)
    sys.exit(
        f"Fehlendes Paket: {err.name}\n"
        f"Dieses Skript läuft mit: {sys.executable}\n"
        f'Installieren mit:  "{sys.executable}" -m pip install rasterio numpy pillow'
    )

# Roblox: 1 Stud = 0.28 m  ->  1 m = 3.571... Studs
STUDS_PER_METER = 1 / 0.28


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="swissALTI3D-GeoTIFF-Kacheln in eine 16-Bit-Heightmap (PNG) für Roblox umrechnen."
    )
    p.add_argument("ordner", type=Path, help="Ordner mit den swissALTI3D-Kacheln (.tif)")
    p.add_argument(
        "-o", "--output", type=Path, default=Path("heightmap.png"),
        help="Ausgabedatei (Standard: heightmap.png)",
    )
    p.add_argument(
        "--bbox", type=float, nargs=4, metavar=("O_MIN", "N_MIN", "O_MAX", "N_MAX"),
        help="Ausschnitt in LV95-Koordinaten (Ost/Nord in Metern, z. B. von map.geo.admin.ch): "
             "Ost min, Nord min, Ost max, Nord max",
    )
    p.add_argument(
        "--blur", type=float, default=0.0, metavar="SIGMA",
        help="Weichzeichner-Stärke in Pixeln (0 = aus, 1-2 = leicht). Standard: 0",
    )
    p.add_argument(
        "--target-width", type=float, default=2000.0, metavar="STUDS",
        help="Zielbreite in Studs für die verkleinerte Variante (Standard: 2000)",
    )
    p.add_argument(
        "--max-pixels", type=int, default=0, metavar="N",
        help="Bild verkleinern, falls die längere Seite mehr als N Pixel hat (0 = nie). "
             "Die Grösse in Metern/Studs bleibt gleich.",
    )
    return p.parse_args()


def find_tiles(folder: Path) -> list[Path]:
    if not folder.is_dir():
        sys.exit(f"Ordner nicht gefunden: {folder}")
    tiles = sorted(
        f for f in folder.iterdir()
        if f.is_file() and f.suffix.lower() in (".tif", ".tiff")
    )
    if not tiles:
        sys.exit(f"Keine .tif-Dateien in {folder}")
    return tiles


def load_mosaic(tiles: list[Path], bbox: list[float] | None):
    """Fügt die Kacheln zusammen; Rückgabe: Höhen (float32, NaN = keine Daten), Pixelgrösse x/y in m."""
    sources = [rasterio.open(t) for t in tiles]
    try:
        crs = sources[0].crs
        for src in sources[1:]:
            if src.crs != crs:
                sys.exit(f"Kacheln haben unterschiedliche Koordinatensysteme: {src.name}")
        res = sources[0].res
        nodata = sources[0].nodata
        if nodata is None:
            nodata = -9999.0

        if bbox is not None:
            o_min, n_min, o_max, n_max = bbox
            if o_min >= o_max or n_min >= n_max:
                sys.exit("--bbox: erst die kleineren Werte (Ost min, Nord min), dann die grösseren.")
            bounds = (o_min, n_min, o_max, n_max)
        else:
            bounds = None

        mosaic, _transform = merge(
            sources, bounds=bounds, res=res, nodata=nodata, dtype="float32"
        )
    finally:
        for src in sources:
            src.close()

    heights = mosaic[0].astype(np.float32)
    heights[heights == np.float32(nodata)] = np.nan
    heights[heights < -1000] = np.nan  # Sicherheitsnetz für andere Nodata-Werte
    return heights, abs(res[0]), abs(res[1])


def fill_gaps(heights: np.ndarray) -> np.ndarray:
    """Lücken (keine Daten) mit der tiefsten Höhe füllen, damit die PNG keine Löcher hat."""
    missing = np.isnan(heights)
    if missing.all():
        sys.exit("Im gewählten Ausschnitt gibt es keine Höhendaten (stimmt --bbox?).")
    if missing.any():
        share = missing.mean() * 100
        print(f"Hinweis: {share:.2f} % ohne Daten (fehlende Kachel oder Ausschnitt zu gross) "
              "-> mit tiefstem Punkt gefüllt.")
        heights = heights.copy()
        heights[missing] = np.nanmin(heights)
    return heights


def gaussian_blur(heights: np.ndarray, sigma: float) -> np.ndarray:
    """Einfacher Gauss-Weichzeichner (getrennt nach Zeilen/Spalten), Ränder werden fortgesetzt."""
    radius = max(1, int(round(sigma * 3)))
    x = np.arange(-radius, radius + 1, dtype=np.float64)
    kernel = np.exp(-(x * x) / (2 * sigma * sigma))
    kernel /= kernel.sum()

    out = np.pad(heights.astype(np.float64), radius, mode="edge")
    out = np.apply_along_axis(lambda r: np.convolve(r, kernel, mode="valid"), 1, out)
    out = np.apply_along_axis(lambda c: np.convolve(c, kernel, mode="valid"), 0, out)
    return out.astype(np.float32)


def downscale(heights: np.ndarray, max_pixels: int) -> np.ndarray:
    rows, cols = heights.shape
    longest = max(rows, cols)
    if max_pixels <= 0 or longest <= max_pixels:
        return heights
    factor = max_pixels / longest
    new_size = (max(1, round(cols * factor)), max(1, round(rows * factor)))
    img = Image.fromarray(heights.astype(np.float32))
    print(f"Bild verkleinert: {cols} x {rows} -> {new_size[0]} x {new_size[1]} Pixel")
    return np.asarray(img.resize(new_size, Image.Resampling.BOX), dtype=np.float32)


def save_png(heights: np.ndarray, path: Path, h_min: float, h_max: float) -> None:
    span = h_max - h_min
    if span <= 0:
        gray = np.zeros(heights.shape, dtype=np.uint16)
    else:
        norm = (heights - h_min) / span
        gray = np.clip(np.round(norm * 65535), 0, 65535).astype(np.uint16)
    path.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(gray).save(path)  # uint16 -> 16-Bit-Graustufen-PNG


def print_sizes(width_m: float, depth_m: float, h_min: float, h_max: float, target_width: float) -> None:
    height_m = h_max - h_min
    x = width_m * STUDS_PER_METER
    y = height_m * STUDS_PER_METER
    z = depth_m * STUDS_PER_METER

    print()
    print("Gelände")
    print(f"  Grösse:        {width_m:.0f} m (Ost-West) x {depth_m:.0f} m (Nord-Süd)")
    print(f"  Tiefster Punkt: {h_min:.1f} m ü. M.")
    print(f"  Höchster Punkt: {h_max:.1f} m ü. M.  (Unterschied {height_m:.1f} m)")
    print()
    print(f"Roblox-Import, echte Proportionen (1 m = {STUDS_PER_METER:.2f} Studs)")
    print(f"  Size X: {x:.0f}   Y: {y:.0f}   Z: {z:.0f}")

    if target_width > 0 and x > 0:
        f = target_width / x
        print()
        print(f"Roblox-Import, verkleinert auf {target_width:.0f} Studs Breite (Faktor {f:.3f})")
        print(f"  Size X: {x * f:.0f}   Y: {y * f:.0f}   Z: {z * f:.0f}")
        print(f"  (1 Stud entspricht dann {1 / (STUDS_PER_METER * f):.2f} m)")
    print()
    print("Y = Höhe von Schwarz bis Weiss. X = Bildbreite (Ost-West), Z = Bildhöhe (Nord-Süd).")


def main() -> None:
    args = parse_args()
    tiles = find_tiles(args.ordner)
    print(f"{len(tiles)} Kachel(n) gefunden, füge zusammen ...")

    heights, px_x, px_y = load_mosaic(tiles, args.bbox)
    rows, cols = heights.shape
    width_m, depth_m = cols * px_x, rows * px_y
    print(f"Raster: {cols} x {rows} Pixel, {px_x:g} m pro Pixel")

    heights = fill_gaps(heights)
    if args.blur > 0:
        print(f"Weichzeichner: Sigma {args.blur:g} Pixel")
        heights = gaussian_blur(heights, args.blur)
    heights = downscale(heights, args.max_pixels)

    h_min = float(heights.min())
    h_max = float(heights.max())
    save_png(heights, args.output, h_min, h_max)
    print(f"Gespeichert: {args.output.resolve()} ({heights.shape[1]} x {heights.shape[0]} Pixel, 16 Bit)")

    print_sizes(width_m, depth_m, h_min, h_max, args.target_width)


if __name__ == "__main__":
    main()
