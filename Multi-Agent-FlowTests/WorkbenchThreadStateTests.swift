import XCTest
@testable import Multi_Agent_Flow

final class WorkbenchThreadStateTests: XCTestCase {
    private static let sharedThreadStateCoordinator = WorkbenchThreadStateCoordinator()

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
    func testOpenClawServicePreservesMultipleActiveRunsWithinSameThread() {
        let service = OpenClawService()
        let workflowID = UUID().uuidString
        let olderRecord = WorkbenchActiveRunRecord(
            threadID: "thread-shared",
            workflowID: workflowID,
            runID: "run-chat",
            sessionKey: "agent:planner:thread-shared",
            transportKind: "gateway_chat",
            executionIntent: OpenClawRuntimeExecutionIntent.conversationAutonomous.rawValue,
            startedAt: Date(timeIntervalSince1970: 1_710_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_710_000_060),
            status: .running
        )
        let newerRecord = WorkbenchActiveRunRecord(
            threadID: "thread-shared",
            workflowID: workflowID,
            runID: "run-run",
            sessionKey: "agent:planner:thread-shared:run",
            transportKind: "gateway_agent",
            executionIntent: OpenClawRuntimeExecutionIntent.workflowControlled.rawValue,
            startedAt: Date(timeIntervalSince1970: 1_710_000_090),
            updatedAt: Date(timeIntervalSince1970: 1_710_000_120),
            status: .stopping
        )

        service.restoreExecutionSnapshot(
            results: [],
            logs: [],
            activeWorkbenchRuns: [olderRecord, newerRecord]
        )

        XCTAssertEqual(service.activeWorkbenchRuns, [newerRecord, olderRecord])
        XCTAssertEqual(service.activeWorkbenchRunRecords(threadID: "thread-shared"), [newerRecord, olderRecord])
        XCTAssertEqual(service.activeWorkbenchRunRecord(threadID: "thread-shared"), newerRecord)
        XCTAssertEqual(service.activeGatewayRunID, newerRecord.runID)
        XCTAssertEqual(service.activeGatewaySessionKey, newerRecord.sessionKey)
        XCTAssertTrue(service.hasActiveRemoteConversation(threadID: "thread-shared"))
        XCTAssertTrue(service.isAbortingRemoteConversation(threadID: "thread-shared"))
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

    func testThreadSummaryAggregatesMultipleActiveRunStatusesPerThread() {
        do {
            let workflowID = UUID()
            let threadID = "thread-aggregate"
            do {
                let coordinator = Self.sharedThreadStateCoordinator
                do {
                    let context = WorkbenchThreadContext(
                        workflowID: workflowID,
                        projectSessionID: "project-session",
                        threadID: threadID,
                        sessionID: "session-1",
                        gatewaySessionKey: "agent:planner:thread-aggregate",
                        interactionMode: .chat,
                        threadType: .conversationAutonomous,
                        threadMode: .conversationToRun,
                        executionIntent: .conversationAutonomous,
                        origin: "workbench_chat",
                        agentID: UUID(),
                        agentName: "Planner"
                    )

                    do {
                        var task = Task(
                            title: "升级到受控执行",
                            description: "将当前对话线程切换到 workflow controlled run",
                            status: .inProgress,
                            priority: .high
                        )
                        task.createdAt = Date(timeIntervalSince1970: 1_710_000_100)
                        task.startedAt = task.createdAt
                        do {
                            let runningRecord = WorkbenchActiveRunRecord(
                                threadID: threadID,
                                workflowID: workflowID.uuidString,
                                runID: "run-chat",
                                sessionKey: "agent:planner:thread-aggregate",
                                transportKind: "gateway_chat",
                                executionIntent: OpenClawRuntimeExecutionIntent.conversationAutonomous.rawValue,
                                startedAt: Date(timeIntervalSince1970: 1_710_000_110),
                                updatedAt: Date(timeIntervalSince1970: 1_710_000_110),
                                status: .running
                            )
                            let stoppingRecord = WorkbenchActiveRunRecord(
                                threadID: threadID,
                                workflowID: workflowID.uuidString,
                                runID: "run-controlled",
                                sessionKey: "agent:planner:thread-aggregate:run",
                                transportKind: "gateway_agent",
                                executionIntent: OpenClawRuntimeExecutionIntent.workflowControlled.rawValue,
                                startedAt: Date(timeIntervalSince1970: 1_710_000_120),
                                updatedAt: Date(timeIntervalSince1970: 1_710_000_130),
                                status: .stopping
                            )

                            let summaryCollections = coordinator.collectSummaryCollections(
                                messageRecords: [],
                                taskRecords: [
                                    WorkbenchThreadSummaryTaskRecord(
                                        threadID: threadID,
                                        task: task,
                                        contextSample: WorkbenchThreadContextSample(
                                            context: context,
                                            activityAt: task.createdAt
                                        )
                                    )
                                ]
                            )

                            do {
                                let summaries = coordinator.summarizeThreads(
                                    workflowID: workflowID,
                                    summaryCollections: summaryCollections,
                                    activeRunRecords: [runningRecord, stoppingRecord],
                                    threadStateRecords: []
                                )

                                print("[WorkbenchThreadStateTests] summaries.count", summaries.count)
                                let firstSummary = summaries.first
                                print("[WorkbenchThreadStateTests] first.id", firstSummary?.id ?? "nil")
                                print("[WorkbenchThreadStateTests] first.threadMode", firstSummary?.threadMode.rawValue ?? "nil")
                                print("[WorkbenchThreadStateTests] first.activeRunStatus", firstSummary?.activeRunStatus?.rawValue ?? "nil")
                                print("[WorkbenchThreadStateTests] first.conversationState", firstSummary?.conversationState.rawValue ?? "nil")

                                print("[WorkbenchThreadStateTests] before assert count")
                                XCTAssertEqual(summaries.count, 1)
                                print("[WorkbenchThreadStateTests] after assert count")
                                XCTAssertEqual(firstSummary?.threadMode, .conversationToRun)
                                print("[WorkbenchThreadStateTests] after assert threadMode")
                                XCTAssertEqual(firstSummary?.activeRunStatus, .stopping)
                                print("[WorkbenchThreadStateTests] after assert activeRunStatus")
                                XCTAssertEqual(firstSummary?.conversationState, .stopping)
                                print("[WorkbenchThreadStateTests] after assert conversationState")
                            }

                            print("[WorkbenchThreadStateTests] after summaries scope")
                        }

                        print("[WorkbenchThreadStateTests] after records scope")
                    }

                    print("[WorkbenchThreadStateTests] after task scope")
                }

                print("[WorkbenchThreadStateTests] after context scope")
            }

            print("[WorkbenchThreadStateTests] after coordinator scope")
        }

        print("[WorkbenchThreadStateTests] after fixture scope")
    }

}
