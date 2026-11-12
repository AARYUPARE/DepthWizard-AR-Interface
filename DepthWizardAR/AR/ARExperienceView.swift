import SwiftUI
import RealityKit
import ARKit
import UIKit
import Combine

struct ARExperienceView: View {
    let storedProject: StoredProject
    @Environment(\.dismiss) private var dismiss
    @State private var status = "Move your iPad slowly to find a surface."
    @State private var showHelp = false
    @State private var resetToken = UUID()
    @State private var showAllMeasurements = false
    @State private var selectedMeasurement: TerrainMeasurement?

    private var measurements: [TerrainMeasurement] {
        storedProject.project.measurements ?? []
    }

    var body: some View {
        ZStack {
            ARSceneView(
                modelURL: storedProject.folderURL.appendingPathComponent(storedProject.project.modelFile),
                resetToken: resetToken,
                measurements: measurements,
                showAllMeasurements: showAllMeasurements,
                selectedMeasurement: $selectedMeasurement,
                status: $status
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .padding(12)
                            .background(.regularMaterial, in: Circle())
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(storedProject.project.name).font(.subheadline.bold())
                        Text("DEPTHWIZARD AR")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(1.4)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(.regularMaterial, in: Capsule())
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)

                Spacer()

                VStack(spacing: 12) {
                    if let selectedMeasurement {
                        measurementCard(selectedMeasurement)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    Text(status)
                        .font(.subheadline.weight(.medium))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(.regularMaterial, in: Capsule())

                    HStack(spacing: 10) {
                        if !measurements.isEmpty {
                            control(
                                showAllMeasurements ? "Featured pins" : "All pins",
                                icon: "mappin.and.ellipse"
                            ) {
                                showAllMeasurements.toggle()
                            }
                        }
                        control("Reset", icon: "arrow.counterclockwise") {
                            selectedMeasurement = nil
                            resetToken = UUID()
                        }
                        control("Instructions", icon: "questionmark.circle") {
                            showHelp = true
                        }
                    }
                }
                .padding(18)
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: selectedMeasurement)
        .statusBarHidden()
        .alert("Explore your reconstruction", isPresented: $showHelp) {
            Button("Got it", role: .cancel) { }
        } message: {
            Text(
                "Move the iPad slowly until a floor or tabletop is detected. Tap the surface to place your terrain. Drag to move it, pinch to resize it and rotate with two fingers. Tap a measurement pin to inspect its source value. Use the pin control to show featured or all measurements.\n\nThe initial size is a visualization scale; it does not convert a relative DSM into real-world metres."
            )
        }
    }

    private func measurementCard(_ measurement: TerrainMeasurement) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(measurement.label)
                        .font(.headline)
                    Text(measurement.type.uppercased() + " · " + measurement.source)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    selectedMeasurement = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }

            Text(measurement.displayValue)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .monospacedDigit()

            if measurement.units == "relative" {
                Text("Relative elevation · not a metric height")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }

            HStack(spacing: 14) {
                detailValue("Raster pixel", "((measurement.pixelX), (measurement.pixelY))")
                detailValue("Terrain position", measurement.normalizedPosition.displayString)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func detailValue(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.caption.monospaced()).lineLimit(1).minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func control(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.subheadline.bold())
                .foregroundStyle(.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                .background(.regularMaterial, in: Capsule())
        }
    }
}

private extension TerrainMeasurementPosition {
    var displayString: String {
        "x \(x.formatted(.number.precision(.fractionLength(2))))  " +
        "y \(y.formatted(.number.precision(.fractionLength(2))))  " +
        "z \(z.formatted(.number.precision(.fractionLength(2))))"
    }
}

private struct ARSceneView: UIViewRepresentable {
    let modelURL: URL
    let resetToken: UUID
    let measurements: [TerrainMeasurement]
    let showAllMeasurements: Bool
    @Binding var selectedMeasurement: TerrainMeasurement?
    @Binding var status: String

