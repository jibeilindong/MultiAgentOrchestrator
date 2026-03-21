import XCTest
@testable import Multi_Agent_Flow

final class NodeDisplayPartsTests: XCTestCase {
    func testParseThreeSegmentsKeepsTopDownOrder() {
        let parts = NodeDisplayParts.parse(from: "规划-研发-3")

        XCTAssertEqual(parts.primary, "规划")
        XCTAssertEqual(parts.secondary, "研发")
        XCTAssertEqual(parts.sequence, "3")
    }

    func testParseSingleSegmentFallsBackGracefully() {
        let parts = NodeDisplayParts.parse(from: "协调节点")

        XCTAssertEqual(parts.primary, "协调节点")
        XCTAssertNil(parts.secondary)
        XCTAssertNil(parts.sequence)
    }

    func testParseIgnoresWhitespaceAroundSegments() {
        let parts = NodeDisplayParts.parse(from: "  协调  -  工作流  -  12  ")

        XCTAssertEqual(parts.primary, "协调")
        XCTAssertEqual(parts.secondary, "工作流")
        XCTAssertEqual(parts.sequence, "12")
    }
}
