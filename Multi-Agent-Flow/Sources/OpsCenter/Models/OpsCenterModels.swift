import Foundation
import SwiftUI

enum OpsCenterConsolePage: String, CaseIterable, Identifiable {
    case liveRun
    case sessions
    case workflowMap
    case history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .liveRun:
            return "Live Run"
        case .sessions:
            return "Sessions"
        case .workflowMap:
            return "Workflow Map"
        case .history:
            return "History"
        }
    }

    var subtitle: String {
        switch self {
        case .liveRun:
            return "Immediate runtime posture and bottlenecks"
        case .sessions:
            return "Session-first execution investigation"
        case .workflowMap:
            return "Runtime state projected onto workflow structure"
        case .history:
            return "Trend and anomaly support layer"
        }
    }

    var systemImage: String {
        switch self {
        case .liveRun:
            return "play.rectangle.on.rectangle"
        case .sessions:
            return "rectangle.stack.badge.person.crop"
        case .workflowMap:
            return "point.3.connected.trianglepath.dotted"
        case .history:
            return "chart.xyaxis.line"
        }
    }
}

enum OpsCenterDisplayMode {
    case fullScreen
    case embedded
}

enum OpsCenterRuntimeStatus: String {
    case idle
    case queued
    case inflight
    case waitingApproval
    case completed
    case failed

    var title: String {
        switch self {
        case .idle:
            return "Idle"
        case .queued:
            return "Queued"
        case .inflight:
            return "Running"
        case .waitingApproval:
            return "Approval"
        case .completed:
            return "Completed"
        case .failed:
            return "Failed"
        }
    }

    var color: Color {
        switch self {
        case .idle:
            return .secondary
        case .queued:
            return .blue
        case .inflight:
            return .orange
        case .waitingApproval:
            return .yellow
        case .completed:
            return .green
        case .failed:
            return .red
        }
    }
}

struct OpsCenterSessionSummary: Identifiable {
    var id: String { sessionID }
    let sessionID: String
    let workflowIDs: [String]
    let eventCount: Int
    let dispatchCount: Int
    let receiptCount: Int
    let queuedDispatchCount: Int
    let inflightDispatchCount: Int
    let completedDispatchCount: Int
    let failedDispatchCount: Int
    let lastUpdatedAt: Date?
    let latestFailureText: String?
    let isPrimaryRuntimeSession: Bool
}

struct OpsCenterNodeSummary: Identifiable {
    let id: UUID
    let title: String
    let agentName: String?
    let status: OpsCenterRuntimeStatus
    let incomingEdgeCount: Int
    let outgoingEdgeCount: Int
    let lastUpdatedAt: Date?
    let latestDetail: String?
    let averageDuration: TimeInterval?
}

struct OpsCenterEdgeSummary: Identifiable {
    let id: UUID
    let title: String
    let fromTitle: String
    let toTitle: String
    let activityCount: Int
    let requiresApproval: Bool
}

struct OpsCenterLiveRunSnapshot {
    let generatedAt: Date
    let workflowName: String
    let activeSessionCount: Int
    let totalSessionCount: Int
    let queuedDispatchCount: Int
    let inflightDispatchCount: Int
    let failedDispatchCount: Int
    let waitingApprovalCount: Int
    let latestErrorText: String?
    let nodeSummaries: [OpsCenterNodeSummary]
    let edgeSummaries: [OpsCenterEdgeSummary]
    let sessionSummaries: [OpsCenterSessionSummary]

    static let empty = OpsCenterLiveRunSnapshot(
        generatedAt: .distantPast,
        workflowName: "Workflow",
        activeSessionCount: 0,
        totalSessionCount: 0,
        queuedDispatchCount: 0,
        inflightDispatchCount: 0,
        failedDispatchCount: 0,
        waitingApprovalCount: 0,
        latestErrorText: nil,
        nodeSummaries: [],
        edgeSummaries: [],
        sessionSummaries: []
    )
}

struct OpsCenterDispatchDigest: Identifiable {
    let id: String
    let sourceName: String
    let targetName: String
    let summary: String
    let status: RuntimeDispatchStatus
    let sessionID: String?
    let updatedAt: Date
    let errorText: String?
}

struct OpsCenterReceiptDigest: Identifiable {
    let id: UUID
    let nodeTitle: String
    let agentName: String?
    let status: ExecutionStatus
    let outputType: ExecutionOutputType
    let sessionID: String?
    let summary: String
    let duration: TimeInterval?
    let timestamp: Date
}

struct OpsCenterEventDigest: Identifiable {
    let id: String
    let eventType: OpenClawRuntimeEventType
    let participants: String
    let summary: String
    let sessionID: String?
    let timestamp: Date
}

struct OpsCenterMessageDigest: Identifiable {
    let id: UUID
    let routeTitle: String
    let summary: String
    let status: MessageStatus
    let timestamp: Date
}

struct OpsCenterTaskDigest: Identifiable {
    let id: UUID
    let title: String
    let summary: String
    let status: TaskStatus
    let priority: TaskPriority
    let timestamp: Date
}

struct OpsCenterSessionInvestigation: Identifiable {
    var id: String { session.sessionID }
    let session: OpsCenterSessionSummary
    let relatedNodes: [OpsCenterNodeSummary]
    let events: [OpsCenterEventDigest]
    let dispatches: [OpsCenterDispatchDigest]
    let receipts: [OpsCenterReceiptDigest]
    let messages: [OpsCenterMessageDigest]
    let tasks: [OpsCenterTaskDigest]
}

