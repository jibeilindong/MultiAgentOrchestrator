import XCTest
import SQLite3
@testable import Multi_Agent_Flow

final class OpsAnalyticsQueryTests: XCTestCase {
    private let service = OpsAnalyticsService()
    private var projectIDsToClean: [UUID] = []
    private var temporaryURLsToClean: [URL] = []
    private let iso8601 = ISO8601DateFormatter()
    private let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .autoupdatingCurrent
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    override func tearDownWithError() throws {
        let fileManager = FileManager.default
        for projectID in projectIDsToClean {
            let dbURL = ProjectManager.shared.analyticsDatabaseURL(for: projectID)
            try? fileManager.removeItem(at: dbURL)
        }
        projectIDsToClean.removeAll()
        for url in temporaryURLsToClean {
            try? fileManager.removeItem(at: url)
        }
        temporaryURLsToClean.removeAll()
        try super.tearDownWithError()
    }

    func testCronDetailReturnsScopedRunsAnomaliesAndHistory() throws {
        let projectID = makeProjectID()
        try prepareEmptyAnalyticsDatabase(for: projectID)

        let now = Date()
        let today = calendarDayString(for: now)
        let yesterdayDate = Calendar.autoupdatingCurrent.date(byAdding: .day, value: -1, to: now) ?? now
        let yesterday = calendarDayString(for: yesterdayDate)
        let sessionID = UUID().uuidString

        try withDatabase(for: projectID) { db in
            try insertCronRun(
                db: db,
                projectID: projectID,
                date: today,
                cronName: "nightly-sync",
                status: "completed",
                jobID: "job-success",
                runID: UUID().uuidString,
                runAt: now,
                durationMs: 1_250,
                deliveryStatus: "delivered",
                summary: "Completed nightly sync",
                sourcePath: "/tmp/nightly-success.jsonl"
            )
            try insertCronRun(
                db: db,
                projectID: projectID,
                date: yesterday,
                cronName: "nightly-sync",
                status: "timeout",
                jobID: "job-timeout",
                runID: sessionID,
                runAt: yesterdayDate,
                durationMs: 9_500,
                error: "Worker timed out",
                sourcePath: "/tmp/nightly-timeout.jsonl"
            )
            try insertCronRun(
                db: db,
                projectID: projectID,
                date: today,
                cronName: "other-cron",
                status: "completed",
                jobID: "job-other",
                runID: UUID().uuidString,
                runAt: now,
                summary: "Should be ignored",
                sourcePath: "/tmp/other.jsonl"
            )
        }

        let detail = try XCTUnwrap(
            service.cronDetail(
                projectID: projectID,
                cronName: "nightly-sync",
                days: 30,
                runLimit: 10,
                anomalyLimit: 10
            )
        )

        let summary = try XCTUnwrap(detail.summary)
        XCTAssertEqual(summary.successfulRuns, 1)
        XCTAssertEqual(summary.failedRuns, 1)
        XCTAssertEqual(summary.successRate, 50, accuracy: 0.001)
        XCTAssertEqual(detail.runs.map(\.jobID), ["job-success", "job-timeout"])
        XCTAssertEqual(detail.anomalies.count, 1)
        XCTAssertEqual(detail.anomalies.first?.relatedJobID, "job-timeout")
        XCTAssertEqual(detail.anomalies.first?.relatedRunID, sessionID)
        XCTAssertEqual(detail.anomalies.first?.relatedSourcePath, "/tmp/nightly-timeout.jsonl")

        let cronReliability = try XCTUnwrap(series(detail.historySeries, metric: .cronReliability))
        XCTAssertEqual(cronReliability.points.count, 2)
        XCTAssertEqual(try XCTUnwrap(cronReliability.latestPoint).value, 100, accuracy: 0.001)

        let errorBudget = try XCTUnwrap(series(detail.historySeries, metric: .errorBudget))
        XCTAssertEqual(try XCTUnwrap(errorBudget.points.last).value, 1, accuracy: 0.001)
    }

    func testToolDetailReturnsScopedSpansAnomaliesAndHistory() throws {
        let projectID = makeProjectID()
        try prepareEmptyAnalyticsDatabase(for: projectID)

        let now = Date()
        let yesterday = Calendar.autoupdatingCurrent.date(byAdding: .day, value: -1, to: now) ?? now

        try withDatabase(for: projectID) { db in
            try insertSpan(
                db: db,
                projectID: projectID,
                spanID: UUID(),
                name: "Search Tool Success",
                service: "openclaw.external-tool-result",
                status: "ok",
                startedAt: now,
                durationMs: 240,
                attributes: [
                    "agent_name": "Scout",
                    "tool_name": "search.web",
                    "preview_text": "Search completed"
                ],
                events: "ok"
            )
            try insertSpan(
                db: db,
                projectID: projectID,
                spanID: UUID(),
                name: "Search Tool Failure",
                service: "openclaw.external-tool-result",
                status: "error",
                startedAt: yesterday,
                durationMs: 800,
                attributes: [
                    "agent_name": "Scout",
                    "tool_name": "search.web",
                    "preview_text": "Search failed"
                ],
                events: "timeout while calling provider"
            )
            try insertSpan(
                db: db,
                projectID: projectID,
                spanID: UUID(),
                name: "Other Tool",
                service: "openclaw.external-tool-result",
                status: "ok",
                startedAt: now,
                durationMs: 50,
                attributes: [
                    "agent_name": "Scout",
                    "tool_name": "file.write",
                    "preview_text": "Should be ignored"
                ],
                events: "ok"
            )
        }

        let detail = try XCTUnwrap(
            service.toolDetail(
                projectID: projectID,
                toolIdentifier: "search.web",
                days: 30,
                spanLimit: 10,
                anomalyLimit: 10
            )
        )

        XCTAssertEqual(detail.spans.count, 2)
        XCTAssertEqual(detail.spans.map(\.agentName), ["Scout", "Scout"])
        XCTAssertEqual(detail.anomalies.count, 1)
        XCTAssertEqual(detail.anomalies.first?.sourceLabel, "Tool")
        XCTAssertEqual(detail.anomalies.first?.statusText, "error")

        let reliability = try XCTUnwrap(series(detail.historySeries, metric: .workflowReliability))
        XCTAssertEqual(reliability.points.count, 2)
        XCTAssertEqual(try XCTUnwrap(reliability.latestPoint).value, 100, accuracy: 0.001)

        let errorBudget = try XCTUnwrap(series(detail.historySeries, metric: .errorBudget))
        XCTAssertEqual(try XCTUnwrap(errorBudget.points.last).value, 1, accuracy: 0.001)
    }

    func testScopedHistorySeriesFiltersCronAndToolScopesIndependently() throws {
        let projectID = makeProjectID()
        try prepareEmptyAnalyticsDatabase(for: projectID)

        let now = Date()
        let twoDaysAgo = Calendar.autoupdatingCurrent.date(byAdding: .day, value: -2, to: now) ?? now

        try withDatabase(for: projectID) { db in
            try insertCronRun(
                db: db,
                projectID: projectID,
                date: calendarDayString(for: now),
                cronName: "focus-cron",
                status: "completed",
                jobID: "cron-ok",
                runID: UUID().uuidString,
                runAt: now,
                summary: "Included"
            )
            try insertCronRun(
                db: db,
                projectID: projectID,
                date: calendarDayString(for: twoDaysAgo),
                cronName: "focus-cron",
                status: "failed",
                jobID: "cron-failed",
                runID: UUID().uuidString,
                runAt: twoDaysAgo,
                error: "Included failure"
            )
            try insertCronRun(
                db: db,
                projectID: projectID,
                date: calendarDayString(for: now),
                cronName: "ignored-cron",
                status: "failed",
                jobID: "cron-ignored",
                runID: UUID().uuidString,
                runAt: now,
                error: "Ignored"
            )

            try insertSpan(
                db: db,
                projectID: projectID,
                spanID: UUID(),
                name: "Focus Tool OK",
                service: "openclaw.external-tool-result",
                status: "ok",
                startedAt: now,
                attributes: [
                    "agent_name": "Analyst",
                    "tool_name": "focus.tool",
                    "preview_text": "Included"
                ]
            )
            try insertSpan(
                db: db,
                projectID: projectID,
                spanID: UUID(),
                name: "Focus Tool Error",
                service: "openclaw.external-tool-result",
                status: "error",
                startedAt: twoDaysAgo,
                attributes: [
                    "agent_name": "Analyst",
                    "tool_name": "focus.tool",
                    "preview_text": "Included failure"
                ],
                events: "timeout"
            )
            try insertSpan(
                db: db,
                projectID: projectID,
                spanID: UUID(),
                name: "Ignored Tool Error",
                service: "openclaw.external-tool-result",
                status: "error",
                startedAt: now,
                attributes: [
                    "agent_name": "Analyst",
                    "tool_name": "ignored.tool",
                    "preview_text": "Ignored"
                ],
                events: "timeout"
            )
        }

        let cronSeries = service.scopedHistorySeries(
            projectID: projectID,
            days: 30,
            scopeKind: "cron",
            scopeValue: "focus-cron",
            scopeMatchKey: "focus-cron"
        )
        let toolSeries = service.scopedHistorySeries(
            projectID: projectID,
            days: 30,
            scopeKind: "tool",
            scopeValue: "focus.tool",
            scopeMatchKey: "focus.tool"
        )

        let cronReliability = try XCTUnwrap(series(cronSeries, metric: .cronReliability))
        XCTAssertEqual(cronReliability.points.count, 2)
        XCTAssertEqual(try XCTUnwrap(cronReliability.latestPoint).value, 100, accuracy: 0.001)

        let cronBudget = try XCTUnwrap(series(cronSeries, metric: .errorBudget))
        XCTAssertEqual(try XCTUnwrap(cronBudget.points.last).value, 1, accuracy: 0.001)

        let toolReliability = try XCTUnwrap(series(toolSeries, metric: .workflowReliability))
        XCTAssertEqual(toolReliability.points.count, 2)
        XCTAssertEqual(try XCTUnwrap(toolReliability.latestPoint).value, 100, accuracy: 0.001)

        let toolBudget = try XCTUnwrap(series(toolSeries, metric: .errorBudget))
        XCTAssertEqual(try XCTUnwrap(toolBudget.points.last).value, 1, accuracy: 0.001)
    }

    func testScopedHistorySeriesBuildsAgentMetricsFromRuntimeActivityAndCronMatches() throws {
        let projectID = makeProjectID()
        try prepareEmptyAnalyticsDatabase(for: projectID)

        let agentID = UUID()
        let agentName = "Planner"
        let now = Date()
        let yesterday = Calendar.autoupdatingCurrent.date(byAdding: .day, value: -1, to: now) ?? now

        try withDatabase(for: projectID) { db in
            try insertSpan(
                db: db,
                projectID: projectID,
                spanID: UUID(),
                name: "Planner Session Success",
                service: "openclaw.external-session",
                status: "ok",
                startedAt: now,
                attributes: [
                    "agent_name": agentName,
                    "execution_status": ExecutionStatus.completed.rawValue,
                    "output_type": ExecutionOutputType.agentFinalResponse.rawValue,
                    "preview_text": "Success"
                ]
            )
            try insertSpan(
                db: db,
                projectID: projectID,
                spanID: UUID(),
                name: "Planner Session Failure",
                service: "multi-agent-flow.execution",
                status: "error",
                startedAt: yesterday,
                attributes: [
                    "agent_name": agentName,
                    "execution_status": ExecutionStatus.failed.rawValue,
                    "output_type": ExecutionOutputType.errorSummary.rawValue,
                    "preview_text": "Failure"
                ],
                events: "timeout"
            )
            try insertSpan(
                db: db,
                projectID: projectID,
                spanID: UUID(),
                name: "Ignored Session",
                service: "openclaw.external-session",
                status: "ok",
                startedAt: now,
                attributes: [
                    "agent_name": "Other Agent",
                    "execution_status": ExecutionStatus.completed.rawValue,
                    "output_type": ExecutionOutputType.agentFinalResponse.rawValue,
                    "preview_text": "Ignored"
                ]
            )

            try insertDailyAgentActivity(
                db: db,
                projectID: projectID,
                date: calendarDayString(for: yesterday),
                agentID: agentID,
                sessionCount: 0,
                memoryLogged: false
            )
            try insertDailyAgentActivity(
                db: db,
                projectID: projectID,
                date: calendarDayString(for: now),
                agentID: agentID,
                sessionCount: 2,
                memoryLogged: true
            )

            try insertCronRun(
                db: db,
                projectID: projectID,
                date: calendarDayString(for: now),
                cronName: "Planner heartbeat",
                status: "completed",
                jobID: "planner-ok",
                runID: UUID().uuidString,
                runAt: now,
                summary: "Planner cron healthy"
            )
            try insertCronRun(
                db: db,
                projectID: projectID,
                date: calendarDayString(for: yesterday),
                cronName: "project-cron",
                status: "failed",
                jobID: "planner-fail",
                runID: UUID().uuidString,
                runAt: yesterday,
                summary: "Planner timed out"
            )
            try insertCronRun(
                db: db,
                projectID: projectID,
                date: calendarDayString(for: now),
                cronName: "other-cron",
                status: "failed",
                jobID: "ignored-fail",
                runID: UUID().uuidString,
                runAt: now,
                summary: "Should be ignored"
            )
        }

        let history = service.scopedHistorySeries(
            projectID: projectID,
            days: 30,
            scopeKind: "agent",
            scopeValue: agentID.uuidString,
            scopeMatchKey: agentName.lowercased()
        )

        let workflowReliability = try XCTUnwrap(series(history, metric: .workflowReliability))
        XCTAssertEqual(workflowReliability.points.count, 2)
        XCTAssertEqual(try XCTUnwrap(workflowReliability.latestPoint).value, 100, accuracy: 0.001)

        let errorBudget = try XCTUnwrap(series(history, metric: .errorBudget))
        XCTAssertEqual(try XCTUnwrap(errorBudget.points.last).value, 1, accuracy: 0.001)

        let engagement = try XCTUnwrap(series(history, metric: .agentEngagement))
        XCTAssertEqual(engagement.points.count, 2)
        XCTAssertEqual(engagement.points.map(\.value), [0, 100])

        let memory = try XCTUnwrap(series(history, metric: .memoryDiscipline))
        XCTAssertEqual(memory.points.map(\.value), [0, 100])

        let cronReliability = try XCTUnwrap(series(history, metric: .cronReliability))
        XCTAssertEqual(cronReliability.points.count, 2)
        XCTAssertEqual(try XCTUnwrap(cronReliability.latestPoint).value, 100, accuracy: 0.001)
    }

