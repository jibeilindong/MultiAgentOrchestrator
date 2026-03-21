//
//  Untitled.swift
//  Multi-Agent-Flow
//
//  Created by 陈荣泽 on 2026/3/18.
//

import Foundation
import CoreGraphics

enum RuntimeDispatchStatus: String, Codable, CaseIterable, Hashable {
    case created
    case dispatched
    case accepted
    case running
    case waitingApproval = "waiting_approval"
    case waitingDependency = "waiting_dependency"
    case completed
    case failed
    case aborted
    case expired
    case partial
}

struct RuntimeDispatchRecord: Codable, Identifiable, Hashable {
    let id: String
    var eventID: String
    var parentEventID: String?
    var runID: String?
    var workflowID: String?
    var nodeID: String?
    var sourceAgentID: String
    var targetAgentID: String
    var summary: String
    var sessionKey: String?
    var idempotencyKey: String?
    var attempt: Int
    var status: RuntimeDispatchStatus
    var transportKind: OpenClawRuntimeTransportKind
    var timeoutSeconds: Int?
    var allowRetry: Bool
    var maxRetries: Int?
    var queuedAt: Date
    var updatedAt: Date
    var completedAt: Date?
    var errorMessage: String?

    init(
        id: String = UUID().uuidString,
        eventID: String,
        parentEventID: String? = nil,
        runID: String? = nil,
        workflowID: String? = nil,
        nodeID: String? = nil,
        sourceAgentID: String,
        targetAgentID: String,
        summary: String,
        sessionKey: String? = nil,
        idempotencyKey: String? = nil,
        attempt: Int = 1,
        status: RuntimeDispatchStatus,
        transportKind: OpenClawRuntimeTransportKind,
        timeoutSeconds: Int? = nil,
        allowRetry: Bool = false,
        maxRetries: Int? = nil,
        queuedAt: Date = Date(),
        updatedAt: Date = Date(),
        completedAt: Date? = nil,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.eventID = eventID
        self.parentEventID = parentEventID
        self.runID = runID
        self.workflowID = workflowID
        self.nodeID = nodeID
        self.sourceAgentID = sourceAgentID
        self.targetAgentID = targetAgentID
        self.summary = summary
        self.sessionKey = sessionKey
        self.idempotencyKey = idempotencyKey
        self.attempt = attempt
        self.status = status
        self.transportKind = transportKind
        self.timeoutSeconds = timeoutSeconds
        self.allowRetry = allowRetry
        self.maxRetries = maxRetries
        self.queuedAt = queuedAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
        self.errorMessage = errorMessage
    }
}

// 运行时状态
struct RuntimeState: Codable {
    var sessionID: String
    var messageQueue: [String]
    var dispatchQueue: [RuntimeDispatchRecord]
    var inflightDispatches: [RuntimeDispatchRecord]
    var completedDispatches: [RuntimeDispatchRecord]
    var failedDispatches: [RuntimeDispatchRecord]
    var agentStates: [String: String]
    var runtimeEvents: [OpenClawRuntimeEvent]
    var workflowConfigurationRevision: Int
    var appliedWorkflowConfigurationRevision: Int
    var lastAppliedWorkflowAt: Date?
    var lastUpdated: Date

    enum CodingKeys: String, CodingKey {
        case sessionID
        case messageQueue
        case dispatchQueue
        case inflightDispatches
        case completedDispatches
        case failedDispatches
        case agentStates
        case runtimeEvents
        case workflowConfigurationRevision
        case appliedWorkflowConfigurationRevision
        case lastAppliedWorkflowAt
        case lastUpdated
    }
    
