import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @Binding var selectedTab: Int
    @Binding var zoomScale: CGFloat
    @State private var sidebarWidth: CGFloat = SettingsManager.shared.sidebarWidth
    @State private var realtimePanelWidth: CGFloat = SettingsManager.shared.realtimePanelWidth
    @State private var sidebarDragOriginWidth: CGFloat?
    @State private var realtimePanelDragOriginWidth: CGFloat?
    @State private var hoveredPanelHandle: PanelHandleKind?
    @StateObject private var workflowEditorSessionState = WorkflowEditorSessionState()
    @StateObject private var quickChatStore = QuickChatStore()
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

    private var openClawRuntimeSourceColor: Color {
        appState.openClawRuntimeSourceColor
    }

    private let sidebarWidthRange: ClosedRange<CGFloat> = 180...320
    private let realtimePanelWidthRange: ClosedRange<CGFloat> = 220...360
    private let minimumCenterWidth: CGFloat = 320
    private let defaultSidebarWidth: CGFloat = 250
    private let defaultRealtimePanelWidth: CGFloat = 280

    private var showsContextSidebar: Bool {
        selectedTab == 0
    }

    private var canUseCanvasViewportControls: Bool {
        selectedTab == 0 && workflowEditorSessionState.viewMode == .architecture
    }
    
    var body: some View {
        GeometryReader { geometry in
            let layout = shellLayout(
                for: geometry.size.width,
                showsSidebar: showsContextSidebar,
                preferredSidebarWidth: sidebarWidth,
                preferredRealtimePanelWidth: realtimePanelWidth
            )

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    if showsContextSidebar {
                        SidebarView(sessionState: workflowEditorSessionState)
                            .frame(width: layout.sidebarWidth)

                        panelResizeHandle(for: .sidebar, totalWidth: geometry.size.width)
                            .gesture(sidebarResizeGesture(totalWidth: geometry.size.width))
                    }

                    // 中间：主内容区
                    VStack(spacing: 0) {
                        HStack(spacing: 12) {
                            ProjectControlsView(style: .toolbar)
                                .environmentObject(appState)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(appState.toolbarItemsInDisplayOrder) { item in
                                        toolbarContent(for: item)
                                    }
                                }
                                .padding(.vertical, 1)
                            }
                            .scrollBounceBehavior(.basedOnSize)
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Spacer(minLength: 12)

                            pageNavigationToolbar
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.8))

                        Divider()

                        // 主内容
                        Group {
                            if selectedTab == 0 && appState.currentProject == nil {
                                ProjectOnboardingView(selectedTab: $selectedTab)
                                    .environmentObject(appState)
                            } else {
                                switch selectedTab {
                                case 0:
                                    WorkflowEditorView(
                                        zoomScale: $zoomScale,
                                        sessionState: workflowEditorSessionState
                                    )
                                case 1:
                                    WorkbenchConversationView(messageManager: appState.messageManager)
                                case 2:
                                    OpsCenterDashboardView(displayMode: .fullScreen)
                                case 3:
                                    TemplateLibraryManagerSheet(selectedTemplateID: $selectedTemplateLibraryID, showsCloseButton: false)
                                default:
                                    WorkflowEditorView(
                                        zoomScale: $zoomScale,
                                        sessionState: workflowEditorSessionState
                                    )
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }

                    panelResizeHandle(for: .realtimePanel, totalWidth: geometry.size.width)
                        .gesture(realtimePanelResizeGesture(totalWidth: geometry.size.width))

                    // 右侧：实时信息面板
                    RealtimeInfoPanel()
                        .frame(width: layout.realtimePanelWidth)
                }

                Divider()

                bottomStatusBar
            }
            .animation(.easeInOut(duration: 0.18), value: showsContextSidebar)
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
        .background(
            QuickChatWindowBridge(store: quickChatStore, appState: appState)
        )
        .sheet(item: $appState.workflowPackageImportPreview, onDismiss: {
            appState.cleanupWorkflowPackageImportPreview()
        }) { preview in
            WorkflowPackageImportPreviewSheet(preview: preview)
                .environmentObject(appState)
        }
        .onChange(of: appState.workflowPackageMessage) { _, newValue in
            guard let newValue else { return }
            openClawMessage = newValue
            appState.workflowPackageMessage = nil
        }
        .onChange(of: selectedTab) { _, newValue in
            guard newValue != 0 else { return }
            sidebarDragOriginWidth = nil
            if hoveredPanelHandle == .sidebar {
                hoveredPanelHandle = nil
                refreshPanelHandleCursor()
            }
        }
        .onChange(of: appState.activeWorkflowID) { _, _ in
            guard quickChatStore.isPresented else { return }
            quickChatStore.refreshContext(using: appState)
        }
        .onChange(of: appState.currentProject?.id) { _, _ in
            guard quickChatStore.isPresented else { return }
            quickChatStore.refreshContext(using: appState)
        }
    }

    @ViewBuilder
    private func toolbarContent(for item: ContentToolbarItem) -> some View {
        switch item {
        case .view:
            TopToolbarGroup {
                Menu {
                    Button(LocalizedString.zoomOut) {
                        zoomScale = max(zoomScale / 1.25, CanvasViewportConfiguration.zoomScaleRange.lowerBound)
                    }
                    Button(LocalizedString.resetZoom) {
                        zoomScale = 1.0
                    }
                    Button(LocalizedString.zoomIn) {
                        zoomScale = min(zoomScale * 1.25, CanvasViewportConfiguration.zoomScaleRange.upperBound)
                    }
                    if canUseCanvasViewportControls {
                        Divider()
                        Button(LocalizedString.fitToContent) {
                            workflowEditorSessionState.sendCanvasViewportCommand(.fitToContent)
                        }
                        Button(LocalizedString.centerContent) {
                            workflowEditorSessionState.sendCanvasViewportCommand(.centerContent)
                        }
                    }
                    Divider()
                    Button(appState.showLogs ? LocalizedString.text("hide_logs") : LocalizedString.text("show_logs")) {
                        appState.showLogs.toggle()
                    }
                } label: {
                    Label(LocalizedString.text("view_menu"), systemImage: "eye")
                }

                HStack(spacing: 4) {
                    Button(action: { zoomScale = max(zoomScale / 1.25, CanvasViewportConfiguration.zoomScaleRange.lowerBound) }) {
                        Image(systemName: "minus.magnifyingglass")
                    }
                    Text("\(Int(zoomScale * 100))%")
                        .font(.caption)
                        .frame(width: 44)
                    Button(action: { zoomScale = min(zoomScale * 1.25, CanvasViewportConfiguration.zoomScaleRange.upperBound) }) {
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
            HStack(spacing: 10) {
                bottomStatusChip(
                    title: openClawStatusBadgeTitle,
                    detail: appState.openClawManager.config.deploymentSummary,
                    color: openClawStatusColor
                )

                bottomStatusChip(
                    title: appState.openClawAttachmentStatusTitle,
                    detail: nil,
                    color: openClawAttachmentColor
                )

                bottomStatusChip(
                    title: appState.openClawRuntimeSourceBadgeTitle,
                    detail: appState.openClawRuntimeSourceEndpoint ?? appState.openClawRuntimeSourceSummary,
                    color: openClawRuntimeSourceColor
                )
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                runtimeActionButtons

                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: 1, height: 24)

                StatusBarButton(title: LocalizedString.text("check_connection"), icon: "arrow.triangle.2.circlepath") {
                    appState.openClawService.checkConnection()
                }

                StatusBarButton(title: LocalizedString.settings, icon: "gearshape") {
                    NotificationCenter.default.post(name: .openSettings, object: nil)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.controlBackgroundColor).opacity(0.86))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            LinearGradient(
                colors: [Color(.controlBackgroundColor).opacity(0.94), Color.white.opacity(0.82)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    @ViewBuilder
    private var runtimeActionButtons: some View {
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
    }

    private func bottomStatusChip(title: String, detail: String?, color: Color) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(.controlBackgroundColor).opacity(0.72))
        )
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

    private var pageNavigationToolbar: some View {
        chromeToolbarGroup {
            HStack(spacing: 10) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        pageNavigationButton(
                            title: LocalizedString.text("workflow_editor_nav"),
                            systemImage: "square.grid.2x2",
                            tag: 0
                        )

                        pageNavigationButton(
                            title: LocalizedString.text("workbench_nav"),
                            systemImage: "message.badge.waveform",
                            tag: 1
                        )

                        pageNavigationButton(
                            title: LocalizedString.text("monitoring_dashboard_nav"),
                            systemImage: "gauge.with.dots.needle.33percent",
                            tag: 2
                        )

                        pageNavigationButton(
                            title: LocalizedString.text("template_library_nav"),
                            systemImage: "shippingbox",
                            tag: 3
                        )
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxWidth: 440, alignment: .trailing)

                Divider()
                    .frame(height: 22)

                quickChatLauncherButton
            }
        }
    }

    private func pageNavigationButton(title: String, systemImage: String, tag: Int) -> some View {
        Button(action: { selectedTab = tag }) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .fontWeight(selectedTab == tag ? .semibold : .regular)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(selectedTab == tag ? Color.accentColor.opacity(0.18) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundColor(selectedTab == tag ? .accentColor : .secondary)
    }

    private var quickChatLauncherButton: some View {
        Button {
            quickChatStore.present(using: appState)
        } label: {
            Label("Quick Chat", systemImage: "bolt.bubble.fill")
                .font(.caption)
                .fontWeight(.semibold)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.accentColor.opacity(0.16))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundColor(.accentColor)
        .help("打开独立弹窗快聊，不进入 Workbench 主控制台")
    }

    @ViewBuilder
    private func chromeToolbarGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 8) {
            content()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.controlBackgroundColor).opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private func shellLayout(
        for totalWidth: CGFloat,
        showsSidebar: Bool,
        preferredSidebarWidth: CGFloat,
        preferredRealtimePanelWidth: CGFloat
    ) -> ContentShellLayout {
        let clampedWidth = max(totalWidth, 720)
        let sidebarWidth = showsSidebar ? clampSidebarWidth(preferredSidebarWidth, totalWidth: clampedWidth) : 0
        let realtimePanelWidth = clampRealtimePanelWidth(
            preferredRealtimePanelWidth,
            totalWidth: clampedWidth,
            sidebarWidth: sidebarWidth
        )
        return ContentShellLayout(
            sidebarWidth: sidebarWidth.rounded(),
            realtimePanelWidth: realtimePanelWidth.rounded()
        )
    }

    private func panelResizeHandle(for kind: PanelHandleKind, totalWidth: CGFloat) -> some View {
        let isHighlighted = hoveredPanelHandle == kind || isHandleDragging(kind)

        return ZStack {
            Rectangle()
                .fill(isHighlighted ? Color.accentColor.opacity(0.08) : Color.clear)

            Divider()
                .opacity(isHighlighted ? 0.35 : 1)

            Capsule()
                .fill(isHighlighted ? Color.accentColor.opacity(0.88) : Color.secondary.opacity(0.28))
                .frame(width: isHighlighted ? 4 : 3, height: isHighlighted ? 36 : 28)
        }
        .frame(width: 12)
        .contentShape(Rectangle())
        .onHover { isHovering in
            if isHovering {
                hoveredPanelHandle = kind
            } else if hoveredPanelHandle == kind {
                hoveredPanelHandle = nil
            }
            refreshPanelHandleCursor()
        }
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                resetPanelWidth(kind, totalWidth: totalWidth)
            }
        )
    }

    private func sidebarResizeGesture(totalWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let originWidth = sidebarDragOriginWidth ?? sidebarWidth
                if sidebarDragOriginWidth == nil {
                    sidebarDragOriginWidth = originWidth
                }
                sidebarWidth = clampSidebarWidth(originWidth + value.translation.width, totalWidth: totalWidth)
                refreshPanelHandleCursor()
            }
            .onEnded { value in
                let originWidth = sidebarDragOriginWidth ?? sidebarWidth
                let resolvedWidth = clampSidebarWidth(originWidth + value.translation.width, totalWidth: totalWidth)
                sidebarWidth = resolvedWidth
                sidebarDragOriginWidth = nil
                SettingsManager.shared.sidebarWidth = resolvedWidth
                refreshPanelHandleCursor()
            }
    }

    private func realtimePanelResizeGesture(totalWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let originWidth = realtimePanelDragOriginWidth ?? realtimePanelWidth
                if realtimePanelDragOriginWidth == nil {
                    realtimePanelDragOriginWidth = originWidth
                }
                realtimePanelWidth = clampRealtimePanelWidth(
                    originWidth - value.translation.width,
                    totalWidth: totalWidth,
                    sidebarWidth: showsContextSidebar ? sidebarWidth : 0
                )
                refreshPanelHandleCursor()
            }
            .onEnded { value in
                let originWidth = realtimePanelDragOriginWidth ?? realtimePanelWidth
                let resolvedWidth = clampRealtimePanelWidth(
                    originWidth - value.translation.width,
                    totalWidth: totalWidth,
                    sidebarWidth: showsContextSidebar ? sidebarWidth : 0
                )
                realtimePanelWidth = resolvedWidth
                realtimePanelDragOriginWidth = nil
                SettingsManager.shared.realtimePanelWidth = resolvedWidth
                refreshPanelHandleCursor()
            }
    }

    private func clampSidebarWidth(_ proposedWidth: CGFloat, totalWidth: CGFloat) -> CGFloat {
        let maxAllowed = min(sidebarWidthRange.upperBound, totalWidth - realtimePanelWidthRange.lowerBound - minimumCenterWidth)
        let effectiveUpperBound = max(sidebarWidthRange.lowerBound, maxAllowed)
        return min(max(proposedWidth, sidebarWidthRange.lowerBound), effectiveUpperBound)
    }

    private func clampRealtimePanelWidth(_ proposedWidth: CGFloat, totalWidth: CGFloat, sidebarWidth: CGFloat) -> CGFloat {
        let maxAllowed = min(realtimePanelWidthRange.upperBound, totalWidth - sidebarWidth - minimumCenterWidth)
        let effectiveUpperBound = max(realtimePanelWidthRange.lowerBound, maxAllowed)
        return min(max(proposedWidth, realtimePanelWidthRange.lowerBound), effectiveUpperBound)
    }

    private func isHandleDragging(_ kind: PanelHandleKind) -> Bool {
        switch kind {
        case .sidebar:
            return sidebarDragOriginWidth != nil
        case .realtimePanel:
            return realtimePanelDragOriginWidth != nil
        }
    }

    private var isAnyPanelHandleActive: Bool {
        hoveredPanelHandle != nil || sidebarDragOriginWidth != nil || realtimePanelDragOriginWidth != nil
    }

    private func refreshPanelHandleCursor() {
        if isAnyPanelHandleActive {
            NSCursor.resizeLeftRight.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    private func resetPanelWidth(_ kind: PanelHandleKind, totalWidth: CGFloat) {
        withAnimation(.easeInOut(duration: 0.18)) {
            switch kind {
            case .sidebar:
                let resolvedWidth = clampSidebarWidth(defaultSidebarWidth, totalWidth: totalWidth)
                sidebarWidth = resolvedWidth
                sidebarDragOriginWidth = nil
                SettingsManager.shared.sidebarWidth = resolvedWidth
            case .realtimePanel:
                let resolvedWidth = clampRealtimePanelWidth(
                    defaultRealtimePanelWidth,
                    totalWidth: totalWidth,
                    sidebarWidth: showsContextSidebar ? sidebarWidth : 0
                )
                realtimePanelWidth = resolvedWidth
                realtimePanelDragOriginWidth = nil
                SettingsManager.shared.realtimePanelWidth = resolvedWidth
            }
        }
    }

}

private struct ContentShellLayout {
    let sidebarWidth: CGFloat
    let realtimePanelWidth: CGFloat
}

private enum PanelHandleKind {
    case sidebar
    case realtimePanel
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

    private let textScaleValues: [CGFloat] = [0.85, 1.0, 1.15, 1.3, 1.5]

    var body: some View {
        TopToolbarGroup {
            HStack(spacing: 10) {
                ToolbarStepper(
                    title: LocalizedString.text("font_size"),
                    valueText: "\(Int(appState.canvasDisplaySettings.textScale * 100))%",
                    canDecrease: selectedIndex(in: textScaleValues, for: appState.canvasDisplaySettings.textScale) > 0,
                    canIncrease: selectedIndex(in: textScaleValues, for: appState.canvasDisplaySettings.textScale) < textScaleValues.count - 1,
                    onDecrease: { shiftTextScale(by: -1) },
                    onIncrease: { shiftTextScale(by: 1) }
                )
            }
        }
    }

    private func selectedIndex(in values: [CGFloat], for current: CGFloat) -> Int {
        values.firstIndex(where: { abs($0 - current) < 0.001 }) ?? 0
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

    private var criticalLogCount: Int {
        executionLogs.filter { $0.level == .error || $0.level == .warning }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            panelHeader

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    metricsStrip

                    panelSection(
                        title: LocalizedString.text("permission_matrix_summary"),
                        count: permissions.count,
                        isExpanded: $showPermissionSummary,
                        content: permissionSummaryContent
                    )

                    panelSection(
                        title: LocalizedString.text("pending_approval_messages"),
                        count: pendingApprovals.count,
                        isExpanded: $showPendingApprovals,
                        content: pendingApprovalContent
                    )

                    panelSection(
                        title: LocalizedString.executionLogs,
                        count: executionLogs.count,
                        isExpanded: $showExecutionLogs,
                        content: executionLogsContent
                    )
                }
                .padding(12)
            }
        }
        .background(Color(.windowBackgroundColor).opacity(0.9))
    }

    private var panelHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(LocalizedString.text("realtime_info"))
                        .font(.headline)
                    Text("权限、审批和执行日志")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "waveform.badge.magnifyingglass")
                    .font(.title3)
                    .foregroundColor(.accentColor)
                    .padding(10)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [Color(.controlBackgroundColor), Color(.controlBackgroundColor).opacity(0.82)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var metricsStrip: some View {
        HStack(spacing: 8) {
            panelMetric(title: LocalizedString.text("approval"), value: pendingApprovals.count, color: .orange)
            panelMetric(title: LocalizedString.executionLogs, value: executionLogs.count, color: .blue)
            panelMetric(title: "Alert", value: criticalLogCount, color: .red)
        }
    }

    private func panelMetric(title: String, value: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                Text("\(value)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(.controlBackgroundColor).opacity(0.78))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func panelSection<Content: View>(
        title: String,
        count: Int,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        DisclosureGroup(isExpanded: isExpanded) {
            content()
        } label: {
            sectionTitle(title, count: count)
        }
        .padding(12)
        .background(Color(.controlBackgroundColor).opacity(0.74))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                .clipShape(Capsule())
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
