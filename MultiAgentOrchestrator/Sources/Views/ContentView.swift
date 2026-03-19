import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @Binding var selectedTab: Int
    @Binding var zoomScale: CGFloat
    @State private var openClawMessage: String?
    @State private var isConnectingOpenClaw = false
    
    var body: some View {
        HStack(spacing: 0) {
            // 左侧：导航栏
            SidebarView(selectedTab: $selectedTab)
                .frame(width: 280)
            
            Divider()
            
            // 中间：主内容区
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    ForEach(appState.toolbarItemsInDisplayOrder) { item in
                        toolbarContent(for: item)
                    }

                    Spacer(minLength: 12)

                    Picker("", selection: $selectedTab) {
                        Label(LocalizedString.workflow, systemImage: "square.grid.2x2").tag(0)
                        Label(LocalizedString.tasks, systemImage: "square.stack.3d.up").tag(1)
                        Label(LocalizedString.dashboard, systemImage: "chart.bar").tag(2)
                        Label(LocalizedString.messages, systemImage: "message").tag(3)
                        Label(LocalizedString.permissions, systemImage: "lock.shield").tag(4)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 520)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color(.windowBackgroundColor))
                
                Divider()
                
                // 主内容
                Group {
                    switch selectedTab {
                    case 0: WorkflowEditorView(zoomScale: $zoomScale)
                    case 1: KanbanView()
                    case 2: TaskDashboardView(taskManager: appState.taskManager)
                    case 3: MessagesView(messageManager: appState.messageManager)
                    case 4: PermissionsView()
                    default: WorkflowEditorView(zoomScale: $zoomScale)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            
            Divider()
            
            // 右侧：实时信息面板
            RealtimeInfoPanel()
                .frame(width: 320)
        }
        .overlay(alignment: .bottom) {
            if isConnectingOpenClaw {
                HStack {
                    ProgressView()
                    Text(LocalizedString.connectingToOpenClaw)
                        .font(.caption)
                }
                .padding()
                .background(Color(.windowBackgroundColor).opacity(0.95))
                .cornerRadius(8)
                .padding(.bottom)
            }
        }
        .alert("OpenClaw", isPresented: Binding(
            get: { openClawMessage != nil },
            set: { if !$0 { openClawMessage = nil } }
        )) {
            Button("OK") { }
        } message: {
            Text(openClawMessage ?? "")
        }
    }

    private var projectSummary: String {
        let agentCount = appState.currentProject?.agents.count ?? 0
        let workflowCount = appState.currentProject?.workflows.count ?? 0
        let edgeCount = appState.currentProject?.workflows.first?.edges.count ?? 0
        return "\(agentCount) agents • \(workflowCount) workflows • \(edgeCount) routes"
    }

    @ViewBuilder
    private func toolbarContent(for item: ContentToolbarItem) -> some View {
        switch item {
        case .project:
            TopToolbarGroup {
                VStack(alignment: .leading, spacing: 2) {
                    Text(appState.currentProject?.name ?? LocalizedString.appName)
                        .font(.headline)
                    Text(projectSummary)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(minWidth: 190, alignment: .leading)
            }
        case .file:
            TopToolbarGroup {
                Menu {
                    Button(action: { appState.createNewProject() }) {
                        Label(LocalizedString.new, systemImage: "plus")
                    }
                    Button(action: { appState.saveProject() }) {
                        Label(LocalizedString.save, systemImage: "square.and.arrow.down")
                    }
                    Divider()
                    Button(action: { appState.importData() }) {
                        Label("Import", systemImage: "square.and.arrow.down.on.square")
                    }
                    Button(action: { appState.exportData() }) {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    if appState.currentProject != nil {
                        Divider()
                        Button(action: { appState.closeProject() }) {
                            Label("Close Project", systemImage: "xmark.circle")
                        }
                    }
                } label: {
                    Label("File", systemImage: "doc")
                }

                Button(action: { appState.saveProject() }) {
                    Label(LocalizedString.save, systemImage: "square.and.arrow.down")
                }
            }
        case .view:
            TopToolbarGroup {
                Menu {
                    Button("Zoom Out") {
                        zoomScale = max(zoomScale / 1.25, 0.25)
                    }
                    Button("Reset Zoom") {
                        zoomScale = 1.0
                    }
                    Button("Zoom In") {
                        zoomScale = min(zoomScale * 1.25, 3.0)
                    }
                    Divider()
                    Button(appState.showLogs ? "Hide Logs" : "Show Logs") {
                        appState.showLogs.toggle()
                    }
                } label: {
                    Label("View", systemImage: "eye")
                }

                HStack(spacing: 4) {
                    Button(action: { zoomScale = max(zoomScale / 1.25, 0.25) }) {
                        Image(systemName: "minus.magnifyingglass")
                    }
                    Text("\(Int(zoomScale * 100))%")
                        .font(.caption)
                        .frame(width: 44)
                    Button(action: { zoomScale = min(zoomScale * 1.25, 3.0) }) {
                        Image(systemName: "plus.magnifyingglass")
                    }
                }
            }
        case .display:
            CanvasDisplayToolbar()
                .environmentObject(appState)
        case .openClaw:
            TopToolbarGroup {
                HStack(spacing: 8) {
                    Label("OpenClaw", systemImage: "bolt.horizontal.circle")
                    statusBadge

                    if appState.openClawManager.isConnected {
                        Button(action: { appState.openClawManager.disconnect() }) {
                            Label("断开", systemImage: "link.badge.minus")
                        }
                        .buttonStyle(.bordered)

                        Button(action: { addOpenClawAgentsToProject() }) {
                            Label("导入 Agents", systemImage: "person.badge.plus")
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Button(action: { autoDetectAndConnect() }) {
                            Label("自动连接", systemImage: "antenna.radiowaves.left.and.right")
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    Button(action: { appState.openClawService.checkConnection() }) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.bordered)

                    Button(action: { NotificationCenter.default.post(name: .openSettings, object: nil) }) {
                        Image(systemName: "gear")
                    }
                    .buttonStyle(.bordered)
                }
            }
        case .language:
            TopToolbarGroup {
                HStack(spacing: 6) {
                    Image(systemName: "globe")
                    ForEach(AppLanguage.allCases) { language in
                        Button(action: { appState.localizationManager.setLanguage(language) }) {
                            Text(language.displayName == "简体中文" ? "简体" : language.displayName == "繁體中文" ? "繁中" : "EN")
                        }
                        .buttonStyle(.bordered)
                        .tint(appState.localizationManager.currentLanguage == language ? .accentColor : nil)
                    }
                }
            }
        }
    }

    private var statusBadge: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(appState.openClawManager.isConnected ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            Text(appState.openClawManager.isConnected ? "Connected" : "Disconnected")
        }
        .padding(.vertical, 4)
    }
    
    private func autoDetectAndConnect() {
        let paths = ["/Users/chenrongze/.local/bin/openclaw", "/usr/local/bin/openclaw"]
        var found = false
        for p in paths {
            if FileManager.default.fileExists(atPath: p) { found = true; break }
        }
        if !found {
            openClawMessage = "OpenClaw not found!"
            return
        }
        isConnectingOpenClaw = true
        appState.openClawManager.connect()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.isConnectingOpenClaw = false
            if self.appState.openClawManager.isConnected {
                self.openClawMessage = "Connected! Found \(self.appState.openClawManager.agents.count) agents."
            } else {
                self.openClawMessage = "Connection failed."
            }
        }
    }
    
    private func addOpenClawAgentsToProject() {
        guard var project = appState.currentProject else {
            openClawMessage = "Please create or open a project first."
            return
        }
        for name in appState.openClawManager.agents {
            if !project.agents.contains(where: { $0.name == name }) {
                var agent = Agent(name: name)
                agent.description = "OpenClaw Agent: \(name)"
                project.agents.append(agent)
            }
        }
        appState.currentProject = project
        openClawMessage = "Added \(appState.openClawManager.agents.count) agents."
    }
}

private struct TopToolbarGroup<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 8) {
            content
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct CanvasDisplayToolbar: View {
    @EnvironmentObject var appState: AppState

    private let lineWidthValues: [CGFloat] = [1, 2, 3, 4, 6]
    private let textScaleValues: [CGFloat] = [0.85, 1.0, 1.15, 1.3, 1.5]

    var body: some View {
        TopToolbarGroup {
            HStack(spacing: 10) {
                ToolbarStepper(
                    title: "线宽",
                    valueText: "\(Int(appState.canvasDisplaySettings.lineWidth))px",
                    canDecrease: selectedIndex(in: lineWidthValues, for: appState.canvasDisplaySettings.lineWidth) > 0,
                    canIncrease: selectedIndex(in: lineWidthValues, for: appState.canvasDisplaySettings.lineWidth) < lineWidthValues.count - 1,
                    onDecrease: { shiftLineWidth(by: -1) },
                    onIncrease: { shiftLineWidth(by: 1) }
                )

                ToolbarStepper(
                    title: "字号",
                    valueText: "\(Int(appState.canvasDisplaySettings.textScale * 100))%",
                    canDecrease: selectedIndex(in: textScaleValues, for: appState.canvasDisplaySettings.textScale) > 0,
                    canIncrease: selectedIndex(in: textScaleValues, for: appState.canvasDisplaySettings.textScale) < textScaleValues.count - 1,
                    onDecrease: { shiftTextScale(by: -1) },
                    onIncrease: { shiftTextScale(by: 1) }
                )

                ToolbarColorSelector(
                    title: "线色",
                    selection: appState.canvasDisplaySettings.lineColor,
                    onSelect: { appState.canvasDisplaySettings.lineColor = $0 }
                )

                ToolbarColorSelector(
                    title: "字色",
                    selection: appState.canvasDisplaySettings.textColor,
                    onSelect: { appState.canvasDisplaySettings.textColor = $0 }
                )
            }
        }
    }

    private func selectedIndex(in values: [CGFloat], for current: CGFloat) -> Int {
        values.firstIndex(where: { abs($0 - current) < 0.001 }) ?? 0
    }

    private func shiftLineWidth(by offset: Int) {
        let currentIndex = selectedIndex(in: lineWidthValues, for: appState.canvasDisplaySettings.lineWidth)
        let nextIndex = min(max(currentIndex + offset, 0), lineWidthValues.count - 1)
        appState.canvasDisplaySettings.lineWidth = lineWidthValues[nextIndex]
    }

    private func shiftTextScale(by offset: Int) {
        let currentIndex = selectedIndex(in: textScaleValues, for: appState.canvasDisplaySettings.textScale)
        let nextIndex = min(max(currentIndex + offset, 0), textScaleValues.count - 1)
        appState.canvasDisplaySettings.textScale = textScaleValues[nextIndex]
    }
}

private struct ToolbarStepper: View {
    let title: String
    let valueText: String
    let canDecrease: Bool
    let canIncrease: Bool
    let onDecrease: () -> Void
    let onIncrease: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            HStack(spacing: 4) {
                Button(action: onDecrease) {
                    Image(systemName: "minus")
                }
                .buttonStyle(.borderless)
                .disabled(!canDecrease)

                Text(valueText)
                    .font(.caption)
                    .frame(minWidth: 42)

                Button(action: onIncrease) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .disabled(!canIncrease)
            }
        }
    }
}

