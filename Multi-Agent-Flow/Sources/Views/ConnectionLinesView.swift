//
//  ConnectionLinesView.swift
//  Multi-Agent-Flow
//

import SwiftUI
import Foundation

struct ConnectionLinesView: View {
    @ObservedObject private var localizationManager = LocalizationManager.shared
    let edgeLayouts: [WorkflowCanvasEdgeLayout]
    let sharedHitLayouts: [WorkflowCanvasSharedSegmentHitLayout]
    let previewLineLayouts: [WorkflowCanvasPreviewLineLayout]
    let blockedRects: [CGRect]
    let lineColor: Color
    let lineWidth: CGFloat
    let textScale: CGFloat
    let textColor: Color
    @Binding var selectedEdgeID: UUID?
    let recentlyCreatedEdgeIDs: Set<UUID>
    @State private var renderCache = ConnectionEdgeRenderCache()
    @State private var hoveredSharedSegmentID: String?
    var onEdgeSelected: ((WorkflowEdge) -> Void)?

    init(
        edgeLayouts: [WorkflowCanvasEdgeLayout] = [],
        sharedHitLayouts: [WorkflowCanvasSharedSegmentHitLayout] = [],
        previewLineLayouts: [WorkflowCanvasPreviewLineLayout] = [],
        blockedRects: [CGRect] = [],
        lineColor: Color = .blue,
        lineWidth: CGFloat = 2,
        textScale: CGFloat = 1,
        textColor: Color = .black,
        selectedEdgeID: Binding<UUID?> = .constant(nil),
        recentlyCreatedEdgeIDs: Set<UUID> = [],
        onEdgeSelected: ((WorkflowEdge) -> Void)? = nil
    ) {
        self.edgeLayouts = edgeLayouts
        self.sharedHitLayouts = sharedHitLayouts
        self.previewLineLayouts = previewLineLayouts
        self.blockedRects = blockedRects
        self.lineColor = lineColor
        self.lineWidth = lineWidth
        self.textScale = textScale
        self.textColor = textColor
        self._selectedEdgeID = selectedEdgeID
        self.recentlyCreatedEdgeIDs = recentlyCreatedEdgeIDs
        self.onEdgeSelected = onEdgeSelected
    }

