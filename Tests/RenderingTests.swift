import Metal
import SceneKit
import XCTest

final class SlicerSettingsTests: XCTestCase {
    func testParseHex() {
        XCTAssertEqual(SlicerSettings.parseHex("#FF0000").map(hex), "#FF0000")
        XCTAssertEqual(SlicerSettings.parseHex("00ff80").map(hex), "#00FF80")
        XCTAssertEqual(SlicerSettings.parseHex("#A3D8E1FF").map(hex), "#A3D8E1")
        XCTAssertNil(SlicerSettings.parseHex(""))
        XCTAssertNil(SlicerSettings.parseHex("#12345"))
        XCTAssertNil(SlicerSettings.parseHex("#GGGGGG"))
    }
}

final class SceneBuilderTests: XCTestCase {
    func testGeometryIsFlatShadedPerColorGroup() throws {
        let mesh = try ThreeMFModel(url: fixture("core-cube.3mf")).buildMesh()
        let (scene, radius) = SceneBuilder.scene(for: mesh)
        let geometry = try XCTUnwrap(scene.rootNode.childNodes.compactMap(\.geometry).first)

        XCTAssertEqual(geometry.elements.count, 2, "one element per color")
        XCTAssertEqual(geometry.materials.count, 2)
        XCTAssertEqual(geometry.sources(for: .vertex).first?.vectorCount, 36, "3 unshared vertices per triangle")
        XCTAssertEqual(geometry.sources(for: .normal).first?.vectorCount, 36)
        XCTAssertEqual(radius, sqrt(300) / 2, accuracy: 0.001)
    }

    func testModelIsCenteredAndCameraLooksAtIt() throws {
        let mesh = try ThreeMFModel(url: fixture("bambu-components.3mf")).buildMesh()
        let (scene, _) = SceneBuilder.scene(for: mesh)
        let node = try XCTUnwrap(scene.rootNode.childNodes.first { $0.geometry != nil })
        let (lo, hi) = node.boundingBox
        XCTAssertEqual(Float(lo.x + hi.x), 0, accuracy: 0.001)
        XCTAssertEqual(Float(lo.y + hi.y), 0, accuracy: 0.001)
        XCTAssertEqual(Float(lo.z + hi.z), 0, accuracy: 0.001)
        XCTAssertNotNil(scene.rootNode.childNode(withName: "camera", recursively: false)?.camera)
    }
}

final class SnapshotRendererTests: XCTestCase {
    func testRendersImageOfRequestedSize() throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal device")
        let mesh = try ThreeMFModel(url: fixture("core-cube.3mf")).buildMesh()
        let image = try XCTUnwrap(SnapshotRenderer.image(for: mesh, size: CGSize(width: 128, height: 128)))
        XCTAssertEqual(image.size, CGSize(width: 128, height: 128))
    }

    func testEmptyMeshRendersNothing() {
        XCTAssertNil(SnapshotRenderer.image(for: ColoredMesh(), size: CGSize(width: 64, height: 64)))
    }
}
