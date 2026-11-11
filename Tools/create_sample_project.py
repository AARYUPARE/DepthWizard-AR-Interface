#!/usr/bin/env python3
"""Create a tiny USDZ sample archive to exercise project packaging and transfer."""
from __future__ import annotations
import json
import struct
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "Samples" / "SampleRelativeTerrain"
OUT.mkdir(parents=True, exist_ok=True)

# A minimal static mesh in USDA. Blender is used for real DepthWizard GLB conversion;
# this self-contained sample exists to exercise the USDZ package and sync contract.
usda = '''#usda 1.0
(
    defaultPrim = "TerrainRoot"
    metersPerUnit = 1
    upAxis = "Y"
)
def Xform "TerrainRoot" {
    def Mesh "Terrain" {
        uniform token subdivisionScheme = "none"
        point3f[] points = [(-0.5, 0.0, -0.5), (0.5, 0.0, -0.5), (0.5, 0.2, 0.5), (-0.5, 0.1, 0.5)]
        int[] faceVertexCounts = [4]
        int[] faceVertexIndices = [0, 1, 2, 3]
        normal3f[] normals = [(0, 1, 0)]
        uniform token normals:interpolation = "constant"
        color3f[] primvars:displayColor = [(0.20, 0.42, 0.27)]
        uniform token primvars:displayColor:interpolation = "constant"
    }
}
'''.encode("utf-8")
name = "terrain.usda"
base_offset = 30 + len(name.encode("utf-8"))
padding = (-base_offset) % 64
if 0 < padding < 4:
    padding += 64
extra = struct.pack("<HH", 0x1986, padding - 4) + b"\0" * (padding - 4) if padding else b""
info = zipfile.ZipInfo(name)
info.compress_type = zipfile.ZIP_STORED
info.extra = extra
archive_path = OUT / "model.usdz"
with zipfile.ZipFile(archive_path, "w") as archive:
    archive.writestr(info, usda)
project = {
    "id": OUT.name,
    "name": "Sample Relative Terrain",
    "description": "A small USDZ terrain asset to test the iPad RealityKit project handoff.",
    "createdAt": "2026-11-11T00:00:00Z",
    "modelFile": "model.usdz",
    "modelFormat": "usdz",
    "sourceModelFile": None,
    "sourceImage": None,
    "elevationMode": "Relative DSM",
    "units": "relative",
}
(OUT / "project.json").write_text(json.dumps(project, indent=2) + "\n", encoding="utf-8")
print(f"Created {archive_path} ({archive_path.stat().st_size:,} bytes)")
