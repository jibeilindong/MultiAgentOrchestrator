import XCTest
@testable import Multi_Agent_Flow

final class AssistOrchestratorTests: XCTestCase {
    @MainActor
    func testWorkbenchAssistDraftPrefersSelectedNodeScopeAndInfersWorkflowIntent() {
        let appState = AppState()
        let project = makeProject()
        let workflow = project.workflows[0]
        let node = workflow.nodes[1]

        appState.currentProject = project
        appState.activeWorkflowID = workflow.id
        appState.selectedNodeID = node.id

        let draft = appState.makeWorkbenchAssistDraft(
            prompt: "请整理一下这个节点附近的布局",
            workflowID: workflow.id,
            preferredThreadID: "workbench-thread-1",
            isPreparingFreshThread: false,
            submitMode: .chat
        )

        XCTAssertEqual(draft.source, .workbenchAssist)
        XCTAssertEqual(draft.intent, .reorganizeWorkflow)
        XCTAssertEqual(draft.scopeType, .node)
        XCTAssertEqual(draft.workflowID, workflow.id)
        XCTAssertEqual(draft.nodeID, node.id)
        XCTAssertEqual(draft.threadID, "workbench-thread-1")
        XCTAssertEqual(draft.workspaceSurface, .draft)
    }

    @MainActor
    func testWorkbenchAssistDraftUsesReadonlySurfaceForPerformanceInspection() {
        let appState = AppState()
        let project = makeProject()
        let workflow = project.workflows[0]

        appState.currentProject = project
        appState.activeWorkflowID = workflow.id
        appState.selectedNodeID = nil

        let draft = appState.makeWorkbenchAssistDraft(
            prompt: "帮我分析一下当前 workflow 的性能瓶颈",
            workflowID: workflow.id,
            preferredThreadID: nil,
            isPreparingFreshThread: true,
            submitMode: .run
        )

        XCTAssertEqual(draft.intent, .inspectPerformance)
        XCTAssertEqual(draft.scopeType, .workflow)
        XCTAssertNil(draft.threadID)
        XCTAssertEqual(draft.workspaceSurface, .runtimeReadonly)
    }

    @MainActor
    func testWorkflowEditorAssistDraftUsesWorkflowSourceAndNoThreadBinding() {
        let appState = AppState()
        let project = makeProject()
        let workflow = project.workflows[0]
        let node = workflow.nodes[1]

        appState.currentProject = project
        appState.activeWorkflowID = workflow.id
        appState.selectedNodeID = node.id

        let draft = appState.makeWorkflowEditorAssistDraft(
            prompt: "请整理当前节点附近的布局并说明原因",
            workflowID: workflow.id
        )

        XCTAssertEqual(draft.source, .workflowNode)
        XCTAssertEqual(draft.invocationChannel, .workflow)
        XCTAssertEqual(draft.intent, .reorganizeWorkflow)
        XCTAssertEqual(draft.scopeType, .node)
        XCTAssertEqual(draft.workflowID, workflow.id)
        XCTAssertEqual(draft.nodeID, node.id)
        XCTAssertNil(draft.threadID)
        XCTAssertEqual(draft.workspaceSurface, .draft)
        XCTAssertEqual(draft.additionalMetadata["entrySurface"], "workflow_editor")
    }

