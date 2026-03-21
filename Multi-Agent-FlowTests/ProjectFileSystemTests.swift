import XCTest
@testable import Multi_Agent_Flow

private struct CommunicationMatrixFixture: Decodable {
    struct Route: Decodable {
        var edgeID: UUID
        var fromNodeID: UUID
        var toNodeID: UUID
        var fromAgentID: UUID?
        var toAgentID: UUID?
        var permissionType: PermissionType
        var requiresApproval: Bool
        var isBidirectional: Bool
        var isImplicitReverse: Bool
    }

    var workflowID: UUID
    var routes: [Route]
}

private struct FileScopeMapFixture: Decodable {
    struct BoundaryScope: Decodable {
        var boundaryID: UUID
        var title: String
        var memberNodeIDs: [UUID]
        var geometryContainedNodeIDs: [UUID]
    }

    struct NodeScope: Decodable {
        var nodeID: UUID
        var agentID: UUID?
        var enclosingBoundaryID: UUID?
        var readableNodeIDs: [UUID]
        var restrictedNodeIDs: [UUID]
    }

    var workflowID: UUID
    var defaultAccess: PermissionType
    var boundaryScopes: [BoundaryScope]
    var nodeScopes: [NodeScope]
}

private struct LaunchReportFixture: Decodable {
    var workflowID: UUID
    var report: WorkflowLaunchVerificationReport?
}

private struct WorkbenchThreadFixture: Decodable {
    var threadID: String
    var sessionID: String
    var workflowID: UUID?
    var entryAgentID: UUID?
    var status: String
    var messageCount: Int
    var taskCount: Int
    var pendingApprovalCount: Int
}

private struct WorkbenchThreadInvestigationFixture: Decodable {
    var threadID: String
    var sessionID: String
    var workflowID: UUID?
    var workflowName: String?
    var entryAgentID: UUID?
    var entryAgentName: String?
    var participantAgentIDs: [UUID]
    var relatedNodeIDs: [UUID]
    var status: String
    var messageCount: Int
    var taskCount: Int
    var pendingApprovalCount: Int
    var dispatchCount: Int
    var eventCount: Int
    var receiptCount: Int
}

private struct RuntimeSessionFixture: Decodable {
    var sessionID: String
    var workflowIDs: [String]
    var eventCount: Int
    var dispatchCount: Int
    var receiptCount: Int
    var isProjectRuntimeSession: Bool
}

private struct WorkflowIndexEntryFixture: Decodable {
    var workflowID: UUID
    var nodeCount: Int
    var edgeCount: Int
}

private struct NodeIndexEntryFixture: Decodable {
    var workflowID: UUID
    var nodeID: UUID
    var agentID: UUID?
    var boundaryID: UUID?
}

private struct ThreadIndexEntryFixture: Decodable {
    var threadID: String
    var sessionID: String
    var status: String
    var messageCount: Int
    var taskCount: Int
}

private struct RuntimeSessionIndexEntryFixture: Decodable {
    var sessionID: String
    var storageDirectoryName: String
    var eventCount: Int
    var dispatchCount: Int
    var receiptCount: Int
    var isProjectRuntimeSession: Bool
}

private struct RuntimeDispatchRecordEnvelopeFixture: Decodable {
    var stateBucket: String
    var record: RuntimeDispatchRecord
}

private struct AnalyticsOverviewProjectionFixture: Decodable {
    var projectID: UUID
    var taskCount: Int
    var messageCount: Int
    var executionResultCount: Int
    var completedExecutionCount: Int
    var failedExecutionCount: Int
    var warningLogCount: Int
    var errorLogCount: Int
    var pendingApprovalCount: Int
}

private struct AnalyticsTraceProjectionFixture: Decodable {
    struct Entry: Decodable {
        var executionID: UUID
        var status: ExecutionStatus
        var outputType: ExecutionOutputType
    }

    var projectID: UUID
    var traces: [Entry]
}

private struct AnalyticsAnomalyProjectionFixture: Decodable {
    struct Entry: Decodable {
        var source: String
        var severity: String
    }

    var projectID: UUID
    var anomalies: [Entry]
}

private func decodeNDJSON<T: Decodable>(_ type: T.Type, from url: URL) throws -> [T] {
    let data = try Data(contentsOf: url)
    guard let contents = String(data: data, encoding: .utf8), !contents.isEmpty else {
        return []
    }

    let decoder = JSONDecoder()
    return try contents
        .split(whereSeparator: \.isNewline)
        .map { line in
            try decoder.decode(T.self, from: Data(line.utf8))
        }
}

final class ProjectFileSystemTests: XCTestCase {
    func testSynchronizeProjectCreatesManagedScaffoldAndManifest() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let project = MAProject(name: "Filesystem Test")
        let fileSystem = ProjectFileSystem()

        let manifest = try fileSystem.synchronizeProject(
            project,
            sourceProjectFileURL: URL(fileURLWithPath: "/tmp/Filesystem Test.maoproj"),
            under: tempRoot
        )

        XCTAssertEqual(manifest.projectID, project.id)
        XCTAssertEqual(manifest.projectName, project.name)
        XCTAssertEqual(manifest.fileVersion, project.fileVersion)

        let manifestURL = fileSystem.manifestURL(for: project.id, under: tempRoot)
        let snapshotURL = fileSystem.currentSnapshotURL(for: project.id, under: tempRoot)

