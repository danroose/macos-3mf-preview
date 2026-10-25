import SceneKit
import XCTest

final class ModelViewTests: XCTestCase {
    private func makeView() throws -> (ModelView, SCNNode) {
        let mesh = try ThreeMFModel(url: fixture("core-cube.3mf")).buildMesh()
        let (scene, _) = SceneBuilder.scene(for: mesh)
        let view = ModelView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        view.allowsCameraControl = true
        view.scene = scene
        view.pointOfView = scene.rootNode.childNode(withName: "camera", recursively: false)
        let model = try XCTUnwrap(scene.rootNode.childNode(withName: SceneBuilder.modelNodeName, recursively: false))
        return (view, model)
    }

    func testAutoSpinRunsOnModelNode() throws {
        let (view, model) = try makeView()
        view.startAutoSpin()
        XCTAssertTrue(view.isAutoSpinning)
        XCTAssertNotNil(model.action(forKey: ModelView.spinKey))
    }

    func testStopAutoSpinRemovesAction() throws {
        let (view, model) = try makeView()
        view.startAutoSpin()
        view.stopAutoSpin()
        XCTAssertFalse(view.isAutoSpinning)
        XCTAssertNil(model.action(forKey: ModelView.spinKey))
    }

    func testTrackpadScrollStopsSpinAndOrbitsCamera() throws {
        let (view, _) = try makeView()
        view.startAutoSpin()
        let camera = try XCTUnwrap(view.pointOfView)
        let before = camera.simdWorldPosition

        // A continuous (trackpad) scroll event, which reports precise deltas.
        let cg = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: 0, wheel2: 40, wheel3: 0))
        cg.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        let event = try XCTUnwrap(NSEvent(cgEvent: cg))
        XCTAssertTrue(event.hasPreciseScrollingDeltas)

        view.scrollWheel(with: event)
        XCTAssertFalse(view.isAutoSpinning)
        XCTAssertGreaterThan(simd_distance(before, camera.simdWorldPosition), 0.01, "camera should have orbited")
    }

    func testOrbitKeepsDistanceToModel() throws {
        let (view, _) = try makeView()
        let camera = try XCTUnwrap(view.pointOfView)
        let distance = simd_length(camera.simdWorldPosition)
        view.orbit(dx: 60, dy: 20)
        XCTAssertEqual(simd_length(camera.simdWorldPosition), distance, accuracy: distance * 0.01)
    }
}
