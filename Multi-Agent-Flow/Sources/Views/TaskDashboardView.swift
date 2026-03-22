//
//  Untitled.swift
//  Multi-Agent-Flow
//
//  Created by 陈荣泽 on 2026/3/18.
//

import SwiftUI
import Charts

enum OpsCronAnomalyRunMatcher {
    static func matchingRun(
        for anomaly: OpsAnomalyRow,
        in runs: [OpsCronRunRow]
    ) -> OpsCronRunRow? {
        if let relatedRunID = normalizedText(anomaly.relatedRunID),
           let exactRun = runs.first(where: { normalizedText($0.runID) == relatedRunID }) {
            return exactRun
        }

        if let relatedJobID = normalizedText(anomaly.relatedJobID),
           let exactJob = runs.first(where: { normalizedText($0.jobID) == relatedJobID }) {
            return exactJob
        }

        if let relatedSourcePath = normalizedPath(anomaly.relatedSourcePath),
           let exactSource = runs.first(where: { normalizedPath($0.sourcePath) == relatedSourcePath }) {
            return exactSource
        }

        if let exactTime = runs.first(where: { abs($0.runAt.timeIntervalSince(anomaly.occurredAt)) < 1 }) {
            return exactTime
        }

        if let minuteMatch = runs.first(where: {
            Calendar.autoupdatingCurrent.isDate($0.runAt, equalTo: anomaly.occurredAt, toGranularity: .minute)
        }) {
            return minuteMatch
        }

        let detailText = normalizedText(anomaly.detailText)
        let fullDetailText = normalizedText(anomaly.fullDetailText)
        return runs.first { run in
            let summary = normalizedText(run.summaryText)
            return summary == detailText || summary == fullDetailText
        }
    }

    private static func normalizedText(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed.lowercased()
    }

    private static func normalizedPath(_ value: String?) -> String? {
        guard let text = normalizedText(value) else { return nil }
        return URL(fileURLWithPath: text).standardizedFileURL.path.lowercased()
    }
}

enum OpsAnomalyClusterBuilder {
    enum SourceFilter {
        case all
        case runtime
        case tool
        case cron
        case openClaw

        fileprivate init(_ filter: OpsAnomalySourceFilter) {
            switch filter {
            case .all:
                self = .all
            case .runtime:
                self = .runtime
            case .tool:
                self = .tool
            case .cron:
                self = .cron
            case .openClaw:
                self = .openClaw
            }
        }

        nonisolated fileprivate func matches(_ row: OpsAnomalyRow) -> Bool {
            switch self {
            case .all:
                return true
            case .runtime:
                return row.sourceLabel == "Runtime"
            case .tool:
                return row.sourceLabel == "Tool"
            case .cron:
                return row.sourceLabel == "Cron"
            case .openClaw:
                return row.sourceLabel == "OpenClaw"
            }
        }
    }

    enum SeverityFilter {
        case all
        case critical
        case warning

        fileprivate init(_ filter: OpsAnomalySeverityFilter) {
            switch filter {
            case .all:
                self = .all
            case .critical:
                self = .critical
            case .warning:
                self = .warning
            }
        }

        nonisolated fileprivate func matches(_ row: OpsAnomalyRow) -> Bool {
            switch self {
            case .all:
                return true
            case .critical:
                return row.status == .critical
            case .warning:
                return row.status == .warning
            }
        }
    }

    nonisolated static func filteredRows(
        from rows: [OpsAnomalyRow],
        sourceFilter: SourceFilter = .all,
        severityFilter: SeverityFilter = .all,
        searchText: String = "",
        windowStart: Date? = nil
    ) -> [OpsAnomalyRow] {
        let normalizedSearch = searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        return rows.filter { row in
            if let windowStart, row.occurredAt < windowStart {
                return false
            }
            guard sourceFilter.matches(row) else { return false }
            guard severityFilter.matches(row) else { return false }
            guard !normalizedSearch.isEmpty else { return true }

            let haystack = [
                row.title,
                row.detailText,
                row.fullDetailText,
                row.sourceLabel,
                row.sourceService ?? "",
                row.statusText
            ]
            .joined(separator: " ")
            .lowercased()

            return haystack.contains(normalizedSearch)
        }
    }

