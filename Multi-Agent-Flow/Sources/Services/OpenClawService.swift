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

enum OpenClawRuntimeExecutionIntent: String, Sendable {
    case conversationAutonomous = "conversation_autonomous"
    case workflowControlled = "workflow_controlled"
    case inspectionReadonly = "inspection_readonly"
    case benchmark = "benchmark"

    var requiresPersistentPublish: Bool {
        switch self {
        case .workflowControlled:
            return true
        case .conversationAutonomous, .inspectionReadonly, .benchmark:
            return false
        }
    }

    var allowsEphemeralPublish: Bool {
        !requiresPersistentPublish
    }

    var displayName: String {
        semanticType.displayTitle
    }
}

private enum WorkflowInstructionStyle {
    case standard
    case fastWorkbenchEntry
}

private enum AgentTransportPreference: Sendable {
    case automatic
    case gatewayOnly
    case cliOnly
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
    let sessionID: String?
    let executionIntent: String?
    let transportKind: String?
    let firstChunkLatencyMs: Int?
    let completionLatencyMs: Int?
    let routingAction: String?
    let routingTargets: [String]
    let routingReason: String?
    let requestedRoutingAction: String?
    let requestedRoutingTargets: [String]
    let requestedRoutingReason: String?
    let protocolRepairCount: Int
    let protocolRepairTypes: [String]
    let protocolSafeDegradeApplied: Bool
    let runtimeEvents: [OpenClawRuntimeEvent]
    let primaryRuntimeEvent: OpenClawRuntimeEvent?
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
        case sessionID
        case executionIntent
        case transportKind
        case firstChunkLatencyMs
        case completionLatencyMs
        case routingAction
        case routingTargets
        case routingReason
        case requestedRoutingAction
        case requestedRoutingTargets
        case requestedRoutingReason
        case protocolRepairCount
        case protocolRepairTypes
        case protocolSafeDegradeApplied
        case runtimeEvents
        case primaryRuntimeEvent
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
        sessionID: String? = nil,
        executionIntent: String? = nil,
        transportKind: String? = nil,
        firstChunkLatencyMs: Int? = nil,
        completionLatencyMs: Int? = nil,
        routingAction: String? = nil,
        routingTargets: [String] = [],
        routingReason: String? = nil,
        requestedRoutingAction: String? = nil,
        requestedRoutingTargets: [String] = [],
        requestedRoutingReason: String? = nil,
        protocolRepairCount: Int = 0,
        protocolRepairTypes: [String] = [],
        protocolSafeDegradeApplied: Bool = false,
        runtimeEvents: [OpenClawRuntimeEvent] = [],
        primaryRuntimeEvent: OpenClawRuntimeEvent? = nil,
        startedAt: Date = Date(),
        completedAt: Date? = nil
    ) {
        self.id = UUID()
        self.nodeID = nodeID
        self.agentID = agentID
        self.status = status
        self.output = output
        self.outputType = outputType
        self.sessionID = sessionID
        self.executionIntent = executionIntent
        self.transportKind = transportKind
        self.firstChunkLatencyMs = firstChunkLatencyMs
        self.completionLatencyMs = completionLatencyMs
        self.routingAction = routingAction
        self.routingTargets = routingTargets
        self.routingReason = routingReason
        self.requestedRoutingAction = requestedRoutingAction
        self.requestedRoutingTargets = requestedRoutingTargets
        self.requestedRoutingReason = requestedRoutingReason
        self.protocolRepairCount = protocolRepairCount
        self.protocolRepairTypes = protocolRepairTypes
        self.protocolSafeDegradeApplied = protocolSafeDegradeApplied
        self.runtimeEvents = runtimeEvents
        self.primaryRuntimeEvent = primaryRuntimeEvent
        self.startedAt = startedAt
        let resolvedCompletedAt = completedAt ?? (status == .completed ? Date() : nil)
        self.completedAt = resolvedCompletedAt
        self.duration = resolvedCompletedAt?.timeIntervalSince(self.startedAt)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        nodeID = try container.decode(UUID.self, forKey: .nodeID)
        agentID = try container.decode(UUID.self, forKey: .agentID)
        status = try container.decode(ExecutionStatus.self, forKey: .status)
        output = try container.decodeIfPresent(String.self, forKey: .output) ?? ""
        outputType = try container.decodeIfPresent(ExecutionOutputType.self, forKey: .outputType) ?? .runtimeLog
        sessionID = try container.decodeIfPresent(String.self, forKey: .sessionID)
        executionIntent = try container.decodeIfPresent(String.self, forKey: .executionIntent)
        transportKind = try container.decodeIfPresent(String.self, forKey: .transportKind)
        firstChunkLatencyMs = try container.decodeIfPresent(Int.self, forKey: .firstChunkLatencyMs)
        completionLatencyMs = try container.decodeIfPresent(Int.self, forKey: .completionLatencyMs)
        routingAction = try container.decodeIfPresent(String.self, forKey: .routingAction)
        routingTargets = try container.decodeIfPresent([String].self, forKey: .routingTargets) ?? []
        routingReason = try container.decodeIfPresent(String.self, forKey: .routingReason)
        requestedRoutingAction = try container.decodeIfPresent(String.self, forKey: .requestedRoutingAction)
        requestedRoutingTargets = try container.decodeIfPresent([String].self, forKey: .requestedRoutingTargets) ?? []
        requestedRoutingReason = try container.decodeIfPresent(String.self, forKey: .requestedRoutingReason)
        protocolRepairCount = try container.decodeIfPresent(Int.self, forKey: .protocolRepairCount) ?? 0
        protocolRepairTypes = try container.decodeIfPresent([String].self, forKey: .protocolRepairTypes) ?? []
        protocolSafeDegradeApplied = try container.decodeIfPresent(Bool.self, forKey: .protocolSafeDegradeApplied) ?? false
        runtimeEvents = try container.decodeIfPresent([OpenClawRuntimeEvent].self, forKey: .runtimeEvents) ?? []
        primaryRuntimeEvent = try container.decodeIfPresent(OpenClawRuntimeEvent.self, forKey: .primaryRuntimeEvent)
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
        try container.encodeIfPresent(sessionID, forKey: .sessionID)
        try container.encodeIfPresent(executionIntent, forKey: .executionIntent)
        try container.encodeIfPresent(transportKind, forKey: .transportKind)
        try container.encodeIfPresent(firstChunkLatencyMs, forKey: .firstChunkLatencyMs)
        try container.encodeIfPresent(completionLatencyMs, forKey: .completionLatencyMs)
        try container.encodeIfPresent(routingAction, forKey: .routingAction)
        try container.encode(routingTargets, forKey: .routingTargets)
        try container.encodeIfPresent(routingReason, forKey: .routingReason)
        try container.encodeIfPresent(requestedRoutingAction, forKey: .requestedRoutingAction)
        try container.encode(requestedRoutingTargets, forKey: .requestedRoutingTargets)
        try container.encodeIfPresent(requestedRoutingReason, forKey: .requestedRoutingReason)
        try container.encode(protocolRepairCount, forKey: .protocolRepairCount)
        try container.encode(protocolRepairTypes, forKey: .protocolRepairTypes)
        try container.encode(protocolSafeDegradeApplied, forKey: .protocolSafeDegradeApplied)
        try container.encode(runtimeEvents, forKey: .runtimeEvents)
        try container.encodeIfPresent(primaryRuntimeEvent, forKey: .primaryRuntimeEvent)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encodeIfPresent(completedAt, forKey: .completedAt)
        try container.encodeIfPresent(duration, forKey: .duration)
    }
}

extension ExecutionResult {
    var runtimeRefCount: Int {
        runtimeEvents.reduce(0) { $0 + $1.refs.count }
    }

    var runtimeEventTypesSummary: String {
        Array(Set(runtimeEvents.map(\.eventType.rawValue)))
            .sorted()
            .joined(separator: ", ")
    }

    var summaryText: String {
        if let primaryRuntimeEvent,
           !primaryRuntimeEvent.summaryText.isEmpty {
            return primaryRuntimeEvent.summaryText
        }

        if let latestSummary = runtimeEvents
            .map(\.summaryText)
            .last(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return latestSummary
        }

        return output
    }

    var previewText: String {
        summaryText.compactSingleLinePreview(limit: 160)
    }

    var renderedOutputText: String {
        let summary = summaryText.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)

        if !summary.isEmpty && summary != rawOutput {
            if rawOutput.isEmpty {
                return summary
            }
            return "\(summary)\n\n\(rawOutput)"
        }

        if !rawOutput.isEmpty {
            return rawOutput
        }

        return summary
    }

    var runtimeEventsText: String? {
        let lines = runtimeEvents.map(\.summaryLine)
        guard !lines.isEmpty else { return nil }
        return lines.joined(separator: "\n")
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

enum TransportBenchmarkKind: String, Codable, CaseIterable, Identifiable {
    case gatewayChat = "gateway_chat"
    case gatewayAgent = "gateway_agent"
    case workflowHotPath = "workflow_hot_path"
    case cli = "cli"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gatewayChat:
            return "Gateway Chat"
        case .gatewayAgent:
            return "Gateway Agent"
        case .workflowHotPath:
            return "Workflow Hot Path"
        case .cli:
            return "CLI"
        }
    }
}

struct TransportBenchmarkSample: Codable, Identifiable {
    let id: UUID
    let transport: TransportBenchmarkKind
    let iteration: Int
    let success: Bool
    let sessionID: String?
    let actualTransportKind: String?
    let startedAt: Date
    let completedAt: Date
    let firstChunkLatencyMs: Int?
    let completionLatencyMs: Int?
    let previewText: String
    let errorText: String?

    init(
        transport: TransportBenchmarkKind,
        iteration: Int,
        success: Bool,
        sessionID: String?,
        actualTransportKind: String?,
        startedAt: Date,
        completedAt: Date,
        firstChunkLatencyMs: Int?,
        completionLatencyMs: Int?,
        previewText: String,
        errorText: String?
    ) {
        self.id = UUID()
        self.transport = transport
        self.iteration = iteration
        self.success = success
        self.sessionID = sessionID
        self.actualTransportKind = actualTransportKind
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.firstChunkLatencyMs = firstChunkLatencyMs
        self.completionLatencyMs = completionLatencyMs
        self.previewText = previewText
        self.errorText = errorText
    }
}

struct TransportBenchmarkSummary: Codable, Identifiable {
    let transport: TransportBenchmarkKind
    let sampleCount: Int
    let successCount: Int
    let failureCount: Int
    let actualTransportKinds: [String]
    let expectedTransportKind: String?
    let expectedTransportMatchedCount: Int
    let expectedTransportMismatchCount: Int
    let averageFirstChunkLatencyMs: Double?
    let averageCompletionLatencyMs: Double?
    let fastestCompletionLatencyMs: Int?
    let slowestCompletionLatencyMs: Int?

    var id: String { transport.rawValue }
}

struct TransportBenchmarkReport: Codable, Identifiable {
    let id: UUID
    let deploymentKind: OpenClawDeploymentKind
    let agentIdentifier: String
    let prompt: String
    let iterationsPerTransport: Int
    let startedAt: Date
    let completedAt: Date
    let samples: [TransportBenchmarkSample]
    let summaries: [TransportBenchmarkSummary]
    let reportFilePath: String?
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
    let sessionID: String?
    let agentID: UUID?
    
    enum LogLevel: String, Codable {
        case info = "INFO"
        case warning = "WARN"
        case error = "ERROR"
        case success = "SUCCESS"
    }
    
    init(
        level: LogLevel,
        message: String,
        nodeID: UUID? = nil,
        sessionID: String? = nil,
        agentID: UUID? = nil
    ) {
        self.id = UUID()
        self.timestamp = Date()
        self.level = level
        self.message = message
        self.nodeID = nodeID
        let normalizedSessionID = sessionID?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.sessionID = (normalizedSessionID?.isEmpty == false) ? normalizedSessionID : nil
        self.agentID = agentID
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
    var runtimeEvents: [OpenClawRuntimeEvent]
    var startTime: Date
    var lastUpdated: Date
    var isPaused: Bool
    var canResume: Bool

    enum CodingKeys: String, CodingKey {
        case workflowID
        case currentStep
        case totalSteps
        case completedNodes
        case failedNodes
        case runtimeEvents
        case startTime
        case lastUpdated
        case isPaused
        case canResume
    }
    
    init(workflowID: UUID, totalSteps: Int) {
        self.workflowID = workflowID
        self.currentStep = 0
        self.totalSteps = totalSteps
        self.completedNodes = []
        self.failedNodes = []
        self.runtimeEvents = []
        self.startTime = Date()
        self.lastUpdated = Date()
        self.isPaused = false
        self.canResume = false
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        workflowID = try container.decode(UUID.self, forKey: .workflowID)
        currentStep = try container.decodeIfPresent(Int.self, forKey: .currentStep) ?? 0
        totalSteps = try container.decodeIfPresent(Int.self, forKey: .totalSteps) ?? 0
        completedNodes = try container.decodeIfPresent([UUID].self, forKey: .completedNodes) ?? []
        failedNodes = try container.decodeIfPresent([UUID].self, forKey: .failedNodes) ?? []
        runtimeEvents = try container.decodeIfPresent([OpenClawRuntimeEvent].self, forKey: .runtimeEvents) ?? []
        startTime = try container.decodeIfPresent(Date.self, forKey: .startTime) ?? Date()
        lastUpdated = try container.decodeIfPresent(Date.self, forKey: .lastUpdated) ?? Date()
        isPaused = try container.decodeIfPresent(Bool.self, forKey: .isPaused) ?? false
        canResume = try container.decodeIfPresent(Bool.self, forKey: .canResume) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(workflowID, forKey: .workflowID)
        try container.encode(currentStep, forKey: .currentStep)
        try container.encode(totalSteps, forKey: .totalSteps)
        try container.encode(completedNodes, forKey: .completedNodes)
        try container.encode(failedNodes, forKey: .failedNodes)
        try container.encode(runtimeEvents, forKey: .runtimeEvents)
        try container.encode(startTime, forKey: .startTime)
        try container.encode(lastUpdated, forKey: .lastUpdated)
        try container.encode(isPaused, forKey: .isPaused)
        try container.encode(canResume, forKey: .canResume)
    }
}

class OpenClawService: ObservableObject {
    private struct ActiveGatewayConversation: Sendable {
        let record: WorkbenchActiveRunRecord