    init() {
        self.sessionID = UUID().uuidString
        self.messageQueue = []
        self.dispatchQueue = []
        self.inflightDispatches = []
        self.completedDispatches = []
        self.failedDispatches = []
        self.agentStates = [:]
        self.runtimeEvents = []
        self.workflowConfigurationRevision = 0
        self.appliedWorkflowConfigurationRevision = 0
        self.lastAppliedWorkflowAt = nil
        self.lastUpdated = Date()
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionID = try container.decodeIfPresent(String.self, forKey: .sessionID) ?? UUID().uuidString
        messageQueue = try container.decodeIfPresent([String].self, forKey: .messageQueue) ?? []
        dispatchQueue = try container.decodeIfPresent([RuntimeDispatchRecord].self, forKey: .dispatchQueue) ?? []
        inflightDispatches = try container.decodeIfPresent([RuntimeDispatchRecord].self, forKey: .inflightDispatches) ?? []
        completedDispatches = try container.decodeIfPresent([RuntimeDispatchRecord].self, forKey: .completedDispatches) ?? []
        failedDispatches = try container.decodeIfPresent([RuntimeDispatchRecord].self, forKey: .failedDispatches) ?? []
        agentStates = try container.decodeIfPresent([String: String].self, forKey: .agentStates) ?? [:]
        runtimeEvents = try container.decodeIfPresent([OpenClawRuntimeEvent].self, forKey: .runtimeEvents) ?? []
        workflowConfigurationRevision = try container.decodeIfPresent(Int.self, forKey: .workflowConfigurationRevision) ?? 0
        appliedWorkflowConfigurationRevision = try container.decodeIfPresent(Int.self, forKey: .appliedWorkflowConfigurationRevision) ?? 0
        lastAppliedWorkflowAt = try container.decodeIfPresent(Date.self, forKey: .lastAppliedWorkflowAt)
        lastUpdated = try container.decodeIfPresent(Date.self, forKey: .lastUpdated) ?? Date()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sessionID, forKey: .sessionID)
        try container.encode(messageQueue, forKey: .messageQueue)
        try container.encode(dispatchQueue, forKey: .dispatchQueue)
        try container.encode(inflightDispatches, forKey: .inflightDispatches)
        try container.encode(completedDispatches, forKey: .completedDispatches)
        try container.encode(failedDispatches, forKey: .failedDispatches)
        try container.encode(agentStates, forKey: .agentStates)
        try container.encode(runtimeEvents, forKey: .runtimeEvents)
        try container.encode(workflowConfigurationRevision, forKey: .workflowConfigurationRevision)
        try container.encode(appliedWorkflowConfigurationRevision, forKey: .appliedWorkflowConfigurationRevision)
        try container.encodeIfPresent(lastAppliedWorkflowAt, forKey: .lastAppliedWorkflowAt)
        try container.encode(lastUpdated, forKey: .lastUpdated)
    }
}

struct ProjectWorkspaceRecord: Codable, Identifiable, Hashable {
    let id: UUID
    var taskID: UUID
    var workspaceRelativePath: String
    var workspaceName: String
    var createdAt: Date
    var updatedAt: Date

    init(
        taskID: UUID,
        workspaceRelativePath: String,
        workspaceName: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = taskID
        self.taskID = taskID
        self.workspaceRelativePath = workspaceRelativePath
        self.workspaceName = workspaceName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct ProjectOpenClawAgentRecord: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var status: String
    var lastReloadedAt: Date?
}

struct ProjectOpenClawDetectedAgentRecord: Codable, Identifiable, Hashable {
    let id: String
    var name: String
    var directoryPath: String?
    var configPath: String?
    var soulPath: String?
    var workspacePath: String?
    var statePath: String?
    var directoryValidated: Bool
    var configValidated: Bool
    var copiedToProjectPath: String?
    var copiedFileCount: Int
    var issues: [String]
    var importedAt: Date?

    init(
        id: String,
        name: String,
        directoryPath: String? = nil,
        configPath: String? = nil,
        soulPath: String? = nil,
        workspacePath: String? = nil,
        statePath: String? = nil,
        directoryValidated: Bool = false,
        configValidated: Bool = false,
        copiedToProjectPath: String? = nil,
        copiedFileCount: Int = 0,
        issues: [String] = [],
        importedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.directoryPath = directoryPath
        self.configPath = configPath
        self.soulPath = soulPath
        self.workspacePath = workspacePath
        self.statePath = statePath
        self.directoryValidated = directoryValidated
        self.configValidated = configValidated
        self.copiedToProjectPath = copiedToProjectPath
        self.copiedFileCount = copiedFileCount
        self.issues = issues
        self.importedAt = importedAt
    }
}

enum OpenClawConnectionPhase: String, Codable {
    case idle
    case discovering
    case probed
    case ready
    case degraded
    case detached
    case failed
}

struct OpenClawConnectionCapabilitiesSnapshot: Codable {
    var cliAvailable: Bool
    var gatewayReachable: Bool
    var gatewayAuthenticated: Bool
    var agentListingAvailable: Bool
    var sessionHistoryAvailable: Bool
    var gatewayAgentAvailable: Bool
    var gatewayChatAvailable: Bool
    var projectAttachmentSupported: Bool

