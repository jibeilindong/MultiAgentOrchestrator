//
//  ConnectionLinesView.swift
//  MultiAgentOrchestrator
//

import SwiftUI

struct ConnectionLinesView: View {
    let currentWorkflow: Workflow?
    @Binding var scale: CGFloat
    let offset: CGSize
    let lineColor: Color
    let lineWidth: CGFloat
    let textScale: CGFloat
    let textColor: Color
    @Binding var selectedEdgeID: UUID?
    var onEdgeSelected: ((WorkflowEdge) -> Void)?

    private let nodeWidth: CGFloat = 80
    private let nodeHeight: CGFloat = 60

    init(
        currentWorkflow: Workflow?,
        scale: Binding<CGFloat>,
        offset: CGSize,
        lineColor: Color = .blue,
        lineWidth: CGFloat = 2,
        textScale: CGFloat = 1,
        textColor: Color = .primary,
        selectedEdgeID: Binding<UUID?> = .constant(nil),
        onEdgeSelected: ((WorkflowEdge) -> Void)? = nil
    ) {
        self.currentWorkflow = currentWorkflow
        self._scale = scale
        self.offset = offset
        self.lineColor = lineColor
        self.lineWidth = lineWidth
        self.textScale = textScale
        self.textColor = textColor
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
                        let points = orthogonalRoute(from: startPoint, to: endPoint)
                        let isSelected = selectedEdgeID == edge.id
                        let baseColor = edge.requiresApproval ? Color.orange : lineColor

                        OrthogonalConnectionShape(points: points)
                            .stroke(
                                isSelected ? Color.accentColor : baseColor.opacity(0.78),
                                style: StrokeStyle(
                                    lineWidth: max(1, lineWidth + (isSelected ? 1 : 0)),
                                    lineCap: .round,
                                    lineJoin: .round,
                                    dash: edge.requiresApproval ? [8, 4] : []
                                )
                            )

                        OrthogonalConnectionShape(points: points)
                            .stroke(Color.clear, lineWidth: max(12, lineWidth + 10))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedEdgeID = edge.id
                                onEdgeSelected?(edge)
                            }

                        if points.count >= 2 {
                            ArrowShape(from: points[points.count - 2], to: points[points.count - 1])
                                .stroke(
                                    isSelected ? Color.accentColor : baseColor.opacity(0.9),
                                    style: StrokeStyle(lineWidth: max(1, lineWidth), lineCap: .round)
                                )
                        }

                        let displayText = edgeDisplayText(edge)
                        if !displayText.isEmpty {
                            EdgeLabelView(
                                text: displayText,
                                requiresApproval: edge.requiresApproval,
                                textScale: textScale,
                                textColor: textColor
                            )
                            .position(midPoint(for: points))
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

    private func orthogonalRoute(from start: CGPoint, to end: CGPoint) -> [CGPoint] {
        let dx = end.x - start.x
        let dy = end.y - start.y

        if abs(dx) >= abs(dy) {
            let midX = start.x + dx * 0.5
            return [
                start,
                CGPoint(x: midX, y: start.y),
                CGPoint(x: midX, y: end.y),
                end
            ]
        }

        let midY = start.y + dy * 0.5
        return [
            start,
            CGPoint(x: start.x, y: midY),
            CGPoint(x: end.x, y: midY),
            end
        ]
    }

    private func edgeDisplayText(_ edge: WorkflowEdge) -> String {
        let label = edge.label.trimmingCharacters(in: .whitespacesAndNewlines)
        let condition = edge.conditionExpression.trimmingCharacters(in: .whitespacesAndNewlines)

        if !label.isEmpty && !condition.isEmpty {
            return "\(label): \(condition)"
        }
        if !label.isEmpty {
            return label
        }
        if !condition.isEmpty {
            return condition
        }
        return edge.requiresApproval ? "Requires approval" : ""
    }

    private func midPoint(for points: [CGPoint]) -> CGPoint {
        guard points.count >= 2 else {
            return points.first ?? .zero
        }

        let totalLength = zip(points, points.dropFirst()).reduce(CGFloat(0)) { partial, segment in
            partial + hypot(segment.1.x - segment.0.x, segment.1.y - segment.0.y)
        }
        let target = totalLength * 0.5

        var walked: CGFloat = 0
        for (from, to) in zip(points, points.dropFirst()) {
            let segmentLength = hypot(to.x - from.x, to.y - from.y)
            if walked + segmentLength >= target, segmentLength > 0 {
                let ratio = (target - walked) / segmentLength
                return CGPoint(
                    x: from.x + (to.x - from.x) * ratio,
                    y: from.y + (to.y - from.y) * ratio
                )
            }
            walked += segmentLength
        }

        return points[points.count / 2]
    }
}

struct OrthogonalConnectionShape: Shape {
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        return path
    }
}

struct EdgeLabelView: View {
    let text: String
    let requiresApproval: Bool
    let textScale: CGFloat
    let textColor: Color

    var body: some View {
        HStack(spacing: 4) {
            if requiresApproval {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 8 * textScale))
            }
            Text(text)
                .font(.system(size: 10 * textScale, weight: .medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(requiresApproval ? Color.orange.opacity(0.95) : Color(NSColor.windowBackgroundColor).opacity(0.95))
        .foregroundColor(requiresApproval ? .white : textColor)
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
