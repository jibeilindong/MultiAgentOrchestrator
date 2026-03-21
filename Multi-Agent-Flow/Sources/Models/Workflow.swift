//
//  Workflow.swift
//  Multi-Agent-Flow
//
//  Created by 陈荣泽 on 2026/3/18.
//

import Foundation
import CoreGraphics
import Combine

enum WorkflowFallbackRoutingPolicy: String, Codable, CaseIterable, Hashable {
    case stop = "stop"
    case firstAvailable = "first_available"
    case allAvailable = "all_available"

    var displayName: String {
        switch self {
        case .stop:
            return LocalizedString.text("routing_stop_display")
        case .firstAvailable:
            return LocalizedString.text("routing_first_available_display")
        case .allAvailable:
            return LocalizedString.text("routing_all_available_display")
        }
    }

    var detail: String {
        switch self {
        case .stop:
            return LocalizedString.text("routing_stop_detail")
        case .firstAvailable:
            return LocalizedString.text("routing_first_available_detail")
        case .allAvailable:
            return LocalizedString.text("routing_all_available_detail")
        }
    }
}

enum WorkflowVerificationStatus: String, Codable, Hashable {
    case pass
    case warn
    case fail

    var displayName: String {
        switch self {
        case .pass: return "PASS"
        case .warn: return "WARN"
        case .fail: return "FAIL"
        }
    }
}

struct WorkflowLaunchTestCase: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var prompt: String
    var requiredAgentNames: [String]
    var forbiddenAgentNames: [String]
    var expectedRoutingActions: [String]
    var expectedOutputTypes: [String]
    var maxSteps: Int?
    var notes: String

    init(
        id: UUID = UUID(),
        name: String,
        prompt: String,
        requiredAgentNames: [String] = [],
        forbiddenAgentNames: [String] = [],
        expectedRoutingActions: [String] = [],
        expectedOutputTypes: [String] = [],
        maxSteps: Int? = nil,
        notes: String = ""
    ) {
        self.id = id
        self.name = name
        self.prompt = prompt
        self.requiredAgentNames = requiredAgentNames
        self.forbiddenAgentNames = forbiddenAgentNames
        self.expectedRoutingActions = expectedRoutingActions
        self.expectedOutputTypes = expectedOutputTypes
        self.maxSteps = maxSteps
        self.notes = notes
    }
}

struct WorkflowLaunchTestCaseReport: Identifiable, Codable, Hashable {
    let id: UUID
    var testCaseID: UUID
    var name: String
    var prompt: String
    var status: WorkflowVerificationStatus
    var actualStepCount: Int
    var actualAgents: [String]
    var actualRoutingActions: [String]
    var actualRoutingTargets: [String]
    var actualOutputTypes: [String]
    var notes: [String]

    init(
        id: UUID = UUID(),
        testCaseID: UUID,
        name: String,
        prompt: String,
        status: WorkflowVerificationStatus,
        actualStepCount: Int,
        actualAgents: [String],
        actualRoutingActions: [String],
        actualRoutingTargets: [String],
        actualOutputTypes: [String],
        notes: [String]
    ) {
        self.id = id
        self.testCaseID = testCaseID
        self.name = name
        self.prompt = prompt
        self.status = status
        self.actualStepCount = actualStepCount
        self.actualAgents = actualAgents
        self.actualRoutingActions = actualRoutingActions
        self.actualRoutingTargets = actualRoutingTargets
        self.actualOutputTypes = actualOutputTypes
        self.notes = notes
    }
}

struct WorkflowLaunchVerificationReport: Identifiable, Codable, Hashable {
    let id: UUID
    var workflowID: UUID
    var workflowName: String
    var workflowSignature: String
    var startedAt: Date
    var completedAt: Date?
    var status: WorkflowVerificationStatus
    var staticFindings: [String]
    var runtimeFindings: [String]
    var testCaseReports: [WorkflowLaunchTestCaseReport]

    init(
        id: UUID = UUID(),
        workflowID: UUID,
        workflowName: String,
        workflowSignature: String,
        startedAt: Date = Date(),
        completedAt: Date? = nil,
        status: WorkflowVerificationStatus = .pass,
        staticFindings: [String] = [],
        runtimeFindings: [String] = [],
        testCaseReports: [WorkflowLaunchTestCaseReport] = []
    ) {
        self.id = id
        self.workflowID = workflowID
        self.workflowName = workflowName
        self.workflowSignature = workflowSignature
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.status = status
        self.staticFindings = staticFindings
        self.runtimeFindings = runtimeFindings
        self.testCaseReports = testCaseReports
    }
}

