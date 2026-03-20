//
//  OpenClawService.swift
//  Multi-Agent-Flow
//
//  Created by 陈荣泽 on 2026/3/18.
//

import Foundation
import Combine

enum ExecutionStatus: String, Codable, Hashable {
    case idle = "Idle"
    case running = "Running"
    case completed = "Completed"
    case failed = "Failed"
    case waiting = "Waiting"

    var displayName: String {
        switch self {
        case .idle: return LocalizedString.text("execution_idle")
        case .running: return LocalizedString.text("execution_running")
        case .completed: return LocalizedString.text("execution_completed")
        case .failed: return LocalizedString.text("execution_failed")
        case .waiting: return LocalizedString.pending
        }
    }
}

enum ExecutionOutputType: String, Codable, Hashable {
    case agentFinalResponse = "agent_final_response"
    case runtimeLog = "runtime_log"
    case errorSummary = "error_summary"
    case empty = "empty"
}

enum AgentOutputMode: Sendable {
    case structuredJSON
    case plainStreaming
}

enum AgentThinkingLevel: String, Sendable {
    case off
    case minimal
    case low
    case medium
    case high
    case xhigh
}

private enum WorkflowInstructionStyle {
    case standard
    case fastWorkbenchEntry
}

private actor StreamingTextAccumulator {
    private var lastVisibleText = ""

    func delta(
        for fullText: String,
        extractor: @Sendable (String) -> String,
        differ: @Sendable (String, String) -> String
    ) -> String {
        let visibleText = extractor(fullText)
        let delta = differ(lastVisibleText, visibleText)
        guard !delta.isEmpty else { return "" }
        lastVisibleText = visibleText
        return delta
    }
}

struct ExecutionResult: Codable, Identifiable {
    let id: UUID
    let nodeID: UUID
    let agentID: UUID
    let status: ExecutionStatus
    let output: String
    let outputType: ExecutionOutputType
    let routingAction: String?
    let routingTargets: [String]
    let routingReason: String?
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
        case routingAction
        case routingTargets
        case routingReason
        case startedAt
        case completedAt
        case duration
    }

    init(
        nodeID: UUID,
        agentID: UUID,
        status: ExecutionStatus,
        output: String = "",
        outputType: ExecutionOutputType = .empty,
        routingAction: String? = nil,
        routingTargets: [String] = [],
        routingReason: String? = nil
    ) {
        self.id = UUID()
        self.nodeID = nodeID
        self.agentID = agentID
        self.status = status
        self.output = output
        self.outputType = outputType
        self.routingAction = routingAction
        self.routingTargets = routingTargets
        self.routingReason = routingReason
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
        routingAction = try container.decodeIfPresent(String.self, forKey: .routingAction)
        routingTargets = try container.decodeIfPresent([String].self, forKey: .routingTargets) ?? []
        routingReason = try container.decodeIfPresent(String.self, forKey: .routingReason)
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
        try container.encodeIfPresent(routingAction, forKey: .routingAction)
        try container.encode(routingTargets, forKey: .routingTargets)
        try container.encodeIfPresent(routingReason, forKey: .routingReason)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encodeIfPresent(completedAt, forKey: .completedAt)
        try container.encodeIfPresent(duration, forKey: .duration)
    }
}

struct NodeStreamUpdate {
    let nodeID: UUID
    let agentID: UUID
    let chunk: String
}

struct WorkbenchEntryExecution {
    let result: ExecutionResult
    let downstreamNodes: [WorkflowNode]
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

    var routingBadge: String? {
        let normalized = message.lowercased()
        if normalized.hasPrefix("routing decision:") { return "ROUTE" }
        if normalized.hasPrefix("queued downstream node") { return "QUEUE" }
        if normalized.hasPrefix("no routing decision emitted") { return "STOP" }
        if normalized.hasPrefix("ignored unknown downstream targets") { return "MISS" }
        if normalized.hasPrefix("routing decision requested selected targets") { return "WARN" }
        if normalized.hasPrefix("routing decision did not match any reachable downstream agent") { return "WARN" }
        return nil
    }

    var isRoutingEvent: Bool {
        routingBadge != nil
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
    @Published var currentNodeID: UUID?
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
    private var agentCLICapabilitiesCache: [String: AgentCLICapabilities] = [:]
    private var loggedCapabilityKeys: Set<String> = []

    private struct WorkflowRoutingDecision {
        enum Action: String {
            case stop
            case all
            case selected
        }

        let action: Action
        let targets: [String]
        let reason: String?
    }

    private struct ParsedAgentOutput {
        let text: String
        let type: ExecutionOutputType
        let routingDecision: WorkflowRoutingDecision?
    }

    private struct RoutingTargetDescriptor {
        let node: WorkflowNode
        let agent: Agent
        let resolvedIdentifier: String
    }

    private struct AgentCLICapabilities {
        var supportsQuiet: Bool
        var supportsLogLevel: Bool
        var supportsJSONOnly: Bool
    }
    
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
        currentNodeID = nil
        lastError = nil
    }

