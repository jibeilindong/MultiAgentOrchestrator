import Foundation

struct OpsCenterProjectionOverviewDocument: Codable {
    let projectID: UUID
    let generatedAt: Date
    let workflowCount: Int
    let nodeCount: Int
    let agentCount: Int
    let taskCount: Int
    let messageCount: Int
    let executionResultCount: Int
    let completedExecutionCount: Int
    let failedExecutionCount: Int
    let warningLogCount: Int
    let errorLogCount: Int
    let pendingApprovalCount: Int
}

struct OpsCenterProjectionTraceEntry: Codable {
    let executionID: UUID
    let nodeID: UUID
    let agentID: UUID
    let sessionID: String?
    let status: ExecutionStatus
    let outputType: ExecutionOutputType
    let startedAt: Date
    let completedAt: Date?
    let duration: TimeInterval?
    let protocolRepairCount: Int
    let previewText: String
}

struct OpsCenterProjectionTraceDocument: Codable {
    let projectID: UUID
    let generatedAt: Date
    let traces: [OpsCenterProjectionTraceEntry]
}

struct OpsCenterProjectionAnomalyEntry: Codable {
    let id: String
    let source: String
    let severity: String
    let message: String
    let nodeID: UUID?
    let agentID: UUID?
    let sessionID: String?
    let timestamp: Date
}

struct OpsCenterProjectionAnomalyDocument: Codable {
    let projectID: UUID
    let generatedAt: Date
    let anomalies: [OpsCenterProjectionAnomalyEntry]
}

struct OpsCenterProjectionWorkflowLiveRunEntry: Codable {
    let workflowID: UUID
    let workflowName: String
    let sessionCount: Int
    let activeSessionCount: Int
    let activeNodeCount: Int
    let failedNodeCount: Int
    let waitingApprovalNodeCount: Int
    let lastUpdatedAt: Date?
}

struct OpsCenterProjectionLiveRunDocument: Codable {
    let projectID: UUID
    let generatedAt: Date
    let runtimeSessionID: String
    let activeSessionCount: Int
    let totalSessionCount: Int
    let queuedDispatchCount: Int
    let inflightDispatchCount: Int
    let failedDispatchCount: Int
    let waitingApprovalCount: Int
    let latestErrorText: String?
    let activeWorkflowCount: Int
    let workflows: [OpsCenterProjectionWorkflowLiveRunEntry]
}

struct OpsCenterProjectionSessionEntry: Codable {
    let sessionID: String
    let workflowIDs: [String]
    let messageCount: Int
    let taskCount: Int
    let eventCount: Int
    let dispatchCount: Int
    let receiptCount: Int
    let queuedDispatchCount: Int
    let inflightDispatchCount: Int
    let completedDispatchCount: Int
    let failedDispatchCount: Int
    let latestFailureText: String?
    let lastUpdatedAt: Date?
    let isProjectRuntimeSession: Bool
}

struct OpsCenterProjectionSessionsDocument: Codable {
    let projectID: UUID
    let generatedAt: Date
    let sessions: [OpsCenterProjectionSessionEntry]
}

struct OpsCenterProjectionNodeRuntimeEntry: Codable {
    let workflowID: UUID
    let workflowName: String
    let nodeID: UUID
    let title: String
    let agentID: UUID?
    let agentName: String?
    let status: String
    let incomingEdgeCount: Int
    let outgoingEdgeCount: Int
    let relatedSessionIDs: [String]
    let queuedDispatchCount: Int
    let inflightDispatchCount: Int
    let completedDispatchCount: Int
    let failedDispatchCount: Int
    let waitingApprovalCount: Int
    let receiptCount: Int
    let averageDuration: TimeInterval?
    let lastUpdatedAt: Date?
    let latestDetail: String?
}

struct OpsCenterProjectionNodesRuntimeDocument: Codable {
    let projectID: UUID
    let generatedAt: Date
    let nodes: [OpsCenterProjectionNodeRuntimeEntry]
}

struct OpsCenterProjectionThreadEntry: Codable {
    let threadID: String
    let sessionID: String
    let workflowID: UUID?
    let workflowName: String?
    let entryAgentName: String?
    let participantNames: [String]
    let status: String
    let startedAt: Date?
    let lastUpdatedAt: Date?
    let messageCount: Int
    let taskCount: Int
    let pendingApprovalCount: Int
    let blockedTaskCount: Int
    let activeTaskCount: Int
    let completedTaskCount: Int
    let failedMessageCount: Int
}

