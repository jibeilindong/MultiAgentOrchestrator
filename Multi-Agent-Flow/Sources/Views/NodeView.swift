//
//  NodeView.swift
//  Multi-Agent-Flow
//
//  Created by 陈荣泽 on 2026/3/18.
//

import SwiftUI

struct NodeDisplayParts: Equatable {
    let primary: String
    let secondary: String?
    let sequence: String?

    static func parse(from rawTitle: String) -> NodeDisplayParts {
        let trimmed = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return NodeDisplayParts(primary: "", secondary: nil, sequence: nil)
        }

        let segments = trimmed
            .split(separator: "-", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        switch segments.count {
        case 3...:
            return NodeDisplayParts(
                primary: segments[0],
                secondary: segments[1],
                sequence: segments[2]
            )
        case 2:
            return NodeDisplayParts(
                primary: segments[0],
                secondary: segments[1],
                sequence: nil
            )
        default:
            return NodeDisplayParts(
                primary: segments[0],
                secondary: nil,
                sequence: nil
            )
        }
    }
}

struct NodeView: View {
    @ObservedObject private var localizationManager = LocalizationManager.shared
    let node: WorkflowNode
    let isSelected: Bool
    let agent: Agent?
    let incomingConnections: Int
    let outgoingConnections: Int
    let isInBoundary: Bool
    
    // 连接模式状态
    var isConnectingMode: Bool = false
    var isConnectSource: Bool = false
    var isBatchSource: Bool = false
    var isBatchTarget: Bool = false
    var hasBatchConflict: Bool = false
    var isRelatedToSelection: Bool = false
    
    // 回调函数
    var onTap: (() -> Void)?
    var accentColor: Color? = nil
    var textScale: CGFloat = 1
    var textColor: Color = .black

    @State private var isHovered: Bool = false
    @State private var pulseAnimation: Bool = false
    @State private var relationPulse: Bool = false
    
    var body: some View {
        nodeCard
    }

    private var nodeTitle: String {
        if let title = optionalText(node.title) {
            return title
        }
        if node.type == .agent, let agent = agent {
            return agent.name
        }
        
        switch node.type {
        case .start:
            switch localizationManager.currentLanguage {
            case .english: return "Start"
            case .traditionalChinese: return "開始"
            case .simplifiedChinese: return "开始"
            }
        case .agent:
            switch localizationManager.currentLanguage {
            case .english: return "Agent"
            case .traditionalChinese: return "節點"
            case .simplifiedChinese: return "节点"
            }
        }
    }

    private var nodeDisplayParts: NodeDisplayParts {
        NodeDisplayParts.parse(from: nodeTitle)
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
        if hasBatchConflict {
            return .red.opacity(0.92)
        }
        if isBatchSource {
            return .blue.opacity(0.88)
        }
        if isBatchTarget {
            return .green.opacity(0.85)
        }
        if isRelatedToSelection {
            return Color.yellow.opacity(0.92)
        }
        if isInBoundary {
            return Color.orange.opacity(0.75)
        }
        if isHovered {
            return nodeColor.opacity(0.7)
        }
        return nodeColor.opacity(0.4)
    }
    
    private var nodeWidth: CGFloat {
        switch node.type {
        case .start: return 134
        case .agent: return 148
        }
    }

    private var nodeHeight: CGFloat {
        switch node.type {
        case .start:
            return isConnectingMode && !isConnectSource ? 170 : 148
        case .agent:
            var height: CGFloat = 160
            if hasNoOutgoingConnections {
                height += 24
            }
            if isConnectingMode && !isConnectSource {
                height += 22
            }
            return height
        }
    }

