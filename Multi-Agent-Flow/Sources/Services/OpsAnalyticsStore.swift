import Foundation
import SQLite3
import CryptoKit

struct OpsAnalyticsPersistenceSummary {
    let dailyActivity: [OpsDailyActivityPoint]
    let historicalSeries: [OpsMetricHistorySeries]
    let cronSummary: OpsCronReliabilitySummary?
    let cronRuns: [OpsCronRunRow]
    let anomalySummary: OpsAnomalySummary?
    let anomalyRows: [OpsAnomalyRow]
    let traceRows: [OpsTraceSummaryRow]
}

private struct ExternalOpsArtifactsSignature {
    let cronSignature: String
    let sessionSignature: String

    var joined: String { "\(cronSignature)::\(sessionSignature)" }
}

private struct ExternalCronRunArtifact {
    let externalID: String
    let date: String
    let cronName: String
    let jobID: String?
    let runID: String?
    let runAt: Date
    let status: String
    let errorText: String?
    let durationMs: Double?
    let deliveryStatus: String?
    let summaryText: String?
    let sourcePath: String
}

private struct ExternalSessionTraceArtifact {
    let spanID: String
    let traceID: String
    let agentName: String
    let status: String
    let executionStatus: ExecutionStatus
    let outputType: ExecutionOutputType
    let startedAt: Date
    let completedAt: Date?
    let durationMs: Double?
    let previewText: String
    let outputText: String
    let attributes: [String: String]
    let eventsText: String?
    let childSpans: [ExternalSessionChildSpanArtifact]
}

private struct ExternalSessionChildSpanArtifact {
    let spanID: String
    let parentSpanID: String?
    let name: String
    let service: String
    let status: String
    let startedAt: Date
    let completedAt: Date?
    let durationMs: Double?
    let attributes: [String: String]
    let eventsText: String?
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

            let externalSignature = makeExternalArtifactsSignature(project: project)

            let syncSignature = makeSyncSignature(
                project: project,
                totalAgents: totalAgents,
                activeAgents: activeAgents,
                trackedMemoryAgents: trackedMemoryAgents,
                completedExecutions: completedExecutions,
                failedExecutions: failedExecutions,
                warningLogCount: warningLogCount,
                errorLogCount: errorLogCount,
                executionResults: executionResults,
                externalSignature: externalSignature.joined
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
                ingestExternalOpenClawArtifacts(
                    db: db,
                    project: project
                )
                lastSyncSignatureByProjectID[project.id] = syncSignature
            }

            return OpsAnalyticsPersistenceSummary(
                dailyActivity: loadDailyActivity(db: db, projectID: project.id, days: 14),
                historicalSeries: loadGoalMetricSeries(db: db, projectID: project.id, days: 30),
                cronSummary: loadCronReliabilitySummary(db: db, projectID: project.id, days: 14),
                cronRuns: loadRecentCronRuns(db: db, projectID: project.id, limit: 8),
                anomalySummary: loadAnomalySummary(db: db, projectID: project.id),
                anomalyRows: loadRecentAnomalyRows(db: db, projectID: project.id, limit: 24),
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

    func loadScopedHistorySeries(
        projectID: UUID,
        days: Int,
        scopeKind: String,
        scopeValue: String,
        scopeMatchKey: String
    ) -> [OpsMetricHistorySeries] {
        queue.sync {
            let dbURL = ProjectManager.shared.analyticsDatabaseURL(for: projectID)
            guard let db = openDatabase(at: dbURL) else { return emptyHistorySeries() }
            defer { sqlite3_close(db) }

            guard createSchema(in: db) else { return emptyHistorySeries() }
            return loadScopedHistorySeries(
                db: db,
                projectID: projectID,
                days: days,
                scopeKind: scopeKind,
                scopeValue: scopeValue,
                scopeMatchKey: scopeMatchKey
            )
        }
    }

    func loadCronDetail(
        projectID: UUID,
        cronName: String,
        days: Int,
        runLimit: Int,
        anomalyLimit: Int
    ) -> OpsCronDetail? {
        queue.sync {
            let dbURL = ProjectManager.shared.analyticsDatabaseURL(for: projectID)
            guard let db = openDatabase(at: dbURL) else { return nil }
            defer { sqlite3_close(db) }

            guard createSchema(in: db) else { return nil }

            let historySeries = loadCronScopedHistorySeries(
                db: db,
                projectID: projectID,
                days: days,
                cronName: cronName
            )
            let runs = loadRecentCronRuns(
                db: db,
                projectID: projectID,
                cronName: cronName,
                limit: runLimit
            )
            let anomalies = loadRecentCronAnomalyRows(
                db: db,
                projectID: projectID,
                cronName: cronName,
                limit: anomalyLimit
            )
            let summary = loadCronReliabilitySummary(
                db: db,
                projectID: projectID,
                days: min(days, 30),
                cronName: cronName
            )

            let hasHistory = historySeries.contains { !$0.points.isEmpty }
            guard summary != nil || !runs.isEmpty || !anomalies.isEmpty || hasHistory else {
                return nil
            }

            return OpsCronDetail(
                cronName: cronName,
                summary: summary,
                historySeries: historySeries,
                runs: runs,
                anomalies: anomalies
            )
        }
    }

    func loadToolDetail(
        projectID: UUID,
        toolIdentifier: String,
        days: Int,
        spanLimit: Int,
        anomalyLimit: Int
    ) -> OpsToolDetail? {
        queue.sync {
            let dbURL = ProjectManager.shared.analyticsDatabaseURL(for: projectID)
            guard let db = openDatabase(at: dbURL) else { return nil }
            defer { sqlite3_close(db) }

            guard createSchema(in: db) else { return nil }

            let historySeries = loadToolScopedHistorySeries(
                db: db,
                projectID: projectID,
                days: days,
                toolIdentifier: toolIdentifier
            )
            let spans = loadRecentToolSpans(
                db: db,
                projectID: projectID,
                toolIdentifier: toolIdentifier,
                limit: spanLimit
            )
            let anomalies = loadRecentToolAnomalyRows(
                db: db,
                projectID: projectID,
                toolIdentifier: toolIdentifier,
                limit: anomalyLimit
            )

            let hasHistory = historySeries.contains { !$0.points.isEmpty }
            guard !spans.isEmpty || !anomalies.isEmpty || hasHistory else {
                return nil
            }

            return OpsToolDetail(
                toolIdentifier: toolIdentifier,
                historySeries: historySeries,
                spans: spans,
                anomalies: anomalies
            )
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

        guard sqlite3_exec(db, schemaSQL, nil, nil, nil) == SQLITE_OK else { return false }

        let cronColumnDefinitions: [(name: String, definition: String)] = [
            ("external_id", "TEXT"),
            ("run_at", "TEXT"),
            ("duration_ms", "REAL"),
            ("delivery_status", "TEXT"),
            ("summary", "TEXT"),
            ("source_path", "TEXT")
        ]

        for column in cronColumnDefinitions {
            guard ensureColumnExists(db: db, table: "cron_runs", column: column.name, definition: column.definition) else {
                return false
            }
        }

        let supplementalIndexSQL = """
        CREATE INDEX IF NOT EXISTS idx_cron_runs_project_run_at ON cron_runs(project_id, run_at);
        CREATE INDEX IF NOT EXISTS idx_cron_runs_project_date ON cron_runs(project_id, date);
        """

        return sqlite3_exec(db, supplementalIndexSQL, nil, nil, nil) == SQLITE_OK
    }

    private func ensureColumnExists(
        db: OpaquePointer,
        table: String,
        column: String,
        definition: String
    ) -> Bool {
        let pragmaSQL = "PRAGMA table_info(\(table));"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, pragmaSQL, -1, &statement, nil) == SQLITE_OK, let statement else {
            return false
        }
        defer { sqlite3_finalize(statement) }

        while sqlite3_step(statement) == SQLITE_ROW {
            guard let columnCString = sqlite3_column_text(statement, 1) else { continue }
            if String(cString: columnCString) == column {
                return true
            }
        }

        let alterSQL = "ALTER TABLE \(table) ADD COLUMN \(column) \(definition);"
        return sqlite3_exec(db, alterSQL, nil, nil, nil) == SQLITE_OK
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
        executionResults: [ExecutionResult],
        externalSignature: String
    ) -> String {
        let latestResultID = executionResults.last?.id.uuidString ?? "none"
        let latestTransportKind = executionResults.last?.transportKind ?? "none"
        let latestCompletionLatencyMs = executionResults.last?.completionLatencyMs ?? -1
        let latestFirstChunkLatencyMs = executionResults.last?.firstChunkLatencyMs ?? -1
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
            String(executionResults.count),
            latestResultID,
            latestTransportKind,
            String(latestCompletionLatencyMs),
            String(latestFirstChunkLatencyMs),
            String(latestUpdatedAt),
            externalSignature
        ].joined(separator: "::")
    }

    private func makeExternalArtifactsSignature(project: MAProject) -> ExternalOpsArtifactsSignature {
        let cronFiles = openClawCronRunFiles(for: project)
        let sessionFiles = openClawSessionFiles(for: project, limit: 60)

        return ExternalOpsArtifactsSignature(
            cronSignature: signature(for: cronFiles),
            sessionSignature: signature(for: sessionFiles)
        )
    }

    private func signature(for files: [URL]) -> String {
        guard !files.isEmpty else { return "none" }

        let latestStamp = files.compactMap { file -> String? in
            guard let values = try? file.resourceValues(forKeys: [.contentModificationDateKey]),
                  let date = values.contentModificationDate else {
                return nil
            }
            return "\(file.lastPathComponent):\(date.timeIntervalSinceReferenceDate)"
        }
        .sorted()
        .last ?? "unknown"

        return "\(files.count):\(latestStamp)"
    }

    private func openClawCandidateBackupRoots(for project: MAProject) -> [URL] {
        var roots: [URL] = [ProjectManager.shared.openClawBackupDirectory(for: project.id)]

        if let sessionBackupPath = project.openClaw.sessionBackupPath,
           !sessionBackupPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            roots.append(URL(fileURLWithPath: sessionBackupPath, isDirectory: true))
        }

        var seenPaths = Set<String>()
        var uniqueRoots: [URL] = []

