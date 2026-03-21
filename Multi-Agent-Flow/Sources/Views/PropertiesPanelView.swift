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
                    SectionView(title: LocalizedString.text("node_properties_title")) {
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
                                    Text(LocalizedString.format("x_position", Int(node.position.x)))
                                        .font(.caption)
                                        .monospacedDigit()
                                    Text(LocalizedString.format("y_position", Int(node.position.y)))
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
                            SectionView(title: LocalizedString.text("incoming_connections")) {
                                ForEach(incomingEdges) { edge in
                                    if let fromNode = workflow.nodes.first(where: { $0.id == edge.fromNodeID }) {
                                        HStack {
                                            Image(systemName: "arrow.right.circle.fill")
                                                .foregroundColor(.green)
                                            Text(LocalizedString.format("from_node", nodeTypeName(fromNode.type)))
                                            Spacer()
                                        }
                                        .padding(.vertical, 4)
                                    }
                                }
                            }
                        }
                        
                        if !outgoingEdges.isEmpty {
                            SectionView(title: LocalizedString.text("outgoing_connections")) {
                                ForEach(outgoingEdges) { edge in
                                    if let toNode = workflow.nodes.first(where: { $0.id == edge.toNodeID }) {
                                        HStack {
                                            Image(systemName: "arrow.right.circle.fill")
                                                .foregroundColor(.blue)
                                            Text(LocalizedString.format("to_node", nodeTypeName(toNode.type)))
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
        case .start: return LocalizedString.text("start_node_title")
        case .agent: return LocalizedString.agentNode
        }
    }
}

// Agent属性视图
struct AgentPropertiesView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var templateLibrary = AgentTemplateLibraryStore.shared
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
    @State private var showingTemplateManager = false

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
                SectionView(title: LocalizedString.text("agent_selection")) {
                    Picker(LocalizedString.text("select_agent_label"), selection: $selectedAgentID) {
                        Text(LocalizedString.text("none_option")).tag(nil as UUID?)
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
                    SectionView(title: LocalizedString.text("agent_configuration_title")) {
                        VStack(alignment: .leading, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(LocalizedString.name)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                TextField(LocalizedString.agentName, text: $agentName)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(LocalizedString.text("identity"))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                TextField(LocalizedString.text("agent_identity"), text: $agentIdentity)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(LocalizedString.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                TextField(LocalizedString.text("agent_description_label"), text: $agentDescription)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                            }

                            Divider()

                            VStack(alignment: .leading, spacing: 8) {
                                Text(LocalizedString.text("openclaw_definition"))
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                TextField(LocalizedString.text("openclaw_agent_id"), text: $openClawAgentIdentifier)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                TextField(LocalizedString.text("model_identifier"), text: $openClawModelIdentifier)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                TextField(LocalizedString.text("runtime_profile"), text: $openClawRuntimeProfile)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                TextField(LocalizedString.text("memory_backup_path"), text: $openClawMemoryBackupPath)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text(LocalizedString.text("agent_color"))
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

                                    Button(LocalizedString.text("clear_action")) {
                                        colorHex = ""
                                    }
                                    .font(.caption)
                                    .buttonStyle(.borderless)
                                }

                                TextField(LocalizedString.text("hex_color"), text: $colorHex)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                            }
                            
                            Divider()
                            
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(LocalizedString.text("workspace_soul_content"))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    TemplatePickerButton(
                                        selectedTemplateID: $selectedTemplateID,
                                        onSelect: { template in applyTemplate(template) },
                                        labelTitle: selectedTemplate.name
                                    )
                                    Button("模板库") {
                                        showingTemplateManager = true
                                    }
                                    .font(.caption)
                                    .buttonStyle(.borderless)
                                    Button(LocalizedString.text("apply_template")) {
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
                                Text(LocalizedString.manageSkills)
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
                                Button(LocalizedString.text("save_changes")) {
                                    saveAgentChanges()
                                }
                                .disabled(!hasChanges)
                                
                                Spacer()
                                
                                Button(LocalizedString.deleteAgent, role: .destructive) {
                                    deleteAgent()
                                }
                            }
                        }
                    }
                } else if appState.currentProject?.agents.isEmpty ?? true {
                    SectionView(title: LocalizedString.noAgents) {
                        VStack(spacing: 12) {
                            Text(LocalizedString.text("no_agents_created_yet"))
                                .foregroundColor(.secondary)
                            
                            HStack {
                                TemplatePickerButton(
                                    selectedTemplateID: $selectedTemplateID,
                                    onSelect: { _ in },
                                    labelTitle: selectedTemplate.name
                                )

                                Button(LocalizedString.text("create_new_agent")) {
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
        .sheet(isPresented: $showingTemplateManager) {
            TemplateLibraryManagerSheet(selectedTemplateID: $selectedTemplateID)
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
        templateLibrary.markUsed(selectedTemplate.id)
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
        templateLibrary.markUsed(selectedTemplateID)
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
    @ObservedObject private var templateLibrary = AgentTemplateLibraryStore.shared
    @Binding var selectedTemplateID: String
    @Binding var isPresented: Bool
    let blankActionTitle: String?
    let onCreateBlank: (() -> Void)?
    let existingAgents: [Agent]
    let onSelectExistingAgent: ((Agent) -> Void)?
    let onSelect: (AgentTemplate) -> Void

    @State private var searchText: String = ""

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var favoriteTemplates: [AgentTemplate] {
        templateLibrary.favoriteTemplates.filter(matchesSearch)
    }

    private var recentTemplates: [AgentTemplate] {
        templateLibrary.recentTemplates
            .filter(matchesSearch)
            .filter { !templateLibrary.isFavorite($0.id) }
    }

    private var filteredFamilies: [(family: AgentTemplateFamily, groups: [(category: AgentTemplateCategory, templates: [AgentTemplate])])] {
        AgentTemplateCatalog.families.compactMap { family in
            let groups: [(category: AgentTemplateCategory, templates: [AgentTemplate])] =
                AgentTemplateCatalog.categories(in: family).compactMap { category -> (category: AgentTemplateCategory, templates: [AgentTemplate])? in
                let templates = AgentTemplateCatalog.templates(in: category).filter(matchesSearch)
                guard !templates.isEmpty else { return nil }
                return (category, templates)
            }

            guard !groups.isEmpty else { return nil }
            return (family, groups)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(LocalizedString.text("select_template"))
                    .font(.headline)
                Spacer()
                Button(LocalizedString.close) { isPresented = false }
                    .buttonStyle(.borderless)
            }

            TextField(LocalizedString.text("search_template"), text: $searchText)
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
                                    Text(LocalizedString.text("create_blank_agent_no_template"))
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

                    if !favoriteTemplates.isEmpty {
                        templateQuickSection(
                            title: "收藏模板",
                            templates: favoriteTemplates
                        )
                    }

                    if !recentTemplates.isEmpty {
                        templateQuickSection(
                            title: "最近使用",
                            templates: recentTemplates
                        )
                    }

                    ForEach(filteredFamilies, id: \.family) { familyGroup in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(familyGroup.family.rawValue)
                                .font(.subheadline.weight(.semibold))

                            ForEach(familyGroup.groups, id: \.category) { group in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(group.category.rawValue)
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                    ForEach(group.templates) { template in
                                        templateSelectionButton(template)
                                    }
                                }
                                .font(.caption)
                            }
                        }
                    }

                    if !existingAgents.isEmpty, let onSelectExistingAgent {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(LocalizedString.text("existing_agent_header"))
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

    private func matchesSearch(_ template: AgentTemplate) -> Bool {
        trimmedSearchText.isEmpty
        || template.name.localizedCaseInsensitiveContains(trimmedSearchText)
        || template.summary.localizedCaseInsensitiveContains(trimmedSearchText)
        || template.identity.localizedCaseInsensitiveContains(trimmedSearchText)
        || template.taxonomyPath.localizedCaseInsensitiveContains(trimmedSearchText)
        || template.tags.joined(separator: " ").localizedCaseInsensitiveContains(trimmedSearchText)
    }

    @ViewBuilder
    private func templateQuickSection(title: String, templates: [AgentTemplate]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)

            ForEach(templates) { template in
                templateSelectionButton(template)
            }
        }
    }

    @ViewBuilder
    private func templateSelectionButton(_ template: AgentTemplate) -> some View {
        Button {
            templateLibrary.markUsed(template.id)
            selectedTemplateID = template.id
            onSelect(template)
            isPresented = false
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(template.name)
                        .font(.body)
                    if templateLibrary.isFavorite(template.id) {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundColor(.yellow)
                    }
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
                Text(template.taxonomyPath)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(LocalizedString.format("applicable_scenarios", template.applicableScenarios.joined(separator: " · ")))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                if !template.tags.isEmpty {
                    Text("标签：\(template.tags.joined(separator: " · "))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(template.id == selectedTemplateID ? Color.accentColor.opacity(0.12) : Color.clear)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

struct TemplateSummaryCard: View {
    let template: AgentTemplate

    private var validationText: String {
        let issues = template.validationIssues
        if issues.isEmpty {
            return "已通过规范校验"
        }

        let errorCount = issues.filter { $0.severity == .error }.count
        let warningCount = issues.filter { $0.severity == .warning }.count

        if errorCount > 0 {
            return "存在 \(errorCount) 个错误，\(warningCount) 个提醒"
        }

        return "存在 \(warningCount) 个提醒"
    }

    private var validationColor: Color {
        let issues = template.validationIssues
        if issues.contains(where: { $0.severity == .error }) {
            return .red
        }
        if issues.contains(where: { $0.severity == .warning }) {
            return .orange
        }
        return .green
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("模板管理信息")
                .font(.caption)
                .foregroundColor(.secondary)

            Text("以下信息仅用于模板选择与管理，不会写入 SOUL.md。")
                .font(.caption2)
                .foregroundColor(.secondary)

            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(Color(hex: template.colorHex) ?? .accentColor)
                    .frame(width: 10, height: 10)
                    .padding(.top, 4)

                VStack(alignment: .leading, spacing: 2) {
                    Text(template.name)
                        .font(.subheadline.weight(.semibold))
                    Text(template.taxonomyPath)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(template.summary)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("能力标签：\(template.capabilities.joined(separator: " · "))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(LocalizedString.format("applicable_scenarios", template.applicableScenarios.joined(separator: " · ")))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(validationText)
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(validationColor)
                }
            }
            .padding(10)
            .background(Color.primary.opacity(0.04))
            .cornerRadius(8)
        }
    }
}

private enum TemplateManagerMode: String, CaseIterable, Identifiable {
    case editor = "编辑模板"
    case validation = "校验扫描"

    var id: String { rawValue }
}

private enum TemplateLibrarySourceFilter: String, CaseIterable, Identifiable {
    case all = "全部来源"
    case builtIn = "仅内置"
    case custom = "仅自定义"
    case invalid = "仅异常"

    var id: String { rawValue }
}

private enum TemplateValidationSeverityFilter: String, CaseIterable, Identifiable {
    case all = "全部问题"
    case errorsOnly = "仅错误"
    case warningsOnly = "仅提醒"

    var id: String { rawValue }
}

private struct TemplateEditorDraft {
    var id: String
    var category: AgentTemplateCategory
    var name: String
    var summary: String
    var applicableScenariosText: String
    var identity: String
    var capabilitiesText: String
    var tagsText: String
    var colorHex: String
    var role: String
    var mission: String
    var coreCapabilitiesText: String
    var responsibilitiesText: String
    var workflowText: String
    var inputsText: String
    var outputsText: String
    var collaborationText: String
    var guardrailsText: String
    var successCriteriaText: String

    init(template: AgentTemplate) {
        id = template.id
        category = template.category
        name = template.name
        summary = template.summary
        applicableScenariosText = template.applicableScenarios.joined(separator: "\n")
        identity = template.identity
        capabilitiesText = template.capabilities.joined(separator: "\n")
        tagsText = template.tags.joined(separator: "\n")
        colorHex = template.colorHex
        role = template.soulSpec.role
        mission = template.soulSpec.mission
        coreCapabilitiesText = template.soulSpec.coreCapabilities.joined(separator: "\n")
        responsibilitiesText = template.soulSpec.responsibilities.joined(separator: "\n")
        workflowText = template.soulSpec.workflow.joined(separator: "\n")
        inputsText = template.soulSpec.inputs.joined(separator: "\n")
        outputsText = template.soulSpec.outputs.joined(separator: "\n")
        collaborationText = template.soulSpec.collaboration.joined(separator: "\n")
        guardrailsText = template.soulSpec.guardrails.joined(separator: "\n")
        successCriteriaText = template.soulSpec.successCriteria.joined(separator: "\n")
    }

    func applying(to template: AgentTemplate) -> AgentTemplate {
        var updated = template
        updated.meta.category = category
        updated.meta.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.meta.summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.meta.applicableScenarios = splitLines(applicableScenariosText)
        updated.meta.identity = identity.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.meta.capabilities = splitLines(capabilitiesText)
        updated.meta.tags = splitLines(tagsText)
        updated.meta.colorHex = colorHex.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.soulSpec.role = role.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.soulSpec.mission = mission.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.soulSpec.coreCapabilities = splitLines(coreCapabilitiesText)
        updated.soulSpec.responsibilities = splitLines(responsibilitiesText)
        updated.soulSpec.workflow = splitLines(workflowText)
        updated.soulSpec.inputs = splitLines(inputsText)
        updated.soulSpec.outputs = splitLines(outputsText)
        updated.soulSpec.collaboration = splitLines(collaborationText)
        updated.soulSpec.guardrails = splitLines(guardrailsText)
        updated.soulSpec.successCriteria = splitLines(successCriteriaText)
        return updated.sanitizedForPersistence()
    }

    private func splitLines(_ text: String) -> [String] {
        text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

struct TemplateLibraryManagerSheet: View {
    @ObservedObject private var templateLibrary = AgentTemplateLibraryStore.shared
    @Binding var selectedTemplateID: String

    @Environment(\.dismiss) private var dismiss

    @State private var mode: TemplateManagerMode = .editor
    @State private var selectedTemplateManagerID: String?
    @State private var draft: TemplateEditorDraft?
    @State private var feedbackMessage: String?
    @State private var searchText: String = ""
    @State private var sourceFilter: TemplateLibrarySourceFilter = .all
    @State private var familyFilter: AgentTemplateFamily?
    @State private var tagFilter: String?

    init(selectedTemplateID: Binding<String>) {
        self._selectedTemplateID = selectedTemplateID
    }

    private var selectedTemplate: AgentTemplate? {
        guard let selectedTemplateManagerID else { return nil }
        return templateLibrary.template(withID: selectedTemplateManagerID)
    }

    private var markdownContentType: UTType {
        UTType(filenameExtension: "md") ?? .plainText
    }

    private var sortedTemplates: [AgentTemplate] {
        templateLibrary.templates.sorted { lhs, rhs in
            if lhs.meta.sortOrder == rhs.meta.sortOrder {
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            return lhs.meta.sortOrder < rhs.meta.sortOrder
        }
    }

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredTemplates: [AgentTemplate] {
        sortedTemplates.filter { template in
            let matchesSearch = trimmedSearchText.isEmpty
                || template.name.localizedCaseInsensitiveContains(trimmedSearchText)
                || template.summary.localizedCaseInsensitiveContains(trimmedSearchText)
                || template.identity.localizedCaseInsensitiveContains(trimmedSearchText)
                || template.taxonomyPath.localizedCaseInsensitiveContains(trimmedSearchText)
                || template.capabilities.joined(separator: " ").localizedCaseInsensitiveContains(trimmedSearchText)
                || template.tags.joined(separator: " ").localizedCaseInsensitiveContains(trimmedSearchText)

            let matchesSource: Bool
            switch sourceFilter {
            case .all:
                matchesSource = true
            case .builtIn:
                matchesSource = templateLibrary.isBuiltInTemplate(template.id)
            case .custom:
                matchesSource = !templateLibrary.isBuiltInTemplate(template.id)
            case .invalid:
                matchesSource = !template.validationIssues.isEmpty
            }

            let matchesFamily = familyFilter == nil || template.family == familyFilter
            let matchesTag = tagFilter == nil || template.tags.contains(tagFilter ?? "")
            return matchesSearch && matchesSource && matchesFamily && matchesTag
        }
    }

    private var availableTags: [String] {
        Array(Set(sortedTemplates.flatMap(\.tags))).sorted()
    }

    private var selectedTemplateSortIndex: Int? {
        guard let selectedTemplateManagerID else { return nil }
        return sortedTemplates.firstIndex(where: { $0.id == selectedTemplateManagerID })
    }

    private var groupedTemplates: [(family: AgentTemplateFamily, groups: [(category: AgentTemplateCategory, templates: [AgentTemplate])])] {
        AgentTemplateCatalog.families.compactMap { family in
            guard familyFilter == nil || familyFilter == family else { return nil }

            let groups: [(category: AgentTemplateCategory, templates: [AgentTemplate])] =
                AgentTemplateCatalog.categories(in: family).compactMap { category in
                    let templates = filteredTemplates.filter { $0.category == category }
                    guard !templates.isEmpty else { return nil }
                    return (category, templates)
                }

            guard !groups.isEmpty else { return nil }
            return (family, groups)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("模板库管理")
                    .font(.headline)
                Spacer()
                Menu("导出 JSON") {
                    Button("导出筛选结果") {
                        exportFilteredTemplates()
                    }
                    .disabled(filteredTemplates.isEmpty || filteredTemplates.count == sortedTemplates.count)

                    Button("导出全部") {
                        exportAllTemplates()
                    }
                    .disabled(sortedTemplates.isEmpty)
                }
                .menuStyle(.borderlessButton)

                Menu("导出 SOUL") {
                    Button("导出当前模板") {
                        guard let selectedTemplate else { return }
                        exportSoulDocument(for: selectedTemplate)
                    }
                    .disabled(selectedTemplate == nil)

                    Button("导出筛选结果") {
                        exportFilteredSoulDocuments()
                    }
                    .disabled(filteredTemplates.isEmpty)

                    Button("导出全部") {
                        exportAllSoulDocuments()
                    }
                    .disabled(sortedTemplates.isEmpty)
                }
                .menuStyle(.borderlessButton)

                Picker("", selection: $mode) {
                    ForEach(TemplateManagerMode.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
                Button("关闭") { dismiss() }
            }
            .padding()

            Divider()

            HStack(spacing: 0) {
                templateListPane
                Divider()
                contentPane
            }

            if let feedbackMessage {
                Divider()
                Text(feedbackMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 980, minHeight: 680)
        .onAppear {
            let initial = templateLibrary.template(withID: selectedTemplateID)?.id
                ?? sortedTemplates.first?.id
            selectedTemplateManagerID = initial
            if let template = initial.flatMap({ templateLibrary.template(withID: $0) }) {
                draft = TemplateEditorDraft(template: template)
            }
        }
        .onChange(of: selectedTemplateManagerID) { _, newValue in
            if let newValue, let template = templateLibrary.template(withID: newValue) {
                draft = TemplateEditorDraft(template: template)
            } else {
                draft = nil
            }
        }
        .onChange(of: templateLibrary.templates.map(\.id)) { _, ids in
            if let selectedTemplateManagerID, ids.contains(selectedTemplateManagerID) {
                return
            }
            selectedTemplateManagerID = ids.first
        }
        .onChange(of: filteredTemplates.map(\.id)) { _, ids in
            guard !ids.isEmpty else { return }
            if let selectedTemplateManagerID, ids.contains(selectedTemplateManagerID) {
                return
            }
            selectedTemplateManagerID = ids.first
        }
    }

    @ViewBuilder
    private var templateListPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button("新建自定义模板") {
                    let sourceID = selectedTemplateManagerID ?? AgentTemplateCatalog.defaultTemplateID
                    if let template = templateLibrary.duplicateTemplate(from: sourceID) {
                        selectedTemplateManagerID = template.id
                        selectedTemplateID = template.id
                        draft = TemplateEditorDraft(template: template)
                        feedbackMessage = "已创建自定义模板：\(template.name)"
                    }
                }
                .buttonStyle(.bordered)

                Button("导入模板") {
                    importTemplates()
                }
                .buttonStyle(.bordered)
            }

            TextField("搜索模板", text: $searchText)
                .textFieldStyle(.roundedBorder)

            HStack {
                Picker("来源", selection: $sourceFilter) {
                    ForEach(TemplateLibrarySourceFilter.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.menu)

                Picker(
                    "标签",
                    selection: Binding(
                        get: { tagFilter },
                        set: { tagFilter = $0 }
                    )
                ) {
                    Text("全部标签").tag(Optional<String>.none)
                    ForEach(availableTags, id: \.self) { tag in
                        Text(tag).tag(Optional(tag))
                    }
                }
                .pickerStyle(.menu)

                Picker(
                    "家族",
                    selection: Binding(
                        get: { familyFilter },
                        set: { familyFilter = $0 }
                    )
                ) {
                    Text("全部家族").tag(Optional<AgentTemplateFamily>.none)
                    ForEach(AgentTemplateCatalog.families, id: \.self) { family in
                        Text(family.rawValue).tag(Optional(family))
                    }
                }
                .pickerStyle(.menu)
            }

            HStack {
                Text("模板数：\(filteredTemplates.count) / \(sortedTemplates.count)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text("收藏：\(templateLibrary.favoriteTemplateIDs.count)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text("最近：\(templateLibrary.recentTemplateIDs.count)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                if !trimmedSearchText.isEmpty || sourceFilter != .all || familyFilter != nil || tagFilter != nil {
                    Button("清除筛选") {
                        searchText = ""
                        sourceFilter = .all
                        familyFilter = nil
                        tagFilter = nil
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            }

            List(selection: $selectedTemplateManagerID) {
                ForEach(groupedTemplates, id: \.family) { familyGroup in
                    Section(familyGroup.family.rawValue) {
                        ForEach(familyGroup.groups, id: \.category) { group in
                            Section(group.category.rawValue) {
                                ForEach(group.templates, id: \.id) { template in
                                    templateListRow(template)
                                }
                            }
                        }
                    }
                }
            }

            if groupedTemplates.isEmpty {
                Text("当前筛选条件下没有可显示的模板。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(width: 280)
    }

    @ViewBuilder
    private var contentPane: some View {
        switch mode {
        case .editor:
            templateEditorPane
        case .validation:
            TemplateValidationScannerView(
                templates: sortedTemplates,
                onSelectTemplate: { templateID in
                    selectedTemplateManagerID = templateID
                    selectedTemplateID = templateID
                    mode = .editor
                }
            )
        }
    }

    @ViewBuilder
    private var templateEditorPane: some View {
        if let template = selectedTemplate, let draft {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(templateLibrary.isBuiltInTemplate(template.id) ? "内置模板" : "自定义模板")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(template.id)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                        }
                        Spacer()
                        Button("导出当前模板") {
                            exportTemplate(templateID: template.id)
                        }
                        .buttonStyle(.bordered)

                        Button("导出 SOUL.md") {
                            exportSoulDocument(for: template)
                        }
                        .buttonStyle(.bordered)

                        Button(templateLibrary.isFavorite(template.id) ? "取消收藏" : "加入收藏") {
                            templateLibrary.toggleFavorite(template.id)
                            feedbackMessage = templateLibrary.isFavorite(template.id) ? "已加入收藏模板。" : "已取消收藏模板。"
                        }
                        .buttonStyle(.bordered)

                        Button("上移") {
                            templateLibrary.moveTemplate(template.id, direction: .up)
                        }
                        .buttonStyle(.bordered)
                        .disabled((selectedTemplateSortIndex ?? 0) == 0)

                        Button("下移") {
                            templateLibrary.moveTemplate(template.id, direction: .down)
                        }
                        .buttonStyle(.bordered)
                        .disabled((selectedTemplateSortIndex ?? (sortedTemplates.count - 1)) >= sortedTemplates.count - 1)

                        if templateLibrary.isBuiltInTemplate(template.id) {
                            Button("重置内置覆盖") {
                                templateLibrary.resetBuiltInTemplate(template.id)
                                if let reloaded = templateLibrary.template(withID: template.id) {
                                    self.draft = TemplateEditorDraft(template: reloaded)
                                    feedbackMessage = "已重置内置模板覆盖。"
                                }
                            }
                            .buttonStyle(.bordered)
                        } else {
                            Button("删除自定义模板", role: .destructive) {
                                let fallbackID = AgentTemplateCatalog.defaultTemplateID
                                templateLibrary.deleteCustomTemplate(template.id)
                                selectedTemplateManagerID = templateLibrary.template(withID: fallbackID)?.id ?? templateLibrary.templates.first?.id
                                feedbackMessage = "已删除自定义模板。"
                            }
                            .buttonStyle(.bordered)
                        }

                        Button("另存为副本") {
                            if let copy = templateLibrary.duplicateTemplate(from: template.id) {
                                selectedTemplateManagerID = copy.id
                                selectedTemplateID = copy.id
                                self.draft = TemplateEditorDraft(template: copy)
                                feedbackMessage = "已复制模板：\(copy.name)"
                            }
                        }
                        .buttonStyle(.bordered)

                        Button("保存修改") {
                            saveDraft(baseTemplate: template, draft: draft)
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    TemplateDraftEditor(
                        draft: Binding(
                            get: { self.draft ?? TemplateEditorDraft(template: template) },
                            set: { self.draft = $0 }
                        )
                    )

                    VStack(alignment: .leading, spacing: 8) {
                        Text("SOUL.md 预览")
                            .font(.headline)
                        TextEditor(text: .constant((self.draft ?? TemplateEditorDraft(template: template)).applying(to: template).soulMD))
                            .font(.system(.body, design: .monospaced))
                            .frame(height: 320)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.gray.opacity(0.25), lineWidth: 1)
                            )
                    }
                }
                .padding()
            }
        } else {
            VStack(spacing: 12) {
                Text("请选择一个模板")
                    .font(.headline)
                Text("可以在左侧选择模板，或新建一个自定义模板。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func saveDraft(baseTemplate: AgentTemplate, draft: TemplateEditorDraft) {
        let updated = draft.applying(to: baseTemplate)
        templateLibrary.upsert(updated)
        selectedTemplateManagerID = updated.id
        selectedTemplateID = updated.id
        self.draft = TemplateEditorDraft(template: updated)
        feedbackMessage = updated.validationIssues.isEmpty ? "模板已保存，并通过规范校验。" : "模板已保存，但仍有 \(updated.validationIssues.count) 个校验问题。"
    }

    private func importTemplates() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]
        panel.begin { response in
            guard response == .OK, let url = panel.url, let data = try? Data(contentsOf: url) else { return }
            do {
                let imported = try templateLibrary.importTemplates(from: data)
                if let first = imported.first {
                    selectedTemplateManagerID = first.id
                    selectedTemplateID = first.id
                    draft = TemplateEditorDraft(template: first)
                }
                feedbackMessage = "已导入 \(imported.count) 个模板。"
            } catch {
                feedbackMessage = "导入失败：\(error.localizedDescription)"
            }
        }
    }

    private func exportTemplate(templateID: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(templateID).json"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let data = try templateLibrary.exportTemplates([templateID])
                try data.write(to: url, options: .atomic)
                feedbackMessage = "模板已导出到 \(url.lastPathComponent)。"
            } catch {
                feedbackMessage = "导出失败：\(error.localizedDescription)"
            }
        }
    }

    private func exportSoulDocument(for template: AgentTemplate) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [markdownContentType]
        panel.nameFieldStringValue = "\(exportFileBaseName(for: template))-SOUL.md"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try template.soulMD.write(to: url, atomically: true, encoding: .utf8)
                feedbackMessage = "SOUL.md 已导出到 \(url.lastPathComponent)。"
            } catch {
                feedbackMessage = "导出 SOUL.md 失败：\(error.localizedDescription)"
            }
        }
    }

    @ViewBuilder
    private func templateListRow(_ template: AgentTemplate) -> some View {
        let issues = template.validationIssues
        let errorCount = issues.filter { $0.severity == .error }.count
        let warningCount = issues.filter { $0.severity == .warning }.count

        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(template.name)
                if templateLibrary.isFavorite(template.id) {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundColor(.yellow)
                }
                if template.id == AgentTemplateCatalog.defaultTemplateID {
                    Text("推荐")
                        .font(.caption2)
                        .foregroundColor(.green)
                }
                Spacer()
            }

            Text(template.taxonomyPath)
                .font(.caption2)
                .foregroundColor(.secondary)

            HStack(spacing: 6) {
                Text(templateLibrary.isBuiltInTemplate(template.id) ? "内置" : "自定义")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                if templateLibrary.recentTemplateIDs.contains(template.id) {
                    Text("最近")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.blue)
                }

                if errorCount > 0 {
                    Text("错误 \(errorCount)")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.red)
                } else if warningCount > 0 {
                    Text("提醒 \(warningCount)")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.orange)
                } else {
                    Text("已校验")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.green)
                }
            }

            if !template.tags.isEmpty {
                Text("标签：\(template.tags.joined(separator: " · "))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .tag(template.id)
    }

    private func exportAllTemplates() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "agent-template-library.json"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let data = try templateLibrary.exportAllTemplates()
                try data.write(to: url, options: .atomic)
                feedbackMessage = "已导出全部模板到 \(url.lastPathComponent)。"
            } catch {
                feedbackMessage = "导出全部失败：\(error.localizedDescription)"
            }
        }
    }

    private func exportFilteredTemplates() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "filtered-agent-templates.json"
        let filteredTemplateIDs = filteredTemplates.map(\.id)

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let data = try templateLibrary.exportTemplates(filteredTemplateIDs)
                try data.write(to: url, options: .atomic)
                feedbackMessage = "已导出 \(filteredTemplateIDs.count) 个筛选模板到 \(url.lastPathComponent)。"
            } catch {
                feedbackMessage = "导出筛选结果失败：\(error.localizedDescription)"
            }
        }
    }

    private func exportFilteredSoulDocuments() {
        exportSoulDocuments(filteredTemplates, directoryName: "filtered-soul-documents")
    }

    private func exportAllSoulDocuments() {
        exportSoulDocuments(sortedTemplates, directoryName: "all-soul-documents")
    }

    private func exportSoulDocuments(_ templates: [AgentTemplate], directoryName: String) {
        guard !templates.isEmpty else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "选择导出目录"
        panel.message = "为纯净的 SOUL.md 文件选择一个导出目录。"
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        panel.begin { response in
            guard response == .OK, let directoryURL = panel.url else { return }

            let exportDirectory = directoryURL.appendingPathComponent(directoryName, isDirectory: true)

            do {
                try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
                for template in templates {
                    let fileURL = exportDirectory
                        .appendingPathComponent("\(exportFileBaseName(for: template))-SOUL")
                        .appendingPathExtension("md")
                    try template.soulMD.write(to: fileURL, atomically: true, encoding: .utf8)
                }
                feedbackMessage = "已导出 \(templates.count) 份 SOUL.md 到 \(exportDirectory.lastPathComponent)。"
            } catch {
                feedbackMessage = "批量导出 SOUL.md 失败：\(error.localizedDescription)"
            }
        }
    }

    private func exportFileBaseName(for template: AgentTemplate) -> String {
        let preferredName = template.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = preferredName.isEmpty ? template.id : preferredName
        let invalidCharacters = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let cleaned = base
            .components(separatedBy: invalidCharacters)
            .joined(separator: "-")
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "--", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-. "))

        return cleaned.isEmpty ? template.id.replacingOccurrences(of: ".", with: "-") : cleaned
    }
}

private struct TemplateDraftEditor: View {
    @Binding var draft: TemplateEditorDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("管理字段") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        editorField("名称", text: $draft.name)
                        editorField("Identity", text: $draft.identity)
                    }
                    HStack {
                        Picker("分类", selection: $draft.category) {
                            ForEach(AgentTemplateCatalog.categories, id: \.self) { category in
                                Text(category.rawValue).tag(category)
                            }
                        }
                        .pickerStyle(.menu)
                        editorField("颜色 HEX", text: $draft.colorHex)
                    }
                    multilineField("摘要", text: $draft.summary, height: 70)
                    multilineField("适用场景", text: $draft.applicableScenariosText, height: 80)
                    multilineField("能力标签", text: $draft.capabilitiesText, height: 80)
                    multilineField("模板标签", text: $draft.tagsText, height: 80)
                }
            }

            GroupBox("SOUL 结构") {
                VStack(alignment: .leading, spacing: 10) {
                    multilineField("角色定位", text: $draft.role, height: 70)
                    multilineField("核心使命", text: $draft.mission, height: 70)
                    multilineField("核心能力", text: $draft.coreCapabilitiesText, height: 80)
                    multilineField("输入要求", text: $draft.inputsText, height: 80)
                    multilineField("工作职责", text: $draft.responsibilitiesText, height: 110)
                    multilineField("工作流程", text: $draft.workflowText, height: 110)
                    multilineField("输出要求", text: $draft.outputsText, height: 90)
                    multilineField("协作边界", text: $draft.collaborationText, height: 90)
                    multilineField("行为边界", text: $draft.guardrailsText, height: 90)
                    multilineField("成功标准", text: $draft.successCriteriaText, height: 90)
                }
            }
        }
    }

    @ViewBuilder
    private func editorField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            TextField(title, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    @ViewBuilder
    private func multilineField(_ title: String, text: Binding<String>, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            TextEditor(text: text)
                .font(.system(.body, design: .monospaced))
                .frame(height: height)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.25), lineWidth: 1)
                )
        }
    }
}

