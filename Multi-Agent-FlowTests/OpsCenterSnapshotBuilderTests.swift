import XCTest
@testable import Multi_Agent_Flow

final class OpsCenterSnapshotBuilderTests: XCTestCase {
    func testBuildThreadInvestigationAggregatesWorkbenchAndRuntimeEvidence() throws {
        var project = MAProject(name: "Ops Center Thread Test")

        let planner = Agent(name: "Planner Agent")
        let reviewer = Agent(name: "Reviewer Agent")
        project.agents = [planner, reviewer]

        var workflow = project.workflows[0]
        var plannerNode = WorkflowNode(type: .agent)
        plannerNode.agentID = planner.id
        plannerNode.title = "Planner"

        var reviewerNode = WorkflowNode(type: .agent)
        reviewerNode.agentID = reviewer.id
        reviewerNode.title = "Reviewer"

        var edge = WorkflowEdge(from: plannerNode.id, to: reviewerNode.id)
        edge.label = "Review Route"
        edge.isBidirectional = false

        workflow.nodes = [plannerNode, reviewerNode]
        workflow.edges = [edge]
        project.workflows = [workflow]

        let threadID = "thread-investigation"
        let startedAt = Date(timeIntervalSince1970: 1_710_200_000)

        let dispatchEvent = OpenClawRuntimeEvent(
            id: "event-thread-dispatch",
            eventType: .taskDispatch,
            workflowId: workflow.id.uuidString,
            nodeId: reviewerNode.id.uuidString,
            sessionKey: threadID,
            source: OpenClawRuntimeActor(kind: .agent, agentId: planner.id.uuidString, agentName: planner.name),
            target: OpenClawRuntimeActor(kind: .agent, agentId: reviewer.id.uuidString, agentName: reviewer.name),
            transport: OpenClawRuntimeTransport(kind: .runtimeChannel, deploymentKind: "local"),
            payload: ["summary": "Send the review request"]
        )
        project.runtimeState.runtimeEvents = [dispatchEvent]

        let dispatchRecord = RuntimeDispatchRecord(
            eventID: "dispatch-thread",
            workflowID: workflow.id.uuidString,
            nodeID: reviewerNode.id.uuidString,
            sourceAgentID: planner.id.uuidString,
            targetAgentID: reviewer.id.uuidString,
            summary: "Thread review dispatch",
            sessionKey: threadID,
            status: .waitingApproval,
            transportKind: .runtimeChannel,
            queuedAt: startedAt,
            updatedAt: startedAt.addingTimeInterval(15)
        )
        project.runtimeState.inflightDispatches = [dispatchRecord]

        let result = ExecutionResult(
            nodeID: reviewerNode.id,
            agentID: reviewer.id,
            status: .running,
            output: "Review in progress",
            outputType: .runtimeLog,
            sessionID: threadID,
            transportKind: OpenClawRuntimeTransportKind.runtimeChannel.rawValue,
            runtimeEvents: [dispatchEvent],
            primaryRuntimeEvent: dispatchEvent,
            startedAt: startedAt,
            completedAt: startedAt.addingTimeInterval(45)
        )

        var userMessage = Message(from: planner.id, to: reviewer.id, type: .task, content: "Please review the draft.")
        userMessage.timestamp = startedAt
        userMessage.status = .read
        userMessage.metadata["channel"] = "workbench"
        userMessage.metadata["workflowID"] = workflow.id.uuidString
        userMessage.metadata["workbenchSessionID"] = threadID
        userMessage.metadata["entryAgentID"] = planner.id.uuidString

        var approvalMessage = Message(from: reviewer.id, to: planner.id, type: .notification, content: "Needs approval before continuing.")
        approvalMessage.timestamp = startedAt.addingTimeInterval(30)
        approvalMessage.status = .waitingForApproval
        approvalMessage.requiresApproval = true
        approvalMessage.metadata["channel"] = "workbench"
        approvalMessage.metadata["workflowID"] = workflow.id.uuidString
        approvalMessage.metadata["workbenchSessionID"] = threadID
        approvalMessage.metadata["entryAgentID"] = planner.id.uuidString

        var reviewTask = Task(
            title: "Review Draft",
            description: "Validate the draft for release",
            status: .inProgress,
            priority: .high,
            assignedAgentID: reviewer.id,
            workflowNodeID: reviewerNode.id
        )
        reviewTask.createdAt = startedAt.addingTimeInterval(5)
        reviewTask.metadata["source"] = "workbench"
        reviewTask.metadata["workflowID"] = workflow.id.uuidString
        reviewTask.metadata["workbenchSessionID"] = threadID

        let investigation = try XCTUnwrap(
            OpsCenterSnapshotBuilder.buildThreadInvestigation(
                project: project,
                workflow: workflow,
                threadID: threadID,
                tasks: [reviewTask],
                messages: [userMessage, approvalMessage],
                executionResults: [result]
            )
        )

        XCTAssertEqual(investigation.threadID, threadID)
        XCTAssertEqual(investigation.sessionID, threadID)
        XCTAssertEqual(investigation.workflowID, workflow.id)
        XCTAssertEqual(investigation.workflowName, workflow.name)
        XCTAssertEqual(investigation.status, "approval_pending")
        XCTAssertEqual(investigation.entryAgentName, planner.name)
        XCTAssertEqual(investigation.participantNames, [planner.name, reviewer.name])
        XCTAssertEqual(investigation.pendingApprovalCount, 1)
        XCTAssertEqual(investigation.relatedSession?.sessionID, threadID)
        XCTAssertEqual(investigation.messages.count, 2)
        XCTAssertEqual(investigation.tasks.count, 1)
        XCTAssertEqual(investigation.dispatches.count, 1)
        XCTAssertEqual(investigation.receipts.count, 1)
        XCTAssertEqual(investigation.events.count, 1)
        XCTAssertTrue(investigation.relatedNodes.contains(where: { $0.id == reviewerNode.id }))
    }

