import Foundation
import CoreGraphics

struct ProjectStorageManifest: Codable, Equatable {
    static let currentSchemaVersion = "project.storage.v1"
    static let currentSnapshotRelativePath = "snapshot/current.maoproj"

    var schemaVersion: String
    var storageRevision: Int
    var projectID: UUID
    var projectName: String
    var fileVersion: String
    var sourceProjectFilePath: String?
    var currentSnapshotRelativePath: String
    var createdAt: Date
    var updatedAt: Date
    var lastOpenedAt: Date?
    var lastSnapshotAt: Date?

    init(
        storageRevision: Int = 1,
        projectID: UUID,
        projectName: String,
        fileVersion: String,
        sourceProjectFilePath: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastOpenedAt: Date? = nil,
        lastSnapshotAt: Date? = nil
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.storageRevision = storageRevision
        self.projectID = projectID
        self.projectName = projectName
        self.fileVersion = fileVersion
        self.sourceProjectFilePath = sourceProjectFilePath
        self.currentSnapshotRelativePath = Self.currentSnapshotRelativePath
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastOpenedAt = lastOpenedAt
        self.lastSnapshotAt = lastSnapshotAt
    }
}

enum ProjectFileSystemError: LocalizedError, Equatable {
    case missingAgentDefinition(nodeID: UUID, agentID: UUID)
    case duplicateNodeAgentBinding(agentID: UUID, firstNodeID: UUID, duplicateNodeID: UUID)
    case missingDesignDocument(path: String)
    case missingNodeAgentDocument(nodeID: UUID, agentID: UUID)
    case agentBindingMismatch(nodeID: UUID, expectedAgentID: UUID, actualAgentID: UUID)

    var errorDescription: String? {
        switch self {
        case let .missingAgentDefinition(nodeID, agentID):
            return "Node \(nodeID.uuidString) references missing agent \(agentID.uuidString)."
        case let .duplicateNodeAgentBinding(agentID, firstNodeID, duplicateNodeID):
            return """
            Agent \(agentID.uuidString) is bound to multiple nodes: \
            \(firstNodeID.uuidString) and \(duplicateNodeID.uuidString).
            """
        case let .missingDesignDocument(path):
            return "Missing required project design document at \(path)."
        case let .missingNodeAgentDocument(nodeID, agentID):
            return "Missing node-local agent document for node \(nodeID.uuidString) and agent \(agentID.uuidString)."
        case let .agentBindingMismatch(nodeID, expectedAgentID, actualAgentID):
            return """
            Node \(nodeID.uuidString) expects agent \(expectedAgentID.uuidString), \
            but design files resolve to \(actualAgentID.uuidString).
            """
        }
    }
}

private struct AgentAssemblySeed: Codable {
    var id: UUID
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
}

private struct WorkflowAssemblySeed: Codable {
    var id: UUID
    var name: String
    var fallbackRoutingPolicy: WorkflowFallbackRoutingPolicy
    var launchTestCases: [WorkflowLaunchTestCase]
    var lastLaunchVerificationReport: WorkflowLaunchVerificationReport?
    var nodes: [WorkflowNode]
    var edges: [WorkflowEdge]
    var boundaries: [WorkflowBoundary]
    var colorGroups: [CanvasColorGroup]
    var createdAt: Date
    var parentNodeID: UUID?
    var inputSchema: [SubflowParameter]
    var outputSchema: [SubflowParameter]
}

private struct ProjectAssemblySeed: Codable {
    var id: UUID
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
}

private struct ProjectDesignDocument: Codable, Equatable {
    var projectID: UUID
    var projectName: String
    var fileVersion: String
    var workflowIDs: [UUID]
    var createdAt: Date
    var updatedAt: Date
}

private struct WorkflowDesignDocument: Codable, Equatable {
    var id: UUID
    var name: String
    var fallbackRoutingPolicy: WorkflowFallbackRoutingPolicy
    var launchTestCases: [WorkflowLaunchTestCase]
    var lastLaunchVerificationReport: WorkflowLaunchVerificationReport?
    var colorGroups: [CanvasColorGroup]
    var createdAt: Date
    var parentNodeID: UUID?
    var inputSchema: [SubflowParameter]
    var outputSchema: [SubflowParameter]
    var nodeIDs: [UUID]
    var edgeIDs: [UUID]
    var boundaryIDs: [UUID]
}

private struct NodeDesignDocument: Codable, Equatable {
    var id: UUID
    var workflowID: UUID
    var agentID: UUID?
    var type: WorkflowNode.NodeType
    var position: CGPoint
    var title: String
    var displayColorHex: String?
    var conditionExpression: String
    var loopEnabled: Bool
    var maxIterations: Int
    var subflowID: UUID?
    var nestingLevel: Int
    var inputParameters: [SubflowParameter]
    var outputParameters: [SubflowParameter]
}

private struct NodeAgentDesignDocument: Codable, Equatable {
    var id: UUID
    var nodeID: UUID
    var name: String
    var identity: String
    var description: String
    var capabilities: [String]
    var colorHex: String?
    var createdAt: Date
    var updatedAt: Date
    var openClawDefinition: OpenClawAgentDefinition
}

private struct NodeOpenClawBindingDocument: Codable, Equatable {
    var nodeID: UUID
    var agentID: UUID
    var agentIdentifier: String
    var modelIdentifier: String
    var runtimeProfile: String
    var memoryBackupPath: String?
    var soulSourcePath: String?
    var lastImportedSoulHash: String?
    var lastImportedSoulPath: String?
    var lastImportedAt: Date?
    var environment: [String: String]
}

private struct NodeOpenClawSourceMapDocument: Codable, Equatable {
    var nodeID: UUID
    var agentID: UUID
    var agentIdentifier: String
    var soulSourcePath: String?
    var mirroredSoulRelativePath: String
    var memoryBackupPath: String?
    var mirroredWorkspaceRelativePath: String
    var generatedAt: Date
}

private struct NodeOpenClawSyncBaselineDocument: Codable, Equatable {
    var nodeID: UUID
    var agentID: UUID
    var lastImportedSoulHash: String?
    var lastImportedSoulPath: String?
    var lastImportedAt: Date?
    var generatedAt: Date
}

private struct NodeOpenClawImportRecordDocument: Codable, Equatable {
    var nodeID: UUID
    var agentID: UUID
    var agentIdentifier: String
    var soulSourcePath: String?
    var memoryBackupPath: String?
    var lastImportedSoulHash: String?
    var lastImportedSoulPath: String?
    var lastImportedAt: Date?
    var generatedAt: Date
}

private struct AnalyticsOverviewProjectionDocument: Codable, Equatable {
    var projectID: UUID
    var generatedAt: Date
    var workflowCount: Int
    var nodeCount: Int
    var agentCount: Int
    var taskCount: Int
    var messageCount: Int
    var executionResultCount: Int
    var completedExecutionCount: Int
    var failedExecutionCount: Int
    var warningLogCount: Int
    var errorLogCount: Int
    var pendingApprovalCount: Int
}

private struct AnalyticsTraceProjectionEntry: Codable, Equatable {
    var executionID: UUID
    var nodeID: UUID
    var agentID: UUID
    var sessionID: String?
    var status: ExecutionStatus
    var outputType: ExecutionOutputType
    var startedAt: Date
    var completedAt: Date?
    var duration: TimeInterval?
    var protocolRepairCount: Int
    var previewText: String
}

private struct AnalyticsTraceProjectionDocument: Codable, Equatable {
    var projectID: UUID
    var generatedAt: Date
    var traces: [AnalyticsTraceProjectionEntry]
}

private struct AnalyticsAnomalyProjectionEntry: Codable, Equatable {
    var id: String
    var source: String
    var severity: String
    var message: String
    var nodeID: UUID?
    var agentID: UUID?
    var sessionID: String?
    var timestamp: Date
}

private struct AnalyticsAnomalyProjectionDocument: Codable, Equatable {
    var projectID: UUID
    var generatedAt: Date
    var anomalies: [AnalyticsAnomalyProjectionEntry]
}

private struct AnalyticsLiveRunWorkflowProjectionEntry: Codable, Equatable {
    var workflowID: UUID
    var workflowName: String
    var sessionCount: Int
    var activeSessionCount: Int
    var activeNodeCount: Int
    var failedNodeCount: Int
    var waitingApprovalNodeCount: Int
    var lastUpdatedAt: Date?
}

private struct AnalyticsLiveRunProjectionDocument: Codable, Equatable {
    var projectID: UUID
    var generatedAt: Date
    var runtimeSessionID: String
    var activeSessionCount: Int
    var totalSessionCount: Int
    var queuedDispatchCount: Int
    var inflightDispatchCount: Int
    var failedDispatchCount: Int
    var waitingApprovalCount: Int
    var latestErrorText: String?
    var activeWorkflowCount: Int
    var workflows: [AnalyticsLiveRunWorkflowProjectionEntry]
}

private struct AnalyticsSessionProjectionEntry: Codable, Equatable {
    var sessionID: String
    var sessionType: String
    var threadID: String?
    var workflowIDs: [String]
    var plannedTransport: String?
    var actualTransport: String?
    var actualTransportKinds: [String]
    var messageCount: Int
    var taskCount: Int
    var eventCount: Int
    var dispatchCount: Int
    var receiptCount: Int
    var queuedDispatchCount: Int
    var inflightDispatchCount: Int
    var completedDispatchCount: Int
    var failedDispatchCount: Int
    var latestFailureText: String?
    var fallbackReason: String?
    var degradationReason: String?
    var lastUpdatedAt: Date?
    var isProjectRuntimeSession: Bool
}

private struct AnalyticsSessionProjectionDocument: Codable, Equatable {
    var projectID: UUID
    var generatedAt: Date
    var sessions: [AnalyticsSessionProjectionEntry]
}

private struct AnalyticsNodeRuntimeProjectionEntry: Codable, Equatable {
    var workflowID: UUID
    var workflowName: String
    var nodeID: UUID
    var title: String
    var agentID: UUID?
    var agentName: String?
    var status: String
    var incomingEdgeCount: Int
    var outgoingEdgeCount: Int
    var relatedSessionIDs: [String]
    var queuedDispatchCount: Int
    var inflightDispatchCount: Int
    var completedDispatchCount: Int
    var failedDispatchCount: Int
    var waitingApprovalCount: Int
    var receiptCount: Int
    var averageDuration: TimeInterval?
    var lastUpdatedAt: Date?
    var latestDetail: String?
}

private struct AnalyticsNodeRuntimeProjectionDocument: Codable, Equatable {
    var projectID: UUID
    var generatedAt: Date
    var nodes: [AnalyticsNodeRuntimeProjectionEntry]
}

private struct AnalyticsThreadProjectionEntry: Codable, Equatable {
    var threadID: String
    var threadType: String
    var mode: String
    var sessionID: String
    var linkedSessionIDs: [String]
    var workflowID: UUID?
    var workflowName: String?
    var entryAgentName: String?
    var participantNames: [String]
    var status: String
    var startedAt: Date?
    var lastUpdatedAt: Date?
    var messageCount: Int
    var taskCount: Int
    var pendingApprovalCount: Int
    var blockedTaskCount: Int
    var activeTaskCount: Int
    var completedTaskCount: Int
    var failedMessageCount: Int
}

private struct AnalyticsThreadProjectionDocument: Codable, Equatable {
    var projectID: UUID
    var generatedAt: Date
    var threads: [AnalyticsThreadProjectionEntry]
}

private struct AnalyticsWorkflowHealthProjectionEntry: Codable, Equatable {
    var workflowID: UUID
    var workflowName: String
    var nodeCount: Int
    var edgeCount: Int
    var sessionCount: Int
    var activeNodeCount: Int
    var failedNodeCount: Int
    var waitingApprovalNodeCount: Int
    var completedNodeCount: Int
    var idleNodeCount: Int
    var recentFailureCount: Int
    var pendingApprovalCount: Int
    var lastUpdatedAt: Date?
}

private struct AnalyticsWorkflowHealthProjectionDocument: Codable, Equatable {
    var projectID: UUID
    var generatedAt: Date
    var workflows: [AnalyticsWorkflowHealthProjectionEntry]
}

private struct WorkflowCommunicationRouteDocument: Codable, Equatable {
    var edgeID: UUID
    var fromNodeID: UUID
    var toNodeID: UUID
    var fromAgentID: UUID?
    var toAgentID: UUID?
    var permissionType: PermissionType
    var requiresApproval: Bool
    var isBidirectional: Bool
    var isImplicitReverse: Bool
    var label: String
    var conditionExpression: String
}

private struct WorkflowCommunicationMatrixDocument: Codable, Equatable {
    var workflowID: UUID
    var generatedAt: Date
    var routes: [WorkflowCommunicationRouteDocument]
}

private struct WorkflowBoundaryScopeDocument: Codable, Equatable {
    var boundaryID: UUID
    var title: String
    var memberNodeIDs: [UUID]
    var geometryContainedNodeIDs: [UUID]
}

private struct WorkflowNodeFileAccessDocument: Codable, Equatable {
    var nodeID: UUID
    var agentID: UUID?
    var enclosingBoundaryID: UUID?
    var readableNodeIDs: [UUID]
    var restrictedNodeIDs: [UUID]
}

private struct WorkflowFileScopeMapDocument: Codable, Equatable {
    var workflowID: UUID
    var generatedAt: Date
    var defaultAccess: PermissionType
    var boundaryScopes: [WorkflowBoundaryScopeDocument]
    var nodeScopes: [WorkflowNodeFileAccessDocument]
}

private struct WorkflowLaunchReportDocument: Codable, Equatable {
    var workflowID: UUID
    var generatedAt: Date
    var report: WorkflowLaunchVerificationReport?
}

private typealias ArchivedWorkbenchThreadMode = WorkbenchThreadSemanticMode
private typealias ArchivedRuntimeSessionType = RuntimeSessionSemanticType

private struct WorkbenchThreadLinkSnapshot {
    var threadID: String
    var threadType: ArchivedRuntimeSessionType
    var threadMode: ArchivedWorkbenchThreadMode
    var workflowID: UUID?
    var entryAgentID: UUID?
    var entryAgentName: String?
    var gatewaySessionKey: String?
}

private struct RuntimeSessionArchiveClassification {
    var sessionType: ArchivedRuntimeSessionType
    var threadID: String?
    var workflowID: UUID?
    var entryAgentID: UUID?
    var entryAgentName: String?
}

private struct RuntimeTransportPlanDocument: Codable {
    var sessionID: String
    var sessionType: String
    var threadID: String?
    var requestedMode: String
    var resolvedMode: String
    var preferredTransport: String?
    var actualTransport: String?
    var actualTransportKinds: [String]
    var capabilitySnapshot: [String: String]
    var fallbackReason: String?
    var degradationReason: String?
    var generatedAt: Date
}

private struct WorkbenchThreadDocument: Codable {
    var threadID: String
    var threadType: String
    var mode: String
    var sessionID: String
    var linkedSessionIDs: [String]
    var workflowID: UUID?
    var workflowName: String?
    var entryAgentID: UUID?
    var entryAgentName: String?
    var status: String
    var startedAt: Date
    var lastUpdatedAt: Date
    var messageCount: Int
    var taskCount: Int
    var pendingApprovalCount: Int
    var latestMessageID: UUID?
    var latestTaskID: UUID?
}

private struct WorkbenchThreadContextDocument: Codable {
    var threadID: String
    var sessionID: String
    var workflowID: UUID?
    var workflowName: String?
    var taskIDs: [UUID]
    var messageIDs: [UUID]
    var participantAgentIDs: [UUID]
    var entryAgentID: UUID?
    var entryAgentName: String?
}

private struct WorkbenchThreadInvestigationDocument: Codable {
    var threadID: String
    var sessionID: String
    var workflowID: UUID?
    var workflowName: String?
    var entryAgentID: UUID?
    var entryAgentName: String?
    var participantAgentIDs: [UUID]
    var relatedNodeIDs: [UUID]
    var status: String
    var startedAt: Date
    var lastUpdatedAt: Date
    var messageCount: Int
    var taskCount: Int
    var pendingApprovalCount: Int
    var dispatchCount: Int
    var eventCount: Int
    var receiptCount: Int
    var latestMessageID: UUID?
    var latestTaskID: UUID?
}

private struct WorkbenchTurnAuditDocument: Codable {
    var turnID: UUID
    var threadID: String
    var sessionID: String
    var workflowID: UUID?
    var taskID: UUID?
    var messageID: UUID
    var role: String
    var kind: String
    var status: String
    var agentID: UUID?
    var agentName: String?
    var executionIntent: String?
    var threadType: String?
    var threadMode: String?
    var interactionMode: String?
    var outputType: String?
    var tokenEstimate: Int?
    var summary: String
    var timestamp: Date
}

private struct WorkbenchDelegationAuditDocument: Codable {
    var delegationID: String
    var threadID: String
    var sessionID: String
    var workflowID: String?
    var nodeID: String?
    var parentDelegationID: String?
    var sourceAgentID: String
    var sourceAgentName: String?
    var targetAgentID: String
    var targetAgentName: String?
    var status: String
    var eventType: String?
    var executionIntent: String?
    var threadType: String?
    var threadMode: String?
    var transportKind: String
    var attempt: Int
    var allowRetry: Bool
    var maxRetries: Int?
    var summary: String
    var errorMessage: String?
    var queuedAt: Date
    var updatedAt: Date
    var completedAt: Date?
}

private struct RuntimeSessionSpanAuditDocument: Codable {
    var spanID: UUID
    var sessionID: String
    var threadID: String?
    var workflowID: UUID?
    var nodeID: UUID
    var agentID: UUID
    var agentName: String?
    var status: String
    var executionIntent: String?
    var transportKind: String?
    var outputType: String
    var linkedEventIDs: [String]
    var primaryEventID: String?
    var parentEventID: String?
    var routingAction: String?
    var routingTargets: [String]
    var requestedRoutingAction: String?
    var requestedRoutingTargets: [String]
    var protocolRepairCount: Int
    var protocolRepairTypes: [String]
    var protocolSafeDegradeApplied: Bool
    var summary: String
    var startedAt: Date
    var completedAt: Date?
    var duration: TimeInterval?
    var firstChunkLatencyMs: Int?
    var completionLatencyMs: Int?
}

