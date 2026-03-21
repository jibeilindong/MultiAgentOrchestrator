import XCTest
@testable import Multi_Agent_Flow

final class WorkflowNodeDeletionProtectionTests: XCTestCase {
    func testUndeletableNodeIDsProtectStartNodeFromMixedDeletionSelection() {
        var workflow = Workflow(name: "Deletion Guard")
        let startNode = WorkflowNode(type: .start)
        let agentNode = WorkflowNode(type: .agent)
        workflow.nodes = [startNode, agentNode]

        let undeletableNodeIDs = AppState.undeletableNodeIDs(in: workflow, from: [startNode.id, agentNode.id])
        let removableNodeIDs = Set([startNode.id, agentNode.id]).subtracting(undeletableNodeIDs)

        XCTAssertEqual(undeletableNodeIDs, Set([startNode.id]))
        XCTAssertEqual(removableNodeIDs, Set([agentNode.id]))
    }

    func testUndeletableNodeIDsReturnsStartNodeWhenOnlyStartNodeIsSelected() {
        var workflow = Workflow(name: "Start Only")
        let startNode = WorkflowNode(type: .start)
        workflow.nodes = [startNode]

        let undeletableNodeIDs = AppState.undeletableNodeIDs(in: workflow, from: [startNode.id])

        XCTAssertEqual(undeletableNodeIDs, Set([startNode.id]))
    }
}
