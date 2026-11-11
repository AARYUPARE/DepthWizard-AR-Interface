import Foundation
import Combine

@MainActor
final class ProjectLibrary: ObservableObject {
    @Published private(set) var projects: [StoredProject] = []
    @Published var errorMessage: String?

    private let fileManager = FileManager.default
    private var root: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("DepthWizardProjects", isDirectory: true)
    }

    init() { refresh() }

    func refresh() {
        do {
            try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
            let folders = try fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
            projects = folders.compactMap { folder in
                let manifest = folder.appendingPathComponent("project.json")
                guard let data = try? Data(contentsOf: manifest),
                      let project = try? JSONDecoder.depthWizard.decode(DepthWizardProject.self, from: data),
                      ProjectAssetSupport.isSafeProjectID(project.id),
                      ProjectAssetSupport.isSafeFilename(project.modelFile),
                      project.modelFormat.lowercased() == "usdz",
                      ProjectAssetSupport.supportedExtensions.contains(URL(fileURLWithPath: project.modelFile).pathExtension.lowercased()) else { return nil }
                let asset = folder.appendingPathComponent(project.modelFile)
                guard fileManager.fileExists(atPath: asset.path) else { return nil }
                do { try validateUSDZHeader(at: asset) }
                catch { return nil }
                return StoredProject(project: project, folderURL: folder)
            }.sorted { ($0.project.createdAt ?? .distantPast) > ($1.project.createdAt ?? .distantPast) }
        } catch {
            errorMessage = "Couldn't read the project library: \(error.localizedDescription)"
        }
    }

    func importProjectFolder(from source: URL) {
        let granted = source.startAccessingSecurityScopedResource()
        defer { if granted { source.stopAccessingSecurityScopedResource() } }
        do {
            let manifestURL = source.appendingPathComponent("project.json")
            let data = try Data(contentsOf: manifestURL)
            let project = try JSONDecoder.depthWizard.decode(DepthWizardProject.self, from: data)
            guard ProjectAssetSupport.isSafeProjectID(project.id),
                  ProjectAssetSupport.isSafeFilename(project.modelFile),
                  project.modelFormat.lowercased() == "usdz" else { throw LibraryError.unsafeAssetName }
            let asset = source.appendingPathComponent(project.modelFile)
            guard fileManager.fileExists(atPath: asset.path) else { throw LibraryError.missingAsset(project.modelFile) }
            let ext = asset.pathExtension.lowercased()
            guard ProjectAssetSupport.supportedExtensions.contains(ext) else { throw LibraryError.unsupportedAsset(ext) }
            try validateUSDZHeader(at: asset)
            let staging = root.appendingPathComponent(".incoming-\(UUID().uuidString)", isDirectory: true)
            try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
            do {
                try fileManager.copyItem(at: asset, to: staging.appendingPathComponent(project.modelFile))
                try data.write(to: staging.appendingPathComponent("project.json"), options: .atomic)
                let destination = root.appendingPathComponent(project.id, isDirectory: true)
                if fileManager.fileExists(atPath: destination.path) { try fileManager.removeItem(at: destination) }
                try fileManager.moveItem(at: staging, to: destination)
            } catch {
                try? fileManager.removeItem(at: staging)
                throw error
            }
            refresh()
        } catch { errorMessage = error.localizedDescription }
    }

    func importModelFile(from source: URL) {
        let granted = source.startAccessingSecurityScopedResource()
        defer { if granted { source.stopAccessingSecurityScopedResource() } }
        let ext = source.pathExtension.lowercased()
        guard ProjectAssetSupport.supportedExtensions.contains(ext) else {
            errorMessage = ProjectAssetSupport.knownButUnsupportedExtensions.contains(ext)
                ? "This is a .\(ext) file. The iPad app opens USDZ companions; use the Windows export helper to convert the desktop GLB."
                : "Unsupported 3D file type: .\(ext)"
            return
        }
        let id = UUID().uuidString.lowercased()
        let folder = root.appendingPathComponent(id, isDirectory: true)
        do {
            try validateUSDZHeader(at: source)
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            let filename = "model.usdz"
            try fileManager.copyItem(at: source, to: folder.appendingPathComponent(filename))
            let project = DepthWizardProject(id: id, name: source.deletingPathExtension().lastPathComponent,
                description: "Imported USDZ asset", createdAt: Date(), modelFile: filename,
                modelFormat: "usdz", sourceImage: nil, elevationMode: "Imported", units: "Unspecified")
            try JSONEncoder.depthWizard.encode(project).write(to: folder.appendingPathComponent("project.json"), options: .atomic)
            refresh()
        } catch {
            try? fileManager.removeItem(at: folder)
            errorMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    func saveDownloadedProject(_ project: DepthWizardProject, modelFileAt sourceURL: URL) throws {
        guard ProjectAssetSupport.isSafeProjectID(project.id),
              ProjectAssetSupport.isSafeFilename(project.modelFile),
              project.modelFile.lowercased().hasSuffix(".usdz"),
              project.modelFormat.lowercased() == "usdz" else { throw LibraryError.unsafeAssetName }
        try validateUSDZHeader(at: sourceURL)
        let staging = root.appendingPathComponent(".incoming-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            try fileManager.copyItem(at: sourceURL, to: staging.appendingPathComponent(project.modelFile))
            try JSONEncoder.depthWizard.encode(project).write(to: staging.appendingPathComponent("project.json"), options: .atomic)
            let finalFolder = root.appendingPathComponent(project.id, isDirectory: true)
            if fileManager.fileExists(atPath: finalFolder.path) { try fileManager.removeItem(at: finalFolder) }
            try fileManager.moveItem(at: staging, to: finalFolder)
            refresh()
        } catch {
            try? fileManager.removeItem(at: staging)
            throw error
        }
    }

    func delete(_ stored: StoredProject) {
        do { try fileManager.removeItem(at: stored.folderURL); refresh() }
        catch { errorMessage = "Couldn't delete project: \(error.localizedDescription)" }
    }

    private func validateUSDZHeader(at url: URL) throws {
        guard !url.hasDirectoryPath,
              (try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])).isRegularFile == true,
              (try url.resourceValues(forKeys: [.isSymbolicLinkKey])).isSymbolicLink != true else {
            throw LibraryError.invalidUSDZ
        }
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
        guard size >= 64, size <= 500 * 1024 * 1024 else { throw LibraryError.invalidUSDZ }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let header = try handle.read(upToCount: 4) ?? Data()
        guard header == Data([0x50, 0x4b, 0x03, 0x04]) else { throw LibraryError.invalidUSDZ }
    }

}

struct StoredProject: Identifiable, Hashable {
    var id: String { project.id }
    let project: DepthWizardProject
    let folderURL: URL
}

enum LibraryError: LocalizedError {
    case missingAsset(String), unsupportedAsset(String), unsafeAssetName, invalidUSDZ
    var errorDescription: String? {
        switch self {
        case .missingAsset(let name): return "The project manifest points to a missing model: \(name)"
        case .unsupportedAsset(let ext): return "The project contains .\(ext). DepthWizard AR opens USDZ companions; convert the desktop GLB with the Windows export helper."
        case .unsafeAssetName: return "The model filename must be a simple filename inside the project folder."
        case .invalidUSDZ: return "This file is not a valid USDZ package. Re-export the project from the Windows helper."
        }
    }
}
