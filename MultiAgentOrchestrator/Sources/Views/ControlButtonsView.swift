//
//  ControlButtonsView.swift
//  MultiAgentOrchestrator
//
//  Created by 陈荣泽 on 2026/3/18.
//

import SwiftUI

struct ControlButtonsView: View {
    @Binding var scale: CGFloat
    @Binding var offset: CGSize
    @Binding var lastOffset: CGSize
    @Binding var selectedNodeID: UUID?
    @Binding var isConnectMode: Bool
    @Binding var connectionType: WorkflowEditorView.ConnectionType
    @Binding var connectFromAgentID: UUID?
    let appState: AppState

    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    HStack(spacing: 6) {
                        Button(action: toggleConnectMode) {
                            Image(systemName: isConnectMode ? "link.circle.fill" : "link.circle")
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(isConnectMode ? .blue : .accentColor)
                        .help("连线模式")

                        if isConnectMode {
                            HStack(spacing: 4) {
                                connectionTypeButton(type: .unidirectional)
                                connectionTypeButton(type: .bidirectional)
                            }
                            .transition(.opacity.combined(with: .move(edge: .trailing)))
                        }
                    }

                    HStack(spacing: 6) {
                        Button(action: zoomOut) {
                            Image(systemName: "minus.magnifyingglass")
                                .frame(width: 28, height: 28)
                        }
                        .keyboardShortcut("-")
                        .buttonStyle(.bordered)
                        .help("缩小")

                        Text("\(Int(scale * 100))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 48)

                        Button(action: zoomIn) {
                            Image(systemName: "plus.magnifyingglass")
                                .frame(width: 28, height: 28)
                        }
                        .keyboardShortcut("+")
                        .buttonStyle(.bordered)
                        .help("放大")

                        Button(action: resetView) {
                            Image(systemName: "arrow.counterclockwise")
                                .frame(width: 28, height: 28)
                        }
                        .keyboardShortcut("0")
                        .buttonStyle(.bordered)
                        .help("重置视图")
                    }

                    HStack(spacing: 6) {
                        Menu {
                            Button("Start Node") { addNode(type: .start) }
                            Button("End Node") { addNode(type: .end) }
                            Button("Subflow Node") { addNode(type: .subflow) }

                            if let agents = appState.currentProject?.agents, !agents.isEmpty {
                                Divider()
                                Menu("Agent Nodes") {
                                    ForEach(agents) { agent in
                                        Button(agent.name) {
                                            addAgentNode(agent)
                                        }
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: "plus.circle")
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.bordered)
                        .help("添加节点")

                        Button(action: deleteSelectedNode) {
                            Image(systemName: "trash")
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.bordered)
                        .keyboardShortcut(.delete, modifiers: [])
                        .disabled(selectedNodeID == nil)
                        .help("删除选中节点")

                        Button(action: generateTasksFromWorkflow) {
                            Image(systemName: "list.bullet.clipboard")
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.bordered)
                        .help("Generate Tasks from Workflow")
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.windowBackgroundColor).opacity(0.95))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 3)
            }
            .padding(12)
        }
    }

    @ViewBuilder
    private func connectionTypeButton(type: WorkflowEditorView.ConnectionType) -> some View {
        Button(action: {
            connectionType = type
            isConnectMode = true
        }) {
            Text(type.rawValue)
                .font(.headline)
                .frame(width: 34, height: 28)
        }
        .buttonStyle(.bordered)
        .tint(connectionType == type ? .blue : nil)
        .help(type.description)
    }
    
    private func generateTasksFromWorkflow() {
        guard let workflow = appState.currentProject?.workflows.first,
              let agents = appState.currentProject?.agents else { return }
        
        appState.taskManager.generateTasks(from: workflow, projectAgents: agents)
    }
    
    private func zoomIn() {
        withAnimation(.easeInOut(duration: 0.2)) {
            scale = min(scale + 0.2, 5.0)
        }
    }
    
    private func zoomOut() {
        withAnimation(.easeInOut(duration: 0.2)) {
            scale = max(scale - 0.2, 0.1)
        }
    }

    private func toggleConnectMode() {
        withAnimation(.easeInOut(duration: 0.15)) {
            isConnectMode.toggle()
            if !isConnectMode {
                connectFromAgentID = nil
            }
        }
    }
    
    private func resetView() {
        withAnimation(.easeInOut(duration: 0.3)) {
            scale = 1.0
            offset = .zero
            lastOffset = .zero
        }
    }
    
    private func addNode(type: WorkflowNode.NodeType) {
        guard let workflow = appState.currentProject?.workflows.first else { return }
        
        let newNode = WorkflowNode(type: type)
        var newNodeCopy = newNode
        newNodeCopy.position = CGPoint(x: 300, y: 200)
        
        var updatedWorkflow = workflow
        updatedWorkflow.nodes.append(newNodeCopy)
        
        if let index = appState.currentProject?.workflows.firstIndex(where: { $0.id == workflow.id }) {
            appState.currentProject?.workflows[index] = updatedWorkflow
        }
    }
    
    private func addAgentNode(_ agent: Agent) {
        guard let workflow = appState.currentProject?.workflows.first else { return }
        
        var newNode = WorkflowNode(type: .agent)
        newNode.agentID = agent.id
        newNode.position = CGPoint(x: 300, y: 200)
        
        var updatedWorkflow = workflow
        updatedWorkflow.nodes.append(newNode)
        
        if let index = appState.currentProject?.workflows.firstIndex(where: { $0.id == workflow.id }) {
            appState.currentProject?.workflows[index] = updatedWorkflow
        }
    }
    
    private func deleteSelectedNode() {
        guard let nodeID = selectedNodeID,
              let workflow = appState.currentProject?.workflows.first else { return }
        
        var updatedWorkflow = workflow
        updatedWorkflow.nodes.removeAll { $0.id == nodeID }
        updatedWorkflow.edges.removeAll { $0.fromNodeID == nodeID || $0.toNodeID == nodeID }
        
        if let index = appState.currentProject?.workflows.firstIndex(where: { $0.id == workflow.id }) {
            appState.currentProject?.workflows[index] = updatedWorkflow
        }
        
        selectedNodeID = nil
    }
}
