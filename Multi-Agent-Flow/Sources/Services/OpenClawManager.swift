//
//  OpenClawManager.swift
//  Multi-Agent-Flow
//

import Foundation
import Combine

class OpenClawManager: ObservableObject {
    static let shared = OpenClawManager()
    private let fileManager = FileManager.default
    private let gatewayClient = OpenClawGatewayClient()
    
    @Published var isConnected: Bool = false
    @Published var agents: [String] = []
    @Published var discoveryResults: [ProjectOpenClawDetectedAgentRecord] = []
    @Published var activeAgents: [UUID: ActiveAgentRuntime] = [:]
    @Published var status: OpenClawStatus = .disconnected
    @Published var config: OpenClawConfig = .load()
    private var cachedLocalWorkspaceMap: [String: String] = [:]
    private var cachedLocalWorkspaceConfigModificationDate: Date?
    private var cachedLocalGatewayConfig: OpenClawConfig?
    private var cachedLocalGatewayConfigModificationDate: Date?
    
    var backupDirectory: URL {
        let openclawPath = NSHomeDirectory() + "/.openclaw"
        return URL(fileURLWithPath: openclawPath).appendingPathComponent("backups", isDirectory: true)
    }
    
    enum OpenClawStatus {
        case disconnected
        case connecting
        case connected
        case error(String)
    }

    struct ActiveAgentRuntime: Codable, Hashable {
        var agentID: UUID
        var name: String
        var status: String
        var lastReloadedAt: Date?
    }

    struct AgentRuntimeCommandResult {
        let terminationStatus: Int32
        let standardOutput: Data
        let standardError: Data
        let channelKey: String
        let executionCount: Int
        let createdAt: Date
        let lastUsedAt: Date

        var reusedExistingChannel: Bool {
            executionCount > 1
        }
    }

    struct ManagedAgentSkillRecord: Identifiable, Hashable {
        var id: String { name }
        var name: String
        var path: String
    }

    struct ManagedAgentRecord: Identifiable, Hashable {
        var id: String
        var projectAgentID: UUID?
        var configIndex: Int?
        var name: String
        var targetIdentifier: String
        var agentDirPath: String?
        var workspacePath: String?
        var modelIdentifier: String
        var installedSkills: [ManagedAgentSkillRecord]

        init(
            id: String,
            projectAgentID: UUID? = nil,
            configIndex: Int? = nil,
            name: String,
            targetIdentifier: String,
            agentDirPath: String? = nil,
            workspacePath: String? = nil,
            modelIdentifier: String = "",
            installedSkills: [ManagedAgentSkillRecord] = []
        ) {
            self.id = id
            self.projectAgentID = projectAgentID
            self.configIndex = configIndex
            self.name = name
            self.targetIdentifier = targetIdentifier
            self.agentDirPath = agentDirPath
            self.workspacePath = workspacePath
            self.modelIdentifier = modelIdentifier
            self.installedSkills = installedSkills
        }
    }

    struct ClawHubSkillRecord: Identifiable, Hashable {
        var id: String { slug }
        var slug: String
        var summary: String
    }

    private struct SessionContext {
        let projectID: UUID
        let rootURL: URL
        let backupURL: URL
        let mirrorURL: URL
        let importedAgentsURL: URL
    }

    private struct MirrorStageResult {
        var updatedAgentCount: Int = 0
        var unresolvedAgentNames: [String] = []
    }

    private final class AgentRuntimeChannel {
        private enum CommandLaunchMode {
            case executable(url: URL, baseArguments: [String])
        }

        private let key: String
        private let launchMode: CommandLaunchMode
        private let stateLock = NSLock()
        private var executionCount = 0
        private let createdAt = Date()
        private var lastUsedAt = Date()

        init(key: String, config: OpenClawConfig, resolvedOpenClawPath: String) throws {
            self.key = key

            switch config.deploymentKind {
            case .local:
                launchMode = .executable(
                    url: URL(fileURLWithPath: resolvedOpenClawPath),
                    baseArguments: []
                )
            case .container:
                let containerName = config.container.containerName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !containerName.isEmpty else {
                    throw NSError(
                        domain: "OpenClawManager",
                        code: 301,
                        userInfo: [NSLocalizedDescriptionKey: "容器名称未配置，无法创建 OpenClaw Agent Runtime 通道。"]
                    )
                }

                let engine = config.container.engine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "docker"
                    : config.container.engine.trimmingCharacters(in: .whitespacesAndNewlines)
                launchMode = .executable(
                    url: URL(fileURLWithPath: "/usr/bin/env"),
                    baseArguments: [engine, "exec", containerName, "openclaw"]
                )
            case .remoteServer:
                throw NSError(
                    domain: "OpenClawManager",
                    code: 302,
                    userInfo: [NSLocalizedDescriptionKey: "远程网关模式暂不支持创建本地 OpenClaw Agent Runtime 通道。"]
                )
            }
        }

        func execute(
            arguments: [String],
            standardInput: FileHandle? = nil,
            onStdoutChunk: ((String) -> Void)? = nil
        ) throws -> AgentRuntimeCommandResult {
            let process = Process()

            switch launchMode {
            case .executable(let url, let baseArguments):
                process.executableURL = url
                process.arguments = baseArguments + arguments
            }

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            process.standardInput = standardInput

            let lock = NSLock()
            var stdoutData = Data()
            var stderrData = Data()

            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                lock.lock()
                stdoutData.append(data)
                lock.unlock()
                if let onStdoutChunk {
                    onStdoutChunk(String(decoding: data, as: UTF8.self))
                }
            }

            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                lock.lock()
                stderrData.append(data)
                lock.unlock()
            }

            try process.run()
            process.waitUntilExit()

            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil

            let remainingStdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            if !remainingStdout.isEmpty {
                lock.lock()
                stdoutData.append(remainingStdout)
                lock.unlock()
                if let onStdoutChunk {
                    onStdoutChunk(String(decoding: remainingStdout, as: UTF8.self))
                }
            }

            let remainingStderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            if !remainingStderr.isEmpty {
                lock.lock()
                stderrData.append(remainingStderr)
                lock.unlock()
            }

