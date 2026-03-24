import XCTest
@testable import Multi_Agent_Flow

final class QuickChatContextResolutionTests: XCTestCase {
    private static let sharedStore = QuickChatStore()

    @MainActor
    func testResolveQuickChatContextPrefersEntryConnectedAgent() {
        let appState = makeAppState()
        let planner = makeAgent(name: "Planner", identifier: "planner")
        let reviewer = makeAgent(name: "Reviewer", identifier: "reviewer")

        let startNode = WorkflowNode(type: .start)
        var plannerNode = WorkflowNode(type: .agent)
        plannerNode.agentID = planner.id
        plannerNode.position = CGPoint(x: 120, y: 80)

        var reviewerNode = WorkflowNode(type: .agent)
        reviewerNode.agentID = reviewer.id
        reviewerNode.position = CGPoint(x: 120, y: 20)

        var workflow = Workflow(name: "Main Workflow")
        workflow.nodes = [startNode, reviewerNode, plannerNode]
        workflow.edges = [WorkflowEdge(from: startNode.id, to: plannerNode.id)]

        var project = MAProject(name: "Quick Chat Project")
        project.agents = [planner, reviewer]
        project.workflows = [workflow]

        appState.currentProject = project
        appState.activeWorkflowID = workflow.id

        let context = appState.resolveQuickChatContext()

        XCTAssertEqual(context?.workflowID, workflow.id)
        XCTAssertEqual(context?.entryAgentID, planner.id)
        XCTAssertEqual(context?.entryAgentName, planner.name)
        XCTAssertEqual(context?.agentIdentifier, "planner")
    }

    @MainActor
    func testResolveQuickChatContextFallsBackToFirstAgentNodeWhenNoEntryConnectionExists() {
        let appState = makeAppState()
        let analyst = makeAgent(name: "Analyst", identifier: "analyst")
        let summarizer = makeAgent(name: "Summarizer", identifier: "summarizer")

        var analystNode = WorkflowNode(type: .agent)
        analystNode.agentID = analyst.id
        analystNode.position = CGPoint(x: 80, y: 20)

        var summarizerNode = WorkflowNode(type: .agent)
        summarizerNode.agentID = summarizer.id
        summarizerNode.position = CGPoint(x: 80, y: 120)

        var workflow = Workflow(name: "Fallback Workflow")
        workflow.nodes = [summarizerNode, analystNode]
        workflow.edges = []

        var project = MAProject(name: "Fallback Project")
        project.agents = [summarizer, analyst]
        project.workflows = [workflow]

        appState.currentProject = project
        appState.activeWorkflowID = workflow.id

        let context = appState.resolveQuickChatContext()

        XCTAssertEqual(context?.entryAgentID, analyst.id)
        XCTAssertEqual(context?.agentIdentifier, "analyst")
    }

    @MainActor
    func testQuickChatStoreCreatesFreshSessionForNewSessionAction() {
        let appState = makeAppState()
        let planner = makeAgent(name: "Planner", identifier: "planner")

        let startNode = WorkflowNode(type: .start)
        var plannerNode = WorkflowNode(type: .agent)
        plannerNode.agentID = planner.id

        var workflow = Workflow(name: "Session Workflow")
        workflow.nodes = [startNode, plannerNode]
        workflow.edges = [WorkflowEdge(from: startNode.id, to: plannerNode.id)]

        var project = MAProject(name: "Session Project")
        project.agents = [planner]
        project.workflows = [workflow]

        appState.currentProject = project
        appState.activeWorkflowID = workflow.id

        let store = Self.sharedStore
        store.present(using: appState)
        store.startNewSession()
        let firstSessionKey = store.sessionKey

        store.startNewSession()
        let secondSessionKey = store.sessionKey

        XCTAssertFalse(firstSessionKey.isEmpty)
        XCTAssertFalse(secondSessionKey.isEmpty)
        XCTAssertNotEqual(firstSessionKey, secondSessionKey)
        XCTAssertTrue(store.messages.isEmpty)
    }

    @MainActor
    func testResolveQuickChatAgentOptionsOrdersEntryAgentFirst() {
        let appState = makeAppState()
        let planner = makeAgent(name: "Planner", identifier: "planner")
        let reviewer = makeAgent(name: "Reviewer", identifier: "reviewer")

        let startNode = WorkflowNode(type: .start)
        var plannerNode = WorkflowNode(type: .agent)
        plannerNode.agentID = planner.id
        plannerNode.position = CGPoint(x: 120, y: 80)

        var reviewerNode = WorkflowNode(type: .agent)
        reviewerNode.agentID = reviewer.id
        reviewerNode.position = CGPoint(x: 120, y: 20)

        var workflow = Workflow(name: "Agent Options Workflow")
        workflow.nodes = [startNode, reviewerNode, plannerNode]
        workflow.edges = [WorkflowEdge(from: startNode.id, to: plannerNode.id)]

        var project = MAProject(name: "Agent Options Project")
        project.agents = [planner, reviewer]
        project.workflows = [workflow]

        appState.currentProject = project
        appState.activeWorkflowID = workflow.id

        let options = appState.resolveQuickChatAgentOptions()

        XCTAssertEqual(options.map(\.agentID), [planner.id, reviewer.id])
        XCTAssertEqual(options.first?.agentIdentifier, "planner")
        XCTAssertEqual(options.first?.isEntryPreferred, true)
        XCTAssertEqual(options.last?.isEntryPreferred, false)
    }

    @MainActor
    func testQuickChatStoreSwitchesSessionWhenAgentSelectionChanges() {
        let appState = makeAppState()
        let planner = makeAgent(name: "Planner", identifier: "planner")
        let reviewer = makeAgent(name: "Reviewer", identifier: "reviewer")

        let startNode = WorkflowNode(type: .start)
        var plannerNode = WorkflowNode(type: .agent)
        plannerNode.agentID = planner.id
        plannerNode.position = CGPoint(x: 120, y: 80)

        var reviewerNode = WorkflowNode(type: .agent)
        reviewerNode.agentID = reviewer.id
        reviewerNode.position = CGPoint(x: 120, y: 20)

        var workflow = Workflow(name: "Switch Workflow")
        workflow.nodes = [startNode, reviewerNode, plannerNode]
        workflow.edges = [WorkflowEdge(from: startNode.id, to: plannerNode.id)]

        var project = MAProject(name: "Switch Project")
        project.agents = [planner, reviewer]
        project.workflows = [workflow]

        appState.currentProject = project
        appState.activeWorkflowID = workflow.id

        let store = Self.sharedStore
        store.present(using: appState)
        store.startNewSession()
        let initialSessionKey = store.sessionKey

        store.selectAgent(reviewer.id, using: appState)

        XCTAssertEqual(store.context?.entryAgentID, reviewer.id)
        XCTAssertEqual(store.context?.agentIdentifier, "reviewer")
        XCTAssertNotEqual(store.sessionKey, initialSessionKey)
    }

    @MainActor
    private func makeAppState() -> AppState {
        AppState()
    }

    private func makeAgent(name: String, identifier: String) -> Agent {
        var agent = Agent(name: name)
        agent.openClawDefinition.agentIdentifier = identifier
        return agent
    }
}