    func testTraceDetailReturnsRootAttributesAndRelatedSpansInOrder() throws {
        let projectID = makeProjectID()
        try prepareEmptyAnalyticsDatabase(for: projectID)

        let rootID = UUID()
        let traceID = rootID.uuidString.replacingOccurrences(of: "-", with: "")
        let nodeID = UUID()
        let now = Date()

        try withDatabase(for: projectID) { db in
            try insertSpan(
                db: db,
                projectID: projectID,
                spanID: rootID,
                traceID: traceID,
                name: "Planner Root Session",
                service: "openclaw.external-session",
                status: "ok",
                startedAt: now,
                durationMs: 2_000,
                attributes: [
                    "agent_name": "Planner",
                    "execution_status": ExecutionStatus.completed.rawValue,
                    "output_type": ExecutionOutputType.agentFinalResponse.rawValue,
                    "routing_action": "fan_out",
                    "routing_reason": "Need specialist follow-up",
                    "routing_targets": "alpha,beta",
                    "node_id": nodeID.uuidString,
                    "preview_text": "Top-level summary",
                    "output_text": "Longer output body"
                ],
                events: "root events"
            )
            try insertSpan(
                db: db,
                projectID: projectID,
                spanID: UUID(),
                traceID: traceID,
                parentSpanID: rootID.uuidString,
                name: "Routing Decision",
                service: "openclaw.external-routing",
                status: "ok",
                startedAt: now.addingTimeInterval(1),
                durationMs: 50,
                attributes: [
                    "routing_action": "fan_out",
                    "routing_targets": "alpha,beta"
                ]
            )
            try insertSpan(
                db: db,
                projectID: projectID,
                spanID: UUID(),
                traceID: traceID,
                parentSpanID: rootID.uuidString,
                name: "Tool Result",
                service: "openclaw.external-tool-result",
                status: "error",
                startedAt: now.addingTimeInterval(2),
                durationMs: 125,
                attributes: [
                    "preview_text": "search.web: timeout",
                    "agent_name": "Planner"
                ],
                events: "timeout"
            )
        }

        let detail = try XCTUnwrap(service.traceDetail(projectID: projectID, traceID: rootID))
        XCTAssertEqual(detail.id, rootID)
        XCTAssertEqual(detail.traceID, traceID)
        XCTAssertEqual(detail.agentName, "Planner")
        XCTAssertEqual(detail.executionStatus, .completed)
        XCTAssertEqual(detail.outputType, .agentFinalResponse)
        XCTAssertEqual(detail.routingAction, "fan_out")
        XCTAssertEqual(detail.routingReason, "Need specialist follow-up")
        XCTAssertEqual(detail.routingTargets, ["alpha", "beta"])
        XCTAssertEqual(detail.nodeID, nodeID)
        XCTAssertEqual(detail.previewText, "Top-level summary")
        XCTAssertEqual(detail.outputText, "Longer output body")
        XCTAssertEqual(detail.eventsText, "root events")
        XCTAssertEqual(detail.relatedSpans.count, 2)
        XCTAssertEqual(detail.relatedSpans.map(\.name), ["Routing Decision", "Tool Result"])
        XCTAssertEqual(detail.relatedSpans.first?.summaryText, "fan_out -> alpha,beta")
        XCTAssertEqual(detail.relatedSpans.last?.summaryText, "search.web: timeout")
    }

    func testRefreshPersistsRuntimeProtocolMetadataForExecutionResults() throws {
        var project = makeProject(name: "Runtime Protocol Acceptance")
        try prepareEmptyAnalyticsDatabase(for: project.id)

        let agent = Agent(name: "Planner")
        project.agents = [agent]

        var node = WorkflowNode(type: .agent)
        node.agentID = agent.id
        node.title = "Planner Node"
        project.workflows[0].nodes = [node]

        let startedAt = Date().addingTimeInterval(-120)
        let completedAt = startedAt.addingTimeInterval(0.84)
        let artifactPath = "/tmp/runtime-artifact.md"

        let dispatchEvent = OpenClawRuntimeEvent(
            eventType: .taskDispatch,
            timestamp: startedAt,
            projectId: project.id.uuidString,
            workflowId: project.workflows[0].id.uuidString,
            nodeId: node.id.uuidString,
            runId: "runtime-acceptance-run",
            sessionKey: "session:runtime-acceptance",
            source: OpenClawRuntimeActor(kind: .user, agentId: "user", agentName: "User"),
            target: OpenClawRuntimeActor(kind: .agent, agentId: agent.id.uuidString, agentName: agent.name),
            transport: OpenClawRuntimeTransport(kind: .gatewayAgent, deploymentKind: "container"),
            payload: [
                "summary": "Drafted execution request",
                "intent": "respond",
                "protocolVersion": "openclaw.runtime.v1",
                "allowedActions": "stop,selected,all",
                "allowedTargets": "Reviewer [agent_id: reviewer, node: node-reviewer]",
                "approvalTargets": "Security Lead [agent_id: security, node: node-security]",
                "requiredOutputContract": #"{"workflow_route":{"action":"stop","targets":[],"reason":"short reason"}}"#,
                "selfCheckRule": "Validate the last non-empty line before sending.",
                "protocolFeedbackHints": "End with one valid routing JSON line. | Choose only allowed targets.",
                "sessionProtocolDigest": "agent=Planner | protocol=openclaw.runtime.v1 | role=worker | transport=gateway_agent | fallback=stop | approval_targets_present"
            ]
        )

        let resultEvent = OpenClawRuntimeEvent(
            eventType: .taskResult,
            timestamp: completedAt,
            projectId: project.id.uuidString,
            workflowId: project.workflows[0].id.uuidString,
            nodeId: node.id.uuidString,
            runId: "runtime-acceptance-run",
            sessionKey: "session:runtime-acceptance",
            parentEventId: dispatchEvent.id,
            source: OpenClawRuntimeActor(kind: .agent, agentId: agent.id.uuidString, agentName: agent.name),
            target: OpenClawRuntimeActor(kind: .orchestrator, agentId: "orchestrator", agentName: "Orchestrator"),
            transport: OpenClawRuntimeTransport(kind: .gatewayAgent, deploymentKind: "container"),
            payload: [
                "summary": "Prepared runtime summary",
                "outputType": ExecutionOutputType.agentFinalResponse.rawValue,
                "status": "success"
            ],
            refs: [
                OpenClawRuntimeRef(
                    refId: "artifact-1",
                    kind: .workspaceFile,
                    locator: "artifact://runtime-artifact",
                    path: artifactPath,
                    contentType: "text/markdown",
                    hash: "sha256:runtime-artifact"
                )
            ]
        )

        let routeEvent = OpenClawRuntimeEvent(
            eventType: .taskRoute,
            timestamp: completedAt,
            projectId: project.id.uuidString,
            workflowId: project.workflows[0].id.uuidString,
            nodeId: node.id.uuidString,
            runId: "runtime-acceptance-run",
            sessionKey: "session:runtime-acceptance",
            parentEventId: resultEvent.id,
            source: OpenClawRuntimeActor(kind: .agent, agentId: agent.id.uuidString, agentName: agent.name),
            target: OpenClawRuntimeActor(kind: .agent, agentId: "reviewer", agentName: "Reviewer"),
            transport: OpenClawRuntimeTransport(kind: .gatewayAgent, deploymentKind: "container"),
            payload: [
                "action": "selected",
                "reason": "Escalate for verification"
            ]
        )

        let result = ExecutionResult(
            nodeID: node.id,
            agentID: agent.id,
            status: .completed,
            output: "Detailed body\nWith trace context",
            outputType: .agentFinalResponse,
            sessionID: "runtime-acceptance-session",
            transportKind: "gateway_agent",
            firstChunkLatencyMs: 120,
            completionLatencyMs: 840,
            routingAction: "selected",
            routingTargets: ["Reviewer"],
            routingReason: "Escalate for verification",
            requestedRoutingAction: "selected",
            requestedRoutingTargets: ["Ghost Reviewer"],
            requestedRoutingReason: "Escalate for verification",
            protocolRepairCount: 1,
            protocolRepairTypes: ["invalid_targets_auto_selected"],
            protocolSafeDegradeApplied: true,
            runtimeEvents: [dispatchEvent, resultEvent, routeEvent],
            primaryRuntimeEvent: resultEvent,
            startedAt: startedAt,
            completedAt: completedAt
        )

        service.refresh(
            project: project,
            tasks: [],
            executionResults: [result],
            executionLogs: [],
            activeAgents: [:],
            isConnected: true
        )

        let traceRow = try XCTUnwrap(service.snapshot.traceRows.first(where: { $0.id == result.id }))
        XCTAssertEqual(traceRow.agentName, agent.name)
        XCTAssertEqual(traceRow.status, .completed)
        XCTAssertEqual(traceRow.outputType, .agentFinalResponse)
        XCTAssertEqual(traceRow.sourceLabel, "Runtime")
        XCTAssertEqual(traceRow.previewText, "Prepared runtime summary")

        let detail = try XCTUnwrap(service.traceDetail(projectID: project.id, traceID: result.id))
        XCTAssertEqual(detail.id, result.id)
        XCTAssertEqual(detail.service, "multi-agent-flow.execution")
        XCTAssertEqual(detail.agentName, agent.name)
        XCTAssertEqual(detail.executionStatus, .completed)
        XCTAssertEqual(detail.outputType, .agentFinalResponse)
        XCTAssertEqual(detail.routingAction, "selected")
        XCTAssertEqual(detail.routingReason, "Escalate for verification")
        XCTAssertEqual(detail.routingTargets, ["Reviewer"])
        XCTAssertEqual(detail.nodeID, node.id)
        XCTAssertEqual(detail.previewText, "Prepared runtime summary")
        XCTAssertEqual(detail.outputText, "Prepared runtime summary\n\nDetailed body\nWith trace context")
        XCTAssertEqual(detail.attributes["protocol_event_count"], "3")
        XCTAssertEqual(detail.attributes["protocol_ref_count"], "1")
        XCTAssertEqual(detail.attributes["protocol_event_types"], "task.dispatch, task.result, task.route")
        XCTAssertEqual(detail.attributes["requested_routing_action"], "selected")
        XCTAssertEqual(detail.attributes["requested_routing_targets"], "Ghost Reviewer")
        XCTAssertEqual(detail.attributes["requested_routing_reason"], "Escalate for verification")
        XCTAssertEqual(detail.attributes["protocol_repair_count"], "1")
        XCTAssertEqual(detail.attributes["protocol_repair_types"], "invalid_targets_auto_selected")
        XCTAssertEqual(
            detail.attributes["protocol_requested_route"],
            "selected | Ghost Reviewer | Escalate for verification"
        )
        XCTAssertEqual(
            detail.attributes["protocol_sanitized_route"],
            "selected | Reviewer | Escalate for verification"
        )
        XCTAssertEqual(detail.attributes["protocol_safe_degrade_applied"], "true")
        XCTAssertEqual(detail.attributes["transport_kind"], "gateway_agent")
        XCTAssertEqual(detail.attributes["session_id"], "runtime-acceptance-session")
        XCTAssertEqual(detail.eventsText?.components(separatedBy: "\n").count, 3)
        XCTAssertTrue(detail.eventsText?.contains("task.dispatch | User -> \(agent.name) | Drafted execution request") == true)
        XCTAssertTrue(detail.eventsText?.contains("task.result | \(agent.name) -> Orchestrator | Prepared runtime summary | refs: workspace_file: \(artifactPath)") == true)
        XCTAssertTrue(detail.eventsText?.contains("task.route | \(agent.name) -> Reviewer | Escalate for verification") == true)
    }