    func testContextResolverCapturesProjectWorkflowNodeAndWorkbenchThreadHistory() {
        let project = makeProject()
        let workflow = project.workflows[0]
        let agent = project.agents[0]
        let node = workflow.nodes[1]
        let threadID = "workbench-thread-1"

        var message = Message(
            from: agent.id,
            to: agent.id,
            type: .text,
            content: "Please reorganize this workflow."
        )
        message.metadata[WorkbenchMetadataKey.channel] = "workbench"
        message.metadata[WorkbenchMetadataKey.workflowID] = workflow.id.uuidString
        message.metadata[WorkbenchMetadataKey.workbenchThreadID] = threadID
        message.metadata[WorkbenchMetadataKey.workbenchSessionID] = "session-1"
        message.metadata[WorkbenchMetadataKey.workbenchMode] = WorkbenchInteractionMode.chat.rawValue
        message.metadata["role"] = "user"

        var task = Task(title: "Reorganize workflow", assignedAgentID: agent.id)
        task.metadata[WorkbenchMetadataKey.workflowID] = workflow.id.uuidString
        task.metadata[WorkbenchMetadataKey.workbenchThreadID] = threadID
        task.metadata[WorkbenchMetadataKey.workbenchMode] = WorkbenchInteractionMode.run.rawValue

        let resolver = AssistContextResolver()
        let output = resolver.resolve(
            input: AssistContextResolver.Input(
                source: .workbenchAssist,
                intent: .reorganizeWorkflow,
                scopeType: .node,
                prompt: "整理一下当前节点及周边布局",
                workflowID: workflow.id,
                nodeID: node.id,
                threadID: threadID
            ),
            snapshot: AssistContextResolver.Snapshot(
                project: project,
                activeWorkflowID: workflow.id,
                selectedNodeID: node.id,
                messages: [message],
                tasks: [task]
            )
        )

        XCTAssertEqual(output.scopeRef.projectID, project.id)
        XCTAssertEqual(output.scopeRef.workflowID, workflow.id)
        XCTAssertEqual(output.scopeRef.nodeID, node.id)
        XCTAssertEqual(output.scopeRef.threadID, threadID)
        XCTAssertTrue(output.entries.contains(where: { $0.kind == .workflowLayout }))
        XCTAssertTrue(output.entries.contains(where: { $0.kind == .nodeMetadata }))
        XCTAssertTrue(output.entries.contains(where: { $0.kind == .runtimeSnapshot && $0.title == "Workbench Thread Snapshot" }))
        XCTAssertTrue(output.entries.contains(where: { $0.title == "Assist Guardrails" }))
    }

    func testOrchestratorPersistsSuggestionOnlyAssistSubmission() throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let project = makeProject()
        let workflow = project.workflows[0]
        let node = workflow.nodes[1]
        let fileSystem = AssistFileSystem()
        let store = AssistStore(fileSystem: fileSystem, appSupportRootDirectory: rootURL)
        let orchestrator = AssistOrchestrator(store: store)

        let result = try orchestrator.submit(
            AssistSubmissionInput(
                source: .inlineEditor,
                intent: .rewriteSelection,
                scopeType: .textSelection,
                prompt: "把这段模板说明改得更清晰",
                requestedAction: .applyToDraft,
                workflowID: workflow.id,
                nodeID: node.id,
                relativeFilePath: "Templates/agent.md",
                selectionStart: 0,
                selectionEnd: 18,
                workspaceSurface: .draft,
                selectedText: "原始模板内容",
                fileContent: "原始模板内容\n下一段内容"
            ),
            snapshot: AssistContextResolver.Snapshot(
                project: project,
                activeWorkflowID: workflow.id,
                selectedNodeID: node.id
            )
        )

        XCTAssertEqual(result.request.status, .awaitingConfirmation)
        XCTAssertEqual(result.request.scopeRef.projectID, project.id)
        XCTAssertEqual(result.proposal.status, .awaitingConfirmation)
        XCTAssertTrue(result.proposal.requiresConfirmation)
        XCTAssertEqual(result.proposal.changeItems.first?.target, .draftText)
        XCTAssertTrue(result.proposal.warnings.contains(where: { $0.contains("gloved") }))
        XCTAssertNotNil(result.contextPack.contentHash)
        XCTAssertEqual(store.request(withID: result.request.id)?.status, .awaitingConfirmation)
        XCTAssertEqual(store.contextPack(withID: result.contextPack.id)?.requestID, result.request.id)
        XCTAssertEqual(store.proposal(withID: result.proposal.id)?.requestID, result.request.id)
        XCTAssertEqual(store.thread(withID: result.thread.id)?.latestProposalID, result.proposal.id)

        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: fileSystem.threadDocumentURL(for: result.thread.id, under: rootURL).path
            )
        )
    }

    private func makeProject() -> MAProject {
        let planner = makeAgent(name: "Planner", identifier: "planner")

        let startNode = WorkflowNode(type: .start)
        var plannerNode = WorkflowNode(type: .agent)
        plannerNode.agentID = planner.id
        plannerNode.title = "规划-排版-1"
        plannerNode.position = CGPoint(x: 160, y: 80)

        var workflow = Workflow(name: "Assist Workflow")
        workflow.nodes = [startNode, plannerNode]
        workflow.edges = [WorkflowEdge(from: startNode.id, to: plannerNode.id)]

        var project = MAProject(name: "Assist Project")
        project.agents = [planner]
        project.workflows = [workflow]
        return project
    }

    private func makeAgent(name: String, identifier: String) -> Agent {
        var agent = Agent(name: name)
        agent.openClawDefinition.agentIdentifier = identifier
        return agent
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AssistOrchestratorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
