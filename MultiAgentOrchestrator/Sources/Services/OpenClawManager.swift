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
    
    private init() {
        // 创建备份目录
        try? FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
    }

    private static let possiblePaths = [
        "/Users/chenrongze/.local/bin/openclaw",
        "/usr/local/bin/openclaw",
        "/opt/homebrew/bin/openclaw",
        "/usr/bin/openclaw"
    ]
    
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
        status = .disconnected
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

    private func resolveOpenClawPath() -> String {
        for path in Self.possiblePaths where FileManager.default.fileExists(atPath: path) {
            return path
        }
        return Self.possiblePaths[0]
    }

    private static func parseAgentNames(from output: String) -> [String] {
        let parsed = output
            .split(separator: "\n")
            .compactMap { line -> String? in
                guard line.hasPrefix("- ") else { return nil }
                let rawName = line.dropFirst(2)
                let name = rawName.split(separator: "(", maxSplits: 1).first?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return name.isEmpty ? nil : name
            }

        return Array(NSOrderedSet(array: parsed)) as? [String] ?? parsed
    }
}
