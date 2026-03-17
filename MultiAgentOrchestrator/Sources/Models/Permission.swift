//
//  Untitled.swift
//  MultiAgentOrchestrator
//
//  Created by 陈荣泽 on 2026/3/18.
//

import Foundation
import SwiftUI

enum PermissionType: String, Codable, CaseIterable {
    case allow = "Allow"
    case deny = "Deny"
    case requireApproval = "Require Approval"
    
    var color: Color {
        switch self {
        case .allow: return .green
        case .deny: return .red
        case .requireApproval: return .orange
        }
    }
    
    var icon: String {
        switch self {
        case .allow: return "checkmark.circle.fill"
        case .deny: return "xmark.circle.fill"
        case .requireApproval: return "exclamationmark.circle.fill"
        }
    }
    
    var description: String {
        switch self {
        case .allow: return "Messages are allowed to flow directly"
        case .deny: return "Messages are completely blocked"
        case .requireApproval: return "Messages require manual approval"
        }
    }
}

struct Permission: Codable, Identifiable, Hashable {
    let id: UUID
    var fromAgentID: UUID
    var toAgentID: UUID
    var permissionType: PermissionType
    var createdAt: Date
    var updatedAt: Date
    
    init(fromAgentID: UUID, toAgentID: UUID, permissionType: PermissionType) {
        self.id = UUID()
        self.fromAgentID = fromAgentID
        self.toAgentID = toAgentID
        self.permissionType = permissionType
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
