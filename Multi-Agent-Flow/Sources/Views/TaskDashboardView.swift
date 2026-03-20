//
//  Untitled.swift
//  Multi-Agent-Flow
//
//  Created by 陈荣泽 on 2026/3/18.
//

import SwiftUI
import Charts

private enum OpsCenterPage: String, CaseIterable, Identifiable {
    case liveOverview
    case projectHistory

    var id: String { rawValue }

    var title: String {
        switch self {
        case .liveOverview: return "Live Ops"
        case .projectHistory: return "Project History"
        }
    }
}

struct MonitoringDashboardView: View {
    @EnvironmentObject var appState: AppState
    @State private var metrics = DashboardMetrics()
    @State private var opsSnapshot: OpsAnalyticsSnapshot = .empty
    @State private var pendingMetricsRefreshWorkItem: DispatchWorkItem?
    @State private var selectedOpsCenterPage: OpsCenterPage = .liveOverview
    @State private var selectedHistoryCategory: OpsHistoryCategory = .all
    @State private var selectedHistoryWindow: OpsHistoryWindow = .last30Days
    @State private var selectedHistoryMetric: OpsHistoryMetric = .workflowReliability
    @State private var selectedTracePanel: OpsTracePanelModel?

    private var project: MAProject? { appState.currentProject }
    private var taskStats: TaskManager.TaskStatistics { appState.taskManager.statistics }
    private var executionState: ExecutionState? { appState.openClawService.executionState }
    private let metricsRefreshDebounce: TimeInterval = 0.25
    private let historyCalendar = Calendar.autoupdatingCurrent

    private var recentTasks: [Task] {
        appState.taskManager.tasks.sorted { $0.createdAt > $1.createdAt }.prefix(8).map { $0 }
    }
    private var conversationTotalCount: Int {
        metrics.conversationTotalCount
    }
    private var agentConversationRows: [DashboardAgentConversationRow] {
        metrics.agentConversationRows
    }
    private var modelTokenRows: [DashboardModelTokenUsageRow] {
        metrics.modelTokenRows
    }
    private var totalTokenCount: Int {
        metrics.totalTokenCount
    }
    private var activeAgentCount: Int {
        metrics.activeAgentCount
    }
    private var idleAgentCount: Int {
        metrics.idleAgentCount
    }
    private var filteredHistoricalSeries: [OpsMetricHistorySeries] {
        let cutoffDate = historyCalendar.date(
            byAdding: .day,
            value: -(selectedHistoryWindow.rawValue - 1),
            to: historyCalendar.startOfDay(for: Date())
        ) ?? .distantPast

        return opsSnapshot.historicalSeries
            .filter { series in
                selectedHistoryCategory == .all || series.metric.category == selectedHistoryCategory
            }
            .map { series in
                OpsMetricHistorySeries(
                    metric: series.metric,
                    points: series.points.filter { $0.date >= cutoffDate }
                )
            }
    }
    private var effectiveSelectedHistoryMetric: OpsHistoryMetric {
        filteredHistoricalSeries.first(where: { $0.metric == selectedHistoryMetric })?.metric
            ?? filteredHistoricalSeries.first?.metric
            ?? selectedHistoryMetric
    }
    private var selectedHistorySeries: OpsMetricHistorySeries? {
        filteredHistoricalSeries.first { $0.metric == effectiveSelectedHistoryMetric }
    }
    private var dashboardRefreshSignature: String {
        let projectSignature = project.map {
            [
                $0.id.uuidString,
                "\($0.agents.count)",
                "\($0.workflows.count)",
                $0.updatedAt.timeIntervalSinceReferenceDate.formatted()
            ].joined(separator: ":")
        } ?? "no-project"
        let messageSignature = appState.messageManager.messages.last.map {
            "\($0.id.uuidString):\($0.content.count):\($0.timestamp.timeIntervalSinceReferenceDate)"
        } ?? "no-messages"
        let taskSignature = appState.taskManager.tasks.last.map {
            "\($0.id.uuidString):\($0.status.rawValue):\($0.createdAt.timeIntervalSinceReferenceDate)"
        } ?? "no-tasks"
        let activeAgentSignature = appState.openClawManager.activeAgents.values
            .sorted { $0.agentID.uuidString < $1.agentID.uuidString }
            .map { "\($0.agentID.uuidString):\($0.status)" }
            .joined(separator: "|")

        return [
            projectSignature,
            messageSignature,
            taskSignature,
            activeAgentSignature,
            String(appState.openClawManager.isConnected)
        ].joined(separator: "::")
    }

