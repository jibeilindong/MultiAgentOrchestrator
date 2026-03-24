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
    var environment: [String: String]
}

struct OpenClawManagedRuntimeStatusSnapshot: Equatable {
    var state: OpenClawManagedRuntimeSupervisorState
    var launchStrategy: OpenClawManagedRuntimeLaunchStrategy?
    var runtimeRootPath: String?
    var supervisorRootPath: String?
    var binaryPath: String?
    var logPath: String?
    var processID: Int32?
    var requestedPort: Int?
    var port: Int?
    var lastStartedAt: Date?
    var lastExitAt: Date?
    var lastUnexpectedExitAt: Date?
    var lastHeartbeatAt: Date?
    var lastStatusCheckAt: Date?
    var restartCount: Int
    var manualRestartCount: Int
    var automaticRecoveryCount: Int
    var consecutiveCrashCount: Int
    var automaticRecoveryAttempt: Int?
    var lastRecoveryAttemptAt: Date?
    var lastRecoverySucceededAt: Date?
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
        requestedPort: Int? = nil,
        port: Int? = nil,
        lastStartedAt: Date? = nil,
        lastExitAt: Date? = nil,
        lastUnexpectedExitAt: Date? = nil,
        lastHeartbeatAt: Date? = nil,
        lastStatusCheckAt: Date? = nil,
        restartCount: Int = 0,
        manualRestartCount: Int = 0,
        automaticRecoveryCount: Int = 0,
        consecutiveCrashCount: Int = 0,
        automaticRecoveryAttempt: Int? = nil,
        lastRecoveryAttemptAt: Date? = nil,
        lastRecoverySucceededAt: Date? = nil,
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
        self.requestedPort = requestedPort
        self.port = port
        self.lastStartedAt = lastStartedAt
        self.lastExitAt = lastExitAt
        self.lastUnexpectedExitAt = lastUnexpectedExitAt
        self.lastHeartbeatAt = lastHeartbeatAt
        self.lastStatusCheckAt = lastStatusCheckAt
        self.restartCount = restartCount
        self.manualRestartCount = manualRestartCount
        self.automaticRecoveryCount = automaticRecoveryCount
        self.consecutiveCrashCount = consecutiveCrashCount
        self.automaticRecoveryAttempt = automaticRecoveryAttempt
        self.lastRecoveryAttemptAt = lastRecoveryAttemptAt
        self.lastRecoverySucceededAt = lastRecoverySucceededAt
        self.lastMessage = lastMessage
        self.lastError = lastError
    }
}

