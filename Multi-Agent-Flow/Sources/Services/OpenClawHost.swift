//
//  OpenClawHost.swift
//  Multi-Agent-Flow
//

import Foundation
import Darwin

struct OpenClawHostCommandPlan {
    let executableURL: URL
    let arguments: [String]
}

nonisolated final class OpenClawHost {
    private final class ProcessOutputAccumulator {
        private let lock = NSLock()
        private var stdoutData = Data()
        private var stderrData = Data()

        func appendStdout(_ data: Data) {
            lock.lock()
            stdoutData.append(data)
            lock.unlock()
        }

        func appendStderr(_ data: Data) {
            lock.lock()
            stderrData.append(data)
            lock.unlock()
        }

        func snapshot() -> (stdout: Data, stderr: Data) {
            lock.lock()
            let stdout = stdoutData
            let stderr = stderrData
            lock.unlock()
            return (stdout, stderr)
        }
    }

    private let fileManager: FileManager
    private let bundleResourceURL: URL?
    private let managedRuntimeRootURL: URL?
    private let homeDirectory: URL

    init(
        fileManager: FileManager = .default,
        bundleResourceURL: URL? = Bundle.main.resourceURL,
        managedRuntimeRootURL: URL? = nil,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.fileManager = fileManager
        self.bundleResourceURL = bundleResourceURL
        self.managedRuntimeRootURL = managedRuntimeRootURL
        self.homeDirectory = homeDirectory
    }

    func resolveLocalBinaryPath(for config: OpenClawConfig) -> String {
        let candidates = Self.localBinaryPathCandidates(
            for: config,
            bundleResourceURL: bundleResourceURL,
            managedRuntimeRootURL: managedRuntimeRootURL,
            homeDirectory: homeDirectory
        )
        return candidates.first(where: { fileManager.fileExists(atPath: $0) })
            ?? candidates.first
            ?? config.localBinaryPath.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func fallbackLocalOpenClawRootURL() -> URL {
        homeDirectory
            .appendingPathComponent(".openclaw", isDirectory: true)
    }

    nonisolated static func executeProcessAndCaptureOutput(
        executableURL: URL,
        arguments: [String],
        standardInput: FileHandle? = nil,
        timeoutSeconds: TimeInterval? = nil,
        onStdoutChunk: ((Data) -> Void)? = nil
    ) throws -> (terminationStatus: Int32, standardOutput: Data, standardError: Data) {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardInput = standardInput

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let accumulator = ProcessOutputAccumulator()
        let terminationSemaphore = DispatchSemaphore(value: 0)

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            accumulator.appendStdout(data)
            onStdoutChunk?(data)
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            accumulator.appendStderr(data)
        }

        process.terminationHandler = { _ in
            terminationSemaphore.signal()
        }

        try process.run()

        let waitResult: DispatchTimeoutResult
        if let timeoutSeconds {
            waitResult = terminationSemaphore.wait(timeout: .now() + max(timeoutSeconds, 1))
        } else {
            terminationSemaphore.wait()
            waitResult = .success
        }

        if waitResult == .timedOut {
            if process.isRunning {
                process.terminate()
                if terminationSemaphore.wait(timeout: .now() + 1) == .timedOut, process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                    _ = terminationSemaphore.wait(timeout: .now() + 1)
                }
            }

            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            let stdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            if !stdout.isEmpty {
                accumulator.appendStdout(stdout)
            }
            if !stderr.isEmpty {
                accumulator.appendStderr(stderr)
            }

            throw NSError(
                domain: "OpenClawManager",
                code: 9801,
                userInfo: [NSLocalizedDescriptionKey: "命令执行超时（\(Int(max(timeoutSeconds ?? 0, 1))) 秒）：\((arguments.first ?? executableURL.lastPathComponent))"]
            )
        }

        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        let remainingStdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        if !remainingStdout.isEmpty {
            accumulator.appendStdout(remainingStdout)
            onStdoutChunk?(remainingStdout)
        }

        let remainingStderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        if !remainingStderr.isEmpty {
            accumulator.appendStderr(remainingStderr)
        }

        let snapshot = accumulator.snapshot()
        return (process.terminationStatus, snapshot.stdout, snapshot.stderr)
    }

    nonisolated private static func deduplicatedLocalBinaryPaths(_ candidates: [String]) -> [String] {
        var seen = Set<String>()
        return candidates.compactMap { candidate in
            let normalized = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { return nil }
            guard seen.insert(normalized).inserted else { return nil }
            return normalized
        }
    }

    nonisolated private static func defaultManagedLocalRuntimeRootURL(
        fileManager: FileManager = .default
    ) -> URL? {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("Multi-Agent-Flow", isDirectory: true)
            .appendingPathComponent("openclaw", isDirectory: true)
            .appendingPathComponent("runtime", isDirectory: true)
    }

    nonisolated private static func localBinaryPathCandidates(
        for config: OpenClawConfig,
        bundleResourceURL: URL? = Bundle.main.resourceURL,
        managedRuntimeRootURL: URL? = nil,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [String] {
        let configured = config.localBinaryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard config.deploymentKind == .local else {
            return configured.isEmpty ? [] : [configured]
        }

        if config.requiresExplicitLocalBinaryPath {
            return configured.isEmpty ? [] : [configured]
        }

        let managedRoot = managedRuntimeRootURL ?? defaultManagedLocalRuntimeRootURL()
        let bundleCandidates = [bundleResourceURL].compactMap { $0 }.flatMap { resourceURL in
            [
                resourceURL.appendingPathComponent("OpenClaw/bin/openclaw", isDirectory: false).path,
                resourceURL.appendingPathComponent("openclaw/bin/openclaw", isDirectory: false).path,
                resourceURL.appendingPathComponent("OpenClaw/openclaw", isDirectory: false).path,
                resourceURL.appendingPathComponent("openclaw/openclaw", isDirectory: false).path
            ]
        }
        let managedCandidates = [managedRoot].compactMap { $0 }.flatMap { rootURL in
            [
                rootURL.appendingPathComponent("bin/openclaw", isDirectory: false).path,
                rootURL.appendingPathComponent("openclaw", isDirectory: false).path
            ]
        }
        let systemCandidates = [
            homeDirectory.appendingPathComponent(".local/bin/openclaw", isDirectory: false).path,
            "/usr/local/bin/openclaw",
            "/opt/homebrew/bin/openclaw",
            "/usr/bin/openclaw"
        ]

        if !configured.isEmpty {
            return deduplicatedLocalBinaryPaths([configured] + bundleCandidates + managedCandidates + systemCandidates)
        }

        return deduplicatedLocalBinaryPaths(bundleCandidates + managedCandidates + systemCandidates)
    }

    func buildOpenClawCommandPlan(
        for config: OpenClawConfig,
        arguments: [String]
    ) throws -> OpenClawHostCommandPlan {
        switch config.deploymentKind {
        case .local:
            return OpenClawHostCommandPlan(
                executableURL: URL(fileURLWithPath: resolveLocalBinaryPath(for: config)),
                arguments: arguments
            )
        case .container:
            guard let containerName = containerName(for: config) else {
                throw NSError(
                    domain: "OpenClawHost",
                    code: 1001,
                    userInfo: [NSLocalizedDescriptionKey: "容器名称未配置"]
                )
            }
            return OpenClawHostCommandPlan(
                executableURL: URL(fileURLWithPath: "/usr/bin/env"),
                arguments: [containerEngine(for: config), "exec", containerName, "openclaw"] + arguments
            )
        case .remoteServer:
            throw NSError(
                domain: "OpenClawHost",
                code: 1002,
                userInfo: [NSLocalizedDescriptionKey: "远程网关模式不支持直接执行 OpenClaw CLI"]
            )
        }
    }

    func buildClawHubCommandPlan(
        for config: OpenClawConfig,
        arguments: [String]
    ) throws -> OpenClawHostCommandPlan {
        switch config.deploymentKind {
        case .local:
            return OpenClawHostCommandPlan(
                executableURL: URL(fileURLWithPath: "/usr/bin/env"),
                arguments: ["clawhub"] + arguments
            )
        case .container:
            guard let containerName = containerName(for: config) else {
                throw NSError(
                    domain: "OpenClawHost",
                    code: 1003,
                    userInfo: [NSLocalizedDescriptionKey: "容器名称未配置"]
                )
            }
            return OpenClawHostCommandPlan(
                executableURL: URL(fileURLWithPath: "/usr/bin/env"),
                arguments: [containerEngine(for: config), "exec", containerName, "clawhub"] + arguments
            )
        case .remoteServer:
            throw NSError(
                domain: "OpenClawHost",
                code: 1004,
                userInfo: [NSLocalizedDescriptionKey: "远程网关模式不支持直接执行 ClawHub CLI"]
            )
        }
    }

    func buildDeploymentCommandPlan(
        for config: OpenClawConfig,
        arguments: [String]
    ) throws -> OpenClawHostCommandPlan {
        guard config.deploymentKind == .container else {
            throw NSError(
                domain: "OpenClawHost",
                code: 1005,
                userInfo: [NSLocalizedDescriptionKey: "当前配置不是容器模式，无法执行部署引擎命令。"]
            )
        }

        return OpenClawHostCommandPlan(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [containerEngine(for: config)] + arguments
        )
    }

    func buildDeploymentShellPlan(
        for config: OpenClawConfig,
        script: String
    ) throws -> OpenClawHostCommandPlan {
        guard config.deploymentKind == .container else {
            throw NSError(
                domain: "OpenClawHost",
                code: 1006,
                userInfo: [NSLocalizedDescriptionKey: "当前配置不是容器模式，无法执行容器 Shell 命令。"]
            )
        }

        guard let containerName = containerName(for: config) else {
            throw NSError(
                domain: "OpenClawHost",
                code: 1007,
                userInfo: [NSLocalizedDescriptionKey: "容器名称未配置"]
            )
        }

        return OpenClawHostCommandPlan(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [containerEngine(for: config), "exec", containerName, "sh", "-lc", script]
        )
    }

    func runOpenClawCommand(
        using config: OpenClawConfig,
        arguments: [String],
        standardInput: FileHandle? = nil,
        timeoutSeconds: TimeInterval? = nil,
        onStdoutChunk: ((Data) -> Void)? = nil
    ) throws -> (terminationStatus: Int32, standardOutput: Data, standardError: Data) {
        let plan = try buildOpenClawCommandPlan(for: config, arguments: arguments)
        return try Self.executeProcessAndCaptureOutput(
            executableURL: plan.executableURL,
            arguments: plan.arguments,
            standardInput: standardInput,
            timeoutSeconds: timeoutSeconds,
            onStdoutChunk: onStdoutChunk
        )
    }

    func runClawHubCommand(
        using config: OpenClawConfig,
        arguments: [String],
        standardInput: FileHandle? = nil,
        timeoutSeconds: TimeInterval? = nil
    ) throws -> (terminationStatus: Int32, standardOutput: Data, standardError: Data) {
        let plan = try buildClawHubCommandPlan(for: config, arguments: arguments)
        return try Self.executeProcessAndCaptureOutput(
            executableURL: plan.executableURL,
            arguments: plan.arguments,
            standardInput: standardInput,
            timeoutSeconds: timeoutSeconds
        )
    }

    func runDeploymentCommand(
        using config: OpenClawConfig,
        arguments: [String],
        standardInput: FileHandle? = nil,
        timeoutSeconds: TimeInterval? = nil
    ) throws -> (terminationStatus: Int32, standardOutput: Data, standardError: Data) {
        let plan = try buildDeploymentCommandPlan(for: config, arguments: arguments)
        return try Self.executeProcessAndCaptureOutput(
            executableURL: plan.executableURL,
            arguments: plan.arguments,
            standardInput: standardInput,
            timeoutSeconds: timeoutSeconds
        )
    }

    func runDeploymentShell(
        using config: OpenClawConfig,
        script: String,
        standardInput: FileHandle? = nil,
        timeoutSeconds: TimeInterval? = nil
    ) throws -> (terminationStatus: Int32, standardOutput: Data, standardError: Data) {
        let plan = try buildDeploymentShellPlan(for: config, script: script)
        return try Self.executeProcessAndCaptureOutput(
            executableURL: plan.executableURL,
            arguments: plan.arguments,
            standardInput: standardInput,
            timeoutSeconds: timeoutSeconds
        )
    }

    func resolveLocalOpenClawConfigURL(
        using config: OpenClawConfig,
        allowFallback: Bool = true
    ) -> URL? {
        guard config.deploymentKind == .local else { return nil }

        let fallbackURL = fallbackLocalOpenClawRootURL()
            .appendingPathComponent("openclaw.json", isDirectory: false)
        let binaryPath = resolveLocalBinaryPath(for: config)
        guard fileManager.fileExists(atPath: binaryPath) else {
            return allowFallback ? fallbackURL : nil
        }

        do {
            let result = try runOpenClawCommand(
                using: config,
                arguments: ["config", "file"],
                timeoutSeconds: TimeInterval(max(config.timeout, 5))
            )

            guard result.terminationStatus == 0 else {
                return allowFallback ? fallbackURL : nil
            }

            let output = String(
                data: result.standardOutput + result.standardError,
                encoding: .utf8
            ) ?? ""
            guard let resolvedPath = normalizeCLIReportedPath(output) else {
                return allowFallback ? fallbackURL : nil
            }

            return URL(fileURLWithPath: resolvedPath, isDirectory: false)
        } catch {
            return allowFallback ? fallbackURL : nil
        }
    }

    private func normalizeCLIReportedPath(_ output: String) -> String? {
        let lines = output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard let candidate = lines.last else { return nil }
        if candidate.hasPrefix("~/") {
            return homeDirectory
                .appendingPathComponent(String(candidate.dropFirst(2)), isDirectory: false)
                .path
        }
        return candidate
    }

    private func containerEngine(for config: OpenClawConfig) -> String {
        let trimmed = config.container.engine.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "docker" : trimmed
    }

    private func containerName(for config: OpenClawConfig) -> String? {
        let trimmed = config.container.containerName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
