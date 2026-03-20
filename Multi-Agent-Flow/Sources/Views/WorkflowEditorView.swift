//
//  WorkflowEditorView.swift
//  Multi-Agent-Flow
//
//  工作流编辑器 - 支持三种视图模式
//

import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct WorkflowEditorView: View {
    @EnvironmentObject var appState: AppState
    @Binding var zoomScale: CGFloat
    
    @State private var viewMode: EditorViewMode = .architecture
    @State private var selectedNodeID: UUID?
    @State private var selectedNodeIDs: Set<UUID> = []
    @State private var selectedEdgeID: UUID?
    @State private var selectedBoundaryIDs: Set<UUID> = []
    @State private var selectedAgentID: UUID?
    @State private var canvasOffset: CGSize = .zero
    @State private var canvasLastOffset: CGSize = .zero
    @State private var isConnectMode: Bool = false
    @State private var connectFromAgentID: UUID?
    @State private var isLassoMode: Bool = false
    @State private var copiedNodes: [WorkflowNode] = []
    @State private var copiedEdges: [WorkflowEdge] = []
    @State private var copiedBoundaries: [WorkflowBoundary] = []
    @State private var connectionType: ConnectionType = .bidirectional
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
            EditorToolbar(
                viewMode: $viewMode,
                scale: $zoomScale,
                offset: $canvasOffset,
                lastOffset: $canvasLastOffset,
                selectedNodeID: $selectedNodeID,
                selectedNodeIDs: $selectedNodeIDs,
                selectedEdgeID: $selectedEdgeID,
                selectedBoundaryIDs: $selectedBoundaryIDs,
                isRunning: isRunning,
                isConnectMode: $isConnectMode,
                isLassoMode: $isLassoMode,
                connectionType: $connectionType,
                connectFromAgentID: $connectFromAgentID,
                onAddNode: { addNode() },
                onAddNodeWithTemplate: { templateID in addNode(templateID: templateID) },
                onDeleteSelectedEdge: deleteSelectedEdge,
                onCopySelection: copySelection,
                onCutSelection: cutSelection,
                onPasteSelection: pasteSelection,
                onDeleteSelection: deleteSelection,
                onAddBoundary: addBoundaryFromSelection,
                onDeleteBoundary: deleteBoundaryFromSelection,
                onAlignSelected: alignSelectedElements,
                onDistributeSelected: distributeSelectedElements,
                onOrganizeConnections: organizeConnections,
                onGenerateTasks: generateTasksFromWorkflow,
                onRunTest: runTest,
                onStopTest: stopTest,
                onSave: { appState.saveProject() }
            )
            .zIndex(1000)
            .background(
                ZStack {
                    DeleteKeyMonitor(
                        isEnabled: { viewMode == .architecture },
                        onDelete: handleDeleteShortcut
                    )
                    WorkflowShortcutMonitor(
                        isEnabled: { viewMode == .architecture },
                        onCopy: copySelection,
                        onCut: cutSelection,
                        onPaste: pasteSelection,
                        onUndo: { appState.undoWorkflowChange() },
                        onRedo: { appState.redoWorkflowChange() },
                        onSelectAll: selectAllSelection
                    )
                }
            )
            
            Divider()
            
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
                        offset: $canvasOffset,
                        lastOffset: $canvasLastOffset,
                        isConnectMode: $isConnectMode,
                        connectFromAgentID: $connectFromAgentID,
                        connectionType: $connectionType,
                        selectedNodeID: $selectedNodeID,
                        selectedNodeIDs: $selectedNodeIDs,
                        selectedEdgeID: $selectedEdgeID,
                        selectedBoundaryIDs: $selectedBoundaryIDs,
                        isLassoMode: $isLassoMode,
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
        .onChange(of: viewMode) { _, newValue in
            if newValue != .architecture {
                isConnectMode = false
                connectFromAgentID = nil
                isLassoMode = false
            }
        }
    }
    
    private func handleAgentConnection(from: UUID, to: UUID) {
        let sourceNodeID = resolveNodeID(for: from, preferredIndex: 0)
        let targetNodeID = resolveNodeID(for: to, preferredIndex: 1)

        guard let sourceNodeID, let targetNodeID else {
            connectFromAgentID = nil
            return
        }

        guard sourceNodeID != targetNodeID else {
            connectFromAgentID = nil
            return
        }

        appState.connectNodes(from: sourceNodeID, to: targetNodeID, bidirectional: connectionType == .bidirectional)

        connectFromAgentID = nil
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

    private func currentWorkflow() -> Workflow? {
        appState.currentProject?.workflows.first
    }

    private func activeNodeSelection() -> Set<UUID> {
        if !selectedNodeIDs.isEmpty {
            return selectedNodeIDs
        }
        if let selectedNodeID {
            return [selectedNodeID]
        }
        return []
    }

    private func boundarySelectionContainsNodeIDs(_ boundary: WorkflowBoundary, selection: Set<UUID>) -> Bool {
        boundary.memberNodeIDs.allSatisfy { selection.contains($0) }
    }

    private func copySelection() {
        guard let workflow = currentWorkflow() else { return }
        let selection = activeNodeSelection()
        guard !selection.isEmpty else { return }

        copiedNodes = workflow.nodes.filter { selection.contains($0.id) }
        copiedEdges = workflow.edges.filter { selection.contains($0.fromNodeID) && selection.contains($0.toNodeID) }
        copiedBoundaries = workflow.boundaries.filter { selectedBoundaryIDs.contains($0.id) || boundarySelectionContainsNodeIDs($0, selection: selection) }
    }

    private func cutSelection() {
        copySelection()
        deleteSelection()
    }

    private func pasteSelection() {
        guard !copiedNodes.isEmpty else { return }

        let sourceAgentIDs = copiedNodes.compactMap(\.agentID)
        let duplicatedAgentIDs = appState.duplicateAgentsForWorkflowPaste(sourceAgentIDs)

        appState.updateMainWorkflow { workflow in
            var nodeIDMapping: [UUID: UUID] = [:]

            for sourceNode in copiedNodes {
                var newNode = WorkflowNode(type: sourceNode.type)
                if sourceNode.type == .agent {
                    guard let sourceAgentID = sourceNode.agentID,
                          let duplicatedAgentID = duplicatedAgentIDs[sourceAgentID] else {
                        continue
                    }
                    newNode.agentID = duplicatedAgentID
                } else {
                    newNode.agentID = sourceNode.agentID
                }
                newNode.position = CGPoint(x: sourceNode.position.x + 60, y: sourceNode.position.y + 60)
                newNode.title = sourceNode.title
                newNode.displayColorHex = sourceNode.displayColorHex
                newNode.conditionExpression = sourceNode.conditionExpression
                newNode.loopEnabled = sourceNode.loopEnabled
                newNode.maxIterations = sourceNode.maxIterations
                newNode.subflowID = sourceNode.subflowID
                newNode.nestingLevel = sourceNode.nestingLevel
                newNode.inputParameters = sourceNode.inputParameters
                newNode.outputParameters = sourceNode.outputParameters
                workflow.nodes.append(newNode)
                nodeIDMapping[sourceNode.id] = newNode.id
            }

            for sourceEdge in copiedEdges {
                guard let fromNodeID = nodeIDMapping[sourceEdge.fromNodeID],
                      let toNodeID = nodeIDMapping[sourceEdge.toNodeID] else { continue }

                var newEdge = WorkflowEdge(from: fromNodeID, to: toNodeID)
                newEdge.label = sourceEdge.label
                newEdge.displayColorHex = sourceEdge.displayColorHex
                newEdge.conditionExpression = sourceEdge.conditionExpression
                newEdge.requiresApproval = sourceEdge.requiresApproval
                newEdge.dataMapping = sourceEdge.dataMapping
                workflow.edges.append(newEdge)
            }

            for boundary in copiedBoundaries {
                let remappedMembers = boundary.memberNodeIDs.compactMap { nodeIDMapping[$0] }
                var newBoundary = WorkflowBoundary(
                    title: boundary.title,
                    rect: appState.snapRectToGrid(boundary.rect.offsetBy(dx: 60, dy: 60)),
                    memberNodeIDs: remappedMembers
                )
                newBoundary.createdAt = Date()
                newBoundary.updatedAt = Date()
                workflow.boundaries.append(newBoundary)
            }
        }
    }

    private func deleteSelection() {
        let nodeSelection = activeNodeSelection()
        if !nodeSelection.isEmpty {
            appState.removeNodes(nodeSelection)
        }
        if !selectedBoundaryIDs.isEmpty {
            appState.removeBoundaries(selectedBoundaryIDs)
        }
        if nodeSelection.isEmpty && selectedBoundaryIDs.isEmpty {
            return
        }
        selectedNodeID = nil
        selectedNodeIDs.removeAll()
        selectedEdgeID = nil
        selectedBoundaryIDs.removeAll()
    }

    private func deleteSelectedEdge() {
        guard let selectedEdgeID else { return }
        appState.removeEdge(selectedEdgeID)
        self.selectedEdgeID = nil
    }

    private func selectAllSelection() {
        guard let workflow = currentWorkflow() else { return }
        selectedNodeID = nil
        selectedNodeIDs = Set(workflow.nodes.map(\.id))
        selectedEdgeID = nil
        selectedBoundaryIDs = Set(workflow.boundaries.map(\.id))
    }

    private func handleDeleteShortcut() {
        if selectedEdgeID != nil, activeNodeSelection().isEmpty, selectedBoundaryIDs.isEmpty {
            deleteSelectedEdge()
        } else {
            deleteSelection()
        }
    }

    private func addNode(templateID: String? = nil) {
        let agent = appState.addNewAgent(templateID: templateID)
        guard let agent else { return }
        appState.addAgentNode(agentName: agent.name, position: CGPoint(x: 300, y: 200))
    }

    private func addBoundaryFromSelection() {
        let selection = activeNodeSelection()
        guard !selection.isEmpty else { return }
        appState.addBoundary(around: selection)
    }

    private func deleteBoundaryFromSelection() {
        if !selectedBoundaryIDs.isEmpty {
            appState.removeBoundaries(selectedBoundaryIDs)
            selectedBoundaryIDs.removeAll()
            return
        }
        let selection = activeNodeSelection()
        guard !selection.isEmpty else { return }
        appState.removeBoundary(around: selection)
    }

    private func alignSelectedElements(_ alignment: AlignmentAxis) {
        let nodeIDs = activeNodeSelection()
        if !nodeIDs.isEmpty {
            appState.updateMainWorkflow { workflow in
                applyNodeAlignment(alignment, in: &workflow, nodeIDs: nodeIDs)
            }
            return
        }

        if !selectedBoundaryIDs.isEmpty {
            appState.updateMainWorkflow { workflow in
                applyBoundaryAlignment(alignment, in: &workflow, boundaryIDs: selectedBoundaryIDs)
            }
        }
    }

    private func distributeSelectedElements(_ axis: DistributionAxis) {
        let nodeIDs = activeNodeSelection()
        if !nodeIDs.isEmpty {
            appState.updateMainWorkflow { workflow in
                applyNodeDistribution(axis, in: &workflow, nodeIDs: nodeIDs)
            }
            return
        }

        if !selectedBoundaryIDs.isEmpty {
            appState.updateMainWorkflow { workflow in
                applyBoundaryDistribution(axis, in: &workflow, boundaryIDs: selectedBoundaryIDs)
            }
        }
    }

    private func organizeConnections() {
        appState.updateMainWorkflow { workflow in
            workflow.edges.sort { lhs, rhs in
                let lhsKey = "\(lhs.requiresApproval ? 1 : 0)-\(lhs.toNodeID.uuidString)-\(lhs.fromNodeID.uuidString)"
                let rhsKey = "\(rhs.requiresApproval ? 1 : 0)-\(rhs.toNodeID.uuidString)-\(rhs.fromNodeID.uuidString)"
                return lhsKey < rhsKey
            }
        }
    }

    enum AlignmentAxis {
        case left, center, right, top, middle, bottom
    }

    enum DistributionAxis {
        case horizontal, vertical
    }

    private func applyNodeAlignment(_ alignment: AlignmentAxis, in workflow: inout Workflow, nodeIDs: Set<UUID>) {
        let indexes = workflow.nodes.indices.filter { nodeIDs.contains(workflow.nodes[$0].id) }
        guard !indexes.isEmpty else { return }

        switch alignment {
        case .left:
            let target = indexes.map { workflow.nodes[$0].position.x }.min() ?? 0
            for index in indexes {
                workflow.nodes[index].position.x = appState.snapPointToGrid(CGPoint(x: target, y: workflow.nodes[index].position.y)).x
            }
        case .center:
            let target = indexes.map { workflow.nodes[$0].position.x }.reduce(0, +) / CGFloat(indexes.count)
            for index in indexes {
                workflow.nodes[index].position.x = appState.snapPointToGrid(CGPoint(x: target, y: workflow.nodes[index].position.y)).x
            }
        case .right:
            let target = indexes.map { workflow.nodes[$0].position.x }.max() ?? 0
            for index in indexes {
                workflow.nodes[index].position.x = appState.snapPointToGrid(CGPoint(x: target, y: workflow.nodes[index].position.y)).x
            }
        case .top:
            let target = indexes.map { workflow.nodes[$0].position.y }.min() ?? 0
            for index in indexes {
                workflow.nodes[index].position.y = appState.snapPointToGrid(CGPoint(x: workflow.nodes[index].position.x, y: target)).y
            }
        case .middle:
            let target = indexes.map { workflow.nodes[$0].position.y }.reduce(0, +) / CGFloat(indexes.count)
            for index in indexes {
                workflow.nodes[index].position.y = appState.snapPointToGrid(CGPoint(x: workflow.nodes[index].position.x, y: target)).y
            }
        case .bottom:
            let target = indexes.map { workflow.nodes[$0].position.y }.max() ?? 0
            for index in indexes {
                workflow.nodes[index].position.y = appState.snapPointToGrid(CGPoint(x: workflow.nodes[index].position.x, y: target)).y
            }
        }
    }

    private func applyBoundaryAlignment(_ alignment: AlignmentAxis, in workflow: inout Workflow, boundaryIDs: Set<UUID>) {
        let indexes = workflow.boundaries.indices.filter { boundaryIDs.contains(workflow.boundaries[$0].id) }
        guard !indexes.isEmpty else { return }

        let rects = indexes.map { workflow.boundaries[$0].rect }
        switch alignment {
        case .left:
            let target = rects.map(\.minX).min() ?? 0
            for index in indexes {
                workflow.boundaries[index].rect.origin.x = target
            }
        case .center:
            let target = rects.map(\.midX).reduce(0, +) / CGFloat(rects.count)
            for index in indexes {
                let width = workflow.boundaries[index].rect.width
                workflow.boundaries[index].rect.origin.x = target - width / 2
            }
        case .right:
            let target = rects.map(\.maxX).max() ?? 0
            for index in indexes {
                let width = workflow.boundaries[index].rect.width
                workflow.boundaries[index].rect.origin.x = target - width
            }
        case .top:
            let target = rects.map(\.minY).min() ?? 0
            for index in indexes {
                workflow.boundaries[index].rect.origin.y = target
            }
        case .middle:
            let target = rects.map(\.midY).reduce(0, +) / CGFloat(rects.count)
            for index in indexes {
                let height = workflow.boundaries[index].rect.height
                workflow.boundaries[index].rect.origin.y = target - height / 2
            }
        case .bottom:
            let target = rects.map(\.maxY).max() ?? 0
            for index in indexes {
                let height = workflow.boundaries[index].rect.height
                workflow.boundaries[index].rect.origin.y = target - height
            }
        }
    }

    private func applyNodeDistribution(_ axis: DistributionAxis, in workflow: inout Workflow, nodeIDs: Set<UUID>) {
        let indexes = workflow.nodes.indices.filter { nodeIDs.contains(workflow.nodes[$0].id) }
        guard indexes.count > 2 else { return }

        let sorted = indexes.sorted {
            let lhs = workflow.nodes[$0].position
            let rhs = workflow.nodes[$1].position
            switch axis {
            case .horizontal: return lhs.x < rhs.x
            case .vertical: return lhs.y < rhs.y
            }
        }

        switch axis {
        case .horizontal:
            let positions = sorted.map { workflow.nodes[$0].position.x }.sorted()
            guard let minX = positions.first, let maxX = positions.last, maxX > minX else { return }
            let step = (maxX - minX) / CGFloat(sorted.count - 1)
            for (index, nodeIndex) in sorted.enumerated() {
                workflow.nodes[nodeIndex].position.x = minX + step * CGFloat(index)
            }
        case .vertical:
            let positions = sorted.map { workflow.nodes[$0].position.y }.sorted()
            guard let minY = positions.first, let maxY = positions.last, maxY > minY else { return }
            let step = (maxY - minY) / CGFloat(sorted.count - 1)
            for (index, nodeIndex) in sorted.enumerated() {
                workflow.nodes[nodeIndex].position.y = minY + step * CGFloat(index)
            }
        }
    }

    private func applyBoundaryDistribution(_ axis: DistributionAxis, in workflow: inout Workflow, boundaryIDs: Set<UUID>) {
        let indexes = workflow.boundaries.indices.filter { boundaryIDs.contains(workflow.boundaries[$0].id) }
        guard indexes.count > 2 else { return }

        let sorted = indexes.sorted {
            let lhs = workflow.boundaries[$0].rect
            let rhs = workflow.boundaries[$1].rect
            switch axis {
            case .horizontal: return lhs.midX < rhs.midX
            case .vertical: return lhs.midY < rhs.midY
            }
        }

        switch axis {
        case .horizontal:
            let positions = sorted.map { workflow.boundaries[$0].rect.midX }.sorted()
            guard let minX = positions.first, let maxX = positions.last, maxX > minX else { return }
            let step = (maxX - minX) / CGFloat(sorted.count - 1)
            for (index, boundaryIndex) in sorted.enumerated() {
                let width = workflow.boundaries[boundaryIndex].rect.width
                workflow.boundaries[boundaryIndex].rect.origin.x = minX + step * CGFloat(index) - width / 2
            }
        case .vertical:
            let positions = sorted.map { workflow.boundaries[$0].rect.midY }.sorted()
            guard let minY = positions.first, let maxY = positions.last, maxY > minY else { return }
            let step = (maxY - minY) / CGFloat(sorted.count - 1)
            for (index, boundaryIndex) in sorted.enumerated() {
                let height = workflow.boundaries[boundaryIndex].rect.height
                workflow.boundaries[boundaryIndex].rect.origin.y = minY + step * CGFloat(index) - height / 2
            }
        }
    }

    private func generateTasksFromWorkflow() {
        guard let workflow = currentWorkflow(),
              let agents = appState.currentProject?.agents else { return }
        appState.taskManager.generateTasks(from: workflow, projectAgents: agents)
    }

    private func simulateWorkflowExecution(workflow: Workflow, agents: [Agent]) {
        guard var execution = testExecution else { return }
        
        let agentNodes = appState.openClawService.executionPlan(for: workflow)
        
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

    private func resolveNodeID(for identifier: UUID, preferredIndex: Int) -> UUID? {
        guard let workflow = appState.currentProject?.workflows.first else { return nil }

        if workflow.nodes.contains(where: { $0.id == identifier }) {
            return identifier
        }

        if let node = workflow.nodes.first(where: { $0.agentID == identifier && $0.type == .agent }) {
            return node.id
        }

        let fallbackX: CGFloat = preferredIndex == 0 ? -180 : 180
        return appState.ensureAgentNode(agentID: identifier, suggestedPosition: CGPoint(x: fallbackX, y: 0))
    }
}

// MARK: - 工具栏
struct EditorToolbar: View {
    @EnvironmentObject var appState: AppState
    @Binding var viewMode: WorkflowEditorView.EditorViewMode
    @Binding var scale: CGFloat
    @Binding var offset: CGSize
    @Binding var lastOffset: CGSize
    @Binding var selectedNodeID: UUID?
    @Binding var selectedNodeIDs: Set<UUID>
    @Binding var selectedEdgeID: UUID?
    @Binding var selectedBoundaryIDs: Set<UUID>
    let isRunning: Bool
    @Binding var isConnectMode: Bool
    @Binding var isLassoMode: Bool
    @Binding var connectionType: WorkflowEditorView.ConnectionType
    @Binding var connectFromAgentID: UUID?
    var onAddNode: () -> Void
    var onAddNodeWithTemplate: (String?) -> Void
    var onDeleteSelectedEdge: () -> Void
    var onCopySelection: () -> Void
    var onCutSelection: () -> Void
    var onPasteSelection: () -> Void
    var onDeleteSelection: () -> Void
    var onAddBoundary: () -> Void
    var onDeleteBoundary: () -> Void
    var onAlignSelected: (WorkflowEditorView.AlignmentAxis) -> Void
    var onDistributeSelected: (WorkflowEditorView.DistributionAxis) -> Void
    var onOrganizeConnections: () -> Void
    var onGenerateTasks: () -> Void
    var onRunTest: () -> Void
    var onStopTest: () -> Void
    var onSave: () -> Void

    @State private var quickAddTemplateID: String = AgentTemplateCatalog.defaultTemplateID

    private var hasNodeSelection: Bool {
        selectedNodeID != nil || !selectedNodeIDs.isEmpty
    }

    private var hasBoundarySelection: Bool {
        !selectedBoundaryIDs.isEmpty
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            WorkflowToolbarGroup(title: "View") {
                HStack(spacing: 8) {
                    ForEach(WorkflowEditorView.EditorViewMode.allCases, id: \.self) { mode in
                        toolbarModeButton(mode)
                    }

                    Divider()
                        .frame(height: 24)
                        .padding(.horizontal, 2)

                    Menu {
                        Button("Zoom Out") { zoomOut() }
                        Button("Reset Zoom") { resetView() }
                        Button("Zoom In") { zoomIn() }
                    } label: {
                        toolbarMenuLabel(title: "Zoom", systemName: "eye")
                    }
                    .menuStyle(.borderlessButton)

                    toolbarIconToggleButton(
                        systemName: isLassoMode ? "rectangle.dashed.badge.checkmark" : "rectangle.dashed",
                        title: "Lasso",
                        action: toggleLassoMode,
                        isActive: isLassoMode,
                        tooltip: "框选模式"
                    )
                }
            }

            WorkflowToolbarGroup(title: "Execution") {
                HStack(spacing: 8) {
                    TemplatePickerButton(
                        selectedTemplateID: $quickAddTemplateID,
                        onSelect: { template in
                            onAddNodeWithTemplate(template.id)
                        },
                        labelTitle: "Add Node",
                        labelSystemImage: "plus.circle",
                        blankActionTitle: "New Blank Agent Node",
                        onCreateBlank: {
                            onAddNode()
                        },
                        existingAgents: appState.currentProject?.agents ?? [],
                        onSelectExistingAgent: { agent in
                            appState.addAgentNode(agentName: agent.name, position: CGPoint(x: 300, y: 200))
                        },
                        variant: .toolbar
                    )

                    Menu {
                        Button("Add Boundary") { onAddBoundary() }
                            .disabled(!hasNodeSelection)
                        Button("Remove Boundary") { onDeleteBoundary() }
                            .disabled(selectedBoundaryIDs.isEmpty && !hasNodeSelection)
                    } label: {
                        toolbarMenuLabel(title: "Insert", systemName: "plus.square.on.square")
                    }
                    .menuStyle(.borderlessButton)

                    Menu {
                        Button("Undo") { appState.undoWorkflowChange() }
                            .disabled(!appState.canUndoWorkflowChange)
                        Button("Redo") { appState.redoWorkflowChange() }
                            .disabled(!appState.canRedoWorkflowChange)
                        Divider()
                        Button("Copy") { onCopySelection() }.disabled(!hasNodeSelection)
                        Button("Cut") { onCutSelection() }.disabled(!hasNodeSelection)
                        Button("Paste") { onPasteSelection() }
                        Button("Select All") { selectAllItems() }
                        Button("Delete") { onDeleteSelection() }.disabled(!hasNodeSelection && selectedBoundaryIDs.isEmpty && selectedEdgeID == nil)
                    } label: {
                        toolbarMenuLabel(title: "Edit", systemName: "doc.on.doc")
                    }
                    .menuStyle(.borderlessButton)

                    Menu {
                        Button("Align Left") { onAlignSelected(.left) }
                            .disabled(!hasNodeSelection && !hasBoundarySelection)
                        Button("Align Center") { onAlignSelected(.center) }
                            .disabled(!hasNodeSelection && !hasBoundarySelection)
                        Button("Align Right") { onAlignSelected(.right) }
                            .disabled(!hasNodeSelection && !hasBoundarySelection)
                        Divider()
                        Button("Align Top") { onAlignSelected(.top) }
                            .disabled(!hasNodeSelection && !hasBoundarySelection)
                        Button("Align Middle") { onAlignSelected(.middle) }
                            .disabled(!hasNodeSelection && !hasBoundarySelection)
                        Button("Align Bottom") { onAlignSelected(.bottom) }
                            .disabled(!hasNodeSelection && !hasBoundarySelection)
                        Divider()
                        Button("Distribute Horizontally") { onDistributeSelected(.horizontal) }
                            .disabled((selectedNodeIDs.count + selectedBoundaryIDs.count) < 3)
                        Button("Distribute Vertically") { onDistributeSelected(.vertical) }
                            .disabled((selectedNodeIDs.count + selectedBoundaryIDs.count) < 3)
                        Divider()
                        Button("Organize Connections") { onOrganizeConnections() }
                        Button("Delete Selected Edge") { onDeleteSelectedEdge() }
                            .disabled(selectedEdgeID == nil)
                    } label: {
                        toolbarMenuLabel(title: "Layout", systemName: "rectangle.3.group")
                    }
                    .menuStyle(.borderlessButton)

                    toolbarIconToggleButton(
                        systemName: isConnectMode ? "link.circle.fill" : "link.circle",
                        title: "Connect",
                        action: toggleConnectMode,
                        isActive: isConnectMode,
                        tooltip: isConnectMode ? "取消创建连线" : "准备创建连线",
                        prominent: true
                    )

                    if isConnectMode {
                        connectionTypeButton(type: .unidirectional)
                        connectionTypeButton(type: .bidirectional)
                    }

                    toolbarIconButton(
                        systemName: "list.bullet.clipboard",
                        title: "Tasks",
                        action: onGenerateTasks,
                        tooltip: "生成任务"
                    )

                    Button(action: isRunning ? onStopTest : onRunTest) {
                        HStack(spacing: 8) {
                            Image(systemName: isRunning ? "stop.circle" : "play.circle")
                                .font(.system(size: 15, weight: .semibold))
                            Text(isRunning ? "Stop" : "Run")
                                .font(.system(size: 12.5, weight: .semibold))
                                .lineLimit(1)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .frame(minWidth: 84)
                        .frame(height: 38)
                        .fixedSize(horizontal: true, vertical: false)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(isRunning ? Color.red : Color.accentColor)
                        )
                    }
                    .buttonStyle(.plain)
                    .help(isRunning ? "停止测试" : "运行测试")

                    toolbarIconButton(
                        systemName: "square.and.arrow.down",
                        title: "Save",
                        action: onSave,
                        tooltip: "保存"
                    )
                }
            }

            if hasNodeSelection || selectedEdgeID != nil {
                WorkflowToolbarGroup(title: "Style") {
                    HStack(spacing: 8) {
                        if hasNodeSelection {
                            Menu {
                                ForEach(CanvasAccentColorPreset.allCases) { preset in
                                    Button {
                                        applyNodeColor(preset.hex)
                                    } label: {
                                        styleMenuLabel(title: preset.title, color: preset.color)
                                    }
                                }
                                Divider()
                                Button(action: {
                                    applyNodeColor(nil)
                                }) {
                                    styleMenuResetLabel(title: "恢复节点默认色")
                                }
                            } label: {
                                toolbarMenuLabel(title: "节点颜色", systemName: "paintpalette")
                            }
                            .menuStyle(.borderlessButton)
                        }

                        if let selectedEdgeID {
                            Menu {
                                ForEach(CanvasAccentColorPreset.allCases) { preset in
                                    Button {
                                        applyEdgeColor(preset.hex, edgeID: selectedEdgeID)
                                    } label: {
                                        styleMenuLabel(title: preset.title, color: preset.color)
                                    }
                                }
                                Divider()
                                Button(action: {
                                    applyEdgeColor(nil, edgeID: selectedEdgeID)
                                }) {
                                    styleMenuResetLabel(title: "恢复连线默认色")
                                }
                            } label: {
                                toolbarMenuLabel(title: "连线颜色", systemName: "scribble.variable")
                            }
                            .menuStyle(.borderlessButton)
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            if appState.isAutoSaving || appState.lastAutoSaveTime != nil {
                toolbarSaveStatusView
                    .padding(.top, 8)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.98), Color(red: 0.968, green: 0.972, blue: 0.985)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private func toolbarModeButton(_ mode: WorkflowEditorView.EditorViewMode) -> some View {
        Button(action: { viewMode = mode }) {
            HStack(spacing: 8) {
                Image(systemName: mode.icon)
                    .font(.system(size: 14, weight: .semibold))
                Text(mode == .architecture ? "Flow" : mode.rawValue)
                    .font(.system(size: 12.5, weight: .semibold))
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .frame(minWidth: 74)
        }
        .buttonStyle(.plain)
        .foregroundColor(viewMode == mode ? .white : Color.primary.opacity(0.76))
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(viewMode == mode ? Color.accentColor : Color.black.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(viewMode == mode ? Color.accentColor.opacity(0.1) : Color.black.opacity(0.06), lineWidth: 1)
        )
        .help(mode.rawValue)
    }

    private func toolbarMenuLabel(title: String, systemName: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
            Text(title)
                .font(.system(size: 12.5, weight: .semibold))
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)
        }
        .foregroundColor(Color.primary.opacity(0.82))
        .padding(.horizontal, 12)
        .frame(height: 38)
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

    private func selectAllItems() {
        guard let workflow = appState.currentProject?.workflows.first else { return }
        selectedNodeID = nil
        selectedNodeIDs = Set(workflow.nodes.map(\.id))
        selectedBoundaryIDs = Set(workflow.boundaries.map(\.id))
        selectedEdgeID = nil
    }

    private func activeNodeSelection() -> Set<UUID> {
        if !selectedNodeIDs.isEmpty {
            return selectedNodeIDs
        }
        if let selectedNodeID {
            return [selectedNodeID]
        }
        return []
    }

    private func applyNodeColor(_ colorHex: String?) {
        appState.setNodeColor(colorHex, for: activeNodeSelection())
    }

    private func applyEdgeColor(_ colorHex: String?, edgeID: UUID) {
        appState.setEdgeColor(colorHex, for: [edgeID])
    }

    private func styleMenuLabel(title: String, color: Color) -> some View {
        Label {
            Text(title)
                .font(.system(size: 12.5, weight: .medium))
                .lineLimit(1)
        } icon: {
            Image(nsImage: menuSwatchImage(color: NSColor(color)))
                .renderingMode(.original)
        }
    }

    private func styleMenuResetLabel(title: String) -> some View {
        Label {
            Text(title)
                .font(.system(size: 12.5, weight: .medium))
                .lineLimit(1)
        } icon: {
            Image(nsImage: menuResetSwatchImage())
                .renderingMode(.original)
        }
    }

    private func menuSwatchImage(color: NSColor) -> NSImage {
        let size = NSSize(width: 14, height: 14)
        let image = NSImage(size: size)
        image.lockFocus()

        let rect = NSRect(origin: .zero, size: size)
        let path = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 3, yRadius: 3)
        color.setFill()
        path.fill()

        NSColor.black.withAlphaComponent(0.12).setStroke()
        path.lineWidth = 1
        path.stroke()

        image.unlockFocus()
        return image
    }

    private func menuResetSwatchImage() -> NSImage {
        let size = NSSize(width: 14, height: 14)
        let image = NSImage(size: size)
        image.lockFocus()

        let rect = NSRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)
        NSColor.clear.setFill()
        path.fill()

        NSColor.secondaryLabelColor.withAlphaComponent(0.55).setStroke()
        path.setLineDash([3, 2], count: 2, phase: 0)
        path.lineWidth = 1
        path.stroke()
        path.setLineDash([], count: 0, phase: 0)

        let slash = NSBezierPath()
        slash.move(to: NSPoint(x: 3.5, y: 3.5))
        slash.line(to: NSPoint(x: 10.5, y: 10.5))
        NSColor.secondaryLabelColor.setStroke()
        slash.lineWidth = 1.4
        slash.lineCapStyle = .round
        slash.stroke()

        image.unlockFocus()
        return image
    }

    private func toolbarIconButton(
        systemName: String,
        title: String? = nil,
        action: @escaping () -> Void,
        tooltip: String
    ) -> some View {
        Button(action: action) {
            toolbarActionLabel(
                systemName: systemName,
                title: title,
                isActive: false,
                prominent: false
            )
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }

    private func toolbarIconToggleButton(
        systemName: String,
        title: String? = nil,
        action: @escaping () -> Void,
        isActive: Bool,
        tooltip: String,
        prominent: Bool = false
    ) -> some View {
        Button(action: action) {
            toolbarActionLabel(
                systemName: systemName,
                title: title,
                isActive: isActive,
                prominent: prominent
            )
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }

    private func connectionTypeButton(type: WorkflowEditorView.ConnectionType) -> some View {
        let icon = type == .unidirectional ? "arrow.right" : "arrow.left.arrow.right"
        let isActive = connectionType == type
        return Button(action: {
            connectionType = type
            isConnectMode = true
        }) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13.5, weight: .semibold))
                Text(type == .unidirectional ? "One-way" : "Two-way")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(isActive ? .white : Color.primary.opacity(0.76))
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isActive ? Color.accentColor : Color.black.opacity(0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isActive ? Color.accentColor.opacity(0.1) : Color.black.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help(type.description)
    }

    private func toolbarActionLabel(
        systemName: String,
        title: String?,
        isActive: Bool,
        prominent: Bool
    ) -> some View {
        let useAccent = prominent || isActive
        return HStack(spacing: 8) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
            if let title {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)
            }
        }
        .foregroundColor(useAccent ? .white : Color.primary.opacity(0.82))
        .padding(.horizontal, title == nil ? 0 : 14)
        .frame(width: title == nil ? 40 : nil, height: 38)
        .fixedSize(horizontal: true, vertical: false)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(useAccent ? Color.accentColor : Color.black.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(useAccent ? Color.accentColor.opacity(0.12) : Color.black.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: useAccent ? Color.accentColor.opacity(0.16) : .clear, radius: 6, x: 0, y: 2)
    }

    @ViewBuilder
    private var toolbarSaveStatusView: some View {
        if appState.isAutoSaving {
            HStack(spacing: 6) {
                ProgressView()
                    .scaleEffect(0.65)
                Text(LocalizedString.saving)
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundColor(.secondary)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.82))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )
        } else if let lastSave = appState.lastAutoSaveTime {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Saved \(lastSave.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.82))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )
        }
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

    private func resetView() {
        withAnimation(.easeInOut(duration: 0.3)) {
            scale = 1.0
            offset = .zero
            lastOffset = .zero
        }
    }

    private func toggleConnectMode() {
        withAnimation(.easeInOut(duration: 0.15)) {
            isConnectMode.toggle()
            if isConnectMode {
                isLassoMode = false
            } else {
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
}

private struct DeleteKeyMonitor: NSViewRepresentable {
    var isEnabled: () -> Bool
    var onDelete: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(isEnabled: isEnabled, onDelete: onDelete)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.isEnabled = isEnabled
        context.coordinator.onDelete = onDelete
        context.coordinator.attach(to: nsView)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator {
        var isEnabled: () -> Bool
        var onDelete: () -> Void

        private weak var view: NSView?
        private var monitor: Any?

        init(isEnabled: @escaping () -> Bool, onDelete: @escaping () -> Void) {
            self.isEnabled = isEnabled
            self.onDelete = onDelete
        }

        func attach(to view: NSView) {
            self.view = view
            guard monitor == nil else { return }

            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
                guard let self, let view = self.view, view.window != nil else { return event }
                guard self.isEnabled() else { return event }
                guard event.keyCode == 51 || event.keyCode == 117 else { return event }
                if view.window?.firstResponder is NSTextView {
                    return event
                }

                self.onDelete()
                return nil
            }
        }

        func detach() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
        }
    }
}

private struct WorkflowShortcutMonitor: NSViewRepresentable {
    var isEnabled: () -> Bool
    var onCopy: () -> Void
    var onCut: () -> Void
    var onPaste: () -> Void
    var onUndo: () -> Void
    var onRedo: () -> Void
    var onSelectAll: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            isEnabled: isEnabled,
            onCopy: onCopy,
            onCut: onCut,
            onPaste: onPaste,
            onUndo: onUndo,
            onRedo: onRedo,
            onSelectAll: onSelectAll
        )
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.isEnabled = isEnabled
        context.coordinator.onCopy = onCopy
        context.coordinator.onCut = onCut
        context.coordinator.onPaste = onPaste
        context.coordinator.onUndo = onUndo
        context.coordinator.onRedo = onRedo
        context.coordinator.onSelectAll = onSelectAll
        context.coordinator.attach(to: nsView)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator {
        var isEnabled: () -> Bool
        var onCopy: () -> Void
        var onCut: () -> Void
        var onPaste: () -> Void
        var onUndo: () -> Void
        var onRedo: () -> Void
        var onSelectAll: () -> Void

        private weak var view: NSView?
        private var monitor: Any?

        init(
            isEnabled: @escaping () -> Bool,
            onCopy: @escaping () -> Void,
            onCut: @escaping () -> Void,
            onPaste: @escaping () -> Void,
            onUndo: @escaping () -> Void,
            onRedo: @escaping () -> Void,
            onSelectAll: @escaping () -> Void
        ) {
            self.isEnabled = isEnabled
            self.onCopy = onCopy
            self.onCut = onCut
            self.onPaste = onPaste
            self.onUndo = onUndo
            self.onRedo = onRedo
            self.onSelectAll = onSelectAll
        }

        func attach(to view: NSView) {
            self.view = view
            guard monitor == nil else { return }

            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
                guard let self, let view = self.view, view.window != nil else { return event }
                guard self.isEnabled() else { return event }
                guard !(view.window?.firstResponder is NSTextView) else { return event }

                let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
                guard modifiers.contains(.command) else { return event }
                guard let characters = event.charactersIgnoringModifiers?.lowercased() else { return event }

                switch (characters, modifiers.contains(.shift), modifiers.contains(.option), modifiers.contains(.control)) {
                case ("c", false, false, false):
                    self.onCopy()
                    return nil
                case ("x", false, false, false):
                    self.onCut()
                    return nil
                case ("v", false, false, false):
                    self.onPaste()
                    return nil
                case ("z", false, false, false):
                    self.onUndo()
                    return nil
                case ("z", true, false, false):
                    self.onRedo()
                    return nil
                case ("a", false, false, false):
                    self.onSelectAll()
                    return nil
                default:
                    return event
                }
            }
        }

        func detach() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
        }
    }
}

