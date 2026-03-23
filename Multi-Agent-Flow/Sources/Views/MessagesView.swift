//
//  MessagesView.swift
//  Multi-Agent-Flow
//

import SwiftUI

enum WorkbenchInteractionMode: String, CaseIterable, Identifiable {
    case chat
    case run

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chat:
            return "Chat"
        case .run:
            return "Run"
        }
    }

    var subtitle: String {
        executionIntent.semanticType.displayTitle
    }

    var executionIntent: OpenClawRuntimeExecutionIntent {
        switch self {
        case .chat:
            return .conversationAutonomous
        case .run:
            return .workflowControlled
        }
    }

    var threadType: RuntimeSessionSemanticType {
        executionIntent.semanticType
    }

    var threadMode: WorkbenchThreadSemanticMode {
        switch self {
        case .chat:
            return .autonomousConversation
        case .run:
            return .controlledRun
        }
    }

    var submitButtonTitle: String {
        switch self {
        case .chat:
            return LocalizedString.text("send_to_workflow")
        case .run:
            return "Run Workflow"
        }
    }
}

struct MessagesView: View {
    @ObservedObject var messageManager: MessageManager

    var body: some View {
        WorkbenchConversationView(messageManager: messageManager)
    }
}

struct WorkbenchConversationView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var messageManager: MessageManager

    @State private var selectedWorkflowID: UUID?
    @State private var dashboardLayout: WorkbenchDashboardLayout = .sideBySide
    @State private var lastCombinedLayout: WorkbenchDashboardLayout = .sideBySide
    @State private var runtimeConfigPanelMode: WorkbenchRuntimeConfigPanelMode = .storedDefault
    @State private var runtimeConfigExpandedHeight: CGFloat = SettingsManager.shared.workbenchRuntimeConfigPanelExpandedHeight
    @State private var runtimeConfigHeightDragOrigin: CGFloat?
    @State private var prompt = ""
    @State private var errorText: String?
    @State private var pendingAutoScrollWorkItem: DispatchWorkItem?
    @State private var availableModels: [String] = []
    @State private var runtimeConfigDrafts: [UUID: AgentRuntimeConfigurationRecord] = [:]
    @State private var runtimeInventoryRecords: [UUID: AgentRuntimeConfigurationRecord] = [:]
    @State private var runtimeConfigMessage: String?
    @State private var runtimeConfigTone: WorkbenchRuntimeConfigTone = .neutral
    @State private var isRefreshingRuntimeConfigurations = false
    @State private var applyingRuntimeConfigurationAgentID: UUID?
    @State private var manualChannelDrafts: [UUID: String] = [:]
    @State private var manualAccountDrafts: [UUID: String] = [:]
    @State private var activeRuntimePreparationAction: WorkbenchRuntimePreparationAction?
    @State private var submitMode: WorkbenchInteractionMode = .chat

    private let compactRuntimeConfigBodyHeight: CGFloat = 146
    private let minimumExpandedRuntimeConfigHeight: CGFloat = 240
    private let maximumExpandedRuntimeConfigHeight: CGFloat = 560

    private var project: MAProject? { appState.currentProject }
    private var workflows: [Workflow] { project?.workflows ?? [] }
    private var availableChannelAccounts: [OpenClawChannelAccountRecord] {
        project?.openClaw.availableChannelAccounts ?? appState.openClawManager.availableChannelAccounts
    }

    private var isRuntimePreparationBusy: Bool {
        activeRuntimePreparationAction != nil || appState.isApplyingWorkflowConfiguration || appState.isSyncingOpenClawSession
    }

    private var canRefreshRuntimeInventory: Bool {
        project != nil
            && !isRefreshingRuntimeConfigurations
            && !isRuntimePreparationBusy
            && appState.openClawManager.config.deploymentKind != .remoteServer
            && appState.openClawManager.isConnected
            && appState.isCurrentProjectAttachedToOpenClaw
            && appState.isProjectMirrorPrepared
    }

    private var hasAgentsMissingManagedPath: Bool {
        workflowAgents.contains { agent in
            !(appState.runtimePreparationState(for: agent.id)?.hasManagedPath ?? false)
        }
    }

    private var runtimePreparationSummary: String? {
        guard appState.openClawManager.config.deploymentKind != .remoteServer else {
            return LocalizedString.text("runtime_config_remote_unsupported")
        }

        if !appState.openClawManager.isConnected {
            return LocalizedString.text("runtime_config_hint_connect")
        }
        if !appState.isCurrentProjectAttachedToOpenClaw {
            return LocalizedString.text("runtime_config_hint_attach")
        }
        if !appState.isProjectMirrorPrepared {
            return LocalizedString.text("runtime_config_hint_prepare_mirror")
        }
        if hasAgentsMissingManagedPath {
            return LocalizedString.text("runtime_config_hint_managed_path")
        }
        if appState.hasPendingOpenClawSessionSync {
            return LocalizedString.text("workflow_apply_sync_current_session_hint")
        }
        return nil
    }

    private var runtimeConfigurationSummaryText: String {
        if let runtimeConfigMessage, !runtimeConfigMessage.isEmpty {
            return runtimeConfigMessage
        }
        if let runtimePreparationSummary, !runtimePreparationSummary.isEmpty {
            return runtimePreparationSummary
        }
        return LocalizedString.format("runtime_config_summary_agents", workflowAgents.count)
    }

    private var runtimeConfigurationBodyHeight: CGFloat {
        switch runtimeConfigPanelMode {
        case .hidden:
            return 0
        case .compact:
            return compactRuntimeConfigBodyHeight
        case .expanded:
            return clampedRuntimeConfigExpandedHeight(runtimeConfigExpandedHeight)
        }
    }

    private var showsRuntimeConfigurationEditor: Bool {
        runtimeConfigPanelMode == .expanded
    }

    private var shouldAutoCollapseRuntimeConfigurationPanel: Bool {
        runtimeConfigPanelMode == .expanded
    }

    private var runtimeConfigurationPrimaryActionTitle: String? {
        guard let action = recommendedRuntimePreparationAction else { return nil }
        return runtimePreparationActionTitle(action)
    }

    private var recommendedRuntimePreparationAction: WorkbenchRuntimePreparationAction? {
        guard appState.openClawManager.config.deploymentKind != .remoteServer else { return nil }

        switch appState.currentOpenClawRuntimeControlPlaneEntry.gate {
        case .probe:
            return .connect
        case .bind:
            return .attach
        case .publish:
            if !appState.isProjectMirrorPrepared || appState.hasPendingWorkflowConfiguration || hasAgentsMissingManagedPath {
                return .prepareMirror
            }
            if appState.hasPendingOpenClawSessionSync {
                return .syncSession
            }
            return nil
        case .execute:
            return nil
        }
    }

    private var canConnectRuntimePreparation: Bool {
        project != nil
            && hasOpenClawConfiguration
            && activeRuntimePreparationAction == nil
            && !appState.openClawManager.isConnected
    }

    private var canAttachRuntimePreparation: Bool {
        project != nil
            && activeRuntimePreparationAction == nil
            && appState.openClawManager.config.deploymentKind != .remoteServer
            && appState.openClawManager.isConnected
            && !appState.isCurrentProjectAttachedToOpenClaw
    }

    private var canPrepareMirrorRuntimePreparation: Bool {
        project != nil
            && activeRuntimePreparationAction == nil
            && !appState.isApplyingWorkflowConfiguration
            && appState.openClawManager.config.deploymentKind != .remoteServer
            && appState.openClawManager.isConnected
            && appState.isCurrentProjectAttachedToOpenClaw
            && (!appState.isProjectMirrorPrepared || appState.hasPendingWorkflowConfiguration || hasAgentsMissingManagedPath)
    }

    private var canSyncRuntimePreparation: Bool {
        activeRuntimePreparationAction == nil && appState.canSyncOpenClawSessionFromWorkflow
    }

    private var selectedWorkflow: Workflow? {
        if let selectedWorkflowID {
            return workflows.first { $0.id == selectedWorkflowID }
        }
        return workflows.first
    }

    private var workflowAgents: [Agent] {
        guard let selectedWorkflow, let project else { return [] }

        var seen = Set<UUID>()
        return selectedWorkflow.nodes
            .filter { $0.type == .agent }
            .compactMap(\.agentID)
            .filter { seen.insert($0).inserted }
            .compactMap { agentID in
                project.agents.first(where: { $0.id == agentID })
            }
    }

    private var isWorkbenchRuntimeAvailable: Bool {
        appState.openClawManager.canRunConversation || appState.openClawManager.canRunWorkflow
    }

    private var canSubmitCurrentMode: Bool {
        switch submitMode {
        case .chat:
            return appState.openClawManager.canRunConversation
        case .run:
            return appState.openClawManager.canRunWorkflow
        }
    }

    private var openClawRuntimeBadgeTitle: String {
        if appState.openClawManager.isConnected {
            return LocalizedString.text("openclaw_connected")
        }
        if appState.openClawManager.connectionState.isRunnableWithDegradedCapabilities {
            return LocalizedString.text("openclaw_degraded")
        }
        return LocalizedString.text("openclaw_disconnected")
    }

    private var openClawRuntimeBadgeColor: Color {
        if appState.openClawManager.isConnected {
            return .green
        }
        if appState.openClawManager.connectionState.isRunnableWithDegradedCapabilities {
            return .orange
        }
        return .red
    }

    private var workbenchMessages: [Message] {
        messageManager.workbenchMessages(for: selectedWorkflow?.id)
    }

    private var lastWorkbenchMessageSignature: String {
        guard let last = workbenchMessages.last else { return "empty" }
        return [
            last.id.uuidString,
            String(last.content.count),
            last.metadata["thinking"] ?? "false",
            last.inferredOutputType ?? "",
            last.runtimeEvent?.eventType.rawValue ?? ""
        ].joined(separator: "|")
    }

    private var currentExecutingNodeID: UUID? {
        guard appState.openClawService.isExecuting else { return nil }
        return appState.openClawService.executionLogs
            .reversed()
            .first(where: { $0.nodeID != nil && $0.message.hasPrefix("Executing node") })?
            .nodeID
    }

    private var latestResultByNodeID: [UUID: ExecutionResult] {
        guard let workflow = selectedWorkflow else { return [:] }
        let nodeIDs = Set(workflow.nodes.map(\.id))
        var mapping: [UUID: ExecutionResult] = [:]
        for result in appState.openClawService.executionResults.reversed() where nodeIDs.contains(result.nodeID) {
            if mapping[result.nodeID] == nil {
                mapping[result.nodeID] = result
            }
        }
        return mapping
    }

    private var workflowFlowReceipts: [WorkflowFlowReceipt] {
        guard let workflow = selectedWorkflow else { return [] }
        let nodeByID = Dictionary(uniqueKeysWithValues: workflow.nodes.map { ($0.id, $0) })

        return workflow.edges.compactMap { edge in
            guard let fromNode = nodeByID[edge.fromNodeID],
                  let toNode = nodeByID[edge.toNodeID] else {
                return nil
            }

            let fromStatus = nodeExecutionStatus(for: fromNode, in: workflow)
            let toStatus = nodeExecutionStatus(for: toNode, in: workflow)
            return WorkflowFlowReceipt(
                id: edge.id,
                fromName: nodeDisplayName(fromNode),
                toName: nodeDisplayName(toNode),
                fromStatus: fromStatus,
                toStatus: toStatus,
                flowStatus: flowStatus(from: fromStatus, to: toStatus)
            )
        }
        .sorted { lhs, rhs in
            if lhs.flowStatus.priority == rhs.flowStatus.priority {
                return lhs.fromName.localizedCaseInsensitiveCompare(rhs.fromName) == .orderedAscending
            }
            return lhs.flowStatus.priority < rhs.flowStatus.priority
        }
    }

    private var hasOpenClawConfiguration: Bool {
        let config = appState.openClawManager.config
        switch config.deploymentKind {
        case .local:
            return !config.requiresExplicitLocalBinaryPath
                || !config.localBinaryPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .remoteServer:
            return !config.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .container:
            return !config.container.containerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var hasExecutableWorkflow: Bool {
        entryConnectedAgentCount > 0
    }

    private var entryConnectedAgentCount: Int {
        guard let workflow = selectedWorkflow else { return 0 }

        let nodeByID = Dictionary(uniqueKeysWithValues: workflow.nodes.map { ($0.id, $0) })
        let startNode = workflow.nodes.first { $0.type == .start }
        guard let startNode else { return 0 }

        let agentIDs = Set(
            workflow.edges
                .filter { $0.isOutgoing(from: startNode.id) }
                .compactMap { edge in
                    let targetNodeID = edge.fromNodeID == startNode.id ? edge.toNodeID : edge.fromNodeID
                    return nodeByID[targetNodeID]?.agentID
                }
        )
        return agentIDs.count
    }

    private var canStopActiveRemoteConversation: Bool {
        let runID = appState.openClawService.activeGatewayRunID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let sessionKey = appState.openClawService.activeGatewaySessionKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !runID.isEmpty && !sessionKey.isEmpty
    }

    private var isStoppingActiveRemoteConversation: Bool {
        appState.openClawService.isAbortingActiveGatewayRun
    }

    var body: some View {
        Group {
            if project == nil {
                WorkbenchEmptyState(
                    title: LocalizedString.text("workbench_empty_setup_title"),
                    description: LocalizedString.text("workbench_empty_setup_desc"),
                    primaryTitle: LocalizedString.text("configure_openclaw"),
                    primaryAction: { NotificationCenter.default.post(name: .openSettings, object: nil) },
                    secondaryTitle: LocalizedString.newProject,
                    secondaryAction: { appState.createNewProject() }
                )
            } else if !isWorkbenchRuntimeAvailable {
                WorkbenchEmptyState(
                    title: LocalizedString.text("workbench_empty_connect_title"),
                    description: LocalizedString.text("workbench_empty_connect_desc"),
                    primaryTitle: LocalizedString.text("connect_openclaw"),
                    primaryAction: { appState.connectOpenClaw() },
                    secondaryTitle: LocalizedString.text("open_settings"),
                    secondaryAction: { NotificationCenter.default.post(name: .openSettings, object: nil) }
                )
            } else if workflows.isEmpty {
                WorkbenchEmptyState(
                    title: LocalizedString.text("workbench_empty_no_workflow_title"),
                    description: LocalizedString.text("workbench_empty_no_workflow_desc"),
                    primaryTitle: LocalizedString.text("create_main_workflow"),
                    primaryAction: { _ = appState.ensureMainWorkflow() },
                    secondaryTitle: LocalizedString.saveProject,
                    secondaryAction: { appState.saveProject() }
                )
            } else if !hasExecutableWorkflow {
                WorkbenchEmptyState(
                    title: LocalizedString.text("workbench_empty_not_executable_title"),
                    description: LocalizedString.text("workbench_empty_not_executable_desc"),
                    primaryTitle: LocalizedString.text("import_project_agents"),
                    primaryAction: { appState.generateArchitectureFromProjectAgents() },
                    secondaryTitle: LocalizedString.text("configure_openclaw"),
                    secondaryAction: { NotificationCenter.default.post(name: .openSettings, object: nil) }
                )
            } else {
                content
            }
        }
        .onAppear {
            runtimeConfigExpandedHeight = clampedRuntimeConfigExpandedHeight(runtimeConfigExpandedHeight)
            if selectedWorkflowID == nil {
                selectedWorkflowID = workflows.first?.id
            }
            appState.refreshWorkbenchHistory(for: selectedWorkflowID)
            refreshRuntimeConfigurationDataIfNeeded()
        }
        .onChange(of: workflows.map(\.id)) { _, newValue in
            guard let firstID = newValue.first else { return }
            if selectedWorkflowID == nil || !newValue.contains(selectedWorkflowID ?? firstID) {
                selectedWorkflowID = firstID
            }
            appState.refreshWorkbenchHistory(for: selectedWorkflowID)
            refreshRuntimeConfigurationDataIfNeeded(force: true)
        }
        .onChange(of: selectedWorkflowID) { _, newValue in
            appState.refreshWorkbenchHistory(for: newValue)
            refreshRuntimeConfigurationDataIfNeeded(force: true)
        }
        .onChange(of: appState.openClawManager.canReadSessionHistory) { _, canReadSessionHistory in
            guard canReadSessionHistory else { return }
            appState.refreshWorkbenchHistory(for: selectedWorkflowID)
        }
        .onChange(of: appState.openClawManager.isConnected) { _, _ in
            refreshRuntimeConfigurationDataIfNeeded(force: true)
        }
        .onChange(of: appState.currentProject?.id) { _, _ in
            refreshRuntimeConfigurationDataIfNeeded(force: true)
        }
        .onChange(of: dashboardLayout) { _, newValue in
            if newValue != .dashboardOnly {
                lastCombinedLayout = newValue
            }
        }
    }

    private var content: some View {
        GeometryReader { geometry in
            let availableWidth = max(geometry.size.width, 0)

            VStack(spacing: 0) {
                header(availableWidth: availableWidth)

                Divider()

                if !hasOpenClawConfiguration {
                    openClawBanner
                    Divider()
                }

                runtimeConfigurationPanel

                Divider()

                workbenchAndDashboardPane(availableWidth: availableWidth)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func header(availableWidth: CGFloat) -> some View {
        let usesCompactHeader = availableWidth < 1_040

        return VStack(alignment: .leading, spacing: 12) {
            if usesCompactHeader {
                compactHeaderContent
            } else {
                regularHeaderContent
            }

            if let workflow = selectedWorkflow {
                workflowSummaryBadges(for: workflow, compact: usesCompactHeader)
            }
        }
        .padding()
    }

    private var regularHeaderContent: some View {
        HStack {
            workbenchTitleBlock

            Spacer()

            workflowPicker
                .frame(width: 220)

            layoutPicker
                .frame(width: 170)

            dashboardLayoutButtons

            runtimeStatusBadges

            Button(LocalizedString.saveProject) {
                appState.saveProject()
            }
            .buttonStyle(.bordered)
        }
    }

    private var compactHeaderContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                workbenchTitleBlock
                Spacer(minLength: 12)
                Button(LocalizedString.saveProject) {
                    appState.saveProject()
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 10) {
                workflowPicker
                    .frame(maxWidth: .infinity)

                layoutPicker
                    .frame(width: 170)
            }

            VStack(alignment: .leading, spacing: 8) {
                dashboardLayoutButtons
                runtimeStatusBadges
            }
        }
    }

    private var workbenchTitleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(LocalizedString.text("workbench_title"))
                .font(.title2)
            Text(LocalizedString.text("workbench_subtitle"))
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var workflowPicker: some View {
        Picker(LocalizedString.text("workflow_picker_label"), selection: $selectedWorkflowID) {
            ForEach(workflows) { workflow in
                Text(workflow.name).tag(workflow.id as UUID?)
            }
        }
    }

    private var layoutPicker: some View {
        Picker(LocalizedString.text("layout_picker_label"), selection: $dashboardLayout) {
            ForEach(WorkbenchDashboardLayout.allCases) { layout in
                Text(layout.title).tag(layout)
            }
        }
        .pickerStyle(.segmented)
    }

    private var dashboardLayoutButtons: some View {
        HStack(spacing: 4) {
            Button(action: shrinkDashboard) {
                Image(systemName: "minus.magnifyingglass")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(LocalizedString.text("dashboard_with_workbench"))
            .disabled(dashboardLayout != .dashboardOnly)

            Button(action: expandDashboard) {
                Image(systemName: "plus.magnifyingglass")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(LocalizedString.text("dashboard_only"))
            .disabled(dashboardLayout == .dashboardOnly)
        }
    }

    private var runtimeStatusBadges: some View {
        HStack(spacing: 8) {
            statusBadge(title: openClawRuntimeBadgeTitle, color: openClawRuntimeBadgeColor)
            statusBadge(
                title: appState.openClawRuntimeControlPlaneBadgeTitle,
                color: appState.openClawRuntimeControlPlaneBadgeColor
            )
            statusBadge(
                title: appState.openClawService.isExecuting ? LocalizedString.text("workflow_running") : LocalizedString.text("workflow_idle"),
                color: appState.openClawService.isExecuting ? .orange : .secondary
            )
        }
    }

    @ViewBuilder
    private func workflowSummaryBadges(for workflow: Workflow, compact: Bool) -> some View {
        if compact {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    statusBadge(
                        title: LocalizedString.format("execution_nodes_count", workflow.nodes.filter { $0.type == .agent }.count),
                        color: .blue
                    )
                    statusBadge(title: LocalizedString.format("communication_links_count", workflow.edges.count), color: .purple)
                }
                statusBadge(title: LocalizedString.format("file_boundaries_count", workflow.boundaries.count), color: .orange)
            }
        } else {
            HStack(spacing: 8) {
                statusBadge(
                    title: LocalizedString.format("execution_nodes_count", workflow.nodes.filter { $0.type == .agent }.count),
                    color: .blue
                )
                statusBadge(title: LocalizedString.format("communication_links_count", workflow.edges.count), color: .purple)
                statusBadge(title: LocalizedString.format("file_boundaries_count", workflow.boundaries.count), color: .orange)
            }
        }
    }

    private var openClawBanner: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedString.text("openclaw_incomplete_config"))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(LocalizedString.text("openclaw_incomplete_config_desc"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(LocalizedString.text("configure_now")) {
                NotificationCenter.default.post(name: .openSettings, object: nil)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(Color.orange.opacity(0.08))
    }

    private var runtimeConfigurationPanel: some View {
        VStack(spacing: 0) {
            runtimeConfigurationPanelHeader

            if runtimeConfigPanelMode != .hidden {
                Divider()

                runtimeConfigurationPanelBody
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .frame(height: runtimeConfigurationBodyHeight, alignment: .topLeading)
                    .clipped()

                if runtimeConfigPanelMode == .expanded {
                    Divider()
                    runtimeConfigurationResizeHandle
                }
            }
        }
        .background(Color(.controlBackgroundColor).opacity(0.6))
    }

    private var runtimeConfigurationPanelHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(LocalizedString.text("runtime_config_title"))
                            .font(.headline)
                        Text(runtimeConfigPanelMode.label)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.14))
                            .clipShape(Capsule())
                    }

                    Text(
                        runtimeConfigPanelMode == .expanded
                            ? LocalizedString.text("runtime_config_subtitle")
                            : runtimeConfigurationSummaryText
                    )
                    .font(.caption)
                    .foregroundColor(
                        runtimeConfigPanelMode == .expanded
                            ? .secondary
                            : (runtimeConfigMessage == nil ? .secondary : runtimeConfigTone.color)
                    )
                    .lineLimit(runtimeConfigPanelMode == .expanded ? 2 : 1)
                }

                Spacer(minLength: 12)

                HStack(spacing: 8) {
                    if let runtimeConfigurationPrimaryActionTitle, runtimeConfigPanelMode == .hidden {
                        Button(runtimeConfigurationPrimaryActionTitle) {
                            performRecommendedRuntimePreparationAction()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }

                    if isRefreshingRuntimeConfigurations {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Button(LocalizedString.text("runtime_config_refresh")) {
                        refreshRuntimeConfigurationDataIfNeeded(force: true)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!canRefreshRuntimeInventory)

                    switch runtimeConfigPanelMode {
                    case .hidden:
                        Button(LocalizedString.text("runtime_config_expand")) {
                            setRuntimeConfigPanelMode(.expanded)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    case .compact:
                        Button(LocalizedString.text("runtime_config_expand")) {
                            setRuntimeConfigPanelMode(.expanded)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button(LocalizedString.text("runtime_config_hide")) {
                            setRuntimeConfigPanelMode(.hidden)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    case .expanded:
                        Button(LocalizedString.text("runtime_config_compact")) {
                            setRuntimeConfigPanelMode(.compact)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button(LocalizedString.text("runtime_config_hide")) {
                            setRuntimeConfigPanelMode(.hidden)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }

            runtimeConfigurationStatusBadges
        }
        .padding()
    }

    private var runtimeConfigurationStatusBadges: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                statusBadge(
                    title: appState.openClawManager.isConnected
                        ? LocalizedString.text("runtime_config_status_connected")
                        : LocalizedString.text("runtime_config_status_disconnected"),
                    color: appState.openClawManager.isConnected ? .green : .red
                )
                statusBadge(
                    title: appState.isCurrentProjectAttachedToOpenClaw
                        ? LocalizedString.text("runtime_config_status_attached")
                        : LocalizedString.text("runtime_config_status_unattached"),
                    color: appState.isCurrentProjectAttachedToOpenClaw ? .green : .orange
                )
                statusBadge(
                    title: appState.isProjectMirrorPrepared
                        ? LocalizedString.text("runtime_config_status_mirror_ready")
                        : LocalizedString.text("runtime_config_status_mirror_not_ready"),
                    color: appState.isProjectMirrorPrepared ? .green : .orange
                )
                statusBadge(
                    title: appState.isCurrentProjectRuntimeSessionSynchronized
                        ? LocalizedString.text("runtime_config_status_session_synced")
                        : LocalizedString.text("runtime_config_status_session_pending"),
                    color: appState.isCurrentProjectRuntimeSessionSynchronized ? .green : .orange
                )
            }
            .padding(.trailing, 1)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var runtimeConfigurationPanelBody: some View {
        ScrollView(showsIndicators: runtimeConfigPanelMode == .expanded) {
            VStack(alignment: .leading, spacing: 12) {
                if let runtimeConfigMessage, runtimeConfigPanelMode != .hidden {
                    Text(runtimeConfigMessage)
                        .font(.caption)
                        .foregroundColor(runtimeConfigTone.color)
                }

                if let runtimePreparationSummary {
                    Text(runtimePreparationSummary)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if appState.openClawManager.config.deploymentKind != .remoteServer {
                    FlowLayout(spacing: 8) {
                        runtimePreparationButton(
                            action: .connect,
                            title: LocalizedString.text("connect_openclaw"),
                            enabled: canConnectRuntimePreparation
                        ) {
                            connectOpenClawForRuntimeConfiguration()
                        }

                        runtimePreparationButton(
                            action: .attach,
                            title: LocalizedString.text("attach_current_project"),
                            enabled: canAttachRuntimePreparation
                        ) {
                            attachCurrentProjectForRuntimeConfiguration()
                        }

                        runtimePreparationButton(
                            action: .prepareMirror,
                            title: LocalizedString.text("apply_workflow_to_mirror"),
                            enabled: canPrepareMirrorRuntimePreparation
                        ) {
                            prepareMirrorForRuntimeConfiguration()
                        }

                        runtimePreparationButton(
                            action: .syncSession,
                            title: LocalizedString.text("sync_current_session"),
                            enabled: canSyncRuntimePreparation
                        ) {
                            syncCurrentSessionForRuntimeConfiguration()
                        }
                    }
                }

                if showsRuntimeConfigurationEditor {
                    if appState.openClawManager.config.deploymentKind == .remoteServer {
                        Text(LocalizedString.text("runtime_config_remote_unsupported"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else if workflowAgents.isEmpty {
                        Text(LocalizedString.text("runtime_config_no_agents"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(workflowAgents) { agent in
                                runtimeConfigurationCard(for: agent)
                            }
                        }
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var runtimeConfigurationResizeHandle: some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(Color.secondary.opacity(0.35))
                .frame(width: 44, height: 5)

            Text(LocalizedString.text("runtime_config_drag_hint"))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .gesture(runtimeConfigurationResizeGesture)
        .onTapGesture(count: 2) {
            resetRuntimeConfigExpandedHeight()
        }
    }

    @ViewBuilder
    private func runtimeConfigurationCard(for agent: Agent) -> some View {
        let preparation = appState.runtimePreparationState(for: agent.id)
        let draft = runtimeConfigDrafts[agent.id] ?? appState.runtimeConfiguration(for: agent.id)
        let isReadyForEditing = preparation?.canConfigure ?? false

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(agent.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(preparation?.managedPath ?? LocalizedString.text("runtime_config_managed_path_missing"))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                }

                Spacer()

                if let preparation {
                    statusBadge(
                        title: preparation.canConfigure
                            ? LocalizedString.text("runtime_config_ready")
                            : LocalizedString.text("runtime_config_pending"),
                        color: preparation.canConfigure ? .green : .orange
                    )
                }

                Button(LocalizedString.text("runtime_config_adopt_runtime")) {
                    adoptRuntimeInventory(for: agent.id)
                }
                .buttonStyle(.bordered)
                .disabled(runtimeInventoryRecords[agent.id] == nil || !isReadyForEditing || isRuntimePreparationBusy)

                Button(
                    applyingRuntimeConfigurationAgentID == agent.id
                        ? LocalizedString.text("runtime_config_applying")
                        : LocalizedString.text("runtime_config_apply")
                ) {
                    applyRuntimeConfiguration(for: agent.id)
                }
                .buttonStyle(.borderedProminent)
                .disabled(applyingRuntimeConfigurationAgentID != nil || !isReadyForEditing || isRuntimePreparationBusy)
            }

            if let preparation, !preparation.canConfigure {
                Text(runtimePreparationHint(for: preparation))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let draft {
                Group {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(LocalizedString.text("runtime_config_model"))
                            .font(.caption)
                            .foregroundColor(.secondary)

                        TextField(LocalizedString.text("runtime_config_model_placeholder"), text: modelBinding(for: agent.id, fallback: draft))
                            .textFieldStyle(.roundedBorder)

                        if !availableModels.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(modelSuggestions(for: draft), id: \.self) { model in
                                        Button(model) {
                                            var updated = draft
                                            updated.modelIdentifier = model
                                            persistRuntimeDraft(updated)
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                    }
                                }
                            }
                        }
                    }

                    Toggle(LocalizedString.text("runtime_config_channel_toggle"), isOn: channelEnabledBinding(for: agent.id, fallback: draft))

                    if draft.channelEnabled {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(LocalizedString.text("runtime_config_selected_channels"))
                                .font(.caption)
                                .foregroundColor(.secondary)

                            if draft.bindings.isEmpty {
                                Text(LocalizedString.text("runtime_config_no_bindings"))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                FlowLayout(spacing: 6) {
                                    ForEach(draft.bindings) { binding in
                                        HStack(spacing: 6) {
                                            Text("\(binding.channelID):\(binding.accountID)")
                                                .font(.caption)
                                            Button(action: {
                                                removeBinding(binding, for: agent.id)
                                            }) {
                                                Image(systemName: "xmark.circle.fill")
                                            }
                                            .buttonStyle(.plain)
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 5)
                                        .background(Color.accentColor.opacity(0.12))
                                        .clipShape(Capsule())
                                    }
                                }
                            }

                            if !availableChannelAccounts.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(LocalizedString.text("runtime_config_discovered_accounts"))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    ForEach(availableChannelAccounts) { account in
                                        Button(action: {
                                            toggleChannelAccount(account, for: agent.id)
                                        }) {
                                            HStack {
                                                Image(systemName: isBindingSelected(account, for: draft) ? "checkmark.circle.fill" : "circle")
                                                Text(account.displayName)
                                                    .lineLimit(1)
                                                Spacer()
                                                if account.isDefaultAccount {
                                                    Text("default")
                                                        .font(.caption2)
                                                        .foregroundColor(.secondary)
                                                }
                                            }
                                        }
                                        .buttonStyle(.borderless)
                                    }
                                }
                            }

                            HStack {
                                TextField(
                                    LocalizedString.text("runtime_config_manual_channel_placeholder"),
                                    text: Binding(
                                        get: { manualChannelDrafts[agent.id] ?? "" },
                                        set: { manualChannelDrafts[agent.id] = $0 }
                                    )
                                )
                                .textFieldStyle(.roundedBorder)

                                TextField(
                                    LocalizedString.text("runtime_config_manual_account_placeholder"),
                                    text: Binding(
                                        get: { manualAccountDrafts[agent.id] ?? "" },
                                        set: { manualAccountDrafts[agent.id] = $0 }
                                    )
                                )
                                .textFieldStyle(.roundedBorder)

                                Button(LocalizedString.text("runtime_config_add_binding")) {
                                    addManualBinding(for: agent.id)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }
                .disabled(!isReadyForEditing)
            }
        }
        .padding(12)
        .background(Color(.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func workbenchAndDashboardPane(availableWidth: CGFloat) -> some View {
        switch effectiveDashboardLayout(for: availableWidth) {
        case .sideBySide:
            HSplitView {
                dialogueAndReceiptsPane(availableWidth: max(availableWidth * 0.44, 420))
                    .frame(minWidth: 420, idealWidth: 520, maxWidth: 640)
                OpsCenterDashboardView(
                    displayMode: .embedded,
                    preferredWorkflowID: selectedWorkflow?.id
                )
                    .frame(minWidth: 320, idealWidth: 620, maxWidth: .infinity, maxHeight: .infinity)
            }
        case .topBottom:
            VSplitView {
                dialogueAndReceiptsPane(availableWidth: availableWidth)
                    .frame(minHeight: 280, idealHeight: 360)
                OpsCenterDashboardView(
                    displayMode: .embedded,
                    preferredWorkflowID: selectedWorkflow?.id
                )
                    .frame(minHeight: 280, idealHeight: 420)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .dashboardOnly:
            OpsCenterDashboardView(
                displayMode: .embedded,
                preferredWorkflowID: selectedWorkflow?.id
            )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func effectiveDashboardLayout(for availableWidth: CGFloat) -> WorkbenchDashboardLayout {
        guard dashboardLayout != .dashboardOnly else { return .dashboardOnly }
        if dashboardLayout == .topBottom {
            return .topBottom
        }
        return availableWidth < 1_280 ? .topBottom : .sideBySide
    }

    @ViewBuilder
    private func dialogueAndReceiptsPane(availableWidth: CGFloat) -> some View {
        Group {
            if availableWidth < 760 {
                VSplitView {
                    conversationPane
                        .frame(minHeight: 260, idealHeight: 360)

                    taskPanePanel
                        .frame(minHeight: 180, idealHeight: 230, maxHeight: 320)
                }
            } else {
                HStack(spacing: 0) {
                    conversationPane
                        .frame(minWidth: 240, idealWidth: 320, maxWidth: .infinity)

                    Divider()

                    taskPanePanel
                        .frame(minWidth: 180, idealWidth: 220, maxWidth: 320)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var taskPanePanel: some View {
        taskPane
            .background(Color(.controlBackgroundColor))
    }

    private var conversationPane: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if workbenchMessages.isEmpty {
                            ContentUnavailableView(
                                LocalizedString.text("no_conversation_tasks"),
                                systemImage: "bubble.left.and.exclamationmark.bubble.right",
                                description: Text(LocalizedString.text("no_conversation_tasks_desc"))
                            )
                            .frame(maxWidth: .infinity, minHeight: 280)
                        } else {
                            ForEach(workbenchMessages) { message in
                                WorkbenchMessageBubble(
                                    message: message,
                                    linkedTask: linkedTask(for: message)
                                )
                                .id(message.id)
                            }
                        }
                    }
                    .padding()
                }
                .textSelection(.enabled)
                .onChange(of: workbenchMessages.count) { _, _ in
                    scheduleAutoScroll(using: proxy, animated: true, debounce: 0)
                }
                .onChange(of: lastWorkbenchMessageSignature) { _, _ in
                    scheduleAutoScroll(using: proxy, animated: false, debounce: 0.08)
                }
                .onDisappear {
                    pendingAutoScrollWorkItem?.cancel()
                    pendingAutoScrollWorkItem = nil
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                if let errorText {
                    Text(errorText)
                        .font(.caption)
                        .foregroundColor(.red)
                }

                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Mode")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Picker("Mode", selection: $submitMode) {
                            ForEach(WorkbenchInteractionMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        Text(submitMode.subtitle)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    TextField(
                        LocalizedString.text("workbench_prompt_placeholder"),
                        text: $prompt,
                        axis: .vertical
                    )
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...8)
                    .onSubmit {
                        publishPrompt()
                    }

                    if !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(LocalizedString.text("markdown_preview"))
                                .font(.caption2)
                                .foregroundColor(.secondary)

                            ScrollView {
                                MarkdownText(prompt)
                                    .font(.caption)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(8)
                            }
                            .frame(minHeight: 64, maxHeight: 140)
                            .background(Color(.controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                }

                HStack {
                    Text(selectedWorkflow?.name ?? LocalizedString.text("no_workflow_selected"))
                        .font(.caption)
                        .foregroundColor(.secondary)

                Spacer()

                if canStopActiveRemoteConversation || isStoppingActiveRemoteConversation {
                    Button(LocalizedString.stopExecution) {
                        stopActiveRemoteConversation()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!canStopActiveRemoteConversation || isStoppingActiveRemoteConversation)
                }

                Button(submitMode.submitButtonTitle) {
                    publishPrompt()
                }
                .disabled(
                    prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || appState.openClawService.isExecuting
                            || !hasExecutableWorkflow
                            || !canSubmitCurrentMode
                    )
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding()
        }
    }

    private var taskPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(LocalizedString.text("flow_receipts"))
                    .font(.headline)
                Spacer()
                Text("\(workflowFlowReceipts.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if workflowFlowReceipts.isEmpty {
                        Text(LocalizedString.text("no_flow_receipts"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding()
                    } else {
                        ForEach(workflowFlowReceipts) { flow in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("\(flow.fromName) → \(flow.toName)")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .lineLimit(1)
                                    Spacer()
                                    statusBadge(title: flow.flowStatus.title, color: flow.flowStatus.color)
                                }

                                HStack(spacing: 8) {
                                    statusBadge(
                                        title: "\(flow.fromName): \(flow.fromStatus.icon) \(flow.fromStatus.title)",
                                        color: flow.fromStatus.color
                                    )
                                    Text("→")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    statusBadge(
                                        title: "\(flow.toName): \(flow.toStatus.icon) \(flow.toStatus.title)",
                                        color: flow.toStatus.color
                                    )
                                }

                                Text(LocalizedString.format("flow_status_prefix", flow.flowStatus.title))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                            }
                            .padding(10)
                            .background(Color(.windowBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                }
                .padding()
            }
            .textSelection(.enabled)
        }
    }

    private func linkedTask(for message: Message) -> Task? {
        guard let taskIDValue = message.metadata["taskID"],
              let taskID = UUID(uuidString: taskIDValue) else {
            return nil
        }
        return appState.taskManager.task(with: taskID)
    }

    private func nodeDisplayName(_ node: WorkflowNode) -> String {
        switch node.type {
        case .start:
            return node.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? LocalizedString.text("node_start_fallback") : node.title
        case .agent:
            if let agentID = node.agentID,
               let agent = project?.agents.first(where: { $0.id == agentID }) {
                return agent.name
            }
            return node.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? LocalizedString.text("node_agent_fallback") : node.title
        }
    }

    private func nodeExecutionStatus(for node: WorkflowNode, in workflow: Workflow) -> NodeExecutionDisplayStatus {
        if let state = appState.openClawService.executionState,
           state.workflowID == workflow.id {
            if state.failedNodes.contains(node.id) {
                return .failed
            }
            if state.completedNodes.contains(node.id) {
                return .completed
            }
            if currentExecutingNodeID == node.id {
                return .running
            }
            if node.type == .start,
               (!state.completedNodes.isEmpty || !state.failedNodes.isEmpty || currentExecutingNodeID != nil) {
                return .completed
            }
        }

        if let latest = latestResultByNodeID[node.id] {
            switch latest.status {
            case .failed:
                return .failed
            case .completed:
                return .completed
            case .running, .waiting:
                return .running
            case .idle:
                return .idle
            }
        }

        return .idle
    }

    private func flowStatus(from: NodeExecutionDisplayStatus, to: NodeExecutionDisplayStatus) -> WorkflowFlowStatus {
        if from == .failed || to == .failed {
            return .blocked
        }
        if to == .completed {
            return .completed
        }
        if from == .running || to == .running || (from == .completed && to == .idle) {
            return .inProgress
        }
        return .pending
    }

    private func publishPrompt() {
        errorText = nil
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else {
            errorText = LocalizedString.text("workbench_error_empty_prompt")
            return
        }

        guard hasExecutableWorkflow else {
            errorText = LocalizedString.text("workbench_error_unconnected_start")
            return
        }

        guard canSubmitCurrentMode else {
            errorText = LocalizedString.text("workbench_error_connect_openclaw")
            return
        }

        guard appState.submitWorkbenchPrompt(text, workflowID: selectedWorkflowID, mode: submitMode) else {
            errorText = appState.openClawService.isExecuting
                ? LocalizedString.text("workbench_error_busy")
                : LocalizedString.text("workbench_error_submit_failed")
            return
        }

        prompt = ""
    }

    private func stopActiveRemoteConversation() {
        errorText = nil
        appState.openClawService.abortActiveRemoteConversation()
    }

    private func scheduleAutoScroll(
        using proxy: ScrollViewProxy,
        animated: Bool,
        debounce: TimeInterval
    ) {
        pendingAutoScrollWorkItem?.cancel()

        let workItem = DispatchWorkItem {
            guard let lastID = workbenchMessages.last?.id else { return }
            if animated {
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo(lastID, anchor: .bottom)
                }
            } else {
                proxy.scrollTo(lastID, anchor: .bottom)
            }
        }

        pendingAutoScrollWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + debounce, execute: workItem)
    }

    private func statusBadge(title: String, color: Color) -> some View {
        Text(title)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .foregroundColor(color)
            .clipShape(Capsule())
    }

    private func expandDashboard() {
        if dashboardLayout != .dashboardOnly {
            lastCombinedLayout = dashboardLayout
        }
        dashboardLayout = .dashboardOnly
    }

    private func shrinkDashboard() {
        dashboardLayout = lastCombinedLayout
    }

    private func refreshRuntimeConfigurationDataIfNeeded(force: Bool = false) {
        guard canRefreshRuntimeInventory else {
            return
        }

        isRefreshingRuntimeConfigurations = true

        appState.openClawManager.loadAvailableModels { success, _, models in
            availableModels = success ? models : []
        }

        appState.refreshRuntimeConfigurationInventory { success, message, records, _ in
            isRefreshingRuntimeConfigurations = false
            runtimeConfigMessage = message
            runtimeConfigTone = success ? .success : .error

            guard success else { return }

            let inventory = Dictionary(uniqueKeysWithValues: records.map { ($0.agentID, $0) })
            runtimeInventoryRecords = inventory

            if force || runtimeConfigDrafts.isEmpty {
                runtimeConfigDrafts = inventory
            } else {
                for record in records {
                    if runtimeConfigDrafts[record.agentID] == nil {
                        runtimeConfigDrafts[record.agentID] = record
                    }
                }
            }
        }
    }

    private func persistRuntimeDraft(_ record: AgentRuntimeConfigurationRecord) {
        runtimeConfigDrafts[record.agentID] = record
        appState.upsertRuntimeConfiguration(record)
    }

    private func adoptRuntimeInventory(for agentID: UUID) {
        guard let inventoryRecord = runtimeInventoryRecords[agentID] else { return }
        persistRuntimeDraft(inventoryRecord)
        runtimeConfigMessage = LocalizedString.text("runtime_config_adopted_runtime")
        runtimeConfigTone = .success
    }

    private func applyRuntimeConfiguration(for agentID: UUID) {
        applyingRuntimeConfigurationAgentID = agentID
        runtimeConfigMessage = nil

        if let draft = runtimeConfigDrafts[agentID] {
            persistRuntimeDraft(draft)
        }

        appState.applyRuntimeConfiguration(for: agentID) { success, message, refreshedRecord in
            applyingRuntimeConfigurationAgentID = nil
            runtimeConfigMessage = message
            runtimeConfigTone = success ? .success : .error

            if let refreshedRecord {
                runtimeConfigDrafts[agentID] = refreshedRecord
                runtimeInventoryRecords[agentID] = refreshedRecord
            }

            if success {
                collapseRuntimeConfigurationPanelAfterSuccessfulAction()
                refreshRuntimeConfigurationDataIfNeeded(force: true)
            }
        }
    }

    private func runtimePreparationActionTitle(_ action: WorkbenchRuntimePreparationAction) -> String {
        switch action {
        case .connect:
            return LocalizedString.text("connect_openclaw")
        case .attach:
            return LocalizedString.text("attach_current_project")
        case .prepareMirror:
            return LocalizedString.text("apply_workflow_to_mirror")
        case .syncSession:
            return LocalizedString.text("sync_current_session")
        }
    }

    private func performRecommendedRuntimePreparationAction() {
        guard let action = recommendedRuntimePreparationAction else { return }

        switch action {
        case .connect:
            connectOpenClawForRuntimeConfiguration()
        case .attach:
            attachCurrentProjectForRuntimeConfiguration()
        case .prepareMirror:
            prepareMirrorForRuntimeConfiguration()
        case .syncSession:
            syncCurrentSessionForRuntimeConfiguration()
        }
    }

    @ViewBuilder
    private func runtimePreparationButton(
        action: WorkbenchRuntimePreparationAction,
        title: String,
        enabled: Bool,
        perform: @escaping () -> Void
    ) -> some View {
        if recommendedRuntimePreparationAction == action {
            Button(action: perform) {
                runtimePreparationButtonLabel(action: action, title: title)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!enabled)
        } else {
            Button(action: perform) {
                runtimePreparationButtonLabel(action: action, title: title)
            }
            .buttonStyle(.bordered)
            .disabled(!enabled)
        }
    }

    @ViewBuilder
    private func runtimePreparationButtonLabel(
        action: WorkbenchRuntimePreparationAction,
        title: String
    ) -> some View {
        HStack(spacing: 6) {
            if isRuntimePreparationActionRunning(action) {
                ProgressView()
                    .controlSize(.small)
            }
            Text(title)
        }
    }

    private func isRuntimePreparationActionRunning(_ action: WorkbenchRuntimePreparationAction) -> Bool {
        switch action {
        case .connect, .attach:
            return activeRuntimePreparationAction == action
        case .prepareMirror:
            return appState.isApplyingWorkflowConfiguration
        case .syncSession:
            return appState.isSyncingOpenClawSession
        }
    }

    private func connectOpenClawForRuntimeConfiguration() {
        performRuntimePreparationAction(.connect) { completion in
            appState.connectOpenClaw(completion: completion)
        }
    }

    private func attachCurrentProjectForRuntimeConfiguration() {
        performRuntimePreparationAction(.attach) { completion in
            appState.attachCurrentProjectToOpenClaw(completion: completion)
        }
    }

    private func prepareMirrorForRuntimeConfiguration() {
        performRuntimePreparationAction(.prepareMirror) { completion in
            appState.applyPendingWorkflowConfiguration(completion: completion)
        }
    }

    private func syncCurrentSessionForRuntimeConfiguration() {
        performRuntimePreparationAction(.syncSession) { completion in
            appState.syncOpenClawActiveSession(
                workflowID: selectedWorkflowID ?? workflows.first?.id,
                completion: completion
            )
        }
    }

    private func performRuntimePreparationAction(
        _ action: WorkbenchRuntimePreparationAction,
        operation: (@escaping (Bool, String) -> Void) -> Void
    ) {
        activeRuntimePreparationAction = action
        runtimeConfigMessage = nil

        operation { success, message in
            activeRuntimePreparationAction = nil
            runtimeConfigMessage = message
            runtimeConfigTone = success ? .success : .error

            if success && canRefreshRuntimeInventory {
                collapseRuntimeConfigurationPanelAfterSuccessfulAction()
                refreshRuntimeConfigurationDataIfNeeded(force: true)
            }
        }
    }

    private func collapseRuntimeConfigurationPanelAfterSuccessfulAction() {
        guard shouldAutoCollapseRuntimeConfigurationPanel else { return }
        setRuntimeConfigPanelMode(.compact)
    }

    private func setRuntimeConfigPanelMode(_ mode: WorkbenchRuntimeConfigPanelMode) {
        runtimeConfigPanelMode = mode
        SettingsManager.shared.workbenchRuntimeConfigPanelMode = mode.rawValue
    }

    private func clampedRuntimeConfigExpandedHeight(_ proposedHeight: CGFloat) -> CGFloat {
        min(max(proposedHeight, minimumExpandedRuntimeConfigHeight), maximumExpandedRuntimeConfigHeight)
    }

    private func resetRuntimeConfigExpandedHeight() {
        let resetHeight = clampedRuntimeConfigExpandedHeight(320)
        runtimeConfigExpandedHeight = resetHeight
        SettingsManager.shared.workbenchRuntimeConfigPanelExpandedHeight = resetHeight
    }

    private var runtimeConfigurationResizeGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let originHeight = runtimeConfigHeightDragOrigin ?? runtimeConfigExpandedHeight
                if runtimeConfigHeightDragOrigin == nil {
                    runtimeConfigHeightDragOrigin = originHeight
                }
                runtimeConfigExpandedHeight = clampedRuntimeConfigExpandedHeight(originHeight + value.translation.height)
            }
            .onEnded { value in
                let originHeight = runtimeConfigHeightDragOrigin ?? runtimeConfigExpandedHeight
                let resolvedHeight = clampedRuntimeConfigExpandedHeight(originHeight + value.translation.height)
                runtimeConfigExpandedHeight = resolvedHeight
                runtimeConfigHeightDragOrigin = nil
                SettingsManager.shared.workbenchRuntimeConfigPanelExpandedHeight = resolvedHeight
            }
    }

    private func runtimePreparationHint(for state: AppState.AgentRuntimePreparationState) -> String {
        if !state.isConnected {
            return LocalizedString.text("runtime_config_hint_connect")
        }
        if !state.isAttachedToCurrentProject {
            return LocalizedString.text("runtime_config_hint_attach")
        }
        if !state.isMirrorPrepared {
            return LocalizedString.text("runtime_config_hint_prepare_mirror")
        }
        if !state.hasManagedPath {
            return LocalizedString.text("runtime_config_hint_managed_path")
        }
        return LocalizedString.text("runtime_config_hint_pending")
    }

    private func modelBinding(for agentID: UUID, fallback draft: AgentRuntimeConfigurationRecord) -> Binding<String> {
        Binding(
            get: { runtimeConfigDrafts[agentID]?.modelIdentifier ?? draft.modelIdentifier },
            set: { newValue in
                var updated = runtimeConfigDrafts[agentID] ?? draft
                updated.modelIdentifier = newValue
                updated.source = .manualOverride
                updated.isStale = false
                persistRuntimeDraft(updated)
            }
        )
    }

    private func channelEnabledBinding(for agentID: UUID, fallback draft: AgentRuntimeConfigurationRecord) -> Binding<Bool> {
        Binding(
            get: { runtimeConfigDrafts[agentID]?.channelEnabled ?? draft.channelEnabled },
            set: { newValue in
                var updated = runtimeConfigDrafts[agentID] ?? draft
                updated.channelEnabled = newValue
                if !newValue {
                    updated.bindings = []
                }
                updated.source = .manualOverride
                updated.isStale = false
                persistRuntimeDraft(updated)
            }
        )
    }

    private func modelSuggestions(for draft: AgentRuntimeConfigurationRecord) -> [String] {
        var suggestions: [String] = []
        let current = draft.modelIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        if !current.isEmpty {
            suggestions.append(current)
        }
        suggestions.append(contentsOf: availableModels)

        var seen = Set<String>()
        return suggestions.filter { model in
            let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmed.isEmpty && seen.insert(trimmed).inserted
        }
    }

    private func toggleChannelAccount(_ account: OpenClawChannelAccountRecord, for agentID: UUID) {
        guard let draft = runtimeConfigDrafts[agentID] ?? appState.runtimeConfiguration(for: agentID) else { return }
        let binding = AgentRuntimeChannelBinding(channelID: account.channelID, accountID: account.accountID)
        let exists = draft.bindings.contains(binding)

        var updated = draft
        if exists {
            updated.bindings.removeAll { $0 == binding }
        } else {
            updated.bindings.append(binding)
        }
        updated.channelEnabled = true
        updated.source = .manualOverride
        updated.isStale = false
        persistRuntimeDraft(updated)
    }

    private func removeBinding(_ binding: AgentRuntimeChannelBinding, for agentID: UUID) {
        guard let draft = runtimeConfigDrafts[agentID] ?? appState.runtimeConfiguration(for: agentID) else { return }
        var updated = draft
        updated.bindings.removeAll { $0 == binding }
        updated.source = .manualOverride
        updated.isStale = false
        persistRuntimeDraft(updated)
    }

    private func addManualBinding(for agentID: UUID) {
        guard let draft = runtimeConfigDrafts[agentID] ?? appState.runtimeConfiguration(for: agentID) else { return }
        let channelID = (manualChannelDrafts[agentID] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !channelID.isEmpty else { return }
        let accountID = (manualAccountDrafts[agentID] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let binding = AgentRuntimeChannelBinding(
            channelID: channelID,
            accountID: accountID.isEmpty ? "default" : accountID
        )

        var updated = draft
        if !updated.bindings.contains(binding) {
            updated.bindings.append(binding)
        }
        updated.channelEnabled = true
        updated.source = .manualOverride
        updated.isStale = false
        persistRuntimeDraft(updated)

        manualChannelDrafts[agentID] = ""
        manualAccountDrafts[agentID] = ""
    }

    private func isBindingSelected(_ account: OpenClawChannelAccountRecord, for draft: AgentRuntimeConfigurationRecord) -> Bool {
        let binding = AgentRuntimeChannelBinding(channelID: account.channelID, accountID: account.accountID)
        return draft.bindings.contains(binding)
    }
}

private enum WorkbenchDashboardLayout: String, CaseIterable, Identifiable {
    case sideBySide
    case topBottom
    case dashboardOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sideBySide:
            return LocalizedString.text("layout_side_by_side")
        case .topBottom:
            return LocalizedString.text("layout_top_bottom")
        case .dashboardOnly:
            return LocalizedString.text("layout_dashboard_only")
        }
    }
}

private enum WorkbenchRuntimeConfigTone {
    case success
    case error
    case neutral

    var color: Color {
        switch self {
        case .success:
            return .green
        case .error:
            return .red
        case .neutral:
            return .secondary
        }
    }
}

private enum WorkbenchRuntimeConfigPanelMode: String {
    case hidden
    case compact
    case expanded

    static var storedDefault: WorkbenchRuntimeConfigPanelMode {
        WorkbenchRuntimeConfigPanelMode(rawValue: SettingsManager.shared.workbenchRuntimeConfigPanelMode) ?? .compact
    }

    var label: String {
        switch self {
        case .hidden:
            return LocalizedString.text("runtime_config_mode_hidden")
        case .compact:
            return LocalizedString.text("runtime_config_mode_compact")
        case .expanded:
            return LocalizedString.text("runtime_config_mode_expanded")
        }
    }
}

private enum WorkbenchRuntimePreparationAction {
    case connect
    case attach
    case prepareMirror
    case syncSession
}

private struct WorkflowFlowReceipt: Identifiable {
    let id: UUID
    let fromName: String
    let toName: String
    let fromStatus: NodeExecutionDisplayStatus
    let toStatus: NodeExecutionDisplayStatus
    let flowStatus: WorkflowFlowStatus
}

private enum NodeExecutionDisplayStatus: String {
    case idle
    case running
    case completed
    case failed

    var title: String {
        switch self {
        case .idle:
            return LocalizedString.text("execution_idle")
        case .running:
            return LocalizedString.text("execution_running")
        case .completed:
            return LocalizedString.text("execution_completed")
        case .failed:
            return LocalizedString.text("execution_failed")
        }
    }

    var color: Color {
        switch self {
        case .idle:
            return .secondary
        case .running:
            return .orange
        case .completed:
            return .green
        case .failed:
            return .red
        }
    }

    var icon: String {
        switch self {
        case .idle:
            return "○"
        case .running:
            return "◔"
        case .completed:
            return "✓"
        case .failed:
            return "✕"
        }
    }
}

private enum WorkflowFlowStatus: String {
    case pending
    case inProgress
    case completed
    case blocked

    var title: String {
        switch self {
        case .pending:
            return LocalizedString.text("flow_pending")
        case .inProgress:
            return LocalizedString.text("flow_in_progress")
        case .completed:
            return LocalizedString.text("flow_completed")
        case .blocked:
            return LocalizedString.text("flow_blocked")
        }
    }

    var color: Color {
        switch self {
        case .pending:
            return .secondary
        case .inProgress:
            return .orange
        case .completed:
            return .green
        case .blocked:
            return .red
        }
    }

    var priority: Int {
        switch self {
        case .inProgress:
            return 0
        case .blocked:
            return 1
        case .pending:
            return 2
        case .completed:
            return 3
        }
    }
}

private struct WorkbenchMessageBubble: View {
    let message: Message
    let linkedTask: Task?

    private var isUserMessage: Bool {
        message.inferredRole == "user"
    }

    private var agentName: String {
        let name = message.inferredAgentName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? LocalizedString.text("node_agent_fallback") : name
    }

    private var isThinking: Bool {
        !isUserMessage && message.metadata["thinking"] == "true"
    }

    private var runtimeEventLabel: String? {
        guard let eventType = message.runtimeEvent?.eventType else { return nil }
        switch eventType {
        case .taskDispatch:
            return "Dispatch"
        case .taskAccepted:
            return "Accepted"
        case .taskProgress:
            return "Progress"
        case .taskResult:
            return "Result"
        case .taskRoute:
            return "Route"
        case .taskError:
            return "Error"
        case .taskApprovalRequired:
            return "Approval"
        case .taskApproved:
            return "Approved"
        case .sessionSync:
            return "Session"
        }
    }

    var body: some View {
        VStack(alignment: isUserMessage ? .trailing : .leading, spacing: 6) {
            HStack {
                if isUserMessage { Spacer() }
                Text(isUserMessage ? LocalizedString.text("user_you") : LocalizedString.format("agent_reply_prefix", agentName))
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                if let runtimeEventLabel {
                    Text(runtimeEventLabel)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12))
                        .foregroundColor(.secondary)
                        .clipShape(Capsule())
                }
                if !isUserMessage {
                    Text(isThinking ? LocalizedString.text("thinking") : LocalizedString.text("replied"))
                        .font(.caption2)
                        .foregroundColor(isThinking ? .orange : .secondary)
                }
                if !isUserMessage { Spacer() }
            }

            if isThinking {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.mini)
                    Text(LocalizedString.text("streaming_reply"))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: isUserMessage ? .trailing : .leading)
            }

            MarkdownText(message.summaryText)
                .font(.body)
                .padding(12)
                .frame(maxWidth: 560, alignment: isUserMessage ? .trailing : .leading)
                .background(isUserMessage ? Color.accentColor : Color(.controlBackgroundColor))
                .foregroundColor(isUserMessage ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            HStack(spacing: 8) {
                if !isUserMessage, let linkedTask {
                    Label(linkedTask.status.displayName, systemImage: linkedTask.status.icon)
                        .foregroundColor(linkedTask.status.color)
                }
                Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                    .foregroundColor(.secondary)
            }
            .font(.caption2)
        }
        .frame(maxWidth: .infinity, alignment: isUserMessage ? .trailing : .leading)
    }
}

private struct MarkdownText: View {
    let content: String

    init(_ content: String) {
        self.content = content
    }

    var body: some View {
        Text(parsed)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var parsed: AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .full,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        if let attributed = try? AttributedString(markdown: content, options: options) {
            return attributed
        }
        return AttributedString(content)
    }
}

private struct WorkbenchEmptyState: View {
    let title: String
    let description: String
    let primaryTitle: String
    let primaryAction: () -> Void
    let secondaryTitle: String
    let secondaryAction: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "rectangle.and.pencil.and.ellipsis")
                .font(.system(size: 56))
                .foregroundColor(.accentColor)

            Text(title)
                .font(.title3)
                .fontWeight(.semibold)

            Text(description)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 560)

            HStack(spacing: 12) {
                Button(primaryTitle, action: primaryAction)
                    .buttonStyle(.borderedProminent)
                Button(secondaryTitle, action: secondaryAction)
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}
