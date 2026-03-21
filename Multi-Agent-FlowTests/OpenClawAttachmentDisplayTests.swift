import XCTest
@testable import Multi_Agent_Flow

final class OpenClawAttachmentDisplayTests: XCTestCase {
    @MainActor
    func testAttachmentStateReportsNoProjectWhenProjectIsMissing() {
        let appState = AppState()

        XCTAssertEqual(appState.currentProjectOpenClawAttachmentState, .noProject)
    }

    @MainActor
    func testAttachmentStateReportsRemoteRuntimeOnlyForRemoteDeployment() {
        let appState = AppState()
        appState.currentProject = MAProject(name: "Remote Attachment")
        var config = OpenClawConfig.default
        config.deploymentKind = .remoteServer
        appState.openClawManager.config = config

        XCTAssertEqual(appState.currentProjectOpenClawAttachmentState, .remoteConnectionOnly)
    }

    @MainActor
    func testAttachmentStateReportsCurrentProjectAttachedWhenIDsMatch() {
        let appState = AppState()
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
        let appState = AppState()
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
}
