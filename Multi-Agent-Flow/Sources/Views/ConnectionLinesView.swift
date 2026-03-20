//
//  ConnectionLinesView.swift
//  Multi-Agent-Flow
//

import SwiftUI
import Foundation

struct ConnectionLinesView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var localizationManager = LocalizationManager.shared
    let currentWorkflow: Workflow?
    @Binding var scale: CGFloat
    let offset: CGSize
    let lineColor: Color
    let lineWidth: CGFloat
    let textScale: CGFloat
    let textColor: Color
    @Binding var selectedEdgeID: UUID?
    @State private var hoveredSharedSegmentID: String?
    var onEdgeSelected: ((WorkflowEdge) -> Void)?
    var onEdgeSecondarySelected: ((WorkflowEdge) -> Void)?

    init(
        currentWorkflow: Workflow?,
        scale: Binding<CGFloat>,
        offset: CGSize,
        lineColor: Color = .blue,
        lineWidth: CGFloat = 2,
        textScale: CGFloat = 1,
        textColor: Color = .black,
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
            let renderData = buildRenderData(in: geo)
            ZStack {
                ForEach(renderData.edgeLayouts, id: \.edge.id) { layout in
                    let points = layout.points

                    if !layout.strokePolylines.isEmpty {
                        OrthogonalConnectionGroupShape(polylines: layout.strokePolylines)
                            .stroke(
                                layout.isSelected ? Color.accentColor : layout.baseColor.opacity(0.78),
                                style: StrokeStyle(
                                    lineWidth: max(1, lineWidth + (layout.isSelected ? 1 : 0)),
                                    lineCap: .round,
                                    lineJoin: .round,
                                    dash: layout.edge.requiresApproval ? [8, 4] : []
                                )
                            )
                    }

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
                                    layout.isSelected ? Color.accentColor : layout.baseColor.opacity(0.9),
                                    style: StrokeStyle(lineWidth: max(1, lineWidth), lineCap: .round)
                                )
                        }
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

                        SharedSegmentBadgeView(
                            previewItems: sharedHit.previewItems,
                            selectedEdgeID: selectedEdgeID,
                            textScale: textScale
                        )
                        .position(sharedHit.badgePosition)
                        .allowsHitTesting(false)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }

                    ConnectionHitShape(points: sharedHit.points, hitWidth: max(22, lineWidth + 16))
                        .fill(Color.clear)
                        .contentShape(ConnectionHitShape(points: sharedHit.points, hitWidth: max(22, lineWidth + 16)))
                        .onHover { isHovering in
                            withAnimation(.easeOut(duration: 0.16)) {
                                hoveredSharedSegmentID = isHovering ? sharedHit.id : (hoveredSharedSegmentID == sharedHit.id ? nil : hoveredSharedSegmentID)
                            }
                        }
                        .onTapGesture {
                            cycleSharedSegmentSelection(sharedHit.edges)
                        }
                }
            }
        }
    }

    private func buildRenderData(in geometry: GeometryProxy) -> ConnectionRenderData {
        let edgeLayouts = buildEdgeLayouts(in: geometry)
        let nodesByID = Dictionary(
            uniqueKeysWithValues: (currentWorkflow?.nodes ?? []).map { ($0.id, $0) }
        )
        return ConnectionRenderData(
            edgeLayouts: edgeLayouts,
            sharedHitLayouts: buildSharedHitLayouts(
                from: edgeLayouts,
                nodesByID: nodesByID
            )
        )
    }

    private func buildEdgeLayouts(in geometry: GeometryProxy) -> [EdgeLayout] {
        guard let workflow = currentWorkflow else { return [] }
        let nodesByID: [UUID: WorkflowNode] = Dictionary(uniqueKeysWithValues: workflow.nodes.map { ($0.id, $0) })
        let nodeFramesByID: [UUID: CGRect] = Dictionary(
            uniqueKeysWithValues: workflow.nodes.map { node in
                (node.id, nodeFrame(for: node, geometry: geometry))
            }
        )
        let candidates = workflow.edges.compactMap { edge -> RoutedEdgeCandidate? in
            guard let fromNode = nodesByID[edge.fromNodeID],
                  let toNode = nodesByID[edge.toNodeID],
                  let fromFrame = nodeFramesByID[fromNode.id],
                  let toFrame = nodeFramesByID[toNode.id] else {
                return nil
            }

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
        let faninInfoByBundleKey = faninLayoutMap(for: candidates)
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
                        return nodeFramesByID[node.id]
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
                        targetAnchorX: fanoutInfo.targetAnchorX(
                            for: candidate.edge.toNodeID,
                            default: candidate.toFrame.midX
                        ),
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
                } else if let faninInfo = faninInfoByBundleKey[candidate.bundleKey],
                          let mergedPath = WorkflowEdgeRoutePlanner.faninRoute(
                            from: candidate.fromFrame,
                            to: candidate.toFrame,
                            incomingSide: faninInfo.incomingSide,
                            mergeAxisValue: faninInfo.mergeAxisValue,
                            trunkAxisValue: faninInfo.trunkAxisValue,
                            avoiding: obstacles
                          ) {
                    path = mergedPath
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
                        strokePolylines: [path],
                        isSelected: selectedEdgeID == candidate.edge.id,
                        baseColor: edgeBaseColor(candidate.edge),
                        displayText: edgeDisplayText(candidate.edge),
                        showsForwardArrow: true,
                        labelPosition: nil
                    )
                )
            }
        }

        return resolvedLabelLayouts(
            resolvedSharedStrokeLayouts(deduplicatedArrowLayouts(layouts)),
            blockedRects: Array(nodeFramesByID.values)
        )
    }

    private func buildSharedHitLayouts(
        from layouts: [EdgeLayout],
        nodesByID: [UUID: WorkflowNode]
    ) -> [SharedSegmentHitLayout] {
        let groupedSegments = Dictionary(grouping: layouts.flatMap { layout -> [SharedSegmentCandidate] in
            zip(layout.points, layout.points.dropFirst()).map { from, to in
                SharedSegmentCandidate(
                    segmentKey: normalizedUndirectedSegmentKey(from: from, to: to),
                    points: [from, to],
                    edge: layout.edge
                )
            }
        }, by: \.segmentKey)

        return groupedSegments.compactMap { segmentKey, candidates in
            let uniqueEdges = uniqueEdgesPreservingOrder(candidates.map(\.edge))
            guard uniqueEdges.count >= 2,
                  let points = candidates.first?.points else { return nil }

            return SharedSegmentHitLayout(
                id: segmentKey,
                points: points,
                edges: uniqueEdges,
                badgePosition: sharedSegmentBadgePosition(for: points),
                previewItems: sharedSegmentPreviewItems(
                    for: uniqueEdges,
                    nodesByID: nodesByID
                )
            )
        }
        .sorted { lhs, rhs in
            let lhsPoint = lhs.points.first ?? .zero
            let rhsPoint = rhs.points.first ?? .zero
            if abs(lhsPoint.y - rhsPoint.y) > 0.5 {
                return lhsPoint.y < rhsPoint.y
            }
            return lhsPoint.x < rhsPoint.x
        }
    }

    private func fanoutLayoutMap(
        for candidates: [RoutedEdgeCandidate],
        in geometry: GeometryProxy,
        workflow: Workflow
    ) -> [UUID: FanoutLayoutInfo] {
        let groupedBySource = Dictionary(grouping: candidates, by: { $0.edge.fromNodeID })
        var layoutBySource: [UUID: FanoutLayoutInfo] = [:]

        for (sourceID, group) in groupedBySource {
            guard group.count >= 2,
                  let sourceFrame = group.first?.fromFrame else { continue }

            let downwardTargets = group.filter { candidate in
                candidate.toFrame.center.y > sourceFrame.center.y + 18
            }
            guard downwardTargets.count >= 2 else { continue }

            let sourceBottom = sourceFrame.maxY + 10
            let targetTop = downwardTargets.map { $0.toFrame.minY }.min() ?? .greatestFiniteMagnitude
            let centeredTarget = closestTarget(to: sourceFrame.midX, in: downwardTargets)
            let verticalGap = targetTop - sourceBottom
            guard verticalGap >= 42 else { continue }

            let preferredTurnY = sourceBottom + max(28, min(76, verticalGap * 0.4))
            let turnY = min(preferredTurnY, targetTop - 18)
            guard turnY > sourceBottom + 8, turnY < targetTop - 8 else { continue }

            let sortedTargets = downwardTargets.sorted { lhs, rhs in
                if abs(lhs.toFrame.midX - rhs.toFrame.midX) > 0.5 {
                    return lhs.toFrame.midX < rhs.toFrame.midX
                }
                return lhs.toFrame.midY < rhs.toFrame.midY
            }

            let fanoutSpacingValue = WorkflowEdgeRoutePlanner.fanoutSpacing(
                for: sourceFrame,
                targetCount: sortedTargets.count
            )
            let slotOffsets = laneOffsets(for: sortedTargets.count, spacing: fanoutSpacingValue)
            let targetAnchorXByTargetID: [UUID: CGFloat] = Dictionary(
                uniqueKeysWithValues: zip(sortedTargets, slotOffsets).map { candidate, slotOffset in
                    let preferredAnchorX = sourceFrame.midX + slotOffset
                    let anchorX = WorkflowEdgeRoutePlanner.clampedVerticalEntryX(
                        for: candidate.toFrame,
                        preferredX: preferredAnchorX
                    )
                    return (candidate.edge.toNodeID, anchorX)
                }
            )

            layoutBySource[sourceID] = FanoutLayoutInfo(
                turnY: turnY,
                centerTargetID: centeredTarget?.edge.toNodeID,
                targetAnchorXByTargetID: targetAnchorXByTargetID
            )
        }

        return layoutBySource
    }

    private func faninLayoutMap(for candidates: [RoutedEdgeCandidate]) -> [RoutedEdgeBundleKey: FaninLayoutInfo] {
        let groupedByBundleKey = Dictionary(grouping: candidates, by: \.bundleKey)
        var layoutByBundleKey: [RoutedEdgeBundleKey: FaninLayoutInfo] = [:]

        for (bundleKey, group) in groupedByBundleKey {
            guard group.count >= 2,
                  let targetFrame = group.first?.toFrame else { continue }

            let info: FaninLayoutInfo?
            switch bundleKey.incomingSide {
            case .bottom:
                let sources = group.filter { candidate in
                    candidate.fromFrame.center.y > targetFrame.center.y + 18
                }
                guard sources.count >= 2 else { continue }

                let targetBottom = targetFrame.maxY + 10
                let nearestSourceTop = sources.map { $0.fromFrame.minY }.min() ?? .greatestFiniteMagnitude
                let verticalGap = nearestSourceTop - targetBottom
                guard verticalGap >= 34 else { continue }

                let preferredMergeY = targetBottom + compactMergeOffset(for: verticalGap)
                let mergeY = min(preferredMergeY, nearestSourceTop - 18)
                guard mergeY > targetBottom + 8, mergeY < nearestSourceTop - 8 else { continue }

                info = FaninLayoutInfo(
                    incomingSide: .bottom,
                    mergeAxisValue: mergeY,
                    trunkAxisValue: targetFrame.midX
                )

            case .top:
                let sources = group.filter { candidate in
                    candidate.fromFrame.center.y < targetFrame.center.y - 18
                }
                guard sources.count >= 2 else { continue }

                let targetTop = targetFrame.minY - 10
                let nearestSourceBottom = sources.map { $0.fromFrame.maxY }.max() ?? -.greatestFiniteMagnitude
                let verticalGap = targetTop - nearestSourceBottom
                guard verticalGap >= 34 else { continue }

                let preferredMergeY = targetTop - compactMergeOffset(for: verticalGap)
                let mergeY = max(preferredMergeY, nearestSourceBottom + 18)
                guard mergeY < targetTop - 8, mergeY > nearestSourceBottom + 8 else { continue }

                info = FaninLayoutInfo(
                    incomingSide: .top,
                    mergeAxisValue: mergeY,
                    trunkAxisValue: targetFrame.midX
                )

            case .left:
                let sources = group.filter { candidate in
                    candidate.fromFrame.center.x < targetFrame.center.x - 18
                }
                guard sources.count >= 2 else { continue }

                let targetLeft = targetFrame.minX - 10
                let nearestSourceRight = sources.map { $0.fromFrame.maxX }.max() ?? -.greatestFiniteMagnitude
                let horizontalGap = targetLeft - nearestSourceRight
                guard horizontalGap >= 34 else { continue }

                let preferredMergeX = targetLeft - compactMergeOffset(for: horizontalGap)
                let mergeX = max(preferredMergeX, nearestSourceRight + 18)
                guard mergeX < targetLeft - 8, mergeX > nearestSourceRight + 8 else { continue }

                info = FaninLayoutInfo(
                    incomingSide: .left,
                    mergeAxisValue: mergeX,
                    trunkAxisValue: targetFrame.midY
                )

            case .right:
                let sources = group.filter { candidate in
                    candidate.fromFrame.center.x > targetFrame.center.x + 18
                }
                guard sources.count >= 2 else { continue }

                let targetRight = targetFrame.maxX + 10
                let nearestSourceLeft = sources.map { $0.fromFrame.minX }.min() ?? .greatestFiniteMagnitude
                let horizontalGap = nearestSourceLeft - targetRight
                guard horizontalGap >= 34 else { continue }

                let preferredMergeX = targetRight + compactMergeOffset(for: horizontalGap)
                let mergeX = min(preferredMergeX, nearestSourceLeft - 18)
                guard mergeX > targetRight + 8, mergeX < nearestSourceLeft - 8 else { continue }

                info = FaninLayoutInfo(
                    incomingSide: .right,
                    mergeAxisValue: mergeX,
                    trunkAxisValue: targetFrame.midY
                )
            }

            if let info {
                layoutByBundleKey[bundleKey] = info
            }
        }

        return layoutByBundleKey
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
                baseColor: layout.baseColor,
                displayText: layout.displayText,
                showsForwardArrow: shouldShowArrow,
                labelPosition: layout.labelPosition
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
                baseColor: layout.baseColor,
                displayText: layout.displayText,
                showsForwardArrow: layout.showsForwardArrow,
                labelPosition: layout.labelPosition
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

    private func sharedSegmentPreviewItems(
        for edges: [WorkflowEdge],
        nodesByID: [UUID: WorkflowNode]
    ) -> [SharedSegmentPreviewItem] {
        edges.map { edge in
            let sourceName = nodeDisplayName(for: edge.fromNodeID, nodesByID: nodesByID)
            let targetName = nodeDisplayName(for: edge.toNodeID, nodesByID: nodesByID)
            let detail = edgeDisplayText(edge)
            let summary = detail.isEmpty
                ? "\(sourceName) -> \(targetName)"
                : "\(sourceName) -> \(targetName)  \(detail)"

            return SharedSegmentPreviewItem(
                id: edge.id,
                text: summary,
                requiresApproval: edge.requiresApproval
            )
        }
    }

    private func sharedSegmentBadgePosition(for points: [CGPoint]) -> CGPoint {
        guard let first = points.first,
              let last = points.last else { return .zero }

        let midpoint = CGPoint(
            x: (first.x + last.x) * 0.5,
            y: (first.y + last.y) * 0.5
        )
        let isVertical = abs(first.x - last.x) < 0.5

        if isVertical {
            return CGPoint(x: midpoint.x + 26, y: midpoint.y)
        }
        return CGPoint(x: midpoint.x, y: midpoint.y - 24)
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
                baseColor: layout.baseColor,
                displayText: layout.displayText,
                showsForwardArrow: layout.showsForwardArrow,
                labelPosition: resolvedPositionsByEdgeID[layout.edge.id]
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

    private func uniqueEdgesPreservingOrder(_ edges: [WorkflowEdge]) -> [WorkflowEdge] {
        var seen = Set<UUID>()
        var result: [WorkflowEdge] = []
        for edge in edges {
            guard seen.insert(edge.id).inserted else { continue }
            result.append(edge)
        }
        return result
    }

    private func compactMergeOffset(for gap: CGFloat) -> CGFloat {
        max(18, min(48, gap * 0.28))
    }

    private func nodeDisplayName(for nodeID: UUID, nodesByID: [UUID: WorkflowNode]) -> String {
        guard let node = nodesByID[nodeID] else { return "Unknown" }

        if let agentID = node.agentID,
           let agent = appState.currentProject?.agents.first(where: { $0.id == agentID }) {
            let name = agent.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty {
                return name
            }
        }

        let title = node.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty {
            return title
        }

        switch node.type {
        case .start:
            return "Start"
        case .agent:
            return "Agent"
        }
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
}

private struct EdgeLayout {
    let edge: WorkflowEdge
    let points: [CGPoint]
    let strokePolylines: [[CGPoint]]
    let isSelected: Bool
    let baseColor: Color
    let displayText: String
    let showsForwardArrow: Bool
    let labelPosition: CGPoint?
}

private struct ConnectionRenderData {
    let edgeLayouts: [EdgeLayout]
    let sharedHitLayouts: [SharedSegmentHitLayout]
}

private struct SharedSegmentCandidate {
    let segmentKey: String
    let points: [CGPoint]
    let edge: WorkflowEdge
}

private struct SharedSegmentHitLayout {
    let id: String
    let points: [CGPoint]
    let edges: [WorkflowEdge]
    let badgePosition: CGPoint
    let previewItems: [SharedSegmentPreviewItem]
}

private struct SharedSegmentPreviewItem: Identifiable {
    let id: UUID
    let text: String
    let requiresApproval: Bool
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
        targetAnchorX: CGFloat,
        avoiding obstacles: [CGRect]
    ) -> [CGPoint]? {
        let start = CGPoint(x: sourceFrame.midX, y: sourceFrame.maxY + anchorClearance)
        let end = CGPoint(
            x: clampedVerticalEntryX(for: targetFrame, preferredX: targetAnchorX),
            y: targetFrame.minY - anchorClearance
        )
        guard turnY > start.y + 4, turnY < end.y - 4 else { return nil }

        let path = simplify([
            start,
            CGPoint(x: sourceFrame.midX, y: turnY),
            CGPoint(x: end.x, y: turnY),
            end
        ])

        let blockedRects = obstacles.map { $0.insetBy(dx: -obstaclePadding, dy: -obstaclePadding) }
        return isClear(path, blockedRects: blockedRects) ? path : nil
    }

    static func faninRoute(
        from sourceFrame: CGRect,
        to targetFrame: CGRect,
        incomingSide: EdgeAnchorSide,
        mergeAxisValue: CGFloat,
        trunkAxisValue: CGFloat,
        avoiding obstacles: [CGRect]
    ) -> [CGPoint]? {
        let start: CGPoint
        let end: CGPoint
        let path: [CGPoint]

        switch incomingSide {
        case .bottom:
            start = CGPoint(x: sourceFrame.midX, y: sourceFrame.minY - anchorClearance)
            end = CGPoint(x: trunkAxisValue, y: targetFrame.maxY + anchorClearance)
            guard mergeAxisValue > end.y + 4, mergeAxisValue < start.y - 4 else { return nil }
            path = simplify([
                start,
                CGPoint(x: start.x, y: mergeAxisValue),
                CGPoint(x: trunkAxisValue, y: mergeAxisValue),
                end
            ])

        case .top:
            start = CGPoint(x: sourceFrame.midX, y: sourceFrame.maxY + anchorClearance)
            end = CGPoint(x: trunkAxisValue, y: targetFrame.minY - anchorClearance)
            guard mergeAxisValue > start.y + 4, mergeAxisValue < end.y - 4 else { return nil }
            path = simplify([
                start,
                CGPoint(x: start.x, y: mergeAxisValue),
                CGPoint(x: trunkAxisValue, y: mergeAxisValue),
                end
            ])

        case .left:
            start = CGPoint(x: sourceFrame.maxX + anchorClearance, y: sourceFrame.midY)
            end = CGPoint(x: targetFrame.minX - anchorClearance, y: trunkAxisValue)
            guard mergeAxisValue > start.x + 4, mergeAxisValue < end.x - 4 else { return nil }
            path = simplify([
                start,
                CGPoint(x: mergeAxisValue, y: start.y),
                CGPoint(x: mergeAxisValue, y: trunkAxisValue),
                end
            ])

        case .right:
            start = CGPoint(x: sourceFrame.minX - anchorClearance, y: sourceFrame.midY)
            end = CGPoint(x: targetFrame.maxX + anchorClearance, y: trunkAxisValue)
            guard mergeAxisValue > end.x + 4, mergeAxisValue < start.x - 4 else { return nil }
            path = simplify([
                start,
                CGPoint(x: mergeAxisValue, y: start.y),
                CGPoint(x: mergeAxisValue, y: trunkAxisValue),
                end
            ])
        }

        let blockedRects = obstacles.map { $0.insetBy(dx: -obstaclePadding, dy: -obstaclePadding) }
        return isClear(path, blockedRects: blockedRects) ? path : nil
    }

    static func fanoutSpacing(for sourceFrame: CGRect, targetCount: Int) -> CGFloat {
        guard targetCount > 1 else { return 0 }

        let widthDriven = max(22, sourceFrame.width * 0.28)
        let countAdjusted = max(20, 40 - CGFloat(max(0, targetCount - 3)) * 3)
        return min(38, max(widthDriven, countAdjusted))
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

    static func clampedVerticalEntryX(for targetFrame: CGRect, preferredX: CGFloat) -> CGFloat {
        let inset = min(18, max(10, targetFrame.width * 0.18))
        let minX = targetFrame.minX + inset
        let maxX = targetFrame.maxX - inset
        return min(max(preferredX, minX), maxX)
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
        let center = rect.center
        let dx = point.x - center.x
        let dy = point.y - center.y
        let verticalThreshold = max(32, rect.height * 0.55)

        if dy >= verticalThreshold {
            return .bottom
        }
        if dy <= -verticalThreshold {
            return .top
        }
        if abs(dx) > abs(dy) * 1.2 {
            return dx >= 0 ? .right : .left
        }
        return dy >= 0 ? .bottom : .top
    }

    static func preferredIncomingSide(for rect: CGRect, toward point: CGPoint) -> EdgeAnchorSide {
        let center = rect.center
        let dx = point.x - center.x
        let dy = point.y - center.y
        let verticalThreshold = max(32, rect.height * 0.55)

        if dy <= -verticalThreshold {
            return .top
        }
        if dy >= verticalThreshold {
            return .bottom
        }
        if abs(dx) > abs(dy) * 1.2 {
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
    let targetAnchorXByTargetID: [UUID: CGFloat]

    func targetAnchorX(for targetID: UUID, default defaultX: CGFloat) -> CGFloat {
        targetAnchorXByTargetID[targetID] ?? defaultX
    }
}

private struct FaninLayoutInfo {
    let incomingSide: EdgeAnchorSide
    let mergeAxisValue: CGFloat
    let trunkAxisValue: CGFloat
}

enum EdgeRouteAxis {
    case horizontal
    case vertical
}

private extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }

    var area: CGFloat {
        guard !isNull, !isEmpty else { return 0 }
        return width * height
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

private struct SharedSegmentBadgeView: View {
    let previewItems: [SharedSegmentPreviewItem]
    let selectedEdgeID: UUID?
    let textScale: CGFloat

    private var sortedItems: [SharedSegmentPreviewItem] {
        previewItems.sorted { lhs, rhs in
            let lhsSelected = lhs.id == selectedEdgeID
            let rhsSelected = rhs.id == selectedEdgeID
            if lhsSelected != rhsSelected {
                return lhsSelected
            }
            return lhs.text.localizedCaseInsensitiveCompare(rhs.text) == .orderedAscending
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Merged \(previewItems.count)")
                .font(.system(size: 10 * textScale, weight: .semibold))
                .foregroundColor(.white.opacity(0.96))

            ForEach(Array(sortedItems.prefix(3))) { item in
                HStack(spacing: 6) {
                    Circle()
                        .fill(item.id == selectedEdgeID ? Color.accentColor : (item.requiresApproval ? Color.orange : Color.white.opacity(0.55)))
                        .frame(width: 5, height: 5)

                    Text(item.text)
                        .font(.system(size: 10 * textScale, weight: item.id == selectedEdgeID ? .semibold : .regular))
                        .foregroundColor(.white.opacity(item.id == selectedEdgeID ? 1 : 0.9))
                        .lineLimit(1)
                }
            }

            if previewItems.count > 3 {
                Text("+\(previewItems.count - 3) more")
                    .font(.system(size: 9 * textScale, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: 220 * textScale, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.82))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 4)
        .fixedSize()
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
