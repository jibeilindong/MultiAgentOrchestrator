import XCTest
@testable import Multi_Agent_Flow

final class OpenClawConnectionStateTests: XCTestCase {
    private var originalStoredOpenClawConfigData: Data?

    override func setUp() {
        super.setUp()
        originalStoredOpenClawConfigData = UserDefaults.standard.data(forKey: OpenClawConfig.storageKey)
    }

    override func tearDown() {
        if let originalStoredOpenClawConfigData {
            UserDefaults.standard.set(originalStoredOpenClawConfigData, forKey: OpenClawConfig.storageKey)
        } else {
            UserDefaults.standard.removeObject(forKey: OpenClawConfig.storageKey)
        }
        super.tearDown()
    }

    private func drainMainQueue() {
        let expectation = expectation(description: "main queue drained")
        DispatchQueue.main.async {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
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
        XCTAssertEqual(snapshot.sessionLifecycle.stage, .inactive)
        XCTAssertFalse(snapshot.sessionLifecycle.hasPendingMirrorChanges)
    }

    func testRestoreDowngradesSyncedSessionLifecycleToPrepared() {
        let manager = OpenClawManager(notificationCenter: NotificationCenter())
        let snapshot = ProjectOpenClawSnapshot(
            config: .default,
            isConnected: false,
            availableAgents: [],
            activeAgents: [],
            detectedAgents: [],
            connectionState: OpenClawConnectionStateSnapshot(phase: .degraded, deploymentKind: .local),
            sessionLifecycle: OpenClawSessionLifecycleSnapshot(
                stage: .synced,
                hasPendingMirrorChanges: false,
                preparedAt: Date(),
                lastAppliedAt: Date()
            ),
            lastProbeReport: nil,
            recoveryReports: [],
            sessionBackupPath: nil,
            sessionMirrorPath: nil,
            lastSyncedAt: Date()
        )

        manager.restore(from: snapshot)

        XCTAssertEqual(manager.sessionLifecycle.stage, .prepared)
        XCTAssertFalse(manager.sessionLifecycle.hasPendingMirrorChanges)
    }

    func testNoteProjectMirrorChangesPromotesPreparedSessionToPendingSync() {
        let manager = OpenClawManager(notificationCenter: NotificationCenter())
        manager.config = .default
        manager.sessionLifecycle = OpenClawSessionLifecycleSnapshot(
            stage: .prepared,
            hasPendingMirrorChanges: false,
            preparedAt: Date(),
            lastAppliedAt: nil
        )

        manager.noteProjectMirrorChangesPendingSync()

        XCTAssertEqual(manager.sessionLifecycle.stage, .pendingSync)
        XCTAssertTrue(manager.sessionLifecycle.hasPendingMirrorChanges)
    }

    func testGatewayConfigParsesLocalGatewayContractFromOpenClawRoot() throws {
        let manager = OpenClawManager(notificationCenter: NotificationCenter())
        let rootURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let payload = """
        {
          "gateway": {
            "mode": "local",
            "port": 22345,
            "auth": {
              "mode": "token",
              "token": "container-secret"
            }
          }
        }
        """
        try payload.write(
            to: rootURL.appendingPathComponent("openclaw.json"),
            atomically: true,
            encoding: .utf8
        )

        var baseConfig = OpenClawConfig.default
        baseConfig.deploymentKind = .container
        baseConfig.host = "127.0.0.1"
        baseConfig.port = 18789
        baseConfig.apiKey = "fallback-token"

        let gatewayConfig = manager.gatewayConfig(
            fromOpenClawRoot: rootURL,
            using: baseConfig,
            hostFallback: "127.0.0.1",
            useSSLFallback: false,
            fallbackPort: baseConfig.port
        )

        XCTAssertEqual(gatewayConfig?.deploymentKind, .remoteServer)
        XCTAssertEqual(gatewayConfig?.host, "127.0.0.1")
        XCTAssertEqual(gatewayConfig?.port, 22345)
        XCTAssertEqual(gatewayConfig?.apiKey, "container-secret")
        XCTAssertEqual(gatewayConfig?.useSSL, false)
    }

    func testGatewayConfigFallsBackToBasePortAndTokenWhenConfigIsMissing() throws {
        let manager = OpenClawManager(notificationCenter: NotificationCenter())
        let rootURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        var baseConfig = OpenClawConfig.default
        baseConfig.deploymentKind = .container
        baseConfig.host = "container-gateway.local"
        baseConfig.port = 19888
        baseConfig.apiKey = "fallback-token"
        baseConfig.useSSL = true

        let gatewayConfig = manager.gatewayConfig(
            fromOpenClawRoot: rootURL,
            using: baseConfig,
            hostFallback: baseConfig.host,
            useSSLFallback: baseConfig.useSSL,
            fallbackPort: baseConfig.port
        )

        XCTAssertEqual(gatewayConfig?.deploymentKind, .remoteServer)
        XCTAssertEqual(gatewayConfig?.host, "container-gateway.local")
        XCTAssertEqual(gatewayConfig?.port, 19888)
        XCTAssertEqual(gatewayConfig?.apiKey, "fallback-token")
        XCTAssertEqual(gatewayConfig?.useSSL, true)
    }

    func testConnectFailureDoesNotPrepareSessionBeforeProbeSucceeds() {
        let manager = OpenClawManager(notificationCenter: NotificationCenter())
        var config = OpenClawConfig.default
        config.deploymentKind = .local
        config.localBinaryPath = "/tmp/openclaw-missing-\(UUID().uuidString)"
        config.autoConnect = false
        manager.config = config

        let project = MAProject(name: "Probe Order Regression")
        let completion = expectation(description: "connect completed")

        manager.connect(for: project) { success, message in
            XCTAssertFalse(success)
            XCTAssertFalse(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            completion.fulfill()
        }

        wait(for: [completion], timeout: 5.0)
        drainMainQueue()

        let snapshot = manager.snapshot()
        XCTAssertFalse(manager.isConnected)
        XCTAssertEqual(manager.sessionLifecycle.stage, .inactive)
        XCTAssertNil(snapshot.sessionBackupPath)
        XCTAssertNil(snapshot.sessionMirrorPath)
    }
}
