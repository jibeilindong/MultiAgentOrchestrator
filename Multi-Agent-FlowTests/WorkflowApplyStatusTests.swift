import XCTest
@testable import Multi_Agent_Flow

final class WorkflowApplyStatusTests: XCTestCase {
    func testPendingWorkflowConfigurationUsesPositiveRevisionDifference() {
        var runtimeState = RuntimeState()
        runtimeState.workflowConfigurationRevision = 7
        runtimeState.appliedWorkflowConfigurationRevision = 4

        XCTAssertTrue(AppState.hasPendingWorkflowConfiguration(runtimeState))
        XCTAssertEqual(AppState.pendingWorkflowConfigurationRevisionDelta(runtimeState), 3)
    }

    func testPendingWorkflowConfigurationIsClearedWhenRevisionsMatch() {
        var runtimeState = RuntimeState()
        runtimeState.workflowConfigurationRevision = 5
        runtimeState.appliedWorkflowConfigurationRevision = 5

        XCTAssertFalse(AppState.hasPendingWorkflowConfiguration(runtimeState))
        XCTAssertEqual(AppState.pendingWorkflowConfigurationRevisionDelta(runtimeState), 0)
    }

    func testPendingWorkflowConfigurationIgnoresAppliedRevisionAheadAnomaly() {
        var runtimeState = RuntimeState()
        runtimeState.workflowConfigurationRevision = 3
        runtimeState.appliedWorkflowConfigurationRevision = 5

        XCTAssertFalse(AppState.hasPendingWorkflowConfiguration(runtimeState))
        XCTAssertEqual(AppState.pendingWorkflowConfigurationRevisionDelta(runtimeState), 0)
    }
}