    init(
        cliAvailable: Bool = false,
        gatewayReachable: Bool = false,
        gatewayAuthenticated: Bool = false,
        agentListingAvailable: Bool = false,
        sessionHistoryAvailable: Bool = false,
        gatewayAgentAvailable: Bool = false,
        gatewayChatAvailable: Bool = false,
        projectAttachmentSupported: Bool = false
    ) {
        self.cliAvailable = cliAvailable
        self.gatewayReachable = gatewayReachable
        self.gatewayAuthenticated = gatewayAuthenticated
        self.agentListingAvailable = agentListingAvailable
        self.sessionHistoryAvailable = sessionHistoryAvailable
        self.gatewayAgentAvailable = gatewayAgentAvailable
        self.gatewayChatAvailable = gatewayChatAvailable
        self.projectAttachmentSupported = projectAttachmentSupported
    }
}

struct OpenClawConnectionHealthSnapshot: Codable {
    var lastProbeAt: Date?
    var lastHeartbeatAt: Date?
    var latencyMs: Int?
    var degradationReason: String?
    var lastMessage: String?

    init(
        lastProbeAt: Date? = nil,
        lastHeartbeatAt: Date? = nil,
        latencyMs: Int? = nil,
        degradationReason: String? = nil,
        lastMessage: String? = nil
    ) {
        self.lastProbeAt = lastProbeAt
        self.lastHeartbeatAt = lastHeartbeatAt
        self.latencyMs = latencyMs
        self.degradationReason = degradationReason
        self.lastMessage = lastMessage
    }
}

struct OpenClawConnectionStateSnapshot: Codable {
    var phase: OpenClawConnectionPhase
    var deploymentKind: OpenClawDeploymentKind
    var capabilities: OpenClawConnectionCapabilitiesSnapshot
    var health: OpenClawConnectionHealthSnapshot

    init(
        phase: OpenClawConnectionPhase = .idle,
        deploymentKind: OpenClawDeploymentKind = .local,
        capabilities: OpenClawConnectionCapabilitiesSnapshot = OpenClawConnectionCapabilitiesSnapshot(),
        health: OpenClawConnectionHealthSnapshot = OpenClawConnectionHealthSnapshot()
    ) {
        self.phase = phase
        self.deploymentKind = deploymentKind
        self.capabilities = capabilities
        self.health = health
    }
}

enum OpenClawProbeLayerState: String, Codable {
    case ready
    case degraded
    case unavailable
    case notRequired = "not_required"
}

struct OpenClawProbeLayersSnapshot: Codable {
    var transport: OpenClawProbeLayerState
    var authentication: OpenClawProbeLayerState
    var session: OpenClawProbeLayerState
    var inventory: OpenClawProbeLayerState

    init(
        transport: OpenClawProbeLayerState = .unavailable,
        authentication: OpenClawProbeLayerState = .unavailable,
        session: OpenClawProbeLayerState = .unavailable,
        inventory: OpenClawProbeLayerState = .unavailable
    ) {
        self.transport = transport
        self.authentication = authentication
        self.session = session
        self.inventory = inventory
    }
}

struct OpenClawProbeReportSnapshot: Codable {
    var success: Bool
    var deploymentKind: OpenClawDeploymentKind
    var endpoint: String
    var layers: OpenClawProbeLayersSnapshot?
    var capabilities: OpenClawConnectionCapabilitiesSnapshot
    var health: OpenClawConnectionHealthSnapshot
    var availableAgents: [String]
    var message: String
    var warnings: [String]
    var sourceOfTruth: String
    var observedDefaultTransports: [String]

    enum CodingKeys: String, CodingKey {
        case success
        case deploymentKind
        case endpoint
        case layers
        case capabilities
        case health
        case availableAgents
        case message
        case warnings
        case sourceOfTruth
        case observedDefaultTransports
    }

