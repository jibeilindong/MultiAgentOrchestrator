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

}
