# Third-party notices

## Blender

The Windows conversion tool invokes a separately installed copy of Blender 4.2+ and uses Blender's built-in glTF importer and USD exporter. Blender is not bundled in this archive. Blender's license and distribution notices are provided by the Blender Foundation with the user's installed copy: https://www.blender.org/about/license/.

## Apple frameworks

The iPad source uses Apple's SwiftUI, ARKit and RealityKit SDKs. No third-party Swift package or prebuilt framework is bundled.

## Python

The bridge, project validator, test suite and Blender-side conversion wrapper use the Python standard library. Blender supplies the `bpy` runtime when the conversion script is executed by `blender.exe`.