private struct RuntimeQueueStateDocument: Codable {
    var generatedAt: Date
    var messageQueue: [String]
    var queuedDispatches: [RuntimeDispatchRecord]
    var inflightDispatches: [RuntimeDispatchRecord]
    var completedDispatches: [RuntimeDispatchRecord]
    var failedDispatches: [RuntimeDispatchRecord]
}

private struct RuntimeDispatchEnvelopeDocument: Codable {
    var stateBucket: String
    var record: RuntimeDispatchRecord
}

private struct RuntimeSessionDocument: Codable {
    var sessionID: String
    var sessionType: String
    var threadID: String?
    var storageDirectoryName: String
    var generatedAt: Date
    var workflowID: UUID?
    var entryAgentID: UUID?
    var entryAgentName: String?
    var workflowIDs: [String]
    var plannedTransport: String?
    var actualTransport: String?
    var actualTransportKinds: [String]
    var fallbackReason: String?
    var degradationReason: String?
    var eventCount: Int
    var dispatchCount: Int
    var receiptCount: Int
    var queuedDispatchCount: Int
    var inflightDispatchCount: Int
    var completedDispatchCount: Int
    var failedDispatchCount: Int
    var latestEventAt: Date?
    var latestReceiptAt: Date?
    var lastUpdatedAt: Date?
    var isProjectRuntimeSession: Bool
}

private struct WorkflowIndexEntryDocument: Codable {
    var workflowID: UUID
    var name: String
    var parentNodeID: UUID?
    var nodeCount: Int
    var edgeCount: Int
    var boundaryCount: Int
    var createdAt: Date
}

private struct NodeIndexEntryDocument: Codable {
    var workflowID: UUID
    var nodeID: UUID
    var agentID: UUID?
    var type: WorkflowNode.NodeType
    var title: String
    var position: CGPoint
    var boundaryID: UUID?
}

private struct ThreadIndexEntryDocument: Codable {
    var threadID: String
    var threadType: String
    var mode: String
    var sessionID: String
    var workflowID: UUID?
    var entryAgentID: UUID?
    var entryAgentName: String?
    var status: String
    var messageCount: Int
    var taskCount: Int
    var lastUpdatedAt: Date
}

private struct RuntimeSessionIndexEntryDocument: Codable {
    var sessionID: String
    var sessionType: String
    var threadID: String?
    var storageDirectoryName: String
    var plannedTransport: String?
    var actualTransport: String?
    var eventCount: Int
    var dispatchCount: Int
    var receiptCount: Int
    var lastUpdatedAt: Date?
    var isProjectRuntimeSession: Bool
}

struct ProjectFileSystem {
    static let shared = ProjectFileSystem()
    static let managedOpenClawWorkspaceMarkdownFiles: [String] = [
        "SOUL.md",
        "AGENTS.md",
        "IDENTITY.md",
        "USER.md",
        "TOOLS.md",
        "HEARTBEAT.md",
        "BOOTSTRAP.md",
        "MEMORY.md",
    ]

    private static let derivedDocumentNames: Set<String> = [
        "communication-matrix.json",
        "file-scope-map.json",
        "launch-report.json",
    ]

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func managedProjectsRootDirectory(under appSupportRootDirectory: URL) -> URL {
        appSupportRootDirectory.appendingPathComponent("Projects", isDirectory: true)
    }

    func managedProjectRootDirectory(for projectID: UUID, under appSupportRootDirectory: URL) -> URL {
        managedProjectsRootDirectory(under: appSupportRootDirectory)
            .appendingPathComponent(projectID.uuidString, isDirectory: true)
    }

    func manifestURL(for projectID: UUID, under appSupportRootDirectory: URL) -> URL {
        managedProjectRootDirectory(for: projectID, under: appSupportRootDirectory)
            .appendingPathComponent("manifest.json", isDirectory: false)
    }

    func currentSnapshotURL(for projectID: UUID, under appSupportRootDirectory: URL) -> URL {
        managedProjectRootDirectory(for: projectID, under: appSupportRootDirectory)
            .appendingPathComponent(ProjectStorageManifest.currentSnapshotRelativePath, isDirectory: false)
    }

    func tasksRootDirectory(for projectID: UUID, under appSupportRootDirectory: URL) -> URL {
        managedProjectRootDirectory(for: projectID, under: appSupportRootDirectory)
            .appendingPathComponent("tasks", isDirectory: true)
    }

    func tasksListURL(for projectID: UUID, under appSupportRootDirectory: URL) -> URL {
        tasksRootDirectory(for: projectID, under: appSupportRootDirectory)
            .appendingPathComponent("tasks.json", isDirectory: false)
    }

    func workspaceIndexURL(for projectID: UUID, under appSupportRootDirectory: URL) -> URL {
        tasksRootDirectory(for: projectID, under: appSupportRootDirectory)
            .appendingPathComponent("workspace-index.json", isDirectory: false)
    }

    func taskWorkspaceRootDirectory(for projectID: UUID, under appSupportRootDirectory: URL) -> URL {
        tasksRootDirectory(for: projectID, under: appSupportRootDirectory)
            .appendingPathComponent("workspaces", isDirectory: true)
    }

    func openClawSessionRootDirectory(for projectID: UUID, under appSupportRootDirectory: URL) -> URL {
        managedProjectRootDirectory(for: projectID, under: appSupportRootDirectory)
            .appendingPathComponent("openclaw/session", isDirectory: true)
    }

    func openClawBackupDirectory(for projectID: UUID, under appSupportRootDirectory: URL) -> URL {
        openClawSessionRootDirectory(for: projectID, under: appSupportRootDirectory)
            .appendingPathComponent("backup", isDirectory: true)
    }

    func openClawMirrorDirectory(for projectID: UUID, under appSupportRootDirectory: URL) -> URL {
        openClawSessionRootDirectory(for: projectID, under: appSupportRootDirectory)
            .appendingPathComponent("mirror", isDirectory: true)
    }

    func openClawImportedAgentsDirectory(for projectID: UUID, under appSupportRootDirectory: URL) -> URL {
        openClawSessionRootDirectory(for: projectID, under: appSupportRootDirectory)
            .appendingPathComponent("agents", isDirectory: true)
    }

    func designWorkflowRootDirectory(
        for workflowID: UUID,
        projectID: UUID,
        under appSupportRootDirectory: URL
    ) -> URL {
        managedProjectRootDirectory(for: projectID, under: appSupportRootDirectory)
            .appendingPathComponent("design/workflows", isDirectory: true)
            .appendingPathComponent(workflowID.uuidString, isDirectory: true)
    }

    func designNodeRootDirectory(
        for nodeID: UUID,
        workflowID: UUID,
        projectID: UUID,
        under appSupportRootDirectory: URL
    ) -> URL {
        designWorkflowRootDirectory(for: workflowID, projectID: projectID, under: appSupportRootDirectory)
            .appendingPathComponent("nodes", isDirectory: true)
            .appendingPathComponent(nodeID.uuidString, isDirectory: true)
    }

    func nodeOpenClawRootDirectory(
        for nodeID: UUID,
        workflowID: UUID,
        projectID: UUID,
        under appSupportRootDirectory: URL
    ) -> URL {
        designNodeRootDirectory(for: nodeID, workflowID: workflowID, projectID: projectID, under: appSupportRootDirectory)
            .appendingPathComponent("openclaw", isDirectory: true)
    }

    func nodeOpenClawWorkspaceDirectory(
        for nodeID: UUID,
        workflowID: UUID,
        projectID: UUID,
        under appSupportRootDirectory: URL
    ) -> URL {
        nodeOpenClawRootDirectory(for: nodeID, workflowID: workflowID, projectID: projectID, under: appSupportRootDirectory)
            .appendingPathComponent("workspace", isDirectory: true)
    }

    func nodeOpenClawSoulURL(
        for nodeID: UUID,
        workflowID: UUID,
        projectID: UUID,
        under appSupportRootDirectory: URL
    ) -> URL {
        nodeOpenClawWorkspaceDirectory(
            for: nodeID,
            workflowID: workflowID,
            projectID: projectID,
            under: appSupportRootDirectory
        )
        .appendingPathComponent("SOUL.md", isDirectory: false)
    }

    func nodeOpenClawWorkspaceDocumentURL(
        for nodeID: UUID,
        workflowID: UUID,
        projectID: UUID,
        fileName: String,
        under appSupportRootDirectory: URL
    ) -> URL {
        nodeOpenClawWorkspaceDirectory(
            for: nodeID,
            workflowID: workflowID,
            projectID: projectID,
            under: appSupportRootDirectory
        )
        .appendingPathComponent(fileName, isDirectory: false)
    }

    func isManagedOpenClawWorkspaceMarkdownFile(_ fileName: String) -> Bool {
        Self.managedOpenClawWorkspaceMarkdownFiles.contains(fileName)
    }

    func defaultManagedOpenClawWorkspaceDocument(
        named fileName: String,
        agent: Agent,
        nodeID: UUID
    ) -> String? {
        switch fileName {
        case "AGENTS.md":
            return renderAgentsMarkdown(agent: agent, nodeID: nodeID)
        case "IDENTITY.md":
            return renderIdentityMarkdown(agent: agent)
        case "USER.md":
            return renderUserMarkdown(agent: agent)
        case "TOOLS.md":
            return renderToolsMarkdown(agent: agent)
        case "BOOTSTRAP.md":
            return renderBootstrapMarkdown(agent: agent)
        case "HEARTBEAT.md":
            return renderHeartbeatMarkdown(agent: agent)
        case "MEMORY.md":
            return renderMemoryMarkdown(agent: agent)
        case "SOUL.md":
            return agent.soulMD
        default:
            return nil
        }
    }

    func analyticsRootDirectory(for projectID: UUID, under appSupportRootDirectory: URL) -> URL {
        managedProjectRootDirectory(for: projectID, under: appSupportRootDirectory)
            .appendingPathComponent("analytics", isDirectory: true)
    }

    func analyticsDatabaseURL(for projectID: UUID, under appSupportRootDirectory: URL) -> URL {
        analyticsRootDirectory(for: projectID, under: appSupportRootDirectory)
            .appendingPathComponent("analytics.sqlite", isDirectory: false)
    }

    func analyticsProjectionDirectory(for projectID: UUID, under appSupportRootDirectory: URL) -> URL {
        analyticsRootDirectory(for: projectID, under: appSupportRootDirectory)
            .appendingPathComponent("projections", isDirectory: true)
    }

    func analyticsOverviewProjectionURL(for projectID: UUID, under appSupportRootDirectory: URL) -> URL {
        analyticsProjectionDirectory(for: projectID, under: appSupportRootDirectory)
            .appendingPathComponent("overview.json", isDirectory: false)
    }

    func analyticsTraceProjectionURL(for projectID: UUID, under appSupportRootDirectory: URL) -> URL {
        analyticsProjectionDirectory(for: projectID, under: appSupportRootDirectory)
            .appendingPathComponent("traces.json", isDirectory: false)
    }

    func analyticsAnomalyProjectionURL(for projectID: UUID, under appSupportRootDirectory: URL) -> URL {
        analyticsProjectionDirectory(for: projectID, under: appSupportRootDirectory)
            .appendingPathComponent("anomalies.json", isDirectory: false)
    }

    func analyticsLiveRunProjectionURL(for projectID: UUID, under appSupportRootDirectory: URL) -> URL {
        analyticsProjectionDirectory(for: projectID, under: appSupportRootDirectory)
            .appendingPathComponent("live-run.json", isDirectory: false)
    }

    func analyticsWorkflowHealthProjectionURL(for projectID: UUID, under appSupportRootDirectory: URL) -> URL {
        analyticsProjectionDirectory(for: projectID, under: appSupportRootDirectory)
            .appendingPathComponent("workflow-health.json", isDirectory: false)
    }

    func analyticsSessionProjectionURL(for projectID: UUID, under appSupportRootDirectory: URL) -> URL {
        analyticsProjectionDirectory(for: projectID, under: appSupportRootDirectory)
            .appendingPathComponent("sessions.json", isDirectory: false)
    }

    func analyticsNodeRuntimeProjectionURL(for projectID: UUID, under appSupportRootDirectory: URL) -> URL {
        analyticsProjectionDirectory(for: projectID, under: appSupportRootDirectory)
            .appendingPathComponent("nodes-runtime.json", isDirectory: false)
    }

    func analyticsThreadProjectionURL(for projectID: UUID, under appSupportRootDirectory: URL) -> URL {
        analyticsProjectionDirectory(for: projectID, under: appSupportRootDirectory)
            .appendingPathComponent("threads.json", isDirectory: false)
    }

    func analyticsCronProjectionURL(for projectID: UUID, under appSupportRootDirectory: URL) -> URL {
        analyticsProjectionDirectory(for: projectID, under: appSupportRootDirectory)
            .appendingPathComponent("cron.json", isDirectory: false)
    }

    func analyticsToolProjectionURL(for projectID: UUID, under appSupportRootDirectory: URL) -> URL {
        analyticsProjectionDirectory(for: projectID, under: appSupportRootDirectory)
            .appendingPathComponent("tools.json", isDirectory: false)
    }

    func validateProject(_ project: MAProject) throws {
        try validateNodeAgentBindings(workflows: project.workflows, knownAgentIDs: Set(project.agents.map(\.id)))
    }

    @discardableResult
    func synchronizeProject(
        _ project: MAProject,
        sourceProjectFileURL: URL?,
        under appSupportRootDirectory: URL
    ) throws -> ProjectStorageManifest {
        try validateProject(project)
        try ensureProjectScaffold(for: project.id, under: appSupportRootDirectory)

        let snapshotURL = currentSnapshotURL(for: project.id, under: appSupportRootDirectory)
        let manifestURL = manifestURL(for: project.id, under: appSupportRootDirectory)
        let existingManifest = try loadManifest(at: manifestURL)
        let now = Date()

        try encode(project, to: snapshotURL)
        try writeDesignState(for: project, under: appSupportRootDirectory)
        try writeCollaborationState(for: project, under: appSupportRootDirectory)
        try writeRuntimeState(for: project, under: appSupportRootDirectory)
        try writeTaskState(for: project, under: appSupportRootDirectory)
        try writeExecutionState(for: project, under: appSupportRootDirectory)
        try writeAnalyticsProjectionState(for: project, under: appSupportRootDirectory)
        try writeIndexes(for: project, under: appSupportRootDirectory)

        let manifest = ProjectStorageManifest(
            storageRevision: (existingManifest?.storageRevision ?? 0) + 1,
            projectID: project.id,
            projectName: project.name,
            fileVersion: project.fileVersion,
            sourceProjectFilePath: sourceProjectFileURL?.path ?? existingManifest?.sourceProjectFilePath,
            createdAt: existingManifest?.createdAt ?? project.createdAt,
            updatedAt: now,
            lastOpenedAt: now,
            lastSnapshotAt: now
        )
        try encode(manifest, to: manifestURL)
        return manifest
    }

    func loadManifest(for projectID: UUID, under appSupportRootDirectory: URL) throws -> ProjectStorageManifest? {
        try loadManifest(at: manifestURL(for: projectID, under: appSupportRootDirectory))
    }

    func loadSnapshot(for projectID: UUID, under appSupportRootDirectory: URL) throws -> MAProject? {
        try loadSnapshot(at: currentSnapshotURL(for: projectID, under: appSupportRootDirectory))
    }

    func loadAssembledProject(for projectID: UUID, under appSupportRootDirectory: URL) throws -> MAProject? {
        let snapshot = try loadSnapshot(for: projectID, under: appSupportRootDirectory)
        let designRootURL = managedProjectRootDirectory(for: projectID, under: appSupportRootDirectory)
            .appendingPathComponent("design", isDirectory: true)
        let projectDocumentURL = designRootURL.appendingPathComponent("project.json", isDirectory: false)

        guard fileManager.fileExists(atPath: projectDocumentURL.path) else {
            return snapshot
        }

        let projectDocument = try decode(ProjectDesignDocument.self, from: projectDocumentURL)
        let workflowsRootURL = designRootURL.appendingPathComponent("workflows", isDirectory: true)
        var designAgentsByID: [UUID: Agent] = [:]
        let workflows = try projectDocument.workflowIDs.map {
            try assembleWorkflowDesignState(workflowID: $0, under: workflowsRootURL, designAgentsByID: &designAgentsByID)
        }

        let knownAgentIDs = Set(snapshot?.agents.map(\.id) ?? []).union(designAgentsByID.keys)
        try validateNodeAgentBindings(workflows: workflows, knownAgentIDs: knownAgentIDs)

        var project: MAProject
        if let snapshot {
            project = snapshot
        } else {
            project = try makeEmptyProject(from: projectDocument)
        }
        project.fileVersion = projectDocument.fileVersion
        project.name = projectDocument.projectName
        project.workflows = workflows
        project.agents = mergeAgents(
            baseAgents: snapshot?.agents ?? [],
            designAgentsByID: designAgentsByID,
            workflowOrder: workflows
        )
        project.createdAt = projectDocument.createdAt
        project.updatedAt = projectDocument.updatedAt
        return project
    }

    func removeManagedProjectRoot(for projectID: UUID, under appSupportRootDirectory: URL) {
        let rootURL = managedProjectRootDirectory(for: projectID, under: appSupportRootDirectory)
        guard fileManager.fileExists(atPath: rootURL.path) else { return }
        try? fileManager.removeItem(at: rootURL)
    }

    func ensureBaseDirectories(under appSupportRootDirectory: URL) throws {
        try fileManager.createDirectory(
            at: managedProjectsRootDirectory(under: appSupportRootDirectory),
            withIntermediateDirectories: true
        )
    }

