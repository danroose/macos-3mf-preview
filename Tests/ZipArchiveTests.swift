import XCTest

final class ZipArchiveTests: XCTestCase {
    func testListsEntries() throws {
        let zip = try ZipArchive(url: fixture("core-cube.3mf"))
        XCTAssertEqual(Set(zip.names), ["[Content_Types].xml", "_rels/.rels", "3D/3dmodel.model", "Metadata/thumbnail.png"])
    }

    func testReadsDeflatedAndStoredEntriesIdentically() throws {
        let deflated = try ZipArchive(url: fixture("core-cube.3mf"))
        let stored = try ZipArchive(url: fixture("core-cube-stored.3mf"))
        XCTAssertEqual(deflated.entry(named: "3D/3dmodel.model")?.method, 8)
        XCTAssertEqual(stored.entry(named: "3D/3dmodel.model")?.method, 0)

        let a = try XCTUnwrap(deflated.read("3D/3dmodel.model"))
        let b = try XCTUnwrap(stored.read("3D/3dmodel.model"))
        XCTAssertEqual(a, b)
        XCTAssertTrue(String(decoding: a, as: UTF8.self).contains("<basematerials"))
    }

    func testLookupToleratesLeadingSlashAndCase() throws {
        let zip = try ZipArchive(url: fixture("core-cube.3mf"))
        XCTAssertNotNil(zip.entry(named: "/3D/3dmodel.model"))
        XCTAssertNotNil(zip.entry(named: "3d/3DMODEL.model"))
        XCTAssertTrue(zip.contains("/Metadata/thumbnail.png"))
        XCTAssertNil(try zip.read("does/not/exist"))
    }

    func testRejectsNonZipFile() throws {
        XCTAssertThrowsError(try ZipArchive(url: fixture("not-a-zip.3mf")))
    }
}
