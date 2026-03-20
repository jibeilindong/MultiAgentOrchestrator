//
//  CanvasView.swift
//  Multi-Agent-Flow
//

import SwiftUI
import UniformTypeIdentifiers

struct CanvasView: View {
    @EnvironmentObject var appState: AppState
    @Binding var zoomScale: CGFloat
    @Binding var offset: CGSize
    @Binding var lastOffset: CGSize
    @Binding var selectedNodeID: UUID?
    @Binding var selectedNodeIDs: Set<UUID>
    @Binding var selectedEdgeID: UUID?
    @Binding var selectedBoundaryIDs: Set<UUID>
    @Binding var isConnectMode: Bool
    @Binding var connectionType: WorkflowEditorView.ConnectionType
    @Binding var connectFromAgentID: UUID?
    @Binding var isLassoMode: Bool

    @State private var scale: CGFloat = 1
    @State private var connectingFromNode: WorkflowNode?
    @State private var tempConnectionEnd: CGPoint?
    @State private var isTransientLassoMode: Bool = false
    @State private var lassoRect: CGRect?
    @State private var suppressCanvasTapClear: Bool = false

    var onNodeClickInConnectMode: ((WorkflowNode) -> Void)?
    var onNodeSelected: ((WorkflowNode) -> Void)?
    var onNodeSecondarySelected: ((WorkflowNode) -> Void)?
    var onEdgeSelected: ((WorkflowEdge) -> Void)?
    var onEdgeSecondarySelected: ((WorkflowEdge) -> Void)?
    var onDropAgent: ((String, CGPoint) -> Void)?

    init(
        zoomScale: Binding<CGFloat> = .constant(1),
        offset: Binding<CGSize> = .constant(.zero),
        lastOffset: Binding<CGSize> = .constant(.zero),
        selectedNodeID: Binding<UUID?> = .constant(nil),
        selectedNodeIDs: Binding<Set<UUID>> = .constant([]),
        selectedEdgeID: Binding<UUID?> = .constant(nil),
        selectedBoundaryIDs: Binding<Set<UUID>> = .constant([]),
        isConnectMode: Binding<Bool> = .constant(false),
        connectionType: Binding<WorkflowEditorView.ConnectionType> = .constant(.bidirectional),
        connectFromAgentID: Binding<UUID?> = .constant(nil),
        isLassoMode: Binding<Bool> = .constant(false),
        onNodeClickInConnectMode: ((WorkflowNode) -> Void)? = nil,
        onNodeSelected: ((WorkflowNode) -> Void)? = nil,
        onNodeSecondarySelected: ((WorkflowNode) -> Void)? = nil,
        onEdgeSelected: ((WorkflowEdge) -> Void)? = nil,
        onEdgeSecondarySelected: ((WorkflowEdge) -> Void)? = nil,
        onDropAgent: ((String, CGPoint) -> Void)? = nil
    ) {
        self._zoomScale = zoomScale
        self._offset = offset
        self._lastOffset = lastOffset
        self._selectedNodeID = selectedNodeID
        self._selectedNodeIDs = selectedNodeIDs
        self._selectedEdgeID = selectedEdgeID
        self._selectedBoundaryIDs = selectedBoundaryIDs
        self._isConnectMode = isConnectMode
        self._connectionType = connectionType
        self._connectFromAgentID = connectFromAgentID
        self._isLassoMode = isLassoMode
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
            scale = zoomScale
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

    private func setupDefaultNodes() {
        _ = appState.ensureMainWorkflow()
    }
}
