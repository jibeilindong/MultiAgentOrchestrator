//
//  ConnectionLinesView.swift
//  MultiAgentOrchestrator
//

import SwiftUI

struct ConnectionLinesView: View {
    let currentWorkflow: Workflow?
    @Binding var scale: CGFloat
    let offset: CGSize
    let geometry: GeometryProxy?
    @Binding var selectedEdgeID: UUID?
    var onEdgeSelected: ((WorkflowEdge) -> Void)?

    private let nodeWidth: CGFloat = 80
    private let nodeHeight: CGFloat = 60

    init(
        currentWorkflow: Workflow?,
        scale: Binding<CGFloat>,
        offset: CGSize,
        geometry: GeometryProxy? = nil,
        selectedEdgeID: Binding<UUID?> = .constant(nil),
        onEdgeSelected: ((WorkflowEdge) -> Void)? = nil
    ) {
        self.currentWorkflow = currentWorkflow
        self._scale = scale
        self.offset = offset
        self.geometry = geometry
        self._selectedEdgeID = selectedEdgeID
        self.onEdgeSelected = onEdgeSelected
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(currentWorkflow?.edges ?? []) { edge in
                    if let fromNode = currentWorkflow?.nodes.first(where: { $0.id == edge.fromNodeID }),
                       let toNode = currentWorkflow?.nodes.first(where: { $0.id == edge.toNodeID }) {
                        let fromPos = getNodeCenter(fromNode.position, geometry: geo)
                        let toPos = getNodeCenter(toNode.position, geometry: geo)
                        let startPoint = calculateEdgePoint(from: fromPos, to: toPos)
                        let endPoint = calculateEdgePoint(from: toPos, to: fromPos)
                        let isSelected = selectedEdgeID == edge.id

                        ConnectionLineShape(from: startPoint, to: endPoint)
                            .stroke(
                                isSelected ? Color.accentColor : (edge.requiresApproval ? Color.orange.opacity(0.7) : Color.blue.opacity(0.6)),
                                style: StrokeStyle(lineWidth: isSelected ? 3 : 2, dash: edge.requiresApproval ? [8, 4] : [])
                            )

                        ConnectionLineShape(from: startPoint, to: endPoint)
                            .stroke(Color.clear, lineWidth: 14)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedEdgeID = edge.id
                                onEdgeSelected?(edge)
                            }

                        ArrowShape(from: startPoint, to: endPoint)
                            .stroke(
                                isSelected ? Color.accentColor : (edge.requiresApproval ? Color.orange.opacity(0.85) : Color.blue.opacity(0.8)),
                                style: StrokeStyle(lineWidth: isSelected ? 3 : 2, lineCap: .round)
                            )

                        let displayText = edgeDisplayText(edge)
                        if !displayText.isEmpty {
                            EdgeLabelView(text: displayText, requiresApproval: edge.requiresApproval)
                                .position(midPoint(from: startPoint, to: endPoint))
                        }
                    }
                }
            }
        }
    }

    private func getNodeCenter(_ position: CGPoint, geometry: GeometryProxy) -> CGPoint {
        let centerX = geometry.size.width / 2
        let centerY = geometry.size.height / 2
        return CGPoint(
            x: position.x * scale + offset.width + centerX,
            y: position.y * scale + offset.height + centerY
        )
    }

    private func calculateEdgePoint(from: CGPoint, to: CGPoint) -> CGPoint {
        let dx = to.x - from.x
        let dy = to.y - from.y
        guard abs(dx) > 0.001 || abs(dy) > 0.001 else {
            return from
        }

        let angle = atan2(dy, dx)
        let diagonal = sqrt(nodeWidth * nodeWidth + nodeHeight * nodeHeight)
        let buffer: CGFloat = diagonal / 2 + 15
        let t = buffer * scale
        return CGPoint(x: from.x + t * cos(angle), y: from.y + t * sin(angle))
    }

    private func midPoint(from: CGPoint, to: CGPoint) -> CGPoint {
        CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
    }

    private func edgeDisplayText(_ edge: WorkflowEdge) -> String {
        let label = edge.label.trimmingCharacters(in: .whitespacesAndNewlines)
        let condition = edge.conditionExpression.trimmingCharacters(in: .whitespacesAndNewlines)

        if !label.isEmpty && !condition.isEmpty {
            return "\(label): \(condition)"
        }
        if !label.isEmpty { return label }
        if !condition.isEmpty { return condition }
        return edge.requiresApproval ? "Requires approval" : ""
    }
}

struct EdgeLabelView: View {
    let text: String
    let requiresApproval: Bool

    var body: some View {
        HStack(spacing: 4) {
            if requiresApproval {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 8))
            }
            Text(text)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(requiresApproval ? Color.orange.opacity(0.95) : Color(NSColor.windowBackgroundColor).opacity(0.95))
        .foregroundColor(requiresApproval ? .white : .primary)
        .overlay(
            Capsule()
                .stroke(requiresApproval ? Color.orange : Color.blue.opacity(0.35), lineWidth: 1)
        )
        .clipShape(Capsule())
        .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 1)
    }
}

struct ConnectionLineShape: Shape {
    let from: CGPoint
    let to: CGPoint

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: from)
        path.addLine(to: to)
        return path
    }
}

struct ArrowShape: Shape {
    let from: CGPoint
    let to: CGPoint

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let dx = to.x - from.x
        let dy = to.y - from.y
        guard abs(dx) > 0.001 || abs(dy) > 0.001 else {
            return path
        }

        let angle = atan2(dy, dx)
        let arrowLength: CGFloat = 12
        let tip = to
        let leftPoint = CGPoint(
            x: tip.x - arrowLength * cos(angle - .pi / 6),
            y: tip.y - arrowLength * sin(angle - .pi / 6)
        )
        let rightPoint = CGPoint(
            x: tip.x - arrowLength * cos(angle + .pi / 6),
            y: tip.y - arrowLength * sin(angle + .pi / 6)
        )

        path.move(to: leftPoint)
        path.addLine(to: tip)
        path.addLine(to: rightPoint)
        return path
    }
}