        var threadID: String { record.threadID }
        var runID: String { record.runID }
        var sessionKey: String { record.sessionKey }
        var startedAt: Date { record.startedAt }
        var isAborting: Bool { record.status == .stopping }
    }

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
    @Published var activeGatewayRunID: String?
    @Published var activeGatewaySessionKey: String?
    @Published var isAbortingActiveGatewayRun = false
    @Published private var activeGatewayConversations: [String: ActiveGatewayConversation] = [:]
    @Published private(set) var activeWorkbenchRuns: [WorkbenchActiveRunRecord] = []
    @Published var isRunningTransportBenchmark = false
    @Published var transportBenchmarkReport: TransportBenchmarkReport?
    @Published var transportBenchmarkError: String?
    var currentProjectProvider: (() -> MAProject?)?
    
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
        enum Action: String, CaseIterable {
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
        let sessionID: String?
        let transportKind: String?
        let firstChunkLatencyMs: Int?
        let completionLatencyMs: Int?
        let routingDecision: WorkflowRoutingDecision?

        init(
            text: String,
            type: ExecutionOutputType,
            sessionID: String? = nil,
            transportKind: String? = nil,
            firstChunkLatencyMs: Int? = nil,
            completionLatencyMs: Int? = nil,
            routingDecision: WorkflowRoutingDecision? = nil
        ) {
            self.text = text
            self.type = type
            self.sessionID = sessionID
            self.transportKind = transportKind
            self.firstChunkLatencyMs = firstChunkLatencyMs
            self.completionLatencyMs = completionLatencyMs
            self.routingDecision = routingDecision
        }
    }

    private struct RoutingTargetDescriptor {
        let node: WorkflowNode
        let agent: Agent
        let resolvedIdentifier: String
    }

    private struct RuntimeRetryPolicy {
        let allowRetry: Bool
        let maxRetries: Int
    }

    private struct AgentCLICapabilities {
        var supportsQuiet: Bool
        var supportsLogLevel: Bool
        var supportsJSONOnly: Bool
    }

    private struct RuntimeDispatchGuardrails {
        let directTargets: [RoutingTargetDescriptor]
        let approvalRequiredTargets: [RoutingTargetDescriptor]
        let writeScope: [String]
        let toolScope: [String]
        let fallbackRoutingPolicy: WorkflowFallbackRoutingPolicy

        var requiresApproval: Bool {
            !approvalRequiredTargets.isEmpty
        }
    }

    private struct ProtocolDispatchCapsule {
        let protocolVersion: String
        let allowedActions: [String]
        let allowedTargets: [String]
        let approvalTargets: [String]
        let writeScope: [String]
        let toolScope: [String]
        let fallbackPolicy: String
        let requiredOutputContract: String
        let selfCheckRule: String
        let feedbackHints: [String]
    }

    private struct RoutingDecisionValidation {
        let sanitizedDecision: WorkflowRoutingDecision?
        let approvalRequiredTargets: [RoutingTargetDescriptor]
        let rejectedTargets: [String]
    }

    private struct RoutingDecisionRepair {
        let requestedDecision: WorkflowRoutingDecision?
        let sanitizedDecision: WorkflowRoutingDecision?
        let approvalRequiredTargets: [RoutingTargetDescriptor]
        let rejectedTargets: [String]
        let repairTypes: [String]
        let safeDegradeApplied: Bool
    }

    private struct RuntimeRegistrationContext {
        let project: MAProject
        let workflowID: UUID?
    }

    private struct RuntimeExecutionAdmission {
        let allowed: Bool
        let note: String?
        let blockingMessage: String?
    }
    
    // 初始化时检测连接状态
    init() {
        checkConnection()
        loadExecutionState()
    }

    func restoreExecutionSnapshot(
        results: [ExecutionResult],
        logs: [ExecutionLogEntry],
        state: ExecutionState? = nil,
        activeWorkbenchRuns: [WorkbenchActiveRunRecord] = []
    ) {
        executionResults = results
        executionLogs = logs
        executionState = state
        isExecuting = false
        currentStep = 0
        totalSteps = 0
        currentNodeID = nil
        lastError = nil
        restoreActiveGatewayConversations(from: activeWorkbenchRuns)
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
        clearActiveGatewayConversation()
    }
    
    // MARK: - 日志方法
    