    private func ensureProjectScaffold(for projectID: UUID, under appSupportRootDirectory: URL) throws {
        let rootURL = managedProjectRootDirectory(for: projectID, under: appSupportRootDirectory)
        let directories = [
            rootURL,
            rootURL.appendingPathComponent("snapshot", isDirectory: true),
            rootURL.appendingPathComponent("design", isDirectory: true),
            rootURL.appendingPathComponent("design/workflows", isDirectory: true),
            rootURL.appendingPathComponent("collaboration", isDirectory: true),
            rootURL.appendingPathComponent("collaboration/workbench", isDirectory: true),
            rootURL.appendingPathComponent("collaboration/workbench/threads", isDirectory: true),
            rootURL.appendingPathComponent("collaboration/communications", isDirectory: true),
            rootURL.appendingPathComponent("runtime", isDirectory: true),
            rootURL.appendingPathComponent("runtime/sessions", isDirectory: true),
            rootURL.appendingPathComponent("runtime/state", isDirectory: true),
            rootURL.appendingPathComponent("tasks", isDirectory: true),
            rootURL.appendingPathComponent("tasks/workspaces", isDirectory: true),
            rootURL.appendingPathComponent("execution", isDirectory: true),
            rootURL.appendingPathComponent("openclaw", isDirectory: true),
            rootURL.appendingPathComponent("openclaw/session", isDirectory: true),
            rootURL.appendingPathComponent("openclaw/session/backup", isDirectory: true),
            rootURL.appendingPathComponent("openclaw/session/mirror", isDirectory: true),
            rootURL.appendingPathComponent("openclaw/session/agents", isDirectory: true),
            rootURL.appendingPathComponent("analytics", isDirectory: true),
            rootURL.appendingPathComponent("analytics/projections", isDirectory: true),
            rootURL.appendingPathComponent("indexes", isDirectory: true),
        ]

        for directory in directories {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    private func writeTaskState(for project: MAProject, under appSupportRootDirectory: URL) throws {
        let tasksRootURL = tasksRootDirectory(for: project.id, under: appSupportRootDirectory)
        let workspacesRootURL = taskWorkspaceRootDirectory(for: project.id, under: appSupportRootDirectory)
        try fileManager.createDirectory(at: tasksRootURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: workspacesRootURL, withIntermediateDirectories: true)

        let tasks = project.tasks.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        let workspaceIndex = project.workspaceIndex.sorted { lhs, rhs in
            if lhs.workspaceName != rhs.workspaceName {
                return lhs.workspaceName.localizedCaseInsensitiveCompare(rhs.workspaceName) == .orderedAscending
            }
            return lhs.taskID.uuidString < rhs.taskID.uuidString
        }

        try encode(tasks, to: tasksListURL(for: project.id, under: appSupportRootDirectory))
        try encode(workspaceIndex, to: workspaceIndexURL(for: project.id, under: appSupportRootDirectory))
    }

    private func writeAnalyticsProjectionState(for project: MAProject, under appSupportRootDirectory: URL) throws {
        let projectionRootURL = analyticsProjectionDirectory(for: project.id, under: appSupportRootDirectory)
        try fileManager.createDirectory(at: projectionRootURL, withIntermediateDirectories: true)
        let generatedAt = Date()

        let workflowCount = project.workflows.count
        let nodeCount = project.workflows.reduce(0) { $0 + $1.nodes.count }
        let warningLogCount = project.executionLogs.filter { $0.level == .warning }.count
        let errorLogCount = project.executionLogs.filter { $0.level == .error }.count
        let pendingApprovalCount = project.messages.filter { $0.status == .waitingForApproval }.count
        let completedExecutionCount = project.executionResults.filter { $0.status == .completed }.count
        let failedExecutionCount = project.executionResults.filter { $0.status == .failed }.count

        try encode(
            AnalyticsOverviewProjectionDocument(
                projectID: project.id,
                generatedAt: generatedAt,
                workflowCount: workflowCount,
                nodeCount: nodeCount,
                agentCount: project.agents.count,
                taskCount: project.tasks.count,
                messageCount: project.messages.count,
                executionResultCount: project.executionResults.count,
                completedExecutionCount: completedExecutionCount,
                failedExecutionCount: failedExecutionCount,
                warningLogCount: warningLogCount,
                errorLogCount: errorLogCount,
                pendingApprovalCount: pendingApprovalCount
            ),
            to: analyticsOverviewProjectionURL(for: project.id, under: appSupportRootDirectory)
        )

        let traces = project.executionResults
            .sorted { lhs, rhs in
                let lhsDate = lhs.completedAt ?? lhs.startedAt
                let rhsDate = rhs.completedAt ?? rhs.startedAt
                if lhsDate != rhsDate {
                    return lhsDate > rhsDate
                }
                return lhs.id.uuidString > rhs.id.uuidString
            }
            .map { result in
                AnalyticsTraceProjectionEntry(
                    executionID: result.id,
                    nodeID: result.nodeID,
                    agentID: result.agentID,
                    sessionID: result.sessionID,
                    status: result.status,
                    outputType: result.outputType,
                    startedAt: result.startedAt,
                    completedAt: result.completedAt,
                    duration: result.duration,
                    protocolRepairCount: result.protocolRepairCount,
                    previewText: truncatedText(result.output)
                )
            }
        try encode(
            AnalyticsTraceProjectionDocument(
                projectID: project.id,
                generatedAt: generatedAt,
                traces: traces
            ),
            to: analyticsTraceProjectionURL(for: project.id, under: appSupportRootDirectory)
        )

        let executionAnomalies = project.executionResults
            .filter { $0.status == .failed }
            .map { result in
                AnalyticsAnomalyProjectionEntry(
                    id: result.id.uuidString,
                    source: "execution",
                    severity: "error",
                    message: truncatedText(result.output, limit: 160),
                    nodeID: result.nodeID,
                    agentID: result.agentID,
                    sessionID: result.sessionID,
                    timestamp: result.completedAt ?? result.startedAt
                )
            }

        let logAnomalies = project.executionLogs
            .filter { $0.level == .warning || $0.level == .error }
            .map { entry in
                AnalyticsAnomalyProjectionEntry(
                    id: entry.id.uuidString,
                    source: "log",
                    severity: entry.level == .error ? "error" : "warning",
                    message: truncatedText(entry.message, limit: 160),
                    nodeID: entry.nodeID,
                    agentID: nil,
                    sessionID: nil,
                    timestamp: entry.timestamp
                )
            }
            .sorted { lhs, rhs in
                if lhs.timestamp != rhs.timestamp {
                    return lhs.timestamp > rhs.timestamp
                }
                return lhs.id > rhs.id
            }

        try encode(
            AnalyticsAnomalyProjectionDocument(
                projectID: project.id,
                generatedAt: generatedAt,
                anomalies: executionAnomalies + logAnomalies
            ),
            to: analyticsAnomalyProjectionURL(for: project.id, under: appSupportRootDirectory)
        )

        let sessionEntries = makeAnalyticsSessionProjectionEntries(for: project)
        let nodeRuntimeEntries = makeAnalyticsNodeRuntimeProjectionEntries(for: project)
        let threadEntries = makeAnalyticsThreadProjectionEntries(for: project)
        let workflowHealthEntries = makeAnalyticsWorkflowHealthProjectionEntries(
            for: project,
            nodeEntries: nodeRuntimeEntries,
            sessionEntries: sessionEntries
        )
        let liveRunDocument = makeAnalyticsLiveRunProjectionDocument(
            for: project,
            sessionEntries: sessionEntries,
            workflowHealthEntries: workflowHealthEntries,
            generatedAt: generatedAt
        )

        try encode(
            liveRunDocument,
            to: analyticsLiveRunProjectionURL(for: project.id, under: appSupportRootDirectory)
        )
        try encode(
            AnalyticsSessionProjectionDocument(
                projectID: project.id,
                generatedAt: generatedAt,
                sessions: sessionEntries
            ),
            to: analyticsSessionProjectionURL(for: project.id, under: appSupportRootDirectory)
        )
        try encode(
            AnalyticsNodeRuntimeProjectionDocument(
                projectID: project.id,
                generatedAt: generatedAt,
                nodes: nodeRuntimeEntries
            ),
            to: analyticsNodeRuntimeProjectionURL(for: project.id, under: appSupportRootDirectory)
        )
        try encode(
            AnalyticsThreadProjectionDocument(
                projectID: project.id,
                generatedAt: generatedAt,
                threads: threadEntries
            ),
            to: analyticsThreadProjectionURL(for: project.id, under: appSupportRootDirectory)
        )
        try encode(
            AnalyticsWorkflowHealthProjectionDocument(
                projectID: project.id,
                generatedAt: generatedAt,
                workflows: workflowHealthEntries
            ),
            to: analyticsWorkflowHealthProjectionURL(for: project.id, under: appSupportRootDirectory)
        )
    }

    private func encode<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)
    }

    private func encodeCompact<T: Encodable>(_ value: T) throws -> Data {
        try JSONEncoder().encode(value)
    }

    private func writeNDJSON<T: Encodable>(_ values: [T], to url: URL) throws {
        let lines = try values.map { try encodeCompact($0) }
        let data: Data
        if lines.isEmpty {
            data = Data()
        } else {
            let joined = lines.enumerated().reduce(into: Data()) { partial, item in
                partial.append(item.element)
                partial.append(0x0A)
            }
            data = joined
        }
        try data.write(to: url, options: .atomic)
    }

