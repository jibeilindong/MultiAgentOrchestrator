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

    private func makeExecutableScript(in directory: URL, named name: String = "openclaw", contents: String) throws -> URL {
        let scriptURL = directory.appendingPathComponent(name, isDirectory: false)
        try contents.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        return scriptURL
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

    func testDegradedLocalCLIOnlyStateSupportsWorkflowAndConversationExecution() {
        let state = OpenClawConnectionStateSnapshot(
            phase: .degraded,
            deploymentKind: .local,
            capabilities: OpenClawConnectionCapabilitiesSnapshot(
                cliAvailable: true,
                gatewayReachable: false,
                gatewayAuthenticated: false,
                agentListingAvailable: true,
                sessionHistoryAvailable: false,
                gatewayAgentAvailable: false,
                gatewayChatAvailable: false,
                projectAttachmentSupported: true
            )
        )

        XCTAssertTrue(state.canRunWorkflow)
        XCTAssertTrue(state.canRunConversation)
        XCTAssertTrue(state.canAttachProject)
        XCTAssertFalse(state.canReadSessionHistory)
        XCTAssertTrue(state.isRunnableWithDegradedCapabilities)
    }

    func testDetachedStateBlocksExecutionEvenWhenCLIIsAvailable() {
        let state = OpenClawConnectionStateSnapshot(
            phase: .detached,
            deploymentKind: .local,
            capabilities: OpenClawConnectionCapabilitiesSnapshot(
                cliAvailable: true,
                gatewayReachable: false,
                gatewayAuthenticated: false,
                agentListingAvailable: true,
                sessionHistoryAvailable: false,
                gatewayAgentAvailable: false,
                gatewayChatAvailable: false,
                projectAttachmentSupported: true
            )
        )

        XCTAssertFalse(state.canRunWorkflow)
        XCTAssertFalse(state.canRunConversation)
        XCTAssertFalse(state.canAttachProject)
        XCTAssertFalse(state.isRunnableWithDegradedCapabilities)
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
        XCTAssertEqual(snapshot.projectAttachment.state, .detached)
        XCTAssertNil(snapshot.projectAttachment.projectID)
        XCTAssertEqual(snapshot.sessionLifecycle.stage, .inactive)
        XCTAssertFalse(snapshot.sessionLifecycle.hasPendingMirrorChanges)
    }

    func testRestoreDowngradesSyncedSessionLifecycleAndDetachesProjectAttachment() {
        let manager = OpenClawManager(notificationCenter: NotificationCenter())
        let projectID = UUID()
        let snapshot = ProjectOpenClawSnapshot(
            config: .default,
            isConnected: false,
            availableAgents: [],
            activeAgents: [],
            detectedAgents: [],
            connectionState: OpenClawConnectionStateSnapshot(phase: .degraded, deploymentKind: .local),
            projectAttachment: OpenClawProjectAttachmentSnapshot(
                state: .attached,
                projectID: projectID,
                attachedAt: Date()
            ),
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
        XCTAssertEqual(manager.projectAttachment.state, .detached)
        XCTAssertNil(manager.projectAttachment.projectID)
        XCTAssertNotNil(manager.projectAttachment.lastDetachedAt)
    }

    func testNoteProjectMirrorChangesPromotesPreparedSessionToPendingSync() {
        let manager = OpenClawManager(notificationCenter: NotificationCenter())
        manager.config = .default
        manager.projectAttachment = OpenClawProjectAttachmentSnapshot(
            state: .attached,
            projectID: UUID(),
            attachedAt: Date()
        )
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

    func testNoteProjectMirrorChangesDoesNothingWhenProjectIsDetached() {
        let manager = OpenClawManager(notificationCenter: NotificationCenter())
        manager.config = .default
        manager.projectAttachment = OpenClawProjectAttachmentSnapshot(state: .detached)
        manager.sessionLifecycle = OpenClawSessionLifecycleSnapshot(
            stage: .prepared,
            hasPendingMirrorChanges: false,
            preparedAt: Date(),
            lastAppliedAt: nil
        )

        manager.noteProjectMirrorChangesPendingSync()

        XCTAssertEqual(manager.sessionLifecycle.stage, .prepared)
        XCTAssertFalse(manager.sessionLifecycle.hasPendingMirrorChanges)
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

    func testResolveLocalOpenClawConfigURLPrefersCLIReportedPath() throws {
        let manager = OpenClawManager(notificationCenter: NotificationCenter())
        let tempDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let customRootURL = tempDirectory.appendingPathComponent("custom-openclaw", isDirectory: true)
        try FileManager.default.createDirectory(at: customRootURL, withIntermediateDirectories: true)
        let customConfigURL = customRootURL.appendingPathComponent("openclaw.json", isDirectory: false)
        try "{}".write(to: customConfigURL, atomically: true, encoding: .utf8)

        let executableURL = try makeExecutableScript(
            in: tempDirectory,
            contents: """
            #!/bin/sh
            if [ "$1" = "config" ] && [ "$2" = "file" ]; then
              printf '%s\\n' "\(customConfigURL.path)"
              exit 0
            fi
            exit 1
            """
        )

        var config = OpenClawConfig.default
        config.deploymentKind = .local
        config.localBinaryPath = executableURL.path

        XCTAssertEqual(
            manager.resolveLocalOpenClawConfigURL(using: config, allowFallback: false)?.path,
            customConfigURL.path
        )
        XCTAssertEqual(
            manager.localOpenClawRootURL(using: config).path,
            customRootURL.path
        )
    }

    func testPreferredGatewayConfigUsesCLIReportedLocalRoot() throws {
        let manager = OpenClawManager(notificationCenter: NotificationCenter())
        let tempDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let customRootURL = tempDirectory.appendingPathComponent("custom-openclaw", isDirectory: true)
        try FileManager.default.createDirectory(at: customRootURL, withIntermediateDirectories: true)
        try """
        {
          "gateway": {
            "mode": "local",
            "port": 23111,
            "auth": {
              "mode": "token",
              "token": "custom-local-token"
            }
          }
        }
        """.write(
            to: customRootURL.appendingPathComponent("openclaw.json", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        let executableURL = try makeExecutableScript(
            in: tempDirectory,
            contents: """
            #!/bin/sh
            if [ "$1" = "config" ] && [ "$2" = "file" ]; then
              printf '%s\\n' "\(customRootURL.appendingPathComponent("openclaw.json", isDirectory: false).path)"
              exit 0
            fi
            exit 1
            """
        )

        var config = OpenClawConfig.default
        config.deploymentKind = .local
        config.localBinaryPath = executableURL.path
        config.port = 18789
        config.apiKey = "fallback-token"
        manager.config = config

        let gatewayConfig = manager.preferredGatewayConfig(using: config)

        XCTAssertEqual(gatewayConfig?.deploymentKind, .remoteServer)
        XCTAssertEqual(gatewayConfig?.host, "127.0.0.1")
        XCTAssertEqual(gatewayConfig?.port, 23111)
        XCTAssertEqual(gatewayConfig?.apiKey, "custom-local-token")
    }

    func testContainerOpenClawRootFallbackCandidatesPrioritizeHomeBeforeWorkspaceMount() {
        let manager = OpenClawManager(notificationCenter: NotificationCenter())
        var config = OpenClawConfig.default
        config.deploymentKind = .container
        config.container.workspaceMountPath = "/workspace/project"

        let candidates = manager.containerOpenClawRootFallbackCandidates(
            for: config,
            homeDirectoryOverride: "/home/app"
        )

        XCTAssertEqual(
            Array(candidates.prefix(4)),
            [
                "/home/app/.openclaw",
                "/home/app/openclaw",
                "/root/.openclaw",
                "/home/node/.openclaw"
            ]
        )
        XCTAssertTrue(candidates.contains("/workspace/project/.openclaw"))
        XCTAssertTrue(candidates.contains("/workspace/project/openclaw"))
        XCTAssertTrue(candidates.contains("/workspace/project"))
    }

    func testContainerOpenClawRootDiscoveryScriptScansRuntimeRootsBeforeWorkspaceFallback() {
        let manager = OpenClawManager(notificationCenter: NotificationCenter())
        let script = manager.containerOpenClawRootDiscoveryScript(workspaceMountPath: "/srv/app'space")

        XCTAssertTrue(script.contains("\"${OPENCLAW_ROOT:-}\""))
        XCTAssertTrue(script.contains("\"$HOME/.openclaw\""))
        XCTAssertTrue(script.contains("find \"$root\" -maxdepth 5 -type f -name openclaw.json"))
        XCTAssertTrue(script.contains("probe_candidate '/srv/app'\\''space/.openclaw' && exit 0"))
        XCTAssertTrue(script.contains("probe_candidate '/srv/app'\\''space/openclaw' && exit 0"))
    }

    func testFirstReachableOpenClawRootCandidateSkipsMissingEntries() {
        let manager = OpenClawManager(notificationCenter: NotificationCenter())
        let resolved = manager.firstReachableOpenClawRootCandidate(
            from: ["", "   ", "/missing/.openclaw", "/workspace/openclaw", "/fallback"]
        ) { candidate in
            candidate == "/workspace/openclaw"
        }

        XCTAssertEqual(resolved, "/workspace/openclaw")
    }

    func testFirstReachableOpenClawRootCandidateReturnsNilWhenAllCandidatesMissing() {
        let manager = OpenClawManager(notificationCenter: NotificationCenter())
        let resolved = manager.firstReachableOpenClawRootCandidate(
            from: ["/missing/.openclaw", "/missing/openclaw"]
        ) { _ in
            false
        }

        XCTAssertNil(resolved)
    }

    func testExecApprovalSnapshotTreatsCustomDefaultsOrAgentsAsCustomEntries() {
        let manager = OpenClawManager(notificationCenter: NotificationCenter())

        let defaultsSnapshot = manager.execApprovalSnapshot(
            fromApprovalFileRecord: [
                "defaults": ["exec": "allow"],
                "agents": [:]
            ]
        )
        XCTAssertTrue(defaultsSnapshot.hasCustomEntries)

        let agentsSnapshot = manager.execApprovalSnapshot(
            fromApprovalFileRecord: [
                "defaults": [:],
                "agents": [
                    "planner": ["exec": "deny"]
                ]
            ]
        )
        XCTAssertTrue(agentsSnapshot.hasCustomEntries)
    }

    func testExecApprovalSnapshotTreatsEmptyApprovalFileAsDefaultEntriesOnly() {
        let manager = OpenClawManager(notificationCenter: NotificationCenter())
        let snapshot = manager.execApprovalSnapshot(
            fromApprovalFileRecord: [
                "defaults": [:],
                "agents": [:]
            ]
        )

        XCTAssertFalse(snapshot.hasCustomEntries)
    }

    func testResolveOpenClawGovernancePathsKeepsLocalRootWithoutInspectionSnapshot() throws {
        let manager = OpenClawManager(notificationCenter: NotificationCenter())
        let paths = try manager.resolveOpenClawGovernancePaths(using: .default, requiresInspectionRoot: false)

        let expectedRoot = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent(".openclaw", isDirectory: true)
        XCTAssertEqual(paths.rootURL?.path, expectedRoot.path)
        XCTAssertEqual(
            paths.configURL?.path,
            expectedRoot.appendingPathComponent("openclaw.json", isDirectory: false).path
        )

        if let approvalsURL = paths.approvalsURL {
            XCTAssertEqual(
                approvalsURL.path,
                expectedRoot.appendingPathComponent("exec-approvals.json", isDirectory: false).path
            )
        }
    }

    func testResolveOpenClawGovernancePathsLeavesRemotePathsEmpty() throws {
        let manager = OpenClawManager(notificationCenter: NotificationCenter())
        var config = OpenClawConfig.default
        config.deploymentKind = .remoteServer

        let paths = try manager.resolveOpenClawGovernancePaths(using: config, requiresInspectionRoot: false)

        XCTAssertNil(paths.rootURL)
        XCTAssertNil(paths.configURL)
        XCTAssertNil(paths.approvalsURL)
    }

    func testSnapshotPreservesProjectAttachmentState() {
        let manager = OpenClawManager(notificationCenter: NotificationCenter())
        let projectID = UUID()
        let attachedAt = Date()
        manager.projectAttachment = OpenClawProjectAttachmentSnapshot(
            state: .attached,
            projectID: projectID,
            attachedAt: attachedAt
        )

        let snapshot = manager.snapshot()

        XCTAssertEqual(snapshot.projectAttachment.state, .attached)
        XCTAssertEqual(snapshot.projectAttachment.projectID, projectID)
        XCTAssertEqual(snapshot.projectAttachment.attachedAt, attachedAt)
    }

    func testConnectFailureDoesNotPrepareSessionBeforeProbeSucceeds() {
        let manager = OpenClawManager(notificationCenter: NotificationCenter())
        let tempDirectory = try! makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let executableURL = try! makeExecutableScript(
            in: tempDirectory,
            contents: """
            #!/bin/sh
            exit 1
            """
        )
        var config = OpenClawConfig.default
        config.deploymentKind = .local
        config.localBinaryPath = executableURL.path
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

    func testSyncUsesActiveSessionDeploymentWhenCurrentConfigChanges() throws {
        let manager = OpenClawManager(notificationCenter: NotificationCenter())
        let tempDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let runtimeRootURL = tempDirectory.appendingPathComponent("runtime-root", isDirectory: true)
        try FileManager.default.createDirectory(at: runtimeRootURL, withIntermediateDirectories: true)
        let configFileURL = runtimeRootURL.appendingPathComponent("openclaw.json", isDirectory: false)
        try "{}".write(to: configFileURL, atomically: true, encoding: .utf8)

        let executableURL = try makeExecutableScript(
            in: tempDirectory,
            contents: """
            #!/bin/sh
            if [ "$1" = "config" ] && [ "$2" = "file" ]; then
              printf '%s\\n' "\(configFileURL.path)"
              exit 0
            fi
            exit 0
            """
        )

        var localConfig = OpenClawConfig.default
        localConfig.deploymentKind = .local
        localConfig.localBinaryPath = executableURL.path
        localConfig.autoConnect = false
        manager.config = localConfig

        let project = MAProject(name: "Session Deployment Drift")
        defer {
            try? FileManager.default.removeItem(at: ProjectManager.shared.openClawProjectRoot(for: project.id))
        }

        try manager.beginSession(for: project.id)
        manager.isConnected = true

        var remoteConfig = localConfig
        remoteConfig.deploymentKind = .remoteServer
        remoteConfig.host = "example.com"
        remoteConfig.port = 443
        manager.config = remoteConfig

        let completion = expectation(description: "session sync completed")
        manager.syncProjectAgentsToActiveSession(project) { result in
            XCTAssertEqual(result.deploymentStatus, .skippedNoPendingChanges)
            XCTAssertNil(result.errorMessage)
            XCTAssertFalse(result.message.contains("远程网关模式"))
            completion.fulfill()
        }

        wait(for: [completion], timeout: 5.0)
        drainMainQueue()
        manager.disconnect()
        XCTAssertEqual(manager.projectAttachment.state, .detached)
    }
}
