import AppKit
import XCTest

final class ThreeMFModelTests: XCTestCase {
    // MARK: - Core 3MF

    func testCoreCubeGeometryAndBounds() throws {
        let mesh = try ThreeMFModel(url: fixture("core-cube.3mf")).buildMesh()
        XCTAssertEqual(mesh.triangleCount, 12)
        XCTAssertEqual(mesh.boundsMin, SIMD3(0, 0, 0))
        XCTAssertEqual(mesh.boundsMax, SIMD3(10, 10, 10))
    }

    func testCoreCubeMaterialColors() throws {
        // Object default is basematerials index 0 (red); triangle 0 overrides with p1=1 (green).
        let mesh = try ThreeMFModel(url: fixture("core-cube.3mf")).buildMesh()
        XCTAssertEqual(colorCounts(mesh), ["#FF0000": 11, "#00FF00": 1])
    }

    func testStoredAndDeflatedPackagesMatch() throws {
        let a = try ThreeMFModel(url: fixture("core-cube.3mf")).buildMesh()
        let b = try ThreeMFModel(url: fixture("core-cube-stored.3mf")).buildMesh()
        XCTAssertEqual(colorCounts(a), colorCounts(b))
        XCTAssertEqual(a.boundsMax, b.boundsMax)
    }

    func testThumbnailFromRelationship() throws {
        let data = try XCTUnwrap(ThreeMFModel(url: fixture("core-cube.3mf")).embeddedThumbnailData())
        let image = try XCTUnwrap(NSImage(data: data))
        XCTAssertEqual(image.size, NSSize(width: 4, height: 4))
    }

    // MARK: - Bambu Studio / OrcaSlicer

    func testBambuComponentsAndItemTransform() throws {
        let mesh = try ThreeMFModel(url: fixture("bambu-components.3mf")).buildMesh()
        XCTAssertEqual(mesh.triangleCount, 12)
        // The build item translates the 10 mm cube by (100, 50, 10).
        XCTAssertEqual(mesh.boundsMin, SIMD3(100, 50, 10))
        XCTAssertEqual(mesh.boundsMax, SIMD3(110, 60, 20))
    }

    func testBambuPaintAndObjectExtruderColors() throws {
        // Triangles 0-2 are painted filament 2 (green); the rest use the object's extruder 3 (blue).
        let mesh = try ThreeMFModel(url: fixture("bambu-components.3mf")).buildMesh()
        XCTAssertEqual(colorCounts(mesh), ["#22FF22": 3, "#3333FF": 9])
    }

    func testBambuPrefersPlateImageOverPickAndSmallImages() throws {
        let data = try XCTUnwrap(ThreeMFModel(url: fixture("bambu-components.3mf")).embeddedThumbnailData())
        let image = try XCTUnwrap(NSImage(data: data))
        XCTAssertEqual(image.size, NSSize(width: 8, height: 6))
    }

    // MARK: - PrusaSlicer

    func testPrusaVolumeRangesPaintAndColorFallback() throws {
        // Triangles 0-3: volume extruder 2, whose extruder_colour is empty, so filament_colour #0000FF.
        // Triangles 4-10: object extruder 1 (#FF0000). Triangle 11: mmu_segmentation paint 2 (#0000FF).
        let mesh = try ThreeMFModel(url: fixture("prusa-volumes.3mf")).buildMesh()
        XCTAssertEqual(colorCounts(mesh), ["#0000FF": 5, "#FF0000": 7])
    }

    func testPrusaWithoutEmbeddedImageHasNoThumbnail() throws {
        XCTAssertNil(try ThreeMFModel(url: fixture("prusa-volumes.3mf")).embeddedThumbnailData())
    }

    // MARK: - Errors

    func testNonZipThrows() throws {
        XCTAssertThrowsError(try ThreeMFModel(url: fixture("not-a-zip.3mf")))
    }
}
