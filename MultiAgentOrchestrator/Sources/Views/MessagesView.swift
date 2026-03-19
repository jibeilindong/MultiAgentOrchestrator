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

    private var workbenchTasks: [Task] {
        appState.taskManager.tasks
            .filter { task in
                task.metadata["source"] == "workbench"
                    && (selectedWorkflow == nil || task.metadata["workflowID"] == selectedWorkflow?.id.uuidString)
            }
            .sorted { $0.createdAt > $1.createdAt }
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
                .filter { $0.fromNodeID == startNode.id }
                .compactMap { nodeByID[$0.toNodeID]?.agentID }
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
    }

    private var content: some View {
        VStack(spacing: 0) {
            header

            Divider()

            if !hasOpenClawConfiguration {
                openClawBanner
                Divider()
            }

            HStack(spacing: 0) {
                conversationPane

                Divider()

                taskPane
                    .frame(width: 280)
                    .background(Color(.controlBackgroundColor))
            }
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
                .onChange(of: workbenchMessages.count) { _, _ in
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

                TextField(
                    "描述要交给当前工作流处理的任务，例如：先调研，再拆分，再给出执行方案。",
                    text: $prompt,
                    axis: .vertical
                )
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...8)

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
                }
            }
            .padding()
        }
    }

    private var taskPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("任务回执")
                    .font(.headline)
                Spacer()
                Text("\(workbenchTasks.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if workbenchTasks.isEmpty {
                        Text("当前工作流还没有由工作台发布的任务。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding()
                    } else {
                        ForEach(workbenchTasks.prefix(12)) { task in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(task.title)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .lineLimit(1)
                                    Spacer()
                                    statusBadge(title: task.status.rawValue, color: task.status.color)
                                }

                                if let agentID = task.assignedAgentID,
                                   let agent = project?.agents.first(where: { $0.id == agentID }) {
                                    Text("入口 Agent: \(agent.name)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }

                                Text(task.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(3)
                            }
                            .padding(10)
                            .background(Color(.windowBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                }
                .padding()
            }
        }
    }

    private func linkedTask(for message: Message) -> Task? {
        guard let taskIDValue = message.metadata["taskID"],
              let taskID = UUID(uuidString: taskIDValue) else {
            return nil
        }
        return appState.taskManager.task(with: taskID)
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
}

private struct WorkbenchMessageBubble: View {
    let message: Message
    let linkedTask: Task?

    private var isUserMessage: Bool {
        message.metadata["role"] == "user"
    }

    var body: some View {
        VStack(alignment: isUserMessage ? .trailing : .leading, spacing: 6) {
            HStack {
                if isUserMessage { Spacer() }
                Text(isUserMessage ? "任务输入" : "工作流回执")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                if !isUserMessage { Spacer() }
            }

            Text(message.content)
                .font(.body)
                .padding(12)
                .frame(maxWidth: 560, alignment: isUserMessage ? .trailing : .leading)
                .background(isUserMessage ? Color.accentColor : Color(.controlBackgroundColor))
                .foregroundColor(isUserMessage ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            HStack(spacing: 8) {
                if let linkedTask {
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
