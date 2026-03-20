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
    let incomingConnections: Int
    let outgoingConnections: Int
    
    // 连接模式状态
    var isConnectingMode: Bool = false
    var isConnectSource: Bool = false
    var isRelatedToSelection: Bool = false
    
    // 回调函数
    var onTap: (() -> Void)?
    var accentColor: Color? = nil
    var textScale: CGFloat = 1
    var textColor: Color = .primary

    @State private var isHovered: Bool = false
    @State private var pulseAnimation: Bool = false
    @State private var relationPulse: Bool = false
    
    var body: some View {
        nodeCard
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
        if isRelatedToSelection {
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
        if isRelatedToSelection {
            return nodeColor.opacity(0.92)
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
        case .start: return 68
        case .agent: return hasNoOutgoingConnections ? 92 : 78
        }
    }

    private var nodeCard: some View {
        VStack(spacing: 3) {
            if node.nestingLevel > 0 {
                NestingLevelBadge(level: node.nestingLevel)
            }

            nodeHeader
            connectionCountLabel
            noOutgoingWarning
            connectionHint
        }
        .frame(width: nodeWidth, height: nodeHeight)
        .background(nodeBackgroundShape)
        .shadow(color: nodeShadowColor, radius: nodeShadowRadius, x: 0, y: nodeShadowYOffset)
        .overlay(relatedHighlightOverlay)
        .overlay(connectSourceOverlay)
        .onTapGesture(count: 1) {
            onTap?()
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
        .onChange(of: isConnectSource) { _, newValue in
            pulseAnimation = newValue
        }
        .scaleEffect(isSelected ? 1.05 : (isHovered ? 1.01 : 1.0))
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .animation(.easeInOut(duration: 0.1), value: isHovered)
        .onAppear {
            relationPulse = isRelatedToSelection
        }
        .onChange(of: isRelatedToSelection) { _, newValue in
            relationPulse = newValue
        }
    }

    private var nodeHeader: some View {
        HStack(spacing: 4) {
            Image(systemName: nodeTypeIcon)
                .font(.title3)
                .foregroundColor(nodeColor)

            Text(nodeTitle)
                .font(.system(size: 12 * textScale))
                .lineLimit(1)
                .foregroundColor(textColor)
        }
    }

    private var connectionCountLabel: some View {
        Text("In \(incomingConnections)  Out \(outgoingConnections)")
            .font(.system(size: 9 * textScale, weight: .medium, design: .rounded))
            .lineLimit(1)
            .foregroundColor(textColor.opacity(0.8))
            .minimumScaleFactor(0.75)
    }

    private var noOutgoingWarning: some View {
        Group {
            if hasNoOutgoingConnections {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 8 * textScale, weight: .semibold))
                    Text("无出口，无法反馈消息")
                        .font(.system(size: 8 * textScale, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .foregroundColor(.red.opacity(0.92))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.red.opacity(0.12))
                .cornerRadius(4)
            }
        }
    }

    private var connectionHint: some View {
        Group {
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
    }

    private var nodeBackgroundShape: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(nodeBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(borderColor, lineWidth: isSelected ? 4 : (isHovered ? 2 : 1))
            )
    }

    private var relatedHighlightOverlay: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(isRelatedToSelection && !isSelected ? Color.white.opacity(0.08) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        isRelatedToSelection && !isSelected ? nodeColor.opacity(relationPulse ? 0.5 : 0.18) : Color.clear,
                        lineWidth: 2
                    )
                    .scaleEffect(isRelatedToSelection && !isSelected ? (relationPulse ? 1.03 : 1.0) : 1.0)
                    .opacity(isRelatedToSelection && !isSelected ? (relationPulse ? 1.0 : 0.55) : 0)
                    .animation(
                        isRelatedToSelection && !isSelected
                            ? Animation.easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                            : .default,
                        value: relationPulse
                    )
            )
    }

    private var connectSourceOverlay: some View {
        RoundedRectangle(cornerRadius: 10)
            .stroke(isConnectSource ? Color.orange : Color.clear, lineWidth: 2)
            .scaleEffect(isConnectSource ? (pulseAnimation ? 1.05 : 1.0) : 1.0)
            .opacity(isConnectSource ? (pulseAnimation ? 0.6 : 1.0) : 0)
            .animation(
                isConnectSource
                    ? Animation.easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                    : .default,
                value: pulseAnimation
            )
    }

    private var nodeShadowColor: Color {
        isSelected ? nodeColor.opacity(0.55) : (isRelatedToSelection ? nodeColor.opacity(0.28) : (isHovered ? Color.black.opacity(0.15) : Color.black.opacity(0.08)))
    }

    private var nodeShadowRadius: CGFloat {
        isSelected ? 12 : (isHovered ? 6 : (isRelatedToSelection ? 8 : 3))
    }

    private var nodeShadowYOffset: CGFloat {
        isSelected ? 6 : (isHovered ? 3 : (isRelatedToSelection ? 4 : 2))
    }

    private var hasNoOutgoingConnections: Bool {
        node.type == .agent && outgoingConnections == 0
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
