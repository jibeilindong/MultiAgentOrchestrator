//
//  CanvasContentView.swift
//  Multi-Agent-Flow
//

import SwiftUI
import UniformTypeIdentifiers

struct CanvasContentView: View {
    @EnvironmentObject var appState: AppState
    @Binding var scale: CGFloat
    @Binding var offset: CGSize
    @Binding var lastOffset: CGSize
    @Binding var selectedNodeID: UUID?
    @Binding var selectedNodeIDs: Set<UUID>
    @Binding var selectedEdgeID: UUID?
    @Binding var selectedBoundaryIDs: Set<UUID>
    @Binding var suppressCanvasTapClear: Bool
    @Binding var isLassoMode: Bool
    @Binding var isTransientLassoMode: Bool
    @Binding var lassoRect: CGRect?
    @Binding var connectingFromNode: WorkflowNode?
    @Binding var tempConnectionEnd: CGPoint?
    var isConnectMode: Bool = false
    var connectFromAgentID: UUID?
    var batchSourceNodeIDs: Set<UUID> = []
    var batchTargetNodeIDs: Set<UUID> = []
    var batchPreview: BatchConnectionPreview?
    var batchCreatedEdgeIDs: Set<UUID> = []
    var isBatchConnectMode: Bool = false
    var onNodeClick: ((WorkflowNode) -> Void)?
    var onNodeSelected: ((WorkflowNode) -> Void)?
    var onNodeSecondarySelected: ((WorkflowNode) -> Void)?
    var onEdgeSelected: ((WorkflowEdge) -> Void)?
    var onEdgeSecondarySelected: ((WorkflowEdge) -> Void)?
    var onAssignBatchSources: (() -> Void)?
    var onAssignBatchTargets: (() -> Void)?

    @State private var isDraggingOverCanvas: Bool = false
    @State private var rightMouseLassoStart: CGPoint?
    @State private var boundaryDragSnapshots: [UUID: BoundaryDragSnapshot] = [:]
    @State private var draggingBoundaryID: UUID?
    @State private var legendFrame: CGRect = .null
    @State private var transientNodePositions: [UUID: CGPoint] = [:]
    @State private var transientBoundaryRects: [UUID: CGRect] = [:]
    @State private var edgeGeometryCache = WorkflowCanvasEdgeGeometryCache()

    private var currentWorkflow: Workflow? {
        appState.currentProject?.workflows.first
    }

    private var currentConnectionCounts: [UUID: WorkflowNodeConnectionCounts] {
        currentWorkflow?.connectionCountsByNodeID() ?? [:]
    }

    private var visibleLegendGroupCount: Int {
        guard let workflow = currentWorkflow else { return 0 }

        let nodeGroups = Set(
            workflow.nodes.compactMap { node in
                CanvasStylePalette.normalizedHex(node.displayColorHex)
            }
        )
        let edgeGroups = Set(
            workflow.edges.compactMap { edge in
                CanvasStylePalette.normalizedHex(edge.displayColorHex)
            }
        )

        return nodeGroups.count + edgeGroups.count
    }

    private var fallbackLegendFrame: CGRect {
        guard visibleLegendGroupCount > 0 else { return .null }

        let scaledRowHeight = max(42, 38 * appState.canvasDisplaySettings.textScale)
        let scaledHeaderHeight = max(22, 18 * appState.canvasDisplaySettings.textScale)
        let interRowSpacing = CGFloat(max(0, visibleLegendGroupCount - 1)) * 10
        let height = 14 + 12 + scaledHeaderHeight + 10 + (CGFloat(visibleLegendGroupCount) * scaledRowHeight) + interRowSpacing + 12
        let width = max(360, 320 + (appState.canvasDisplaySettings.textScale * 40))

        return CGRect(x: 8, y: 8, width: width, height: height)
    }

