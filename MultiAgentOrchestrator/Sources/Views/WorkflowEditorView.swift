//
//  WorkflowEditorView.swift
//  MultiAgentOrchestrator
//
//  工作流编辑器 - 支持三种视图模式
//

import SwiftUI
import UniformTypeIdentifiers

struct WorkflowEditorView: View {
    @EnvironmentObject var appState: AppState
    @Binding var zoomScale: CGFloat
    
    @State private var viewMode: EditorViewMode = .architecture
    @State private var selectedAgentID: UUID?
    @State private var isConnectMode: Bool = false
    @State private var connectFromAgentID: UUID?
    @State private var connectionType: ConnectionType = .unidirectional
    @State private var testExecution: WorkflowTestExecution?
    @State private var isRunning: Bool = false
    @State private var refreshKey: Int = 0  // 用于刷新Agent库
    
    enum ConnectionType: String, CaseIterable {
        case unidirectional = "→"
        case bidirectional = "⇄"
        
        var description: String {
            switch self {
            case .unidirectional: return "One-way"
            case .bidirectional: return "Two-way"
            }
        }
    }
    
    enum EditorViewMode: String, CaseIterable {
        case list = "List"
        case grid = "Grid"
        case architecture = "Architecture"
        
        var icon: String {
            switch self {
            case .list: return "list.bullet"
            case .grid: return "square.grid.2x2"
            case .architecture: return "network"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            EditorToolbar(
                viewMode: $viewMode,
                isRunning: isRunning,
                onRunTest: runTest,
                onStopTest: stopTest
            )
            .zIndex(1000)
            
            Divider()
            
            ZStack {
                switch viewMode {
                case .list:
                    AgentListView(
                        selectedAgentID: $selectedAgentID,
                        isConnectMode: isConnectMode,
                        connectFromAgentID: connectFromAgentID,
                        onConnect: handleAgentConnection
                    )
                case .grid:
                    AgentGridView(
                        selectedAgentID: $selectedAgentID,
                        isConnectMode: isConnectMode,
                        connectFromAgentID: connectFromAgentID,
                        onConnect: handleAgentConnection
                    )
                case .architecture:
                    ArchitectureView(
                        zoomScale: $zoomScale,
                        isConnectMode: $isConnectMode,
                        connectFromAgentID: $connectFromAgentID,
                        connectionType: $connectionType,
                        onConnect: handleAgentConnection,
                        testExecution: testExecution
                    )
                }
            }
            
            // 测试执行面板
            if let execution = testExecution {
                Divider()
                TestExecutionPanel(execution: execution)
            }
        }
        .onChange(of: viewMode) { _, newValue in
            if newValue != .architecture {
                isConnectMode = false
                connectFromAgentID = nil
            }
        }
    }
    
    private func handleAgentConnection(from: UUID, to: UUID) {
        let sourceNodeID = resolveNodeID(for: from, preferredIndex: 0)
        let targetNodeID = resolveNodeID(for: to, preferredIndex: 1)

        if let sourceNodeID, let targetNodeID, sourceNodeID != targetNodeID {
            appState.connectNodes(from: sourceNodeID, to: targetNodeID, bidirectional: connectionType == .bidirectional)
        }

        connectFromAgentID = nil
    }
    
    private func runTest() {
        guard let project = appState.currentProject,
              let workflow = project.workflows.first else { return }
        
        isRunning = true
        
        // 显示执行进度
        testExecution = WorkflowTestExecution(workflow: workflow, agents: project.agents)
        
        // 调用OpenClaw执行工作流
        appState.openClawService.executeWorkflow(workflow, agents: project.agents) { results in
            DispatchQueue.main.async {
                self.isRunning = false
                // 显示执行结果
                for result in results {
                    print("Agent executed: \(result.status) - \(result.output)")
                }
            }
        }
        
        // 同时显示模拟的执行进度（实时反馈）
        simulateWorkflowExecution(workflow: workflow, agents: project.agents)
    }
    
    private func stopTest() {
        isRunning = false
        testExecution = nil
    }
    
    private func simulateWorkflowExecution(workflow: Workflow, agents: [Agent]) {
        guard var execution = testExecution else { return }
        
        let agentNodes = appState.openClawService.executionPlan(for: workflow)
        
        for (index, node) in agentNodes.enumerated() {
            guard let agentID = node.agentID,
                  let agent = agents.first(where: { $0.id == agentID }) else { continue }
            
            // 添加执行步骤
            let step = WorkflowTestStep(
                stepNumber: index + 1,
                agentID: agentID,
                agentName: agent.name,
                action: getAgentAction(agent: agent, index: index, total: agentNodes.count),
                status: .pending,
                timestamp: Date()
            )
            execution.steps.append(step)
        }
        
        self.testExecution = execution
        
        // 逐步执行
        executeSteps(index: 0)
    }
    
    private func executeSteps(index: Int) {
        guard var execution = testExecution, index < execution.steps.count else {
            isRunning = false
            return
        }
        
        // 更新当前步骤状态
        execution.steps[index].status = .running
        execution.currentStep = index + 1
        testExecution = execution
        
        // 模拟执行延迟 - 使用简单的递归调用
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.completeStep(index: index)
        }
    }
    
