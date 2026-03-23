import XCTest
import Darwin
@testable import Multi_Agent_Flow

final class OpenClawManagedRuntimeManagerTests: XCTestCase {
    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenClawManagedRuntimeManagerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func drainMainQueue() {
        let expectation = expectation(description: "main queue drained")
        DispatchQueue.main.async {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }

    private func pumpMainRunLoop(until deadline: Date, step: TimeInterval = 0.05) {
        while Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(step))
        }
    }

    private func makeManagedRuntimeGatewayBinary(at binaryURL: URL) throws {
        let fileManager = FileManager.default
        let runtimeRootURL = binaryURL.deletingLastPathComponent().deletingLastPathComponent()
        let configFileURL = runtimeRootURL.appendingPathComponent("openclaw.json", isDirectory: false)
        let alphaAgentDirectory = runtimeRootURL.appendingPathComponent("agents/agent-alpha", isDirectory: true)
        let betaAgentDirectory = runtimeRootURL.appendingPathComponent("agents/agent-beta", isDirectory: true)
        let alphaWorkspaceURL = runtimeRootURL.appendingPathComponent("workspace/agent-alpha", isDirectory: true)
        let betaWorkspaceURL = runtimeRootURL.appendingPathComponent("workspace/agent-beta", isDirectory: true)

        try fileManager.createDirectory(at: binaryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: alphaAgentDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: betaAgentDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: alphaWorkspaceURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: betaWorkspaceURL, withIntermediateDirectories: true)

        try "# runtime alpha baseline\n".write(
            to: alphaAgentDirectory.appendingPathComponent("SOUL.md", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try "# runtime beta baseline\n".write(
            to: betaAgentDirectory.appendingPathComponent("SOUL.md", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try """
        {
          "agents": {
            "list": [
              {
                "id": "agent-alpha",
                "name": "Alpha Agent",
                "workspace": "\(alphaWorkspaceURL.path)",
                "agentDir": "\(alphaAgentDirectory.path)"
              },
              {
                "id": "agent-beta",
                "name": "Beta Agent",
                "workspace": "\(betaWorkspaceURL.path)",
                "agentDir": "\(betaAgentDirectory.path)"
              }
            ]
          }
        }
        """.write(to: configFileURL, atomically: true, encoding: .utf8)

        try """
        #!/bin/sh
        exec python3 - "$@" <<'PY'
        import base64
        import hashlib
        import json
        import socket
        import sys
        import signal

        GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
        CONFIG_PATH = r"#(configFileURL.path)"
        AGENTS = [
            {
                "id": "agent-alpha",
                "name": "Alpha Agent",
                "workspace": r"#(alphaWorkspaceURL.path)",
                "agentDir": r"#(alphaAgentDirectory.path)"
            },
            {
                "id": "agent-beta",
                "name": "Beta Agent",
                "workspace": r"#(betaWorkspaceURL.path)",
                "agentDir": r"#(betaAgentDirectory.path)"
            }
        ]

        port = 18789
        args = sys.argv[1:]
        index = 0
        while index < len(args):
            current = args[index]
            if current == "--port" and index + 1 < len(args):
                port = int(args[index + 1])
                index += 2
                continue
            index += 1

        def recv_exact(connection, length):
            data = b""
            while len(data) < length:
                chunk = connection.recv(length - len(data))
                if not chunk:
                    raise ConnectionError("socket closed")
                data += chunk
            return data

        def receive_frame(connection, buffer):
            while len(buffer) < 2:
                chunk = connection.recv(4096)
                if not chunk:
                    raise ConnectionError("socket closed")
                buffer += chunk

            first_byte = buffer[0]
            second_byte = buffer[1]
            opcode = first_byte & 0x0F
            masked = (second_byte & 0x80) != 0
            payload_length = second_byte & 0x7F
            offset = 2

            if payload_length == 126:
                while len(buffer) < offset + 2:
                    chunk = connection.recv(4096)
                    if not chunk:
                        raise ConnectionError("socket closed")
                    buffer += chunk
                payload_length = int.from_bytes(buffer[offset:offset + 2], "big")
                offset += 2
            elif payload_length == 127:
                while len(buffer) < offset + 8:
                    chunk = connection.recv(4096)
                    if not chunk:
                        raise ConnectionError("socket closed")
                    buffer += chunk
                payload_length = int.from_bytes(buffer[offset:offset + 8], "big")
                offset += 8

            mask_length = 4 if masked else 0
            required_length = offset + mask_length + payload_length
            while len(buffer) < required_length:
                chunk = connection.recv(4096)
                if not chunk:
                    raise ConnectionError("socket closed")
                buffer += chunk

            payload = buffer[offset + mask_length:required_length]
            if masked:
                mask = buffer[offset:offset + 4]
                payload = bytes(value ^ mask[index % 4] for index, value in enumerate(payload))

            return opcode, payload, buffer[required_length:]

        def send_frame(connection, opcode, payload=b""):
            first_byte = 0x80 | (opcode & 0x0F)
            payload_length = len(payload)

            if payload_length < 126:
                header = bytes([first_byte, payload_length])
            elif payload_length <= 0xFFFF:
                header = bytes([first_byte, 126]) + payload_length.to_bytes(2, "big")
            else:
                header = bytes([first_byte, 127]) + payload_length.to_bytes(8, "big")

            connection.sendall(header + payload)

        def send_json(connection, payload):
            send_frame(
                connection,
                0x1,
                json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
            )

        def serve_gateway(selected_port):
            server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            server.bind(("127.0.0.1", selected_port))
            server.listen(5)

            def shutdown(*_args):
                try:
                    server.close()
                finally:
                    sys.exit(0)

            signal.signal(signal.SIGTERM, shutdown)
            signal.signal(signal.SIGINT, shutdown)

            while True:
                connection, _ = server.accept()
                with connection:
                    try:
                        header_buffer = b""
                        while b"\\r\\n\\r\\n" not in header_buffer:
                            chunk = connection.recv(4096)
                            if not chunk:
                                raise ConnectionError("socket closed during handshake")
                            header_buffer += chunk

                        header_block, _, frame_buffer = header_buffer.partition(b"\\r\\n\\r\\n")
                        header_lines = header_block.decode("utf-8", "ignore").split("\\r\\n")
                        headers = {}
                        for line in header_lines[1:]:
                            if ":" not in line:
                                continue
                            key, value = line.split(":", 1)
                            headers[key.strip().lower()] = value.strip()

                        websocket_key = headers.get("sec-websocket-key", "")
                        websocket_accept = base64.b64encode(
                            hashlib.sha1((websocket_key + GUID).encode("utf-8")).digest()
                        ).decode("utf-8")
                        response = (
                            "HTTP/1.1 101 Switching Protocols\\r\\n"
                            "Upgrade: websocket\\r\\n"
                            "Connection: Upgrade\\r\\n"
                            f"Sec-WebSocket-Accept: {websocket_accept}\\r\\n"
                            "\\r\\n"
                        )
                        connection.sendall(response.encode("utf-8"))

                        send_json(connection, {
                            "type": "event",
                            "event": "connect.challenge",
                            "payload": {"nonce": "test-nonce"}
                        })

                        while True:
                            opcode, payload, frame_buffer = receive_frame(connection, frame_buffer)
                            if opcode == 0x8:
                                send_frame(connection, 0x8, payload)
                                break
                            if opcode == 0x9:
                                send_frame(connection, 0xA, payload)
                                continue
                            if opcode != 0x1:
                                continue

                            request = json.loads(payload.decode("utf-8"))
                            request_id = request.get("id", "")
                            method = request.get("method")

                            if method == "connect":
                                send_json(connection, {
                                    "type": "res",
                                    "id": request_id,
                                    "ok": True,
                                    "payload": {
                                        "policy": {"tickIntervalMs": 30000}
                                    }
                                })
                            elif method == "health":
                                send_json(connection, {
                                    "type": "res",
                                    "id": request_id,
                                    "ok": True,
                                    "payload": {"status": "ok"}
                                })
                            elif method == "agents.list":
                                send_json(connection, {
                                    "type": "res",
                                    "id": request_id,
                                    "ok": True,
                                    "payload": {"agents": AGENTS}
                                })
                            else:
                                send_json(connection, {
                                    "type": "res",
                                    "id": request_id,
                                    "ok": False,
                                    "error": {
                                        "message": f"Unsupported method: {method}"
                                    }
                                })
                    except ConnectionError:
                        continue

        if args[:2] == ["agents", "list"]:
            if "--json" in args:
                print(json.dumps(AGENTS, ensure_ascii=False))
            else:
                for agent in AGENTS:
                    print(f"- {agent['name']} ({agent['id']})")
            sys.exit(0)

        if args[:2] == ["config", "file"]:
            print(CONFIG_PATH)
            sys.exit(0)

        if args[:1] == ["gateway"]:
            serve_gateway(port)
            sys.exit(0)

        print("Unsupported arguments", file=sys.stderr)
        sys.exit(1)
        PY
        """.write(to: binaryURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binaryURL.path)
    }

    private func makeProjectAgent(name: String, runtimeIdentifier: String) -> Agent {
        var agent = Agent(name: name)
        agent.soulMD = "# 新智能体\n这是我的配置..."
        agent.openClawDefinition.agentIdentifier = runtimeIdentifier
        agent.openClawDefinition.soulSourcePath = nil
        agent.openClawDefinition.memoryBackupPath = nil
        return agent
    }

    private func makeWorkflowBoundProject(
        named projectName: String,
        agentName: String,
        runtimeIdentifier: String
    ) -> (project: MAProject, workflow: Workflow, node: WorkflowNode, agent: Agent) {
        let agent = makeProjectAgent(name: agentName, runtimeIdentifier: runtimeIdentifier)
        var workflow = Workflow(name: "Main Workflow")
        var node = WorkflowNode(type: .agent)
        node.agentID = agent.id
        node.title = agent.name
        workflow.nodes = [node]

        var project = MAProject(name: projectName)
        project.agents = [agent]
        project.workflows = [workflow]
        return (project, workflow, node, agent)
    }

    private func managedRuntimeAgentList(from configFileURL: URL) throws -> [[String: Any]] {
        let configData = try Data(contentsOf: configFileURL)
        let configObject = try XCTUnwrap(JSONSerialization.jsonObject(with: configData) as? [String: Any])
        let agentsObject = try XCTUnwrap(configObject["agents"] as? [String: Any])
        return try XCTUnwrap(agentsObject["list"] as? [[String: Any]])
    }

    private func makeAvailableTCPPort() throws -> Int {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(descriptor, 0, "Unable to create TCP socket for test port allocation.")
        defer { close(descriptor) }

        var reuseAddress: Int32 = 1
        XCTAssertEqual(
            setsockopt(
                descriptor,
                SOL_SOCKET,
                SO_REUSEADDR,
                &reuseAddress,
                socklen_t(MemoryLayout<Int32>.size)
            ),
            0
        )

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(0).bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { reboundPointer in
                Darwin.bind(descriptor, reboundPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        XCTAssertEqual(bindResult, 0, "Unable to bind test socket for port allocation.")

        var resolvedAddress = address
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &resolvedAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { reboundPointer in
                getsockname(descriptor, reboundPointer, &length)
            }
        }
        XCTAssertEqual(nameResult, 0, "Unable to resolve allocated test port.")

        return Int(UInt16(bigEndian: resolvedAddress.sin_port))
    }

    func testManagerStartAndStopManagedRuntimeUpdatesApplicationState() throws {
        let tempRoot = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let managedRuntimeRoot = tempRoot.appendingPathComponent("runtime", isDirectory: true)
        let supervisorRoot = tempRoot.appendingPathComponent("supervisor", isDirectory: true)
        let binaryURL = managedRuntimeRoot.appendingPathComponent("bin/openclaw", isDirectory: false)
        try makeManagedRuntimeGatewayBinary(at: binaryURL)

        let host = OpenClawHost(
            fileManager: .default,
            bundleResourceURL: nil,
            managedRuntimeRootURL: managedRuntimeRoot,
            homeDirectory: tempRoot
        )
        let supervisor = OpenClawManagedRuntimeSupervisor(
            fileManager: .default,
            host: host,
            managedRuntimeRootURL: managedRuntimeRoot,
            supervisorRootURL: supervisorRoot
        )
        let manager = OpenClawManager(
            notificationCenter: NotificationCenter(),
            fileManager: .default,
            host: host,
            managedRuntimeSupervisor: supervisor
        )

        var config = OpenClawConfig.default
        config.deploymentKind = .local
        config.runtimeOwnership = .appManaged
        config.host = "127.0.0.1"
        config.port = try makeAvailableTCPPort()
        config.timeout = 5
        config.cliQuietMode = true
        config.cliLogLevel = .warning
        config.localBinaryPath = ""
        manager.config = config

        let startExpectation = expectation(description: "managed runtime started")
        manager.startManagedRuntime { success, message in
            XCTAssertTrue(success, message)
            startExpectation.fulfill()
        }
        wait(for: [startExpectation], timeout: 10)

        XCTAssertEqual(manager.managedRuntimeStatus.state, .running)
        XCTAssertEqual(manager.managedRuntimeStatus.port, config.port)
        XCTAssertEqual(manager.managedRuntimeStatus.binaryPath, binaryURL.path)
        XCTAssertNotNil(manager.managedRuntimeStatus.processID)

        let stopExpectation = expectation(description: "managed runtime stopped")
        manager.stopManagedRuntime { success, message in
            XCTAssertTrue(success, message)
            stopExpectation.fulfill()
        }
        wait(for: [stopExpectation], timeout: 10)

        XCTAssertEqual(manager.managedRuntimeStatus.state, .idle)
        XCTAssertNil(manager.managedRuntimeStatus.processID)
        XCTAssertFalse(manager.isConnected)
        XCTAssertTrue(manager.activeAgents.isEmpty)
        if case .disconnected = manager.status {
        } else {
            XCTFail("Expected manager status to be disconnected after stopping managed runtime.")
        }
    }

    func testManagerRestartManagedRuntimeIncrementsRestartCount() throws {
        let tempRoot = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let managedRuntimeRoot = tempRoot.appendingPathComponent("runtime", isDirectory: true)
        let supervisorRoot = tempRoot.appendingPathComponent("supervisor", isDirectory: true)
        let binaryURL = managedRuntimeRoot.appendingPathComponent("bin/openclaw", isDirectory: false)
        try makeManagedRuntimeGatewayBinary(at: binaryURL)

        let host = OpenClawHost(
            fileManager: .default,
            bundleResourceURL: nil,
            managedRuntimeRootURL: managedRuntimeRoot,
            homeDirectory: tempRoot
        )
        let supervisor = OpenClawManagedRuntimeSupervisor(
            fileManager: .default,
            host: host,
            managedRuntimeRootURL: managedRuntimeRoot,
            supervisorRootURL: supervisorRoot
        )
        let manager = OpenClawManager(
            notificationCenter: NotificationCenter(),
            fileManager: .default,
            host: host,
            managedRuntimeSupervisor: supervisor
        )

        var config = OpenClawConfig.default
        config.deploymentKind = .local
        config.runtimeOwnership = .appManaged
        config.host = "127.0.0.1"
        config.port = try makeAvailableTCPPort()
        config.timeout = 5
        config.cliQuietMode = true
        config.cliLogLevel = .warning
        config.localBinaryPath = ""
        manager.config = config

        let startExpectation = expectation(description: "managed runtime started")
        manager.startManagedRuntime { success, message in
            XCTAssertTrue(success, message)
            startExpectation.fulfill()
        }
        wait(for: [startExpectation], timeout: 10)

        let restartExpectation = expectation(description: "managed runtime restarted")
        manager.restartManagedRuntime { success, message in
            XCTAssertTrue(success, message)
            restartExpectation.fulfill()
        }
        wait(for: [restartExpectation], timeout: 10)

        XCTAssertEqual(manager.managedRuntimeStatus.state, .running)
        XCTAssertEqual(manager.managedRuntimeStatus.restartCount, 1)
        XCTAssertEqual(manager.managedRuntimeStatus.port, config.port)

        let stopExpectation = expectation(description: "managed runtime stopped")
        manager.stopManagedRuntime { success, message in
            XCTAssertTrue(success, message)
            stopExpectation.fulfill()
        }
        wait(for: [stopExpectation], timeout: 10)
    }

    func testManagerConnectStartsManagedRuntimeAndCompletesGatewayProbe() throws {
        let tempRoot = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let managedRuntimeRoot = tempRoot.appendingPathComponent("runtime", isDirectory: true)
        let supervisorRoot = tempRoot.appendingPathComponent("supervisor", isDirectory: true)
        let binaryURL = managedRuntimeRoot.appendingPathComponent("bin/openclaw", isDirectory: false)
        try makeManagedRuntimeGatewayBinary(at: binaryURL)

        let host = OpenClawHost(
            fileManager: .default,
            bundleResourceURL: nil,
            managedRuntimeRootURL: managedRuntimeRoot,
            homeDirectory: tempRoot
        )
        let supervisor = OpenClawManagedRuntimeSupervisor(
            fileManager: .default,
            host: host,
            managedRuntimeRootURL: managedRuntimeRoot,
            supervisorRootURL: supervisorRoot
        )
        let manager = OpenClawManager(
            notificationCenter: NotificationCenter(),
            fileManager: .default,
            host: host,
            managedRuntimeSupervisor: supervisor
        )

        var config = OpenClawConfig.default
        config.deploymentKind = .local
        config.runtimeOwnership = .appManaged
        config.host = "127.0.0.1"
        config.port = try makeAvailableTCPPort()
        config.timeout = 5
        config.cliQuietMode = true
        config.cliLogLevel = .warning
        config.localBinaryPath = ""
        manager.config = config

        let connectExpectation = expectation(description: "managed runtime connected")
        manager.connect { success, message in
            XCTAssertTrue(success, message)
            connectExpectation.fulfill()
        }
        wait(for: [connectExpectation], timeout: 10)

        XCTAssertTrue(manager.isConnected)
        XCTAssertEqual(manager.managedRuntimeStatus.state, .running)
        XCTAssertEqual(manager.managedRuntimeStatus.port, config.port)
        XCTAssertNotNil(manager.managedRuntimeStatus.lastHeartbeatAt)
        XCTAssertEqual(manager.agents, ["Alpha Agent", "Beta Agent"])
        XCTAssertEqual(manager.discoveryResults.map(\.name), ["Alpha Agent", "Beta Agent"])
        XCTAssertEqual(manager.connectionState.phase, .ready)
        XCTAssertTrue(manager.connectionState.capabilities.cliAvailable)
        XCTAssertTrue(manager.connectionState.capabilities.gatewayReachable)
        XCTAssertTrue(manager.connectionState.capabilities.gatewayAuthenticated)
        XCTAssertTrue(manager.canAttachProject)
        XCTAssertEqual(manager.lastProbeReport?.availableAgents, ["Alpha Agent", "Beta Agent"])
        XCTAssertTrue(manager.lastProbeReport?.success == true)

        let stopExpectation = expectation(description: "managed runtime stopped after connect")
        manager.stopManagedRuntime { success, message in
            XCTAssertTrue(success, message)
            stopExpectation.fulfill()
        }
        wait(for: [stopExpectation], timeout: 10)
    }

    func testManagerAttachProjectSessionAfterManagedRuntimeConnectionUpdatesSessionState() throws {
        let tempRoot = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let managedRuntimeRoot = tempRoot.appendingPathComponent("runtime", isDirectory: true)
        let supervisorRoot = tempRoot.appendingPathComponent("supervisor", isDirectory: true)
        let binaryURL = managedRuntimeRoot.appendingPathComponent("bin/openclaw", isDirectory: false)
        try makeManagedRuntimeGatewayBinary(at: binaryURL)

        let host = OpenClawHost(
            fileManager: .default,
            bundleResourceURL: nil,
            managedRuntimeRootURL: managedRuntimeRoot,
            homeDirectory: tempRoot
        )
        let supervisor = OpenClawManagedRuntimeSupervisor(
            fileManager: .default,
            host: host,
            managedRuntimeRootURL: managedRuntimeRoot,
            supervisorRootURL: supervisorRoot
        )
        let manager = OpenClawManager(
            notificationCenter: NotificationCenter(),
            fileManager: .default,
            host: host,
            managedRuntimeSupervisor: supervisor
        )

        var config = OpenClawConfig.default
        config.deploymentKind = .local
        config.runtimeOwnership = .appManaged
        config.host = "127.0.0.1"
        config.port = try makeAvailableTCPPort()
        config.timeout = 5
        config.cliQuietMode = true
        config.cliLogLevel = .warning
        config.localBinaryPath = ""
        manager.config = config

        let project = MAProject(name: "Managed Runtime Attach")
        defer {
            try? FileManager.default.removeItem(at: ProjectManager.shared.openClawProjectRoot(for: project.id))
        }

        let connectExpectation = expectation(description: "managed runtime connected before attach")
        manager.connect { success, message in
            XCTAssertTrue(success, message)
            connectExpectation.fulfill()
        }
        wait(for: [connectExpectation], timeout: 10)

        let agent = makeProjectAgent(name: "任务中心-任务领域-1", runtimeIdentifier: "agent-alpha")
        var mutableProject = project
        mutableProject.agents = [agent]

        var attachResult: (success: Bool, message: String)?
        manager.attachProjectSession(for: mutableProject) { success, message in
            attachResult = (success, message)
        }
        let attachDeadline = Date().addingTimeInterval(10)
        while attachResult == nil && Date() < attachDeadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        guard let attachResult else {
            XCTFail("managed runtime attached project session did not complete in time")
            return
        }
        XCTAssertTrue(attachResult.success, attachResult.message)
        drainMainQueue()

        XCTAssertEqual(manager.projectAttachment.state, .attached)
        XCTAssertEqual(manager.projectAttachment.projectID, mutableProject.id)
        XCTAssertTrue(manager.hasAttachedProjectSession)
        XCTAssertEqual(manager.sessionLifecycle.stage, .prepared)

        let backupURL = ProjectManager.shared.openClawBackupDirectory(for: mutableProject.id)
        let backupSoulURL = backupURL.appendingPathComponent("agents/agent-alpha/SOUL.md", isDirectory: false)
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupSoulURL.path))
        XCTAssertEqual(try String(contentsOf: backupSoulURL, encoding: .utf8), "# runtime alpha baseline\n")

        var reconciledProject = mutableProject
        let report = manager.applyPendingSoulReconcileResult(to: &reconciledProject)
        XCTAssertEqual(report?.overwrittenCount, 1)
        XCTAssertEqual(reconciledProject.agents.first?.soulMD, "# runtime alpha baseline\n")

        let stopExpectation = expectation(description: "managed runtime stopped after attach")
        manager.stopManagedRuntime { success, message in
            XCTAssertTrue(success, message)
            stopExpectation.fulfill()
        }
        wait(for: [stopExpectation], timeout: 10)
    }

    func testManagerManagedRuntimeSyncWritesSessionChangesAndRestoresBackupOnDisconnect() throws {
        let tempRoot = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let managedRuntimeRoot = tempRoot.appendingPathComponent("runtime", isDirectory: true)
        let supervisorRoot = tempRoot.appendingPathComponent("supervisor", isDirectory: true)
        let binaryURL = managedRuntimeRoot.appendingPathComponent("bin/openclaw", isDirectory: false)
        try makeManagedRuntimeGatewayBinary(at: binaryURL)

        let host = OpenClawHost(
            fileManager: .default,
            bundleResourceURL: nil,
            managedRuntimeRootURL: managedRuntimeRoot,
            homeDirectory: tempRoot
        )
        let supervisor = OpenClawManagedRuntimeSupervisor(
            fileManager: .default,
            host: host,
            managedRuntimeRootURL: managedRuntimeRoot,
            supervisorRootURL: supervisorRoot
        )
        let manager = OpenClawManager(
            notificationCenter: NotificationCenter(),
            fileManager: .default,
            host: host,
            managedRuntimeSupervisor: supervisor
        )

        var config = OpenClawConfig.default
        config.deploymentKind = .local
        config.runtimeOwnership = .appManaged
        config.host = "127.0.0.1"
        config.port = try makeAvailableTCPPort()
        config.timeout = 5
        config.cliQuietMode = true
        config.cliLogLevel = .warning
        config.localBinaryPath = ""
        manager.config = config

        let setup = makeWorkflowBoundProject(
            named: "Managed Runtime Sync",
            agentName: "任务中心-任务领域-1",
            runtimeIdentifier: "agent-alpha"
        )
        let project = setup.project
        let workflow = setup.workflow
        let node = setup.node
        defer {
            ProjectManager.shared.deleteProject(
                at: tempRoot.appendingPathComponent("ManagedRuntimeSync.maoproj", isDirectory: false),
                projectID: project.id
            )
        }

        let managedWorkspaceURL = ProjectFileSystem.shared.nodeOpenClawWorkspaceDirectory(
            for: node.id,
            workflowID: workflow.id,
            projectID: project.id,
            under: ProjectManager.shared.appSupportRootDirectory
        )
        try FileManager.default.createDirectory(at: managedWorkspaceURL, withIntermediateDirectories: true)
        try "# managed alpha soul\n".write(
            to: managedWorkspaceURL.appendingPathComponent("SOUL.md", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try "# managed agents notes\n".write(
            to: managedWorkspaceURL.appendingPathComponent("AGENTS.md", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        let connectExpectation = expectation(description: "managed runtime connected before sync")
        manager.connect { success, message in
            XCTAssertTrue(success, message)
            connectExpectation.fulfill()
        }
        wait(for: [connectExpectation], timeout: 10)

        var attachedResult: (Bool, String)?
        manager.attachProjectSession(for: project) { success, message in
            attachedResult = (success, message)
        }
        let attachDeadline = Date().addingTimeInterval(10)
        while attachedResult == nil && Date() < attachDeadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        let attachResult = try XCTUnwrap(attachedResult)
        XCTAssertTrue(attachResult.0, attachResult.1)
        drainMainQueue()

        XCTAssertEqual(manager.sessionLifecycle.stage, .pendingSync)
        XCTAssertTrue(manager.sessionLifecycle.hasPendingMirrorChanges)

        let syncExpectation = expectation(description: "managed runtime synced")
        manager.syncProjectAgentsToActiveSession(project, workflowID: workflow.id) { result in
            XCTAssertEqual(result.deploymentStatus, .appliedToRuntime)
            XCTAssertNil(result.errorMessage)
            syncExpectation.fulfill()
        }
        wait(for: [syncExpectation], timeout: 10)
        drainMainQueue()

        let runtimeSoulURL = managedRuntimeRoot.appendingPathComponent("agents/agent-alpha/SOUL.md", isDirectory: false)
        XCTAssertEqual(try String(contentsOf: runtimeSoulURL, encoding: .utf8), "# managed alpha soul\n")

        let runtimeWorkspaceURL = managedRuntimeRoot.appendingPathComponent("agents/agent-alpha/workspace", isDirectory: true)
        let runtimeAgentsDocURL = runtimeWorkspaceURL.appendingPathComponent("AGENTS.md", isDirectory: false)
        XCTAssertTrue(FileManager.default.fileExists(atPath: runtimeAgentsDocURL.path))
        XCTAssertEqual(try String(contentsOf: runtimeAgentsDocURL, encoding: .utf8), "# managed agents notes\n")

        let syncedAgentList = try managedRuntimeAgentList(from: managedRuntimeRoot.appendingPathComponent("openclaw.json", isDirectory: false))
        let syncedAgent = try XCTUnwrap(syncedAgentList.first { ($0["id"] as? String) == "agent-alpha" })
        XCTAssertEqual(syncedAgent["workspace"] as? String, runtimeWorkspaceURL.path)
        XCTAssertEqual(syncedAgent["agentDir"] as? String, managedRuntimeRoot.appendingPathComponent("agents/agent-alpha", isDirectory: true).path)

        XCTAssertEqual(manager.sessionLifecycle.stage, .synced)
        XCTAssertFalse(manager.sessionLifecycle.hasPendingMirrorChanges)

        manager.disconnect()
        drainMainQueue()

        XCTAssertEqual(try String(contentsOf: runtimeSoulURL, encoding: .utf8), "# runtime alpha baseline\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: runtimeAgentsDocURL.path))

        let restoredAgentList = try managedRuntimeAgentList(from: managedRuntimeRoot.appendingPathComponent("openclaw.json", isDirectory: false))
        let restoredAgent = try XCTUnwrap(restoredAgentList.first { ($0["id"] as? String) == "agent-alpha" })
        XCTAssertEqual(restoredAgent["workspace"] as? String, managedRuntimeRoot.appendingPathComponent("workspace/agent-alpha", isDirectory: true).path)
        XCTAssertEqual(manager.sessionLifecycle.stage, .prepared)

        let stopExpectation = expectation(description: "managed runtime stopped after sync")
        manager.stopManagedRuntime { success, message in
            XCTAssertTrue(success, message)
            stopExpectation.fulfill()
        }
        wait(for: [stopExpectation], timeout: 10)
    }
}
