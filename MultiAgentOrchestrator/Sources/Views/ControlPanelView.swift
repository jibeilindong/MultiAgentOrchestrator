//
//  ControlPanelView.swift
//  MultiAgentOrchestrator
//
//  Created by 陈荣泽 on 2026/3/18.
//

import SwiftUI

struct ControlPanelView: View {
    @EnvironmentObject var appState: AppState
    
    @State private var selectedTab = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // 标签页
            Picker("", selection: $selectedTab) {
                Label("Messages", systemImage: "message").tag(0)
                Label("Execution", systemImage: "play").tag(1)
                Label("Monitoring", systemImage: "chart.bar").tag(2)
            }
            .pickerStyle(.segmented)
            .padding()
            
            Divider()
            
            // 内容区域 - 使用条件显示替代TabView
            Group {
                switch selectedTab {
                case 0:
                    MessagesView(messageManager: appState.messageManager)
                        .environmentObject(appState)
                case 1:
                    ExecutionView()
                        .environmentObject(appState)
                case 2:
                    MonitoringView()
                        .environmentObject(appState)
                default:
                    MessagesView(messageManager: appState.messageManager)
                        .environmentObject(appState)
                }
            }
        }
    }
}

// 监控视图
struct MonitoringView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 系统状态
                systemStatusView
                
                // Agent状态
                agentStatusView
                
                // 实时统计
                realtimeStatsView
            }
            .padding()
        }
    }
    
    private var systemStatusView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LocalizedString.systemStatus)
                .font(.headline)
            
            HStack(spacing: 16) {
                StatusCard(
                    title: "Agents",
                    value: "\(appState.currentProject?.agents.count ?? 0)",
                    icon: "person.2.fill",
                    color: .blue,
                    status: .normal
                )
                
                StatusCard(
                    title: "Tasks",
                    value: "\(appState.taskManager.statistics.total)",
                    icon: "checklist",
                    color: .green,
                    status: appState.taskManager.statistics.blocked > 0 ? .warning : .normal
                )
                
                StatusCard(
                    title: "Messages",
                    value: "\(appState.messageManager.messages.count)",
                    icon: "message.fill",
                    color: .orange,
                    status: appState.messageManager.pendingApprovals.count > 0 ? .warning : .normal
                )
                
                StatusCard(
                    title: "Executions",
                    value: "\(appState.openClawService.executionResults.count)",
                    icon: "play.fill",
                    color: .purple,
                    status: .normal
                )
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    private var agentStatusView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LocalizedString.agentStatus)
                .font(.headline)
            
            if let agents = appState.currentProject?.agents, !agents.isEmpty {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    ForEach(agents) { agent in
                        AgentStatusCard(agent: agent, appState: appState)
                    }
                }
            } else {
                Text(LocalizedString.noAgentsAvailable)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 100)
                    .background(Color(.controlBackgroundColor))
                    .cornerRadius(8)
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    private var realtimeStatsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LocalizedString.realtimeStatistics)
                .font(.headline)
            
            HStack(spacing: 20) {
                StatProgressCard(
                    title: "Task Completion",
                    value: appState.taskManager.statistics.completionRate,
                    color: .green
                )
                
                StatProgressCard(
                    title: "Message Delivery",
                    value: messageDeliveryRate,
                    color: .blue
                )
                
                StatProgressCard(
                    title: "Execution Success",
                    value: executionSuccessRate,
                    color: .purple
                )
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    private var messageDeliveryRate: Double {
        let total = appState.messageManager.messages.count
        let delivered = appState.messageManager.messages.filter {
            $0.status == .delivered || $0.status == .read || $0.status == .approved
        }.count
        return total > 0 ? Double(delivered) / Double(total) : 0
    }
    
    private var executionSuccessRate: Double {
        let total = appState.openClawService.executionResults.count
        let completed = appState.openClawService.executionResults.filter {
            $0.status == .completed
        }.count
        return total > 0 ? Double(completed) / Double(total) : 0
    }
}

// 状态卡片
struct StatusCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    let status: Status
    
    enum Status {
        case normal
        case warning
        case error
        
        var color: Color {
            switch self {
            case .normal: return .green
            case .warning: return .orange
            case .error: return .red
            }
        }
        
        var icon: String {
            switch self {
            case .normal: return "checkmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .error: return "xmark.circle.fill"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Spacer()
                Image(systemName: status.icon)
                    .foregroundColor(status.color)
            }
            
            Text(value)
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.windowBackgroundColor))
        .cornerRadius(8)
    }
}

// Agent状态卡片
struct AgentStatusCard: View {
    let agent: Agent
    let appState: AppState
    
    private var taskStats: (total: Int, active: Int, completed: Int) {
        let tasks = appState.taskManager.tasks(for: agent.id)
        let total = tasks.count
        let active = tasks.filter { $0.isActive }.count
        let completed = tasks.filter { $0.isCompleted }.count
        return (total, active, completed)
    }
    
    private var messageStats: (sent: Int, received: Int, pending: Int) {
        let sent = appState.messageManager.messagesFromAgent(agent.id).count
        let received = appState.messageManager.messagesForAgent(agent.id).count
        let pending = appState.messageManager.pendingApprovals.filter { $0.fromAgentID == agent.id }.count
        return (sent, received, pending)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "person.circle.fill")
                    .foregroundColor(.blue)
                    .font(.title2)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(agent.name)
                        .font(.headline)
                        .lineLimit(1)
                    Text(agent.description)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
            }
            
            Divider()
            
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(LocalizedString.tasks)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("\(taskStats.active)/\(taskStats.total)")
                        .font(.caption)
                }
                
                Spacer()
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(LocalizedString.messages)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("\(messageStats.sent)/\(messageStats.received)")
                        .font(.caption)
                }
            }
            
            if messageStats.pending > 0 {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.caption2)
                        .foregroundColor(.orange)
                    Text("\(messageStats.pending) pending approvals")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.windowBackgroundColor))
        .cornerRadius(8)
    }
}

// 统计进度卡片
struct StatProgressCard: View {
    let title: String
    let value: Double
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            ZStack {
                Circle()
                    .stroke(color.opacity(0.2), lineWidth: 8)
                    .frame(width: 80, height: 80)
                
                Circle()
                    .trim(from: 0, to: CGFloat(value))
                    .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(-90))
                
                Text("\(Int(value * 100))%")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(color)
            }
            
            Text(value > 0.8 ? "Good" : value > 0.5 ? "Fair" : "Poor")
                .font(.caption)
                .foregroundColor(value > 0.8 ? .green : value > 0.5 ? .orange : .red)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.windowBackgroundColor))
        .cornerRadius(8)
    }
}
