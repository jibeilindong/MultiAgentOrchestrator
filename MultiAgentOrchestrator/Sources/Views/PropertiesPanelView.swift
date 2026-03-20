//
//  PropertiesPanelView.swift
//  MultiAgentOrchestrator
//
//  Created by 陈荣泽 on 2026/3/18.
//

import SwiftUI
import UniformTypeIdentifiers

struct PropertiesPanelView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // 标签页选择器
            Picker("", selection: $selectedTab) {
                Text(LocalizedString.node).tag(0)
                Text(LocalizedString.agent).tag(1)
                Text(LocalizedString.project).tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 8)
            
            Divider()
            
            // 内容区域 - 使用条件显示替代TabView
            Group {
                switch selectedTab {
                case 0:
                    NodePropertiesView()
                case 1:
                    AgentPropertiesView()
                case 2:
                    ProjectPropertiesView()
                default:
                    NodePropertiesView()
                }
            }
        }
    }
}

// 节点属性视图
struct NodePropertiesView: View {
    @EnvironmentObject var appState: AppState
    
    var selectedNode: WorkflowNode? {
        guard let nodeID = appState.selectedNodeID,
              let workflow = appState.currentProject?.workflows.first else { return nil }
        return workflow.nodes.first { $0.id == nodeID }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let node = selectedNode {
                    // 节点基础信息
                    SectionView(title: "Node Properties") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: nodeTypeIcon(node.type))
                                    .foregroundColor(nodeTypeColor(node.type))
                                Text(nodeTypeName(node.type))
                                    .font(.headline)
                            }
                            
                            if let agent = appState.getAgent(for: node) {
                                Divider()
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(LocalizedString.agent)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(agent.name)
                                        .font(.body)
                                }
                            }
                            
                            Divider()
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text(LocalizedString.position)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                HStack {
                                    Text("X: \(Int(node.position.x))")
                                        .font(.caption)
                                        .monospacedDigit()
                                    Text("Y: \(Int(node.position.y))")
                                        .font(.caption)
                                        .monospacedDigit()
                                }
                            }
                        }
                    }
                    
                    // 连接信息
                    if let workflow = appState.currentProject?.workflows.first {
                        let incomingEdges = workflow.edges.filter { $0.isIncoming(to: node.id) }
                        let outgoingEdges = workflow.edges.filter { $0.isOutgoing(from: node.id) }
                        
                        if !incomingEdges.isEmpty {
                            SectionView(title: "Incoming Connections") {
                                ForEach(incomingEdges) { edge in
                                    if let fromNode = workflow.nodes.first(where: { $0.id == edge.fromNodeID }) {
                                        HStack {
                                            Image(systemName: "arrow.right.circle.fill")
                                                .foregroundColor(.green)
                                            Text("From: \(nodeTypeName(fromNode.type))")
                                            Spacer()
                                        }
                                        .padding(.vertical, 4)
                                    }
                                }
                            }
                        }
                        
                        if !outgoingEdges.isEmpty {
                            SectionView(title: "Outgoing Connections") {
                                ForEach(outgoingEdges) { edge in
                                    if let toNode = workflow.nodes.first(where: { $0.id == edge.toNodeID }) {
                                        HStack {
                                            Image(systemName: "arrow.right.circle.fill")
                                                .foregroundColor(.blue)
                                            Text("To: \(nodeTypeName(toNode.type))")
                                            Spacer()
                                        }
                                        .padding(.vertical, 4)
                                    }
                                }
                            }
                        }
                    }
                } else {
                    // 无选中节点
                    VStack(spacing: 20) {
                        Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        
                        Text(LocalizedString.selectNode)
                            .font(.headline)
                        
                        Text(LocalizedString.selectNodeToEdit)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.vertical, 40)
                }
            }
            .padding()
        }
    }
    
    private func nodeTypeIcon(_ type: WorkflowNode.NodeType) -> String {
        switch type {
        case .start: return "play.circle.fill"
        case .agent: return "person.circle.fill"
        }
    }
    
    private func nodeTypeColor(_ type: WorkflowNode.NodeType) -> Color {
        switch type {
        case .start: return .orange
        case .agent: return .blue
        }
    }
    
    private func nodeTypeName(_ type: WorkflowNode.NodeType) -> String {
        switch type {
        case .start: return "Start Node"
        case .agent: return "Agent Node"
        }
    }
}