    nonisolated static func clusters(
        from rows: [OpsAnomalyRow],
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> [OpsAnomalyCluster] {
        let recent24HourStart = calendar.date(byAdding: .day, value: -1, to: now) ?? .distantPast
        let groupedRows = Dictionary(grouping: rows, by: clusterKey(for:))
        let clusters: [OpsAnomalyCluster] = groupedRows.map { (key: String, rows: [OpsAnomalyRow]) in
            let latest = rows.max(by: { $0.occurredAt < $1.occurredAt }) ?? rows[0]
            let firstOccurredAt = rows.map(\.occurredAt).min() ?? latest.occurredAt
            let lastOccurredAt = rows.map(\.occurredAt).max() ?? latest.occurredAt
            let criticalCount = rows.filter { $0.status == .critical }.count
            let linkedTraceCount = rows.filter { $0.linkedSpanID != nil }.count
            let recent24HourCount = rows.filter { $0.occurredAt >= recent24HourStart }.count

            return OpsAnomalyCluster(
                id: key,
                title: latest.title,
                sourceLabel: latest.sourceLabel,
                sourceService: latest.sourceService,
                sampleDetail: latest.detailText,
                latestOccurredAt: lastOccurredAt,
                firstOccurredAt: firstOccurredAt,
                status: criticalCount > 0 ? .critical : .warning,
                occurrenceCount: rows.count,
                recent24HourCount: recent24HourCount,
                linkedTraceCount: linkedTraceCount,
                latestAnomaly: latest
            )
        }

        return clusters.sorted { lhs, rhs in
            if lhs.occurrenceCount != rhs.occurrenceCount {
                return lhs.occurrenceCount > rhs.occurrenceCount
            }
            if lhs.latestOccurredAt != rhs.latestOccurredAt {
                return lhs.latestOccurredAt > rhs.latestOccurredAt
            }
            return lhs.id < rhs.id
        }
    }

    nonisolated static func clusteredRows(
        from rows: [OpsAnomalyRow],
        sourceFilter: SourceFilter = .all,
        severityFilter: SeverityFilter = .all,
        searchText: String = "",
        windowStart: Date? = nil,
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> [OpsAnomalyCluster] {
        clusters(
            from: filteredRows(
                from: rows,
                sourceFilter: sourceFilter,
                severityFilter: severityFilter,
                searchText: searchText,
                windowStart: windowStart
            ),
            now: now,
            calendar: calendar
        )
    }

    nonisolated private static func clusterKey(for row: OpsAnomalyRow) -> String {
        [
            row.sourceLabel.lowercased(),
            (row.sourceService ?? row.sourceLabel).lowercased(),
            row.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        ]
        .joined(separator: "::")
    }
}

struct OpsProtocolAgentProfile: Identifiable {
    let agentName: String
    let totalTraceCount: Int
    let repairedTraceCount: Int
    let safeDegradeCount: Int
    let hardInterruptCount: Int
    let latestActivityAt: Date
    let dominantRepairLabel: String?
    let recommendedFilter: OpsProtocolTraceFilter

    var id: String { agentName.lowercased() }
    nonisolated var riskScore: Int { (hardInterruptCount * 4) + (safeDegradeCount * 2) + repairedTraceCount }
}

struct OpsProtocolRepairDistributionItem: Identifiable {
    let filter: OpsProtocolTraceFilter
    let title: String
    let count: Int

    var id: OpsProtocolTraceFilter { filter }
}

enum OpsProtocolRepairDistributionBuilder {
    nonisolated static func items(from traceRows: [OpsTraceSummaryRow]) -> [OpsProtocolRepairDistributionItem] {
        let runtimeRows = traceRows.filter { $0.sourceLabel == "Runtime" }
        return [
            OpsProtocolRepairDistributionItem(
                filter: .missingRoute,
                title: "Missing Route",
                count: runtimeRows.filter { $0.protocolRepairTypes.contains("missing_route_auto_selected") }.count
            ),
            OpsProtocolRepairDistributionItem(
                filter: .invalidTarget,
                title: "Invalid Target",
                count: runtimeRows.filter { $0.protocolRepairTypes.contains("invalid_targets_auto_selected") }.count
            ),
            OpsProtocolRepairDistributionItem(
                filter: .approvalBlocked,
                title: "Approval Blocked",
                count: runtimeRows.filter { $0.protocolRepairTypes.contains("route_missing_approval_blocked") }.count
            )
        ]
        .filter { $0.count > 0 }
        .sorted { lhs, rhs in
            if lhs.count != rhs.count {
                return lhs.count > rhs.count
            }
            return lhs.title < rhs.title
        }
    }
}

enum OpsProtocolAgentInsightBuilder {
    nonisolated static func profiles(
        from traceRows: [OpsTraceSummaryRow],
        limit: Int = 6
    ) -> [OpsProtocolAgentProfile] {
        let runtimeRows = traceRows.filter { $0.sourceLabel == "Runtime" }
        let grouped = Dictionary(grouping: runtimeRows, by: \.agentName)

        return grouped.compactMap { agentName, rows in
            guard let latestActivityAt = rows.map(\.startedAt).max() else { return nil }

            let repairedTraceCount = rows.filter { $0.protocolRepairCount > 0 }.count
            let safeDegradeCount = rows.filter(\.protocolSafeDegradeApplied).count
            let hardInterruptCount = rows.filter {
                $0.status == .failed && $0.protocolRepairCount > 0 && !$0.protocolSafeDegradeApplied
            }.count
            guard repairedTraceCount > 0 || safeDegradeCount > 0 || hardInterruptCount > 0 else {
                return nil
            }

            let repairTypeCounts = rows
                .flatMap(\.protocolRepairTypes)
                .reduce(into: [String: Int]()) { counts, kind in
                    counts[kind, default: 0] += 1
                }
            let dominantRepairType = repairTypeCounts.max { lhs, rhs in
                if lhs.value != rhs.value {
                    return lhs.value < rhs.value
                }
                return repairPriority(for: lhs.key) < repairPriority(for: rhs.key)
            }?.key

            return OpsProtocolAgentProfile(
                agentName: agentName,
                totalTraceCount: rows.count,
                repairedTraceCount: repairedTraceCount,
                safeDegradeCount: safeDegradeCount,
                hardInterruptCount: hardInterruptCount,
                latestActivityAt: latestActivityAt,
                dominantRepairLabel: dominantRepairType.map(repairDisplayLabel(for:)),
                recommendedFilter: recommendedFilter(
                    hardInterruptCount: hardInterruptCount,
                    repairTypeCounts: repairTypeCounts,
                    safeDegradeCount: safeDegradeCount
                )
            )
        }
        .sorted { lhs, rhs in
            if lhs.riskScore != rhs.riskScore {
                return lhs.riskScore > rhs.riskScore
            }
            if lhs.latestActivityAt != rhs.latestActivityAt {
                return lhs.latestActivityAt > rhs.latestActivityAt
            }
            return lhs.agentName.localizedCaseInsensitiveCompare(rhs.agentName) == .orderedAscending
        }
        .prefix(limit)
        .map { $0 }
    }

    nonisolated private static func recommendedFilter(
        hardInterruptCount: Int,
        repairTypeCounts: [String: Int],
        safeDegradeCount: Int
    ) -> OpsProtocolTraceFilter {
        if hardInterruptCount > 0 {
            return .hardInterrupt
        }
        if (repairTypeCounts["route_missing_approval_blocked"] ?? 0) > 0 {
            return .approvalBlocked
        }
        if (repairTypeCounts["invalid_targets_auto_selected"] ?? 0) > 0 {
            return .invalidTarget
        }
        if (repairTypeCounts["missing_route_auto_selected"] ?? 0) > 0 {
            return .missingRoute
        }
        if safeDegradeCount > 0 {
            return .safeDegrade
        }
        return .repaired
    }

    nonisolated private static func repairDisplayLabel(for repairType: String) -> String {
        switch repairType {
        case "missing_route_auto_selected":
            return "Missing Route"
        case "invalid_targets_auto_selected":
            return "Invalid Target"
        case "route_missing_approval_blocked":
            return "Approval Blocked"
        default:
            return repairType
                .replacingOccurrences(of: "_", with: " ")
                .localizedCapitalized
        }
    }

    nonisolated private static func repairPriority(for repairType: String) -> Int {
        switch repairType {
        case "route_missing_approval_blocked":
            return 3
        case "invalid_targets_auto_selected":
            return 2
        case "missing_route_auto_selected":
            return 1
        default:
            return 0
        }
    }
}

enum OpsHistoryInsightBuilder {
    nonisolated static func contextCards(
        metric: OpsHistoryMetric,
        focusTitle: String,
        totalAgents: Int,
        traceRows: [OpsTraceSummaryRow],
        anomalyRows: [OpsAnomalyRow],
        agentRows: [OpsAgentHealthRow],
        cronRuns: [OpsCronRunRow]
    ) -> [OpsContextCard] {
        switch metric {
        case .workflowReliability:
            let failed = traceRows.filter { $0.status == .failed }.count
            let openClaw = traceRows.filter { $0.sourceLabel == "OpenClaw" }.count
            let runtimeAnomalies = anomalyRows.filter {
                $0.sourceLabel == "Runtime" || $0.sourceLabel == "Tool"
            }.count
            return [
                OpsContextCard(
                    id: "wf-failed",
                    title: "Failed Traces",
                    value: "\(failed)",
                    detail: "\(focusTitle) traces in current scope",
                    tone: failed == 0 ? .green : .red
                ),
                OpsContextCard(
                    id: "wf-openclaw",
                    title: "OpenClaw Share",
                    value: "\(openClaw)",
                    detail: "External traces matching this scope",
                    tone: .teal
                ),
                OpsContextCard(
                    id: "wf-runtime",
                    title: "Runtime Signals",
                    value: "\(runtimeAnomalies)",
                    detail: "Runtime and tool anomalies in scope",
                    tone: runtimeAnomalies == 0 ? .green : .orange
                )
            ]
        case .agentEngagement:
            return [
                OpsContextCard(
                    id: "eng-active",
                    title: "Scoped Agents",
                    value: "\(agentRows.count)",
                    detail: "Agents matching the current focus",
                    tone: agentRows.isEmpty ? .secondary : .blue
                ),
                OpsContextCard(
                    id: "eng-total",
                    title: "Total Agents",
                    value: "\(totalAgents)",
                    detail: "Agents defined for this project",
                    tone: .secondary
                ),
                OpsContextCard(
                    id: "eng-completed",
                    title: "Completed Runs",
                    value: "\(agentRows.reduce(0) { $0 + $1.completedCount })",
                    detail: "Completed runs in scope",
                    tone: .green
                )
            ]
        case .memoryDiscipline:
            let scopedTracked = agentRows.filter(\.hasTrackedMemory).count
            let untracked = max(agentRows.count - scopedTracked, 0)
            let coverageRate = agentRows.isEmpty
                ? "-"
                : "\(Int((Double(scopedTracked) / Double(agentRows.count) * 100).rounded()))%"
            return [
                OpsContextCard(
                    id: "mem-tracked",
                    title: "Tracked Memory",
                    value: "\(scopedTracked)",
                    detail: "Agents in scope with backup coverage",
                    tone: scopedTracked == 0 ? .secondary : .green
                ),
                OpsContextCard(
                    id: "mem-gap",
                    title: "Coverage Gaps",
                    value: "\(untracked)",
                    detail: "Agents in scope missing tracked memory",
                    tone: untracked == 0 ? .green : .orange
                ),
                OpsContextCard(
                    id: "mem-total",
                    title: "Coverage Rate",
                    value: coverageRate,
                    detail: "Current memory discipline posture",
                    tone: untracked == 0 ? .green : .blue
                )
            ]
        case .errorBudget:
            let critical = anomalyRows.filter { $0.status == .critical }.count
            let timeouts = anomalyRows.filter {
                $0.detailText.localizedCaseInsensitiveContains("timeout")
                    || $0.fullDetailText.localizedCaseInsensitiveContains("timeout")
            }.count
            let failedTraces = traceRows.filter { $0.status == .failed }.count
            return [
                OpsContextCard(
                    id: "err-critical",
                    title: "Critical Alerts",
                    value: "\(critical)",
                    detail: "Critical anomalies currently retained",
                    tone: critical == 0 ? .green : .red
                ),
                OpsContextCard(
                    id: "err-timeout",
                    title: "Timeout Signals",
                    value: "\(timeouts)",
                    detail: "Timeout-tagged anomalies in scope",
                    tone: timeouts == 0 ? .green : .orange
                ),
                OpsContextCard(
                    id: "err-failed",
                    title: "Failed Executions",
                    value: "\(failedTraces)",
                    detail: "Recent failed traces in scope",
                    tone: failedTraces == 0 ? .green : .red
                )
            ]
        case .cronReliability:
            let failedRuns = cronRuns.filter { $0.statusText != "OK" }.count
            let successRate = cronRuns.isEmpty
                ? nil
                : Double(cronRuns.filter { $0.statusText == "OK" }.count) / Double(cronRuns.count) * 100
            return [
                OpsContextCard(
                    id: "cron-rate",
                    title: "Success Rate",
                    value: successRate.map { "\(Int($0.rounded()))%" } ?? "-",
                    detail: "Scoped cron reliability from retained runs",
                    tone: (successRate ?? 0) >= 90 ? .green : .orange
                ),
                OpsContextCard(
                    id: "cron-failed",
                    title: "Failed Runs",
                    value: "\(failedRuns)",
                    detail: "Failed or timed-out cron runs in scope",
                    tone: failedRuns == 0 ? .green : .red
                ),
                OpsContextCard(
                    id: "cron-latest",
                    title: "Recent Samples",
                    value: "\(cronRuns.count)",
                    detail: "Most recent ingested cron runs in scope",
                    tone: .blue
                )
            ]
        case .protocolConformance:
            let runtimeTraceRows = runtimeProtocolTraceRows(traceRows)
            let repairedRuns = runtimeTraceRows.filter { $0.protocolRepairCount > 0 }.count
            let conformingRuns = runtimeTraceRows.count - repairedRuns
            let safeDegradeRuns = runtimeTraceRows.filter(\.protocolSafeDegradeApplied).count
            return [
                OpsContextCard(
                    id: "protocol-conforming",
                    title: "Conforming",
                    value: "\(max(conformingRuns, 0))",
                    detail: "Recent traces without runtime repair",
                    tone: repairedRuns == 0 ? .green : .blue
                ),
                OpsContextCard(
                    id: "protocol-repaired",
                    title: "Repaired",
                    value: "\(repairedRuns)",
                    detail: "Recent traces that needed protocol repair",
                    tone: repairedRuns == 0 ? .green : .orange
                ),
                OpsContextCard(
                    id: "protocol-safe",
                    title: "Safe Degrade",
                    value: "\(safeDegradeRuns)",
                    detail: "Recent traces completed through safe degrade",
                    tone: safeDegradeRuns == 0 ? .secondary : .teal
                )
            ]
        case .protocolAutoRepair:
            let repairedRows = runtimeProtocolTraceRows(traceRows).filter { $0.protocolRepairCount > 0 }
            let successfulRepairs = repairedRows.filter { $0.status == .completed }.count
            let invalidTargetRepairs = repairedRows.filter {
                $0.protocolRepairTypes.contains("invalid_targets_auto_selected")
            }.count
            return [
                OpsContextCard(
                    id: "auto-repair-total",
                    title: "Repaired Traces",
                    value: "\(repairedRows.count)",
                    detail: "Recent traces that needed any repair",
                    tone: repairedRows.isEmpty ? .secondary : .orange
                ),
                OpsContextCard(
                    id: "auto-repair-success",
                    title: "Recovered",
                    value: "\(successfulRepairs)",
                    detail: "Repaired traces that still completed",
                    tone: successfulRepairs == repairedRows.count && !repairedRows.isEmpty ? .green : .teal
                ),
                OpsContextCard(
                    id: "auto-repair-invalid",
                    title: "Invalid Targets",
                    value: "\(invalidTargetRepairs)",
                    detail: "Repairs caused by invalid routing targets",
                    tone: invalidTargetRepairs == 0 ? .green : .orange
                )
            ]
        case .protocolSafeDegrade:
            let safeDegradeRows = runtimeProtocolTraceRows(traceRows).filter(\.protocolSafeDegradeApplied)
            let completedSafeDegrade = safeDegradeRows.filter { $0.status == .completed }.count
            let missingRouteRepairs = safeDegradeRows.filter {
                $0.protocolRepairTypes.contains("missing_route_auto_selected")
            }.count
            return [
                OpsContextCard(
                    id: "safe-degrade-total",
                    title: "Safe Degrade",
                    value: "\(safeDegradeRows.count)",
                    detail: "Recent traces that fell back to safe degrade",
                    tone: safeDegradeRows.isEmpty ? .secondary : .teal
                ),
                OpsContextCard(
                    id: "safe-degrade-complete",
                    title: "Completed",
                    value: "\(completedSafeDegrade)",
                    detail: "Safe-degrade traces that still completed",
                    tone: completedSafeDegrade == safeDegradeRows.count && !safeDegradeRows.isEmpty ? .green : .orange
                ),
                OpsContextCard(
                    id: "safe-degrade-missing-route",
                    title: "Missing Route",
                    value: "\(missingRouteRepairs)",
                    detail: "Safe-degrade traces triggered by missing routes",
                    tone: missingRouteRepairs == 0 ? .green : .orange
                )
            ]
        case .protocolHardInterrupts:
            let runtimeTraceRows = runtimeProtocolTraceRows(traceRows)
            let hardInterruptRows = runtimeTraceRows.filter {
                $0.status == .failed && $0.protocolRepairCount > 0 && !$0.protocolSafeDegradeApplied
            }
            let approvalBlocked = hardInterruptRows.filter {
                $0.protocolRepairTypes.contains("route_missing_approval_blocked")
            }.count
            let totalRepaired = runtimeTraceRows.filter { $0.protocolRepairCount > 0 }.count
            return [
                OpsContextCard(
                    id: "interrupt-total",
                    title: "Hard Interrupts",
                    value: "\(hardInterruptRows.count)",
                    detail: "Recent traces that could not be safely repaired",
                    tone: hardInterruptRows.isEmpty ? .green : .red
                ),
                OpsContextCard(
                    id: "interrupt-approval",
                    title: "Approval Blocked",
                    value: "\(approvalBlocked)",
                    detail: "Interrupts caused by missing approval targets",
                    tone: approvalBlocked == 0 ? .green : .red
                ),
                OpsContextCard(
                    id: "interrupt-repaired",
                    title: "Repair Pressure",
                    value: "\(totalRepaired)",
                    detail: "Recent traces that entered the repair layer",
                    tone: totalRepaired == 0 ? .green : .orange
                )
            ]
        }
    }

    nonisolated static func signalRows(
        metric: OpsHistoryMetric,
        anomalyRows: [OpsAnomalyRow],
        traceRows: [OpsTraceSummaryRow],
        agentRows: [OpsAgentHealthRow],
        cronRuns: [OpsCronRunRow]
    ) -> [OpsHistorySignalRow] {
        switch metric {
        case .workflowReliability:
            let anomalySignals = anomalyRows
                .filter { $0.sourceLabel != "Cron" }
                .map { anomaly in
                    OpsHistorySignalRow(
                        id: "anomaly-\(anomaly.id)",
                        title: anomaly.title,
                        badge: anomaly.sourceLabel,
                        detail: anomaly.detailText,
                        occurredAt: anomaly.occurredAt,
                        tone: anomalyTone(for: anomaly.sourceLabel),
                        anomaly: anomaly,
                        trace: nil,
                        cronRun: nil
                    )
                }

            let traceSignals = traceRows
                .filter { $0.status == .failed }
                .map { trace in
                    OpsHistorySignalRow(
                        id: "trace-\(trace.id.uuidString)",
                        title: trace.agentName,
                        badge: trace.sourceLabel,
                        detail: trace.previewText,
                        occurredAt: trace.startedAt,
                        tone: traceTone(for: trace.status),
                        anomaly: nil,
                        trace: trace,
                        cronRun: nil
                    )
                }

            return (anomalySignals + traceSignals)
                .sorted { ($0.occurredAt ?? .distantPast) > ($1.occurredAt ?? .distantPast) }
        case .agentEngagement:
            return agentRows
                .sorted { lhs, rhs in
                    if lhs.completedCount != rhs.completedCount {
                        return lhs.completedCount > rhs.completedCount
                    }
                    return (lhs.lastActivityAt ?? .distantPast) > (rhs.lastActivityAt ?? .distantPast)
                }
                .prefix(6)
                .map { row in
                    OpsHistorySignalRow(
                        id: "agent-\(row.id.uuidString)",
                        title: row.agentName,
                        badge: row.stateText,
                        detail: "Completed \(row.completedCount) • Failed \(row.failedCount) • Last \(row.lastActivityAt?.formatted(date: .omitted, time: .shortened) ?? "inactive")",
                        occurredAt: row.lastActivityAt,
                        tone: healthTone(for: row.status),
                        anomaly: nil,
                        trace: nil,
                        cronRun: nil
                    )
                }
        case .memoryDiscipline:
            return agentRows
                .sorted { lhs, rhs in
                    if lhs.hasTrackedMemory != rhs.hasTrackedMemory {
                        return !lhs.hasTrackedMemory && rhs.hasTrackedMemory
                    }
                    return lhs.agentName < rhs.agentName
                }
                .prefix(6)
                .map { row in
                    OpsHistorySignalRow(
                        id: "memory-\(row.id.uuidString)",
                        title: row.agentName,
                        badge: row.hasTrackedMemory ? "Tracked" : "Gap",
                        detail: row.hasTrackedMemory
                            ? "Memory backup path is configured for this agent."
                            : "This agent is missing tracked memory backup coverage.",
                        occurredAt: row.lastActivityAt,
                        tone: row.hasTrackedMemory ? .green : .orange,
                        anomaly: nil,
                        trace: nil,
                        cronRun: nil
                    )
                }
        case .errorBudget:
            return anomalyRows
                .sorted { lhs, rhs in
                    if lhs.status != rhs.status {
                        return lhs.status == .critical && rhs.status != .critical
                    }
                    return lhs.occurredAt > rhs.occurredAt
                }
                .prefix(6)
                .map { anomaly in
                    OpsHistorySignalRow(
                        id: "budget-\(anomaly.id)",
                        title: anomaly.title,
                        badge: anomaly.status == .critical ? "Critical" : anomaly.sourceLabel,
                        detail: anomaly.detailText,
                        occurredAt: anomaly.occurredAt,
                        tone: healthTone(for: anomaly.status),
                        anomaly: anomaly,
                        trace: nil,
                        cronRun: nil
                    )
                }
        case .cronReliability:
            return cronRuns
                .map { run in
                    OpsHistorySignalRow(
                        id: "cron-\(run.id)",
                        title: run.cronName,
                        badge: run.statusText,
                        detail: "\(run.duration.map(formatDuration) ?? "-") • \(run.summaryText)",
                        occurredAt: run.runAt,
                        tone: run.statusText == "OK" ? .green : .red,
                        anomaly: anomalyRows.first(where: { $0.sourceLabel == "Cron" && $0.title == run.cronName }),
                        trace: nil,
                        cronRun: run
                    )
                }
                .sorted { ($0.occurredAt ?? .distantPast) > ($1.occurredAt ?? .distantPast) }
        case .protocolConformance:
            return runtimeProtocolTraceRows(traceRows)
                .filter { $0.protocolRepairCount > 0 || $0.protocolSafeDegradeApplied }
                .sorted { $0.startedAt > $1.startedAt }
                .prefix(6)
                .map { trace in
                    OpsHistorySignalRow(
                        id: "protocol-conformance-\(trace.id.uuidString)",
                        title: trace.agentName,
                        badge: trace.protocolSafeDegradeApplied ? "Safe Degrade" : "Repaired",
                        detail: trace.previewText,
                        occurredAt: trace.startedAt,
                        tone: trace.protocolSafeDegradeApplied ? .teal : .orange,
                        anomaly: nil,
                        trace: trace,
                        cronRun: nil
                    )
                }
        case .protocolAutoRepair:
            return runtimeProtocolTraceRows(traceRows)
                .filter { $0.protocolRepairCount > 0 }
                .sorted { $0.startedAt > $1.startedAt }
                .prefix(6)
                .map { trace in
                    OpsHistorySignalRow(
                        id: "protocol-repair-\(trace.id.uuidString)",
                        title: trace.agentName,
                        badge: trace.protocolRepairTypes.first.map(protocolBadge(for:)) ?? "Repair",
                        detail: trace.previewText,
                        occurredAt: trace.startedAt,
                        tone: trace.status == .completed ? .green : .orange,
                        anomaly: nil,
                        trace: trace,
                        cronRun: nil
                    )
                }
        case .protocolSafeDegrade:
            return runtimeProtocolTraceRows(traceRows)
                .filter(\.protocolSafeDegradeApplied)
                .sorted { $0.startedAt > $1.startedAt }
                .prefix(6)
                .map { trace in
                    OpsHistorySignalRow(
                        id: "protocol-safe-\(trace.id.uuidString)",
                        title: trace.agentName,
                        badge: "Safe Degrade",
                        detail: trace.previewText,
                        occurredAt: trace.startedAt,
                        tone: trace.status == .completed ? .teal : .orange,
                        anomaly: nil,
                        trace: trace,
                        cronRun: nil
                    )
                }
        case .protocolHardInterrupts:
            return runtimeProtocolTraceRows(traceRows)
                .filter { $0.status == .failed && $0.protocolRepairCount > 0 && !$0.protocolSafeDegradeApplied }
                .sorted { $0.startedAt > $1.startedAt }
                .prefix(6)
                .map { trace in
                    OpsHistorySignalRow(
                        id: "protocol-interrupt-\(trace.id.uuidString)",
                        title: trace.agentName,
                        badge: trace.protocolRepairTypes.first.map(protocolBadge(for:)) ?? "Interrupt",
                        detail: trace.previewText,
                        occurredAt: trace.startedAt,
                        tone: .red,
                        anomaly: nil,
                        trace: trace,
                        cronRun: nil
                    )
                }
        }
    }

    nonisolated private static func runtimeProtocolTraceRows(_ traceRows: [OpsTraceSummaryRow]) -> [OpsTraceSummaryRow] {
        traceRows.filter { $0.sourceLabel == "Runtime" }
    }

    nonisolated static func daySummaryCards(
        metric: OpsHistoryMetric,
        point: OpsMetricHistoryPoint?,
        rows: [OpsHistorySignalRow],
        selectedDate: Date
    ) -> [OpsContextCard] {
        let signalCount = rows.count
        let actionableCount = rows.filter { $0.anomaly != nil || $0.trace != nil || $0.cronRun != nil }.count
        let criticalCount = rows.filter { $0.badge == "Critical" || $0.badge == "Error" }.count

        return [
            OpsContextCard(
                id: "day-sample",
                title: "Sample",
                value: point.map { metric.formattedValue($0.value) } ?? "-",
                detail: selectedDate.formatted(date: .abbreviated, time: .omitted),
                tone: metricTone(for: metric)
            ),
            OpsContextCard(
                id: "day-signals",
                title: "Signals",
                value: "\(signalCount)",
                detail: "Rows captured for this day",
                tone: signalCount == 0 ? .secondary : .blue
            ),
            OpsContextCard(
                id: "day-actionable",
                title: "Actionable",
                value: "\(actionableCount)",
                detail: "Rows that can open detail panels",
                tone: actionableCount == 0 ? .secondary : .teal
            ),
            OpsContextCard(
                id: "day-critical",
                title: "Critical",
                value: "\(criticalCount)",
                detail: "High-risk signals on this day",
                tone: criticalCount == 0 ? .green : .red
            )
        ]
    }

    nonisolated private static func healthTone(for status: OpsHealthStatus) -> OpsAccentTone {
        switch status {
        case .healthy:
            return .green
        case .warning:
            return .orange
        case .critical:
            return .red
        case .neutral:
            return .secondary
        }
    }

    nonisolated private static func anomalyTone(for sourceLabel: String) -> OpsAccentTone {
        switch sourceLabel {
        case "Cron":
            return .red
        case "Tool":
            return .teal
        case "OpenClaw":
            return .orange
        default:
            return .blue
        }
    }

    nonisolated private static func traceTone(for status: ExecutionStatus) -> OpsAccentTone {
        switch status {
        case .completed:
            return .green
        case .failed:
            return .red
        case .running:
            return .orange
        case .waiting:
            return .blue
        case .idle:
            return .secondary
        }
    }

    nonisolated private static func formatDuration(_ duration: TimeInterval) -> String {
        if duration >= 60 {
            let minutes = Int(duration) / 60
            let seconds = Int(duration) % 60
            return "\(minutes)m \(seconds)s"
        }
        return String(format: "%.1fs", duration)
    }

    nonisolated private static func metricTone(for metric: OpsHistoryMetric) -> OpsAccentTone {
        switch metric {
        case .workflowReliability:
            return .green
        case .agentEngagement:
            return .blue
        case .memoryDiscipline:
            return .orange
        case .errorBudget:
            return .red
        case .cronReliability:
            return .teal
        case .protocolConformance:
            return .green
        case .protocolAutoRepair:
            return .orange
        case .protocolSafeDegrade:
            return .teal
        case .protocolHardInterrupts:
            return .red
        }
    }

    nonisolated private static func protocolBadge(for repairType: String) -> String {
        switch repairType {
        case "missing_route_auto_selected":
            return "Missing Route"
        case "invalid_targets_auto_selected":
            return "Invalid Target"
        case "route_missing_approval_blocked":
            return "Approval Blocked"
        default:
            return "Repair"
        }
    }
}

enum OpsHistoryNarrativeBuilder {
    nonisolated static func deltaText(for series: OpsMetricHistorySeries) -> String {
        guard let latest = series.latestPoint?.value else {
            return "No historical samples yet"
        }

        guard let previous = series.previousPoint?.value else {
            return "First sample: \(series.metric.formattedValue(latest))"
        }

        let delta = latest - previous
        if series.metric == .errorBudget {
            let sign = delta > 0 ? "+" : ""
            return "Changed \(sign)\(Int(delta.rounded())) since previous sample"
        }

        let sign = delta > 0 ? "+" : ""
        return "Changed \(sign)\(Int(delta.rounded())) pts since previous sample"
    }

    nonisolated static func narrative(
        for series: OpsMetricHistorySeries,
        focusText: String
    ) -> String {
        let latestText = series.latestPoint.map { series.metric.formattedValue($0.value) } ?? "no sample"
        let deltaText = deltaText(for: series)

        switch series.metric {
        case .workflowReliability:
            return "\(focusText) workflow reliability is currently \(latestText). \(deltaText), with recent runtime and tool anomalies shown below for faster root-cause review."
        case .agentEngagement:
            return "\(focusText) agent engagement is currently \(latestText). \(deltaText), and the signal rows highlight which agents are carrying or losing activity."
        case .memoryDiscipline:
            return "\(focusText) memory discipline is currently \(latestText). \(deltaText), with contributor rows showing which agents are covered by tracked memory backups."
        case .errorBudget:
            return "\(focusText) error budget is currently \(latestText). \(deltaText), so the rows below focus on the newest failure, timeout, and escalation signals."
        case .cronReliability:
            return "\(focusText) cron reliability is currently \(latestText). \(deltaText), and the related signals below show the latest scheduled runs feeding this trend."
        case .protocolConformance:
            return "\(focusText) protocol conformance is currently \(latestText). \(deltaText), and the rows below highlight recent traces that required repair or safe degrade."
        case .protocolAutoRepair:
            return "\(focusText) protocol auto repair is currently \(latestText). \(deltaText), with the latest repaired traces listed below for route-level follow-up."
        case .protocolSafeDegrade:
            return "\(focusText) protocol safe degrade is currently \(latestText). \(deltaText), and the signal rows show which traces completed through degraded routing."
        case .protocolHardInterrupts:
            return "\(focusText) protocol hard interrupts are currently \(latestText). \(deltaText), so the rows below focus on unrecoverable protocol stops that need rule or approval fixes."
        }
    }
}

enum OpsAnomalyInsightBuilder {
    nonisolated static func explorerCards(
        rows: [OpsAnomalyRow],
        clusters: [OpsAnomalyCluster],
        timeWindowDetail: String
    ) -> [OpsContextCard] {
        let criticalCount = rows.filter { $0.status == .critical }.count
        let cronCount = rows.filter { $0.sourceLabel == "Cron" }.count
        let linkedTraceCount = rows.filter { $0.linkedSpanID != nil }.count
        let repeatedClusters = clusters.filter { $0.occurrenceCount > 1 }.count

        return [
            OpsContextCard(
                id: "matching",
                title: "Matching",
                value: "\(rows.count)",
                detail: timeWindowDetail,
                tone: rows.isEmpty ? .secondary : .blue
            ),
            OpsContextCard(
                id: "critical",
                title: "Critical",
                value: "\(criticalCount)",
                detail: "Highest-severity anomalies in scope",
                tone: criticalCount == 0 ? .green : .red
            ),
            OpsContextCard(
                id: "cron",
                title: "Cron Impact",
                value: "\(cronCount)",
                detail: "Scheduled run anomalies in scope",
                tone: cronCount == 0 ? .green : .orange
            ),
            OpsContextCard(
                id: "clusters",
                title: "Repeated Clusters",
                value: "\(repeatedClusters)",
                detail: "\(linkedTraceCount) trace-linked rows retained",
                tone: repeatedClusters == 0 ? .secondary : .teal
            )
        ]
    }
}

enum OpsAnomalyClusterInsightBuilder {
    nonisolated static func trendText(
        occurrenceCount: Int,
        recent24HourCount: Int,
        includeEarlierBreakdown: Bool
    ) -> String {
        guard includeEarlierBreakdown else {
            return "24h \(recent24HourCount)"
        }

        let olderCount = max(occurrenceCount - recent24HourCount, 0)
        return "24h \(recent24HourCount) • earlier \(olderCount)"
    }
}

enum OpsHistoryScopeMatcher {
    enum Kind {
        case project
        case agent
        case tool
        case cron

        fileprivate init(_ mode: OpsHistoryFocusMode) {
            switch mode {
            case .project:
                self = .project
            case .agent:
                self = .agent
            case .tool:
                self = .tool
            case .cron:
                self = .cron
            }
        }
    }

    nonisolated static func matches(
        _ row: OpsAnomalyRow,
        kind: Kind,
        matchKey: String
    ) -> Bool {
        switch kind {
        case .project:
            return true
        case .agent:
            return matchesAnyText(
                [
                    row.title,
                    row.detailText,
                    row.fullDetailText,
                    row.sourceService ?? ""
                ],
                matchKey: matchKey
            )
        case .tool:
            guard row.sourceLabel == "Tool" else { return false }
            return matchesAnyText(
                [
                    row.title,
                    row.detailText,
                    row.fullDetailText,
                    row.sourceService ?? ""
                ],
                matchKey: matchKey
            )
        case .cron:
            guard row.sourceLabel == "Cron" else { return false }
            return normalized(row.title) == normalized(matchKey)
        }
    }

    nonisolated static func matches(
        _ row: OpsTraceSummaryRow,
        kind: Kind,
        matchKey: String
    ) -> Bool {
        switch kind {
        case .project:
            return true
        case .agent:
            return normalized(row.agentName) == normalized(matchKey)
        case .tool:
            return matchesAnyText(
                [
                    row.previewText,
                    row.routingAction ?? "",
                    row.outputType.rawValue
                ],
                matchKey: matchKey
            )
        case .cron:
            return false
        }
    }

    nonisolated static func matches(
        _ row: OpsAgentHealthRow,
        kind: Kind,
        matchKey: String
    ) -> Bool {
        switch kind {
        case .project:
            return true
        case .agent:
            return normalized(row.agentName) == normalized(matchKey)
        case .tool, .cron:
            return false
        }
    }

    nonisolated static func matches(
        _ row: OpsCronRunRow,
        kind: Kind,
        matchKey: String
    ) -> Bool {
        switch kind {
        case .project:
            return true
        case .agent:
            return matchesAnyText(
                [
                    row.cronName,
                    row.summaryText
                ],
                matchKey: matchKey
            )
        case .tool:
            return matchesAnyText(
                [
                    row.summaryText,
                    row.cronName
                ],
                matchKey: matchKey
            )
        case .cron:
            return normalized(row.cronName) == normalized(matchKey)
        }
    }

    nonisolated private static func matchesAnyText(
        _ texts: [String],
        matchKey: String
    ) -> Bool {
        let needle = normalized(matchKey)
        guard !needle.isEmpty else { return true }
        return texts
            .joined(separator: " ")
            .lowercased()
            .contains(needle)
    }

    nonisolated private static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

private enum OpsCenterPage: String, CaseIterable, Identifiable {
    case liveOverview
    case projectHistory

    var id: String { rawValue }

    var title: String {
        switch self {
        case .liveOverview: return "Live Ops"
        case .projectHistory: return "Project History"
        }
    }
}

private enum OpsTraceSourceFilter: String, CaseIterable, Identifiable {
    case all
    case runtime
    case openClaw

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .runtime: return "Runtime"
        case .openClaw: return "OpenClaw"
        }
    }

    func matches(_ row: OpsTraceSummaryRow) -> Bool {
        switch self {
        case .all:
            return true
        case .runtime:
            return row.sourceLabel == "Runtime"
        case .openClaw:
            return row.sourceLabel == "OpenClaw"
        }
    }
}

enum OpsProtocolTraceFilter: String, CaseIterable, Identifiable {
    case all
    case repaired
    case safeDegrade
    case hardInterrupt
    case missingRoute
    case invalidTarget
    case approvalBlocked

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All Protocol"
        case .repaired: return "Repaired"
        case .safeDegrade: return "Safe Degrade"
        case .hardInterrupt: return "Hard Interrupt"
        case .missingRoute: return "Missing Route"
        case .invalidTarget: return "Invalid Target"
        case .approvalBlocked: return "Approval Blocked"
        }
    }

    func matches(_ row: OpsTraceSummaryRow) -> Bool {
        switch self {
        case .all:
            return true
        case .repaired:
            return row.protocolRepairCount > 0
        case .safeDegrade:
            return row.protocolSafeDegradeApplied
        case .hardInterrupt:
            return row.status == .failed && row.protocolRepairCount > 0 && !row.protocolSafeDegradeApplied
        case .missingRoute:
            return row.protocolRepairTypes.contains("missing_route_auto_selected")
        case .invalidTarget:
            return row.protocolRepairTypes.contains("invalid_targets_auto_selected")
        case .approvalBlocked:
            return row.protocolRepairTypes.contains("route_missing_approval_blocked")
        }
    }
}

private enum OpsTraceSpanFilter: String, CaseIterable, Identifiable {
    case all
    case conversation
    case tools
    case runtime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .conversation: return "Messages"
        case .tools: return "Tools"
        case .runtime: return "Runtime"
        }
    }

    func matches(service: String) -> Bool {
        switch self {
        case .all:
            return true
        case .conversation:
            return service.contains("message")
        case .tools:
            return service.contains("tool")
        case .runtime:
            return !service.contains("message") && !service.contains("tool")
        }
    }
}

private enum OpsAnomalySourceFilter: String, CaseIterable, Identifiable {
    case all
    case runtime
    case tool
    case cron
    case openClaw

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .runtime: return "Runtime"
        case .tool: return "Tool"
        case .cron: return "Cron"
        case .openClaw: return "OpenClaw"
        }
    }

    func matches(_ row: OpsAnomalyRow) -> Bool {
        switch self {
        case .all:
            return true
        case .runtime:
            return row.sourceLabel == "Runtime"
        case .tool:
            return row.sourceLabel == "Tool"
        case .cron:
            return row.sourceLabel == "Cron"
        case .openClaw:
            return row.sourceLabel == "OpenClaw"
        }
    }
}

private enum OpsAnomalySeverityFilter: String, CaseIterable, Identifiable {
    case all
    case critical
    case warning

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return LocalizedString.text("filter_all")
        case .critical: return LocalizedString.text("critical_label")
        case .warning: return LocalizedString.text("warning_label")
        }
    }

    func matches(_ row: OpsAnomalyRow) -> Bool {
        switch self {
        case .all:
            return true
        case .critical:
            return row.status == .critical
        case .warning:
            return row.status == .warning
        }
    }
}

private enum OpsAnomalyTimeWindow: String, CaseIterable, Identifiable {
    case last24Hours
    case last3Days
    case last7Days
    case last14Days
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .last24Hours: return "24h"
        case .last3Days: return "3d"
        case .last7Days: return "7d"
        case .last14Days: return "14d"
        case .all: return "All"
        }
    }

    var dayCount: Int? {
        switch self {
        case .last24Hours: return 1
        case .last3Days: return 3
        case .last7Days: return 7
        case .last14Days: return 14
        case .all: return nil
        }
    }

    var detailText: String {
        switch self {
        case .last24Hours: return LocalizedString.text("signals_last_24_hours")
        case .last3Days: return LocalizedString.text("signals_last_3_days")
        case .last7Days: return LocalizedString.text("signals_last_7_days")
        case .last14Days: return LocalizedString.text("signals_last_14_days")
        case .all: return LocalizedString.text("all_retained_anomalies_local_cache")
        }
    }
}

private enum OpsHistoryFocusMode: String, CaseIterable, Identifiable {
    case project
    case agent
    case tool
    case cron

    var id: String { rawValue }

    var title: String {
        switch self {
        case .project: return "Project"
        case .agent: return "Agent"
        case .tool: return "Tool"
        case .cron: return "Cron"
        }
    }
}

