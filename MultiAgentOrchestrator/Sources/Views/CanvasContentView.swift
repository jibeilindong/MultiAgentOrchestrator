//
//  CanvasContentView.swift
//  MultiAgentOrchestrator
//
//  Created by 陈荣泽 on 2026/3/18.
//

import SwiftUI

struct CanvasContentView: View {
    @EnvironmentObject var appState: AppState
    @Binding var scale: CGFloat
    @Binding var offset: CGSize
    @Binding var lastOffset: CGSize
    @Binding var selectedNodeID: UUID?
    @Binding var connectingFromNode: WorkflowNode?
    @Binding var tempConnectionEnd: CGPoint?
    
    var currentWorkflow: Workflow? {
        appState.currentProject?.workflows.first
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 1. 网格背景
                GridBackground()
                    .scaleEffect(scale)
                    .offset(offset)
                
                // 2. 连接线
                ConnectionLinesView(currentWorkflow: currentWorkflow, scale: scale, offset: offset)
                
                // 3. 临时连接线（正在拖拽连接时）
                if let fromNode = connectingFromNode,
                   let endPoint = tempConnectionEnd {
                    ConnectionLine(
                        from: adjustedPosition(fromNode.position, geometry: geometry),
                        to: endPoint
                    )
                    .stroke(Color.orange.opacity(0.7), style: StrokeStyle(lineWidth: 2, dash: [5]))
                }
                
                // 4. 节点
                NodesView(
                    currentWorkflow: currentWorkflow,
                    selectedNodeID: $selectedNodeID,
                    connectingFromNode: $connectingFromNode,
                    tempConnectionEnd: $tempConnectionEnd,
                    scale: scale,
                    offset: offset,
                    geometry: geometry
                )
                .environmentObject(appState)
                
                // 5. 提示视图
                HintViews(geometry: geometry)
            }
        }
    }
    
    private func adjustedPosition(_ position: CGPoint, geometry: GeometryProxy) -> CGPoint {
        return CGPoint(
            x: position.x * scale + offset.width + 200,
            y: position.y * scale + offset.height + 200
        )
    }
}
