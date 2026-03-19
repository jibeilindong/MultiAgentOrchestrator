//
//  Untitled.swift
//  MultiAgentOrchestrator
//
//  Created by 陈荣泽 on 2026/3/18.
//

import Foundation
import CoreGraphics

// 运行时状态
struct RuntimeState: Codable {
    var sessionID: String
    var messageQueue: [String]
    var agentStates: [String: String]
    var lastUpdated: Date
    
    init() {
        self.sessionID = UUID().uuidString
        self.messageQueue = []
        self.agentStates = [:]
        self.lastUpdated = Date()
    }
}

struct ProjectWorkspaceRecord: Codable, Identifiable, Hashable {
    let id: UUID
    var taskID: UUID
    var workspaceRelativePath: String
    var workspaceName: String
    var createdAt: Date
    var updatedAt: Date

    init(
        taskID: UUID,
        workspaceRelativePath: String,
        workspaceName: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = taskID
        self.taskID = taskID
        self.workspaceRelativePath = workspaceRelativePath
        self.workspaceName = workspaceName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct ProjectOpenClawAgentRecord: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var status: String
    var lastReloadedAt: Date?
}

struct ProjectOpenClawDetectedAgentRecord: Codable, Identifiable, Hashable {
    let id: String
    var name: String
    var directoryPath: String?
    var configPath: String?
    var workspacePath: String?
    var statePath: String?
    var directoryValidated: Bool
    var configValidated: Bool
    var copiedToProjectPath: String?
    var copiedFileCount: Int
    var issues: [String]
    var importedAt: Date?

    init(
        id: String,
        name: String,
        directoryPath: String? = nil,
        configPath: String? = nil,
        workspacePath: String? = nil,
        statePath: String? = nil,
        directoryValidated: Bool = false,
        configValidated: Bool = false,
        copiedToProjectPath: String? = nil,
        copiedFileCount: Int = 0,
        issues: [String] = [],
        importedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.directoryPath = directoryPath
        self.configPath = configPath
        self.workspacePath = workspacePath
        self.statePath = statePath
        self.directoryValidated = directoryValidated
        self.configValidated = configValidated
        self.copiedToProjectPath = copiedToProjectPath
        self.copiedFileCount = copiedFileCount
        self.issues = issues
        self.importedAt = importedAt
    }
}

struct ProjectOpenClawSnapshot: Codable {
    var config: OpenClawConfig
    var isConnected: Bool
    var availableAgents: [String]
    var activeAgents: [ProjectOpenClawAgentRecord]
    var detectedAgents: [ProjectOpenClawDetectedAgentRecord]
    var sessionBackupPath: String?
    var sessionMirrorPath: String?
    var lastSyncedAt: Date

    enum CodingKeys: String, CodingKey {
        case config
        case isConnected
        case availableAgents
        case activeAgents
        case detectedAgents
        case sessionBackupPath
        case sessionMirrorPath
        case lastSyncedAt
    }

    init(
        config: OpenClawConfig = .default,
        isConnected: Bool = false,
        availableAgents: [String] = [],
        activeAgents: [ProjectOpenClawAgentRecord] = [],
        detectedAgents: [ProjectOpenClawDetectedAgentRecord] = [],
        sessionBackupPath: String? = nil,
        sessionMirrorPath: String? = nil,
        lastSyncedAt: Date = Date()
    ) {
        self.config = config
        self.isConnected = isConnected
        self.availableAgents = availableAgents
        self.activeAgents = activeAgents
        self.detectedAgents = detectedAgents
        self.sessionBackupPath = sessionBackupPath
        self.sessionMirrorPath = sessionMirrorPath
        self.lastSyncedAt = lastSyncedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        config = try container.decodeIfPresent(OpenClawConfig.self, forKey: .config) ?? .default
        isConnected = try container.decodeIfPresent(Bool.self, forKey: .isConnected) ?? false
        availableAgents = try container.decodeIfPresent([String].self, forKey: .availableAgents) ?? []
        activeAgents = try container.decodeIfPresent([ProjectOpenClawAgentRecord].self, forKey: .activeAgents) ?? []
        detectedAgents = try container.decodeIfPresent([ProjectOpenClawDetectedAgentRecord].self, forKey: .detectedAgents) ?? []
        sessionBackupPath = try container.decodeIfPresent(String.self, forKey: .sessionBackupPath)
        sessionMirrorPath = try container.decodeIfPresent(String.self, forKey: .sessionMirrorPath)
        lastSyncedAt = try container.decodeIfPresent(Date.self, forKey: .lastSyncedAt) ?? Date()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(config, forKey: .config)
        try container.encode(isConnected, forKey: .isConnected)
        try container.encode(availableAgents, forKey: .availableAgents)
        try container.encode(activeAgents, forKey: .activeAgents)
        try container.encode(detectedAgents, forKey: .detectedAgents)
        try container.encodeIfPresent(sessionBackupPath, forKey: .sessionBackupPath)
        try container.encodeIfPresent(sessionMirrorPath, forKey: .sessionMirrorPath)
        try container.encode(lastSyncedAt, forKey: .lastSyncedAt)
    }
}

struct ProjectTaskDataSettings: Codable {
    var workspaceRootPath: String?
    var organizationMode: String
    var lastUpdatedAt: Date

