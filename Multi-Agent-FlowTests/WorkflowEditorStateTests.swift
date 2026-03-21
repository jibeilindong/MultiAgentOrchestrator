import XCTest
@testable import Multi_Agent_Flow

final class WorkflowEditorStateTests: XCTestCase {
    func testUpdateNodeKeepsAgentNodeTitleAlignedWithAgentName() {
        var project = MAProject(name: "Agent Title Sync")
        let agent = Agent(name: "planner-task-1")
        project.agents = [agent]

        var workflow = project.workflows[0]
        var node = WorkflowNode(type: .agent)
        node.agentID = agent.id
        node.title = "custom-node-title"
        workflow.nodes = [node]
        project.workflows = [workflow]
        let normalizedProject = AppState.normalizeProjectNaming(project)

        XCTAssertEqual(normalizedProject.workflows.first?.nodes.first?.title, agent.name)
    }

    func testUpdateAgentRefreshesBoundNodeTitleToAgentName() {
        var project = MAProject(name: "Agent Rename Sync")
        var agent = Agent(name: "planner-task-1")
        project.agents = [agent]

        var workflow = project.workflows[0]
        var node = WorkflowNode(type: .agent)
        node.agentID = agent.id
        node.title = agent.name
        workflow.nodes = [node]
        project.workflows = [workflow]

        agent.name = "reviewer-task-1"
        project.agents = [agent]
        let normalizedProject = AppState.normalizeProjectNaming(project)

        XCTAssertEqual(normalizedProject.workflows.first?.nodes.first?.title, "reviewer-task-1")
    }

    func testNormalizeProjectNamingKeepsNonAgentNodeTitlesEditable() {
        var project = MAProject(name: "Mixed Node Titles")
        let agent = Agent(name: "planner-task-1")
        project.agents = [agent]

        var workflow = project.workflows[0]
        var startNode = WorkflowNode(type: .start)
        startNode.title = "custom-start-title"

        var agentNode = WorkflowNode(type: .agent)
        agentNode.agentID = agent.id
        agentNode.title = "custom-agent-title"

        workflow.nodes = [startNode, agentNode]
        project.workflows = [workflow]

        let normalizedProject = AppState.normalizeProjectNaming(project)
        let normalizedNodes = normalizedProject.workflows.first?.nodes ?? []
        let expectedStartTitle = WorkflowNode.normalizedTitle(
            requestedTitle: "custom-start-title",
            nodeType: .start,
            existingNodes: [],
            excludingNodeID: startNode.id
        )

        XCTAssertEqual(normalizedNodes.first(where: { $0.id == startNode.id })?.title, expectedStartTitle)
        XCTAssertEqual(normalizedNodes.first(where: { $0.id == agentNode.id })?.title, agent.name)
    }

    func testNormalizeProjectNamingRenamesDuplicateAgentsAndRebindsNodeTitles() {
        var project = MAProject(name: "Duplicate Agent Names")
        let firstAgent = Agent(name: "planner")
        let secondAgent = Agent(name: "planner")
        project.agents = [firstAgent, secondAgent]

        var workflow = project.workflows[0]
        var firstNode = WorkflowNode(type: .agent)
        firstNode.agentID = firstAgent.id
        firstNode.title = "first-custom"

        var secondNode = WorkflowNode(type: .agent)
        secondNode.agentID = secondAgent.id
        secondNode.title = "second-custom"

        workflow.nodes = [firstNode, secondNode]
        project.workflows = [workflow]

        let normalizedProject = AppState.normalizeProjectNaming(project)
        let normalizedAgents = normalizedProject.agents
        let normalizedNodes = normalizedProject.workflows.first?.nodes ?? []

        XCTAssertEqual(normalizedAgents.count, 2)
        XCTAssertNotEqual(normalizedAgents[0].name, normalizedAgents[1].name)
        XCTAssertEqual(
            normalizedNodes.first(where: { $0.id == firstNode.id })?.title,
            normalizedAgents.first(where: { $0.id == firstAgent.id })?.name
        )
        XCTAssertEqual(
            normalizedNodes.first(where: { $0.id == secondNode.id })?.title,
            normalizedAgents.first(where: { $0.id == secondAgent.id })?.name
        )
    }
}
