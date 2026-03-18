//
//  CanvasContentView.swift
//  MultiAgentOrchestrator
//
//  Created by 陈荣泽 on 2026/3/18.
//

import SwiftUI
import UniformTypeIdentifiers

struct CanvasContentView: View {
    @EnvironmentObject var appState: AppState
    @Binding var scale: CGFloat
    @Binding var offset: CGSize
    @Binding var lastOffset: CGSize
    @Binding var selectedNodeID: UUID?
    @Binding var connectingFromNode: WorkflowNode?
    @Binding var tempConnectionEnd: CGPoint?
    var isConnectMode: Bool = false
    var connectFromAgentID: UUID?
    var onNodeClick: ((WorkflowNode) -> Void)?
    var onSubflowEdit: ((WorkflowNode) -> Void)?
    
    // 拖拽状态
    @State private var isDraggingOverCanvas: Bool = false
    @State private var dropLocation: CGPoint = .zero
    
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
                    .opacity(isDraggingOverCanvas ? 0.6 : 1.0)
                
                // 拖拽时的放置指示器
                if isDraggingOverCanvas {
                    DropIndicatorView(geometry: geometry)
                }
                
                // 2. 连接线（添加选中状态支持）
                ConnectionLinesView(
                    currentWorkflow: currentWorkflow,
                    scale: $scale,
                    offset: offset,
                    geometry: geometry
                )
                
                // 3. 临时连接线（正在拖拽连接时）
                if let fromNode = connectingFromNode,
                   let endPoint = tempConnectionEnd {
                    ConnectionLineShape(
                        from: adjustedPosition(fromNode.position, geometry: geometry),
                        to: endPoint
                    )
                    .stroke(Color.orange.opacity(0.8), style: StrokeStyle(lineWidth: 3, dash: [6, 3]))
                }
                
                // 4. 节点
                NodesView(
                    currentWorkflow: currentWorkflow,
                    selectedNodeID: $selectedNodeID,
                    connectingFromNode: $connectingFromNode,
                    tempConnectionEnd: $tempConnectionEnd,
                    scale: scale,
                    offset: offset,
                    geometry: geometry,
                    isConnectMode: isConnectMode,
                    connectFromAgentID: connectFromAgentID,
                    onNodeClick: onNodeClick,
                    onSubflowEdit: onSubflowEdit
                )
                .environmentObject(appState)
                
                // 5. 提示视图
                HintViews(geometry: geometry)
            }
            // 拖拽目标识别 - 添加视觉反馈
            .onDrop(of: [.text], isTargeted: $isDraggingOverCanvas) { providers, location in
                _ = handleDrop(providers: providers, location: location)
                return true
            }
        }
    }
    
    private func adjustedPosition(_ position: CGPoint, geometry: GeometryProxy) -> CGPoint {
        let centerX = geometry.size.width / 2
        let centerY = geometry.size.height / 2
        return CGPoint(
            x: position.x * scale + offset.width + centerX,
            y: position.y * scale + offset.height + centerY
        )
    }
    
    private func handleDrop(providers: [NSItemProvider], location: CGPoint) -> Bool {
        for provider in providers {
            provider.loadObject(ofClass: NSString.self) { item, error in
                if let agentName = item as? String {
                    DispatchQueue.main.async {
                        addAgentNodeToCanvas(agentName: agentName, at: location)
                    }
                }
            }
        }
        return true
    }
    
    private func addAgentNodeToCanvas(agentName: String, at location: CGPoint) {
        guard var project = appState.currentProject,
              var workflow = project.workflows.first else { return }
        
        guard let agent = project.agents.first(where: { $0.name == agentName }) else { return }
        
        var newNode = WorkflowNode(type: .agent)
        newNode.agentID = agent.id
        
        // 将屏幕坐标转换为画布坐标
        let centerX: CGFloat = 200
        let centerY: CGFloat = 200
        newNode.position = CGPoint(
            x: (location.x - centerX - offset.width) / scale,
            y: (location.y - centerY - offset.height) / scale
        )
        
        workflow.nodes.append(newNode)
        
        if let index = project.workflows.firstIndex(where: { $0.id == workflow.id }) {
            project.workflows[index] = workflow
            appState.currentProject = project
        }
    }
}

// 拖拽放置指示器视图
struct DropIndicatorView: View {
    let geometry: GeometryProxy
    
    var body: some View {
        ZStack {
            // 半透明覆盖层
            Color.blue.opacity(0.08)
                .edgesIgnoringSafeArea(.all)
            
            // 中心放置指示器
            Circle()
                .stroke(Color.blue, lineWidth: 2)
                .fill(Color.blue.opacity(0.15))
                .frame(width: 90, height: 90)
                .overlay(
                    ZStack {
                        Circle()
                            .stroke(Color.blue, lineWidth: 2)
                            .frame(width: 100, height: 100)
                            .opacity(0.5)
                    }
                )
            
            // 提示文字
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Text(LocalizedString.dropToAddNode)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.blue)
                        .cornerRadius(8)
                        .shadow(radius: 2)
                        .position(x: geometry.size.width - 70, y: geometry.size.height - 40)
                }
            }
        }
    }
}
