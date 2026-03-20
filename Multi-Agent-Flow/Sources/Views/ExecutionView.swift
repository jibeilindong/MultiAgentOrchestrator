//
//  ExecutionView.swift
//  Multi-Agent-Flow
//
//  Created by 陈荣泽 on 2026/3/18.
//

import SwiftUI

struct ExecutionView: View {  // 这应该是 ExecutionView，不是 ContentView
    @EnvironmentObject var appState: AppState
    
    @State private var selectedWorkflowID: UUID?
    @State private var isExecuting = false
    @State private var showResults = false
    @State private var showLogs = false

    private var openClawService: OpenClawService {
        appState.openClawService
    }
    
    var workflows: [Workflow] {
        appState.currentProject?.workflows ?? []
    }
    
    var selectedWorkflow: Workflow? {
        if let id = selectedWorkflowID {
            return workflows.first { $0.id == id }
        }
        return nil
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 控制面板
            HStack {
                Text(LocalizedString.workflowEditor)
                    .font(.title2)
                
                Spacer()
                
                // 工作流选择器
                Picker(LocalizedString.text("workflow_picker_label"), selection: $selectedWorkflowID) {
                    Text(LocalizedString.selectWorkflow).tag(nil as UUID?)
                    ForEach(workflows) { workflow in
                        Text(workflow.name).tag(workflow.id as UUID?)
                    }
                }
                .frame(width: 200)
                
                Button(LocalizedString.text("execute_action")) {
                    executeWorkflow()
                }
                .disabled(selectedWorkflow == nil || isExecuting)
                .buttonStyle(.borderedProminent)
                
                Button(LocalizedString.text("clear_results_action")) {
                    openClawService.clearResults()
                    openClawService.clearLogs()
                }
                .disabled(openClawService.executionResults.isEmpty)
                
                Button(action: { showLogs.toggle() }) {
                    HStack {
                        Image(systemName: showLogs ? "doc.text.fill" : "doc.text")
                        Text(LocalizedString.logs)
                    }
                }
                .disabled(openClawService.executionLogs.isEmpty && !isExecuting)
            }
            .padding()
            
            Divider()
            
            if isExecuting {
                // 执行进度
                executionProgressView
            } else if showResults {
                // 执行结果
                executionResultsView
            } else {
                // 默认视图
                defaultView
            }
        }
    }
    
    private var executionProgressView: some View {
        HStack(spacing: 0) {
            // 左侧：进度信息
            VStack(spacing: 20) {
                ProgressView(value: Double(openClawService.currentStep), total: Double(openClawService.totalSteps)) {
                    Text(LocalizedString.executing)
                        .font(.headline)
                }
                .progressViewStyle(.linear)
                .padding()
                
                Text(LocalizedString.format("step_of_total", openClawService.currentStep, openClawService.totalSteps))
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if let workflow = selectedWorkflow {
                    if let currentNodeID = openClawService.currentNodeID,
                       let currentNode = workflow.nodes.first(where: { $0.id == currentNodeID }) {
                        if let agentID = currentNode.agentID,
                           let agent = appState.currentProject?.agents.first(where: { $0.id == agentID }) {
                            VStack {
                                Text(LocalizedString.format("executing_agent", agent.name))
                                    .font(.headline)
                                Text(LocalizedString.format("node_position", Int(currentNode.position.x), Int(currentNode.position.y)))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                
                // 连接状态指示
                connectionStatusView
            }
            .frame(maxWidth: showLogs ? .infinity : .infinity)
            
            // 右侧：实时日志（工部任务：实时日志输出）
            if showLogs {
                Divider()
                realTimeLogView
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var connectionStatusView: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(connectionStatusColor)
                .frame(width: 8, height: 8)
            Text(connectionStatusText)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(16)
    }
    
    private var connectionStatusColor: Color {
        switch openClawService.connectionStatus {
        case .connected: return .green
        case .connecting: return .yellow
        case .disconnected: return .gray
        case .error: return .red
        }
    }
    
    private var connectionStatusText: String {
        switch openClawService.connectionStatus {
        case .connected: return LocalizedString.text("connected_status")
        case .connecting: return LocalizedString.text("connecting_status")
        case .disconnected: return LocalizedString.text("disconnected_status")
        case .error(let msg): return LocalizedString.format("error_status", msg)
        }
    }
    
    // 实时日志面板（工部任务）
    private var realTimeLogView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(LocalizedString.executionLogs)
                    .font(.headline)
                Spacer()
                Button(LocalizedString.text("clear")) {
                    openClawService.clearLogs()
                }
                .font(.caption)
            }
            .padding()
            .background(Color(.windowBackgroundColor))
            
            Divider()
            
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(openClawService.executionLogs) { entry in
                            LogEntryView(entry: entry)
                                .id(entry.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: openClawService.executionLogs.count) { _, _ in
                    if let lastLog = openClawService.executionLogs.last {
                        withAnimation {
                            proxy.scrollTo(lastLog.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .background(Color(.textBackgroundColor))
    }
    
    private var executionResultsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if openClawService.executionResults.isEmpty {
                    ContentUnavailableView(
                        LocalizedString.text("no_execution_results"),
                        systemImage: "chart.bar",
                        description: Text(LocalizedString.executeWorkflowToSeeResults)
                    )
                } else {
                    // 统计摘要
                    resultSummaryView
                    
                    // 详细结果
                    ForEach(openClawService.executionResults) { result in
                        ExecutionResultView(result: result)
                    }
                }
            }
            .padding()
        }
    }
    
    private var resultSummaryView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LocalizedString.executionResults)
                .font(.headline)
            
            let total = openClawService.executionResults.count
            let completed = openClawService.executionResults.filter { $0.status == .completed }.count
            let failed = openClawService.executionResults.filter { $0.status == .failed }.count
            let successRate = total > 0 ? Double(completed) / Double(total) * 100 : 0
            
            HStack(spacing: 20) {
                StatCard(title: "Total", value: "\(total)", color: .primary)
                StatCard(title: "Completed", value: "\(completed)", color: .green)
                StatCard(title: "Failed", value: "\(failed)", color: .red)
                StatCard(title: "Success Rate", value: String(format: "%.1f%%", successRate),
                        color: successRate > 80 ? .green : .orange)
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    private var defaultView: some View {
        VStack(spacing: 30) {
            Image(systemName: "play.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.blue)
                .opacity(0.5)
            
            Text(LocalizedString.ok)
                .font(.title)
                .foregroundColor(.secondary)
            
            Text(LocalizedString.selectWorkflow)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            if let workflow = selectedWorkflow {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Selected Workflow: \(workflow.name)")
                        .font(.headline)
                    
                    let agentNodes = workflow.nodes.filter { $0.type == .agent }
                    Text("\(agentNodes.count) agent nodes, \(workflow.edges.count) connections")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(.controlBackgroundColor))
                .cornerRadius(8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func executeWorkflow() {
        guard let workflow = selectedWorkflow,
              let project = appState.currentProject else { return }
        
        isExecuting = true
        showResults = false
        
        appState.openClawService.executeWorkflow(
            workflow,
            agents: project.agents
        ) { _ in
            isExecuting = false
            showResults = true
        }
    }
}

// 日志条目视图（工部任务）
struct LogEntryView: View {
    let entry: ExecutionLogEntry
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(entry.timestamp.formatted(date: .omitted, time: .shortened))
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .leading)
            
            Text(entry.level.rawValue)
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(levelColor)
                .frame(width: 50)

            if let routingBadge = entry.routingBadge {
                Text(routingBadge)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(routingBadgeColor.opacity(0.14))
                    .foregroundColor(routingBadgeColor)
                    .clipShape(Capsule())
            }
            
            Text(entry.message)
                .font(.caption)
                .foregroundColor(entry.isRoutingEvent ? routingBadgeColor : .primary)
                .lineLimit(2)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(entry.isRoutingEvent ? routingBadgeColor.opacity(0.06) : Color.clear)
        .cornerRadius(8)
    }
    
    private var levelColor: Color {
        switch entry.level {
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        case .success: return .green
        }
    }

    private var routingBadgeColor: Color {
        switch entry.routingBadge {
        case "STOP": return .orange
        case "WARN", "MISS": return .red
        case "QUEUE": return .blue
        case "ROUTE": return .purple
        default: return .secondary
        }
    }
}
