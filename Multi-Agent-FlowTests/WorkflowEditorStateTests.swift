import XCTest
@testable import Multi_Agent_Flow

final class WorkflowEditorStateTests: XCTestCase {
    func testUpdateNodeKeepsAgentNodeTitleAlignedWithAgentName() {
        let appState = AppState()
        var project = MAProject(name: "Agent Title Sync")
        let agent = Agent(name: "planner-task-1")
        project.agents = [agent]

        var workflow = project.workflows[0]
        var node = WorkflowNode(type: .agent)
        node.agentID = agent.id
        node.title = "custom-node-title"
        workflow.nodes = [node]
        project.workflows = [workflow]
        appState.currentProject = project

        appState.updateNode(node.id) { updatedNode in
            updatedNode.title = "another-custom-title"
        }

        XCTAssertEqual(appState.currentProject?.workflows.first?.nodes.first?.title, agent.name)
    }

    func testUpdateAgentRefreshesBoundNodeTitleToAgentName() {
        let appState = AppState()
        var project = MAProject(name: "Agent Rename Sync")
        var agent = Agent(name: "planner-task-1")
        project.agents = [agent]

        var workflow = project.workflows[0]
        var node = WorkflowNode(type: .agent)
        node.agentID = agent.id
        node.title = agent.name
        workflow.nodes = [node]
        project.workflows = [workflow]
        appState.currentProject = project

        agent.name = "reviewer-task-1"
        appState.updateAgent(agent)

        XCTAssertEqual(appState.currentProject?.workflows.first?.nodes.first?.title, "reviewer-task-1")
    }
}
