import Foundation
import SQLite3

struct OpsAnalyticsPersistenceSummary {
    let dailyActivity: [OpsDailyActivityPoint]
    let historicalSeries: [OpsMetricHistorySeries]
    let traceRows: [OpsTraceSummaryRow]
}

final class OpsAnalyticsStore {
    static let shared = OpsAnalyticsStore()

    private let queue = DispatchQueue(label: "MultiAgentFlow.OpsAnalyticsStore")
    private let iso8601 = ISO8601DateFormatter()
    private let dayFormatter: DateFormatter
    private var lastSyncSignatureByProjectID: [UUID: String] = [:]

    private init() {
        let formatter = DateFormatter()
        formatter.calendar = .autoupdatingCurrent
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        self.dayFormatter = formatter
    }

    func synchronize(
        project: MAProject,
        totalAgents: Int,
        activeAgents: Int,
        trackedMemoryAgents: Int,
        completedExecutions: Int,
        failedExecutions: Int,
        warningLogCount: Int,
        errorLogCount: Int,
        agentRows: [OpsAgentHealthRow],
        executionResults: [ExecutionResult],
        agentNamesByID: [UUID: String],
        isConnected: Bool
    ) -> OpsAnalyticsPersistenceSummary? {
        queue.sync {
            let dbURL = ProjectManager.shared.analyticsDatabaseURL(for: project.id)
            guard let db = openDatabase(at: dbURL) else { return nil }
            defer { sqlite3_close(db) }

            guard createSchema(in: db) else { return nil }

            let syncSignature = makeSyncSignature(
                project: project,
                totalAgents: totalAgents,
                activeAgents: activeAgents,
                trackedMemoryAgents: trackedMemoryAgents,
                completedExecutions: completedExecutions,
                failedExecutions: failedExecutions,
                warningLogCount: warningLogCount,
                errorLogCount: errorLogCount,
                executionResults: executionResults
            )

            if lastSyncSignatureByProjectID[project.id] != syncSignature {
                persistCurrentAnalytics(
                    db: db,
                    project: project,
                    totalAgents: totalAgents,
                    activeAgents: activeAgents,
                    trackedMemoryAgents: trackedMemoryAgents,
                    completedExecutions: completedExecutions,
                    failedExecutions: failedExecutions,
                    warningLogCount: warningLogCount,
                    errorLogCount: errorLogCount,
                    agentRows: agentRows,
                    executionResults: executionResults,
                    agentNamesByID: agentNamesByID,
                    isConnected: isConnected
                )
                lastSyncSignatureByProjectID[project.id] = syncSignature
            }

            return OpsAnalyticsPersistenceSummary(
                dailyActivity: loadDailyActivity(db: db, projectID: project.id, days: 14),
                historicalSeries: loadGoalMetricSeries(db: db, projectID: project.id, days: 30),
                traceRows: loadRecentTraceRows(db: db, projectID: project.id, limit: 10)
            )
        }
    }

    func loadTraceDetail(projectID: UUID, spanID: UUID) -> OpsTraceDetail? {
        queue.sync {
            let dbURL = ProjectManager.shared.analyticsDatabaseURL(for: projectID)
            guard let db = openDatabase(at: dbURL) else { return nil }
            defer { sqlite3_close(db) }

            guard createSchema(in: db) else { return nil }
            return loadTraceDetail(db: db, projectID: projectID, spanID: spanID)
        }
    }

    private func openDatabase(at url: URL) -> OpaquePointer? {
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK, let db else {
            if db != nil {
                sqlite3_close(db)
            }
            return nil
        }

        sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA foreign_keys=ON;", nil, nil, nil)
        return db
    }