private struct WorkflowToolbarGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color.primary.opacity(0.38))
                .tracking(0.8)

            content
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(minHeight: 96, alignment: .topLeading)
        .fixedSize(horizontal: true, vertical: false)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.86))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 2)
    }
}

private enum AgentCollectionSort: String, CaseIterable, Identifiable {
    case updated = "Recently Updated"
    case name = "Name"
    case model = "Model"
    case connections = "Connections"

    var id: String { rawValue }
}

private enum AgentCollectionFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case onCanvas = "On Canvas"
    case withSoulFile = "With SOUL"
    case attention = "Needs Attention"

    var id: String { rawValue }
}

private struct AgentCollectionItem: Identifiable {
    let agent: Agent
    let nodeID: UUID?
    let soulSourcePath: String?
    let statusLabel: String
    let statusSystemImage: String
    let statusColor: Color
    let statusIsProblem: Bool
    let incomingConnections: Int
    let outgoingConnections: Int

    var id: UUID { agent.id }
    var totalConnections: Int { incomingConnections + outgoingConnections }
    var hasSoulFile: Bool { soulSourcePath != nil }
    var isOnCanvas: Bool { nodeID != nil }
    var soulDisplayName: String { soulSourcePath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Project Cache" }
    var soulDirectoryName: String? { soulSourcePath.map { URL(fileURLWithPath: $0).deletingLastPathComponent().lastPathComponent } }
}

private struct AgentCollectionSnapshot {
    let items: [AgentCollectionItem]
    let onCanvasCount: Int
    let withSoulCount: Int
    let attentionCount: Int