    init(
        success: Bool = false,
        deploymentKind: OpenClawDeploymentKind = .local,
        endpoint: String = "",
        layers: OpenClawProbeLayersSnapshot? = nil,
        capabilities: OpenClawConnectionCapabilitiesSnapshot = OpenClawConnectionCapabilitiesSnapshot(),
        health: OpenClawConnectionHealthSnapshot = OpenClawConnectionHealthSnapshot(),
        availableAgents: [String] = [],
        message: String = "",
        warnings: [String] = [],
        sourceOfTruth: String = "",
        observedDefaultTransports: [String] = []
    ) {
        self.success = success
        self.deploymentKind = deploymentKind
        self.endpoint = endpoint
        self.layers = layers
        self.capabilities = capabilities
        self.health = health
        self.availableAgents = availableAgents
        self.message = message
        self.warnings = warnings
        self.sourceOfTruth = sourceOfTruth
        self.observedDefaultTransports = observedDefaultTransports
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = try container.decodeIfPresent(Bool.self, forKey: .success) ?? false
        deploymentKind = try container.decodeIfPresent(OpenClawDeploymentKind.self, forKey: .deploymentKind) ?? .local
        endpoint = try container.decodeIfPresent(String.self, forKey: .endpoint) ?? ""
        layers = try container.decodeIfPresent(OpenClawProbeLayersSnapshot.self, forKey: .layers)
        capabilities = try container.decodeIfPresent(OpenClawConnectionCapabilitiesSnapshot.self, forKey: .capabilities)
            ?? OpenClawConnectionCapabilitiesSnapshot()
        health = try container.decodeIfPresent(OpenClawConnectionHealthSnapshot.self, forKey: .health)
            ?? OpenClawConnectionHealthSnapshot()
        availableAgents = try container.decodeIfPresent([String].self, forKey: .availableAgents) ?? []
        message = try container.decodeIfPresent(String.self, forKey: .message) ?? ""
        warnings = try container.decodeIfPresent([String].self, forKey: .warnings) ?? []
        sourceOfTruth = try container.decodeIfPresent(String.self, forKey: .sourceOfTruth) ?? ""
        observedDefaultTransports = try container.decodeIfPresent([String].self, forKey: .observedDefaultTransports) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(success, forKey: .success)
        try container.encode(deploymentKind, forKey: .deploymentKind)
        try container.encode(endpoint, forKey: .endpoint)
        try container.encodeIfPresent(layers, forKey: .layers)
        try container.encode(capabilities, forKey: .capabilities)
        try container.encode(health, forKey: .health)
        try container.encode(availableAgents, forKey: .availableAgents)
        try container.encode(message, forKey: .message)
        try container.encode(warnings, forKey: .warnings)
        try container.encode(sourceOfTruth, forKey: .sourceOfTruth)
        try container.encode(observedDefaultTransports, forKey: .observedDefaultTransports)
    }
}

enum OpenClawRecoveryReportStatus: String, Codable {
    case completed
    case partial
    case manualFollowUp = "manual_follow_up"
    case failed
}

struct OpenClawRecoveryStateSnapshot: Codable {
    var label: String
    var summary: String
    var layers: String

    init(
        label: String = "",
        summary: String = "",
        layers: String = ""
    ) {
        self.label = label
        self.summary = summary
        self.layers = layers
    }
}

struct OpenClawRecoveryReportSnapshot: Codable {
    var createdAt: Date
    var status: OpenClawRecoveryReportStatus
    var summary: String
    var completedSteps: [String]
    var manualSteps: [String]
    var findings: [String]
    var before: OpenClawRecoveryStateSnapshot
    var after: OpenClawRecoveryStateSnapshot

    init(
        createdAt: Date = Date(),
        status: OpenClawRecoveryReportStatus = .completed,
        summary: String = "",
        completedSteps: [String] = [],
        manualSteps: [String] = [],
        findings: [String] = [],
        before: OpenClawRecoveryStateSnapshot = OpenClawRecoveryStateSnapshot(),
        after: OpenClawRecoveryStateSnapshot = OpenClawRecoveryStateSnapshot()
    ) {
        self.createdAt = createdAt
        self.status = status
        self.summary = summary
        self.completedSteps = completedSteps
        self.manualSteps = manualSteps
        self.findings = findings
        self.before = before
        self.after = after
    }
}

struct ProjectOpenClawSnapshot: Codable {
    var config: OpenClawConfig
    var isConnected: Bool
    var availableAgents: [String]
    var activeAgents: [ProjectOpenClawAgentRecord]
    var detectedAgents: [ProjectOpenClawDetectedAgentRecord]
    var connectionState: OpenClawConnectionStateSnapshot
    var lastProbeReport: OpenClawProbeReportSnapshot?
    var recoveryReports: [OpenClawRecoveryReportSnapshot]
    var sessionBackupPath: String?
    var sessionMirrorPath: String?
    var lastSyncedAt: Date

