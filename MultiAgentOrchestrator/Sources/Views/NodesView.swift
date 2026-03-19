//
//  NodesView.swift
//  MultiAgentOrchestrator
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
    let scale: CGFloat
    let offset: CGSize
    let geometry: GeometryProxy
    var isConnectMode: Bool = false
    var connectFromAgentID: UUID?
    var onNodeClick: ((WorkflowNode) -> Void)?
    var onNodeSelected: ((WorkflowNode) -> Void)?

    @State private var draggingNode: WorkflowNode?
    @State private var dragOriginPositions: [UUID: CGPoint] = [:]

    var body: some View {
        ForEach(currentWorkflow?.nodes ?? []) { node in
            NodeView(
                node: node,
                isSelected: selectedNodeIDs.contains(node.id) || node.id == selectedNodeID,
                agent: appState.getAgent(for: node),
                isConnectingMode: isConnectMode,
                isConnectSource: connectFromAgentID == node.id,
                onTap: { handleSingleTap(node) },
                accentColor: displayColor(for: node),
                textScale: appState.canvasDisplaySettings.textScale,
                textColor: appState.canvasDisplaySettings.textColor.color
            )
            .position(adjustedPosition(node.position))
            .zIndex(selectedNodeIDs.contains(node.id) || node.id == selectedNodeID ? 100 : (draggingNode?.id == node.id ? 50 : 1))
            .gesture(createNodeGesture(for: node))
        }
    }

    private func adjustedPosition(_ position: CGPoint) -> CGPoint {
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

        appState.updateMainWorkflow { workflow in
            for index in workflow.nodes.indices where selection.contains(workflow.nodes[index].id) {
                guard let origin = dragOriginPositions[workflow.nodes[index].id] else { continue }
                let tentative = CGPoint(x: origin.x + dx, y: origin.y + dy)
                workflow.nodes[index].position = appState.snapPointToGrid(tentative)
            }
        }
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

    private func displayColor(for node: WorkflowNode) -> Color? {
        guard node.type == .agent else { return nil }

        if let agent = appState.getAgent(for: node),
           let colorHex = agent.colorHex,
           let customColor = color(from: colorHex) {
            return customColor
        }

        let connectedNodeIDs = Set((currentWorkflow?.edges ?? []).flatMap { [$0.fromNodeID, $0.toNodeID] })
        if !connectedNodeIDs.contains(node.id) {
            return .red
        }
        return nil
    }

    private func color(from hex: String) -> Color? {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count == 6 || cleaned.count == 8 else { return nil }

        var value: UInt64 = 0
        guard Scanner(string: cleaned).scanHexInt64(&value) else { return nil }

        let r, g, b, a: UInt64
        if cleaned.count == 8 {
            r = (value >> 24) & 0xff
            g = (value >> 16) & 0xff
            b = (value >> 8) & 0xff
            a = value & 0xff
        } else {
            r = (value >> 16) & 0xff
            g = (value >> 8) & 0xff
            b = value & 0xff
            a = 0xff
        }

        return Color(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
