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
}
