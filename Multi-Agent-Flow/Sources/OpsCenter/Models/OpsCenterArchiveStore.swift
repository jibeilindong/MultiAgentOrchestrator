import Foundation

private struct OpsCenterArchiveRuntimeDispatchEnvelopeDocument: Codable {
    let stateBucket: String
    let record: RuntimeDispatchRecord
}

private struct OpsCenterArchiveRuntimeSessionDocument: Codable {
    let sessionID: String
    let storageDirectoryName: String
    let generatedAt: Date
    let workflowIDs: [String]
    let eventCount: Int
    let dispatchCount: Int
    let receiptCount: Int
    let queuedDispatchCount: Int
    let inflightDispatchCount: Int
    let completedDispatchCount: Int
    let failedDispatchCount: Int
    let latestEventAt: Date?
    let latestReceiptAt: Date?
    let lastUpdatedAt: Date?
    let isProjectRuntimeSession: Bool
}

private struct OpsCenterArchiveThreadContextDocument: Codable {
    let threadID: String
    let sessionID: String
    let workflowID: UUID?
    let workflowName: String?
    let taskIDs: [UUID]
    let messageIDs: [UUID]
    let participantAgentIDs: [UUID]
    let entryAgentID: UUID?
    let entryAgentName: String?
}

private struct OpsCenterArchiveWorkbenchThreadDocument: Codable {
    let threadID: String
    let sessionID: String
    let workflowID: UUID?
    let workflowName: String?
    let entryAgentID: UUID?
    let entryAgentName: String?
    let status: String
    let startedAt: Date
    let lastUpdatedAt: Date
    let messageCount: Int
    let taskCount: Int
    let pendingApprovalCount: Int
    let latestMessageID: UUID?
    let latestTaskID: UUID?
}

private struct OpsCenterArchiveThreadInvestigationDocument: Codable {
    let threadID: String
    let sessionID: String
    let workflowID: UUID?
    let workflowName: String?
    let entryAgentID: UUID?
    let entryAgentName: String?
    let participantAgentIDs: [UUID]
    let relatedNodeIDs: [UUID]
    let status: String
    let startedAt: Date
    let lastUpdatedAt: Date
    let messageCount: Int
    let taskCount: Int
    let pendingApprovalCount: Int
    let dispatchCount: Int
    let eventCount: Int
    let receiptCount: Int
    let latestMessageID: UUID?
    let latestTaskID: UUID?
}

private struct OpsCenterArchiveSessionPayload {
    let summary: OpsCenterSessionSummary
    let relatedNodeIDs: Set<UUID>
    let dispatches: [OpsCenterDispatchDigest]
    let events: [OpsCenterEventDigest]
    let receipts: [OpsCenterReceiptDigest]
    let messages: [OpsCenterMessageDigest]
    let tasks: [OpsCenterTaskDigest]
}

enum OpsCenterArchiveStore {
    static func loadSessionInvestigation(
        projectID: UUID,
        workflowID: UUID?,
        sessionID: String,
        projections: OpsCenterProjectionBundle? = nil
    ) -> OpsCenterSessionInvestigation? {
        guard let snapshot = loadSnapshot(projectID: projectID) else { return nil }
        guard let payload = loadSessionPayload(
            projectID: projectID,
            workflowID: workflowID,
            sessionID: sessionID,
            snapshot: snapshot,
            projections: projections
        ) else {
            return nil
        }

        let relatedNodes = buildRelatedNodes(
            snapshot: snapshot,
            workflowID: workflowID,
            relatedNodeIDs: payload.relatedNodeIDs,
            sessionID: sessionID,
            receipts: payload.receipts,
            projections: projections
        )

        return OpsCenterSessionInvestigation(
            session: payload.summary,
            relatedNodes: relatedNodes,
            events: payload.events,
            dispatches: payload.dispatches,
            receipts: payload.receipts,
            messages: payload.messages,
            tasks: payload.tasks
        )
    }

