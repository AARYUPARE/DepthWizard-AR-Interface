import Foundation

struct DepthWizardProject: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var description: String?
    var createdAt: Date?
    var modelFile: String
    var modelFormat: String
    var sourceImage: String?
    var elevationMode: String?
    var units: String?

    var displayFormat: String { modelFormat.uppercased() }
}

struct RemoteProject: Identifiable, Decodable, Hashable {
    let id: String
    let name: String
    let description: String?
    let createdAt: String?
    let modelFile: String
    let modelFormat: String
    let sourceImage: String?
    let elevationMode: String?
    let units: String?
    let modelSizeBytes: Int
    let sha256: String

    var displaySize: String {
        ByteCountFormatter.string(fromByteCount: Int64(modelSizeBytes), countStyle: .file)
    }

    func localProject() -> DepthWizardProject {
        let date = createdAt.flatMap { ISO8601DateFormatter().date(from: $0) }
        return DepthWizardProject(
            id: id, name: name, description: description, createdAt: date,
            modelFile: modelFile, modelFormat: modelFormat,
            sourceImage: sourceImage, elevationMode: elevationMode, units: units
        )
    }
}

enum ProjectAssetSupport {
    static let supportedExtensions: Set<String> = ["usdz"]
    static let knownButUnsupportedExtensions: Set<String> = ["glb", "gltf", "obj", "ply", "stl", "usd", "usda", "usdc", "reality"]

    static func isSafeFilename(_ name: String) -> Bool {
        !name.isEmpty && name == URL(fileURLWithPath: name).lastPathComponent && !name.contains("..") && !name.contains("/") && !name.contains("\\")
    }

    static func isSafeProjectID(_ value: String) -> Bool {
        value.range(of: "^[A-Za-z0-9_-]{1,80}$", options: .regularExpression) != nil
    }
}

extension JSONDecoder {
    static var depthWizard: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

extension JSONEncoder {
    static var depthWizard: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
