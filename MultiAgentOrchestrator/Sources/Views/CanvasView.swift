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
    @State private var connectingFromNode: WorkflowNode?
    @State private var tempConnectionEnd: CGPoint?
    @State private var isDraggingCanvas: Bool = false
    @State private var isLassoMode: Bool = false
    @State private var lassoRect: CGRect?

    @State private var copiedNodes: [WorkflowNode] = []
    @State private var copiedEdges: [WorkflowEdge] = []

    @State private var showingSubflowEditor: Bool = false
    @State private var editingSubflowNode: WorkflowNode?
    @State private var currentWorkflowForSubflow: Workflow?

    var onNodeClickInConnectMode: ((WorkflowNode) -> Void)?
    var onDropAgent: ((String, CGPoint) -> Void)?

    init(
        zoomScale: Binding<CGFloat> = .constant(1),
        isConnectMode: Binding<Bool> = .constant(false),
        connectionType: Binding<WorkflowEditorView.ConnectionType> = .constant(.unidirectional),
        connectFromAgentID: Binding<UUID?> = .constant(nil),
        onNodeClickInConnectMode: ((WorkflowNode) -> Void)? = nil,
        onDropAgent: ((String, CGPoint) -> Void)? = nil
    ) {
        self._zoomScale = zoomScale
        self._isConnectMode = isConnectMode
        self._connectionType = connectionType
        self._connectFromAgentID = connectFromAgentID
        self.onNodeClickInConnectMode = onNodeClickInConnectMode
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
            isLassoMode: $isLassoMode,
            lassoRect: $lassoRect,
            connectingFromNode: $connectingFromNode,
            tempConnectionEnd: $tempConnectionEnd,
            isConnectMode: isConnectMode,
            connectFromAgentID: connectFromAgentID,
            onNodeClick: onNodeClickInConnectMode,
            onSubflowEdit: handleSubflowEdit
        )
        .gesture(createCanvasGesture())
        .onAppear {
            NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                if event.modifierFlags.contains(.command) {
                    let delta = event.scrollingDeltaY * 0.01
                    let newScale = max(0.1, min(2.0, self.scale + delta))
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
                onPasteSelection: pasteSelection,
                onDeleteSelection: deleteSelection,
                appState: appState
            )
        )
        .sheet(isPresented: $showingSubflowEditor) {
            if let node = editingSubflowNode, let workflow = currentWorkflowForSubflow {
                SubflowEditorView(
                    parentNode: node,
                    parentWorkflow: workflow,
                    isPresented: $showingSubflowEditor
                )
                .environmentObject(appState)
            }
        }
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

    private func handleSubflowEdit(_ node: WorkflowNode) {
        if let workflow = appState.currentProject?.workflows.first {
            editingSubflowNode = node
            currentWorkflowForSubflow = workflow
            showingSubflowEditor = true
        }
    }

    private func copySelection() {
        guard let workflow = appState.currentProject?.workflows.first else { return }
        let selection = activeSelection
        guard !selection.isEmpty else { return }

        copiedNodes = workflow.nodes.filter { selection.contains($0.id) }
        copiedEdges = workflow.edges.filter { selection.contains($0.fromNodeID) && selection.contains($0.toNodeID) }
    }

    private func pasteSelection() {
        guard !copiedNodes.isEmpty else { return }

        appState.updateMainWorkflow { workflow in
            var nodeIDMapping: [UUID: UUID] = [:]

            for sourceNode in copiedNodes {
                var newNode = WorkflowNode(type: sourceNode.type)
                newNode.agentID = sourceNode.agentID
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
        }
    }

    private func deleteSelection() {
        let selection = activeSelection
        guard !selection.isEmpty else { return }
        appState.removeNodes(selection)
        selectedNodeID = nil
        selectedNodeIDs.removeAll()
        selectedEdgeID = nil
    }

    private func deleteSelectedEdge() {
        guard let selectedEdgeID else { return }
        appState.removeEdge(selectedEdgeID)
        self.selectedEdgeID = nil
    }

    private func createCanvasGesture() -> some Gesture {
        SimultaneousGesture(
            MagnificationGesture()
                .onChanged { value in
                    scale = lastOffset == .zero ? value.magnitude : scale
                    scale = max(0.1, min(scale, 2.0))
                }
                .onEnded { _ in
                    lastOffset = offset
                    zoomScale = scale
                },
            SimultaneousGesture(
                DragGesture(minimumDistance: 5)
                    .onChanged { value in
                        guard !isLassoMode, connectingFromNode == nil else { return }
                        isDraggingCanvas = true
                        offset = CGSize(
                            width: lastOffset.width + value.translation.width,
                            height: lastOffset.height + value.translation.height
                        )
                    }
                    .onEnded { _ in
                        guard !isLassoMode else { return }
                        if isDraggingCanvas {
                            lastOffset = offset
                            isDraggingCanvas = false
                        }
                    },
                TapGesture(count: 1)
                    .onEnded {
                        guard !isLassoMode else { return }
                        selectedNodeID = nil
                        selectedNodeIDs.removeAll()
                        selectedEdgeID = nil
                        connectingFromNode = nil
                        tempConnectionEnd = nil
                        connectFromAgentID = nil
                    }
            )
        )
    }

    private func setupDefaultNodes() {
        guard let workflow = appState.ensureMainWorkflow(), workflow.nodes.isEmpty else { return }

        appState.updateMainWorkflow { workflow in
            var startNode = WorkflowNode(type: .start)
            startNode.position = CGPoint(x: 100, y: 100)

            var endNode = WorkflowNode(type: .end)
            endNode.position = CGPoint(x: 500, y: 100)

            workflow.nodes = [startNode, endNode]
        }
    }
}