    private func completeStep(index: Int) {
        guard var execution = testExecution, index < execution.steps.count else {
            isRunning = false
            return
        }
        
        execution.steps[index].status = .completed
        execution.steps[index].completedAt = Date()
        testExecution = execution
        
        // 执行下一步
        executeSteps(index: index + 1)
    }
    
    private func getAgentAction(agent: Agent, index: Int, total: Int) -> String {
        if index == 0 {
            return "任务分解 - 分析需求，拆分子任务"
        } else if index == total - 1 {
            return "结果汇总 - 收集整理，最终输出"
        } else if index % 2 == 1 {
            return "执行处理 - 处理子任务"
        } else {
            return "校验确认 - 验证结果准确性"
        }
    }

    private func resolveNodeID(for identifier: UUID, preferredIndex: Int) -> UUID? {
        guard let workflow = appState.currentProject?.workflows.first else { return nil }

        if workflow.nodes.contains(where: { $0.id == identifier }) {
            return identifier
        }

        if let node = workflow.nodes.first(where: { $0.agentID == identifier && $0.type == .agent }) {
            return node.id
        }

        let fallbackX: CGFloat = preferredIndex == 0 ? -180 : 180
        return appState.ensureAgentNode(agentID: identifier, suggestedPosition: CGPoint(x: fallbackX, y: 0))
    }
}

// MARK: - 工具栏
struct EditorToolbar: View {
    @EnvironmentObject var appState: AppState
    @Binding var viewMode: WorkflowEditorView.EditorViewMode
    let isRunning: Bool
    var onRunTest: () -> Void
    var onStopTest: () -> Void
    
    var body: some View {
        HStack(spacing: 10) {
            WorkflowToolbarGroup(title: "View") {
                HStack(spacing: 4) {
                    ForEach(WorkflowEditorView.EditorViewMode.allCases, id: \.self) { mode in
                        Button(action: { viewMode = mode }) {
                            HStack(spacing: 4) {
                                Image(systemName: mode.icon)
                                Text(mode.rawValue)
                                    .font(.caption)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(viewMode == mode ? Color.accentColor.opacity(0.18) : Color.clear)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(viewMode == mode ? .accentColor : .secondary)
                    }
                }
            }

            WorkflowToolbarGroup(title: "Execution") {
                HStack(spacing: 8) {
                    Button(action: isRunning ? onStopTest : onRunTest) {
                        Label(isRunning ? "Stop" : "Test", systemImage: isRunning ? "stop.circle" : "play.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.borderedProminent)

                    Button(action: { appState.saveProject() }) {
                        Label("Save", systemImage: "square.and.arrow.down")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                }

                if appState.isAutoSaving {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.6)
                        Text(LocalizedString.saving)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else if let lastSave = appState.lastAutoSaveTime {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Auto-saved \(lastSave.formatted(date: .omitted, time: .shortened))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.windowBackgroundColor))
    }
}

private struct WorkflowToolbarGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption2)
                .foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                content
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - 列表视图
struct AgentListView: View {
    @EnvironmentObject var appState: AppState
    @Binding var selectedAgentID: UUID?
    var isConnectMode: Bool
    var connectFromAgentID: UUID?
    var onConnect: (UUID, UUID) -> Void
    
    @State private var draggedAgentID: UUID?
    
    var body: some View {
        VStack(spacing: 0) {
            // 表头
            HStack {
                Text("Status").frame(width: 60, alignment: .leading)
                Text("Name").frame(minWidth: 100, alignment: .leading)
                Text("ID").frame(width: 80, alignment: .leading)
                Text("Model").frame(width: 80, alignment: .leading)
                Text("Skills").frame(width: 60, alignment: .center)
                Text("Actions").frame(width: 120, alignment: .center)
                Spacer()
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(.controlBackgroundColor))
            
            Divider()
            
            // 智能体列表
            List {
                ForEach(Array((appState.currentProject?.agents ?? []).enumerated()), id: \.element.id) { index, agent in
                    AgentListRow(
                        agent: agent,
                        index: index,
                        isSelected: selectedAgentID == agent.id,
                        isConnectMode: isConnectMode,
                        isConnectSource: connectFromAgentID == agent.id,
                        onSelect: { selectedAgentID = agent.id },
                        onConnect: { targetID in
                            if let sourceID = connectFromAgentID {
                                onConnect(sourceID, targetID)
                            }
                        }
                    )
                    
                    .contextMenu {
                        AgentContextMenu(agent: agent)
                    }
                }
            }
            .listStyle(.plain)
        }
    }
}

struct AgentListRow: View {
    let agent: Agent
    let index: Int
    let isSelected: Bool
    let isConnectMode: Bool
    let isConnectSource: Bool
    var onSelect: () -> Void
    var onConnect: (UUID) -> Void
    
    var body: some View {
        HStack {
            // 状态指示
            Circle()
                .fill(Color.green)
                .frame(width: 8, height: 8)
                .frame(width: 60, alignment: .leading)
            
            // 名称
            Text(agent.name)
                .frame(minWidth: 100, alignment: .leading)
            
            // ID
            Text(String(agent.id.uuidString.prefix(8)))
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)
            
            // 模型
            Text(agent.openClawDefinition.modelIdentifier)
                .font(.caption)
                .frame(width: 80, alignment: .leading)
            
            // 技能数
            Text("\(agent.capabilities.count)")
                .font(.caption)
                .frame(width: 60, alignment: .center)
            
            // 操作按钮
            HStack(spacing: 8) {
                Button(action: {}) {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                
                Button(action: {}) {
                    Image(systemName: "doc.text")
                }
                .buttonStyle(.borderless)
                
                Button(action: {}) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                
                if isConnectMode {
                    Button(action: { onConnect(agent.id) }) {
                        Image(systemName: "link")
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.blue)
                }
            }
            .frame(width: 120, alignment: .center)
            
            Spacer()
        }
        .padding(.vertical, 4)
        .background(isSelected ? Color.accentColor.opacity(0.1) : (isConnectSource ? Color.blue.opacity(0.1) : Color.clear))
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
    }
}



// MARK: - 网格视图
struct AgentGridView: View {
    @EnvironmentObject var appState: AppState
    @Binding var selectedAgentID: UUID?
    var isConnectMode: Bool
    var connectFromAgentID: UUID?
    var onConnect: (UUID, UUID) -> Void
    
    let columns = [GridItem(.adaptive(minimum: 200))]
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(appState.currentProject?.agents ?? []) { agent in
                    AgentGridCard(
                        agent: agent,
                        isSelected: selectedAgentID == agent.id,
                        isConnectMode: isConnectMode,
                        isConnectSource: connectFromAgentID == agent.id,
                        onSelect: { selectedAgentID = agent.id },
                        onConnect: { targetID in
                            if let sourceID = connectFromAgentID {
                                onConnect(sourceID, targetID)
                            }
                        }
                    )
                    .contextMenu {
                        AgentContextMenu(agent: agent)
                    }
                }
            }
            .padding()
        }
    }
}

struct AgentGridCard: View {
    let agent: Agent
    let isSelected: Bool
    let isConnectMode: Bool
    let isConnectSource: Bool
    var onSelect: () -> Void
    var onConnect: (UUID) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle()
                    .fill(Color.green)
                    .frame(width: 10, height: 10)
                
                Text(agent.name)
                    .font(.headline)
                
                Spacer()
                
                if isConnectMode {
                    Button(action: { onConnect(agent.id) }) {
                        Image(systemName: "link")
                    }
                    .buttonStyle(.borderless)
                }
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 4) {
                Label("ID: \(String(agent.id.uuidString.prefix(8)))", systemImage: "number")
                Label("Model: M2.5", systemImage: "cpu")
                Label("Skills: \(agent.capabilities.count)", systemImage: "star")
            }
            .font(.caption)
            .foregroundColor(.secondary)
            
            HStack {
                Button(action: {}) {
                    Label("Edit", systemImage: "pencil")
                }
                .buttonStyle(.borderless)
                
                Spacer()
                
                Button(action: {}) {
                    Label("Menu", systemImage: "ellipsis.circle")
                }
                .buttonStyle(.borderless)
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : (isConnectSource ? Color.blue : Color.clear), lineWidth: 2)
        )
        .onTapGesture {
            onSelect()
        }
    }
}

