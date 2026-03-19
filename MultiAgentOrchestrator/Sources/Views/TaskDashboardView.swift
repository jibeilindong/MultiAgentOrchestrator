//
//  Untitled.swift
//  MultiAgentOrchestrator
//
//  Created by 陈荣泽 on 2026/3/18.
//

import SwiftUI
import Charts

struct MonitoringDashboardView: View {
    @EnvironmentObject var appState: AppState

    private var project: MAProject? { appState.currentProject }
    private var taskStats: TaskManager.TaskStatistics { appState.taskManager.statistics }
    private var executionState: ExecutionState? { appState.openClawService.executionState }
    private var recentTasks: [Task] {
        appState.taskManager.tasks.sorted { $0.createdAt > $1.createdAt }.prefix(8).map { $0 }
    }

    var body: some View {
        Group {
            if project == nil {
                ContentUnavailableView(
                    "先打开一个 Project",
                    systemImage: "gauge.with.dots.needle.33percent",
                    description: Text("仪表盘会基于当前 project 展示工作流运行态、任务状态和 OpenClaw 干预入口。")
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        overviewSection
                        executionSection
                        interventionSection
                        taskSection
                        resultsSection
                        logsSection
                    }
                    .padding()
                }
            }
        }
    }

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("全局状态")
                .font(.headline)

            HStack(spacing: 16) {
                monitoringCard(
                    title: "OpenClaw",
                    value: appState.openClawManager.isConnected ? "Connected" : "Disconnected",
                    detail: appState.openClawManager.config.deploymentSummary,
                    color: appState.openClawManager.isConnected ? .green : .red
                )
                monitoringCard(
                    title: "任务",
                    value: "\(taskStats.total)",
                    detail: "进行中 \(taskStats.inProgress) / 阻塞 \(taskStats.blocked)",
                    color: .blue
                )
                monitoringCard(
                    title: "执行",
                    value: appState.openClawService.isExecuting ? "Running" : "Idle",
                    detail: executionProgressText,
                    color: appState.openClawService.isExecuting ? .orange : .secondary
                )
                monitoringCard(
                    title: "记忆备份",
                    value: "\(project?.memoryData.taskExecutionMemories.count ?? 0)",
                    detail: "任务 \(project?.memoryData.taskExecutionMemories.count ?? 0) / Agent \(project?.memoryData.agentMemories.count ?? 0)",
                    color: .purple
                )
            }
        }
    }

    private var executionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("工作流运行态")
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                ProgressView(
                    value: Double(appState.openClawService.currentStep),
                    total: max(Double(appState.openClawService.totalSteps), 1)
                )
                .progressViewStyle(.linear)

                HStack(spacing: 8) {
                    monitoringPill(
                        title: executionProgressText,
                        color: appState.openClawService.isExecuting ? .orange : .green
                    )

                    if let executionState, executionState.isPaused {
                        monitoringPill(title: "已暂停", color: .red)
                    }

                    if let lastUpdated = project?.runtimeState.lastUpdated {
                        monitoringPill(
                            title: "更新于 \(lastUpdated.formatted(date: .omitted, time: .shortened))",
                            color: .secondary
                        )
                    }
                }

                if let workflow = project?.workflows.first {
                    Text("当前项目包含 \(workflow.nodes.filter { $0.type == .agent }.count) 个执行节点、\(workflow.edges.count) 条通信线、\(workflow.boundaries.count) 个文件边界。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color(.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var interventionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("干预操作")
                .font(.headline)

            HStack(spacing: 10) {
                Button(appState.openClawManager.isConnected ? "断开 OpenClaw" : "连接 OpenClaw") {
                    if appState.openClawManager.isConnected {
                        appState.openClawManager.disconnect()
                    } else {
                        appState.openClawManager.connect()
                    }
                }
                .buttonStyle(.borderedProminent)

                Button("检测连接") {
                    appState.openClawService.checkConnection()
                }
                .buttonStyle(.bordered)

                Button("暂停执行") {
                    appState.openClawService.pauseExecution()
                }
                .buttonStyle(.bordered)
                .disabled(!appState.openClawService.isExecuting)

                Button("恢复执行") {
                    appState.openClawService.resumeExecution()
                }
                .buttonStyle(.bordered)
                .disabled(!(executionState?.canResume ?? false))

                Button("回滚检查点") {
                    appState.openClawService.rollbackToLastCheckpoint()
                }
                .buttonStyle(.bordered)
                .disabled(executionState?.completedNodes.isEmpty ?? true)

                Button("项目设置") {
                    NotificationCenter.default.post(name: .openSettings, object: nil)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var taskSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("任务监控")
                .font(.headline)

            VStack(spacing: 10) {
                ForEach(recentTasks) { task in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(task.title)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text(task.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }

                        Spacer()

                        monitoringPill(title: task.status.rawValue, color: task.status.color)

                        Button("进行中") {
                            appState.taskManager.moveTask(task.id, to: .inProgress)
                        }
                        .buttonStyle(.borderless)

                        Button("完成") {
                            appState.taskManager.moveTask(task.id, to: .done)
                        }
                        .buttonStyle(.borderless)

                        Button("阻塞") {
                            appState.taskManager.moveTask(task.id, to: .blocked)
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(10)
                    .background(Color(.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
    }

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("最近执行结果")
                .font(.headline)

            VStack(spacing: 8) {
                if appState.openClawService.executionResults.isEmpty {
                    Text("当前没有执行结果。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(appState.openClawService.executionResults.suffix(6).reversed()) { result in
                        HStack {
                            Text(result.status.rawValue)
                                .font(.caption)
                                .foregroundColor(result.status == .completed ? .green : .red)
                                .frame(width: 80, alignment: .leading)
                            Text(result.output.isEmpty ? "无输出" : result.output)
                                .font(.caption)
                                .lineLimit(2)
                            Spacer()
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .padding()
            .background(Color(.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var logsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("实时日志")
                    .font(.headline)
                Spacer()
                Button("清空日志") {
                    appState.openClawService.clearLogs()
                }
                .buttonStyle(.borderless)
            }

            VStack(spacing: 6) {
                if appState.openClawService.executionLogs.isEmpty {
                    Text("当前没有日志。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(appState.openClawService.executionLogs.suffix(30).reversed()) { entry in
                        HStack(alignment: .top, spacing: 8) {
                            Text(entry.timestamp.formatted(date: .omitted, time: .standard))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .frame(width: 72, alignment: .leading)
                            Text(entry.level.rawValue)
                                .font(.caption2)
                                .foregroundColor(logColor(for: entry.level))
                                .frame(width: 56, alignment: .leading)
                            Text(entry.message)
                                .font(.caption)
                                .lineLimit(2)
                            Spacer()
                        }
                    }
                }
            }
            .padding()
            .background(Color(.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var executionProgressText: String {
        let totalSteps = appState.openClawService.totalSteps
        let currentStep = appState.openClawService.currentStep
        guard totalSteps > 0 else { return "未开始" }
        return "\(currentStep)/\(totalSteps) 步"
    }

    private func monitoringCard(title: String, value: String, detail: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(color)
            Text(detail)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func monitoringPill(title: String, color: Color) -> some View {
        Text(title)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .foregroundColor(color)
            .clipShape(Capsule())
    }

    private func logColor(for level: ExecutionLogEntry.LogLevel) -> Color {
        switch level {
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        case .success: return .green
        }
    }
}

struct TaskDashboardView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var taskManager: TaskManager
    
    @State private var selectedTimeRange: TimeRange = .week
    @State private var showingAgentStats = false
    
    enum TimeRange: String, CaseIterable {
        case day = "Day"
        case week = "Week"
        case month = "Month"
        case all = "All Time"
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 概览卡片
                overviewCards
                
                // 图表区域
                chartSection
                
                // Agent 统计
                agentStatsSection
                
                // 最近活动
                recentActivitySection
            }
            .padding()
        }
        .navigationTitle("Task Dashboard")
        .toolbar {
            ToolbarItem {
                Picker("Time Range", selection: $selectedTimeRange) {
                    ForEach(TimeRange.allCases, id: \.self) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
            }
        }
    }
    
    // MARK: - 子视图
    
    private var overviewCards: some View {
        HStack(spacing: 16) {
            DashboardStatCard(  // 使用重命名后的名称
                title: "Completion Rate",
                value: "\(Int(taskManager.statistics.completionRate * 100))%",
                icon: "checkmark.circle.fill",
                color: taskManager.statistics.completionRate > 0.7 ? .green : .orange,
                trend: .up(15)
            )
            
            DashboardStatCard(  // 使用重命名后的名称
                title: "Avg. Completion Time",
                value: formatDuration(taskManager.statistics.averageCompletionTime),
                icon: "clock.fill",
                color: .blue,
                trend: .down(8)
            )
            
            DashboardStatCard(  // 使用重命名后的名称
                title: "Active Tasks",
                value: "\(taskManager.statistics.inProgress)",
                icon: "arrow.triangle.2.circlepath",
                color: .blue,
                trend: .steady
            )
            
            DashboardStatCard(  // 使用重命名后的名称
                title: "Blocked Tasks",
                value: "\(taskManager.statistics.blocked)",
                icon: "exclamationmark.triangle",
                color: .red,
                trend: .up(3)
            )
        }
    }
    
    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LocalizedString.taskStatus)
                .font(.headline)
            
            Chart {
                ForEach(TaskStatus.allCases, id: \.self) { status in
                    SectorMark(
                        angle: .value("Count", taskManager.tasks(for: status).count),
                        innerRadius: .ratio(0.6),
                        angularInset: 1
                    )
                    .foregroundStyle(status.color)
                    .annotation(position: .overlay) {
                        Text("\(taskManager.tasks(for: status).count)")
                            .font(.caption)
                            .foregroundColor(.white)
                    }
                }
            }
            .frame(height: 200)
            .chartLegend(position: .bottom)
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    private var agentStatsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(LocalizedString.agent + " " + LocalizedString.performance)
                    .font(.headline)
                Spacer()
                Button("Show Details") {
                    showingAgentStats = true
                }
                .font(.caption)
            }
            
            if let agents = appState.currentProject?.agents, !agents.isEmpty {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    ForEach(agents.prefix(6)) { agent in
                        AgentStatCard(agent: agent, taskManager: taskManager)
                    }
                }
            } else {
                Text(LocalizedString.noAgents)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 100)
                    .background(Color(.controlBackgroundColor))
                    .cornerRadius(8)
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
        .sheet(isPresented: $showingAgentStats) {
            AgentStatsDetailView(agents: appState.currentProject?.agents ?? [], taskManager: taskManager)
        }
    }
    
    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LocalizedString.actions)
                .font(.headline)
            
            VStack(spacing: 8) {
                ForEach(taskManager.tasks.sorted(by: { $0.createdAt > $1.createdAt }).prefix(5)) { task in
                    ActivityRow(task: task)
                }
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    // MARK: - 辅助方法
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        if duration < 60 {
            return "\(Int(duration))s"
        } else if duration < 3600 {
            return "\(Int(duration / 60))m"
        } else {
            return "\(Int(duration / 3600))h"
        }
    }
}

// MARK: - 辅助视图

struct DashboardStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    let trend: Trend
    
    enum Trend {
        case up(Int)
        case down(Int)
        case steady
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Spacer()
                trendIndicator
            }
            
            Text(value)
                .font(.title)
                .fontWeight(.bold)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 100)
        .background(Color(.windowBackgroundColor))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    private var trendIndicator: some View {
        Group {
            switch trend {
            case .up(let percent):
                HStack(spacing: 2) {
                    Image(systemName: "arrow.up")
                    Text("\(percent)%")
                }
                .font(.caption2)
                .foregroundColor(.green)
            case .down(let percent):
                HStack(spacing: 2) {
                    Image(systemName: "arrow.down")
                    Text("\(percent)%")
                }
                .font(.caption2)
                .foregroundColor(.red)
            case .steady:
                Text("—")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
        }
    }
}

struct AgentStatCard: View {
    let agent: Agent
    let taskManager: TaskManager
    
    private var agentTasks: [Task] {
        taskManager.tasks(for: agent.id)
    }
    
    private var completedTasks: Int {
        agentTasks.filter { $0.isCompleted }.count
    }
    
    private var completionRate: Double {
        agentTasks.isEmpty ? 0 : Double(completedTasks) / Double(agentTasks.count)
    }
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.circle.fill")
                .font(.title)
                .foregroundColor(.blue)
            
            Text(agent.name)
                .font(.caption)
                .lineLimit(1)
            
            Text("\(agentTasks.count) tasks")
                .font(.caption2)
                .foregroundColor(.secondary)
            
            ProgressView(value: completionRate)
                .progressViewStyle(.linear)
                .frame(width: 60)
            
            Text("\(Int(completionRate * 100))%")
                .font(.caption2)
                .foregroundColor(completionRate > 0.7 ? .green : .orange)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.windowBackgroundColor))
        .cornerRadius(8)
    }
}

struct ActivityRow: View {
    let task: Task
    
    var body: some View {
        HStack {
            Image(systemName: task.status.icon)
                .foregroundColor(task.status.color)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.caption)
                    .lineLimit(1)
                Text("\(task.status.rawValue) • \(task.createdAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text(task.priority.rawValue)
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(task.priority.color.opacity(0.2)))
                .foregroundColor(task.priority.color)
        }
        .padding(.vertical, 4)
    }
}

struct AgentStatsDetailView: View {
    let agents: [Agent]
    let taskManager: TaskManager
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            List(agents) { agent in
                AgentDetailRow(agent: agent, taskManager: taskManager)
            }
            .navigationTitle("Agent Performance")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .frame(minWidth: 400, minHeight: 500)
        }
    }
}

struct AgentDetailRow: View {
    let agent: Agent
    let taskManager: TaskManager
    
    private var agentTasks: [Task] {
        taskManager.tasks(for: agent.id)
    }
    
    private var stats: (total: Int, todo: Int, inProgress: Int, done: Int, blocked: Int) {
        let total = agentTasks.count
        let todo = agentTasks.filter { $0.status == .todo }.count
        let inProgress = agentTasks.filter { $0.status == .inProgress }.count
        let done = agentTasks.filter { $0.status == .done }.count
        let blocked = agentTasks.filter { $0.status == .blocked }.count
        
        return (total, todo, inProgress, done, blocked)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "person.circle.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading) {
                    Text(agent.name)
                        .font(.headline)
                    Text(agent.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                Spacer()
                
                Text("\(stats.total) tasks")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.blue.opacity(0.2)))
            }
            
            HStack(spacing: 16) {
                StatPill(count: stats.todo, label: "To Do", color: .gray)
                StatPill(count: stats.inProgress, label: "In Progress", color: .blue)
                StatPill(count: stats.done, label: "Done", color: .green)
                StatPill(count: stats.blocked, label: "Blocked", color: .red)
            }
        }
        .padding(.vertical, 8)
    }
}

struct StatPill: View {
    let count: Int
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(.headline)
                .foregroundColor(color)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(width: 60)
    }
}
