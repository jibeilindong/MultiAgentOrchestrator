//
//  ControlButtonsView.swift
//  Multi-Agent-Flow
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
    @State private var panelCenter: CGPoint = .zero
    @State private var hasInitializedPanelPosition = false
    @State private var panelSizeAtDragStart: CGSize?
    @State private var panelCenterAtDragStart: CGPoint?
    @State private var panelCenterAtResizeStart: CGPoint?
    @State private var activeResizeEdges: PanelResizeEdges = []
    @State private var addNodeTemplateID: String = AgentTemplateCatalog.defaultTemplateID
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
        GeometryReader { geometry in
            Color.clear
                .allowsHitTesting(false)
                .overlay(alignment: .topLeading) {
                    panelView
                        .position(panelCenter)
                        .allowsHitTesting(true)
                }
                .onAppear {
                    initializePanelPositionIfNeeded(in: geometry)
                }
                .onChange(of: geometry.size) { _, newSize in
                    if !hasInitializedPanelPosition {
                        initializePanelPositionIfNeeded(in: geometry)
                    } else {
                        clampPanelPosition(to: newSize)
                    }
                }
        }
    }

    private var panelView: some View {
        ZStack(alignment: .topLeading) {
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
                                        Image(systemName: isLassoMode ? "rectangle.dashed.badge.checkmark" : "rectangle.dashed")
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
                                TemplatePickerButton(
                                    selectedTemplateID: $addNodeTemplateID,
                                    onSelect: { template in
                                        addNode(templateID: template.id)
                                    },
                                    labelTitle: "添加节点",
                                    labelSystemImage: "plus.circle",
                                    blankActionTitle: "New Blank Agent Node",
                                    onCreateBlank: {
                                        addNode()
                                    },
                                    existingAgents: appState.currentProject?.agents ?? [],
                                    onSelectExistingAgent: { agent in
                                        addAgentNode(agent)
                                    }
                                )

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
            .overlay(resizeEdgeZones)
            .simultaneousGesture(moveGesture)
            .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 3)
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
                        panelCenterAtResizeStart = panelCenter
                        activeResizeEdges = [.right, .bottom]
                    }
                    guard let startSize = panelSizeAtDragStart,
                          let startCenter = panelCenterAtResizeStart else { return }
                    let metrics = resizedPanelMetrics(
                        from: startSize,
                        center: startCenter,
                        translation: value.translation,
                        edges: activeResizeEdges
                    )
                    panelSize = metrics.size
                    panelCenter = metrics.center
                }
                .onEnded { _ in
                    panelSizeAtDragStart = nil
                    panelCenterAtResizeStart = nil
                    activeResizeEdges = []
                }
        )
    }

    private var resizeEdgeZones: some View {
        ZStack {
            edgeResizeStrip(edges: [.top], width: panelSize.width - edgeResizeThreshold * 2, height: edgeResizeThreshold)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, edgeResizeThreshold)

            edgeResizeStrip(edges: [.bottom], width: panelSize.width - edgeResizeThreshold * 2, height: edgeResizeThreshold)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.horizontal, edgeResizeThreshold)

            HStack {
                edgeResizeStrip(edges: [.left], width: edgeResizeThreshold, height: panelSize.height - edgeResizeThreshold * 2)
                    .frame(maxHeight: .infinity, alignment: .leading)
                    .padding(.vertical, edgeResizeThreshold)

                Spacer(minLength: 0)

                edgeResizeStrip(edges: [.right], width: edgeResizeThreshold, height: panelSize.height - edgeResizeThreshold * 2)
                    .frame(maxHeight: .infinity, alignment: .trailing)
                    .padding(.vertical, edgeResizeThreshold)
            }
        }
        .frame(width: panelSize.width, height: panelSize.height)
    }

    private func edgeResizeStrip(edges: PanelResizeEdges, width: CGFloat, height: CGFloat) -> some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: max(0, width), height: max(0, height))
            .contentShape(Rectangle())
            .gesture(resizeGesture(for: edges))
    }

    private func resizeGesture(for edges: PanelResizeEdges) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if panelSizeAtDragStart == nil {
                    panelSizeAtDragStart = panelSize
                    panelCenterAtResizeStart = panelCenter
                    activeResizeEdges = edges
                }

                guard let startSize = panelSizeAtDragStart,
                      let startCenter = panelCenterAtResizeStart else { return }

                let metrics = resizedPanelMetrics(
                    from: startSize,
                    center: startCenter,
                    translation: value.translation,
                    edges: activeResizeEdges
                )
                panelSize = metrics.size
                panelCenter = metrics.center
            }
            .onEnded { _ in
                panelSizeAtDragStart = nil
                panelCenterAtResizeStart = nil
                activeResizeEdges = []
            }
    }

    private func resizeEdges(at location: CGPoint) -> PanelResizeEdges {
        var edges: PanelResizeEdges = []
        if location.x <= edgeResizeThreshold { edges.insert(.left) }
        if location.x >= panelSize.width - edgeResizeThreshold { edges.insert(.right) }
        if location.y <= edgeResizeThreshold { edges.insert(.top) }
        if location.y >= panelSize.height - edgeResizeThreshold { edges.insert(.bottom) }
        return edges
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                guard resizeEdges(at: value.startLocation).isEmpty else { return }
                if panelCenterAtDragStart == nil {
                    panelCenterAtDragStart = panelCenter
                }
                guard let startCenter = panelCenterAtDragStart else { return }
                panelCenter = CGPoint(
                    x: startCenter.x + value.translation.width,
                    y: startCenter.y + value.translation.height
                )
            }
            .onEnded { _ in
                panelCenterAtDragStart = nil
            }
    }

    private var edgeResizeGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if panelSizeAtDragStart == nil {
                    let edges = resizeEdges(at: value.startLocation)
                    guard !edges.isEmpty else { return }
                    panelSizeAtDragStart = panelSize
                    panelCenterAtResizeStart = panelCenter
                    activeResizeEdges = edges
                }

                guard let startSize = panelSizeAtDragStart,
                      let startCenter = panelCenterAtResizeStart else { return }
                let metrics = resizedPanelMetrics(
                    from: startSize,
                    center: startCenter,
                    translation: value.translation,
                    edges: activeResizeEdges
                )
                panelSize = metrics.size
                panelCenter = metrics.center
            }
            .onEnded { _ in
                panelSizeAtDragStart = nil
                panelCenterAtResizeStart = nil
                activeResizeEdges = []
            }
    }

    private func resizedPanelMetrics(
        from startSize: CGSize,
        center startCenter: CGPoint,
        translation: CGSize,
        edges: PanelResizeEdges
    ) -> (size: CGSize, center: CGPoint) {
        let minWidth: CGFloat = 190
        let maxWidth: CGFloat = 520
        let minHeight: CGFloat = 170
        let maxHeight: CGFloat = 420

        var left = startCenter.x - startSize.width / 2
        var right = startCenter.x + startSize.width / 2
        var top = startCenter.y - startSize.height / 2
        var bottom = startCenter.y + startSize.height / 2

        if edges.contains(.left) { left += translation.width }
        if edges.contains(.right) { right += translation.width }
        if edges.contains(.top) { top += translation.height }
        if edges.contains(.bottom) { bottom += translation.height }

        var width = right - left
        if width < minWidth {
            if edges.contains(.left) { left = right - minWidth } else { right = left + minWidth }
            width = minWidth
        } else if width > maxWidth {
            if edges.contains(.left) { left = right - maxWidth } else { right = left + maxWidth }
            width = maxWidth
        }

        var height = bottom - top
        if height < minHeight {
            if edges.contains(.top) { top = bottom - minHeight } else { bottom = top + minHeight }
            height = minHeight
        } else if height > maxHeight {
            if edges.contains(.top) { top = bottom - maxHeight } else { bottom = top + maxHeight }
            height = maxHeight
        }

        return (
            CGSize(width: width, height: height),
            CGPoint(x: (left + right) / 2, y: (top + bottom) / 2)
        )
    }

    private func initializePanelPositionIfNeeded(in geometry: GeometryProxy) {
        guard !hasInitializedPanelPosition else { return }
        panelCenter = CGPoint(
            x: geometry.size.width - panelSize.width / 2 - 12,
            y: geometry.size.height - panelSize.height / 2 - 12
        )
        hasInitializedPanelPosition = true
    }

    private func clampPanelPosition(to size: CGSize) {
        let halfWidth = panelSize.width / 2
        let halfHeight = panelSize.height / 2
        panelCenter.x = min(max(panelCenter.x, halfWidth + 8), size.width - halfWidth - 8)
        panelCenter.y = min(max(panelCenter.y, halfHeight + 8), size.height - halfHeight - 8)
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

    private func addNode(templateID: String? = nil) {
        let agent = appState.addNewAgent(templateID: templateID)
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
