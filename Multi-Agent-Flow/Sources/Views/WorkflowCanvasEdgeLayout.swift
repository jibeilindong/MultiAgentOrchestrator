//
//  WorkflowCanvasEdgeLayout.swift
//  Multi-Agent-Flow
//

import SwiftUI
import Foundation

struct WorkflowCanvasEdgeLayout {
    let edge: WorkflowEdge
    let points: [CGPoint]

    func distance(to location: CGPoint, tolerance: CGFloat) -> CGFloat? {
        guard points.count >= 2 else { return nil }
        var bestDistance: CGFloat?

        for segment in zip(points, points.dropFirst()) {
            let segmentDistance = distance(from: location, to: segment.0, and: segment.1)
            guard segmentDistance <= tolerance else { continue }
            if bestDistance == nil || segmentDistance < bestDistance! {
                bestDistance = segmentDistance
            }
        }

        return bestDistance
    }

    private func distance(from point: CGPoint, to a: CGPoint, and b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        if abs(dx) < 0.001 && abs(dy) < 0.001 {
            return hypot(point.x - a.x, point.y - a.y)
        }

        let t = max(0, min(1, ((point.x - a.x) * dx + (point.y - a.y) * dy) / (dx * dx + dy * dy)))
        let projection = CGPoint(x: a.x + t * dx, y: a.y + t * dy)
        return hypot(point.x - projection.x, point.y - projection.y)
    }
}

struct WorkflowCanvasSharedSegmentHitLayout {
    let id: String
    let points: [CGPoint]
    let edges: [WorkflowEdge]
}

struct WorkflowCanvasPreviewLineLayout: Identifiable {
    let id: String
    let from: CGPoint
    let to: CGPoint
}

struct WorkflowCanvasResolvedEdgeData {
    let edgeLayouts: [WorkflowCanvasEdgeLayout]
    let sharedHitLayouts: [WorkflowCanvasSharedSegmentHitLayout]

    static let empty = WorkflowCanvasResolvedEdgeData(
        edgeLayouts: [],
        sharedHitLayouts: []
    )
}

final class WorkflowCanvasEdgeGeometryCache {
    private var lastTopologySignature: Int?
    private var lastLayoutSignature: Int?
    private var cachedData: WorkflowCanvasResolvedEdgeData = .empty

    func resolve(
        workflow: Workflow?,
        nodeFramesByID: [UUID: CGRect],
        transientNodeIDs: Set<UUID>
    ) -> WorkflowCanvasResolvedEdgeData {
        guard let workflow else {
            lastTopologySignature = nil
            lastLayoutSignature = nil
            cachedData = .empty
            return .empty
        }

        let topologySignature = WorkflowCanvasEdgeLayoutBuilder.topologySignature(for: workflow)
        let layoutSignature = WorkflowCanvasEdgeLayoutBuilder.layoutSignature(
            for: workflow,
            nodeFramesByID: nodeFramesByID
        )

        if lastLayoutSignature == layoutSignature {
            return cachedData
        }

        let reusableLayoutsByEdgeID: [UUID: WorkflowCanvasEdgeLayout]
        if lastTopologySignature == topologySignature {
            reusableLayoutsByEdgeID = Dictionary(
                uniqueKeysWithValues: cachedData.edgeLayouts.map { ($0.edge.id, $0) }
            )
        } else {
            reusableLayoutsByEdgeID = [:]
        }

        let edgeLayouts = WorkflowCanvasEdgeLayoutBuilder.buildEdgeLayouts(
            workflow: workflow,
            nodeFramesByID: nodeFramesByID,
            reusing: reusableLayoutsByEdgeID,
            transientNodeIDs: transientNodeIDs
        )
        let sharedHitLayouts = WorkflowCanvasEdgeLayoutBuilder.buildSharedHitLayouts(from: edgeLayouts)
        let resolvedData = WorkflowCanvasResolvedEdgeData(
            edgeLayouts: edgeLayouts,
            sharedHitLayouts: sharedHitLayouts
        )

        lastTopologySignature = topologySignature
        lastLayoutSignature = layoutSignature
        cachedData = resolvedData
        return resolvedData
    }
}

