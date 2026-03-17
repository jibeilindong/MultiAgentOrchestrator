//
//  Workflow.swift
//  MultiAgentOrchestrator
//
//  Created by 陈荣泽 on 2026/3/18.
//

import Foundation
import CoreGraphics

struct WorkflowNode: Identifiable, Codable, Hashable {
    let id: UUID
    var agentID: UUID?
    var type: NodeType
    var position: CGPoint
    
    enum NodeType: String, Codable, Hashable {
        case agent
        case start
        case end
    }
    
    init(type: NodeType) {
        self.id = UUID()
        self.type = type
        self.position = .zero
    }
}

struct WorkflowEdge: Identifiable, Codable, Hashable {
    let id: UUID
    var fromNodeID: UUID
    var toNodeID: UUID
    
    init(from: UUID, to: UUID) {
        self.id = UUID()
        self.fromNodeID = from
        self.toNodeID = to
    }
}

struct Workflow: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var nodes: [WorkflowNode]
    var edges: [WorkflowEdge]
    var createdAt: Date
    
    init(name: String) {
        self.id = UUID()
        self.name = name
        self.nodes = []
        self.edges = []
        self.createdAt = Date()
    }
}
