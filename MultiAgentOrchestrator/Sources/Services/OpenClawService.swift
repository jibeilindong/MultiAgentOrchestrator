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

enum ExecutionOutputType: String, Codable {
    case agentFinalResponse = "agent_final_response"
    case runtimeLog = "runtime_log"
    case errorSummary = "error_summary"
    case empty = "empty"
}

struct ExecutionResult: Codable, Identifiable {
    let id: UUID
    let nodeID: UUID
    let agentID: UUID
    let status: ExecutionStatus
    let output: String
    let outputType: ExecutionOutputType
    let startedAt: Date
    let completedAt: Date?
    let duration: TimeInterval?

    enum CodingKeys: String, CodingKey {
        case id
        case nodeID
        case agentID
        case status
        case output
        case outputType
        case startedAt
        case completedAt
        case duration
    }

    init(
        nodeID: UUID,
        agentID: UUID,
        status: ExecutionStatus,
        output: String = "",
        outputType: ExecutionOutputType = .empty
    ) {
        self.id = UUID()
        self.nodeID = nodeID
        self.agentID = agentID
        self.status = status
        self.output = output
        self.outputType = outputType
        self.startedAt = Date()
        self.completedAt = status == .completed ? Date() : nil
        self.duration = self.completedAt?.timeIntervalSince(self.startedAt)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        nodeID = try container.decode(UUID.self, forKey: .nodeID)
        agentID = try container.decode(UUID.self, forKey: .agentID)
        status = try container.decode(ExecutionStatus.self, forKey: .status)
        output = try container.decodeIfPresent(String.self, forKey: .output) ?? ""
        outputType = try container.decodeIfPresent(ExecutionOutputType.self, forKey: .outputType) ?? .runtimeLog
        startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt) ?? Date()
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        duration = try container.decodeIfPresent(TimeInterval.self, forKey: .duration)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(nodeID, forKey: .nodeID)
        try container.encode(agentID, forKey: .agentID)
        try container.encode(status, forKey: .status)
        try container.encode(output, forKey: .output)
        try container.encode(outputType, forKey: .outputType)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encodeIfPresent(completedAt, forKey: .completedAt)
        try container.encodeIfPresent(duration, forKey: .duration)
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
    func executeWorkflow(
        _ workflow: Workflow,
        agents: [Agent],
        prompt: String? = nil,
        onNodeCompleted: ((ExecutionResult) -> Void)? = nil,
        completion: @escaping ([ExecutionResult]) -> Void
    ) {
        // 检查连接状态
        let managerConnected = OpenClawManager.shared.isConnected
        guard managerConnected || isConnected || agentConfig.useLocal else {
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
        executeNodesSequentially(
            agentNodes,
            workflow: workflow,
            agents: agents,
            prompt: prompt,
            onNodeCompleted: onNodeCompleted
        ) { nodeResults in
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
        let entryNodes: [WorkflowNode]
        if !startNodes.isEmpty {
            entryNodes = startNodes
        } else {
            entryNodes = workflow.nodes
                .filter { node in
                    !workflow.edges.contains(where: { $0.toNodeID == node.id })
                }
                .sorted(by: nodeSort)
        }

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
            addLog(.warning, "Some agent nodes are unreachable from the current workflow routes and were skipped.")
        }

        return routedAgents
    }
    
    private func executeNodesSequentially(
        _ nodes: [WorkflowNode],
        workflow: Workflow,
        agents: [Agent],
        prompt: String?,
        onNodeCompleted: ((ExecutionResult) -> Void)? = nil,
        completion: @escaping ([ExecutionResult]) -> Void
    ) {
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
                    output: "Agent not found for node",
                    outputType: .errorSummary
                )
                results.append(result)
                executionState?.failedNodes.append(node.id)
                addLog(.error, "Agent not found for node", nodeID: node.id)
                executeNext()
                return
            }
            
