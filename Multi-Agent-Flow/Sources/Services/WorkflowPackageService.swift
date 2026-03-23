import Foundation
import CryptoKit

enum WorkflowPackageError: LocalizedError {
    case workflowNotFound
    case packageRootNotFound
    case invalidManifest
    case missingWorkflowDocument(UUID)
    case missingNodeDocument(UUID, workflowID: UUID)
    case missingAgentDocument(UUID, nodeID: UUID)
    case missingEdgeDocument(UUID, workflowID: UUID)
    case missingBoundaryDocument(UUID, workflowID: UUID)
    case invalidPermissionNodeReference(UUID)
    case archiveFailed(String)

    var errorDescription: String? {
        switch self {
        case .workflowNotFound:
            return "未找到需要导出的 workflow。"
        case .packageRootNotFound:
            return "导入包中未找到 manifest.json。"
        case .invalidManifest:
            return "工作流设计包 manifest 无效。"
        case .missingWorkflowDocument(let workflowID):
            return "缺少 workflow 文档：\(workflowID.uuidString)"
        case .missingNodeDocument(let nodeID, let workflowID):
            return "缺少 node 文档：workflow \(workflowID.uuidString) / node \(nodeID.uuidString)"
        case .missingAgentDocument(let agentID, let nodeID):
            return "缺少 agent 文档：agent \(agentID.uuidString) / node \(nodeID.uuidString)"
        case .missingEdgeDocument(let edgeID, let workflowID):
            return "缺少 edge 文档：workflow \(workflowID.uuidString) / edge \(edgeID.uuidString)"
        case .missingBoundaryDocument(let boundaryID, let workflowID):
            return "缺少 boundary 文档：workflow \(workflowID.uuidString) / boundary \(boundaryID.uuidString)"
        case .invalidPermissionNodeReference(let nodeID):
            return "权限文档引用了不存在的 node：\(nodeID.uuidString)"
        case .archiveFailed(let detail):
            return detail
        }
    }
}

final class WorkflowPackageService {
    private struct LoadedWorkflowPackage {
        var manifest: WorkflowPackageManifest
        var permissions: [WorkflowPackagePermissionRecord]
        var workflows: [UUID: WorkflowPackageWorkflowDocument]
        var nodesByWorkflowID: [UUID: [WorkflowPackageNodeDocument]]
        var agentsByNodeID: [UUID: WorkflowPackageAgentDocument]
        var edgesByWorkflowID: [UUID: [WorkflowEdge]]
        var boundariesByWorkflowID: [UUID: [WorkflowBoundary]]
        var workspaceRootByNodeID: [UUID: URL]
        var workspaceManifestByNodeID: [UUID: WorkflowPackageWorkspaceManifest]
    }

    private struct WorkspaceCopyPlan {
        var sourceURL: URL
        var destinationURL: URL
    }