    func testProtocolOutcomeFeedbackPromotesRepeatedRepairsIntoAgentMemory() throws {
        var project = makeProject(name: "Protocol Feedback Memory")
        let agent = Agent(name: "Planner")
        project.agents = [agent]

        let digest = "agent=Planner | protocol=openclaw.runtime.v1 | role=worker | transport=gateway_agent | fallback=stop | no_approval_targets"
        let startedAt = Date().addingTimeInterval(-30)
        let dispatchEvent = OpenClawRuntimeEvent(
            eventType: .taskDispatch,
            timestamp: startedAt,
            projectId: project.id.uuidString,
            workflowId: project.workflows[0].id.uuidString,
            nodeId: UUID().uuidString,
            runId: "protocol-feedback-run",
            sessionKey: "session:protocol-feedback",
            source: OpenClawRuntimeActor(kind: .orchestrator, agentId: "workflow.executor", agentName: "Orchestrator"),
            target: OpenClawRuntimeActor(kind: .agent, agentId: agent.id.uuidString, agentName: agent.name),
            transport: OpenClawRuntimeTransport(kind: .gatewayAgent, deploymentKind: "container"),
            payload: [
                "summary": "Continue work",
                "sessionProtocolDigest": digest
            ]
        )
        let result = ExecutionResult(
            nodeID: UUID(),
            agentID: agent.id,
            status: .completed,
            output: "Completed",
            outputType: .agentFinalResponse,
            sessionID: "protocol-feedback-session",
            transportKind: "gateway_agent",
            routingAction: "selected",
            routingTargets: ["Reviewer"],
            requestedRoutingAction: "selected",
            requestedRoutingTargets: ["Unknown Agent"],
            requestedRoutingReason: "Need review",
            protocolRepairCount: 1,
            protocolRepairTypes: ["missing_route_auto_selected"],
            protocolSafeDegradeApplied: true,
            runtimeEvents: [dispatchEvent],
            primaryRuntimeEvent: dispatchEvent,
            startedAt: startedAt,
            completedAt: startedAt.addingTimeInterval(1)
        )

        for index in 0..<3 {
            AppState.recordProtocolOutcome(
                result,
                in: &project,
                at: startedAt.addingTimeInterval(TimeInterval(index))
            )
        }

        let memory = try XCTUnwrap(project.agents.first?.openClawDefinition.protocolMemory)
        XCTAssertEqual(memory.lastSessionDigest, digest)
        XCTAssertEqual(memory.recentCorrections.count, 1)
        XCTAssertEqual(memory.recentCorrections.first?.kind, "missing_route_auto_selected")
        XCTAssertEqual(memory.recentCorrections.first?.count, 3)
        XCTAssertEqual(memory.repeatOffenses.count, 1)
        XCTAssertEqual(memory.repeatOffenses.first?.kind, "missing_route_auto_selected")
        XCTAssertEqual(memory.repeatOffenses.first?.count, 1)
        XCTAssertTrue(
            memory.stableRules.contains(
                "Never omit the final routing JSON line when the protocol requires a machine tail."
            )
        )
    }

    func testRefreshPublishesProtocolHealthGoalCards() throws {
        var project = makeProject(name: "Protocol Goal Cards")
        let agent = Agent(name: "Planner")
        project.agents = [agent]

        let startedAt = Date().addingTimeInterval(-120)
        let conformingResult = ExecutionResult(
            nodeID: UUID(),
            agentID: agent.id,
            status: .completed,
            output: "Conforming",
            outputType: .agentFinalResponse,
            sessionID: "workflow-conforming",
            transportKind: "gateway_agent",
            startedAt: startedAt,
            completedAt: startedAt.addingTimeInterval(1)
        )
        let repairedResult = ExecutionResult(
            nodeID: UUID(),
            agentID: agent.id,
            status: .completed,
            output: "Repaired",
            outputType: .agentFinalResponse,
            sessionID: "workflow-repaired",
            transportKind: "gateway_agent",
            requestedRoutingAction: "selected",
            requestedRoutingTargets: ["Unknown Agent"],
            protocolRepairCount: 1,
            protocolRepairTypes: ["invalid_targets_auto_selected"],
            protocolSafeDegradeApplied: true,
            startedAt: startedAt.addingTimeInterval(5),
            completedAt: startedAt.addingTimeInterval(6)
        )
        let interruptedResult = ExecutionResult(
            nodeID: UUID(),
            agentID: agent.id,
            status: .failed,
            output: "Interrupted",
            outputType: .errorSummary,
            sessionID: "workflow-interrupted",
            transportKind: "gateway_agent",
            requestedRoutingAction: "selected",
            requestedRoutingTargets: ["Blocked Agent"],
            protocolRepairCount: 1,
            protocolRepairTypes: ["route_missing_approval_blocked"],
            protocolSafeDegradeApplied: false,
            startedAt: startedAt.addingTimeInterval(10),
            completedAt: startedAt.addingTimeInterval(11)
        )

        service.refresh(
            project: project,
            tasks: [],
            executionResults: [conformingResult, repairedResult, interruptedResult],
            executionLogs: [],
            activeAgents: [
                agent.id: OpenClawManager.ActiveAgentRuntime(
                    agentID: agent.id,
                    name: agent.name,
                    status: "active",
                    lastReloadedAt: startedAt
                )
            ],
            isConnected: true
        )

        let cardsByID = Dictionary(uniqueKeysWithValues: service.snapshot.goalCards.map { ($0.id, $0) })
        XCTAssertEqual(cardsByID["protocol_conformance"]?.valueText, "33%")
        XCTAssertEqual(cardsByID["protocol_conformance"]?.detailText, "1 of 3 runs executed without runtime repair")
        XCTAssertEqual(cardsByID["protocol_auto_repair"]?.valueText, "50%")
        XCTAssertEqual(cardsByID["protocol_auto_repair"]?.detailText, "1 of 2 repaired runs still completed")
        XCTAssertEqual(cardsByID["protocol_safe_degrade"]?.valueText, "100%")
        XCTAssertEqual(cardsByID["protocol_safe_degrade"]?.detailText, "1 of 1 safe-degrade runs still completed")
        XCTAssertEqual(cardsByID["protocol_interrupts"]?.valueText, "33%")
        XCTAssertEqual(cardsByID["protocol_interrupts"]?.detailText, "1 runs ended in unrecoverable protocol interruption")
    }

    func testRefreshPersistsProtocolGovernanceHistorySeries() throws {
        var project = makeProject(name: "Protocol History")
        try prepareEmptyAnalyticsDatabase(for: project.id)

        let agent = Agent(name: "Planner")
        project.agents = [agent]

        let startedAt = Date().addingTimeInterval(-180)
        let conformingResult = ExecutionResult(
            nodeID: UUID(),
            agentID: agent.id,
            status: .completed,
            output: "Conforming",
            outputType: .agentFinalResponse,
            sessionID: "workflow-history-conforming",
            transportKind: "gateway_agent",
            startedAt: startedAt,
            completedAt: startedAt.addingTimeInterval(1)
        )
        let repairedResult = ExecutionResult(
            nodeID: UUID(),
            agentID: agent.id,
            status: .completed,
            output: "Repaired",
            outputType: .agentFinalResponse,
            sessionID: "workflow-history-repaired",
            transportKind: "gateway_agent",
            requestedRoutingAction: "selected",
            requestedRoutingTargets: ["Unknown Agent"],
            protocolRepairCount: 1,
            protocolRepairTypes: ["invalid_targets_auto_selected"],
            protocolSafeDegradeApplied: true,
            startedAt: startedAt.addingTimeInterval(5),
            completedAt: startedAt.addingTimeInterval(6)
        )
        let interruptedResult = ExecutionResult(
            nodeID: UUID(),
            agentID: agent.id,
            status: .failed,
            output: "Interrupted",
            outputType: .errorSummary,
            sessionID: "workflow-history-interrupted",
            transportKind: "gateway_agent",
            requestedRoutingAction: "selected",
            requestedRoutingTargets: ["Blocked Agent"],
            protocolRepairCount: 1,
            protocolRepairTypes: ["route_missing_approval_blocked"],
            protocolSafeDegradeApplied: false,
            startedAt: startedAt.addingTimeInterval(10),
            completedAt: startedAt.addingTimeInterval(11)
        )

        service.refresh(
            project: project,
            tasks: [],
            executionResults: [conformingResult, repairedResult, interruptedResult],
            executionLogs: [],
            activeAgents: [:],
            isConnected: true
        )

        let conformance = try XCTUnwrap(series(service.snapshot.historicalSeries, metric: .protocolConformance))
        XCTAssertEqual(try XCTUnwrap(conformance.latestPoint).value, 100.0 / 3.0, accuracy: 0.001)

        let autoRepair = try XCTUnwrap(series(service.snapshot.historicalSeries, metric: .protocolAutoRepair))
        XCTAssertEqual(try XCTUnwrap(autoRepair.latestPoint).value, 50, accuracy: 0.001)

        let safeDegrade = try XCTUnwrap(series(service.snapshot.historicalSeries, metric: .protocolSafeDegrade))
        XCTAssertEqual(try XCTUnwrap(safeDegrade.latestPoint).value, 100, accuracy: 0.001)

        let hardInterrupts = try XCTUnwrap(series(service.snapshot.historicalSeries, metric: .protocolHardInterrupts))
        XCTAssertEqual(try XCTUnwrap(hardInterrupts.latestPoint).value, 100.0 / 3.0, accuracy: 0.001)
    }

    func testTraceDetailFallsBackToEventsWhenPreviewAndOutputAreMissing() throws {
        let project = makeProject(name: "Runtime Events Fallback")
        try prepareEmptyAnalyticsDatabase(for: project.id)

        let spanID = UUID()
        let traceID = spanID.uuidString.replacingOccurrences(of: "-", with: "")
        let startedAt = Date().addingTimeInterval(-45)
        let eventsText = """
        task.dispatch | User -> Planner | Drafted execution request
        task.result | Planner -> Orchestrator | Prepared runtime summary
        """

        try withDatabase(for: project.id) { db in
            try insertSpan(
                db: db,
                projectID: project.id,
                spanID: spanID,
                traceID: traceID,
                name: "Runtime Events Only",
                service: "multi-agent-flow.execution",
                status: "ok",
                startedAt: startedAt,
                durationMs: 320,
                attributes: [
                    "agent_name": "Planner",
                    "execution_status": ExecutionStatus.completed.rawValue,
                    "output_type": ExecutionOutputType.agentFinalResponse.rawValue
                ],
                events: eventsText
            )
        }

        service.refresh(
            project: project,
            tasks: [],
            executionResults: [],
            executionLogs: [],
            activeAgents: [:],
            isConnected: true
        )

        let traceRow = try XCTUnwrap(service.snapshot.traceRows.first(where: { $0.id == spanID }))
        XCTAssertEqual(traceRow.agentName, "Planner")
        XCTAssertEqual(traceRow.status, .completed)
        XCTAssertEqual(traceRow.outputType, .agentFinalResponse)
        XCTAssertEqual(traceRow.sourceLabel, "Runtime")
        XCTAssertEqual(traceRow.previewText, eventsText.compactSingleLinePreview(limit: 160))

        let detail = try XCTUnwrap(service.traceDetail(projectID: project.id, traceID: spanID))
        XCTAssertEqual(detail.id, spanID)
        XCTAssertEqual(detail.previewText, eventsText.compactSingleLinePreview(limit: 160))
        XCTAssertEqual(detail.outputText, eventsText)
        XCTAssertEqual(detail.eventsText, eventsText)
        XCTAssertNil(detail.attributes["preview_text"])
        XCTAssertNil(detail.attributes["output_text"])
    }

