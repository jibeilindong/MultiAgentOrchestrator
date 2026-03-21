import XCTest
@testable import Multi_Agent_Flow

final class OpenClawConnectionStateTests: XCTestCase {
    private func drainMainQueue() {
        let expectation = expectation(description: "main queue drained")
        DispatchQueue.main.async {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }

    func testGatewayDisconnectNotificationDowngradesConnectedState() {
        let notificationCenter = NotificationCenter()
        let manager = OpenClawManager(notificationCenter: notificationCenter)

        manager.config = .default
        manager.isConnected = true
        manager.status = .connected
        manager.activeAgents = [
            UUID(): OpenClawManager.ActiveAgentRuntime(
                agentID: UUID(),
                name: "planner",
                status: "running",
                lastReloadedAt: Date()
            )
        ]
        manager.connectionState = OpenClawConnectionStateSnapshot(
            phase: .ready,
            deploymentKind: .local,
            capabilities: OpenClawConnectionCapabilitiesSnapshot(
                cliAvailable: true,
                gatewayReachable: true,
                gatewayAuthenticated: true,
                agentListingAvailable: true,
                sessionHistoryAvailable: true,
                gatewayAgentAvailable: true,
                gatewayChatAvailable: true,
                projectAttachmentSupported: true
            ),
            health: OpenClawConnectionHealthSnapshot(
                lastProbeAt: Date(),
                lastHeartbeatAt: Date(),
                latencyMs: 12,
                degradationReason: nil,
                lastMessage: "connected"
            )
        )

        notificationCenter.post(
            name: OpenClawGatewayClient.disconnectNotificationName,
            object: nil,
            userInfo: [OpenClawGatewayClient.disconnectMessageUserInfoKey: "socket dropped"]
        )
        drainMainQueue()

        XCTAssertFalse(manager.isConnected)
        XCTAssertTrue(manager.activeAgents.isEmpty)
        XCTAssertEqual(manager.connectionState.phase, .degraded)
        XCTAssertFalse(manager.connectionState.capabilities.gatewayReachable)
        XCTAssertFalse(manager.connectionState.capabilities.gatewayAuthenticated)

        guard case .error(let message) = manager.status else {
            return XCTFail("Expected status to be .error after gateway disconnect.")
        }
        XCTAssertTrue(message.contains("socket dropped"))
    }

    func testGatewayDisconnectNotificationDoesNotMutateIdleState() {
        let notificationCenter = NotificationCenter()
        let manager = OpenClawManager(notificationCenter: notificationCenter)

        manager.config = .default
        manager.isConnected = false
        manager.status = .disconnected
        manager.connectionState = OpenClawConnectionStateSnapshot(
            phase: .idle,
            deploymentKind: .local
        )

        notificationCenter.post(
            name: OpenClawGatewayClient.disconnectNotificationName,
            object: nil,
            userInfo: [OpenClawGatewayClient.disconnectMessageUserInfoKey: "late event"]
        )
        drainMainQueue()

        XCTAssertFalse(manager.isConnected)
        XCTAssertEqual(manager.connectionState.phase, .idle)
        guard case .disconnected = manager.status else {
            return XCTFail("Expected idle manager to stay disconnected.")
        }
    }
}
