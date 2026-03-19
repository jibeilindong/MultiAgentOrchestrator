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
        status = .connecting
        config.save()
        confirmConnection(using: config) { success, message in
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
                self.isConnected = success
                self.status = success ? .connected : .error(message)
                if !success {
                    self.activeAgents.removeAll()
                }
                completion(success, message)
            }
        }
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
        isConnected = false
        agents = []
        activeAgents.removeAll()
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
            lastSyncedAt: Date()
        )
    }

    func restore(from snapshot: ProjectOpenClawSnapshot) {
        config = snapshot.config
        config.save()
        agents = snapshot.availableAgents
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

        if snapshot.config.autoConnect {
            connect()
        } else {
            isConnected = false
            status = .disconnected
        }
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