    private var legendInteractionFrame: CGRect {
        let candidates = [
            legendFrame.isNull ? CGRect.null : legendFrame.insetBy(dx: -16, dy: -16),
            fallbackLegendFrame
        ].filter { !$0.isNull && $0.width > 0 && $0.height > 0 }

        return candidates.reduce(CGRect.null) { partial, rect in
            partial.isNull ? rect : partial.union(rect)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let canvasNodeFramesByID = nodeFramesByID(in: geometry)
            let edgeGeometry = edgeGeometryCache.resolve(
                workflow: currentWorkflow,
                nodeFramesByID: canvasNodeFramesByID,
                transientNodeIDs: Set(transientNodePositions.keys)
            )
            let canvasEdgeLayouts = edgeGeometry.edgeLayouts
            let sharedEdgeHitLayouts = edgeGeometry.sharedHitLayouts
            let previewLineLayouts = buildPreviewLineLayouts(nodeFramesByID: canvasNodeFramesByID)
            let canvasLayer = ZStack {
                GridBackground()
                    .frame(width: geometry.size.width * 10, height: geometry.size.height * 10)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                    .scaleEffect(scale)
                    .offset(offset)
                    .opacity(isDraggingOverCanvas ? 0.6 : 1.0)

                if isDraggingOverCanvas {
                    DropIndicatorView(geometry: geometry)
                }

                ConnectionLinesView(
                    edgeLayouts: canvasEdgeLayouts,
                    sharedHitLayouts: sharedEdgeHitLayouts,
                    previewLineLayouts: previewLineLayouts,
                    blockedRects: Array(canvasNodeFramesByID.values),
                    lineColor: appState.canvasDisplaySettings.lineColor.color,
                    lineWidth: appState.canvasDisplaySettings.lineWidth,
                    textScale: appState.canvasDisplaySettings.textScale,
                    textColor: .black,
                    selectedEdgeID: $selectedEdgeID,
                    recentlyCreatedEdgeIDs: batchCreatedEdgeIDs,
                    onEdgeSelected: { edge in
                        suppressCanvasTapClear = true
                        selectedNodeID = nil
                        selectedNodeIDs.removeAll()
                        selectedBoundaryIDs.removeAll()
                        onEdgeSelected?(edge)
                    }
                )

                WorkflowBoundaryOverlay(
                    groups: explicitBoundaryRects(in: geometry),
                    fallbackGroups: collaborationGroups(in: geometry),
                    selectedBoundaryIDs: selectedBoundaryIDs,
                    draggingBoundaryID: draggingBoundaryID,
                    onBoundaryTap: { boundaryID in
                        suppressCanvasTapClear = true
                        selectedBoundaryIDs = [boundaryID]
                        selectedNodeID = nil
                        selectedEdgeID = nil
                        connectingFromNode = nil
                        tempConnectionEnd = nil
                    },
                    onBoundaryDragChanged: { boundaryID, translation in
                        handleBoundaryDrag(boundaryID: boundaryID, translation: translation)
                    },
                    onBoundaryDragEnded: { boundaryID in
                        commitBoundaryDrag(boundaryID: boundaryID)
                        boundaryDragSnapshots.removeValue(forKey: boundaryID)
                        if draggingBoundaryID == boundaryID {
                            draggingBoundaryID = nil
                        }
                    }
                )

                if let fromNode = connectingFromNode,
                   let endPoint = tempConnectionEnd {
                    ConnectionLineShape(
                        from: adjustedPosition(resolvedPosition(for: fromNode), geometry: geometry),
                        to: endPoint
                    )
                    .stroke(Color.orange.opacity(0.8), style: StrokeStyle(lineWidth: 3, dash: [6, 3]))
                }

                NodesView(
                    currentWorkflow: currentWorkflow,
                    selectedNodeID: $selectedNodeID,
                    selectedNodeIDs: $selectedNodeIDs,
                    selectedEdgeID: $selectedEdgeID,
                    selectedBoundaryIDs: $selectedBoundaryIDs,
                    connectingFromNode: $connectingFromNode,
                    tempConnectionEnd: $tempConnectionEnd,
                    transientNodePositions: $transientNodePositions,
                    scale: scale,
                    offset: offset,
                    geometry: geometry,
                    isConnectMode: isConnectMode,
                    connectFromAgentID: connectFromAgentID,
                    batchSourceNodeIDs: batchSourceNodeIDs,
                    batchTargetNodeIDs: batchTargetNodeIDs,
                    onNodeClick: onNodeClick,
                    onNodeSelected: onNodeSelected,
                    onNodeDragEnded: commitNodeDrag
                )
                .environmentObject(appState)

                if let lassoRect {
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.08))
                        .frame(width: lassoRect.width, height: lassoRect.height)
                        .overlay(
                            Rectangle()
                                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [6, 3]))
                        )
                        .position(x: lassoRect.midX, y: lassoRect.midY)
                }
            }
            let interactiveCanvas = Group {
                if isLassoMode || isTransientLassoMode {
                    canvasLayer
                        .contentShape(Rectangle())
                        .highPriorityGesture(lassoGesture(in: geometry))
                } else {
                    canvasLayer
                        .contentShape(Rectangle())
                }
            }
            interactiveCanvas
            .coordinateSpace(name: CanvasOverlayFramePreferenceKey.coordinateSpaceName)
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 10) {
                    CanvasGroupLegendView(
                        workflow: currentWorkflow,
                        selectedNodeIDs: selectedNodeIDs,
                        selectedEdgeID: selectedEdgeID,
                        textScale: appState.canvasDisplaySettings.textScale
                    )

                    if isBatchConnectMode {
                        BatchCanvasQuickBar(
                            selectionCount: selectedNodeIDs.isEmpty ? (selectedNodeID == nil ? 0 : 1) : selectedNodeIDs.count,
                            sourceCount: batchSourceNodeIDs.count,
                            targetCount: batchTargetNodeIDs.count,
                            onAssignSources: onAssignBatchSources,
                            onAssignTargets: onAssignBatchTargets
                        )
                    }
                }
                .padding(.top, 14)
                .padding(.leading, 14)
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .preference(
                                key: CanvasOverlayFramePreferenceKey.self,
                                value: proxy.frame(in: .named(CanvasOverlayFramePreferenceKey.coordinateSpaceName))
                            )
                    }
                )
            }
            .onPreferenceChange(CanvasOverlayFramePreferenceKey.self) { legendFrame = $0 }
            .background(
                BlankCanvasDragMonitor(
                    isEnabled: { !(isLassoMode || isTransientLassoMode) },
                    shouldIgnoreLocation: { location in
                        legendInteractionFrame.contains(location)
                    },
                    onEdgeHit: { location in
                        guard let edge = edge(at: location, in: canvasEdgeLayouts) else { return false }
                        suppressCanvasTapClear = true
                        selectedNodeID = nil
                        selectedNodeIDs.removeAll()
                        selectedBoundaryIDs.removeAll()
                        selectedEdgeID = edge.id
                        onEdgeSelected?(edge)
                        return true
                    },
                    isBlankLocation: { location in
                        isBlankCanvasLocation(location, geometry: geometry, edgeLayouts: canvasEdgeLayouts)
                    },
                    currentOffset: { offset },
                    onBlankClick: {
                        clearCanvasSelection()
                    },
                    onDragStart: {
                        NSCursor.openHand.set()
                    },
                    onDragChanged: { translation, startOffset in
                        offset = CGSize(
                            width: startOffset.width + translation.width,
                            height: startOffset.height + translation.height
                        )
                        NSCursor.closedHand.set()
                    },
                    onDragEnded: { didDrag, location in
                        if didDrag {
                            lastOffset = offset
                        }
                        NSCursor.arrow.set()
                        _ = location
                    }
                )
            )
            .background(
                RightMouseDragMonitor(
                    shouldIgnoreLocation: { location in
                        legendInteractionFrame.contains(location)
                    },
                    onStart: { start in
                        isTransientLassoMode = true
                        rightMouseLassoStart = start
                        lassoRect = CGRect(origin: start, size: .zero)
                    },
                    onDrag: { location in
                        guard isTransientLassoMode, let start = rightMouseLassoStart else { return }
                        lassoRect = CGRect(
                            x: min(start.x, location.x),
                            y: min(start.y, location.y),
                            width: abs(location.x - start.x),
                            height: abs(location.y - start.y)
                        )
                    },
                    onEnd: { location in
                        defer {
                            rightMouseLassoStart = nil
                            lassoRect = nil
                            isTransientLassoMode = false
                        }
                        guard let start = rightMouseLassoStart else { return }
                        let dx = location.x - start.x
                        let dy = location.y - start.y
                        let distance = hypot(dx, dy)

                        if distance < 4 {
                            if let edge = edge(at: location, in: canvasEdgeLayouts) {
                                suppressCanvasTapClear = true
                                selectedNodeID = nil
                                selectedNodeIDs.removeAll()
                                selectedBoundaryIDs.removeAll()
                                selectedEdgeID = edge.id
                                onEdgeSecondarySelected?(edge)
                                return
                            }
                            if let node = node(at: location, geometry: geometry) {
                                suppressCanvasTapClear = true
                                selectedNodeIDs = [node.id]
                                selectedNodeID = node.id
                                selectedEdgeID = nil
                                selectedBoundaryIDs.removeAll()
                                onNodeSecondarySelected?(node)
                            } else {
                                suppressCanvasTapClear = false
                            }
                            return
                        }

                        let rect = CGRect(
                            x: min(start.x, location.x),
                            y: min(start.y, location.y),
                            width: abs(location.x - start.x),
                            height: abs(location.y - start.y)
                        )
                        applyLassoSelection(with: rect, geometry: geometry)
                        suppressCanvasTapClear = false
                    }
                )
            )
            .onDrop(of: [.text], isTargeted: $isDraggingOverCanvas) { providers, location in
                handleDrop(providers: providers, location: location, geometry: geometry)
            }
        }
    }

    private func adjustedPosition(_ position: CGPoint, geometry: GeometryProxy) -> CGPoint {
        let centerX = geometry.size.width / 2
        let centerY = geometry.size.height / 2
        return CGPoint(
            x: position.x * scale + offset.width + centerX,
            y: position.y * scale + offset.height + centerY
        )
    }

    private func resolvedPosition(for node: WorkflowNode) -> CGPoint {
        transientNodePositions[node.id] ?? node.position
    }

    private func resolvedRect(for boundary: WorkflowBoundary) -> CGRect {
        transientBoundaryRects[boundary.id] ?? boundary.rect
    }

    private func handleDrop(providers: [NSItemProvider], location: CGPoint, geometry: GeometryProxy) -> Bool {
        for provider in providers {
            provider.loadObject(ofClass: NSString.self) { item, _ in
                if let agentName = item as? String {
                    DispatchQueue.main.async {
                        if agentName.hasPrefix("nodeType:") {
                            let rawType = String(agentName.dropFirst("nodeType:".count))
                            let nodeType = WorkflowNode.NodeType(rawValue: rawType) ?? WorkflowNode.NodeType.decoded(from: rawType)
                            addWorkflowNodeToCanvas(type: nodeType, at: location, geometry: geometry)
                        } else if agentName.hasPrefix("template:") {
                            let templateID = String(agentName.dropFirst("template:".count))
                            addTemplateNodeToCanvas(templateID: templateID, at: location, geometry: geometry)
                        } else {
                            addAgentNodeToCanvas(agentName: agentName, at: location, geometry: geometry)
                        }
                    }
                }
            }
        }
        return true
    }

    private func addWorkflowNodeToCanvas(type: WorkflowNode.NodeType, at location: CGPoint, geometry: GeometryProxy) {
        let centerX = geometry.size.width / 2
        let centerY = geometry.size.height / 2
        let rawPosition = CGPoint(
            x: (location.x - centerX - offset.width) / scale,
            y: (location.y - centerY - offset.height) / scale
        )
        let position = appState.snapPointToGrid(rawPosition)
        appState.addNode(type: type, position: position)
    }

    private func addAgentNodeToCanvas(agentName: String, at location: CGPoint, geometry: GeometryProxy) {
        let centerX = geometry.size.width / 2
        let centerY = geometry.size.height / 2
        let rawPosition = CGPoint(
            x: (location.x - centerX - offset.width) / scale,
            y: (location.y - centerY - offset.height) / scale
        )
        let position = appState.snapPointToGrid(rawPosition)
        appState.addAgentNode(agentName: agentName, position: position)
    }

    private func addTemplateNodeToCanvas(templateID: String, at location: CGPoint, geometry: GeometryProxy) {
        let centerX = geometry.size.width / 2
        let centerY = geometry.size.height / 2
        let rawPosition = CGPoint(
            x: (location.x - centerX - offset.width) / scale,
            y: (location.y - centerY - offset.height) / scale
        )
        let position = appState.snapPointToGrid(rawPosition)

        guard let agent = appState.addNewAgent(templateID: templateID) else { return }
        appState.addAgentNode(agentName: agent.name, position: position)
    }

    private func lassoGesture(in geometry: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                let lassoEnabled = isLassoMode || isTransientLassoMode
                guard lassoEnabled else { return }

                let start = value.startLocation
                let current = value.location
                lassoRect = CGRect(
                    x: min(start.x, current.x),
                    y: min(start.y, current.y),
                    width: abs(current.x - start.x),
                    height: abs(current.y - start.y)
                )
            }
            .onEnded { _ in
                let lassoEnabled = isLassoMode || isTransientLassoMode
                guard lassoEnabled, let lassoRect else {
                    lassoRect = nil
                    isTransientLassoMode = false
                    return
                }

                applyLassoSelection(with: lassoRect, geometry: geometry)
                self.lassoRect = nil
                if !isLassoMode {
                    isTransientLassoMode = false
                }
            }
    }

    private func applyLassoSelection(with rect: CGRect, geometry: GeometryProxy) {
        let workflow = currentWorkflow
        let selectedNodesInRect = Set((workflow?.nodes ?? []).compactMap { node -> UUID? in
            nodeFrame(for: node, geometry: geometry).intersects(rect) ? node.id : nil
        })

        let selectedBoundaries = Set((workflow?.boundaries ?? []).compactMap { boundary -> UUID? in
            boundaryFrame(for: boundary, geometry: geometry).intersects(rect) ? boundary.id : nil
        })

        let boundaryContainedNodes = Set((workflow?.boundaries ?? [])
            .filter { selectedBoundaries.contains($0.id) }
            .flatMap { boundary in
                (workflow?.nodes ?? []).compactMap { node in
                    boundaryFrame(for: boundary, geometry: geometry).contains(adjustedPosition(resolvedPosition(for: node), geometry: geometry)) ? node.id : nil
                }
            })

        let selected = selectedNodesInRect.union(boundaryContainedNodes)
        selectedBoundaryIDs = selectedBoundaries
        selectedNodeIDs = selected
        selectedNodeID = selected.count == 1 && selectedBoundaries.isEmpty ? selected.first : nil
        selectedEdgeID = nil
    }

    private func handleBoundaryDrag(boundaryID: UUID, translation: CGSize) {
        guard let workflow = currentWorkflow else { return }

        if boundaryDragSnapshots[boundaryID] == nil,
           let boundary = workflow.boundaries.first(where: { $0.id == boundaryID }) {
            boundaryDragSnapshots[boundaryID] = BoundaryDragSnapshot(
                rect: boundary.rect
            )
        }

        guard let snapshot = boundaryDragSnapshots[boundaryID] else { return }
        let dx = translation.width / scale
        let dy = translation.height / scale

        suppressCanvasTapClear = true
        draggingBoundaryID = boundaryID
        selectedBoundaryIDs = [boundaryID]
        selectedNodeIDs.removeAll()
        selectedNodeID = nil
        selectedEdgeID = nil

        transientBoundaryRects[boundaryID] = appState.snapRectToGrid(
            snapshot.rect.offsetBy(dx: dx, dy: dy)
        )
    }

    private func commitBoundaryDrag(boundaryID: UUID) {
        guard let finalRect = transientBoundaryRects[boundaryID] else { return }

        appState.updateMainWorkflow { workflow in
            guard let boundaryIndex = workflow.boundaries.firstIndex(where: { $0.id == boundaryID }) else { return }
            workflow.boundaries[boundaryIndex].rect = finalRect
            workflow.boundaries[boundaryIndex].updatedAt = Date()
        }

        transientBoundaryRects.removeValue(forKey: boundaryID)
    }

    private func commitNodeDrag(_ positions: [UUID: CGPoint]) {
        guard !positions.isEmpty else { return }

        appState.updateMainWorkflow { workflow in
            for index in workflow.nodes.indices {
                guard let position = positions[workflow.nodes[index].id] else { continue }
                workflow.nodes[index].position = position
            }
        }
    }

    private func clearCanvasSelection() {
        selectedNodeID = nil
        selectedNodeIDs.removeAll()
        selectedEdgeID = nil
        selectedBoundaryIDs.removeAll()
        connectingFromNode = nil
        tempConnectionEnd = nil
        suppressCanvasTapClear = false
    }

    private func collaborationGroups(in geometry: GeometryProxy) -> [CGRect] {
        guard currentWorkflow?.boundaries.isEmpty ?? true else { return [] }
        guard let workflow = currentWorkflow else { return [] }

        let nodesByID = Dictionary(uniqueKeysWithValues: workflow.nodes.map { ($0.id, $0) })
        let adjacency = workflow.edges.reduce(into: [UUID: Set<UUID>]()) { partial, edge in
            partial[edge.fromNodeID, default: []].insert(edge.toNodeID)
            partial[edge.toNodeID, default: []].insert(edge.fromNodeID)
        }

        var visited = Set<UUID>()
        var rects: [CGRect] = []

        for node in workflow.nodes where !visited.contains(node.id) {
            var stack = [node.id]
            var component: [WorkflowNode] = []

            while let current = stack.popLast() {
                guard visited.insert(current).inserted else { continue }
                if let node = nodesByID[current] {
                    component.append(node)
                }
                stack.append(contentsOf: adjacency[current, default: []])
            }

            guard component.count > 1 else { continue }
            let merged = component
                .map { nodeFrame(for: $0, geometry: geometry) }
                .reduce(CGRect.null) { $0.union($1) }
            rects.append(merged.insetBy(dx: -28, dy: -28))
        }

        return rects
    }

    private func explicitBoundaryRects(in geometry: GeometryProxy) -> [WorkflowBoundaryDisplayGroup] {
        guard let workflow = currentWorkflow else { return [] }

        return workflow.boundaries.map { boundary in
            let rect = boundaryFrame(for: boundary, geometry: geometry)
            return WorkflowBoundaryDisplayGroup(id: boundary.id, title: boundary.title, rect: rect)
        }
    }

    private func boundaryFrame(for boundary: WorkflowBoundary, geometry: GeometryProxy) -> CGRect {
        let boundaryRect = resolvedRect(for: boundary)
        let origin = adjustedPosition(CGPoint(x: boundaryRect.minX, y: boundaryRect.minY), geometry: geometry)
        let opposite = adjustedPosition(CGPoint(x: boundaryRect.maxX, y: boundaryRect.maxY), geometry: geometry)
        return CGRect(
            x: min(origin.x, opposite.x),
            y: min(origin.y, opposite.y),
            width: abs(opposite.x - origin.x),
            height: abs(opposite.y - origin.y)
        )
    }

    private func nodeFrame(for node: WorkflowNode, geometry: GeometryProxy) -> CGRect {
        let center = adjustedPosition(resolvedPosition(for: node), geometry: geometry)
        let size = nodeSize(for: node)
        return CGRect(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    private func nodeSize(for node: WorkflowNode) -> CGSize {
        switch node.type {
        case .start:
            return CGSize(width: 100, height: 68)
        case .agent:
            let outgoing = currentConnectionCounts[node.id]?.outgoing ?? 0
            return CGSize(width: 110, height: outgoing == 0 ? 92 : 78)
        }
    }

    private func node(at location: CGPoint, geometry: GeometryProxy) -> WorkflowNode? {
        guard let workflow = currentWorkflow else { return nil }
        return workflow.nodes.reversed().first { node in
            nodeFrame(for: node, geometry: geometry).contains(location)
        }
    }

    private func boundary(at location: CGPoint, geometry: GeometryProxy) -> WorkflowBoundary? {
        guard let workflow = currentWorkflow else { return nil }
        return workflow.boundaries.reversed().first { boundary in
            boundaryFrame(for: boundary, geometry: geometry)
                .insetBy(dx: -8, dy: -8)
                .contains(location)
        }
    }

    private func edge(at location: CGPoint, in layouts: [WorkflowCanvasEdgeLayout]) -> WorkflowEdge? {
        let tolerance = max(10, appState.canvasDisplaySettings.lineWidth + 6)
        return layouts
            .compactMap { layout -> (WorkflowEdge, CGFloat)? in
                guard let distance = layout.distance(to: location, tolerance: tolerance) else { return nil }
                return (layout.edge, distance)
            }
            .min(by: { $0.1 < $1.1 })?
            .0
    }

    private func isBlankCanvasLocation(
        _ location: CGPoint,
        geometry: GeometryProxy,
        edgeLayouts: [WorkflowCanvasEdgeLayout]
    ) -> Bool {
        guard node(at: location, geometry: geometry) == nil else { return false }
        guard edge(at: location, in: edgeLayouts) == nil else { return false }
        guard boundary(at: location, geometry: geometry) == nil else { return false }
        return true
    }

    private func nodeFramesByID(in geometry: GeometryProxy) -> [UUID: CGRect] {
        guard let workflow = currentWorkflow else { return [:] }
        return Dictionary(
            uniqueKeysWithValues: workflow.nodes.map { node in
                (node.id, nodeFrame(for: node, geometry: geometry))
            }
        )
    }

    private func buildPreviewLineLayouts(
        nodeFramesByID: [UUID: CGRect]
    ) -> [WorkflowCanvasPreviewLineLayout] {
        guard currentWorkflow != nil else { return [] }

        return (batchPreview?.newEdges ?? []).compactMap { candidate in
            guard candidate.status == .new,
                  let fromFrame = nodeFramesByID[candidate.fromNodeID],
                  let toFrame = nodeFramesByID[candidate.toNodeID] else {
                return nil
            }

            return WorkflowCanvasPreviewLineLayout(
                id: candidate.id,
                from: fromFrame.center,
                to: toFrame.center
            )
        }
    }
}

private struct BoundaryDragSnapshot {
    let rect: CGRect
}

struct WorkflowBoundaryDisplayGroup: Identifiable {
    let id: UUID
    let title: String
    let rect: CGRect
}

struct WorkflowBoundaryOverlay: View {
    let groups: [WorkflowBoundaryDisplayGroup]
    let fallbackGroups: [CGRect]
    let selectedBoundaryIDs: Set<UUID>
    let draggingBoundaryID: UUID?
    var onBoundaryTap: ((UUID) -> Void)?
    var onBoundaryDragChanged: ((UUID, CGSize) -> Void)?
    var onBoundaryDragEnded: ((UUID) -> Void)?

    var body: some View {
        ZStack {
            ForEach(groups) { group in
                let rect = group.rect
                let isSelected = selectedBoundaryIDs.contains(group.id)
                let isDragging = draggingBoundaryID == group.id
                let boundaryDragGesture = LongPressGesture(minimumDuration: 0.2)
                    .sequenced(before: DragGesture(minimumDistance: 0))
                    .onChanged { value in
                        switch value {
                        case .second(true, let drag?):
                            onBoundaryDragChanged?(group.id, drag.translation)
                        default:
                            break
                        }
                    }
                    .onEnded { _ in
                        onBoundaryDragEnded?(group.id)
                    }

                Rectangle()
                    .fill((isDragging ? Color.accentColor : (isSelected ? Color.accentColor : Color.orange)).opacity(isDragging ? 0.14 : (isSelected ? 0.09 : 0.04)))
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .allowsHitTesting(false)
                    .shadow(color: isDragging ? Color.accentColor.opacity(0.28) : .clear, radius: isDragging ? 10 : 0, x: 0, y: 3)

                Rectangle()
                    .stroke(
                        isDragging ? Color.accentColor : (isSelected ? Color.accentColor : Color.orange.opacity(0.85)),
                        style: StrokeStyle(lineWidth: isDragging ? 3 : (isSelected ? 2.5 : 2), dash: isDragging ? [] : [8, 4])
                    )
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .shadow(color: isDragging ? Color.accentColor.opacity(0.35) : .clear, radius: isDragging ? 6 : 0, x: 0, y: 0)

                Rectangle()
                    .stroke(Color.primary.opacity(0.001), lineWidth: 14)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onBoundaryTap?(group.id)
                    }
                    .simultaneousGesture(boundaryDragGesture)

                Text(group.title)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background((isDragging ? Color.accentColor : (isSelected ? Color.accentColor : Color.orange)).opacity(0.95))
                    .foregroundColor(.white)
                    .position(x: rect.minX + 42, y: rect.minY + 12)

                if isDragging {
                    Text("Dragging")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.95))
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                        .position(x: rect.maxX - 44, y: rect.minY + 12)
                }
            }

            ForEach(Array(fallbackGroups.indices), id: \.self) { index in
                let rect = fallbackGroups[index]
                Rectangle()
                    .fill(Color.orange.opacity(0.03))
                    .overlay(
                        Rectangle()
                            .stroke(Color.orange.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [8, 4]))
                    )
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
            }
        }
    }
}