struct OpsCenterProjectionThreadsDocument: Codable {
    let projectID: UUID
    let generatedAt: Date
    let threads: [OpsCenterProjectionThreadEntry]
}

struct OpsCenterProjectionMetricPoint: Codable {
    let date: Date
    let value: Double
}

struct OpsCenterProjectionMetricSeries: Codable {
    let metricID: String
    let points: [OpsCenterProjectionMetricPoint]

    func historySeries() -> OpsMetricHistorySeries? {
        guard let metric = OpsHistoryMetric(rawValue: metricID) else { return nil }
        return OpsMetricHistorySeries(
            metric: metric,
            points: points.map { OpsMetricHistoryPoint(date: $0.date, value: $0.value) }
        )
    }
}

struct OpsCenterProjectionScopedAnomalyEntry: Codable {
    let id: String
    let title: String
    let sourceLabel: String
    let detailText: String
    let fullDetailText: String
    let occurredAt: Date
    let status: String
    let statusText: String
    let sourceService: String?
    let linkedSpanID: UUID?
    let relatedRunID: String?
    let relatedJobID: String?
    let relatedSourcePath: String?

    func anomalyRow() -> OpsAnomalyRow {
        OpsAnomalyRow(
            id: id,
            title: title,
            sourceLabel: sourceLabel,
            detailText: detailText,
            fullDetailText: fullDetailText,
            occurredAt: occurredAt,
            status: projectionHealthStatus(from: status),
            statusText: statusText,
            sourceService: sourceService,
            linkedSpanID: linkedSpanID,
            relatedRunID: relatedRunID,
            relatedJobID: relatedJobID,
            relatedSourcePath: relatedSourcePath
        )
    }

    private func projectionHealthStatus(from rawValue: String) -> OpsHealthStatus {
        OpsHealthStatus(rawValue: rawValue) ?? .neutral
    }
}

struct OpsCenterProjectionCronSummary: Codable {
    let successRate: Double
    let successfulRuns: Int
    let failedRuns: Int
    let latestRunAt: Date?

    func summary() -> OpsCronReliabilitySummary {
        OpsCronReliabilitySummary(
            successRate: successRate,
            successfulRuns: successfulRuns,
            failedRuns: failedRuns,
            latestRunAt: latestRunAt
        )
    }
}

struct OpsCenterProjectionCronRunEntry: Codable {
    let id: String
    let cronName: String
    let statusText: String
    let runAt: Date
    let duration: TimeInterval?
    let deliveryStatus: String?
    let summaryText: String
    let jobID: String?
    let runID: String?
    let sourcePath: String?

    func runRow() -> OpsCronRunRow {
        OpsCronRunRow(
            id: id,
            cronName: cronName,
            statusText: statusText,
            runAt: runAt,
            duration: duration,
            deliveryStatus: deliveryStatus,
            summaryText: summaryText,
            jobID: jobID,
            runID: runID,
            sourcePath: sourcePath
        )
    }
}

struct OpsCenterProjectionCronEntry: Codable {
    let cronName: String
    let summary: OpsCenterProjectionCronSummary?
    let historySeries: [OpsCenterProjectionMetricSeries]
    let runs: [OpsCenterProjectionCronRunEntry]
    let anomalies: [OpsCenterProjectionScopedAnomalyEntry]

    func investigation() -> OpsCenterCronInvestigation {
        OpsCenterCronInvestigation(
            cronName: cronName,
            summary: summary?.summary(),
            historySeries: historySeries.compactMap { $0.historySeries() },
            runs: runs.map { $0.runRow() },
            anomalies: anomalies.map { $0.anomalyRow() }
        )
    }
}

struct OpsCenterProjectionCronDocument: Codable {
    let projectID: UUID
    let generatedAt: Date
    let summary: OpsCenterProjectionCronSummary?
    let crons: [OpsCenterProjectionCronEntry]
}

struct OpsCenterProjectionToolSpanEntry: Codable {
    let id: UUID
    let title: String
    let service: String
    let statusText: String
    let agentName: String
    let startedAt: Date
    let duration: TimeInterval?
    let summaryText: String

