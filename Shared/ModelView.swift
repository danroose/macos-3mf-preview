import SceneKit

/// SceneKit view for the preview. Adds two things on top of SCNView's built-in camera control:
///
/// - A slow turntable spin when the preview opens, so the model reads as 3D even where it can't be
///   dragged (Finder's preview pane turns a click-drag into a file drag). Any interaction stops it.
/// - Trackpad two-finger scrolling orbits the camera, since scroll events reach the view in places
///   where drags don't. A mouse wheel (no precise deltas) zooms instead.
final class ModelView: SCNView {
    static let spinKey = "autoSpin"
    /// Seconds per full turn of the auto-spin.
    static let spinPeriod: TimeInterval = 14
    /// Degrees of orbit per point of trackpad scroll.
    static let scrollRotationScale: Float = 0.35

    private(set) var isAutoSpinning = false

    private var modelNode: SCNNode? { scene?.rootNode.childNode(withName: SceneBuilder.modelNodeName, recursively: false) }

    func startAutoSpin() {
        guard let node = modelNode else { return }
        let turn = SCNAction.rotateBy(x: 0, y: .pi * 2, z: 0, duration: Self.spinPeriod)
        node.runAction(.repeatForever(turn), forKey: Self.spinKey)
        isAutoSpinning = true
    }

    func stopAutoSpin() {
        modelNode?.removeAction(forKey: Self.spinKey)
        isAutoSpinning = false
    }

    override func mouseDown(with event: NSEvent) {
        stopAutoSpin()
        super.mouseDown(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        stopAutoSpin()
        super.rightMouseDown(with: event)
    }

    override func magnify(with event: NSEvent) {
        stopAutoSpin()
        super.magnify(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        stopAutoSpin()
        guard allowsCameraControl else { return super.scrollWheel(with: event) }
        if event.hasPreciseScrollingDeltas {
            orbit(dx: Float(event.scrollingDeltaX), dy: Float(event.scrollingDeltaY))
        } else {
            super.scrollWheel(with: event)
        }
    }

    /// Orbits the camera around the model, like dragging. Positive dx swings the view to the left.
    func orbit(dx: Float, dy: Float) {
        defaultCameraController.rotateBy(x: dx * Self.scrollRotationScale, y: dy * Self.scrollRotationScale)
    }
}
