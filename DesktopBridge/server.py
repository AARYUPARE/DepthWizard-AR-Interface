#!/usr/bin/env python3
"""Read-only, pairing-code-protected local project bridge for DepthWizard AR.

This server intentionally exposes only validated project manifests and USDZ files.
It does not connect to or expose the DepthWizard inference sidecar.
"""
from __future__ import annotations

import argparse
import hashlib
import hmac
import ipaddress
import json
import math
import re
import secrets
import struct
import socket
import sys
import zipfile
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path, PurePosixPath
from typing import Any
from urllib.parse import unquote, urlsplit

MAX_MODEL_BYTES = 500 * 1024 * 1024
MAX_MANIFEST_BYTES = 1024 * 1024
PROJECT_ID_RE = re.compile(r"^[A-Za-z0-9_-]{1,80}$")
PRIVATE_NETWORKS = tuple(map(ipaddress.ip_network, (
    "10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16",
    "fc00::/7", "127.0.0.0/8", "::1/128",
)))

class ProjectError(Exception):
    pass


def is_trusted_lan_address(value: str) -> bool:
    try:
        address = ipaddress.ip_address(value.split("%", 1)[0])
        return any(address in network for network in PRIVATE_NETWORKS)
    except ValueError:
        return False


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def validate_usdz(path: Path) -> int:
    if path.is_symlink() or not path.is_file():
        raise ProjectError("Model asset is not a regular file")
    size = path.stat().st_size
    if size < 64 or size > MAX_MODEL_BYTES:
        raise ProjectError("USDZ size must be between 64 bytes and 500 MB")
    if not zipfile.is_zipfile(path):
        raise ProjectError("Expected a valid USDZ ZIP package")
    try:
        with zipfile.ZipFile(path, "r") as archive:
            entries = archive.infolist()
            if not entries or len(entries) > 10000:
                raise ProjectError("USDZ package is empty or has too many entries")
            first = entries[0]
            if Path(first.filename).suffix.lower() not in {".usd", ".usda", ".usdc"} or first.file_size == 0:
                raise ProjectError("First USDZ package entry must be a non-empty USD scene file")
            root_signature = archive.read(first)[:8]
            if not (root_signature.startswith(b"#usda") or root_signature.startswith(b"PXR-USDC")):
                raise ProjectError("USDZ root scene has an unknown USD file signature")
            expanded_total = 0
            with path.open("rb") as raw:
                for entry in entries:
                    member = PurePosixPath(entry.filename.replace("\\", "/"))
                    if member.is_absolute() or ".." in member.parts or entry.is_dir():
                        raise ProjectError("USDZ contains an unsafe or directory entry")
                    if entry.flag_bits & 0x1:
                        raise ProjectError("Encrypted USDZ entries are unsupported")
                    if entry.compress_type != zipfile.ZIP_STORED:
                        raise ProjectError("USDZ entries must be stored without ZIP compression")
                    raw.seek(entry.header_offset)
                    local_header = raw.read(30)
                    if len(local_header) != 30:
                        raise ProjectError("USDZ contains a truncated local ZIP header")
                    fields = struct.unpack("<IHHHHHIIIHH", local_header)
                    signature, name_length, extra_length = fields[0], fields[-2], fields[-1]
                    if signature != 0x04034B50:
                        raise ProjectError("USDZ contains an invalid local ZIP header")
                    data_offset = entry.header_offset + 30 + name_length + extra_length
                    if data_offset % 64 != 0:
                        raise ProjectError("USDZ package entry is not 64-byte aligned")
                    expanded_total += entry.file_size
                    if expanded_total > MAX_MODEL_BYTES:
                        raise ProjectError("USDZ expands beyond the 500 MB safety limit")
            corrupt = archive.testzip()
            if corrupt:
                raise ProjectError(f"USDZ contains a corrupt entry: {corrupt}")
    except (OSError, zipfile.BadZipFile, RuntimeError) as exc:
        raise ProjectError(f"Could not validate USDZ package: {exc}") from exc
    return size


