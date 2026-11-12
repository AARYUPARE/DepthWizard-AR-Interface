import Foundation

/// Coordinates are normalized to the exported terrain mesh bounds (0...1).
/// They are intentionally dimensionless so AR placement can map them into the
/// RealityKit entity's local bounds without treating relative elevation as metres.
struct TerrainMeasurementPosition: Codable, Hashable {
    var x: Double
    var y: Double
    var z: Double

    var isValid: Bool {
        x.isFinite && y.isFinite && z.isFinite &&
        (0...1).contains(x) && (0...1).contains(y) && (0...1).contains(z)
    }
}

struct TerrainMeasurement: Identifiable, Codable, Hashable {
    let id: String
    let label: String
    let value: Double
    let units: String
    let source: String
    let type: String
    let pixelX: Int
    let pixelY: Int
    let normalizedPosition: TerrainMeasurementPosition
    var featured: Bool

    var displayValue: String {
        let number = value.formatted(.number.precision(.fractionLength(0...3)))
        return units.isEmpty ? number : "\(number) \(units)"
    }
}