    enum CodingKeys: String, CodingKey {
        case config
        case isConnected
        case availableAgents
        case activeAgents
        case detectedAgents
        case connectionState
        case lastProbeReport
        case recoveryReports
        case sessionBackupPath
        case sessionMirrorPath
        case lastSyncedAt
    }

    init(
        config: OpenClawConfig = .default,
        isConnected: Bool = false,
        availableAgents: [String] = [],
        activeAgents: [ProjectOpenClawAgentRecord] = [],
        detectedAgents: [ProjectOpenClawDetectedAgentRecord] = [],
        connectionState: OpenClawConnectionStateSnapshot = OpenClawConnectionStateSnapshot(),
        lastProbeReport: OpenClawProbeReportSnapshot? = nil,
        recoveryReports: [OpenClawRecoveryReportSnapshot] = [],
        sessionBackupPath: String? = nil,
        sessionMirrorPath: String? = nil,
        lastSyncedAt: Date = Date()
    ) {
        self.config = config
        self.isConnected = isConnected
        self.availableAgents = availableAgents
        self.activeAgents = activeAgents
        self.detectedAgents = detectedAgents
        self.connectionState = connectionState
        self.lastProbeReport = lastProbeReport
        self.recoveryReports = recoveryReports
        self.sessionBackupPath = sessionBackupPath
        self.sessionMirrorPath = sessionMirrorPath
        self.lastSyncedAt = lastSyncedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        config = try container.decodeIfPresent(OpenClawConfig.self, forKey: .config) ?? .default
        isConnected = try container.decodeIfPresent(Bool.self, forKey: .isConnected) ?? false
        availableAgents = try container.decodeIfPresent([String].self, forKey: .availableAgents) ?? []
        activeAgents = try container.decodeIfPresent([ProjectOpenClawAgentRecord].self, forKey: .activeAgents) ?? []
        detectedAgents = try container.decodeIfPresent([ProjectOpenClawDetectedAgentRecord].self, forKey: .detectedAgents) ?? []
        connectionState = try container.decodeIfPresent(OpenClawConnectionStateSnapshot.self, forKey: .connectionState)
            ?? OpenClawConnectionStateSnapshot(
                phase: isConnected ? .ready : .idle,
                deploymentKind: config.deploymentKind
            )
        lastProbeReport = try container.decodeIfPresent(OpenClawProbeReportSnapshot.self, forKey: .lastProbeReport)
        recoveryReports = try container.decodeIfPresent([OpenClawRecoveryReportSnapshot].self, forKey: .recoveryReports) ?? []
        sessionBackupPath = try container.decodeIfPresent(String.self, forKey: .sessionBackupPath)
        sessionMirrorPath = try container.decodeIfPresent(String.self, forKey: .sessionMirrorPath)
        lastSyncedAt = try container.decodeIfPresent(Date.self, forKey: .lastSyncedAt) ?? Date()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(config, forKey: .config)
        try container.encode(isConnected, forKey: .isConnected)
        try container.encode(availableAgents, forKey: .availableAgents)
        try container.encode(activeAgents, forKey: .activeAgents)
        try container.encode(detectedAgents, forKey: .detectedAgents)
        try container.encode(connectionState, forKey: .connectionState)
        try container.encodeIfPresent(lastProbeReport, forKey: .lastProbeReport)
        try container.encode(recoveryReports, forKey: .recoveryReports)
        try container.encodeIfPresent(sessionBackupPath, forKey: .sessionBackupPath)
        try container.encodeIfPresent(sessionMirrorPath, forKey: .sessionMirrorPath)
        try container.encode(lastSyncedAt, forKey: .lastSyncedAt)
    }
}

struct ProjectTaskDataSettings: Codable {
    var workspaceRootPath: String?
    var organizationMode: String
    var lastUpdatedAt: Date