nonisolated final class OpenClawManagedRuntimeSupervisor {
    private struct PersistedProcessState: Codable {
        var pid: Int32
        var requestedPort: Int?
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
    private let automaticRecoveryDelaySeconds: TimeInterval
    private let automaticRecoveryStableUptimeSeconds: TimeInterval
    private let automaticRecoveryMaxConsecutiveAttempts: Int
    private let lock = NSLock()

    private var trackedProcess: TrackedProcess?
    private var expectedStoppedPID: Int32?
    private var statusSnapshot: OpenClawManagedRuntimeStatusSnapshot
    private var lastManagedConfig: OpenClawConfig?
    private var automaticRecoveryWorkItem: DispatchWorkItem?
    private var automaticRecoveryInProgress = false
    private var consecutiveUnexpectedExitCount = 0
    private var statusChangeHandler: ((OpenClawManagedRuntimeStatusSnapshot) -> Void)?

    nonisolated init(
        fileManager: FileManager = .default,
        host: OpenClawHost? = nil,
        managedRuntimeRootURL: URL? = OpenClawManagedRuntimeInstaller.shared.managedRuntimeRootURL(),
        supervisorRootURL: URL? = nil,
        dateProvider: @escaping () -> Date = Date.init,
        automaticRecoveryDelaySeconds: TimeInterval = 2,
        automaticRecoveryStableUptimeSeconds: TimeInterval = 30,
        automaticRecoveryMaxConsecutiveAttempts: Int = 3
    ) {
        self.fileManager = fileManager
        self.host = host ?? OpenClawHost(
            fileManager: fileManager,
            managedRuntimeRootURL: managedRuntimeRootURL
        )
        self.managedRuntimeRootURL = managedRuntimeRootURL
        self.supervisorRootURL = supervisorRootURL
        self.dateProvider = dateProvider
        self.automaticRecoveryDelaySeconds = max(automaticRecoveryDelaySeconds, 0)
        self.automaticRecoveryStableUptimeSeconds = max(automaticRecoveryStableUptimeSeconds, 0)
        self.automaticRecoveryMaxConsecutiveAttempts = max(automaticRecoveryMaxConsecutiveAttempts, 1)
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

    func currentStatusSnapshot() -> OpenClawManagedRuntimeStatusSnapshot {
        locked { statusSnapshot }
    }

    func setStatusChangeHandler(_ handler: ((OpenClawManagedRuntimeStatusSnapshot) -> Void)?) {
        locked {
            statusChangeHandler = handler
        }
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
            arguments: plan.arguments,
            environment: plan.environment
        )
    }

    @discardableResult
    func refreshStatus(using config: OpenClawConfig) -> OpenClawManagedRuntimeStatusSnapshot {
        guard config.usesManagedLocalRuntime else {
            return updateStatusSnapshot {
                $0.state = .unmanaged
                $0.launchStrategy = nil
                $0.processID = nil
                $0.requestedPort = nil
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
            _ = reconcileCrashRecoveryStabilityIfNeededLocked(now: now)

            var nextSnapshot = statusSnapshot
            nextSnapshot.runtimeRootPath = managedRuntimeRootURL?.path
            if let resolvedSupervisorRootURL = try? resolvedSupervisorRootURL(required: false) {
                nextSnapshot.supervisorRootPath = resolvedSupervisorRootURL.path
            }
            nextSnapshot.lastStatusCheckAt = now
            nextSnapshot.requestedPort = config.port
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
                nextSnapshot.requestedPort = persistedState.requestedPort ?? config.port
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

        if snapshot.state == .running {
            return snapshot
        }

        return try start(using: config)
    }

    @discardableResult
    func start(using config: OpenClawConfig) throws -> OpenClawManagedRuntimeStatusSnapshot {
        guard config.usesManagedLocalRuntime else {
            return refreshStatus(using: config)
        }

        let automaticRecoveryStart = locked { automaticRecoveryInProgress }
        locked {
            lastManagedConfig = config
            if !automaticRecoveryStart {
                cancelAutomaticRecoveryLocked()
                consecutiveUnexpectedExitCount = 0
                statusSnapshot.consecutiveCrashCount = 0
                statusSnapshot.automaticRecoveryAttempt = nil
            }
        }

        let currentSnapshot = refreshStatus(using: config)
        if currentSnapshot.state == .running {
            return currentSnapshot
        }

        try OpenClawManagedRuntimeInstaller.shared.ensureManagedRuntimeBootstrapIfNeeded()

        var launchConfig = config
        if config.usesManagedLocalRuntime {
            launchConfig.port = resolveManagedRuntimePort(preferredPort: config.port, host: config.host)
        }
        let requestedPort = config.port
        let didReassignPort = launchConfig.port != requestedPort

        let commandPlan = try buildLaunchCommandPlan(using: launchConfig)
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

        let logURL = logsRootURL.appendingPathComponent("gateway-\(launchConfig.port).log", isDirectory: false)
        if !fileManager.fileExists(atPath: logURL.path) {
            fileManager.createFile(atPath: logURL.path, contents: nil)
        }
        let logHandle = try FileHandle(forWritingTo: logURL)
        try logHandle.truncate(atOffset: 0)
        try logHandle.seekToEnd()

        let process = Process()
        process.executableURL = commandPlan.executableURL
        process.arguments = commandPlan.arguments
        if !commandPlan.environment.isEmpty {
            var mergedEnvironment = ProcessInfo.processInfo.environment
            commandPlan.environment.forEach { mergedEnvironment[$0.key] = $0.value }
            if let stateDirectory = mergedEnvironment["OPENCLAW_STATE_DIR"],
               !stateDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try fileManager.createDirectory(
                    at: URL(fileURLWithPath: stateDirectory, isDirectory: true),
                    withIntermediateDirectories: true
                )
            }
            process.environment = mergedEnvironment
        }
        process.currentDirectoryURL = managedRuntimeRootURL ?? fileManager.homeDirectoryForCurrentUser
        process.standardOutput = logHandle
        process.standardError = logHandle
        process.standardInput = FileHandle.nullDevice

        _ = updateStatusSnapshot {
            $0.state = .starting
            $0.launchStrategy = commandPlan.launchStrategy
            $0.binaryPath = executablePath
            $0.logPath = logURL.path
            $0.requestedPort = requestedPort
            $0.port = launchConfig.port
            $0.lastStatusCheckAt = dateProvider()
            $0.lastMessage = didReassignPort
                ? "首选端口 \(requestedPort) 已被占用，正在改用 \(launchConfig.port) 启动托管 OpenClaw Gateway Sidecar..."
                : "正在启动托管 OpenClaw Gateway Sidecar..."
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
            port: launchConfig.port,
            logURL: logURL,
            launchStrategy: commandPlan.launchStrategy
        )

        try persistProcessState(
            PersistedProcessState(
                pid: pid,
                requestedPort: requestedPort,
                port: launchConfig.port,
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
        guard waitForGatewayReadiness(host: launchConfig.host, port: launchConfig.port, timeoutSeconds: readinessTimeout) else {
            let processWasRunning = isProcessAlive(pid: pid)
            _ = try? stopProcess(pid: pid)
            let failureMessage = readinessFailureMessage(
                logURL: logURL,
                port: launchConfig.port,
                timeoutSeconds: readinessTimeout,
                processWasRunning: processWasRunning
            )
            throw NSError(
                domain: "OpenClawManagedRuntimeSupervisor",
                code: 4102,
                userInfo: [NSLocalizedDescriptionKey: failureMessage]
            )
        }

        return updateStatusSnapshot {
            $0.state = .running
            $0.launchStrategy = commandPlan.launchStrategy
            $0.binaryPath = executablePath
            $0.logPath = logURL.path
            $0.processID = pid
            $0.requestedPort = requestedPort
            $0.port = launchConfig.port
            $0.lastStartedAt = startedAt
            $0.lastStatusCheckAt = dateProvider()
            $0.lastMessage = didReassignPort
                ? "首选端口 \(requestedPort) 已被占用，托管 OpenClaw Gateway Sidecar 已改用 \(launchConfig.port) 启动。"
                : "托管 OpenClaw Gateway Sidecar 已启动。"
            $0.lastError = nil
        }
    }

    @discardableResult
    func stop(using config: OpenClawConfig) throws -> OpenClawManagedRuntimeStatusSnapshot {
        guard config.usesManagedLocalRuntime else {
            return refreshStatus(using: config)
        }

        locked {
            cancelAutomaticRecoveryLocked()
            automaticRecoveryInProgress = false
            consecutiveUnexpectedExitCount = 0
        }

        let snapshot = refreshStatus(using: config)
        guard let pid = snapshot.processID else {
            return updateStatusSnapshot {
                $0.state = .idle
                $0.lastStatusCheckAt = dateProvider()
                $0.consecutiveCrashCount = 0
                $0.automaticRecoveryAttempt = nil
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
            $0.consecutiveCrashCount = 0
            $0.automaticRecoveryAttempt = nil
            $0.lastMessage = "托管 OpenClaw Runtime 已停止。"
            $0.lastError = nil
        }
    }

    @discardableResult
    func restart(using config: OpenClawConfig) throws -> OpenClawManagedRuntimeStatusSnapshot {
        guard config.usesManagedLocalRuntime else {
            return refreshStatus(using: config)
        }

        let currentSnapshot = currentStatusSnapshot()
        let previousRestartCount = currentSnapshot.restartCount
        let previousManualRestartCount = currentSnapshot.manualRestartCount
        _ = try stop(using: config)
        _ = try start(using: config)
        return updateStatusSnapshot {
            $0.restartCount = previousRestartCount + 1
            $0.manualRestartCount = previousManualRestartCount + 1
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
            if self.recoveryWindowHasStabilized(now: now, snapshot: $0) {
                self.consecutiveUnexpectedExitCount = 0
                $0.consecutiveCrashCount = 0
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

    private func resolveManagedRuntimePort(preferredPort: Int, host: String) -> Int {
        let normalizedPreferredPort = max(preferredPort, 1)
        for offset in 0...64 {
            let candidatePort = normalizedPreferredPort + offset
            if !canConnect(host: host, port: candidatePort) {
                return candidatePort
            }
        }

        return normalizedPreferredPort
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

    private func readinessFailureMessage(
        logURL: URL,
        port: Int,
        timeoutSeconds: TimeInterval,
        processWasRunning: Bool
    ) -> String {
        let baseMessage: String
        if processWasRunning {
            baseMessage = "托管 OpenClaw Gateway 启动超时，\(Int(timeoutSeconds)) 秒内未监听端口 \(port)。"
        } else {
            baseMessage = "托管 OpenClaw Gateway 在监听端口 \(port) 前已退出。"
        }

        guard let excerpt = recentLogExcerpt(from: logURL) else {
            return baseMessage
        }
        return "\(baseMessage)\n最近日志：\n\(excerpt)"
    }

    private func recentLogExcerpt(from logURL: URL, maxLines: Int = 12, maxCharacters: Int = 1200) -> String? {
        guard let data = try? Data(contentsOf: logURL),
              var text = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return nil
        }

        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return nil }

        text = lines.suffix(maxLines).joined(separator: "\n")
        if text.count > maxCharacters {
            text = String(text.suffix(maxCharacters))
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
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
        let now = dateProvider()
        var snapshotToPublish: OpenClawManagedRuntimeStatusSnapshot?
        var recoveryConfig: OpenClawConfig?
        var recoveryAttempt = 0

        locked {
            if let trackedProcess, trackedProcess.pid == pid {
                try? trackedProcess.logHandle.close()
                self.trackedProcess = nil
            }

            let expectedStop = expectedStoppedPID == pid
            if expectedStop {
                expectedStoppedPID = nil
                cancelAutomaticRecoveryLocked()
                automaticRecoveryInProgress = false
                consecutiveUnexpectedExitCount = 0
            }

            let uptime = statusSnapshot.lastStartedAt.map { now.timeIntervalSince($0) } ?? 0
            if !expectedStop && uptime >= automaticRecoveryStableUptimeSeconds {
                consecutiveUnexpectedExitCount = 0
            }

            statusSnapshot.processID = nil
            statusSnapshot.lastExitAt = now
            statusSnapshot.lastStatusCheckAt = now

            if expectedStop {
                statusSnapshot.state = .idle
                statusSnapshot.consecutiveCrashCount = 0
                statusSnapshot.automaticRecoveryAttempt = nil
                statusSnapshot.lastMessage = "托管 OpenClaw Runtime 已停止。"
                statusSnapshot.lastError = nil
            } else if let config = lastManagedConfig, config.shouldAutoRestartManagedRuntimeOnCrash {
                consecutiveUnexpectedExitCount += 1
                statusSnapshot.lastUnexpectedExitAt = now
                statusSnapshot.consecutiveCrashCount = consecutiveUnexpectedExitCount
                if consecutiveUnexpectedExitCount <= automaticRecoveryMaxConsecutiveAttempts {
                    recoveryConfig = config
                    recoveryAttempt = consecutiveUnexpectedExitCount
                    statusSnapshot.state = .starting
                    statusSnapshot.automaticRecoveryAttempt = recoveryAttempt
                    let crashMessage = "托管 OpenClaw Runtime 进程异常退出（code \(terminationStatus)）。"
                    statusSnapshot.lastMessage = "\(crashMessage) \(Int(automaticRecoveryDelaySeconds)) 秒后自动重启（\(recoveryAttempt)/\(automaticRecoveryMaxConsecutiveAttempts)）。"
                    statusSnapshot.lastError = crashMessage
                } else {
                    statusSnapshot.state = .failed
                    statusSnapshot.automaticRecoveryAttempt = nil
                    statusSnapshot.lastMessage = "托管 OpenClaw Runtime 进程异常退出（code \(terminationStatus)），且已达到自动恢复上限。"
                    statusSnapshot.lastError = statusSnapshot.lastMessage
                }
            } else {
                consecutiveUnexpectedExitCount += 1
                statusSnapshot.state = .failed
                statusSnapshot.lastUnexpectedExitAt = now
                statusSnapshot.consecutiveCrashCount = consecutiveUnexpectedExitCount
                statusSnapshot.automaticRecoveryAttempt = nil
                statusSnapshot.lastMessage = "托管 OpenClaw Runtime 进程异常退出（code \(terminationStatus)）。"
                statusSnapshot.lastError = statusSnapshot.lastMessage
            }

            snapshotToPublish = statusSnapshot
        }

        if let snapshotToPublish {
            publishStatusSnapshot(snapshotToPublish)
        }

        if let recoveryConfig {
            scheduleAutomaticRecovery(using: recoveryConfig, attempt: recoveryAttempt)
        }
    }

    private func cleanupTrackedProcessIfNeededLocked() {
        guard let trackedProcess, !trackedProcess.process.isRunning else { return }
        try? trackedProcess.logHandle.close()
        self.trackedProcess = nil
    }

    private func reconcileCrashRecoveryStabilityIfNeededLocked(now: Date) -> Bool {
        guard consecutiveUnexpectedExitCount > 0 else { return false }
        guard !automaticRecoveryInProgress else { return false }
        guard automaticRecoveryWorkItem == nil else { return false }
        guard recoveryWindowHasStabilized(now: now, snapshot: statusSnapshot) else { return false }
        consecutiveUnexpectedExitCount = 0
        statusSnapshot.consecutiveCrashCount = 0
        return true
    }

    private func isProcessAlive(pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        return kill(pid, 0) == 0 || errno == EPERM
    }

    private func recoveryWindowHasStabilized(
        now: Date,
        snapshot: OpenClawManagedRuntimeStatusSnapshot
    ) -> Bool {
        guard automaticRecoveryStableUptimeSeconds > 0 else { return true }
        guard snapshot.state == .running else { return false }
        guard let lastStartedAt = snapshot.lastStartedAt else { return false }
        return now.timeIntervalSince(lastStartedAt) >= automaticRecoveryStableUptimeSeconds
    }

    private func updateStatusSnapshot(
        _ mutation: (inout OpenClawManagedRuntimeStatusSnapshot) -> Void
    ) -> OpenClawManagedRuntimeStatusSnapshot {
        let snapshot = locked {
            mutation(&statusSnapshot)
            return statusSnapshot
        }
        publishStatusSnapshot(snapshot)
        return snapshot
    }

    private func scheduleAutomaticRecovery(using config: OpenClawConfig, attempt: Int) {
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }

            self.locked {
                self.automaticRecoveryWorkItem = nil
                self.automaticRecoveryInProgress = true
            }
            defer {
                self.locked {
                    self.automaticRecoveryInProgress = false
                }
            }

            do {
                let recoveryAttemptAt = self.dateProvider()
                _ = self.updateStatusSnapshot {
                    $0.state = .starting
                    $0.automaticRecoveryAttempt = attempt
                    $0.lastRecoveryAttemptAt = recoveryAttemptAt
                    $0.lastStatusCheckAt = recoveryAttemptAt
                    $0.lastMessage = "正在执行托管 OpenClaw Runtime 自动恢复（第 \(attempt) 次尝试）。"
                    $0.lastError = nil
                }
                _ = try self.start(using: config)
                let recoverySucceededAt = self.dateProvider()
                _ = self.updateStatusSnapshot {
                    $0.restartCount += 1
                    $0.automaticRecoveryCount += 1
                    $0.automaticRecoveryAttempt = nil
                    $0.lastRecoverySucceededAt = recoverySucceededAt
                    $0.lastStatusCheckAt = self.dateProvider()
                    $0.lastMessage = "托管 OpenClaw Runtime 已自动恢复（第 \(attempt) 次重启）。"
                    $0.lastError = nil
                }
            } catch {
                let failureMessage = "托管 OpenClaw Runtime 自动恢复失败：\(error.localizedDescription)"
                _ = self.updateStatusSnapshot {
                    $0.state = .failed
                    $0.automaticRecoveryAttempt = nil
                    $0.lastExitAt = self.dateProvider()
                    $0.lastStatusCheckAt = self.dateProvider()
                    $0.lastMessage = failureMessage
                    $0.lastError = failureMessage
                }
            }
        }

        locked {
            cancelAutomaticRecoveryLocked()
            automaticRecoveryWorkItem = workItem
        }

        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + automaticRecoveryDelaySeconds,
            execute: workItem
        )
    }

    private func cancelAutomaticRecoveryLocked() {
        automaticRecoveryWorkItem?.cancel()
        automaticRecoveryWorkItem = nil
    }

    private func publishStatusSnapshot(_ snapshot: OpenClawManagedRuntimeStatusSnapshot) {
        let handler = locked { statusChangeHandler }
        handler?(snapshot)
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
