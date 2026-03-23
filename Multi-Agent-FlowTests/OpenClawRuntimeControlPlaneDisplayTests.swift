import XCTest
@testable import Multi_Agent_Flow

private let sharedOpenClawRuntimeControlPlaneTestAppState = AppState()

final class OpenClawRuntimeControlPlaneDisplayTests: XCTestCase {
    @MainActor
    func testExecuteSummaryExplainsConversationCanContinueWhileRunControlledIsBlocked() {
        let appState = sharedOpenClawRuntimeControlPlaneTestAppState
        let manager = appState.openClawManager

        let originalConfig = manager.config
        let originalConnectionState = manager.connectionState
        let originalProjectAttachment = manager.projectAttachment
        let originalSessionLifecycle = manager.sessionLifecycle
        let originalProject = appState.currentProject

        defer {
            manager.config = originalConfig
            manager.connectionState = originalConnectionState
            manager.projectAttachment = originalProjectAttachment
            manager.sessionLifecycle = originalSessionLifecycle
            appState.currentProject = originalProject
        }

        manager.config = .default
        manager.connectionState = OpenClawConnectionStateSnapshot(
            phase: .ready,
            deploymentKind: .local,
            capabilities: OpenClawConnectionCapabilitiesSnapshot(
                gatewayReachable: true,
                gatewayAuthenticated: true,
                gatewayChatAvailable: true,
                projectAttachmentSupported: true
            )
        )

        var project = MAProject(name: "Control Plane Execute")
        project.runtimeState.workflowConfigurationRevision = 3
        project.runtimeState.appliedToMirrorConfigurationRevision = 3
        project.runtimeState.syncedToRuntimeConfigurationRevision = 2
        project.runtimeState.latestRuntimeSyncReceipt = makeBlockedSyncReceipt()
        appState.currentProject = project

        manager.projectAttachment = OpenClawProjectAttachmentSnapshot(
            state: .attached,
            projectID: project.id,
            attachedAt: Date()
        )
        manager.sessionLifecycle = OpenClawSessionLifecycleSnapshot(
            stage: .synced,
            hasPendingMirrorChanges: false
        )

        XCTAssertEqual(appState.currentOpenClawRuntimeControlPlaneEntry.gate, .publish)
        XCTAssertEqual(
            appState.openClawRuntimeControlPlaneSummary,
            "聊天模式可以继续，但 run.controlled 当前仍被阻塞：当前 run.controlled 需要先完成 persistent publish：项目镜像 staging 不完整，已阻止本次运行时写回。"
        )
        XCTAssertEqual(
            appState.openClawRuntimeControlPlaneSecondarySummary,
            "当前 run.controlled 需要先完成 persistent publish：项目镜像 staging 不完整，已阻止本次运行时写回。"
        )
    }

    @MainActor
    func testPublishSummaryUsesBlockingMessageFromLatestSyncReceipt() {
        let appState = sharedOpenClawRuntimeControlPlaneTestAppState
        let manager = appState.openClawManager

        let originalConfig = manager.config
        let originalConnectionState = manager.connectionState
        let originalProjectAttachment = manager.projectAttachment
        let originalSessionLifecycle = manager.sessionLifecycle
        let originalProject = appState.currentProject

        defer {
            manager.config = originalConfig
            manager.connectionState = originalConnectionState
            manager.projectAttachment = originalProjectAttachment
            manager.sessionLifecycle = originalSessionLifecycle
            appState.currentProject = originalProject
        }

        manager.config = .default
        manager.connectionState = OpenClawConnectionStateSnapshot(
            phase: .ready,
            deploymentKind: .local,
            capabilities: OpenClawConnectionCapabilitiesSnapshot(
                projectAttachmentSupported: true
            )
        )

        var project = MAProject(name: "Control Plane Publish")
        project.runtimeState.workflowConfigurationRevision = 5
        project.runtimeState.appliedToMirrorConfigurationRevision = 5
        project.runtimeState.syncedToRuntimeConfigurationRevision = 4
        project.runtimeState.latestRuntimeSyncReceipt = makeBlockedSyncReceipt()
        appState.currentProject = project

        manager.projectAttachment = OpenClawProjectAttachmentSnapshot(
            state: .attached,
            projectID: project.id,
            attachedAt: Date()
        )
        manager.sessionLifecycle = OpenClawSessionLifecycleSnapshot(
            stage: .synced,
            hasPendingMirrorChanges: false
        )

        XCTAssertEqual(appState.currentOpenClawRuntimeControlPlaneEntry.gate, .publish)
        XCTAssertEqual(
            appState.openClawRuntimeControlPlaneSummary,
            "当前 run.controlled 需要先完成 persistent publish：项目镜像 staging 不完整，已阻止本次运行时写回。"
        )
        XCTAssertEqual(
            appState.openClawRuntimeControlPlaneSecondarySummary,
            "项目镜像 staging 不完整，已阻止本次运行时写回。"
        )
    }

    private func makeBlockedSyncReceipt() -> OpenClawRuntimeSyncReceipt {
        OpenClawRuntimeSyncReceipt(
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
    }
}
