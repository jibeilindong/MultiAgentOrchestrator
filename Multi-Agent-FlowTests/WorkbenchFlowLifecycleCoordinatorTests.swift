import XCTest
@testable import Multi_Agent_Flow

final class WorkbenchFlowLifecycleCoordinatorTests: XCTestCase {
    func testChatEntryDispositionReturnsReadyToRunWhenEntryCompletesWithoutBackgroundNodes() {
        let coordinator = WorkbenchFlowLifecycleCoordinator()
        let result = makeExecutionResult(status: .completed, output: "done", summary: "Entry complete")
        WorkbenchFlowLifecycleTestRetention.retain(coordinator: coordinator, results: [result])

        let disposition = coordinator.chatEntryDisposition(for: result, hasBackgroundNodes: false)

        if case .readyToRun = disposition {
        } else {
            XCTFail("Expected readyToRun disposition")
        }
    }

    func testChatEntryDispositionReturnsFailedWhenEntryFails() {
        let coordinator = WorkbenchFlowLifecycleCoordinator()
        let result = makeExecutionResult(status: .failed, output: "error", summary: "Entry failed")
        WorkbenchFlowLifecycleTestRetention.retain(coordinator: coordinator, results: [result])

        let disposition = coordinator.chatEntryDisposition(for: result, hasBackgroundNodes: true)

        if case let .failed(errorMessage) = disposition {
            XCTAssertEqual(errorMessage, "Entry failed")
        } else {
            XCTFail("Expected failed disposition")
        }
    }

    func testBackgroundWorkflowTerminalTransitionUsesConversationToRunOnSuccess() {
        let coordinator = WorkbenchFlowLifecycleCoordinator()
        let results = [
            makeExecutionResult(status: .completed, output: "ok", summary: "Node A complete"),
            makeExecutionResult(status: .completed, output: "ok", summary: "Node B complete")
        ]

        let transition = coordinator.backgroundWorkflowTerminalTransition(for: results)
        WorkbenchFlowLifecycleTestRetention.retain(
            coordinator: coordinator,
            results: results,
            transition: transition
        )

        if case let .completed(interactionMode, threadMode) = transition {
            switch interactionMode {
            case .run:
                break
            default:
                XCTFail("Expected run interaction mode")
            }

            switch threadMode {
            case .conversationToRun:
                break
            default:
                XCTFail("Expected conversationToRun thread mode")
            }
        } else {
            XCTFail("Expected completed background transition")
        }
    }

    func testWorkflowRunPresentationBuildsFailureSummaryAndTerminalTransition() {
        let coordinator = WorkbenchFlowLifecycleCoordinator()
        let results = [
            makeExecutionResult(status: .completed, output: "ok", summary: "Node A complete"),
            makeExecutionResult(status: .failed, output: "error", summary: "Node B failed")
        ]

        let presentation = coordinator.workflowRunPresentation(for: results)
        WorkbenchFlowLifecycleTestRetention.retain(
            coordinator: coordinator,
            results: results,
            transition: presentation.terminalTransition,
            presentation: presentation
        )

        switch presentation.taskStatus {
        case .blocked:
            break
        default:
            XCTFail("Expected blocked task status")
        }
        if case let .failed(errorMessage, interactionMode, threadMode) = presentation.terminalTransition {
            XCTAssertEqual(errorMessage, "Node B failed")
            switch interactionMode {
            case .run:
                break
            default:
                XCTFail("Expected run interaction mode")
            }

            switch threadMode {
            case .controlledRun:
                break
            default:
                XCTFail("Expected controlledRun thread mode")
            }
        } else {
            XCTFail("Expected failed run transition")
        }
        switch presentation.messageType {
        case .data:
            break
        default:
            XCTFail("Expected data message type")
        }

        switch presentation.outputType {
        case .errorSummary:
            break
        default:
            XCTFail("Expected errorSummary output type")
        }
        XCTAssertTrue(presentation.summaryText.contains("Run completed: 1 succeeded, 1 failed."))
        XCTAssertTrue(presentation.summaryText.contains("Failure: Node B failed"))
    }
}

private extension WorkbenchFlowLifecycleCoordinatorTests {
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

private enum WorkbenchFlowLifecycleTestRetention {
    static var coordinators: [WorkbenchFlowLifecycleCoordinator] = []
    static var resultBatches: [[ExecutionResult]] = []
    static var transitions: [WorkbenchThreadTransition] = []
    static var presentations: [WorkbenchWorkflowRunPresentation] = []

    static func retain(
        coordinator: WorkbenchFlowLifecycleCoordinator,
        results: [ExecutionResult],
        transition: WorkbenchThreadTransition? = nil,
        presentation: WorkbenchWorkflowRunPresentation? = nil
    ) {
        coordinators.append(coordinator)
        resultBatches.append(results)

        if let transition {
            transitions.append(transition)
        }

        if let presentation {
            presentations.append(presentation)
        }
    }
}
