import XCTest
@testable import Multi_Agent_Flow

final class OpsCenterSnapshotBuilderTests: XCTestCase {
    func testBuildRouteInvestigationFocusesOnDirectRouteTraffic() throws {
        var project = MAProject(name: "Ops Center Route Test")

        let planner = Agent(name: "规划-研发-1")
        let reviewer = Agent(name: "评审-研发-1")
        let writer = Agent(name: "撰写-研发-1")
        project.agents = [planner, reviewer, writer]

        var workflow = project.workflows[0]
        var plannerNode = WorkflowNode(type: .agent)
        plannerNode.agentID = planner.id
        plannerNode.title = "Planner"

        var reviewerNode = WorkflowNode(type: .agent)
        reviewerNode.agentID = reviewer.id
        reviewerNode.title = "Reviewer"

        var writerNode = WorkflowNode(type: .agent)
        writerNode.agentID = writer.id
        writerNode.title = "Writer"

        var reviewEdge = WorkflowEdge(from: plannerNode.id, to: reviewerNode.id)
        reviewEdge.label = "Review Route"
        reviewEdge.isBidirectional = false

        var writingEdge = WorkflowEdge(from: plannerNode.id, to: writerNode.id)
        writingEdge.label = "Writing Route"
        writingEdge.isBidirectional = false

        workflow.nodes = [plannerNode, reviewerNode, writerNode]
        workflow.edges = [reviewEdge, writingEdge]
        project.workflows = [workflow]

        let reviewSessionID = "session-review"
        let writingSessionID = "session-writing"
        let startedAt = Date(timeIntervalSince1970: 1_710_000_000)

        let reviewDispatch = RuntimeDispatchRecord(
            eventID: "dispatch-review",
            workflowID: workflow.id.uuidString,
            nodeID: reviewerNode.id.uuidString,
            sourceAgentID: planner.id.uuidString,
            targetAgentID: reviewer.id.uuidString,
            summary: "Send draft to reviewer",
            sessionKey: reviewSessionID,
            status: .running,
            transportKind: .runtimeChannel,
            queuedAt: startedAt,
            updatedAt: startedAt.addingTimeInterval(10)
        )
        let writingDispatch = RuntimeDispatchRecord(
            eventID: "dispatch-writing",
            workflowID: workflow.id.uuidString,
            nodeID: writerNode.id.uuidString,
            sourceAgentID: planner.id.uuidString,
            targetAgentID: writer.id.uuidString,
            summary: "Send draft to writer",
            sessionKey: writingSessionID,
            status: .running,
            transportKind: .runtimeChannel,
            queuedAt: startedAt,
            updatedAt: startedAt.addingTimeInterval(20)
        )
        project.runtimeState.dispatchQueue = [reviewDispatch, writingDispatch]

        let reviewEvent = OpenClawRuntimeEvent(
            id: "event-review",
            eventType: .taskDispatch,
            workflowId: workflow.id.uuidString,
            nodeId: reviewerNode.id.uuidString,
            sessionKey: reviewSessionID,
            source: OpenClawRuntimeActor(kind: .agent, agentId: planner.id.uuidString, agentName: planner.name),
            target: OpenClawRuntimeActor(kind: .agent, agentId: reviewer.id.uuidString, agentName: reviewer.name),
            transport: OpenClawRuntimeTransport(kind: .runtimeChannel, deploymentKind: "local"),
            payload: ["summary": "Review draft"]
        )
        let writingEvent = OpenClawRuntimeEvent(
            id: "event-writing",
            eventType: .taskDispatch,
            workflowId: workflow.id.uuidString,
            nodeId: writerNode.id.uuidString,
            sessionKey: writingSessionID,
            source: OpenClawRuntimeActor(kind: .agent, agentId: planner.id.uuidString, agentName: planner.name),
            target: OpenClawRuntimeActor(kind: .agent, agentId: writer.id.uuidString, agentName: writer.name),
            transport: OpenClawRuntimeTransport(kind: .runtimeChannel, deploymentKind: "local"),
            payload: ["summary": "Write draft"]
        )
        project.runtimeState.runtimeEvents = [reviewEvent, writingEvent]

        let reviewResult = ExecutionResult(
            nodeID: reviewerNode.id,
            agentID: reviewer.id,
            status: .completed,
            output: "Reviewed",
            outputType: .agentFinalResponse,
            sessionID: reviewSessionID,
            transportKind: OpenClawRuntimeTransportKind.runtimeChannel.rawValue,
            runtimeEvents: [reviewEvent],
            primaryRuntimeEvent: reviewEvent,
            startedAt: startedAt,
            completedAt: startedAt.addingTimeInterval(45)
        )
        let writingResult = ExecutionResult(
            nodeID: writerNode.id,
            agentID: writer.id,
            status: .completed,
            output: "Written",
            outputType: .agentFinalResponse,
            sessionID: writingSessionID,
            transportKind: OpenClawRuntimeTransportKind.runtimeChannel.rawValue,
            runtimeEvents: [writingEvent],
            primaryRuntimeEvent: writingEvent,
            startedAt: startedAt,
            completedAt: startedAt.addingTimeInterval(50)
        )

        var reviewMessage = Message(from: planner.id, to: reviewer.id, type: .text, content: "Please review.")
        reviewMessage.metadata["workflowID"] = workflow.id.uuidString
        reviewMessage.metadata["workbenchSessionID"] = reviewSessionID

        var writingMessage = Message(from: planner.id, to: writer.id, type: .text, content: "Please write.")
        writingMessage.metadata["workflowID"] = workflow.id.uuidString
        writingMessage.metadata["workbenchSessionID"] = writingSessionID

        var reviewTask = Task(
            title: "Review Draft",
            description: "Inspect the draft",
            status: .inProgress,
            priority: .high,
            assignedAgentID: reviewer.id,
            workflowNodeID: reviewerNode.id
        )
        reviewTask.metadata["workflowID"] = workflow.id.uuidString
        reviewTask.metadata["workbenchSessionID"] = reviewSessionID

        var writingTask = Task(
            title: "Write Draft",
            description: "Produce the draft",
            status: .inProgress,
            priority: .medium,
            assignedAgentID: writer.id,
            workflowNodeID: writerNode.id
        )
        writingTask.metadata["workflowID"] = workflow.id.uuidString
        writingTask.metadata["workbenchSessionID"] = writingSessionID

        let investigation = try XCTUnwrap(
            OpsCenterSnapshotBuilder.buildRouteInvestigation(
                project: project,
                workflow: workflow,
                edgeID: reviewEdge.id,
                tasks: [reviewTask, writingTask],
                messages: [reviewMessage, writingMessage],
                executionResults: [reviewResult, writingResult]
            )
        )

        XCTAssertEqual(investigation.edge.id, reviewEdge.id)
        XCTAssertEqual(investigation.relatedSessions.map(\.sessionID), [reviewSessionID])
        XCTAssertEqual(investigation.dispatches.count, 1)
        XCTAssertEqual(investigation.dispatches.first?.summary, "Send draft to reviewer")
        XCTAssertEqual(investigation.receipts.count, 1)
        XCTAssertEqual(investigation.receipts.first?.nodeTitle, "Reviewer")
        XCTAssertEqual(investigation.messages.count, 1)
        XCTAssertEqual(investigation.messages.first?.routeTitle, "\(planner.name) -> \(reviewer.name)")
        XCTAssertEqual(investigation.tasks.count, 1)
        XCTAssertEqual(investigation.tasks.first?.title, "Review Draft")
        XCTAssertEqual(investigation.upstreamNode?.title, "Planner")
        XCTAssertEqual(investigation.downstreamNode?.title, "Reviewer")
    }

