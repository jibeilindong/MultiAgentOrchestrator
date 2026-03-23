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

    private func makeManagedRuntimeGatewayBinary(at binaryURL: URL) throws {
        try FileManager.default.createDirectory(at: binaryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try """
        #!/bin/sh
        exec python3 - "$@" <<'PY'
        import http.server
        import socketserver
        import sys

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

        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b"ok")

            def log_message(self, fmt, *args):
                pass

        class ReusableTCPServer(socketserver.TCPServer):
            allow_reuse_address = True

        with ReusableTCPServer(("127.0.0.1", port), Handler) as server:
            server.serve_forever()
        PY
        """.write(to: binaryURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binaryURL.path)
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
}
