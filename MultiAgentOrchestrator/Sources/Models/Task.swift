//
//  Task.swift
//  MultiAgentOrchestrator
//
//  Created by 陈荣泽 on 2026/3/18.
//

import Foundation
import SwiftUI

enum TaskStatus: String, Codable, CaseIterable {
    case todo = "To Do"
    case inProgress = "In Progress"
    case done = "Done"
    case blocked = "Blocked"
    
    var color: Color {
        switch self {
        case .todo: return .gray
        case .inProgress: return .blue
        case .done: return .green
        case .blocked: return .red
        }
    }
    
    var icon: String {
        switch self {
        case .todo: return "circle"
        case .inProgress: return "arrow.triangle.2.circlepath"
        case .done: return "checkmark.circle.fill"
        case .blocked: return "exclamationmark.triangle"
        }
    }
}

enum TaskPriority: String, Codable, CaseIterable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"
    case critical = "Critical"
    
    var color: Color {
        switch self {
        case .low: return .blue
        case .medium: return .orange
        case .high: return .red
        case .critical: return .purple
        }
    }
}

struct Task: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var title: String
    var description: String
    var status: TaskStatus
    var priority: TaskPriority
    var assignedAgentID: UUID?
    var workflowNodeID: UUID?  // 关联的工作流节点
    var createdBy: UUID?       // 创建者（Agent ID）
    var createdAt: Date
    var startedAt: Date?
    var completedAt: Date?
    var estimatedDuration: TimeInterval?  // 预计耗时（秒）
    var actualDuration: TimeInterval?     // 实际耗时（秒）
    var tags: [String]
    var metadata: [String: String]  // 额外元数据
    
    init(
        title: String,
        description: String = "",
        status: TaskStatus = .todo,
        priority: TaskPriority = .medium,
        assignedAgentID: UUID? = nil,
        workflowNodeID: UUID? = nil,
        createdBy: UUID? = nil,
        tags: [String] = [],  // 添加 tags 参数
        estimatedDuration: TimeInterval? = nil  // 添加 estimatedDuration 参数
    ) {
        self.id = UUID()
        self.title = title
        self.description = description
        self.status = status
        self.priority = priority
        self.assignedAgentID = assignedAgentID
        self.workflowNodeID = workflowNodeID
        self.createdBy = createdBy
        self.createdAt = Date()
        self.tags = tags
        self.metadata = [:]
        self.estimatedDuration = estimatedDuration
    }

    // 计算属性
    var isActive: Bool {
        status == .inProgress
    }
    
    var isCompleted: Bool {
        status == .done
    }
    
    var duration: TimeInterval? {
        if let started = startedAt, let completed = completedAt {
            return completed.timeIntervalSince(started)
        }
        return nil
    }
    
    var timeSpent: TimeInterval? {
        guard let started = startedAt else { return nil }
        if let completed = completedAt {
            return completed.timeIntervalSince(started)
        }
        return Date().timeIntervalSince(started)
    }
    
    // 更新状态
    mutating func start() {
        guard status == .todo else { return }
        status = .inProgress
        startedAt = Date()
    }
    
    mutating func complete() {
        guard status == .inProgress else { return }
        status = .done
        completedAt = Date()
        actualDuration = timeSpent
    }
    
    mutating func block() {
        status = .blocked
    }
    
    mutating func reassign(to agentID: UUID?) {
        assignedAgentID = agentID
    }
}
