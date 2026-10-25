import Foundation
import XCTest

final class FixtureLocator {}

/// URL of a file in Tests/Fixtures (copied into the test bundle as a folder reference).
func fixture(_ name: String, file: StaticString = #filePath, line: UInt = #line) throws -> URL {
    let bundle = Bundle(for: FixtureLocator.self)
    let url = try XCTUnwrap(bundle.url(forResource: "Fixtures", withExtension: nil), file: file, line: line)
        .appendingPathComponent(name)
    XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "missing fixture \(name)", file: file, line: line)
    return url
}

/// Hex form of a mesh color, e.g. "#FF0000", for readable assertions.
func hex(_ c: SIMD4<Float>) -> String {
    String(format: "#%02X%02X%02X", Int((c.x * 255).rounded()), Int((c.y * 255).rounded()), Int((c.z * 255).rounded()))
}

/// Triangle count per color, keyed by hex.
func colorCounts(_ mesh: ColoredMesh) -> [String: Int] {
    var out: [String: Int] = [:]
    for (color, verts) in mesh.groups { out[hex(color), default: 0] += verts.count / 3 }
    return out
}