// Agent属性视图
struct AgentPropertiesView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedAgentID: UUID?
    @State private var agentName: String = ""
    @State private var agentIdentity: String = ""
    @State private var agentDescription: String = ""
    @State private var soulMD: String = ""
    @State private var capabilities: [String] = ["Basic"]
    @State private var colorHex: String = ""
    @State private var openClawAgentIdentifier: String = ""
    @State private var openClawModelIdentifier: String = "MiniMax-M2.5"
    @State private var openClawRuntimeProfile: String = "default"
    @State private var openClawMemoryBackupPath: String = ""

    private let agentColorPresets: [(title: String, hex: String, color: Color)] = [
        ("蓝", "2563EB", .blue),
        ("绿", "059669", .green),
        ("橙", "EA580C", .orange),
        ("红", "DC2626", .red),
        ("紫", "7C3AED", .purple),
        ("石墨", "334155", .gray)
    ]
    
    var selectedAgent: Agent? {
        if let id = selectedAgentID {
            return appState.currentProject?.agents.first { $0.id == id }
        }
        return nil
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SectionView(title: "Agent Selection") {
                    Picker("Select Agent", selection: $selectedAgentID) {
                        Text("None").tag(nil as UUID?)
                        if let agents = appState.currentProject?.agents {
                            ForEach(agents) { agent in
                                Text(agent.name).tag(agent.id as UUID?)
                            }
                        }
                    }
                    .onChange(of: selectedAgentID) { _, newAgentID in
                        if let agentID = newAgentID,
                           let agent = appState.currentProject?.agents.first(where: { $0.id == agentID }) {
                            agentName = agent.name
                            agentIdentity = agent.identity
                            agentDescription = agent.description
                            soulMD = agent.soulMD
                            capabilities = agent.capabilities
                            colorHex = agent.colorHex ?? ""
                            openClawAgentIdentifier = agent.openClawDefinition.agentIdentifier
                            openClawModelIdentifier = agent.openClawDefinition.modelIdentifier
                            openClawRuntimeProfile = agent.openClawDefinition.runtimeProfile
                            openClawMemoryBackupPath = agent.openClawDefinition.memoryBackupPath ?? ""
                        } else {
                            resetForm()
                        }
                    }
                }
                
                if let _ = selectedAgent {
                    SectionView(title: "Agent Configuration") {
                        VStack(alignment: .leading, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(LocalizedString.name)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                TextField("Agent Name", text: $agentName)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Identity")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                TextField("Agent Identity", text: $agentIdentity)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(LocalizedString.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                TextField("Agent Description", text: $agentDescription)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                            }

                            Divider()

                            VStack(alignment: .leading, spacing: 8) {
                                Text("OpenClaw Definition")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                TextField("OpenClaw Agent ID", text: $openClawAgentIdentifier)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                TextField("Model Identifier", text: $openClawModelIdentifier)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                TextField("Runtime Profile", text: $openClawRuntimeProfile)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                TextField("Memory Backup Path", text: $openClawMemoryBackupPath)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Agent Color")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                HStack(spacing: 8) {
                                    ForEach(agentColorPresets, id: \.hex) { preset in
                                        Button(action: { colorHex = preset.hex }) {
                                            Circle()
                                                .fill(preset.color)
                                                .frame(width: 18, height: 18)
                                                .overlay(
                                                    Circle()
                                                        .stroke(colorHex == preset.hex ? Color.primary : Color.clear, lineWidth: 2)
                                                )
                                        }
                                        .buttonStyle(.plain)
                                        .help(preset.title)
                                    }

                                    Button("清除") {
                                        colorHex = ""
                                    }
                                    .font(.caption)
                                    .buttonStyle(.borderless)
                                }

                                TextField("Hex Color", text: $colorHex)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                            }
                            
                            Divider()
                            
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Workspace SOUL Content")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Button("Load Template") {
                                        loadTemplate()
                                    }
                                    .font(.caption)
                                    .buttonStyle(.borderless)
                                }
                                
                                TextEditor(text: $soulMD)
                                    .font(.system(.body, design: .monospaced))
                                    .frame(height: 200)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                    )
                            }
                            
                            Divider()
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Skills")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                HStack {
                                    ForEach(["Basic", "Web Search", "File I/O", "API Call", "Data Analysis"], id: \.self) { capability in
                                        Button(capability) {
                                            toggleCapability(capability)
                                        }
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(
                                            capabilities.contains(capability) ?
                                                Color.blue.opacity(0.3) :
                                                Color.gray.opacity(0.1)
                                        )
                                        .cornerRadius(4)
                                    }
                                }
                            }
                            
                            Divider()
                            
                            HStack {
                                Button("Save Changes") {
                                    saveAgentChanges()
                                }
                                .disabled(!hasChanges)
                                
                                Spacer()
                                
                                Button("Delete Agent", role: .destructive) {
                                    deleteAgent()
                                }
                            }
                        }
                    }
                } else if appState.currentProject?.agents.isEmpty ?? true {
                    SectionView(title: "No Agents") {
                        VStack(spacing: 12) {
                            Text("No agents created yet.")
                                .foregroundColor(.secondary)
                            
                            Button("Create New Agent") {
                                createNewAgent()
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding()
        }
        .onAppear {
            // 默认选择第一个agent
            if selectedAgentID == nil, let firstAgent = appState.currentProject?.agents.first {
                selectedAgentID = firstAgent.id
                agentName = firstAgent.name
                agentIdentity = firstAgent.identity
                agentDescription = firstAgent.description
                soulMD = firstAgent.soulMD
                capabilities = firstAgent.capabilities
                colorHex = firstAgent.colorHex ?? ""
                openClawAgentIdentifier = firstAgent.openClawDefinition.agentIdentifier
                openClawModelIdentifier = firstAgent.openClawDefinition.modelIdentifier
                openClawRuntimeProfile = firstAgent.openClawDefinition.runtimeProfile
                openClawMemoryBackupPath = firstAgent.openClawDefinition.memoryBackupPath ?? ""
            }
        }
    }
    
    private var hasChanges: Bool {
        guard let agent = selectedAgent else { return false }
        return agent.name != agentName ||
               agent.identity != agentIdentity ||
               agent.description != agentDescription ||
               agent.soulMD != soulMD ||
               agent.capabilities != capabilities ||
               (agent.colorHex ?? "") != colorHex ||
               agent.openClawDefinition.agentIdentifier != openClawAgentIdentifier ||
               agent.openClawDefinition.modelIdentifier != openClawModelIdentifier ||
               agent.openClawDefinition.runtimeProfile != openClawRuntimeProfile ||
               (agent.openClawDefinition.memoryBackupPath ?? "") != openClawMemoryBackupPath
    }
    
    private func loadTemplate() {
        let template = """
        # Agent Configuration
        
        ## Role
        You are a helpful assistant.
        
        ## Capabilities
        - Answer questions
        - Process requests
        - Generate content
        
        ## Behavior Guidelines
        1. Be helpful and accurate
        2. Provide detailed responses
        3. Ask for clarification when needed
        """
        
        soulMD = template
    }
    
    private func toggleCapability(_ capability: String) {
        if capabilities.contains(capability) {
            capabilities.removeAll { $0 == capability }
        } else {
            capabilities.append(capability)
        }
    }
    
    private func saveAgentChanges() {
        guard let agent = selectedAgent else { return }
        
        var updatedAgent = agent
        updatedAgent.name = agentName
        updatedAgent.identity = agentIdentity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "generalist" : agentIdentity.trimmingCharacters(in: .whitespacesAndNewlines)
        updatedAgent.description = agentDescription
        updatedAgent.soulMD = soulMD
        updatedAgent.capabilities = capabilities
        updatedAgent.colorHex = colorHex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : colorHex.trimmingCharacters(in: .whitespacesAndNewlines)
        updatedAgent.openClawDefinition.agentIdentifier = openClawAgentIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? updatedAgent.name : openClawAgentIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        updatedAgent.openClawDefinition.modelIdentifier = openClawModelIdentifier
        updatedAgent.openClawDefinition.runtimeProfile = openClawRuntimeProfile
        updatedAgent.openClawDefinition.memoryBackupPath = openClawMemoryBackupPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : openClawMemoryBackupPath.trimmingCharacters(in: .whitespacesAndNewlines)
        updatedAgent.updatedAt = Date()
        
        appState.updateAgent(updatedAgent, reload: true)
    }
    
    private func deleteAgent() {
        guard let agent = selectedAgent,
              appState.currentProject?.agents.contains(where: { $0.id == agent.id }) == true else { return }

        appState.deleteAgent(agent.id)
        resetForm()
        selectedAgentID = nil
    }
    
    private func createNewAgent() {
        guard let newAgent = appState.addNewAgent() else { return }
        selectedAgentID = newAgent.id
        agentName = newAgent.name
        agentIdentity = newAgent.identity
        agentDescription = newAgent.description
        soulMD = newAgent.soulMD
        capabilities = newAgent.capabilities
        colorHex = newAgent.colorHex ?? ""
        openClawAgentIdentifier = newAgent.openClawDefinition.agentIdentifier
        openClawModelIdentifier = newAgent.openClawDefinition.modelIdentifier
        openClawRuntimeProfile = newAgent.openClawDefinition.runtimeProfile
        openClawMemoryBackupPath = newAgent.openClawDefinition.memoryBackupPath ?? ""
    }
    
    private func resetForm() {
        agentName = ""
        agentIdentity = ""
        agentDescription = ""
        soulMD = ""
        capabilities = ["Basic"]
        colorHex = ""
        openClawAgentIdentifier = ""
        openClawModelIdentifier = "MiniMax-M2.5"
        openClawRuntimeProfile = "default"
        openClawMemoryBackupPath = ""
    }
}


// 项目属性视图
struct ProjectPropertiesView: View {
    @EnvironmentObject var appState: AppState
    @State private var projectName: String = ""
    @State private var showExportPanel = false

    private var workspaceRootPath: String {
        appState.currentProject?.taskData.workspaceRootPath ?? appState.projectManager.defaultWorkspaceRootDirectory.path
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SectionView(title: "Project Info") {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Project Name")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("Project Name", text: $projectName)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .onAppear {
                                    projectName = appState.currentProject?.name ?? ""
                                }
                                .onChange(of: projectName) { _, newValue in
                                    appState.currentProject?.name = newValue
                                }
                        }
                        
                        if let project = appState.currentProject {
                            Divider()
                            
                            InfoRow(label: "Created", value: project.createdAt.formatted(date: .abbreviated, time: .shortened))
                            InfoRow(label: "Last Updated", value: project.updatedAt.formatted(date: .abbreviated, time: .shortened))
                            InfoRow(label: "Agents", value: "\(project.agents.count)")
                            InfoRow(label: "Workflows", value: "\(project.workflows.count)")
                            InfoRow(label: "OpenClaw", value: project.openClaw.config.deploymentSummary)
                        }
                    }
                }

                SectionView(title: "Task Data") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(workspaceRootPath)
                            .font(.caption)
                            .textSelection(.enabled)

                        HStack {
                            Button("Choose Folder") {
                                appState.chooseTaskDataRootDirectory()
                            }
                            Button("Reset Default") {
                                appState.resetTaskDataRootDirectory()
                            }
                        }
                    }
                }

                SectionView(title: "Memory Backup") {
                    VStack(alignment: .leading, spacing: 8) {
                        InfoRow(label: "Mode", value: appState.currentProject?.memoryData.backupOnly == true ? "Backup Only" : "Managed")
                        InfoRow(label: "Task Memories", value: "\(appState.currentProject?.memoryData.taskExecutionMemories.count ?? 0)")
                        InfoRow(label: "Agent Memories", value: "\(appState.currentProject?.memoryData.agentMemories.count ?? 0)")
                    }
                }
                
                SectionView(title: "Statistics") {
                    VStack(alignment: .leading, spacing: 8) {
                        InfoRow(label: "Total Nodes", value: "\(appState.currentProject?.workflows.first?.nodes.count ?? 0)")
                        InfoRow(label: "Total Connections", value: "\(appState.currentProject?.workflows.first?.edges.count ?? 0)")
                        InfoRow(label: "Total Boundaries", value: "\(appState.currentProject?.workflows.first?.boundaries.count ?? 0)")
                        InfoRow(label: "Project Size", value: "Compact")
                    }
                }
                
                SectionView(title: "Export") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Export your project for sharing or backup.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        HStack {
                            Button("Export as JSON") {
                                exportProjectAsJSON()
                            }
                            
                            Button("Export as Image") {
                                // 导出为图片功能
                            }
                            .disabled(true)
                        }
                    }
                }
            }
            .padding()
        }
    }
    
    private func exportProjectAsJSON() {
        guard let project = appState.currentProject else { return }
        
        let panel = NSSavePanel()
        panel.title = "Export Project"
        panel.nameFieldStringValue = "\(project.name).json"
        panel.allowedContentTypes = [.json]
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                do {
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = .prettyPrinted
                    let data = try encoder.encode(project)
                    try data.write(to: url)
                } catch {
                    print("导出失败: \(error)")
                }
            }
        }
    }
}

// Section视图

// 信息行
struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
    }
}
