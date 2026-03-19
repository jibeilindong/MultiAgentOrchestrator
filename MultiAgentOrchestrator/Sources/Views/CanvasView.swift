//
//  CanvasView.swift
//  MultiAgentOrchestrator
//

import SwiftUI
import UniformTypeIdentifiers

struct CanvasView: View {
    @EnvironmentObject var appState: AppState
    @Binding var zoomScale: CGFloat
    @Binding var isConnectMode: Bool
    @Binding var connectionType: WorkflowEditorView.ConnectionType
    @Binding var connectFromAgentID: UUID?

    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var selectedNodeID: UUID?
    @State private var selectedNodeIDs: Set<UUID> = []
    @State private var selectedEdgeID: UUID?
    @State private var selectedBoundaryIDs: Set<UUID> = []
    @State private var connectingFromNode: WorkflowNode?
    @State private var tempConnectionEnd: CGPoint?
    @State private var isLassoMode: Bool = false
    @State private var isTransientLassoMode: Bool = false
    @State private var lassoRect: CGRect?
    @State private var suppressCanvasTapClear: Bool = false

    @State private var copiedNodes: [WorkflowNode] = []
    @State private var copiedEdges: [WorkflowEdge] = []
    @State private var copiedBoundaries: [WorkflowBoundary] = []

    var onNodeClickInConnectMode: ((WorkflowNode) -> Void)?
    var onNodeSelected: ((WorkflowNode) -> Void)?
    var onNodeSecondarySelected: ((WorkflowNode) -> Void)?
    var onEdgeSelected: ((WorkflowEdge) -> Void)?
    var onEdgeSecondarySelected: ((WorkflowEdge) -> Void)?
    var onDropAgent: ((String, CGPoint) -> Void)?

    init(
        zoomScale: Binding<CGFloat> = .constant(1),
        isConnectMode: Binding<Bool> = .constant(false),
        connectionType: Binding<WorkflowEditorView.ConnectionType> = .constant(.unidirectional),
        connectFromAgentID: Binding<UUID?> = .constant(nil),
        onNodeClickInConnectMode: ((WorkflowNode) -> Void)? = nil,
        onNodeSelected: ((WorkflowNode) -> Void)? = nil,
        onNodeSecondarySelected: ((WorkflowNode) -> Void)? = nil,
        onEdgeSelected: ((WorkflowEdge) -> Void)? = nil,
        onEdgeSecondarySelected: ((WorkflowEdge) -> Void)? = nil,
        onDropAgent: ((String, CGPoint) -> Void)? = nil
    ) {
        self._zoomScale = zoomScale
        self._isConnectMode = isConnectMode
        self._connectionType = connectionType
        self._connectFromAgentID = connectFromAgentID
        self.onNodeClickInConnectMode = onNodeClickInConnectMode
        self.onNodeSelected = onNodeSelected
        self.onNodeSecondarySelected = onNodeSecondarySelected
        self.onEdgeSelected = onEdgeSelected
        self.onEdgeSecondarySelected = onEdgeSecondarySelected
        self.onDropAgent = onDropAgent
    }

    var body: some View {
        CanvasContentView(
            scale: $scale,
            offset: $offset,
            lastOffset: $lastOffset,
            selectedNodeID: $selectedNodeID,
            selectedNodeIDs: $selectedNodeIDs,
            selectedEdgeID: $selectedEdgeID,
            selectedBoundaryIDs: $selectedBoundaryIDs,
            suppressCanvasTapClear: $suppressCanvasTapClear,
            isLassoMode: $isLassoMode,
            isTransientLassoMode: $isTransientLassoMode,
            lassoRect: $lassoRect,
            connectingFromNode: $connectingFromNode,
            tempConnectionEnd: $tempConnectionEnd,
            isConnectMode: isConnectMode,
            connectFromAgentID: connectFromAgentID,
            onNodeClick: onNodeClickInConnectMode,
            onNodeSelected: { node in
                suppressCanvasTapClear = true
                onNodeSelected?(node)
            },
            onNodeSecondarySelected: { node in
                suppressCanvasTapClear = true
                onNodeSecondarySelected?(node)
            },
            onEdgeSelected: { edge in
                suppressCanvasTapClear = true
                onEdgeSelected?(edge)
            },
            onEdgeSecondarySelected: { edge in
                suppressCanvasTapClear = true
                onEdgeSecondarySelected?(edge)
            }
        )
        .onChange(of: selectedEdgeID) { _, newValue in
            if newValue != nil {
                suppressCanvasTapClear = true
            }
        }
        .onAppear {
            NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                if event.modifierFlags.contains(.command) {
                    let delta = event.scrollingDeltaY * 0.01
                    let newScale = max(0.05, min(20.0, self.scale + delta))
                    self.scale = newScale
                    self.zoomScale = newScale
                    return nil
                }
                return event
            }
        }
        .overlay(
            ControlButtonsView(
                scale: $scale,
                offset: $offset,
                lastOffset: $lastOffset,
                selectedNodeID: $selectedNodeID,
                selectedNodeIDs: $selectedNodeIDs,
                selectedEdgeID: $selectedEdgeID,
                isConnectMode: $isConnectMode,
                connectionType: $connectionType,
                connectFromAgentID: $connectFromAgentID,
                isLassoMode: $isLassoMode,
                onDeleteSelectedEdge: deleteSelectedEdge,
                onCopySelection: copySelection,
                onCutSelection: cutSelection,
                onPasteSelection: pasteSelection,
                onDeleteSelection: deleteSelection,
                appState: appState
            )
        )
        .onAppear {
            setupDefaultNodes()
        }
        .onChange(of: zoomScale) { _, newValue in
            scale = newValue
        }
        .onChange(of: isConnectMode) { _, newValue in
            if !newValue {
                connectFromAgentID = nil
            }
        }
        .clipped()
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

    private func copySelection() {
        guard let workflow = appState.currentProject?.workflows.first else { return }
        let selection = activeSelection
        guard !selection.isEmpty else { return }

        copiedNodes = workflow.nodes.filter { selection.contains($0.id) }
        copiedEdges = workflow.edges.filter { selection.contains($0.fromNodeID) && selection.contains($0.toNodeID) }
        copiedBoundaries = workflow.boundaries.filter { boundary in
            boundary.memberNodeIDs.allSatisfy { selection.contains($0) }
        }
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
                newEdge.conditionExpression = sourceEdge.conditionExpression
                newEdge.requiresApproval = sourceEdge.requiresApproval
                newEdge.dataMapping = sourceEdge.dataMapping
                workflow.edges.append(newEdge)
            }

            for boundary in copiedBoundaries {
                let remappedMembers = boundary.memberNodeIDs.compactMap { nodeIDMapping[$0] }
                guard !remappedMembers.isEmpty else { continue }

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

    private func cutSelection() {
        copySelection()
        deleteSelection()
    }

    private func deleteSelection() {
        let selection = activeSelection
        if !selection.isEmpty {
            appState.removeNodes(selection)
        }
        if !selectedBoundaryIDs.isEmpty {
            appState.removeBoundaries(selectedBoundaryIDs)
        }

        guard !selection.isEmpty || !selectedBoundaryIDs.isEmpty else { return }
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

    private func setupDefaultNodes() {
        _ = appState.ensureMainWorkflow()
    }
}