    var body: some View {
        let renderData = buildRenderData()
        ZStack {
            ForEach(renderData.edgeLayouts, id: \.edge.id) { layout in
                if !layout.strokePolylines.isEmpty {
                    OrthogonalConnectionGroupShape(polylines: layout.strokePolylines)
                        .stroke(
                            strokeColor(for: layout),
                            style: strokeStyle(for: layout)
                        )
                }
            }

            ForEach(renderData.edgeLayouts, id: \.edge.id) { layout in
                ForEach(layout.bridgeOverlays) { bridge in
                    BridgeMaskShape(from: bridge.eraseFrom, to: bridge.eraseTo)
                        .stroke(
                            Color(NSColor.windowBackgroundColor).opacity(0.98),
                            style: StrokeStyle(
                                lineWidth: max(strokeWidth(for: layout) + 2.5, lineWidth + 4),
                                lineCap: .round
                            )
                        )

                    BridgeArcShape(
                        from: bridge.arcFrom,
                        control: bridge.control,
                        to: bridge.arcTo
                    )
                    .stroke(
                        strokeColor(for: layout),
                        style: strokeStyle(for: layout)
                    )
                }
            }

            ForEach(previewLineLayouts, id: \.id) { previewLine in
                Path { path in
                    path.move(to: previewLine.from)
                    path.addLine(to: previewLine.to)
                }
                .stroke(
                    Color.accentColor.opacity(0.85),
                    style: StrokeStyle(lineWidth: max(2, lineWidth + 0.5), lineCap: .round, dash: [10, 6])
                )
            }

            ForEach(renderData.edgeLayouts, id: \.edge.id) { layout in
                let points = layout.points

                ConnectionHitShape(points: points, hitWidth: max(18, lineWidth + 14))
                    .fill(Color.clear)
                    .contentShape(ConnectionHitShape(points: points, hitWidth: max(18, lineWidth + 14)))
                    .onTapGesture {
                        selectedEdgeID = layout.edge.id
                        onEdgeSelected?(layout.edge)
                    }

                if points.count >= 2 {
                    if layout.showsForwardArrow {
                        ArrowShape(from: points[points.count - 2], to: points[points.count - 1])
                            .stroke(
                                arrowColor(for: layout),
                                style: StrokeStyle(lineWidth: max(1, lineWidth), lineCap: .round)
                            )
                    }
                    if layout.edge.isBidirectional {
                        ArrowShape(from: points[1], to: points[0])
                            .stroke(
                                arrowColor(for: layout),
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
                        textColor: textColor,
                        accentColor: layout.baseColor
                    )
                    .position(layout.labelPosition ?? labelPosition(for: layout))
                }
            }

            ForEach(renderData.sharedHitLayouts, id: \.id) { sharedHit in
                let isHovered = hoveredSharedSegmentID == sharedHit.id
                let containsSelectedEdge = selectedEdgeID.map { selectedID in
                    sharedHit.edges.contains(where: { $0.id == selectedID })
                } ?? false

                if isHovered {
                    OrthogonalConnectionShape(points: sharedHit.points)
                        .stroke(
                            Color.accentColor.opacity(containsSelectedEdge ? 0.5 : 0.35),
                            style: StrokeStyle(
                                lineWidth: max(containsSelectedEdge ? 7 : 6, lineWidth + 4),
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )
                        .allowsHitTesting(false)
                }

                ConnectionHitShape(points: sharedHit.points, hitWidth: max(22, lineWidth + 16))
                    .fill(Color.clear)
                    .contentShape(ConnectionHitShape(points: sharedHit.points, hitWidth: max(22, lineWidth + 16)))
                    .onTapGesture {
                        cycleSharedSegmentSelection(sharedHit.edges)
                    }
            }
        }
        .onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case .active(let location):
                updateHoveredSharedSegment(
                    sharedSegmentHitID(at: location, in: renderData.sharedHitLayouts)
                )
            case .ended:
                updateHoveredSharedSegment(nil)
            }
        }
    }

    private func buildRenderData() -> ConnectionRenderData {
        let resolvedEdgeLayouts = renderCache.resolve(signature: renderSignature()) {
            let renderEdgeLayouts = edgeLayouts.map { layout in
                EdgeLayout(
                    edge: layout.edge,
                    points: layout.points,
                    strokePolylines: [layout.points],
                    isSelected: selectedEdgeID == layout.edge.id,
                    isRecentlyCreated: recentlyCreatedEdgeIDs.contains(layout.edge.id),
                    baseColor: edgeBaseColor(layout.edge),
                    displayText: edgeDisplayText(layout.edge),
                    showsForwardArrow: true,
                    labelPosition: nil,
                    bridgeOverlays: []
                )
            }

            return resolvedLabelLayouts(
                resolvedBridgeLayouts(
                    resolvedSharedStrokeLayouts(deduplicatedArrowLayouts(renderEdgeLayouts))
                ),
                blockedRects: blockedRects
            )
        }

        return ConnectionRenderData(
            edgeLayouts: resolvedEdgeLayouts,
            sharedHitLayouts: sharedHitLayouts
        )
    }

