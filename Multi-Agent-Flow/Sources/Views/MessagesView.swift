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

    private var project: MAProject? { appState.currentProject }
    private var workflows: [Workflow] { project?.workflows ?? [] }

    private var selectedWorkflow: Workflow? {
        if let selectedWorkflowID {
            return workflows.first { $0.id == selectedWorkflowID }
        }
        return workflows.first
    }

    private var isOpenClawConnected: Bool {
        appState.openClawManager.isConnected
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
            last.metadata["outputType"] ?? ""
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
            } else if !isOpenClawConnected {
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
        }
        .onChange(of: workflows.map(\.id)) { _, newValue in
            guard let firstID = newValue.first else { return }
            if selectedWorkflowID == nil || !newValue.contains(selectedWorkflowID ?? firstID) {
                selectedWorkflowID = firstID
            }
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

                statusBadge(title: LocalizedString.text("openclaw_connected"), color: .green)
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

    @ViewBuilder
    private var workbenchAndDashboardPane: some View {
        switch dashboardLayout {
        case .sideBySide:
            HSplitView {
                dialogueAndReceiptsPane
                    .frame(minWidth: 500, idealWidth: 560)
                MonitoringDashboardView()
                    .frame(minWidth: 360, idealWidth: 780, maxWidth: .infinity, maxHeight: .infinity)
            }
        case .topBottom:
            VSplitView {
                dialogueAndReceiptsPane
                    .frame(minHeight: 280, idealHeight: 360)
                MonitoringDashboardView()
                    .frame(minHeight: 280, idealHeight: 420)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .dashboardOnly:
            MonitoringDashboardView()
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

        guard isOpenClawConnected else {
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
        message.metadata["role"] == "user"
    }

    private var agentName: String {
        let name = message.metadata["agentName"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? LocalizedString.text("node_agent_fallback") : name
    }

    private var isThinking: Bool {
        !isUserMessage && message.metadata["thinking"] == "true"
    }

    var body: some View {
        VStack(alignment: isUserMessage ? .trailing : .leading, spacing: 6) {
            HStack {
                if isUserMessage { Spacer() }
                Text(isUserMessage ? LocalizedString.text("user_you") : LocalizedString.format("agent_reply_prefix", agentName))
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
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

            MarkdownText(message.content)
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
