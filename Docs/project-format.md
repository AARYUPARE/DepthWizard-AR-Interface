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
  "id": "terrain-project-001",
  "name": "Reconstructed terrain",
  "createdAt": "2026-11-12T08:00:00Z",
  "modelFile": "model.usdz",
  "modelFormat": "usdz",
  "elevationMode": "Relative DSM",
  "units": "relative",
  "surfaceProduct": "rdsm",
  "horizontalUnits": "m",
  "verticalUnits": "relative",
  "measurementSchemaVersion": 1,
  "measurementCoordinateSpace": "terrain_glb_local_bounds_v1",
  "measurementPixelOrigin": "top_left_zero_based",
  "measurementAxes": {
    "x": "raster_columns_positive",
    "y": "mesh_elevation_up",
    "z": "negative_raster_rows"
  },
  "measurementRasterWidth": 107,
  "measurementRasterHeight": 83,
  "measurementMeshStride": 5,
  "measurementValueMinimum": 0.0,
  "measurementValueMaximum": 0.6,
  "sourceMeshSha256": "<64 lowercase hex characters>",
  "measurementSourceSurfaceSha256": "<64 lowercase hex characters>",
  "measurementMeshSha256": "<same digest as sourceMeshSha256>",
  "measurementBuildConfigSha256": "<64 lowercase hex characters>",
  "measurements": [
    {
      "id": "p00_00",
      "label": "Point 01",
      "value": 0.375,
      "units": "relative",
      "source": "Persisted relative DSM raster",
      "type": "rdsm",
      "pixelX": 10,
      "pixelY": 25,
      "normalizedPosition": { "x": 0.09433962264150944, "y": 0.625, "z": 0.6951219512195121 },
      "featured": false
    }
  ]
}
```

Required string fields remain `id`, `name`, `modelFile`, and `modelFormat`. The ID is 1–80 characters from `[A-Za-z0-9_-]` and must match the folder name. `modelFile` is a filename inside the project folder and must end in `.usdz`; `modelFormat` must be `usdz`. Measurement fields are optional for older projects.

## Measurement contract

Desktop samples the persisted primary DSM or rDSM used to generate the exported LOD0 terrain. Up to 100 spatially distributed points are included. Nine points (a 3×3 distribution across the raster) are marked `featured` for the initial AR view; the iPad can reveal the full set. Every measurement contains the raw source-raster value, source product, units, zero-based pixel column/row, and a dimensionless position within the exported terrain mesh bounds. The manifest also stores `measurementValueMinimum` and `measurementValueMaximum` over sampled LOD0 vertices; normalized Y must equal the raw source value mapped into that range (or 0.5 for a flat range). This is equivalent to the positive display-elevation transform used by the mesh, including rDSM display scaling.

`measurementCoordinateSpace = terrain_glb_local_bounds_v1` means the normalized XYZ position is a fraction of the exported mesh's local bounding box, not latitude/longitude or a world coordinate. The axis mapping follows the terrain builder: X increases with raster columns, Y is mesh elevation up, and positive normalized Z points toward the top (row zero) of the source raster. Pixel origin is top-left, zero-based. This contract is tied to the LOD0 mesh stride reported in the manifest.

DSM measurement values use metres only when the source DSM declares metre units. rDSM values retain the raw relative elevation value and `relative` units. rDSM's display-only vertical exaggeration is used only to position the point on the rendered terrain; it is never applied to the reported measurement value or presented as metres.

Bridge validation checks the schema, coordinate-space declaration, axis declaration, raster dimensions, mesh stride, unique IDs, finite values, units/product consistency, pixel bounds, normalized positions in [0, 1], exact normalized X/Z correspondence to the source pixel, normalized Y correspondence to the source value range, and that each pixel lies on the declared LOD0 sample grid (including appended last-row/last-column edge vertices). It also checks the source surface, source mesh, and build-configuration SHA-256 provenance fields; the measurement mesh digest must match the exported source GLB digest. Legacy projects without measurement metadata remain valid and simply show no measurement pins.

The laptop bridge computes the model size and SHA-256 at discovery time. The iPad checks both after download and verifies the ZIP signature before saving. The bridge also checks that USDZ entries are uncompressed, 64-byte aligned, path-safe, within size limits, and that the first entry is a USD scene file. These are package/transfer checks, not proof that RealityKit will render every possible material or that the elevation model is scientifically accurate.