    static func loadNodeInvestigation(
        projectID: UUID,
        workflowID: UUID?,
        nodeID: UUID,
        projections: OpsCenterProjectionBundle? = nil
    ) -> OpsCenterNodeInvestigation? {
        guard let snapshot = loadSnapshot(projectID: projectID) else { return nil }
        guard let nodeContext = resolveNodeContext(snapshot: snapshot, workflowID: workflowID, nodeID: nodeID) else {
            return nil
        }

        let relatedSessionIDs = resolveRelatedSessionIDs(
            projectID: projectID,
            snapshot: snapshot,
            node: nodeContext.node,
            workflowID: nodeContext.workflow.id,
            projections: projections
        )

        let sessionPayloads = relatedSessionIDs.compactMap {
            loadSessionPayload(
                projectID: projectID,
                workflowID: nodeContext.workflow.id,
                sessionID: $0,
                snapshot: snapshot,
                projections: projections
            )
        }

        let relatedSessions = sessionPayloads.map(\.summary).sorted {
            if $0.isPrimaryRuntimeSession != $1.isPrimaryRuntimeSession {
                return $0.isPrimaryRuntimeSession
            }
            return ($0.lastUpdatedAt ?? .distantPast) > ($1.lastUpdatedAt ?? .distantPast)
        }

        let dispatches = mergeDispatchDigests(sessionPayloads.flatMap(\.dispatches))
        let events = mergeEventDigests(sessionPayloads.flatMap(\.events))
        let receipts = mergeReceiptDigests(sessionPayloads.flatMap(\.receipts).filter { $0.id.uuidString.isEmpty == false })
            .filter { $0.nodeTitle == nodeContext.node.title || $0.agentName == nodeContext.agentName }
        let messages = mergeMessageDigests(sessionPayloads.flatMap(\.messages))
        let archiveTasks = mergeTaskDigests(sessionPayloads.flatMap(\.tasks))

        let currentTasks = snapshot.tasks
            .filter { task in
                task.workflowNodeID == nodeID
                    || (nodeContext.node.agentID != nil && task.assignedAgentID == nodeContext.node.agentID)
            }
            .map { task in
                OpsCenterTaskDigest(
                    id: task.id,
                    title: task.title,
                    summary: archiveTaskSummary(task, agentName: task.assignedAgentID.flatMap { agentName(for: $0, snapshot: snapshot) }),
                    status: task.status,
                    priority: task.priority,
                    timestamp: task.completedAt ?? task.startedAt ?? task.createdAt
                )
            }

        let tasks = mergeTaskDigests(archiveTasks + currentTasks)
        let nodeSummary = buildNodeSummary(
            snapshot: snapshot,
            workflow: nodeContext.workflow,
            node: nodeContext.node,
            relatedSessionIDs: relatedSessionIDs,
            dispatches: dispatches,
            receipts: receipts,
            projections: projections
        )

        let relatedSessionActivityCount = relatedSessions.reduce(0) { partial, session in
            partial + (session.workflowIDs.contains(nodeContext.workflow.id.uuidString) ? 1 : 0)
        }

        let incomingEdges = nodeContext.workflow.edges
            .filter { $0.toNodeID == nodeID }
            .map { edge in
                let fromTitle = nodeContext.workflow.nodes.first(where: { $0.id == edge.fromNodeID })?.title ?? "Unknown"
                let toTitle = nodeContext.workflow.nodes.first(where: { $0.id == edge.toNodeID })?.title ?? "Unknown"
                return OpsCenterEdgeSummary(
                    id: edge.id,
                    title: edge.label.isEmpty ? "Path" : edge.label,
                    fromTitle: fromTitle,
                    toTitle: toTitle,
                    activityCount: relatedSessionActivityCount,
                    requiresApproval: edge.requiresApproval
                )
            }

        let outgoingEdges = nodeContext.workflow.edges
            .filter { $0.fromNodeID == nodeID }
            .map { edge in
                let fromTitle = nodeContext.workflow.nodes.first(where: { $0.id == edge.fromNodeID })?.title ?? "Unknown"
                let toTitle = nodeContext.workflow.nodes.first(where: { $0.id == edge.toNodeID })?.title ?? "Unknown"
                return OpsCenterEdgeSummary(
                    id: edge.id,
                    title: edge.label.isEmpty ? "Path" : edge.label,
                    fromTitle: fromTitle,
                    toTitle: toTitle,
                    activityCount: relatedSessionActivityCount,
                    requiresApproval: edge.requiresApproval
                )
            }

        return OpsCenterNodeInvestigation(
            workflowName: nodeContext.workflow.name,
            node: nodeSummary,
            relatedSessions: relatedSessions,
            incomingEdges: incomingEdges,
            outgoingEdges: outgoingEdges,
            events: events,
            dispatches: dispatches,
            receipts: receipts,
            messages: messages,
            tasks: tasks
        )
    }

    static func loadRouteInvestigation(
        projectID: UUID,
        workflowID: UUID?,
        edgeID: UUID,
        projections: OpsCenterProjectionBundle? = nil
    ) -> OpsCenterRouteInvestigation? {
        guard let snapshot = loadSnapshot(projectID: projectID) else { return nil }
        guard let routeContext = resolveRouteContext(snapshot: snapshot, workflowID: workflowID, edgeID: edgeID) else {
            return nil
        }

        let relatedSessionIDs = resolveRouteSessionIDs(
            projectID: projectID,
            workflow: routeContext.workflow,
            edge: routeContext.edge,
            projections: projections
        )
        let sessionPayloads = relatedSessionIDs.compactMap {
            loadSessionPayload(
                projectID: projectID,
                workflowID: routeContext.workflow.id,
                sessionID: $0,
                snapshot: snapshot,
                projections: projections
            )
        }

        let agentNamesByID = Dictionary(uniqueKeysWithValues: snapshot.agents.map { ($0.id, $0.name) })
        let upstreamAgentName = routeContext.upstreamNode.agentID.flatMap { agentNamesByID[$0] }
        let downstreamAgentName = routeContext.downstreamNode.agentID.flatMap { agentNamesByID[$0] }
        let relatedSessions = sessionPayloads.map(\.summary).sorted {
            if $0.isPrimaryRuntimeSession != $1.isPrimaryRuntimeSession {
                return $0.isPrimaryRuntimeSession
            }
            return ($0.lastUpdatedAt ?? .distantPast) > ($1.lastUpdatedAt ?? .distantPast)
        }

        let dispatches = mergeDispatchDigests(sessionPayloads.flatMap(\.dispatches)).filter { dispatch in
            let sourceMatches = upstreamAgentName.map { dispatch.sourceName == $0 } ?? false
            let targetMatches = downstreamAgentName.map { dispatch.targetName == $0 } ?? false
            return sourceMatches && targetMatches
        }
        let events = mergeEventDigests(sessionPayloads.flatMap(\.events)).filter { event in
            guard let sessionID = event.sessionID else { return false }
            return relatedSessionIDs.contains(sessionID)
        }
        let receipts = mergeReceiptDigests(sessionPayloads.flatMap(\.receipts)).filter { receipt in
            receipt.nodeTitle == routeContext.upstreamNode.title || receipt.nodeTitle == routeContext.downstreamNode.title
        }
        let messages = mergeMessageDigests(sessionPayloads.flatMap(\.messages))
        let tasks = mergeTaskDigests(sessionPayloads.flatMap(\.tasks))

        let upstreamNodeSummary = projections?.nodeSummaries(for: routeContext.workflow.id).first(where: {
            $0.id == routeContext.upstreamNode.id
        }) ?? buildNodeSummary(
            snapshot: snapshot,
            workflow: routeContext.workflow,
            node: routeContext.upstreamNode,
            relatedSessionIDs: relatedSessionIDs,
            dispatches: dispatches,
            receipts: receipts.filter { $0.nodeTitle == routeContext.upstreamNode.title },
            projections: projections
        )
        let downstreamNodeSummary = projections?.nodeSummaries(for: routeContext.workflow.id).first(where: {
            $0.id == routeContext.downstreamNode.id
        }) ?? buildNodeSummary(
            snapshot: snapshot,
            workflow: routeContext.workflow,
            node: routeContext.downstreamNode,
            relatedSessionIDs: relatedSessionIDs,
            dispatches: dispatches,
            receipts: receipts.filter { $0.nodeTitle == routeContext.downstreamNode.title },
            projections: projections
        )

        return OpsCenterRouteInvestigation(
            workflowName: routeContext.workflow.name,
            edge: OpsCenterEdgeSummary(
                id: routeContext.edge.id,
                title: routeContext.edge.label.isEmpty ? "Path" : routeContext.edge.label,
                fromTitle: routeContext.upstreamNode.title,
                toTitle: routeContext.downstreamNode.title,
                activityCount: max(dispatches.count, relatedSessions.count),
                requiresApproval: routeContext.edge.requiresApproval
            ),
            upstreamNode: upstreamNodeSummary,
            downstreamNode: downstreamNodeSummary,
            relatedSessions: relatedSessions,
            events: events,
            dispatches: dispatches,
            receipts: receipts,
            messages: messages,
            tasks: tasks
        )
    }