    static let empty = AgentCollectionSnapshot(
        items: [],
        onCanvasCount: 0,
        withSoulCount: 0,
        attentionCount: 0
    )
}

private struct AgentCollectionSignature: Equatable {
    let projectID: UUID?
    let projectUpdatedAt: Date?
    let runtimeUpdatedAt: Date?
    let agentCount: Int
    let nodeCount: Int
    let edgeCount: Int
}

private struct AgentActionFeedback: Identifiable {
    let id = UUID()
    let message: String
    let isError: Bool
}

private func makeAgentCollectionSignature(project: MAProject?) -> AgentCollectionSignature {
    let workflow = project?.workflows.first

    return AgentCollectionSignature(
        projectID: project?.id,
        projectUpdatedAt: project?.updatedAt,
        runtimeUpdatedAt: project?.runtimeState.lastUpdated,
        agentCount: project?.agents.count ?? 0,
        nodeCount: workflow?.nodes.count ?? 0,
        edgeCount: workflow?.edges.count ?? 0
    )
}

private func makeAgentCollectionSnapshot(appState: AppState) -> AgentCollectionSnapshot {
    guard let project = appState.currentProject else { return .empty }

    let workflow = project.workflows.first
    let nodes = workflow?.nodes ?? []
    let edges = workflow?.edges ?? []

    var nodeIDsByAgentID: [UUID: UUID] = [:]
    for node in nodes where node.type == .agent {
        guard let agentID = node.agentID, nodeIDsByAgentID[agentID] == nil else { continue }
        nodeIDsByAgentID[agentID] = node.id
    }

    var incomingCounts: [UUID: Int] = [:]
    var outgoingCounts: [UUID: Int] = [:]
    for edge in edges {
        outgoingCounts[edge.fromNodeID, default: 0] += 1
        incomingCounts[edge.toNodeID, default: 0] += 1
    }

    let items = project.agents.map { agent in
        let nodeID = nodeIDsByAgentID[agent.id]
        let soulPath = appState.agentSoulFileURL(for: agent.id)?.path
        let rawStatus = project.runtimeState.agentStates[agent.id.uuidString]
        let status = runtimePresentation(for: rawStatus)

        return AgentCollectionItem(
            agent: agent,
            nodeID: nodeID,
            soulSourcePath: soulPath,
            statusLabel: status.label,
            statusSystemImage: status.systemImage,
            statusColor: status.color,
            statusIsProblem: status.isProblem,
            incomingConnections: nodeID.flatMap { incomingCounts[$0] } ?? 0,
            outgoingConnections: nodeID.flatMap { outgoingCounts[$0] } ?? 0
        )
    }

    let counts = items.reduce(into: (onCanvas: 0, withSoul: 0, attention: 0)) { result, item in
        if item.isOnCanvas {
            result.onCanvas += 1
        }
        if item.hasSoulFile {
            result.withSoul += 1
        }
        if !item.hasSoulFile || !item.isOnCanvas || item.statusIsProblem {
            result.attention += 1
        }
    }

    return AgentCollectionSnapshot(
        items: items,
        onCanvasCount: counts.onCanvas,
        withSoulCount: counts.withSoul,
        attentionCount: counts.attention
    )
}

private func runtimePresentation(for rawStatus: String?) -> (label: String, systemImage: String, color: Color, isProblem: Bool) {
    let status = rawStatus?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""

    switch status {
    case "", "idle", "ready":
        return ("Ready", "checkmark.circle.fill", .green, false)
    case "running":
        return ("Running", "bolt.circle.fill", .blue, false)
    case "reloaded":
        return ("Reloaded", "arrow.clockwise.circle.fill", .green, false)
    case "reload_failed", "error", "failed":
        return ("Needs Reload", "exclamationmark.triangle.fill", .orange, true)
    case "stopped":
        return ("Stopped", "pause.circle.fill", .secondary, true)
    default:
        return (status.capitalized, "circle.fill", .secondary, false)
    }
}

private func filterAgentItems(
    _ items: [AgentCollectionItem],
    searchText: String,
    filter: AgentCollectionFilter,
    sort: AgentCollectionSort
) -> [AgentCollectionItem] {
    let trimmedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

    let filtered = items.filter { item in
        let matchesFilter: Bool
        switch filter {
        case .all:
            matchesFilter = true
        case .onCanvas:
            matchesFilter = item.isOnCanvas
        case .withSoulFile:
            matchesFilter = item.hasSoulFile
        case .attention:
            matchesFilter = !item.hasSoulFile || !item.isOnCanvas || item.statusIsProblem
        }

        guard matchesFilter else { return false }
        guard !trimmedSearchText.isEmpty else { return true }

        let searchableText = [
            item.agent.name,
            item.agent.identity,
            item.agent.description,
            item.agent.openClawDefinition.modelIdentifier,
            item.agent.openClawDefinition.runtimeProfile,
            item.soulSourcePath,
            item.agent.capabilities.joined(separator: " ")
        ]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")

        return searchableText.contains(trimmedSearchText)
    }

    return filtered.sorted { lhs, rhs in
        switch sort {
        case .updated:
            if lhs.agent.updatedAt != rhs.agent.updatedAt {
                return lhs.agent.updatedAt > rhs.agent.updatedAt
            }
            return lhs.agent.name.localizedCaseInsensitiveCompare(rhs.agent.name) == .orderedAscending
        case .name:
            return lhs.agent.name.localizedCaseInsensitiveCompare(rhs.agent.name) == .orderedAscending
        case .model:
            let lhsModel = lhs.agent.openClawDefinition.modelIdentifier
            let rhsModel = rhs.agent.openClawDefinition.modelIdentifier
            if lhsModel != rhsModel {
                return lhsModel.localizedCaseInsensitiveCompare(rhsModel) == .orderedAscending
            }
            return lhs.agent.name.localizedCaseInsensitiveCompare(rhs.agent.name) == .orderedAscending
        case .connections:
            if lhs.totalConnections != rhs.totalConnections {
                return lhs.totalConnections > rhs.totalConnections
            }
            return lhs.agent.name.localizedCaseInsensitiveCompare(rhs.agent.name) == .orderedAscending
        }
    }
}

private struct AgentCollectionToolbar: View {
    @Binding var searchText: String
    @Binding var filter: AgentCollectionFilter
    @Binding var sort: AgentCollectionSort
    let snapshot: AgentCollectionSnapshot
    let visibleCount: Int
    let feedback: AgentActionFeedback?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search agents, models, identities, skills or SOUL paths", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color(.controlBackgroundColor))
                .cornerRadius(10)

