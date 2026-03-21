//
//  Agent.swift
//  Multi-Agent-Flow
//
//  Created by 陈荣泽 on 2026/3/18.
//

import Foundation
import CoreGraphics

struct OpenClawProtocolCorrectionRecord: Codable, Hashable, Identifiable {
    var id: String
    var kind: String
    var message: String
    var count: Int
    var lastSeenAt: Date

    init(
        id: String = UUID().uuidString,
        kind: String,
        message: String,
        count: Int = 1,
        lastSeenAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.message = message
        self.count = count
        self.lastSeenAt = lastSeenAt
    }
}

struct OpenClawAgentProtocolMemory: Codable, Hashable {
    var protocolVersion: String
    var stableRules: [String]
    var recentCorrections: [OpenClawProtocolCorrectionRecord]
    var repeatOffenses: [OpenClawProtocolCorrectionRecord]
    var lastSessionDigest: String?
    var lastUpdatedAt: Date

    init(
        protocolVersion: String = "openclaw.runtime.v1",
        stableRules: [String] = [
            "Machine-readable workflow coordination must use the runtime protocol.",
            "Always end with exactly one valid routing JSON line when a machine tail is required.",
            "Only choose downstream targets from the allowed candidate list.",
            "Do not exceed the provided write scope, tool scope, or approval rules.",
            "If uncertain, emit the smallest valid safe result instead of guessing."
        ],
        recentCorrections: [OpenClawProtocolCorrectionRecord] = [],
        repeatOffenses: [OpenClawProtocolCorrectionRecord] = [],
        lastSessionDigest: String? = nil,
        lastUpdatedAt: Date = Date()
    ) {
        self.protocolVersion = protocolVersion
        self.stableRules = stableRules
        self.recentCorrections = recentCorrections
        self.repeatOffenses = repeatOffenses
        self.lastSessionDigest = lastSessionDigest
        self.lastUpdatedAt = lastUpdatedAt
    }
}

struct OpenClawAgentDefinition: Codable, Hashable {
    var agentIdentifier: String
    var modelIdentifier: String
    var runtimeProfile: String
    var memoryBackupPath: String?
    var soulSourcePath: String?
    var lastImportedSoulHash: String?
    var lastImportedSoulPath: String?
    var lastImportedAt: Date?
    var environment: [String: String]
    var protocolMemory: OpenClawAgentProtocolMemory

    init(
        agentIdentifier: String = "",
        modelIdentifier: String = "MiniMax-M2.5",
        runtimeProfile: String = "default",
        memoryBackupPath: String? = nil,
        soulSourcePath: String? = nil,
        lastImportedSoulHash: String? = nil,
        lastImportedSoulPath: String? = nil,
        lastImportedAt: Date? = nil,
        environment: [String: String] = [:],
        protocolMemory: OpenClawAgentProtocolMemory = OpenClawAgentProtocolMemory()
    ) {
        self.agentIdentifier = agentIdentifier
        self.modelIdentifier = modelIdentifier
        self.runtimeProfile = runtimeProfile
        self.memoryBackupPath = memoryBackupPath
        self.soulSourcePath = soulSourcePath
        self.lastImportedSoulHash = lastImportedSoulHash
        self.lastImportedSoulPath = lastImportedSoulPath
        self.lastImportedAt = lastImportedAt
        self.environment = environment
        self.protocolMemory = protocolMemory
    }
}

struct Agent: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    var name: String
    var identity: String
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
        case identity
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
        self.identity = "generalist"
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
        identity = try container.decodeIfPresent(String.self, forKey: .identity) ?? "generalist"
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
