import XCTest
@testable import Multi_Agent_Flow

final class OpenClawServiceAdmissionTests: XCTestCase {
    func testPersistentPublishBlockingMessageUsesBlockedReasonWhenRuntimeWriteStepIsBlocked() {
        let receipt = OpenClawRuntimeSyncReceipt(
            projectID: UUID(),
            requestedMirrorRevision: 3,
            appliedRuntimeRevision: 2,
            status: .partial,
            steps: [
                OpenClawRuntimeSyncStepReceipt(
                    step: .writeRuntimeSession,
                    status: .skipped,
                    message: "项目镜像 staging 不完整，已阻止本次运行时写回。"
                )
            ]
        )

        let message = OpenClawService.persistentPublishBlockingMessage(latestSyncReceipt: receipt)

        XCTAssertEqual(
            message,
            "当前 run.controlled 需要先完成 persistent publish：项目镜像 staging 不完整，已阻止本次运行时写回。"
        )
    }

    func testPersistentPublishBlockingMessageUsesPrimaryIssueWhenSyncFailedWithoutBlockedReason() {
        let receipt = OpenClawRuntimeSyncReceipt(
            projectID: UUID(),
            requestedMirrorRevision: 4,
            appliedRuntimeRevision: 3,
            status: .failed,
            steps: [
                OpenClawRuntimeSyncStepReceipt(
                    step: .stageProjectMirror,
                    status: .succeeded,
                    message: "项目镜像已是最新。"
                ),
                OpenClawRuntimeSyncStepReceipt(
                    step: .writeRuntimeSession,
                    status: .succeeded,
                    message: "项目镜像已同步到当前 OpenClaw 会话。"
                ),
                OpenClawRuntimeSyncStepReceipt(
                    step: .syncCommunicationAllowList,
                    status: .failed,
                    message: "allow list failed"
                )
            ],
            errorMessage: "allow list failed"
        )

        let message = OpenClawService.persistentPublishBlockingMessage(latestSyncReceipt: receipt)

        XCTAssertEqual(
            message,
            "当前 run.controlled 需要先完成 persistent publish：最近一次“同步当前会话”未完成。allow list failed"
        )
    }

    func testPersistentPublishBlockingMessageFallsBackToDefaultWhenReceiptIsMissing() {
        let message = OpenClawService.persistentPublishBlockingMessage(latestSyncReceipt: nil)

        XCTAssertEqual(
            message,
            "当前 run.controlled 需要先完成 persistent publish：请先执行“同步当前会话”，把最新项目镜像写入运行时会话。"
        )
    }

    func testRuntimeSyncReceiptDetectsReadOnlyDeploymentFailures() {
        let receipt = OpenClawRuntimeSyncReceipt(
            projectID: UUID(),
            requestedMirrorRevision: 5,
            appliedRuntimeRevision: 0,
            status: .failed,
            steps: [
                OpenClawRuntimeSyncStepReceipt(
                    step: .writeRuntimeSession,
                    status: .failed,
                    message: "同步项目镜像到 OpenClaw 会话失败: You can’t save the file “dist” because the volume is read only."
                )
            ],
            errorMessage: "同步项目镜像到 OpenClaw 会话失败: You can’t save the file “dist” because the volume is read only."
        )

        XCTAssertTrue(receipt.indicatesReadOnlyDeploymentFailure)
    }

    func testRuntimeSyncReceiptTreatsWarningOnlySuccessfulPublishAsNonBlocking() {
        let receipt = OpenClawRuntimeSyncReceipt(
            projectID: UUID(),
            requestedMirrorRevision: 8,
            appliedRuntimeRevision: 8,
            status: .partial,
            steps: [
                OpenClawRuntimeSyncStepReceipt(
                    step: .stageProjectMirror,
                    status: .succeeded,
                    message: "已更新 2 个 agent 的项目镜像。"
                ),
                OpenClawRuntimeSyncStepReceipt(
                    step: .writeRuntimeSession,
                    status: .succeeded,
                    message: "已成功写回当前运行时会话。"
                ),
                OpenClawRuntimeSyncStepReceipt(
                    step: .syncCommunicationAllowList,
                    status: .succeeded,
                    message: "allow list 已同步。"
                )
            ],
            warnings: [
                "以下 agent 未绑定到当前 workflow 节点，已跳过自动注册：Coordinator-任务领域-1"
            ]
        )

        XCTAssertTrue(receipt.isWarningOnlySuccessfulPublish)
    }
}
