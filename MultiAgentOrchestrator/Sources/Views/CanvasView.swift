//
//  CanvasView.swift
//  MultiAgentOrchestrator
//

import SwiftUI
import UniformTypeIdentifiers

struct CanvasView: View {
    @EnvironmentObject var appState: AppState
    @Binding var zoomScale: CGFloat
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var selectedNodeID: UUID?
    @State private var selectedEdgeID: UUID?
    @State private var connectingFromNode: WorkflowNode?
    @State private var tempConnectionEnd: CGPoint?
    @State private var isDraggingCanvas: Bool = false

    @State private var showingSubflowEditor: Bool = false
    @State private var editingSubflowNode: WorkflowNode?
    @State private var currentWorkflowForSubflow: Workflow?

    var isConnectMode: Bool = false
    var onNodeClickInConnectMode: ((WorkflowNode) -> Void)?
    var onNodeSelected: ((WorkflowNode) -> Void)?
    var onEdgeSelected: ((WorkflowEdge) -> Void)?
    var onDropAgent: ((String, CGPoint) -> Void)?

    init(
        zoomScale: Binding<CGFloat> = .constant(1.0),
        isConnectMode: Bool = false,
        onNodeClickInConnectMode: ((WorkflowNode) -> Void)? = nil,
        onNodeSelected: ((WorkflowNode) -> Void)? = nil,
        onEdgeSelected: ((WorkflowEdge) -> Void)? = nil,
        onDropAgent: ((String, CGPoint) -> Void)? = nil
    ) {
        self._zoomScale = zoomScale
        self.isConnectMode = isConnectMode
        self.onNodeClickInConnectMode = onNodeClickInConnectMode
        self.onNodeSelected = onNodeSelected
        self.onEdgeSelected = onEdgeSelected
        self.onDropAgent = onDropAgent
    }

    var body: some View {
        CanvasContentView(
            scale: $scale,
            offset: $offset,
            lastOffset: $lastOffset,
            selectedNodeID: $selectedNodeID,
            selectedEdgeID: $selectedEdgeID,
            connectingFromNode: $connectingFromNode,
            tempConnectionEnd: $tempConnectionEnd,
            onNodeClick: onNodeClickInConnectMode,
            onNodeSelected: onNodeSelected,
            onEdgeSelected: onEdgeSelected,
            onSubflowEdit: handleSubflowEdit
        )
        .onDrop(of: [.text], isTargeted: nil) { providers, location in
            for provider in providers {
                provider.loadObject(ofClass: NSString.self) { item, _ in
                    if let agentName = item as? String {
                        DispatchQueue.main.async {
                            self.onDropAgent?(agentName, location)
                        }
                    }
                }
            }
            return true
        }
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
                selectedEdgeID: $selectedEdgeID,
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
    }

    private func handleSubflowEdit(_ node: WorkflowNode) {
        if let workflow = appState.currentProject?.workflows.first {
            editingSubflowNode = node
            currentWorkflowForSubflow = workflow
            showingSubflowEditor = true
        }
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
                        if connectingFromNode == nil {
                            isDraggingCanvas = true
                            offset = CGSize(
                                width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height
                            )
                        }
                    }
                    .onEnded { _ in
                        if isDraggingCanvas {
                            lastOffset = offset
                            isDraggingCanvas = false
                        }
                    },
                TapGesture(count: 1)
                    .onEnded {
                        selectedNodeID = nil
                        selectedEdgeID = nil
                        connectingFromNode = nil
                        tempConnectionEnd = nil
                    }
            )
        )
    }

    private func setupDefaultNodes() {
        guard let workflow = appState.ensureMainWorkflow(),
              workflow.nodes.isEmpty else { return }

        appState.updateMainWorkflow { workflow in
            var startNode = WorkflowNode(type: .start)
            startNode.position = CGPoint(x: 100, y: 100)

            var endNode = WorkflowNode(type: .end)
            endNode.position = CGPoint(x: 500, y: 100)

            workflow.nodes = [startNode, endNode]
        }
    }
}
