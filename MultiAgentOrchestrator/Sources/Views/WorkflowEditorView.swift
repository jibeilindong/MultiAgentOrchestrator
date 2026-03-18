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
            // 工具栏
            EditorToolbar(
                viewMode: $viewMode,
                isConnectMode: $isConnectMode,
                connectFromAgentID: $connectFromAgentID,
                connectionType: $connectionType,
                onRunTest: runTest,
                onStopTest: stopTest
            )
            .zIndex(1000) // 确保工具栏始终在最上层
            
            Divider()
            
            // 主内容区
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
                        isConnectMode: isConnectMode,
                        connectFromAgentID: $connectFromAgentID,
                        connectionType: connectionType,
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
    }
    
    private func handleAgentConnection(from: UUID, to: UUID) {
        guard var project = appState.currentProject,
              var workflow = project.workflows.first else { return }
        
        // 添加连接边（从源到目标）
        let edge = WorkflowEdge(from: from, to: to)
        workflow.edges.append(edge)
        
        // 添加权限到权限矩阵
        addPermission(from: from, to: to, bidirectional: connectionType == .bidirectional)
        
        // 如果是双向连接，还需要添加反向边
        if connectionType == .bidirectional {
            let reverseEdge = WorkflowEdge(from: to, to: from)
            workflow.edges.append(reverseEdge)
        }
        
        // 更新项目
        if let index = project.workflows.firstIndex(where: { $0.id == workflow.id }) {
            project.workflows[index] = workflow
            appState.currentProject = project
        }
        
        // 清除连接模式
        connectFromAgentID = nil
    }
    
    // 添加权限到权限矩阵
    private func addPermission(from: UUID, to: UUID, bidirectional: Bool) {
        guard var project = appState.currentProject else { return }
        
        // 添加从源到目标的权限（允许）
        let forwardPerm = Permission(fromAgentID: from, toAgentID: to, permissionType: .allow)
        project.permissions.append(forwardPerm)
        
        // 如果是双向连接，添加反向权限
        if bidirectional {
            let reversePerm = Permission(fromAgentID: to, toAgentID: from, permissionType: .allow)
            project.permissions.append(reversePerm)
        }
        
        appState.currentProject = project
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
        
        // 按拓扑顺序执行节点
        let agentNodes = workflow.nodes.filter { $0.type == .agent }
        
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
}

