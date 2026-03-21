//
//  NodesView.swift
//  Multi-Agent-Flow
//

import SwiftUI

struct NodesView: View {
    @EnvironmentObject var appState: AppState
    let currentWorkflow: Workflow?
    @Binding var selectedNodeID: UUID?
    @Binding var selectedNodeIDs: Set<UUID>
    @Binding var selectedEdgeID: UUID?
    @Binding var selectedBoundaryIDs: Set<UUID>
    @Binding var connectingFromNode: WorkflowNode?
    @Binding var tempConnectionEnd: CGPoint?
    @Binding var transientNodePositions: [UUID: CGPoint]
    let scale: CGFloat
    let offset: CGSize
    let geometry: GeometryProxy
    var isConnectMode: Bool = false
    var connectFromAgentID: UUID?
    var batchSourceNodeIDs: Set<UUID> = []
    var batchTargetNodeIDs: Set<UUID> = []
    var onNodeClick: ((WorkflowNode) -> Void)?
    var onNodeSelected: ((WorkflowNode) -> Void)?
    var onNodeDragEnded: (([UUID: CGPoint]) -> Void)?

    @State private var draggingNode: WorkflowNode?
    @State private var dragOriginPositions: [UUID: CGPoint] = [:]

    var body: some View {
        let workflow = currentWorkflow
        let focusedNodeIDs = activeFocusedNodeIDs()
        let nodeConnectionCounts = workflow?.connectionCountsByNodeID() ?? [:]
        let connectedNodeIDs = allConnectedNodeIDs(in: workflow)
        let relatedNodeIDs = relatedNodeIDs(for: focusedNodeIDs, in: workflow)
        let nodeIDsInBoundaries = nodeIDsInBoundaries(in: workflow)

        ForEach(workflow?.nodes ?? []) { node in
            let counts = nodeConnectionCounts[node.id] ?? .zero
            NodeView(
                node: node,
                isSelected: selectedNodeIDs.contains(node.id) || node.id == selectedNodeID,
                agent: appState.getAgent(for: node),
                incomingConnections: counts.incoming,
                outgoingConnections: counts.outgoing,
                isInBoundary: nodeIDsInBoundaries.contains(node.id),
                isConnectingMode: isConnectMode,
                isConnectSource: connectFromAgentID == node.id,
                isBatchSource: batchSourceNodeIDs.contains(node.id),
                isBatchTarget: batchTargetNodeIDs.contains(node.id),
                hasBatchConflict: batchSourceNodeIDs.contains(node.id) && batchTargetNodeIDs.contains(node.id),
                isRelatedToSelection: relatedNodeIDs.contains(node.id) && !focusedNodeIDs.contains(node.id) && node.type == .agent,
                onTap: { handleSingleTap(node) },
                accentColor: displayColor(for: node, connectedNodeIDs: connectedNodeIDs),
                textScale: appState.canvasDisplaySettings.textScale,
                textColor: .black
            )
            .position(adjustedPosition(node))
            .zIndex(selectedNodeIDs.contains(node.id) || node.id == selectedNodeID ? 100 : (draggingNode?.id == node.id ? 50 : 1))
            .gesture(createNodeGesture(for: node))
        }
    }

    private func adjustedPosition(_ node: WorkflowNode) -> CGPoint {
        let position = transientNodePositions[node.id] ?? node.position
        let centerX = geometry.size.width / 2
        let centerY = geometry.size.height / 2
        return CGPoint(
            x: position.x * scale + offset.width + centerX,
            y: position.y * scale + offset.height + centerY
        )
    }

