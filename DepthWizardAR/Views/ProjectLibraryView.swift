import SwiftUI

struct ProjectLibraryView: View {
    @EnvironmentObject private var library: ProjectLibrary
    @State private var showFolderImporter = false
    @State private var showModelImporter = false
    @State private var showConnectLaptop = false
    @State private var selectedProject: StoredProject?

    private let ink = Color(red: 0.13, green: 0.20, blue: 0.29)
    private let blue = Color(red: 0.15, green: 0.42, blue: 0.78)
    private let canvas = Color(red: 0.955, green: 0.968, blue: 0.982)

    var body: some View {
        NavigationStack {
            ZStack {
                canvas.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        header
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            actionButton("Connect laptop", system: "wifi", color: blue) { showConnectLaptop = true }
                            actionButton("Import project", system: "folder.badge.plus", color: .white, foreground: ink) { showFolderImporter = true }
                            actionButton("Add USDZ model", system: "cube.transparent", color: .white, foreground: ink) { showModelImporter = true }
                        }
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Your workspace").font(.title2.bold()).foregroundStyle(ink)
                                Text("Synced from your laptop or imported from Files").font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(library.projects.count) PROJECTS").font(.caption2.bold()).tracking(0.8).foregroundStyle(blue)
                        }
                        if library.projects.isEmpty { emptyState }
                        else {
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                                ForEach(library.projects) { item in
                                    Button { selectedProject = item } label: { ProjectCard(item: item) }
                                        .buttonStyle(.plain)
                                        .contextMenu { Button(role: .destructive) { library.delete(item) } label: { Label("Delete project", systemImage: "trash") } }
                                }
                            }
                        }
                        infoStrip
                    }.padding(20)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .fileImporter(isPresented: $showFolderImporter, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
                if case .success(let urls) = result, let url = urls.first { library.importProjectFolder(from: url) }
            }
            .fileImporter(isPresented: $showModelImporter, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
                if case .success(let urls) = result, let url = urls.first { library.importModelFile(from: url) }
            }
            .sheet(item: $selectedProject) { item in ARExperienceView(storedProject: item) }
            .sheet(isPresented: $showConnectLaptop) { ConnectLaptopView().environmentObject(library) }
            .alert("DepthWizard AR", isPresented: Binding(get: { library.errorMessage != nil }, set: { if !$0 { library.errorMessage = nil } })) {
                Button("OK", role: .cancel) { library.errorMessage = nil }
            } message: { Text(library.errorMessage ?? "") }
        }
        .tint(blue)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ZStack { RoundedRectangle(cornerRadius: 15).fill(blue).frame(width: 48, height: 48); Image(systemName: "view.3d").font(.title2.bold()).foregroundStyle(.white) }
                VStack(alignment: .leading, spacing: 2) {
                    Text("DEPTHWIZARD").font(.caption.bold()).tracking(2).foregroundStyle(blue)
                    Text("AR Studio").font(.title.bold()).foregroundStyle(ink)
                }
                Spacer()
                Image(systemName: "ipad.gen2").font(.title2).foregroundStyle(blue)
            }
            Text("Bring your reconstructed worlds into reality.")
                .font(.system(size: 27, weight: .semibold, design: .rounded)).foregroundStyle(ink).fixedSize(horizontal: false, vertical: true)
            Text("Sync a reconstruction from your Windows laptop or import a USDZ model to explore it in augmented reality.")
                .font(.subheadline).foregroundStyle(.secondary).lineSpacing(3)
        }
        .padding(20).background(.white, in: RoundedRectangle(cornerRadius: 24)).overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.black.opacity(0.045)))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "cube.transparent").font(.system(size: 42)).foregroundStyle(blue.opacity(0.8))
            Text("Your 3D library is empty").font(.headline).foregroundStyle(ink)
            Text("Connect your Windows laptop over Wi-Fi, or import a USDZ project from Files.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button { showConnectLaptop = true } label: { Label("Connect laptop", systemImage: "wifi") }.buttonStyle(.borderedProminent)
        }.frame(maxWidth: .infinity).padding(28).background(.white, in: RoundedRectangle(cornerRadius: 22))
    }

    private var infoStrip: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill").foregroundStyle(blue)
            Text("DepthWizard keeps its textured GLB master. The Windows helper creates a USDZ companion for RealityKit; the iPad verifies each laptop download with SHA-256 before saving it.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(14).background(.white, in: RoundedRectangle(cornerRadius: 16))
    }

    private func actionButton(_ title: String, system: String, color: Color, foreground: Color = .white, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: system).font(.subheadline.bold()).foregroundStyle(foreground)
                .frame(maxWidth: .infinity).padding(.vertical, 15).background(color, in: RoundedRectangle(cornerRadius: 15))
                .overlay(RoundedRectangle(cornerRadius: 15).stroke(Color.black.opacity(color == .white ? 0.07 : 0)))
        }
    }
}

private struct ProjectCard: View {
    let item: StoredProject
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 15).fill(LinearGradient(colors: [Color(red: 0.88, green: 0.93, blue: 0.98), Color(red: 0.95, green: 0.97, blue: 0.99)], startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "mountain.2.fill").font(.system(size: 36)).foregroundStyle(Color(red: 0.24, green: 0.48, blue: 0.72))
                VStack { HStack { Spacer(); Text(item.project.displayFormat).font(.system(size: 9, weight: .bold)).padding(6).background(.white.opacity(0.85), in: Capsule()) }; Spacer() }.padding(9)
            }.frame(height: 112)
            Text(item.project.name).font(.subheadline.bold()).foregroundStyle(Color(red: 0.13, green: 0.20, blue: 0.29)).lineLimit(1)
            Text(item.project.elevationMode ?? "3D reconstruction").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Label("Open in AR", systemImage: "arkit").font(.caption.bold()).foregroundStyle(Color(red: 0.15, green: 0.42, blue: 0.78))
        }.padding(10).background(.white, in: RoundedRectangle(cornerRadius: 19)).overlay(RoundedRectangle(cornerRadius: 19).stroke(Color.black.opacity(0.045)))
    }
}
