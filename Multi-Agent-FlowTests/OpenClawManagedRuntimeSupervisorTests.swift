import XCTest
import Darwin
@testable import Multi_Agent_Flow

final class OpenClawManagedRuntimeSupervisorTests: XCTestCase {
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

    private func occupyTCPPort(_ port: Int) throws -> Int32 {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(descriptor, 0, "Unable to create TCP socket for port occupation.")

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
        address.sin_port = in_port_t(UInt16(port).bigEndian)
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { reboundPointer in
                Darwin.bind(descriptor, reboundPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        XCTAssertEqual(bindResult, 0, "Unable to occupy requested TCP port.")
        XCTAssertEqual(listen(descriptor, 1), 0, "Unable to listen on occupied TCP port.")
        return descriptor
    }

    private func waitForProcessExit(pid: Int32, timeout: TimeInterval = 5) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !(kill(pid, 0) == 0 || errno == EPERM) {
                return
            }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        XCTFail("Managed runtime test process \(pid) did not exit in time.")
    }

    private func makeCrashOnceThenRecoverGatewayBinary(at binaryURL: URL, markerURL: URL) throws {
        try FileManager.default.createDirectory(
            at: binaryURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        try """
        #!/bin/sh
        exec python3 - "$@" <<'PY'
        import os
        import signal
        import socket
        import sys
        import threading
        import time

        marker_path = r"\(markerURL.path)"
        port = 18789
        args = sys.argv[1:]
        index = 0
        while index < len(args):
            if args[index] == "--port" and index + 1 < len(args):
                port = int(args[index + 1])
                index += 2
                continue
            index += 1

        crash_once = not os.path.exists(marker_path)
        if crash_once:
            with open(marker_path, "w", encoding="utf-8") as marker_file:
                marker_file.write("crashed")

        server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        server.bind(("127.0.0.1", port))
        server.listen(5)

        def shutdown(*_args):
            try:
                server.close()
            finally:
                sys.exit(0)

        signal.signal(signal.SIGTERM, shutdown)
        signal.signal(signal.SIGINT, shutdown)

        def accept_loop():
            while True:
                try:
                    connection, _ = server.accept()
                except OSError:
                    break
                try:
                    connection.close()
                except OSError:
                    pass

        threading.Thread(target=accept_loop, daemon=True).start()

        if crash_once:
            time.sleep(0.35)
            os._exit(1)

        while True:
            time.sleep(0.25)
        PY
        """.write(to: binaryURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binaryURL.path)
    }

    private func makeSteadyGatewayBinary(at binaryURL: URL) throws {
        try FileManager.default.createDirectory(
            at: binaryURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        try """
        #!/bin/sh
        exec python3 - "$@" <<'PY'
        import signal
        import socket
        import sys
        import threading
        import time

        port = 18789
        args = sys.argv[1:]
        index = 0
        while index < len(args):
            if args[index] == "--port" and index + 1 < len(args):
                port = int(args[index + 1])
                index += 2
                continue
            index += 1

        server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        server.bind(("127.0.0.1", port))
        server.listen(5)

        def shutdown(*_args):
            try:
                server.close()
            finally:
                sys.exit(0)

        signal.signal(signal.SIGTERM, shutdown)
        signal.signal(signal.SIGINT, shutdown)

        def accept_loop():
            while True:
                try:
                    connection, _ = server.accept()
                except OSError:
                    break
                try:
                    connection.close()
                except OSError:
                    pass

        threading.Thread(target=accept_loop, daemon=True).start()

        while True:
            time.sleep(0.25)
        PY
        """.write(to: binaryURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binaryURL.path)
    }

    private func makeFailingGatewayBinary(at binaryURL: URL) throws {
        try FileManager.default.createDirectory(
            at: binaryURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        try """
        #!/bin/sh
        echo "Config invalid" >&2
        echo "plugins.allow: plugin not found: minimax-portal-auth" >&2
        exit 1
        """.write(to: binaryURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binaryURL.path)
    }

    func testBuildLaunchCommandPlanUsesManagedRuntimeBinaryForAppManagedConfig() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenClawManagedRuntimeSupervisorPlanTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let managedRuntimeRoot = tempRoot.appendingPathComponent("runtime", isDirectory: true)
        let binaryURL = managedRuntimeRoot.appendingPathComponent("bin/openclaw", isDirectory: false)
        try FileManager.default.createDirectory(at: binaryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "#!/bin/sh\nsleep 1\n".write(to: binaryURL, atomically: true, encoding: .utf8)

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
            supervisorRootURL: tempRoot.appendingPathComponent("supervisor", isDirectory: true)
        )

        var config = OpenClawConfig.default
        config.runtimeOwnership = .appManaged
        config.localBinaryPath = "/legacy/openclaw"
        config.cliQuietMode = true
        config.cliLogLevel = .warning

        let plan = try supervisor.buildLaunchCommandPlan(using: config)

        XCTAssertEqual(plan.launchStrategy, .foregroundGateway)
        XCTAssertEqual(plan.executableURL.path, binaryURL.path)
        XCTAssertEqual(plan.arguments, ["gateway", "--port", "18789"])
        XCTAssertEqual(plan.environment["OPENCLAW_CONFIG_PATH"], managedRuntimeRoot.appendingPathComponent("openclaw.json").path)
        XCTAssertEqual(plan.environment["OPENCLAW_STATE_DIR"], tempRoot.appendingPathComponent("state", isDirectory: true).path)
    }

    func testRefreshStatusTreatsLivePersistedPidAsRunning() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenClawManagedRuntimeSupervisorLivePIDTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let managedRuntimeRoot = tempRoot.appendingPathComponent("runtime", isDirectory: true)
        let supervisorRoot = tempRoot.appendingPathComponent("supervisor", isDirectory: true)
        try FileManager.default.createDirectory(at: supervisorRoot, withIntermediateDirectories: true)

        try makePersistedProcessState(
            at: supervisorRoot.appendingPathComponent("process-state.json", isDirectory: false),
            pid: getpid(),
            port: 18789,
            executablePath: "/managed/bin/openclaw",
            logPath: "/managed/logs/gateway.log"
        )

        let supervisor = OpenClawManagedRuntimeSupervisor(
            fileManager: .default,
            host: OpenClawHost(fileManager: .default, bundleResourceURL: nil, managedRuntimeRootURL: managedRuntimeRoot, homeDirectory: tempRoot),
            managedRuntimeRootURL: managedRuntimeRoot,
            supervisorRootURL: supervisorRoot
        )

        let snapshot = supervisor.refreshStatus(using: .default)

        XCTAssertEqual(snapshot.state, .running)
        XCTAssertEqual(snapshot.processID, getpid())
        XCTAssertEqual(snapshot.port, 18789)
        XCTAssertEqual(snapshot.binaryPath, "/managed/bin/openclaw")
        XCTAssertEqual(snapshot.logPath, "/managed/logs/gateway.log")
        XCTAssertEqual(snapshot.launchStrategy, .foregroundGateway)
    }

    func testRefreshStatusRemovesStalePersistedPidFile() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenClawManagedRuntimeSupervisorStalePIDTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let managedRuntimeRoot = tempRoot.appendingPathComponent("runtime", isDirectory: true)
        let supervisorRoot = tempRoot.appendingPathComponent("supervisor", isDirectory: true)
        let processStateURL = supervisorRoot.appendingPathComponent("process-state.json", isDirectory: false)
        try FileManager.default.createDirectory(at: supervisorRoot, withIntermediateDirectories: true)

        try makePersistedProcessState(
            at: processStateURL,
            pid: Int32.max,
            port: 18789,
            executablePath: "/managed/bin/openclaw",
            logPath: "/managed/logs/gateway.log"
        )

        let supervisor = OpenClawManagedRuntimeSupervisor(
            fileManager: .default,
            host: OpenClawHost(fileManager: .default, bundleResourceURL: nil, managedRuntimeRootURL: managedRuntimeRoot, homeDirectory: tempRoot),
            managedRuntimeRootURL: managedRuntimeRoot,
            supervisorRootURL: supervisorRoot
        )

        let snapshot = supervisor.refreshStatus(using: .default)

        XCTAssertEqual(snapshot.state, .idle)
        XCTAssertNil(snapshot.processID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: processStateURL.path))
    }

