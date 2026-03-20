import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @Binding var selectedTab: Int
    @Binding var zoomScale: CGFloat
    @State private var openClawMessage: String?
    @State private var isConnectingOpenClaw = false
    @State private var isPresentingOpenClawImportSheet = false
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                // 左侧：导航栏
                SidebarView(selectedTab: $selectedTab)
                    .frame(width: 280)

                Divider()

                // 中间：主内容区
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(appState.toolbarItemsInDisplayOrder) { item in
                                    toolbarContent(for: item)
                                }
                            }
                            .padding(.vertical, 1)
                        }
                        .scrollBounceBehavior(.basedOnSize)

                        Spacer(minLength: 12)

                        if selectedTab == 2 {
                            HStack(spacing: 8) {
                                Label("仪表盘（通过左侧导航）", systemImage: "gauge.with.dots.needle.33percent")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Button("切回工作台") {
                                    selectedTab = 1
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        } else {
                            Picker("", selection: toolbarTabSelection) {
                                Label("编辑器", systemImage: "square.grid.2x2").tag(0)
                                Label("工作台", systemImage: "message.badge.waveform").tag(1)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 230)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.8))

                    Divider()

                    // 主内容
                    Group {
                        if appState.currentProject == nil {
                            ProjectOnboardingView()
                                .environmentObject(appState)
                        } else {
                            switch selectedTab {
                            case 0: WorkflowEditorView(zoomScale: $zoomScale)
                            case 1: WorkbenchConversationView(messageManager: appState.messageManager)
                            case 2: MonitoringDashboardView()
                            default: WorkflowEditorView(zoomScale: $zoomScale)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                Divider()

                // 右侧：实时信息面板
                RealtimeInfoPanel()
                    .frame(width: 320)
            }

            Divider()

            bottomStatusBar
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
        .sheet(isPresented: $isPresentingOpenClawImportSheet) {
            OpenClawAgentImportSheet(
                records: appState.openClawManager.discoveryResults,
                actionTitle: "导入这些 Agents",
                onImport: { selectedIDs in
                    let imported = appState.importDetectedOpenClawAgents(selectedRecordIDs: selectedIDs)
                    if imported.isEmpty {
                        openClawMessage = "没有选中可导入的 Agents。"
                    } else {
                        openClawMessage = "已导入 \(imported.count) 个 Agents。"
                    }
                }
            )
        }
    }

    @ViewBuilder
    private func toolbarContent(for item: ContentToolbarItem) -> some View {
        switch item {
        case .view:
            TopToolbarGroup {
                Menu {
                    Button("Zoom Out") {
                        zoomScale = max(zoomScale / 1.25, 0.05)
                    }
                    Button("Reset Zoom") {
                        zoomScale = 1.0
                    }
                    Button("Zoom In") {
                        zoomScale = min(zoomScale * 1.25, 20.0)
                    }
                    Divider()
                    Button(appState.showLogs ? "Hide Logs" : "Show Logs") {
                        appState.showLogs.toggle()
                    }
                } label: {
                    Label("视图", systemImage: "eye")
                }

                HStack(spacing: 4) {
                    Button(action: { zoomScale = max(zoomScale / 1.25, 0.05) }) {
                        Image(systemName: "minus.magnifyingglass")
                    }
                    Text("\(Int(zoomScale * 100))%")
                        .font(.caption)
                        .frame(width: 44)
                    Button(action: { zoomScale = min(zoomScale * 1.25, 20.0) }) {
                        Image(systemName: "plus.magnifyingglass")
                    }
                }
            }
        case .display:
            CanvasDisplayToolbar()
                .environmentObject(appState)
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

    private var bottomStatusBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(appState.openClawManager.isConnected ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(appState.openClawManager.isConnected ? "OpenClaw Connected" : "OpenClaw Disconnected")
                    .font(.caption)
                    .fontWeight(.medium)
                Text(appState.openClawManager.config.deploymentSummary)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            if appState.openClawManager.isConnected {
                StatusBarButton(title: "断开", icon: "link.badge.minus") {
                    appState.disconnectOpenClaw()
                }

                StatusBarButton(title: "导入 Agents", icon: "person.badge.plus") {
                    if appState.openClawManager.discoveryResults.isEmpty {
                        openClawMessage = "请先自动识别 OpenClaw agents。"
                        return
                    }
                    isPresentingOpenClawImportSheet = true
                }
                .disabled(appState.openClawManager.discoveryResults.isEmpty)
            } else {
                StatusBarButton(title: "自动识别", icon: "dot.radiowaves.left.and.right", prominent: true) {
                    autoDetectOpenClaw()
                }

                StatusBarButton(title: "连接", icon: "link.badge.plus") {
                    appState.connectOpenClaw { success, message in
                        openClawMessage = message
                        if !success {
                            return
                        }
                        openClawMessage = "已连接并同步 \(appState.openClawManager.agents.count) 个 agents。"
                    }
                }
            }

            StatusBarButton(title: "检测", icon: "arrow.triangle.2.circlepath") {
                appState.openClawService.checkConnection()
            }

            StatusBarButton(title: "设置", icon: "gearshape") {
                NotificationCenter.default.post(name: .openSettings, object: nil)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
                .background(Color.white.opacity(0.8))
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
    
    private func autoDetectOpenClaw() {
        isConnectingOpenClaw = true
        appState.detectOpenClawAgents { success, message, agentNames in
            self.isConnectingOpenClaw = false
            if success {
                self.openClawMessage = "已识别 \(agentNames.count) 个 agents。请在设置或底部栏手动确认连接。"
            } else {
                self.openClawMessage = message
            }
        }
    }

    private var toolbarTabSelection: Binding<Int> {
        Binding(
            get: { selectedTab == 0 ? 0 : 1 },
            set: { selectedTab = $0 }
        )
    }

}

private struct ProjectOnboardingView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "square.grid.3x3.middle.filled")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)

            Text("从 OpenClaw 配置开始")
                .font(.title2)
                .fontWeight(.semibold)

            Text("推荐流程：先配置 OpenClaw，再新建 Project，在编辑器搭建工作流并保存，随后到工作台对话发任务，最后在仪表盘实时监控与干预。")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 620)

            VStack(alignment: .leading, spacing: 10) {
                onboardingStep(index: 1, title: "配置 OpenClaw", detail: "保存本地、远程或容器部署配置，作为所有 agent 的底层驱动。")
                onboardingStep(index: 2, title: "新建 Project", detail: "Project 保存工作流、OpenClaw、任务数据与记忆备份索引。")
                onboardingStep(index: 3, title: "编辑工作流", detail: "搭建节点、连接线与边界，并编辑 agent 的 soul、identity 与 skill。")
                onboardingStep(index: 4, title: "工作台发任务", detail: "保存后在工作台通过对话把任务发布给当前工作流。")
                onboardingStep(index: 5, title: "仪表盘监控", detail: "实时查看任务、日志与执行进度，并进行暂停、恢复和回滚。")
            }
            .padding(18)
            .background(Color(.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            HStack(spacing: 12) {
                Button("配置 OpenClaw") {
                    NotificationCenter.default.post(name: .openSettings, object: nil)
                }
                .buttonStyle(.borderedProminent)

                Button("新建 Project") {
                    appState.createNewProject()
                }
                .buttonStyle(.bordered)

                Button("打开 Project") {
                    appState.openProject()
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    private func onboardingStep(index: Int, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(index)")
                .font(.subheadline)
                .fontWeight(.semibold)
                .frame(width: 28, height: 28)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
    }
}

private struct TopToolbarGroup<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 8) {
            content
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct StatusBarButton: View {
    let title: String
    let icon: String
    var prominent: Bool = false
    let action: () -> Void

    var body: some View {
        Group {
            if prominent {
                Button(action: action) {
                    label
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button(action: action) {
                    label
                }
                .buttonStyle(.bordered)
            }
        }
        .controlSize(.small)
    }

    private var label: some View {
        Label(title, systemImage: icon)
            .font(.caption)
            .lineLimit(1)
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
                    onSelect: { preset in
                        appState.updateCanvasDisplaySettings { settings in
                            settings.lineColor = preset
                        }
                    }
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
        appState.updateCanvasDisplaySettings { settings in
            settings.lineWidth = lineWidthValues[nextIndex]
        }
    }

    private func shiftTextScale(by offset: Int) {
        let currentIndex = selectedIndex(in: textScaleValues, for: appState.canvasDisplaySettings.textScale)
        let nextIndex = min(max(currentIndex + offset, 0), textScaleValues.count - 1)
        appState.updateCanvasDisplaySettings { settings in
            settings.textScale = textScaleValues[nextIndex]
        }
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

struct ToolbarCustomizationSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Customize Toolbar")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                Text("Choose which toolbar groups are visible and adjust their order.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                VStack(spacing: 10) {
                    ForEach(appState.orderedToolbarItems) { item in
                        HStack(spacing: 12) {
                            Toggle(isOn: Binding(
                                get: { appState.visibleToolbarItems.contains(item) },
                                set: { appState.setToolbarItem(item, visible: $0) }
                            )) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                    Text(toolbarItemDescription(for: item))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .toggleStyle(.checkbox)

                            Spacer()

                            HStack(spacing: 6) {
                                Button(action: { appState.moveToolbarItem(item, by: -1) }) {
                                    Image(systemName: "arrow.up")
                                }
                                .disabled(isFirst(item))

                                Button(action: { appState.moveToolbarItem(item, by: 1) }) {
                                    Image(systemName: "arrow.down")
                                }
                                .disabled(isLast(item))
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color(.controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }

                HStack {
                    Button("Reset to Default") {
                        appState.resetToolbarLayout()
                    }
                    .buttonStyle(.bordered)

                    Spacer()
                }
            }
            .padding()

            Spacer(minLength: 0)
        }
        .frame(width: 520, height: 420)
    }

    private func isFirst(_ item: ContentToolbarItem) -> Bool {
        appState.orderedToolbarItems.first == item
    }

    private func isLast(_ item: ContentToolbarItem) -> Bool {
        appState.orderedToolbarItems.last == item
    }

    private func toolbarItemDescription(for item: ContentToolbarItem) -> String {
        switch item {
        case .view:
            return "Zoom controls and log visibility"
        case .display:
            return "Line width, text size and route color controls"
        case .language:
            return "Language switcher"
        }
    }
}
