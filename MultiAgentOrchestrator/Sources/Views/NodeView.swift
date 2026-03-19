//
//  NodeView.swift
//  MultiAgentOrchestrator
//
//  Created by 陈荣泽 on 2026/3/18.
//

import SwiftUI

struct NodeView: View {
    @EnvironmentObject var appState: AppState
    let node: WorkflowNode
    let isSelected: Bool
    let agent: Agent?
    let taskStatus: TaskStatus?
    let subflowName: String?
    
    // 连接模式状态
    var isConnectingMode: Bool = false
    var isConnectSource: Bool = false
    
    // 回调函数
    var onTap: (() -> Void)?
    var onDoubleTap: (() -> Void)?
    var onLongPress: (() -> Void)?
    var accentColor: Color? = nil
    var textScale: CGFloat = 1
    var textColor: Color = .primary

    @State private var isHovered: Bool = false
    @State private var pulseAnimation: Bool = false
    
    var body: some View {
        VStack(spacing: 4) {
            // 嵌套层级指示器
            if node.nestingLevel > 0 {
                NestingLevelBadge(level: node.nestingLevel)
            }
            
            // 状态指示器
            if let status = taskStatus {
                Circle()
                    .fill(status.color)
                    .frame(width: 10, height: 10)
                    .overlay(
                        Circle()
                            .stroke(Color.white, lineWidth: 2)
                    )
                    .shadow(color: status.color.opacity(0.5), radius: isHovered ? 4 : 2)
                    .offset(x: 35, y: -35)
            }
            
            // 节点图标和标题
            HStack(spacing: 4) {
                Image(systemName: nodeTypeIcon)
                    .font(.title3)
                    .foregroundColor(nodeColor)
                
                if let subflowName = subflowName {
                    Text(subflowName)
                        .font(.system(size: 10 * textScale))
                        .lineLimit(1)
                        .foregroundColor(textColor)
                } else {
                    Text(nodeTitle)
                        .font(.system(size: 12 * textScale))
                        .lineLimit(1)
                        .foregroundColor(textColor)
                }
            }

            if node.type == .branch, let condition = optionalText(node.conditionExpression) {
                Text(condition)
                    .font(.system(size: 10 * textScale))
                    .lineLimit(1)
                    .foregroundColor(textColor.opacity(0.75))
                    .padding(.horizontal, 8)
            }
            
            // 连接指示器（连接模式下显示）
            if isConnectingMode && !isConnectSource {
                HStack(spacing: 2) {
                    Image(systemName: "link")
                        .font(.system(size: 10 * textScale))
                    Text("点击连接")
                        .font(.system(size: 8 * textScale))
                }
                .foregroundColor(.orange)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(4)
            }
            
            // 子流程指示器
            if node.type == .subflow {
                HStack(spacing: 2) {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 10 * textScale))
                    Text(LocalizedString.subflow)
                        .font(.system(size: 10 * textScale))
                }
                .foregroundColor(.purple)
            }
        }
        .frame(width: nodeWidth, height: nodeHeight)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(nodeBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(borderColor, lineWidth: isSelected ? 3 : (isHovered ? 2 : 1))
                )
        )
        .shadow(
            color: isSelected ? nodeColor.opacity(0.4) : (isHovered ? Color.black.opacity(0.15) : Color.black.opacity(0.08)),
            radius: isSelected ? 8 : (isHovered ? 6 : 3),
            x: 0,
            y: isSelected ? 4 : (isHovered ? 3 : 2)
        )
        // 连接源节点动画
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    isConnectSource ? Color.orange : Color.clear,
                    lineWidth: 2
                )
                .scaleEffect(isConnectSource ? (pulseAnimation ? 1.05 : 1.0) : 1.0)
                .opacity(isConnectSource ? (pulseAnimation ? 0.6 : 1.0) : 0)
                .animation(
                    isConnectSource ? 
                        Animation.easeInOut(duration: 0.8).repeatForever(autoreverses: true) : 
                        .default,
                    value: pulseAnimation
                )
        )
        // 点击手势
        .onTapGesture(count: 2) {
            onDoubleTap?()
        }
        .onTapGesture(count: 1) {
            onTap?()
        }
        .onLongPressGesture(minimumDuration: 0.5) {
            onLongPress?()
        }
        // 悬停状态
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
        // 连接源时启动脉冲动画
        .onChange(of: isConnectSource) { _, newValue in
            if newValue {
                pulseAnimation = true
            } else {
                pulseAnimation = false
            }
        }
        // 变换
        .scaleEffect(isSelected ? 1.02 : (isHovered ? 1.01 : 1.0))
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .animation(.easeInOut(duration: 0.1), value: isHovered)
    }

    private var nodeTypeIcon: String {
        switch node.type {
        case .agent: return "person.circle.fill"
        case .branch: return "arrow.triangle.branch"
        case .start: return "play.circle.fill"
        case .end: return "stop.circle.fill"
        case .subflow: return "arrow.down.doc.fill"
        }
    }
    
    private var nodeTitle: String {
        if let title = optionalText(node.title) {
            return title
        }
        if node.type == .agent, let agent = agent {
            return agent.name
        }
        
        switch node.type {
        case .agent: return "Agent"
        case .branch: return "Branch"
        case .start: return "Start"
        case .end: return "End"
        case .subflow: return "Subflow"
        }
    }
    
    private var nodeColor: Color {
        if isSelected {
            return .accentColor
        }
        switch node.type {
        case .agent: return accentColor ?? .blue
        case .branch: return .orange
        case .start: return .green
        case .end: return .red
        case .subflow: return .purple
        }
    }
    
    private var nodeBackground: Color {
        if isSelected {
            return nodeColor.opacity(0.15)
        }
        switch node.type {
        case .agent: return nodeColor.opacity(0.1)
        case .branch: return Color.orange.opacity(0.1)
        case .start: return Color.green.opacity(0.08)
        case .end: return Color.red.opacity(0.08)
        case .subflow: return Color.purple.opacity(0.08)
        }
    }
    
    private var borderColor: Color {
        if isSelected {
            return nodeColor
        }
        if appState.boundary(for: node.id) != nil {
            return Color.orange.opacity(0.75)
        }
        if isHovered {
            return nodeColor.opacity(0.7)
        }
        return nodeColor.opacity(0.4)
    }
    
    private var nodeWidth: CGFloat {
        switch node.type {
        case .agent: return 110
        case .branch: return 110
        case .subflow: return 130
        default: return 90
        }
    }
    
    private var nodeHeight: CGFloat {
        switch node.type {
        case .subflow: return 75
        default: return 65
        }
    }

    private func optionalText(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// 嵌套层级徽章
struct NestingLevelBadge: View {
    let level: Int
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<level, id: \.self) { _ in
                Image(systemName: "square.fill")
                    .font(.system(size: 4))
            }
        }
        .foregroundColor(.orange)
        .offset(x: -35, y: -28)
    }
}