// MARK: - 架构视图（带Agent库和隔离框）
struct ArchitectureView: View {
    @EnvironmentObject var appState: AppState
    @Binding var zoomScale: CGFloat
    @Binding var isConnectMode: Bool
    @Binding var connectFromAgentID: UUID?
    @Binding var connectionType: WorkflowEditorView.ConnectionType
    var onConnect: (UUID, UUID) -> Void
    var testExecution: WorkflowTestExecution?
    
    @State private var showNodePropertyPanel = false
    @State private var selectedNodeForProperty: WorkflowNode?
    @State private var showEdgePropertyPanel = false
    @State private var selectedEdgeForProperty: WorkflowEdge?
    
    var body: some View {
        GeometryReader { _ in
            ZStack {
                CanvasView(
                    zoomScale: $zoomScale,
                    isConnectMode: $isConnectMode,
                    connectionType: $connectionType,
                    connectFromAgentID: $connectFromAgentID,
                    onNodeClickInConnectMode: { node in
                        self.handleNodeClickInConnectMode(node: node)
                    },
                    onNodeSelected: { node in
                        selectedEdgeForProperty = nil
                        showEdgePropertyPanel = false
                        selectedNodeForProperty = node
                        showNodePropertyPanel = true
                    },
                    onEdgeSelected: { edge in
                        selectedNodeForProperty = nil
                        showNodePropertyPanel = false
                        selectedEdgeForProperty = edge
                        showEdgePropertyPanel = true
                    },
                    onDropAgent: { agentName, location in
                        self.addAgentNodeToCanvas(agentName: agentName, at: location)
                    }
                )

                if showNodePropertyPanel, let node = selectedNodeForProperty {
                    NodePropertyPanel(
                        node: node,
                        isPresented: $showNodePropertyPanel
                    )
                    .transition(.move(edge: .trailing))
                }

                if showEdgePropertyPanel, let edge = selectedEdgeForProperty {
                    EdgePropertyPanel(
                        edge: edge,
                        isPresented: $showEdgePropertyPanel
                    )
                    .transition(.move(edge: .trailing))
                }
            }
        }
    }
    
    private func addAgentNodeToCanvas(agentName: String, at _: CGPoint) {
        appState.addAgentNode(agentName: agentName, position: CGPoint(x: 300, y: 200))
    }
    