struct MonitoringDashboardView: View {
    @EnvironmentObject var appState: AppState
    @State private var metrics = DashboardMetrics()
    @State private var opsSnapshot: OpsAnalyticsSnapshot = .empty
    @State private var pendingMetricsRefreshWorkItem: DispatchWorkItem?
    @State private var selectedOpsCenterPage: OpsCenterPage = .liveOverview
    @State private var selectedHistoryCategory: OpsHistoryCategory = .all
    @State private var selectedHistoryWindow: OpsHistoryWindow = .last30Days
    @State private var selectedHistoryMetric: OpsHistoryMetric = .workflowReliability
    @State private var selectedHistoryFocusMode: OpsHistoryFocusMode = .project
    @State private var selectedHistoryFocusID: String = "project"
    @State private var selectedHistoryDateID: String = ""
    @State private var scopedHistoricalSeries: [OpsMetricHistorySeries] = []
    @State private var selectedTraceSourceFilter: OpsTraceSourceFilter = .all
    @State private var selectedProtocolTraceFilter: OpsProtocolTraceFilter = .all
    @State private var selectedProtocolAgentFilter: String?
    @State private var traceSearchText: String = ""
    @State private var selectedTracePanel: OpsTracePanelModel?
    @State private var selectedAnomalyPanel: OpsAnomalyPanelModel?
    @State private var selectedCronPanel: OpsCronPanelModel?
    @State private var selectedToolPanel: OpsToolPanelModel?
    @State private var selectedAnomalySourceFilter: OpsAnomalySourceFilter = .all
    @State private var selectedAnomalySeverityFilter: OpsAnomalySeverityFilter = .all
    @State private var selectedAnomalyTimeWindow: OpsAnomalyTimeWindow = .last7Days
    @State private var anomalySearchText: String = ""

    private var project: MAProject? { appState.currentProject }
    private var taskStats: TaskManager.TaskStatistics { appState.taskManager.statistics }
    private var executionState: ExecutionState? { appState.openClawService.executionState }
    private let metricsRefreshDebounce: TimeInterval = 0.25
    private let historyCalendar = Calendar.autoupdatingCurrent

    private var recentTasks: [Task] {
        appState.taskManager.tasks.sorted { $0.createdAt > $1.createdAt }.prefix(8).map { $0 }
    }
    private var conversationTotalCount: Int {
        metrics.conversationTotalCount
    }
    private var agentConversationRows: [DashboardAgentConversationRow] {
        metrics.agentConversationRows
    }
    private var modelTokenRows: [DashboardModelTokenUsageRow] {
        metrics.modelTokenRows
    }
    private var totalTokenCount: Int {
        metrics.totalTokenCount
    }
    private var activeAgentCount: Int {
        metrics.activeAgentCount
    }
    private var idleAgentCount: Int {
        metrics.idleAgentCount
    }
    private var isWorkflowRuntimeAvailable: Bool {
        appState.openClawManager.canRunWorkflow
    }
    private var isOpenClawRuntimeDegraded: Bool {
        appState.openClawManager.connectionState.isRunnableWithDegradedCapabilities
    }
    private var openClawStatusValueText: String {
        if appState.openClawManager.isConnected {
            return LocalizedString.text("connected_status")
        }
        if isOpenClawRuntimeDegraded {
            return LocalizedString.text("degraded_status")
        }
        return LocalizedString.text("disconnected_status")
    }
    private var openClawStatusColor: Color {
        if appState.openClawManager.isConnected {
            return .green
        }
        if isOpenClawRuntimeDegraded {
            return .orange
        }
        return .red
    }
    private var openClawAttachmentColor: Color {
        switch appState.currentProjectOpenClawAttachmentState {
        case .attachedCurrentProject:
            return .green
        case .attachedDifferentProject, .unattached:
            return .orange
        case .remoteConnectionOnly:
            return .blue
        case .noProject:
            return .secondary
        }
    }
    private var openClawLatestSyncColor: Color {
        switch appState.latestOpenClawRuntimeSyncReceipt?.status {
        case .succeeded:
            return .green
        case .partial:
            return .orange
        case .failed:
            return .red
        case .none:
            return .secondary
        }
    }
    private var openClawOverviewDetailText: String {
        if let revisionSummary = appState.openClawRevisionSummary {
            return "\(appState.openClawManager.config.deploymentSummary) • \(appState.openClawAttachmentStatusTitle) • \(revisionSummary)"
        }
        return "\(appState.openClawManager.config.deploymentSummary) • \(appState.openClawAttachmentStatusTitle)"
    }
    private var openClawOverviewCardColor: Color {
        switch appState.currentProjectOpenClawAttachmentState {
        case .attachedCurrentProject:
            return openClawStatusColor
        case .attachedDifferentProject, .unattached, .remoteConnectionOnly, .noProject:
            return openClawAttachmentColor
        }
    }
    private var blockedRuntimeMessage: String? {
        let detail = appState.openClawManager.connectionState.health.lastMessage?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let detail, !detail.isEmpty else { return nil }
        return detail
    }
    private var sourceHistoricalSeries: [OpsMetricHistorySeries] {
        selectedHistoryFocusMode == .project ? opsSnapshot.historicalSeries : scopedHistoricalSeries
    }
    private var filteredHistoricalSeries: [OpsMetricHistorySeries] {
        let cutoffDate = historyCalendar.date(
            byAdding: .day,
            value: -(selectedHistoryWindow.rawValue - 1),
            to: historyCalendar.startOfDay(for: Date())
        ) ?? .distantPast

        return sourceHistoricalSeries
            .filter { series in
                selectedHistoryCategory == .all || series.metric.category == selectedHistoryCategory
            }
            .map { series in
                OpsMetricHistorySeries(
                    metric: series.metric,
                    points: series.points.filter { $0.date >= cutoffDate }
                )
            }
    }
    private var visibleHistoricalSeries: [OpsMetricHistorySeries] {
        filteredHistoricalSeries.filter { !$0.points.isEmpty }
    }
    private var effectiveSelectedHistoryMetric: OpsHistoryMetric {
        visibleHistoricalSeries.first(where: { $0.metric == selectedHistoryMetric })?.metric
            ?? visibleHistoricalSeries.first?.metric
            ?? selectedHistoryMetric
    }
    private var selectedHistorySeries: OpsMetricHistorySeries? {
        visibleHistoricalSeries.first { $0.metric == effectiveSelectedHistoryMetric }
    }
    private var historyDateOptions: [OpsHistoryDateOption] {
        guard let series = selectedHistorySeries else { return [] }
        return series.points
            .sorted { $0.date > $1.date }
            .map {
                OpsHistoryDateOption(
                    id: historyDateID(for: $0.date),
                    date: $0.date,
                    title: $0.date.formatted(date: .abbreviated, time: .omitted)
                )
            }
    }
    private var effectiveSelectedHistoryDateOption: OpsHistoryDateOption? {
        historyDateOptions.first(where: { $0.id == selectedHistoryDateID }) ?? historyDateOptions.first
    }
    private var historyFocusOptions: [OpsHistoryFocusOption] {
        historyFocusOptions(for: selectedHistoryFocusMode)
    }
    private var effectiveSelectedHistoryFocus: OpsHistoryFocusOption {
        historyFocusOptions.first(where: { $0.id == selectedHistoryFocusID })
            ?? historyFocusOptions.first
            ?? OpsHistoryFocusOption(
                id: "project",
                title: project?.name ?? "Project",
                subtitle: "Project-wide context",
                matchKey: project?.name.lowercased() ?? "project",
                scopeValue: "project"
            )
    }
    private var historyScopeMatcherKind: OpsHistoryScopeMatcher.Kind {
        .init(selectedHistoryFocusMode)
    }
    private var anomalyWindowStart: Date? {
        guard let dayCount = selectedAnomalyTimeWindow.dayCount else { return nil }
        return historyCalendar.date(byAdding: .day, value: -dayCount, to: Date())
    }
    private var filteredAnomalyRows: [OpsAnomalyRow] {
        OpsAnomalyClusterBuilder.filteredRows(
            from: opsSnapshot.anomalyRows,
            sourceFilter: .init(selectedAnomalySourceFilter),
            severityFilter: .init(selectedAnomalySeverityFilter),
            searchText: anomalySearchText,
            windowStart: anomalyWindowStart
        )
    }
    private var anomalyClusters: [OpsAnomalyCluster] {
        OpsAnomalyClusterBuilder.clusters(
            from: filteredAnomalyRows,
            now: Date(),
            calendar: historyCalendar
        )
    }
    private var hotAnomalyClusters: [OpsAnomalyCluster] {
        Array(anomalyClusters.prefix(6))
    }
    private var primaryOpsGoalCards: [OpsGoalCard] {
        opsSnapshot.goalCards.filter { !$0.id.hasPrefix("protocol_") }
    }
    private var protocolGoalCards: [OpsGoalCard] {
        opsSnapshot.goalCards.filter { $0.id.hasPrefix("protocol_") }
    }
    private var protocolHistoricalSeries: [OpsMetricHistorySeries] {
        opsSnapshot.historicalSeries.filter {
            [
                OpsHistoryMetric.protocolConformance,
                .protocolAutoRepair,
                .protocolSafeDegrade,
                .protocolHardInterrupts
            ].contains($0.metric) && !$0.points.isEmpty
        }
    }
    private var protocolRepairDistribution: [OpsProtocolRepairDistributionItem] {
        OpsProtocolRepairDistributionBuilder.items(from: opsSnapshot.traceRows)
    }
    private var protocolAgentProfiles: [OpsProtocolAgentProfile] {
        OpsProtocolAgentInsightBuilder.profiles(from: opsSnapshot.traceRows)
    }
    private var activeProtocolTraceFilterTitle: String? {
        selectedProtocolTraceFilter == .all ? nil : selectedProtocolTraceFilter.title
    }
    private var activeProtocolAgentFilterTitle: String? {
        selectedProtocolAgentFilter
    }
    private var activeProtocolDrillDownSummary: String? {
        switch (activeProtocolTraceFilterTitle, activeProtocolAgentFilterTitle) {
        case let (trace?, agent?):
            return "\(trace) • \(agent)"
        case let (trace?, nil):
            return trace
        case let (nil, agent?):
            return agent
        default:
            return nil
        }
    }
    private var filteredTraceRows: [OpsTraceSummaryRow] {
        let normalizedSearch = traceSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return opsSnapshot.traceRows.filter { row in
            guard selectedTraceSourceFilter.matches(row) else { return false }
            guard selectedProtocolTraceFilter.matches(row) else { return false }
            if let selectedProtocolAgentFilter,
               row.agentName.localizedCaseInsensitiveCompare(selectedProtocolAgentFilter) != .orderedSame {
                return false
            }
            guard !normalizedSearch.isEmpty else { return true }

            let haystack = [
                row.agentName,
                row.previewText,
                row.routingAction ?? "",
                row.outputType.rawValue,
                row.sourceLabel,
                row.protocolRepairTypes.joined(separator: " ")
            ]
            .joined(separator: " ")
            .lowercased()

            return haystack.contains(normalizedSearch)
        }
    }
    private var dashboardRefreshSignature: String {
        let projectSignature = project.map {
            [
                $0.id.uuidString,
                "\($0.agents.count)",
                "\($0.workflows.count)",
                $0.updatedAt.timeIntervalSinceReferenceDate.formatted()
            ].joined(separator: ":")
        } ?? "no-project"
        let messageSignature = appState.messageManager.messages.last.map {
            "\($0.id.uuidString):\($0.content.count):\($0.timestamp.timeIntervalSinceReferenceDate)"
        } ?? "no-messages"
        let taskSignature = appState.taskManager.tasks.last.map {
            "\($0.id.uuidString):\($0.status.rawValue):\($0.createdAt.timeIntervalSinceReferenceDate)"
        } ?? "no-tasks"
        let activeAgentSignature = appState.openClawManager.activeAgents.values
            .sorted { $0.agentID.uuidString < $1.agentID.uuidString }
            .map { "\($0.agentID.uuidString):\($0.status)" }
            .joined(separator: "|")

        return [
            projectSignature,
            messageSignature,
            taskSignature,
            activeAgentSignature,
            appState.openClawManager.connectionState.phase.rawValue,
            String(appState.openClawManager.canRunWorkflow)
        ].joined(separator: "::")
    }