    func testBuildArchiveProjectionInvestigationScopesProjectionBundle() throws {
        var project = MAProject(name: "Ops Center Projection Test")

        let agent = Agent(name: "Archive Agent")
        project.agents = [agent]

        var workflow = project.workflows[0]
        var node = WorkflowNode(type: .agent)
        node.agentID = agent.id
        node.title = "Archive Node"
        workflow.nodes = [node]
        workflow.edges = []
        project.workflows = [workflow]

        let now = Date(timeIntervalSince1970: 1_710_300_000)
        let executionID = UUID()
        let sessionID = "projection-thread"

        let bundle = OpsCenterProjectionBundle(
            projectID: project.id,
            loadedAt: now.addingTimeInterval(30),
            overview: OpsCenterProjectionOverviewDocument(
                projectID: project.id,
                generatedAt: now,
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
                pendingApprovalCount: 2
            ),
            traces: OpsCenterProjectionTraceDocument(
                projectID: project.id,
                generatedAt: now,
                traces: [
                    OpsCenterProjectionTraceEntry(
                        executionID: executionID,
                        nodeID: node.id,
                        agentID: agent.id,
                        sessionID: sessionID,
                        status: .failed,
                        outputType: .runtimeLog,
                        startedAt: now.addingTimeInterval(-60),
                        completedAt: now.addingTimeInterval(-30),
                        duration: 30,
                        protocolRepairCount: 1,
                        previewText: "Projection trace preview"
                    )
                ]
            ),
            anomalies: OpsCenterProjectionAnomalyDocument(
                projectID: project.id,
                generatedAt: now,
                anomalies: [
                    OpsCenterProjectionAnomalyEntry(
                        id: "projection-anomaly",
                        source: "runtime",
                        severity: "error",
                        message: "Projection retained a runtime failure",
                        nodeID: node.id,
                        agentID: agent.id,
                        sessionID: sessionID,
                        timestamp: now.addingTimeInterval(-20)
                    )
                ]
            ),
            liveRun: OpsCenterProjectionLiveRunDocument(
                projectID: project.id,
                generatedAt: now,
                runtimeSessionID: sessionID,
                activeSessionCount: 1,
                totalSessionCount: 1,
                queuedDispatchCount: 0,
                inflightDispatchCount: 1,
                failedDispatchCount: 1,
                waitingApprovalCount: 1,
                latestErrorText: "Projection error text",
                activeWorkflowCount: 1,
                workflows: [
                    OpsCenterProjectionWorkflowLiveRunEntry(
                        workflowID: workflow.id,
                        workflowName: workflow.name,
                        sessionCount: 1,
                        activeSessionCount: 1,
                        activeNodeCount: 1,
                        failedNodeCount: 1,
                        waitingApprovalNodeCount: 1,
                        lastUpdatedAt: now
                    )
                ]
            ),
            sessions: OpsCenterProjectionSessionsDocument(
                projectID: project.id,
                generatedAt: now,
                sessions: [
                    OpsCenterProjectionSessionEntry(
                        sessionID: sessionID,
                        sessionType: nil,
                        threadID: sessionID,
                        workflowIDs: [workflow.id.uuidString],
                        plannedTransport: nil,
                        actualTransport: nil,
                        actualTransportKinds: nil,
                        messageCount: 3,
                        taskCount: 2,
                        eventCount: 1,
                        dispatchCount: 1,
                        receiptCount: 1,
                        queuedDispatchCount: 0,
                        inflightDispatchCount: 1,
                        completedDispatchCount: 0,
                        failedDispatchCount: 1,
                        latestFailureText: "Retained failure",
                        fallbackReason: nil,
                        degradationReason: nil,
                        lastUpdatedAt: now,
                        isProjectRuntimeSession: true
                    )
                ]
            ),
            nodesRuntime: OpsCenterProjectionNodesRuntimeDocument(
                projectID: project.id,
                generatedAt: now,
                nodes: [
                    OpsCenterProjectionNodeRuntimeEntry(
                        workflowID: workflow.id,
                        workflowName: workflow.name,
                        nodeID: node.id,
                        title: node.title,
                        agentID: agent.id,
                        agentName: agent.name,
                        status: "failed",
                        incomingEdgeCount: 0,
                        outgoingEdgeCount: 0,
                        relatedSessionIDs: [sessionID],
                        queuedDispatchCount: 0,
                        inflightDispatchCount: 1,
                        completedDispatchCount: 0,
                        failedDispatchCount: 1,
                        waitingApprovalCount: 1,
                        receiptCount: 1,
                        averageDuration: 30,
                        lastUpdatedAt: now,
                        latestDetail: "Projection node failed"
                    )
                ]
            ),
            threads: OpsCenterProjectionThreadsDocument(
                projectID: project.id,
                generatedAt: now,
                threads: [
                    OpsCenterProjectionThreadEntry(
                        threadID: sessionID,
                        threadType: RuntimeSessionSemanticType.conversationAutonomous.rawValue,
                        mode: WorkbenchThreadSemanticMode.autonomousConversation.rawValue,
                        sessionID: sessionID,
                        linkedSessionIDs: [sessionID],
                        workflowID: workflow.id,
                        workflowName: workflow.name,
                        entryAgentName: agent.name,
                        participantNames: [agent.name],
                        status: "approval_pending",
                        startedAt: now.addingTimeInterval(-90),
                        lastUpdatedAt: now,
                        messageCount: 3,
                        taskCount: 2,
                        pendingApprovalCount: 1,
                        blockedTaskCount: 0,
                        activeTaskCount: 1,
                        completedTaskCount: 1,
                        failedMessageCount: 0
                    )
                ]
            ),
            cron: OpsCenterProjectionCronDocument(
                projectID: project.id,
                generatedAt: now,
                summary: OpsCenterProjectionCronSummary(
                    successRate: 50,
                    successfulRuns: 1,
                    failedRuns: 1,
                    latestRunAt: now
                ),
                crons: [
                    OpsCenterProjectionCronEntry(
                        cronName: "nightly-sync",
                        summary: OpsCenterProjectionCronSummary(
                            successRate: 50,
                            successfulRuns: 1,
                            failedRuns: 1,
                            latestRunAt: now
                        ),
                        historySeries: [
                            OpsCenterProjectionMetricSeries(
                                metricID: OpsHistoryMetric.cronReliability.rawValue,
                                points: [
                                    OpsCenterProjectionMetricPoint(date: now.addingTimeInterval(-86_400), value: 0),
                                    OpsCenterProjectionMetricPoint(date: now, value: 100)
                                ]
                            )
                        ],
                        runs: [
                            OpsCenterProjectionCronRunEntry(
                                id: "cron-run-1",
                                cronName: "nightly-sync",
                                statusText: "Completed",
                                runAt: now,
                                duration: 42,
                                deliveryStatus: "delivered",
                                summaryText: "Projection cron completed",
                                jobID: "job-1",
                                runID: sessionID,
                                sourcePath: "/tmp/cron.jsonl"
                            )
                        ],
                        anomalies: [
                            OpsCenterProjectionScopedAnomalyEntry(
                                id: "cron-anomaly-1",
                                title: "nightly-sync",
                                sourceLabel: "Cron",
                                detailText: "Projection cron timed out",
                                fullDetailText: "Projection cron timed out while draining work.",
                                occurredAt: now.addingTimeInterval(-30),
                                status: OpsHealthStatus.warning.rawValue,
                                statusText: "Timeout",
                                sourceService: nil,
                                linkedSpanID: nil,
                                relatedRunID: sessionID,
                                relatedJobID: "job-1",
                                relatedSourcePath: "/tmp/cron.jsonl"
                            )
                        ]
                    )
                ]
            ),
            tools: OpsCenterProjectionToolsDocument(
                projectID: project.id,
                generatedAt: now,
                tools: [
                    OpsCenterProjectionToolEntry(
                        toolIdentifier: "search.web",
                        historySeries: [
                            OpsCenterProjectionMetricSeries(
                                metricID: OpsHistoryMetric.workflowReliability.rawValue,
                                points: [
                                    OpsCenterProjectionMetricPoint(date: now.addingTimeInterval(-86_400), value: 0),
                                    OpsCenterProjectionMetricPoint(date: now, value: 100)
                                ]
                            )
                        ],
                        spans: [
                            OpsCenterProjectionToolSpanEntry(
                                id: executionID,
                                title: "Search Tool",
                                service: "openclaw.external-tool-result",
                                statusText: "error",
                                agentName: agent.name,
                                startedAt: now.addingTimeInterval(-40),
                                duration: 3,
                                summaryText: "Search timed out"
                            )
                        ],
                        anomalies: [
                            OpsCenterProjectionScopedAnomalyEntry(
                                id: "tool-anomaly-1",
                                title: "Search Tool",
                                sourceLabel: "Tool",
                                detailText: "Search timed out",
                                fullDetailText: "Search timed out against upstream provider.",
                                occurredAt: now.addingTimeInterval(-35),
                                status: OpsHealthStatus.critical.rawValue,
                                statusText: "error",
                                sourceService: "search.web",
                                linkedSpanID: executionID,
                                relatedRunID: nil,
                                relatedJobID: nil,
                                relatedSourcePath: nil
                            )
                        ]
                    )
                ]
            ),
            workflowHealth: OpsCenterProjectionWorkflowHealthDocument(
                projectID: project.id,
                generatedAt: now,
                workflows: [
                    OpsCenterProjectionWorkflowHealthEntry(
                        workflowID: workflow.id,
                        workflowName: workflow.name,
                        nodeCount: 1,
                        edgeCount: 0,
                        sessionCount: 1,
                        activeNodeCount: 1,
                        failedNodeCount: 1,
                        waitingApprovalNodeCount: 1,
                        completedNodeCount: 0,
                        idleNodeCount: 0,
                        recentFailureCount: 1,
                        pendingApprovalCount: 1,
                        lastUpdatedAt: now
                    )
                ]
            )
        )

        let investigation = try XCTUnwrap(
            OpsCenterSnapshotBuilder.buildArchiveProjectionInvestigation(
                project: project,
                workflow: workflow,
                projections: bundle
            )
        )

        XCTAssertEqual(investigation.scopeTitle, workflow.name)
        XCTAssertEqual(investigation.projectName, project.name)
        XCTAssertEqual(investigation.sessionCount, 1)
        XCTAssertEqual(investigation.nodeCount, 1)
        XCTAssertEqual(investigation.traceCount, 1)
        XCTAssertEqual(investigation.anomalyCount, 1)
        XCTAssertEqual(investigation.documentDigests.count, 10)
        XCTAssertTrue(investigation.documentDigests.contains(where: { $0.title == "Traces" && $0.valueText == "1 scoped traces" }))
        XCTAssertTrue(investigation.documentDigests.contains(where: { $0.title == "Threads" && $0.valueText == "1 scoped threads" }))
        XCTAssertTrue(investigation.documentDigests.contains(where: { $0.title == "Cron" && $0.valueText == "2 retained runs" }))
        XCTAssertTrue(investigation.documentDigests.contains(where: { $0.title == "Tools" && $0.valueText == "1 retained tools" }))
        XCTAssertEqual(investigation.freshestGeneratedAt, now)
        XCTAssertTrue(investigation.liveRunSummary?.contains("1 active of 1 scoped sessions") == true)
        XCTAssertTrue(investigation.workflowHealthSummary?.contains("1 recent failures") == true)
    }

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
                        sessionType: nil,
                        threadID: "session-a",
                        workflowIDs: [workflowID.uuidString],
                        plannedTransport: nil,
                        actualTransport: nil,
                        actualTransportKinds: nil,
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
                        fallbackReason: nil,
                        degradationReason: nil,
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
        try writeJSON(
            OpsCenterProjectionThreadsDocument(
                projectID: projectID,
                generatedAt: generatedAt.addingTimeInterval(15),
                threads: [
                    OpsCenterProjectionThreadEntry(
                        threadID: "session-a",
                        threadType: RuntimeSessionSemanticType.workflowControlled.rawValue,
                        mode: WorkbenchThreadSemanticMode.controlledRun.rawValue,
                        sessionID: "session-a",
                        linkedSessionIDs: ["session-a"],
                        workflowID: workflowID,
                        workflowName: "Main Workflow",
                        entryAgentName: "Reviewer Agent",
                        participantNames: ["Reviewer Agent"],
                        status: "active",
                        startedAt: generatedAt,
                        lastUpdatedAt: generatedAt.addingTimeInterval(25),
                        messageCount: 2,
                        taskCount: 1,
                        pendingApprovalCount: 0,
                        blockedTaskCount: 0,
                        activeTaskCount: 1,
                        completedTaskCount: 0,
                        failedMessageCount: 0
                    )
                ]
            ),
            to: fileSystem.analyticsThreadProjectionURL(for: projectID, under: tempRoot),
            encoder: encoder
        )
        try writeJSON(
            OpsCenterProjectionCronDocument(
                projectID: projectID,
                generatedAt: generatedAt.addingTimeInterval(18),
                summary: OpsCenterProjectionCronSummary(
                    successRate: 50,
                    successfulRuns: 1,
                    failedRuns: 1,
                    latestRunAt: generatedAt.addingTimeInterval(18)
                ),
                crons: [
                    OpsCenterProjectionCronEntry(
                        cronName: "nightly-sync",
                        summary: OpsCenterProjectionCronSummary(
                            successRate: 50,
                            successfulRuns: 1,
                            failedRuns: 1,
                            latestRunAt: generatedAt.addingTimeInterval(18)
                        ),
                        historySeries: [
                            OpsCenterProjectionMetricSeries(
                                metricID: OpsHistoryMetric.cronReliability.rawValue,
                                points: [
                                    OpsCenterProjectionMetricPoint(date: generatedAt, value: 50)
                                ]
                            )
                        ],
                        runs: [
                            OpsCenterProjectionCronRunEntry(
                                id: "cron-run-1",
                                cronName: "nightly-sync",
                                statusText: "Completed",
                                runAt: generatedAt.addingTimeInterval(18),
                                duration: 12,
                                deliveryStatus: "delivered",
                                summaryText: "Cron completed",
                                jobID: "job-1",
                                runID: "run-1",
                                sourcePath: "/tmp/nightly.jsonl"
                            )
                        ],
                        anomalies: []
                    )
                ]
            ),
            to: fileSystem.analyticsCronProjectionURL(for: projectID, under: tempRoot),
            encoder: encoder
        )
        try writeJSON(
            OpsCenterProjectionToolsDocument(
                projectID: projectID,
                generatedAt: generatedAt.addingTimeInterval(20),
                tools: [
                    OpsCenterProjectionToolEntry(
                        toolIdentifier: "search.web",
                        historySeries: [
                            OpsCenterProjectionMetricSeries(
                                metricID: OpsHistoryMetric.workflowReliability.rawValue,
                                points: [
                                    OpsCenterProjectionMetricPoint(date: generatedAt, value: 100)
                                ]
                            )
                        ],
                        spans: [
                            OpsCenterProjectionToolSpanEntry(
                                id: UUID(uuidString: "04000000-0000-0000-0000-000000000444")!,
                                title: "Search Tool",
                                service: "openclaw.external-tool-result",
                                statusText: "ok",
                                agentName: "Reviewer Agent",
                                startedAt: generatedAt.addingTimeInterval(20),
                                duration: 3,
                                summaryText: "Search completed"
                            )
                        ],
                        anomalies: []
                    )
                ]
            ),
            to: fileSystem.analyticsToolProjectionURL(for: projectID, under: tempRoot),
            encoder: encoder
        )