    var body: some View {
        Group {
            if project == nil {
                ContentUnavailableView(
                    LocalizedString.text("open_project_first"),
                    systemImage: "gauge.with.dots.needle.33percent",
                    description: Text(LocalizedString.text("open_project_first_dashboard_desc"))
                )
            } else if !appState.openClawManager.isConnected {
                VStack(spacing: 16) {
                    Image(systemName: "cable.connector")
                        .font(.system(size: 44))
                        .foregroundColor(.accentColor)

                    Text(LocalizedString.text("connect_openclaw_first"))
                        .font(.title3)
                        .fontWeight(.semibold)

                    Text(LocalizedString.text("connect_openclaw_first_dashboard_desc"))
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 520)

                    HStack(spacing: 12) {
                        Button(LocalizedString.text("connect_openclaw")) {
                            appState.connectOpenClaw()
                        }
                        .buttonStyle(.borderedProminent)

                        Button(LocalizedString.text("open_settings")) {
                            NotificationCenter.default.post(name: .openSettings, object: nil)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(32)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        opsCenterHeaderSection
                        if selectedOpsCenterPage == .liveOverview {
                            opsOverviewSection
                            opsDailyActivitySection
                            opsCronReliabilitySection
                            opsAgentHealthSection
                        } else {
                            opsProjectHistorySection
                        }
                        opsTraceSection
                        overviewSection
                        conversationMonitoringSection
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
        .onAppear {
            opsSnapshot = appState.opsAnalytics.snapshot
            scheduleMetricsRefresh(immediately: true)
        }
        .onReceive(appState.opsAnalytics.$snapshot) { snapshot in
            opsSnapshot = snapshot
        }
        .onChange(of: dashboardRefreshSignature) { _, _ in
            scheduleMetricsRefresh(immediately: false)
        }
        .onDisappear {
            pendingMetricsRefreshWorkItem?.cancel()
            pendingMetricsRefreshWorkItem = nil
        }
        .sheet(item: $selectedTracePanel) { panel in
            OpsTraceDetailSheet(panel: panel)
        }
    }

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LocalizedString.text("global_status"))
                .font(.headline)

            HStack(spacing: 16) {
                monitoringCard(
                    title: "OpenClaw",
                    value: appState.openClawManager.isConnected ? LocalizedString.text("connected_status") : LocalizedString.text("disconnected_status"),
                    detail: appState.openClawManager.config.deploymentSummary,
                    color: appState.openClawManager.isConnected ? .green : .red
                )
                monitoringCard(
                    title: LocalizedString.tasks,
                    value: "\(taskStats.total)",
                    detail: "\(LocalizedString.text("mark_in_progress")) \(taskStats.inProgress) / \(LocalizedString.text("mark_blocked")) \(taskStats.blocked)",
                    color: .blue
                )
                monitoringCard(
                    title: LocalizedString.execution,
                    value: appState.openClawService.isExecuting ? LocalizedString.text("running_status") : LocalizedString.text("idle_status"),
                    detail: executionProgressText,
                    color: appState.openClawService.isExecuting ? .orange : .secondary
                )
                monitoringCard(
                    title: LocalizedString.text("memory_backup"),
                    value: "\(project?.memoryData.taskExecutionMemories.count ?? 0)",
                    detail: "\(LocalizedString.tasks) \(project?.memoryData.taskExecutionMemories.count ?? 0) / \(LocalizedString.agent) \(project?.memoryData.agentMemories.count ?? 0)",
                    color: .purple
                )
            }
        }
    }

    private var opsCenterHeaderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Ops Center")
                    .font(.headline)

                Spacer()

                if opsSnapshot.generatedAt != .distantPast {
                    Text("Updated \(opsSnapshot.generatedAt.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Picker("Ops Center Page", selection: $selectedOpsCenterPage) {
                ForEach(OpsCenterPage.allCases) { page in
                    Text(page.title).tag(page)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var opsOverviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Current Posture")
                .font(.headline)

            if opsSnapshot.goalCards.isEmpty {
                Text("Ops analytics will appear after a project is loaded.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16)], spacing: 16) {
                    ForEach(opsSnapshot.goalCards) { card in
                        monitoringCard(
                            title: card.title,
                            value: card.valueText,
                            detail: card.detailText,
                            color: opsColor(for: card.status)
                        )
                    }
                }
            }
        }
    }

    private var opsProjectHistorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Project History")
                        .font(.headline)
                    Text("OA CLI-inspired project metrics with runtime and cron history overlays.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            HStack(spacing: 12) {
                Picker("History Category", selection: $selectedHistoryCategory) {
                    ForEach(OpsHistoryCategory.allCases) { category in
                        Text(category.title).tag(category)
                    }
                }
                .pickerStyle(.segmented)

                Picker("History Window", selection: $selectedHistoryWindow) {
                    ForEach(OpsHistoryWindow.allCases) { window in
                        Text(window.title).tag(window)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 180)
            }

            if filteredHistoricalSeries.allSatisfy({ $0.points.isEmpty }) {
                Text("Project history will populate after the first analytics sync.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16)], spacing: 16) {
                    ForEach(filteredHistoricalSeries) { series in
                        Button {
                            selectedHistoryMetric = series.metric
                        } label: {
                            historyMetricCard(series: series, isSelected: effectiveSelectedHistoryMetric == series.metric)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let series = selectedHistorySeries, !series.points.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(series.metric.windowDescription)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Chart {
                            ForEach(series.points) { point in
                                AreaMark(
                                    x: .value("Day", point.date, unit: .day),
                                    y: .value(series.metric.title, point.value)
                                )
                                .interpolationMethod(.catmullRom)
                                .foregroundStyle(historyColor(for: series.metric).opacity(0.14))

                                LineMark(
                                    x: .value("Day", point.date, unit: .day),
                                    y: .value(series.metric.title, point.value)
                                )
                                .interpolationMethod(.catmullRom)
                                .foregroundStyle(historyColor(for: series.metric))
                                .lineStyle(StrokeStyle(lineWidth: 2.5))

                                PointMark(
                                    x: .value("Day", point.date, unit: .day),
                                    y: .value(series.metric.title, point.value)
                                )
                                .foregroundStyle(historyColor(for: series.metric))
                            }
                        }
                        .chartYAxis {
                            AxisMarks(position: .leading)
                        }
                        .frame(height: 260)

                        HStack(spacing: 16) {
                            historyStatPill(
                                title: "Latest",
                                value: series.latestPoint.map { series.metric.formattedValue($0.value) } ?? "-"
                            )
                            historyStatPill(
                                title: "Previous",
                                value: series.previousPoint.map { series.metric.formattedValue($0.value) } ?? "-"
                            )
                            historyStatPill(
                                title: "Delta",
                                value: historyDeltaText(for: series)
                            )
                        }
                    }
                    .padding()
                    .background(Color(.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }

    private var opsCronReliabilitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Cron Reliability")
                        .font(.headline)
                    Text("External OpenClaw scheduled runs ingested from backup artifacts.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if let latestRunAt = opsSnapshot.cronSummary?.latestRunAt {
                    Text("Latest \(latestRunAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if let summary = opsSnapshot.cronSummary {
                HStack(spacing: 16) {
                    monitoringCard(
                        title: "Success Rate",
                        value: "\(Int(summary.successRate.rounded()))%",
                        detail: "\(summary.successfulRuns) successful runs",
                        color: summary.successRate >= 90 ? .green : (summary.successRate >= 75 ? .orange : .red)
                    )
                    monitoringCard(
                        title: "Failed Runs",
                        value: "\(summary.failedRuns)",
                        detail: "Last 14 days",
                        color: summary.failedRuns == 0 ? .green : .red
                    )
                    monitoringCard(
                        title: "Recent Runs",
                        value: "\(opsSnapshot.cronRuns.count)",
                        detail: "Showing latest ingested executions",
                        color: .blue
                    )
                }

                VStack(spacing: 8) {
                    ForEach(opsSnapshot.cronRuns) { row in
                        HStack(alignment: .top, spacing: 10) {
                            Text(row.runAt.formatted(date: .omitted, time: .standard))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .frame(width: 72, alignment: .leading)

                            monitoringPill(
                                title: row.statusText,
                                color: row.statusText == "OK" ? .green : .red
                            )
                            .frame(width: 78, alignment: .leading)

                            Text(row.cronName)
                                .font(.caption)
                                .frame(width: 110, alignment: .leading)

                            Text(row.duration.map(formatOpsDuration) ?? "-")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 56, alignment: .leading)

                            Text(row.deliveryStatus ?? "-")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .frame(width: 76, alignment: .leading)

                            Text(row.summaryText)
                                .font(.caption)
                                .lineLimit(2)

                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
                .padding()
                .background(Color(.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                Text("No external cron runs have been discovered yet.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private var opsDailyActivitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Reliability Trend")
                .font(.headline)

            if opsSnapshot.dailyActivity.isEmpty {
                Text("No historical execution activity is available yet.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                Chart {
                    ForEach(opsSnapshot.dailyActivity) { point in
                        BarMark(
                            x: .value("Day", point.date, unit: .day),
                            y: .value("Completed", point.completedCount)
                        )
                        .foregroundStyle(Color.green.gradient)

                        BarMark(
                            x: .value("Day", point.date, unit: .day),
                            y: .value("Failed", point.failedCount)
                        )
                        .foregroundStyle(Color.red.gradient)

                        LineMark(
                            x: .value("Day", point.date, unit: .day),
                            y: .value("Errors", point.errorCount)
                        )
                        .foregroundStyle(Color.orange)
                        .symbol(.circle)
                    }
                }
                .frame(height: 220)
                .padding()
                .background(Color(.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private var opsAgentHealthSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Agent Health")
                .font(.headline)

            VStack(spacing: 8) {
                if opsSnapshot.agentRows.isEmpty {
                    Text("No agents available to analyze.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(opsSnapshot.agentRows) { row in
                        HStack(spacing: 12) {
                            Text(row.agentName)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .frame(width: 140, alignment: .leading)

                            monitoringPill(title: row.stateText, color: opsColor(for: row.status))
                                .frame(width: 128, alignment: .leading)

                            Text("Done \(row.completedCount)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 70, alignment: .leading)

                            Text("Fail \(row.failedCount)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 64, alignment: .leading)

                            Text(row.averageDuration.map { "Avg \(formatOpsDuration($0))" } ?? "Avg -")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 92, alignment: .leading)

                            Text(row.hasTrackedMemory ? "Memory tracked" : "Memory missing")
                                .font(.caption)
                                .foregroundColor(row.hasTrackedMemory ? .secondary : .orange)
                                .frame(width: 110, alignment: .leading)

                            Text(row.lastActivityAt.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "No activity")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)

                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }
            .padding()
            .background(Color(.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var opsTraceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Traces")
                .font(.headline)

            VStack(spacing: 8) {
                if opsSnapshot.traceRows.isEmpty {
                    Text("No execution traces are available yet.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(opsSnapshot.traceRows) { row in
                        Button {
                            openTraceDetail(for: row)
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Text(row.startedAt.formatted(date: .omitted, time: .standard))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .frame(width: 72, alignment: .leading)

                                monitoringPill(title: row.sourceLabel, color: traceSourceColor(for: row.sourceLabel))
                                    .frame(width: 84, alignment: .leading)

                                monitoringPill(title: row.status.displayName, color: traceStatusColor(for: row.status))
                                    .frame(width: 92, alignment: .leading)

                                Text(row.agentName)
                                    .font(.caption)
                                    .frame(width: 112, alignment: .leading)

                                Text(row.duration.map(formatOpsDuration) ?? "-")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .frame(width: 56, alignment: .leading)

                                Text(row.routingAction?.uppercased() ?? row.outputType.rawValue)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .frame(width: 116, alignment: .leading)

                                Text(row.previewText)
                                    .font(.caption)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.4))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
            .background(Color(.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var executionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LocalizedString.text("workflow_runtime"))
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
                        monitoringPill(title: LocalizedString.text("paused"), color: .red)
                    }

                    if let lastUpdated = project?.runtimeState.lastUpdated {
                        monitoringPill(
                            title: LocalizedString.format("updated_at", lastUpdated.formatted(date: .omitted, time: .shortened)),
                            color: .secondary
                        )
                    }
                }

                if let workflow = project?.workflows.first {
                    Text(LocalizedString.format(
                        "workflow_runtime_summary",
                        workflow.nodes.filter { $0.type == .agent }.count,
                        workflow.edges.count,
                        workflow.boundaries.count
                    ))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color(.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var conversationMonitoringSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LocalizedString.text("conversation_monitoring"))
                .font(.headline)

            HStack(spacing: 16) {
                monitoringCard(
                    title: LocalizedString.text("conversation_total"),
                    value: "\(conversationTotalCount)",
                    detail: LocalizedString.text("workflow_message_total"),
                    color: .blue
                )
                monitoringCard(
                    title: LocalizedString.text("online_status"),
                    value: LocalizedString.format("active_idle_summary", activeAgentCount, idleAgentCount),
                    detail: LocalizedString.text("runtime_based_judgement"),
                    color: activeAgentCount > 0 ? .green : .secondary
                )
                monitoringCard(
                    title: LocalizedString.text("model_tokens"),
                    value: "\(totalTokenCount)",
                    detail: LocalizedString.format("model_token_estimate", modelTokenRows.count),
                    color: .purple
                )
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(LocalizedString.text("agent_activity_metrics"))
                    .font(.subheadline)
                    .fontWeight(.medium)

                if agentConversationRows.isEmpty {
                    Text(LocalizedString.text("no_monitorable_agents"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(agentConversationRows) { row in
                        HStack(spacing: 10) {
                            Text(row.agent.name)
                                .font(.subheadline)
                                .frame(width: 140, alignment: .leading)

                            monitoringPill(title: row.state.title, color: row.state.color)
                                .frame(width: 72, alignment: .leading)

                            Text(LocalizedString.format("spoken_count", row.outgoingCount))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 68, alignment: .leading)

                            Text(LocalizedString.format("received_count", row.incomingCount))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 68, alignment: .leading)

                            Text(LocalizedString.format("skill_count", row.skillCount))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 62, alignment: .leading)

                            Text(LocalizedString.format("file_count", row.fileCount))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 72, alignment: .leading)

                            Spacer()
                        }
                    }
                }
            }
            .padding()
            .background(Color(.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 10) {
                Text(LocalizedString.text("model_token_details"))
                    .font(.subheadline)
                    .fontWeight(.medium)

                if modelTokenRows.isEmpty {
                    Text(LocalizedString.text("no_token_usage"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(modelTokenRows) { row in
                        HStack {
                            Text(row.model)
                                .font(.caption)
                                .frame(width: 180, alignment: .leading)

                            Text(LocalizedString.format("input_count", row.inputTokens))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 86, alignment: .leading)

                            Text(LocalizedString.format("output_count", row.outputTokens))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 86, alignment: .leading)

                            Text(LocalizedString.format("total_count", row.totalTokens))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 84, alignment: .leading)

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

    private var interventionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LocalizedString.text("intervention_actions"))
                .font(.headline)

            HStack(spacing: 10) {
                Button(appState.openClawManager.isConnected ? LocalizedString.text("disconnect_openclaw") + " OpenClaw" : LocalizedString.text("connect_openclaw") + " OpenClaw") {
                    if appState.openClawManager.isConnected {
                        appState.disconnectOpenClaw()
                    } else {
                        appState.connectOpenClaw()
                    }
                }
                .buttonStyle(.borderedProminent)

                Button(LocalizedString.text("detect_connection")) {
                    appState.openClawService.checkConnection()
                }
                .buttonStyle(.bordered)

                Button(LocalizedString.text("pause_execution")) {
                    appState.openClawService.pauseExecution()
                }
                .buttonStyle(.bordered)
                .disabled(!appState.openClawService.isExecuting)

                Button(LocalizedString.text("resume_execution")) {
                    appState.openClawService.resumeExecution()
                }
                .buttonStyle(.bordered)
                .disabled(!(executionState?.canResume ?? false))

                Button(LocalizedString.text("rollback_checkpoint")) {
                    appState.openClawService.rollbackToLastCheckpoint()
                }
                .buttonStyle(.bordered)
                .disabled(executionState?.completedNodes.isEmpty ?? true)

                Button(LocalizedString.text("project_settings")) {
                    NotificationCenter.default.post(name: .openSettings, object: nil)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var taskSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LocalizedString.text("task_monitoring"))
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

                        monitoringPill(title: task.status.displayName, color: task.status.color)

                        Button(LocalizedString.text("mark_in_progress")) {
                            appState.taskManager.moveTask(task.id, to: .inProgress)
                        }
                        .buttonStyle(.borderless)

                        Button(LocalizedString.text("mark_done")) {
                            appState.taskManager.moveTask(task.id, to: .done)
                        }
                        .buttonStyle(.borderless)

                        Button(LocalizedString.text("mark_blocked")) {
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
            Text(LocalizedString.text("recent_execution_results"))
                .font(.headline)

            VStack(spacing: 8) {
                if appState.openClawService.executionResults.isEmpty {
                    Text(LocalizedString.text("no_execution_results"))
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
                            Text(result.output.isEmpty ? LocalizedString.text("no_output") : result.output)
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
                Text(LocalizedString.text("realtime_logs"))
                    .font(.headline)
                Spacer()
                Button(LocalizedString.text("clear_logs")) {
                    appState.openClawService.clearLogs()
                }
                .buttonStyle(.borderless)
            }

            VStack(spacing: 6) {
                if appState.openClawService.executionLogs.isEmpty {
                    Text(LocalizedString.text("no_logs"))
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
                            if let routingBadge = entry.routingBadge {
                                Text(routingBadge)
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(routingColor(for: entry).opacity(0.14))
                                    .foregroundColor(routingColor(for: entry))
                                    .clipShape(Capsule())
                            }
                            Text(entry.message)
                                .font(.caption)
                                .foregroundColor(entry.isRoutingEvent ? routingColor(for: entry) : .primary)
                                .lineLimit(2)
                            Spacer()
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(entry.isRoutingEvent ? routingColor(for: entry).opacity(0.06) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
        guard totalSteps > 0 else { return LocalizedString.text("not_started") }
        return LocalizedString.format("step_progress", currentStep, totalSteps)
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

    private func historyMetricCard(series: OpsMetricHistorySeries, isSelected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(series.metric.title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Circle()
                    .fill(historyColor(for: series.metric))
                    .frame(width: 8, height: 8)
            }

            Text(series.latestPoint.map { series.metric.formattedValue($0.value) } ?? "No data")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(isSelected ? historyColor(for: series.metric) : .primary)

            Text(historyDeltaText(for: series))
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.controlBackgroundColor))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? historyColor(for: series.metric) : Color.clear, lineWidth: 2)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func historyStatPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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

    private func historyDeltaText(for series: OpsMetricHistorySeries) -> String {
        guard let latest = series.latestPoint?.value else {
            return "No historical samples yet"
        }

        guard let previous = series.previousPoint?.value else {
            return "First sample: \(series.metric.formattedValue(latest))"
        }

        let delta = latest - previous
        if series.metric == .errorBudget {
            let sign = delta > 0 ? "+" : ""
            return "Changed \(sign)\(Int(delta.rounded())) since previous sample"
        }

        let sign = delta > 0 ? "+" : ""
        return "Changed \(sign)\(Int(delta.rounded())) pts since previous sample"
    }

    private func logColor(for level: ExecutionLogEntry.LogLevel) -> Color {
        switch level {
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        case .success: return .green
        }
    }

    private func routingColor(for entry: ExecutionLogEntry) -> Color {
        switch entry.routingBadge {
        case "STOP": return .orange
        case "WARN", "MISS": return .red
        case "QUEUE": return .blue
        case "ROUTE": return .purple
        default: return logColor(for: entry.level)
        }
    }

    private func opsColor(for status: OpsHealthStatus) -> Color {
        switch status {
        case .healthy: return .green
        case .warning: return .orange
        case .critical: return .red
        case .neutral: return .secondary
        }
    }

    private func historyColor(for metric: OpsHistoryMetric) -> Color {
        switch metric {
        case .workflowReliability: return .green
        case .agentEngagement: return .blue
        case .memoryDiscipline: return .orange
        case .errorBudget: return .red
        case .cronReliability: return .teal
        }
    }

    private func traceSourceColor(for sourceLabel: String) -> Color {
        sourceLabel == "OpenClaw" ? .teal : .blue
    }

    private func traceStatusColor(for status: ExecutionStatus) -> Color {
        switch status {
        case .completed: return .green
        case .failed: return .red
        case .running: return .orange
        case .waiting: return .blue
        case .idle: return .secondary
        }
    }

    private func formatOpsDuration(_ duration: TimeInterval) -> String {
        if duration >= 60 {
            let minutes = Int(duration) / 60
            let seconds = Int(duration) % 60
            return "\(minutes)m \(seconds)s"
        }
        return String(format: "%.1fs", duration)
    }

    private func openTraceDetail(for row: OpsTraceSummaryRow) {
        guard let projectID = project?.id else { return }

        if let detail = appState.opsAnalytics.traceDetail(projectID: projectID, traceID: row.id) {
            selectedTracePanel = OpsTracePanelModel(
                detail: detail,
                relatedLogs: relatedLogs(for: detail),
                workflowPath: buildWorkflowPath(for: detail)
            )
            return
        }

        let fallbackDetail = OpsTraceDetail(
            id: row.id,
            traceID: row.id.uuidString.replacingOccurrences(of: "-", with: ""),
            parentSpanID: nil,
            spanName: row.agentName,
            service: row.sourceLabel == "OpenClaw" ? "openclaw.external-session" : "multi-agent-flow.execution",
            statusText: row.status == .failed ? "error" : "ok",
            agentName: row.agentName,
            executionStatus: row.status,
            outputType: row.outputType,
            routingAction: row.routingAction,
            routingReason: nil,
            routingTargets: [],
            nodeID: nil,
            startedAt: row.startedAt,
            completedAt: row.duration.map { row.startedAt.addingTimeInterval($0) },
            duration: row.duration,
            previewText: row.previewText,
            outputText: row.previewText,
            attributes: [:],
            eventsText: nil,
            relatedSpans: []
        )
        selectedTracePanel = OpsTracePanelModel(
            detail: fallbackDetail,
            relatedLogs: relatedLogs(for: fallbackDetail),
            workflowPath: buildWorkflowPath(for: fallbackDetail)
        )
    }

    private func relatedLogs(for detail: OpsTraceDetail) -> [ExecutionLogEntry] {
        guard detail.service != "openclaw.external-session" else { return [] }

        let lowerBound = detail.startedAt.addingTimeInterval(-15)
        let upperBound = (detail.completedAt ?? detail.startedAt).addingTimeInterval(30)

        return appState.openClawService.executionLogs
            .filter { entry in
                if let nodeID = detail.nodeID, entry.nodeID == nodeID {
                    return true
                }
                return entry.timestamp >= lowerBound && entry.timestamp <= upperBound
            }
            .sorted { $0.timestamp < $1.timestamp }
            .suffix(30)
            .map { $0 }
    }

    private func buildWorkflowPath(for detail: OpsTraceDetail) -> OpsTraceWorkflowPath? {
        guard let workflow = project?.workflows.first,
              let currentNodeID = detail.nodeID else {
            return nil
        }

        let nodeByID = Dictionary(uniqueKeysWithValues: workflow.nodes.map { ($0.id, $0) })
        let agentByID = Dictionary(uniqueKeysWithValues: (project?.agents ?? []).map { ($0.id, $0) })

        guard let currentNode = nodeByID[currentNodeID] else { return nil }

        let incomingEdges = workflow.edges.filter { $0.isIncoming(to: currentNodeID) }
        let outgoingEdges = workflow.edges.filter { $0.isOutgoing(from: currentNodeID) }
        let requestedTargets = Set(detail.routingTargets.map(normalizedRouteKey))

        let upstreamNodes = incomingEdges.compactMap { edge -> OpsTraceWorkflowPathNode? in
            let sourceID = edge.toNodeID == currentNodeID ? edge.fromNodeID : edge.toNodeID
            guard let node = nodeByID[sourceID] else { return nil }
            return makeWorkflowPathNode(node: node, role: .upstream, state: .normal, agentByID: agentByID)
        }

        let downstreamNodes = outgoingEdges.compactMap { edge -> OpsTraceWorkflowPathNode? in
            let targetID = edge.fromNodeID == currentNodeID ? edge.toNodeID : edge.fromNodeID
            guard let node = nodeByID[targetID] else { return nil }
            let state: OpsTraceWorkflowPathNode.State = matchesRouteTarget(node: node, requestedTargets: requestedTargets, agentByID: agentByID)
                ? .selected
                : .skipped
            return makeWorkflowPathNode(node: node, role: .downstream, state: state, agentByID: agentByID)
        }

        guard let currentPathNode = makeWorkflowPathNode(
            node: currentNode,
            role: .current,
            state: .selected,
            agentByID: agentByID
        ) else {
            return nil
        }

        return OpsTraceWorkflowPath(
            upstreamNodes: uniqueWorkflowPathNodes(upstreamNodes),
            currentNode: currentPathNode,
            downstreamNodes: uniqueWorkflowPathNodes(downstreamNodes)
        )
    }

    private func makeWorkflowPathNode(
        node: WorkflowNode,
        role: OpsTraceWorkflowPathNode.Role,
        state: OpsTraceWorkflowPathNode.State,
        agentByID: [UUID: Agent]
    ) -> OpsTraceWorkflowPathNode? {
        let agentName = node.agentID.flatMap { agentByID[$0]?.name }
        let title = node.title.isEmpty ? (agentName ?? "Untitled Node") : node.title
        let subtitle: String

        switch node.type {
        case .start:
            subtitle = "Start Node"
        case .agent:
            subtitle = agentName ?? "Agent Node"
        }

        return OpsTraceWorkflowPathNode(
            id: node.id,
            title: title,
            subtitle: subtitle,
            role: role,
            state: state
        )
    }

    private func uniqueWorkflowPathNodes(_ nodes: [OpsTraceWorkflowPathNode]) -> [OpsTraceWorkflowPathNode] {
        var seen = Set<UUID>()
        return nodes.filter { node in
            seen.insert(node.id).inserted
        }
    }

    private func matchesRouteTarget(
        node: WorkflowNode,
        requestedTargets: Set<String>,
        agentByID: [UUID: Agent]
    ) -> Bool {
        guard !requestedTargets.isEmpty else { return false }

        var candidates: Set<String> = [
            normalizedRouteKey(node.id.uuidString),
            normalizedRouteKey(String(node.id.uuidString.prefix(8))),
            normalizedRouteKey(node.title)
        ]

        if let agentID = node.agentID, let agent = agentByID[agentID] {
            candidates.insert(normalizedRouteKey(agent.name))
        }

        candidates = candidates.filter { !$0.isEmpty }
        return !candidates.isDisjoint(with: requestedTargets)
    }

    private func normalizedRouteKey(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func scheduleMetricsRefresh(immediately: Bool) {
        pendingMetricsRefreshWorkItem?.cancel()

        let signature = dashboardRefreshSignature
        let projectSnapshot = project
        let tasksSnapshot = appState.taskManager.tasks
        let messagesSnapshot = appState.messageManager.messages
        let activeAgentsSnapshot = appState.openClawManager.activeAgents
        let isConnected = appState.openClawManager.isConnected
        let fileRootsByAgent = buildFileRootsByAgent(project: projectSnapshot, tasks: tasksSnapshot)
        let unknownModelLabel = LocalizedString.text("unknown_model")

        let workItem = DispatchWorkItem {
            DispatchQueue.global(qos: .utility).async {
                let refreshedMetrics = DashboardMetrics.build(
                    project: projectSnapshot,
                    tasks: tasksSnapshot,
                    messages: messagesSnapshot,
                    activeAgents: activeAgentsSnapshot,
                    isConnected: isConnected,
                    fileRootsByAgent: fileRootsByAgent,
                    unknownModelLabel: unknownModelLabel
                )

                DispatchQueue.main.async {
                    guard dashboardRefreshSignature == signature else {
                        scheduleMetricsRefresh(immediately: false)
                        return
                    }
                    metrics = refreshedMetrics
                }
            }
        }

        pendingMetricsRefreshWorkItem = workItem
        let delay = immediately ? 0 : metricsRefreshDebounce
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func buildFileRootsByAgent(project: MAProject?, tasks: [Task]) -> [UUID: [URL]] {
        guard let project else { return [:] }

        var rootsByAgent: [UUID: [URL]] = [:]
        for agent in project.agents {
            if let memoryPath = agent.openClawDefinition.memoryBackupPath?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !memoryPath.isEmpty {
                rootsByAgent[agent.id, default: []].append(URL(fileURLWithPath: memoryPath, isDirectory: true))
            }
        }

        for task in tasks {
            guard let agentID = task.assignedAgentID,
                  let workspaceURL = appState.absoluteWorkspaceURL(for: task.id) else {
                continue
            }
            rootsByAgent[agentID, default: []].append(workspaceURL)
        }

        return rootsByAgent.mapValues { roots in
            Array(Dictionary(uniqueKeysWithValues: roots.map { ($0.standardizedFileURL.path, $0) }).values)
        }
    }
}

private struct OpsTracePanelModel: Identifiable {
    let detail: OpsTraceDetail
    let relatedLogs: [ExecutionLogEntry]
    let workflowPath: OpsTraceWorkflowPath?

    var id: UUID { detail.id }
}

private struct OpsTraceWorkflowPath {
    let upstreamNodes: [OpsTraceWorkflowPathNode]
    let currentNode: OpsTraceWorkflowPathNode
    let downstreamNodes: [OpsTraceWorkflowPathNode]
}

private struct OpsTraceWorkflowPathNode: Identifiable {
    enum Role: Equatable {
        case upstream
        case current
        case downstream
    }

    enum State: Equatable {
        case normal
        case selected
        case skipped
    }

    let id: UUID
    let title: String
    let subtitle: String
    let role: Role
    let state: State
}

private struct OpsTraceDetailSheet: View {
    let panel: OpsTracePanelModel

    private var detail: OpsTraceDetail { panel.detail }

    private var visibleAttributeKeys: [String] {
        detail.attributes.keys
            .filter { key in
                !["output_text", "preview_text"].contains(key)
            }
            .sorted()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(detail.spanName)
                            .font(.title3)
                            .fontWeight(.semibold)
                        Text(detail.traceID)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                    }

                    Spacer()

                    Text(detail.executionStatus.displayName)
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(traceStatusColor(detail.executionStatus).opacity(0.12))
                        .foregroundColor(traceStatusColor(detail.executionStatus))
                        .clipShape(Capsule())
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                    detailCard(
                        title: "Source",
                        value: detail.service == "openclaw.external-session" ? "OpenClaw Backup" : "Runtime"
                    )
                    detailCard(title: "Agent", value: detail.agentName)
                    detailCard(title: "Output", value: detail.outputType.rawValue)
                    detailCard(title: "Route", value: detail.routingAction ?? "N/A")
                    detailCard(title: "Duration", value: detail.duration.map(formatOpsDuration) ?? "N/A")
                    detailCard(title: "Started", value: detail.startedAt.formatted(date: .abbreviated, time: .standard))
                    detailCard(title: "Completed", value: detail.completedAt?.formatted(date: .abbreviated, time: .standard) ?? "In progress")
                }

                if let reason = detail.routingReason, !reason.isEmpty {
                    detailSection(title: "Routing Reason", text: reason)
                }

                if !detail.routingTargets.isEmpty {
                    detailSection(title: "Routing Targets", text: detail.routingTargets.joined(separator: ", "))
                }

                detailSection(title: "Preview", text: detail.previewText)

                if !detail.outputText.isEmpty {
                    detailSection(title: "Raw Output", text: detail.outputText, monospaced: true)
                }

                if let workflowPath = panel.workflowPath {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Workflow Path")
                            .font(.headline)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: 18) {
                                workflowPathColumn(
                                    title: "Upstream",
                                    nodes: workflowPath.upstreamNodes,
                                    emptyText: "No upstream nodes"
                                )

                                Image(systemName: "arrow.right")
                                    .foregroundColor(.secondary)
                                    .padding(.top, 34)

                                workflowPathCurrentNode(workflowPath.currentNode)

                                Image(systemName: "arrow.right")
                                    .foregroundColor(.secondary)
                                    .padding(.top, 34)

                                workflowPathColumn(
                                    title: "Downstream",
                                    nodes: workflowPath.downstreamNodes,
                                    emptyText: "No downstream nodes"
                                )
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .padding()
                    .background(Color(.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                if !detail.relatedSpans.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Span Timeline")
                            .font(.headline)

                        ForEach(detail.relatedSpans) { span in
                            HStack(alignment: .top, spacing: 12) {
                                Rectangle()
                                    .fill(span.statusText == "error" ? Color.red : Color.blue)
                                    .frame(width: 3)
                                    .clipShape(Capsule())

                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(span.name)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                        Spacer()
                                        Text(span.duration.map(formatOpsDuration) ?? "0.0s")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }

                                    Text(span.service)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)

                                    Text(span.summaryText)
                                        .font(.caption)

                                    Text(span.startedAt.formatted(date: .omitted, time: .standard))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .padding()
                    .background(Color(.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                if !visibleAttributeKeys.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Attributes")
                            .font(.headline)

                        ForEach(visibleAttributeKeys, id: \.self) { key in
                            HStack(alignment: .top, spacing: 12) {
                                Text(key)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .frame(width: 140, alignment: .leading)

                                Text(detail.attributes[key] ?? "")
                                    .font(.caption)
                                    .textSelection(.enabled)

                                Spacer()
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .padding()
                    .background(Color(.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                if let eventsText = detail.eventsText, !eventsText.isEmpty {
                    detailSection(title: "Events", text: eventsText, monospaced: true)
                }

                if !panel.relatedLogs.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Related Logs")
                            .font(.headline)

                        ForEach(panel.relatedLogs) { entry in
                            HStack(alignment: .top, spacing: 10) {
                                Text(entry.timestamp.formatted(date: .omitted, time: .standard))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .frame(width: 78, alignment: .leading)

                                Text(entry.level.rawValue)
                                    .font(.caption2)
                                    .foregroundColor(logColor(for: entry.level))
                                    .frame(width: 52, alignment: .leading)

                                Text(entry.message)
                                    .font(.caption)
                                    .textSelection(.enabled)

                                Spacer()
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .padding()
                    .background(Color(.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .padding()
        }
        .frame(minWidth: 760, minHeight: 560)
    }

    private func detailCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .textSelection(.enabled)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func workflowPathColumn(
        title: String,
        nodes: [OpsTraceWorkflowPathNode],
        emptyText: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)

            if nodes.isEmpty {
                Text(emptyText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 180, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(nodes) { node in
                        workflowPathNodeCard(node)
                    }
                }
            }
        }
    }

    private func workflowPathCurrentNode(_ node: OpsTraceWorkflowPathNode) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Current")
                .font(.caption)
                .foregroundColor(.secondary)

            workflowPathNodeCard(node)
                .frame(width: 220)
        }
    }

    private func workflowPathNodeCard(_ node: OpsTraceWorkflowPathNode) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(node.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Spacer()
                Text(workflowPathBadgeText(node))
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(workflowPathBadgeColor(node).opacity(0.14))
                    .foregroundColor(workflowPathBadgeColor(node))
                    .clipShape(Capsule())
            }

            Text(node.subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
        .padding()
        .frame(width: 180, alignment: .leading)
        .background(workflowPathCardColor(node))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(workflowPathBadgeColor(node).opacity(node.role == .current ? 0.6 : 0.22), lineWidth: node.role == .current ? 2 : 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func detailSection(title: String, text: String, monospaced: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            Text(text)
                .font(monospaced ? .system(.body, design: .monospaced) : .body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func traceStatusColor(_ status: ExecutionStatus) -> Color {
        switch status {
        case .completed: return .green
        case .failed: return .red
        case .running: return .orange
        case .waiting: return .blue
        case .idle: return .secondary
        }
    }

    private func logColor(for level: ExecutionLogEntry.LogLevel) -> Color {
        switch level {
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        case .success: return .green
        }
    }

    private func workflowPathBadgeText(_ node: OpsTraceWorkflowPathNode) -> String {
        switch node.role {
        case .current:
            return "Current"
        case .upstream:
            return "Upstream"
        case .downstream:
            switch node.state {
            case .selected:
                return "Selected"
            case .skipped:
                return "Available"
            case .normal:
                return "Node"
            }
        }
    }

    private func workflowPathBadgeColor(_ node: OpsTraceWorkflowPathNode) -> Color {
        switch node.role {
        case .current:
            return .blue
        case .upstream:
            return .secondary
        case .downstream:
            switch node.state {
            case .selected:
                return .green
            case .skipped:
                return .orange
            case .normal:
                return .secondary
            }
        }
    }

    private func workflowPathCardColor(_ node: OpsTraceWorkflowPathNode) -> Color {
        switch node.role {
        case .current:
            return Color.blue.opacity(0.08)
        case .upstream:
            return Color(.controlBackgroundColor)
        case .downstream:
            switch node.state {
            case .selected:
                return Color.green.opacity(0.08)
            case .skipped:
                return Color.orange.opacity(0.08)
            case .normal:
                return Color(.controlBackgroundColor)
            }
        }
    }

    private func formatOpsDuration(_ duration: TimeInterval) -> String {
        if duration >= 60 {
            let minutes = Int(duration) / 60
            let seconds = Int(duration) % 60
            return "\(minutes)m \(seconds)s"
        }
        return String(format: "%.1fs", duration)
    }
}

private struct DashboardMetrics {
    var conversationTotalCount = 0
    var agentConversationRows: [DashboardAgentConversationRow] = []
    var modelTokenRows: [DashboardModelTokenUsageRow] = []
    var totalTokenCount = 0
    var activeAgentCount = 0
    var idleAgentCount = 0

    nonisolated init() {}

    nonisolated init(
        conversationTotalCount: Int,
        agentConversationRows: [DashboardAgentConversationRow],
        modelTokenRows: [DashboardModelTokenUsageRow],
        totalTokenCount: Int,
        activeAgentCount: Int,
        idleAgentCount: Int
    ) {
        self.conversationTotalCount = conversationTotalCount
        self.agentConversationRows = agentConversationRows
        self.modelTokenRows = modelTokenRows
        self.totalTokenCount = totalTokenCount
        self.activeAgentCount = activeAgentCount
        self.idleAgentCount = idleAgentCount
    }

    nonisolated static func build(
        project: MAProject?,
        tasks: [Task],
        messages: [Message],
        activeAgents: [UUID: OpenClawManager.ActiveAgentRuntime],
        isConnected: Bool,
        fileRootsByAgent: [UUID: [URL]],
        unknownModelLabel: String
    ) -> DashboardMetrics {
        guard let project else { return DashboardMetrics() }

        let agentIDs = Set(project.agents.map(\.id))
        let relevantMessages = messages
            .filter { message in
                agentIDs.contains(message.fromAgentID) || agentIDs.contains(message.toAgentID)
            }
            .sorted { $0.timestamp < $1.timestamp }
        let agentLookup = Dictionary(uniqueKeysWithValues: project.agents.map { ($0.id, $0) })
        let runningTaskAgentIDs = Set(
            tasks
                .filter { $0.status == .inProgress }
                .compactMap(\.assignedAgentID)
        )

        var outgoingCounts: [UUID: Int] = [:]
        var incomingCounts: [UUID: Int] = [:]
        var usageByModel: [String: (input: Int, output: Int)] = [:]

        for message in relevantMessages {
            let role = message.metadata["role"]?.lowercased()
            let kind = message.metadata["kind"]?.lowercased()

            if message.fromAgentID == message.toAgentID {
                if role == "assistant" || kind == "output" {
                    outgoingCounts[message.fromAgentID, default: 0] += 1
                } else if role == "user" || kind == "input" {
                    incomingCounts[message.toAgentID, default: 0] += 1
                }
            } else {
                outgoingCounts[message.fromAgentID, default: 0] += 1
                incomingCounts[message.toAgentID, default: 0] += 1
            }

            guard kind != "system" else { continue }
            let tokens = estimatedTokens(for: message)
            guard tokens > 0 else { continue }

            let fromModel = agentLookup[message.fromAgentID].map { normalizedModelName(for: $0, unknownModelLabel: unknownModelLabel) }
            let toModel = agentLookup[message.toAgentID].map { normalizedModelName(for: $0, unknownModelLabel: unknownModelLabel) }

            if message.fromAgentID == message.toAgentID {
                guard let model = toModel ?? fromModel else { continue }
                var bucket = usageByModel[model, default: (0, 0)]
                if role == "assistant" || kind == "output" {
                    bucket.output += tokens
                } else {
                    bucket.input += tokens
                }
                usageByModel[model] = bucket
                continue
            }

            if let fromModel {
                var bucket = usageByModel[fromModel, default: (0, 0)]
                bucket.output += tokens
                usageByModel[fromModel] = bucket
            }

            if let toModel {
                var bucket = usageByModel[toModel, default: (0, 0)]
                bucket.input += tokens
                usageByModel[toModel] = bucket
            }
        }

        let agentConversationRows = project.agents
            .map { agent in
                DashboardAgentConversationRow(
                    agent: agent,
                    state: resolveAgentState(
                        for: agent,
                        project: project,
                        activeAgents: activeAgents,
                        runningTaskAgentIDs: runningTaskAgentIDs,
                        isConnected: isConnected
                    ),
                    outgoingCount: outgoingCounts[agent.id, default: 0],
                    incomingCount: incomingCounts[agent.id, default: 0],
                    skillCount: Set(agent.capabilities.map {
                        $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    }.filter { !$0.isEmpty }).count,
                    fileCount: fileRootsByAgent[agent.id, default: []].reduce(0) { partial, root in
                        partial + regularFileCount(at: root)
                    }
                )
            }
            .sorted { $0.agent.name.localizedCaseInsensitiveCompare($1.agent.name) == .orderedAscending }

        let modelTokenRows = usageByModel
            .map { model, usage in
                DashboardModelTokenUsageRow(
                    model: model,
                    inputTokens: usage.input,
                    outputTokens: usage.output
                )
            }
            .sorted { $0.model.localizedCaseInsensitiveCompare($1.model) == .orderedAscending }

        let activeAgentCount = agentConversationRows.reduce(into: 0) { partial, row in
            if row.state.isActive {
                partial += 1
            }
        }

        return DashboardMetrics(
            conversationTotalCount: relevantMessages.count,
            agentConversationRows: agentConversationRows,
            modelTokenRows: modelTokenRows,
            totalTokenCount: modelTokenRows.reduce(0) { $0 + $1.totalTokens },
            activeAgentCount: activeAgentCount,
            idleAgentCount: max(agentConversationRows.count - activeAgentCount, 0)
        )
    }

    private nonisolated static func resolveAgentState(
        for agent: Agent,
        project: MAProject,
        activeAgents: [UUID: OpenClawManager.ActiveAgentRuntime],
        runningTaskAgentIDs: Set<UUID>,
        isConnected: Bool
    ) -> DashboardAgentOnlineState {
        guard isConnected else {
            return .idle
        }

        let runtimeState = project.runtimeState.agentStates[agent.id.uuidString]?.lowercased() ?? ""
        let openClawState = activeAgents[agent.id]?.status.lowercased() ?? ""
        let isActive = runningTaskAgentIDs.contains(agent.id)
            || runtimeState.contains("running")
            || runtimeState.contains("queued")
            || runtimeState.contains("active")
            || runtimeState.contains("reload")
            || openClawState.contains("running")
            || openClawState.contains("active")
            || openClawState.contains("reload")

        return isActive ? .active : .idle
    }

    private nonisolated static func regularFileCount(at rootURL: URL) -> Int {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: rootURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return 0
        }

        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return 0
        }

        var count = 0
        for case let fileURL as URL in enumerator {
            if let isRegular = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile,
               isRegular == true {
                count += 1
            }
        }
        return count
    }

    private nonisolated static func normalizedModelName(for agent: Agent, unknownModelLabel: String) -> String {
        let value = agent.openClawDefinition.modelIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? unknownModelLabel : value
    }

    private nonisolated static func estimatedTokens(for message: Message) -> Int {
        if let tokenText = message.metadata["tokenEstimate"],
           let value = Int(tokenText),
           value >= 0 {
            return value
        }
        return estimatedTokens(for: message.content)
    }

    private nonisolated static func estimatedTokens(for text: String) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        let scalarCount = trimmed.unicodeScalars.count
        return max(1, Int(ceil(Double(scalarCount) / 4.0)))
    }
}

private enum DashboardAgentOnlineState {
    case active
    case idle

    nonisolated var isActive: Bool {
        switch self {
        case .active: return true
        case .idle: return false
        }
    }

    var title: String {
        switch self {
        case .active: return LocalizedString.text("active_state")
        case .idle: return LocalizedString.text("idle_state")
        }
    }

    var color: Color {
        switch self {
        case .active: return .green
        case .idle: return .secondary
        }
    }
}

private struct DashboardAgentConversationRow: Identifiable {
    var id: UUID { agent.id }
    let agent: Agent
    let state: DashboardAgentOnlineState
    let outgoingCount: Int
    let incomingCount: Int
    let skillCount: Int
    let fileCount: Int
}

private struct DashboardModelTokenUsageRow: Identifiable {
    var id: String { model }
    let model: String
    let inputTokens: Int
    let outputTokens: Int
    let totalTokens: Int

    nonisolated init(model: String, inputTokens: Int, outputTokens: Int) {
        self.model = model
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalTokens = inputTokens + outputTokens
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