    func testUnexpectedExitSchedulesAutomaticRecoveryWhenEnabled() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenClawManagedRuntimeSupervisorRecoveryTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let managedRuntimeRoot = tempRoot.appendingPathComponent("runtime", isDirectory: true)
        let supervisorRoot = tempRoot.appendingPathComponent("supervisor", isDirectory: true)
        let binaryURL = managedRuntimeRoot.appendingPathComponent("bin/openclaw", isDirectory: false)
        let markerURL = tempRoot.appendingPathComponent("crash-once.marker", isDirectory: false)
        try makeCrashOnceThenRecoverGatewayBinary(at: binaryURL, markerURL: markerURL)

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
            supervisorRootURL: supervisorRoot,
            automaticRecoveryDelaySeconds: 0.2,
            automaticRecoveryStableUptimeSeconds: 1,
            automaticRecoveryMaxConsecutiveAttempts: 2
        )

        var config = OpenClawConfig.default
        config.runtimeOwnership = .appManaged
        config.managedRuntimeAutoRestartOnCrash = true
        config.port = 18793
        config.timeout = 5

        let started = try supervisor.start(using: config)
        let originalPID = try XCTUnwrap(started.processID)

        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            let snapshot = supervisor.currentStatusSnapshot()
            if snapshot.state == .running,
               snapshot.restartCount == 1,
               snapshot.manualRestartCount == 0,
               snapshot.automaticRecoveryCount == 1,
               snapshot.consecutiveCrashCount == 1,
               snapshot.lastUnexpectedExitAt != nil,
               snapshot.lastRecoveryAttemptAt != nil,
               snapshot.lastRecoverySucceededAt != nil,
               let recoveredPID = snapshot.processID,
               recoveredPID != originalPID {
                _ = try supervisor.stop(using: config)
                return
            }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }

        XCTFail("Supervisor did not automatically recover the managed runtime after an unexpected exit.")
    }

    func testUnexpectedExitStaysFailedWhenAutomaticRecoveryDisabled() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenClawManagedRuntimeSupervisorManualRecoveryTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let managedRuntimeRoot = tempRoot.appendingPathComponent("runtime", isDirectory: true)
        let supervisorRoot = tempRoot.appendingPathComponent("supervisor", isDirectory: true)
        let binaryURL = managedRuntimeRoot.appendingPathComponent("bin/openclaw", isDirectory: false)
        let markerURL = tempRoot.appendingPathComponent("crash-once-disabled.marker", isDirectory: false)
        try makeCrashOnceThenRecoverGatewayBinary(at: binaryURL, markerURL: markerURL)

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
            supervisorRootURL: supervisorRoot,
            automaticRecoveryDelaySeconds: 0.2,
            automaticRecoveryStableUptimeSeconds: 1,
            automaticRecoveryMaxConsecutiveAttempts: 2
        )

        var config = OpenClawConfig.default
        config.runtimeOwnership = .appManaged
        config.managedRuntimeAutoRestartOnCrash = false
        config.port = 18794
        config.timeout = 5

        let started = try supervisor.start(using: config)
        XCTAssertNotNil(started.processID)

        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            let snapshot = supervisor.currentStatusSnapshot()
            if snapshot.state == .failed {
                XCTAssertNil(snapshot.processID)
                XCTAssertEqual(snapshot.restartCount, 0)
                XCTAssertEqual(snapshot.manualRestartCount, 0)
                XCTAssertEqual(snapshot.automaticRecoveryCount, 0)
                XCTAssertEqual(snapshot.consecutiveCrashCount, 1)
                XCTAssertNil(snapshot.lastRecoverySucceededAt)
                XCTAssertNotNil(snapshot.lastUnexpectedExitAt)
                XCTAssertTrue(snapshot.lastMessage?.contains("异常退出") == true)
                return
            }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }

        XCTFail("Supervisor should remain in failed state when automatic recovery is disabled.")
    }

    func testStartReassignsManagedRuntimePortWhenPreferredPortIsOccupied() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenClawManagedRuntimeSupervisorPortResolutionTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let managedRuntimeRoot = tempRoot.appendingPathComponent("runtime", isDirectory: true)
        let supervisorRoot = tempRoot.appendingPathComponent("supervisor", isDirectory: true)
        let binaryURL = managedRuntimeRoot.appendingPathComponent("bin/openclaw", isDirectory: false)
        try makeSteadyGatewayBinary(at: binaryURL)

        let preferredPort = try makeAvailableTCPPort()
        let occupiedSocket = try occupyTCPPort(preferredPort)
        defer { close(occupiedSocket) }

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

        var config = OpenClawConfig.default
        config.runtimeOwnership = .appManaged
        config.host = "127.0.0.1"
        config.port = preferredPort
        config.timeout = 5

        let snapshot = try supervisor.start(using: config)
        let runtimePID = try XCTUnwrap(snapshot.processID)
        defer {
            kill(runtimePID, SIGKILL)
            waitForProcessExit(pid: runtimePID)
        }

        let actualPort = try XCTUnwrap(snapshot.port)
        XCTAssertEqual(snapshot.requestedPort, preferredPort)
        XCTAssertNotEqual(actualPort, preferredPort)
        XCTAssertTrue(snapshot.logPath?.contains("gateway-\(actualPort).log") == true)
        XCTAssertTrue(snapshot.lastMessage?.contains("已动态分配端口 \(actualPort)") == true)
        XCTAssertTrue(snapshot.lastMessage?.contains("配置端口 \(preferredPort) 仅作兼容保留") == true)
        XCTAssertTrue(snapshot.lastMessage?.contains("\(actualPort)") == true)
    }

    func testStartSurfacesRecentGatewayLogExcerptWhenLaunchFailsBeforeReadiness() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenClawManagedRuntimeSupervisorFailureTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let managedRuntimeRoot = tempRoot.appendingPathComponent("runtime", isDirectory: true)
        let supervisorRoot = tempRoot.appendingPathComponent("supervisor", isDirectory: true)
        let binaryURL = managedRuntimeRoot.appendingPathComponent("bin/openclaw", isDirectory: false)
        try makeFailingGatewayBinary(at: binaryURL)

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

        var config = OpenClawConfig.default
        config.runtimeOwnership = .appManaged
        config.host = "127.0.0.1"
        config.port = 18795
        config.timeout = 1

        XCTAssertThrowsError(try supervisor.start(using: config)) { error in
            let message = error.localizedDescription
            XCTAssertTrue(message.contains("监听端口 18795 前已退出"))
            XCTAssertTrue(message.contains("Config invalid"))
            XCTAssertTrue(message.contains("minimax-portal-auth"))
        }
    }

    private func makePersistedProcessState(
        at url: URL,
        pid: Int32,
        requestedPort: Int? = nil,
        port: Int,
        executablePath: String,
        logPath: String
    ) throws {
        var payload: [String: Any] = [
            "pid": pid,
            "port": port,
            "executablePath": executablePath,
            "logPath": logPath,
            "launchStrategy": "foregroundGateway",
            "startedAt": Date().timeIntervalSinceReferenceDate
        ]
        if let requestedPort {
            payload["requestedPort"] = requestedPort
        }
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }
}
