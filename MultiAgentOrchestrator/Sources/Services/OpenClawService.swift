//
//  Untitled.swift
//  MultiAgentOrchestrator
//
//  Created by 陈荣泽 on 2026/3/18.
//

import Foundation
import Combine

enum ExecutionStatus: String, Codable {
    case idle = "Idle"
    case running = "Running"
    case completed = "Completed"
    case failed = "Failed"
    case waiting = "Waiting"
}

struct ExecutionResult: Codable, Identifiable {
    let id: UUID
    let nodeID: UUID
    let agentID: UUID
    let status: ExecutionStatus
    let output: String
    let startedAt: Date
    let completedAt: Date?
    let duration: TimeInterval?
    
    init(nodeID: UUID, agentID: UUID, status: ExecutionStatus, output: String = "") {
        self.id = UUID()
        self.nodeID = nodeID
        self.agentID = agentID
        self.status = status
        self.output = output
        self.startedAt = Date()
        self.completedAt = status == .completed ? Date() : nil
        self.duration = self.completedAt?.timeIntervalSince(self.startedAt)
    }
}

class OpenClawService: ObservableObject {
    @Published var executionResults: [ExecutionResult] = []
    @Published var isExecuting = false
    @Published var currentStep = 0
    @Published var totalSteps = 0
    
    private var cancellables = Set<AnyCancellable>()
    
    // 模拟OpenClaw执行
    func executeWorkflow(_ workflow: Workflow, agents: [Agent], completion: @escaping ([ExecutionResult]) -> Void) {
        isExecuting = true
        executionResults.removeAll()
        
        // 过滤出Agent节点
        let agentNodes = workflow.nodes.filter { $0.type == .agent }
        totalSteps = agentNodes.count
        currentStep = 0
        
        var results: [ExecutionResult] = []
        
        // 按连接顺序执行
        executeNodesSequentially(agentNodes, workflow: workflow, agents: agents) { nodeResults in
            results = nodeResults
            self.executionResults = results
            self.isExecuting = false
            completion(results)
        }
    }
    
    private func executeNodesSequentially(_ nodes: [WorkflowNode], workflow: Workflow, agents: [Agent], completion: @escaping ([ExecutionResult]) -> Void) {
        var results: [ExecutionResult] = []
        var remainingNodes = nodes
        
        func executeNext() {
            guard let node = remainingNodes.first else {
                completion(results)
                return
            }
            
            remainingNodes.removeFirst()
            currentStep += 1
            
            guard let agentID = node.agentID,
                  let agent = agents.first(where: { $0.id == agentID }) else {
                let result = ExecutionResult(
                    nodeID: node.id,
                    agentID: UUID(),  // 占位符
                    status: .failed,
                    output: "Agent not found for node"
                )
                results.append(result)
                executeNext()
                return
            }
            
            // 模拟执行节点
            simulateNodeExecution(node, agent: agent) { result in
                results.append(result)
                self.executionResults.append(result)
                executeNext()
            }
        }
        
        executeNext()
    }
    
    private func simulateNodeExecution(_ node: WorkflowNode, agent: Agent, completion: @escaping (ExecutionResult) -> Void) {
        // 模拟执行延迟
        let delay = Double.random(in: 1.0...3.0)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            // 随机决定成功或失败
            let isSuccess = Bool.random()
            let status: ExecutionStatus = isSuccess ? .completed : .failed
            
            let output = isSuccess ?
                "Agent '\(agent.name)' executed successfully.\nOutput: Processed data for node at position (\(Int(node.position.x)), \(Int(node.position.y)))" :
                "Agent '\(agent.name)' execution failed.\nError: Simulated error occurred during processing."
            
            let result = ExecutionResult(
                nodeID: node.id,
                agentID: agent.id,
                status: status,
                output: output
            )
            
            completion(result)
        }
    }
    
    // 执行单个节点
    func executeNode(_ node: WorkflowNode, agent: Agent, completion: @escaping (ExecutionResult) -> Void) {
        simulateNodeExecution(node, agent: agent, completion: completion)
    }
    
    // 获取节点的执行结果
    func resultsForNode(_ nodeID: UUID) -> [ExecutionResult] {
        executionResults.filter { $0.nodeID == nodeID }
    }
    
    // 获取Agent的执行结果
    func resultsForAgent(_ agentID: UUID) -> [ExecutionResult] {
        executionResults.filter { $0.agentID == agentID }
    }
    
    // 获取最近的结果
    var recentResults: [ExecutionResult] {
        Array(executionResults.suffix(10))
    }
    
    // 清理结果
    func clearResults() {
        executionResults.removeAll()
    }
}

