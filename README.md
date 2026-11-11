# DepthWizard AR — Windows-to-iPad companion

A light-themed iPad AR companion for DepthWizard Desktop. DepthWizard keeps its existing textured **GLB** as the desktop/source asset. A Windows helper uses Blender 4.2+ to create a **USDZ companion**; the iPad downloads that companion over a trusted private Wi-Fi network, verifies its SHA-256 digest, and places it into the room using ARKit + RealityKit.

> **Source package, not an installable IPA.** This repository contains the iPad SwiftUI source, Windows bridge/export tools, sample project, tests, and a GitHub Actions unsigned-build workflow. Native iPad compilation and signing must run with Apple's Xcode/iOS SDK. You do not need to buy a Mac: the included GitHub Actions workflow uses a hosted macOS runner for an unsigned compile check. Installing on a physical iPad still requires an Apple signing/provisioning route. This archive does not contain a signed IPA.

## What is included

- **Light iPad library:** DepthWizard-inspired pale canvas, white project cards, blue accent, project count, laptop connection, folder import, USDZ import, and delete action.
- **AR placement:** ARKit horizontal-plane detection, tap-to-place, RealityKit model loading, drag/rotate/scale gestures, reset and usage guidance.
- **Laptop project discovery:** a read-only Python HTTP bridge protected by a random temporary pairing code, private-LAN client filtering, failed-pairing throttling, manifest/path validation, USDZ package validation, and SHA-256 metadata.
- **Windows export helper:** takes the existing single-file DepthWizard GLB, converts it with Blender to a USDZ companion, preserves the original as `source.glb`, and writes a `project.json` manifest.
- **Integrity checks:** project IDs and asset names are constrained, USDZ archive entries are stored and 64-byte aligned, archive paths are checked, and downloads are verified by size and SHA-256 on iPad.
- **Sample project:** a small untextured USDA terrain packaged as a USDZ for exercising the import/sync/AR path.

## Data flow

```text
DepthWizard Desktop (Windows)
  textured terrain.glb  ← existing desktop export
          │
          ▼
DesktopBridge/export_project.ps1
  Blender 4.2+ imports GLB and writes USDZ
          │
          ▼
DepthWizard-AR-Exports/<project-id>/
  project.json
  model.usdz       ← iPad downloads this
  source.glb       ← preserved desktop master
          │
          ▼
DesktopBridge/server.py  (read-only, private Wi-Fi)
          │  pairing code + SHA-256 + file size
          ▼
iPad app → local project library → RealityKit / ARKit placement
```

