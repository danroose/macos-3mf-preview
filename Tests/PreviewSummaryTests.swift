import XCTest

final class PreviewSummaryTests: XCTestCase {
    func testCaptionForFixture() throws {
        let mesh = try ThreeMFModel(url: fixture("core-cube.3mf")).buildMesh()
        XCTAssertEqual(PreviewSummary.caption(for: mesh), "10.0 × 10.0 × 10.0 mm · 12 triangles")
    }

    func testMillimetersDropDecimalsForLargeSizes() {
        XCTAssertEqual(PreviewSummary.millimeters(9.94), "9.9")
        XCTAssertEqual(PreviewSummary.millimeters(239.2), "239")
    }

    func testTriangleCountIsAbbreviated() {
        XCTAssertEqual(PreviewSummary.count(999), "999")
        XCTAssertEqual(PreviewSummary.count(6_364), "6.4K")
        XCTAssertEqual(PreviewSummary.count(500_474), "500K")
        XCTAssertEqual(PreviewSummary.count(1_289_182), "1.3M")
    }
}
