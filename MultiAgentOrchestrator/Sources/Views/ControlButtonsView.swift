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
    var onCutSelection: () -> Void
    var onPasteSelection: () -> Void
    var onDeleteSelection: () -> Void

    let appState: AppState

    @State private var panelSize = CGSize(width: 280, height: 244)
    @State private var panelSizeAtDragStart: CGSize?
    @State private var activeResizeEdges: PanelResizeEdges = []
    private let edgeResizeThreshold: CGFloat = 12

    private var hasNodeSelection: Bool {
        selectedNodeID != nil || !selectedNodeIDs.isEmpty
    }

    private var activeSelection: Set<UUID> {
        if !selectedNodeIDs.isEmpty {
            return selectedNodeIDs
        }
        if let selectedNodeID {
            return [selectedNodeID]
        }
        return []
    }

    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                VStack(spacing: 0) {
                    ScrollView {
                        LazyVGrid(columns: gridColumns, spacing: 10) {
                            controlCard(title: "连线", icon: "link") {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(spacing: 6) {
                                        iconButton(
                                            systemName: isConnectMode ? "link.circle.fill" : "link.circle",
                                            action: toggleConnectMode,
                                            prominent: true
                                        )
                                        .tint(isConnectMode ? .blue : .accentColor)
                                        .help(isConnectMode ? "取消创建连线" : "准备创建连线")

                                        iconButton(systemName: "link.badge.minus", action: onDeleteSelectedEdge)
                                            .disabled(selectedEdgeID == nil)
                                            .help("删除选中连接线")
                                    }

                                    if isConnectMode {
                                        HStack(spacing: 6) {
                                            connectionTypeButton(type: .unidirectional)
                                            connectionTypeButton(type: .bidirectional)
                                        }
                                    }
                                }
                            }

                            controlCard(title: "视图", icon: "viewfinder") {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(spacing: 6) {
                                        iconButton(systemName: "minus.magnifyingglass", action: zoomOut)
                                        iconButton(systemName: "plus.magnifyingglass", action: zoomIn)
                                        iconButton(systemName: "arrow.counterclockwise", action: resetView)
                                    }

                                    Text("\(Int(scale * 100))%")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }

                            controlCard(title: "选择", icon: "cursorarrow.motionlines") {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(spacing: 6) {
                                        Button(action: toggleLassoMode) {
                                            Image(systemName: isLassoMode ? "selection.pin.in.out" : "selection.pin.out")
                                                .frame(width: 28, height: 28)
                                        }
                                        .buttonStyle(.bordered)
                                        .tint(isLassoMode ? .accentColor : nil)
                                        .help("框选模式（也支持按住右键拖动）")
                                        iconButton(systemName: "doc.on.doc", action: onCopySelection)
                                            .disabled(!hasNodeSelection)
                                        iconButton(systemName: "scissors", action: onCutSelection)
                                            .disabled(!hasNodeSelection)
                                        iconButton(systemName: "doc.on.clipboard", action: onPasteSelection)
                                        iconButton(systemName: "trash", action: onDeleteSelection)
                                            .disabled(!hasNodeSelection)
                                    }

                                    Text(hasNodeSelection ? "已选中 \(activeSelection.count) 个节点" : "当前未选中节点")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }

                            controlCard(title: "构建", icon: "square.stack.3d.up") {
                                VStack(alignment: .leading, spacing: 8) {
                                    Menu {
                                        Button("New Agent Node") { addNode() }

                                        if let agents = appState.currentProject?.agents, !agents.isEmpty {
                                            Divider()
                                            ForEach(agents) { agent in
                                                Button(agent.name) {
                                                    addAgentNode(agent)
                                                }
                                            }
                                        }
                                    } label: {
                                        Label("添加节点", systemImage: "plus.circle")
                                            .font(.caption)
                                    }
                                    .menuStyle(.borderlessButton)

                                    HStack(spacing: 6) {
                                        iconButton(systemName: "list.bullet.clipboard", action: generateTasksFromWorkflow)
                                        iconButton(systemName: "square.dashed", action: createBoundaryFromSelection)
                                            .disabled(activeSelection.isEmpty)
                                        iconButton(systemName: "trash.square", action: deleteBoundaryFromSelection)
                                            .disabled(activeSelection.isEmpty)
                                    }
                                }
                            }
                        }
                        .padding(12)
                    }

                    resizeHandle
                }
                .frame(width: panelSize.width, height: panelSize.height)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.windowBackgroundColor).opacity(0.95))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                )
                .simultaneousGesture(edgeResizeGesture)
                .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 3)
            }
            .padding(12)
        }
    }

    private var gridColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(minimum: 110, maximum: .infinity), spacing: 10, alignment: .top),
            count: max(1, min(3, Int(panelSize.width / 150)))
        )
    }

    private var resizeHandle: some View {
        HStack {
            Spacer()
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(10)
        }
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    if panelSizeAtDragStart == nil {
                        panelSizeAtDragStart = panelSize
                        activeResizeEdges = [.right, .bottom]
                    }
                    guard let startSize = panelSizeAtDragStart else { return }
                    panelSize = resizedPanelSize(
                        from: startSize,
                        translation: value.translation,
                        edges: activeResizeEdges
                    )
                }
                .onEnded { _ in
                    panelSizeAtDragStart = nil
                    activeResizeEdges = []
                }
        )
    }

    private func resizeEdges(at location: CGPoint) -> PanelResizeEdges {
        var edges: PanelResizeEdges = []
        if location.x <= edgeResizeThreshold { edges.insert(.left) }
        if location.x >= panelSize.width - edgeResizeThreshold { edges.insert(.right) }
        if location.y <= edgeResizeThreshold { edges.insert(.top) }
        if location.y >= panelSize.height - edgeResizeThreshold { edges.insert(.bottom) }
        return edges
    }

    private var edgeResizeGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if panelSizeAtDragStart == nil {
                    let edges = resizeEdges(at: value.startLocation)
                    guard !edges.isEmpty else { return }
                    panelSizeAtDragStart = panelSize
                    activeResizeEdges = edges
                }

                guard let startSize = panelSizeAtDragStart else { return }
                panelSize = resizedPanelSize(
                    from: startSize,
                    translation: value.translation,
                    edges: activeResizeEdges
                )
            }
            .onEnded { _ in
                panelSizeAtDragStart = nil
                activeResizeEdges = []
            }
    }

    private func resizedPanelSize(
        from startSize: CGSize,
        translation: CGSize,
        edges: PanelResizeEdges
    ) -> CGSize {
        var width = startSize.width
        var height = startSize.height

        if edges.contains(.right) {
            width += translation.width
        }
        if edges.contains(.left) {
            width -= translation.width
        }
        if edges.contains(.bottom) {
            height += translation.height
        }
        if edges.contains(.top) {
            height -= translation.height
        }

        return CGSize(
            width: min(max(width, 190), 520),
            height: min(max(height, 170), 420)
        )
    }

    @ViewBuilder
    private func controlCard<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundColor(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private func iconButton(
        systemName: String,
        action: @escaping () -> Void,
        prominent: Bool = false
    ) -> some View {
        Group {
            if prominent {
                Button(action: action) {
                    Image(systemName: systemName)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button(action: action) {
                    Image(systemName: systemName)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.bordered)
            }
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
            scale = min(scale + 0.2, 20.0)
        }
    }

    private func zoomOut() {
        withAnimation(.easeInOut(duration: 0.2)) {
            scale = max(scale - 0.2, 0.05)
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

    private func addNode() {
        let agent = appState.addNewAgent()
        guard let agent else { return }
        appState.addAgentNode(agentName: agent.name, position: CGPoint(x: 300, y: 200))
    }

    private func addAgentNode(_ agent: Agent) {
        appState.addAgentNode(agentName: agent.name, position: CGPoint(x: 300, y: 200))
    }

    private func createBoundaryFromSelection() {
        appState.addBoundary(around: activeSelection)
    }

    private func deleteBoundaryFromSelection() {
        appState.removeBoundary(around: activeSelection)
    }
}

private struct PanelResizeEdges: OptionSet {
    let rawValue: Int

    static let left = PanelResizeEdges(rawValue: 1 << 0)
    static let right = PanelResizeEdges(rawValue: 1 << 1)
    static let top = PanelResizeEdges(rawValue: 1 << 2)
    static let bottom = PanelResizeEdges(rawValue: 1 << 3)
}