            let snapshot = markExecutionFinished()
            return AgentRuntimeCommandResult(
                terminationStatus: process.terminationStatus,
                standardOutput: stdoutData,
                standardError: stderrData,
                channelKey: key,
                executionCount: snapshot.executionCount,
                createdAt: snapshot.createdAt,
                lastUsedAt: snapshot.lastUsedAt
            )
        }

        private func markExecutionFinished() -> (executionCount: Int, createdAt: Date, lastUsedAt: Date) {
            stateLock.lock()
            executionCount += 1
            lastUsedAt = Date()
            let snapshot = (executionCount: executionCount, createdAt: createdAt, lastUsedAt: lastUsedAt)
            stateLock.unlock()
            return snapshot
        }
    }

    private var sessionContext: SessionContext?
    private var discoverySnapshotURL: URL?
    private var pluginStageCleanupPerformed = false
    private let pluginStageCleanupLock = NSLock()
    private var agentRuntimeChannels: [String: AgentRuntimeChannel] = [:]
    private let agentRuntimeChannelLock = NSLock()

    private static let possiblePaths = [
        "/Users/chenrongze/.local/bin/openclaw",
        "/usr/local/bin/openclaw",
        "/opt/homebrew/bin/openclaw",
        "/usr/bin/openclaw"
    ]
    
    private init() {
        // 创建备份目录
        try? FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
    }
    
    // 连接OpenClaw - 使用配置
    func connect(completion: ((Bool, String) -> Void)? = nil) {
        connect(for: nil, completion: completion)
    }

    func connect(for projectID: UUID? = nil, completion: ((Bool, String) -> Void)? = nil) {
        connect(for: projectID, project: nil, completion: completion)
    }

    func connect(for project: MAProject, completion: ((Bool, String) -> Void)? = nil) {
        connect(for: project.id, project: project, completion: completion)
    }

    private func connect(
        for projectID: UUID? = nil,
        project: MAProject? = nil,
        completion: ((Bool, String) -> Void)? = nil
    ) {
        status = .connecting
        config.save()

        let cleanupResult = cleanupStalePluginInstallStageArtifactsIfNeeded(using: config)
        let cleanupNote: String? = cleanupResult.success ? nil : cleanupResult.message
        var stageNote: String?

        if let projectID, config.deploymentKind != .remoteServer {
            do {
                try beginSession(for: projectID)
                if let project {
                    let stageResult = stageProjectAgentsIntoMirror(project)
                    try applySessionMirrorToDeployment()
                    stageNote = mirrorStageMessage(from: stageResult)
                }
            } catch {
                endSession(restoreOriginalState: true)
                status = .error(error.localizedDescription)
                completion?(false, error.localizedDescription)
                return
            }
        }

        confirmConnection(using: config) { [weak self] success, message in
            guard let self else { return }
            if !success, projectID != nil {
                self.endSession(restoreOriginalState: true)
            }
            var extraNotes: [String] = []
            if let stageNote, !stageNote.isEmpty {
                extraNotes.append(stageNote)
            }
            if let cleanupNote, !cleanupNote.isEmpty {
                extraNotes.append(cleanupNote)
            }

            let finalMessage: String
            if extraNotes.isEmpty {
                finalMessage = message
            } else {
                finalMessage = "\(message)（附加信息：\(extraNotes.joined(separator: "；"))）"
            }
            completion?(success, finalMessage)
        }
    }

    func cleanupStalePluginInstallStageArtifactsIfNeeded(
        using config: OpenClawConfig? = nil
    ) -> (success: Bool, message: String) {
        let resolvedConfig = config ?? self.config

        pluginStageCleanupLock.lock()
        let alreadyCleaned = pluginStageCleanupPerformed
        pluginStageCleanupLock.unlock()
        if alreadyCleaned {
            return (true, "")
        }

        switch resolvedConfig.deploymentKind {
        case .remoteServer:
            return (true, "")
        case .local:
            do {
                let extensionsDirectory = localOpenClawRootURL().appendingPathComponent("extensions", isDirectory: true)
                guard FileManager.default.fileExists(atPath: extensionsDirectory.path) else {
                    pluginStageCleanupLock.lock()
                    pluginStageCleanupPerformed = true
                    pluginStageCleanupLock.unlock()
                    return (true, "")
                }

                let contents = try FileManager.default.contentsOfDirectory(
                    at: extensionsDirectory,
                    includingPropertiesForKeys: [.isDirectoryKey]
                )
                let stagedDirectories = contents.filter { url in
                    guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return false }
                    return url.lastPathComponent.hasPrefix(".openclaw-install-stage-")
                }

                for directory in stagedDirectories {
                    try? FileManager.default.removeItem(at: directory)
                }

                pluginStageCleanupLock.lock()
                pluginStageCleanupPerformed = true
                pluginStageCleanupLock.unlock()

                if stagedDirectories.isEmpty {
                    return (true, "")
                }
                return (true, "已清理 \(stagedDirectories.count) 个 OpenClaw 插件安装残留目录。")
            } catch {
                return (false, "清理 OpenClaw 插件安装残留目录失败：\(error.localizedDescription)")
            }
        case .container:
            do {
                guard let containerName = containerName(for: resolvedConfig),
                      let deploymentRootPath = containerOpenClawRootPath(for: resolvedConfig) else {
                    return (false, "容器模式下无法定位 OpenClaw 根目录，未完成插件残留清理。")
                }

                let cleanupCommand = """
                shopt -s nullglob >/dev/null 2>&1 || true
                for d in \(shellQuoted(deploymentRootPath))/extensions/.openclaw-install-stage-*; do
                  [ -e "$d" ] || continue
                  rm -rf "$d"
                done
                """

                let result = try runDeploymentCommand(
                    using: resolvedConfig,
                    arguments: ["exec", containerName, "sh", "-lc", cleanupCommand]
                )

                guard result.terminationStatus == 0 else {
                    let stderr = String(data: result.standardError, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    return (false, stderr.isEmpty ? "容器模式插件残留清理失败。" : stderr)
                }

                pluginStageCleanupLock.lock()
                pluginStageCleanupPerformed = true
                pluginStageCleanupLock.unlock()
                return (true, "已执行容器内 OpenClaw 插件残留清理。")
            } catch {
                return (false, "容器模式插件残留清理失败：\(error.localizedDescription)")
            }
        }
    }

    func refreshAgents(completion: @escaping ([String]) -> Void) {
        testConnection(using: config) { [weak self] success, message, agentNames in
            guard let self else { return }
            DispatchQueue.main.async {
                self.agents = success ? (self.discoveryResults.isEmpty ? agentNames : self.discoveryResults.map(\.name)) : []
                self.isConnected = success
                self.status = success ? .connected : .error(message)
                completion(self.agents)
            }
        }
    }

    func confirmConnection(using config: OpenClawConfig, completion: @escaping (Bool, String) -> Void) {
        status = .connecting
        testConnection(using: config) { [weak self] success, message, agentNames in
            guard let self else { return }
            DispatchQueue.main.async {
                self.config = config
                self.config.save()
                self.agents = success ? (self.discoveryResults.isEmpty ? agentNames : self.discoveryResults.map(\.name)) : []
                self.isConnected = success
                self.status = success ? .connected : .error(message)
                if !success {
                    self.activeAgents.removeAll()
                    self.resetAgentRuntimeChannels()
                    self.resetGatewayConnection()
                }
                completion(success, message)
            }
        }
    }

    func beginSession(for projectID: UUID) throws {
        guard config.deploymentKind != .remoteServer else { return }
        guard sessionContext == nil else { return }

        let projectRoot = ProjectManager.shared.openClawProjectRoot(for: projectID)
        let backupURL = ProjectManager.shared.openClawBackupDirectory(for: projectID)
        let mirrorURL = ProjectManager.shared.openClawMirrorDirectory(for: projectID)
        let importedAgentsURL = ProjectManager.shared.openClawImportedAgentsDirectory(for: projectID)

        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: backupURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: mirrorURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: importedAgentsURL, withIntermediateDirectories: true)

        switch config.deploymentKind {
        case .local:
            let openClawRoot = localOpenClawRootURL()
            _ = try replaceDirectoryContents(of: backupURL, withContentsOf: openClawRoot)
            if directoryHasContent(mirrorURL) {
                _ = try replaceDirectoryContents(of: openClawRoot, withContentsOf: mirrorURL)
            } else {
                _ = try replaceDirectoryContents(of: mirrorURL, withContentsOf: openClawRoot)
            }
        case .container:
            guard let deploymentRootPath = containerOpenClawRootPath(for: config) else {
                throw NSError(domain: "OpenClawManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法解析容器内 OpenClaw 路径"])
            }

            _ = try copyDeploymentContentsToLocal(backupURL, deploymentRootPath: deploymentRootPath, using: config)
            if directoryHasContent(mirrorURL) {
                try copyLocalContentsToDeployment(mirrorURL, deploymentRootPath: deploymentRootPath, using: config)
            } else {
                _ = try copyDeploymentContentsToLocal(mirrorURL, deploymentRootPath: deploymentRootPath, using: config)
            }
        case .remoteServer:
            break
        }

        sessionContext = SessionContext(
            projectID: projectID,
            rootURL: projectRoot,
            backupURL: backupURL,
            mirrorURL: mirrorURL,
            importedAgentsURL: importedAgentsURL
        )
    }

    func endSession(restoreOriginalState: Bool = true) {
        guard let context = sessionContext else { return }

        do {
            try FileManager.default.createDirectory(at: context.mirrorURL, withIntermediateDirectories: true)
            switch config.deploymentKind {
            case .local:
                let openClawRoot = localOpenClawRootURL()
                _ = try replaceDirectoryContents(of: context.mirrorURL, withContentsOf: openClawRoot)

                if restoreOriginalState {
                    _ = try replaceDirectoryContents(of: openClawRoot, withContentsOf: context.backupURL)
                }
            case .container:
                guard let deploymentRootPath = containerOpenClawRootPath(for: config) else {
                    throw NSError(domain: "OpenClawManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "无法解析容器内 OpenClaw 路径"])
                }

                _ = try copyDeploymentContentsToLocal(context.mirrorURL, deploymentRootPath: deploymentRootPath, using: config)

                if restoreOriginalState {
                    try copyLocalContentsToDeployment(context.backupURL, deploymentRootPath: deploymentRootPath, using: config)
                }
            case .remoteServer:
                break
            }
        } catch {
            print("OpenClaw session finalization failed: \(error)")
        }

        sessionContext = nil
    }

    func testConnection(
        using config: OpenClawConfig,
        completion: @escaping (Bool, String, [String]) -> Void
    ) {
        switch config.deploymentKind {
        case .local:
            runLocalConnectionTest(binaryPath: resolveOpenClawPath(for: config), completion: completion)
        case .container:
            runContainerConnectionTest(config: config, completion: completion)
        case .remoteServer:
            runRemoteConnectionTest(config: config, completion: completion)
        }
    }
    
    // 断开连接
    func disconnect() {
        if sessionContext != nil {
            endSession(restoreOriginalState: true)
        }
        isConnected = false
        agents = []
        activeAgents.removeAll()
        discoveryResults = []
        clearDiscoverySnapshot()
        resetAgentRuntimeChannels()
        resetGatewayConnection()
        status = .disconnected
    }

    func activateAgent(_ agent: Agent) {
        activeAgents[agent.id] = ActiveAgentRuntime(
            agentID: agent.id,
            name: agent.name,
            status: "active",
            lastReloadedAt: nil
        )
    }

    func terminateAgent(_ agentID: UUID) {
        activeAgents.removeValue(forKey: agentID)
    }

    func reloadAgent(_ agent: Agent) {
        var runtime = activeAgents[agent.id] ?? ActiveAgentRuntime(
            agentID: agent.id,
            name: agent.name,
            status: "active",
            lastReloadedAt: nil
        )
        runtime.name = agent.name
        runtime.status = "reloading"
        runtime.lastReloadedAt = Date()
        activeAgents[agent.id] = runtime

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            var updated = runtime
            updated.status = "active"
            self.activeAgents[agent.id] = updated
        }
    }

    func snapshot() -> ProjectOpenClawSnapshot {
        ProjectOpenClawSnapshot(
            config: config,
            isConnected: isConnected,
            availableAgents: agents,
            activeAgents: activeAgents.values
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                .map {
                    ProjectOpenClawAgentRecord(
                        id: $0.agentID,
                        name: $0.name,
                        status: $0.status,
                        lastReloadedAt: $0.lastReloadedAt
                    )
                },
            detectedAgents: discoveryResults,
            sessionBackupPath: sessionContext?.backupURL.path,
            sessionMirrorPath: sessionContext?.mirrorURL.path,
            lastSyncedAt: Date()
        )
    }

    func restore(from snapshot: ProjectOpenClawSnapshot) {
        config = snapshot.config
        config.save()
        agents = snapshot.availableAgents
        discoveryResults = snapshot.detectedAgents
        activeAgents = Dictionary(uniqueKeysWithValues: snapshot.activeAgents.map {
            (
                $0.id,
                ActiveAgentRuntime(
                    agentID: $0.id,
                    name: $0.name,
                    status: $0.status,
                    lastReloadedAt: $0.lastReloadedAt
                )
            )
        })
        isConnected = false
        status = .disconnected
    }

    @discardableResult
    func importDetectedAgents(into project: inout MAProject, selectedRecordIDs: Set<String>? = nil) -> [ProjectOpenClawDetectedAgentRecord] {
        let importRoot = ProjectManager.shared.openClawImportedAgentsDirectory(for: project.id)
        try? FileManager.default.createDirectory(at: importRoot, withIntermediateDirectories: true)

        var importedRecords: [ProjectOpenClawDetectedAgentRecord] = []
        let selectedRecords = discoveryResults.filter { record in
            guard let selectedRecordIDs else { return true }
            return selectedRecordIDs.contains(record.id)
        }

        for record in selectedRecords {
            guard record.directoryValidated,
                  let sourceDirectoryPath = record.directoryPath else {
                continue
            }

            let sourceDirectory = URL(fileURLWithPath: sourceDirectoryPath, isDirectory: true)
            guard FileManager.default.fileExists(atPath: sourceDirectory.path) else { continue }

            if project.agents.contains(where: { $0.name == record.name }) {
                continue
            }

            let agentRoot = importRoot.appendingPathComponent(safePathComponent(record.id), isDirectory: true)
            let privateRoot = agentRoot.appendingPathComponent("private", isDirectory: true)
            let workspaceRoot = agentRoot.appendingPathComponent("workspace", isDirectory: true)
            let stateRoot = agentRoot.appendingPathComponent("state", isDirectory: true)
            try? FileManager.default.createDirectory(at: agentRoot, withIntermediateDirectories: true)
            try? FileManager.default.createDirectory(at: privateRoot, withIntermediateDirectories: true)
            try? FileManager.default.createDirectory(at: workspaceRoot, withIntermediateDirectories: true)
            try? FileManager.default.createDirectory(at: stateRoot, withIntermediateDirectories: true)

            var copiedItemCount = 0
            copiedItemCount += (try? replaceDirectoryContents(of: privateRoot, withContentsOf: sourceDirectory)) ?? 0

            if let workspacePath = record.workspacePath {
                let workspaceURL = URL(fileURLWithPath: workspacePath, isDirectory: true)
                if FileManager.default.fileExists(atPath: workspaceURL.path) {
                    copiedItemCount += (try? replaceDirectoryContents(of: workspaceRoot, withContentsOf: workspaceURL)) ?? 0
                }
            }

            if let statePath = record.statePath {
                let stateURL = URL(fileURLWithPath: statePath, isDirectory: true)
                if FileManager.default.fileExists(atPath: stateURL.path) {
                    copiedItemCount += (try? replaceDirectoryContents(of: stateRoot, withContentsOf: stateURL)) ?? 0
                }
            }

            let soulPath = sourceDirectory.appendingPathComponent("SOUL.md")
            let fallbackSoulPath = sourceDirectory.appendingPathComponent("soul.md")
            var soulText = "# \(record.name)\n"
            if let content = try? String(contentsOf: soulPath, encoding: .utf8) {
                soulText = content
            } else if let content = try? String(contentsOf: fallbackSoulPath, encoding: .utf8) {
                soulText = content
            }

            let skillsDirectory = sourceDirectory.appendingPathComponent("skills", isDirectory: true)
            var capabilities: [String] = ["basic"]
            if let skillContents = try? FileManager.default.contentsOfDirectory(at: skillsDirectory, includingPropertiesForKeys: nil) {
                capabilities = skillContents
                    .filter { ["md", "MD"].contains($0.pathExtension) }
                    .map { $0.deletingPathExtension().lastPathComponent }
                if capabilities.isEmpty {
                    capabilities = ["basic"]
                }
            }

            var agent = Agent(name: record.name)
            agent.description = "Imported from OpenClaw"
            agent.soulMD = soulText
            agent.capabilities = capabilities
            agent.openClawDefinition.agentIdentifier = record.name
            agent.openClawDefinition.memoryBackupPath = privateRoot.path
            agent.openClawDefinition.soulSourcePath = preferredSoulURL(in: sourceDirectory).path
            agent.openClawDefinition.runtimeProfile = "imported"
            agent.updatedAt = Date()
            project.agents.append(agent)

            var updatedRecord = record
            updatedRecord.copiedToProjectPath = agentRoot.path
            updatedRecord.copiedFileCount = copiedItemCount
            updatedRecord.importedAt = Date()
            importedRecords.append(updatedRecord)
        }

        if !importedRecords.isEmpty {
            discoveryResults = mergeImportedRecords(importedRecords)
        }

        return importedRecords
    }

    func loadManagedAgents(
        for project: MAProject?,
        using config: OpenClawConfig? = nil,
        completion: @escaping (Bool, String, [ManagedAgentRecord]) -> Void
    ) {
        let resolvedConfig = config ?? self.config

        guard let project else {
            completion(false, "请先创建或打开项目，再管理 target agents。", [])
            return
        }

        guard resolvedConfig.deploymentKind != .remoteServer else {
            completion(false, "远程网关模式下暂不支持直接修改 OpenClaw agent 配置。", [])
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            var runtimeRecords: [ManagedAgentRecord] = []
            var runtimeWarning: String?

            do {
                let result = try self.runOpenClawCommand(using: resolvedConfig, arguments: ["agents", "list", "--json"])
                if result.terminationStatus == 0 {
                    runtimeRecords = self.parseManagedAgents(from: result.standardOutput, using: resolvedConfig)
                } else {
                    let fallback = String(data: result.standardError, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    runtimeWarning = fallback.isEmpty ? "读取 OpenClaw agents 失败" : fallback
                }
            } catch {
                runtimeWarning = error.localizedDescription
            }

            let records = self.mergeManagedAgents(for: project, runtimeRecords: runtimeRecords, using: resolvedConfig)
            DispatchQueue.main.async {
                if records.isEmpty, let runtimeWarning {
                    completion(false, runtimeWarning, [])
                } else {
                    let message: String
                    if let runtimeWarning, !runtimeWarning.isEmpty {
                        message = "已加载 \(records.count) 个项目 target agents，运行时信息部分不可用：\(runtimeWarning)"
                    } else {
                        message = "已加载 \(records.count) 个项目 target agents。"
                    }
                    completion(true, message, records)
                }
            }
        }
    }

    func loadAvailableModels(
        using config: OpenClawConfig? = nil,
        completion: @escaping (Bool, String, [String]) -> Void
    ) {
        let resolvedConfig = config ?? self.config

        guard resolvedConfig.deploymentKind != .remoteServer else {
            completion(false, "远程网关模式下无法读取本地模型目录。", [])
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let result = try self.runOpenClawCommand(using: resolvedConfig, arguments: ["models", "list", "--plain"])
                guard result.terminationStatus == 0 else {
                    let fallback = String(data: result.standardError, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    throw NSError(
                        domain: "OpenClawManager",
                        code: Int(result.terminationStatus),
                        userInfo: [NSLocalizedDescriptionKey: fallback.isEmpty ? "读取模型列表失败" : fallback]
                    )
                }

                let rawModels = self.parsePlainTextList(from: result.standardOutput)
                var seen = Set<String>()
                let models = rawModels.filter { seen.insert($0).inserted }
                DispatchQueue.main.async {
                    completion(true, "已加载 \(models.count) 个模型。", models)
                }
            } catch {
                DispatchQueue.main.async {
                    completion(false, error.localizedDescription, [])
                }
            }
        }
    }

    func updateManagedAgentModel(
        _ agent: ManagedAgentRecord,
        model: String,
        using config: OpenClawConfig? = nil,
        completion: @escaping (Bool, String) -> Void
    ) {
        let resolvedConfig = config ?? self.config

        guard resolvedConfig.deploymentKind != .remoteServer else {
            completion(false, "远程网关模式下暂不支持修改单个 agent 的 model。")
            return
        }

        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModel.isEmpty else {
            completion(false, "Model 不能为空。")
            return
        }

        guard let configIndex = agent.configIndex else {
            completion(false, "未找到 \(agent.name) 对应的 OpenClaw 运行时配置，无法直接写回。")
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let result = try self.runOpenClawCommand(
                    using: resolvedConfig,
                    arguments: ["config", "set", "agents.list[\(configIndex)].model", trimmedModel]
                )

                guard result.terminationStatus == 0 else {
                    let fallback = String(data: result.standardError, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    throw NSError(
                        domain: "OpenClawManager",
                        code: Int(result.terminationStatus),
                        userInfo: [NSLocalizedDescriptionKey: fallback.isEmpty ? "更新 agent model 失败" : fallback]
                    )
                }

                DispatchQueue.main.async {
                    completion(true, "\(agent.name) 的 model 已更新为 \(trimmedModel)。建议重新连接或重启 OpenClaw 使其完全生效。")
                }
            } catch {
                DispatchQueue.main.async {
                    completion(false, error.localizedDescription)
                }
            }
        }
    }

    func syncAgentCommunicationAllowLists(
        from project: MAProject,
        using config: OpenClawConfig? = nil,
        completion: @escaping (Bool, String) -> Void
    ) {
        let resolvedConfig = config ?? self.config

        guard resolvedConfig.deploymentKind != .remoteServer else {
            completion(false, "远程网关模式下暂不支持同步 agent 通信白名单。")
            return
        }

        let desiredAllowMap = desiredAllowAgentsMap(for: project)
        guard !desiredAllowMap.isEmpty else {
            completion(true, "当前项目未配置可同步的 agent 通信白名单。")
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let getResult = try self.runOpenClawCommand(
                    using: resolvedConfig,
                    arguments: ["config", "get", "agents.list"]
                )
                guard getResult.terminationStatus == 0 else {
                    let fallback = String(data: getResult.standardError, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    throw NSError(
                        domain: "OpenClawManager",
                        code: Int(getResult.terminationStatus),
                        userInfo: [NSLocalizedDescriptionKey: fallback.isEmpty ? "读取 OpenClaw agents.list 失败" : fallback]
                    )
                }

                let payloadData = self.extractJSONPayload(from: getResult.standardOutput) ?? getResult.standardOutput
                guard let jsonObject = try? JSONSerialization.jsonObject(with: payloadData),
                      var runtimeAgents = jsonObject as? [[String: Any]] else {
                    throw NSError(
                        domain: "OpenClawManager",
                        code: 1010,
                        userInfo: [NSLocalizedDescriptionKey: "解析 OpenClaw agents.list 失败"]
                    )
                }

                var changedCount = 0
                for index in runtimeAgents.indices {
                    var entry = runtimeAgents[index]
                    let runtimeID = (entry["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    guard !runtimeID.isEmpty else { continue }

                    let key = self.normalizeAgentKey(runtimeID)
                    guard let desiredAllowAgents = desiredAllowMap[key] else { continue }

                    var subagents = (entry["subagents"] as? [String: Any]) ?? [:]
                    let currentAllow = ((subagents["allowAgents"] as? [String]) ?? [])
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                        .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

                    if currentAllow == desiredAllowAgents {
                        continue
                    }

                    subagents["allowAgents"] = desiredAllowAgents
                    entry["subagents"] = subagents
                    runtimeAgents[index] = entry
                    changedCount += 1
                }

                guard changedCount > 0 else {
                    DispatchQueue.main.async {
                        completion(true, "OpenClaw 通信白名单已与当前项目一致。")
                    }
                    return
                }

                let updatedData = try JSONSerialization.data(withJSONObject: runtimeAgents, options: [])
                guard let updatedJSON = String(data: updatedData, encoding: .utf8) else {
                    throw NSError(
                        domain: "OpenClawManager",
                        code: 1011,
                        userInfo: [NSLocalizedDescriptionKey: "序列化更新后的 agents.list 失败"]
                    )
                }

                let setResult = try self.runOpenClawCommand(
                    using: resolvedConfig,
                    arguments: ["config", "set", "agents.list", updatedJSON]
                )

                guard setResult.terminationStatus == 0 else {
                    let fallback = String(data: setResult.standardError, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    throw NSError(
                        domain: "OpenClawManager",
                        code: Int(setResult.terminationStatus),
                        userInfo: [NSLocalizedDescriptionKey: fallback.isEmpty ? "写回 OpenClaw agents.list 失败" : fallback]
                    )
                }

                DispatchQueue.main.async {
                    completion(true, "已同步 \(changedCount) 个 agent 的通信白名单到 OpenClaw（建议重连 OpenClaw）。")
                }
            } catch {
                DispatchQueue.main.async {
                    completion(false, error.localizedDescription)
                }
            }
        }
    }

    func installSkill(
        _ skillSlug: String,
        for agent: ManagedAgentRecord,
        using config: OpenClawConfig? = nil,
        completion: @escaping (Bool, String) -> Void
    ) {
        let resolvedConfig = config ?? self.config

        guard resolvedConfig.deploymentKind != .remoteServer else {
            completion(false, "远程网关模式下暂不支持通过本应用安装技能。")
            return
        }

        let trimmedSkill = skillSlug.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSkill.isEmpty else {
            completion(false, "请先输入 skill slug。")
            return
        }

        guard let workspacePath = agent.workspacePath?.trimmingCharacters(in: .whitespacesAndNewlines), !workspacePath.isEmpty else {
            completion(false, "\(agent.name) 未配置 workspace，无法安装技能。")
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                if resolvedConfig.deploymentKind == .local {
                    let workspaceURL = URL(fileURLWithPath: workspacePath, isDirectory: true)
                    try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
                }

                let result = try self.runClawHubCommand(
                    using: resolvedConfig,
                    arguments: ["install", trimmedSkill, "--workdir", workspacePath]
                )

                guard result.terminationStatus == 0 else {
                    let fallback = String(data: result.standardError, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    throw NSError(
                        domain: "OpenClawManager",
                        code: Int(result.terminationStatus),
                        userInfo: [NSLocalizedDescriptionKey: fallback.isEmpty ? "安装技能失败" : fallback]
                    )
                }

                DispatchQueue.main.async {
                    completion(true, "\(trimmedSkill) 已安装到 \(agent.name) 的 workspace。")
                }
            } catch {
                DispatchQueue.main.async {
                    completion(false, error.localizedDescription)
                }
            }
        }
    }

    func searchClawHubSkills(
        query: String,
        using config: OpenClawConfig? = nil,
        completion: @escaping (Bool, String, [ClawHubSkillRecord]) -> Void
    ) {
        let resolvedConfig = config ?? self.config
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedQuery.isEmpty else {
            completion(true, "请输入关键词后再搜索。", [])
            return
        }

        guard resolvedConfig.deploymentKind != .remoteServer else {
            completion(false, "远程网关模式下暂不支持 ClawHub 搜索。", [])
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let searchResult = try self.runClawHubCommand(
                    using: resolvedConfig,
                    arguments: ["search", trimmedQuery, "--plain"]
                )

                if searchResult.terminationStatus == 0 {
                    let parsed = self.parseClawHubSkillRecords(from: searchResult.standardOutput)
                    let filtered = self.filterSkillRecords(parsed, with: trimmedQuery)
                    DispatchQueue.main.async {
                        completion(true, "搜索到 \(filtered.count) 条技能结果。", filtered)
                    }
                    return
                }

                let listResult = try self.runClawHubCommand(using: resolvedConfig, arguments: ["list", "--plain"])
                guard listResult.terminationStatus == 0 else {
                    let fallback = String(data: searchResult.standardError, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    throw NSError(
                        domain: "OpenClawManager",
                        code: Int(searchResult.terminationStatus),
                        userInfo: [NSLocalizedDescriptionKey: fallback.isEmpty ? "ClawHub 搜索失败" : fallback]
                    )
                }

                let parsed = self.parseClawHubSkillRecords(from: listResult.standardOutput)
                let filtered = self.filterSkillRecords(parsed, with: trimmedQuery)
                DispatchQueue.main.async {
                    completion(true, "搜索到 \(filtered.count) 条技能结果。", filtered)
                }
            } catch {
                DispatchQueue.main.async {
                    completion(false, error.localizedDescription, [])
                }
            }
        }
    }

    func removeSkill(
        _ skillName: String,
        from agent: ManagedAgentRecord,
        using config: OpenClawConfig? = nil,
        completion: @escaping (Bool, String) -> Void
    ) {
        let resolvedConfig = config ?? self.config

        guard resolvedConfig.deploymentKind != .remoteServer else {
            completion(false, "远程网关模式下暂不支持移除技能。")
            return
        }

        let trimmedSkill = skillName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSkill.isEmpty else {
            completion(false, "技能名称不能为空。")
            return
        }

        guard let workspacePath = agent.workspacePath?.trimmingCharacters(in: .whitespacesAndNewlines), !workspacePath.isEmpty else {
            completion(false, "\(agent.name) 未配置 workspace，无法移除技能。")
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let skillsPath = URL(fileURLWithPath: workspacePath, isDirectory: true)
                    .appendingPathComponent("skills", isDirectory: true)
                    .appendingPathComponent(trimmedSkill, isDirectory: true)

                switch resolvedConfig.deploymentKind {
                case .local:
                    if FileManager.default.fileExists(atPath: skillsPath.path) {
                        try FileManager.default.removeItem(at: skillsPath)
                    }
                case .container:
                    guard let containerName = self.containerName(for: resolvedConfig) else {
                        throw NSError(domain: "OpenClawManager", code: 20, userInfo: [NSLocalizedDescriptionKey: "容器名称未配置"])
                    }
                    let result = try self.runDeploymentCommand(
                        using: resolvedConfig,
                        arguments: ["exec", containerName, "rm", "-rf", skillsPath.path]
                    )
                    guard result.terminationStatus == 0 else {
                        let fallback = String(data: result.standardError, encoding: .utf8)?
                            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        throw NSError(
                            domain: "OpenClawManager",
                            code: Int(result.terminationStatus),
                            userInfo: [NSLocalizedDescriptionKey: fallback.isEmpty ? "移除技能失败" : fallback]
                        )
                    }
                case .remoteServer:
                    break
                }

                DispatchQueue.main.async {
                    completion(true, "\(trimmedSkill) 已从 \(agent.name) 的 workspace 移除。")
                }
            } catch {
                DispatchQueue.main.async {
                    completion(false, error.localizedDescription)
                }
            }
        }
    }

    func updateAgentSoulMD(
        matching candidateNames: [String],
        soulMD: String,
        completion: @escaping (Bool, String) -> Void
    ) {
        let normalizedNames = Set(candidateNames.map(normalizeAgentKey).filter { !$0.isEmpty })
        guard !normalizedNames.isEmpty else {
            completion(false, "未提供可定位的 OpenClaw agent 标识。")
            return
        }

        guard let soulURL = localAgentSoulURL(matching: candidateNames) else {
            completion(false, "未找到对应的 OpenClaw SOUL.md，仅更新了项目缓存。")
            return
        }

        do {
            try FileManager.default.createDirectory(at: soulURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try soulMD.write(to: soulURL, atomically: true, encoding: .utf8)
            completion(true, "SOUL.md 已同步到 OpenClaw: \(soulURL.path)")
        } catch {
            completion(false, "同步 SOUL.md 失败: \(error.localizedDescription)")
        }
    }

    func projectMirrorSoulURL(for agent: Agent, in project: MAProject) -> URL? {
        let mirrorURL: URL
        let backupURL: URL?

        if let sessionContext, sessionContext.projectID == project.id {
            mirrorURL = sessionContext.mirrorURL
            backupURL = sessionContext.backupURL
        } else {
            mirrorURL = ProjectManager.shared.openClawMirrorDirectory(for: project.id)
            backupURL = firstNonEmptyPath(project.openClaw.sessionBackupPath).map {
                URL(fileURLWithPath: $0, isDirectory: true)
            }
        }

        return resolveProjectMirrorSoulURL(for: agent, in: project, mirrorURL: mirrorURL, backupURL: backupURL)
    }

    func syncProjectAgentsToActiveSession(_ project: MAProject, completion: @escaping (Bool, String) -> Void) {
        guard config.deploymentKind != .remoteServer else {
            completion(false, "远程网关模式下暂不支持将项目镜像写回 OpenClaw 会话。")
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let stageResult = self.stageProjectAgentsIntoMirror(project)

            guard let sessionContext = self.sessionContext,
                  sessionContext.projectID == project.id,
                  self.isConnected else {
                let note = self.mirrorStageMessage(from: stageResult) ?? "项目镜像已更新，待下次连接时应用。"
                DispatchQueue.main.async {
                    completion(true, note)
                }
                return
            }

            do {
                try self.applySessionMirrorToDeployment()
                let message = self.mirrorStageMessage(from: stageResult)
                    ?? "项目镜像已同步到当前 OpenClaw 会话。"
                DispatchQueue.main.async {
                    completion(true, message)
                }
            } catch {
                DispatchQueue.main.async {
                    completion(false, "同步项目镜像到 OpenClaw 会话失败: \(error.localizedDescription)")
                }
            }
        }
    }

    func executeOpenClawCLI(
        arguments: [String],
        using config: OpenClawConfig? = nil,
        standardInput: FileHandle? = nil
    ) throws -> (terminationStatus: Int32, standardOutput: Data, standardError: Data) {
        try runOpenClawCommand(using: config ?? self.config, arguments: arguments, standardInput: standardInput)
    }

    func executeAgentRuntimeCommand(
        arguments: [String],
        using config: OpenClawConfig? = nil,
        standardInput: FileHandle? = nil,
        onStdoutChunk: ((String) -> Void)? = nil
    ) throws -> AgentRuntimeCommandResult {
        let resolvedConfig = config ?? self.config
        let channel = try agentRuntimeChannel(for: resolvedConfig)
        return try channel.execute(
            arguments: arguments,
            standardInput: standardInput,
            onStdoutChunk: onStdoutChunk
        )
    }

    func resetAgentRuntimeChannels() {
        agentRuntimeChannelLock.lock()
        agentRuntimeChannels.removeAll()
        agentRuntimeChannelLock.unlock()
    }

    func resetGatewayConnection() {
        _Concurrency.Task {
            await gatewayClient.disconnect()
        }
    }

    func preferredGatewayConfig(using config: OpenClawConfig? = nil) -> OpenClawConfig? {
        let resolvedConfig = config ?? self.config

        switch resolvedConfig.deploymentKind {
        case .remoteServer:
            let host = resolvedConfig.host.trimmingCharacters(in: .whitespacesAndNewlines)
            return host.isEmpty ? nil : resolvedConfig
        case .local:
            return localLoopbackGatewayConfig(using: resolvedConfig)
        case .container:
            return nil
        }
    }

    func executeGatewayAgentCommand(
        message: String,
        agentIdentifier: String,
        sessionKey: String?,
        thinkingLevel: AgentThinkingLevel?,
        timeoutSeconds: Int,
        using config: OpenClawConfig? = nil,
        onAssistantTextUpdated: @escaping @Sendable (String) -> Void
    ) async throws -> OpenClawGatewayClient.AgentExecutionResult {
        try await gatewayClient.executeAgent(
            using: config ?? self.config,
            message: message,
            agentIdentifier: agentIdentifier,
            sessionKey: sessionKey,
            thinkingLevel: thinkingLevel,
            timeoutSeconds: timeoutSeconds,
            onAssistantTextUpdated: onAssistantTextUpdated
        )
    }

    func executeGatewayChatCommand(
        message: String,
        sessionKey: String,
        thinkingLevel: AgentThinkingLevel?,
        timeoutSeconds: Int,
        using config: OpenClawConfig? = nil,
        onRunStarted: (@Sendable (String, String) -> Void)? = nil,
        onAssistantTextUpdated: @escaping @Sendable (String) -> Void
    ) async throws -> OpenClawGatewayClient.AgentExecutionResult {
        try await gatewayClient.executeChat(
            using: config ?? self.config,
            message: message,
            sessionKey: sessionKey,
            thinkingLevel: thinkingLevel,
            timeoutSeconds: timeoutSeconds,
            onRunStarted: onRunStarted,
            onAssistantTextUpdated: onAssistantTextUpdated
        )
    }

    func listGatewaySessions(
        using config: OpenClawConfig? = nil,
        limit: Int? = nil
    ) async throws -> [OpenClawGatewayClient.ChatSessionRecord] {
        try await gatewayClient.listSessions(using: config ?? self.config, limit: limit)
    }

    func gatewayChatHistory(
        sessionKey: String,
        using config: OpenClawConfig? = nil,
        limit: Int? = nil
    ) async throws -> [OpenClawGatewayClient.ChatTranscriptMessage] {
        try await gatewayClient.chatHistory(
            using: config ?? self.config,
            sessionKey: sessionKey,
            limit: limit
        )
    }

    func abortGatewayChatRun(
        sessionKey: String,
        runID: String,
        using config: OpenClawConfig? = nil
    ) async throws {
        try await gatewayClient.abortChatRun(
            using: config ?? self.config,
            sessionKey: sessionKey,
            runID: runID
        )
    }

    func resolvedOpenClawPath(using config: OpenClawConfig? = nil) -> String {
        resolveOpenClawPath(for: config ?? self.config)
    }

    private func agentRuntimeChannel(for config: OpenClawConfig) throws -> AgentRuntimeChannel {
        let key = agentRuntimeChannelKey(for: config)

        agentRuntimeChannelLock.lock()
        if let existing = agentRuntimeChannels[key] {
            agentRuntimeChannelLock.unlock()
            return existing
        }
        agentRuntimeChannelLock.unlock()

        let channel = try AgentRuntimeChannel(
            key: key,
            config: config,
            resolvedOpenClawPath: resolveOpenClawPath(for: config)
        )

        agentRuntimeChannelLock.lock()
        if let existing = agentRuntimeChannels[key] {
            agentRuntimeChannelLock.unlock()
            return existing
        }
        agentRuntimeChannels[key] = channel
        agentRuntimeChannelLock.unlock()
        return channel
    }

    private func agentRuntimeChannelKey(for config: OpenClawConfig) -> String {
        switch config.deploymentKind {
        case .local:
            return "local|\(resolveOpenClawPath(for: config))"
        case .container:
            let engine = config.container.engine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "docker"
                : config.container.engine.trimmingCharacters(in: .whitespacesAndNewlines)
            let containerName = config.container.containerName.trimmingCharacters(in: .whitespacesAndNewlines)
            return "container|\(engine)|\(containerName)"
        case .remoteServer:
            let host = config.host.trimmingCharacters(in: .whitespacesAndNewlines)
            return "remote|\(host)|\(config.port)|\(config.useSSL)"
        }
    }

    private func parseManagedAgents(from data: Data, using config: OpenClawConfig) -> [ManagedAgentRecord] {
        guard
            let jsonData = extractJSONPayload(from: data),
            let jsonObject = try? JSONSerialization.jsonObject(with: jsonData),
            let dictionaries = dictionaryArray(in: jsonObject)
        else {
            let names = parsePlainTextList(from: data)
            return names.enumerated().map { index, name in
                ManagedAgentRecord(
                    id: name,
                    name: name,
                    targetIdentifier: name,
                    modelIdentifier: ""
                )
            }
        }

        return dictionaries.enumerated().map { index, dictionary in
            let id = stringValue(dictionary, keys: ["id", "agentID", "agentId", "name"]) ?? "agent-\(index)"
            let name = stringValue(dictionary, keys: ["name", "displayName", "agentName"]) ?? id
            let agentDirPath = stringValue(dictionary, keys: ["agentDir", "agentDirPath", "directory", "agentDirectory"])
            let workspacePath = stringValue(dictionary, keys: ["workspace", "workspacePath", "workdir", "workPath"])
            let modelIdentifier = stringValue(dictionary, keys: ["model", "modelIdentifier", "primaryModel", "defaultModel"]) ?? ""

            let installedSkills = loadInstalledSkills(
                forWorkspacePath: workspacePath,
                using: config
            )

            return ManagedAgentRecord(
                id: id,
                configIndex: index,
                name: name,
                targetIdentifier: id,
                agentDirPath: agentDirPath,
                workspacePath: workspacePath,
                modelIdentifier: modelIdentifier,
                installedSkills: installedSkills
            )
        }
    }

    private func loadInstalledSkills(
        forWorkspacePath workspacePath: String?,
        using config: OpenClawConfig
    ) -> [ManagedAgentSkillRecord] {
        guard let workspacePath, !workspacePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        switch config.deploymentKind {
        case .local:
            let skillsPath = URL(fileURLWithPath: workspacePath, isDirectory: true)
                .appendingPathComponent("skills", isDirectory: true)
            guard let contents = try? FileManager.default.contentsOfDirectory(at: skillsPath, includingPropertiesForKeys: [.isDirectoryKey]) else {
                return []
            }

            return contents.compactMap { item in
                let values = try? item.resourceValues(forKeys: [.isDirectoryKey])
                if values?.isDirectory == true {
                    return ManagedAgentSkillRecord(name: item.lastPathComponent, path: item.path)
                }
                if item.pathExtension.lowercased() == "md" {
                    return ManagedAgentSkillRecord(name: item.deletingPathExtension().lastPathComponent, path: item.path)
                }
                return nil
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .container:
            guard let containerName = containerName(for: config) else { return [] }

            let skillsPath = URL(fileURLWithPath: workspacePath, isDirectory: true)
                .appendingPathComponent("skills", isDirectory: true)
                .path

            let script = """
            if [ -d \(shellQuoted(skillsPath)) ]; then
              find \(shellQuoted(skillsPath)) -mindepth 1 -maxdepth 1 -print 2>/dev/null
            fi
            """

            guard let result = try? runDeploymentCommand(
                using: config,
                arguments: ["exec", containerName, "sh", "-lc", script]
            ), result.terminationStatus == 0 else {
                return []
            }

            let paths = parsePlainTextList(from: result.standardOutput)
            return paths.map {
                ManagedAgentSkillRecord(name: URL(fileURLWithPath: $0).lastPathComponent, path: $0)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .remoteServer:
            return []
        }
    }

    private func parsePlainTextList(from data: Data) -> [String] {
        let output = String(data: data, encoding: .utf8)?
            .replacingOccurrences(of: "\\n", with: "\n") ?? ""
        return output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { line in
                !line.isEmpty && !isDiagnosticOutputLine(line)
            }
    }

    private func parseClawHubSkillRecords(from data: Data) -> [ClawHubSkillRecord] {
        let lines = parsePlainTextList(from: data)
        var records: [ClawHubSkillRecord] = []

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            if line.hasPrefix("NAME") || line.hasPrefix("SLUG") {
                continue
            }
            if line.allSatisfy({ $0 == "-" || $0 == "|" }) {
                continue
            }

            if line.contains("|") {
                let columns = line
                    .split(separator: "|")
                    .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                if let slug = columns.first, !slug.isEmpty {
                    let summary = columns.dropFirst().joined(separator: " | ")
                    records.append(ClawHubSkillRecord(slug: slug, summary: summary))
                    continue
                }
            }

            if let range = line.range(of: " - ") {
                let slug = String(line[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                let summary = String(line[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !slug.isEmpty {
                    records.append(ClawHubSkillRecord(slug: slug, summary: summary))
                    continue
                }
            }

            let parts = line
                .split(maxSplits: 1, omittingEmptySubsequences: true) { $0 == " " || $0 == "\t" }
                .map(String.init)
            if let slug = parts.first, !slug.isEmpty {
                let summary = parts.count > 1 ? parts[1].trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) : ""
                records.append(ClawHubSkillRecord(slug: slug, summary: summary))
            }
        }

        var seen = Set<String>()
        return records
            .filter { seen.insert($0.slug.lowercased()).inserted }
            .sorted { $0.slug.localizedCaseInsensitiveCompare($1.slug) == .orderedAscending }
    }

    private func filterSkillRecords(_ records: [ClawHubSkillRecord], with query: String) -> [ClawHubSkillRecord] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else { return records }

        return records.filter { record in
            record.slug.lowercased().contains(normalizedQuery) || record.summary.lowercased().contains(normalizedQuery)
        }
    }

    private func dictionaryArray(in value: Any) -> [[String: Any]]? {
        if let array = value as? [[String: Any]] {
            return array
        }

        if let dictionary = value as? [String: Any] {
            for key in ["agents", "list", "items", "data"] {
                if let nested = dictionary[key], let nestedArray = dictionaryArray(in: nested) {
                    return nestedArray
                }
            }
        }

        return nil
    }

    private func mergeManagedAgents(
        for project: MAProject,
        runtimeRecords: [ManagedAgentRecord],
        using config: OpenClawConfig
    ) -> [ManagedAgentRecord] {
        let detectedRecords = project.openClaw.detectedAgents.isEmpty ? discoveryResults : project.openClaw.detectedAgents

        return project.agents.map { projectAgent in
            let candidateKeys = managedAgentLookupKeys(for: projectAgent)
            let runtimeRecord = runtimeRecords.first { runtime in
                candidateKeys.contains(normalizeAgentKey(runtime.targetIdentifier))
                    || candidateKeys.contains(normalizeAgentKey(runtime.name))
            }
            let detectedRecord = detectedRecords.first { record in
                candidateKeys.contains(normalizeAgentKey(record.name))
            }

            let resolvedPaths = resolveManagedAgentPaths(
                for: projectAgent,
                runtimeRecord: runtimeRecord,
                detectedRecord: detectedRecord
            )

            let runtimeModel = runtimeRecord?.modelIdentifier.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let projectModel = projectAgent.openClawDefinition.modelIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
            let modelIdentifier = runtimeModel.isEmpty ? projectModel : runtimeModel

            return ManagedAgentRecord(
                id: projectAgent.id.uuidString,
                projectAgentID: projectAgent.id,
                configIndex: runtimeRecord?.configIndex,
                name: projectAgent.name,
                targetIdentifier: normalizedTargetIdentifier(for: projectAgent),
                agentDirPath: resolvedPaths.agentDirPath,
                workspacePath: resolvedPaths.workspacePath,
                modelIdentifier: modelIdentifier,
                installedSkills: loadInstalledSkills(
                    forWorkspacePath: resolvedPaths.workspacePath,
                    using: config
                )
            )
        }
    }

    private func managedAgentLookupKeys(for agent: Agent) -> Set<String> {
        var keys = Set<String>()
        let identifier = normalizedTargetIdentifier(for: agent)
        if !identifier.isEmpty {
            keys.insert(normalizeAgentKey(identifier))
        }
        let normalizedName = normalizeAgentKey(agent.name)
        if !normalizedName.isEmpty {
            keys.insert(normalizedName)
        }
        return keys
    }

    private func normalizedTargetIdentifier(for agent: Agent) -> String {
        let identifier = agent.openClawDefinition.agentIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        return identifier.isEmpty ? agent.name : identifier
    }

    private func resolveManagedAgentPaths(
        for projectAgent: Agent,
        runtimeRecord: ManagedAgentRecord?,
        detectedRecord: ProjectOpenClawDetectedAgentRecord?
    ) -> (agentDirPath: String?, workspacePath: String?) {
        let projectPaths = resolveProjectManagedAgentPaths(for: projectAgent, detectedRecord: detectedRecord)
        let workspacePath = firstNonEmptyPath(
            runtimeRecord?.workspacePath,
            projectPaths.workspacePath,
            detectedRecord?.workspacePath
        )
        let agentDirPath = firstNonEmptyPath(
            runtimeRecord?.agentDirPath,
            projectPaths.agentDirPath,
            detectedRecord?.directoryPath
        )
        return (agentDirPath, workspacePath)
    }

    private func resolveProjectManagedAgentPaths(
        for projectAgent: Agent,
        detectedRecord: ProjectOpenClawDetectedAgentRecord?
    ) -> (agentDirPath: String?, workspacePath: String?) {
        if let memoryBackupPath = firstNonEmptyPath(projectAgent.openClawDefinition.memoryBackupPath) {
            let privateURL = URL(fileURLWithPath: memoryBackupPath, isDirectory: true)
            let agentRoot = privateURL.lastPathComponent == "private" ? privateURL.deletingLastPathComponent() : privateURL
            let workspaceURL = agentRoot.appendingPathComponent("workspace", isDirectory: true)

            return (
                agentDirPath: FileManager.default.fileExists(atPath: privateURL.path) ? privateURL.path : nil,
                workspacePath: FileManager.default.fileExists(atPath: workspaceURL.path) ? workspaceURL.path : nil
            )
        }

        if let copiedRootPath = firstNonEmptyPath(detectedRecord?.copiedToProjectPath) {
            let copiedRootURL = URL(fileURLWithPath: copiedRootPath, isDirectory: true)
            let privateURL = copiedRootURL.appendingPathComponent("private", isDirectory: true)
            let workspaceURL = copiedRootURL.appendingPathComponent("workspace", isDirectory: true)

            return (
                agentDirPath: FileManager.default.fileExists(atPath: privateURL.path) ? privateURL.path : nil,
                workspacePath: FileManager.default.fileExists(atPath: workspaceURL.path) ? workspaceURL.path : nil
            )
        }

        return (nil, nil)
    }

    private func firstNonEmptyPath(_ candidates: String?...) -> String? {
        for candidate in candidates {
            guard let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
                continue
            }
            return trimmed
        }
        return nil
    }

    private func isDiagnosticOutputLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return true
        }
        if trimmed.hasPrefix("[plugins]") || trimmed.hasPrefix("Config warnings:") {
            return true
        }
        if trimmed.hasPrefix("- plugins.") || trimmed.contains("duplicate plugin id detected") {
            return true
        }
        return false
    }

    private func extractJSONPayload(from data: Data) -> Data? {
        guard let output = String(data: data, encoding: .utf8) else { return nil }
        let characters = Array(output)

        for startIndex in characters.indices {
            let opening = characters[startIndex]
            guard opening == "[" || opening == "{" else { continue }

            var stack: [Character] = [opening]
            var isInsideString = false
            var isEscaping = false

            for index in characters.index(after: startIndex)..<characters.endIndex {
                let character = characters[index]

                if isInsideString {
                    if isEscaping {
                        isEscaping = false
                    } else if character == "\\" {
                        isEscaping = true
                    } else if character == "\"" {
                        isInsideString = false
                    }
                    continue
                }

                if character == "\"" {
                    isInsideString = true
                    continue
                }

                if character == "[" || character == "{" {
                    stack.append(character)
                    continue
                }

                if character == "]" || character == "}" {
                    guard let last = stack.last else { break }
                    let matches = (last == "[" && character == "]") || (last == "{" && character == "}")
                    guard matches else { break }
                    stack.removeLast()

                    if stack.isEmpty {
                        let payload = String(characters[startIndex...index])
                        guard let payloadData = payload.data(using: .utf8) else { return nil }
                        if (try? JSONSerialization.jsonObject(with: payloadData)) != nil {
                            return payloadData
                        }
                        break
                    }
                }
            }
        }

        return nil
    }

    private func runOpenClawCommand(
        using config: OpenClawConfig,
        arguments: [String],
        standardInput: FileHandle? = nil
    ) throws -> (terminationStatus: Int32, standardOutput: Data, standardError: Data) {
        switch config.deploymentKind {
        case .local:
            let process = Process()
            process.executableURL = URL(fileURLWithPath: resolveOpenClawPath(for: config))
            process.arguments = arguments

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            process.standardInput = standardInput

            try process.run()
            process.waitUntilExit()

            let stdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            return (process.terminationStatus, stdout, stderr)
        case .container:
            guard let containerName = containerName(for: config) else {
                throw NSError(domain: "OpenClawManager", code: 11, userInfo: [NSLocalizedDescriptionKey: "容器名称未配置"])
            }
            return try runDeploymentCommand(using: config, arguments: ["exec", containerName, "openclaw"] + arguments, standardInput: standardInput)
        case .remoteServer:
            throw NSError(domain: "OpenClawManager", code: 12, userInfo: [NSLocalizedDescriptionKey: "远程网关模式不支持直接执行 OpenClaw CLI"])
        }
    }

    private func runClawHubCommand(
        using config: OpenClawConfig,
        arguments: [String],
        standardInput: FileHandle? = nil
    ) throws -> (terminationStatus: Int32, standardOutput: Data, standardError: Data) {
        switch config.deploymentKind {
        case .local:
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["clawhub"] + arguments

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            process.standardInput = standardInput

            try process.run()
            process.waitUntilExit()

            let stdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            return (process.terminationStatus, stdout, stderr)
        case .container:
            guard let containerName = containerName(for: config) else {
                throw NSError(domain: "OpenClawManager", code: 13, userInfo: [NSLocalizedDescriptionKey: "容器名称未配置"])
            }
            return try runDeploymentCommand(using: config, arguments: ["exec", containerName, "clawhub"] + arguments, standardInput: standardInput)
        case .remoteServer:
            throw NSError(domain: "OpenClawManager", code: 14, userInfo: [NSLocalizedDescriptionKey: "远程网关模式不支持直接执行 ClawHub CLI"])
        }
    }

    private func mergeImportedRecords(_ importedRecords: [ProjectOpenClawDetectedAgentRecord]) -> [ProjectOpenClawDetectedAgentRecord] {
        var merged = discoveryResults
        for imported in importedRecords {
            if let index = merged.firstIndex(where: { $0.id == imported.id }) {
                merged[index] = imported
            } else {
                merged.append(imported)
            }
        }
        return merged.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func localOpenClawRootURL() -> URL {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent(".openclaw", isDirectory: true)
    }

    func localAgentSoulURL(matching candidateNames: [String]) -> URL? {
        if let existing = existingLocalAgentSoulURL(matching: candidateNames) {
            return existing
        }

        guard let workspacePath = localAgentWorkspacePath(matching: candidateNames) else {
            return nil
        }

        return preferredSoulURL(in: URL(fileURLWithPath: workspacePath, isDirectory: true))
    }

    func localAgentWorkspacePath(matching candidateNames: [String]) -> String? {
        let normalizedNames = Set(candidateNames.map(normalizeAgentKey).filter { !$0.isEmpty })
        guard !normalizedNames.isEmpty else { return nil }

        let workspaceMap = localAgentWorkspaceMap()
        for name in normalizedNames {
            if let workspacePath = workspaceMap[name] {
                return workspacePath
            }
        }
        return nil
    }

    private func existingLocalAgentSoulURL(matching candidateNames: [String]) -> URL? {
        if let workspacePath = localAgentWorkspacePath(matching: candidateNames) {
            let workspaceURL = URL(fileURLWithPath: workspacePath, isDirectory: true)
            if let soulURL = existingSoulURL(in: workspaceURL) {
                return soulURL
            }
        }

        let normalizedNames = Set(candidateNames.map(normalizeAgentKey).filter { !$0.isEmpty })
        if !normalizedNames.isEmpty {
            if let record = discoveryResults.first(where: { normalizedNames.contains(normalizeAgentKey($0.name)) }) {
                if let copiedRoot = firstNonEmptyPath(record.copiedToProjectPath),
                   let soulURL = existingSoulURL(in: URL(fileURLWithPath: copiedRoot, isDirectory: true)) {
                    return soulURL
                }
                if let directoryPath = firstNonEmptyPath(record.directoryPath),
                   let soulURL = existingSoulURL(in: URL(fileURLWithPath: directoryPath, isDirectory: true)) {
                    return soulURL
                }
            }
        }

        return nil
    }

    private func stageProjectAgentsIntoMirror(_ project: MAProject) -> MirrorStageResult {
        let mirrorURL = ProjectManager.shared.openClawMirrorDirectory(for: project.id)
        let backupURL: URL? = {
            if let sessionContext, sessionContext.projectID == project.id {
                return sessionContext.backupURL
            }
            if let backupPath = firstNonEmptyPath(project.openClaw.sessionBackupPath) {
                return URL(fileURLWithPath: backupPath, isDirectory: true)
            }
            return nil
        }()

        try? FileManager.default.createDirectory(at: mirrorURL, withIntermediateDirectories: true)

        var result = MirrorStageResult()
        for agent in project.agents {
            guard let soulURL = resolveProjectMirrorSoulURL(for: agent, in: project, mirrorURL: mirrorURL, backupURL: backupURL) else {
                result.unresolvedAgentNames.append(agent.name)
                continue
            }

            do {
                try FileManager.default.createDirectory(at: soulURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try agent.soulMD.write(to: soulURL, atomically: true, encoding: .utf8)
                result.updatedAgentCount += 1
            } catch {
                result.unresolvedAgentNames.append(agent.name)
            }
        }

        return result
    }

    private func applySessionMirrorToDeployment() throws {
        guard let sessionContext else { return }

        switch config.deploymentKind {
        case .local:
            let openClawRoot = localOpenClawRootURL()
            _ = try replaceDirectoryContents(of: openClawRoot, withContentsOf: sessionContext.mirrorURL)
        case .container:
            guard let deploymentRootPath = containerOpenClawRootPath(for: config) else {
                throw NSError(
                    domain: "OpenClawManager",
                    code: 15,
                    userInfo: [NSLocalizedDescriptionKey: "无法解析容器内 OpenClaw 路径"]
                )
            }
            try copyLocalContentsToDeployment(sessionContext.mirrorURL, deploymentRootPath: deploymentRootPath, using: config)
        case .remoteServer:
            break
        }
    }

    private func mirrorStageMessage(from result: MirrorStageResult) -> String? {
        var parts: [String] = []
        if result.updatedAgentCount > 0 {
            parts.append("已更新 \(result.updatedAgentCount) 个 agent 的项目镜像")
        }
        if !result.unresolvedAgentNames.isEmpty {
            let names = result.unresolvedAgentNames.sorted().joined(separator: ", ")
            parts.append("未能定位这些 agent 的 SOUL 路径：\(names)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: "；")
    }

    private func resolveProjectMirrorSoulURL(
        for agent: Agent,
        in project: MAProject,
        mirrorURL: URL,
        backupURL: URL?
    ) -> URL? {
        let candidateNames = Array(
            Set([
                agent.name,
                agent.openClawDefinition.agentIdentifier,
                normalizedTargetIdentifier(for: agent)
            ].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        )

        if let existingMirrorMatch = findMatchingSoulURL(in: mirrorURL, matching: candidateNames) {
            return existingMirrorMatch
        }

        let sourceCandidates = mirrorSourceCandidates(for: agent, in: project, matching: candidateNames)
        for sourceURL in sourceCandidates {
            if let translated = translateURLToMirror(
                sourceURL,
                mirrorURL: mirrorURL,
                currentBackupURL: backupURL,
                project: project
            ) {
                return translated
            }
        }

        if let backupURL,
           let backupMatch = findMatchingSoulURL(in: backupURL, matching: candidateNames),
           let translated = translateRelativeURL(backupMatch, from: backupURL, to: mirrorURL) {
            return translated
        }

        let fallbackName = safePathComponent(normalizedTargetIdentifier(for: agent))
        return mirrorURL
            .appendingPathComponent("agents", isDirectory: true)
            .appendingPathComponent(fallbackName, isDirectory: true)
            .appendingPathComponent("SOUL.md", isDirectory: false)
    }

    private func mirrorSourceCandidates(
        for agent: Agent,
        in project: MAProject,
        matching candidateNames: [String]
    ) -> [URL] {
        var sources: [URL] = []

        if let sourcePath = firstNonEmptyPath(agent.openClawDefinition.soulSourcePath) {
            sources.append(URL(fileURLWithPath: sourcePath, isDirectory: false))
        }

        if let localSoulURL = localAgentSoulURL(matching: candidateNames) {
            sources.append(localSoulURL)
        }

        let normalizedNames = Set(candidateNames.map(normalizeAgentKey))
        if let detectedRecord = discoveryResults.first(where: { normalizedNames.contains(normalizeAgentKey($0.name)) }) {
            if let directoryPath = firstNonEmptyPath(detectedRecord.directoryPath) {
                sources.append(preferredSoulURL(in: URL(fileURLWithPath: directoryPath, isDirectory: true)))
            }
            if let copiedRootPath = firstNonEmptyPath(detectedRecord.copiedToProjectPath) {
                sources.append(preferredSoulURL(in: URL(fileURLWithPath: copiedRootPath, isDirectory: true)))
            }
        }

        if let memoryBackupPath = firstNonEmptyPath(agent.openClawDefinition.memoryBackupPath) {
            let privateURL = URL(fileURLWithPath: memoryBackupPath, isDirectory: true)
            let rootURL = privateURL.lastPathComponent == "private" ? privateURL.deletingLastPathComponent() : privateURL
            sources.append(preferredSoulURL(in: rootURL))
        }

        var seen = Set<String>()
        return sources.filter { seen.insert($0.path).inserted }
    }

    private func translateURLToMirror(
        _ sourceURL: URL,
        mirrorURL: URL,
        currentBackupURL: URL?,
        project: MAProject
    ) -> URL? {
        if sourceURL.path == mirrorURL.path || sourceURL.path.hasPrefix(mirrorURL.path + "/") {
            return sourceURL
        }

        var sourceRoots: [URL] = []
        if let currentBackupURL {
            sourceRoots.append(currentBackupURL)
        }
        if let previousMirrorPath = firstNonEmptyPath(project.openClaw.sessionMirrorPath) {
            sourceRoots.append(URL(fileURLWithPath: previousMirrorPath, isDirectory: true))
        }
        if let previousBackupPath = firstNonEmptyPath(project.openClaw.sessionBackupPath) {
            sourceRoots.append(URL(fileURLWithPath: previousBackupPath, isDirectory: true))
        }
        if config.deploymentKind == .local {
            sourceRoots.append(localOpenClawRootURL())
        }

        var seen = Set<String>()
        for sourceRoot in sourceRoots where seen.insert(sourceRoot.path).inserted {
            if let translated = translateRelativeURL(sourceURL, from: sourceRoot, to: mirrorURL) {
                return translated
            }
        }

        return nil
    }

    private func translateRelativeURL(_ sourceURL: URL, from sourceRoot: URL, to targetRoot: URL) -> URL? {
        let normalizedSourceRoot = sourceRoot.standardizedFileURL.path
        let normalizedSourceURL = sourceURL.standardizedFileURL.path
        guard normalizedSourceURL == normalizedSourceRoot || normalizedSourceURL.hasPrefix(normalizedSourceRoot + "/") else {
            return nil
        }

        let relativePath = String(normalizedSourceURL.dropFirst(normalizedSourceRoot.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !relativePath.isEmpty else { return targetRoot }
        return targetRoot.appendingPathComponent(relativePath, isDirectory: false)
    }

    private func findMatchingSoulURL(in rootURL: URL, matching candidateNames: [String]) -> URL? {
        guard FileManager.default.fileExists(atPath: rootURL.path) else { return nil }

        let normalizedNames = Set(candidateNames.map(normalizeAgentKey).filter { !$0.isEmpty })
        guard !normalizedNames.isEmpty else { return nil }

        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        var bestMatch: (score: Int, url: URL)?
        for case let fileURL as URL in enumerator {
            let filename = fileURL.lastPathComponent.lowercased()
            guard filename == "soul.md" else { continue }

            let score = scoreSoulURL(fileURL, matching: normalizedNames)
            guard score > 0 else { continue }

            if let currentBest = bestMatch {
                if score > currentBest.score {
                    bestMatch = (score, fileURL)
                }
            } else {
                bestMatch = (score, fileURL)
            }
        }

        return bestMatch?.url
    }

    private func scoreSoulURL(_ fileURL: URL, matching candidateNames: Set<String>) -> Int {
        var score = 0
        var current = fileURL.deletingLastPathComponent()

        for depth in 0..<6 {
            let normalizedComponent = normalizeAgentKey(current.lastPathComponent)
            if candidateNames.contains(normalizedComponent) {
                score = max(score, 100 - (depth * 10))
            } else {
                let pathComponent = normalizeAgentKey(current.path)
                if candidateNames.contains(where: { !$0.isEmpty && pathComponent.contains($0) }) {
                    score = max(score, 50 - (depth * 5))
                }
            }

            let parent = current.deletingLastPathComponent()
            if parent.path == current.path {
                break
            }
            current = parent
        }

        return score
    }
    private func localAgentWorkspaceMap() -> [String: String] {
        let configURL = localOpenClawRootURL().appendingPathComponent("openclaw.json")
        let currentModificationDate = (try? fileManager.attributesOfItem(atPath: configURL.path)[.modificationDate] as? Date) ?? nil

        if cachedLocalWorkspaceConfigModificationDate == currentModificationDate,
           !cachedLocalWorkspaceMap.isEmpty {
            return cachedLocalWorkspaceMap
        }

        guard
            let data = try? Data(contentsOf: configURL),
            let json = try? JSONSerialization.jsonObject(with: data),
            let root = json as? [String: Any],
            let agents = root["agents"] as? [String: Any],
            let list = agents["list"] as? [[String: Any]]
        else {
            cachedLocalWorkspaceMap = [:]
            cachedLocalWorkspaceConfigModificationDate = currentModificationDate
            return [:]
        }

        var map: [String: String] = [:]
        for entry in list {
            guard let id = stringValue(entry, keys: ["id", "agentID", "agentId", "name"]),
                  let workspace = stringValue(entry, keys: ["workspace", "workspacePath", "workdir", "workPath"]) else {
                continue
            }
            map[normalizeAgentKey(id)] = workspace
        }
        cachedLocalWorkspaceMap = map
        cachedLocalWorkspaceConfigModificationDate = currentModificationDate
        return map
    }

    private func localLoopbackGatewayConfig(using baseConfig: OpenClawConfig) -> OpenClawConfig? {
        let configURL = localOpenClawRootURL().appendingPathComponent("openclaw.json")
        let currentModificationDate = (try? fileManager.attributesOfItem(atPath: configURL.path)[.modificationDate] as? Date) ?? nil

        if cachedLocalGatewayConfigModificationDate == currentModificationDate {
            return cachedLocalGatewayConfig
        }

        guard
            let data = try? Data(contentsOf: configURL),
            let json = try? JSONSerialization.jsonObject(with: data),
            let root = json as? [String: Any],
            let gateway = root["gateway"] as? [String: Any]
        else {
            cachedLocalGatewayConfig = nil
            cachedLocalGatewayConfigModificationDate = currentModificationDate
            return nil
        }

        let mode = (stringValue(gateway, keys: ["mode"]) ?? "local").lowercased()
        guard mode == "local" else {
            cachedLocalGatewayConfig = nil
            cachedLocalGatewayConfigModificationDate = currentModificationDate
            return nil
        }

        let port = intValue(gateway, keys: ["port"]) ?? baseConfig.port
        guard port > 0 else {
            cachedLocalGatewayConfig = nil
            cachedLocalGatewayConfigModificationDate = currentModificationDate
            return nil
        }

        let auth = gateway["auth"] as? [String: Any] ?? [:]
        let authMode = (stringValue(auth, keys: ["mode"]) ?? "token").lowercased()
        let token = auth["token"] as? String
        let normalizedToken = token?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let resolvedToken: String
        switch authMode {
        case "none":
            resolvedToken = ""
        case "token":
            guard !normalizedToken.isEmpty else {
                cachedLocalGatewayConfig = nil
                cachedLocalGatewayConfigModificationDate = currentModificationDate
                return nil
            }
            resolvedToken = normalizedToken
        default:
            cachedLocalGatewayConfig = nil
            cachedLocalGatewayConfigModificationDate = currentModificationDate
            return nil
        }

        let gatewayConfig = OpenClawConfig(
            deploymentKind: .remoteServer,
            host: "127.0.0.1",
            port: port,
            useSSL: false,
            apiKey: resolvedToken,
            defaultAgent: baseConfig.defaultAgent,
            timeout: baseConfig.timeout,
            autoConnect: baseConfig.autoConnect,
            localBinaryPath: baseConfig.localBinaryPath,
            container: baseConfig.container,
            cliQuietMode: baseConfig.cliQuietMode,
            cliLogLevel: baseConfig.cliLogLevel
        )

        cachedLocalGatewayConfig = gatewayConfig
        cachedLocalGatewayConfigModificationDate = currentModificationDate
        return gatewayConfig
    }

    private func existingSoulURL(in rootURL: URL) -> URL? {
        let preferred = rootURL.appendingPathComponent("SOUL.md")
        if FileManager.default.fileExists(atPath: preferred.path) { return preferred }

        let fallback = rootURL.appendingPathComponent("soul.md")
        if FileManager.default.fileExists(atPath: fallback.path) { return fallback }
        return nil
    }

    private struct DirectoryInspection {
        let name: String
        let path: String
        let workspacePath: String?
        let statePath: String?
        let hasSoulFile: Bool
    }

    private struct ConfigInspection {
        let name: String
        let configPath: String?
        let workspacePath: String?
        let statePath: String?
    }

    private func inspectOpenClawAgents(using config: OpenClawConfig, fallbackAgentNames: [String] = []) -> [ProjectOpenClawDetectedAgentRecord] {
        switch config.deploymentKind {
        case .local:
            clearDiscoverySnapshot()
            return inspectOpenClawAgents(at: localOpenClawRootURL(), fallbackAgentNames: fallbackAgentNames)
        case .container:
            guard let snapshotURL = try? prepareDiscoverySnapshot(using: config) else {
                return fallbackAgentNames.map {
                    ProjectOpenClawDetectedAgentRecord(
                        id: $0,
                        name: $0,
                        directoryValidated: false,
                        configValidated: false,
                        issues: ["无法读取容器中的 OpenClaw 文件，仅保留 CLI 结果。"]
                    )
                }
            }
            return inspectOpenClawAgents(at: snapshotURL, fallbackAgentNames: fallbackAgentNames)
        case .remoteServer:
            return []
        }
    }

    private func inspectOpenClawAgents(at rootURL: URL, fallbackAgentNames: [String] = []) -> [ProjectOpenClawDetectedAgentRecord] {
        let agentsDirectory = rootURL.appendingPathComponent("agents", isDirectory: true)
        let configURL = rootURL.appendingPathComponent("openclaw.json")

        let directoryInspections = inspectAgentDirectories(at: agentsDirectory)
        let configInspections = inspectAgentConfigCandidates(at: configURL)

        let directoryMap = Dictionary(uniqueKeysWithValues: directoryInspections.map { (normalizeAgentKey($0.name), $0) })
        let configMap = Dictionary(uniqueKeysWithValues: configInspections.map { (normalizeAgentKey($0.name), $0) })
        let mergedKeys = Set(directoryMap.keys).union(configMap.keys).sorted()

        let records = mergedKeys.map { key in
            let directory = directoryMap[key]
            let configCandidate = configMap[key]
            var issues: [String] = []
            let workspacePath = configCandidate?.workspacePath?.trimmingCharacters(in: .whitespacesAndNewlines)
            let workspaceURL = (workspacePath?.isEmpty == false)
                ? URL(fileURLWithPath: workspacePath!, isDirectory: true)
                : nil
            let workspaceValidated = workspaceURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
            let sourceDirectoryPath = workspaceValidated ? workspaceURL?.path : directory?.path
            let directoryValidated = workspaceValidated || directory != nil
            let configValidated = configCandidate != nil

            if !directoryValidated {
                issues.append("workspace 目录未找到")
            } else if let sourceDirectoryPath {
                let soulURL = URL(fileURLWithPath: sourceDirectoryPath, isDirectory: true)
                if existingSoulURL(in: soulURL) == nil {
                    issues.append("缺少 SOUL.md")
                }
            } else {
                issues.append("缺少 SOUL.md")
            }

            if !configValidated {
                issues.append("openclaw.json 中未找到匹配项")
            }

            let name = configCandidate?.name ?? directory?.name ?? key
            let recordID = [
                name,
                sourceDirectoryPath ?? "",
                configCandidate?.configPath ?? ""
            ].joined(separator: "|")

            return ProjectOpenClawDetectedAgentRecord(
                id: recordID,
                name: name,
                directoryPath: sourceDirectoryPath,
                configPath: configCandidate?.configPath,
                workspacePath: configCandidate?.workspacePath ?? directory?.workspacePath,
                statePath: configCandidate?.statePath ?? directory?.statePath,
                directoryValidated: directoryValidated,
                configValidated: configValidated,
                issues: issues
            )
        }
        .sorted(by: { (lhs: ProjectOpenClawDetectedAgentRecord, rhs: ProjectOpenClawDetectedAgentRecord) in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        })

        if !records.isEmpty {
            return records
        }

        guard !fallbackAgentNames.isEmpty else {
            return []
        }

        return fallbackAgentNames.map {
            ProjectOpenClawDetectedAgentRecord(
                id: $0,
                name: $0,
                directoryValidated: false,
                configValidated: false,
                issues: ["未发现可验证的 agent 文件，仅保留 CLI 结果。"]
            )
        }
        .sorted(by: { (lhs: ProjectOpenClawDetectedAgentRecord, rhs: ProjectOpenClawDetectedAgentRecord) in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        })
    }

    private func inspectAgentDirectories(at agentsDirectory: URL) -> [DirectoryInspection] {
        guard let contents = try? FileManager.default.contentsOfDirectory(at: agentsDirectory, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return []
        }

        return contents.compactMap { url in
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            guard values?.isDirectory == true else { return nil }

            let soulFile = url.appendingPathComponent("SOUL.md")
            let fallbackSoulFile = url.appendingPathComponent("soul.md")
            let hasSoulFile = FileManager.default.fileExists(atPath: soulFile.path) || FileManager.default.fileExists(atPath: fallbackSoulFile.path)

            let workspacePath = firstExistingChildPath(in: url, candidates: ["workspace", "workspaces", "job", "jobs"])
            let statePath = firstExistingChildPath(in: url, candidates: ["state", "status", "runtime", "private"])

            return DirectoryInspection(
                name: url.lastPathComponent,
                path: url.path,
                workspacePath: workspacePath,
                statePath: statePath,
                hasSoulFile: hasSoulFile
            )
        }
    }

    private func inspectAgentConfigCandidates(at configURL: URL) -> [ConfigInspection] {
        guard let data = try? Data(contentsOf: configURL),
              let json = try? JSONSerialization.jsonObject(with: data) else {
            return []
        }

        var candidates: [ConfigInspection] = []

        func walk(_ value: Any, path: [String]) {
            if let dict = value as? [String: Any] {
                let name = stringValue(dict, keys: ["name", "agentName", "agentIdentifier", "identifier", "id"])
                let configPath = stringValue(dict, keys: ["configPath", "path", "filePath"])
                let workspacePath = stringValue(dict, keys: ["workspacePath", "workspace", "workPath", "workdir"])
                let statePath = stringValue(dict, keys: ["statePath", "statusPath", "privatePath", "state", "private"])

                if let name, (path.contains("agents") || configPath != nil || workspacePath != nil || statePath != nil) {
                    candidates.append(
                        ConfigInspection(
                            name: name,
                            configPath: configPath ?? configURL.path,
                            workspacePath: workspacePath,
                            statePath: statePath
                        )
                    )
                }

                for (key, child) in dict {
                    walk(child, path: path + [key])
                }
            } else if let array = value as? [Any] {
                for child in array {
                    walk(child, path: path)
                }
            }
        }

        walk(json, path: [])

        var unique: [String: ConfigInspection] = [:]
        for candidate in candidates {
            unique[normalizeAgentKey(candidate.name)] = candidate
        }
        return Array(unique.values).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func firstExistingChildPath(in url: URL, candidates: [String]) -> String? {
        for candidate in candidates {
            let child = url.appendingPathComponent(candidate, isDirectory: true)
            if FileManager.default.fileExists(atPath: child.path) {
                return child.path
            }
        }
        return nil
    }

    private func preferredSoulURL(in rootURL: URL) -> URL {
        let preferred = rootURL.appendingPathComponent("SOUL.md")
        let fallback = rootURL.appendingPathComponent("soul.md")
        if FileManager.default.fileExists(atPath: preferred.path) { return preferred }
        if FileManager.default.fileExists(atPath: fallback.path) { return fallback }
        return preferred
    }

    private func stringValue(_ dictionary: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = dictionary[key] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
        }
        return nil
    }

    private func intValue(_ dictionary: [String: Any], keys: [String]) -> Int? {
        for key in keys {
            if let value = dictionary[key] as? Int {
                return value
            }
            if let value = dictionary[key] as? NSNumber {
                return value.intValue
            }
            if let value = dictionary[key] as? String,
               let parsed = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return parsed
            }
        }
        return nil
    }

    private func normalizeAgentKey(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func desiredAllowAgentsMap(for project: MAProject) -> [String: [String]] {
        var identifierByAgentID: [UUID: String] = [:]
        var desiredSetBySourceKey: [String: Set<String>] = [:]

        for agent in project.agents {
            let identifier = normalizedTargetIdentifier(for: agent).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !identifier.isEmpty else { continue }
            identifierByAgentID[agent.id] = identifier
            desiredSetBySourceKey[normalizeAgentKey(identifier), default: []] = []
        }

        for permission in project.permissions where permission.permissionType == .allow {
            guard let fromIdentifier = identifierByAgentID[permission.fromAgentID],
                  let toIdentifier = identifierByAgentID[permission.toAgentID] else {
                continue
            }

            let normalizedFrom = normalizeAgentKey(fromIdentifier)
            let normalizedTo = normalizeAgentKey(toIdentifier)
            guard !normalizedFrom.isEmpty, !normalizedTo.isEmpty, normalizedFrom != normalizedTo else { continue }

            desiredSetBySourceKey[normalizedFrom, default: []].insert(toIdentifier)
        }

        return desiredSetBySourceKey.reduce(into: [String: [String]]()) { partial, entry in
            partial[entry.key] = entry.value.sorted {
                $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
            }
        }
    }

    private func safePathComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let cleaned = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        let result = String(cleaned)
        return result.isEmpty ? UUID().uuidString : result
    }

    private func directoryHasContent(_ url: URL) -> Bool {
        guard let contents = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) else {
            return false
        }
        return !contents.isEmpty
    }

    private func removeDirectoryContents(at url: URL) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return }

        let contents = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
        for item in contents {
            try? fileManager.removeItem(at: item)
        }
    }

    private func replaceDirectoryContents(of destination: URL, withContentsOf source: URL) throws -> Int {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        try removeDirectoryContents(at: destination)

        guard fileManager.fileExists(atPath: source.path) else { return 0 }

        let contents = try fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
        var copiedItemCount = 0
        for item in contents {
            let target = destination.appendingPathComponent(item.lastPathComponent)
            if fileManager.fileExists(atPath: target.path) {
                try fileManager.removeItem(at: target)
            }
            try fileManager.copyItem(at: item, to: target)
            copiedItemCount += 1
        }
        return copiedItemCount
    }

    private func prepareDiscoverySnapshot(using config: OpenClawConfig) throws -> URL {
        guard let deploymentRootPath = containerOpenClawRootPath(for: config) else {
            throw NSError(domain: "OpenClawManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "无法解析容器内 OpenClaw 路径"])
        }

        clearDiscoverySnapshot()

        let snapshotURL = backupDirectory.appendingPathComponent("discovery-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: snapshotURL, withIntermediateDirectories: true)
        _ = try copyDeploymentContentsToLocal(snapshotURL, deploymentRootPath: deploymentRootPath, using: config)
        discoverySnapshotURL = snapshotURL
        return snapshotURL
    }

    private func clearDiscoverySnapshot() {
        guard let discoverySnapshotURL else { return }
        try? FileManager.default.removeItem(at: discoverySnapshotURL)
        self.discoverySnapshotURL = nil
    }

    private func containerEngine(for config: OpenClawConfig) -> String {
        let trimmed = config.container.engine.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "docker" : trimmed
    }

    private func containerName(for config: OpenClawConfig) -> String? {
        let trimmed = config.container.containerName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func containerOpenClawRootPath(for config: OpenClawConfig) -> String? {
        if let discoveredRoot = discoverContainerOpenClawRootPath(using: config) {
            return discoveredRoot
        }

        if let homeDirectory = queryContainerHomeDirectory(using: config) {
            let trimmed = homeDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return URL(fileURLWithPath: trimmed, isDirectory: true)
                    .appendingPathComponent(".openclaw", isDirectory: true)
                    .path
            }
        }

        let fallbackMount = config.container.workspaceMountPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fallbackMount.isEmpty else { return nil }
        return URL(fileURLWithPath: fallbackMount, isDirectory: true)
            .appendingPathComponent(".openclaw", isDirectory: true)
            .path
    }

    private func discoverContainerOpenClawRootPath(using config: OpenClawConfig) -> String? {
        guard let containerName = containerName(for: config) else { return nil }

        let workspaceMountPath = config.container.workspaceMountPath.trimmingCharacters(in: .whitespacesAndNewlines)

        var script = """
        probe_candidate() {
          candidate="$1"
          if [ -n "$candidate" ] && [ -d "$candidate" ]; then
            if [ -f "$candidate/openclaw.json" ] || [ -d "$candidate/agents" ]; then
              printf '%s' "$candidate"
              return 0
            fi
          fi
          return 1
        }

        for candidate in \
          "${OPENCLAW_ROOT:-}" \
          "${OPENCLAW_HOME:-}" \
          "${OPENCLAW_PATH:-}" \
          "${XDG_CONFIG_HOME:-$HOME/.config}/openclaw" \
          "${XDG_CONFIG_HOME:-$HOME/.config}/.openclaw" \
          "${XDG_DATA_HOME:-$HOME/.local/share}/openclaw" \
          "${XDG_DATA_HOME:-$HOME/.local/share}/.openclaw" \
          "$HOME/.openclaw" \
          "$HOME/openclaw" \
          "/root/.openclaw" \
          "/home/node/.openclaw" \
          "/home/app/.openclaw" \
          "/app/.openclaw" \
          "/workspace/.openclaw" \
          "/workspace/openclaw" \
          "/workspaces/.openclaw" \
          "/workspaces/openclaw"; do
          probe_candidate "$candidate" && exit 0
        done
        """

        if !workspaceMountPath.isEmpty {
            let workspaceCandidates = [
                URL(fileURLWithPath: workspaceMountPath, isDirectory: true)
                    .appendingPathComponent(".openclaw", isDirectory: true)
                    .path,
                URL(fileURLWithPath: workspaceMountPath, isDirectory: true)
                    .appendingPathComponent("openclaw", isDirectory: true)
                    .path
            ]

            script += "\n"
            for candidate in workspaceCandidates {
                script += "probe_candidate \(shellQuoted(candidate)) && exit 0\n"
            }
        }

        script += """

        for root in \
          "$HOME" \
          "/root" \
          "/home/node" \
          "/home/app" \
          "/app" \
          "/workspace" \
          "/workspaces" \
          "/tmp" \
          "/opt"; do
          [ -d "$root" ] || continue

          found_json="$(find "$root" -maxdepth 5 -type f -name openclaw.json 2>/dev/null | head -n 1)"
          if [ -n "$found_json" ]; then
            dirname "$found_json"
            exit 0
          fi

          found_agents="$(find "$root" -maxdepth 5 -type d -name agents 2>/dev/null | head -n 1)"
          if [ -n "$found_agents" ]; then
            dirname "$found_agents"
            exit 0
          fi
        done
        """

        let result = try? runDeploymentCommand(
            using: config,
            arguments: ["exec", containerName, "sh", "-lc", script]
        )

        guard let result, result.terminationStatus == 0 else { return nil }

        let output = String(data: result.standardOutput, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !output.isEmpty else { return nil }

        return output
    }

    private func queryContainerHomeDirectory(using config: OpenClawConfig) -> String? {
        guard let containerName = containerName(for: config) else { return nil }

        let result = try? runDeploymentCommand(
            using: config,
            arguments: ["exec", containerName, "sh", "-lc", "printf %s \"$HOME\""]
        )

        guard let result, result.terminationStatus == 0 else { return nil }

        let output = String(data: result.standardOutput, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return output.isEmpty ? nil : output
    }

    private func runDeploymentCommand(
        using config: OpenClawConfig,
        arguments: [String],
        standardInput: FileHandle? = nil
    ) throws -> (terminationStatus: Int32, standardOutput: Data, standardError: Data) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [containerEngine(for: config)] + arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = standardInput

        try process.run()
        process.waitUntilExit()

        let stdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        return (process.terminationStatus, stdout, stderr)
    }

    private func copyDeploymentContentsToLocal(
        _ localDestination: URL,
        deploymentRootPath: String,
        using config: OpenClawConfig
    ) throws -> Int {
        switch config.deploymentKind {
        case .local:
            let source = URL(fileURLWithPath: deploymentRootPath, isDirectory: true)
            return try replaceDirectoryContents(of: localDestination, withContentsOf: source)
        case .container:
            try FileManager.default.createDirectory(at: localDestination, withIntermediateDirectories: true)
            try removeDirectoryContents(at: localDestination)

            guard let containerName = containerName(for: config) else { return 0 }

            let command = "cd \(shellQuoted(deploymentRootPath)) && tar -cf - ."
            let result = try runDeploymentCommand(
                using: config,
                arguments: ["exec", containerName, "sh", "-lc", command]
            )

            guard result.terminationStatus == 0, !result.standardOutput.isEmpty else {
                return 0
            }

            let archiveURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("openclaw-snapshot-\(UUID().uuidString).tar", isDirectory: false)
            try result.standardOutput.write(to: archiveURL, options: .atomic)
            defer { try? FileManager.default.removeItem(at: archiveURL) }

            let extract = Process()
            extract.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            extract.arguments = ["tar", "-xf", archiveURL.path, "-C", localDestination.path]
            try extract.run()
            extract.waitUntilExit()

            guard extract.terminationStatus == 0 else {
                let message = String(data: result.standardError, encoding: .utf8) ?? "容器快照同步失败"
                throw NSError(domain: "OpenClawManager", code: Int(extract.terminationStatus), userInfo: [NSLocalizedDescriptionKey: message])
            }

            let contents = try? FileManager.default.contentsOfDirectory(at: localDestination, includingPropertiesForKeys: nil)
            return contents?.count ?? 0
        case .remoteServer:
            return 0
        }
    }

    private func copyLocalContentsToDeployment(
        _ localSource: URL,
        deploymentRootPath: String,
        using config: OpenClawConfig
    ) throws {
        switch config.deploymentKind {
        case .local:
            let destination = URL(fileURLWithPath: deploymentRootPath, isDirectory: true)
            _ = try replaceDirectoryContents(of: destination, withContentsOf: localSource)
        case .container:
            guard let containerName = containerName(for: config) else { return }
            guard FileManager.default.fileExists(atPath: localSource.path) else { return }

            let archiveURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("openclaw-upload-\(UUID().uuidString).tar", isDirectory: false)
            let createArchive = Process()
            createArchive.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            createArchive.arguments = ["tar", "-cf", archiveURL.path, "-C", localSource.path, "."]
            try createArchive.run()
            createArchive.waitUntilExit()

            guard createArchive.terminationStatus == 0 else {
                try? FileManager.default.removeItem(at: archiveURL)
                throw NSError(domain: "OpenClawManager", code: Int(createArchive.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "本地快照打包失败"])
            }

            defer { try? FileManager.default.removeItem(at: archiveURL) }

            let clearCommand = "mkdir -p \(shellQuoted(deploymentRootPath)) && find \(shellQuoted(deploymentRootPath)) -mindepth 1 -maxdepth 1 -exec rm -rf {} +"
            let clearResult = try runDeploymentCommand(
                using: config,
                arguments: ["exec", containerName, "sh", "-lc", clearCommand]
            )
            guard clearResult.terminationStatus == 0 else {
                let message = String(data: clearResult.standardError, encoding: .utf8) ?? "容器目录清理失败"
                throw NSError(domain: "OpenClawManager", code: Int(clearResult.terminationStatus), userInfo: [NSLocalizedDescriptionKey: message])
            }

            let input = try FileHandle(forReadingFrom: archiveURL)
            defer { input.closeFile() }

            let extractCommand = "mkdir -p \(shellQuoted(deploymentRootPath)) && tar -xf - -C \(shellQuoted(deploymentRootPath))"
            let extractResult = try runDeploymentCommand(
                using: config,
                arguments: ["exec", "-i", containerName, "sh", "-lc", extractCommand],
                standardInput: input
            )

            guard extractResult.terminationStatus == 0 else {
                let message = String(data: extractResult.standardError, encoding: .utf8) ?? "容器文件同步失败"
                throw NSError(domain: "OpenClawManager", code: Int(extractResult.terminationStatus), userInfo: [NSLocalizedDescriptionKey: message])
            }
        case .remoteServer:
            return
        }
    }

    private func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private func resolveOpenClawPath(for config: OpenClawConfig) -> String {
        if FileManager.default.fileExists(atPath: config.localBinaryPath) {
            return config.localBinaryPath
        }
        return Self.possiblePaths.first(where: { FileManager.default.fileExists(atPath: $0) }) ?? config.localBinaryPath
    }

    private static func parseAgentNames(from output: String) -> [String] {
        output
            .components(separatedBy: .newlines)
            .compactMap { line in
                guard line.hasPrefix("- ") else { return nil }
                let raw = String(line.dropFirst(2))
                return raw.components(separatedBy: " (").first?.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
    }

    private func runLocalConnectionTest(
        binaryPath: String,
        completion: @escaping (Bool, String, [String]) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard FileManager.default.fileExists(atPath: binaryPath) else {
                DispatchQueue.main.async {
                    completion(false, "未找到 OpenClaw 可执行文件：\(binaryPath)", [])
                }
                return
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: binaryPath)
            process.arguments = ["agents", "list"]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            do {
                try process.run()
                process.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                let agentNames = Self.parseAgentNames(from: output)
                let success = process.terminationStatus == 0
                let message: String

                if success {
                    message = "连接成功，发现 \(agentNames.count) 个 OpenClaw agents"
                } else {
                    let fallback = output.trimmingCharacters(in: .whitespacesAndNewlines)
                    message = fallback.isEmpty ? "OpenClaw 本地连接失败" : fallback
                }

                DispatchQueue.main.async {
                    if success {
                        self.discoveryResults = self.inspectOpenClawAgents(using: .default, fallbackAgentNames: agentNames)
                        if self.discoveryResults.isEmpty {
                            self.discoveryResults = agentNames.map {
                                ProjectOpenClawDetectedAgentRecord(
                                    id: $0,
                                    name: $0,
                                    directoryValidated: false,
                                    configValidated: false,
                                    issues: ["未发现可验证的 agent 文件，仅保留 CLI 结果。"]
                                )
                            }
                        }
                        self.agents = self.discoveryResults.map(\.name)
                    } else {
                        self.discoveryResults = []
                    }
                    completion(success, message, agentNames)
                }
            } catch {
                DispatchQueue.main.async {
                    completion(false, error.localizedDescription, [])
                }
            }
        }
    }

    private func runContainerConnectionTest(
        config: OpenClawConfig,
        completion: @escaping (Bool, String, [String]) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            let containerName = config.container.containerName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !containerName.isEmpty else {
                DispatchQueue.main.async {
                    completion(false, "请先填写容器名称", [])
                }
                return
            }

            let engine = config.container.engine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "docker"
                : config.container.engine.trimmingCharacters(in: .whitespacesAndNewlines)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [engine, "exec", containerName, "openclaw", "agents", "list"]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            do {
                try process.run()
                process.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                let agentNames = Self.parseAgentNames(from: output)
                let success = process.terminationStatus == 0
                let message: String

                if success {
                    message = "容器连接成功，发现 \(agentNames.count) 个 OpenClaw agents"
                } else {
                    let fallback = output.trimmingCharacters(in: .whitespacesAndNewlines)
                    message = fallback.isEmpty ? "OpenClaw 容器连接失败" : fallback
                }

                DispatchQueue.main.async {
                    if success {
                        self.discoveryResults = self.inspectOpenClawAgents(using: config, fallbackAgentNames: agentNames)
                        self.agents = self.discoveryResults.map(\.name)
                    } else {
                        self.discoveryResults = []
                        self.agents = []
                    }
                    completion(success, message, agentNames)
                }
            } catch {
                DispatchQueue.main.async {
                    completion(false, error.localizedDescription, [])
                }
            }
        }
    }

    private func runRemoteConnectionTest(
        config: OpenClawConfig,
        completion: @escaping (Bool, String, [String]) -> Void
    ) {
        let host = config.host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else {
            completion(false, "请先填写远程主机地址", [])
            return
        }

        _Concurrency.Task {
            do {
                let probe = try await gatewayClient.probe(using: config)
                DispatchQueue.main.async {
                    self.discoveryResults = probe.agents.map { agent in
                        ProjectOpenClawDetectedAgentRecord(
                            id: agent.id,
                            name: agent.name,
                            directoryValidated: true,
                            configValidated: true
                        )
                    }
                    self.agents = self.discoveryResults.map(\.name)
                    completion(
                        true,
                        "远程网关连接成功：\((config.useSSL ? "wss" : "ws"))://\(host):\(config.port)",
                        probe.agentNames
                    )
                }
            } catch {
                DispatchQueue.main.async {
                    self.discoveryResults = []
                    self.agents = []
                    completion(false, error.localizedDescription, [])
                }
            }
        }
    }
    
    // 备份当前OpenClaw配置
    func backup() -> Bool {
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let backupPath = backupDirectory.appendingPathComponent("backup-\(timestamp)")
        
        do {
            try FileManager.default.createDirectory(at: backupPath, withIntermediateDirectories: true)
            
            let openclawPath = NSHomeDirectory() + "/.openclaw"
            let fileManager = FileManager.default
            
            // 备份agents目录
            let agentsSrc = URL(fileURLWithPath: openclawPath).appendingPathComponent("agents")
            let agentsDst = backupPath.appendingPathComponent("agents")
            if fileManager.fileExists(atPath: agentsSrc.path) {
                try fileManager.copyItem(at: agentsSrc, to: agentsDst)
            }
            
            // 备份workspaces
            let workspacesSrc = URL(fileURLWithPath: openclawPath)
            for item in try fileManager.contentsOfDirectory(atPath: openclawPath) {
                if item.hasPrefix("workspace") {
                    let src = workspacesSrc.appendingPathComponent(item)
                    let dst = backupPath.appendingPathComponent(item)
                    try fileManager.copyItem(at: src, to: dst)
                }
            }
            
            print("Backup created at: \(backupPath)")
            return true
        } catch {
            print("Backup failed: \(error)")
            return false
        }
    }
    
    // 还原到备份
    func restore(backupPath: URL) -> Bool {
        let openclawPath = NSHomeDirectory() + "/.openclaw"
        
        do {
            let fileManager = FileManager.default
            
            // 恢复agents
            let agentsBackup = backupPath.appendingPathComponent("agents")
            let agentsDst = URL(fileURLWithPath: openclawPath).appendingPathComponent("agents")
            if fileManager.fileExists(atPath: agentsBackup.path) {
                if fileManager.fileExists(atPath: agentsDst.path) {
                    try fileManager.removeItem(at: agentsDst)
                }
                try fileManager.copyItem(at: agentsBackup, to: agentsDst)
            }
            
            // 恢复workspaces
            for item in try fileManager.contentsOfDirectory(atPath: backupPath.path) {
                if item.hasPrefix("workspace") {
                    let src = backupPath.appendingPathComponent(item)
                    let dst = URL(fileURLWithPath: openclawPath).appendingPathComponent(item)
                    if fileManager.fileExists(atPath: dst.path) {
                        try fileManager.removeItem(at: dst)
                    }
                    try fileManager.copyItem(at: src, to: dst)
                }
            }
            
            print("Restore completed from: \(backupPath)")
            return true
        } catch {
            print("Restore failed: \(error)")
            return false
        }
    }
    
    // 获取可用备份列表
    func listBackups() -> [URL] {
        guard let contents = try? FileManager.default.contentsOfDirectory(at: backupDirectory, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return []
        }
        
        return contents
            .filter { $0.hasDirectoryPath }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }
    
    // 应用配置到OpenClaw（将架构中的agents同步到OpenClaw）
    func applyConfiguration(agents: [Agent]) -> Bool {
        // 备份当前配置
        guard backup() else { return false }
        
        // 这里可以实现将架构中的agent配置同步到OpenClaw
        // 目前只是占位实现
        print("Applying configuration for \(agents.count) agents")
        return true
    }
}
