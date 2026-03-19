//
//  CanvasContentView.swift
//  MultiAgentOrchestrator
//

import SwiftUI
import UniformTypeIdentifiers

struct CanvasContentView: View {
    @EnvironmentObject var appState: AppState
    @Binding var scale: CGFloat
    @Binding var offset: CGSize
    @Binding var lastOffset: CGSize
    @Binding var selectedNodeID: UUID?
    @Binding var selectedEdgeID: UUID?
    @Binding var connectingFromNode: WorkflowNode?
    @Binding var tempConnectionEnd: CGPoint?
    var onNodeClick: ((WorkflowNode) -> Void)?
    var onNodeSelected: ((WorkflowNode) -> Void)?
    var onEdgeSelected: ((WorkflowEdge) -> Void)?
    var onSubflowEdit: ((WorkflowNode) -> Void)?

    @State private var isDraggingOverCanvas: Bool = false

    var currentWorkflow: Workflow? {
        appState.currentProject?.workflows.first
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                GridBackground()
                    .scaleEffect(scale)
                    .offset(offset)
                    .opacity(isDraggingOverCanvas ? 0.6 : 1.0)

                if isDraggingOverCanvas {
                    DropIndicatorView(geometry: geometry)
                }

                ConnectionLinesView(
                    currentWorkflow: currentWorkflow,
                    scale: $scale,
                    offset: offset,
                    geometry: geometry,
                    selectedEdgeID: $selectedEdgeID,
                    onEdgeSelected: { edge in
                        selectedNodeID = nil
                        onEdgeSelected?(edge)
                    }
                )

                if let fromNode = connectingFromNode,
                   let endPoint = tempConnectionEnd {
                    ConnectionLineShape(
                        from: adjustedPosition(fromNode.position, geometry: geometry),
                        to: endPoint
                    )
                    .stroke(Color.orange.opacity(0.8), style: StrokeStyle(lineWidth: 3, dash: [6, 3]))
                }

                NodesView(
                    currentWorkflow: currentWorkflow,
                    selectedNodeID: $selectedNodeID,
                    selectedEdgeID: $selectedEdgeID,
                    connectingFromNode: $connectingFromNode,
                    tempConnectionEnd: $tempConnectionEnd,
                    scale: scale,
                    offset: offset,
                    geometry: geometry,
                    onNodeClick: onNodeClick,
                    onNodeSelected: onNodeSelected,
                    onSubflowEdit: onSubflowEdit
                )
                .environmentObject(appState)

                HintViews(geometry: geometry)
            }
            .onDrop(of: [.text], isTargeted: $isDraggingOverCanvas) { providers, location in
                handleDrop(providers: providers, location: location)
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
            provider.loadObject(ofClass: NSString.self) { item, _ in
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
        let centerX: CGFloat = 200
        let centerY: CGFloat = 200
        let canvasPosition = CGPoint(
            x: (location.x - centerX - offset.width) / scale,
            y: (location.y - centerY - offset.height) / scale
        )

        appState.addAgentNode(agentName: agentName, position: canvasPosition)
    }
}

struct DropIndicatorView: View {
    let geometry: GeometryProxy

    var body: some View {
        ZStack {
            Color.blue.opacity(0.08)
                .edgesIgnoringSafeArea(.all)

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