    init(
        workspaceRootPath: String? = nil,
        organizationMode: String = "project/task",
        lastUpdatedAt: Date = Date()
    ) {
        self.workspaceRootPath = workspaceRootPath
        self.organizationMode = organizationMode
        self.lastUpdatedAt = lastUpdatedAt
    }
}

struct TaskMemoryBackupRecord: Codable, Identifiable, Hashable {
    let id: UUID
    var taskID: UUID
    var workspaceRelativePath: String
    var backupLabel: String
    var lastCapturedAt: Date

    init(taskID: UUID, workspaceRelativePath: String, backupLabel: String, lastCapturedAt: Date = Date()) {
        self.id = taskID
        self.taskID = taskID
        self.workspaceRelativePath = workspaceRelativePath
        self.backupLabel = backupLabel
        self.lastCapturedAt = lastCapturedAt
    }
}

struct AgentMemoryBackupRecord: Codable, Identifiable, Hashable {
    let id: UUID
    var agentID: UUID
    var agentName: String
    var sourcePath: String?
    var lastCapturedAt: Date

    init(agentID: UUID, agentName: String, sourcePath: String? = nil, lastCapturedAt: Date = Date()) {
        self.id = agentID
        self.agentID = agentID
        self.agentName = agentName
        self.sourcePath = sourcePath
        self.lastCapturedAt = lastCapturedAt
    }
}

struct ProjectMemoryData: Codable {
    var backupOnly: Bool
    var taskExecutionMemories: [TaskMemoryBackupRecord]
    var agentMemories: [AgentMemoryBackupRecord]
    var lastBackupAt: Date?

    init(
        backupOnly: Bool = true,
        taskExecutionMemories: [TaskMemoryBackupRecord] = [],
        agentMemories: [AgentMemoryBackupRecord] = [],
        lastBackupAt: Date? = nil
    ) {
        self.backupOnly = backupOnly
        self.taskExecutionMemories = taskExecutionMemories
        self.agentMemories = agentMemories
        self.lastBackupAt = lastBackupAt
    }
}

struct MAProject: Codable, Identifiable {
    let id: UUID
    var fileVersion: String
    var name: String
    var agents: [Agent]
    var workflows: [Workflow]
    var permissions: [Permission]
    var openClaw: ProjectOpenClawSnapshot
    var taskData: ProjectTaskDataSettings
    var tasks: [Task]
    var messages: [Message]
    var executionResults: [ExecutionResult]
    var executionLogs: [ExecutionLogEntry]
    var workspaceIndex: [ProjectWorkspaceRecord]
    var memoryData: ProjectMemoryData
    var runtimeState: RuntimeState
    var createdAt: Date
    var updatedAt: Date
    
    // 显式实现 Codable
    enum CodingKeys: String, CodingKey {
        case id
        case fileVersion
        case name
        case agents
        case workflows
        case permissions
        case openClaw
        case taskData
        case tasks
        case messages
        case executionResults
        case executionLogs
        case workspaceIndex
        case memoryData
        case runtimeState
        case createdAt
        case updatedAt
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        fileVersion = try container.decodeIfPresent(String.self, forKey: .fileVersion) ?? "2.0"
        name = try container.decode(String.self, forKey: .name)
        agents = try container.decode([Agent].self, forKey: .agents)
        workflows = try container.decode([Workflow].self, forKey: .workflows)
        permissions = try container.decode([Permission].self, forKey: .permissions)
        openClaw = try container.decodeIfPresent(ProjectOpenClawSnapshot.self, forKey: .openClaw) ?? ProjectOpenClawSnapshot()
        taskData = try container.decodeIfPresent(ProjectTaskDataSettings.self, forKey: .taskData) ?? ProjectTaskDataSettings()
        tasks = try container.decodeIfPresent([Task].self, forKey: .tasks) ?? []
        messages = try container.decodeIfPresent([Message].self, forKey: .messages) ?? []
        executionResults = try container.decodeIfPresent([ExecutionResult].self, forKey: .executionResults) ?? []
        executionLogs = try container.decodeIfPresent([ExecutionLogEntry].self, forKey: .executionLogs) ?? []
        workspaceIndex = try container.decodeIfPresent([ProjectWorkspaceRecord].self, forKey: .workspaceIndex) ?? []
        memoryData = try container.decodeIfPresent(ProjectMemoryData.self, forKey: .memoryData) ?? ProjectMemoryData()
        runtimeState = (try? container.decode(RuntimeState.self, forKey: .runtimeState)) ?? RuntimeState()
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(fileVersion, forKey: .fileVersion)
        try container.encode(name, forKey: .name)
        try container.encode(agents, forKey: .agents)
        try container.encode(workflows, forKey: .workflows)
        try container.encode(permissions, forKey: .permissions)
        try container.encode(openClaw, forKey: .openClaw)
        try container.encode(taskData, forKey: .taskData)
        try container.encode(tasks, forKey: .tasks)
        try container.encode(messages, forKey: .messages)
        try container.encode(executionResults, forKey: .executionResults)
        try container.encode(executionLogs, forKey: .executionLogs)
        try container.encode(workspaceIndex, forKey: .workspaceIndex)
        try container.encode(memoryData, forKey: .memoryData)
        try container.encode(runtimeState, forKey: .runtimeState)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
    
