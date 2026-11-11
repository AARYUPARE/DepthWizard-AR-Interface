#!/usr/bin/env python3
"""Validate a DepthWizard AR project folder and its USDZ package."""
from __future__ import annotations
import json
import re
import sys
import struct
import zipfile
from pathlib import Path, PurePosixPath

MAX_BYTES = 500 * 1024 * 1024
USD_EXTENSIONS = {".usd", ".usda", ".usdc"}

def inspect_usdz(asset: Path) -> tuple[bool, str]:
    if asset.is_symlink() or not asset.is_file():
        return False, "model asset is missing or is a symlink"
    size = asset.stat().st_size
    if size < 64 or size > MAX_BYTES:
        return False, "USDZ size must be between 64 bytes and 500 MB"
    if not zipfile.is_zipfile(asset):
        return False, "file is not a USDZ ZIP package"
    try:
        with zipfile.ZipFile(asset, "r") as archive:
            entries = archive.infolist()
            if not entries or len(entries) > 10000:
                return False, "USDZ is empty or contains too many entries"
            first = entries[0]
            if Path(first.filename).suffix.lower() not in USD_EXTENSIONS or first.file_size == 0:
                return False, "first USDZ package entry must be a non-empty USD scene file"
            root_signature = archive.read(first)[:8]
            if not (root_signature.startswith(b"#usda") or root_signature.startswith(b"PXR-USDC")):
                return False, "USDZ root scene has an unknown USD file signature"
            expanded = 0
            with asset.open("rb") as raw:
                for entry in entries:
                    name = PurePosixPath(entry.filename.replace("\\", "/"))
                    if name.is_absolute() or ".." in name.parts or entry.is_dir():
                        return False, "USDZ contains an unsafe path or directory entry"
                    if entry.flag_bits & 1:
                        return False, "encrypted USDZ entries are unsupported"
                    if entry.compress_type != zipfile.ZIP_STORED:
                        return False, "USDZ entries must be stored without ZIP compression"
                    raw.seek(entry.header_offset)
                    local_header = raw.read(30)
                    if len(local_header) != 30:
                        return False, "USDZ contains a truncated local ZIP header"
                    fields = struct.unpack("<IHHHHHIIIHH", local_header)
                    signature, name_length, extra_length = fields[0], fields[-2], fields[-1]
                    if signature != 0x04034B50:
                        return False, "USDZ contains an invalid local ZIP header"
                    offset = entry.header_offset + 30 + name_length + extra_length
                    if offset % 64:
                        return False, "USDZ entry is not 64-byte aligned"
                    expanded += entry.file_size
                    if expanded > MAX_BYTES:
                        return False, "USDZ expands beyond the 500 MB safety limit"
            if archive.testzip() is not None:
                return False, "USDZ contains a corrupt ZIP entry"
    except (OSError, zipfile.BadZipFile, RuntimeError) as exc:
        return False, f"could not read USDZ package: {exc}"
    return True, f"{size:,} bytes, aligned USDZ archive"

def validate(folder: Path) -> tuple[bool, str]:
    if folder.is_symlink() or not folder.is_dir():
        return False, "project folder must be a real directory"
    manifest_path = folder / "project.json"
    if not manifest_path.is_file() or manifest_path.is_symlink():
        return False, "missing project.json or manifest symlink"
    if manifest_path.stat().st_size > 1024 * 1024:
        return False, "project.json exceeds the 1 MB limit"
    try:
        data = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
    except Exception as exc:
        return False, f"invalid JSON: {exc}"
    if not isinstance(data, dict):
        return False, "manifest must be a JSON object"
    required = ("id", "name", "modelFile", "modelFormat")
    if any(not isinstance(data.get(k), str) or not data[k].strip() for k in required):
        return False, "required fields: id, name, modelFile and modelFormat"
    project_id = data["id"]
    if project_id != folder.name or re.fullmatch(r"[A-Za-z0-9_-]{1,80}", project_id) is None:
        return False, "project id must be a simple ID matching the folder name"
    name = data["modelFile"]
    if name != Path(name).name or name in (".", "..") or "/" in name or "\\" in name:
        return False, "modelFile must be a filename within the project folder"
    if not isinstance(data["modelFormat"], str) or Path(name).suffix.lower() != ".usdz" or data["modelFormat"].lower().lstrip(".") != "usdz":
        return False, "the iPad v1 project must reference a USDZ companion asset"
    asset = folder / name
    try:
        if asset.resolve().parent != folder.resolve():
            return False, "model path escapes the project folder"
    except OSError:
        return False, "could not resolve model path"
    ok, details = inspect_usdz(asset)
    if not ok:
        return False, details
    return True, f"{data['name']} -> {name} ({details})"

def main() -> int:
    if len(sys.argv) != 2:
        print("Usage: python validate_project.py <project-folder>")
        return 2
    ok, message = validate(Path(sys.argv[1]).expanduser().resolve())
    print(("PASS: " if ok else "FAIL: ") + message)
    return 0 if ok else 1

if __name__ == "__main__":
    raise SystemExit(main())
