//
//  CanvasView.swift
//  Multi-Agent-Flow
//

import SwiftUI
import UniformTypeIdentifiers

struct CanvasView: View {
    @EnvironmentObject var appState: AppState
    let isActive: Bool
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
    let batchSourceNodeIDs: Set<UUID>
    let batchTargetNodeIDs: Set<UUID>
    let batchPreview: BatchConnectionPreview?
    let batchCreatedEdgeIDs: Set<UUID>
    let isBatchConnectMode: Bool

    @State private var scale: CGFloat = 1
    @State private var connectingFromNode: WorkflowNode?
    @State private var tempConnectionEnd: CGPoint?
    @State private var isTransientLassoMode: Bool = false
    @State private var lassoRect: CGRect?
    @State private var suppressCanvasTapClear: Bool = false
    @State private var scrollEventMonitor: Any?

    var onNodeClickInConnectMode: ((WorkflowNode) -> Void)?
    var onNodeSelected: ((WorkflowNode) -> Void)?
    var onNodeSecondarySelected: ((WorkflowNode) -> Void)?
    var onEdgeSelected: ((WorkflowEdge) -> Void)?
    var onEdgeSecondarySelected: ((WorkflowEdge) -> Void)?
    var onDropAgent: ((String, CGPoint) -> Void)?
    var onAssignBatchSources: (() -> Void)?
    var onAssignBatchTargets: (() -> Void)?

    init(
        isActive: Bool = true,
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
        batchSourceNodeIDs: Set<UUID> = [],
        batchTargetNodeIDs: Set<UUID> = [],
        batchPreview: BatchConnectionPreview? = nil,
        batchCreatedEdgeIDs: Set<UUID> = [],
        isBatchConnectMode: Bool = false,
        onNodeClickInConnectMode: ((WorkflowNode) -> Void)? = nil,
        onNodeSelected: ((WorkflowNode) -> Void)? = nil,
        onNodeSecondarySelected: ((WorkflowNode) -> Void)? = nil,
        onEdgeSelected: ((WorkflowEdge) -> Void)? = nil,
        onEdgeSecondarySelected: ((WorkflowEdge) -> Void)? = nil,
        onDropAgent: ((String, CGPoint) -> Void)? = nil,
        onAssignBatchSources: (() -> Void)? = nil,
        onAssignBatchTargets: (() -> Void)? = nil
    ) {
        self.isActive = isActive
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
        self.batchSourceNodeIDs = batchSourceNodeIDs
        self.batchTargetNodeIDs = batchTargetNodeIDs
        self.batchPreview = batchPreview
        self.batchCreatedEdgeIDs = batchCreatedEdgeIDs
        self.isBatchConnectMode = isBatchConnectMode
        self.onNodeClickInConnectMode = onNodeClickInConnectMode
        self.onNodeSelected = onNodeSelected
        self.onNodeSecondarySelected = onNodeSecondarySelected
        self.onEdgeSelected = onEdgeSelected
        self.onEdgeSecondarySelected = onEdgeSecondarySelected
        self.onDropAgent = onDropAgent
        self.onAssignBatchSources = onAssignBatchSources
        self.onAssignBatchTargets = onAssignBatchTargets
    }

    var body: some View {
        Group {
            if isActive {
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
                    onZoomOut: zoomOut,
                    onResetView: resetView,
                    onZoomIn: zoomIn,
                    connectingFromNode: $connectingFromNode,
                    tempConnectionEnd: $tempConnectionEnd,
                    isConnectMode: isConnectMode,
                    connectFromAgentID: connectFromAgentID,
                    batchSourceNodeIDs: batchSourceNodeIDs,
                    batchTargetNodeIDs: batchTargetNodeIDs,
                    batchPreview: batchPreview,
                    batchCreatedEdgeIDs: batchCreatedEdgeIDs,
                    isBatchConnectMode: isBatchConnectMode,
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
                    },
                    onAssignBatchSources: onAssignBatchSources,
                    onAssignBatchTargets: onAssignBatchTargets
                )
            } else {
                Color.clear
            }
        }
        .onChange(of: selectedEdgeID) { _, newValue in
            if newValue != nil {
                suppressCanvasTapClear = true
            }
        }
        .onAppear {
            scale = zoomScale
            updateScrollMonitor(isEnabled: isActive)
            setupDefaultNodes()
        }
        .onDisappear {
            updateScrollMonitor(isEnabled: false)
        }
        .onChange(of: zoomScale) { _, newValue in
            scale = newValue
        }
        .onChange(of: isActive) { _, newValue in
            updateScrollMonitor(isEnabled: newValue)

            if !newValue {
                connectingFromNode = nil
                tempConnectionEnd = nil
                lassoRect = nil
                isTransientLassoMode = false
                suppressCanvasTapClear = false
            }
        }
        .onChange(of: isConnectMode) { _, newValue in
            if !newValue {
                connectFromAgentID = nil
            }
        }
        .clipped()
    }

    private func updateScrollMonitor(isEnabled: Bool) {
        if isEnabled {
            guard scrollEventMonitor == nil else { return }
            scrollEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                if event.modifierFlags.contains(.command) {
                    let delta = event.scrollingDeltaY * 0.01
                    let newScale = max(0.05, min(20.0, self.scale + delta))
                    self.scale = newScale
                    self.zoomScale = newScale
                    return nil
                }
                return event
            }
            return
        }

        if let scrollEventMonitor {
            NSEvent.removeMonitor(scrollEventMonitor)
            self.scrollEventMonitor = nil
        }
    }

    private func setupDefaultNodes() {
        _ = appState.ensureMainWorkflow()
    }

    private func zoomIn() {
        let nextScale = min(scale + 0.2, 20.0)
        withAnimation(.easeInOut(duration: 0.2)) {
            scale = nextScale
        }
        zoomScale = nextScale
    }

    private func zoomOut() {
        let nextScale = max(scale - 0.2, 0.05)
        withAnimation(.easeInOut(duration: 0.2)) {
            scale = nextScale
        }
        zoomScale = nextScale
    }

    private func resetView() {
        withAnimation(.easeInOut(duration: 0.3)) {
            scale = 1.0
            offset = .zero
            lastOffset = .zero
        }
        zoomScale = 1.0
    }
}

struct CanvasZoomControls: View {
    let scale: CGFloat
    let onZoomOut: () -> Void
    let onReset: () -> Void
    let onZoomIn: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            zoomButton(systemName: "minus.magnifyingglass", tooltip: LocalizedString.zoomOut, action: onZoomOut)
            zoomButton(systemName: "arrow.counterclockwise", tooltip: LocalizedString.resetZoom, action: onReset)
            zoomButton(systemName: "plus.magnifyingglass", tooltip: LocalizedString.zoomIn, action: onZoomIn)
        }
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 14, y: 8)
        .help("\(LocalizedString.zoom): \(Int((scale * 100).rounded()))%")
    }

    private func zoomButton(systemName: String, tooltip: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundColor(Color.primary.opacity(0.84))
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.88))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.black.opacity(0.06), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }
}
