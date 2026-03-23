import XCTest
@testable import Multi_Agent_Flow

final class WorkflowPackageServiceTests: XCTestCase {
    func testExportPreviewImportRoundTripPreservesWorkspaceTree() throws {
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory
            .appendingPathComponent("WorkflowPackageServiceTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: tempRoot) }

        let fileSystem = ProjectFileSystem()
        let service = WorkflowPackageService(fileManager: fileManager, projectFileSystem: fileSystem)

        var sourceProject = MAProject(name: "Source Project")
        var agent = Agent(name: "planner-task-1")
        agent.identity = "planner"
        agent.description = "Package source agent"
        agent.soulMD = "# Source Soul\nHello"
        sourceProject.agents = [agent]

        var workflow = sourceProject.workflows[0]
        var startNode = WorkflowNode(type: .start)
        startNode.title = "Start"
        var agentNode = WorkflowNode(type: .agent)
        agentNode.agentID = agent.id
        agentNode.title = agent.name
        workflow.nodes = [startNode, agentNode]
        workflow.edges = [WorkflowEdge(from: startNode.id, to: agentNode.id)]
        sourceProject.workflows = [workflow]

        _ = try fileSystem.synchronizeProject(sourceProject, sourceProjectFileURL: nil, under: tempRoot)

        let sourceWorkspaceURL = fileSystem.nodeOpenClawWorkspaceDirectory(
            for: agentNode.id,
            workflowID: workflow.id,
            projectID: sourceProject.id,
            under: tempRoot
        )
        try fileManager.createDirectory(
            at: sourceWorkspaceURL.appendingPathComponent("custom/state", isDirectory: true),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: sourceWorkspaceURL.appendingPathComponent("skills/custom", isDirectory: true),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: sourceWorkspaceURL.appendingPathComponent("memory/workspace", isDirectory: true),
            withIntermediateDirectories: true
        )
        try "agent state".write(
            to: sourceWorkspaceURL.appendingPathComponent("custom/state/profile.txt", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try "# custom skill".write(
            to: sourceWorkspaceURL.appendingPathComponent("skills/custom/SKILL.md", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try "{\"memory\":true}".write(
            to: sourceWorkspaceURL.appendingPathComponent("memory/workspace/history.json", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        let archiveURL = tempRoot.appendingPathComponent("workflow.maoworkflow", isDirectory: false)
        try service.exportPackage(
            rootWorkflowID: workflow.id,
            from: sourceProject,
            under: tempRoot,
            to: archiveURL
        )

        let preview = try service.preflightImportPackage(at: archiveURL)
        defer { service.cleanupPreview(preview) }

        XCTAssertEqual(preview.workflowCount, 1)
        XCTAssertEqual(preview.nodeAgentCount, 1)
        XCTAssertGreaterThan(preview.workspaceFileCount, 0)

        let targetProject = MAProject(name: "Target Project")
        let importResult = try service.importPackage(
            from: preview,
            into: targetProject,
            under: tempRoot,
            rootWorkflowNameOverride: "Imported Workflow"
        )

        let importedWorkflow = try XCTUnwrap(
            importResult.project.workflows.first(where: { $0.id == importResult.importedRootWorkflowID })
        )
        XCTAssertEqual(importedWorkflow.name, "Imported Workflow")

        let importedAgentNode = try XCTUnwrap(importedWorkflow.nodes.first(where: { $0.type == .agent }))
        let importedWorkspaceURL = fileSystem.nodeOpenClawWorkspaceDirectory(
            for: importedAgentNode.id,
            workflowID: importedWorkflow.id,
            projectID: importResult.project.id,
            under: tempRoot
        )

        XCTAssertEqual(
            try String(
                contentsOf: importedWorkspaceURL.appendingPathComponent("custom/state/profile.txt", isDirectory: false),
                encoding: .utf8
            ),
            "agent state"
        )
        XCTAssertEqual(
            try String(
                contentsOf: importedWorkspaceURL.appendingPathComponent("skills/custom/SKILL.md", isDirectory: false),
                encoding: .utf8
            ),
            "# custom skill"
        )
        XCTAssertEqual(
            try String(
                contentsOf: importedWorkspaceURL.appendingPathComponent("memory/workspace/history.json", isDirectory: false),
                encoding: .utf8
            ),
            "{\"memory\":true}"
        )

        _ = try fileSystem.synchronizeProject(importResult.project, sourceProjectFileURL: nil, under: tempRoot)

        XCTAssertTrue(
            fileManager.fileExists(
                atPath: importedWorkspaceURL.appendingPathComponent("custom/state/profile.txt", isDirectory: false).path
            )
        )
        XCTAssertTrue(
            fileManager.fileExists(
                atPath: importedWorkspaceURL.appendingPathComponent("skills/custom/SKILL.md", isDirectory: false).path
            )
        )
        XCTAssertTrue(
            fileManager.fileExists(
                atPath: importedWorkspaceURL.appendingPathComponent("memory/workspace/history.json", isDirectory: false).path
            )
        )
    }

    @MainActor
    func testAppStateUsesActiveWorkflowForEditingOperations() {
        let appState = AppState()
        var project = MAProject(name: "Workflow Switch")

        var firstWorkflow = Workflow(name: "First")
        firstWorkflow.nodes = [WorkflowNode(type: .start)]

        var secondWorkflow = Workflow(name: "Second")
        secondWorkflow.nodes = [WorkflowNode(type: .start)]

        project.workflows = [firstWorkflow, secondWorkflow]
        appState.currentProject = project
        appState.setActiveWorkflow(secondWorkflow.id)
        appState.addNewNode()

        let updatedProject = try? XCTUnwrap(appState.currentProject)
        XCTAssertEqual(updatedProject?.workflows.first(where: { $0.id == firstWorkflow.id })?.nodes.count, 1)
        XCTAssertEqual(updatedProject?.workflows.first(where: { $0.id == secondWorkflow.id })?.nodes.count, 2)
        XCTAssertEqual(appState.workflow(for: nil)?.id, secondWorkflow.id)
    }
}
