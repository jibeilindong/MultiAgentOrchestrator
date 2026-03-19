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

struct ProjectOpenClawSnapshot: Codable {
    var config: OpenClawConfig
    var isConnected: Bool
    var availableAgents: [String]
    var activeAgents: [ProjectOpenClawAgentRecord]
    var lastSyncedAt: Date

    init(
        config: OpenClawConfig = .default,
        isConnected: Bool = false,
        availableAgents: [String] = [],
        activeAgents: [ProjectOpenClawAgentRecord] = [],
        lastSyncedAt: Date = Date()
    ) {
        self.config = config
        self.isConnected = isConnected
        self.availableAgents = availableAgents
        self.activeAgents = activeAgents
        self.lastSyncedAt = lastSyncedAt
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
    var tasks: [Task]
    var messages: [Message]
    var executionResults: [ExecutionResult]
    var executionLogs: [ExecutionLogEntry]
    var workspaceIndex: [ProjectWorkspaceRecord]
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
        case tasks
        case messages
        case executionResults
        case executionLogs
        case workspaceIndex
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
        tasks = try container.decodeIfPresent([Task].self, forKey: .tasks) ?? []
        messages = try container.decodeIfPresent([Message].self, forKey: .messages) ?? []
        executionResults = try container.decodeIfPresent([ExecutionResult].self, forKey: .executionResults) ?? []
        executionLogs = try container.decodeIfPresent([ExecutionLogEntry].self, forKey: .executionLogs) ?? []
        workspaceIndex = try container.decodeIfPresent([ProjectWorkspaceRecord].self, forKey: .workspaceIndex) ?? []
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
        try container.encode(tasks, forKey: .tasks)
        try container.encode(messages, forKey: .messages)
        try container.encode(executionResults, forKey: .executionResults)
        try container.encode(executionLogs, forKey: .executionLogs)
        try container.encode(workspaceIndex, forKey: .workspaceIndex)
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
        self.tasks = []
        self.messages = []
        self.executionResults = []
        self.executionLogs = []
        self.workspaceIndex = []
        self.runtimeState = RuntimeState()
        self.createdAt = Date()
        self.updatedAt = Date()
    }
    
    // 获取两个Agent之间的权限
    func permission(from: Agent, to: Agent) -> PermissionType {
        if from.id == to.id {
            return .allow  // 自身总是允许
        }
        
        if let permission = permissions.first(where: {
            $0.fromAgentID == from.id && $0.toAgentID == to.id
        }) {
            return permission.permissionType
        }
        
        return .allow  // 默认允许
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
}
