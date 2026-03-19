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
    
    // 连接模式状态
    var isConnectingMode: Bool = false
    var isConnectSource: Bool = false
    
    // 回调函数
    var onTap: (() -> Void)?
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
            
            // 节点图标和标题
            HStack(spacing: 4) {
                Image(systemName: nodeTypeIcon)
                    .font(.title3)
                    .foregroundColor(nodeColor)

                Text(nodeTitle)
                    .font(.system(size: 12 * textScale))
                    .lineLimit(1)
                    .foregroundColor(textColor)
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
        .onTapGesture(count: 1) {
            onTap?()
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
        case .start: return "play.circle.fill"
        case .agent: return "person.circle.fill"
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
        case .start: return "Start"
        case .agent: return "Agent"
        }
    }
    
    private var nodeColor: Color {
        if isSelected {
            return .accentColor
        }
        switch node.type {
        case .start: return .orange
        case .agent: return accentColor ?? .blue
        }
    }
    
    private var nodeBackground: Color {
        if isSelected {
            return nodeColor.opacity(0.15)
        }
        switch node.type {
        case .start: return Color.orange.opacity(0.12)
        case .agent: return nodeColor.opacity(0.1)
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
        case .start: return 100
        case .agent: return 110
        }
    }

    private var nodeHeight: CGFloat {
        switch node.type {
        case .start: return 60
        case .agent: return 65
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
