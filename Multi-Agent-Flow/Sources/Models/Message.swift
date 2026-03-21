//
//  Message.swift
//  Multi-Agent-Flow
//
//  Created by 陈荣泽 on 2026/3/18.
//

import Foundation
import SwiftUI

enum MessageStatus: String, Codable, CaseIterable {
    case pending = "Pending"
    case sent = "Sent"
    case delivered = "Delivered"
    case read = "Read"
    case failed = "Failed"
    case waitingForApproval = "Waiting for Approval"
    case approved = "Approved"
    case rejected = "Rejected"
    
    var color: Color {
        switch self {
        case .pending: return .orange
        case .sent: return .blue
        case .delivered: return .blue
        case .read: return .green
        case .failed: return .red
        case .waitingForApproval: return .orange
        case .approved: return .green
        case .rejected: return .red
        }
    }
    
    var icon: String {
        switch self {
        case .pending: return "clock"
        case .sent: return "paperplane"
        case .delivered: return "checkmark"
        case .read: return "checkmark.circle"
        case .failed: return "xmark.circle"
        case .waitingForApproval: return "exclamationmark.triangle"
        case .approved: return "checkmark.shield"
        case .rejected: return "xmark.shield"
        }
    }
}

enum MessageType: String, Codable, CaseIterable {
    case text = "Text"
    case task = "Task"
    case command = "Command"
    case data = "Data"
    case notification = "Notification"
    
    var icon: String {
        switch self {
        case .text: return "text.bubble"
        case .task: return "checklist"
        case .command: return "terminal"
        case .data: return "doc.text"
        case .notification: return "bell"
        }
    }
}

struct Message: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    let fromAgentID: UUID
    let toAgentID: UUID
    var type: MessageType
    var content: String
    var timestamp: Date
    var status: MessageStatus
    var metadata: [String: String]
    var runtimeEvent: OpenClawRuntimeEvent?
    var requiresApproval: Bool
    var approvedBy: UUID?
    var approvalTimestamp: Date?
    
    init(from: UUID, to: UUID, type: MessageType, content: String, requiresApproval: Bool = false) {
        self.id = UUID()
        self.fromAgentID = from
        self.toAgentID = to
        self.type = type
        self.content = content
        self.timestamp = Date()
        self.status = requiresApproval ? .waitingForApproval : .pending
        self.metadata = [:]
        self.runtimeEvent = nil
        self.requiresApproval = requiresApproval
    }
    
    // 静态示例
    static var sample: Message {
        Message(
            from: UUID(),
            to: UUID(),
            type: MessageType.text,  // 明确指定类型
            content: "Hello, this is a sample message."
        )
    }

    nonisolated var inferredRole: String? {
        switch runtimeEvent?.eventType {
        case .taskDispatch:
            return runtimeEvent?.source.kind == .user ? "user" : "assistant"
        case .taskAccepted, .taskProgress, .taskResult, .taskRoute, .taskError, .taskApprovalRequired, .taskApproved, .sessionSync:
            return "assistant"
        case nil:
            break
        }

        if let role = metadata["role"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !role.isEmpty {
            return role
        }

        return nil
    }

    nonisolated var inferredKind: String? {
        switch runtimeEvent?.eventType {
        case .taskDispatch:
            return "input"
        case .taskAccepted, .taskProgress, .sessionSync:
            return "system"
        case .taskResult, .taskRoute, .taskError, .taskApprovalRequired, .taskApproved:
            return "output"
        case nil:
            break
        }

        if let kind = metadata["kind"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !kind.isEmpty {
            return kind
        }

        return nil
    }

    nonisolated var inferredAgentName: String? {
        if let runtimeAgentName = runtimeEvent?.source.agentName ?? runtimeEvent?.target.agentName,
           !runtimeAgentName.isEmpty {
            return runtimeAgentName
        }

        if let agentName = metadata["agentName"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !agentName.isEmpty {
            return agentName
        }
        return nil
    }

    nonisolated var inferredOutputType: String? {
        if let runtimeOutputType = runtimeEvent?.payload["outputType"],
           !runtimeOutputType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return runtimeOutputType
        }

        if let outputType = metadata["outputType"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !outputType.isEmpty {
            return outputType
        }
        return nil
    }

    nonisolated var summaryText: String {
        if let summary = runtimeEvent?.payload["summary"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !summary.isEmpty {
            return summary
        }
        return content
    }
}
