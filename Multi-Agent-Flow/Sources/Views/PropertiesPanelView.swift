//
//  PropertiesPanelView.swift
//  Multi-Agent-Flow
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
    @State private var selectedTemplateID: String = AgentTemplateCatalog.defaultTemplateID

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

    private var selectedTemplate: AgentTemplate {
        AgentTemplateCatalog.template(withID: selectedTemplateID) ?? AgentTemplateCatalog.defaultTemplate
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
                            selectedTemplateID = matchingTemplateID(for: agent)
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
                                    TemplatePickerButton(
                                        selectedTemplateID: $selectedTemplateID,
                                        onSelect: { template in applyTemplate(template) },
                                        labelTitle: selectedTemplate.name
                                    )
                                    Button("Apply Template") {
                                        loadTemplate()
                                    }
                                    .font(.caption)
                                    .buttonStyle(.borderless)
                                }

                                TemplateSummaryCard(template: selectedTemplate)
                                
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
                            
                            HStack {
                                TemplatePickerButton(
                                    selectedTemplateID: $selectedTemplateID,
                                    onSelect: { _ in },
                                    labelTitle: selectedTemplate.name
                                )

                                Button("Create New Agent") {
                                    createNewAgent()
                                }
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
                selectedTemplateID = matchingTemplateID(for: firstAgent)
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
        applyTemplate(selectedTemplate)
    }

    private func applyTemplate(_ template: AgentTemplate) {
        if agentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            agentName = template.name
        }
        agentIdentity = template.identity
        agentDescription = template.summary
        soulMD = template.soulMD
        capabilities = template.capabilities
        colorHex = template.colorHex
        selectedTemplateID = template.id
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
        guard let newAgent = appState.addNewAgent(templateID: selectedTemplateID) else { return }
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

    private func matchingTemplateID(for agent: Agent) -> String {
        if let exactMatch = AgentTemplateCatalog.templates.first(where: {
            $0.identity == agent.identity &&
            $0.summary == agent.description &&
            $0.capabilities == agent.capabilities &&
            $0.colorHex == (agent.colorHex ?? "")
        }) {
            return exactMatch.id
        }

        if let identityMatch = AgentTemplateCatalog.templates.first(where: { $0.identity == agent.identity }) {
            return identityMatch.id
        }

        return AgentTemplateCatalog.defaultTemplateID
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
        selectedTemplateID = AgentTemplateCatalog.defaultTemplateID
    }
}

struct TemplatePickerButton: View {
    enum Variant {
        case plain
        case toolbar
    }

    @Binding var selectedTemplateID: String
    let onSelect: (AgentTemplate) -> Void
    let labelTitle: String
    let labelSystemImage: String
    let blankActionTitle: String?
    let onCreateBlank: (() -> Void)?
    let existingAgents: [Agent]
    let onSelectExistingAgent: ((Agent) -> Void)?
    let variant: Variant

    @State private var isPresented = false

    init(
        selectedTemplateID: Binding<String>,
        onSelect: @escaping (AgentTemplate) -> Void,
        labelTitle: String,
        labelSystemImage: String = "square.grid.2x2",
        blankActionTitle: String? = nil,
        onCreateBlank: (() -> Void)? = nil,
        existingAgents: [Agent] = [],
        onSelectExistingAgent: ((Agent) -> Void)? = nil,
        variant: Variant = .plain
    ) {
        self._selectedTemplateID = selectedTemplateID
        self.onSelect = onSelect
        self.labelTitle = labelTitle
        self.labelSystemImage = labelSystemImage
        self.blankActionTitle = blankActionTitle
        self.onCreateBlank = onCreateBlank
        self.existingAgents = existingAgents
        self.onSelectExistingAgent = onSelectExistingAgent
        self.variant = variant
    }

    var body: some View {
        Button {
            isPresented = true
        } label: {
            switch variant {
            case .plain:
                Label(labelTitle, systemImage: labelSystemImage)
            case .toolbar:
                HStack(spacing: 8) {
                    Image(systemName: labelSystemImage)
                        .font(.system(size: 13, weight: .semibold))
                    Text(labelTitle)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                }
                .foregroundColor(Color.primary.opacity(0.82))
                .padding(.horizontal, 12)
                .frame(height: 38)
                .frame(minWidth: 104, alignment: .center)
                .fixedSize(horizontal: true, vertical: false)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.black.opacity(0.045))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.black.opacity(0.06), lineWidth: 1)
                )
            }
        }
        .font(.caption)
        .buttonStyle(.plain)
        .layoutPriority(1)
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            TemplatePickerPopover(
                selectedTemplateID: $selectedTemplateID,
                isPresented: $isPresented,
                blankActionTitle: blankActionTitle,
                onCreateBlank: onCreateBlank,
                existingAgents: existingAgents,
                onSelectExistingAgent: onSelectExistingAgent,
                onSelect: onSelect
            )
            .frame(width: 460, height: 500)
        }
    }
}

