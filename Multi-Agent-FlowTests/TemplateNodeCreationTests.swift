import XCTest
@testable import Multi_Agent_Flow

final class TemplateNodeCreationTests: XCTestCase {
    @MainActor
    func testFocusAgentNodeSelectsWorkflowNodeBoundToAgent() throws {
        let appState = AppState()
        appState.currentProject = MAProject(name: "Template Selection Test")

        let agent = try XCTUnwrap(appState.addNewAgent(named: "模板智能体"))
        let nodeID = try XCTUnwrap(
            appState.focusAgentNode(
                agentID: agent.id,
                createIfMissing: true,
                suggestedPosition: CGPoint(x: 300, y: 200)
            )
        )

        XCTAssertEqual(appState.selectedNodeID, nodeID)
        XCTAssertNotEqual(appState.selectedNodeID, agent.id)
        XCTAssertEqual(
            appState.currentProject?.workflows.first?.nodes.first(where: { $0.id == nodeID })?.agentID,
            agent.id
        )
    }

    func testResolvedNewAgentNameUsesTemplateNameForDefaultCreation() throws {
        let template = try XCTUnwrap(AgentTemplateCatalog.templates.first)
        XCTAssertEqual(
            AppState.resolvedNewAgentName(template: template, existingAgents: []),
            Agent.normalizedName(requestedName: template.name, existingAgents: [])
        )
    }

    func testResolvedNewAgentNameKeepsExplicitNameWhenTemplateIsApplied() throws {
        let template = try XCTUnwrap(AgentTemplateCatalog.templates.first)
        let customName = "自定义名称"

        XCTAssertEqual(
            AppState.resolvedNewAgentName(
                requestedName: customName,
                template: template,
                existingAgents: []
            ),
            Agent.normalizedName(requestedName: customName, existingAgents: [])
        )
    }

    func testApplyTemplateCopiesTemplateContentToAgent() throws {
        let template = try XCTUnwrap(AgentTemplateCatalog.templates.first)
        let resolvedName = AppState.resolvedNewAgentName(template: template, existingAgents: [])
        var agent = Agent(name: resolvedName)

        agent.apply(template: template)

        XCTAssertEqual(agent.name, resolvedName)
        XCTAssertEqual(agent.identity, template.identity)
        XCTAssertEqual(agent.description, template.summary)
        XCTAssertEqual(agent.soulMD, template.soulMD)
        XCTAssertEqual(agent.capabilities, template.capabilities)
        XCTAssertEqual(agent.colorHex, template.colorHex)
    }

    func testPreparedMirroredAgentForProjectMirrorSetsIndependentSoulAndPrivatePaths() {
        let importedAt = Date(timeIntervalSince1970: 1_710_000_000)
        let soulPath = "/tmp/project/agents/test-agent-1/SOUL.md"
        let privateRootPath = "/tmp/project/agents/test-agent-1/private"
        let agent = Agent(name: "测试-任务-1")

        let mirrored = AppState.preparedMirroredAgentForProjectMirror(
            agent: agent,
            soulPath: soulPath,
            privateRootPath: privateRootPath,
            importedAt: importedAt
        )

        XCTAssertEqual(mirrored.openClawDefinition.soulSourcePath, soulPath)
        XCTAssertEqual(mirrored.openClawDefinition.lastImportedSoulPath, soulPath)
        XCTAssertEqual(mirrored.openClawDefinition.lastImportedAt, importedAt)
        XCTAssertEqual(mirrored.openClawDefinition.memoryBackupPath, privateRootPath)
    }

    func testPreparedDraftAgentForDeferredMaterializationClearsRealPaths() {
        var agent = Agent(name: "测试-任务-1")
        agent.openClawDefinition.agentIdentifier = "旧标识"
        agent.openClawDefinition.soulSourcePath = "/tmp/existing/SOUL.md"
        agent.openClawDefinition.lastImportedSoulPath = "/tmp/existing/SOUL.md"
        agent.openClawDefinition.lastImportedAt = Date(timeIntervalSince1970: 1_700_000_000)
        agent.openClawDefinition.memoryBackupPath = "/tmp/existing/private"

        let draft = AppState.preparedDraftAgentForDeferredMaterialization(
            agent,
            agentIdentifier: "新标识"
        )

        XCTAssertEqual(draft.openClawDefinition.agentIdentifier, "新标识")
        XCTAssertNil(draft.openClawDefinition.soulSourcePath)
        XCTAssertNil(draft.openClawDefinition.lastImportedSoulPath)
        XCTAssertNil(draft.openClawDefinition.lastImportedAt)
        XCTAssertNil(draft.openClawDefinition.memoryBackupPath)
    }
}