struct OpsCenterNodeInvestigation: Identifiable {
    var id: UUID { node.id }
    let workflowName: String
    let node: OpsCenterNodeSummary
    let relatedSessions: [OpsCenterSessionSummary]
    let incomingEdges: [OpsCenterEdgeSummary]
    let outgoingEdges: [OpsCenterEdgeSummary]
    let events: [OpsCenterEventDigest]
    let dispatches: [OpsCenterDispatchDigest]
    let receipts: [OpsCenterReceiptDigest]
    let messages: [OpsCenterMessageDigest]
    let tasks: [OpsCenterTaskDigest]
}

struct OpsCenterRouteInvestigation: Identifiable {
    var id: UUID { edge.id }
    let workflowName: String
    let edge: OpsCenterEdgeSummary
    let upstreamNode: OpsCenterNodeSummary?
    let downstreamNode: OpsCenterNodeSummary?
    let relatedSessions: [OpsCenterSessionSummary]
    let events: [OpsCenterEventDigest]
    let dispatches: [OpsCenterDispatchDigest]
    let receipts: [OpsCenterReceiptDigest]
    let messages: [OpsCenterMessageDigest]
    let tasks: [OpsCenterTaskDigest]
}

struct OpsCenterThreadInvestigation: Identifiable {
    var id: String { threadID }
    let threadID: String
    let sessionID: String
    let workflowID: UUID?
    let workflowName: String
    let status: String
    let startedAt: Date?
    let lastUpdatedAt: Date?
    let entryAgentName: String?
    let participantNames: [String]
    let pendingApprovalCount: Int
    let relatedSession: OpsCenterSessionSummary?
    let relatedNodes: [OpsCenterNodeSummary]
    let events: [OpsCenterEventDigest]
    let dispatches: [OpsCenterDispatchDigest]
    let receipts: [OpsCenterReceiptDigest]
    let messages: [OpsCenterMessageDigest]
    let tasks: [OpsCenterTaskDigest]
}

enum OpsCenterInvestigationTarget: Identifiable {
    case session(OpsCenterSessionInvestigation)
    case node(OpsCenterNodeInvestigation)
    case route(OpsCenterRouteInvestigation)
    case thread(OpsCenterThreadInvestigation)

    var id: String {
        switch self {
        case let .session(investigation):
            return "session-\(investigation.id)"
        case let .node(investigation):
            return "node-\(investigation.id.uuidString)"
        case let .route(investigation):
            return "route-\(investigation.id.uuidString)"
        case let .thread(investigation):
            return "thread-\(investigation.id)"
        }
    }

    var title: String {
        switch self {
        case let .session(investigation):
            return investigation.session.sessionID
        case let .node(investigation):
            return investigation.node.title
        case let .route(investigation):
            return "\(investigation.edge.fromTitle) -> \(investigation.edge.toTitle)"
        case let .thread(investigation):
            return investigation.threadID
        }
    }

    var subtitle: String {
        switch self {
        case .session:
            return "Session Investigation"
        case let .node(investigation):
            return "\(investigation.workflowName) • Node Investigation"
        case let .route(investigation):
            return "\(investigation.workflowName) • Route Investigation"
        case let .thread(investigation):
            return "\(investigation.workflowName) • Thread Investigation"
        }
    }
}

