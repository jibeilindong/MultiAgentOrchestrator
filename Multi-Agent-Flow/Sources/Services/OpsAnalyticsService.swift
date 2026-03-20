import Foundation
import Combine

enum OpsHealthStatus: String {
    case healthy
    case warning
    case critical
    case neutral
}

struct OpsGoalCard: Identifiable {
    let id: String
    let title: String
    let valueText: String
    let detailText: String
    let status: OpsHealthStatus
}

struct OpsDailyActivityPoint: Identifiable {
    let date: Date
    let completedCount: Int
    let failedCount: Int
    let errorCount: Int

    var id: TimeInterval { date.timeIntervalSinceReferenceDate }
}

struct OpsAgentHealthRow: Identifiable {
    let id: UUID
    let agentName: String
    let stateText: String
    let status: OpsHealthStatus
    let completedCount: Int
    let failedCount: Int
    let averageDuration: TimeInterval?
    let lastActivityAt: Date?
    let hasTrackedMemory: Bool
}

struct OpsTraceSummaryRow: Identifiable {
    let id: UUID
    let agentName: String
    let status: ExecutionStatus
    let duration: TimeInterval?
    let startedAt: Date
    let routingAction: String?
    let outputType: ExecutionOutputType
    let previewText: String
}

enum OpsHistoryMetric: String, CaseIterable, Identifiable {
    case workflowReliability
    case agentEngagement
    case memoryDiscipline
    case errorBudget

    var id: String { rawValue }

    var title: String {
        switch self {
        case .workflowReliability: return "Workflow Reliability"
        case .agentEngagement: return "Agent Engagement"
        case .memoryDiscipline: return "Memory Discipline"
        case .errorBudget: return "Error Budget"
        }
    }

    var goalKey: String {
        switch self {
        case .workflowReliability: return "workflow_reliability"
        case .agentEngagement: return "agent_engagement"
        case .memoryDiscipline: return "memory_discipline"
        case .errorBudget: return "error_budget"
        }
    }

    var metricKey: String {
        switch self {
        case .workflowReliability: return "success_rate"
        case .agentEngagement: return "engagement_rate"
        case .memoryDiscipline: return "tracked_rate"
        case .errorBudget: return "error_count"
        }
    }

    var windowDescription: String {
        switch self {
        case .workflowReliability: return "Successful runs as a percentage of total runs"
        case .agentEngagement: return "Share of project agents that were active"
        case .memoryDiscipline: return "Share of agents with tracked memory coverage"
        case .errorBudget: return "Errors recorded in recent runtime activity"
        }
    }

    func formattedValue(_ value: Double) -> String {
        switch self {
        case .workflowReliability, .agentEngagement, .memoryDiscipline:
            return "\(Int(value.rounded()))%"
        case .errorBudget:
            return "\(Int(value.rounded()))"
        }
    }
}

struct OpsMetricHistoryPoint: Identifiable {
    let date: Date
    let value: Double

    var id: TimeInterval { date.timeIntervalSinceReferenceDate }
}

struct OpsMetricHistorySeries: Identifiable {
    let metric: OpsHistoryMetric
    let points: [OpsMetricHistoryPoint]

    var id: String { metric.id }

    var latestPoint: OpsMetricHistoryPoint? { points.last }
    var previousPoint: OpsMetricHistoryPoint? { points.dropLast().last }
}

struct OpsTraceRelatedSpan: Identifiable {
    let id: String
    let parentSpanID: String?
    let name: String
    let service: String
    let statusText: String
    let startedAt: Date
    let completedAt: Date?
    let duration: TimeInterval?
    let summaryText: String
}

struct OpsTraceDetail: Identifiable {
    let id: UUID
    let traceID: String
    let parentSpanID: String?
    let spanName: String
    let service: String
    let statusText: String
    let agentName: String
    let executionStatus: ExecutionStatus
    let outputType: ExecutionOutputType
    let routingAction: String?
    let routingReason: String?
    let routingTargets: [String]
    let nodeID: UUID?
    let startedAt: Date
    let completedAt: Date?
    let duration: TimeInterval?
    let previewText: String
    let outputText: String
    let attributes: [String: String]
    let eventsText: String?
    let relatedSpans: [OpsTraceRelatedSpan]
}

struct OpsAnalyticsSnapshot {
    let generatedAt: Date
    let totalAgents: Int
    let activeAgents: Int
    let trackedMemoryAgents: Int
    let completedExecutions: Int
    let failedExecutions: Int
    let warningLogCount: Int
    let errorLogCount: Int
    let averageExecutionDuration: TimeInterval?
    let goalCards: [OpsGoalCard]
    let dailyActivity: [OpsDailyActivityPoint]
    let historicalSeries: [OpsMetricHistorySeries]
    let agentRows: [OpsAgentHealthRow]
    let traceRows: [OpsTraceSummaryRow]

