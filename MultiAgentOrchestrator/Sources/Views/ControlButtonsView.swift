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
    @Binding var selectedNodeIDs: Set<UUID>
    @Binding var selectedEdgeID: UUID?
    @Binding var isConnectMode: Bool
    @Binding var connectionType: WorkflowEditorView.ConnectionType
    @Binding var connectFromAgentID: UUID?
    @Binding var isLassoMode: Bool

    var onDeleteSelectedEdge: () -> Void
    var onCopySelection: () -> Void
    var onPasteSelection: () -> Void
    var onDeleteSelection: () -> Void

    let appState: AppState

    private var hasNodeSelection: Bool {
        selectedNodeID != nil || !selectedNodeIDs.isEmpty
    }

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
                        .help(isConnectMode ? "取消创建连线" : "准备创建连线")

                        if isConnectMode {
                            HStack(spacing: 4) {
                                connectionTypeButton(type: .unidirectional)
                                connectionTypeButton(type: .bidirectional)
                            }
                            .transition(.opacity.combined(with: .move(edge: .trailing)))
                        }

                        Button(action: onDeleteSelectedEdge) {
                            Image(systemName: "link.badge.minus")
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.bordered)
                        .disabled(selectedEdgeID == nil)
                        .help("删除选中连接线")
                    }

                    HStack(spacing: 6) {
                        Button(action: zoomOut) {
                            Image(systemName: "minus.magnifyingglass")
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.bordered)
                        .keyboardShortcut("-")
                        .help("缩小")

                        Text("\(Int(scale * 100))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 48)

                        Button(action: zoomIn) {
                            Image(systemName: "plus.magnifyingglass")
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.bordered)
                        .keyboardShortcut("+")
                        .help("放大")

                        Button(action: resetView) {
                            Image(systemName: "arrow.counterclockwise")
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.bordered)
                        .keyboardShortcut("0")
                        .help("重置视图")
                    }

                    HStack(spacing: 6) {
                        Button(action: toggleLassoMode) {
                            Image(systemName: isLassoMode ? "selection.pin.in.out" : "selection.pin.out")
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.bordered)
                        .tint(isLassoMode ? .accentColor : nil)
                        .help("框选模式")

                        Button(action: onCopySelection) {
                            Image(systemName: "doc.on.doc")
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.bordered)
                        .disabled(!hasNodeSelection)
                        .help("复制选中节点")

                        Button(action: onPasteSelection) {
                            Image(systemName: "doc.on.clipboard")
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.bordered)
                        .help("粘贴节点")

                        Button(action: onDeleteSelection) {
                            Image(systemName: "trash")
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.bordered)
                        .disabled(!hasNodeSelection)
                        .help("删除选中节点")
                    }

                    HStack(spacing: 6) {
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
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.bordered)
                        .help("添加节点")

                        Button(action: generateTasksFromWorkflow) {
                            Image(systemName: "list.bullet.clipboard")
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.bordered)
                        .help("从工作流生成任务")
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
            if isConnectMode {
                isLassoMode = false
            }
            if !isConnectMode {
                connectFromAgentID = nil
            }
        }
    }

    private func toggleLassoMode() {
        withAnimation(.easeInOut(duration: 0.15)) {
            isLassoMode.toggle()
            if isLassoMode {
                isConnectMode = false
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
        appState.addNode(type: type, position: CGPoint(x: 300, y: 200))
    }

    private func addAgentNode(_ agent: Agent) {
        appState.addAgentNode(agentName: agent.name, position: CGPoint(x: 300, y: 200))
    }
}
