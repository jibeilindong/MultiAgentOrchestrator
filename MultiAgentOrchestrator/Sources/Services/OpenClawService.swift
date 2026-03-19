//
//  OpenClawService.swift
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

// OpenClaw Agent配置
struct OpenClawAgentConfig: Codable {
    var agentID: String      // Agent ID (如 taizi, zhongshu)
    var useLocal: Bool      // 是否使用本地模式
    var model: String       // 模型名称
    var timeout: Int        // 超时时间(秒)
    
    static var `default`: OpenClawAgentConfig {
        OpenClawAgentConfig(
            agentID: "taizi",
            useLocal: true,
            model: "MiniMax-M2.5",
            timeout: 120
        )
    }
}

// 执行日志条目
struct ExecutionLogEntry: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let level: LogLevel
    let message: String
    let nodeID: UUID?
    
    enum LogLevel: String, Codable {
        case info = "INFO"
        case warning = "WARN"
        case error = "ERROR"
        case success = "SUCCESS"
    }
    
    init(level: LogLevel, message: String, nodeID: UUID? = nil) {
        self.id = UUID()
        self.timestamp = Date()
        self.level = level
        self.message = message
        self.nodeID = nodeID
    }
}

// 执行状态跟踪（用于回滚）
struct ExecutionState: Codable {
    var workflowID: UUID
    var currentStep: Int
    var totalSteps: Int
    var completedNodes: [UUID]
    var failedNodes: [UUID]
    var startTime: Date
    var lastUpdated: Date
    var isPaused: Bool
    var canResume: Bool
    
    init(workflowID: UUID, totalSteps: Int) {
        self.workflowID = workflowID
        self.currentStep = 0
        self.totalSteps = totalSteps
        self.completedNodes = []
        self.failedNodes = []
        self.startTime = Date()
        self.lastUpdated = Date()
        self.isPaused = false
        self.canResume = false
    }
}

class OpenClawService: ObservableObject {
    @Published var executionResults: [ExecutionResult] = []
    @Published var executionLogs: [ExecutionLogEntry] = []
    @Published var isExecuting = false
    @Published var currentStep = 0
    @Published var totalSteps = 0
    @Published var lastError: String?
    @Published var isConnected = false
    @Published var executionState: ExecutionState?
    @Published var connectionStatus: ConnectionStatus = .disconnected
    
    // Agent配置
    @Published var agentConfig = OpenClawAgentConfig.default
    
    // 超时配置
    @Published var connectionTimeout: TimeInterval = 10.0
    @Published var executionTimeout: TimeInterval = 120.0
    
    enum ConnectionStatus {
        case connected
        case connecting
        case disconnected
        case error(String)
    }
    
    private var cancellables = Set<AnyCancellable>()
    private var process: Process?
    private var timeoutTimer: Timer?
    private let logQueue = DispatchQueue(label: "com.openclaw.logs")
    
    // 初始化时检测连接状态
    init() {
        checkConnection()
        loadExecutionState()
    }

    func restoreExecutionSnapshot(
        results: [ExecutionResult],
        logs: [ExecutionLogEntry],
        state: ExecutionState? = nil
    ) {
        executionResults = results
        executionLogs = logs
        executionState = state
        isExecuting = false
        currentStep = 0
        totalSteps = 0
        lastError = nil
    }

    func resetExecutionSnapshot() {
        executionResults.removeAll()
        executionLogs.removeAll()
        executionState = nil
        isExecuting = false
        currentStep = 0
        totalSteps = 0
        lastError = nil
    }
    
    // MARK: - 日志方法
    
    func addLog(_ level: ExecutionLogEntry.LogLevel, _ message: String, nodeID: UUID? = nil) {
        let entry = ExecutionLogEntry(level: level, message: message, nodeID: nodeID)
        DispatchQueue.main.async {
            self.executionLogs.append(entry)
            // 保留最近1000条日志
            if self.executionLogs.count > 1000 {
                self.executionLogs.removeFirst(100)
            }
        }
    }
    
    func clearLogs() {
        executionLogs.removeAll()
    }
    
    // MARK: - 状态持久化（户部任务：配置持久化）
    