struct DropIndicatorView: View {
    let geometry: GeometryProxy

    var body: some View {
        ZStack {
            Color.blue.opacity(0.08)

            Circle()
                .stroke(Color.blue, lineWidth: 2)
                .fill(Color.blue.opacity(0.15))
                .frame(width: 90, height: 90)
                .overlay(
                    Circle()
                        .stroke(Color.blue, lineWidth: 2)
                        .frame(width: 100, height: 100)
                        .opacity(0.5)
                )

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Text(LocalizedString.dropToAddNode)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.blue)
                        .cornerRadius(8)
                        .shadow(radius: 2)
                        .position(x: geometry.size.width - 70, y: geometry.size.height - 40)
                }
            }
        }
    }
}

private struct CanvasGroupLegendView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var localizationManager = LocalizationManager.shared

    let workflow: Workflow?
    let selectedNodeIDs: Set<UUID>
    let selectedEdgeID: UUID?
    let textScale: CGFloat

    @State private var titleDrafts: [String: String] = [:]
    @State private var editingGroupID: String?
    @FocusState private var focusedGroupID: String?

    private var groups: [CanvasLegendGroup] {
        guard let workflow else { return [] }

        let storedGroupsByID = Dictionary(uniqueKeysWithValues: workflow.colorGroups.map { ($0.id, $0) })
        let nodeGroups = Dictionary(grouping: workflow.nodes.compactMap { node -> (String, UUID)? in
            guard let colorHex = CanvasStylePalette.normalizedHex(node.displayColorHex) else { return nil }
            return (colorHex, node.id)
        }, by: \.0)

        let edgeGroups = Dictionary(grouping: workflow.edges.compactMap { edge -> (String, UUID)? in
            guard let colorHex = CanvasStylePalette.normalizedHex(edge.displayColorHex) else { return nil }
            return (colorHex, edge.id)
        }, by: \.0)

        let nodeLegendGroups = nodeGroups.keys.sorted().map { colorHex -> CanvasLegendGroup in
            let id = CanvasColorGroup(kind: .node, colorHex: colorHex, title: "").id
            let stored = storedGroupsByID[id]
            let itemIDs = nodeGroups[colorHex]?.map(\.1) ?? []
            return CanvasLegendGroup(
                kind: .node,
                colorHex: colorHex,
                title: stored?.title ?? "",
                itemCount: itemIDs.count,
                isSelected: !selectedNodeIDs.isEmpty && itemIDs.contains(where: selectedNodeIDs.contains)
            )
        }

        let edgeLegendGroups = edgeGroups.keys.sorted().map { colorHex -> CanvasLegendGroup in
            let id = CanvasColorGroup(kind: .edge, colorHex: colorHex, title: "").id
            let stored = storedGroupsByID[id]
            let itemIDs = edgeGroups[colorHex]?.map(\.1) ?? []
            return CanvasLegendGroup(
                kind: .edge,
                colorHex: colorHex,
                title: stored?.title ?? "",
                itemCount: itemIDs.count,
                isSelected: selectedEdgeID.map { itemIDs.contains($0) } ?? false
            )
        }

        return nodeLegendGroups + edgeLegendGroups
    }

    var body: some View {
        if !groups.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(legendTitle)
                    .font(.system(size: 11 * textScale, weight: .semibold))
                    .foregroundColor(.secondary)

                ForEach(groups) { group in
                    legendGroupRow(group)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(NSColor.windowBackgroundColor).opacity(group.isSelected ? 0.98 : 0.92))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(
                                group.isSelected
                                    ? (CanvasStylePalette.color(from: group.colorHex) ?? .accentColor).opacity(0.75)
                                    : Color.black.opacity(0.08),
                                lineWidth: group.isSelected ? 1.5 : 1
                            )
                    )
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(NSColor.windowBackgroundColor).opacity(0.92))
            )
            .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 2)
            .onAppear {
                syncDrafts()
            }
            .onChange(of: groups.map { "\($0.id)|\($0.title)|\($0.itemCount)" }) { _, _ in
                syncDrafts()
            }
            .onChange(of: focusedGroupID) { _, newValue in
                guard let editingGroupID, newValue != editingGroupID else { return }
                if let group = groups.first(where: { $0.id == editingGroupID }) {
                    finishEditing(group)
                } else {
                    self.editingGroupID = nil
                }
            }
        }
    }

    @ViewBuilder
    private func legendGroupRow(_ group: CanvasLegendGroup) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(CanvasStylePalette.color(from: group.colorHex) ?? .secondary)
                .frame(width: 12, height: 12)

            Text(group.kindTitle(language: localizationManager.currentLanguage))
                .font(.system(size: 10 * textScale, weight: .semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background((CanvasStylePalette.color(from: group.colorHex) ?? .secondary).opacity(0.12))
                .clipShape(Capsule())

            editorField(for: group)

            Text("\(group.itemCount)")
                .font(.system(size: 10 * textScale, weight: .medium))
                .foregroundColor(.secondary)
                .frame(minWidth: 18)
        }
    }

    @ViewBuilder
    private func editorField(for group: CanvasLegendGroup) -> some View {
        if editingGroupID == group.id {
            TextField(
                "",
                text: binding(for: group),
                prompt: Text(group.defaultTitle(language: localizationManager.currentLanguage))
            )
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 11 * textScale))
            .frame(width: 132)
            .focused($focusedGroupID, equals: group.id)
            .onAppear {
                DispatchQueue.main.async {
                    focusedGroupID = group.id
                }
            }
            .onSubmit {
                finishEditing(group)
            }
        } else {
            Button {
                beginEditing(group)
            } label: {
                HStack(spacing: 6) {
                    Text(displayTitle(for: group))
                        .font(.system(size: 11 * textScale, weight: group.title.isEmpty ? .regular : .medium))
                        .foregroundColor(group.title.isEmpty ? .secondary : .primary)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    Image(systemName: "pencil")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary.opacity(0.8))
                }
                .padding(.horizontal, 9)
                .frame(width: 132, height: 28, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.black.opacity(0.035))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.black.opacity(0.06), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .help(editTitle)
        }
    }

    private func binding(for group: CanvasLegendGroup) -> Binding<String> {
        Binding(
            get: { titleDrafts[group.id] ?? group.title },
            set: { newValue in
                titleDrafts[group.id] = newValue
            }
        )
    }

    private func syncDrafts() {
        var nextDrafts = titleDrafts
        let validIDs = Set(groups.map(\.id))

        for group in groups where nextDrafts[group.id] == nil {
            nextDrafts[group.id] = group.title
        }

        titleDrafts = nextDrafts.reduce(into: [String: String]()) { result, entry in
            guard validIDs.contains(entry.key) else { return }
            if entry.key != editingGroupID,
               let latestGroup = groups.first(where: { $0.id == entry.key }) {
                result[entry.key] = latestGroup.title
                return
            }
            result[entry.key] = entry.value
        }
    }

    private func beginEditing(_ group: CanvasLegendGroup) {
        titleDrafts[group.id] = titleDrafts[group.id] ?? group.title
        editingGroupID = group.id
        focusedGroupID = group.id
    }

    private func finishEditing(_ group: CanvasLegendGroup) {
        commit(group, title: titleDrafts[group.id] ?? group.title)
        focusedGroupID = nil
        editingGroupID = nil
    }

    private func commit(_ group: CanvasLegendGroup, title: String? = nil) {
        appState.updateColorGroupTitle(
            kind: group.kind,
            colorHex: group.colorHex,
            title: title ?? titleDrafts[group.id] ?? group.title
        )
    }

    private func displayTitle(for group: CanvasLegendGroup) -> String {
        let title = titleDrafts[group.id] ?? group.title
        return title.isEmpty ? group.defaultTitle(language: localizationManager.currentLanguage) : title
    }

    private var legendTitle: String {
        switch localizationManager.currentLanguage {
        case .english:
            return "Color Groups"
        case .traditionalChinese:
            return "顏色分組"
        case .simplifiedChinese:
            return "颜色分组"
        }
    }

    private var editTitle: String {
        switch localizationManager.currentLanguage {
        case .english:
            return "Edit group title"
        case .traditionalChinese:
            return "編輯分組標題"
        case .simplifiedChinese:
            return "编辑分组标题"
        }
    }

}

