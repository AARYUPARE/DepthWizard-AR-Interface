# DepthWizard AR project format (v1)

One export lives in a directory named exactly for its project ID:

```text
<project-id>/
  project.json
  model.usdz
  source.glb        # optional, preserved desktop source; not downloaded by iPad
  <source-image>    # optional provenance image
```

Example `project.json`:

```json
{
  "id": "sydney-opera-house-001",
  "name": "Sydney Opera House",
  "description": "DepthWizard reconstructed terrain",
  "createdAt": "2026-11-11T08:00:00Z",
  "modelFile": "model.usdz",
  "modelFormat": "usdz",
  "sourceModelFile": "source.glb",
  "sourceImage": "000.png",
  "elevationMode": "Relative DSM",
  "units": "relative"
}
```

Required string fields: `id`, `name`, `modelFile`, `modelFormat`. `id` is 1–80 characters from `[A-Za-z0-9_-]` and must match the folder name. `modelFile` must be a filename in the project folder, with `.usdz` extension. `modelFormat` must be `usdz`. v1 serves one self-contained USDZ companion and does not serve the original GLB or arbitrary project files.

The laptop bridge computes the model's size and SHA-256 at discovery time. The iPad checks both after download and verifies the ZIP signature before saving. The bridge also checks that USDZ entries are uncompressed, 64-byte aligned, path-safe, within size limits, and that the first entry is a USD scene file. These are package/transfer checks, not proof that RealityKit will render every possible material or that the elevation model is scientifically accurate.

The desktop master remains GLB. Blender 4.2+ converts that file into the USDZ companion needed by RealityKit. The source GLB is preserved in the project folder for traceability.