    func testRefreshSnapshotIncludesSortedAnomaliesAndLinkedCronMetadata() throws {
        var project = makeProject(name: "Ops Snapshot")
        try prepareEmptyAnalyticsDatabase(for: project.id)

        let now = Date()
        let sessionID = UUID().uuidString
        let backupRoot = try makeTemporaryDirectory(named: "openclaw-backup")
        project.openClaw.sessionBackupPath = backupRoot.path

        let timeoutDate = now.addingTimeInterval(-90)
        let cronDate = now.addingTimeInterval(-30)
        let cronFileURL = backupRoot
            .appendingPathComponent("cron", isDirectory: true)
            .appendingPathComponent("runs", isDirectory: true)
            .appendingPathComponent("nightly-sync.jsonl", isDirectory: false)
        let sessionFileURL = backupRoot
            .appendingPathComponent("agents", isDirectory: true)
            .appendingPathComponent("Scout", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent("\(sessionID).jsonl", isDirectory: false)

        try writeJSONLines(
            [
                [
                    "runAtMs": Int64(cronDate.timeIntervalSince1970 * 1000),
                    "ts": Int64(cronDate.timeIntervalSince1970 * 1000),
                    "sessionId": sessionID,
                    "jobId": "job-failed",
                    "status": "failed",
                    "error": "Nightly sync failed",
                    "summary": "Nightly sync failed",
                    "durationMs": 8200,
                    "sessionKey": "cron:agent:nightly-sync"
                ]
            ],
            to: cronFileURL
        )
        try writeJSONLines(
            [
                [
                    "type": "session",
                    "id": sessionID,
                    "timestamp": iso8601.string(from: timeoutDate.addingTimeInterval(-5)),
                    "cwd": "/tmp/scout"
                ],
                [
                    "type": "custom",
                    "customType": "model-snapshot",
                    "data": [
                        "provider": "OpenAI",
                        "modelId": "gpt-5.4"
                    ]
                ],
                [
                    "type": "message",
                    "message": [
                        "role": "user",
                        "timestamp": Int64(timeoutDate.addingTimeInterval(-3).timeIntervalSince1970 * 1000),
                        "content": [
                            [
                                "type": "text",
                                "text": "Investigate the nightly sync failure."
                            ]
                        ]
                    ]
                ],
                [
                    "type": "message",
                    "message": [
                        "role": "assistant",
                        "timestamp": Int64(timeoutDate.addingTimeInterval(-2).timeIntervalSince1970 * 1000),
                        "content": [
                            [
                                "type": "toolCall",
                                "name": "search.web",
                                "arguments": [
                                    "query": "nightly sync status"
                                ]
                            ]
                        ]
                    ]
                ],
                [
                    "type": "message",
                    "message": [
                        "role": "toolResult",
                        "toolName": "search.web",
                        "isError": true,
                        "timestamp": Int64(timeoutDate.timeIntervalSince1970 * 1000),
                        "content": [
                            [
                                "type": "text",
                                "text": "Provider unavailable"
                            ]
                        ],
                        "details": [
                            "status": 504
                        ]
                    ]
                ]
            ],
            to: sessionFileURL
        )

        service.refresh(
            project: project,
            tasks: [],
            executionResults: [],
            executionLogs: [],
            activeAgents: [:],
            isConnected: true
        )

        let anomalyRows = service.snapshot.anomalyRows
        XCTAssertEqual(anomalyRows.count, 3)
        XCTAssertEqual(anomalyRows.map(\.sourceLabel), ["Cron", "Tool", "OpenClaw"])
        XCTAssertEqual(anomalyRows.map(\.title), ["Cron / nightly-sync", "Tool Result", "Scout"])

        let cronAnomaly = try XCTUnwrap(anomalyRows.first)
        XCTAssertEqual(cronAnomaly.relatedJobID, "job-failed")
        XCTAssertEqual(cronAnomaly.relatedRunID, sessionID)
        XCTAssertEqual(
            cronAnomaly.relatedSourcePath.map { URL(fileURLWithPath: $0).standardizedFileURL.path },
            cronFileURL.standardizedFileURL.path
        )
        XCTAssertEqual(cronAnomaly.linkedSessionSpanID, UUID(uuidString: sessionID))

        let summary = try XCTUnwrap(service.snapshot.anomalySummary)
        XCTAssertEqual(summary.cronFailures24h, 1)
        XCTAssertEqual(summary.cronFailures7d, 1)
        XCTAssertEqual(summary.toolFailures24h, 1)
        XCTAssertEqual(summary.toolFailures7d, 1)
        XCTAssertEqual(summary.timeoutCount7d, 0)
    }

    func testRefreshIngestsExternalSessionBackupIntoTraceDetail() throws {
        var project = makeProject(name: "OpenClaw Trace")
        try prepareEmptyAnalyticsDatabase(for: project.id)

        let backupRoot = try makeTemporaryDirectory(named: "openclaw-trace")
        project.openClaw.sessionBackupPath = backupRoot.path

        let sessionID = UUID().uuidString
        let sessionUUID = try XCTUnwrap(UUID(uuidString: sessionID))
        let startedAt = Date().addingTimeInterval(-600)
        let userAt = startedAt.addingTimeInterval(5)
        let assistantToolCallAt = startedAt.addingTimeInterval(10)
        let toolResultAt = startedAt.addingTimeInterval(12)
        let assistantFinalAt = startedAt.addingTimeInterval(18)
        let sessionFileURL = backupRoot
            .appendingPathComponent("agents", isDirectory: true)
            .appendingPathComponent("Scout", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent("\(sessionID).jsonl", isDirectory: false)

        try writeJSONLines(
            [
                [
                    "type": "session",
                    "id": sessionID,
                    "timestamp": iso8601.string(from: startedAt),
                    "cwd": "/tmp/scout-workspace"
                ],
                [
                    "type": "model_change",
                    "provider": "OpenAI",
                    "modelId": "gpt-5.4"
                ],
                [
                    "type": "message",
                    "message": [
                        "role": "user",
                        "timestamp": Int64(userAt.timeIntervalSince1970 * 1000),
                        "content": [
                            [
                                "type": "text",
                                "text": "Investigate the nightly sync failure."
                            ]
                        ]
                    ]
                ],
                [
                    "type": "message",
                    "message": [
                        "role": "assistant",
                        "timestamp": Int64(assistantToolCallAt.timeIntervalSince1970 * 1000),
                        "content": [
                            [
                                "type": "toolCall",
                                "name": "search.web",
                                "arguments": [
                                    "query": "nightly sync root cause"
                                ]
                            ]
                        ]
                    ]
                ],
                [
                    "type": "message",
                    "message": [
                        "role": "toolResult",
                        "toolName": "search.web",
                        "isError": false,
                        "timestamp": Int64(toolResultAt.timeIntervalSince1970 * 1000),
                        "content": [
                            [
                                "type": "text",
                                "text": "3 relevant notes found."
                            ]
                        ],
                        "details": [
                            "matches": 3
                        ]
                    ]
                ],
                [
                    "type": "message",
                    "message": [
                        "role": "assistant",
                        "timestamp": Int64(assistantFinalAt.timeIntervalSince1970 * 1000),
                        "content": [
                            [
                                "type": "text",
                                "text": "I found 3 likely causes."
                            ]
                        ]
                    ]
                ]
            ],
            to: sessionFileURL
        )

        service.refresh(
            project: project,
            tasks: [],
            executionResults: [],
            executionLogs: [],
            activeAgents: [:],
            isConnected: true
        )

        let traceRow = try XCTUnwrap(service.snapshot.traceRows.first(where: { $0.id == sessionUUID }))
        XCTAssertEqual(traceRow.agentName, "Scout")
        XCTAssertEqual(traceRow.status, .completed)
        XCTAssertEqual(traceRow.outputType, .agentFinalResponse)
        XCTAssertEqual(traceRow.sourceLabel, "OpenClaw")
        XCTAssertEqual(traceRow.previewText, "I found 3 likely causes.")

        let detail = try XCTUnwrap(service.traceDetail(projectID: project.id, traceID: sessionUUID))
        XCTAssertEqual(detail.id, sessionUUID)
        XCTAssertEqual(detail.service, "openclaw.external-session")
        XCTAssertEqual(detail.agentName, "Scout")
        XCTAssertEqual(detail.executionStatus, .completed)
        XCTAssertEqual(detail.outputType, .agentFinalResponse)
        XCTAssertEqual(detail.previewText, "I found 3 likely causes.")
        XCTAssertEqual(detail.outputText, "I found 3 likely causes.")
        XCTAssertEqual(detail.attributes["provider"], "OpenAI")
        XCTAssertEqual(detail.attributes["model"], "gpt-5.4")
        XCTAssertEqual(detail.attributes["cwd"], "/tmp/scout-workspace")
        XCTAssertEqual(
            detail.attributes["session_path"].map { URL(fileURLWithPath: $0).standardizedFileURL.path },
            sessionFileURL.standardizedFileURL.path
        )
        XCTAssertEqual(
            detail.eventsText,
            "User messages: 1\nAssistant messages: 2\nTool calls: 1\nTool errors: 0\nModel: gpt-5.4\nProvider: OpenAI"
        )
        XCTAssertEqual(
            detail.relatedSpans.map(\.name),
            ["User Prompt", "Assistant Turn", "Tool Call", "Tool Result", "Assistant Turn"]
        )
        XCTAssertEqual(
            detail.relatedSpans.map(\.summaryText),
            [
                "Investigate the nightly sync failure.",
                "Requested 1 tool call(s)",
                "search.web: {\"query\":\"nightly sync root cause\"}",
                "search.web: 3 relevant notes found.",
                "I found 3 likely causes."
            ]
        )
    }

    func testRefreshDeduplicatesEquivalentOpenClawBackupRoots() throws {
        var project = makeProject(name: "OpenClaw Duplicate Backup Root")
        try prepareEmptyAnalyticsDatabase(for: project.id)

        let backupRoot = ProjectManager.shared.openClawBackupDirectory(for: project.id)
        let projectRoot = ProjectManager.shared.openClawProjectRoot(for: project.id)
        defer { try? FileManager.default.removeItem(at: projectRoot) }

        try FileManager.default.createDirectory(at: backupRoot, withIntermediateDirectories: true)
        project.openClaw.sessionBackupPath = backupRoot.appendingPathComponent(".", isDirectory: true).path

        let sessionID = UUID().uuidString
        let sessionUUID = try XCTUnwrap(UUID(uuidString: sessionID))
        let startedAt = Date().addingTimeInterval(-120)
        let sessionFileURL = backupRoot
            .appendingPathComponent("agents", isDirectory: true)
            .appendingPathComponent("Scout", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent("\(sessionID).jsonl", isDirectory: false)

        try writeJSONLines(
            [
                [
                    "type": "session",
                    "id": sessionID,
                    "timestamp": iso8601.string(from: startedAt),
                    "cwd": "/tmp/scout-dedup"
                ],
                [
                    "type": "message",
                    "message": [
                        "role": "assistant",
                        "timestamp": Int64(startedAt.addingTimeInterval(3).timeIntervalSince1970 * 1000),
                        "content": [
                            [
                                "type": "text",
                                "text": "Single ingest only."
                            ]
                        ]
                    ]
                ]
            ],
            to: sessionFileURL
        )

        service.refresh(
            project: project,
            tasks: [],
            executionResults: [],
            executionLogs: [],
            activeAgents: [:],
            isConnected: true
        )

        let matchingRows = service.snapshot.traceRows.filter { $0.id == sessionUUID }
        XCTAssertEqual(matchingRows.count, 1)
        XCTAssertEqual(matchingRows.first?.previewText, "Single ingest only.")
    }

    func testToolDetailFromExternalSessionLinksToChildTraceDetail() throws {
        var project = makeProject(name: "OpenClaw Tool Detail")
        try prepareEmptyAnalyticsDatabase(for: project.id)

        let backupRoot = try makeTemporaryDirectory(named: "openclaw-tool-detail")
        project.openClaw.sessionBackupPath = backupRoot.path

        let sessionID = UUID().uuidString
        let startedAt = Date().addingTimeInterval(-300)
        let assistantToolCallAt = startedAt.addingTimeInterval(8)
        let toolResultAt = startedAt.addingTimeInterval(12)
        let sessionFileURL = backupRoot
            .appendingPathComponent("agents", isDirectory: true)
            .appendingPathComponent("Scout", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent("\(sessionID).jsonl", isDirectory: false)

        try writeJSONLines(
            [
                [
                    "type": "session",
                    "id": sessionID,
                    "timestamp": iso8601.string(from: startedAt),
                    "cwd": "/tmp/scout-tool"
                ],
                [
                    "type": "message",
                    "message": [
                        "role": "assistant",
                        "timestamp": Int64(assistantToolCallAt.timeIntervalSince1970 * 1000),
                        "content": [
                            [
                                "type": "toolCall",
                                "name": "search.web",
                                "arguments": [
                                    "query": "deep failure analysis"
                                ]
                            ]
                        ]
                    ]
                ],
                [
                    "type": "message",
                    "message": [
                        "role": "toolResult",
                        "toolName": "search.web",
                        "isError": true,
                        "timestamp": Int64(toolResultAt.timeIntervalSince1970 * 1000),
                        "content": [
                            [
                                "type": "text",
                                "text": "Provider unavailable"
                            ]
                        ],
                        "details": [
                            "status": 503,
                            "retryable": true
                        ]
                    ]
                ]
            ],
            to: sessionFileURL
        )

        service.refresh(
            project: project,
            tasks: [],
            executionResults: [],
            executionLogs: [],
            activeAgents: [:],
            isConnected: true
        )

        let toolDetail = try XCTUnwrap(
            service.toolDetail(
                projectID: project.id,
                toolIdentifier: "search.web",
                days: 30,
                spanLimit: 10,
                anomalyLimit: 10
            )
        )

        XCTAssertEqual(toolDetail.spans.map(\.title), ["Tool Result", "Tool Call"])
        XCTAssertEqual(toolDetail.spans.map(\.service), ["openclaw.external-tool-result", "openclaw.external-tool-call"])
        XCTAssertEqual(toolDetail.anomalies.count, 1)

        let anomaly = try XCTUnwrap(toolDetail.anomalies.first)
        XCTAssertEqual(anomaly.sourceLabel, "Tool")
        XCTAssertEqual(anomaly.status, .critical)
        XCTAssertEqual(anomaly.statusText, "error")
        XCTAssertEqual(anomaly.fullDetailText, "Provider unavailable\n\n{\"retryable\":true,\"status\":503}")

        let linkedSpanID = try XCTUnwrap(anomaly.linkedSpanID)
        XCTAssertEqual(linkedSpanID, toolDetail.spans.first?.id)

        let traceDetail = try XCTUnwrap(service.traceDetail(projectID: project.id, traceID: linkedSpanID))
        XCTAssertEqual(traceDetail.service, "openclaw.external-tool-result")
        XCTAssertEqual(traceDetail.agentName, "Scout")
        XCTAssertEqual(traceDetail.statusText, "error")
        XCTAssertEqual(traceDetail.previewText, "search.web: Provider unavailable")
        XCTAssertEqual(traceDetail.outputText, "Provider unavailable\n\n{\"retryable\":true,\"status\":503}")
        XCTAssertEqual(traceDetail.eventsText, "Provider unavailable\n\n{\"retryable\":true,\"status\":503}")
        XCTAssertEqual(traceDetail.attributes["tool_name"], "search.web")
        XCTAssertEqual(traceDetail.relatedSpans.map(\.name), ["Scout", "Assistant Turn", "Tool Call"])
        XCTAssertEqual(traceDetail.relatedSpans.last?.summaryText, "search.web: {\"query\":\"deep failure analysis\"}")
    }

    func testToolDetailTreatsTimeoutSignalsAsWarningAnomalies() throws {
        let projectID = makeProjectID()
        try prepareEmptyAnalyticsDatabase(for: projectID)

        let now = Date()

        try withDatabase(for: projectID) { db in
            try insertSpan(
                db: db,
                projectID: projectID,
                spanID: UUID(),
                name: "Search Timeout",
                service: "openclaw.external-tool-result",
                status: "ok",
                startedAt: now,
                durationMs: 1_200,
                attributes: [
                    "agent_name": "Scout",
                    "tool_name": "search.web",
                    "preview_text": "Request retried",
                    "provider_status": "timeout"
                ],
                events: "provider timeout"
            )
        }

        let detail = try XCTUnwrap(
            service.toolDetail(
                projectID: projectID,
                toolIdentifier: "search.web",
                days: 30,
                spanLimit: 10,
                anomalyLimit: 10
            )
        )

        let anomaly = try XCTUnwrap(detail.anomalies.first)
        XCTAssertEqual(detail.anomalies.count, 1)
        XCTAssertEqual(anomaly.title, "Search Timeout")
        XCTAssertEqual(anomaly.status, .warning)
        XCTAssertEqual(anomaly.statusText, "ok")
        XCTAssertEqual(anomaly.sourceLabel, "Tool")
        XCTAssertEqual(anomaly.fullDetailText, "provider timeout")
        XCTAssertNotNil(anomaly.linkedSpanID)
    }

    func testCronAnomalyRunMatcherPrefersExplicitRunIDOverTimeFallback() {
        let now = Date()
        let matchedRunID = UUID().uuidString
        let exactRun = makeCronRunRow(
            cronName: "nightly-sync",
            statusText: "FAILED",
            runAt: now.addingTimeInterval(-300),
            summaryText: "Older matching run",
            jobID: "job-exact",
            runID: matchedRunID,
            sourcePath: "/tmp/exact.jsonl"
        )
        let timeNearbyRun = makeCronRunRow(
            cronName: "nightly-sync",
            statusText: "FAILED",
            runAt: now,
            summaryText: "Time fallback run",
            jobID: "job-nearby",
            runID: UUID().uuidString,
            sourcePath: "/tmp/nearby.jsonl"
        )
        let anomaly = OpsAnomalyRow(
            id: "cron-anomaly",
            title: "nightly-sync",
            sourceLabel: "Cron",
            detailText: "Nightly sync failed",
            fullDetailText: "Nightly sync failed",
            occurredAt: now,
            status: .critical,
            statusText: "FAILED",
            sourceService: nil,
            linkedSpanID: nil,
            relatedRunID: matchedRunID,
            relatedJobID: nil,
            relatedSourcePath: nil
        )

        let match = OpsCronAnomalyRunMatcher.matchingRun(for: anomaly, in: [timeNearbyRun, exactRun])

        XCTAssertEqual(match?.id, exactRun.id)
    }

    func testCronAnomalyRunMatcherFallsBackToJobIDAndSourcePath() {
        let now = Date()
        let sourcePath = "/tmp/cron/job-42.jsonl"
        let sourceMatchedRun = makeCronRunRow(
            cronName: "nightly-sync",
            statusText: "FAILED",
            runAt: now.addingTimeInterval(-600),
            summaryText: "Source path match",
            jobID: "job-42",
            runID: UUID().uuidString,
            sourcePath: sourcePath
        )
        let unrelatedRun = makeCronRunRow(
            cronName: "nightly-sync",
            statusText: "FAILED",
            runAt: now,
            summaryText: "Unrelated fallback",
            jobID: "job-other",
            runID: UUID().uuidString,
            sourcePath: "/tmp/other.jsonl"
        )

        let jobAnomaly = OpsAnomalyRow(
            id: "cron-job",
            title: "nightly-sync",
            sourceLabel: "Cron",
            detailText: "Job based match",
            fullDetailText: "Job based match",
            occurredAt: now,
            status: .critical,
            statusText: "FAILED",
            sourceService: nil,
            linkedSpanID: nil,
            relatedRunID: nil,
            relatedJobID: "job-42",
            relatedSourcePath: nil
        )
        let sourceAnomaly = OpsAnomalyRow(
            id: "cron-source",
            title: "nightly-sync",
            sourceLabel: "Cron",
            detailText: "Source based match",
            fullDetailText: "Source based match",
            occurredAt: now,
            status: .critical,
            statusText: "FAILED",
            sourceService: nil,
            linkedSpanID: nil,
            relatedRunID: nil,
            relatedJobID: nil,
            relatedSourcePath: sourcePath
        )

        XCTAssertEqual(
            OpsCronAnomalyRunMatcher.matchingRun(for: jobAnomaly, in: [unrelatedRun, sourceMatchedRun])?.id,
            sourceMatchedRun.id
        )
        XCTAssertEqual(
            OpsCronAnomalyRunMatcher.matchingRun(for: sourceAnomaly, in: [unrelatedRun, sourceMatchedRun])?.id,
            sourceMatchedRun.id
        )
    }

    func testCronAnomalyRunMatcherFallsBackToTimeThenSummary() {
        let now = Date(timeIntervalSinceReferenceDate: 600)
        let minuteMatchedRun = makeCronRunRow(
            cronName: "nightly-sync",
            statusText: "FAILED",
            runAt: now.addingTimeInterval(20),
            summaryText: "Not the summary fallback",
            jobID: "job-minute",
            runID: UUID().uuidString,
            sourcePath: nil
        )
        let summaryMatchedRun = makeCronRunRow(
            cronName: "nightly-sync",
            statusText: "FAILED",
            runAt: now.addingTimeInterval(-7200),
            summaryText: "Nightly sync failed hard",
            jobID: "job-summary",
            runID: UUID().uuidString,
            sourcePath: nil
        )

        let timeAnomaly = OpsAnomalyRow(
            id: "cron-time",
            title: "nightly-sync",
            sourceLabel: "Cron",
            detailText: "Different text",
            fullDetailText: "Different text",
            occurredAt: now,
            status: .critical,
            statusText: "FAILED",
            sourceService: nil,
            linkedSpanID: nil
        )
        let summaryAnomaly = OpsAnomalyRow(
            id: "cron-summary",
            title: "nightly-sync",
            sourceLabel: "Cron",
            detailText: "Nightly sync failed hard",
            fullDetailText: "Nightly sync failed hard",
            occurredAt: now.addingTimeInterval(-86400),
            status: .critical,
            statusText: "FAILED",
            sourceService: nil,
            linkedSpanID: nil
        )

        XCTAssertEqual(
            OpsCronAnomalyRunMatcher.matchingRun(for: timeAnomaly, in: [summaryMatchedRun, minuteMatchedRun])?.id,
            minuteMatchedRun.id
        )
        XCTAssertEqual(
            OpsCronAnomalyRunMatcher.matchingRun(for: summaryAnomaly, in: [minuteMatchedRun, summaryMatchedRun])?.id,
            summaryMatchedRun.id
        )
    }

    func testAnomalyClusterBuilderGroupsEscalatesAndSortsClusters() throws {
        let now = Date()
        let toolLinkedID = UUID()
        let olderLinkedID = UUID()

        let clusters = OpsAnomalyClusterBuilder.clusters(
            from: [
                makeAnomalyRow(
                    id: "tool-warning-old",
                    title: "Search Timeout",
                    sourceLabel: "Tool",
                    detailText: "Provider timeout",
                    fullDetailText: "Provider timeout after retry",
                    occurredAt: now.addingTimeInterval(-28 * 3600),
                    status: .warning,
                    statusText: "timeout",
                    sourceService: "openclaw.external-tool-result",
                    linkedSpanID: olderLinkedID
                ),
                makeAnomalyRow(
                    id: "tool-critical-new",
                    title: "Search Timeout",
                    sourceLabel: "Tool",
                    detailText: "Provider unavailable",
                    fullDetailText: "Provider unavailable",
                    occurredAt: now.addingTimeInterval(-15 * 60),
                    status: .critical,
                    statusText: "error",
                    sourceService: "openclaw.external-tool-result",
                    linkedSpanID: toolLinkedID
                ),
                makeAnomalyRow(
                    id: "tool-warning-mid",
                    title: "Search Timeout",
                    sourceLabel: "Tool",
                    detailText: "Provider timeout",
                    fullDetailText: "Provider timeout",
                    occurredAt: now.addingTimeInterval(-2 * 3600),
                    status: .warning,
                    statusText: "timeout",
                    sourceService: "openclaw.external-tool-result",
                    linkedSpanID: nil
                ),
                makeAnomalyRow(
                    id: "runtime-warning-new",
                    title: "Planner Drift",
                    sourceLabel: "Runtime",
                    detailText: "Planner exceeded budget",
                    fullDetailText: "Planner exceeded budget",
                    occurredAt: now.addingTimeInterval(-5 * 60),
                    status: .warning,
                    statusText: "warning",
                    sourceService: "multi-agent-flow.execution",
                    linkedSpanID: nil
                ),
                makeAnomalyRow(
                    id: "runtime-warning-old",
                    title: "Planner Drift",
                    sourceLabel: "Runtime",
                    detailText: "Planner exceeded budget",
                    fullDetailText: "Planner exceeded budget",
                    occurredAt: now.addingTimeInterval(-7 * 3600),
                    status: .warning,
                    statusText: "warning",
                    sourceService: "multi-agent-flow.execution",
                    linkedSpanID: nil
                ),
                makeAnomalyRow(
                    id: "cron-warning",
                    title: "Nightly Sync Failed",
                    sourceLabel: "Cron",
                    detailText: "Job timed out",
                    fullDetailText: "Job timed out",
                    occurredAt: now.addingTimeInterval(-3 * 60),
                    status: .warning,
                    statusText: "timeout",
                    sourceService: nil,
                    linkedSpanID: nil
                )
            ],
            now: now
        )

        XCTAssertEqual(clusters.map(\.title), ["Search Timeout", "Planner Drift", "Nightly Sync Failed"])

        let firstCluster = try XCTUnwrap(clusters.first)
        XCTAssertEqual(firstCluster.occurrenceCount, 3)
        XCTAssertEqual(firstCluster.status, .critical)
        XCTAssertEqual(firstCluster.recent24HourCount, 2)
        XCTAssertEqual(firstCluster.linkedTraceCount, 2)
        XCTAssertEqual(firstCluster.sampleDetail, "Provider unavailable")
        XCTAssertEqual(firstCluster.latestAnomaly.id, "tool-critical-new")
    }

    func testAnomalyClusterBuilderAppliesFiltersSearchAndWindow() {
        let now = Date()
        let windowStart = now.addingTimeInterval(-3 * 24 * 3600)

        let filteredRows = OpsAnomalyClusterBuilder.filteredRows(
            from: [
                makeAnomalyRow(
                    id: "tool-warning-match",
                    title: "Search Timeout",
                    sourceLabel: "Tool",
                    detailText: "Provider timeout while searching",
                    fullDetailText: "Provider timeout while searching",
                    occurredAt: now.addingTimeInterval(-2 * 3600),
                    status: .warning,
                    statusText: "timeout",
                    sourceService: "openclaw.external-tool-result",
                    linkedSpanID: nil
                ),
                makeAnomalyRow(
                    id: "tool-warning-old",
                    title: "Search Timeout",
                    sourceLabel: "Tool",
                    detailText: "Provider timeout while searching",
                    fullDetailText: "Provider timeout while searching",
                    occurredAt: now.addingTimeInterval(-5 * 24 * 3600),
                    status: .warning,
                    statusText: "timeout",
                    sourceService: "openclaw.external-tool-result",
                    linkedSpanID: nil
                ),
                makeAnomalyRow(
                    id: "tool-critical",
                    title: "Search Timeout",
                    sourceLabel: "Tool",
                    detailText: "Provider timeout while searching",
                    fullDetailText: "Provider timeout while searching",
                    occurredAt: now.addingTimeInterval(-90 * 60),
                    status: .critical,
                    statusText: "error",
                    sourceService: "openclaw.external-tool-result",
                    linkedSpanID: nil
                ),
                makeAnomalyRow(
                    id: "runtime-warning",
                    title: "Search Timeout",
                    sourceLabel: "Runtime",
                    detailText: "Provider timeout while searching",
                    fullDetailText: "Provider timeout while searching",
                    occurredAt: now.addingTimeInterval(-30 * 60),
                    status: .warning,
                    statusText: "timeout",
                    sourceService: "multi-agent-flow.execution",
                    linkedSpanID: nil
                ),
                makeAnomalyRow(
                    id: "tool-warning-no-search",
                    title: "Search Provider Error",
                    sourceLabel: "Tool",
                    detailText: "Provider unavailable",
                    fullDetailText: "Provider unavailable",
                    occurredAt: now.addingTimeInterval(-20 * 60),
                    status: .warning,
                    statusText: "warning",
                    sourceService: "openclaw.external-tool-result",
                    linkedSpanID: nil
                )
            ],
            sourceFilter: .tool,
            severityFilter: .warning,
            searchText: " timeout ",
            windowStart: windowStart
        )

        XCTAssertEqual(filteredRows.map(\.id), ["tool-warning-match"])

        let clusters = OpsAnomalyClusterBuilder.clusteredRows(
            from: filteredRows,
            now: now
        )

        XCTAssertEqual(clusters.count, 1)
        XCTAssertEqual(clusters.first?.title, "Search Timeout")
        XCTAssertEqual(clusters.first?.status, .warning)
    }

    func testAnomalyClusterBuilderFallsBackToStableIDOrderingForTies() {
        let now = Date()
        let clusters = OpsAnomalyClusterBuilder.clusters(
            from: [
                makeAnomalyRow(
                    id: "beta",
                    title: "Beta Issue",
                    sourceLabel: "Runtime",
                    detailText: "Same timestamp",
                    fullDetailText: "Same timestamp",
                    occurredAt: now,
                    status: .warning,
                    statusText: "warning",
                    sourceService: "multi-agent-flow.execution",
                    linkedSpanID: nil
                ),
                makeAnomalyRow(
                    id: "alpha",
                    title: "Alpha Issue",
                    sourceLabel: "Runtime",
                    detailText: "Same timestamp",
                    fullDetailText: "Same timestamp",
                    occurredAt: now,
                    status: .warning,
                    statusText: "warning",
                    sourceService: "multi-agent-flow.execution",
                    linkedSpanID: nil
                )
            ],
            now: now
        )

        XCTAssertEqual(clusters.map(\.id), [
            "runtime::multi-agent-flow.execution::alpha issue",
            "runtime::multi-agent-flow.execution::beta issue"
        ])
    }

    func testHistoryInsightBuilderBuildsWorkflowContextCards() {
        let cards = OpsHistoryInsightBuilder.contextCards(
            metric: .workflowReliability,
            focusTitle: "Planner",
            totalAgents: 5,
            traceRows: [
                makeTraceRow(
                    agentName: "Planner",
                    status: .failed,
                    startedAt: Date(),
                    sourceLabel: "Runtime",
                    previewText: "Runtime failed"
                ),
                makeTraceRow(
                    agentName: "Planner",
                    status: .completed,
                    startedAt: Date(),
                    sourceLabel: "OpenClaw",
                    previewText: "Recovered"
                )
            ],
            anomalyRows: [
                makeAnomalyRow(
                    id: "runtime",
                    title: "Planner Error",
                    sourceLabel: "Runtime",
                    detailText: "Runtime issue",
                    fullDetailText: "Runtime issue",
                    occurredAt: Date(),
                    status: .critical,
                    statusText: "error",
                    sourceService: "multi-agent-flow.execution",
                    linkedSpanID: nil
                ),
                makeAnomalyRow(
                    id: "tool",
                    title: "Search Timeout",
                    sourceLabel: "Tool",
                    detailText: "Tool issue",
                    fullDetailText: "Tool issue",
                    occurredAt: Date(),
                    status: .warning,
                    statusText: "timeout",
                    sourceService: "openclaw.external-tool-result",
                    linkedSpanID: nil
                ),
                makeAnomalyRow(
                    id: "cron",
                    title: "Nightly Sync",
                    sourceLabel: "Cron",
                    detailText: "Cron issue",
                    fullDetailText: "Cron issue",
                    occurredAt: Date(),
                    status: .warning,
                    statusText: "timeout",
                    sourceService: nil,
                    linkedSpanID: nil
                )
            ],
            agentRows: [],
            cronRuns: []
        )

        XCTAssertEqual(cards.map(\.id), ["wf-failed", "wf-openclaw", "wf-runtime"])
        XCTAssertEqual(cards.map(\.value), ["1", "1", "2"])
        XCTAssertEqual(cards.map(\.tone), [.red, .teal, .orange])
        XCTAssertEqual(cards.first?.detail, "Planner traces in current scope")
    }

    func testHistoryInsightBuilderBuildsWorkflowSignalRowsInDescendingTimeOrder() {
        let now = Date()
        let failedTrace = makeTraceRow(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111") ?? UUID(),
            agentName: "Planner",
            status: .failed,
            startedAt: now.addingTimeInterval(-120),
            sourceLabel: "OpenClaw",
            previewText: "Trace failed"
        )
        let rows = OpsHistoryInsightBuilder.signalRows(
            metric: .workflowReliability,
            anomalyRows: [
                makeAnomalyRow(
                    id: "runtime-new",
                    title: "Planner Drift",
                    sourceLabel: "Runtime",
                    detailText: "Budget exceeded",
                    fullDetailText: "Budget exceeded",
                    occurredAt: now.addingTimeInterval(-60),
                    status: .warning,
                    statusText: "warning",
                    sourceService: "multi-agent-flow.execution",
                    linkedSpanID: nil
                ),
                makeAnomalyRow(
                    id: "cron-old",
                    title: "Nightly Sync Failed",
                    sourceLabel: "Cron",
                    detailText: "Should be excluded",
                    fullDetailText: "Should be excluded",
                    occurredAt: now.addingTimeInterval(-30),
                    status: .critical,
                    statusText: "error",
                    sourceService: nil,
                    linkedSpanID: nil
                )
            ],
            traceRows: [
                failedTrace,
                makeTraceRow(
                    agentName: "Planner",
                    status: .completed,
                    startedAt: now.addingTimeInterval(-10),
                    sourceLabel: "Runtime",
                    previewText: "Completed trace should be ignored"
                )
            ],
            agentRows: [],
            cronRuns: []
        )

        XCTAssertEqual(rows.map(\.id), ["anomaly-runtime-new", "trace-\(failedTrace.id.uuidString)"])
        XCTAssertEqual(rows.map(\.badge), ["Runtime", "OpenClaw"])
        XCTAssertEqual(rows.map(\.tone), [.blue, .red])
        XCTAssertEqual(rows.count, 2)
    }

    func testHistoryInsightBuilderBuildsMemoryContextCards() {
        let cards = OpsHistoryInsightBuilder.contextCards(
            metric: .memoryDiscipline,
            focusTitle: "Project",
            totalAgents: 4,
            traceRows: [],
            anomalyRows: [],
            agentRows: [
                makeAgentRow(
                    agentName: "Planner",
                    stateText: "Active",
                    status: .healthy,
                    completedCount: 4,
                    failedCount: 0,
                    lastActivityAt: Date(),
                    hasTrackedMemory: true
                ),
                makeAgentRow(
                    agentName: "Scout",
                    stateText: "Waiting",
                    status: .warning,
                    completedCount: 1,
                    failedCount: 1,
                    lastActivityAt: Date(),
                    hasTrackedMemory: false
                )
            ],
            cronRuns: []
        )

        XCTAssertEqual(cards.map(\.id), ["mem-tracked", "mem-gap", "mem-total"])
        XCTAssertEqual(cards.map(\.value), ["1", "1", "50%"])
        XCTAssertEqual(cards.map(\.tone), [.green, .orange, .blue])
    }

    func testProtocolAgentInsightBuilderRanksProfilesByRiskAndDominantRepair() throws {
        let now = Date()
        let profiles = OpsProtocolAgentInsightBuilder.profiles(
            from: [
                makeTraceRow(
                    agentName: "Planner",
                    status: .failed,
                    startedAt: now,
                    sourceLabel: "Runtime",
                    previewText: "Approval blocked",
                    protocolRepairCount: 1,
                    protocolRepairTypes: ["route_missing_approval_blocked"],
                    protocolSafeDegradeApplied: false
                ),
                makeTraceRow(
                    agentName: "Planner",
                    status: .completed,
                    startedAt: now.addingTimeInterval(-60),
                    sourceLabel: "Runtime",
                    previewText: "Recovered with safe degrade",
                    protocolRepairCount: 1,
                    protocolRepairTypes: ["invalid_targets_auto_selected"],
                    protocolSafeDegradeApplied: true
                ),
                makeTraceRow(
                    agentName: "Scout",
                    status: .completed,
                    startedAt: now.addingTimeInterval(-30),
                    sourceLabel: "Runtime",
                    previewText: "Missing route fixed",
                    protocolRepairCount: 1,
                    protocolRepairTypes: ["missing_route_auto_selected"],
                    protocolSafeDegradeApplied: true
                ),
                makeTraceRow(
                    agentName: "Reviewer",
                    status: .completed,
                    startedAt: now.addingTimeInterval(-10),
                    sourceLabel: "OpenClaw",
                    previewText: "External trace should be ignored",
                    protocolRepairCount: 1,
                    protocolRepairTypes: ["invalid_targets_auto_selected"],
                    protocolSafeDegradeApplied: true
                )
            ]
        )

        XCTAssertEqual(profiles.map(\.agentName), ["Planner", "Scout"])

        let planner = try XCTUnwrap(profiles.first)
        XCTAssertEqual(planner.riskScore, 8)
        XCTAssertEqual(planner.hardInterruptCount, 1)
        XCTAssertEqual(planner.safeDegradeCount, 1)
        XCTAssertEqual(planner.repairedTraceCount, 2)
        XCTAssertEqual(planner.dominantRepairLabel, "Approval Blocked")
        XCTAssertEqual(planner.recommendedFilter, .hardInterrupt)

        let scout = try XCTUnwrap(profiles.last)
        XCTAssertEqual(scout.totalTraceCount, 1)
        XCTAssertEqual(scout.dominantRepairLabel, "Missing Route")
        XCTAssertEqual(scout.recommendedFilter, .missingRoute)
    }

    func testProtocolRepairDistributionBuilderCountsRuntimeRowsOnly() {
        let now = Date()
        let items = OpsProtocolRepairDistributionBuilder.items(
            from: [
                makeTraceRow(
                    agentName: "Planner",
                    status: .completed,
                    startedAt: now,
                    sourceLabel: "Runtime",
                    previewText: "Invalid target repaired",
                    protocolRepairCount: 1,
                    protocolRepairTypes: ["invalid_targets_auto_selected"],
                    protocolSafeDegradeApplied: true
                ),
                makeTraceRow(
                    agentName: "Scout",
                    status: .completed,
                    startedAt: now.addingTimeInterval(-20),
                    sourceLabel: "Runtime",
                    previewText: "Invalid target repaired again",
                    protocolRepairCount: 1,
                    protocolRepairTypes: ["invalid_targets_auto_selected"],
                    protocolSafeDegradeApplied: true
                ),
                makeTraceRow(
                    agentName: "Planner",
                    status: .failed,
                    startedAt: now.addingTimeInterval(-40),
                    sourceLabel: "Runtime",
                    previewText: "Approval blocked",
                    protocolRepairCount: 1,
                    protocolRepairTypes: ["route_missing_approval_blocked"],
                    protocolSafeDegradeApplied: false
                ),
                makeTraceRow(
                    agentName: "Reviewer",
                    status: .completed,
                    startedAt: now.addingTimeInterval(-10),
                    sourceLabel: "OpenClaw",
                    previewText: "External session missing route",
                    protocolRepairCount: 1,
                    protocolRepairTypes: ["missing_route_auto_selected"],
                    protocolSafeDegradeApplied: true
                )
            ]
        )

        XCTAssertEqual(items.map(\.title), ["Invalid Target", "Approval Blocked"])
        XCTAssertEqual(items.map(\.count), [2, 1])
        XCTAssertEqual(items.map(\.filter), [.invalidTarget, .approvalBlocked])
    }

    func testHistoryInsightBuilderUsesRuntimeRowsOnlyForProtocolMetrics() {
        let now = Date()
        let runtimeRepaired = makeTraceRow(
            agentName: "Planner",
            status: .completed,
            startedAt: now.addingTimeInterval(-60),
            sourceLabel: "Runtime",
            previewText: "Recovered with safe degrade",
            protocolRepairCount: 1,
            protocolRepairTypes: ["invalid_targets_auto_selected"],
            protocolSafeDegradeApplied: true
        )
        let runtimeConforming = makeTraceRow(
            agentName: "Scout",
            status: .completed,
            startedAt: now.addingTimeInterval(-90),
            sourceLabel: "Runtime",
            previewText: "Conforming run"
        )
        let externalRepair = makeTraceRow(
            agentName: "Reviewer",
            status: .completed,
            startedAt: now,
            sourceLabel: "OpenClaw",
            previewText: "External repaired trace should be ignored",
            protocolRepairCount: 1,
            protocolRepairTypes: ["missing_route_auto_selected"],
            protocolSafeDegradeApplied: true
        )

        let cards = OpsHistoryInsightBuilder.contextCards(
            metric: .protocolConformance,
            focusTitle: "Project",
            totalAgents: 3,
            traceRows: [runtimeRepaired, runtimeConforming, externalRepair],
            anomalyRows: [],
            agentRows: [],
            cronRuns: []
        )
        XCTAssertEqual(cards.map(\.value), ["1", "1", "1"])

        let rows = OpsHistoryInsightBuilder.signalRows(
            metric: .protocolAutoRepair,
            anomalyRows: [],
            traceRows: [runtimeRepaired, externalRepair],
            agentRows: [],
            cronRuns: []
        )
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.title, "Planner")
        XCTAssertEqual(rows.first?.badge, "Invalid Target")
    }

    func testHistoryInsightBuilderBuildsCronSignalRowsWithLinkedAnomalyAndFormattedDuration() throws {
        let now = Date()
        let matchingAnomaly = makeAnomalyRow(
            id: "cron-anomaly",
            title: "nightly-sync",
            sourceLabel: "Cron",
            detailText: "Job timed out",
            fullDetailText: "Job timed out",
            occurredAt: now.addingTimeInterval(-30),
            status: .critical,
            statusText: "FAILED",
            sourceService: nil,
            linkedSpanID: nil
        )
        let rows = OpsHistoryInsightBuilder.signalRows(
            metric: .cronReliability,
            anomalyRows: [matchingAnomaly],
            traceRows: [],
            agentRows: [],
            cronRuns: [
                makeCronRunRow(
                    cronName: "nightly-sync",
                    statusText: "FAILED",
                    runAt: now,
                    summaryText: "Nightly sync timed out",
                    jobID: "job-1",
                    runID: UUID().uuidString,
                    sourcePath: nil,
                    duration: 65
                ),
                makeCronRunRow(
                    cronName: "other-cron",
                    statusText: "OK",
                    runAt: now.addingTimeInterval(-300),
                    summaryText: "Healthy",
                    jobID: "job-2",
                    runID: UUID().uuidString,
                    sourcePath: nil,
                    duration: 5.2
                )
            ]
        )

        let first = try XCTUnwrap(rows.first)
        XCTAssertEqual(rows.map(\.title), ["nightly-sync", "other-cron"])
        XCTAssertEqual(first.badge, "FAILED")
        XCTAssertEqual(first.tone, .red)
        XCTAssertEqual(first.detail, "1m 5s • Nightly sync timed out")
        XCTAssertEqual(first.anomaly?.id, matchingAnomaly.id)
        XCTAssertEqual(rows.last?.detail, "5.2s • Healthy")
    }

    func testHistoryScopeMatcherMatchesAgentScopeAcrossRows() {
        let anomaly = makeAnomalyRow(
            id: "runtime",
            title: "Planner Drift",
            sourceLabel: "Runtime",
            detailText: "Planner exceeded budget",
            fullDetailText: "Planner exceeded budget during execution",
            occurredAt: Date(),
            status: .warning,
            statusText: "warning",
            sourceService: "multi-agent-flow.execution",
            linkedSpanID: nil
        )
        let trace = makeTraceRow(
            agentName: "Planner",
            status: .failed,
            startedAt: Date(),
            sourceLabel: "Runtime",
            previewText: "Planner failed"
        )
        let agent = makeAgentRow(
            agentName: "Planner",
            stateText: "Active",
            status: .healthy,
            completedCount: 3,
            failedCount: 1,
            lastActivityAt: Date(),
            hasTrackedMemory: true
        )
        let cron = makeCronRunRow(
            cronName: "heartbeat",
            statusText: "FAILED",
            runAt: Date(),
            summaryText: "Planner heartbeat stalled",
            jobID: "job-1",
            runID: UUID().uuidString,
            sourcePath: nil
        )

        XCTAssertTrue(OpsHistoryScopeMatcher.matches(anomaly, kind: .agent, matchKey: "planner"))
        XCTAssertTrue(OpsHistoryScopeMatcher.matches(trace, kind: .agent, matchKey: "planner"))
        XCTAssertTrue(OpsHistoryScopeMatcher.matches(agent, kind: .agent, matchKey: "planner"))
        XCTAssertTrue(OpsHistoryScopeMatcher.matches(cron, kind: .agent, matchKey: "planner"))

        XCTAssertFalse(
            OpsHistoryScopeMatcher.matches(
                makeTraceRow(
                    agentName: "Scout",
                    status: .failed,
                    startedAt: Date(),
                    sourceLabel: "Runtime",
                    previewText: "Scout failed"
                ),
                kind: .agent,
                matchKey: "planner"
            )
        )
    }

    func testHistoryScopeMatcherMatchesToolScopeOnlyForToolRelevantRows() {
        let toolAnomaly = makeAnomalyRow(
            id: "tool",
            title: "Search Timeout",
            sourceLabel: "Tool",
            detailText: "search.web timed out",
            fullDetailText: "search.web timed out after retry",
            occurredAt: Date(),
            status: .warning,
            statusText: "timeout",
            sourceService: "search.web",
            linkedSpanID: nil
        )
        let runtimeAnomaly = makeAnomalyRow(
            id: "runtime",
            title: "Search Timeout",
            sourceLabel: "Runtime",
            detailText: "search.web timed out",
            fullDetailText: "search.web timed out after retry",
            occurredAt: Date(),
            status: .warning,
            statusText: "timeout",
            sourceService: "search.web",
            linkedSpanID: nil
        )
        let trace = makeTraceRow(
            agentName: "Planner",
            status: .failed,
            startedAt: Date(),
            sourceLabel: "OpenClaw",
            previewText: "Tool search.web failed"
        )
        let cron = makeCronRunRow(
            cronName: "nightly-sync",
            statusText: "FAILED",
            runAt: Date(),
            summaryText: "search.web provider unavailable",
            jobID: "job-2",
            runID: UUID().uuidString,
            sourcePath: nil
        )

        XCTAssertTrue(OpsHistoryScopeMatcher.matches(toolAnomaly, kind: .tool, matchKey: "search.web"))
        XCTAssertTrue(OpsHistoryScopeMatcher.matches(trace, kind: .tool, matchKey: "search.web"))
        XCTAssertTrue(OpsHistoryScopeMatcher.matches(cron, kind: .tool, matchKey: "search.web"))
        XCTAssertFalse(OpsHistoryScopeMatcher.matches(runtimeAnomaly, kind: .tool, matchKey: "search.web"))
        XCTAssertFalse(
            OpsHistoryScopeMatcher.matches(
                makeAgentRow(
                    agentName: "Planner",
                    stateText: "Active",
                    status: .healthy,
                    completedCount: 1,
                    failedCount: 0,
                    lastActivityAt: Date(),
                    hasTrackedMemory: true
                ),
                kind: .tool,
                matchKey: "search.web"
            )
        )
    }

    func testHistoryScopeMatcherMatchesCronScopeByExactIdentifierAndProjectScopeAlwaysMatches() {
        let cronAnomaly = makeAnomalyRow(
            id: "cron",
            title: "nightly-sync",
            sourceLabel: "Cron",
            detailText: "Nightly sync failed",
            fullDetailText: "Nightly sync failed",
            occurredAt: Date(),
            status: .critical,
            statusText: "FAILED",
            sourceService: nil,
            linkedSpanID: nil
        )
        let cronRun = makeCronRunRow(
            cronName: "nightly-sync",
            statusText: "FAILED",
            runAt: Date(),
            summaryText: "Nightly sync failed",
            jobID: "job-3",
            runID: UUID().uuidString,
            sourcePath: nil
        )
        let trace = makeTraceRow(
            agentName: "Planner",
            status: .completed,
            startedAt: Date(),
            sourceLabel: "Runtime",
            previewText: "Unrelated"
        )

        XCTAssertTrue(OpsHistoryScopeMatcher.matches(cronAnomaly, kind: .cron, matchKey: "NIGHTLY-SYNC"))
        XCTAssertTrue(OpsHistoryScopeMatcher.matches(cronRun, kind: .cron, matchKey: "NIGHTLY-SYNC"))
        XCTAssertFalse(OpsHistoryScopeMatcher.matches(trace, kind: .cron, matchKey: "nightly-sync"))

        XCTAssertTrue(OpsHistoryScopeMatcher.matches(cronAnomaly, kind: .project, matchKey: ""))
        XCTAssertTrue(OpsHistoryScopeMatcher.matches(trace, kind: .project, matchKey: ""))
    }

    func testAnomalyInsightBuilderBuildsExplorerCards() {
        let now = Date()
        let rows = [
            makeAnomalyRow(
                id: "critical-cron",
                title: "nightly-sync",
                sourceLabel: "Cron",
                detailText: "Timed out",
                fullDetailText: "Timed out",
                occurredAt: now,
                status: .critical,
                statusText: "FAILED",
                sourceService: nil,
                linkedSpanID: UUID()
            ),
            makeAnomalyRow(
                id: "warning-tool",
                title: "search.web",
                sourceLabel: "Tool",
                detailText: "Provider unavailable",
                fullDetailText: "Provider unavailable",
                occurredAt: now.addingTimeInterval(-60),
                status: .warning,
                statusText: "error",
                sourceService: "openclaw.external-tool-result",
                linkedSpanID: nil
            ),
            makeAnomalyRow(
                id: "warning-tool-2",
                title: "search.web",
                sourceLabel: "Tool",
                detailText: "Provider timeout",
                fullDetailText: "Provider timeout",
                occurredAt: now.addingTimeInterval(-120),
                status: .warning,
                statusText: "timeout",
                sourceService: "openclaw.external-tool-result",
                linkedSpanID: nil
            )
        ]
        let clusters = OpsAnomalyClusterBuilder.clusters(from: rows, now: now)

        let cards = OpsAnomalyInsightBuilder.explorerCards(
            rows: rows,
            clusters: clusters,
            timeWindowDetail: "Signals from the last 7 days"
        )

        XCTAssertEqual(cards.map(\.id), ["matching", "critical", "cron", "clusters"])
        XCTAssertEqual(cards.map(\.value), ["3", "1", "1", "1"])
        XCTAssertEqual(cards.map(\.tone), [.blue, .red, .orange, .teal])
        XCTAssertEqual(cards.last?.detail, "1 trace-linked rows retained")
    }

    func testHistoryNarrativeBuilderBuildsDeltaTextAcrossSampleStates() {
        let start = Date(timeIntervalSinceReferenceDate: 10_000)

        let emptySeries = OpsMetricHistorySeries(metric: .workflowReliability, points: [])
        XCTAssertEqual(
            OpsHistoryNarrativeBuilder.deltaText(for: emptySeries),
            "No historical samples yet"
        )

        let firstSampleSeries = makeHistorySeries(
            metric: .workflowReliability,
            start: start,
            values: [83]
        )
        XCTAssertEqual(
            OpsHistoryNarrativeBuilder.deltaText(for: firstSampleSeries),
            "First sample: 83%"
        )

        let reliabilitySeries = makeHistorySeries(
            metric: .workflowReliability,
            start: start,
            values: [78, 84]
        )
        XCTAssertEqual(
            OpsHistoryNarrativeBuilder.deltaText(for: reliabilitySeries),
            "Changed +6 pts since previous sample"
        )

        let errorBudgetSeries = makeHistorySeries(
            metric: .errorBudget,
            start: start,
            values: [3, 1]
        )
        XCTAssertEqual(
            OpsHistoryNarrativeBuilder.deltaText(for: errorBudgetSeries),
            "Changed -2 since previous sample"
        )
    }

    func testHistoryNarrativeBuilderBuildsMetricSpecificNarrative() {
        let series = makeHistorySeries(
            metric: .cronReliability,
            start: Date(timeIntervalSinceReferenceDate: 20_000),
            values: [55, 80]
        )

        XCTAssertEqual(
            OpsHistoryNarrativeBuilder.narrative(for: series, focusText: "Project-wide"),
            "Project-wide cron reliability is currently 80%. Changed +25 pts since previous sample, and the related signals below show the latest scheduled runs feeding this trend."
        )
    }

    func testAnomalyClusterInsightBuilderSummarizesRecentAndEarlierCounts() {
        XCTAssertEqual(
            OpsAnomalyClusterInsightBuilder.trendText(
                occurrenceCount: 5,
                recent24HourCount: 2,
                includeEarlierBreakdown: false
            ),
            "24h 2"
        )

        XCTAssertEqual(
            OpsAnomalyClusterInsightBuilder.trendText(
                occurrenceCount: 5,
                recent24HourCount: 2,
                includeEarlierBreakdown: true
            ),
            "24h 2 • earlier 3"
        )

        XCTAssertEqual(
            OpsAnomalyClusterInsightBuilder.trendText(
                occurrenceCount: 1,
                recent24HourCount: 3,
                includeEarlierBreakdown: true
            ),
            "24h 3 • earlier 0"
        )
    }

    func testHistoryInsightBuilderBuildsDaySummaryCards() {
        let selectedDate = Date(timeIntervalSinceReferenceDate: 123_456)
        let rows = [
            OpsHistorySignalRow(
                id: "critical",
                title: "Planner Failure",
                badge: "Critical",
                detail: "Needs action",
                occurredAt: selectedDate,
                tone: .red,
                anomaly: makeAnomalyRow(
                    id: "critical",
                    title: "Planner Failure",
                    sourceLabel: "Runtime",
                    detailText: "Needs action",
                    fullDetailText: "Needs action",
                    occurredAt: selectedDate,
                    status: .critical,
                    statusText: "error",
                    sourceService: "multi-agent-flow.execution",
                    linkedSpanID: nil
                ),
                trace: nil,
                cronRun: nil
            ),
            OpsHistorySignalRow(
                id: "info",
                title: "Background signal",
                badge: "Info",
                detail: "No panel",
                occurredAt: selectedDate,
                tone: .blue,
                anomaly: nil,
                trace: nil,
                cronRun: nil
            ),
            OpsHistorySignalRow(
                id: "error-trace",
                title: "Failed Trace",
                badge: "Error",
                detail: "Trace panel",
                occurredAt: selectedDate,
                tone: .red,
                anomaly: nil,
                trace: makeTraceRow(
                    agentName: "Planner",
                    status: .failed,
                    startedAt: selectedDate,
                    sourceLabel: "Runtime",
                    previewText: "Trace panel"
                ),
                cronRun: nil
            )
        ]
        let point = OpsMetricHistoryPoint(date: selectedDate, value: 83)

        let cards = OpsHistoryInsightBuilder.daySummaryCards(
            metric: .workflowReliability,
            point: point,
            rows: rows,
            selectedDate: selectedDate
        )

        XCTAssertEqual(cards.map(\.id), ["day-sample", "day-signals", "day-actionable", "day-critical"])
        XCTAssertEqual(cards.map(\.value), ["83%", "3", "2", "2"])
        XCTAssertEqual(cards.map(\.tone), [.green, .blue, .teal, .red])
    }

    private func makeProjectID() -> UUID {
        let projectID = UUID()
        projectIDsToClean.append(projectID)
        return projectID
    }

    private func makeProject(name: String) -> MAProject {
        let project = MAProject(name: name)
        projectIDsToClean.append(project.id)
        return project
    }

    private func makeTemporaryDirectory(named name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MultiAgentFlowTests-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        temporaryURLsToClean.append(url)
        return url
    }

    private func prepareEmptyAnalyticsDatabase(for projectID: UUID) throws {
        let dbURL = ProjectManager.shared.analyticsDatabaseURL(for: projectID)
        try? FileManager.default.removeItem(at: dbURL)

        _ = service.scopedHistorySeries(
            projectID: projectID,
            days: 1,
            scopeKind: "project",
            scopeValue: "project",
            scopeMatchKey: "project"
        )
    }

    private func withDatabase(
        for projectID: UUID,
        perform body: (OpaquePointer) throws -> Void
    ) throws {
        let dbURL = ProjectManager.shared.analyticsDatabaseURL(for: projectID)
        var db: OpaquePointer?
        guard sqlite3_open(dbURL.path, &db) == SQLITE_OK, let db else {
            defer { if db != nil { sqlite3_close(db) } }
            throw DatabaseError.open(message(from: db))
        }
        defer { sqlite3_close(db) }

        try body(db)
    }

    private func insertCronRun(
        db: OpaquePointer,
        projectID: UUID,
        date: String,
        cronName: String,
        status: String,
        jobID: String,
        runID: String,
        runAt: Date,
        durationMs: Double? = nil,
        deliveryStatus: String? = nil,
        summary: String? = nil,
        error: String? = nil,
        sourcePath: String? = nil
    ) throws {
        let sql = """
        INSERT INTO cron_runs
        (project_id, date, cron_name, slot_time, status, job_id, run_id, error, external_id, run_at, duration_ms, delivery_status, summary, source_path)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """

        let externalID = "\(cronName)-\(jobID)"
        try execute(
            db: db,
            sql: sql,
            bindings: [
                .text(projectID.uuidString),
                .text(date),
                .text(cronName),
                .text(iso8601.string(from: runAt)),
                .text(status),
                .text(jobID),
                .text(runID),
                .text(error),
                .text(externalID),
                .text(iso8601.string(from: runAt)),
                .double(durationMs),
                .text(deliveryStatus),
                .text(summary),
                .text(sourcePath)
            ]
        )
    }

    private func insertSpan(
        db: OpaquePointer,
        projectID: UUID,
        spanID: UUID,
        traceID: String? = nil,
        parentSpanID: String? = nil,
        name: String,
        service: String,
        status: String,
        startedAt: Date,
        durationMs: Double? = nil,
        attributes: [String: String],
        events: String? = nil
    ) throws {
        let sql = """
        INSERT INTO spans
        (span_id, project_id, trace_id, parent_span_id, name, service, status, start_time, end_time, duration_ms, attributes, events)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """

        let endTime = durationMs.map { startedAt.addingTimeInterval($0 / 1000.0) }
        let attributesText = try String(
            data: JSONSerialization.data(withJSONObject: attributes, options: [.sortedKeys]),
            encoding: .utf8
        )

        try execute(
            db: db,
            sql: sql,
            bindings: [
                .text(spanID.uuidString),
                .text(projectID.uuidString),
                .text(traceID ?? spanID.uuidString.replacingOccurrences(of: "-", with: "")),
                .text(parentSpanID),
                .text(name),
                .text(service),
                .text(status),
                .text(iso8601.string(from: startedAt)),
                .text(endTime.map(iso8601.string(from:))),
                .double(durationMs),
                .text(attributesText),
                .text(events)
            ]
        )
    }

    private func insertDailyAgentActivity(
        db: OpaquePointer,
        projectID: UUID,
        date: String,
        agentID: UUID,
        sessionCount: Int,
        memoryLogged: Bool
    ) throws {
        let sql = """
        INSERT INTO daily_agent_activity
        (project_id, date, agent_id, session_count, memory_logged, last_active)
        VALUES (?, ?, ?, ?, ?, ?);
        """

        try execute(
            db: db,
            sql: sql,
            bindings: [
                .text(projectID.uuidString),
                .text(date),
                .text(agentID.uuidString),
                .int(sessionCount),
                .int(memoryLogged ? 1 : 0),
                .text(nil)
            ]
        )
    }

    private func execute(
        db: OpaquePointer,
        sql: String,
        bindings: [SQLiteBinding]
    ) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw DatabaseError.prepare(message(from: db))
        }
        defer { sqlite3_finalize(statement) }

        for (index, binding) in bindings.enumerated() {
            let parameter = Int32(index + 1)
            switch binding {
            case let .text(value):
                if let value {
                    sqlite3_bind_text(statement, parameter, value, -1, sqliteTransientDestructor)
                } else {
                    sqlite3_bind_null(statement, parameter)
                }
            case let .double(value):
                if let value {
                    sqlite3_bind_double(statement, parameter, value)
                } else {
                    sqlite3_bind_null(statement, parameter)
                }
            case let .int(value):
                if let value {
                    sqlite3_bind_int64(statement, parameter, sqlite3_int64(value))
                } else {
                    sqlite3_bind_null(statement, parameter)
                }
            }
        }

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DatabaseError.step(message(from: db))
        }
    }