private struct ToolbarColorSelector: View {
    let title: String
    let selection: CanvasColorPreset
    let onSelect: (CanvasColorPreset) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            HStack(spacing: 4) {
                ForEach(CanvasColorPreset.allCases) { preset in
                    Button(action: { onSelect(preset) }) {
                        Circle()
                            .fill(preset.color)
                            .frame(width: 12, height: 12)
                            .overlay {
                                Circle()
                                    .stroke(selection == preset ? Color.primary : Color.clear, lineWidth: 2)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct RealtimeInfoPanel: View {
    @EnvironmentObject var appState: AppState

    @State private var showPermissionSummary = true
    @State private var showPendingApprovals = true
    @State private var showExecutionLogs = true

    private var project: MAProject? { appState.currentProject }
    private var permissions: [Permission] { project?.permissions ?? [] }
    private var pendingApprovals: [Message] { appState.messageManager.pendingApprovals }
    private var executionLogs: [ExecutionLogEntry] { appState.openClawService.executionLogs }

    private var agentNameMap: [UUID: String] {
        Dictionary(uniqueKeysWithValues: (project?.agents ?? []).map { ($0.id, $0.name) })
    }

    private var allowCount: Int {
        permissions.filter { $0.permissionType == .allow }.count
    }

    private var denyCount: Int {
        permissions.filter { $0.permissionType == .deny }.count
    }

    private var approvalCount: Int {
        permissions.filter { $0.permissionType == .requireApproval }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("实时信息")
                    .font(.headline)
                Spacer()
            }
            .padding()
            .background(Color(.controlBackgroundColor))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    DisclosureGroup(
                        isExpanded: $showPermissionSummary,
                        content: permissionSummaryContent,
                        label: {
                            sectionTitle("权限矩阵摘要", count: permissions.count)
                        }
                    )

                    DisclosureGroup(
                        isExpanded: $showPendingApprovals,
                        content: pendingApprovalContent,
                        label: {
                            sectionTitle("待审批消息", count: pendingApprovals.count)
                        }
                    )

                    DisclosureGroup(
                        isExpanded: $showExecutionLogs,
                        content: executionLogsContent,
                        label: {
                            sectionTitle("执行日志", count: executionLogs.count)
                        }
                    )
                }
                .padding()
            }
        }
        .background(Color(.windowBackgroundColor))
    }

    private func sectionTitle(_ title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
            Spacer()
            Text("\(count)")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.18))
                .cornerRadius(4)
        }
    }

    private func permissionSummaryContent() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                summaryPill("Allow", value: allowCount, color: .green)
                summaryPill("Deny", value: denyCount, color: .red)
                summaryPill("审批", value: approvalCount, color: .orange)
            }

            if permissions.isEmpty {
                Text("暂无权限规则")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(Array(permissions.prefix(8))) { permission in
                    HStack(spacing: 6) {
                        Text("\(agentName(for: permission.fromAgentID)) → \(agentName(for: permission.toAgentID))")
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()
                        Label(permission.permissionType.rawValue, systemImage: permission.permissionType.icon)
                            .font(.caption2)
                            .foregroundColor(permission.permissionType.color)
                    }
                    .padding(.vertical, 2)
                }

                if permissions.count > 8 {
                    Text("还有 \(permissions.count - 8) 条规则")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(10)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }

    private func pendingApprovalContent() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if pendingApprovals.isEmpty {
                Text("当前没有待审批消息")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(Array(pendingApprovals.prefix(20))) { message in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("\(agentName(for: message.fromAgentID)) → \(agentName(for: message.toAgentID))")
                                .font(.caption)
                                .fontWeight(.medium)
                                .lineLimit(1)
                            Spacer()
                            Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Text(message.content)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    .padding(8)
                    .background(Color.orange.opacity(0.08))
                    .cornerRadius(6)
                }
            }
        }
        .padding(10)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }

    private func executionLogsContent() -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if executionLogs.isEmpty {
                Text("暂无执行日志")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(Array(executionLogs.suffix(80).reversed())) { entry in
                    HStack(alignment: .top, spacing: 6) {
                        Text(entry.timestamp.formatted(date: .omitted, time: .standard))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .frame(width: 70, alignment: .leading)
                        Text(entry.level.rawValue)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(logLevelColor(entry.level))
                            .frame(width: 52, alignment: .leading)
                        Text(entry.message)
                            .font(.caption2)
                            .lineLimit(2)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 1)
                }
            }
        }
        .padding(10)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }

    private func summaryPill(_ title: String, value: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text("\(title): \(value)")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.08))
        .cornerRadius(6)
    }

    private func agentName(for id: UUID) -> String {
        agentNameMap[id] ?? String(id.uuidString.prefix(8))
    }

    private func logLevelColor(_ level: ExecutionLogEntry.LogLevel) -> Color {
        switch level {
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        case .success: return .green
        }
    }
}