    static func loadThreadInvestigation(
        projectID: UUID,
        workflowID: UUID?,
        threadID: String,
        projections: OpsCenterProjectionBundle? = nil
    ) -> OpsCenterThreadInvestigation? {
        guard let snapshot = loadSnapshot(projectID: projectID) else { return nil }
        guard let normalizedTargetThreadID = normalizedSessionID(threadID) else { return nil }

        let projectRootURL = ProjectManager.shared.managedProjectRootDirectory(for: projectID)
        let threadRootURL = projectRootURL
            .appendingPathComponent("collaboration", isDirectory: true)
            .appendingPathComponent("workbench", isDirectory: true)
            .appendingPathComponent("threads", isDirectory: true)
            .appendingPathComponent(safeStorageName(for: normalizedTargetThreadID), isDirectory: true)

        guard FileManager.default.fileExists(atPath: threadRootURL.path) else { return nil }

        let threadDocument = decode(
            OpsCenterArchiveWorkbenchThreadDocument.self,
            from: threadRootURL.appendingPathComponent("thread.json", isDirectory: false)
        )
        let threadContext = decode(
            OpsCenterArchiveThreadContextDocument.self,
            from: threadRootURL.appendingPathComponent("context.json", isDirectory: false)
        )
        let investigationDocument = decode(
            OpsCenterArchiveThreadInvestigationDocument.self,
            from: threadRootURL.appendingPathComponent("investigation.json", isDirectory: false)
        )

        let resolvedWorkflowID = workflowID
            ?? threadDocument?.workflowID
            ?? threadContext?.workflowID
            ?? investigationDocument?.workflowID
        let resolvedSessionID = normalizedSessionID(
            threadDocument?.sessionID
                ?? threadContext?.sessionID
                ?? investigationDocument?.sessionID
                ?? normalizedTargetThreadID
        ) ?? normalizedTargetThreadID
        let payload = loadSessionPayload(
            projectID: projectID,
            workflowID: resolvedWorkflowID,
            sessionID: resolvedSessionID,
            snapshot: snapshot,
            projections: projections
        )

        let relatedNodeIDs = Set(investigationDocument?.relatedNodeIDs ?? [])
            .union(payload?.relatedNodeIDs ?? [])
        let relatedNodes: [OpsCenterNodeSummary]
        if relatedNodeIDs.isEmpty {
            relatedNodes = []
        } else {
            relatedNodes = buildRelatedNodes(
                snapshot: snapshot,
                workflowID: resolvedWorkflowID,
                relatedNodeIDs: relatedNodeIDs,
                sessionID: resolvedSessionID,
                receipts: payload?.receipts ?? [],
                projections: projections
            )
        }

        let participantNames = Set(
            (threadContext?.participantAgentIDs ?? investigationDocument?.participantAgentIDs ?? [])
                .compactMap { agentName(for: $0, snapshot: snapshot) }
        )
        .sorted()
        let messageTimestamps = payload?.messages.map(\.timestamp) ?? []
        let taskTimestamps = payload?.tasks.map(\.timestamp) ?? []
        let pendingApprovalCount = max(
            threadDocument?.pendingApprovalCount ?? 0,
            investigationDocument?.pendingApprovalCount ?? 0,
            payload?.messages.filter { $0.status == .waitingForApproval }.count ?? 0
        )
        let resolvedWorkflowName = threadDocument?.workflowName
            ?? threadContext?.workflowName
            ?? investigationDocument?.workflowName
            ?? resolvedWorkflowID.flatMap { workflowID in
                snapshot.workflows.first(where: { $0.id == workflowID })?.name
            }
            ?? "Workbench Thread"

        guard threadDocument != nil || threadContext != nil || investigationDocument != nil || payload != nil else {
            return nil
        }

        let resolvedStatus = threadDocument?.status
            ?? investigationDocument?.status
            ?? archiveThreadStatus(
                messages: payload?.messages ?? [],
                tasks: payload?.tasks ?? [],
                pendingApprovalCount: pendingApprovalCount
            )
        let resolvedStartedAt = threadDocument?.startedAt
            ?? investigationDocument?.startedAt
            ?? (messageTimestamps + taskTimestamps).min()
        let resolvedLastUpdatedAt = [
            threadDocument?.lastUpdatedAt,
            investigationDocument?.lastUpdatedAt,
            payload?.summary.lastUpdatedAt,
            (messageTimestamps + taskTimestamps).max()
        ]
        .compactMap { $0 }
        .max()
        let resolvedEntryAgentName: String? = {
            if let name = threadDocument?.entryAgentName {
                return name
            }
            if let name = threadContext?.entryAgentName {
                return name
            }
            if let name = investigationDocument?.entryAgentName {
                return name
            }
            if let entryAgentID = threadDocument?.entryAgentID {
                return agentName(for: entryAgentID, snapshot: snapshot)
            }
            if let entryAgentID = threadContext?.entryAgentID {
                return agentName(for: entryAgentID, snapshot: snapshot)
            }
            if let entryAgentID = investigationDocument?.entryAgentID {
                return agentName(for: entryAgentID, snapshot: snapshot)
            }
            return nil
        }()

        return OpsCenterThreadInvestigation(
            threadID: normalizedTargetThreadID,
            sessionID: resolvedSessionID,
            workflowID: resolvedWorkflowID,
            workflowName: resolvedWorkflowName,
            status: resolvedStatus,
            startedAt: resolvedStartedAt,
            lastUpdatedAt: resolvedLastUpdatedAt,
            entryAgentName: resolvedEntryAgentName,
            participantNames: participantNames,
            pendingApprovalCount: pendingApprovalCount,
            relatedSession: payload?.summary,
            relatedNodes: relatedNodes,
            events: payload?.events ?? [],
            dispatches: payload?.dispatches ?? [],
            receipts: payload?.receipts ?? [],
            messages: payload?.messages ?? [],
            tasks: payload?.tasks ?? []
        )
    }

