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
    func connect() {
        status = .connecting
        config.save()
        refreshAgents { _ in }
    }

    func refreshAgents(completion: @escaping ([String]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: self.resolveOpenClawPath())
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

                DispatchQueue.main.async {
                    self.agents = agentNames
                    self.isConnected = process.terminationStatus == 0
                    self.status = process.terminationStatus == 0 ? .connected : .error(output.trimmingCharacters(in: .whitespacesAndNewlines))
                    completion(agentNames)
                }
            } catch {
                DispatchQueue.main.async {
                    self.isConnected = false
                    self.status = .error(error.localizedDescription)
                    completion([])
                }
            }
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

    private func resolveOpenClawPath() -> String {
        Self.possiblePaths.first(where: { FileManager.default.fileExists(atPath: $0) }) ?? "/Users/chenrongze/.local/bin/openclaw"
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
