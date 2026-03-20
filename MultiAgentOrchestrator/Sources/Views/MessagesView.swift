//
//  MessagesView.swift
//  MultiAgentOrchestrator
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

    private var project: MAProject? { appState.currentProject }
    private var workflows: [Workflow] { project?.workflows ?? [] }

    private var selectedWorkflow: Workflow? {
        if let selectedWorkflowID {
            return workflows.first { $0.id == selectedWorkflowID }
        }
        return workflows.first
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
                    title: "先配置 OpenClaw，再新建 Project",
                    description: "安装软件后先完成 OpenClaw 配置，然后创建或打开项目，在编辑器中搭建工作流并保存。保存后，这里就是对该工作流发布任务和追踪回执的工作台。",
                    primaryTitle: "配置 OpenClaw",
                    primaryAction: { NotificationCenter.default.post(name: .openSettings, object: nil) },
                    secondaryTitle: "新建项目",
                    secondaryAction: { appState.createNewProject() }
                )
            } else if workflows.isEmpty {
                WorkbenchEmptyState(
                    title: "Project 里还没有工作流",
                    description: "先在编辑器中创建工作流架构，再回到工作台以对话形式发布任务。",
                    primaryTitle: "创建主工作流",
                    primaryAction: { _ = appState.ensureMainWorkflow() },
                    secondaryTitle: "保存项目",
                    secondaryAction: { appState.saveProject() }
                )
            } else if !hasExecutableWorkflow {
                WorkbenchEmptyState(
                    title: "当前工作流还不能执行",
                    description: "入口（Start）节点至少需要连接一个 Agent 节点。工作台输入会路由到入口连线对应的 Agent。",
                    primaryTitle: "导入 Project Agents",
                    primaryAction: { appState.generateArchitectureFromProjectAgents() },
                    secondaryTitle: "配置 OpenClaw",
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
                    Text("工作台")
                        .font(.title2)
                    Text("以对话方式向已保存工作流发布任务")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Picker("Workflow", selection: $selectedWorkflowID) {
                    ForEach(workflows) { workflow in
                        Text(workflow.name).tag(workflow.id as UUID?)
                    }
                }
                .frame(width: 220)

                Picker("布局", selection: $dashboardLayout) {
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
                    .help("与工作台共同展示仪表盘")
                    .disabled(dashboardLayout != .dashboardOnly)

                    Button(action: expandDashboard) {
                        Image(systemName: "plus.magnifyingglass")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("仅显示仪表盘")
                    .disabled(dashboardLayout == .dashboardOnly)
                }

                statusBadge(
                    title: appState.openClawService.isExecuting ? "执行中" : "待命",
                    color: appState.openClawService.isExecuting ? .orange : .green
                )

                Button("保存项目") {
                    appState.saveProject()
                }
                .buttonStyle(.bordered)
            }

            if let workflow = selectedWorkflow {
                HStack(spacing: 8) {
                    statusBadge(title: "\(workflow.nodes.filter { $0.type == .agent }.count) 个执行节点", color: .blue)
                    statusBadge(title: "\(workflow.edges.count) 条通信线", color: .purple)
                    statusBadge(title: "\(workflow.boundaries.count) 个文件边界", color: .orange)
                }
            }
        }
        .padding()
    }

    private var openClawBanner: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("OpenClaw 尚未完成配置")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("工作台会记录任务，但没有可用的 OpenClaw 配置时，流程无法稳定驱动执行。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button("现在配置") {
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
                                "还没有对话任务",
                                systemImage: "bubble.left.and.exclamationmark.bubble.right",
                                description: Text("在下方输入任务目标，软件会把它发布到当前工作流，并把执行结果回写到项目。")
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
                    if let lastID = workbenchMessages.last?.id {
                        withAnimation {
                            proxy.scrollTo(lastID, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: lastWorkbenchMessageSignature) { _, _ in
                    if let lastID = workbenchMessages.last?.id {
                        withAnimation {
                            proxy.scrollTo(lastID, anchor: .bottom)
                        }
                    }
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
                        "描述要交给当前工作流处理的任务，例如：先调研，再拆分，再给出执行方案。",
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
                            Text("Markdown 预览")
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
                    Text(selectedWorkflow?.name ?? "未选择工作流")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    Button("发送到工作流") {
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
                Text("信息流转回执")
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
                        Text("当前工作流还没有可展示的信息流转。")
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

                                Text("流转状态：\(flow.flowStatus.title)")
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
            return node.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Start" : node.title
        case .agent:
            if let agentID = node.agentID,
               let agent = project?.agents.first(where: { $0.id == agentID }) {
                return agent.name
            }
            return node.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Agent" : node.title
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
            errorText = "请输入要发给工作流的任务。"
            return
        }

        guard hasExecutableWorkflow else {
            errorText = "当前工作流入口节点尚未连接 Agent，请先从 Start 节点连线到目标 Agent。"
            return
        }

        guard appState.submitWorkbenchPrompt(text, workflowID: selectedWorkflowID) else {
            errorText = appState.openClawService.isExecuting
                ? "当前已有工作流在执行，请等待本轮完成后再发布新任务。"
                : "任务发布失败，请检查工作流结构和 OpenClaw 配置。"
            return
        }

        prompt = ""
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
            return "左右分栏"
        case .topBottom:
            return "上下分栏"
        case .dashboardOnly:
            return "仅仪表盘"
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
            return "待命"
        case .running:
            return "执行中"
        case .completed:
            return "已完成"
        case .failed:
            return "失败"
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
            return "待流转"
        case .inProgress:
            return "流转中"
        case .completed:
            return "已流转"
        case .blocked:
            return "阻塞"
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
        return name.isEmpty ? "Agent" : name
    }

    private var isThinking: Bool {
        !isUserMessage && message.metadata["thinking"] == "true"
    }

    var body: some View {
        VStack(alignment: isUserMessage ? .trailing : .leading, spacing: 6) {
            HStack {
                if isUserMessage { Spacer() }
                Text(isUserMessage ? "你" : "回复 Agent: \(agentName)")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                if !isUserMessage {
                    Text(isThinking ? "思考中…" : "已回复")
                        .font(.caption2)
                        .foregroundColor(isThinking ? .orange : .secondary)
                }
                if !isUserMessage { Spacer() }
            }

            if isThinking {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("正在生成回复，内容会实时更新")
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
                    Label(linkedTask.status.rawValue, systemImage: linkedTask.status.icon)
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
