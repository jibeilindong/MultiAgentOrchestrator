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

    private struct NameSegments {
        let functionDescription: String
        let taskDomain: String
        let sequence: Int?
    }

    private static let validNamePattern = try! NSRegularExpression(pattern: #"^([^-]+)-([^-]+)-([1-9]\d*)$"#)
    
    // 不需要为 CGPoint 定义 Codable，因为我们有单独的扩展文件
    
    init(name: String) {
        let normalizedName = Agent.normalizedName(requestedName: name, existingAgents: [])
        self.id = UUID()
        self.name = normalizedName
        self.identity = "generalist"
        self.description = ""
        self.soulMD = "# 新智能体\n这是我的配置..."
        self.position = .zero
        self.createdAt = Date()
        self.updatedAt = Date()
        self.capabilities = ["basic"]
        self.colorHex = nil
        self.openClawDefinition = OpenClawAgentDefinition(agentIdentifier: normalizedName)
    }

    static func isValidName(_ name: String) -> Bool {
        let normalized = normalizeWhitespace(normalizeDash(name))
        let range = NSRange(location: 0, length: normalized.utf16.count)
        return validNamePattern.firstMatch(in: normalized, options: [], range: range) != nil
    }

    static func normalizedName(
        requestedName: String,
        existingAgents: [Agent],
        excludingAgentID: UUID? = nil,
        fallbackFunctionDescription: String? = nil,
        fallbackTaskDomain: String? = nil
    ) -> String {
        let fallbackName = normalizeWhitespace(fallbackFunctionDescription ?? "")
        let rawName = normalizeWhitespace(requestedName).isEmpty ? fallbackName : requestedName
        let parsed = parseRequestedName(
            rawName,
            fallbackFunctionDescription: fallbackFunctionDescription,
            fallbackTaskDomain: fallbackTaskDomain
        )
        let sequence = nextAvailableSequence(
            for: parsed.functionDescription,
            taskDomain: parsed.taskDomain,
            existingAgents: existingAgents,
            excludingAgentID: excludingAgentID,
            preferredSequence: parsed.sequence
        )
        return "\(parsed.functionDescription)-\(parsed.taskDomain)-\(sequence)"
    }

    private static func parseRequestedName(
        _ name: String,
        fallbackFunctionDescription: String?,
        fallbackTaskDomain: String?
    ) -> NameSegments {
        let defaults = defaultNameSegments(
            fallbackFunctionDescription: fallbackFunctionDescription,
            fallbackTaskDomain: fallbackTaskDomain
        )
        let normalized = normalizeWhitespace(normalizeDash(name))
        let parts = normalized
            .split(separator: "-", omittingEmptySubsequences: true)
            .map { normalizeWhitespace(String($0)) }
            .filter { !$0.isEmpty }

        guard !parts.isEmpty else {
            return NameSegments(
                functionDescription: defaults.functionDescription,
                taskDomain: defaults.taskDomain,
                sequence: nil
            )
        }

        if parts.count >= 3, let explicitSequence = Int(parts[parts.count - 1]), explicitSequence > 0 {
            return NameSegments(
                functionDescription: sanitizeNameSegment(
                    parts.dropLast(2).joined(separator: " "),
                    fallback: defaults.functionDescription
                ),
                taskDomain: sanitizeNameSegment(parts[parts.count - 2], fallback: defaults.taskDomain),
                sequence: explicitSequence
            )
        }

        if parts.count >= 2 {
            return NameSegments(
                functionDescription: sanitizeNameSegment(
                    parts.dropLast().joined(separator: " "),
                    fallback: defaults.functionDescription
                ),
                taskDomain: sanitizeNameSegment(parts[parts.count - 1], fallback: defaults.taskDomain),
                sequence: nil
            )
        }

        return NameSegments(
            functionDescription: sanitizeNameSegment(parts[0], fallback: defaults.functionDescription),
            taskDomain: defaults.taskDomain,
            sequence: nil
        )
    }

    private static func parseExistingName(_ name: String) -> NameSegments? {
        let normalized = normalizeWhitespace(normalizeDash(name))
        let range = NSRange(location: 0, length: normalized.utf16.count)
        guard let match = validNamePattern.firstMatch(in: normalized, options: [], range: range),
              let functionRange = Range(match.range(at: 1), in: normalized),
              let domainRange = Range(match.range(at: 2), in: normalized),
              let sequenceRange = Range(match.range(at: 3), in: normalized),
              let sequence = Int(normalized[sequenceRange]),
              sequence > 0 else {
            return nil
        }

        return NameSegments(
            functionDescription: sanitizeNameSegment(String(normalized[functionRange]), fallback: ""),
            taskDomain: sanitizeNameSegment(String(normalized[domainRange]), fallback: ""),
            sequence: sequence
        )
    }

    private static func defaultNameSegments(
        fallbackFunctionDescription: String?,
        fallbackTaskDomain: String?
    ) -> (functionDescription: String, taskDomain: String) {
        (
            sanitizeNameSegment(fallbackFunctionDescription ?? "", fallback: "功能描述"),
            sanitizeNameSegment(fallbackTaskDomain ?? "", fallback: "任务领域")
        )
    }

    private static func nextAvailableSequence(
        for functionDescription: String,
        taskDomain: String,
        existingAgents: [Agent],
        excludingAgentID: UUID?,
        preferredSequence: Int?
    ) -> Int {
        let key = nameKey(functionDescription: functionDescription, taskDomain: taskDomain)
        var usedSequences = Set<Int>()

        for agent in existingAgents {
            if let excludingAgentID, agent.id == excludingAgentID {
                continue
            }
            guard let parsed = parseExistingName(agent.name),
                  nameKey(functionDescription: parsed.functionDescription, taskDomain: parsed.taskDomain) == key,
                  let sequence = parsed.sequence else {
                continue
            }
            usedSequences.insert(sequence)
        }

        if let preferredSequence, preferredSequence > 0, !usedSequences.contains(preferredSequence) {
            return preferredSequence
        }

        var next = 1
        while usedSequences.contains(next) {
            next += 1
        }
        return next
    }

    private static func nameKey(functionDescription: String, taskDomain: String) -> String {
        "\(functionDescription.lowercased())::\(taskDomain.lowercased())"
    }

    private static func normalizeDash(_ value: String) -> String {
        value.replacingOccurrences(of: "[－—–]+", with: "-", options: .regularExpression)
    }

    private static func normalizeWhitespace(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    private static func sanitizeNameSegment(_ value: String, fallback: String) -> String {
        let normalized = normalizeWhitespace(normalizeDash(value).replacingOccurrences(of: "-", with: " "))
        return normalized.isEmpty ? fallback : normalized
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