                Picker("Filter", selection: $filter) {
                    ForEach(AgentCollectionFilter.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.menu)

                Picker("Sort", selection: $sort) {
                    ForEach(AgentCollectionSort.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.menu)
            }

            HStack(spacing: 8) {
                AgentCollectionBadge(systemImage: "person.3.fill", text: "\(visibleCount)/\(snapshot.items.count) visible")
                AgentCollectionBadge(systemImage: "square.grid.2x2", text: "\(snapshot.onCanvasCount) on canvas")
                AgentCollectionBadge(systemImage: "doc.text.fill", text: "\(snapshot.withSoulCount) with SOUL")
                AgentCollectionBadge(systemImage: "exclamationmark.triangle.fill", text: "\(snapshot.attentionCount) need attention")
            }

            if let feedback {
                HStack(spacing: 8) {
                    Image(systemName: feedback.isError ? "xmark.octagon.fill" : "checkmark.circle.fill")
                    Text(feedback.message)
                        .lineLimit(2)
                }
                .font(.caption)
                .foregroundColor(feedback.isError ? .red : .green)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(Color(.windowBackgroundColor))
    }
}

private struct AgentCollectionBadge: View {
    let systemImage: String
    let text: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(.controlBackgroundColor))
            .cornerRadius(999)
    }
}

private struct AgentCollectionEmptyState: View {
    let searchText: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 28))
                .foregroundColor(.secondary)
            Text("No agents match the current filter")
                .font(.headline)
            if !searchText.isEmpty {
                Text("Try clearing or adjusting the search keywords.")
                    .foregroundColor(.secondary)
            } else {
                Text("The current project has no agents in this category.")
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}

private struct AgentStatusPill: View {
    let label: String
    let systemImage: String
    let color: Color

    var body: some View {
        Label(label, systemImage: systemImage)
            .font(.caption)
            .foregroundColor(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.12))
            .cornerRadius(999)
    }
}

private struct AgentContextMenuContent: View {
    let item: AgentCollectionItem
    let canPaste: Bool
    var onOpen: () -> Void
    var onRevealSoul: () -> Void
    var onOpenWorkspace: () -> Void
    var onReloadSoul: () -> Void
    var onEdit: () -> Void
    var onManageSkills: () -> Void
    var onConfigurePermissions: () -> Void
    var onCopy: () -> Void
    var onCut: () -> Void
    var onPaste: () -> Void
    var onDuplicate: () -> Void
    var onExport: () -> Void
    var onReset: () -> Void
    var onDelete: () -> Void

    var body: some View {
        Button(action: onOpen) {
            Label("Focus Agent", systemImage: "scope")
        }

        Button(action: onEdit) {
            Label("Edit SOUL.md", systemImage: "pencil.and.outline")
        }

        Button(action: onRevealSoul) {
            Label(item.hasSoulFile ? "Reveal SOUL.md" : "Reveal Expected SOUL Location", systemImage: "doc.text.magnifyingglass")
        }

        Button(action: onOpenWorkspace) {
            Label("Open Workspace", systemImage: "folder")
        }

        Button(action: onReloadSoul) {
            Label("Reload SOUL from Disk", systemImage: "arrow.clockwise")
        }

        Divider()

        Button(action: onManageSkills) {
            Label("Manage Skills", systemImage: "star")
        }

        Button(action: onConfigurePermissions) {
            Label("Configure Permissions", systemImage: "lock.shield")
        }

        Divider()

        Button(action: onCopy) {
            Label("Copy", systemImage: "doc.on.doc")
        }

        Button(action: onCut) {
            Label("Cut", systemImage: "scissors")
        }

        Button(action: onPaste) {
            Label("Paste", systemImage: "doc.on.clipboard")
        }
        .disabled(!canPaste)

        Button(action: onDuplicate) {
            Label("Duplicate", systemImage: "plus.square.on.square")
        }

        Button(action: onExport) {
            Label("Export", systemImage: "square.and.arrow.up")
        }

        Button(action: onReset) {
            Label("Reset", systemImage: "arrow.counterclockwise")
        }

        Divider()

        Button(role: .destructive, action: onDelete) {
            Label("Delete", systemImage: "trash")
        }
    }
}

// MARK: - 列表视图
struct AgentListView: View {
    @EnvironmentObject var appState: AppState
    @Binding var selectedAgentID: UUID?
    var isConnectMode: Bool
    var connectFromAgentID: UUID?
    var onConnect: (UUID, UUID) -> Void

