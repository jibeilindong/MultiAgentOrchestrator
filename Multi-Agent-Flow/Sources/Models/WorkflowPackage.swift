import Foundation

struct WorkflowPackageManifest: Codable, Hashable {
    struct Source: Codable, Hashable {
        var app: String
        var projectName: String
        var workflowName: String
    }

    struct Includes: Codable, Hashable {
        var permissions: Bool
        var nodeAgentSnapshots: Bool
        var fullWorkspaceContents: Bool
        var subflows: Bool
    }

    struct WorkspacePolicy: Codable, Hashable {
        var mode: String
        var excludeJunkFiles: Bool
        var excludedNames: [String]
    }

    struct ImportPolicy: Codable, Hashable {
        var agentIdentity: String
        var deduplicateAgents: Bool
        var reuseExistingAgents: Bool
    }

    var format: String
    var version: String
    var packageType: String
    var exportedAt: Date
    var source: Source
    var entryWorkflowID: UUID
    var workflowIDs: [UUID]
    var includes: Includes
    var workspacePolicy: WorkspacePolicy
    var importPolicy: ImportPolicy
}

struct WorkflowPackagePermissionsDocument: Codable, Hashable {
    var permissions: [WorkflowPackagePermissionRecord]
}

struct WorkflowPackagePermissionRecord: Codable, Hashable, Identifiable {
    let id: UUID
    var fromNodeID: UUID
    var toNodeID: UUID
    var permissionType: PermissionType

    init(
        id: UUID = UUID(),
        fromNodeID: UUID,
        toNodeID: UUID,
        permissionType: PermissionType
    ) {
        self.id = id
        self.fromNodeID = fromNodeID
        self.toNodeID = toNodeID
        self.permissionType = permissionType
    }
}

struct WorkflowPackageWorkflowDocument: Codable, Hashable {
    var id: UUID
    var name: String
    var parentNodeID: UUID?
    var fallbackRoutingPolicy: WorkflowFallbackRoutingPolicy
    var launchTestCases: [WorkflowLaunchTestCase]
    var inputSchema: [SubflowParameter]
    var outputSchema: [SubflowParameter]
    var nodeIDs: [UUID]
    var edgeIDs: [UUID]
    var boundaryIDs: [UUID]
}

struct WorkflowPackageNodeDocument: Codable, Hashable {
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

struct WorkflowPackageAgentDocument: Codable, Hashable {
    var id: UUID
    var nodeID: UUID
    var name: String
    var identity: String
    var description: String
    var capabilities: [String]
    var colorHex: String?
}

struct WorkflowPackageWorkspaceManifest: Codable, Hashable {
    var nodeID: UUID
    var agentID: UUID
    var root: String
    var mode: String
    var files: [WorkflowPackageWorkspaceFileRecord]
}

struct WorkflowPackageWorkspaceFileRecord: Codable, Hashable, Identifiable {
    var id: String { relativePath }
    var relativePath: String
    var size: Int
    var sha256: String
}

struct WorkflowPackagePreview: Identifiable, Hashable {
    let id: UUID
    let archiveURL: URL
    let extractedRootURL: URL
    let manifest: WorkflowPackageManifest
    let rootWorkflowName: String
    let workflowCount: Int
    let nodeCount: Int
    let edgeCount: Int
    let boundaryCount: Int
    let nodeAgentCount: Int
    let workspaceFileCount: Int
    let workspaceTotalBytes: Int64

    init(
        id: UUID = UUID(),
        archiveURL: URL,
        extractedRootURL: URL,
        manifest: WorkflowPackageManifest,
        rootWorkflowName: String,
        workflowCount: Int,
        nodeCount: Int,
        edgeCount: Int,
        boundaryCount: Int,
        nodeAgentCount: Int,
        workspaceFileCount: Int,
        workspaceTotalBytes: Int64
    ) {
        self.id = id
        self.archiveURL = archiveURL
        self.extractedRootURL = extractedRootURL
        self.manifest = manifest
        self.rootWorkflowName = rootWorkflowName
        self.workflowCount = workflowCount
        self.nodeCount = nodeCount
        self.edgeCount = edgeCount
        self.boundaryCount = boundaryCount
        self.nodeAgentCount = nodeAgentCount
        self.workspaceFileCount = workspaceFileCount
        self.workspaceTotalBytes = workspaceTotalBytes
    }
}

struct WorkflowPackageImportResult {
    var project: MAProject
    var importedRootWorkflowID: UUID
    var importedWorkflowIDs: [UUID]
}
