//
//  WorkflowEditorView.swift
//  Multi-Agent-Flow
//
//  工作流编辑器 - 支持三种视图模式
//

import SwiftUI
import UniformTypeIdentifiers
import AppKit
import Combine

final class WorkflowEditorSessionState: ObservableObject {
    @Published var viewMode: WorkflowEditorView.EditorViewMode = .architecture
    @Published var canvasOffset: CGSize = .zero
    @Published var canvasLastOffset: CGSize = .zero
    @Published var selectedAgentID: UUID?
}

struct WorkflowEditorView: View {
    @EnvironmentObject var appState: AppState
    @Binding var zoomScale: CGFloat
    @ObservedObject var sessionState: WorkflowEditorSessionState
    
    @State private var selectedNodeID: UUID?
    @State private var selectedNodeIDs: Set<UUID> = []
    @State private var selectedEdgeID: UUID?
    @State private var selectedBoundaryIDs: Set<UUID> = []
    @State private var isConnectMode: Bool = false
    @State private var connectFromAgentID: UUID?
    @State private var isBatchConnectMode: Bool = false
    @State private var batchSourceNodeIDs: Set<UUID> = []
    @State private var batchTargetNodeIDs: Set<UUID> = []
    @State private var batchPreview: BatchConnectionPreview?
    @State private var batchCreatedEdgeIDs: Set<UUID> = []
    @State private var batchHighlightedEdgeIDs: Set<UUID> = []
    @State private var batchEdgeLabel: String = ""
    @State private var batchEdgeColorHex: String?
    @State private var batchRequiresApproval: Bool = false
    @State private var batchFeedback: BatchFeedback?
    @State private var isLassoMode: Bool = false
    @State private var copiedNodes: [WorkflowNode] = []
    @State private var copiedEdges: [WorkflowEdge] = []
    @State private var copiedBoundaries: [WorkflowBoundary] = []
    @State private var connectionType: ConnectionType = .bidirectional
    @State private var refreshKey: Int = 0  // 用于刷新Agent库
    @State private var agentCollectionSnapshot: AgentCollectionSnapshot = .empty
    @State private var agentCollectionRefreshWorkItem: DispatchWorkItem?
    @State private var agentCollectionRefreshToken = UUID()
    @State private var hasActivatedListView = false
    @State private var hasActivatedGridView = false
    @State private var shouldPresentNewNodeProperties = false
    
    enum ConnectionType: String, CaseIterable {
        case unidirectional = "→"
        case bidirectional = "⇄"
        
