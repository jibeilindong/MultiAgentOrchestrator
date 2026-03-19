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
            let layouts = buildEdgeLayouts(in: geo)

            ZStack {
                ForEach(layouts, id: \.edge.id) { layout in
                    OrthogonalConnectionShape(points: layout.points)
                        .stroke(
                            layout.isSelected ? Color.accentColor : layout.baseColor.opacity(0.78),
                            style: StrokeStyle(
                                lineWidth: max(1, lineWidth + (layout.isSelected ? 1 : 0)),
                                lineCap: .round,
                                lineJoin: .round,
                                dash: layout.edge.requiresApproval ? [8, 4] : []
                            )
                        )

                    if layout.points.count >= 2 {
                        ArrowShape(from: layout.points[layout.points.count - 2], to: layout.points[layout.points.count - 1])
                            .stroke(
                                layout.isSelected ? Color.accentColor : layout.baseColor.opacity(0.9),
                                style: StrokeStyle(lineWidth: max(1, lineWidth), lineCap: .round)
                            )
                    }

                    let displayText = edgeDisplayText(layout.edge)
                    if !displayText.isEmpty {
                        EdgeLabelView(
                            text: displayText,
                            requiresApproval: layout.edge.requiresApproval,
                            textScale: textScale,
                            textColor: textColor
                        )
                        .position(midPoint(for: layout.points))
                    }
                }
            }
            .overlay(hitTestOverlay(layouts: layouts))
        }
    }

    private func buildEdgeLayouts(in geometry: GeometryProxy) -> [EdgeLayout] {
        guard let workflow = currentWorkflow else { return [] }
        let nodesByID = Dictionary(uniqueKeysWithValues: workflow.nodes.map { ($0.id, $0) })

        return workflow.edges.compactMap { edge in
            guard let fromNode = nodesByID[edge.fromNodeID],
                  let toNode = nodesByID[edge.toNodeID] else {
                return nil
            }

            let fromPos = getNodeCenter(fromNode.position, geometry: geometry)
            let toPos = getNodeCenter(toNode.position, geometry: geometry)
            let startPoint = calculateEdgePoint(from: fromPos, to: toPos)
            let endPoint = calculateEdgePoint(from: toPos, to: fromPos)
            let points = orthogonalRoute(from: startPoint, to: endPoint)
            let baseColor = edge.requiresApproval ? Color.orange : lineColor
            return EdgeLayout(
                edge: edge,
                points: points,
                isSelected: selectedEdgeID == edge.id,
                baseColor: baseColor
            )
        }
    }

    private func hitTestOverlay(layouts: [EdgeLayout]) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        let movement = hypot(value.translation.width, value.translation.height)
                        guard movement < 4 else { return }
                        guard let matchedEdge = nearestEdge(to: value.location, from: layouts) else { return }
                        selectedEdgeID = matchedEdge.id
                        onEdgeSelected?(matchedEdge)
                    }
            )
    }

    private func nearestEdge(to point: CGPoint, from layouts: [EdgeLayout]) -> WorkflowEdge? {
        let tolerance = max(14, lineWidth + 10)
        var nearest: (edge: WorkflowEdge, distance: CGFloat)?

        for layout in layouts {
            let distance = distance(from: point, toPolyline: layout.points)
            guard distance <= tolerance else { continue }

            if let currentNearest = nearest {
                if distance < currentNearest.distance {
                    nearest = (layout.edge, distance)
                }
            } else {
                nearest = (layout.edge, distance)
            }
        }

        return nearest?.edge
    }

    private func distance(from point: CGPoint, toPolyline points: [CGPoint]) -> CGFloat {
        guard points.count >= 2 else { return .greatestFiniteMagnitude }
        return zip(points, points.dropFirst()).reduce(CGFloat.greatestFiniteMagnitude) { currentMin, segment in
            min(currentMin, distance(from: point, toSegmentFrom: segment.0, to: segment.1))
        }
    }

    private func distance(from point: CGPoint, toSegmentFrom start: CGPoint, to end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else {
            return hypot(point.x - start.x, point.y - start.y)
        }

        let t = max(0, min(1, ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared))
        let projection = CGPoint(x: start.x + t * dx, y: start.y + t * dy)
        return hypot(point.x - projection.x, point.y - projection.y)
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

private struct EdgeLayout {
    let edge: WorkflowEdge
    let points: [CGPoint]
    let isSelected: Bool
    let baseColor: Color
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
