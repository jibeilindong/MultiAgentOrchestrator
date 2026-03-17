//
//  Untitled.swift
//  MultiAgentOrchestrator
//
//  Created by 陈荣泽 on 2026/3/18.
//

import SwiftUI

struct NodeView: View {
    let node: WorkflowNode
    let isSelected: Bool
    let agent: Agent?
    let taskStatus: TaskStatus?  // 新增：节点关联的任务状态

    var body: some View {
        VStack(spacing: 4) {
            // 状态指示器
            if let status = taskStatus {
                Circle()
                    .fill(status.color)
                    .frame(width: 8, height: 8)
                    .overlay(
                        Circle()
                            .stroke(Color.white, lineWidth: 2)
                    )
                    .offset(x: 30, y: -30)
            }
            
            Image(systemName: nodeTypeIcon)
                .font(.title2)
                .foregroundColor(nodeColor)
            Text(nodeTitle)
                .font(.caption)
                .foregroundColor(.primary)
        }
        .frame(width: nodeWidth, height: 60)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(nodeBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(borderColor, lineWidth: isSelected ? 3 : 2)
                )
        )
        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
    }

    private var nodeTypeIcon: String {
        switch node.type {
        case .agent: return "person.circle.fill"
        case .start: return "play.circle.fill"
        case .end: return "stop.circle.fill"
        }
    }
    
    private var nodeTitle: String {
        if node.type == .agent, let agent = agent {
            return agent.name
        }
        
        switch node.type {
        case .agent: return "Agent"
        case .start: return "Start"
        case .end: return "End"
        }
    }
    
    private var nodeColor: Color {
        switch node.type {
        case .agent: return .blue
        case .start: return .green
        case .end: return .red
        }
    }
    
    private var nodeBackground: Color {
        switch node.type {
        case .agent: return Color.blue.opacity(0.1)
        case .start: return Color.green.opacity(0.1)
        case .end: return Color.red.opacity(0.1)
        }
    }
    
    private var borderColor: Color {
        isSelected ? nodeColor : nodeColor.opacity(0.5)
    }
    
    private var nodeWidth: CGFloat {
        switch node.type {
        case .agent: return 100
        default: return 80
        }
    }
}