            // 调用OpenClaw执行节点
            executeNodeOnOpenClaw(node: node, agent: agent, prompt: prompt) { result in
                results.append(result)
                self.executionResults.append(result)
                onNodeCompleted?(result)
                
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
    private func executeNodeOnOpenClaw(
        node: WorkflowNode,
        agent: Agent,
        prompt: String?,
        completion: @escaping (ExecutionResult) -> Void
    ) {
        // 构建执行指令
        let instruction = buildInstruction(for: node, agent: agent, prompt: prompt)
        let targetAgentID = resolvedAgentIdentifier(for: agent)
        
        // 调用openclaw agent命令
        callOpenClawAgent(instruction: instruction, agentIdentifier: targetAgentID) { success, output, outputType in
            let status: ExecutionStatus = success ? .completed : .failed
            let result = ExecutionResult(
                nodeID: node.id,
                agentID: agent.id,
                status: status,
                output: output,
                outputType: outputType
            )
            completion(result)
        }
    }
    
    // 构建Agent指令
    private func buildInstruction(for node: WorkflowNode, agent: Agent, prompt: String?) -> String {
        var instruction = "Execute agent task:\n"
        instruction += "Agent: \(agent.name)\n"
        instruction += "Node ID: \(node.id.uuidString)\n"
        instruction += "Node Type: \(node.type.rawValue)\n"
        
        // 添加节点位置信息
        instruction += "Position: (\(Int(node.position.x)), \(Int(node.position.y)))\n"
        
        let normalizedPrompt = prompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !normalizedPrompt.isEmpty {
            instruction += "\nUser Task:\n\(normalizedPrompt)\n"
        }
        
        return instruction
    }
    
    // 调用OpenClaw Agent
    private func callOpenClawAgent(
        instruction: String,
        agentIdentifier: String,
        completion: @escaping (Bool, String, ExecutionOutputType) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let serviceConfig = self.agentConfig
            let manager = OpenClawManager.shared
            let connectionConfig = manager.config

            if connectionConfig.deploymentKind == .remoteServer {
                DispatchQueue.main.async {
                    completion(false, "当前连接模式为远程网关，工作台对话暂不支持直接执行 agent CLI。", .errorSummary)
                }
                return
            }
            
            // 构建命令
            let resolvedAgent = self.resolveRuntimeAgentIdentifier(
                preferred: agentIdentifier,
                manager: manager,
                config: connectionConfig
            )
            if let message = resolvedAgent.message {
                self.addLog(.warning, message)
            }

            var args = ["agent"]
            args.append(contentsOf: ["--agent", resolvedAgent.identifier])
            args.append(contentsOf: ["--message", instruction])
            
            let shouldUseLocal = serviceConfig.useLocal
                && !manager.isConnected
                && connectionConfig.deploymentKind == .local
            if shouldUseLocal {
                args.append("--local")
            }
            
            args.append(contentsOf: ["--timeout", String(max(1, serviceConfig.timeout))])
            args.append("--json")

            do {
                let result = try manager.executeOpenClawCLI(arguments: args, using: connectionConfig)
                let stdout = String(data: result.standardOutput, encoding: .utf8) ?? ""
                let stderr = String(data: result.standardError, encoding: .utf8) ?? ""
                let stdoutTrimmed = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                let stderrTrimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                let parsedOutput = self.extractAgentResponse(from: stdoutTrimmed)

                if !stderrTrimmed.isEmpty {
                    let level: ExecutionLogEntry.LogLevel = result.terminationStatus == 0 ? .warning : .error
                    self.addLog(level, "OpenClaw stderr (\(resolvedAgent.identifier)): \(self.truncatedLog(stderrTrimmed))")
                }

                DispatchQueue.main.async {
                    if result.terminationStatus == 0 {
                        completion(true, parsedOutput.text, parsedOutput.type)
                    } else {
                        let fallback = self.executionFailureSummary(
                            exitCode: result.terminationStatus,
                            stderr: stderrTrimmed,
                            stdout: stdoutTrimmed
                        )
                        completion(false, fallback, .errorSummary)
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    completion(false, "Error: \(error.localizedDescription)", .errorSummary)
                }
            }
        }
    }

    private func resolvedAgentIdentifier(for agent: Agent) -> String {
        let identifier = agent.openClawDefinition.agentIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        if !identifier.isEmpty {
            return identifier
        }

        let name = agent.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            return name
        }

        let configured = agentConfig.agentID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !configured.isEmpty {
            return configured
        }

        let fallback = OpenClawManager.shared.config.defaultAgent.trimmingCharacters(in: .whitespacesAndNewlines)
        return fallback.isEmpty ? "default" : fallback
    }

    private func extractAgentResponse(from stdout: String) -> (text: String, type: ExecutionOutputType) {
        let trimmed = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ("", .empty) }

