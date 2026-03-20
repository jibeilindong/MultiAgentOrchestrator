import XCTest
import SQLite3
@testable import Multi_Agent_Flow

final class OpsAnalyticsQueryTests: XCTestCase {
    private let service = OpsAnalyticsService()
    private var projectIDsToClean: [UUID] = []
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

    private func makeProjectID() -> UUID {
        let projectID = UUID()
        projectIDsToClean.append(projectID)
        return projectID
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
        VALUES (?, ?, ?, NULL, ?, ?, ?, ?, ?, ?, ?, ?);
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
                .text(spanID.uuidString.replacingOccurrences(of: "-", with: "")),
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

    private func message(from db: OpaquePointer?) -> String {
        guard let db else { return "Unknown SQLite error" }
        return String(cString: sqlite3_errmsg(db))
    }
}

private enum SQLiteBinding {
    case text(String?)
    case double(Double?)
}

private enum DatabaseError: Error {
    case open(String)
    case prepare(String)
    case step(String)
}

private let sqliteTransientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
