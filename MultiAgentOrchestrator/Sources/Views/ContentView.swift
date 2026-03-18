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
            SidebarView()
                .frame(width: 250)
            
            Divider()
            
            // 中间：主内容区
            VStack(spacing: 0) {
                // 顶部工具栏
                HStack {
                    // 项目名称
                    Text(appState.currentProject?.name ?? LocalizedString.appName)
                        .font(.headline)
                        .padding(.leading)
                    
                    Spacer()
                    
                    // 缩放控制
                    HStack(spacing: 4) {
                        Button(action: { zoomScale = max(zoomScale / 1.25, 0.25) }) {
                            Image(systemName: "minus.magnifyingglass")
                        }
                        Text("\(Int(zoomScale * 100))%")
                            .font(.caption)
                            .frame(width: 40)
                        Button(action: { zoomScale = min(zoomScale * 1.25, 3.0) }) {
                            Image(systemName: "plus.magnifyingglass")
                        }
                    }
                    .padding(6)
                    .background(Color(.controlBackgroundColor))
                    .cornerRadius(6)
                    
                    // 语言切换
                    Menu {
                        ForEach(AppLanguage.allCases) { language in
                            Button(action: { appState.localizationManager.setLanguage(language) }) {
                                HStack {
                                    Text(language.displayName)
                                    if appState.localizationManager.currentLanguage == language {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "globe")
                            Text(appState.localizationManager.currentLanguage == .simplifiedChinese ? "简" : "EN")
                        }
                    }
                    .frame(width: 40)
                    
                    // Tools菜单
                    Menu {
                        // 连接状态
                        HStack {
                            Circle()
                                .fill(appState.openClawManager.isConnected ? Color.green : Color.red)
                                .frame(width: 8, height: 8)
                            Text(appState.openClawManager.isConnected ? "Connected" : "Disconnected")
                        }
                        .padding(.vertical, 4)
                        
                        Divider()
                        
                        if appState.openClawManager.isConnected {
                            Button(action: { appState.openClawManager.disconnect() }) {
                                Label("Disconnect", systemImage: "link.badge.minus")
                            }
                            Divider()
                            Button(action: { addOpenClawAgentsToProject() }) {
                                Label("Add Agents to Project", systemImage: "person.badge.plus")
                            }
                        } else {
                            Button(action: { autoDetectAndConnect() }) {
                                Label("Auto Detect & Connect", systemImage: "antenna.radiowaves.left.and.right")
                            }
                        }
                        
                        Divider()
                        
                        // 关闭项目按钮
                        if appState.currentProject != nil {
                            Button(action: { appState.closeProject() }) {
                                Label("Close Project", systemImage: "xmark.circle")
                            }
                            Divider()
                        }
                        
                        Button(action: { NotificationCenter.default.post(name: .openSettings, object: nil) }) {
                            Label(LocalizedString.settings, systemImage: "gear")
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "wrench.and.screwdriver")
                            Text(LocalizedString.tools)
                        }
                    }
                    .frame(width: 60)
                    
                    Button(action: { appState.createNewProject() }) {
                        Label(LocalizedString.new, systemImage: "plus")
                    }
                    
                    Button(action: { appState.saveProject() }) {
                        Label(LocalizedString.save, systemImage: "square.and.arrow.down")
                    }
                    
                    Spacer()
                    
                    // Tab选择器
                    Picker("", selection: $selectedTab) {
                        Label(LocalizedString.workflow, systemImage: "square.grid.2x2").tag(0)
                        Label(LocalizedString.tasks, systemImage: "square.stack.3d.up").tag(1)
                        Label(LocalizedString.dashboard, systemImage: "chart.bar").tag(2)
                        Label(LocalizedString.controlPanel, systemImage: "gearshape.2").tag(3)
                        Label(LocalizedString.permissions, systemImage: "lock.shield").tag(4)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 500)
                    
                    Spacer()
                }
                .padding(.vertical, 8)
                .background(Color(.windowBackgroundColor))
                
                Divider()
                
                // 主内容
                Group {
                    switch selectedTab {
                    case 0: WorkflowEditorView(zoomScale: $zoomScale)
                    case 1: KanbanView()
                    case 2: TaskDashboardView(taskManager: appState.taskManager)
                    case 3: ControlPanelView()
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
