//
//  ConnectionLinesView.swift
//  MultiAgentOrchestrator
//
//  Created by 陈荣泽 on 2026/3/18.
//

import SwiftUI

struct ConnectionLinesView: View {
    let currentWorkflow: Workflow?
    @Binding var scale: CGFloat
    let offset: CGSize
    let geometry: GeometryProxy?
    
    // 节点宽度和高度（用于计算边缘）
    private let nodeWidth: CGFloat = 80
    private let nodeHeight: CGFloat = 60
    
    init(currentWorkflow: Workflow?, scale: Binding<CGFloat>, offset: CGSize, geometry: GeometryProxy? = nil) {
        self.currentWorkflow = currentWorkflow
        self._scale = scale
        self.offset = offset
        self.geometry = geometry
    }
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                // 画连接线和箭头
                ForEach(currentWorkflow?.edges ?? []) { edge in
                    if let fromNode = currentWorkflow?.nodes.first(where: { $0.id == edge.fromNodeID }),
                       let toNode = currentWorkflow?.nodes.first(where: { $0.id == edge.toNodeID }) {
                        
                        let fromPos = getNodeCenter(fromNode.position, geometry: geo)
                        let toPos = getNodeCenter(toNode.position, geometry: geo)
                        
                        // 计算起点和终点（节点外围的圆形缓冲区）
                        let startPoint = calculateEdgePoint(from: fromPos, to: toPos)
                        let endPoint = calculateEdgePoint(from: toPos, to: fromPos)
                        
                        // 画直线
                        ConnectionLineShape(from: startPoint, to: endPoint)
                            .stroke(edge.requiresApproval ? Color.orange.opacity(0.7) : Color.blue.opacity(0.6),
                                    style: StrokeStyle(lineWidth: 2, dash: edge.requiresApproval ? [8, 4] : []))
                        
                        // 画箭头
                        ArrowShape(from: startPoint, to: endPoint)
                            .stroke(edge.requiresApproval ? Color.orange.opacity(0.85) : Color.blue.opacity(0.8),
                                    style: StrokeStyle(lineWidth: 2, lineCap: .round))

                        if !edgeDisplayText(edge).isEmpty {
                            EdgeLabelView(text: edgeDisplayText(edge), requiresApproval: edge.requiresApproval)
                                .position(midPoint(from: startPoint, to: endPoint))
                        }
                    }
                }
            }
        }
    }
    
    // 获取节点中心位置
    private func getNodeCenter(_ position: CGPoint, geometry: GeometryProxy) -> CGPoint {
        let centerX = geometry.size.width / 2
        let centerY = geometry.size.height / 2
        return CGPoint(
            x: position.x * scale + offset.width + centerX,
            y: position.y * scale + offset.height + centerY
        )
    }
    
    // 计算节点外围的圆形缓冲区上的点
    private func calculateEdgePoint(from: CGPoint, to: CGPoint) -> CGPoint {
        let dx = to.x - from.x
        let dy = to.y - from.y
        
        // 防止除以零
        guard abs(dx) > 0.001 || abs(dy) > 0.001 else {
            return from
        }
        
        let angle = atan2(dy, dx)
        
        // 缓冲区半径 = 节点对角线的一半 + 15像素
        let diagonal = sqrt(nodeWidth * nodeWidth + nodeHeight * nodeHeight)
        let buffer: CGFloat = diagonal / 2 + 15
        
        // 计算交点（圆形缓冲区）
        let t = buffer * scale
        
        // 计算交点
        let x = from.x + t * cos(angle)
        let y = from.y + t * sin(angle)
        
        return CGPoint(x: x, y: y)
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
        if !label.isEmpty {
            return label
        }
        if !condition.isEmpty {
            return condition
        }
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

// 直线连接
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

// 箭头
struct ArrowShape: Shape {
    let from: CGPoint
    let to: CGPoint
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        let dx = to.x - from.x
        let dy = to.y - from.y
        
        // 防止除以零
        guard abs(dx) > 0.001 || abs(dy) > 0.001 else {
            return path
        }
        
        let angle = atan2(dy, dx)
        
        // 箭头参数
        let arrowLength: CGFloat = 12
        
        // 箭头起点 = 终点
        let tip = to
        
        // 箭头左侧点
        let leftPoint = CGPoint(
            x: tip.x - arrowLength * cos(angle - .pi / 6),
            y: tip.y - arrowLength * sin(angle - .pi / 6)
        )
        
        // 箭头右侧点
        let rightPoint = CGPoint(
            x: tip.x - arrowLength * cos(angle + .pi / 6),
            y: tip.y - arrowLength * sin(angle + .pi / 6)
        )
        
        // 画V形箭头
        path.move(to: leftPoint)
        path.addLine(to: tip)
        path.addLine(to: rightPoint)
        
        return path
    }
}