enum WorkflowCanvasEdgeLayoutBuilder {
    static func buildEdgeLayouts(
        workflow: Workflow,
        nodeFramesByID: [UUID: CGRect],
        reusing previousLayoutsByEdgeID: [UUID: WorkflowCanvasEdgeLayout] = [:],
        transientNodeIDs: Set<UUID> = []
    ) -> [WorkflowCanvasEdgeLayout] {
        let nodesByID = Dictionary(uniqueKeysWithValues: workflow.nodes.map { ($0.id, $0) })
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

        let fanoutInfoBySourceID = fanoutLayoutMap(for: candidates)
        let faninInfoByBundleKey = faninLayoutMap(for: candidates)
        let grouped = Dictionary(grouping: candidates, by: \.bundleKey)
        let groupedBundles = grouped.values.sorted { lhs, rhs in
            guard let lhsFirst = lhs.first,
                  let rhsFirst = rhs.first else {
                return lhs.count < rhs.count
            }

            if abs(lhsFirst.toFrame.midY - rhsFirst.toFrame.midY) > 0.5 {
                return lhsFirst.toFrame.midY < rhsFirst.toFrame.midY
            }
            if abs(lhsFirst.toFrame.midX - rhsFirst.toFrame.midX) > 0.5 {
                return lhsFirst.toFrame.midX < rhsFirst.toFrame.midX
            }
            if abs(lhsFirst.fromFrame.midY - rhsFirst.fromFrame.midY) > 0.5 {
                return lhsFirst.fromFrame.midY < rhsFirst.fromFrame.midY
            }
            return lhsFirst.fromFrame.midX < rhsFirst.fromFrame.midX
        }
        let edgeIDsNeedingRefresh = edgeIDsNeedingRefresh(
            in: workflow,
            transientNodeIDs: transientNodeIDs
        )
        var layouts: [WorkflowCanvasEdgeLayout] = []

        for bundle in groupedBundles {
            let sortedBundle = bundle.sorted { lhs, rhs in
                let lhsAngle = angle(from: lhs.toFrame.center, to: lhs.fromFrame.center)
                let rhsAngle = angle(from: rhs.toFrame.center, to: rhs.fromFrame.center)
                return lhsAngle < rhsAngle
            }
            let laneOffsets = laneOffsets(for: sortedBundle.count)

            for (index, candidate) in sortedBundle.enumerated() {
                if !previousLayoutsByEdgeID.isEmpty,
                   !edgeIDsNeedingRefresh.contains(candidate.edge.id),
                   let existingLayout = previousLayoutsByEdgeID[candidate.edge.id],
                   existingLayout.edge == candidate.edge {
                    layouts.append(existingLayout)
                    continue
                }

                let obstacles = workflow.nodes.compactMap { node -> CGRect? in
                    guard node.id != candidate.edge.fromNodeID,
                          node.id != candidate.edge.toNodeID else { return nil }
                    return nodeFramesByID[node.id]
                }
                let points = bestPath(
                    from: candidatePaths(
                        for: candidate,
                        obstacles: obstacles,
                        laneOffset: laneOffsets[index],
                        fanoutInfo: fanoutInfoBySourceID[candidate.edge.fromNodeID],
                        faninInfo: faninInfoByBundleKey[candidate.bundleKey]
                    ),
                    against: layouts
                )

                layouts.append(
                    WorkflowCanvasEdgeLayout(
                        edge: candidate.edge,
                        points: points
                    )
                )
            }
        }

        return layouts
    }

