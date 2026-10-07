#!/usr/bin/env python3
"""swissALTI3D-Kacheln -> Höhendatei (.bin) für das Studio-Plugin „Terrain-Import“.

Anders als die Heightmap-PNG geht hier nichts durch den Roblox-Bildimport: Die Höhen
werden als 32-Bit-Kommazahlen (Meter, volle Genauigkeit) gespeichert, und das Plugin
schreibt das Terrain selbst (WriteVoxels mit Bruchteil-Füllung an der Oberfläche).
Dadurch gibt es keine Treppenstufen.

Benutzt Laden, Zusammenfügen und Glätten aus swissalti_to_heightmap.py – beide Dateien
müssen im selben Ordner liegen.

Beispiele:
    python swissalti_to_terrain.py kacheln
    python swissalti_to_terrain.py kacheln -o huegel.bin --blur 1
    python swissalti_to_terrain.py kacheln --bbox 2600000 1199000 2601500 1200000
    python swissalti_to_terrain.py kacheln --target-width 2000

Dateiformat (little-endian), für das Plugin:
    0   4 Bytes  "GTST"
    4   u16      Version (1)
    6   u16      reserviert (0)
    8   u32      Spalten (West -> Ost)
    12  u32      Zeilen (Nord -> Süd)
    16  f32      Zellgrösse Ost-West (m)
    20  f32      Zellgrösse Nord-Süd (m)
    24  f32      tiefste Höhe (m ü. M.)
    28  f32      höchste Höhe (m ü. M.)
    32  f64      LV95 Ost der Nordwest-Ecke (nur zur Info)
    40  f64      LV95 Nord der Nordwest-Ecke (nur zur Info)
    48  f32 x Spalten x Zeilen: Höhen (m ü. M.), Zeile für Zeile, Zeile 0 = Norden

Benötigt: pip install rasterio numpy pillow
"""

from __future__ import annotations

import argparse
import struct
import sys
from pathlib import Path

# Das Heightmap-Skript liegt im selben Ordner (auch wenn Python mit -I gestartet wurde)
sys.path.insert(0, str(Path(__file__).resolve().parent))

try:
    from swissalti_to_heightmap import (
        STUDS_PER_METER,
        VOXEL_STUDS,
        fill_gaps,
        find_tiles,
        gaussian_blur,
        load_mosaic,
        np,
        resample_to_voxels,
    )
except ImportError as err:
    if err.name == "swissalti_to_heightmap":
        sys.exit(
            "swissalti_to_heightmap.py nicht gefunden. Beide Skripte (swissalti_to_heightmap.py "
            "und swissalti_to_terrain.py) müssen im selben Ordner liegen."
        )
    raise

MAGIC = b"GTST"
VERSION = 1
HEADER = struct.Struct("<4sHHIIffffdd")  # 48 Bytes, siehe Dateiformat oben
WARN_CELLS = 4_000_000  # ab hier wird die Datei gross (16 MB) und das Plugin langsam


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="swissALTI3D-GeoTIFF-Kacheln in eine Höhendatei für das Plugin „Terrain-Import“ umrechnen."
    )
    p.add_argument("ordner", type=Path, help="Ordner mit den swissALTI3D-Kacheln (.tif)")
    p.add_argument(
        "-o", "--output", type=Path, default=Path("terrain.bin"),
        help="Ausgabedatei (Standard: terrain.bin)",
    )
    p.add_argument(
        "--bbox", type=float, nargs=4, metavar=("O_MIN", "N_MIN", "O_MAX", "N_MAX"),
        help="Ausschnitt in LV95-Koordinaten (Ost/Nord in Metern, z. B. von map.geo.admin.ch): "
             "Ost min, Nord min, Ost max, Nord max",
    )
    p.add_argument(
        "--blur", type=float, default=0.0, metavar="SIGMA",
        help="Glätten (Gauss) in 2-m-Pixeln: 0 = aus, 0.5-1 = leicht, 2 = deutlich. Standard: 0",
    )
    p.add_argument(
        "--target-width", type=float, default=0.0, metavar="STUDS",
        help="Optional: auf genau 1 Wert pro Voxel (4 Studs) bei dieser Breite in Studs "
             "herunterrechnen. Kleinere Datei, schnellerer Import. Im Plugin dann dieselbe "
             "Breite eintragen. Standard: 0 = volle Auflösung behalten",
    )
    return p.parse_args()


def main() -> None:
    args = parse_args()
    tiles = find_tiles(args.ordner)
    print(f"{len(tiles)} Kachel(n) gefunden, füge zusammen ...")

    heights, px_x, px_y, origin = load_mosaic(tiles, args.bbox, with_origin=True)
    rows, cols = heights.shape
    width_m, depth_m = cols * px_x, rows * px_y
    print(f"Raster: {cols} x {rows} Werte, {px_x:g} m pro Wert")

    heights = fill_gaps(heights)
    if args.blur > 0:
        print(f"Glätten: Sigma {args.blur:g} Pixel")
        heights = gaussian_blur(heights, args.blur)

    if args.target_width > 0:
        studs_per_m = args.target_width / width_m
        cols = max(2, round(width_m * studs_per_m / VOXEL_STUDS))
        rows = max(2, round(depth_m * studs_per_m / VOXEL_STUDS))
        heights = resample_to_voxels(heights, cols, rows)
        px_x, px_y = width_m / cols, depth_m / rows
        print(f"Heruntergerechnet auf {cols} x {rows} Werte (1 Wert = 1 Voxel bei "
              f"{args.target_width:g} Studs Breite)")

    if rows * cols > WARN_CELLS:
        print(f"Hinweis: {rows * cols:,} Werte – der Import im Plugin dauert dann länger. "
              "Kleinerer Ausschnitt (--bbox) oder --target-width hilft.")

    heights = np.ascontiguousarray(heights, dtype="<f4")
    h_min = float(heights.min())
    h_max = float(heights.max())

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with open(args.output, "wb") as f:
        f.write(HEADER.pack(MAGIC, VERSION, 0, cols, rows, px_x, px_y, h_min, h_max,
                            origin[0], origin[1]))
        f.write(heights.tobytes())
    size_mb = args.output.stat().st_size / 1_000_000
    print(f"Gespeichert: {args.output.resolve()} ({size_mb:.1f} MB)")

    height_m = h_max - h_min
    print()
    print("Gelände")
    print(f"  Grösse:         {width_m:.0f} m (Ost-West) x {depth_m:.0f} m (Nord-Süd)")
    print(f"  Tiefster Punkt: {h_min:.1f} m ü. M.")
    print(f"  Höchster Punkt: {h_max:.1f} m ü. M.  (Unterschied {height_m:.1f} m)")
    print()
    print("Im Plugin „Terrain-Import“:")
    print(f"  Echte Proportionen: Zielbreite {width_m * STUDS_PER_METER:.0f} Studs "
          f"(Höhe dann {height_m * STUDS_PER_METER:.0f} Studs)")
    for width in (2000, 1000):
        f = width / (width_m * STUDS_PER_METER)
        print(f"  Zielbreite {width} Studs: Höhe {height_m * STUDS_PER_METER * f:.0f} Studs "
              f"bei Steigungsfaktor 1")
    print("  Norden = -Z, Osten = +X. Quellenangabe im Spiel: „Höhendaten: © swisstopo“")


if __name__ == "__main__":
    main()