    private func createNodeGesture(for node: WorkflowNode) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                guard connectingFromNode == nil else { return }
                prepareSelectionForDragging(node)
                updateNodePositions(for: node, translation: value.translation)
                draggingNode = node
            }
            .onEnded { _ in
                let finalPositions = transientNodePositions
                if !finalPositions.isEmpty {
                    onNodeDragEnded?(finalPositions)
                }
                transientNodePositions.removeAll()
                draggingNode = nil
                dragOriginPositions.removeAll()
            }
    }

    private func prepareSelectionForDragging(_ node: WorkflowNode) {
        if !selectedNodeIDs.contains(node.id) {
            selectedNodeIDs = [node.id]
            selectedNodeID = node.id
        } else if selectedNodeID == nil, selectedNodeIDs.count == 1 {
            selectedNodeID = node.id
        }

        selectedEdgeID = nil
        selectedBoundaryIDs.removeAll()
    }

    private func activeFocusedNodeIDs() -> Set<UUID> {
        if !selectedNodeIDs.isEmpty {
            return selectedNodeIDs
        }
        if let selectedNodeID {
            return [selectedNodeID]
        }
        return []
    }

    private func relatedNodeIDs(for focusedNodeIDs: Set<UUID>, in workflow: Workflow?) -> Set<UUID> {
        guard let workflow, !focusedNodeIDs.isEmpty else { return [] }

        var result: Set<UUID> = []
        for edge in workflow.edges {
            if focusedNodeIDs.contains(edge.fromNodeID) {
                result.insert(edge.toNodeID)
            }
            if focusedNodeIDs.contains(edge.toNodeID) {
                result.insert(edge.fromNodeID)
            }
        }
        return result
    }

    private func allConnectedNodeIDs(in workflow: Workflow?) -> Set<UUID> {
        guard let workflow else { return [] }

        var nodeIDs: Set<UUID> = []
        nodeIDs.reserveCapacity(workflow.edges.count * 2)
        for edge in workflow.edges {
            nodeIDs.insert(edge.fromNodeID)
            nodeIDs.insert(edge.toNodeID)
        }
        return nodeIDs
    }

    private func updateNodePositions(for node: WorkflowNode, translation: CGSize) {
        guard let workflow = currentWorkflow else { return }
        let selection = selectedNodeIDs.contains(node.id) ? selectedNodeIDs : [node.id]

        if dragOriginPositions.isEmpty {
            dragOriginPositions = Dictionary(uniqueKeysWithValues: workflow.nodes
                .filter { selection.contains($0.id) }
                .map { ($0.id, $0.position) })
        }

        let dx = translation.width / scale
        let dy = translation.height / scale

        var updatedPositions = transientNodePositions
        for targetNode in workflow.nodes where selection.contains(targetNode.id) {
            guard let origin = dragOriginPositions[targetNode.id] else { continue }
            let tentative = CGPoint(x: origin.x + dx, y: origin.y + dy)
            updatedPositions[targetNode.id] = appState.snapPointToGrid(tentative)
        }
        transientNodePositions = updatedPositions
    }

    private func nodeIDsInBoundaries(in workflow: Workflow?) -> Set<UUID> {
        guard let workflow else { return [] }

        var nodeIDs: Set<UUID> = []
        for boundary in workflow.boundaries {
            nodeIDs.formUnion(boundary.memberNodeIDs)
            for node in workflow.nodes where boundary.rect.contains(node.position) {
                nodeIDs.insert(node.id)
            }
        }
        return nodeIDs
    }

    private func handleSingleTap(_ node: WorkflowNode) {
        if NSEvent.modifierFlags.contains(.command) {
            if selectedNodeIDs.contains(node.id) {
                selectedNodeIDs.remove(node.id)
            } else {
                selectedNodeIDs.insert(node.id)
            }
            selectedNodeID = selectedNodeIDs.count == 1 ? selectedNodeIDs.first : nil
        } else {
            selectedNodeIDs = [node.id]
            selectedNodeID = node.id
        }
        selectedEdgeID = nil
        selectedBoundaryIDs.removeAll()

        if isConnectMode, let onNodeClick {
            onNodeClick(node)
        } else {
            connectingFromNode = nil
            tempConnectionEnd = nil
            onNodeSelected?(node)
        }
    }

    private func displayColor(for node: WorkflowNode, connectedNodeIDs: Set<UUID>) -> Color? {
        guard node.type == .agent else { return nil }

        if let customColor = CanvasStylePalette.color(from: node.displayColorHex) {
            return customColor
        }

        if let agent = appState.getAgent(for: node),
           let colorHex = agent.colorHex,
           let customColor = CanvasStylePalette.color(from: colorHex) {
            return customColor
        }

        if !connectedNodeIDs.contains(node.id) {
            return .red
        }
        return nil
    }
}