        let bundle = try XCTUnwrap(
            OpsCenterProjectionStore.load(projectID: projectID, appSupportRootDirectory: tempRoot)
        )

        XCTAssertEqual(bundle.projectID, projectID)
        XCTAssertEqual(bundle.overview?.taskCount, 2)
        XCTAssertEqual(bundle.freshestGeneratedAt, generatedAt.addingTimeInterval(20))
        XCTAssertEqual(bundle.sessionSummaries(for: workflowID).map(\.sessionID), ["session-a"])
        XCTAssertEqual(bundle.nodeSummaries(for: workflowID).first?.id, nodeID)
        XCTAssertEqual(bundle.nodeSummaries(for: workflowID).first?.status, .failed)
        XCTAssertEqual(bundle.nodeSummaries(for: workflowID).first?.latestDetail, "Failure retained.")
        XCTAssertEqual(bundle.threadEntries(for: workflowID).map(\.threadID), ["session-a"])
        XCTAssertEqual(bundle.threadEntries(for: workflowID).first?.entryAgentName, "Reviewer Agent")
        XCTAssertEqual(bundle.cronSummary?.failedRuns, 1)
        XCTAssertEqual(bundle.recentCronRuns().map(\.cronName), ["nightly-sync"])
        XCTAssertEqual(bundle.toolEntries().map(\.toolIdentifier), ["search.web"])
    }

    func testBuildAgentRadarDigestsRanksCriticalAgentAheadOfStableAgent() throws {
        let strugglingAgent = Agent(name: "Struggling Agent")
        let stableAgent = Agent(name: "Stable Agent")
        let startedAt = Date(timeIntervalSince1970: 1_710_500_000)

        let activeTask = Task(
            title: "Investigate Runtime",
            description: "Check the failing workflow path",
            status: .inProgress,
            priority: .high,
            assignedAgentID: strugglingAgent.id
        )

        let failingResult = ExecutionResult(
            nodeID: UUID(),
            agentID: strugglingAgent.id,
            status: .failed,
            output: "Gateway execution failed",
            outputType: .errorSummary,
            startedAt: startedAt,
            completedAt: startedAt.addingTimeInterval(240)
        )

        let stableResult = ExecutionResult(
            nodeID: UUID(),
            agentID: stableAgent.id,
            status: .completed,
            output: "All clear",
            outputType: .agentFinalResponse,
            startedAt: startedAt,
            completedAt: startedAt.addingTimeInterval(24)
        )

        let digests = opsBuildAgentRadarDigests(
            agents: [stableAgent, strugglingAgent],
            trackedMemoryAgentIDs: Set([stableAgent.id]),
            tasks: [activeTask],
            executionResults: [stableResult, failingResult],
            executionLogs: [
                ExecutionLogEntry(
                    level: .error,
                    message: "Gateway timeout reached while dispatching",
                    agentID: strugglingAgent.id
                )
            ],
            activeAgentIDs: Set([strugglingAgent.id]),
            nodeAgentIDs: [:]
        )

        XCTAssertEqual(digests.first?.id, strugglingAgent.id)

        let strugglingDigest = try XCTUnwrap(digests.first(where: { $0.id == strugglingAgent.id }))
        XCTAssertEqual(strugglingDigest.status, .critical)
        XCTAssertEqual(strugglingDigest.failedCount, 1)
        XCTAssertEqual(strugglingDigest.errorCount, 1)
        XCTAssertEqual(strugglingDigest.activeTaskCount, 1)
        XCTAssertTrue(strugglingDigest.isActive)
        XCTAssertFalse(strugglingDigest.hasTrackedMemory)

        let stableDigest = try XCTUnwrap(digests.first(where: { $0.id == stableAgent.id }))
        XCTAssertEqual(stableDigest.status, .healthy)
        XCTAssertEqual(stableDigest.completedCount, 1)
        XCTAssertTrue(stableDigest.hasTrackedMemory)
        XCTAssertFalse(stableDigest.isActive)
    }

    func testBuildAgentInvestigationAggregatesAgentOwnedEvidenceAndSessions() throws {
        var project = MAProject(name: "Ops Agent Investigation")

        let planner = Agent(name: "Planner Agent")
        let reviewer = Agent(name: "Reviewer Agent")
        project.agents = [planner, reviewer]

        var workflow = project.workflows[0]
        var plannerNode = WorkflowNode(type: .agent)
        plannerNode.agentID = planner.id
        plannerNode.title = "Planner Node"

        var reviewerNode = WorkflowNode(type: .agent)
        reviewerNode.agentID = reviewer.id
        reviewerNode.title = "Reviewer Node"

        workflow.nodes = [plannerNode, reviewerNode]
        workflow.edges = [WorkflowEdge(from: plannerNode.id, to: reviewerNode.id)]
        project.workflows = [workflow]

        let sessionID = "agent-investigation-session"
        let startedAt = Date(timeIntervalSince1970: 1_710_700_000)

        let runtimeEvent = OpenClawRuntimeEvent(
            id: "agent-investigation-event",
            eventType: .taskDispatch,
            workflowId: workflow.id.uuidString,
            nodeId: reviewerNode.id.uuidString,
            sessionKey: sessionID,
            source: OpenClawRuntimeActor(kind: .agent, agentId: planner.id.uuidString, agentName: planner.name),
            target: OpenClawRuntimeActor(kind: .agent, agentId: reviewer.id.uuidString, agentName: reviewer.name),
            transport: OpenClawRuntimeTransport(kind: .runtimeChannel, deploymentKind: "local"),
            payload: ["summary": "Route work to reviewer"]
        )
        project.runtimeState.runtimeEvents = [runtimeEvent]
        project.runtimeState.inflightDispatches = [
            RuntimeDispatchRecord(
                eventID: "dispatch-reviewer",
                workflowID: workflow.id.uuidString,
                nodeID: reviewerNode.id.uuidString,
                sourceAgentID: planner.id.uuidString,
                targetAgentID: reviewer.id.uuidString,
                summary: "Reviewer must validate the plan",
                sessionKey: sessionID,
                status: .running,
                transportKind: .runtimeChannel,
                queuedAt: startedAt,
                updatedAt: startedAt.addingTimeInterval(12)
            )
        ]

        var reviewTask = Task(
            title: "Review Plan",
            description: "Validate the final proposal",
            status: .inProgress,
            priority: .high,
            assignedAgentID: reviewer.id,
            workflowNodeID: reviewerNode.id
        )
        reviewTask.createdAt = startedAt.addingTimeInterval(5)
        reviewTask.metadata["workflowID"] = workflow.id.uuidString
        reviewTask.metadata["workbenchSessionID"] = sessionID

        var reviewMessage = Message(from: planner.id, to: reviewer.id, type: .task, content: "Please check the risk section.")
        reviewMessage.timestamp = startedAt.addingTimeInterval(8)
        reviewMessage.metadata["channel"] = "workbench"
        reviewMessage.metadata["workflowID"] = workflow.id.uuidString
        reviewMessage.metadata["workbenchSessionID"] = sessionID

        let reviewResult = ExecutionResult(
            nodeID: reviewerNode.id,
            agentID: reviewer.id,
            status: .failed,
            output: "Reviewer found an invalid connection assumption",
            outputType: .errorSummary,
            sessionID: sessionID,
            transportKind: OpenClawRuntimeTransportKind.runtimeChannel.rawValue,
            runtimeEvents: [runtimeEvent],
            primaryRuntimeEvent: runtimeEvent,
            startedAt: startedAt,
            completedAt: startedAt.addingTimeInterval(90)
        )

        let investigation = try XCTUnwrap(
            OpsCenterSnapshotBuilder.buildAgentInvestigation(
                project: project,
                workflow: nil,
                agentID: reviewer.id,
                tasks: [reviewTask],
                messages: [reviewMessage],
                executionResults: [reviewResult],
                executionLogs: [
                    ExecutionLogEntry(
                        level: .warning,
                        message: "Reviewer exceeded expected latency",
                        nodeID: reviewerNode.id,
                        sessionID: sessionID
                    ),
                    ExecutionLogEntry(
                        level: .error,
                        message: "Reviewer returned an invalid tool response",
                        sessionID: sessionID,
                        agentID: reviewer.id
                    )
                ],
                activeAgentIDs: Set([reviewer.id])
            )
        )

        XCTAssertEqual(investigation.agentID, reviewer.id)
        XCTAssertEqual(investigation.agentName, reviewer.name)
        XCTAssertEqual(investigation.scopeTitle, project.name)
        XCTAssertEqual(investigation.status, .critical)
        XCTAssertEqual(investigation.completedCount, 0)
        XCTAssertEqual(investigation.failedCount, 1)
        XCTAssertEqual(investigation.warningCount, 1)
        XCTAssertEqual(investigation.errorCount, 1)
        XCTAssertEqual(investigation.activeTaskCount, 1)
        XCTAssertTrue(investigation.isActive)
        XCTAssertFalse(investigation.hasTrackedMemory)
        XCTAssertEqual(investigation.relatedNodes.map(\.id), [reviewerNode.id])
        XCTAssertEqual(investigation.relatedSessions.map(\.sessionID), [sessionID])
        XCTAssertEqual(investigation.events.count, 1)
        XCTAssertEqual(investigation.dispatches.count, 1)
        XCTAssertEqual(investigation.receipts.count, 1)
        XCTAssertEqual(investigation.messages.count, 1)
        XCTAssertEqual(investigation.tasks.count, 1)
    }

    func testBuildAssetRadarSnapshotSurfacesMissingStaleAndCompressionSignals() throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent("ops-war-room-assets-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: rootURL) }

        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)

        let now = Date(timeIntervalSince1970: 1_710_600_000)
        let staleDate = now.addingTimeInterval(-(60 * 60 * 24 * 9))
        let owner = Agent(name: "Archivist Agent")

        let compressedTask = Task(
            title: "Compressed Workspace",
            description: "Large generated output",
            status: .todo,
            priority: .medium,
            assignedAgentID: owner.id
        )
        let staleTask = Task(
            title: "Stale Workspace",
            description: "Quiet archive candidate",
            status: .todo,
            priority: .medium,
            assignedAgentID: owner.id
        )
        let missingTask = Task(
            title: "Missing Workspace",
            description: "Workspace path is gone",
            status: .todo,
            priority: .medium,
            assignedAgentID: owner.id
        )

        let compressedURL = rootURL.appendingPathComponent("compressed", isDirectory: true)
        let staleURL = rootURL.appendingPathComponent("stale", isDirectory: true)
        try fileManager.createDirectory(at: compressedURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: staleURL, withIntermediateDirectories: true)

        for index in 0..<251 {
            let fileURL = compressedURL.appendingPathComponent("file-\(index).txt")
            try Data("x".utf8).write(to: fileURL)
        }

        let staleFileURL = staleURL.appendingPathComponent("state.json")
        try Data("stale".utf8).write(to: staleFileURL)
        try fileManager.setAttributes([.modificationDate: staleDate], ofItemAtPath: staleFileURL.path)
        try fileManager.setAttributes([.modificationDate: staleDate], ofItemAtPath: staleURL.path)

        let readyMemoryURL = rootURL.appendingPathComponent("memory-ready.json")
        let staleMemoryURL = rootURL.appendingPathComponent("memory-stale.json")
        try Data("ready".utf8).write(to: readyMemoryURL)
        try Data("stale-memory".utf8).write(to: staleMemoryURL)

        let snapshot = opsBuildAssetRadarSnapshot(
            workspaceRecords: [
                ProjectWorkspaceRecord(
                    taskID: compressedTask.id,
                    workspaceRelativePath: "compressed",
                    workspaceName: "Compressed Workspace",
                    createdAt: now,
                    updatedAt: now
                ),
                ProjectWorkspaceRecord(
                    taskID: staleTask.id,
                    workspaceRelativePath: "stale",
                    workspaceName: "Stale Workspace",
                    createdAt: staleDate,
                    updatedAt: staleDate
                ),
                ProjectWorkspaceRecord(
                    taskID: missingTask.id,
                    workspaceRelativePath: "missing",
                    workspaceName: "Missing Workspace",
                    createdAt: now,
                    updatedAt: now
                )
            ],
            memoryData: ProjectMemoryData(
                agentMemories: [
                    AgentMemoryBackupRecord(
                        agentID: owner.id,
                        agentName: owner.name,
                        sourcePath: nil,
                        lastCapturedAt: now
                    ),
                    AgentMemoryBackupRecord(
                        agentID: UUID(),
                        agentName: "Stale Memory Agent",
                        sourcePath: staleMemoryURL.path,
                        lastCapturedAt: now.addingTimeInterval(-(60 * 60 * 24 * 15))
                    ),
                    AgentMemoryBackupRecord(
                        agentID: UUID(),
                        agentName: "Ready Memory Agent",
                        sourcePath: readyMemoryURL.path,
                        lastCapturedAt: now.addingTimeInterval(-(60 * 60 * 24))
                    )
                ]
            ),
            tasks: [compressedTask, staleTask, missingTask],
            agentNamesByID: [owner.id: owner.name],
            workspaceRootURL: rootURL,
            now: now,
            fileManager: fileManager
        )

        XCTAssertEqual(snapshot.totalFileCount, 252)
        XCTAssertEqual(snapshot.missingWorkspaceCount, 1)
        XCTAssertEqual(snapshot.staleWorkspaceCount, 1)
        XCTAssertEqual(snapshot.compressionCandidateCount, 1)
        XCTAssertEqual(snapshot.missingMemoryCount, 1)

        let missingWorkspace = try XCTUnwrap(snapshot.workspaces.first(where: { $0.workspaceName == "Missing Workspace" }))
        XCTAssertTrue(missingWorkspace.isMissing)
        XCTAssertEqual(missingWorkspace.status, .critical)

        let compressedWorkspace = try XCTUnwrap(snapshot.workspaces.first(where: { $0.workspaceName == "Compressed Workspace" }))
        XCTAssertTrue(compressedWorkspace.compressionCandidate)
        XCTAssertEqual(compressedWorkspace.fileCount, 251)
        XCTAssertEqual(compressedWorkspace.status, .warning)

        let staleWorkspace = try XCTUnwrap(snapshot.workspaces.first(where: { $0.workspaceName == "Stale Workspace" }))
        XCTAssertFalse(staleWorkspace.isMissing)
        XCTAssertEqual(staleWorkspace.fileCount, 1)
        XCTAssertEqual(staleWorkspace.status, .warning)

        let missingMemory = try XCTUnwrap(snapshot.memoryDigests.first(where: { $0.agentName == owner.name }))
        XCTAssertEqual(missingMemory.status, .critical)

        let staleMemory = try XCTUnwrap(snapshot.memoryDigests.first(where: { $0.agentName == "Stale Memory Agent" }))
        XCTAssertEqual(staleMemory.status, .warning)

        let readyMemory = try XCTUnwrap(snapshot.memoryDigests.first(where: { $0.agentName == "Ready Memory Agent" }))
        XCTAssertEqual(readyMemory.status, .healthy)
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