    private static func candidatePaths(
        for candidate: RoutedEdgeCandidate,
        obstacles: [CGRect],
        laneOffset: CGFloat,
        fanoutInfo: FanoutLayoutInfo?,
        faninInfo: FaninLayoutInfo?
    ) -> [[CGPoint]] {
        var result: [[CGPoint]] = []
        var seen = Set<String>()

        func append(_ path: [CGPoint]?) {
            guard let path, path.count >= 2 else { return }
            let key = normalizedPathKey(path)
            guard seen.insert(key).inserted else { return }
            result.append(path)
        }

        if let fanoutInfo {
            if candidate.edge.toNodeID == fanoutInfo.centerTargetID,
               abs(candidate.toFrame.midX - candidate.fromFrame.midX) <= 28 {
                append(
                    WorkflowEdgeRoutePlanner.centerDownRoute(
                        from: candidate.fromFrame,
                        to: candidate.toFrame,
                        avoiding: obstacles
                    )
                )
                for path in WorkflowEdgeRoutePlanner.routeCandidates(
                    from: candidate.fromFrame,
                    to: candidate.toFrame,
                    avoiding: obstacles,
                    preferredAxis: .vertical,
                    laneOffset: 0
                ) {
                    append(path)
                }
            } else {
                append(
                    WorkflowEdgeRoutePlanner.fanoutRoute(
                        from: candidate.fromFrame,
                        to: candidate.toFrame,
                        turnY: fanoutInfo.turnY,
                        targetAnchorX: fanoutInfo.targetAnchorX(
                            for: candidate.edge.toNodeID,
                            default: candidate.toFrame.midX
                        ),
                        avoiding: obstacles
                    )
                )
            }
        }

        if let faninInfo {
            append(
                WorkflowEdgeRoutePlanner.faninRoute(
                    from: candidate.fromFrame,
                    to: candidate.toFrame,
                    incomingSide: faninInfo.incomingSide,
                    mergeAxisValue: faninInfo.mergeAxisValue,
                    trunkAxisValue: faninInfo.trunkAxisValue,
                    avoiding: obstacles
                )
            )
        }

        for path in WorkflowEdgeRoutePlanner.routeCandidates(
            from: candidate.fromFrame,
            to: candidate.toFrame,
            avoiding: obstacles,
            preferredAxis: candidate.preferredAxis,
            laneOffset: laneOffset
        ) {
            append(path)
        }

        if result.isEmpty {
            result.append(
                WorkflowEdgeRoutePlanner.route(
                    from: candidate.fromFrame,
                    to: candidate.toFrame,
                    avoiding: obstacles,
                    preferredAxis: candidate.preferredAxis,
                    laneOffset: laneOffset
                )
            )
        }

        return result
    }

    private static func bestPath(
        from candidates: [[CGPoint]],
        against existingLayouts: [WorkflowCanvasEdgeLayout]
    ) -> [CGPoint] {
        guard !candidates.isEmpty else { return [] }

        return candidates.enumerated().min { lhs, rhs in
            let lhsScore = pathScore(for: lhs.element, against: existingLayouts, fallbackIndex: lhs.offset)
            let rhsScore = pathScore(for: rhs.element, against: existingLayouts, fallbackIndex: rhs.offset)

            if lhsScore.crossings != rhsScore.crossings {
                return lhsScore.crossings < rhsScore.crossings
            }
            if lhsScore.bends != rhsScore.bends {
                return lhsScore.bends < rhsScore.bends
            }
            if abs(lhsScore.length - rhsScore.length) > 0.5 {
                return lhsScore.length < rhsScore.length
            }
            return lhsScore.fallbackIndex < rhsScore.fallbackIndex
        }?.element ?? candidates[0]
    }

    private static func pathScore(
        for path: [CGPoint],
        against existingLayouts: [WorkflowCanvasEdgeLayout],
        fallbackIndex: Int
    ) -> (crossings: Int, bends: Int, length: CGFloat, fallbackIndex: Int) {
        (
            crossingCount(for: path, against: existingLayouts),
            max(0, path.count - 2),
            pathLength(path),
            fallbackIndex
        )
    }