    func spanRow() -> OpsToolSpanRow {
        OpsToolSpanRow(
            id: id,
            title: title,
            service: service,
            statusText: statusText,
            agentName: agentName,
            startedAt: startedAt,
            duration: duration,
            summaryText: summaryText
        )
    }
}

struct OpsCenterProjectionToolEntry: Codable {
    let toolIdentifier: String
    let historySeries: [OpsCenterProjectionMetricSeries]
    let spans: [OpsCenterProjectionToolSpanEntry]
    let anomalies: [OpsCenterProjectionScopedAnomalyEntry]

    func investigation() -> OpsCenterToolInvestigation {
        OpsCenterToolInvestigation(
            toolIdentifier: toolIdentifier,
            historySeries: historySeries.compactMap { $0.historySeries() },
            spans: spans.map { $0.spanRow() },
            anomalies: anomalies.map { $0.anomalyRow() }
        )
    }
}

struct OpsCenterProjectionToolsDocument: Codable {
    let projectID: UUID
    let generatedAt: Date
    let tools: [OpsCenterProjectionToolEntry]
}

struct OpsCenterProjectionWorkflowHealthEntry: Codable {
    let workflowID: UUID
    let workflowName: String
    let nodeCount: Int
    let edgeCount: Int
    let sessionCount: Int
    let activeNodeCount: Int
    let failedNodeCount: Int
    let waitingApprovalNodeCount: Int
    let completedNodeCount: Int
    let idleNodeCount: Int
    let recentFailureCount: Int
    let pendingApprovalCount: Int
    let lastUpdatedAt: Date?
}

struct OpsCenterProjectionWorkflowHealthDocument: Codable {
    let projectID: UUID
    let generatedAt: Date
    let workflows: [OpsCenterProjectionWorkflowHealthEntry]
}

struct OpsCenterProjectionBundle {
    let projectID: UUID
    let loadedAt: Date
    let overview: OpsCenterProjectionOverviewDocument?
    let traces: OpsCenterProjectionTraceDocument?
    let anomalies: OpsCenterProjectionAnomalyDocument?
    let liveRun: OpsCenterProjectionLiveRunDocument?
    let sessions: OpsCenterProjectionSessionsDocument?
    let nodesRuntime: OpsCenterProjectionNodesRuntimeDocument?
    let threads: OpsCenterProjectionThreadsDocument?
    let cron: OpsCenterProjectionCronDocument?
    let tools: OpsCenterProjectionToolsDocument?
    let workflowHealth: OpsCenterProjectionWorkflowHealthDocument?

    var freshestGeneratedAt: Date? {
        [
            overview?.generatedAt,
            traces?.generatedAt,
            anomalies?.generatedAt,
            liveRun?.generatedAt,
            sessions?.generatedAt,
            nodesRuntime?.generatedAt,
            threads?.generatedAt,
            cron?.generatedAt,
            tools?.generatedAt,
            workflowHealth?.generatedAt
        ]
        .compactMap { $0 }
        .max()
    }

    func liveRunEntry(for workflowID: UUID?) -> OpsCenterProjectionWorkflowLiveRunEntry? {
        guard let workflowID else { return nil }
        return liveRun?.workflows.first(where: { $0.workflowID == workflowID })
    }

    func workflowHealthEntry(for workflowID: UUID?) -> OpsCenterProjectionWorkflowHealthEntry? {
        guard let workflowID else { return nil }
        return workflowHealth?.workflows.first(where: { $0.workflowID == workflowID })
    }

    func sessionSummaries(for workflowID: UUID?) -> [OpsCenterSessionSummary] {
        let scopeID = workflowID?.uuidString
        return (sessions?.sessions ?? [])
            .filter { entry in
                guard let scopeID else { return true }
                return entry.workflowIDs.contains(scopeID)
            }
            .map { entry in
                OpsCenterSessionSummary(
                    sessionID: entry.sessionID,
                    workflowIDs: entry.workflowIDs,
                    eventCount: entry.eventCount,
                    dispatchCount: entry.dispatchCount,
                    receiptCount: entry.receiptCount,
                    queuedDispatchCount: entry.queuedDispatchCount,
                    inflightDispatchCount: entry.inflightDispatchCount,
                    completedDispatchCount: entry.completedDispatchCount,
                    failedDispatchCount: entry.failedDispatchCount,
                    lastUpdatedAt: entry.lastUpdatedAt,
                    latestFailureText: entry.latestFailureText,
                    isPrimaryRuntimeSession: entry.isProjectRuntimeSession
                )
            }
    }

