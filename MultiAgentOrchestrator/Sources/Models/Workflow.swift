//
//  Workflow.swift
//  MultiAgentOrchestrator
//
//  Created by 陈荣泽 on 2026/3/18.
//

import Foundation
import CoreGraphics
import Combine
import Combine

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
    // 子流程相关属性
    var subflowID: UUID?  // 关联的子工作流ID
    var nestingLevel: Int = 0  // 嵌套层级（0表示顶层）
    // 子流程数据存储
    var inputParameters: [SubflowParameter] = []  // 输入参数
    var outputParameters: [SubflowParameter] = []  // 输出参数
    
    enum NodeType: String, Codable, Hashable {
        case agent
        case start
        case end
        case subflow  // 子流程节点
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
    // 数据传递：边上的数据映射
    var dataMapping: [String: String] = [:]  // fromKey -> toKey
    
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
    var parentNodeID: UUID?  // 父工作流的节点ID（如果是子流程）
    // 子流程数据存储
    var inputSchema: [SubflowParameter] = []  // 输入参数定义
    var outputSchema: [SubflowParameter] = [] // 输出参数定义
    
    init(name: String) {
        self.id = UUID()
        self.name = name
        self.nodes = []
        self.edges = []
        self.createdAt = Date()
    }
    
    // 获取所有子工作流
    static func getSubflows(from workflows: [Workflow], parentID: UUID) -> [Workflow] {
        return workflows.filter { $0.parentNodeID == parentID }
    }
    
    // 获取直接子节点（不含嵌套）
    var directNodes: [WorkflowNode] {
        nodes.filter { $0.nestingLevel == 0 }
    }
}
