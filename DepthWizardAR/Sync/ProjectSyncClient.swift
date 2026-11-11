import Foundation
import CryptoKit

struct ProjectListResponse: Decodable {
    let projects: [RemoteProject]
}

enum ProjectSyncError: LocalizedError {
    case invalidAddress, http(Int), invalidResponse, hashMismatch, tooLarge, invalidAsset
    var errorDescription: String? {
        switch self {
        case .invalidAddress: return "Enter the laptop's private Wi-Fi IP address, for example 192.168.1.20."
        case .http(let code): return "Laptop bridge returned HTTP \(code). Check the IP, pairing code and server window."
        case .invalidResponse: return "The laptop returned an unreadable project response."
        case .hashMismatch: return "The downloaded model failed its SHA-256 integrity check. Please retry the transfer."
        case .tooLarge: return "The project is larger than the 500 MB transfer limit."
        case .invalidAsset: return "The laptop did not send a valid USDZ model package."
        }
    }
}

struct ProjectSyncClient {
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 600
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    func fetchProjects(host: String, pairingCode: String) async throws -> [RemoteProject] {
        let url = try endpoint(host: host, path: "/api/v1/projects")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(pairingCode)", forHTTPHeaderField: "Authorization")
        request.setValue("1", forHTTPHeaderField: "ngrok-skip-browser-warning")
        let (data, response) = try await session.data(for: request)
        try check(response)
        guard let decoded = try? JSONDecoder().decode(ProjectListResponse.self, from: data) else { throw ProjectSyncError.invalidResponse }
        return decoded.projects
    }

    func download(_ project: RemoteProject, host: String, pairingCode: String) async throws -> (DepthWizardProject, URL) {
        guard project.modelSizeBytes > 0, project.modelSizeBytes <= 500 * 1024 * 1024 else { throw ProjectSyncError.tooLarge }
        guard ProjectAssetSupport.isSafeProjectID(project.id),
              ProjectAssetSupport.isSafeFilename(project.modelFile),
              project.modelFile.lowercased().hasSuffix(".usdz"),
              project.modelFormat.lowercased() == "usdz",
              project.sha256.range(of: "^[0-9a-fA-F]{64}$", options: .regularExpression) != nil else {
            throw ProjectSyncError.invalidAsset
        }
        let url = try endpoint(host: host, path: "/api/v1/projects/\(project.id)/model")
        var request = URLRequest(url: url)
        request.setValue("Bearer \(pairingCode)", forHTTPHeaderField: "Authorization")
        request.setValue("1", forHTTPHeaderField: "ngrok-skip-browser-warning")
        let (temporaryFile, response) = try await session.download(for: request)
        do {
            try check(response)
            let attributes = try FileManager.default.attributesOfItem(atPath: temporaryFile.path)
            let downloadedSize = (attributes[.size] as? NSNumber)?.intValue ?? 0
            guard downloadedSize == project.modelSizeBytes else { throw ProjectSyncError.invalidResponse }
            let actualDigest = try sha256File(at: temporaryFile)
            guard actualDigest.caseInsensitiveCompare(project.sha256) == .orderedSame else {
                throw ProjectSyncError.hashMismatch
            }
            let header = try FileHandle(forReadingFrom: temporaryFile)
            let signature = try header.read(upToCount: 4) ?? Data()
            try header.close()
            guard downloadedSize >= 64, signature == Data([0x50, 0x4b, 0x03, 0x04]) else {
                throw ProjectSyncError.invalidAsset
            }
            return (project.localProject(), temporaryFile)
        } catch {
            try? FileManager.default.removeItem(at: temporaryFile)
            throw error
        }
    }

    private func sha256File(at url: URL) throws -> String {
        var digest = SHA256()
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            digest.update(data: chunk)
        }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func endpoint(host: String, path: String) throws -> URL {
    let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !trimmed.isEmpty,
          var components = URLComponents(string:
            trimmed.contains("://") ? trimmed : "http://\(trimmed)"
          ),
          let scheme = components.scheme?.lowercased(),
          ["http", "https"].contains(scheme),
          let hostname = components.host,
          !hostname.isEmpty,
          components.user == nil,
          components.password == nil,
          components.query == nil,
            components.fragment == nil,
            components.path.isEmpty
        else {
            throw ProjectSyncError.invalidAddress
        }

        if scheme == "http" && components.port == nil {
            components.port = 8765
        }

        components.path = path

        guard let url = components.url else {
            throw ProjectSyncError.invalidAddress
        }

        return url
    }

    private func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw ProjectSyncError.invalidResponse }
        guard (200...299).contains(http.statusCode) else { throw ProjectSyncError.http(http.statusCode) }
    }
}