struct WorkflowBoundary: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var rect: CGRect
    var memberNodeIDs: [UUID]
    var createdAt: Date
    var updatedAt: Date

    init(title: String = "Boundary", rect: CGRect = .zero, memberNodeIDs: [UUID] = []) {
        self.id = UUID()
        self.title = title
        self.rect = rect
        self.memberNodeIDs = memberNodeIDs
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    func contains(_ nodeID: UUID) -> Bool {
        memberNodeIDs.contains(nodeID)
    }

    func contains(point: CGPoint) -> Bool {
        rect.contains(point)
    }

    func matchesSelection(_ nodeIDs: Set<UUID>) -> Bool {
        !memberNodeIDs.isEmpty && Set(memberNodeIDs).isSubset(of: nodeIDs)
    }
}

// 子流程数据参数
struct SubflowParameter: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var type: ParameterType
    var value: String
    var isInput: Bool  // true = 输入参数, false = 输出参数
    
    enum ParameterType: String, Codable, Hashable {
        case string = "String"
        case number = "Number"
        case boolean = "Boolean"
        case array = "Array"
        case object = "Object"
    }
    
    init(name: String, type: ParameterType, value: String = "", isInput: Bool = true) {
        self.id = UUID()
        self.name = name
        self.type = type
        self.value = value
        self.isInput = isInput
    }
}

// 子流程执行记录
struct SubflowExecutionRecord: Codable, Identifiable {
    let id: UUID
    let subflowID: UUID
    let subflowName: String
    let parentNodeID: UUID
    let startedAt: Date
    var completedAt: Date?
    var inputParameters: [SubflowParameter]
    var outputParameters: [SubflowParameter]
    var status: ExecutionStatus
    var errorMessage: String?
    
    init(subflowID: UUID, subflowName: String, parentNodeID: UUID, inputParameters: [SubflowParameter]) {
        self.id = UUID()
        self.subflowID = subflowID
        self.subflowName = subflowName
        self.parentNodeID = parentNodeID
        self.startedAt = Date()
        self.inputParameters = inputParameters
        self.outputParameters = []
        self.status = .running
    }
    
    enum ExecutionStatus: String, Codable {
        case pending = "Pending"
        case running = "Running"
        case completed = "Completed"
        case failed = "Failed"
    }
}

// 子流程数据存储管理器
class SubflowDataStore: ObservableObject {
    static let shared = SubflowDataStore()
    
    @Published var executionRecords: [SubflowExecutionRecord] = []
    
    private let maxRecordsPerSubflow = 100  // 每个子流程最多保留100条记录
    
    private init() {}
    
    // 保存执行记录
    func saveRecord(_ record: SubflowExecutionRecord) {
        // 更新已有记录或添加新记录
        if let index = executionRecords.firstIndex(where: { $0.id == record.id }) {
            executionRecords[index] = record
        } else {
            executionRecords.append(record)
        }
        
        // 清理旧记录
        cleanupOldRecords()
    }
    
    // 获取子流程的执行记录
    func getRecords(for subflowID: UUID) -> [SubflowExecutionRecord] {
        return executionRecords.filter { $0.subflowID == subflowID }
    }
    
    // 获取最新执行记录
    func getLatestRecord(for subflowID: UUID) -> SubflowExecutionRecord? {
        return executionRecords
            .filter { $0.subflowID == subflowID }
            .sorted { $0.startedAt > $1.startedAt }
            .first
    }
    
    // 清理旧记录
    private func cleanupOldRecords() {
        let subflowIDs = Set(executionRecords.map { $0.subflowID })
        for subflowID in subflowIDs {
            var records = executionRecords.filter { $0.subflowID == subflowID }
            if records.count > maxRecordsPerSubflow {
                records.sort { $0.startedAt > $1.startedAt }
                let toRemove = records.suffix(from: maxRecordsPerSubflow)
                let toRemoveIDs = Set(toRemove.map { $0.id })
                executionRecords.removeAll { toRemoveIDs.contains($0.id) }
            }
        }
    }
    
    // 清空指定子流程的记录
    func clearRecords(for subflowID: UUID) {
        executionRecords.removeAll { $0.subflowID == subflowID }
    }
    
    // 清空所有记录
    func clearAllRecords() {
        executionRecords.removeAll()
    }
}