    // 处理连接模式下的节点点击
    private func handleNodeClickInConnectMode(node: WorkflowNode) {
        guard node.type == .agent else { return }

        if isConnectMode {
            if let fromID = connectFromAgentID {
                // Create connection from source to this node
                if let sourceNodeID = resolveAgentNodeID(from: fromID) {
                    self.createConnection(from: sourceNodeID, to: node.id)
                }
                connectFromAgentID = nil
            } else {
                // Set as source node
                connectFromAgentID = node.id
            }
        }
    }
    
    // 创建连接
    private func createConnection(from: UUID, to: UUID) {
        appState.connectNodes(from: from, to: to, bidirectional: connectionType == .bidirectional)
    }

    private func resolveAgentNodeID(from identifier: UUID) -> UUID? {
        guard let workflow = appState.currentProject?.workflows.first else { return nil }

        if workflow.nodes.contains(where: { $0.id == identifier && $0.type == .agent }) {
            return identifier
        }

        if let node = workflow.nodes.first(where: { $0.agentID == identifier && $0.type == .agent }) {
            return node.id
        }

        return nil
    }
}

// MARK: - Agent库侧边栏
struct AgentLibrarySidebar: View {
    @EnvironmentObject var appState: AppState
    var onAddAll: () -> Void
    var isOpenClawConnected: Bool = false
    var openClawAgents: [String] = []
    