    private func renderSignature() -> Int {
        var hasher = Hasher()
        hasher.combine(selectedEdgeID)
        hasher.combine(recentlyCreatedEdgeIDs.count)
        for edgeID in recentlyCreatedEdgeIDs.sorted(by: { $0.uuidString < $1.uuidString }) {
            hasher.combine(edgeID)
        }

        hasher.combine(Double(lineWidth))
        hasher.combine(Double(textScale))
        hasher.combine(approvalText)
        hasher.combine(String(describing: lineColor))

        hasher.combine(edgeLayouts.count)
        for layout in edgeLayouts {
            hasher.combine(layout.edge.id)
            hasher.combine(layout.edge.fromNodeID)
            hasher.combine(layout.edge.toNodeID)
            hasher.combine(layout.edge.label)
            hasher.combine(layout.edge.conditionExpression)
            hasher.combine(layout.edge.requiresApproval)
            hasher.combine(layout.edge.isBidirectional)
            hasher.combine(layout.edge.displayColorHex ?? "")
            hasher.combine(layout.points.count)
            for point in layout.points {
                hasher.combine(normalizedCoordinate(point.x))
                hasher.combine(normalizedCoordinate(point.y))
            }
        }

        let blockedRectSignatures = blockedRects.map(rectSignature).sorted()
        hasher.combine(blockedRectSignatures.count)
        for signature in blockedRectSignatures {
            hasher.combine(signature)
        }

        return hasher.finalize()
    }

    private func strokeWidth(for layout: EdgeLayout) -> CGFloat {
        max(1, lineWidth + (layout.isSelected ? 1 : 0) + (layout.isRecentlyCreated ? 1.5 : 0))
    }

    private func strokeColor(for layout: EdgeLayout) -> Color {
        layout.isSelected
            ? Color.accentColor
            : (layout.isRecentlyCreated ? Color.accentColor.opacity(0.92) : layout.baseColor.opacity(0.78))
    }

    private func arrowColor(for layout: EdgeLayout) -> Color {
        layout.isSelected
            ? Color.accentColor
            : (layout.isRecentlyCreated ? Color.accentColor.opacity(0.95) : layout.baseColor.opacity(0.9))
    }

    private func strokeStyle(for layout: EdgeLayout) -> StrokeStyle {
        StrokeStyle(
            lineWidth: strokeWidth(for: layout),
            lineCap: .round,
            lineJoin: .round,
            dash: layout.edge.requiresApproval ? [8, 4] : []
        )
    }

    private func deduplicatedArrowLayouts(_ layouts: [EdgeLayout]) -> [EdgeLayout] {
        let layoutsByTerminalSegment = Dictionary(grouping: layouts.enumerated(), by: { _, layout in
            guard layout.points.count >= 2 else { return "" }
            return normalizedSegmentKey(
                from: layout.points[layout.points.count - 2],
                to: layout.points[layout.points.count - 1]
            )
        })

        let preferredArrowEdgeIDBySegment: [String: UUID] = Dictionary(
            uniqueKeysWithValues: layoutsByTerminalSegment.compactMap { segmentKey, entries in
                guard !segmentKey.isEmpty else { return nil }
                let preferred = entries.first(where: { $0.element.isSelected })?.element
                    ?? entries.first?.element
                guard let preferred else { return nil }
                return (segmentKey, preferred.edge.id)
            }
        )

        return layouts.map { layout in
            guard layout.points.count >= 2 else { return layout }

            let segmentKey = normalizedSegmentKey(
                from: layout.points[layout.points.count - 2],
                to: layout.points[layout.points.count - 1]
            )
            let shouldShowArrow = preferredArrowEdgeIDBySegment[segmentKey] == layout.edge.id

            return EdgeLayout(
                edge: layout.edge,
                points: layout.points,
                strokePolylines: layout.strokePolylines,
                isSelected: layout.isSelected,
                isRecentlyCreated: layout.isRecentlyCreated,
                baseColor: layout.baseColor,
                displayText: layout.displayText,
                showsForwardArrow: shouldShowArrow,
                labelPosition: layout.labelPosition,
                bridgeOverlays: layout.bridgeOverlays
            )
        }
    }

    private func resolvedSharedStrokeLayouts(_ layouts: [EdgeLayout]) -> [EdgeLayout] {
        var seenSegments = Set<String>()

        return layouts.map { layout in
            if layout.isSelected {
                for (from, to) in zip(layout.points, layout.points.dropFirst()) {
                    seenSegments.insert(normalizedUndirectedSegmentKey(from: from, to: to))
                }
                return layout
            }

            let uniquePolylines = uniqueStrokePolylines(
                from: layout.points,
                seenSegments: &seenSegments
            )

            return EdgeLayout(
                edge: layout.edge,
                points: layout.points,
                strokePolylines: uniquePolylines,
                isSelected: layout.isSelected,
                isRecentlyCreated: layout.isRecentlyCreated,
                baseColor: layout.baseColor,
                displayText: layout.displayText,
                showsForwardArrow: layout.showsForwardArrow,
                labelPosition: layout.labelPosition,
                bridgeOverlays: layout.bridgeOverlays
            )
        }
    }