    private func series(
        _ series: [OpsMetricHistorySeries],
        metric: OpsHistoryMetric
    ) -> OpsMetricHistorySeries? {
        series.first { $0.metric == metric }
    }

    private func calendarDayString(for date: Date) -> String {
        dayFormatter.string(from: date)
    }

    private func makeHistorySeries(
        metric: OpsHistoryMetric,
        start: Date,
        values: [Double]
    ) -> OpsMetricHistorySeries {
        OpsMetricHistorySeries(
            metric: metric,
            points: values.enumerated().map { index, value in
                OpsMetricHistoryPoint(
                    date: start.addingTimeInterval(TimeInterval(index * 86_400)),
                    value: value
                )
            }
        )
    }

    private func makeCronRunRow(
        cronName: String,
        statusText: String,
        runAt: Date,
        summaryText: String,
        jobID: String?,
        runID: String?,
        sourcePath: String?,
        duration: TimeInterval? = nil
    ) -> OpsCronRunRow {
        OpsCronRunRow(
            id: "\(cronName)-\(jobID ?? UUID().uuidString)",
            cronName: cronName,
            statusText: statusText,
            runAt: runAt,
            duration: duration,
            deliveryStatus: nil,
            summaryText: summaryText,
            jobID: jobID,
            runID: runID,
            sourcePath: sourcePath
        )
    }