    private let fileManager: FileManager
    private let projectFileSystem: ProjectFileSystem
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        fileManager: FileManager = .default,
        projectFileSystem: ProjectFileSystem = .shared
    ) {
        self.fileManager = fileManager
        self.projectFileSystem = projectFileSystem
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func exportPackage(
        rootWorkflowID: UUID,
        from project: MAProject,
        under appSupportRootDirectory: URL,
        to destinationURL: URL
    ) throws {
        guard let rootWorkflow = project.workflows.first(where: { $0.id == rootWorkflowID }) else {
            throw WorkflowPackageError.workflowNotFound
        }

        let workflows = collectExportWorkflows(rootWorkflowID: rootWorkflowID, in: project)
        let stagingParent = fileManager.temporaryDirectory
            .appendingPathComponent("maoworkflow-export-\(UUID().uuidString)", isDirectory: true)
        let packageRootURL = stagingParent.appendingPathComponent(safeDirectoryName(rootWorkflow.name), isDirectory: true)

        try fileManager.createDirectory(at: packageRootURL, withIntermediateDirectories: true)

        defer {
            try? fileManager.removeItem(at: stagingParent)
        }

        let nodeToAgentID = Dictionary(uniqueKeysWithValues: workflows.flatMap { workflow in
            workflow.nodes.compactMap { node -> (UUID, UUID)? in
                guard let agentID = node.agentID else { return nil }
                return (node.id, agentID)
            }
        })
        let agentToNodeID = Dictionary(uniqueKeysWithValues: nodeToAgentID.map { ($0.value, $0.key) })
        let agentsByID = Dictionary(uniqueKeysWithValues: project.agents.map { ($0.id, $0) })

        let manifest = WorkflowPackageManifest(
            format: "multi-agent-flow.workflow-package",
            version: "2.0",
            packageType: "workflow_design_bundle",
            exportedAt: Date(),
            source: WorkflowPackageManifest.Source(
                app: "Multi-Agent-Flow",
                projectName: project.name,
                workflowName: rootWorkflow.name
            ),
            entryWorkflowID: rootWorkflow.id,
            workflowIDs: workflows.map(\.id),
            includes: WorkflowPackageManifest.Includes(
                permissions: true,
                nodeAgentSnapshots: true,
                fullWorkspaceContents: true,
                subflows: true
            ),
            workspacePolicy: WorkflowPackageManifest.WorkspacePolicy(
                mode: "preserve_recursive_copy",
                excludeJunkFiles: true,
                excludedNames: [".DS_Store"]
            ),
            importPolicy: WorkflowPackageManifest.ImportPolicy(
                agentIdentity: "node_bound_snapshot",
                deduplicateAgents: false,
                reuseExistingAgents: false
            )
        )

        try encode(manifest, to: packageRootURL.appendingPathComponent("manifest.json", isDirectory: false))

        let permissionRecords = project.permissions.compactMap { permission -> WorkflowPackagePermissionRecord? in
            guard let fromNodeID = agentToNodeID[permission.fromAgentID],
                  let toNodeID = agentToNodeID[permission.toAgentID] else {
                return nil
            }

            return WorkflowPackagePermissionRecord(
                id: permission.id,
                fromNodeID: fromNodeID,
                toNodeID: toNodeID,
                permissionType: permission.permissionType
            )
        }

        try encode(
            WorkflowPackagePermissionsDocument(permissions: permissionRecords),
            to: packageRootURL.appendingPathComponent("permissions.json", isDirectory: false)
        )

        let workflowsRootURL = packageRootURL.appendingPathComponent("workflows", isDirectory: true)
        try fileManager.createDirectory(at: workflowsRootURL, withIntermediateDirectories: true)

        for workflow in workflows {
            let workflowRootURL = workflowsRootURL.appendingPathComponent(workflow.id.uuidString, isDirectory: true)
            let nodesRootURL = workflowRootURL.appendingPathComponent("nodes", isDirectory: true)
            let edgesRootURL = workflowRootURL.appendingPathComponent("edges", isDirectory: true)
            let boundariesRootURL = workflowRootURL.appendingPathComponent("boundaries", isDirectory: true)
            for directory in [workflowRootURL, nodesRootURL, edgesRootURL, boundariesRootURL] {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            }

            try encode(
                WorkflowPackageWorkflowDocument(
                    id: workflow.id,
                    name: workflow.name,
                    parentNodeID: workflow.parentNodeID,
                    fallbackRoutingPolicy: workflow.fallbackRoutingPolicy,
                    launchTestCases: workflow.launchTestCases,
                    inputSchema: workflow.inputSchema,
                    outputSchema: workflow.outputSchema,
                    nodeIDs: workflow.nodes.map(\.id),
                    edgeIDs: workflow.edges.map(\.id),
                    boundaryIDs: workflow.boundaries.map(\.id)
                ),
                to: workflowRootURL.appendingPathComponent("workflow.json", isDirectory: false)
            )

            for node in workflow.nodes {
                let nodeRootURL = nodesRootURL.appendingPathComponent(node.id.uuidString, isDirectory: true)
                let nodeOpenClawRootURL = nodeRootURL.appendingPathComponent("openclaw", isDirectory: true)
                let nodeWorkspaceRootURL = nodeOpenClawRootURL.appendingPathComponent("workspace", isDirectory: true)
                try fileManager.createDirectory(at: nodeWorkspaceRootURL, withIntermediateDirectories: true)

                try encode(
                    WorkflowPackageNodeDocument(
                        id: node.id,
                        workflowID: workflow.id,
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
                    ),
                    to: nodeRootURL.appendingPathComponent("node.json", isDirectory: false)
                )

                if let agentID = node.agentID, let agent = agentsByID[agentID] {
                    try encode(
                        WorkflowPackageAgentDocument(
                            id: agent.id,
                            nodeID: node.id,
                            name: agent.name,
                            identity: agent.identity,
                            description: agent.description,
                            capabilities: agent.capabilities,
                            colorHex: agent.colorHex
                        ),
                        to: nodeRootURL.appendingPathComponent("agent.json", isDirectory: false)
                    )

                    let workspaceSourceURL = projectFileSystem.nodeOpenClawWorkspaceDirectory(
                        for: node.id,
                        workflowID: workflow.id,
                        projectID: project.id,
                        under: appSupportRootDirectory
                    )

                    if fileManager.fileExists(atPath: workspaceSourceURL.path) {
                        try copyDirectory(from: workspaceSourceURL, to: nodeWorkspaceRootURL)
                    }

                    let synthesizedSoulURL = nodeWorkspaceRootURL.appendingPathComponent("SOUL.md", isDirectory: false)
                    if !fileManager.fileExists(atPath: synthesizedSoulURL.path) {
                        try agent.soulMD.write(to: synthesizedSoulURL, atomically: true, encoding: .utf8)
                    }

                    try removeJunkFiles(in: nodeWorkspaceRootURL)

                    let workspaceManifest = try buildWorkspaceManifest(
                        nodeID: node.id,
                        agentID: agent.id,
                        workspaceRootURL: nodeWorkspaceRootURL
                    )
                    try encode(
                        workspaceManifest,
                        to: nodeOpenClawRootURL.appendingPathComponent("workspace.manifest.json", isDirectory: false)
                    )
                }
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
        }

        try archiveDirectory(packageRootURL, to: destinationURL)
    }

    func preflightImportPackage(at archiveURL: URL) throws -> WorkflowPackagePreview {
        let extractedRootURL = try extractArchive(at: archiveURL)
        let packageRootURL = try locatePackageRoot(in: extractedRootURL)
        let package = try loadPackage(from: packageRootURL)
        let rootWorkflowName = package.workflows[package.manifest.entryWorkflowID]?.name ?? package.manifest.source.workflowName
        let nodeCount = package.nodesByWorkflowID.values.reduce(0) { $0 + $1.count }
        let edgeCount = package.edgesByWorkflowID.values.reduce(0) { $0 + $1.count }
        let boundaryCount = package.boundariesByWorkflowID.values.reduce(0) { $0 + $1.count }
        let workspaceFiles = package.workspaceManifestByNodeID.values.flatMap(\.files)
        let workspaceTotalBytes = workspaceFiles.reduce(Int64(0)) { partial, record in
            partial + Int64(record.size)
        }

        return WorkflowPackagePreview(
            archiveURL: archiveURL,
            extractedRootURL: extractedRootURL,
            manifest: package.manifest,
            rootWorkflowName: rootWorkflowName,
            workflowCount: package.workflows.count,
            nodeCount: nodeCount,
            edgeCount: edgeCount,
            boundaryCount: boundaryCount,
            nodeAgentCount: package.agentsByNodeID.count,
            workspaceFileCount: workspaceFiles.count,
            workspaceTotalBytes: workspaceTotalBytes
        )
    }

    func cleanupPreview(_ preview: WorkflowPackagePreview) {
        try? fileManager.removeItem(at: preview.extractedRootURL)
    }

    func importPackage(
        from preview: WorkflowPackagePreview,
        into project: MAProject,
        under appSupportRootDirectory: URL,
        rootWorkflowNameOverride: String?
    ) throws -> WorkflowPackageImportResult {
        let packageRootURL = try locatePackageRoot(in: preview.extractedRootURL)
        let package = try loadPackage(from: packageRootURL)

        var updatedProject = project
        var existingWorkflowNames = Set(updatedProject.workflows.map(\.name))
        var importedWorkflowsByOldID: [UUID: Workflow] = [:]
        var importedWorkflowIDByOldID: [UUID: UUID] = [:]
        var workflowOrder: [UUID] = []

        for workflowID in package.manifest.workflowIDs {
            guard let document = package.workflows[workflowID] else {
                throw WorkflowPackageError.missingWorkflowDocument(workflowID)
            }

            let requestedName: String
            if workflowID == package.manifest.entryWorkflowID,
               let rootWorkflowNameOverride,
               !rootWorkflowNameOverride.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                requestedName = rootWorkflowNameOverride.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                requestedName = document.name
            }

            let resolvedName = uniqueWorkflowName(requestedName, existingNames: existingWorkflowNames)
            existingWorkflowNames.insert(resolvedName)

            var workflow = Workflow(name: resolvedName)
            workflow.fallbackRoutingPolicy = document.fallbackRoutingPolicy
            workflow.launchTestCases = document.launchTestCases.map { testCase in
                WorkflowLaunchTestCase(
                    name: testCase.name,
                    prompt: testCase.prompt,
                    requiredAgentNames: testCase.requiredAgentNames,
                    forbiddenAgentNames: testCase.forbiddenAgentNames,
                    expectedRoutingActions: testCase.expectedRoutingActions,
                    expectedOutputTypes: testCase.expectedOutputTypes,
                    maxSteps: testCase.maxSteps,
                    notes: testCase.notes
                )
            }
            workflow.inputSchema = document.inputSchema
            workflow.outputSchema = document.outputSchema
            importedWorkflowsByOldID[workflowID] = workflow
            importedWorkflowIDByOldID[workflowID] = workflow.id
            workflowOrder.append(workflowID)
        }

        var nodeIDMap: [UUID: UUID] = [:]
        var nodeToAgentIDMap: [UUID: UUID] = [:]
        var importedNodeDocumentsByOldNodeID: [UUID: WorkflowPackageNodeDocument] = [:]
        var workspaceCopyPlans: [WorkspaceCopyPlan] = []

        for workflowID in workflowOrder {
            guard var workflow = importedWorkflowsByOldID[workflowID],
                  let workflowDocument = package.workflows[workflowID] else {
                throw WorkflowPackageError.missingWorkflowDocument(workflowID)
            }

            let nodeDocuments = package.nodesByWorkflowID[workflowID] ?? []
            var importedNodes: [WorkflowNode] = []
            importedNodes.reserveCapacity(nodeDocuments.count)

            for nodeDocument in nodeDocuments {
                var node = WorkflowNode(type: nodeDocument.type)
                node.position = nodeDocument.position
                node.title = nodeDocument.title
                node.displayColorHex = nodeDocument.displayColorHex
                node.conditionExpression = nodeDocument.conditionExpression
                node.loopEnabled = nodeDocument.loopEnabled
                node.maxIterations = nodeDocument.maxIterations
                node.nestingLevel = nodeDocument.nestingLevel
                node.inputParameters = nodeDocument.inputParameters
                node.outputParameters = nodeDocument.outputParameters
                nodeIDMap[nodeDocument.id] = node.id
                importedNodeDocumentsByOldNodeID[nodeDocument.id] = nodeDocument

                if let oldAgentID = nodeDocument.agentID {
                    guard let agentDocument = package.agentsByNodeID[nodeDocument.id] else {
                        throw WorkflowPackageError.missingAgentDocument(oldAgentID, nodeID: nodeDocument.id)
                    }

                    let workspaceRootURL = package.workspaceRootByNodeID[nodeDocument.id]
                    let soulMD = workspaceRootURL
                        .flatMap { try? String(contentsOf: $0.appendingPathComponent("SOUL.md", isDirectory: false), encoding: .utf8) }
                        ?? "# \(agentDocument.name)\n"

                    var agent = Agent(name: agentDocument.name)
                    agent.name = Agent.normalizedName(
                        requestedName: agentDocument.name,
                        existingAgents: updatedProject.agents
                    )
                    agent.identity = agentDocument.identity
                    agent.description = agentDocument.description
                    agent.capabilities = agentDocument.capabilities
                    agent.colorHex = agentDocument.colorHex
                    agent.soulMD = soulMD
                    agent.openClawDefinition.agentIdentifier = Agent.normalizedRuntimeIdentifier(
                        requestedIdentifier: agentDocument.name,
                        fallbackName: agent.name,
                        existingAgents: updatedProject.agents
                    )
                    updatedProject.agents.append(agent)

                    node.agentID = agent.id
                    node.title = agent.name
                    nodeToAgentIDMap[nodeDocument.id] = agent.id

                    if let workspaceRootURL {
                        let destinationURL = projectFileSystem.nodeOpenClawWorkspaceDirectory(
                            for: node.id,
                            workflowID: workflow.id,
                            projectID: updatedProject.id,
                            under: appSupportRootDirectory
                        )
                        workspaceCopyPlans.append(
                            WorkspaceCopyPlan(
                                sourceURL: workspaceRootURL,
                                destinationURL: destinationURL
                            )
                        )
                    }
                }

                importedNodes.append(node)
            }

            let importedEdges = try workflowDocument.edgeIDs.map { edgeID in
                guard let edge = package.edgesByWorkflowID[workflowID]?.first(where: { $0.id == edgeID }) else {
                    throw WorkflowPackageError.missingEdgeDocument(edgeID, workflowID: workflowID)
                }
                guard let fromNodeID = nodeIDMap[edge.fromNodeID],
                      let toNodeID = nodeIDMap[edge.toNodeID] else {
                    throw WorkflowPackageError.invalidManifest
                }
                var importedEdge = WorkflowEdge(from: fromNodeID, to: toNodeID)
                importedEdge.label = edge.label
                importedEdge.displayColorHex = edge.displayColorHex
                importedEdge.conditionExpression = edge.conditionExpression
                importedEdge.requiresApproval = edge.requiresApproval
                importedEdge.isBidirectional = edge.isBidirectional
                importedEdge.dataMapping = edge.dataMapping
                return importedEdge
            }

            let importedBoundaries = try workflowDocument.boundaryIDs.map { boundaryID in
                guard let boundary = package.boundariesByWorkflowID[workflowID]?.first(where: { $0.id == boundaryID }) else {
                    throw WorkflowPackageError.missingBoundaryDocument(boundaryID, workflowID: workflowID)
                }
                let remappedMembers = boundary.memberNodeIDs.compactMap { nodeIDMap[$0] }
                return WorkflowBoundary(
                    title: boundary.title,
                    rect: boundary.rect,
                    memberNodeIDs: remappedMembers
                )
            }

            workflow.nodes = importedNodes
            workflow.edges = importedEdges
            workflow.boundaries = importedBoundaries
            importedWorkflowsByOldID[workflowID] = workflow
        }

        for workflowID in workflowOrder {
            guard var workflow = importedWorkflowsByOldID[workflowID],
                  let workflowDocument = package.workflows[workflowID] else {
                throw WorkflowPackageError.missingWorkflowDocument(workflowID)
            }

            workflow.parentNodeID = workflowDocument.parentNodeID.flatMap { nodeIDMap[$0] }
            workflow.nodes = workflow.nodes.map { node in
                var updatedNode = node
                if let originalNodeID = nodeIDMap.first(where: { $0.value == node.id })?.key,
                   let nodeDocument = importedNodeDocumentsByOldNodeID[originalNodeID] {
                    updatedNode.subflowID = nodeDocument.subflowID.flatMap { importedWorkflowIDByOldID[$0] }
                }
                return updatedNode
            }
            importedWorkflowsByOldID[workflowID] = workflow
        }

        let importedWorkflows = workflowOrder.compactMap { importedWorkflowsByOldID[$0] }
        updatedProject.workflows.append(contentsOf: importedWorkflows)

        for permission in package.permissions {
            guard let fromAgentID = nodeToAgentIDMap[permission.fromNodeID] else {
                throw WorkflowPackageError.invalidPermissionNodeReference(permission.fromNodeID)
            }
            guard let toAgentID = nodeToAgentIDMap[permission.toNodeID] else {
                throw WorkflowPackageError.invalidPermissionNodeReference(permission.toNodeID)
            }

            updatedProject.permissions.append(
                Permission(
                    fromAgentID: fromAgentID,
                    toAgentID: toAgentID,
                    permissionType: permission.permissionType
                )
            )
        }

        try copyImportedWorkspaceTrees(workspaceCopyPlans)
        updatedProject.updatedAt = Date()

        guard let importedRootWorkflowID = importedWorkflowIDByOldID[package.manifest.entryWorkflowID] else {
            throw WorkflowPackageError.missingWorkflowDocument(package.manifest.entryWorkflowID)
        }
        return WorkflowPackageImportResult(
            project: updatedProject,
            importedRootWorkflowID: importedRootWorkflowID,
            importedWorkflowIDs: importedWorkflows.map(\.id)
        )
    }

    private func loadPackage(from packageRootURL: URL) throws -> LoadedWorkflowPackage {
        let manifestURL = packageRootURL.appendingPathComponent("manifest.json", isDirectory: false)
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            throw WorkflowPackageError.packageRootNotFound
        }

        let manifest = try decode(WorkflowPackageManifest.self, from: manifestURL)
        guard manifest.format == "multi-agent-flow.workflow-package" else {
            throw WorkflowPackageError.invalidManifest
        }

        let permissionsURL = packageRootURL.appendingPathComponent("permissions.json", isDirectory: false)
        let permissionDocument = fileManager.fileExists(atPath: permissionsURL.path)
            ? try decode(WorkflowPackagePermissionsDocument.self, from: permissionsURL)
            : WorkflowPackagePermissionsDocument(permissions: [])

        let workflowsRootURL = packageRootURL.appendingPathComponent("workflows", isDirectory: true)
        var workflowDocuments: [UUID: WorkflowPackageWorkflowDocument] = [:]
        var nodeDocumentsByWorkflowID: [UUID: [WorkflowPackageNodeDocument]] = [:]
        var edgeDocumentsByWorkflowID: [UUID: [WorkflowEdge]] = [:]
        var boundaryDocumentsByWorkflowID: [UUID: [WorkflowBoundary]] = [:]
        var agentDocumentsByNodeID: [UUID: WorkflowPackageAgentDocument] = [:]
        var workspaceRootByNodeID: [UUID: URL] = [:]
        var workspaceManifestByNodeID: [UUID: WorkflowPackageWorkspaceManifest] = [:]

        for workflowID in manifest.workflowIDs {
            let workflowRootURL = workflowsRootURL.appendingPathComponent(workflowID.uuidString, isDirectory: true)
            let workflowDocumentURL = workflowRootURL.appendingPathComponent("workflow.json", isDirectory: false)
            guard fileManager.fileExists(atPath: workflowDocumentURL.path) else {
                throw WorkflowPackageError.missingWorkflowDocument(workflowID)
            }

            let workflowDocument = try decode(WorkflowPackageWorkflowDocument.self, from: workflowDocumentURL)
            workflowDocuments[workflowID] = workflowDocument

            let nodesRootURL = workflowRootURL.appendingPathComponent("nodes", isDirectory: true)
            let edgesRootURL = workflowRootURL.appendingPathComponent("edges", isDirectory: true)
            let boundariesRootURL = workflowRootURL.appendingPathComponent("boundaries", isDirectory: true)

            nodeDocumentsByWorkflowID[workflowID] = try workflowDocument.nodeIDs.map { nodeID in
                let nodeRootURL = nodesRootURL.appendingPathComponent(nodeID.uuidString, isDirectory: true)
                let nodeURL = nodeRootURL.appendingPathComponent("node.json", isDirectory: false)
                guard fileManager.fileExists(atPath: nodeURL.path) else {
                    throw WorkflowPackageError.missingNodeDocument(nodeID, workflowID: workflowID)
                }
                let nodeDocument = try decode(WorkflowPackageNodeDocument.self, from: nodeURL)
                if nodeDocument.agentID != nil {
                    let agentURL = nodeRootURL.appendingPathComponent("agent.json", isDirectory: false)
                    guard fileManager.fileExists(atPath: agentURL.path) else {
                        throw WorkflowPackageError.missingAgentDocument(nodeDocument.agentID ?? UUID(), nodeID: nodeDocument.id)
                    }
                    let agentDocument = try decode(WorkflowPackageAgentDocument.self, from: agentURL)
                    agentDocumentsByNodeID[nodeDocument.id] = agentDocument

                    let openClawRootURL = nodeRootURL.appendingPathComponent("openclaw", isDirectory: true)
                    let workspaceManifestURL = openClawRootURL.appendingPathComponent("workspace.manifest.json", isDirectory: false)
                    if fileManager.fileExists(atPath: workspaceManifestURL.path) {
                        workspaceManifestByNodeID[nodeDocument.id] = try decode(WorkflowPackageWorkspaceManifest.self, from: workspaceManifestURL)
                    }
                    let workspaceRootURL = openClawRootURL.appendingPathComponent("workspace", isDirectory: true)
                    if fileManager.fileExists(atPath: workspaceRootURL.path) {
                        workspaceRootByNodeID[nodeDocument.id] = workspaceRootURL
                    }
                }
                return nodeDocument
            }

            edgeDocumentsByWorkflowID[workflowID] = try workflowDocument.edgeIDs.map { edgeID in
                let edgeURL = edgesRootURL.appendingPathComponent("\(edgeID.uuidString).json", isDirectory: false)
                guard fileManager.fileExists(atPath: edgeURL.path) else {
                    throw WorkflowPackageError.missingEdgeDocument(edgeID, workflowID: workflowID)
                }
                return try decode(WorkflowEdge.self, from: edgeURL)
            }

            boundaryDocumentsByWorkflowID[workflowID] = try workflowDocument.boundaryIDs.map { boundaryID in
                let boundaryURL = boundariesRootURL.appendingPathComponent("\(boundaryID.uuidString).json", isDirectory: false)
                guard fileManager.fileExists(atPath: boundaryURL.path) else {
                    throw WorkflowPackageError.missingBoundaryDocument(boundaryID, workflowID: workflowID)
                }
                return try decode(WorkflowBoundary.self, from: boundaryURL)
            }
        }

        return LoadedWorkflowPackage(
            manifest: manifest,
            permissions: permissionDocument.permissions,
            workflows: workflowDocuments,
            nodesByWorkflowID: nodeDocumentsByWorkflowID,
            agentsByNodeID: agentDocumentsByNodeID,
            edgesByWorkflowID: edgeDocumentsByWorkflowID,
            boundariesByWorkflowID: boundaryDocumentsByWorkflowID,
            workspaceRootByNodeID: workspaceRootByNodeID,
            workspaceManifestByNodeID: workspaceManifestByNodeID
        )
    }

    private func collectExportWorkflows(rootWorkflowID: UUID, in project: MAProject) -> [Workflow] {
        let workflowsByID = Dictionary(uniqueKeysWithValues: project.workflows.map { ($0.id, $0) })
        var ordered: [Workflow] = []
        var visited = Set<UUID>()

        func visit(_ workflowID: UUID) {
            guard visited.insert(workflowID).inserted,
                  let workflow = workflowsByID[workflowID] else {
                return
            }

            ordered.append(workflow)
            for subflowID in workflow.nodes.compactMap(\.subflowID) {
                visit(subflowID)
            }
        }

        visit(rootWorkflowID)
        return ordered
    }

    private func copyImportedWorkspaceTrees(_ plans: [WorkspaceCopyPlan]) throws {
        for plan in plans {
            try copyDirectory(from: plan.sourceURL, to: plan.destinationURL)
        }
    }

    private func buildWorkspaceManifest(
        nodeID: UUID,
        agentID: UUID,
        workspaceRootURL: URL
    ) throws -> WorkflowPackageWorkspaceManifest {
        let fileURLs = try recursiveFileURLs(in: workspaceRootURL)
        let fileRecords = try fileURLs.map { fileURL in
            let data = try Data(contentsOf: fileURL)
            let relativePath = fileURL.path.replacingOccurrences(
                of: workspaceRootURL.path + "/",
                with: ""
            )
            return WorkflowPackageWorkspaceFileRecord(
                relativePath: relativePath,
                size: data.count,
                sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            )
        }

        return WorkflowPackageWorkspaceManifest(
            nodeID: nodeID,
            agentID: agentID,
            root: "workspace",
            mode: "full_recursive_copy",
            files: fileRecords.sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
        )
    }

    private func recursiveFileURLs(in rootURL: URL) throws -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: []
        ) else {
            return []
        }

        var fileURLs: [URL] = []
        for case let fileURL as URL in enumerator {
            if fileURL.lastPathComponent == ".DS_Store" {
                continue
            }
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            if values.isRegularFile == true {
                fileURLs.append(fileURL)
            }
        }
        return fileURLs
    }

    private func archiveDirectory(_ sourceURL: URL, to destinationURL: URL) throws {
        try? fileManager.removeItem(at: destinationURL)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", sourceURL.path, destinationURL.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw WorkflowPackageError.archiveFailed("工作流设计包打包失败。")
        }
    }

    private func extractArchive(at archiveURL: URL) throws -> URL {
        let extractedRootURL = fileManager.temporaryDirectory
            .appendingPathComponent("maoworkflow-import-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: extractedRootURL, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", archiveURL.path, extractedRootURL.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw WorkflowPackageError.archiveFailed("工作流设计包解包失败。")
        }
        return extractedRootURL
    }

    private func locatePackageRoot(in extractedRootURL: URL) throws -> URL {
        if fileManager.fileExists(atPath: extractedRootURL.appendingPathComponent("manifest.json", isDirectory: false).path) {
            return extractedRootURL
        }

        let topLevelEntries = try fileManager.contentsOfDirectory(at: extractedRootURL, includingPropertiesForKeys: nil)
        for entry in topLevelEntries {
            let manifestURL = entry.appendingPathComponent("manifest.json", isDirectory: false)
            if fileManager.fileExists(atPath: manifestURL.path) {
                return entry
            }
        }

        throw WorkflowPackageError.packageRootNotFound
    }

    private func copyDirectory(from sourceURL: URL, to destinationURL: URL) throws {
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        try removeJunkFiles(in: destinationURL)
    }

    private func removeJunkFiles(in rootURL: URL) throws {
        guard let enumerator = fileManager.enumerator(at: rootURL, includingPropertiesForKeys: nil, options: []) else {
            return
        }

        var junkURLs: [URL] = []
        for case let fileURL as URL in enumerator where fileURL.lastPathComponent == ".DS_Store" {
            junkURLs.append(fileURL)
        }

        for junkURL in junkURLs {
            try? fileManager.removeItem(at: junkURL)
        }
    }

    private func safeDirectoryName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "workflow-package" : trimmed
        return base.replacingOccurrences(of: "/", with: "-")
    }

    private func uniqueWorkflowName(_ requestedName: String, existingNames: Set<String>) -> String {
        let trimmed = requestedName.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "Imported Workflow" : trimmed
        guard existingNames.contains(base) else { return base }

        var candidate = base
        var suffix = 2
        while existingNames.contains(candidate) {
            candidate = "\(base) \(suffix)"
            suffix += 1
        }
        return candidate
    }

    private func encode<T: Encodable>(_ value: T, to url: URL) throws {
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)
    }

    private func decode<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        let data = try Data(contentsOf: url)
        return try decoder.decode(type, from: data)
    }
}
