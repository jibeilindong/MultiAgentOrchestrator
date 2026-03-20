//
//  Workflow.swift
//  Multi-Agent-Flow
//
//  Created by 陈荣泽 on 2026/3/18.
//

import Foundation
import CoreGraphics
import Combine

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
    
    init(type: NodeType) {
        self.init(id: UUID(), type: type)
    }

    init(id: UUID, type: NodeType) {
        self.id = id
        self.type = type
        self.position = .zero
        self.title = type == .start ? "Start" : ""
        self.displayColorHex = nil
        self.conditionExpression = ""
        self.loopEnabled = false
        self.maxIterations = 1
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
        self.isBidirectional = false
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

struct Workflow: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
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
}