    init(
        workspaceRootPath: String? = nil,
        organizationMode: String = "project/task",
        lastUpdatedAt: Date = Date()
    ) {
        self.workspaceRootPath = workspaceRootPath
        self.organizationMode = organizationMode
        self.lastUpdatedAt = lastUpdatedAt
    }
}

struct TaskMemoryBackupRecord: Codable, Identifiable, Hashable {
    let id: UUID
    var taskID: UUID
    var workspaceRelativePath: String
    var backupLabel: String
    var lastCapturedAt: Date

    init(taskID: UUID, workspaceRelativePath: String, backupLabel: String, lastCapturedAt: Date = Date()) {
        self.id = taskID
        self.taskID = taskID
        self.workspaceRelativePath = workspaceRelativePath
        self.backupLabel = backupLabel
        self.lastCapturedAt = lastCapturedAt
    }
}

struct AgentMemoryBackupRecord: Codable, Identifiable, Hashable {
    let id: UUID
    var agentID: UUID
    var agentName: String
    var sourcePath: String?
    var lastCapturedAt: Date

    init(agentID: UUID, agentName: String, sourcePath: String? = nil, lastCapturedAt: Date = Date()) {
        self.id = agentID
        self.agentID = agentID
        self.agentName = agentName
        self.sourcePath = sourcePath
        self.lastCapturedAt = lastCapturedAt
    }
}

struct ProjectMemoryData: Codable {
    var backupOnly: Bool
    var taskExecutionMemories: [TaskMemoryBackupRecord]
    var agentMemories: [AgentMemoryBackupRecord]
    var lastBackupAt: Date?

    init(
        backupOnly: Bool = true,
        taskExecutionMemories: [TaskMemoryBackupRecord] = [],
        agentMemories: [AgentMemoryBackupRecord] = [],
        lastBackupAt: Date? = nil
    ) {
        self.backupOnly = backupOnly
        self.taskExecutionMemories = taskExecutionMemories
        self.agentMemories = agentMemories
        self.lastBackupAt = lastBackupAt
    }
}

struct MAProject: Codable, Identifiable {
    let id: UUID
    var fileVersion: String
    var name: String
    var agents: [Agent]
    var workflows: [Workflow]
    var permissions: [Permission]
    var openClaw: ProjectOpenClawSnapshot
    var taskData: ProjectTaskDataSettings
    var tasks: [Task]
    var messages: [Message]
    var executionResults: [ExecutionResult]
    var executionLogs: [ExecutionLogEntry]
    var workspaceIndex: [ProjectWorkspaceRecord]
    var memoryData: ProjectMemoryData
    var runtimeState: RuntimeState
    var createdAt: Date
    var updatedAt: Date
    