// MARK: - 工具栏
struct EditorToolbar: View {
    @EnvironmentObject var appState: AppState
    @Binding var viewMode: WorkflowEditorView.EditorViewMode
    @Binding var isConnectMode: Bool
    @Binding var connectFromAgentID: UUID?
    @Binding var connectionType: WorkflowEditorView.ConnectionType
    var onRunTest: () -> Void
    var onStopTest: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // 视图选择器 - 改进版
            HStack(spacing: 4) {
                ForEach(WorkflowEditorView.EditorViewMode.allCases, id: \.self) { mode in
                    Button(action: { viewMode = mode }) {
                        HStack(spacing: 4) {
                            Image(systemName: mode.icon)
                            Text(mode.rawValue)
                                .font(.caption)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(viewMode == mode ? Color.accentColor.opacity(0.2) : Color.clear)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(viewMode == mode ? .accentColor : .secondary)
                }
            }
            .padding(4)
            .background(Color(.controlBackgroundColor))
            .cornerRadius(8)
            
            Divider()
                .frame(height: 20)
            
            // 连接类型选择器
            HStack(spacing: 4) {
                ForEach(WorkflowEditorView.ConnectionType.allCases, id: \.self) { type in
                    Button(action: {
                        isConnectMode = true
                        connectionType = type
                    }) {
                        HStack(spacing: 2) {
                            Text(type.rawValue)
                                .font(.headline)
                            Text(type.description)
                                .font(.caption)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(isConnectMode && connectionType == type ? Color.blue.opacity(0.2) : Color.clear)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(isConnectMode && connectionType == type ? .blue : .secondary)
                }
            }
            .padding(4)
            .background(Color(.controlBackgroundColor))
            .cornerRadius(8)
            .tint(isConnectMode ? .blue : nil)
            
            // 连接状态提示
            if isConnectMode {
                Text("Select target agent")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
            
            Divider()
                .frame(height: 20)
            
            // 测试按钮
            Button(action: onRunTest) {
                HStack(spacing: 4) {
                    Image(systemName: "play.circle")
                    Text("Test")
                        .font(.caption)
                }
            }
            .buttonStyle(.bordered)
            
            Spacer()
            
            // OpenClaw连接状态
            HStack(spacing: 8) {
                // 连接状态指示
                Circle()
                    .fill(appState.openClawService.isConnected ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                
                Text(appState.openClawService.isConnected ? "OpenClaw Connected" : "OpenClaw Disconnected")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                // 手动连接按钮
                Button(action: { appState.openClawService.checkConnection() }) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Refresh connection")
            }
            
            Divider()
                .frame(height: 20)
            
            // 自动识别Agents按钮
            Button(action: { 
                appState.openClawManager.connect()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "wand.and.stars")
                    Text("Auto Detect")
                        .font(.caption)
                }
            }
            .buttonStyle(.bordered)
            .help("Auto-detect OpenClaw agents")
            
            Divider()
                .frame(height: 20)
            
            // 自动保存状态指示器
            if appState.isAutoSaving {
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("Saving...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else if let lastSave = appState.lastAutoSaveTime {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Auto-saved")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .help("Last saved: \(lastSave.formatted(date: .omitted, time: .shortened))")
            }
            
            // 手动保存按钮
            Button(action: { appState.saveProject() }) {
                HStack(spacing: 4) {
                    Image(systemName: "square.and.arrow.down")
                    Text("Save")
                        .font(.caption)
                }
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.windowBackgroundColor))
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
            Text("M2.5")
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
    var isConnectMode: Bool
    @Binding var connectFromAgentID: UUID?
    var connectionType: WorkflowEditorView.ConnectionType
    var onConnect: (UUID, UUID) -> Void
    var testExecution: WorkflowTestExecution?
    
    @State private var showNodePropertyPanel = false
    @State private var selectedNodeForProperty: WorkflowNode?
    
    var body: some View {
        HStack(spacing: 0) {
            // Agent库侧边栏
            AgentLibrarySidebar(
                onAddAll: { self.addAllAgentsToCanvas() },
                isOpenClawConnected: appState.openClawManager.isConnected,
                openClawAgents: appState.openClawManager.agents
            )
                .frame(width: 200)
            
            Divider()
            
            // 画布区域
            ZStack {
                CanvasView(
                    zoomScale: $zoomScale,
                    isConnectMode: isConnectMode,
                    onNodeClickInConnectMode: { node in
                        self.handleNodeClickInConnectMode(node: node)
                    }
                )
                    .onDrop(of: [.text], isTargeted: nil) { providers, location in
                        handleDrop(providers: providers, location: location)
                    }
                
                // 节点属性面板（从右侧滑入）
                if showNodePropertyPanel, let node = selectedNodeForProperty {
                    NodePropertyPanel(
                        node: node,
                        isPresented: $showNodePropertyPanel
                    )
                    .transition(.move(edge: .trailing))
                }
            }
        }
    }
    
    private func handleDrop(providers: [NSItemProvider], location: CGPoint) -> Bool {
        // Handle dropped Agent from library
        for provider in providers {
            provider.loadObject(ofClass: NSString.self) { item, error in
                if let agentName = item as? String {
                    DispatchQueue.main.async {
                        addAgentNodeToCanvas(agentName: agentName, at: location)
                    }
                }
            }
        }
        return true
    }
    
    private func addAgentNodeToCanvas(agentName: String, at location: CGPoint) {
        guard var project = appState.currentProject else { return }
        
        // 确保有workflow
        if project.workflows.isEmpty {
            var newWorkflow = Workflow(name: "Main Workflow")
            project.workflows.append(newWorkflow)
        }
        
        guard var workflow = project.workflows.first else { return }
        
        // 查找或创建agent
        var agent: Agent
        if let existingAgent = project.agents.first(where: { $0.name == agentName }) {
            agent = existingAgent
        } else {
            // 如果agent不存在，创建一个新的
            agent = Agent(name: agentName)
            agent.description = "Agent: \(agentName)"
            project.agents.append(agent)
        }
        
        // 使用更明显的位置（画布中心偏上）
        let dropPosition = CGPoint(x: max(100, location.x), y: max(100, location.y))
        
        // Create new node at drop location
        var newNode = WorkflowNode(type: .agent)
        newNode.agentID = agent.id
        newNode.position = dropPosition
        
        workflow.nodes.append(newNode)
        
        print("Added node for agent: \(agentName) at position: \(dropPosition)")
        
        // Update project
        if let index = project.workflows.firstIndex(where: { $0.id == workflow.id }) {
            project.workflows[index] = workflow
        }
        appState.currentProject = project
    }
    
    // 添加所有OpenClaw agents到画布
    private func addAllAgentsToCanvas() {
        guard var project = appState.currentProject,
              var workflow = project.workflows.first else { return }
        
        // 清除现有节点
        workflow.nodes.removeAll()
        workflow.edges.removeAll()
        
        // 计算布局 - 根据角色分组
        let agentPositions = calculateAgentPositions(agents: project.agents)
        
        for (agent, position) in agentPositions {
            var newNode = WorkflowNode(type: .agent)
            newNode.agentID = agent.id
            newNode.position = position
            workflow.nodes.append(newNode)
        }
        
        // 自动生成连接
        let connections = analyzeAndGenerateConnections(agents: project.agents)
        for (fromName, toName) in connections {
            if let fromAgent = project.agents.first(where: { $0.name == fromName }),
               let toAgent = project.agents.first(where: { $0.name == toName }),
               let fromNode = workflow.nodes.first(where: { $0.agentID == fromAgent.id }),
               let toNode = workflow.nodes.first(where: { $0.agentID == toAgent.id }) {
                let edge = WorkflowEdge(from: fromNode.id, to: toNode.id)
                workflow.edges.append(edge)
                
                // 添加权限
                let perm = Permission(fromAgentID: fromAgent.id, toAgentID: toAgent.id, permissionType: .allow)
                project.permissions.append(perm)
            }
        }
        
        // 更新项目
        if let index = project.workflows.firstIndex(where: { $0.id == workflow.id }) {
            project.workflows[index] = workflow
            appState.currentProject = project
        }
    }
    
    // 计算agent位置（基于角色层级）
    private func calculateAgentPositions(agents: [Agent]) -> [(Agent, CGPoint)] {
        var positions: [(Agent, CGPoint)] = []
        
        // 定义层级
        let tier1 = ["taizi", "太子"]  // 接收消息
        let tier2 = ["zhongshu", "中书省"]  // 处理任务
        let tier3 = ["shangshu", "尚书省"]  // 结果汇总
        let tier4 = ["menxia", "门下省"]  // 审核
        let departments = ["libu", "吏部", "hubu", "户部", "bingbu", "兵部", "xingbu", "刑部", "gongbu", "工部", "libu_hr", "吏部HR", "zaochao", "早朝"]
        
        var tier1Agents: [Agent] = []
        var tier2Agents: [Agent] = []
        var tier3Agents: [Agent] = []
        var tier4Agents: [Agent] = []
        var deptAgents: [Agent] = []
        
        for agent in agents {
            let name = agent.name.lowercased()
            if tier1.contains(where: { name.contains($0.lowercased()) }) {
                tier1Agents.append(agent)
            } else if tier2.contains(where: { name.contains($0.lowercased()) }) {
                tier2Agents.append(agent)
            } else if tier3.contains(where: { name.contains($0.lowercased()) }) {
                tier3Agents.append(agent)
            } else if tier4.contains(where: { name.contains($0.lowercased()) }) {
                tier4Agents.append(agent)
            } else {
                deptAgents.append(agent)
            }
        }
        
        // 布局参数
        let startX: CGFloat = 100
        let startY: CGFloat = 80
        let tierSpacing: CGFloat = 200
        let nodeSpacing: CGFloat = 160
        
        // 第一层：太子
        for (index, agent) in tier1Agents.enumerated() {
            positions.append((agent, CGPoint(x: startX + CGFloat(index) * nodeSpacing, y: startY)))
        }
        
        // 第二层：中书省
        for (index, agent) in tier2Agents.enumerated() {
            positions.append((agent, CGPoint(x: startX + CGFloat(index) * nodeSpacing, y: startY + tierSpacing)))
        }
        
        // 第三层：尚书省
        for (index, agent) in tier3Agents.enumerated() {
            positions.append((agent, CGPoint(x: startX + CGFloat(index) * nodeSpacing, y: startY + tierSpacing * 2)))
        }
        
        // 第四层：门下省
        for (index, agent) in tier4Agents.enumerated() {
            positions.append((agent, CGPoint(x: startX + CGFloat(index) * nodeSpacing, y: startY + tierSpacing * 3)))
        }
        
        // 部门：六部
        let columns = 4
        for (index, agent) in deptAgents.enumerated() {
            let col = index % columns
            let row = index / columns
            positions.append((agent, CGPoint(x: startX + CGFloat(col) * nodeSpacing, y: startY + tierSpacing * 4 + CGFloat(row) * 100)))
        }
        
        return positions
    }
    
    // 分析并生成连接关系
    private func analyzeAndGenerateConnections(agents: [Agent]) -> [(String, String)] {
        var connections: [(String, String)] = []
        
        // 从SOUL.md和配置中分析关系
        // 1. 太子 -> 中书省
        if agents.contains(where: { $0.name == "taizi" || $0.name == "太子" }) &&
           agents.contains(where: { $0.name == "zhongshu" || $0.name == "中书省" }) {
            connections.append(("taizi", "zhongshu"))
            connections.append(("太子", "中书省"))
        }
        
        // 2. 中书省 -> 尚书省
        if agents.contains(where: { $0.name == "zhongshu" || $0.name == "中书省" }) &&
           agents.contains(where: { $0.name == "shangshu" || $0.name == "尚书省" }) {
            connections.append(("zhongshu", "shangshu"))
            connections.append(("中书省", "尚书省"))
        }
        
        // 3. 尚书省 -> 太子（返回结果）
        if agents.contains(where: { $0.name == "shangshu" || $0.name == "尚书省" }) &&
           agents.contains(where: { $0.name == "taizi" || $0.name == "太子" }) {
            connections.append(("shangshu", "taizi"))
            connections.append(("尚书省", "太子"))
        }
        
        // 4. 中书省 -> 各部门
        let departments = ["libu", "吏部", "hubu", "户部", "bingbu", "兵部", "xingbu", "刑部", "gongbu", "工部", "libu_hr", "menxia", "门下省"]
        for dept in departments {
            if agents.contains(where: { $0.name == "zhongshu" || $0.name == "中书省" }) &&
               agents.contains(where: { $0.name == dept }) {
                connections.append(("zhongshu", dept))
                connections.append(("中书省", dept))
            }
        }
        
        // 5. 尚书省 -> 各部门（审核）
        for dept in departments {
            if agents.contains(where: { $0.name == "shangshu" || $0.name == "尚书省" }) &&
               agents.contains(where: { $0.name == dept }) {
                connections.append((dept, "shangshu"))
                connections.append((dept, "尚书省"))
            }
        }
        
        // 6. 部门之间可能的协作（工部与其他）
        if agents.contains(where: { $0.name == "gongbu" || $0.name == "工部" }) {
            // 工部可以与其他部门协作
        }
        
        return connections
    }
    
    // 处理连接模式下的节点点击
    private func handleNodeClickInConnectMode(node: WorkflowNode) {
        if isConnectMode {
            if let fromID = connectFromAgentID {
                // Create connection from source to this node
                self.createConnection(from: fromID, to: node.id)
                connectFromAgentID = nil
            } else {
                // Set as source node
                connectFromAgentID = node.id
            }
        }
    }
    
    // 创建连接
    private func createConnection(from: UUID, to: UUID) {
        guard var project = appState.currentProject,
              var workflow = project.workflows.first else { return }
        
        // 添加连接边（从源到目标）
        let edge = WorkflowEdge(from: from, to: to)
        workflow.edges.append(edge)
        
        // 添加权限到权限矩阵
        addPermission(from: from, to: to, bidirectional: connectionType == .bidirectional)
        
        // 如果是双向连接，还需要添加反向边
        if connectionType == .bidirectional {
            let reverseEdge = WorkflowEdge(from: to, to: from)
            workflow.edges.append(reverseEdge)
        }
        
        // 更新项目
        if let index = project.workflows.firstIndex(where: { $0.id == workflow.id }) {
            project.workflows[index] = workflow
            appState.currentProject = project
        }
    }
    
    // 添加权限到权限矩阵
    private func addPermission(from: UUID, to: UUID, bidirectional: Bool) {
        guard var project = appState.currentProject else { return }
        
        // 添加从源到目标的权限（允许）
        let forwardPerm = Permission(fromAgentID: from, toAgentID: to, permissionType: .allow)
        project.permissions.append(forwardPerm)
        
        // 如果是双向连接，添加反向权限
        if bidirectional {
            let reversePerm = Permission(fromAgentID: to, toAgentID: from, permissionType: .allow)
            project.permissions.append(reversePerm)
        }
        
        appState.currentProject = project
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
                Text("Agent Library")
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
                            Text("OpenClaw Agents")
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
                        Text("Project Agents")
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
            
            Divider()
            
            // 节点类型
            VStack(alignment: .leading, spacing: 8) {
                Text("Node Types")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                
                HStack(spacing: 8) {
                    NodeTypeButton(icon: "play.circle", label: "Start", type: .start)
                    NodeTypeButton(icon: "circle", label: "Agent", type: .agent)
                    NodeTypeButton(icon: "arrow.triangle.branch", label: "Branch", type: .agent)
                    NodeTypeButton(icon: "stop.circle", label: "End", type: .end)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .background(Color(.controlBackgroundColor))
        }
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
        .onDrag { NSItemProvider(object: type.rawValue as NSString) }
    }
}

// MARK: - 节点属性面板
struct NodePropertyPanel: View {
    @EnvironmentObject var appState: AppState
    let node: WorkflowNode
    @Binding var isPresented: Bool
    
    @State private var nodeName: String = ""
    @State private var soulConfig: String = ""
    @State private var condition: String = ""
    @State private var cpuQuota: Double = 1.0
    @State private var memoryQuota: Double = 1.0
    
    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
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
                    // 节点信息
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
                            
                            LabeledContent("Position") {
                                Text("(\(Int(node.position.x)), \(Int(node.position.y)))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(8)
                    }
                    
                    // Agent配置（如果是Agent节点）
                    if node.type == .agent, let agentID = node.agentID,
                       let agent = getAgent(id: agentID) {
                        GroupBox("Agent: \(agent.name)") {
                            VStack(alignment: .leading, spacing: 12) {
                                TextField("Name", text: $nodeName)
                                    .textFieldStyle(.roundedBorder)
                                
                                Text("Soul.md Configuration")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                TextEditor(text: $soulConfig)
                                    .font(.system(.caption, design: .monospaced))
                                    .frame(height: 150)
                                    .border(Color.gray.opacity(0.3))
                                
                                // 资源配额
                                Text("Resource Quota")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                HStack {
                                    Text("CPU")
                                    Slider(value: $cpuQuota, in: 0.1...4.0, step: 0.1)
                                    Text("\(cpuQuota, specifier: "%.1f")x")
                                        .font(.caption)
                                }
                                
                                HStack {
                                    Text("Memory")
                                    Slider(value: $memoryQuota, in: 0.1...4.0, step: 0.1)
                                    Text("\(memoryQuota, specifier: "%.1f")x")
                                        .font(.caption)
                                }
                            }
                            .padding(8)
                        }
                    }
                    
                    // 分支/条件配置（如果是控制节点）
                    if node.type == .start || node.type == .end {
                        GroupBox("Flow Control") {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Condition (e.g., priority > high)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                TextField("condition", text: $condition)
                                    .textFieldStyle(.roundedBorder)
                                
                                Text("Available variables:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Text("task.priority, task.status, agent.load, time.hour")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(8)
                        }
                    }
                    
                    // 循环配置（可选）
                    GroupBox("Loop Settings") {
                        Toggle("Enable Loop", isOn: .constant(false))
                        TextField("Max Iterations", value: .constant(10), format: .number)
                            .textFieldStyle(.roundedBorder)
                        .padding(8)
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
        if let agentID = node.agentID,
           let agent = getAgent(id: agentID) {
            nodeName = agent.name
            soulConfig = agent.soulMD
        }
    }
    
    private func saveChanges() {
        // Save changes to workflow node and agent
        guard var project = appState.currentProject,
              var workflow = project.workflows.first,
              let nodeIndex = workflow.nodes.firstIndex(where: { $0.id == node.id }) else { return }
        
        // Update node name if changed
        if let agentID = node.agentID,
           let agentIndex = project.agents.firstIndex(where: { $0.id == agentID }) {
            project.agents[agentIndex].name = nodeName
            project.agents[agentIndex].soulMD = soulConfig
            project.agents[agentIndex].updatedAt = Date()
        }
        
        appState.currentProject = project
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
    @State private var copiedAgent: Agent?
    
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
        
        Button(action: { pasteAgent() }) {
            Label("Paste", systemImage: "doc.on.clipboard")
        }
        .disabled(copiedAgent == nil)
        
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
           let index = project.agents.firstIndex(where: { $0.id == agent.id }) {
            // Show agent details in properties panel
            appState.selectedNodeID = agent.id
            showToastMessage("Opened: \(agent.name)", type: .info)
        }
    }
    
    private func copyAgent() {
        copiedAgent = agent
        // Copy to pasteboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        // Store as JSON string for cross-app compatibility
        if let data = try? JSONEncoder().encode(agent),
           let jsonString = String(data: data, encoding: .utf8) {
            pasteboard.setString(jsonString, forType: .string)
            showToastMessage("Copied: \(agent.name)", type: .success)
        } else {
            showToastMessage("Copy failed", type: .error)
        }
    }
    
    private func pasteAgent() {
        guard let project = appState.currentProject,
              let copied = copiedAgent else {
            showToastMessage("No agent to paste", type: .error)
            return
        }
        
        // Create a new agent with copied properties but new ID
        var newAgent = Agent(name: copied.name + " (Copy)")
        newAgent.description = copied.description
        newAgent.soulMD = copied.soulMD
        newAgent.capabilities = copied.capabilities
        newAgent.position = CGPoint(x: copied.position.x + 50, y: copied.position.y + 50)
        
        var updatedProject = project
        updatedProject.agents.append(newAgent)
        appState.currentProject = updatedProject
        showToastMessage("Pasted: \(newAgent.name)", type: .success)
    }
    
    private func duplicateAgent() {
        guard var project = appState.currentProject else {
            showToastMessage("No project", type: .error)
            return
        }
        
        var newAgent = Agent(name: agent.name + " (Duplicate)")
        newAgent.description = agent.description
        newAgent.soulMD = agent.soulMD
        newAgent.capabilities = agent.capabilities
        newAgent.position = CGPoint(x: agent.position.x + 50, y: agent.position.y + 50)
        
        project.agents.append(newAgent)
        appState.currentProject = project
        showToastMessage("Duplicated: \(newAgent.name)", type: .success)
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
        guard var project = appState.currentProject,
              let index = project.agents.firstIndex(where: { $0.id == agent.id }) else {
            showToastMessage("Reset failed", type: .error)
            return
        }
        
        // Reset agent to default state
        var updatedAgent = project.agents[index]
        updatedAgent.updatedAt = Date()
        
        project.agents[index] = updatedAgent
        appState.currentProject = project
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
        guard var project = appState.currentProject,
              let index = project.agents.firstIndex(where: { $0.id == agent.id }) else { return }
        
        project.agents[index].name = name
        project.agents[index].description = description
        project.agents[index].soulMD = soulMD
        project.agents[index].updatedAt = Date()
        
        appState.currentProject = project
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
        guard var project = appState.currentProject else { return }
        
        // Remove agent
        project.agents.removeAll { $0.id == agent.id }
        
        // Remove related permissions
        project.permissions.removeAll { $0.fromAgentID == agent.id || $0.toAgentID == agent.id }
        
        // Remove related workflow nodes
        for i in 0..<project.workflows.count {
            project.workflows[i].nodes.removeAll { $0.agentID == agent.id }
        }
        
        appState.currentProject = project
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
