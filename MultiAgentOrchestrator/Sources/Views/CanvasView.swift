//
//  Untitled.swift
//  MultiAgentOrchestrator
//
//  Created by 陈荣泽 on 2026/3/18.
//

import SwiftUI

struct CanvasView: View {
    @EnvironmentObject var appState: AppState
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var selectedNodeID: UUID?
    @State private var connectingFromNode: WorkflowNode?
    @State private var tempConnectionEnd: CGPoint?
    @State private var isDraggingCanvas: Bool = false
    
    var body: some View {
        CanvasContentView(
            scale: $scale,
            offset: $offset,
            lastOffset: $lastOffset,
            selectedNodeID: $selectedNodeID,
            connectingFromNode: $connectingFromNode,
            tempConnectionEnd: $tempConnectionEnd
        )
        .gesture(createCanvasGesture())
        .overlay(ControlButtonsView(
            scale: $scale,
            offset: $offset,
            lastOffset: $lastOffset,
            selectedNodeID: $selectedNodeID,
            appState: appState
        ))
        .onAppear {
            setupDefaultNodes()
        }
    }
    
    private func createCanvasGesture() -> some Gesture {
        SimultaneousGesture(
            MagnificationGesture()
                .onChanged { value in
                    scale = lastOffset == .zero ? value.magnitude : scale
                    scale = max(0.1, min(scale, 5.0))
                }
                .onEnded { _ in
                    lastOffset = offset
                },
            
            SimultaneousGesture(
                DragGesture(minimumDistance: 5)
                    .onChanged { value in
                        if connectingFromNode == nil {
                            isDraggingCanvas = true
                            offset = CGSize(
                                width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height
                            )
                        }
                    }
                    .onEnded { _ in
                        if isDraggingCanvas {
                            lastOffset = offset
                            isDraggingCanvas = false
                        }
                    },
                
                TapGesture(count: 1)
                    .onEnded {
                        // 点击空白处取消选择
                        selectedNodeID = nil
                        connectingFromNode = nil
                        tempConnectionEnd = nil
                    }
            )
        )
    }
    
    private func setupDefaultNodes() {
        guard let workflow = appState.currentProject?.workflows.first,
              workflow.nodes.isEmpty else { return }
        
        // 添加起始节点
        let startNode = WorkflowNode(type: .start)
        var startNodeCopy = startNode
        startNodeCopy.position = CGPoint(x: 100, y: 100)
        
        // 添加结束节点
        let endNode = WorkflowNode(type: .end)
        var endNodeCopy = endNode
        endNodeCopy.position = CGPoint(x: 500, y: 100)
        
        var updatedWorkflow = workflow
        updatedWorkflow.nodes = [startNodeCopy, endNodeCopy]
        
        if let index = appState.currentProject?.workflows.firstIndex(where: { $0.id == workflow.id }) {
            appState.currentProject?.workflows[index] = updatedWorkflow
        }
    }
}