    func nodeSummaries(for workflowID: UUID?) -> [OpsCenterNodeSummary] {
        (nodesRuntime?.nodes ?? [])
            .filter { entry in
                guard let workflowID else { return true }
                return entry.workflowID == workflowID
            }
            .map { entry in
                OpsCenterNodeSummary(
                    id: entry.nodeID,
                    title: entry.title,
                    agentName: entry.agentName,
                    status: runtimeStatus(from: entry.status),
                    incomingEdgeCount: entry.incomingEdgeCount,
                    outgoingEdgeCount: entry.outgoingEdgeCount,
                    lastUpdatedAt: entry.lastUpdatedAt,
                    latestDetail: entry.latestDetail,
                    averageDuration: entry.averageDuration
                )
            }
            .sorted { lhs, rhs in
                if lhs.status == rhs.status {
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
                return projectionStatusRank(lhs.status) < projectionStatusRank(rhs.status)
            }
    }

    func threadEntries(for workflowID: UUID?) -> [OpsCenterProjectionThreadEntry] {
        (threads?.threads ?? [])
            .filter { entry in
                guard let workflowID else { return true }
                return entry.workflowID == workflowID
            }
            .sorted { lhs, rhs in
                if lhs.lastUpdatedAt != rhs.lastUpdatedAt {
                    return (lhs.lastUpdatedAt ?? .distantPast) > (rhs.lastUpdatedAt ?? .distantPast)
                }
                return lhs.threadID < rhs.threadID
            }
    }

    var cronSummary: OpsCronReliabilitySummary? {
        cron?.summary?.summary()
    }

    func cronEntries() -> [OpsCenterProjectionCronEntry] {
        (cron?.crons ?? []).sorted { lhs, rhs in
            let lhsDate = lhs.summary?.latestRunAt ?? lhs.runs.first?.runAt ?? .distantPast
            let rhsDate = rhs.summary?.latestRunAt ?? rhs.runs.first?.runAt ?? .distantPast
            if lhsDate != rhsDate {
                return lhsDate > rhsDate
            }
            return lhs.cronName.localizedCaseInsensitiveCompare(rhs.cronName) == .orderedAscending
        }
    }

    func cronInvestigation(for cronName: String) -> OpsCenterCronInvestigation? {
        cronEntries()
            .first(where: { $0.cronName.caseInsensitiveCompare(cronName) == .orderedSame })
            .map { $0.investigation() }
    }

    func recentCronRuns(limit: Int? = nil) -> [OpsCronRunRow] {
        let runs = cronEntries()
            .flatMap(\.runs)
            .map { $0.runRow() }
            .sorted { lhs, rhs in
                if lhs.runAt != rhs.runAt {
                    return lhs.runAt > rhs.runAt
                }
                return lhs.id > rhs.id
            }
        guard let limit else { return runs }
        return Array(runs.prefix(limit))
    }

    func toolEntries() -> [OpsCenterProjectionToolEntry] {
        (tools?.tools ?? []).sorted { lhs, rhs in
            let lhsDate = lhs.spans.first?.startedAt ?? lhs.anomalies.first?.occurredAt ?? .distantPast
            let rhsDate = rhs.spans.first?.startedAt ?? rhs.anomalies.first?.occurredAt ?? .distantPast
            if lhsDate != rhsDate {
                return lhsDate > rhsDate
            }
            return lhs.toolIdentifier.localizedCaseInsensitiveCompare(rhs.toolIdentifier) == .orderedAscending
        }
    }

    func toolInvestigation(for toolIdentifier: String) -> OpsCenterToolInvestigation? {
        toolEntries()
            .first(where: { $0.toolIdentifier.caseInsensitiveCompare(toolIdentifier) == .orderedSame })
            .map { $0.investigation() }
    }

    private func runtimeStatus(from rawValue: String) -> OpsCenterRuntimeStatus {
        switch rawValue {
        case "queued":
            return .queued
        case "inflight":
            return .inflight
        case "waitingApproval":
            return .waitingApproval
        case "completed":
            return .completed
        case "failed":
            return .failed
        default:
            return .idle
        }
    }

    private func projectionStatusRank(_ status: OpsCenterRuntimeStatus) -> Int {
        switch status {
        case .failed:
            return 0
        case .waitingApproval:
            return 1
        case .inflight:
            return 2
        case .queued:
            return 3
        case .completed:
            return 4
        case .idle:
            return 5
        }
    }
}

enum OpsCenterProjectionStore {
    static func load(projectID: UUID, appSupportRootDirectory: URL) -> OpsCenterProjectionBundle? {
        let fileSystem = ProjectFileSystem.shared
        let decoder = JSONDecoder()

        let overview: OpsCenterProjectionOverviewDocument? = decode(
            OpsCenterProjectionOverviewDocument.self,
            from: fileSystem.analyticsOverviewProjectionURL(for: projectID, under: appSupportRootDirectory),
            decoder: decoder
        )
        let traces: OpsCenterProjectionTraceDocument? = decode(
            OpsCenterProjectionTraceDocument.self,
            from: fileSystem.analyticsTraceProjectionURL(for: projectID, under: appSupportRootDirectory),
            decoder: decoder
        )
        let anomalies: OpsCenterProjectionAnomalyDocument? = decode(
            OpsCenterProjectionAnomalyDocument.self,
            from: fileSystem.analyticsAnomalyProjectionURL(for: projectID, under: appSupportRootDirectory),
            decoder: decoder
        )
        let liveRun: OpsCenterProjectionLiveRunDocument? = decode(
            OpsCenterProjectionLiveRunDocument.self,
            from: fileSystem.analyticsLiveRunProjectionURL(for: projectID, under: appSupportRootDirectory),
            decoder: decoder
        )
        let sessions: OpsCenterProjectionSessionsDocument? = decode(
            OpsCenterProjectionSessionsDocument.self,
            from: fileSystem.analyticsSessionProjectionURL(for: projectID, under: appSupportRootDirectory),
            decoder: decoder
        )
        let nodesRuntime: OpsCenterProjectionNodesRuntimeDocument? = decode(
            OpsCenterProjectionNodesRuntimeDocument.self,
            from: fileSystem.analyticsNodeRuntimeProjectionURL(for: projectID, under: appSupportRootDirectory),
            decoder: decoder
        )
        let threads: OpsCenterProjectionThreadsDocument? = decode(
            OpsCenterProjectionThreadsDocument.self,
            from: fileSystem.analyticsThreadProjectionURL(for: projectID, under: appSupportRootDirectory),
            decoder: decoder
        )
        let cron: OpsCenterProjectionCronDocument? = decode(
            OpsCenterProjectionCronDocument.self,
            from: fileSystem.analyticsCronProjectionURL(for: projectID, under: appSupportRootDirectory),
            decoder: decoder
        )
        let tools: OpsCenterProjectionToolsDocument? = decode(
            OpsCenterProjectionToolsDocument.self,
            from: fileSystem.analyticsToolProjectionURL(for: projectID, under: appSupportRootDirectory),
            decoder: decoder
        )
        let workflowHealth: OpsCenterProjectionWorkflowHealthDocument? = decode(
            OpsCenterProjectionWorkflowHealthDocument.self,
            from: fileSystem.analyticsWorkflowHealthProjectionURL(for: projectID, under: appSupportRootDirectory),
            decoder: decoder
        )

        guard overview != nil
            || traces != nil
            || anomalies != nil
            || liveRun != nil
            || sessions != nil
            || nodesRuntime != nil
            || threads != nil
            || cron != nil
            || tools != nil
            || workflowHealth != nil else {
            return nil
        }

        return OpsCenterProjectionBundle(
            projectID: projectID,
            loadedAt: Date(),
            overview: overview,
            traces: traces,
            anomalies: anomalies,
            liveRun: liveRun,
            sessions: sessions,
            nodesRuntime: nodesRuntime,
            threads: threads,
            cron: cron,
            tools: tools,
            workflowHealth: workflowHealth
        )
    }

    private static func decode<T: Decodable>(_ type: T.Type, from url: URL, decoder: JSONDecoder) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(type, from: data)
    }
}