    static let empty = OpsAnalyticsSnapshot(
        generatedAt: .distantPast,
        totalAgents: 0,
        activeAgents: 0,
        trackedMemoryAgents: 0,
        completedExecutions: 0,
        failedExecutions: 0,
        warningLogCount: 0,
        errorLogCount: 0,
        averageExecutionDuration: nil,
        goalCards: [],
        dailyActivity: [],
        historicalSeries: [],
        agentRows: [],
        traceRows: []
    )
}

final class OpsAnalyticsService: ObservableObject {
    @Published private(set) var snapshot: OpsAnalyticsSnapshot = .empty

    private let calendar = Calendar.autoupdatingCurrent
    private let store = OpsAnalyticsStore.shared

    func refresh(
        project: MAProject?,
        tasks: [Task],
        executionResults: [ExecutionResult],
        executionLogs: [ExecutionLogEntry],
        activeAgents: [UUID: OpenClawManager.ActiveAgentRuntime],
        isConnected: Bool
    ) {
        guard let project else {
            snapshot = .empty
            return
        }

        let workflow = project.workflows.first
        let nodeToAgent = Dictionary(uniqueKeysWithValues: (workflow?.nodes ?? []).compactMap { node -> (UUID, UUID)? in
            guard let agentID = node.agentID else { return nil }
            return (node.id, agentID)
        })

        let projectAgents = project.agents
        let totalAgents = projectAgents.count
        let completedResults = executionResults.filter { $0.status == .completed }
        let failedResults = executionResults.filter { $0.status == .failed }
        let warningLogs = executionLogs.filter { $0.level == .warning }
        let errorLogs = executionLogs.filter { $0.level == .error }

        let activeAgentIDs = makeActiveAgentIDs(
            project: project,
            tasks: tasks,
            activeAgents: activeAgents,
            isConnected: isConnected
        )
        let trackedMemoryAgentIDs = makeTrackedMemoryAgentIDs(project: project)
        let averageDuration = completedResults.compactMap(\.duration).average
        let goalCards = makeGoalCards(
            isConnected: isConnected,
            totalAgents: totalAgents,
            activeAgents: activeAgentIDs.count,
            trackedMemoryAgents: trackedMemoryAgentIDs.count,
            completedExecutions: completedResults.count,
            failedExecutions: failedResults.count,
            warningLogCount: warningLogs.count,
            errorLogCount: errorLogs.count
        )

        let resultBucketsByAgentID = Dictionary(grouping: executionResults, by: \.agentID)
        let logBucketsByAgentID = Dictionary(grouping: executionLogs.compactMap { entry -> (UUID, ExecutionLogEntry)? in
            guard let nodeID = entry.nodeID, let agentID = nodeToAgent[nodeID] else { return nil }
            return (agentID, entry)
        }, by: \.0)

        let agentRows: [OpsAgentHealthRow] = projectAgents
            .map { agent in
                let agentResults = resultBucketsByAgentID[agent.id] ?? []
                let agentLogs = (logBucketsByAgentID[agent.id] ?? []).map(\.1)
                let completedCount = agentResults.filter { $0.status == .completed }.count
                let failedCount = agentResults.filter { $0.status == .failed }.count
                let hasErrors = agentLogs.contains(where: { $0.level == .error }) || failedCount > 0
                let isActive = activeAgentIDs.contains(agent.id)
                let hasTrackedMemory = trackedMemoryAgentIDs.contains(agent.id)
                let averageDuration = agentResults.compactMap(\.duration).average
                let lastActivityAt = agentResults
                    .compactMap { $0.completedAt ?? $0.startedAt }
                    .max()

                return OpsAgentHealthRow(
                    id: agent.id,
                    agentName: agent.name,
                    stateText: makeStateText(isActive: isActive, hasErrors: hasErrors, hasTrackedMemory: hasTrackedMemory),
                    status: makeAgentStatus(isActive: isActive, hasErrors: hasErrors, hasTrackedMemory: hasTrackedMemory),
                    completedCount: completedCount,
                    failedCount: failedCount,
                    averageDuration: averageDuration,
                    lastActivityAt: lastActivityAt,
                    hasTrackedMemory: hasTrackedMemory
                )
            }
            .sorted { lhs, rhs in
                lhs.agentName.localizedCaseInsensitiveCompare(rhs.agentName) == .orderedAscending
            }

        let traceRows = executionResults
            .sorted { $0.startedAt > $1.startedAt }
            .prefix(10)
            .map { result in
                OpsTraceSummaryRow(
                    id: result.id,
                    agentName: projectAgents.first(where: { $0.id == result.agentID })?.name ?? "Unknown Agent",
                    status: result.status,
                    duration: result.duration,
                    startedAt: result.startedAt,
                    routingAction: result.routingAction,
                    outputType: result.outputType,
                    previewText: result.output.compactSingleLinePreview(limit: 160)
                )
            }

        let dailyActivity = makeDailyActivity(
            executionResults: executionResults,
            executionLogs: executionLogs
        )

        let persistenceSummary = store.synchronize(
            project: project,
            totalAgents: totalAgents,
            activeAgents: activeAgentIDs.count,
            trackedMemoryAgents: trackedMemoryAgentIDs.count,
            completedExecutions: completedResults.count,
            failedExecutions: failedResults.count,
            warningLogCount: warningLogs.count,
            errorLogCount: errorLogs.count,
            agentRows: agentRows,
            executionResults: executionResults,
            agentNamesByID: Dictionary(uniqueKeysWithValues: projectAgents.map { ($0.id, $0.name) }),
            isConnected: isConnected
        )

        snapshot = OpsAnalyticsSnapshot(
            generatedAt: Date(),
            totalAgents: totalAgents,
            activeAgents: activeAgentIDs.count,
            trackedMemoryAgents: trackedMemoryAgentIDs.count,
            completedExecutions: completedResults.count,
            failedExecutions: failedResults.count,
            warningLogCount: warningLogs.count,
            errorLogCount: errorLogs.count,
            averageExecutionDuration: averageDuration,
            goalCards: goalCards,
            dailyActivity: persistenceSummary?.dailyActivity ?? dailyActivity,
            historicalSeries: persistenceSummary?.historicalSeries ?? [],
            agentRows: agentRows,
            traceRows: persistenceSummary?.traceRows ?? traceRows
        )
    }