    @State private var searchText = ""
    @State private var filter: AgentCollectionFilter = .all
    @State private var sort: AgentCollectionSort = .updated
    @State private var editingAgent: Agent?
    @State private var skillsAgent: Agent?
    @State private var permissionsAgent: Agent?
    @State private var deleteCandidate: Agent?
    @State private var feedback: AgentActionFeedback?
    @State private var collectionSnapshot: AgentCollectionSnapshot = .empty

    private var items: [AgentCollectionItem] {
        collectionSnapshot.items
    }

    private var visibleItems: [AgentCollectionItem] {
        filterAgentItems(items, searchText: searchText, filter: filter, sort: sort)
    }

    private var collectionSignature: AgentCollectionSignature {
        makeAgentCollectionSignature(project: appState.currentProject)
    }

    var body: some View {
        VStack(spacing: 0) {
            AgentCollectionToolbar(
                searchText: $searchText,
                filter: $filter,
                sort: $sort,
                snapshot: collectionSnapshot,
                visibleCount: visibleItems.count,
                feedback: feedback
            )

            Divider()

            if visibleItems.isEmpty {
                AgentCollectionEmptyState(searchText: searchText)
            } else {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Text("Status").frame(width: 120, alignment: .leading)
                        Text("Agent").frame(minWidth: 220, alignment: .leading)
                        Text("Model").frame(minWidth: 170, alignment: .leading)
                        Text("Connections").frame(width: 110, alignment: .leading)
                        Text("SOUL").frame(minWidth: 170, alignment: .leading)
                        Text("Actions").frame(width: isConnectMode ? 210 : 180, alignment: .center)
                        Spacer(minLength: 0)
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(.controlBackgroundColor))

                    List {
                        ForEach(visibleItems) { item in
                            AgentListRow(
                                item: item,
                                isSelected: selectedAgentID == item.agent.id,
                                isConnectMode: isConnectMode,
                                isConnectSource: connectFromAgentID == item.agent.id,
                                onSelect: { selectAgent(item.agent.id, focusNode: false) },
                                onOpen: { selectAgent(item.agent.id, focusNode: true) },
                                onEdit: { beginEditing(item.agent.id) },
                                onRevealSoul: { revealSoul(for: item.agent.id) },
                                onDuplicate: { duplicateAgent(item.agent.id) },
                                onDelete: { deleteCandidate = currentAgent(id: item.agent.id) ?? item.agent },
                                onConnect: { targetID in connect(sourceID: connectFromAgentID, targetID: targetID) }
                            )
                            .contextMenu {
                                AgentContextMenuContent(
                                    item: item,
                                    canPaste: NSPasteboard.general.canReadObject(forClasses: [NSString.self], options: nil),
                                    onOpen: { selectAgent(item.agent.id, focusNode: true) },
                                    onRevealSoul: { revealSoul(for: item.agent.id) },
                                    onOpenWorkspace: { openWorkspace(for: item.agent.id) },
                                    onReloadSoul: { reloadSoul(for: item.agent.id) },
                                    onEdit: { beginEditing(item.agent.id) },
                                    onManageSkills: { skillsAgent = currentAgent(id: item.agent.id) ?? item.agent },
                                    onConfigurePermissions: { permissionsAgent = currentAgent(id: item.agent.id) ?? item.agent },
                                    onCopy: { copyAgent(item.agent.id) },
                                    onCut: { cutAgent(item.agent.id) },
                                    onPaste: pasteAgent,
                                    onDuplicate: { duplicateAgent(item.agent.id) },
                                    onExport: { export(agentID: item.agent.id) },
                                    onReset: { resetAgent(item.agent.id) },
                                    onDelete: { deleteCandidate = currentAgent(id: item.agent.id) ?? item.agent }
                                )
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
        }
        .sheet(item: $editingAgent) { agent in
            AgentEditSheet(agent: agent, isPresented: bindingForAgentSheet($editingAgent))
        }
        .sheet(item: $skillsAgent) { agent in
            SkillsManagementSheet(agent: agent, isPresented: bindingForAgentSheet($skillsAgent))
        }
        .sheet(item: $permissionsAgent) { agent in
            PermissionsConfigSheet(agent: agent, isPresented: bindingForAgentSheet($permissionsAgent))
        }
        .alert("Delete Agent?", isPresented: deleteConfirmationBinding) {
            Button("Delete", role: .destructive) {
                if let candidate = deleteCandidate {
                    appState.deleteAgent(candidate.id)
                    if selectedAgentID == candidate.id {
                        selectedAgentID = nil
                    }
                    showFeedback("Deleted \(candidate.name)", isError: false)
                }
                deleteCandidate = nil
            }
            Button("Cancel", role: .cancel) {
                deleteCandidate = nil
            }
        } message: {
            Text(deleteCandidate.map { "Delete \"\($0.name)\" and remove its workflow node references?" } ?? "")
        }
        .onAppear(perform: refreshCollectionSnapshot)
        .onChange(of: collectionSignature) { _, _ in
            refreshCollectionSnapshot()
        }
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { deleteCandidate != nil },
            set: { if !$0 { deleteCandidate = nil } }
        )
    }

    private func bindingForAgentSheet(_ item: Binding<Agent?>) -> Binding<Bool> {
        Binding(
            get: { item.wrappedValue != nil },
            set: { if !$0 { item.wrappedValue = nil } }
        )
    }

    private func currentAgent(id: UUID) -> Agent? {
        appState.currentProject?.agents.first(where: { $0.id == id })
    }

    private func selectAgent(_ agentID: UUID, focusNode: Bool) {
        selectedAgentID = agentID
        if focusNode {
            _ = appState.focusAgentNode(agentID: agentID, createIfMissing: true, suggestedPosition: .zero)
        }
    }

    private func beginEditing(_ agentID: UUID) {
        guard let agent = currentAgent(id: agentID) else { return }
        selectAgent(agentID, focusNode: false)
        editingAgent = agent
    }

    private func connect(sourceID: UUID?, targetID: UUID) {
        guard let sourceID else { return }
        onConnect(sourceID, targetID)
    }

    private func revealSoul(for agentID: UUID) {
        if let soulURL = appState.agentSoulFileURL(for: agentID) {
            NSWorkspace.shared.activateFileViewerSelecting([soulURL])
            showFeedback("Revealed \(soulURL.lastPathComponent)", isError: false)
        } else {
            showFeedback("No real SOUL.md file was found for this agent.", isError: true)
        }
    }

    private func openWorkspace(for agentID: UUID) {
        if let workspaceURL = appState.agentWorkspaceURL(for: agentID) {
            NSWorkspace.shared.open(workspaceURL)
            showFeedback("Opened workspace \(workspaceURL.lastPathComponent)", isError: false)
        } else {
            showFeedback("No workspace directory was found for this agent.", isError: true)
        }
    }

    private func reloadSoul(for agentID: UUID) {
        let result = appState.refreshAgentSoulMDFromSource(agentID: agentID)
        showFeedback(result.message, isError: !result.success)
        if result.success, editingAgent?.id == agentID {
            editingAgent = currentAgent(id: agentID)
        }
    }

    private func copyAgent(_ agentID: UUID) {
        guard let agent = currentAgent(id: agentID) else { return }
        let success = appState.copyAgent(agent)
        showFeedback(success ? "Copied \(agent.name)" : "Copy failed", isError: !success)
    }

    private func cutAgent(_ agentID: UUID) {
        let success = appState.cutAgent(agentID)
        if success, selectedAgentID == agentID {
            selectedAgentID = nil
        }
        let agentName = currentAgent(id: agentID)?.name ?? "agent"
        showFeedback(success ? "Cut \(agentName)" : "Cut failed", isError: !success)
    }

    private func pasteAgent() {
        if let newAgent = appState.pasteAgentFromPasteboard() {
            selectedAgentID = newAgent.id
            showFeedback("Pasted \(newAgent.name)", isError: false)
        } else {
            showFeedback("Paste failed", isError: true)
        }
    }

    private func duplicateAgent(_ agentID: UUID) {
        if let newAgent = appState.duplicateAgent(agentID, suffix: "Duplicate", offset: CGPoint(x: 50, y: 50)) {
            selectedAgentID = newAgent.id
            showFeedback("Duplicated \(newAgent.name)", isError: false)
        } else {
            showFeedback("Duplicate failed", isError: true)
        }
    }

    private func export(agentID: UUID) {
        guard let agent = currentAgent(id: agentID) else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(agent.name).json"

        panel.begin { response in
            if response == .OK, let url = panel.url {
                do {
                    let data = try JSONEncoder().encode(agent)
                    try data.write(to: url)
                    showFeedback("Exported \(agent.name)", isError: false)
                } catch {
                    showFeedback("Export failed: \(error.localizedDescription)", isError: true)
                }
            }
        }
    }

    private func resetAgent(_ agentID: UUID) {
        guard var agent = currentAgent(id: agentID) else { return }
        agent.updatedAt = Date()
        appState.updateAgent(agent, reload: true)
        showFeedback("Reset \(agent.name)", isError: false)
    }

    private func showFeedback(_ message: String, isError: Bool) {
        feedback = AgentActionFeedback(message: message, isError: isError)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            if feedback?.message == message {
                feedback = nil
            }
        }
    }

    private func refreshCollectionSnapshot() {
        collectionSnapshot = makeAgentCollectionSnapshot(appState: appState)
    }
}

private struct AgentListRow: View {
    let item: AgentCollectionItem
    let isSelected: Bool
    let isConnectMode: Bool
    let isConnectSource: Bool
    var onSelect: () -> Void
    var onOpen: () -> Void
    var onEdit: () -> Void
    var onRevealSoul: () -> Void
    var onDuplicate: () -> Void
    var onDelete: () -> Void
    var onConnect: (UUID) -> Void

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 12) {
                AgentStatusPill(label: item.statusLabel, systemImage: item.statusSystemImage, color: item.statusColor)
                    .frame(width: 120, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.agent.name)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    Text(item.agent.identity)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    if !item.agent.description.isEmpty {
                        Text(item.agent.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(minWidth: 220, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.agent.openClawDefinition.modelIdentifier)
                        .font(.subheadline)
                        .lineLimit(1)
                    Text(item.agent.openClawDefinition.runtimeProfile)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .frame(minWidth: 170, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    Text("In \(item.incomingConnections) / Out \(item.outgoingConnections)")
                        .font(.caption)
                    Text("\(item.agent.capabilities.count) skills")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(width: 110, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.soulDisplayName)
                        .font(.caption)
                        .foregroundColor(item.hasSoulFile ? .primary : .orange)
                        .lineLimit(1)
                    Text(item.soulDirectoryName ?? "Using project cache only")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .frame(minWidth: 170, alignment: .leading)

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onSelect()
            }
            .onTapGesture(count: 2) {
                onEdit()
            }

            HStack(spacing: 8) {
                Button(action: onOpen) {
                    Image(systemName: "scope")
                }
                .buttonStyle(.borderless)
                .help("Focus agent and sync selection")

                Button(action: onEdit) {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .help("Edit real SOUL.md content")

                Button(action: onRevealSoul) {
                    Image(systemName: "doc.text.magnifyingglass")
                }
                .buttonStyle(.borderless)
                .help("Reveal SOUL.md in Finder")

                Button(action: onDuplicate) {
                    Image(systemName: "plus.square.on.square")
                }
                .buttonStyle(.borderless)
                .help("Duplicate agent")

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Delete agent")

                if isConnectMode {
                    Button(action: { onConnect(item.agent.id) }) {
                        Image(systemName: "link")
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.blue)
                    .help("Connect from selected source agent")
                }
            }
            .frame(width: isConnectMode ? 210 : 180, alignment: .center)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 2)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : (isConnectSource ? Color.blue.opacity(0.10) : Color.clear))
        )
    }
}

// MARK: - 网格视图
struct AgentGridView: View {
    @EnvironmentObject var appState: AppState
    @Binding var selectedAgentID: UUID?
    var isConnectMode: Bool
    var connectFromAgentID: UUID?
    var onConnect: (UUID, UUID) -> Void

    private let columns = [GridItem(.adaptive(minimum: 280, maximum: 380), spacing: 16)]

    @State private var searchText = ""
    @State private var filter: AgentCollectionFilter = .all
    @State private var sort: AgentCollectionSort = .updated
    @State private var editingAgent: Agent?
    @State private var skillsAgent: Agent?
    @State private var permissionsAgent: Agent?
    @State private var deleteCandidate: Agent?
    @State private var feedback: AgentActionFeedback?
    @State private var collectionSnapshot: AgentCollectionSnapshot = .empty

    private var items: [AgentCollectionItem] {
        collectionSnapshot.items
    }

    private var visibleItems: [AgentCollectionItem] {
        filterAgentItems(items, searchText: searchText, filter: filter, sort: sort)
    }

    private var collectionSignature: AgentCollectionSignature {
        makeAgentCollectionSignature(project: appState.currentProject)
    }

