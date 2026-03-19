//
//  OpenClawManager.swift
//  MultiAgentOrchestrator
//

import Foundation
import Combine

class OpenClawManager: ObservableObject {
    static let shared = OpenClawManager()
    
    @Published var isConnected: Bool = false
    @Published var agents: [String] = []
    @Published var discoveryResults: [ProjectOpenClawDetectedAgentRecord] = []
    @Published var activeAgents: [UUID: ActiveAgentRuntime] = [:]
    @Published var status: OpenClawStatus = .disconnected
    @Published var config: OpenClawConfig = .load()
    
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

    private struct SessionContext {
        let projectID: UUID
        let rootURL: URL
        let backupURL: URL
        let mirrorURL: URL
        let importedAgentsURL: URL
    }

    private var sessionContext: SessionContext?

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
        status = .connecting
        config.save()

        if let projectID, config.deploymentKind == .local {
            do {
                try beginSession(for: projectID)
            } catch {
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
            completion?(success, message)
        }
    }

    func refreshAgents(completion: @escaping ([String]) -> Void) {
        testConnection(using: config) { [weak self] success, message, agentNames in
            guard let self else { return }
            DispatchQueue.main.async {
                self.agents = success ? agentNames : []
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
                self.agents = success ? agentNames : []
                if success {
                    self.discoveryResults = self.inspectOpenClawAgents(using: config)
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
                } else {
                    self.discoveryResults = []
                }
                self.isConnected = success
                self.status = success ? .connected : .error(message)
                if !success {
                    self.activeAgents.removeAll()
                }
                completion(success, message)
            }
        }
    }

    func beginSession(for projectID: UUID) throws {
        guard config.deploymentKind == .local else { return }
        guard sessionContext == nil else { return }

        let projectRoot = ProjectManager.shared.openClawProjectRoot(for: projectID)
        let backupURL = ProjectManager.shared.openClawBackupDirectory(for: projectID)
        let mirrorURL = ProjectManager.shared.openClawMirrorDirectory(for: projectID)
        let importedAgentsURL = ProjectManager.shared.openClawImportedAgentsDirectory(for: projectID)
        let openClawRoot = localOpenClawRootURL()

        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: backupURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: mirrorURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: importedAgentsURL, withIntermediateDirectories: true)

        _ = try replaceDirectoryContents(of: backupURL, withContentsOf: openClawRoot)

        if directoryHasContent(mirrorURL) {
            _ = try replaceDirectoryContents(of: openClawRoot, withContentsOf: mirrorURL)
        } else {
            _ = try replaceDirectoryContents(of: mirrorURL, withContentsOf: openClawRoot)
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
        let openClawRoot = localOpenClawRootURL()

        do {
            try FileManager.default.createDirectory(at: context.mirrorURL, withIntermediateDirectories: true)
            _ = try replaceDirectoryContents(of: context.mirrorURL, withContentsOf: openClawRoot)

            if restoreOriginalState {
                _ = try replaceDirectoryContents(of: openClawRoot, withContentsOf: context.backupURL)
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
    func importDetectedAgents(into project: inout MAProject) -> [ProjectOpenClawDetectedAgentRecord] {
        guard config.deploymentKind == .local else { return [] }

        let importRoot = ProjectManager.shared.openClawImportedAgentsDirectory(for: project.id)
        try? FileManager.default.createDirectory(at: importRoot, withIntermediateDirectories: true)

        var importedRecords: [ProjectOpenClawDetectedAgentRecord] = []

        for record in discoveryResults {
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

    private func isLocalFileDeployment(_ config: OpenClawConfig) -> Bool {
        config.deploymentKind == .local
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

    private func inspectOpenClawAgents(using config: OpenClawConfig) -> [ProjectOpenClawDetectedAgentRecord] {
        guard isLocalFileDeployment(config) else { return [] }

        let rootURL = localOpenClawRootURL()
        let agentsDirectory = rootURL.appendingPathComponent("agents", isDirectory: true)
        let configURL = rootURL.appendingPathComponent("openclaw.json")

        let directoryInspections = inspectAgentDirectories(at: agentsDirectory)
        let configInspections = inspectAgentConfigCandidates(at: configURL)

        let directoryMap = Dictionary(uniqueKeysWithValues: directoryInspections.map { (normalizeAgentKey($0.name), $0) })
        let configMap = Dictionary(uniqueKeysWithValues: configInspections.map { (normalizeAgentKey($0.name), $0) })
        let mergedKeys = Set(directoryMap.keys).union(configMap.keys).sorted()

        return mergedKeys.map { key in
            let directory = directoryMap[key]
            let configCandidate = configMap[key]
            var issues: [String] = []
            let directoryValidated = directory != nil
            let configValidated = configCandidate != nil

            if !directoryValidated {
                issues.append("agent 目录未找到")
            } else if directory?.hasSoulFile == false {
                issues.append("缺少 SOUL.md")
            }

            if !configValidated {
                issues.append("openclaw.json 中未找到匹配项")
            }

            let name = configCandidate?.name ?? directory?.name ?? key
            let recordID = [
                name,
                directory?.path ?? "",
                configCandidate?.configPath ?? ""
            ].joined(separator: "|")

            return ProjectOpenClawDetectedAgentRecord(
                id: recordID,
                name: name,
                directoryPath: directory?.path,
                configPath: configCandidate?.configPath,
                workspacePath: configCandidate?.workspacePath ?? directory?.workspacePath,
                statePath: configCandidate?.statePath ?? directory?.statePath,
                directoryValidated: directoryValidated,
                configValidated: configValidated,
                issues: issues
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
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

    private func stringValue(_ dictionary: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = dictionary[key] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
        }
        return nil
    }

    private func normalizeAgentKey(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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
                        self.discoveryResults = self.inspectOpenClawAgents(using: .default)
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

        guard let url = URL(string: config.baseURL) else {
            completion(false, "远程地址无效：\(config.baseURL)", [])
            return
        }

        var request = URLRequest(url: url, timeoutInterval: TimeInterval(max(config.timeout, 5)))
        if !config.apiKey.isEmpty {
            request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }

        URLSession.shared.dataTask(with: request) { _, response, error in
            if let error {
                DispatchQueue.main.async {
                    completion(false, error.localizedDescription, [])
                }
                return
            }

            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            let success = (200..<400).contains(statusCode)
            let message = success
                ? "远程连接成功：\(config.baseURL)"
                : "远程连接失败，HTTP \(statusCode)"

            DispatchQueue.main.async {
                completion(success, message, [])
            }
        }.resume()
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
