//
//  OpenClawConfigView.swift
//  Multi-Agent-Flow
//

import SwiftUI

struct OpenClawConfigView: View {
    @EnvironmentObject var appState: AppState
    @State private var config: OpenClawConfig = .default
    @State private var isTesting = false
    @State private var isSaving = false
    @State private var isSyncingSession = false
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
            config = appState.openClawManager.config
            refreshStatusFromManager()
        }
        .onChange(of: configFingerprint(config)) { _, newFingerprint in
            if let lastTestedFingerprint, lastTestedFingerprint != newFingerprint {
                lastTestSucceeded = false
                statusMessage = LocalizedString.text("config_modified_retest")
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

    private var sessionLifecycleHint: String {
        appState.openClawAttachmentStatusDetail
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
            }

            Text(sessionLifecycleHint)
                .font(.footnote)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

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
        appState.openClawManager.config = config
        config.save()
        isSaving = false
        statusMessage = LocalizedString.text("config_saved_connect_next")
        statusTone = .neutral
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
        switch appState.openClawManager.status {
        case .connected:
            statusMessage = sessionLifecycleHint
            statusTone = .success
        case .connecting:
            statusMessage = LocalizedString.text("processing_openclaw_session")
            statusTone = .neutral
        case .disconnected:
            statusMessage = LocalizedString.text("current_not_confirmed")
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
                                        Text(LocalizedString.text("model_switch"))
                                            .font(.caption)
                                            .foregroundColor(.secondary)

                                        HStack(spacing: 10) {
                                            TextField("provider/model", text: $managedAgentModelDraft)
                                                .textFieldStyle(.roundedBorder)

                                            Menu(LocalizedString.text("model_candidates")) {
                                                if availableModels.isEmpty {
                                                    Text(LocalizedString.text("no_models_available"))
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
                                                    Text(isMutatingManagedAgent ? LocalizedString.text("applying") : LocalizedString.text("apply_model"))
                                                }
                                            }
                                            .buttonStyle(.borderedProminent)
                                            .disabled(isMutatingManagedAgent || managedAgentModelDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                        }
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
            availableModels = []
            selectedManagedAgentID = nil
            managedAgentModelDraft = ""
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

        let trimmedModel = managedAgentModelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModel.isEmpty else { return }

        guard let projectAgentID = selectedManagedAgent.projectAgentID else {
            managedAgentMessage = "未定位到对应的项目 Agent。"
            managedAgentTone = .error
            return
        }

        if selectedManagedAgent.configIndex == nil {
            appState.updateAgentOpenClawDefinition(for: projectAgentID) { definition in
                definition.modelIdentifier = trimmedModel
            }
            managedAgentMessage = "\(selectedManagedAgent.name) 的项目 model 已更新为 \(trimmedModel)，但当前未匹配到可写回的 OpenClaw 运行时配置。"
            managedAgentTone = .success
            refreshManagedAgentDataIfNeeded()
            return
        }

        isMutatingManagedAgent = true
        appState.openClawManager.updateManagedAgentModel(selectedManagedAgent, model: trimmedModel, using: config) { success, message in
            isMutatingManagedAgent = false
            if success {
                appState.updateAgentOpenClawDefinition(for: projectAgentID) { definition in
                    definition.modelIdentifier = trimmedModel
                }
            }
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
