import XCTest

/// Paint strings are hex nibbles read from the end. Leaf nibble: state in the top two bits,
/// 0 in the bottom two; state 3 means "read the next nibble and add 3". Split nibble: the
/// bottom two bits give split sides, followed by (sides + 1) children.
final class PaintDecoderTests: XCTestCase {
    private func state(_ s: String) -> Int { s.withCString { PaintDecoder.dominantState($0) } }

    func testUnpaintedAndEmpty() {
        XCTAssertEqual(state(""), 0)
        XCTAssertEqual(state("0"), 0)
    }

    func testSingleLeafStates() {
        XCTAssertEqual(state("4"), 1)
        XCTAssertEqual(state("8"), 2)
    }

    func testExtendedStates() {
        XCTAssertEqual(state("0C"), 3)
        XCTAssertEqual(state("1C"), 4)
        XCTAssertEqual(state("5C"), 8)
    }

    func testSplitTrianglePicksMajorityByArea() {
        // Four children (split sides = 3): states 2, 2, 2, 1.
        XCTAssertEqual(state("48883"), 2)
        // Two children (split sides = 1): one painted 1, one split again into four mostly-2 children.
        // Reading order: [1, 4, 3, 8, 8, 8, 4] -> child A = 1 (weight 1/2), child B = 2,2,2,1 (1/8 each).
        XCTAssertEqual(state("4888341"), 1)
    }

    func testLowercaseHexAndTerminatingQuote() {
        XCTAssertEqual(state("0c"), 3)
        // The scanner hands the decoder a pointer into XML, so a closing quote ends the value.
        XCTAssertEqual(state("8\" v1=\"4"), 2)
    }

    func testRejectsGarbage() {
        XCTAssertEqual(state("zz"), 0)
    }
}
