//
//  ControlButtonsView.swift
//  MultiAgentOrchestrator
//

import SwiftUI

struct ControlButtonsView: View {
    @Binding var scale: CGFloat
    @Binding var offset: CGSize
    @Binding var lastOffset: CGSize
    @Binding var selectedNodeID: UUID?
    @Binding var selectedEdgeID: UUID?
    let appState: AppState

    var body: some View {
        VStack {
            HStack {
                Spacer()
                VStack(spacing: 8) {
                    Group {
                        Button(action: zoomIn) {
                            Image(systemName: "plus.magnifyingglass")
                                .frame(width: 30, height: 30)
                        }
                        .keyboardShortcut("+")
                        .help("放大")

                        Button(action: zoomOut) {
                            Image(systemName: "minus.magnifyingglass")
                                .frame(width: 30, height: 30)
                        }
                        .keyboardShortcut("-")
                        .help("缩小")

                        Button(action: resetView) {
                            Image(systemName: "arrow.counterclockwise")
                                .frame(width: 30, height: 30)
                        }
                        .keyboardShortcut("0")
                        .help("重置视图")
                    }
                    .buttonStyle(.bordered)

                    Divider()
                        .frame(width: 30)

                    Group {
                        Menu {
                            Button("Start Node") { addNode(type: .start) }
                            Button("End Node") { addNode(type: .end) }
                            Button("Branch Node") { addNode(type: .branch) }
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
                                .frame(width: 30, height: 30)
                        }
                        .help("添加节点")

                        Button(action: deleteSelectedNode) {
                            Image(systemName: "trash")
                                .frame(width: 30, height: 30)
                        }
                        .keyboardShortcut(.delete, modifiers: [])
                        .disabled(selectedNodeID == nil)
                        .help("删除选中节点")

                        Button(action: deleteSelectedEdge) {
                            Image(systemName: "link.badge.minus")
                                .frame(width: 30, height: 30)
                        }
                        .disabled(selectedEdgeID == nil)
                        .help("删除选中连接线")
                    }
                    .buttonStyle(.bordered)

                    Button(action: generateTasksFromWorkflow) {
                        Image(systemName: "list.bullet.clipboard")
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.bordered)
                    .help("Generate Tasks from Workflow")
                }
                .padding()
            }
            Spacer()
        }
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

    private func resetView() {
        withAnimation(.easeInOut(duration: 0.3)) {
            scale = 1.0
            offset = .zero
            lastOffset = .zero
        }
    }

    private func addNode(type: WorkflowNode.NodeType) {
        appState.addNode(type: type, position: CGPoint(x: 300, y: 200))
    }

    private func addAgentNode(_ agent: Agent) {
        appState.addAgentNode(agentName: agent.name, position: CGPoint(x: 300, y: 200))
    }

    private func deleteSelectedNode() {
        guard let nodeID = selectedNodeID else { return }
        appState.removeNode(nodeID)
        selectedNodeID = nil
    }

    private func deleteSelectedEdge() {
        guard let edgeID = selectedEdgeID else { return }
        appState.removeEdge(edgeID)
        selectedEdgeID = nil
    }
}