    var body: some View {
        VStack(spacing: 0) {
            // 标题
            HStack {
                Image(systemName: "cube.box")
                Text(LocalizedString.agentLibrary)
                    .font(.headline)
                Spacer()
            }
            .padding()
            .background(Color(.controlBackgroundColor))
            
            // 添加所有Agent到画布按钮（仅在连接OpenClaw时显示）
            if isOpenClawConnected {
                Button(action: onAddAll) {
                    HStack {
                        Image(systemName: "plus.square.on.square")
                        Text("Generate Architecture")
                    }
                    .font(.caption)
                    .frame(maxWidth: .infinity)
                    .padding(8)
                }
                .help("Auto-detect agents from OpenClaw and generate collaboration architecture based on SOUL.md")
                .buttonStyle(.bordered)
                .padding(.horizontal)
            }
            
            Divider()
            
            // Agent列表（可拖拽）
            ScrollView {
                LazyVStack(spacing: 8) {
                    // OpenClaw Agents 组（仅在连接时显示）
                    if isOpenClawConnected && !openClawAgents.isEmpty {
                        // 组标题
                        HStack {
                            Image(systemName: "network")
                            Text(LocalizedString.openclawAgents)
                                .font(.caption)
                                .fontWeight(.semibold)
                            Spacer()
                            Text("\(openClawAgents.count)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.2))
                                .cornerRadius(4)
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)
                        
                        ForEach(openClawAgents, id: \.self) { agentName in
                            DraggableAgentItem(name: agentName)
                                .padding(.horizontal, 4)
                        }
                            
                            Divider()
                                .padding(.vertical, 8)
                    }
                    
                    // 项目中的Agents
                    let projectAgents = appState.currentProject?.agents ?? []
                    HStack {
                        Image(systemName: "folder")
                        Text(LocalizedString.projectAgents)
                            .font(.caption)
                            .fontWeight(.semibold)
                        Spacer()
                        Text("\(projectAgents.count)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.2))
                            .cornerRadius(4)
                    }
                    .padding(.horizontal)
                    
                    ForEach(projectAgents) { agent in
                        DraggableAgentItem(name: agent.name, agent: agent)
                            .padding(.horizontal, 4)
                    }
                }
                .padding()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            
            Divider()
            
            // 节点类型
            VStack(alignment: .leading, spacing: 8) {
                Text(LocalizedString.nodeTypes)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                
                HStack(spacing: 8) {
                    NodeTypeButton(icon: "play.circle.fill", label: LocalizedString.startNode, type: .start)
                    NodeTypeButton(icon: "person.circle.fill", label: LocalizedString.agentNode, type: .agent)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .background(Color(.controlBackgroundColor))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    
    private func loadOpenClawAgents() -> [String] {
        // 使用OpenClaw CLI获取agents列表
        let possiblePaths = [
            "/Users/chenrongze/.local/bin/openclaw",
            "/usr/local/bin/openclaw",
            "/opt/homebrew/bin/openclaw"
        ]
        
        var openclawPath = "/Users/chenrongze/.local/bin/openclaw"
        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                openclawPath = path
                break
            }
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: openclawPath)
        process.arguments = ["agents", "list"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                // 解析输出，提取agent名称
                var agents: [String] = []
                let lines = output.components(separatedBy: "\n")
                for line in lines {
                    // 匹配 "- agentName (default)" 格式
                    if line.hasPrefix("- ") {
                        let trimmed = line.trimmingCharacters(in: .whitespaces)
                        // 去掉 "- " 前缀和可能的 " (default)" 后缀
                        var name = String(trimmed.dropFirst(2))
                        if name.contains(" (") {
                            name = name.components(separatedBy: " (").first ?? name
                        }
                        if !name.isEmpty {
                            agents.append(name)
                        }
                    }
                }
                return agents.sorted()
            }
        } catch {
            print("Failed to run openclaw agents list: \(error)")
        }
        
        return []
    }
}

struct DraggableAgentItem: View {
    let name: String
    var agent: Agent?
    
    var body: some View {
        HStack {
            Image(systemName: "person.circle.fill")
                .foregroundColor(.accentColor)
            
            Text(name)
                .lineLimit(1)
            
            Spacer()
            
            Image(systemName: "line.3.horizontal")
                .foregroundColor(.secondary)
        }
        .padding(8)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(6)
        .onDrag { NSItemProvider(object: name as NSString) }
    }
}

struct NodeTypeButton: View {
    let icon: String
    let label: String
    let type: WorkflowNode.NodeType
    
    var body: some View {
        VStack {
            Image(systemName: icon)
                .font(.title2)
            Text(label)
                .font(.caption2)
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(6)
        .onDrag { NSItemProvider(object: "nodeType:\(type.rawValue)" as NSString) }
    }
}

// MARK: - 节点属性面板
struct NodePropertyPanel: View {
    @EnvironmentObject var appState: AppState
    let node: WorkflowNode
    @Binding var isPresented: Bool
    
    @State private var nodeTitle: String = ""
    @State private var agentDescription: String = ""
    @State private var soulConfig: String = ""
    @State private var conditionExpression: String = ""
    @State private var loopEnabled: Bool = false
    @State private var maxIterations: Double = 1
    @State private var reloadStatus: String?
    @State private var outgoingEdgeDrafts: [UUID: EdgeDraft] = [:]
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Node Properties")
                    .font(.headline)
                Spacer()
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(.windowBackgroundColor))
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    GroupBox("Node Info") {
                        VStack(alignment: .leading, spacing: 8) {
                            LabeledContent("ID") {
                                Text(node.id.uuidString.prefix(8))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            LabeledContent("Type") {
                                Text(node.type.rawValue.capitalized)
                            }

                            if node.type != .agent {
                                TextField("Title", text: $nodeTitle)
                                    .textFieldStyle(.roundedBorder)
                            }

                            LabeledContent("Position") {
                                Text("(\(Int(node.position.x)), \(Int(node.position.y)))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(8)
                    }
                    
                    if node.type == .agent, let agentID = node.agentID,
                       let agent = getAgent(id: agentID) {
                        GroupBox("Agent: \(agent.name)") {
                            VStack(alignment: .leading, spacing: 12) {
                                TextField("Name", text: $nodeTitle)
                                    .textFieldStyle(.roundedBorder)

                                TextField("Description", text: $agentDescription)
                                    .textFieldStyle(.roundedBorder)

                                Text("Soul.md Configuration")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                TextEditor(text: $soulConfig)
                                    .font(.system(.caption, design: .monospaced))
                                    .frame(height: 150)
                                    .border(Color.gray.opacity(0.3))

                                if let reloadStatus {
                                    Text(reloadStatus)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(8)
                        }
                    }
                }
                .padding()
            }
            
            Divider()
            
            // 底部按钮
            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button("Apply") {
                    saveChanges()
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 320)
        .background(Color(.windowBackgroundColor))
        .onAppear {
            loadNodeData()
        }
    }
    
    private func getAgent(id: UUID) -> Agent? {
        appState.currentProject?.agents.first { $0.id == id }
    }
    
    private func loadNodeData() {
        nodeTitle = node.title
        agentDescription = ""
        conditionExpression = node.conditionExpression
        loopEnabled = node.loopEnabled
        maxIterations = Double(max(1, node.maxIterations))

        if let agentID = node.agentID,
           let agent = getAgent(id: agentID) {
            nodeTitle = agent.name
            agentDescription = agent.description
            soulConfig = agent.soulMD
        }
    }
    
    private func saveChanges() {
        var updatedNode = node
        updatedNode.title = node.type == .agent ? "" : nodeTitle
        appState.updateNode(updatedNode)

        if let agentID = node.agentID,
           var agent = getAgent(id: agentID) {
            agent.name = nodeTitle
            agent.description = agentDescription
            agent.soulMD = soulConfig
            agent.updatedAt = Date()
            appState.updateAgent(agent, reload: true)
            reloadStatus = "Reload requested at \(Date.now.formatted(date: .omitted, time: .shortened))"
        }
    }

    private var outgoingEdges: [WorkflowEdge] {
        appState.currentProject?.workflows.first?.edges.filter { $0.fromNodeID == node.id } ?? []
    }

    private func binding(for edge: WorkflowEdge) -> Binding<EdgeDraft> {
        Binding(
            get: { outgoingEdgeDrafts[edge.id] ?? EdgeDraft(edge: edge) },
            set: { outgoingEdgeDrafts[edge.id] = $0 }
        )
    }

    private func targetName(for edge: WorkflowEdge) -> String {
        guard let workflow = appState.currentProject?.workflows.first,
              let targetNode = workflow.nodes.first(where: { $0.id == edge.toNodeID }) else {
            return "Unknown"
        }

        if let targetAgent = targetNode.agentID.flatMap(getAgent(id:)) {
            return targetAgent.name
        }

        if !targetNode.title.isEmpty {
            return targetNode.title
        }

        return targetNode.type.rawValue.capitalized
    }

    struct EdgeDraft {
        var edge: WorkflowEdge
        var label: String
        var conditionExpression: String
        var requiresApproval: Bool

        init(edge: WorkflowEdge) {
            self.edge = edge
            self.label = edge.label
            self.conditionExpression = edge.conditionExpression
            self.requiresApproval = edge.requiresApproval
        }
    }
}

struct RouteEditorRow: View {
    @Binding var edge: NodePropertyPanel.EdgeDraft
    let targetName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "arrow.turn.down.right")
                    .foregroundColor(.secondary)
                Text(targetName)
                    .font(.caption)
                    .fontWeight(.medium)
                Spacer()
                Toggle("Approval", isOn: $edge.requiresApproval)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            TextField("Condition label", text: $edge.label)
                .textFieldStyle(.roundedBorder)

            TextField("Condition expression", text: $edge.conditionExpression)
                .textFieldStyle(.roundedBorder)
        }
        .padding(10)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }
}

struct EdgePropertyPanel: View {
    @EnvironmentObject var appState: AppState
    let edge: WorkflowEdge
    @Binding var isPresented: Bool

    @State private var label: String = ""
    @State private var conditionExpression: String = ""
    @State private var requiresApproval: Bool = false
    @State private var dataMappingText: String = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Edge Properties", systemImage: "arrowshape.right")
                    .font(.headline)
                Spacer()
                Button("Close") {
                    isPresented = false
                }
                .buttonStyle(.borderless)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    GroupBox("Route Summary") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("From: \(sourceName)")
                            Text("To: \(targetName)")
                            Text("Edge ID: \(edge.id.uuidString.prefix(8))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                    }

                    GroupBox("Visual Summary") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 10) {
                                summaryBadge(text: sourceName, color: .blue)
                                Image(systemName: "arrow.right")
                                    .foregroundColor(.secondary)
                                summaryBadge(text: targetName, color: .green)
                            }

                            HStack(spacing: 8) {
                                summaryBadge(
                                    text: label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Unlabeled route" : label,
                                    color: .accentColor
                                )
                                if requiresApproval {
                                    summaryBadge(text: "Approval", color: .orange)
                                }
                            }

                            Text(
                                conditionExpression.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? "No condition expression. This route is always eligible when reached."
                                    : conditionExpression
                            )
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                    }
                }
                .padding()
            }

            Divider()

            HStack {
                Button("Delete Route", role: .destructive) {
                    appState.removeEdge(edge.id)
                    isPresented = false
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Close") {
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 320)
        .background(Color(.windowBackgroundColor))
        .onAppear {
            label = edge.label
            conditionExpression = edge.conditionExpression
            requiresApproval = edge.requiresApproval
            dataMappingText = formattedDataMapping(edge.dataMapping)
        }
    }

    private var sourceName: String { endpointName(for: edge.fromNodeID) }
    private var targetName: String { endpointName(for: edge.toNodeID) }

    private func summaryBadge(text: String, color: Color) -> some View {
        Text(text)
            .font(.caption)
            .fontWeight(.medium)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.14))
            .foregroundColor(color)
            .clipShape(Capsule())
    }

    private func formattedDataMapping(_ mapping: [String: String]) -> String {
        mapping
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "\n")
    }

    private func parseDataMapping() -> [String: String] {
        dataMappingText
            .split(whereSeparator: \.isNewline)
            .reduce(into: [String: String]()) { result, line in
                let parts = line.split(separator: "=", maxSplits: 1).map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return }
                result[parts[0]] = parts[1]
            }
    }

    private func endpointName(for nodeID: UUID) -> String {
        guard let workflow = appState.currentProject?.workflows.first,
              let node = workflow.nodes.first(where: { $0.id == nodeID }) else {
            return "Unknown"
        }

        if let agentID = node.agentID,
           let agent = appState.currentProject?.agents.first(where: { $0.id == agentID }) {
            return agent.name
        }

        if !node.title.isEmpty {
            return node.title
        }

        return node.type.rawValue.capitalized
    }
}

