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

    private func makeMutableOpenClawScript(in directory: URL, configFileURL: URL) throws -> URL {
        try makeExecutableScript(
            in: directory,
            contents: """
            #!/bin/sh
            CONFIG_PATH="\(configFileURL.path)"
            python3 - "$CONFIG_PATH" "$@" <<'PY'
            import json
            import sys

            config_path = sys.argv[1]
            args = sys.argv[2:]

            def load():
                with open(config_path, "r", encoding="utf-8") as handle:
                    return json.load(handle)

            def save(payload):
                with open(config_path, "w", encoding="utf-8") as handle:
                    json.dump(payload, handle, ensure_ascii=False, indent=2, sort_keys=True)

            if args[:2] == ["config", "file"]:
                print(config_path)
                sys.exit(0)

            if args[:2] == ["agents", "list"]:
                payload = load()
                agents = payload.get("agents", {}).get("list", [])
                if "--json" in args:
                    print(json.dumps(agents, ensure_ascii=False))
                else:
                    for agent in agents:
                        print(f"- {agent.get('name', agent.get('id', ''))}")
                sys.exit(0)

            if len(args) >= 4 and args[:2] == ["config", "set"]:
                path = args[2]
                value = args[3]
                payload = load()
                agents = payload.setdefault("agents", {}).setdefault("list", [])
                if path.startswith("agents.list[") and path.endswith("].model"):
                    index_text = path[len("agents.list["):path.index("]")]
                    try:
                        index = int(index_text)
                    except ValueError:
                        sys.exit(1)
                    if index < 0 or index >= len(agents):
                        sys.exit(1)
                    agents[index]["model"] = value
                    save(payload)
                    print(json.dumps({"ok": True}, ensure_ascii=False))
                    sys.exit(0)
                sys.exit(1)

            if args[:2] == ["channels", "list"]:
                payload = load()
                print(json.dumps(payload.get("channels", []), ensure_ascii=False))
                sys.exit(0)

            if args[:2] == ["agents", "bindings"]:
                payload = load()
                bindings = payload.get("bindings", [])
                agent_filter = None
                if "--agent" in args:
                    index = args.index("--agent")
                    if index + 1 < len(args):
                        agent_filter = args[index + 1].strip().lower()
                if agent_filter:
                    bindings = [
                        binding for binding in bindings
                        if binding.get("agent", "").strip().lower() == agent_filter
                    ]
                print(json.dumps({"bindings": bindings}, ensure_ascii=False))
                sys.exit(0)

            if args[:2] == ["agents", "bind"]:
                payload = load()
                bindings = payload.setdefault("bindings", [])
                agent_identifier = ""
                bind_specs = []
                index = 2
                while index < len(args):
                    flag = args[index]
                    if flag == "--agent" and index + 1 < len(args):
                        agent_identifier = args[index + 1]
                        index += 2
                    elif flag == "--bind" and index + 1 < len(args):
                        bind_specs.append(args[index + 1])
                        index += 2
                    else:
                        index += 1

                for bind_spec in bind_specs:
                    components = bind_spec.split(":", 1)
                    channel = components[0]
                    account = components[1] if len(components) > 1 else "default"
                    exists = any(
                        binding.get("agent", "").strip().lower() == agent_identifier.strip().lower()
                        and binding.get("channel", "") == channel
                        and binding.get("account", "default") == account
                        for binding in bindings
                    )
                    if not exists:
                        bindings.append({
                            "agent": agent_identifier,
                            "channel": channel,
                            "account": account
                        })
                save(payload)
                print(json.dumps({"ok": True}, ensure_ascii=False))
                sys.exit(0)

            if args[:2] == ["agents", "unbind"]:
                payload = load()
                bindings = payload.setdefault("bindings", [])
                agent_identifier = ""
                remove_all = False
                bind_specs = []
                index = 2
                while index < len(args):
                    flag = args[index]
                    if flag == "--agent" and index + 1 < len(args):
                        agent_identifier = args[index + 1]
                        index += 2
                    elif flag == "--all":
                        remove_all = True
                        index += 1
                    elif flag == "--bind" and index + 1 < len(args):
                        bind_specs.append(args[index + 1])
                        index += 2
                    else:
                        index += 1

                if remove_all:
                    bindings[:] = [
                        binding for binding in bindings
                        if binding.get("agent", "").strip().lower() != agent_identifier.strip().lower()
                    ]
                else:
                    removal_specs = set()
                    for bind_spec in bind_specs:
                        components = bind_spec.split(":", 1)
                        channel = components[0]
                        account = components[1] if len(components) > 1 else "default"
                        removal_specs.add((channel, account))
                    bindings[:] = [
                        binding for binding in bindings
                        if binding.get("agent", "").strip().lower() != agent_identifier.strip().lower()
                        or (binding.get("channel", ""), binding.get("account", "default")) not in removal_specs
                    ]
                save(payload)
                print(json.dumps({"ok": True}, ensure_ascii=False))
                sys.exit(0)

            if len(args) >= 3 and args[:2] == ["agents", "add"]:
                identifier = args[2]
                payload = load()
                agents_root = payload.setdefault("agents", {})
                agents = agents_root.setdefault("list", [])

                workspace = ""
                agent_dir = ""
                model = ""
                index = 3
                while index < len(args):
                    flag = args[index]
                    if flag == "--workspace" and index + 1 < len(args):
                        workspace = args[index + 1]
                        index += 2
                    elif flag == "--agent-dir" and index + 1 < len(args):
                        agent_dir = args[index + 1]
                        index += 2
                    elif flag == "--model" and index + 1 < len(args):
                        model = args[index + 1]
                        index += 2
                    else:
                        index += 1

                agents[:] = [
                    agent for agent in agents
                    if agent.get("id", "").strip().lower() != identifier.strip().lower()
                ]
                agents.append({
                    "id": identifier,
                    "name": identifier,
                    "workspace": workspace,
                    "agentDir": agent_dir,
                    "model": model
                })
                save(payload)
                print(json.dumps({"id": identifier}, ensure_ascii=False))
                sys.exit(0)

            if args[:2] == ["agent", "--help"]:
                print("Usage: openclaw agent --agent <id> --message <text> [--json] [--quiet] [--log-level <level>]")
                sys.exit(0)

            if args[:1] == ["agent"]:
                identifier = ""
                message = ""
                emit_json = False
                index = 1
                while index < len(args):
                    flag = args[index]
                    if flag == "--agent" and index + 1 < len(args):
                        identifier = args[index + 1]
                        index += 2
                    elif flag == "--message" and index + 1 < len(args):
                        message = args[index + 1]
                        index += 2
                    elif flag == "--json":
                        emit_json = True
                        index += 1
                    else:
                        index += 1

                if emit_json:
                    print(json.dumps({
                        "output": f"reply from {identifier}",
                        "route": {"action": "stop", "targets": [], "reason": "mock"}
                    }, ensure_ascii=False))
                else:
                    print(f"reply from {identifier}: {message}".strip())
                sys.exit(0)

            sys.exit(1)
            PY
            """
        )
    }

    private func makeProjectAgent(
        name: String,
        workspaceRootURL: URL
    ) throws -> Agent {
        try FileManager.default.createDirectory(at: workspaceRootURL, withIntermediateDirectories: true)
        try "# \(name)\n".write(
            to: workspaceRootURL.appendingPathComponent("SOUL.md", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        var agent = Agent(name: name)
        agent.soulMD = "# \(name)\n"
        agent.openClawDefinition.agentIdentifier = name
        agent.openClawDefinition.soulSourcePath = workspaceRootURL.appendingPathComponent("SOUL.md", isDirectory: false).path
        return agent
    }

    private func makeDeferredProjectAgent(name: String) -> Agent {
        var agent = Agent(name: name)
        agent.soulMD = "# \(name)\n"
        agent.openClawDefinition.agentIdentifier = name
        agent.openClawDefinition.soulSourcePath = nil
        agent.openClawDefinition.memoryBackupPath = nil
        return agent
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

    func testSyncRegistersLocalRuntimeAgentUsingUserProvidedBootstrapDirectory() throws {
        let manager = OpenClawManager(notificationCenter: NotificationCenter())
        let tempDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let runtimeRootURL = tempDirectory.appendingPathComponent("runtime-root", isDirectory: true)
        try FileManager.default.createDirectory(at: runtimeRootURL, withIntermediateDirectories: true)
        let configFileURL = runtimeRootURL.appendingPathComponent("openclaw.json", isDirectory: false)
        try """
        {
          "agents": {
            "list": [
              {
                "id": "main",
                "name": "main",
                "workspace": "\(runtimeRootURL.appendingPathComponent("workspace", isDirectory: true).path)",
                "agentDir": "\(runtimeRootURL.appendingPathComponent("agents/main/agent", isDirectory: true).path)"
              }
            ]
          }
        }
        """.write(to: configFileURL, atomically: true, encoding: .utf8)

        let executableURL = try makeMutableOpenClawScript(in: tempDirectory, configFileURL: configFileURL)

        var config = OpenClawConfig.default
        config.deploymentKind = .local
        config.localBinaryPath = executableURL.path
        config.autoConnect = false
        manager.config = config

        let project = MAProject(name: "Bootstrap Sync")
        defer {
            try? FileManager.default.removeItem(at: ProjectManager.shared.openClawProjectRoot(for: project.id))
        }

        let workspaceRootURL = tempDirectory.appendingPathComponent("task-center-workspace", isDirectory: true)
        let agent = try makeProjectAgent(name: "任务中心-任务领域-1", workspaceRootURL: workspaceRootURL)
        var workflow = Workflow(name: "Main Workflow")
        var node = WorkflowNode(type: .agent)
        node.agentID = agent.id
        node.title = agent.name
        workflow.nodes = [node]
        var mutableProject = project
        mutableProject.agents = [agent]
        mutableProject.workflows = [workflow]

        try manager.beginSession(for: mutableProject.id)
        manager.isConnected = true

        let bootstrapRootURL = tempDirectory.appendingPathComponent("bootstrap-root", isDirectory: true)
        let backupAgentDirectory = bootstrapRootURL.appendingPathComponent("main/agent", isDirectory: true)
        try FileManager.default.createDirectory(at: backupAgentDirectory, withIntermediateDirectories: true)
        try #"{"profiles":{"minimax:cn":{"provider":"minimax"}}}"#.write(
            to: backupAgentDirectory.appendingPathComponent("auth-profiles.json", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try #"{"providers":{"minimax":{"models":[{"id":"MiniMax-M2.5"}]}}}"#.write(
            to: backupAgentDirectory.appendingPathComponent("models.json", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        let registration = manager.registerUserProvidedLocalBootstrapDirectory(bootstrapRootURL)
        XCTAssertTrue(registration.success, registration.message)

        let completion = expectation(description: "sync completed")
        manager.syncProjectAgentsToActiveSession(mutableProject) { result in
            XCTAssertEqual(result.deploymentStatus, .appliedToRuntime)
            XCTAssertNil(result.errorMessage)
            completion.fulfill()
        }

        wait(for: [completion], timeout: 5.0)
        drainMainQueue()

        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: runtimeRootURL
                    .appendingPathComponent("agents/任务中心-任务领域-1/agent/auth-profiles.json", isDirectory: false)
                    .path
            )
        )

        let configData = try Data(contentsOf: configFileURL)
        let configObject = try XCTUnwrap(JSONSerialization.jsonObject(with: configData) as? [String: Any])
        let agentsObject = try XCTUnwrap(configObject["agents"] as? [String: Any])
        let list = try XCTUnwrap(agentsObject["list"] as? [[String: Any]])
        XCTAssertTrue(list.contains { ($0["id"] as? String) == "任务中心-任务领域-1" })
    }

    func testSyncRegistersDeferredAgentUsingManagedNodeWorkspace() throws {
        let manager = OpenClawManager(notificationCenter: NotificationCenter())
        let tempDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let runtimeRootURL = tempDirectory.appendingPathComponent("runtime-root", isDirectory: true)
        let mainAgentDirectory = runtimeRootURL.appendingPathComponent("agents/main/agent", isDirectory: true)
        try FileManager.default.createDirectory(at: mainAgentDirectory, withIntermediateDirectories: true)
        let configFileURL = runtimeRootURL.appendingPathComponent("openclaw.json", isDirectory: false)
        try """
        {
          "agents": {
            "list": [
              {
                "id": "main",
                "name": "main",
                "workspace": "\(runtimeRootURL.appendingPathComponent("workspace", isDirectory: true).path)",
                "agentDir": "\(mainAgentDirectory.path)"
              }
            ]
          }
        }
        """.write(to: configFileURL, atomically: true, encoding: .utf8)
        try #"{"profiles":{"minimax:cn":{"provider":"minimax"}}}"#.write(
            to: mainAgentDirectory.appendingPathComponent("auth-profiles.json", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try #"{"providers":{"minimax":{"models":[{"id":"MiniMax-M2.5"}]}}}"#.write(
            to: mainAgentDirectory.appendingPathComponent("models.json", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        let executableURL = try makeMutableOpenClawScript(in: tempDirectory, configFileURL: configFileURL)

        var config = OpenClawConfig.default
        config.deploymentKind = .local
        config.localBinaryPath = executableURL.path
        config.autoConnect = false
        manager.config = config

        let project = MAProject(name: "Deferred Workspace Sync")
        defer {
            try? FileManager.default.removeItem(at: ProjectManager.shared.openClawProjectRoot(for: project.id))
        }

        let agent = makeDeferredProjectAgent(name: "任务中心-任务领域-1")
        var workflow = Workflow(name: "Main Workflow")
        var node = WorkflowNode(type: .agent)
        node.agentID = agent.id
        node.title = agent.name
        workflow.nodes = [node]

        var mutableProject = project
        mutableProject.agents = [agent]
        mutableProject.workflows = [workflow]

        let expectedWorkspacePath = runtimeRootURL
            .appendingPathComponent("agents/任务中心-任务领域-1/workspace", isDirectory: true)
            .path

        try manager.beginSession(for: mutableProject.id)
        manager.isConnected = true

        let completion = expectation(description: "deferred workspace sync completed")
        manager.syncProjectAgentsToActiveSession(mutableProject) { result in
            XCTAssertEqual(result.deploymentStatus, .appliedToRuntime)
            XCTAssertNil(result.errorMessage)
            XCTAssertTrue(result.workspacePathRequiredAgentNames.isEmpty)
            completion.fulfill()
        }

        wait(for: [completion], timeout: 5.0)
        drainMainQueue()

        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedWorkspacePath))

        let configData = try Data(contentsOf: configFileURL)
        let configText = try XCTUnwrap(String(data: configData, encoding: .utf8))
        XCTAssertFalse(configText.contains("\\/"))
        let configObject = try XCTUnwrap(JSONSerialization.jsonObject(with: configData) as? [String: Any])
        let agentsObject = try XCTUnwrap(configObject["agents"] as? [String: Any])
        let list = try XCTUnwrap(agentsObject["list"] as? [[String: Any]])
        let registered = try XCTUnwrap(list.first { ($0["id"] as? String) == "任务中心-任务领域-1" })
        XCTAssertEqual(registered["workspace"] as? String, expectedWorkspacePath)
    }

    func testSyncMergePreservesExistingMainAuthFilesWhenProjectMirrorDoesNotContainThem() throws {
        let manager = OpenClawManager(notificationCenter: NotificationCenter())
        let tempDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let runtimeRootURL = tempDirectory.appendingPathComponent("runtime-root", isDirectory: true)
        let mainAgentDirectory = runtimeRootURL.appendingPathComponent("agents/main/agent", isDirectory: true)
        try FileManager.default.createDirectory(at: mainAgentDirectory, withIntermediateDirectories: true)
        let configFileURL = runtimeRootURL.appendingPathComponent("openclaw.json", isDirectory: false)
        try """
        {
          "agents": {
            "list": [
              {
                "id": "main",
                "name": "main",
                "workspace": "\(runtimeRootURL.appendingPathComponent("workspace", isDirectory: true).path)",
                "agentDir": "\(mainAgentDirectory.path)"
              }
            ]
          }
        }
        """.write(to: configFileURL, atomically: true, encoding: .utf8)
        let preservedAuthPath = mainAgentDirectory.appendingPathComponent("auth-profiles.json", isDirectory: false)
        try #"{"profiles":{"minimax:cn":{"provider":"minimax"}}}"#.write(
            to: preservedAuthPath,
            atomically: true,
            encoding: .utf8
        )
        try #"{"providers":{"minimax":{"models":[{"id":"MiniMax-M2.5"}]}}}"#.write(
            to: mainAgentDirectory.appendingPathComponent("models.json", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        let executableURL = try makeMutableOpenClawScript(in: tempDirectory, configFileURL: configFileURL)

        var config = OpenClawConfig.default
        config.deploymentKind = .local
        config.localBinaryPath = executableURL.path
        config.autoConnect = false
        manager.config = config

        let project = MAProject(name: "Merge Sync")
        defer {
            try? FileManager.default.removeItem(at: ProjectManager.shared.openClawProjectRoot(for: project.id))
        }

        let mirrorURL = ProjectManager.shared.openClawMirrorDirectory(for: project.id)
        try FileManager.default.createDirectory(at: mirrorURL, withIntermediateDirectories: true)
        try "placeholder".write(
            to: mirrorURL.appendingPathComponent(".keep", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        let workspaceRootURL = tempDirectory.appendingPathComponent("merge-workspace", isDirectory: true)
        let agent = try makeProjectAgent(name: "任务中心-任务领域-1", workspaceRootURL: workspaceRootURL)
        var workflow = Workflow(name: "Main Workflow")
        var node = WorkflowNode(type: .agent)
        node.agentID = agent.id
        node.title = agent.name
        workflow.nodes = [node]
        var mutableProject = project
        mutableProject.agents = [agent]
        mutableProject.workflows = [workflow]

        try manager.beginSession(for: mutableProject.id)
        manager.isConnected = true

        let completion = expectation(description: "merge sync completed")
        manager.syncProjectAgentsToActiveSession(mutableProject) { result in
            XCTAssertEqual(result.deploymentStatus, .appliedToRuntime)
            XCTAssertNil(result.errorMessage)
            completion.fulfill()
        }

        wait(for: [completion], timeout: 5.0)
        drainMainQueue()

        let preservedContent = try String(contentsOf: preservedAuthPath, encoding: .utf8)
        XCTAssertTrue(preservedContent.contains(#""provider":"minimax""#))
    }

    func testSyncDoesNotUseProjectBackupAsAutomaticBootstrapSource() throws {
        let manager = OpenClawManager(notificationCenter: NotificationCenter())
        let tempDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let runtimeRootURL = tempDirectory.appendingPathComponent("runtime-root", isDirectory: true)
        let mainAgentDirectory = runtimeRootURL.appendingPathComponent("agents/main/agent", isDirectory: true)
        try FileManager.default.createDirectory(at: mainAgentDirectory, withIntermediateDirectories: true)
        let configFileURL = runtimeRootURL.appendingPathComponent("openclaw.json", isDirectory: false)
        try """
        {
          "agents": {
            "list": [
              {
                "id": "main",
                "name": "main",
                "workspace": "\(runtimeRootURL.appendingPathComponent("workspace", isDirectory: true).path)",
                "agentDir": "\(mainAgentDirectory.path)"
              }
            ]
          }
        }
        """.write(to: configFileURL, atomically: true, encoding: .utf8)

        let executableURL = try makeMutableOpenClawScript(in: tempDirectory, configFileURL: configFileURL)
        var config = OpenClawConfig.default
        config.deploymentKind = .local
        config.localBinaryPath = executableURL.path
        config.autoConnect = false
        manager.config = config

        let project = MAProject(name: "No Auto Backup Bootstrap")
        defer {
            try? FileManager.default.removeItem(at: ProjectManager.shared.openClawProjectRoot(for: project.id))
        }

        let workspaceRootURL = tempDirectory.appendingPathComponent("no-auto-workspace", isDirectory: true)
        let agent = try makeProjectAgent(name: "任务中心-任务领域-1", workspaceRootURL: workspaceRootURL)
        var workflow = Workflow(name: "Main Workflow")
        var node = WorkflowNode(type: .agent)
        node.agentID = agent.id
        node.title = agent.name
        workflow.nodes = [node]
        var mutableProject = project
        mutableProject.agents = [agent]
        mutableProject.workflows = [workflow]

        try manager.beginSession(for: mutableProject.id)
        manager.isConnected = true

        let backupAgentDirectory = ProjectManager.shared.openClawBackupDirectory(for: mutableProject.id)
            .appendingPathComponent("agents/main/agent", isDirectory: true)
        try FileManager.default.createDirectory(at: backupAgentDirectory, withIntermediateDirectories: true)
        try #"{"profiles":{"minimax:cn":{"provider":"minimax"}}}"#.write(
            to: backupAgentDirectory.appendingPathComponent("auth-profiles.json", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try #"{"providers":{"minimax":{"models":[{"id":"MiniMax-M2.5"}]}}}"#.write(
            to: backupAgentDirectory.appendingPathComponent("models.json", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        let completion = expectation(description: "sync failed without manual bootstrap")
        manager.syncProjectAgentsToActiveSession(mutableProject) { result in
            XCTAssertEqual(result.deploymentStatus, .failed)
            XCTAssertEqual(result.bootstrapPathRequiredAgentNames, ["任务中心-任务领域-1"])
            XCTAssertNotNil(result.errorMessage)
            completion.fulfill()
        }

        wait(for: [completion], timeout: 5.0)
        drainMainQueue()
    }

    func testSyncSkipsUnboundAgentsFromAutomaticRegistration() throws {
        let manager = OpenClawManager(notificationCenter: NotificationCenter())
        let tempDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let runtimeRootURL = tempDirectory.appendingPathComponent("runtime-root", isDirectory: true)
        let mainAgentDirectory = runtimeRootURL.appendingPathComponent("agents/main/agent", isDirectory: true)
        try FileManager.default.createDirectory(at: mainAgentDirectory, withIntermediateDirectories: true)
        let configFileURL = runtimeRootURL.appendingPathComponent("openclaw.json", isDirectory: false)
        try """
        {
          "agents": {
            "list": [
              {
                "id": "main",
                "name": "main",
                "workspace": "\(runtimeRootURL.appendingPathComponent("workspace", isDirectory: true).path)",
                "agentDir": "\(mainAgentDirectory.path)"
              }
            ]
          }
        }
        """.write(to: configFileURL, atomically: true, encoding: .utf8)
        try #"{"profiles":{"minimax:cn":{"provider":"minimax"}}}"#.write(
            to: mainAgentDirectory.appendingPathComponent("auth-profiles.json", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try #"{"providers":{"minimax":{"models":[{"id":"MiniMax-M2.5"}]}}}"#.write(
            to: mainAgentDirectory.appendingPathComponent("models.json", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        let executableURL = try makeMutableOpenClawScript(in: tempDirectory, configFileURL: configFileURL)
        var config = OpenClawConfig.default
        config.deploymentKind = .local
        config.localBinaryPath = executableURL.path
        config.autoConnect = false
        manager.config = config

        let project = MAProject(name: "Skip Unbound Agents")
        defer {
            try? FileManager.default.removeItem(at: ProjectManager.shared.openClawProjectRoot(for: project.id))
        }

        let boundAgent = makeDeferredProjectAgent(name: "任务中心-任务领域-1")
        let unboundAgent = makeDeferredProjectAgent(name: "训练测试-任务领域-1")
        var workflow = Workflow(name: "Main Workflow")
        var node = WorkflowNode(type: .agent)
        node.agentID = boundAgent.id
        node.title = boundAgent.name
        workflow.nodes = [node]

        var mutableProject = project
        mutableProject.agents = [boundAgent, unboundAgent]
        mutableProject.workflows = [workflow]

        try manager.beginSession(for: mutableProject.id)
        manager.isConnected = true

        let completion = expectation(description: "sync completed while skipping unbound agent")
        manager.syncProjectAgentsToActiveSession(mutableProject) { result in
            XCTAssertEqual(result.deploymentStatus, .appliedToRuntime)
            XCTAssertTrue(result.workspacePathRequiredAgentNames.isEmpty)
            XCTAssertTrue(result.bootstrapPathRequiredAgentNames.isEmpty)
            XCTAssertNil(result.errorMessage)
            XCTAssertTrue(
                result.runtimeWarnings.contains(where: { $0.contains("训练测试-任务领域-1") && $0.contains("跳过自动注册") })
            )
            completion.fulfill()
        }

        wait(for: [completion], timeout: 5.0)
        drainMainQueue()

        let configData = try Data(contentsOf: configFileURL)
        let configObject = try XCTUnwrap(JSONSerialization.jsonObject(with: configData) as? [String: Any])
        let agentsObject = try XCTUnwrap(configObject["agents"] as? [String: Any])
        let list = try XCTUnwrap(agentsObject["list"] as? [[String: Any]])
        XCTAssertTrue(list.contains { ($0["id"] as? String) == "任务中心-任务领域-1" })
        XCTAssertFalse(list.contains { ($0["id"] as? String) == "训练测试-任务领域-1" })
    }

    func testSyncUsesSelectedWorkflowBindingForSharedAgentWorkspaceRegistration() throws {
        let manager = OpenClawManager(notificationCenter: NotificationCenter())
        let tempDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let runtimeRootURL = tempDirectory.appendingPathComponent("runtime-root", isDirectory: true)
        let mainAgentDirectory = runtimeRootURL.appendingPathComponent("agents/main/agent", isDirectory: true)
        try FileManager.default.createDirectory(at: mainAgentDirectory, withIntermediateDirectories: true)
        let configFileURL = runtimeRootURL.appendingPathComponent("openclaw.json", isDirectory: false)
        try """
        {
          "agents": {
            "list": [
              {
                "id": "main",
                "name": "main",
                "workspace": "\(runtimeRootURL.appendingPathComponent("workspace", isDirectory: true).path)",
                "agentDir": "\(mainAgentDirectory.path)"
              }
            ]
          }
        }
        """.write(to: configFileURL, atomically: true, encoding: .utf8)
        try #"{"profiles":{"minimax:cn":{"provider":"minimax"}}}"#.write(
            to: mainAgentDirectory.appendingPathComponent("auth-profiles.json", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try #"{"providers":{"minimax":{"models":[{"id":"MiniMax-M2.5"}]}}}"#.write(
            to: mainAgentDirectory.appendingPathComponent("models.json", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        let executableURL = try makeMutableOpenClawScript(in: tempDirectory, configFileURL: configFileURL)
        var config = OpenClawConfig.default
        config.deploymentKind = .local
        config.localBinaryPath = executableURL.path
        config.autoConnect = false
        manager.config = config

        let project = MAProject(name: "Selected Workflow Sync")
        defer {
            try? FileManager.default.removeItem(at: ProjectManager.shared.openClawProjectRoot(for: project.id))
        }

        let sharedAgent = makeDeferredProjectAgent(name: "任务中心-任务领域-1")

        var workflowA = Workflow(name: "Workflow A")
        var nodeA = WorkflowNode(type: .agent)
        nodeA.agentID = sharedAgent.id
        nodeA.title = sharedAgent.name
        workflowA.nodes = [nodeA]

        var workflowB = Workflow(name: "Workflow B")
        var nodeB = WorkflowNode(type: .agent)
        nodeB.agentID = sharedAgent.id
        nodeB.title = sharedAgent.name
        workflowB.nodes = [nodeB]

        var mutableProject = project
        mutableProject.agents = [sharedAgent]
        mutableProject.workflows = [workflowA, workflowB]

        let expectedWorkspacePath = runtimeRootURL
            .appendingPathComponent("agents/任务中心-任务领域-1/workspace", isDirectory: true)
            .path
        let unexpectedWorkspacePath = ProjectFileSystem.shared.nodeOpenClawWorkspaceDirectory(
            for: nodeA.id,
            workflowID: workflowA.id,
            projectID: project.id,
            under: ProjectManager.shared.appSupportRootDirectory
        ).path

        try manager.beginSession(for: mutableProject.id)
        manager.isConnected = true

        let completion = expectation(description: "selected workflow sync completed")
        manager.syncProjectAgentsToActiveSession(mutableProject, workflowID: workflowB.id) { result in
            XCTAssertEqual(result.deploymentStatus, .appliedToRuntime)
            XCTAssertNil(result.errorMessage)
            completion.fulfill()
        }

        wait(for: [completion], timeout: 5.0)
        drainMainQueue()

        let configData = try Data(contentsOf: configFileURL)
        let configObject = try XCTUnwrap(JSONSerialization.jsonObject(with: configData) as? [String: Any])
        let agentsObject = try XCTUnwrap(configObject["agents"] as? [String: Any])
        let list = try XCTUnwrap(agentsObject["list"] as? [[String: Any]])
        let registered = try XCTUnwrap(list.first { ($0["id"] as? String) == "任务中心-任务领域-1" })
        XCTAssertEqual(registered["workspace"] as? String, expectedWorkspacePath)
        XCTAssertNotEqual(registered["workspace"] as? String, unexpectedWorkspacePath)
    }

    func testFirstRegistrationSeedsModelAndBindingsFromExistingBootstrapAgent() throws {
        let manager = OpenClawManager(notificationCenter: NotificationCenter())
        let tempDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let runtimeRootURL = tempDirectory.appendingPathComponent("runtime-root", isDirectory: true)
        let mainAgentDirectory = runtimeRootURL.appendingPathComponent("agents/main/agent", isDirectory: true)
        try FileManager.default.createDirectory(at: mainAgentDirectory, withIntermediateDirectories: true)
        let configFileURL = runtimeRootURL.appendingPathComponent("openclaw.json", isDirectory: false)
        try """
        {
          "agents": {
            "list": [
              {
                "id": "main",
                "name": "main",
                "workspace": "\(runtimeRootURL.appendingPathComponent("workspace", isDirectory: true).path)",
                "agentDir": "\(mainAgentDirectory.path)",
                "model": "minimax/MiniMax-M2.5"
              }
            ]
          },
          "bindings": [
            {
              "agent": "main",
              "channel": "chat",
              "account": "default"
            }
          ]
        }
        """.write(to: configFileURL, atomically: true, encoding: .utf8)
        try #"{"profiles":{"minimax:cn":{"provider":"minimax"}}}"#.write(
            to: mainAgentDirectory.appendingPathComponent("auth-profiles.json", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try #"{"providers":{"minimax":{"models":[{"id":"MiniMax-M2.5"}]}}}"#.write(
            to: mainAgentDirectory.appendingPathComponent("models.json", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        let executableURL = try makeMutableOpenClawScript(in: tempDirectory, configFileURL: configFileURL)
        var config = OpenClawConfig.default
        config.deploymentKind = .local
        config.localBinaryPath = executableURL.path
        config.autoConnect = false
        manager.config = config

        let project = MAProject(name: "Seeded Runtime Activation")
        defer {
            try? FileManager.default.removeItem(at: ProjectManager.shared.openClawProjectRoot(for: project.id))
        }

        var agent = makeDeferredProjectAgent(name: "任务中心-任务领域-1")
        agent.openClawDefinition.modelIdentifier = ""
        var workflow = Workflow(name: "Main Workflow")
        var node = WorkflowNode(type: .agent)
        node.agentID = agent.id
        node.title = agent.name
        workflow.nodes = [node]

        var mutableProject = project
        mutableProject.agents = [agent]
        mutableProject.workflows = [workflow]

        try manager.beginSession(for: mutableProject.id)
        manager.isConnected = true

        let completion = expectation(description: "seeded registration completed")
        manager.syncProjectAgentsToActiveSession(mutableProject) { result in
            XCTAssertEqual(result.deploymentStatus, .appliedToRuntime)
            XCTAssertNil(result.errorMessage)
            XCTAssertTrue(result.bootstrapPathRequiredAgentNames.isEmpty)
            completion.fulfill()
        }

        wait(for: [completion], timeout: 5.0)
        drainMainQueue()

        let configData = try Data(contentsOf: configFileURL)
        let configObject = try XCTUnwrap(JSONSerialization.jsonObject(with: configData) as? [String: Any])
        let agentsObject = try XCTUnwrap(configObject["agents"] as? [String: Any])
        let list = try XCTUnwrap(agentsObject["list"] as? [[String: Any]])
        let registered = try XCTUnwrap(list.first { ($0["id"] as? String) == "任务中心-任务领域-1" })
        XCTAssertEqual(registered["model"] as? String, "minimax/MiniMax-M2.5")

        let bindings = try XCTUnwrap(configObject["bindings"] as? [[String: Any]])
        XCTAssertTrue(bindings.contains {
            ($0["agent"] as? String) == "任务中心-任务领域-1"
                && ($0["channel"] as? String) == "chat"
                && ($0["account"] as? String) == "default"
        })
    }

    func testSnapshotRestorePreservesManualBootstrapDirectoryForSubsequentSync() throws {
        let originalManager = OpenClawManager(notificationCenter: NotificationCenter())
        let restoredManager = OpenClawManager(notificationCenter: NotificationCenter())
        let tempDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let runtimeRootURL = tempDirectory.appendingPathComponent("runtime-root", isDirectory: true)
        try FileManager.default.createDirectory(at: runtimeRootURL, withIntermediateDirectories: true)
        let configFileURL = runtimeRootURL.appendingPathComponent("openclaw.json", isDirectory: false)
        try """
        {
          "agents": {
            "list": [
              {
                "id": "main",
                "name": "main",
                "workspace": "\(runtimeRootURL.appendingPathComponent("workspace", isDirectory: true).path)",
                "agentDir": "\(runtimeRootURL.appendingPathComponent("agents/main/agent", isDirectory: true).path)"
              }
            ]
          }
        }
        """.write(to: configFileURL, atomically: true, encoding: .utf8)

        let executableURL = try makeMutableOpenClawScript(in: tempDirectory, configFileURL: configFileURL)
        var config = OpenClawConfig.default
        config.deploymentKind = .local
        config.localBinaryPath = executableURL.path
        config.autoConnect = false
        originalManager.config = config

        let project = MAProject(name: "Persist Bootstrap Sync")
        defer {
            try? FileManager.default.removeItem(at: ProjectManager.shared.openClawProjectRoot(for: project.id))
        }

        let workspaceRootURL = tempDirectory.appendingPathComponent("persist-bootstrap-workspace", isDirectory: true)
        let agent = try makeProjectAgent(name: "任务中心-任务领域-1", workspaceRootURL: workspaceRootURL)
        var workflow = Workflow(name: "Main Workflow")
        var node = WorkflowNode(type: .agent)
        node.agentID = agent.id
        node.title = agent.name
        workflow.nodes = [node]

        var mutableProject = project
        mutableProject.agents = [agent]
        mutableProject.workflows = [workflow]

        let bootstrapRootURL = tempDirectory.appendingPathComponent("bootstrap-root", isDirectory: true)
        let bootstrapAgentDirectory = bootstrapRootURL.appendingPathComponent("main/agent", isDirectory: true)
        try FileManager.default.createDirectory(at: bootstrapAgentDirectory, withIntermediateDirectories: true)
        try #"{"profiles":{"minimax:cn":{"provider":"minimax"}}}"#.write(
            to: bootstrapAgentDirectory.appendingPathComponent("auth-profiles.json", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try #"{"providers":{"minimax":{"models":[{"id":"MiniMax-M2.5"}]}}}"#.write(
            to: bootstrapAgentDirectory.appendingPathComponent("models.json", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        let bootstrapRegistration = originalManager.registerUserProvidedLocalBootstrapDirectory(bootstrapRootURL)
        XCTAssertTrue(bootstrapRegistration.success, bootstrapRegistration.message)

        let snapshot = originalManager.snapshot()
        XCTAssertEqual(snapshot.localRuntimeBootstrapDirectory, bootstrapRootURL.path)

        restoredManager.restore(from: snapshot)
        try restoredManager.beginSession(for: mutableProject.id)
        restoredManager.isConnected = true

        let completion = expectation(description: "restored bootstrap sync completed")
        restoredManager.syncProjectAgentsToActiveSession(mutableProject) { result in
            XCTAssertEqual(result.deploymentStatus, .appliedToRuntime)
            XCTAssertNil(result.errorMessage)
            XCTAssertTrue(result.bootstrapPathRequiredAgentNames.isEmpty)
            completion.fulfill()
        }

        wait(for: [completion], timeout: 5.0)
        drainMainQueue()

        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: runtimeRootURL
                    .appendingPathComponent("agents/任务中心-任务领域-1/agent/auth-profiles.json", isDirectory: false)
                    .path
            )
        )
    }

    func testSnapshotRestorePreservesManualWorkspaceDirectoryForSubsequentRegistration() throws {
        let originalManager = OpenClawManager(notificationCenter: NotificationCenter())
        let restoredManager = OpenClawManager(notificationCenter: NotificationCenter())
        let tempDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let runtimeRootURL = tempDirectory.appendingPathComponent("runtime-root", isDirectory: true)
        let mainAgentDirectory = runtimeRootURL.appendingPathComponent("agents/main/agent", isDirectory: true)
        try FileManager.default.createDirectory(at: mainAgentDirectory, withIntermediateDirectories: true)
        let configFileURL = runtimeRootURL.appendingPathComponent("openclaw.json", isDirectory: false)
        try """
        {
          "agents": {
            "list": [
              {
                "id": "main",
                "name": "main",
                "workspace": "\(runtimeRootURL.appendingPathComponent("workspace", isDirectory: true).path)",
                "agentDir": "\(mainAgentDirectory.path)"
              }
            ]
          }
        }
        """.write(to: configFileURL, atomically: true, encoding: .utf8)
        try #"{"profiles":{"minimax:cn":{"provider":"minimax"}}}"#.write(
            to: mainAgentDirectory.appendingPathComponent("auth-profiles.json", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try #"{"providers":{"minimax":{"models":[{"id":"MiniMax-M2.5"}]}}}"#.write(
            to: mainAgentDirectory.appendingPathComponent("models.json", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        let executableURL = try makeMutableOpenClawScript(in: tempDirectory, configFileURL: configFileURL)
        var config = OpenClawConfig.default
        config.deploymentKind = .local
        config.localBinaryPath = executableURL.path
        config.autoConnect = false
        originalManager.config = config

        let agent = makeDeferredProjectAgent(name: "任务中心-任务领域-1")
        let workflowID = UUID()
        let nodeID = UUID()
        let workspaceRootURL = tempDirectory.appendingPathComponent("manual-workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceRootURL, withIntermediateDirectories: true)

        let requirement = OpenClawManager.LocalRuntimeWorkspaceRequirement(
            agentID: agent.id,
            workflowID: workflowID,
            nodeID: nodeID,
            agentName: agent.name,
            targetIdentifier: agent.name
        )
        let workspaceRegistration = originalManager.registerUserProvidedLocalWorkspaceDirectory(
            workspaceRootURL,
            for: requirement
        )
        XCTAssertTrue(workspaceRegistration.success, workspaceRegistration.message)

        let snapshot = originalManager.snapshot()
        XCTAssertEqual(snapshot.localRuntimeWorkspaceDirectoriesByNodeID[nodeID.uuidString], workspaceRootURL.path)
        XCTAssertEqual(snapshot.localRuntimeWorkspaceDirectoriesByAgentID[agent.id.uuidString], workspaceRootURL.path)

        restoredManager.restore(from: snapshot)
        XCTAssertEqual(restoredManager.resolvedWorkspacePath(for: agent), workspaceRootURL.path)

        let registration = restoredManager.ensureLocalRuntimeAgentRegistration(for: agent, using: config)
        XCTAssertTrue(registration.success, registration.message)
        XCTAssertEqual(registration.workspaceRequirement, nil)

        let configData = try Data(contentsOf: configFileURL)
        let configObject = try XCTUnwrap(JSONSerialization.jsonObject(with: configData) as? [String: Any])
        let agentsObject = try XCTUnwrap(configObject["agents"] as? [String: Any])
        let list = try XCTUnwrap(agentsObject["list"] as? [[String: Any]])
        let registered = try XCTUnwrap(list.first { ($0["id"] as? String) == "任务中心-任务领域-1" })
        let expectedWorkspacePath = runtimeRootURL
            .appendingPathComponent("agents/任务中心-任务领域-1/workspace", isDirectory: true)
            .path
        XCTAssertEqual(registered["workspace"] as? String, expectedWorkspacePath)
    }

    func testResolvedWorkspacePathSkipsAmbiguousLocalConfigRecords() throws {
        let manager = OpenClawManager(notificationCenter: NotificationCenter())
        let tempDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let runtimeRootURL = tempDirectory.appendingPathComponent("runtime-root", isDirectory: true)
        try FileManager.default.createDirectory(at: runtimeRootURL, withIntermediateDirectories: true)
        let workspaceAURL = tempDirectory.appendingPathComponent("workspace-a", isDirectory: true)
        let workspaceBURL = tempDirectory.appendingPathComponent("workspace-b", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceAURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: workspaceBURL, withIntermediateDirectories: true)

        let configFileURL = runtimeRootURL.appendingPathComponent("openclaw.json", isDirectory: false)
        try """
        {
          "agents": {
            "list": [
              {
                "id": "任务中心-任务领域-1",
                "name": "任务中心-任务领域-1",
                "workspace": "\(workspaceAURL.path)"
              },
              {
                "id": "legacy-task-domain-1",
                "name": "任务中心-任务领域-1",
                "workspace": "\(workspaceBURL.path)"
              }
            ]
          }
        }
        """.write(to: configFileURL, atomically: true, encoding: .utf8)

        let executableURL = try makeMutableOpenClawScript(in: tempDirectory, configFileURL: configFileURL)
        var config = OpenClawConfig.default
        config.deploymentKind = .local
        config.localBinaryPath = executableURL.path
        config.autoConnect = false
        manager.config = config

        let agent = makeDeferredProjectAgent(name: "任务中心-任务领域-1")
        XCTAssertNil(manager.resolvedWorkspacePath(for: agent))
    }

    func testResolvedWorkspacePathAcceptsDuplicateLocalConfigRecordsWhenWorkspaceConsistent() throws {
        let manager = OpenClawManager(notificationCenter: NotificationCenter())
        let tempDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let runtimeRootURL = tempDirectory.appendingPathComponent("runtime-root", isDirectory: true)
        try FileManager.default.createDirectory(at: runtimeRootURL, withIntermediateDirectories: true)
        let workspaceURL = tempDirectory.appendingPathComponent("shared-workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)

        let configFileURL = runtimeRootURL.appendingPathComponent("openclaw.json", isDirectory: false)
        try """
        {
          "agents": {
            "list": [
              {
                "id": "任务中心-任务领域-1",
                "name": "任务中心-任务领域-1",
                "workspace": "\(workspaceURL.path)"
              },
              {
                "id": "legacy-task-domain-1",
                "name": "任务中心-任务领域-1",
                "workspace": "\(workspaceURL.path)"
              }
            ]
          }
        }
        """.write(to: configFileURL, atomically: true, encoding: .utf8)

        let executableURL = try makeMutableOpenClawScript(in: tempDirectory, configFileURL: configFileURL)
        var config = OpenClawConfig.default
        config.deploymentKind = .local
        config.localBinaryPath = executableURL.path
        config.autoConnect = false
        manager.config = config

        let agent = makeDeferredProjectAgent(name: "任务中心-任务领域-1")
        XCTAssertEqual(manager.resolvedWorkspacePath(for: agent), workspaceURL.path)
    }

    func testRegistrationCanonicalizesDuplicateLocalConfigEntries() throws {
        let manager = OpenClawManager(notificationCenter: NotificationCenter())
        let tempDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let runtimeRootURL = tempDirectory.appendingPathComponent("runtime-root", isDirectory: true)
        let mainAgentDirectory = runtimeRootURL.appendingPathComponent("agents/main/agent", isDirectory: true)
        let targetAgentDirectory = runtimeRootURL.appendingPathComponent("agents/任务中心-任务领域-1/agent", isDirectory: true)
        let legacyAgentDirectory = runtimeRootURL.appendingPathComponent("agents/legacy-task-domain-1/agent", isDirectory: true)
        try FileManager.default.createDirectory(at: mainAgentDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: targetAgentDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: legacyAgentDirectory, withIntermediateDirectories: true)

        try #"{"profiles":{"minimax:cn":{"provider":"minimax"}}}"#.write(
            to: mainAgentDirectory.appendingPathComponent("auth-profiles.json", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try #"{"providers":{"minimax":{"models":[{"id":"MiniMax-M2.5"}]}}}"#.write(
            to: mainAgentDirectory.appendingPathComponent("models.json", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        let currentWorkspaceURL = tempDirectory.appendingPathComponent("current-workspace", isDirectory: true)
        let staleWorkspaceURL = tempDirectory.appendingPathComponent("stale-workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: currentWorkspaceURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: staleWorkspaceURL, withIntermediateDirectories: true)

        let configFileURL = runtimeRootURL.appendingPathComponent("openclaw.json", isDirectory: false)
        try """
        {
          "agents": {
            "list": [
              {
                "id": "main",
                "name": "main",
                "workspace": "\(runtimeRootURL.appendingPathComponent("workspace", isDirectory: true).path)",
                "agentDir": "\(mainAgentDirectory.path)"
              },
              {
                "id": "任务中心-任务领域-1",
                "name": "旧任务领域",
                "workspace": "\(staleWorkspaceURL.path)",
                "agentDir": "\(targetAgentDirectory.path)"
              },
              {
                "id": "legacy-task-domain-1",
                "name": "任务中心-任务领域-1",
                "workspace": "\(staleWorkspaceURL.path)",
                "agentDir": "\(legacyAgentDirectory.path)"
              }
            ]
          }
        }
        """.write(to: configFileURL, atomically: true, encoding: .utf8)

        let executableURL = try makeMutableOpenClawScript(in: tempDirectory, configFileURL: configFileURL)
        var config = OpenClawConfig.default
        config.deploymentKind = .local
        config.localBinaryPath = executableURL.path
        config.autoConnect = false
        manager.config = config

        let agent = makeDeferredProjectAgent(name: "任务中心-任务领域-1")
        let requirement = OpenClawManager.LocalRuntimeWorkspaceRequirement(
            agentID: agent.id,
            workflowID: UUID(),
            nodeID: UUID(),
            agentName: agent.name,
            targetIdentifier: agent.name
        )
        let workspaceRegistration = manager.registerUserProvidedLocalWorkspaceDirectory(
            currentWorkspaceURL,
            for: requirement
        )
        XCTAssertTrue(workspaceRegistration.success, workspaceRegistration.message)

        let registration = manager.ensureLocalRuntimeAgentRegistration(for: agent, using: config)
        XCTAssertTrue(registration.success, registration.message)

        let configData = try Data(contentsOf: configFileURL)
        let configObject = try XCTUnwrap(JSONSerialization.jsonObject(with: configData) as? [String: Any])
        let agentsObject = try XCTUnwrap(configObject["agents"] as? [String: Any])
        let list = try XCTUnwrap(agentsObject["list"] as? [[String: Any]])

        XCTAssertEqual(list.count, 3)
        let matchingEntries = list.filter { ($0["id"] as? String) == "任务中心-任务领域-1" }
        XCTAssertEqual(matchingEntries.count, 1)
        XCTAssertEqual(matchingEntries.first?["id"] as? String, "任务中心-任务领域-1")
        XCTAssertEqual(matchingEntries.first?["name"] as? String, "任务中心-任务领域-1")
        let expectedWorkspacePath = runtimeRootURL
            .appendingPathComponent("agents/任务中心-任务领域-1/workspace", isDirectory: true)
            .path
        XCTAssertEqual(matchingEntries.first?["workspace"] as? String, expectedWorkspacePath)
        XCTAssertTrue(list.contains {
            ($0["id"] as? String) == "legacy-task-domain-1"
                && ($0["name"] as? String) == "任务中心-任务领域-1"
        })
    }

}