struct TemplatePickerPopover: View {
    @Binding var selectedTemplateID: String
    @Binding var isPresented: Bool
    let blankActionTitle: String?
    let onCreateBlank: (() -> Void)?
    let existingAgents: [Agent]
    let onSelectExistingAgent: ((Agent) -> Void)?
    let onSelect: (AgentTemplate) -> Void

    @State private var searchText: String = ""

    private var filteredCategories: [(category: AgentTemplateCategory, templates: [AgentTemplate])] {
        AgentTemplateCatalog.categories.compactMap { category in
            let templates = AgentTemplateCatalog.templates(in: category).filter {
                searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.summary.localizedCaseInsensitiveContains(searchText)
                || $0.identity.localizedCaseInsensitiveContains(searchText)
            }
            guard !templates.isEmpty else { return nil }
            return (category, templates)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("选择模板")
                    .font(.headline)
                Spacer()
                Button("关闭") { isPresented = false }
                    .buttonStyle(.borderless)
            }

            TextField("搜索模板", text: $searchText)
                .textFieldStyle(.roundedBorder)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if let blankActionTitle, let onCreateBlank {
                        Button {
                            isPresented = false
                            onCreateBlank()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(.accentColor)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(blankActionTitle)
                                        .font(.body)
                                    Text("创建不套用模板的空白 agent")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.accentColor.opacity(0.08))
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }

                    ForEach(filteredCategories, id: \.category) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group.category.rawValue)
                                .font(.caption)
                                .foregroundColor(.secondary)