// MARK: - 右键菜单
struct AgentContextMenu: View {
    @EnvironmentObject var appState: AppState
    let agent: Agent
    
    @State private var showEditSheet = false
    @State private var showSkillsSheet = false
    @State private var showPermissionsSheet = false
    @State private var showDeleteAlert = false
    
    // 点击反馈状态
    @State private var showToast = false
    @State private var toastMessage = ""
    @State private var toastType: ToastType = .success
    
    enum ToastType {
        case success, error, info
    }
    
    var body: some View {
        Button(action: { openAgent() }) {
            Label("Open", systemImage: "folder")
        }
        
        Divider()
        
        Button(action: { copyAgent() }) {
            Label("Copy", systemImage: "doc.on.doc")
        }

        Button(action: { cutAgent() }) {
            Label("Cut", systemImage: "scissors")
        }

        Button(action: { pasteAgent() }) {
            Label("Paste", systemImage: "doc.on.clipboard")
        }
        
        Divider()
        
        Button(action: { exportAgent() }) {
            Label("Export", systemImage: "square.and.arrow.up")
        }
        
        Divider()
        
        Button(action: { showEditSheet = true }) {
            Label("Edit SOUL.md", systemImage: "doc.text")
        }
        
        Button(action: { showSkillsSheet = true }) {
            Label("Manage Skills", systemImage: "star")
        }
        
        Button(action: { showPermissionsSheet = true }) {
            Label("Configure Permissions", systemImage: "lock.shield")
        }
        
        Divider()
        
        Button(action: { duplicateAgent() }) {
            Label("Duplicate", systemImage: "plus.square.on.square")
        }
        
        Button(action: { resetAgent() }) {
            Label("Reset", systemImage: "arrow.counterclockwise")
        }
        
        Divider()
        
        Button(action: { showDeleteAlert = true }) {
            Label("Delete", systemImage: "trash")
        }
        .foregroundColor(.red)
        
        // Edit SOUL.md Sheet
        if showEditSheet {
            AgentEditSheet(agent: agent, isPresented: $showEditSheet)
        }
        
        // Skills Sheet
        if showSkillsSheet {
            SkillsManagementSheet(agent: agent, isPresented: $showSkillsSheet)
        }
        
        // Permissions Sheet
        if showPermissionsSheet {
            PermissionsConfigSheet(agent: agent, isPresented: $showPermissionsSheet)
        }
        
        // Delete Alert
        if showDeleteAlert {
            DeleteConfirmation(agent: agent, isPresented: $showDeleteAlert)
        }
        
        // Toast 反馈
        if showToast {
            ToastView(message: toastMessage, type: toastType)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation {
                            showToast = false
                        }
                    }
                }
        }
    }
    
    private func showToastMessage(_ message: String, type: ToastType) {
        toastMessage = message
        toastType = type
        withAnimation {
            showToast = true
        }
    }
    
    private func openAgent() {
        // Select the agent in the editor
        if let project = appState.currentProject,
           project.agents.contains(where: { $0.id == agent.id }) {
            // Show agent details in properties panel
            appState.selectedNodeID = agent.id
            showToastMessage("Opened: \(agent.name)", type: .info)
        }
    }
    
    private func copyAgent() {
        if appState.copyAgent(agent) {
            showToastMessage("Copied: \(agent.name)", type: .success)
        } else {
            showToastMessage("Copy failed", type: .error)
        }
    }

    private func cutAgent() {
        if appState.cutAgent(agent.id) {
            showToastMessage("Cut: \(agent.name)", type: .success)
        } else {
            showToastMessage("Cut failed", type: .error)
        }
    }

    private func pasteAgent() {
        if let newAgent = appState.pasteAgentFromPasteboard() {
            showToastMessage("Pasted: \(newAgent.name)", type: .success)
        } else {
            showToastMessage("Paste failed", type: .error)
        }
    }
    
    private func duplicateAgent() {
        if let newAgent = appState.duplicateAgent(agent.id, suffix: "Duplicate", offset: CGPoint(x: 50, y: 50)) {
            showToastMessage("Duplicated: \(newAgent.name)", type: .success)
        } else {
            showToastMessage("Duplicate failed", type: .error)
        }
    }
    
    private func exportAgent() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(agent.name).json"
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                do {
                    let data = try JSONEncoder().encode(agent)
                    try data.write(to: url)
                    self.showToastMessage("Exported: \(agent.name)", type: .success)
                } catch {
                    self.showToastMessage("Export failed: \(error.localizedDescription)", type: .error)
                }
            }
        }
    }
    
    private func resetAgent() {
        var updatedAgent = agent
        updatedAgent.updatedAt = Date()
        appState.updateAgent(updatedAgent, reload: true)
        showToastMessage("Reset: \(agent.name)", type: .success)
    }
}

