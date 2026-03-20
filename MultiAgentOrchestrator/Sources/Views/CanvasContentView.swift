//
//  CanvasContentView.swift
//  MultiAgentOrchestrator
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
    var onNodeClick: ((WorkflowNode) -> Void)?
    var onNodeSelected: ((WorkflowNode) -> Void)?
    var onNodeSecondarySelected: ((WorkflowNode) -> Void)?
    var onEdgeSelected: ((WorkflowEdge) -> Void)?
    var onEdgeSecondarySelected: ((WorkflowEdge) -> Void)?

    @State private var isDraggingOverCanvas: Bool = false
    @State private var rightMouseLassoStart: CGPoint?
    @State private var boundaryDragSnapshots: [UUID: BoundaryDragSnapshot] = [:]
    @State private var draggingBoundaryID: UUID?

    private var currentWorkflow: Workflow? {
        appState.currentProject?.workflows.first
    }

    var body: some View {
        GeometryReader { geometry in
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
                    currentWorkflow: currentWorkflow,
                    scale: $scale,
                    offset: offset,
                    lineColor: appState.canvasDisplaySettings.lineColor.color,
                    lineWidth: appState.canvasDisplaySettings.lineWidth,
                    textScale: appState.canvasDisplaySettings.textScale,
                    textColor: appState.canvasDisplaySettings.textColor.color,
                    selectedEdgeID: $selectedEdgeID,
                    onEdgeSelected: { edge in
                        suppressCanvasTapClear = true
                        selectedNodeID = nil
                        selectedNodeIDs.removeAll()
                        selectedBoundaryIDs.removeAll()
                        onEdgeSelected?(edge)
                    },
                    onEdgeSecondarySelected: { edge in
                        suppressCanvasTapClear = true
                        selectedNodeID = nil
                        selectedNodeIDs.removeAll()
                        selectedBoundaryIDs.removeAll()
                        onEdgeSecondarySelected?(edge)
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
                        boundaryDragSnapshots.removeValue(forKey: boundaryID)
                        if draggingBoundaryID == boundaryID {
                            draggingBoundaryID = nil
                        }
                    }
                )

                if let fromNode = connectingFromNode,
                   let endPoint = tempConnectionEnd {
                    ConnectionLineShape(
                        from: adjustedPosition(fromNode.position, geometry: geometry),
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
                    scale: scale,
                    offset: offset,
                    geometry: geometry,
                    isConnectMode: isConnectMode,
                    connectFromAgentID: connectFromAgentID,
                    onNodeClick: onNodeClick,
                    onNodeSelected: onNodeSelected
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
            .background(
                BlankCanvasDragMonitor(
                    isEnabled: { !(isLassoMode || isTransientLassoMode) },
                    onEdgeHit: { location in
                        guard let edge = edge(at: location, geometry: geometry) else { return false }
                        suppressCanvasTapClear = true
                        selectedNodeID = nil
                        selectedNodeIDs.removeAll()
                        selectedBoundaryIDs.removeAll()
                        selectedEdgeID = edge.id
                        onEdgeSelected?(edge)
                        return true
                    },
                    isBlankLocation: { location in
                        isBlankCanvasLocation(location, geometry: geometry)
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
                            if let edge = edge(at: location, geometry: geometry) {
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

    private func handleDrop(providers: [NSItemProvider], location: CGPoint, geometry: GeometryProxy) -> Bool {
        for provider in providers {
            provider.loadObject(ofClass: NSString.self) { item, _ in
                if let agentName = item as? String {
                    DispatchQueue.main.async {
                        if agentName.hasPrefix("nodeType:") {
                            let rawType = String(agentName.dropFirst("nodeType:".count))
                            let nodeType = WorkflowNode.NodeType(rawValue: rawType) ?? WorkflowNode.NodeType.decoded(from: rawType)
                            addWorkflowNodeToCanvas(type: nodeType, at: location, geometry: geometry)
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
                    boundaryFrame(for: boundary, geometry: geometry).contains(adjustedPosition(node.position, geometry: geometry)) ? node.id : nil
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

        appState.updateMainWorkflow { workflow in
            guard let boundaryIndex = workflow.boundaries.firstIndex(where: { $0.id == boundaryID }) else { return }

            workflow.boundaries[boundaryIndex].rect = appState.snapRectToGrid(
                snapshot.rect.offsetBy(dx: dx, dy: dy)
            )
            workflow.boundaries[boundaryIndex].updatedAt = Date()
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
        let origin = adjustedPosition(CGPoint(x: boundary.rect.minX, y: boundary.rect.minY), geometry: geometry)
        let opposite = adjustedPosition(CGPoint(x: boundary.rect.maxX, y: boundary.rect.maxY), geometry: geometry)
        return CGRect(
            x: min(origin.x, opposite.x),
            y: min(origin.y, opposite.y),
            width: abs(opposite.x - origin.x),
            height: abs(opposite.y - origin.y)
        )
    }

    private func nodeFrame(for node: WorkflowNode, geometry: GeometryProxy) -> CGRect {
        let center = adjustedPosition(node.position, geometry: geometry)
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
            let outgoing = currentWorkflow?.edges.reduce(into: 0) { partial, edge in
                if edge.isOutgoing(from: node.id) { partial += 1 }
            } ?? 0
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

    private func edge(at location: CGPoint, geometry: GeometryProxy) -> WorkflowEdge? {
        guard let workflow = currentWorkflow else { return nil }
        let tolerance = max(10, appState.canvasDisplaySettings.lineWidth + 6)
        return routedEdgeLayouts(in: geometry, workflow: workflow)
            .compactMap { layout -> (WorkflowEdge, CGFloat)? in
                guard let distance = layout.distance(to: location, tolerance: tolerance) else { return nil }
                return (layout.edge, distance)
            }
            .min(by: { $0.1 < $1.1 })?
            .0
    }

    private func isBlankCanvasLocation(_ location: CGPoint, geometry: GeometryProxy) -> Bool {
        guard node(at: location, geometry: geometry) == nil else { return false }
        guard edge(at: location, geometry: geometry) == nil else { return false }
        guard boundary(at: location, geometry: geometry) == nil else { return false }
        return true
    }

    private func isPoint(_ point: CGPoint, near polyline: [CGPoint], tolerance: CGFloat) -> Bool {
        guard polyline.count >= 2 else { return false }
        for segment in zip(polyline, polyline.dropFirst()) {
            if distance(point, to: segment.0, and: segment.1) <= tolerance {
                return true
            }
        }
        return false
    }

    private func distance(_ point: CGPoint, to a: CGPoint, and b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        if abs(dx) < 0.001 && abs(dy) < 0.001 {
            return hypot(point.x - a.x, point.y - a.y)
        }

        let t = max(0, min(1, ((point.x - a.x) * dx + (point.y - a.y) * dy) / (dx * dx + dy * dy)))
        let projection = CGPoint(x: a.x + t * dx, y: a.y + t * dy)
        return hypot(point.x - projection.x, point.y - projection.y)
    }

    private func routedEdgeLayouts(in geometry: GeometryProxy, workflow: Workflow) -> [RoutedEdgeHitLayout] {
        let nodesByID = Dictionary(uniqueKeysWithValues: workflow.nodes.map { ($0.id, $0) })
        let candidates = workflow.edges.compactMap { edge -> RoutedEdgeHitCandidate? in
            guard let fromNode = nodesByID[edge.fromNodeID],
                  let toNode = nodesByID[edge.toNodeID] else {
                return nil
            }

            let fromFrame = nodeFrame(for: fromNode, geometry: geometry)
            let toFrame = nodeFrame(for: toNode, geometry: geometry)
            let targetSide = WorkflowEdgeRoutePlanner.preferredIncomingSide(
                for: toFrame,
                toward: CGPoint(x: fromFrame.midX, y: fromFrame.midY)
            )

            return RoutedEdgeHitCandidate(
                edge: edge,
                fromFrame: fromFrame,
                toFrame: toFrame,
                targetSide: targetSide
            )
        }

        let grouped = Dictionary(grouping: candidates) { $0.bundleKey }
        var layouts: [RoutedEdgeHitLayout] = []

        for bundle in grouped.values {
            let sortedBundle = bundle.sorted { lhs, rhs in
                let lhsAngle = atan2(lhs.fromFrame.midY - lhs.toFrame.midY, lhs.fromFrame.midX - lhs.toFrame.midX)
                let rhsAngle = atan2(rhs.fromFrame.midY - rhs.toFrame.midY, rhs.fromFrame.midX - rhs.toFrame.midX)
                return lhsAngle < rhsAngle
            }
            let laneOffsets = laneOffsets(for: sortedBundle.count)

            for (index, candidate) in sortedBundle.enumerated() {
                let obstacles = workflow.nodes.compactMap { node -> CGRect? in
                    guard node.id != candidate.edge.fromNodeID,
                          node.id != candidate.edge.toNodeID else { return nil }
                    return nodeFrame(for: node, geometry: geometry)
                }

                let points = WorkflowEdgeRoutePlanner.route(
                    from: candidate.fromFrame,
                    to: candidate.toFrame,
                    avoiding: obstacles,
                    preferredAxis: candidate.preferredAxis,
                    laneOffset: laneOffsets[index]
                )

                layouts.append(RoutedEdgeHitLayout(edge: candidate.edge, points: points))
            }
        }

        return layouts
    }

    private func laneOffsets(for count: Int) -> [CGFloat] {
        guard count > 1 else { return [0] }
        let spacing: CGFloat = 14
        let center = CGFloat(count - 1) / 2
        return (0..<count).map { index in
            (CGFloat(index) - center) * spacing
        }
    }
}

private struct BoundaryDragSnapshot {
    let rect: CGRect
}

private struct RoutedEdgeHitCandidate {
    let edge: WorkflowEdge
    let fromFrame: CGRect
    let toFrame: CGRect
    let targetSide: EdgeAnchorSide

    var bundleKey: RoutedEdgeBundleKey {
        RoutedEdgeBundleKey(
            targetNodeID: edge.toNodeID,
            incomingSide: targetSide,
            requiresApproval: edge.requiresApproval
        )
    }

    var preferredAxis: EdgeRouteAxis {
        let dx = toFrame.midX - fromFrame.midX
        let dy = toFrame.midY - fromFrame.midY
        return abs(dx) >= abs(dy) ? .horizontal : .vertical
    }
}

private struct RoutedEdgeBundleKey: Hashable {
    let targetNodeID: UUID
    let incomingSide: EdgeAnchorSide
    let requiresApproval: Bool
}

private struct RoutedEdgeHitLayout {
    let edge: WorkflowEdge
    let points: [CGPoint]

    func distance(to location: CGPoint, tolerance: CGFloat) -> CGFloat? {
        guard points.count >= 2 else { return nil }
        var best: CGFloat?
        for segment in zip(points, points.dropFirst()) {
            let segmentDistance = distance(from: location, to: segment.0, and: segment.1)
            guard segmentDistance <= tolerance else { continue }
            if best == nil || segmentDistance < best! {
                best = segmentDistance
            }
        }
        return best
    }

    private func distance(from point: CGPoint, to a: CGPoint, and b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        if abs(dx) < 0.001 && abs(dy) < 0.001 {
            return hypot(point.x - a.x, point.y - a.y)
        }

        let t = max(0, min(1, ((point.x - a.x) * dx + (point.y - a.y) * dy) / (dx * dx + dy * dy)))
        let projection = CGPoint(x: a.x + t * dx, y: a.y + t * dy)
        return hypot(point.x - projection.x, point.y - projection.y)
    }
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

private struct BlankCanvasDragMonitor: NSViewRepresentable {
    var isEnabled: () -> Bool
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
            onEdgeHit: @escaping (_ location: CGPoint) -> Bool,
            isBlankLocation: @escaping (CGPoint) -> Bool,
            currentOffset: @escaping () -> CGSize,
            onBlankClick: @escaping () -> Void,
            onDragStart: @escaping () -> Void,
            onDragChanged: @escaping (_ translation: CGSize, _ startOffset: CGSize) -> Void,
            onDragEnded: @escaping (_ didDrag: Bool, _ location: CGPoint) -> Void
        ) {
            self.isEnabled = isEnabled
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
    var onStart: (CGPoint) -> Void
    var onDrag: (CGPoint) -> Void
    var onEnd: (CGPoint) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onStart: onStart, onDrag: onDrag, onEnd: onEnd)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onStart = onStart
        context.coordinator.onDrag = onDrag
        context.coordinator.onEnd = onEnd
        context.coordinator.attach(to: nsView)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator {
        var onStart: (CGPoint) -> Void
        var onDrag: (CGPoint) -> Void
        var onEnd: (CGPoint) -> Void

        private weak var view: NSView?
        private var monitor: Any?
        private var tracking = false

        init(onStart: @escaping (CGPoint) -> Void, onDrag: @escaping (CGPoint) -> Void, onEnd: @escaping (CGPoint) -> Void) {
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
