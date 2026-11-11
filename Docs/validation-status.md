# Validation status

## Checks run in the source-build environment

- Python syntax compilation for the bridge, converter wrapper, validator, sample generator and tests.
- Bridge unit tests cover valid USDZ project metadata and SHA-256, traversal rejection, manifest path escape, malformed archive rejection, private-network filtering, authenticated project discovery, and model download.
- Sample project generator and project validator check the generated 64-byte-aligned USDZ package.
- Swift source is parser-checked where a Swift compiler is available; this is **not** an iOS SDK compile or link.
- XcodeGen YAML and Info.plist syntax are validated.
- ZIP integrity check on the delivered source archive.

## Not verified here

- No Blender runtime is installed in this environment, so the real GLB → USDZ conversion script has not been executed. The first real DepthWizard GLB must be converted and inspected; tune any Blender export options if geometry, UVs, textures, axes or scale differ.
- No Xcode/iOS SDK is available here. The app has not been built, signed or installed, and the GitHub Actions workflow has not been run from this workspace.
- No physical iPad A16 was available for camera permission, plane detection, tap placement, gestures, local network transfer, or RealityKit material rendering.
- The sample USDZ is intentionally simple and untextured; it tests package and bridge plumbing rather than DepthWizard's textured terrain look.
- The actual DepthWizard Tauri repository source was not changed. The PowerShell helper is an interim export path, not a one-click desktop integration.

These gaps are explicitly recorded so a successful packaging check is not confused with an end-to-end device test.
