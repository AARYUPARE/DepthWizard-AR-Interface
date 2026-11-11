import SwiftUI

struct ConnectLaptopView: View {
    @EnvironmentObject private var library: ProjectLibrary
    @Environment(\.dismiss) private var dismiss
    @AppStorage("depthWizardLaptopIP") private var savedHost = ""
    @State private var host = ""
    @State private var pairingCode = ""
    @State private var remoteProjects: [RemoteProject] = []
    @State private var isConnecting = false
    @State private var downloadingID: String?
    @State private var message: String?
    @State private var isError = false

    private let client = ProjectSyncClient()
    private let blue = Color(red: 0.15, green: 0.42, blue: 0.78)
    private let ink = Color(red: 0.13, green: 0.20, blue: 0.29)

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.955, green: 0.968, blue: 0.982).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        introCard
                        connectionForm
                        if !remoteProjects.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("Laptop projects").font(.title2.bold()).foregroundStyle(ink)
                                    Spacer()
                                    Text("\(remoteProjects.count) FOUND").font(.caption2.bold()).foregroundStyle(blue)
                                }
                                ForEach(remoteProjects) { project in remoteCard(project) }
                            }
                        }
                        securityNote
                    }.padding(18)
                }
            }
            .navigationTitle("Connect laptop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .alert(isError ? "Connection problem" : "DepthWizard AR", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) { message = nil }
            } message: { Text(message ?? "") }
            .onAppear { host = savedHost }
        }
        .tint(blue)
    }

    private var introCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "wifi").font(.title2).foregroundStyle(blue)
            Text("Bring your desktop projects over Wi-Fi.").font(.title2.bold()).foregroundStyle(ink)
            Text("Start the DepthWizard AR bridge on your Windows laptop. Keep both devices on the same trusted Wi-Fi network, then enter the IP address and temporary pairing code shown in the laptop terminal.")
                .font(.subheadline).foregroundStyle(.secondary).lineSpacing(3)
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(.white, in: RoundedRectangle(cornerRadius: 20))
    }

    private var connectionForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Laptop connection").font(.headline).foregroundStyle(ink)
            VStack(alignment: .leading, spacing: 6) {
                Text("LAPTOP IP ADDRESS").font(.caption2.bold()).tracking(0.8).foregroundStyle(.secondary)
                TextField("192.168.1.20", text: $host).keyboardType(.decimalPad).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .padding(13).background(Color(red: 0.96, green: 0.97, blue: 0.985), in: RoundedRectangle(cornerRadius: 12))
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("PAIRING CODE").font(.caption2.bold()).tracking(0.8).foregroundStyle(.secondary)
                SecureField("Enter code from laptop terminal", text: $pairingCode).textInputAutocapitalization(.characters).autocorrectionDisabled()
                    .padding(13).background(Color(red: 0.96, green: 0.97, blue: 0.985), in: RoundedRectangle(cornerRadius: 12))
            }
            Button { Task { await connect() } } label: {
                HStack { if isConnecting { ProgressView().tint(.white) }; Text(isConnecting ? "Connecting…" : "Connect and find projects") }
                    .font(.subheadline.bold()).frame(maxWidth: .infinity).padding(.vertical, 15)
                    .foregroundStyle(.white).background(blue, in: RoundedRectangle(cornerRadius: 14))
            }.disabled(isConnecting || host.isEmpty || pairingCode.isEmpty)
        }.padding(18).background(.white, in: RoundedRectangle(cornerRadius: 20))
    }

    private func remoteCard(_ project: RemoteProject) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 13).fill(Color(red: 0.89, green: 0.94, blue: 0.99)).frame(width: 58, height: 58)
                .overlay(Image(systemName: "mountain.2.fill").font(.title2).foregroundStyle(blue))
            VStack(alignment: .leading, spacing: 4) {
                Text(project.name).font(.subheadline.bold()).foregroundStyle(ink).lineLimit(1)
                Text("\(project.displaySize) · \(project.elevationMode ?? "3D terrain")")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            Button { Task { await download(project) } } label: {
                if downloadingID == project.id { ProgressView() }
                else { Label("Add", systemImage: "arrow.down.to.line").font(.caption.bold()) }
            }.buttonStyle(.borderedProminent).tint(blue).disabled(downloadingID != nil)
        }.padding(12).background(.white, in: RoundedRectangle(cornerRadius: 17))
    }

    private var securityNote: some View {
        Label("Local network only. The bridge is read-only and should never be exposed to the public Internet.", systemImage: "lock.shield.fill")
            .font(.caption).foregroundStyle(.secondary).padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 15))
    }

    @MainActor
    private func connect() async {
        isConnecting = true
        defer { isConnecting = false }
        do {
            pairingCode = pairingCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            host = host.trimmingCharacters(in: .whitespacesAndNewlines)
            remoteProjects = try await client.fetchProjects(host: host, pairingCode: pairingCode)
            savedHost = host
            if remoteProjects.isEmpty { message = "Connected successfully. No exported projects were found in the laptop's AR export folder yet."; isError = false }
        } catch { message = error.localizedDescription; isError = true }
    }

    @MainActor
    private func download(_ remote: RemoteProject) async {
        downloadingID = remote.id
        defer { downloadingID = nil }
        do {
            let (project, downloadedFile) = try await client.download(remote, host: host, pairingCode: pairingCode)
            defer { try? FileManager.default.removeItem(at: downloadedFile) }
            try library.saveDownloadedProject(project, modelFileAt: downloadedFile)
            message = "\(project.name) was added to your iPad library."
            isError = false
        } catch { message = error.localizedDescription; isError = true }
    }
}