    private func createSchema(in db: OpaquePointer) -> Bool {
        let schemaSQL = """
        CREATE TABLE IF NOT EXISTS goal_metrics (
            project_id TEXT NOT NULL,
            date TEXT NOT NULL,
            goal TEXT NOT NULL,
            metric TEXT NOT NULL,
            value REAL,
            unit TEXT DEFAULT '',
            breakdown TEXT,
            created_at TEXT DEFAULT (datetime('now')),
            UNIQUE(project_id, date, goal, metric)
        );

        CREATE TABLE IF NOT EXISTS cron_runs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            project_id TEXT NOT NULL,
            date TEXT NOT NULL,
            cron_name TEXT NOT NULL,
            slot_time TEXT,
            status TEXT NOT NULL DEFAULT 'unknown',
            job_id TEXT,
            run_id TEXT,
            error TEXT,
            created_at TEXT DEFAULT (datetime('now'))
        );

        CREATE TABLE IF NOT EXISTS daily_agent_activity (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            project_id TEXT NOT NULL,
            date TEXT NOT NULL,
            agent_id TEXT NOT NULL,
            session_count INTEGER DEFAULT 0,
            memory_logged INTEGER DEFAULT 0,
            last_active TEXT,
            created_at TEXT DEFAULT (datetime('now')),
            UNIQUE(project_id, date, agent_id)
        );

        CREATE TABLE IF NOT EXISTS spans (
            span_id TEXT PRIMARY KEY,
            project_id TEXT NOT NULL,
            trace_id TEXT NOT NULL,
            parent_span_id TEXT,
            name TEXT NOT NULL,
            service TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'ok',
            start_time TEXT NOT NULL,
            end_time TEXT,
            duration_ms REAL,
            attributes TEXT,
            events TEXT,
            created_at TEXT DEFAULT (datetime('now'))
        );

        CREATE INDEX IF NOT EXISTS idx_goal_metrics_project_date ON goal_metrics(project_id, date);
        CREATE INDEX IF NOT EXISTS idx_daa_project_date ON daily_agent_activity(project_id, date);
        CREATE INDEX IF NOT EXISTS idx_spans_project_start ON spans(project_id, start_time);
        """

        return sqlite3_exec(db, schemaSQL, nil, nil, nil) == SQLITE_OK
    }

    private func makeSyncSignature(
        project: MAProject,
        totalAgents: Int,
        activeAgents: Int,
        trackedMemoryAgents: Int,
        completedExecutions: Int,
        failedExecutions: Int,
        warningLogCount: Int,
        errorLogCount: Int,
        executionResults: [ExecutionResult]
    ) -> String {
        let latestResultID = executionResults.last?.id.uuidString ?? "none"
        let latestUpdatedAt = project.updatedAt.timeIntervalSinceReferenceDate
        return [
            project.id.uuidString,
            String(totalAgents),
            String(activeAgents),
            String(trackedMemoryAgents),
            String(completedExecutions),
            String(failedExecutions),
            String(warningLogCount),
            String(errorLogCount),
            latestResultID,
            String(latestUpdatedAt)
        ].joined(separator: "::")
    }