    private var nodeCard: some View {
        VStack(spacing: 8) {
            if node.nestingLevel > 0 {
                NestingLevelBadge(level: node.nestingLevel)
            }

            nameStack
            sequenceBadge
            statDivider
            connectionCountLabel
            noOutgoingWarning
            connectionHint
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(width: nodeWidth, height: nodeHeight)
        .background(nodeBackgroundShape)
        .shadow(color: nodeShadowColor, radius: nodeShadowRadius, x: 0, y: nodeShadowYOffset)
        .overlay(relatedHighlightOverlay)
        .overlay(connectSourceOverlay)
        .overlay(alignment: .topTrailing) {
            batchRoleBadge
        }
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

    private var nameStack: some View {
        VStack(spacing: 4) {
            Text(nodeDisplayParts.primary)
                .font(.system(size: 13 * textScale, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .foregroundColor(textColor)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .tracking(0.2)

            if let secondary = nodeDisplayParts.secondary {
                Text(secondary)
                    .font(.system(size: 11 * textScale, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .foregroundColor(textColor.opacity(0.85))
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }
        }
    }

    @ViewBuilder
    private var sequenceBadge: some View {
        if let sequence = nodeDisplayParts.sequence {
            ZStack {
                Circle()
                    .fill(nodeColor.gradient)
                Circle()
                    .stroke(Color.white.opacity(0.65), lineWidth: 1.2)
                Text(sequence)
                    .font(.system(size: 13 * textScale, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(width: 34, height: 34)
            .shadow(color: nodeColor.opacity(0.28), radius: 6, x: 0, y: 3)
        }
    }

    private var connectionCountLabel: some View {
        HStack(spacing: 6) {
            connectionStatPill(
                label: inboundLabel,
                value: incomingConnections,
                color: nodeColor.opacity(0.18)
            )
            connectionStatPill(
                label: outboundLabel,
                value: outgoingConnections,
                color: nodeColor.opacity(0.12)
            )
        }
        .frame(maxWidth: .infinity)
    }

    private var statDivider: some View {
        Capsule()
            .fill(nodeColor.opacity(0.16))
            .frame(width: 44, height: 3)
    }

    private func connectionStatPill(label: String, value: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 8 * textScale, weight: .bold, design: .rounded))
                .foregroundColor(textColor.opacity(0.7))
            Text("\(value)")
                .font(.system(size: 9 * textScale, weight: .bold, design: .rounded))
                .foregroundColor(textColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color)
        .clipShape(Capsule())
    }

    private var noOutgoingWarning: some View {
        Group {
            if hasNoOutgoingConnections {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 8 * textScale, weight: .semibold))
                    Text(noOutgoingWarningText)
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
                    Text(connectHintText)
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
            .fill(Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        isRelatedToSelection && !isSelected ? Color.yellow.opacity(relationPulse ? 0.92 : 0.28) : Color.clear,
                        lineWidth: 2.5
                    )
                    .scaleEffect(isRelatedToSelection && !isSelected ? (relationPulse ? 1.035 : 1.0) : 1.0)
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

    @ViewBuilder
    private var batchRoleBadge: some View {
        if hasBatchConflict {
            batchBadge(text: "!", color: .red)
                .offset(x: -6, y: 6)
        } else if isBatchSource {
            batchBadge(text: batchBadgeText(kind: .source), color: .blue)
                .offset(x: -6, y: 6)
        } else if isBatchTarget {
            batchBadge(text: batchBadgeText(kind: .target), color: .green)
                .offset(x: -6, y: 6)
        }
    }

    private func batchBadge(text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 8 * textScale, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color)
            .clipShape(Capsule())
            .shadow(color: Color.black.opacity(0.12), radius: 3, x: 0, y: 1)
    }

    private enum BatchBadgeKind {
        case source
        case target
    }

    private func batchBadgeText(kind: BatchBadgeKind) -> String {
        switch localizationManager.currentLanguage {
        case .english:
            return kind == .source ? "From" : "To"
        case .traditionalChinese:
            return kind == .source ? "來源" : "目標"
        case .simplifiedChinese:
            return kind == .source ? "来源" : "目标"
        }
    }

    private var nodeShadowColor: Color {
        isSelected ? nodeColor.opacity(0.55) : (isRelatedToSelection ? Color.yellow.opacity(0.3) : (isHovered ? Color.black.opacity(0.15) : Color.black.opacity(0.08)))
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

    private var inboundLabel: String {
        switch localizationManager.currentLanguage {
        case .english:
            return "IN"
        case .traditionalChinese:
            return "入"
        case .simplifiedChinese:
            return "入"
        }
    }

    private var outboundLabel: String {
        switch localizationManager.currentLanguage {
        case .english:
            return "OUT"
        case .traditionalChinese:
            return "出"
        case .simplifiedChinese:
            return "出"
        }
    }

    private var noOutgoingWarningText: String {
        switch localizationManager.currentLanguage {
        case .english:
            return "No outbound route"
        case .traditionalChinese:
            return "無出口，無法回傳消息"
        case .simplifiedChinese:
            return "无出口，无法回传消息"
        }
    }

    private var connectHintText: String {
        switch localizationManager.currentLanguage {
        case .english:
            return "Tap to link"
        case .traditionalChinese:
            return "點擊連接"
        case .simplifiedChinese:
            return "点击连接"
        }
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
