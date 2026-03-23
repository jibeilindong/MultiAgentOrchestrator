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

    func testConversationStateResolverPrefersActiveRunStatusOverAssistantMessages() {
        let state = WorkbenchConversationStateResolver.resolve(
            WorkbenchConversationStateDerivationInput(
                interactionMode: .chat,
                threadMode: .autonomousConversation,
                latestTaskStatus: nil,
                latestUserMessageAt: Date(timeIntervalSince1970: 1_710_000_000),
                latestAssistantMessageAt: Date(timeIntervalSince1970: 1_710_000_060),
                latestAssistantThinking: false,
                latestAssistantOutputType: nil,
                hasRunActivity: false,
                activeRunStatus: .running,
                explicitState: .readyToRun
            )
        )

        XCTAssertEqual(state, .running)
    }

    func testConversationStateResolverReturnsReadyToRunAfterAssistantReply() {
        let state = WorkbenchConversationStateResolver.resolve(
            WorkbenchConversationStateDerivationInput(
                interactionMode: .chat,
                threadMode: .autonomousConversation,
                latestTaskStatus: nil,
                latestUserMessageAt: Date(timeIntervalSince1970: 1_710_000_000),
                latestAssistantMessageAt: Date(timeIntervalSince1970: 1_710_000_060),
                latestAssistantThinking: false,
                latestAssistantOutputType: nil,
                hasRunActivity: false,
                activeRunStatus: nil,
                explicitState: nil
            )
        )

        XCTAssertEqual(state, .readyToRun)
    }

    func testPreferredThreadModePromotesMixedChatAndRunHistoryToConversationToRun() {
        let preferredMode = WorkbenchThreadSemanticMode.preferredMode(
            from: [.autonomousConversation, .controlledRun]
        )

        XCTAssertEqual(preferredMode, .conversationToRun)
    }

    func testThreadTransitionResolverMarksStopRequestedThreadsAsStopping() {
        let resolution = WorkbenchThreadTransitionResolver.resolve(
            .stopRequested,
            interactionMode: .chat,
            threadMode: .conversationToRun
        )

        XCTAssertEqual(resolution.interactionMode, .chat)
        XCTAssertEqual(resolution.threadMode, .conversationToRun)
        XCTAssertEqual(resolution.state, .stopping)
        XCTAssertNil(resolution.errorMessage)
    }

    func testWorkbenchFlowLifecycleCoordinatorReturnsReadyToRunWhenEntryCompletesWithoutBackgroundNodes() {
        let coordinator = WorkbenchFlowLifecycleCoordinator()
        let result = makeExecutionResult(status: .completed, output: "done", summary: "Entry complete")

        let disposition = coordinator.chatEntryDisposition(for: result, hasBackgroundNodes: false)

        XCTAssertEqual(disposition, .readyToRun)
    }

    func testWorkbenchFlowLifecycleCoordinatorReturnsFailedDispositionForFailedEntry() {
        let coordinator = WorkbenchFlowLifecycleCoordinator()
        let result = makeExecutionResult(status: .failed, output: "error", summary: "Entry failed")

        let disposition = coordinator.chatEntryDisposition(for: result, hasBackgroundNodes: true)

        XCTAssertEqual(disposition, .failed(errorMessage: "Entry failed"))
    }

    func testWorkbenchFlowLifecycleCoordinatorBuildsSuccessfulRunPresentation() {
        let coordinator = WorkbenchFlowLifecycleCoordinator()
        let results = [
            makeExecutionResult(status: .completed, output: "ok", summary: "Node A complete"),
            makeExecutionResult(status: .completed, output: "ok", summary: "Node B complete")
        ]

        let presentation = coordinator.workflowRunPresentation(for: results)

        XCTAssertEqual(presentation.taskStatus, .done)
        if case let .completed(interactionMode, threadMode) = presentation.terminalTransition {
            XCTAssertEqual(interactionMode, .run)
            XCTAssertEqual(threadMode, .controlledRun)
        } else {
            XCTFail("Expected completed transition")
        }
        XCTAssertEqual(presentation.messageType, .notification)
        XCTAssertEqual(presentation.outputType, .agentFinalResponse)
        XCTAssertTrue(presentation.summaryText.contains("2 succeeded, 0 failed"))
    }

    func testWorkbenchFlowLifecycleCoordinatorBuildsFailedRunPresentation() {
        let coordinator = WorkbenchFlowLifecycleCoordinator()
        let results = [
            makeExecutionResult(status: .completed, output: "ok", summary: "Node A complete"),
            makeExecutionResult(status: .failed, output: "error", summary: "Node B failed")
        ]

        let presentation = coordinator.workflowRunPresentation(for: results)

        XCTAssertEqual(presentation.taskStatus, .blocked)
        if case let .failed(errorMessage, interactionMode, threadMode) = presentation.terminalTransition {
            XCTAssertEqual(errorMessage, "Node B failed")
            XCTAssertEqual(interactionMode, .run)
            XCTAssertEqual(threadMode, .controlledRun)
        } else {
            XCTFail("Expected failed transition")
        }
        XCTAssertEqual(presentation.messageType, .data)
        XCTAssertEqual(presentation.outputType, .errorSummary)
        XCTAssertTrue(presentation.summaryText.contains("Failure: Node B failed"))
    }
}

private extension WorkbenchThreadStateTests {
    func makeExecutionResult(
        status: ExecutionStatus,
        output: String,
        summary: String
    ) -> ExecutionResult {
        let event = OpenClawRuntimeEvent(
            eventType: status == .failed ? .taskError : .taskResult,
            source: OpenClawRuntimeActor(kind: .agent, agentId: "agent-1", agentName: "Planner"),
            target: OpenClawRuntimeActor(kind: .user, agentId: "user", agentName: "User"),
            transport: OpenClawRuntimeTransport(kind: .gatewayChat, deploymentKind: "local"),
            payload: ["summary": summary]
        )
        return ExecutionResult(
            nodeID: UUID(),
            agentID: UUID(),
            status: status,
            output: output,
            outputType: status == .failed ? .errorSummary : .agentFinalResponse,
            runtimeEvents: [event],
            primaryRuntimeEvent: event
        )
    }
}
