# Windows laptop → iPad workflow

## Requirements

- Windows 10/11, Python 3.10+ and Blender 4.2+.
- DepthWizard final textured terrain exported as a single-file `.glb`.
- An ARKit-capable iPad (the A16 iPad generation is intended target; verify iPadOS and camera access on device).
- Both devices connected to the same trusted private Wi-Fi network.

## 1. Export a USDZ companion

Open PowerShell in the extracted companion folder:

```powershell
.\DesktopBridge\export_project.ps1 `
  -Name "My reconstructed terrain" `
  -ModelPath "C:\path\to\terrain.glb" `
  -ElevationMode "Relative DSM" `
  -Units "relative"
```

The helper invokes Blender in background mode to import GLB and export a USDZ, then validates the generated archive. It writes `project.json`, `model.usdz`, and the preserved `source.glb` into `%USERPROFILE%\Documents\DepthWizard-AR-Exports\<project-id>\`.

If needed, pass `-BlenderPath "C:\...\blender.exe"`. The conversion script requires Blender 4.2+ and uses the built-in USD exporter. Blender documents that setting the output extension to `.usdz` writes a ZIP-based package with the USD scene and its texture dependencies. See https://docs.blender.org/manual/en/4.2/files/import_export/usd.html.

This helper packages an already-exported GLB; it does not change the DepthWizard Tauri code or create a one-click desktop button.

## 2. Start the bridge

```powershell
.\DesktopBridge\start_sync_server.ps1
```

Keep the terminal open. Copy the IP and temporary pairing code shown. If Windows Firewall prompts, allow Python only for a **Private** network. Never port-forward the server or expose it to the public Internet.

## 3. Pair and sync on iPad

1. Open DepthWizard AR → **Connect laptop**.
2. Enter the laptop's private IPv4 address and pairing code.
3. Tap **Connect and find projects**.
4. Tap **Add** to download a project. The app checks file size, SHA-256 and the USDZ archive signature.
5. Return to the library and open the downloaded project in AR.
6. Scan a horizontal surface, tap to place the model, then use drag/rotate/scale gestures.

Reconnect to refresh the project list after exporting something new. **Import project** accepts the folder containing `project.json` and `model.usdz`; **Add USDZ model** imports a standalone USDZ.

## 4. Security

The bridge is read-only and separate from the DepthWizard inference sidecar. It exposes only validated project metadata and USDZ assets. It filters clients to private/loopback address ranges, uses a temporary random pairing code, and throttles repeated failed pairing attempts. It uses plain HTTP; use only on a trusted private Wi-Fi network and stop it with `Ctrl+C` when done.

## 5. Native iPad build reality

You can write and edit the Swift source on Windows. Apple's Xcode/iOS SDK is still needed to compile a native iPad app, and a physical device install requires a signed/provisioned app. No Mac purchase is required for source editing: the included GitHub Actions workflow requests an unsigned build on a hosted macOS runner. The workflow does not create a signed IPA or install the app on your iPad.
