import XCTest
@testable import Multi_Agent_Flow

final class OpenClawProtocolGuidanceTests: XCTestCase {
    func testPlainStreamingGuidanceFiltersMachineTailHints() {
        let lines = [
            "Always end with exactly one valid routing JSON line when a machine tail is required.",
            "Before sending the final answer, validate the last non-empty line.",
            "Only choose downstream targets from the allowed candidate list."
        ]

        let filtered = OpenClawService.filteredProtocolGuidanceLines(
            lines,
            for: .plainStreaming
        )

        XCTAssertEqual(
            filtered,
            ["Only choose downstream targets from the allowed candidate list."]
        )
    }

    func testStructuredJSONGuidanceKeepsMachineTailHints() {
        let lines = [
            "Always end with exactly one valid routing JSON line when a machine tail is required.",
            "Only choose downstream targets from the allowed candidate list."
        ]

        let filtered = OpenClawService.filteredProtocolGuidanceLines(
            lines,
            for: .structuredJSON
        )

        XCTAssertEqual(filtered, lines)
    }

    func testPlainStreamingOutputContractDoesNotRequireRoutingJSON() {
        let contract = OpenClawService.protocolOutputContract(for: .plainStreaming)

        XCTAssertFalse(contract.requiredOutputContract.lowercased().contains("workflow_route"))
        XCTAssertTrue(contract.requiredOutputContract.lowercased().contains("do not append routing json"))
        XCTAssertFalse(contract.selfCheckRule.lowercased().contains("last non-empty line"))
    }

    func testPlainStreamingVisibleOutputStripsLegacyRoutingDirective() {
        let stdout = """
        这是给用户的直接回复。
        {"workflow_route":{"action":"selected","targets":["Reviewer"],"reason":"need help"}}
        """

        let parsed = OpenClawService.parsePlainStreamingVisibleOutput(from: stdout)

        XCTAssertEqual(parsed.text, "这是给用户的直接回复。")
        XCTAssertEqual(parsed.outputType, .agentFinalResponse)
    }

    func testPlainStreamingWorkbenchEntryCollaborationSectionDoesNotDispatchWorkflow() {
        let section = OpenClawService.workbenchEntryCollaborationSection(
            for: .plainStreaming,
            candidateLines: ["- Reviewer"],
            approvalLines: ["- Security"]
        )

        XCTAssertTrue(section.lowercased().contains("does not trigger workflow dispatch"))
        XCTAssertFalse(section.contains("Downstream Candidates"))
        XCTAssertTrue(section.contains("Available Specialists (Informational Only)"))
    }

    func testStructuredJSONWorkbenchEntryCollaborationSectionKeepsRoutingTargets() {
        let section = OpenClawService.workbenchEntryCollaborationSection(
            for: .structuredJSON,
            candidateLines: ["- Reviewer"],
            approvalLines: ["- Security"]
        )

        XCTAssertTrue(section.contains("Downstream Candidates"))
        XCTAssertTrue(section.contains("Approval-Required Downstream Agents"))
    }
}
