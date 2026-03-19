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
                        let incomingEdges = workflow.edges.filter { $0.toNodeID == node.id }
                        let outgoingEdges = workflow.edges.filter { $0.fromNodeID == node.id }
                        
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
        case .agent: return "person.circle.fill"
        case .branch: return "arrow.triangle.branch"
        case .start: return "play.circle.fill"
        case .end: return "stop.circle.fill"
        case .subflow: return "square.stack.3d.up"
        }
    }
    
    private func nodeTypeColor(_ type: WorkflowNode.NodeType) -> Color {
        switch type {
        case .agent: return .blue
        case .branch: return .orange
        case .start: return .green
        case .end: return .red
        case .subflow: return .purple
        }
    }
    
    private func nodeTypeName(_ type: WorkflowNode.NodeType) -> String {
        switch type {
        case .agent: return "Agent Node"
        case .branch: return "Branch Node"
        case .start: return "Start Node"
        case .end: return "End Node"
        case .subflow: return "Subflow Node"
        }
    }
}

// Agent属性视图
struct AgentPropertiesView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedAgentID: UUID?
    @State private var agentName: String = ""
    @State private var agentDescription: String = ""
    @State private var soulMD: String = ""
    @State private var capabilities: [String] = ["Basic"]
    
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
                    .onChange(of: selectedAgentID) { newAgentID in
                        if let agentID = newAgentID,
                           let agent = appState.currentProject?.agents.first(where: { $0.id == agentID }) {
                            agentName = agent.name
                            agentDescription = agent.description
                            soulMD = agent.soulMD
                            capabilities = agent.capabilities
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
                                Text(LocalizedString.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                TextField("Agent Description", text: $agentDescription)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                            }
                            
                            Divider()
                            
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Soul.md Configuration")
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
                                Text("Capabilities")
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
                agentDescription = firstAgent.description
                soulMD = firstAgent.soulMD
                capabilities = firstAgent.capabilities
            }
        }
    }
    
    private var hasChanges: Bool {
        guard let agent = selectedAgent else { return false }
        return agent.name != agentName ||
               agent.description != agentDescription ||
               agent.soulMD != soulMD ||
               agent.capabilities != capabilities
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
        guard let agent = selectedAgent,
              let index = appState.currentProject?.agents.firstIndex(where: { $0.id == agent.id }) else { return }
        
        var updatedAgent = agent
        updatedAgent.name = agentName
        updatedAgent.description = agentDescription
        updatedAgent.soulMD = soulMD
        updatedAgent.capabilities = capabilities
        updatedAgent.updatedAt = Date()
        
        appState.currentProject?.agents[index] = updatedAgent
    }
    
    private func deleteAgent() {
        guard let agent = selectedAgent,
              let index = appState.currentProject?.agents.firstIndex(where: { $0.id == agent.id }) else { return }
        
        appState.currentProject?.agents.remove(at: index)
        resetForm()
        selectedAgentID = nil
    }
    
    private func createNewAgent() {
        let newAgent = Agent(name: "New Agent")
        appState.currentProject?.agents.append(newAgent)
        selectedAgentID = newAgent.id
        agentName = newAgent.name
        agentDescription = newAgent.description
        soulMD = newAgent.soulMD
        capabilities = newAgent.capabilities
    }
    
    private func resetForm() {
        agentName = ""
        agentDescription = ""
        soulMD = ""
        capabilities = ["Basic"]
    }
}


// 项目属性视图
struct ProjectPropertiesView: View {
    @EnvironmentObject var appState: AppState
    @State private var projectName: String = ""
    @State private var showExportPanel = false
    
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
                                .onChange(of: projectName) { newValue in
                                    appState.currentProject?.name = newValue
                                }
                        }
                        
                        if let project = appState.currentProject {
                            Divider()
                            
                            InfoRow(label: "Created", value: project.createdAt.formatted(date: .abbreviated, time: .shortened))
                            InfoRow(label: "Last Updated", value: project.updatedAt.formatted(date: .abbreviated, time: .shortened))
                            InfoRow(label: "Agents", value: "\(project.agents.count)")
                            InfoRow(label: "Workflows", value: "\(project.workflows.count)")
                        }
                    }
                }
                
                SectionView(title: "Statistics") {
                    VStack(alignment: .leading, spacing: 8) {
                        InfoRow(label: "Total Nodes", value: "\(appState.currentProject?.workflows.first?.nodes.count ?? 0)")
                        InfoRow(label: "Total Connections", value: "\(appState.currentProject?.workflows.first?.edges.count ?? 0)")
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