enum OpsCenterSnapshotBuilder {
    static func buildLiveRunSnapshot(
        project: MAProject?,
        workflow: Workflow?,
        tasks: [Task],
        messages: [Message],
        executionResults: [ExecutionResult]
    ) -> OpsCenterLiveRunSnapshot {
        guard let project, let workflow else { return .empty }

        let runtimeState = project.runtimeState
        let dispatches = runtimeState.dispatchQueue
            + runtimeState.inflightDispatches
            + runtimeState.completedDispatches
            + runtimeState.failedDispatches
        let agentNamesByID = Dictionary(uniqueKeysWithValues: project.agents.map { ($0.id, $0.name) })
        let nodeByID = Dictionary(uniqueKeysWithValues: workflow.nodes.map { ($0.id, $0) })

        let sessionSummaries = buildSessionSummaries(
            project: project,
            workflow: workflow,
            tasks: tasks,
            messages: messages,
            executionResults: executionResults
        )

        let nodeSummaries = workflow.nodes.map { node in
            let latestReceipt = executionResults
                .filter { $0.nodeID == node.id }
                .sorted { ($0.completedAt ?? $0.startedAt) > ($1.completedAt ?? $1.startedAt) }
                .first

            let relatedDispatches = relatedDispatches(
                for: node,
                in: dispatches
            )

            let status = resolveStatus(
                node: node,
                relatedDispatches: relatedDispatches,
                latestReceipt: latestReceipt
            )

            let lastUpdatedAt = (
                relatedDispatches.map(\.updatedAt)
                + [latestReceipt?.completedAt, latestReceipt?.startedAt].compactMap { $0 }
            ).max()

            let averageDuration: TimeInterval? = {
                let durations = executionResults
                    .filter { $0.nodeID == node.id }
                    .compactMap(\.duration)
                guard !durations.isEmpty else { return nil }
                return durations.reduce(0, +) / Double(durations.count)
            }()

            return OpsCenterNodeSummary(
                id: node.id,
                title: node.title,
                agentName: node.agentID.flatMap { agentNamesByID[$0] },
                status: status,
                incomingEdgeCount: workflow.edges.filter { $0.toNodeID == node.id }.count,
                outgoingEdgeCount: workflow.edges.filter { $0.fromNodeID == node.id }.count,
                lastUpdatedAt: lastUpdatedAt,
                latestDetail: latestDetailText(receipt: latestReceipt, dispatches: relatedDispatches),
                averageDuration: averageDuration
            )
        }

        let edgeSummaries = workflow.edges.map { edge in
            let activityCount = dispatches.reduce(into: 0) { partial, dispatch in
                guard let fromAgentID = nodeByID[edge.fromNodeID]?.agentID,
                      let toAgentID = nodeByID[edge.toNodeID]?.agentID else {
                    return
                }

                if normalizedUUIDString(dispatch.sourceAgentID) == fromAgentID.uuidString.lowercased()
                    && normalizedUUIDString(dispatch.targetAgentID) == toAgentID.uuidString.lowercased() {
                    partial += 1
                }
            }

            return OpsCenterEdgeSummary(
                id: edge.id,
                title: edge.label.isEmpty ? "Path" : edge.label,
                fromTitle: nodeByID[edge.fromNodeID]?.title ?? "Unknown",
                toTitle: nodeByID[edge.toNodeID]?.title ?? "Unknown",
                activityCount: activityCount,
                requiresApproval: edge.requiresApproval
            )
        }

        let activeSessionCount = sessionSummaries.filter {
            $0.queuedDispatchCount > 0 || $0.inflightDispatchCount > 0
        }.count

        let latestErrorText = (
            runtimeState.failedDispatches.compactMap(\.errorMessage)
            + executionResults.filter { $0.status == .failed }.map(\.summaryText)
        )
        .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })

        let waitingApprovalCount = messages.filter { $0.status == .waitingForApproval }.count
            + runtimeState.inflightDispatches.filter { $0.status == .waitingApproval }.count

        return OpsCenterLiveRunSnapshot(
            generatedAt: Date(),
            workflowName: workflow.name,
            activeSessionCount: activeSessionCount,
            totalSessionCount: sessionSummaries.count,
            queuedDispatchCount: runtimeState.dispatchQueue.count,
            inflightDispatchCount: runtimeState.inflightDispatches.count,
            failedDispatchCount: runtimeState.failedDispatches.count,
            waitingApprovalCount: waitingApprovalCount,
            latestErrorText: latestErrorText,
            nodeSummaries: nodeSummaries.sorted { lhs, rhs in
                if lhs.status == rhs.status {
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
                return severityRank(lhs.status) < severityRank(rhs.status)
            },
            edgeSummaries: edgeSummaries.sorted { lhs, rhs in
                if lhs.activityCount == rhs.activityCount {
                    return lhs.fromTitle.localizedCaseInsensitiveCompare(rhs.fromTitle) == .orderedAscending
                }
                return lhs.activityCount > rhs.activityCount
            },
            sessionSummaries: sessionSummaries
        )
    }

    static func buildSessionSummaries(
        project: MAProject?,
        workflow: Workflow?,
        tasks: [Task],
        messages: [Message],
        executionResults: [ExecutionResult]
    ) -> [OpsCenterSessionSummary] {
        guard let project else { return [] }

        let runtimeState = project.runtimeState
        let dispatches = allDispatches(from: runtimeState)
        let sessionIDs = Set([runtimeState.sessionID])
            .union(messages.compactMap { normalizedSessionID($0.metadata["workbenchSessionID"]) })
            .union(tasks.compactMap { normalizedSessionID($0.metadata["workbenchSessionID"]) })
            .union(dispatches.compactMap { normalizedSessionID($0.sessionKey) })
            .union(runtimeState.runtimeEvents.compactMap { normalizedSessionID($0.sessionKey) })
            .union(executionResults.compactMap { normalizedSessionID($0.sessionID) })

        let nodeIDsForWorkflow = Set(workflow?.nodes.map(\.id) ?? [])

        return sessionIDs.map { sessionID in
            let sessionDispatches = dispatches.filter { normalizedSessionID($0.sessionKey) == sessionID }
            let sessionEvents = runtimeState.runtimeEvents.filter { normalizedSessionID($0.sessionKey) == sessionID }
            let sessionReceipts = executionResults.filter { normalizedSessionID($0.sessionID) == sessionID }
                .filter { nodeIDsForWorkflow.isEmpty || nodeIDsForWorkflow.contains($0.nodeID) }

            let workflowIDs = Set(
                sessionDispatches.compactMap(\.workflowID)
                    + sessionEvents.compactMap(\.workflowId)
                    + messages.compactMap { message in
                        guard normalizedSessionID(message.metadata["workbenchSessionID"]) == sessionID else { return nil }
                        return normalizedWorkflowID(message.metadata["workflowID"])
                    }
                    + tasks.compactMap { task in
                        guard normalizedSessionID(task.metadata["workbenchSessionID"]) == sessionID else { return nil }
                        return normalizedWorkflowID(task.metadata["workflowID"])
                    }
            )
            .sorted()

            let latestFailureText = (
                sessionDispatches.compactMap(\.errorMessage)
                + sessionReceipts.filter { $0.status == .failed }.map(\.summaryText)
            )
            .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })

            return OpsCenterSessionSummary(
                sessionID: sessionID,
                workflowIDs: workflowIDs,
                eventCount: sessionEvents.count,
                dispatchCount: sessionDispatches.count,
                receiptCount: sessionReceipts.count,
                queuedDispatchCount: sessionDispatches.filter { $0.status == .created || $0.status == .waitingDependency }.count,
                inflightDispatchCount: sessionDispatches.filter {
                    [.dispatched, .accepted, .running, .waitingApproval].contains($0.status)
                }.count,
                completedDispatchCount: sessionDispatches.filter { $0.status == .completed }.count,
                failedDispatchCount: sessionDispatches.filter { $0.status == .failed || $0.status == .aborted || $0.status == .expired }.count,
                lastUpdatedAt: (
                    sessionDispatches.map(\.updatedAt)
                    + sessionEvents.map(\.timestamp)
                    + sessionReceipts.compactMap { $0.completedAt ?? $0.startedAt }
                ).max(),
                latestFailureText: latestFailureText,
                isPrimaryRuntimeSession: normalizedSessionID(runtimeState.sessionID) == sessionID
            )
        }
        .sorted { lhs, rhs in
            if lhs.isPrimaryRuntimeSession != rhs.isPrimaryRuntimeSession {
                return lhs.isPrimaryRuntimeSession
            }
            return (lhs.lastUpdatedAt ?? .distantPast) > (rhs.lastUpdatedAt ?? .distantPast)
        }
    }

    static func buildSessionInvestigation(
        project: MAProject?,
        workflow: Workflow?,
        sessionID: String,
        tasks: [Task],
        messages: [Message],
        executionResults: [ExecutionResult]
    ) -> OpsCenterSessionInvestigation? {
        guard let project,
              let normalizedTargetSessionID = normalizedSessionID(sessionID) else {
            return nil
        }

        let snapshot = buildLiveRunSnapshot(
            project: project,
            workflow: workflow,
            tasks: tasks,
            messages: messages,
            executionResults: executionResults
        )
        guard let session = snapshot.sessionSummaries.first(where: { $0.sessionID == normalizedTargetSessionID }) else {
            return nil
        }

        let agentNamesByID = Dictionary(uniqueKeysWithValues: project.agents.map { ($0.id, $0.name) })
        let nodeTitlesByID = Dictionary(uniqueKeysWithValues: workflow?.nodes.map { ($0.id, $0.title) } ?? [])
        let sessionDispatches = allDispatches(from: project.runtimeState)
            .filter { normalizedSessionID($0.sessionKey) == normalizedTargetSessionID }
        let sessionEvents = project.runtimeState.runtimeEvents
            .filter { normalizedSessionID($0.sessionKey) == normalizedTargetSessionID }
        let sessionReceipts = executionResults
            .filter { normalizedSessionID($0.sessionID) == normalizedTargetSessionID }
            .filter { result in
                guard let workflow else { return true }
                return workflow.nodes.contains(where: { $0.id == result.nodeID })
            }
        let sessionMessages = messages
            .filter { normalizedSessionID($0.metadata["workbenchSessionID"]) == normalizedTargetSessionID }
            .filter { matchesWorkflow($0.metadata, workflowID: workflow?.id) }
        let sessionTasks = tasks
            .filter { normalizedSessionID($0.metadata["workbenchSessionID"]) == normalizedTargetSessionID }
            .filter { matchesWorkflow($0.metadata, workflowID: workflow?.id) }

        let relatedNodeIDs = Set(
            sessionDispatches.compactMap { uuid(from: $0.nodeID) }
                + sessionEvents.compactMap { uuid(from: $0.nodeId) }
                + sessionReceipts.map(\.nodeID)
                + sessionTasks.compactMap(\.workflowNodeID)
        )

        return OpsCenterSessionInvestigation(
            session: session,
            relatedNodes: snapshot.nodeSummaries.filter { relatedNodeIDs.contains($0.id) },
            events: buildEventDigests(sessionEvents),
            dispatches: buildDispatchDigests(sessionDispatches, agentNamesByID: agentNamesByID),
            receipts: buildReceiptDigests(
                sessionReceipts,
                nodeTitlesByID: nodeTitlesByID,
                agentNamesByID: agentNamesByID
            ),
            messages: buildMessageDigests(sessionMessages, agentNamesByID: agentNamesByID),
            tasks: buildTaskDigests(sessionTasks, agentNamesByID: agentNamesByID)
        )
    }

    static func buildNodeInvestigation(
        project: MAProject?,
        workflow: Workflow?,
        nodeID: UUID,
        tasks: [Task],
        messages: [Message],
        executionResults: [ExecutionResult]
    ) -> OpsCenterNodeInvestigation? {
        guard let project,
              let workflow,
              let workflowNode = workflow.nodes.first(where: { $0.id == nodeID }) else {
            return nil
        }

        let snapshot = buildLiveRunSnapshot(
            project: project,
            workflow: workflow,
            tasks: tasks,
            messages: messages,
            executionResults: executionResults
        )
        guard let node = snapshot.nodeSummaries.first(where: { $0.id == nodeID }) else {
            return nil
        }

        let allDispatches = allDispatches(from: project.runtimeState)
        let agentNamesByID = Dictionary(uniqueKeysWithValues: project.agents.map { ($0.id, $0.name) })
        let nodeTitlesByID = Dictionary(uniqueKeysWithValues: workflow.nodes.map { ($0.id, $0.title) })
        let edgeSummaryByID = Dictionary(uniqueKeysWithValues: snapshot.edgeSummaries.map { ($0.id, $0) })
        let relatedDispatches = relatedDispatches(for: workflowNode, in: allDispatches)
        let relatedReceipts = executionResults.filter { $0.nodeID == nodeID }
        let relatedTasks = tasks
            .filter { task in
                task.workflowNodeID == nodeID
                    || (workflowNode.agentID != nil && task.assignedAgentID == workflowNode.agentID)
            }
            .filter { task in
                task.workflowNodeID == nodeID || matchesWorkflow(task.metadata, workflowID: workflow.id)
            }

        let relatedSessionIDs = Set(
            relatedDispatches.compactMap { normalizedSessionID($0.sessionKey) }
                + relatedReceipts.compactMap { normalizedSessionID($0.sessionID) }
                + relatedTasks.compactMap { normalizedSessionID($0.metadata["workbenchSessionID"]) }
        )

        let relatedMessages = messages
            .filter { message in
                if relatedSessionIDs.contains(normalizedSessionID(message.metadata["workbenchSessionID"]) ?? "") {
                    return matchesWorkflow(message.metadata, workflowID: workflow.id)
                }
                guard let agentID = workflowNode.agentID else { return false }
                let touchesAgent = message.fromAgentID == agentID || message.toAgentID == agentID
                return touchesAgent && matchesWorkflow(message.metadata, workflowID: workflow.id)
            }

        let relatedEvents = project.runtimeState.runtimeEvents.filter { event in
            normalizedUUIDString(event.nodeId) == nodeID.uuidString.lowercased()
                || relatedSessionIDs.contains(normalizedSessionID(event.sessionKey) ?? "")
        }

        let relatedSessions = snapshot.sessionSummaries.filter { relatedSessionIDs.contains($0.sessionID) }
        let incomingEdges = workflow.edges
            .filter { $0.toNodeID == nodeID }
            .compactMap { edgeSummaryByID[$0.id] }
        let outgoingEdges = workflow.edges
            .filter { $0.fromNodeID == nodeID }
            .compactMap { edgeSummaryByID[$0.id] }

        return OpsCenterNodeInvestigation(
            workflowName: workflow.name,
            node: node,
            relatedSessions: relatedSessions,
            incomingEdges: incomingEdges,
            outgoingEdges: outgoingEdges,
            events: buildEventDigests(relatedEvents),
            dispatches: buildDispatchDigests(relatedDispatches, agentNamesByID: agentNamesByID),
            receipts: buildReceiptDigests(
                relatedReceipts,
                nodeTitlesByID: nodeTitlesByID,
                agentNamesByID: agentNamesByID
            ),
            messages: buildMessageDigests(relatedMessages, agentNamesByID: agentNamesByID),
            tasks: buildTaskDigests(relatedTasks, agentNamesByID: agentNamesByID)
        )
    }

    static func buildRouteInvestigation(
        project: MAProject?,
        workflow: Workflow?,
        edgeID: UUID,
        tasks: [Task],
        messages: [Message],
        executionResults: [ExecutionResult]
    ) -> OpsCenterRouteInvestigation? {
        guard let project,
              let workflow,
              let edge = workflow.edges.first(where: { $0.id == edgeID }),
              let upstreamWorkflowNode = workflow.nodes.first(where: { $0.id == edge.fromNodeID }),
              let downstreamWorkflowNode = workflow.nodes.first(where: { $0.id == edge.toNodeID }) else {
            return nil
        }

        let snapshot = buildLiveRunSnapshot(
            project: project,
            workflow: workflow,
            tasks: tasks,
            messages: messages,
            executionResults: executionResults
        )
        let edgeSummary = snapshot.edgeSummaries.first(where: { $0.id == edgeID }) ?? OpsCenterEdgeSummary(
            id: edge.id,
            title: edge.label.isEmpty ? "Path" : edge.label,
            fromTitle: upstreamWorkflowNode.title,
            toTitle: downstreamWorkflowNode.title,
            activityCount: 0,
            requiresApproval: edge.requiresApproval
        )

        let allDispatches = allDispatches(from: project.runtimeState)
        let directRouteDispatches = routeDispatches(
            for: edge,
            workflow: workflow,
            in: allDispatches
        )
        let routeSessionIDs = Set(
            directRouteDispatches.compactMap { normalizedSessionID($0.sessionKey) }
        )

        let endpointNodeIDs: Set<UUID> = [upstreamWorkflowNode.id, downstreamWorkflowNode.id]
        let relatedReceipts = executionResults.filter { receipt in
            guard endpointNodeIDs.contains(receipt.nodeID) else { return false }
            guard let sessionID = normalizedSessionID(receipt.sessionID) else {
                return routeSessionIDs.isEmpty
            }
            return routeSessionIDs.isEmpty || routeSessionIDs.contains(sessionID)
        }

        let relatedEvents = project.runtimeState.runtimeEvents.filter { event in
            let eventNodeID = uuid(from: event.nodeId)
            let sessionID = normalizedSessionID(event.sessionKey)
            return endpointNodeIDs.contains(eventNodeID ?? UUID())
                || (sessionID != nil && routeSessionIDs.contains(sessionID!))
        }

        let relatedMessages = messages
            .filter { matchesWorkflow($0.metadata, workflowID: workflow.id) }
            .filter { message in
                guard let sessionID = normalizedSessionID(message.metadata["workbenchSessionID"]) else {
                    return false
                }
                return routeSessionIDs.contains(sessionID)
            }

        let relatedTasks = tasks
            .filter { task in
                if let sessionID = normalizedSessionID(task.metadata["workbenchSessionID"]),
                   routeSessionIDs.contains(sessionID) {
                    return matchesWorkflow(task.metadata, workflowID: workflow.id)
                }
                return false
            }

        let relatedSessions = snapshot.sessionSummaries.filter { routeSessionIDs.contains($0.sessionID) }
        let agentNamesByID = Dictionary(uniqueKeysWithValues: project.agents.map { ($0.id, $0.name) })
        let nodeTitlesByID = Dictionary(uniqueKeysWithValues: workflow.nodes.map { ($0.id, $0.title) })

        return OpsCenterRouteInvestigation(
            workflowName: workflow.name,
            edge: edgeSummary,
            upstreamNode: snapshot.nodeSummaries.first(where: { $0.id == upstreamWorkflowNode.id }),
            downstreamNode: snapshot.nodeSummaries.first(where: { $0.id == downstreamWorkflowNode.id }),
            relatedSessions: relatedSessions,
            events: buildEventDigests(relatedEvents),
            dispatches: buildDispatchDigests(directRouteDispatches, agentNamesByID: agentNamesByID),
            receipts: buildReceiptDigests(
                relatedReceipts,
                nodeTitlesByID: nodeTitlesByID,
                agentNamesByID: agentNamesByID
            ),
            messages: buildMessageDigests(relatedMessages, agentNamesByID: agentNamesByID),
            tasks: buildTaskDigests(relatedTasks, agentNamesByID: agentNamesByID)
        )
    }

    static func buildThreadInvestigation(
        project: MAProject?,
        workflow: Workflow?,
        threadID: String,
        tasks: [Task],
        messages: [Message],
        executionResults: [ExecutionResult]
    ) -> OpsCenterThreadInvestigation? {
        guard let project,
              let normalizedTargetThreadID = normalizedSessionID(threadID) else {
            return nil
        }

        let workbenchMessages = messages
            .filter { $0.metadata["channel"] == "workbench" }
            .filter { normalizedSessionID($0.metadata["workbenchSessionID"]) == normalizedTargetThreadID }
            .filter { matchesWorkflow($0.metadata, workflowID: workflow?.id) }
        let workbenchTasks = tasks
            .filter { $0.metadata["source"] == "workbench" }
            .filter { normalizedSessionID($0.metadata["workbenchSessionID"]) == normalizedTargetThreadID }
            .filter { matchesWorkflow($0.metadata, workflowID: workflow?.id) }

        let sessionInvestigation = buildSessionInvestigation(
            project: project,
            workflow: workflow,
            sessionID: normalizedTargetThreadID,
            tasks: tasks,
            messages: messages,
            executionResults: executionResults
        )

        guard !workbenchMessages.isEmpty
                || !workbenchTasks.isEmpty
                || sessionInvestigation != nil else {
            return nil
        }

        let snapshot = buildLiveRunSnapshot(
            project: project,
            workflow: workflow,
            tasks: tasks,
            messages: messages,
            executionResults: executionResults
        )
        let agentNamesByID = Dictionary(uniqueKeysWithValues: project.agents.map { ($0.id, $0.name) })
        let resolvedWorkflowID = workflow?.id
            ?? workbenchMessages.compactMap { UUID(uuidString: $0.metadata["workflowID"] ?? "") }.first
            ?? workbenchTasks.compactMap { UUID(uuidString: $0.metadata["workflowID"] ?? "") }.first
        let resolvedWorkflowName = workflow?.name
            ?? resolvedWorkflowID.flatMap { workflowID in
                project.workflows.first(where: { $0.id == workflowID })?.name
            }
            ?? "Workbench Thread"
        let entryAgentID = workbenchMessages
            .compactMap { UUID(uuidString: $0.metadata["entryAgentID"] ?? "") }
            .first
            ?? workbenchTasks.compactMap(\.assignedAgentID).first
        let participantNames = Set(
            workbenchMessages.flatMap { [$0.fromAgentID, $0.toAgentID] }
                + workbenchTasks.compactMap(\.assignedAgentID)
        )
        .compactMap { agentNamesByID[$0] }
        .sorted()
        let startedAt = (workbenchMessages.map(\.timestamp) + workbenchTasks.map(\.createdAt)).min()
            ?? sessionInvestigation?.session.lastUpdatedAt
        let taskDates = workbenchTasks.map { $0.completedAt ?? $0.startedAt ?? $0.createdAt }
        let lastUpdatedAt = (workbenchMessages.map(\.timestamp) + taskDates).max()
            ?? sessionInvestigation?.session.lastUpdatedAt

        return OpsCenterThreadInvestigation(
            threadID: normalizedTargetThreadID,
            sessionID: normalizedTargetThreadID,
            workflowID: resolvedWorkflowID,
            workflowName: resolvedWorkflowName,
            status: workbenchThreadStatus(messages: workbenchMessages, tasks: workbenchTasks),
            startedAt: startedAt,
            lastUpdatedAt: lastUpdatedAt,
            entryAgentName: entryAgentID.flatMap { agentNamesByID[$0] },
            participantNames: participantNames,
            pendingApprovalCount: workbenchMessages.filter { $0.status == .waitingForApproval }.count,
            relatedSession: sessionInvestigation?.session ?? snapshot.sessionSummaries.first(where: {
                $0.sessionID == normalizedTargetThreadID
            }),
            relatedNodes: sessionInvestigation?.relatedNodes ?? [],
            events: sessionInvestigation?.events ?? [],
            dispatches: sessionInvestigation?.dispatches ?? [],
            receipts: sessionInvestigation?.receipts ?? [],
            messages: buildMessageDigests(workbenchMessages, agentNamesByID: agentNamesByID),
            tasks: buildTaskDigests(workbenchTasks, agentNamesByID: agentNamesByID)
        )
    }

    private static func resolveStatus(
        node: WorkflowNode,
        relatedDispatches: [RuntimeDispatchRecord],
        latestReceipt: ExecutionResult?
    ) -> OpsCenterRuntimeStatus {
        if relatedDispatches.contains(where: { $0.status == .failed || $0.status == .aborted || $0.status == .expired }) {
            return .failed
        }
        if relatedDispatches.contains(where: { $0.status == .waitingApproval }) {
            return .waitingApproval
        }
        if relatedDispatches.contains(where: { [.running, .accepted, .dispatched].contains($0.status) }) {
            return .inflight
        }
        if relatedDispatches.contains(where: { [.created, .waitingDependency].contains($0.status) }) {
            return .queued
        }
        if let latestReceipt {
            switch latestReceipt.status {
            case .failed:
                return .failed
            case .completed:
                return .completed
            case .running:
                return .inflight
            case .waiting:
                return .queued
            case .idle:
                return node.type == .start ? .completed : .idle
            }
        }
        return node.type == .start ? .completed : .idle
    }

    private static func relatedDispatches(
        for node: WorkflowNode,
        in dispatches: [RuntimeDispatchRecord]
    ) -> [RuntimeDispatchRecord] {
        dispatches.filter { record in
            normalizedUUIDString(record.nodeID) == node.id.uuidString.lowercased()
                || (node.agentID != nil && normalizedUUIDString(record.targetAgentID) == node.agentID?.uuidString.lowercased())
                || (node.agentID != nil && normalizedUUIDString(record.sourceAgentID) == node.agentID?.uuidString.lowercased())
        }
    }

    private static func routeDispatches(
        for edge: WorkflowEdge,
        workflow: Workflow,
        in dispatches: [RuntimeDispatchRecord]
    ) -> [RuntimeDispatchRecord] {
        guard let upstreamNode = workflow.nodes.first(where: { $0.id == edge.fromNodeID }),
              let downstreamNode = workflow.nodes.first(where: { $0.id == edge.toNodeID }) else {
            return []
        }

        let upstreamAgentID = upstreamNode.agentID?.uuidString.lowercased()
        let downstreamAgentID = downstreamNode.agentID?.uuidString.lowercased()
        let upstreamNodeID = upstreamNode.id.uuidString.lowercased()
        let downstreamNodeID = downstreamNode.id.uuidString.lowercased()

        return dispatches.filter { record in
            let sourceMatches = upstreamAgentID != nil && normalizedUUIDString(record.sourceAgentID) == upstreamAgentID
            let targetMatches = downstreamAgentID != nil && normalizedUUIDString(record.targetAgentID) == downstreamAgentID
            let nodeMatches = normalizedUUIDString(record.nodeID) == downstreamNodeID

            if sourceMatches && targetMatches {
                return true
            }

            if sourceMatches && nodeMatches {
                return true
            }

            if normalizedUUIDString(record.nodeID) == upstreamNodeID && targetMatches {
                return true
            }

            return false
        }
    }

    private static func latestDetailText(receipt: ExecutionResult?, dispatches: [RuntimeDispatchRecord]) -> String? {
        if let error = dispatches.compactMap(\.errorMessage).last,
           !error.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return compactPreview(error)
        }

        if let receipt {
            if !receipt.summaryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return compactPreview(receipt.summaryText)
            }
            if !receipt.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return compactPreview(receipt.output)
            }
        }

        return dispatches.last.map { compactPreview($0.summary) }
    }

    private static func buildDispatchDigests(
        _ dispatches: [RuntimeDispatchRecord],
        agentNamesByID: [UUID: String]
    ) -> [OpsCenterDispatchDigest] {
        dispatches
            .sorted { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return lhs.id > rhs.id
            }
            .map { dispatch in
                OpsCenterDispatchDigest(
                    id: dispatch.id,
                    sourceName: agentName(for: dispatch.sourceAgentID, using: agentNamesByID),
                    targetName: agentName(for: dispatch.targetAgentID, using: agentNamesByID),
                    summary: compactPreview(dispatch.summary, limit: 140),
                    status: dispatch.status,
                    sessionID: normalizedSessionID(dispatch.sessionKey),
                    updatedAt: dispatch.updatedAt,
                    errorText: dispatch.errorMessage.map { compactPreview($0, limit: 140) }
                )
            }
    }

    private static func buildReceiptDigests(
        _ receipts: [ExecutionResult],
        nodeTitlesByID: [UUID: String],
        agentNamesByID: [UUID: String]
    ) -> [OpsCenterReceiptDigest] {
        receipts
            .sorted { lhs, rhs in
                let lhsDate = lhs.completedAt ?? lhs.startedAt
                let rhsDate = rhs.completedAt ?? rhs.startedAt
                if lhsDate != rhsDate {
                    return lhsDate > rhsDate
                }
                return lhs.id.uuidString > rhs.id.uuidString
            }
            .map { receipt in
                OpsCenterReceiptDigest(
                    id: receipt.id,
                    nodeTitle: nodeTitlesByID[receipt.nodeID] ?? "Unknown Node",
                    agentName: agentNamesByID[receipt.agentID],
                    status: receipt.status,
                    outputType: receipt.outputType,
                    sessionID: normalizedSessionID(receipt.sessionID),
                    summary: compactPreview(receipt.summaryText, limit: 160),
                    duration: receipt.duration,
                    timestamp: receipt.completedAt ?? receipt.startedAt
                )
            }
    }

    private static func buildEventDigests(_ events: [OpenClawRuntimeEvent]) -> [OpsCenterEventDigest] {
        events
            .sorted { lhs, rhs in
                if lhs.timestamp != rhs.timestamp {
                    return lhs.timestamp > rhs.timestamp
                }
                return lhs.id > rhs.id
            }
            .map { event in
                OpsCenterEventDigest(
                    id: event.id,
                    eventType: event.eventType,
                    participants: event.participantsText,
                    summary: compactPreview(event.summaryText, limit: 160),
                    sessionID: normalizedSessionID(event.sessionKey),
                    timestamp: event.timestamp
                )
            }
    }

    private static func buildMessageDigests(
        _ messages: [Message],
        agentNamesByID: [UUID: String]
    ) -> [OpsCenterMessageDigest] {
        messages
            .sorted { lhs, rhs in
                if lhs.timestamp != rhs.timestamp {
                    return lhs.timestamp > rhs.timestamp
                }
                return lhs.id.uuidString > rhs.id.uuidString
            }
            .map { message in
                let fromName = agentNamesByID[message.fromAgentID] ?? message.runtimeEvent?.source.agentName ?? "Unknown"
                let toName = agentNamesByID[message.toAgentID] ?? message.runtimeEvent?.target.agentName ?? "Unknown"
                return OpsCenterMessageDigest(
                    id: message.id,
                    routeTitle: "\(fromName) -> \(toName)",
                    summary: compactPreview(message.summaryText, limit: 160),
                    status: message.status,
                    timestamp: message.timestamp
                )
            }
    }

    private static func buildTaskDigests(
        _ tasks: [Task],
        agentNamesByID: [UUID: String]
    ) -> [OpsCenterTaskDigest] {
        tasks
            .sorted { lhs, rhs in
                let lhsDate = lhs.completedAt ?? lhs.startedAt ?? lhs.createdAt
                let rhsDate = rhs.completedAt ?? rhs.startedAt ?? rhs.createdAt
                if lhsDate != rhsDate {
                    return lhsDate > rhsDate
                }
                return lhs.id.uuidString > rhs.id.uuidString
            }
            .map { task in
                let assignedName = task.assignedAgentID.flatMap { agentNamesByID[$0] } ?? "Unassigned"
                let description = task.description.trimmingCharacters(in: .whitespacesAndNewlines)
                let summary = description.isEmpty
                    ? "Assigned to \(assignedName)"
                    : "\(assignedName) • \(compactPreview(description, limit: 140))"
                return OpsCenterTaskDigest(
                    id: task.id,
                    title: task.title,
                    summary: summary,
                    status: task.status,
                    priority: task.priority,
                    timestamp: task.completedAt ?? task.startedAt ?? task.createdAt
                )
            }
    }

    private static func severityRank(_ status: OpsCenterRuntimeStatus) -> Int {
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

    private static func matchesWorkflow(_ metadata: [String: String], workflowID: UUID?) -> Bool {
        guard let workflowID else { return true }
        guard let resolvedWorkflowID = normalizedWorkflowID(metadata["workflowID"]) else { return true }
        return resolvedWorkflowID == workflowID.uuidString
    }

    private static func allDispatches(from runtimeState: RuntimeState) -> [RuntimeDispatchRecord] {
        runtimeState.dispatchQueue
            + runtimeState.inflightDispatches
            + runtimeState.completedDispatches
            + runtimeState.failedDispatches
    }

    private static func workbenchThreadStatus(messages: [Message], tasks: [Task]) -> String {
        if messages.contains(where: { $0.status == .waitingForApproval }) {
            return "approval_pending"
        }
        if tasks.contains(where: { $0.status == .blocked }) {
            return "blocked"
        }
        if tasks.contains(where: { $0.status == .inProgress || $0.status == .todo }) {
            return "active"
        }
        if tasks.contains(where: { $0.status == .done }) {
            return "completed"
        }
        return messages.isEmpty ? "idle" : "active"
    }

    private static func agentName(for rawAgentID: String, using agentNamesByID: [UUID: String]) -> String {
        guard let agentID = UUID(uuidString: rawAgentID.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return rawAgentID
        }
        return agentNamesByID[agentID] ?? rawAgentID
    }

    private static func uuid(from rawValue: String?) -> UUID? {
        guard let normalizedUUIDString = normalizedUUIDString(rawValue) else { return nil }
        return UUID(uuidString: normalizedUUIDString)
    }

    private static func normalizedSessionID(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed.lowercased()
    }

    private static func normalizedWorkflowID(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalizedUUIDString(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed.lowercased()
    }

    private static func compactPreview(_ text: String, limit: Int = 96) -> String {
        let singleLine = text
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard singleLine.count > limit else { return singleLine }
        return "\(singleLine.prefix(limit))..."
    }
}
