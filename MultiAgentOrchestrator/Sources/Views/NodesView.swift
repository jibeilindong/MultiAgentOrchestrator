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
    var isConnectMode: Bool = false
    var connectFromAgentID: UUID?
    var onNodeClick: ((WorkflowNode) -> Void)?
    var onSubflowEdit: ((WorkflowNode) -> Void)?  // 新增：子流程编辑回调
    
    @State private var draggingNode: WorkflowNode?
    @State private var isDraggingNode: Bool = false
    
    var body: some View {
        ForEach(currentWorkflow?.nodes ?? []) { node in
            NodeView(
                node: node,
                isSelected: node.id == selectedNodeID,
                agent: appState.getAgent(for: node),
                taskStatus: getTaskStatus(for: node),
                subflowName: getSubflowName(for: node),  // 新增
                isConnectingMode: isConnectMode,
                isConnectSource: connectFromAgentID == node.id,
                onTap: { handleSingleTap(node) },
                onDoubleTap: { handleDoubleTap(node) },
                onLongPress: { handleLongPress(node) }
            )
            .position(adjustedPosition(node.position))
            .zIndex(node.id == selectedNodeID ? 100 : (draggingNode?.id == node.id ? 50 : 1))
            .gesture(createNodeGesture(for: node))
        }
    }
    
    // 获取子流程名称
    private func getSubflowName(for node: WorkflowNode) -> String? {
        guard node.type == .subflow,
              let subflowID = node.subflowID,
              let subflow = appState.currentProject?.workflows.first(where: { $0.id == subflowID }) else {
            return nil
        }
        return subflow.name
    }
    
    private func getTaskStatus(for node: WorkflowNode) -> TaskStatus? {
        guard let task = appState.taskManager.tasks.first(where: { $0.workflowNodeID == node.id }) else {
            return nil
        }
        return task.status
    }
    
    private func adjustedPosition(_ position: CGPoint) -> CGPoint {
        let centerX = geometry.size.width / 2
        let centerY = geometry.size.height / 2
        return CGPoint(
            x: position.x * scale + offset.width + centerX,
            y: position.y * scale + offset.height + centerY
        )
    }
    
    private func createNodeGesture(for node: WorkflowNode) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if connectingFromNode == nil {
                    isDraggingNode = true
                    updateNodePosition(node.id, value.location)
                    draggingNode = node
                }
            }
            .onEnded { _ in
                draggingNode = nil
                isDraggingNode = false
            }
    }
    
    private func updateNodePosition(_ nodeID: UUID, _ location: CGPoint) {
        guard var workflow = currentWorkflow,
              let index = workflow.nodes.firstIndex(where: { $0.id == nodeID }) else { return }
        
        let centerX = geometry.size.width / 2
        let centerY = geometry.size.height / 2
        
        let adjustedX = (location.x - centerX - offset.width) / scale
        let adjustedY = (location.y - centerY - offset.height) / scale
        
        workflow.nodes[index].position = CGPoint(x: adjustedX, y: adjustedY)
        updateWorkflow(workflow)
    }
    
    // 双击处理：如果是子流程节点，打开子流程编辑器
    private func handleDoubleTap(_ node: WorkflowNode) {
        if node.type == .subflow {
            // 打开子流程编辑器
            onSubflowEdit?(node)
        } else if connectingFromNode == nil {
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
        
        if let callback = onNodeClick {
            callback(node)
        }
    }
    
    // 长按处理：如果是子流程节点，打开编辑菜单
    private func handleLongPress(_ node: WorkflowNode) {
        if node.type == .subflow {
            onSubflowEdit?(node)
        } else {
            deleteNode(node.id)
        }
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
