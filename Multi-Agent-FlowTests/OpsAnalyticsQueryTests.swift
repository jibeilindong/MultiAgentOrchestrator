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
        XCTAssertEqual(traceDetail.outputText, "")
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
        let now = Date()
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

    private func makeCronRunRow(
        cronName: String,
        statusText: String,
        runAt: Date,
        summaryText: String,
        jobID: String?,
        runID: String?,
        sourcePath: String?
    ) -> OpsCronRunRow {
        OpsCronRunRow(
            id: "\(cronName)-\(jobID ?? UUID().uuidString)",
            cronName: cronName,
            statusText: statusText,
            runAt: runAt,
            duration: nil,
            deliveryStatus: nil,
            summaryText: summaryText,
            jobID: jobID,
            runID: runID,
            sourcePath: sourcePath
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
