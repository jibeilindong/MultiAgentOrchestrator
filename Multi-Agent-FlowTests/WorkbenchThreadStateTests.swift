import XCTest
@testable import Multi_Agent_Flow

final class WorkbenchThreadStateTests: XCTestCase {
    @MainActor
    func testOpenClawServiceRestoresActiveWorkbenchRunsIntoThreadRegistry() {
        let service = OpenClawService()
        let runRecord = WorkbenchActiveRunRecord(
            threadID: "thread-restore",
            workflowID: UUID().uuidString,
            runID: "run-restore",
            sessionKey: "agent:planner:thread-restore",
            transportKind: "gateway_chat",
            executionIntent: OpenClawRuntimeExecutionIntent.conversationAutonomous.rawValue,
            startedAt: Date(timeIntervalSince1970: 1_710_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_710_000_120),
            status: .stopping
        )

        service.restoreExecutionSnapshot(
            results: [],
            logs: [],
            activeWorkbenchRuns: [runRecord]
        )

        XCTAssertEqual(service.activeWorkbenchRuns, [runRecord])
        XCTAssertTrue(service.hasActiveRemoteConversation(threadID: runRecord.threadID))
        XCTAssertTrue(service.isAbortingRemoteConversation(threadID: runRecord.threadID))
        XCTAssertEqual(service.activeWorkbenchRunRecord(threadID: runRecord.threadID), runRecord)
        XCTAssertEqual(service.activeGatewayRunID, runRecord.runID)
        XCTAssertEqual(service.activeGatewaySessionKey, runRecord.sessionKey)
        XCTAssertTrue(service.isAbortingActiveGatewayRun)
    }

    @MainActor
    func testWorkbenchThreadSummariesExposeActiveRunStatus() {
        let appState = AppState()
        let agent = Agent(name: "planner-agent-1")
        var project = MAProject(name: "Workbench Thread Summary Test")
        project.agents = [agent]

        let workflowID = try! XCTUnwrap(project.workflows.first?.id)
        let threadID = "thread-summary-running"
        let sessionID = "session-summary-running"
        let gatewaySessionKey = "agent:planner-agent-1:thread-summary-running"

        appState.currentProject = project
        appState.openClawService.restoreExecutionSnapshot(
            results: [],
            logs: [],
            activeWorkbenchRuns: [
                WorkbenchActiveRunRecord(
                    threadID: threadID,
                    workflowID: workflowID.uuidString,
                    runID: "run-summary-running",
                    sessionKey: gatewaySessionKey,
                    transportKind: "gateway_chat",
                    executionIntent: OpenClawRuntimeExecutionIntent.conversationAutonomous.rawValue,
                    startedAt: Date(timeIntervalSince1970: 1_710_000_000),
                    updatedAt: Date(timeIntervalSince1970: 1_710_000_060),
                    status: .running
                )
            ]
        )

        var message = Message(from: agent.id, to: agent.id, type: .task, content: "Assess the current workbench state")
        message.status = .read
        message.timestamp = Date(timeIntervalSince1970: 1_710_000_120)
        message.metadata = [
            WorkbenchMetadataKey.channel: "workbench",
            WorkbenchMetadataKey.workflowID: workflowID.uuidString,
            WorkbenchMetadataKey.workbenchSessionID: sessionID,
            WorkbenchMetadataKey.workbenchThreadID: threadID,
            WorkbenchMetadataKey.workbenchThreadType: RuntimeSessionSemanticType.conversationAutonomous.rawValue,
            WorkbenchMetadataKey.workbenchThreadMode: WorkbenchThreadSemanticMode.autonomousConversation.rawValue,
            WorkbenchMetadataKey.workbenchEntryAgentID: agent.id.uuidString,
            WorkbenchMetadataKey.workbenchProjectSessionID: project.runtimeState.sessionID,
            WorkbenchMetadataKey.workbenchGatewaySessionKey: gatewaySessionKey,
            WorkbenchMetadataKey.workbenchMode: WorkbenchInteractionMode.chat.rawValue,
            "role": "user",
            "kind": "input"
        ]
        appState.messageManager.replaceMessages([message])

        let summaries = appState.workbenchThreadSummaries(for: workflowID)
        let summary = try! XCTUnwrap(summaries.first)

        XCTAssertEqual(summary.id, threadID)
        XCTAssertEqual(summary.activeRunStatus, .running)
        XCTAssertTrue(summary.subtitle.contains("running"))
        XCTAssertEqual(summary.entryAgentName, agent.name)
        XCTAssertEqual(summary.messageCount, 1)
    }
}