RealityKit's asynchronous `Entity(contentsOf:)` loader supports USD/USDZ and Reality files; it does not natively load GLB. The desktop therefore retains GLB and creates a USDZ companion on Windows. See [Apple's RealityKit file-loading documentation](https://developer.apple.com/documentation/realitykit/entity/init%28contentsof%3Awithname%3A%29) and [Blender's USD export manual](https://docs.blender.org/manual/en/4.2/files/import_export/usd.html).

## Windows requirements

- Windows 10/11.
- Python 3.10+ available as `python` in PowerShell (only for the bridge and validator).
- Blender 4.2+ installed (for GLB → USDZ conversion).
- DepthWizard's final textured model exported as one `.glb` file.
- Laptop and iPad on the same trusted private Wi-Fi network.

No Python packages are required by the bridge, validator, tests, or converter wrapper. Blender provides its own Python runtime when the conversion script is run inside Blender.

## 1. Create an iPad companion project

Open PowerShell in the extracted project folder and run:

```powershell
.\DesktopBridge\export_project.ps1 `
  -Name "My reconstructed terrain" `
  -ModelPath "C:\path\to\terrain.glb" `
  -ElevationMode "Relative DSM" `
  -Units "relative"
```

If Blender is not on `PATH`, pass its executable explicitly:

```powershell
.\DesktopBridge\export_project.ps1 `
  -Name "My terrain" `
  -ModelPath "C:\path\to\terrain.glb" `
  -BlenderPath "C:\Program Files\Blender Foundation\Blender 4.2\blender.exe"
```

The helper creates:

```text
%USERPROFILE%\Documents\DepthWizard-AR-Exports\<project-id>\
  project.json
  model.usdz
  source.glb
```

Optional `-SourceImage` copies the source image into the export folder and records its filename in the manifest. The helper does not run DepthWizard inference or modify the desktop project. It packages an already-exported GLB. The existing Tauri source has **not** been patched with a one-click export button in this archive.

## 2. Start the laptop bridge

```powershell
.\DesktopBridge\start_sync_server.ps1
```

Keep the terminal open. It displays the laptop's private IP, port `8765`, and a temporary 10-character pairing code. If Windows Firewall prompts, allow Python on **Private networks only**. Do not add a public firewall rule, port-forward the bridge, or use it on public Wi-Fi.

To specify another export root:

```powershell
.\DesktopBridge\start_sync_server.ps1 -ProjectsDirectory "D:\DepthWizardExports"
```

## 3. Sync and place on iPad

1. Open DepthWizard AR and tap **Connect laptop**.
2. Enter the laptop's private IPv4 address and temporary pairing code.
3. Tap **Connect and find projects**.
4. Tap **Add** on a project. The iPad checks the downloaded file's size, SHA-256 and USDZ ZIP signature before saving it locally.
5. Close the connection sheet. The project appears in **Your workspace**.
6. Open the project, move the iPad slowly to scan a horizontal surface, then tap to place the model.
7. Drag to move, pinch to resize, and rotate with two fingers. Reset removes the placed model and restarts tracking.

Reconnect to refresh the laptop list after creating additional exports. The local library remains on the iPad between app launches. You can also use **Import project** for a folder containing `project.json` and `model.usdz`, or **Add USDZ model** for a single USDZ asset.

## 4. Build the iPad source

The Xcode project is generated from `project.yml` using XcodeGen. The included workflow at `.github/workflows/ios-build.yml` runs on a hosted macOS runner and attempts an unsigned iPadOS compile when the source changes or when manually dispatched.

For local development on Windows, edit Swift files and commit/push them to GitHub. A hosted macOS runner can compile the source. For installation on a physical iPad, you still need an Apple signing/provisioning path (for example, an Apple Developer account plus signed build). The workflow deliberately does not claim to produce an installable IPA.

## Security notes

- The bridge is read-only and independent of DepthWizard's inference sidecar. It does not expose model-generation or arbitrary filesystem APIs.
- It only serves project folders that pass manifest and USDZ validation.
- It requires a generated pairing code, rate-limits repeated wrong codes, and rejects clients outside private/loopback network ranges.
- Traffic uses plain HTTP on the private LAN. Treat the pairing code as temporary, keep the devices on a trusted network, and stop the bridge with `Ctrl+C` when finished.
- SHA-256 verifies transfer integrity, not scientific correctness, geospatial calibration, or trustworthiness of the source reconstruction.

## Project layout

```text
DepthWizardAR/       SwiftUI, RealityKit/ARKit, local library and sync client
DesktopBridge/       Windows PowerShell helpers and read-only Python server
Tools/               Blender conversion script, project validator, sample generator
Samples/              small sample USDZ project
Tests/                bridge validation and HTTP tests
Configuration/        iPad camera/local-network permission strings
.github/workflows/    hosted unsigned Xcode compile workflow
Docs/                 integration, format, Windows/iPad and validation notes
```

## Known limitations / validation status

- The Windows conversion helper and iPad source have not yet been run against your actual DepthWizard-generated GLB and physical iPad A16. Blender conversion is configurable but must be qualified against the exact materials, texture sizes and mesh extensions your desktop emits.
- Blender's USD exporter documents USDZ output and texture dependencies, but USD export supports a subset of material/shader behavior. Inspect the first real exported USDZ on iPad; tune the exporter profile if any material, UV, axis, or scale discrepancy appears.
- The sample USDZ is intentionally simple and untextured. It proves archive packaging and bridge flow, not the look of a real DepthWizard elevation model.
- The bridge exposes a folder of exported projects; the Tauri desktop UI currently does not automatically call the PowerShell helper. This is an interim handoff until a one-click export action is integrated into the real desktop source.
- Native iPad compile/sign/install and camera/AR interaction have not been executed in this environment. A Windows machine alone cannot run Apple's Xcode toolchain; use the included hosted macOS workflow for compile checks and an Apple signing path for installation.