// MARK: - Toast View
struct ToastView: View {
    let message: String
    let type: AgentContextMenu.ToastType
    
    var backgroundColor: Color {
        switch type {
        case .success: return .green
        case .error: return .red
        case .info: return .blue
        }
    }
    
    var icon: String {
        switch type {
        case .success: return "checkmark.circle.fill"
        case .error: return "xmark.circle.fill"
        case .info: return "info.circle.fill"
        }
    }
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
            Text(message)
                .font(.caption)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(backgroundColor)
        .foregroundColor(.white)
        .cornerRadius(20)
        .shadow(radius: 4)
        .padding(.bottom, 20)
    }
}

// MARK: - Edit Sheet
struct AgentEditSheet: View {
    @EnvironmentObject var appState: AppState
    let agent: Agent
    @Binding var isPresented: Bool
    
    @State private var name: String = ""
    @State private var description: String = ""
    @State private var soulMD: String = ""
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Edit Agent: \(agent.name)")
                .font(.headline)
            
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
            
            TextField("Description", text: $description)
                .textFieldStyle(.roundedBorder)
            
            Text("SOUL.md Configuration")
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            TextEditor(text: $soulMD)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 200)
                .border(Color.gray.opacity(0.3))
            
            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button("Save") {
                    saveChanges()
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 500, height: 450)
        .onAppear {
            loadAgentData()
        }
    }
    
    private func loadAgentData() {
        if let project = appState.currentProject,
           let a = project.agents.first(where: { $0.id == agent.id }) {
            name = a.name
            description = a.description
            soulMD = a.soulMD
        }
    }
    
    private func saveChanges() {
        var updatedAgent = agent
        updatedAgent.name = name
        updatedAgent.description = description
        updatedAgent.soulMD = soulMD
        updatedAgent.updatedAt = Date()
        appState.updateAgent(updatedAgent, reload: true)
    }
}