private struct CanvasLegendGroup: Identifiable, Hashable {
    let kind: CanvasGroupKind
    let colorHex: String
    let title: String
    let itemCount: Int
    let isSelected: Bool

    var id: String {
        CanvasColorGroup(kind: kind, colorHex: colorHex, title: title).id
    }

    func kindTitle(language: AppLanguage) -> String {
        switch (kind, language) {
        case (.node, .english): return "Node"
        case (.edge, .english): return "Route"
        case (.node, .traditionalChinese): return "節點"
        case (.edge, .traditionalChinese): return "連線"
        case (.node, .simplifiedChinese): return "节点"
        case (.edge, .simplifiedChinese): return "连线"
        }
    }

    func defaultTitle(language: AppLanguage) -> String {
        switch (kind, language) {
        case (.node, .english): return "Node group"
        case (.edge, .english): return "Route group"
        case (.node, .traditionalChinese): return "節點組"
        case (.edge, .traditionalChinese): return "連線組"
        case (.node, .simplifiedChinese): return "节点组"
        case (.edge, .simplifiedChinese): return "连线组"
        }
    }
}

private struct BlankCanvasDragMonitor: NSViewRepresentable {
    var isEnabled: () -> Bool
    var shouldIgnoreLocation: (CGPoint) -> Bool
    var onEdgeHit: (_ location: CGPoint) -> Bool
    var isBlankLocation: (CGPoint) -> Bool
    var currentOffset: () -> CGSize
    var onBlankClick: () -> Void
    var onDragStart: () -> Void
    var onDragChanged: (_ translation: CGSize, _ startOffset: CGSize) -> Void
    var onDragEnded: (_ didDrag: Bool, _ location: CGPoint) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            isEnabled: isEnabled,
            shouldIgnoreLocation: shouldIgnoreLocation,
            onEdgeHit: onEdgeHit,
            isBlankLocation: isBlankLocation,
            currentOffset: currentOffset,
            onBlankClick: onBlankClick,
            onDragStart: onDragStart,
            onDragChanged: onDragChanged,
            onDragEnded: onDragEnded
        )
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.isEnabled = isEnabled
        context.coordinator.shouldIgnoreLocation = shouldIgnoreLocation
        context.coordinator.onEdgeHit = onEdgeHit
        context.coordinator.isBlankLocation = isBlankLocation
        context.coordinator.currentOffset = currentOffset
        context.coordinator.onBlankClick = onBlankClick
        context.coordinator.onDragStart = onDragStart
        context.coordinator.onDragChanged = onDragChanged
        context.coordinator.onDragEnded = onDragEnded
        context.coordinator.attach(to: nsView)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator {
        var isEnabled: () -> Bool
        var shouldIgnoreLocation: (CGPoint) -> Bool
        var onEdgeHit: (_ location: CGPoint) -> Bool
        var isBlankLocation: (CGPoint) -> Bool
        var currentOffset: () -> CGSize
        var onBlankClick: () -> Void
        var onDragStart: () -> Void
        var onDragChanged: (_ translation: CGSize, _ startOffset: CGSize) -> Void
        var onDragEnded: (_ didDrag: Bool, _ location: CGPoint) -> Void

        private weak var view: NSView?
        private var monitor: Any?
        private var tracking = false
        private var dragging = false
        private var startLocation: CGPoint = .zero
        private var startOffset: CGSize = .zero
        private let dragThreshold: CGFloat = 2

        init(
            isEnabled: @escaping () -> Bool,
            shouldIgnoreLocation: @escaping (CGPoint) -> Bool,
            onEdgeHit: @escaping (_ location: CGPoint) -> Bool,
            isBlankLocation: @escaping (CGPoint) -> Bool,
            currentOffset: @escaping () -> CGSize,
            onBlankClick: @escaping () -> Void,
            onDragStart: @escaping () -> Void,
            onDragChanged: @escaping (_ translation: CGSize, _ startOffset: CGSize) -> Void,
            onDragEnded: @escaping (_ didDrag: Bool, _ location: CGPoint) -> Void
        ) {
            self.isEnabled = isEnabled
            self.shouldIgnoreLocation = shouldIgnoreLocation
            self.onEdgeHit = onEdgeHit
            self.isBlankLocation = isBlankLocation
            self.currentOffset = currentOffset
            self.onBlankClick = onBlankClick
            self.onDragStart = onDragStart
            self.onDragChanged = onDragChanged
            self.onDragEnded = onDragEnded
        }

        func attach(to view: NSView) {
            self.view = view
            guard monitor == nil else { return }

            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
                guard let self, let view = self.view, view.window != nil else { return event }
                guard self.isEnabled() else { return event }

                let converted = view.convert(event.locationInWindow, from: nil)
                let location = CGPoint(x: converted.x, y: view.bounds.height - converted.y)
                guard view.bounds.contains(location) else { return event }
                if self.shouldIgnoreLocation(location) {
                    return event
                }

                switch event.type {
                case .leftMouseDown:
                    if self.onEdgeHit(location) {
                        return nil
                    }
                    guard self.isBlankLocation(location) else { return event }
                    self.tracking = true
                    self.dragging = false
                    self.startLocation = location
                    self.startOffset = self.currentOffset()
                    NSCursor.openHand.set()
                    return nil

                case .leftMouseDragged:
                    guard self.tracking else { return event }
                    let translation = CGSize(
                        width: location.x - self.startLocation.x,
                        height: location.y - self.startLocation.y
                    )
                    let distance = hypot(translation.width, translation.height)
                    if !self.dragging {
                        guard distance >= self.dragThreshold else { return nil }
                        self.dragging = true
                        self.onDragStart()
                    }
                    self.onDragChanged(translation, self.startOffset)
                    return nil

                case .leftMouseUp:
                    guard self.tracking else { return event }
                    let didDrag = self.dragging
                    self.tracking = false
                    self.dragging = false
                    if didDrag {
                        self.onDragEnded(true, location)
                    } else {
                        self.onBlankClick()
                        self.onDragEnded(false, location)
                    }
                    NSCursor.arrow.set()
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
            tracking = false
            dragging = false
        }
    }
}