private struct TemplateValidationScannerView: View {
    let templates: [AgentTemplate]
    let onSelectTemplate: (String) -> Void

    @State private var searchText: String = ""
    @State private var severityFilter: TemplateValidationSeverityFilter = .all

    private var invalidTemplates: [AgentTemplate] {
        templates.filter { !$0.validationIssues.isEmpty }
    }

    private var filteredInvalidTemplates: [AgentTemplate] {
        let trimmedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        return invalidTemplates.filter { template in
            let matchingIssues = filteredIssues(for: template)
            let matchesTemplateFields = trimmedSearchText.isEmpty
                || template.name.localizedCaseInsensitiveContains(trimmedSearchText)
                || template.summary.localizedCaseInsensitiveContains(trimmedSearchText)
                || template.taxonomyPath.localizedCaseInsensitiveContains(trimmedSearchText)

            return matchesTemplateFields || !matchingIssues.isEmpty
        }
    }

    private var totalErrorCount: Int {
        invalidTemplates.flatMap(\.validationIssues).filter { $0.severity == .error }.count
    }

    private var totalWarningCount: Int {
        invalidTemplates.flatMap(\.validationIssues).filter { $0.severity == .warning }.count
    }

    private func filteredIssues(for template: AgentTemplate) -> [AgentTemplateValidationIssue] {
        let trimmedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        return template.validationIssues.filter { issue in
            let matchesSeverity: Bool
            switch severityFilter {
            case .all:
                matchesSeverity = true
            case .errorsOnly:
                matchesSeverity = issue.severity == .error
            case .warningsOnly:
                matchesSeverity = issue.severity == .warning
            }

            let matchesSearch = trimmedSearchText.isEmpty
                || issue.field.localizedCaseInsensitiveContains(trimmedSearchText)
                || issue.message.localizedCaseInsensitiveContains(trimmedSearchText)

            return matchesSeverity && matchesSearch
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("模板校验扫描")
                            .font(.headline)
                        Text("扫描所有模板，检查是否存在管理信息泄漏、字段缺失或内容过长。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text("异常模板：\(filteredInvalidTemplates.count) / \(templates.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(invalidTemplates.isEmpty ? .green : .orange)
                }

                HStack {
                    TextField("搜索异常模板或问题描述", text: $searchText)
                        .textFieldStyle(.roundedBorder)

                    Picker("问题级别", selection: $severityFilter) {
                        ForEach(TemplateValidationSeverityFilter.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 120)
                }

                HStack(spacing: 12) {
                    Text("错误：\(totalErrorCount)")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.red)
                    Text("提醒：\(totalWarningCount)")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.orange)
                    Spacer()
                    if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || severityFilter != .all {
                        Button("清除筛选") {
                            searchText = ""
                            severityFilter = .all
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    }
                }

                if invalidTemplates.isEmpty {
                    Text("当前所有模板均通过规范校验。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.green.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else if filteredInvalidTemplates.isEmpty {
                    Text("当前筛选条件下没有匹配的问题模板。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                    ForEach(filteredInvalidTemplates, id: \.id) { template in
                        let issues = filteredIssues(for: template)

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(template.name)
                                        .font(.subheadline.weight(.semibold))
                                    Text(template.taxonomyPath)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Button("打开模板") {
                                    onSelectTemplate(template.id)
                                }
                                .buttonStyle(.bordered)
                            }

                            ForEach(issues) { issue in
                                Text("[\(issue.severity.rawValue.uppercased())] \(issue.field): \(issue.message)")
                                    .font(.caption)
                                    .foregroundColor(issue.severity == .error ? .red : .orange)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
                projectInfoSection
                taskDataSection
                workflowRoutingSection
                launchVerificationSection
                memoryBackupSection
                statisticsSection
                exportSection
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

    @ViewBuilder
    private var projectInfoSection: some View {
        SectionView(title: LocalizedString.text("project_info")) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(LocalizedString.text("project_name_label"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField(LocalizedString.text("project_name_label"), text: $projectName)
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
                    InfoRow(label: LocalizedString.text("created_label"), value: project.createdAt.formatted(date: .abbreviated, time: .shortened))
                    InfoRow(label: LocalizedString.text("last_updated"), value: project.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    InfoRow(label: LocalizedString.agents, value: "\(project.agents.count)")
                    InfoRow(label: LocalizedString.workflows, value: "\(project.workflows.count)")
                    InfoRow(label: "OpenClaw", value: project.openClaw.config.deploymentSummary)
                }
            }
        }
    }

    @ViewBuilder
    private var taskDataSection: some View {
        SectionView(title: LocalizedString.text("task_data")) {
            VStack(alignment: .leading, spacing: 12) {
                Text(workspaceRootPath)
                    .font(.caption)
                    .textSelection(.enabled)

                HStack {
                    Button(LocalizedString.text("choose_folder")) {
                        appState.chooseTaskDataRootDirectory()
                    }
                    Button(LocalizedString.text("reset_default")) {
                        appState.resetTaskDataRootDirectory()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var workflowRoutingSection: some View {
        SectionView(title: LocalizedString.text("workflow_routing")) {
            VStack(alignment: .leading, spacing: 12) {
                if workflows.isEmpty {
                    Text(LocalizedString.text("no_workflows_in_project"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(LocalizedString.text("workflow_label"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Picker(LocalizedString.text("workflow_label"), selection: workflowSelectionBinding) {
                            ForEach(workflows) { workflow in
                                Text(workflow.name).tag(workflow.id as UUID?)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    if let workflow = selectedWorkflow {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(LocalizedString.text("fallback_routing_policy"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Picker(
                                LocalizedString.text("fallback_routing_policy"),
                                selection: fallbackRoutingPolicyBinding(for: workflow)
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
    }

    @ViewBuilder
    private var launchVerificationSection: some View {
        SectionView(title: LocalizedString.text("launch_verification")) {
            VStack(alignment: .leading, spacing: 12) {
                launchVerificationHeader

                if isRunningLaunchVerification {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(LocalizedString.text("running_launch_verification"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if let report = selectedWorkflow?.lastLaunchVerificationReport {
                    launchVerificationReportView(report)
                } else {
                    Text(LocalizedString.text("no_launch_verification_report"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .confirmationDialog(
                LocalizedString.text("run_launch_verification_confirm"),
                isPresented: $showLaunchVerificationConfirmation,
                titleVisibility: .visible
            ) {
                Button(LocalizedString.text("start_verification")) {
                    startLaunchVerification()
                }
                Button(LocalizedString.cancel, role: .cancel) { }
            } message: {
                Text(LocalizedString.text("launch_verification_confirm_message"))
            }
        }
    }

    @ViewBuilder
    private var memoryBackupSection: some View {
        SectionView(title: LocalizedString.text("memory_backup_section")) {
            VStack(alignment: .leading, spacing: 8) {
                InfoRow(label: LocalizedString.text("mode_label"), value: appState.currentProject?.memoryData.backupOnly == true ? LocalizedString.text("backup_only") : LocalizedString.text("managed_mode"))
                InfoRow(label: LocalizedString.text("task_memories"), value: "\(appState.currentProject?.memoryData.taskExecutionMemories.count ?? 0)")
                InfoRow(label: LocalizedString.text("agent_memories"), value: "\(appState.currentProject?.memoryData.agentMemories.count ?? 0)")
            }
        }
    }

    @ViewBuilder
    private var statisticsSection: some View {
        SectionView(title: LocalizedString.text("statistics_section")) {
            VStack(alignment: .leading, spacing: 8) {
                InfoRow(label: LocalizedString.text("total_nodes"), value: "\(appState.currentProject?.workflows.first?.nodes.count ?? 0)")
                InfoRow(label: LocalizedString.text("total_connections"), value: "\(appState.currentProject?.workflows.first?.edges.count ?? 0)")
                InfoRow(label: LocalizedString.text("total_boundaries"), value: "\(appState.currentProject?.workflows.first?.boundaries.count ?? 0)")
                InfoRow(label: LocalizedString.text("project_size"), value: LocalizedString.text("compact_size"))
            }
        }
    }

    @ViewBuilder
    private var exportSection: some View {
        SectionView(title: LocalizedString.text("export_section")) {
            VStack(alignment: .leading, spacing: 12) {
                Text(LocalizedString.text("export_project_sharing_hint"))
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack {
                    Button(LocalizedString.text("export_as_json")) {
                        exportProjectAsJSON()
                    }

                    Button(LocalizedString.text("export_as_image")) {
                        // 导出为图片功能
                    }
                    .disabled(true)
                }
            }
        }
    }

    @ViewBuilder
    private var launchVerificationHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedString.text("manual_check"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(LocalizedString.text("launch_verification_manual_hint"))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(isRunningLaunchVerification ? LocalizedString.text("execution_running") : LocalizedString.text("launch_verification")) {
                showLaunchVerificationConfirmation = true
            }
            .disabled(selectedWorkflow == nil || isRunningLaunchVerification || appState.openClawService.isExecuting)
        }
    }

    @ViewBuilder
    private func launchVerificationReportView(_ report: WorkflowLaunchVerificationReport) -> some View {
        HStack {
            Text(LocalizedString.text("last_result"))
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

        InfoRow(label: LocalizedString.text("started_label"), value: report.startedAt.formatted(date: .abbreviated, time: .shortened))
        InfoRow(label: LocalizedString.text("completed_label"), value: report.completedAt?.formatted(date: .abbreviated, time: .shortened) ?? LocalizedString.text("execution_running"))
        InfoRow(label: LocalizedString.text("cases_label"), value: "\(report.testCaseReports.count)")

        if !report.staticFindings.isEmpty {
            verificationList(title: LocalizedString.text("static_findings"), items: report.staticFindings, color: .orange)
        }

        if !report.runtimeFindings.isEmpty {
            verificationList(title: LocalizedString.text("runtime_findings"), items: Array(report.runtimeFindings.prefix(5)), color: .blue)
        }

        if !report.testCaseReports.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(LocalizedString.text("case_results"))
                    .font(.caption)
                    .foregroundColor(.secondary)

                ForEach(report.testCaseReports) { caseReport in
                    launchVerificationCaseRow(caseReport)
                }
            }
        }
    }

    @ViewBuilder
    private func launchVerificationCaseRow(_ caseReport: WorkflowLaunchTestCaseReport) -> some View {
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
            Text(LocalizedString.format("case_result_summary", caseReport.actualStepCount, caseReport.actualAgents.joined(separator: ", ")))
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

    private var workflowSelectionBinding: Binding<UUID?> {
        Binding(
            get: { selectedWorkflowID ?? workflows.first?.id },
            set: { selectedWorkflowID = $0 }
        )
    }

    private func fallbackRoutingPolicyBinding(for workflow: Workflow) -> Binding<WorkflowFallbackRoutingPolicy> {
        Binding(
            get: { workflow.fallbackRoutingPolicy },
            set: { newPolicy in
                var updatedWorkflow = workflow
                updatedWorkflow.fallbackRoutingPolicy = newPolicy
                appState.updateWorkflow(updatedWorkflow)
            }
        )
    }
    
    private func exportProjectAsJSON() {
        guard let project = appState.currentProject else { return }
        
        let panel = NSSavePanel()
        panel.title = LocalizedString.text("export_project_title")
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

    private func startLaunchVerification() {
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