    init(name: String) {
        self.id = UUID()
        self.fileVersion = "2.0"
        self.name = name
        self.agents = []
        self.workflows = [Workflow(name: "Main Workflow")]
        self.permissions = []
        self.openClaw = ProjectOpenClawSnapshot()
        self.taskData = ProjectTaskDataSettings()
        self.tasks = []
        self.messages = []
        self.executionResults = []
        self.executionLogs = []
        self.workspaceIndex = []
        self.memoryData = ProjectMemoryData()
        self.runtimeState = RuntimeState()
        self.createdAt = Date()
        self.updatedAt = Date()
    }
    
    // 获取两个Agent之间的权限
    func permission(from: Agent, to: Agent) -> PermissionType {
        if from.id == to.id {
            return .allow  // 自身总是允许
        }

        if let explicitPermission = permissions.first(where: {
            $0.fromAgentID == from.id && $0.toAgentID == to.id
        }) {
            return explicitPermission.permissionType
        }

        if isConversationAllowed(from: from.id, to: to.id) {
            return .allow
        }

        return .deny
    }
    
    // 设置权限
    mutating func setPermission(from: Agent, to: Agent, type: PermissionType) {
        if from.id == to.id {
            return  // 不设置自身权限
        }
        
        if let index = permissions.firstIndex(where: {
            $0.fromAgentID == from.id && $0.toAgentID == to.id
        }) {
            if type == .allow && permissions[index].permissionType == .allow {
                // 如果是默认值，删除权限条目
                permissions.remove(at: index)
            } else {
                permissions[index].permissionType = type
                permissions[index].updatedAt = Date()
            }
        } else if type != .allow {
            // 只存储非默认权限
            let permission = Permission(
                fromAgentID: from.id,
                toAgentID: to.id,
                permissionType: type
            )
            permissions.append(permission)
        }
    }

    mutating func removePermission(fromAgentID: UUID, toAgentID: UUID) {
        permissions.removeAll {
            $0.fromAgentID == fromAgentID && $0.toAgentID == toAgentID
        }
    }

    func isConversationAllowed(from fromAgentID: UUID, to toAgentID: UUID) -> Bool {
        guard fromAgentID != toAgentID else { return true }

        for workflow in workflows {
            guard let fromNode = workflow.nodes.first(where: { $0.agentID == fromAgentID && $0.type == .agent }),
                  let toNode = workflow.nodes.first(where: { $0.agentID == toAgentID && $0.type == .agent }) else {
                continue
            }

            if workflow.edges.contains(where: {
                $0.fromNodeID == fromNode.id && $0.toNodeID == toNode.id
            }) {
                return true
            }
        }

        return false
    }

    func fileAccessAllowed(from fromAgentID: UUID, to toAgentID: UUID) -> Bool {
        guard fromAgentID != toAgentID else { return true }

        for workflow in workflows {
            guard let fromNode = workflow.nodes.first(where: { $0.agentID == fromAgentID && $0.type == .agent }),
                  let toNode = workflow.nodes.first(where: { $0.agentID == toAgentID && $0.type == .agent }) else {
                continue
            }

            if let sourceBoundary = workflow.boundary(containing: fromNode.position) {
                return sourceBoundary.contains(point: toNode.position)
            }

            if workflow.boundary(containing: toNode.position) != nil {
                return true
            }
        }

        return true
    }
}