        for root in roots {
            let normalizedPath = root.standardizedFileURL.path
            guard seenPaths.insert(normalizedPath).inserted else { continue }
            uniqueRoots.append(root)
        }

        return uniqueRoots
    }

    private func openClawCronRunFiles(for project: MAProject) -> [URL] {
        openClawCandidateBackupRoots(for: project)
            .flatMap { root in
                let cronRunsURL = root.appendingPathComponent("cron/runs", isDirectory: true)
                return ((try? FileManager.default.contentsOfDirectory(
                    at: cronRunsURL,
                    includingPropertiesForKeys: [.contentModificationDateKey],
                    options: [.skipsHiddenFiles]
                )) ?? [])
                .filter { $0.pathExtension == "jsonl" }
            }
            .sorted { lhs, rhs in
                let leftDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rightDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return leftDate > rightDate
            }
    }

    private func openClawSessionFiles(for project: MAProject, limit: Int) -> [URL] {
        let files = openClawCandidateBackupRoots(for: project)
            .flatMap { root in
                let agentsURL = root.appendingPathComponent("agents", isDirectory: true)
                let agentDirectories = (try? FileManager.default.contentsOfDirectory(
                    at: agentsURL,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                )) ?? []

                return agentDirectories.flatMap { agentDirectory in
                    let sessionsURL = agentDirectory.appendingPathComponent("sessions", isDirectory: true)
                    return ((try? FileManager.default.contentsOfDirectory(
                        at: sessionsURL,
                        includingPropertiesForKeys: [.contentModificationDateKey],
                        options: [.skipsHiddenFiles]
                    )) ?? [])
                    .filter { url in
                        url.pathExtension == "jsonl" && !url.lastPathComponent.contains(".deleted.")
                    }
                }
            }
            .sorted { lhs, rhs in
                let leftDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rightDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return leftDate > rightDate
            }

        return Array(files.prefix(limit))
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
        let gatewayExecutions = executionResults.filter { ($0.transportKind ?? "").hasPrefix("gateway_") }.count
        let gatewayAdoptionRate = totalExecutions > 0 ? (Double(gatewayExecutions) / Double(totalExecutions)) * 100.0 : 0.0
        let workflowHotPathExecutions = executionResults.filter { result in
            let sessionID = result.sessionID?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            return sessionID.hasPrefix("workflow-")
        }
        let matchedHotPathExecutions = workflowHotPathExecutions.filter {
            ($0.transportKind ?? "").lowercased() == "gateway_agent"
        }
        let hotPathMismatchCount = workflowHotPathExecutions.count - matchedHotPathExecutions.count
        let hotPathAdoptionRate = workflowHotPathExecutions.isEmpty
            ? 0.0
            : (Double(matchedHotPathExecutions.count) / Double(workflowHotPathExecutions.count)) * 100.0
        let firstChunkLatencies = executionResults.compactMap(\.firstChunkLatencyMs).map(Double.init)
        let completionLatencies = executionResults.compactMap(\.completionLatencyMs).map(Double.init)
        let averageFirstChunkLatency = firstChunkLatencies.isEmpty
            ? nil
            : firstChunkLatencies.reduce(0, +) / Double(firstChunkLatencies.count)
        let averageCompletionLatency = completionLatencies.isEmpty
            ? nil
            : completionLatencies.reduce(0, +) / Double(completionLatencies.count)

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
        upsertGoalMetric(
            db: db,
            projectID: projectID,
            date: dateString,
            goal: "transport_efficiency",
            metric: "gateway_adoption_rate",
            value: gatewayAdoptionRate,
            unit: "%",
            breakdown: [
                "gateway_runs": "\(gatewayExecutions)",
                "total_runs": "\(totalExecutions)"
            ]
        )
        upsertGoalMetric(
            db: db,
            projectID: projectID,
            date: dateString,
            goal: "transport_efficiency",
            metric: "workflow_hot_path_adoption_rate",
            value: hotPathAdoptionRate,
            unit: "%",
            breakdown: [
                "workflow_runs": "\(workflowHotPathExecutions.count)",
                "gateway_agent_runs": "\(matchedHotPathExecutions.count)"
            ]
        )
        upsertGoalMetric(
            db: db,
            projectID: projectID,
            date: dateString,
            goal: "transport_efficiency",
            metric: "workflow_hot_path_mismatch_count",
            value: Double(hotPathMismatchCount),
            unit: "count",
            breakdown: [
                "workflow_runs": "\(workflowHotPathExecutions.count)"
            ]
        )
        if let averageFirstChunkLatency {
            upsertGoalMetric(
                db: db,
                projectID: projectID,
                date: dateString,
                goal: "transport_efficiency",
                metric: "avg_first_chunk_latency_ms",
                value: averageFirstChunkLatency,
                unit: "ms",
                breakdown: ["sample_count": "\(firstChunkLatencies.count)"]
            )
        }
        if let averageCompletionLatency {
            upsertGoalMetric(
                db: db,
                projectID: projectID,
                date: dateString,
                goal: "transport_efficiency",
                metric: "avg_completion_latency_ms",
                value: averageCompletionLatency,
                unit: "ms",
                breakdown: ["sample_count": "\(completionLatencies.count)"]
            )
        }

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
            let normalizedSessionID = result.sessionID?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            let expectsWorkflowHotPath = normalizedSessionID.hasPrefix("workflow-")
            let matchedWorkflowHotPath = expectsWorkflowHotPath && (result.transportKind ?? "").lowercased() == "gateway_agent"

            let attributes: [String: String] = [
                "agent_id": result.agentID.uuidString,
                "agent_name": agentNamesByID[result.agentID] ?? "Unknown Agent",
                "node_id": result.nodeID.uuidString,
                "execution_status": result.status.rawValue,
                "output_type": result.outputType.rawValue,
                "session_id": result.sessionID ?? "",
                "transport_kind": result.transportKind ?? "",
                "first_chunk_latency_ms": result.firstChunkLatencyMs.map(String.init) ?? "",
                "completion_latency_ms": result.completionLatencyMs.map(String.init) ?? "",
                "routing_action": result.routingAction ?? "",
                "routing_reason": result.routingReason ?? "",
                "routing_targets": result.routingTargets.joined(separator: ", "),
                "protocol_event_count": String(result.runtimeEvents.count),
                "protocol_ref_count": String(result.runtimeRefCount),
                "protocol_event_types": result.runtimeEventTypesSummary,
                "workflow_hot_path_expected": expectsWorkflowHotPath ? "true" : "false",
                "workflow_hot_path_matched": matchedWorkflowHotPath ? "true" : "false",
                "output_text": result.renderedOutputText,
                "preview_text": result.previewText
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
                attributes: attributes,
                eventsText: result.runtimeEventsText
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

            if let firstChunkLatencyMs = result.firstChunkLatencyMs {
                let firstResponseAt = result.startedAt.addingTimeInterval(Double(firstChunkLatencyMs) / 1000.0)
                let firstResponseAttributes: [String: String] = [
                    "agent_name": agentNamesByID[result.agentID] ?? "Unknown Agent",
                    "transport_kind": result.transportKind ?? "",
                    "session_id": result.sessionID ?? "",
                    "first_chunk_latency_ms": String(firstChunkLatencyMs)
                ]

                upsertSpan(
                    db: db,
                    spanID: "\(result.id.uuidString)-first-response",
                    projectID: projectID,
                    traceID: traceID,
                    parentSpanID: result.id.uuidString,
                    name: "First Response",
                    service: "multi-agent-flow.streaming",
                    status: "ok",
                    startTime: result.startedAt,
                    endTime: firstResponseAt,
                    durationMs: Double(firstChunkLatencyMs),
                    attributes: firstResponseAttributes
                )
            }

            if !result.renderedOutputText.isEmpty {
                let outputAttributes: [String: String] = [
                    "agent_name": agentNamesByID[result.agentID] ?? "Unknown Agent",
                    "output_type": result.outputType.rawValue,
                    "preview_text": result.previewText
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
                    attributes: outputAttributes,
                    eventsText: result.runtimeEventsText
                )
            }
        }
    }

    private func ingestExternalOpenClawArtifacts(
        db: OpaquePointer,
        project: MAProject
    ) {
        let projectID = project.id.uuidString
        let cronArtifacts = openClawCronRunFiles(for: project).flatMap(loadCronArtifacts(from:))

        replaceCronRuns(
            db: db,
            projectID: projectID,
            artifacts: cronArtifacts
        )
        rebuildCronReliabilityGoalMetrics(
            db: db,
            projectID: projectID,
            artifacts: cronArtifacts
        )

        let sessionArtifacts = openClawSessionFiles(for: project, limit: 60).compactMap(loadExternalSessionArtifact(from:))
        replaceExternalSessionSpans(
            db: db,
            projectID: projectID,
            artifacts: sessionArtifacts
        )
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

    private func replaceCronRuns(
        db: OpaquePointer,
        projectID: String,
        artifacts: [ExternalCronRunArtifact]
    ) {
        let deleteSQL = "DELETE FROM cron_runs WHERE project_id = ?;"
        var deleteStatement: OpaquePointer?
        if sqlite3_prepare_v2(db, deleteSQL, -1, &deleteStatement, nil) == SQLITE_OK, let deleteStatement {
            bindText(projectID, to: 1, in: deleteStatement)
            sqlite3_step(deleteStatement)
            sqlite3_finalize(deleteStatement)
        }

        let insertSQL = """
        INSERT INTO cron_runs
        (project_id, date, cron_name, slot_time, status, job_id, run_id, error, external_id, run_at, duration_ms, delivery_status, summary, source_path, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, datetime('now'));
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, insertSQL, -1, &statement, nil) == SQLITE_OK, let statement else { return }
        defer { sqlite3_finalize(statement) }

        for artifact in artifacts {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)

            bindText(projectID, to: 1, in: statement)
            bindText(artifact.date, to: 2, in: statement)
            bindText(artifact.cronName, to: 3, in: statement)
            bindText(iso8601.string(from: artifact.runAt), to: 4, in: statement)
            bindText(artifact.status, to: 5, in: statement)
            bindText(artifact.jobID, to: 6, in: statement)
            bindText(artifact.runID, to: 7, in: statement)
            bindText(artifact.errorText, to: 8, in: statement)
            bindText(artifact.externalID, to: 9, in: statement)
            bindText(iso8601.string(from: artifact.runAt), to: 10, in: statement)
            if let durationMs = artifact.durationMs {
                sqlite3_bind_double(statement, 11, durationMs)
            } else {
                sqlite3_bind_null(statement, 11)
            }
            bindText(artifact.deliveryStatus, to: 12, in: statement)
            bindText(artifact.summaryText, to: 13, in: statement)
            bindText(artifact.sourcePath, to: 14, in: statement)
            sqlite3_step(statement)
        }
    }

    private func rebuildCronReliabilityGoalMetrics(
        db: OpaquePointer,
        projectID: String,
        artifacts: [ExternalCronRunArtifact]
    ) {
        let deleteSQL = "DELETE FROM goal_metrics WHERE project_id = ? AND goal = 'cron_reliability';"
        var deleteStatement: OpaquePointer?
        if sqlite3_prepare_v2(db, deleteSQL, -1, &deleteStatement, nil) == SQLITE_OK, let deleteStatement {
            bindText(projectID, to: 1, in: deleteStatement)
            sqlite3_step(deleteStatement)
            sqlite3_finalize(deleteStatement)
        }

        guard !artifacts.isEmpty else { return }

        var countsByDate: [String: (success: Int, failed: Int)] = [:]
        for artifact in artifacts {
            var bucket = countsByDate[artifact.date, default: (0, 0)]
            if isSuccessfulCronStatus(artifact.status) {
                bucket.success += 1
            } else {
                bucket.failed += 1
            }
            countsByDate[artifact.date] = bucket
        }

        for (date, bucket) in countsByDate {
            let total = bucket.success + bucket.failed
            let successRate = total > 0 ? (Double(bucket.success) / Double(total)) * 100.0 : 0

            upsertGoalMetric(
                db: db,
                projectID: projectID,
                date: date,
                goal: "cron_reliability",
                metric: "success_rate",
                value: successRate,
                unit: "%",
                breakdown: [
                    "successful_runs": "\(bucket.success)",
                    "failed_runs": "\(bucket.failed)"
                ]
            )
            upsertGoalMetric(
                db: db,
                projectID: projectID,
                date: date,
                goal: "cron_reliability",
                metric: "successful_runs",
                value: Double(bucket.success),
                unit: "count",
                breakdown: nil
            )
            upsertGoalMetric(
                db: db,
                projectID: projectID,
                date: date,
                goal: "cron_reliability",
                metric: "failed_runs",
                value: Double(bucket.failed),
                unit: "count",
                breakdown: nil
            )
        }
    }

    private func replaceExternalSessionSpans(
        db: OpaquePointer,
        projectID: String,
        artifacts: [ExternalSessionTraceArtifact]
    ) {
        let deleteSQL = "DELETE FROM spans WHERE project_id = ? AND service LIKE 'openclaw.external-%';"
        var deleteStatement: OpaquePointer?
        if sqlite3_prepare_v2(db, deleteSQL, -1, &deleteStatement, nil) == SQLITE_OK, let deleteStatement {
            bindText(projectID, to: 1, in: deleteStatement)
            sqlite3_step(deleteStatement)
            sqlite3_finalize(deleteStatement)
        }

        for artifact in artifacts {
            upsertSpan(
                db: db,
                spanID: artifact.spanID,
                projectID: projectID,
                traceID: artifact.traceID,
                parentSpanID: nil,
                name: artifact.agentName,
                service: "openclaw.external-session",
                status: artifact.status,
                startTime: artifact.startedAt,
                endTime: artifact.completedAt,
                durationMs: artifact.durationMs,
                attributes: artifact.attributes,
                eventsText: artifact.eventsText
            )

            for child in artifact.childSpans {
                upsertSpan(
                    db: db,
                    spanID: child.spanID,
                    projectID: projectID,
                    traceID: artifact.traceID,
                    parentSpanID: child.parentSpanID,
                    name: child.name,
                    service: child.service,
                    status: child.status,
                    startTime: child.startedAt,
                    endTime: child.completedAt,
                    durationMs: child.durationMs,
                    attributes: child.attributes,
                    eventsText: child.eventsText
                )
            }
        }
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
        attributes: [String: String],
        eventsText: String? = nil
    ) {
        let sql = """
        INSERT OR REPLACE INTO spans
        (span_id, project_id, trace_id, parent_span_id, name, service, status, start_time, end_time, duration_ms, attributes, events, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, datetime('now'));
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
        bindText(eventsText, to: 12, in: statement)
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
        SELECT span_id, start_time, duration_ms, attributes, service, status, events
        FROM spans
        WHERE project_id = ?
          AND service IN ('multi-agent-flow.execution', 'openclaw.external-session')
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
                  let serviceCString = sqlite3_column_text(statement, 4),
                  let statusCString = sqlite3_column_text(statement, 5),
                  let id = UUID(uuidString: String(cString: spanCString)),
                  let startedAt = iso8601.date(from: String(cString: startCString)) else {
                continue
            }

            let durationMs = sqlite3_column_type(statement, 2) == SQLITE_NULL ? nil : sqlite3_column_double(statement, 2)
            let attributes = dictionary(from: String(cString: attributesCString))
            let service = String(cString: serviceCString)
            let status = String(cString: statusCString)
            let eventsText = sqlite3_column_type(statement, 6) == SQLITE_NULL
                ? nil
                : String(cString: sqlite3_column_text(statement, 6))
            let executionStatus = ExecutionStatus(rawValue: attributes["execution_status"] ?? "") ?? executionStatus(forSpanStatus: status)
            let outputType = ExecutionOutputType(rawValue: attributes["output_type"] ?? "") ?? .empty
            let previewText = emptyToNil(attributes["preview_text"])
                ?? emptyToNil(eventsText?.compactSingleLinePreview(limit: 160))
                ?? "No output"

            rows.append(
                OpsTraceSummaryRow(
                    id: id,
                    agentName: attributes["agent_name"] ?? "Unknown Agent",
                    status: executionStatus,
                    duration: durationMs.map { $0 / 1000.0 },
                    startedAt: startedAt,
                    routingAction: emptyToNil(attributes["routing_action"]),
                    outputType: outputType,
                    sourceLabel: service == "openclaw.external-session" ? "OpenClaw" : "Runtime",
                    previewText: previewText
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
            OR (goal = 'cron_reliability' AND metric = 'success_rate')
          )
        ORDER BY date ASC;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            return emptyHistorySeries()
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

        return buildHistorySeries(from: pointsByMetric)
    }

    private func loadScopedHistorySeries(
        db: OpaquePointer,
        projectID: UUID,
        days: Int,
        scopeKind: String,
        scopeValue: String,
        scopeMatchKey: String
    ) -> [OpsMetricHistorySeries] {
        switch scopeKind {
        case "project":
            return loadGoalMetricSeries(db: db, projectID: projectID, days: days)
        case "agent":
            return loadAgentScopedHistorySeries(
                db: db,
                projectID: projectID,
                days: days,
                agentID: scopeValue,
                agentName: scopeMatchKey
            )
        case "tool":
            return loadToolScopedHistorySeries(
                db: db,
                projectID: projectID,
                days: days,
                toolIdentifier: scopeValue
            )
        case "cron":
            return loadCronScopedHistorySeries(
                db: db,
                projectID: projectID,
                days: days,
                cronName: scopeValue
            )
        default:
            return emptyHistorySeries()
        }
    }

    private func loadAgentScopedHistorySeries(
        db: OpaquePointer,
        projectID: UUID,
        days: Int,
        agentID: String,
        agentName: String
    ) -> [OpsMetricHistorySeries] {
        var pointsByMetric: [OpsHistoryMetric: [OpsMetricHistoryPoint]] = [:]
        let projectIDText = projectID.uuidString
        let normalizedAgentName = agentName.lowercased()

        let reliabilitySQL = """
        SELECT date(start_time), status, COUNT(*)
        FROM spans
        WHERE project_id = ?
          AND service IN ('multi-agent-flow.execution', 'openclaw.external-session')
          AND lower(COALESCE(json_extract(attributes, '$.agent_name'), '')) = ?
          AND date(start_time) >= date('now', ?)
        GROUP BY date(start_time), status
        ORDER BY date(start_time) ASC;
        """

        let reliabilityRows = groupedCountsByDate(
            db: db,
            sql: reliabilitySQL,
            bindings: [projectIDText, normalizedAgentName, "-\(days) days"]
        )
        pointsByMetric[.workflowReliability] = ratePoints(
            from: reliabilityRows,
            successKeys: ["ok"],
            failureKeys: ["error"]
        )
        pointsByMetric[.errorBudget] = countPoints(
            db: db,
            sql: """
            SELECT date(start_time), COUNT(*)
            FROM spans
            WHERE project_id = ?
              AND lower(COALESCE(json_extract(attributes, '$.agent_name'), '')) = ?
              AND date(start_time) >= date('now', ?)
              AND (
                status = 'error'
                OR lower(COALESCE(events, '')) LIKE '%timeout%'
                OR lower(COALESCE(attributes, '')) LIKE '%timeout%'
              )
            GROUP BY date(start_time)
            ORDER BY date(start_time) ASC;
            """,
            bindings: [projectIDText, normalizedAgentName, "-\(days) days"]
        )
        pointsByMetric[.agentEngagement] = countPoints(
            db: db,
            sql: """
            SELECT date, CASE WHEN session_count > 0 THEN 100 ELSE 0 END
            FROM daily_agent_activity
            WHERE project_id = ?
              AND agent_id = ?
              AND date >= date('now', ?)
            ORDER BY date ASC;
            """,
            bindings: [projectIDText, agentID, "-\(days) days"]
        )
        pointsByMetric[.memoryDiscipline] = countPoints(
            db: db,
            sql: """
            SELECT date, CASE WHEN memory_logged = 1 THEN 100 ELSE 0 END
            FROM daily_agent_activity
            WHERE project_id = ?
              AND agent_id = ?
              AND date >= date('now', ?)
            ORDER BY date ASC;
            """,
            bindings: [projectIDText, agentID, "-\(days) days"]
        )
        pointsByMetric[.cronReliability] = ratePoints(
            from: groupedCountsByDate(
                db: db,
                sql: """
                SELECT date, lower(COALESCE(status, 'unknown')), COUNT(*)
                FROM cron_runs
                WHERE project_id = ?
                  AND date >= date('now', ?)
                  AND (
                    lower(cron_name) LIKE '%' || ? || '%'
                    OR lower(COALESCE(summary, '')) LIKE '%' || ? || '%'
                  )
                GROUP BY date, lower(COALESCE(status, 'unknown'))
                ORDER BY date ASC;
                """,
                bindings: [projectIDText, "-\(days) days", normalizedAgentName, normalizedAgentName]
            ),
            successKeys: ["ok", "success", "completed", "delivered"],
            failureKeys: ["error", "failed", "timeout"]
        )

        return buildHistorySeries(from: pointsByMetric)
    }

    private func loadToolScopedHistorySeries(
        db: OpaquePointer,
        projectID: UUID,
        days: Int,
        toolIdentifier: String
    ) -> [OpsMetricHistorySeries] {
        var pointsByMetric: [OpsHistoryMetric: [OpsMetricHistoryPoint]] = [:]
        let projectIDText = projectID.uuidString
        let normalizedToolIdentifier = toolIdentifier.lowercased()

        let groupedRows = groupedCountsByDate(
            db: db,
            sql: """
            SELECT date(start_time), status, COUNT(*)
            FROM spans
            WHERE project_id = ?
              AND service LIKE '%tool%'
              AND date(start_time) >= date('now', ?)
              AND (
                lower(service) LIKE '%' || ? || '%'
                OR lower(name) LIKE '%' || ? || '%'
                OR lower(COALESCE(attributes, '')) LIKE '%' || ? || '%'
              )
            GROUP BY date(start_time), status
            ORDER BY date(start_time) ASC;
            """,
            bindings: [
                projectIDText,
                "-\(days) days",
                normalizedToolIdentifier,
                normalizedToolIdentifier,
                normalizedToolIdentifier
            ]
        )

        pointsByMetric[.workflowReliability] = ratePoints(
            from: groupedRows,
            successKeys: ["ok"],
            failureKeys: ["error"]
        )
        pointsByMetric[.errorBudget] = countPoints(
            db: db,
            sql: """
            SELECT date(start_time), COUNT(*)
            FROM spans
            WHERE project_id = ?
              AND service LIKE '%tool%'
              AND date(start_time) >= date('now', ?)
              AND (
                lower(service) LIKE '%' || ? || '%'
                OR lower(name) LIKE '%' || ? || '%'
                OR lower(COALESCE(attributes, '')) LIKE '%' || ? || '%'
              )
              AND (
                status = 'error'
                OR lower(COALESCE(events, '')) LIKE '%timeout%'
                OR lower(COALESCE(attributes, '')) LIKE '%timeout%'
              )
            GROUP BY date(start_time)
            ORDER BY date(start_time) ASC;
            """,
            bindings: [
                projectIDText,
                "-\(days) days",
                normalizedToolIdentifier,
                normalizedToolIdentifier,
                normalizedToolIdentifier
            ]
        )

        return buildHistorySeries(from: pointsByMetric)
    }

    private func loadCronScopedHistorySeries(
        db: OpaquePointer,
        projectID: UUID,
        days: Int,
        cronName: String
    ) -> [OpsMetricHistorySeries] {
        var pointsByMetric: [OpsHistoryMetric: [OpsMetricHistoryPoint]] = [:]
        let projectIDText = projectID.uuidString
        let normalizedCronName = cronName.lowercased()

        let groupedRows = groupedCountsByDate(
            db: db,
            sql: """
            SELECT date, lower(COALESCE(status, 'unknown')), COUNT(*)
            FROM cron_runs
            WHERE project_id = ?
              AND date >= date('now', ?)
              AND lower(cron_name) = ?
            GROUP BY date, lower(COALESCE(status, 'unknown'))
            ORDER BY date ASC;
            """,
            bindings: [projectIDText, "-\(days) days", normalizedCronName]
        )

        pointsByMetric[.cronReliability] = ratePoints(
            from: groupedRows,
            successKeys: ["ok", "success", "completed", "delivered"],
            failureKeys: ["error", "failed", "timeout"]
        )
        pointsByMetric[.errorBudget] = countPoints(
            db: db,
            sql: """
            SELECT date, COUNT(*)
            FROM cron_runs
            WHERE project_id = ?
              AND date >= date('now', ?)
              AND lower(cron_name) = ?
              AND lower(COALESCE(status, 'unknown')) NOT IN ('ok', 'success', 'completed', 'delivered')
            GROUP BY date
            ORDER BY date ASC;
            """,
            bindings: [projectIDText, "-\(days) days", normalizedCronName]
        )

        return buildHistorySeries(from: pointsByMetric)
    }

    private func groupedCountsByDate(
        db: OpaquePointer,
        sql: String,
        bindings: [String]
    ) -> [String: [String: Int]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return [:] }
        defer { sqlite3_finalize(statement) }

        for (index, value) in bindings.enumerated() {
            bindText(value, to: Int32(index + 1), in: statement)
        }

        var rows: [String: [String: Int]] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let dateCString = sqlite3_column_text(statement, 0),
                  let keyCString = sqlite3_column_text(statement, 1) else {
                continue
            }

            let date = String(cString: dateCString)
            let key = String(cString: keyCString).lowercased()
            let count = Int(sqlite3_column_int(statement, 2))
            rows[date, default: [:]][key, default: 0] += count
        }
        return rows
    }

    private func ratePoints(
        from groupedRows: [String: [String: Int]],
        successKeys: Set<String>,
        failureKeys: Set<String>
    ) -> [OpsMetricHistoryPoint] {
        groupedRows.keys.sorted().compactMap { dateString in
            guard let date = dayFormatter.date(from: dateString),
                  let row = groupedRows[dateString] else {
                return nil
            }

            let successCount = row
                .filter { successKeys.contains($0.key) }
                .map(\.value)
                .reduce(0, +)
            let failureCount = row
                .filter { failureKeys.contains($0.key) }
                .map(\.value)
                .reduce(0, +)
            let total = successCount + failureCount
            guard total > 0 else { return nil }

            return OpsMetricHistoryPoint(
                date: date,
                value: (Double(successCount) / Double(total)) * 100.0
            )
        }
    }

    private func countPoints(
        db: OpaquePointer,
        sql: String,
        bindings: [String]
    ) -> [OpsMetricHistoryPoint] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return [] }
        defer { sqlite3_finalize(statement) }

        for (index, value) in bindings.enumerated() {
            bindText(value, to: Int32(index + 1), in: statement)
        }

        var points: [OpsMetricHistoryPoint] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let dateCString = sqlite3_column_text(statement, 0),
                  let date = dayFormatter.date(from: String(cString: dateCString)) else {
                continue
            }

            let value = sqlite3_column_double(statement, 1)
            points.append(OpsMetricHistoryPoint(date: date, value: value))
        }
        return points.sorted { $0.date < $1.date }
    }

    private func buildHistorySeries(
        from pointsByMetric: [OpsHistoryMetric: [OpsMetricHistoryPoint]]
    ) -> [OpsMetricHistorySeries] {
        OpsHistoryMetric.allCases.map { metric in
            OpsMetricHistorySeries(
                metric: metric,
                points: pointsByMetric[metric, default: []].sorted { $0.date < $1.date }
            )
        }
    }

    private func emptyHistorySeries() -> [OpsMetricHistorySeries] {
        OpsHistoryMetric.allCases.map { OpsMetricHistorySeries(metric: $0, points: []) }
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

        let normalizedEventsText = emptyToNil(eventsText)
        let previewText = emptyToNil(attributes["preview_text"])
            ?? emptyToNil(normalizedEventsText?.compactSingleLinePreview(limit: 160))
            ?? "No output"
        let outputText = emptyToNil(attributes["output_text"])
            ?? normalizedEventsText
            ?? ""

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
            previewText: previewText,
            outputText: outputText,
            attributes: attributes,
            eventsText: normalizedEventsText,
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
        ORDER BY
          start_time ASC,
          CASE name
            WHEN 'User Prompt' THEN 0
            WHEN 'Assistant Turn' THEN 1
            WHEN 'Tool Call' THEN 2
            WHEN 'Tool Result' THEN 3
            WHEN 'Routing Decision' THEN 4
            WHEN 'Output Emission' THEN 5
            ELSE 6
          END ASC,
          created_at ASC,
          span_id ASC;
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

    private func loadCronReliabilitySummary(
        db: OpaquePointer,
        projectID: UUID,
        days: Int
    ) -> OpsCronReliabilitySummary? {
        let sql = """
        SELECT status, COALESCE(run_at, slot_time, created_at)
        FROM cron_runs
        WHERE project_id = ? AND date >= date('now', ?);
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return nil }
        defer { sqlite3_finalize(statement) }

        bindText(projectID.uuidString, to: 1, in: statement)
        bindText("-\(days) days", to: 2, in: statement)

        var successfulRuns = 0
        var failedRuns = 0
        var latestRunAt: Date?

        while sqlite3_step(statement) == SQLITE_ROW {
            guard let statusCString = sqlite3_column_text(statement, 0) else { continue }

            let status = String(cString: statusCString)
            if isSuccessfulCronStatus(status) {
                successfulRuns += 1
            } else {
                failedRuns += 1
            }

            if let runDateCString = sqlite3_column_text(statement, 1),
               let runDate = iso8601.date(from: String(cString: runDateCString)) {
                latestRunAt = max(latestRunAt ?? .distantPast, runDate)
            }
        }

        let totalRuns = successfulRuns + failedRuns
        guard totalRuns > 0 else { return nil }

        return OpsCronReliabilitySummary(
            successRate: (Double(successfulRuns) / Double(totalRuns)) * 100.0,
            successfulRuns: successfulRuns,
            failedRuns: failedRuns,
            latestRunAt: latestRunAt
        )
    }

    private func loadCronReliabilitySummary(
        db: OpaquePointer,
        projectID: UUID,
        days: Int,
        cronName: String
    ) -> OpsCronReliabilitySummary? {
        let sql = """
        SELECT status, COALESCE(run_at, slot_time, created_at)
        FROM cron_runs
        WHERE project_id = ?
          AND date >= date('now', ?)
          AND lower(cron_name) = ?;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return nil }
        defer { sqlite3_finalize(statement) }

        bindText(projectID.uuidString, to: 1, in: statement)
        bindText("-\(days) days", to: 2, in: statement)
        bindText(cronName.lowercased(), to: 3, in: statement)

        var successfulRuns = 0
        var failedRuns = 0
        var latestRunAt: Date?

        while sqlite3_step(statement) == SQLITE_ROW {
            guard let statusCString = sqlite3_column_text(statement, 0) else { continue }

            let status = String(cString: statusCString)
            if isSuccessfulCronStatus(status) {
                successfulRuns += 1
            } else {
                failedRuns += 1
            }

            if let runDateCString = sqlite3_column_text(statement, 1),
               let runDate = iso8601.date(from: String(cString: runDateCString)) {
                latestRunAt = max(latestRunAt ?? .distantPast, runDate)
            }
        }

        let totalRuns = successfulRuns + failedRuns
        guard totalRuns > 0 else { return nil }

        return OpsCronReliabilitySummary(
            successRate: (Double(successfulRuns) / Double(totalRuns)) * 100.0,
            successfulRuns: successfulRuns,
            failedRuns: failedRuns,
            latestRunAt: latestRunAt
        )
    }

    private func loadRecentCronRuns(
        db: OpaquePointer,
        projectID: UUID,
        limit: Int
    ) -> [OpsCronRunRow] {
        let sql = """
        SELECT
            COALESCE(external_id, run_id, job_id, cron_name || '-' || COALESCE(run_at, slot_time, created_at)),
            cron_name,
            status,
            COALESCE(run_at, slot_time, created_at),
            duration_ms,
            delivery_status,
            summary,
            error,
            job_id,
            run_id,
            source_path
        FROM cron_runs
        WHERE project_id = ?
        ORDER BY COALESCE(run_at, slot_time, created_at) DESC
        LIMIT ?;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return [] }
        defer { sqlite3_finalize(statement) }

        bindText(projectID.uuidString, to: 1, in: statement)
        sqlite3_bind_int(statement, 2, Int32(limit))

        var rows: [OpsCronRunRow] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let idCString = sqlite3_column_text(statement, 0),
                  let cronNameCString = sqlite3_column_text(statement, 1),
                  let statusCString = sqlite3_column_text(statement, 2),
                  let runAtCString = sqlite3_column_text(statement, 3),
                  let runAt = iso8601.date(from: String(cString: runAtCString)) else {
                continue
            }

            let durationMs = sqlite3_column_type(statement, 4) == SQLITE_NULL ? nil : sqlite3_column_double(statement, 4)
            let deliveryStatus = sqlite3_column_type(statement, 5) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(statement, 5))
            let summary = sqlite3_column_type(statement, 6) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(statement, 6))
            let error = sqlite3_column_type(statement, 7) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(statement, 7))
            let jobID = sqlite3_column_type(statement, 8) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(statement, 8))
            let runID = sqlite3_column_type(statement, 9) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(statement, 9))
            let sourcePath = sqlite3_column_type(statement, 10) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(statement, 10))

            rows.append(
                OpsCronRunRow(
                    id: String(cString: idCString),
                    cronName: String(cString: cronNameCString),
                    statusText: formattedCronStatus(String(cString: statusCString)),
                    runAt: runAt,
                    duration: durationMs.map { $0 / 1000.0 },
                    deliveryStatus: emptyToNil(deliveryStatus),
                    summaryText: emptyToNil(summary) ?? emptyToNil(error) ?? "No summary captured",
                    jobID: emptyToNil(jobID),
                    runID: emptyToNil(runID),
                    sourcePath: emptyToNil(sourcePath)
                )
            )
        }

        return rows
    }

    private func loadRecentCronRuns(
        db: OpaquePointer,
        projectID: UUID,
        cronName: String,
        limit: Int
    ) -> [OpsCronRunRow] {
        let sql = """
        SELECT
            COALESCE(external_id, run_id, job_id, cron_name || '-' || COALESCE(run_at, slot_time, created_at)),
            cron_name,
            status,
            COALESCE(run_at, slot_time, created_at),
            duration_ms,
            delivery_status,
            summary,
            error,
            job_id,
            run_id,
            source_path
        FROM cron_runs
        WHERE project_id = ?
          AND lower(cron_name) = ?
        ORDER BY COALESCE(run_at, slot_time, created_at) DESC
        LIMIT ?;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return [] }
        defer { sqlite3_finalize(statement) }

        bindText(projectID.uuidString, to: 1, in: statement)
        bindText(cronName.lowercased(), to: 2, in: statement)
        sqlite3_bind_int(statement, 3, Int32(limit))

        var rows: [OpsCronRunRow] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let idCString = sqlite3_column_text(statement, 0),
                  let cronNameCString = sqlite3_column_text(statement, 1),
                  let statusCString = sqlite3_column_text(statement, 2),
                  let runAtCString = sqlite3_column_text(statement, 3),
                  let runAt = iso8601.date(from: String(cString: runAtCString)) else {
                continue
            }

            let durationMs = sqlite3_column_type(statement, 4) == SQLITE_NULL ? nil : sqlite3_column_double(statement, 4)
            let deliveryStatus = sqlite3_column_type(statement, 5) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(statement, 5))
            let summary = sqlite3_column_type(statement, 6) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(statement, 6))
            let error = sqlite3_column_type(statement, 7) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(statement, 7))
            let jobID = sqlite3_column_type(statement, 8) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(statement, 8))
            let runID = sqlite3_column_type(statement, 9) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(statement, 9))
            let sourcePath = sqlite3_column_type(statement, 10) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(statement, 10))

            rows.append(
                OpsCronRunRow(
                    id: String(cString: idCString),
                    cronName: String(cString: cronNameCString),
                    statusText: formattedCronStatus(String(cString: statusCString)),
                    runAt: runAt,
                    duration: durationMs.map { $0 / 1000.0 },
                    deliveryStatus: emptyToNil(deliveryStatus),
                    summaryText: emptyToNil(summary) ?? emptyToNil(error) ?? "No summary captured",
                    jobID: emptyToNil(jobID),
                    runID: emptyToNil(runID),
                    sourcePath: emptyToNil(sourcePath)
                )
            )
        }

        return rows
    }

    private func loadRecentToolSpans(
        db: OpaquePointer,
        projectID: UUID,
        toolIdentifier: String,
        limit: Int
    ) -> [OpsToolSpanRow] {
        let normalizedToolIdentifier = toolIdentifier.lowercased()
        let sql = """
        SELECT span_id, name, service, status, start_time, duration_ms, attributes, events
        FROM spans
        WHERE project_id = ?
          AND service LIKE '%tool%'
          AND (
            lower(service) LIKE '%' || ? || '%'
            OR lower(name) LIKE '%' || ? || '%'
            OR lower(COALESCE(attributes, '')) LIKE '%' || ? || '%'
          )
        ORDER BY start_time DESC
        LIMIT ?;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return [] }
        defer { sqlite3_finalize(statement) }

        bindText(projectID.uuidString, to: 1, in: statement)
        bindText(normalizedToolIdentifier, to: 2, in: statement)
        bindText(normalizedToolIdentifier, to: 3, in: statement)
        bindText(normalizedToolIdentifier, to: 4, in: statement)
        sqlite3_bind_int(statement, 5, Int32(limit))

        var rows: [OpsToolSpanRow] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let spanCString = sqlite3_column_text(statement, 0),
                  let nameCString = sqlite3_column_text(statement, 1),
                  let serviceCString = sqlite3_column_text(statement, 2),
                  let statusCString = sqlite3_column_text(statement, 3),
                  let startCString = sqlite3_column_text(statement, 4),
                  let id = UUID(uuidString: String(cString: spanCString)),
                  let startedAt = iso8601.date(from: String(cString: startCString)) else {
                continue
            }

            let durationMs = sqlite3_column_type(statement, 5) == SQLITE_NULL ? nil : sqlite3_column_double(statement, 5)
            let attributes = sqlite3_column_type(statement, 6) == SQLITE_NULL
                ? [:]
                : dictionary(from: String(cString: sqlite3_column_text(statement, 6)))
            let eventsText = sqlite3_column_type(statement, 7) == SQLITE_NULL
                ? nil
                : String(cString: sqlite3_column_text(statement, 7))
            let summaryText = emptyToNil(attributes["preview_text"])
                ?? emptyToNil(eventsText?.compactSingleLinePreview(limit: 180))
                ?? String(cString: nameCString)

            rows.append(
                OpsToolSpanRow(
                    id: id,
                    title: String(cString: nameCString),
                    service: String(cString: serviceCString),
                    statusText: String(cString: statusCString),
                    agentName: attributes["agent_name"] ?? "Unknown Agent",
                    startedAt: startedAt,
                    duration: durationMs.map { $0 / 1000.0 },
                    summaryText: summaryText
                )
            )
        }

        return rows
    }

    private func loadAnomalySummary(
        db: OpaquePointer,
        projectID: UUID
    ) -> OpsAnomalySummary? {
        let projectIDText = projectID.uuidString
        let cronFailures24h = countCronFailures(db: db, projectID: projectIDText, window: "-1 day")
        let cronFailures7d = countCronFailures(db: db, projectID: projectIDText, window: "-7 days")
        let runtimeFailures24h = countSpanFailures(
            db: db,
            projectID: projectIDText,
            services: ["multi-agent-flow.execution", "openclaw.external-session"],
            window: "-1 day"
        )
        let runtimeFailures7d = countSpanFailures(
            db: db,
            projectID: projectIDText,
            services: ["multi-agent-flow.execution", "openclaw.external-session"],
            window: "-7 days"
        )
        let toolFailures24h = countSpanFailures(
            db: db,
            projectID: projectIDText,
            services: ["openclaw.external-tool-result"],
            window: "-1 day"
        )
        let toolFailures7d = countSpanFailures(
            db: db,
            projectID: projectIDText,
            services: ["openclaw.external-tool-result"],
            window: "-7 days"
        )
        let timeoutCount7d = countTimeouts(db: db, projectID: projectIDText, window: "-7 days")
        let latestAnomalyAt = latestAnomalyDate(db: db, projectID: projectIDText)

        guard runtimeFailures7d > 0 || cronFailures7d > 0 || toolFailures7d > 0 || timeoutCount7d > 0 || latestAnomalyAt != nil else {
            return nil
        }

        return OpsAnomalySummary(
            runtimeFailures24h: runtimeFailures24h,
            runtimeFailures7d: runtimeFailures7d,
            cronFailures24h: cronFailures24h,
            cronFailures7d: cronFailures7d,
            toolFailures24h: toolFailures24h,
            toolFailures7d: toolFailures7d,
            timeoutCount7d: timeoutCount7d,
            latestAnomalyAt: latestAnomalyAt
        )
    }

    private func loadRecentAnomalyRows(
        db: OpaquePointer,
        projectID: UUID,
        limit: Int
    ) -> [OpsAnomalyRow] {
        let projectIDText = projectID.uuidString
        var rows: [OpsAnomalyRow] = []

        let cronSQL = """
        SELECT
            COALESCE(external_id, run_id, job_id, cron_name || '-' || COALESCE(run_at, slot_time, created_at)),
            cron_name,
            COALESCE(status, 'unknown'),
            COALESCE(error, summary, 'Cron anomaly'),
            COALESCE(run_at, slot_time, created_at),
            job_id,
            run_id,
            source_path
        FROM cron_runs
        WHERE project_id = ?
          AND status NOT IN ('ok', 'success', 'completed', 'delivered')
        ORDER BY COALESCE(run_at, slot_time, created_at) DESC
        LIMIT ?;
        """

        var cronStatement: OpaquePointer?
        if sqlite3_prepare_v2(db, cronSQL, -1, &cronStatement, nil) == SQLITE_OK, let cronStatement {
            defer { sqlite3_finalize(cronStatement) }
            bindText(projectIDText, to: 1, in: cronStatement)
            sqlite3_bind_int(cronStatement, 2, Int32(limit))

            while sqlite3_step(cronStatement) == SQLITE_ROW {
                guard let idCString = sqlite3_column_text(cronStatement, 0),
                      let nameCString = sqlite3_column_text(cronStatement, 1),
                      let statusCString = sqlite3_column_text(cronStatement, 2),
                      let detailCString = sqlite3_column_text(cronStatement, 3),
                      let dateCString = sqlite3_column_text(cronStatement, 4),
                      let occurredAt = iso8601.date(from: String(cString: dateCString)) else {
                    continue
                }

                let rawStatus = String(cString: statusCString)
                let jobID = sqlite3_column_type(cronStatement, 5) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(cronStatement, 5))
                let runID = sqlite3_column_type(cronStatement, 6) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(cronStatement, 6))
                let sourcePath = sqlite3_column_type(cronStatement, 7) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(cronStatement, 7))
                let detailText = String(cString: detailCString)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let normalizedDetail = detailText.isEmpty ? "Cron anomaly" : detailText

                rows.append(
                    OpsAnomalyRow(
                        id: "cron-\(String(cString: idCString))",
                        title: String(cString: nameCString),
                        sourceLabel: "Cron",
                        detailText: normalizedDetail.compactSingleLinePreview(limit: 180),
                        fullDetailText: normalizedDetail,
                        occurredAt: occurredAt,
                        status: cronAnomalyStatus(for: rawStatus),
                        statusText: formattedCronStatus(rawStatus),
                        sourceService: nil,
                        linkedSpanID: nil,
                        relatedRunID: emptyToNil(runID),
                        relatedJobID: emptyToNil(jobID),
                        relatedSourcePath: emptyToNil(sourcePath)
                    )
                )
            }
        }

        let spanSQL = """
        SELECT span_id, name, service, status, start_time, COALESCE(events, json_extract(attributes, '$.preview_text'), 'Trace anomaly')
        FROM spans
        WHERE project_id = ?
          AND (
            status = 'error'
            OR lower(COALESCE(events, '')) LIKE '%timeout%'
            OR lower(COALESCE(attributes, '')) LIKE '%timeout%'
          )
        ORDER BY start_time DESC
        LIMIT ?;
        """

        var spanStatement: OpaquePointer?
        if sqlite3_prepare_v2(db, spanSQL, -1, &spanStatement, nil) == SQLITE_OK, let spanStatement {
            defer { sqlite3_finalize(spanStatement) }
            bindText(projectIDText, to: 1, in: spanStatement)
            sqlite3_bind_int(spanStatement, 2, Int32(limit * 2))

            while sqlite3_step(spanStatement) == SQLITE_ROW {
                guard let idCString = sqlite3_column_text(spanStatement, 0),
                      let nameCString = sqlite3_column_text(spanStatement, 1),
                      let serviceCString = sqlite3_column_text(spanStatement, 2),
                      let statusCString = sqlite3_column_text(spanStatement, 3),
                      let dateCString = sqlite3_column_text(spanStatement, 4),
                      let occurredAt = iso8601.date(from: String(cString: dateCString)) else {
                    continue
                }

                let detailText = sqlite3_column_type(spanStatement, 5) == SQLITE_NULL
                    ? "Trace anomaly"
                    : String(cString: sqlite3_column_text(spanStatement, 5))
                let normalizedDetail = detailText.trimmingCharacters(in: .whitespacesAndNewlines)
                let spanID = UUID(uuidString: String(cString: idCString))
                let rawStatus = String(cString: statusCString)

                rows.append(
                    OpsAnomalyRow(
                        id: "span-\(String(cString: idCString))",
                        title: String(cString: nameCString),
                        sourceLabel: anomalySourceLabel(forService: String(cString: serviceCString)),
                        detailText: (normalizedDetail.isEmpty ? "Trace anomaly" : normalizedDetail).compactSingleLinePreview(limit: 180),
                        fullDetailText: normalizedDetail.isEmpty ? "Trace anomaly" : normalizedDetail,
                        occurredAt: occurredAt,
                        status: rawStatus == "error" ? .critical : .warning,
                        statusText: rawStatus,
                        sourceService: String(cString: serviceCString),
                        linkedSpanID: spanID
                    )
                )
            }
        }

        return Array(
            rows.sorted { lhs, rhs in
                if lhs.occurredAt != rhs.occurredAt {
                    return lhs.occurredAt > rhs.occurredAt
                }
                return lhs.id < rhs.id
            }
            .prefix(limit)
        )
    }

    private func loadRecentCronAnomalyRows(
        db: OpaquePointer,
        projectID: UUID,
        cronName: String,
        limit: Int
    ) -> [OpsAnomalyRow] {
        let sql = """
        SELECT
            COALESCE(external_id, run_id, job_id, cron_name || '-' || COALESCE(run_at, slot_time, created_at)),
            cron_name,
            COALESCE(status, 'unknown'),
            COALESCE(error, summary, 'Cron anomaly'),
            COALESCE(run_at, slot_time, created_at),
            job_id,
            run_id,
            source_path
        FROM cron_runs
        WHERE project_id = ?
          AND lower(cron_name) = ?
          AND lower(COALESCE(status, 'unknown')) NOT IN ('ok', 'success', 'completed', 'delivered')
        ORDER BY COALESCE(run_at, slot_time, created_at) DESC
        LIMIT ?;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return [] }
        defer { sqlite3_finalize(statement) }

        bindText(projectID.uuidString, to: 1, in: statement)
        bindText(cronName.lowercased(), to: 2, in: statement)
        sqlite3_bind_int(statement, 3, Int32(limit))

        var rows: [OpsAnomalyRow] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let idCString = sqlite3_column_text(statement, 0),
                  let nameCString = sqlite3_column_text(statement, 1),
                  let statusCString = sqlite3_column_text(statement, 2),
                  let detailCString = sqlite3_column_text(statement, 3),
                  let dateCString = sqlite3_column_text(statement, 4),
                  let occurredAt = iso8601.date(from: String(cString: dateCString)) else {
                continue
            }

            let rawStatus = String(cString: statusCString)
            let jobID = sqlite3_column_type(statement, 5) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(statement, 5))
            let runID = sqlite3_column_type(statement, 6) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(statement, 6))
            let sourcePath = sqlite3_column_type(statement, 7) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(statement, 7))
            let detailText = String(cString: detailCString)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedDetail = detailText.isEmpty ? "Cron anomaly" : detailText

            rows.append(
                OpsAnomalyRow(
                    id: "cron-\(String(cString: idCString))",
                    title: String(cString: nameCString),
                    sourceLabel: "Cron",
                    detailText: normalizedDetail.compactSingleLinePreview(limit: 180),
                    fullDetailText: normalizedDetail,
                    occurredAt: occurredAt,
                    status: cronAnomalyStatus(for: rawStatus),
                    statusText: formattedCronStatus(rawStatus),
                    sourceService: nil,
                    linkedSpanID: nil,
                    relatedRunID: emptyToNil(runID),
                    relatedJobID: emptyToNil(jobID),
                    relatedSourcePath: emptyToNil(sourcePath)
                )
            )
        }

        return rows
    }

    private func loadRecentToolAnomalyRows(
        db: OpaquePointer,
        projectID: UUID,
        toolIdentifier: String,
        limit: Int
    ) -> [OpsAnomalyRow] {
        let normalizedToolIdentifier = toolIdentifier.lowercased()
        let sql = """
        SELECT span_id, name, service, status, start_time, COALESCE(events, json_extract(attributes, '$.preview_text'), 'Tool anomaly')
        FROM spans
        WHERE project_id = ?
          AND service LIKE '%tool%'
          AND (
            lower(service) LIKE '%' || ? || '%'
            OR lower(name) LIKE '%' || ? || '%'
            OR lower(COALESCE(attributes, '')) LIKE '%' || ? || '%'
          )
          AND (
            status = 'error'
            OR lower(COALESCE(events, '')) LIKE '%timeout%'
            OR lower(COALESCE(attributes, '')) LIKE '%timeout%'
          )
        ORDER BY start_time DESC
        LIMIT ?;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return [] }
        defer { sqlite3_finalize(statement) }

        bindText(projectID.uuidString, to: 1, in: statement)
        bindText(normalizedToolIdentifier, to: 2, in: statement)
        bindText(normalizedToolIdentifier, to: 3, in: statement)
        bindText(normalizedToolIdentifier, to: 4, in: statement)
        sqlite3_bind_int(statement, 5, Int32(limit))

        var rows: [OpsAnomalyRow] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let idCString = sqlite3_column_text(statement, 0),
                  let nameCString = sqlite3_column_text(statement, 1),
                  let serviceCString = sqlite3_column_text(statement, 2),
                  let statusCString = sqlite3_column_text(statement, 3),
                  let dateCString = sqlite3_column_text(statement, 4),
                  let occurredAt = iso8601.date(from: String(cString: dateCString)) else {
                continue
            }

            let detailText = sqlite3_column_type(statement, 5) == SQLITE_NULL
                ? "Tool anomaly"
                : String(cString: sqlite3_column_text(statement, 5))
            let normalizedDetail = detailText.trimmingCharacters(in: .whitespacesAndNewlines)
            let spanID = UUID(uuidString: String(cString: idCString))
            let rawStatus = String(cString: statusCString)

            rows.append(
                OpsAnomalyRow(
                    id: "tool-\(String(cString: idCString))",
                    title: String(cString: nameCString),
                    sourceLabel: "Tool",
                    detailText: (normalizedDetail.isEmpty ? "Tool anomaly" : normalizedDetail).compactSingleLinePreview(limit: 180),
                    fullDetailText: normalizedDetail.isEmpty ? "Tool anomaly" : normalizedDetail,
                    occurredAt: occurredAt,
                    status: rawStatus == "error" ? .critical : .warning,
                    statusText: rawStatus,
                    sourceService: String(cString: serviceCString),
                    linkedSpanID: spanID
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

    private func countCronFailures(
        db: OpaquePointer,
        projectID: String,
        window: String
    ) -> Int {
        let sql = """
        SELECT COUNT(*)
        FROM cron_runs
        WHERE project_id = ?
          AND COALESCE(run_at, slot_time, created_at) >= datetime('now', ?)
          AND status NOT IN ('ok', 'success', 'completed', 'delivered');
        """

        return scalarCount(db: db, sql: sql, bindings: [projectID, window])
    }

    private func countSpanFailures(
        db: OpaquePointer,
        projectID: String,
        services: [String],
        window: String
    ) -> Int {
        guard !services.isEmpty else { return 0 }
        let placeholders = Array(repeating: "?", count: services.count).joined(separator: ", ")
        let sql = """
        SELECT COUNT(*)
        FROM spans
        WHERE project_id = ?
          AND start_time >= datetime('now', ?)
          AND service IN (\(placeholders))
          AND status = 'error';
        """

        return scalarCount(db: db, sql: sql, bindings: [projectID, window] + services)
    }

    private func countTimeouts(
        db: OpaquePointer,
        projectID: String,
        window: String
    ) -> Int {
        let cronSQL = """
        SELECT COUNT(*)
        FROM cron_runs
        WHERE project_id = ?
          AND COALESCE(run_at, slot_time, created_at) >= datetime('now', ?)
          AND lower(COALESCE(error, summary, '')) LIKE '%timeout%';
        """

        let spanSQL = """
        SELECT COUNT(*)
        FROM spans
        WHERE project_id = ?
          AND start_time >= datetime('now', ?)
          AND (
            lower(COALESCE(events, '')) LIKE '%timeout%'
            OR lower(COALESCE(attributes, '')) LIKE '%timeout%'
          );
        """

        return scalarCount(db: db, sql: cronSQL, bindings: [projectID, window])
            + scalarCount(db: db, sql: spanSQL, bindings: [projectID, window])
    }

    private func latestAnomalyDate(
        db: OpaquePointer,
        projectID: String
    ) -> Date? {
        var dates: [Date] = []

        let cronSQL = """
        SELECT MAX(COALESCE(run_at, slot_time, created_at))
        FROM cron_runs
        WHERE project_id = ?
          AND status NOT IN ('ok', 'success', 'completed', 'delivered');
        """
        if let text = scalarText(db: db, sql: cronSQL, bindings: [projectID]),
           let date = iso8601.date(from: text) {
            dates.append(date)
        }

        let spanSQL = """
        SELECT MAX(start_time)
        FROM spans
        WHERE project_id = ?
          AND (
            status = 'error'
            OR lower(COALESCE(events, '')) LIKE '%timeout%'
            OR lower(COALESCE(attributes, '')) LIKE '%timeout%'
          );
        """
        if let text = scalarText(db: db, sql: spanSQL, bindings: [projectID]),
           let date = iso8601.date(from: text) {
            dates.append(date)
        }

        return dates.max()
    }

    private func anomalySourceLabel(forService service: String) -> String {
        if service.contains("tool") {
            return "Tool"
        }
        if service.contains("external") {
            return "OpenClaw"
        }
        return "Runtime"
    }

    private func cronAnomalyStatus(for status: String) -> OpsHealthStatus {
        switch normalizedCronStatus(status) {
        case "timeout", "error", "failed":
            return .critical
        default:
            return .warning
        }
    }

    private func scalarCount(
        db: OpaquePointer,
        sql: String,
        bindings: [String]
    ) -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return 0 }
        defer { sqlite3_finalize(statement) }

        for (index, value) in bindings.enumerated() {
            bindText(value, to: Int32(index + 1), in: statement)
        }

        guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int(statement, 0))
    }

    private func scalarText(
        db: OpaquePointer,
        sql: String,
        bindings: [String]
    ) -> String? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return nil }
        defer { sqlite3_finalize(statement) }

        for (index, value) in bindings.enumerated() {
            bindText(value, to: Int32(index + 1), in: statement)
        }

        guard sqlite3_step(statement) == SQLITE_ROW,
              sqlite3_column_type(statement, 0) != SQLITE_NULL,
              let text = sqlite3_column_text(statement, 0) else {
            return nil
        }

        return String(cString: text)
    }

    private func loadCronArtifacts(from fileURL: URL) -> [ExternalCronRunArtifact] {
        guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }

        var artifactsByID: [String: ExternalCronRunArtifact] = [:]
        contents.enumerateLines { [self] line, _ in
            guard let object = self.jsonObject(from: line),
                  let runAt = self.millisecondsDate(from: object["runAtMs"]) ?? self.millisecondsDate(from: object["ts"]) else {
                return
            }

            let jobID = self.stringValue(object["jobId"]) ?? fileURL.deletingPathExtension().lastPathComponent
            let runID = self.stringValue(object["sessionId"]).map { self.canonicalExternalSpanID(for: $0) }
            let externalID = runID ?? "\(jobID)-\(Int(runAt.timeIntervalSince1970 * 1000))"
            let status = self.normalizedCronStatus(self.stringValue(object["status"]) ?? "unknown")

            artifactsByID[externalID] = ExternalCronRunArtifact(
                externalID: externalID,
                date: self.dayFormatter.string(from: runAt),
                cronName: self.cronDisplayName(from: object, fileURL: fileURL),
                jobID: jobID,
                runID: runID,
                runAt: runAt,
                status: status,
                errorText: self.emptyToNil(self.stringValue(object["error"])),
                durationMs: self.doubleValue(from: object["durationMs"]),
                deliveryStatus: self.emptyToNil(self.stringValue(object["deliveryStatus"])),
                summaryText: self.emptyToNil(self.stringValue(object["summary"])),
                sourcePath: fileURL.path
            )
        }

        return artifactsByID.values.sorted { $0.runAt > $1.runAt }
    }

    private func loadExternalSessionArtifact(from fileURL: URL) -> ExternalSessionTraceArtifact? {
        guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else { return nil }

        let agentName = fileURL.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent
        let fallbackSessionID = fileURL.deletingPathExtension().lastPathComponent
        var sessionID = fallbackSessionID
        var startDate: Date?
        var lastEventDate: Date?
        var provider: String?
        var model: String?
        var cwd: String?
        var userMessages = 0
        var assistantMessages = 0
        var toolCalls = 0
        var toolErrors = 0
        var lastAssistantText: String?
        var lastToolText: String?
        var childSpans: [ExternalSessionChildSpanArtifact] = []
        var messageIndex = 0

        contents.enumerateLines { [self] line, _ in
            guard let object = self.jsonObject(from: line) else { return }

            if object["type"] as? String == "session" {
                sessionID = self.stringValue(object["id"]) ?? fallbackSessionID
                startDate = startDate ?? self.iso8601.date(from: self.stringValue(object["timestamp"]) ?? "")
                cwd = self.emptyToNil(self.stringValue(object["cwd"]))
            }

            if object["type"] as? String == "model_change" {
                provider = self.emptyToNil(self.stringValue(object["provider"])) ?? provider
                model = self.emptyToNil(self.stringValue(object["modelId"])) ?? model
            }

            if object["type"] as? String == "custom",
               object["customType"] as? String == "model-snapshot",
               let data = object["data"] as? [String: Any] {
                provider = self.emptyToNil(self.stringValue(data["provider"])) ?? provider
                model = self.emptyToNil(self.stringValue(data["modelId"])) ?? model
            }

            if let eventDate = self.sessionEventDate(from: object) {
                startDate = min(startDate ?? eventDate, eventDate)
                lastEventDate = max(lastEventDate ?? eventDate, eventDate)
            }

            guard object["type"] as? String == "message",
                  let message = object["message"] as? [String: Any],
                  let role = message["role"] as? String else {
                return
            }

            messageIndex += 1
            let content = message["content"] as? [[String: Any]] ?? []
            let messageDate = self.sessionEventDate(from: object) ?? startDate ?? Date()
            let messageSpanID = "\(sessionID)-message-\(messageIndex)"
            switch role {
            case "user":
                userMessages += 1
                let preview = self.previewText(for: content) ?? "User instruction"
                childSpans.append(
                    ExternalSessionChildSpanArtifact(
                        spanID: messageSpanID,
                        parentSpanID: sessionID,
                        name: "User Prompt",
                        service: "openclaw.external-user-message",
                        status: "ok",
                        startedAt: messageDate,
                        completedAt: messageDate,
                        durationMs: 0,
                        attributes: [
                            "agent_name": agentName,
                            "role": "user",
                            "preview_text": preview
                        ],
                        eventsText: nil
                    )
                )
            case "assistant":
                assistantMessages += 1
                let assistantText = content.compactMap { item -> String? in
                    guard item["type"] as? String == "text" else { return nil }
                    return self.emptyToNil(self.stringValue(item["text"]))
                }
                .joined(separator: "\n\n")
                if let text = self.emptyToNil(assistantText) {
                    lastAssistantText = text
                }
                let toolCallItems = content.filter { $0["type"] as? String == "toolCall" }
                toolCalls += toolCallItems.count
                let preview = self.emptyToNil(assistantText)?.compactSingleLinePreview(limit: 180)
                    ?? (toolCallItems.isEmpty ? "Assistant turn" : "Requested \(toolCallItems.count) tool call(s)")

                childSpans.append(
                    ExternalSessionChildSpanArtifact(
                        spanID: messageSpanID,
                        parentSpanID: sessionID,
                        name: "Assistant Turn",
                        service: "openclaw.external-assistant-message",
                        status: "ok",
                        startedAt: messageDate,
                        completedAt: messageDate,
                        durationMs: 0,
                        attributes: [
                            "agent_name": agentName,
                            "role": "assistant",
                            "preview_text": preview,
                            "tool_call_count": "\(toolCallItems.count)"
                        ],
                        eventsText: self.emptyToNil(assistantText)
                    )
                )

                for (toolIndex, item) in toolCallItems.enumerated() {
                    let toolName = self.emptyToNil(self.stringValue(item["name"])) ?? "tool"
                    let argumentsPreview = self.valuePreview(item["arguments"], maxLength: 220) ?? "No arguments"
                    childSpans.append(
                        ExternalSessionChildSpanArtifact(
                            spanID: "\(messageSpanID)-tool-\(toolIndex + 1)",
                            parentSpanID: messageSpanID,
                            name: "Tool Call",
                            service: "openclaw.external-tool-call",
                            status: "ok",
                            startedAt: messageDate,
                            completedAt: messageDate,
                            durationMs: 0,
                            attributes: [
                                "agent_name": agentName,
                                "tool_name": toolName,
                                "preview_text": "\(toolName): \(argumentsPreview)"
                            ],
                            eventsText: argumentsPreview
                        )
                    )
                }
            case "toolResult":
                if let isError = message["isError"] as? Bool, isError {
                    toolErrors += 1
                }
                let toolText = content.compactMap { item -> String? in
                    guard item["type"] as? String == "text" else { return nil }
                    return self.emptyToNil(self.stringValue(item["text"]))
                }
                .joined(separator: "\n")
                if let text = self.emptyToNil(toolText) {
                    lastToolText = text
                }
                let toolName = self.emptyToNil(self.stringValue(message["toolName"])) ?? "tool"
                let isError = (message["isError"] as? Bool) == true
                let preview = self.emptyToNil(toolText)?.compactSingleLinePreview(limit: 180)
                    ?? (isError ? "Tool failed" : "Tool completed")
                let detailsPreview = self.valuePreview(message["details"], maxLength: 280)

                childSpans.append(
                    ExternalSessionChildSpanArtifact(
                        spanID: messageSpanID,
                        parentSpanID: sessionID,
                        name: "Tool Result",
                        service: "openclaw.external-tool-result",
                        status: isError ? "error" : "ok",
                        startedAt: messageDate,
                        completedAt: messageDate,
                        durationMs: 0,
                        attributes: [
                            "agent_name": agentName,
                            "tool_name": toolName,
                            "preview_text": "\(toolName): \(preview)"
                        ],
                        eventsText: [self.emptyToNil(toolText), detailsPreview]
                            .compactMap { $0 }
                            .joined(separator: "\n\n")
                    )
                )
            default:
                break
            }
        }

        guard let startedAt = startDate else { return nil }

        let rootSpanID = canonicalExternalSpanID(for: sessionID)
        let normalizedChildSpans = childSpans.map { child in
            ExternalSessionChildSpanArtifact(
                spanID: canonicalExternalSpanID(for: child.spanID),
                parentSpanID: child.parentSpanID.map { canonicalExternalSpanID(for: $0) },
                name: child.name,
                service: child.service,
                status: child.status,
                startedAt: child.startedAt,
                completedAt: child.completedAt,
                durationMs: child.durationMs,
                attributes: child.attributes,
                eventsText: child.eventsText
            )
        }

        let outputText = limitedText(lastAssistantText ?? lastToolText ?? "No assistant summary captured", maxLength: 8000)
        let executionStatus: ExecutionStatus = toolErrors > 0 ? .failed : (assistantMessages > 0 ? .completed : .waiting)
        let outputType: ExecutionOutputType = toolErrors > 0 ? .errorSummary : (lastAssistantText == nil ? .runtimeLog : .agentFinalResponse)

        var attributes: [String: String] = [
            "agent_name": agentName,
            "execution_status": executionStatus.rawValue,
            "output_type": outputType.rawValue,
            "preview_text": outputText.compactSingleLinePreview(limit: 160),
            "output_text": outputText,
            "session_path": fileURL.path,
            "source_label": "OpenClaw"
        ]

        if let provider {
            attributes["provider"] = provider
        }
        if let model {
            attributes["model"] = model
        }
        if let cwd {
            attributes["cwd"] = cwd
        }

        let eventsTextLines: [String] = [
            "User messages: \(userMessages)",
            "Assistant messages: \(assistantMessages)",
            "Tool calls: \(toolCalls)",
            "Tool errors: \(toolErrors)",
            model.map { "Model: \($0)" } ?? "",
            provider.map { "Provider: \($0)" } ?? ""
        ]
        .filter { !$0.isEmpty }
        let eventsText = eventsTextLines.joined(separator: "\n")

        return ExternalSessionTraceArtifact(
            spanID: rootSpanID,
            traceID: rootSpanID.replacingOccurrences(of: "-", with: ""),
            agentName: agentName,
            status: executionStatus == .failed ? "error" : (executionStatus == .completed ? "ok" : "warning"),
            executionStatus: executionStatus,
            outputType: outputType,
            startedAt: startedAt,
            completedAt: lastEventDate,
            durationMs: lastEventDate.map { $0.timeIntervalSince(startedAt) * 1000.0 },
            previewText: outputText.compactSingleLinePreview(limit: 160),
            outputText: outputText,
            attributes: attributes,
            eventsText: emptyToNil(eventsText),
            childSpans: normalizedChildSpans.sorted { lhs, rhs in
                if lhs.startedAt == rhs.startedAt {
                    return lhs.spanID < rhs.spanID
                }
                return lhs.startedAt < rhs.startedAt
            }
        )
    }

    private func cronDisplayName(from object: [String: Any], fileURL: URL) -> String {
        if let sessionKey = stringValue(object["sessionKey"]) {
            let parts = sessionKey.split(separator: ":").map(String.init)
            if let agentIndex = parts.firstIndex(of: "agent"), agentIndex + 1 < parts.count {
                let agentName = parts[agentIndex + 1]
                return agentName == "main" ? "Main Cron" : "Cron / \(agentName)"
            }
        }

        let fallback = fileURL.deletingPathExtension().lastPathComponent
        return "Cron / \(String(fallback.prefix(8)))"
    }

    private func normalizedCronStatus(_ status: String) -> String {
        let normalized = status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? "unknown" : normalized
    }

    private func canonicalExternalSpanID(for rawID: String) -> String {
        let trimmed = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return stableUUIDString(for: "openclaw.external-span.empty")
        }

        if let uuid = UUID(uuidString: trimmed) {
            return uuid.uuidString
        }

        return stableUUIDString(for: "openclaw.external-span.\(trimmed)")
    }

    private func stableUUIDString(for seed: String) -> String {
        let digest = SHA256.hash(data: Data(seed.utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80

        let uuid = UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
        return uuid.uuidString
    }

    private func isSuccessfulCronStatus(_ status: String) -> Bool {
        ["ok", "success", "completed", "delivered"].contains(normalizedCronStatus(status))
    }

    private func formattedCronStatus(_ status: String) -> String {
        switch normalizedCronStatus(status) {
        case "ok", "success", "completed":
            return "OK"
        case "error", "failed", "timeout":
            return "Error"
        default:
            return status.capitalized
        }
    }

    private func executionStatus(forSpanStatus status: String) -> ExecutionStatus {
        switch status.lowercased() {
        case "ok":
            return .completed
        case "error":
            return .failed
        case "warning":
            return .waiting
        default:
            return .idle
        }
    }

    private func jsonObject(from line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }

    private func stringValue(_ value: Any?) -> String? {
        switch value {
        case let value as String:
            return value
        case let value as NSNumber:
            return value.stringValue
        default:
            return nil
        }
    }

    private func doubleValue(from value: Any?) -> Double? {
        switch value {
        case let value as NSNumber:
            return value.doubleValue
        case let value as String:
            return Double(value)
        default:
            return nil
        }
    }

    private func millisecondsDate(from value: Any?) -> Date? {
        guard let milliseconds = doubleValue(from: value) else { return nil }
        return Date(timeIntervalSince1970: milliseconds / 1000.0)
    }

    private func sessionEventDate(from object: [String: Any]) -> Date? {
        if let timestamp = stringValue(object["timestamp"]),
           let date = iso8601.date(from: timestamp) {
            return date
        }

        if let message = object["message"] as? [String: Any],
           let timestamp = message["timestamp"] {
            return millisecondsDate(from: timestamp)
        }

        return nil
    }

    private func previewText(for content: [[String: Any]]) -> String? {
        let text = content.compactMap { item -> String? in
            guard item["type"] as? String == "text" else { return nil }
            return emptyToNil(stringValue(item["text"]))
        }
        .joined(separator: "\n\n")

        return emptyToNil(text)?.compactSingleLinePreview(limit: 180)
    }

    private func valuePreview(_ value: Any?, maxLength: Int) -> String? {
        switch value {
        case nil:
            return nil
        case let text as String:
            return limitedText(text.compactSingleLinePreview(limit: maxLength), maxLength: maxLength)
        case let number as NSNumber:
            return number.stringValue
        default:
            guard JSONSerialization.isValidJSONObject(value as Any),
                  let data = try? JSONSerialization.data(withJSONObject: value as Any, options: [.sortedKeys]),
                  let text = String(data: data, encoding: .utf8) else {
                return nil
            }
            return limitedText(text.compactSingleLinePreview(limit: maxLength), maxLength: maxLength)
        }
    }

    private func limitedText(_ text: String, maxLength: Int) -> String {
        if text.count <= maxLength { return text }
        return String(text.prefix(maxLength)) + "..."
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