    var body: some View {
        VStack(spacing: 0) {
            AgentCollectionToolbar(
                searchText: $searchText,
                filter: $filter,
                sort: $sort,
                snapshot: collectionSnapshot,
                visibleCount: visibleItems.count,
                feedback: feedback
            )

            Divider()

            if visibleItems.isEmpty {
                AgentCollectionEmptyState(searchText: searchText)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(visibleItems) { item in
                            AgentGridCard(
                                item: item,
                                isSelected: selectedAgentID == item.agent.id,
                                isConnectMode: isConnectMode,
                                isConnectSource: connectFromAgentID == item.agent.id,
                                onSelect: { selectedAgentID = item.agent.id },
                                onOpen: { focusAgent(item.agent.id) },
                                onEdit: { beginEditing(item.agent.id) },
                                onRevealSoul: { revealSoul(for: item.agent.id) },
                                onOpenWorkspace: { openWorkspace(for: item.agent.id) },
                                onDuplicate: { duplicateAgent(item.agent.id) },
                                onDelete: { deleteCandidate = currentAgent(id: item.agent.id) ?? item.agent },
                                onConnect: { targetID in
                                    guard let sourceID = connectFromAgentID else { return }
                                    onConnect(sourceID, targetID)
                                }
                            )
                            .contextMenu {
                                AgentContextMenuContent(
                                    item: item,
                                    canPaste: NSPasteboard.general.canReadObject(forClasses: [NSString.self], options: nil),
                                    onOpen: { focusAgent(item.agent.id) },
                                    onRevealSoul: { revealSoul(for: item.agent.id) },
                                    onOpenWorkspace: { openWorkspace(for: item.agent.id) },
                                    onReloadSoul: { reloadSoul(for: item.agent.id) },
                                    onEdit: { beginEditing(item.agent.id) },
                                    onManageSkills: { skillsAgent = currentAgent(id: item.agent.id) ?? item.agent },
                                    onConfigurePermissions: { permissionsAgent = currentAgent(id: item.agent.id) ?? item.agent },
                                    onCopy: { copyAgent(item.agent.id) },
                                    onCut: { cutAgent(item.agent.id) },
                                    onPaste: pasteAgent,
                                    onDuplicate: { duplicateAgent(item.agent.id) },
                                    onExport: { export(agentID: item.agent.id) },
                                    onReset: { resetAgent(item.agent.id) },
                                    onDelete: { deleteCandidate = currentAgent(id: item.agent.id) ?? item.agent }
                                )
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
        .sheet(item: $editingAgent) { agent in
            AgentEditSheet(agent: agent, isPresented: bindingForAgentSheet($editingAgent))
        }
        .sheet(item: $skillsAgent) { agent in
            SkillsManagementSheet(agent: agent, isPresented: bindingForAgentSheet($skillsAgent))
        }
        .sheet(item: $permissionsAgent) { agent in
            PermissionsConfigSheet(agent: agent, isPresented: bindingForAgentSheet($permissionsAgent))
        }
        .alert("Delete Agent?", isPresented: deleteConfirmationBinding) {
            Button("Delete", role: .destructive) {
                if let candidate = deleteCandidate {
                    appState.deleteAgent(candidate.id)
                    if selectedAgentID == candidate.id {
                        selectedAgentID = nil
                    }
                    showFeedback("Deleted \(candidate.name)", isError: false)
                }
                deleteCandidate = nil
            }
            Button("Cancel", role: .cancel) {
                deleteCandidate = nil
            }
        } message: {
            Text(deleteCandidate.map { "Delete \"\($0.name)\" and remove its workflow node references?" } ?? "")
        }
        .onAppear(perform: refreshCollectionSnapshot)
        .onChange(of: collectionSignature) { _, _ in
            refreshCollectionSnapshot()
        }
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { deleteCandidate != nil },
            set: { if !$0 { deleteCandidate = nil } }
        )
    }

    private func bindingForAgentSheet(_ item: Binding<Agent?>) -> Binding<Bool> {
        Binding(
            get: { item.wrappedValue != nil },
            set: { if !$0 { item.wrappedValue = nil } }
        )
    }

    private func currentAgent(id: UUID) -> Agent? {
        appState.currentProject?.agents.first(where: { $0.id == id })
    }

    private func focusAgent(_ agentID: UUID) {
        selectedAgentID = agentID
        _ = appState.focusAgentNode(agentID: agentID, createIfMissing: true, suggestedPosition: .zero)
    }

    private func beginEditing(_ agentID: UUID) {
        guard let agent = currentAgent(id: agentID) else { return }
        selectedAgentID = agentID
        editingAgent = agent
    }

    private func revealSoul(for agentID: UUID) {
        if let soulURL = appState.agentSoulFileURL(for: agentID) {
            NSWorkspace.shared.activateFileViewerSelecting([soulURL])
            showFeedback("Revealed \(soulURL.lastPathComponent)", isError: false)
        } else {
            showFeedback("No real SOUL.md file was found for this agent.", isError: true)
        }
    }

    private func openWorkspace(for agentID: UUID) {
        if let workspaceURL = appState.agentWorkspaceURL(for: agentID) {
            NSWorkspace.shared.open(workspaceURL)
            showFeedback("Opened workspace \(workspaceURL.lastPathComponent)", isError: false)
        } else {
            showFeedback("No workspace directory was found for this agent.", isError: true)
        }
    }

    private func reloadSoul(for agentID: UUID) {
        let result = appState.refreshAgentSoulMDFromSource(agentID: agentID)
        showFeedback(result.message, isError: !result.success)
        if result.success, editingAgent?.id == agentID {
            editingAgent = currentAgent(id: agentID)
        }
    }

    private func copyAgent(_ agentID: UUID) {
        guard let agent = currentAgent(id: agentID) else { return }
        let success = appState.copyAgent(agent)
        showFeedback(success ? "Copied \(agent.name)" : "Copy failed", isError: !success)
    }

    private func cutAgent(_ agentID: UUID) {
        let agentName = currentAgent(id: agentID)?.name ?? "agent"
        let success = appState.cutAgent(agentID)
        if success, selectedAgentID == agentID {
            selectedAgentID = nil
        }
        showFeedback(success ? "Cut \(agentName)" : "Cut failed", isError: !success)
    }

    private func pasteAgent() {
        if let newAgent = appState.pasteAgentFromPasteboard() {
            selectedAgentID = newAgent.id
            showFeedback("Pasted \(newAgent.name)", isError: false)
        } else {
            showFeedback("Paste failed", isError: true)
        }
    }

    private func duplicateAgent(_ agentID: UUID) {
        if let newAgent = appState.duplicateAgent(agentID, suffix: "Duplicate", offset: CGPoint(x: 50, y: 50)) {
            selectedAgentID = newAgent.id
            showFeedback("Duplicated \(newAgent.name)", isError: false)
        } else {
            showFeedback("Duplicate failed", isError: true)
        }
    }

    private func export(agentID: UUID) {
        guard let agent = currentAgent(id: agentID) else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(agent.name).json"

        panel.begin { response in
            if response == .OK, let url = panel.url {
                do {
                    let data = try JSONEncoder().encode(agent)
                    try data.write(to: url)
                    showFeedback("Exported \(agent.name)", isError: false)
                } catch {
                    showFeedback("Export failed: \(error.localizedDescription)", isError: true)
                }
            }
        }
    }

    private func resetAgent(_ agentID: UUID) {
        guard var agent = currentAgent(id: agentID) else { return }
        agent.updatedAt = Date()
        appState.updateAgent(agent, reload: true)
        showFeedback("Reset \(agent.name)", isError: false)
    }

    private func showFeedback(_ message: String, isError: Bool) {
        feedback = AgentActionFeedback(message: message, isError: isError)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            if feedback?.message == message {
                feedback = nil
            }
        }
    }

    private func refreshCollectionSnapshot() {
        collectionSnapshot = makeAgentCollectionSnapshot(appState: appState)
    }
}

private struct AgentGridCard: View {
    let item: AgentCollectionItem
    let isSelected: Bool
    let isConnectMode: Bool
    let isConnectSource: Bool
    var onSelect: () -> Void
    var onOpen: () -> Void
    var onEdit: () -> Void
    var onRevealSoul: () -> Void
    var onOpenWorkspace: () -> Void
    var onDuplicate: () -> Void
    var onDelete: () -> Void
    var onConnect: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.agent.name)
                            .font(.headline)
                            .lineLimit(1)
                        Text(item.agent.identity)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    AgentStatusPill(label: item.statusLabel, systemImage: item.statusSystemImage, color: item.statusColor)
                }

                if !item.agent.description.isEmpty {
                    Text(item.agent.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Label(item.agent.openClawDefinition.modelIdentifier, systemImage: "cpu")
                    Label(item.agent.openClawDefinition.runtimeProfile, systemImage: "dial.high")
                    Label("\(item.agent.capabilities.count) skills", systemImage: "star")
                    Label("In \(item.incomingConnections) / Out \(item.outgoingConnections)", systemImage: "arrow.left.arrow.right")
                    Label(item.hasSoulFile ? item.soulDisplayName : "Project cache only", systemImage: item.hasSoulFile ? "doc.text" : "exclamationmark.triangle")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .onTapGesture {
                onSelect()
            }
            .onTapGesture(count: 2) {
                onEdit()
            }

            HStack(spacing: 10) {
                Button(action: onOpen) {
                    Label("Focus", systemImage: "scope")
                }
                .buttonStyle(.borderless)

                Button(action: onEdit) {
                    Label("Edit", systemImage: "pencil")
                }
                .buttonStyle(.borderless)

                Button(action: onRevealSoul) {
                    Label("SOUL", systemImage: "doc.text.magnifyingglass")
                }
                .buttonStyle(.borderless)

                Spacer()

                Button(action: onOpenWorkspace) {
                    Image(systemName: "folder")
                }
                .buttonStyle(.borderless)
                .help("Open workspace")

                Button(action: onDuplicate) {
                    Image(systemName: "plus.square.on.square")
                }
                .buttonStyle(.borderless)
                .help("Duplicate agent")

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Delete agent")

                if isConnectMode {
                    Button(action: { onConnect(item.agent.id) }) {
                        Image(systemName: "link")
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.blue)
                    .help("Connect from selected source agent")
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isSelected ? Color.accentColor : (isConnectSource ? Color.blue : Color.clear), lineWidth: 2)
        )
    }
}

// MARK: - 架构视图（带Agent库和隔离框）
struct ArchitectureView: View {
    @EnvironmentObject var appState: AppState
    @Binding var zoomScale: CGFloat
    @Binding var offset: CGSize
    @Binding var lastOffset: CGSize
    @Binding var isConnectMode: Bool
    @Binding var connectFromAgentID: UUID?
    @Binding var connectionType: WorkflowEditorView.ConnectionType
    @Binding var selectedNodeID: UUID?
    @Binding var selectedNodeIDs: Set<UUID>
    @Binding var selectedEdgeID: UUID?
    @Binding var selectedBoundaryIDs: Set<UUID>
    @Binding var isLassoMode: Bool
    var onConnect: (UUID, UUID) -> Void
    var testExecution: WorkflowTestExecution?
    
    @State private var showNodePropertyPanel = false
    @State private var selectedNodeForProperty: WorkflowNode?
    @State private var showEdgePropertyPanel = false
    @State private var selectedEdgeForProperty: WorkflowEdge?
    