    func traceDetail(projectID: UUID, traceID: UUID) -> OpsTraceDetail? {
        store.loadTraceDetail(projectID: projectID, spanID: traceID)
    }

    private func makeGoalCards(
        isConnected: Bool,
        totalAgents: Int,
        activeAgents: Int,
        trackedMemoryAgents: Int,
        completedExecutions: Int,
        failedExecutions: Int,
        warningLogCount: Int,
        errorLogCount: Int
    ) -> [OpsGoalCard] {
        let totalExecutions = completedExecutions + failedExecutions
        let reliabilityRate = totalExecutions > 0 ? Double(completedExecutions) / Double(totalExecutions) : nil
        let engagementRate = totalAgents > 0 ? Double(activeAgents) / Double(totalAgents) : nil
        let memoryRate = totalAgents > 0 ? Double(trackedMemoryAgents) / Double(totalAgents) : nil

        return [
            OpsGoalCard(
                id: "openclaw_readiness",
                title: "OpenClaw Readiness",
                valueText: isConnected ? "Connected" : "Offline",
                detailText: "\(activeAgents) active agents visible",
                status: isConnected ? .healthy : .critical
            ),
            OpsGoalCard(
                id: "workflow_reliability",
                title: "Workflow Reliability",
                valueText: reliabilityRate.map { "\($0.percentageString)" } ?? "No data",
                detailText: "\(completedExecutions) completed / \(failedExecutions) failed",
                status: makeRateStatus(reliabilityRate, healthy: 0.9, warning: 0.75)
            ),
            OpsGoalCard(
                id: "agent_engagement",
                title: "Agent Engagement",
                valueText: totalAgents > 0 ? "\(activeAgents)/\(totalAgents)" : "No agents",
                detailText: engagementRate.map { "\($0.percentageString) currently active" } ?? "Create agents to measure activity",
                status: makeRateStatus(engagementRate, healthy: 0.6, warning: 0.3)
            ),
            OpsGoalCard(
                id: "memory_discipline",
                title: "Memory Discipline",
                valueText: memoryRate.map { "\($0.percentageString)" } ?? "No agents",
                detailText: "\(trackedMemoryAgents) agents with tracked memory",
                status: makeRateStatus(memoryRate, healthy: 0.8, warning: 0.5)
            ),
            OpsGoalCard(
                id: "error_budget",
                title: "Error Budget",
                valueText: "\(errorLogCount)",
                detailText: "\(warningLogCount) warnings in recent runtime logs",
                status: makeErrorBudgetStatus(errorCount: errorLogCount, warningCount: warningLogCount)
            )
        ]
    }