    private func resolvedBridgeLayouts(_ layouts: [EdgeLayout]) -> [EdgeLayout] {
        let segmentRefs = layouts.flatMap { layout in
            layout.strokePolylines.enumerated().flatMap { _, polyline in
                strokeSegments(
                    in: polyline,
                    edgeID: layout.edge.id
                )
            }
        }

        let verticalSegments = segmentRefs.filter(\.isVertical)
        let baseBridgeRadius = max(7, lineWidth * 3.6)
        var overlaysByEdgeID: [UUID: [EdgeBridgeOverlay]] = [:]

        for horizontalSegment in segmentRefs where horizontalSegment.isHorizontal {
            let crossingCenters = verticalSegments.compactMap { verticalSegment -> CGPoint? in
                guard verticalSegment.edgeID != horizontalSegment.edgeID else { return nil }
                return segmentIntersection(horizontal: horizontalSegment, vertical: verticalSegment)
            }
            .sorted { lhs, rhs in
                if abs(lhs.x - rhs.x) > 0.5 {
                    return lhs.x < rhs.x
                }
                return lhs.y < rhs.y
            }

            guard !crossingCenters.isEmpty else { continue }

            let mergedCenters = mergedBridgeCenters(crossingCenters, minimumSpacing: baseBridgeRadius * 2.4)
            let directionIsForward = horizontalSegment.start.x <= horizontalSegment.end.x
            let segmentMinX = min(horizontalSegment.start.x, horizontalSegment.end.x)
            let segmentMaxX = max(horizontalSegment.start.x, horizontalSegment.end.x)

            for center in mergedCenters {
                let availableRadius = min(
                    baseBridgeRadius,
                    center.x - segmentMinX - 4,
                    segmentMaxX - center.x - 4
                )
                guard availableRadius >= 5 else { continue }

                let leftPoint = CGPoint(x: center.x - availableRadius, y: center.y)
                let rightPoint = CGPoint(x: center.x + availableRadius, y: center.y)
                let arcFrom = directionIsForward ? leftPoint : rightPoint
                let arcTo = directionIsForward ? rightPoint : leftPoint

                overlaysByEdgeID[horizontalSegment.edgeID, default: []].append(
                    EdgeBridgeOverlay(
                        id: "\(horizontalSegment.edgeID.uuidString)-\(Int((center.x * 10).rounded()))-\(Int((center.y * 10).rounded()))",
                        eraseFrom: leftPoint,
                        eraseTo: rightPoint,
                        arcFrom: arcFrom,
                        control: CGPoint(x: center.x, y: center.y - availableRadius * 1.7),
                        arcTo: arcTo
                    )
                )
            }
        }

        return layouts.map { layout in
            EdgeLayout(
                edge: layout.edge,
                points: layout.points,
                strokePolylines: layout.strokePolylines,
                isSelected: layout.isSelected,
                isRecentlyCreated: layout.isRecentlyCreated,
                baseColor: layout.baseColor,
                displayText: layout.displayText,
                showsForwardArrow: layout.showsForwardArrow,
                labelPosition: layout.labelPosition,
                bridgeOverlays: overlaysByEdgeID[layout.edge.id] ?? []
            )
        }
    }

