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
                Text(LocalizedString.execution)
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

                Button(openClawService.isRunningTransportBenchmark ? "Benchmarking..." : "Run Benchmark") {
                    runTransportBenchmark()
                }
                .disabled(isExecuting || openClawService.isRunningTransportBenchmark)
                .buttonStyle(.bordered)
                
                Button(LocalizedString.text("clear_results_action")) {
                    openClawService.clearResults()
                    openClawService.clearLogs()
                }
                .disabled(openClawService.executionResults.isEmpty)
                
                Button(action: { showLogs.toggle() }) {
                    HStack {
                        Image(systemName: showLogs ? "doc.text.fill" : "doc.text")
                        Text(showLogs ? LocalizedString.text("hide_logs") : LocalizedString.text("show_logs"))
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
                if let report = openClawService.transportBenchmarkReport {
                    benchmarkSummaryView(report)
                }

                if openClawService.executionResults.isEmpty {
                    if openClawService.transportBenchmarkReport == nil {
                    ContentUnavailableView(
                        LocalizedString.text("no_execution_results"),
                        systemImage: "chart.bar",
                        description: Text(LocalizedString.executeWorkflowToSeeResults)
                    )
                    }
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
        return VStack(alignment: .leading, spacing: 12) {
            Text(LocalizedString.executionResults)
                .font(.headline)
            
            let total = openClawService.executionResults.count
            let completed = openClawService.executionResults.filter { $0.status == .completed }.count
            let failed = openClawService.executionResults.filter { $0.status == .failed }.count
            let successRate = total > 0 ? Double(completed) / Double(total) * 100 : 0
            let gatewayRuns = openClawService.executionResults.filter { ($0.transportKind ?? "").hasPrefix("gateway_") }.count
            let gatewayAdoption = total > 0 ? Double(gatewayRuns) / Double(total) * 100 : 0
            let workflowRuns = openClawService.executionResults.filter { result in
                let sessionID = result.sessionID?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
                return sessionID.hasPrefix("workflow-")
            }
            let hotPathRuns = workflowRuns.filter { ($0.transportKind ?? "").lowercased() == "gateway_agent" }.count
            let hotPathAdoption = workflowRuns.isEmpty ? 0 : Double(hotPathRuns) / Double(workflowRuns.count) * 100
            let hotPathMismatches = workflowRuns.filter { ($0.transportKind ?? "").lowercased() != "gateway_agent" }.count
            let firstResponseSamples = openClawService.executionResults.compactMap(\.firstChunkLatencyMs)
            let averageFirstResponseMs = firstResponseSamples.isEmpty
                ? nil
                : Double(firstResponseSamples.reduce(0, +)) / Double(firstResponseSamples.count)
            let runtimeEventCount = openClawService.executionResults.reduce(0) { partial, result in
                partial + result.runtimeEvents.count
            }
            
            HStack(spacing: 20) {
                StatCard(title: LocalizedString.text("execution_total"), value: "\(total)", color: .primary)
                StatCard(title: LocalizedString.text("execution_completed"), value: "\(completed)", color: .green)
                StatCard(title: LocalizedString.text("execution_failed_summary"), value: "\(failed)", color: .red)
                StatCard(title: LocalizedString.text("execution_success_rate"), value: String(format: "%.1f%%", successRate),
                        color: successRate > 80 ? .green : .orange)
                StatCard(title: "Gateway", value: String(format: "%.1f%%", gatewayAdoption),
                        color: gatewayAdoption >= 80 ? .green : .orange)
                StatCard(title: "Hot Path", value: workflowRuns.isEmpty ? "N/A" : String(format: "%.1f%%", hotPathAdoption),
                        color: workflowRuns.isEmpty ? .secondary : (hotPathAdoption >= 80 ? .green : .orange))
                StatCard(title: "Mismatch", value: "\(hotPathMismatches)",
                        color: hotPathMismatches == 0 ? .green : .red)
                StatCard(title: "首响", value: averageFirstResponseMs.map(formatLatency) ?? "N/A",
                        color: (averageFirstResponseMs ?? 9999) <= 1200 ? .green : .orange)
                StatCard(title: "Protocol", value: "\(runtimeEventCount)", color: runtimeEventCount > 0 ? .purple : .secondary)
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func benchmarkSummaryView(_ report: TransportBenchmarkReport) -> some View {
        let sortedSummaries = report.summaries.sorted { lhs, rhs in
            switch (lhs.averageCompletionLatencyMs, rhs.averageCompletionLatencyMs) {
            case let (left?, right?):
                return left < right
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return lhs.transport.displayName < rhs.transport.displayName
            }
        }
        let cliSummary = benchmarkSummary(for: .cli, in: report)
        let fastestSummary = sortedSummaries.first { $0.averageCompletionLatencyMs != nil }

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Transport Benchmark")
                    .font(.headline)
                Spacer()
                Text(report.deploymentKind.title)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.14))
                    .foregroundColor(.blue)
                    .clipShape(Capsule())
            }

            Text("Agent: \(report.agentIdentifier) | Iterations: \(report.iterationsPerTransport)")
                .font(.caption)
                .foregroundColor(.secondary)

            if let cliSummary {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Vs CLI")
                        .font(.subheadline)

                    ForEach(sortedSummaries.filter { $0.transport != .cli }) { summary in
                        HStack(spacing: 12) {
                            Text(summary.transport.displayName)
                                .font(.caption)
                                .frame(width: 120, alignment: .leading)

                            Text(benchmarkComparisonLabel(summary: summary, baseline: cliSummary) ?? "Insufficient data")
                                .font(.caption)
                                .foregroundColor(benchmarkComparisonColor(summary: summary, baseline: cliSummary))

                            if let spreadLabel = benchmarkSpreadLabel(summary) {
                                Text(spreadLabel)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()
                        }
                    }
                }
                .padding(12)
                .background(Color.blue.opacity(0.08))
                .cornerRadius(10)
            }

            if let fastestSummary,
               let recommendation = benchmarkRecommendationLabel(summary: fastestSummary, baseline: cliSummary) {
                Text(recommendation)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let verificationNote = workflowHotPathVerificationNote(report: report) {
                Text(verificationNote)
                    .font(.caption)
                    .foregroundColor(workflowHotPathVerificationColor(report: report))
            }

            ForEach(sortedSummaries) { summary in
                HStack(spacing: 16) {
                    Text(summary.transport.displayName)
                        .font(.subheadline)
                        .frame(width: 120, alignment: .leading)

                    Text("Success \(summary.successCount)/\(summary.sampleCount)")
                        .font(.caption)
                        .foregroundColor(summary.failureCount == 0 ? .green : .orange)
                        .frame(width: 110, alignment: .leading)

                    Text("First \(summary.averageFirstChunkLatencyMs.map(formatLatency) ?? "N/A")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 110, alignment: .leading)

                    Text("Total \(summary.averageCompletionLatencyMs.map(formatLatency) ?? "N/A")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 110, alignment: .leading)

                    if let actualPathLabel = benchmarkActualPathLabel(
                        transport: summary.transport,
                        report: report
                    ) {
                        Text(actualPathLabel)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 140, alignment: .leading)
                    }

                    if let verificationLabel = benchmarkVerificationLabel(summary) {
                        Text(verificationLabel)
                            .font(.caption)
                            .foregroundColor(benchmarkVerificationColor(summary))
                            .frame(width: 88, alignment: .leading)
                    }

                    if let spreadLabel = benchmarkSpreadLabel(summary) {
                        Text(spreadLabel)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 120, alignment: .leading)
                    }

                    Spacer()
                }
                .padding(.vertical, 2)
            }

            if let reportFilePath = report.reportFilePath {
                Text(reportFilePath)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }

    private func benchmarkSummary(
        for transport: TransportBenchmarkKind,
        in report: TransportBenchmarkReport
    ) -> TransportBenchmarkSummary? {
        report.summaries.first { $0.transport == transport }
    }

    private func benchmarkComparisonLabel(
        summary: TransportBenchmarkSummary,
        baseline: TransportBenchmarkSummary
    ) -> String? {
        guard
            let baselineLatency = baseline.averageCompletionLatencyMs,
            let summaryLatency = summary.averageCompletionLatencyMs,
            baselineLatency > 0,
            summaryLatency > 0
        else {
            return nil
        }

        let ratio = baselineLatency / summaryLatency
        let improvement = (baselineLatency - summaryLatency) / baselineLatency * 100

        if ratio >= 1 {
            return String(format: "%.2fx faster (%.0f%% lower total)", ratio, improvement)
        }

        return String(format: "%.2fx slower (%.0f%% higher total)", 1 / ratio, abs(improvement))
    }

    private func benchmarkComparisonColor(
        summary: TransportBenchmarkSummary,
        baseline: TransportBenchmarkSummary
    ) -> Color {
        guard
            let baselineLatency = baseline.averageCompletionLatencyMs,
            let summaryLatency = summary.averageCompletionLatencyMs
        else {
            return .secondary
        }

        return summaryLatency <= baselineLatency ? .green : .orange
    }

    private func benchmarkSpreadLabel(_ summary: TransportBenchmarkSummary) -> String? {
        guard
            let fastest = summary.fastestCompletionLatencyMs,
            let slowest = summary.slowestCompletionLatencyMs
        else {
            return nil
        }

        return "Range \(formatLatency(Double(fastest)))-\(formatLatency(Double(slowest)))"
    }

    private func benchmarkActualPathLabel(
        transport: TransportBenchmarkKind,
        report: TransportBenchmarkReport
    ) -> String? {
        let actualKinds = Set(
            report.samples
                .filter { $0.transport == transport }
                .compactMap(\.actualTransportKind)
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        )
        guard !actualKinds.isEmpty else { return nil }
        return "Path " + actualKinds.sorted().joined(separator: ", ")
    }

    private func benchmarkVerificationLabel(_ summary: TransportBenchmarkSummary) -> String? {
        guard let expectedTransportKind = summary.expectedTransportKind else { return nil }
        if summary.expectedTransportMismatchCount > 0 {
            return "Mismatch \(summary.expectedTransportMismatchCount)"
        }
        if summary.expectedTransportMatchedCount > 0 {
            return "Verified"
        }
        if summary.actualTransportKinds.isEmpty {
            return nil
        }
        return "Expected \(expectedTransportKind)"
    }

    private func benchmarkVerificationColor(_ summary: TransportBenchmarkSummary) -> Color {
        if summary.expectedTransportMismatchCount > 0 {
            return .red
        }
        if summary.expectedTransportMatchedCount > 0 {
            return .green
        }
        return .secondary
    }

    private func workflowHotPathVerificationNote(report: TransportBenchmarkReport) -> String? {
        guard let summary = benchmarkSummary(for: .workflowHotPath, in: report) else { return nil }
        if summary.expectedTransportMismatchCount > 0 {
            return "Workflow hot path verification failed: expected gateway_agent, observed \(summary.actualTransportKinds.joined(separator: ", "))."
        }
        if summary.expectedTransportMatchedCount > 0 {
            return "Workflow hot path verified on gateway_agent."
        }
        return nil
    }

    private func workflowHotPathVerificationColor(report: TransportBenchmarkReport) -> Color {
        guard let summary = benchmarkSummary(for: .workflowHotPath, in: report) else { return .secondary }
        return benchmarkVerificationColor(summary)
    }

    private func benchmarkRecommendationLabel(
        summary: TransportBenchmarkSummary,
        baseline: TransportBenchmarkSummary?
    ) -> String? {
        guard let averageLatency = summary.averageCompletionLatencyMs else { return nil }

        if let baseline, let comparison = benchmarkComparisonLabel(summary: summary, baseline: baseline) {
            return "Recommended default: \(summary.transport.displayName) at \(formatLatency(averageLatency)), \(comparison)."
        }

        return "Recommended default: \(summary.transport.displayName) at \(formatLatency(averageLatency))."
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
                    Text(LocalizedString.format("selected_workflow", workflow.name))
                        .font(.headline)
                    
                    let agentNodes = workflow.nodes.filter { $0.type == .agent }
                    Text(LocalizedString.format("workflow_agent_connections_summary", agentNodes.count, workflow.edges.count))
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
            agents: project.agents,
            projectID: project.id,
            projectRuntimeSessionID: project.runtimeState.sessionID
        ) { _ in
            isExecuting = false
            showResults = true
        }
    }

    private func runTransportBenchmark() {
        openClawService.runTransportBenchmark { _ in
            showResults = true
        }
    }

    private func formatLatency(_ milliseconds: Double) -> String {
        if milliseconds >= 1000 {
            return String(format: "%.1fs", milliseconds / 1000.0)
        }
        return "\(Int(milliseconds.rounded()))ms"
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
