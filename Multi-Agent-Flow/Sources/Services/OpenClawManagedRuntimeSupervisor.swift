import Foundation
import Darwin

enum OpenClawManagedRuntimeSupervisorState: String, Equatable {
    case unmanaged
    case idle
    case starting
    case running
    case stopping
    case failed
}

enum OpenClawManagedRuntimeLaunchStrategy: String, Codable, Equatable {
    case foregroundGateway
    case daemonCLI
}

struct OpenClawManagedRuntimeSupervisorCommandPlan: Equatable {
    var launchStrategy: OpenClawManagedRuntimeLaunchStrategy
    var executableURL: URL
    var arguments: [String]
}

struct OpenClawManagedRuntimeStatusSnapshot: Equatable {
    var state: OpenClawManagedRuntimeSupervisorState
    var launchStrategy: OpenClawManagedRuntimeLaunchStrategy?
    var runtimeRootPath: String?
    var supervisorRootPath: String?
    var binaryPath: String?
    var logPath: String?
    var processID: Int32?
    var port: Int?
    var lastStartedAt: Date?
    var lastExitAt: Date?
    var lastHeartbeatAt: Date?
    var lastStatusCheckAt: Date?
    var restartCount: Int
    var lastMessage: String?
    var lastError: String?

    nonisolated init(
        state: OpenClawManagedRuntimeSupervisorState = .idle,
        launchStrategy: OpenClawManagedRuntimeLaunchStrategy? = nil,
        runtimeRootPath: String? = nil,
        supervisorRootPath: String? = nil,
        binaryPath: String? = nil,
        logPath: String? = nil,
        processID: Int32? = nil,
        port: Int? = nil,
        lastStartedAt: Date? = nil,
        lastExitAt: Date? = nil,
        lastHeartbeatAt: Date? = nil,
        lastStatusCheckAt: Date? = nil,
        restartCount: Int = 0,
        lastMessage: String? = nil,
        lastError: String? = nil
    ) {
        self.state = state
        self.launchStrategy = launchStrategy
        self.runtimeRootPath = runtimeRootPath
        self.supervisorRootPath = supervisorRootPath
        self.binaryPath = binaryPath
        self.logPath = logPath
        self.processID = processID
        self.port = port
        self.lastStartedAt = lastStartedAt
        self.lastExitAt = lastExitAt
        self.lastHeartbeatAt = lastHeartbeatAt
        self.lastStatusCheckAt = lastStatusCheckAt
        self.restartCount = restartCount
        self.lastMessage = lastMessage
        self.lastError = lastError
    }
}

