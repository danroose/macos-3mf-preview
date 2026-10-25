import Cocoa
import Quartz
import SceneKit

/// Space-bar Quick Look preview: an interactive 3D view of the model (drag or two-finger swipe to orbit,
/// pinch to zoom). Also hosted by Finder's preview pane, where it spins on its own.
final class PreviewViewController: NSViewController, QLPreviewingController {
    private let sceneView = ModelView()
    private let status = NSTextField(labelWithString: "")

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        sceneView.translatesAutoresizingMaskIntoConstraints = false
        sceneView.backgroundColor = .clear
        sceneView.antialiasingMode = .multisampling4X
        sceneView.allowsCameraControl = true
        sceneView.defaultCameraController.interactionMode = .orbitTurntable
        sceneView.defaultCameraController.inertiaEnabled = true
        root.addSubview(sceneView)

        status.translatesAutoresizingMaskIntoConstraints = false
        status.textColor = .secondaryLabelColor
        status.font = .systemFont(ofSize: 11)
        status.lineBreakMode = .byTruncatingTail
        status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        root.addSubview(status)

        NSLayoutConstraint.activate([
            sceneView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            sceneView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            sceneView.topAnchor.constraint(equalTo: root.topAnchor),
            sceneView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            status.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10),
            status.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -10),
            status.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -8),
        ])
        view = root
        preferredContentSize = NSSize(width: 800, height: 600)
    }

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let mesh = try ThreeMFModel(url: url).buildMesh()
                guard !mesh.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
                let (scene, _) = SceneBuilder.scene(for: mesh)
                let caption = PreviewSummary.caption(for: mesh)
                DispatchQueue.main.async {
                    self.sceneView.scene = scene
                    self.sceneView.pointOfView = scene.rootNode.childNode(withName: "camera", recursively: false)
                    self.sceneView.defaultCameraController.target = SCNVector3Zero
                    self.status.stringValue = caption
                    self.sceneView.startAutoSpin()
                    handler(nil)
                }
            } catch {
                DispatchQueue.main.async { handler(error) }
            }
        }
    }
}