    func makeCoordinator() -> Coordinator {
        Coordinator(
            status: $status,
            selectedMeasurement: $selectedMeasurement,
            resetToken: resetToken,
            measurements: measurements,
            showAllMeasurements: showAllMeasurements
        )
    }

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero)
        view.automaticallyConfigureSession = false
        context.coordinator.attach(to: view, modelURL: modelURL)
        context.coordinator.runSession()
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.measurements = measurements
        context.coordinator.showAllMeasurements = showAllMeasurements
        context.coordinator.refreshMeasurementPins()

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
        @Binding private var selectedMeasurement: TerrainMeasurement?
        weak var arView: ARView?
        private var modelURL: URL?
        private var modelTemplate: Entity?
        private var placedAnchor: AnchorEntity?
        private var placedTerrain: ModelEntity?
        private var measurementRoot: Entity?
        var measurements: [TerrainMeasurement]
        var showAllMeasurements: Bool
        var lastResetToken: UUID
        private var loadStarted = false
        private var modelLoadCancellable: AnyCancellable?

        init(
            status: Binding<String>,
            selectedMeasurement: Binding<TerrainMeasurement?>,
            resetToken: UUID,
            measurements: [TerrainMeasurement],
            showAllMeasurements: Bool
        ) {
            _status = status
            _selectedMeasurement = selectedMeasurement
            lastResetToken = resetToken
            self.measurements = measurements
            self.showAllMeasurements = showAllMeasurements
        }

        func attach(to view: ARView, modelURL: URL) {
            arView = view
            self.modelURL = modelURL
            view.session.delegate = self
            view.addGestureRecognizer(
                UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            )
            loadModel()
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

        private func loadModel() {
            guard !loadStarted, let modelURL else { return }
            loadStarted = true

            modelLoadCancellable = Entity.loadAsync(contentsOf: modelURL)
                .receive(on: DispatchQueue.main)
                .sink(receiveCompletion: { [weak self] completion in
                    guard case .failure(let error) = completion else { return }
                    Task { @MainActor [weak self] in
                        self?.status = "Couldn't load the USDZ model: \(error.localizedDescription)"
                    }
                }, receiveValue: { [weak self] entity in
                    Task { @MainActor [weak self] in
                        self?.modelTemplate = entity
                        self?.status = "Model ready. Tap a detected surface to place it."
                    }
                })
        }

        @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let view = arView else { return }
            let point = recognizer.location(in: view)

            if let hit = view.entity(at: point), let identifier = measurementID(for: hit),
               let measurement = measurements.first(where: { $0.id == identifier }) {
                selectedMeasurement = measurement
                status = "Selected \(measurement.label)."
                return
            }

            selectedMeasurement = nil
            guard let modelTemplate else {
                status = "The model is still loading."
                return
            }

            let results = view.raycast(
                from: point,
                allowing: .estimatedPlane,
                alignment: .horizontal
            )
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
            placedTerrain = movable
            view.installGestures([.translation, .rotation, .scale], for: movable)
            refreshMeasurementPins()

            status = measurements.isEmpty
                ? "Placed! Drag to move, pinch to resize and rotate with two fingers."
                : "Placed! Tap a measurement pin to inspect its value."
        }

        func removeModel() {
            if let placedAnchor { arView?.scene.removeAnchor(placedAnchor) }
            placedAnchor = nil
            placedTerrain = nil
            measurementRoot = nil
        }

        func refreshMeasurementPins() {
            measurementRoot?.removeFromParent()
            measurementRoot = nil
            guard let terrain = placedTerrain else { return }

            let validMeasurements = measurements.filter { $0.normalizedPosition.isValid }
            let visibleMeasurements = showAllMeasurements
                ? validMeasurements
                : validMeasurements.filter(\.featured)
            guard !visibleMeasurements.isEmpty else { return }

            // The pin container is a child of the same movable entity as the terrain.
            // Its normalized coordinates therefore inherit exactly the terrain's AR transform.
            let bounds = terrain.visualBounds(relativeTo: terrain)
            let minimum = bounds.min
            let size = bounds.extents
            let root = Entity()
            root.name = "DepthWizardMeasurementPins"

            for measurement in visibleMeasurements {
                let p = measurement.normalizedPosition
                let pin = ModelEntity(
                    mesh: .generateSphere(radius: 0.008),
                    materials: [UnlitMaterial(color: measurement.featured ? .systemBlue : .systemTeal)]
                )
                pin.name = "dw-measurement-pin-\(measurement.id)"
                pin.position = SIMD3<Float>(
                    minimum.x + Float(p.x) * size.x,
                    minimum.y + Float(p.y) * size.y + 0.012,
                    minimum.z + Float(p.z) * size.z
                )
                pin.components.set(
                    CollisionComponent(shapes: [.generateSphere(radius: 0.018)])
                )
                root.addChild(pin)

                let labelMesh = MeshResource.generateText(
                    measurement.displayValue,
                    extrusionDepth: 0.0005,
                    font: .systemFont(ofSize: 0.035, weight: .bold),
                    containerFrame: .zero,
                    alignment: .center,
                    lineBreakMode: .byClipping
                )
                let label = ModelEntity(
                    mesh: labelMesh,
                    materials: [UnlitMaterial(color: .white)]
                )
                label.name = "dw-measurement-label-\(measurement.id)"
                label.position = pin.position + SIMD3<Float>(0, 0.025, 0)
                label.scale = SIMD3<Float>(repeating: 0.35)
                root.addChild(label)
            }

            terrain.addChild(root)
            measurementRoot = root
        }

        private func measurementID(for entity: Entity) -> String? {
            var current: Entity? = entity
            while let candidate = current {
                if candidate.name.hasPrefix("dw-measurement-pin-") {
                    return String(candidate.name.dropFirst("dw-measurement-pin-".count))
                }
                current = candidate.parent
            }
            return nil
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
            let size = SIMD3<Float>(
                max(extents.x, 0.01),
                max(extents.y, 0.01),
                max(extents.z, 0.01)
            )
            let shape = ShapeResource.generateBox(size: size)
                .offsetBy(translation: bounds.center)
            entity.components.set(CollisionComponent(shapes: [shape]))
        }

        func session(_ session: ARSession, didFailWithError error: Error) {
            Task { @MainActor in self.status = "AR session error: \(error.localizedDescription)" }
        }

        func sessionWasInterrupted(_ session: ARSession) {
            Task { @MainActor in self.status = "AR tracking paused. Return to the camera view to resume." }
        }

        func sessionInterruptionEnded(_ session: ARSession) {
            runSession(reset: true)
        }
    }
}
