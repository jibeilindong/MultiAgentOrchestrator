import XCTest
@testable import Multi_Agent_Flow

final class WorkflowApplyStatusTests: XCTestCase {
    func testPendingWorkflowConfigurationUsesPositiveRevisionDifference() {
        var runtimeState = RuntimeState()
        runtimeState.workflowConfigurationRevision = 7
        runtimeState.appliedToMirrorConfigurationRevision = 4

        XCTAssertTrue(AppState.hasPendingWorkflowConfiguration(runtimeState))
        XCTAssertEqual(AppState.pendingWorkflowConfigurationRevisionDelta(runtimeState), 3)
    }

    func testPendingWorkflowConfigurationIsClearedWhenRevisionsMatch() {
        var runtimeState = RuntimeState()
        runtimeState.workflowConfigurationRevision = 5
        runtimeState.appliedToMirrorConfigurationRevision = 5

        XCTAssertFalse(AppState.hasPendingWorkflowConfiguration(runtimeState))
        XCTAssertEqual(AppState.pendingWorkflowConfigurationRevisionDelta(runtimeState), 0)
    }

    func testPendingWorkflowConfigurationIgnoresAppliedRevisionAheadAnomaly() {
        var runtimeState = RuntimeState()
        runtimeState.workflowConfigurationRevision = 3
        runtimeState.appliedToMirrorConfigurationRevision = 5

        XCTAssertFalse(AppState.hasPendingWorkflowConfiguration(runtimeState))
        XCTAssertEqual(AppState.pendingWorkflowConfigurationRevisionDelta(runtimeState), 0)
    }

    func testPendingRuntimeSyncUsesMirrorAndRuntimeRevisionDifference() {
        var runtimeState = RuntimeState()
        runtimeState.appliedToMirrorConfigurationRevision = 6
        runtimeState.syncedToRuntimeConfigurationRevision = 4

        XCTAssertEqual(AppState.pendingOpenClawRuntimeSyncRevisionDelta(runtimeState), 2)
    }

    func testRuntimeStateDecodesLegacyAppliedRevisionIntoMirrorRevision() throws {
        let json = """
        {
          "sessionID": "legacy-session",
          "messageQueue": [],
          "dispatchQueue": [],
          "inflightDispatches": [],
          "completedDispatches": [],
          "failedDispatches": [],
          "agentStates": {},
          "runtimeEvents": [],
          "workflowConfigurationRevision": 5,
          "appliedWorkflowConfigurationRevision": 3
        }
        """

        let data = try XCTUnwrap(json.data(using: .utf8))
        let runtimeState = try JSONDecoder().decode(RuntimeState.self, from: data)

        XCTAssertEqual(runtimeState.workflowConfigurationRevision, 5)
        XCTAssertEqual(runtimeState.appliedToMirrorConfigurationRevision, 3)
        XCTAssertEqual(runtimeState.syncedToRuntimeConfigurationRevision, 0)
        XCTAssertNil(runtimeState.latestRuntimeSyncReceipt)
        XCTAssertTrue(runtimeState.recentRuntimeSyncReceipts.isEmpty)
    }

    func testRuntimeSyncReceiptPrimaryIssuePrefersFailedStepMessage() {
        let receipt = OpenClawRuntimeSyncReceipt(
            projectID: UUID(),
            requestedMirrorRevision: 6,
            appliedRuntimeRevision: 4,
            status: .partial,
            steps: [
                OpenClawRuntimeSyncStepReceipt(
                    step: .stageProjectMirror,
                    status: .succeeded,
                    message: "stage ok"
                ),
                OpenClawRuntimeSyncStepReceipt(
                    step: .syncCommunicationAllowList,
                    status: .failed,
                    message: "allow list failed"
                )
            ],
            warnings: ["warning text"],
            errorMessage: "fallback error"
        )

        XCTAssertEqual(receipt.primaryIssueMessage, "allow list failed")
    }

    func testRuntimeSyncReceiptExposesBlockedReasonAndNonBlockedIssueSteps() {
        let receipt = OpenClawRuntimeSyncReceipt(
            projectID: UUID(),
            requestedMirrorRevision: 9,
            appliedRuntimeRevision: 6,
            status: .partial,
            steps: [
                OpenClawRuntimeSyncStepReceipt(
                    step: .stageProjectMirror,
                    status: .partial,
                    message: "planner 的 SOUL 路径未解析"
                ),
                OpenClawRuntimeSyncStepReceipt(
                    step: .writeRuntimeSession,
                    status: .skipped,
                    message: "项目镜像 staging 不完整，已阻止本次运行时写回。"
                ),
                OpenClawRuntimeSyncStepReceipt(
                    step: .syncCommunicationAllowList,
                    status: .skipped,
                    message: "运行时写回未完成，已跳过通信 allow list 同步。"
                )
            ],
            warnings: ["以下 agent 的 SOUL 路径未能解析"]
        )

        XCTAssertEqual(receipt.blockedReasonMessage, "项目镜像 staging 不完整，已阻止本次运行时写回。")
        XCTAssertEqual(
            receipt.issueStepsExcludingBlockedReason.map(\.step),
            [.stageProjectMirror, .syncCommunicationAllowList]
        )
        XCTAssertEqual(receipt.normalizedWarnings, ["以下 agent 的 SOUL 路径未能解析"])
    }

    func testRuntimeStatePersistsLatestRuntimeSyncReceipt() throws {
        let receipt = OpenClawRuntimeSyncReceipt(
            projectID: UUID(),
            requestedMirrorRevision: 8,
            appliedRuntimeRevision: 5,
            status: .partial,
            steps: [
                OpenClawRuntimeSyncStepReceipt(
                    step: .writeRuntimeSession,
                    status: .partial,
                    message: "运行时未在线，暂未写回。"
                )
            ]
        )

        var runtimeState = RuntimeState()
        runtimeState.latestRuntimeSyncReceipt = receipt
        runtimeState.recentRuntimeSyncReceipts = [receipt]

        let data = try JSONEncoder().encode(runtimeState)
        let decoded = try JSONDecoder().decode(RuntimeState.self, from: data)

        XCTAssertEqual(decoded.latestRuntimeSyncReceipt, receipt)
        XCTAssertEqual(decoded.recentRuntimeSyncReceipts, [receipt])
    }
}
