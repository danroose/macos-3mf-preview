import SceneKit
import Metal

enum SnapshotRenderer {
    /// Renders the model offscreen, used for thumbnails when the file has no embedded preview image.
    static func image(for mesh: ColoredMesh, size: CGSize) -> NSImage? {
        guard !mesh.isEmpty, let device = MTLCreateSystemDefaultDevice() else { return nil }
        let (scene, _) = SceneBuilder.scene(for: mesh)
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = scene
        renderer.pointOfView = scene.rootNode.childNode(withName: "camera", recursively: false)
        renderer.autoenablesDefaultLighting = false
        scene.background.contents = NSColor.clear
        return renderer.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)
    }
}