    func testProjectionStoreLoadsPersistedProjectionDocuments() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ops-center-projection-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let projectID = UUID(uuidString: "01000000-0000-0000-0000-000000000111")!
        let workflowID = UUID(uuidString: "02000000-0000-0000-0000-000000000222")!
        let nodeID = UUID(uuidString: "03000000-0000-0000-0000-000000000333")!
        let generatedAt = Date(timeIntervalSince1970: 1_710_100_000)
        let fileSystem = ProjectFileSystem.shared
        let encoder = JSONEncoder()

        try writeJSON(
            OpsCenterProjectionOverviewDocument(
                projectID: projectID,
                generatedAt: generatedAt,
                workflowCount: 1,
                nodeCount: 1,
                agentCount: 1,
                taskCount: 2,
                messageCount: 3,
                executionResultCount: 4,
                completedExecutionCount: 3,
                failedExecutionCount: 1,
                warningLogCount: 1,
                errorLogCount: 1,
                pendingApprovalCount: 0
            ),
            to: fileSystem.analyticsOverviewProjectionURL(for: projectID, under: tempRoot),
            encoder: encoder
        )
        try writeJSON(
            OpsCenterProjectionSessionsDocument(
                projectID: projectID,
                generatedAt: generatedAt.addingTimeInterval(5),
                sessions: [
                    OpsCenterProjectionSessionEntry(
                        sessionID: "session-a",
                        workflowIDs: [workflowID.uuidString],
                        messageCount: 2,
                        taskCount: 1,
                        eventCount: 3,
                        dispatchCount: 2,
                        receiptCount: 1,
                        queuedDispatchCount: 0,
                        inflightDispatchCount: 1,
                        completedDispatchCount: 1,
                        failedDispatchCount: 0,
                        latestFailureText: nil,
                        lastUpdatedAt: generatedAt.addingTimeInterval(10),
                        isProjectRuntimeSession: true
                    )
                ]
            ),
            to: fileSystem.analyticsSessionProjectionURL(for: projectID, under: tempRoot),
            encoder: encoder
        )
        try writeJSON(
            OpsCenterProjectionNodesRuntimeDocument(
                projectID: projectID,
                generatedAt: generatedAt.addingTimeInterval(10),
                nodes: [
                    OpsCenterProjectionNodeRuntimeEntry(
                        workflowID: workflowID,
                        workflowName: "Main Workflow",
                        nodeID: nodeID,
                        title: "Reviewer",
                        agentID: nil,
                        agentName: "Reviewer Agent",
                        status: "failed",
                        incomingEdgeCount: 1,
                        outgoingEdgeCount: 0,
                        relatedSessionIDs: ["session-a"],
                        queuedDispatchCount: 0,
                        inflightDispatchCount: 0,
                        completedDispatchCount: 1,
                        failedDispatchCount: 1,
                        waitingApprovalCount: 0,
                        receiptCount: 1,
                        averageDuration: 12,
                        lastUpdatedAt: generatedAt.addingTimeInterval(20),
                        latestDetail: "Failure retained."
                    )
                ]
            ),
            to: fileSystem.analyticsNodeRuntimeProjectionURL(for: projectID, under: tempRoot),
            encoder: encoder
        )

        let bundle = try XCTUnwrap(
            OpsCenterProjectionStore.load(projectID: projectID, appSupportRootDirectory: tempRoot)
        )

        XCTAssertEqual(bundle.projectID, projectID)
        XCTAssertEqual(bundle.overview?.taskCount, 2)
        XCTAssertEqual(bundle.freshestGeneratedAt, generatedAt.addingTimeInterval(10))
        XCTAssertEqual(bundle.sessionSummaries(for: workflowID).map(\.sessionID), ["session-a"])
        XCTAssertEqual(bundle.nodeSummaries(for: workflowID).first?.id, nodeID)
        XCTAssertEqual(bundle.nodeSummaries(for: workflowID).first?.status, .failed)
        XCTAssertEqual(bundle.nodeSummaries(for: workflowID).first?.latestDetail, "Failure retained.")
    }

    private func writeJSON<T: Encodable>(
        _ value: T,
        to url: URL,
        encoder: JSONEncoder
    ) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(value)
        try data.write(to: url)
    }
}