    func addLog(
        _ level: ExecutionLogEntry.LogLevel,
        _ message: String,
        nodeID: UUID? = nil,
        sessionID: String? = nil,
        agentID: UUID? = nil
    ) {
        let entry = ExecutionLogEntry(
            level: level,
            message: message,
            nodeID: nodeID,
            sessionID: sessionID,
            agentID: agentID
        )
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

    private func normalizedActiveGatewayConversationThreadID(
        _ threadID: String?,
        sessionKey: String? = nil
    ) -> String? {
        let normalizedThreadID = threadID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !normalizedThreadID.isEmpty {
            return normalizedThreadID
        }

        let normalizedSessionKey = sessionKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !normalizedSessionKey.isEmpty else { return nil }
        return "session:\(normalizedSessionKey)"
    }

    @MainActor
    private func syncActiveGatewayConversationSnapshot() {
        activeWorkbenchRuns = activeGatewayConversations.values
            .map(\.record)
            .sorted { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return lhs.id > rhs.id
            }

        if let latestConversation = activeGatewayConversations.values.max(by: { lhs, rhs in
            if lhs.startedAt == rhs.startedAt {
                return lhs.threadID < rhs.threadID
            }
            return lhs.startedAt < rhs.startedAt
        }) {
            activeGatewayRunID = latestConversation.runID
            activeGatewaySessionKey = latestConversation.sessionKey
            isAbortingActiveGatewayRun = latestConversation.isAborting
        } else {
            activeGatewayRunID = nil
            activeGatewaySessionKey = nil
            isAbortingActiveGatewayRun = false
        }
    }

    @MainActor
    private func restoreActiveGatewayConversations(from records: [WorkbenchActiveRunRecord]) {
        activeGatewayConversations = records.reduce(into: [:]) { partialResult, record in
            partialResult[record.threadID] = ActiveGatewayConversation(record: record)
        }
        syncActiveGatewayConversationSnapshot()
    }

    @MainActor
    private func activeGatewayConversation(threadID: String?) -> ActiveGatewayConversation? {
        if let normalizedThreadID = normalizedActiveGatewayConversationThreadID(threadID) {
            return activeGatewayConversations[normalizedThreadID]
        }

        return activeGatewayConversations.values.max(by: { lhs, rhs in
            if lhs.startedAt == rhs.startedAt {
                return lhs.threadID < rhs.threadID
            }
            return lhs.startedAt < rhs.startedAt
        })
    }

    @MainActor
    private func setActiveGatewayConversation(
        threadID: String?,
        workflowID: UUID?,
        runID: String,
        sessionKey: String,
        transportKind: String,
        executionIntent: OpenClawRuntimeExecutionIntent
    ) {
        guard let normalizedThreadID = normalizedActiveGatewayConversationThreadID(
            threadID,
            sessionKey: sessionKey
        ) else {
            activeGatewayRunID = runID
            activeGatewaySessionKey = sessionKey
            isAbortingActiveGatewayRun = false
            return
        }

        activeGatewayConversations[normalizedThreadID] = ActiveGatewayConversation(
            record: WorkbenchActiveRunRecord(
                threadID: normalizedThreadID,
                workflowID: workflowID?.uuidString ?? "",
                runID: runID,
                sessionKey: sessionKey,
                transportKind: transportKind,
                executionIntent: executionIntent.rawValue,
                startedAt: Date(),
                updatedAt: Date(),
                status: .running
            )
        )
        syncActiveGatewayConversationSnapshot()
    }

    @MainActor
    private func clearActiveGatewayConversation(threadID: String? = nil, sessionKey: String? = nil) {
        if let normalizedThreadID = normalizedActiveGatewayConversationThreadID(
            threadID,
            sessionKey: sessionKey
        ) {
            activeGatewayConversations.removeValue(forKey: normalizedThreadID)
        } else {
            activeGatewayConversations.removeAll()
        }
        syncActiveGatewayConversationSnapshot()
    }

    @MainActor
    private func updateActiveGatewayConversationAbortState(
        threadID: String?,
        isAborting: Bool
    ) -> ActiveGatewayConversation? {
        guard let conversation = activeGatewayConversation(threadID: threadID) else {
            return nil
        }

        activeGatewayConversations[conversation.threadID] = ActiveGatewayConversation(
            record: WorkbenchActiveRunRecord(
                id: conversation.record.id,
                threadID: conversation.record.threadID,
                workflowID: conversation.record.workflowID,
                runID: conversation.record.runID,
                sessionKey: conversation.record.sessionKey,
                transportKind: conversation.record.transportKind,
                executionIntent: conversation.record.executionIntent,
                startedAt: conversation.record.startedAt,
                updatedAt: Date(),
                status: isAborting ? .stopping : .running
            )
        )
        syncActiveGatewayConversationSnapshot()
        return activeGatewayConversations[conversation.threadID]
    }

    @MainActor
    func hasActiveRemoteConversation(threadID: String?) -> Bool {
        activeGatewayConversation(threadID: threadID) != nil
    }

    @MainActor
    func isAbortingRemoteConversation(threadID: String?) -> Bool {
        activeGatewayConversation(threadID: threadID)?.isAborting ?? false
    }

    @MainActor
    func activeWorkbenchRunRecord(threadID: String?) -> WorkbenchActiveRunRecord? {
        activeGatewayConversation(threadID: threadID)?.record
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
            clearActiveGatewayConversation()
        case .error(let message):
            connectionStatus = .error(message)
            isConnected = false
            lastError = message
            clearActiveGatewayConversation()
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

    @MainActor
    func abortActiveRemoteConversation(threadID: String? = nil) {
        let manager = OpenClawManager.shared
        let connectionConfig = manager.config
        guard let gatewayConfig = manager.preferredGatewayConfig(using: connectionConfig) else {
            addLog(.warning, "Abort ignored: no available gateway transport for the active conversation.")
            return
        }

        guard let trackedConversation = activeGatewayConversation(threadID: threadID) else {
            addLog(.warning, "Abort ignored: no active gateway chat run is tracked.")
            return
        }

        let sessionKey = trackedConversation.sessionKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let runID = trackedConversation.runID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sessionKey.isEmpty, !runID.isEmpty else {
            addLog(.warning, "Abort ignored: no active gateway chat run is tracked.")
            return
        }

        guard !trackedConversation.isAborting else { return }

        _ = updateActiveGatewayConversationAbortState(threadID: trackedConversation.threadID, isAborting: true)
        addLog(.info, "Requesting gateway chat abort for run \(runID) in session \(sessionKey).")

        _Concurrency.Task { [weak self] in
            guard let self else { return }
            do {
                try await manager.abortGatewayChatRun(
                    sessionKey: sessionKey,
                    runID: runID,
                    using: gatewayConfig
                )
                self.addLog(.info, "Gateway chat abort accepted for run \(runID).")
            } catch {
                await MainActor.run {
                    _ = self.updateActiveGatewayConversationAbortState(
                        threadID: trackedConversation.threadID,
                        isAborting: false
                    )
                    self.lastError = error.localizedDescription
                }
                self.addLog(.error, "Failed to abort gateway chat run \(runID): \(error.localizedDescription)")
            }
        }
    }
    
    // 执行工作流 - 真正调用OpenClaw
    func executeWorkflow(
        _ workflow: Workflow,
        agents: [Agent],
        prompt: String? = nil,
        projectID: UUID? = nil,
        projectRuntimeSessionID: String? = nil,
        threadID: String? = nil,
        executionIntent: OpenClawRuntimeExecutionIntent = .workflowControlled,
        startingNodes: [WorkflowNode]? = nil,
        entryNodeIDsOverride: Set<UUID>? = nil,
        preloadedResults: [ExecutionResult] = [],
        precompletedNodeIDs: [UUID] = [],
        agentOutputMode: AgentOutputMode = .structuredJSON,
        onNodeStream: ((NodeStreamUpdate) -> Void)? = nil,
        onNodeDispatched: ((OpenClawRuntimeEvent) -> Void)? = nil,
        onNodeAccepted: ((OpenClawRuntimeEvent) -> Void)? = nil,
        onNodeProgress: ((OpenClawRuntimeEvent) -> Void)? = nil,
        onNodeCompleted: ((ExecutionResult) -> Void)? = nil,
        completion: @escaping ([ExecutionResult]) -> Void
    ) {
        let manager = OpenClawManager.shared
        guard manager.canRunWorkflow else {
            let healthMessage = manager.connectionState.health.lastMessage?.trimmingCharacters(in: .whitespacesAndNewlines)
            let failureMessage = healthMessage?.isEmpty == false
                ? healthMessage!
                : "OpenClaw runtime is not runnable under the current capability state."
            lastError = failureMessage
            addLog(.error, "Cannot execute workflow: \(failureMessage)")
            completion([])
            return
        }

        let executionAdmission = runtimeExecutionAdmission(
            for: executionIntent,
            projectID: projectID
        )
        if let note = executionAdmission.note {
            addLog(.info, note)
        }
        guard executionAdmission.allowed else {
            let failureMessage = executionAdmission.blockingMessage ?? "OpenClaw runtime admission check failed."
            lastError = failureMessage
            addLog(.error, failureMessage)
            completion([])
            return
        }

        let isolationAssessment = manager.runtimeIsolationAssessment(for: workflow, agents: agents)
        if !isolationAssessment.advisoryMessages.isEmpty {
            let message = isolationAssessment.advisoryMessages.joined(separator: " | ")
            addLog(.warning, "Runtime isolation advisory: \(message)")
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
            projectID: projectID,
            projectRuntimeSessionID: projectRuntimeSessionID,
            threadID: threadID,
            executionIntent: executionIntent,
            entryNodeIDs: effectiveEntryNodeIDs,
            seedResults: preloadedResults,
            agentOutputMode: agentOutputMode,
            onNodeStream: onNodeStream,
            onNodeDispatched: onNodeDispatched,
            onNodeAccepted: onNodeAccepted,
            onNodeProgress: onNodeProgress,
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
        projectID: UUID? = nil,
        sessionID: String? = nil,
        threadID: String? = nil,
        thinkingLevel: AgentThinkingLevel = .off,
        onStream: ((String) -> Void)? = nil,
        onDispatched: ((OpenClawRuntimeEvent) -> Void)? = nil,
        onAccepted: ((OpenClawRuntimeEvent) -> Void)? = nil,
        onProgress: ((OpenClawRuntimeEvent) -> Void)? = nil,
        completion: @escaping (WorkbenchEntryExecution) -> Void
    ) {
        let isolationAssessment = OpenClawManager.shared.runtimeIsolationAssessment(for: workflow, agents: agents)
        if !isolationAssessment.advisoryMessages.isEmpty {
            let message = isolationAssessment.advisoryMessages.joined(separator: " | ")
            addLog(.warning, "Runtime isolation advisory for workbench entry: \(message)", nodeID: node.id)
        }

        guard let agentID = node.agentID,
              let agent = agents.first(where: { $0.id == agentID }) else {
            let failedResult = ExecutionResult(
                nodeID: node.id,
                agentID: UUID(),
                status: .failed,
                output: "Agent not found for node",
                outputType: .errorSummary,
                executionIntent: OpenClawRuntimeExecutionIntent.conversationAutonomous.rawValue
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
        let guardrails = runtimeDispatchGuardrails(
            for: agent,
            node: node,
            workflow: workflow,
            projectID: projectID,
            outgoingEdges: outgoingEdges,
            agents: agents
        )

        executeNodeOnOpenClaw(
            node: node,
            agent: agent,
            workflowID: workflow.id,
            prompt: prompt,
            executionIntent: .conversationAutonomous,
            isEntryNode: true,
            downstreamTargets: downstreamTargets,
            guardrails: guardrails,
            instructionStyle: .fastWorkbenchEntry,
            sessionID: sessionID,
            threadID: threadID,
            thinkingLevel: thinkingLevel,
            trackActiveRemoteRun: true,
            outputMode: .plainStreaming,
            onDispatched: onDispatched,
            onAccepted: onAccepted,
            onProgress: onProgress,
            onStream: onStream
        ) { [weak self] result, routingDecision in
            guard let self else { return }
            let resolvedTargets = self.resolveRoutingTargets(
                from: routingDecision,
                availableTargets: downstreamTargets,
                node: node,
                outputType: result.outputType,
                fallbackPolicy: workflow.fallbackRoutingPolicy,
                sessionID: result.sessionID,
                agentID: agent.id
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
        projectID: UUID?,
        projectRuntimeSessionID: String?,
        threadID: String?,
        executionIntent: OpenClawRuntimeExecutionIntent,
        entryNodeIDs: Set<UUID>,
        seedResults: [ExecutionResult] = [],
        agentOutputMode: AgentOutputMode,
        onNodeStream: ((NodeStreamUpdate) -> Void)? = nil,
        onNodeDispatched: ((OpenClawRuntimeEvent) -> Void)? = nil,
        onNodeAccepted: ((OpenClawRuntimeEvent) -> Void)? = nil,
        onNodeProgress: ((OpenClawRuntimeEvent) -> Void)? = nil,
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
            let queuedSessionID: String?
            if let agentID = node.agentID {
                queuedSessionID = workflowNodeSessionID(
                    projectRuntimeSessionID: projectRuntimeSessionID,
                    workflowID: workflow.id,
                    nodeID: node.id,
                    agentID: agentID
                )
            } else {
                queuedSessionID = nil
            }
            addLog(
                .info,
                "Queued downstream node \(nodeLabel): \(reason)",
                nodeID: node.id,
                sessionID: queuedSessionID,
                agentID: node.agentID
            )
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

            guard let agentID = node.agentID,
                  let agent = agentByID[agentID] else {
                let result = ExecutionResult(
                    nodeID: node.id,
                    agentID: UUID(),
                    status: .failed,
                    output: "Agent not found for node",
                    outputType: .errorSummary,
                    executionIntent: executionIntent.rawValue
                )
                results.append(result)
                executionState?.failedNodes.append(node.id)
                addLog(.error, "Agent not found for node", nodeID: node.id)
                executeNext()
                return
            }

            let nodeSessionID = workflowNodeSessionID(
                projectRuntimeSessionID: projectRuntimeSessionID,
                workflowID: workflow.id,
                nodeID: node.id,
                agentID: agent.id
            )
            addLog(
                .info,
                "Executing node \(currentStep)/\(totalSteps)",
                nodeID: node.id,
                sessionID: nodeSessionID,
                agentID: agent.id
            )
            let guardrails = self.runtimeDispatchGuardrails(
                for: agent,
                node: node,
                workflow: workflow,
                projectID: projectID,
                outgoingEdges: outgoingEdges,
                agents: agents
            )
            
            // 调用OpenClaw执行节点
            executeNodeOnOpenClaw(
                node: node,
                agent: agent,
                workflowID: workflow.id,
                prompt: prompt,
                executionIntent: executionIntent,
                isEntryNode: entryNodeIDs.contains(node.id),
                downstreamTargets: guardrails.directTargets,
                guardrails: guardrails,
                sessionID: nodeSessionID,
                threadID: threadID,
                outputMode: agentOutputMode,
                onDispatched: onNodeDispatched,
                onAccepted: onNodeAccepted,
                onProgress: onNodeProgress,
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
                self.executionState?.runtimeEvents.append(contentsOf: result.runtimeEvents)
                onNodeCompleted?(result)

                // 更新执行状态
                if result.status == .completed {
                    self.executionState?.completedNodes.append(node.id)
                    self.addLog(
                        .success,
                        "Node completed: \(agent.name)",
                        nodeID: node.id,
                        sessionID: result.sessionID ?? nodeSessionID,
                        agentID: agent.id
                    )

                    let selectedTargets = self.resolveRoutingTargets(
                        from: routingDecision,
                        availableTargets: guardrails.directTargets,
                        node: node,
                        outputType: result.outputType,
                        fallbackPolicy: workflow.fallbackRoutingPolicy,
                        sessionID: result.sessionID ?? nodeSessionID,
                        agentID: agent.id
                    )
                    for target in selectedTargets {
                        enqueue(target.node, because: routingDecision?.reason ?? "routed by \(agent.name)")
                    }
                } else {
                    self.executionState?.failedNodes.append(node.id)
                    let failureSummary = result.summaryText.compactSingleLinePreview(limit: 160)
                    self.addLog(
                        .error,
                        "Node failed: \(agent.name) - \(failureSummary)",
                        nodeID: node.id,
                        sessionID: result.sessionID ?? nodeSessionID,
                        agentID: agent.id
                    )
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
        workflowID: UUID? = nil,
        prompt: String?,
        executionIntent: OpenClawRuntimeExecutionIntent = .workflowControlled,
        isEntryNode: Bool = false,
        downstreamTargets: [RoutingTargetDescriptor] = [],
        guardrails: RuntimeDispatchGuardrails? = nil,
        instructionStyle: WorkflowInstructionStyle = .standard,
        sessionID: String? = nil,
        threadID: String? = nil,
        thinkingLevel: AgentThinkingLevel? = nil,
        trackActiveRemoteRun: Bool = false,
        outputMode: AgentOutputMode = .structuredJSON,
        dispatchAttempt: Int = 1,
        dispatchIdempotencyKey: String? = nil,
        onDispatched: ((OpenClawRuntimeEvent) -> Void)? = nil,
        onAccepted: ((OpenClawRuntimeEvent) -> Void)? = nil,
        onProgress: ((OpenClawRuntimeEvent) -> Void)? = nil,
        onStream: ((String) -> Void)? = nil,
        completion: @escaping (ExecutionResult, WorkflowRoutingDecision?) -> Void
    ) {
        let nodeStartedAt = Date()
        let targetAgentID = resolvedAgentIdentifier(for: agent)
        let normalizedSessionID = sessionID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTransportKind = runtimeTransportKind(
            for: outputMode,
            sessionID: normalizedSessionID,
            executionIntent: executionIntent
        )
        let retryPolicy = runtimeRetryPolicy(isEntryNode: isEntryNode)
        let runtimeIdempotencyKey = dispatchIdempotencyKey ?? UUID().uuidString
        let effectiveGuardrails = guardrails ?? RuntimeDispatchGuardrails(
            directTargets: downstreamTargets,
            approvalRequiredTargets: [],
            writeScope: runtimeWriteScope(for: agent),
            toolScope: runtimeToolScope(for: agent, directTargets: downstreamTargets, approvalTargets: []),
            fallbackRoutingPolicy: .stop
        )
        let protocolMemory = resolvedProtocolMemory(for: agent)
        let dispatchCapsule = makeProtocolDispatchCapsule(
            for: agent,
            guardrails: effectiveGuardrails
        )
        let sessionProtocolDigest = makeSessionProtocolDigest(
            for: agent,
            capsule: dispatchCapsule,
            transportKind: resolvedTransportKind,
            isEntryNode: isEntryNode
        )
        let serializedWriteScope = effectiveGuardrails.writeScope.joined(separator: "|")
        let serializedToolScope = effectiveGuardrails.toolScope.joined(separator: "|")
        let dispatchEvent = makeRuntimeEvent(
            eventType: .taskDispatch,
            source: runtimeSystemActor(kind: .orchestrator, id: "workflow.executor"),
            target: runtimeAgentActor(id: targetAgentID, name: agent.name),
            transportKind: resolvedTransportKind,
            deploymentKind: OpenClawManager.shared.config.deploymentKind.rawValue,
            workflowID: workflowID,
            node: node,
            sessionKey: normalizedSessionID,
            executionIntent: executionIntent,
            idempotencyKey: runtimeIdempotencyKey,
            attempt: dispatchAttempt,
            payload: [
                "intent": "respond",
                "summary": (prompt?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                    ? prompt!.trimmingCharacters(in: .whitespacesAndNewlines)
                    : "execute workflow node"),
                "expectedOutput": outputMode == .structuredJSON ? "structured_result" : "plain_response",
                "visibleToUser": isEntryNode ? "true" : "false",
                "protocolVersion": dispatchCapsule.protocolVersion,
                "allowedActions": dispatchCapsule.allowedActions.joined(separator: ","),
                "allowedTargets": dispatchCapsule.allowedTargets.joined(separator: " | "),
                "approvalTargets": dispatchCapsule.approvalTargets.joined(separator: " | "),
                "requiredOutputContract": dispatchCapsule.requiredOutputContract,
                "selfCheckRule": dispatchCapsule.selfCheckRule,
                "protocolFeedbackHints": dispatchCapsule.feedbackHints.joined(separator: " | "),
                "sessionProtocolDigest": sessionProtocolDigest
            ],
            constraints: [
                "timeoutSeconds": String(max(1, agentConfig.timeout)),
                "thinkingLevel": thinkingLevel?.rawValue ?? "off",
                "writeScope": serializedWriteScope,
                "toolScope": serializedToolScope
            ],
            control: [
                "requiresApproval": effectiveGuardrails.requiresApproval ? "true" : "false",
                "fallbackRoutingPolicy": effectiveGuardrails.fallbackRoutingPolicy.rawValue,
                "allowRetry": retryPolicy.allowRetry ? "true" : "false",
                "maxRetries": String(max(retryPolicy.maxRetries, 1))
            ]
        )
        onDispatched?(dispatchEvent)

        // 构建执行指令
        let instruction = buildInstruction(
            for: node,
            agent: agent,
            prompt: prompt,
            isEntryNode: isEntryNode,
            downstreamTargets: downstreamTargets,
            guardrails: effectiveGuardrails,
            protocolMemory: protocolMemory,
            protocolCapsule: dispatchCapsule,
            sessionProtocolDigest: sessionProtocolDigest,
            style: instructionStyle
        )

        let acceptedEvent = makeRuntimeEvent(
            eventType: .taskAccepted,
            source: runtimeAgentActor(id: targetAgentID, name: agent.name),
            target: runtimeSystemActor(kind: .orchestrator, id: "workflow.executor"),
            transportKind: resolvedTransportKind,
            deploymentKind: OpenClawManager.shared.config.deploymentKind.rawValue,
            workflowID: workflowID,
            node: node,
            sessionKey: normalizedSessionID,
            executionIntent: executionIntent,
            parentEventId: dispatchEvent.id,
            idempotencyKey: runtimeIdempotencyKey,
            attempt: dispatchAttempt,
            payload: [
                "accepted": "true",
                "status": "accepted"
            ]
        )
        onAccepted?(acceptedEvent)

        var progressEvent: OpenClawRuntimeEvent?
        func emitProgressIfNeeded(from chunk: String) {
            let summary = chunk
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .compactSingleLinePreview(limit: 120)
            guard !summary.isEmpty else { return }
            guard progressEvent == nil else { return }

            let event = makeRuntimeEvent(
                eventType: .taskProgress,
                source: runtimeAgentActor(id: targetAgentID, name: agent.name),
                target: runtimeSystemActor(kind: .orchestrator, id: "workflow.executor"),
                transportKind: resolvedTransportKind,
                deploymentKind: OpenClawManager.shared.config.deploymentKind.rawValue,
                workflowID: workflowID,
                node: node,
                sessionKey: normalizedSessionID,
                executionIntent: executionIntent,
                parentEventId: acceptedEvent.id,
                idempotencyKey: runtimeIdempotencyKey,
                attempt: dispatchAttempt,
                payload: [
                    "status": "running",
                    "summary": summary
                ]
            )
            progressEvent = event
            onProgress?(event)
        }

        // 调用openclaw agent命令
        callOpenClawAgent(
            instruction: instruction,
            agentIdentifier: targetAgentID,
            runtimeAgent: agent,
            workflowID: workflowID,
            sessionID: sessionID,
            threadID: threadID,
            executionIntent: executionIntent,
            thinkingLevel: thinkingLevel,
            trackActiveRemoteRun: trackActiveRemoteRun,
            outputMode: outputMode,
            onPartial: { chunk in
                emitProgressIfNeeded(from: chunk)
                onStream?(chunk)
            }
        ) { success, parsedOutput in
            let isTimeoutFailure = !success && self.isLikelyTimeoutFailure(parsedOutput.text)
            let canRetryAfterFailure = isTimeoutFailure
                && retryPolicy.allowRetry
                && dispatchAttempt < max(retryPolicy.maxRetries, 1)

            if canRetryAfterFailure {
                let nextAttempt = dispatchAttempt + 1
                self.addLog(
                    .warning,
                    "Node timed out: \(agent.name). Retrying attempt \(nextAttempt)/\(max(retryPolicy.maxRetries, 1)).",
                    nodeID: node.id,
                    sessionID: sessionID,
                    agentID: agent.id
                )
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                    guard let self else { return }
                    self.executeNodeOnOpenClaw(
                        node: node,
                        agent: agent,
                        workflowID: workflowID,
                        prompt: prompt,
                        executionIntent: executionIntent,
                        isEntryNode: isEntryNode,
                        downstreamTargets: downstreamTargets,
                        guardrails: effectiveGuardrails,
                        instructionStyle: instructionStyle,
                        sessionID: sessionID,
                        threadID: threadID,
                        thinkingLevel: thinkingLevel,
                        trackActiveRemoteRun: trackActiveRemoteRun,
                        outputMode: outputMode,
                        dispatchAttempt: nextAttempt,
                        dispatchIdempotencyKey: runtimeIdempotencyKey,
                        onDispatched: onDispatched,
                        onAccepted: onAccepted,
                        onProgress: onProgress,
                        onStream: onStream,
                        completion: completion
                    )
                }
                return
            }

            let routingRepair = self.repairRoutingDecision(
                parsedOutput.routingDecision,
                directTargets: effectiveGuardrails.directTargets,
                approvalTargets: effectiveGuardrails.approvalRequiredTargets,
                node: node,
                outputType: parsedOutput.type,
                fallbackPolicy: effectiveGuardrails.fallbackRoutingPolicy,
                sessionID: parsedOutput.sessionID ?? normalizedSessionID,
                agentID: agent.id
            )
            let status: ExecutionStatus = success ? .completed : .failed
            let completedAt = Date()
            let resultEvent = self.makeRuntimeEvent(
                eventType: success ? .taskResult : .taskError,
                source: self.runtimeAgentActor(id: targetAgentID, name: agent.name),
                target: self.runtimeSystemActor(kind: .orchestrator, id: "workflow.executor"),
                transportKind: resolvedTransportKind,
                deploymentKind: OpenClawManager.shared.config.deploymentKind.rawValue,
                workflowID: workflowID,
                node: node,
                sessionKey: parsedOutput.sessionID ?? normalizedSessionID,
                executionIntent: executionIntent,
                parentEventId: acceptedEvent.id,
                idempotencyKey: runtimeIdempotencyKey,
                attempt: dispatchAttempt,
                payload: success
                    ? [
                        "status": "success",
                        "outputType": parsedOutput.type.rawValue,
                        "summary": parsedOutput.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? "execution completed"
                            : parsedOutput.text.trimmingCharacters(in: .whitespacesAndNewlines)
                      ]
                    : [
                        "code": isTimeoutFailure ? "E_RUNTIME_DISPATCH_TIMEOUT" : "E_AGENT_EXECUTION_FAILED",
                        "message": parsedOutput.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? (isTimeoutFailure
                                ? "OpenClaw agent execution timed out."
                                : "OpenClaw agent execution failed.")
                            : parsedOutput.text.trimmingCharacters(in: .whitespacesAndNewlines),
                        "retryable": isTimeoutFailure && retryPolicy.allowRetry && dispatchAttempt < max(retryPolicy.maxRetries, 1)
                            ? "true"
                            : "false"
                      ]
            )
            let routeEvent = parsedOutput.routingDecision.map { decision in
                self.makeRuntimeEvent(
                    eventType: .taskRoute,
                    source: self.runtimeAgentActor(id: targetAgentID, name: agent.name),
                    target: self.runtimeSystemActor(kind: .orchestrator, id: "workflow.router"),
                    transportKind: resolvedTransportKind,
                    deploymentKind: OpenClawManager.shared.config.deploymentKind.rawValue,
                    workflowID: workflowID,
                    node: node,
                    sessionKey: parsedOutput.sessionID ?? normalizedSessionID,
                    executionIntent: executionIntent,
                    parentEventId: resultEvent.id,
                    payload: [
                        "action": decision.action.rawValue,
                        "targets": decision.targets.joined(separator: ","),
                        "reason": decision.reason ?? ""
                    ]
                )
            }
            let approvalEvents = routingRepair.approvalRequiredTargets.map { target in
                self.makeRuntimeEvent(
                    eventType: .taskApprovalRequired,
                    source: self.runtimeAgentActor(id: targetAgentID, name: agent.name),
                    target: self.runtimeSystemActor(kind: .orchestrator, id: "workflow.router"),
                    transportKind: resolvedTransportKind,
                    deploymentKind: OpenClawManager.shared.config.deploymentKind.rawValue,
                    workflowID: workflowID,
                    node: node,
                    sessionKey: parsedOutput.sessionID ?? normalizedSessionID,
                    executionIntent: executionIntent,
                    parentEventId: routeEvent?.id ?? resultEvent.id,
                    payload: [
                        "approvalScope": "edge",
                        "approvalKey": "\(node.id.uuidString)->\(target.node.id.uuidString)",
                        "requestedAction": "route",
                        "targetAgentId": target.resolvedIdentifier,
                        "reason": "Routing to \(target.agent.name) requires operator approval."
                    ]
                )
            }
            let runtimeEvents =
                [dispatchEvent, acceptedEvent]
                + (progressEvent.map { [$0] } ?? [])
                + [resultEvent]
                + (routeEvent.map { [$0] } ?? [])
                + approvalEvents
            let result = ExecutionResult(
                nodeID: node.id,
                agentID: agent.id,
                status: status,
                output: parsedOutput.text,
                outputType: parsedOutput.type,
                sessionID: parsedOutput.sessionID,
                executionIntent: executionIntent.rawValue,
                transportKind: parsedOutput.transportKind,
                firstChunkLatencyMs: parsedOutput.firstChunkLatencyMs,
                completionLatencyMs: parsedOutput.completionLatencyMs,
                routingAction: routingRepair.sanitizedDecision?.action.rawValue,
                routingTargets: routingRepair.sanitizedDecision?.targets ?? [],
                routingReason: routingRepair.sanitizedDecision?.reason ?? parsedOutput.routingDecision?.reason,
                requestedRoutingAction: parsedOutput.routingDecision?.action.rawValue,
                requestedRoutingTargets: parsedOutput.routingDecision?.targets ?? [],
                requestedRoutingReason: parsedOutput.routingDecision?.reason,
                protocolRepairCount: routingRepair.repairTypes.count,
                protocolRepairTypes: routingRepair.repairTypes,
                protocolSafeDegradeApplied: routingRepair.safeDegradeApplied,
                runtimeEvents: runtimeEvents,
                primaryRuntimeEvent: approvalEvents.last ?? routeEvent ?? resultEvent,
                startedAt: nodeStartedAt,
                completedAt: completedAt
            )
            completion(result, routingRepair.sanitizedDecision)
        }
    }

    private func runtimeAgentActor(id: String, name: String? = nil) -> OpenClawRuntimeActor {
        OpenClawRuntimeActor(kind: .agent, agentId: id, agentName: name)
    }

    private func runtimeSystemActor(kind: OpenClawRuntimeActorKind, id: String) -> OpenClawRuntimeActor {
        OpenClawRuntimeActor(kind: kind, agentId: id, agentName: id)
    }

    private func runtimeTransportKind(
        for outputMode: AgentOutputMode,
        sessionID: String?,
        executionIntent: OpenClawRuntimeExecutionIntent
    ) -> String {
        let deploymentKind = OpenClawManager.shared.config.deploymentKind
        return OpenClawTransportRouting.runtimeTransportKind(
            deploymentKind: deploymentKind,
            outputMode: outputMode,
            sessionID: sessionID,
            executionIntent: executionIntent
        ).rawValue
    }

    private func runtimeExecutionAdmission(
        for executionIntent: OpenClawRuntimeExecutionIntent,
        projectID: UUID?
    ) -> RuntimeExecutionAdmission {
        let manager = OpenClawManager.shared
        let config = manager.config

        guard executionIntent.requiresPersistentPublish else {
            if executionIntent == .conversationAutonomous || executionIntent == .inspectionReadonly,
               config.deploymentKind != .remoteServer,
               let projectID,
               let project = currentProjectProvider?(),
               project.id == projectID {
                if !manager.hasAttachedProjectSession || manager.attachedProjectID != project.id {
                    return RuntimeExecutionAdmission(
                        allowed: true,
                        note: "当前 \(executionIntent.displayName) 将以轻绑定方式继续运行；当前项目尚未强绑定到 OpenClaw 会话，因此不会要求 persistent publish。",
                        blockingMessage: nil
                    )
                }

                if project.runtimeState.workflowConfigurationRevision > project.runtimeState.appliedToMirrorConfigurationRevision {
                    return RuntimeExecutionAdmission(
                        allowed: true,
                        note: "当前 \(executionIntent.displayName) 检测到项目镜像仍有待准备变更，将按 ephemeral publish 语义继续运行，不写入正式 runtime published revision。",
                        blockingMessage: nil
                    )
                }

                if project.runtimeState.appliedToMirrorConfigurationRevision > project.runtimeState.syncedToRuntimeConfigurationRevision
                    || manager.sessionLifecycle.hasPendingMirrorChanges {
                    return RuntimeExecutionAdmission(
                        allowed: true,
                        note: "当前 \(executionIntent.displayName) 检测到 runtime published revision 落后于项目镜像，将按 ephemeral publish 语义继续运行。",
                        blockingMessage: nil
                    )
                }
            }

            return RuntimeExecutionAdmission(allowed: true, note: nil, blockingMessage: nil)
        }

        guard config.deploymentKind != .remoteServer else {
            return RuntimeExecutionAdmission(
                allowed: true,
                note: "当前 run.controlled 运行在 remoteServer 模式，项目级 persistent publish 门槛暂不强制阻塞。",
                blockingMessage: nil
            )
        }

        guard let projectID,
              let project = currentProjectProvider?(),
              project.id == projectID else {
            return RuntimeExecutionAdmission(
                allowed: true,
                note: "当前 run.controlled 缺少可验证的项目快照上下文，已跳过 persistent publish 准入校验。",
                blockingMessage: nil
            )
        }

        guard manager.hasAttachedProjectSession, manager.attachedProjectID == project.id else {
            return RuntimeExecutionAdmission(
                allowed: false,
                note: nil,
                blockingMessage: "当前 run.controlled 需要先完成 Bind：请先附着当前项目到 OpenClaw 会话。"
            )
        }

        guard project.runtimeState.workflowConfigurationRevision <= project.runtimeState.appliedToMirrorConfigurationRevision else {
            return RuntimeExecutionAdmission(
                allowed: false,
                note: nil,
                blockingMessage: "当前 run.controlled 需要先完成 Publish：项目镜像仍有待准备变更，请先应用工作流配置。"
            )
        }

        let runtimePublished =
            project.runtimeState.appliedToMirrorConfigurationRevision > 0
            && project.runtimeState.syncedToRuntimeConfigurationRevision >= project.runtimeState.appliedToMirrorConfigurationRevision
            && manager.sessionLifecycle.stage == .synced
            && !manager.sessionLifecycle.hasPendingMirrorChanges

        guard runtimePublished else {
            return RuntimeExecutionAdmission(
                allowed: false,
                note: nil,
                blockingMessage: "当前 run.controlled 需要先完成 persistent publish：请先执行“同步当前会话”，把最新项目镜像写入运行时会话。"
            )
        }

        return RuntimeExecutionAdmission(allowed: true, note: nil, blockingMessage: nil)
    }

    private func makeRuntimeEvent(
        eventType: OpenClawRuntimeEventType,
        source: OpenClawRuntimeActor,
        target: OpenClawRuntimeActor,
        transportKind: String,
        deploymentKind: String,
        workflowID: UUID?,
        node: WorkflowNode,
        sessionKey: String?,
        executionIntent: OpenClawRuntimeExecutionIntent? = nil,
        parentEventId: String? = nil,
        idempotencyKey: String? = nil,
        attempt: Int? = 1,
        payload: [String: String],
        constraints: [String: String] = [:],
        control: [String: String] = [:]
    ) -> OpenClawRuntimeEvent {
        let resolvedTransport = OpenClawRuntimeTransportKind(rawValue: transportKind) ?? .unknown
        var resolvedControl = control
        if let executionIntent {
            resolvedControl["executionIntent"] = executionIntent.rawValue
        }
        return OpenClawRuntimeEvent(
            eventType: eventType,
            workflowId: workflowID?.uuidString,
            nodeId: node.id.uuidString,
            sessionKey: sessionKey,
            parentEventId: parentEventId,
            idempotencyKey: idempotencyKey ?? UUID().uuidString,
            attempt: attempt,
            source: source,
            target: target,
            transport: OpenClawRuntimeTransport(kind: resolvedTransport, deploymentKind: deploymentKind),
            payload: payload,
            refs: [],
            constraints: constraints,
            control: resolvedControl
        )
    }

    // 构建Agent指令
    private func buildInstruction(
        for node: WorkflowNode,
        agent: Agent,
        prompt: String?,
        isEntryNode: Bool,
        downstreamTargets: [RoutingTargetDescriptor],
        guardrails: RuntimeDispatchGuardrails,
        protocolMemory: OpenClawAgentProtocolMemory,
        protocolCapsule: ProtocolDispatchCapsule,
        sessionProtocolDigest: String,
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
        let approvalLines: [String]
        if guardrails.approvalRequiredTargets.isEmpty {
            approvalLines = ["- None."]
        } else {
            approvalLines = guardrails.approvalRequiredTargets.map { target in
                let title = target.node.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let nodeLabel = title.isEmpty ? target.node.id.uuidString : title
                return "- \(target.agent.name) (agent_id: \(target.resolvedIdentifier), node: \(nodeLabel))"
            }
        }
        let writeScopeText = guardrails.writeScope.isEmpty ? "- No explicit write scope resolved." : guardrails.writeScope.map { "- \($0)" }.joined(separator: "\n")
        let toolScopeText = guardrails.toolScope.isEmpty ? "- No explicit tool scope resolved." : guardrails.toolScope.map { "- \($0)" }.joined(separator: "\n")
        let stableRulesText = protocolMemory.stableRules.isEmpty
            ? "- Follow the runtime protocol."
            : protocolMemory.stableRules.map { "- \($0)" }.joined(separator: "\n")
        let feedbackHintsText = protocolCapsule.feedbackHints.isEmpty
            ? "- None."
            : protocolCapsule.feedbackHints.map { "- \($0)" }.joined(separator: "\n")
        let allowedActionsText = protocolCapsule.allowedActions.joined(separator: ", ")
        let approvalTargetsText = protocolCapsule.approvalTargets.isEmpty
            ? "- None."
            : protocolCapsule.approvalTargets.map { "- \($0)" }.joined(separator: "\n")
        let allowedTargetsText = protocolCapsule.allowedTargets.isEmpty
            ? "- None."
            : protocolCapsule.allowedTargets.map { "- \($0)" }.joined(separator: "\n")

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

            Long-Term Protocol Memory:
            \(stableRulesText)

            Session Protocol Digest:
            - \(sessionProtocolDigest)

            Recent Protocol Corrections:
            \(feedbackHintsText)

            Execution Capsule:
            - Protocol version: \(protocolCapsule.protocolVersion)
            - Allowed actions: \(allowedActionsText)
            - Fallback policy: \(protocolCapsule.fallbackPolicy)
            - Required output contract: \(protocolCapsule.requiredOutputContract)
            - Self-check rule: \(protocolCapsule.selfCheckRule)

            Allowed Downstream Targets:
            \(allowedTargetsText)

            Approval Targets:
            \(approvalTargetsText)

            Workflow Routing Policy:
            - Downstream routing is opt-in, never automatic.
            - If you can finish the task yourself, stop and do not route further.
            - Only route when you genuinely need help from a downstream agent in this workflow.
            - You may only choose downstream agents from the list below.

            Downstream Candidates:
            \(candidateLines.joined(separator: "\n"))

            Approval-Required Downstream Agents:
            \(approvalLines.joined(separator: "\n"))

            Runtime Guardrails:
            - You must not contact or delegate to agents outside the allowed downstream candidate list.
            - If you need an approval-required target, explain it in your visible reply and include it in routing JSON; do not contact it directly.
            - Restrict file writes to the paths below.
            \(writeScopeText)
            - Restrict tool usage to the scopes below.
            \(toolScopeText)

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
            - Before sending your final answer, self-check the machine tail. If it is invalid, rewrite only the machine tail so it becomes valid.
            - If no downstream collaboration is needed, emit the smallest valid safe result with action "stop".
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
            - Follow protocol version \(protocolCapsule.protocolVersion).
            - Self-check the last line before sending. If invalid, rewrite only the machine tail.
            - If uncertain, emit the smallest valid safe result instead of guessing.

            Long-Term Protocol Memory:
            \(stableRulesText)

            Session Protocol Digest:
            - \(sessionProtocolDigest)

            Recent Protocol Corrections:
            \(feedbackHintsText)

            Execution Capsule:
            - Allowed actions: \(allowedActionsText)
            - Fallback policy: \(protocolCapsule.fallbackPolicy)
            - Required output contract: \(protocolCapsule.requiredOutputContract)

            Downstream Candidates:
            \(candidateLines.joined(separator: "\n"))

            Approval-Required Downstream Agents:
            \(approvalLines.joined(separator: "\n"))

            Runtime Guardrails:
            - Do not directly contact approval-required targets.
            - Keep writes inside:
            \(writeScopeText)
            - Limit tools to:
            \(toolScopeText)

            Append exactly one JSON object as the last non-empty line:
            {"workflow_route":{"action":"stop","targets":[],"reason":"short reason"}}
            Allowed action values: "stop", "selected", "all".
            Keep the JSON on its own line with no Markdown fence.
            """
        }
    }

    private func resolvedProtocolMemory(for agent: Agent) -> OpenClawAgentProtocolMemory {
        agent.openClawDefinition.protocolMemory
    }

    private func makeProtocolDispatchCapsule(
        for agent: Agent,
        guardrails: RuntimeDispatchGuardrails
    ) -> ProtocolDispatchCapsule {
        let allowedTargets = guardrails.directTargets.map { target in
            "\(target.agent.name) [agent_id: \(target.resolvedIdentifier), node: \(target.node.id.uuidString)]"
        }
        let approvalTargets = guardrails.approvalRequiredTargets.map { target in
            "\(target.agent.name) [agent_id: \(target.resolvedIdentifier), node: \(target.node.id.uuidString)]"
        }

        return ProtocolDispatchCapsule(
            protocolVersion: agent.openClawDefinition.protocolMemory.protocolVersion,
            allowedActions: WorkflowRoutingDecision.Action.allCases.map(\.rawValue),
            allowedTargets: allowedTargets,
            approvalTargets: approvalTargets,
            writeScope: guardrails.writeScope,
            toolScope: guardrails.toolScope,
            fallbackPolicy: guardrails.fallbackRoutingPolicy.rawValue,
            requiredOutputContract: #"{"workflow_route":{"action":"stop","targets":[],"reason":"short reason"}}"#,
            selfCheckRule: "Before sending the final answer, validate the last non-empty line. If the machine tail is invalid, rewrite only the machine tail so it becomes valid.",
            feedbackHints: protocolFeedbackHints(for: agent)
        )
    }

    private func makeSessionProtocolDigest(
        for agent: Agent,
        capsule: ProtocolDispatchCapsule,
        transportKind: String,
        isEntryNode: Bool
    ) -> String {
        let role = isEntryNode ? "entry" : "worker"
        let approvalMode = capsule.approvalTargets.isEmpty ? "no_approval_targets" : "approval_targets_present"
        return [
            "agent=\(agent.name)",
            "protocol=\(capsule.protocolVersion)",
            "role=\(role)",
            "transport=\(transportKind)",
            "fallback=\(capsule.fallbackPolicy)",
            approvalMode
        ].joined(separator: " | ")
    }

    private func protocolFeedbackHints(for agent: Agent) -> [String] {
        let protocolMemory = agent.openClawDefinition.protocolMemory
        let prioritized = protocolMemory.repeatOffenses + protocolMemory.recentCorrections
        var seen = Set<String>()
        var hints: [String] = []

        for item in prioritized {
            let message = item.message.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !message.isEmpty else { continue }
            guard seen.insert(message).inserted else { continue }
            hints.append(message)
            if hints.count == 2 {
                break
            }
        }

        return hints
    }

    private func runtimeDispatchGuardrails(
        for agent: Agent,
        node: WorkflowNode,
        workflow: Workflow,
        projectID: UUID?,
        outgoingEdges: [UUID: [WorkflowEdge]],
        agents: [Agent]
    ) -> RuntimeDispatchGuardrails {
        let buckets = routingTargetBuckets(
            for: node,
            workflow: workflow,
            agents: agents,
            outgoingEdges: outgoingEdges
        )
        return RuntimeDispatchGuardrails(
            directTargets: buckets.directTargets,
            approvalRequiredTargets: buckets.approvalTargets,
            writeScope: runtimeWriteScope(
                for: agent,
                workflowID: workflow.id,
                nodeID: node.id,
                projectID: projectID
            ),
            toolScope: runtimeToolScope(for: agent, directTargets: buckets.directTargets, approvalTargets: buckets.approvalTargets),
            fallbackRoutingPolicy: workflow.fallbackRoutingPolicy
        )
    }

    private func runtimeWriteScope(for agent: Agent) -> [String] {
        var scopes: [String] = []

        if let workspacePath = OpenClawManager.shared.resolvedWorkspacePath(for: agent)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !workspacePath.isEmpty {
            scopes.append(workspacePath)
        }

        if let memoryBackupPath = agent.openClawDefinition.memoryBackupPath?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !memoryBackupPath.isEmpty {
            scopes.append(memoryBackupPath)
        }

        return Array(Set(scopes)).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    private func runtimeWriteScope(
        for agent: Agent,
        workflowID: UUID,
        nodeID: UUID,
        projectID: UUID?
    ) -> [String] {
        var scopes = runtimeWriteScope(for: agent)

        if let projectID {
            let managedWorkspacePath = ProjectFileSystem.shared.nodeOpenClawWorkspaceDirectory(
                for: nodeID,
                workflowID: workflowID,
                projectID: projectID,
                under: ProjectManager.shared.appSupportRootDirectory
            ).path.trimmingCharacters(in: .whitespacesAndNewlines)
            if !managedWorkspacePath.isEmpty {
                scopes.append(managedWorkspacePath)
            }
        }

        return Array(Set(scopes)).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    private func runtimeToolScope(
        for agent: Agent,
        directTargets: [RoutingTargetDescriptor],
        approvalTargets: [RoutingTargetDescriptor]
    ) -> [String] {
        var scopes = agent.capabilities
            .map { normalizedToolScopeKey($0) }
            .filter { !$0.isEmpty && $0 != "basic" }

        if !directTargets.isEmpty || !approvalTargets.isEmpty {
            scopes.append("workflow.route")
        }

        return Array(Set(scopes)).sorted()
    }

    private func normalizedToolScopeKey(_ value: String) -> String {
        let filtered = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .map { character -> Character in
                switch character {
                case "a"..."z", "0"..."9", ".", "-", "_":
                    return character
                default:
                    return "-"
                }
            }
        return String(filtered)
            .replacingOccurrences(of: "--", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private func validateRoutingDecision(
        _ decision: WorkflowRoutingDecision?,
        directTargets: [RoutingTargetDescriptor],
        approvalTargets: [RoutingTargetDescriptor],
        node: WorkflowNode
    ) -> RoutingDecisionValidation {
        guard let decision else {
            return RoutingDecisionValidation(sanitizedDecision: nil, approvalRequiredTargets: [], rejectedTargets: [])
        }

        switch decision.action {
        case .stop:
            return RoutingDecisionValidation(sanitizedDecision: decision, approvalRequiredTargets: [], rejectedTargets: [])
        case .all:
            if !approvalTargets.isEmpty {
                let names = approvalTargets.map(\.agent.name).joined(separator: ", ")
                addLog(.warning, "Routing request includes approval-required targets and they will remain blocked until approved: \(names)", nodeID: node.id)
            }
            return RoutingDecisionValidation(
                sanitizedDecision: WorkflowRoutingDecision(action: .all, targets: directTargets.map(\.resolvedIdentifier), reason: decision.reason),
                approvalRequiredTargets: approvalTargets,
                rejectedTargets: []
            )
        case .selected:
            var allowedTargets: [RoutingTargetDescriptor] = []
            var approvalRequiredSelections: [RoutingTargetDescriptor] = []
            var rejectedTargets: [String] = []

            for requestedTarget in decision.targets {
                if let directTarget = directTargets.first(where: { routeTargetMatches([requestedTarget], candidate: $0) }) {
                    if !allowedTargets.contains(where: { $0.node.id == directTarget.node.id }) {
                        allowedTargets.append(directTarget)
                    }
                    continue
                }

                if let approvalTarget = approvalTargets.first(where: { routeTargetMatches([requestedTarget], candidate: $0) }) {
                    if !approvalRequiredSelections.contains(where: { $0.node.id == approvalTarget.node.id }) {
                        approvalRequiredSelections.append(approvalTarget)
                    }
                    continue
                }

                rejectedTargets.append(requestedTarget)
            }

            if !approvalRequiredSelections.isEmpty {
                let names = approvalRequiredSelections.map(\.agent.name).joined(separator: ", ")
                addLog(.warning, "Routing request to \(names) requires approval and was withheld from direct execution.", nodeID: node.id)
            }

            if !rejectedTargets.isEmpty {
                addLog(.warning, "Routing request referenced unsupported targets and they were rejected: \(rejectedTargets.joined(separator: ", "))", nodeID: node.id)
            }

            let sanitizedDecision: WorkflowRoutingDecision
            if allowedTargets.isEmpty {
                sanitizedDecision = WorkflowRoutingDecision(
                    action: .stop,
                    targets: [],
                    reason: decision.reason ?? "all requested targets were blocked by runtime guardrails"
                )
            } else {
                sanitizedDecision = WorkflowRoutingDecision(
                    action: .selected,
                    targets: allowedTargets.map(\.resolvedIdentifier),
                    reason: decision.reason
                )
            }

            return RoutingDecisionValidation(
                sanitizedDecision: sanitizedDecision,
                approvalRequiredTargets: approvalRequiredSelections,
                rejectedTargets: rejectedTargets
            )
        }
    }

    private func repairRoutingDecision(
        _ decision: WorkflowRoutingDecision?,
        directTargets: [RoutingTargetDescriptor],
        approvalTargets: [RoutingTargetDescriptor],
        node: WorkflowNode,
        outputType: ExecutionOutputType,
        fallbackPolicy: WorkflowFallbackRoutingPolicy,
        sessionID: String? = nil,
        agentID: UUID? = nil
    ) -> RoutingDecisionRepair {
        let validation = validateRoutingDecision(
            decision,
            directTargets: directTargets,
            approvalTargets: approvalTargets,
            node: node
        )

        var repairTypes: [String] = []
        var safeDegradeApplied = false
        var sanitizedDecision = validation.sanitizedDecision
        let requestedDecision = decision

        if decision == nil,
           outputType != .runtimeLog,
           directTargets.count == 1,
           approvalTargets.isEmpty {
            let fallbackTarget = directTargets[0]
            sanitizedDecision = WorkflowRoutingDecision(
                action: .selected,
                targets: [fallbackTarget.resolvedIdentifier],
                reason: "auto-repaired from missing routing directive"
            )
            repairTypes.append("missing_route_auto_selected")
            safeDegradeApplied = true
            addLog(
                .info,
                "Protocol repair selected the only safe downstream target \(fallbackTarget.agent.name) after the agent omitted a routing directive.",
                nodeID: node.id,
                sessionID: sessionID,
                agentID: agentID
            )
        } else if let decision,
                  decision.action == .selected,
                  (validation.sanitizedDecision?.targets ?? []).isEmpty,
                  directTargets.count == 1,
                  approvalTargets.isEmpty,
                  !validation.rejectedTargets.isEmpty {
            let fallbackTarget = directTargets[0]
            sanitizedDecision = WorkflowRoutingDecision(
                action: .selected,
                targets: [fallbackTarget.resolvedIdentifier],
                reason: decision.reason ?? "auto-repaired from invalid routing targets"
            )
            repairTypes.append("invalid_targets_auto_selected")
            safeDegradeApplied = true
            addLog(
                .info,
                "Protocol repair replaced invalid routing targets with the only safe downstream target \(fallbackTarget.agent.name).",
                nodeID: node.id,
                sessionID: sessionID,
                agentID: agentID
            )
        } else if decision == nil,
                  outputType != .runtimeLog,
                  directTargets.isEmpty,
                  !approvalTargets.isEmpty,
                  fallbackPolicy != .stop {
            repairTypes.append("route_missing_approval_blocked")
            safeDegradeApplied = true
            addLog(
                .info,
                "Protocol repair kept the current node result and blocked downstream continuation because only approval-gated targets were available.",
                nodeID: node.id,
                sessionID: sessionID,
                agentID: agentID
            )
        }

        return RoutingDecisionRepair(
            requestedDecision: requestedDecision,
            sanitizedDecision: sanitizedDecision,
            approvalRequiredTargets: validation.approvalRequiredTargets,
            rejectedTargets: validation.rejectedTargets,
            repairTypes: Array(Set(repairTypes)).sorted(),
            safeDegradeApplied: safeDegradeApplied
        )
    }

    private func routingTargetBuckets(
        for node: WorkflowNode,
        workflow: Workflow,
        agents: [Agent],
        outgoingEdges: [UUID: [WorkflowEdge]]
    ) -> (directTargets: [RoutingTargetDescriptor], approvalTargets: [RoutingTargetDescriptor]) {
        let nodeByID = Dictionary(uniqueKeysWithValues: workflow.nodes.map { ($0.id, $0) })
        let agentByID = Dictionary(uniqueKeysWithValues: agents.map { ($0.id, $0) })
        let edges = outgoingEdges[node.id, default: []]

        var directTargets: [RoutingTargetDescriptor] = []
        var approvalTargets: [RoutingTargetDescriptor] = []
        var seenDirect = Set<UUID>()
        var seenApproval = Set<UUID>()

        for edge in edges {
            let condition = edge.conditionExpression.trimmingCharacters(in: .whitespacesAndNewlines)
            guard condition.isEmpty || evaluateExpression(condition, workflow: workflow) else {
                continue
            }

            guard let candidateNode = nodeByID[edge.toNodeID],
                  candidateNode.type == .agent,
                  let agentID = candidateNode.agentID,
                  let candidateAgent = agentByID[agentID] else {
                continue
            }

            let descriptor = RoutingTargetDescriptor(
                node: candidateNode,
                agent: candidateAgent,
                resolvedIdentifier: resolvedAgentIdentifier(for: candidateAgent)
            )

            if edge.requiresApproval {
                guard seenApproval.insert(candidateNode.id).inserted else { continue }
                approvalTargets.append(descriptor)
            } else {
                guard seenDirect.insert(candidateNode.id).inserted else { continue }
                directTargets.append(descriptor)
            }
        }

        let sorter: (RoutingTargetDescriptor, RoutingTargetDescriptor) -> Bool = { lhs, rhs in
            self.nodeSort(lhs.node, rhs.node)
        }
        return (
            directTargets.sorted(by: sorter),
            approvalTargets.sorted(by: sorter)
        )
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
        fallbackPolicy: WorkflowFallbackRoutingPolicy,
        sessionID: String? = nil,
        agentID: UUID? = nil
    ) -> [RoutingTargetDescriptor] {
        guard !availableTargets.isEmpty else { return [] }

        guard let decision else {
            if outputType != .runtimeLog {
                switch fallbackPolicy {
                case .stop:
                    addLog(.info, "No routing decision emitted; stopping at current node by default.", nodeID: node.id, sessionID: sessionID, agentID: agentID)
                    return []
                case .firstAvailable:
                    if availableTargets.count == 1 {
                        let target = availableTargets[0]
                        addLog(.info, "No routing decision emitted; fallback policy routed to single downstream agent \(target.agent.name).", nodeID: node.id, sessionID: sessionID, agentID: agentID)
                        return [target]
                    }
                    addLog(.info, "No routing decision emitted; fallback policy requires exactly one downstream agent, so execution stopped.", nodeID: node.id, sessionID: sessionID, agentID: agentID)
                    return []
                case .allAvailable:
                    let names = availableTargets.map(\.agent.name).joined(separator: ", ")
                    addLog(.info, "No routing decision emitted; fallback policy routed to all downstream agents: \(names)", nodeID: node.id, sessionID: sessionID, agentID: agentID)
                    return availableTargets
                }
            }
            return []
        }

        switch decision.action {
        case .stop:
            addLog(.info, "Routing decision: stop.", nodeID: node.id, sessionID: sessionID, agentID: agentID)
            return []
        case .all:
            addLog(.info, "Routing decision: fan out to all downstream agents.", nodeID: node.id, sessionID: sessionID, agentID: agentID)
            return availableTargets
        case .selected:
            if decision.targets.isEmpty {
                addLog(.warning, "Routing decision requested selected targets, but no targets were provided.", nodeID: node.id, sessionID: sessionID, agentID: agentID)
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
                addLog(.warning, "Ignored unknown downstream targets: \(unresolved.joined(separator: ", "))", nodeID: node.id, sessionID: sessionID, agentID: agentID)
            }

            if resolved.isEmpty {
                addLog(.warning, "Routing decision did not match any reachable downstream agent.", nodeID: node.id, sessionID: sessionID, agentID: agentID)
            } else {
                let names = resolved.map { $0.agent.name }.joined(separator: ", ")
                addLog(.info, "Routing decision: \(names)", nodeID: node.id, sessionID: sessionID, agentID: agentID)
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

    private func runtimeRegistrationContext(
        for agent: Agent,
        preferredWorkflowID: UUID?
    ) -> RuntimeRegistrationContext? {
        guard let project = currentProjectProvider?() else { return nil }
        guard project.agents.contains(where: { $0.id == agent.id }) else { return nil }

        if let preferredWorkflowID,
           project.workflows.contains(where: { $0.id == preferredWorkflowID && $0.nodes.contains(where: { $0.type == .agent && $0.agentID == agent.id }) }) {
            return RuntimeRegistrationContext(project: project, workflowID: preferredWorkflowID)
        }

        let matchingWorkflowIDs = project.workflows.compactMap { workflow in
            workflow.nodes.contains(where: { $0.type == .agent && $0.agentID == agent.id }) ? workflow.id : nil
        }

        if matchingWorkflowIDs.count == 1, let workflowID = matchingWorkflowIDs.first {
            return RuntimeRegistrationContext(project: project, workflowID: workflowID)
        }

        return RuntimeRegistrationContext(project: project, workflowID: nil)
    }
    
    // 调用OpenClaw Agent
    private func callOpenClawAgent(
        instruction: String,
        agentIdentifier: String,
        runtimeAgent: Agent? = nil,
        workflowID: UUID? = nil,
        sessionID: String? = nil,
        threadID: String? = nil,
        executionIntent: OpenClawRuntimeExecutionIntent = .conversationAutonomous,
        thinkingLevel: AgentThinkingLevel? = nil,
        trackActiveRemoteRun: Bool = false,
        transportPreference: AgentTransportPreference = .automatic,
        outputMode: AgentOutputMode = .structuredJSON,
        onPartial: ((String) -> Void)? = nil,
        completion: @escaping (Bool, ParsedAgentOutput) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async(execute: { [weak self] in
            guard let self = self else { return }
            let executionStartedAt = Date()
            let metricsQueue = DispatchQueue(label: "com.openclaw.agent.metrics")

            final class FirstChunkLatencyState: @unchecked Sendable {
                var value: Int?
            }

            let firstChunkLatencyState = FirstChunkLatencyState()

            func durationMs(since start: Date, until end: Date = Date()) -> Int {
                Int((end.timeIntervalSince(start) * 1000.0).rounded())
            }

            @Sendable
            func captureFirstChunkLatencyIfNeeded(referenceTime: Date = Date()) {
                metricsQueue.sync {
                    guard firstChunkLatencyState.value == nil else { return }
                    firstChunkLatencyState.value = durationMs(since: executionStartedAt, until: referenceTime)
                }
            }

            @Sendable
            func currentFirstChunkLatency() -> Int? {
                metricsQueue.sync { firstChunkLatencyState.value }
            }

            func buildParsedOutput(
                text: String,
                type: ExecutionOutputType,
                sessionID: String?,
                transportKind: String?,
                completionLatencyMs: Int,
                routingDecision: WorkflowRoutingDecision?
            ) -> ParsedAgentOutput {
                ParsedAgentOutput(
                    text: text,
                    type: type,
                    sessionID: sessionID,
                    transportKind: transportKind,
                    firstChunkLatencyMs: currentFirstChunkLatency(),
                    completionLatencyMs: completionLatencyMs,
                    routingDecision: routingDecision
                )
            }
            
            let serviceConfig = self.agentConfig
            let manager = OpenClawManager.shared
            let connectionConfig = manager.config
            let pluginCleanup = manager.cleanupStalePluginInstallStageArtifactsIfNeeded(using: connectionConfig)
            if !pluginCleanup.success {
                self.addLog(.warning, pluginCleanup.message)
            } else if !pluginCleanup.message.isEmpty {
                self.addLog(.info, pluginCleanup.message)
            }

            var preferredRuntimeIdentifier = agentIdentifier
            if connectionConfig.deploymentKind == .local, let runtimeAgent {
                let registrationContext = self.runtimeRegistrationContext(
                    for: runtimeAgent,
                    preferredWorkflowID: workflowID
                )
                let registration = manager.ensureLocalRuntimeAgentRegistration(
                    for: runtimeAgent,
                    in: registrationContext?.project,
                    workflowID: registrationContext?.workflowID,
                    using: connectionConfig
                )
                if !registration.identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    preferredRuntimeIdentifier = registration.identifier
                }
                if !registration.success {
                    self.addLog(.warning, registration.message)
                } else if !registration.message.isEmpty {
                    self.addLog(.info, registration.message)
                }
            }

            let resolvedAgent = self.resolveRuntimeAgentIdentifier(
                preferred: preferredRuntimeIdentifier,
                manager: manager,
                config: connectionConfig
            )
            if let message = resolvedAgent.message {
                self.addLog(.warning, message)
            }
            let gatewayConfig = manager.preferredGatewayConfig(using: connectionConfig)
            let executionAdmission = self.runtimeExecutionAdmission(
                for: executionIntent,
                projectID: self.currentProjectProvider?()?.id
            )
            if let note = executionAdmission.note {
                self.addLog(.info, note, sessionID: sessionID, agentID: runtimeAgent?.id)
            }
            guard executionAdmission.allowed else {
                let failureMessage = executionAdmission.blockingMessage ?? "OpenClaw runtime admission check failed."
                let completionLatencyMs = durationMs(since: executionStartedAt)
                DispatchQueue.main.async {
                    completion(
                        false,
                        buildParsedOutput(
                            text: failureMessage,
                            type: .errorSummary,
                            sessionID: sessionID,
                            transportKind: nil,
                            completionLatencyMs: completionLatencyMs,
                            routingDecision: nil
                        )
                    )
                }
                return
            }

            func runCLITransport() {
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
                        "OpenClaw CLI 输出能力: quiet=\(capabilities.supportsQuiet), log-level=\(capabilities.supportsLogLevel), json-only=\(capabilities.supportsJSONOnly); 当前启用参数: \(flagText).",
                        sessionID: sessionID,
                        agentID: runtimeAgent?.id
                    )
                }

                // In local deployment, CLI fallback must stay on the local runtime even if
                // the gateway layer is currently marked as connected. Otherwise `openclaw agent`
                // falls back to the remote gateway path and surfaces misleading token errors.
                let shouldUseLocal = serviceConfig.useLocal
                    && connectionConfig.deploymentKind == .local
                let normalizedSessionID = sessionID?.trimmingCharacters(in: .whitespacesAndNewlines)
                let effectiveSessionID = (normalizedSessionID?.isEmpty == false) ? normalizedSessionID : nil
                if shouldUseLocal {
                    let authFallback = manager.ensureLocalDefaultAgentAuthFallback(using: connectionConfig)
                    if !authFallback.success {
                        self.addLog(.warning, authFallback.message, sessionID: effectiveSessionID, agentID: runtimeAgent?.id)
                    } else if !authFallback.message.isEmpty {
                        self.addLog(.info, authFallback.message, sessionID: effectiveSessionID, agentID: runtimeAgent?.id)
                    }
                    args.append("--local")
                    self.addLog(
                        .info,
                        "CLI fallback is using local mode for agent \(resolvedAgent.identifier).",
                        sessionID: effectiveSessionID,
                        agentID: runtimeAgent?.id
                    )
                }

                args.append(contentsOf: ["--timeout", String(max(1, serviceConfig.timeout))])

                do {
                    let result = try manager.executeAgentRuntimeCommand(
                        arguments: args,
                        using: connectionConfig,
                        onStdoutChunk: { chunk in
                            let visibleChunk = self.extractStreamingTextChunk(from: chunk)
                            guard !visibleChunk.isEmpty else { return }
                            captureFirstChunkLatencyIfNeeded()
                            guard let onPartial else { return }
                            DispatchQueue.main.async {
                                onPartial(visibleChunk)
                            }
                        }
                    )
                    let stdout = String(data: result.standardOutput, encoding: .utf8) ?? ""
                    let stderr = String(data: result.standardError, encoding: .utf8) ?? ""
                    let stdoutTrimmed = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                    let stderrTrimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                    let completionLatencyMs = durationMs(since: executionStartedAt)
                    let parsedAgentOutput = self.parseAgentOutput(
                        from: stdoutTrimmed,
                        outputMode: outputMode,
                        sessionID: effectiveSessionID,
                        transportKind: "cli",
                        firstChunkLatencyMs: currentFirstChunkLatency(),
                        completionLatencyMs: completionLatencyMs
                    )

                    let runtimeMessage: String?
                    if result.executionCount == 1 {
                        runtimeMessage = "Created OpenClaw Agent Runtime channel \(result.channelKey) and executed the first request."
                    } else if result.executionCount == 2 {
                        runtimeMessage = "OpenClaw Agent Runtime channel \(result.channelKey) is now being reused for subsequent requests."
                    } else {
                        runtimeMessage = nil
                    }
                    if let runtimeMessage {
                        self.addLog(.info, runtimeMessage, sessionID: effectiveSessionID, agentID: runtimeAgent?.id)
                    }

                    if !stderrTrimmed.isEmpty {
                        let level: ExecutionLogEntry.LogLevel = result.terminationStatus == 0 ? .warning : .error
                        self.addLog(
                            level,
                            "OpenClaw stderr (\(resolvedAgent.identifier)): \(self.truncatedLog(stderrTrimmed))",
                            sessionID: effectiveSessionID,
                            agentID: runtimeAgent?.id
                        )
                    }

                    DispatchQueue.main.async {
                        if result.terminationStatus == 0 {
                            completion(true, parsedAgentOutput)
                        } else {
                            let fallback = self.executionFailureSummary(
                                exitCode: result.terminationStatus,
                                stderr: stderrTrimmed,
                                stdout: stdoutTrimmed
                            )
                            completion(
                                false,
                                buildParsedOutput(
                                    text: fallback,
                                    type: .errorSummary,
                                    sessionID: effectiveSessionID,
                                    transportKind: "cli",
                                    completionLatencyMs: completionLatencyMs,
                                    routingDecision: nil
                                )
                            )
                        }
                    }
                } catch {
                    let completionLatencyMs = durationMs(since: executionStartedAt)
                    DispatchQueue.main.async {
                        completion(
                            false,
                            buildParsedOutput(
                                text: "Error: \(error.localizedDescription)",
                                type: .errorSummary,
                                sessionID: effectiveSessionID,
                                transportKind: "cli",
                                completionLatencyMs: completionLatencyMs,
                                routingDecision: nil
                            )
                        )
                    }
                }
            }

            let shouldUseGatewayTransport: Bool
            switch transportPreference {
            case .automatic, .gatewayOnly:
                shouldUseGatewayTransport = true
            case .cliOnly:
                shouldUseGatewayTransport = false
            }

            if let gatewayConfig, shouldUseGatewayTransport {
                let gatewaySessionKey = self.gatewaySessionKey(
                    sessionID: sessionID,
                    agentIdentifier: resolvedAgent.identifier
                )
                let useGatewayChatTransport = self.prefersGatewayChatTransport(
                    sessionID: sessionID,
                    outputMode: outputMode,
                    executionIntent: executionIntent
                )
                let transportKind = useGatewayChatTransport ? "gateway_chat" : "gateway_agent"
                let shouldStreamPlainOutput: Bool
                switch outputMode {
                case .plainStreaming:
                    shouldStreamPlainOutput = true
                case .structuredJSON:
                    shouldStreamPlainOutput = false
                }
                let gatewayModeDescription = connectionConfig.deploymentKind == .remoteServer
                    ? "remote server"
                    : "local loopback"

                self.addLog(
                    .info,
                    "Gateway agent path enabled for \(gatewayModeDescription): agent=\(resolvedAgent.identifier), sessionKey=\(gatewaySessionKey)",
                    sessionID: sessionID ?? gatewaySessionKey,
                    agentID: runtimeAgent?.id
                )

                _Concurrency.Task {
                    do {
                        let streamAccumulator = StreamingTextAccumulator()
                        let onAssistantTextUpdated: @Sendable (String) -> Void = { fullText in
                            let visibleText = Self.extractVisiblePlainResponseText(from: fullText)
                            if !visibleText.isEmpty {
                                captureFirstChunkLatencyIfNeeded()
                            }
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
                        if useGatewayChatTransport {
                            await MainActor.run {
                                self.addLog(
                                    .info,
                                    "Gateway chat session path enabled for session \(gatewaySessionKey).",
                                    sessionID: gatewaySessionKey,
                                    agentID: runtimeAgent?.id
                                )
                            }
                            do {
                                result = try await manager.executeGatewayChatCommand(
                                    message: instruction,
                                    sessionKey: gatewaySessionKey,
                                    thinkingLevel: thinkingLevel,
                                    timeoutSeconds: max(1, serviceConfig.timeout),
                                    using: gatewayConfig,
                                    onRunStarted: { [weak self] runID, sessionKey in
                                        guard trackActiveRemoteRun else { return }
                                        guard let service = self else { return }
                                        _Concurrency.Task { @MainActor in
                                            service.setActiveGatewayConversation(
                                                threadID: threadID,
                                                workflowID: workflowID,
                                                runID: runID,
                                                sessionKey: sessionKey,
                                                transportKind: transportKind,
                                                executionIntent: executionIntent
                                            )
                                        }
                                    },
                                    onAssistantTextUpdated: onAssistantTextUpdated
                                )
                                if trackActiveRemoteRun {
                                    await MainActor.run {
                                        self.clearActiveGatewayConversation(
                                            threadID: threadID,
                                            sessionKey: gatewaySessionKey
                                        )
                                    }
                                }
                            } catch {
                                if trackActiveRemoteRun {
                                    await MainActor.run {
                                        self.clearActiveGatewayConversation(
                                            threadID: threadID,
                                            sessionKey: gatewaySessionKey
                                        )
                                    }
                                }
                                throw error
                            }
                        } else {
                            result = try await manager.executeGatewayAgentCommand(
                                message: instruction,
                                agentIdentifier: resolvedAgent.identifier,
                                sessionKey: gatewaySessionKey,
                                thinkingLevel: thinkingLevel,
                                timeoutSeconds: max(1, serviceConfig.timeout),
                                using: gatewayConfig,
                                onAssistantTextUpdated: onAssistantTextUpdated
                            )
                        }

                        let normalizedText = result.assistantText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !normalizedText.isEmpty {
                            captureFirstChunkLatencyIfNeeded()
                        }
                        let completionLatencyMs = durationMs(since: executionStartedAt)
                        let parsedAgentOutput = await MainActor.run {
                            self.parseAgentOutput(
                                from: normalizedText,
                                outputMode: outputMode,
                                sessionID: result.sessionKey ?? sessionID,
                                transportKind: transportKind,
                                firstChunkLatencyMs: currentFirstChunkLatency(),
                                completionLatencyMs: completionLatencyMs
                            )
                        }
                        let success = result.status == "ok"
                        let fallback = result.errorMessage ?? (normalizedText.isEmpty ? "Gateway agent run finished with status: \(result.status)" : normalizedText)

                        DispatchQueue.main.async {
                            if success {
                                completion(true, parsedAgentOutput)
                            } else {
                                completion(
                                    false,
                                    buildParsedOutput(
                                        text: fallback,
                                        type: .errorSummary,
                                        sessionID: result.sessionKey ?? sessionID,
                                        transportKind: transportKind,
                                        completionLatencyMs: completionLatencyMs,
                                        routingDecision: nil
                                    )
                                )
                            }
                        }
                    } catch {
                        let shouldFallbackToCLI: Bool
                        switch transportPreference {
                        case .automatic:
                            shouldFallbackToCLI = connectionConfig.deploymentKind != .remoteServer
                        case .gatewayOnly, .cliOnly:
                            shouldFallbackToCLI = false
                        }

                        if shouldFallbackToCLI {
                            await MainActor.run {
                                self.addLog(
                                    .warning,
                                    "Gateway transport failed in local mode, falling back to CLI: \(error.localizedDescription)",
                                    sessionID: sessionID,
                                    agentID: runtimeAgent?.id
                                )
                            }
                            DispatchQueue.global(qos: .userInitiated).async {
                                runCLITransport()
                            }
                            return
                        }

                        let completionLatencyMs = durationMs(since: executionStartedAt)
                        DispatchQueue.main.async {
                            completion(
                                false,
                                buildParsedOutput(
                                    text: "Gateway error: \(error.localizedDescription)",
                                    type: .errorSummary,
                                    sessionID: sessionID,
                                    transportKind: transportKind,
                                    completionLatencyMs: completionLatencyMs,
                                    routingDecision: nil
                                )
                            )
                        }
                    }
                }
                return
            }

            switch transportPreference {
            case .gatewayOnly:
                let completionLatencyMs = durationMs(since: executionStartedAt)
                let preferredTransportKind = self.prefersGatewayChatTransport(
                    sessionID: sessionID,
                    outputMode: outputMode,
                    executionIntent: executionIntent
                ) ? "gateway_chat" : "gateway_agent"
                DispatchQueue.main.async {
                    completion(
                        false,
                        buildParsedOutput(
                            text: "Gateway transport is unavailable for the current OpenClaw configuration.",
                            type: .errorSummary,
                            sessionID: sessionID,
                            transportKind: preferredTransportKind,
                            completionLatencyMs: completionLatencyMs,
                            routingDecision: nil
                        )
                    )
                }
                return
            case .automatic, .cliOnly:
                break
            }

            runCLITransport()
        })
    }

    private func parseAgentOutput(
        from stdout: String,
        outputMode: AgentOutputMode,
        sessionID: String? = nil,
        transportKind: String? = nil,
        firstChunkLatencyMs: Int? = nil,
        completionLatencyMs: Int? = nil
    ) -> ParsedAgentOutput {
        switch outputMode {
        case .structuredJSON:
            let parsed = extractAgentResponse(from: stdout)
            let routingDecision = extractRoutingDecision(from: stdout) ?? extractRoutingDecision(from: parsed.text)
            let sanitizedText = stripRoutingDirective(from: parsed.text)
            return ParsedAgentOutput(
                text: sanitizedText,
                type: parsed.type,
                sessionID: sessionID,
                transportKind: transportKind,
                firstChunkLatencyMs: firstChunkLatencyMs,
                completionLatencyMs: completionLatencyMs,
                routingDecision: routingDecision
            )
        case .plainStreaming:
            let text = extractVisiblePlainResponse(from: stdout)
            let routingDecision = extractRoutingDecision(from: stdout) ?? extractRoutingDecision(from: text)
            let sanitizedText = stripRoutingDirective(from: text)
            let outputType: ExecutionOutputType = sanitizedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? .runtimeLog
                : .agentFinalResponse
            return ParsedAgentOutput(
                text: sanitizedText,
                type: outputType,
                sessionID: sessionID,
                transportKind: transportKind,
                firstChunkLatencyMs: firstChunkLatencyMs,
                completionLatencyMs: completionLatencyMs,
                routingDecision: routingDecision
            )
        }
    }

    private func capabilityCacheKey(for config: OpenClawConfig) -> String {
        switch config.deploymentKind {
        case .local:
            return "local|\(config.runtimeOwnership.rawValue)|\(config.localBinaryPath.trimmingCharacters(in: .whitespacesAndNewlines))"
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

    private func prefersGatewayChatTransport(
        sessionID: String?,
        outputMode: AgentOutputMode,
        executionIntent: OpenClawRuntimeExecutionIntent
    ) -> Bool {
        OpenClawTransportRouting.prefersGatewayChatTransport(
            sessionID: sessionID,
            outputMode: outputMode,
            executionIntent: executionIntent
        )
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

    private func workflowNodeSessionID(
        projectRuntimeSessionID: String?,
        workflowID: UUID,
        nodeID: UUID,
        agentID: UUID
    ) -> String? {
        let connectionConfig = OpenClawManager.shared.config
        guard OpenClawManager.shared.preferredGatewayConfig(using: connectionConfig) != nil else { return nil }

        let base = projectRuntimeSessionID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolvedBase = base.isEmpty ? workflowID.uuidString : base
        return "workflow-\(resolvedBase)-\(workflowID.uuidString)-\(nodeID.uuidString)-\(agentID.uuidString)"
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

    private func runtimeRetryPolicy(isEntryNode: Bool) -> RuntimeRetryPolicy {
        RuntimeRetryPolicy(
            allowRetry: !isEntryNode,
            maxRetries: isEntryNode ? 1 : 2
        )
    }

    private func isLikelyTimeoutFailure(_ text: String) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }

        let timeoutMarkers = [
            "timed out",
            "timeout",
            "request timed out",
            "execution timeout",
            "deadline exceeded",
            "超时",
            "逾时"
        ]
        return timeoutMarkers.contains { normalized.contains($0) }
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

        return (
            preferredID,
            "目标 agent \(preferredID) 在当前本地运行态不存在，请先应用到 OpenClaw 或修复本地 runtime 注册。"
        )
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

    private var transportBenchmarkReportsDirectoryURL: URL? {
        stateFileURL?
            .deletingLastPathComponent()
            .appendingPathComponent("benchmarks", isDirectory: true)
    }
    
    // 清理结果
    func clearResults() {
        executionResults.removeAll()
        currentNodeID = nil
        lastError = nil
    }

    func runTransportBenchmark(
        prompt: String? = nil,
        iterationsPerTransport: Int = 3,
        completion: ((TransportBenchmarkReport) -> Void)? = nil
    ) {
        guard !isRunningTransportBenchmark else { return }

        let manager = OpenClawManager.shared
        let config = manager.config
        let transports = availableBenchmarkTransports(for: config)
        guard !transports.isEmpty else {
            let message = "No benchmark transports are available for the current OpenClaw deployment."
            transportBenchmarkError = message
            addLog(.warning, message)
            return
        }

        let preferredAgentIdentifier = preferredBenchmarkAgentIdentifier(using: config)
        let benchmarkPrompt = sanitizedBenchmarkPrompt(prompt)
        let measuredIterations = max(1, iterationsPerTransport)

        transportBenchmarkError = nil
        isRunningTransportBenchmark = true
        addLog(
            .info,
            "Starting transport benchmark for \(transports.map(\.displayName).joined(separator: ", ")) with \(measuredIterations) iteration(s) each."
        )

        _Concurrency.Task { [weak self] in
            guard let self else { return }

            let benchmarkStartedAt = Date()
            var samples: [TransportBenchmarkSample] = []

            for transport in transports {
                let sharedSessionID: String?
                switch transport {
                case .gatewayChat:
                    sharedSessionID = "benchmark-\(UUID().uuidString.lowercased())"
                case .workflowHotPath:
                    sharedSessionID = "workflow-benchmark-\(UUID().uuidString.lowercased())"
                case .gatewayAgent, .cli:
                    sharedSessionID = nil
                }

                for iteration in 1...measuredIterations {
                    let instruction = """
                    \(benchmarkPrompt)

                    Benchmark metadata:
                    - transport: \(transport.rawValue)
                    - iteration: \(iteration)
                    - required output: reply with one short sentence and include the iteration number.
                    """

                    let invocationStartedAt = Date()
                    let outcome = await self.runTransportBenchmarkInvocation(
                        instruction: instruction,
                        preferredAgentIdentifier: preferredAgentIdentifier,
                        transport: transport,
                        sessionID: sharedSessionID
                    )
                    let completedAt = Date()

                    let previewText: String
                    if outcome.output.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        previewText = outcome.success ? "No output" : "Benchmark failed"
                    } else {
                        previewText = outcome.output.text.compactSingleLinePreview(limit: 180)
                    }

                    let sample = TransportBenchmarkSample(
                        transport: transport,
                        iteration: iteration,
                        success: outcome.success,
                        sessionID: outcome.output.sessionID ?? sharedSessionID,
                        actualTransportKind: outcome.output.transportKind,
                        startedAt: invocationStartedAt,
                        completedAt: completedAt,
                        firstChunkLatencyMs: outcome.output.firstChunkLatencyMs,
                        completionLatencyMs: outcome.output.completionLatencyMs,
                        previewText: previewText,
                        errorText: outcome.success ? nil : outcome.output.text
                    )
                    samples.append(sample)

                    let logLevel: ExecutionLogEntry.LogLevel = outcome.success ? .success : .error
                    self.addLog(
                        logLevel,
                        "Benchmark \(transport.displayName) #\(iteration): actual=\(sample.actualTransportKind ?? "unknown"), first=\(sample.firstChunkLatencyMs.map(String.init) ?? "n/a")ms, total=\(sample.completionLatencyMs.map(String.init) ?? "n/a")ms"
                    )
                }
            }

            let reportBase = TransportBenchmarkReport(
                id: UUID(),
                deploymentKind: config.deploymentKind,
                agentIdentifier: preferredAgentIdentifier,
                prompt: benchmarkPrompt,
                iterationsPerTransport: measuredIterations,
                startedAt: benchmarkStartedAt,
                completedAt: Date(),
                samples: samples,
                summaries: self.summarizeTransportBenchmarkSamples(samples),
                reportFilePath: nil
            )
            let persistedReportURL = self.persistTransportBenchmarkReport(reportBase)
            let report = TransportBenchmarkReport(
                id: reportBase.id,
                deploymentKind: reportBase.deploymentKind,
                agentIdentifier: reportBase.agentIdentifier,
                prompt: reportBase.prompt,
                iterationsPerTransport: reportBase.iterationsPerTransport,
                startedAt: reportBase.startedAt,
                completedAt: reportBase.completedAt,
                samples: reportBase.samples,
                summaries: reportBase.summaries,
                reportFilePath: persistedReportURL?.path
            )

            await MainActor.run {
                self.transportBenchmarkReport = report
                self.isRunningTransportBenchmark = false
                completion?(report)
            }

            self.addLog(
                .info,
                "Transport benchmark completed. Report saved to \(persistedReportURL?.path ?? "memory only")."
            )
        }
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

    private func availableBenchmarkTransports(for config: OpenClawConfig) -> [TransportBenchmarkKind] {
        if OpenClawManager.shared.preferredGatewayConfig(using: config) != nil {
            if config.deploymentKind == .remoteServer {
                return [.gatewayChat, .gatewayAgent, .workflowHotPath]
            }
            return [.gatewayChat, .gatewayAgent, .workflowHotPath, .cli]
        }
        return [.cli]
    }

    private func preferredBenchmarkAgentIdentifier(using config: OpenClawConfig) -> String {
        let configured = agentConfig.agentID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !configured.isEmpty {
            return configured
        }

        let fallback = config.defaultAgent.trimmingCharacters(in: .whitespacesAndNewlines)
        return fallback.isEmpty ? "default" : fallback
    }

    private func sanitizedBenchmarkPrompt(_ prompt: String?) -> String {
        let trimmed = prompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            return "You are running a transport latency benchmark. Reply briefly in plain text."
        }
        return trimmed
    }

    private func runTransportBenchmarkInvocation(
        instruction: String,
        preferredAgentIdentifier: String,
        transport: TransportBenchmarkKind,
        sessionID: String?
    ) async -> (success: Bool, output: ParsedAgentOutput) {
        await withCheckedContinuation { continuation in
            let benchmarkSessionID: String?
            let transportPreference: AgentTransportPreference
            switch transport {
            case .gatewayChat:
                benchmarkSessionID = sessionID
                transportPreference = .gatewayOnly
            case .gatewayAgent:
                benchmarkSessionID = nil
                transportPreference = .gatewayOnly
            case .workflowHotPath:
                benchmarkSessionID = sessionID
                transportPreference = .gatewayOnly
            case .cli:
                benchmarkSessionID = nil
                transportPreference = .cliOnly
            }

            callOpenClawAgent(
                instruction: instruction,
                agentIdentifier: preferredAgentIdentifier,
                sessionID: benchmarkSessionID,
                executionIntent: .benchmark,
                thinkingLevel: .off,
                transportPreference: transportPreference,
                outputMode: .plainStreaming
            ) { success, output in
                continuation.resume(returning: (success, output))
            }
        }
    }

    private func summarizeTransportBenchmarkSamples(
        _ samples: [TransportBenchmarkSample]
    ) -> [TransportBenchmarkSummary] {
        OpenClawTransportRouting.summarizeTransportBenchmarkSamples(samples)
    }

    private func expectedBenchmarkTransportKind(for transport: TransportBenchmarkKind) -> String? {
        OpenClawTransportRouting.expectedBenchmarkTransportKind(for: transport)?.rawValue
    }

    private func persistTransportBenchmarkReport(_ report: TransportBenchmarkReport) -> URL? {
        guard let directoryURL = transportBenchmarkReportsDirectoryURL else { return nil }

        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
            let timestamp = formatter.string(from: report.completedAt).replacingOccurrences(of: ":", with: "-")
            let filename = "transport-benchmark-\(timestamp)-\(report.deploymentKind.rawValue).json"
            let fileURL = directoryURL.appendingPathComponent(filename, isDirectory: false)

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(report)
            try data.write(to: fileURL, options: .atomic)
            return fileURL
        } catch {
            addLog(.warning, "Failed to persist transport benchmark report: \(error.localizedDescription)")
            return nil
        }
    }
}
