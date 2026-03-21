import SwiftUI
import Combine

struct OpsCenterDashboardView: View {
    @EnvironmentObject var appState: AppState

    let displayMode: OpsCenterDisplayMode
    let preferredWorkflowID: UUID?

    private let projectionRefreshTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    @State private var selectedPage: OpsCenterConsolePage = .liveRun
    @State private var selectedWorkflowID: UUID?
    @State private var selectedInvestigation: OpsCenterInvestigationTarget?
    @State private var projections: OpsCenterProjectionBundle?

    init(
        displayMode: OpsCenterDisplayMode = .fullScreen,
        preferredWorkflowID: UUID? = nil
    ) {
        self.displayMode = displayMode
        self.preferredWorkflowID = preferredWorkflowID
    }

    private var workflows: [Workflow] {
        appState.currentProject?.workflows ?? []
    }

    private var selectedWorkflow: Workflow? {
        if let selectedWorkflowID {
            return workflows.first(where: { $0.id == selectedWorkflowID })
        }
        return workflows.first
    }

    var body: some View {
        Group {
            if appState.currentProject == nil {
                ContentUnavailableView(
                    "Open a project to inspect workflow runtime",
                    systemImage: "gauge.with.dots.needle.33percent",
                    description: Text("Ops Center now focuses on live runtime investigation, sessions, workflow structure, and history.")
                )
            } else {
                VStack(spacing: 0) {
                    header
                    Divider()
                    pageContent
                }
            }
        }
        .sheet(item: $selectedInvestigation) { target in
            OpsCenterInvestigationPanel(target: target)
        }
        .onAppear {
            syncSelectedWorkflow()
            refreshProjectionsIfNeeded(force: true)
        }
        .onChange(of: workflows.map(\.id)) { _, _ in
            syncSelectedWorkflow()
        }
        .onChange(of: preferredWorkflowID) { _, _ in
            syncSelectedWorkflow()
        }
        .onChange(of: appState.currentProject?.id) { _, _ in
            refreshProjectionsIfNeeded(force: true)
        }
        .onReceive(projectionRefreshTimer) { _ in
            refreshProjectionsIfNeeded()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ops Center")
                        .font(displayMode == .embedded ? .title3.weight(.semibold) : .title2.weight(.semibold))
                    Text(selectedPage.subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if !workflows.isEmpty {
                    Picker("Workflow", selection: workflowSelectionBinding) {
                        ForEach(workflows) { workflow in
                            Text(workflow.name).tag(workflow.id as UUID?)
                        }
                    }
                    .frame(width: displayMode == .embedded ? 220 : 260)
                }

                opsStatusPill(
                    title: appState.openClawManager.isConnected ? "OpenClaw Connected" : "OpenClaw Offline",
                    color: appState.openClawManager.isConnected ? .green : .red
                )

                if let freshestProjectionAt = projections?.freshestGeneratedAt {
                    opsStatusPill(
                        title: "Projection \(freshestProjectionAt.formatted(date: .omitted, time: .shortened))",
                        color: .blue
                    )
                }
            }

            Picker("Ops Center Page", selection: $selectedPage) {
                ForEach(OpsCenterConsolePage.allCases) { page in
                    Label(page.title, systemImage: page.systemImage).tag(page)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(displayMode == .embedded ? 12 : 16)
        .background(Color.white.opacity(0.82))
    }

    @ViewBuilder
    private var pageContent: some View {
        switch selectedPage {
        case .liveRun:
            OpsCenterLiveRunDashboardView(
                workflow: selectedWorkflow,
                projections: projections,
                onSelectSession: openSessionInvestigation,
                onSelectNode: openNodeInvestigation
            )
        case .sessions:
            OpsCenterSessionsDashboardView(
                workflow: selectedWorkflow,
                projections: projections,
                onSelectSession: openSessionInvestigation
            )
        case .workflowMap:
            OpsCenterWorkflowMapDashboardView(
                workflow: selectedWorkflow,
                projections: projections,
                onSelectNode: openNodeInvestigation,
                onSelectRoute: openRouteInvestigation
            )
        case .history:
            OpsCenterHistoryDashboardView(
                workflow: selectedWorkflow,
                projections: projections,
                onSelectSession: openSessionInvestigation,
                onSelectNode: openNodeInvestigation
            )
        }
    }

    private var workflowSelectionBinding: Binding<UUID?> {
        Binding(
            get: { selectedWorkflowID ?? workflows.first?.id },
            set: { selectedWorkflowID = $0 }
        )
    }

    private func syncSelectedWorkflow() {
        let availableIDs = workflows.map(\.id)
        if let preferredWorkflowID, availableIDs.contains(preferredWorkflowID) {
            selectedWorkflowID = preferredWorkflowID
            return
        }

        if let selectedWorkflowID, availableIDs.contains(selectedWorkflowID) {
            return
        }

        selectedWorkflowID = workflows.first?.id
    }

    private func openSessionInvestigation(_ sessionID: String) {
        let liveInvestigation = OpsCenterSnapshotBuilder.buildSessionInvestigation(
            project: appState.currentProject,
            workflow: selectedWorkflow,
            sessionID: sessionID,
            tasks: appState.taskManager.tasks,
            messages: appState.messageManager.messages,
            executionResults: appState.openClawService.executionResults
        )

        let archiveInvestigation: OpsCenterSessionInvestigation?
        if let projectID = appState.currentProject?.id {
            archiveInvestigation = OpsCenterArchiveStore.loadSessionInvestigation(
                projectID: projectID,
                workflowID: selectedWorkflow?.id,
                sessionID: sessionID,
                projections: projections
            )
        } else {
            archiveInvestigation = nil
        }

        if let investigation = mergedSessionInvestigation(
            live: liveInvestigation,
            archive: archiveInvestigation
        ) {
            selectedInvestigation = .session(investigation)
            return
        }

        if let projectionSession = projections?.sessionSummaries(for: selectedWorkflow?.id).first(where: { $0.sessionID == sessionID }) {
            let scopeWorkflowID = selectedWorkflow?.id
            let relatedNodes = (projections?.nodesRuntime?.nodes ?? [])
                .filter { entry in
                    entry.relatedSessionIDs.contains(sessionID)
                        && (scopeWorkflowID == nil || entry.workflowID == scopeWorkflowID)
                }
                .map {
                    OpsCenterNodeSummary(
                        id: $0.nodeID,
                        title: $0.title,
                        agentName: $0.agentName,
                        status: projectionRuntimeStatus(from: $0.status),
                        incomingEdgeCount: $0.incomingEdgeCount,
                        outgoingEdgeCount: $0.outgoingEdgeCount,
                        lastUpdatedAt: $0.lastUpdatedAt,
                        latestDetail: $0.latestDetail,
                        averageDuration: $0.averageDuration
                    )
                }

            selectedInvestigation = .session(
                OpsCenterSessionInvestigation(
                    session: projectionSession,
                    relatedNodes: relatedNodes,
                    events: [],
                    dispatches: [],
                    receipts: [],
                    messages: [],
                    tasks: []
                )
            )
        }
    }

    private func openNodeInvestigation(_ nodeID: UUID) {
        let liveInvestigation = OpsCenterSnapshotBuilder.buildNodeInvestigation(
            project: appState.currentProject,
            workflow: selectedWorkflow,
            nodeID: nodeID,
            tasks: appState.taskManager.tasks,
            messages: appState.messageManager.messages,
            executionResults: appState.openClawService.executionResults
        )

        let archiveInvestigation: OpsCenterNodeInvestigation?
        if let projectID = appState.currentProject?.id {
            archiveInvestigation = OpsCenterArchiveStore.loadNodeInvestigation(
                projectID: projectID,
                workflowID: selectedWorkflow?.id,
                nodeID: nodeID,
                projections: projections
            )
        } else {
            archiveInvestigation = nil
        }

        if let investigation = mergedNodeInvestigation(
            live: liveInvestigation,
            archive: archiveInvestigation
        ) {
            selectedInvestigation = .node(investigation)
            return
        }

        if let projectionNode = projections?.nodeSummaries(for: selectedWorkflow?.id).first(where: { $0.id == nodeID }) {
            let relatedSessions = (projections?.sessions?.sessions ?? [])
                .filter { session in
                    (projections?.nodesRuntime?.nodes.first(where: { $0.nodeID == nodeID })?.relatedSessionIDs.contains(session.sessionID) ?? false)
                }
                .map {
                    OpsCenterSessionSummary(
                        sessionID: $0.sessionID,
                        workflowIDs: $0.workflowIDs,
                        eventCount: $0.eventCount,
                        dispatchCount: $0.dispatchCount,
                        receiptCount: $0.receiptCount,
                        queuedDispatchCount: $0.queuedDispatchCount,
                        inflightDispatchCount: $0.inflightDispatchCount,
                        completedDispatchCount: $0.completedDispatchCount,
                        failedDispatchCount: $0.failedDispatchCount,
                        lastUpdatedAt: $0.lastUpdatedAt,
                        latestFailureText: $0.latestFailureText,
                        isPrimaryRuntimeSession: $0.isProjectRuntimeSession
                    )
                }

            selectedInvestigation = .node(
                OpsCenterNodeInvestigation(
                    workflowName: selectedWorkflow?.name ?? "Workflow",
                    node: projectionNode,
                    relatedSessions: relatedSessions,
                    incomingEdges: [],
                    outgoingEdges: [],
                    events: [],
                    dispatches: [],
                    receipts: [],
                    messages: [],
                    tasks: []
                )
            )
        }
    }

    private func openRouteInvestigation(_ edgeID: UUID) {
        let liveInvestigation = OpsCenterSnapshotBuilder.buildRouteInvestigation(
            project: appState.currentProject,
            workflow: selectedWorkflow,
            edgeID: edgeID,
            tasks: appState.taskManager.tasks,
            messages: appState.messageManager.messages,
            executionResults: appState.openClawService.executionResults
        )

        let archiveInvestigation: OpsCenterRouteInvestigation?
        if let projectID = appState.currentProject?.id {
            archiveInvestigation = OpsCenterArchiveStore.loadRouteInvestigation(
                projectID: projectID,
                workflowID: selectedWorkflow?.id,
                edgeID: edgeID,
                projections: projections
            )
        } else {
            archiveInvestigation = nil
        }

        if let investigation = mergedRouteInvestigation(
            live: liveInvestigation,
            archive: archiveInvestigation
        ) {
            selectedInvestigation = .route(investigation)
        }
    }

    private func refreshProjectionsIfNeeded(force: Bool = false) {
        guard let projectID = appState.currentProject?.id else {
            projections = nil
            return
        }

        let loaded = OpsCenterProjectionStore.load(
            projectID: projectID,
            appSupportRootDirectory: ProjectManager.shared.appSupportRootDirectory
        )

        if force {
            projections = loaded
            return
        }

        if projections?.freshestGeneratedAt != loaded?.freshestGeneratedAt
            || projections?.projectID != loaded?.projectID {
            projections = loaded
        }
    }

    private func projectionRuntimeStatus(from rawValue: String) -> OpsCenterRuntimeStatus {
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

    private func mergedSessionInvestigation(
        live: OpsCenterSessionInvestigation?,
        archive: OpsCenterSessionInvestigation?
    ) -> OpsCenterSessionInvestigation? {
        switch (live, archive) {
        case let (live?, archive?):
            return OpsCenterSessionInvestigation(
                session: mergedSessionSummary(live.session, archive.session),
                relatedNodes: mergedNodeSummaries(live.relatedNodes, archive.relatedNodes),
                events: mergedEventDigests(live.events, archive.events),
                dispatches: mergedDispatchDigests(live.dispatches, archive.dispatches),
                receipts: mergedReceiptDigests(live.receipts, archive.receipts),
                messages: mergedMessageDigests(live.messages, archive.messages),
                tasks: mergedTaskDigests(live.tasks, archive.tasks)
            )
        case let (live?, nil):
            return live
        case let (nil, archive?):
            return archive
        case (nil, nil):
            return nil
        }
    }

    private func mergedNodeInvestigation(
        live: OpsCenterNodeInvestigation?,
        archive: OpsCenterNodeInvestigation?
    ) -> OpsCenterNodeInvestigation? {
        switch (live, archive) {
        case let (live?, archive?):
            return OpsCenterNodeInvestigation(
                workflowName: preferredText(live.workflowName, archive.workflowName) ?? live.workflowName,
                node: mergedNodeSummary(live.node, archive.node),
                relatedSessions: mergedSessionSummaries(live.relatedSessions, archive.relatedSessions),
                incomingEdges: mergedEdgeSummaries(live.incomingEdges, archive.incomingEdges),
                outgoingEdges: mergedEdgeSummaries(live.outgoingEdges, archive.outgoingEdges),
                events: mergedEventDigests(live.events, archive.events),
                dispatches: mergedDispatchDigests(live.dispatches, archive.dispatches),
                receipts: mergedReceiptDigests(live.receipts, archive.receipts),
                messages: mergedMessageDigests(live.messages, archive.messages),
                tasks: mergedTaskDigests(live.tasks, archive.tasks)
            )
        case let (live?, nil):
            return live
        case let (nil, archive?):
            return archive
        case (nil, nil):
            return nil
        }
    }

    private func mergedRouteInvestigation(
        live: OpsCenterRouteInvestigation?,
        archive: OpsCenterRouteInvestigation?
    ) -> OpsCenterRouteInvestigation? {
        switch (live, archive) {
        case let (live?, archive?):
            return OpsCenterRouteInvestigation(
                workflowName: preferredText(live.workflowName, archive.workflowName) ?? live.workflowName,
                edge: mergedEdgeSummaries([live.edge], [archive.edge]).first ?? live.edge,
                upstreamNode: mergedOptionalNodeSummary(live.upstreamNode, archive.upstreamNode),
                downstreamNode: mergedOptionalNodeSummary(live.downstreamNode, archive.downstreamNode),
                relatedSessions: mergedSessionSummaries(live.relatedSessions, archive.relatedSessions),
                events: mergedEventDigests(live.events, archive.events),
                dispatches: mergedDispatchDigests(live.dispatches, archive.dispatches),
                receipts: mergedReceiptDigests(live.receipts, archive.receipts),
                messages: mergedMessageDigests(live.messages, archive.messages),
                tasks: mergedTaskDigests(live.tasks, archive.tasks)
            )
        case let (live?, nil):
            return live
        case let (nil, archive?):
            return archive
        case (nil, nil):
            return nil
        }
    }

    private func mergedSessionSummary(
        _ lhs: OpsCenterSessionSummary,
        _ rhs: OpsCenterSessionSummary
    ) -> OpsCenterSessionSummary {
        OpsCenterSessionSummary(
            sessionID: lhs.sessionID,
            workflowIDs: Array(Set(lhs.workflowIDs + rhs.workflowIDs)).sorted(),
            eventCount: max(lhs.eventCount, rhs.eventCount),
            dispatchCount: max(lhs.dispatchCount, rhs.dispatchCount),
            receiptCount: max(lhs.receiptCount, rhs.receiptCount),
            queuedDispatchCount: max(lhs.queuedDispatchCount, rhs.queuedDispatchCount),
            inflightDispatchCount: max(lhs.inflightDispatchCount, rhs.inflightDispatchCount),
            completedDispatchCount: max(lhs.completedDispatchCount, rhs.completedDispatchCount),
            failedDispatchCount: max(lhs.failedDispatchCount, rhs.failedDispatchCount),
            lastUpdatedAt: [lhs.lastUpdatedAt, rhs.lastUpdatedAt].compactMap { $0 }.max(),
            latestFailureText: preferredText(lhs.latestFailureText, rhs.latestFailureText),
            isPrimaryRuntimeSession: lhs.isPrimaryRuntimeSession || rhs.isPrimaryRuntimeSession
        )
    }

    private func mergedNodeSummary(
        _ lhs: OpsCenterNodeSummary,
        _ rhs: OpsCenterNodeSummary
    ) -> OpsCenterNodeSummary {
        OpsCenterNodeSummary(
            id: lhs.id,
            title: preferredText(lhs.title, rhs.title) ?? lhs.title,
            agentName: preferredText(lhs.agentName, rhs.agentName),
            status: mergedRuntimeStatus(lhs.status, rhs.status),
            incomingEdgeCount: max(lhs.incomingEdgeCount, rhs.incomingEdgeCount),
            outgoingEdgeCount: max(lhs.outgoingEdgeCount, rhs.outgoingEdgeCount),
            lastUpdatedAt: [lhs.lastUpdatedAt, rhs.lastUpdatedAt].compactMap { $0 }.max(),
            latestDetail: preferredText(lhs.latestDetail, rhs.latestDetail),
            averageDuration: lhs.averageDuration ?? rhs.averageDuration
        )
    }

    private func mergedOptionalNodeSummary(
        _ lhs: OpsCenterNodeSummary?,
        _ rhs: OpsCenterNodeSummary?
    ) -> OpsCenterNodeSummary? {
        switch (lhs, rhs) {
        case let (lhs?, rhs?):
            return mergedNodeSummary(lhs, rhs)
        case let (lhs?, nil):
            return lhs
        case let (nil, rhs?):
            return rhs
        case (nil, nil):
            return nil
        }
    }

    private func mergedEdgeSummaries(
        _ lhs: [OpsCenterEdgeSummary],
        _ rhs: [OpsCenterEdgeSummary]
    ) -> [OpsCenterEdgeSummary] {
        let merged = (lhs + rhs).reduce(into: [UUID: OpsCenterEdgeSummary]()) { partial, edge in
            guard let existing = partial[edge.id] else {
                partial[edge.id] = edge
                return
            }

            partial[edge.id] = OpsCenterEdgeSummary(
                id: existing.id,
                title: preferredText(existing.title, edge.title) ?? existing.title,
                fromTitle: preferredText(existing.fromTitle, edge.fromTitle) ?? existing.fromTitle,
                toTitle: preferredText(existing.toTitle, edge.toTitle) ?? existing.toTitle,
                activityCount: max(existing.activityCount, edge.activityCount),
                requiresApproval: existing.requiresApproval || edge.requiresApproval
            )
        }

        return merged.values.sorted { lhs, rhs in
            if lhs.activityCount != rhs.activityCount {
                return lhs.activityCount > rhs.activityCount
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private func mergedSessionSummaries(
        _ lhs: [OpsCenterSessionSummary],
        _ rhs: [OpsCenterSessionSummary]
    ) -> [OpsCenterSessionSummary] {
        let merged = (lhs + rhs).reduce(into: [String: OpsCenterSessionSummary]()) { partial, session in
            if let existing = partial[session.sessionID] {
                partial[session.sessionID] = mergedSessionSummary(existing, session)
            } else {
                partial[session.sessionID] = session
            }
        }

        return merged.values.sorted { lhs, rhs in
            if lhs.isPrimaryRuntimeSession != rhs.isPrimaryRuntimeSession {
                return lhs.isPrimaryRuntimeSession
            }
            return (lhs.lastUpdatedAt ?? .distantPast) > (rhs.lastUpdatedAt ?? .distantPast)
        }
    }

    private func mergedNodeSummaries(
        _ lhs: [OpsCenterNodeSummary],
        _ rhs: [OpsCenterNodeSummary]
    ) -> [OpsCenterNodeSummary] {
        let merged = (lhs + rhs).reduce(into: [UUID: OpsCenterNodeSummary]()) { partial, node in
            if let existing = partial[node.id] {
                partial[node.id] = mergedNodeSummary(existing, node)
            } else {
                partial[node.id] = node
            }
        }

        return merged.values.sorted { lhs, rhs in
            let lhsPriority = runtimeStatusPriority(lhs.status)
            let rhsPriority = runtimeStatusPriority(rhs.status)
            if lhsPriority != rhsPriority {
                return lhsPriority < rhsPriority
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private func mergedDispatchDigests(
        _ lhs: [OpsCenterDispatchDigest],
        _ rhs: [OpsCenterDispatchDigest]
    ) -> [OpsCenterDispatchDigest] {
        let merged = (lhs + rhs).reduce(into: [String: OpsCenterDispatchDigest]()) { partial, dispatch in
            if let existing = partial[dispatch.id], existing.updatedAt >= dispatch.updatedAt {
                return
            }
            partial[dispatch.id] = dispatch
        }

        return merged.values.sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.id > rhs.id
        }
    }

    private func mergedEventDigests(
        _ lhs: [OpsCenterEventDigest],
        _ rhs: [OpsCenterEventDigest]
    ) -> [OpsCenterEventDigest] {
        let merged = (lhs + rhs).reduce(into: [String: OpsCenterEventDigest]()) { partial, event in
            if let existing = partial[event.id], existing.timestamp >= event.timestamp {
                return
            }
            partial[event.id] = event
        }

        return merged.values.sorted { lhs, rhs in
            if lhs.timestamp != rhs.timestamp {
                return lhs.timestamp > rhs.timestamp
            }
            return lhs.id > rhs.id
        }
    }

    private func mergedReceiptDigests(
        _ lhs: [OpsCenterReceiptDigest],
        _ rhs: [OpsCenterReceiptDigest]
    ) -> [OpsCenterReceiptDigest] {
        let merged = (lhs + rhs).reduce(into: [UUID: OpsCenterReceiptDigest]()) { partial, receipt in
            if let existing = partial[receipt.id], existing.timestamp >= receipt.timestamp {
                return
            }
            partial[receipt.id] = receipt
        }

        return merged.values.sorted { lhs, rhs in
            if lhs.timestamp != rhs.timestamp {
                return lhs.timestamp > rhs.timestamp
            }
            return lhs.id.uuidString > rhs.id.uuidString
        }
    }

    private func mergedMessageDigests(
        _ lhs: [OpsCenterMessageDigest],
        _ rhs: [OpsCenterMessageDigest]
    ) -> [OpsCenterMessageDigest] {
        let merged = (lhs + rhs).reduce(into: [UUID: OpsCenterMessageDigest]()) { partial, message in
            if let existing = partial[message.id], existing.timestamp >= message.timestamp {
                return
            }
            partial[message.id] = message
        }

        return merged.values.sorted { lhs, rhs in
            if lhs.timestamp != rhs.timestamp {
                return lhs.timestamp > rhs.timestamp
            }
            return lhs.id.uuidString > rhs.id.uuidString
        }
    }

    private func mergedTaskDigests(
        _ lhs: [OpsCenterTaskDigest],
        _ rhs: [OpsCenterTaskDigest]
    ) -> [OpsCenterTaskDigest] {
        let merged = (lhs + rhs).reduce(into: [UUID: OpsCenterTaskDigest]()) { partial, task in
            if let existing = partial[task.id], existing.timestamp >= task.timestamp {
                return
            }
            partial[task.id] = task
        }

        return merged.values.sorted { lhs, rhs in
            if lhs.timestamp != rhs.timestamp {
                return lhs.timestamp > rhs.timestamp
            }
            return lhs.id.uuidString > rhs.id.uuidString
        }
    }

    private func preferredText(_ primary: String?, _ fallback: String?) -> String? {
        let primaryValue = primary?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let primaryValue, !primaryValue.isEmpty {
            return primaryValue
        }

        let fallbackValue = fallback?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let fallbackValue, !fallbackValue.isEmpty {
            return fallbackValue
        }

        return nil
    }

    private func mergedRuntimeStatus(
        _ lhs: OpsCenterRuntimeStatus,
        _ rhs: OpsCenterRuntimeStatus
    ) -> OpsCenterRuntimeStatus {
        runtimeStatusPriority(lhs) <= runtimeStatusPriority(rhs) ? lhs : rhs
    }

    private func runtimeStatusPriority(_ status: OpsCenterRuntimeStatus) -> Int {
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

private struct OpsCenterLiveRunDashboardView: View {
    @EnvironmentObject var appState: AppState
    let workflow: Workflow?
    let projections: OpsCenterProjectionBundle?
    let onSelectSession: (String) -> Void
    let onSelectNode: (UUID) -> Void

    private var snapshot: OpsCenterLiveRunSnapshot {
        OpsCenterSnapshotBuilder.buildLiveRunSnapshot(
            project: appState.currentProject,
            workflow: workflow,
            tasks: appState.taskManager.tasks,
            messages: appState.messageManager.messages,
            executionResults: appState.openClawService.executionResults
        )
    }

    private var effectiveNodeSummaries: [OpsCenterNodeSummary] {
        snapshot.nodeSummaries.isEmpty ? (projections?.nodeSummaries(for: workflow?.id) ?? []) : snapshot.nodeSummaries
    }

    private var effectiveSessionSummaries: [OpsCenterSessionSummary] {
        snapshot.sessionSummaries.isEmpty ? (projections?.sessionSummaries(for: workflow?.id) ?? []) : snapshot.sessionSummaries
    }

    private var effectiveActiveSessionCount: Int {
        if !effectiveSessionSummaries.isEmpty {
            return effectiveSessionSummaries.filter {
                $0.queuedDispatchCount > 0 || $0.inflightDispatchCount > 0
            }.count
        }
        return projections?.liveRunEntry(for: workflow?.id)?.activeSessionCount
            ?? projections?.liveRun?.activeSessionCount
            ?? snapshot.activeSessionCount
    }

    private var effectiveTotalSessionCount: Int {
        if !effectiveSessionSummaries.isEmpty {
            return effectiveSessionSummaries.count
        }
        return projections?.liveRunEntry(for: workflow?.id)?.sessionCount
            ?? projections?.liveRun?.totalSessionCount
            ?? snapshot.totalSessionCount
    }

    private var effectiveFailureCount: Int {
        if snapshot.failedDispatchCount > 0 {
            return snapshot.failedDispatchCount
        }
        return projections?.workflowHealthEntry(for: workflow?.id)?.recentFailureCount
            ?? projections?.liveRunEntry(for: workflow?.id)?.failedNodeCount
            ?? projections?.liveRun?.failedDispatchCount
            ?? 0
    }

    private var effectiveApprovalCount: Int {
        if snapshot.waitingApprovalCount > 0 {
            return snapshot.waitingApprovalCount
        }
        return projections?.workflowHealthEntry(for: workflow?.id)?.pendingApprovalCount
            ?? projections?.liveRunEntry(for: workflow?.id)?.waitingApprovalNodeCount
            ?? projections?.liveRun?.waitingApprovalCount
            ?? 0
    }

    private var projectionContextText: String? {
        guard snapshot.nodeSummaries.isEmpty || snapshot.sessionSummaries.isEmpty,
              let freshestProjectionAt = projections?.freshestGeneratedAt else {
            return nil
        }
        return "Showing persisted projection support from \(freshestProjectionAt.formatted(date: .abbreviated, time: .shortened)) while live runtime state is sparse."
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if workflow == nil {
                    opsEmptyState(
                        title: "No workflow available",
                        detail: "Create or select a workflow to inspect live runtime posture."
                    )
                } else {
                    sectionTitle("Current Runtime")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 14)], spacing: 14) {
                        opsMetricCard(title: "Workflow", value: snapshot.workflowName, detail: "Selected runtime surface", color: .blue)
                        opsMetricCard(title: "Active Sessions", value: "\(effectiveActiveSessionCount)", detail: "\(effectiveTotalSessionCount) visible in current scope", color: .green)
                        opsMetricCard(title: "Queued", value: "\(snapshot.queuedDispatchCount)", detail: "Dispatches waiting to move", color: .blue)
                        opsMetricCard(title: "Running", value: "\(snapshot.inflightDispatchCount)", detail: "Inflight dispatches", color: .orange)
                        opsMetricCard(title: "Failures", value: "\(effectiveFailureCount)", detail: snapshot.latestErrorText ?? projections?.liveRun?.latestErrorText ?? "No recent runtime failure text", color: effectiveFailureCount > 0 ? .red : .green)
                        opsMetricCard(title: "Approvals", value: "\(effectiveApprovalCount)", detail: "Pending approval gates", color: effectiveApprovalCount > 0 ? .yellow : .secondary)
                    }

                    if let projectionContextText {
                        Text(projectionContextText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Text("Select a node or session to open the investigation panel with linked events, dispatches, receipts, and workbench history.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    sectionTitle("Hot Nodes")
                    VStack(spacing: 8) {
                        ForEach(effectiveNodeSummaries.prefix(8)) { node in
                            Button {
                                onSelectNode(node.id)
                            } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    opsStatusPill(title: node.status.title, color: node.status.color)
                                        .frame(width: 84, alignment: .leading)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(node.title)
                                            .font(.subheadline.weight(.medium))
                                            .foregroundColor(.primary)
                                        Text(node.agentName ?? "No bound agent")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        if let latestDetail = node.latestDetail, !latestDetail.isEmpty {
                                            Text(latestDetail)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .lineLimit(2)
                                        }
                                    }

                                    Spacer()

                                    VStack(alignment: .trailing, spacing: 4) {
                                        Text("In \(node.incomingEdgeCount) / Out \(node.outgoingEdgeCount)")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        if let averageDuration = node.averageDuration {
                                            Text("Avg \(opsDurationText(averageDuration))")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                        if let lastUpdatedAt = node.lastUpdatedAt {
                                            Text(lastUpdatedAt.formatted(date: .omitted, time: .shortened))
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                                .padding(10)
                                .background(Color(.controlBackgroundColor))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    sectionTitle("Active Sessions")
                    VStack(spacing: 8) {
                        ForEach(effectiveSessionSummaries.prefix(6)) { session in
                            Button {
                                onSelectSession(session.sessionID)
                            } label: {
                                sessionRow(session)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding()
        }
    }

    private func sessionRow(_ session: OpsCenterSessionSummary) -> some View {
        HStack(alignment: .top, spacing: 12) {
            opsStatusPill(
                title: session.isPrimaryRuntimeSession ? "Primary" : "Session",
                color: session.isPrimaryRuntimeSession ? .teal : .secondary
            )
            .frame(width: 72, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(session.sessionID)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.primary)
                Text(
                    [
                        "Events \(session.eventCount)",
                        "Dispatches \(session.dispatchCount)",
                        "Receipts \(session.receiptCount)"
                    ]
                    .joined(separator: " • ")
                )
                .font(.caption)
                .foregroundColor(.secondary)

                if let latestFailureText = session.latestFailureText {
                    Text(latestFailureText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("Q \(session.queuedDispatchCount) / R \(session.inflightDispatchCount)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text("F \(session.failedDispatchCount) / C \(session.completedDispatchCount)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                if let lastUpdatedAt = session.lastUpdatedAt {
                    Text(lastUpdatedAt.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(10)
        .background(Color(.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct OpsCenterSessionsDashboardView: View {
    @EnvironmentObject var appState: AppState
    let workflow: Workflow?
    let projections: OpsCenterProjectionBundle?
    let onSelectSession: (String) -> Void

    private var sessions: [OpsCenterSessionSummary] {
        OpsCenterSnapshotBuilder.buildSessionSummaries(
            project: appState.currentProject,
            workflow: workflow,
            tasks: appState.taskManager.tasks,
            messages: appState.messageManager.messages,
            executionResults: appState.openClawService.executionResults
        )
    }

    private var effectiveSessions: [OpsCenterSessionSummary] {
        sessions.isEmpty ? (projections?.sessionSummaries(for: workflow?.id) ?? []) : sessions
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                sectionTitle("Session Investigation Queue")
                if effectiveSessions.isEmpty {
                    opsEmptyState(
                        title: "No runtime sessions captured",
                        detail: "Sessions will appear after workbench or workflow runtime activity enters the managed project runtime store."
                    )
                } else {
                    Text("Open any session to inspect related runtime events, receipts, dispatch pressure, and workbench context together.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if sessions.isEmpty, let freshestProjectionAt = projections?.freshestGeneratedAt {
                        Text("Using persisted session projections from \(freshestProjectionAt.formatted(date: .abbreviated, time: .shortened)).")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    ForEach(effectiveSessions) { session in
                        Button {
                            onSelectSession(session.sessionID)
                        } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text(session.sessionID)
                                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                        .foregroundColor(.primary)
                                    Spacer()
                                    opsStatusPill(
                                        title: session.isPrimaryRuntimeSession ? "Primary Runtime Session" : "Linked Session",
                                        color: session.isPrimaryRuntimeSession ? .teal : .blue
                                    )
                                }

                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                                    opsMetricCard(title: "Events", value: "\(session.eventCount)", detail: "Runtime event count", color: .blue)
                                    opsMetricCard(title: "Dispatches", value: "\(session.dispatchCount)", detail: "Queued + inflight + terminal", color: .orange)
                                    opsMetricCard(title: "Receipts", value: "\(session.receiptCount)", detail: "Execution receipts in scope", color: .green)
                                    opsMetricCard(title: "Failures", value: "\(session.failedDispatchCount)", detail: session.latestFailureText ?? "No recent failure text", color: session.failedDispatchCount > 0 ? .red : .green)
                                }

                                HStack(spacing: 12) {
                                    Text(
                                        session.workflowIDs.isEmpty
                                            ? "No workflow IDs resolved yet"
                                            : "Workflow IDs: \(session.workflowIDs.joined(separator: ", "))"
                                    )
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                    Spacer()

                                    if let lastUpdatedAt = session.lastUpdatedAt {
                                        Text("Updated \(lastUpdatedAt.formatted(date: .abbreviated, time: .shortened))")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .padding()
                            .background(Color(.controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
        }
    }
}

private struct OpsCenterWorkflowMapDashboardView: View {
    @EnvironmentObject var appState: AppState
    let workflow: Workflow?
    let projections: OpsCenterProjectionBundle?
    let onSelectNode: (UUID) -> Void
    let onSelectRoute: (UUID) -> Void

    @State private var selectedLayer: OpsCenterMapLayer = .state

    private var snapshot: OpsCenterLiveRunSnapshot {
        OpsCenterSnapshotBuilder.buildLiveRunSnapshot(
            project: appState.currentProject,
            workflow: workflow,
            tasks: appState.taskManager.tasks,
            messages: appState.messageManager.messages,
            executionResults: appState.openClawService.executionResults
        )
    }

    private var effectiveNodeSummaries: [OpsCenterNodeSummary] {
        snapshot.nodeSummaries.isEmpty ? (projections?.nodeSummaries(for: workflow?.id) ?? []) : snapshot.nodeSummaries
    }

    private var effectiveEdgeSummaries: [OpsCenterEdgeSummary] {
        if !snapshot.edgeSummaries.isEmpty {
            return snapshot.edgeSummaries
        }

        guard let workflow else { return [] }
        let projectionNodesByID = Dictionary(
            uniqueKeysWithValues: (projections?.nodesRuntime?.nodes ?? [])
                .filter { $0.workflowID == workflow.id }
                .map { ($0.nodeID, $0) }
        )

        return workflow.edges.map { edge in
            let fromEntry = projectionNodesByID[edge.fromNodeID]
            let toEntry = projectionNodesByID[edge.toNodeID]
            let activityCount = Set(fromEntry?.relatedSessionIDs ?? [])
                .intersection(Set(toEntry?.relatedSessionIDs ?? []))
                .count

            return OpsCenterEdgeSummary(
                id: edge.id,
                title: edge.label.isEmpty ? "Path" : edge.label,
                fromTitle: workflow.nodes.first(where: { $0.id == edge.fromNodeID })?.title ?? "Unknown",
                toTitle: workflow.nodes.first(where: { $0.id == edge.toNodeID })?.title ?? "Unknown",
                activityCount: activityCount,
                requiresApproval: edge.requiresApproval
            )
        }
    }

    private var scopedNodeIDs: Set<UUID> {
        if let workflow {
            return Set(workflow.nodes.map(\.id))
        }
        return Set(appState.currentProject?.workflows.flatMap(\.nodes).map(\.id) ?? [])
    }

    private var nodeSummaryByID: [UUID: OpsCenterNodeSummary] {
        Dictionary(uniqueKeysWithValues: effectiveNodeSummaries.map { ($0.id, $0) })
    }

    private var historyAnomaliesByNodeID: [UUID: [OpsCenterProjectionAnomalyEntry]] {
        let items = (projections?.anomalies?.anomalies ?? []).filter { entry in
            guard let nodeID = entry.nodeID else { return false }
            return scopedNodeIDs.contains(nodeID)
        }
        var grouped: [UUID: [OpsCenterProjectionAnomalyEntry]] = [:]
        for item in items {
            guard let nodeID = item.nodeID else { continue }
            grouped[nodeID, default: []].append(item)
        }
        return grouped
    }

    private var latestProjectionTraceByNodeID: [UUID: OpsCenterProjectionTraceEntry] {
        let traces = (projections?.traces?.traces ?? [])
            .filter { scopedNodeIDs.contains($0.nodeID) }
            .sorted { lhs, rhs in
                let lhsDate = lhs.completedAt ?? lhs.startedAt
                let rhsDate = rhs.completedAt ?? rhs.startedAt
                if lhsDate != rhsDate {
                    return lhsDate > rhsDate
                }
                return lhs.executionID.uuidString > rhs.executionID.uuidString
            }

        var latestByNodeID: [UUID: OpsCenterProjectionTraceEntry] = [:]
        for trace in traces where latestByNodeID[trace.nodeID] == nil {
            latestByNodeID[trace.nodeID] = trace
        }
        return latestByNodeID
    }

    private var latestLiveResultByNodeID: [UUID: ExecutionResult] {
        let results = appState.openClawService.executionResults
            .filter { scopedNodeIDs.contains($0.nodeID) }
            .sorted { lhs, rhs in
                let lhsDate = lhs.completedAt ?? lhs.startedAt
                let rhsDate = rhs.completedAt ?? rhs.startedAt
                if lhsDate != rhsDate {
                    return lhsDate > rhsDate
                }
                return lhs.id.uuidString > rhs.id.uuidString
            }

        var latestByNodeID: [UUID: ExecutionResult] = [:]
        for result in results where latestByNodeID[result.nodeID] == nil {
            latestByNodeID[result.nodeID] = result
        }
        return latestByNodeID
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    sectionTitle("Workflow Runtime Map")
                    Spacer()
                    Picker("Layer", selection: $selectedLayer) {
                        ForEach(OpsCenterMapLayer.allCases) { layer in
                            Text(layer.title).tag(layer)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 360)
                }

                if workflow == nil {
                    opsEmptyState(
                        title: "No workflow selected",
                        detail: "Workflow Map needs a concrete workflow to project runtime state."
                    )
                } else {
                    Text(selectedLayer.detail)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if snapshot.nodeSummaries.isEmpty, let freshestProjectionAt = projections?.freshestGeneratedAt {
                        Text("Rendering persisted node-runtime projection from \(freshestProjectionAt.formatted(date: .abbreviated, time: .shortened)).")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 14)], spacing: 14) {
                        ForEach(effectiveNodeSummaries) { node in
                            Button {
                                onSelectNode(node.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(node.title)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundColor(.primary)
                                            Text(node.agentName ?? "No bound agent")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        Circle()
                                            .fill(node.status.color)
                                            .frame(width: 10, height: 10)
                                    }

                                    HStack(spacing: 8) {
                                        opsStatusPill(title: node.status.title, color: node.status.color)
                                        if let averageDuration = node.averageDuration {
                                            opsStatusPill(title: opsDurationText(averageDuration), color: .secondary)
                                        }
                                        let anomalyCount = historyAnomalyCount(for: node)
                                        if anomalyCount > 0 {
                                            opsStatusPill(
                                                title: "\(anomalyCount) anomalies",
                                                color: anomalyCount > 2 ? .red : .orange
                                            )
                                        }
                                    }

                                    Text(layerDetail(for: node))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(3)

                                    if let historyTraceSummary = historyTraceSummary(for: node), !historyTraceSummary.isEmpty {
                                        Text(historyTraceSummary)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                            .lineLimit(2)
                                    }

                                    HStack {
                                        Text("In \(node.incomingEdgeCount)")
                                        Text("Out \(node.outgoingEdgeCount)")
                                        Spacer()
                                        if let lastUpdatedAt = node.lastUpdatedAt {
                                            Text(lastUpdatedAt.formatted(date: .omitted, time: .shortened))
                                        }
                                    }
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                }
                                .padding()
                                .background(Color(.controlBackgroundColor))
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    sectionTitle("Edge Activity")
                    VStack(spacing: 8) {
                        ForEach(effectiveEdgeSummaries) { edge in
                            let routeAnomalyCount = historyAnomalyCount(forEdge: edge)
                            let routeSharedSessionCount = sharedSessionCount(forEdge: edge)
                            let downstreamStatus = downstreamNodeStatus(forEdge: edge)

                            Button {
                                onSelectRoute(edge.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text("\(edge.fromTitle) -> \(edge.toTitle)")
                                                .font(.caption.weight(.medium))
                                                .foregroundColor(.primary)
                                            Text(edge.title)
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        if let downstreamStatus {
                                            opsStatusPill(title: downstreamStatus.title, color: downstreamStatus.color)
                                        }
                                    }

                                    HStack(spacing: 8) {
                                        opsStatusPill(
                                            title: "Flow \(edge.activityCount)",
                                            color: edge.activityCount > 0 ? .blue : .secondary
                                        )

                                        if routeSharedSessionCount > 0 {
                                            opsStatusPill(
                                                title: "Shared \(routeSharedSessionCount)",
                                                color: routeSharedSessionCount > 1 ? .orange : .secondary
                                            )
                                        }

                                        if routeAnomalyCount > 0 {
                                            opsStatusPill(
                                                title: "\(routeAnomalyCount) anomalies",
                                                color: routeAnomalyCount > 2 ? .red : .orange
                                            )
                                        }

                                        if edge.requiresApproval {
                                            opsStatusPill(title: "Approval", color: .yellow)
                                        }
                                    }

                                    Text(routeDetailText(for: edge))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(3)

                                    if let routeTraceSummary = routeTraceSummary(for: edge), !routeTraceSummary.isEmpty {
                                        Text(routeTraceSummary)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                                .padding(10)
                                .background(Color(.controlBackgroundColor))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding()
        }
    }

    private func layerDetail(for node: OpsCenterNodeSummary) -> String {
        switch selectedLayer {
        case .state:
            return node.latestDetail ?? "No runtime detail captured for this node yet."
        case .latency:
            return node.averageDuration.map { "Average runtime \(opsDurationText($0))." } ?? "No average runtime captured yet."
        case .failures:
            return node.status == .failed
                ? (node.latestDetail ?? "This node currently surfaces a failure signal.")
                : "No active failure signal for this node."
        case .routing:
            return "Incoming edges \(node.incomingEdgeCount), outgoing edges \(node.outgoingEdgeCount). Use this layer to inspect where flow density is concentrating."
        case .approvals:
            return node.status == .waitingApproval
                ? "This node is currently blocked by an approval gate."
                : "No active approval gate detected on this node."
        case .files:
            return "File scope overlays will be projected here as workflow-derived file access data is migrated into the new Ops Center surfaces."
        }
    }

    private func historyAnomalyCount(for node: OpsCenterNodeSummary) -> Int {
        historyAnomaliesByNodeID[node.id]?.count ?? 0
    }

    private func historyTraceSummary(for node: OpsCenterNodeSummary) -> String? {
        if let trace = latestProjectionTraceByNodeID[node.id] {
            let statusText = trace.status.rawValue
            let summary = compactWorkflowMapPreview(trace.previewText, limit: 110)
            return "Recent trace: \(statusText) • \(summary)"
        }

        if let result = latestLiveResultByNodeID[node.id] {
            let summary = compactWorkflowMapPreview(result.summaryText, limit: 110)
            return "Live trace: \(result.status.rawValue) • \(summary)"
        }

        return nil
    }

    private func compactWorkflowMapPreview(_ text: String, limit: Int) -> String {
        let singleLine = text
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !singleLine.isEmpty else { return "No retained trace summary." }
        guard singleLine.count > limit else { return singleLine }
        return "\(singleLine.prefix(limit))..."
    }

    private func historyAnomalyCount(forEdge edge: OpsCenterEdgeSummary) -> Int {
        guard let workflow else { return 0 }
        guard let workflowEdge = workflow.edges.first(where: { $0.id == edge.id }) else { return 0 }
        let fromCount = historyAnomaliesByNodeID[workflowEdge.fromNodeID]?.count ?? 0
        let toCount = historyAnomaliesByNodeID[workflowEdge.toNodeID]?.count ?? 0
        return fromCount + toCount
    }

    private func sharedSessionCount(forEdge edge: OpsCenterEdgeSummary) -> Int {
        guard let workflow else { return 0 }
        guard let workflowEdge = workflow.edges.first(where: { $0.id == edge.id }) else { return 0 }

        let projectionNodesByID = Dictionary(
            uniqueKeysWithValues: (projections?.nodesRuntime?.nodes ?? [])
                .filter { $0.workflowID == workflow.id }
                .map { ($0.nodeID, $0) }
        )

        let fromSessions = Set(projectionNodesByID[workflowEdge.fromNodeID]?.relatedSessionIDs ?? [])
        let toSessions = Set(projectionNodesByID[workflowEdge.toNodeID]?.relatedSessionIDs ?? [])
        return fromSessions.intersection(toSessions).count
    }

    private func downstreamNodeStatus(forEdge edge: OpsCenterEdgeSummary) -> OpsCenterRuntimeStatus? {
        guard let workflow else { return nil }
        guard let workflowEdge = workflow.edges.first(where: { $0.id == edge.id }) else { return nil }
        return nodeSummaryByID[workflowEdge.toNodeID]?.status
    }

    private func routeDetailText(for edge: OpsCenterEdgeSummary) -> String {
        let anomalyCount = historyAnomalyCount(forEdge: edge)
        let sessionCount = sharedSessionCount(forEdge: edge)

        if anomalyCount > 0 {
            return "Route carries \(anomalyCount) retained anomaly signal(s) across its connected nodes."
        }
        if sessionCount > 0 {
            return "Route is shared by \(sessionCount) retained session(s) in the persisted runtime projection."
        }
        if edge.activityCount > 0 {
            return "Route is currently active in live or projected runtime flow."
        }
        if edge.requiresApproval {
            return "Route includes an approval gate and should be watched for operator latency."
        }
        return "No recent retained congestion or failure signal on this route."
    }

    private func routeTraceSummary(for edge: OpsCenterEdgeSummary) -> String? {
        guard let workflow else { return nil }
        guard let workflowEdge = workflow.edges.first(where: { $0.id == edge.id }) else { return nil }

        if let downstreamNode = nodeSummaryByID[workflowEdge.toNodeID],
           let summary = historyTraceSummary(for: downstreamNode) {
            return summary
        }

        if let upstreamNode = nodeSummaryByID[workflowEdge.fromNodeID],
           let summary = historyTraceSummary(for: upstreamNode) {
            return summary
        }

        return nil
    }
}

private struct OpsCenterHistoryGoalDigest: Identifiable {
    let id: String
    let title: String
    let valueText: String
    let detailText: String
    let status: OpsHealthStatus
}

private struct OpsCenterHistoryAnomalyDigest: Identifiable {
    let id: String
    let title: String
    let sourceLabel: String
    let detailText: String
    let timestamp: Date
    let status: OpsHealthStatus
    let sessionID: String?
    let nodeID: UUID?
}

private struct OpsCenterHistoryTraceDigest: Identifiable {
    let id: String
    let title: String
    let agentName: String
    let sourceLabel: String
    let statusText: String
    let previewText: String
    let outputTypeText: String
    let timestamp: Date
    let duration: TimeInterval?
    let protocolRepairCount: Int
    let sessionID: String?
    let nodeID: UUID?
}

private struct OpsCenterHistoryDashboardView: View {
    @EnvironmentObject var appState: AppState
    let workflow: Workflow?
    let projections: OpsCenterProjectionBundle?
    let onSelectSession: (String) -> Void
    let onSelectNode: (UUID) -> Void

    private var snapshot: OpsAnalyticsSnapshot {
        appState.opsAnalytics.snapshot
    }

    private var executionResultsByID: [UUID: ExecutionResult] {
        Dictionary(uniqueKeysWithValues: appState.openClawService.executionResults.map { ($0.id, $0) })
    }

    private var scopedNodeIDs: Set<UUID> {
        if let workflow {
            return Set(workflow.nodes.map(\.id))
        }
        return Set(appState.currentProject?.workflows.flatMap(\.nodes).map(\.id) ?? [])
    }

    private var agentNamesByID: [UUID: String] {
        Dictionary(uniqueKeysWithValues: (appState.currentProject?.agents ?? []).map { ($0.id, $0.name) })
    }

    private var nodeTitlesByID: [UUID: String] {
        Dictionary(
            uniqueKeysWithValues: (appState.currentProject?.workflows.flatMap(\.nodes) ?? [])
                .map { ($0.id, $0.title) }
        )
    }

    private var effectiveGoalCards: [OpsCenterHistoryGoalDigest] {
        if !snapshot.goalCards.isEmpty {
            return snapshot.goalCards.map {
                OpsCenterHistoryGoalDigest(
                    id: $0.id,
                    title: $0.title,
                    valueText: $0.valueText,
                    detailText: $0.detailText,
                    status: $0.status
                )
            }
        }

        var cards: [OpsCenterHistoryGoalDigest] = []

        if let overview = projections?.overview {
            let totalExecutions = max(overview.executionResultCount, 1)
            let successRate = Int((Double(overview.completedExecutionCount) / Double(totalExecutions) * 100).rounded())
            cards.append(
                OpsCenterHistoryGoalDigest(
                    id: "projection-reliability",
                    title: "Execution Reliability",
                    valueText: "\(successRate)%",
                    detailText: "\(overview.completedExecutionCount) completed / \(overview.failedExecutionCount) failed from persisted runtime traces",
                    status: overview.failedExecutionCount > 0 ? .warning : .healthy
                )
            )
            cards.append(
                OpsCenterHistoryGoalDigest(
                    id: "projection-error-budget",
                    title: "Error Budget",
                    valueText: "\(overview.errorLogCount)",
                    detailText: "\(overview.warningLogCount) warnings retained in persisted analytics snapshot",
                    status: overview.errorLogCount > 0 ? .critical : (overview.warningLogCount > 0 ? .warning : .healthy)
                )
            )
            cards.append(
                OpsCenterHistoryGoalDigest(
                    id: "projection-approvals",
                    title: "Approval Pressure",
                    valueText: "\(overview.pendingApprovalCount)",
                    detailText: "Pending approval gates captured in the latest filesystem projection",
                    status: overview.pendingApprovalCount > 0 ? .warning : .healthy
                )
            )
        }

        if let liveRun = projections?.liveRunEntry(for: workflow?.id) ?? projections?.liveRun.map({
            OpsCenterProjectionWorkflowLiveRunEntry(
                workflowID: workflow?.id ?? UUID(),
                workflowName: workflow?.name ?? "Project Runtime",
                sessionCount: $0.totalSessionCount,
                activeSessionCount: $0.activeSessionCount,
                activeNodeCount: 0,
                failedNodeCount: 0,
                waitingApprovalNodeCount: $0.waitingApprovalCount,
                lastUpdatedAt: $0.generatedAt
            )
        }) {
            cards.append(
                OpsCenterHistoryGoalDigest(
                    id: "projection-sessions",
                    title: "Session Load",
                    valueText: "\(liveRun.activeSessionCount) / \(liveRun.sessionCount)",
                    detailText: "Active versus visible sessions in the persisted runtime projection",
                    status: liveRun.activeSessionCount > 0 ? .warning : .neutral
                )
            )
        }

        if let workflowHealth = projections?.workflowHealthEntry(for: workflow?.id) {
            cards.append(
                OpsCenterHistoryGoalDigest(
                    id: "projection-workflow-health",
                    title: "Workflow Hotspots",
                    valueText: "\(workflowHealth.failedNodeCount)",
                    detailText: "\(workflowHealth.waitingApprovalNodeCount) approval nodes and \(workflowHealth.activeNodeCount) active nodes in current health projection",
                    status: workflowHealth.failedNodeCount > 0 ? .critical : (workflowHealth.waitingApprovalNodeCount > 0 ? .warning : .healthy)
                )
            )
        }

        return cards
    }

    private var effectiveAnomalies: [OpsCenterHistoryAnomalyDigest] {
        let liveItems = snapshot.anomalyRows.map {
            let linkedResult = $0.linkedSessionSpanID.flatMap { executionResultsByID[$0] }
            return OpsCenterHistoryAnomalyDigest(
                id: "live-\($0.id)",
                title: $0.title,
                sourceLabel: $0.sourceLabel,
                detailText: $0.detailText,
                timestamp: $0.occurredAt,
                status: $0.status,
                sessionID: linkedResult?.sessionID,
                nodeID: linkedResult?.nodeID
            )
        }

        let persistedItems = (projections?.anomalies?.anomalies ?? [])
            .filter { entry in
                guard let workflow else { return true }
                guard let nodeID = entry.nodeID else { return true }
                return scopedNodeIDs.contains(nodeID) && workflow.nodes.contains(where: { $0.id == nodeID })
            }
            .map { entry in
                let status: OpsHealthStatus = {
                    switch entry.severity.lowercased() {
                    case "error":
                        return .critical
                    case "warning":
                        return .warning
                    default:
                        return .neutral
                    }
                }()

                return OpsCenterHistoryAnomalyDigest(
                    id: "projection-\(entry.id)",
                    title: nodeTitlesByID[entry.nodeID ?? UUID()] ?? entry.source.capitalized,
                    sourceLabel: entry.source.capitalized,
                    detailText: entry.message,
                    timestamp: entry.timestamp,
                    status: status,
                    sessionID: entry.sessionID,
                    nodeID: entry.nodeID
                )
            }

        let merged = (liveItems + persistedItems).reduce(into: [String: OpsCenterHistoryAnomalyDigest]()) { partial, item in
            let dedupeKey = "\(item.title)|\(item.detailText)|\(item.timestamp.timeIntervalSince1970)"
            if let existing = partial[dedupeKey], existing.timestamp >= item.timestamp {
                return
            }
            partial[dedupeKey] = item
        }

        return merged.values.sorted { lhs, rhs in
            if lhs.timestamp != rhs.timestamp {
                return lhs.timestamp > rhs.timestamp
            }
            return lhs.id > rhs.id
        }
    }

    private var effectiveTraces: [OpsCenterHistoryTraceDigest] {
        let liveItems = snapshot.traceRows.map {
            let linkedResult = executionResultsByID[$0.id]
            return OpsCenterHistoryTraceDigest(
                id: "live-\($0.id.uuidString)",
                title: $0.sourceLabel,
                agentName: $0.agentName,
                sourceLabel: $0.sourceLabel,
                statusText: $0.status.rawValue,
                previewText: $0.previewText,
                outputTypeText: $0.outputType.rawValue,
                timestamp: $0.startedAt,
                duration: $0.duration,
                protocolRepairCount: $0.protocolRepairCount,
                sessionID: linkedResult?.sessionID,
                nodeID: linkedResult?.nodeID
            )
        }

        let persistedItems = (projections?.traces?.traces ?? [])
            .filter { entry in
                guard workflow != nil else { return true }
                return scopedNodeIDs.contains(entry.nodeID)
            }
            .map { entry in
                OpsCenterHistoryTraceDigest(
                    id: "projection-\(entry.executionID.uuidString)",
                    title: nodeTitlesByID[entry.nodeID] ?? "Runtime Trace",
                    agentName: agentNamesByID[entry.agentID] ?? "Unknown Agent",
                    sourceLabel: entry.sessionID ?? "Persisted Trace",
                    statusText: entry.status.rawValue,
                    previewText: entry.previewText,
                    outputTypeText: entry.outputType.rawValue,
                    timestamp: entry.completedAt ?? entry.startedAt,
                    duration: entry.duration,
                    protocolRepairCount: entry.protocolRepairCount,
                    sessionID: entry.sessionID,
                    nodeID: entry.nodeID
                )
            }

        let merged = (liveItems + persistedItems).reduce(into: [String: OpsCenterHistoryTraceDigest]()) { partial, item in
            let dedupeKey = item.id.replacingOccurrences(of: "live-", with: "").replacingOccurrences(of: "projection-", with: "")
            if let existing = partial[dedupeKey], existing.timestamp >= item.timestamp {
                return
            }
            partial[dedupeKey] = item
        }

        return merged.values.sorted { lhs, rhs in
            if lhs.timestamp != rhs.timestamp {
                return lhs.timestamp > rhs.timestamp
            }
            return lhs.id > rhs.id
        }
    }

    private var projectionSummaryText: String? {
        guard let freshestProjectionAt = projections?.freshestGeneratedAt else { return nil }
        return "Persisted analytics projection refreshed at \(freshestProjectionAt.formatted(date: .abbreviated, time: .shortened))."
    }

    private var averagePersistedTraceDuration: TimeInterval? {
        let durations = effectiveTraces.compactMap(\.duration)
        guard !durations.isEmpty else { return nil }
        return durations.reduce(0, +) / Double(durations.count)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                sectionTitle("History")
                Text("Use history to inspect retained runtime posture, recent failures, and execution drift even when the live graph has already cooled down.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 14)], spacing: 14) {
                    opsMetricCard(title: "Goal Cards", value: "\(effectiveGoalCards.count)", detail: "Current health summary cards", color: .blue)
                    opsMetricCard(title: "Trend Series", value: "\(snapshot.historicalSeries.count)", detail: "In-memory historical metric series", color: .green)
                    opsMetricCard(title: "Anomalies", value: "\(effectiveAnomalies.count)", detail: "Merged live and persisted anomaly queue", color: effectiveAnomalies.isEmpty ? .green : .orange)
                    opsMetricCard(title: "Trace Rows", value: "\(effectiveTraces.count)", detail: "Merged live and persisted execution traces", color: .purple)
                    opsMetricCard(title: "Failures", value: "\(projections?.overview?.failedExecutionCount ?? snapshot.failedExecutions)", detail: "Retained failed executions in current scope", color: (projections?.overview?.failedExecutionCount ?? snapshot.failedExecutions) > 0 ? .red : .green)
                    opsMetricCard(title: "Avg Duration", value: averagePersistedTraceDuration.map(opsDurationText) ?? "n/a", detail: "Average runtime duration across retained traces", color: .teal)
                }

                if let projectionSummaryText {
                    Text(projectionSummaryText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if effectiveGoalCards.isEmpty {
                    opsEmptyState(
                        title: "No history snapshot available yet",
                        detail: "Trend cards, anomalies, and retained traces will populate after runtime and analytics projections are written."
                    )
                } else {
                    sectionTitle("Runtime Snapshot")
                    VStack(spacing: 8) {
                        ForEach(effectiveGoalCards) { card in
                            HStack(alignment: .top, spacing: 12) {
                                opsStatusPill(title: card.title, color: historyColor(for: card.status))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(card.valueText)
                                        .font(.subheadline.weight(.semibold))
                                    Text(card.detailText)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                            .padding(10)
                            .background(Color(.controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                }

                sectionTitle("Trend Signals")
                if snapshot.historicalSeries.isEmpty {
                    if snapshot.dailyActivity.isEmpty {
                        opsInlineEmptyState("No retained trend series are available yet.")
                    } else {
                        VStack(spacing: 8) {
                            ForEach(snapshot.dailyActivity.suffix(7)) { point in
                                HStack(spacing: 12) {
                                    Text(point.date.formatted(date: .abbreviated, time: .omitted))
                                        .font(.caption.weight(.medium))
                                        .frame(width: 96, alignment: .leading)

                                    GeometryReader { geometry in
                                        let total = max(point.completedCount + point.failedCount + point.errorCount, 1)
                                        let completedWidth = geometry.size.width * CGFloat(point.completedCount) / CGFloat(total)
                                        let failedWidth = geometry.size.width * CGFloat(point.failedCount) / CGFloat(total)
                                        let errorWidth = geometry.size.width * CGFloat(point.errorCount) / CGFloat(total)

                                        HStack(spacing: 2) {
                                            Rectangle().fill(Color.green.opacity(0.8)).frame(width: completedWidth)
                                            Rectangle().fill(Color.orange.opacity(0.8)).frame(width: failedWidth)
                                            Rectangle().fill(Color.red.opacity(0.8)).frame(width: errorWidth)
                                        }
                                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                    }
                                    .frame(height: 12)

                                    Text("C \(point.completedCount) / F \(point.failedCount) / E \(point.errorCount)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .frame(width: 120, alignment: .trailing)
                                }
                                .padding(10)
                                .background(Color(.controlBackgroundColor))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                        }
                    }
                } else {
                    VStack(spacing: 8) {
                        ForEach(snapshot.historicalSeries.prefix(4)) { series in
                            let latest = series.latestPoint?.value
                            let previous = series.previousPoint?.value
                            let deltaText: String = {
                                guard let latest, let previous else { return "No prior point" }
                                let delta = latest - previous
                                return delta == 0 ? "Stable" : String(format: "%@%.0f", delta > 0 ? "+" : "", delta)
                            }()

                            HStack(alignment: .center, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(series.metric.title)
                                        .font(.subheadline.weight(.medium))
                                    Text(series.metric.windowDescription)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 4) {
                                    Text(latest.map(series.metric.formattedValue) ?? "n/a")
                                        .font(.subheadline.weight(.semibold))
                                    Text(deltaText)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(10)
                            .background(Color(.controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                }

                sectionTitle("Recent Anomalies")
                if effectiveAnomalies.isEmpty {
                    opsInlineEmptyState("No retained anomalies available in the current scope.")
                } else {
                    VStack(spacing: 8) {
                        ForEach(effectiveAnomalies.prefix(8)) { anomaly in
                            HStack(alignment: .top, spacing: 12) {
                                opsStatusPill(title: anomaly.sourceLabel, color: historyColor(for: anomaly.status))
                                    .frame(width: 84, alignment: .leading)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(anomaly.title)
                                        .font(.subheadline.weight(.medium))
                                    Text(anomaly.detailText)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(3)
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 6) {
                                    historyActionButtons(sessionID: anomaly.sessionID, nodeID: anomaly.nodeID)
                                    Text(anomaly.timestamp.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(10)
                            .background(Color(.controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                }

                sectionTitle("Recent Traces")
                if effectiveTraces.isEmpty {
                    opsInlineEmptyState("No retained traces available in the current scope.")
                } else {
                    VStack(spacing: 8) {
                        ForEach(effectiveTraces.prefix(10)) { trace in
                            HStack(alignment: .top, spacing: 12) {
                                opsStatusPill(title: trace.statusText, color: historyStatusColor(trace.statusText))
                                    .frame(width: 92, alignment: .leading)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(trace.title)
                                        .font(.subheadline.weight(.medium))
                                    Text("\(trace.agentName) • \(trace.outputTypeText) • \(trace.sourceLabel)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(trace.previewText)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(3)
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 6) {
                                    historyActionButtons(sessionID: trace.sessionID, nodeID: trace.nodeID)
                                    if let duration = trace.duration {
                                        Text(opsDurationText(duration))
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    if trace.protocolRepairCount > 0 {
                                        Text("Repair \(trace.protocolRepairCount)")
                                            .font(.caption2)
                                            .foregroundColor(.orange)
                                    }
                                    Text(trace.timestamp.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(10)
                            .background(Color(.controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                }
            }
            .padding()
        }
    }

    private func historyColor(for status: OpsHealthStatus) -> Color {
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

    private func historyStatusColor(_ rawValue: String) -> Color {
        switch rawValue.lowercased() {
        case "completed":
            return .green
        case "failed":
            return .red
        case "running":
            return .orange
        case "waiting":
            return .yellow
        default:
            return .secondary
        }
    }

    @ViewBuilder
    private func historyActionButtons(sessionID: String?, nodeID: UUID?) -> some View {
        let normalizedSessionID = normalizedHistorySessionID(sessionID)

        if normalizedSessionID != nil || nodeID != nil {
            HStack(spacing: 6) {
                if let normalizedSessionID {
                    historyActionButton(title: "Session") {
                        onSelectSession(normalizedSessionID)
                    }
                }

                if let nodeID {
                    historyActionButton(title: "Node") {
                        onSelectNode(nodeID)
                    }
                }
            }
        }
    }

    private func historyActionButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundColor(.blue)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.blue.opacity(0.10))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func normalizedHistorySessionID(_ sessionID: String?) -> String? {
        let trimmed = sessionID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct OpsCenterInvestigationPanel: View {
    let target: OpsCenterInvestigationTarget

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(target.title)
                        .font(.title2.weight(.semibold))
                    Text(target.subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                switch target {
                case let .session(investigation):
                    sessionInvestigationBody(investigation)
                case let .node(investigation):
                    nodeInvestigationBody(investigation)
                case let .route(investigation):
                    routeInvestigationBody(investigation)
                }
            }
            .padding(20)
        }
        .frame(minWidth: 920, minHeight: 760)
        .background(Color(.windowBackgroundColor))
    }

    @ViewBuilder
    private func sessionInvestigationBody(_ investigation: OpsCenterSessionInvestigation) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
            opsMetricCard(title: "Events", value: "\(investigation.session.eventCount)", detail: "Runtime events in this session", color: .blue)
            opsMetricCard(title: "Dispatches", value: "\(investigation.session.dispatchCount)", detail: "Queue + inflight + terminal", color: .orange)
            opsMetricCard(title: "Receipts", value: "\(investigation.session.receiptCount)", detail: "Execution receipts linked to session", color: .green)
            opsMetricCard(title: "Failures", value: "\(investigation.session.failedDispatchCount)", detail: investigation.session.latestFailureText ?? "No recent failure text", color: investigation.session.failedDispatchCount > 0 ? .red : .green)
            opsMetricCard(title: "Workbench Messages", value: "\(investigation.messages.count)", detail: "Messages currently linked", color: .purple)
            opsMetricCard(title: "Tasks", value: "\(investigation.tasks.count)", detail: "Workbench tasks linked to session", color: .teal)
        }

        opsInvestigationSection("Related Nodes", detail: "Nodes touched by this session's dispatches, receipts, tasks, or runtime events.") {
            if investigation.relatedNodes.isEmpty {
                opsInlineEmptyState("No node relationships resolved yet.")
            } else {
                ForEach(investigation.relatedNodes) { node in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(node.title)
                                .font(.subheadline.weight(.medium))
                            Text(node.agentName ?? "No bound agent")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        opsStatusPill(title: node.status.title, color: node.status.color)
                    }
                    .padding(10)
                    .background(Color(.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }

        opsInvestigationSection("Runtime Events", detail: "Recent runtime events emitted under this session key.") {
            if investigation.events.isEmpty {
                opsInlineEmptyState("No session events captured.")
            } else {
                ForEach(investigation.events.prefix(10)) { event in
                    OpsCenterEventDigestCard(event: event)
                }
            }
        }

        opsInvestigationSection("Dispatches", detail: "Dispatch pressure and terminal outcomes for this session.") {
            if investigation.dispatches.isEmpty {
                opsInlineEmptyState("No dispatch records captured.")
            } else {
                ForEach(investigation.dispatches.prefix(12)) { dispatch in
                    OpsCenterDispatchDigestCard(dispatch: dispatch)
                }
            }
        }

        opsInvestigationSection("Receipts", detail: "Execution receipts observed for this session.") {
            if investigation.receipts.isEmpty {
                opsInlineEmptyState("No execution receipts captured.")
            } else {
                ForEach(investigation.receipts.prefix(10)) { receipt in
                    OpsCenterReceiptDigestCard(receipt: receipt)
                }
            }
        }

        opsInvestigationSection("Workbench Messages", detail: "User and agent conversation linked to this session.") {
            if investigation.messages.isEmpty {
                opsInlineEmptyState("No workbench messages linked.")
            } else {
                ForEach(investigation.messages.prefix(10)) { message in
                    OpsCenterMessageDigestCard(message: message)
                }
            }
        }

        opsInvestigationSection("Workbench Tasks", detail: "Tasks carrying the same session key.") {
            if investigation.tasks.isEmpty {
                opsInlineEmptyState("No tasks linked to this session.")
            } else {
                ForEach(investigation.tasks.prefix(10)) { task in
                    OpsCenterTaskDigestCard(task: task)
                }
            }
        }
    }

    @ViewBuilder
    private func nodeInvestigationBody(_ investigation: OpsCenterNodeInvestigation) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
            opsMetricCard(title: "Node Status", value: investigation.node.status.title, detail: investigation.node.latestDetail ?? "No runtime detail captured", color: investigation.node.status.color)
            opsMetricCard(title: "Sessions", value: "\(investigation.relatedSessions.count)", detail: "Sessions touching this node", color: .blue)
            opsMetricCard(title: "Dispatches", value: "\(investigation.dispatches.count)", detail: "Recent dispatch records resolved", color: .orange)
            opsMetricCard(title: "Receipts", value: "\(investigation.receipts.count)", detail: "Execution receipts for this node", color: .green)
            opsMetricCard(title: "Messages", value: "\(investigation.messages.count)", detail: "Linked workbench messages", color: .purple)
            opsMetricCard(title: "Tasks", value: "\(investigation.tasks.count)", detail: "Tasks mapped by node or agent", color: .teal)
        }

        opsInvestigationSection("Routing Context", detail: "Incoming and outgoing paths around this node.") {
            if investigation.incomingEdges.isEmpty && investigation.outgoingEdges.isEmpty {
                opsInlineEmptyState("No routing edges connected.")
            } else {
                ForEach(investigation.incomingEdges) { edge in
                    HStack {
                        Text("\(edge.fromTitle) -> \(edge.toTitle)")
                            .font(.caption.weight(.medium))
                        Spacer()
                        Text("Flow \(edge.activityCount)")
                            .font(.caption)
                            .foregroundColor(edge.activityCount > 0 ? .blue : .secondary)
                        if edge.requiresApproval {
                            opsStatusPill(title: "Approval", color: .yellow)
                        }
                    }
                    .padding(10)
                    .background(Color(.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                ForEach(investigation.outgoingEdges) { edge in
                    HStack {
                        Text("\(edge.fromTitle) -> \(edge.toTitle)")
                            .font(.caption.weight(.medium))
                        Spacer()
                        Text("Flow \(edge.activityCount)")
                            .font(.caption)
                            .foregroundColor(edge.activityCount > 0 ? .blue : .secondary)
                        if edge.requiresApproval {
                            opsStatusPill(title: "Approval", color: .yellow)
                        }
                    }
                    .padding(10)
                    .background(Color(.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }

        opsInvestigationSection("Related Sessions", detail: "Sessions whose work currently touches this node.") {
            if investigation.relatedSessions.isEmpty {
                opsInlineEmptyState("No related sessions resolved.")
            } else {
                ForEach(investigation.relatedSessions) { session in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(session.sessionID)
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            Text("Events \(session.eventCount) • Dispatches \(session.dispatchCount) • Receipts \(session.receiptCount)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        opsStatusPill(
                            title: session.isPrimaryRuntimeSession ? "Primary" : "Linked",
                            color: session.isPrimaryRuntimeSession ? .teal : .blue
                        )
                    }
                    .padding(10)
                    .background(Color(.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }

        opsInvestigationSection("Runtime Events", detail: "Recent runtime events directly touching this node or its sessions.") {
            if investigation.events.isEmpty {
                opsInlineEmptyState("No node events captured.")
            } else {
                ForEach(investigation.events.prefix(10)) { event in
                    OpsCenterEventDigestCard(event: event)
                }
            }
        }

        opsInvestigationSection("Dispatches", detail: "Dispatch records touching the node or its bound agent.") {
            if investigation.dispatches.isEmpty {
                opsInlineEmptyState("No dispatch records captured.")
            } else {
                ForEach(investigation.dispatches.prefix(12)) { dispatch in
                    OpsCenterDispatchDigestCard(dispatch: dispatch)
                }
            }
        }

        opsInvestigationSection("Receipts", detail: "Execution receipts emitted by this node.") {
            if investigation.receipts.isEmpty {
                opsInlineEmptyState("No execution receipts captured.")
            } else {
                ForEach(investigation.receipts.prefix(10)) { receipt in
                    OpsCenterReceiptDigestCard(receipt: receipt)
                }
            }
        }

        opsInvestigationSection("Workbench Messages", detail: "Messages linked by session or bound agent.") {
            if investigation.messages.isEmpty {
                opsInlineEmptyState("No related workbench messages.")
            } else {
                ForEach(investigation.messages.prefix(10)) { message in
                    OpsCenterMessageDigestCard(message: message)
                }
            }
        }

        opsInvestigationSection("Workbench Tasks", detail: "Tasks linked by workflow node binding or agent assignment.") {
            if investigation.tasks.isEmpty {
                opsInlineEmptyState("No related tasks.")
            } else {
                ForEach(investigation.tasks.prefix(10)) { task in
                    OpsCenterTaskDigestCard(task: task)
                }
            }
        }
    }

    @ViewBuilder
    private func routeInvestigationBody(_ investigation: OpsCenterRouteInvestigation) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
            opsMetricCard(title: "Route Flow", value: "\(investigation.edge.activityCount)", detail: investigation.edge.title, color: .blue)
            opsMetricCard(title: "Sessions", value: "\(investigation.relatedSessions.count)", detail: "Sessions correlated to this route", color: .green)
            opsMetricCard(title: "Dispatches", value: "\(investigation.dispatches.count)", detail: "Direct dispatches across this route", color: .orange)
            opsMetricCard(title: "Receipts", value: "\(investigation.receipts.count)", detail: "Endpoint receipts linked to route sessions", color: .teal)
            opsMetricCard(title: "Messages", value: "\(investigation.messages.count)", detail: "Workbench messages under route sessions", color: .purple)
            opsMetricCard(title: "Tasks", value: "\(investigation.tasks.count)", detail: "Tasks retained under route sessions", color: .indigo)
        }

        opsInvestigationSection("Route Posture", detail: "Upstream, downstream, and gate posture for the selected workflow route.") {
            VStack(alignment: .leading, spacing: 8) {
                routeEndpointCard(
                    title: "Upstream",
                    node: investigation.upstreamNode,
                    fallbackTitle: investigation.edge.fromTitle
                )
                routeEndpointCard(
                    title: "Downstream",
                    node: investigation.downstreamNode,
                    fallbackTitle: investigation.edge.toTitle
                )
                HStack {
                    Text("Label")
                        .font(.caption.weight(.medium))
                    Spacer()
                    Text(investigation.edge.title)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if investigation.edge.requiresApproval {
                        opsStatusPill(title: "Approval", color: .yellow)
                    }
                }
                .padding(10)
                .background(Color(.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }

        opsInvestigationSection("Related Sessions", detail: "Sessions that retained evidence of traffic across this route.") {
            if investigation.relatedSessions.isEmpty {
                opsInlineEmptyState("No route-correlated sessions resolved.")
            } else {
                ForEach(investigation.relatedSessions) { session in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(session.sessionID)
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            Text("Events \(session.eventCount) • Dispatches \(session.dispatchCount) • Receipts \(session.receiptCount)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        opsStatusPill(
                            title: session.failedDispatchCount > 0 ? "Failure Signal" : "Observed",
                            color: session.failedDispatchCount > 0 ? .red : .blue
                        )
                    }
                    .padding(10)
                    .background(Color(.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }

        opsInvestigationSection("Dispatches", detail: "Direct dispatches observed between the route endpoints.") {
            if investigation.dispatches.isEmpty {
                opsInlineEmptyState("No direct route dispatches captured.")
            } else {
                ForEach(investigation.dispatches.prefix(12)) { dispatch in
                    OpsCenterDispatchDigestCard(dispatch: dispatch)
                }
            }
        }

        opsInvestigationSection("Endpoint Receipts", detail: "Execution receipts emitted by the route endpoints inside correlated sessions.") {
            if investigation.receipts.isEmpty {
                opsInlineEmptyState("No endpoint receipts captured.")
            } else {
                ForEach(investigation.receipts.prefix(12)) { receipt in
                    OpsCenterReceiptDigestCard(receipt: receipt)
                }
            }
        }

        opsInvestigationSection("Runtime Events", detail: "Recent runtime events retained under route-correlated sessions.") {
            if investigation.events.isEmpty {
                opsInlineEmptyState("No route events captured.")
            } else {
                ForEach(investigation.events.prefix(10)) { event in
                    OpsCenterEventDigestCard(event: event)
                }
            }
        }

        opsInvestigationSection("Workbench Messages", detail: "Messages linked to sessions moving across this route.") {
            if investigation.messages.isEmpty {
                opsInlineEmptyState("No route-linked workbench messages.")
            } else {
                ForEach(investigation.messages.prefix(10)) { message in
                    OpsCenterMessageDigestCard(message: message)
                }
            }
        }

        opsInvestigationSection("Workbench Tasks", detail: "Tasks retained inside sessions that flowed through this route.") {
            if investigation.tasks.isEmpty {
                opsInlineEmptyState("No route-linked tasks.")
            } else {
                ForEach(investigation.tasks.prefix(10)) { task in
                    OpsCenterTaskDigestCard(task: task)
                }
            }
        }
    }
}

private func routeEndpointCard(
    title: String,
    node: OpsCenterNodeSummary?,
    fallbackTitle: String
) -> some View {
    HStack {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(node?.title ?? fallbackTitle)
                .font(.subheadline.weight(.medium))
            Text(node?.agentName ?? "No bound agent")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        Spacer()
        if let node {
            opsStatusPill(title: node.status.title, color: node.status.color)
        }
    }
    .padding(10)
    .background(Color(.controlBackgroundColor))
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
}

private struct OpsCenterDispatchDigestCard: View {
    let dispatch: OpsCenterDispatchDigest

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(dispatch.sourceName) -> \(dispatch.targetName)")
                    .font(.caption.weight(.medium))
                Spacer()
                opsStatusPill(title: opsDispatchStatusTitle(dispatch.status), color: opsDispatchStatusColor(dispatch.status))
            }

            Text(dispatch.summary)
                .font(.caption)
                .foregroundColor(.secondary)

            if let errorText = dispatch.errorText, !errorText.isEmpty {
                Text(errorText)
                    .font(.caption)
                    .foregroundColor(.red)
                    .lineLimit(2)
            }

            HStack {
                if let sessionID = dispatch.sessionID {
                    Text(sessionID)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                }
                Spacer()
                Text(dispatch.updatedAt.formatted(date: .abbreviated, time: .shortened))
            }
            .font(.caption2)
            .foregroundColor(.secondary)
        }
        .padding(10)
        .background(Color(.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct OpsCenterReceiptDigestCard: View {
    let receipt: OpsCenterReceiptDigest

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(receipt.nodeTitle)
                        .font(.caption.weight(.medium))
                    Text(receipt.agentName ?? "Unknown agent")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
                opsStatusPill(title: receipt.status.rawValue, color: opsExecutionStatusColor(receipt.status))
            }

            Text(receipt.summary)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(3)

            HStack {
                Text(receipt.outputType.rawValue)
                Spacer()
                if let duration = receipt.duration {
                    Text(opsDurationText(duration))
                }
                Text(receipt.timestamp.formatted(date: .abbreviated, time: .shortened))
            }
            .font(.caption2)
            .foregroundColor(.secondary)
        }
        .padding(10)
        .background(Color(.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct OpsCenterEventDigestCard: View {
    let event: OpsCenterEventDigest

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(event.eventType.rawValue)
                    .font(.caption.weight(.medium))
                Spacer()
                Text(event.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Text(event.participants)
                .font(.caption2)
                .foregroundColor(.secondary)

            Text(event.summary)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(3)

            if let sessionID = event.sessionID {
                Text(sessionID)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
        .padding(10)
        .background(Color(.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct OpsCenterMessageDigestCard: View {
    let message: OpsCenterMessageDigest

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(message.routeTitle)
                    .font(.caption.weight(.medium))
                Spacer()
                opsStatusPill(title: message.status.rawValue, color: message.status.color)
            }

            Text(message.summary)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(3)

            Text(message.timestamp.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(10)
        .background(Color(.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct OpsCenterTaskDigestCard: View {
    let task: OpsCenterTaskDigest

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(task.title)
                    .font(.caption.weight(.medium))
                Spacer()
                opsStatusPill(title: task.status.rawValue, color: task.status.color)
                opsStatusPill(title: task.priority.rawValue, color: task.priority.color)
            }

            Text(task.summary)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(3)

            Text(task.timestamp.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(10)
        .background(Color(.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private enum OpsCenterMapLayer: String, CaseIterable, Identifiable {
    case state
    case latency
    case failures
    case routing
    case approvals
    case files

    var id: String { rawValue }

    var title: String {
        switch self {
        case .state:
            return "State"
        case .latency:
            return "Latency"
        case .failures:
            return "Failures"
        case .routing:
            return "Routing"
        case .approvals:
            return "Approvals"
        case .files:
            return "Files"
        }
    }

    var detail: String {
        switch self {
        case .state:
            return "Shows the latest runtime state projected onto each node."
        case .latency:
            return "Shows where runtime duration is concentrating."
        case .failures:
            return "Highlights where execution pressure is failing."
        case .routing:
            return "Shows structural flow concentration across the workflow."
        case .approvals:
            return "Surfaces approval-gated nodes and edges."
        case .files:
            return "Reserved for managed file-scope overlays from workflow-derived data."
        }
    }
}

private func sectionTitle(_ value: String) -> some View {
    Text(value)
        .font(.headline)
}

private func opsMetricCard(title: String, value: String, detail: String, color: Color) -> some View {
    VStack(alignment: .leading, spacing: 8) {
        Text(title)
            .font(.caption)
            .foregroundColor(.secondary)
        Text(value)
            .font(.title3.weight(.semibold))
            .foregroundColor(.primary)
        Text(detail)
            .font(.caption)
            .foregroundColor(.secondary)
            .lineLimit(3)
        RoundedRectangle(cornerRadius: 999, style: .continuous)
            .fill(color.opacity(0.22))
            .frame(height: 6)
    }
    .padding()
    .background(Color(.controlBackgroundColor))
    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
}

private func opsStatusPill(title: String, color: Color) -> some View {
    Text(title)
        .font(.caption2.weight(.semibold))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.16))
        .foregroundColor(color)
        .clipShape(Capsule())
}

private func opsEmptyState(title: String, detail: String) -> some View {
    ContentUnavailableView(
        title,
        systemImage: "tray",
        description: Text(detail)
    )
    .frame(maxWidth: .infinity, minHeight: 220)
    .background(Color(.controlBackgroundColor))
    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
}

private func opsInvestigationSection<Content: View>(
    _ title: String,
    detail: String? = nil,
    @ViewBuilder content: () -> Content
) -> some View {
    VStack(alignment: .leading, spacing: 10) {
        Text(title)
            .font(.headline)
        if let detail, !detail.isEmpty {
            Text(detail)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        VStack(spacing: 8) {
            content()
        }
    }
}

private func opsInlineEmptyState(_ detail: String) -> some View {
    Text(detail)
        .font(.caption)
        .foregroundColor(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
}

private func opsDispatchStatusTitle(_ status: RuntimeDispatchStatus) -> String {
    switch status {
    case .created:
        return "Created"
    case .dispatched:
        return "Dispatched"
    case .accepted:
        return "Accepted"
    case .running:
        return "Running"
    case .waitingApproval:
        return "Approval"
    case .waitingDependency:
        return "Waiting"
    case .completed:
        return "Completed"
    case .failed:
        return "Failed"
    case .aborted:
        return "Aborted"
    case .expired:
        return "Expired"
    case .partial:
        return "Partial"
    }
}

private func opsDispatchStatusColor(_ status: RuntimeDispatchStatus) -> Color {
    switch status {
    case .created, .dispatched, .accepted, .waitingDependency:
        return .blue
    case .running, .partial:
        return .orange
    case .waitingApproval:
        return .yellow
    case .completed:
        return .green
    case .failed, .aborted, .expired:
        return .red
    }
}

private func opsExecutionStatusColor(_ status: ExecutionStatus) -> Color {
    switch status {
    case .idle:
        return .secondary
    case .running:
        return .orange
    case .completed:
        return .green
    case .failed:
        return .red
    case .waiting:
        return .blue
    }
}

private func opsDurationText(_ duration: TimeInterval) -> String {
    if duration >= 60 {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return "\(minutes)m \(seconds)s"
    }
    return String(format: "%.1fs", duration)
}