                            ForEach(group.templates) { template in
                                Button {
                                    selectedTemplateID = template.id
                                    onSelect(template)
                                    isPresented = false
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(template.name)
                                                .font(.body)
                                            Spacer()
                                            if template.id == selectedTemplateID {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundColor(.accentColor)
                                            }
                                        }
                                        Text(template.summary)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(2)
                                        Text("适用场景：\(template.applicableScenarios.joined(separator: " · "))")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                            .lineLimit(2)
                                    }
                                    .padding(10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(template.id == selectedTemplateID ? Color.accentColor.opacity(0.12) : Color.clear)
                                    .cornerRadius(8)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if !existingAgents.isEmpty, let onSelectExistingAgent {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("现有 Agent")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            ForEach(existingAgents) { agent in
                                Button {
                                    isPresented = false
                                    onSelectExistingAgent(agent)
                                } label: {
                                    HStack(spacing: 10) {
                                        Circle()
                                            .fill(Color(hex: agent.colorHex ?? "") ?? .accentColor)
                                            .frame(width: 10, height: 10)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(agent.name)
                                                .font(.body)
                                            Text(agent.description.isEmpty ? agent.identity : agent.description)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .lineLimit(2)
                                        }
                                        Spacer()
                                    }
                                    .padding(10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.primary.opacity(0.04))
                                    .cornerRadius(8)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
        .padding()
    }
}

struct TemplateSummaryCard: View {
    let template: AgentTemplate

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("当前模板名称/说明")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(Color(hex: template.colorHex) ?? .accentColor)
                    .frame(width: 10, height: 10)
                    .padding(.top, 4)

                VStack(alignment: .leading, spacing: 2) {
                    Text(template.name)
                        .font(.subheadline.weight(.semibold))
                    Text(template.summary)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("适用场景：\(template.applicableScenarios.joined(separator: " · "))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(10)
            .background(Color.primary.opacity(0.04))
            .cornerRadius(8)
        }
    }
}

private extension Color {
    init?(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count == 6 else { return nil }
        var value: UInt64 = 0
        guard Scanner(string: cleaned).scanHexInt64(&value) else { return nil }
        let r = Double((value >> 16) & 0xff) / 255
        let g = Double((value >> 8) & 0xff) / 255
        let b = Double(value & 0xff) / 255
        self = Color(red: r, green: g, blue: b)
    }
}


// 项目属性视图
struct ProjectPropertiesView: View {
    @EnvironmentObject var appState: AppState
    @State private var projectName: String = ""
    @State private var showExportPanel = false
    @State private var selectedWorkflowID: UUID?
    @State private var showLaunchVerificationConfirmation = false
    @State private var isRunningLaunchVerification = false

    private var workspaceRootPath: String {
        appState.currentProject?.taskData.workspaceRootPath ?? appState.projectManager.defaultWorkspaceRootDirectory.path
    }

    private var workflows: [Workflow] {
        appState.currentProject?.workflows ?? []
    }

    private var selectedWorkflow: Workflow? {
        let resolvedID = selectedWorkflowID ?? workflows.first?.id
        return workflows.first { $0.id == resolvedID }
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

                SectionView(title: "Workflow Routing") {
                    VStack(alignment: .leading, spacing: 12) {
                        if workflows.isEmpty {
                            Text("当前项目还没有工作流。")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Workflow")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Picker("Workflow", selection: workflowSelectionBinding) {
                                    ForEach(workflows) { workflow in
                                        Text(workflow.name).tag(workflow.id as UUID?)
                                    }
                                }
                                .pickerStyle(.menu)
                            }

                            if let workflow = selectedWorkflow {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Fallback Routing Policy")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Picker(
                                        "Fallback Routing Policy",
                                        selection: Binding(
                                            get: { workflow.fallbackRoutingPolicy },
                                            set: { newPolicy in
                                                var updatedWorkflow = workflow
                                                updatedWorkflow.fallbackRoutingPolicy = newPolicy
                                                appState.updateWorkflow(updatedWorkflow)
                                            }
                                        )
                                    ) {
                                        ForEach(WorkflowFallbackRoutingPolicy.allCases, id: \.self) { policy in
                                            Text(policy.displayName).tag(policy)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                }

                                Text(workflow.fallbackRoutingPolicy.detail)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color(.controlBackgroundColor))
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                        }
                    }
                }

                SectionView(title: "Launch Verification") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Manual Check")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("启动验证只会在你手动确认后运行，不会在工作流启动时自动触发。")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Button(isRunningLaunchVerification ? "Running..." : "Run Launch Verification") {
                                showLaunchVerificationConfirmation = true
                            }
                            .disabled(selectedWorkflow == nil || isRunningLaunchVerification || appState.openClawService.isExecuting)
                        }

                        if isRunningLaunchVerification {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("正在执行启动验证，请稍候。")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        if let report = selectedWorkflow?.lastLaunchVerificationReport {
                            HStack {
                                Text("Last Result")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(report.status.displayName)
                                    .font(.caption2)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(verificationColor(report.status).opacity(0.14))
                                    .foregroundColor(verificationColor(report.status))
                                    .clipShape(Capsule())
                            }

                            InfoRow(label: "Started", value: report.startedAt.formatted(date: .abbreviated, time: .shortened))
                            InfoRow(label: "Completed", value: report.completedAt?.formatted(date: .abbreviated, time: .shortened) ?? "Running")
                            InfoRow(label: "Cases", value: "\(report.testCaseReports.count)")

                            if !report.staticFindings.isEmpty {
                                verificationList(title: "Static Findings", items: report.staticFindings, color: .orange)
                            }

                            if !report.runtimeFindings.isEmpty {
                                verificationList(title: "Runtime Findings", items: Array(report.runtimeFindings.prefix(5)), color: .blue)
                            }

                            if !report.testCaseReports.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Case Results")
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                    ForEach(report.testCaseReports) { caseReport in
                                        VStack(alignment: .leading, spacing: 6) {
                                            HStack {
                                                Text(caseReport.name)
                                                    .font(.caption)
                                                    .fontWeight(.semibold)
                                                Spacer()
                                                Text(caseReport.status.displayName)
                                                    .font(.caption2)
                                                    .padding(.horizontal, 8)
                                                    .padding(.vertical, 3)
                                                    .background(verificationColor(caseReport.status).opacity(0.14))
                                                    .foregroundColor(verificationColor(caseReport.status))
                                                    .clipShape(Capsule())
                                            }
                                            Text("Steps: \(caseReport.actualStepCount) | Agents: \(caseReport.actualAgents.joined(separator: ", "))")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                            if !caseReport.notes.isEmpty {
                                                Text(caseReport.notes.joined(separator: " | "))
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                        .padding(10)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color(.controlBackgroundColor))
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    }
                                }
                            }
                        } else {
                            Text("还没有启动验证报告。请点击上方按钮并确认后启动首次验证。")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .confirmationDialog(
                        "Run launch verification for the selected workflow?",
                        isPresented: $showLaunchVerificationConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button("Start Verification") {
                            guard let workflow = selectedWorkflow else { return }
                            isRunningLaunchVerification = true
                            let started = appState.runWorkflowLaunchVerification(workflowID: workflow.id) { _ in
                                DispatchQueue.main.async {
                                    isRunningLaunchVerification = false
                                }
                            }
                            if !started {
                                isRunningLaunchVerification = false
                            }
                        }
                        Button("Cancel", role: .cancel) { }
                    } message: {
                        Text("This will execute the workflow's launch verification cases and refresh the report in this panel.")
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
        .onAppear {
            projectName = appState.currentProject?.name ?? ""
            if selectedWorkflowID == nil {
                selectedWorkflowID = workflows.first?.id
            }
        }
        .onChange(of: appState.currentProject?.id) { _, _ in
            projectName = appState.currentProject?.name ?? ""
            selectedWorkflowID = workflows.first?.id
        }
        .onChange(of: workflows.map(\.id)) { _, workflowIDs in
            guard !workflowIDs.isEmpty else {
                selectedWorkflowID = nil
                return
            }
            if let selectedWorkflowID, workflowIDs.contains(selectedWorkflowID) {
                return
            }
            selectedWorkflowID = workflowIDs.first
        }
    }

    private var workflowSelectionBinding: Binding<UUID?> {
        Binding(
            get: { selectedWorkflowID ?? workflows.first?.id },
            set: { selectedWorkflowID = $0 }
        )
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

    private func verificationColor(_ status: WorkflowVerificationStatus) -> Color {
        switch status {
        case .pass: return .green
        case .warn: return .orange
        case .fail: return .red
        }
    }

    @ViewBuilder
    private func verificationList(title: String, items: [String], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(color.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