    var body: some View {
        GeometryReader { _ in
            HStack(spacing: 0) {
                CanvasView(
                    zoomScale: $zoomScale,
                    offset: $offset,
                    lastOffset: $lastOffset,
                    selectedNodeID: $selectedNodeID,
                    selectedNodeIDs: $selectedNodeIDs,
                    selectedEdgeID: $selectedEdgeID,
                    selectedBoundaryIDs: $selectedBoundaryIDs,
                    isConnectMode: $isConnectMode,
                    connectionType: $connectionType,
                    connectFromAgentID: $connectFromAgentID,
                    isLassoMode: $isLassoMode,
                    onNodeClickInConnectMode: { node in
                        self.handleNodeClickInConnectMode(node: node)
                    },
                    onNodeSelected: { node in
                        selectedEdgeForProperty = nil
                        showEdgePropertyPanel = false
                        selectedNodeForProperty = node
                    },
                    onNodeSecondarySelected: { node in
                        selectedEdgeForProperty = nil
                        showEdgePropertyPanel = false
                        selectedNodeForProperty = node
                        showNodePropertyPanel = true
                    },
                    onEdgeSelected: { edge in
                        selectedNodeForProperty = nil
                        showNodePropertyPanel = false
                        selectedEdgeForProperty = edge
                        showEdgePropertyPanel = true
                    },
                    onEdgeSecondarySelected: { edge in
                        selectedNodeForProperty = nil
                        showNodePropertyPanel = false
                        selectedEdgeForProperty = edge
                        showEdgePropertyPanel = true
                    },
                    onDropAgent: { agentName, location in
                        self.addAgentNodeToCanvas(agentName: agentName, at: location)
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if showNodePropertyPanel, let node = selectedNodeForProperty {
                    NodePropertyPanel(
                        node: node,
                        isPresented: $showNodePropertyPanel
                    )
                    .frame(width: 420)
                    .transition(.move(edge: .trailing))
                } else if showEdgePropertyPanel, let edge = selectedEdgeForProperty {
                    EdgePropertyPanel(
                        edge: edge,
                        isPresented: $showEdgePropertyPanel
                    )
                    .frame(width: 360)
                    .transition(.move(edge: .trailing))
                }
            }
        }
    }
    
    private func addAgentNodeToCanvas(agentName: String, at _: CGPoint) {
        appState.addAgentNode(agentName: agentName, position: CGPoint(x: 300, y: 200))
    }
    
    // 处理连接模式下的节点点击
    private func handleNodeClickInConnectMode(node: WorkflowNode) {
        guard node.type == .agent || node.type == .start else { return }

        if isConnectMode {
            if let fromID = connectFromAgentID {
                // Create connection from source to this node
                if let sourceNodeID = resolveConnectableNodeID(from: fromID) {
                    self.createConnection(from: sourceNodeID, to: node.id)
                }
                connectFromAgentID = nil
            } else {
                // Set as source node
                connectFromAgentID = node.id
            }
        }
    }
    
    // 创建连接
    private func createConnection(from: UUID, to: UUID) {
        guard from != to else { return }
        appState.connectNodes(from: from, to: to, bidirectional: connectionType == .bidirectional)
    }

    private func resolveConnectableNodeID(from identifier: UUID) -> UUID? {
        guard let workflow = appState.currentProject?.workflows.first else { return nil }

        if workflow.nodes.contains(where: { $0.id == identifier && ($0.type == .agent || $0.type == .start) }) {
            return identifier
        }

        if let node = workflow.nodes.first(where: { $0.agentID == identifier && $0.type == .agent }) {
            return node.id
        }

        return nil
    }
}

// MARK: - Agent库侧边栏
struct AgentLibrarySidebar: View {
    @EnvironmentObject var appState: AppState
    var onAddAll: () -> Void
    var isOpenClawConnected: Bool = false
    var openClawAgents: [String] = []
    @State private var openClawExpanded: Bool = true
    @State private var projectExpanded: Bool = true
    @State private var templateExpanded: Bool = false

    private var templateGroups: [(category: AgentTemplateCategory, templates: [AgentTemplate])] {
        AgentTemplateCatalog.categories.compactMap { category in
            let templates = AgentTemplateCatalog.templates(in: category)
            guard !templates.isEmpty else { return nil }
            return (category, templates)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 标题
            HStack {
                Image(systemName: "cube.box")
                Text(LocalizedString.agentLibrary)
                    .font(.headline)
                Spacer()
            }
            .padding()
            .background(Color(.controlBackgroundColor))
            
            // 添加所有Agent到画布按钮（仅在连接OpenClaw时显示）
            if isOpenClawConnected {
                Button(action: onAddAll) {
                    HStack {
                        Spacer(minLength: 0)
                        Image(systemName: "plus.square.on.square")
                        Text("Generate Architecture")
                        Spacer(minLength: 0)
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
                        AgentLibraryDisclosureHeader(
                            title: LocalizedString.openclawAgents,
                            systemImage: "network",
                            count: openClawAgents.count,
                            isExpanded: openClawExpanded,
                            topPadding: 8
                        ) {
                            openClawExpanded.toggle()
                        }

                        if openClawExpanded {
                            ForEach(openClawAgents, id: \.self) { agentName in
                                DraggableAgentItem(name: agentName)
                                    .padding(.horizontal, 4)
                            }
                        }
                            
                        Divider()
                            .padding(.vertical, 8)
                    }

                    AgentLibraryDisclosureHeader(
                        title: "模板",
                        systemImage: "square.stack.3d.up",
                        count: AgentTemplateCatalog.templates.count,
                        isExpanded: templateExpanded
                    ) {
                        templateExpanded.toggle()
                    }

                    if templateExpanded {
                        ForEach(templateGroups, id: \.category) { group in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(group.category.rawValue)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 4)

                                ForEach(group.templates) { template in
                                    TemplateLibraryItem(template: template) {
                                        addTemplateNode(template)
                                    }
                                    .padding(.horizontal, 4)
                                }
                            }
                        }

                        Divider()
                            .padding(.vertical, 8)
                    }
                    
                    // 项目中的Agents
                    let projectAgents = appState.currentProject?.agents ?? []
                    AgentLibraryDisclosureHeader(
                        title: LocalizedString.projectAgents,
                        systemImage: "folder",
                        count: projectAgents.count,
                        isExpanded: projectExpanded
                    ) {
                        projectExpanded.toggle()
                    }
                    
                    if projectExpanded {
                        ForEach(projectAgents) { agent in
                            DraggableAgentItem(name: agent.name, agent: agent)
                                .padding(.horizontal, 4)
                        }
                    }
                }
                .padding()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            
            Divider()
            
            // 节点类型
            VStack(alignment: .leading, spacing: 8) {
                Text(LocalizedString.nodeTypes)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                
                HStack(spacing: 8) {
                    NodeTypeButton(icon: "play.circle.fill", label: LocalizedString.startNode, type: .start)
                    NodeTypeButton(icon: "person.circle.fill", label: LocalizedString.agentNode, type: .agent)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .background(Color(.controlBackgroundColor))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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

    private func addTemplateNode(_ template: AgentTemplate) {
        guard let agent = appState.addNewAgent(templateID: template.id) else { return }
        appState.addAgentNode(agentName: agent.name, position: CGPoint(x: 300, y: 200))
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
        .onDrag { NSItemProvider(object: "nodeType:\(type.rawValue)" as NSString) }
    }
}

private struct AgentLibraryDisclosureHeader: View {
    let title: String
    let systemImage: String
    let count: Int
    let isExpanded: Bool
    var topPadding: CGFloat = 0
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: systemImage)
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(count)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.2))
                    .cornerRadius(4)
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.top, topPadding)
        }
        .buttonStyle(.plain)
    }
}

private struct TemplateLibraryItem: View {
    let template: AgentTemplate
    let onAdd: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "shippingbox.fill")
                .foregroundColor(.accentColor)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(template.name)
                    .font(.subheadline)
                    .lineLimit(1)
                Text(template.summary)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Button(action: onAdd) {
                Image(systemName: "plus.circle")
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
            .help("基于该模板创建节点")
        }
        .padding(8)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(6)
        .help("拖拽到画布可直接创建模板节点")
        .onDrag { NSItemProvider(object: "template:\(template.id)" as NSString) }
    }
}

// MARK: - 节点属性面板
struct NodePropertyPanel: View {
    @EnvironmentObject var appState: AppState
    let node: WorkflowNode
    @Binding var isPresented: Bool
    
    @State private var nodeTitle: String = ""
    @State private var agentDescription: String = ""
    @State private var soulConfig: String = ""
    @State private var conditionExpression: String = ""
    @State private var loopEnabled: Bool = false
    @State private var maxIterations: Double = 1
    @State private var nodeDisplayColorHex: String?
    @State private var reloadStatus: String?
    @State private var soulSourcePath: String?
    @State private var outgoingEdgeDrafts: [UUID: EdgeDraft] = [:]
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Node Properties")
                    .font(.headline)
                Spacer()
                Button("Close") {
                    isPresented = false
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
            }
            .padding()
            .background(Color(.windowBackgroundColor))
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
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

                            if node.type != .agent {
                                TextField("Title", text: $nodeTitle)
                                    .textFieldStyle(.roundedBorder)
                            }

                        }
                        .padding(8)
                    }

                    GroupBox("Node Color Group") {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                ForEach(CanvasAccentColorPreset.allCases) { preset in
                                    Button {
                                        nodeDisplayColorHex = preset.hex
                                    } label: {
                                        Circle()
                                            .fill(preset.color)
                                            .frame(width: 18, height: 18)
                                            .overlay(
                                                Circle()
                                                    .stroke(
                                                        CanvasStylePalette.normalizedHex(nodeDisplayColorHex) == preset.hex ? Color.primary : Color.clear,
                                                        lineWidth: 2
                                                    )
                                            )
                                    }
                                    .buttonStyle(.plain)
                                    .help(preset.title)
                                }

                                Button("默认") {
                                    nodeDisplayColorHex = nil
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }

                            Text("同色节点会自动归组，标签可在画布左上角直接编辑。")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(8)
                    }
                    
                    if node.type == .agent, let agentID = node.agentID,
                       let agent = getAgent(id: agentID) {
                        GroupBox("Agent: \(agent.name)") {
                            VStack(alignment: .leading, spacing: 14) {
                                TextField("Name", text: $nodeTitle)
                                    .textFieldStyle(.roundedBorder)

                                TextField("Description", text: $agentDescription)
                                    .textFieldStyle(.roundedBorder)

                                VStack(alignment: .leading, spacing: 6) {
                                    Text("SOUL Source Path")
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                    if let soulSourcePath {
                                        LabeledContent("Path") {
                                            Text(soulSourcePath)
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                                .multilineTextAlignment(.trailing)
                                                .textSelection(.enabled)
                                        }
                                    } else {
                                        Text("未定位到 SOUL 文件，当前编辑的是项目缓存。")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }

                                TextEditor(text: $soulConfig)
                                    .font(.system(.caption, design: .monospaced))
                                    .frame(minHeight: 380, idealHeight: 440, maxHeight: 560)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                    )

                                if let reloadStatus {
                                    Text(reloadStatus)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(8)
                        }
                    }
                }
                .padding()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            
            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button("Apply") {
                saveChanges()
                isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(.regularMaterial)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.black.opacity(0.10))
                    .frame(height: 1)
            }
            .shadow(color: Color.black.opacity(0.10), radius: 10, x: 0, y: -3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(.windowBackgroundColor))
        .onAppear {
            loadNodeData()
        }
    }
    
    private func getAgent(id: UUID) -> Agent? {
        appState.currentProject?.agents.first { $0.id == id }
    }

    private func loadNodeData() {
        nodeTitle = node.title
        agentDescription = ""
        conditionExpression = node.conditionExpression
        loopEnabled = node.loopEnabled
        maxIterations = Double(max(1, node.maxIterations))
        nodeDisplayColorHex = CanvasStylePalette.normalizedHex(node.displayColorHex)

        if let agentID = node.agentID,
           let agent = getAgent(id: agentID) {
            nodeTitle = agent.name
            agentDescription = agent.description
            if let loaded = appState.loadAgentSoulMDFromSource(agentID: agentID) {
                soulConfig = loaded.content
                soulSourcePath = loaded.sourcePath
            } else {
                soulConfig = agent.soulMD
                soulSourcePath = nil
            }
        }
    }
    
    private func saveChanges() {
        var updatedNode = node
        updatedNode.title = node.type == .agent ? "" : nodeTitle
        updatedNode.displayColorHex = CanvasStylePalette.normalizedHex(nodeDisplayColorHex)
        appState.updateNode(updatedNode)

        if let agentID = node.agentID,
           var agent = getAgent(id: agentID) {
            let fileResult = appState.persistAgentSoulMDToSource(agentID: agentID, soulMD: soulConfig)
            if !fileResult.success {
                reloadStatus = fileResult.message
            } else {
                soulSourcePath = fileResult.message.replacingOccurrences(of: "已写入 ", with: "")
            }
            agent.name = nodeTitle
            agent.description = agentDescription
            agent.soulMD = soulConfig
            agent.openClawDefinition.soulSourcePath = soulSourcePath ?? agent.openClawDefinition.soulSourcePath
            agent.updatedAt = Date()
            appState.updateAgent(agent, reload: true)
            if fileResult.success {
                reloadStatus = "Reload requested at \(Date.now.formatted(date: .omitted, time: .shortened))"
            }
        }
    }

    private var outgoingEdges: [WorkflowEdge] {
        appState.currentProject?.workflows.first?.edges.filter { $0.isOutgoing(from: node.id) } ?? []
    }

    private func binding(for edge: WorkflowEdge) -> Binding<EdgeDraft> {
        Binding(
            get: { outgoingEdgeDrafts[edge.id] ?? EdgeDraft(edge: edge) },
            set: { outgoingEdgeDrafts[edge.id] = $0 }
        )
    }

    private func targetName(for edge: WorkflowEdge) -> String {
        guard let workflow = appState.currentProject?.workflows.first,
              let targetNode = workflow.nodes.first(where: { $0.id == edge.toNodeID }) else {
            return "Unknown"
        }

        if let targetAgent = targetNode.agentID.flatMap(getAgent(id:)) {
            return targetAgent.name
        }

        if !targetNode.title.isEmpty {
            return targetNode.title
        }

        return targetNode.type.rawValue.capitalized
    }

    struct EdgeDraft {
        var edge: WorkflowEdge
        var label: String
        var conditionExpression: String
        var requiresApproval: Bool

        init(edge: WorkflowEdge) {
            self.edge = edge
            self.label = edge.label
            self.conditionExpression = edge.conditionExpression
            self.requiresApproval = edge.requiresApproval
        }
    }
}