    private func makeTraceRow(
        id: UUID = UUID(),
        agentName: String,
        status: ExecutionStatus,
        startedAt: Date,
        sourceLabel: String,
        previewText: String,
        protocolRepairCount: Int = 0,
        protocolRepairTypes: [String] = [],
        protocolSafeDegradeApplied: Bool = false
    ) -> OpsTraceSummaryRow {
        OpsTraceSummaryRow(
            id: id,
            agentName: agentName,
            status: status,
            duration: nil,
            startedAt: startedAt,
            routingAction: nil,
            outputType: .agentFinalResponse,
            sourceLabel: sourceLabel,
            previewText: previewText,
            protocolRepairCount: protocolRepairCount,
            protocolRepairTypes: protocolRepairTypes,
            protocolSafeDegradeApplied: protocolSafeDegradeApplied
        )
    }

    private func makeAgentRow(
        agentName: String,
        stateText: String,
        status: OpsHealthStatus,
        completedCount: Int,
        failedCount: Int,
        lastActivityAt: Date?,
        hasTrackedMemory: Bool
    ) -> OpsAgentHealthRow {
        OpsAgentHealthRow(
            id: UUID(),
            agentName: agentName,
            stateText: stateText,
            status: status,
            completedCount: completedCount,
            failedCount: failedCount,
            averageDuration: nil,
            lastActivityAt: lastActivityAt,
            hasTrackedMemory: hasTrackedMemory
        )
    }