// MARK: - Skills Management Sheet
struct SkillsManagementSheet: View {
    @EnvironmentObject var appState: AppState
    let agent: Agent
    @Binding var isPresented: Bool
    
    @State private var availableSkills: [String] = []
    @State private var selectedSkills: Set<String> = []
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Manage Skills: \(agent.name)")
                .font(.headline)
            
            // Current skills
            VStack(alignment: .leading) {
                Text("Current Skills")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                if selectedSkills.isEmpty {
                    Text("No skills assigned")
                        .foregroundColor(.secondary)
                } else {
                    FlowLayout(spacing: 8) {
                        ForEach(Array(selectedSkills), id: \.self) { skill in
                            SkillTag(skill: skill, isSelected: true) {
                                selectedSkills.remove(skill)
                            }
                        }
                    }
                }
            }
            
            Divider()
            
            // Available skills
            VStack(alignment: .leading) {
                Text("Available Skills")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                FlowLayout(spacing: 8) {
                    ForEach(availableSkills.filter { !selectedSkills.contains($0) }, id: \.self) { skill in
                        SkillTag(skill: skill, isSelected: false) {
                            selectedSkills.insert(skill)
                        }
                    }
                }
            }
            
            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button("Save") {
                    saveSkills()
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 450, height: 350)
        .onAppear {
            loadSkills()
        }
    }
    
    private func loadSkills() {
        // Load from OpenClaw skills directory
        let skillsPath = NSHomeDirectory() + "/.openclaw/agents/" + agent.name + "/skills"
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: skillsPath) {
            availableSkills = contents.filter { $0.hasSuffix(".md") }
        }
        
        // Current skills from agent
        selectedSkills = Set(agent.capabilities)
    }
    
    private func saveSkills() {
        guard var project = appState.currentProject,
              let index = project.agents.firstIndex(where: { $0.id == agent.id }) else { return }
        
        project.agents[index].capabilities = Array(selectedSkills)
        project.agents[index].updatedAt = Date()
        
        appState.currentProject = project
    }
}

struct SkillTag: View {
    let skill: String
    let isSelected: Bool
    var onRemove: () -> Void = {}
    
    var body: some View {
        HStack(spacing: 4) {
            Text(skill.replacingOccurrences(of: ".md", with: ""))
                .font(.caption)
            
            if isSelected {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
}


// MARK: - Permissions Config Sheet
struct PermissionsConfigSheet: View {
    @EnvironmentObject var appState: AppState
    let agent: Agent
    @Binding var isPresented: Bool
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Configure Permissions: \(agent.name)")
                .font(.headline)
            
            if let project = appState.currentProject {
                List {
                    ForEach(project.agents) { otherAgent in
                        if otherAgent.id != agent.id {
                            HStack {
                                Text(otherAgent.name)
                                Spacer()
                                Text(permissionText(for: otherAgent))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            
            HStack {
                Button("Close") {
                    isPresented = false
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .frame(width: 400, height: 300)
    }
    
    private func permissionText(for otherAgent: Agent) -> String {
        if let project = appState.currentProject {
            let perm = project.permission(from: agent, to: otherAgent)
            return perm == .allow ? "Allowed" : "Denied"
        }
        return "Unknown"
    }
}

// MARK: - Delete Confirmation
struct DeleteConfirmation: View {
    @EnvironmentObject var appState: AppState
    let agent: Agent
    @Binding var isPresented: Bool
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundColor(.red)
            
            Text("Delete Agent?")
                .font(.headline)
            
            Text("Are you sure you want to delete \"\(agent.name)\"? This action cannot be undone.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            
            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button("Delete") {
                    deleteAgent()
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
        .padding()
        .frame(width: 350)
    }
    
    private func deleteAgent() {
        appState.deleteAgent(agent.id)
    }
}

// MARK: - 测试执行
struct WorkflowTestExecution: Identifiable {
    let id = UUID()
    var workflow: Workflow
    var agents: [Agent]
    var steps: [WorkflowTestStep] = []
    var currentStep: Int = 0
}

struct WorkflowTestStep: Identifiable {
    let id = UUID()
    var stepNumber: Int
    var agentID: UUID
    var agentName: String
    var action: String
    var status: StepStatus
    var timestamp: Date
    var completedAt: Date?
    
    enum StepStatus {
        case pending, running, completed, failed
    }
}

struct TestExecutionPanel: View {
    var execution: WorkflowTestExecution
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Workflow Test Execution")
                    .font(.headline)
                Spacer()
                Text("Step \(execution.currentStep)/\(execution.steps.count)")
                    .foregroundColor(.secondary)
            }
            
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(execution.steps) { step in
                        TestStepRow(step: step)
                    }
                }
            }
        }
        .padding()
        .frame(height: 200)
        .background(Color(.controlBackgroundColor))
    }
}

struct TestStepRow: View {
    let step: WorkflowTestStep
    
    var body: some View {
        HStack {
            // 状态图标
            switch step.status {
            case .pending:
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 20, height: 20)
            case .running:
                ProgressView()
                    .scaleEffect(0.6)
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
            }
            
            Text("\(step.stepNumber).")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 24)
            
            Text(step.agentName)
                .font(.caption)
                .fontWeight(.medium)
            
            Spacer()
            
            Text(step.action)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(step.status == .running ? Color.blue.opacity(0.1) : Color.clear)
    }
}
