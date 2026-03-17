//
//  NodesView.swift
//  MultiAgentOrchestrator
//
//  Created by 陈荣泽 on 2026/3/18.
//

import SwiftUI

struct NodesView: View {
    @EnvironmentObject var appState: AppState
    let currentWorkflow: Workflow?
    @Binding var selectedNodeID: UUID?
    @Binding var connectingFromNode: WorkflowNode?
    @Binding var tempConnectionEnd: CGPoint?
    let scale: CGFloat
    let offset: CGSize
    let geometry: GeometryProxy
    
    @State private var draggingNode: WorkflowNode?
    
    var body: some View {
        ForEach(currentWorkflow?.nodes ?? []) { node in
            NodeView(
                node: node,
                isSelected: node.id == selectedNodeID,
                agent: appState.getAgent(for: node),
                taskStatus: getTaskStatus(for: node)  // 新增
            )
            .position(adjustedPosition(node.position))
            .gesture(createNodeGesture(for: node))
        }
    }
    
    private func getTaskStatus(for node: WorkflowNode) -> TaskStatus? {
        guard let task = appState.taskManager.tasks.first(where: { $0.workflowNodeID == node.id }) else {
            return nil
        }
        return task.status
    }
    
    private func adjustedPosition(_ position: CGPoint) -> CGPoint {
        return CGPoint(
            x: position.x * scale + offset.width + 200,
            y: position.y * scale + offset.height + 200
        )
    }
    
    private func createNodeGesture(for node: WorkflowNode) -> some Gesture {
        SimultaneousGesture(
            DragGesture()
                .onChanged { value in
                    if connectingFromNode == nil {
                        updateNodePosition(node.id, value.location)
                        draggingNode = node
                    }
                }
                .onEnded { _ in
                    draggingNode = nil
                },
            
            SimultaneousGesture(
                TapGesture(count: 2)
                    .onEnded {
                        handleDoubleTap(node)
                    },
                
                SimultaneousGesture(
                    TapGesture(count: 1)
                        .onEnded {
                            handleSingleTap(node)
                        },
                    
                    LongPressGesture(minimumDuration: 0.5)
                        .onEnded { _ in
                            handleLongPress(node)
                        }
                )
            )
        )
    }
    
    private func updateNodePosition(_ nodeID: UUID, _ location: CGPoint) {
        guard var workflow = currentWorkflow,
              let index = workflow.nodes.firstIndex(where: { $0.id == nodeID }) else { return }
        
        let adjustedX = (location.x - offset.width - 200) / scale
        let adjustedY = (location.y - offset.height - 200) / scale
        
        workflow.nodes[index].position = CGPoint(x: adjustedX, y: adjustedY)
        updateWorkflow(workflow)
    }
    
    private func handleDoubleTap(_ node: WorkflowNode) {
        if connectingFromNode == nil {
            connectingFromNode = node
        } else if connectingFromNode?.id != node.id {
            createConnection(from: connectingFromNode!.id, to: node.id)
            connectingFromNode = nil
            tempConnectionEnd = nil
        }
    }
    
    private func handleSingleTap(_ node: WorkflowNode) {
        selectedNodeID = node.id
        connectingFromNode = nil
        tempConnectionEnd = nil
    }
    
    private func handleLongPress(_ node: WorkflowNode) {
        deleteNode(node.id)
    }
    
    private func createConnection(from: UUID, to: UUID) {
        guard var workflow = currentWorkflow,
              workflow.nodes.contains(where: { $0.id == from }),
              workflow.nodes.contains(where: { $0.id == to }) else { return }
        
        let newEdge = WorkflowEdge(from: from, to: to)
        workflow.edges.append(newEdge)
        updateWorkflow(workflow)
    }
    
    private func deleteNode(_ nodeID: UUID) {
        guard var workflow = currentWorkflow else { return }
        
        // 删除节点
        workflow.nodes.removeAll { $0.id == nodeID }
        
        // 删除相关的连接线
        workflow.edges.removeAll { $0.fromNodeID == nodeID || $0.toNodeID == nodeID }
        
        updateWorkflow(workflow)
        
        if selectedNodeID == nodeID {
            selectedNodeID = nil
        }
    }
    
    private func updateWorkflow(_ workflow: Workflow) {
        guard let index = appState.currentProject?.workflows.firstIndex(where: { $0.id == workflow.id }) else { return }
        appState.currentProject?.workflows[index] = workflow
    }
}
