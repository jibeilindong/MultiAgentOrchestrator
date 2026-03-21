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

    func testLegacyProbeReportSnapshotDecodesWithoutLayers() throws {
        let json = """
        {
          "success": true,
          "deploymentKind": "local",
          "endpoint": "http://127.0.0.1:18789",
          "capabilities": {
            "cliAvailable": true,
            "gatewayReachable": true,
            "gatewayAuthenticated": true,
            "agentListingAvailable": true,
            "sessionHistoryAvailable": true,
            "gatewayAgentAvailable": true,
            "gatewayChatAvailable": true,
            "projectAttachmentSupported": true
          },
          "health": {
            "lastMessage": "connected"
          },
          "availableAgents": ["planner"],
          "message": "Connected.",
          "warnings": [],
          "sourceOfTruth": "probe",
          "observedDefaultTransports": ["cli", "ws"]
        }
        """

        let data = try XCTUnwrap(json.data(using: .utf8))
        let report = try JSONDecoder().decode(OpenClawProbeReportSnapshot.self, from: data)

        XCTAssertTrue(report.success)
        XCTAssertEqual(report.endpoint, "http://127.0.0.1:18789")
        XCTAssertNil(report.layers)
        XCTAssertEqual(report.availableAgents, ["planner"])
    }

    func testLegacyProjectOpenClawSnapshotDecodesWithoutRecoveryReports() throws {
        let json = """
        {
          "config": {
            "deploymentKind": "local",
            "host": "127.0.0.1",
            "port": 18789,
            "useSSL": false,
            "apiKey": "",
            "defaultAgent": "default",
            "timeout": 30,
            "autoConnect": true,
            "localBinaryPath": "/usr/local/bin/openclaw",
            "container": {
              "engine": "docker",
              "containerName": "openclaw-dev",
              "workspaceMountPath": "/workspace"
            },
            "cliQuietMode": true,
            "cliLogLevel": "warning"
          },
          "isConnected": false,
          "availableAgents": [],
          "activeAgents": [],
          "detectedAgents": [],
          "connectionState": {
            "phase": "idle",
            "deploymentKind": "local",
            "capabilities": {
              "cliAvailable": false,
              "gatewayReachable": false,
              "gatewayAuthenticated": false,
              "agentListingAvailable": false,
              "sessionHistoryAvailable": false,
              "gatewayAgentAvailable": false,
              "gatewayChatAvailable": false,
              "projectAttachmentSupported": false
            },
            "health": {}
          },
          "lastProbeReport": null,
          "sessionBackupPath": null,
          "sessionMirrorPath": null
        }
        """

        let data = try XCTUnwrap(json.data(using: .utf8))
        let snapshot = try JSONDecoder().decode(ProjectOpenClawSnapshot.self, from: data)

        XCTAssertTrue(snapshot.recoveryReports.isEmpty)
        XCTAssertEqual(snapshot.connectionState.phase, .idle)
    }
}
