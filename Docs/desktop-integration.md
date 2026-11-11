# DepthWizard desktop integration

The published DepthWizard README describes a Tauri/Three.js geospatial desktop application and textured GLB/LOD terrain output. The AR companion intentionally treats that GLB as the desktop master. RealityKit's native `Entity(contentsOf:)` loader accepts USD/USDZ and Reality files, not GLB, so the Windows helper converts the GLB into a USDZ companion using Blender's built-in USD exporter.

## Current integration included in this archive

`DesktopBridge/export_project.ps1` is an interim Windows export step. It runs `Tools/convert_glb_to_usdz.py` inside Blender 4.2+, preserves the source as `source.glb`, writes `model.usdz` and a manifest, then validates the result. `DesktopBridge/server.py` serves validated project folders on a private LAN.

The project does **not** patch the public DepthWizard Tauri source with a new menu item or automatic conversion. A developer can integrate a one-click action after the existing GLB export is finalized. That action should pass the GLB path, project display name, elevation mode, units, and source image to the same conversion/manifest logic, or invoke the PowerShell helper.

## Recommended future desktop action

1. User selects **Export to iPad AR** after a successful GLB export.
2. Desktop code creates a unique project ID and invokes the Blender conversion helper or a controlled packaging service.
3. Write `project.json`, `model.usdz`, and retain the source GLB in the export root.
4. Start/notify the bridge, or have the bridge run as an explicit opt-in local service.
5. Refreshing the iPad connection displays the new export.

Keep the scientific inference sidecar bound to loopback. Do not make that API network-accessible just to sync a rendered asset.
