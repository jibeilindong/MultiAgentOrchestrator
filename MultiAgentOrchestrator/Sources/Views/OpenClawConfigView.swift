//
//  OpenClawConfigView.swift
//  MultiAgentOrchestrator
//

import SwiftUI

struct OpenClawConfigView: View {
    @EnvironmentObject var appState: AppState
    @State private var config: OpenClawConfig = .default
    @State private var isTesting = false
    @State private var isSaving = false
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
                    Text("OpenClaw Connection")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("先测试当前配置是否可用，测试通过后点击 Save 即视为确认连接。")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                statusBanner

                GroupBox("Deployment") {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Deployment", selection: $config.deploymentKind) {
                            ForEach(OpenClawDeploymentKind.allCases) { kind in
                                Text(kind.title).tag(kind)
                            }
                        }
                        .pickerStyle(.segmented)

                        if config.deploymentKind == .local {
                            labeledField("OpenClaw Binary") {
                                TextField("OpenClaw Binary", text: $config.localBinaryPath)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }

                        if config.deploymentKind == .container {
                            labeledField("Container Engine") {
                                TextField("Container Engine", text: $config.container.engine)
                                    .textFieldStyle(.roundedBorder)
                            }
                            labeledField("Container Name") {
                                TextField("Container Name", text: $config.container.containerName)
                                    .textFieldStyle(.roundedBorder)
                            }
                            labeledField("Workspace Mount") {
                                TextField("Workspace Mount", text: $config.container.workspaceMountPath)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                    }
                }

                GroupBox("Connection Settings") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            labeledField("Host") {
                                TextField("Host", text: $config.host)
                                    .textFieldStyle(.roundedBorder)
                            }

                            labeledField("Port") {
                                TextField("Port", value: $config.port, format: .number)
                                    .textFieldStyle(.roundedBorder)
                            }
                            .frame(width: 140)
                        }

