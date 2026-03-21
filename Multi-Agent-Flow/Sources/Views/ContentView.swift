import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @Binding var selectedTab: Int
    @Binding var zoomScale: CGFloat
    @State private var openClawMessage: String?
    @State private var isConnectingOpenClaw = false
    @State private var isPresentingOpenClawImportSheet = false
    @State private var selectedTemplateLibraryID: String = AgentTemplateCatalog.defaultTemplateID

    private var isOpenClawRuntimeDegraded: Bool {
        appState.openClawManager.connectionState.isRunnableWithDegradedCapabilities
    }

    private var openClawStatusBadgeTitle: String {
        if appState.openClawManager.isConnected {
            return LocalizedString.text("openclaw_connected")
        }
        if isOpenClawRuntimeDegraded {
            return LocalizedString.text("openclaw_degraded")
        }
        return LocalizedString.text("openclaw_disconnected")
    }

    private var openClawStatusText: String {
        if appState.openClawManager.isConnected {
            return LocalizedString.text("connected_status")
        }
        if isOpenClawRuntimeDegraded {
            return LocalizedString.text("degraded_status")
        }
        return LocalizedString.text("disconnected_status")
    }

    private var openClawStatusColor: Color {
        if appState.openClawManager.isConnected {
            return .green
        }
        if isOpenClawRuntimeDegraded {
            return .orange
        }
        return .red
    }

    private var openClawAttachmentColor: Color {
        switch appState.currentProjectOpenClawAttachmentState {
        case .attachedCurrentProject:
            return .green
        case .attachedDifferentProject, .unattached:
            return .orange
        case .remoteConnectionOnly:
            return .blue
        case .noProject:
            return .secondary
        }
    }
    
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

                        if selectedTab == 2 || selectedTab == 3 {
                            HStack(spacing: 8) {
                                Label(
                                    selectedTab == 2
                                        ? LocalizedString.text("dashboard_via_sidebar")
                                        : LocalizedString.text("template_library_via_sidebar"),
                                    systemImage: selectedTab == 2 ? "gauge.with.dots.needle.33percent" : "shippingbox"
                                )
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Button(LocalizedString.text("switch_to_workbench")) {
                                    selectedTab = 1
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        } else {
                            Picker("", selection: toolbarTabSelection) {
                                Label(LocalizedString.text("editor_tab"), systemImage: "square.grid.2x2").tag(0)
                                Label(LocalizedString.text("workbench_tab"), systemImage: "message.badge.waveform").tag(1)
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
                        if appState.currentProject == nil && selectedTab != 3 {
                            ProjectOnboardingView(selectedTab: $selectedTab)
                                .environmentObject(appState)
                        } else {
                            switch selectedTab {
                            case 0: WorkflowEditorView(zoomScale: $zoomScale)
                            case 1: WorkbenchConversationView(messageManager: appState.messageManager)
                            case 2: OpsCenterDashboardView(displayMode: .fullScreen)
                            case 3: TemplateLibraryManagerSheet(selectedTemplateID: $selectedTemplateLibraryID, showsCloseButton: false)
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
        .alert(LocalizedString.text("openclaw_alert_title"), isPresented: Binding(
            get: { openClawMessage != nil },
            set: { if !$0 { openClawMessage = nil } }
        )) {
            Button(LocalizedString.ok) { }
        } message: {
            Text(openClawMessage ?? "")
        }
        .sheet(isPresented: $isPresentingOpenClawImportSheet) {
            OpenClawAgentImportSheet(
                records: appState.openClawManager.discoveryResults,
                actionTitle: LocalizedString.text("import_these_agents"),
                onImport: { selections in
                    let imported = appState.importDetectedOpenClawAgents(selections: selections)
                    if imported.isEmpty {
                        openClawMessage = LocalizedString.text("no_agents_selected_for_import")
                    } else {
                        openClawMessage = LocalizedString.format("agents_imported_count", imported.count)
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
                    Button(LocalizedString.zoomOut) {
                        zoomScale = max(zoomScale / 1.25, 0.05)
                    }
                    Button(LocalizedString.resetZoom) {
                        zoomScale = 1.0
                    }
                    Button(LocalizedString.zoomIn) {
                        zoomScale = min(zoomScale * 1.25, 20.0)
                    }
                    Divider()
                    Button(appState.showLogs ? LocalizedString.text("hide_logs") : LocalizedString.text("show_logs")) {
                        appState.showLogs.toggle()
                    }
                } label: {
                    Label(LocalizedString.text("view_menu"), systemImage: "eye")
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
                            Text(language.shortDisplayName)
                        }
                        .buttonStyle(.bordered)
                        .tint(appState.localizationManager.currentLanguage == language ? .accentColor : nil)
                    }

                    Button(action: {
                        NotificationCenter.default.post(name: .openSettings, object: nil)
                    }) {
                        Image(systemName: "gearshape")
                    }
                    .buttonStyle(.bordered)
                    .help(LocalizedString.settings)
                }
            }
        }
    }

    private var bottomStatusBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(openClawStatusColor)
                    .frame(width: 8, height: 8)
                Text(openClawStatusBadgeTitle)
                    .font(.caption)
                    .fontWeight(.medium)
                Text(appState.openClawManager.config.deploymentSummary)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                Circle()
                    .fill(openClawAttachmentColor)
                    .frame(width: 8, height: 8)
                Text(appState.openClawAttachmentStatusTitle)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            if appState.openClawManager.isConnected {
                StatusBarButton(title: LocalizedString.text("disconnect_openclaw"), icon: "link.badge.minus") {
                    appState.disconnectOpenClaw()
                }

                if let currentProject = appState.currentProject,
                   appState.openClawManager.canAttachProject,
                   appState.openClawManager.config.deploymentKind != .remoteServer,
                   (
                    !appState.openClawManager.hasAttachedProjectSession
                    || appState.openClawManager.attachedProjectID != currentProject.id
                   ) {
                    StatusBarButton(title: LocalizedString.text("attach_current_project"), icon: "link.badge.plus") {
                        appState.attachCurrentProjectToOpenClaw { _, message in
                            openClawMessage = message
                        }
                    }
                }

                if appState.openClawManager.config.deploymentKind != .remoteServer,
                   appState.isCurrentProjectAttachedToOpenClaw {
                    StatusBarButton(title: "同步会话", icon: "arrow.triangle.merge") {
                        appState.syncOpenClawActiveSession { success, message in
                            openClawMessage = message
                            if !success {
                                return
                            }
                            openClawMessage = message
                        }
                    }
                }

                StatusBarButton(title: LocalizedString.text("import_agents"), icon: "person.badge.plus") {
                    if appState.openClawManager.discoveryResults.isEmpty {
                        openClawMessage = LocalizedString.text("detect_agents_first")
                        return
                    }
                    isPresentingOpenClawImportSheet = true
                }
                .disabled(appState.openClawManager.discoveryResults.isEmpty)
            } else {
                StatusBarButton(title: LocalizedString.text("auto_detect_agents"), icon: "dot.radiowaves.left.and.right", prominent: true) {
                    autoDetectOpenClaw()
                }

                StatusBarButton(title: LocalizedString.text("connect_openclaw"), icon: "link.badge.plus") {
                    appState.connectOpenClaw { success, message in
                        openClawMessage = message
                        if !success {
                            return
                        }
                        openClawMessage = message
                    }
                }
            }

            StatusBarButton(title: LocalizedString.text("check_connection"), icon: "arrow.triangle.2.circlepath") {
                appState.openClawService.checkConnection()
            }

            StatusBarButton(title: LocalizedString.settings, icon: "gearshape") {
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
                .fill(openClawStatusColor)
                .frame(width: 8, height: 8)
            Text(openClawStatusText)
        }
        .padding(.vertical, 4)
    }
    
    private func autoDetectOpenClaw() {
        isConnectingOpenClaw = true
        appState.detectOpenClawAgents { success, message, agentNames in
            self.isConnectingOpenClaw = false
            if success {
                self.openClawMessage = LocalizedString.format("detected_agents_confirm_connection", agentNames.count)
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
    @Binding var selectedTab: Int

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "square.grid.3x3.middle.filled")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)

            Text(LocalizedString.text("onboarding_title"))
                .font(.title2)
                .fontWeight(.semibold)

            Text(LocalizedString.text("onboarding_description"))
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 620)

            HStack(spacing: 10) {
                onboardingBadge(
                    icon: "square.grid.2x2",
                    title: LocalizedString.text("onboarding_badge_design_first")
                )
                onboardingBadge(
                    icon: "square.and.arrow.down.on.square",
                    title: LocalizedString.text("onboarding_badge_save_apply")
                )
                onboardingBadge(
                    icon: "link.badge.plus",
                    title: LocalizedString.text("onboarding_badge_runtime_optional")
                )
            }

            VStack(alignment: .leading, spacing: 10) {
                onboardingStep(index: 1, title: LocalizedString.text("onboarding_step_1_title"), detail: LocalizedString.text("onboarding_step_1_detail"))
                onboardingStep(index: 2, title: LocalizedString.text("onboarding_step_2_title"), detail: LocalizedString.text("onboarding_step_2_detail"))
                onboardingStep(index: 3, title: LocalizedString.text("onboarding_step_3_title"), detail: LocalizedString.text("onboarding_step_3_detail"))
                onboardingStep(index: 4, title: LocalizedString.text("onboarding_step_4_title"), detail: LocalizedString.text("onboarding_step_4_detail"))
                onboardingStep(index: 5, title: LocalizedString.text("onboarding_step_5_title"), detail: LocalizedString.text("onboarding_step_5_detail"))
            }
            .padding(18)
            .background(Color(.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            HStack(spacing: 12) {
                Button(LocalizedString.newProject) {
                    appState.createNewProject()
                }
                .buttonStyle(.borderedProminent)

                Button(LocalizedString.openProject) {
                    appState.openProject()
                }
                .buttonStyle(.bordered)

                Button(LocalizedString.text("open_template_library")) {
                    selectedTab = 3
                }
                .buttonStyle(.bordered)

                Button(LocalizedString.text("configure_openclaw_optional")) {
                    NotificationCenter.default.post(name: .openSettings, object: nil)
                }
                .buttonStyle(.bordered)
            }

            Text(LocalizedString.text("onboarding_runtime_hint"))
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 620)
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

    private func onboardingBadge(icon: String, title: String) -> some View {
        Label(title, systemImage: icon)
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(.controlBackgroundColor))
            .clipShape(Capsule())
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
                    title: LocalizedString.text("line_width"),
                    valueText: "\(Int(appState.canvasDisplaySettings.lineWidth))px",
                    canDecrease: selectedIndex(in: lineWidthValues, for: appState.canvasDisplaySettings.lineWidth) > 0,
                    canIncrease: selectedIndex(in: lineWidthValues, for: appState.canvasDisplaySettings.lineWidth) < lineWidthValues.count - 1,
                    onDecrease: { shiftLineWidth(by: -1) },
                    onIncrease: { shiftLineWidth(by: 1) }
                )

                ToolbarStepper(
                    title: LocalizedString.text("font_size"),
                    valueText: "\(Int(appState.canvasDisplaySettings.textScale * 100))%",
                    canDecrease: selectedIndex(in: textScaleValues, for: appState.canvasDisplaySettings.textScale) > 0,
                    canIncrease: selectedIndex(in: textScaleValues, for: appState.canvasDisplaySettings.textScale) < textScaleValues.count - 1,
                    onDecrease: { shiftTextScale(by: -1) },
                    onIncrease: { shiftTextScale(by: 1) }
                )

                ToolbarColorSelector(
                    title: LocalizedString.text("line_color"),
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
                Text(LocalizedString.text("realtime_info"))
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
                            sectionTitle(LocalizedString.text("permission_matrix_summary"), count: permissions.count)
                        }
                    )

                    DisclosureGroup(
                        isExpanded: $showPendingApprovals,
                        content: pendingApprovalContent,
                        label: {
                            sectionTitle(LocalizedString.text("pending_approval_messages"), count: pendingApprovals.count)
                        }
                    )

                    DisclosureGroup(
                        isExpanded: $showExecutionLogs,
                        content: executionLogsContent,
                        label: {
                            sectionTitle(LocalizedString.executionLogs, count: executionLogs.count)
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
                summaryPill(LocalizedString.text("allow_label"), value: allowCount, color: .green)
                summaryPill(LocalizedString.text("deny_label"), value: denyCount, color: .red)
                summaryPill(LocalizedString.text("approval"), value: approvalCount, color: .orange)
            }

            if permissions.isEmpty {
                Text(LocalizedString.text("no_permission_rules"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(Array(permissions.prefix(8))) { permission in
                    HStack(spacing: 6) {
                        Text("\(agentName(for: permission.fromAgentID)) → \(agentName(for: permission.toAgentID))")
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()
                        Label(permission.permissionType.displayName, systemImage: permission.permissionType.icon)
                            .font(.caption2)
                            .foregroundColor(permission.permissionType.color)
                    }
                    .padding(.vertical, 2)
                }

                if permissions.count > 8 {
                    Text(LocalizedString.format("remaining_rules_count", permissions.count - 8))
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
                Text(LocalizedString.text("no_pending_approval_messages"))
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
                        Text(message.summaryText)
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
                Text(LocalizedString.text("no_execution_logs"))
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
                        if let routingBadge = entry.routingBadge {
                            Text(routingBadge)
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(routingLogColor(entry).opacity(0.14))
                                .foregroundColor(routingLogColor(entry))
                                .clipShape(Capsule())
                        }
                        Text(entry.message)
                            .font(.caption2)
                            .foregroundColor(entry.isRoutingEvent ? routingLogColor(entry) : .primary)
                            .lineLimit(2)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(entry.isRoutingEvent ? routingLogColor(entry).opacity(0.06) : Color.clear)
                    .cornerRadius(8)
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

    private func routingLogColor(_ entry: ExecutionLogEntry) -> Color {
        switch entry.routingBadge {
        case "STOP": return .orange
        case "WARN", "MISS": return .red
        case "QUEUE": return .blue
        case "ROUTE": return .purple
        default: return logLevelColor(entry.level)
        }
    }
}

struct ToolbarCustomizationSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(LocalizedString.text("toolbar_customize_title"))
                    .font(.headline)
                Spacer()
                Button(LocalizedString.text("toolbar_customize_done")) {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                Text(LocalizedString.text("toolbar_customize_description"))
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
                    Button(LocalizedString.text("toolbar_reset_default")) {
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
            return LocalizedString.text("toolbar_view_description")
        case .display:
            return LocalizedString.text("toolbar_display_description")
        case .language:
            return LocalizedString.text("toolbar_language_description")
        }
    }
}