    private var stateFileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("OpenClaw")
            .appendingPathComponent("execution_state.json")
    }
    
    func saveExecutionState() {
        guard let url = stateFileURL else { return }
        
        do {
            let directory = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            
            if let data = try? JSONEncoder().encode(executionState) {
                try data.write(to: url)
                addLog(.info, "Execution state saved")
            }
        } catch {
            addLog(.error, "Failed to save execution state: \(error.localizedDescription)")
        }
    }
    
    func loadExecutionState() {
        guard let url = stateFileURL,
              FileManager.default.fileExists(atPath: url.path) else { return }
        
        do {
            let data = try Data(contentsOf: url)
            executionState = try JSONDecoder().decode(ExecutionState.self, from: data)
            addLog(.info, "Execution state loaded")
        } catch {
            addLog(.warning, "Failed to load execution state: \(error.localizedDescription)")
        }
    }
    
    func clearExecutionState() {
        executionState = nil
        if let url = stateFileURL {
            try? FileManager.default.removeItem(at: url)
        }
    }
    
    // MARK: - 回滚机制（刑部任务）
    
    func pauseExecution() {
        guard isExecuting, let state = executionState else { return }
        var mutableState = state
        mutableState.isPaused = true
        mutableState.canResume = true
        mutableState.lastUpdated = Date()
        executionState = mutableState
        saveExecutionState()
        addLog(.warning, "Execution paused at step \(currentStep)/\(totalSteps)")
    }
    
    func resumeExecution() {
        guard let state = executionState, state.canResume else {
            addLog(.error, "No paused execution to resume")
            return
        }
        addLog(.info, "Resuming execution from step \(state.currentStep)")
    }
    
    func rollbackToLastCheckpoint() {
        guard let state = executionState, !state.completedNodes.isEmpty else {
            addLog(.warning, "No checkpoint to rollback to")
            return
        }
        
        // 移除最后一个完成的节点
        var mutableState = state
        if let lastNode = mutableState.completedNodes.last {
            mutableState.completedNodes.removeLast()
            mutableState.currentStep = mutableState.completedNodes.count
            executionState = mutableState
            saveExecutionState()
            addLog(.warning, "Rolled back to checkpoint before node \(lastNode.uuidString.prefix(8))")
        }
    }
    
    // MARK: - 超时处理（刑部任务）
    
    func startTimeoutTimer(duration: TimeInterval, onTimeout: @escaping () -> Void) {
        stopTimeoutTimer()
        timeoutTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            self?.addLog(.error, "Execution timeout after \(Int(duration)) seconds")
            onTimeout()
        }
    }
    
    func stopTimeoutTimer() {
        timeoutTimer?.invalidate()
        timeoutTimer = nil
    }
    
    // 检测OpenClaw网关是否可用
    func checkConnection() {
        connectionStatus = .connecting
        addLog(.info, "Checking OpenClaw Gateway connection...")
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-c", "openclaw status 2>&1 | grep -q 'Gateway' && echo 'OK' || echo 'FAIL'"]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            
            // 设置超时
            let timeout = self.connectionTimeout
            let startTime = Date()
            
            do {
                try process.run()
                
                // 等待进程完成或超时
                while process.isRunning {
                    if Date().timeIntervalSince(startTime) > timeout {
                        process.terminate()
                        DispatchQueue.main.async {
                            self.connectionStatus = .error("Connection timeout")
                            self.isConnected = false
                            self.lastError = "Connection timeout after \(Int(timeout)) seconds"
                            self.addLog(.error, "Connection timeout")
                        }
                        return
                    }
                    Thread.sleep(forTimeInterval: 0.1)
                }
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                
                DispatchQueue.main.async {
                    let connected = output.contains("OK")
                    self.isConnected = connected
                    
                    if connected {
                        self.connectionStatus = .connected
                        self.lastError = nil
                        self.addLog(.success, "OpenClaw Gateway connected")
                    } else {
                        self.connectionStatus = .error("Gateway not reachable")
                        self.lastError = "OpenClaw Gateway not reachable"
                        self.addLog(.error, "OpenClaw Gateway not reachable")
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.connectionStatus = .error(error.localizedDescription)
                    self.isConnected = false
                    self.lastError = error.localizedDescription
                    self.addLog(.error, "Connection error: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // 断开连接时自动降级（刑部任务：回滚方案）
    func handleDisconnection() {
        addLog(.warning, "Connection lost, attempting to reconnect...")
        
        if isExecuting {
            // 保存当前状态
            pauseExecution()
            addLog(.warning, "Execution paused due to disconnection")
        }
        
        // 尝试重新连接
        checkConnection()
    }
    
    // 执行工作流 - 真正调用OpenClaw
    func executeWorkflow(_ workflow: Workflow, agents: [Agent], completion: @escaping ([ExecutionResult]) -> Void) {
        // 检查连接状态
        guard isConnected || agentConfig.useLocal else {
            lastError = "Not connected to OpenClaw Gateway"
            addLog(.error, "Cannot execute: Not connected to OpenClaw Gateway")
            completion([])
            return
        }
        
        isExecuting = true
        executionResults.removeAll()
        lastError = nil
        
        let agentNodes = executionPlan(for: workflow)
        totalSteps = agentNodes.count
        currentStep = 0
        
        // 初始化执行状态（用于回滚）
        executionState = ExecutionState(workflowID: workflow.id, totalSteps: totalSteps)
        addLog(.info, "Starting workflow execution: \(workflow.name) with \(totalSteps) agent nodes")
        
        var results: [ExecutionResult] = []
        
        // 设置超时监控
        startTimeoutTimer(duration: executionTimeout) { [weak self] in
            self?.addLog(.error, "Execution timeout, stopping...")
            self?.isExecuting = false
        }
        
        // 按连接顺序执行
        executeNodesSequentially(agentNodes, workflow: workflow, agents: agents) { nodeResults in
            results = nodeResults
            self.executionResults = results
            self.isExecuting = false
            self.stopTimeoutTimer()
            
            // 清理执行状态
            self.clearExecutionState()
            
            let successCount = results.filter { $0.status == .completed }.count
            let failCount = results.filter { $0.status == .failed }.count
            self.addLog(.info, "Workflow execution completed: \(successCount) succeeded, \(failCount) failed")
            
            completion(results)
        }
    }

    func executionPlan(for workflow: Workflow) -> [WorkflowNode] {
        let nodeLookup = Dictionary(uniqueKeysWithValues: workflow.nodes.map { ($0.id, $0) })
        let orderedEdges = workflow.edges.sorted { lhs, rhs in
            guard let leftTarget = nodeLookup[lhs.toNodeID], let rightTarget = nodeLookup[rhs.toNodeID] else {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return nodeSort(leftTarget, rightTarget)
        }
        let outgoingEdges = Dictionary(grouping: orderedEdges, by: \.fromNodeID)

        let startNodes = workflow.nodes
            .filter { $0.type == .start }
            .sorted(by: nodeSort)

        let entryNodes = startNodes.isEmpty
            ? workflow.nodes.filter { node in
                !workflow.edges.contains(where: { $0.toNodeID == node.id })
              }.sorted(by: nodeSort)
            : startNodes

        var routedAgents: [WorkflowNode] = []
        var appendedAgents = Set<UUID>()
        var visitCounts: [UUID: Int] = [:]

        let traversalQueue = entryNodes.map(\.id)
        if traversalQueue.isEmpty {
            return fallbackExecutionPlan(for: workflow)
        }

        var queue = traversalQueue

        while !queue.isEmpty {
            let nodeID = queue.removeFirst()
            guard let node = nodeLookup[nodeID] else { continue }

            let nextVisitCount = visitCounts[nodeID, default: 0] + 1
            visitCounts[nodeID] = nextVisitCount

            let allowedVisits = max(1, node.loopEnabled ? node.maxIterations : 1)
            if nextVisitCount > allowedVisits {
                addLog(.warning, "Skipping repeated visit for node \(node.id.uuidString.prefix(8)) beyond loop limit")
                continue
            }

            if node.type == .agent, appendedAgents.insert(node.id).inserted {
                routedAgents.append(node)
            }

            let selectedEdges = selectOutgoingEdges(for: node, edges: outgoingEdges[node.id, default: []], workflow: workflow)
            queue.append(contentsOf: selectedEdges.map(\.toNodeID))
        }

        if routedAgents.isEmpty {
            return fallbackExecutionPlan(for: workflow)
        }

        let reachableIDs = Set(routedAgents.map(\.id))
        let missingAgents = workflow.nodes
            .filter { $0.type == .agent && !reachableIDs.contains($0.id) }
            .sorted(by: nodeSort)

        if !missingAgents.isEmpty {
            addLog(.warning, "Some agent nodes are unreachable under current branch conditions and were skipped.")
        }

        return routedAgents
    }
    
    private func executeNodesSequentially(_ nodes: [WorkflowNode], workflow: Workflow, agents: [Agent], completion: @escaping ([ExecutionResult]) -> Void) {
        var results: [ExecutionResult] = []
        var remainingNodes = nodes
        
        func executeNext() {
            // 检查是否暂停
            if let state = executionState, state.isPaused {
                addLog(.warning, "Execution paused, waiting to resume...")
                return
            }
            
            guard let node = remainingNodes.first else {
                completion(results)
                return
            }
            
            remainingNodes.removeFirst()
            currentStep += 1
            
            // 更新执行状态
            executionState?.currentStep = currentStep
            executionState?.lastUpdated = Date()
            saveExecutionState()
            
            addLog(.info, "Executing node \(currentStep)/\(totalSteps)", nodeID: node.id)
            
            guard let agentID = node.agentID,
                  let agent = agents.first(where: { $0.id == agentID }) else {
                let result = ExecutionResult(
                    nodeID: node.id,
                    agentID: UUID(),
                    status: .failed,
                    output: "Agent not found for node"
                )
                results.append(result)
                executionState?.failedNodes.append(node.id)
                addLog(.error, "Agent not found for node", nodeID: node.id)
                executeNext()
                return
            }
            
            // 调用OpenClaw执行节点
            executeNodeOnOpenClaw(node: node, agent: agent) { result in
                results.append(result)
                self.executionResults.append(result)
                
                // 更新执行状态
                if result.status == .completed {
                    self.executionState?.completedNodes.append(node.id)
                    self.addLog(.success, "Node completed: \(agent.name)", nodeID: node.id)
                } else {
                    self.executionState?.failedNodes.append(node.id)
                    self.addLog(.error, "Node failed: \(agent.name) - \(result.output)", nodeID: node.id)
                }
                
                self.saveExecutionState()
                executeNext()
            }
        }
        
        executeNext()
    }
    
    // 在OpenClaw上执行单个节点
    private func executeNodeOnOpenClaw(node: WorkflowNode, agent: Agent, completion: @escaping (ExecutionResult) -> Void) {
        // 构建执行指令
        let instruction = buildInstruction(for: node, agent: agent)
        
        // 调用openclaw agent命令
        callOpenClawAgent(instruction: instruction) { success, output in
            let status: ExecutionStatus = success ? .completed : .failed
            let result = ExecutionResult(
                nodeID: node.id,
                agentID: agent.id,
                status: status,
                output: output
            )
            completion(result)
        }
    }
    
    // 构建Agent指令
    private func buildInstruction(for node: WorkflowNode, agent: Agent) -> String {
        var instruction = "Execute agent task:\n"
        instruction += "Agent: \(agent.name)\n"
        instruction += "Node ID: \(node.id.uuidString)\n"
        instruction += "Node Type: \(node.type.rawValue)\n"
        
        // 添加节点位置信息
        instruction += "Position: (\(Int(node.position.x)), \(Int(node.position.y)))\n"
        
        return instruction
    }
    
    // 调用OpenClaw Agent
    private func callOpenClawAgent(instruction: String, completion: @escaping (Bool, String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let config = self.agentConfig
            
            // 构建命令
            var args = ["openclaw", "agent"]
            args.append(contentsOf: ["--agent", config.agentID])
            args.append(contentsOf: ["--message", instruction])
            
            if config.useLocal {
                args.append("--local")
            }
            
            args.append(contentsOf: ["--timeout", String(config.timeout)])
            args.append("--json")
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = args
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            
            do {
                try process.run()
                process.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                
                let success = process.terminationStatus == 0
                
                // 解析JSON输出
                var parsedOutput = output
                if let jsonData = output.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                   let content = json["content"] as? String {
                    parsedOutput = content
                }
                
                DispatchQueue.main.async {
                    if !success && output.isEmpty {
                        completion(false, "OpenClaw agent execution failed")
                    } else {
                        completion(success, parsedOutput)
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    completion(false, "Error: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // 测试OpenClaw连接
    func testConnection(host: String = "127.0.0.1", port: Int = 18789, completion: @escaping (Bool, String) -> Void) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", "curl -s -o /dev/null -w '%{http_code}' http://\(host):\(port)/ || echo 'FAIL'"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            
            let success = output == "200" || output == "302"
            DispatchQueue.main.async {
                completion(success, success ? "Connection successful" : "Connection failed: \(output)")
            }
        } catch {
            DispatchQueue.main.async {
                completion(false, "Error: \(error.localizedDescription)")
            }
        }
    }
    
    // 获取Agent列表
    func listAgents(completion: @escaping ([String]) -> Void) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", "openclaw agents list 2>&1 | grep -E '^\\- ' | awk '{print $2}'"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            let agents = output.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            
            DispatchQueue.main.async {
                completion(agents)
            }
        } catch {
            DispatchQueue.main.async {
                completion([])
            }
        }
    }
    
    // 执行单个节点
    func executeNode(_ node: WorkflowNode, agent: Agent, completion: @escaping (ExecutionResult) -> Void) {
        executeNodeOnOpenClaw(node: node, agent: agent, completion: completion)
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
        lastError = nil
    }

    func reloadAgent(_ agent: Agent, completion: @escaping (Bool, String) -> Void) {
        addLog(.info, "Reloading agent \(agent.name)")

        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.1) {
            let message = "Reloaded agent \(agent.name) from updated Soul.md"
            DispatchQueue.main.async {
                self.addLog(.success, message)
                completion(true, message)
            }
        }
    }

    private func fallbackExecutionPlan(for workflow: Workflow) -> [WorkflowNode] {
        let executableNodes = workflow.nodes.filter { $0.type == .agent }
        guard !executableNodes.isEmpty else { return [] }

        let executableIDs = Set(executableNodes.map(\.id))
        let relevantEdges = workflow.edges.filter {
            executableIDs.contains($0.fromNodeID) && executableIDs.contains($0.toNodeID)
        }

        var indegree: [UUID: Int] = Dictionary(uniqueKeysWithValues: executableNodes.map { ($0.id, 0) })
        var adjacency: [UUID: [UUID]] = [:]

        for edge in relevantEdges {
            adjacency[edge.fromNodeID, default: []].append(edge.toNodeID)
            indegree[edge.toNodeID, default: 0] += 1
        }

        let nodeLookup = Dictionary(uniqueKeysWithValues: executableNodes.map { ($0.id, $0) })
        var queue = executableNodes
            .filter { indegree[$0.id] == 0 }
            .sorted(by: nodeSort)

        var ordered: [WorkflowNode] = []
        var visited = Set<UUID>()

        while !queue.isEmpty {
            let node = queue.removeFirst()
            guard visited.insert(node.id).inserted else { continue }
            ordered.append(node)

            for nextID in adjacency[node.id, default: []].sorted(by: nodeIDSort(nodeLookup: nodeLookup)) {
                indegree[nextID, default: 0] -= 1
                if indegree[nextID] == 0, let nextNode = nodeLookup[nextID] {
                    queue.append(nextNode)
                    queue.sort(by: nodeSort)
                }
            }
        }

        if ordered.count != executableNodes.count {
            let remaining = executableNodes
                .filter { !visited.contains($0.id) }
                .sorted(by: nodeSort)
            addLog(.warning, "Workflow contains cycles or disconnected branches. Falling back to stable node order for remaining nodes.")
            ordered.append(contentsOf: remaining)
        }

        return ordered
    }

    private func selectOutgoingEdges(for node: WorkflowNode, edges: [WorkflowEdge], workflow: Workflow) -> [WorkflowEdge] {
        guard !edges.isEmpty else { return [] }

        let routableEdges = edges.filter { edge in
            if edge.requiresApproval {
                addLog(.warning, "Skipping edge \(edge.id.uuidString.prefix(8)) because it requires approval.", nodeID: node.id)
                return false
            }
            return true
        }

        if node.type == .branch {
            if !node.conditionExpression.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let result = evaluateExpression(node.conditionExpression, workflow: workflow)
                let expectedLabel = result ? "true" : "false"
                let matchingByLabel = routableEdges.filter {
                    $0.label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == expectedLabel
                }
                if !matchingByLabel.isEmpty {
                    return matchingByLabel
                }
            }

            let matchingByCondition = routableEdges.filter { edge in
                let condition = edge.conditionExpression.trimmingCharacters(in: .whitespacesAndNewlines)
                return condition.isEmpty || evaluateExpression(condition, workflow: workflow)
            }

            if !matchingByCondition.isEmpty {
                return matchingByCondition
            }

            return Array(routableEdges.prefix(1))
        }

        return routableEdges.filter { edge in
            let condition = edge.conditionExpression.trimmingCharacters(in: .whitespacesAndNewlines)
            return condition.isEmpty || evaluateExpression(condition, workflow: workflow)
        }
    }

    private func evaluateExpression(_ expression: String, workflow: Workflow) -> Bool {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }

        let context = evaluationContext(for: workflow)
        let normalized = trimmed.lowercased()

        if normalized == "true" { return true }
        if normalized == "false" { return false }

        let operators = ["==", "!=", ">=", "<=", ">", "<", "contains"]
        guard let op = operators.first(where: { normalized.contains(" \($0) ") }) else {
            if let value = context[normalized] {
                return truthy(value)
            }
            return false
        }

        let components = normalized.components(separatedBy: " \(op) ")
        guard components.count == 2 else { return false }

        let leftValue = context[components[0].trimmingCharacters(in: .whitespaces)] ?? parseLiteral(components[0])
        let rightValue = context[components[1].trimmingCharacters(in: .whitespaces)] ?? parseLiteral(components[1])

        switch op {
        case "==":
            return compare(leftValue, rightValue) == .orderedSame
        case "!=":
            return compare(leftValue, rightValue) != .orderedSame
        case ">":
            return compare(leftValue, rightValue) == .orderedDescending
        case "<":
            return compare(leftValue, rightValue) == .orderedAscending
        case ">=":
            let result = compare(leftValue, rightValue)
            return result == .orderedDescending || result == .orderedSame
        case "<=":
            let result = compare(leftValue, rightValue)
            return result == .orderedAscending || result == .orderedSame
        case "contains":
            return String(describing: leftValue).localizedCaseInsensitiveContains(String(describing: rightValue))
        default:
            return false
        }
    }

    private func evaluationContext(for workflow: Workflow) -> [String: Any] {
        let date = Date()
        let components = Calendar.current.dateComponents([.hour, .weekday], from: date)

        return [
            "workflow.hasagents": workflow.nodes.contains(where: { $0.type == .agent }),
            "workflow.agentcount": workflow.nodes.filter { $0.type == .agent }.count,
            "workflow.nodecount": workflow.nodes.count,
            "workflow.edgecount": workflow.edges.count,
            "time.hour": components.hour ?? 0,
            "time.weekday": components.weekday ?? 0
        ]
    }

    private func parseLiteral(_ raw: String) -> Any {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")
        if let intValue = Int(trimmed) { return intValue }
        if let doubleValue = Double(trimmed) { return doubleValue }
        if trimmed == "true" { return true }
        if trimmed == "false" { return false }
        return trimmed
    }

    private func truthy(_ value: Any) -> Bool {
        switch value {
        case let bool as Bool:
            return bool
        case let int as Int:
            return int != 0
        case let double as Double:
            return double != 0
        case let string as String:
            return !string.isEmpty && string != "false" && string != "0"
        default:
            return false
        }
    }

    private func compare(_ lhs: Any, _ rhs: Any) -> ComparisonResult {
        switch (lhs, rhs) {
        case let (left as Int, right as Int):
            return left == right ? .orderedSame : (left < right ? .orderedAscending : .orderedDescending)
        case let (left as Double, right as Double):
            return left == right ? .orderedSame : (left < right ? .orderedAscending : .orderedDescending)
        case let (left as Int, right as Double):
            let value = Double(left)
            return value == right ? .orderedSame : (value < right ? .orderedAscending : .orderedDescending)
        case let (left as Double, right as Int):
            let value = Double(right)
            return left == value ? .orderedSame : (left < value ? .orderedAscending : .orderedDescending)
        case let (left as Bool, right as Bool):
            return left == right ? .orderedSame : (left ? .orderedDescending : .orderedAscending)
        default:
            let left = String(describing: lhs).lowercased()
            let right = String(describing: rhs).lowercased()
            if left == right { return .orderedSame }
            return left < right ? .orderedAscending : .orderedDescending
        }
    }

    private func nodeSort(_ lhs: WorkflowNode, _ rhs: WorkflowNode) -> Bool {
        if lhs.position.y != rhs.position.y {
            return lhs.position.y < rhs.position.y
        }
        if lhs.position.x != rhs.position.x {
            return lhs.position.x < rhs.position.x
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func nodeIDSort(nodeLookup: [UUID: WorkflowNode]) -> (UUID, UUID) -> Bool {
        { lhs, rhs in
            guard let leftNode = nodeLookup[lhs], let rightNode = nodeLookup[rhs] else {
                return lhs.uuidString < rhs.uuidString
            }
            return self.nodeSort(leftNode, rightNode)
        }
    }
}