    private func persistCurrentAnalytics(
        db: OpaquePointer,
        project: MAProject,
        totalAgents: Int,
        activeAgents: Int,
        trackedMemoryAgents: Int,
        completedExecutions: Int,
        failedExecutions: Int,
        warningLogCount: Int,
        errorLogCount: Int,
        agentRows: [OpsAgentHealthRow],
        executionResults: [ExecutionResult],
        agentNamesByID: [UUID: String],
        isConnected: Bool
    ) {
        let projectID = project.id.uuidString
        let dateString = dayFormatter.string(from: Date())

        let totalExecutions = completedExecutions + failedExecutions
        let reliabilityRate = totalExecutions > 0 ? (Double(completedExecutions) / Double(totalExecutions)) * 100.0 : 0.0
        let engagementRate = totalAgents > 0 ? (Double(activeAgents) / Double(totalAgents)) * 100.0 : 0.0
        let memoryRate = totalAgents > 0 ? (Double(trackedMemoryAgents) / Double(totalAgents)) * 100.0 : 0.0

        upsertGoalMetric(
            db: db,
            projectID: projectID,
            date: dateString,
            goal: "openclaw_readiness",
            metric: "connected",
            value: isConnected ? 1 : 0,
            unit: "bool",
            breakdown: ["active_agents": "\(activeAgents)"]
        )
        upsertGoalMetric(
            db: db,
            projectID: projectID,
            date: dateString,
            goal: "workflow_reliability",
            metric: "success_rate",
            value: reliabilityRate,
            unit: "%",
            breakdown: [
                "completed_runs": "\(completedExecutions)",
                "failed_runs": "\(failedExecutions)"
            ]
        )
        upsertGoalMetric(
            db: db,
            projectID: projectID,
            date: dateString,
            goal: "workflow_reliability",
            metric: "completed_runs",
            value: Double(completedExecutions),
            unit: "count",
            breakdown: nil
        )
        upsertGoalMetric(
            db: db,
            projectID: projectID,
            date: dateString,
            goal: "workflow_reliability",
            metric: "failed_runs",
            value: Double(failedExecutions),
            unit: "count",
            breakdown: nil
        )
        upsertGoalMetric(
            db: db,
            projectID: projectID,
            date: dateString,
            goal: "agent_engagement",
            metric: "active_agent_count",
            value: Double(activeAgents),
            unit: "count",
            breakdown: ["total_agents": "\(totalAgents)"]
        )
        upsertGoalMetric(
            db: db,
            projectID: projectID,
            date: dateString,
            goal: "agent_engagement",
            metric: "engagement_rate",
            value: engagementRate,
            unit: "%",
            breakdown: ["total_agents": "\(totalAgents)"]
        )
        upsertGoalMetric(
            db: db,
            projectID: projectID,
            date: dateString,
            goal: "memory_discipline",
            metric: "tracked_agent_count",
            value: Double(trackedMemoryAgents),
            unit: "count",
            breakdown: ["total_agents": "\(totalAgents)"]
        )
        upsertGoalMetric(
            db: db,
            projectID: projectID,
            date: dateString,
            goal: "memory_discipline",
            metric: "tracked_rate",
            value: memoryRate,
            unit: "%",
            breakdown: ["total_agents": "\(totalAgents)"]
        )
        upsertGoalMetric(
            db: db,
            projectID: projectID,
            date: dateString,
            goal: "error_budget",
            metric: "error_count",
            value: Double(errorLogCount),
            unit: "count",
            breakdown: ["warning_count": "\(warningLogCount)"]
        )

        for row in agentRows {
            upsertDailyAgentActivity(
                db: db,
                projectID: projectID,
                date: dateString,
                agentID: row.id.uuidString,
                sessionCount: row.completedCount + row.failedCount,
                memoryLogged: row.hasTrackedMemory,
                lastActive: row.lastActivityAt
            )
        }

        for result in executionResults {
            let traceID = result.id.uuidString.replacingOccurrences(of: "-", with: "")
            deleteSpans(db: db, traceID: traceID)

            let attributes: [String: String] = [
                "agent_id": result.agentID.uuidString,
                "agent_name": agentNamesByID[result.agentID] ?? "Unknown Agent",
                "node_id": result.nodeID.uuidString,
                "execution_status": result.status.rawValue,
                "output_type": result.outputType.rawValue,
                "routing_action": result.routingAction ?? "",
                "routing_reason": result.routingReason ?? "",
                "routing_targets": result.routingTargets.joined(separator: ", "),
                "output_text": result.output,
                "preview_text": result.output.compactSingleLinePreview(limit: 160)
            ]

            upsertSpan(
                db: db,
                spanID: result.id.uuidString,
                projectID: projectID,
                traceID: traceID,
                parentSpanID: nil,
                name: agentNamesByID[result.agentID] ?? "Unknown Agent",
                service: "multi-agent-flow.execution",
                status: result.status == .failed ? "error" : "ok",
                startTime: result.startedAt,
                endTime: result.completedAt,
                durationMs: result.duration.map { $0 * 1000.0 },
                attributes: attributes
            )

            if result.routingAction != nil || result.routingReason != nil || !result.routingTargets.isEmpty {
                let routingAttributes: [String: String] = [
                    "agent_name": agentNamesByID[result.agentID] ?? "Unknown Agent",
                    "routing_action": result.routingAction ?? "",
                    "routing_reason": result.routingReason ?? "",
                    "routing_targets": result.routingTargets.joined(separator: ", ")
                ]

                upsertSpan(
                    db: db,
                    spanID: "\(result.id.uuidString)-route",
                    projectID: projectID,
                    traceID: traceID,
                    parentSpanID: result.id.uuidString,
                    name: "Routing Decision",
                    service: "multi-agent-flow.routing",
                    status: "ok",
                    startTime: result.completedAt ?? result.startedAt,
                    endTime: result.completedAt ?? result.startedAt,
                    durationMs: 0,
                    attributes: routingAttributes
                )
            }

            if !result.output.isEmpty {
                let outputAttributes: [String: String] = [
                    "agent_name": agentNamesByID[result.agentID] ?? "Unknown Agent",
                    "output_type": result.outputType.rawValue,
                    "preview_text": result.output.compactSingleLinePreview(limit: 160)
                ]

                upsertSpan(
                    db: db,
                    spanID: "\(result.id.uuidString)-output",
                    projectID: projectID,
                    traceID: traceID,
                    parentSpanID: result.id.uuidString,
                    name: "Output Emission",
                    service: "multi-agent-flow.output",
                    status: result.status == .failed ? "error" : "ok",
                    startTime: result.completedAt ?? result.startedAt,
                    endTime: result.completedAt ?? result.startedAt,
                    durationMs: 0,
                    attributes: outputAttributes
                )
            }
        }
    }

