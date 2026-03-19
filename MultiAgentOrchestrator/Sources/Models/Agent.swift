//
//  Agent.swift
//  MultiAgentOrchestrator
//
//  Created by 陈荣泽 on 2026/3/18.
//

import Foundation
import CoreGraphics

struct OpenClawAgentDefinition: Codable, Hashable {
    var agentIdentifier: String
    var modelIdentifier: String
    var runtimeProfile: String
    var memoryBackupPath: String?
    var environment: [String: String]

    init(
        agentIdentifier: String = "",
        modelIdentifier: String = "MiniMax-M2.5",
        runtimeProfile: String = "default",
        memoryBackupPath: String? = nil,
        environment: [String: String] = [:]
    ) {
        self.agentIdentifier = agentIdentifier
        self.modelIdentifier = modelIdentifier
        self.runtimeProfile = runtimeProfile
        self.memoryBackupPath = memoryBackupPath
        self.environment = environment
    }
}

struct Agent: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    var name: String
    var description: String
    var soulMD: String
    var position: CGPoint
    var createdAt: Date
    var updatedAt: Date
    var capabilities: [String]
    var colorHex: String?
    var openClawDefinition: OpenClawAgentDefinition

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case soulMD
        case position
        case createdAt
        case updatedAt
        case capabilities
        case colorHex
        case openClawDefinition
    }
    
    // 不需要为 CGPoint 定义 Codable，因为我们有单独的扩展文件
    
    init(name: String) {
        self.id = UUID()
        self.name = name
        self.description = ""
        self.soulMD = "# 新智能体\n这是我的配置..."
        self.position = .zero
        self.createdAt = Date()
        self.updatedAt = Date()
        self.capabilities = ["basic"]
        self.colorHex = nil
        self.openClawDefinition = OpenClawAgentDefinition(agentIdentifier: name)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        soulMD = try container.decodeIfPresent(String.self, forKey: .soulMD) ?? "# 新智能体\n这是我的配置..."
        position = try container.decodeIfPresent(CGPoint.self, forKey: .position) ?? .zero
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        capabilities = try container.decodeIfPresent([String].self, forKey: .capabilities) ?? ["basic"]
        colorHex = try container.decodeIfPresent(String.self, forKey: .colorHex)
        openClawDefinition = try container.decodeIfPresent(OpenClawAgentDefinition.self, forKey: .openClawDefinition)
            ?? OpenClawAgentDefinition(agentIdentifier: name)
    }
    
    // 自动合成 Equatable 和 Hashable
    // 因为所有属性都符合 Hashable，所以不需要手动实现
}