    private static func loadSessionPayload(
        projectID: UUID,
        workflowID: UUID?,
        sessionID: String,
        snapshot: MAProject,
        projections: OpsCenterProjectionBundle?
    ) -> OpsCenterArchiveSessionPayload? {
        let projectRootURL = ProjectManager.shared.managedProjectRootDirectory(for: projectID)
        let runtimeRootURL = projectRootURL
            .appendingPathComponent("runtime", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
        let threadRootURL = projectRootURL
            .appendingPathComponent("collaboration", isDirectory: true)
            .appendingPathComponent("workbench", isDirectory: true)
            .appendingPathComponent("threads", isDirectory: true)
        let tasksURL = projectRootURL
            .appendingPathComponent("tasks", isDirectory: true)
            .appendingPathComponent("tasks.json", isDirectory: false)

        let storageName = safeStorageName(for: sessionID)
        let sessionRootURL = runtimeRootURL.appendingPathComponent(storageName, isDirectory: true)
        let threadURL = threadRootURL.appendingPathComponent(storageName, isDirectory: true)

        guard FileManager.default.fileExists(atPath: sessionRootURL.path) || FileManager.default.fileExists(atPath: threadURL.path) else {
            return nil
        }

        let sessionDocument = decode(
            OpsCenterArchiveRuntimeSessionDocument.self,
            from: sessionRootURL.appendingPathComponent("session.json", isDirectory: false)
        )

        let workflowScopeID = workflowID?.uuidString
        let agentNamesByID = Dictionary(uniqueKeysWithValues: snapshot.agents.map { ($0.id, $0.name) })
        let nodeTitleByID = Dictionary(uniqueKeysWithValues: snapshot.workflows.flatMap { $0.nodes }.map { ($0.id, $0.title) })

        let dispatchEnvelopes = decodeNDJSON(
            OpsCenterArchiveRuntimeDispatchEnvelopeDocument.self,
            from: sessionRootURL.appendingPathComponent("dispatches.ndjson", isDirectory: false)
        )
        let events = decodeNDJSON(
            OpenClawRuntimeEvent.self,
            from: sessionRootURL.appendingPathComponent("events.ndjson", isDirectory: false)
        )
        let receipts = decodeNDJSON(
            ExecutionResult.self,
            from: sessionRootURL.appendingPathComponent("receipts.ndjson", isDirectory: false)
        )
        let messages = decodeNDJSON(
            Message.self,
            from: threadURL.appendingPathComponent("dialog.ndjson", isDirectory: false)
        )
        let threadContext = decode(
            OpsCenterArchiveThreadContextDocument.self,
            from: threadURL.appendingPathComponent("context.json", isDirectory: false)
        )
        let threadTaskIDs = Set(threadContext?.taskIDs ?? [])
        let tasks = (decode([Task].self, from: tasksURL) ?? snapshot.tasks).filter {
            normalizedSessionID($0.metadata["workbenchSessionID"]) == normalizedSessionID(sessionID)
                || threadTaskIDs.contains($0.id)
        }

        let scopedDispatches = dispatchEnvelopes.filter { envelope in
            guard let workflowScopeID else { return true }
            return envelope.record.workflowID == nil || envelope.record.workflowID == workflowScopeID
        }
        let scopedEvents = events.filter { event in
            guard let workflowScopeID else { return true }
            return event.workflowId == nil || event.workflowId == workflowScopeID
        }
        let scopedWorkflow = workflowID.flatMap { targetWorkflowID in
            snapshot.workflows.first(where: { $0.id == targetWorkflowID })
        }
        let scopedReceipts = receipts.filter { receipt in
            guard let scopedWorkflow else {
                return true
            }
            return scopedWorkflow.nodes.contains(where: { $0.id == receipt.nodeID })
        }
        let scopedMessages = messages.filter { message in
            guard let workflowScopeID else { return true }
            return message.metadata["workflowID"] == nil || message.metadata["workflowID"] == workflowScopeID
        }
        let scopedTasks = tasks.filter { task in
            guard let workflowScopeID else { return true }
            return task.metadata["workflowID"] == nil || task.metadata["workflowID"] == workflowScopeID
        }

        let summary = makeSessionSummary(
            sessionID: sessionID,
            sessionDocument: sessionDocument,
            dispatches: scopedDispatches,
            events: scopedEvents,
            receipts: scopedReceipts,
            messages: scopedMessages,
            tasks: scopedTasks,
            projections: projections,
            workflowID: workflowID
        )

        let dispatchNodeIDs = scopedDispatches.compactMap { uuid(from: $0.record.nodeID) }
        let eventNodeIDs = scopedEvents.compactMap { uuid(from: $0.nodeId) }
        let receiptNodeIDs = scopedReceipts.map(\.nodeID)
        let taskNodeIDs = scopedTasks.compactMap(\.workflowNodeID)
        let relatedNodeIDs = Set(dispatchNodeIDs + eventNodeIDs + receiptNodeIDs + taskNodeIDs)

        let dispatchDigests = scopedDispatches
            .sorted { lhs, rhs in
                if lhs.record.updatedAt != rhs.record.updatedAt {
                    return lhs.record.updatedAt > rhs.record.updatedAt
                }
                return lhs.record.id > rhs.record.id
            }
            .map { envelope in
                OpsCenterDispatchDigest(
                    id: envelope.record.id,
                    sourceName: agentName(for: envelope.record.sourceAgentID, namesByID: agentNamesByID),
                    targetName: agentName(for: envelope.record.targetAgentID, namesByID: agentNamesByID),
                    summary: compactPreview(envelope.record.summary, limit: 140),
                    status: envelope.record.status,
                    sessionID: normalizedSessionID(envelope.record.sessionKey),
                    updatedAt: envelope.record.updatedAt,
                    errorText: envelope.record.errorMessage.map { compactPreview($0, limit: 140) }
                )
            }

        let eventDigests = scopedEvents
            .sorted { lhs, rhs in
                if lhs.timestamp != rhs.timestamp {
                    return lhs.timestamp > rhs.timestamp
                }
                return lhs.id > rhs.id
            }
            .map {
                OpsCenterEventDigest(
                    id: $0.id,
                    eventType: $0.eventType,
                    participants: $0.participantsText,
                    summary: compactPreview($0.summaryText, limit: 160),
                    sessionID: normalizedSessionID($0.sessionKey),
                    timestamp: $0.timestamp
                )
            }

        let receiptDigests = scopedReceipts
            .sorted { lhs, rhs in
                let lhsDate = lhs.completedAt ?? lhs.startedAt
                let rhsDate = rhs.completedAt ?? rhs.startedAt
                if lhsDate != rhsDate {
                    return lhsDate > rhsDate
                }
                return lhs.id.uuidString > rhs.id.uuidString
            }
            .map {
                OpsCenterReceiptDigest(
                    id: $0.id,
                    nodeTitle: nodeTitleByID[$0.nodeID] ?? "Unknown Node",
                    agentName: agentNamesByID[$0.agentID],
                    status: $0.status,
                    outputType: $0.outputType,
                    sessionID: normalizedSessionID($0.sessionID),
                    summary: compactPreview($0.summaryText, limit: 160),
                    duration: $0.duration,
                    timestamp: $0.completedAt ?? $0.startedAt
                )
            }

        let messageDigests = scopedMessages
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

        let taskDigests = scopedTasks
            .sorted { lhs, rhs in
                let lhsDate = lhs.completedAt ?? lhs.startedAt ?? lhs.createdAt
                let rhsDate = rhs.completedAt ?? rhs.startedAt ?? rhs.createdAt
                if lhsDate != rhsDate {
                    return lhsDate > rhsDate
                }
                return lhs.id.uuidString > rhs.id.uuidString
            }
            .map { task in
                OpsCenterTaskDigest(
                    id: task.id,
                    title: task.title,
                    summary: archiveTaskSummary(task, agentName: task.assignedAgentID.flatMap { agentNamesByID[$0] }),
                    status: task.status,
                    priority: task.priority,
                    timestamp: task.completedAt ?? task.startedAt ?? task.createdAt
                )
            }
        return OpsCenterArchiveSessionPayload(
            summary: summary,
            relatedNodeIDs: relatedNodeIDs,
            dispatches: dispatchDigests,
            events: eventDigests,
            receipts: receiptDigests,
            messages: messageDigests,
            tasks: taskDigests
        )
    }

    private static func makeSessionSummary(
        sessionID: String,
        sessionDocument: OpsCenterArchiveRuntimeSessionDocument?,
        dispatches: [OpsCenterArchiveRuntimeDispatchEnvelopeDocument],
        events: [OpenClawRuntimeEvent],
        receipts: [ExecutionResult],
        messages: [Message],
        tasks: [Task],
        projections: OpsCenterProjectionBundle?,
        workflowID: UUID?
    ) -> OpsCenterSessionSummary {
        if let sessionDocument {
            return OpsCenterSessionSummary(
                sessionID: sessionDocument.sessionID,
                workflowIDs: sessionDocument.workflowIDs,
                eventCount: sessionDocument.eventCount,
                dispatchCount: sessionDocument.dispatchCount,
                receiptCount: sessionDocument.receiptCount,
                queuedDispatchCount: sessionDocument.queuedDispatchCount,
                inflightDispatchCount: sessionDocument.inflightDispatchCount,
                completedDispatchCount: sessionDocument.completedDispatchCount,
                failedDispatchCount: sessionDocument.failedDispatchCount,
                lastUpdatedAt: sessionDocument.lastUpdatedAt,
                latestFailureText: latestFailureText(dispatches: dispatches, receipts: receipts),
                isPrimaryRuntimeSession: sessionDocument.isProjectRuntimeSession
            )
        }

        if let projectionSummary = projections?.sessionSummaries(for: workflowID).first(where: { $0.sessionID == sessionID }) {
            return projectionSummary
        }

        let workflowIDs = Set(
            dispatches.compactMap(\.record.workflowID)
                + events.compactMap(\.workflowId)
                + messages.compactMap { normalizedWorkflowID($0.metadata["workflowID"]) }
                + tasks.compactMap { normalizedWorkflowID($0.metadata["workflowID"]) }
        )
        .sorted()

        return OpsCenterSessionSummary(
            sessionID: sessionID,
            workflowIDs: workflowIDs,
            eventCount: events.count,
            dispatchCount: dispatches.count,
            receiptCount: receipts.count,
            queuedDispatchCount: dispatches.filter { $0.stateBucket == "queued" }.count,
            inflightDispatchCount: dispatches.filter { $0.stateBucket == "inflight" }.count,
            completedDispatchCount: dispatches.filter { $0.stateBucket == "completed" }.count,
            failedDispatchCount: dispatches.filter { $0.stateBucket == "failed" }.count,
            lastUpdatedAt: (
                dispatches.map(\.record.updatedAt)
                + events.map(\.timestamp)
                + receipts.compactMap { $0.completedAt ?? $0.startedAt }
            ).max(),
            latestFailureText: latestFailureText(dispatches: dispatches, receipts: receipts),
            isPrimaryRuntimeSession: false
        )
    }

    private static func buildRelatedNodes(
        snapshot: MAProject,
        workflowID: UUID?,
        relatedNodeIDs: Set<UUID>,
        sessionID: String,
        receipts: [OpsCenterReceiptDigest],
        projections: OpsCenterProjectionBundle?
    ) -> [OpsCenterNodeSummary] {
        let scopedWorkflows = snapshot.workflows.filter { workflow in
            guard let workflowID else { return true }
            return workflow.id == workflowID
        }

        let runtimeProjectionNodes = projections?.nodesRuntime?.nodes.filter {
            relatedNodeIDs.contains($0.nodeID) && (workflowID == nil || $0.workflowID == workflowID)
        } ?? []

        let projectionNodesByID = Dictionary(uniqueKeysWithValues: runtimeProjectionNodes.map { ($0.nodeID, $0) })
        let receiptTimestampsByNodeID = Dictionary(grouping: receipts, by: \.nodeTitle)

        return scopedWorkflows
            .flatMap(\.nodes)
            .filter { relatedNodeIDs.contains($0.id) }
            .map { node in
                let projectionEntry = projectionNodesByID[node.id]
                let status = projectionEntry.map { projectionRuntimeStatus(from: $0.status) } ?? .idle
                let workflowForNode = scopedWorkflows.first(where: { workflow in
                    workflow.nodes.contains(node)
                })
                let incomingEdgeCount = projectionEntry?.incomingEdgeCount
                    ?? workflowForNode?.edges.filter { $0.toNodeID == node.id }.count
                    ?? 0
                let outgoingEdgeCount = projectionEntry?.outgoingEdgeCount
                    ?? workflowForNode?.edges.filter { $0.fromNodeID == node.id }.count
                    ?? 0

                return OpsCenterNodeSummary(
                    id: node.id,
                    title: node.title,
                    agentName: projectionEntry?.agentName ?? node.agentID.flatMap { agentName(for: $0, snapshot: snapshot) },
                    status: status,
                    incomingEdgeCount: incomingEdgeCount,
                    outgoingEdgeCount: outgoingEdgeCount,
                    lastUpdatedAt: projectionEntry?.lastUpdatedAt ?? receiptTimestampsByNodeID[node.title]?.map(\.timestamp).max(),
                    latestDetail: projectionEntry?.latestDetail ?? "Touched by session \(sessionID)",
                    averageDuration: projectionEntry?.averageDuration
                )
            }
            .sorted { lhs, rhs in
                if lhs.status == rhs.status {
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
                return statusRank(lhs.status) < statusRank(rhs.status)
            }
    }

    private static func buildNodeSummary(
        snapshot: MAProject,
        workflow: Workflow,
        node: WorkflowNode,
        relatedSessionIDs: [String],
        dispatches: [OpsCenterDispatchDigest],
        receipts: [OpsCenterReceiptDigest],
        projections: OpsCenterProjectionBundle?
    ) -> OpsCenterNodeSummary {
        if let projectionNode = projections?.nodeSummaries(for: workflow.id).first(where: { $0.id == node.id }) {
            return projectionNode
        }

        let relatedReceipts = receipts.filter { $0.nodeTitle == node.title }
        let status: OpsCenterRuntimeStatus = {
            if dispatches.contains(where: { $0.status == .failed || $0.status == .aborted || $0.status == .expired }) {
                return .failed
            }
            if dispatches.contains(where: { $0.status == .waitingApproval }) {
                return .waitingApproval
            }
            if dispatches.contains(where: { [.running, .accepted, .dispatched].contains($0.status) }) {
                return .inflight
            }
            if dispatches.contains(where: { [.created, .waitingDependency].contains($0.status) }) {
                return .queued
            }
            if let latestReceipt = relatedReceipts.first {
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
        }()

        let averageDuration: TimeInterval? = {
            let durations = relatedReceipts.compactMap(\.duration)
            guard !durations.isEmpty else { return nil }
            return durations.reduce(0, +) / Double(durations.count)
        }()

        return OpsCenterNodeSummary(
            id: node.id,
            title: node.title,
            agentName: node.agentID.flatMap { agentName(for: $0, snapshot: snapshot) },
            status: status,
            incomingEdgeCount: workflow.edges.filter { $0.toNodeID == node.id }.count,
            outgoingEdgeCount: workflow.edges.filter { $0.fromNodeID == node.id }.count,
            lastUpdatedAt: (
                dispatches.map(\.updatedAt)
                + relatedReceipts.map(\.timestamp)
            ).max(),
            latestDetail: relatedReceipts.first?.summary ?? "Touched by \(relatedSessionIDs.count) session(s)",
            averageDuration: averageDuration
        )
    }

    private static func resolveNodeContext(
        snapshot: MAProject,
        workflowID: UUID?,
        nodeID: UUID
    ) -> (workflow: Workflow, node: WorkflowNode, agentName: String?)? {
        if let workflowID,
           let workflow = snapshot.workflows.first(where: { $0.id == workflowID }),
           let node = workflow.nodes.first(where: { $0.id == nodeID }) {
            return (workflow, node, node.agentID.flatMap { agentName(for: $0, snapshot: snapshot) })
        }

        for workflow in snapshot.workflows {
            if let node = workflow.nodes.first(where: { $0.id == nodeID }) {
                return (workflow, node, node.agentID.flatMap { agentName(for: $0, snapshot: snapshot) })
            }
        }

        return nil
    }

    private static func resolveRouteContext(
        snapshot: MAProject,
        workflowID: UUID?,
        edgeID: UUID
    ) -> (workflow: Workflow, edge: WorkflowEdge, upstreamNode: WorkflowNode, downstreamNode: WorkflowNode)? {
        let candidateWorkflows: [Workflow]
        if let workflowID, let workflow = snapshot.workflows.first(where: { $0.id == workflowID }) {
            candidateWorkflows = [workflow]
        } else {
            candidateWorkflows = snapshot.workflows
        }

        for workflow in candidateWorkflows {
            guard let edge = workflow.edges.first(where: { $0.id == edgeID }),
                  let upstreamNode = workflow.nodes.first(where: { $0.id == edge.fromNodeID }),
                  let downstreamNode = workflow.nodes.first(where: { $0.id == edge.toNodeID }) else {
                continue
            }
            return (workflow, edge, upstreamNode, downstreamNode)
        }

        return nil
    }

    private static func resolveRelatedSessionIDs(
        projectID: UUID,
        snapshot: MAProject,
        node: WorkflowNode,
        workflowID: UUID,
        projections: OpsCenterProjectionBundle?
    ) -> [String] {
        var sessionIDs = Set(
            projections?.nodesRuntime?.nodes.first(where: { $0.nodeID == node.id })?.relatedSessionIDs ?? []
        )

        snapshot.tasks
            .filter { $0.workflowNodeID == node.id || (node.agentID != nil && $0.assignedAgentID == node.agentID) }
            .compactMap { normalizedSessionID($0.metadata["workbenchSessionID"]) }
            .forEach { sessionIDs.insert($0) }

        snapshot.executionResults
            .filter { $0.nodeID == node.id }
            .compactMap { normalizedSessionID($0.sessionID) }
            .forEach { sessionIDs.insert($0) }

        let sessionsRootURL = ProjectManager.shared.managedProjectRootDirectory(for: projectID)
            .appendingPathComponent("runtime", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)

        let fileManager = FileManager.default
        let sessionDirectories = (try? fileManager.contentsOfDirectory(
            at: sessionsRootURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        for sessionDirectory in sessionDirectories where sessionDirectory.hasDirectoryPath {
            let sessionDocument = decode(
                OpsCenterArchiveRuntimeSessionDocument.self,
                from: sessionDirectory.appendingPathComponent("session.json", isDirectory: false)
            )
            if sessionDocument?.workflowIDs.contains(workflowID.uuidString) == true {
                let dispatches = decodeNDJSON(
                    OpsCenterArchiveRuntimeDispatchEnvelopeDocument.self,
                    from: sessionDirectory.appendingPathComponent("dispatches.ndjson", isDirectory: false)
                )
                let receipts = decodeNDJSON(
                    ExecutionResult.self,
                    from: sessionDirectory.appendingPathComponent("receipts.ndjson", isDirectory: false)
                )
                let events = decodeNDJSON(
                    OpenClawRuntimeEvent.self,
                    from: sessionDirectory.appendingPathComponent("events.ndjson", isDirectory: false)
                )

                let touchesNode = dispatches.contains { uuid(from: $0.record.nodeID) == node.id }
                    || receipts.contains { $0.nodeID == node.id }
                    || events.contains { uuid(from: $0.nodeId) == node.id }

                if touchesNode, let sessionID = sessionDocument?.sessionID {
                    sessionIDs.insert(sessionID)
                }
            }
        }

        return sessionIDs.sorted()
    }

    private static func resolveRouteSessionIDs(
        projectID: UUID,
        workflow: Workflow,
        edge: WorkflowEdge,
        projections: OpsCenterProjectionBundle?
    ) -> [String] {
        let projectionNodesByID = Dictionary(
            uniqueKeysWithValues: (projections?.nodesRuntime?.nodes ?? [])
                .filter { $0.workflowID == workflow.id }
                .map { ($0.nodeID, $0) }
        )
        var sessionIDs = Set(
            Set(projectionNodesByID[edge.fromNodeID]?.relatedSessionIDs ?? [])
                .intersection(Set(projectionNodesByID[edge.toNodeID]?.relatedSessionIDs ?? []))
        )

        let sessionsRootURL = ProjectManager.shared.managedProjectRootDirectory(for: projectID)
            .appendingPathComponent("runtime", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)

        let fileManager = FileManager.default
        let sessionDirectories = (try? fileManager.contentsOfDirectory(
            at: sessionsRootURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        let upstreamNode = workflow.nodes.first(where: { $0.id == edge.fromNodeID })
        let downstreamNode = workflow.nodes.first(where: { $0.id == edge.toNodeID })
        let upstreamAgentID = upstreamNode?.agentID?.uuidString.lowercased()
        let downstreamAgentID = downstreamNode?.agentID?.uuidString.lowercased()

        for sessionDirectory in sessionDirectories where sessionDirectory.hasDirectoryPath {
            let sessionDocument = decode(
                OpsCenterArchiveRuntimeSessionDocument.self,
                from: sessionDirectory.appendingPathComponent("session.json", isDirectory: false)
            )
            guard sessionDocument?.workflowIDs.contains(workflow.id.uuidString) == true else { continue }

            let dispatches = decodeNDJSON(
                OpsCenterArchiveRuntimeDispatchEnvelopeDocument.self,
                from: sessionDirectory.appendingPathComponent("dispatches.ndjson", isDirectory: false)
            )

            let matchesRoute = dispatches.contains { envelope in
                let sourceMatches = upstreamAgentID != nil && normalizedUUIDValue(envelope.record.sourceAgentID) == upstreamAgentID
                let targetMatches = downstreamAgentID != nil && normalizedUUIDValue(envelope.record.targetAgentID) == downstreamAgentID
                let nodeMatches = uuid(from: envelope.record.nodeID) == edge.toNodeID
                return (sourceMatches && targetMatches) || (sourceMatches && nodeMatches)
            }

            if matchesRoute, let sessionID = sessionDocument?.sessionID {
                sessionIDs.insert(sessionID.lowercased())
            }
        }

        return sessionIDs.sorted()
    }

    private static func loadSnapshot(projectID: UUID) -> MAProject? {
        try? ProjectFileSystem.shared.loadSnapshot(
            for: projectID,
            under: ProjectManager.shared.appSupportRootDirectory
        )
    }

    private static func mergeDispatchDigests(_ items: [OpsCenterDispatchDigest]) -> [OpsCenterDispatchDigest] {
        Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
            .values
            .sorted { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return lhs.id > rhs.id
            }
    }

    private static func mergeEventDigests(_ items: [OpsCenterEventDigest]) -> [OpsCenterEventDigest] {
        Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
            .values
            .sorted { lhs, rhs in
                if lhs.timestamp != rhs.timestamp {
                    return lhs.timestamp > rhs.timestamp
                }
                return lhs.id > rhs.id
            }
    }

    private static func mergeReceiptDigests(_ items: [OpsCenterReceiptDigest]) -> [OpsCenterReceiptDigest] {
        Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
            .values
            .sorted { lhs, rhs in
                if lhs.timestamp != rhs.timestamp {
                    return lhs.timestamp > rhs.timestamp
                }
                return lhs.id.uuidString > rhs.id.uuidString
            }
    }

    private static func mergeMessageDigests(_ items: [OpsCenterMessageDigest]) -> [OpsCenterMessageDigest] {
        Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
            .values
            .sorted { lhs, rhs in
                if lhs.timestamp != rhs.timestamp {
                    return lhs.timestamp > rhs.timestamp
                }
                return lhs.id.uuidString > rhs.id.uuidString
            }
    }

    private static func mergeTaskDigests(_ items: [OpsCenterTaskDigest]) -> [OpsCenterTaskDigest] {
        Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
            .values
            .sorted { lhs, rhs in
                if lhs.timestamp != rhs.timestamp {
                    return lhs.timestamp > rhs.timestamp
                }
                return lhs.id.uuidString > rhs.id.uuidString
            }
    }

    private static func archiveThreadStatus(
        messages: [OpsCenterMessageDigest],
        tasks: [OpsCenterTaskDigest],
        pendingApprovalCount: Int
    ) -> String {
        if pendingApprovalCount > 0 || messages.contains(where: { $0.status == .waitingForApproval }) {
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

    private static func latestFailureText(
        dispatches: [OpsCenterArchiveRuntimeDispatchEnvelopeDocument],
        receipts: [ExecutionResult]
    ) -> String? {
        let dispatchText = dispatches.compactMap(\.record.errorMessage)
            .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        if let dispatchText {
            return compactPreview(dispatchText, limit: 160)
        }

        let receiptText = receipts
            .filter { $0.status == .failed }
            .map(\.summaryText)
            .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        return receiptText.map { compactPreview($0, limit: 160) }
    }

    private static func projectionRuntimeStatus(from rawValue: String) -> OpsCenterRuntimeStatus {
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

    private static func statusRank(_ status: OpsCenterRuntimeStatus) -> Int {
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

    private static func archiveTaskSummary(_ task: Task, agentName: String?) -> String {
        let trimmedDescription = task.description.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedDescription.isEmpty {
            return "\(agentName ?? "Unassigned") • \(compactPreview(trimmedDescription, limit: 140))"
        }
        return "Assigned to \(agentName ?? "Unassigned")"
    }

    private static func agentName(for rawAgentID: String, namesByID: [UUID: String]) -> String {
        guard let agentID = UUID(uuidString: rawAgentID.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return rawAgentID
        }
        return namesByID[agentID] ?? rawAgentID
    }

    private static func agentName(for agentID: UUID, snapshot: MAProject) -> String? {
        snapshot.agents.first(where: { $0.id == agentID })?.name
    }

    private static func decode<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func decodeNDJSON<T: Decodable>(_ type: T.Type, from url: URL) -> [T] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        return text
            .split(whereSeparator: \.isNewline)
            .compactMap { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                return try? decoder.decode(T.self, from: Data(trimmed.utf8))
            }
    }

    private static func uuid(from rawValue: String?) -> UUID? {
        guard let rawValue = normalizedUUIDValue(rawValue) else { return nil }
        return UUID(uuidString: rawValue)
    }

    private static func normalizedSessionID(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed.lowercased()
    }

    private static func normalizedWorkflowID(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalizedUUIDValue(_ rawValue: String?) -> String? {
        let trimmed = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed.lowercased()
    }

    private static func safeStorageName(for rawValue: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        return rawValue.addingPercentEncoding(withAllowedCharacters: allowed) ?? rawValue
    }

    private static func compactPreview(_ text: String, limit: Int) -> String {
        let singleLine = text
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard singleLine.count > limit else { return singleLine }
        return "\(singleLine.prefix(limit))..."
    }
}
