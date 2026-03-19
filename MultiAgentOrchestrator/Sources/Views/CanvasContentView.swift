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

    @State private var isDraggingOverCanvas: Bool = false
    @State private var rightMouseLassoStart: CGPoint?
    @State private var boundaryDragSnapshots: [UUID: BoundaryDragSnapshot] = [:]

    private var currentWorkflow: Workflow? {
        appState.currentProject?.workflows.first
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
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
                    }
                )

                WorkflowBoundaryOverlay(
                    groups: explicitBoundaryRects(in: geometry),
                    fallbackGroups: collaborationGroups(in: geometry),
                    selectedBoundaryIDs: selectedBoundaryIDs,
                    onBoundaryTap: { boundaryID in
                        guard let workflow = currentWorkflow,
                              let boundary = workflow.boundaries.first(where: { $0.id == boundaryID }) else {
                            return
                        }
                        suppressCanvasTapClear = true
                        selectedBoundaryIDs = [boundaryID]
                        selectedNodeIDs = Set(boundary.memberNodeIDs)
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
            .contentShape(Rectangle())
            .simultaneousGesture(lassoGesture(in: geometry))
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

        let boundaryMemberNodes = Set((workflow?.boundaries ?? [])
            .filter { selectedBoundaries.contains($0.id) }
            .flatMap(\.memberNodeIDs))

        let selected = selectedNodesInRect.union(boundaryMemberNodes)
        selectedBoundaryIDs = selectedBoundaries
        selectedNodeIDs = selected
        selectedNodeID = selected.count == 1 && selectedBoundaries.isEmpty ? selected.first : nil
        selectedEdgeID = nil
    }

    private func handleBoundaryDrag(boundaryID: UUID, translation: CGSize) {
        guard let workflow = currentWorkflow else { return }

        if boundaryDragSnapshots[boundaryID] == nil,
           let boundary = workflow.boundaries.first(where: { $0.id == boundaryID }) {
            let nodePositions = Dictionary(uniqueKeysWithValues: workflow.nodes
                .filter { boundary.memberNodeIDs.contains($0.id) }
                .map { ($0.id, $0.position) })
            boundaryDragSnapshots[boundaryID] = BoundaryDragSnapshot(
                rect: boundary.rect,
                memberNodeIDs: Set(boundary.memberNodeIDs),
                nodePositions: nodePositions
            )
        }

        guard let snapshot = boundaryDragSnapshots[boundaryID] else { return }
        let dx = translation.width / scale
        let dy = translation.height / scale

        suppressCanvasTapClear = true
        selectedBoundaryIDs = [boundaryID]
        selectedNodeIDs = snapshot.memberNodeIDs
        selectedNodeID = nil
        selectedEdgeID = nil

        appState.updateMainWorkflow { workflow in
            guard let boundaryIndex = workflow.boundaries.firstIndex(where: { $0.id == boundaryID }) else { return }

            workflow.boundaries[boundaryIndex].rect = appState.snapRectToGrid(
                snapshot.rect.offsetBy(dx: dx, dy: dy)
            )
            workflow.boundaries[boundaryIndex].updatedAt = Date()

            for nodeIndex in workflow.nodes.indices {
                let nodeID = workflow.nodes[nodeIndex].id
                guard let originalPosition = snapshot.nodePositions[nodeID] else { continue }
                let moved = CGPoint(x: originalPosition.x + dx, y: originalPosition.y + dy)
                workflow.nodes[nodeIndex].position = appState.snapPointToGrid(moved)
            }
        }
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
        let size: CGSize
        switch node.type {
        case .start:
            size = CGSize(width: 100, height: 60)
        case .agent:
            size = CGSize(width: 110, height: 65)
        }
        return CGRect(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    private func node(at location: CGPoint, geometry: GeometryProxy) -> WorkflowNode? {
        guard let workflow = currentWorkflow else { return nil }
        return workflow.nodes.reversed().first { node in
            nodeFrame(for: node, geometry: geometry).contains(location)
        }
    }
}

private struct BoundaryDragSnapshot {
    let rect: CGRect
    let memberNodeIDs: Set<UUID>
    let nodePositions: [UUID: CGPoint]
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
    var onBoundaryTap: ((UUID) -> Void)?
    var onBoundaryDragChanged: ((UUID, CGSize) -> Void)?
    var onBoundaryDragEnded: ((UUID) -> Void)?

    var body: some View {
        ZStack {
            ForEach(groups) { group in
                let rect = group.rect
                let isSelected = selectedBoundaryIDs.contains(group.id)
                Rectangle()
                    .fill((isSelected ? Color.accentColor : Color.orange).opacity(isSelected ? 0.09 : 0.04))
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .allowsHitTesting(false)

                Rectangle()
                    .stroke(
                        isSelected ? Color.accentColor : Color.orange.opacity(0.85),
                        style: StrokeStyle(lineWidth: isSelected ? 2.5 : 2, dash: [8, 4])
                    )
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)

                Rectangle()
                    .stroke(Color.primary.opacity(0.001), lineWidth: 14)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .onTapGesture {
                        onBoundaryTap?(group.id)
                    }
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { value in
                                onBoundaryDragChanged?(group.id, value.translation)
                            }
                            .onEnded { _ in
                                onBoundaryDragEnded?(group.id)
                            }
                    )

                Text(group.title)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background((isSelected ? Color.accentColor : Color.orange).opacity(0.95))
                    .foregroundColor(.white)
                    .position(x: rect.minX + 42, y: rect.minY + 12)
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
                .edgesIgnoringSafeArea(.all)

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