struct WorkflowNode: Identifiable, Codable, Hashable {
    let id: UUID
    var agentID: UUID?
    var type: NodeType
    var position: CGPoint
    var title: String
    var displayColorHex: String?
    var conditionExpression: String
    var loopEnabled: Bool
    var maxIterations: Int
    // 子流程相关属性
    var subflowID: UUID?  // 关联的子工作流ID
    var nestingLevel: Int = 0  // 嵌套层级（0表示顶层）
    // 子流程数据存储
    var inputParameters: [SubflowParameter] = []  // 输入参数
    var outputParameters: [SubflowParameter] = []  // 输出参数
    
    enum NodeType: String, Codable, Hashable {
        case start
        case agent

        static func decoded(from rawType: String) -> NodeType {
            switch rawType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "start", "startnode", "entry", "root":
                return .start
            case "agent", "subflow", "branch", "end":
                return .agent
            default:
                return .agent
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case agentID
        case type
        case position
        case title
        case displayColorHex
        case conditionExpression
        case loopEnabled
        case maxIterations
        case subflowID
        case nestingLevel
        case inputParameters
        case outputParameters
    }

    private struct TitleSegments {
        let functionDescription: String
        let taskDomain: String
        let sequence: Int?
    }

    private static let validTitlePattern = try! NSRegularExpression(pattern: #"^([^-]+)-([^-]+)-([1-9]\d*)$"#)
    
    init(type: NodeType) {
        self.init(id: UUID(), type: type)
    }

    init(id: UUID, type: NodeType) {
        self.id = id
        self.type = type
        self.position = .zero
        self.title = type == .start ? "开始-工作流-1" : "功能描述-任务领域-1"
        self.displayColorHex = nil
        self.conditionExpression = ""
        self.loopEnabled = false
        self.maxIterations = 1
    }

    static func isValidTitle(_ title: String) -> Bool {
        let normalized = normalizeWhitespace(normalizeDash(title))
        let range = NSRange(location: 0, length: normalized.utf16.count)
        return validTitlePattern.firstMatch(in: normalized, options: [], range: range) != nil
    }

    static func normalizedTitle(
        requestedTitle: String,
        nodeType: NodeType,
        existingNodes: [WorkflowNode],
        excludingNodeID: UUID? = nil,
        fallbackFunctionDescription: String? = nil,
        fallbackTaskDomain: String? = nil
    ) -> String {
        let fallbackTitle = normalizeWhitespace(fallbackFunctionDescription ?? "")
        let rawTitle = normalizeWhitespace(requestedTitle).isEmpty ? fallbackTitle : requestedTitle
        let parsed = parseRequestedTitle(
            rawTitle,
            nodeType: nodeType,
            fallbackFunctionDescription: fallbackFunctionDescription,
            fallbackTaskDomain: fallbackTaskDomain
        )
        let sequence = nextAvailableSequence(
            for: parsed.functionDescription,
            taskDomain: parsed.taskDomain,
            existingNodes: existingNodes,
            excludingNodeID: excludingNodeID,
            preferredSequence: parsed.sequence
        )
        return "\(parsed.functionDescription)-\(parsed.taskDomain)-\(sequence)"
    }

    private static func parseRequestedTitle(
        _ title: String,
        nodeType: NodeType,
        fallbackFunctionDescription: String?,
        fallbackTaskDomain: String?
    ) -> TitleSegments {
        let defaults = defaultTitleSegments(
            for: nodeType,
            fallbackFunctionDescription: fallbackFunctionDescription,
            fallbackTaskDomain: fallbackTaskDomain
        )
        let normalized = normalizeWhitespace(normalizeDash(title))
        let parts = normalized
            .split(separator: "-", omittingEmptySubsequences: true)
            .map { normalizeWhitespace(String($0)) }
            .filter { !$0.isEmpty }

        guard !parts.isEmpty else {
            return TitleSegments(
                functionDescription: defaults.functionDescription,
                taskDomain: defaults.taskDomain,
                sequence: nil
            )
        }

        if parts.count >= 3, let explicitSequence = Int(parts[parts.count - 1]), explicitSequence > 0 {
            let functionDescription = sanitizeTitleSegment(
                parts.dropLast(2).joined(separator: " "),
                fallback: defaults.functionDescription
            )
            let taskDomain = sanitizeTitleSegment(parts[parts.count - 2], fallback: defaults.taskDomain)
            return TitleSegments(
                functionDescription: functionDescription,
                taskDomain: taskDomain,
                sequence: explicitSequence
            )
        }

        if parts.count >= 2 {
            return TitleSegments(
                functionDescription: sanitizeTitleSegment(
                    parts.dropLast().joined(separator: " "),
                    fallback: defaults.functionDescription
                ),
                taskDomain: sanitizeTitleSegment(parts[parts.count - 1], fallback: defaults.taskDomain),
                sequence: nil
            )
        }

        return TitleSegments(
            functionDescription: sanitizeTitleSegment(parts[0], fallback: defaults.functionDescription),
            taskDomain: defaults.taskDomain,
            sequence: nil
        )
    }

    private static func parseExistingTitle(_ title: String) -> TitleSegments? {
        let normalized = normalizeWhitespace(normalizeDash(title))
        let range = NSRange(location: 0, length: normalized.utf16.count)
        guard let match = validTitlePattern.firstMatch(in: normalized, options: [], range: range),
              let functionRange = Range(match.range(at: 1), in: normalized),
              let domainRange = Range(match.range(at: 2), in: normalized),
              let sequenceRange = Range(match.range(at: 3), in: normalized),
              let sequence = Int(normalized[sequenceRange]),
              sequence > 0 else {
            return nil
        }

        return TitleSegments(
            functionDescription: sanitizeTitleSegment(String(normalized[functionRange]), fallback: ""),
            taskDomain: sanitizeTitleSegment(String(normalized[domainRange]), fallback: ""),
            sequence: sequence
        )
    }

    private static func defaultTitleSegments(
        for nodeType: NodeType,
        fallbackFunctionDescription: String?,
        fallbackTaskDomain: String?
    ) -> (functionDescription: String, taskDomain: String) {
        let defaultFunctionDescription = nodeType == .start ? "开始" : "功能描述"
        let defaultTaskDomain = nodeType == .start ? "工作流" : "任务领域"
        return (
            sanitizeTitleSegment(fallbackFunctionDescription ?? "", fallback: defaultFunctionDescription),
            sanitizeTitleSegment(fallbackTaskDomain ?? "", fallback: defaultTaskDomain)
        )
    }

    private static func nextAvailableSequence(
        for functionDescription: String,
        taskDomain: String,
        existingNodes: [WorkflowNode],
        excludingNodeID: UUID?,
        preferredSequence: Int?
    ) -> Int {
        let key = titleKey(functionDescription: functionDescription, taskDomain: taskDomain)
        var usedSequences = Set<Int>()

        for node in existingNodes {
            if let excludingNodeID, node.id == excludingNodeID {
                continue
            }
            guard let parsed = parseExistingTitle(node.title),
                  titleKey(functionDescription: parsed.functionDescription, taskDomain: parsed.taskDomain) == key,
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

    private static func titleKey(functionDescription: String, taskDomain: String) -> String {
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

    private static func sanitizeTitleSegment(_ value: String, fallback: String) -> String {
        let normalized = normalizeWhitespace(normalizeDash(value).replacingOccurrences(of: "-", with: " "))
        return normalized.isEmpty ? fallback : normalized
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        agentID = try container.decodeIfPresent(UUID.self, forKey: .agentID)
        let rawType = try container.decodeIfPresent(String.self, forKey: .type) ?? NodeType.agent.rawValue
        type = WorkflowNode.NodeType(rawValue: rawType) ?? WorkflowNode.NodeType.decoded(from: rawType)
        position = try container.decode(CGPoint.self, forKey: .position)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        displayColorHex = try container.decodeIfPresent(String.self, forKey: .displayColorHex)
        conditionExpression = try container.decodeIfPresent(String.self, forKey: .conditionExpression) ?? ""
        loopEnabled = try container.decodeIfPresent(Bool.self, forKey: .loopEnabled) ?? false
        maxIterations = max(1, try container.decodeIfPresent(Int.self, forKey: .maxIterations) ?? 1)
        subflowID = try container.decodeIfPresent(UUID.self, forKey: .subflowID)
        nestingLevel = try container.decodeIfPresent(Int.self, forKey: .nestingLevel) ?? 0
        inputParameters = try container.decodeIfPresent([SubflowParameter].self, forKey: .inputParameters) ?? []
        outputParameters = try container.decodeIfPresent([SubflowParameter].self, forKey: .outputParameters) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(agentID, forKey: .agentID)
        try container.encode(type.rawValue, forKey: .type)
        try container.encode(position, forKey: .position)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(displayColorHex, forKey: .displayColorHex)
        try container.encode(conditionExpression, forKey: .conditionExpression)
        try container.encode(loopEnabled, forKey: .loopEnabled)
        try container.encode(maxIterations, forKey: .maxIterations)
        try container.encodeIfPresent(subflowID, forKey: .subflowID)
        try container.encode(nestingLevel, forKey: .nestingLevel)
        try container.encode(inputParameters, forKey: .inputParameters)
        try container.encode(outputParameters, forKey: .outputParameters)
    }
}

struct WorkflowEdge: Identifiable, Codable, Hashable {
    let id: UUID
    var fromNodeID: UUID
    var toNodeID: UUID
    var label: String
    var displayColorHex: String?
    var conditionExpression: String
    var requiresApproval: Bool
    var isBidirectional: Bool
    // 数据传递：边上的数据映射
    var dataMapping: [String: String] = [:]  // fromKey -> toKey

    enum CodingKeys: String, CodingKey {
        case id
        case fromNodeID
        case toNodeID
        case label
        case displayColorHex
        case conditionExpression
        case requiresApproval
        case isBidirectional
        case dataMapping
    }
    
    init(from: UUID, to: UUID) {
        self.init(id: UUID(), from: from, to: to)
    }

    init(id: UUID, from: UUID, to: UUID) {
        self.id = id
        self.fromNodeID = from
        self.toNodeID = to
        self.label = ""
        self.displayColorHex = nil
        self.conditionExpression = ""
        self.requiresApproval = false
        self.isBidirectional = true
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        fromNodeID = try container.decode(UUID.self, forKey: .fromNodeID)
        toNodeID = try container.decode(UUID.self, forKey: .toNodeID)
        label = try container.decodeIfPresent(String.self, forKey: .label) ?? ""
        displayColorHex = try container.decodeIfPresent(String.self, forKey: .displayColorHex)
        conditionExpression = try container.decodeIfPresent(String.self, forKey: .conditionExpression) ?? ""
        requiresApproval = try container.decodeIfPresent(Bool.self, forKey: .requiresApproval) ?? false
        isBidirectional = try container.decodeIfPresent(Bool.self, forKey: .isBidirectional) ?? false
        dataMapping = try container.decodeIfPresent([String: String].self, forKey: .dataMapping) ?? [:]
    }

    func connects(_ nodeID: UUID) -> Bool {
        fromNodeID == nodeID || toNodeID == nodeID
    }

    func isOutgoing(from nodeID: UUID) -> Bool {
        fromNodeID == nodeID || (isBidirectional && toNodeID == nodeID)
    }

    func isIncoming(to nodeID: UUID) -> Bool {
        toNodeID == nodeID || (isBidirectional && fromNodeID == nodeID)
    }

    func reversed() -> WorkflowEdge {
        var edge = self
        swap(&edge.fromNodeID, &edge.toNodeID)
        return edge
    }
}

enum BatchConnectionCandidateStatus: Hashable {
    case new
    case duplicate
    case invalid
}

enum BatchConnectionCandidateReason: Hashable {
    case existingRelationship
    case selfConnection
    case unsupportedSource
    case unsupportedTarget
    case missingSourceNode
    case missingTargetNode
}

struct BatchConnectionCandidate: Identifiable, Hashable {
    let id: String
    let fromNodeID: UUID
    let toNodeID: UUID
    let status: BatchConnectionCandidateStatus
    let reason: BatchConnectionCandidateReason?
    let existingEdgeID: UUID?

    init(
        fromNodeID: UUID,
        toNodeID: UUID,
        status: BatchConnectionCandidateStatus,
        reason: BatchConnectionCandidateReason? = nil,
        existingEdgeID: UUID? = nil
    ) {
        self.fromNodeID = fromNodeID
        self.toNodeID = toNodeID
        self.status = status
        self.reason = reason
        self.existingEdgeID = existingEdgeID
        self.id = "\(fromNodeID.uuidString)->\(toNodeID.uuidString)-\(String(describing: status))"
    }
}

struct BatchConnectionPreview: Hashable {
    let sourceNodeIDs: [UUID]
    let targetNodeIDs: [UUID]
    let candidates: [BatchConnectionCandidate]

    var newEdges: [BatchConnectionCandidate] {
        candidates.filter { $0.status == .new }
    }

    var duplicateEdges: [BatchConnectionCandidate] {
        candidates.filter { $0.status == .duplicate }
    }

    var invalidPairs: [BatchConnectionCandidate] {
        candidates.filter { $0.status == .invalid }
    }

    var newEdgeCount: Int { newEdges.count }
    var duplicateCount: Int { duplicateEdges.count }
    var invalidCount: Int { invalidPairs.count }
    var hasActionableEdges: Bool { newEdgeCount > 0 }
}

struct BatchConnectionResult: Hashable {
    let preview: BatchConnectionPreview
    let createdEdgeIDs: [UUID]
    let createdCount: Int
    let duplicateCount: Int
    let invalidCount: Int
}

struct WorkflowNodeConnectionCounts: Hashable {
    var incoming: Int = 0
    var outgoing: Int = 0

    static let zero = WorkflowNodeConnectionCounts()
}

struct Workflow: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var fallbackRoutingPolicy: WorkflowFallbackRoutingPolicy
    var launchTestCases: [WorkflowLaunchTestCase]
    var lastLaunchVerificationReport: WorkflowLaunchVerificationReport?
    var nodes: [WorkflowNode]
    var edges: [WorkflowEdge]
    var boundaries: [WorkflowBoundary]
    var colorGroups: [CanvasColorGroup]
    var createdAt: Date
    var parentNodeID: UUID?  // 父工作流的节点ID（如果是子流程）
    // 子流程数据存储
    var inputSchema: [SubflowParameter] = []  // 输入参数定义
    var outputSchema: [SubflowParameter] = [] // 输出参数定义

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case fallbackRoutingPolicy
        case launchTestCases
        case lastLaunchVerificationReport
        case nodes
        case edges
        case boundaries
        case colorGroups
        case createdAt
        case parentNodeID
        case inputSchema
        case outputSchema
    }
    
    init(name: String) {
        self.id = UUID()
        self.name = name
        self.fallbackRoutingPolicy = .stop
        self.launchTestCases = []
        self.lastLaunchVerificationReport = nil
        self.nodes = []
        self.edges = []
        self.boundaries = []
        self.colorGroups = []
        self.createdAt = Date()
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        fallbackRoutingPolicy = try container.decodeIfPresent(WorkflowFallbackRoutingPolicy.self, forKey: .fallbackRoutingPolicy) ?? .stop
        launchTestCases = try container.decodeIfPresent([WorkflowLaunchTestCase].self, forKey: .launchTestCases) ?? []
        lastLaunchVerificationReport = try container.decodeIfPresent(WorkflowLaunchVerificationReport.self, forKey: .lastLaunchVerificationReport)
        nodes = try container.decodeIfPresent([WorkflowNode].self, forKey: .nodes) ?? []
        edges = try container.decodeIfPresent([WorkflowEdge].self, forKey: .edges) ?? []
        boundaries = try container.decodeIfPresent([WorkflowBoundary].self, forKey: .boundaries) ?? []
        colorGroups = try container.decodeIfPresent([CanvasColorGroup].self, forKey: .colorGroups) ?? []
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        parentNodeID = try container.decodeIfPresent(UUID.self, forKey: .parentNodeID)
        inputSchema = try container.decodeIfPresent([SubflowParameter].self, forKey: .inputSchema) ?? []
        outputSchema = try container.decodeIfPresent([SubflowParameter].self, forKey: .outputSchema) ?? []
    }
    
    // 获取所有子工作流
    static func getSubflows(from workflows: [Workflow], parentID: UUID) -> [Workflow] {
        return workflows.filter { $0.parentNodeID == parentID }
    }
    
    // 获取直接子节点（不含嵌套）
    var directNodes: [WorkflowNode] {
        nodes.filter { $0.nestingLevel == 0 }
    }

    func boundary(containing nodeID: UUID) -> WorkflowBoundary? {
        boundaries.first { $0.memberNodeIDs.contains(nodeID) }
    }

    func boundary(containing point: CGPoint) -> WorkflowBoundary? {
        boundaries.reversed().first { $0.contains(point: point) }
    }

    func connectionCountsByNodeID() -> [UUID: WorkflowNodeConnectionCounts] {
        var counts: [UUID: WorkflowNodeConnectionCounts] = [:]
        counts.reserveCapacity(nodes.count)

        for edge in edges {
            counts[edge.toNodeID, default: .zero].incoming += 1
            counts[edge.fromNodeID, default: .zero].outgoing += 1

            guard edge.isBidirectional else { continue }

            counts[edge.fromNodeID, default: .zero].incoming += 1
            counts[edge.toNodeID, default: .zero].outgoing += 1
        }

        return counts
    }
}