    private func decode<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(type, from: data)
    }

    private func loadManifest(at url: URL) throws -> ProjectStorageManifest? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try decode(ProjectStorageManifest.self, from: url)
    }

    private func loadSnapshot(at url: URL) throws -> MAProject? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try decode(MAProject.self, from: url)
    }

    private func writeDesignState(for project: MAProject, under appSupportRootDirectory: URL) throws {
        let designRootURL = managedProjectRootDirectory(for: project.id, under: appSupportRootDirectory)
            .appendingPathComponent("design", isDirectory: true)
        let workflowsRootURL = designRootURL.appendingPathComponent("workflows", isDirectory: true)
        let sortedWorkflowIDs = project.workflows.map(\.id)

        let projectDocument = ProjectDesignDocument(
            projectID: project.id,
            projectName: project.name,
            fileVersion: project.fileVersion,
            workflowIDs: sortedWorkflowIDs,
            createdAt: project.createdAt,
            updatedAt: project.updatedAt
        )
        try encode(projectDocument, to: designRootURL.appendingPathComponent("project.json", isDirectory: false))

        let validWorkflowNames = Set(sortedWorkflowIDs.map(\.uuidString))
        try removeUnexpectedEntries(in: workflowsRootURL, keeping: validWorkflowNames)

        let agentsByID = Dictionary(uniqueKeysWithValues: project.agents.map { ($0.id, $0) })
        for workflow in project.workflows {
            try writeWorkflowDesignState(workflow, agentsByID: agentsByID, under: workflowsRootURL)
        }
    }

    private func writeCollaborationState(for project: MAProject, under appSupportRootDirectory: URL) throws {
        let projectRootURL = managedProjectRootDirectory(for: project.id, under: appSupportRootDirectory)
        let collaborationRootURL = projectRootURL.appendingPathComponent("collaboration", isDirectory: true)
        let threadsRootURL = collaborationRootURL
            .appendingPathComponent("workbench", isDirectory: true)
            .appendingPathComponent("threads", isDirectory: true)
        let communicationsRootURL = collaborationRootURL.appendingPathComponent("communications", isDirectory: true)

        try fileManager.createDirectory(at: threadsRootURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: communicationsRootURL, withIntermediateDirectories: true)

        let messages = project.messages.sorted { lhs, rhs in
            if lhs.timestamp != rhs.timestamp {
                return lhs.timestamp < rhs.timestamp
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        try writeNDJSON(messages, to: communicationsRootURL.appendingPathComponent("messages.ndjson", isDirectory: false))

        let approvalMessages = messages.filter { message in
            message.requiresApproval
                || message.status == .waitingForApproval
                || message.status == .approved
                || message.status == .rejected
                || message.approvedBy != nil
                || message.approvalTimestamp != nil
        }
        try writeNDJSON(
            approvalMessages,
            to: communicationsRootURL.appendingPathComponent("approvals.ndjson", isDirectory: false)
        )

        let workflowsByID = Dictionary(uniqueKeysWithValues: project.workflows.map { ($0.id, $0) })
        let agentsByID = Dictionary(uniqueKeysWithValues: project.agents.map { ($0.id, $0) })
        let allRuntimeDispatchEnvelopes = runtimeDispatchEnvelopes(from: project.runtimeState)
        let workbenchMessages = messages.filter { $0.metadata["channel"] == "workbench" }
        let workbenchTasks = project.tasks.filter { $0.metadata["source"] == "workbench" }
        let workbenchThreadLinks = buildWorkbenchThreadLinks(
            messages: workbenchMessages,
            tasks: workbenchTasks,
            agentsByID: agentsByID
        )

        let sessionIDs = Set(workbenchMessages.compactMap { workbenchSessionID(from: $0.metadata) })
            .union(workbenchTasks.compactMap { workbenchSessionID(from: $0.metadata) })
            .sorted()
        let validThreadDirectoryNames = Set(sessionIDs.map(safeStorageName(for:)))
        try removeUnexpectedEntries(in: threadsRootURL, keeping: validThreadDirectoryNames)

        for sessionID in sessionIDs {
            let threadDirectoryName = safeStorageName(for: sessionID)
            let threadRootURL = threadsRootURL.appendingPathComponent(threadDirectoryName, isDirectory: true)
            let attachmentsURL = threadRootURL.appendingPathComponent("attachments", isDirectory: true)
            try fileManager.createDirectory(at: attachmentsURL, withIntermediateDirectories: true)

            let threadMessages = workbenchMessages.filter { workbenchSessionID(from: $0.metadata) == sessionID }
            let threadTasks = workbenchTasks.filter { workbenchSessionID(from: $0.metadata) == sessionID }
            let resolvedWorkflowID = threadMessages.compactMap { workflowIDFromMetadata($0.metadata) }.first
                ?? threadTasks.compactMap { workflowIDFromMetadata($0.metadata) }.first
            let workflowName = resolvedWorkflowID.flatMap { workflowsByID[$0]?.name }
            let resolvedEntryAgentID = threadMessages.compactMap { entryAgentIDFromMetadata($0.metadata) }.first
                ?? threadTasks.compactMap(\.assignedAgentID).first
            let entryAgentName = resolvedEntryAgentID.flatMap { agentsByID[$0]?.name }

            let startedAt = (threadMessages.map(\.timestamp) + threadTasks.map(\.createdAt)).min() ?? project.createdAt
            let lastUpdatedAt = (threadMessages.map(\.timestamp)
                + threadTasks.map { $0.completedAt ?? $0.startedAt ?? $0.createdAt }).max() ?? project.updatedAt
            let pendingApprovalCount = threadMessages.filter { $0.status == .waitingForApproval }.count
            let threadStatus = workbenchThreadStatus(messages: threadMessages, tasks: threadTasks)
            let linkedGatewaySessionIDs = workbenchThreadLinks[sessionID]
                .flatMap { link in
                    link.gatewaySessionKey.map { [$0] } ?? []
                } ?? []
            let linkedSessionIDs = Set([sessionID] + linkedGatewaySessionIDs).sorted()
            let semantics = resolveWorkbenchThreadSemantics(
                messages: threadMessages,
                tasks: threadTasks
            )

            let threadDocument = WorkbenchThreadDocument(
                threadID: sessionID,
                threadType: semantics.type.rawValue,
                mode: semantics.mode.rawValue,
                sessionID: sessionID,
                linkedSessionIDs: linkedSessionIDs,
                workflowID: resolvedWorkflowID,
                workflowName: workflowName,
                entryAgentID: resolvedEntryAgentID,
                entryAgentName: entryAgentName,
                status: threadStatus,
                startedAt: startedAt,
                lastUpdatedAt: lastUpdatedAt,
                messageCount: threadMessages.count,
                taskCount: threadTasks.count,
                pendingApprovalCount: pendingApprovalCount,
                latestMessageID: threadMessages.last?.id,
                latestTaskID: threadTasks.max(by: { $0.createdAt < $1.createdAt })?.id
            )
            try encode(threadDocument, to: threadRootURL.appendingPathComponent("thread.json", isDirectory: false))

            let participantAgentIDs = Set(
                threadMessages.flatMap { [$0.fromAgentID, $0.toAgentID] }
                    + threadTasks.compactMap(\.assignedAgentID)
            )
            let contextDocument = WorkbenchThreadContextDocument(
                threadID: sessionID,
                sessionID: sessionID,
                workflowID: resolvedWorkflowID,
                workflowName: workflowName,
                taskIDs: threadTasks.map(\.id),
                messageIDs: threadMessages.map(\.id),
                participantAgentIDs: participantAgentIDs.sorted { $0.uuidString < $1.uuidString },
                entryAgentID: resolvedEntryAgentID,
                entryAgentName: entryAgentName
            )
            try encode(contextDocument, to: threadRootURL.appendingPathComponent("context.json", isDirectory: false))

            let runtimeDispatchEnvelopes = allRuntimeDispatchEnvelopes
                .filter { normalizedSessionID($0.record.sessionKey) == sessionID }
                .filter { envelope in
                    guard let resolvedWorkflowID else { return true }
                    return envelope.record.workflowID == nil || envelope.record.workflowID == resolvedWorkflowID.uuidString
                }
            let runtimeDispatches = runtimeDispatchEnvelopes
                .map(\.record)
            let runtimeEvents = project.runtimeState.runtimeEvents
                .filter { normalizedSessionID($0.sessionKey) == sessionID }
                .filter { event in
                    guard let resolvedWorkflowID else { return true }
                    return event.workflowId == nil || event.workflowId == resolvedWorkflowID.uuidString
                }
            let workflowNodeIDs = Set(workflowsByID[resolvedWorkflowID ?? UUID()]?.nodes.map(\.id) ?? [])
            let runtimeReceipts = project.executionResults
                .filter { normalizedSessionID($0.sessionID) == sessionID }
                .filter { receipt in
                    workflowNodeIDs.isEmpty || workflowNodeIDs.contains(receipt.nodeID)
                }
            let relatedNodeIDs = Set(
                threadTasks.compactMap(\.workflowNodeID)
                    + runtimeDispatches.compactMap { record in
                        guard let rawNodeID = record.nodeID else { return nil }
                        return UUID(uuidString: rawNodeID.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                    + runtimeEvents.compactMap { event in
                        guard let rawNodeID = event.nodeId else { return nil }
                        return UUID(uuidString: rawNodeID.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                    + runtimeReceipts.map(\.nodeID)
            )
            let investigationDocument = WorkbenchThreadInvestigationDocument(
                threadID: sessionID,
                sessionID: sessionID,
                workflowID: resolvedWorkflowID,
                workflowName: workflowName,
                entryAgentID: resolvedEntryAgentID,
                entryAgentName: entryAgentName,
                participantAgentIDs: participantAgentIDs.sorted { $0.uuidString < $1.uuidString },
                relatedNodeIDs: relatedNodeIDs.sorted { $0.uuidString < $1.uuidString },
                status: threadStatus,
                startedAt: startedAt,
                lastUpdatedAt: lastUpdatedAt,
                messageCount: threadMessages.count,
                taskCount: threadTasks.count,
                pendingApprovalCount: pendingApprovalCount,
                dispatchCount: runtimeDispatches.count,
                eventCount: runtimeEvents.count,
                receiptCount: runtimeReceipts.count,
                latestMessageID: threadMessages.last?.id,
                latestTaskID: threadTasks.max(by: { $0.createdAt < $1.createdAt })?.id
            )
            try encode(
                investigationDocument,
                to: threadRootURL.appendingPathComponent("investigation.json", isDirectory: false)
            )
            try writeNDJSON(threadMessages, to: threadRootURL.appendingPathComponent("dialog.ndjson", isDirectory: false))
            try writeNDJSON(
                makeWorkbenchTurnAuditDocuments(
                    threadID: sessionID,
                    sessionID: sessionID,
                    workflowID: resolvedWorkflowID,
                    messages: threadMessages,
                    agentsByID: agentsByID
                ),
                to: threadRootURL.appendingPathComponent("turns.ndjson", isDirectory: false)
            )
            try writeNDJSON(
                makeWorkbenchDelegationAuditDocuments(
                    threadID: sessionID,
                    sessionID: sessionID,
                    dispatches: runtimeDispatchEnvelopes,
                    events: runtimeEvents
                ),
                to: threadRootURL.appendingPathComponent("delegation.ndjson", isDirectory: false)
            )
        }
    }

    private func writeRuntimeState(for project: MAProject, under appSupportRootDirectory: URL) throws {
        let projectRootURL = managedProjectRootDirectory(for: project.id, under: appSupportRootDirectory)
        let runtimeRootURL = projectRootURL.appendingPathComponent("runtime", isDirectory: true)
        let sessionsRootURL = runtimeRootURL.appendingPathComponent("sessions", isDirectory: true)
        let runtimeStateRootURL = runtimeRootURL.appendingPathComponent("state", isDirectory: true)

        try fileManager.createDirectory(at: sessionsRootURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: runtimeStateRootURL, withIntermediateDirectories: true)

        try encode(
            project.runtimeState,
            to: runtimeStateRootURL.appendingPathComponent("runtime-state.json", isDirectory: false)
        )
        try encode(
            RuntimeQueueStateDocument(
                generatedAt: Date(),
                messageQueue: project.runtimeState.messageQueue,
                queuedDispatches: project.runtimeState.dispatchQueue,
                inflightDispatches: project.runtimeState.inflightDispatches,
                completedDispatches: project.runtimeState.completedDispatches,
                failedDispatches: project.runtimeState.failedDispatches
            ),
            to: runtimeStateRootURL.appendingPathComponent("queue.json", isDirectory: false)
        )

        let agentsByID = Dictionary(uniqueKeysWithValues: project.agents.map { ($0.id, $0) })
        let allDispatches = runtimeDispatchEnvelopes(from: project.runtimeState)
        let workbenchThreadLinks = buildWorkbenchThreadLinks(
            messages: project.messages.filter { $0.metadata["channel"] == "workbench" },
            tasks: project.tasks.filter { $0.metadata["source"] == "workbench" },
            agentsByID: agentsByID
        )
        let sessionIDs = Set([project.runtimeState.sessionID])
            .union(project.messages.compactMap { workbenchSessionID(from: $0.metadata) })
            .union(project.tasks.compactMap { workbenchSessionID(from: $0.metadata) })
            .union(allDispatches.compactMap { normalizedSessionID($0.record.sessionKey) })
            .union(project.runtimeState.runtimeEvents.compactMap { normalizedSessionID($0.sessionKey) })
            .union(project.executionResults.compactMap { normalizedSessionID($0.sessionID) })
            .sorted()

        let validSessionDirectoryNames = Set(sessionIDs.map(safeStorageName(for:)))
        try removeUnexpectedEntries(in: sessionsRootURL, keeping: validSessionDirectoryNames)

        for sessionID in sessionIDs {
            let storageDirectoryName = safeStorageName(for: sessionID)
            let sessionRootURL = sessionsRootURL.appendingPathComponent(storageDirectoryName, isDirectory: true)
            let artifactsURL = sessionRootURL.appendingPathComponent("artifacts", isDirectory: true)
            try fileManager.createDirectory(at: artifactsURL, withIntermediateDirectories: true)

            let sessionDispatches = allDispatches.filter { normalizedSessionID($0.record.sessionKey) == sessionID }
            let sessionEvents = project.runtimeState.runtimeEvents.filter { normalizedSessionID($0.sessionKey) == sessionID }
            let sessionReceipts = project.executionResults.filter { normalizedSessionID($0.sessionID) == sessionID }
            let sessionMessages = project.messages.filter { workbenchSessionID(from: $0.metadata) == sessionID }
            let sessionTasks = project.tasks.filter { workbenchSessionID(from: $0.metadata) == sessionID }

            let classification = classifyRuntimeSession(
                sessionID: sessionID,
                project: project,
                sessionMessages: sessionMessages,
                sessionTasks: sessionTasks,
                sessionDispatches: sessionDispatches,
                sessionEvents: sessionEvents,
                sessionReceipts: sessionReceipts,
                workbenchThreadLinks: workbenchThreadLinks
            )

            let workflowIDs = Set(
                sessionDispatches.compactMap(\.record.workflowID)
                    + sessionEvents.compactMap(\.workflowId)
                    + sessionMessages.compactMap { workflowIDFromMetadata($0.metadata)?.uuidString }
                    + sessionTasks.compactMap { workflowIDFromMetadata($0.metadata)?.uuidString }
            )
            .sorted()
            let actualTransportKinds = Array(
                Set(
                    sessionDispatches.map { $0.record.transportKind.rawValue }
                        + sessionEvents.map { $0.transport.kind.rawValue }
                        + sessionReceipts.compactMap(\.transportKind)
                )
            ).sorted()
            let latestFailureText = (
                sessionDispatches.compactMap(\.record.errorMessage)
                + sessionReceipts
                    .filter { $0.status == .failed }
                    .map { truncatedText($0.summaryText, limit: 160) }
            )
            .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            let transportPlan = makeRuntimeTransportPlan(
                sessionID: sessionID,
                classification: classification,
                project: project,
                actualTransportKinds: actualTransportKinds,
                degradationReason: latestFailureText
            )

            let sessionDocument = RuntimeSessionDocument(
                sessionID: sessionID,
                sessionType: classification.sessionType.rawValue,
                threadID: classification.threadID,
                storageDirectoryName: storageDirectoryName,
                generatedAt: Date(),
                workflowID: classification.workflowID,
                entryAgentID: classification.entryAgentID,
                entryAgentName: classification.entryAgentName,
                workflowIDs: workflowIDs,
                plannedTransport: transportPlan.preferredTransport,
                actualTransport: transportPlan.actualTransport,
                actualTransportKinds: transportPlan.actualTransportKinds,
                fallbackReason: transportPlan.fallbackReason,
                degradationReason: transportPlan.degradationReason,
                eventCount: sessionEvents.count,
                dispatchCount: sessionDispatches.count,
                receiptCount: sessionReceipts.count,
                queuedDispatchCount: sessionDispatches.filter { $0.stateBucket == "queued" }.count,
                inflightDispatchCount: sessionDispatches.filter { $0.stateBucket == "inflight" }.count,
                completedDispatchCount: sessionDispatches.filter { $0.stateBucket == "completed" }.count,
                failedDispatchCount: sessionDispatches.filter { $0.stateBucket == "failed" }.count,
                latestEventAt: sessionEvents.map(\.timestamp).max(),
                latestReceiptAt: sessionReceipts.compactMap { $0.completedAt ?? $0.startedAt }.max(),
                lastUpdatedAt: (
                    sessionEvents.map(\.timestamp)
                    + sessionReceipts.compactMap { $0.completedAt ?? $0.startedAt }
                    + sessionDispatches.map(\.record.updatedAt)
                ).max(),
                isProjectRuntimeSession: project.runtimeState.sessionID == sessionID
            )
            try encode(sessionDocument, to: sessionRootURL.appendingPathComponent("session.json", isDirectory: false))
            try encode(
                transportPlan,
                to: sessionRootURL.appendingPathComponent("transport-plan.json", isDirectory: false)
            )
            try writeNDJSON(
                sessionDispatches,
                to: sessionRootURL.appendingPathComponent("dispatches.ndjson", isDirectory: false)
            )
            try writeNDJSON(
                sessionEvents,
                to: sessionRootURL.appendingPathComponent("events.ndjson", isDirectory: false)
            )
            try writeNDJSON(
                sessionReceipts,
                to: sessionRootURL.appendingPathComponent("receipts.ndjson", isDirectory: false)
            )
            try writeNDJSON(
                makeRuntimeSessionSpanAuditDocuments(
                    sessionID: sessionID,
                    threadID: classification.threadID,
                    workflowID: classification.workflowID,
                    receipts: sessionReceipts,
                    agentsByID: agentsByID
                ),
                to: sessionRootURL.appendingPathComponent("spans.ndjson", isDirectory: false)
            )
        }
    }

    private func writeExecutionState(for project: MAProject, under appSupportRootDirectory: URL) throws {
        let executionRootURL = managedProjectRootDirectory(for: project.id, under: appSupportRootDirectory)
            .appendingPathComponent("execution", isDirectory: true)
        try fileManager.createDirectory(at: executionRootURL, withIntermediateDirectories: true)

        let results = project.executionResults.sorted { lhs, rhs in
            if lhs.startedAt != rhs.startedAt {
                return lhs.startedAt < rhs.startedAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        let logs = project.executionLogs.sorted { lhs, rhs in
            if lhs.timestamp != rhs.timestamp {
                return lhs.timestamp < rhs.timestamp
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }

        try writeNDJSON(results, to: executionRootURL.appendingPathComponent("results.ndjson", isDirectory: false))
        try writeNDJSON(logs, to: executionRootURL.appendingPathComponent("logs.ndjson", isDirectory: false))
    }

    private func writeIndexes(for project: MAProject, under appSupportRootDirectory: URL) throws {
        let indexesRootURL = managedProjectRootDirectory(for: project.id, under: appSupportRootDirectory)
            .appendingPathComponent("indexes", isDirectory: true)
        try fileManager.createDirectory(at: indexesRootURL, withIntermediateDirectories: true)

        let workflowIndex = project.workflows.map { workflow in
            WorkflowIndexEntryDocument(
                workflowID: workflow.id,
                name: workflow.name,
                parentNodeID: workflow.parentNodeID,
                nodeCount: workflow.nodes.count,
                edgeCount: workflow.edges.count,
                boundaryCount: workflow.boundaries.count,
                createdAt: workflow.createdAt
            )
        }
        try encode(workflowIndex, to: indexesRootURL.appendingPathComponent("workflows.json", isDirectory: false))

        let nodeIndex = project.workflows.flatMap { workflow in
            workflow.nodes.map { node in
                NodeIndexEntryDocument(
                    workflowID: workflow.id,
                    nodeID: node.id,
                    agentID: node.agentID,
                    type: node.type,
                    title: node.title,
                    position: node.position,
                    boundaryID: workflow.boundary(containing: node.position)?.id
                )
            }
        }
        try encode(nodeIndex, to: indexesRootURL.appendingPathComponent("nodes.json", isDirectory: false))

        let threads = makeThreadIndexEntries(for: project)
        try encode(threads, to: indexesRootURL.appendingPathComponent("threads.json", isDirectory: false))

        let sessions = makeRuntimeSessionIndexEntries(for: project)
        try encode(sessions, to: indexesRootURL.appendingPathComponent("sessions.json", isDirectory: false))
    }

    private func writeWorkflowDesignState(
        _ workflow: Workflow,
        agentsByID: [UUID: Agent],
        under workflowsRootURL: URL
    ) throws {
        let workflowRootURL = workflowsRootURL.appendingPathComponent(workflow.id.uuidString, isDirectory: true)
        let nodesRootURL = workflowRootURL.appendingPathComponent("nodes", isDirectory: true)
        let edgesRootURL = workflowRootURL.appendingPathComponent("edges", isDirectory: true)
        let boundariesRootURL = workflowRootURL.appendingPathComponent("boundaries", isDirectory: true)
        let derivedRootURL = workflowRootURL.appendingPathComponent("derived", isDirectory: true)

        for directory in [workflowRootURL, nodesRootURL, edgesRootURL, boundariesRootURL, derivedRootURL] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        let workflowDocument = WorkflowDesignDocument(
            id: workflow.id,
            name: workflow.name,
            fallbackRoutingPolicy: workflow.fallbackRoutingPolicy,
            launchTestCases: workflow.launchTestCases,
            lastLaunchVerificationReport: workflow.lastLaunchVerificationReport,
            colorGroups: workflow.colorGroups,
            createdAt: workflow.createdAt,
            parentNodeID: workflow.parentNodeID,
            inputSchema: workflow.inputSchema,
            outputSchema: workflow.outputSchema,
            nodeIDs: workflow.nodes.map(\.id),
            edgeIDs: workflow.edges.map(\.id),
            boundaryIDs: workflow.boundaries.map(\.id)
        )
        try encode(workflowDocument, to: workflowRootURL.appendingPathComponent("workflow.json", isDirectory: false))

        try removeUnexpectedEntries(in: nodesRootURL, keeping: Set(workflow.nodes.map { $0.id.uuidString }))
        try removeUnexpectedEntries(
            in: edgesRootURL,
            keeping: Set(workflow.edges.map { "\($0.id.uuidString).json" })
        )
        try removeUnexpectedEntries(
            in: boundariesRootURL,
            keeping: Set(workflow.boundaries.map { "\($0.id.uuidString).json" })
        )
        try removeUnexpectedEntries(in: derivedRootURL, keeping: Self.derivedDocumentNames)

        for node in workflow.nodes {
            try writeNodeDesignState(
                node,
                workflowID: workflow.id,
                agent: try resolveBoundAgent(for: node, agentsByID: agentsByID),
                under: nodesRootURL
            )
        }

        for edge in workflow.edges {
            try encode(edge, to: edgesRootURL.appendingPathComponent("\(edge.id.uuidString).json", isDirectory: false))
        }

        for boundary in workflow.boundaries {
            try encode(
                boundary,
                to: boundariesRootURL.appendingPathComponent("\(boundary.id.uuidString).json", isDirectory: false)
            )
        }

        try writeDerivedWorkflowState(for: workflow, under: derivedRootURL)
    }

    private func resolveBoundAgent(for node: WorkflowNode, agentsByID: [UUID: Agent]) throws -> Agent? {
        guard let agentID = node.agentID else { return nil }
        guard let agent = agentsByID[agentID] else {
            throw ProjectFileSystemError.missingAgentDefinition(nodeID: node.id, agentID: agentID)
        }
        return agent
    }

    private func writeNodeDesignState(
        _ node: WorkflowNode,
        workflowID: UUID,
        agent: Agent?,
        under nodesRootURL: URL
    ) throws {
        let nodeRootURL = nodesRootURL.appendingPathComponent(node.id.uuidString, isDirectory: true)
        let openClawRootURL = nodeRootURL.appendingPathComponent("openclaw", isDirectory: true)
        let workspaceRootURL = openClawRootURL.appendingPathComponent("workspace", isDirectory: true)
        let mirrorRootURL = openClawRootURL.appendingPathComponent("mirror", isDirectory: true)
        let stateRootURL = openClawRootURL.appendingPathComponent("state", isDirectory: true)

        for directory in [nodeRootURL, openClawRootURL, workspaceRootURL, mirrorRootURL, stateRootURL] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        let nodeDocument = NodeDesignDocument(
            id: node.id,
            workflowID: workflowID,
            agentID: node.agentID,
            type: node.type,
            position: node.position,
            title: node.title,
            displayColorHex: node.displayColorHex,
            conditionExpression: node.conditionExpression,
            loopEnabled: node.loopEnabled,
            maxIterations: node.maxIterations,
            subflowID: node.subflowID,
            nestingLevel: node.nestingLevel,
            inputParameters: node.inputParameters,
            outputParameters: node.outputParameters
        )
        try encode(nodeDocument, to: nodeRootURL.appendingPathComponent("node.json", isDirectory: false))

        guard let agent else {
            try? fileManager.removeItem(at: nodeRootURL.appendingPathComponent("agent.json", isDirectory: false))
            try? fileManager.removeItem(at: openClawRootURL)
            return
        }

        let agentDocument = NodeAgentDesignDocument(
            id: agent.id,
            nodeID: node.id,
            name: agent.name,
            identity: agent.identity,
            description: agent.description,
            capabilities: agent.capabilities,
            colorHex: agent.colorHex,
            createdAt: agent.createdAt,
            updatedAt: agent.updatedAt,
            openClawDefinition: agent.openClawDefinition
        )
        try encode(agentDocument, to: nodeRootURL.appendingPathComponent("agent.json", isDirectory: false))

        let bindingDocument = NodeOpenClawBindingDocument(
            nodeID: node.id,
            agentID: agent.id,
            agentIdentifier: agent.openClawDefinition.agentIdentifier,
            modelIdentifier: agent.openClawDefinition.modelIdentifier,
            runtimeProfile: agent.openClawDefinition.runtimeProfile,
            memoryBackupPath: agent.openClawDefinition.memoryBackupPath,
            soulSourcePath: agent.openClawDefinition.soulSourcePath,
            lastImportedSoulHash: agent.openClawDefinition.lastImportedSoulHash,
            lastImportedSoulPath: agent.openClawDefinition.lastImportedSoulPath,
            lastImportedAt: agent.openClawDefinition.lastImportedAt,
            environment: agent.openClawDefinition.environment
        )
        try encode(bindingDocument, to: openClawRootURL.appendingPathComponent("binding.json", isDirectory: false))
        try encode(
            agent.openClawDefinition.protocolMemory,
            to: stateRootURL.appendingPathComponent("protocol-memory.json", isDirectory: false)
        )
        try writeOpenClawWorkspaceDocuments(
            for: agent,
            nodeID: node.id,
            workspaceRootURL: workspaceRootURL,
            mirrorRootURL: mirrorRootURL,
            stateRootURL: stateRootURL
        )
    }

    private func writeOpenClawWorkspaceDocuments(
        for agent: Agent,
        nodeID: UUID,
        workspaceRootURL: URL,
        mirrorRootURL: URL,
        stateRootURL: URL
    ) throws {
        let memoryRootURL = workspaceRootURL.appendingPathComponent("memory", isDirectory: true)
        let skillsRootURL = workspaceRootURL.appendingPathComponent("skills", isDirectory: true)

        for directory in [memoryRootURL, skillsRootURL] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        try syncMirroredOpenClawWorkspaceArtifacts(
            for: agent,
            memoryRootURL: memoryRootURL,
            skillsRootURL: skillsRootURL
        )

        for fileName in Self.managedOpenClawWorkspaceMarkdownFiles {
            guard let defaultContent = defaultManagedOpenClawWorkspaceDocument(
                named: fileName,
                agent: agent,
                nodeID: nodeID
            ) else {
                continue
            }
            try writeManagedWorkspaceDocumentIfMissing(
                defaultContent,
                to: workspaceRootURL.appendingPathComponent(fileName, isDirectory: false)
            )
        }

        try encode(
            NodeOpenClawSourceMapDocument(
                nodeID: nodeID,
                agentID: agent.id,
                agentIdentifier: agent.openClawDefinition.agentIdentifier,
                soulSourcePath: agent.openClawDefinition.soulSourcePath,
                mirroredSoulRelativePath: "workspace/SOUL.md",
                memoryBackupPath: agent.openClawDefinition.memoryBackupPath,
                mirroredWorkspaceRelativePath: "workspace",
                generatedAt: Date()
            ),
            to: mirrorRootURL.appendingPathComponent("source-map.json", isDirectory: false)
        )
        try encode(
            NodeOpenClawSyncBaselineDocument(
                nodeID: nodeID,
                agentID: agent.id,
                lastImportedSoulHash: agent.openClawDefinition.lastImportedSoulHash,
                lastImportedSoulPath: agent.openClawDefinition.lastImportedSoulPath,
                lastImportedAt: agent.openClawDefinition.lastImportedAt,
                generatedAt: Date()
            ),
            to: mirrorRootURL.appendingPathComponent("sync-baseline.json", isDirectory: false)
        )
        try encode(
            NodeOpenClawImportRecordDocument(
                nodeID: nodeID,
                agentID: agent.id,
                agentIdentifier: agent.openClawDefinition.agentIdentifier,
                soulSourcePath: agent.openClawDefinition.soulSourcePath,
                memoryBackupPath: agent.openClawDefinition.memoryBackupPath,
                lastImportedSoulHash: agent.openClawDefinition.lastImportedSoulHash,
                lastImportedSoulPath: agent.openClawDefinition.lastImportedSoulPath,
                lastImportedAt: agent.openClawDefinition.lastImportedAt,
                generatedAt: Date()
            ),
            to: stateRootURL.appendingPathComponent("import-record.json", isDirectory: false)
        )
    }

    private func syncMirroredOpenClawWorkspaceArtifacts(
        for agent: Agent,
        memoryRootURL: URL,
        skillsRootURL: URL
    ) throws {
        try recreateDirectory(at: skillsRootURL)
        try recreateDirectory(at: memoryRootURL)

        if let skillsSourceURL = resolveOpenClawWorkspaceRootURL(for: agent)?
            .appendingPathComponent("skills", isDirectory: true),
           directoryExists(at: skillsSourceURL) {
            try copyDirectoryContents(from: skillsSourceURL, to: skillsRootURL)
        }

        let workspaceMemoryRootURL = memoryRootURL.appendingPathComponent("workspace", isDirectory: true)
        let backupMemoryRootURL = memoryRootURL.appendingPathComponent("backup", isDirectory: true)
        try fileManager.createDirectory(at: workspaceMemoryRootURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: backupMemoryRootURL, withIntermediateDirectories: true)

        if let workspaceMemorySourceURL = resolveOpenClawWorkspaceRootURL(for: agent)?
            .appendingPathComponent("memory", isDirectory: true),
           directoryExists(at: workspaceMemorySourceURL) {
            try copyDirectoryContents(from: workspaceMemorySourceURL, to: workspaceMemoryRootURL)
        }

        if let backupMemorySourceURL = resolveOpenClawMemoryBackupRootURL(for: agent),
           directoryExists(at: backupMemorySourceURL) {
            try copyDirectoryContents(from: backupMemorySourceURL, to: backupMemoryRootURL)
        }
    }

    private func resolveOpenClawWorkspaceRootURL(for agent: Agent) -> URL? {
        if let memoryBackupRootURL = resolveOpenClawMemoryBackupRootURL(for: agent) {
            let candidate = memoryBackupRootURL.lastPathComponent == "private"
                ? memoryBackupRootURL.deletingLastPathComponent().appendingPathComponent("workspace", isDirectory: true)
                : memoryBackupRootURL.appendingPathComponent("workspace", isDirectory: true)
            if directoryExists(at: candidate) {
                return candidate
            }
        }

        guard let soulSourcePath = normalizedNonEmptyPath(agent.openClawDefinition.soulSourcePath) else {
            return nil
        }

        var candidate = URL(fileURLWithPath: soulSourcePath, isDirectory: false).deletingLastPathComponent()
        for _ in 0..<6 {
            if directoryLooksLikeOpenClawWorkspace(candidate) {
                return candidate
            }

            let next = candidate.deletingLastPathComponent()
            if next.path == candidate.path {
                break
            }
            candidate = next
        }

        return nil
    }

    private func resolveOpenClawMemoryBackupRootURL(for agent: Agent) -> URL? {
        guard let memoryBackupPath = normalizedNonEmptyPath(agent.openClawDefinition.memoryBackupPath) else {
            return nil
        }

        let url = URL(fileURLWithPath: memoryBackupPath, isDirectory: true)
        return directoryExists(at: url) ? url : nil
    }

    private func normalizedNonEmptyPath(_ path: String?) -> String? {
        let trimmed = path?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func directoryLooksLikeOpenClawWorkspace(_ url: URL) -> Bool {
        if fileManager.fileExists(atPath: url.appendingPathComponent("SOUL.md", isDirectory: false).path) {
            return true
        }

        return directoryExists(at: url.appendingPathComponent("skills", isDirectory: true))
            || directoryExists(at: url.appendingPathComponent("memory", isDirectory: true))
    }

    private func directoryExists(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private func recreateDirectory(at url: URL) throws {
        if fileManager.fileExists(atPath: url.path) {
            try? fileManager.removeItem(at: url)
        }
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private func copyDirectoryContents(from sourceURL: URL, to destinationURL: URL) throws {
        let contents = try fileManager.contentsOfDirectory(
            at: sourceURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        for item in contents {
            let destinationItemURL = destinationURL.appendingPathComponent(item.lastPathComponent, isDirectory: false)
            if fileManager.fileExists(atPath: destinationItemURL.path) {
                try? fileManager.removeItem(at: destinationItemURL)
            }
            try fileManager.copyItem(at: item, to: destinationItemURL)
        }
    }

    private func writeTextDocument(_ text: String, to url: URL) throws {
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func writeManagedWorkspaceDocumentIfMissing(_ text: String, to url: URL) throws {
        guard !fileManager.fileExists(atPath: url.path) else { return }
        try writeTextDocument(text, to: url)
    }

    private func renderAgentsMarkdown(agent: Agent, nodeID: UUID) -> String {
        """
        # AGENTS

        - agent_name: \(agent.name)
        - agent_id: \(agent.id.uuidString)
        - node_id: \(nodeID.uuidString)
        - agent_identifier: \(normalizedOrPlaceholder(agent.openClawDefinition.agentIdentifier))
        """
    }

    private func renderIdentityMarkdown(agent: Agent) -> String {
        """
        # IDENTITY

        \(normalizedOrPlaceholder(agent.identity))
        """
    }

    private func renderUserMarkdown(agent: Agent) -> String {
        """
        # USER.md - About Your Human

        _Learn about the person you're helping. Update this as you go._

        - **Name:**
        - **What to call them:**
        - **Pronouns:** _(optional)_
        - **Timezone:**
        - **Notes:**

        ## Context

        _(What do they care about? What projects are they working on? What annoys them? What makes them laugh? Build this over time.)_

        ---

        The more you know, the better you can help. But remember - you're learning about a person, not building a dossier. Respect the difference.
        """
    }

    private func renderToolsMarkdown(agent: Agent) -> String {
        let capabilities = agent.capabilities.isEmpty
            ? "- none"
            : agent.capabilities.sorted().map { "- \($0)" }.joined(separator: "\n")
        let environment = agent.openClawDefinition.environment.isEmpty
            ? "- none"
            : agent.openClawDefinition.environment
                .sorted { $0.key < $1.key }
                .map { "- \($0.key)=\($0.value)" }
                .joined(separator: "\n")

        return """
        # TOOLS

        Model: \(normalizedOrPlaceholder(agent.openClawDefinition.modelIdentifier))
        Runtime Profile: \(normalizedOrPlaceholder(agent.openClawDefinition.runtimeProfile))

        ## Capabilities
        \(capabilities)

        ## Environment
        \(environment)
        """
    }

    private func renderBootstrapMarkdown(agent: Agent) -> String {
        """
        # BOOTSTRAP

        Agent Identifier: \(normalizedOrPlaceholder(agent.openClawDefinition.agentIdentifier))
        Model Identifier: \(normalizedOrPlaceholder(agent.openClawDefinition.modelIdentifier))
        Runtime Profile: \(normalizedOrPlaceholder(agent.openClawDefinition.runtimeProfile))
        Soul Source Path: \(normalizedOrPlaceholder(agent.openClawDefinition.soulSourcePath))
        """
    }

    private func renderHeartbeatMarkdown(agent: Agent) -> String {
        let recentCount = agent.openClawDefinition.protocolMemory.recentCorrections.count
        let repeatCount = agent.openClawDefinition.protocolMemory.repeatOffenses.count

        return """
        # HEARTBEAT

        Protocol Version: \(agent.openClawDefinition.protocolMemory.protocolVersion)
        Last Updated: \(iso8601String(from: agent.openClawDefinition.protocolMemory.lastUpdatedAt))
        Recent Corrections: \(recentCount)
        Repeat Offenses: \(repeatCount)
        """
    }

    private func renderMemoryMarkdown(agent: Agent) -> String {
        let stableRules = agent.openClawDefinition.protocolMemory.stableRules.isEmpty
            ? "- none"
            : agent.openClawDefinition.protocolMemory.stableRules.map { "- \($0)" }.joined(separator: "\n")

        return """
        # MEMORY

        Memory Backup Path: \(normalizedOrPlaceholder(agent.openClawDefinition.memoryBackupPath))
        Last Session Digest: \(normalizedOrPlaceholder(agent.openClawDefinition.protocolMemory.lastSessionDigest))

        ## Stable Rules
        \(stableRules)
        """
    }

    private func normalizedOrPlaceholder(_ value: String?, fallback: String = "Not recorded.") -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? fallback : trimmed
    }

    private func iso8601String(from date: Date?) -> String {
        guard let date else { return "Not recorded." }
        return ISO8601DateFormatter().string(from: date)
    }

    private func truncatedText(_ text: String, limit: Int = 120) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(limit)) + "..."
    }

    private func writeDerivedWorkflowState(for workflow: Workflow, under derivedRootURL: URL) throws {
        try encode(
            makeCommunicationMatrixDocument(for: workflow),
            to: derivedRootURL.appendingPathComponent("communication-matrix.json", isDirectory: false)
        )
        try encode(
            makeFileScopeMapDocument(for: workflow),
            to: derivedRootURL.appendingPathComponent("file-scope-map.json", isDirectory: false)
        )
        try encode(
            WorkflowLaunchReportDocument(
                workflowID: workflow.id,
                generatedAt: Date(),
                report: workflow.lastLaunchVerificationReport
            ),
            to: derivedRootURL.appendingPathComponent("launch-report.json", isDirectory: false)
        )
    }

    private func makeCommunicationMatrixDocument(for workflow: Workflow) -> WorkflowCommunicationMatrixDocument {
        let nodesByID = Dictionary(uniqueKeysWithValues: workflow.nodes.map { ($0.id, $0) })
        var routes: [WorkflowCommunicationRouteDocument] = []

        for edge in workflow.edges {
            if let route = makeCommunicationRoute(for: edge, nodesByID: nodesByID, isImplicitReverse: false) {
                routes.append(route)
            }
            if edge.isBidirectional,
               let reversedRoute = makeCommunicationRoute(for: edge.reversed(), nodesByID: nodesByID, isImplicitReverse: true) {
                routes.append(reversedRoute)
            }
        }

        return WorkflowCommunicationMatrixDocument(
            workflowID: workflow.id,
            generatedAt: Date(),
            routes: routes
        )
    }

    private func makeCommunicationRoute(
        for edge: WorkflowEdge,
        nodesByID: [UUID: WorkflowNode],
        isImplicitReverse: Bool
    ) -> WorkflowCommunicationRouteDocument? {
        guard let fromNode = nodesByID[edge.fromNodeID], let toNode = nodesByID[edge.toNodeID] else {
            return nil
        }

        return WorkflowCommunicationRouteDocument(
            edgeID: edge.id,
            fromNodeID: fromNode.id,
            toNodeID: toNode.id,
            fromAgentID: fromNode.agentID,
            toAgentID: toNode.agentID,
            permissionType: edge.requiresApproval ? .requireApproval : .allow,
            requiresApproval: edge.requiresApproval,
            isBidirectional: edge.isBidirectional,
            isImplicitReverse: isImplicitReverse,
            label: edge.label,
            conditionExpression: edge.conditionExpression
        )
    }

    private func makeFileScopeMapDocument(for workflow: Workflow) -> WorkflowFileScopeMapDocument {
        let boundaryScopes = workflow.boundaries.map { boundary in
            WorkflowBoundaryScopeDocument(
                boundaryID: boundary.id,
                title: boundary.title,
                memberNodeIDs: boundary.memberNodeIDs,
                geometryContainedNodeIDs: workflow.nodes
                    .filter { boundary.contains(point: $0.position) }
                    .map(\.id)
            )
        }

        let nodeScopes = workflow.nodes.map { sourceNode in
            let readableNodeIDs = workflow.nodes
                .filter { fileAccessAllowed(in: workflow, from: sourceNode, to: $0) }
                .map(\.id)
            let restrictedNodeIDs = workflow.nodes
                .filter { !fileAccessAllowed(in: workflow, from: sourceNode, to: $0) }
                .map(\.id)

            return WorkflowNodeFileAccessDocument(
                nodeID: sourceNode.id,
                agentID: sourceNode.agentID,
                enclosingBoundaryID: workflow.boundary(containing: sourceNode.position)?.id,
                readableNodeIDs: readableNodeIDs,
                restrictedNodeIDs: restrictedNodeIDs
            )
        }

        return WorkflowFileScopeMapDocument(
            workflowID: workflow.id,
            generatedAt: Date(),
            defaultAccess: .allow,
            boundaryScopes: boundaryScopes,
            nodeScopes: nodeScopes
        )
    }

    private func fileAccessAllowed(in workflow: Workflow, from sourceNode: WorkflowNode, to targetNode: WorkflowNode) -> Bool {
        guard sourceNode.id != targetNode.id else { return true }

        if let sourceBoundary = workflow.boundary(containing: sourceNode.position) {
            return sourceBoundary.contains(point: targetNode.position)
        }

        if workflow.boundary(containing: targetNode.position) != nil {
            return true
        }

        return true
    }

    private func assembleWorkflowDesignState(
        workflowID: UUID,
        under workflowsRootURL: URL,
        designAgentsByID: inout [UUID: Agent]
    ) throws -> Workflow {
        let workflowRootURL = workflowsRootURL.appendingPathComponent(workflowID.uuidString, isDirectory: true)
        let workflowDocumentURL = workflowRootURL.appendingPathComponent("workflow.json", isDirectory: false)
        guard fileManager.fileExists(atPath: workflowDocumentURL.path) else {
            throw ProjectFileSystemError.missingDesignDocument(path: workflowDocumentURL.path)
        }

        let workflowDocument = try decode(WorkflowDesignDocument.self, from: workflowDocumentURL)
        let nodesRootURL = workflowRootURL.appendingPathComponent("nodes", isDirectory: true)
        let edgesRootURL = workflowRootURL.appendingPathComponent("edges", isDirectory: true)
        let boundariesRootURL = workflowRootURL.appendingPathComponent("boundaries", isDirectory: true)

        let nodes = try workflowDocument.nodeIDs.map { nodeID in
            try loadNodeDesignState(
                nodeID: nodeID,
                workflowID: workflowDocument.id,
                under: nodesRootURL,
                designAgentsByID: &designAgentsByID
            )
        }
        let edges = try workflowDocument.edgeIDs.map { edgeID in
            let url = edgesRootURL.appendingPathComponent("\(edgeID.uuidString).json", isDirectory: false)
            guard fileManager.fileExists(atPath: url.path) else {
                throw ProjectFileSystemError.missingDesignDocument(path: url.path)
            }
            return try decode(WorkflowEdge.self, from: url)
        }
        let boundaries = try workflowDocument.boundaryIDs.map { boundaryID in
            let url = boundariesRootURL.appendingPathComponent("\(boundaryID.uuidString).json", isDirectory: false)
            guard fileManager.fileExists(atPath: url.path) else {
                throw ProjectFileSystemError.missingDesignDocument(path: url.path)
            }
            return try decode(WorkflowBoundary.self, from: url)
        }

        return try makeWorkflow(
            from: workflowDocument,
            nodes: nodes,
            edges: edges,
            boundaries: boundaries
        )
    }

    private func loadNodeDesignState(
        nodeID: UUID,
        workflowID: UUID,
        under nodesRootURL: URL,
        designAgentsByID: inout [UUID: Agent]
    ) throws -> WorkflowNode {
        let nodeRootURL = nodesRootURL.appendingPathComponent(nodeID.uuidString, isDirectory: true)
        let nodeDocumentURL = nodeRootURL.appendingPathComponent("node.json", isDirectory: false)
        guard fileManager.fileExists(atPath: nodeDocumentURL.path) else {
            throw ProjectFileSystemError.missingDesignDocument(path: nodeDocumentURL.path)
        }

        let nodeDocument = try decode(NodeDesignDocument.self, from: nodeDocumentURL)
        guard nodeDocument.workflowID == workflowID else {
            throw ProjectFileSystemError.missingDesignDocument(path: nodeDocumentURL.path)
        }

        var node = try decode(WorkflowNode.self, from: nodeDocumentURL)
        if let agent = try loadNodeAgentDesignState(node: node, at: nodeRootURL) {
            node.agentID = agent.id
            designAgentsByID[agent.id] = agent
        } else if let agentID = nodeDocument.agentID {
            throw ProjectFileSystemError.missingNodeAgentDocument(nodeID: node.id, agentID: agentID)
        }

        return node
    }

    private func loadNodeAgentDesignState(node: WorkflowNode, at nodeRootURL: URL) throws -> Agent? {
        let agentDocumentURL = nodeRootURL.appendingPathComponent("agent.json", isDirectory: false)
        guard fileManager.fileExists(atPath: agentDocumentURL.path) else { return nil }

        let agentDocument = try decode(NodeAgentDesignDocument.self, from: agentDocumentURL)
        if let expectedAgentID = node.agentID, expectedAgentID != agentDocument.id {
            throw ProjectFileSystemError.agentBindingMismatch(
                nodeID: node.id,
                expectedAgentID: expectedAgentID,
                actualAgentID: agentDocument.id
            )
        }

        let openClawRootURL = nodeRootURL.appendingPathComponent("openclaw", isDirectory: true)
        let bindingURL = openClawRootURL.appendingPathComponent("binding.json", isDirectory: false)
        let protocolMemoryURL = openClawRootURL
            .appendingPathComponent("state", isDirectory: true)
            .appendingPathComponent("protocol-memory.json", isDirectory: false)
        let soulURL = openClawRootURL
            .appendingPathComponent("workspace", isDirectory: true)
            .appendingPathComponent("SOUL.md", isDirectory: false)

        let binding = fileManager.fileExists(atPath: bindingURL.path)
            ? try decode(NodeOpenClawBindingDocument.self, from: bindingURL)
            : nil
        if let binding, binding.agentID != agentDocument.id {
            throw ProjectFileSystemError.agentBindingMismatch(
                nodeID: node.id,
                expectedAgentID: agentDocument.id,
                actualAgentID: binding.agentID
            )
        }

        var openClawDefinition = agentDocument.openClawDefinition
        if let binding {
            openClawDefinition.agentIdentifier = binding.agentIdentifier
            openClawDefinition.modelIdentifier = binding.modelIdentifier
            openClawDefinition.runtimeProfile = binding.runtimeProfile
            openClawDefinition.memoryBackupPath = binding.memoryBackupPath
            openClawDefinition.soulSourcePath = binding.soulSourcePath
            openClawDefinition.lastImportedSoulHash = binding.lastImportedSoulHash
            openClawDefinition.lastImportedSoulPath = binding.lastImportedSoulPath
            openClawDefinition.lastImportedAt = binding.lastImportedAt
            openClawDefinition.environment = binding.environment
        }
        if fileManager.fileExists(atPath: protocolMemoryURL.path) {
            openClawDefinition.protocolMemory = try decode(OpenClawAgentProtocolMemory.self, from: protocolMemoryURL)
        }

        let soulMD: String
        if fileManager.fileExists(atPath: soulURL.path) {
            soulMD = try String(contentsOf: soulURL, encoding: .utf8)
        } else {
            soulMD = "# \(agentDocument.name)\n"
        }

        return try makeAgent(from: agentDocument, soulMD: soulMD, openClawDefinition: openClawDefinition)
    }

    private func makeAgent(
        from document: NodeAgentDesignDocument,
        soulMD: String,
        openClawDefinition: OpenClawAgentDefinition
    ) throws -> Agent {
        try decode(
            Agent.self,
            from: encodeToData(
                AgentAssemblySeed(
                    id: document.id,
                    name: document.name,
                    identity: document.identity,
                    description: document.description,
                    soulMD: soulMD,
                    position: .zero,
                    createdAt: document.createdAt,
                    updatedAt: document.updatedAt,
                    capabilities: document.capabilities,
                    colorHex: document.colorHex,
                    openClawDefinition: openClawDefinition
                )
            )
        )
    }

    private func makeWorkflow(
        from document: WorkflowDesignDocument,
        nodes: [WorkflowNode],
        edges: [WorkflowEdge],
        boundaries: [WorkflowBoundary]
    ) throws -> Workflow {
        try decode(
            Workflow.self,
            from: encodeToData(
                WorkflowAssemblySeed(
                    id: document.id,
                    name: document.name,
                    fallbackRoutingPolicy: document.fallbackRoutingPolicy,
                    launchTestCases: document.launchTestCases,
                    lastLaunchVerificationReport: document.lastLaunchVerificationReport,
                    nodes: nodes,
                    edges: edges,
                    boundaries: boundaries,
                    colorGroups: document.colorGroups,
                    createdAt: document.createdAt,
                    parentNodeID: document.parentNodeID,
                    inputSchema: document.inputSchema,
                    outputSchema: document.outputSchema
                )
            )
        )
    }

    private func makeEmptyProject(from document: ProjectDesignDocument) throws -> MAProject {
        try decode(
            MAProject.self,
            from: encodeToData(
                ProjectAssemblySeed(
                    id: document.projectID,
                    fileVersion: document.fileVersion,
                    name: document.projectName,
                    agents: [],
                    workflows: [],
                    permissions: [],
                    openClaw: ProjectOpenClawSnapshot(),
                    taskData: ProjectTaskDataSettings(),
                    tasks: [],
                    messages: [],
                    executionResults: [],
                    executionLogs: [],
                    workspaceIndex: [],
                    memoryData: ProjectMemoryData(),
                    runtimeState: RuntimeState(),
                    createdAt: document.createdAt,
                    updatedAt: document.updatedAt
                )
            )
        )
    }

    private func workbenchSessionID(from metadata: [String: String]) -> String? {
        normalizedSessionID(metadata["workbenchSessionID"])
    }

    private func workflowIDFromMetadata(_ metadata: [String: String]) -> UUID? {
        guard let rawValue = metadata["workflowID"] else { return nil }
        return UUID(uuidString: rawValue.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func entryAgentIDFromMetadata(_ metadata: [String: String]) -> UUID? {
        guard let rawValue = metadata["entryAgentID"] else { return nil }
        return UUID(uuidString: rawValue.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func workbenchThreadType(from metadata: [String: String]) -> ArchivedRuntimeSessionType? {
        ArchivedRuntimeSessionType(
            normalizedRawValue: metadata["workbenchThreadType"] ?? metadata["executionIntent"]
        )
    }

    private func workbenchThreadMode(from metadata: [String: String]) -> ArchivedWorkbenchThreadMode? {
        ArchivedWorkbenchThreadMode(
            normalizedRawValue: metadata["workbenchThreadMode"] ?? metadata["workbenchMode"]
        )
    }

    private func normalizedSessionID(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func safeStorageName(for rawValue: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        return rawValue.addingPercentEncoding(withAllowedCharacters: allowed) ?? rawValue
    }

    private func workbenchThreadStatus(messages: [Message], tasks: [Task]) -> String {
        if messages.contains(where: { $0.status == .waitingForApproval }) {
            return "approval_pending"
        }
        if tasks.contains(where: { $0.status == .blocked }) {
            return "blocked"
        }
        if tasks.contains(where: { $0.status == .inProgress || $0.status == .todo }) {
            return "active"
        }
        if tasks.contains(where: { $0.status == .done }) {
            return "completed"
        }
        return messages.isEmpty ? "idle" : "active"
    }

    private func resolveWorkbenchThreadSemantics(
        messages: [Message],
        tasks: [Task],
        linkedSessionTypes: [ArchivedRuntimeSessionType] = []
    ) -> (type: ArchivedRuntimeSessionType, mode: ArchivedWorkbenchThreadMode) {
        let explicitTypes = messages.compactMap { workbenchThreadType(from: $0.metadata) }
            + tasks.compactMap { workbenchThreadType(from: $0.metadata) }
        let explicitModes = messages.compactMap { workbenchThreadMode(from: $0.metadata) }
            + tasks.compactMap { workbenchThreadMode(from: $0.metadata) }
        let allTypes = explicitTypes + linkedSessionTypes

        let resolvedType = ArchivedRuntimeSessionType.preferredWorkbenchThreadType(from: allTypes)
            ?? .conversationAutonomous
        let resolvedMode = ArchivedWorkbenchThreadMode.preferredMode(from: explicitModes)
            ?? ArchivedWorkbenchThreadMode.inferred(from: allTypes.isEmpty ? [resolvedType] : allTypes)

        return (resolvedType, resolvedMode)
    }

    private func makeWorkbenchTurnAuditDocuments(
        threadID: String,
        sessionID: String,
        workflowID: UUID?,
        messages: [Message],
        agentsByID: [UUID: Agent]
    ) -> [WorkbenchTurnAuditDocument] {
        messages.map { message in
            let role = message.inferredRole ?? message.metadata["role"] ?? "assistant"
            let agentName = message.runtimeEvent?.source.agentName
                ?? message.metadata["agentName"]
                ?? agentsByID[message.fromAgentID]?.name

            return WorkbenchTurnAuditDocument(
                turnID: message.id,
                threadID: threadID,
                sessionID: sessionID,
                workflowID: workflowID,
                taskID: message.metadata["taskID"].flatMap(UUID.init(uuidString:)),
                messageID: message.id,
                role: role,
                kind: message.inferredKind ?? message.metadata["kind"] ?? "output",
                status: message.status.rawValue,
                agentID: role == "user" ? nil : message.fromAgentID,
                agentName: role == "user" ? "User" : agentName,
                executionIntent: message.metadata["executionIntent"]
                    ?? message.runtimeEvent?.control["executionIntent"]
                    ?? message.runtimeEvent?.payload["executionIntent"],
                threadType: message.metadata["workbenchThreadType"]
                    ?? message.runtimeEvent?.control["workbenchThreadType"],
                threadMode: message.metadata["workbenchThreadMode"]
                    ?? message.runtimeEvent?.control["workbenchThreadMode"],
                interactionMode: message.metadata["workbenchMode"],
                outputType: message.inferredOutputType,
                tokenEstimate: message.metadata["tokenEstimate"].flatMap(Int.init),
                summary: truncatedText(message.summaryText, limit: 240),
                timestamp: message.timestamp
            )
        }
    }

    private func makeWorkbenchDelegationAuditDocuments(
        threadID: String,
        sessionID: String,
        dispatches: [RuntimeDispatchEnvelopeDocument],
        events: [OpenClawRuntimeEvent]
    ) -> [WorkbenchDelegationAuditDocument] {
        let eventsByID = Dictionary(uniqueKeysWithValues: events.map { ($0.id, $0) })

        return dispatches.map { envelope in
            let record = envelope.record
            let event = eventsByID[record.eventID]
            return WorkbenchDelegationAuditDocument(
                delegationID: record.id,
                threadID: threadID,
                sessionID: sessionID,
                workflowID: record.workflowID,
                nodeID: record.nodeID,
                parentDelegationID: record.parentEventID,
                sourceAgentID: record.sourceAgentID,
                sourceAgentName: event?.source.agentName,
                targetAgentID: record.targetAgentID,
                targetAgentName: event?.target.agentName,
                status: record.status.rawValue,
                eventType: event?.eventType.rawValue,
                executionIntent: record.executionIntent ?? event?.control["executionIntent"] ?? event?.payload["executionIntent"],
                threadType: event?.control["workbenchThreadType"],
                threadMode: event?.control["workbenchThreadMode"],
                transportKind: record.transportKind.rawValue,
                attempt: record.attempt,
                allowRetry: record.allowRetry,
                maxRetries: record.maxRetries,
                summary: truncatedText(record.summary, limit: 240),
                errorMessage: record.errorMessage,
                queuedAt: record.queuedAt,
                updatedAt: record.updatedAt,
                completedAt: record.completedAt
            )
        }
    }

    private func makeRuntimeSessionSpanAuditDocuments(
        sessionID: String,
        threadID: String?,
        workflowID: UUID?,
        receipts: [ExecutionResult],
        agentsByID: [UUID: Agent]
    ) -> [RuntimeSessionSpanAuditDocument] {
        receipts.map { receipt in
            RuntimeSessionSpanAuditDocument(
                spanID: receipt.id,
                sessionID: sessionID,
                threadID: threadID,
                workflowID: workflowID,
                nodeID: receipt.nodeID,
                agentID: receipt.agentID,
                agentName: agentsByID[receipt.agentID]?.name,
                status: receipt.status.rawValue,
                executionIntent: receipt.executionIntent,
                transportKind: receipt.transportKind,
                outputType: receipt.outputType.rawValue,
                linkedEventIDs: receipt.runtimeEvents.map(\.id),
                primaryEventID: receipt.primaryRuntimeEvent?.id,
                parentEventID: receipt.primaryRuntimeEvent?.parentEventId,
                routingAction: receipt.routingAction,
                routingTargets: receipt.routingTargets,
                requestedRoutingAction: receipt.requestedRoutingAction,
                requestedRoutingTargets: receipt.requestedRoutingTargets,
                protocolRepairCount: receipt.protocolRepairCount,
                protocolRepairTypes: receipt.protocolRepairTypes,
                protocolSafeDegradeApplied: receipt.protocolSafeDegradeApplied,
                summary: truncatedText(receipt.summaryText, limit: 240),
                startedAt: receipt.startedAt,
                completedAt: receipt.completedAt,
                duration: receipt.duration,
                firstChunkLatencyMs: receipt.firstChunkLatencyMs,
                completionLatencyMs: receipt.completionLatencyMs
            )
        }
    }

    private func buildWorkbenchThreadLinks(
        messages: [Message],
        tasks: [Task],
        agentsByID: [UUID: Agent]
    ) -> [String: WorkbenchThreadLinkSnapshot] {
        let sessionIDs = Set(messages.compactMap { workbenchSessionID(from: $0.metadata) })
            .union(tasks.compactMap { workbenchSessionID(from: $0.metadata) })
            .sorted()

        return Dictionary(uniqueKeysWithValues: sessionIDs.map { sessionID in
            let sessionMessages = messages.filter { workbenchSessionID(from: $0.metadata) == sessionID }
            let sessionTasks = tasks.filter { workbenchSessionID(from: $0.metadata) == sessionID }
            let semantics = resolveWorkbenchThreadSemantics(messages: sessionMessages, tasks: sessionTasks)
            let workflowID = sessionMessages.compactMap { workflowIDFromMetadata($0.metadata) }.first
                ?? sessionTasks.compactMap { workflowIDFromMetadata($0.metadata) }.first
            let entryAgentID = sessionMessages.compactMap { entryAgentIDFromMetadata($0.metadata) }.first
                ?? sessionTasks.compactMap(\.assignedAgentID).first
            let entryAgentName = entryAgentID.flatMap { agentsByID[$0]?.name }
            let gatewaySessionKey = entryAgentID
                .flatMap { agentsByID[$0] }
                .map { workbenchGatewaySessionKey(sessionID: sessionID, agent: $0) }

            return (
                sessionID,
                WorkbenchThreadLinkSnapshot(
                    threadID: sessionID,
                    threadType: semantics.type,
                    threadMode: semantics.mode,
                    workflowID: workflowID,
                    entryAgentID: entryAgentID,
                    entryAgentName: entryAgentName,
                    gatewaySessionKey: gatewaySessionKey
                )
            )
        })
    }

    private func runtimeSessionType(from rawValue: String?) -> ArchivedRuntimeSessionType? {
        ArchivedRuntimeSessionType(normalizedRawValue: rawValue)
    }

    private func classifyRuntimeSession(
        sessionID: String,
        project: MAProject,
        sessionMessages: [Message],
        sessionTasks: [Task],
        sessionDispatches: [RuntimeDispatchEnvelopeDocument],
        sessionEvents: [OpenClawRuntimeEvent],
        sessionReceipts: [ExecutionResult],
        workbenchThreadLinks: [String: WorkbenchThreadLinkSnapshot]
    ) -> RuntimeSessionArchiveClassification {
        let directThreadLink = workbenchThreadLinks[sessionID]
        let gatewayThreadLink = workbenchThreadLinks.values.first { $0.gatewaySessionKey == sessionID }
        let linkedThread = directThreadLink ?? gatewayThreadLink
        let dispatchSessionTypes = sessionDispatches.compactMap { runtimeSessionType(from: $0.record.executionIntent) }
        let eventSessionTypes = sessionEvents.compactMap {
            runtimeSessionType(from: $0.control["executionIntent"] ?? $0.payload["executionIntent"])
        }
        let receiptSessionTypes = sessionReceipts.compactMap { runtimeSessionType(from: $0.executionIntent) }
        let messageSessionTypes = sessionMessages.compactMap { workbenchThreadType(from: $0.metadata) }
        let taskSessionTypes = sessionTasks.compactMap { workbenchThreadType(from: $0.metadata) }
        let linkedThreadSessionTypes = linkedThread.map { [$0.threadType] } ?? []
        let recordedSessionTypes: Set<ArchivedRuntimeSessionType> = Set(
            dispatchSessionTypes
                + eventSessionTypes
                + receiptSessionTypes
                + messageSessionTypes
                + taskSessionTypes
                + linkedThreadSessionTypes
        )

        let sessionType: ArchivedRuntimeSessionType
        if recordedSessionTypes.contains(.benchmark) || sessionID.lowercased().hasPrefix("benchmark-") || sessionID.lowercased().hasPrefix("workflow-benchmark-") {
            sessionType = .benchmark
        } else if recordedSessionTypes.contains(.inspectionReadonly) {
            sessionType = .inspectionReadonly
        } else if recordedSessionTypes.contains(.workflowControlled) || sessionID.lowercased().hasPrefix("workflow-") {
            sessionType = .workflowControlled
        } else if recordedSessionTypes.contains(.conversationAutonomous)
                    || recordedSessionTypes.contains(.conversationAssisted)
                    || directThreadLink != nil
                    || gatewayThreadLink != nil
                    || !sessionMessages.isEmpty
                    || !sessionTasks.isEmpty
                    || sessionID.lowercased().hasPrefix("workbench-")
                    || sessionID.lowercased().hasPrefix("conversation-")
                    || sessionID.lowercased().hasPrefix("agent:") {
            sessionType = recordedSessionTypes.contains(.conversationAssisted) ? .conversationAssisted : .conversationAutonomous
        } else if sessionID == project.runtimeState.sessionID || !sessionDispatches.isEmpty || !sessionReceipts.isEmpty || !sessionEvents.isEmpty {
            sessionType = .workflowControlled
        } else {
            sessionType = .unknown
        }

        let workflowID = linkedThread?.workflowID
            ?? sessionMessages.compactMap { workflowIDFromMetadata($0.metadata) }.first
            ?? sessionTasks.compactMap { workflowIDFromMetadata($0.metadata) }.first
            ?? sessionDispatches.compactMap { $0.record.workflowID }.compactMap { UUID(uuidString: $0) }
                .first
            ?? sessionEvents.compactMap(\.workflowId).compactMap { UUID(uuidString: $0) }.first

        let entryAgentID = linkedThread?.entryAgentID
            ?? sessionMessages.compactMap { entryAgentIDFromMetadata($0.metadata) }.first
            ?? sessionTasks.compactMap(\.assignedAgentID).first
            ?? sessionReceipts.map(\.agentID).first
        let entryAgentName = linkedThread?.entryAgentName
            ?? entryAgentID.flatMap { agentID in
                project.agents.first(where: { $0.id == agentID })?.name
            }

        return RuntimeSessionArchiveClassification(
            sessionType: sessionType,
            threadID: linkedThread?.threadID,
            workflowID: workflowID,
            entryAgentID: entryAgentID,
            entryAgentName: entryAgentName
        )
    }

    private func dominantTransportKind(from values: [String]) -> String? {
        let normalizedValues = values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        guard !normalizedValues.isEmpty else { return nil }

        let counts = normalizedValues.reduce(into: [String: Int]()) { partial, value in
            partial[value, default: 0] += 1
        }
        return counts.max { lhs, rhs in
            if lhs.value != rhs.value {
                return lhs.value < rhs.value
            }
            return lhs.key > rhs.key
        }?.key
    }

    private func plannedTransportKind(
        for sessionType: ArchivedRuntimeSessionType,
        deploymentKind: OpenClawDeploymentKind,
        actualTransport: String?
    ) -> String? {
        switch sessionType {
        case .conversationAutonomous, .conversationAssisted:
            return OpenClawRuntimeTransportKind.gatewayChat.rawValue
        case .workflowControlled, .inspectionReadonly:
            switch deploymentKind {
            case .remoteServer:
                return OpenClawRuntimeTransportKind.gatewayAgent.rawValue
            case .local, .container:
                return OpenClawRuntimeTransportKind.cli.rawValue
            }
        case .benchmark:
            return actualTransport
        case .unknown:
            return actualTransport
        }
    }

    private func modeStrings(for sessionType: ArchivedRuntimeSessionType) -> (requested: String, resolved: String) {
        switch sessionType {
        case .conversationAutonomous, .conversationAssisted:
            return ("chat", "chat")
        case .workflowControlled:
            return ("run", "run")
        case .inspectionReadonly:
            return ("inspect", "inspect")
        case .benchmark:
            return ("benchmark", "benchmark")
        case .unknown:
            return ("unknown", "unknown")
        }
    }

    private func makeRuntimeTransportPlan(
        sessionID: String,
        classification: RuntimeSessionArchiveClassification,
        project: MAProject,
        actualTransportKinds: [String],
        degradationReason: String?
    ) -> RuntimeTransportPlanDocument {
        let dominantActualTransport = dominantTransportKind(from: actualTransportKinds)
        let preferredTransport = plannedTransportKind(
            for: classification.sessionType,
            deploymentKind: project.openClaw.config.deploymentKind,
            actualTransport: dominantActualTransport
        )
        let modes = modeStrings(for: classification.sessionType)
        let fallbackReason: String?
        if let preferredTransport, let dominantActualTransport, preferredTransport != dominantActualTransport {
            fallbackReason = "Preferred transport \(preferredTransport) degraded to \(dominantActualTransport) for this archived session."
        } else {
            fallbackReason = nil
        }

        let controlPlaneSnapshot = Dictionary(
            uniqueKeysWithValues: project.openClaw.controlPlane.entries.map { entry in
                (entry.gate.rawValue, entry.status.rawValue)
            }
        )

        return RuntimeTransportPlanDocument(
            sessionID: sessionID,
            sessionType: classification.sessionType.rawValue,
            threadID: classification.threadID,
            requestedMode: modes.requested,
            resolvedMode: modes.resolved,
            preferredTransport: preferredTransport,
            actualTransport: dominantActualTransport,
            actualTransportKinds: actualTransportKinds,
            capabilitySnapshot: [
                "deploymentKind": project.openClaw.config.deploymentKind.rawValue,
                "runtimeOwnership": project.openClaw.config.runtimeOwnership.rawValue,
                "probeGate": controlPlaneSnapshot[ProjectOpenClawControlPlaneGate.probe.rawValue] ?? ProjectOpenClawControlPlaneStatus.pending.rawValue,
                "bindGate": controlPlaneSnapshot[ProjectOpenClawControlPlaneGate.bind.rawValue] ?? ProjectOpenClawControlPlaneStatus.pending.rawValue,
                "publishGate": controlPlaneSnapshot[ProjectOpenClawControlPlaneGate.publish.rawValue] ?? ProjectOpenClawControlPlaneStatus.pending.rawValue,
                "executeGate": controlPlaneSnapshot[ProjectOpenClawControlPlaneGate.execute.rawValue] ?? ProjectOpenClawControlPlaneStatus.pending.rawValue
            ],
            fallbackReason: fallbackReason,
            degradationReason: degradationReason,
            generatedAt: Date()
        )
    }

    private func workbenchGatewaySessionKey(sessionID: String, agent: Agent) -> String {
        let identifier = agent.openClawDefinition.agentIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedIdentifier = identifier.isEmpty ? agent.name : identifier
        let normalizedAgent = normalizedWorkbenchGatewayAgentID(resolvedIdentifier)
        let normalizedSessionID = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedSessionID.lowercased().hasPrefix("agent:") {
            return normalizedSessionID.lowercased()
        }
        return "agent:\(normalizedAgent):\(sanitizedWorkbenchGatewaySessionComponent(normalizedSessionID))"
    }

    private func normalizedWorkbenchGatewayAgentID(_ rawValue: String) -> String {
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
        let normalized = String(filtered).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return normalized.isEmpty ? "main" : normalized
    }

    private func sanitizedWorkbenchGatewaySessionComponent(_ rawValue: String) -> String {
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
        let normalized = String(filtered).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return normalized.isEmpty ? "main" : normalized
    }

    private func runtimeDispatchEnvelopes(from runtimeState: RuntimeState) -> [RuntimeDispatchEnvelopeDocument] {
        let queued = runtimeState.dispatchQueue.map {
            RuntimeDispatchEnvelopeDocument(stateBucket: "queued", record: $0)
        }
        let inflight = runtimeState.inflightDispatches.map {
            RuntimeDispatchEnvelopeDocument(stateBucket: "inflight", record: $0)
        }
        let completed = runtimeState.completedDispatches.map {
            RuntimeDispatchEnvelopeDocument(stateBucket: "completed", record: $0)
        }
        let failed = runtimeState.failedDispatches.map {
            RuntimeDispatchEnvelopeDocument(stateBucket: "failed", record: $0)
        }
        return (queued + inflight + completed + failed).sorted { lhs, rhs in
            if lhs.record.updatedAt != rhs.record.updatedAt {
                return lhs.record.updatedAt < rhs.record.updatedAt
            }
            return lhs.record.id < rhs.record.id
        }
    }

    private func makeThreadIndexEntries(for project: MAProject) -> [ThreadIndexEntryDocument] {
        let agentsByID = Dictionary(uniqueKeysWithValues: project.agents.map { ($0.id, $0) })
        let workbenchMessages = project.messages
            .filter { $0.metadata["channel"] == "workbench" }
            .sorted { $0.timestamp < $1.timestamp }
        let workbenchTasks = project.tasks.filter { $0.metadata["source"] == "workbench" }
        let sessionIDs = Set(workbenchMessages.compactMap { workbenchSessionID(from: $0.metadata) })
            .union(workbenchTasks.compactMap { workbenchSessionID(from: $0.metadata) })
            .sorted()

        return sessionIDs.map { sessionID in
            let sessionMessages = workbenchMessages.filter { workbenchSessionID(from: $0.metadata) == sessionID }
            let sessionTasks = workbenchTasks.filter { workbenchSessionID(from: $0.metadata) == sessionID }
            let semantics = resolveWorkbenchThreadSemantics(messages: sessionMessages, tasks: sessionTasks)
            let resolvedEntryAgentID = sessionMessages.compactMap { entryAgentIDFromMetadata($0.metadata) }.first
                ?? sessionTasks.compactMap(\.assignedAgentID).first
            let updatedAt = (sessionMessages.map(\.timestamp)
                + sessionTasks.map { $0.completedAt ?? $0.startedAt ?? $0.createdAt }).max() ?? project.updatedAt

            return ThreadIndexEntryDocument(
                threadID: sessionID,
                threadType: semantics.type.rawValue,
                mode: semantics.mode.rawValue,
                sessionID: sessionID,
                workflowID: sessionMessages.compactMap { workflowIDFromMetadata($0.metadata) }.first
                    ?? sessionTasks.compactMap { workflowIDFromMetadata($0.metadata) }.first,
                entryAgentID: resolvedEntryAgentID,
                entryAgentName: resolvedEntryAgentID.flatMap { agentsByID[$0]?.name },
                status: workbenchThreadStatus(messages: sessionMessages, tasks: sessionTasks),
                messageCount: sessionMessages.count,
                taskCount: sessionTasks.count,
                lastUpdatedAt: updatedAt
            )
        }
    }

    private func makeRuntimeSessionIndexEntries(for project: MAProject) -> [RuntimeSessionIndexEntryDocument] {
        let dispatches = runtimeDispatchEnvelopes(from: project.runtimeState)
        let workbenchThreadLinks = buildWorkbenchThreadLinks(
            messages: project.messages.filter { $0.metadata["channel"] == "workbench" },
            tasks: project.tasks.filter { $0.metadata["source"] == "workbench" },
            agentsByID: Dictionary(uniqueKeysWithValues: project.agents.map { ($0.id, $0) })
        )
        let sessionIDs = Set([project.runtimeState.sessionID])
            .union(project.messages.compactMap { workbenchSessionID(from: $0.metadata) })
            .union(project.tasks.compactMap { workbenchSessionID(from: $0.metadata) })
            .union(dispatches.compactMap { normalizedSessionID($0.record.sessionKey) })
            .union(project.runtimeState.runtimeEvents.compactMap { normalizedSessionID($0.sessionKey) })
            .union(project.executionResults.compactMap { normalizedSessionID($0.sessionID) })
            .sorted()

        return sessionIDs.map { sessionID in
            let sessionDispatches = dispatches.filter { normalizedSessionID($0.record.sessionKey) == sessionID }
            let sessionEvents = project.runtimeState.runtimeEvents.filter { normalizedSessionID($0.sessionKey) == sessionID }
            let sessionReceipts = project.executionResults.filter { normalizedSessionID($0.sessionID) == sessionID }
            let sessionMessages = project.messages.filter { workbenchSessionID(from: $0.metadata) == sessionID }
            let sessionTasks = project.tasks.filter { $0.metadata["source"] == "workbench" && workbenchSessionID(from: $0.metadata) == sessionID }
            let classification = classifyRuntimeSession(
                sessionID: sessionID,
                project: project,
                sessionMessages: sessionMessages,
                sessionTasks: sessionTasks,
                sessionDispatches: sessionDispatches,
                sessionEvents: sessionEvents,
                sessionReceipts: sessionReceipts,
                workbenchThreadLinks: workbenchThreadLinks
            )
            let transportPlan = makeRuntimeTransportPlan(
                sessionID: sessionID,
                classification: classification,
                project: project,
                actualTransportKinds: Array(
                    Set(
                        sessionDispatches.map { $0.record.transportKind.rawValue }
                            + sessionEvents.map { $0.transport.kind.rawValue }
                            + sessionReceipts.compactMap(\.transportKind)
                    )
                ).sorted(),
                degradationReason: (
                    sessionDispatches.compactMap(\.record.errorMessage)
                    + sessionReceipts.filter { $0.status == .failed }.map { truncatedText($0.summaryText, limit: 160) }
                ).first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            )
            let lastUpdatedAt = (
                sessionDispatches.map(\.record.updatedAt)
                + sessionEvents.map(\.timestamp)
                + sessionReceipts.compactMap { $0.completedAt ?? $0.startedAt }
            ).max()

            return RuntimeSessionIndexEntryDocument(
                sessionID: sessionID,
                sessionType: classification.sessionType.rawValue,
                threadID: classification.threadID,
                storageDirectoryName: safeStorageName(for: sessionID),
                plannedTransport: transportPlan.preferredTransport,
                actualTransport: transportPlan.actualTransport,
                eventCount: sessionEvents.count,
                dispatchCount: sessionDispatches.count,
                receiptCount: sessionReceipts.count,
                lastUpdatedAt: lastUpdatedAt,
                isProjectRuntimeSession: project.runtimeState.sessionID == sessionID
            )
        }
    }

    private func makeAnalyticsSessionProjectionEntries(for project: MAProject) -> [AnalyticsSessionProjectionEntry] {
        let dispatches = runtimeDispatchEnvelopes(from: project.runtimeState)
        let workbenchThreadLinks = buildWorkbenchThreadLinks(
            messages: project.messages.filter { $0.metadata["channel"] == "workbench" },
            tasks: project.tasks.filter { $0.metadata["source"] == "workbench" },
            agentsByID: Dictionary(uniqueKeysWithValues: project.agents.map { ($0.id, $0) })
        )
        let sessionIDs = Set([project.runtimeState.sessionID])
            .union(project.messages.compactMap { workbenchSessionID(from: $0.metadata) })
            .union(project.tasks.compactMap { workbenchSessionID(from: $0.metadata) })
            .union(dispatches.compactMap { normalizedSessionID($0.record.sessionKey) })
            .union(project.runtimeState.runtimeEvents.compactMap { normalizedSessionID($0.sessionKey) })
            .union(project.executionResults.compactMap { normalizedSessionID($0.sessionID) })
            .sorted()

        return sessionIDs.map { sessionID in
            let sessionDispatches = dispatches.filter { normalizedSessionID($0.record.sessionKey) == sessionID }
            let sessionEvents = project.runtimeState.runtimeEvents.filter { normalizedSessionID($0.sessionKey) == sessionID }
            let sessionReceipts = project.executionResults.filter { normalizedSessionID($0.sessionID) == sessionID }
            let sessionMessages = project.messages.filter { workbenchSessionID(from: $0.metadata) == sessionID }
            let sessionTasks = project.tasks.filter { workbenchSessionID(from: $0.metadata) == sessionID }
            let classification = classifyRuntimeSession(
                sessionID: sessionID,
                project: project,
                sessionMessages: sessionMessages,
                sessionTasks: sessionTasks,
                sessionDispatches: sessionDispatches,
                sessionEvents: sessionEvents,
                sessionReceipts: sessionReceipts,
                workbenchThreadLinks: workbenchThreadLinks
            )

            let workflowIDs = Set(
                sessionDispatches.compactMap(\.record.workflowID)
                    + sessionEvents.compactMap(\.workflowId)
                    + sessionMessages.compactMap { workflowIDFromMetadata($0.metadata)?.uuidString }
                    + sessionTasks.compactMap { workflowIDFromMetadata($0.metadata)?.uuidString }
            )
            .sorted()

            let latestFailureText = (
                sessionDispatches.compactMap(\.record.errorMessage)
                + sessionReceipts
                    .filter { $0.status == .failed }
                    .map { truncatedText($0.summaryText, limit: 160) }
            )
            .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            let transportPlan = makeRuntimeTransportPlan(
                sessionID: sessionID,
                classification: classification,
                project: project,
                actualTransportKinds: Array(
                    Set(
                        sessionDispatches.map { $0.record.transportKind.rawValue }
                            + sessionEvents.map { $0.transport.kind.rawValue }
                            + sessionReceipts.compactMap(\.transportKind)
                    )
                ).sorted(),
                degradationReason: latestFailureText
            )

            return AnalyticsSessionProjectionEntry(
                sessionID: sessionID,
                sessionType: classification.sessionType.rawValue,
                threadID: classification.threadID,
                workflowIDs: workflowIDs,
                plannedTransport: transportPlan.preferredTransport,
                actualTransport: transportPlan.actualTransport,
                actualTransportKinds: transportPlan.actualTransportKinds,
                messageCount: sessionMessages.count,
                taskCount: sessionTasks.count,
                eventCount: sessionEvents.count,
                dispatchCount: sessionDispatches.count,
                receiptCount: sessionReceipts.count,
                queuedDispatchCount: sessionDispatches.filter { $0.stateBucket == "queued" }.count,
                inflightDispatchCount: sessionDispatches.filter { $0.stateBucket == "inflight" }.count,
                completedDispatchCount: sessionDispatches.filter { $0.stateBucket == "completed" }.count,
                failedDispatchCount: sessionDispatches.filter { $0.stateBucket == "failed" }.count,
                latestFailureText: latestFailureText,
                fallbackReason: transportPlan.fallbackReason,
                degradationReason: transportPlan.degradationReason,
                lastUpdatedAt: (
                    sessionDispatches.map(\.record.updatedAt)
                    + sessionEvents.map(\.timestamp)
                    + sessionReceipts.compactMap { $0.completedAt ?? $0.startedAt }
                    + sessionMessages.map(\.timestamp)
                    + sessionTasks.map { $0.completedAt ?? $0.startedAt ?? $0.createdAt }
                ).max(),
                isProjectRuntimeSession: project.runtimeState.sessionID == sessionID
            )
        }
        .sorted { lhs, rhs in
            if lhs.isProjectRuntimeSession != rhs.isProjectRuntimeSession {
                return lhs.isProjectRuntimeSession
            }
            return (lhs.lastUpdatedAt ?? .distantPast) > (rhs.lastUpdatedAt ?? .distantPast)
        }
    }

    private func makeAnalyticsNodeRuntimeProjectionEntries(for project: MAProject) -> [AnalyticsNodeRuntimeProjectionEntry] {
        let dispatches = runtimeDispatchEnvelopes(from: project.runtimeState)
        let agentNamesByID = Dictionary(uniqueKeysWithValues: project.agents.map { ($0.id, $0.name) })

        return project.workflows
            .flatMap { workflow in
                workflow.nodes.map { node in
                    let relatedDispatches = analyticsRelatedDispatchEnvelopes(for: node, in: dispatches)
                    let relatedReceipts = project.executionResults.filter { $0.nodeID == node.id }
                    let latestReceipt = relatedReceipts.sorted {
                        ($0.completedAt ?? $0.startedAt) > ($1.completedAt ?? $1.startedAt)
                    }.first
                    let averageDuration: TimeInterval? = {
                        let durations = relatedReceipts.compactMap(\.duration)
                        guard !durations.isEmpty else { return nil }
                        return durations.reduce(0, +) / Double(durations.count)
                    }()

                    let relatedSessionIDs = Set(
                        relatedDispatches.compactMap { normalizedSessionID($0.record.sessionKey) }
                            + project.runtimeState.runtimeEvents.compactMap { event in
                                guard normalizedUUIDValue(event.nodeId) == node.id.uuidString.lowercased() else { return nil }
                                return normalizedSessionID(event.sessionKey)
                            }
                            + relatedReceipts.compactMap { normalizedSessionID($0.sessionID) }
                            + project.tasks
                                .filter { $0.workflowNodeID == node.id }
                                .compactMap { workbenchSessionID(from: $0.metadata) }
                    )
                    .sorted()

                    return AnalyticsNodeRuntimeProjectionEntry(
                        workflowID: workflow.id,
                        workflowName: workflow.name,
                        nodeID: node.id,
                        title: node.title,
                        agentID: node.agentID,
                        agentName: node.agentID.flatMap { agentNamesByID[$0] },
                        status: analyticsRuntimeStatus(
                            for: node,
                            dispatches: relatedDispatches,
                            latestReceipt: latestReceipt
                        ),
                        incomingEdgeCount: workflow.edges.filter { $0.toNodeID == node.id }.count,
                        outgoingEdgeCount: workflow.edges.filter { $0.fromNodeID == node.id }.count,
                        relatedSessionIDs: relatedSessionIDs,
                        queuedDispatchCount: relatedDispatches.filter { $0.stateBucket == "queued" }.count,
                        inflightDispatchCount: relatedDispatches.filter { $0.stateBucket == "inflight" }.count,
                        completedDispatchCount: relatedDispatches.filter { $0.stateBucket == "completed" }.count,
                        failedDispatchCount: relatedDispatches.filter { $0.stateBucket == "failed" }.count,
                        waitingApprovalCount: relatedDispatches.filter { $0.record.status == .waitingApproval }.count,
                        receiptCount: relatedReceipts.count,
                        averageDuration: averageDuration,
                        lastUpdatedAt: (
                            relatedDispatches.map(\.record.updatedAt)
                            + relatedReceipts.compactMap { $0.completedAt ?? $0.startedAt }
                        ).max(),
                        latestDetail: analyticsLatestDetailText(receipt: latestReceipt, dispatches: relatedDispatches)
                    )
                }
            }
            .sorted { lhs, rhs in
                if analyticsRuntimeStatusRank(lhs.status) != analyticsRuntimeStatusRank(rhs.status) {
                    return analyticsRuntimeStatusRank(lhs.status) < analyticsRuntimeStatusRank(rhs.status)
                }
                if lhs.workflowName != rhs.workflowName {
                    return lhs.workflowName.localizedCaseInsensitiveCompare(rhs.workflowName) == .orderedAscending
                }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }

    private func makeAnalyticsThreadProjectionEntries(for project: MAProject) -> [AnalyticsThreadProjectionEntry] {
        let workbenchMessages = project.messages.filter { $0.metadata["channel"] == "workbench" }
        let workbenchTasks = project.tasks.filter { $0.metadata["source"] == "workbench" }
        let sessionIDs = Set(workbenchMessages.compactMap { workbenchSessionID(from: $0.metadata) })
            .union(workbenchTasks.compactMap { workbenchSessionID(from: $0.metadata) })
            .sorted()
        let workflowsByID = Dictionary(uniqueKeysWithValues: project.workflows.map { ($0.id, $0.name) })
        let agentsByID = Dictionary(uniqueKeysWithValues: project.agents.map { ($0.id, $0) })
        let agentNamesByID = Dictionary(uniqueKeysWithValues: project.agents.map { ($0.id, $0.name) })
        let workbenchThreadLinks = buildWorkbenchThreadLinks(
            messages: workbenchMessages,
            tasks: workbenchTasks,
            agentsByID: agentsByID
        )

        return sessionIDs.map { sessionID in
            let threadMessages = workbenchMessages.filter { workbenchSessionID(from: $0.metadata) == sessionID }
            let threadTasks = workbenchTasks.filter { workbenchSessionID(from: $0.metadata) == sessionID }
            let resolvedWorkflowID = threadMessages.compactMap { workflowIDFromMetadata($0.metadata) }.first
                ?? threadTasks.compactMap { workflowIDFromMetadata($0.metadata) }.first
            let resolvedEntryAgentID = threadMessages.compactMap { entryAgentIDFromMetadata($0.metadata) }.first
                ?? threadTasks.compactMap(\.assignedAgentID).first
            let participantNames = Set(
                threadMessages.flatMap { [$0.fromAgentID, $0.toAgentID] }
                    + threadTasks.compactMap(\.assignedAgentID)
            )
            .compactMap { agentNamesByID[$0] }
            .sorted()
            let taskDates = threadTasks.map { $0.completedAt ?? $0.startedAt ?? $0.createdAt }
            let activeTaskCount = threadTasks.filter { $0.status == .todo || $0.status == .inProgress }.count
            let blockedTaskCount = threadTasks.filter { $0.status == .blocked }.count
            let completedTaskCount = threadTasks.filter { $0.status == .done }.count
            let failedMessageCount = threadMessages.filter { $0.status == .failed || $0.status == .rejected }.count
            let linkedGatewaySessionIDs = workbenchThreadLinks[sessionID]
                .flatMap { link in
                    link.gatewaySessionKey.map { [$0] } ?? []
                } ?? []
            let linkedSessionIDs = Set([sessionID] + linkedGatewaySessionIDs).sorted()
            let semantics = resolveWorkbenchThreadSemantics(
                messages: threadMessages,
                tasks: threadTasks
            )

            return AnalyticsThreadProjectionEntry(
                threadID: sessionID,
                threadType: semantics.type.rawValue,
                mode: semantics.mode.rawValue,
                sessionID: sessionID,
                linkedSessionIDs: linkedSessionIDs,
                workflowID: resolvedWorkflowID,
                workflowName: resolvedWorkflowID.flatMap { workflowsByID[$0] },
                entryAgentName: resolvedEntryAgentID.flatMap { agentNamesByID[$0] },
                participantNames: participantNames,
                status: workbenchThreadStatus(messages: threadMessages, tasks: threadTasks),
                startedAt: (threadMessages.map(\.timestamp) + threadTasks.map(\.createdAt)).min(),
                lastUpdatedAt: (threadMessages.map(\.timestamp) + taskDates).max(),
                messageCount: threadMessages.count,
                taskCount: threadTasks.count,
                pendingApprovalCount: threadMessages.filter { $0.status == .waitingForApproval }.count,
                blockedTaskCount: blockedTaskCount,
                activeTaskCount: activeTaskCount,
                completedTaskCount: completedTaskCount,
                failedMessageCount: failedMessageCount
            )
        }
        .sorted { lhs, rhs in
            if lhs.lastUpdatedAt != rhs.lastUpdatedAt {
                return (lhs.lastUpdatedAt ?? .distantPast) > (rhs.lastUpdatedAt ?? .distantPast)
            }
            return lhs.threadID < rhs.threadID
        }
    }

    private func makeAnalyticsWorkflowHealthProjectionEntries(
        for project: MAProject,
        nodeEntries: [AnalyticsNodeRuntimeProjectionEntry],
        sessionEntries: [AnalyticsSessionProjectionEntry]
    ) -> [AnalyticsWorkflowHealthProjectionEntry] {
        let approvalMessages = project.messages.filter { $0.status == .waitingForApproval }
        let approvalDispatches = runtimeDispatchEnvelopes(from: project.runtimeState)
            .filter { $0.record.status == .waitingApproval }

        return project.workflows.map { workflow in
            let workflowNodeEntries = nodeEntries.filter { $0.workflowID == workflow.id }
            let workflowSessions = sessionEntries.filter { $0.workflowIDs.contains(workflow.id.uuidString) }
            let workflowNodeIDs = Set(workflow.nodes.map(\.id))
            let recentFailureCount = project.executionResults.filter {
                $0.status == .failed && workflowNodeIDs.contains($0.nodeID)
            }.count
            let pendingApprovalCount = approvalMessages.filter {
                workflowIDFromMetadata($0.metadata) == workflow.id
            }.count + approvalDispatches.filter { $0.record.workflowID == workflow.id.uuidString }.count

            return AnalyticsWorkflowHealthProjectionEntry(
                workflowID: workflow.id,
                workflowName: workflow.name,
                nodeCount: workflow.nodes.count,
                edgeCount: workflow.edges.count,
                sessionCount: workflowSessions.count,
                activeNodeCount: workflowNodeEntries.filter {
                    ["queued", "inflight", "waitingApproval"].contains($0.status)
                }.count,
                failedNodeCount: workflowNodeEntries.filter { $0.status == "failed" }.count,
                waitingApprovalNodeCount: workflowNodeEntries.filter { $0.status == "waitingApproval" }.count,
                completedNodeCount: workflowNodeEntries.filter { $0.status == "completed" }.count,
                idleNodeCount: workflowNodeEntries.filter { $0.status == "idle" }.count,
                recentFailureCount: recentFailureCount,
                pendingApprovalCount: pendingApprovalCount,
                lastUpdatedAt: (
                    workflowNodeEntries.compactMap(\.lastUpdatedAt)
                    + workflowSessions.compactMap(\.lastUpdatedAt)
                ).max()
            )
        }
        .sorted { lhs, rhs in
            if lhs.failedNodeCount != rhs.failedNodeCount {
                return lhs.failedNodeCount > rhs.failedNodeCount
            }
            if lhs.waitingApprovalNodeCount != rhs.waitingApprovalNodeCount {
                return lhs.waitingApprovalNodeCount > rhs.waitingApprovalNodeCount
            }
            return (lhs.lastUpdatedAt ?? .distantPast) > (rhs.lastUpdatedAt ?? .distantPast)
        }
    }

    private func makeAnalyticsLiveRunProjectionDocument(
        for project: MAProject,
        sessionEntries: [AnalyticsSessionProjectionEntry],
        workflowHealthEntries: [AnalyticsWorkflowHealthProjectionEntry],
        generatedAt: Date
    ) -> AnalyticsLiveRunProjectionDocument {
        let latestErrorText = (
            project.runtimeState.failedDispatches.compactMap(\.errorMessage)
            + project.executionResults
                .filter { $0.status == .failed }
                .map { truncatedText($0.summaryText, limit: 160) }
        )
        .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })

        let workflowEntries = workflowHealthEntries.map { entry in
            let matchingSessions = sessionEntries.filter { $0.workflowIDs.contains(entry.workflowID.uuidString) }
            return AnalyticsLiveRunWorkflowProjectionEntry(
                workflowID: entry.workflowID,
                workflowName: entry.workflowName,
                sessionCount: matchingSessions.count,
                activeSessionCount: matchingSessions.filter {
                    $0.queuedDispatchCount > 0 || $0.inflightDispatchCount > 0
                }.count,
                activeNodeCount: entry.activeNodeCount,
                failedNodeCount: entry.failedNodeCount,
                waitingApprovalNodeCount: entry.waitingApprovalNodeCount,
                lastUpdatedAt: entry.lastUpdatedAt
            )
        }

        return AnalyticsLiveRunProjectionDocument(
            projectID: project.id,
            generatedAt: generatedAt,
            runtimeSessionID: project.runtimeState.sessionID,
            activeSessionCount: sessionEntries.filter {
                $0.queuedDispatchCount > 0 || $0.inflightDispatchCount > 0
            }.count,
            totalSessionCount: sessionEntries.count,
            queuedDispatchCount: project.runtimeState.dispatchQueue.count,
            inflightDispatchCount: project.runtimeState.inflightDispatches.count,
            failedDispatchCount: project.runtimeState.failedDispatches.count,
            waitingApprovalCount: project.messages.filter { $0.status == .waitingForApproval }.count
                + project.runtimeState.inflightDispatches.filter { $0.status == .waitingApproval }.count,
            latestErrorText: latestErrorText,
            activeWorkflowCount: workflowEntries.filter {
                $0.activeNodeCount > 0 || $0.activeSessionCount > 0 || $0.failedNodeCount > 0
            }.count,
            workflows: workflowEntries
        )
    }

    private func analyticsRelatedDispatchEnvelopes(
        for node: WorkflowNode,
        in dispatches: [RuntimeDispatchEnvelopeDocument]
    ) -> [RuntimeDispatchEnvelopeDocument] {
        dispatches.filter { envelope in
            let record = envelope.record
            return normalizedUUIDValue(record.nodeID) == node.id.uuidString.lowercased()
                || (node.agentID != nil && normalizedUUIDValue(record.targetAgentID) == node.agentID?.uuidString.lowercased())
                || (node.agentID != nil && normalizedUUIDValue(record.sourceAgentID) == node.agentID?.uuidString.lowercased())
        }
    }

    private func analyticsRuntimeStatus(
        for node: WorkflowNode,
        dispatches: [RuntimeDispatchEnvelopeDocument],
        latestReceipt: ExecutionResult?
    ) -> String {
        if dispatches.contains(where: { $0.record.status == .failed || $0.record.status == .aborted || $0.record.status == .expired }) {
            return "failed"
        }
        if dispatches.contains(where: { $0.record.status == .waitingApproval }) {
            return "waitingApproval"
        }
        if dispatches.contains(where: { [.running, .accepted, .dispatched].contains($0.record.status) }) {
            return "inflight"
        }
        if dispatches.contains(where: { [.created, .waitingDependency].contains($0.record.status) }) {
            return "queued"
        }
        if let latestReceipt {
            switch latestReceipt.status {
            case .failed:
                return "failed"
            case .completed:
                return "completed"
            case .running:
                return "inflight"
            case .waiting:
                return "queued"
            case .idle:
                return node.type == .start ? "completed" : "idle"
            }
        }
        return node.type == .start ? "completed" : "idle"
    }

    private func analyticsLatestDetailText(
        receipt: ExecutionResult?,
        dispatches: [RuntimeDispatchEnvelopeDocument]
    ) -> String? {
        if let error = dispatches.compactMap(\.record.errorMessage).last,
           !error.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return truncatedText(error, limit: 160)
        }

        if let receipt {
            if !receipt.summaryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return truncatedText(receipt.summaryText, limit: 160)
            }
            if !receipt.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return truncatedText(receipt.output, limit: 160)
            }
        }

        return dispatches.last.map { truncatedText($0.record.summary, limit: 160) }
    }

    private func analyticsRuntimeStatusRank(_ status: String) -> Int {
        switch status {
        case "failed":
            return 0
        case "waitingApproval":
            return 1
        case "inflight":
            return 2
        case "queued":
            return 3
        case "completed":
            return 4
        default:
            return 5
        }
    }

    private func normalizedUUIDValue(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed.lowercased()
    }

    private func mergeAgents(
        baseAgents: [Agent],
        designAgentsByID: [UUID: Agent],
        workflowOrder: [Workflow]
    ) -> [Agent] {
        let baseAgentsByID = Dictionary(uniqueKeysWithValues: baseAgents.map { ($0.id, $0) })
        let orderedBoundAgentIDs = workflowOrder.flatMap { workflow in
            workflow.nodes.compactMap(\.agentID)
        }

        var merged: [Agent] = []
        var seen: Set<UUID> = []

        for agentID in orderedBoundAgentIDs {
            guard !seen.contains(agentID) else { continue }
            if let agent = designAgentsByID[agentID] ?? baseAgentsByID[agentID] {
                merged.append(agent)
                seen.insert(agentID)
            }
        }

        for agent in baseAgents where !seen.contains(agent.id) {
            merged.append(designAgentsByID[agent.id] ?? agent)
            seen.insert(agent.id)
        }

        for agent in designAgentsByID.values where !seen.contains(agent.id) {
            merged.append(agent)
            seen.insert(agent.id)
        }

        return merged
    }

    private func encodeToData<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        return try encoder.encode(value)
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try JSONDecoder().decode(type, from: data)
    }

    private func validateNodeAgentBindings(workflows: [Workflow], knownAgentIDs: Set<UUID>) throws {
        var nodeIDByAgentID: [UUID: UUID] = [:]

        for workflow in workflows {
            for node in workflow.nodes {
                guard let agentID = node.agentID else { continue }
                guard knownAgentIDs.contains(agentID) else {
                    throw ProjectFileSystemError.missingAgentDefinition(nodeID: node.id, agentID: agentID)
                }
                if let existingNodeID = nodeIDByAgentID[agentID], existingNodeID != node.id {
                    throw ProjectFileSystemError.duplicateNodeAgentBinding(
                        agentID: agentID,
                        firstNodeID: existingNodeID,
                        duplicateNodeID: node.id
                    )
                }
                nodeIDByAgentID[agentID] = node.id
            }
        }
    }

    private func removeUnexpectedEntries(in directoryURL: URL, keeping validEntryNames: Set<String>) throws {
        let contents = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        for item in contents where !validEntryNames.contains(item.lastPathComponent) {
            try? fileManager.removeItem(at: item)
        }
    }
}