def clean_measurements(value: Any) -> list[dict[str, Any]] | None:
    """Validate and expose the bounded, local-coordinate measurement payload."""
    if value is None:
        return None
    if not isinstance(value, list) or not 1 <= len(value) <= 500:
        raise ProjectError("Measurements must contain between 1 and 500 entries")
    clean: list[dict[str, Any]] = []
    seen: set[str] = set()
    for point in value:
        if not isinstance(point, dict):
            raise ProjectError("Measurement entries must be JSON objects")
        identifier = point.get("id")
        if not isinstance(identifier, str) or not PROJECT_ID_RE.fullmatch(identifier) or identifier in seen:
            raise ProjectError("Measurement IDs must be unique safe identifiers")
        if point.get("type") not in {"dsm", "rdsm"}:
            raise ProjectError("Measurement type must be dsm or rdsm")
        expected_units = "m" if point["type"] == "dsm" else "relative"
        if point.get("units") != expected_units:
            raise ProjectError("Measurement units do not match the surface type")
        value_number = point.get("value")
        if isinstance(value_number, bool) or not isinstance(value_number, (int, float)) or not math.isfinite(value_number):
            raise ProjectError("Measurement values must be finite numbers")
        label, source = point.get("label"), point.get("source")
        if not all(isinstance(item, str) and item.strip() and len(item) <= 120 for item in (label, source)):
            raise ProjectError("Measurement labels and sources must be non-empty strings up to 120 characters")
        if type(point.get("featured")) is not bool:
            raise ProjectError("Measurement featured flags must be booleans")
        pixel_x, pixel_y = point.get("pixelX"), point.get("pixelY")
        if (isinstance(pixel_x, bool) or not isinstance(pixel_x, int) or pixel_x < 0 or
                isinstance(pixel_y, bool) or not isinstance(pixel_y, int) or pixel_y < 0):
            raise ProjectError("Measurement pixel coordinates must be non-negative integers")
        position = point.get("normalizedPosition")
        if not isinstance(position, dict):
            raise ProjectError("Measurement normalizedPosition must be an object")
        coordinates = {axis: position.get(axis) for axis in ("x", "y", "z")}
        if any(isinstance(coordinate, bool) or not isinstance(coordinate, (int, float)) or
               not math.isfinite(coordinate) or not 0.0 <= coordinate <= 1.0
               for coordinate in coordinates.values()):
            raise ProjectError("Measurement normalized positions must be finite fractions in [0, 1]")
        clean.append({
            "id": identifier,
            "label": label,
            "value": float(value_number),
            "units": expected_units,
            "source": source,
            "type": point["type"],
            "pixelX": pixel_x,
            "pixelY": pixel_y,
            "normalizedPosition": {axis: float(coordinate) for axis, coordinate in coordinates.items()},
            "featured": point["featured"],
        })
        seen.add(identifier)
    return clean


