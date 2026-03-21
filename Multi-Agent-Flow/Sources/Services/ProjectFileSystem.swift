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

private struct WorkbenchThreadDocument: Codable {
    var threadID: String
    var sessionID: String
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
    var storageDirectoryName: String
    var generatedAt: Date
    var workflowIDs: [String]
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
    var storageDirectoryName: String
    var eventCount: Int
    var dispatchCount: Int
    var receiptCount: Int
    var lastUpdatedAt: Date?
    var isProjectRuntimeSession: Bool
}

struct ProjectFileSystem {
    static let shared = ProjectFileSystem()

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

    func analyticsRootDirectory(for projectID: UUID, under appSupportRootDirectory: URL) -> URL {
        managedProjectRootDirectory(for: projectID, under: appSupportRootDirectory)
            .appendingPathComponent("analytics", isDirectory: true)
    }

    func analyticsDatabaseURL(for projectID: UUID, under appSupportRootDirectory: URL) -> URL {
        analyticsRootDirectory(for: projectID, under: appSupportRootDirectory)
            .appendingPathComponent("analytics.sqlite", isDirectory: false)
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
        let workbenchMessages = messages.filter { $0.metadata["channel"] == "workbench" }
        let workbenchTasks = project.tasks.filter { $0.metadata["source"] == "workbench" }

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

            let threadDocument = WorkbenchThreadDocument(
                threadID: sessionID,
                sessionID: sessionID,
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
            try writeNDJSON(threadMessages, to: threadRootURL.appendingPathComponent("dialog.ndjson", isDirectory: false))
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

        let allDispatches = runtimeDispatchEnvelopes(from: project.runtimeState)
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

            let workflowIDs = Set(
                sessionDispatches.compactMap(\.record.workflowID)
                    + sessionEvents.compactMap(\.workflowId)
                    + project.messages
                        .filter { workbenchSessionID(from: $0.metadata) == sessionID }
                        .compactMap { workflowIDFromMetadata($0.metadata)?.uuidString }
                    + project.tasks
                        .filter { workbenchSessionID(from: $0.metadata) == sessionID }
                        .compactMap { workflowIDFromMetadata($0.metadata)?.uuidString }
            )
            .sorted()

            let sessionDocument = RuntimeSessionDocument(
                sessionID: sessionID,
                storageDirectoryName: storageDirectoryName,
                generatedAt: Date(),
                workflowIDs: workflowIDs,
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
        try agent.soulMD.write(
            to: workspaceRootURL.appendingPathComponent("SOUL.md", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
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
            let resolvedEntryAgentID = sessionMessages.compactMap { entryAgentIDFromMetadata($0.metadata) }.first
                ?? sessionTasks.compactMap(\.assignedAgentID).first
            let updatedAt = (sessionMessages.map(\.timestamp)
                + sessionTasks.map { $0.completedAt ?? $0.startedAt ?? $0.createdAt }).max() ?? project.updatedAt

            return ThreadIndexEntryDocument(
                threadID: sessionID,
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
            let lastUpdatedAt = (
                sessionDispatches.map(\.record.updatedAt)
                + sessionEvents.map(\.timestamp)
                + sessionReceipts.compactMap { $0.completedAt ?? $0.startedAt }
            ).max()

            return RuntimeSessionIndexEntryDocument(
                sessionID: sessionID,
                storageDirectoryName: safeStorageName(for: sessionID),
                eventCount: sessionEvents.count,
                dispatchCount: sessionDispatches.count,
                receiptCount: sessionReceipts.count,
                lastUpdatedAt: lastUpdatedAt,
                isProjectRuntimeSession: project.runtimeState.sessionID == sessionID
            )
        }
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
