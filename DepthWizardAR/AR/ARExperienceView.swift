import SwiftUI
import RealityKit
import ARKit
import UIKit

struct ARExperienceView: View {
    let storedProject: StoredProject
    @Environment(\.dismiss) private var dismiss
    @State private var status = "Move your iPad slowly to find a surface."
    @State private var showHelp = false
    @State private var resetToken = UUID()

    var body: some View {
        ZStack {
            ARSceneView(
                modelURL: storedProject.folderURL.appendingPathComponent(storedProject.project.modelFile),
                resetToken: resetToken,
                status: $status
            ).ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left").font(.headline).foregroundStyle(.primary)
                            .padding(12).background(.regularMaterial, in: Circle())
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(storedProject.project.name).font(.subheadline.bold())
                        Text("DEPTHWIZARD AR").font(.system(size: 9, weight: .bold)).tracking(1.4).foregroundStyle(.secondary)
                    }.padding(.horizontal, 14).padding(.vertical, 9).background(.regularMaterial, in: Capsule())
                }.padding(.horizontal, 18).padding(.top, 12)
                Spacer()
                VStack(spacing: 12) {
                    Text(status).font(.subheadline.weight(.medium)).multilineTextAlignment(.center)
                        .padding(.horizontal, 18).padding(.vertical, 12).frame(maxWidth: .infinity)
                        .background(.regularMaterial, in: Capsule())
                    HStack(spacing: 14) {
                        control("Reset", icon: "arrow.counterclockwise") { resetToken = UUID() }
                        control("Instructions", icon: "questionmark.circle") { showHelp = true }
                    }
                }.padding(18)
            }
        }
        .statusBarHidden()
        .alert("Explore your reconstruction", isPresented: $showHelp) {
            Button("Got it", role: .cancel) { }
        } message: {
            Text("Move the iPad slowly until a floor or tabletop is detected. Tap the surface to place your terrain. Drag to move it, pinch to resize it and rotate with two fingers. Use Reset to remove it and scan again.\n\nThe initial size is a visualization scale; it does not convert a relative DSM into real-world metres.")
        }
    }

    private func control(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.subheadline.bold()).foregroundStyle(.primary)
                .padding(.horizontal, 18).padding(.vertical, 13).background(.regularMaterial, in: Capsule())
        }
    }
}

private struct ARSceneView: UIViewRepresentable {
    let modelURL: URL
    let resetToken: UUID
    @Binding var status: String

    func makeCoordinator() -> Coordinator { Coordinator(status: $status, resetToken: resetToken) }

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero)
        view.automaticallyConfigureSession = false
        context.coordinator.attach(to: view, modelURL: modelURL)
        context.coordinator.runSession()
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        if context.coordinator.lastResetToken != resetToken {
            context.coordinator.lastResetToken = resetToken
            context.coordinator.removeModel()
            context.coordinator.runSession(reset: true)
        }
    }

    static func dismantleUIView(_ uiView: ARView, coordinator: Coordinator) {
        uiView.session.pause()
    }

    @MainActor
    final class Coordinator: NSObject, @preconcurrency ARSessionDelegate {
        @Binding private var status: String
        weak var arView: ARView?
        private var modelURL: URL?
        private var modelTemplate: Entity?
        private var placedAnchor: AnchorEntity?
        var lastResetToken: UUID
        private var loadStarted = false

        init(status: Binding<String>, resetToken: UUID) {
            _status = status
            lastResetToken = resetToken
        }

        func attach(to view: ARView, modelURL: URL) {
            arView = view
            self.modelURL = modelURL
            view.session.delegate = self
            view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap(_:))))
            Task { await loadModel() }
        }

        func runSession(reset: Bool = false) {
            guard let view = arView else { return }
            guard ARWorldTrackingConfiguration.isSupported else {
                status = "This iPad does not support AR world tracking."
                return
            }
            let configuration = ARWorldTrackingConfiguration()
            configuration.planeDetection = [.horizontal]
            configuration.environmentTexturing = .automatic
            let options: ARSession.RunOptions = reset ? [.resetTracking, .removeExistingAnchors] : []
            view.session.run(configuration, options: options)
            status = "Move your iPad slowly to scan a floor or tabletop."
        }

        private func loadModel() async {
            guard !loadStarted, let modelURL else { return }
            loadStarted = true
            do {
                let entity = try await Entity(contentsOf: modelURL)
                modelTemplate = entity
                status = "Model ready. Tap a detected surface to place it."
            } catch {
                status = "Couldn't load the USDZ model: \(error.localizedDescription)"
            }
        }

        @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let view = arView, let modelTemplate else {
                status = "The model is still loading."
                return
            }
            let point = recognizer.location(in: view)
            let results = view.raycast(from: point, allowing: .estimatedPlane, alignment: .horizontal)
            guard let result = results.first else {
                status = "No horizontal surface found yet. Move the iPad slowly and try again."
                return
            }
            removeModel()
            let anchor = AnchorEntity(world: result.worldTransform)
            let movable = ModelEntity()
            movable.name = "DepthWizard AR Model"
            movable.addChild(modelTemplate.clone(recursive: true))
            normalizeForTabletop(movable)
            addSelectionCollider(to: movable)
            anchor.addChild(movable)
            view.scene.addAnchor(anchor)
            placedAnchor = anchor
            view.installGestures([.translation, .rotation, .scale], for: movable)
            status = "Placed! Drag to move, pinch to resize and rotate with two fingers."
        }

        func removeModel() {
            if let placedAnchor { arView?.scene.removeAnchor(placedAnchor) }
            placedAnchor = nil
        }

        private func normalizeForTabletop(_ entity: Entity) {
            let bounds = entity.visualBounds(relativeTo: nil)
            let extents = bounds.extents
            let largest = max(extents.x, max(extents.y, extents.z))
            guard largest.isFinite, largest > 0 else { return }
            let scale = 0.35 / largest
            entity.scale = SIMD3<Float>(repeating: scale)
            let scaledBounds = entity.visualBounds(relativeTo: nil)
            entity.position.y -= scaledBounds.min.y
        }

        private func addSelectionCollider(to entity: ModelEntity) {
            // One simple aggregate box keeps terrain hit-testing light, even when the
            // imported reconstruction contains a dense mesh hierarchy.
            let bounds = entity.visualBounds(relativeTo: entity)
            let extents = bounds.extents
            let size = SIMD3<Float>(max(extents.x, 0.01), max(extents.y, 0.01), max(extents.z, 0.01))
            let shape = ShapeResource.generateBox(size: size).offsetBy(translation: bounds.center)
            entity.components.set(CollisionComponent(shapes: [shape]))
        }

        func session(_ session: ARSession, didFailWithError error: Error) {
            Task { @MainActor in self.status = "AR session error: \(error.localizedDescription)" }
        }
        func sessionWasInterrupted(_ session: ARSession) {
            Task { @MainActor in self.status = "AR tracking paused. Return to the camera view to resume." }
        }
        func sessionInterruptionEnded(_ session: ARSession) { runSession(reset: true) }
    }
}
