import XCTest
import Darwin
@testable import Multi_Agent_Flow

final class OpenClawManagedRuntimeSupervisorTests: XCTestCase {
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

    private func makePersistedProcessState(
        at url: URL,
        pid: Int32,
        port: Int,
        executablePath: String,
        logPath: String
    ) throws {
        let payload: [String: Any] = [
            "pid": pid,
            "port": port,
            "executablePath": executablePath,
            "logPath": logPath,
            "launchStrategy": "foregroundGateway",
            "startedAt": Date().timeIntervalSinceReferenceDate
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }
}