def validate_project_folder(folder: Path) -> dict[str, Any]:
    if folder.is_symlink() or not folder.is_dir():
        raise ProjectError("Project folder must be a real directory")
    manifest_path = folder / "project.json"
    if manifest_path.is_symlink() or not manifest_path.is_file():
        raise ProjectError("Missing project.json")
    if manifest_path.stat().st_size > MAX_MANIFEST_BYTES:
        raise ProjectError("Project manifest is too large")
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ProjectError(f"Invalid project.json: {exc}") from exc
    if not isinstance(manifest, dict):
        raise ProjectError("Project manifest must be a JSON object")

    required = ("id", "name", "modelFile", "modelFormat")
    if any(not isinstance(manifest.get(key), str) or not manifest[key].strip() for key in required):
        raise ProjectError("Manifest requires non-empty id, name, modelFile and modelFormat fields")
    project_id = manifest["id"]
    if not PROJECT_ID_RE.fullmatch(project_id) or folder.name != project_id:
        raise ProjectError("Project id must be a simple ID matching its folder name")
    filename = manifest["modelFile"]
    if filename != Path(filename).name or filename in (".", "..") or "/" in filename or "\\" in filename:
        raise ProjectError("modelFile must be a filename inside the project folder")
    if Path(filename).suffix.lower() != ".usdz" or manifest["modelFormat"].lower().lstrip(".") != "usdz":
        raise ProjectError("The iPad companion project must reference a USDZ model")

    asset_path = folder / filename
    try:
        if asset_path.resolve().parent != folder.resolve():
            raise ProjectError("Model path escapes the project folder")
    except OSError as exc:
        raise ProjectError("Could not resolve model path") from exc
    size = validate_usdz(asset_path)
    measurements = clean_measurements(manifest.get("measurements"))
    if measurements is not None:
        if manifest.get("measurementSchemaVersion") != 1:
            raise ProjectError("Unsupported measurement schema version")
        if manifest.get("measurementCoordinateSpace") != "terrain_glb_local_bounds_v1":
            raise ProjectError("Unsupported measurement coordinate-space contract")
        if manifest.get("measurementPixelOrigin") != "top_left_zero_based":
            raise ProjectError("Unsupported measurement pixel origin")
        expected_axes = {
            "x": "raster_columns_positive",
            "y": "mesh_elevation_up",
            "z": "negative_raster_rows",
        }
        if manifest.get("measurementAxes") != expected_axes:
            raise ProjectError("Measurement axis contract is missing or invalid")
        width, height = manifest.get("measurementRasterWidth"), manifest.get("measurementRasterHeight")
        stride = manifest.get("measurementMeshStride")
        if (isinstance(width, bool) or not isinstance(width, int) or width < 2 or
                isinstance(height, bool) or not isinstance(height, int) or height < 2 or
                isinstance(stride, bool) or not isinstance(stride, int) or stride < 1):
            raise ProjectError("Measurement raster dimensions or mesh stride are invalid")
        for key in (
            "measurementSourceSurfaceSha256",
            "measurementMeshSha256",
            "measurementBuildConfigSha256",
        ):
            digest = manifest.get(key)
            if not isinstance(digest, str) or re.fullmatch(r"[0-9a-f]{64}", digest) is None:
                raise ProjectError(f"{key} must be a lowercase SHA-256 digest")
        if manifest.get("measurementMeshSha256") != manifest.get("sourceMeshSha256"):
            raise ProjectError("Measurement metadata does not identify the exported source mesh")
        product = manifest.get("surfaceProduct")
        units = manifest.get("verticalUnits", manifest.get("units"))
        expected_units = "m" if product == "dsm" else "relative" if product == "rdsm" else None
        if expected_units is None or units != expected_units:
            raise ProjectError("Project surface product and vertical units are inconsistent")
        if any(point["type"] != product or point["units"] != expected_units or
               point["pixelX"] >= width or point["pixelY"] >= height
               for point in measurements):
            raise ProjectError("Measurement point does not match the project's source raster")
    clean = {
        "id": project_id,
        "name": manifest["name"][:160],
        "description": str(manifest.get("description") or "")[:1000] or None,
        "createdAt": manifest.get("createdAt") if isinstance(manifest.get("createdAt"), str) else None,
        "modelFile": filename,
        "modelFormat": "usdz",
        "sourceImage": str(manifest.get("sourceImage") or "")[:255] or None,
        "elevationMode": str(manifest.get("elevationMode") or "")[:80] or None,
        "units": str(manifest.get("units") or "")[:80] or None,
        "measurements": measurements,
        "modelSizeBytes": size,
        "sha256": sha256_file(asset_path),
    }
    return clean


def discover_lan_addresses() -> list[str]:
    found: set[str] = set()
    try:
        for entry in socket.getaddrinfo(socket.gethostname(), None, family=socket.AF_INET):
            address = entry[4][0]
            if is_trusted_lan_address(address) and not address.startswith("127."):
                found.add(address)
    except OSError:
        pass
    # Determine the default-route source IP without sending application data.
    probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        probe.connect(("192.0.2.1", 9))
        address = probe.getsockname()[0]
        if is_trusted_lan_address(address) and not address.startswith("127."):
            found.add(address)
    except OSError:
        pass
    finally:
        probe.close()
    return sorted(found)


class BridgeState:
    def __init__(self, root: Path, pairing_code: str):
        self.root = root.resolve()
        self.pairing_code = pairing_code
        self.failures: dict[str, list[float]] = {}

    def authorized(self, client_ip: str, supplied: str) -> bool:
        now = time.monotonic()
        recent = [stamp for stamp in self.failures.get(client_ip, []) if now - stamp < 60]
        self.failures[client_ip] = recent
        if len(recent) >= 8:
            return False
        valid = hmac.compare_digest(supplied.encode("utf-8"), self.pairing_code.encode("utf-8"))
        if not valid:
            recent.append(now)
            self.failures[client_ip] = recent
        else:
            self.failures.pop(client_ip, None)
        return valid

    def find_project(self, project_id: str) -> tuple[Path, dict[str, Any]]:
        if not PROJECT_ID_RE.fullmatch(project_id):
            raise ProjectError("Invalid project id")
        folder = self.root / project_id
        if folder.resolve().parent != self.root:
            raise ProjectError("Invalid project directory")
        return folder, validate_project_folder(folder)

    def list_projects(self) -> list[dict[str, Any]]:
        projects: list[dict[str, Any]] = []
        for folder in self.root.iterdir():
            if not folder.is_dir() or folder.is_symlink():
                continue
            try:
                projects.append(validate_project_folder(folder))
            except (ProjectError, OSError) as exc:
                print(f"[skip] {folder.name}: {exc}", file=sys.stderr)
        projects.sort(key=lambda item: item.get("createdAt") or "", reverse=True)
        return projects