    private static func crossingCount(
        for path: [CGPoint],
        against existingLayouts: [WorkflowCanvasEdgeLayout]
    ) -> Int {
        let pathSegments = orthogonalSegments(for: path)
        guard !pathSegments.isEmpty else { return 0 }

        var count = 0
        for layout in existingLayouts {
            for existingSegment in orthogonalSegments(for: layout.points) {
                if pathSegments.contains(where: { segmentsCross($0, existingSegment) }) {
                    count += 1
                }
            }
        }
        return count
    }

    private static func orthogonalSegments(for points: [CGPoint]) -> [OrthogonalSegment] {
        zip(points, points.dropFirst()).compactMap { start, end in
            let isVertical = abs(start.x - end.x) < 0.5
            let isHorizontal = abs(start.y - end.y) < 0.5
            guard isVertical || isHorizontal else { return nil }
            return OrthogonalSegment(start: start, end: end)
        }
    }

    private static func segmentsCross(_ lhs: OrthogonalSegment, _ rhs: OrthogonalSegment) -> Bool {
        if lhs.isHorizontal == rhs.isHorizontal {
            return false
        }

        let horizontal = lhs.isHorizontal ? lhs : rhs
        let vertical = lhs.isHorizontal ? rhs : lhs
        let intersection = CGPoint(x: vertical.fixedValue, y: horizontal.fixedValue)

        return horizontal.strictlyContains(x: intersection.x)
            && vertical.strictlyContains(y: intersection.y)
    }

    private static func normalizedPathKey(_ points: [CGPoint]) -> String {
        points
            .map { "\(Int(($0.x * 10).rounded())):\(Int(($0.y * 10).rounded()))" }
            .joined(separator: "|")
    }

    private static func pathLength(_ points: [CGPoint]) -> CGFloat {
        guard points.count >= 2 else { return 0 }
        return zip(points, points.dropFirst()).reduce(CGFloat(0)) { partial, segment in
            partial + hypot(segment.1.x - segment.0.x, segment.1.y - segment.0.y)
        }
    }

    static func topologySignature(for workflow: Workflow) -> Int {
        var hasher = Hasher()
        hasher.combine(workflow.nodes.count)
        hasher.combine(workflow.edges.count)

        for node in workflow.nodes.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            hasher.combine(node.id)
            hasher.combine(node.type)
        }