    private func makeDailyActivity(
        executionResults: [ExecutionResult],
        executionLogs: [ExecutionLogEntry]
    ) -> [OpsDailyActivityPoint] {
        var completedByDay: [Date: Int] = [:]
        var failedByDay: [Date: Int] = [:]
        var errorsByDay: [Date: Int] = [:]

        for result in executionResults {
            let day = calendar.startOfDay(for: result.startedAt)
            switch result.status {
            case .completed:
                completedByDay[day, default: 0] += 1
            case .failed:
                failedByDay[day, default: 0] += 1
            default:
                break
            }
        }

        for entry in executionLogs where entry.level == .error {
            let day = calendar.startOfDay(for: entry.timestamp)
            errorsByDay[day, default: 0] += 1
        }

        let allDays = Set(completedByDay.keys)
            .union(failedByDay.keys)
            .union(errorsByDay.keys)
        let sortedDays = allDays.sorted()

        return sortedDays.suffix(14).map { day in
            OpsDailyActivityPoint(
                date: day,
                completedCount: completedByDay[day, default: 0],
                failedCount: failedByDay[day, default: 0],
                errorCount: errorsByDay[day, default: 0]
            )
        }
    }

    private func makeActiveAgentIDs(
        project: MAProject,
        tasks: [Task],
        activeAgents: [UUID: OpenClawManager.ActiveAgentRuntime],
        isConnected: Bool
    ) -> Set<UUID> {
        guard isConnected else { return [] }

        let runningTaskAgentIDs = Set(
            tasks
                .filter { $0.status == .inProgress }
                .compactMap(\.assignedAgentID)
        )

        let runtimeAgentIDs = Set(
            project.runtimeState.agentStates.compactMap { key, value -> UUID? in
                let normalized = value.lowercased()
                guard normalized.contains("running")
                        || normalized.contains("queued")
                        || normalized.contains("active")
                        || normalized.contains("reload"),
                      let id = UUID(uuidString: key) else {
                    return nil
                }
                return id
            }
        )

        let openClawAgentIDs: Set<UUID> = Set(
            activeAgents.compactMap { agentID, runtime in
                let normalized = runtime.status.lowercased()
                guard normalized.contains("running")
                        || normalized.contains("active")
                        || normalized.contains("reload") else {
                    return nil
                }
                return agentID
            }
        )

        return runningTaskAgentIDs
            .union(runtimeAgentIDs)
            .union(openClawAgentIDs)
    }

    private func makeTrackedMemoryAgentIDs(project: MAProject) -> Set<UUID> {
        let explicitBackups = Set(project.memoryData.agentMemories.map(\.agentID))
        let configuredPaths = Set(project.agents.compactMap { agent -> UUID? in
            let path = agent.openClawDefinition.memoryBackupPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return path.isEmpty ? nil : agent.id
        })
        return explicitBackups.union(configuredPaths)
    }

    private func makeRateStatus(_ rate: Double?, healthy: Double, warning: Double) -> OpsHealthStatus {
        guard let rate else { return .neutral }
        if rate >= healthy { return .healthy }
        if rate >= warning { return .warning }
        return .critical
    }

    private func makeErrorBudgetStatus(errorCount: Int, warningCount: Int) -> OpsHealthStatus {
        if errorCount == 0 && warningCount == 0 { return .healthy }
        if errorCount <= 2 { return .warning }
        return .critical
    }

    private func makeAgentStatus(isActive: Bool, hasErrors: Bool, hasTrackedMemory: Bool) -> OpsHealthStatus {
        if hasErrors { return .critical }
        if isActive { return .healthy }
        if !hasTrackedMemory { return .warning }
        return .neutral
    }

    private func makeStateText(isActive: Bool, hasErrors: Bool, hasTrackedMemory: Bool) -> String {
        if hasErrors { return "Needs Attention" }
        if isActive { return "Active" }
        if !hasTrackedMemory { return "Memory Untracked" }
        return "Idle"
    }
}

private extension Array where Element == TimeInterval {
    var average: TimeInterval? {
        guard !isEmpty else { return nil }
        return reduce(0, +) / Double(count)
    }
}

private extension Double {
    var percentageString: String {
        "\(Int((self * 100).rounded()))%"
    }
}

extension String {
    func compactSingleLinePreview(limit: Int) -> String {
        let collapsed = replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !collapsed.isEmpty else { return "No output" }
        guard collapsed.count > limit else { return collapsed }
        return String(collapsed.prefix(limit)) + "..."
    }
}
