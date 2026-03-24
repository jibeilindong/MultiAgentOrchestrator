//
//  OpenClawConfigView.swift
//  Multi-Agent-Flow
//

import AppKit
import Combine
import SwiftUI

struct OpenClawConfigView: View {
    private struct ManagedRuntimeRecommendation {
        let title: String
        let detail: String
        let color: Color
    }

    @EnvironmentObject var appState: AppState
    @ObservedObject private var openClawManager = OpenClawManager.shared
    @State private var config: OpenClawConfig = .default
    @State private var isTesting = false
    @State private var isSaving = false
    @State private var isSyncingSession = false
    @State private var isMutatingManagedRuntime = false
    @State private var testResult: String?
    @State private var statusMessage: String?
    @State private var statusTone: StatusTone = .neutral
    @State private var lastTestedFingerprint: String?
    @State private var lastTestSucceeded = false
    @State private var isPresentingImportSheet = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(LocalizedString.text("openclaw_connection_title"))
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text(LocalizedString.text("openclaw_connection_hint"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                statusBanner
                attachmentStatusSection

                GroupBox(LocalizedString.text("deployment")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker(LocalizedString.text("deployment"), selection: $config.deploymentKind) {
                            ForEach(OpenClawDeploymentKind.allCases) { kind in
                                Text(kind.title).tag(kind)
                            }
                        }
                        .pickerStyle(.segmented)

                        if config.deploymentKind == .local {
                            labeledField("Local runtime ownership") {
                                Picker("Local runtime ownership", selection: $config.runtimeOwnership) {
                                    ForEach(OpenClawRuntimeOwnership.allCases) { ownership in
                                        Text(ownership.title).tag(ownership)
                                    }
                                }
                                .pickerStyle(.segmented)
                            }

                            if config.usesManagedLocalRuntime {
                                Toggle(
                                    "应用退出时停止托管 Runtime",
                                    isOn: stopManagedRuntimeOnApplicationTerminationBinding
                                )
                                .toggleStyle(.switch)

                                Toggle(
                                    "Runtime 崩溃后自动拉起",
                                    isOn: $config.managedRuntimeAutoRestartOnCrash
                                )
                                .toggleStyle(.switch)
                            }
                        }

                        if config.requiresExplicitLocalBinaryPath {
                            labeledField(LocalizedString.text("openclaw_binary")) {
                                TextField(LocalizedString.text("openclaw_binary"), text: $config.localBinaryPath)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }

                        if config.deploymentKind == .container {
                            labeledField(LocalizedString.text("container_engine")) {
                                TextField(LocalizedString.text("container_engine"), text: $config.container.engine)
                                    .textFieldStyle(.roundedBorder)
                            }
                            labeledField(LocalizedString.text("container_name")) {
                                TextField(LocalizedString.text("container_name"), text: $config.container.containerName)
                                    .textFieldStyle(.roundedBorder)
                            }
                            labeledField(LocalizedString.text("workspace_mount")) {
                                TextField(LocalizedString.text("workspace_mount"), text: $config.container.workspaceMountPath)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                    }
                }

                if showsManagedRuntimeSection {
                    managedRuntimeSection
                }

                GroupBox(LocalizedString.text("connection_settings_title")) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            labeledField(LocalizedString.host) {
                                TextField(LocalizedString.host, text: $config.host)
                                    .textFieldStyle(.roundedBorder)
                            }

                            labeledField(LocalizedString.port) {
                                TextField(LocalizedString.port, value: $config.port, format: .number)
                                    .textFieldStyle(.roundedBorder)
                            }
                            .frame(width: 140)
                        }

                        HStack(spacing: 20) {
                            Toggle(LocalizedString.text("use_ssl"), isOn: $config.useSSL)
                            Toggle(LocalizedString.text("auto_connect_startup"), isOn: $config.autoConnect)
                        }
                    }
                }

                GroupBox(LocalizedString.text("authentication_timeout")) {
                    VStack(alignment: .leading, spacing: 12) {
                        labeledField(LocalizedString.apiKey) {
                            SecureField(LocalizedString.apiKey, text: $config.apiKey)
                                .textFieldStyle(.roundedBorder)
                        }

                        HStack(spacing: 12) {
                            labeledField(LocalizedString.timeout) {
                                TextField(LocalizedString.timeout, value: $config.timeout, format: .number)
                                    .textFieldStyle(.roundedBorder)
                            }
                            .frame(width: 140)

                            Text(LocalizedString.seconds)
                                .foregroundColor(.secondary)
                                .padding(.top, 20)
                        }
                    }
                }

                GroupBox(LocalizedString.text("cli_output")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle(LocalizedString.text("quiet_mode_supported"), isOn: $config.cliQuietMode)

                        labeledField(LocalizedString.text("log_level")) {
                            Picker(LocalizedString.text("log_level"), selection: $config.cliLogLevel) {
                                ForEach(OpenClawCLILogLevel.allCases) { level in
                                    Text(level.title).tag(level)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                    }
                }

                HStack(spacing: 12) {
                    Button(action: testConnection) {
                        HStack(spacing: 8) {
                            if isTesting {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text(isTesting ? LocalizedString.text("detecting") : LocalizedString.autoDetect)
                        }
                    }
                    .disabled(isTesting || isSaving || !canTestConnection)

                    Button(action: saveConfig) {
                        HStack(spacing: 8) {
                            if isSaving {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text(isSaving ? LocalizedString.saving : LocalizedString.text("save_config"))
                        }
                    }
                    .disabled(isTesting || isSaving)

                    Button(action: connectNow) {
                        Text(LocalizedString.text("manual_connect_label"))
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isTesting || isSaving || !canTestConnection)

                    Button(action: attachCurrentProject) {
                        Text(LocalizedString.text("attach_current_project"))
                    }
                    .buttonStyle(.bordered)
                    .disabled(isTesting || isSaving || isSyncingSession || !canAttachCurrentProject)

                    Button(action: syncCurrentSession) {
                        HStack(spacing: 8) {
                            if isSyncingSession {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text(isSyncingSession ? "正在同步会话..." : "同步当前会话")
                        }
                    }
                    .disabled(isTesting || isSaving || isSyncingSession || !canSyncCurrentSession)
                }

                if let testResult {
                    Text(testResult)
                        .font(.footnote)
                        .foregroundColor(lastTestSucceeded ? .green : .red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                detectedAgentsSection
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(isPresented: $isPresentingImportSheet) {
            OpenClawAgentImportSheet(
                records: appState.openClawManager.discoveryResults,
                actionTitle: LocalizedString.text("import_these_agents_title"),
                onImport: { selections in
                    let imported = appState.importDetectedOpenClawAgents(selections: selections)
                    if imported.isEmpty {
                        testResult = LocalizedString.text("no_agents_selected_for_import")
                        statusMessage = LocalizedString.text("no_agents_imported")
                        statusTone = .error
                    } else {
                        testResult = LocalizedString.format("agents_imported_done", imported.count)
                        statusMessage = LocalizedString.text("agents_imported_status")
                        statusTone = .success
                    }
                }
            )
        }
        .onAppear {
            config = openClawManager.config
            refreshStatusFromManager()
            refreshManagedRuntimeStatus()
        }
        .onChange(of: configFingerprint(config)) { _, newFingerprint in
            if let lastTestedFingerprint, lastTestedFingerprint != newFingerprint {
                lastTestSucceeded = false
                statusMessage = LocalizedString.text("config_modified_retest")
                statusTone = .neutral
            }
        }
        .onChange(of: config.deploymentKind) { _, _ in
            refreshManagedRuntimeStatus()
            refreshStatusFromManager()
        }
        .onChange(of: config.runtimeOwnership) { _, _ in
            refreshManagedRuntimeStatus()
            refreshStatusFromManager()
        }
        .onReceive(openClawManager.$managedRuntimeStatus) { _ in
            refreshStatusFromManager()
        }
        .onReceive(openClawManager.$status) { _ in
            refreshStatusFromManager()
        }
    }
    
    private var canTestConnection: Bool {
        switch config.deploymentKind {
        case .local:
            return !config.requiresExplicitLocalBinaryPath
                || !config.localBinaryPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .remoteServer:
            return !config.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .container:
            return !config.container.containerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var canSyncCurrentSession: Bool {
        appState.currentProject != nil
            && appState.isCurrentProjectAttachedToOpenClaw
            && appState.openClawManager.canAttachProject
            && appState.openClawManager.config.deploymentKind != .remoteServer
    }

    private var canAttachCurrentProject: Bool {
        guard let currentProject = appState.currentProject else { return false }
        return appState.openClawManager.canAttachProject
            && appState.openClawManager.config.deploymentKind != .remoteServer
            && (
                !appState.openClawManager.hasAttachedProjectSession
                || appState.openClawManager.attachedProjectID != currentProject.id
            )
    }

    private var showsManagedRuntimeSection: Bool {
        config.usesManagedLocalRuntime
    }

    private var managedRuntimeSnapshot: OpenClawManagedRuntimeStatusSnapshot {
        openClawManager.managedRuntimeStatus
    }

    private var canRefreshManagedRuntime: Bool {
        !isTesting && !isSaving && !isSyncingSession && !isMutatingManagedRuntime
    }

    private var canStartManagedRuntime: Bool {
        canRefreshManagedRuntime && managedRuntimeSnapshot.state != .running && managedRuntimeSnapshot.state != .starting
    }

    private var canStopManagedRuntime: Bool {
        canRefreshManagedRuntime && (managedRuntimeSnapshot.state == .running || managedRuntimeSnapshot.state == .starting || managedRuntimeSnapshot.processID != nil)
    }

    private var canRestartManagedRuntime: Bool {
        canRefreshManagedRuntime && (managedRuntimeSnapshot.state == .running || managedRuntimeSnapshot.state == .failed || managedRuntimeSnapshot.processID != nil)
    }

    private var managedRuntimeTitle: String {
        switch managedRuntimeSnapshot.state {
        case .running: return "运行中"
        case .starting: return "启动中"
        case .stopping: return "停止中"
        case .failed: return "失败"
        case .idle: return "未运行"
        case .unmanaged: return "未托管"
        }
    }

    private var managedRuntimeColor: Color {
        switch managedRuntimeSnapshot.state {
        case .running:
            return .green
        case .starting, .stopping:
            return .orange
        case .failed:
            return .red
        case .idle, .unmanaged:
            return .secondary
        }
    }

    private var managedRuntimeSummary: String {
        managedRuntimeSnapshot.lastMessage ?? "托管 OpenClaw Runtime 状态尚未刷新。"
    }

    private var managedRuntimeLaunchStrategyText: String {
        switch managedRuntimeSnapshot.launchStrategy {
        case .foregroundGateway:
            return "Foreground Gateway"
        case .daemonCLI:
            return "Daemon CLI"
        case .none:
            return "未确定"
        }
    }

    private var managedRuntimeTerminationBehaviorText: String {
        switch config.managedRuntimeTerminationBehavior {
        case .stopWithApplication:
            return "应用退出即停止"
        case .keepRunning:
            return "应用退出后保持运行"
        }
    }

    private var managedRuntimeCrashRecoveryText: String {
        config.managedRuntimeAutoRestartOnCrash ? "自动恢复已启用" : "需要手动恢复"
    }

    private var managedRuntimeOwnershipSummaryText: String {
        switch config.runtimeOwnership {
        case .appManaged:
            return "应用私有 Runtime，不复用 ~/.openclaw 或系统 PATH 中的 openclaw。"
        case .externalLocal:
            return "显式使用用户指定的本地 openclaw 二进制。"
        }
    }

    private var managedRuntimeRestartSummaryText: String {
        "总计 \(managedRuntimeSnapshot.restartCount) 次，手动 \(managedRuntimeSnapshot.manualRestartCount) 次，自动恢复 \(managedRuntimeSnapshot.automaticRecoveryCount) 次"
    }

    private var managedRuntimeEndpointText: String {
        let scheme = config.useSSL ? "wss" : "ws"
        let port = managedRuntimeSnapshot.port ?? config.port
        return "\(scheme)://\(config.host):\(port)"
    }

    private var managedRuntimePortResolutionText: String? {
        guard let requestedPort = managedRuntimeSnapshot.requestedPort else { return nil }
        let actualPort = managedRuntimeSnapshot.port ?? config.port
        guard requestedPort != actualPort else { return nil }
        return "首选端口 \(requestedPort) 已避让，当前实际使用 \(actualPort)"
    }

    private var managedRuntimeRecoveryProgressText: String? {
        guard let attempt = managedRuntimeSnapshot.automaticRecoveryAttempt else { return nil }
        return "正在进行第 \(attempt) 次自动恢复"
    }

    private var managedRuntimeCrashSummaryText: String? {
        guard managedRuntimeSnapshot.consecutiveCrashCount > 0 else { return nil }
        return "当前连续异常退出 \(managedRuntimeSnapshot.consecutiveCrashCount) 次"
    }

    private var managedRuntimeRecommendation: ManagedRuntimeRecommendation? {
        if managedRuntimeSnapshot.state == .failed && managedRuntimeSnapshot.consecutiveCrashCount > 0 {
            return ManagedRuntimeRecommendation(
                title: "Runtime 进入异常恢复阶段",
                detail: "检测到连续异常退出，建议优先打开日志或导出诊断，再决定是否继续手动重启。",
                color: .red
            )
        }

        if managedRuntimeSnapshot.state == .starting,
           managedRuntimeSnapshot.automaticRecoveryAttempt != nil {
            return ManagedRuntimeRecommendation(
                title: "Supervisor 正在自动恢复",
                detail: "当前 sidecar 正在执行自动恢复，建议先等待本轮恢复完成，再观察是否需要人工介入。",
                color: .orange
            )
        }

        if managedRuntimeSnapshot.state == .running && !openClawManager.isConnected {
            return ManagedRuntimeRecommendation(
                title: "Runtime 已运行，但控制面未连通",
                detail: "sidecar 已经启动成功，现在最有价值的下一步是连接控制面，确认 Gateway 探测与能力协商是否完成。",
                color: .orange
            )
        }

        if managedRuntimeSnapshot.state == .running && appState.isCurrentProjectAttachedToOpenClaw && canSyncCurrentSession {
            return ManagedRuntimeRecommendation(
                title: "当前项目已接入，可继续同步",
                detail: "如果你刚修改了本地 agents、workspace 或 SOUL，建议立即同步当前会话，把变更推送到运行时侧。",
                color: .blue
            )
        }

        if managedRuntimeSnapshot.state == .running && canAttachCurrentProject {
            return ManagedRuntimeRecommendation(
                title: "控制面已就绪，可附加当前项目",
                detail: "当前 Runtime 已具备接管项目上下文的条件，下一步建议执行附加，让聊天/执行共用同一个运行时视角。",
                color: .green
            )
        }

        if managedRuntimeSnapshot.state == .idle {
            return ManagedRuntimeRecommendation(
                title: "Runtime 尚未启动",
                detail: "当前是 sidecar 托管模式，建议直接启动 Runtime，让应用进入“可连接、可附加、可同步”的完整控制面流程。",
                color: .secondary
            )
        }

        return nil
    }

    private var managedRuntimeLogURL: URL? {
        existingItemURL(from: managedRuntimeSnapshot.logPath)
    }

    private var managedRuntimeRootURL: URL? {
        existingItemURL(from: managedRuntimeSnapshot.runtimeRootPath)
    }

    private var managedRuntimeSupervisorRootURL: URL? {
        existingItemURL(from: managedRuntimeSnapshot.supervisorRootPath)
    }

    private var managedRuntimeDiagnosticSummary: String {
        openClawManager.managedRuntimeDiagnosticSummary(using: managedRuntimeSnapshot)
    }

    private var runtimeSourceDescriptor: OpenClawRuntimeSourceDescriptor {
        openClawManager.runtimeSourceDescriptor(
            using: managedRuntimeSnapshot,
            config: config
        )
    }

    private var runtimeSourceColor: Color {
        switch config.deploymentKind {
        case .local:
            return config.runtimeOwnership == .appManaged ? .green : .orange
        case .container:
            return .blue
        case .remoteServer:
            return .purple
        }
    }

    private var stopManagedRuntimeOnApplicationTerminationBinding: Binding<Bool> {
        Binding(
            get: { config.managedRuntimeTerminationBehavior == .stopWithApplication },
            set: { shouldStop in
                config.managedRuntimeTerminationBehavior = shouldStop ? .stopWithApplication : .keepRunning
            }
        )
    }

    private var sessionLifecycleHint: String {
        appState.openClawRuntimeControlPlaneSummary
    }

    private var runtimeStatusTitle: String {
        if appState.openClawManager.isConnected {
            return LocalizedString.text("connected_status")
        }
        if appState.openClawManager.connectionState.isRunnableWithDegradedCapabilities {
            return LocalizedString.text("degraded_status")
        }
        return LocalizedString.text("disconnected_status")
    }

    private var runtimeStatusColor: Color {
        if appState.openClawManager.isConnected {
            return .green
        }
        if appState.openClawManager.connectionState.isRunnableWithDegradedCapabilities {
            return .orange
        }
        return .secondary
    }

    private var attachmentStatusColor: Color {
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

    private var latestRuntimeSyncColor: Color {
        switch appState.latestOpenClawRuntimeSyncReceipt?.status {
        case .succeeded:
            return .green
        case .partial:
            return .orange
        case .failed:
            return .red
        case .none:
            return .secondary
        }
    }

    @ViewBuilder
    private var managedRuntimeSection: some View {
        GroupBox("Managed Runtime") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    statusPill(
                        label: "Supervisor",
                        value: managedRuntimeTitle,
                        color: managedRuntimeColor
                    )
                    statusPill(
                        label: "Strategy",
                        value: managedRuntimeLaunchStrategyText,
                        color: managedRuntimeColor
                    )

                    if let processID = managedRuntimeSnapshot.processID {
                        statusPill(
                            label: "PID",
                            value: "\(processID)",
                            color: managedRuntimeColor
                        )
                    }

                    statusPill(
                        label: "Port",
                        value: "\(managedRuntimeSnapshot.port ?? config.port)",
                        color: managedRuntimeColor
                    )
                }

                Text(managedRuntimeSummary)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let recommendation = managedRuntimeRecommendation {
                    managedRuntimeRecommendationCard(recommendation)
                }

                if let lastError = managedRuntimeSnapshot.lastError?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !lastError.isEmpty,
                   lastError != managedRuntimeSummary {
                    Text(lastError)
                        .font(.caption)
                        .foregroundColor(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let logPath = managedRuntimeSnapshot.logPath, !logPath.isEmpty {
                    infoLine(label: "日志", value: logPath)
                }
                if let binaryPath = managedRuntimeSnapshot.binaryPath, !binaryPath.isEmpty {
                    infoLine(label: "Binary", value: binaryPath)
                }
                if let runtimeRootPath = managedRuntimeSnapshot.runtimeRootPath, !runtimeRootPath.isEmpty {
                    infoLine(label: "Runtime Root", value: runtimeRootPath)
                }
                if let supervisorRootPath = managedRuntimeSnapshot.supervisorRootPath, !supervisorRootPath.isEmpty {
                    infoLine(label: "Supervisor Root", value: supervisorRootPath)
                }
                infoLine(label: "Gateway Endpoint", value: managedRuntimeEndpointText)
                infoLine(label: "隔离模式", value: managedRuntimeOwnershipSummaryText)
                infoLine(label: "退出策略", value: managedRuntimeTerminationBehaviorText)
                infoLine(label: "崩溃恢复", value: managedRuntimeCrashRecoveryText)
                infoLine(label: "重启统计", value: managedRuntimeRestartSummaryText)

                if let portResolution = managedRuntimePortResolutionText {
                    infoLine(label: "端口避让", value: portResolution)
                }

                if let recoveryProgress = managedRuntimeRecoveryProgressText {
                    infoLine(label: "恢复进度", value: recoveryProgress)
                }

                if let crashSummary = managedRuntimeCrashSummaryText {
                    infoLine(label: "崩溃状态", value: crashSummary)
                }

                if let lastUnexpectedExitAt = managedRuntimeSnapshot.lastUnexpectedExitAt {
                    infoLine(label: "最近异常退出", value: formattedTimestamp(lastUnexpectedExitAt))
                }

                if let lastRecoveryAttemptAt = managedRuntimeSnapshot.lastRecoveryAttemptAt {
                    infoLine(label: "最近恢复尝试", value: formattedTimestamp(lastRecoveryAttemptAt))
                }

                if let lastRecoverySucceededAt = managedRuntimeSnapshot.lastRecoverySucceededAt {
                    infoLine(label: "最近恢复成功", value: formattedTimestamp(lastRecoverySucceededAt))
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("快速操作")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)

                    HStack(spacing: 12) {
                        Button("打开日志", action: openManagedRuntimeLog)
                            .disabled(managedRuntimeLogURL == nil)

                        Button("在 Finder 显示日志", action: revealManagedRuntimeLog)
                            .disabled(managedRuntimeLogURL == nil)

                        Button("打开 Runtime Root") {
                            openManagedRuntimeDirectory(managedRuntimeRootURL, label: "Runtime Root")
                        }
                        .disabled(managedRuntimeRootURL == nil)

                        Button("打开 Supervisor Root") {
                            openManagedRuntimeDirectory(managedRuntimeSupervisorRootURL, label: "Supervisor Root")
                        }
                        .disabled(managedRuntimeSupervisorRootURL == nil)
                    }

                    HStack(spacing: 12) {
                        Button("复制诊断", action: copyManagedRuntimeDiagnostics)
                        Button("导出诊断", action: exportManagedRuntimeDiagnostics)
                    }
                }

                HStack(spacing: 12) {
                    Button(action: refreshManagedRuntimeStatus) {
                        HStack(spacing: 8) {
                            if isMutatingManagedRuntime {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text(isMutatingManagedRuntime ? "处理中..." : "刷新状态")
                        }
                    }
                    .disabled(!canRefreshManagedRuntime)

                    Button("启动 Runtime", action: startManagedRuntime)
                        .disabled(!canStartManagedRuntime)

                    Button("停止 Runtime", action: stopManagedRuntime)
                        .disabled(!canStopManagedRuntime)

                    Button("重启 Runtime", action: restartManagedRuntime)
                        .disabled(!canRestartManagedRuntime)
                }

                if let lastHeartbeatAt = managedRuntimeSnapshot.lastHeartbeatAt {
                    Text("最近心跳：\(lastHeartbeatAt.formatted(date: .abbreviated, time: .standard))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else if let lastStartedAt = managedRuntimeSnapshot.lastStartedAt {
                    Text("最近启动：\(lastStartedAt.formatted(date: .abbreviated, time: .standard))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var attachmentStatusSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                statusPill(
                    label: LocalizedString.text("status"),
                    value: runtimeStatusTitle,
                    color: runtimeStatusColor
                )
                statusPill(
                    label: LocalizedString.text("openclaw_attachment_status_label"),
                    value: appState.openClawAttachmentStatusTitle,
                    color: attachmentStatusColor
                )
                statusPill(
                    label: "控制面",
                    value: appState.openClawRuntimeControlPlaneBadgeTitle,
                    color: appState.openClawRuntimeControlPlaneBadgeColor
                )
                statusPill(
                    label: "来源",
                    value: runtimeSourceDescriptor.badgeTitle,
                    color: runtimeSourceColor
                )
            }

            Text(sessionLifecycleHint)
                .font(.footnote)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(runtimeSourceDescriptor.summary)
                .font(.caption)
                .foregroundColor(runtimeSourceColor)
                .fixedSize(horizontal: false, vertical: true)

            Text(runtimeSourceDescriptor.detail)
                .font(.caption2)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let endpoint = runtimeSourceDescriptor.endpoint {
                Text("当前 Endpoint: \(endpoint)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let binaryPath = runtimeSourceDescriptor.binaryPath, !binaryPath.isEmpty {
                Text("当前 Binary: \(binaryPath)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if sessionLifecycleHint != appState.openClawAttachmentStatusDetail {
                Text(appState.openClawAttachmentStatusDetail)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let revisionSummary = appState.openClawRevisionSummary {
                Text(revisionSummary)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let runtimeSyncSummary = appState.openClawLatestRuntimeSyncSummary {
                Text("\(LocalizedString.text("openclaw_runtime_sync_status_label")): \(runtimeSyncSummary)")
                    .font(.caption)
                    .foregroundColor(latestRuntimeSyncColor)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let runtimeSyncDetail = appState.openClawLatestRuntimeSyncDetail {
                Text(runtimeSyncDetail)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            runtimeSyncDiagnosticsSection
        }
    }

    @ViewBuilder
    private var runtimeSyncDiagnosticsSection: some View {
        if appState.hasOpenClawLatestRuntimeSyncDiagnostics {
            VStack(alignment: .leading, spacing: 8) {
                if let blockedReason = appState.openClawLatestRuntimeSyncBlockedReason {
                    runtimeSyncDiagnosticGroup(
                        title: LocalizedString.text("openclaw_runtime_sync_blocked_reason_label"),
                        items: [blockedReason],
                        color: latestRuntimeSyncColor
                    )
                }

                if !appState.openClawLatestRuntimeSyncIssueLines.isEmpty {
                    runtimeSyncDiagnosticGroup(
                        title: LocalizedString.text("openclaw_runtime_sync_step_issues_label"),
                        items: appState.openClawLatestRuntimeSyncIssueLines,
                        color: appState.latestOpenClawRuntimeSyncReceipt?.status == .failed ? .red : .orange
                    )
                }

                if !appState.openClawLatestRuntimeSyncWarnings.isEmpty {
                    runtimeSyncDiagnosticGroup(
                        title: LocalizedString.text("openclaw_runtime_sync_warnings_label"),
                        items: appState.openClawLatestRuntimeSyncWarnings,
                        color: .orange
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var statusBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: statusIconName)
                .foregroundColor(statusTone.color)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                Text(statusTitle)
                    .font(.headline)
                Text(statusMessage ?? LocalizedString.text("connection_status_here"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(statusTone.color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func statusPill(label: String, value: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .foregroundColor(.secondary)
            Text(value)
                .fontWeight(.semibold)
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.12))
        .foregroundColor(color)
        .clipShape(Capsule())
    }

    @ViewBuilder
    private func runtimeSyncDiagnosticGroup(title: String, items: [String], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(color)

            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 6) {
                    Circle()
                        .fill(color)
                        .frame(width: 5, height: 5)
                        .padding(.top, 5)
                    Text(item)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(10)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private func infoLine(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.caption2)
                .foregroundColor(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func managedRuntimeRecommendationCard(_ recommendation: ManagedRuntimeRecommendation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(recommendation.title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(recommendation.color)

            Text(recommendation.detail)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(recommendation.color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func formattedTimestamp(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .standard)
    }

    private var statusTitle: String {
        switch statusTone {
        case .success: return LocalizedString.text("connection_confirmed")
        case .error: return LocalizedString.text("connection_not_ready")
        case .neutral: return LocalizedString.text("awaiting_confirmation")
        }
    }

    private var statusIconName: String {
        switch statusTone {
        case .success: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        case .neutral: return "info.circle.fill"
        }
    }

    @ViewBuilder
    private func labeledField<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            content()
        }
    }

    private func testConnection() {
        isTesting = true
        testResult = nil

        appState.detectOpenClawAgents(using: config) { success, message, _ in
            isTesting = false
            testResult = message
            lastTestedFingerprint = configFingerprint(config)
            lastTestSucceeded = success
            statusMessage = success
                ? LocalizedString.text("detection_complete_manual_connect")
                : LocalizedString.text("detection_failed_retry")
            statusTone = success ? .success : .error
        }
    }
    
    private func saveConfig() {
        isSaving = true
        openClawManager.config = config
        config.save()
        isSaving = false
        statusMessage = LocalizedString.text("config_saved_connect_next")
        statusTone = .neutral
        refreshManagedRuntimeStatus()
    }

    private func connectNow() {
        isSaving = true
        appState.connectOpenClaw(using: config) { success, message in
            isSaving = false
            testResult = message
            statusMessage = success ? message : LocalizedString.format("error_status", message)
            statusTone = success ? .success : .error
        }
    }

    private func refreshManagedRuntimeStatus() {
        managedRuntimeStatusUpdate {
            _ = openClawManager.refreshManagedRuntimeStatus(using: config)
            return true
        }
    }

    private func startManagedRuntime() {
        persistDraftConfigIfNeeded()
        isMutatingManagedRuntime = true
        openClawManager.startManagedRuntime { success, message in
            isMutatingManagedRuntime = false
            testResult = message
            lastTestSucceeded = success
            statusMessage = success ? message : LocalizedString.format("error_status", message)
            statusTone = success ? .success : .error
        }
    }

    private func stopManagedRuntime() {
        persistDraftConfigIfNeeded()
        isMutatingManagedRuntime = true
        openClawManager.stopManagedRuntime { success, message in
            isMutatingManagedRuntime = false
            testResult = message
            lastTestSucceeded = success
            statusMessage = success ? message : LocalizedString.format("error_status", message)
            statusTone = success ? .success : .error
        }
    }

    private func restartManagedRuntime() {
        persistDraftConfigIfNeeded()
        isMutatingManagedRuntime = true
        openClawManager.restartManagedRuntime { success, message in
            isMutatingManagedRuntime = false
            testResult = message
            lastTestSucceeded = success
            statusMessage = success ? message : LocalizedString.format("error_status", message)
            statusTone = success ? .success : .error
        }
    }

    private func attachCurrentProject() {
        isSyncingSession = true
        appState.attachCurrentProjectToOpenClaw { success, message in
            isSyncingSession = false
            testResult = message
            statusMessage = success ? message : LocalizedString.format("error_status", message)
            statusTone = success ? .success : .error
        }
    }

    private func syncCurrentSession() {
        isSyncingSession = true
        appState.syncOpenClawActiveSession { success, message in
            isSyncingSession = false
            testResult = message
            statusMessage = success ? message : LocalizedString.format("error_status", message)
            statusTone = success ? .success : .error
        }
    }

    private func refreshStatusFromManager() {
        switch openClawManager.status {
        case .connected:
            statusMessage = sessionLifecycleHint
            statusTone = .success
        case .connecting:
            statusMessage = showsManagedRuntimeSection
                ? managedRuntimeSummary
                : LocalizedString.text("processing_openclaw_session")
            statusTone = .neutral
        case .disconnected:
            statusMessage = showsManagedRuntimeSection
                ? managedRuntimeSummary
                : LocalizedString.text("current_not_confirmed")
            statusTone = .neutral
        case .error(let message):
            statusMessage = message
            statusTone = .error
        }
    }

    private func persistDraftConfigIfNeeded() {
        openClawManager.config = config
        config.save()
    }

    private func copyManagedRuntimeDiagnostics() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        if pasteboard.setString(managedRuntimeDiagnosticSummary, forType: .string) {
            testResult = "已复制 Managed Runtime 诊断信息。"
            statusMessage = "Managed Runtime 诊断已复制到剪贴板，可直接粘贴给开发者或附到问题单。"
            statusTone = .success
        } else {
            testResult = "复制 Managed Runtime 诊断失败。"
            statusMessage = "无法写入系统剪贴板，请稍后重试。"
            statusTone = .error
        }
    }

    private func exportManagedRuntimeDiagnostics() {
        let panel = NSSavePanel()
        panel.title = "导出 OpenClaw Managed Runtime 诊断"
        panel.nameFieldStringValue = "openclaw-managed-runtime-diagnostics-\(Date().formatted(date: .numeric, time: .omitted)).txt"

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            do {
                try managedRuntimeDiagnosticSummary.write(to: url, atomically: true, encoding: .utf8)
                testResult = "已导出 Managed Runtime 诊断。"
                statusMessage = "诊断文件已导出到 \(url.path)。"
                statusTone = .success
            } catch {
                testResult = "导出 Managed Runtime 诊断失败：\(error.localizedDescription)"
                statusMessage = "诊断导出失败，请检查目录权限或稍后重试。"
                statusTone = .error
            }
        }
    }

    private func openManagedRuntimeLog() {
        openManagedRuntimeFile(managedRuntimeLogURL, label: "日志文件")
    }

    private func revealManagedRuntimeLog() {
        guard let logURL = managedRuntimeLogURL else {
            testResult = "当前没有可显示的 Runtime 日志。"
            statusMessage = "日志文件尚未生成，通常需要先启动一次 Runtime。"
            statusTone = .error
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([logURL])
        testResult = "已在 Finder 中显示 Runtime 日志。"
        statusMessage = "你可以直接查看日志内容或复制给开发者分析。"
        statusTone = .success
    }

    private func openManagedRuntimeDirectory(_ directoryURL: URL?, label: String) {
        openManagedRuntimeFile(directoryURL, label: label)
    }

    private func managedRuntimeStatusUpdate(_ action: () -> Bool) {
        guard !isMutatingManagedRuntime else { return }
        isMutatingManagedRuntime = true
        let _ = action()
        isMutatingManagedRuntime = false
    }

    private func openManagedRuntimeFile(_ url: URL?, label: String) {
        guard let url else {
            testResult = "\(label) 当前不可用。"
            statusMessage = "相关路径尚未生成，请先启动 Runtime 或刷新状态。"
            statusTone = .error
            return
        }

        guard NSWorkspace.shared.open(url) else {
            testResult = "打开 \(label) 失败。"
            statusMessage = "系统暂时无法打开 \(label)，请检查路径是否仍然存在。"
            statusTone = .error
            return
        }

        testResult = "已打开 \(label)。"
        statusMessage = "\(label) 已在系统中打开。"
        statusTone = .success
    }

    private func existingItemURL(from rawPath: String?) -> URL? {
        let trimmed = rawPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        guard FileManager.default.fileExists(atPath: trimmed) else { return nil }
        return URL(fileURLWithPath: trimmed)
    }

    private func configFingerprint(_ config: OpenClawConfig) -> String {
        [
            config.deploymentKind.rawValue,
            config.runtimeOwnership.rawValue,
            config.managedRuntimeTerminationBehavior.rawValue,
            config.managedRuntimeAutoRestartOnCrash ? "auto-restart-on" : "auto-restart-off",
            config.host,
            "\(config.port)",
            config.useSSL ? "ssl" : "plain",
            config.apiKey,
            "\(config.timeout)",
            config.localBinaryPath,
            config.container.engine,
            config.container.containerName,
            config.container.workspaceMountPath,
            config.cliQuietMode ? "quiet-on" : "quiet-off",
            config.cliLogLevel.rawValue
        ].joined(separator: "|")
    }

    @ViewBuilder
    private var detectedAgentsSection: some View {
        let detectedAgents = appState.openClawManager.discoveryResults

        if !detectedAgents.isEmpty {
            GroupBox(LocalizedString.text("detection_results")) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(detectedAgents) { agent in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: agent.directoryValidated && agent.configValidated ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                                .foregroundColor(agent.directoryValidated && agent.configValidated ? .green : .orange)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(agent.name)
                                    .font(.headline)
                                Text(agent.issues.isEmpty ? LocalizedString.text("directory_openclaw_validated") : agent.issues.joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                if let path = agent.soulPath ?? agent.copiedToProjectPath ?? agent.directoryPath {
                                    Text(path)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 4)
                    }

                    HStack {
                        Spacer()
                        Button(LocalizedString.text("import_these_agents_title")) {
                            isPresentingImportSheet = true
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!appState.openClawManager.canAttachProject || detectedAgents.isEmpty)
                    }
                }
            }
        }
    }
}

struct OpenClawAgentManagementView: View {
    @EnvironmentObject var appState: AppState
    @State private var managedAgents: [OpenClawManager.ManagedAgentRecord] = []
    @State private var selectedManagedAgentID: String?
    @State private var managedSkillSlug: String = ""
    @State private var searchKeyword: String = ""
    @State private var searchResults: [OpenClawManager.ClawHubSkillRecord] = []
    @State private var managedAgentMessage: String?
    @State private var managedAgentTone: StatusTone = .neutral
    @State private var isRefreshingManagedAgents = false
    @State private var isMutatingManagedAgent = false
    @State private var isSearchingSkills = false

    private var config: OpenClawConfig { appState.openClawManager.config }

    private var canManageOpenClawAgents: Bool {
        appState.openClawManager.canAttachProject && config.deploymentKind != .remoteServer
    }

    private var selectedManagedAgent: OpenClawManager.ManagedAgentRecord? {
        guard let selectedManagedAgentID else { return nil }
        return managedAgents.first(where: { $0.id == selectedManagedAgentID })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(LocalizedString.text("openclaw_agent_management"))
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text(LocalizedString.text("openclaw_agent_management_hint"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                GroupBox(LocalizedString.text("agent_configuration")) {
                    VStack(alignment: .leading, spacing: 12) {
                        if !appState.openClawManager.canAttachProject {
                            Text(LocalizedString.text("complete_connection_first"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else if config.deploymentKind == .remoteServer {
                            Text(LocalizedString.text("remote_gateway_no_local_edit"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            HStack(alignment: .center, spacing: 12) {
                                labeledField(LocalizedString.text("target_agent")) {
                                    Picker(LocalizedString.text("target_agent"), selection: Binding<String?>(
                                        get: { selectedManagedAgentID },
                                        set: { newValue in
                                            selectedManagedAgentID = newValue
                                            syncManagedAgentDrafts()
                                        }
                                    )) {
                                        Text(LocalizedString.text("please_select_agent")).tag(nil as String?)
                                        ForEach(managedAgents) { agent in
                                            Text(agentPickerLabel(for: agent)).tag(Optional(agent.id))
                                        }
                                    }
                                    .pickerStyle(.menu)
                                }

                                Spacer()

                                Button {
                                    refreshManagedAgentDataIfNeeded()
                                } label: {
                                    HStack(spacing: 8) {
                                        if isRefreshingManagedAgents {
                                            ProgressView()
                                                .controlSize(.small)
                                        }
                                        Text(isRefreshingManagedAgents ? LocalizedString.text("refreshing") : LocalizedString.text("refresh_list"))
                                    }
                                }
                                .disabled(isRefreshingManagedAgents)
                            }

                            if let selectedManagedAgent {
                                Divider()

                                VStack(alignment: .leading, spacing: 10) {
                                    infoRow(label: LocalizedString.text("project_agent"), value: selectedManagedAgent.name)
                                    infoRow(label: LocalizedString.text("openclaw_id"), value: selectedManagedAgent.targetIdentifier)
                                    if let configIndex = selectedManagedAgent.configIndex {
                                        infoRow(label: LocalizedString.text("config_index"), value: "\(configIndex)")
                                    }
                                    infoRow(label: LocalizedString.text("workspace"), value: selectedManagedAgent.workspacePath ?? LocalizedString.text("not_configured"))
                                    infoRow(label: LocalizedString.text("agent_dir"), value: selectedManagedAgent.agentDirPath ?? LocalizedString.text("not_configured"))
                                    infoRow(label: LocalizedString.text("current_model"), value: selectedManagedAgent.modelIdentifier.isEmpty ? LocalizedString.text("not_set") : selectedManagedAgent.modelIdentifier)

                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(LocalizedString.text("runtime_model_config_scope"))
                                            .font(.caption)
                                            .foregroundColor(.secondary)

                                        Text(LocalizedString.text("runtime_model_config_scope_hint"))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }

                                    Divider()

                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(LocalizedString.text("skill_installation"))
                                            .font(.caption)
                                            .foregroundColor(.secondary)

                                        HStack(spacing: 10) {
                                            TextField("clawhub skill slug", text: $managedSkillSlug)
                                                .textFieldStyle(.roundedBorder)

                                            Button {
                                                installManagedSkill()
                                            } label: {
                                                HStack(spacing: 8) {
                                                    if isMutatingManagedAgent {
                                                        ProgressView()
                                                            .controlSize(.small)
                                                    }
                                                    Text(LocalizedString.text("install_by_slug"))
                                                }
                                            }
                                            .buttonStyle(.borderedProminent)
                                            .disabled(isMutatingManagedAgent || managedSkillSlug.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                        }

                                        HStack(spacing: 10) {
                                            TextField(LocalizedString.text("search_clawhub_skill"), text: $searchKeyword)
                                                .textFieldStyle(.roundedBorder)
                                            Button {
                                                searchSkillsFromClawHub()
                                            } label: {
                                                HStack(spacing: 8) {
                                                    if isSearchingSkills {
                                                        ProgressView()
                                                            .controlSize(.small)
                                                    }
                                                    Text(isSearchingSkills ? LocalizedString.text("searching") : LocalizedString.text("search_install"))
                                                }
                                            }
                                            .buttonStyle(.bordered)
                                            .disabled(isSearchingSkills || isMutatingManagedAgent || searchKeyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                        }

                                        if !searchResults.isEmpty {
                                            VStack(alignment: .leading, spacing: 6) {
                                                ForEach(searchResults) { result in
                                                    HStack(spacing: 8) {
                                                        VStack(alignment: .leading, spacing: 2) {
                                                            Text(result.slug)
                                                                .font(.subheadline)
                                                            if !result.summary.isEmpty {
                                                                Text(result.summary)
                                                                    .font(.caption2)
                                                                    .foregroundColor(.secondary)
                                                                    .lineLimit(2)
                                                            }
                                                        }
                                                        Spacer()
                                                        Button(LocalizedString.text("install")) {
                                                            managedSkillSlug = result.slug
                                                            installManagedSkill()
                                                        }
                                                        .buttonStyle(.borderedProminent)
                                                        .disabled(isMutatingManagedAgent)
                                                    }
                                                    .padding(.vertical, 2)
                                                }
                                            }
                                        }

                                        if selectedManagedAgent.installedSkills.isEmpty {
                                            Text(LocalizedString.text("no_installed_skills"))
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        } else {
                                            ForEach(selectedManagedAgent.installedSkills) { skill in
                                                HStack(spacing: 8) {
                                                    VStack(alignment: .leading, spacing: 2) {
                                                        Text(skill.name)
                                                            .font(.subheadline)
                                                        Text(skill.path)
                                                            .font(.caption2)
                                                            .foregroundColor(.secondary)
                                                            .lineLimit(1)
                                                    }
                                                    Spacer()
                                                    Button(role: .destructive) {
                                                        removeManagedSkill(skill.name)
                                                    } label: {
                                                        Text(LocalizedString.text("remove"))
                                                    }
                                                    .buttonStyle(.bordered)
                                                    .disabled(isMutatingManagedAgent)
                                                }
                                                .padding(.vertical, 3)
                                            }
                                        }
                                    }
                                }
                            } else if !managedAgents.isEmpty {
                                Text(LocalizedString.text("select_agent_for_details"))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                Text(LocalizedString.text("no_openclaw_agent_config"))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                if let managedAgentMessage {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: managedAgentTone == .success ? "checkmark.circle.fill" : (managedAgentTone == .error ? "exclamationmark.triangle.fill" : "info.circle.fill"))
                            .foregroundColor(managedAgentTone.color)
                        Text(managedAgentMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                    }
                    .padding(10)
                    .background(managedAgentTone.color.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .padding(24)
        }
        .onAppear {
            refreshManagedAgentDataIfNeeded()
        }
    }

    @ViewBuilder
    private func labeledField<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            content()
        }
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 90, alignment: .leading)
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
            Spacer()
        }
    }

    private func agentPickerLabel(for agent: OpenClawManager.ManagedAgentRecord) -> String {
        if agent.name == agent.targetIdentifier {
            return agent.name
        }
        return "\(agent.name) -> \(agent.targetIdentifier)"
    }

    private func refreshManagedAgentDataIfNeeded() {
        guard canManageOpenClawAgents else {
            managedAgents = []
            selectedManagedAgentID = nil
            managedSkillSlug = ""
            searchResults = []
            managedAgentMessage = nil
            return
        }

        isRefreshingManagedAgents = true

        appState.openClawManager.loadManagedAgents(for: appState.currentProject, using: config) { success, message, records in
            isRefreshingManagedAgents = false
            if success {
                managedAgents = records
                managedAgentMessage = message
                managedAgentTone = .success

                if let selectedManagedAgentID {
                    if !records.contains(where: { $0.id == selectedManagedAgentID }) {
                        self.selectedManagedAgentID = records.first?.id
                    }
                } else {
                    selectedManagedAgentID = records.first?.id
                }
                syncManagedAgentDrafts()
            } else {
                managedAgents = []
                selectedManagedAgentID = nil
                managedSkillSlug = ""
                searchResults = []
                managedAgentMessage = message
                managedAgentTone = .error
            }
        }

    }

    private func syncManagedAgentDrafts() {
        guard selectedManagedAgent != nil else {
            managedSkillSlug = ""
            searchResults = []
            return
        }

        managedSkillSlug = ""
    }

    private func installManagedSkill() {
        guard let selectedManagedAgent else { return }

        let skill = managedSkillSlug.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !skill.isEmpty else { return }

        isMutatingManagedAgent = true
        appState.openClawManager.installSkill(skill, for: selectedManagedAgent, using: config) { success, message in
            isMutatingManagedAgent = false
            managedAgentMessage = message
            managedAgentTone = success ? .success : .error
            if success {
                refreshManagedAgentDataIfNeeded()
            }
        }
    }

    private func removeManagedSkill(_ skillName: String) {
        guard let selectedManagedAgent else { return }

        isMutatingManagedAgent = true
        appState.openClawManager.removeSkill(skillName, from: selectedManagedAgent, using: config) { success, message in
            isMutatingManagedAgent = false
            managedAgentMessage = message
            managedAgentTone = success ? .success : .error
            if success {
                refreshManagedAgentDataIfNeeded()
            }
        }
    }

    private func searchSkillsFromClawHub() {
        let keyword = searchKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else {
            searchResults = []
            return
        }

        isSearchingSkills = true
        appState.openClawManager.searchClawHubSkills(query: keyword, using: config) { success, message, records in
            isSearchingSkills = false
            searchResults = records
            managedAgentMessage = message
            managedAgentTone = success ? .success : .error
        }
    }
}

private enum StatusTone {
    case success
    case error
    case neutral

    var color: Color {
        switch self {
        case .success: return .green
        case .error: return .red
        case .neutral: return .accentColor
        }
    }
}