        XCTAssertTrue(FileManager.default.fileExists(atPath: manifestURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: snapshotURL.path))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: fileSystem.managedProjectRootDirectory(for: project.id, under: tempRoot)
                    .appendingPathComponent("design/workflows", isDirectory: true).path
            )
        )
    }

    func testNodeOpenClawPathHelpersResolveManagedDesignLocations() {
        let projectID = UUID(uuidString: "01000000-0000-0000-0000-000000000001")!
        let workflowID = UUID(uuidString: "02000000-0000-0000-0000-000000000002")!
        let nodeID = UUID(uuidString: "03000000-0000-0000-0000-000000000003")!
        let appSupportRoot = URL(fileURLWithPath: "/tmp/project-fs-helpers", isDirectory: true)
        let fileSystem = ProjectFileSystem()

        let nodeRootURL = fileSystem.designNodeRootDirectory(
            for: nodeID,
            workflowID: workflowID,
            projectID: projectID,
            under: appSupportRoot
        )
        let openClawRootURL = fileSystem.nodeOpenClawRootDirectory(
            for: nodeID,
            workflowID: workflowID,
            projectID: projectID,
            under: appSupportRoot
        )
        let workspaceRootURL = fileSystem.nodeOpenClawWorkspaceDirectory(
            for: nodeID,
            workflowID: workflowID,
            projectID: projectID,
            under: appSupportRoot
        )
        let soulURL = fileSystem.nodeOpenClawSoulURL(
            for: nodeID,
            workflowID: workflowID,
            projectID: projectID,
            under: appSupportRoot
        )

        XCTAssertEqual(
            nodeRootURL.path,
            "/tmp/project-fs-helpers/Projects/01000000-0000-0000-0000-000000000001/design/workflows/02000000-0000-0000-0000-000000000002/nodes/03000000-0000-0000-0000-000000000003"
        )
        XCTAssertEqual(openClawRootURL, nodeRootURL.appendingPathComponent("openclaw", isDirectory: true))
        XCTAssertEqual(workspaceRootURL, openClawRootURL.appendingPathComponent("workspace", isDirectory: true))
        XCTAssertEqual(soulURL, workspaceRootURL.appendingPathComponent("SOUL.md", isDirectory: false))
    }

    func testSynchronizeProjectUpdatesStoredSnapshotContents() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let project = MAProject(name: "Snapshot Test")
        let fileSystem = ProjectFileSystem()

        _ = try fileSystem.synchronizeProject(project, sourceProjectFileURL: nil, under: tempRoot)

        let snapshotURL = fileSystem.currentSnapshotURL(for: project.id, under: tempRoot)
        let data = try Data(contentsOf: snapshotURL)
        let decoded = try JSONDecoder().decode(MAProject.self, from: data)

        XCTAssertEqual(decoded.id, project.id)
        XCTAssertEqual(decoded.name, project.name)
        XCTAssertEqual(decoded.fileVersion, project.fileVersion)
    }

    func testSynchronizeProjectWritesDesignWorkflowNodeAndAgentFiles() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        var project = MAProject(name: "Design Test")
        var agent = Agent(name: "测试-任务-1")
        agent.identity = "reviewer"
        agent.description = "Design agent"
        agent.soulMD = "# SOUL\nDesign soul"
        agent.openClawDefinition.agentIdentifier = "design-agent"
        agent.openClawDefinition.modelIdentifier = "gpt-test"
        agent.openClawDefinition.runtimeProfile = "strict"
        agent.openClawDefinition.memoryBackupPath = "/tmp/design-agent-memory"
        agent.openClawDefinition.soulSourcePath = "/tmp/design-agent/SOUL.md"
        agent.openClawDefinition.lastImportedSoulHash = "hash-123"
        agent.openClawDefinition.lastImportedSoulPath = "/tmp/design-agent/SOUL.md"
        agent.openClawDefinition.lastImportedAt = Date(timeIntervalSince1970: 1_700_000_000)
        agent.openClawDefinition.environment = ["MODE": "test"]
        project.agents = [agent]

        var workflow = project.workflows[0]
        var node = WorkflowNode(type: .agent)
        node.agentID = agent.id
        node.title = "节点-设计-1"
        workflow.nodes = [node]

        var edge = WorkflowEdge(from: node.id, to: node.id)
        edge.requiresApproval = true
        workflow.edges = [edge]

        let boundary = WorkflowBoundary(title: "Boundary", rect: .zero, memberNodeIDs: [node.id])
        workflow.boundaries = [boundary]
        project.workflows = [workflow]

        let fileSystem = ProjectFileSystem()
        _ = try fileSystem.synchronizeProject(project, sourceProjectFileURL: nil, under: tempRoot)

        let projectRoot = fileSystem.managedProjectRootDirectory(for: project.id, under: tempRoot)
        let designProjectURL = projectRoot.appendingPathComponent("design/project.json", isDirectory: false)
        let workflowURL = projectRoot.appendingPathComponent(
            "design/workflows/\(workflow.id.uuidString)/workflow.json",
            isDirectory: false
        )
        let nodeURL = projectRoot.appendingPathComponent(
            "design/workflows/\(workflow.id.uuidString)/nodes/\(node.id.uuidString)/node.json",
            isDirectory: false
        )
        let agentURL = projectRoot.appendingPathComponent(
            "design/workflows/\(workflow.id.uuidString)/nodes/\(node.id.uuidString)/agent.json",
            isDirectory: false
        )
        let soulURL = projectRoot.appendingPathComponent(
            "design/workflows/\(workflow.id.uuidString)/nodes/\(node.id.uuidString)/openclaw/workspace/SOUL.md",
            isDirectory: false
        )
        let agentsMarkdownURL = projectRoot.appendingPathComponent(
            "design/workflows/\(workflow.id.uuidString)/nodes/\(node.id.uuidString)/openclaw/workspace/AGENTS.md",
            isDirectory: false
        )
        let identityURL = projectRoot.appendingPathComponent(
            "design/workflows/\(workflow.id.uuidString)/nodes/\(node.id.uuidString)/openclaw/workspace/IDENTITY.md",
            isDirectory: false
        )
        let userURL = projectRoot.appendingPathComponent(
            "design/workflows/\(workflow.id.uuidString)/nodes/\(node.id.uuidString)/openclaw/workspace/USER.md",
            isDirectory: false
        )
        let toolsURL = projectRoot.appendingPathComponent(
            "design/workflows/\(workflow.id.uuidString)/nodes/\(node.id.uuidString)/openclaw/workspace/TOOLS.md",
            isDirectory: false
        )
        let heartbeatURL = projectRoot.appendingPathComponent(
            "design/workflows/\(workflow.id.uuidString)/nodes/\(node.id.uuidString)/openclaw/workspace/HEARTBEAT.md",
            isDirectory: false
        )
        let bootstrapURL = projectRoot.appendingPathComponent(
            "design/workflows/\(workflow.id.uuidString)/nodes/\(node.id.uuidString)/openclaw/workspace/BOOTSTRAP.md",
            isDirectory: false
        )
        let memoryURL = projectRoot.appendingPathComponent(
            "design/workflows/\(workflow.id.uuidString)/nodes/\(node.id.uuidString)/openclaw/workspace/MEMORY.md",
            isDirectory: false
        )
        let memoryDirectoryURL = projectRoot.appendingPathComponent(
            "design/workflows/\(workflow.id.uuidString)/nodes/\(node.id.uuidString)/openclaw/workspace/memory",
            isDirectory: true
        )
        let skillsDirectoryURL = projectRoot.appendingPathComponent(
            "design/workflows/\(workflow.id.uuidString)/nodes/\(node.id.uuidString)/openclaw/workspace/skills",
            isDirectory: true
        )
        let bindingURL = projectRoot.appendingPathComponent(
            "design/workflows/\(workflow.id.uuidString)/nodes/\(node.id.uuidString)/openclaw/binding.json",
            isDirectory: false
        )
        let sourceMapURL = projectRoot.appendingPathComponent(
            "design/workflows/\(workflow.id.uuidString)/nodes/\(node.id.uuidString)/openclaw/mirror/source-map.json",
            isDirectory: false
        )
        let syncBaselineURL = projectRoot.appendingPathComponent(
            "design/workflows/\(workflow.id.uuidString)/nodes/\(node.id.uuidString)/openclaw/mirror/sync-baseline.json",
            isDirectory: false
        )
        let importRecordURL = projectRoot.appendingPathComponent(
            "design/workflows/\(workflow.id.uuidString)/nodes/\(node.id.uuidString)/openclaw/state/import-record.json",
            isDirectory: false
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: designProjectURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: workflowURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: nodeURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: agentURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: soulURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: agentsMarkdownURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: identityURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: userURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: toolsURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: heartbeatURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: bootstrapURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: memoryURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: memoryDirectoryURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: skillsDirectoryURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: bindingURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceMapURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: syncBaselineURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: importRecordURL.path))

        let soulContents = try String(contentsOf: soulURL, encoding: .utf8)
        let identityContents = try String(contentsOf: identityURL, encoding: .utf8)
        let toolsContents = try String(contentsOf: toolsURL, encoding: .utf8)
        let importRecordData = try Data(contentsOf: importRecordURL)
        let importRecordJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: importRecordData) as? [String: Any])
        XCTAssertEqual(soulContents, agent.soulMD)
        XCTAssertTrue(identityContents.contains(agent.identity))
        XCTAssertTrue(toolsContents.contains(agent.openClawDefinition.modelIdentifier))
        XCTAssertEqual(importRecordJSON["agentIdentifier"] as? String, agent.openClawDefinition.agentIdentifier)
        XCTAssertEqual(importRecordJSON["memoryBackupPath"] as? String, agent.openClawDefinition.memoryBackupPath)
    }

    func testSynchronizeProjectMirrorsOpenClawWorkspaceSkillsAndMemoryArtifacts() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let externalAgentRoot = tempRoot.appendingPathComponent("external-agent", isDirectory: true)
        let externalWorkspaceRoot = externalAgentRoot.appendingPathComponent("workspace", isDirectory: true)
        let externalSkillsRoot = externalWorkspaceRoot.appendingPathComponent("skills", isDirectory: true)
        let externalMemoryRoot = externalWorkspaceRoot.appendingPathComponent("memory", isDirectory: true)
        let externalPrivateRoot = externalAgentRoot.appendingPathComponent("private", isDirectory: true)
        let nestedSkillDirectory = externalSkillsRoot.appendingPathComponent("playbooks", isDirectory: true)

        try FileManager.default.createDirectory(at: nestedSkillDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: externalMemoryRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: externalPrivateRoot, withIntermediateDirectories: true)

        let soulSourceURL = externalWorkspaceRoot.appendingPathComponent("SOUL.md", isDirectory: false)
        try "# External Soul\nMirrored".write(to: soulSourceURL, atomically: true, encoding: .utf8)
        try "planner-skill".write(
            to: externalSkillsRoot.appendingPathComponent("planner.md", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try "nested-checklist".write(
            to: nestedSkillDirectory.appendingPathComponent("checklist.md", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try "workspace-memory".write(
            to: externalMemoryRoot.appendingPathComponent("summary.txt", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try "{\"session\":\"backup\"}".write(
            to: externalPrivateRoot.appendingPathComponent("session.json", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        var project = MAProject(name: "Mirror Test")
        var agent = Agent(name: "镜像-OpenClaw-1")
        agent.soulMD = "# Managed Soul\nPrimary"
        agent.openClawDefinition.agentIdentifier = "mirror-agent"
        agent.openClawDefinition.memoryBackupPath = externalPrivateRoot.path
        agent.openClawDefinition.soulSourcePath = soulSourceURL.path
        project.agents = [agent]

        var workflow = project.workflows[0]
        var node = WorkflowNode(type: .agent)
        node.agentID = agent.id
        node.title = "镜像节点"
        workflow.nodes = [node]
        project.workflows = [workflow]

        let fileSystem = ProjectFileSystem()
        _ = try fileSystem.synchronizeProject(project, sourceProjectFileURL: nil, under: tempRoot)

        let openClawWorkspaceRoot = fileSystem.managedProjectRootDirectory(for: project.id, under: tempRoot)
            .appendingPathComponent(
                "design/workflows/\(workflow.id.uuidString)/nodes/\(node.id.uuidString)/openclaw/workspace",
                isDirectory: true
            )

        let mirroredSkillURL = openClawWorkspaceRoot.appendingPathComponent("skills/planner.md", isDirectory: false)
        let mirroredNestedSkillURL = openClawWorkspaceRoot.appendingPathComponent(
            "skills/playbooks/checklist.md",
            isDirectory: false
        )
        let mirroredWorkspaceMemoryURL = openClawWorkspaceRoot.appendingPathComponent(
            "memory/workspace/summary.txt",
            isDirectory: false
        )
        let mirroredBackupMemoryURL = openClawWorkspaceRoot.appendingPathComponent(
            "memory/backup/session.json",
            isDirectory: false
        )

        XCTAssertEqual(try String(contentsOf: mirroredSkillURL, encoding: .utf8), "planner-skill")
        XCTAssertEqual(try String(contentsOf: mirroredNestedSkillURL, encoding: .utf8), "nested-checklist")
        XCTAssertEqual(try String(contentsOf: mirroredWorkspaceMemoryURL, encoding: .utf8), "workspace-memory")
        XCTAssertEqual(try String(contentsOf: mirroredBackupMemoryURL, encoding: .utf8), "{\"session\":\"backup\"}")
    }

    func testSynchronizeProjectWritesDerivedWorkflowIndexes() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        var project = MAProject(name: "Derived Test")

        var agentA = Agent(name: "分析-研发-1")
        agentA.soulMD = "# Agent A"
        var agentB = Agent(name: "执行-研发-1")
        agentB.soulMD = "# Agent B"
        project.agents = [agentA, agentB]

        var workflow = project.workflows[0]
        var nodeA = WorkflowNode(type: .agent)
        nodeA.agentID = agentA.id
        nodeA.position = CGPoint(x: 20, y: 20)
        nodeA.title = "分析-研发-1"

        var nodeB = WorkflowNode(type: .agent)
        nodeB.agentID = agentB.id
        nodeB.position = CGPoint(x: 220, y: 220)
        nodeB.title = "执行-研发-1"

        var edge = WorkflowEdge(from: nodeA.id, to: nodeB.id)
        edge.requiresApproval = true
        edge.isBidirectional = true

        let boundary = WorkflowBoundary(
            title: "Secure Scope",
            rect: CGRect(x: 0, y: 0, width: 120, height: 120),
            memberNodeIDs: [nodeA.id]
        )
        let report = WorkflowLaunchVerificationReport(
            workflowID: workflow.id,
            workflowName: workflow.name,
            workflowSignature: "signature-1",
            status: .warn,
            staticFindings: ["edge requires approval"]
        )

        workflow.nodes = [nodeA, nodeB]
        workflow.edges = [edge]
        workflow.boundaries = [boundary]
        workflow.lastLaunchVerificationReport = report
        project.workflows = [workflow]

        let fileSystem = ProjectFileSystem()
        _ = try fileSystem.synchronizeProject(project, sourceProjectFileURL: nil, under: tempRoot)

        let workflowRoot = fileSystem.managedProjectRootDirectory(for: project.id, under: tempRoot)
            .appendingPathComponent("design/workflows/\(workflow.id.uuidString)", isDirectory: true)

        let matrixURL = workflowRoot.appendingPathComponent("derived/communication-matrix.json", isDirectory: false)
        let scopeMapURL = workflowRoot.appendingPathComponent("derived/file-scope-map.json", isDirectory: false)
        let launchReportURL = workflowRoot.appendingPathComponent("derived/launch-report.json", isDirectory: false)

        XCTAssertTrue(FileManager.default.fileExists(atPath: matrixURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: scopeMapURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: launchReportURL.path))

        let matrix = try JSONDecoder().decode(CommunicationMatrixFixture.self, from: Data(contentsOf: matrixURL))
        XCTAssertEqual(matrix.workflowID, workflow.id)
        XCTAssertEqual(matrix.routes.count, 2)
        XCTAssertTrue(matrix.routes.allSatisfy(\.requiresApproval))
        XCTAssertTrue(matrix.routes.allSatisfy { $0.permissionType == .requireApproval })
        XCTAssertTrue(matrix.routes.contains { !$0.isImplicitReverse && $0.fromNodeID == nodeA.id && $0.toNodeID == nodeB.id })
        XCTAssertTrue(matrix.routes.contains { $0.isImplicitReverse && $0.fromNodeID == nodeB.id && $0.toNodeID == nodeA.id })

        let scopeMap = try JSONDecoder().decode(FileScopeMapFixture.self, from: Data(contentsOf: scopeMapURL))
        XCTAssertEqual(scopeMap.workflowID, workflow.id)
        XCTAssertEqual(scopeMap.defaultAccess, .allow)
        XCTAssertEqual(scopeMap.boundaryScopes.first?.memberNodeIDs, [nodeA.id])
        XCTAssertEqual(scopeMap.boundaryScopes.first?.geometryContainedNodeIDs, [nodeA.id])

        let nodeAScope = try XCTUnwrap(scopeMap.nodeScopes.first { $0.nodeID == nodeA.id })
        XCTAssertEqual(nodeAScope.enclosingBoundaryID, boundary.id)
        XCTAssertTrue(nodeAScope.readableNodeIDs.contains(nodeA.id))
        XCTAssertTrue(nodeAScope.restrictedNodeIDs.contains(nodeB.id))

        let nodeBScope = try XCTUnwrap(scopeMap.nodeScopes.first { $0.nodeID == nodeB.id })
        XCTAssertNil(nodeBScope.enclosingBoundaryID)
        XCTAssertTrue(nodeBScope.readableNodeIDs.contains(nodeA.id))
        XCTAssertTrue(nodeBScope.readableNodeIDs.contains(nodeB.id))
        XCTAssertTrue(nodeBScope.restrictedNodeIDs.isEmpty)

        let launchReport = try JSONDecoder().decode(LaunchReportFixture.self, from: Data(contentsOf: launchReportURL))
        XCTAssertEqual(launchReport.workflowID, workflow.id)
        XCTAssertEqual(launchReport.report?.status, .warn)
        XCTAssertEqual(launchReport.report?.staticFindings, ["edge requires approval"])
    }

    func testLoadAssembledProjectPrefersDesignStateForBoundAgents() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        var project = MAProject(name: "Assemble Test")

        var boundAgent = Agent(name: "写作-策划-1")
        boundAgent.soulMD = "# Bound Agent\noriginal"
        var unboundAgent = Agent(name: "校验-策划-1")
        unboundAgent.soulMD = "# Unbound Agent"
        project.agents = [boundAgent, unboundAgent]

        var workflow = project.workflows[0]
        var node = WorkflowNode(type: .agent)
        node.agentID = boundAgent.id
        node.title = "写作-策划-1"
        workflow.nodes = [node]
        project.workflows = [workflow]

        let fileSystem = ProjectFileSystem()
        _ = try fileSystem.synchronizeProject(project, sourceProjectFileURL: nil, under: tempRoot)

        let soulURL = fileSystem.managedProjectRootDirectory(for: project.id, under: tempRoot)
            .appendingPathComponent(
                "design/workflows/\(workflow.id.uuidString)/nodes/\(node.id.uuidString)/openclaw/workspace/SOUL.md",
                isDirectory: false
            )
        try "# Bound Agent\nupdated-from-design".write(to: soulURL, atomically: true, encoding: .utf8)

        let assembled = try XCTUnwrap(fileSystem.loadAssembledProject(for: project.id, under: tempRoot))
        let assembledBoundAgent = try XCTUnwrap(assembled.agents.first { $0.id == boundAgent.id })
        let assembledUnboundAgent = try XCTUnwrap(assembled.agents.first { $0.id == unboundAgent.id })

        XCTAssertEqual(assembled.workflows.count, 1)
        XCTAssertEqual(assembled.workflows[0].nodes.first?.agentID, boundAgent.id)
        XCTAssertEqual(assembledBoundAgent.soulMD, "# Bound Agent\nupdated-from-design")
        XCTAssertEqual(assembledUnboundAgent.soulMD, unboundAgent.soulMD)
    }

    func testSynchronizeProjectRejectsReusedAgentAcrossNodes() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        var project = MAProject(name: "Topology Test")
        let agent = Agent(name: "复用-非法-1")
        project.agents = [agent]

        var workflow = project.workflows[0]
        var firstNode = WorkflowNode(type: .agent)
        firstNode.agentID = agent.id
        var secondNode = WorkflowNode(type: .agent)
        secondNode.agentID = agent.id
        workflow.nodes = [firstNode, secondNode]
        project.workflows = [workflow]

        let fileSystem = ProjectFileSystem()

        XCTAssertThrowsError(try fileSystem.synchronizeProject(project, sourceProjectFileURL: nil, under: tempRoot)) { error in
            guard case let ProjectFileSystemError.duplicateNodeAgentBinding(agentID, firstNodeID, duplicateNodeID) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(agentID, agent.id)
            XCTAssertEqual(firstNodeID, firstNode.id)
            XCTAssertEqual(duplicateNodeID, secondNode.id)
        }
    }

    func testSynchronizeProjectWritesCollaborationRuntimeExecutionAndIndexes() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        var project = MAProject(name: "Operations Test")

        let agent = Agent(name: "协作-运行-1")
        project.agents = [agent]

        var workflow = project.workflows[0]
        var node = WorkflowNode(type: .agent)
        node.agentID = agent.id
        node.position = CGPoint(x: 40, y: 40)
        node.title = "协作-运行-1"
        workflow.nodes = [node]
        let boundary = WorkflowBoundary(title: "Ops", rect: CGRect(x: 0, y: 0, width: 100, height: 100), memberNodeIDs: [node.id])
        workflow.boundaries = [boundary]
        project.workflows = [workflow]

        let sessionID = "workbench-\(project.runtimeState.sessionID)-\(workflow.id.uuidString)-\(agent.id.uuidString)"
        var task = Task(
            title: "运营任务",
            description: "整理执行过程",
            status: .inProgress,
            priority: .high,
            assignedAgentID: agent.id,
            workflowNodeID: node.id
        )
        task.metadata["source"] = "workbench"
        task.metadata["workflowID"] = workflow.id.uuidString
        task.metadata["workbenchSessionID"] = sessionID
        project.tasks = [task]
        project.workspaceIndex = [
            ProjectWorkspaceRecord(
                taskID: task.id,
                workspaceRelativePath: "\(project.id.uuidString)/\(task.id.uuidString)",
                workspaceName: task.title
            )
        ]

        var userMessage = Message(from: agent.id, to: agent.id, type: .task, content: "开始任务")
        userMessage.status = .read
        userMessage.metadata["channel"] = "workbench"
        userMessage.metadata["role"] = "user"
        userMessage.metadata["workflowID"] = workflow.id.uuidString
        userMessage.metadata["workbenchSessionID"] = sessionID
        userMessage.metadata["entryAgentID"] = agent.id.uuidString

        var approvalMessage = Message(from: agent.id, to: agent.id, type: .notification, content: "需要审批")
        approvalMessage.status = .waitingForApproval
        approvalMessage.requiresApproval = true
        approvalMessage.metadata["channel"] = "workbench"
        approvalMessage.metadata["role"] = "assistant"
        approvalMessage.metadata["workflowID"] = workflow.id.uuidString
        approvalMessage.metadata["workbenchSessionID"] = sessionID
        approvalMessage.metadata["entryAgentID"] = agent.id.uuidString
        project.messages = [userMessage, approvalMessage]

        let dispatchEvent = OpenClawRuntimeEvent(
            eventType: .taskDispatch,
            workflowId: workflow.id.uuidString,
            nodeId: node.id.uuidString,
            sessionKey: sessionID,
            source: OpenClawRuntimeActor(kind: .user, agentId: "user", agentName: "User"),
            target: OpenClawRuntimeActor(kind: .agent, agentId: agent.id.uuidString, agentName: agent.name),
            transport: OpenClawRuntimeTransport(kind: .runtimeChannel, deploymentKind: "local"),
            payload: ["summary": "开始任务"]
        )
        let resultEvent = OpenClawRuntimeEvent(
            eventType: .taskResult,
            workflowId: workflow.id.uuidString,
            nodeId: node.id.uuidString,
            sessionKey: sessionID,
            source: OpenClawRuntimeActor(kind: .agent, agentId: agent.id.uuidString, agentName: agent.name),
            target: OpenClawRuntimeActor(kind: .orchestrator, agentId: "orchestrator", agentName: "Orchestrator"),
            transport: OpenClawRuntimeTransport(kind: .runtimeChannel, deploymentKind: "local"),
            payload: ["summary": "执行完成"]
        )

        let dispatchRecord = RuntimeDispatchRecord(
            eventID: dispatchEvent.id,
            workflowID: workflow.id.uuidString,
            nodeID: node.id.uuidString,
            sourceAgentID: "user",
            targetAgentID: agent.id.uuidString,
            summary: "开始任务",
            sessionKey: sessionID,
            status: .running,
            transportKind: .runtimeChannel
        )
        project.runtimeState.dispatchQueue = [dispatchRecord]
        project.runtimeState.runtimeEvents = [dispatchEvent, resultEvent]

        let result = ExecutionResult(
            nodeID: node.id,
            agentID: agent.id,
            status: .completed,
            output: "执行完成",
            outputType: .agentFinalResponse,
            sessionID: sessionID,
            transportKind: OpenClawRuntimeTransportKind.runtimeChannel.rawValue,
            runtimeEvents: [dispatchEvent, resultEvent],
            primaryRuntimeEvent: resultEvent
        )
        project.executionResults = [result]
        project.executionLogs = [
            ExecutionLogEntry(level: .info, message: "Workbench started", nodeID: node.id)
        ]

        let fileSystem = ProjectFileSystem()
        _ = try fileSystem.synchronizeProject(project, sourceProjectFileURL: nil, under: tempRoot)

        let projectRoot = fileSystem.managedProjectRootDirectory(for: project.id, under: tempRoot)
        let threadRoot = projectRoot.appendingPathComponent(
            "collaboration/workbench/threads/\(sessionID)",
            isDirectory: true
        )
        let runtimeSessionRoot = projectRoot.appendingPathComponent(
            "runtime/sessions/\(sessionID)",
            isDirectory: true
        )

        let threadURL = threadRoot.appendingPathComponent("thread.json", isDirectory: false)
        let contextURL = threadRoot.appendingPathComponent("context.json", isDirectory: false)
        let threadInvestigationURL = threadRoot.appendingPathComponent("investigation.json", isDirectory: false)
        let dialogURL = threadRoot.appendingPathComponent("dialog.ndjson", isDirectory: false)
        let messagesURL = projectRoot.appendingPathComponent("collaboration/communications/messages.ndjson", isDirectory: false)
        let approvalsURL = projectRoot.appendingPathComponent("collaboration/communications/approvals.ndjson", isDirectory: false)
        let runtimeStateURL = projectRoot.appendingPathComponent("runtime/state/runtime-state.json", isDirectory: false)
        let queueURL = projectRoot.appendingPathComponent("runtime/state/queue.json", isDirectory: false)
        let runtimeSessionURL = runtimeSessionRoot.appendingPathComponent("session.json", isDirectory: false)
        let runtimeDispatchesURL = runtimeSessionRoot.appendingPathComponent("dispatches.ndjson", isDirectory: false)
        let runtimeEventsURL = runtimeSessionRoot.appendingPathComponent("events.ndjson", isDirectory: false)
        let runtimeReceiptsURL = runtimeSessionRoot.appendingPathComponent("receipts.ndjson", isDirectory: false)
        let resultsURL = projectRoot.appendingPathComponent("execution/results.ndjson", isDirectory: false)
        let logsURL = projectRoot.appendingPathComponent("execution/logs.ndjson", isDirectory: false)
        let tasksURL = projectRoot.appendingPathComponent("tasks/tasks.json", isDirectory: false)
        let workspaceIndexURL = projectRoot.appendingPathComponent("tasks/workspace-index.json", isDirectory: false)
        let analyticsOverviewURL = projectRoot.appendingPathComponent("analytics/projections/overview.json", isDirectory: false)
        let analyticsTracesURL = projectRoot.appendingPathComponent("analytics/projections/traces.json", isDirectory: false)
        let analyticsAnomaliesURL = projectRoot.appendingPathComponent("analytics/projections/anomalies.json", isDirectory: false)
        let workflowIndexURL = projectRoot.appendingPathComponent("indexes/workflows.json", isDirectory: false)
        let nodeIndexURL = projectRoot.appendingPathComponent("indexes/nodes.json", isDirectory: false)
        let threadIndexURL = projectRoot.appendingPathComponent("indexes/threads.json", isDirectory: false)
        let sessionIndexURL = projectRoot.appendingPathComponent("indexes/sessions.json", isDirectory: false)

        XCTAssertTrue(FileManager.default.fileExists(atPath: threadURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: contextURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: threadInvestigationURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dialogURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: messagesURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: approvalsURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: runtimeStateURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: queueURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: runtimeSessionURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: runtimeDispatchesURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: runtimeEventsURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: runtimeReceiptsURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: resultsURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: logsURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: tasksURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: workspaceIndexURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: analyticsOverviewURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: analyticsTracesURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: analyticsAnomaliesURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: workflowIndexURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: nodeIndexURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: threadIndexURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sessionIndexURL.path))

        let thread = try JSONDecoder().decode(WorkbenchThreadFixture.self, from: Data(contentsOf: threadURL))
        XCTAssertEqual(thread.threadID, sessionID)
        XCTAssertEqual(thread.sessionID, sessionID)
        XCTAssertEqual(thread.workflowID, workflow.id)
        XCTAssertEqual(thread.entryAgentID, agent.id)
        XCTAssertEqual(thread.status, "approval_pending")
        XCTAssertEqual(thread.messageCount, 2)
        XCTAssertEqual(thread.taskCount, 1)
        XCTAssertEqual(thread.pendingApprovalCount, 1)

        let threadInvestigation = try JSONDecoder().decode(
            WorkbenchThreadInvestigationFixture.self,
            from: Data(contentsOf: threadInvestigationURL)
        )
        XCTAssertEqual(threadInvestigation.threadID, sessionID)
        XCTAssertEqual(threadInvestigation.sessionID, sessionID)
        XCTAssertEqual(threadInvestigation.workflowID, workflow.id)
        XCTAssertEqual(threadInvestigation.workflowName, workflow.name)
        XCTAssertEqual(threadInvestigation.entryAgentID, agent.id)
        XCTAssertEqual(threadInvestigation.entryAgentName, agent.name)
        XCTAssertEqual(threadInvestigation.participantAgentIDs, [agent.id])
        XCTAssertEqual(threadInvestigation.relatedNodeIDs, [node.id])
        XCTAssertEqual(threadInvestigation.status, "approval_pending")
        XCTAssertEqual(threadInvestigation.messageCount, 2)
        XCTAssertEqual(threadInvestigation.taskCount, 1)
        XCTAssertEqual(threadInvestigation.pendingApprovalCount, 1)
        XCTAssertEqual(threadInvestigation.dispatchCount, 1)
        XCTAssertEqual(threadInvestigation.eventCount, 2)
        XCTAssertEqual(threadInvestigation.receiptCount, 1)

        let dialogMessages = try decodeNDJSON(Message.self, from: dialogURL)
        XCTAssertEqual(dialogMessages.count, 2)
        XCTAssertEqual(dialogMessages.last?.status, .waitingForApproval)

        let communicationMessages = try decodeNDJSON(Message.self, from: messagesURL)
        let approvalMessages = try decodeNDJSON(Message.self, from: approvalsURL)
        XCTAssertEqual(communicationMessages.count, 2)
        XCTAssertEqual(approvalMessages.count, 1)

        let runtimeState = try JSONDecoder().decode(RuntimeState.self, from: Data(contentsOf: runtimeStateURL))
        XCTAssertEqual(runtimeState.runtimeEvents.count, 2)
        let runtimeSession = try JSONDecoder().decode(RuntimeSessionFixture.self, from: Data(contentsOf: runtimeSessionURL))
        XCTAssertEqual(runtimeSession.sessionID, sessionID)
        XCTAssertEqual(runtimeSession.workflowIDs, [workflow.id.uuidString])
        XCTAssertEqual(runtimeSession.eventCount, 2)
        XCTAssertEqual(runtimeSession.dispatchCount, 1)
        XCTAssertEqual(runtimeSession.receiptCount, 1)
        XCTAssertFalse(runtimeSession.isProjectRuntimeSession)

        let runtimeDispatches = try decodeNDJSON(RuntimeDispatchRecordEnvelopeFixture.self, from: runtimeDispatchesURL)
        let runtimeEvents = try decodeNDJSON(OpenClawRuntimeEvent.self, from: runtimeEventsURL)
        let runtimeReceipts = try decodeNDJSON(ExecutionResult.self, from: runtimeReceiptsURL)
        XCTAssertEqual(runtimeDispatches.count, 1)
        XCTAssertEqual(runtimeEvents.count, 2)
        XCTAssertEqual(runtimeReceipts.count, 1)

        let results = try decodeNDJSON(ExecutionResult.self, from: resultsURL)
        let logs = try decodeNDJSON(ExecutionLogEntry.self, from: logsURL)
        let persistedTasks = try JSONDecoder().decode([Task].self, from: Data(contentsOf: tasksURL))
        let persistedWorkspaceIndex = try JSONDecoder().decode(
            [ProjectWorkspaceRecord].self,
            from: Data(contentsOf: workspaceIndexURL)
        )
        let analyticsOverview = try JSONDecoder().decode(
            AnalyticsOverviewProjectionFixture.self,
            from: Data(contentsOf: analyticsOverviewURL)
        )
        let analyticsTraces = try JSONDecoder().decode(
            AnalyticsTraceProjectionFixture.self,
            from: Data(contentsOf: analyticsTracesURL)
        )
        let analyticsAnomalies = try JSONDecoder().decode(
            AnalyticsAnomalyProjectionFixture.self,
            from: Data(contentsOf: analyticsAnomaliesURL)
        )
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(persistedTasks.map(\.id), [task.id])
        XCTAssertEqual(persistedWorkspaceIndex.map(\.taskID), [task.id])
        XCTAssertEqual(analyticsOverview.projectID, project.id)
        XCTAssertEqual(analyticsOverview.taskCount, 1)
        XCTAssertEqual(analyticsOverview.messageCount, 2)
        XCTAssertEqual(analyticsOverview.executionResultCount, 1)
        XCTAssertEqual(analyticsOverview.completedExecutionCount, 1)
        XCTAssertEqual(analyticsOverview.failedExecutionCount, 0)
        XCTAssertEqual(analyticsOverview.warningLogCount, 0)
        XCTAssertEqual(analyticsOverview.errorLogCount, 0)
        XCTAssertEqual(analyticsOverview.pendingApprovalCount, 1)
        XCTAssertEqual(analyticsTraces.projectID, project.id)
        XCTAssertEqual(analyticsTraces.traces.first?.executionID, result.id)
        XCTAssertEqual(analyticsAnomalies.projectID, project.id)
        XCTAssertTrue(analyticsAnomalies.anomalies.isEmpty)

        let workflowIndex = try JSONDecoder().decode([WorkflowIndexEntryFixture].self, from: Data(contentsOf: workflowIndexURL))
        let nodeIndex = try JSONDecoder().decode([NodeIndexEntryFixture].self, from: Data(contentsOf: nodeIndexURL))
        let threadIndex = try JSONDecoder().decode([ThreadIndexEntryFixture].self, from: Data(contentsOf: threadIndexURL))
        let sessionIndex = try JSONDecoder().decode([RuntimeSessionIndexEntryFixture].self, from: Data(contentsOf: sessionIndexURL))
        XCTAssertEqual(workflowIndex.first?.workflowID, workflow.id)
        XCTAssertEqual(workflowIndex.first?.nodeCount, 1)
        XCTAssertEqual(nodeIndex.first?.nodeID, node.id)
        XCTAssertEqual(nodeIndex.first?.boundaryID, boundary.id)
        XCTAssertEqual(threadIndex.first?.threadID, sessionID)
        XCTAssertTrue(sessionIndex.contains { $0.sessionID == sessionID && !$0.isProjectRuntimeSession })
        XCTAssertTrue(sessionIndex.contains { $0.sessionID == project.runtimeState.sessionID && $0.isProjectRuntimeSession })
    }
}
