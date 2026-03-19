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
    @Binding var isLassoMode: Bool
    @Binding var lassoRect: CGRect?
    @Binding var connectingFromNode: WorkflowNode?
    @Binding var tempConnectionEnd: CGPoint?
    var isConnectMode: Bool = false
    var connectFromAgentID: UUID?
    var onNodeClick: ((WorkflowNode) -> Void)?
    var onNodeSelected: ((WorkflowNode) -> Void)?
    var onEdgeSelected: ((WorkflowEdge) -> Void)?
    var onSubflowEdit: ((WorkflowNode) -> Void)?

    @State private var isDraggingOverCanvas: Bool = false

    private var currentWorkflow: Workflow? {
        appState.currentProject?.workflows.first
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                GridBackground()
                    .scaleEffect(scale)
                    .offset(offset)
                    .opacity(isDraggingOverCanvas ? 0.6 : 1.0)

                if isDraggingOverCanvas {
                    DropIndicatorView(geometry: geometry)
                }

                WorkflowBoundaryOverlay(
                    groups: explicitBoundaryRects(in: geometry),
                    fallbackGroups: collaborationGroups(in: geometry)
                )

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
                        selectedNodeID = nil
                        selectedNodeIDs.removeAll()
                        onEdgeSelected?(edge)
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
                    connectingFromNode: $connectingFromNode,
                    tempConnectionEnd: $tempConnectionEnd,
                    scale: scale,
                    offset: offset,
                    geometry: geometry,
                    isConnectMode: isConnectMode,
                    connectFromAgentID: connectFromAgentID,
                    onNodeClick: onNodeClick,
                    onNodeSelected: onNodeSelected,
                    onSubflowEdit: onSubflowEdit
                )
                .environmentObject(appState)

                HintViews(geometry: geometry)

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
        let position = CGPoint(
            x: (location.x - centerX - offset.width) / scale,
            y: (location.y - centerY - offset.height) / scale
        )
        appState.addNode(type: type, position: position)
    }

    private func addAgentNodeToCanvas(agentName: String, at location: CGPoint, geometry: GeometryProxy) {
        let centerX = geometry.size.width / 2
        let centerY = geometry.size.height / 2
        let position = CGPoint(
            x: (location.x - centerX - offset.width) / scale,
            y: (location.y - centerY - offset.height) / scale
        )
        appState.addAgentNode(agentName: agentName, position: position)
    }

    private func lassoGesture(in geometry: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                guard isLassoMode else { return }
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
                guard isLassoMode, let lassoRect else { return }
                let selected = Set((currentWorkflow?.nodes ?? []).compactMap { node -> UUID? in
                    nodeFrame(for: node, geometry: geometry).intersects(lassoRect) ? node.id : nil
                })
                selectedNodeIDs = selected
                selectedNodeID = selected.count == 1 ? selected.first : nil
                selectedEdgeID = nil
                self.lassoRect = nil
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
            let origin = adjustedPosition(CGPoint(x: boundary.rect.minX, y: boundary.rect.minY), geometry: geometry)
            let opposite = adjustedPosition(CGPoint(x: boundary.rect.maxX, y: boundary.rect.maxY), geometry: geometry)
            let rect = CGRect(
                x: min(origin.x, opposite.x),
                y: min(origin.y, opposite.y),
                width: abs(opposite.x - origin.x),
                height: abs(opposite.y - origin.y)
            )
            return WorkflowBoundaryDisplayGroup(id: boundary.id, title: boundary.title, rect: rect)
        }
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
}

struct WorkflowBoundaryDisplayGroup: Identifiable {
    let id: UUID
    let title: String
    let rect: CGRect
}

struct WorkflowBoundaryOverlay: View {
    let groups: [WorkflowBoundaryDisplayGroup]
    let fallbackGroups: [CGRect]

    var body: some View {
        ZStack {
            ForEach(groups) { group in
                let rect = group.rect
                Rectangle()
                    .fill(Color.orange.opacity(0.04))
                    .overlay(
                        Rectangle()
                            .stroke(Color.orange.opacity(0.85), style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
                    )
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)

                Text(group.title)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.95))
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
