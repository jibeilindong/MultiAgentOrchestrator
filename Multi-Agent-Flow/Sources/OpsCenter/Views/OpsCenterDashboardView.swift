import SwiftUI
import Combine

struct OpsCenterDashboardView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var localizationManager = LocalizationManager.shared

    let displayMode: OpsCenterDisplayMode
    let preferredWorkflowID: UUID?

    private let projectionRefreshTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    @State private var selectedPage: OpsCenterConsolePage = .threads
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
                    LocalizedString.text("ops_center_empty_title"),
                    systemImage: "gauge.with.dots.needle.33percent",
                    description: Text(LocalizedString.text("ops_center_empty_description"))
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
            OpsCenterInvestigationPanel(
                target: target,
                onSelectSession: openSessionInvestigation,
                onSelectNode: openNodeInvestigation,
                onSelectRoute: openRouteInvestigation,
                onSelectThread: openThreadInvestigation
            )
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
        .environment(\.locale, Locale(identifier: localizationManager.currentLanguage.rawValue))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(LocalizedString.text("ops_center"))
                        .font(displayMode == .embedded ? .title3.weight(.semibold) : .title2.weight(.semibold))
                    Text(selectedPage.subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if !workflows.isEmpty {
                    Picker(LocalizedString.text("workflow_label"), selection: workflowSelectionBinding) {
                        ForEach(workflows) { workflow in
                            Text(workflow.name).tag(workflow.id as UUID?)
                        }
                    }
                    .frame(width: displayMode == .embedded ? 220 : 260)
                }

                opsStatusPill(
                    title: appState.openClawManager.isConnected
                        ? LocalizedString.text("openclaw_connected")
                        : LocalizedString.text("openclaw_disconnected"),
                    color: appState.openClawManager.isConnected ? .green : .red
                )

                if let freshestProjectionAt = projections?.freshestGeneratedAt {
                    opsStatusPill(
                        title: LocalizedString.format(
                            "ops_projection_updated_at",
                            freshestProjectionAt.formatted(date: .omitted, time: .shortened)
                        ),
                        color: .blue
                    )
                }
            }

            Picker(LocalizedString.text("ops_center_page"), selection: $selectedPage) {
                ForEach(OpsCenterConsolePage.allCases) { page in
                    Text(page.title).tag(page)
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
        case .threads:
            OpsCenterThreadsDashboardView(
                workflow: selectedWorkflow,
                projections: projections,
                onSelectThread: openThreadInvestigation,
                onSelectSession: openSessionInvestigation
            )
        case .signals:
            OpsCenterSignalsDashboardView(
                workflow: selectedWorkflow,
                projections: projections,
                onSelectCron: openCronInvestigation,
                onSelectTool: openToolInvestigation,
                onSelectArchiveProjection: openArchiveProjectionInvestigation,
                onSelectSession: openSessionInvestigation,
                onSelectThread: openThreadInvestigation,
                onSelectNode: openNodeInvestigation
            )
        case .liveRun:
            OpsCenterLiveRunDashboardView(
                workflow: selectedWorkflow,
                projections: projections,
                onSelectSession: openSessionInvestigation,
                onSelectNode: openNodeInvestigation,
                onSelectThread: openThreadInvestigation
            )
        case .sessions:
            OpsCenterSessionsDashboardView(
                workflow: selectedWorkflow,
                projections: projections,
                onSelectSession: openSessionInvestigation,
                onSelectThread: openThreadInvestigation
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
                onSelectNode: openNodeInvestigation,
                onSelectThread: openThreadInvestigation,
                onSelectCron: openCronInvestigation,
                onSelectTool: openToolInvestigation,
                onSelectArchiveProjection: openArchiveProjectionInvestigation
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
                    workflowName: selectedWorkflow?.name ?? LocalizedString.text("workflow_label"),
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

    private func openThreadInvestigation(_ threadID: String) {
        let liveInvestigation = OpsCenterSnapshotBuilder.buildThreadInvestigation(
            project: appState.currentProject,
            workflow: selectedWorkflow,
            threadID: threadID,
            tasks: appState.taskManager.tasks,
            messages: appState.messageManager.messages,
            executionResults: appState.openClawService.executionResults
        )

        let archiveInvestigation: OpsCenterThreadInvestigation?
        if let projectID = appState.currentProject?.id {
            archiveInvestigation = OpsCenterArchiveStore.loadThreadInvestigation(
                projectID: projectID,
                workflowID: selectedWorkflow?.id,
                threadID: threadID,
                projections: projections
            )
        } else {
            archiveInvestigation = nil
        }

        if let investigation = mergedThreadInvestigation(
            live: liveInvestigation,
            archive: archiveInvestigation
        ) {
            selectedInvestigation = .thread(investigation)
        }
    }

    private func openCronInvestigation(_ cronName: String) {
        guard let projectID = appState.currentProject?.id else { return }

        if let detail = appState.opsAnalytics.cronDetail(
            projectID: projectID,
            cronName: cronName,
            days: 14,
            runLimit: 24,
            anomalyLimit: 12
        ) {
            selectedInvestigation = .cron(
                OpsCenterCronInvestigation(
                    cronName: detail.cronName,
                    summary: detail.summary,
                    historySeries: detail.historySeries,
                    runs: detail.runs,
                    anomalies: detail.anomalies
                )
            )
            return
        }

        if let projectionInvestigation = projections?.cronInvestigation(for: cronName) {
            selectedInvestigation = .cron(projectionInvestigation)
            return
        }

        let snapshot = appState.opsAnalytics.snapshot
        let fallbackRuns = snapshot.cronRuns.filter { $0.cronName == cronName }
        let fallbackAnomalies = snapshot.anomalyRows.filter {
            $0.sourceLabel == "Cron" && ($0.title == cronName || $0.relatedSourcePath == cronName)
        }
        guard !fallbackRuns.isEmpty || !fallbackAnomalies.isEmpty else { return }

        selectedInvestigation = .cron(
            OpsCenterCronInvestigation(
                cronName: cronName,
                summary: snapshot.cronSummary,
                historySeries: [],
                runs: fallbackRuns,
                anomalies: fallbackAnomalies
            )
        )
    }

    private func openToolInvestigation(_ toolIdentifier: String) {
        guard let projectID = appState.currentProject?.id else { return }

        if let detail = appState.opsAnalytics.toolDetail(
            projectID: projectID,
            toolIdentifier: toolIdentifier,
            days: 14,
            spanLimit: 24,
            anomalyLimit: 12
        ) {
            selectedInvestigation = .tool(
                OpsCenterToolInvestigation(
                    toolIdentifier: detail.toolIdentifier,
                    historySeries: detail.historySeries,
                    spans: detail.spans,
                    anomalies: detail.anomalies
                )
            )
            return
        }

        if let projectionInvestigation = projections?.toolInvestigation(for: toolIdentifier) {
            selectedInvestigation = .tool(projectionInvestigation)
            return
        }

        let fallbackAnomalies = appState.opsAnalytics.snapshot.anomalyRows.filter {
            normalizedToolIdentifier($0.sourceService) == normalizedToolIdentifier(toolIdentifier)
        }
        guard !fallbackAnomalies.isEmpty else { return }

        selectedInvestigation = .tool(
            OpsCenterToolInvestigation(
                toolIdentifier: toolIdentifier,
                historySeries: [],
                spans: [],
                anomalies: fallbackAnomalies
            )
        )
    }

    private func openArchiveProjectionInvestigation() {
        guard let investigation = OpsCenterSnapshotBuilder.buildArchiveProjectionInvestigation(
            project: appState.currentProject,
            workflow: selectedWorkflow,
            projections: projections
        ) else {
            return
        }

        selectedInvestigation = .archiveProjection(investigation)
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

    private func normalizedToolIdentifier(_ rawValue: String?) -> String? {
        let trimmed = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed.lowercased()
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

    private func mergedThreadInvestigation(
        live: OpsCenterThreadInvestigation?,
        archive: OpsCenterThreadInvestigation?
    ) -> OpsCenterThreadInvestigation? {
        switch (live, archive) {
        case let (live?, archive?):
            return OpsCenterThreadInvestigation(
                threadID: preferredText(live.threadID, archive.threadID) ?? live.threadID,
                sessionID: preferredText(live.sessionID, archive.sessionID) ?? live.sessionID,
                workflowID: live.workflowID ?? archive.workflowID,
                workflowName: preferredText(live.workflowName, archive.workflowName) ?? live.workflowName,
                status: preferredText(live.status, archive.status) ?? live.status,
                startedAt: [live.startedAt, archive.startedAt].compactMap { $0 }.min(),
                lastUpdatedAt: [live.lastUpdatedAt, archive.lastUpdatedAt].compactMap { $0 }.max(),
                entryAgentName: preferredText(live.entryAgentName, archive.entryAgentName),
                participantNames: Array(Set(live.participantNames + archive.participantNames)).sorted(),
                pendingApprovalCount: max(live.pendingApprovalCount, archive.pendingApprovalCount),
                relatedSession: mergedOptionalSessionSummary(live.relatedSession, archive.relatedSession),
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

    private func mergedOptionalSessionSummary(
        _ lhs: OpsCenterSessionSummary?,
        _ rhs: OpsCenterSessionSummary?
    ) -> OpsCenterSessionSummary? {
        switch (lhs, rhs) {
        case let (lhs?, rhs?):
            return mergedSessionSummary(lhs, rhs)
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

private struct OpsCenterSignalsDashboardView: View {
    @EnvironmentObject var appState: AppState
    let workflow: Workflow?
    let projections: OpsCenterProjectionBundle?
    let onSelectCron: (String) -> Void
    let onSelectTool: (String) -> Void
    let onSelectArchiveProjection: () -> Void
    let onSelectSession: (String) -> Void
    let onSelectThread: (String) -> Void
    let onSelectNode: (UUID) -> Void

    @State private var searchText = ""
    @State private var selectedFilter: OpsCenterSignalListFilter = .all
    @State private var selectedSort: OpsCenterSignalSort = .priority

    private var snapshot: OpsAnalyticsSnapshot {
        appState.opsAnalytics.snapshot
    }

    private var executionResultsByID: [UUID: ExecutionResult] {
        Dictionary(uniqueKeysWithValues: appState.openClawService.executionResults.map { ($0.id, $0) })
    }

    private var sessionSummaries: [OpsCenterSessionSummary] {
        OpsCenterSnapshotBuilder.buildSessionSummaries(
            project: appState.currentProject,
            workflow: workflow,
            tasks: appState.taskManager.tasks,
            messages: appState.messageManager.messages,
            executionResults: appState.openClawService.executionResults
        )
    }

    private var effectiveSessions: [OpsCenterSessionSummary] {
        sessionSummaries.isEmpty ? (projections?.sessionSummaries(for: workflow?.id) ?? []) : sessionSummaries
    }

    private var threadSummaries: [OpsCenterThreadSummary] {
        opsBuildThreadSummaries(
            project: appState.currentProject,
            workflow: workflow,
            messages: appState.messageManager.messages,
            tasks: appState.taskManager.tasks,
            sessionSummaries: effectiveSessions,
            projections: projections
        )
    }

    private var leadThreadBySessionID: [String: OpsCenterThreadSummary] {
        Dictionary(
            grouping: threadSummaries.compactMap { thread -> (String, OpsCenterThreadSummary)? in
                guard let sessionID = opsNormalizedSessionID(thread.relatedSession?.sessionID) else { return nil }
                return (sessionID, thread)
            },
            by: { $0.0 }
        )
        .compactMapValues { items in
            items.map(\.1).max(by: { lhs, rhs in
                if lhs.hotspotScore != rhs.hotspotScore {
                    return lhs.hotspotScore < rhs.hotspotScore
                }
                return (lhs.lastUpdatedAt ?? .distantPast) < (rhs.lastUpdatedAt ?? .distantPast)
            })
        }
    }

    private var effectiveCronSummary: OpsCronReliabilitySummary? {
        snapshot.cronSummary ?? projections?.cronSummary
    }

    private var recentCronRuns: [OpsCronRunRow] {
        let liveRuns = snapshot.cronRuns
        let projectedRuns = projections?.recentCronRuns() ?? []

        return Array(
            (liveRuns + projectedRuns).reduce(into: [String: OpsCronRunRow]()) { partial, item in
                let key = item.id
                guard let existing = partial[key] else {
                    partial[key] = item
                    return
                }
                if item.runAt > existing.runAt {
                    partial[key] = item
                }
            }
            .values
        )
        .sorted { lhs, rhs in
            if lhs.runAt != rhs.runAt {
                return lhs.runAt > rhs.runAt
            }
            return lhs.id > rhs.id
        }
    }

    private var toolHotspots: [OpsCenterToolHotspotDigest] {
        let anomalyPairs: [(String, OpsAnomalyRow)] = snapshot.anomalyRows.compactMap { anomaly in
            guard let identifier = opsToolIdentifier(from: anomaly) else { return nil }
            return (identifier, anomaly)
        }
        let groupedLiveHotspots = Dictionary(grouping: anomalyPairs, by: { $0.0 })
        let liveHotspots: [OpsCenterToolHotspotDigest] = groupedLiveHotspots.compactMap { identifier, items in
            let anomalies = items.map { $0.1 }
            guard let latestAnomaly = anomalies.max(by: { $0.occurredAt < $1.occurredAt }) else {
                return nil
            }
            let timeoutCount = anomalies.filter {
                $0.statusText.lowercased().contains("timeout")
                    || $0.detailText.lowercased().contains("timeout")
            }.count
            return OpsCenterToolHotspotDigest(
                toolIdentifier: identifier,
                failureCount: anomalies.count,
                timeoutCount: timeoutCount,
                latestAt: latestAnomaly.occurredAt,
                latestDetailText: latestAnomaly.detailText,
                status: anomalies.contains(where: { $0.status == .critical }) ? .critical : .warning
            )
        }

        let projectedHotspots: [OpsCenterToolHotspotDigest] = projections?.toolEntries().compactMap { entry in
            let anomalies = entry.anomalies.map { $0.anomalyRow() }
            let spans = entry.spans.map { $0.spanRow() }
            let latestAt = (anomalies.map(\.occurredAt) + spans.map(\.startedAt)).max()
            let latestDetailText = anomalies.first?.detailText ?? spans.first?.summaryText
            let timeoutCount = anomalies.filter {
                $0.statusText.lowercased().contains("timeout")
                    || $0.detailText.lowercased().contains("timeout")
            }.count
            let failureCount = max(anomalies.count, spans.filter { $0.statusText.lowercased() != "ok" }.count)
            guard let latestAt, failureCount > 0 || timeoutCount > 0 else { return nil }

            return OpsCenterToolHotspotDigest(
                toolIdentifier: entry.toolIdentifier,
                failureCount: failureCount,
                timeoutCount: timeoutCount,
                latestAt: latestAt,
                latestDetailText: latestDetailText ?? "Persisted tool posture is available.",
                status: anomalies.contains(where: { $0.status == .critical }) ? .critical : .warning
            )
        } ?? []

        let mergedByIdentifier = (liveHotspots + projectedHotspots).reduce(into: [String: OpsCenterToolHotspotDigest]()) { partial, item in
            let key = item.toolIdentifier.lowercased()
            guard let existing = partial[key] else {
                partial[key] = item
                return
            }

            if item.failureCount > existing.failureCount
                || (item.failureCount == existing.failureCount && item.latestAt > existing.latestAt) {
                partial[key] = item
            }
        }

        return Array(mergedByIdentifier.values).sorted { lhs, rhs in
            if lhs.failureCount != rhs.failureCount {
                return lhs.failureCount > rhs.failureCount
            }
            if lhs.latestAt != rhs.latestAt {
                return lhs.latestAt > rhs.latestAt
            }
            return lhs.toolIdentifier < rhs.toolIdentifier
        }
    }

    private var archiveProjectionInvestigation: OpsCenterArchiveProjectionInvestigation? {
        OpsCenterSnapshotBuilder.buildArchiveProjectionInvestigation(
            project: appState.currentProject,
            workflow: workflow,
            projections: projections
        )
    }

    private var loadedProjectionDigests: [OpsCenterArchiveProjectionDocumentDigest] {
        guard let archiveProjectionInvestigation else { return [] }
        return archiveProjectionInvestigation.documentDigests
            .filter { $0.generatedAt != nil }
            .sorted { lhs, rhs in
                let lhsRank = opsHealthStatusRank(lhs.status)
                let rhsRank = opsHealthStatusRank(rhs.status)
                if lhsRank != rhsRank {
                    return lhsRank < rhsRank
                }
                return (lhs.generatedAt ?? .distantPast) > (rhs.generatedAt ?? .distantPast)
            }
    }

    private var observedCronCount: Int {
        max(Set(recentCronRuns.map(\.cronName)).count, projections?.cronEntries().count ?? 0)
    }

    private var observedToolCount: Int {
        max(toolHotspots.count, projections?.toolEntries().count ?? 0)
    }

    private var projectionSummaryText: String? {
        guard let freshestProjectionAt = projections?.freshestGeneratedAt else { return nil }
        return LocalizedString.format(
            "history_projection_refreshed_at",
            freshestProjectionAt.formatted(date: .abbreviated, time: .shortened)
        )
    }

    private var cronFrontline: [OpsCenterSignalFrontlineDigest] {
        let grouped = Dictionary(grouping: recentCronRuns, by: \.cronName)

        return grouped.compactMap { cronName, runs -> OpsCenterSignalFrontlineDigest? in
            guard let latestRun = runs.max(by: { $0.runAt < $1.runAt }) else { return nil }
            let failureCount = runs.filter { opsCronRunIsFailure($0) }.count
            let status: OpsHealthStatus = failureCount > 0 ? .warning : .healthy
            let priorityScore = (failureCount * 6) + runs.count
            let linkedSessionID = opsLeadLinkedSessionID(
                spanIDs: runs.compactMap(\.linkedSessionSpanID),
                executionResultsByID: executionResultsByID
            )
            let linkedThreadID = linkedSessionID.flatMap { leadThreadBySessionID[$0]?.threadID }
            let linkedNodeID = opsLeadLinkedNodeID(
                spanIDs: runs.compactMap(\.linkedSessionSpanID),
                executionResultsByID: executionResultsByID
            )

            return OpsCenterSignalFrontlineDigest(
                id: "cron-\(cronName)",
                kind: .cron,
                title: cronName,
                subtitleText: LocalizedString.text("cron_category"),
                detailText: latestRun.summaryText,
                metricText: LocalizedString.format("cron_runs_failures_summary", runs.count, failureCount),
                timestamp: latestRun.runAt,
                status: status,
                priorityScore: priorityScore,
                actionTitle: LocalizedString.text("open_cron"),
                action: { onSelectCron(cronName) },
                linkedSessionID: linkedSessionID,
                linkedThreadID: linkedThreadID,
                linkedNodeID: linkedNodeID
            )
        }
    }

    private var toolFrontline: [OpsCenterSignalFrontlineDigest] {
        toolHotspots.map { tool -> OpsCenterSignalFrontlineDigest in
            let linkedSessionID = opsLeadLinkedSessionID(
                spanIDs: opsLinkedToolSpanIDs(
                    toolIdentifier: tool.toolIdentifier,
                    snapshot: snapshot,
                    projections: projections
                ),
                executionResultsByID: executionResultsByID
            )
            let linkedThreadID = linkedSessionID.flatMap { leadThreadBySessionID[$0]?.threadID }
            let linkedNodeID = opsLeadLinkedNodeID(
                spanIDs: opsLinkedToolSpanIDs(
                    toolIdentifier: tool.toolIdentifier,
                    snapshot: snapshot,
                    projections: projections
                ),
                executionResultsByID: executionResultsByID
            )

            return OpsCenterSignalFrontlineDigest(
                id: "tool-\(tool.toolIdentifier)",
                kind: .tool,
                title: tool.toolIdentifier,
                subtitleText: LocalizedString.text("tool_category"),
                detailText: tool.latestDetailText,
                metricText: LocalizedString.format("failures_timeouts_summary", tool.failureCount, tool.timeoutCount),
                timestamp: tool.latestAt,
                status: tool.status,
                priorityScore: (tool.failureCount * 6) + (tool.timeoutCount * 3),
                actionTitle: LocalizedString.text("open_tool"),
                action: { onSelectTool(tool.toolIdentifier) },
                linkedSessionID: linkedSessionID,
                linkedThreadID: linkedThreadID,
                linkedNodeID: linkedNodeID
            )
        }
    }

    private var projectionFrontline: [OpsCenterSignalFrontlineDigest] {
        loadedProjectionDigests.map { document -> OpsCenterSignalFrontlineDigest in
            return OpsCenterSignalFrontlineDigest(
                id: "projection-\(document.id)",
                kind: .projection,
                title: document.title,
                subtitleText: LocalizedString.text("ops_projections"),
                detailText: document.detailText,
                metricText: document.valueText,
                timestamp: document.generatedAt,
                status: document.status,
                priorityScore: opsProjectionDigestPriorityScore(document),
                actionTitle: LocalizedString.text("open_projection"),
                action: onSelectArchiveProjection,
                linkedSessionID: nil,
                linkedThreadID: nil,
                linkedNodeID: nil
            )
        }
    }

    private var signalFrontline: [OpsCenterSignalFrontlineDigest] {
        (cronFrontline + toolFrontline + projectionFrontline)
            .filter(matchesSignalFilter)
            .filter(matchesSignalSearch)
            .sorted(by: sortSignals)
    }

    private var leadSignal: OpsCenterSignalFrontlineDigest? {
        signalFrontline.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                sectionTitle(LocalizedString.text("signals_frontline_title"))
                Text(LocalizedString.text("signals_frontline_desc"))
                    .font(.caption)
                    .foregroundColor(.secondary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 14)], spacing: 14) {
                    opsMetricCard(title: LocalizedString.text("signals_observed_crons"), value: "\(observedCronCount)", detail: effectiveCronSummary.map { LocalizedString.format("signals_retained_cron_window_detail", $0.successfulRuns, $0.failedRuns) } ?? LocalizedString.text("signals_no_retained_cron_window"), color: (effectiveCronSummary?.failedRuns ?? 0) > 0 ? .orange : .green)
                    opsMetricCard(title: LocalizedString.text("signals_lead_cron"), value: recentCronRuns.first?.cronName ?? LocalizedString.text("ops_none"), detail: recentCronRuns.first?.summaryText ?? LocalizedString.text("signals_no_recent_cron_execution"), color: recentCronRuns.isEmpty ? .secondary : opsHistoryStatusColor(recentCronRuns.first?.statusText ?? ""))
                    opsMetricCard(title: LocalizedString.text("signals_observed_tools"), value: "\(observedToolCount)", detail: toolHotspots.first.map { LocalizedString.format("signals_tool_recent_anomaly_detail", $0.toolIdentifier, $0.failureCount) } ?? LocalizedString.text("signals_no_recent_tool_anomaly"), color: toolHotspots.isEmpty ? .green : .orange)
                    opsMetricCard(title: LocalizedString.text("signals_lead_tool"), value: toolHotspots.first?.toolIdentifier ?? LocalizedString.text("ops_none"), detail: toolHotspots.first?.latestDetailText ?? LocalizedString.text("signals_no_recent_tool_anomaly"), color: toolHotspots.first.map { opsHistoryHealthColor($0.status) } ?? .secondary)
                    opsMetricCard(title: LocalizedString.text("signals_projection_docs"), value: "\(loadedProjectionDigests.count)", detail: archiveProjectionInvestigation?.freshestGeneratedAt.map { LocalizedString.format("signals_freshest_projection", $0.formatted(date: .abbreviated, time: .shortened)) } ?? LocalizedString.text("signals_no_archive_projection_bundle"), color: loadedProjectionDigests.isEmpty ? .orange : .blue)
                    opsMetricCard(title: LocalizedString.text("signals_projection_scope"), value: archiveProjectionInvestigation?.scopeTitle ?? LocalizedString.text("ops_unavailable"), detail: archiveProjectionInvestigation?.liveRunSummary ?? archiveProjectionInvestigation?.workflowHealthSummary ?? LocalizedString.text("signals_projection_scope_summary_unavailable"), color: archiveProjectionInvestigation == nil ? .secondary : .blue)
                }

                if let projectionSummaryText {
                    Text(projectionSummaryText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center, spacing: 12) {
                        TextField(LocalizedString.text("signals_search_placeholder"), text: $searchText)
                            .textFieldStyle(.roundedBorder)

                        Picker(LocalizedString.text("ops_filter_label"), selection: $selectedFilter) {
                            ForEach(OpsCenterSignalListFilter.allCases) { filter in
                                Text(filter.title).tag(filter)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 320)
                    }

                    HStack(alignment: .center, spacing: 12) {
                        Picker(LocalizedString.text("ops_sort_label"), selection: $selectedSort) {
                            ForEach(OpsCenterSignalSort.allCases) { sort in
                                Text(sort.title).tag(sort)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 180)

                        Spacer()

                        Text(LocalizedString.format("signals_frontline_visible_count", signalFrontline.count))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                sectionTitle(LocalizedString.text("signal_queue_title"))
                if signalFrontline.isEmpty {
                    opsInlineEmptyState(LocalizedString.text("signal_queue_empty"))
                } else {
                    VStack(spacing: 8) {
                        ForEach(Array(signalFrontline.prefix(10))) { item in
                            signalQueueRow(item)
                        }
                    }
                }

                if let leadSignal {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(LocalizedString.text("lead_signal_title"))
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)
                            Text("\(leadSignal.kind.title): \(leadSignal.title)")
                                .font(.subheadline.weight(.semibold))
                            Text(leadSignal.detailText)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 6) {
                            signalActionButton(title: leadSignal.actionTitle, action: leadSignal.action)
                            signalContextButtons(for: leadSignal)
                        }
                    }
                    .padding(10)
                    .background(Color(.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                sectionTitle(LocalizedString.text("cron_frontline_title"))
                if recentCronRuns.isEmpty && effectiveCronSummary == nil {
                    opsInlineEmptyState(LocalizedString.text("cron_frontline_empty"))
                } else {
                    if let cronSummary = effectiveCronSummary {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(LocalizedString.format("cron_success_rate_summary", Int(cronSummary.successRate.rounded())))
                                    .font(.subheadline.weight(.semibold))
                                Text(LocalizedString.format("cron_ok_failed_summary", cronSummary.successfulRuns, cronSummary.failedRuns))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                if let latestRunAt = cronSummary.latestRunAt {
                                    Text(LocalizedString.format("latest_run_at", latestRunAt.formatted(date: .abbreviated, time: .shortened)))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            if let leadCronName = recentCronRuns.first?.cronName {
                                signalActionButton(title: LocalizedString.text("open_cron")) {
                                    onSelectCron(leadCronName)
                                }
                            }
                        }
                        .padding(10)
                        .background(Color(.controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    VStack(spacing: 8) {
                        ForEach(Array(recentCronRuns.prefix(6))) { run in
                            HStack(alignment: .top, spacing: 12) {
                                opsStatusPill(title: run.statusText, color: opsHistoryStatusColor(run.statusText))
                                    .frame(width: 96, alignment: .leading)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(run.cronName)
                                        .font(.subheadline.weight(.medium))
                                    Text(run.summaryText)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                    Text([run.jobID, run.sourcePath].compactMap { $0 }.joined(separator: " • "))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 6) {
                                    signalActionButton(title: LocalizedString.text("open_cron")) {
                                        onSelectCron(run.cronName)
                                    }
                                    if let duration = run.duration {
                                        Text(opsDurationText(duration))
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    Text(run.runAt.formatted(date: .abbreviated, time: .shortened))
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

                sectionTitle(LocalizedString.text("tool_frontline_title"))
                if toolHotspots.isEmpty {
                    opsInlineEmptyState(LocalizedString.text("tool_frontline_empty"))
                } else {
                    VStack(spacing: 8) {
                        ForEach(Array(toolHotspots.prefix(6))) { tool in
                            HStack(alignment: .top, spacing: 12) {
                                opsStatusPill(title: tool.failureCount > 1 ? LocalizedString.text("tool_hotspot_badge") : LocalizedString.text("tool_watch_badge"), color: opsHistoryHealthColor(tool.status))
                                    .frame(width: 96, alignment: .leading)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(tool.toolIdentifier)
                                        .font(.subheadline.weight(.medium))
                                    Text(tool.latestDetailText)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(3)
                                    Text(LocalizedString.format("failures_timeouts_summary", tool.failureCount, tool.timeoutCount))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 6) {
                                    signalActionButton(title: LocalizedString.text("open_tool")) {
                                        onSelectTool(tool.toolIdentifier)
                                    }
                                    Text(tool.latestAt.formatted(date: .abbreviated, time: .shortened))
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

                sectionTitle(LocalizedString.text("projection_frontline_title"))
                if let archiveProjectionInvestigation {
                    VStack(spacing: 8) {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(archiveProjectionInvestigation.scopeTitle)
                                    .font(.subheadline.weight(.semibold))
                                Text(LocalizedString.format("projection_scope_counts", archiveProjectionInvestigation.sessionCount, archiveProjectionInvestigation.nodeCount, archiveProjectionInvestigation.traceCount, archiveProjectionInvestigation.anomalyCount))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(archiveProjectionInvestigation.liveRunSummary ?? archiveProjectionInvestigation.workflowHealthSummary ?? LocalizedString.text("projection_scope_summary_missing"))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(3)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 6) {
                                signalActionButton(title: LocalizedString.text("open_projection")) {
                                    onSelectArchiveProjection()
                                }
                                if let freshestGeneratedAt = archiveProjectionInvestigation.freshestGeneratedAt {
                                    Text(freshestGeneratedAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(10)
                        .background(Color(.controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                        ForEach(loadedProjectionDigests) { document in
                            HStack(alignment: .top, spacing: 12) {
                                opsStatusPill(title: document.title, color: opsHistoryHealthColor(document.status))
                                    .frame(width: 110, alignment: .leading)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(document.valueText)
                                        .font(.subheadline.weight(.medium))
                                    Text(document.detailText)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(3)
                                }

                                Spacer()

                                if let generatedAt = document.generatedAt {
                                    Text(generatedAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(10)
                            .background(Color(.controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                } else {
                    opsInlineEmptyState(LocalizedString.text("projection_bundle_missing"))
                }
            }
            .padding()
        }
    }

    private func signalActionButton(title: String, action: @escaping () -> Void) -> some View {
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

    private func matchesSignalFilter(_ item: OpsCenterSignalFrontlineDigest) -> Bool {
        switch selectedFilter {
        case .all:
            return true
        case .crons:
            return item.kind == .cron
        case .tools:
            return item.kind == .tool
        case .projections:
            return item.kind == .projection
        }
    }

    private func matchesSignalSearch(_ item: OpsCenterSignalFrontlineDigest) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty == false else { return true }

        return [
            item.title,
            item.subtitleText,
            item.detailText,
            item.metricText
        ].contains { value in
            value.localizedCaseInsensitiveContains(query)
        }
    }

    private func sortSignals(lhs: OpsCenterSignalFrontlineDigest, rhs: OpsCenterSignalFrontlineDigest) -> Bool {
        switch selectedSort {
        case .priority:
            if lhs.priorityScore != rhs.priorityScore {
                return lhs.priorityScore > rhs.priorityScore
            }
        case .recent:
            if lhs.timestamp != rhs.timestamp {
                return (lhs.timestamp ?? .distantPast) > (rhs.timestamp ?? .distantPast)
            }
        case .name:
            if lhs.title != rhs.title {
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
        }

        let lhsRank = opsHealthStatusRank(lhs.status)
        let rhsRank = opsHealthStatusRank(rhs.status)
        if lhsRank != rhsRank {
            return lhsRank < rhsRank
        }

        if lhs.timestamp != rhs.timestamp {
            return (lhs.timestamp ?? .distantPast) > (rhs.timestamp ?? .distantPast)
        }

        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }

    private func signalQueueRow(_ item: OpsCenterSignalFrontlineDigest) -> some View {
        HStack(alignment: .top, spacing: 12) {
            opsStatusPill(title: item.kind.title, color: opsHistoryHealthColor(item.status))
                .frame(width: 96, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                Text(item.detailText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                Text("\(item.subtitleText) • \(item.metricText)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                signalActionButton(title: item.actionTitle, action: item.action)
                signalContextButtons(for: item)
                if let timestamp = item.timestamp {
                    Text(timestamp.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(10)
        .background(Color(.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func signalContextButtons(for item: OpsCenterSignalFrontlineDigest) -> some View {
        if item.linkedSessionID != nil || item.linkedThreadID != nil || item.linkedNodeID != nil {
            HStack(spacing: 6) {
                if let sessionID = item.linkedSessionID {
                    signalActionButton(title: LocalizedString.text("ops_session_short")) {
                        onSelectSession(sessionID)
                    }
                }
                if let threadID = item.linkedThreadID {
                    signalActionButton(title: LocalizedString.text("ops_thread_short")) {
                        onSelectThread(threadID)
                    }
                }
                if let nodeID = item.linkedNodeID {
                    signalActionButton(title: LocalizedString.text("ops_node_short")) {
                        onSelectNode(nodeID)
                    }
                }
            }
        }
    }
}

private struct OpsCenterThreadsDashboardView: View {
    @EnvironmentObject var appState: AppState
    let workflow: Workflow?
    let projections: OpsCenterProjectionBundle?
    let onSelectThread: (String) -> Void
    let onSelectSession: (String) -> Void

    @State private var searchText = ""
    @State private var selectedFilter: OpsCenterThreadListFilter = .all
    @State private var selectedFocus: OpsCenterThreadFocus = .all
    @State private var selectedSort: OpsCenterThreadSort = .hotspot

    private var sessionSummaries: [OpsCenterSessionSummary] {
        OpsCenterSnapshotBuilder.buildSessionSummaries(
            project: appState.currentProject,
            workflow: workflow,
            tasks: appState.taskManager.tasks,
            messages: appState.messageManager.messages,
            executionResults: appState.openClawService.executionResults
        )
    }

    private var effectiveSessions: [OpsCenterSessionSummary] {
        sessionSummaries.isEmpty ? (projections?.sessionSummaries(for: workflow?.id) ?? []) : sessionSummaries
    }

    private var threadSummaries: [OpsCenterThreadSummary] {
        opsBuildThreadSummaries(
            project: appState.currentProject,
            workflow: workflow,
            messages: appState.messageManager.messages,
            tasks: appState.taskManager.tasks,
            sessionSummaries: effectiveSessions,
            projections: projections
        )
    }

    private var hotspotThreads: [OpsCenterThreadSummary] {
        threadSummaries.filter(opsThreadIsHotspot)
    }

    private var approvalThreads: [OpsCenterThreadSummary] {
        threadSummaries.filter { $0.pendingApprovalCount > 0 }
    }

    private var blockedThreads: [OpsCenterThreadSummary] {
        threadSummaries.filter { $0.blockedTaskCount > 0 || $0.status == "blocked" }
    }

    private var runtimeLinkedThreads: [OpsCenterThreadSummary] {
        threadSummaries.filter(opsThreadHasRuntimePressure)
    }

    private var leadHotspotThread: OpsCenterThreadSummary? {
        hotspotThreads.first
    }

    private var displayedHotspotThreads: [OpsCenterThreadSummary] {
        displayedThreads.filter(opsThreadIsHotspot)
    }

    private var displayedApprovalThreads: [OpsCenterThreadSummary] {
        displayedThreads.filter { $0.pendingApprovalCount > 0 }
    }

    private var displayedBlockedThreads: [OpsCenterThreadSummary] {
        displayedThreads.filter { $0.blockedTaskCount > 0 || $0.status == "blocked" }
    }

    private var displayedRuntimeThreads: [OpsCenterThreadSummary] {
        displayedThreads.filter(opsThreadHasRuntimePressure)
    }

    private var interventionThreads: [OpsCenterThreadSummary] {
        let merged = displayedHotspotThreads + displayedApprovalThreads + displayedBlockedThreads + displayedRuntimeThreads
        let uniqueThreads = merged.reduce(into: [String: OpsCenterThreadSummary]()) { partial, thread in
            guard let existing = partial[thread.threadID] else {
                partial[thread.threadID] = thread
                return
            }

            if sortThreads(lhs: thread, rhs: existing) {
                partial[thread.threadID] = thread
            }
        }

        return Array(uniqueThreads.values)
            .sorted(by: sortThreads)
    }

    private var leadApprovalThread: OpsCenterThreadSummary? {
        displayedApprovalThreads.first
    }

    private var leadBlockedThread: OpsCenterThreadSummary? {
        displayedBlockedThreads.first
    }

    private var leadRuntimeThread: OpsCenterThreadSummary? {
        displayedRuntimeThreads.first
    }

    private var hotspotLanes: [OpsCenterThreadClusterDigest] {
        opsBuildThreadClusterDigests(displayedThreads)
    }

    private var leadHotspotLane: OpsCenterThreadClusterDigest? {
        hotspotLanes.first
    }

    private var pressureModes: [OpsCenterThreadPressureDigest] {
        opsBuildThreadPressureDigests(displayedThreads)
    }

    private var leadPressureMode: OpsCenterThreadPressureDigest? {
        pressureModes.first
    }

    private var sessionHotspots: [OpsCenterThreadSessionDigest] {
        opsBuildThreadSessionDigests(displayedThreads.filter { $0.relatedSession != nil })
    }

    private var leadSessionHotspot: OpsCenterThreadSessionDigest? {
        sessionHotspots.first
    }

    private var pressureTimeline: [OpsCenterThreadPressureTimelineDigest] {
        opsBuildThreadPressureTimelineDigests(displayedThreads)
    }

    private var leadTimelineSlice: OpsCenterThreadPressureTimelineDigest? {
        pressureTimeline.first
    }

    private var projectionContextText: String? {
        guard threadSummaries.isEmpty == false,
              sessionSummaries.isEmpty,
              let freshestProjectionAt = projections?.freshestGeneratedAt else {
            return nil
        }
        return LocalizedString.format(
            "threads_projection_context",
            freshestProjectionAt.formatted(date: .abbreviated, time: .shortened)
        )
    }

    private var filteredThreads: [OpsCenterThreadSummary] {
        threadSummaries.filter { thread in
            matchesThreadFilter(thread) && matchesThreadSearch(thread)
        }
    }

    private var displayedThreads: [OpsCenterThreadSummary] {
        let focusFiltered: [OpsCenterThreadSummary]
        switch selectedFocus {
        case .all:
            focusFiltered = filteredThreads
        case .hotspots:
            focusFiltered = filteredThreads.filter(opsThreadIsHotspot)
        case .approval:
            focusFiltered = filteredThreads.filter { $0.pendingApprovalCount > 0 }
        case .blocked:
            focusFiltered = filteredThreads.filter { $0.blockedTaskCount > 0 || $0.status == "blocked" }
        case .runtime:
            focusFiltered = filteredThreads.filter(opsThreadHasRuntimePressure)
        }

        return focusFiltered.sorted(by: sortThreads)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if threadSummaries.isEmpty {
                    opsEmptyState(
                        title: LocalizedString.text("threads_empty_title"),
                        detail: LocalizedString.text("threads_empty_desc")
                    )
                } else {
                    sectionTitle(LocalizedString.text("thread_frontline_title"))
                    Text(LocalizedString.text("thread_frontline_desc"))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 14)], spacing: 14) {
                        opsMetricCard(title: LocalizedString.text("visible_threads"), value: "\(threadSummaries.count)", detail: LocalizedString.text("visible_threads_detail"), color: .blue)
                        opsMetricCard(title: LocalizedString.text("hotspot_queue"), value: "\(hotspotThreads.count)", detail: hotspotThreads.first.map(opsThreadHotspotReason) ?? LocalizedString.text("no_thread_intervention_needed"), color: hotspotThreads.isEmpty ? .green : .orange)
                        opsMetricCard(title: LocalizedString.text("approval_pressure_label"), value: "\(approvalThreads.reduce(0) { $0 + $1.pendingApprovalCount })", detail: LocalizedString.format("approval_pressure_threads_detail", approvalThreads.count), color: approvalThreads.isEmpty ? .green : .yellow)
                        opsMetricCard(title: LocalizedString.text("blocked_tasks"), value: "\(blockedThreads.count)", detail: LocalizedString.text("blocked_threads_detail"), color: blockedThreads.isEmpty ? .green : .red)
                        opsMetricCard(title: LocalizedString.text("runtime_linked_threads"), value: "\(runtimeLinkedThreads.count)", detail: LocalizedString.text("runtime_linked_threads_detail"), color: runtimeLinkedThreads.isEmpty ? .green : .orange)
                        opsMetricCard(title: LocalizedString.text("hotspot_lanes_title"), value: "\(hotspotLanes.count)", detail: leadHotspotLane.map { LocalizedString.format("lead_lane_summary", $0.title) } ?? LocalizedString.text("no_thread_lane_pressure"), color: hotspotLanes.isEmpty ? .green : .orange)
                        opsMetricCard(title: LocalizedString.text("pressure_modes_title"), value: "\(pressureModes.count)", detail: leadPressureMode.map { LocalizedString.format("lead_mode_summary", $0.mode.title) } ?? LocalizedString.text("no_pressure_mode_dominates"), color: leadPressureMode?.mode.color ?? .green)
                        opsMetricCard(title: LocalizedString.text("session_families_title"), value: "\(sessionHotspots.count)", detail: leadSessionHotspot.map { LocalizedString.format("lead_session_family_summary", $0.title) } ?? LocalizedString.text("no_runtime_session_family_visible"), color: leadSessionHotspot == nil ? .green : .orange)
                        opsMetricCard(title: LocalizedString.text("timeline_slices_title"), value: "\(pressureTimeline.count)", detail: leadTimelineSlice.map { LocalizedString.format("lead_timeline_slice_summary", $0.title) } ?? LocalizedString.text("no_recent_pressure_slice"), color: leadTimelineSlice == nil ? .green : .blue)
                        opsMetricCard(title: LocalizedString.text("lead_thread_title"), value: leadHotspotThread.map { String($0.threadID.prefix(12)) } ?? LocalizedString.text("ops_none"), detail: leadHotspotThread.map(opsThreadHotspotReason) ?? LocalizedString.text("no_lead_hotspot_active"), color: leadHotspotThread == nil ? .green : .red)
                        opsMetricCard(title: LocalizedString.text("lead_lane_title"), value: leadHotspotLane?.title ?? LocalizedString.text("ops_none"), detail: leadHotspotLane.map { LocalizedString.format("lead_lane_pressure_summary", $0.hotspotThreadCount, $0.approvalPressure, $0.blockedThreadCount) } ?? LocalizedString.text("no_concentrated_lane_active"), color: leadHotspotLane == nil ? .green : .red)
                        opsMetricCard(title: LocalizedString.text("lead_mode_title"), value: leadPressureMode?.mode.shortTitle ?? LocalizedString.text("ops_none"), detail: leadPressureMode.map { LocalizedString.format("lead_mode_pressure_summary", $0.threadCount, $0.runtimeBacklogCount, $0.runtimeFailureCount) } ?? LocalizedString.text("no_pressure_mode_needs_triage"), color: leadPressureMode?.mode.color ?? .green)
                        opsMetricCard(title: LocalizedString.text("lead_session_title"), value: leadSessionHotspot?.title ?? LocalizedString.text("ops_none"), detail: leadSessionHotspot.map { LocalizedString.format("lead_session_runtime_summary", $0.threadCount, $0.queuedDispatchCount, $0.inflightDispatchCount, $0.failedDispatchCount) } ?? LocalizedString.text("no_session_family_dominates"), color: leadSessionHotspot == nil ? .green : .orange)
                    }

                    if let projectionContextText {
                        Text(projectionContextText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .center, spacing: 12) {
                            TextField(LocalizedString.text("thread_search_placeholder"), text: $searchText)
                                .textFieldStyle(.roundedBorder)

                            Picker(LocalizedString.text("ops_filter_label"), selection: $selectedFilter) {
                                ForEach(OpsCenterThreadListFilter.allCases) { filter in
                                    Text(filter.title).tag(filter)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 260)
                        }

                        HStack(alignment: .center, spacing: 12) {
                            Picker(LocalizedString.text("ops_focus_label"), selection: $selectedFocus) {
                                ForEach(OpsCenterThreadFocus.allCases) { focus in
                                    Text(focus.title).tag(focus)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 420)

                            Picker(LocalizedString.text("ops_sort_label"), selection: $selectedSort) {
                                ForEach(OpsCenterThreadSort.allCases) { sort in
                                    Text(sort.title).tag(sort)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 180)

                            Spacer()

                            Text(LocalizedString.format("threads_visible_in_scope", displayedThreads.count, threadSummaries.count))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    sectionTitle(LocalizedString.text("operator_pivots_title"))
                    if leadHotspotThread == nil && leadApprovalThread == nil && leadBlockedThread == nil && leadRuntimeThread == nil {
                        opsInlineEmptyState(LocalizedString.text("no_actionable_lead_thread"))
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 10)], spacing: 10) {
                            if let thread = leadHotspotThread {
                                Button {
                                    onSelectThread(thread.threadID)
                                } label: {
                                    threadPivotCard(
                                        title: LocalizedString.text("lead_hotspot_card_title"),
                                        badgeTitle: LocalizedString.text("hotspot_badge"),
                                        color: .red,
                                        thread: thread,
                                        detailText: opsThreadHotspotReason(thread)
                                    )
                                }
                                .buttonStyle(.plain)
                            }

                            if let thread = leadApprovalThread {
                                Button {
                                    onSelectThread(thread.threadID)
                                } label: {
                                    threadPivotCard(
                                        title: LocalizedString.text("lead_approval_card_title"),
                                        badgeTitle: LocalizedString.text("approval"),
                                        color: .yellow,
                                        thread: thread,
                                        detailText: LocalizedString.format("approvals_waiting_in_thread", thread.pendingApprovalCount)
                                    )
                                }
                                .buttonStyle(.plain)
                            }

                            if let thread = leadBlockedThread {
                                Button {
                                    onSelectThread(thread.threadID)
                                } label: {
                                    threadPivotCard(
                                        title: LocalizedString.text("lead_blocked_card_title"),
                                        badgeTitle: LocalizedString.blocked,
                                        color: .orange,
                                        thread: thread,
                                        detailText: LocalizedString.format("blocked_tasks_in_thread", thread.blockedTaskCount)
                                    )
                                }
                                .buttonStyle(.plain)
                            }

                            if let thread = leadRuntimeThread {
                                Button {
                                    onSelectThread(thread.threadID)
                                } label: {
                                    threadPivotCard(
                                        title: LocalizedString.text("lead_runtime_card_title"),
                                        badgeTitle: LocalizedString.text("runtime_category"),
                                        color: .blue,
                                        thread: thread,
                                        detailText: thread.relatedSession.map {
                                            LocalizedString.format("runtime_thread_pressure_summary", $0.queuedDispatchCount, $0.inflightDispatchCount, $0.failedDispatchCount)
                                        } ?? LocalizedString.text("runtime_thread_pressure_fallback")
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    sectionTitle(LocalizedString.text("intervention_queue_title"))
                    if interventionThreads.isEmpty {
                        opsInlineEmptyState(LocalizedString.text("no_actionable_thread_queue"))
                    } else {
                        VStack(spacing: 8) {
                            ForEach(Array(interventionThreads.prefix(8))) { thread in
                                Button {
                                    onSelectThread(thread.threadID)
                                } label: {
                                    opsThreadRow(thread, emphasis: opsThreadIsHotspot(thread) ? .hotspot : .standard)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    if let sessionID = thread.relatedSession?.sessionID {
                                        Button(LocalizedString.text("open_linked_session")) {
                                            onSelectSession(sessionID)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    sectionTitle(LocalizedString.text("hotspot_lanes_title"))
                    if hotspotLanes.isEmpty {
                        opsInlineEmptyState(LocalizedString.text("no_thread_lane_matches"))
                    } else {
                        VStack(spacing: 8) {
                            ForEach(Array(hotspotLanes.prefix(5))) { lane in
                                Button {
                                    onSelectThread(lane.leadThreadID)
                                } label: {
                                    hotspotLaneRow(lane)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    sectionTitle(LocalizedString.text("pressure_modes_title"))
                    if pressureModes.isEmpty {
                        opsInlineEmptyState(LocalizedString.text("no_pressure_mode_visible"))
                    } else {
                        VStack(spacing: 8) {
                            ForEach(pressureModes) { mode in
                                Button {
                                    onSelectThread(mode.leadThreadID)
                                } label: {
                                    pressureModeRow(mode)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    sectionTitle(LocalizedString.text("session_hotspots_title"))
                    if sessionHotspots.isEmpty {
                        opsInlineEmptyState(LocalizedString.text("no_runtime_linked_session_family"))
                    } else {
                        VStack(spacing: 8) {
                            ForEach(sessionHotspots) { session in
                                Button {
                                    if let sessionID = session.sessionID {
                                        onSelectSession(sessionID)
                                    } else {
                                        onSelectThread(session.leadThreadID)
                                    }
                                } label: {
                                    sessionHotspotRow(session)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    if let sessionID = session.sessionID {
                                        Button(LocalizedString.text("open_lead_session")) {
                                            onSelectSession(sessionID)
                                        }
                                    }
                                    Button(LocalizedString.text("open_lead_thread")) {
                                        onSelectThread(session.leadThreadID)
                                    }
                                }
                            }
                        }
                    }

                    sectionTitle(LocalizedString.text("pressure_timeline_title"))
                    if pressureTimeline.isEmpty {
                        opsInlineEmptyState(LocalizedString.text("no_recent_thread_pressure_slice"))
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 10)], spacing: 10) {
                            ForEach(pressureTimeline) { slice in
                                Button {
                                    onSelectThread(slice.leadThreadID)
                                } label: {
                                    pressureTimelineCard(slice)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if !approvalThreads.isEmpty {
                        sectionTitle(LocalizedString.text("approval_queue_title"))
                        VStack(spacing: 8) {
                            ForEach(Array(approvalThreads.prefix(4))) { thread in
                                Button {
                                    onSelectThread(thread.threadID)
                                } label: {
                                    opsThreadRow(thread, emphasis: .standard)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    sectionTitle(LocalizedString.text("thread_inventory_title"))
                    if displayedThreads.isEmpty {
                        opsInlineEmptyState(LocalizedString.text("no_threads_match_scope"))
                    } else {
                        VStack(spacing: 8) {
                            ForEach(displayedThreads) { thread in
                                Button {
                                    onSelectThread(thread.threadID)
                                } label: {
                                    opsThreadRow(thread, emphasis: opsThreadIsHotspot(thread) ? .hotspot : .standard)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    if let sessionID = thread.relatedSession?.sessionID {
                                        Button(LocalizedString.text("open_linked_session")) {
                                            onSelectSession(sessionID)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding()
        }
    }

    private func matchesThreadFilter(_ thread: OpsCenterThreadSummary) -> Bool {
        switch selectedFilter {
        case .all:
            return true
        case .active:
            return opsThreadIsActive(thread)
        case .blocked:
            return thread.blockedTaskCount > 0 || thread.status == "blocked"
        }
    }

    private func matchesThreadSearch(_ thread: OpsCenterThreadSummary) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty == false else { return true }

        let haystacks = [
            thread.threadID,
            thread.workflowName,
            thread.entryAgentName ?? "",
            thread.participantNames.joined(separator: " "),
            thread.relatedSession?.latestFailureText ?? "",
            opsThreadHotspotReason(thread)
        ]

        return haystacks.contains { value in
            value.localizedCaseInsensitiveContains(query)
        }
    }

    private func sortThreads(lhs: OpsCenterThreadSummary, rhs: OpsCenterThreadSummary) -> Bool {
        switch selectedSort {
        case .hotspot:
            if lhs.hotspotScore != rhs.hotspotScore {
                return lhs.hotspotScore > rhs.hotspotScore
            }
        case .recent:
            break
        case .approval:
            if lhs.pendingApprovalCount != rhs.pendingApprovalCount {
                return lhs.pendingApprovalCount > rhs.pendingApprovalCount
            }
        case .runtime:
            let lhsRuntime = opsThreadRuntimePressureScore(lhs)
            let rhsRuntime = opsThreadRuntimePressureScore(rhs)
            if lhsRuntime != rhsRuntime {
                return lhsRuntime > rhsRuntime
            }
        case .messages:
            let lhsLoad = lhs.messageCount + lhs.taskCount
            let rhsLoad = rhs.messageCount + rhs.taskCount
            if lhsLoad != rhsLoad {
                return lhsLoad > rhsLoad
            }
        }

        let lhsDate = lhs.lastUpdatedAt ?? .distantPast
        let rhsDate = rhs.lastUpdatedAt ?? .distantPast
        if lhsDate != rhsDate {
            return lhsDate > rhsDate
        }

        if lhs.hotspotScore != rhs.hotspotScore {
            return lhs.hotspotScore > rhs.hotspotScore
        }

        return lhs.threadID.localizedCaseInsensitiveCompare(rhs.threadID) == .orderedAscending
    }

    private func hotspotLaneRow(_ lane: OpsCenterThreadClusterDigest) -> some View {
        HStack(alignment: .top, spacing: 12) {
            opsStatusPill(
                title: lane.hotspotThreadCount > 0 ? LocalizedString.text("pressure_lane_badge") : LocalizedString.text("stable_lane_badge"),
                color: lane.hotspotThreadCount > 0 ? .orange : .green
            )
            .frame(width: 104, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(lane.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                Text(lane.detailText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                Text(lane.subtitleText)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(LocalizedString.format("lane_count_summary", lane.threadCount, lane.hotspotThreadCount))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(LocalizedString.format("lane_pressure_summary", lane.approvalPressure, lane.blockedThreadCount, lane.runtimeLinkedThreadCount))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                if let latestAt = lane.latestAt {
                    Text(latestAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(10)
        .background(Color(.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func threadPivotCard(
        title: String,
        badgeTitle: String,
        color: Color,
        thread: OpsCenterThreadSummary,
        detailText: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                    Text(String(thread.threadID.prefix(12)))
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(.primary)
                }

                Spacer()

                opsStatusPill(title: badgeTitle, color: color)
            }

            Text(detailText)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(3)

            Text([
                thread.workflowName,
                thread.entryAgentName,
                thread.participantNames.isEmpty ? nil : LocalizedString.format("participants_count_summary", thread.participantNames.count)
            ].compactMap { $0 }.joined(separator: " • "))
            .font(.caption2)
            .foregroundColor(.secondary)
            .lineLimit(1)

            Text(LocalizedString.format("thread_load_summary", thread.pendingApprovalCount, thread.blockedTaskCount, thread.activeTaskCount, thread.messageCount))
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func pressureModeRow(_ mode: OpsCenterThreadPressureDigest) -> some View {
        HStack(alignment: .top, spacing: 12) {
            opsStatusPill(title: mode.mode.shortTitle, color: mode.mode.color)
                .frame(width: 104, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(mode.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                Text(mode.detailText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                Text(LocalizedString.format("mode_count_summary", mode.threadCount, mode.hotspotThreadCount, mode.totalHotspotScore))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(LocalizedString.format("mode_pressure_summary", mode.approvalPressure, mode.blockedThreadCount))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(LocalizedString.format("mode_runtime_summary", mode.runtimeFailureCount, mode.runtimeBacklogCount))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                if let latestAt = mode.latestAt {
                    Text(latestAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(10)
        .background(Color(.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func sessionHotspotRow(_ session: OpsCenterThreadSessionDigest) -> some View {
        HStack(alignment: .top, spacing: 12) {
            opsStatusPill(
                title: session.failedDispatchCount > 0 ? LocalizedString.text("session_failure_badge") : LocalizedString.text("session_watch_badge"),
                color: session.failedDispatchCount > 0 ? .red : .orange
            )
            .frame(width: 104, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(session.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                Text(session.detailText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                Text(LocalizedString.format("session_hotspot_summary", session.threadCount, session.hotspotThreadCount, session.approvalPressure))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(LocalizedString.format("session_hotspot_runtime_summary", session.queuedDispatchCount, session.inflightDispatchCount))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text("F \(session.failedDispatchCount)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                if let latestAt = session.latestAt {
                    Text(latestAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(10)
        .background(Color(.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func pressureTimelineCard(_ slice: OpsCenterThreadPressureTimelineDigest) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(slice.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                Spacer()
                opsStatusPill(
                    title: slice.hotspotThreadCount > 0 ? LocalizedString.text("hot_badge") : LocalizedString.text("quiet_badge"),
                    color: slice.hotspotThreadCount > 0 ? .orange : .green
                )
            }

            Text(slice.detailText)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(3)

            Text(LocalizedString.format("timeline_count_summary", slice.threadCount, slice.hotspotThreadCount, slice.approvalPressure))
                .font(.caption2)
                .foregroundColor(.secondary)

            Text(LocalizedString.format("timeline_pressure_summary", slice.blockedThreadCount, slice.runtimeLinkedThreadCount))
                .font(.caption2)
                .foregroundColor(.secondary)

            if let latestAt = slice.latestAt {
                Text(latestAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct OpsCenterLiveRunDashboardView: View {
    @EnvironmentObject var appState: AppState
    let workflow: Workflow?
    let projections: OpsCenterProjectionBundle?
    let onSelectSession: (String) -> Void
    let onSelectNode: (UUID) -> Void
    let onSelectThread: (String) -> Void

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

    private var threadSummaries: [OpsCenterThreadSummary] {
        opsBuildThreadSummaries(
            project: appState.currentProject,
            workflow: workflow,
            messages: appState.messageManager.messages,
            tasks: appState.taskManager.tasks,
            sessionSummaries: effectiveSessionSummaries,
            projections: projections
        )
    }

    private var hotspotThreads: [OpsCenterThreadSummary] {
        threadSummaries.filter(opsThreadIsHotspot)
    }

    private var activeThreadCount: Int {
        threadSummaries.filter(opsThreadIsActive).count
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
                        title: LocalizedString.text("no_workflow_available"),
                        detail: LocalizedString.text("no_workflow_available_desc")
                    )
                } else {
                    sectionTitle(LocalizedString.text("current_runtime_title"))
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 14)], spacing: 14) {
                        opsMetricCard(title: LocalizedString.text("workflow_label"), value: snapshot.workflowName, detail: LocalizedString.text("selected_runtime_surface"), color: .blue)
                        opsMetricCard(title: LocalizedString.text("active_sessions_label"), value: "\(effectiveActiveSessionCount)", detail: LocalizedString.format("active_sessions_in_scope", effectiveTotalSessionCount), color: .green)
                        opsMetricCard(title: LocalizedString.text("active_threads_label"), value: "\(activeThreadCount)", detail: LocalizedString.format("active_threads_in_scope", threadSummaries.count), color: activeThreadCount > 0 ? .purple : .green)
                        opsMetricCard(title: LocalizedString.text("hot_threads_label"), value: "\(hotspotThreads.count)", detail: hotspotThreads.first.map(opsThreadHotspotReason) ?? LocalizedString.text("no_urgent_thread_drilldown"), color: hotspotThreads.isEmpty ? .green : .orange)
                        opsMetricCard(title: LocalizedString.text("queued_status"), value: "\(snapshot.queuedDispatchCount)", detail: LocalizedString.text("queued_dispatches_waiting"), color: .blue)
                        opsMetricCard(title: LocalizedString.text("running_status"), value: "\(snapshot.inflightDispatchCount)", detail: LocalizedString.text("inflight_dispatches"), color: .orange)
                        opsMetricCard(title: LocalizedString.text("failures_label"), value: "\(effectiveFailureCount)", detail: snapshot.latestErrorText ?? projections?.liveRun?.latestErrorText ?? LocalizedString.text("no_recent_runtime_failure"), color: effectiveFailureCount > 0 ? .red : .green)
                        opsMetricCard(title: LocalizedString.text("approvals_label"), value: "\(effectiveApprovalCount)", detail: LocalizedString.text("pending_approval_gates"), color: effectiveApprovalCount > 0 ? .yellow : .secondary)
                    }

                    if let projectionContextText {
                        Text(projectionContextText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Text(LocalizedString.text("live_run_investigation_hint"))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    sectionTitle(LocalizedString.text("hot_threads_title"))
                    if hotspotThreads.isEmpty {
                        opsInlineEmptyState(LocalizedString.text("hot_threads_empty"))
                    } else {
                        VStack(spacing: 8) {
                            ForEach(Array(hotspotThreads.prefix(5))) { thread in
                                Button {
                                    onSelectThread(thread.threadID)
                                } label: {
                                    opsThreadRow(thread, emphasis: .hotspot)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    sectionTitle(LocalizedString.text("hot_nodes_title"))
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
                                        Text(node.agentName ?? LocalizedString.text("no_bound_agent"))
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
                                        Text(LocalizedString.format("node_io_summary", node.incomingEdgeCount, node.outgoingEdgeCount))
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        if let averageDuration = node.averageDuration {
                                            Text(LocalizedString.format("average_duration_short", opsDurationText(averageDuration)))
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

                    sectionTitle(LocalizedString.text("active_sessions_title"))
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
                title: session.isPrimaryRuntimeSession ? LocalizedString.text("primary_badge") : LocalizedString.text("session_badge"),
                color: session.isPrimaryRuntimeSession ? .teal : .secondary
            )
            .frame(width: 72, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(session.sessionID)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.primary)
                Text(
                    LocalizedString.format("session_counts_summary", session.eventCount, session.dispatchCount, session.receiptCount)
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
                Text(LocalizedString.format("session_runtime_summary", session.queuedDispatchCount, session.inflightDispatchCount))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(LocalizedString.format("session_completion_summary", session.failedDispatchCount, session.completedDispatchCount))
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
    let onSelectThread: (String) -> Void

    @State private var searchText = ""
    @State private var selectedFilter: OpsCenterSessionListFilter = .all
    @State private var selectedFocus: OpsCenterSessionFocus = .all
    @State private var selectedSort: OpsCenterSessionSort = .recent

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

    private var threadSummaries: [OpsCenterThreadSummary] {
        opsBuildThreadSummaries(
            project: appState.currentProject,
            workflow: workflow,
            messages: appState.messageManager.messages,
            tasks: appState.taskManager.tasks,
            sessionSummaries: effectiveSessions,
            projections: projections
        )
    }

    private var hotspotThreads: [OpsCenterThreadSummary] {
        threadSummaries.filter(opsThreadIsHotspot)
    }

    private var threadApprovalPressure: Int {
        threadSummaries.reduce(0) { $0 + $1.pendingApprovalCount }
    }

    private var blockedThreadCount: Int {
        threadSummaries.filter { $0.status == "blocked" }.count
    }

    private var leadHotspotThread: OpsCenterThreadSummary? {
        hotspotThreads.first
    }

    private var filteredSessions: [OpsCenterSessionSummary] {
        effectiveSessions.filter { session in
            matchesSessionFilter(session) && matchesSessionSearch(session)
        }
    }

    private var sortedSessions: [OpsCenterSessionSummary] {
        filteredSessions.sorted(by: sortSessions)
    }

    private var displayedSessions: [OpsCenterSessionSummary] {
        switch selectedFocus {
        case .all:
            return sortedSessions
        case .hotspots:
            return sortedSessions.filter(opsSessionIsHotspot)
        }
    }

    private var hotspotSessions: [OpsCenterSessionSummary] {
        sortedSessions.filter(opsSessionIsHotspot)
    }

    private var hotspotDispatchPressure: Int {
        hotspotSessions.reduce(0) { partial, session in
            partial + session.queuedDispatchCount + session.inflightDispatchCount
        }
    }

    private var hotspotFailureSignals: Int {
        hotspotSessions.reduce(0) { partial, session in
            partial + session.failedDispatchCount
        }
    }

    private var leadHotspotSession: OpsCenterSessionSummary? {
        hotspotSessions.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                sectionTitle(LocalizedString.text("sessions_thread_frontline_title"))
                if threadSummaries.isEmpty {
                    opsInlineEmptyState(LocalizedString.text("sessions_thread_frontline_empty"))
                } else {
                    Text(LocalizedString.text("sessions_thread_frontline_desc"))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 14)], spacing: 14) {
                        opsMetricCard(title: LocalizedString.text("hotspot_threads_label"), value: "\(hotspotThreads.count)", detail: LocalizedString.text("hotspot_threads_detail"), color: hotspotThreads.isEmpty ? .green : .orange)
                        opsMetricCard(title: LocalizedString.text("approval_pressure_label"), value: "\(threadApprovalPressure)", detail: LocalizedString.text("thread_approval_pressure_detail"), color: threadApprovalPressure > 0 ? .yellow : .green)
                        opsMetricCard(title: LocalizedString.text("blocked_tasks"), value: "\(blockedThreadCount)", detail: LocalizedString.text("thread_blocked_detail"), color: blockedThreadCount > 0 ? .red : .green)
                        opsMetricCard(title: LocalizedString.text("lead_thread_title"), value: leadHotspotThread.map { String($0.threadID.prefix(12)) } ?? LocalizedString.text("ops_none"), detail: leadHotspotThread.map(opsThreadHotspotReason) ?? LocalizedString.text("lead_thread_intervention_detail"), color: leadHotspotThread == nil ? .green : .red)
                    }

                    if !hotspotThreads.isEmpty {
                        sectionTitle(LocalizedString.text("current_thread_hotspots_title"))
                        VStack(spacing: 8) {
                            ForEach(Array(hotspotThreads.prefix(4))) { thread in
                                Button {
                                    onSelectThread(thread.threadID)
                                } label: {
                                    opsThreadRow(thread, emphasis: .hotspot)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    sectionTitle(LocalizedString.text("workbench_threads_title"))
                    VStack(spacing: 8) {
                        ForEach(threadSummaries) { thread in
                            Button {
                                onSelectThread(thread.threadID)
                            } label: {
                                opsThreadRow(thread, emphasis: .standard)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                sectionTitle(LocalizedString.text("session_queue_title"))
                if effectiveSessions.isEmpty {
                    opsEmptyState(
                        title: LocalizedString.text("session_queue_empty_title"),
                        detail: LocalizedString.text("session_queue_empty_desc")
                    )
                } else {
                    Text(LocalizedString.text("session_queue_hint"))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .center, spacing: 12) {
                            TextField(LocalizedString.text("session_search_placeholder"), text: $searchText)
                                .textFieldStyle(.roundedBorder)

                            Picker(LocalizedString.text("ops_filter_label"), selection: $selectedFilter) {
                                ForEach(OpsCenterSessionListFilter.allCases) { filter in
                                    Text(filter.title).tag(filter)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 260)
                        }

                        HStack(alignment: .center, spacing: 12) {
                            Picker(LocalizedString.text("ops_focus_label"), selection: $selectedFocus) {
                                ForEach(OpsCenterSessionFocus.allCases) { focus in
                                    Text(focus.title).tag(focus)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 230)

                            Picker(LocalizedString.text("ops_sort_label"), selection: $selectedSort) {
                                ForEach(OpsCenterSessionSort.allCases) { sort in
                                    Text(sort.title).tag(sort)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 170)

                            Spacer()

                            Text(LocalizedString.format("sessions_visible_in_scope", displayedSessions.count, effectiveSessions.count))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 14)], spacing: 14) {
                        opsMetricCard(title: LocalizedString.text("hotspot_sessions_label"), value: "\(hotspotSessions.count)", detail: LocalizedString.text("hotspot_sessions_detail"), color: hotspotSessions.isEmpty ? .green : .orange)
                        opsMetricCard(title: LocalizedString.text("dispatch_pressure_label"), value: "\(hotspotDispatchPressure)", detail: LocalizedString.text("dispatch_pressure_detail"), color: hotspotDispatchPressure > 0 ? .orange : .green)
                        opsMetricCard(title: LocalizedString.text("failure_signals_label"), value: "\(hotspotFailureSignals)", detail: LocalizedString.text("failure_signals_detail"), color: hotspotFailureSignals > 0 ? .red : .green)
                        opsMetricCard(title: LocalizedString.text("lead_hotspot_label"), value: leadHotspotSession.map { String($0.sessionID.prefix(12)) } ?? LocalizedString.text("ops_none"), detail: leadHotspotSession.map(opsSessionHotspotReason) ?? LocalizedString.text("lead_hotspot_detail"), color: leadHotspotSession == nil ? .green : .red)
                    }

                    if sessions.isEmpty, let freshestProjectionAt = projections?.freshestGeneratedAt {
                        Text(LocalizedString.format("persisted_sessions_notice", freshestProjectionAt.formatted(date: .abbreviated, time: .shortened)))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if !hotspotSessions.isEmpty {
                        sectionTitle(LocalizedString.text("ops_hotspots"))
                        VStack(spacing: 8) {
                            ForEach(Array(hotspotSessions.prefix(3))) { session in
                                Button {
                                    onSelectSession(session.sessionID)
                                } label: {
                                    HStack(alignment: .top, spacing: 12) {
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(session.sessionID)
                                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                                .foregroundColor(.primary)
                                            Text(opsSessionHotspotReason(session))
                                                .font(.caption.weight(.medium))
                                                .foregroundColor(.primary)
                                            Text(LocalizedString.format("queued_running_failed_receipts_summary", session.queuedDispatchCount, session.inflightDispatchCount, session.failedDispatchCount, session.receiptCount))
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }

                                        Spacer()

                                        VStack(alignment: .trailing, spacing: 6) {
                                            opsStatusPill(
                                                title: session.failedDispatchCount > 0 ? LocalizedString.text("failure_hotspot_badge") : (session.inflightDispatchCount > 0 ? LocalizedString.text("running_hotspot_badge") : LocalizedString.text("watch_badge")),
                                                color: session.failedDispatchCount > 0 ? .red : (session.inflightDispatchCount > 0 ? .orange : .teal)
                                            )
                                            if let lastUpdatedAt = session.lastUpdatedAt {
                                                Text(lastUpdatedAt.formatted(date: .abbreviated, time: .shortened))
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
                    }

                    if displayedSessions.isEmpty {
                        opsInlineEmptyState(LocalizedString.text("sessions_no_match_scope"))
                    }

                    ForEach(displayedSessions) { session in
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
                                        title: session.isPrimaryRuntimeSession ? LocalizedString.text("primary_runtime_session_badge") : LocalizedString.text("linked_session_badge"),
                                        color: session.isPrimaryRuntimeSession ? .teal : .blue
                                    )
                                }

                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                                    opsMetricCard(title: LocalizedString.text("events"), value: "\(session.eventCount)", detail: LocalizedString.text("events_detail"), color: .blue)
                                    opsMetricCard(title: LocalizedString.text("dispatches_label"), value: "\(session.dispatchCount)", detail: LocalizedString.text("dispatches_detail"), color: .orange)
                                    opsMetricCard(title: LocalizedString.text("receipts_label"), value: "\(session.receiptCount)", detail: LocalizedString.text("receipts_detail"), color: .green)
                                    opsMetricCard(title: LocalizedString.text("failures_label"), value: "\(session.failedDispatchCount)", detail: session.latestFailureText ?? LocalizedString.text("no_recent_runtime_failure"), color: session.failedDispatchCount > 0 ? .red : .green)
                                }

                                HStack(spacing: 12) {
                                    Text(
                                        session.workflowIDs.isEmpty
                                            ? LocalizedString.text("no_workflow_ids_resolved")
                                            : LocalizedString.format("workflow_ids_prefix", session.workflowIDs.joined(separator: ", "))
                                    )
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                    Spacer()

                                    if let lastUpdatedAt = session.lastUpdatedAt {
                                        Text(LocalizedString.format("updated_time", lastUpdatedAt.formatted(date: .abbreviated, time: .shortened)))
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

    private func matchesSessionFilter(_ session: OpsCenterSessionSummary) -> Bool {
        switch selectedFilter {
        case .all:
            return true
        case .active:
            return session.queuedDispatchCount > 0 || session.inflightDispatchCount > 0
        case .failed:
            return session.failedDispatchCount > 0 || (session.latestFailureText?.isEmpty == false)
        }
    }

    private func matchesSessionSearch(_ session: OpsCenterSessionSummary) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return true }

        let haystack = [
            session.sessionID.lowercased(),
            session.workflowIDs.joined(separator: " ").lowercased(),
            session.latestFailureText?.lowercased() ?? ""
        ]
        .joined(separator: " ")

        return haystack.contains(query)
    }

    private func sortSessions(_ lhs: OpsCenterSessionSummary, _ rhs: OpsCenterSessionSummary) -> Bool {
        switch selectedSort {
        case .recent:
            let lhsDate = lhs.lastUpdatedAt ?? .distantPast
            let rhsDate = rhs.lastUpdatedAt ?? .distantPast
            if lhsDate != rhsDate {
                return lhsDate > rhsDate
            }
            if opsSessionActivityScore(lhs) != opsSessionActivityScore(rhs) {
                return opsSessionActivityScore(lhs) > opsSessionActivityScore(rhs)
            }
        case .failures:
            if opsSessionFailureScore(lhs) != opsSessionFailureScore(rhs) {
                return opsSessionFailureScore(lhs) > opsSessionFailureScore(rhs)
            }
            if opsSessionActivityScore(lhs) != opsSessionActivityScore(rhs) {
                return opsSessionActivityScore(lhs) > opsSessionActivityScore(rhs)
            }
        case .activity:
            if opsSessionActivityScore(lhs) != opsSessionActivityScore(rhs) {
                return opsSessionActivityScore(lhs) > opsSessionActivityScore(rhs)
            }
            if opsSessionFailureScore(lhs) != opsSessionFailureScore(rhs) {
                return opsSessionFailureScore(lhs) > opsSessionFailureScore(rhs)
            }
        }

        let lhsDate = lhs.lastUpdatedAt ?? .distantPast
        let rhsDate = rhs.lastUpdatedAt ?? .distantPast
        if lhsDate != rhsDate {
            return lhsDate > rhsDate
        }
        return lhs.sessionID.localizedCaseInsensitiveCompare(rhs.sessionID) == .orderedAscending
    }
}

private enum OpsCenterSessionListFilter: String, CaseIterable, Identifiable {
    case all
    case active
    case failed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return LocalizedString.text("ops_all")
        case .active:
            return LocalizedString.text("ops_active")
        case .failed:
            return LocalizedString.text("failed_label")
        }
    }
}

private enum OpsCenterThreadListFilter: String, CaseIterable, Identifiable {
    case all
    case active
    case blocked

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return LocalizedString.text("ops_all")
        case .active:
            return LocalizedString.text("ops_active")
        case .blocked:
            return LocalizedString.blocked
        }
    }
}

private enum OpsCenterThreadFocus: String, CaseIterable, Identifiable {
    case all
    case hotspots
    case approval
    case blocked
    case runtime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return LocalizedString.text("ops_all")
        case .hotspots:
            return LocalizedString.text("ops_hotspots")
        case .approval:
            return LocalizedString.text("approval")
        case .blocked:
            return LocalizedString.blocked
        case .runtime:
            return LocalizedString.text("runtime_category")
        }
    }
}

private enum OpsCenterThreadSort: String, CaseIterable, Identifiable {
    case hotspot
    case recent
    case approval
    case runtime
    case messages

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hotspot:
            return LocalizedString.text("ops_hotspot_score")
        case .recent:
            return LocalizedString.text("ops_most_recent")
        case .approval:
            return LocalizedString.text("ops_approval_load")
        case .runtime:
            return LocalizedString.text("ops_runtime_load")
        case .messages:
            return LocalizedString.text("ops_message_load")
        }
    }
}

private enum OpsCenterSignalListFilter: String, CaseIterable, Identifiable {
    case all
    case crons
    case tools
    case projections

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return LocalizedString.text("ops_all")
        case .crons:
            return LocalizedString.text("ops_crons")
        case .tools:
            return LocalizedString.tools
        case .projections:
            return LocalizedString.text("ops_projections")
        }
    }
}

private enum OpsCenterSignalSort: String, CaseIterable, Identifiable {
    case priority
    case recent
    case name

    var id: String { rawValue }

    var title: String {
        switch self {
        case .priority:
            return LocalizedString.priority
        case .recent:
            return LocalizedString.text("ops_most_recent")
        case .name:
            return LocalizedString.text("ops_name")
        }
    }
}

private enum OpsCenterThreadPressureMode: String, CaseIterable, Identifiable {
    case approval
    case blocked
    case runtimeFailure
    case runtimeBacklog
    case activeWork
    case stable

    var id: String { rawValue }

    var title: String {
        switch self {
        case .approval:
            return LocalizedString.text("ops_approval_gridlock")
        case .blocked:
            return LocalizedString.text("ops_blocked_work")
        case .runtimeFailure:
            return LocalizedString.text("ops_runtime_failure")
        case .runtimeBacklog:
            return LocalizedString.text("ops_runtime_backlog")
        case .activeWork:
            return LocalizedString.text("ops_active_work")
        case .stable:
            return LocalizedString.text("ops_stable_hold")
        }
    }

    var shortTitle: String {
        switch self {
        case .approval:
            return LocalizedString.text("approval")
        case .blocked:
            return LocalizedString.blocked
        case .runtimeFailure:
            return LocalizedString.text("ops_failure_short")
        case .runtimeBacklog:
            return LocalizedString.text("ops_backlog_short")
        case .activeWork:
            return LocalizedString.text("ops_active")
        case .stable:
            return LocalizedString.text("ops_stable_short")
        }
    }

    var color: Color {
        switch self {
        case .approval:
            return .yellow
        case .blocked:
            return .red
        case .runtimeFailure:
            return .red
        case .runtimeBacklog:
            return .orange
        case .activeWork:
            return .blue
        case .stable:
            return .green
        }
    }
}

private enum OpsCenterSignalKind: String {
    case cron
    case tool
    case projection

    var title: String {
        switch self {
        case .cron:
            return LocalizedString.text("cron_category")
        case .tool:
            return LocalizedString.text("tool_category")
        case .projection:
            return LocalizedString.text("ops_projections")
        }
    }
}

private enum OpsCenterSessionFocus: String, CaseIterable, Identifiable {
    case all
    case hotspots

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return LocalizedString.text("ops_all_sessions")
        case .hotspots:
            return LocalizedString.text("ops_hotspots")
        }
    }
}

private enum OpsCenterSessionSort: String, CaseIterable, Identifiable {
    case recent
    case failures
    case activity

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recent:
            return LocalizedString.text("ops_most_recent")
        case .failures:
            return LocalizedString.text("ops_failure_pressure")
        case .activity:
            return LocalizedString.text("ops_activity_load")
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
                title: edge.label.isEmpty ? LocalizedString.text("route_path_fallback") : edge.label,
                fromTitle: workflow.nodes.first(where: { $0.id == edge.fromNodeID })?.title ?? LocalizedString.text("investigation_unknown_title"),
                toTitle: workflow.nodes.first(where: { $0.id == edge.toNodeID })?.title ?? LocalizedString.text("investigation_unknown_title"),
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
                    sectionTitle(LocalizedString.text("workflow_runtime_map_title"))
                    Spacer()
                    Picker(LocalizedString.text("ops_layer_label"), selection: $selectedLayer) {
                        ForEach(OpsCenterMapLayer.allCases) { layer in
                            Text(layer.title).tag(layer)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 360)
                }

                if workflow == nil {
                    opsEmptyState(
                        title: LocalizedString.text("no_workflow_selected"),
                        detail: LocalizedString.text("workflow_map_needs_workflow")
                    )
                } else {
                    Text(selectedLayer.detail)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if snapshot.nodeSummaries.isEmpty, let freshestProjectionAt = projections?.freshestGeneratedAt {
                        Text(
                            LocalizedString.format(
                                "workflow_map_projection_notice",
                                freshestProjectionAt.formatted(date: .abbreviated, time: .shortened)
                            )
                        )
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
                                            Text(node.agentName ?? LocalizedString.text("no_bound_agent"))
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
                                                title: LocalizedString.format("anomalies_count_badge", anomalyCount),
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
                                        Text(LocalizedString.format("incoming_count_badge", node.incomingEdgeCount))
                                        Text(LocalizedString.format("outgoing_count_badge", node.outgoingEdgeCount))
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

                    sectionTitle(LocalizedString.text("edge_activity_title"))
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
                                            title: LocalizedString.format("edge_flow_badge", edge.activityCount),
                                            color: edge.activityCount > 0 ? .blue : .secondary
                                        )

                                        if routeSharedSessionCount > 0 {
                                            opsStatusPill(
                                                title: LocalizedString.format("edge_shared_badge", routeSharedSessionCount),
                                                color: routeSharedSessionCount > 1 ? .orange : .secondary
                                            )
                                        }

                                        if routeAnomalyCount > 0 {
                                            opsStatusPill(
                                                title: LocalizedString.format("anomalies_count_badge", routeAnomalyCount),
                                                color: routeAnomalyCount > 2 ? .red : .orange
                                            )
                                        }

                                        if edge.requiresApproval {
                                            opsStatusPill(title: LocalizedString.text("approval"), color: .yellow)
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
            return node.latestDetail ?? LocalizedString.text("node_state_detail_empty")
        case .latency:
            return node.averageDuration.map {
                LocalizedString.format("node_latency_detail_prefix", opsDurationText($0))
            } ?? LocalizedString.text("node_latency_detail_empty")
        case .failures:
            return node.status == .failed
                ? (node.latestDetail ?? LocalizedString.text("node_failure_detail_active"))
                : LocalizedString.text("node_failure_detail_clear")
        case .routing:
            return LocalizedString.format("node_routing_detail", node.incomingEdgeCount, node.outgoingEdgeCount)
        case .approvals:
            return node.status == .waitingApproval
                ? LocalizedString.text("node_approval_detail_active")
                : LocalizedString.text("node_approval_detail_clear")
        case .files:
            return LocalizedString.text("node_files_detail")
        }
    }

    private func historyAnomalyCount(for node: OpsCenterNodeSummary) -> Int {
        historyAnomaliesByNodeID[node.id]?.count ?? 0
    }

    private func historyTraceSummary(for node: OpsCenterNodeSummary) -> String? {
        if let trace = latestProjectionTraceByNodeID[node.id] {
            let statusText = trace.status.rawValue
            let summary = compactWorkflowMapPreview(trace.previewText, limit: 110)
            return LocalizedString.format("history_trace_summary_recent", statusText, summary)
        }

        if let result = latestLiveResultByNodeID[node.id] {
            let summary = compactWorkflowMapPreview(result.summaryText, limit: 110)
            return LocalizedString.format("history_trace_summary_live", result.status.rawValue, summary)
        }

        return nil
    }

    private func compactWorkflowMapPreview(_ text: String, limit: Int) -> String {
        let singleLine = text
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !singleLine.isEmpty else { return LocalizedString.text("history_trace_summary_empty") }
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
            return LocalizedString.format("route_detail_anomalies", anomalyCount)
        }
        if sessionCount > 0 {
            return LocalizedString.format("route_detail_shared_sessions", sessionCount)
        }
        if edge.activityCount > 0 {
            return LocalizedString.text("route_detail_active")
        }
        if edge.requiresApproval {
            return LocalizedString.text("route_detail_approval")
        }
        return LocalizedString.text("route_detail_clear")
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

private struct OpsCenterHistorySpotlightDigest: Identifiable {
    let id: String
    let kindTitle: String
    let title: String
    let detailText: String
    let timestamp: Date
    let color: Color
    let sessionID: String?
    let nodeID: UUID?
    let priority: Int
}

private enum OpsCenterHistoryListFilter: String, CaseIterable, Identifiable {
    case all
    case anomalies
    case traces
    case actionable

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return LocalizedString.text("history_filter_all")
        case .anomalies:
            return LocalizedString.text("history_filter_anomalies")
        case .traces:
            return LocalizedString.text("history_filter_traces")
        case .actionable:
            return LocalizedString.text("history_filter_actionable")
        }
    }
}

private enum OpsCenterHistoryFocus: String, CaseIterable, Identifiable {
    case all
    case hotspots
    case current

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return LocalizedString.text("ops_all_signals")
        case .hotspots:
            return LocalizedString.text("history_focus_hotspots")
        case .current:
            return LocalizedString.text("history_focus_current")
        }
    }
}

private enum OpsCenterHistorySort: String, CaseIterable, Identifiable {
    case newest
    case severity
    case runtimeCost

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newest:
            return LocalizedString.text("ops_newest_first")
        case .severity:
            return LocalizedString.text("ops_severity_first")
        case .runtimeCost:
            return LocalizedString.text("ops_runtime_cost")
        }
    }
}

private struct OpsCenterRoutePressureDigest: Identifiable {
    let id: String
    let title: String
    let valueText: String
    let detailText: String
    let color: Color
}

private struct OpsCenterRouteTimelineDigest: Identifiable {
    let id: String
    let kindTitle: String
    let title: String
    let detailText: String
    let timestamp: Date
    let color: Color
    let sessionID: String?
}

private struct OpsCenterThreadSummary: Identifiable {
    let threadID: String
    let workflowID: UUID?
    let workflowName: String
    let status: String
    let entryAgentName: String?
    let participantNames: [String]
    let messageCount: Int
    let taskCount: Int
    let pendingApprovalCount: Int
    let blockedTaskCount: Int
    let activeTaskCount: Int
    let completedTaskCount: Int
    let failedMessageCount: Int
    let startedAt: Date?
    let lastUpdatedAt: Date?
    let relatedSession: OpsCenterSessionSummary?
    let hotspotScore: Int

    var id: String { threadID }
}

private struct OpsCenterThreadClusterDigest: Identifiable {
    let key: String
    let title: String
    let subtitleText: String
    let detailText: String
    let threadCount: Int
    let hotspotThreadCount: Int
    let approvalPressure: Int
    let blockedThreadCount: Int
    let runtimeLinkedThreadCount: Int
    let totalHotspotScore: Int
    let latestAt: Date?
    let leadThreadID: String

    var id: String { key }
}

private struct OpsCenterThreadPressureDigest: Identifiable {
    let key: String
    let mode: OpsCenterThreadPressureMode
    let title: String
    let detailText: String
    let threadCount: Int
    let hotspotThreadCount: Int
    let approvalPressure: Int
    let blockedThreadCount: Int
    let runtimeFailureCount: Int
    let runtimeBacklogCount: Int
    let totalHotspotScore: Int
    let latestAt: Date?
    let leadThreadID: String

    var id: String { key }
}

private struct OpsCenterThreadSessionDigest: Identifiable {
    let key: String
    let title: String
    let detailText: String
    let threadCount: Int
    let hotspotThreadCount: Int
    let approvalPressure: Int
    let queuedDispatchCount: Int
    let inflightDispatchCount: Int
    let failedDispatchCount: Int
    let latestAt: Date?
    let leadThreadID: String
    let sessionID: String?

    var id: String { key }
}

private struct OpsCenterThreadPressureTimelineDigest: Identifiable {
    let key: String
    let title: String
    let detailText: String
    let threadCount: Int
    let hotspotThreadCount: Int
    let approvalPressure: Int
    let blockedThreadCount: Int
    let runtimeLinkedThreadCount: Int
    let latestAt: Date?
    let leadThreadID: String

    var id: String { key }
}

private struct OpsCenterToolHotspotDigest: Identifiable {
    let toolIdentifier: String
    let failureCount: Int
    let timeoutCount: Int
    let latestAt: Date
    let latestDetailText: String
    let status: OpsHealthStatus

    var id: String { toolIdentifier }
}

private struct OpsCenterSignalFrontlineDigest: Identifiable {
    let id: String
    let kind: OpsCenterSignalKind
    let title: String
    let subtitleText: String
    let detailText: String
    let metricText: String
    let timestamp: Date?
    let status: OpsHealthStatus
    let priorityScore: Int
    let actionTitle: String
    let action: () -> Void
    let linkedSessionID: String?
    let linkedThreadID: String?
    let linkedNodeID: UUID?
}

private enum OpsThreadRowEmphasis {
    case standard
    case hotspot
}

private struct OpsCenterHistoryDashboardView: View {
    @EnvironmentObject var appState: AppState
    let workflow: Workflow?
    let projections: OpsCenterProjectionBundle?
    let onSelectSession: (String) -> Void
    let onSelectNode: (UUID) -> Void
    let onSelectThread: (String) -> Void
    let onSelectCron: (String) -> Void
    let onSelectTool: (String) -> Void
    let onSelectArchiveProjection: () -> Void

    @State private var searchText = ""
    @State private var selectedFilter: OpsCenterHistoryListFilter = .all
    @State private var selectedFocus: OpsCenterHistoryFocus = .all
    @State private var selectedSort: OpsCenterHistorySort = .newest

    private var snapshot: OpsAnalyticsSnapshot {
        appState.opsAnalytics.snapshot
    }

    private var liveRunSnapshot: OpsCenterLiveRunSnapshot {
        OpsCenterSnapshotBuilder.buildLiveRunSnapshot(
            project: appState.currentProject,
            workflow: workflow,
            tasks: appState.taskManager.tasks,
            messages: appState.messageManager.messages,
            executionResults: appState.openClawService.executionResults
        )
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
                    title: LocalizedString.text("history_execution_reliability_title"),
                    valueText: "\(successRate)%",
                    detailText: LocalizedString.format("history_execution_reliability_detail", overview.completedExecutionCount, overview.failedExecutionCount),
                    status: overview.failedExecutionCount > 0 ? .warning : .healthy
                )
            )
            cards.append(
                OpsCenterHistoryGoalDigest(
                    id: "projection-error-budget",
                    title: LocalizedString.text("history_error_budget_title"),
                    valueText: "\(overview.errorLogCount)",
                    detailText: LocalizedString.format("history_error_budget_detail", overview.warningLogCount),
                    status: overview.errorLogCount > 0 ? .critical : (overview.warningLogCount > 0 ? .warning : .healthy)
                )
            )
            cards.append(
                OpsCenterHistoryGoalDigest(
                    id: "projection-approvals",
                    title: LocalizedString.text("approval_pressure_label"),
                    valueText: "\(overview.pendingApprovalCount)",
                    detailText: LocalizedString.text("history_projection_approval_detail"),
                    status: overview.pendingApprovalCount > 0 ? .warning : .healthy
                )
            )
        }

        let projectedLiveRun = projections?.liveRun.map { liveRun in
            OpsCenterProjectionWorkflowLiveRunEntry(
                workflowID: workflow?.id ?? UUID(),
                workflowName: workflow?.name ?? LocalizedString.text("history_project_runtime"),
                sessionCount: liveRun.totalSessionCount,
                activeSessionCount: liveRun.activeSessionCount,
                activeNodeCount: 0,
                failedNodeCount: 0,
                waitingApprovalNodeCount: liveRun.waitingApprovalCount,
                lastUpdatedAt: liveRun.generatedAt
            )
        }

        if let liveRun = projections?.liveRunEntry(for: workflow?.id) ?? projectedLiveRun {
            cards.append(
                OpsCenterHistoryGoalDigest(
                    id: "projection-sessions",
                    title: LocalizedString.text("history_session_load_title"),
                    valueText: "\(liveRun.activeSessionCount) / \(liveRun.sessionCount)",
                    detailText: LocalizedString.text("history_session_load_detail"),
                    status: liveRun.activeSessionCount > 0 ? .warning : .neutral
                )
            )
        }

        if let workflowHealth = projections?.workflowHealthEntry(for: workflow?.id) {
            cards.append(
                OpsCenterHistoryGoalDigest(
                    id: "projection-workflow-health",
                    title: LocalizedString.text("history_workflow_hotspots_title"),
                    valueText: "\(workflowHealth.failedNodeCount)",
                    detailText: LocalizedString.format("history_workflow_hotspots_detail", workflowHealth.waitingApprovalNodeCount, workflowHealth.activeNodeCount),
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
                    title: nodeTitlesByID[entry.nodeID] ?? LocalizedString.text("history_runtime_trace_title"),
                    agentName: agentNamesByID[entry.agentID] ?? LocalizedString.text("investigation_unknown_agent"),
                    sourceLabel: entry.sessionID ?? LocalizedString.text("history_persisted_trace_title"),
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

    private var effectiveCronSummary: OpsCronReliabilitySummary? {
        snapshot.cronSummary ?? projections?.cronSummary
    }

    private var toolHotspots: [OpsCenterToolHotspotDigest] {
        let anomalyPairs: [(String, OpsAnomalyRow)] = snapshot.anomalyRows.compactMap { anomaly in
            guard let identifier = opsToolIdentifier(from: anomaly) else { return nil }
            return (identifier, anomaly)
        }
        let groupedLiveHotspots = Dictionary(grouping: anomalyPairs, by: { $0.0 })
        let liveHotspots: [OpsCenterToolHotspotDigest] = groupedLiveHotspots.compactMap { identifier, items in
            let anomalies = items.map { $0.1 }
            guard let latestAnomaly = anomalies.max(by: { $0.occurredAt < $1.occurredAt }) else {
                return nil
            }
            let timeoutCount = anomalies.filter {
                $0.statusText.lowercased().contains("timeout")
                    || $0.detailText.lowercased().contains("timeout")
            }.count
            return OpsCenterToolHotspotDigest(
                toolIdentifier: identifier,
                failureCount: anomalies.count,
                timeoutCount: timeoutCount,
                latestAt: latestAnomaly.occurredAt,
                latestDetailText: latestAnomaly.detailText,
                status: anomalies.contains(where: { $0.status == .critical }) ? .critical : .warning
            )
        }

        let projectedHotspots: [OpsCenterToolHotspotDigest] = projections?.toolEntries().compactMap { entry in
            let anomalies = entry.anomalies.map { $0.anomalyRow() }
            let spans = entry.spans.map { $0.spanRow() }
            let latestAt = (anomalies.map(\.occurredAt) + spans.map(\.startedAt)).max()
            let latestDetailText = anomalies.first?.detailText ?? spans.first?.summaryText
            let timeoutCount = anomalies.filter {
                $0.statusText.lowercased().contains("timeout")
                    || $0.detailText.lowercased().contains("timeout")
            }.count
            let failureCount = max(anomalies.count, spans.filter { $0.statusText.lowercased() != "ok" }.count)
            guard let latestAt, failureCount > 0 || timeoutCount > 0 else { return nil }

            return OpsCenterToolHotspotDigest(
                toolIdentifier: entry.toolIdentifier,
                failureCount: failureCount,
                timeoutCount: timeoutCount,
                latestAt: latestAt,
                latestDetailText: latestDetailText ?? "Persisted tool posture is available.",
                status: anomalies.contains(where: { $0.status == .critical }) ? .critical : .warning
            )
        } ?? []

        let mergedHotspots: [OpsCenterToolHotspotDigest] = liveHotspots + projectedHotspots

        let mergedByIdentifier = mergedHotspots.reduce(into: [String: OpsCenterToolHotspotDigest]()) { partial, item in
            let key = item.toolIdentifier.lowercased()
            guard let existing = partial[key] else {
                partial[key] = item
                return
            }

            if item.failureCount > existing.failureCount
                || (item.failureCount == existing.failureCount && item.latestAt > existing.latestAt) {
                partial[key] = item
            }
        }

        return Array(mergedByIdentifier.values).sorted { lhs, rhs in
            if lhs.failureCount != rhs.failureCount {
                return lhs.failureCount > rhs.failureCount
            }
            if lhs.latestAt != rhs.latestAt {
                return lhs.latestAt > rhs.latestAt
            }
            return lhs.toolIdentifier < rhs.toolIdentifier
        }
    }

    private var recentCronRuns: [OpsCronRunRow] {
        let liveRuns = snapshot.cronRuns
        let projectedRuns = projections?.recentCronRuns() ?? []

        return (liveRuns + projectedRuns).reduce(into: [String: OpsCronRunRow]()) { partial, item in
            let key = item.id
            guard let existing = partial[key] else {
                partial[key] = item
                return
            }
            if item.runAt > existing.runAt {
                partial[key] = item
            }
        }
        .values
        .sorted { lhs, rhs in
            if lhs.runAt != rhs.runAt {
                return lhs.runAt > rhs.runAt
            }
            return lhs.id > rhs.id
        }
    }

    private var archiveProjectionInvestigation: OpsCenterArchiveProjectionInvestigation? {
        OpsCenterSnapshotBuilder.buildArchiveProjectionInvestigation(
            project: appState.currentProject,
            workflow: workflow,
            projections: projections
        )
    }

    private var workflowHotspotNodeIDs: Set<UUID> {
        Set(
            liveRunSnapshot.nodeSummaries
                .filter { node in
                    switch node.status {
                    case .queued, .inflight, .waitingApproval, .failed:
                        return true
                    case .idle, .completed:
                        return false
                    }
                }
                .map(\.id)
        )
    }

    private var workflowHotspotSessionIDs: Set<String> {
        Set(liveRunSnapshot.sessionSummaries.filter(opsSessionIsHotspot).map(\.sessionID))
    }

    private var hasCurrentFocusSignals: Bool {
        !workflowHotspotNodeIDs.isEmpty || !workflowHotspotSessionIDs.isEmpty
    }

    private var filteredAnomalies: [OpsCenterHistoryAnomalyDigest] {
        effectiveAnomalies.filter { anomaly in
            let filterMatch = matchesHistoryFilterForAnomaly || (selectedFilter == .actionable && isActionable(anomaly))
            return filterMatch
                && matchesHistorySearch(anomaly: anomaly)
                && matchesHistoryFocus(anomaly: anomaly)
        }
        .sorted(by: sortAnomalies)
    }

    private var filteredTraces: [OpsCenterHistoryTraceDigest] {
        effectiveTraces.filter { trace in
            let filterMatch = matchesHistoryFilterForTrace || (selectedFilter == .actionable && isActionable(trace))
            return filterMatch
                && matchesHistorySearch(trace: trace)
                && matchesHistoryFocus(trace: trace)
        }
        .sorted(by: sortTraces)
    }

    private var matchesHistoryFilterForAnomaly: Bool {
        selectedFilter == .all || selectedFilter == .anomalies
    }

    private var matchesHistoryFilterForTrace: Bool {
        selectedFilter == .all || selectedFilter == .traces
    }

    private var currentHotspotItems: [OpsCenterHistorySpotlightDigest] {
        let anomalyItems = effectiveAnomalies
            .filter(isHistoryHotspot)
            .map { anomaly in
                OpsCenterHistorySpotlightDigest(
                    id: "anomaly-\(anomaly.id)",
                    kindTitle: LocalizedString.text("history_anomaly_kind"),
                    title: anomaly.title,
                    detailText: "\(anomaly.sourceLabel) • \(anomaly.detailText)",
                    timestamp: anomaly.timestamp,
                    color: historyColor(for: anomaly.status),
                    sessionID: anomaly.sessionID,
                    nodeID: anomaly.nodeID,
                    priority: historySpotlightPriority(nodeID: anomaly.nodeID, sessionID: anomaly.sessionID, actionable: isActionable(anomaly))
                )
            }

        let traceItems = effectiveTraces
            .filter(isHistoryHotspot)
            .map { trace in
                OpsCenterHistorySpotlightDigest(
                    id: "trace-\(trace.id)",
                    kindTitle: LocalizedString.text("history_trace_kind"),
                    title: trace.title,
                    detailText: "\(trace.agentName) • \(trace.statusText) • \(trace.previewText)",
                    timestamp: trace.timestamp,
                    color: historyStatusColor(trace.statusText),
                    sessionID: trace.sessionID,
                    nodeID: trace.nodeID,
                    priority: historySpotlightPriority(nodeID: trace.nodeID, sessionID: trace.sessionID, actionable: isActionable(trace))
                )
            }

        return (anomalyItems + traceItems).sorted { lhs, rhs in
            if lhs.priority != rhs.priority {
                return lhs.priority < rhs.priority
            }
            if lhs.timestamp != rhs.timestamp {
                return lhs.timestamp > rhs.timestamp
            }
            return lhs.id > rhs.id
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                sectionTitle(LocalizedString.text("history_panel_title"))
                Text(LocalizedString.text("history_panel_desc"))
                    .font(.caption)
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center, spacing: 12) {
                        TextField(LocalizedString.text("history_search_placeholder"), text: $searchText)
                            .textFieldStyle(.roundedBorder)

                        Picker(LocalizedString.text("history_signal_label"), selection: $selectedFilter) {
                            ForEach(OpsCenterHistoryListFilter.allCases) { filter in
                                Text(filter.title).tag(filter)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 320)
                    }

                    HStack(alignment: .center, spacing: 12) {
                        Picker(LocalizedString.text("ops_focus_label"), selection: $selectedFocus) {
                            ForEach(OpsCenterHistoryFocus.allCases) { focus in
                                Text(focus.title).tag(focus)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 300)

                        Picker(LocalizedString.text("ops_sort_label"), selection: $selectedSort) {
                            ForEach(OpsCenterHistorySort.allCases) { sort in
                                Text(sort.title).tag(sort)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 170)

                        Spacer()

                        Text(LocalizedString.format("history_visible_summary", filteredAnomalies.count, filteredTraces.count))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 14)], spacing: 14) {
                    opsMetricCard(title: LocalizedString.text("history_goal_cards_title"), value: "\(effectiveGoalCards.count)", detail: LocalizedString.text("history_goal_cards_detail"), color: .blue)
                    opsMetricCard(title: LocalizedString.text("history_trend_series_title"), value: "\(snapshot.historicalSeries.count)", detail: LocalizedString.text("history_trend_series_detail"), color: .green)
                    opsMetricCard(title: LocalizedString.text("history_current_hotspots_title"), value: "\(currentHotspotItems.count)", detail: LocalizedString.text("history_current_hotspots_detail"), color: currentHotspotItems.isEmpty ? .green : .orange)
                    opsMetricCard(title: LocalizedString.text("history_hot_nodes_title"), value: "\(workflowHotspotNodeIDs.count)", detail: LocalizedString.text("history_hot_nodes_detail"), color: workflowHotspotNodeIDs.isEmpty ? .green : .red)
                    opsMetricCard(title: LocalizedString.text("history_cron_runs_title"), value: "\(recentCronRuns.count)", detail: effectiveCronSummary.map { LocalizedString.format("history_cron_runs_summary", $0.successfulRuns, $0.failedRuns) } ?? LocalizedString.text("history_cron_runs_empty"), color: (effectiveCronSummary?.failedRuns ?? 0) > 0 ? .orange : .green)
                    opsMetricCard(title: LocalizedString.text("history_tool_hotspots_title"), value: "\(toolHotspots.count)", detail: toolHotspots.first.map { LocalizedString.format("history_tool_hotspots_summary", $0.toolIdentifier, $0.failureCount) } ?? LocalizedString.text("history_tool_hotspots_empty"), color: toolHotspots.isEmpty ? .green : .orange)
                    opsMetricCard(title: LocalizedString.text("history_projection_docs_title"), value: "\(archiveProjectionInvestigation?.documentDigests.filter { $0.generatedAt != nil }.count ?? 0)", detail: archiveProjectionInvestigation?.freshestGeneratedAt.map { LocalizedString.format("history_projection_docs_summary", $0.formatted(date: .abbreviated, time: .shortened)) } ?? LocalizedString.text("history_projection_docs_empty"), color: archiveProjectionInvestigation == nil ? .orange : .blue)
                    opsMetricCard(title: LocalizedString.text("history_filter_anomalies"), value: "\(filteredAnomalies.count)", detail: LocalizedString.text("history_anomalies_detail"), color: filteredAnomalies.isEmpty ? .green : .orange)
                    opsMetricCard(title: LocalizedString.text("history_trace_rows_title"), value: "\(filteredTraces.count)", detail: LocalizedString.text("history_trace_rows_detail"), color: .purple)
                    opsMetricCard(title: LocalizedString.text("failures_label"), value: "\(projections?.overview?.failedExecutionCount ?? snapshot.failedExecutions)", detail: LocalizedString.text("history_failures_detail"), color: (projections?.overview?.failedExecutionCount ?? snapshot.failedExecutions) > 0 ? .red : .green)
                    opsMetricCard(title: LocalizedString.text("history_avg_duration_title"), value: filteredAverageTraceDuration.map(opsDurationText) ?? LocalizedString.text("na"), detail: LocalizedString.text("history_avg_duration_detail"), color: .teal)
                }

                if let projectionSummaryText {
                    Text(projectionSummaryText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if hasCurrentFocusSignals {
                    Text(LocalizedString.format("history_current_focus_summary", workflowHotspotNodeIDs.count, workflowHotspotSessionIDs.count))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                sectionTitle(LocalizedString.text("history_cron_reliability_title"))
                if recentCronRuns.isEmpty && effectiveCronSummary == nil {
                    opsInlineEmptyState(LocalizedString.text("history_cron_reliability_empty"))
                } else {
                    if let cronSummary = effectiveCronSummary {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(LocalizedString.format("history_success_rate_summary", Int(cronSummary.successRate.rounded())))
                                    .font(.subheadline.weight(.semibold))
                                Text(LocalizedString.format("cron_ok_failed_summary", cronSummary.successfulRuns, cronSummary.failedRuns))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                if let latestRunAt = cronSummary.latestRunAt {
                                    Text(LocalizedString.format("latest_run_at", latestRunAt.formatted(date: .abbreviated, time: .shortened)))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            if let leadCronName = recentCronRuns.first?.cronName {
                                historyActionButton(title: LocalizedString.text("open_cron")) {
                                    onSelectCron(leadCronName)
                                }
                            }
                        }
                        .padding(10)
                        .background(Color(.controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    VStack(spacing: 8) {
                        ForEach(Array(recentCronRuns.prefix(6))) { run in
                            HStack(alignment: .top, spacing: 12) {
                                opsStatusPill(title: run.statusText, color: opsHistoryStatusColor(run.statusText))
                                    .frame(width: 96, alignment: .leading)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(run.cronName)
                                        .font(.subheadline.weight(.medium))
                                    Text(run.summaryText)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                    Text([run.jobID, run.sourcePath].compactMap { $0 }.joined(separator: " • "))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 6) {
                                    historyActionButton(title: LocalizedString.text("open_cron")) {
                                        onSelectCron(run.cronName)
                                    }
                                    if let duration = run.duration {
                                        Text(opsDurationText(duration))
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    Text(run.runAt.formatted(date: .abbreviated, time: .shortened))
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

                sectionTitle(LocalizedString.text("history_tool_hotspots_title"))
                if toolHotspots.isEmpty {
                    opsInlineEmptyState(LocalizedString.text("history_tool_hotspots_list_empty"))
                } else {
                    VStack(spacing: 8) {
                        ForEach(Array(toolHotspots.prefix(6))) { tool in
                            HStack(alignment: .top, spacing: 12) {
                                opsStatusPill(title: tool.failureCount > 1 ? LocalizedString.text("tool_hotspot_badge") : LocalizedString.text("tool_watch_badge"), color: historyColor(for: tool.status))
                                    .frame(width: 96, alignment: .leading)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(tool.toolIdentifier)
                                        .font(.subheadline.weight(.medium))
                                    Text(tool.latestDetailText)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(3)
                                    Text(LocalizedString.format("failures_timeouts_summary", tool.failureCount, tool.timeoutCount))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 6) {
                                    historyActionButton(title: LocalizedString.text("open_tool")) {
                                        onSelectTool(tool.toolIdentifier)
                                    }
                                    Text(tool.latestAt.formatted(date: .abbreviated, time: .shortened))
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

                sectionTitle(LocalizedString.text("history_projection_health_title"))
                if let archiveProjectionInvestigation {
                    VStack(spacing: 8) {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(archiveProjectionInvestigation.scopeTitle)
                                    .font(.subheadline.weight(.semibold))
                                Text(LocalizedString.format("projection_scope_counts", archiveProjectionInvestigation.sessionCount, archiveProjectionInvestigation.nodeCount, archiveProjectionInvestigation.traceCount, archiveProjectionInvestigation.anomalyCount))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(archiveProjectionInvestigation.liveRunSummary ?? archiveProjectionInvestigation.workflowHealthSummary ?? LocalizedString.text("projection_scope_summary_missing"))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(3)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 6) {
                                historyActionButton(title: LocalizedString.text("open_projection")) {
                                    onSelectArchiveProjection()
                                }
                                if let freshestGeneratedAt = archiveProjectionInvestigation.freshestGeneratedAt {
                                    Text(freshestGeneratedAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(10)
                        .background(Color(.controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                        ForEach(archiveProjectionInvestigation.documentDigests) { document in
                            HStack(alignment: .top, spacing: 12) {
                                opsStatusPill(title: document.title, color: historyColor(for: document.status))
                                    .frame(width: 110, alignment: .leading)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(document.valueText)
                                        .font(.subheadline.weight(.medium))
                                    Text(document.detailText)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(3)
                                }

                                Spacer()

                                if let generatedAt = document.generatedAt {
                                    Text(generatedAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(10)
                            .background(Color(.controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                } else {
                    opsInlineEmptyState(LocalizedString.text("projection_bundle_missing"))
                }

                sectionTitle(LocalizedString.text("history_current_hotspots_title"))
                if currentHotspotItems.isEmpty {
                    opsInlineEmptyState(LocalizedString.text("history_current_hotspots_empty"))
                } else {
                    VStack(spacing: 8) {
                        ForEach(Array(currentHotspotItems.prefix(6))) { item in
                            HStack(alignment: .top, spacing: 12) {
                                opsStatusPill(title: item.kindTitle, color: item.color)
                                    .frame(width: 84, alignment: .leading)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.title)
                                        .font(.subheadline.weight(.medium))
                                    Text(item.detailText)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(3)
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 6) {
                                    historyActionButtons(sessionID: item.sessionID, nodeID: item.nodeID)
                                    Text(item.timestamp.formatted(date: .abbreviated, time: .shortened))
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

                if effectiveGoalCards.isEmpty {
                    opsEmptyState(
                        title: LocalizedString.text("history_snapshot_empty_title"),
                        detail: LocalizedString.text("history_snapshot_empty_detail")
                    )
                } else {
                    sectionTitle(LocalizedString.text("history_runtime_snapshot_title"))
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

                sectionTitle(LocalizedString.text("history_trend_signals_title"))
                if snapshot.historicalSeries.isEmpty {
                    if snapshot.dailyActivity.isEmpty {
                        opsInlineEmptyState(LocalizedString.text("history_trend_signals_empty"))
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

                                    Text(LocalizedString.format("history_daily_activity_summary", point.completedCount, point.failedCount, point.errorCount))
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
                                guard let latest, let previous else { return LocalizedString.text("history_no_prior_point") }
                                let delta = latest - previous
                                return delta == 0
                                    ? LocalizedString.text("history_delta_stable")
                                    : LocalizedString.format("history_delta_value", delta > 0 ? "+" : "", Int(delta.rounded()))
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
                                    Text(latest.map(series.metric.formattedValue) ?? LocalizedString.text("na"))
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

                sectionTitle(LocalizedString.text("history_recent_anomalies_title"))
                if filteredAnomalies.isEmpty {
                    opsInlineEmptyState(LocalizedString.text("history_recent_anomalies_empty"))
                } else {
                    VStack(spacing: 8) {
                        ForEach(filteredAnomalies.prefix(8)) { anomaly in
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

                sectionTitle(LocalizedString.text("history_recent_traces_title"))
                if filteredTraces.isEmpty {
                    opsInlineEmptyState(LocalizedString.text("history_recent_traces_empty"))
                } else {
                    VStack(spacing: 8) {
                        ForEach(filteredTraces.prefix(10)) { trace in
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
                                        Text(LocalizedString.format("history_repair_badge", trace.protocolRepairCount))
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

    private var filteredAverageTraceDuration: TimeInterval? {
        let durations = filteredTraces.compactMap(\.duration)
        guard !durations.isEmpty else { return nil }
        return durations.reduce(0, +) / Double(durations.count)
    }

    private func matchesHistorySearch(anomaly: OpsCenterHistoryAnomalyDigest) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return true }

        let haystack = [
            anomaly.title,
            anomaly.sourceLabel,
            anomaly.detailText,
            anomaly.sessionID ?? "",
            anomaly.nodeID?.uuidString ?? ""
        ]
        .joined(separator: " ")
        .lowercased()

        return haystack.contains(query)
    }

    private func matchesHistorySearch(trace: OpsCenterHistoryTraceDigest) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return true }

        let haystack = [
            trace.title,
            trace.agentName,
            trace.sourceLabel,
            trace.statusText,
            trace.previewText,
            trace.sessionID ?? "",
            trace.nodeID?.uuidString ?? ""
        ]
        .joined(separator: " ")
        .lowercased()

        return haystack.contains(query)
    }

    private func isActionable(_ anomaly: OpsCenterHistoryAnomalyDigest) -> Bool {
        anomaly.status == .critical || anomaly.status == .warning
    }

    private func isActionable(_ trace: OpsCenterHistoryTraceDigest) -> Bool {
        let status = trace.statusText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return status != "completed" || trace.protocolRepairCount > 0
    }

    private func isHistoryHotspot(_ anomaly: OpsCenterHistoryAnomalyDigest) -> Bool {
        isActionable(anomaly) || isCurrentWorkflowFocus(nodeID: anomaly.nodeID, sessionID: anomaly.sessionID)
    }

    private func isHistoryHotspot(_ trace: OpsCenterHistoryTraceDigest) -> Bool {
        isActionable(trace) || isCurrentWorkflowFocus(nodeID: trace.nodeID, sessionID: trace.sessionID)
    }

    private func isCurrentWorkflowFocus(nodeID: UUID?, sessionID: String?) -> Bool {
        if let nodeID, workflowHotspotNodeIDs.contains(nodeID) {
            return true
        }
        if let normalizedSessionID = normalizedHistorySessionID(sessionID),
           workflowHotspotSessionIDs.contains(normalizedSessionID) {
            return true
        }
        return false
    }

    private func matchesHistoryFocus(anomaly: OpsCenterHistoryAnomalyDigest) -> Bool {
        switch selectedFocus {
        case .all:
            return true
        case .hotspots:
            return isHistoryHotspot(anomaly)
        case .current:
            return hasCurrentFocusSignals
                ? isCurrentWorkflowFocus(nodeID: anomaly.nodeID, sessionID: anomaly.sessionID)
                : isHistoryHotspot(anomaly)
        }
    }

    private func matchesHistoryFocus(trace: OpsCenterHistoryTraceDigest) -> Bool {
        switch selectedFocus {
        case .all:
            return true
        case .hotspots:
            return isHistoryHotspot(trace)
        case .current:
            return hasCurrentFocusSignals
                ? isCurrentWorkflowFocus(nodeID: trace.nodeID, sessionID: trace.sessionID)
                : isHistoryHotspot(trace)
        }
    }

    private func sortAnomalies(_ lhs: OpsCenterHistoryAnomalyDigest, _ rhs: OpsCenterHistoryAnomalyDigest) -> Bool {
        let lhsCurrent = isCurrentWorkflowFocus(nodeID: lhs.nodeID, sessionID: lhs.sessionID)
        let rhsCurrent = isCurrentWorkflowFocus(nodeID: rhs.nodeID, sessionID: rhs.sessionID)

        switch selectedSort {
        case .newest:
            if lhs.timestamp != rhs.timestamp {
                return lhs.timestamp > rhs.timestamp
            }
            if lhsCurrent != rhsCurrent {
                return lhsCurrent
            }
        case .severity:
            if opsHealthStatusRank(lhs.status) != opsHealthStatusRank(rhs.status) {
                return opsHealthStatusRank(lhs.status) < opsHealthStatusRank(rhs.status)
            }
            if lhsCurrent != rhsCurrent {
                return lhsCurrent
            }
        case .runtimeCost:
            if lhsCurrent != rhsCurrent {
                return lhsCurrent
            }
            if opsHealthStatusRank(lhs.status) != opsHealthStatusRank(rhs.status) {
                return opsHealthStatusRank(lhs.status) < opsHealthStatusRank(rhs.status)
            }
        }

        if lhs.timestamp != rhs.timestamp {
            return lhs.timestamp > rhs.timestamp
        }
        return lhs.id > rhs.id
    }

    private func sortTraces(_ lhs: OpsCenterHistoryTraceDigest, _ rhs: OpsCenterHistoryTraceDigest) -> Bool {
        let lhsCurrent = isCurrentWorkflowFocus(nodeID: lhs.nodeID, sessionID: lhs.sessionID)
        let rhsCurrent = isCurrentWorkflowFocus(nodeID: rhs.nodeID, sessionID: rhs.sessionID)

        switch selectedSort {
        case .newest:
            if lhs.timestamp != rhs.timestamp {
                return lhs.timestamp > rhs.timestamp
            }
            if lhsCurrent != rhsCurrent {
                return lhsCurrent
            }
        case .severity:
            if opsTraceStatusRank(lhs.statusText) != opsTraceStatusRank(rhs.statusText) {
                return opsTraceStatusRank(lhs.statusText) < opsTraceStatusRank(rhs.statusText)
            }
            if lhs.protocolRepairCount != rhs.protocolRepairCount {
                return lhs.protocolRepairCount > rhs.protocolRepairCount
            }
            if lhsCurrent != rhsCurrent {
                return lhsCurrent
            }
        case .runtimeCost:
            if lhsCurrent != rhsCurrent {
                return lhsCurrent
            }
            if lhs.protocolRepairCount != rhs.protocolRepairCount {
                return lhs.protocolRepairCount > rhs.protocolRepairCount
            }
            let lhsDuration = lhs.duration ?? 0
            let rhsDuration = rhs.duration ?? 0
            if lhsDuration != rhsDuration {
                return lhsDuration > rhsDuration
            }
        }

        if lhs.timestamp != rhs.timestamp {
            return lhs.timestamp > rhs.timestamp
        }
        return lhs.id > rhs.id
    }

    private func historySpotlightPriority(nodeID: UUID?, sessionID: String?, actionable: Bool) -> Int {
        if isCurrentWorkflowFocus(nodeID: nodeID, sessionID: sessionID) {
            return 0
        }
        if actionable {
            return 1
        }
        return 2
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
                    historyActionButton(title: LocalizedString.text("ops_session_short")) {
                        onSelectSession(normalizedSessionID)
                    }
                    historyActionButton(title: LocalizedString.text("ops_thread_short")) {
                        onSelectThread(normalizedSessionID)
                    }
                }

                if let nodeID {
                    historyActionButton(title: LocalizedString.text("ops_node_short")) {
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
    let onSelectSession: (String) -> Void
    let onSelectNode: (UUID) -> Void
    let onSelectRoute: (UUID) -> Void
    let onSelectThread: (String) -> Void

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
                case let .thread(investigation):
                    threadInvestigationBody(investigation)
                case let .cron(investigation):
                    cronInvestigationBody(investigation)
                case let .tool(investigation):
                    toolInvestigationBody(investigation)
                case let .archiveProjection(investigation):
                    archiveProjectionInvestigationBody(investigation)
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
            opsMetricCard(title: LocalizedString.text("events"), value: "\(investigation.session.eventCount)", detail: LocalizedString.text("investigation_session_events_detail"), color: .blue)
            opsMetricCard(title: LocalizedString.text("dispatches_label"), value: "\(investigation.session.dispatchCount)", detail: LocalizedString.text("dispatches_detail"), color: .orange)
            opsMetricCard(title: LocalizedString.text("receipts_label"), value: "\(investigation.session.receiptCount)", detail: LocalizedString.text("investigation_session_receipts_detail"), color: .green)
            opsMetricCard(title: LocalizedString.text("failures_label"), value: "\(investigation.session.failedDispatchCount)", detail: investigation.session.latestFailureText ?? LocalizedString.text("investigation_no_recent_failure_text"), color: investigation.session.failedDispatchCount > 0 ? .red : .green)
            opsMetricCard(title: LocalizedString.text("investigation_workbench_messages_title"), value: "\(investigation.messages.count)", detail: LocalizedString.text("investigation_session_messages_detail"), color: .purple)
            opsMetricCard(title: LocalizedString.text("tasks"), value: "\(investigation.tasks.count)", detail: LocalizedString.text("investigation_session_tasks_detail"), color: .teal)
        }

        opsInvestigationSection(LocalizedString.text("investigation_session_entry_title"), detail: LocalizedString.text("investigation_session_entry_detail")) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(investigation.session.sessionID)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    Text(LocalizedString.text("investigation_session_thread_alignment"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                investigationActionButton(title: LocalizedString.text("open_thread")) {
                    onSelectThread(investigation.session.sessionID)
                }
            }
            .padding(10)
            .background(Color(.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }

        opsInvestigationSection(LocalizedString.text("investigation_related_nodes_title"), detail: LocalizedString.text("investigation_session_related_nodes_detail")) {
            if investigation.relatedNodes.isEmpty {
                opsInlineEmptyState(LocalizedString.text("investigation_session_related_nodes_empty"))
            } else {
                ForEach(investigation.relatedNodes) { node in
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(node.title)
                                .font(.subheadline.weight(.medium))
                            Text(node.agentName ?? LocalizedString.text("no_bound_agent"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        opsStatusPill(title: node.status.title, color: node.status.color)
                        investigationActionButton(title: LocalizedString.text("open_node")) {
                            onSelectNode(node.id)
                        }
                    }
                    .padding(10)
                    .background(Color(.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }

        opsInvestigationSection(LocalizedString.text("investigation_runtime_events_title"), detail: LocalizedString.text("investigation_session_runtime_events_detail")) {
            if investigation.events.isEmpty {
                opsInlineEmptyState(LocalizedString.text("investigation_session_runtime_events_empty"))
            } else {
                ForEach(investigation.events.prefix(10)) { event in
                    OpsCenterEventDigestCard(event: event)
                }
            }
        }

        opsInvestigationSection(LocalizedString.text("dispatches_label"), detail: LocalizedString.text("investigation_session_dispatches_detail")) {
            if investigation.dispatches.isEmpty {
                opsInlineEmptyState(LocalizedString.text("investigation_session_dispatches_empty"))
            } else {
                ForEach(investigation.dispatches.prefix(12)) { dispatch in
                    OpsCenterDispatchDigestCard(dispatch: dispatch)
                }
            }
        }

        opsInvestigationSection(LocalizedString.text("receipts_label"), detail: LocalizedString.text("investigation_session_receipts_section_detail")) {
            if investigation.receipts.isEmpty {
                opsInlineEmptyState(LocalizedString.text("investigation_session_receipts_empty"))
            } else {
                ForEach(investigation.receipts.prefix(10)) { receipt in
                    OpsCenterReceiptDigestCard(receipt: receipt)
                }
            }
        }

        opsInvestigationSection(LocalizedString.text("investigation_workbench_messages_title"), detail: LocalizedString.text("investigation_session_messages_section_detail")) {
            if investigation.messages.isEmpty {
                opsInlineEmptyState(LocalizedString.text("investigation_session_messages_empty"))
            } else {
                ForEach(investigation.messages.prefix(10)) { message in
                    OpsCenterMessageDigestCard(message: message)
                }
            }
        }

        opsInvestigationSection(LocalizedString.text("investigation_workbench_tasks_title"), detail: LocalizedString.text("investigation_session_tasks_section_detail")) {
            if investigation.tasks.isEmpty {
                opsInlineEmptyState(LocalizedString.text("investigation_session_tasks_empty"))
            } else {
                ForEach(investigation.tasks.prefix(10)) { task in
                    OpsCenterTaskDigestCard(task: task)
                }
            }
        }
    }

    @ViewBuilder
    private func threadInvestigationBody(_ investigation: OpsCenterThreadInvestigation) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
            opsMetricCard(
                title: LocalizedString.text("investigation_thread_status_title"),
                value: workbenchThreadStatusTitle(investigation.status),
                detail: investigation.entryAgentName ?? LocalizedString.text("investigation_no_entry_agent"),
                color: workbenchThreadStatusColor(investigation.status)
            )
            opsMetricCard(title: LocalizedString.text("investigation_participants_title"), value: "\(investigation.participantNames.count)", detail: LocalizedString.text("investigation_thread_participants_detail"), color: .blue)
            opsMetricCard(title: LocalizedString.text("messages"), value: "\(investigation.messages.count)", detail: LocalizedString.text("investigation_thread_messages_detail"), color: .purple)
            opsMetricCard(title: LocalizedString.text("tasks"), value: "\(investigation.tasks.count)", detail: LocalizedString.text("investigation_thread_tasks_detail"), color: .teal)
            opsMetricCard(title: LocalizedString.text("approvals_label"), value: "\(investigation.pendingApprovalCount)", detail: LocalizedString.text("investigation_thread_approvals_detail"), color: investigation.pendingApprovalCount > 0 ? .yellow : .green)
            opsMetricCard(title: LocalizedString.text("investigation_runtime_evidence_title"), value: "\(investigation.events.count + investigation.dispatches.count + investigation.receipts.count)", detail: LocalizedString.text("investigation_runtime_evidence_detail"), color: .orange)
        }

        opsInvestigationSection(LocalizedString.text("investigation_thread_posture_title"), detail: LocalizedString.text("investigation_thread_posture_detail")) {
            VStack(spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(LocalizedString.text("workflow_label"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(investigation.workflowName)
                            .font(.subheadline.weight(.medium))
                    }
                    Spacer()
                    opsStatusPill(title: workbenchThreadStatusTitle(investigation.status), color: workbenchThreadStatusColor(investigation.status))
                }
                .padding(10)
                .background(Color(.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(LocalizedString.text("investigation_session_key_title"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(investigation.sessionID)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    }
                    Spacer()
                    investigationActionButton(title: LocalizedString.text("open_session")) {
                        onSelectSession(investigation.sessionID)
                    }
                }
                .padding(10)
                .background(Color(.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(LocalizedString.text("investigation_entry_agent_title"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(investigation.entryAgentName ?? LocalizedString.text("investigation_no_entry_agent"))
                            .font(.subheadline.weight(.medium))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        if let startedAt = investigation.startedAt {
                            Text(LocalizedString.format("started_at_label", startedAt.formatted(date: .abbreviated, time: .shortened)))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        if let lastUpdatedAt = investigation.lastUpdatedAt {
                            Text(LocalizedString.format("updated_time", lastUpdatedAt.formatted(date: .abbreviated, time: .shortened)))
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

        opsInvestigationSection(LocalizedString.text("investigation_participants_title"), detail: LocalizedString.text("investigation_thread_participants_section_detail")) {
            if investigation.participantNames.isEmpty {
                opsInlineEmptyState(LocalizedString.text("investigation_thread_participants_empty"))
            } else {
                ForEach(investigation.participantNames, id: \.self) { participantName in
                    HStack {
                        Text(participantName)
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        opsStatusPill(title: LocalizedString.text("investigation_participant_badge"), color: .blue)
                    }
                    .padding(10)
                    .background(Color(.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }

        opsInvestigationSection(LocalizedString.text("investigation_related_session_title"), detail: LocalizedString.text("investigation_related_session_detail")) {
            if let session = investigation.relatedSession {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(session.sessionID)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        Text(LocalizedString.format("session_counts_summary", session.eventCount, session.dispatchCount, session.receiptCount))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    opsStatusPill(
                        title: session.failedDispatchCount > 0 ? LocalizedString.text("failure_signal_badge") : (session.isPrimaryRuntimeSession ? LocalizedString.text("primary_badge") : LocalizedString.text("observed_badge")),
                        color: session.failedDispatchCount > 0 ? .red : (session.isPrimaryRuntimeSession ? .teal : .blue)
                    )
                    investigationActionButton(title: LocalizedString.text("open_session")) {
                        onSelectSession(session.sessionID)
                    }
                }
                .padding(10)
                .background(Color(.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                opsInlineEmptyState(LocalizedString.text("investigation_related_session_empty"))
            }
        }

        opsInvestigationSection(LocalizedString.text("investigation_related_nodes_title"), detail: LocalizedString.text("investigation_thread_related_nodes_detail")) {
            if investigation.relatedNodes.isEmpty {
                opsInlineEmptyState(LocalizedString.text("investigation_thread_related_nodes_empty"))
            } else {
                ForEach(investigation.relatedNodes) { node in
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(node.title)
                                .font(.subheadline.weight(.medium))
                            Text(node.agentName ?? LocalizedString.text("no_bound_agent"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        opsStatusPill(title: node.status.title, color: node.status.color)
                        investigationActionButton(title: LocalizedString.text("open_node")) {
                            onSelectNode(node.id)
                        }
                    }
                    .padding(10)
                    .background(Color(.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }

        opsInvestigationSection(LocalizedString.text("investigation_workbench_messages_title"), detail: LocalizedString.text("investigation_thread_messages_section_detail")) {
            if investigation.messages.isEmpty {
                opsInlineEmptyState(LocalizedString.text("investigation_thread_messages_empty"))
            } else {
                ForEach(investigation.messages.prefix(12)) { message in
                    OpsCenterMessageDigestCard(message: message)
                }
            }
        }

        opsInvestigationSection(LocalizedString.text("investigation_workbench_tasks_title"), detail: LocalizedString.text("investigation_thread_tasks_section_detail")) {
            if investigation.tasks.isEmpty {
                opsInlineEmptyState(LocalizedString.text("investigation_thread_tasks_empty"))
            } else {
                ForEach(investigation.tasks.prefix(12)) { task in
                    OpsCenterTaskDigestCard(task: task)
                }
            }
        }

        opsInvestigationSection(LocalizedString.text("investigation_runtime_dispatches_title"), detail: LocalizedString.text("investigation_runtime_dispatches_detail")) {
            if investigation.dispatches.isEmpty {
                opsInlineEmptyState(LocalizedString.text("investigation_runtime_dispatches_empty"))
            } else {
                ForEach(investigation.dispatches.prefix(12)) { dispatch in
                    OpsCenterDispatchDigestCard(dispatch: dispatch)
                }
            }
        }

        opsInvestigationSection(LocalizedString.text("investigation_execution_receipts_title"), detail: LocalizedString.text("investigation_execution_receipts_detail")) {
            if investigation.receipts.isEmpty {
                opsInlineEmptyState(LocalizedString.text("investigation_execution_receipts_empty"))
            } else {
                ForEach(investigation.receipts.prefix(10)) { receipt in
                    OpsCenterReceiptDigestCard(receipt: receipt)
                }
            }
        }

        opsInvestigationSection(LocalizedString.text("investigation_runtime_events_title"), detail: LocalizedString.text("investigation_thread_runtime_events_detail")) {
            if investigation.events.isEmpty {
                opsInlineEmptyState(LocalizedString.text("investigation_thread_runtime_events_empty"))
            } else {
                ForEach(investigation.events.prefix(10)) { event in
                    OpsCenterEventDigestCard(event: event)
                }
            }
        }
    }

    @ViewBuilder
    private func cronInvestigationBody(_ investigation: OpsCenterCronInvestigation) -> some View {
        let successRateText = investigation.summary.map { "\(Int($0.successRate.rounded()))%" } ?? LocalizedString.text("na")
        let latestRun = investigation.runs.max(by: { $0.runAt < $1.runAt })

        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
            opsMetricCard(title: LocalizedString.text("investigation_success_rate_title"), value: successRateText, detail: investigation.summary.map { LocalizedString.format("cron_ok_failed_summary", $0.successfulRuns, $0.failedRuns) } ?? LocalizedString.text("investigation_cron_summary_empty"), color: (investigation.summary?.failedRuns ?? 0) > 0 ? .orange : .green)
            opsMetricCard(title: LocalizedString.text("investigation_recent_runs_title"), value: "\(investigation.runs.count)", detail: latestRun.map { LocalizedString.format("latest_run_at", $0.runAt.formatted(date: .abbreviated, time: .shortened)) } ?? LocalizedString.text("investigation_recent_cron_runs_empty"), color: .blue)
            opsMetricCard(title: LocalizedString.text("history_filter_anomalies"), value: "\(investigation.anomalies.count)", detail: LocalizedString.text("investigation_cron_anomalies_detail"), color: investigation.anomalies.isEmpty ? .green : .red)
            opsMetricCard(title: LocalizedString.text("history_trend_series_title"), value: "\(investigation.historySeries.count)", detail: LocalizedString.text("investigation_cron_trend_series_detail"), color: .teal)
        }

        opsInvestigationSection(LocalizedString.text("investigation_cron_posture_title"), detail: LocalizedString.text("investigation_cron_posture_detail")) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(investigation.cronName)
                        .font(.subheadline.weight(.semibold))
                    Text(investigation.summary.map { LocalizedString.format("investigation_cron_posture_summary", $0.successfulRuns, $0.failedRuns) } ?? LocalizedString.text("investigation_cron_posture_empty"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if let latestRunAt = investigation.summary?.latestRunAt {
                    Text(latestRunAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(10)
            .background(Color(.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }

        opsInvestigationSection(LocalizedString.text("history_trend_signals_title"), detail: LocalizedString.text("investigation_cron_trend_signals_detail")) {
            if investigation.historySeries.isEmpty {
                opsInlineEmptyState(LocalizedString.text("investigation_cron_trend_signals_empty"))
            } else {
                ForEach(investigation.historySeries) { series in
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
                            Text(series.latestPoint.map { series.metric.formattedValue($0.value) } ?? LocalizedString.text("na"))
                                .font(.subheadline.weight(.semibold))
                            Text(series.latestPoint.map { $0.date.formatted(date: .abbreviated, time: .shortened) } ?? LocalizedString.text("investigation_no_points"))
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

        opsInvestigationSection(LocalizedString.text("investigation_recent_runs_title"), detail: LocalizedString.text("investigation_recent_runs_detail")) {
            if investigation.runs.isEmpty {
                opsInlineEmptyState(LocalizedString.text("investigation_recent_runs_empty"))
            } else {
                ForEach(investigation.runs.prefix(12)) { run in
                    HStack(alignment: .top, spacing: 12) {
                        opsStatusPill(title: run.statusText, color: opsHistoryStatusColor(run.statusText))
                            .frame(width: 92, alignment: .leading)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(run.summaryText)
                                .font(.caption.weight(.medium))
                            Text([run.jobID, run.deliveryStatus, run.sourcePath].compactMap { $0 }.joined(separator: " • "))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 4) {
                            if let duration = run.duration {
                                Text(opsDurationText(duration))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Text(run.runAt.formatted(date: .abbreviated, time: .shortened))
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

        opsInvestigationSection(LocalizedString.text("history_filter_anomalies"), detail: LocalizedString.text("investigation_cron_anomalies_section_detail")) {
            if investigation.anomalies.isEmpty {
                opsInlineEmptyState(LocalizedString.text("investigation_cron_anomalies_empty"))
            } else {
                ForEach(investigation.anomalies.prefix(12)) { anomaly in
                    opsAnomalyRow(anomaly)
                }
            }
        }
    }

    @ViewBuilder
    private func toolInvestigationBody(_ investigation: OpsCenterToolInvestigation) -> some View {
        let latestSpan = investigation.spans.max(by: { $0.startedAt < $1.startedAt })
        let averageDuration: TimeInterval? = {
            let durations = investigation.spans.compactMap(\.duration)
            guard !durations.isEmpty else { return nil }
            return durations.reduce(0, +) / Double(durations.count)
        }()
        let failingSpanCount = investigation.spans.filter { $0.statusText.lowercased() != "completed" }.count

        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
            opsMetricCard(title: LocalizedString.text("tool_category"), value: investigation.toolIdentifier, detail: LocalizedString.text("investigation_tool_identifier_detail"), color: .blue)
            opsMetricCard(title: LocalizedString.text("investigation_recent_spans_title"), value: "\(investigation.spans.count)", detail: latestSpan.map { LocalizedString.format("investigation_latest_span_at", $0.startedAt.formatted(date: .abbreviated, time: .shortened)) } ?? LocalizedString.text("investigation_recent_tool_spans_empty"), color: .green)
            opsMetricCard(title: LocalizedString.text("failures_label"), value: "\(investigation.anomalies.count)", detail: LocalizedString.format("investigation_tool_failures_detail", failingSpanCount), color: investigation.anomalies.isEmpty ? .green : .red)
            opsMetricCard(title: LocalizedString.text("history_avg_duration_title"), value: averageDuration.map(opsDurationText) ?? LocalizedString.text("na"), detail: LocalizedString.text("investigation_tool_avg_duration_detail"), color: .teal)
        }

        opsInvestigationSection(LocalizedString.text("investigation_tool_posture_title"), detail: LocalizedString.text("investigation_tool_posture_detail")) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(investigation.toolIdentifier)
                        .font(.subheadline.weight(.semibold))
                    Text(LocalizedString.format("investigation_tool_posture_summary", investigation.spans.count, investigation.anomalies.count))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if let latestSpan {
                    Text(latestSpan.startedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(10)
            .background(Color(.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }

        opsInvestigationSection(LocalizedString.text("history_trend_signals_title"), detail: LocalizedString.text("investigation_tool_trend_signals_detail")) {
            if investigation.historySeries.isEmpty {
                opsInlineEmptyState(LocalizedString.text("investigation_tool_trend_signals_empty"))
            } else {
                ForEach(investigation.historySeries) { series in
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
                            Text(series.latestPoint.map { series.metric.formattedValue($0.value) } ?? LocalizedString.text("na"))
                                .font(.subheadline.weight(.semibold))
                            Text(series.latestPoint.map { $0.date.formatted(date: .abbreviated, time: .shortened) } ?? LocalizedString.text("investigation_no_points"))
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

        opsInvestigationSection(LocalizedString.text("investigation_recent_tool_spans_title"), detail: LocalizedString.text("investigation_recent_tool_spans_detail")) {
            if investigation.spans.isEmpty {
                opsInlineEmptyState(LocalizedString.text("investigation_recent_tool_spans_empty"))
            } else {
                ForEach(investigation.spans.prefix(12)) { span in
                    HStack(alignment: .top, spacing: 12) {
                        opsStatusPill(title: span.statusText, color: opsHistoryStatusColor(span.statusText))
                            .frame(width: 92, alignment: .leading)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(span.title)
                                .font(.subheadline.weight(.medium))
                            Text("\(span.agentName) • \(span.service)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(span.summaryText)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(3)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 4) {
                            if let duration = span.duration {
                                Text(opsDurationText(duration))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Text(span.startedAt.formatted(date: .abbreviated, time: .shortened))
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

        opsInvestigationSection(LocalizedString.text("history_filter_anomalies"), detail: LocalizedString.text("investigation_tool_anomalies_detail")) {
            if investigation.anomalies.isEmpty {
                opsInlineEmptyState(LocalizedString.text("investigation_tool_anomalies_empty"))
            } else {
                ForEach(investigation.anomalies.prefix(12)) { anomaly in
                    opsAnomalyRow(anomaly)
                }
            }
        }
    }

    @ViewBuilder
    private func archiveProjectionInvestigationBody(_ investigation: OpsCenterArchiveProjectionInvestigation) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
            opsMetricCard(title: LocalizedString.text("investigation_scope_title"), value: investigation.scopeTitle, detail: investigation.projectName, color: .blue)
            opsMetricCard(title: LocalizedString.text("investigation_documents_title"), value: "\(investigation.documentDigests.filter { $0.generatedAt != nil }.count)", detail: LocalizedString.format("investigation_projection_documents_detail", investigation.documentDigests.count), color: .green)
            opsMetricCard(title: LocalizedString.text("investigation_sessions_nodes_title"), value: "\(investigation.sessionCount) / \(investigation.nodeCount)", detail: LocalizedString.text("investigation_sessions_nodes_detail"), color: .orange)
            opsMetricCard(title: LocalizedString.text("investigation_traces_anomalies_title"), value: "\(investigation.traceCount) / \(investigation.anomalyCount)", detail: LocalizedString.text("investigation_traces_anomalies_detail"), color: .teal)
        }

        opsInvestigationSection(LocalizedString.text("investigation_projection_freshness_title"), detail: LocalizedString.text("investigation_projection_freshness_detail")) {
            VStack(spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(LocalizedString.text("investigation_freshest_generated_at"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(investigation.freshestGeneratedAt?.formatted(date: .abbreviated, time: .shortened) ?? LocalizedString.text("ops_unavailable"))
                            .font(.subheadline.weight(.medium))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(LocalizedString.text("investigation_loaded_at"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(investigation.loadedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.subheadline.weight(.medium))
                    }
                }
                .padding(10)
                .background(Color(.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                if let liveRunSummary = investigation.liveRunSummary {
                    Text(liveRunSummary)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color(.controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                if let workflowHealthSummary = investigation.workflowHealthSummary {
                    Text(workflowHealthSummary)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color(.controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }

        opsInvestigationSection(LocalizedString.text("investigation_projection_documents_title"), detail: LocalizedString.text("investigation_projection_documents_section_detail")) {
            ForEach(investigation.documentDigests) { document in
                HStack(alignment: .top, spacing: 12) {
                    opsStatusPill(title: document.title, color: opsHistoryHealthColor(document.status))
                        .frame(width: 110, alignment: .leading)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(document.valueText)
                            .font(.subheadline.weight(.medium))
                        Text(document.detailText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(3)
                    }

                    Spacer()

                    Text(document.generatedAt?.formatted(date: .abbreviated, time: .shortened) ?? LocalizedString.text("investigation_missing"))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(10)
                .background(Color(.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private func opsAnomalyRow(_ anomaly: OpsAnomalyRow) -> some View {
        HStack(alignment: .top, spacing: 12) {
            opsStatusPill(title: anomaly.sourceLabel, color: opsHistoryHealthColor(anomaly.status))
                .frame(width: 92, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(anomaly.title)
                    .font(.subheadline.weight(.medium))
                Text(anomaly.detailText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                Text([anomaly.relatedJobID, anomaly.relatedSourcePath, anomaly.sourceService].compactMap { $0 }.joined(separator: " • "))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(anomaly.statusText)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(anomaly.occurredAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(10)
        .background(Color(.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func nodeInvestigationBody(_ investigation: OpsCenterNodeInvestigation) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
            opsMetricCard(title: LocalizedString.text("investigation_node_status_title"), value: investigation.node.status.title, detail: investigation.node.latestDetail ?? LocalizedString.text("node_state_detail_empty"), color: investigation.node.status.color)
            opsMetricCard(title: LocalizedString.text("ops_all_sessions"), value: "\(investigation.relatedSessions.count)", detail: LocalizedString.text("investigation_node_sessions_detail"), color: .blue)
            opsMetricCard(title: LocalizedString.text("dispatches_label"), value: "\(investigation.dispatches.count)", detail: LocalizedString.text("investigation_node_dispatches_detail"), color: .orange)
            opsMetricCard(title: LocalizedString.text("receipts_label"), value: "\(investigation.receipts.count)", detail: LocalizedString.text("investigation_node_receipts_detail"), color: .green)
            opsMetricCard(title: LocalizedString.text("messages"), value: "\(investigation.messages.count)", detail: LocalizedString.text("investigation_node_messages_detail"), color: .purple)
            opsMetricCard(title: LocalizedString.text("tasks"), value: "\(investigation.tasks.count)", detail: LocalizedString.text("investigation_node_tasks_detail"), color: .teal)
        }

        opsInvestigationSection(LocalizedString.text("investigation_routing_context_title"), detail: LocalizedString.text("investigation_routing_context_detail")) {
            if investigation.incomingEdges.isEmpty && investigation.outgoingEdges.isEmpty {
                opsInlineEmptyState(LocalizedString.text("investigation_routing_context_empty"))
            } else {
                ForEach(investigation.incomingEdges) { edge in
                    HStack {
                        Text("\(edge.fromTitle) -> \(edge.toTitle)")
                            .font(.caption.weight(.medium))
                        Spacer()
                        Text(LocalizedString.format("edge_flow_badge", edge.activityCount))
                            .font(.caption)
                            .foregroundColor(edge.activityCount > 0 ? .blue : .secondary)
                        if edge.requiresApproval {
                            opsStatusPill(title: LocalizedString.text("approval"), color: .yellow)
                        }
                        investigationActionButton(title: LocalizedString.text("open_route")) {
                            onSelectRoute(edge.id)
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
                        Text(LocalizedString.format("edge_flow_badge", edge.activityCount))
                            .font(.caption)
                            .foregroundColor(edge.activityCount > 0 ? .blue : .secondary)
                        if edge.requiresApproval {
                            opsStatusPill(title: LocalizedString.text("approval"), color: .yellow)
                        }
                        investigationActionButton(title: LocalizedString.text("open_route")) {
                            onSelectRoute(edge.id)
                        }
                    }
                    .padding(10)
                    .background(Color(.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }

        opsInvestigationSection(LocalizedString.text("investigation_related_sessions_title"), detail: LocalizedString.text("investigation_node_related_sessions_detail")) {
            if investigation.relatedSessions.isEmpty {
                opsInlineEmptyState(LocalizedString.text("investigation_node_related_sessions_empty"))
            } else {
                ForEach(investigation.relatedSessions) { session in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                        Text(session.sessionID)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            Text(LocalizedString.format("session_counts_summary", session.eventCount, session.dispatchCount, session.receiptCount))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        opsStatusPill(
                            title: session.isPrimaryRuntimeSession ? LocalizedString.text("primary_badge") : LocalizedString.text("linked_badge"),
                            color: session.isPrimaryRuntimeSession ? .teal : .blue
                        )
                        investigationActionButton(title: LocalizedString.text("open_session")) {
                            onSelectSession(session.sessionID)
                        }
                        investigationActionButton(title: LocalizedString.text("open_thread")) {
                            onSelectThread(session.sessionID)
                        }
                    }
                    .padding(10)
                    .background(Color(.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }

        opsInvestigationSection(LocalizedString.text("investigation_runtime_events_title"), detail: LocalizedString.text("investigation_node_runtime_events_detail")) {
            if investigation.events.isEmpty {
                opsInlineEmptyState(LocalizedString.text("investigation_node_runtime_events_empty"))
            } else {
                ForEach(investigation.events.prefix(10)) { event in
                    OpsCenterEventDigestCard(event: event)
                }
            }
        }

        opsInvestigationSection(LocalizedString.text("dispatches_label"), detail: LocalizedString.text("investigation_node_dispatches_section_detail")) {
            if investigation.dispatches.isEmpty {
                opsInlineEmptyState(LocalizedString.text("investigation_node_dispatches_empty"))
            } else {
                ForEach(investigation.dispatches.prefix(12)) { dispatch in
                    OpsCenterDispatchDigestCard(dispatch: dispatch)
                }
            }
        }

        opsInvestigationSection(LocalizedString.text("receipts_label"), detail: LocalizedString.text("investigation_node_receipts_section_detail")) {
            if investigation.receipts.isEmpty {
                opsInlineEmptyState(LocalizedString.text("investigation_node_receipts_empty"))
            } else {
                ForEach(investigation.receipts.prefix(10)) { receipt in
                    OpsCenterReceiptDigestCard(receipt: receipt)
                }
            }
        }

        opsInvestigationSection(LocalizedString.text("investigation_workbench_messages_title"), detail: LocalizedString.text("investigation_node_messages_section_detail")) {
            if investigation.messages.isEmpty {
                opsInlineEmptyState(LocalizedString.text("investigation_node_messages_empty"))
            } else {
                ForEach(investigation.messages.prefix(10)) { message in
                    OpsCenterMessageDigestCard(message: message)
                }
            }
        }

        opsInvestigationSection(LocalizedString.text("investigation_workbench_tasks_title"), detail: LocalizedString.text("investigation_node_tasks_section_detail")) {
            if investigation.tasks.isEmpty {
                opsInlineEmptyState(LocalizedString.text("investigation_node_tasks_empty"))
            } else {
                ForEach(investigation.tasks.prefix(10)) { task in
                    OpsCenterTaskDigestCard(task: task)
                }
            }
        }
    }

    @ViewBuilder
    private func routeInvestigationBody(_ investigation: OpsCenterRouteInvestigation) -> some View {
        let pressureDigests = routePressureDigests(for: investigation)
        let timelineEntries = routeTimelineEntries(for: investigation)

        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
            opsMetricCard(title: LocalizedString.text("investigation_route_flow_title"), value: "\(investigation.edge.activityCount)", detail: investigation.edge.title, color: .blue)
            opsMetricCard(title: LocalizedString.text("ops_all_sessions"), value: "\(investigation.relatedSessions.count)", detail: LocalizedString.text("investigation_route_sessions_detail"), color: .green)
            opsMetricCard(title: LocalizedString.text("dispatches_label"), value: "\(investigation.dispatches.count)", detail: LocalizedString.text("investigation_route_dispatches_detail"), color: .orange)
            opsMetricCard(title: LocalizedString.text("receipts_label"), value: "\(investigation.receipts.count)", detail: LocalizedString.text("investigation_route_receipts_detail"), color: .teal)
            opsMetricCard(title: LocalizedString.text("messages"), value: "\(investigation.messages.count)", detail: LocalizedString.text("investigation_route_messages_detail"), color: .purple)
            opsMetricCard(title: LocalizedString.text("tasks"), value: "\(investigation.tasks.count)", detail: LocalizedString.text("investigation_route_tasks_detail"), color: .indigo)
        }

        opsInvestigationSection(LocalizedString.text("investigation_route_posture_title"), detail: LocalizedString.text("investigation_route_posture_detail")) {
            VStack(alignment: .leading, spacing: 8) {
                routeEndpointCard(title: LocalizedString.text("investigation_upstream_title"), node: investigation.upstreamNode, fallbackTitle: investigation.edge.fromTitle)
                if let upstreamNode = investigation.upstreamNode {
                    HStack {
                        Spacer()
                        investigationActionButton(title: LocalizedString.text("open_upstream_node")) {
                            onSelectNode(upstreamNode.id)
                        }
                    }
                }

                routeEndpointCard(title: LocalizedString.text("investigation_downstream_title"), node: investigation.downstreamNode, fallbackTitle: investigation.edge.toTitle)
                if let downstreamNode = investigation.downstreamNode {
                    HStack {
                        Spacer()
                        investigationActionButton(title: LocalizedString.text("open_downstream_node")) {
                            onSelectNode(downstreamNode.id)
                        }
                    }
                }

                HStack {
                    Text(LocalizedString.text("investigation_label_title"))
                        .font(.caption.weight(.medium))
                    Spacer()
                    Text(investigation.edge.title)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if investigation.edge.requiresApproval {
                        opsStatusPill(title: LocalizedString.text("approval"), color: .yellow)
                    }
                }
                .padding(10)
                .background(Color(.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }

        opsInvestigationSection(LocalizedString.text("investigation_pressure_judgement_title"), detail: LocalizedString.text("investigation_pressure_judgement_detail")) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                ForEach(pressureDigests) { digest in
                    opsMetricCard(title: digest.title, value: digest.valueText, detail: digest.detailText, color: digest.color)
                }
            }
        }

        opsInvestigationSection(LocalizedString.text("investigation_timeline_summary_title"), detail: LocalizedString.text("investigation_timeline_summary_detail")) {
            if timelineEntries.isEmpty {
                opsInlineEmptyState(LocalizedString.text("investigation_timeline_summary_empty"))
            } else {
                ForEach(Array(timelineEntries.prefix(16))) { entry in
                    HStack(alignment: .top, spacing: 12) {
                        opsStatusPill(title: entry.kindTitle, color: entry.color)
                            .frame(width: 86, alignment: .leading)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.title)
                                .font(.subheadline.weight(.medium))
                            Text(entry.detailText)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(3)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 6) {
                            if let sessionID = entry.sessionID, !sessionID.isEmpty {
                                Text(sessionID)
                                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            Text(entry.timestamp.formatted(date: .abbreviated, time: .shortened))
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

        opsInvestigationSection(LocalizedString.text("investigation_related_sessions_title"), detail: LocalizedString.text("investigation_route_related_sessions_detail")) {
            if investigation.relatedSessions.isEmpty {
                opsInlineEmptyState(LocalizedString.text("investigation_route_related_sessions_empty"))
            } else {
                ForEach(investigation.relatedSessions) { session in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                        Text(session.sessionID)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            Text(LocalizedString.format("session_counts_summary", session.eventCount, session.dispatchCount, session.receiptCount))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        opsStatusPill(
                            title: session.failedDispatchCount > 0 ? LocalizedString.text("failure_signal_badge") : LocalizedString.text("observed_badge"),
                            color: session.failedDispatchCount > 0 ? .red : .blue
                        )
                        investigationActionButton(title: LocalizedString.text("open_session")) {
                            onSelectSession(session.sessionID)
                        }
                        investigationActionButton(title: LocalizedString.text("open_thread")) {
                            onSelectThread(session.sessionID)
                        }
                    }
                    .padding(10)
                    .background(Color(.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }

        opsInvestigationSection(LocalizedString.text("dispatches_label"), detail: LocalizedString.text("investigation_route_dispatches_section_detail")) {
            if investigation.dispatches.isEmpty {
                opsInlineEmptyState(LocalizedString.text("investigation_route_dispatches_empty"))
            } else {
                ForEach(investigation.dispatches.prefix(12)) { dispatch in
                    OpsCenterDispatchDigestCard(dispatch: dispatch)
                }
            }
        }

        opsInvestigationSection(LocalizedString.text("investigation_endpoint_receipts_title"), detail: LocalizedString.text("investigation_endpoint_receipts_detail")) {
            if investigation.receipts.isEmpty {
                opsInlineEmptyState(LocalizedString.text("investigation_endpoint_receipts_empty"))
            } else {
                ForEach(investigation.receipts.prefix(12)) { receipt in
                    OpsCenterReceiptDigestCard(receipt: receipt)
                }
            }
        }

        opsInvestigationSection(LocalizedString.text("investigation_runtime_events_title"), detail: LocalizedString.text("investigation_route_runtime_events_detail")) {
            if investigation.events.isEmpty {
                opsInlineEmptyState(LocalizedString.text("investigation_route_runtime_events_empty"))
            } else {
                ForEach(investigation.events.prefix(10)) { event in
                    OpsCenterEventDigestCard(event: event)
                }
            }
        }

        opsInvestigationSection(LocalizedString.text("investigation_workbench_messages_title"), detail: LocalizedString.text("investigation_route_messages_section_detail")) {
            if investigation.messages.isEmpty {
                opsInlineEmptyState(LocalizedString.text("investigation_route_messages_empty"))
            } else {
                ForEach(investigation.messages.prefix(10)) { message in
                    OpsCenterMessageDigestCard(message: message)
                }
            }
        }

        opsInvestigationSection(LocalizedString.text("investigation_workbench_tasks_title"), detail: LocalizedString.text("investigation_route_tasks_section_detail")) {
            if investigation.tasks.isEmpty {
                opsInlineEmptyState(LocalizedString.text("investigation_route_tasks_empty"))
            } else {
                ForEach(investigation.tasks.prefix(10)) { task in
                    OpsCenterTaskDigestCard(task: task)
                }
            }
        }
    }

    private func routePressureDigests(for investigation: OpsCenterRouteInvestigation) -> [OpsCenterRoutePressureDigest] {
        let upstreamBacklog = investigation.relatedSessions.reduce(0) { partial, session in
            partial + session.queuedDispatchCount + session.inflightDispatchCount
        }
        let failedDispatches = investigation.dispatches.filter { dispatch in
            dispatch.status == .failed || dispatch.status == .aborted || dispatch.status == .expired
        }.count
        let waitingDispatches = investigation.dispatches.filter { dispatch in
            dispatch.status == .created
                || dispatch.status == .dispatched
                || dispatch.status == .accepted
                || dispatch.status == .running
                || dispatch.status == .waitingDependency
        }.count
        let waitingApprovals = investigation.dispatches.filter { $0.status == .waitingApproval }.count
            + investigation.messages.filter { $0.status == .waitingForApproval }.count
        let downstreamFailures = investigation.receipts.filter { $0.status == .failed }.count
        let downstreamWaiting = investigation.receipts.filter { $0.status == .waiting }.count

        let upstreamScore = routePressureScore(for: investigation.upstreamNode) + upstreamBacklog + waitingDispatches
        let downstreamScore = routePressureScore(for: investigation.downstreamNode) + downstreamFailures * 3 + downstreamWaiting * 2 + failedDispatches * 2
        let gateScore = (investigation.edge.requiresApproval ? 2 : 0) + waitingApprovals * 3

        let bottleneckDigest: OpsCenterRoutePressureDigest = {
            if gateScore >= max(upstreamScore, downstreamScore), gateScore > 0 {
                return OpsCenterRoutePressureDigest(
                    id: "bottleneck",
                    title: LocalizedString.text("investigation_likely_bottleneck_title"),
                    valueText: LocalizedString.text("investigation_approval_gate_value"),
                    detailText: waitingApprovals > 0
                        ? LocalizedString.format("investigation_route_approval_waits_detail", waitingApprovals)
                        : LocalizedString.text("investigation_route_approval_gate_detail"),
                    color: .yellow
                )
            }
            if downstreamScore > upstreamScore + 1 {
                return OpsCenterRoutePressureDigest(
                    id: "bottleneck",
                    title: LocalizedString.text("investigation_likely_bottleneck_title"),
                    valueText: LocalizedString.text("investigation_downstream_sink_value"),
                    detailText: LocalizedString.format("investigation_downstream_sink_detail", downstreamFailures, downstreamWaiting),
                    color: .red
                )
            }
            if upstreamScore > downstreamScore + 1 {
                return OpsCenterRoutePressureDigest(
                    id: "bottleneck",
                    title: LocalizedString.text("investigation_likely_bottleneck_title"),
                    valueText: LocalizedString.text("investigation_upstream_backlog_value"),
                    detailText: LocalizedString.format("investigation_upstream_backlog_detail", upstreamBacklog),
                    color: .orange
                )
            }
            if failedDispatches > 0 {
                return OpsCenterRoutePressureDigest(
                    id: "bottleneck",
                    title: LocalizedString.text("investigation_likely_bottleneck_title"),
                    valueText: LocalizedString.text("investigation_failure_churn_value"),
                    detailText: LocalizedString.format("investigation_failure_churn_detail", failedDispatches),
                    color: .red
                )
            }
            return OpsCenterRoutePressureDigest(
                id: "bottleneck",
                title: LocalizedString.text("investigation_likely_bottleneck_title"),
                valueText: LocalizedString.text("investigation_flowing_value"),
                detailText: LocalizedString.text("investigation_flowing_detail"),
                color: .green
            )
        }()

        return [
            OpsCenterRoutePressureDigest(
                id: "upstream",
                title: LocalizedString.text("investigation_upstream_pressure_title"),
                valueText: routePressureLabel(for: upstreamScore),
                detailText: LocalizedString.format("investigation_upstream_pressure_detail", upstreamBacklog, investigation.upstreamNode?.status.title ?? LocalizedString.text("investigation_unknown_status")),
                color: routePressureColor(for: upstreamScore)
            ),
            OpsCenterRoutePressureDigest(
                id: "downstream",
                title: LocalizedString.text("investigation_downstream_pressure_title"),
                valueText: routePressureLabel(for: downstreamScore),
                detailText: LocalizedString.format("investigation_downstream_pressure_detail", downstreamFailures, downstreamWaiting, investigation.downstreamNode?.status.title ?? LocalizedString.text("investigation_unknown_status")),
                color: routePressureColor(for: downstreamScore)
            ),
            OpsCenterRoutePressureDigest(
                id: "approval",
                title: LocalizedString.text("investigation_approval_gating_title"),
                valueText: gateScore > 0 ? (waitingApprovals > 0 ? LocalizedString.text("investigation_waiting_value") : LocalizedString.text("investigation_armed_value")) : LocalizedString.text("investigation_clear_value"),
                detailText: gateScore > 0
                    ? LocalizedString.format("investigation_approval_gating_detail", waitingApprovals, investigation.edge.requiresApproval ? LocalizedString.text("investigation_gate_enabled") : LocalizedString.text("investigation_gate_clear"))
                    : LocalizedString.text("investigation_approval_gating_empty"),
                color: gateScore > 0 ? .yellow : .green
            ),
            bottleneckDigest
        ]
    }

    private func routeTimelineEntries(for investigation: OpsCenterRouteInvestigation) -> [OpsCenterRouteTimelineDigest] {
        let dispatchEntries = investigation.dispatches.map { dispatch in
            OpsCenterRouteTimelineDigest(
                id: "dispatch-\(dispatch.id)",
                kindTitle: LocalizedString.text("dispatches_label"),
                title: "\(dispatch.sourceName) -> \(dispatch.targetName)",
                detailText: "\(opsDispatchStatusTitle(dispatch.status)) • \(dispatch.summary)",
                timestamp: dispatch.updatedAt,
                color: opsDispatchStatusColor(dispatch.status),
                sessionID: dispatch.sessionID
            )
        }

        let receiptEntries = investigation.receipts.map { receipt in
            OpsCenterRouteTimelineDigest(
                id: "receipt-\(receipt.id.uuidString)",
                kindTitle: LocalizedString.text("receipt_label"),
                title: receipt.nodeTitle,
                detailText: "\(opsExecutionStatusTitle(receipt.status)) • \(receipt.summary)",
                timestamp: receipt.timestamp,
                color: opsExecutionStatusColor(receipt.status),
                sessionID: receipt.sessionID
            )
        }

        let eventEntries = investigation.events.map { event in
            OpsCenterRouteTimelineDigest(
                id: "event-\(event.id)",
                kindTitle: LocalizedString.text("event_label"),
                title: opsRuntimeEventTypeTitle(event.eventType),
                detailText: "\(event.participants) • \(event.summary)",
                timestamp: event.timestamp,
                color: .blue,
                sessionID: event.sessionID
            )
        }

        let messageEntries = investigation.messages.map { message in
            OpsCenterRouteTimelineDigest(
                id: "message-\(message.id.uuidString)",
                kindTitle: LocalizedString.text("message"),
                title: message.routeTitle,
                detailText: "\(opsMessageStatusTitle(message.status)) • \(message.summary)",
                timestamp: message.timestamp,
                color: message.status.color,
                sessionID: nil
            )
        }

        let taskEntries = investigation.tasks.map { task in
            OpsCenterRouteTimelineDigest(
                id: "task-\(task.id.uuidString)",
                kindTitle: LocalizedString.text("task"),
                title: task.title,
                detailText: "\(task.status.displayName) • \(task.summary)",
                timestamp: task.timestamp,
                color: task.priority.color,
                sessionID: nil
            )
        }

        return (dispatchEntries + receiptEntries + eventEntries + messageEntries + taskEntries).sorted { lhs, rhs in
            if lhs.timestamp != rhs.timestamp {
                return lhs.timestamp > rhs.timestamp
            }
            return lhs.id > rhs.id
        }
    }

    private func routePressureScore(for node: OpsCenterNodeSummary?) -> Int {
        guard let node else { return 0 }
        switch node.status {
        case .failed:
            return 5
        case .waitingApproval:
            return 4
        case .inflight:
            return 3
        case .queued:
            return 2
        case .completed:
            return 1
        case .idle:
            return 0
        }
    }

    private func routePressureLabel(for score: Int) -> String {
        switch score {
        case 7...:
            return LocalizedString.text("high")
        case 3...6:
            return LocalizedString.text("medium")
        case 1...2:
            return LocalizedString.text("low")
        default:
            return LocalizedString.text("investigation_clear_value")
        }
    }

    private func routePressureColor(for score: Int) -> Color {
        switch score {
        case 7...:
            return .red
        case 3...6:
            return .orange
        case 1...2:
            return .yellow
        default:
            return .green
        }
    }

    private func workbenchThreadStatusTitle(_ status: String) -> String {
        switch status {
        case "approval_pending":
            return LocalizedString.text("workbench_thread_status_approval_pending")
        case "blocked":
            return LocalizedString.text("workbench_thread_status_blocked")
        case "active":
            return LocalizedString.text("workbench_thread_status_active")
        case "completed":
            return LocalizedString.text("workbench_thread_status_completed")
        default:
            return LocalizedString.text("workbench_thread_status_idle")
        }
    }

    private func workbenchThreadStatusColor(_ status: String) -> Color {
        switch status {
        case "approval_pending":
            return .yellow
        case "blocked":
            return .red
        case "active":
            return .orange
        case "completed":
            return .green
        default:
            return .secondary
        }
    }

    private func investigationActionButton(title: String, action: @escaping () -> Void) -> some View {
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
            Text(node?.agentName ?? LocalizedString.text("no_bound_agent"))
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
                    Text(receipt.agentName ?? LocalizedString.text("investigation_unknown_agent"))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
                opsStatusPill(title: opsExecutionStatusTitle(receipt.status), color: opsExecutionStatusColor(receipt.status))
            }

            Text(receipt.summary)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(3)

            HStack {
                Text(opsExecutionOutputTypeTitle(receipt.outputType))
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
                Text(opsRuntimeEventTypeTitle(event.eventType))
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
                opsStatusPill(title: opsMessageStatusTitle(message.status), color: message.status.color)
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
                opsStatusPill(title: task.status.displayName, color: task.status.color)
                opsStatusPill(title: task.priority.displayName, color: task.priority.color)
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
            return LocalizedString.text("map_layer_state")
        case .latency:
            return LocalizedString.text("map_layer_latency")
        case .failures:
            return LocalizedString.text("map_layer_failures")
        case .routing:
            return LocalizedString.text("map_layer_routing")
        case .approvals:
            return LocalizedString.text("map_layer_approvals")
        case .files:
            return LocalizedString.text("map_layer_files")
        }
    }

    var detail: String {
        switch self {
        case .state:
            return LocalizedString.text("map_layer_state_detail")
        case .latency:
            return LocalizedString.text("map_layer_latency_detail")
        case .failures:
            return LocalizedString.text("map_layer_failures_detail")
        case .routing:
            return LocalizedString.text("map_layer_routing_detail")
        case .approvals:
            return LocalizedString.text("map_layer_approvals_detail")
        case .files:
            return LocalizedString.text("map_layer_files_detail")
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
        return LocalizedString.text("dispatch_status_created")
    case .dispatched:
        return LocalizedString.text("dispatch_status_dispatched")
    case .accepted:
        return LocalizedString.text("dispatch_status_accepted")
    case .running:
        return LocalizedString.text("dispatch_status_running")
    case .waitingApproval:
        return LocalizedString.text("dispatch_status_approval")
    case .waitingDependency:
        return LocalizedString.text("dispatch_status_waiting")
    case .completed:
        return LocalizedString.text("dispatch_status_completed")
    case .failed:
        return LocalizedString.text("dispatch_status_failed")
    case .aborted:
        return LocalizedString.text("dispatch_status_aborted")
    case .expired:
        return LocalizedString.text("dispatch_status_expired")
    case .partial:
        return LocalizedString.text("dispatch_status_partial")
    }
}

private func opsExecutionStatusTitle(_ status: ExecutionStatus) -> String {
    status.displayName
}

private func opsExecutionOutputTypeTitle(_ outputType: ExecutionOutputType) -> String {
    switch outputType {
    case .agentFinalResponse:
        return LocalizedString.text("execution_output_agent_final_response")
    case .runtimeLog:
        return LocalizedString.text("execution_output_runtime_log")
    case .errorSummary:
        return LocalizedString.text("execution_output_error_summary")
    case .empty:
        return LocalizedString.text("execution_output_empty")
    }
}

private func opsRuntimeEventTypeTitle(_ eventType: OpenClawRuntimeEventType) -> String {
    switch eventType {
    case .taskDispatch:
        return LocalizedString.text("runtime_event_task_dispatch")
    case .taskAccepted:
        return LocalizedString.text("runtime_event_task_accepted")
    case .taskProgress:
        return LocalizedString.text("runtime_event_task_progress")
    case .taskResult:
        return LocalizedString.text("runtime_event_task_result")
    case .taskRoute:
        return LocalizedString.text("runtime_event_task_route")
    case .taskError:
        return LocalizedString.text("runtime_event_task_error")
    case .taskApprovalRequired:
        return LocalizedString.text("runtime_event_task_approval_required")
    case .taskApproved:
        return LocalizedString.text("runtime_event_task_approved")
    case .sessionSync:
        return LocalizedString.text("runtime_event_session_sync")
    }
}

private func opsMessageStatusTitle(_ status: MessageStatus) -> String {
    switch status {
    case .pending:
        return LocalizedString.pending
    case .sent:
        return LocalizedString.text("message_status_sent")
    case .delivered:
        return LocalizedString.text("message_status_delivered")
    case .read:
        return LocalizedString.text("message_status_read")
    case .failed:
        return LocalizedString.text("dispatch_status_failed")
    case .waitingForApproval:
        return LocalizedString.text("pending_approval")
    case .approved:
        return LocalizedString.text("message_status_approved")
    case .rejected:
        return LocalizedString.text("message_status_rejected")
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

private func opsThreadRow(_ thread: OpsCenterThreadSummary, emphasis: OpsThreadRowEmphasis) -> some View {
    HStack(alignment: .top, spacing: 12) {
        opsStatusPill(
            title: opsWorkbenchThreadStatusTitle(thread.status),
            color: opsWorkbenchThreadStatusColor(thread.status)
        )
        .frame(width: 104, alignment: .leading)

        VStack(alignment: .leading, spacing: 4) {
            Text(thread.threadID)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(.primary)
            Text(opsThreadHotspotReason(thread))
                .font(emphasis == .hotspot ? .caption.weight(.medium) : .caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
            Text([
                thread.workflowName,
                thread.entryAgentName,
                thread.participantNames.isEmpty ? nil : "\(thread.participantNames.count) participants"
            ].compactMap { $0 }.joined(separator: " • "))
            .font(.caption2)
            .foregroundColor(.secondary)
            .lineLimit(1)
            if let relatedSession = thread.relatedSession {
                Text("Runtime Q \(relatedSession.queuedDispatchCount) • Run \(relatedSession.inflightDispatchCount) • F \(relatedSession.failedDispatchCount)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }

        Spacer()

        VStack(alignment: .trailing, spacing: 4) {
            Text("M \(thread.messageCount) • T \(thread.taskCount)")
                .font(.caption2)
                .foregroundColor(.secondary)
            Text("A \(thread.pendingApprovalCount) • B \(thread.blockedTaskCount) • R \(thread.activeTaskCount)")
                .font(.caption2)
                .foregroundColor(.secondary)
            if let lastUpdatedAt = thread.lastUpdatedAt {
                Text(lastUpdatedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
    .padding(10)
    .background(Color(.controlBackgroundColor))
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
}

private func opsSessionIsHotspot(_ session: OpsCenterSessionSummary) -> Bool {
    session.failedDispatchCount > 0
        || session.queuedDispatchCount > 0
        || session.inflightDispatchCount > 0
        || session.isPrimaryRuntimeSession
        || ((session.latestFailureText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) == false)
}

private func opsSessionActivityScore(_ session: OpsCenterSessionSummary) -> Int {
    (session.inflightDispatchCount * 4)
        + (session.queuedDispatchCount * 3)
        + (session.dispatchCount * 2)
        + session.receiptCount
        + session.eventCount
}

private func opsSessionFailureScore(_ session: OpsCenterSessionSummary) -> Int {
    let failureTextScore = ((session.latestFailureText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) == false) ? 2 : 0
    return (session.failedDispatchCount * 4) + failureTextScore + (session.isPrimaryRuntimeSession ? 1 : 0)
}

private func opsSessionHotspotReason(_ session: OpsCenterSessionSummary) -> String {
    if session.failedDispatchCount > 0 {
        return "Dispatch failure pressure is retained in this session."
    }
    if session.inflightDispatchCount > 0 {
        return "This session still owns inflight route work."
    }
    if session.queuedDispatchCount > 0 {
        return "Queued dispatches are waiting to clear from this session."
    }
    if session.isPrimaryRuntimeSession {
        return "Primary runtime session should stay visible for top-level drill-down."
    }
    if (session.latestFailureText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) == false {
        return "Failure text is retained even though live pressure may have cooled."
    }
    return "Observed session with retained workflow evidence."
}

private func opsBuildThreadSummaries(
    project: MAProject?,
    workflow: Workflow?,
    messages: [Message],
    tasks: [Task],
    sessionSummaries: [OpsCenterSessionSummary],
    projections: OpsCenterProjectionBundle?
) -> [OpsCenterThreadSummary] {
    let scopedWorkflowID = workflow?.id
    let scopeWorkflowText = scopedWorkflowID?.uuidString

    let liveSummaries: [OpsCenterThreadSummary] = {
        guard let project else { return [] }

        let workbenchMessages = messages.filter { $0.metadata["channel"] == "workbench" }
        let workbenchTasks = tasks.filter { $0.metadata["source"] == "workbench" }
        let sessionIDs = Set(workbenchMessages.compactMap { opsNormalizedThreadID($0.metadata["workbenchSessionID"]) })
            .union(workbenchTasks.compactMap { opsNormalizedThreadID($0.metadata["workbenchSessionID"]) })

        guard !sessionIDs.isEmpty else { return [] }

        let agentNamesByID = Dictionary(uniqueKeysWithValues: project.agents.map { ($0.id, $0.name) })
        let workflowsByID = Dictionary(uniqueKeysWithValues: project.workflows.map { ($0.id, $0.name) })

        return sessionIDs.compactMap { sessionID in
            let threadMessages = workbenchMessages.filter { opsNormalizedThreadID($0.metadata["workbenchSessionID"]) == sessionID }
            let threadTasks = workbenchTasks.filter { opsNormalizedThreadID($0.metadata["workbenchSessionID"]) == sessionID }
            let relatedSession = sessionSummaries.first { $0.sessionID == sessionID }
            let resolvedWorkflowID = threadMessages.compactMap { opsWorkflowID(from: $0.metadata["workflowID"]) }.first
                ?? threadTasks.compactMap { opsWorkflowID(from: $0.metadata["workflowID"]) }.first
            let metadataMatchesScope = threadMessages.contains { opsMatchesWorkflowScope($0.metadata, workflowID: scopedWorkflowID) }
                || threadTasks.contains { opsMatchesWorkflowScope($0.metadata, workflowID: scopedWorkflowID) }
            let sessionMatchesScope = scopeWorkflowText.map { relatedSession?.workflowIDs.contains($0) ?? false } ?? true
            let resolvedMatchesScope = scopedWorkflowID.map { resolvedWorkflowID == $0 } ?? true

            if scopedWorkflowID != nil && !(metadataMatchesScope || sessionMatchesScope || resolvedMatchesScope) {
                return nil
            }

            let entryAgentID = threadMessages.compactMap { opsAgentID(from: $0.metadata["entryAgentID"]) }.first
                ?? threadTasks.compactMap(\.assignedAgentID).first
            let participantNames = Set(
                threadMessages.flatMap { [$0.fromAgentID, $0.toAgentID] } + threadTasks.compactMap(\.assignedAgentID)
            )
            .compactMap { agentNamesByID[$0] }
            .sorted()
            let taskDates = threadTasks.map { $0.completedAt ?? $0.startedAt ?? $0.createdAt }
            let startedAt = (threadMessages.map(\.timestamp) + threadTasks.map(\.createdAt)).min() ?? relatedSession?.lastUpdatedAt
            let lastUpdatedAt = (threadMessages.map(\.timestamp) + taskDates).max() ?? relatedSession?.lastUpdatedAt
            let activeTaskCount = threadTasks.filter { $0.status == .todo || $0.status == .inProgress }.count
            let blockedTaskCount = threadTasks.filter { $0.status == .blocked }.count
            let completedTaskCount = threadTasks.filter { $0.status == .done }.count
            let failedMessageCount = threadMessages.filter { $0.status == .failed || $0.status == .rejected }.count
            let status = opsWorkbenchThreadStatus(messages: threadMessages, tasks: threadTasks)
            let summary = OpsCenterThreadSummary(
                threadID: sessionID,
                workflowID: resolvedWorkflowID,
                workflowName: resolvedWorkflowID.flatMap { workflowsByID[$0] } ?? workflow?.name ?? LocalizedString.text("workbench_thread_label"),
                status: status,
                entryAgentName: entryAgentID.flatMap { agentNamesByID[$0] },
                participantNames: participantNames,
                messageCount: threadMessages.count,
                taskCount: threadTasks.count,
                pendingApprovalCount: threadMessages.filter { $0.status == .waitingForApproval }.count,
                blockedTaskCount: blockedTaskCount,
                activeTaskCount: activeTaskCount,
                completedTaskCount: completedTaskCount,
                failedMessageCount: failedMessageCount,
                startedAt: startedAt,
                lastUpdatedAt: lastUpdatedAt,
                relatedSession: relatedSession,
                hotspotScore: 0
            )

            let hotspotScore = opsThreadHotspotScore(summary)
            return OpsCenterThreadSummary(
                threadID: summary.threadID,
                workflowID: summary.workflowID,
                workflowName: summary.workflowName,
                status: summary.status,
                entryAgentName: summary.entryAgentName,
                participantNames: summary.participantNames,
                messageCount: summary.messageCount,
                taskCount: summary.taskCount,
                pendingApprovalCount: summary.pendingApprovalCount,
                blockedTaskCount: summary.blockedTaskCount,
                activeTaskCount: summary.activeTaskCount,
                completedTaskCount: summary.completedTaskCount,
                failedMessageCount: summary.failedMessageCount,
                startedAt: summary.startedAt,
                lastUpdatedAt: summary.lastUpdatedAt,
                relatedSession: summary.relatedSession,
                hotspotScore: hotspotScore
            )
        }
    }()

    let projectionSummaries: [OpsCenterThreadSummary] = (projections?.threadEntries(for: scopedWorkflowID) ?? []).map { entry in
        let relatedSession = sessionSummaries.first { $0.sessionID == entry.sessionID }
        let summary = OpsCenterThreadSummary(
            threadID: entry.threadID,
            workflowID: entry.workflowID,
            workflowName: entry.workflowName ?? workflow?.name ?? LocalizedString.text("workbench_thread_label"),
            status: entry.status,
            entryAgentName: entry.entryAgentName,
            participantNames: entry.participantNames,
            messageCount: entry.messageCount,
            taskCount: entry.taskCount,
            pendingApprovalCount: entry.pendingApprovalCount,
            blockedTaskCount: entry.blockedTaskCount,
            activeTaskCount: entry.activeTaskCount,
            completedTaskCount: entry.completedTaskCount,
            failedMessageCount: entry.failedMessageCount,
            startedAt: entry.startedAt,
            lastUpdatedAt: entry.lastUpdatedAt,
            relatedSession: relatedSession,
            hotspotScore: 0
        )
        return OpsCenterThreadSummary(
            threadID: summary.threadID,
            workflowID: summary.workflowID,
            workflowName: summary.workflowName,
            status: summary.status,
            entryAgentName: summary.entryAgentName,
            participantNames: summary.participantNames,
            messageCount: summary.messageCount,
            taskCount: summary.taskCount,
            pendingApprovalCount: summary.pendingApprovalCount,
            blockedTaskCount: summary.blockedTaskCount,
            activeTaskCount: summary.activeTaskCount,
            completedTaskCount: summary.completedTaskCount,
            failedMessageCount: summary.failedMessageCount,
            startedAt: summary.startedAt,
            lastUpdatedAt: summary.lastUpdatedAt,
            relatedSession: summary.relatedSession,
            hotspotScore: opsThreadHotspotScore(summary)
        )
    }

    let merged = (projectionSummaries + liveSummaries).reduce(into: [String: OpsCenterThreadSummary]()) { partial, item in
        if partial[item.threadID] == nil || liveSummaries.contains(where: { $0.threadID == item.threadID }) {
            partial[item.threadID] = item
        }
    }

    return merged.values.sorted { lhs, rhs in
        if lhs.hotspotScore != rhs.hotspotScore {
            return lhs.hotspotScore > rhs.hotspotScore
        }
        if lhs.lastUpdatedAt != rhs.lastUpdatedAt {
            return (lhs.lastUpdatedAt ?? .distantPast) > (rhs.lastUpdatedAt ?? .distantPast)
        }
        return lhs.threadID < rhs.threadID
    }
}

private func opsNormalizedThreadID(_ rawValue: String?) -> String? {
    let trimmed = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? nil : trimmed.lowercased()
}

private func opsWorkflowID(from rawValue: String?) -> UUID? {
    let trimmed = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? nil : UUID(uuidString: trimmed)
}

private func opsAgentID(from rawValue: String?) -> UUID? {
    let trimmed = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? nil : UUID(uuidString: trimmed)
}

private func opsMatchesWorkflowScope(_ metadata: [String: String], workflowID: UUID?) -> Bool {
    guard let workflowID else { return true }
    guard let metadataWorkflowID = opsWorkflowID(from: metadata["workflowID"]) else { return false }
    return metadataWorkflowID == workflowID
}

private func opsWorkbenchThreadStatus(messages: [Message], tasks: [Task]) -> String {
    if messages.contains(where: { $0.status == .waitingForApproval }) {
        return "approval_pending"
    }
    if tasks.contains(where: { $0.status == .blocked }) {
        return "blocked"
    }
    if tasks.contains(where: { $0.status == .todo || $0.status == .inProgress }) {
        return "active"
    }
    if tasks.contains(where: { $0.status == .done }) {
        return "completed"
    }
    return messages.isEmpty ? "idle" : "active"
}

private func opsWorkbenchThreadStatusTitle(_ status: String) -> String {
    switch status {
    case "approval_pending":
        return LocalizedString.text("workbench_thread_status_approval_pending")
    case "blocked":
        return LocalizedString.text("workbench_thread_status_blocked")
    case "active":
        return LocalizedString.text("workbench_thread_status_active")
    case "completed":
        return LocalizedString.text("workbench_thread_status_completed")
    default:
        return LocalizedString.text("workbench_thread_status_idle")
    }
}

private func opsWorkbenchThreadStatusColor(_ status: String) -> Color {
    switch status {
    case "approval_pending":
        return .yellow
    case "blocked":
        return .red
    case "active":
        return .orange
    case "completed":
        return .green
    default:
        return .secondary
    }
}

private func opsThreadIsActive(_ thread: OpsCenterThreadSummary) -> Bool {
    switch thread.status {
    case "approval_pending", "blocked", "active":
        return true
    default:
        return (thread.relatedSession?.queuedDispatchCount ?? 0) > 0 || (thread.relatedSession?.inflightDispatchCount ?? 0) > 0
    }
}

private func opsThreadHasRuntimePressure(_ thread: OpsCenterThreadSummary) -> Bool {
    guard let session = thread.relatedSession else { return false }
    return session.failedDispatchCount > 0
        || session.queuedDispatchCount > 0
        || session.inflightDispatchCount > 0
        || session.isPrimaryRuntimeSession
}

private func opsThreadIsHotspot(_ thread: OpsCenterThreadSummary) -> Bool {
    thread.hotspotScore > 0
}

private func opsThreadHotspotScore(_ thread: OpsCenterThreadSummary) -> Int {
    let session = thread.relatedSession
    return (thread.pendingApprovalCount * 6)
        + (thread.blockedTaskCount * 5)
        + (thread.failedMessageCount * 4)
        + (thread.activeTaskCount * 3)
        + ((session?.failedDispatchCount ?? 0) * 4)
        + ((session?.inflightDispatchCount ?? 0) * 3)
        + ((session?.queuedDispatchCount ?? 0) * 2)
        + ((session?.isPrimaryRuntimeSession ?? false) ? 1 : 0)
}

private func opsThreadRuntimePressureScore(_ thread: OpsCenterThreadSummary) -> Int {
    let session = thread.relatedSession
    return ((session?.failedDispatchCount ?? 0) * 5)
        + ((session?.inflightDispatchCount ?? 0) * 4)
        + ((session?.queuedDispatchCount ?? 0) * 3)
        + ((session?.dispatchCount ?? 0) * 2)
        + ((session?.isPrimaryRuntimeSession ?? false) ? 1 : 0)
}

private func opsThreadHotspotReason(_ thread: OpsCenterThreadSummary) -> String {
    if thread.pendingApprovalCount > 0 {
        return LocalizedString.text("thread_hotspot_reason_approval")
    }
    if thread.blockedTaskCount > 0 {
        return LocalizedString.text("thread_hotspot_reason_blocked")
    }
    if let relatedSession = thread.relatedSession, relatedSession.failedDispatchCount > 0 {
        return LocalizedString.text("thread_hotspot_reason_runtime_failure")
    }
    if let relatedSession = thread.relatedSession, relatedSession.inflightDispatchCount > 0 {
        return LocalizedString.text("thread_hotspot_reason_inflight")
    }
    if let relatedSession = thread.relatedSession, relatedSession.queuedDispatchCount > 0 {
        return LocalizedString.text("thread_hotspot_reason_queued")
    }
    if thread.activeTaskCount > 0 {
        return LocalizedString.text("thread_hotspot_reason_active_work")
    }
    if thread.completedTaskCount > 0 {
        return LocalizedString.text("thread_hotspot_reason_completed")
    }
    return LocalizedString.text("thread_hotspot_reason_observed")
}

private func opsPrimaryThreadPressureMode(_ thread: OpsCenterThreadSummary) -> OpsCenterThreadPressureMode {
    if thread.pendingApprovalCount > 0 {
        return .approval
    }
    if thread.blockedTaskCount > 0 || thread.status == "blocked" {
        return .blocked
    }
    if (thread.relatedSession?.failedDispatchCount ?? 0) > 0 || thread.failedMessageCount > 0 {
        return .runtimeFailure
    }
    if let session = thread.relatedSession,
       session.queuedDispatchCount > 0 || session.inflightDispatchCount > 0 || session.isPrimaryRuntimeSession {
        return .runtimeBacklog
    }
    if thread.activeTaskCount > 0 || thread.status == "active" {
        return .activeWork
    }
    return .stable
}

private func opsBuildThreadClusterDigests(_ threads: [OpsCenterThreadSummary]) -> [OpsCenterThreadClusterDigest] {
    let grouped = Dictionary(grouping: threads) { thread -> String in
        let workflowKey = thread.workflowName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let agentKey = (thread.entryAgentName ?? "unassigned").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "\(workflowKey)|\(agentKey)"
    }

    return grouped.compactMap { key, items in
        guard let leadThread = items.max(by: { lhs, rhs in
            if lhs.hotspotScore != rhs.hotspotScore {
                return lhs.hotspotScore < rhs.hotspotScore
            }
            return (lhs.lastUpdatedAt ?? .distantPast) < (rhs.lastUpdatedAt ?? .distantPast)
        }) else {
            return nil
        }

        let title = leadThread.entryAgentName ?? LocalizedString.text("unassigned_entry")
        let hotspotThreadCount = items.filter(opsThreadIsHotspot).count
        let approvalPressure = items.reduce(0) { $0 + $1.pendingApprovalCount }
        let blockedThreadCount = items.filter { $0.blockedTaskCount > 0 || $0.status == "blocked" }.count
        let runtimeLinkedThreadCount = items.filter(opsThreadHasRuntimePressure).count
        let totalHotspotScore = items.reduce(0) { $0 + $1.hotspotScore }
        let latestAt = items.compactMap(\.lastUpdatedAt).max()
        let subtitleText = [
            leadThread.workflowName,
            LocalizedString.format("thread_count_summary", items.count),
            hotspotThreadCount > 0 ? LocalizedString.format("hotspot_count_summary", hotspotThreadCount) : nil
        ]
        .compactMap { $0 }
        .joined(separator: " • ")

        let detailText: String
        if approvalPressure > 0 {
            detailText = LocalizedString.format("thread_cluster_approval_detail", approvalPressure)
        } else if blockedThreadCount > 0 {
            detailText = LocalizedString.format("thread_cluster_blocked_detail", blockedThreadCount)
        } else if runtimeLinkedThreadCount > 0 {
            detailText = LocalizedString.format("thread_cluster_runtime_detail", runtimeLinkedThreadCount)
        } else {
            detailText = opsThreadHotspotReason(leadThread)
        }

        return OpsCenterThreadClusterDigest(
            key: key,
            title: title,
            subtitleText: subtitleText,
            detailText: detailText,
            threadCount: items.count,
            hotspotThreadCount: hotspotThreadCount,
            approvalPressure: approvalPressure,
            blockedThreadCount: blockedThreadCount,
            runtimeLinkedThreadCount: runtimeLinkedThreadCount,
            totalHotspotScore: totalHotspotScore,
            latestAt: latestAt,
            leadThreadID: leadThread.threadID
        )
    }
    .sorted { lhs, rhs in
        if lhs.totalHotspotScore != rhs.totalHotspotScore {
            return lhs.totalHotspotScore > rhs.totalHotspotScore
        }
        if lhs.hotspotThreadCount != rhs.hotspotThreadCount {
            return lhs.hotspotThreadCount > rhs.hotspotThreadCount
        }
        if lhs.latestAt != rhs.latestAt {
            return (lhs.latestAt ?? .distantPast) > (rhs.latestAt ?? .distantPast)
        }
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }
}

private func opsBuildThreadPressureDigests(_ threads: [OpsCenterThreadSummary]) -> [OpsCenterThreadPressureDigest] {
    let grouped = Dictionary(grouping: threads, by: opsPrimaryThreadPressureMode)

    return grouped.compactMap { mode, items -> OpsCenterThreadPressureDigest? in
        guard let leadThread = items.max(by: { lhs, rhs in
            if lhs.hotspotScore != rhs.hotspotScore {
                return lhs.hotspotScore < rhs.hotspotScore
            }
            return (lhs.lastUpdatedAt ?? .distantPast) < (rhs.lastUpdatedAt ?? .distantPast)
        }) else {
            return nil
        }

        let hotspotThreadCount = items.filter(opsThreadIsHotspot).count
        let approvalPressure = items.reduce(0) { $0 + $1.pendingApprovalCount }
        let blockedThreadCount = items.filter { $0.blockedTaskCount > 0 || $0.status == "blocked" }.count
        let runtimeFailureCount = items.filter {
            ($0.relatedSession?.failedDispatchCount ?? 0) > 0 || $0.failedMessageCount > 0
        }.count
        let runtimeBacklogCount = items.filter {
            guard let session = $0.relatedSession else { return false }
            return session.queuedDispatchCount > 0 || session.inflightDispatchCount > 0 || session.isPrimaryRuntimeSession
        }.count
        let totalHotspotScore = items.reduce(0) { $0 + $1.hotspotScore }
        let latestAt = items.compactMap(\.lastUpdatedAt).max()

        let detailText: String
        switch mode {
        case .approval:
            detailText = LocalizedString.format("thread_pressure_approval_detail", approvalPressure)
        case .blocked:
            detailText = LocalizedString.format("thread_pressure_blocked_detail", blockedThreadCount)
        case .runtimeFailure:
            detailText = LocalizedString.format("thread_pressure_runtime_failure_detail", runtimeFailureCount)
        case .runtimeBacklog:
            detailText = LocalizedString.format("thread_pressure_runtime_backlog_detail", runtimeBacklogCount)
        case .activeWork:
            detailText = LocalizedString.text("thread_pressure_active_work_detail")
        case .stable:
            detailText = LocalizedString.text("thread_pressure_stable_detail")
        }

        return OpsCenterThreadPressureDigest(
            key: mode.rawValue,
            mode: mode,
            title: mode.title,
            detailText: detailText,
            threadCount: items.count,
            hotspotThreadCount: hotspotThreadCount,
            approvalPressure: approvalPressure,
            blockedThreadCount: blockedThreadCount,
            runtimeFailureCount: runtimeFailureCount,
            runtimeBacklogCount: runtimeBacklogCount,
            totalHotspotScore: totalHotspotScore,
            latestAt: latestAt,
            leadThreadID: leadThread.threadID
        )
    }
    .sorted { lhs, rhs in
        if lhs.totalHotspotScore != rhs.totalHotspotScore {
            return lhs.totalHotspotScore > rhs.totalHotspotScore
        }
        if lhs.threadCount != rhs.threadCount {
            return lhs.threadCount > rhs.threadCount
        }
        if lhs.latestAt != rhs.latestAt {
            return (lhs.latestAt ?? .distantPast) > (rhs.latestAt ?? .distantPast)
        }
        return lhs.mode.rawValue < rhs.mode.rawValue
    }
}

private func opsBuildThreadSessionDigests(_ threads: [OpsCenterThreadSummary]) -> [OpsCenterThreadSessionDigest] {
    let grouped = Dictionary(grouping: threads) { thread -> String in
        opsNormalizedSessionID(thread.relatedSession?.sessionID) ?? "detached"
    }

    return grouped.compactMap { key, items in
        guard let leadThread = items.max(by: { lhs, rhs in
            if lhs.hotspotScore != rhs.hotspotScore {
                return lhs.hotspotScore < rhs.hotspotScore
            }
            return (lhs.lastUpdatedAt ?? .distantPast) < (rhs.lastUpdatedAt ?? .distantPast)
        }) else {
            return nil
        }

        let leadSession = items.compactMap(\.relatedSession).max(by: { lhs, rhs in
            let lhsScore = lhs.failedDispatchCount * 6 + lhs.inflightDispatchCount * 4 + lhs.queuedDispatchCount * 3
            let rhsScore = rhs.failedDispatchCount * 6 + rhs.inflightDispatchCount * 4 + rhs.queuedDispatchCount * 3
            if lhsScore != rhsScore {
                return lhsScore < rhsScore
            }
            return (lhs.lastUpdatedAt ?? .distantPast) < (rhs.lastUpdatedAt ?? .distantPast)
        })

        let threadCount = items.count
        let hotspotThreadCount = items.filter(opsThreadIsHotspot).count
        let approvalPressure = items.reduce(0) { $0 + $1.pendingApprovalCount }
        let latestAt = items.compactMap(\.lastUpdatedAt).max()

        let title = leadSession.map { LocalizedString.format("thread_session_title", String($0.sessionID.prefix(12))) } ?? LocalizedString.text("detached_threads_title")
        let detailText: String
        if let leadSession, leadSession.failedDispatchCount > 0 {
            detailText = leadSession.latestFailureText ?? LocalizedString.format("thread_session_failure_detail", leadSession.failedDispatchCount)
        } else if let leadSession, leadSession.queuedDispatchCount > 0 || leadSession.inflightDispatchCount > 0 {
            detailText = LocalizedString.text("thread_session_runtime_detail")
        } else if approvalPressure > 0 {
            detailText = LocalizedString.format("thread_session_approval_detail", approvalPressure)
        } else {
            detailText = LocalizedString.text("thread_session_context_detail")
        }

        return OpsCenterThreadSessionDigest(
            key: key,
            title: title,
            detailText: detailText,
            threadCount: threadCount,
            hotspotThreadCount: hotspotThreadCount,
            approvalPressure: approvalPressure,
            queuedDispatchCount: leadSession?.queuedDispatchCount ?? 0,
            inflightDispatchCount: leadSession?.inflightDispatchCount ?? 0,
            failedDispatchCount: leadSession?.failedDispatchCount ?? 0,
            latestAt: latestAt,
            leadThreadID: leadThread.threadID,
            sessionID: leadSession?.sessionID
        )
    }
    .sorted { lhs, rhs in
        let lhsScore = lhs.failedDispatchCount * 6 + lhs.inflightDispatchCount * 4 + lhs.queuedDispatchCount * 3 + lhs.approvalPressure * 2 + lhs.hotspotThreadCount
        let rhsScore = rhs.failedDispatchCount * 6 + rhs.inflightDispatchCount * 4 + rhs.queuedDispatchCount * 3 + rhs.approvalPressure * 2 + rhs.hotspotThreadCount
        if lhsScore != rhsScore {
            return lhsScore > rhsScore
        }
        if lhs.threadCount != rhs.threadCount {
            return lhs.threadCount > rhs.threadCount
        }
        if lhs.latestAt != rhs.latestAt {
            return (lhs.latestAt ?? .distantPast) > (rhs.latestAt ?? .distantPast)
        }
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }
}

private func opsNormalizedSessionID(_ rawValue: String?) -> String? {
    let trimmed = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? nil : trimmed
}

private func opsNormalizedToolIdentifier(_ rawValue: String?) -> String? {
    let trimmed = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? nil : trimmed.lowercased()
}

private func opsLeadLinkedSessionID(
    spanIDs: [UUID],
    executionResultsByID: [UUID: ExecutionResult]
) -> String? {
    let sessionIDs = spanIDs.compactMap { spanID in
        opsNormalizedSessionID(executionResultsByID[spanID]?.sessionID)
    }
    guard !sessionIDs.isEmpty else { return nil }

    let counts = sessionIDs.reduce(into: [String: Int]()) { partial, sessionID in
        partial[sessionID, default: 0] += 1
    }

    return counts.max { lhs, rhs in
        if lhs.value != rhs.value {
            return lhs.value < rhs.value
        }
        return lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedDescending
    }?.key
}

private func opsLeadLinkedNodeID(
    spanIDs: [UUID],
    executionResultsByID: [UUID: ExecutionResult]
) -> UUID? {
    let nodeIDs = spanIDs.compactMap { spanID in
        executionResultsByID[spanID]?.nodeID
    }
    guard !nodeIDs.isEmpty else { return nil }

    let counts = nodeIDs.reduce(into: [UUID: Int]()) { partial, nodeID in
        partial[nodeID, default: 0] += 1
    }

    return counts.max { lhs, rhs in
        if lhs.value != rhs.value {
            return lhs.value < rhs.value
        }
        return lhs.key.uuidString.localizedCaseInsensitiveCompare(rhs.key.uuidString) == .orderedDescending
    }?.key
}

private func opsLinkedToolSpanIDs(
    toolIdentifier: String,
    snapshot: OpsAnalyticsSnapshot,
    projections: OpsCenterProjectionBundle?
) -> [UUID] {
    let liveSpanIDs = snapshot.anomalyRows.compactMap { anomaly -> UUID? in
        guard opsNormalizedToolIdentifier(anomaly.sourceService) == opsNormalizedToolIdentifier(toolIdentifier) else {
            return nil
        }
        return anomaly.linkedSessionSpanID
    }

    let projectedEntry = projections?.toolEntries().first { entry in
        opsNormalizedToolIdentifier(entry.toolIdentifier) == opsNormalizedToolIdentifier(toolIdentifier)
    }
    let projectedSpanIDs = (projectedEntry?.anomalies ?? []).compactMap { anomaly in
        anomaly.linkedSpanID ?? anomaly.relatedRunID.flatMap(UUID.init(uuidString:))
    }

    return liveSpanIDs + projectedSpanIDs
}

private func opsBuildThreadPressureTimelineDigests(_ threads: [OpsCenterThreadSummary]) -> [OpsCenterThreadPressureTimelineDigest] {
    let datedThreads = threads.compactMap { thread -> (OpsCenterThreadSummary, Date)? in
        let activityAt = thread.lastUpdatedAt ?? thread.startedAt
        guard let activityAt else { return nil }
        return (thread, activityAt)
    }
    guard let latestActivityAt = datedThreads.map(\.1).max() else { return [] }

    let calendar = Calendar.current
    let latestBucketStart = calendar.dateInterval(of: .hour, for: latestActivityAt)?.start ?? latestActivityAt

    return (0..<6).compactMap { offset -> OpsCenterThreadPressureTimelineDigest? in
        guard let bucketStart = calendar.date(byAdding: .hour, value: -offset, to: latestBucketStart),
              let bucketEnd = calendar.date(byAdding: .hour, value: 1, to: bucketStart) else {
            return nil
        }

        let bucketThreads = datedThreads
            .filter { _, activityAt in activityAt >= bucketStart && activityAt < bucketEnd }
            .map(\.0)

        guard let leadThread = bucketThreads.max(by: { lhs, rhs in
            if lhs.hotspotScore != rhs.hotspotScore {
                return lhs.hotspotScore < rhs.hotspotScore
            }
            return (lhs.lastUpdatedAt ?? lhs.startedAt ?? .distantPast) < (rhs.lastUpdatedAt ?? rhs.startedAt ?? .distantPast)
        }) else {
            return nil
        }

        let hotspotThreadCount = bucketThreads.filter(opsThreadIsHotspot).count
        let approvalPressure = bucketThreads.reduce(0) { $0 + $1.pendingApprovalCount }
        let blockedThreadCount = bucketThreads.filter { $0.blockedTaskCount > 0 || $0.status == "blocked" }.count
        let runtimeLinkedThreadCount = bucketThreads.filter(opsThreadHasRuntimePressure).count
        let latestAt = bucketThreads.compactMap(\.lastUpdatedAt).max()
        let title: String
        if offset == 0 {
            title = LocalizedString.text("thread_timeline_current_hour")
        } else {
            title = LocalizedString.format("thread_timeline_hours_ago", offset)
        }

        let detailText: String
        if approvalPressure > 0 {
            detailText = LocalizedString.format("thread_timeline_approval_detail", approvalPressure)
        } else if blockedThreadCount > 0 {
            detailText = LocalizedString.format("thread_timeline_blocked_detail", blockedThreadCount)
        } else if runtimeLinkedThreadCount > 0 {
            detailText = LocalizedString.format("thread_timeline_runtime_detail", runtimeLinkedThreadCount)
        } else {
            detailText = LocalizedString.text("thread_timeline_stable_detail")
        }

        return OpsCenterThreadPressureTimelineDigest(
            key: bucketStart.ISO8601Format(),
            title: title,
            detailText: detailText,
            threadCount: bucketThreads.count,
            hotspotThreadCount: hotspotThreadCount,
            approvalPressure: approvalPressure,
            blockedThreadCount: blockedThreadCount,
            runtimeLinkedThreadCount: runtimeLinkedThreadCount,
            latestAt: latestAt,
            leadThreadID: leadThread.threadID
        )
    }
}

private func opsCronRunIsFailure(_ run: OpsCronRunRow) -> Bool {
    let normalizedStatus = run.statusText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if normalizedStatus.contains("fail") || normalizedStatus.contains("error") || normalizedStatus.contains("timeout") {
        return true
    }

    let delivery = run.deliveryStatus?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    return delivery.contains("fail") || delivery.contains("error") || delivery.contains("timeout")
}

private func opsProjectionDigestPriorityScore(_ digest: OpsCenterArchiveProjectionDocumentDigest) -> Int {
    let statusScore: Int
    switch digest.status {
    case .critical:
        statusScore = 30
    case .warning:
        statusScore = 20
    case .neutral:
        statusScore = 10
    case .healthy:
        statusScore = 0
    }

    let stalenessScore: Int
    if let generatedAt = digest.generatedAt {
        let hoursSinceGeneration = max(Int(Date().timeIntervalSince(generatedAt) / 3600), 0)
        stalenessScore = min(hoursSinceGeneration, 24)
    } else {
        stalenessScore = 24
    }

    return statusScore + stalenessScore
}

private func opsToolIdentifier(from anomaly: OpsAnomalyRow) -> String? {
    let sourceLabel = anomaly.sourceLabel.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let sourceService = anomaly.sourceService?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard sourceLabel == "tool" || sourceService.lowercased().contains("tool") else {
        return nil
    }
    return sourceService.isEmpty ? nil : sourceService
}

private func opsHealthStatusRank(_ status: OpsHealthStatus) -> Int {
    switch status {
    case .critical:
        return 0
    case .warning:
        return 1
    case .neutral:
        return 2
    case .healthy:
        return 3
    }
}

private func opsHistoryHealthColor(_ status: OpsHealthStatus) -> Color {
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

private func opsHistoryStatusColor(_ rawValue: String) -> Color {
    switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "completed", "success", "ok":
        return .green
    case "failed", "error", "critical":
        return .red
    case "running", "in_progress", "in progress":
        return .orange
    case "waiting", "pending", "queued":
        return .yellow
    default:
        return .secondary
    }
}

private func opsTraceStatusRank(_ rawValue: String) -> Int {
    switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "failed":
        return 0
    case "waiting":
        return 1
    case "running":
        return 2
    case "idle":
        return 3
    case "completed":
        return 4
    default:
        return 5
    }
}