        let payloads = extractJSONPayloads(from: trimmed)
        for payload in payloads.reversed() {
            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data),
                  let candidate = extractFinalResponseCandidate(from: json) else {
                continue
            }
            return (candidate, .agentFinalResponse)
        }

        if !payloads.isEmpty {
            return ("", .runtimeLog)
        }

        if looksLikeRuntimeLog(trimmed) {
            return ("", .runtimeLog)
        }

        return (trimmed, .agentFinalResponse)
    }

    private func extractFinalResponseCandidate(from json: Any) -> String? {
        if let dict = json as? [String: Any] {
            if let direct = firstNonEmptyString(in: dict, keys: ["final", "content", "message", "response", "output", "text", "answer"]) {
                return direct
            }

            if let choices = dict["choices"] as? [Any] {
                for choice in choices.reversed() {
                    if let text = extractFinalResponseCandidate(from: choice) {
                        return text
                    }
                }
            }

            if let messages = dict["messages"] as? [Any] {
                for message in messages.reversed() {
                    if let text = extractFinalResponseCandidate(from: message) {
                        return text
                    }
                }
            }

            for key in ["result", "data", "payload"] {
                if let nested = dict[key],
                   let text = extractFinalResponseCandidate(from: nested) {
                    return text
                }
            }

            return nil
        }

        if let array = json as? [Any] {
            for item in array.reversed() {
                if let text = extractFinalResponseCandidate(from: item) {
                    return text
                }
            }
            return nil
        }

        if let string = json as? String {
            return normalizedNonEmpty(string)
        }

        return nil
    }

    private func firstNonEmptyString(in dict: [String: Any], keys: [String]) -> String? {
        for key in keys {
            guard let value = dict[key] else { continue }
            if let text = textValue(from: value) {
                return text
            }
        }
        return nil
    }

    private func textValue(from value: Any) -> String? {
        if let text = value as? String {
            return normalizedNonEmpty(text)
        }

        if let dict = value as? [String: Any] {
            if let direct = firstNonEmptyString(in: dict, keys: ["content", "text", "output_text", "message", "response", "final"]) {
                return direct
            }
            return nil
        }

        if let array = value as? [Any] {
            let chunks = array.compactMap { item -> String? in
                if let text = item as? String {
                    return normalizedNonEmpty(text)
                }
                if let dict = item as? [String: Any] {
                    return firstNonEmptyString(in: dict, keys: ["text", "content", "output_text"])
                }
                return nil
            }
            let combined = chunks.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            return combined.isEmpty ? nil : combined
        }

        return nil
    }

    private func normalizedNonEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func looksLikeRuntimeLog(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        if lowercased.hasPrefix("[plugins]") || lowercased.hasPrefix("[diagnostic]") || lowercased.hasPrefix("[model-fallback/decision]") {
            return true
        }
        if lowercased.contains(" registered ") && lowercased.contains(" tool") {
            return true
        }
        if lowercased.contains("\"summarychars\"") && lowercased.contains("\"propertiescount\"") {
            return true
        }
        return false
    }

    private func executionFailureSummary(exitCode: Int32, stderr: String, stdout: String) -> String {
        let stderrLine = stderr
            .components(separatedBy: .newlines)
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            ?? ""
        if let normalized = normalizedNonEmpty(stderrLine) {
            return normalized
        }

        let stdoutLine = stdout
            .components(separatedBy: .newlines)
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            ?? ""
        if let normalized = normalizedNonEmpty(stdoutLine) {
            return normalized
        }

        return "OpenClaw agent execution failed (exit code \(exitCode))."
    }

    private func truncatedLog(_ text: String, maxLength: Int = 2000) -> String {
        guard text.count > maxLength else { return text }
        return "\(text.prefix(maxLength)) …"
    }

    private func resolveRuntimeAgentIdentifier(
        preferred: String,
        manager: OpenClawManager,
        config: OpenClawConfig
    ) -> (identifier: String, message: String?) {
        let preferredID = preferred.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !preferredID.isEmpty else {
            let fallback = preferredRuntimeAgentFallback(from: runtimeAgentIdentifiers(manager: manager, config: config))
            if let fallback {
                return (fallback, "目标 agent 未配置，已回退到 \(fallback)。")
            }
            return ("default", nil)
        }

        let available = runtimeAgentIdentifiers(manager: manager, config: config)
        guard !available.isEmpty else {
            return (preferredID, nil)
        }

        if let matched = firstCaseInsensitiveMatch(preferredID, in: available) {
            return (matched, nil)
        }

        if let defaultMatch = firstCaseInsensitiveMatch(
            config.defaultAgent.trimmingCharacters(in: .whitespacesAndNewlines),
            in: available
        ) {
            return (defaultMatch, "目标 agent \(preferredID) 在当前运行态不存在，已回退到默认 agent \(defaultMatch)。")
        }

        if let mainMatch = firstCaseInsensitiveMatch("main", in: available) {
            return (mainMatch, "目标 agent \(preferredID) 在当前运行态不存在，已回退到 \(mainMatch)。")
        }

        let first = available[0]
        return (first, "目标 agent \(preferredID) 在当前运行态不存在，已回退到 \(first)。")
    }

    private func preferredRuntimeAgentFallback(from available: [String]) -> String? {
        if let main = firstCaseInsensitiveMatch("main", in: available) {
            return main
        }
        return available.first
    }

    private func firstCaseInsensitiveMatch(_ value: String, in candidates: [String]) -> String? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }
        return candidates.first { $0.lowercased() == normalized }
    }

    private func runtimeAgentIdentifiers(manager: OpenClawManager, config: OpenClawConfig) -> [String] {
        do {
            let result = try manager.executeOpenClawCLI(arguments: ["agents", "list", "--json"], using: config)
            let stdout = String(data: result.standardOutput, encoding: .utf8) ?? ""
            let payload = extractFirstJSONPayload(from: stdout) ?? stdout

            guard let data = payload.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) else {
                return []
            }

            var identifiers: [String] = []
            if let array = object as? [[String: Any]] {
                identifiers = array.compactMap { item in
                    guard let id = item["id"] as? String else { return nil }
                    let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty ? nil : trimmed
                }
            } else if let dict = object as? [String: Any],
                      let nested = dict["agents"] as? [[String: Any]] {
                identifiers = nested.compactMap { item in
                    guard let id = item["id"] as? String else { return nil }
                    let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty ? nil : trimmed
                }
            }

            var seen = Set<String>()
            return identifiers.filter { seen.insert($0.lowercased()).inserted }
        } catch {
            return []
        }
    }

    private func extractFirstJSONPayload(from text: String) -> String? {
        extractJSONPayloads(from: text).first
    }

    private func extractJSONPayloads(from text: String) -> [String] {
        let chars = Array(text)
        var payloads: [String] = []

        for startIndex in chars.indices {
            let opening = chars[startIndex]
            guard opening == "{" || opening == "[" else { continue }

            var stack: [Character] = [opening]
            var inString = false
            var escaping = false

            for index in chars.index(after: startIndex)..<chars.endIndex {
                let char = chars[index]

                if inString {
                    if escaping {
                        escaping = false
                    } else if char == "\\" {
                        escaping = true
                    } else if char == "\"" {
                        inString = false
                    }
                    continue
                }

                if char == "\"" {
                    inString = true
                    continue
                }

                if char == "{" || char == "[" {
                    stack.append(char)
                    continue
                }

                if char == "}" || char == "]" {
                    guard let last = stack.last else { break }
                    let matched = (last == "{" && char == "}") || (last == "[" && char == "]")
                    guard matched else { break }
                    stack.removeLast()
                    if stack.isEmpty {
                        payloads.append(String(chars[startIndex...index]))
                        break
                    }
                }
            }
        }

        return payloads
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
        executeNodeOnOpenClaw(node: node, agent: agent, prompt: nil, completion: completion)
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
            addLog(.warning, "Workflow contains cycles or disconnected components. Falling back to stable node order for remaining nodes.")
            ordered.append(contentsOf: remaining)
        }

        return ordered
    }

    private func selectOutgoingEdges(for node: WorkflowNode, edges: [WorkflowEdge], workflow: Workflow) -> [WorkflowEdge] {
        guard !edges.isEmpty else { return [] }

        return edges.filter { edge in
            if edge.requiresApproval {
                addLog(.warning, "Skipping edge \(edge.id.uuidString.prefix(8)) because it requires approval.", nodeID: node.id)
                return false
            }
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