    // 显式实现 Codable
    enum CodingKeys: String, CodingKey {
        case id
        case fileVersion
        case name
        case agents
        case workflows
        case permissions
        case openClaw
        case taskData
        case tasks
        case messages
        case executionResults
        case executionLogs
        case workspaceIndex
        case memoryData
        case runtimeState
        case createdAt
        case updatedAt
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        fileVersion = try container.decodeIfPresent(String.self, forKey: .fileVersion) ?? "2.0"
        name = try container.decode(String.self, forKey: .name)
        agents = try container.decode([Agent].self, forKey: .agents)
        workflows = try container.decode([Workflow].self, forKey: .workflows)
        permissions = try container.decode([Permission].self, forKey: .permissions)
        openClaw = try container.decodeIfPresent(ProjectOpenClawSnapshot.self, forKey: .openClaw) ?? ProjectOpenClawSnapshot()
        taskData = try container.decodeIfPresent(ProjectTaskDataSettings.self, forKey: .taskData) ?? ProjectTaskDataSettings()
        tasks = try container.decodeIfPresent([Task].self, forKey: .tasks) ?? []
        messages = try container.decodeIfPresent([Message].self, forKey: .messages) ?? []
        executionResults = try container.decodeIfPresent([ExecutionResult].self, forKey: .executionResults) ?? []
        executionLogs = try container.decodeIfPresent([ExecutionLogEntry].self, forKey: .executionLogs) ?? []
        workspaceIndex = try container.decodeIfPresent([ProjectWorkspaceRecord].self, forKey: .workspaceIndex) ?? []
        memoryData = try container.decodeIfPresent(ProjectMemoryData.self, forKey: .memoryData) ?? ProjectMemoryData()
        runtimeState = (try? container.decode(RuntimeState.self, forKey: .runtimeState)) ?? RuntimeState()
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(fileVersion, forKey: .fileVersion)
        try container.encode(name, forKey: .name)
        try container.encode(agents, forKey: .agents)
        try container.encode(workflows, forKey: .workflows)
        try container.encode(permissions, forKey: .permissions)
        try container.encode(openClaw, forKey: .openClaw)
        try container.encode(taskData, forKey: .taskData)
        try container.encode(tasks, forKey: .tasks)
        try container.encode(messages, forKey: .messages)
        try container.encode(executionResults, forKey: .executionResults)
        try container.encode(executionLogs, forKey: .executionLogs)
        try container.encode(workspaceIndex, forKey: .workspaceIndex)
        try container.encode(memoryData, forKey: .memoryData)
        try container.encode(runtimeState, forKey: .runtimeState)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
    
    init(name: String) {
        self.id = UUID()
        self.fileVersion = "2.0"
        self.name = name
        self.agents = []
        self.workflows = [Workflow(name: "Main Workflow")]
        self.permissions = []
        self.openClaw = ProjectOpenClawSnapshot()
        self.taskData = ProjectTaskDataSettings()
        self.tasks = []
        self.messages = []
        self.executionResults = []
        self.executionLogs = []
        self.workspaceIndex = []
        self.memoryData = ProjectMemoryData()
        self.runtimeState = RuntimeState()
        self.createdAt = Date()
        self.updatedAt = Date()
    }
    
    // 获取两个Agent之间的权限
    func permission(from: Agent, to: Agent) -> PermissionType {
        if from.id == to.id {
            return .allow  // 自身总是允许
        }

        if isConversationAllowed(from: from.id, to: to.id) {
            return .allow
        }

        return .deny
    }
    
    // 设置权限
    mutating func setPermission(from: Agent, to: Agent, type: PermissionType) {
        if from.id == to.id {
            return  // 不设置自身权限
        }
        
        if let index = permissions.firstIndex(where: {
            $0.fromAgentID == from.id && $0.toAgentID == to.id
        }) {
            if type == .allow && permissions[index].permissionType == .allow {
                // 如果是默认值，删除权限条目
                permissions.remove(at: index)
            } else {
                permissions[index].permissionType = type
                permissions[index].updatedAt = Date()
            }
        } else if type != .allow {
            // 只存储非默认权限
            let permission = Permission(
                fromAgentID: from.id,
                toAgentID: to.id,
                permissionType: type
            )
            permissions.append(permission)
        }
    }

    mutating func removePermission(fromAgentID: UUID, toAgentID: UUID) {
        permissions.removeAll {
            $0.fromAgentID == fromAgentID && $0.toAgentID == toAgentID
        }
    }

    func isConversationAllowed(from fromAgentID: UUID, to toAgentID: UUID) -> Bool {
        guard fromAgentID != toAgentID else { return true }

        for workflow in workflows {
            guard let fromNode = workflow.nodes.first(where: { $0.agentID == fromAgentID && $0.type == .agent }),
                  let toNode = workflow.nodes.first(where: { $0.agentID == toAgentID && $0.type == .agent }) else {
                continue
            }

            if workflow.edges.contains(where: {
                $0.fromNodeID == fromNode.id && $0.toNodeID == toNode.id
            }) {
                return true
            }
        }

        return false
    }

    func fileAccessAllowed(from fromAgentID: UUID, to toAgentID: UUID) -> Bool {
        guard fromAgentID != toAgentID else { return true }

        for workflow in workflows {
            guard let fromNode = workflow.nodes.first(where: { $0.agentID == fromAgentID && $0.type == .agent }),
                  let toNode = workflow.nodes.first(where: { $0.agentID == toAgentID && $0.type == .agent }) else {
                continue
            }

            if let sourceBoundary = workflow.boundary(containing: fromNode.position) {
                return sourceBoundary.contains(point: toNode.position)
            }

            if workflow.boundary(containing: toNode.position) != nil {
                return true
            }
        }

        return true
    }
}
