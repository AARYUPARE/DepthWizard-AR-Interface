from __future__ import annotations
import json
import struct
import sys
import tempfile
import threading
import unittest
import zipfile
from http.server import ThreadingHTTPServer
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "DesktopBridge"))
import server


def write_usdz(path: Path, name: str = "scene.usda", content: bytes | None = None, compression: int = zipfile.ZIP_STORED) -> None:
    if content is None:
        content = b'''#usda 1.0\n(\n defaultPrim = "Root"\n metersPerUnit = 1\n upAxis = "Y"\n)\ndef Xform "Root" {}\n'''

    base = 30 + len(name.encode("utf-8"))
    padding = (-base) % 64
    if 0 < padding < 4:
        padding += 64
    extra = struct.pack("<HH", 0x1986, padding - 4) + bytes(padding - 4) if padding else b""
    info = zipfile.ZipInfo(name)
    info.compress_type = compression
    info.extra = extra
    with zipfile.ZipFile(path, "w") as archive:
        archive.writestr(info, content)


def create_project(root: Path, project_id: str = "test-project") -> Path:
    folder = root / project_id
    folder.mkdir()
    write_usdz(folder / "model.usdz")
    (folder / "project.json").write_text(json.dumps({
        "id": project_id, "name": "Test terrain", "modelFile": "model.usdz", "modelFormat": "usdz"
    }), encoding="utf-8")
    return folder


def add_measurements(folder: Path, *, invalid_pixel: bool = False) -> None:
    manifest_path = folder / "project.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    manifest.update({
        "surfaceProduct": "dsm",
        "verticalUnits": "m",
        "measurementSchemaVersion": 1,
        "measurementCoordinateSpace": "terrain_glb_local_bounds_v1",
        "measurementPixelOrigin": "top_left_zero_based",
        "measurementAxes": {
            "x": "raster_columns_positive",
            "y": "mesh_elevation_up",
            "z": "negative_raster_rows",
        },
        "measurementRasterWidth": 640,
        "measurementRasterHeight": 480,
        "measurementMeshStride": 1,
        "sourceMeshSha256": "a" * 64,
        "measurementMeshSha256": "a" * 64,
        "measurementSourceSurfaceSha256": "b" * 64,
        "measurementBuildConfigSha256": "c" * 64,
        "measurements": [{
            "id": "p00_00",
            "label": "Point 01",
            "value": 512.375,
            "units": "m",
            "source": "Persisted DSM raster",
            "type": "dsm",
            "pixelX": 640 if invalid_pixel else 12,
            "pixelY": 24,
            "normalizedPosition": {"x": 0.25, "y": 0.5, "z": 0.75},
            "featured": True,
        }],
    })
    manifest_path.write_text(json.dumps(manifest), encoding="utf-8")


class BridgeTests(unittest.TestCase):
    def test_valid_project_and_hash(self):
        with tempfile.TemporaryDirectory() as temp:
            folder = create_project(Path(temp))
            item = server.validate_project_folder(folder)
            self.assertEqual(item["id"], "test-project")
            self.assertEqual(len(item["sha256"]), 64)
            self.assertGreater(item["modelSizeBytes"], 64)

    def test_valid_measurement_contract_is_returned(self):
        with tempfile.TemporaryDirectory() as temp:
            folder = create_project(Path(temp))
            add_measurements(folder)
            item = server.validate_project_folder(folder)
            self.assertEqual(len(item["measurements"]), 1)
            point = item["measurements"][0]
            self.assertEqual(point["label"], "Point 01")
            self.assertEqual(point["pixelX"], 12)
            self.assertEqual(point["units"], "m")
            self.assertEqual(point["normalizedPosition"], {"x": 0.25, "y": 0.5, "z": 0.75})

    def test_measurement_pixel_outside_raster_is_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            folder = create_project(Path(temp))
            add_measurements(folder, invalid_pixel=True)
            with self.assertRaises(server.ProjectError):
                server.validate_project_folder(folder)

    def test_relative_dsm_cannot_claim_metre_units(self):
        with tempfile.TemporaryDirectory() as temp:
            folder = create_project(Path(temp))
            add_measurements(folder)
            manifest_path = folder / "project.json"
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            manifest["surfaceProduct"] = "rdsm"
            manifest["verticalUnits"] = "relative"
            (folder / "project.json").write_text(json.dumps(manifest), encoding="utf-8")
            with self.assertRaises(server.ProjectError):
                server.validate_project_folder(folder)

    def test_traversal_and_invalid_project_id_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            state = server.BridgeState(Path(temp), "TEST")
            with self.assertRaises(server.ProjectError):
                state.find_project("../outside")

    def test_path_escape_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            folder = create_project(root)
            manifest = json.loads((folder / "project.json").read_text())
            manifest["modelFile"] = "../secret.usdz"
            (folder / "project.json").write_text(json.dumps(manifest))
            with self.assertRaises(server.ProjectError):
                server.validate_project_folder(folder)

    def test_malformed_model_archive_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            folder = create_project(Path(temp))
            (folder / "model.usdz").write_bytes(b"glTF" + b"0" * 100)
            with self.assertRaises(server.ProjectError):
                server.validate_project_folder(folder)

    def test_usdz_internal_path_traversal_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            folder = root / "traversal-project"
            folder.mkdir()
            write_usdz(folder / "model.usdz", name="../escape.usda")
            (folder / "project.json").write_text(json.dumps({
                "id": "traversal-project", "name": "Unsafe", "modelFile": "model.usdz", "modelFormat": "usdz"
            }), encoding="utf-8")
            with self.assertRaises(server.ProjectError):
                server.validate_project_folder(folder)

    def test_compressed_usdz_entry_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            folder = create_project(Path(temp))
            write_usdz(folder / "model.usdz", compression=zipfile.ZIP_DEFLATED)
            with self.assertRaises(server.ProjectError):
                server.validate_project_folder(folder)

    def test_private_address_filter(self):
        self.assertTrue(server.is_trusted_lan_address("192.168.1.20"))
        self.assertTrue(server.is_trusted_lan_address("127.0.0.1"))
        self.assertFalse(server.is_trusted_lan_address("8.8.8.8"))

    def test_http_pairing_listing_and_model_download(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            create_project(root)
            state = server.BridgeState(root, "PAIRING-CODE")
            httpd = ThreadingHTTPServer(("127.0.0.1", 0), server.BridgeHandler)
            httpd.state = state
            thread = threading.Thread(target=httpd.serve_forever, daemon=True)
            thread.start()
            base = f"http://127.0.0.1:{httpd.server_port}"
            try:
                request = Request(base + "/api/v1/projects", headers={"Authorization": "Bearer PAIRING-CODE"})
                with urlopen(request) as response:
                    data = json.loads(response.read())
                    self.assertEqual(data["projects"][0]["id"], "test-project")
                    self.assertEqual(data["projects"][0]["modelFormat"], "usdz")
                request = Request(base + "/api/v1/projects/test-project/model", headers={"Authorization": "Bearer PAIRING-CODE"})
                with urlopen(request) as response:
                    self.assertTrue(response.read().startswith(b"PK\x03\x04"))
                request = Request(base + "/api/v1/projects", headers={"Authorization": "Bearer WRONG"})
                with self.assertRaises(HTTPError) as context:
                    urlopen(request)
                self.assertEqual(context.exception.code, 401)
            finally:
                httpd.shutdown()
                httpd.server_close()
                thread.join(timeout=2)

if __name__ == "__main__":
    unittest.main(verbosity=2)