                        HStack(spacing: 20) {
                            Toggle("Use SSL", isOn: $config.useSSL)
                            Toggle("Auto Connect on Startup", isOn: $config.autoConnect)
                        }
                    }
                }

                GroupBox("Authentication & Timeout") {
                    VStack(alignment: .leading, spacing: 12) {
                        labeledField("API Key") {
                            SecureField("API Key", text: $config.apiKey)
                                .textFieldStyle(.roundedBorder)
                        }

                        HStack(spacing: 12) {
                            labeledField("Timeout") {
                                TextField("Timeout", value: $config.timeout, format: .number)
                                    .textFieldStyle(.roundedBorder)
                            }
                            .frame(width: 140)

                            Text("seconds")
                                .foregroundColor(.secondary)
                                .padding(.top, 20)
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
                            Text(isTesting ? "识别中..." : "自动识别")
                        }
                    }
                    .disabled(isTesting || isSaving || !canTestConnection)

                    Button(action: saveConfig) {
                        HStack(spacing: 8) {
                            if isSaving {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text(isSaving ? "保存中..." : "保存配置")
                        }
                    }
                    .disabled(isTesting || isSaving)

                    Button(action: connectNow) {
                        Text("手动连接")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isTesting || isSaving || !canTestConnection)
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
                actionTitle: "导入这些 Agents",
                onImport: { selectedIDs in
                    let imported = appState.importDetectedOpenClawAgents(selectedRecordIDs: selectedIDs)
                    if imported.isEmpty {
                        testResult = "没有选中可导入的 Agents。"
                        statusMessage = "未导入任何 Agents。"
                        statusTone = .error
                    } else {
                        testResult = "已导入 \(imported.count) 个 Agents。"
                        statusMessage = "已将选中的 Agents 导入到当前项目。"
                        statusTone = .success
                    }
                }
            )
        }
        .onAppear {
            config = appState.openClawManager.config
            refreshStatusFromManager()
        }
        .onChange(of: configFingerprint(config)) { _, newFingerprint in
            if let lastTestedFingerprint, lastTestedFingerprint != newFingerprint {
                lastTestSucceeded = false
                statusMessage = "配置已修改，请重新测试后再保存以确认连接。"
                statusTone = .neutral
            }
        }
    }
    
    private var canTestConnection: Bool {
        switch config.deploymentKind {
        case .local:
            return !config.localBinaryPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .remoteServer:
            return !config.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .container:
            return !config.container.containerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
                Text(statusMessage ?? "当前连接状态会在这里反馈。")
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

    private var statusTitle: String {
        switch statusTone {
        case .success: return "连接已确认"
        case .error: return "连接未就绪"
        case .neutral: return "等待确认"
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
                ? "识别完成。请确认结果后再手动连接。"
                : "识别未通过。请调整配置后重新识别。"
            statusTone = success ? .success : .error
        }
    }
    
    private func saveConfig() {
        isSaving = true
        appState.openClawManager.config = config
        config.save()
        isSaving = false
        statusMessage = "配置已保存。识别后点击手动连接即可进入会话。"
        statusTone = .neutral
    }

    private func connectNow() {
        isSaving = true
        appState.connectOpenClaw(using: config) { success, message in
            isSaving = false
            testResult = message
            statusMessage = success ? "连接已确认，OpenClaw 文件已经进入会话同步。" : "连接失败：\(message)"
            statusTone = success ? .success : .error
        }
    }

    private func refreshStatusFromManager() {
        switch appState.openClawManager.status {
        case .connected:
            statusMessage = "当前配置已连接到 OpenClaw，会话文件已同步。"
            statusTone = .success
        case .connecting:
            statusMessage = "正在处理 OpenClaw 会话。"
            statusTone = .neutral
        case .disconnected:
            statusMessage = "当前尚未确认连接。可先自动识别，再手动连接。"
            statusTone = .neutral
        case .error(let message):
            statusMessage = message
            statusTone = .error
        }
    }

    private func configFingerprint(_ config: OpenClawConfig) -> String {
        [
            config.deploymentKind.rawValue,
            config.host,
            "\(config.port)",
            config.useSSL ? "ssl" : "plain",
            config.apiKey,
            "\(config.timeout)",
            config.localBinaryPath,
            config.container.engine,
            config.container.containerName,
            config.container.workspaceMountPath
        ].joined(separator: "|")
    }

    @ViewBuilder
    private var detectedAgentsSection: some View {
        let detectedAgents = appState.openClawManager.discoveryResults

        if !detectedAgents.isEmpty {
            GroupBox("识别结果") {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(detectedAgents) { agent in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: agent.directoryValidated && agent.configValidated ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                                .foregroundColor(agent.directoryValidated && agent.configValidated ? .green : .orange)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(agent.name)
                                    .font(.headline)
                                Text(agent.issues.isEmpty ? "目录与 openclaw.json 都已校验。" : agent.issues.joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                if let path = agent.copiedToProjectPath {
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
                        Button("导入这些 Agents") {
                            isPresentingImportSheet = true
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!appState.openClawManager.isConnected || detectedAgents.isEmpty)
                    }
                }
            }
        }
    }
}

struct OpenClawAgentManagementView: View {
    @EnvironmentObject var appState: AppState
    @State private var managedAgents: [OpenClawManager.ManagedAgentRecord] = []
    @State private var availableModels: [String] = []
    @State private var selectedManagedAgentID: String?
    @State private var managedAgentModelDraft: String = ""
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
        appState.openClawManager.isConnected && config.deploymentKind != .remoteServer
    }

    private var selectedManagedAgent: OpenClawManager.ManagedAgentRecord? {
        guard let selectedManagedAgentID else { return nil }
        return managedAgents.first(where: { $0.id == selectedManagedAgentID })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("OpenClaw Agent 管理")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("管理单个 OpenClaw agent 的 model 与 skills，并支持从 ClawHub 搜索后直接安装。")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                GroupBox("Agent 配置") {
                    VStack(alignment: .leading, spacing: 12) {
                        if !appState.openClawManager.isConnected {
                            Text("请先在 OpenClaw Connection 页面完成连接。")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else if config.deploymentKind == .remoteServer {
                            Text("远程网关模式不提供本地 agent 文件与 workspace 直接编辑。")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            HStack(alignment: .center, spacing: 12) {
                                labeledField("Target Agent") {
                                    Picker("Target Agent", selection: Binding<String?>(
                                        get: { selectedManagedAgentID },
                                        set: { newValue in
                                            selectedManagedAgentID = newValue
                                            syncManagedAgentDrafts()
                                        }
                                    )) {
                                        Text("请选择 Agent").tag(nil as String?)
                                        ForEach(managedAgents) { agent in
                                            Text("\(agent.name) (\(agent.id))").tag(Optional(agent.id))
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
                                        Text(isRefreshingManagedAgents ? "刷新中..." : "刷新列表")
                                    }
                                }
                                .disabled(isRefreshingManagedAgents)
                            }

                            if let selectedManagedAgent {
                                Divider()

                                VStack(alignment: .leading, spacing: 10) {
                                    infoRow(label: "Agent ID", value: selectedManagedAgent.id)
                                    infoRow(label: "配置索引", value: "\(selectedManagedAgent.configIndex)")
                                    infoRow(label: "Workspace", value: selectedManagedAgent.workspacePath ?? "未配置")
                                    infoRow(label: "Agent Dir", value: selectedManagedAgent.agentDirPath ?? "未配置")
                                    infoRow(label: "当前 Model", value: selectedManagedAgent.modelIdentifier.isEmpty ? "未设置" : selectedManagedAgent.modelIdentifier)

                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Model 切换")
                                            .font(.caption)
                                            .foregroundColor(.secondary)

                                        HStack(spacing: 10) {
                                            TextField("provider/model", text: $managedAgentModelDraft)
                                                .textFieldStyle(.roundedBorder)

                                            Menu("模型候选") {
                                                if availableModels.isEmpty {
                                                    Text("暂无可用模型")
                                                } else {
                                                    ForEach(availableModels, id: \.self) { model in
                                                        Button(model) {
                                                            managedAgentModelDraft = model
                                                        }
                                                    }
                                                }
                                            }

                                            Button {
                                                applyManagedAgentModel()
                                            } label: {
                                                HStack(spacing: 8) {
                                                    if isMutatingManagedAgent {
                                                        ProgressView()
                                                            .controlSize(.small)
                                                    }
                                                    Text(isMutatingManagedAgent ? "应用中..." : "应用模型")
                                                }
                                            }
                                            .buttonStyle(.borderedProminent)
                                            .disabled(isMutatingManagedAgent || managedAgentModelDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                        }
                                    }

                                    Divider()

                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("技能安装")
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
                                                    Text("按 slug 安装")
                                                }
                                            }
                                            .buttonStyle(.borderedProminent)
                                            .disabled(isMutatingManagedAgent || managedSkillSlug.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                        }

                                        HStack(spacing: 10) {
                                            TextField("从 ClawHub 搜索技能", text: $searchKeyword)
                                                .textFieldStyle(.roundedBorder)
                                            Button {
                                                searchSkillsFromClawHub()
                                            } label: {
                                                HStack(spacing: 8) {
                                                    if isSearchingSkills {
                                                        ProgressView()
                                                            .controlSize(.small)
                                                    }
                                                    Text(isSearchingSkills ? "搜索中..." : "搜索并安装")
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
                                                        Button("安装") {
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
                                            Text("暂无已安装技能。")
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
                                                        Text("移除")
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
                                Text("请选择一个 agent 查看详细配置。")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                Text("当前没有可用的 OpenClaw agent 配置。")
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

    private func refreshManagedAgentDataIfNeeded() {
        guard canManageOpenClawAgents else {
            managedAgents = []
            availableModels = []
            selectedManagedAgentID = nil
            managedAgentModelDraft = ""
            managedSkillSlug = ""
            searchResults = []
            managedAgentMessage = nil
            return
        }

        isRefreshingManagedAgents = true

        appState.openClawManager.loadManagedAgents(using: config) { success, message, records in
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
                managedAgentModelDraft = ""
                managedSkillSlug = ""
                searchResults = []
                managedAgentMessage = message
                managedAgentTone = .error
            }
        }

        appState.openClawManager.loadAvailableModels(using: config) { success, _, models in
            availableModels = success ? models : []
        }
    }

    private func syncManagedAgentDrafts() {
        guard let selectedManagedAgent else {
            managedAgentModelDraft = ""
            managedSkillSlug = ""
            searchResults = []
            return
        }

        managedAgentModelDraft = selectedManagedAgent.modelIdentifier
        managedSkillSlug = ""
    }

    private func applyManagedAgentModel() {
        guard let selectedManagedAgent else { return }

        isMutatingManagedAgent = true
        appState.openClawManager.updateManagedAgentModel(selectedManagedAgent, model: managedAgentModelDraft, using: config) { success, message in
            isMutatingManagedAgent = false
            managedAgentMessage = message
            managedAgentTone = success ? .success : .error
            if success {
                refreshManagedAgentDataIfNeeded()
            }
        }
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