    private func uniqueStrokePolylines(from points: [CGPoint], seenSegments: inout Set<String>) -> [[CGPoint]] {
        guard points.count >= 2 else { return [] }

        var polylines: [[CGPoint]] = []
        var currentPolyline: [CGPoint] = []

        for (from, to) in zip(points, points.dropFirst()) {
            let segmentKey = normalizedUndirectedSegmentKey(from: from, to: to)
            if seenSegments.contains(segmentKey) {
                if currentPolyline.count >= 2 {
                    polylines.append(currentPolyline)
                }
                currentPolyline = []
                continue
            }

            seenSegments.insert(segmentKey)
            if currentPolyline.isEmpty {
                currentPolyline = [from, to]
            } else if let lastPoint = currentPolyline.last,
                      abs(lastPoint.x - from.x) < 0.5,
                      abs(lastPoint.y - from.y) < 0.5 {
                currentPolyline.append(to)
            } else {
                if currentPolyline.count >= 2 {
                    polylines.append(currentPolyline)
                }
                currentPolyline = [from, to]
            }
        }

        if currentPolyline.count >= 2 {
            polylines.append(currentPolyline)
        }

        return polylines
    }

    private func strokeSegments(
        in polyline: [CGPoint],
        edgeID: UUID
    ) -> [StrokeSegmentReference] {
        zip(polyline, polyline.dropFirst()).compactMap { segment in
            let start = segment.0
            let end = segment.1
            let isHorizontal = abs(start.y - end.y) < 0.5
            let isVertical = abs(start.x - end.x) < 0.5
            guard isHorizontal || isVertical else { return nil }

            return StrokeSegmentReference(
                edgeID: edgeID,
                start: start,
                end: end
            )
        }
    }

    private func segmentIntersection(
        horizontal: StrokeSegmentReference,
        vertical: StrokeSegmentReference
    ) -> CGPoint? {
        let x = vertical.start.x
        let y = horizontal.start.y
        let horizontalMinX = min(horizontal.start.x, horizontal.end.x) + 0.5
        let horizontalMaxX = max(horizontal.start.x, horizontal.end.x) - 0.5
        let verticalMinY = min(vertical.start.y, vertical.end.y) + 0.5
        let verticalMaxY = max(vertical.start.y, vertical.end.y) - 0.5

        guard x > horizontalMinX,
              x < horizontalMaxX,
              y > verticalMinY,
              y < verticalMaxY else {
            return nil
        }

        return CGPoint(x: x, y: y)
    }

    private func mergedBridgeCenters(_ points: [CGPoint], minimumSpacing: CGFloat) -> [CGPoint] {
        var result: [CGPoint] = []

        for point in points {
            if let last = result.last, abs(last.x - point.x) < minimumSpacing {
                continue
            }
            result.append(point)
        }

        return result
    }

    private func cycleSharedSegmentSelection(_ edges: [WorkflowEdge]) {
        guard !edges.isEmpty else { return }

        let nextEdge: WorkflowEdge
        if let selectedEdgeID,
           let selectedIndex = edges.firstIndex(where: { $0.id == selectedEdgeID }) {
            nextEdge = edges[(selectedIndex + 1) % edges.count]
        } else {
            nextEdge = edges[0]
        }

        selectedEdgeID = nextEdge.id
        onEdgeSelected?(nextEdge)
    }

    private func updateHoveredSharedSegment(_ nextID: String?) {
        guard hoveredSharedSegmentID != nextID else { return }
        withAnimation(.easeOut(duration: 0.12)) {
            hoveredSharedSegmentID = nextID
        }
    }

    private func sharedSegmentHitID(at location: CGPoint, in layouts: [WorkflowCanvasSharedSegmentHitLayout]) -> String? {
        let hoverThreshold = max(10, lineWidth + 6)
        let bestMatch = layouts.compactMap { layout -> (id: String, distance: CGFloat)? in
            guard layout.points.count >= 2 else { return nil }
            let distance = distanceFromPoint(
                location,
                toSegmentFrom: layout.points[0],
                to: layout.points[layout.points.count - 1]
            )
            guard distance <= hoverThreshold else { return nil }
            return (layout.id, distance)
        }
        .min { lhs, rhs in
            if abs(lhs.distance - rhs.distance) > 0.5 {
                return lhs.distance < rhs.distance
            }
            return lhs.id < rhs.id
        }

        return bestMatch?.id
    }