class BridgeHandler(BaseHTTPRequestHandler):
    server_version = "DepthWizardARBridge/1.0"
    sys_version = ""

    @property
    def state(self) -> BridgeState:
        return self.server.state  # type: ignore[attr-defined]

    def log_message(self, fmt: str, *args: Any) -> None:
        # Do not log request headers or pairing credentials.
        print(f"[{self.client_address[0]}] {fmt % args}")

    def _send_json(self, status: int, payload: dict[str, Any]) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        self.wfile.write(body)

    def _authorized(self) -> bool:
        client_ip = self.client_address[0]
        if not is_trusted_lan_address(client_ip):
            self._send_json(403, {"error": "Private LAN clients only"})
            return False
        header = self.headers.get("Authorization", "")
        supplied = header[7:].strip() if header.lower().startswith("bearer ") else ""
        if not self.state.authorized(client_ip, supplied):
            self._send_json(401, {"error": "Unauthorized"})
            return False
        return True

    def do_GET(self) -> None:  # noqa: N802
        parsed = urlsplit(self.path)
        if parsed.path == "/api/v1/health":
            if not is_trusted_lan_address(self.client_address[0]):
                self._send_json(403, {"error": "Private LAN clients only"})
                return
            self._send_json(200, {"service": "DepthWizard AR Bridge", "version": 1, "readOnly": True})
            return
        if not self._authorized():
            return
        if parsed.path == "/api/v1/projects":
            self._send_json(200, {"projects": self.state.list_projects()})
            return
        parts = [unquote(part) for part in parsed.path.strip("/").split("/")]
        if len(parts) == 5 and parts[:3] == ["api", "v1", "projects"] and parts[4] == "model":
            project_id = parts[3]
            try:
                folder, manifest = self.state.find_project(project_id)
                asset_path = folder / manifest["modelFile"]
                size = validate_usdz(asset_path)
                self.send_response(200)
                self.send_header("Content-Type", "model/vnd.usdz+zip")
                self.send_header("Content-Length", str(size))
                self.send_header("Content-Disposition", f'attachment; filename="{project_id}.usdz"')
                self.send_header("Cache-Control", "no-store")
                self.send_header("X-Content-Type-Options", "nosniff")
                self.end_headers()
                with asset_path.open("rb") as stream:
                    while chunk := stream.read(1024 * 1024):
                        self.wfile.write(chunk)
            except (ProjectError, OSError) as exc:
                self._send_json(404, {"error": str(exc)})
            return
        self._send_json(404, {"error": "Not found"})


def main() -> int:
    parser = argparse.ArgumentParser(description="Serve validated DepthWizard USDZ companion projects on a private LAN")
    parser.add_argument("--root", required=True, type=Path, help="Folder containing one project subfolder per export")
    parser.add_argument("--port", type=int, default=8765)
    args = parser.parse_args()
    root = args.root.expanduser().resolve()
    if not root.is_dir():
        parser.error(f"Projects root is not a directory: {root}")
    pairing_code = secrets.token_hex(5).upper()
    state = BridgeState(root, pairing_code)
    server = ThreadingHTTPServer(("0.0.0.0", args.port), BridgeHandler)
    server.daemon_threads = True
    server.state = state  # type: ignore[attr-defined]
    print("\nDepthWizard AR laptop bridge is running")
    print(f"Projects folder : {root}")
    print(f"Port            : {args.port}")
    print(f"Pairing code    : {pairing_code}")
    addresses = discover_lan_addresses()
    if addresses:
        for address in addresses:
            print(f"Laptop IP       : {address}")
    else:
        print("Laptop IP       : Find the IPv4 address for the active Wi-Fi adapter using ipconfig")
    print("\nKeep this terminal open. Use only on a trusted private Wi-Fi network.")
    print("Press Ctrl+C to stop the bridge.\n")
    try:
        server.serve_forever(poll_interval=0.4)
    except KeyboardInterrupt:
        print("\nStopping DepthWizard AR bridge…")
    finally:
        server.server_close()
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