private struct RightMouseDragMonitor: NSViewRepresentable {
    var shouldIgnoreLocation: (CGPoint) -> Bool
    var onStart: (CGPoint) -> Void
    var onDrag: (CGPoint) -> Void
    var onEnd: (CGPoint) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            shouldIgnoreLocation: shouldIgnoreLocation,
            onStart: onStart,
            onDrag: onDrag,
            onEnd: onEnd
        )
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.shouldIgnoreLocation = shouldIgnoreLocation
        context.coordinator.onStart = onStart
        context.coordinator.onDrag = onDrag
        context.coordinator.onEnd = onEnd
        context.coordinator.attach(to: nsView)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator {
        var shouldIgnoreLocation: (CGPoint) -> Bool
        var onStart: (CGPoint) -> Void
        var onDrag: (CGPoint) -> Void
        var onEnd: (CGPoint) -> Void

        private weak var view: NSView?
        private var monitor: Any?
        private var tracking = false

        init(
            shouldIgnoreLocation: @escaping (CGPoint) -> Bool,
            onStart: @escaping (CGPoint) -> Void,
            onDrag: @escaping (CGPoint) -> Void,
            onEnd: @escaping (CGPoint) -> Void
        ) {
            self.shouldIgnoreLocation = shouldIgnoreLocation
            self.onStart = onStart
            self.onDrag = onDrag
            self.onEnd = onEnd
        }

        func attach(to view: NSView) {
            self.view = view
            guard monitor == nil else { return }

            monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .rightMouseDragged, .rightMouseUp]) { [weak self] event in
                guard let self, let view = self.view, view.window != nil else { return event }
                let converted = view.convert(event.locationInWindow, from: nil)
                let location = CGPoint(x: converted.x, y: view.bounds.height - converted.y)
                let inside = view.bounds.contains(location)

                switch event.type {
                case .rightMouseDown:
                    guard inside else { return event }
                    guard !self.shouldIgnoreLocation(location) else { return event }
                    tracking = true
                    onStart(location)
                    return nil
                case .rightMouseDragged:
                    guard tracking else { return event }
                    onDrag(location)
                    return nil
                case .rightMouseUp:
                    guard tracking else { return event }
                    tracking = false
                    onEnd(location)
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
            tracking = false
        }
    }
}

