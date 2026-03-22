//
//  MessagesView.swift
//  Multi-Agent-Flow
//

import SwiftUI

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

    private var project: MAProject? { appState.currentProject }
    private var workflows: [Workflow] { project?.workflows ?? [] }
    private var availableChannelAccounts: [OpenClawChannelAccountRecord] {
        project?.openClaw.availableChannelAccounts ?? appState.openClawManager.availableChannelAccounts
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
        appState.openClawManager.canRunConversation
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
            return !config.localBinaryPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
        VStack(spacing: 0) {
            header

            Divider()

            if !hasOpenClawConfiguration {
                openClawBanner
                Divider()
            }

            runtimeConfigurationPanel

            Divider()

            workbenchAndDashboardPane
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(LocalizedString.text("workbench_title"))
                        .font(.title2)
                    Text(LocalizedString.text("workbench_subtitle"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Picker(LocalizedString.text("workflow_picker_label"), selection: $selectedWorkflowID) {
                    ForEach(workflows) { workflow in
                        Text(workflow.name).tag(workflow.id as UUID?)
                    }
                }
                .frame(width: 220)

                Picker(LocalizedString.text("layout_picker_label"), selection: $dashboardLayout) {
                    ForEach(WorkbenchDashboardLayout.allCases) { layout in
                        Text(layout.title).tag(layout)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 170)

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

                statusBadge(title: openClawRuntimeBadgeTitle, color: openClawRuntimeBadgeColor)
                statusBadge(
                    title: appState.openClawService.isExecuting ? LocalizedString.text("workflow_running") : LocalizedString.text("workflow_idle"),
                    color: appState.openClawService.isExecuting ? .orange : .secondary
                )

                Button(LocalizedString.saveProject) {
                    appState.saveProject()
                }
                .buttonStyle(.bordered)
            }

            if let workflow = selectedWorkflow {
                HStack(spacing: 8) {
                    statusBadge(title: LocalizedString.format("execution_nodes_count", workflow.nodes.filter { $0.type == .agent }.count), color: .blue)
                    statusBadge(title: LocalizedString.format("communication_links_count", workflow.edges.count), color: .purple)
                    statusBadge(title: LocalizedString.format("file_boundaries_count", workflow.boundaries.count), color: .orange)
                }
            }
        }
        .padding()
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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("运行时配置")
                        .font(.headline)
                    Text("工作台负责为节点对应的 Agent 配置模型与 channel，编辑器不再承担这部分配置。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if isRefreshingRuntimeConfigurations {
                    ProgressView()
                        .controlSize(.small)
                }

                Button("刷新运行时") {
                    refreshRuntimeConfigurationDataIfNeeded(force: true)
                }
                .buttonStyle(.bordered)
                .disabled(isRefreshingRuntimeConfigurations || project == nil)
            }

            HStack(spacing: 8) {
                statusBadge(
                    title: appState.openClawManager.isConnected ? "OpenClaw 已连接" : "OpenClaw 未连接",
                    color: appState.openClawManager.isConnected ? .green : .red
                )
                statusBadge(
                    title: appState.isCurrentProjectAttachedToOpenClaw ? "当前项目已附着" : "当前项目未附着",
                    color: appState.isCurrentProjectAttachedToOpenClaw ? .green : .orange
                )
                statusBadge(
                    title: appState.openClawManager.sessionLifecycle.stage == .inactive ? "镜像未就绪" : "镜像已准备",
                    color: appState.openClawManager.sessionLifecycle.stage == .inactive ? .orange : .green
                )
                statusBadge(
                    title: appState.openClawManager.sessionLifecycle.stage == .synced ? "会话已同步" : "会话待同步",
                    color: appState.openClawManager.sessionLifecycle.stage == .synced ? .green : .orange
                )
            }

            if let runtimeConfigMessage {
                Text(runtimeConfigMessage)
                    .font(.caption)
                    .foregroundColor(runtimeConfigTone.color)
            }

            if appState.openClawManager.config.deploymentKind == .remoteServer {
                Text("当前是远程网关模式。按照现阶段 OpenClaw 能力，这里暂不支持直接读取或写回 Agent 的 channel 绑定。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if workflowAgents.isEmpty {
                Text("当前工作流还没有可配置的 Agent 节点。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(workflowAgents) { agent in
                            runtimeConfigurationCard(for: agent)
                        }
                    }
                }
                .frame(minHeight: 140, maxHeight: 320)
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor).opacity(0.6))
    }

    @ViewBuilder
    private func runtimeConfigurationCard(for agent: Agent) -> some View {
        let preparation = appState.runtimePreparationState(for: agent.id)
        let draft = runtimeConfigDrafts[agent.id] ?? appState.runtimeConfiguration(for: agent.id)

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(agent.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(preparation?.managedPath ?? "尚未解析到受管路径")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                }

                Spacer()

                if let preparation {
                    statusBadge(
                        title: preparation.canConfigure ? "可配置" : "待准备",
                        color: preparation.canConfigure ? .green : .orange
                    )
                }

                Button("采用现状") {
                    adoptRuntimeInventory(for: agent.id)
                }
                .buttonStyle(.bordered)
                .disabled(runtimeInventoryRecords[agent.id] == nil)

                Button(applyingRuntimeConfigurationAgentID == agent.id ? "应用中…" : "应用到 OpenClaw") {
                    applyRuntimeConfiguration(for: agent.id)
                }
                .buttonStyle(.borderedProminent)
                .disabled(applyingRuntimeConfigurationAgentID != nil || !(preparation?.canConfigure ?? false))
            }

            if let preparation, !preparation.canConfigure {
                Text(runtimePreparationHint(for: preparation))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let draft {
                VStack(alignment: .leading, spacing: 6) {
                    Text("模型")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    TextField("输入模型标识", text: modelBinding(for: agent.id, fallback: draft))
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

                Toggle("连接 channel", isOn: channelEnabledBinding(for: agent.id, fallback: draft))

                if draft.channelEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("已选 channel")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        if draft.bindings.isEmpty {
                            Text("当前还没有绑定。可以直接选择 OpenClaw 已发现的 channel/account，也可以手动新增。")
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
                                Text("OpenClaw 已发现的可选项")
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
                                "手动输入 channel",
                                text: Binding(
                                    get: { manualChannelDrafts[agent.id] ?? "" },
                                    set: { manualChannelDrafts[agent.id] = $0 }
                                )
                            )
                            .textFieldStyle(.roundedBorder)

                            TextField(
                                "account，留空则为 default",
                                text: Binding(
                                    get: { manualAccountDrafts[agent.id] ?? "" },
                                    set: { manualAccountDrafts[agent.id] = $0 }
                                )
                            )
                            .textFieldStyle(.roundedBorder)

                            Button("新增绑定") {
                                addManualBinding(for: agent.id)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(Color(.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private var workbenchAndDashboardPane: some View {
        switch dashboardLayout {
        case .sideBySide:
            HSplitView {
                dialogueAndReceiptsPane
                    .frame(minWidth: 500, idealWidth: 560)
                OpsCenterDashboardView(
                    displayMode: .embedded,
                    preferredWorkflowID: selectedWorkflow?.id
                )
                    .frame(minWidth: 360, idealWidth: 780, maxWidth: .infinity, maxHeight: .infinity)
            }
        case .topBottom:
            VSplitView {
                dialogueAndReceiptsPane
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

    private var dialogueAndReceiptsPane: some View {
        HStack(spacing: 0) {
            conversationPane
                .frame(minWidth: 300, idealWidth: 340, maxWidth: .infinity)

            Divider()

            taskPane
                .frame(minWidth: 220, idealWidth: 280, maxWidth: 360)
                .background(Color(.controlBackgroundColor))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

                Button(LocalizedString.text("send_to_workflow")) {
                    publishPrompt()
                }
                .disabled(
                    prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || appState.openClawService.isExecuting
                            || !hasExecutableWorkflow
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

        guard isWorkbenchRuntimeAvailable else {
            errorText = LocalizedString.text("workbench_error_connect_openclaw")
            return
        }

        guard appState.submitWorkbenchPrompt(text, workflowID: selectedWorkflowID) else {
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
        guard project != nil, appState.openClawManager.config.deploymentKind != .remoteServer else {
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
        runtimeConfigMessage = "已采用运行时现状作为当前 Agent 的配置草稿。"
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
                refreshRuntimeConfigurationDataIfNeeded(force: true)
            }
        }
    }

    private func runtimePreparationHint(for state: AppState.AgentRuntimePreparationState) -> String {
        if !state.isConnected {
            return "需要先连接 OpenClaw。"
        }
        if !state.isAttachedToCurrentProject {
            return "需要先把当前项目附着到 OpenClaw 会话。"
        }
        if !state.isMirrorPrepared {
            return "需要先完成项目镜像准备，再开始配置。"
        }
        if !state.hasManagedPath {
            return "当前节点还没有解析到受管路径，暂时不能可靠地下发模型与 channel 配置。"
        }
        return "当前配置仍待准备。"
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