    private func makeAnomalyRow(
        id: String,
        title: String,
        sourceLabel: String,
        detailText: String,
        fullDetailText: String,
        occurredAt: Date,
        status: OpsHealthStatus,
        statusText: String,
        sourceService: String?,
        linkedSpanID: UUID?
    ) -> OpsAnomalyRow {
        OpsAnomalyRow(
            id: id,
            title: title,
            sourceLabel: sourceLabel,
            detailText: detailText,
            fullDetailText: fullDetailText,
            occurredAt: occurredAt,
            status: status,
            statusText: statusText,
            sourceService: sourceService,
            linkedSpanID: linkedSpanID
        )
    }

    private func writeJSONLines(
        _ objects: [[String: Any]],
        to url: URL
    ) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let lines = try objects.map { object -> String in
            let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            guard let line = String(data: data, encoding: .utf8) else {
                throw DatabaseError.prepare("Failed to encode JSON line")
            }
            return line
        }
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private func message(from db: OpaquePointer?) -> String {
        guard let db else { return "Unknown SQLite error" }
        return String(cString: sqlite3_errmsg(db))
    }
}

private enum SQLiteBinding {
    case text(String?)
    case double(Double?)
    case int(Int?)
}

private enum DatabaseError: Error {
    case open(String)
    case prepare(String)
    case step(String)
}

private let sqliteTransientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