    private func deleteSpans(
        db: OpaquePointer,
        traceID: String
    ) {
        let sql = "DELETE FROM spans WHERE trace_id = ?;"

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return }
        defer { sqlite3_finalize(statement) }

        bindText(traceID, to: 1, in: statement)
        sqlite3_step(statement)
    }

    private func upsertGoalMetric(
        db: OpaquePointer,
        projectID: String,
        date: String,
        goal: String,
        metric: String,
        value: Double,
        unit: String,
        breakdown: [String: String]?
    ) {
        let sql = """
        INSERT INTO goal_metrics (project_id, date, goal, metric, value, unit, breakdown, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, datetime('now'))
        ON CONFLICT(project_id, date, goal, metric) DO UPDATE SET
            value = excluded.value,
            unit = excluded.unit,
            breakdown = excluded.breakdown,
            created_at = datetime('now');
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return }
        defer { sqlite3_finalize(statement) }

        bindText(projectID, to: 1, in: statement)
        bindText(date, to: 2, in: statement)
        bindText(goal, to: 3, in: statement)
        bindText(metric, to: 4, in: statement)
        sqlite3_bind_double(statement, 5, value)
        bindText(unit, to: 6, in: statement)
        bindText(jsonString(from: breakdown), to: 7, in: statement)
        sqlite3_step(statement)
    }

    private func upsertDailyAgentActivity(
        db: OpaquePointer,
        projectID: String,
        date: String,
        agentID: String,
        sessionCount: Int,
        memoryLogged: Bool,
        lastActive: Date?
    ) {
        let sql = """
        INSERT INTO daily_agent_activity
        (project_id, date, agent_id, session_count, memory_logged, last_active, created_at)
        VALUES (?, ?, ?, ?, ?, ?, datetime('now'))
        ON CONFLICT(project_id, date, agent_id) DO UPDATE SET
            session_count = excluded.session_count,
            memory_logged = excluded.memory_logged,
            last_active = excluded.last_active,
            created_at = datetime('now');
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return }
        defer { sqlite3_finalize(statement) }

        bindText(projectID, to: 1, in: statement)
        bindText(date, to: 2, in: statement)
        bindText(agentID, to: 3, in: statement)
        sqlite3_bind_int(statement, 4, Int32(sessionCount))
        sqlite3_bind_int(statement, 5, memoryLogged ? 1 : 0)
        bindText(lastActive.map(iso8601.string(from:)), to: 6, in: statement)
        sqlite3_step(statement)
    }

    private func upsertSpan(
        db: OpaquePointer,
        spanID: String,
        projectID: String,
        traceID: String,
        parentSpanID: String?,
        name: String,
        service: String,
        status: String,
        startTime: Date,
        endTime: Date?,
        durationMs: Double?,
        attributes: [String: String]
    ) {
        let sql = """
        INSERT OR REPLACE INTO spans
        (span_id, project_id, trace_id, parent_span_id, name, service, status, start_time, end_time, duration_ms, attributes, events, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, datetime('now'));
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return }
        defer { sqlite3_finalize(statement) }

        bindText(spanID, to: 1, in: statement)
        bindText(projectID, to: 2, in: statement)
        bindText(traceID, to: 3, in: statement)
        bindText(parentSpanID, to: 4, in: statement)
        bindText(name, to: 5, in: statement)
        bindText(service, to: 6, in: statement)
        bindText(status, to: 7, in: statement)
        bindText(iso8601.string(from: startTime), to: 8, in: statement)
        bindText(endTime.map(iso8601.string(from:)), to: 9, in: statement)
        if let durationMs {
            sqlite3_bind_double(statement, 10, durationMs)
        } else {
            sqlite3_bind_null(statement, 10)
        }
        bindText(jsonString(from: attributes), to: 11, in: statement)
        sqlite3_step(statement)
    }

    private func loadDailyActivity(
        db: OpaquePointer,
        projectID: UUID,
        days: Int
    ) -> [OpsDailyActivityPoint] {
        let sql = """
        SELECT date, goal, metric, value
        FROM goal_metrics
        WHERE project_id = ? AND date >= date('now', ?)
          AND (
            (goal = 'workflow_reliability' AND metric IN ('completed_runs', 'failed_runs'))
            OR (goal = 'error_budget' AND metric = 'error_count')
          )
        ORDER BY date ASC;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return [] }
        defer { sqlite3_finalize(statement) }

        bindText(projectID.uuidString, to: 1, in: statement)
        bindText("-\(days) days", to: 2, in: statement)

        var rowsByDate: [String: (completed: Int, failed: Int, error: Int)] = [:]

        while sqlite3_step(statement) == SQLITE_ROW {
            guard let dateCString = sqlite3_column_text(statement, 0),
                  let goalCString = sqlite3_column_text(statement, 1),
                  let metricCString = sqlite3_column_text(statement, 2) else {
                continue
            }

            let date = String(cString: dateCString)
            let goal = String(cString: goalCString)
            let metric = String(cString: metricCString)
            let value = Int(sqlite3_column_double(statement, 3).rounded())
            var row = rowsByDate[date, default: (0, 0, 0)]

            if goal == "workflow_reliability", metric == "completed_runs" {
                row.completed = value
            } else if goal == "workflow_reliability", metric == "failed_runs" {
                row.failed = value
            } else if goal == "error_budget", metric == "error_count" {
                row.error = value
            }

            rowsByDate[date] = row
        }

        return rowsByDate.keys.sorted().compactMap { dateString in
            guard let date = dayFormatter.date(from: dateString),
                  let row = rowsByDate[dateString] else {
                return nil
            }
            return OpsDailyActivityPoint(
                date: date,
                completedCount: row.completed,
                failedCount: row.failed,
                errorCount: row.error
            )
        }
    }

    private func loadRecentTraceRows(
        db: OpaquePointer,
        projectID: UUID,
        limit: Int
    ) -> [OpsTraceSummaryRow] {
        let sql = """
        SELECT span_id, start_time, duration_ms, attributes
        FROM spans
        WHERE project_id = ? AND service = 'multi-agent-flow.execution'
        ORDER BY start_time DESC
        LIMIT ?;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return [] }
        defer { sqlite3_finalize(statement) }

        bindText(projectID.uuidString, to: 1, in: statement)
        sqlite3_bind_int(statement, 2, Int32(limit))

        var rows: [OpsTraceSummaryRow] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let spanCString = sqlite3_column_text(statement, 0),
                  let startCString = sqlite3_column_text(statement, 1),
                  let attributesCString = sqlite3_column_text(statement, 3),
                  let id = UUID(uuidString: String(cString: spanCString)),
                  let startedAt = iso8601.date(from: String(cString: startCString)) else {
                continue
            }

            let durationMs = sqlite3_column_type(statement, 2) == SQLITE_NULL ? nil : sqlite3_column_double(statement, 2)
            let attributes = dictionary(from: String(cString: attributesCString))
            let executionStatus = ExecutionStatus(rawValue: attributes["execution_status"] ?? "") ?? .idle
            let outputType = ExecutionOutputType(rawValue: attributes["output_type"] ?? "") ?? .empty

            rows.append(
                OpsTraceSummaryRow(
                    id: id,
                    agentName: attributes["agent_name"] ?? "Unknown Agent",
                    status: executionStatus,
                    duration: durationMs.map { $0 / 1000.0 },
                    startedAt: startedAt,
                    routingAction: emptyToNil(attributes["routing_action"]),
                    outputType: outputType,
                    previewText: attributes["preview_text"] ?? "No output"
                )
            )
        }

        return rows
    }

    private func loadGoalMetricSeries(
        db: OpaquePointer,
        projectID: UUID,
        days: Int
    ) -> [OpsMetricHistorySeries] {
        let sql = """
        SELECT date, goal, metric, value
        FROM goal_metrics
        WHERE project_id = ? AND date >= date('now', ?)
          AND (
            (goal = 'workflow_reliability' AND metric = 'success_rate')
            OR (goal = 'agent_engagement' AND metric = 'engagement_rate')
            OR (goal = 'memory_discipline' AND metric = 'tracked_rate')
            OR (goal = 'error_budget' AND metric = 'error_count')
          )
        ORDER BY date ASC;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            return OpsHistoryMetric.allCases.map { OpsMetricHistorySeries(metric: $0, points: []) }
        }
        defer { sqlite3_finalize(statement) }

        bindText(projectID.uuidString, to: 1, in: statement)
        bindText("-\(days) days", to: 2, in: statement)

        var pointsByMetric: [OpsHistoryMetric: [OpsMetricHistoryPoint]] = [:]

        while sqlite3_step(statement) == SQLITE_ROW {
            guard let dateCString = sqlite3_column_text(statement, 0),
                  let goalCString = sqlite3_column_text(statement, 1),
                  let metricCString = sqlite3_column_text(statement, 2) else {
                continue
            }

            let dateString = String(cString: dateCString)
            let goal = String(cString: goalCString)
            let metric = String(cString: metricCString)
            let value = sqlite3_column_double(statement, 3)

            guard let date = dayFormatter.date(from: dateString),
                  let historyMetric = OpsHistoryMetric.allCases.first(where: {
                      $0.goalKey == goal && $0.metricKey == metric
                  }) else {
                continue
            }

            pointsByMetric[historyMetric, default: []].append(
                OpsMetricHistoryPoint(date: date, value: value)
            )
        }

        return OpsHistoryMetric.allCases.map { metric in
            OpsMetricHistorySeries(
                metric: metric,
                points: pointsByMetric[metric, default: []].sorted { $0.date < $1.date }
            )
        }
    }

    private func loadTraceDetail(
        db: OpaquePointer,
        projectID: UUID,
        spanID: UUID
    ) -> OpsTraceDetail? {
        let sql = """
        SELECT span_id, trace_id, parent_span_id, name, service, status, start_time, end_time, duration_ms, attributes, events
        FROM spans
        WHERE project_id = ? AND span_id = ?
        LIMIT 1;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return nil }
        defer { sqlite3_finalize(statement) }

        bindText(projectID.uuidString, to: 1, in: statement)
        bindText(spanID.uuidString, to: 2, in: statement)

        guard sqlite3_step(statement) == SQLITE_ROW,
              let spanCString = sqlite3_column_text(statement, 0),
              let traceCString = sqlite3_column_text(statement, 1),
              let nameCString = sqlite3_column_text(statement, 3),
              let serviceCString = sqlite3_column_text(statement, 4),
              let statusCString = sqlite3_column_text(statement, 5),
              let startCString = sqlite3_column_text(statement, 6),
              let id = UUID(uuidString: String(cString: spanCString)),
              let startedAt = iso8601.date(from: String(cString: startCString)) else {
            return nil
        }

        let parentSpanID = sqlite3_column_type(statement, 2) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(statement, 2))
        let completedAt = sqlite3_column_type(statement, 7) == SQLITE_NULL
            ? nil
            : iso8601.date(from: String(cString: sqlite3_column_text(statement, 7)))
        let durationMs = sqlite3_column_type(statement, 8) == SQLITE_NULL ? nil : sqlite3_column_double(statement, 8)
        let attributes = sqlite3_column_type(statement, 9) == SQLITE_NULL
            ? [:]
            : dictionary(from: String(cString: sqlite3_column_text(statement, 9)))
        let eventsText = sqlite3_column_type(statement, 10) == SQLITE_NULL
            ? nil
            : String(cString: sqlite3_column_text(statement, 10))

        let executionStatus = ExecutionStatus(rawValue: attributes["execution_status"] ?? "") ?? .idle
        let outputType = ExecutionOutputType(rawValue: attributes["output_type"] ?? "") ?? .empty
        let routingTargets = emptyToNil(attributes["routing_targets"])?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } ?? []
        let relatedSpans = loadTraceRelatedSpans(db: db, traceID: String(cString: traceCString), rootSpanID: id.uuidString)

        return OpsTraceDetail(
            id: id,
            traceID: String(cString: traceCString),
            parentSpanID: parentSpanID,
            spanName: String(cString: nameCString),
            service: String(cString: serviceCString),
            statusText: String(cString: statusCString),
            agentName: attributes["agent_name"] ?? "Unknown Agent",
            executionStatus: executionStatus,
            outputType: outputType,
            routingAction: emptyToNil(attributes["routing_action"]),
            routingReason: emptyToNil(attributes["routing_reason"]),
            routingTargets: routingTargets,
            nodeID: attributes["node_id"].flatMap(UUID.init(uuidString:)),
            startedAt: startedAt,
            completedAt: completedAt,
            duration: durationMs.map { $0 / 1000.0 },
            previewText: attributes["preview_text"] ?? "No output",
            outputText: attributes["output_text"] ?? "",
            attributes: attributes,
            eventsText: emptyToNil(eventsText),
            relatedSpans: relatedSpans
        )
    }

    private func loadTraceRelatedSpans(
        db: OpaquePointer,
        traceID: String,
        rootSpanID: String
    ) -> [OpsTraceRelatedSpan] {
        let sql = """
        SELECT span_id, parent_span_id, name, service, status, start_time, end_time, duration_ms, attributes
        FROM spans
        WHERE trace_id = ? AND span_id != ?
        ORDER BY start_time ASC, created_at ASC;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return [] }
        defer { sqlite3_finalize(statement) }

        bindText(traceID, to: 1, in: statement)
        bindText(rootSpanID, to: 2, in: statement)

        var rows: [OpsTraceRelatedSpan] = []

        while sqlite3_step(statement) == SQLITE_ROW {
            guard let spanCString = sqlite3_column_text(statement, 0),
                  let nameCString = sqlite3_column_text(statement, 2),
                  let serviceCString = sqlite3_column_text(statement, 3),
                  let statusCString = sqlite3_column_text(statement, 4),
                  let startCString = sqlite3_column_text(statement, 5),
                  let startedAt = iso8601.date(from: String(cString: startCString)) else {
                continue
            }

            let parentSpanID = sqlite3_column_type(statement, 1) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(statement, 1))
            let completedAt = sqlite3_column_type(statement, 6) == SQLITE_NULL
                ? nil
                : iso8601.date(from: String(cString: sqlite3_column_text(statement, 6)))
            let durationMs = sqlite3_column_type(statement, 7) == SQLITE_NULL ? nil : sqlite3_column_double(statement, 7)
            let attributes = sqlite3_column_type(statement, 8) == SQLITE_NULL
                ? [:]
                : dictionary(from: String(cString: sqlite3_column_text(statement, 8)))

            rows.append(
                OpsTraceRelatedSpan(
                    id: String(cString: spanCString),
                    parentSpanID: parentSpanID,
                    name: String(cString: nameCString),
                    service: String(cString: serviceCString),
                    statusText: String(cString: statusCString),
                    startedAt: startedAt,
                    completedAt: completedAt,
                    duration: durationMs.map { $0 / 1000.0 },
                    summaryText: summarizeRelatedSpan(name: String(cString: nameCString), attributes: attributes)
                )
            )
        }

        return rows
    }

    private func summarizeRelatedSpan(name: String, attributes: [String: String]) -> String {
        if name == "Routing Decision" {
            let action = emptyToNil(attributes["routing_action"]) ?? "none"
            let targets = emptyToNil(attributes["routing_targets"]) ?? "no targets"
            return "\(action) -> \(targets)"
        }

        if name == "Output Emission" {
            let outputType = emptyToNil(attributes["output_type"]) ?? "unknown"
            let preview = emptyToNil(attributes["preview_text"]) ?? "No output"
            return "\(outputType): \(preview)"
        }

        return emptyToNil(attributes["preview_text"]) ?? name
    }

    private func bindText(_ text: String?, to index: Int32, in statement: OpaquePointer) {
        if let text {
            sqlite3_bind_text(statement, index, text, -1, sqliteTransientDestructor)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func jsonString(from dictionary: [String: String]?) -> String? {
        guard let dictionary,
              let data = try? JSONSerialization.data(withJSONObject: dictionary, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        return text
    }

    private func dictionary(from json: String) -> [String: String] {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return [:]
        }
        return object
    }

    private func emptyToNil(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}

private let sqliteTransientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