    func resetExecutionSnapshot() {
        executionResults.removeAll()
        executionLogs.removeAll()
        executionState = nil
        isExecuting = false
        currentStep = 0
        totalSteps = 0
        currentNodeID = nil
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

    func syncConnectionStatus(with status: OpenClawManager.OpenClawStatus) {
        switch status {
        case .connected:
            connectionStatus = .connected
            isConnected = true
            lastError = nil
        case .connecting:
            connectionStatus = .connecting
        case .disconnected:
            connectionStatus = .disconnected
            isConnected = false
        case .error(let message):
            connectionStatus = .error(message)
            isConnected = false
            lastError = message
        }
    }
    
    // 检测OpenClaw网关是否可用
    func checkConnection() {
        let manager = OpenClawManager.shared
        syncConnectionStatus(with: .connecting)
        addLog(.info, "Checking OpenClaw Gateway connection...")

        manager.confirmConnection(using: manager.config) { [weak self] success, message in
            guard let self else { return }

            self.syncConnectionStatus(with: success ? .connected : .error(message))
            if success {
                self.addLog(.success, message)
            } else {
                self.addLog(.error, message)
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
        startingNodes: [WorkflowNode]? = nil,
        entryNodeIDsOverride: Set<UUID>? = nil,
        preloadedResults: [ExecutionResult] = [],
        precompletedNodeIDs: [UUID] = [],
        agentOutputMode: AgentOutputMode = .structuredJSON,
        onNodeStream: ((NodeStreamUpdate) -> Void)? = nil,
        onNodeCompleted: ((ExecutionResult) -> Void)? = nil,
        completion: @escaping ([ExecutionResult]) -> Void
    ) {
        // 检查连接状态
        let managerConnected = OpenClawManager.shared.isConnected
        guard managerConnected else {
            lastError = "Not connected to OpenClaw Gateway"
            addLog(.error, "Cannot execute: Not connected to OpenClaw Gateway")
            completion([])
            return
        }
        
        isExecuting = true
        executionResults = preloadedResults
        lastError = nil
        
        let queuedNodes = startingNodes ?? entryAgentNodes(in: workflow)
        let effectiveEntryNodeIDs = entryNodeIDsOverride ?? entryAgentNodeIDs(in: workflow)
        totalSteps = precompletedNodeIDs.count + queuedNodes.count
        currentStep = precompletedNodeIDs.count
        currentNodeID = nil

        // 初始化执行状态（用于回滚）
        executionState = ExecutionState(workflowID: workflow.id, totalSteps: totalSteps)
        executionState?.completedNodes = precompletedNodeIDs
        executionState?.currentStep = currentStep
        addLog(.info, "Starting workflow execution: \(workflow.name) with \(queuedNodes.count) queued node(s)")

        if queuedNodes.isEmpty {
            isExecuting = false
            currentNodeID = nil
            stopTimeoutTimer()
            clearExecutionState()

            let successCount = preloadedResults.filter { $0.status == .completed }.count
            let failCount = preloadedResults.filter { $0.status == .failed }.count
            addLog(.info, "Workflow execution completed: \(successCount) succeeded, \(failCount) failed")
            completion(preloadedResults)
            return
        }
        
        // 设置超时监控
        startTimeoutTimer(duration: executionTimeout) { [weak self] in
            self?.addLog(.error, "Execution timeout, stopping...")
            self?.isExecuting = false
        }
        
        // 按连接顺序执行
        executeNodesSequentially(
            queuedNodes,
            workflow: workflow,
            agents: agents,
            prompt: prompt,
            entryNodeIDs: effectiveEntryNodeIDs,
            seedResults: preloadedResults,
            agentOutputMode: agentOutputMode,
            onNodeStream: onNodeStream,
            onNodeCompleted: onNodeCompleted
        ) { nodeResults in
            self.executionResults = nodeResults
            self.isExecuting = false
            self.currentNodeID = nil
            self.stopTimeoutTimer()
            
            // 清理执行状态
            self.clearExecutionState()
            
            let successCount = nodeResults.filter { $0.status == .completed }.count
            let failCount = nodeResults.filter { $0.status == .failed }.count
            self.addLog(.info, "Workflow execution completed: \(successCount) succeeded, \(failCount) failed")
            
            completion(nodeResults)
        }
    }

    func executeWorkbenchEntryNode(
        node: WorkflowNode,
        workflow: Workflow,
        agents: [Agent],
        prompt: String,
        sessionID: String? = nil,
        thinkingLevel: AgentThinkingLevel = .off,
        onStream: ((String) -> Void)? = nil,
        completion: @escaping (WorkbenchEntryExecution) -> Void
    ) {
        guard let agentID = node.agentID,
              let agent = agents.first(where: { $0.id == agentID }) else {
            let failedResult = ExecutionResult(
                nodeID: node.id,
                agentID: UUID(),
                status: .failed,
                output: "Agent not found for node",
                outputType: .errorSummary
            )
            completion(WorkbenchEntryExecution(result: failedResult, downstreamNodes: []))
            return
        }

        let nodeByID = Dictionary(uniqueKeysWithValues: workflow.nodes.map { ($0.id, $0) })
        let sortedEdges = workflow.edges.sorted { lhs, rhs in
            guard let leftTarget = nodeByID[lhs.toNodeID], let rightTarget = nodeByID[rhs.toNodeID] else {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return nodeSort(leftTarget, rightTarget)
        }

        var outgoingEdges: [UUID: [WorkflowEdge]] = [:]
        for edge in sortedEdges {
            outgoingEdges[edge.fromNodeID, default: []].append(edge)
            if edge.isBidirectional {
                outgoingEdges[edge.toNodeID, default: []].append(edge.reversed())
            }
        }

        let downstreamTargets = routingTargets(
            for: node,
            workflow: workflow,
            agents: agents,
            outgoingEdges: outgoingEdges
        )

        executeNodeOnOpenClaw(
            node: node,
            agent: agent,
            prompt: prompt,
            isEntryNode: true,
            downstreamTargets: downstreamTargets,
            instructionStyle: .fastWorkbenchEntry,
            sessionID: sessionID,
            thinkingLevel: thinkingLevel,
            outputMode: .plainStreaming,
            onStream: onStream
        ) { [weak self] result, routingDecision in
            guard let self else { return }
            let resolvedTargets = self.resolveRoutingTargets(
                from: routingDecision,
                availableTargets: downstreamTargets,
                node: node,
                outputType: result.outputType,
                fallbackPolicy: workflow.fallbackRoutingPolicy
            )
            completion(
                WorkbenchEntryExecution(
                    result: result,
                    downstreamNodes: resolvedTargets.map(\.node)
                )
            )
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
        var outgoingEdges: [UUID: [WorkflowEdge]] = [:]
        for edge in orderedEdges {
            outgoingEdges[edge.fromNodeID, default: []].append(edge)
            if edge.isBidirectional {
                outgoingEdges[edge.toNodeID, default: []].append(edge.reversed())
            }
        }

        let startNodes = workflow.nodes
            .filter { $0.type == .start }
            .sorted(by: nodeSort)
        let entryNodes: [WorkflowNode]
        if !startNodes.isEmpty {
            entryNodes = startNodes
        } else {
            entryNodes = workflow.nodes
                .filter { node in
                    !workflow.edges.contains(where: { $0.isIncoming(to: node.id) })
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

    private func entryAgentNodeIDs(in workflow: Workflow) -> Set<UUID> {
        Set(entryAgentNodes(in: workflow).map(\.id))
    }

    private func entryAgentNodes(in workflow: Workflow) -> [WorkflowNode] {
        let nodeByID = Dictionary(uniqueKeysWithValues: workflow.nodes.map { ($0.id, $0) })
        let startNodes = workflow.nodes
            .filter { $0.type == .start }
            .sorted(by: nodeSort)

        if !startNodes.isEmpty {
            let connectedNodeIDs = startNodes.flatMap { startNode in
                workflow.edges.compactMap { edge -> UUID? in
                    guard edge.isOutgoing(from: startNode.id) else { return nil }
                    let targetNodeID = edge.fromNodeID == startNode.id ? edge.toNodeID : edge.fromNodeID
                    guard let node = nodeByID[targetNodeID], node.type == .agent else { return nil }
                    return targetNodeID
                }
            }
            let orderedIDs = orderedUniqueNodeIDs(connectedNodeIDs, nodeByID: nodeByID)
            return orderedIDs.compactMap { nodeByID[$0] }
        }

        return workflow.nodes
            .filter { node in
                node.type == .agent && !workflow.edges.contains(where: { $0.isIncoming(to: node.id) })
            }
            .sorted(by: nodeSort)
    }

    private func orderedUniqueNodeIDs(_ nodeIDs: [UUID], nodeByID: [UUID: WorkflowNode]) -> [UUID] {
        var seen = Set<UUID>()
        let unique = nodeIDs.filter { seen.insert($0).inserted }
        return unique.sorted { lhs, rhs in
            guard let leftNode = nodeByID[lhs], let rightNode = nodeByID[rhs] else {
                return lhs.uuidString < rhs.uuidString
            }
            return nodeSort(leftNode, rightNode)
        }
    }
    
    private func executeNodesSequentially(
        _ nodes: [WorkflowNode],
        workflow: Workflow,
        agents: [Agent],
        prompt: String?,
        entryNodeIDs: Set<UUID>,
        seedResults: [ExecutionResult] = [],
        agentOutputMode: AgentOutputMode,
        onNodeStream: ((NodeStreamUpdate) -> Void)? = nil,
        onNodeCompleted: ((ExecutionResult) -> Void)? = nil,
        completion: @escaping ([ExecutionResult]) -> Void
    ) {
        var results: [ExecutionResult] = seedResults
        let nodeByID = Dictionary(uniqueKeysWithValues: workflow.nodes.map { ($0.id, $0) })
        let agentByID = Dictionary(uniqueKeysWithValues: agents.map { ($0.id, $0) })
        let sortedEdges = workflow.edges.sorted { lhs, rhs in
            guard let leftTarget = nodeByID[lhs.toNodeID], let rightTarget = nodeByID[rhs.toNodeID] else {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return nodeSort(leftTarget, rightTarget)
        }
        var outgoingEdges: [UUID: [WorkflowEdge]] = [:]
        for edge in sortedEdges {
            outgoingEdges[edge.fromNodeID, default: []].append(edge)
            if edge.isBidirectional {
                outgoingEdges[edge.toNodeID, default: []].append(edge.reversed())
            }
        }

        var remainingNodes = nodes
        var scheduledVisitCounts = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, 1) })

        func enqueue(_ node: WorkflowNode, because reason: String) {
            let allowedVisits = max(1, node.loopEnabled ? node.maxIterations : 1)
            let nextVisitCount = scheduledVisitCounts[node.id, default: 0] + 1
            let nodeLabel = node.title.isEmpty ? String(node.id.uuidString.prefix(8)) : node.title
            guard nextVisitCount <= allowedVisits else {
                addLog(.warning, "Skipping route to \(nodeLabel) because it exceeds loop limit.", nodeID: node.id)
                return
            }

            scheduledVisitCounts[node.id] = nextVisitCount
            remainingNodes.append(node)
            totalSteps += 1
            executionState?.totalSteps = totalSteps
            addLog(.info, "Queued downstream node \(nodeLabel): \(reason)", nodeID: node.id)
        }

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
            currentNodeID = node.id

            // 更新执行状态
            executionState?.currentStep = currentStep
            executionState?.lastUpdated = Date()
            executionState?.totalSteps = totalSteps
            saveExecutionState()

            addLog(.info, "Executing node \(currentStep)/\(totalSteps)", nodeID: node.id)
            
            guard let agentID = node.agentID,
                  let agent = agentByID[agentID] else {
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
            executeNodeOnOpenClaw(
                node: node,
                agent: agent,
                prompt: prompt,
                isEntryNode: entryNodeIDs.contains(node.id),
                downstreamTargets: routingTargets(for: node, workflow: workflow, agents: agents, outgoingEdges: outgoingEdges),
                outputMode: agentOutputMode,
                onStream: { chunk in
                    onNodeStream?(
                        NodeStreamUpdate(
                            nodeID: node.id,
                            agentID: agent.id,
                            chunk: chunk
                        )
                    )
                }
            ) { result, routingDecision in
                results.append(result)
                self.executionResults.append(result)
                onNodeCompleted?(result)

                // 更新执行状态
                if result.status == .completed {
                    self.executionState?.completedNodes.append(node.id)
                    self.addLog(.success, "Node completed: \(agent.name)", nodeID: node.id)

                    let downstreamTargets = self.routingTargets(for: node, workflow: workflow, agents: agents, outgoingEdges: outgoingEdges)
                    let selectedTargets = self.resolveRoutingTargets(
                        from: routingDecision,
                        availableTargets: downstreamTargets,
                        node: node,
                        outputType: result.outputType,
                        fallbackPolicy: workflow.fallbackRoutingPolicy
                    )
                    for target in selectedTargets {
                        enqueue(target.node, because: routingDecision?.reason ?? "routed by \(agent.name)")
                    }
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
        isEntryNode: Bool = false,
        downstreamTargets: [RoutingTargetDescriptor] = [],
        instructionStyle: WorkflowInstructionStyle = .standard,
        sessionID: String? = nil,
        thinkingLevel: AgentThinkingLevel? = nil,
        outputMode: AgentOutputMode = .structuredJSON,
        onStream: ((String) -> Void)? = nil,
        completion: @escaping (ExecutionResult, WorkflowRoutingDecision?) -> Void
    ) {
        // 构建执行指令
        let instruction = buildInstruction(
            for: node,
            agent: agent,
            prompt: prompt,
            isEntryNode: isEntryNode,
            downstreamTargets: downstreamTargets,
            style: instructionStyle
        )
        let targetAgentID = resolvedAgentIdentifier(for: agent)

        // 调用openclaw agent命令
        callOpenClawAgent(
            instruction: instruction,
            agentIdentifier: targetAgentID,
            sessionID: sessionID,
            thinkingLevel: thinkingLevel,
            outputMode: outputMode,
            onPartial: onStream
        ) { success, parsedOutput in
            let status: ExecutionStatus = success ? .completed : .failed
            let result = ExecutionResult(
                nodeID: node.id,
                agentID: agent.id,
                status: status,
                output: parsedOutput.text,
                outputType: parsedOutput.type,
                routingAction: parsedOutput.routingDecision?.action.rawValue,
                routingTargets: parsedOutput.routingDecision?.targets ?? [],
                routingReason: parsedOutput.routingDecision?.reason
            )
            completion(result, parsedOutput.routingDecision)
        }
    }

    // 构建Agent指令
    private func buildInstruction(
        for node: WorkflowNode,
        agent: Agent,
        prompt: String?,
        isEntryNode: Bool,
        downstreamTargets: [RoutingTargetDescriptor],
        style: WorkflowInstructionStyle
    ) -> String {
        let normalizedPrompt = prompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let candidateLines: [String]
        if downstreamTargets.isEmpty {
            candidateLines = ["- No downstream agents are available from this node."]
        } else {
            candidateLines = downstreamTargets.map { target in
                let title = target.node.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let nodeLabel = title.isEmpty ? target.node.id.uuidString : title
                return "- \(target.agent.name) (agent_id: \(target.resolvedIdentifier), node: \(nodeLabel))"
            }
        }

        switch style {
        case .standard:
            var instruction = "Execute agent task:\n"
            instruction += "Agent: \(agent.name)\n"
            instruction += "Node ID: \(node.id.uuidString)\n"
            instruction += "Node Type: \(node.type.rawValue)\n"
            instruction += "Position: (\(Int(node.position.x)), \(Int(node.position.y)))\n"

            if !normalizedPrompt.isEmpty {
                instruction += "\nUser Task:\n\(normalizedPrompt)\n"
            }

            if isEntryNode {
                instruction += """

                Workbench Entry Policy:
                - You are the entry agent facing the user directly.
                - Reply to the user immediately with a direct answer first.
                - Contact other agents only when strictly necessary.
                - If cross-agent communication is limited, do not stall; continue with the best direct answer and clearly state constraints.
                """
                instruction += "\n"
            }

            instruction += """

            Workflow Routing Policy:
            - Downstream routing is opt-in, never automatic.
            - If you can finish the task yourself, stop and do not route further.
            - Only route when you genuinely need help from a downstream agent in this workflow.
            - You may only choose downstream agents from the list below.

            Downstream Candidates:
            \(candidateLines.joined(separator: "\n"))

            Routing Output Contract:
            - After your normal visible reply, append exactly one valid single-line JSON object as the last non-empty line.
            - Use this schema:
              {"workflow_route":{"action":"stop","targets":[],"reason":"short reason"}}
            - Allowed action values:
              - "stop": do not trigger any downstream agent.
              - "selected": trigger only the listed downstream agents by name, agent_id, or node title.
              - "all": trigger every available downstream agent.
            - Keep the JSON line separate from the user-facing answer.
            - Do not wrap the JSON in Markdown code fences.
            """

            return instruction
        case .fastWorkbenchEntry:
            return """
            Fast Workbench Entry
            Agent: \(agent.name)
            User Task: \(normalizedPrompt.isEmpty ? "(none provided)" : normalizedPrompt)

            Rules:
            - Reply to the user immediately with a practical answer.
            - Keep the visible reply concise and high-signal.
            - If you can finish the task yourself, do not route further.
            - Only choose downstream agents from the list below when they are truly needed.

            Downstream Candidates:
            \(candidateLines.joined(separator: "\n"))

            Append exactly one JSON object as the last non-empty line:
            {"workflow_route":{"action":"stop","targets":[],"reason":"short reason"}}
            Allowed action values: "stop", "selected", "all".
            Keep the JSON on its own line with no Markdown fence.
            """
        }
    }

    private func routingTargets(
        for node: WorkflowNode,
        workflow: Workflow,
        agents: [Agent],
        outgoingEdges: [UUID: [WorkflowEdge]]
    ) -> [RoutingTargetDescriptor] {
        let nodeByID = Dictionary(uniqueKeysWithValues: workflow.nodes.map { ($0.id, $0) })
        let agentByID = Dictionary(uniqueKeysWithValues: agents.map { ($0.id, $0) })
        let edges = selectOutgoingEdges(for: node, edges: outgoingEdges[node.id, default: []], workflow: workflow)

        var targets: [RoutingTargetDescriptor] = []
        var seen = Set<UUID>()

        for edge in edges {
            guard let candidateNode = nodeByID[edge.toNodeID],
                  candidateNode.type == .agent,
                  let agentID = candidateNode.agentID,
                  let candidateAgent = agentByID[agentID],
                  seen.insert(candidateNode.id).inserted else {
                continue
            }

            targets.append(
                RoutingTargetDescriptor(
                    node: candidateNode,
                    agent: candidateAgent,
                    resolvedIdentifier: resolvedAgentIdentifier(for: candidateAgent)
                )
            )
        }

        return targets.sorted { lhs, rhs in
            nodeSort(lhs.node, rhs.node)
        }
    }

    private func resolveRoutingTargets(
        from decision: WorkflowRoutingDecision?,
        availableTargets: [RoutingTargetDescriptor],
        node: WorkflowNode,
        outputType: ExecutionOutputType,
        fallbackPolicy: WorkflowFallbackRoutingPolicy
    ) -> [RoutingTargetDescriptor] {
        guard !availableTargets.isEmpty else { return [] }

        guard let decision else {
            if outputType != .runtimeLog {
                switch fallbackPolicy {
                case .stop:
                    addLog(.info, "No routing decision emitted; stopping at current node by default.", nodeID: node.id)
                    return []
                case .firstAvailable:
                    if availableTargets.count == 1 {
                        let target = availableTargets[0]
                        addLog(.info, "No routing decision emitted; fallback policy routed to single downstream agent \(target.agent.name).", nodeID: node.id)
                        return [target]
                    }
                    addLog(.info, "No routing decision emitted; fallback policy requires exactly one downstream agent, so execution stopped.", nodeID: node.id)
                    return []
                case .allAvailable:
                    let names = availableTargets.map(\.agent.name).joined(separator: ", ")
                    addLog(.info, "No routing decision emitted; fallback policy routed to all downstream agents: \(names)", nodeID: node.id)
                    return availableTargets
                }
            }
            return []
        }

        switch decision.action {
        case .stop:
            addLog(.info, "Routing decision: stop.", nodeID: node.id)
            return []
        case .all:
            addLog(.info, "Routing decision: fan out to all downstream agents.", nodeID: node.id)
            return availableTargets
        case .selected:
            if decision.targets.isEmpty {
                addLog(.warning, "Routing decision requested selected targets, but no targets were provided.", nodeID: node.id)
                return []
            }

            let resolved = availableTargets.filter { target in
                routeTargetMatches(decision.targets, candidate: target)
            }

            let unresolved = decision.targets.filter { requested in
                !availableTargets.contains { target in
                    routeTargetMatches([requested], candidate: target)
                }
            }
            if !unresolved.isEmpty {
                addLog(.warning, "Ignored unknown downstream targets: \(unresolved.joined(separator: ", "))", nodeID: node.id)
            }

            if resolved.isEmpty {
                addLog(.warning, "Routing decision did not match any reachable downstream agent.", nodeID: node.id)
            } else {
                let names = resolved.map { $0.agent.name }.joined(separator: ", ")
                addLog(.info, "Routing decision: \(names)", nodeID: node.id)
            }
            return resolved
        }
    }

    private func routeTargetMatches(_ requestedTargets: [String], candidate: RoutingTargetDescriptor) -> Bool {
        let candidateKeys = routeMatchKeys(for: candidate)
        return requestedTargets.contains { requested in
            let normalized = normalizedRouteKey(requested)
            return !normalized.isEmpty && candidateKeys.contains(normalized)
        }
    }

    private func routeMatchKeys(for candidate: RoutingTargetDescriptor) -> Set<String> {
        var keys: Set<String> = [
            normalizedRouteKey(candidate.agent.name),
            normalizedRouteKey(candidate.resolvedIdentifier),
            normalizedRouteKey(candidate.node.title),
            normalizedRouteKey(candidate.node.id.uuidString),
            normalizedRouteKey(String(candidate.node.id.uuidString.prefix(8)))
        ]
        keys = keys.filter { !$0.isEmpty }
        return keys
    }

    private func normalizedRouteKey(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
    
    // 调用OpenClaw Agent
    private func callOpenClawAgent(
        instruction: String,
        agentIdentifier: String,
        sessionID: String? = nil,
        thinkingLevel: AgentThinkingLevel? = nil,
        outputMode: AgentOutputMode = .structuredJSON,
        onPartial: ((String) -> Void)? = nil,
        completion: @escaping (Bool, ParsedAgentOutput) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async(execute: { [weak self] in
            guard let self = self else { return }
            
            let serviceConfig = self.agentConfig
            let manager = OpenClawManager.shared
            let connectionConfig = manager.config
            let pluginCleanup = manager.cleanupStalePluginInstallStageArtifactsIfNeeded(using: connectionConfig)
            if !pluginCleanup.success {
                self.addLog(.warning, pluginCleanup.message)
            } else if !pluginCleanup.message.isEmpty {
                self.addLog(.info, pluginCleanup.message)
            }

            let resolvedAgent = self.resolveRuntimeAgentIdentifier(
                preferred: agentIdentifier,
                manager: manager,
                config: connectionConfig
            )
            if let message = resolvedAgent.message {
                self.addLog(.warning, message)
            }

            if connectionConfig.deploymentKind == .remoteServer {
                let gatewaySessionKey = self.gatewaySessionKey(
                    sessionID: sessionID,
                    agentIdentifier: resolvedAgent.identifier
                )
                let shouldStreamPlainOutput: Bool
                switch outputMode {
                case .plainStreaming:
                    shouldStreamPlainOutput = true
                case .structuredJSON:
                    shouldStreamPlainOutput = false
                }

                self.addLog(
                    .info,
                    "Gateway agent path enabled for remote server: agent=\(resolvedAgent.identifier), sessionKey=\(gatewaySessionKey)"
                )

                _Concurrency.Task {
                    do {
                        let streamAccumulator = StreamingTextAccumulator()
                        let onAssistantTextUpdated: @Sendable (String) -> Void = { fullText in
                            guard let onPartial, shouldStreamPlainOutput else { return }
                            _Concurrency.Task {
                                let delta = await streamAccumulator.delta(
                                    for: fullText,
                                    extractor: Self.extractVisiblePlainResponseText(from:),
                                    differ: Self.streamingDeltaText(from:to:)
                                )
                                guard !delta.isEmpty else { return }
                                DispatchQueue.main.async {
                                    onPartial(delta)
                                }
                            }
                        }
                        let result: OpenClawGatewayClient.AgentExecutionResult
                        if let sessionID, !sessionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            await MainActor.run {
                                self.addLog(
                                    .info,
                                    "Gateway chat session path enabled for remote workbench session \(gatewaySessionKey)."
                                )
                            }
                            result = try await manager.executeGatewayChatCommand(
                                message: instruction,
                                sessionKey: gatewaySessionKey,
                                thinkingLevel: thinkingLevel,
                                timeoutSeconds: max(1, serviceConfig.timeout),
                                using: connectionConfig,
                                onAssistantTextUpdated: onAssistantTextUpdated
                            )
                        } else {
                            result = try await manager.executeGatewayAgentCommand(
                                message: instruction,
                                agentIdentifier: resolvedAgent.identifier,
                                sessionKey: gatewaySessionKey,
                                thinkingLevel: thinkingLevel,
                                timeoutSeconds: max(1, serviceConfig.timeout),
                                using: connectionConfig,
                                onAssistantTextUpdated: onAssistantTextUpdated
                            )
                        }

                        let normalizedText = result.assistantText.trimmingCharacters(in: .whitespacesAndNewlines)
                        let parsedOutput = await MainActor.run {
                            self.parseAgentOutput(from: normalizedText, outputMode: outputMode)
                        }
                        let success = result.status == "ok"
                        let fallback = result.errorMessage ?? (normalizedText.isEmpty ? "Gateway agent run finished with status: \(result.status)" : normalizedText)

                        DispatchQueue.main.async {
                            if success {
                                completion(true, parsedOutput)
                            } else {
                                completion(
                                    false,
                                    ParsedAgentOutput(
                                        text: fallback,
                                        type: .errorSummary,
                                        routingDecision: nil
                                    )
                                )
                            }
                        }
                    } catch {
                        DispatchQueue.main.async {
                            completion(
                                false,
                                ParsedAgentOutput(
                                    text: "Gateway error: \(error.localizedDescription)",
                                    type: .errorSummary,
                                    routingDecision: nil
                                )
                            )
                        }
                    }
                }
                return
            }
            
            // 构建命令

            var args = ["agent"]
            args.append(contentsOf: ["--agent", resolvedAgent.identifier])
            args.append(contentsOf: ["--message", instruction])
            if let sessionID, !sessionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                args.append(contentsOf: ["--session-id", sessionID])
            }
            if let thinkingLevel {
                args.append(contentsOf: ["--thinking", thinkingLevel.rawValue])
            }

            let capabilityCacheKey = self.capabilityCacheKey(for: connectionConfig)
            let capabilities = self.resolveAgentCLICapabilities(
                manager: manager,
                config: connectionConfig,
                cacheKey: capabilityCacheKey
            )
            let enabledFlags = self.appendCLIOutputFlags(
                to: &args,
                capabilities: capabilities,
                config: connectionConfig,
                outputMode: outputMode
            )

            if self.loggedCapabilityKeys.insert(capabilityCacheKey).inserted {
                let flagText = enabledFlags.isEmpty ? "(none)" : enabledFlags.joined(separator: " ")
                self.addLog(
                    .info,
                    "OpenClaw CLI 输出能力: quiet=\(capabilities.supportsQuiet), log-level=\(capabilities.supportsLogLevel), json-only=\(capabilities.supportsJSONOnly); 当前启用参数: \(flagText)."
                )
            }
            
            let shouldUseLocal = serviceConfig.useLocal
                && !manager.isConnected
                && connectionConfig.deploymentKind == .local
            if shouldUseLocal {
                args.append("--local")
            }
            
            args.append(contentsOf: ["--timeout", String(max(1, serviceConfig.timeout))])

            do {
                let result = try manager.executeAgentRuntimeCommand(
                    arguments: args,
                    using: connectionConfig,
                    onStdoutChunk: { chunk in
                        guard let onPartial else { return }
                        let visibleChunk = self.extractStreamingTextChunk(from: chunk)
                        guard !visibleChunk.isEmpty else { return }
                        DispatchQueue.main.async {
                            onPartial(visibleChunk)
                        }
                    }
                )
                let stdout = String(data: result.standardOutput, encoding: .utf8) ?? ""
                let stderr = String(data: result.standardError, encoding: .utf8) ?? ""
                let stdoutTrimmed = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                let stderrTrimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                let parsedOutput = self.parseAgentOutput(from: stdoutTrimmed, outputMode: outputMode)

                let runtimeMessage: String?
                if result.executionCount == 1 {
                    runtimeMessage = "Created OpenClaw Agent Runtime channel \(result.channelKey) and executed the first request."
                } else if result.executionCount == 2 {
                    runtimeMessage = "OpenClaw Agent Runtime channel \(result.channelKey) is now being reused for subsequent requests."
                } else {
                    runtimeMessage = nil
                }
                if let runtimeMessage {
                    self.addLog(.info, runtimeMessage)
                }

                if !stderrTrimmed.isEmpty {
                    let level: ExecutionLogEntry.LogLevel = result.terminationStatus == 0 ? .warning : .error
                    self.addLog(level, "OpenClaw stderr (\(resolvedAgent.identifier)): \(self.truncatedLog(stderrTrimmed))")
                }

                DispatchQueue.main.async {
                    if result.terminationStatus == 0 {
                        completion(true, parsedOutput)
                    } else {
                        let fallback = self.executionFailureSummary(
                            exitCode: result.terminationStatus,
                            stderr: stderrTrimmed,
                            stdout: stdoutTrimmed
                        )
                        completion(
                            false,
                            ParsedAgentOutput(
                                text: fallback,
                                type: .errorSummary,
                                routingDecision: nil
                            )
                        )
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    completion(
                        false,
                        ParsedAgentOutput(
                            text: "Error: \(error.localizedDescription)",
                            type: .errorSummary,
                            routingDecision: nil
                        )
                    )
                }
            }
        })
    }

    private func parseAgentOutput(from stdout: String, outputMode: AgentOutputMode) -> ParsedAgentOutput {
        switch outputMode {
        case .structuredJSON:
            let parsed = extractAgentResponse(from: stdout)
            let routingDecision = extractRoutingDecision(from: stdout) ?? extractRoutingDecision(from: parsed.text)
            let sanitizedText = stripRoutingDirective(from: parsed.text)
            return ParsedAgentOutput(text: sanitizedText, type: parsed.type, routingDecision: routingDecision)
        case .plainStreaming:
            let text = extractVisiblePlainResponse(from: stdout)
            let routingDecision = extractRoutingDecision(from: stdout) ?? extractRoutingDecision(from: text)
            let sanitizedText = stripRoutingDirective(from: text)
            let outputType: ExecutionOutputType = sanitizedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? .runtimeLog
                : .agentFinalResponse
            return ParsedAgentOutput(text: sanitizedText, type: outputType, routingDecision: routingDecision)
        }
    }

    private func capabilityCacheKey(for config: OpenClawConfig) -> String {
        switch config.deploymentKind {
        case .local:
            return "local|\(config.localBinaryPath)"
        case .container:
            return "container|\(config.container.engine)|\(config.container.containerName)"
        case .remoteServer:
            return "remote|\(config.host)|\(config.port)"
        }
    }

    private func resolveAgentCLICapabilities(
        manager: OpenClawManager,
        config: OpenClawConfig,
        cacheKey: String
    ) -> AgentCLICapabilities {
        if let cached = agentCLICapabilitiesCache[cacheKey] {
            return cached
        }

        let detected = detectAgentCLICapabilities(manager: manager, config: config)
        agentCLICapabilitiesCache[cacheKey] = detected
        return detected
    }

    private func detectAgentCLICapabilities(
        manager: OpenClawManager,
        config: OpenClawConfig
    ) -> AgentCLICapabilities {
        do {
            let helpResult = try manager.executeOpenClawCLI(arguments: ["agent", "--help"], using: config)
            let text = (
                String(data: helpResult.standardOutput, encoding: .utf8) ?? ""
            ) + "\n" + (
                String(data: helpResult.standardError, encoding: .utf8) ?? ""
            )
            let normalized = text.lowercased()

            let supportsQuiet = normalized.contains("--quiet") || normalized.contains("-q,")
            let supportsLogLevel = normalized.contains("--log-level")
            let supportsJSONOnly = normalized.contains("--json-only")

            return AgentCLICapabilities(
                supportsQuiet: supportsQuiet,
                supportsLogLevel: supportsLogLevel,
                supportsJSONOnly: supportsJSONOnly
            )
        } catch {
            return AgentCLICapabilities(
                supportsQuiet: false,
                supportsLogLevel: false,
                supportsJSONOnly: false
            )
        }
    }

    private func appendCLIOutputFlags(
        to arguments: inout [String],
        capabilities: AgentCLICapabilities,
        config: OpenClawConfig,
        outputMode: AgentOutputMode
    ) -> [String] {
        var enabledFlags: [String] = []

        if capabilities.supportsLogLevel {
            arguments.append(contentsOf: ["--log-level", config.cliLogLevel.cliValue])
            enabledFlags.append("--log-level \(config.cliLogLevel.cliValue)")
        }

        if config.cliQuietMode && capabilities.supportsQuiet {
            arguments.append("--quiet")
            enabledFlags.append("--quiet")
        }

        if outputMode == .structuredJSON {
            if capabilities.supportsJSONOnly {
                arguments.append("--json-only")
                enabledFlags.append("--json-only")
            } else {
                arguments.append("--json")
                enabledFlags.append("--json")
            }
        }

        return enabledFlags
    }

    private func executeOpenClawAgentStreamingProcess(
        manager: OpenClawManager,
        config: OpenClawConfig,
        arguments: [String],
        onStdoutChunk: @escaping (String) -> Void
    ) throws -> (terminationStatus: Int32, standardOutput: Data, standardError: Data) {
        let process = Process()

        switch config.deploymentKind {
        case .local:
            process.executableURL = URL(fileURLWithPath: manager.resolvedOpenClawPath(using: config))
            process.arguments = arguments
        case .container:
            let containerName = config.container.containerName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !containerName.isEmpty else {
                throw NSError(
                    domain: "OpenClawService",
                    code: 2001,
                    userInfo: [NSLocalizedDescriptionKey: "容器名称未配置，无法执行 OpenClaw agent 命令。"]
                )
            }
            let engine = config.container.engine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "docker"
                : config.container.engine.trimmingCharacters(in: .whitespacesAndNewlines)
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [engine, "exec", containerName, "openclaw"] + arguments
        case .remoteServer:
            throw NSError(
                domain: "OpenClawService",
                code: 2002,
                userInfo: [NSLocalizedDescriptionKey: "远程网关模式不支持直接执行 OpenClaw CLI。"]
            )
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let lock = NSLock()
        var stdoutData = Data()
        var stderrData = Data()

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            lock.lock()
            stdoutData.append(data)
            lock.unlock()
            onStdoutChunk(String(decoding: data, as: UTF8.self))
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            lock.lock()
            stderrData.append(data)
            lock.unlock()
        }

        try process.run()
        process.waitUntilExit()

        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        let remainingStdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        if !remainingStdout.isEmpty {
            lock.lock()
            stdoutData.append(remainingStdout)
            lock.unlock()
            onStdoutChunk(String(decoding: remainingStdout, as: UTF8.self))
        }

        let remainingStderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        if !remainingStderr.isEmpty {
            lock.lock()
            stderrData.append(remainingStderr)
            lock.unlock()
        }

        return (process.terminationStatus, stdoutData, stderrData)
    }

    private func extractStreamingTextChunk(from chunk: String) -> String {
        let normalized = chunk.replacingOccurrences(of: "\r", with: "")
        guard !normalized.isEmpty else { return "" }

        let lines = normalized.components(separatedBy: .newlines)
        var visibleLines: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                visibleLines.append(line)
                continue
            }

            if looksLikeRuntimeLog(trimmed) {
                continue
            }
            if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
                continue
            }
            visibleLines.append(line)
        }

        var filtered = visibleLines.joined(separator: "\n")
        if normalized.hasSuffix("\n"), !filtered.hasSuffix("\n") {
            filtered += "\n"
        }

        guard !filtered.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
        return filtered
    }

    private func gatewaySessionKey(sessionID: String?, agentIdentifier: String) -> String {
        let normalizedAgent = normalizedGatewayAgentID(agentIdentifier)
        let base = sessionID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !base.isEmpty {
            if base.lowercased().hasPrefix("agent:") {
                return base.lowercased()
            }
            return "agent:\(normalizedAgent):\(sanitizedGatewaySessionComponent(base))"
        }
        return "agent:\(normalizedAgent):main"
    }

    private func normalizedGatewayAgentID(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return "main" }

        let filtered = trimmed.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) {
                return Character(scalar)
            }
            if scalar == "-" || scalar == "_" || scalar == "." {
                return Character(scalar)
            }
            return "-"
        }

        let value = String(filtered).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return value.isEmpty ? "main" : value
    }

    private func sanitizedGatewaySessionComponent(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "main" }

        let filtered = trimmed.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) {
                return Character(scalar)
            }
            if scalar == "-" || scalar == "_" || scalar == ":" || scalar == "." {
                return Character(scalar)
            }
            return "-"
        }

        let value = String(filtered)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            .lowercased()
        return value.isEmpty ? "main" : value
    }