        for edge in workflow.edges.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            hasher.combine(edge.id)
            hasher.combine(edge.fromNodeID)
            hasher.combine(edge.toNodeID)
            hasher.combine(edge.requiresApproval)
        }

        return hasher.finalize()
    }

    static func layoutSignature(
        for workflow: Workflow,
        nodeFramesByID: [UUID: CGRect]
    ) -> Int {
        var hasher = Hasher()
        hasher.combine(topologySignature(for: workflow))

        for node in workflow.nodes.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            hasher.combine(node.id)
            let frame = nodeFramesByID[node.id] ?? .zero
            combine(frame.minX, into: &hasher)
            combine(frame.minY, into: &hasher)
            combine(frame.width, into: &hasher)
            combine(frame.height, into: &hasher)
        }

        return hasher.finalize()
    }

    static func buildSharedHitLayouts(
        from layouts: [WorkflowCanvasEdgeLayout]
    ) -> [WorkflowCanvasSharedSegmentHitLayout] {
        let axisSegments = layouts.flatMap { layout in
            sharedAxisSegments(for: layout)
        }
        let groupedSegments = Dictionary(grouping: axisSegments, by: \.axisKey)

        return groupedSegments
            .flatMap { axisKey, segments in
                sharedHitLayouts(for: segments, axisKey: axisKey)
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

    private static func sharedAxisSegments(
        for layout: WorkflowCanvasEdgeLayout
    ) -> [SharedAxisSegmentCandidate] {
        zip(layout.points, layout.points.dropFirst()).compactMap { from, to in
            let isVertical = abs(from.x - to.x) < 0.5
            let isHorizontal = abs(from.y - to.y) < 0.5
            guard isVertical || isHorizontal else { return nil }

            let orientation: SharedSegmentOrientation = isVertical ? .vertical : .horizontal
            let fixedValue = isVertical ? from.x : from.y
            let rangeStart = isVertical ? min(from.y, to.y) : min(from.x, to.x)
            let rangeEnd = isVertical ? max(from.y, to.y) : max(from.x, to.x)
            guard rangeEnd - rangeStart > 0.5 else { return nil }

            return SharedAxisSegmentCandidate(
                axisKey: "\(orientation.rawValue):\(Int((fixedValue * 10).rounded()))",
                orientation: orientation,
                fixedValue: fixedValue,
                rangeStart: rangeStart,
                rangeEnd: rangeEnd,
                edge: layout.edge
            )
        }
    }

    private static func sharedHitLayouts(
        for segments: [SharedAxisSegmentCandidate],
        axisKey: String
    ) -> [WorkflowCanvasSharedSegmentHitLayout] {
        let boundaries = uniqueSortedAxisBoundaries(
            segments.flatMap { [$0.rangeStart, $0.rangeEnd] }
        )
        guard boundaries.count >= 2 else { return [] }

        var atomicSegments: [SharedAtomicSegment] = []
        for (start, end) in zip(boundaries, boundaries.dropFirst()) {
            guard end - start > 0.5 else { continue }

            let coveringEdges = uniqueEdgesPreservingOrder(
                segments.compactMap { segment in
                    segment.covers(start: start, end: end) ? segment.edge : nil
                }
            )
            guard coveringEdges.count >= 2,
                  let firstSegment = segments.first else { continue }

            atomicSegments.append(
                SharedAtomicSegment(
                    orientation: firstSegment.orientation,
                    fixedValue: firstSegment.fixedValue,
                    rangeStart: start,
                    rangeEnd: end,
                    edges: coveringEdges
                )
            )
        }

        guard !atomicSegments.isEmpty else { return [] }
        var mergedSegments: [SharedAtomicSegment] = []
        for segment in atomicSegments {
            if let last = mergedSegments.last,
               last.canMerge(with: segment) {
                mergedSegments[mergedSegments.count - 1] = last.merged(with: segment)
            } else {
                mergedSegments.append(segment)
            }
        }

        return mergedSegments.map { segment in
            WorkflowCanvasSharedSegmentHitLayout(
                id: "\(axisKey):\(Int((segment.rangeStart * 10).rounded()))-\(Int((segment.rangeEnd * 10).rounded()))",
                points: segment.points,
                edges: segment.edges
            )
        }
    }

    private static func uniqueSortedAxisBoundaries(_ values: [CGFloat]) -> [CGFloat] {
        var result: [CGFloat] = []
        for value in values.sorted() {
            if let last = result.last, abs(last - value) < 0.5 {
                continue
            }
            result.append(value)
        }
        return result
    }

    private static func fanoutLayoutMap(
        for candidates: [RoutedEdgeCandidate]
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
            let targetAnchorXByTargetID = Dictionary(
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

    private static func faninLayoutMap(
        for candidates: [RoutedEdgeCandidate]
    ) -> [RoutedEdgeBundleKey: FaninLayoutInfo] {
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

    private static func laneOffsets(for count: Int) -> [CGFloat] {
        laneOffsets(for: count, spacing: 14)
    }

    private static func laneOffsets(for count: Int, spacing: CGFloat) -> [CGFloat] {
        guard count > 1 else { return [0] }
        let center = CGFloat(count - 1) / 2
        return (0..<count).map { index in
            (CGFloat(index) - center) * spacing
        }
    }

    private static func compactMergeOffset(for gap: CGFloat) -> CGFloat {
        max(18, min(48, gap * 0.28))
    }

    private static func closestTarget(
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

    private static func angle(from center: CGPoint, to point: CGPoint) -> CGFloat {
        atan2(point.y - center.y, point.x - center.x)
    }

    private static func uniqueEdgesPreservingOrder(_ edges: [WorkflowEdge]) -> [WorkflowEdge] {
        var seen = Set<UUID>()
        var result: [WorkflowEdge] = []
        for edge in edges {
            guard seen.insert(edge.id).inserted else { continue }
            result.append(edge)
        }
        return result
    }

    private static func edgeIDsNeedingRefresh(
        in workflow: Workflow,
        transientNodeIDs: Set<UUID>
    ) -> Set<UUID> {
        guard !transientNodeIDs.isEmpty else {
            return Set(workflow.edges.map(\.id))
        }

        var affectedSourceIDs = transientNodeIDs
        var affectedTargetIDs = transientNodeIDs

        for edge in workflow.edges {
            if transientNodeIDs.contains(edge.fromNodeID) {
                affectedTargetIDs.insert(edge.toNodeID)
            }
            if transientNodeIDs.contains(edge.toNodeID) {
                affectedSourceIDs.insert(edge.fromNodeID)
            }
        }

        return Set(workflow.edges.compactMap { edge in
            let touchesTransientNode = transientNodeIDs.contains(edge.fromNodeID)
                || transientNodeIDs.contains(edge.toNodeID)
            let sharesAffectedSource = affectedSourceIDs.contains(edge.fromNodeID)
            let sharesAffectedTarget = affectedTargetIDs.contains(edge.toNodeID)

            guard touchesTransientNode || sharesAffectedSource || sharesAffectedTarget else {
                return nil
            }
            return edge.id
        })
    }

    private static func combine(_ value: CGFloat, into hasher: inout Hasher) {
        hasher.combine(Int((value * 10).rounded()))
    }
}

private struct SharedAxisSegmentCandidate {
    let axisKey: String
    let orientation: SharedSegmentOrientation
    let fixedValue: CGFloat
    let rangeStart: CGFloat
    let rangeEnd: CGFloat
    let edge: WorkflowEdge

    func covers(start: CGFloat, end: CGFloat) -> Bool {
        rangeStart <= start + 0.5 && rangeEnd >= end - 0.5
    }
}

private struct SharedAtomicSegment {
    let orientation: SharedSegmentOrientation
    let fixedValue: CGFloat
    let rangeStart: CGFloat
    let rangeEnd: CGFloat
    let edges: [WorkflowEdge]

    var points: [CGPoint] {
        switch orientation {
        case .horizontal:
            return [
                CGPoint(x: rangeStart, y: fixedValue),
                CGPoint(x: rangeEnd, y: fixedValue)
            ]
        case .vertical:
            return [
                CGPoint(x: fixedValue, y: rangeStart),
                CGPoint(x: fixedValue, y: rangeEnd)
            ]
        }
    }

    func canMerge(with other: SharedAtomicSegment) -> Bool {
        orientation == other.orientation
            && abs(fixedValue - other.fixedValue) < 0.5
            && abs(rangeEnd - other.rangeStart) < 0.5
            && edges.map(\.id) == other.edges.map(\.id)
    }

    func merged(with other: SharedAtomicSegment) -> SharedAtomicSegment {
        SharedAtomicSegment(
            orientation: orientation,
            fixedValue: fixedValue,
            rangeStart: min(rangeStart, other.rangeStart),
            rangeEnd: max(rangeEnd, other.rangeEnd),
            edges: edges
        )
    }
}

private enum SharedSegmentOrientation: String {
    case horizontal
    case vertical
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

enum EdgeRouteAxis {
    case horizontal
    case vertical
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

        for path in candidates where isClear(path, blockedRects: blockedRects) {
            return simplify(path)
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

extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }

    var area: CGFloat {
        guard !isNull, !isEmpty else { return 0 }
        return width * height
    }
}

extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        hypot(x - other.x, y - other.y)
    }
}
