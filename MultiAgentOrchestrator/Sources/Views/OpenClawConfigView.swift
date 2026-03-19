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
                        Button("添加这些 Agents") {
                            _ = appState.importDetectedOpenClawAgents()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!appState.openClawManager.isConnected || detectedAgents.isEmpty)
                    }
                }
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
}
