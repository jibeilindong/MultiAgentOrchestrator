import XCTest
@testable import Multi_Agent_Flow

private let sharedOpenClawAttachmentDisplayTestAppState = AppState()

final class OpenClawAttachmentDisplayTests: XCTestCase {
    @MainActor
    func testAttachmentStateReportsNoProjectWhenProjectIsMissing() {
        let appState = sharedOpenClawAttachmentDisplayTestAppState
        let originalProject = appState.currentProject
        let originalConfig = appState.openClawManager.config
        let originalAttachment = appState.openClawManager.projectAttachment

        defer {
            appState.currentProject = originalProject
            appState.openClawManager.config = originalConfig
            appState.openClawManager.projectAttachment = originalAttachment
        }

        appState.currentProject = nil

        XCTAssertEqual(appState.currentProjectOpenClawAttachmentState, .noProject)
    }

    @MainActor
    func testAttachmentStateReportsRemoteRuntimeOnlyForRemoteDeployment() {
        let appState = sharedOpenClawAttachmentDisplayTestAppState
        let originalProject = appState.currentProject
        let originalConfig = appState.openClawManager.config
        let originalAttachment = appState.openClawManager.projectAttachment

        defer {
            appState.currentProject = originalProject
            appState.openClawManager.config = originalConfig
            appState.openClawManager.projectAttachment = originalAttachment
        }

        appState.currentProject = MAProject(name: "Remote Attachment")
        var config = OpenClawConfig.default
        config.deploymentKind = .remoteServer
        appState.openClawManager.config = config

        XCTAssertEqual(appState.currentProjectOpenClawAttachmentState, .remoteConnectionOnly)
    }

    @MainActor
    func testAttachmentStateReportsCurrentProjectAttachedWhenIDsMatch() {
        let appState = sharedOpenClawAttachmentDisplayTestAppState
        let originalProject = appState.currentProject
        let originalConfig = appState.openClawManager.config
        let originalAttachment = appState.openClawManager.projectAttachment

        defer {
            appState.currentProject = originalProject
            appState.openClawManager.config = originalConfig
            appState.openClawManager.projectAttachment = originalAttachment
        }

        let project = MAProject(name: "Attached Project")
        appState.currentProject = project
        appState.openClawManager.projectAttachment = OpenClawProjectAttachmentSnapshot(
            state: .attached,
            projectID: project.id,
            attachedAt: Date()
        )

        XCTAssertEqual(appState.currentProjectOpenClawAttachmentState, .attachedCurrentProject)
        XCTAssertTrue(appState.isCurrentProjectAttachedToOpenClaw)
    }

    @MainActor
    func testAttachmentStateReportsOtherProjectAttachedWhenIDsDiffer() {
        let appState = sharedOpenClawAttachmentDisplayTestAppState
        let originalProject = appState.currentProject
        let originalConfig = appState.openClawManager.config
        let originalAttachment = appState.openClawManager.projectAttachment

        defer {
            appState.currentProject = originalProject
            appState.openClawManager.config = originalConfig
            appState.openClawManager.projectAttachment = originalAttachment
        }

        appState.currentProject = MAProject(name: "Current Project")
        appState.openClawManager.projectAttachment = OpenClawProjectAttachmentSnapshot(
            state: .attached,
            projectID: UUID(),
            attachedAt: Date()
        )

        XCTAssertEqual(appState.currentProjectOpenClawAttachmentState, .attachedDifferentProject)
        XCTAssertFalse(appState.isCurrentProjectAttachedToOpenClaw)
        XCTAssertFalse(appState.hasPendingOpenClawSessionSync)
    }

    @MainActor
    func testAppStateReportsManagedRuntimeSourceForAppManagedLocalRuntime() {
        let appState = sharedOpenClawAttachmentDisplayTestAppState
        let originalProject = appState.currentProject
        let originalConfig = appState.openClawManager.config
        let originalAttachment = appState.openClawManager.projectAttachment
        let originalManagedRuntimeStatus = appState.openClawManager.managedRuntimeStatus

        defer {
            appState.currentProject = originalProject
            appState.openClawManager.config = originalConfig
            appState.openClawManager.projectAttachment = originalAttachment
            appState.openClawManager.managedRuntimeStatus = originalManagedRuntimeStatus
        }

        var config = OpenClawConfig.default
        config.deploymentKind = .local
        config.runtimeOwnership = .appManaged
        config.host = "127.0.0.1"
        config.port = 18789
        appState.openClawManager.config = config
        appState.openClawManager.managedRuntimeStatus = OpenClawManagedRuntimeStatusSnapshot(
            state: .running,
            binaryPath: "/managed/runtime/bin/openclaw",
            requestedPort: 18789,
            port: 18792
        )

        XCTAssertEqual(appState.openClawRuntimeSourceBadgeTitle, "App Managed")
        XCTAssertEqual(appState.openClawRuntimeSourceSummary, "应用私有 OpenClaw Sidecar")
        XCTAssertEqual(appState.openClawRuntimeSourceEndpoint, "ws://127.0.0.1:18792")
        XCTAssertEqual(appState.openClawRuntimeSourceBinaryPath, "/managed/runtime/bin/openclaw")
        XCTAssertTrue(appState.openClawRuntimeSourceDetail.contains("不会复用 ~/.openclaw"))
    }

    @MainActor
    func testAppStateReportsExternalLocalRuntimeSourceForExplicitBinaryMode() {
        let appState = sharedOpenClawAttachmentDisplayTestAppState
        let originalProject = appState.currentProject
        let originalConfig = appState.openClawManager.config
        let originalAttachment = appState.openClawManager.projectAttachment
        let originalManagedRuntimeStatus = appState.openClawManager.managedRuntimeStatus

        defer {
            appState.currentProject = originalProject
            appState.openClawManager.config = originalConfig
            appState.openClawManager.projectAttachment = originalAttachment
            appState.openClawManager.managedRuntimeStatus = originalManagedRuntimeStatus
        }

        var config = OpenClawConfig.default
        config.deploymentKind = .local
        config.runtimeOwnership = .externalLocal
        config.host = "127.0.0.1"
        config.port = 28888
        config.localBinaryPath = "/custom/openclaw/bin/openclaw"
        appState.openClawManager.config = config

        XCTAssertEqual(appState.openClawRuntimeSourceBadgeTitle, "External Local")
        XCTAssertEqual(appState.openClawRuntimeSourceSummary, "用户本地 OpenClaw Binary")
        XCTAssertEqual(appState.openClawRuntimeSourceEndpoint, "ws://127.0.0.1:28888")
        XCTAssertEqual(appState.openClawRuntimeSourceBinaryPath, "/custom/openclaw/bin/openclaw")
        XCTAssertTrue(appState.openClawRuntimeSourceDetail.contains("固定使用用户提供的本地 openclaw binary"))
    }
}