    private func distanceFromPoint(_ point: CGPoint, toSegmentFrom start: CGPoint, to end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0.5 else {
            return point.distance(to: start)
        }

        let projection = ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared
        let clampedProjection = min(1, max(0, projection))
        let projectedPoint = CGPoint(
            x: start.x + dx * clampedProjection,
            y: start.y + dy * clampedProjection
        )
        return point.distance(to: projectedPoint)
    }

    private func resolvedLabelLayouts(_ layouts: [EdgeLayout], blockedRects: [CGRect]) -> [EdgeLayout] {
        var occupiedRects: [CGRect] = []
        let expandedBlockedRects = blockedRects.map { $0.insetBy(dx: -12, dy: -10) }
        let prioritizedLayouts = layouts.enumerated().sorted { lhs, rhs in
            let lhsPriority = labelPriority(for: lhs.element)
            let rhsPriority = labelPriority(for: rhs.element)
            if lhsPriority != rhsPriority {
                return lhsPriority > rhsPriority
            }
            return lhs.offset < rhs.offset
        }

        var resolvedPositionsByEdgeID: [UUID: CGPoint] = [:]
        for (_, layout) in prioritizedLayouts {
            guard !layout.displayText.isEmpty else { continue }

            let labelSize = estimatedLabelSize(for: layout)
            let candidates = labelCandidates(for: layout)
            let chosenPoint = chooseLabelCandidate(
                from: candidates,
                basePoint: labelPosition(for: layout),
                size: labelSize,
                occupiedRects: occupiedRects,
                blockedRects: expandedBlockedRects
            )

            if let chosenPoint {
                resolvedPositionsByEdgeID[layout.edge.id] = chosenPoint
                occupiedRects.append(labelRect(center: chosenPoint, size: labelSize))
            }
        }

        return layouts.map { layout in
            EdgeLayout(
                edge: layout.edge,
                points: layout.points,
                strokePolylines: layout.strokePolylines,
                isSelected: layout.isSelected,
                isRecentlyCreated: layout.isRecentlyCreated,
                baseColor: layout.baseColor,
                displayText: layout.displayText,
                showsForwardArrow: layout.showsForwardArrow,
                labelPosition: resolvedPositionsByEdgeID[layout.edge.id],
                bridgeOverlays: layout.bridgeOverlays
            )
        }
    }

    private func chooseLabelCandidate(
        from candidates: [CGPoint],
        basePoint: CGPoint,
        size: CGSize,
        occupiedRects: [CGRect],
        blockedRects: [CGRect]
    ) -> CGPoint? {
        struct RankedCandidate {
            let point: CGPoint
            let collisionCount: Int
            let overlapArea: CGFloat
            let blockedPenalty: CGFloat
            let distanceFromBase: CGFloat
        }

        let ranked = candidates.map { candidate -> RankedCandidate in
            let rect = labelRect(center: candidate, size: size)
            let expandedRect = rect.insetBy(dx: -8, dy: -6)

            let occupiedIntersections = occupiedRects.filter { $0.intersects(expandedRect) }
            let blockedIntersections = blockedRects.filter { $0.intersects(expandedRect) }
            let overlapArea = occupiedIntersections.reduce(CGFloat(0)) { partial, other in
                partial + expandedRect.intersection(other).area
            }
            let blockedPenalty = blockedIntersections.reduce(CGFloat(0)) { partial, other in
                partial + expandedRect.intersection(other).area
            }

            return RankedCandidate(
                point: candidate,
                collisionCount: occupiedIntersections.count + blockedIntersections.count,
                overlapArea: overlapArea,
                blockedPenalty: blockedPenalty,
                distanceFromBase: candidate.distance(to: basePoint)
            )
        }

        if let perfect = ranked.first(where: { $0.collisionCount == 0 }) {
            return perfect.point
        }

        return ranked.min { lhs, rhs in
            if lhs.collisionCount != rhs.collisionCount {
                return lhs.collisionCount < rhs.collisionCount
            }
            if abs(lhs.blockedPenalty - rhs.blockedPenalty) > 0.5 {
                return lhs.blockedPenalty < rhs.blockedPenalty
            }
            if abs(lhs.distanceFromBase - rhs.distanceFromBase) > 0.5 {
                return lhs.distanceFromBase < rhs.distanceFromBase
            }
            return lhs.overlapArea < rhs.overlapArea
        }?.point
    }

