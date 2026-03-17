//
//  Message.swift
//  MultiAgentOrchestrator
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
}
