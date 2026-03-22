import XCTest
import CoreGraphics
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

    @MainActor
    func testInstantiateTemplatePayloadCreatesNodeBoundToTemplateAgent() throws {
        let appState = AppState()
        appState.currentProject = MAProject(name: "Template Payload Test")
        let template = try XCTUnwrap(AgentTemplateCatalog.templates.first)

        let instantiated = try XCTUnwrap(
            appState.instantiateAgentNodeFromPalettePayload(
                "template:\(template.id)",
                position: CGPoint(x: 240, y: 180)
            )
        )

        XCTAssertEqual(instantiated.agent.soulMD, template.soulMD)
        XCTAssertEqual(
            appState.currentProject?.workflows.first?.nodes.first(where: { $0.id == instantiated.nodeID })?.agentID,
            instantiated.agent.id
        )
    }

    @MainActor
    func testInstantiateProjectAgentPayloadDuplicatesAgentSoulContent() throws {
        let appState = AppState()
        appState.currentProject = MAProject(name: "Project Agent Payload Test")

        let sourceAgent = try XCTUnwrap(appState.addNewAgent(named: "源智能体"))
        var updatedSourceAgent = sourceAgent
        updatedSourceAgent.soulMD = "# 源智能体\n\n复制这份 soul。"
        appState.updateAgent(updatedSourceAgent, reload: false)

        let instantiated = try XCTUnwrap(
            appState.instantiateAgentNodeFromPalettePayload(
                "projectAgent:\(sourceAgent.id.uuidString)",
                position: CGPoint(x: 320, y: 220)
            )
        )

        XCTAssertNotEqual(instantiated.agent.id, sourceAgent.id)
        XCTAssertEqual(instantiated.agent.soulMD, updatedSourceAgent.soulMD)
        XCTAssertEqual(
            appState.currentProject?.workflows.first?.nodes.first(where: { $0.id == instantiated.nodeID })?.agentID,
            instantiated.agent.id
        )
    }

    @MainActor
    func testDeleteAgentClearsSelectedNodeAndRemovesBoundWorkflowNode() throws {
        let appState = AppState()
        appState.currentProject = MAProject(name: "Delete Agent Selection Test")

        let agent = try XCTUnwrap(appState.addNewAgent(named: "待删除智能体"))
        let nodeID = try XCTUnwrap(
            appState.focusAgentNode(
                agentID: agent.id,
                createIfMissing: true,
                suggestedPosition: CGPoint(x: 200, y: 160)
            )
        )

        XCTAssertEqual(appState.selectedNodeID, nodeID)

        appState.deleteAgent(agent.id)

        XCTAssertNil(appState.selectedNodeID)
        XCTAssertFalse(appState.currentProject?.agents.contains(where: { $0.id == agent.id }) ?? true)
        XCTAssertFalse(appState.currentProject?.workflows.first?.nodes.contains(where: { $0.id == nodeID }) ?? true)
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