    private func labelPriority(for layout: EdgeLayout) -> CGFloat {
        var priority = CGFloat(layout.displayText.count)
        if layout.isSelected {
            priority += 1000
        }
        if layout.edge.requiresApproval {
            priority += 80
        }
        priority += CGFloat(layout.points.count) * 4
        return priority
    }

    private func estimatedLabelSize(for layout: EdgeLayout) -> CGSize {
        let fontSize = 10 * textScale
        let iconWidth = layout.edge.requiresApproval ? 12 * textScale : 0
        let textWidth = CGFloat(layout.displayText.count) * fontSize * 0.62
        let width = textWidth + iconWidth + 20
        let height = max(20, 18 * textScale)
        return CGSize(width: width, height: height)
    }

    private func labelRect(center: CGPoint, size: CGSize) -> CGRect {
        CGRect(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    private func labelCandidates(for layout: EdgeLayout) -> [CGPoint] {
        let basePoint = labelPosition(for: layout)
        var candidates: [CGPoint] = [basePoint]
        let offsets = [
            CGSize(width: 0, height: -12),
            CGSize(width: 0, height: 12),
            CGSize(width: -14, height: 0),
            CGSize(width: 14, height: 0),
            CGSize(width: 0, height: -20),
            CGSize(width: 0, height: 20),
            CGSize(width: -24, height: 0),
            CGSize(width: 24, height: 0),
            CGSize(width: -18, height: -18),
            CGSize(width: 18, height: -18),
            CGSize(width: -18, height: 18),
            CGSize(width: 18, height: 18)
        ]

        for offset in offsets {
            candidates.append(
                CGPoint(
                    x: basePoint.x + offset.width,
                    y: basePoint.y + offset.height
                )
            )
        }
        return candidates
    }

    private func normalizedSegmentKey(from start: CGPoint, to end: CGPoint) -> String {
        "\(Int((start.x * 10).rounded())):\(Int((start.y * 10).rounded()))->\(Int((end.x * 10).rounded())):\(Int((end.y * 10).rounded()))"
    }

    private func normalizedUndirectedSegmentKey(from start: CGPoint, to end: CGPoint) -> String {
        let startKey = "\(Int((start.x * 10).rounded())):\(Int((start.y * 10).rounded()))"
        let endKey = "\(Int((end.x * 10).rounded())):\(Int((end.y * 10).rounded()))"
        return startKey <= endKey ? "\(startKey)|\(endKey)" : "\(endKey)|\(startKey)"
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
        return edge.requiresApproval ? approvalText : ""
    }

    private func edgeBaseColor(_ edge: WorkflowEdge) -> Color {
        if let customColor = CanvasStylePalette.color(from: edge.displayColorHex) {
            return customColor
        }
        if edge.requiresApproval {
            return .orange
        }
        return lineColor
    }

    private var approvalText: String {
        switch localizationManager.currentLanguage {
        case .english:
            return "Requires approval"
        case .traditionalChinese:
            return "需審批"
        case .simplifiedChinese:
            return "需审批"
        }
    }

    private func labelPosition(for layout: EdgeLayout) -> CGPoint {
        let points = layout.points
        guard points.count >= 2 else {
            return points.first ?? .zero
        }

        struct Candidate {
            let point: CGPoint
            let score: CGFloat
        }

        let hashedOffsetSeed = CGFloat(abs(layout.edge.id.uuidString.hashValue % 2) == 0 ? 1 : -1)
        let centerIndex = CGFloat(max(points.count - 2, 1)) * 0.5

        let candidates: [Candidate] = zip(points.indices, zip(points, points.dropFirst())).compactMap { index, segment in
            let from = segment.0
            let to = segment.1
            let length = hypot(to.x - from.x, to.y - from.y)
            guard length >= 36 else { return nil }

            let midpoint = CGPoint(
                x: (from.x + to.x) * 0.5,
                y: (from.y + to.y) * 0.5
            )

            let isVertical = abs(from.x - to.x) < 0.5
            let baseOffset: CGFloat = 14
            let offsetPoint = isVertical
                ? CGPoint(x: midpoint.x + baseOffset * hashedOffsetSeed, y: midpoint.y)
                : CGPoint(x: midpoint.x, y: midpoint.y - baseOffset * hashedOffsetSeed)

            var score = length
            score -= abs(CGFloat(index) - centerIndex) * 8

            if index == points.count - 2 {
                score -= 28
            }
            if index == 0 {
                score -= 12
            }
            if isVertical {
                score += 6
            }

            return Candidate(point: offsetPoint, score: score)
        }

        if let bestCandidate = candidates.max(by: { $0.score < $1.score }) {
            return bestCandidate.point
        }

        return midPoint(for: points)
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

    private func normalizedCoordinate(_ value: CGFloat) -> Int {
        Int((Double(value) * 10).rounded())
    }

    private func rectSignature(_ rect: CGRect) -> String {
        [
            normalizedCoordinate(rect.origin.x),
            normalizedCoordinate(rect.origin.y),
            normalizedCoordinate(rect.size.width),
            normalizedCoordinate(rect.size.height)
        ]
        .map(String.init)
        .joined(separator: ":")
    }
}

private struct EdgeLayout {
    let edge: WorkflowEdge
    let points: [CGPoint]
    let strokePolylines: [[CGPoint]]
    let isSelected: Bool
    let isRecentlyCreated: Bool
    let baseColor: Color
    let displayText: String
    let showsForwardArrow: Bool
    let labelPosition: CGPoint?
    let bridgeOverlays: [EdgeBridgeOverlay]
}

private struct ConnectionRenderData {
    let edgeLayouts: [EdgeLayout]
    let sharedHitLayouts: [WorkflowCanvasSharedSegmentHitLayout]
}

private final class ConnectionEdgeRenderCache {
    private var lastSignature: Int?
    private var cachedEdgeLayouts: [EdgeLayout] = []

    func resolve(signature: Int, producer: () -> [EdgeLayout]) -> [EdgeLayout] {
        if lastSignature == signature {
            return cachedEdgeLayouts
        }

        let edgeLayouts = producer()
        lastSignature = signature
        cachedEdgeLayouts = edgeLayouts
        return edgeLayouts
    }
}

private struct StrokeSegmentReference {
    let edgeID: UUID
    let start: CGPoint
    let end: CGPoint

    var isHorizontal: Bool {
        abs(start.y - end.y) < 0.5
    }

    var isVertical: Bool {
        abs(start.x - end.x) < 0.5
    }
}

private struct EdgeBridgeOverlay: Identifiable {
    let id: String
    let eraseFrom: CGPoint
    let eraseTo: CGPoint
    let arcFrom: CGPoint
    let control: CGPoint
    let arcTo: CGPoint
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

struct OrthogonalConnectionGroupShape: Shape {
    let polylines: [[CGPoint]]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for polyline in polylines {
            guard let first = polyline.first else { continue }
            path.move(to: first)
            for point in polyline.dropFirst() {
                path.addLine(to: point)
            }
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

struct BridgeMaskShape: Shape {
    let from: CGPoint
    let to: CGPoint

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: from)
        path.addLine(to: to)
        return path
    }
}

struct BridgeArcShape: Shape {
    let from: CGPoint
    let control: CGPoint
    let to: CGPoint

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: from)
        path.addQuadCurve(to: to, control: control)
        return path
    }
}

struct EdgeLabelView: View {
    let text: String
    let requiresApproval: Bool
    let textScale: CGFloat
    let textColor: Color
    let accentColor: Color

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
                .stroke(requiresApproval ? Color.orange : accentColor.opacity(0.45), lineWidth: 1)
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