private struct BatchCanvasQuickBar: View {
    @ObservedObject private var localizationManager = LocalizationManager.shared

    let selectionCount: Int
    let sourceCount: Int
    let targetCount: Int
    var onAssignSources: (() -> Void)?
    var onAssignTargets: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label(batchTitle, systemImage: "square.stack.3d.up.fill")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Text(summaryText)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 8) {
                Button(sourceButtonTitle) {
                    onAssignSources?()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(selectionCount == 0)

                Button(targetButtonTitle) {
                    onAssignTargets?()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(selectionCount == 0)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(NSColor.windowBackgroundColor).opacity(0.94))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 2)
    }

    private var batchTitle: String {
        switch localizationManager.currentLanguage {
        case .english: return "Batch Connect"
        case .traditionalChinese: return "批量連線"
        case .simplifiedChinese: return "批量连接"
        }
    }

    private var sourceButtonTitle: String {
        switch localizationManager.currentLanguage {
        case .english: return "Set Sources"
        case .traditionalChinese: return "設為來源"
        case .simplifiedChinese: return "设为来源"
        }
    }

    private var targetButtonTitle: String {
        switch localizationManager.currentLanguage {
        case .english: return "Set Targets"
        case .traditionalChinese: return "設為目標"
        case .simplifiedChinese: return "设为目标"
        }
    }

    private var summaryText: String {
        switch localizationManager.currentLanguage {
        case .english:
            return "Selected \(selectionCount) / From \(sourceCount) / To \(targetCount)"
        case .traditionalChinese:
            return "已選 \(selectionCount) / 來源 \(sourceCount) / 目標 \(targetCount)"
        case .simplifiedChinese:
            return "已选 \(selectionCount) / 来源 \(sourceCount) / 目标 \(targetCount)"
        }
    }
}

private struct CanvasOverlayFramePreferenceKey: PreferenceKey {
    static let coordinateSpaceName = "CanvasContentViewCoordinateSpace"
    static var defaultValue: CGRect = .null

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}
