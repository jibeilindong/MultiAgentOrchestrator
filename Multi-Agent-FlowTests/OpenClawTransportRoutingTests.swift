import XCTest
@testable import Multi_Agent_Flow

final class OpenClawTransportRoutingTests: XCTestCase {
    func testWorkflowSessionsUseGatewayAgentOnRemoteServer() {
        let transport = OpenClawTransportRouting.runtimeTransportKind(
            deploymentKind: .remoteServer,
            outputMode: .structuredJSON,
            sessionID: "workflow-benchmark-123"
        )

        XCTAssertEqual(transport, .gatewayAgent)
    }

    func testWorkbenchAndBenchmarkSessionsUseGatewayChatOnRemoteServer() {
        let workbenchTransport = OpenClawTransportRouting.runtimeTransportKind(
            deploymentKind: .remoteServer,
            outputMode: .plainStreaming,
            sessionID: "workbench-demo-123"
        )
        let benchmarkTransport = OpenClawTransportRouting.runtimeTransportKind(
            deploymentKind: .remoteServer,
            outputMode: .structuredJSON,
            sessionID: "benchmark-demo-456"
        )
        let agentScopedTransport = OpenClawTransportRouting.runtimeTransportKind(
            deploymentKind: .remoteServer,
            outputMode: .structuredJSON,
            sessionID: "agent:planner:main"
        )

        XCTAssertEqual(workbenchTransport, .gatewayChat)
        XCTAssertEqual(benchmarkTransport, .gatewayChat)
        XCTAssertEqual(agentScopedTransport, .gatewayChat)
    }

    func testLocalAndContainerDeploymentsUseCLITransport() {
        let localTransport = OpenClawTransportRouting.runtimeTransportKind(
            deploymentKind: .local,
            outputMode: .structuredJSON,
            sessionID: "workflow-anything"
        )
        let containerTransport = OpenClawTransportRouting.runtimeTransportKind(
            deploymentKind: .container,
            outputMode: .plainStreaming,
            sessionID: "workbench-anything"
        )

        XCTAssertEqual(localTransport, .cli)
        XCTAssertEqual(containerTransport, .cli)
    }

    func testBenchmarkSummaryTracksWorkflowHotPathMismatchSeparately() throws {
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let samples = [
            TransportBenchmarkSample(
                transport: .workflowHotPath,
                iteration: 1,
                success: true,
                sessionID: "workflow-benchmark-a",
                actualTransportKind: "gateway_agent",
                startedAt: startedAt,
                completedAt: startedAt.addingTimeInterval(0.1),
                firstChunkLatencyMs: 40,
                completionLatencyMs: 100,
                previewText: "ok",
                errorText: nil
            ),
            TransportBenchmarkSample(
                transport: .workflowHotPath,
                iteration: 2,
                success: true,
                sessionID: "workflow-benchmark-a",
                actualTransportKind: "gateway_chat",
                startedAt: startedAt.addingTimeInterval(1),
                completedAt: startedAt.addingTimeInterval(1.12),
                firstChunkLatencyMs: 45,
                completionLatencyMs: 120,
                previewText: "fallback",
                errorText: nil
            ),
            TransportBenchmarkSample(
                transport: .workflowHotPath,
                iteration: 3,
                success: false,
                sessionID: "workflow-benchmark-a",
                actualTransportKind: nil,
                startedAt: startedAt.addingTimeInterval(2),
                completedAt: startedAt.addingTimeInterval(2.2),
                firstChunkLatencyMs: nil,
                completionLatencyMs: nil,
                previewText: "failed",
                errorText: "timeout"
            )
        ]

        let summary = try XCTUnwrap(
            OpenClawTransportRouting.summarizeTransportBenchmarkSamples(samples).first
        )

        XCTAssertEqual(summary.transport, .workflowHotPath)
        XCTAssertEqual(summary.sampleCount, 3)
        XCTAssertEqual(summary.successCount, 2)
        XCTAssertEqual(summary.failureCount, 1)
        XCTAssertEqual(summary.expectedTransportKind, "gateway_agent")
        XCTAssertEqual(summary.expectedTransportMatchedCount, 1)
        XCTAssertEqual(summary.expectedTransportMismatchCount, 1)
        XCTAssertEqual(summary.actualTransportKinds, ["gateway_agent", "gateway_chat"])
    }
}