struct RouteEditorRow: View {
    @Binding var edge: NodePropertyPanel.EdgeDraft
    let targetName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "arrow.turn.down.right")
                    .foregroundColor(.secondary)
                Text(targetName)
                    .font(.caption)
                    .fontWeight(.medium)
                Spacer()
                Toggle("Approval", isOn: $edge.requiresApproval)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            TextField("Condition label", text: $edge.label)
                .textFieldStyle(.roundedBorder)

            TextField("Condition expression", text: $edge.conditionExpression)
                .textFieldStyle(.roundedBorder)
        }
        .padding(10)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }
}

struct EdgePropertyPanel: View {
    @EnvironmentObject var appState: AppState
    let edge: WorkflowEdge
    @Binding var isPresented: Bool

    @State private var label: String = ""
    @State private var conditionExpression: String = ""
    @State private var requiresApproval: Bool = false
    @State private var isBidirectional: Bool = false
    @State private var dataMappingText: String = ""
    @State private var edgeDisplayColorHex: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Edge Properties", systemImage: "arrowshape.right")
                    .font(.headline)
                Spacer()
                Button("Close") {
                    isPresented = false
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    GroupBox("Route Summary") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("From: \(sourceName)")
                            Text("To: \(targetName)")
                            Text("Edge ID: \(edge.id.uuidString.prefix(8))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                    }

                    GroupBox("Visual Summary") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 10) {
                                summaryBadge(text: sourceName, color: .blue)
                                Image(systemName: "arrow.right")
                                    .foregroundColor(.secondary)
                                summaryBadge(text: targetName, color: .green)
                            }

                            HStack(spacing: 8) {
                                summaryBadge(
                                    text: label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Unlabeled route" : label,
                                    color: .accentColor
                                )
                                summaryBadge(
                                    text: isBidirectional ? "Two-way" : "One-way",
                                    color: .indigo
                                )
                                if requiresApproval {
                                    summaryBadge(text: "Approval", color: .orange)
                                }
                            }

                            Text(
                                conditionExpression.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? "No condition expression. This route is always eligible when reached."
                                    : conditionExpression
                            )
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                    }

                    GroupBox("Route Display") {
                        VStack(alignment: .leading, spacing: 12) {
                            TextField("Label", text: $label)
                                .textFieldStyle(.roundedBorder)

                            TextField("Condition", text: $conditionExpression)
                                .textFieldStyle(.roundedBorder)

                            Toggle("Requires Approval", isOn: $requiresApproval)

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Data Mapping")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                TextEditor(text: $dataMappingText)
                                    .font(.system(.caption, design: .monospaced))
                                    .frame(minHeight: 90, maxHeight: 120)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(Color.gray.opacity(0.25), lineWidth: 1)
                                    )
                            }
                        }
                        .padding(8)
                    }

                    GroupBox("Route Color Group") {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                ForEach(CanvasAccentColorPreset.allCases) { preset in
                                    Button {
                                        edgeDisplayColorHex = preset.hex
                                    } label: {
                                        Circle()
                                            .fill(preset.color)
                                            .frame(width: 18, height: 18)
                                            .overlay(
                                                Circle()
                                                    .stroke(
                                                        CanvasStylePalette.normalizedHex(edgeDisplayColorHex) == preset.hex ? Color.primary : Color.clear,
                                                        lineWidth: 2
                                                    )
                                            )
                                    }
                                    .buttonStyle(.plain)
                                    .help(preset.title)
                                }

                                Button("默认") {
                                    edgeDisplayColorHex = nil
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }

                            Text("同色连线会自动归组，标签可在画布左上角直接编辑。")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(8)
                    }

                    GroupBox("Communication Direction") {
                        VStack(alignment: .leading, spacing: 10) {
                            Picker("Direction", selection: $isBidirectional) {
                                Text("One-way").tag(false)
                                Text("Two-way").tag(true)
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: isBidirectional) { _, newValue in
                                appState.setEdgeCommunicationDirection(edgeID: edge.id, bidirectional: newValue)
                            }

                            HStack(spacing: 8) {
                                Button {
                                    appState.flipEdgeDirection(edgeID: edge.id)
                                } label: {
                                    Label("Reverse", systemImage: "arrow.left.arrow.right")
                                }
                                .buttonStyle(.bordered)
                                .disabled(isBidirectional)

                                Text(isBidirectional ? "Two-way keeps both directions." : "Use Reverse to swap the one-way direction.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(8)
                    }
                }
                .padding()
            }

            Divider()

            HStack {
                Button("Delete Route", role: .destructive) {
                    appState.removeEdge(edge.id)
                    isPresented = false
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Apply") {
                    saveRouteDisplayChanges()
                }
                .buttonStyle(.bordered)

                Button("Close") {
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 320)
        .background(Color(.windowBackgroundColor))
        .onAppear {
            label = edge.label
            conditionExpression = edge.conditionExpression
            requiresApproval = edge.requiresApproval
            isBidirectional = isBidirectionalEdge(edge)
            dataMappingText = formattedDataMapping(edge.dataMapping)
            edgeDisplayColorHex = CanvasStylePalette.normalizedHex(edge.displayColorHex)
        }
    }

    private var sourceName: String { endpointName(for: edge.fromNodeID) }
    private var targetName: String { endpointName(for: edge.toNodeID) }

    private func summaryBadge(text: String, color: Color) -> some View {
        Text(text)
            .font(.caption)
            .fontWeight(.medium)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.14))
            .foregroundColor(color)
            .clipShape(Capsule())
    }

    private func formattedDataMapping(_ mapping: [String: String]) -> String {
        mapping
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "\n")
    }

    private func parseDataMapping() -> [String: String] {
        dataMappingText
            .split(whereSeparator: \.isNewline)
            .reduce(into: [String: String]()) { result, line in
                let parts = line.split(separator: "=", maxSplits: 1).map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return }
                result[parts[0]] = parts[1]
            }
    }

    private func endpointName(for nodeID: UUID) -> String {
        guard let workflow = appState.currentProject?.workflows.first,
              let node = workflow.nodes.first(where: { $0.id == nodeID }) else {
            return "Unknown"
        }

        if let agentID = node.agentID,
           let agent = appState.currentProject?.agents.first(where: { $0.id == agentID }) {
            return agent.name
        }

        if !node.title.isEmpty {
            return node.title
        }

        return node.type.rawValue.capitalized
    }

    private func isBidirectionalEdge(_ edge: WorkflowEdge) -> Bool {
        edge.isBidirectional
    }

    private func saveRouteDisplayChanges() {
        appState.updateEdge(edge.id) { updatedEdge in
            updatedEdge.label = label.trimmingCharacters(in: .whitespacesAndNewlines)
            updatedEdge.conditionExpression = conditionExpression.trimmingCharacters(in: .whitespacesAndNewlines)
            updatedEdge.requiresApproval = requiresApproval
            updatedEdge.dataMapping = parseDataMapping()
            updatedEdge.displayColorHex = CanvasStylePalette.normalizedHex(edgeDisplayColorHex)
        }
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

        Button(action: { cutAgent() }) {
            Label("Cut", systemImage: "scissors")
        }

        Button(action: { pasteAgent() }) {
            Label("Paste", systemImage: "doc.on.clipboard")
        }
        
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
           project.agents.contains(where: { $0.id == agent.id }) {
            // Show agent details in properties panel
            appState.selectedNodeID = agent.id
            showToastMessage("Opened: \(agent.name)", type: .info)
        }
    }
    
    private func copyAgent() {
        if appState.copyAgent(agent) {
            showToastMessage("Copied: \(agent.name)", type: .success)
        } else {
            showToastMessage("Copy failed", type: .error)
        }
    }

    private func cutAgent() {
        if appState.cutAgent(agent.id) {
            showToastMessage("Cut: \(agent.name)", type: .success)
        } else {
            showToastMessage("Cut failed", type: .error)
        }
    }

    private func pasteAgent() {
        if let newAgent = appState.pasteAgentFromPasteboard() {
            showToastMessage("Pasted: \(newAgent.name)", type: .success)
        } else {
            showToastMessage("Paste failed", type: .error)
        }
    }
    
    private func duplicateAgent() {
        if let newAgent = appState.duplicateAgent(agent.id, suffix: "Duplicate", offset: CGPoint(x: 50, y: 50)) {
            showToastMessage("Duplicated: \(newAgent.name)", type: .success)
        } else {
            showToastMessage("Duplicate failed", type: .error)
        }
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
        var updatedAgent = agent
        updatedAgent.updatedAt = Date()
        appState.updateAgent(updatedAgent, reload: true)
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
    @State private var identity: String = ""
    @State private var soulSourcePath: String?
    @State private var statusMessage: String?
    @State private var statusIsError = false
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Edit Agent: \(agent.name)")
                        .font(.headline)
                    Text("The editor now reads from the real SOUL source file when one is available.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Close") {
                    isPresented = false
                }
                .buttonStyle(.borderless)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    GroupBox("Agent Info") {
                        VStack(alignment: .leading, spacing: 12) {
                            TextField("Name", text: $name)
                                .textFieldStyle(.roundedBorder)

                            TextField("Identity", text: $identity)
                                .textFieldStyle(.roundedBorder)

                            TextField("Description", text: $description)
                                .textFieldStyle(.roundedBorder)
                        }
                        .padding(8)
                    }

                    GroupBox("SOUL Source") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(soulSourcePath ?? "No real SOUL.md file detected. Saving will create or reuse the best available path.")
                                        .font(.caption)
                                        .foregroundColor(soulSourcePath == nil ? .orange : .secondary)
                                        .textSelection(.enabled)
                                }
                                Spacer()
                            }

                            HStack(spacing: 10) {
                                Button("Reload From Disk") {
                                    reloadFromSource()
                                }
                                .buttonStyle(.bordered)

                                Button("Reveal in Finder") {
                                    revealSource()
                                }
                                .buttonStyle(.bordered)
                                .disabled(soulSourcePath == nil)
                            }

                            TextEditor(text: $soulMD)
                                .font(.system(.body, design: .monospaced))
                                .frame(minHeight: 320)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.gray.opacity(0.25), lineWidth: 1)
                                )
                        }
                        .padding(8)
                    }

                    if let statusMessage {
                        HStack(spacing: 8) {
                            Image(systemName: statusIsError ? "xmark.octagon.fill" : "checkmark.circle.fill")
                            Text(statusMessage)
                        }
                        .font(.caption)
                        .foregroundColor(statusIsError ? .red : .green)
                    }
                }
                .padding()
            }

            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button("Save") {
                    saveChanges()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(.regularMaterial)
        }
        .frame(width: 680, height: 620)
        .onAppear {
            loadAgentData()
        }
    }
    
    private func loadAgentData() {
        if let project = appState.currentProject,
           let a = project.agents.first(where: { $0.id == agent.id }) {
            name = a.name
            identity = a.identity
            description = a.description
            if let loaded = appState.loadAgentSoulMDFromSource(agentID: a.id) {
                soulMD = loaded.content
                soulSourcePath = loaded.sourcePath
                if loaded.sourcePath != nil {
                    statusMessage = "Loaded the real SOUL source file."
                    statusIsError = false
                } else {
                    statusMessage = "No SOUL source file was found. You are editing the project cache."
                    statusIsError = true
                }
            } else {
                soulMD = a.soulMD
                soulSourcePath = nil
                statusMessage = "Failed to resolve the current agent."
                statusIsError = true
            }
        }
    }
    
    private func reloadFromSource() {
        let result = appState.refreshAgentSoulMDFromSource(agentID: agent.id)
        statusMessage = result.message
        statusIsError = !result.success

        if result.success, let loaded = appState.loadAgentSoulMDFromSource(agentID: agent.id) {
            soulMD = loaded.content
            soulSourcePath = loaded.sourcePath
        }
    }

    private func revealSource() {
        guard let soulSourcePath else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: soulSourcePath)])
    }

    private func saveChanges() {
        guard var updatedAgent = appState.currentProject?.agents.first(where: { $0.id == agent.id }) else {
            statusMessage = "Failed to locate the current agent before saving."
            statusIsError = true
            return
        }

        let normalizedIdentity = identity.trimmingCharacters(in: .whitespacesAndNewlines)
        updatedAgent.name = name
        updatedAgent.identity = normalizedIdentity.isEmpty ? "generalist" : normalizedIdentity
        updatedAgent.description = description
        updatedAgent.soulMD = soulMD
        updatedAgent.updatedAt = Date()

        let fileResult = appState.persistAgentSoulMDToSource(agentID: updatedAgent.id, soulMD: soulMD)
        if fileResult.success {
            let persistedPath = fileResult.message.replacingOccurrences(of: "已写入 ", with: "")
            updatedAgent.openClawDefinition.soulSourcePath = persistedPath
            soulSourcePath = persistedPath
        }

        appState.updateAgent(updatedAgent, reload: true)
        statusMessage = fileResult.success ? "Saved agent metadata and SOUL.md to the real source file." : fileResult.message
        statusIsError = !fileResult.success
        if fileResult.success {
            isPresented = false
        }
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
        appState.deleteAgent(agent.id)
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
