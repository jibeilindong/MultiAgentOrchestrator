//
//  ConnectionLinesView.swift
//  Multi-Agent-Flow
//

import SwiftUI
import Foundation

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
    var onEdgeSecondarySelected: ((WorkflowEdge) -> Void)?

    init(
        currentWorkflow: Workflow?,
        scale: Binding<CGFloat>,
        offset: CGSize,
        lineColor: Color = .blue,
        lineWidth: CGFloat = 2,
        textScale: CGFloat = 1,
        textColor: Color = .primary,
        selectedEdgeID: Binding<UUID?> = .constant(nil),
        onEdgeSelected: ((WorkflowEdge) -> Void)? = nil,
        onEdgeSecondarySelected: ((WorkflowEdge) -> Void)? = nil
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
        self.onEdgeSecondarySelected = onEdgeSecondarySelected
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(buildEdgeLayouts(in: geo), id: \.edge.id) { layout in
                    let points = layout.points

                    OrthogonalConnectionShape(points: points)
                        .stroke(
                            layout.isSelected ? Color.accentColor : layout.baseColor.opacity(0.78),
                            style: StrokeStyle(
                                lineWidth: max(1, lineWidth + (layout.isSelected ? 1 : 0)),
                                lineCap: .round,
                                lineJoin: .round,
                                dash: layout.edge.requiresApproval ? [8, 4] : []
                            )
                        )

                    ConnectionHitShape(points: points, hitWidth: max(18, lineWidth + 14))
                        .fill(Color.clear)
                        .contentShape(ConnectionHitShape(points: points, hitWidth: max(18, lineWidth + 14)))
                        .onTapGesture {
                            selectedEdgeID = layout.edge.id
                            onEdgeSelected?(layout.edge)
                        }

                    if points.count >= 2 {
                        ArrowShape(from: points[points.count - 2], to: points[points.count - 1])
                            .stroke(
                                layout.isSelected ? Color.accentColor : layout.baseColor.opacity(0.9),
                                style: StrokeStyle(lineWidth: max(1, lineWidth), lineCap: .round)
                            )
                        if layout.edge.isBidirectional {
                            ArrowShape(from: points[1], to: points[0])
                                .stroke(
                                    layout.isSelected ? Color.accentColor : layout.baseColor.opacity(0.9),
                                    style: StrokeStyle(lineWidth: max(1, lineWidth), lineCap: .round)
                                )
                        }
                    }

                    let displayText = layout.displayText
                    if !displayText.isEmpty {
                        EdgeLabelView(
                            text: displayText,
                            requiresApproval: layout.edge.requiresApproval,
                            textScale: textScale,
                            textColor: textColor
                        )
                        .position(midPoint(for: points))
                    }
                }
            }
        }
    }

    private func buildEdgeLayouts(in geometry: GeometryProxy) -> [EdgeLayout] {
        guard let workflow = currentWorkflow else { return [] }
        let nodesByID: [UUID: WorkflowNode] = Dictionary(uniqueKeysWithValues: workflow.nodes.map { ($0.id, $0) })
        let candidates = workflow.edges.compactMap { edge -> RoutedEdgeCandidate? in
            guard let fromNode = nodesByID[edge.fromNodeID],
                  let toNode = nodesByID[edge.toNodeID] else {
                return nil
            }

            let fromFrame = nodeFrame(for: fromNode, geometry: geometry)
            let toFrame = nodeFrame(for: toNode, geometry: geometry)
            let targetSide = WorkflowEdgeRoutePlanner.preferredIncomingSide(
                for: toFrame,
                toward: fromFrame.center
            )
            return RoutedEdgeCandidate(
                edge: edge,
                fromFrame: fromFrame,
                toFrame: toFrame,
                targetSide: targetSide
            )
        }

        let fanoutInfoBySourceID = fanoutLayoutMap(for: candidates, in: geometry, workflow: workflow)
        let grouped = Dictionary(grouping: candidates, by: { $0.bundleKey })
        var layouts: [EdgeLayout] = []

        for bundle in grouped.values {
            let sortedBundle = bundle.sorted { lhs, rhs in
                let lhsAngle = angle(from: lhs.toFrame.center, to: lhs.fromFrame.center)
                let rhsAngle = angle(from: rhs.toFrame.center, to: rhs.fromFrame.center)
                return lhsAngle < rhsAngle
            }
            let laneOffsets = laneOffsets(for: sortedBundle.count)

            for (index, candidate) in sortedBundle.enumerated() {
                let obstacles = workflow.nodes
                    .compactMap { node -> CGRect? in
                        guard node.id != candidate.edge.fromNodeID,
                              node.id != candidate.edge.toNodeID else { return nil }
                        return nodeFrame(for: node, geometry: geometry)
                    }

                let path: [CGPoint]
                if let fanoutInfo = fanoutInfoBySourceID[candidate.edge.fromNodeID] {
                    if candidate.edge.toNodeID == fanoutInfo.centerTargetID,
                       abs(candidate.toFrame.midX - candidate.fromFrame.midX) <= 28 {
                        path = WorkflowEdgeRoutePlanner.centerDownRoute(
                            from: candidate.fromFrame,
                            to: candidate.toFrame,
                            avoiding: obstacles
                        ) ?? WorkflowEdgeRoutePlanner.route(
                            from: candidate.fromFrame,
                            to: candidate.toFrame,
                            avoiding: obstacles,
                            preferredAxis: .vertical,
                            laneOffset: 0
                        )
                    } else if let fanoutPath = WorkflowEdgeRoutePlanner.fanoutRoute(
                        from: candidate.fromFrame,
                        to: candidate.toFrame,
                        turnY: fanoutInfo.turnY,
                        branchOffset: fanoutInfo.branchOffset(for: candidate.edge.toNodeID),
                        avoiding: obstacles
                    ) {
                        path = fanoutPath
                    } else {
                        path = WorkflowEdgeRoutePlanner.route(
                            from: candidate.fromFrame,
                            to: candidate.toFrame,
                            avoiding: obstacles,
                            preferredAxis: candidate.preferredAxis,
                            laneOffset: laneOffsets[index]
                        )
                    }
                } else {
                    path = WorkflowEdgeRoutePlanner.route(
                        from: candidate.fromFrame,
                        to: candidate.toFrame,
                        avoiding: obstacles,
                        preferredAxis: candidate.preferredAxis,
                        laneOffset: laneOffsets[index]
                    )
                }

                layouts.append(
                    EdgeLayout(
                        edge: candidate.edge,
                        points: path,
                        isSelected: selectedEdgeID == candidate.edge.id,
                        baseColor: candidate.edge.requiresApproval ? Color.orange : lineColor,
                        displayText: edgeDisplayText(candidate.edge)
                    )
                )
            }
        }

        return layouts
    }

    private func fanoutLayoutMap(
        for candidates: [RoutedEdgeCandidate],
        in geometry: GeometryProxy,
        workflow: Workflow
    ) -> [UUID: FanoutLayoutInfo] {
        let groupedBySource = Dictionary(grouping: candidates, by: { $0.edge.fromNodeID })
        var layoutBySource: [UUID: FanoutLayoutInfo] = [:]

        for (sourceID, group) in groupedBySource {
            guard group.count >= 3,
                  let sourceFrame = group.first?.fromFrame else { continue }

            let downwardTargets = group.filter { candidate in
                candidate.toFrame.center.y > sourceFrame.center.y + 18
            }
            guard downwardTargets.count >= 3 else { continue }

            let sourceBottom = sourceFrame.maxY + 10
            let targetTop = downwardTargets.map { $0.toFrame.minY }.min() ?? .greatestFiniteMagnitude
            let centeredTarget = closestTarget(to: sourceFrame.midX, in: downwardTargets)

            let centeredBottom = centeredTarget?.toFrame.maxY ?? sourceBottom
            let turnY = max(sourceBottom + 34, centeredBottom + 18)
            guard turnY < targetTop - 14 else { continue }

            let sortedTargets = downwardTargets.sorted {
                let lhsDistance = abs($0.toFrame.midX - sourceFrame.midX)
                let rhsDistance = abs($1.toFrame.midX - sourceFrame.midX)
                if abs(lhsDistance - rhsDistance) > 0.5 {
                    return lhsDistance < rhsDistance
                }
                return $0.toFrame.midX < $1.toFrame.midX
            }

            let fanoutSpacingValue = WorkflowEdgeRoutePlanner.fanoutSpacing(for: sourceFrame, targetCount: sortedTargets.count)
            let slotOffsets = laneOffsets(for: sortedTargets.count, spacing: fanoutSpacingValue)
            let branchOffsetsByTargetID: [UUID: CGFloat] = Dictionary(uniqueKeysWithValues: zip(sortedTargets, slotOffsets).map { candidate, offset in
                (candidate.edge.toNodeID, offset)
            })

            layoutBySource[sourceID] = FanoutLayoutInfo(
                turnY: min(turnY, targetTop - 14),
                centerTargetID: centeredTarget?.edge.toNodeID,
                branchOffsetsByTargetID: branchOffsetsByTargetID
            )
        }

        return layoutBySource
    }

    private func closestTarget(
        to sourceMidX: CGFloat,
        in candidates: [RoutedEdgeCandidate]
    ) -> RoutedEdgeCandidate? {
        guard !candidates.isEmpty else { return nil }

        var bestCandidate = candidates[0]
        var bestDistance = abs(bestCandidate.toFrame.midX - sourceMidX)

        for candidate in candidates.dropFirst() {
            let distance = abs(candidate.toFrame.midX - sourceMidX)
            if distance < bestDistance {
                bestCandidate = candidate
                bestDistance = distance
            }
        }

        return bestCandidate
    }

    private func nodeFrame(for node: WorkflowNode, geometry: GeometryProxy) -> CGRect {
        let center = getNodeCenter(node.position, geometry: geometry)
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

    private func getNodeCenter(_ position: CGPoint, geometry: GeometryProxy) -> CGPoint {
        let centerX = geometry.size.width / 2
        let centerY = geometry.size.height / 2
        return CGPoint(
            x: position.x * scale + offset.width + centerX,
            y: position.y * scale + offset.height + centerY
        )
    }

    private func displayText(for edges: [WorkflowEdge]) -> String {
        let labels = Set(edges.map(edgeDisplayText).filter { !$0.isEmpty })
        if labels.count == 1 {
            return labels.first ?? ""
        }
        return edges.count == 1 ? edgeDisplayText(edges[0]) : ""
    }

    private func laneOffsets(for count: Int) -> [CGFloat] {
        laneOffsets(for: count, spacing: 14)
    }

    private func laneOffsets(for count: Int, spacing: CGFloat) -> [CGFloat] {
        guard count > 1 else { return [0] }

        let center = CGFloat(count - 1) / 2
        return (0..<count).map { index in
            (CGFloat(index) - center) * spacing
        }
    }

    private func angle(from center: CGPoint, to point: CGPoint) -> CGFloat {
        atan2(point.y - center.y, point.x - center.x)
    }

    private func edgeDisplayText(_ edge: WorkflowEdge) -> String {
        let label = edge.label.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let condition = edge.conditionExpression.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

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
    let displayText: String
}

private struct RoutedEdgeCandidate {
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

enum EdgeAnchorSide: String, Hashable {
    case left
    case right
    case top
    case bottom
}

struct WorkflowEdgeRoutePlanner {
    private static let anchorClearance: CGFloat = 10
    private static let obstaclePadding: CGFloat = 14
    private static let candidateSpacing: CGFloat = 16

    static func route(
        from sourceFrame: CGRect,
        to targetFrame: CGRect,
        avoiding obstacles: [CGRect],
        preferredAxis: EdgeRouteAxis,
        laneOffset: CGFloat
    ) -> [CGPoint] {
        let sourceCenter = sourceFrame.center
        let targetCenter = targetFrame.center
        let sourceSide = preferredOutgoingSide(for: sourceFrame, toward: targetCenter)
        let targetSide = preferredIncomingSide(for: targetFrame, toward: sourceCenter)

        let start = anchorPoint(on: sourceFrame, side: sourceSide, laneOffset: laneOffset)
        let end = anchorPoint(on: targetFrame, side: targetSide, laneOffset: laneOffset)
        let blockedRects = obstacles.map { $0.insetBy(dx: -obstaclePadding, dy: -obstaclePadding) }

        let candidates = candidatePaths(
            from: start,
            to: end,
            blockedRects: blockedRects,
            laneOffset: laneOffset,
            preferredAxis: preferredAxis
        )

        for path in candidates {
            if isClear(path, blockedRects: blockedRects) {
                return simplify(path)
            }
        }

        return simplify(candidates.first ?? [start, end])
    }

    static func fanoutRoute(
        from sourceFrame: CGRect,
        to targetFrame: CGRect,
        turnY: CGFloat,
        branchOffset: CGFloat,
        avoiding obstacles: [CGRect]
    ) -> [CGPoint]? {
        let start = CGPoint(x: sourceFrame.midX, y: sourceFrame.maxY + anchorClearance)
        let end = CGPoint(x: targetFrame.midX, y: targetFrame.minY - anchorClearance)
        guard turnY > start.y + 4, turnY < end.y - 4 else { return nil }

        let path = simplify([
            start,
            CGPoint(x: sourceFrame.midX, y: turnY),
            CGPoint(x: sourceFrame.midX + branchOffset, y: turnY),
            CGPoint(x: targetFrame.midX, y: turnY),
            end
        ])

        let blockedRects = obstacles.map { $0.insetBy(dx: -obstaclePadding, dy: -obstaclePadding) }
        return isClear(path, blockedRects: blockedRects) ? path : nil
    }

    static func fanoutSpacing(for sourceFrame: CGRect, targetCount: Int) -> CGFloat {
        guard targetCount > 1 else { return 0 }

        let base = max(20, sourceFrame.width * 0.42)
        let spread = CGFloat(targetCount - 1)
        let even = max(22, base / max(spread, 1))
        return min(42, max(18, even))
    }

    static func centerDownRoute(
        from sourceFrame: CGRect,
        to targetFrame: CGRect,
        avoiding obstacles: [CGRect]
    ) -> [CGPoint]? {
        let start = CGPoint(x: sourceFrame.midX, y: sourceFrame.maxY + anchorClearance)
        let end = CGPoint(x: targetFrame.midX, y: targetFrame.minY - anchorClearance)
        let blockedRects = obstacles.map { $0.insetBy(dx: -obstaclePadding, dy: -obstaclePadding) }

        let direct = simplify([start, end])
        if isClear(direct, blockedRects: blockedRects) {
            return direct
        }

        let midY = (start.y + end.y) / 2
        let fallback = simplify([
            start,
            CGPoint(x: start.x, y: midY),
            CGPoint(x: end.x, y: midY),
            end
        ])
        return isClear(fallback, blockedRects: blockedRects) ? fallback : nil
    }

    private static func candidatePaths(
        from start: CGPoint,
        to end: CGPoint,
        blockedRects: [CGRect],
        laneOffset: CGFloat,
        preferredAxis: EdgeRouteAxis
    ) -> [[CGPoint]] {
        var ranked: [(points: [CGPoint], bends: Int, length: CGFloat)] = []
        var seen = Set<String>()

        func append(_ points: [CGPoint], bends: Int) {
            let key = points.map { "\(Int(($0.x * 10).rounded())):\(Int(($0.y * 10).rounded()))" }.joined(separator: "|")
            guard seen.insert(key).inserted else { return }
            ranked.append((points: points, bends: bends, length: pathLength(points)))
        }

        if abs(start.x - end.x) < 0.5 {
            append([start, end], bends: 0)
        }

        if preferredAxis == .horizontal {
            let midY = (start.y + end.y) / 2
            append([
                start,
                CGPoint(x: start.x, y: midY),
                CGPoint(x: end.x, y: midY),
                end
            ], bends: 2)
        }

        let corridorYs = corridorYs(
            from: start,
            to: end,
            blockedRects: blockedRects,
            laneOffset: laneOffset,
            preferredAxis: preferredAxis
        )
        for y in corridorYs {
            append([
                start,
                CGPoint(x: start.x, y: y),
                CGPoint(x: end.x, y: y),
                end
            ], bends: 2)
        }

        let outerXs = outerCorridorXs(for: blockedRects, laneOffset: laneOffset)
        let yPairs = orderedYPairs(from: corridorYs)
        for outerX in outerXs {
            for pair in yPairs {
                append([
                    start,
                    CGPoint(x: start.x, y: pair.0),
                    CGPoint(x: outerX, y: pair.0),
                    CGPoint(x: outerX, y: pair.1),
                    CGPoint(x: end.x, y: pair.1),
                    end
                ], bends: 4)
            }
        }

        return ranked
            .sorted { lhs, rhs in
                if lhs.bends != rhs.bends { return lhs.bends < rhs.bends }
                return lhs.length < rhs.length
            }
            .map(\.points)
    }

    private static func corridorYs(
        from start: CGPoint,
        to end: CGPoint,
        blockedRects: [CGRect],
        laneOffset: CGFloat,
        preferredAxis: EdgeRouteAxis
    ) -> [CGFloat] {
        var values: [CGFloat] = [
            (start.y + end.y) / 2 + laneOffset
        ]

        for rect in blockedRects {
            values.append(rect.minY - candidateSpacing)
            values.append(rect.maxY + candidateSpacing)
        }

        let anchorBias = preferredAxis == .horizontal ? candidateSpacing : candidateSpacing * 0.5
        values.append(min(start.y, end.y) - candidateSpacing - anchorBias)
        values.append(max(start.y, end.y) + candidateSpacing + anchorBias)

        return uniqueSorted(values)
    }

    private static func outerCorridorXs(for blockedRects: [CGRect], laneOffset: CGFloat) -> [CGFloat] {
        guard !blockedRects.isEmpty else { return [laneOffset == 0 ? 0 : laneOffset] }

        let minX = blockedRects.map(\.minX).min() ?? 0
        let maxX = blockedRects.map(\.maxX).max() ?? 0
        return uniqueSorted([
            minX - candidateSpacing * 2 - abs(laneOffset),
            maxX + candidateSpacing * 2 + abs(laneOffset)
        ])
    }

    private static func orderedYPairs(from values: [CGFloat]) -> [(CGFloat, CGFloat)] {
        guard values.count > 1 else { return [] }
        var pairs: [(CGFloat, CGFloat)] = []
        for lhs in values {
            for rhs in values where abs(lhs - rhs) > 0.5 {
                pairs.append((lhs, rhs))
            }
        }
        return pairs.sorted { lhs, rhs in
            let lhsMid = (lhs.0 + lhs.1) / 2
            let rhsMid = (rhs.0 + rhs.1) / 2
            let lhsSpan = abs(lhs.0 - lhs.1)
            let rhsSpan = abs(rhs.0 - rhs.1)
            if lhsSpan != rhsSpan { return lhsSpan < rhsSpan }
            return abs(lhsMid) < abs(rhsMid)
        }
    }

    private static func uniqueSorted(_ values: [CGFloat]) -> [CGFloat] {
        var result: [CGFloat] = []
        for value in values.sorted() {
            if result.contains(where: { abs($0 - value) < 0.5 }) { continue }
            result.append(value)
        }
        return result
    }

    private static func pathLength(_ points: [CGPoint]) -> CGFloat {
        guard points.count >= 2 else { return 0 }
        return zip(points, points.dropFirst()).reduce(0) { partial, segment in
            partial + hypot(segment.1.x - segment.0.x, segment.1.y - segment.0.y)
        }
    }

    static func preferredOutgoingSide(for rect: CGRect, toward point: CGPoint) -> EdgeAnchorSide {
        preferredSide(for: rect, toward: point)
    }

    static func preferredIncomingSide(for rect: CGRect, toward point: CGPoint) -> EdgeAnchorSide {
        preferredSide(for: rect, toward: point)
    }

    private static func preferredSide(for rect: CGRect, toward point: CGPoint) -> EdgeAnchorSide {
        let center = rect.center
        let dx = point.x - center.x
        let dy = point.y - center.y

        if abs(dx) >= abs(dy) * 0.7 {
            return dx >= 0 ? .right : .left
        }

        return dy >= 0 ? .bottom : .top
    }

    private static func anchorPoint(on rect: CGRect, side: EdgeAnchorSide, laneOffset: CGFloat) -> CGPoint {
        switch side {
        case .top: return CGPoint(x: rect.midX + laneOffset, y: rect.minY - anchorClearance)
        case .bottom: return CGPoint(x: rect.midX + laneOffset, y: rect.maxY + anchorClearance)
        case .left: return CGPoint(x: rect.minX - anchorClearance, y: rect.midY + laneOffset)
        case .right: return CGPoint(x: rect.maxX + anchorClearance, y: rect.midY + laneOffset)
        }
    }

    private static func isClear(_ path: [CGPoint], blockedRects: [CGRect]) -> Bool {
        guard path.count >= 2 else { return false }
        for (from, to) in zip(path, path.dropFirst()) {
            if blockedRects.contains(where: { segment(from, to: to).intersects($0) }) {
                return false
            }
        }
        return true
    }

    private static func simplify(_ path: [CGPoint]) -> [CGPoint] {
        guard path.count > 2 else { return path }

        var points: [CGPoint] = [path[0]]
        for point in path.dropFirst() {
            while points.count >= 2 {
                let a = points[points.count - 2]
                let b = points[points.count - 1]
                if isCollinear(a, b, point) {
                    points.removeLast()
                } else {
                    break
                }
            }
            points.append(point)
        }
        return points
    }

    private static func isCollinear(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> Bool {
        (abs(a.x - b.x) < 0.5 && abs(b.x - c.x) < 0.5) ||
        (abs(a.y - b.y) < 0.5 && abs(b.y - c.y) < 0.5)
    }

    private static func segment(_ from: CGPoint, to: CGPoint) -> CGRect {
        CGRect(
            x: min(from.x, to.x),
            y: min(from.y, to.y),
            width: max(abs(to.x - from.x), 1),
            height: max(abs(to.y - from.y), 1)
        ).insetBy(dx: -1, dy: -1)
    }
}

private struct FanoutLayoutInfo {
    let turnY: CGFloat
    let centerTargetID: UUID?
    let branchOffsetsByTargetID: [UUID: CGFloat]

    func branchOffset(for targetID: UUID) -> CGFloat {
        branchOffsetsByTargetID[targetID] ?? 0
    }
}

enum EdgeRouteAxis {
    case horizontal
    case vertical
}

private extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}

private extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        hypot(x - other.x, y - other.y)
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

struct ConnectionHitShape: Shape {
    let points: [CGPoint]
    let hitWidth: CGFloat

    func path(in rect: CGRect) -> Path {
        OrthogonalConnectionShape(points: points)
            .path(in: rect)
            .strokedPath(
                StrokeStyle(
                    lineWidth: hitWidth,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
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