    var body: some View {
        Group {
            if project == nil {
                ContentUnavailableView(
                    LocalizedString.text("open_project_first"),
                    systemImage: "gauge.with.dots.needle.33percent",
                    description: Text(LocalizedString.text("open_project_first_dashboard_desc"))
                )
            } else if !isWorkflowRuntimeAvailable {
                VStack(spacing: 16) {
                    Image(systemName: "cable.connector")
                        .font(.system(size: 44))
                        .foregroundColor(.accentColor)

                    Text(LocalizedString.text("connect_openclaw_first"))
                        .font(.title3)
                        .fontWeight(.semibold)

                    Text(LocalizedString.text("connect_openclaw_first_dashboard_desc"))
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 520)

                    if let blockedRuntimeMessage {
                        Text(blockedRuntimeMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 520)
                    }

                    HStack(spacing: 12) {
                        Button(LocalizedString.text("connect_openclaw")) {
                            appState.connectOpenClaw()
                        }
                        .buttonStyle(.borderedProminent)

                        Button(LocalizedString.text("open_settings")) {
                            NotificationCenter.default.post(name: .openSettings, object: nil)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(32)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        opsCenterHeaderSection
                        if selectedOpsCenterPage == .liveOverview {
                            opsOverviewSection
                            opsProtocolGovernanceSection
                            opsAnomalyOverviewSection
                            opsAnomalyExplorerSection
                            opsDailyActivitySection
                            opsCronReliabilitySection
                            opsAgentHealthSection
                        } else {
                            opsProjectHistorySection
                        }
                        opsTraceSection
                        overviewSection
                        conversationMonitoringSection
                        executionSection
                        interventionSection
                        taskSection
                        resultsSection
                        logsSection
                    }
                    .padding()
                }
            }
        }
        .onAppear {
            opsSnapshot = appState.opsAnalytics.snapshot
            reloadScopedHistorySeries()
            normalizeHistoryDateSelection()
            scheduleMetricsRefresh(immediately: true)
        }
        .onReceive(appState.opsAnalytics.$snapshot) { snapshot in
            opsSnapshot = snapshot
            reloadScopedHistorySeries()
            normalizeHistoryDateSelection()
        }
        .onChange(of: selectedHistoryFocusMode) { _, newMode in
            let options = historyFocusOptions(for: newMode)
            if !options.contains(where: { $0.id == selectedHistoryFocusID }) {
                selectedHistoryFocusID = options.first?.id ?? "project"
            }
            reloadScopedHistorySeries()
            normalizeHistoryDateSelection()
        }
        .onChange(of: selectedHistoryFocusID) { _, _ in
            reloadScopedHistorySeries()
            normalizeHistoryDateSelection()
        }
        .onChange(of: selectedHistoryMetric) { _, _ in
            if !historyDateOptions.contains(where: { $0.id == selectedHistoryDateID }) {
                selectedHistoryDateID = historyDateOptions.first?.id ?? ""
            }
        }
        .onChange(of: selectedHistoryWindow) { _, _ in
            if !historyDateOptions.contains(where: { $0.id == selectedHistoryDateID }) {
                selectedHistoryDateID = historyDateOptions.first?.id ?? ""
            }
        }
        .onChange(of: dashboardRefreshSignature) { _, _ in
            scheduleMetricsRefresh(immediately: false)
        }
        .onDisappear {
            pendingMetricsRefreshWorkItem?.cancel()
            pendingMetricsRefreshWorkItem = nil
        }
        .sheet(item: $selectedTracePanel) { panel in
            OpsTraceDetailSheet(panel: panel)
        }
        .sheet(item: $selectedAnomalyPanel) { panel in
            OpsAnomalyDetailSheet(panel: panel)
        }
        .sheet(item: $selectedCronPanel) { panel in
            OpsCronDetailSheet(panel: panel)
                .environmentObject(appState)
        }
        .sheet(item: $selectedToolPanel) { panel in
            OpsToolDetailSheet(panel: panel)
                .environmentObject(appState)
        }
    }

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LocalizedString.text("global_status"))
                .font(.headline)

            HStack(spacing: 16) {
                monitoringCard(
                    title: "OpenClaw",
                    value: openClawStatusValueText,
                    detail: openClawOverviewDetailText,
                    color: openClawOverviewCardColor
                )
                monitoringCard(
                    title: LocalizedString.tasks,
                    value: "\(taskStats.total)",
                    detail: "\(LocalizedString.text("mark_in_progress")) \(taskStats.inProgress) / \(LocalizedString.text("mark_blocked")) \(taskStats.blocked)",
                    color: .blue
                )
                monitoringCard(
                    title: LocalizedString.execution,
                    value: appState.openClawService.isExecuting ? LocalizedString.text("running_status") : LocalizedString.text("idle_status"),
                    detail: executionProgressText,
                    color: appState.openClawService.isExecuting ? .orange : .secondary
                )
                monitoringCard(
                    title: LocalizedString.text("memory_backup"),
                    value: "\(project?.memoryData.taskExecutionMemories.count ?? 0)",
                    detail: "\(LocalizedString.tasks) \(project?.memoryData.taskExecutionMemories.count ?? 0) / \(LocalizedString.agent) \(project?.memoryData.agentMemories.count ?? 0)",
                    color: .purple
                )
            }
        }
    }

    private var opsCenterHeaderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(LocalizedString.text("ops_center"))
                    .font(.headline)

                Spacer()

                if opsSnapshot.generatedAt != .distantPast {
                    Text(LocalizedString.format("updated_time", opsSnapshot.generatedAt.formatted(date: .omitted, time: .shortened)))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Picker(LocalizedString.text("ops_center_page"), selection: $selectedOpsCenterPage) {
                ForEach(OpsCenterPage.allCases) { page in
                    Text(page.title).tag(page)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var opsOverviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LocalizedString.text("current_posture"))
                .font(.headline)

            if primaryOpsGoalCards.isEmpty {
                Text(LocalizedString.text("ops_analytics_after_project_loaded"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16)], spacing: 16) {
                    ForEach(primaryOpsGoalCards) { card in
                        monitoringCard(
                            title: card.title,
                            value: card.valueText,
                            detail: card.detailText,
                            color: opsColor(for: card.status)
                        )
                    }
                }
            }
        }
    }

    private var opsProtocolGovernanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Protocol Governance")
                        .font(.headline)
                    Text("Track conformance, repair quality, and interruption pressure across recent agent runs.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if let drillDownSummary = activeProtocolDrillDownSummary {
                    Text("Trace drill-down: \(drillDownSummary)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if protocolGoalCards.isEmpty && protocolRepairDistribution.isEmpty {
                Text("Protocol governance metrics will appear after runtime traces are ingested.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                if !protocolGoalCards.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16)], spacing: 16) {
                        ForEach(protocolGoalCards) { card in
                            Button {
                                applyProtocolDrillDown(for: card)
                            } label: {
                                monitoringCard(
                                    title: card.title,
                                    value: card.valueText,
                                    detail: card.detailText,
                                    color: opsColor(for: card.status)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if !protocolHistoricalSeries.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Protocol Trends")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("Click to open historical view")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16)], spacing: 16) {
                            ForEach(protocolHistoricalSeries) { series in
                                Button {
                                    selectedOpsCenterPage = .projectHistory
                                    selectedHistoryCategory = .runtime
                                    selectedHistoryMetric = series.metric
                                } label: {
                                    historyMetricCard(
                                        series: series,
                                        isSelected: selectedOpsCenterPage == .projectHistory
                                            && effectiveSelectedHistoryMetric == series.metric
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding()
                    .background(Color(.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                if !protocolRepairDistribution.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Repair Distribution")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("Recent traces")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                            ForEach(protocolRepairDistribution) { item in
                                Button {
                                    applyProtocolTraceFilter(item.filter)
                                } label: {
                                    monitoringCard(
                                        title: item.title,
                                        value: "\(item.count)",
                                        detail: "Recent traces repaired by this protocol rule",
                                        color: selectedProtocolTraceFilter == item.filter ? .teal : .orange
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding()
                    .background(Color(.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                if !protocolAgentProfiles.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Agent Profiles")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("Highest protocol pressure first")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        VStack(spacing: 8) {
                            ForEach(protocolAgentProfiles) { profile in
                                protocolAgentProfileButton(profile)
                            }
                        }
                    }
                    .padding()
                    .background(Color(.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }

    private var opsAnomalyOverviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(LocalizedString.text("project_anomalies"))
                        .font(.headline)
                    Text(LocalizedString.text("project_anomalies_desc"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if let latest = opsSnapshot.anomalySummary?.latestAnomalyAt {
                    Text(LocalizedString.format("latest_time", latest.formatted(date: .abbreviated, time: .shortened)))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if let summary = opsSnapshot.anomalySummary {
                HStack(spacing: 16) {
                    monitoringCard(
                        title: LocalizedString.text("runtime_failures"),
                        value: "\(summary.runtimeFailures24h)",
                        detail: LocalizedString.format("time_window_24h_7d", summary.runtimeFailures24h, summary.runtimeFailures7d),
                        color: summary.runtimeFailures24h == 0 ? .green : .red
                    )
                    monitoringCard(
                        title: LocalizedString.text("tool_failures"),
                        value: "\(summary.toolFailures24h)",
                        detail: LocalizedString.format("time_window_24h_7d", summary.toolFailures24h, summary.toolFailures7d),
                        color: summary.toolFailures24h == 0 ? .green : .orange
                    )
                    monitoringCard(
                        title: LocalizedString.text("cron_errors"),
                        value: "\(summary.cronFailures24h)",
                        detail: LocalizedString.format("time_window_24h_7d", summary.cronFailures24h, summary.cronFailures7d),
                        color: summary.cronFailures24h == 0 ? .green : .red
                    )
                    monitoringCard(
                        title: LocalizedString.text("timeouts"),
                        value: "\(summary.timeoutCount7d)",
                        detail: LocalizedString.text("timeouts_7d_detail"),
                        color: summary.timeoutCount7d == 0 ? .green : .orange
                    )
                }

                VStack(spacing: 8) {
                    ForEach(opsSnapshot.anomalyRows) { row in
                        anomalyRowButton(row)
                    }
                }
                .padding()
                .background(Color(.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                Text(LocalizedString.text("no_project_level_anomalies"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private var opsProjectHistorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(LocalizedString.text("project_history"))
                        .font(.headline)
                    Text(LocalizedString.text("project_history_desc"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            HStack(spacing: 12) {
                Picker(LocalizedString.text("history_category"), selection: $selectedHistoryCategory) {
                    ForEach(OpsHistoryCategory.allCases) { category in
                        Text(category.title).tag(category)
                    }
                }
                .pickerStyle(.segmented)

                Picker(LocalizedString.text("history_window"), selection: $selectedHistoryWindow) {
                    ForEach(OpsHistoryWindow.allCases) { window in
                        Text(window.title).tag(window)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 180)
            }

            HStack(spacing: 12) {
                Picker(LocalizedString.text("history_focus"), selection: $selectedHistoryFocusMode) {
                    ForEach(OpsHistoryFocusMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.menu)

                Picker(LocalizedString.text("history_scope"), selection: $selectedHistoryFocusID) {
                    ForEach(historyFocusOptions) { option in
                        Text(option.title).tag(option.id)
                    }
                }
                .pickerStyle(.menu)

                Spacer()

                if selectedHistoryFocusMode == .tool {
                    Button(LocalizedString.text("open_tool_detail")) {
                        openToolDetail(for: effectiveSelectedHistoryFocus.scopeValue)
                    }
                    .buttonStyle(.bordered)
                }

                if selectedHistoryFocusMode == .cron {
                    Button(LocalizedString.text("open_cron_detail")) {
                        openCronDetail(for: effectiveSelectedHistoryFocus.scopeValue)
                    }
                    .buttonStyle(.bordered)
                }

                Text(effectiveSelectedHistoryFocus.subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if visibleHistoricalSeries.isEmpty {
                Text(LocalizedString.text("project_history_after_sync"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16)], spacing: 16) {
                    ForEach(visibleHistoricalSeries) { series in
                        Button {
                            selectedHistoryMetric = series.metric
                        } label: {
                            historyMetricCard(series: series, isSelected: effectiveSelectedHistoryMetric == series.metric)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let series = selectedHistorySeries, !series.points.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(series.metric.windowDescription)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Chart {
                            ForEach(series.points) { point in
                                AreaMark(
                                    x: .value(LocalizedString.text("day_label"), point.date, unit: .day),
                                    y: .value(series.metric.title, point.value)
                                )
                                .interpolationMethod(.catmullRom)
                                .foregroundStyle(historyColor(for: series.metric).opacity(0.14))

                                LineMark(
                                    x: .value(LocalizedString.text("day_label"), point.date, unit: .day),
                                    y: .value(series.metric.title, point.value)
                                )
                                .interpolationMethod(.catmullRom)
                                .foregroundStyle(historyColor(for: series.metric))
                                .lineStyle(StrokeStyle(lineWidth: 2.5))

                                PointMark(
                                    x: .value(LocalizedString.text("day_label"), point.date, unit: .day),
                                    y: .value(series.metric.title, point.value)
                                )
                                .foregroundStyle(historyColor(for: series.metric))
                            }

                            if let selectedDate = effectiveSelectedHistoryDateOption,
                               let selectedPoint = series.points.first(where: {
                                   historyCalendar.isDate($0.date, inSameDayAs: selectedDate.date)
                               }) {
                                RuleMark(x: .value(LocalizedString.text("selected_day"), selectedDate.date, unit: .day))
                                    .foregroundStyle(historyColor(for: series.metric).opacity(0.35))
                                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))

                                PointMark(
                                    x: .value(LocalizedString.text("day_label"), selectedPoint.date, unit: .day),
                                    y: .value(series.metric.title, selectedPoint.value)
                                )
                                .symbolSize(110)
                                .foregroundStyle(historyColor(for: series.metric))
                            }
                        }
                        .chartYAxis {
                            AxisMarks(position: .leading)
                        }
                        .chartXSelection(value: historyChartDateSelectionBinding)
                        .frame(height: 260)

                        HStack(spacing: 16) {
                            historyStatPill(
                                title: LocalizedString.text("latest"),
                                value: series.latestPoint.map { series.metric.formattedValue($0.value) } ?? "-"
                            )
                            historyStatPill(
                                title: LocalizedString.text("previous"),
                                value: series.previousPoint.map { series.metric.formattedValue($0.value) } ?? "-"
                            )
                            historyStatPill(
                                title: LocalizedString.text("delta"),
                                value: OpsHistoryNarrativeBuilder.deltaText(for: series)
                            )
                        }

                        if let selectedDate = effectiveSelectedHistoryDateOption {
                            historyDayDrillDownSection(for: series, selectedDate: selectedDate)
                        }

                        opsHistoryContextSection(for: series)
                    }
                    .padding()
                    .background(Color(.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }

    private var opsAnomalyExplorerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(LocalizedString.text("anomaly_explorer"))
                        .font(.headline)
                    Text(LocalizedString.text("anomaly_explorer_desc"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text(LocalizedString.format("matching_count", filteredAnomalyRows.count))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 12) {
                Picker("Source", selection: $selectedAnomalySourceFilter) {
                    ForEach(OpsAnomalySourceFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.menu)

                Picker("Severity", selection: $selectedAnomalySeverityFilter) {
                    ForEach(OpsAnomalySeverityFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.menu)

                Picker("Window", selection: $selectedAnomalyTimeWindow) {
                    ForEach(OpsAnomalyTimeWindow.allCases) { window in
                        Text(window.title).tag(window)
                    }
                }
                .pickerStyle(.menu)

                Spacer()
            }

            TextField(LocalizedString.text("anomaly_search_placeholder"), text: $anomalySearchText)
                .textFieldStyle(.roundedBorder)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 16)], spacing: 16) {
                ForEach(anomalyExplorerCards) { card in
                    monitoringCard(
                        title: card.title,
                        value: card.value,
                        detail: card.detail,
                        color: card.color
                    )
                }
            }

            if !hotAnomalyClusters.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(LocalizedString.text("hot_clusters"))
                            .font(.headline)
                        Spacer()
                        Text(selectedAnomalyTimeWindow.detailText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    ForEach(hotAnomalyClusters) { cluster in
                        anomalyClusterButton(cluster)
                    }
                }
                .padding()
                .background(Color(.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            VStack(spacing: 8) {
                if filteredAnomalyRows.isEmpty {
                    Text(LocalizedString.text("no_anomalies_match_filters"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    HStack {
                        Text(LocalizedString.text("recent_matches"))
                            .font(.headline)
                        Spacer()
                        Text(LocalizedString.text("sorted_by_latest_occurrence"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 2)

                    ForEach(filteredAnomalyRows) { row in
                        anomalyRowButton(row)
                    }
                }
            }
            .padding()
            .background(Color(.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var opsCronReliabilitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(LocalizedString.text("cron_reliability"))
                            .font(.headline)
                    Text(LocalizedString.text("cron_reliability_desc"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if let latestRunAt = opsSnapshot.cronSummary?.latestRunAt {
                    Text(LocalizedString.format("latest_time", latestRunAt.formatted(date: .abbreviated, time: .shortened)))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if let summary = opsSnapshot.cronSummary {
                HStack(spacing: 16) {
                    monitoringCard(
                        title: LocalizedString.text("execution_success_rate"),
                        value: "\(Int(summary.successRate.rounded()))%",
                        detail: LocalizedString.format("success_detail", summary.successfulRuns, summary.failedRuns),
                        color: summary.successRate >= 90 ? .green : (summary.successRate >= 75 ? .orange : .red)
                    )
                    monitoringCard(
                        title: LocalizedString.text("failed_runs"),
                        value: "\(summary.failedRuns)",
                        detail: LocalizedString.text("last_14_days"),
                        color: summary.failedRuns == 0 ? .green : .red
                    )
                    monitoringCard(
                        title: LocalizedString.text("recent_runs"),
                        value: "\(opsSnapshot.cronRuns.count)",
                        detail: LocalizedString.text("showing_latest_ingested_executions"),
                        color: .blue
                    )
                }

                VStack(spacing: 8) {
                    ForEach(opsSnapshot.cronRuns) { row in
                        Button {
                            openCronDetail(for: row.cronName)
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Text(row.runAt.formatted(date: .omitted, time: .standard))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .frame(width: 72, alignment: .leading)

                                monitoringPill(
                                    title: row.statusText,
                                    color: row.statusText == "OK" ? .green : .red
                                )
                                .frame(width: 78, alignment: .leading)

                                Text(row.cronName)
                                    .font(.caption)
                                    .frame(width: 110, alignment: .leading)

                                Text(row.duration.map(formatOpsDuration) ?? "-")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .frame(width: 56, alignment: .leading)

                                Text(row.deliveryStatus ?? "-")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .frame(width: 76, alignment: .leading)

                                Text(row.summaryText)
                                    .font(.caption)
                                    .lineLimit(2)

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.4))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
                .background(Color(.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                Text(LocalizedString.text("no_external_cron_runs"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private var opsDailyActivitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LocalizedString.text("reliability_trend"))
                .font(.headline)

            if opsSnapshot.dailyActivity.isEmpty {
                Text(LocalizedString.text("no_historical_execution_activity"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                Chart {
                    ForEach(opsSnapshot.dailyActivity) { point in
                        BarMark(
                            x: .value(LocalizedString.text("day_label"), point.date, unit: .day),
                            y: .value(LocalizedString.text("completed_label"), point.completedCount)
                        )
                        .foregroundStyle(Color.green.gradient)

                        BarMark(
                            x: .value(LocalizedString.text("day_label"), point.date, unit: .day),
                            y: .value(LocalizedString.text("failed_label"), point.failedCount)
                        )
                        .foregroundStyle(Color.red.gradient)

                        LineMark(
                            x: .value(LocalizedString.text("day_label"), point.date, unit: .day),
                            y: .value(LocalizedString.text("errors_label"), point.errorCount)
                        )
                        .foregroundStyle(Color.orange)
                        .symbol(.circle)
                    }
                }
                .frame(height: 220)
                .padding()
                .background(Color(.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private var opsAgentHealthSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LocalizedString.text("agent_health"))
                .font(.headline)

            VStack(spacing: 8) {
                if opsSnapshot.agentRows.isEmpty {
                    Text(LocalizedString.text("no_agents_to_analyze"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(opsSnapshot.agentRows) { row in
                        HStack(spacing: 12) {
                            Text(row.agentName)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .frame(width: 140, alignment: .leading)

                            monitoringPill(title: row.stateText, color: opsColor(for: row.status))
                                .frame(width: 128, alignment: .leading)

                            Text(LocalizedString.format("done_count", row.completedCount))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 70, alignment: .leading)

                            Text(LocalizedString.format("fail_count", row.failedCount))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 64, alignment: .leading)

                            Text(row.averageDuration.map { LocalizedString.format("average_duration", formatOpsDuration($0)) } ?? LocalizedString.format("average_duration", "-"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 92, alignment: .leading)

                            Text(row.hasTrackedMemory ? LocalizedString.text("memory_tracked") : LocalizedString.text("memory_missing"))
                                .font(.caption)
                                .foregroundColor(row.hasTrackedMemory ? .secondary : .orange)
                                .frame(width: 110, alignment: .leading)

                            Text(row.lastActivityAt.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? LocalizedString.text("no_activity"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)

                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }
            .padding()
            .background(Color(.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var opsTraceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(LocalizedString.text("recent_traces"))
                        .font(.headline)
                    Text(LocalizedString.text("recent_traces_desc"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Picker(LocalizedString.text("trace_source"), selection: $selectedTraceSourceFilter) {
                    ForEach(OpsTraceSourceFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)

                Picker("Protocol", selection: $selectedProtocolTraceFilter) {
                    ForEach(OpsProtocolTraceFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.menu)
            }

            TextField(LocalizedString.text("trace_search_placeholder"), text: $traceSearchText)
                .textFieldStyle(.roundedBorder)

            if let drillDownSummary = activeProtocolDrillDownSummary {
                HStack {
                    Text("Protocol filter: \(drillDownSummary)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Clear") {
                        selectedProtocolTraceFilter = .all
                        selectedProtocolAgentFilter = nil
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.teal.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            VStack(spacing: 8) {
                if filteredTraceRows.isEmpty {
                    Text(traceSearchText.isEmpty ? LocalizedString.text("no_execution_traces_available") : LocalizedString.text("no_traces_match_search"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(filteredTraceRows) { row in
                        Button {
                            openTraceDetail(for: row)
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Text(row.startedAt.formatted(date: .omitted, time: .standard))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .frame(width: 72, alignment: .leading)

                                monitoringPill(title: row.sourceLabel, color: traceSourceColor(for: row.sourceLabel))
                                    .frame(width: 84, alignment: .leading)

                                monitoringPill(title: row.status.displayName, color: traceStatusColor(for: row.status))
                                    .frame(width: 92, alignment: .leading)

                                Text(row.agentName)
                                    .font(.caption)
                                    .frame(width: 112, alignment: .leading)

                                Text(row.duration.map(formatOpsDuration) ?? "-")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .frame(width: 56, alignment: .leading)

                                Text(row.routingAction?.uppercased() ?? row.outputType.rawValue)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .frame(width: 116, alignment: .leading)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(row.previewText)
                                        .font(.caption)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)

                                    if row.protocolRepairCount > 0 || row.protocolSafeDegradeApplied {
                                        HStack(spacing: 6) {
                                            if row.protocolRepairCount > 0 {
                                                monitoringPill(
                                                    title: "\(row.protocolRepairCount)x repair",
                                                    color: .orange
                                                )
                                            }
                                            if row.protocolSafeDegradeApplied {
                                                monitoringPill(title: "Safe Degrade", color: .teal)
                                            }
                                        }
                                    }
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.4))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
            .background(Color(.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var executionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LocalizedString.text("workflow_runtime"))
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                ProgressView(
                    value: Double(appState.openClawService.currentStep),
                    total: max(Double(appState.openClawService.totalSteps), 1)
                )
                .progressViewStyle(.linear)

                HStack(spacing: 8) {
                    monitoringPill(
                        title: executionProgressText,
                        color: appState.openClawService.isExecuting ? .orange : .green
                    )

                    if let executionState, executionState.isPaused {
                        monitoringPill(title: LocalizedString.text("paused"), color: .red)
                    }

                    if let lastUpdated = project?.runtimeState.lastUpdated {
                        monitoringPill(
                            title: LocalizedString.format("updated_at", lastUpdated.formatted(date: .omitted, time: .shortened)),
                            color: .secondary
                        )
                    }
                }

                if let workflow = project?.workflows.first {
                    Text(LocalizedString.format(
                        "workflow_runtime_summary",
                        workflow.nodes.filter { $0.type == .agent }.count,
                        workflow.edges.count,
                        workflow.boundaries.count
                    ))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color(.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var conversationMonitoringSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LocalizedString.text("conversation_monitoring"))
                .font(.headline)

            HStack(spacing: 16) {
                monitoringCard(
                    title: LocalizedString.text("conversation_total"),
                    value: "\(conversationTotalCount)",
                    detail: LocalizedString.text("workflow_message_total"),
                    color: .blue
                )
                monitoringCard(
                    title: LocalizedString.text("online_status"),
                    value: LocalizedString.format("active_idle_summary", activeAgentCount, idleAgentCount),
                    detail: LocalizedString.text("runtime_based_judgement"),
                    color: activeAgentCount > 0 ? .green : .secondary
                )
                monitoringCard(
                    title: LocalizedString.text("model_tokens"),
                    value: "\(totalTokenCount)",
                    detail: LocalizedString.format("model_token_estimate", modelTokenRows.count),
                    color: .purple
                )
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(LocalizedString.text("agent_activity_metrics"))
                    .font(.subheadline)
                    .fontWeight(.medium)

                if agentConversationRows.isEmpty {
                    Text(LocalizedString.text("no_monitorable_agents"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(agentConversationRows) { row in
                        HStack(spacing: 10) {
                            Text(row.agent.name)
                                .font(.subheadline)
                                .frame(width: 140, alignment: .leading)

                            monitoringPill(title: row.state.title, color: row.state.color)
                                .frame(width: 72, alignment: .leading)

                            Text(LocalizedString.format("spoken_count", row.outgoingCount))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 68, alignment: .leading)

                            Text(LocalizedString.format("received_count", row.incomingCount))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 68, alignment: .leading)

                            Text(LocalizedString.format("skill_count", row.skillCount))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 62, alignment: .leading)

                            Text(LocalizedString.format("file_count", row.fileCount))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 72, alignment: .leading)

                            Spacer()
                        }
                    }
                }
            }
            .padding()
            .background(Color(.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 10) {
                Text(LocalizedString.text("model_token_details"))
                    .font(.subheadline)
                    .fontWeight(.medium)

                if modelTokenRows.isEmpty {
                    Text(LocalizedString.text("no_token_usage"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(modelTokenRows) { row in
                        HStack {
                            Text(row.model)
                                .font(.caption)
                                .frame(width: 180, alignment: .leading)

                            Text(LocalizedString.format("input_count", row.inputTokens))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 86, alignment: .leading)

                            Text(LocalizedString.format("output_count", row.outputTokens))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 86, alignment: .leading)

                            Text(LocalizedString.format("total_count", row.totalTokens))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 84, alignment: .leading)

                            Spacer()
                        }
                    }
                }
            }
            .padding()
            .background(Color(.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var interventionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LocalizedString.text("intervention_actions"))
                .font(.headline)

            Text(appState.openClawAttachmentStatusDetail)
                .font(.footnote)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let runtimeSyncSummary = appState.openClawLatestRuntimeSyncSummary {
                Text("\(LocalizedString.text("openclaw_runtime_sync_status_label")): \(runtimeSyncSummary)")
                    .font(.footnote.weight(.medium))
                    .foregroundColor(openClawLatestSyncColor)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let runtimeSyncDetail = appState.openClawLatestRuntimeSyncDetail {
                Text(runtimeSyncDetail)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            runtimeSyncDiagnosticsSection

            HStack(spacing: 10) {
                Button(appState.openClawManager.isConnected ? LocalizedString.text("disconnect_openclaw") + " OpenClaw" : LocalizedString.text("connect_openclaw") + " OpenClaw") {
                    if appState.openClawManager.isConnected {
                        appState.disconnectOpenClaw()
                    } else {
                        appState.connectOpenClaw()
                    }
                }
                .buttonStyle(.borderedProminent)

                if let currentProject = appState.currentProject,
                   appState.openClawManager.canAttachProject,
                   appState.openClawManager.config.deploymentKind != .remoteServer,
                   (
                    !appState.openClawManager.hasAttachedProjectSession
                    || appState.openClawManager.attachedProjectID != currentProject.id
                   ) {
                    Button(LocalizedString.text("attach_current_project")) {
                        appState.attachCurrentProjectToOpenClaw()
                    }
                    .buttonStyle(.bordered)
                }

                if appState.openClawManager.canAttachProject,
                   appState.openClawManager.config.deploymentKind != .remoteServer,
                   appState.isCurrentProjectAttachedToOpenClaw {
                    Button("同步当前会话") {
                        appState.syncOpenClawActiveSession()
                    }
                    .buttonStyle(.bordered)
                }

                Button(LocalizedString.text("detect_connection")) {
                    appState.openClawService.checkConnection()
                }
                .buttonStyle(.bordered)

                Button(LocalizedString.text("pause_execution")) {
                    appState.openClawService.pauseExecution()
                }
                .buttonStyle(.bordered)
                .disabled(!appState.openClawService.isExecuting)

                Button(LocalizedString.text("resume_execution")) {
                    appState.openClawService.resumeExecution()
                }
                .buttonStyle(.bordered)
                .disabled(!(executionState?.canResume ?? false))

                Button(LocalizedString.text("rollback_checkpoint")) {
                    appState.openClawService.rollbackToLastCheckpoint()
                }
                .buttonStyle(.bordered)
                .disabled(executionState?.completedNodes.isEmpty ?? true)

                Button(LocalizedString.text("project_settings")) {
                    NotificationCenter.default.post(name: .openSettings, object: nil)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder
    private var runtimeSyncDiagnosticsSection: some View {
        if appState.hasOpenClawLatestRuntimeSyncDiagnostics {
            VStack(alignment: .leading, spacing: 8) {
                if let blockedReason = appState.openClawLatestRuntimeSyncBlockedReason {
                    runtimeSyncDiagnosticGroup(
                        title: LocalizedString.text("openclaw_runtime_sync_blocked_reason_label"),
                        items: [blockedReason],
                        color: openClawLatestSyncColor
                    )
                }

                if !appState.openClawLatestRuntimeSyncIssueLines.isEmpty {
                    runtimeSyncDiagnosticGroup(
                        title: LocalizedString.text("openclaw_runtime_sync_step_issues_label"),
                        items: appState.openClawLatestRuntimeSyncIssueLines,
                        color: appState.latestOpenClawRuntimeSyncReceipt?.status == .failed ? .red : .orange
                    )
                }

                if !appState.openClawLatestRuntimeSyncWarnings.isEmpty {
                    runtimeSyncDiagnosticGroup(
                        title: LocalizedString.text("openclaw_runtime_sync_warnings_label"),
                        items: appState.openClawLatestRuntimeSyncWarnings,
                        color: .orange
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func runtimeSyncDiagnosticGroup(title: String, items: [String], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(color)

            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 6) {
                    Circle()
                        .fill(color)
                        .frame(width: 5, height: 5)
                        .padding(.top, 5)
                    Text(item)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(10)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var taskSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LocalizedString.text("task_monitoring"))
                .font(.headline)

            VStack(spacing: 10) {
                ForEach(recentTasks) { task in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(task.title)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text(task.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }

                        Spacer()

                        monitoringPill(title: task.status.displayName, color: task.status.color)

                        Button(LocalizedString.text("mark_in_progress")) {
                            appState.taskManager.moveTask(task.id, to: .inProgress)
                        }
                        .buttonStyle(.borderless)

                        Button(LocalizedString.text("mark_done")) {
                            appState.taskManager.moveTask(task.id, to: .done)
                        }
                        .buttonStyle(.borderless)

                        Button(LocalizedString.text("mark_blocked")) {
                            appState.taskManager.moveTask(task.id, to: .blocked)
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(10)
                    .background(Color(.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
    }

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LocalizedString.text("recent_execution_results"))
                .font(.headline)

            VStack(spacing: 8) {
                if appState.openClawService.executionResults.isEmpty {
                    Text(LocalizedString.text("no_execution_results"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(appState.openClawService.executionResults.suffix(6).reversed()) { result in
                        HStack {
                            Text(result.status.rawValue)
                                .font(.caption)
                                .foregroundColor(result.status == .completed ? .green : .red)
                                .frame(width: 80, alignment: .leading)
                            Text(result.summaryText.isEmpty ? LocalizedString.text("no_output") : result.summaryText)
                                .font(.caption)
                                .lineLimit(2)
                            Spacer()
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .padding()
            .background(Color(.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var logsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(LocalizedString.text("realtime_logs"))
                    .font(.headline)
                Spacer()
                Button(LocalizedString.text("clear_logs")) {
                    appState.openClawService.clearLogs()
                }
                .buttonStyle(.borderless)
            }

            VStack(spacing: 6) {
                if appState.openClawService.executionLogs.isEmpty {
                    Text(LocalizedString.text("no_logs"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(appState.openClawService.executionLogs.suffix(30).reversed()) { entry in
                        HStack(alignment: .top, spacing: 8) {
                            Text(entry.timestamp.formatted(date: .omitted, time: .standard))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .frame(width: 72, alignment: .leading)
                            Text(entry.level.rawValue)
                                .font(.caption2)
                                .foregroundColor(logColor(for: entry.level))
                                .frame(width: 56, alignment: .leading)
                            if let routingBadge = entry.routingBadge {
                                Text(routingBadge)
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(routingColor(for: entry).opacity(0.14))
                                    .foregroundColor(routingColor(for: entry))
                                    .clipShape(Capsule())
                            }
                            Text(entry.message)
                                .font(.caption)
                                .foregroundColor(entry.isRoutingEvent ? routingColor(for: entry) : .primary)
                                .lineLimit(2)
                            Spacer()
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(entry.isRoutingEvent ? routingColor(for: entry).opacity(0.06) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }
            .padding()
            .background(Color(.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var executionProgressText: String {
        let totalSteps = appState.openClawService.totalSteps
        let currentStep = appState.openClawService.currentStep
        guard totalSteps > 0 else { return LocalizedString.text("not_started") }
        return LocalizedString.format("step_progress", currentStep, totalSteps)
    }

    private func monitoringCard(title: String, value: String, detail: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(color)
            Text(detail)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func historyMetricCard(series: OpsMetricHistorySeries, isSelected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(series.metric.title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Circle()
                    .fill(historyColor(for: series.metric))
                    .frame(width: 8, height: 8)
            }

            Text(series.latestPoint.map { series.metric.formattedValue($0.value) } ?? "No data")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(isSelected ? historyColor(for: series.metric) : .primary)

            Text(OpsHistoryNarrativeBuilder.deltaText(for: series))
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.controlBackgroundColor))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? historyColor(for: series.metric) : Color.clear, lineWidth: 2)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func historyStatPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func monitoringPill(title: String, color: Color) -> some View {
        Text(title)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .foregroundColor(color)
            .clipShape(Capsule())
    }

    private var anomalyExplorerCards: [OpsContextCard] {
        OpsAnomalyInsightBuilder.explorerCards(
            rows: filteredAnomalyRows,
            clusters: anomalyClusters,
            timeWindowDetail: selectedAnomalyTimeWindow.detailText
        )
    }

    private func historyFocusOptions(for mode: OpsHistoryFocusMode) -> [OpsHistoryFocusOption] {
        switch mode {
        case .project:
            return [
                OpsHistoryFocusOption(
                    id: "project",
                    title: project?.name ?? "Project",
                    subtitle: "Project-wide context",
                    matchKey: project?.name.lowercased() ?? "project",
                    scopeValue: "project"
                )
            ]
        case .agent:
            let uniqueAgents = Array(
                Dictionary(
                    uniqueKeysWithValues: opsSnapshot.agentRows.map {
                        ($0.agentName.lowercased(), OpsHistoryFocusOption(
                            id: "agent:\($0.agentName.lowercased())",
                            title: $0.agentName,
                            subtitle: $0.stateText,
                            matchKey: $0.agentName.lowercased(),
                            scopeValue: $0.id.uuidString
                        ))
                    }
                ).values
            )
            return uniqueAgents.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .tool:
            let identifiers = Set(
                opsSnapshot.anomalyRows.compactMap { row -> String? in
                    guard row.sourceLabel == "Tool" else { return nil }
                    return (row.sourceService ?? row.title).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                .filter { !$0.isEmpty }
            )

            return identifiers.sorted().map { identifier in
                OpsHistoryFocusOption(
                    id: "tool:\(identifier.lowercased())",
                    title: historyFocusDisplayName(forToolIdentifier: identifier),
                    subtitle: "Tool-service scoped context",
                    matchKey: identifier.lowercased(),
                    scopeValue: identifier.lowercased()
                )
            }
        case .cron:
            let identifiers = Set(
                opsSnapshot.cronRuns.map(\.cronName) +
                opsSnapshot.anomalyRows.filter { $0.sourceLabel == "Cron" }.map(\.title)
            )

            return identifiers.sorted().map { identifier in
                OpsHistoryFocusOption(
                    id: "cron:\(identifier.lowercased())",
                    title: identifier,
                    subtitle: "Scheduled run scoped context",
                    matchKey: identifier.lowercased(),
                    scopeValue: identifier.lowercased()
                )
            }
        }
    }

    private func reloadScopedHistorySeries() {
        guard let projectID = project?.id else {
            scopedHistoricalSeries = []
            return
        }

        guard selectedHistoryFocusMode != .project else {
            scopedHistoricalSeries = []
            return
        }

        let focus = effectiveSelectedHistoryFocus
        scopedHistoricalSeries = appState.opsAnalytics.scopedHistorySeries(
            projectID: projectID,
            days: 30,
            scopeKind: selectedHistoryFocusMode.rawValue,
            scopeValue: focus.scopeValue,
            scopeMatchKey: focus.matchKey
        )
    }

    private func historyFocusDisplayName(forToolIdentifier identifier: String) -> String {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return LocalizedString.text("tool_category") }

        if let lastComponent = trimmed.split(separator: ".").last {
            return String(lastComponent)
        }
        return trimmed
    }

    private func opsHistoryContextSection(for series: OpsMetricHistorySeries) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(LocalizedString.text("metric_lens"))
                    .font(.headline)
                Text(LocalizedString.format("scope_format", effectiveSelectedHistoryFocus.title))
                    .font(.caption.weight(.medium))
                    .foregroundColor(historyColor(for: series.metric))
                Text(
                    OpsHistoryNarrativeBuilder.narrative(
                        for: series,
                        focusText: selectedHistoryFocusMode == .project
                            ? LocalizedString.text("project_wide")
                            : effectiveSelectedHistoryFocus.title
                    )
                )
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 16)], spacing: 16) {
                ForEach(historyContextCards(for: series.metric)) { card in
                    monitoringCard(
                        title: card.title,
                        value: card.value,
                        detail: card.detail,
                        color: card.color
                    )
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(LocalizedString.text("related_signals"))
                    .font(.headline)

                let rows = historySignalRows(for: series.metric)
                if rows.isEmpty {
                    Text(LocalizedString.text("no_supporting_signals"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(rows) { row in
                        historySignalRowView(row)
                    }
                }
            }
            .padding()
            .background(Color.white.opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(.top, 6)
    }

    private func historyDateID(for date: Date) -> String {
        String(Int(date.timeIntervalSinceReferenceDate))
    }

    private func normalizeHistoryDateSelection() {
        if !historyDateOptions.contains(where: { $0.id == selectedHistoryDateID }) {
            selectedHistoryDateID = historyDateOptions.first?.id ?? ""
        }
    }

    private func nearestHistoryDateOption(to date: Date) -> OpsHistoryDateOption? {
        historyDateOptions.min { lhs, rhs in
            abs(lhs.date.timeIntervalSince(date)) < abs(rhs.date.timeIntervalSince(date))
        }
    }

    private var historyDateSelectionBinding: Binding<String> {
        Binding(
            get: { effectiveSelectedHistoryDateOption?.id ?? selectedHistoryDateID },
            set: { selectedHistoryDateID = $0 }
        )
    }

    private var historyChartDateSelectionBinding: Binding<Date?> {
        Binding(
            get: { effectiveSelectedHistoryDateOption?.date },
            set: { newValue in
                guard let newValue,
                      let nearestOption = nearestHistoryDateOption(to: newValue) else {
                    return
                }

                selectedHistoryDateID = nearestOption.id
            }
        )
    }

    private func historyDayDrillDownSection(
        for series: OpsMetricHistorySeries,
        selectedDate: OpsHistoryDateOption
    ) -> some View {
        let dayRows = historyDayDrillDownRows(for: series.metric, date: selectedDate.date)
        let selectedPoint = series.points.first { historyCalendar.isDate($0.date, inSameDayAs: selectedDate.date) }

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(LocalizedString.text("day_drill_down"))
                        .font(.headline)
                    Text(LocalizedString.text("day_drill_down_desc"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Picker(LocalizedString.text("sample_day"), selection: historyDateSelectionBinding) {
                    ForEach(historyDateOptions) { option in
                        Text(option.title).tag(option.id)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 180)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 16)], spacing: 16) {
                ForEach(historyDaySummaryCards(for: series.metric, point: selectedPoint, rows: dayRows, selectedDate: selectedDate.date)) { card in
                    monitoringCard(
                        title: card.title,
                        value: card.value,
                        detail: card.detail,
                        color: card.color
                    )
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(LocalizedString.format("signals_on", selectedDate.title))
                    .font(.headline)

                if dayRows.isEmpty {
                    Text(LocalizedString.text("no_related_signals_for_day"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(dayRows) { row in
                        historySignalRowView(row)
                    }
                }
            }
            .padding()
            .background(Color.white.opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(.top, 4)
    }

    private func historyDaySummaryCards(
        for metric: OpsHistoryMetric,
        point: OpsMetricHistoryPoint?,
        rows: [OpsHistorySignalRow],
        selectedDate: Date
    ) -> [OpsContextCard] {
        OpsHistoryInsightBuilder.daySummaryCards(
            metric: metric,
            point: point,
            rows: rows,
            selectedDate: selectedDate
        )
    }

    private func historyContextCards(for metric: OpsHistoryMetric) -> [OpsContextCard] {
        let focusedTraceRows = opsSnapshot.traceRows.filter(matchesHistoryFocus)
        let focusedAnomalyRows = opsSnapshot.anomalyRows.filter(matchesHistoryFocus)
        let focusedAgentRows = opsSnapshot.agentRows.filter(matchesHistoryFocus)
        let focusedCronRuns = opsSnapshot.cronRuns.filter(matchesHistoryFocus)
        return OpsHistoryInsightBuilder.contextCards(
            metric: metric,
            focusTitle: effectiveSelectedHistoryFocus.title,
            totalAgents: opsSnapshot.totalAgents,
            traceRows: focusedTraceRows,
            anomalyRows: focusedAnomalyRows,
            agentRows: focusedAgentRows,
            cronRuns: focusedCronRuns
        )
    }

    private func historySignalRows(for metric: OpsHistoryMetric) -> [OpsHistorySignalRow] {
        Array(historySignalPool(for: metric).prefix(6))
    }

    private func historyDayDrillDownRows(for metric: OpsHistoryMetric, date: Date) -> [OpsHistorySignalRow] {
        historySignalPool(for: metric)
            .filter { row in
                guard let occurredAt = row.occurredAt else { return false }
                return historyCalendar.isDate(occurredAt, inSameDayAs: date)
            }
            .prefix(8)
            .map { $0 }
    }

    private func historySignalPool(for metric: OpsHistoryMetric) -> [OpsHistorySignalRow] {
        let focusedAnomalyRows = opsSnapshot.anomalyRows.filter(matchesHistoryFocus)
        let focusedTraceRows = opsSnapshot.traceRows.filter(matchesHistoryFocus)
        let focusedAgentRows = opsSnapshot.agentRows.filter(matchesHistoryFocus)
        let focusedCronRuns = opsSnapshot.cronRuns.filter(matchesHistoryFocus)
        return OpsHistoryInsightBuilder.signalRows(
            metric: metric,
            anomalyRows: focusedAnomalyRows,
            traceRows: focusedTraceRows,
            agentRows: focusedAgentRows,
            cronRuns: focusedCronRuns
        )
    }

    private func historySignalRowView(_ row: OpsHistorySignalRow) -> some View {
        Group {
            if row.anomaly != nil || row.trace != nil || row.cronRun != nil {
                Button {
                    openHistorySignal(row)
                } label: {
                    historySignalRowContent(row)
                }
                .buttonStyle(.plain)
            } else {
                historySignalRowContent(row)
            }
        }
    }

    private func historySignalRowContent(_ row: OpsHistorySignalRow) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(row.occurredAt?.formatted(date: .omitted, time: .standard) ?? "-")
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(width: 72, alignment: .leading)

            monitoringPill(title: row.badge, color: row.color)
                .frame(width: 92, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(row.title)
                    .font(.caption.weight(.medium))
                Text(row.detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            if row.anomaly != nil || row.trace != nil || row.cronRun != nil {
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func openHistorySignal(_ row: OpsHistorySignalRow) {
        if let cronRun = row.cronRun {
            openCronDetail(for: cronRun.cronName)
            return
        }
        if let anomaly = row.anomaly {
            openAnomalyDetail(for: anomaly)
            return
        }
        if let trace = row.trace {
            openTraceDetail(for: trace)
        }
    }

    private func protocolAgentProfileButton(_ profile: OpsProtocolAgentProfile) -> some View {
        Button {
            applyProtocolAgentDrillDown(profile)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(profile.agentName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.primary)

                        monitoringPill(
                            title: "Risk \(profile.riskScore)",
                            color: profile.hardInterruptCount > 0 ? .red : .orange
                        )
                    }

                    HStack(spacing: 6) {
                        if profile.repairedTraceCount > 0 {
                            monitoringPill(title: "Repair \(profile.repairedTraceCount)", color: .orange)
                        }
                        if profile.safeDegradeCount > 0 {
                            monitoringPill(title: "Safe \(profile.safeDegradeCount)", color: .teal)
                        }
                        if profile.hardInterruptCount > 0 {
                            monitoringPill(title: "Interrupt \(profile.hardInterruptCount)", color: .red)
                        }
                    }

                    Text(
                        [
                            "Runtime traces \(profile.totalTraceCount)",
                            profile.dominantRepairLabel.map { "Dominant \($0)" },
                            "Latest \(profile.latestActivityAt.formatted(date: .abbreviated, time: .shortened))"
                        ]
                        .compactMap { $0 }
                        .joined(separator: " • ")
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
                }

                Spacer()

                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func applyProtocolDrillDown(for card: OpsGoalCard) {
        switch card.id {
        case "protocol_conformance":
            applyProtocolTraceFilter(.repaired)
        case "protocol_auto_repair":
            applyProtocolTraceFilter(.repaired)
        case "protocol_safe_degrade":
            applyProtocolTraceFilter(.safeDegrade)
        case "protocol_interrupts":
            applyProtocolTraceFilter(.hardInterrupt)
        default:
            applyProtocolTraceFilter(.all)
        }
    }

    private func applyProtocolTraceFilter(_ filter: OpsProtocolTraceFilter) {
        selectedProtocolTraceFilter = filter
        selectedProtocolAgentFilter = nil
        if filter != .all {
            selectedTraceSourceFilter = .runtime
        }
    }

    private func applyProtocolAgentDrillDown(_ profile: OpsProtocolAgentProfile) {
        applyProtocolTraceFilter(profile.recommendedFilter)
        selectedProtocolAgentFilter = profile.agentName
        selectedHistoryFocusMode = .agent
        selectedHistoryMetric = profile.hardInterruptCount > 0 ? .protocolHardInterrupts : .protocolAutoRepair

        let focusID = "agent:\(profile.agentName.lowercased())"
        if historyFocusOptions(for: .agent).contains(where: { $0.id == focusID }) {
            selectedHistoryFocusID = focusID
        }
    }

    private func anomalyRowButton(_ row: OpsAnomalyRow) -> some View {
        Button {
            openAnomalyDetail(for: row)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Text(row.occurredAt.formatted(date: .omitted, time: .standard))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(width: 72, alignment: .leading)

                monitoringPill(title: row.sourceLabel, color: anomalySourceColor(for: row.sourceLabel))
                    .frame(width: 84, alignment: .leading)

                monitoringPill(title: row.status == .critical ? LocalizedString.text("critical_label") : LocalizedString.text("warning_label"), color: opsColor(for: row.status))
                    .frame(width: 74, alignment: .leading)

                Text(row.title)
                    .font(.caption)
                    .frame(width: 128, alignment: .leading)

                Text(row.detailText)
                    .font(.caption)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Spacer()

                Image(systemName: row.linkedSpanID == nil ? "doc.text.magnifyingglass" : "point.topleft.down.curvedto.point.bottomright.up")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func matchesHistoryFocus(_ row: OpsAnomalyRow) -> Bool {
        OpsHistoryScopeMatcher.matches(
            row,
            kind: historyScopeMatcherKind,
            matchKey: effectiveSelectedHistoryFocus.matchKey
        )
    }

    private func matchesHistoryFocus(_ row: OpsTraceSummaryRow) -> Bool {
        OpsHistoryScopeMatcher.matches(
            row,
            kind: historyScopeMatcherKind,
            matchKey: effectiveSelectedHistoryFocus.matchKey
        )
    }

    private func matchesHistoryFocus(_ row: OpsAgentHealthRow) -> Bool {
        OpsHistoryScopeMatcher.matches(
            row,
            kind: historyScopeMatcherKind,
            matchKey: effectiveSelectedHistoryFocus.matchKey
        )
    }

    private func matchesHistoryFocus(_ row: OpsCronRunRow) -> Bool {
        OpsHistoryScopeMatcher.matches(
            row,
            kind: historyScopeMatcherKind,
            matchKey: effectiveSelectedHistoryFocus.matchKey
        )
    }

    private func anomalyClusterButton(_ cluster: OpsAnomalyCluster) -> some View {
        Button {
            openAnomalyDetail(for: cluster.latestAnomaly)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Text(cluster.latestOccurredAt.formatted(date: .omitted, time: .standard))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(width: 72, alignment: .leading)

                monitoringPill(title: cluster.sourceLabel, color: anomalySourceColor(for: cluster.sourceLabel))
                    .frame(width: 84, alignment: .leading)

                monitoringPill(title: cluster.status == .critical ? LocalizedString.text("critical_label") : LocalizedString.text("warning_label"), color: opsColor(for: cluster.status))
                    .frame(width: 74, alignment: .leading)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(cluster.title)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)

                        Text("\(cluster.occurrenceCount)x")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(opsColor(for: cluster.status).opacity(0.12))
                            .foregroundColor(opsColor(for: cluster.status))
                            .clipShape(Capsule())
                    }

                    Text(cluster.sampleDetail)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)

                    HStack(spacing: 10) {
                        Text(cluster.sourceService ?? cluster.sourceLabel)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(
                            OpsAnomalyClusterInsightBuilder.trendText(
                                occurrenceCount: cluster.occurrenceCount,
                                recent24HourCount: cluster.recent24HourCount,
                                includeEarlierBreakdown: selectedAnomalyTimeWindow != .last24Hours
                            )
                        )
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(LocalizedString.format("first_time", cluster.firstOccurredAt.formatted(date: .abbreviated, time: .shortened)))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        if cluster.linkedTraceCount > 0 {
                            Text(LocalizedString.format("trace_linked_count", cluster.linkedTraceCount))
                                .font(.caption2)
                                .foregroundColor(.teal)
                        }
                    }
                }

                Spacer()

                Image(systemName: cluster.latestAnomaly.linkedSpanID == nil ? "chevron.right.circle" : "arrowshape.turn.up.right.circle")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func logColor(for level: ExecutionLogEntry.LogLevel) -> Color {
        switch level {
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        case .success: return .green
        }
    }

    private func routingColor(for entry: ExecutionLogEntry) -> Color {
        switch entry.routingBadge {
        case "STOP": return .orange
        case "WARN", "MISS": return .red
        case "QUEUE": return .blue
        case "ROUTE": return .purple
        default: return logColor(for: entry.level)
        }
    }

    private func opsColor(for status: OpsHealthStatus) -> Color {
        switch status {
        case .healthy: return .green
        case .warning: return .orange
        case .critical: return .red
        case .neutral: return .secondary
        }
    }

    private func historyColor(for metric: OpsHistoryMetric) -> Color {
        switch metric {
        case .workflowReliability: return .green
        case .agentEngagement: return .blue
        case .memoryDiscipline: return .orange
        case .errorBudget: return .red
        case .cronReliability: return .teal
        case .protocolConformance: return .green
        case .protocolAutoRepair: return .orange
        case .protocolSafeDegrade: return .teal
        case .protocolHardInterrupts: return .red
        }
    }

    private func traceSourceColor(for sourceLabel: String) -> Color {
        sourceLabel == "OpenClaw" ? .teal : .blue
    }

    private func anomalySourceColor(for sourceLabel: String) -> Color {
        switch sourceLabel {
        case "Cron":
            return .red
        case "Tool":
            return .teal
        case "OpenClaw":
            return .orange
        default:
            return .blue
        }
    }

    private func traceStatusColor(for status: ExecutionStatus) -> Color {
        switch status {
        case .completed: return .green
        case .failed: return .red
        case .running: return .orange
        case .waiting: return .blue
        case .idle: return .secondary
        }
    }

    private func formatOpsDuration(_ duration: TimeInterval) -> String {
        if duration >= 60 {
            let minutes = Int(duration) / 60
            let seconds = Int(duration) % 60
            return "\(minutes)m \(seconds)s"
        }
        return String(format: "%.1fs", duration)
    }

    private func openTraceDetail(for row: OpsTraceSummaryRow) {
        guard let projectID = project?.id else { return }
        selectedCronPanel = nil
        selectedToolPanel = nil

        if let detail = appState.opsAnalytics.traceDetail(projectID: projectID, traceID: row.id) {
            selectedTracePanel = makeOpsTracePanelModel(
                detail: detail,
                project: project,
                executionLogs: appState.openClawService.executionLogs
            )
            return
        }

        let fallbackDetail = OpsTraceDetail(
            id: row.id,
            traceID: row.id.uuidString.replacingOccurrences(of: "-", with: ""),
            parentSpanID: nil,
            spanName: row.agentName,
            service: row.sourceLabel == "OpenClaw" ? "openclaw.external-session" : "multi-agent-flow.execution",
            statusText: row.status == .failed ? "error" : "ok",
            agentName: row.agentName,
            executionStatus: row.status,
            outputType: row.outputType,
            routingAction: row.routingAction,
            routingReason: nil,
            routingTargets: [],
            nodeID: nil,
            startedAt: row.startedAt,
            completedAt: row.duration.map { row.startedAt.addingTimeInterval($0) },
            duration: row.duration,
            previewText: row.previewText,
            outputText: row.previewText,
            attributes: [:],
            eventsText: nil,
            relatedSpans: []
        )
        selectedTracePanel = makeOpsTracePanelModel(
            detail: fallbackDetail,
            project: project,
            executionLogs: appState.openClawService.executionLogs
        )
    }

    private func openAnomalyDetail(for row: OpsAnomalyRow) {
        selectedTracePanel = nil
        selectedCronPanel = nil
        selectedToolPanel = nil

        if let projectID = project?.id,
           let spanID = row.linkedSpanID,
           let detail = appState.opsAnalytics.traceDetail(projectID: projectID, traceID: spanID) {
            selectedAnomalyPanel = nil
            selectedTracePanel = makeOpsTracePanelModel(
                detail: detail,
                project: project,
                executionLogs: appState.openClawService.executionLogs
            )
            return
        }

        selectedAnomalyPanel = OpsAnomalyPanelModel(row: row)
    }

    private func openCronDetail(for cronName: String) {
        guard let projectID = project?.id else { return }

        selectedTracePanel = nil
        selectedAnomalyPanel = nil
        selectedToolPanel = nil

        if let detail = appState.opsAnalytics.cronDetail(
            projectID: projectID,
            cronName: cronName,
            days: 30,
            runLimit: 24,
            anomalyLimit: 12
        ) {
            selectedCronPanel = OpsCronPanelModel(projectID: projectID, detail: detail)
            return
        }

        let normalizedCronName = cronName.lowercased()
        let fallbackRuns = opsSnapshot.cronRuns.filter { $0.cronName.lowercased() == normalizedCronName }
        let fallbackAnomalies = opsSnapshot.anomalyRows.filter {
            $0.sourceLabel == "Cron" && $0.title.lowercased() == normalizedCronName
        }
        let fallbackHistory = appState.opsAnalytics.scopedHistorySeries(
            projectID: projectID,
            days: 30,
            scopeKind: "cron",
            scopeValue: cronName,
            scopeMatchKey: normalizedCronName
        )
        let successfulRuns = fallbackRuns.filter { $0.statusText == "OK" }.count
        let failedRuns = max(fallbackRuns.count - successfulRuns, 0)
        let fallbackSummary: OpsCronReliabilitySummary? = fallbackRuns.isEmpty ? nil : OpsCronReliabilitySummary(
            successRate: Double(successfulRuns) / Double(fallbackRuns.count) * 100,
            successfulRuns: successfulRuns,
            failedRuns: failedRuns,
            latestRunAt: fallbackRuns.map(\.runAt).max()
        )
        let hasHistory = fallbackHistory.contains { !$0.points.isEmpty }

        guard fallbackSummary != nil || !fallbackRuns.isEmpty || !fallbackAnomalies.isEmpty || hasHistory else {
            return
        }

        selectedCronPanel = OpsCronPanelModel(
            projectID: projectID,
            detail: OpsCronDetail(
                cronName: cronName,
                summary: fallbackSummary,
                historySeries: fallbackHistory,
                runs: fallbackRuns,
                anomalies: fallbackAnomalies
            )
        )
    }

    private func openToolDetail(for toolIdentifier: String) {
        guard let projectID = project?.id else { return }

        selectedTracePanel = nil
        selectedAnomalyPanel = nil
        selectedCronPanel = nil

        if let detail = appState.opsAnalytics.toolDetail(
            projectID: projectID,
            toolIdentifier: toolIdentifier,
            days: 30,
            spanLimit: 24,
            anomalyLimit: 12
        ) {
            selectedToolPanel = OpsToolPanelModel(projectID: projectID, detail: detail)
            return
        }

        let normalizedToolIdentifier = toolIdentifier.lowercased()
        let fallbackHistory = appState.opsAnalytics.scopedHistorySeries(
            projectID: projectID,
            days: 30,
            scopeKind: "tool",
            scopeValue: normalizedToolIdentifier,
            scopeMatchKey: normalizedToolIdentifier
        )
        let fallbackAnomalies = opsSnapshot.anomalyRows.filter { row in
            guard row.sourceLabel == "Tool" else { return false }
            return [row.title, row.detailText, row.fullDetailText, row.sourceService ?? ""]
                .joined(separator: " ")
                .lowercased()
                .contains(normalizedToolIdentifier)
        }
        let hasHistory = fallbackHistory.contains { !$0.points.isEmpty }

        guard !fallbackAnomalies.isEmpty || hasHistory else { return }

        selectedToolPanel = OpsToolPanelModel(
            projectID: projectID,
            detail: OpsToolDetail(
                toolIdentifier: toolIdentifier,
                historySeries: fallbackHistory,
                spans: [],
                anomalies: fallbackAnomalies
            )
        )
    }

    private func scheduleMetricsRefresh(immediately: Bool) {
        pendingMetricsRefreshWorkItem?.cancel()

        let signature = dashboardRefreshSignature
        let projectSnapshot = project
        let tasksSnapshot = appState.taskManager.tasks
        let messagesSnapshot = appState.messageManager.messages
        let activeAgentsSnapshot = appState.openClawManager.activeAgents
        let isConnected = appState.openClawManager.canRunWorkflow
        let fileRootsByAgent = buildFileRootsByAgent(project: projectSnapshot, tasks: tasksSnapshot)
        let unknownModelLabel = LocalizedString.text("unknown_model")

        let workItem = DispatchWorkItem {
            DispatchQueue.global(qos: .utility).async {
                let refreshedMetrics = DashboardMetrics.build(
                    project: projectSnapshot,
                    tasks: tasksSnapshot,
                    messages: messagesSnapshot,
                    activeAgents: activeAgentsSnapshot,
                    isConnected: isConnected,
                    fileRootsByAgent: fileRootsByAgent,
                    unknownModelLabel: unknownModelLabel
                )

                DispatchQueue.main.async {
                    guard dashboardRefreshSignature == signature else {
                        scheduleMetricsRefresh(immediately: false)
                        return
                    }
                    metrics = refreshedMetrics
                }
            }
        }

        pendingMetricsRefreshWorkItem = workItem
        let delay = immediately ? 0 : metricsRefreshDebounce
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func buildFileRootsByAgent(project: MAProject?, tasks: [Task]) -> [UUID: [URL]] {
        guard let project else { return [:] }

        var rootsByAgent: [UUID: [URL]] = [:]

        var managedWorkspaceByAgentID: [UUID: URL] = [:]
        for workflow in project.workflows {
            for node in workflow.nodes where node.type == .agent {
                guard let agentID = node.agentID, managedWorkspaceByAgentID[agentID] == nil else { continue }
                managedWorkspaceByAgentID[agentID] = ProjectFileSystem.shared.nodeOpenClawWorkspaceDirectory(
                    for: node.id,
                    workflowID: workflow.id,
                    projectID: project.id,
                    under: ProjectManager.shared.appSupportRootDirectory
                )
            }
        }

        for agent in project.agents {
            if let managedWorkspaceURL = managedWorkspaceByAgentID[agent.id] {
                rootsByAgent[agent.id, default: []].append(managedWorkspaceURL)
                continue
            }

            if let workspacePath = OpenClawManager.shared.resolvedWorkspacePath(for: agent)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !workspacePath.isEmpty {
                rootsByAgent[agent.id, default: []].append(URL(fileURLWithPath: workspacePath, isDirectory: true))
                continue
            }

            if let memoryPath = agent.openClawDefinition.memoryBackupPath?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !memoryPath.isEmpty {
                let privateURL = URL(fileURLWithPath: memoryPath, isDirectory: true)
                let rootURL = privateURL.lastPathComponent == "private"
                    ? privateURL.deletingLastPathComponent()
                    : privateURL
                rootsByAgent[agent.id, default: []].append(rootURL)
            }
        }

        for task in tasks {
            guard let agentID = task.assignedAgentID,
                  let workspaceURL = appState.absoluteWorkspaceURL(for: task.id) else {
                continue
            }
            rootsByAgent[agentID, default: []].append(workspaceURL)
        }

        return rootsByAgent.mapValues { roots in
            Array(Dictionary(uniqueKeysWithValues: roots.map { ($0.standardizedFileURL.path, $0) }).values)
        }
    }
}

private struct OpsTracePanelModel: Identifiable {
    let detail: OpsTraceDetail
    let relatedLogs: [ExecutionLogEntry]
    let workflowPath: OpsTraceWorkflowPath?

    var id: UUID { detail.id }
}

private struct OpsAnomalyPanelModel: Identifiable {
    let row: OpsAnomalyRow

    var id: String { row.id }
}

private struct OpsCronPanelModel: Identifiable {
    let projectID: UUID
    let detail: OpsCronDetail

    var id: String { "\(projectID.uuidString)::\(detail.cronName.lowercased())" }
}

private struct OpsToolPanelModel: Identifiable {
    let projectID: UUID
    let detail: OpsToolDetail

    var id: String { "\(projectID.uuidString)::\(detail.toolIdentifier.lowercased())" }
}

enum OpsAccentTone {
    case secondary
    case green
    case red
    case orange
    case teal
    case blue

    var color: Color {
        switch self {
        case .secondary:
            return .secondary
        case .green:
            return .green
        case .red:
            return .red
        case .orange:
            return .orange
        case .teal:
            return .teal
        case .blue:
            return .blue
        }
    }
}

struct OpsContextCard: Identifiable {
    let id: String
    let title: String
    let value: String
    let detail: String
    let tone: OpsAccentTone

    var color: Color { tone.color }
}

private struct OpsHistoryFocusOption: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let matchKey: String
    let scopeValue: String
}

private struct OpsHistoryDateOption: Identifiable, Hashable {
    let id: String
    let date: Date
    let title: String
}

struct OpsHistorySignalRow: Identifiable {
    let id: String
    let title: String
    let badge: String
    let detail: String
    let occurredAt: Date?
    let tone: OpsAccentTone
    let anomaly: OpsAnomalyRow?
    let trace: OpsTraceSummaryRow?
    let cronRun: OpsCronRunRow?

    var color: Color { tone.color }
}

struct OpsAnomalyCluster: Identifiable {
    let id: String
    let title: String
    let sourceLabel: String
    let sourceService: String?
    let sampleDetail: String
    let latestOccurredAt: Date
    let firstOccurredAt: Date
    let status: OpsHealthStatus
    let occurrenceCount: Int
    let recent24HourCount: Int
    let linkedTraceCount: Int
    let latestAnomaly: OpsAnomalyRow
}

private struct OpsTraceWorkflowPath {
    let upstreamNodes: [OpsTraceWorkflowPathNode]
    let currentNode: OpsTraceWorkflowPathNode
    let downstreamNodes: [OpsTraceWorkflowPathNode]
}

private struct OpsTraceWorkflowPathNode: Identifiable {
    enum Role: Equatable {
        case upstream
        case current
        case downstream
    }

    enum State: Equatable {
        case normal
        case selected
        case skipped
    }

    let id: UUID
    let title: String
    let subtitle: String
    let role: Role
    let state: State
}

private func makeOpsTracePanelModel(
    detail: OpsTraceDetail,
    project: MAProject?,
    executionLogs: [ExecutionLogEntry]
) -> OpsTracePanelModel {
    OpsTracePanelModel(
        detail: detail,
        relatedLogs: opsRelatedLogs(for: detail, executionLogs: executionLogs),
        workflowPath: buildOpsWorkflowPath(for: detail, project: project)
    )
}

private func opsRelatedLogs(
    for detail: OpsTraceDetail,
    executionLogs: [ExecutionLogEntry]
) -> [ExecutionLogEntry] {
    guard detail.service != "openclaw.external-session" else { return [] }

    let lowerBound = detail.startedAt.addingTimeInterval(-15)
    let upperBound = (detail.completedAt ?? detail.startedAt).addingTimeInterval(30)

    return executionLogs
        .filter { entry in
            if let nodeID = detail.nodeID, entry.nodeID == nodeID {
                return true
            }
            return entry.timestamp >= lowerBound && entry.timestamp <= upperBound
        }
        .sorted { $0.timestamp < $1.timestamp }
        .suffix(30)
        .map { $0 }
}

private func buildOpsWorkflowPath(
    for detail: OpsTraceDetail,
    project: MAProject?
) -> OpsTraceWorkflowPath? {
    guard let workflow = project?.workflows.first,
          let currentNodeID = detail.nodeID else {
        return nil
    }

    let nodeByID = Dictionary(uniqueKeysWithValues: workflow.nodes.map { ($0.id, $0) })
    let agentByID = Dictionary(uniqueKeysWithValues: (project?.agents ?? []).map { ($0.id, $0) })

    guard let currentNode = nodeByID[currentNodeID] else { return nil }

    let incomingEdges = workflow.edges.filter { $0.isIncoming(to: currentNodeID) }
    let outgoingEdges = workflow.edges.filter { $0.isOutgoing(from: currentNodeID) }
    let requestedTargets = Set(detail.routingTargets.map(normalizedOpsRouteKey))

    let upstreamNodes = incomingEdges.compactMap { edge -> OpsTraceWorkflowPathNode? in
        let sourceID = edge.toNodeID == currentNodeID ? edge.fromNodeID : edge.toNodeID
        guard let node = nodeByID[sourceID] else { return nil }
        return makeOpsWorkflowPathNode(node: node, role: .upstream, state: .normal, agentByID: agentByID)
    }

    let downstreamNodes = outgoingEdges.compactMap { edge -> OpsTraceWorkflowPathNode? in
        let targetID = edge.fromNodeID == currentNodeID ? edge.toNodeID : edge.fromNodeID
        guard let node = nodeByID[targetID] else { return nil }
        let state: OpsTraceWorkflowPathNode.State = matchesOpsRouteTarget(node: node, requestedTargets: requestedTargets, agentByID: agentByID)
            ? .selected
            : .skipped
        return makeOpsWorkflowPathNode(node: node, role: .downstream, state: state, agentByID: agentByID)
    }

    guard let currentPathNode = makeOpsWorkflowPathNode(
        node: currentNode,
        role: .current,
        state: .selected,
        agentByID: agentByID
    ) else {
        return nil
    }

    return OpsTraceWorkflowPath(
        upstreamNodes: uniqueOpsWorkflowPathNodes(upstreamNodes),
        currentNode: currentPathNode,
        downstreamNodes: uniqueOpsWorkflowPathNodes(downstreamNodes)
    )
}

private func makeOpsWorkflowPathNode(
    node: WorkflowNode,
    role: OpsTraceWorkflowPathNode.Role,
    state: OpsTraceWorkflowPathNode.State,
    agentByID: [UUID: Agent]
) -> OpsTraceWorkflowPathNode? {
    let agentName = node.agentID.flatMap { agentByID[$0]?.name }
    let title = node.title.isEmpty ? (agentName ?? "Untitled Node") : node.title
    let subtitle: String

    switch node.type {
    case .start:
        subtitle = "Start Node"
    case .agent:
        subtitle = agentName ?? "Agent Node"
    }

    return OpsTraceWorkflowPathNode(
        id: node.id,
        title: title,
        subtitle: subtitle,
        role: role,
        state: state
    )
}

private func uniqueOpsWorkflowPathNodes(_ nodes: [OpsTraceWorkflowPathNode]) -> [OpsTraceWorkflowPathNode] {
    var seen = Set<UUID>()
    return nodes.filter { node in
        seen.insert(node.id).inserted
    }
}

private func matchesOpsRouteTarget(
    node: WorkflowNode,
    requestedTargets: Set<String>,
    agentByID: [UUID: Agent]
) -> Bool {
    guard !requestedTargets.isEmpty else { return false }

    var candidates: Set<String> = [
        normalizedOpsRouteKey(node.id.uuidString),
        normalizedOpsRouteKey(String(node.id.uuidString.prefix(8))),
        normalizedOpsRouteKey(node.title)
    ]

    if let agentID = node.agentID, let agent = agentByID[agentID] {
        candidates.insert(normalizedOpsRouteKey(agent.name))
    }

    candidates = candidates.filter { !$0.isEmpty }
    return !candidates.isDisjoint(with: requestedTargets)
}

private func normalizedOpsRouteKey(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
}

private struct OpsTraceTimelineEntry: Identifiable {
    let span: OpsTraceRelatedSpan
    let depth: Int

    var id: String { span.id }
}

private struct OpsTraceDetailSheet: View {
    let panel: OpsTracePanelModel
    @State private var selectedSpanFilter: OpsTraceSpanFilter = .all
    @State private var spanSearchText: String = ""
    @State private var prioritizeAnomalies: Bool = true

    private var detail: OpsTraceDetail { panel.detail }

    private var visibleAttributeKeys: [String] {
        detail.attributes.keys
            .filter { key in
                ![
                    "output_text",
                    "preview_text",
                    "protocol_event_count",
                    "protocol_ref_count",
                    "protocol_event_types",
                    "protocol_repair_count",
                    "protocol_repair_types",
                    "protocol_requested_route",
                    "protocol_sanitized_route",
                    "protocol_safe_degrade_applied"
                ].contains(key)
            }
            .sorted()
    }
    private var protocolEventCount: Int? {
        if let count = detail.attributes["protocol_event_count"].flatMap(Int.init) {
            return count
        }
        return detail.eventsText?.split(separator: "\n").count
    }

    private var protocolRefCount: Int? {
        detail.attributes["protocol_ref_count"].flatMap(Int.init)
    }

    private var protocolEventTypes: String? {
        let value = detail.attributes["protocol_event_types"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty == false) ? value : nil
    }

    private var protocolRepairCount: Int? {
        detail.attributes["protocol_repair_count"].flatMap(Int.init)
    }

    private var protocolRepairTypes: String? {
        let value = detail.attributes["protocol_repair_types"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty == false) ? value : nil
    }

    private var requestedProtocolRoute: String? {
        let value = detail.attributes["protocol_requested_route"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty == false) ? value : nil
    }

    private var sanitizedProtocolRoute: String? {
        let value = detail.attributes["protocol_sanitized_route"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty == false) ? value : nil
    }

    private var protocolSafeDegradeApplied: Bool? {
        detail.attributes["protocol_safe_degrade_applied"].flatMap { value in
            switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "1", "yes":
                return true
            case "false", "0", "no":
                return false
            default:
                return nil
            }
        }
    }

    private var filteredTimelineEntries: [OpsTraceTimelineEntry] {
        let normalizedSearch = spanSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let spans = detail.relatedSpans.filter { span in
            guard selectedSpanFilter.matches(service: span.service) else { return false }
            guard !normalizedSearch.isEmpty else { return true }

            let haystack = [
                span.name,
                span.service,
                span.summaryText,
                span.statusText
            ]
            .joined(separator: " ")
            .lowercased()

            return haystack.contains(normalizedSearch)
        }
        let spanByID = Dictionary(uniqueKeysWithValues: spans.map { ($0.id, $0) })

        func depth(for span: OpsTraceRelatedSpan) -> Int {
            var currentParentID = span.parentSpanID
            var currentDepth = 0
            var visited: Set<String> = []

            while let parentID = currentParentID,
                  parentID != detail.id.uuidString,
                  let parentSpan = spanByID[parentID],
                  visited.insert(parentID).inserted {
                currentDepth += 1
                currentParentID = parentSpan.parentSpanID
            }

            return currentDepth
        }

        let entries = spans.map { OpsTraceTimelineEntry(span: $0, depth: depth(for: $0)) }

        guard prioritizeAnomalies else { return entries }

        return entries.sorted { lhs, rhs in
            let leftIsAnomalous = isAnomalous(lhs.span)
            let rightIsAnomalous = isAnomalous(rhs.span)
            if leftIsAnomalous != rightIsAnomalous {
                return leftIsAnomalous && !rightIsAnomalous
            }
            if lhs.depth != rhs.depth {
                return lhs.depth < rhs.depth
            }
            if lhs.span.startedAt != rhs.span.startedAt {
                return lhs.span.startedAt < rhs.span.startedAt
            }
            return lhs.span.id < rhs.span.id
        }
    }
    private var anomalyCount: Int {
        detail.relatedSpans.filter(isAnomalous).count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(detail.spanName)
                            .font(.title3)
                            .fontWeight(.semibold)
                        Text(detail.traceID)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                    }

                    Spacer()

                    Text(detail.executionStatus.displayName)
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(traceStatusColor(detail.executionStatus).opacity(0.12))
                        .foregroundColor(traceStatusColor(detail.executionStatus))
                        .clipShape(Capsule())
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                    detailCard(
                        title: "Source",
                        value: detail.service == "openclaw.external-session" ? "OpenClaw Backup" : "Runtime"
                    )
                    detailCard(title: "Agent", value: detail.agentName)
                    detailCard(title: "Output", value: detail.outputType.rawValue)
                    detailCard(title: "Route", value: detail.routingAction ?? "N/A")
                    detailCard(title: "Duration", value: detail.duration.map(formatOpsDuration) ?? "N/A")
                    detailCard(title: "Started", value: detail.startedAt.formatted(date: .abbreviated, time: .standard))
                    detailCard(title: "Completed", value: detail.completedAt?.formatted(date: .abbreviated, time: .standard) ?? "In progress")
                    if let protocolEventCount, protocolEventCount > 0 {
                        detailCard(title: "Protocol Events", value: String(protocolEventCount))
                    }
                    if let protocolRefCount, protocolRefCount > 0 {
                        detailCard(title: "Protocol Refs", value: String(protocolRefCount))
                    }
                    if let protocolRepairCount, protocolRepairCount > 0 {
                        detailCard(title: "Protocol Repairs", value: String(protocolRepairCount))
                    }
                    if let protocolSafeDegradeApplied {
                        detailCard(title: "Safe Degrade", value: protocolSafeDegradeApplied ? "Applied" : "Not applied")
                    }
                }

                if let reason = detail.routingReason, !reason.isEmpty {
                    detailSection(title: LocalizedString.text("routing_reason"), text: reason)
                }

                if !detail.routingTargets.isEmpty {
                    detailSection(title: LocalizedString.text("routing_targets"), text: detail.routingTargets.joined(separator: ", "))
                }

                detailSection(title: LocalizedString.text("preview"), text: detail.previewText)

                if !detail.outputText.isEmpty {
                    detailSection(title: LocalizedString.text("raw_output"), text: detail.outputText, monospaced: true)
                }

                if let workflowPath = panel.workflowPath {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(LocalizedString.text("workflow_path"))
                            .font(.headline)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: 18) {
                                workflowPathColumn(
                                    title: LocalizedString.text("upstream"),
                                    nodes: workflowPath.upstreamNodes,
                                    emptyText: LocalizedString.text("no_upstream_nodes")
                                )

                                Image(systemName: "arrow.right")
                                    .foregroundColor(.secondary)
                                    .padding(.top, 34)

                                workflowPathCurrentNode(workflowPath.currentNode)

                                Image(systemName: "arrow.right")
                                    .foregroundColor(.secondary)
                                    .padding(.top, 34)

                                workflowPathColumn(
                                    title: LocalizedString.text("downstream"),
                                    nodes: workflowPath.downstreamNodes,
                                    emptyText: LocalizedString.text("no_downstream_nodes")
                                )
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .padding()
                    .background(Color(.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                if !detail.relatedSpans.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(LocalizedString.text("span_timeline"))
                                    .font(.headline)
                                Text(LocalizedString.text("span_timeline_desc"))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Picker(LocalizedString.text("span_filter"), selection: $selectedSpanFilter) {
                                ForEach(OpsTraceSpanFilter.allCases) { filter in
                                    Text(filter.title).tag(filter)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 250)
                        }

                        HStack(spacing: 12) {
                            TextField(LocalizedString.text("span_search_placeholder"), text: $spanSearchText)
                                .textFieldStyle(.roundedBorder)

                            Toggle(LocalizedString.text("prioritize_anomalies"), isOn: $prioritizeAnomalies)
                                .toggleStyle(.switch)
                                .frame(maxWidth: 180)
                        }

                        if anomalyCount > 0 {
                            Text(LocalizedString.format("anomalous_spans_highlighted", anomalyCount))
                                .font(.caption)
                                .foregroundColor(.orange)
                        }

                        if filteredTimelineEntries.isEmpty {
                            Text(spanSearchText.isEmpty ? LocalizedString.text("no_spans_match_filter") : LocalizedString.text("no_spans_match_search"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.vertical, 4)
                        }

                        ForEach(filteredTimelineEntries) { entry in
                            let span = entry.span

                            HStack(alignment: .top, spacing: 12) {
                                Color.clear
                                    .frame(width: CGFloat(entry.depth) * 18)

                                if entry.depth > 0 {
                                    Image(systemName: "arrow.turn.down.right")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .frame(width: 10, alignment: .leading)
                                } else {
                                    Color.clear.frame(width: 10)
                                }

                                Rectangle()
                                    .fill(span.statusText == "error" ? Color.red : Color.blue)
                                    .frame(width: 3)
                                    .clipShape(Capsule())

                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(span.name)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                        Spacer()
                                        Text(span.duration.map(formatOpsDuration) ?? "0.0s")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }

                                    HStack(spacing: 8) {
                                        Text(spanTimelineCategoryLabel(for: span.service))
                                            .font(.caption2)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 3)
                                            .background(spanTimelineCategoryColor(for: span.service).opacity(0.12))
                                            .foregroundColor(spanTimelineCategoryColor(for: span.service))
                                            .clipShape(Capsule())

                                        Text(span.service)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }

                                    Text(span.summaryText)
                                        .font(.caption)

                                    Text(span.startedAt.formatted(date: .omitted, time: .standard))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(isAnomalous(span) ? Color.orange.opacity(0.09) : Color.clear)
                            .overlay {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(isAnomalous(span) ? Color.orange.opacity(0.45) : Color.clear, lineWidth: 1)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                    .padding()
                    .background(Color(.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                if !visibleAttributeKeys.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(LocalizedString.text("attributes"))
                            .font(.headline)

                        ForEach(visibleAttributeKeys, id: \.self) { key in
                            HStack(alignment: .top, spacing: 12) {
                                Text(key)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .frame(width: 140, alignment: .leading)

                                Text(detail.attributes[key] ?? "")
                                    .font(.caption)
                                    .textSelection(.enabled)

                                Spacer()
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .padding()
                    .background(Color(.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                if let eventsText = detail.eventsText, !eventsText.isEmpty {
                    detailSection(title: "Protocol Events", text: eventsText, monospaced: true)
                }

                if let protocolEventTypes {
                    detailSection(title: "Protocol Event Types", text: protocolEventTypes)
                }

                if let protocolRepairTypes {
                    detailSection(title: "Protocol Repair Types", text: protocolRepairTypes)
                }

                if let requestedProtocolRoute {
                    detailSection(title: "Requested Route", text: requestedProtocolRoute)
                }

                if let sanitizedProtocolRoute {
                    detailSection(title: "Sanitized Route", text: sanitizedProtocolRoute)
                }

                if !panel.relatedLogs.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(LocalizedString.text("related_logs"))
                            .font(.headline)

                        ForEach(panel.relatedLogs) { entry in
                            HStack(alignment: .top, spacing: 10) {
                                Text(entry.timestamp.formatted(date: .omitted, time: .standard))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .frame(width: 78, alignment: .leading)

                                Text(entry.level.rawValue)
                                    .font(.caption2)
                                    .foregroundColor(logColor(for: entry.level))
                                    .frame(width: 52, alignment: .leading)

                                Text(entry.message)
                                    .font(.caption)
                                    .textSelection(.enabled)

                                Spacer()
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .padding()
                    .background(Color(.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .padding()
        }
        .frame(minWidth: 760, minHeight: 560)
    }

    private func detailCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .textSelection(.enabled)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func workflowPathColumn(
        title: String,
        nodes: [OpsTraceWorkflowPathNode],
        emptyText: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)

            if nodes.isEmpty {
                Text(emptyText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 180, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(nodes) { node in
                        workflowPathNodeCard(node)
                    }
                }
            }
        }
    }

    private func workflowPathCurrentNode(_ node: OpsTraceWorkflowPathNode) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LocalizedString.text("current"))
                .font(.caption)
                .foregroundColor(.secondary)

            workflowPathNodeCard(node)
                .frame(width: 220)
        }
    }

    private func workflowPathNodeCard(_ node: OpsTraceWorkflowPathNode) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(node.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Spacer()
                Text(workflowPathBadgeText(node))
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(workflowPathBadgeColor(node).opacity(0.14))
                    .foregroundColor(workflowPathBadgeColor(node))
                    .clipShape(Capsule())
            }

            Text(node.subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
        .padding()
        .frame(width: 180, alignment: .leading)
        .background(workflowPathCardColor(node))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(workflowPathBadgeColor(node).opacity(node.role == .current ? 0.6 : 0.22), lineWidth: node.role == .current ? 2 : 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func detailSection(title: String, text: String, monospaced: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            Text(text)
                .font(monospaced ? .system(.body, design: .monospaced) : .body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func traceStatusColor(_ status: ExecutionStatus) -> Color {
        switch status {
        case .completed: return .green
        case .failed: return .red
        case .running: return .orange
        case .waiting: return .blue
        case .idle: return .secondary
        }
    }

    private func logColor(for level: ExecutionLogEntry.LogLevel) -> Color {
        switch level {
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        case .success: return .green
        }
    }

    private func spanTimelineCategoryLabel(for service: String) -> String {
        if service.contains("message") {
            return LocalizedString.text("message_category")
        }
        if service.contains("tool") {
            return LocalizedString.text("tool_category")
        }
        if service.contains("routing") {
            return LocalizedString.text("routing_category")
        }
        if service.contains("output") {
            return LocalizedString.text("output_category")
        }
        return LocalizedString.text("runtime_category")
    }

    private func spanTimelineCategoryColor(for service: String) -> Color {
        if service.contains("message") {
            return .blue
        }
        if service.contains("tool") {
            return .teal
        }
        if service.contains("routing") {
            return .purple
        }
        if service.contains("output") {
            return .orange
        }
        return .secondary
    }

    private func isAnomalous(_ span: OpsTraceRelatedSpan) -> Bool {
        let summary = span.summaryText.lowercased()
        let status = span.statusText.lowercased()
        return status.contains("error")
            || status.contains("fail")
            || summary.contains("error")
            || summary.contains("failed")
            || summary.contains("timeout")
            || summary.contains("timed out")
    }

    private func workflowPathBadgeText(_ node: OpsTraceWorkflowPathNode) -> String {
        switch node.role {
        case .current:
            return LocalizedString.text("current")
        case .upstream:
            return LocalizedString.text("upstream")
        case .downstream:
            switch node.state {
            case .selected:
                return LocalizedString.text("selected")
            case .skipped:
                return LocalizedString.text("available")
            case .normal:
                return LocalizedString.text("node_label")
            }
        }
    }

    private func workflowPathBadgeColor(_ node: OpsTraceWorkflowPathNode) -> Color {
        switch node.role {
        case .current:
            return .blue
        case .upstream:
            return .secondary
        case .downstream:
            switch node.state {
            case .selected:
                return .green
            case .skipped:
                return .orange
            case .normal:
                return .secondary
            }
        }
    }

    private func workflowPathCardColor(_ node: OpsTraceWorkflowPathNode) -> Color {
        switch node.role {
        case .current:
            return Color.blue.opacity(0.08)
        case .upstream:
            return Color(.controlBackgroundColor)
        case .downstream:
            switch node.state {
            case .selected:
                return Color.green.opacity(0.08)
            case .skipped:
                return Color.orange.opacity(0.08)
            case .normal:
                return Color(.controlBackgroundColor)
            }
        }
    }

    private func formatOpsDuration(_ duration: TimeInterval) -> String {
        if duration >= 60 {
            let minutes = Int(duration) / 60
            let seconds = Int(duration) % 60
            return "\(minutes)m \(seconds)s"
        }
        return String(format: "%.1fs", duration)
    }
}

private struct OpsCronDetailSheet: View {
    @EnvironmentObject var appState: AppState

    let panel: OpsCronPanelModel
    @State private var selectedTracePanel: OpsTracePanelModel?

    private var detail: OpsCronDetail { panel.detail }
    private var currentProject: MAProject? {
        guard appState.currentProject?.id == panel.projectID else { return nil }
        return appState.currentProject
    }
    private var reliabilitySeries: OpsMetricHistorySeries? {
        detail.historySeries.first { $0.metric == .cronReliability }
    }
    private var errorBudgetSeries: OpsMetricHistorySeries? {
        detail.historySeries.first { $0.metric == .errorBudget }
    }
    private var latestRun: OpsCronRunRow? {
        detail.runs.max { $0.runAt < $1.runAt }
    }
    private var linkedSessionCount: Int {
        detail.runs.filter { $0.linkedSessionSpanID != nil }.count
    }
    private var linkedAnomalyCount: Int {
        detail.anomalies.filter { $0.linkedSessionSpanID != nil || matchingRun(for: $0)?.linkedSessionSpanID != nil }.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                headerSection
                summarySection
                trendSection
                recentRunsSection
                anomalySection
            }
            .padding(20)
        }
        .frame(minWidth: 680, minHeight: 560)
        .sheet(item: $selectedTracePanel) { panel in
            OpsTraceDetailSheet(panel: panel)
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(detail.cronName)
                .font(.title3.weight(.semibold))

            HStack(spacing: 8) {
                detailBadge(
                    latestRun?.statusText ?? "Unknown",
                    color: statusColor(for: latestRun?.statusText ?? "")
                )
                detailBadge(LocalizedString.format("runs_count", detail.runs.count), color: .blue)
                detailBadge(LocalizedString.format("anomalies_count", detail.anomalies.count), color: detail.anomalies.isEmpty ? .secondary : .red)
            }

            Text(LocalizedString.text("cron_scoped_desc"))
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var summarySection: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 16)], spacing: 16) {
            summaryCard(
                title: LocalizedString.text("execution_success_rate"),
                value: summarySuccessRateText,
                detail: detail.summary.map { LocalizedString.format("success_detail", $0.successfulRuns, $0.failedRuns) } ?? LocalizedString.text("recent_retained_samples"),
                color: summarySuccessRateColor
            )
            summaryCard(
                title: LocalizedString.text("latest_run"),
                value: latestRun.map { $0.runAt.formatted(date: .abbreviated, time: .shortened) } ?? "-",
                detail: latestRun?.summaryText ?? LocalizedString.text("no_recent_run_captured"),
                color: .blue
            )
            summaryCard(
                title: LocalizedString.text("linked_sessions"),
                value: "\(linkedSessionCount)",
                detail: LocalizedString.text("runs_open_external_session_trace"),
                color: linkedSessionCount == 0 ? .secondary : .teal
            )
            summaryCard(
                title: LocalizedString.text("linked_anomalies"),
                value: "\(linkedAnomalyCount)",
                detail: LocalizedString.text("anomalies_jump_underlying_session"),
                color: linkedAnomalyCount == 0 ? .secondary : .orange
            )
            summaryCard(
                title: LocalizedString.text("last_error_count"),
                value: latestErrorBudgetText,
                detail: LocalizedString.text("most_recent_scoped_error_budget_sample"),
                color: latestErrorBudgetValue == 0 ? .green : .red
            )
        }
    }

    @ViewBuilder
    private var trendSection: some View {
        if let reliabilitySeries, !reliabilitySeries.points.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(LocalizedString.text("thirty_day_trend"))
                            .font(.headline)
                        Text(LocalizedString.text("cron_trend_desc"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if let latestPoint = reliabilitySeries.latestPoint {
                        Text(LocalizedString.format("latest_percent", Int(latestPoint.value.rounded())))
                            .font(.caption.weight(.medium))
                            .foregroundColor(.secondary)
                    }
                }

                Chart {
                    ForEach(reliabilitySeries.points) { point in
                        AreaMark(
                            x: .value(LocalizedString.text("day_label"), point.date, unit: .day),
                            y: .value(LocalizedString.text("execution_success_rate"), point.value)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(Color.teal.opacity(0.14))

                        LineMark(
                            x: .value(LocalizedString.text("day_label"), point.date, unit: .day),
                            y: .value(LocalizedString.text("execution_success_rate"), point.value)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(Color.teal)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))

                        PointMark(
                            x: .value(LocalizedString.text("day_label"), point.date, unit: .day),
                            y: .value(LocalizedString.text("execution_success_rate"), point.value)
                        )
                        .foregroundStyle(Color.teal)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .chartYScale(domain: 0 ... 100)
                .frame(height: 220)

                Text(LocalizedString.format("latest_error_budget_sample", latestErrorBudgetText))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var recentRunsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LocalizedString.text("recent_runs"))
                .font(.headline)

            if detail.runs.isEmpty {
                emptyState(LocalizedString.text("no_retained_runs_for_cron"))
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(detail.runs.prefix(12))) { run in
                        Button {
                            openLinkedSession(for: run)
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Text(run.runAt.formatted(date: .omitted, time: .standard))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .frame(width: 72, alignment: .leading)

                                detailBadge(run.statusText, color: statusColor(for: run.statusText))
                                    .frame(width: 76, alignment: .leading)

                                Text(run.duration.map(formatDuration) ?? "-")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .frame(width: 56, alignment: .leading)

                                Text(run.deliveryStatus ?? "-")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .frame(width: 86, alignment: .leading)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(run.summaryText)
                                        .font(.caption)
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                    if let metadata = runMetadataSummary(for: run) {
                                        Text(metadata)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }

                                    if let sourcePath = run.sourcePath, !sourcePath.isEmpty {
                                        Text(sourcePath)
                                            .font(.system(.caption2, design: .monospaced))
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }
                                }

                                if run.linkedSessionSpanID != nil {
                                    Image(systemName: "arrowshape.turn.up.right")
                                        .font(.caption2)
                                        .foregroundColor(.teal)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.45))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
                .background(Color(.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private var anomalySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LocalizedString.text("recent_anomalies"))
                .font(.headline)

            if detail.anomalies.isEmpty {
                emptyState(LocalizedString.text("no_retained_cron_anomalies"))
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(detail.anomalies.prefix(10))) { row in
                        let matchedRun = matchingRun(for: row)
                        Button {
                            openLinkedSession(for: row)
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 8) {
                                    Text(row.occurredAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)

                                    detailBadge(row.status == .critical ? LocalizedString.text("critical_label") : LocalizedString.text("warning_label"), color: statusColor(for: row.statusText))
                                    detailBadge(row.statusText, color: .secondary)

                                    if row.linkedSessionSpanID != nil || matchingRun(for: row)?.linkedSessionSpanID != nil {
                                        detailBadge(LocalizedString.text("open_session"), color: .teal)
                                    }
                                }

                                Text(row.detailText)
                                    .font(.caption)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                if let metadata = anomalyMetadataSummary(for: row, matchedRun: matchedRun) {
                                    Text(metadata)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }

                                if let sourcePath = row.relatedSourcePath ?? matchedRun?.sourcePath,
                                   !sourcePath.isEmpty {
                                    Text(sourcePath)
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }

                                if row.fullDetailText != row.detailText {
                                    Text(row.fullDetailText)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .lineLimit(4)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.45))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
                .background(Color(.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private var summarySuccessRateText: String {
        if let summary = detail.summary {
            return "\(Int(summary.successRate.rounded()))%"
        }
        if let latestValue = reliabilitySeries?.latestPoint?.value {
            return "\(Int(latestValue.rounded()))%"
        }
        return "-"
    }

    private var summarySuccessRateColor: Color {
        if let summary = detail.summary {
            return summary.successRate >= 90 ? .green : (summary.successRate >= 75 ? .orange : .red)
        }
        return .secondary
    }

    private var latestErrorBudgetValue: Int? {
        errorBudgetSeries?.latestPoint.map { Int($0.value.rounded()) }
    }

    private var latestErrorBudgetText: String {
        latestErrorBudgetValue.map(String.init) ?? "-"
    }

    private func openLinkedSession(for run: OpsCronRunRow) {
        guard let spanID = run.linkedSessionSpanID,
              let detail = appState.opsAnalytics.traceDetail(projectID: panel.projectID, traceID: spanID) else {
            return
        }

        selectedTracePanel = makeOpsTracePanelModel(
            detail: detail,
            project: currentProject,
            executionLogs: appState.openClawService.executionLogs
        )
    }

    private func openLinkedSession(for anomaly: OpsAnomalyRow) {
        if let spanID = anomaly.linkedSessionSpanID,
           let detail = appState.opsAnalytics.traceDetail(projectID: panel.projectID, traceID: spanID) {
            selectedTracePanel = makeOpsTracePanelModel(
                detail: detail,
                project: currentProject,
                executionLogs: appState.openClawService.executionLogs
            )
            return
        }

        guard let run = matchingRun(for: anomaly) else { return }
        openLinkedSession(for: run)
    }

    private func matchingRun(for anomaly: OpsAnomalyRow) -> OpsCronRunRow? {
        OpsCronAnomalyRunMatcher.matchingRun(for: anomaly, in: detail.runs)
    }

    private func runMetadataSummary(for run: OpsCronRunRow) -> String? {
        var parts: [String] = []
        if let jobID = run.jobID {
            parts.append(LocalizedString.format("job_id_label", jobID))
        }
        if let runID = run.runID {
            parts.append(LocalizedString.format("session_label", shortIdentifier(runID)))
        }
        if let sourcePath = run.sourcePath {
            parts.append(LocalizedString.format("artifact_label", URL(fileURLWithPath: sourcePath).lastPathComponent))
        }

        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }

    private func anomalyMetadataSummary(
        for anomaly: OpsAnomalyRow,
        matchedRun: OpsCronRunRow?
    ) -> String? {
        var parts: [String] = []
        if let jobID = anomaly.relatedJobID ?? matchedRun?.jobID {
            parts.append(LocalizedString.format("matched_run_label", jobID))
        }
        if let runID = anomaly.relatedRunID ?? matchedRun?.runID {
            parts.append(LocalizedString.format("session_label", shortIdentifier(runID)))
        }
        if let sourcePath = anomaly.relatedSourcePath ?? matchedRun?.sourcePath {
            parts.append(LocalizedString.format("artifact_label", URL(fileURLWithPath: sourcePath).lastPathComponent))
        }

        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }

    private func shortIdentifier(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 10 else { return trimmed }
        return "\(trimmed.prefix(8))...\(trimmed.suffix(4))"
    }

    private func summaryCard(title: String, value: String, detail: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundColor(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundColor(color)
            Text(detail)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func emptyState(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundColor(.secondary)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func detailBadge(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.caption.weight(.medium))
            .foregroundColor(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    private func statusColor(for statusText: String) -> Color {
        switch statusText.uppercased() {
        case "OK":
            return .green
        case "TIMEOUT", "FAILED", "ERROR":
            return .red
        default:
            return .orange
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        if duration >= 60 {
            let minutes = Int(duration) / 60
            let seconds = Int(duration) % 60
            return "\(minutes)m \(seconds)s"
        }
        return String(format: "%.1fs", duration)
    }
}

private struct OpsToolDetailSheet: View {
    @EnvironmentObject var appState: AppState

    let panel: OpsToolPanelModel
    @State private var selectedTracePanel: OpsTracePanelModel?

    private var detail: OpsToolDetail { panel.detail }
    private var currentProject: MAProject? {
        guard appState.currentProject?.id == panel.projectID else { return nil }
        return appState.currentProject
    }
    private var reliabilitySeries: OpsMetricHistorySeries? {
        detail.historySeries.first { $0.metric == .workflowReliability }
    }
    private var errorBudgetSeries: OpsMetricHistorySeries? {
        detail.historySeries.first { $0.metric == .errorBudget }
    }
    private var latestSpan: OpsToolSpanRow? {
        detail.spans.max { $0.startedAt < $1.startedAt }
    }
    private var linkedTraceCount: Int {
        detail.spans.count + detail.anomalies.filter { $0.linkedSpanID != nil }.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                headerSection
                summarySection
                trendSection
                recentSpanSection
                anomalySection
            }
            .padding(20)
        }
        .frame(minWidth: 720, minHeight: 580)
        .sheet(item: $selectedTracePanel) { panel in
            OpsTraceDetailSheet(panel: panel)
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(displayTitle)
                .font(.title3.weight(.semibold))

            HStack(spacing: 8) {
                detailBadge(detail.spans.isEmpty ? LocalizedString.text("no_spans_badge") : LocalizedString.format("spans_count", detail.spans.count), color: .blue)
                detailBadge(LocalizedString.format("anomalies_count", detail.anomalies.count), color: detail.anomalies.isEmpty ? .secondary : .red)
                detailBadge(latestSpan?.service ?? detail.toolIdentifier, color: .teal)
            }

            Text(LocalizedString.text("tool_scoped_desc"))
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var summarySection: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 16)], spacing: 16) {
            summaryCard(
                title: LocalizedString.text("execution_success_rate"),
                value: latestReliabilityText,
                detail: LocalizedString.text("latest_tool_scoped_reliability_sample"),
                color: reliabilityColor
            )
            summaryCard(
                title: LocalizedString.text("latest"),
                value: latestSpan.map { $0.startedAt.formatted(date: .abbreviated, time: .shortened) } ?? "-",
                detail: latestSpan?.title ?? LocalizedString.text("no_retained_tool_span"),
                color: .blue
            )
            summaryCard(
                title: LocalizedString.text("last_error_count"),
                value: latestErrorBudgetText,
                detail: LocalizedString.text("most_recent_scoped_error_budget_sample"),
                color: latestErrorBudgetValue == 0 ? .green : .red
            )
            summaryCard(
                title: LocalizedString.text("trace_drill_down"),
                value: "\(linkedTraceCount)",
                detail: LocalizedString.text("retained_tool_context_count"),
                color: linkedTraceCount == 0 ? .secondary : .teal
            )
        }
    }

    @ViewBuilder
    private var trendSection: some View {
        if let reliabilitySeries, !reliabilitySeries.points.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(LocalizedString.text("thirty_day_trend"))
                            .font(.headline)
                        Text(LocalizedString.text("tool_trend_desc"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Text(LocalizedString.format("latest_time", latestReliabilityText))
                        .font(.caption.weight(.medium))
                        .foregroundColor(.secondary)
                }

                Chart {
                    ForEach(reliabilitySeries.points) { point in
                        AreaMark(
                            x: .value(LocalizedString.text("day_label"), point.date, unit: .day),
                            y: .value(LocalizedString.text("execution_success_rate"), point.value)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(Color.teal.opacity(0.14))

                        LineMark(
                            x: .value(LocalizedString.text("day_label"), point.date, unit: .day),
                            y: .value(LocalizedString.text("execution_success_rate"), point.value)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(Color.teal)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))

                        PointMark(
                            x: .value(LocalizedString.text("day_label"), point.date, unit: .day),
                            y: .value(LocalizedString.text("execution_success_rate"), point.value)
                        )
                        .foregroundStyle(Color.teal)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .chartYScale(domain: 0 ... 100)
                .frame(height: 220)
            }
            .padding()
            .background(Color(.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var recentSpanSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LocalizedString.text("recent_tool_spans"))
                .font(.headline)

            if detail.spans.isEmpty {
                emptyState(LocalizedString.text("no_retained_tool_spans"))
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(detail.spans.prefix(12))) { row in
                        Button {
                            openTraceDetail(for: row)
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Text(row.startedAt.formatted(date: .omitted, time: .standard))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .frame(width: 72, alignment: .leading)

                                detailBadge(row.statusText, color: statusColor(for: row.statusText))
                                    .frame(width: 76, alignment: .leading)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(row.title)
                                        .font(.caption.weight(.medium))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text("\(row.agentName) • \(row.service)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .frame(width: 220, alignment: .leading)

                                Text(row.duration.map(formatDuration) ?? "-")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .frame(width: 56, alignment: .leading)

                                Text(row.summaryText)
                                    .font(.caption)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.45))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
                .background(Color(.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private var anomalySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LocalizedString.text("recent_tool_anomalies"))
                .font(.headline)

            if detail.anomalies.isEmpty {
                emptyState(LocalizedString.text("no_retained_tool_anomalies"))
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(detail.anomalies.prefix(10))) { row in
                        Button {
                            openLinkedTrace(for: row)
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 8) {
                                    Text(row.occurredAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)

                                    detailBadge(row.status == .critical ? LocalizedString.text("critical_label") : LocalizedString.text("warning_label"), color: statusColor(for: row.statusText))
                                    detailBadge(row.sourceService ?? LocalizedString.text("tool_category"), color: .teal)

                                    if row.linkedSpanID != nil {
                                        detailBadge(LocalizedString.text("open_trace"), color: .blue)
                                    }
                                }

                                Text(row.detailText)
                                    .font(.caption)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                if row.fullDetailText != row.detailText {
                                    Text(row.fullDetailText)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .lineLimit(4)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.45))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
                .background(Color(.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private var displayTitle: String {
        let trimmed = detail.toolIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return LocalizedString.text("tool_category") }
        if let lastComponent = trimmed.split(separator: ".").last {
            return String(lastComponent)
        }
        return trimmed
    }

    private var latestReliabilityText: String {
        if let latestValue = reliabilitySeries?.latestPoint?.value {
            return "\(Int(latestValue.rounded()))%"
        }
        return "-"
    }

    private var reliabilityColor: Color {
        guard let latestValue = reliabilitySeries?.latestPoint?.value else { return .secondary }
        return latestValue >= 90 ? .green : (latestValue >= 75 ? .orange : .red)
    }

    private var latestErrorBudgetValue: Int? {
        errorBudgetSeries?.latestPoint.map { Int($0.value.rounded()) }
    }

    private var latestErrorBudgetText: String {
        latestErrorBudgetValue.map(String.init) ?? "-"
    }

    private func openTraceDetail(for row: OpsToolSpanRow) {
        guard let detail = appState.opsAnalytics.traceDetail(projectID: panel.projectID, traceID: row.id) else {
            return
        }

        selectedTracePanel = makeOpsTracePanelModel(
            detail: detail,
            project: currentProject,
            executionLogs: appState.openClawService.executionLogs
        )
    }

    private func openLinkedTrace(for row: OpsAnomalyRow) {
        guard let spanID = row.linkedSpanID,
              let detail = appState.opsAnalytics.traceDetail(projectID: panel.projectID, traceID: spanID) else {
            return
        }

        selectedTracePanel = makeOpsTracePanelModel(
            detail: detail,
            project: currentProject,
            executionLogs: appState.openClawService.executionLogs
        )
    }

    private func summaryCard(title: String, value: String, detail: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundColor(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundColor(color)
            Text(detail)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func emptyState(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundColor(.secondary)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func detailBadge(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.caption.weight(.medium))
            .foregroundColor(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    private func statusColor(for statusText: String) -> Color {
        switch statusText.lowercased() {
        case "ok", "success", "completed":
            return .green
        case "error", "failed", "timeout":
            return .red
        default:
            return .orange
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        if duration >= 60 {
            let minutes = Int(duration) / 60
            let seconds = Int(duration) % 60
            return "\(minutes)m \(seconds)s"
        }
        return String(format: "%.1fs", duration)
    }
}

private struct OpsAnomalyDetailSheet: View {
    let panel: OpsAnomalyPanelModel

    private var row: OpsAnomalyRow { panel.row }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(row.title)
                        .font(.title3.weight(.semibold))

                    HStack(spacing: 8) {
                        detailBadge(row.sourceLabel, color: sourceColor)
                        detailBadge(row.status == .critical ? LocalizedString.text("critical_label") : LocalizedString.text("warning_label"), color: statusColor)
                        detailBadge(row.statusText.isEmpty ? "Unknown" : row.statusText.capitalized, color: .secondary)
                    }
                }

                detailGrid

                VStack(alignment: .leading, spacing: 8) {
                    Text(LocalizedString.text("captured_detail"))
                        .font(.headline)

                    Text(row.fullDetailText.isEmpty ? LocalizedString.text("no_additional_detail_captured") : row.fullDetailText)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color(.controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .padding(20)
        }
        .frame(minWidth: 560, minHeight: 420)
    }

    private var detailGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
            GridRow {
                detailKey(LocalizedString.text("occurred"))
                detailValue(row.occurredAt.formatted(date: .abbreviated, time: .standard))
            }

            GridRow {
                detailKey(LocalizedString.text("source_label"))
                detailValue(row.sourceService ?? row.sourceLabel)
            }

            GridRow {
                detailKey(LocalizedString.text("navigation"))
                detailValue(row.linkedSpanID == nil ? LocalizedString.text("detail_view_only") : LocalizedString.text("linked_trace_available"))
            }

            if let spanID = row.linkedSpanID {
                GridRow {
                    detailKey(LocalizedString.text("span_id"))
                    detailValue(spanID.uuidString)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var sourceColor: Color {
        switch row.sourceLabel {
        case "Cron":
            return .red
        case "Tool":
            return .teal
        case "OpenClaw":
            return .orange
        default:
            return .blue
        }
    }

    private var statusColor: Color {
        switch row.status {
        case .healthy:
            return .green
        case .warning:
            return .orange
        case .critical:
            return .red
        case .neutral:
            return .secondary
        }
    }

    private func detailBadge(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.caption.weight(.medium))
            .foregroundColor(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    private func detailKey(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundColor(.secondary)
            .frame(width: 88, alignment: .leading)
    }

    private func detailValue(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DashboardMetrics {
    var conversationTotalCount = 0
    var agentConversationRows: [DashboardAgentConversationRow] = []
    var modelTokenRows: [DashboardModelTokenUsageRow] = []
    var totalTokenCount = 0
    var activeAgentCount = 0
    var idleAgentCount = 0

    nonisolated init() {}

    nonisolated init(
        conversationTotalCount: Int,
        agentConversationRows: [DashboardAgentConversationRow],
        modelTokenRows: [DashboardModelTokenUsageRow],
        totalTokenCount: Int,
        activeAgentCount: Int,
        idleAgentCount: Int
    ) {
        self.conversationTotalCount = conversationTotalCount
        self.agentConversationRows = agentConversationRows
        self.modelTokenRows = modelTokenRows
        self.totalTokenCount = totalTokenCount
        self.activeAgentCount = activeAgentCount
        self.idleAgentCount = idleAgentCount
    }

    nonisolated static func build(
        project: MAProject?,
        tasks: [Task],
        messages: [Message],
        activeAgents: [UUID: OpenClawManager.ActiveAgentRuntime],
        isConnected: Bool,
        fileRootsByAgent: [UUID: [URL]],
        unknownModelLabel: String
    ) -> DashboardMetrics {
        guard let project else { return DashboardMetrics() }

        let agentIDs = Set(project.agents.map(\.id))
        let relevantMessages = messages
            .filter { message in
                agentIDs.contains(message.fromAgentID) || agentIDs.contains(message.toAgentID)
            }
            .sorted { $0.timestamp < $1.timestamp }
        let agentLookup = Dictionary(uniqueKeysWithValues: project.agents.map { ($0.id, $0) })
        let runningTaskAgentIDs = Set(
            tasks
                .filter { $0.status == .inProgress }
                .compactMap(\.assignedAgentID)
        )

        var outgoingCounts: [UUID: Int] = [:]
        var incomingCounts: [UUID: Int] = [:]
        var usageByModel: [String: (input: Int, output: Int)] = [:]

        for message in relevantMessages {
            let role = message.inferredRole
            let kind = message.inferredKind

            if message.fromAgentID == message.toAgentID {
                if role == "assistant" || kind == "output" {
                    outgoingCounts[message.fromAgentID, default: 0] += 1
                } else if role == "user" || kind == "input" {
                    incomingCounts[message.toAgentID, default: 0] += 1
                }
            } else {
                outgoingCounts[message.fromAgentID, default: 0] += 1
                incomingCounts[message.toAgentID, default: 0] += 1
            }

            guard kind != "system" else { continue }
            let tokens = estimatedTokens(for: message)
            guard tokens > 0 else { continue }

            let fromModel = agentLookup[message.fromAgentID].map { normalizedModelName(for: $0, unknownModelLabel: unknownModelLabel) }
            let toModel = agentLookup[message.toAgentID].map { normalizedModelName(for: $0, unknownModelLabel: unknownModelLabel) }

            if message.fromAgentID == message.toAgentID {
                guard let model = toModel ?? fromModel else { continue }
                var bucket = usageByModel[model, default: (0, 0)]
                if role == "assistant" || kind == "output" {
                    bucket.output += tokens
                } else {
                    bucket.input += tokens
                }
                usageByModel[model] = bucket
                continue
            }

            if let fromModel {
                var bucket = usageByModel[fromModel, default: (0, 0)]
                bucket.output += tokens
                usageByModel[fromModel] = bucket
            }

            if let toModel {
                var bucket = usageByModel[toModel, default: (0, 0)]
                bucket.input += tokens
                usageByModel[toModel] = bucket
            }
        }

        let agentConversationRows = project.agents
            .map { agent in
                DashboardAgentConversationRow(
                    agent: agent,
                    state: resolveAgentState(
                        for: agent,
                        project: project,
                        activeAgents: activeAgents,
                        runningTaskAgentIDs: runningTaskAgentIDs,
                        isConnected: isConnected
                    ),
                    outgoingCount: outgoingCounts[agent.id, default: 0],
                    incomingCount: incomingCounts[agent.id, default: 0],
                    skillCount: Set(agent.capabilities.map {
                        $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    }.filter { !$0.isEmpty }).count,
                    fileCount: fileRootsByAgent[agent.id, default: []].reduce(0) { partial, root in
                        partial + regularFileCount(at: root)
                    }
                )
            }
            .sorted { $0.agent.name.localizedCaseInsensitiveCompare($1.agent.name) == .orderedAscending }

        let modelTokenRows = usageByModel
            .map { model, usage in
                DashboardModelTokenUsageRow(
                    model: model,
                    inputTokens: usage.input,
                    outputTokens: usage.output
                )
            }
            .sorted { $0.model.localizedCaseInsensitiveCompare($1.model) == .orderedAscending }

        let activeAgentCount = agentConversationRows.reduce(into: 0) { partial, row in
            if row.state.isActive {
                partial += 1
            }
        }

        return DashboardMetrics(
            conversationTotalCount: relevantMessages.count,
            agentConversationRows: agentConversationRows,
            modelTokenRows: modelTokenRows,
            totalTokenCount: modelTokenRows.reduce(0) { $0 + $1.totalTokens },
            activeAgentCount: activeAgentCount,
            idleAgentCount: max(agentConversationRows.count - activeAgentCount, 0)
        )
    }

    private nonisolated static func resolveAgentState(
        for agent: Agent,
        project: MAProject,
        activeAgents: [UUID: OpenClawManager.ActiveAgentRuntime],
        runningTaskAgentIDs: Set<UUID>,
        isConnected: Bool
    ) -> DashboardAgentOnlineState {
        guard isConnected else {
            return .idle
        }

        let runtimeState = project.runtimeState.agentStates[agent.id.uuidString]?.lowercased() ?? ""
        let openClawState = activeAgents[agent.id]?.status.lowercased() ?? ""
        let isActive = runningTaskAgentIDs.contains(agent.id)
            || runtimeState.contains("running")
            || runtimeState.contains("queued")
            || runtimeState.contains("active")
            || runtimeState.contains("reload")
            || openClawState.contains("running")
            || openClawState.contains("active")
            || openClawState.contains("reload")

        return isActive ? .active : .idle
    }

    private nonisolated static func regularFileCount(at rootURL: URL) -> Int {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: rootURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return 0
        }

        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return 0
        }

        var count = 0
        for case let fileURL as URL in enumerator {
            if let isRegular = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile,
               isRegular == true {
                count += 1
            }
        }
        return count
    }

    private nonisolated static func normalizedModelName(for agent: Agent, unknownModelLabel: String) -> String {
        let value = agent.openClawDefinition.modelIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? unknownModelLabel : value
    }

    private nonisolated static func estimatedTokens(for message: Message) -> Int {
        if let tokenText = message.metadata["tokenEstimate"],
           let value = Int(tokenText),
           value >= 0 {
            return value
        }
        return estimatedTokens(for: message.summaryText)
    }

    private nonisolated static func estimatedTokens(for text: String) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        let scalarCount = trimmed.unicodeScalars.count
        return max(1, Int(ceil(Double(scalarCount) / 4.0)))
    }
}

private enum DashboardAgentOnlineState {
    case active
    case idle

    nonisolated var isActive: Bool {
        switch self {
        case .active: return true
        case .idle: return false
        }
    }

    var title: String {
        switch self {
        case .active: return LocalizedString.text("active_state")
        case .idle: return LocalizedString.text("idle_state")
        }
    }

    var color: Color {
        switch self {
        case .active: return .green
        case .idle: return .secondary
        }
    }
}

private struct DashboardAgentConversationRow: Identifiable {
    var id: UUID { agent.id }
    let agent: Agent
    let state: DashboardAgentOnlineState
    let outgoingCount: Int
    let incomingCount: Int
    let skillCount: Int
    let fileCount: Int
}

private struct DashboardModelTokenUsageRow: Identifiable {
    var id: String { model }
    let model: String
    let inputTokens: Int
    let outputTokens: Int
    let totalTokens: Int

    nonisolated init(model: String, inputTokens: Int, outputTokens: Int) {
        self.model = model
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalTokens = inputTokens + outputTokens
    }
}

struct TaskDashboardView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var taskManager: TaskManager
    @ObservedObject private var localizationManager = LocalizationManager.shared
    
    @State private var selectedTimeRange: TimeRange = .week
    @State private var showingAgentStats = false
    
    enum TimeRange: String, CaseIterable {
        case day
        case week
        case month
        case all

        var title: String {
            switch self {
            case .day: return LocalizedString.text("day_label")
            case .week: return LocalizedString.text("week_label")
            case .month: return LocalizedString.text("month_label")
            case .all: return LocalizedString.text("all_time")
            }
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 概览卡片
                overviewCards
                
                // 图表区域
                chartSection
                
                // Agent 统计
                agentStatsSection
                
                // 最近活动
                recentActivitySection
            }
            .padding()
        }
        .navigationTitle(LocalizedString.text("task_dashboard_title"))
        .toolbar {
            ToolbarItem {
                Picker(LocalizedString.text("time_range"), selection: $selectedTimeRange) {
                    ForEach(TimeRange.allCases, id: \.self) { range in
                        Text(range.title).tag(range)
                    }
                }
            }
        }
        .environment(\.locale, Locale(identifier: localizationManager.currentLanguage.rawValue))
    }
    
    // MARK: - 子视图
    
    private var overviewCards: some View {
        HStack(spacing: 16) {
            DashboardStatCard(  // 使用重命名后的名称
                title: LocalizedString.text("completion_rate"),
                value: "\(Int(taskManager.statistics.completionRate * 100))%",
                icon: "checkmark.circle.fill",
                color: taskManager.statistics.completionRate > 0.7 ? .green : .orange,
                trend: .up(15)
            )
            
            DashboardStatCard(  // 使用重命名后的名称
                title: LocalizedString.text("avg_completion_time"),
                value: formatDuration(taskManager.statistics.averageCompletionTime),
                icon: "clock.fill",
                color: .blue,
                trend: .down(8)
            )
            
            DashboardStatCard(  // 使用重命名后的名称
                title: LocalizedString.text("active_tasks"),
                value: "\(taskManager.statistics.inProgress)",
                icon: "arrow.triangle.2.circlepath",
                color: .blue,
                trend: .steady
            )
            
            DashboardStatCard(  // 使用重命名后的名称
                title: LocalizedString.text("blocked_tasks"),
                value: "\(taskManager.statistics.blocked)",
                icon: "exclamationmark.triangle",
                color: .red,
                trend: .up(3)
            )
        }
    }
    
    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LocalizedString.taskStatus)
                .font(.headline)
            
            Chart {
                ForEach(TaskStatus.allCases, id: \.self) { status in
                    SectorMark(
                        angle: .value(LocalizedString.text("count_label"), taskManager.tasks(for: status).count),
                        innerRadius: .ratio(0.6),
                        angularInset: 1
                    )
                    .foregroundStyle(status.color)
                    .annotation(position: .overlay) {
                        Text("\(taskManager.tasks(for: status).count)")
                            .font(.caption)
                            .foregroundColor(.white)
                    }
                }
            }
            .frame(height: 200)
            .chartLegend(position: .bottom)
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    private var agentStatsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(LocalizedString.text("agent_performance"))
                    .font(.headline)
                Spacer()
                Button(LocalizedString.text("show_details")) {
                    showingAgentStats = true
                }
                .font(.caption)
            }
            
            if let agents = appState.currentProject?.agents, !agents.isEmpty {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    ForEach(agents.prefix(6)) { agent in
                        AgentStatCard(agent: agent, taskManager: taskManager)
                    }
                }
            } else {
                Text(LocalizedString.noAgents)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 100)
                    .background(Color(.controlBackgroundColor))
                    .cornerRadius(8)
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
        .sheet(isPresented: $showingAgentStats) {
            AgentStatsDetailView(agents: appState.currentProject?.agents ?? [], taskManager: taskManager)
        }
    }
    
    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LocalizedString.text("recent_activity"))
                .font(.headline)
            
            VStack(spacing: 8) {
                ForEach(taskManager.tasks.sorted(by: { $0.createdAt > $1.createdAt }).prefix(5)) { task in
                    ActivityRow(task: task)
                }
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    // MARK: - 辅助方法
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 1

        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: localizationManager.currentLanguage.rawValue)
        formatter.calendar = calendar

        if duration < 60 {
            formatter.allowedUnits = [.second]
        } else if duration < 3600 {
            formatter.allowedUnits = [.minute]
        } else if duration < 86_400 {
            formatter.allowedUnits = [.hour]
        } else {
            formatter.allowedUnits = [.day]
        }

        return formatter.string(from: duration) ?? "\(Int(duration))"
    }
}

// MARK: - 辅助视图

struct DashboardStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    let trend: Trend
    
    enum Trend {
        case up(Int)
        case down(Int)
        case steady
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Spacer()
                trendIndicator
            }
            
            Text(value)
                .font(.title)
                .fontWeight(.bold)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 100)
        .background(Color(.windowBackgroundColor))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    private var trendIndicator: some View {
        Group {
            switch trend {
            case .up(let percent):
                HStack(spacing: 2) {
                    Image(systemName: "arrow.up")
                    Text("\(percent)%")
                }
                .font(.caption2)
                .foregroundColor(.green)
            case .down(let percent):
                HStack(spacing: 2) {
                    Image(systemName: "arrow.down")
                    Text("\(percent)%")
                }
                .font(.caption2)
                .foregroundColor(.red)
            case .steady:
                Text("—")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
        }
    }
}

struct AgentStatCard: View {
    let agent: Agent
    let taskManager: TaskManager
    
    private var agentTasks: [Task] {
        taskManager.tasks(for: agent.id)
    }
    
    private var completedTasks: Int {
        agentTasks.filter { $0.isCompleted }.count
    }
    
    private var completionRate: Double {
        agentTasks.isEmpty ? 0 : Double(completedTasks) / Double(agentTasks.count)
    }
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.circle.fill")
                .font(.title)
                .foregroundColor(.blue)
            
            Text(agent.name)
                .font(.caption)
                .lineLimit(1)
            
            Text(LocalizedString.format("tasks_count", agentTasks.count))
                .font(.caption2)
                .foregroundColor(.secondary)
            
            ProgressView(value: completionRate)
                .progressViewStyle(.linear)
                .frame(width: 60)
            
            Text("\(Int(completionRate * 100))%")
                .font(.caption2)
                .foregroundColor(completionRate > 0.7 ? .green : .orange)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.windowBackgroundColor))
        .cornerRadius(8)
    }
}

struct ActivityRow: View {
    let task: Task
    
    var body: some View {
        HStack {
            Image(systemName: task.status.icon)
                .foregroundColor(task.status.color)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.caption)
                    .lineLimit(1)
                Text("\(task.status.displayName) • \(task.createdAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text(task.priority.displayName)
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(task.priority.color.opacity(0.2)))
                .foregroundColor(task.priority.color)
        }
        .padding(.vertical, 4)
    }
}

struct AgentStatsDetailView: View {
    let agents: [Agent]
    let taskManager: TaskManager
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            List(agents) { agent in
                AgentDetailRow(agent: agent, taskManager: taskManager)
            }
            .navigationTitle(LocalizedString.text("agent_performance"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(LocalizedString.text("done_label")) {
                        dismiss()
                    }
                }
            }
            .frame(minWidth: 400, minHeight: 500)
        }
    }
}

struct AgentDetailRow: View {
    let agent: Agent
    let taskManager: TaskManager
    
    private var agentTasks: [Task] {
        taskManager.tasks(for: agent.id)
    }
    
    private var stats: (total: Int, todo: Int, inProgress: Int, done: Int, blocked: Int) {
        let total = agentTasks.count
        let todo = agentTasks.filter { $0.status == .todo }.count
        let inProgress = agentTasks.filter { $0.status == .inProgress }.count
        let done = agentTasks.filter { $0.status == .done }.count
        let blocked = agentTasks.filter { $0.status == .blocked }.count
        
        return (total, todo, inProgress, done, blocked)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "person.circle.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading) {
                    Text(agent.name)
                        .font(.headline)
                    Text(agent.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                Spacer()
                
                Text(LocalizedString.format("tasks_count", stats.total))
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.blue.opacity(0.2)))
            }
            
            HStack(spacing: 16) {
                StatPill(count: stats.todo, label: LocalizedString.todo, color: .gray)
                StatPill(count: stats.inProgress, label: LocalizedString.inProgress, color: .blue)
                StatPill(count: stats.done, label: LocalizedString.text("done_label"), color: .green)
                StatPill(count: stats.blocked, label: LocalizedString.blocked, color: .red)
            }
        }
        .padding(.vertical, 8)
    }
}

struct StatPill: View {
    let count: Int
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(.headline)
                .foregroundColor(color)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(width: 60)
    }
}