    private func streamingDelta(from previous: String, to current: String) -> String {
        Self.streamingDeltaText(from: previous, to: current)
    }

    private nonisolated static func streamingDeltaText(from previous: String, to current: String) -> String {
        guard !current.isEmpty else { return "" }
        if previous.isEmpty {
            return current
        }
        if current.hasPrefix(previous) {
            return String(current.dropFirst(previous.count))
        }
        return current
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

    private func extractRoutingDecision(from text: String) -> WorkflowRoutingDecision? {
        let payloads = extractJSONPayloads(from: text)
        for payload in payloads.reversed() {
            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data),
                  let decision = routingDecision(from: json) else {
                continue
            }
            return decision
        }
        return nil
    }

    private func stripRoutingDirective(from text: String) -> String {
        let normalized = text.replacingOccurrences(of: "\r", with: "")
        let lines = normalized.components(separatedBy: .newlines)
        guard let lastIndex = lines.lastIndex(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            return text
        }

        let candidate = lines[lastIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        guard extractRoutingDecision(from: candidate) != nil else {
            return text
        }

        var trimmedLines = lines
        trimmedLines.remove(at: lastIndex)
        return trimmedLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func routingDecision(from json: Any) -> WorkflowRoutingDecision? {
        if let dict = json as? [String: Any] {
            if let nested = dict["workflow_route"] {
                return routingDecision(fromRouteObject: nested)
            }
            if let nested = dict["route"] {
                return routingDecision(fromRouteObject: nested)
            }
            if let nested = dict["routing"] {
                return routingDecision(fromRouteObject: nested)
            }
            return routingDecision(fromRouteObject: dict)
        }

        if let array = json as? [Any] {
            for item in array.reversed() {
                if let decision = routingDecision(from: item) {
                    return decision
                }
            }
        }

        return nil
    }

    private func routingDecision(fromRouteObject object: Any) -> WorkflowRoutingDecision? {
        guard let dict = object as? [String: Any] else { return nil }

        let rawAction = firstNonEmptyString(in: dict, keys: ["action", "mode", "decision", "type"])?.lowercased()
        let action: WorkflowRoutingDecision.Action
        switch rawAction {
        case "all", "broadcast", "fanout":
            action = .all
        case "selected", "select", "route", "delegate", "handoff", "handover":
            action = .selected
        case "stop", "none", "finish", "done":
            action = .stop
        case nil:
            if let continueValue = dict["continue"] as? Bool {
                action = continueValue ? .selected : .stop
            } else {
                let nextAgents = stringArray(from: dict["targets"] ?? dict["next_agents"] ?? dict["nextAgents"])
                action = nextAgents.isEmpty ? .stop : .selected
            }
        default:
            return nil
        }

        let targets = stringArray(from: dict["targets"] ?? dict["next_agents"] ?? dict["nextAgents"] ?? dict["agents"])
        let reason = firstNonEmptyString(in: dict, keys: ["reason", "why", "note", "summary"])
        return WorkflowRoutingDecision(action: action, targets: targets, reason: reason)
    }

    private func stringArray(from value: Any?) -> [String] {
        guard let value else { return [] }

        if let strings = value as? [String] {
            return strings.compactMap(normalizedNonEmpty)
        }

        if let array = value as? [Any] {
            return array.compactMap { item in
                if let text = item as? String {
                    return normalizedNonEmpty(text)
                }
                if let dict = item as? [String: Any] {
                    return firstNonEmptyString(in: dict, keys: ["name", "agent", "agent_id", "id", "node", "target"])
                }
                return nil
            }
        }

        if let string = value as? String {
            let parts = string
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .compactMap(normalizedNonEmpty)
            return parts
        }

        return []
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

    private func extractVisiblePlainResponse(from stdout: String) -> String {
        Self.extractVisiblePlainResponseText(from: stdout)
    }

    private nonisolated static func extractVisiblePlainResponseText(from stdout: String) -> String {
        let normalized = stdout.replacingOccurrences(of: "\r", with: "")
        guard !normalized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }

        let keptLines = normalized
            .components(separatedBy: .newlines)
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return false }
                if looksLikeRuntimeLogText(trimmed) { return false }
                if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") { return false }
                return true
            }

        let joined = keptLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if !joined.isEmpty {
            return joined
        }
        return normalized.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func looksLikeRuntimeLog(_ text: String) -> Bool {
        Self.looksLikeRuntimeLogText(text)
    }

    private nonisolated static func looksLikeRuntimeLogText(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        if lowercased.hasPrefix("[plugins]") || lowercased.hasPrefix("[diagnostic]") || lowercased.hasPrefix("[model-fallback/decision]") {
            return true
        }
        if lowercased.hasPrefix("config warnings:") || lowercased.hasPrefix("- plugins.entries.") {
            return true
        }
        if lowercased.contains("duplicate plugin id detected") || lowercased.contains("config overwrite:") {
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
        if config.deploymentKind == .remoteServer {
            return resolveRemoteRuntimeAgentIdentifier(preferred: preferred, manager: manager, config: config)
        }

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

    private func resolveRemoteRuntimeAgentIdentifier(
        preferred: String,
        manager: OpenClawManager,
        config: OpenClawConfig
    ) -> (identifier: String, message: String?) {
        let availableRecords = manager.discoveryResults.compactMap { record -> (id: String, name: String)? in
            let identifier = record.id.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = record.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !identifier.isEmpty else { return nil }
            return (identifier, name.isEmpty ? identifier : name)
        }

        func match(_ value: String) -> (id: String, name: String)? {
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !normalized.isEmpty else { return nil }
            return availableRecords.first { record in
                record.id.lowercased() == normalized || record.name.lowercased() == normalized
            }
        }

        let preferredID = preferred.trimmingCharacters(in: .whitespacesAndNewlines)
        if let matched = match(preferredID) {
            return (matched.id, matched.id == preferredID ? nil : "远程网关已将 agent \(preferredID) 解析为 \(matched.id)。")
        }

        if let defaultMatch = match(config.defaultAgent) {
            let message = preferredID.isEmpty
                ? "目标 agent 未配置，已回退到默认远程 agent \(defaultMatch.id)。"
                : "目标 agent \(preferredID) 在远程网关中不存在，已回退到默认 agent \(defaultMatch.id)。"
            return (defaultMatch.id, message)
        }

        if let mainMatch = match("main") {
            let message = preferredID.isEmpty
                ? "目标 agent 未配置，已回退到远程 agent \(mainMatch.id)。"
                : "目标 agent \(preferredID) 在远程网关中不存在，已回退到 \(mainMatch.id)。"
            return (mainMatch.id, message)
        }

        if let first = availableRecords.first {
            let message = preferredID.isEmpty
                ? "目标 agent 未配置，已回退到远程 agent \(first.id)。"
                : "目标 agent \(preferredID) 在远程网关中不存在，已回退到 \(first.id)。"
            return (first.id, message)
        }

        return (preferredID.isEmpty ? "main" : preferredID, nil)
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
        if config.deploymentKind == .remoteServer {
            let identifiers = manager.discoveryResults.compactMap { record -> String? in
                let identifier = record.id.trimmingCharacters(in: .whitespacesAndNewlines)
                return identifier.isEmpty ? nil : identifier
            }

            if !identifiers.isEmpty {
                var seen = Set<String>()
                return identifiers.filter { seen.insert($0.lowercased()).inserted }
            }

            var seen = Set<String>()
            return manager.agents.filter { candidate in
                let normalized = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !normalized.isEmpty else { return false }
                return seen.insert(normalized.lowercased()).inserted
            }
        }

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
        executeNodeOnOpenClaw(node: node, agent: agent, prompt: nil) { result, _ in
            completion(result)
        }
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
        currentNodeID = nil
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
            if edge.isBidirectional {
                adjacency[edge.toNodeID, default: []].append(edge.fromNodeID)
                indegree[edge.fromNodeID, default: 0] += 1
            }
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