        var description: String {
            switch self {
            case .unidirectional: return LocalizedString.text("connection_one_way")
            case .bidirectional: return LocalizedString.text("connection_two_way")
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

        var displayTitle: String {
            switch self {
            case .list: return LocalizedString.text("view_mode_list")
            case .grid: return LocalizedString.text("view_mode_grid")
            case .architecture: return LocalizedString.text("view_mode_flow")
            }
        }
    }

    private var selectedAgentBinding: Binding<UUID?> {
        Binding(
            get: { sessionState.selectedAgentID },
            set: { sessionState.selectedAgentID = $0 }
        )
    }

    private struct BatchFeedback: Equatable {
        let message: String
        let isError: Bool
    }
    
    var body: some View {
        VStack(spacing: 0) {
            EditorToolbar(
                currentWorkflowName: appState.currentWorkflowName,
                workflows: appState.currentProject?.workflows ?? [],
                activeWorkflowID: appState.activeWorkflowID,
                viewMode: $sessionState.viewMode,
                selectedNodeID: $selectedNodeID,
                selectedNodeIDs: $selectedNodeIDs,
                selectedEdgeID: $selectedEdgeID,
                selectedBoundaryIDs: $selectedBoundaryIDs,
                isConnectMode: $isConnectMode,
                isBatchConnectMode: $isBatchConnectMode,
                isLassoMode: $isLassoMode,
                connectionType: $connectionType,
                connectFromAgentID: $connectFromAgentID,
                batchSourceCount: batchSourceNodeIDs.count,
                batchTargetCount: batchTargetNodeIDs.count,
                batchPreviewCount: batchPreview?.newEdgeCount ?? 0,
                batchCanCommit: batchPreview?.hasActionableEdges ?? false,
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
                onToggleBatchConnectMode: toggleBatchConnectMode,
                onAssignBatchSources: assignBatchSourcesFromSelection,
                onAssignBatchTargets: assignBatchTargetsFromSelection,
                onPreviewBatchConnections: previewBatchConnections,
                onCommitBatchConnections: commitBatchConnections,
                onCancelBatchConnections: cancelBatchConnectionMode,
                onSelectWorkflow: { workflowID in appState.setActiveWorkflow(workflowID) },
                onImportWorkflowPackage: { appState.importWorkflowPackage() },
                onExportWorkflowPackage: { appState.exportCurrentWorkflowPackage() },
                onApplyWorkflow: { appState.applyPendingWorkflowConfiguration() },
                onSyncWorkflowSession: { appState.syncOpenClawActiveSession(workflowID: currentWorkflow()?.id) }
            )
            .zIndex(1000)
            .background(
                ZStack {
                    DeleteKeyMonitor(
                        isEnabled: { sessionState.viewMode == .architecture },
                        onDelete: handleDeleteShortcut
                    )
                    WorkflowShortcutMonitor(
                        isEnabled: { sessionState.viewMode == .architecture },
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

            if let batchFeedback {
                BatchFeedbackBanner(message: batchFeedback.message, isError: batchFeedback.isError)
                    .padding(.horizontal, 18)
                    .padding(.top, 10)
            }
            
            activeEditorPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .topLeading) {
                    retainedEditorPanes
                }
        }
        .onChange(of: sessionState.viewMode) { _, newValue in
            if newValue == .list {
                hasActivatedListView = true
            } else if newValue == .grid {
                hasActivatedGridView = true
            }

            if newValue != .architecture {
                isConnectMode = false
                connectFromAgentID = nil
                isLassoMode = false
                resetBatchConnectionState()
                if agentCollectionSnapshot.items.isEmpty {
                    refreshAgentCollectionSnapshot(immediate: true)
                }
            }
        }
        .onAppear {
            hasActivatedListView = true
            hasActivatedGridView = true
            refreshAgentCollectionSnapshot(immediate: true)
            reconcileSelectionState()
        }
        .onChange(of: selectedNodeID) { _, newValue in
            appState.selectedNodeID = newValue

            guard let workflow = currentWorkflow(),
                  let nodeID = newValue,
                  let node = workflow.nodes.first(where: { $0.id == nodeID }),
                  let agentID = node.agentID else {
                if newValue == nil, selectedNodeIDs.isEmpty, selectedEdgeID == nil, selectedBoundaryIDs.isEmpty {
                    sessionState.selectedAgentID = nil
                }
                return
            }

            sessionState.selectedAgentID = agentID
        }
        .onChange(of: selectedNodeIDs) { _, newValue in
            if !newValue.isEmpty {
                appState.selectedNodeID = nil
                sessionState.selectedAgentID = nil
            }
        }
        .onChange(of: selectedEdgeID) { _, newValue in
            if newValue != nil {
                appState.selectedNodeID = nil
                sessionState.selectedAgentID = nil
            }
        }
        .onChange(of: selectedBoundaryIDs) { _, newValue in
            if !newValue.isEmpty {
                appState.selectedNodeID = nil
                sessionState.selectedAgentID = nil
            }
        }
        .onChange(of: appState.selectedNodeID) { _, newValue in
            guard newValue != selectedNodeID else { return }

            if let newValue {
                selectedNodeID = newValue
                selectedNodeIDs.removeAll()
                selectedEdgeID = nil
                selectedBoundaryIDs.removeAll()
            } else if selectedNodeID != nil,
                      selectedNodeIDs.isEmpty,
                      selectedEdgeID == nil,
                      selectedBoundaryIDs.isEmpty {
                selectedNodeID = nil
                sessionState.selectedAgentID = nil
            }
        }
        .onChange(of: agentCollectionSignature) { _, _ in
            refreshAgentCollectionSnapshot()
            reconcileSelectionState()
        }
        .onChange(of: appState.activeWorkflowID) { _, _ in
            isConnectMode = false
            connectFromAgentID = nil
            resetBatchConnectionState()
            reconcileSelectionState()
            refreshAgentCollectionSnapshot(immediate: true)
        }
    }

    @ViewBuilder
    private var activeEditorPane: some View {
        switch sessionState.viewMode {
        case .architecture:
            architecturePane(isActive: true)
        case .list:
            listPane(isActive: true)
        case .grid:
            gridPane(isActive: true)
        }
    }

    @ViewBuilder
    private var retainedEditorPanes: some View {
        ZStack {
            if sessionState.viewMode != .architecture {
                architecturePane(isActive: false)
                    .modifier(BackgroundRetainedPane())
            }

            if hasActivatedListView && sessionState.viewMode != .list {
                listPane(isActive: false)
                    .modifier(BackgroundRetainedPane())
            }

            if hasActivatedGridView && sessionState.viewMode != .grid {
                gridPane(isActive: false)
                    .modifier(BackgroundRetainedPane())
            }
        }
    }

    private func architecturePane(isActive: Bool) -> some View {
        ArchitectureView(
            isActive: isActive,
            zoomScale: $zoomScale,
            offset: $sessionState.canvasOffset,
            lastOffset: $sessionState.canvasLastOffset,
            isConnectMode: $isConnectMode,
            connectFromAgentID: $connectFromAgentID,
            connectionType: $connectionType,
            selectedNodeID: $selectedNodeID,
            selectedNodeIDs: $selectedNodeIDs,
            selectedAgentID: selectedAgentBinding,
            selectedEdgeID: $selectedEdgeID,
            selectedBoundaryIDs: $selectedBoundaryIDs,
            isLassoMode: $isLassoMode,
            isBatchConnectMode: $isBatchConnectMode,
            batchSourceNodeIDs: $batchSourceNodeIDs,
            batchTargetNodeIDs: $batchTargetNodeIDs,
            batchPreview: $batchPreview,
            batchCreatedEdgeIDs: $batchCreatedEdgeIDs,
            batchHighlightedEdgeIDs: batchHighlightedEdgeIDs,
            batchEdgeLabel: $batchEdgeLabel,
            batchEdgeColorHex: $batchEdgeColorHex,
            batchRequiresApproval: $batchRequiresApproval,
            shouldPresentSelectedNodeProperties: $shouldPresentNewNodeProperties,
            onAssignBatchSources: assignBatchSourcesFromSelection,
            onAssignBatchTargets: assignBatchTargetsFromSelection,
            onPreviewBatchConnections: previewBatchConnections,
            onCommitBatchConnections: commitBatchConnections,
            onCancelBatchConnections: cancelBatchConnectionMode,
            onUndoBatchConnections: undoLastBatchConnection,
            onConnect: handleAgentConnection
        )
    }

    private func listPane(isActive: Bool) -> some View {
        AgentListView(
            snapshot: agentCollectionSnapshot,
            collectionSignature: agentCollectionSignature,
            isActive: isActive,
            selectedAgentID: selectedAgentBinding,
            isConnectMode: isConnectMode,
            connectFromAgentID: connectFromAgentID,
            onConnect: handleAgentConnection
        )
    }

    private func gridPane(isActive: Bool) -> some View {
        AgentGridView(
            snapshot: agentCollectionSnapshot,
            collectionSignature: agentCollectionSignature,
            isActive: isActive,
            selectedAgentID: selectedAgentBinding,
            isConnectMode: isConnectMode,
            connectFromAgentID: connectFromAgentID,
            onConnect: handleAgentConnection
        )
    }

    private var agentCollectionSignature: AgentCollectionSignature {
        makeAgentCollectionSignature(
            project: appState.currentProject,
            activeWorkflowID: appState.activeWorkflowID
        )
    }

    private func refreshAgentCollectionSnapshot(immediate: Bool = false) {
        agentCollectionRefreshWorkItem?.cancel()

        let refreshToken = UUID()
        agentCollectionRefreshToken = refreshToken

        let update = DispatchWorkItem {
            guard let context = makeAgentCollectionSnapshotContext(
                appState: appState,
                activeWorkflowID: appState.activeWorkflowID
            ) else {
                if agentCollectionRefreshToken == refreshToken {
                    agentCollectionSnapshot = .empty
                }
                return
            }

            DispatchQueue.global(qos: .userInitiated).async {
                let snapshot = makeAgentCollectionSnapshot(context: context)
                DispatchQueue.main.async {
                    guard agentCollectionRefreshToken == refreshToken else { return }
                    agentCollectionSnapshot = snapshot
                }
            }
        }
        agentCollectionRefreshWorkItem = update

        if immediate {
            update.perform()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: update)
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

    private func toggleBatchConnectMode() {
        if isBatchConnectMode {
            cancelBatchConnectionMode()
            return
        }

        isBatchConnectMode = true
        isConnectMode = false
        connectFromAgentID = nil
        batchPreview = nil
        showBatchFeedback(batchLocalizedString("batch_mode_enabled"), isError: false)
    }

    private func assignBatchSourcesFromSelection() {
        let selection = activeNodeSelection()
        guard !selection.isEmpty else {
            showBatchFeedback(batchLocalizedString("select_sources_first"), isError: true)
            return
        }

        isBatchConnectMode = true
        isConnectMode = false
        batchSourceNodeIDs = selection
        batchPreview = nil
        showBatchFeedback(batchLocalizedFormat("batch_sources_selected", selection.count), isError: false)
    }

    private func assignBatchTargetsFromSelection() {
        let selection = activeNodeSelection()
        guard !selection.isEmpty else {
            showBatchFeedback(batchLocalizedString("select_targets_first"), isError: true)
            return
        }

        isBatchConnectMode = true
        isConnectMode = false
        batchTargetNodeIDs = selection
        batchPreview = nil
        showBatchFeedback(batchLocalizedFormat("batch_targets_selected", selection.count), isError: false)
    }

    private func previewBatchConnections() {
        guard !batchSourceNodeIDs.isEmpty else {
            showBatchFeedback(batchLocalizedString("select_sources_first"), isError: true)
            return
        }
        guard !batchTargetNodeIDs.isEmpty else {
            showBatchFeedback(batchLocalizedString("select_targets_first"), isError: true)
            return
        }
        guard let preview = appState.previewBatchConnections(
            sourceNodeIDs: batchSourceNodeIDs,
            targetNodeIDs: batchTargetNodeIDs
        ) else {
            showBatchFeedback(batchLocalizedString("batch_preview_failed"), isError: true)
            return
        }

        batchPreview = preview
        let previewMessage = batchLocalizedSummary(
            created: preview.newEdgeCount,
            duplicate: preview.duplicateCount,
            invalid: preview.invalidCount
        )
        showBatchFeedback(previewMessage, isError: !preview.hasActionableEdges)
    }

    private func commitBatchConnections() {
        guard let result = appState.connectNodesBatch(
            sourceNodeIDs: batchSourceNodeIDs,
            targetNodeIDs: batchTargetNodeIDs,
            bidirectional: connectionType == .bidirectional,
            sharedLabel: batchEdgeLabel,
            sharedColorHex: batchEdgeColorHex,
            requiresApproval: batchRequiresApproval
        ) else {
            showBatchFeedback(batchLocalizedString("batch_commit_failed"), isError: true)
            return
        }

        batchPreview = result.preview
        batchCreatedEdgeIDs = Set(result.createdEdgeIDs)
        batchHighlightedEdgeIDs = Set(result.createdEdgeIDs)
        if !result.createdEdgeIDs.isEmpty {
            let createdEdgeSet = Set(result.createdEdgeIDs)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                if batchHighlightedEdgeIDs == createdEdgeSet {
                    batchHighlightedEdgeIDs.removeAll()
                }
            }
        }
        showBatchFeedback(
            batchLocalizedSummary(
                created: result.createdCount,
                duplicate: result.duplicateCount,
                invalid: result.invalidCount
            ),
            isError: result.createdCount == 0
        )
    }

    private func undoLastBatchConnection() {
        guard !batchCreatedEdgeIDs.isEmpty else { return }
        appState.removeEdges(batchCreatedEdgeIDs)
        let removedCount = batchCreatedEdgeIDs.count
        batchCreatedEdgeIDs.removeAll()
        batchHighlightedEdgeIDs.removeAll()
        batchPreview = nil
        showBatchFeedback(batchLocalizedFormat("batch_undo_success", removedCount), isError: false)
    }

    private func cancelBatchConnectionMode() {
        resetBatchConnectionState(clearCreatedEdges: false)
        showBatchFeedback(batchLocalizedString("batch_mode_cancelled"), isError: false)
    }

    private func resetBatchConnectionState(clearCreatedEdges: Bool = true) {
        isBatchConnectMode = false
        batchSourceNodeIDs.removeAll()
        batchTargetNodeIDs.removeAll()
        batchPreview = nil
        batchEdgeLabel = ""
        batchEdgeColorHex = nil
        batchRequiresApproval = false
        batchHighlightedEdgeIDs.removeAll()
        if clearCreatedEdges {
            batchCreatedEdgeIDs.removeAll()
        }
    }

    private func showBatchFeedback(_ message: String, isError: Bool) {
        let feedback = BatchFeedback(message: message, isError: isError)
        batchFeedback = feedback
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            if batchFeedback == feedback {
                batchFeedback = nil
            }
        }
    }
    
    private func currentWorkflow() -> Workflow? {
        appState.workflow(for: nil)
    }

    private func reconcileSelectionState() {
        let validAgentIDs = Set((appState.currentProject?.agents ?? []).map(\.id))
        if let selectedAgentID = sessionState.selectedAgentID,
           !validAgentIDs.contains(selectedAgentID) {
            sessionState.selectedAgentID = nil
        }

        guard let workflow = currentWorkflow() else {
            selectedNodeID = nil
            selectedNodeIDs.removeAll()
            selectedEdgeID = nil
            selectedBoundaryIDs.removeAll()
            return
        }

        let validNodeIDs = Set(workflow.nodes.map(\.id))
        let validEdgeIDs = Set(workflow.edges.map(\.id))
        let validBoundaryIDs = Set(workflow.boundaries.map(\.id))

        if let selectedNodeID, !validNodeIDs.contains(selectedNodeID) {
            self.selectedNodeID = nil
        }
        selectedNodeIDs = selectedNodeIDs.intersection(validNodeIDs)

        if let selectedEdgeID, !validEdgeIDs.contains(selectedEdgeID) {
            self.selectedEdgeID = nil
        }

        selectedBoundaryIDs = selectedBoundaryIDs.intersection(validBoundaryIDs)
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

    private func deletableActiveNodeSelection() -> Set<UUID> {
        let selection = activeNodeSelection()
        return selection.subtracting(appState.undeletableNodeIDs(in: selection))
    }

    private func boundarySelectionContainsNodeIDs(_ boundary: WorkflowBoundary, selection: Set<UUID>) -> Bool {
        boundary.memberNodeIDs.allSatisfy { selection.contains($0) }
    }

    private func copySelection() {
        copySelection(nodeSelection: nil)
    }

    private func copySelection(nodeSelection: Set<UUID>?) {
        guard let workflow = currentWorkflow() else { return }
        let selection = nodeSelection ?? activeNodeSelection()
        guard !selection.isEmpty else { return }

        copiedNodes = workflow.nodes.filter { selection.contains($0.id) }
        copiedEdges = workflow.edges.filter { selection.contains($0.fromNodeID) && selection.contains($0.toNodeID) }
        copiedBoundaries = workflow.boundaries.filter { selectedBoundaryIDs.contains($0.id) || boundarySelectionContainsNodeIDs($0, selection: selection) }
    }

    private func cutSelection() {
        let selection = deletableActiveNodeSelection()
        guard !selection.isEmpty else { return }
        copySelection(nodeSelection: selection)
        deleteSelection()
    }

    private func pasteSelection() {
        guard !copiedNodes.isEmpty else { return }

        let sourceAgentIDs = copiedNodes.compactMap(\.agentID)
        let duplicatedAgentIDs = appState.duplicateAgentsForWorkflowPaste(sourceAgentIDs)
        let agentNamesByID = Dictionary(uniqueKeysWithValues: (appState.currentProject?.agents ?? []).map { ($0.id, $0.name) })
        var createdNodeIDs: [UUID] = []
        var createdPrimaryAgentID: UUID?

        appState.updateMainWorkflow { workflow in
            var nodeIDMapping: [UUID: UUID] = [:]

            for sourceNode in copiedNodes {
                if sourceNode.type == .start,
                   workflow.nodes.contains(where: { $0.type == .start }) {
                    continue
                }

                var newNode = WorkflowNode(type: sourceNode.type)
                if sourceNode.type == .agent {
                    guard let sourceAgentID = sourceNode.agentID,
                          let duplicatedAgentID = duplicatedAgentIDs[sourceAgentID] else {
                        continue
                    }
                    newNode.agentID = duplicatedAgentID
                    newNode.title = agentNamesByID[duplicatedAgentID] ?? sourceNode.title
                } else {
                    newNode.agentID = sourceNode.agentID
                    newNode.title = sourceNode.title
                }
                newNode.position = CGPoint(x: sourceNode.position.x + 60, y: sourceNode.position.y + 60)
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
                createdNodeIDs.append(newNode.id)
                if createdPrimaryAgentID == nil, let agentID = newNode.agentID {
                    createdPrimaryAgentID = agentID
                }
            }

            for sourceEdge in copiedEdges {
                guard let fromNodeID = nodeIDMapping[sourceEdge.fromNodeID],
                      let toNodeID = nodeIDMapping[sourceEdge.toNodeID] else { continue }

                var newEdge = WorkflowEdge(from: fromNodeID, to: toNodeID)
                newEdge.label = sourceEdge.label
                newEdge.displayColorHex = sourceEdge.displayColorHex
                newEdge.conditionExpression = sourceEdge.conditionExpression
                newEdge.requiresApproval = sourceEdge.requiresApproval
                newEdge.isBidirectional = sourceEdge.isBidirectional
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

        selectedEdgeID = nil
        selectedBoundaryIDs.removeAll()

        if createdNodeIDs.count == 1, let nodeID = createdNodeIDs.first {
            selectedNodeID = nodeID
            selectedNodeIDs.removeAll()
            sessionState.selectedAgentID = createdPrimaryAgentID
            shouldPresentNewNodeProperties = true
        } else if !createdNodeIDs.isEmpty {
            selectedNodeID = nil
            selectedNodeIDs = Set(createdNodeIDs)
            sessionState.selectedAgentID = nil
            shouldPresentNewNodeProperties = false
        }
    }

    private func deleteSelection() {
        let nodeSelection = activeNodeSelection()
        let removedNodeIDs: Set<UUID>
        if !nodeSelection.isEmpty {
            removedNodeIDs = appState.removeNodes(nodeSelection)
        } else {
            removedNodeIDs = []
        }
        let survivingNodeIDs = nodeSelection.subtracting(removedNodeIDs)
        if !selectedBoundaryIDs.isEmpty {
            appState.removeBoundaries(selectedBoundaryIDs)
        }
        if removedNodeIDs.isEmpty && selectedBoundaryIDs.isEmpty {
            return
        }

        if survivingNodeIDs.isEmpty {
            selectedNodeID = nil
            selectedNodeIDs.removeAll()
        } else if survivingNodeIDs.count == 1 {
            selectedNodeID = survivingNodeIDs.first
            selectedNodeIDs.removeAll()
        } else {
            selectedNodeID = nil
            selectedNodeIDs = survivingNodeIDs
        }

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
        let nodeID = appState.focusAgentNode(
            agentID: agent.id,
            createIfMissing: true,
            suggestedPosition: CGPoint(x: 300, y: 200)
        )

        selectedNodeID = nodeID
        selectedNodeIDs.removeAll()
        selectedEdgeID = nil
        selectedBoundaryIDs.removeAll()
        sessionState.selectedAgentID = agent.id
        shouldPresentNewNodeProperties = nodeID != nil
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

    private func resolveNodeID(for identifier: UUID, preferredIndex: Int) -> UUID? {
        guard let workflow = currentWorkflow() else { return nil }

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

private struct BackgroundRetainedPane: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(width: 0, height: 0)
            .clipped()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

// MARK: - 工具栏
struct EditorToolbar: View {
    @EnvironmentObject var appState: AppState
    let currentWorkflowName: String
    let workflows: [Workflow]
    let activeWorkflowID: UUID?
    @Binding var viewMode: WorkflowEditorView.EditorViewMode
    @Binding var selectedNodeID: UUID?
    @Binding var selectedNodeIDs: Set<UUID>
    @Binding var selectedEdgeID: UUID?
    @Binding var selectedBoundaryIDs: Set<UUID>
    @Binding var isConnectMode: Bool
    @Binding var isBatchConnectMode: Bool
    @Binding var isLassoMode: Bool
    @Binding var connectionType: WorkflowEditorView.ConnectionType
    @Binding var connectFromAgentID: UUID?
    let batchSourceCount: Int
    let batchTargetCount: Int
    let batchPreviewCount: Int
    let batchCanCommit: Bool
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
    var onToggleBatchConnectMode: () -> Void
    var onAssignBatchSources: () -> Void
    var onAssignBatchTargets: () -> Void
    var onPreviewBatchConnections: () -> Void
    var onCommitBatchConnections: () -> Void
    var onCancelBatchConnections: () -> Void
    var onSelectWorkflow: (UUID) -> Void
    var onImportWorkflowPackage: () -> Void
    var onExportWorkflowPackage: () -> Void
    var onApplyWorkflow: () -> Void
    var onSyncWorkflowSession: () -> Void

    @State private var quickAddTemplateID: String = AgentTemplateCatalog.defaultTemplateID

    private var hasNodeSelection: Bool {
        selectedNodeID != nil || !selectedNodeIDs.isEmpty
    }

    private var deletableNodeCandidateSelection: Set<UUID> {
        if !selectedNodeIDs.isEmpty {
            return selectedNodeIDs
        }
        if let selectedNodeID {
            return [selectedNodeID]
        }
        return []
    }

    private var hasDeletableNodeSelection: Bool {
        !deletableNodeCandidateSelection
            .subtracting(appState.undeletableNodeIDs(in: deletableNodeCandidateSelection))
            .isEmpty
    }

    private var activeNodeCount: Int {
        if !selectedNodeIDs.isEmpty {
            return selectedNodeIDs.count
        }
        return selectedNodeID == nil ? 0 : 1
    }

    private var hasBoundarySelection: Bool {
        !selectedBoundaryIDs.isEmpty
    }

    private var hasDeleteTarget: Bool {
        hasDeletableNodeSelection || hasBoundarySelection || selectedEdgeID != nil
    }

    private var applyWorkflowButtonTitle: String {
        appState.isApplyingWorkflowConfiguration
            ? LocalizedString.text("applying")
            : LocalizedString.text("apply_workflow_to_mirror")
    }

    private var applyWorkflowButtonTooltip: String {
        appState.hasPendingWorkflowConfiguration
            ? LocalizedString.text("apply_workflow_to_mirror_tooltip")
            : LocalizedString.text("apply_workflow_tooltip_idle")
    }

    private var syncWorkflowButtonTitle: String {
        appState.isSyncingOpenClawSession
            ? LocalizedString.text("syncing_current_session")
            : LocalizedString.text("sync_current_session")
    }

    private var syncWorkflowButtonTooltip: String {
        if appState.isSyncingOpenClawSession {
            return LocalizedString.text("syncing_current_session_tooltip")
        }

        if appState.hasPendingOpenClawSessionSync {
            if !appState.openClawManager.canAttachProject {
                return LocalizedString.text("sync_current_session_connect_required_tooltip")
            }

            if appState.openClawManager.config.deploymentKind == .remoteServer {
                return LocalizedString.text("sync_current_session_remote_unsupported_tooltip")
            }

            return LocalizedString.text("sync_current_session_tooltip")
        }

        return LocalizedString.text("sync_current_session_tooltip_idle")
    }

    private var shouldShowWorkflowSyncStatus: Bool {
        appState.isSyncingOpenClawSession || appState.hasPendingOpenClawSessionSync
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            WorkflowToolbarGroup(title: "Workflow") {
                HStack(spacing: 8) {
                    Menu {
                        ForEach(workflows) { workflow in
                            Button {
                                onSelectWorkflow(workflow.id)
                            } label: {
                                Label(
                                    workflow.name,
                                    systemImage: workflow.id == activeWorkflowID ? "checkmark.circle.fill" : "circle"
                                )
                            }
                        }
                    } label: {
                        toolbarMenuLabel(title: currentWorkflowName, systemName: "point.3.connected.trianglepath.dotted")
                    }
                    .menuStyle(.borderlessButton)

                    Menu {
                        Button("导入设计包", action: onImportWorkflowPackage)
                        Button("导出当前设计包", action: onExportWorkflowPackage)
                            .disabled(workflows.isEmpty)
                    } label: {
                        toolbarMenuLabel(title: "设计包", systemName: "shippingbox")
                    }
                    .menuStyle(.borderlessButton)
                }
            }

            WorkflowToolbarGroup(title: LocalizedString.text("workflow_toolbar_view")) {
                HStack(spacing: 8) {
                    ForEach(WorkflowEditorView.EditorViewMode.allCases, id: \.self) { mode in
                        toolbarModeButton(mode)
                    }
                }
            }

            WorkflowToolbarGroup(title: LocalizedString.text("workflow_toolbar_editing")) {
                HStack(spacing: 8) {
                    Group {
                        TemplatePickerButton(
                            selectedTemplateID: $quickAddTemplateID,
                            onSelect: { template in
                                onAddNodeWithTemplate(template.id)
                            },
                            labelTitle: LocalizedString.text("add_node_toolbar"),
                            labelSystemImage: "plus.circle",
                            blankActionTitle: LocalizedString.text("new_blank_agent_node"),
                            onCreateBlank: {
                                onAddNode()
                            },
                            existingAgents: appState.currentProject?.agents ?? [],
                            onSelectExistingAgent: { agent in
                                appState.addAgentNode(agentName: agent.name, position: CGPoint(x: 300, y: 200))
                            },
                            variant: .toolbar
                        )
                        toolbarIconButton(
                            systemName: "align.horizontal.left",
                            action: { onAlignSelected(.left) },
                            tooltip: LocalizedString.text("align_left")
                        )
                        .disabled(!hasNodeSelection)

                        toolbarIconButton(
                            systemName: "align.horizontal.center",
                            action: { onAlignSelected(.center) },
                            tooltip: LocalizedString.text("align_center")
                        )
                        .disabled(!hasNodeSelection)

                        toolbarIconButton(
                            systemName: "align.horizontal.right",
                            action: { onAlignSelected(.right) },
                            tooltip: LocalizedString.text("align_right")
                        )
                        .disabled(!hasNodeSelection)

                        toolbarIconButton(
                            systemName: "align.vertical.top",
                            action: { onAlignSelected(.top) },
                            tooltip: LocalizedString.text("align_top")
                        )
                        .disabled(!hasNodeSelection)

                        toolbarIconButton(
                            systemName: "align.vertical.center",
                            action: { onAlignSelected(.middle) },
                            tooltip: LocalizedString.text("align_middle")
                        )
                        .disabled(!hasNodeSelection)

                        toolbarIconButton(
                            systemName: "align.vertical.bottom",
                            action: { onAlignSelected(.bottom) },
                            tooltip: LocalizedString.text("align_bottom")
                        )
                        .disabled(!hasNodeSelection)

                        toolbarIconButton(
                            systemName: "arrow.left.and.right",
                            action: { onDistributeSelected(.horizontal) },
                            tooltip: LocalizedString.text("distribute_horizontally")
                        )
                        .disabled(activeNodeCount < 3)

                        toolbarIconButton(
                            systemName: "arrow.up.and.down",
                            action: { onDistributeSelected(.vertical) },
                            tooltip: LocalizedString.text("distribute_vertically")
                        )
                        .disabled(activeNodeCount < 3)
                    }

                    toolbarSectionDivider()

                    toolbarIconToggleButton(
                        systemName: isConnectMode ? "link.circle.fill" : "link.circle",
                        title: LocalizedString.text("connect_toolbar"),
                        action: toggleConnectMode,
                        isActive: isConnectMode,
                        tooltip: isConnectMode ? LocalizedString.text("connect_cancel_tooltip") : LocalizedString.text("connect_prepare_tooltip"),
                        prominent: true
                    )

                    if isConnectMode {
                        connectionTypeButton(type: .unidirectional)
                        connectionTypeButton(type: .bidirectional)
                    }

                    toolbarIconToggleButton(
                        systemName: isBatchConnectMode ? "square.stack.3d.up.fill" : "square.stack.3d.up",
                        title: batchLocalizedString("batch_connect"),
                        action: onToggleBatchConnectMode,
                        isActive: isBatchConnectMode,
                        tooltip: batchLocalizedString("batch_connect_help")
                    )

                    if isBatchConnectMode {
                        connectionTypeButton(type: .unidirectional)
                        connectionTypeButton(type: .bidirectional)

                        toolbarIconButton(
                            systemName: "arrow.up.circle",
                            title: batchSourceCount > 0 ? batchLocalizedFormat("batch_sources_short", batchSourceCount) : batchLocalizedString("set_sources"),
                            action: onAssignBatchSources,
                            tooltip: batchLocalizedString("set_sources_help"),
                            prominent: batchSourceCount > 0
                        )

                        toolbarIconButton(
                            systemName: "arrow.down.circle",
                            title: batchTargetCount > 0 ? batchLocalizedFormat("batch_targets_short", batchTargetCount) : batchLocalizedString("set_targets"),
                            action: onAssignBatchTargets,
                            tooltip: batchLocalizedString("set_targets_help"),
                            prominent: batchTargetCount > 0
                        )

                        toolbarIconButton(
                            systemName: "sparkles.rectangle.stack",
                            title: batchPreviewCount > 0 ? batchLocalizedFormat("preview_count_short", batchPreviewCount) : batchLocalizedString("preview"),
                            action: onPreviewBatchConnections,
                            tooltip: batchLocalizedString("preview_help"),
                            prominent: batchSourceCount > 0 && batchTargetCount > 0
                        )

                        toolbarIconButton(
                            systemName: "checkmark.circle",
                            title: batchPanelActionText("create_now"),
                            action: onCommitBatchConnections,
                            tooltip: batchLocalizedString("create_now_help"),
                            prominent: batchCanCommit
                        )
                        .disabled(!batchCanCommit)

                        toolbarIconButton(
                            systemName: "xmark.circle",
                            title: batchLocalizedString("cancel"),
                            action: onCancelBatchConnections,
                            tooltip: batchLocalizedString("cancel_help")
                        )
                    }

                    toolbarIconButton(
                        systemName: "arrow.triangle.branch",
                        title: LocalizedString.text("organize_connections"),
                        action: onOrganizeConnections,
                        tooltip: LocalizedString.text("organize_connections")
                    )

                    toolbarSectionDivider()

                    Menu {
                        Button(LocalizedString.text("add_boundary")) { onAddBoundary() }
                            .disabled(!hasNodeSelection)
                        Button(LocalizedString.text("remove_boundary")) { onDeleteBoundary() }
                            .disabled(selectedBoundaryIDs.isEmpty && !hasNodeSelection)
                    } label: {
                        toolbarMenuLabel(title: LocalizedString.text("boundary"), systemName: "square.dashed")
                    }
                    .menuStyle(.borderlessButton)

                    toolbarSectionDivider()

                    toolbarIconButton(
                        systemName: "arrow.uturn.backward",
                        title: LocalizedString.undo,
                        action: { appState.undoWorkflowChange() },
                        tooltip: LocalizedString.undo
                    )
                    .disabled(!appState.canUndoWorkflowChange)

                    toolbarIconButton(
                        systemName: "arrow.uturn.forward",
                        title: LocalizedString.redo,
                        action: { appState.redoWorkflowChange() },
                        tooltip: LocalizedString.redo
                    )
                    .disabled(!appState.canRedoWorkflowChange)

                    toolbarIconButton(
                        systemName: "trash",
                        title: LocalizedString.delete,
                        action: handleDeleteAction,
                        tooltip: LocalizedString.delete
                    )
                    .disabled(!hasDeleteTarget)

                    toolbarIconButton(
                        systemName: "list.bullet.clipboard",
                        title: LocalizedString.text("tasks_toolbar"),
                        action: onGenerateTasks,
                        tooltip: LocalizedString.text("generate_tasks_tooltip")
                    )

                    toolbarIconButton(
                        systemName: appState.hasPendingWorkflowConfiguration ? "checkmark.seal.fill" : "checkmark.seal",
                        title: applyWorkflowButtonTitle,
                        action: onApplyWorkflow,
                        tooltip: applyWorkflowButtonTooltip,
                        prominent: appState.hasPendingWorkflowConfiguration && !appState.isApplyingWorkflowConfiguration
                    )
                    .disabled(!appState.hasPendingWorkflowConfiguration || appState.isApplyingWorkflowConfiguration)

                    toolbarIconButton(
                        systemName: appState.hasPendingOpenClawSessionSync ? "arrow.clockwise.circle.fill" : "arrow.clockwise.circle",
                        title: syncWorkflowButtonTitle,
                        action: onSyncWorkflowSession,
                        tooltip: syncWorkflowButtonTooltip,
                        prominent: appState.hasPendingOpenClawSessionSync && !appState.isSyncingOpenClawSession
                    )
                    .disabled(!appState.canSyncOpenClawSessionFromWorkflow)

                    toolbarIconButton(
                        systemName: "square.and.arrow.down.on.square",
                        title: LocalizedString.text("save_draft"),
                        action: { appState.saveDraft() },
                        tooltip: LocalizedString.text("save_draft_tooltip")
                    )
                    .disabled(appState.currentProject == nil)
                }
            }

            if hasNodeSelection || selectedEdgeID != nil {
                WorkflowToolbarGroup(title: LocalizedString.text("workflow_toolbar_style")) {
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
                                    styleMenuResetLabel(title: LocalizedString.text("reset_node_color"))
                                }
                            } label: {
                                toolbarMenuLabel(title: LocalizedString.text("node_color"), systemName: "paintpalette")
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
                                    styleMenuResetLabel(title: LocalizedString.text("reset_edge_color"))
                                }
                            } label: {
                                toolbarMenuLabel(title: LocalizedString.text("edge_color"), systemName: "scribble.variable")
                            }
                            .menuStyle(.borderlessButton)
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            if appState.isSavingDraft
                || appState.lastDraftSaveTime != nil
                || showsWorkflowRuntimeStatus {
                VStack(alignment: .trailing, spacing: 8) {
                    if appState.isSavingDraft || appState.lastDraftSaveTime != nil {
                        HStack(spacing: 8) {
                            toolbarSaveStatusView
                        }
                    }

                    workflowRuntimeStatusStack
                }
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
                Text(mode.displayTitle)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .frame(minWidth: 82)
            .fixedSize(horizontal: true, vertical: false)
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
        .help(mode.displayTitle)
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

    private func toolbarSectionDivider() -> some View {
        Rectangle()
            .fill(Color.black.opacity(0.08))
            .frame(width: 1, height: 28)
            .padding(.horizontal, 2)
    }

    private func selectAllItems() {
        guard let workflow = appState.workflow(for: nil) else { return }
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
        tooltip: String,
        prominent: Bool = false
    ) -> some View {
        Button(action: action) {
            toolbarActionLabel(
                systemName: systemName,
                title: title,
                isActive: false,
                prominent: prominent
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
            if isBatchConnectMode {
                isConnectMode = false
            } else {
                isConnectMode = true
            }
        }) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13.5, weight: .semibold))
                Text(type == .unidirectional ? LocalizedString.text("connection_one_way") : LocalizedString.text("connection_two_way"))
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

    private func handleDeleteAction() {
        if selectedEdgeID != nil && !hasNodeSelection && !hasBoundarySelection {
            onDeleteSelectedEdge()
        } else {
            onDeleteSelection()
        }
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
        if appState.isSavingDraft {
            HStack(spacing: 6) {
                ProgressView()
                    .scaleEffect(0.65)
                Text(LocalizedString.text("saving_draft"))
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
        } else if let lastSave = appState.lastDraftSaveTime {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text(draftStatusText(for: lastSave))
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

    private func draftStatusText(for date: Date) -> String {
        let formattedDate = date.formatted(date: .omitted, time: .shortened)
        switch appState.lastDraftSaveKind {
        case .automatic:
            return LocalizedString.format("draft_auto_saved_at", formattedDate)
        case .restored:
            return LocalizedString.format("draft_restored_at", formattedDate)
        case .manual, .none:
            return LocalizedString.format("draft_saved_at", formattedDate)
        }
    }

    private var showsWorkflowRuntimeStatus: Bool {
        appState.openClawRevisionSummary != nil
            || appState.openClawLatestRuntimeSyncSummary != nil
            || appState.currentOpenClawRuntimeControlPlaneEntry.status != .ready
            || appState.openClawRuntimeControlPlaneSecondarySummary != nil
    }

    @ViewBuilder
    private var workflowRuntimeStatusStack: some View {
        if showsWorkflowRuntimeStatus {
            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 8) {
                    if let revisionSummary = appState.openClawRevisionSummary {
                        workflowRevisionStatusView(revisionSummary)
                    }

                    if let runtimeSyncSummary = appState.openClawLatestRuntimeSyncSummary {
                        workflowRuntimeSyncReceiptStatusView(runtimeSyncSummary)
                    }
                }

                if appState.currentOpenClawRuntimeControlPlaneEntry.status != .ready {
                    workflowRuntimeSyncDiagnosticView(appState.openClawRuntimeControlPlaneSummary)
                        .frame(maxWidth: 420, alignment: .trailing)
                }

                if let secondarySummary = appState.openClawRuntimeControlPlaneSecondarySummary {
                    workflowRuntimeSyncDiagnosticView(secondarySummary)
                        .frame(maxWidth: 420, alignment: .trailing)
                }
            }
        }
    }

    private var workflowApplyStatusView: some View {
        let pendingCount = max(1, appState.pendingWorkflowConfigurationRevisionDelta)

        return HStack(spacing: 6) {
            Image(systemName: "clock.badge.exclamationmark")
                .foregroundColor(.orange)
            Text(LocalizedString.format("workflow_apply_pending_count", pendingCount))
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

    private var workflowSessionSyncStatusView: some View {
        let label: String
        let iconName: String
        let iconColor: Color

        if appState.isSyncingOpenClawSession {
            label = LocalizedString.text("syncing_current_session")
            iconName = "arrow.clockwise.circle.fill"
            iconColor = .accentColor
        } else if appState.openClawManager.config.deploymentKind == .remoteServer {
            label = LocalizedString.text("workflow_session_sync_remote_unavailable")
            iconName = "exclamationmark.triangle.fill"
            iconColor = .orange
        } else if appState.openClawManager.isConnected {
            label = LocalizedString.text("workflow_session_sync_pending")
            iconName = "arrow.clockwise.circle"
            iconColor = .orange
        } else {
            label = LocalizedString.text("workflow_session_sync_connect_required")
            iconName = "bolt.horizontal.circle"
            iconColor = .orange
        }

        return HStack(spacing: 6) {
            Image(systemName: iconName)
                .foregroundColor(iconColor)
            Text(label)
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

    private func workflowAppliedStatusView(_ lastApplied: Date) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundColor(.green)
            Text(LocalizedString.format("workflow_applied_at", lastApplied.formatted(date: .omitted, time: .shortened)))
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

    private func workflowRevisionStatusView(_ summary: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .foregroundColor(.blue)
            Text(summary)
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

    private func workflowRuntimeSyncReceiptStatusView(_ summary: String) -> some View {
        let iconColor: Color
        let iconName: String

        switch appState.latestOpenClawRuntimeSyncReceipt?.status {
        case .succeeded:
            iconColor = .green
            iconName = "checkmark.circle.fill"
        case .partial:
            iconColor = .orange
            iconName = "exclamationmark.triangle.fill"
        case .failed:
            iconColor = .red
            iconName = "xmark.circle.fill"
        case .none:
            iconColor = .secondary
            iconName = "clock.badge.questionmark"
        }

        return HStack(spacing: 6) {
            Image(systemName: iconName)
                .foregroundColor(iconColor)
            Text(summary)
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

    private func workflowRuntimeSyncDiagnosticView(_ detail: String) -> some View {
        let color: Color = appState.latestOpenClawRuntimeSyncReceipt?.status == .failed ? .red : .orange

        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: appState.latestOpenClawRuntimeSyncReceipt?.status == .failed ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(color)
                .padding(.top, 1)
            Text(detail)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(color.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(color.opacity(0.16), lineWidth: 1)
        )
    }

    private func toggleConnectMode() {
        withAnimation(.easeInOut(duration: 0.15)) {
            isConnectMode.toggle()
            if isConnectMode {
                isLassoMode = false
                isBatchConnectMode = false
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
    case connections = "Connections"

    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .updated: return LocalizedString.text("sort_recently_updated")
        case .name: return LocalizedString.text("sort_name")
        case .connections: return LocalizedString.text("sort_connections")
        }
    }
}

private enum AgentCollectionFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case onCanvas = "On Canvas"
    case withSoulFile = "With SOUL"
    case attention = "Needs Attention"

    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .all: return LocalizedString.text("filter_all")
        case .onCanvas: return LocalizedString.text("filter_on_canvas")
        case .withSoulFile: return LocalizedString.text("filter_with_soul")
        case .attention: return LocalizedString.text("filter_needs_attention")
        }
    }
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
    var soulDisplayName: String { soulSourcePath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? LocalizedString.text("project_cache_only") }
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

private struct AgentCollectionSnapshotContext {
    let project: MAProject
    let activeWorkflowID: UUID?
    let managedWorkspacePathsByAgentID: [UUID: String]
}

private struct AgentCollectionSignature: Equatable {
    let projectID: UUID?
    let workflowID: UUID?
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

private func makeAgentCollectionSignature(project: MAProject?, activeWorkflowID: UUID?) -> AgentCollectionSignature {
    let workflow = resolvedAgentCollectionWorkflow(in: project, activeWorkflowID: activeWorkflowID)

    return AgentCollectionSignature(
        projectID: project?.id,
        workflowID: workflow?.id,
        projectUpdatedAt: project?.updatedAt,
        runtimeUpdatedAt: project?.runtimeState.lastUpdated,
        agentCount: project?.agents.count ?? 0,
        nodeCount: workflow?.nodes.count ?? 0,
        edgeCount: workflow?.edges.count ?? 0
    )
}

private func makeAgentCollectionSnapshotContext(appState: AppState, activeWorkflowID: UUID?) -> AgentCollectionSnapshotContext? {
    guard let project = appState.currentProject else { return nil }

    var managedWorkspacePathsByAgentID: [UUID: String] = [:]
    managedWorkspacePathsByAgentID.reserveCapacity(project.agents.count)

    for workflow in project.workflows {
        for node in workflow.nodes where node.type == .agent {
            guard let agentID = node.agentID, managedWorkspacePathsByAgentID[agentID] == nil else { continue }

            let managedWorkspaceURL = ProjectFileSystem.shared.nodeOpenClawWorkspaceDirectory(
                for: node.id,
                workflowID: workflow.id,
                projectID: project.id,
                under: ProjectManager.shared.appSupportRootDirectory
            )
            managedWorkspacePathsByAgentID[agentID] = managedWorkspaceURL.path
        }
    }

    return AgentCollectionSnapshotContext(
        project: project,
        activeWorkflowID: activeWorkflowID,
        managedWorkspacePathsByAgentID: managedWorkspacePathsByAgentID
    )
}

private func makeAgentCollectionSnapshot(context: AgentCollectionSnapshotContext) -> AgentCollectionSnapshot {
    let project = context.project

    let workflow = resolvedAgentCollectionWorkflow(in: project, activeWorkflowID: context.activeWorkflowID)
    let nodes = workflow?.nodes ?? []
    let soulSourcePaths = makeAgentCollectionSoulSourcePaths(context: context)
    let connectionCounts = workflow?.connectionCountsByNodeID() ?? [:]

    var nodeIDsByAgentID: [UUID: UUID] = [:]
    for node in nodes where node.type == .agent {
        guard let agentID = node.agentID, nodeIDsByAgentID[agentID] == nil else { continue }
        nodeIDsByAgentID[agentID] = node.id
    }

    let items = project.agents.map { agent in
        let nodeID = nodeIDsByAgentID[agent.id]
        let soulPath = soulSourcePaths[agent.id] ?? nil
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
            incomingConnections: nodeID.flatMap { connectionCounts[$0]?.incoming } ?? 0,
            outgoingConnections: nodeID.flatMap { connectionCounts[$0]?.outgoing } ?? 0
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

private func resolvedAgentCollectionWorkflow(in project: MAProject?, activeWorkflowID: UUID?) -> Workflow? {
    guard let project else { return nil }
    if let activeWorkflowID {
        return project.workflows.first(where: { $0.id == activeWorkflowID }) ?? project.workflows.first
    }
    return project.workflows.first
}

private func makeAgentCollectionSoulSourcePaths(context: AgentCollectionSnapshotContext) -> [UUID: String?] {
    let project = context.project

    return Dictionary(uniqueKeysWithValues: project.agents.map { agent in
        (
            agent.id,
            fastAgentCollectionSoulSourcePath(for: agent, context: context)
        )
    })
}

private func fastAgentCollectionSoulSourcePath(
    for agent: Agent,
    context: AgentCollectionSnapshotContext
) -> String? {
    if let managedWorkspacePath = context.managedWorkspacePathsByAgentID[agent.id],
       FileManager.default.fileExists(atPath: managedWorkspacePath) {
        let managedWorkspaceURL = URL(fileURLWithPath: managedWorkspacePath, isDirectory: true)
        for fileName in ProjectFileSystem.managedOpenClawWorkspaceMarkdownFiles {
            let documentURL = managedWorkspaceURL.appendingPathComponent(fileName, isDirectory: false)
            if FileManager.default.fileExists(atPath: documentURL.path) {
                return documentURL.path
            }
        }
    }

    return nil
}

private func runtimePresentation(for rawStatus: String?) -> (label: String, systemImage: String, color: Color, isProblem: Bool) {
    let status = rawStatus?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""

    switch status {
    case "", "idle", "ready":
        return (LocalizedString.text("status_ready"), "checkmark.circle.fill", .green, false)
    case "running":
        return (LocalizedString.text("status_running"), "bolt.circle.fill", .blue, false)
    case "reloaded":
        return (LocalizedString.text("status_reloaded"), "arrow.clockwise.circle.fill", .green, false)
    case "reload_failed", "error", "failed":
        return (LocalizedString.text("status_needs_reload"), "exclamationmark.triangle.fill", .orange, true)
    case "stopped":
        return (LocalizedString.text("status_stopped"), "pause.circle.fill", .secondary, true)
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
                    TextField(LocalizedString.text("agent_search_placeholder"), text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color(.controlBackgroundColor))
                .cornerRadius(10)

                Picker(LocalizedString.text("filter_label"), selection: $filter) {
                    ForEach(AgentCollectionFilter.allCases) { option in
                        Text(option.displayTitle).tag(option)
                    }
                }
                .pickerStyle(.menu)

                Picker(LocalizedString.text("sort_label"), selection: $sort) {
                    ForEach(AgentCollectionSort.allCases) { option in
                        Text(option.displayTitle).tag(option)
                    }
                }
                .pickerStyle(.menu)
            }

            HStack(spacing: 8) {
                AgentCollectionBadge(systemImage: "person.3.fill", text: LocalizedString.format("visible_count", visibleCount, snapshot.items.count))
                AgentCollectionBadge(systemImage: "square.grid.2x2", text: LocalizedString.format("on_canvas_count", snapshot.onCanvasCount))
                AgentCollectionBadge(systemImage: "doc.text.fill", text: LocalizedString.format("with_soul_count", snapshot.withSoulCount))
                AgentCollectionBadge(systemImage: "exclamationmark.triangle.fill", text: LocalizedString.format("need_attention_count", snapshot.attentionCount))
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
            Text(LocalizedString.text("no_agents_match_filter"))
                .font(.headline)
            if !searchText.isEmpty {
                Text(LocalizedString.text("try_adjust_search"))
                    .foregroundColor(.secondary)
            } else {
                Text(LocalizedString.text("no_agents_in_category"))
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
    var onRevealManagedConfig: () -> Void
    var onOpenWorkspace: () -> Void
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
            Label(LocalizedString.text("focus_agent"), systemImage: "scope")
        }

        Button(action: onEdit) {
            Label(LocalizedString.text("edit_soul_md"), systemImage: "pencil.and.outline")
        }

        Button(action: onRevealManagedConfig) {
            Label(item.hasSoulFile ? LocalizedString.text("reveal_soul_md") : LocalizedString.text("reveal_expected_soul"), systemImage: "doc.text.magnifyingglass")
        }

        Button(action: onOpenWorkspace) {
            Label(LocalizedString.text("open_workspace"), systemImage: "folder")
        }

        Divider()

        Button(action: onManageSkills) {
            Label(LocalizedString.text("manage_skills"), systemImage: "star")
        }

        Button(action: onConfigurePermissions) {
            Label(LocalizedString.text("configure_permissions"), systemImage: "lock.shield")
        }

        Divider()

        Button(action: onCopy) {
            Label(LocalizedString.copy, systemImage: "doc.on.doc")
        }

        Button(action: onCut) {
            Label(LocalizedString.cut, systemImage: "scissors")
        }

        Button(action: onPaste) {
            Label(LocalizedString.paste, systemImage: "doc.on.clipboard")
        }
        .disabled(!canPaste)

        Button(action: onDuplicate) {
            Label(LocalizedString.text("duplicate"), systemImage: "plus.square.on.square")
        }

        Button(action: onExport) {
            Label(LocalizedString.text("export_action"), systemImage: "square.and.arrow.up")
        }

        Button(action: onReset) {
            Label(LocalizedString.text("reset_action"), systemImage: "arrow.counterclockwise")
        }

        Divider()

        Button(role: .destructive, action: onDelete) {
            Label(LocalizedString.delete, systemImage: "trash")
        }
    }
}

// MARK: - 列表视图
private struct AgentListView: View {
    @EnvironmentObject var appState: AppState
    let snapshot: AgentCollectionSnapshot
    let collectionSignature: AgentCollectionSignature
    let isActive: Bool
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
    @State private var visibleItems: [AgentCollectionItem] = []
    @State private var canPasteFromPasteboard = false
    @State private var pendingVisibleItemsRefresh = false

    private var items: [AgentCollectionItem] {
        snapshot.items
    }

    var body: some View {
        VStack(spacing: 0) {
            AgentCollectionToolbar(
                searchText: $searchText,
                filter: $filter,
                sort: $sort,
                snapshot: snapshot,
                visibleCount: visibleItems.count,
                feedback: feedback
            )

            Divider()

            if visibleItems.isEmpty {
                AgentCollectionEmptyState(searchText: searchText)
            } else {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Text(LocalizedString.text("status_header")).frame(width: 120, alignment: .leading)
                        Text(LocalizedString.text("agent_header")).frame(minWidth: 220, alignment: .leading)
                        Text(LocalizedString.text("model_header")).frame(minWidth: 170, alignment: .leading)
                        Text(LocalizedString.text("connections_header")).frame(width: 110, alignment: .leading)
                        Text(LocalizedString.text("soul_header")).frame(minWidth: 170, alignment: .leading)
                        Text(LocalizedString.text("actions_header")).frame(width: isConnectMode ? 210 : 180, alignment: .center)
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
                                onRevealSoul: { revealManagedConfigFile(for: item.agent.id) },
                                onDuplicate: { duplicateAgent(item.agent.id) },
                                onDelete: { deleteCandidate = currentAgent(id: item.agent.id) ?? item.agent },
                                onConnect: { targetID in connect(sourceID: connectFromAgentID, targetID: targetID) }
                            )
                            .contextMenu {
                                AgentContextMenuContent(
                                    item: item,
                                    canPaste: canPasteFromPasteboard,
                                    onOpen: { selectAgent(item.agent.id, focusNode: true) },
                                    onRevealManagedConfig: { revealManagedConfigFile(for: item.agent.id) },
                                    onOpenWorkspace: { openWorkspace(for: item.agent.id) },
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
        .alert(LocalizedString.text("delete_agent_title"), isPresented: deleteConfirmationBinding) {
            Button(LocalizedString.delete, role: .destructive) {
                if let candidate = deleteCandidate {
                    appState.deleteAgent(candidate.id)
                    if selectedAgentID == candidate.id {
                        selectedAgentID = nil
                    }
                    showFeedback(LocalizedString.format("deleted_agent", candidate.name), isError: false)
                }
                deleteCandidate = nil
            }
            Button(LocalizedString.cancel, role: .cancel) {
                deleteCandidate = nil
            }
        } message: {
            Text(deleteCandidate.map { LocalizedString.format("delete_agent_message", $0.name) } ?? "")
        }
        .onAppear {
            canPasteFromPasteboard = NSPasteboard.general.canReadObject(forClasses: [NSString.self], options: nil)
            handleVisibleItemsChange(force: true)
        }
        .onChange(of: collectionSignature) { _, _ in
            handleVisibleItemsChange()
        }
        .onChange(of: searchText) { _, _ in
            handleVisibleItemsChange()
        }
        .onChange(of: filter) { _, _ in
            handleVisibleItemsChange()
        }
        .onChange(of: sort) { _, _ in
            handleVisibleItemsChange()
        }
        .onChange(of: isActive) { _, newValue in
            guard newValue else { return }
            if pendingVisibleItemsRefresh || visibleItems.isEmpty {
                refreshVisibleItems()
            }
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
        guard appState.ensureAgentNode(agentID: agentID, suggestedPosition: .zero) != nil,
              let agent = currentAgent(id: agentID) else { return }
        selectAgent(agentID, focusNode: false)
        editingAgent = agent
    }

    private func connect(sourceID: UUID?, targetID: UUID) {
        guard let sourceID else { return }
        onConnect(sourceID, targetID)
    }

    private func revealManagedConfigFile(for agentID: UUID) {
        if let configURL = appState.managedAgentPrimaryConfigURL(for: agentID) {
            NSWorkspace.shared.activateFileViewerSelecting([configURL])
            showFeedback(LocalizedString.format("revealed_file", configURL.lastPathComponent), isError: false)
        } else {
            showFeedback(LocalizedString.text("no_real_soul_file"), isError: true)
        }
    }

    private func openWorkspace(for agentID: UUID) {
        if let workspaceURL = appState.agentWorkspaceURL(for: agentID) {
            NSWorkspace.shared.open(workspaceURL)
            showFeedback(LocalizedString.format("opened_workspace", workspaceURL.lastPathComponent), isError: false)
        } else {
            showFeedback(LocalizedString.text("no_workspace_directory"), isError: true)
        }
    }

    private func copyAgent(_ agentID: UUID) {
        guard let agent = currentAgent(id: agentID) else { return }
        let success = appState.copyAgent(agent)
        showFeedback(success ? LocalizedString.format("copied_agent", agent.name) : LocalizedString.text("copy_failed"), isError: !success)
    }

    private func cutAgent(_ agentID: UUID) {
        let success = appState.cutAgent(agentID)
        if success, selectedAgentID == agentID {
            selectedAgentID = nil
        }
        let agentName = currentAgent(id: agentID)?.name ?? "agent"
        showFeedback(success ? LocalizedString.format("cut_agent", agentName) : LocalizedString.text("cut_failed"), isError: !success)
    }

    private func pasteAgent() {
        if let newAgent = appState.pasteAgentFromPasteboard() {
            selectedAgentID = newAgent.id
            showFeedback(LocalizedString.format("pasted_agent", newAgent.name), isError: false)
        } else {
            showFeedback(LocalizedString.text("paste_failed"), isError: true)
        }
    }

    private func duplicateAgent(_ agentID: UUID) {
        if let newAgent = appState.duplicateAgent(agentID, suffix: LocalizedString.text("duplicate_suffix"), offset: CGPoint(x: 50, y: 50)) {
            selectedAgentID = newAgent.id
            showFeedback(LocalizedString.format("duplicated_agent", newAgent.name), isError: false)
        } else {
            showFeedback(LocalizedString.text("duplicate_failed"), isError: true)
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
                    showFeedback(LocalizedString.format("exported_agent", agent.name), isError: false)
                } catch {
                    showFeedback(LocalizedString.format("export_failed", error.localizedDescription), isError: true)
                }
            }
        }
    }

    private func resetAgent(_ agentID: UUID) {
        guard var agent = currentAgent(id: agentID) else { return }
        agent.updatedAt = Date()
        appState.updateAgent(agent, reload: true)
        showFeedback(LocalizedString.format("reset_agent", agent.name), isError: false)
    }

    private func showFeedback(_ message: String, isError: Bool) {
        feedback = AgentActionFeedback(message: message, isError: isError)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            if feedback?.message == message {
                feedback = nil
            }
        }
    }

    private func refreshVisibleItems() {
        visibleItems = filterAgentItems(items, searchText: searchText, filter: filter, sort: sort)
        pendingVisibleItemsRefresh = false
    }

    private func handleVisibleItemsChange(force: Bool = false) {
        if force || isActive {
            refreshVisibleItems()
        } else {
            pendingVisibleItemsRefresh = true
        }
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
                    Text(LocalizedString.format("in_out_connections", item.incomingConnections, item.outgoingConnections))
                        .font(.caption)
                    Text(LocalizedString.format("skill_count_small", item.agent.capabilities.count))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(width: 110, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.soulDisplayName)
                        .font(.caption)
                        .foregroundColor(item.hasSoulFile ? .primary : .orange)
                        .lineLimit(1)
                    Text(item.soulDirectoryName ?? LocalizedString.text("using_project_cache_only"))
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
                .help(LocalizedString.text("focus_agent_help"))

                Button(action: onEdit) {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .help(LocalizedString.text("edit_soul_help"))

                Button(action: onRevealSoul) {
                    Image(systemName: "doc.text.magnifyingglass")
                }
                .buttonStyle(.borderless)
                .help(LocalizedString.text("reveal_soul_help"))

                Button(action: onDuplicate) {
                    Image(systemName: "plus.square.on.square")
                }
                .buttonStyle(.borderless)
                .help(LocalizedString.text("duplicate_agent_help"))

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help(LocalizedString.text("delete_agent_help"))

                if isConnectMode {
                    Button(action: { onConnect(item.agent.id) }) {
                        Image(systemName: "link")
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.blue)
                    .help(LocalizedString.text("connect_from_selected_help"))
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
private struct AgentGridView: View {
    @EnvironmentObject var appState: AppState
    let snapshot: AgentCollectionSnapshot
    let collectionSignature: AgentCollectionSignature
    let isActive: Bool
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
    @State private var visibleItems: [AgentCollectionItem] = []
    @State private var canPasteFromPasteboard = false
    @State private var pendingVisibleItemsRefresh = false

    private var items: [AgentCollectionItem] {
        snapshot.items
    }

    var body: some View {
        VStack(spacing: 0) {
            AgentCollectionToolbar(
                searchText: $searchText,
                filter: $filter,
                sort: $sort,
                snapshot: snapshot,
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
                                onRevealSoul: { revealManagedConfigFile(for: item.agent.id) },
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
                                    canPaste: canPasteFromPasteboard,
                                    onOpen: { focusAgent(item.agent.id) },
                                    onRevealManagedConfig: { revealManagedConfigFile(for: item.agent.id) },
                                    onOpenWorkspace: { openWorkspace(for: item.agent.id) },
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
        .alert(LocalizedString.text("delete_agent_title"), isPresented: deleteConfirmationBinding) {
            Button(LocalizedString.delete, role: .destructive) {
                if let candidate = deleteCandidate {
                    appState.deleteAgent(candidate.id)
                    if selectedAgentID == candidate.id {
                        selectedAgentID = nil
                    }
                    showFeedback(LocalizedString.format("deleted_agent", candidate.name), isError: false)
                }
                deleteCandidate = nil
            }
            Button(LocalizedString.cancel, role: .cancel) {
                deleteCandidate = nil
            }
        } message: {
            Text(deleteCandidate.map { LocalizedString.format("delete_agent_message", $0.name) } ?? "")
        }
        .onAppear {
            canPasteFromPasteboard = NSPasteboard.general.canReadObject(forClasses: [NSString.self], options: nil)
            handleVisibleItemsChange(force: true)
        }
        .onChange(of: collectionSignature) { _, _ in
            handleVisibleItemsChange()
        }
        .onChange(of: searchText) { _, _ in
            handleVisibleItemsChange()
        }
        .onChange(of: filter) { _, _ in
            handleVisibleItemsChange()
        }
        .onChange(of: sort) { _, _ in
            handleVisibleItemsChange()
        }
        .onChange(of: isActive) { _, newValue in
            guard newValue else { return }
            if pendingVisibleItemsRefresh || visibleItems.isEmpty {
                refreshVisibleItems()
            }
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
        guard appState.ensureAgentNode(agentID: agentID, suggestedPosition: .zero) != nil,
              let agent = currentAgent(id: agentID) else { return }
        selectedAgentID = agentID
        editingAgent = agent
    }

    private func revealManagedConfigFile(for agentID: UUID) {
        if let configURL = appState.managedAgentPrimaryConfigURL(for: agentID) {
            NSWorkspace.shared.activateFileViewerSelecting([configURL])
            showFeedback(LocalizedString.format("revealed_file", configURL.lastPathComponent), isError: false)
        } else {
            showFeedback(LocalizedString.text("no_real_soul_file"), isError: true)
        }
    }

    private func openWorkspace(for agentID: UUID) {
        if let workspaceURL = appState.agentWorkspaceURL(for: agentID) {
            NSWorkspace.shared.open(workspaceURL)
            showFeedback(LocalizedString.format("opened_workspace", workspaceURL.lastPathComponent), isError: false)
        } else {
            showFeedback(LocalizedString.text("no_workspace_directory"), isError: true)
        }
    }

    private func copyAgent(_ agentID: UUID) {
        guard let agent = currentAgent(id: agentID) else { return }
        let success = appState.copyAgent(agent)
        showFeedback(success ? LocalizedString.format("copied_agent", agent.name) : LocalizedString.text("copy_failed"), isError: !success)
    }

    private func cutAgent(_ agentID: UUID) {
        let agentName = currentAgent(id: agentID)?.name ?? "agent"
        let success = appState.cutAgent(agentID)
        if success, selectedAgentID == agentID {
            selectedAgentID = nil
        }
        showFeedback(success ? LocalizedString.format("cut_agent", agentName) : LocalizedString.text("cut_failed"), isError: !success)
    }

    private func pasteAgent() {
        if let newAgent = appState.pasteAgentFromPasteboard() {
            selectedAgentID = newAgent.id
            showFeedback(LocalizedString.format("pasted_agent", newAgent.name), isError: false)
        } else {
            showFeedback(LocalizedString.text("paste_failed"), isError: true)
        }
    }

    private func duplicateAgent(_ agentID: UUID) {
        if let newAgent = appState.duplicateAgent(agentID, suffix: LocalizedString.text("duplicate_suffix"), offset: CGPoint(x: 50, y: 50)) {
            selectedAgentID = newAgent.id
            showFeedback(LocalizedString.format("duplicated_agent", newAgent.name), isError: false)
        } else {
            showFeedback(LocalizedString.text("duplicate_failed"), isError: true)
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
                    showFeedback(LocalizedString.format("exported_agent", agent.name), isError: false)
                } catch {
                    showFeedback(LocalizedString.format("export_failed", error.localizedDescription), isError: true)
                }
            }
        }
    }

    private func resetAgent(_ agentID: UUID) {
        guard var agent = currentAgent(id: agentID) else { return }
        agent.updatedAt = Date()
        appState.updateAgent(agent, reload: true)
        showFeedback(LocalizedString.format("reset_agent", agent.name), isError: false)
    }

    private func showFeedback(_ message: String, isError: Bool) {
        feedback = AgentActionFeedback(message: message, isError: isError)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            if feedback?.message == message {
                feedback = nil
            }
        }
    }

    private func refreshVisibleItems() {
        visibleItems = filterAgentItems(items, searchText: searchText, filter: filter, sort: sort)
        pendingVisibleItemsRefresh = false
    }

    private func handleVisibleItemsChange(force: Bool = false) {
        if force || isActive {
            refreshVisibleItems()
        } else {
            pendingVisibleItemsRefresh = true
        }
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
                    Label(LocalizedString.format("skill_count_small", item.agent.capabilities.count), systemImage: "star")
                    Label(LocalizedString.format("in_out_connections", item.incomingConnections, item.outgoingConnections), systemImage: "arrow.left.arrow.right")
                    Label(item.hasSoulFile ? item.soulDisplayName : LocalizedString.text("project_cache_only"), systemImage: item.hasSoulFile ? "doc.text" : "exclamationmark.triangle")
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
                    Label(LocalizedString.text("focus"), systemImage: "scope")
                }
                .buttonStyle(.borderless)

                Button(action: onEdit) {
                    Label(LocalizedString.text("edit_action"), systemImage: "pencil")
                }
                .buttonStyle(.borderless)

                Button(action: onRevealSoul) {
                    Label(LocalizedString.text("soul_header"), systemImage: "doc.text.magnifyingglass")
                }
                .buttonStyle(.borderless)

                Spacer()

                Button(action: onOpenWorkspace) {
                    Image(systemName: "folder")
                }
                .buttonStyle(.borderless)
                .help(LocalizedString.text("open_workspace_help"))

                Button(action: onDuplicate) {
                    Image(systemName: "plus.square.on.square")
                }
                .buttonStyle(.borderless)
                .help(LocalizedString.text("duplicate_agent_help"))

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help(LocalizedString.text("delete_agent_help"))

                if isConnectMode {
                    Button(action: { onConnect(item.agent.id) }) {
                        Image(systemName: "link")
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.blue)
                    .help(LocalizedString.text("connect_from_selected_help"))
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
    let isActive: Bool
    @Binding var zoomScale: CGFloat
    @Binding var offset: CGSize
    @Binding var lastOffset: CGSize
    @Binding var isConnectMode: Bool
    @Binding var connectFromAgentID: UUID?
    @Binding var connectionType: WorkflowEditorView.ConnectionType
    @Binding var selectedNodeID: UUID?
    @Binding var selectedNodeIDs: Set<UUID>
    @Binding var selectedAgentID: UUID?
    @Binding var selectedEdgeID: UUID?
    @Binding var selectedBoundaryIDs: Set<UUID>
    @Binding var isLassoMode: Bool
    @Binding var isBatchConnectMode: Bool
    @Binding var batchSourceNodeIDs: Set<UUID>
    @Binding var batchTargetNodeIDs: Set<UUID>
    @Binding var batchPreview: BatchConnectionPreview?
    @Binding var batchCreatedEdgeIDs: Set<UUID>
    let batchHighlightedEdgeIDs: Set<UUID>
    @Binding var batchEdgeLabel: String
    @Binding var batchEdgeColorHex: String?
    @Binding var batchRequiresApproval: Bool
    @Binding var shouldPresentSelectedNodeProperties: Bool
    var onAssignBatchSources: () -> Void
    var onAssignBatchTargets: () -> Void
    var onPreviewBatchConnections: () -> Void
    var onCommitBatchConnections: () -> Void
    var onCancelBatchConnections: () -> Void
    var onUndoBatchConnections: () -> Void
    var onConnect: (UUID, UUID) -> Void
    
    @State private var showNodePropertyPanel = false
    @State private var selectedNodeForProperty: WorkflowNode?
    @State private var showEdgePropertyPanel = false
    @State private var selectedEdgeForProperty: WorkflowEdge?
    
    var body: some View {
        GeometryReader { _ in
            HStack(spacing: 0) {
                CanvasView(
                    isActive: isActive,
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
                    batchSourceNodeIDs: batchSourceNodeIDs,
                    batchTargetNodeIDs: batchTargetNodeIDs,
                    batchPreview: batchPreview,
                    batchCreatedEdgeIDs: batchHighlightedEdgeIDs,
                    isBatchConnectMode: isBatchConnectMode,
                    onNodeClickInConnectMode: { node in
                        self.handleNodeClickInConnectMode(node: node)
                    },
                    onNodeSelected: { node in
                        selectedEdgeForProperty = nil
                        showEdgePropertyPanel = false
                        selectedNodeForProperty = node
                    },
                    onNodeSecondarySelected: { node in
                        presentNodePropertyPanel(for: node)
                    },
                    onEdgeSelected: { edge in
                        presentEdgePropertyPanel(for: edge)
                    },
                    onEdgeSecondarySelected: { edge in
                        presentEdgePropertyPanel(for: edge)
                    },
                    onDropAgent: { agentName, location in
                        self.addAgentNodeToCanvas(agentName: agentName, at: location)
                    },
                    onAgentNodeInstantiated: { nodeID, agentID in
                        selectedNodeID = nodeID
                        selectedNodeIDs.removeAll()
                        selectedEdgeID = nil
                        selectedBoundaryIDs.removeAll()
                        self.selectedAgentID = agentID
                        self.shouldPresentSelectedNodeProperties = true
                    },
                    onAssignBatchSources: onAssignBatchSources,
                    onAssignBatchTargets: onAssignBatchTargets
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if isBatchConnectMode {
                    BatchConnectionPreviewPanel(
                        workflow: appState.workflow(for: nil),
                        selectedNodeIDs: selectedNodeIDs,
                        sourceNodeIDs: batchSourceNodeIDs,
                        targetNodeIDs: batchTargetNodeIDs,
                        preview: batchPreview,
                        createdEdgeIDs: batchCreatedEdgeIDs,
                        edgeLabel: $batchEdgeLabel,
                        edgeColorHex: $batchEdgeColorHex,
                        requiresApproval: $batchRequiresApproval,
                        onAssignSources: onAssignBatchSources,
                        onAssignTargets: onAssignBatchTargets,
                        onPreview: onPreviewBatchConnections,
                        onCommit: onCommitBatchConnections,
                        onUndo: onUndoBatchConnections,
                        onCancel: onCancelBatchConnections
                    )
                    .frame(width: 360)
                    .transition(.move(edge: .trailing))
                } else if showNodePropertyPanel, let node = selectedNodeForProperty {
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
        .onChange(of: selectedNodeID) { _, newValue in
            guard shouldPresentSelectedNodeProperties else { return }
            guard let workflow = appState.workflow(for: nil),
                  let nodeID = newValue,
                  let node = workflow.nodes.first(where: { $0.id == nodeID }) else {
                shouldPresentSelectedNodeProperties = false
                return
            }

            presentNodePropertyPanel(for: node)
            shouldPresentSelectedNodeProperties = false
        }
    }
    
    private func addAgentNodeToCanvas(agentName: String, at _: CGPoint) {
        guard let instantiated = appState.instantiateAgentNodeFromPalettePayload(
            agentName,
            position: CGPoint(x: 300, y: 200)
        ) else { return }

        selectedNodeID = instantiated.nodeID
        selectedNodeIDs.removeAll()
        selectedEdgeID = nil
        selectedBoundaryIDs.removeAll()
        selectedAgentID = instantiated.agent.id
        shouldPresentSelectedNodeProperties = true
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
        guard let workflow = appState.workflow(for: nil) else { return nil }

        if workflow.nodes.contains(where: { $0.id == identifier && ($0.type == .agent || $0.type == .start) }) {
            return identifier
        }

        if let node = workflow.nodes.first(where: { $0.agentID == identifier && $0.type == .agent }) {
            return node.id
        }

        return nil
    }

    private func presentNodePropertyPanel(for node: WorkflowNode) {
        selectedEdgeForProperty = nil
        showEdgePropertyPanel = false
        selectedNodeForProperty = node
        showNodePropertyPanel = true
    }

    private func presentEdgePropertyPanel(for edge: WorkflowEdge) {
        selectedNodeForProperty = nil
        showNodePropertyPanel = false
        selectedEdgeForProperty = edge
        showEdgePropertyPanel = true
    }
}

// MARK: - Agent库侧边栏
struct AgentLibrarySidebar: View {
    @EnvironmentObject var appState: AppState
    @Binding var selectedAgentID: UUID?
    var onAddAll: () -> Void
    var isOpenClawConnected: Bool = false
    var openClawAgents: [String] = []
    @State private var openClawExpanded: Bool = true
    @State private var projectExpanded: Bool = true
    @State private var templateExpanded: Bool = false
    @State private var deleteCandidate: Agent?

    private var templateGroups: [(family: AgentTemplateFamily, groups: [(category: AgentTemplateCategory, templates: [AgentTemplate])])] {
        AgentTemplateCatalog.families.compactMap { family in
            let groups: [(category: AgentTemplateCategory, templates: [AgentTemplate])] =
                AgentTemplateCatalog.categories(in: family).compactMap { category -> (category: AgentTemplateCategory, templates: [AgentTemplate])? in
                let templates = AgentTemplateCatalog.templates(in: category)
                guard !templates.isEmpty else { return nil }
                return (category, templates)
            }

            guard !groups.isEmpty else { return nil }
            return (family, groups)
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
                                DraggableAgentItem(
                                    name: agentName,
                                    dragPayload: "detectedAgent:\(agentName)"
                                )
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
                        ForEach(templateGroups, id: \.family) { familyGroup in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(familyGroup.family.rawValue)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 4)

                                ForEach(familyGroup.groups, id: \.category) { group in
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(group.category.rawValue)
                                            .font(.caption2)
                                            .foregroundColor(CanvasStylePalette.color(from: group.category.defaultColorHex) ?? .secondary)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background((CanvasStylePalette.color(from: group.category.defaultColorHex) ?? .secondary).opacity(0.12))
                                            .clipShape(Capsule())
                                            .padding(.horizontal, 4)

                                        ForEach(group.templates) { template in
                                            TemplateLibraryItem(template: template) {
                                                addTemplateNode(template)
                                            }
                                            .padding(.horizontal, 4)
                                        }
                                    }
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
                            DraggableAgentItem(
                                name: agent.name,
                                agent: agent,
                                dragPayload: "projectAgent:\(agent.id.uuidString)",
                                isSelected: selectedAgentID == agent.id,
                                onSelect: { selectedAgentID = agent.id },
                                onOpen: { focusProjectAgent(agent.id) },
                                onDelete: { deleteCandidate = currentProjectAgent(id: agent.id) ?? agent }
                            )
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
        .alert(LocalizedString.text("delete_agent_title"), isPresented: deleteConfirmationBinding) {
            Button(LocalizedString.delete, role: .destructive) {
                if let candidate = deleteCandidate {
                    appState.deleteAgent(candidate.id)
                    if selectedAgentID == candidate.id {
                        selectedAgentID = nil
                    }
                }
                deleteCandidate = nil
            }
            Button(LocalizedString.cancel, role: .cancel) {
                deleteCandidate = nil
            }
        } message: {
            Text(deleteCandidate.map { LocalizedString.format("delete_agent_message", $0.name) } ?? "")
        }
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
        guard let instantiated = appState.instantiateAgentNodeFromPalettePayload(
            "template:\(template.id)",
            position: CGPoint(x: 300, y: 200)
        ) else { return }

        appState.selectedNodeID = instantiated.nodeID
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { deleteCandidate != nil },
            set: { if !$0 { deleteCandidate = nil } }
        )
    }

    private func currentProjectAgent(id: UUID) -> Agent? {
        appState.currentProject?.agents.first(where: { $0.id == id })
    }

    private func focusProjectAgent(_ agentID: UUID) {
        selectedAgentID = agentID
        _ = appState.focusAgentNode(agentID: agentID, createIfMissing: true, suggestedPosition: .zero)
    }
}

struct DraggableAgentItem: View {
    let name: String
    var agent: Agent?
    var dragPayload: String?
    var isSelected: Bool = false
    var onSelect: (() -> Void)?
    var onOpen: (() -> Void)?
    var onDelete: (() -> Void)?
    
    var body: some View {
        HStack {
            Image(systemName: "person.circle.fill")
                .foregroundColor(.accentColor)
            
            Text(name)
                .lineLimit(1)
            
            Spacer()

            if isSelected, let onDelete {
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.borderless)
                .help(LocalizedString.text("delete_agent_help"))
            } else {
                Image(systemName: "line.3.horizontal")
                    .foregroundColor(.secondary)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.14) : Color(.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? Color.accentColor.opacity(0.85) : Color.clear, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .onTapGesture {
            onSelect?()
        }
        .onTapGesture(count: 2) {
            onOpen?()
        }
        .contextMenu {
            if let onOpen {
                Button(LocalizedString.text("focus")) {
                    onOpen()
                }
            }

            if let onDelete {
                Button(LocalizedString.delete, role: .destructive) {
                    onDelete()
                }
            }
        }
        .onDrag { NSItemProvider(object: (dragPayload ?? name) as NSString) }
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
        let categoryColor = CanvasStylePalette.color(from: template.category.defaultColorHex) ?? .accentColor

        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "shippingbox.fill")
                .foregroundColor(categoryColor)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(template.name)
                        .font(.subheadline)
                        .lineLimit(1)
                    Text(template.category.rawValue)
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(categoryColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(categoryColor.opacity(0.12))
                        .clipShape(Capsule())
                }
                Text(template.taxonomyPath)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Text(template.summary)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Button(action: onAdd) {
                Image(systemName: "plus.circle")
                    .foregroundColor(categoryColor)
            }
            .buttonStyle(.plain)
            .help("基于该模板创建节点")
        }
        .padding(8)
        .background(categoryColor.opacity(0.06))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 6)
                .fill(categoryColor)
                .frame(width: 4)
        }
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
    @State private var conditionExpression: String = ""
    @State private var loopEnabled: Bool = false
    @State private var maxIterations: Double = 1
    @State private var nodeDisplayColorHex: String?
    @State private var reloadStatus: String?
    @State private var reloadStatusIsError = false
    @State private var managedConfigFiles: [ManagedAgentWorkspaceDocumentReference] = []
    @State private var selectedConfigRelativePath: String = "SOUL.md"
    @State private var selectedConfigFilePath: String?
    @State private var managedConfigDrafts: [String: String] = [:]
    @State private var dirtyManagedConfigPaths: Set<String> = []
    @State private var outgoingEdgeDrafts: [UUID: EdgeDraft] = [:]
    @State private var showingDiscardChangesAlert = false
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(LocalizedString.nodeProperties)
                    .font(.headline)
                if hasUnsavedChanges {
                    WorkflowEditorDirtyBadgeView()
                }
                Spacer()
                Button(LocalizedString.close) {
                    requestClose()
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
            }
            .padding()
            .background(Color(.windowBackgroundColor))
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    GroupBox(LocalizedString.text("node_info")) {
                        VStack(alignment: .leading, spacing: 8) {
                            LabeledContent(LocalizedString.text("id_label")) {
                                Text(node.id.uuidString.prefix(8))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            LabeledContent(LocalizedString.text("type_label")) {
                                Text(node.type.rawValue.capitalized)
                            }

                            if node.type != .agent {
                                TextField(LocalizedString.text("title_label"), text: $nodeTitle)
                                    .textFieldStyle(.roundedBorder)
                            }

                        }
                        .padding(8)
                    }

                    GroupBox(LocalizedString.text("node_color_group")) {
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

                                Button(LocalizedString.text("color_default")) {
                                    nodeDisplayColorHex = nil
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }

                            Text(LocalizedString.text("color_group_nodes_hint"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(8)
                    }
                    
                    if node.type == .agent, let agentID = node.agentID,
                       let agent = getAgent(id: agentID) {
                        GroupBox(LocalizedString.format("agent_section_title", agent.name)) {
                            VStack(alignment: .leading, spacing: 14) {
                                LabeledContent(LocalizedString.name) {
                                    Text(agent.name)
                                        .foregroundColor(.primary)
                                }

                                ManagedConfigEditorPane(
                                    files: managedConfigFiles,
                                    selectedRelativePath: $selectedConfigRelativePath,
                                    selectedFilePath: selectedConfigFilePath,
                                    text: managedConfigTextBinding,
                                    onSelectRelativePath: { newValue in
                                        loadManagedConfigDraft(agentID: agentID, relativePath: newValue)
                                    },
                                    editorFont: .system(.caption, design: .monospaced),
                                    minEditorHeight: 380,
                                    idealEditorHeight: 440,
                                    maxEditorHeight: 560
                                )
                                
                                if let reloadStatus {
                                    WorkflowEditorInlineStatusView(
                                        message: reloadStatus,
                                        isError: reloadStatusIsError,
                                        pendingApplyCount: reloadStatusIsError ? 0 : appState.pendingWorkflowConfigurationRevisionDelta
                                    )
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
                Button(LocalizedString.cancel) {
                    requestClose()
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button(LocalizedString.save) {
                    saveChanges()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!hasUnsavedChanges)
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
        .onChange(of: node) { _, _ in
            loadNodeData()
        }
        .onChange(of: nodeTitle) { _, _ in
            clearReloadStatus()
        }
        .onChange(of: conditionExpression) { _, _ in
            clearReloadStatus()
        }
        .onChange(of: loopEnabled) { _, _ in
            clearReloadStatus()
        }
        .onChange(of: maxIterations) { _, _ in
            clearReloadStatus()
        }
        .onChange(of: nodeDisplayColorHex) { _, _ in
            clearReloadStatus()
        }
        .alert(LocalizedString.text("discard_changes_title"), isPresented: $showingDiscardChangesAlert) {
            Button(LocalizedString.text("discard_changes_action"), role: .destructive) {
                isPresented = false
            }
            Button(LocalizedString.text("keep_editing_action"), role: .cancel) {}
        } message: {
            Text(LocalizedString.text("discard_changes_message"))
        }
    }

    private var hasUnsavedChanges: Bool {
        let hasNodeMetadataChanges: Bool = {
            if node.type != .agent {
                let existingNodes = appState.workflow(for: nil)?.nodes ?? []
                let normalizedTitle = WorkflowNode.normalizedTitle(
                    requestedTitle: nodeTitle,
                    nodeType: node.type,
                    existingNodes: existingNodes,
                    excludingNodeID: node.id
                )
                if normalizedTitle != node.title {
                    return true
                }
            }

            return node.conditionExpression != conditionExpression
                || node.loopEnabled != loopEnabled
                || node.maxIterations != Int(maxIterations.rounded())
                || CanvasStylePalette.normalizedHex(node.displayColorHex) != CanvasStylePalette.normalizedHex(nodeDisplayColorHex)
        }()

        return hasNodeMetadataChanges || !dirtyManagedConfigPaths.isEmpty
    }

    private var managedConfigTextBinding: Binding<String> {
        Binding(
            get: { managedConfigDrafts[selectedConfigRelativePath] ?? "" },
            set: {
                managedConfigDrafts[selectedConfigRelativePath] = $0
                dirtyManagedConfigPaths.insert(selectedConfigRelativePath)
                clearReloadStatus()
            }
        )
    }

    private func clearReloadStatus() {
        guard reloadStatus != nil else { return }
        reloadStatus = nil
        reloadStatusIsError = false
    }

    private func getAgent(id: UUID) -> Agent? {
        appState.currentProject?.agents.first { $0.id == id }
    }

    private func loadManagedConfigDraft(agentID: UUID, relativePath: String) {
        if managedConfigDrafts[relativePath] != nil,
           let file = managedConfigFiles.first(where: { $0.relativePath == relativePath }) {
            selectedConfigFilePath = file.absolutePath
            return
        }

        if let loaded = appState.loadManagedAgentWorkspaceDocument(agentID: agentID, relativePath: relativePath) {
            managedConfigDrafts[relativePath] = loaded.content
            selectedConfigFilePath = loaded.documentPath
        } else {
            managedConfigDrafts[relativePath] = ""
            selectedConfigFilePath = managedConfigFiles.first(where: { $0.relativePath == relativePath })?.absolutePath
        }
    }

    private func requestClose() {
        if hasUnsavedChanges {
            showingDiscardChangesAlert = true
        } else {
            isPresented = false
        }
    }

    private func preferredConfigRelativePath() -> String {
        if managedConfigFiles.contains(where: { $0.relativePath == "SOUL.md" }) {
            return "SOUL.md"
        }
        return managedConfigFiles.first?.relativePath ?? "SOUL.md"
    }

    private func loadNodeData() {
        nodeTitle = node.title
        agentDescription = ""
        conditionExpression = node.conditionExpression
        loopEnabled = node.loopEnabled
        maxIterations = Double(max(1, node.maxIterations))
        nodeDisplayColorHex = CanvasStylePalette.normalizedHex(node.displayColorHex)
        managedConfigFiles = []
        managedConfigDrafts = [:]
        dirtyManagedConfigPaths = []
        selectedConfigFilePath = nil
        reloadStatus = nil
        reloadStatusIsError = false

        if let agentID = node.agentID,
           let agent = getAgent(id: agentID) {
            nodeTitle = agent.name
            agentDescription = agent.description
            managedConfigFiles = appState.managedAgentWorkspaceDocuments(agentID: agentID)
            selectedConfigRelativePath = preferredConfigRelativePath()
            loadManagedConfigDraft(agentID: agentID, relativePath: selectedConfigRelativePath)
        }
    }
    
    private func saveChanges() {
        var updatedNode = node
        if node.type != .agent {
            let existingNodes = appState.workflow(for: nil)?.nodes ?? []
            updatedNode.title = WorkflowNode.normalizedTitle(
                requestedTitle: nodeTitle,
                nodeType: node.type,
                existingNodes: existingNodes,
                excludingNodeID: node.id
            )
        }
        updatedNode.conditionExpression = conditionExpression
        updatedNode.loopEnabled = loopEnabled
        updatedNode.maxIterations = Int(maxIterations.rounded())
        updatedNode.displayColorHex = CanvasStylePalette.normalizedHex(nodeDisplayColorHex)
        appState.updateNode(updatedNode)

        if let agentID = node.agentID, !dirtyManagedConfigPaths.isEmpty {
            let dirtyDocuments = managedConfigDrafts.filter { dirtyManagedConfigPaths.contains($0.key) }
            let fileResult = appState.persistManagedAgentWorkspaceDocuments(
                agentID: agentID,
                documents: dirtyDocuments
            )
            reloadStatus = fileResult.message
            reloadStatusIsError = !fileResult.success
            if fileResult.success {
                selectedConfigFilePath = fileResult.paths[selectedConfigRelativePath] ?? selectedConfigFilePath
                dirtyManagedConfigPaths.removeAll()
            }
        } else {
            reloadStatus = LocalizedString.text("workflow_changes_saved_locally")
            reloadStatusIsError = false
        }
    }

    private var outgoingEdges: [WorkflowEdge] {
        appState.workflow(for: nil)?.edges.filter { $0.isOutgoing(from: node.id) } ?? []
    }

    private func binding(for edge: WorkflowEdge) -> Binding<EdgeDraft> {
        Binding(
            get: { outgoingEdgeDrafts[edge.id] ?? EdgeDraft(edge: edge) },
            set: { outgoingEdgeDrafts[edge.id] = $0 }
        )
    }

    private func targetName(for edge: WorkflowEdge) -> String {
        guard let workflow = appState.workflow(for: nil),
              let targetNode = workflow.nodes.first(where: { $0.id == edge.toNodeID }) else {
            return LocalizedString.text("unknown_value")
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
                Toggle(LocalizedString.text("approval"), isOn: $edge.requiresApproval)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            TextField(LocalizedString.text("condition_label"), text: $edge.label)
                .textFieldStyle(.roundedBorder)

            TextField(LocalizedString.text("condition_expression"), text: $edge.conditionExpression)
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
                Label(LocalizedString.text("edge_properties"), systemImage: "arrowshape.right")
                    .font(.headline)
                Spacer()
                Button(LocalizedString.close) {
                    isPresented = false
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    GroupBox(LocalizedString.text("route_summary")) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(LocalizedString.text("from_label")): \(sourceName)")
                            Text("\(LocalizedString.text("to_label")): \(targetName)")
                            Text("\(LocalizedString.text("edge_id")): \(edge.id.uuidString.prefix(8))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                    }

                    GroupBox(LocalizedString.text("visual_summary")) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 10) {
                                summaryBadge(text: sourceName, color: .blue)
                                Image(systemName: "arrow.right")
                                    .foregroundColor(.secondary)
                                summaryBadge(text: targetName, color: .green)
                            }

                            HStack(spacing: 8) {
                                summaryBadge(
                                    text: label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? LocalizedString.text("unlabeled_route") : label,
                                    color: .accentColor
                                )
                                summaryBadge(
                                    text: isBidirectional ? LocalizedString.text("connection_two_way") : LocalizedString.text("connection_one_way"),
                                    color: .indigo
                                )
                                if requiresApproval {
                                    summaryBadge(text: LocalizedString.text("approval"), color: .orange)
                                }
                            }

                            Text(
                                conditionExpression.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? LocalizedString.text("no_condition_expression_hint")
                                    : conditionExpression
                            )
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                    }

                    GroupBox(LocalizedString.text("route_display")) {
                        VStack(alignment: .leading, spacing: 12) {
                            TextField(LocalizedString.text("label_text"), text: $label)
                                .textFieldStyle(.roundedBorder)

                            TextField(LocalizedString.text("condition_text"), text: $conditionExpression)
                                .textFieldStyle(.roundedBorder)

                            Toggle(LocalizedString.text("requires_approval"), isOn: $requiresApproval)

                            VStack(alignment: .leading, spacing: 6) {
                                Text(LocalizedString.text("data_mapping"))
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

                    GroupBox(LocalizedString.text("route_color_group")) {
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

                                Button(LocalizedString.text("color_default")) {
                                    edgeDisplayColorHex = nil
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }

                            Text(LocalizedString.text("color_group_edges_hint"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(8)
                    }

                    GroupBox(LocalizedString.text("communication_direction")) {
                        VStack(alignment: .leading, spacing: 10) {
                            Picker(LocalizedString.text("direction"), selection: $isBidirectional) {
                                Text(LocalizedString.text("connection_one_way")).tag(false)
                                Text(LocalizedString.text("connection_two_way")).tag(true)
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: isBidirectional) { _, newValue in
                                appState.setEdgeCommunicationDirection(edgeID: edge.id, bidirectional: newValue)
                            }

                            HStack(spacing: 8) {
                                Button {
                                    appState.flipEdgeDirection(edgeID: edge.id)
                                } label: {
                                    Label(LocalizedString.text("reverse"), systemImage: "arrow.left.arrow.right")
                                }
                                .buttonStyle(.bordered)
                                .disabled(isBidirectional)

                                Text(isBidirectional ? LocalizedString.text("two_way_direction_hint") : LocalizedString.text("reverse_direction_hint"))
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
                Button(LocalizedString.text("delete_route"), role: .destructive) {
                    appState.removeEdge(edge.id)
                    isPresented = false
                }
                .buttonStyle(.bordered)

                Spacer()

                Button(LocalizedString.save) {
                    saveRouteDisplayChanges()
                }
                .buttonStyle(.bordered)

                Button(LocalizedString.close) {
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
        .onChange(of: edge) { _, newEdge in
            label = newEdge.label
            conditionExpression = newEdge.conditionExpression
            requiresApproval = newEdge.requiresApproval
            isBidirectional = isBidirectionalEdge(newEdge)
            dataMappingText = formattedDataMapping(newEdge.dataMapping)
            edgeDisplayColorHex = CanvasStylePalette.normalizedHex(newEdge.displayColorHex)
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
        guard let workflow = appState.workflow(for: nil),
              let node = workflow.nodes.first(where: { $0.id == nodeID }) else {
            return LocalizedString.text("unknown_value")
        }

        if !node.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return node.title
        }

        if let agentID = node.agentID,
           let agent = appState.currentProject?.agents.first(where: { $0.id == agentID }) {
            return agent.name
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
            Label(LocalizedString.text("open_action"), systemImage: "folder")
        }
        
        Divider()
        
        Button(action: { copyAgent() }) {
            Label(LocalizedString.copy, systemImage: "doc.on.doc")
        }

        Button(action: { cutAgent() }) {
            Label(LocalizedString.cut, systemImage: "scissors")
        }

        Button(action: { pasteAgent() }) {
            Label(LocalizedString.paste, systemImage: "doc.on.clipboard")
        }
        
        Divider()
        
        Button(action: { exportAgent() }) {
            Label(LocalizedString.text("export_action"), systemImage: "square.and.arrow.up")
        }
        
        Divider()
        
        Button(action: { showEditSheet = true }) {
            Label(LocalizedString.text("edit_soul_md"), systemImage: "doc.text")
        }
        
        Button(action: { showSkillsSheet = true }) {
            Label(LocalizedString.text("manage_skills"), systemImage: "star")
        }
        
        Button(action: { showPermissionsSheet = true }) {
            Label(LocalizedString.text("configure_permissions"), systemImage: "lock.shield")
        }
        
        Divider()
        
        Button(action: { duplicateAgent() }) {
            Label(LocalizedString.text("duplicate"), systemImage: "plus.square.on.square")
        }
        
        Button(action: { resetAgent() }) {
            Label(LocalizedString.text("reset_action"), systemImage: "arrow.counterclockwise")
        }
        
        Divider()
        
        Button(action: { showDeleteAlert = true }) {
            Label(LocalizedString.delete, systemImage: "trash")
        }
        .foregroundColor(.red)
        
        // Edit managed config sheet
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
            _ = appState.focusAgentNode(agentID: agent.id, createIfMissing: true, suggestedPosition: .zero)
            showToastMessage(LocalizedString.format("opened_agent", agent.name), type: .info)
        }
    }
    
    private func copyAgent() {
        if appState.copyAgent(agent) {
            showToastMessage(LocalizedString.format("copied_agent", agent.name), type: .success)
        } else {
            showToastMessage(LocalizedString.text("copy_failed"), type: .error)
        }
    }

    private func cutAgent() {
        if appState.cutAgent(agent.id) {
            showToastMessage(LocalizedString.format("cut_agent", agent.name), type: .success)
        } else {
            showToastMessage(LocalizedString.text("cut_failed"), type: .error)
        }
    }

    private func pasteAgent() {
        if let newAgent = appState.pasteAgentFromPasteboard() {
            showToastMessage(LocalizedString.format("pasted_agent", newAgent.name), type: .success)
        } else {
            showToastMessage(LocalizedString.text("paste_failed"), type: .error)
        }
    }
    
    private func duplicateAgent() {
        if let newAgent = appState.duplicateAgent(agent.id, suffix: LocalizedString.text("duplicate_suffix"), offset: CGPoint(x: 50, y: 50)) {
            showToastMessage(LocalizedString.format("duplicated_agent", newAgent.name), type: .success)
        } else {
            showToastMessage(LocalizedString.text("duplicate_failed"), type: .error)
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
                    self.showToastMessage(LocalizedString.format("exported_agent", agent.name), type: .success)
                } catch {
                    self.showToastMessage(LocalizedString.format("export_failed", error.localizedDescription), type: .error)
                }
            }
        }
    }
    
    private func resetAgent() {
        var updatedAgent = agent
        updatedAgent.updatedAt = Date()
        appState.updateAgent(updatedAgent, reload: true)
        showToastMessage(LocalizedString.format("reset_agent", agent.name), type: .success)
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
    @State private var managedConfigFiles: [ManagedAgentWorkspaceDocumentReference] = []
    @State private var selectedConfigRelativePath: String = "SOUL.md"
    @State private var selectedConfigFilePath: String?
    @State private var managedConfigDrafts: [String: String] = [:]
    @State private var dirtyManagedConfigPaths: Set<String> = []
    @State private var statusMessage: String?
    @State private var statusIsError = false
    @State private var showingDiscardChangesAlert = false
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(LocalizedString.format("agent_edit_title", agent.name))
                            .font(.headline)
                        if hasUnsavedChanges {
                            WorkflowEditorDirtyBadgeView()
                        }
                    }
                    Text(LocalizedString.text("managed_config_editor_scope_hint"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(LocalizedString.close) {
                    requestClose()
                }
                .buttonStyle(.borderless)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    GroupBox(LocalizedString.text("agent_info")) {
                        VStack(alignment: .leading, spacing: 12) {
                            TextField(LocalizedString.name, text: $name)
                                .textFieldStyle(.roundedBorder)
                            Text(LocalizedString.text("agent_node_title_follows_name_hint"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(8)
                    }

                    GroupBox(LocalizedString.text("managed_config_group_title")) {
                        ManagedConfigEditorPane(
                            files: managedConfigFiles,
                            selectedRelativePath: $selectedConfigRelativePath,
                            selectedFilePath: selectedConfigFilePath,
                            text: managedConfigTextBinding,
                            onSelectRelativePath: { newValue in
                                loadManagedConfigDraft(relativePath: newValue)
                            },
                            editorFont: .system(.body, design: .monospaced),
                            minEditorHeight: 320
                        )
                        .padding(8)
                    }

                    if let statusMessage {
                        WorkflowEditorInlineStatusView(
                            message: statusMessage,
                            isError: statusIsError,
                            pendingApplyCount: statusIsError ? 0 : appState.pendingWorkflowConfigurationRevisionDelta
                        )
                    }
                }
                .padding()
            }

            HStack {
                Button(LocalizedString.cancel) {
                    requestClose()
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button(LocalizedString.save) {
                    saveChanges()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!hasUnsavedChanges)
            }
            .padding()
            .background(.regularMaterial)
        }
        .frame(width: 680, height: 620)
        .onAppear {
            loadAgentData()
        }
        .onChange(of: name) { _, _ in
            clearStatusMessage()
        }
        .alert(LocalizedString.text("discard_changes_title"), isPresented: $showingDiscardChangesAlert) {
            Button(LocalizedString.text("discard_changes_action"), role: .destructive) {
                isPresented = false
            }
            Button(LocalizedString.text("keep_editing_action"), role: .cancel) {}
        } message: {
            Text(LocalizedString.text("discard_changes_message"))
        }
    }

    private var hasUnsavedChanges: Bool {
        name != agent.name || !dirtyManagedConfigPaths.isEmpty
    }

    private var managedConfigTextBinding: Binding<String> {
        Binding(
            get: { managedConfigDrafts[selectedConfigRelativePath] ?? "" },
            set: {
                managedConfigDrafts[selectedConfigRelativePath] = $0
                dirtyManagedConfigPaths.insert(selectedConfigRelativePath)
                clearStatusMessage()
            }
        )
    }

    private func clearStatusMessage() {
        guard statusMessage != nil else { return }
        statusMessage = nil
        statusIsError = false
    }
    
    private func loadAgentData() {
        if let project = appState.currentProject,
           let a = project.agents.first(where: { $0.id == agent.id }) {
            name = a.name
            managedConfigFiles = appState.managedAgentWorkspaceDocuments(agentID: a.id)
            selectedConfigRelativePath = managedConfigFiles.contains(where: { $0.relativePath == "SOUL.md" })
                ? "SOUL.md"
                : (managedConfigFiles.first?.relativePath ?? "SOUL.md")
            loadManagedConfigDraft(relativePath: selectedConfigRelativePath)
            dirtyManagedConfigPaths = []
            statusMessage = nil
            statusIsError = false
        }
    }

    private func loadManagedConfigDraft(relativePath: String) {
        if managedConfigDrafts[relativePath] != nil,
           let file = managedConfigFiles.first(where: { $0.relativePath == relativePath }) {
            selectedConfigFilePath = file.absolutePath
            return
        }

        if let loaded = appState.loadManagedAgentWorkspaceDocument(agentID: agent.id, relativePath: relativePath) {
            managedConfigDrafts[relativePath] = loaded.content
            selectedConfigFilePath = loaded.documentPath
        } else {
            managedConfigDrafts[relativePath] = ""
            selectedConfigFilePath = managedConfigFiles.first(where: { $0.relativePath == relativePath })?.absolutePath
        }
    }

    private func saveChanges() {
        guard var updatedAgent = appState.currentProject?.agents.first(where: { $0.id == agent.id }) else {
            statusMessage = LocalizedString.text("failed_locate_current_agent_before_saving")
            statusIsError = true
            return
        }

        updatedAgent.name = name
        updatedAgent.soulMD = managedConfigDrafts["SOUL.md"] ?? updatedAgent.soulMD
        updatedAgent.updatedAt = Date()
        appState.updateAgent(updatedAgent, reload: true)

        if !dirtyManagedConfigPaths.isEmpty {
            let dirtyDocuments = managedConfigDrafts.filter { dirtyManagedConfigPaths.contains($0.key) }
            let fileResult = appState.persistManagedAgentWorkspaceDocuments(
                agentID: updatedAgent.id,
                documents: dirtyDocuments
            )
            if fileResult.success {
                selectedConfigFilePath = fileResult.paths[selectedConfigRelativePath] ?? selectedConfigFilePath
                dirtyManagedConfigPaths.removeAll()
            }

            statusMessage = fileResult.message
            statusIsError = !fileResult.success
            if fileResult.success {
                isPresented = false
            }
            return
        }

        statusMessage = LocalizedString.text("workflow_changes_saved_locally")
        statusIsError = false
        if name != agent.name || !managedConfigFiles.isEmpty {
            isPresented = false
        }
    }

    private func requestClose() {
        if hasUnsavedChanges {
            showingDiscardChangesAlert = true
        } else {
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
            Text(LocalizedString.format("manage_skills_title", agent.name))
                .font(.headline)
            
            // Current skills
            VStack(alignment: .leading) {
                Text(LocalizedString.text("current_skills"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                if selectedSkills.isEmpty {
                    Text(LocalizedString.text("no_skills_assigned"))
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
                Text(LocalizedString.text("available_skills"))
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
                Button(LocalizedString.cancel) {
                    isPresented = false
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button(LocalizedString.save) {
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
        if let skillsDirectoryURL = resolvedSkillsDirectoryURL(),
           let contents = try? FileManager.default.contentsOfDirectory(atPath: skillsDirectoryURL.path) {
            availableSkills = contents.filter { $0.hasSuffix(".md") }
        } else {
            availableSkills = []
        }

        selectedSkills = Set(agent.capabilities)
    }

    private func resolvedSkillsDirectoryURL() -> URL? {
        guard let workspaceURL = appState.agentWorkspaceURL(for: agent.id) else {
            return nil
        }

        let directSkillsURL = workspaceURL.appendingPathComponent("skills", isDirectory: true)
        if FileManager.default.fileExists(atPath: directSkillsURL.path) {
            return directSkillsURL
        }

        let nestedSkillsURL = workspaceURL
            .appendingPathComponent("agent", isDirectory: true)
            .appendingPathComponent("skills", isDirectory: true)
        if FileManager.default.fileExists(atPath: nestedSkillsURL.path) {
            return nestedSkillsURL
        }

        return nil
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
            Text(LocalizedString.format("configure_permissions_title", agent.name))
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
                Button(LocalizedString.close) {
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
            return perm == .allow ? LocalizedString.allowed : LocalizedString.denied
        }
        return LocalizedString.text("permission_unknown")
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
            
            Text(LocalizedString.text("delete_agent_title"))
                .font(.headline)
            
            Text(LocalizedString.format("delete_agent_cannot_undo", agent.name))
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            
            HStack {
                Button(LocalizedString.cancel) {
                    isPresented = false
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button(LocalizedString.delete) {
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


private struct BatchFeedbackBanner: View {
    let message: String
    let isError: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundColor(isError ? .orange : .green)
            Text(message)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundColor(.primary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(NSColor.windowBackgroundColor).opacity(0.95))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke((isError ? Color.orange : Color.green).opacity(0.22), lineWidth: 1)
        )
    }
}

private struct BatchConnectionPreviewPanel: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var localizationManager = LocalizationManager.shared

    let workflow: Workflow?
    let selectedNodeIDs: Set<UUID>
    let sourceNodeIDs: Set<UUID>
    let targetNodeIDs: Set<UUID>
    let preview: BatchConnectionPreview?
    let createdEdgeIDs: Set<UUID>
    @Binding var edgeLabel: String
    @Binding var edgeColorHex: String?
    @Binding var requiresApproval: Bool
    var onAssignSources: () -> Void
    var onAssignTargets: () -> Void
    var onPreview: () -> Void
    var onCommit: () -> Void
    var onUndo: () -> Void
    var onCancel: () -> Void

    private var currentSelectionCount: Int {
        selectedNodeIDs.count
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label(batchPanelText("panel_title"), systemImage: "square.stack.3d.up.fill")
                    .font(.headline)
                Spacer()
                Button(batchLocalizedString("cancel")) {
                    onCancel()
                }
                .buttonStyle(.borderless)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    GroupBox(batchPanelText("selection")) {
                        VStack(alignment: .leading, spacing: 10) {
                            panelMetricRow(title: batchPanelText("current_selection"), value: "\(currentSelectionCount)")
                            panelMetricRow(title: batchPanelText("source_nodes"), value: "\(sourceNodeIDs.count)")
                            panelMetricRow(title: batchPanelText("target_nodes"), value: "\(targetNodeIDs.count)")

                            HStack(spacing: 8) {
                                Button(batchLocalizedString("set_sources")) {
                                    onAssignSources()
                                }
                                .buttonStyle(.bordered)
                                .disabled(currentSelectionCount == 0)

                                Button(batchLocalizedString("set_targets")) {
                                    onAssignTargets()
                                }
                                .buttonStyle(.bordered)
                                .disabled(currentSelectionCount == 0)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                    }

                    GroupBox(batchPanelText("attributes")) {
                        VStack(alignment: .leading, spacing: 12) {
                            TextField(batchPanelText("label"), text: $edgeLabel)
                                .textFieldStyle(.roundedBorder)

                            Toggle(batchPanelText("requires_approval"), isOn: $requiresApproval)

                            HStack(spacing: 8) {
                                ForEach(CanvasAccentColorPreset.allCases) { preset in
                                    Button {
                                        edgeColorHex = preset.hex
                                    } label: {
                                        Circle()
                                            .fill(preset.color)
                                            .frame(width: 18, height: 18)
                                            .overlay(
                                                Circle()
                                                    .stroke(
                                                        CanvasStylePalette.normalizedHex(edgeColorHex) == preset.hex ? Color.primary : Color.clear,
                                                        lineWidth: 2
                                                    )
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }

                                Button(batchPanelText("color_default")) {
                                    edgeColorHex = nil
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                        .padding(8)
                    }

                    GroupBox(batchPanelText("summary")) {
                        VStack(alignment: .leading, spacing: 10) {
                            panelMetricRow(title: batchPanelText("planned_new_edges"), value: "\(preview?.newEdgeCount ?? 0)")
                            panelMetricRow(title: batchPanelText("skipped_duplicates"), value: "\(preview?.duplicateCount ?? 0)")
                            panelMetricRow(title: batchPanelText("skipped_invalid"), value: "\(preview?.invalidCount ?? 0)")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                    }

                    if let preview {
                        if !preview.newEdges.isEmpty {
                            candidateSection(title: batchPanelText("created_edges"), candidates: preview.newEdges)
                        }
                        if !preview.duplicateEdges.isEmpty {
                            candidateSection(title: batchPanelText("duplicate_edges"), candidates: preview.duplicateEdges)
                        }
                        if !preview.invalidPairs.isEmpty {
                            candidateSection(title: batchPanelText("invalid_edges"), candidates: preview.invalidPairs)
                        }
                    } else {
                        Text(batchPanelText("preview_first"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
            }

            Divider()

            HStack {
                Button(batchLocalizedString("preview")) {
                    onPreview()
                }
                .buttonStyle(.bordered)
                .disabled(sourceNodeIDs.isEmpty || targetNodeIDs.isEmpty)

                Button(batchPanelText("undo_last")) {
                    onUndo()
                }
                .buttonStyle(.bordered)
                .disabled(createdEdgeIDs.isEmpty)

                Spacer()

                Button(batchPanelText("create_now")) {
                    onCommit()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!(preview?.hasActionableEdges ?? false))
            }
            .padding()
        }
        .background(Color(.windowBackgroundColor))
    }

    private func panelMetricRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
        }
        .font(.caption)
    }

    private func candidateSection(title: String, candidates: [BatchConnectionCandidate]) -> some View {
        GroupBox(title) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(candidates.prefix(12)) { candidate in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(nodeName(candidate.fromNodeID)) -> \(nodeName(candidate.toNodeID))")
                            .font(.caption.weight(.semibold))
                        if let reason = candidate.reason {
                            Text(batchCandidateReasonText(reason))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color(.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                if candidates.count > 12 {
                    Text(batchPanelText("more_rows", candidates.count - 12))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(8)
        }
    }

    private func nodeName(_ nodeID: UUID) -> String {
        guard let workflow,
              let node = workflow.nodes.first(where: { $0.id == nodeID }) else {
            return nodeID.uuidString.prefix(6).description
        }

        if let agentID = node.agentID,
           let agent = appState.currentProject?.agents.first(where: { $0.id == agentID }) {
            return agent.name
        }

        if !node.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return node.title
        }

        return node.type == .start ? batchPanelText("start_node") : batchPanelText("agent_node")
    }

    private func batchPanelText(_ key: String, _ count: Int? = nil) -> String {
        switch localizationManager.currentLanguage {
        case .english:
            switch key {
            case "panel_title": return "Batch Connect"
            case "selection": return "Selection"
            case "attributes": return "Shared Attributes"
            case "summary": return "Preview Summary"
            case "current_selection": return "Current selection"
            case "source_nodes": return "Source nodes"
            case "target_nodes": return "Target nodes"
            case "planned_new_edges": return "Planned new edges"
            case "skipped_duplicates": return "Skipped duplicates"
            case "skipped_invalid": return "Skipped invalid"
            case "label": return "Label"
            case "requires_approval": return "Requires approval"
            case "color_default": return "Default"
            case "created_edges": return "New edges"
            case "duplicate_edges": return "Existing edges"
            case "invalid_edges": return "Invalid pairs"
            case "preview_first": return "Set a source set and a target set, then preview before creating."
            case "create_now": return "Create"
            case "undo_last": return "Undo last batch"
            case "start_node": return "Start"
            case "agent_node": return "Agent"
            case "more_rows": return "+\(count ?? 0) more"
            default: return key
            }
        case .traditionalChinese:
            switch key {
            case "panel_title": return "批量連線"
            case "selection": return "選擇"
            case "attributes": return "統一屬性"
            case "summary": return "預覽摘要"
            case "current_selection": return "當前選取"
            case "source_nodes": return "來源節點"
            case "target_nodes": return "目標節點"
            case "planned_new_edges": return "預計新增"
            case "skipped_duplicates": return "跳過重複"
            case "skipped_invalid": return "跳過無效"
            case "label": return "標籤"
            case "requires_approval": return "需要審批"
            case "color_default": return "預設"
            case "created_edges": return "新增連線"
            case "duplicate_edges": return "已存在連線"
            case "invalid_edges": return "無效配對"
            case "preview_first": return "先設定來源與目標，再預覽後建立。"
            case "create_now": return "建立"
            case "undo_last": return "撤銷上次批量"
            case "start_node": return "開始"
            case "agent_node": return "節點"
            case "more_rows": return "還有 \(count ?? 0) 條"
            default: return key
            }
        case .simplifiedChinese:
            switch key {
            case "panel_title": return "批量连接"
            case "selection": return "选择"
            case "attributes": return "统一属性"
            case "summary": return "预览摘要"
            case "current_selection": return "当前选中"
            case "source_nodes": return "来源节点"
            case "target_nodes": return "目标节点"
            case "planned_new_edges": return "预计新增"
            case "skipped_duplicates": return "跳过重复"
            case "skipped_invalid": return "跳过无效"
            case "label": return "标签"
            case "requires_approval": return "需要审批"
            case "color_default": return "默认"
            case "created_edges": return "新增连接"
            case "duplicate_edges": return "已存在连接"
            case "invalid_edges": return "无效配对"
            case "preview_first": return "先设置来源与目标，再预览后创建。"
            case "create_now": return "创建"
            case "undo_last": return "撤销上次批量"
            case "start_node": return "开始"
            case "agent_node": return "节点"
            case "more_rows": return "还有 \(count ?? 0) 条"
            default: return key
            }
        }
    }
}

private func batchLocalizedString(_ key: String) -> String {
    switch LocalizationManager.shared.currentLanguage {
    case .english:
        switch key {
        case "batch_mode_enabled": return "Batch connect mode enabled."
        case "select_sources_first": return "Select one or more nodes, then set them as sources."
        case "select_targets_first": return "Select one or more nodes, then set them as targets."
        case "batch_preview_failed": return "Unable to build a batch preview right now."
        case "batch_commit_failed": return "Unable to create batch connections."
        case "batch_mode_cancelled": return "Batch connect mode cancelled."
        case "batch_connect": return "Batch Connect"
        case "batch_connect_help": return "Prepare sources and targets for bulk edge creation"
        case "set_sources": return "Set Sources"
        case "set_targets": return "Set Targets"
        case "set_sources_help": return "Use the current node selection as the source set"
        case "set_targets_help": return "Use the current node selection as the target set"
        case "preview": return "Preview"
        case "preview_help": return "Preview how many edges will be created or skipped"
        case "create_now_help": return "Create the valid connections from the current preview"
        case "cancel": return "Cancel"
        case "cancel_help": return "Exit batch connect mode"
        default: return key
        }
    case .traditionalChinese:
        switch key {
        case "batch_mode_enabled": return "已進入批量連線模式。"
        case "select_sources_first": return "請先選取一個或多個節點，再設為來源。"
        case "select_targets_first": return "請先選取一個或多個節點，再設為目標。"
        case "batch_preview_failed": return "暫時無法生成批量預覽。"
        case "batch_commit_failed": return "暫時無法建立批量連線。"
        case "batch_mode_cancelled": return "已取消批量連線模式。"
        case "batch_connect": return "批量連線"
        case "batch_connect_help": return "先設定來源與目標，再一次建立多條連線"
        case "set_sources": return "設為來源"
        case "set_targets": return "設為目標"
        case "set_sources_help": return "將當前選取的節點設為來源集合"
        case "set_targets_help": return "將當前選取的節點設為目標集合"
        case "preview": return "預覽"
        case "preview_help": return "預覽本次會新增或跳過多少條連線"
        case "create_now_help": return "建立當前預覽中的有效連線"
        case "cancel": return "取消"
        case "cancel_help": return "退出批量連線模式"
        default: return key
        }
    case .simplifiedChinese:
        switch key {
        case "batch_mode_enabled": return "已进入批量连接模式。"
        case "select_sources_first": return "请先选中一个或多个节点，再设为来源。"
        case "select_targets_first": return "请先选中一个或多个节点，再设为目标。"
        case "batch_preview_failed": return "暂时无法生成批量预览。"
        case "batch_commit_failed": return "暂时无法创建批量连接。"
        case "batch_mode_cancelled": return "已取消批量连接模式。"
        case "batch_connect": return "批量连接"
        case "batch_connect_help": return "先设置来源与目标，再一次创建多条连接"
        case "set_sources": return "设为来源"
        case "set_targets": return "设为目标"
        case "set_sources_help": return "将当前选中的节点设为来源集合"
        case "set_targets_help": return "将当前选中的节点设为目标集合"
        case "preview": return "预览"
        case "preview_help": return "预览本次会新增或跳过多少条连接"
        case "create_now_help": return "创建当前预览中的有效连接"
        case "cancel": return "取消"
        case "cancel_help": return "退出批量连接模式"
        default: return key
        }
    }
}

private func batchPanelActionText(_ key: String) -> String {
    switch LocalizationManager.shared.currentLanguage {
    case .english:
        switch key {
        case "create_now": return "Create"
        default: return key
        }
    case .traditionalChinese:
        switch key {
        case "create_now": return "建立"
        default: return key
        }
    case .simplifiedChinese:
        switch key {
        case "create_now": return "创建"
        default: return key
        }
    }
}

private func batchLocalizedFormat(_ key: String, _ count: Int) -> String {
    switch LocalizationManager.shared.currentLanguage {
    case .english:
        switch key {
        case "batch_sources_selected": return "\(count) source nodes selected."
        case "batch_targets_selected": return "\(count) target nodes selected."
        case "batch_undo_success": return "Removed \(count) newly created edges."
        case "batch_sources_short": return "Sources \(count)"
        case "batch_targets_short": return "Targets \(count)"
        case "preview_count_short": return "Preview \(count)"
        default: return "\(count)"
        }
    case .traditionalChinese:
        switch key {
        case "batch_sources_selected": return "已選擇 \(count) 個來源節點。"
        case "batch_targets_selected": return "已選擇 \(count) 個目標節點。"
        case "batch_undo_success": return "已移除剛建立的 \(count) 條連線。"
        case "batch_sources_short": return "來源 \(count)"
        case "batch_targets_short": return "目標 \(count)"
        case "preview_count_short": return "預覽 \(count)"
        default: return "\(count)"
        }
    case .simplifiedChinese:
        switch key {
        case "batch_sources_selected": return "已选择 \(count) 个来源节点。"
        case "batch_targets_selected": return "已选择 \(count) 个目标节点。"
        case "batch_undo_success": return "已移除刚创建的 \(count) 条连接。"
        case "batch_sources_short": return "来源 \(count)"
        case "batch_targets_short": return "目标 \(count)"
        case "preview_count_short": return "预览 \(count)"
        default: return "\(count)"
        }
    }
}

private func batchLocalizedSummary(created: Int, duplicate: Int, invalid: Int) -> String {
    switch LocalizationManager.shared.currentLanguage {
    case .english:
        return "New \(created), skipped \(duplicate) duplicates, skipped \(invalid) invalid."
    case .traditionalChinese:
        return "新增 \(created) 條，跳過 \(duplicate) 條重複，跳過 \(invalid) 條無效。"
    case .simplifiedChinese:
        return "新增 \(created) 条，跳过 \(duplicate) 条重复，跳过 \(invalid) 条无效。"
    }
}

private func batchCandidateReasonText(_ reason: BatchConnectionCandidateReason) -> String {
    switch LocalizationManager.shared.currentLanguage {
    case .english:
        switch reason {
        case .existingRelationship: return "Already connected."
        case .selfConnection: return "Self connections are not allowed."
        case .unsupportedSource: return "The source node type does not support edges."
        case .unsupportedTarget: return "The target node type does not support edges."
        case .missingSourceNode: return "The source node is missing."
        case .missingTargetNode: return "The target node is missing."
        }
    case .traditionalChinese:
        switch reason {
        case .existingRelationship: return "該節點對已存在連線。"
        case .selfConnection: return "不允許自連線。"
        case .unsupportedSource: return "來源節點類型不支援連線。"
        case .unsupportedTarget: return "目標節點類型不支援連線。"
        case .missingSourceNode: return "來源節點不存在。"
        case .missingTargetNode: return "目標節點不存在。"
        }
    case .simplifiedChinese:
        switch reason {
        case .existingRelationship: return "该节点对已存在连接。"
        case .selfConnection: return "不允许自连接。"
        case .unsupportedSource: return "来源节点类型不支持连接。"
        case .unsupportedTarget: return "目标节点类型不支持连接。"
        case .missingSourceNode: return "来源节点不存在。"
        case .missingTargetNode: return "目标节点不存在。"
        }
    }
}
