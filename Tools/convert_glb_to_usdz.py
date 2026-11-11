"""Run inside Blender 4.2+ to convert one self-contained GLB into USDZ.

Invocation: blender --background --factory-startup --python this_file.py -- --input a.glb --output b.usdz
"""
from __future__ import annotations
import argparse
import sys
from pathlib import Path


def arguments() -> argparse.Namespace:
    values = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True)
    parser.add_argument("--output", required=True)
    return parser.parse_args(values)


def main() -> int:
    import bpy  # type: ignore

    args = arguments()
    source = Path(args.input).expanduser().resolve()
    destination = Path(args.output).expanduser().resolve()
    if not source.is_file() or source.suffix.lower() != ".glb":
        raise SystemExit(f"Input must be an existing .glb file: {source}")
    if bpy.app.version < (4, 2, 0):
        raise SystemExit(f"Blender 4.2 or newer is required for the USDZ export workflow. Found {bpy.app.version_string}.")

    bpy.ops.wm.read_factory_settings(use_empty=True)
    # Blender 4.2 ships glTF I/O as a bundled extension/add-on; explicitly enable it
    # because this helper is run with factory settings in background mode.
    try:
        bpy.ops.preferences.addon_enable(module="io_scene_gltf2")
    except Exception as exc:
        raise SystemExit(
            "Could not enable Blender's bundled glTF 2.0 importer. "
            "Open Blender once, install/enable the glTF 2.0 I/O extension, and retry. "
            f"Details: {exc}"
        ) from exc
    if not hasattr(bpy.ops.import_scene, "gltf"):
        raise SystemExit("Blender's glTF 2.0 importer is unavailable. Enable the glTF 2.0 I/O extension and retry.")
    bpy.ops.import_scene.gltf(filepath=str(source))
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    if not meshes:
        raise SystemExit("The GLB did not contain any mesh objects.")

    operator_properties = bpy.ops.wm.usd_export.get_rna_type().properties
    available = {prop.identifier for prop in operator_properties}
    options = {
        "filepath": str(destination),
        "selected_objects_only": False,
        "export_animation": False,
        "export_meshes": True,
        "export_lights": False,
        "export_cameras": False,
        "export_uvmaps": True,
        "export_normals": True,
        "export_materials": True,
        "triangulate_meshes": True,
        "convert_scene_units": "METERS",
        "meters_per_unit": 1.0,
        "usdz_downscale_size": "KEEP",
        "root_prim_path": "/DepthWizardProject",
        "relative_paths": True,
        "overwrite_textures": True,
    }
    # Blender 4.2 used export_textures; newer releases expose export_textures_mode.
    if "export_textures_mode" in available:
        options["export_textures_mode"] = "NEW"
    elif "export_textures" in available:
        options["export_textures"] = True
    options = {key: value for key, value in options.items() if key in available}
    result = bpy.ops.wm.usd_export(**options)
    if "FINISHED" not in result or not destination.is_file() or destination.stat().st_size == 0:
        raise SystemExit("Blender did not produce a USDZ asset.")
    print(f"USDZ export written: {destination} ({destination.stat().st_size:,} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