nonisolated final class OpenClawManagedRuntimeSupervisor {
    private struct PersistedProcessState: Codable {
        var pid: Int32
        var port: Int
        var executablePath: String
        var logPath: String
        var launchStrategy: OpenClawManagedRuntimeLaunchStrategy
        var startedAt: Date
    }

    private struct TrackedProcess {
        var process: Process
        var logHandle: FileHandle
        var pid: Int32
        var port: Int
        var logURL: URL
        var launchStrategy: OpenClawManagedRuntimeLaunchStrategy
    }

    private let fileManager: FileManager
    private let host: OpenClawHost
    private let managedRuntimeRootURL: URL?
    private let supervisorRootURL: URL?
    private let dateProvider: () -> Date
    private let lock = NSLock()

    private var trackedProcess: TrackedProcess?
    private var expectedStoppedPID: Int32?
    private var statusSnapshot: OpenClawManagedRuntimeStatusSnapshot

    nonisolated init(
        fileManager: FileManager = .default,
        host: OpenClawHost? = nil,
        managedRuntimeRootURL: URL? = OpenClawManagedRuntimeInstaller.shared.managedRuntimeRootURL(),
        supervisorRootURL: URL? = nil,
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.fileManager = fileManager
        self.host = host ?? OpenClawHost(
            fileManager: fileManager,
            managedRuntimeRootURL: managedRuntimeRootURL
        )
        self.managedRuntimeRootURL = managedRuntimeRootURL
        self.supervisorRootURL = supervisorRootURL
        self.dateProvider = dateProvider
        let resolvedSupervisorRootURL = supervisorRootURL
            ?? managedRuntimeRootURL?
                .deletingLastPathComponent()
                .appendingPathComponent("supervisor", isDirectory: true)
        self.statusSnapshot = OpenClawManagedRuntimeStatusSnapshot(
            state: .idle,
            runtimeRootPath: managedRuntimeRootURL?.path,
            supervisorRootPath: resolvedSupervisorRootURL?.path,
            lastMessage: "托管 OpenClaw Runtime Supervisor 已就绪。"
        )
    }

    nonisolated deinit {}

    func currentStatusSnapshot() -> OpenClawManagedRuntimeStatusSnapshot {
        locked { statusSnapshot }
    }

    func buildLaunchCommandPlan(using config: OpenClawConfig) throws -> OpenClawManagedRuntimeSupervisorCommandPlan {
        let shouldUseVerboseGatewayLogging = !config.cliQuietMode || config.cliLogLevel == .debug
        var arguments = ["gateway", "--port", String(config.port)]
        if shouldUseVerboseGatewayLogging {
            arguments.append("--verbose")
        }

        let plan = try host.buildOpenClawCommandPlan(for: config, arguments: arguments)
        return OpenClawManagedRuntimeSupervisorCommandPlan(
            launchStrategy: .foregroundGateway,
            executableURL: plan.executableURL,
            arguments: plan.arguments
        )
    }

    @discardableResult
    func refreshStatus(using config: OpenClawConfig) -> OpenClawManagedRuntimeStatusSnapshot {
        guard config.usesManagedLocalRuntime else {
            return updateStatusSnapshot {
                $0.state = .unmanaged
                $0.launchStrategy = nil
                $0.processID = nil
                $0.port = nil
                $0.lastStatusCheckAt = dateProvider()
                $0.lastMessage = "当前配置未启用 App Managed OpenClaw Runtime。"
                $0.lastError = nil
            }
        }

        let now = dateProvider()
        let persistedState = loadPersistedProcessState()

        return locked {
            cleanupTrackedProcessIfNeededLocked()

            var nextSnapshot = statusSnapshot
            nextSnapshot.runtimeRootPath = managedRuntimeRootURL?.path
            if let resolvedSupervisorRootURL = try? resolvedSupervisorRootURL(required: false) {
                nextSnapshot.supervisorRootPath = resolvedSupervisorRootURL.path
            }
            nextSnapshot.lastStatusCheckAt = now
            nextSnapshot.port = config.port

            if let trackedProcess, isProcessAlive(pid: trackedProcess.pid) {
                nextSnapshot.state = .running
                nextSnapshot.launchStrategy = trackedProcess.launchStrategy
                nextSnapshot.processID = trackedProcess.pid
                nextSnapshot.port = trackedProcess.port
                nextSnapshot.logPath = trackedProcess.logURL.path
                nextSnapshot.lastMessage = "托管 OpenClaw Gateway Sidecar 正在运行。"
                nextSnapshot.lastError = nil
                statusSnapshot = nextSnapshot
                return statusSnapshot
            }

            if let persistedState, isProcessAlive(pid: persistedState.pid) {
                nextSnapshot.state = .running
                nextSnapshot.launchStrategy = persistedState.launchStrategy
                nextSnapshot.binaryPath = persistedState.executablePath
                nextSnapshot.logPath = persistedState.logPath
                nextSnapshot.processID = persistedState.pid
                nextSnapshot.port = persistedState.port
                nextSnapshot.lastStartedAt = persistedState.startedAt
                nextSnapshot.lastMessage = "检测到托管 OpenClaw Runtime 仍在运行。"
                nextSnapshot.lastError = nil
                statusSnapshot = nextSnapshot
                return statusSnapshot
            }

            if persistedState != nil {
                removePersistedProcessState()
            }

            nextSnapshot.state = nextSnapshot.state == .stopping ? .stopping : .idle
            nextSnapshot.launchStrategy = nil
            nextSnapshot.processID = nil
            nextSnapshot.lastMessage = "托管 OpenClaw Runtime 当前未运行。"
            statusSnapshot = nextSnapshot
            return statusSnapshot
        }
    }

    @discardableResult
    func ensureRunning(using config: OpenClawConfig) throws -> OpenClawManagedRuntimeStatusSnapshot {
        let snapshot = refreshStatus(using: config)
        guard config.usesManagedLocalRuntime else { return snapshot }

        if snapshot.state == .running, snapshot.port == config.port {
            return snapshot
        }

        if snapshot.state == .running, snapshot.port != config.port {
            _ = try stop(using: config)
        }

        return try start(using: config)
    }

    @discardableResult
    func start(using config: OpenClawConfig) throws -> OpenClawManagedRuntimeStatusSnapshot {
        guard config.usesManagedLocalRuntime else {
            return refreshStatus(using: config)
        }

        let currentSnapshot = refreshStatus(using: config)
        if currentSnapshot.state == .running, currentSnapshot.port == config.port {
            return currentSnapshot
        }

        let commandPlan = try buildLaunchCommandPlan(using: config)
        let executablePath = commandPlan.executableURL.path
        guard fileManager.fileExists(atPath: executablePath) else {
            throw NSError(
                domain: "OpenClawManagedRuntimeSupervisor",
                code: 4101,
                userInfo: [NSLocalizedDescriptionKey: "未找到托管 OpenClaw 可执行文件：\(executablePath)"]
            )
        }

        guard let supervisorRootURL = try resolvedSupervisorRootURL(required: true) else {
            throw NSError(
                domain: "OpenClawManagedRuntimeSupervisor",
                code: 4103,
                userInfo: [NSLocalizedDescriptionKey: "无法解析托管 Runtime 的 Supervisor 工作目录。"]
            )
        }
        let logsRootURL = supervisorRootURL.appendingPathComponent("logs", isDirectory: true)
        try fileManager.createDirectory(at: logsRootURL, withIntermediateDirectories: true)

        let logURL = logsRootURL.appendingPathComponent("gateway-\(config.port).log", isDirectory: false)
        if !fileManager.fileExists(atPath: logURL.path) {
            fileManager.createFile(atPath: logURL.path, contents: nil)
        }
        let logHandle = try FileHandle(forWritingTo: logURL)
        try logHandle.seekToEnd()

        let process = Process()
        process.executableURL = commandPlan.executableURL
        process.arguments = commandPlan.arguments
        process.currentDirectoryURL = managedRuntimeRootURL ?? fileManager.homeDirectoryForCurrentUser
        process.standardOutput = logHandle
        process.standardError = logHandle
        process.standardInput = FileHandle.nullDevice

        _ = updateStatusSnapshot {
            $0.state = .starting
            $0.launchStrategy = commandPlan.launchStrategy
            $0.binaryPath = executablePath
            $0.logPath = logURL.path
            $0.port = config.port
            $0.lastStatusCheckAt = dateProvider()
            $0.lastMessage = "正在启动托管 OpenClaw Gateway Sidecar..."
            $0.lastError = nil
        }

        process.terminationHandler = { [weak self] terminatedProcess in
            self?.handleProcessTermination(
                pid: terminatedProcess.processIdentifier,
                terminationStatus: terminatedProcess.terminationStatus
            )
        }

        do {
            try process.run()
        } catch {
            try? logHandle.close()
            throw error
        }

        let pid = process.processIdentifier
        let startedAt = dateProvider()
        let trackedProcess = TrackedProcess(
            process: process,
            logHandle: logHandle,
            pid: pid,
            port: config.port,
            logURL: logURL,
            launchStrategy: commandPlan.launchStrategy
        )

        try persistProcessState(
            PersistedProcessState(
                pid: pid,
                port: config.port,
                executablePath: executablePath,
                logPath: logURL.path,
                launchStrategy: commandPlan.launchStrategy,
                startedAt: startedAt
            )
        )

        locked {
            self.trackedProcess = trackedProcess
            self.expectedStoppedPID = nil
            self.statusSnapshot.processID = pid
            self.statusSnapshot.lastStartedAt = startedAt
        }

        let readinessTimeout = TimeInterval(max(config.timeout, 5))
        guard waitForGatewayReadiness(host: config.host, port: config.port, timeoutSeconds: readinessTimeout) else {
            _ = try? stopProcess(pid: pid)
            throw NSError(
                domain: "OpenClawManagedRuntimeSupervisor",
                code: 4102,
                userInfo: [NSLocalizedDescriptionKey: "托管 OpenClaw Gateway 启动超时，\(Int(readinessTimeout)) 秒内未监听端口 \(config.port)。"]
            )
        }

        return updateStatusSnapshot {
            $0.state = .running
            $0.launchStrategy = commandPlan.launchStrategy
            $0.binaryPath = executablePath
            $0.logPath = logURL.path
            $0.processID = pid
            $0.port = config.port
            $0.lastStartedAt = startedAt
            $0.lastStatusCheckAt = dateProvider()
            $0.lastMessage = "托管 OpenClaw Gateway Sidecar 已启动。"
            $0.lastError = nil
        }
    }

    @discardableResult
    func stop(using config: OpenClawConfig) throws -> OpenClawManagedRuntimeStatusSnapshot {
        guard config.usesManagedLocalRuntime else {
            return refreshStatus(using: config)
        }

        let snapshot = refreshStatus(using: config)
        guard let pid = snapshot.processID else {
            return updateStatusSnapshot {
                $0.state = .idle
                $0.lastStatusCheckAt = dateProvider()
                $0.lastMessage = "托管 OpenClaw Runtime 已处于停止状态。"
                $0.lastError = nil
            }
        }

        _ = updateStatusSnapshot {
            $0.state = .stopping
            $0.lastStatusCheckAt = dateProvider()
            $0.lastMessage = "正在停止托管 OpenClaw Runtime..."
            $0.lastError = nil
        }

        try stopProcess(pid: pid)

        return updateStatusSnapshot {
            $0.state = .idle
            $0.processID = nil
            $0.lastExitAt = dateProvider()
            $0.lastStatusCheckAt = dateProvider()
            $0.lastMessage = "托管 OpenClaw Runtime 已停止。"
            $0.lastError = nil
        }
    }

    @discardableResult
    func restart(using config: OpenClawConfig) throws -> OpenClawManagedRuntimeStatusSnapshot {
        guard config.usesManagedLocalRuntime else {
            return refreshStatus(using: config)
        }

        let previousRestartCount = currentStatusSnapshot().restartCount
        _ = try stop(using: config)
        _ = try start(using: config)
        return updateStatusSnapshot {
            $0.restartCount = previousRestartCount + 1
            $0.lastMessage = "托管 OpenClaw Runtime 已重启。"
        }
    }

    @discardableResult
    func markGatewayHeartbeatSucceeded(message: String? = nil) -> OpenClawManagedRuntimeStatusSnapshot {
        let now = dateProvider()
        return updateStatusSnapshot {
            if $0.state == .starting {
                $0.state = .running
            }
            $0.lastHeartbeatAt = now
            $0.lastStatusCheckAt = now
            $0.lastMessage = message?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? message
                : "托管 OpenClaw Gateway 心跳正常。"
            $0.lastError = nil
        }
    }

    @discardableResult
    func markGatewayDisconnect(message: String? = nil) -> OpenClawManagedRuntimeStatusSnapshot {
        let trimmedMessage = message?.trimmingCharacters(in: .whitespacesAndNewlines)
        let runtimeStillRunning = locked {
            cleanupTrackedProcessIfNeededLocked()
            if let trackedProcess {
                return isProcessAlive(pid: trackedProcess.pid)
            }
            if let persistedState = loadPersistedProcessState() {
                return isProcessAlive(pid: persistedState.pid)
            }
            return false
        }

        return updateStatusSnapshot {
            $0.lastStatusCheckAt = dateProvider()
            $0.lastError = trimmedMessage
            if runtimeStillRunning {
                if $0.state == .idle || $0.state == .failed {
                    $0.state = .running
                }
                $0.lastMessage = trimmedMessage?.isEmpty == false
                    ? "Gateway 连接已断开，但托管 Runtime 进程仍在运行：\(trimmedMessage!)"
                    : "Gateway 连接已断开，但托管 Runtime 进程仍在运行。"
            } else {
                $0.state = .failed
                $0.processID = nil
                $0.lastExitAt = dateProvider()
                $0.lastMessage = trimmedMessage?.isEmpty == false
                    ? "Gateway 已断开，且托管 Runtime 未运行：\(trimmedMessage!)"
                    : "Gateway 已断开，且托管 Runtime 未运行。"
            }
        }
    }

    private func persistProcessState(_ state: PersistedProcessState) throws {
        guard let url = try processStateURL(required: true) else {
            throw NSError(
                domain: "OpenClawManagedRuntimeSupervisor",
                code: 4105,
                userInfo: [NSLocalizedDescriptionKey: "无法写入托管 Runtime 进程状态文件。"]
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: url, options: .atomic)
    }

    private func loadPersistedProcessState() -> PersistedProcessState? {
        guard let processStateURL = try? processStateURL(required: false),
              fileManager.fileExists(atPath: processStateURL.path),
              let data = try? Data(contentsOf: processStateURL) else {
            return nil
        }

        return try? JSONDecoder().decode(PersistedProcessState.self, from: data)
    }

    private func removePersistedProcessState() {
        guard let processStateURL = try? processStateURL(required: false) else { return }
        try? fileManager.removeItem(at: processStateURL)
    }

    private func processStateURL(required: Bool) throws -> URL? {
        guard let supervisorRootURL = try resolvedSupervisorRootURL(required: required) else { return nil }
        if required {
            try fileManager.createDirectory(at: supervisorRootURL, withIntermediateDirectories: true)
        }
        return supervisorRootURL.appendingPathComponent("process-state.json", isDirectory: false)
    }

    private func resolvedSupervisorRootURL(required: Bool = false) throws -> URL? {
        if let supervisorRootURL {
            if required {
                try fileManager.createDirectory(at: supervisorRootURL, withIntermediateDirectories: true)
            }
            return supervisorRootURL
        }

        guard let managedRuntimeRootURL else {
            if required {
                throw NSError(
                    domain: "OpenClawManagedRuntimeSupervisor",
                    code: 4103,
                    userInfo: [NSLocalizedDescriptionKey: "无法解析托管 Runtime 的 Supervisor 工作目录。"]
                )
            }
            return nil
        }

        let resolved = managedRuntimeRootURL
            .deletingLastPathComponent()
            .appendingPathComponent("supervisor", isDirectory: true)
        if required {
            try fileManager.createDirectory(at: resolved, withIntermediateDirectories: true)
        }
        return resolved
    }

    private func waitForGatewayReadiness(
        host: String,
        port: Int,
        timeoutSeconds: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(max(timeoutSeconds, 1))
        while Date() < deadline {
            if canConnect(host: host, port: port) {
                return true
            }

            let stillRunning = locked {
                guard let trackedProcess else { return false }
                return trackedProcess.process.isRunning
            }
            if !stillRunning {
                return false
            }

            Thread.sleep(forTimeInterval: 0.25)
        }

        return false
    }

    private func canConnect(host: String, port: Int) -> Bool {
        var hints = addrinfo(
            ai_flags: 0,
            ai_family: AF_UNSPEC,
            ai_socktype: Int32(SOCK_STREAM),
            ai_protocol: IPPROTO_TCP,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )
        var infoPointer: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, String(port), &hints, &infoPointer) == 0,
              let firstInfo = infoPointer else {
            return false
        }
        defer { freeaddrinfo(firstInfo) }

        var currentInfo: UnsafeMutablePointer<addrinfo>? = firstInfo
        while let info = currentInfo {
            let socketDescriptor = socket(info.pointee.ai_family, info.pointee.ai_socktype, info.pointee.ai_protocol)
            if socketDescriptor >= 0 {
                var timeout = timeval(tv_sec: 1, tv_usec: 0)
                withUnsafePointer(to: &timeout) { pointer in
                    pointer.withMemoryRebound(to: UInt8.self, capacity: MemoryLayout<timeval>.size) { reboundPointer in
                        _ = setsockopt(
                            socketDescriptor,
                            SOL_SOCKET,
                            SO_SNDTIMEO,
                            reboundPointer,
                            socklen_t(MemoryLayout<timeval>.size)
                        )
                    }
                }

                let result = connect(socketDescriptor, info.pointee.ai_addr, info.pointee.ai_addrlen)
                close(socketDescriptor)
                if result == 0 {
                    return true
                }
            }

            currentInfo = info.pointee.ai_next
        }

        return false
    }

    private func stopProcess(pid: Int32) throws {
        locked {
            expectedStoppedPID = pid
        }

        if let trackedProcess = locked({ self.trackedProcess }), trackedProcess.pid == pid {
            trackedProcess.process.terminate()
        } else if isProcessAlive(pid: pid) {
            kill(pid, SIGTERM)
        }

        let gracefulDeadline = Date().addingTimeInterval(3)
        while Date() < gracefulDeadline {
            if !isProcessAlive(pid: pid) {
                cleanupStoppedProcess(pid: pid)
                return
            }
            Thread.sleep(forTimeInterval: 0.1)
        }

        if isProcessAlive(pid: pid) {
            kill(pid, SIGKILL)
        }

        let hardDeadline = Date().addingTimeInterval(2)
        while Date() < hardDeadline {
            if !isProcessAlive(pid: pid) {
                cleanupStoppedProcess(pid: pid)
                return
            }
            Thread.sleep(forTimeInterval: 0.1)
        }

        throw NSError(
            domain: "OpenClawManagedRuntimeSupervisor",
            code: 4104,
            userInfo: [NSLocalizedDescriptionKey: "无法停止托管 OpenClaw Runtime 进程（pid \(pid)）。"]
        )
    }

    private func cleanupStoppedProcess(pid: Int32) {
        removePersistedProcessState()
        locked {
            if let trackedProcess, trackedProcess.pid == pid {
                try? trackedProcess.logHandle.close()
                self.trackedProcess = nil
            }
            if expectedStoppedPID == pid {
                expectedStoppedPID = nil
            }
        }
    }

    private func handleProcessTermination(pid: Int32, terminationStatus: Int32) {
        removePersistedProcessState()

        locked {
            if let trackedProcess, trackedProcess.pid == pid {
                try? trackedProcess.logHandle.close()
                self.trackedProcess = nil
            }

            let expectedStop = expectedStoppedPID == pid
            if expectedStop {
                expectedStoppedPID = nil
            }

            statusSnapshot.processID = nil
            statusSnapshot.lastExitAt = dateProvider()
            statusSnapshot.lastStatusCheckAt = dateProvider()

            if expectedStop {
                statusSnapshot.state = .idle
                statusSnapshot.lastMessage = "托管 OpenClaw Runtime 已停止。"
                statusSnapshot.lastError = nil
            } else {
                statusSnapshot.state = .failed
                statusSnapshot.lastMessage = "托管 OpenClaw Runtime 进程异常退出（code \(terminationStatus)）。"
                statusSnapshot.lastError = statusSnapshot.lastMessage
            }
        }
    }

    private func cleanupTrackedProcessIfNeededLocked() {
        guard let trackedProcess, !trackedProcess.process.isRunning else { return }
        try? trackedProcess.logHandle.close()
        self.trackedProcess = nil
    }

    private func isProcessAlive(pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        return kill(pid, 0) == 0 || errno == EPERM
    }

    private func updateStatusSnapshot(
        _ mutation: (inout OpenClawManagedRuntimeStatusSnapshot) -> Void
    ) -> OpenClawManagedRuntimeStatusSnapshot {
        locked {
            mutation(&statusSnapshot)
            return statusSnapshot
        }
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
