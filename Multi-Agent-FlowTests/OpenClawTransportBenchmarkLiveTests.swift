import XCTest
import Combine
@testable import Multi_Agent_Flow

final class OpenClawTransportBenchmarkLiveTests: XCTestCase {
    private enum LiveBenchmarkDefaultsKey {
        static let enabled = "OPENCLAW_BENCHMARK_LIVE"
        static let iterations = "OPENCLAW_BENCHMARK_ITERATIONS"
        static let timeout = "OPENCLAW_BENCHMARK_TIMEOUT"
    }

    private var cancellables = Set<AnyCancellable>()

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }

    func testWorkflowHotPathLiveBenchmarkReportPrefersGatewayAgent() throws {
        try requireLiveBenchmarkEnabled()

        let config = try loadLiveBenchmarkConfig()
        guard OpenClawManager.shared.preferredGatewayConfig(using: config) != nil else {
            throw XCTSkip("当前 OpenClaw 配置未启用 gateway，无法验证 workflow_hot_path 是否命中 gateway_agent。")
        }

        let manager = OpenClawManager.shared
        let previousConfig = manager.config
        let previousStoredConfig = UserDefaults.standard.data(forKey: OpenClawConfig.storageKey)

        defer {
            manager.resetGatewayConnection()
            manager.config = previousConfig
            if let previousStoredConfig {
                UserDefaults.standard.set(previousStoredConfig, forKey: OpenClawConfig.storageKey)
            } else {
                UserDefaults.standard.removeObject(forKey: OpenClawConfig.storageKey)
            }
        }

        manager.resetGatewayConnection()
        manager.config = config
        UserDefaults.standard.set(try JSONEncoder().encode(config), forKey: OpenClawConfig.storageKey)

        let service = OpenClawService()
        let iterations = liveBenchmarkIterations
        let timeoutSeconds = liveBenchmarkTimeoutSeconds
        let expectation = expectation(description: "transport benchmark completed")
        let finishLock = NSLock()
        var hasFinished = false
        var report: TransportBenchmarkReport?
        var benchmarkError: String?

        func finishOnce() {
            finishLock.lock()
            defer { finishLock.unlock() }
            guard !hasFinished else { return }
            hasFinished = true
            expectation.fulfill()
        }

        service.$transportBenchmarkError
            .dropFirst()
            .sink { error in
                guard let error,
                      !error.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return
                }
                benchmarkError = error
                finishOnce()
            }
            .store(in: &cancellables)

        service.runTransportBenchmark(
            prompt: "Reply with one short sentence about benchmark routing.",
            iterationsPerTransport: iterations
        ) { completedReport in
            report = completedReport
            finishOnce()
        }

        wait(for: [expectation], timeout: timeoutSeconds)

        XCTAssertNil(benchmarkError, benchmarkError ?? "transport benchmark failed")

        let completedReport = try XCTUnwrap(report, "未收到 transport benchmark 报告。")
        let workflowSummary = try XCTUnwrap(
            completedReport.summaries.first(where: { $0.transport == .workflowHotPath }),
            "benchmark 报告缺少 workflow_hot_path summary。"
        )

        XCTAssertEqual(workflowSummary.expectedTransportKind, "gateway_agent")
        XCTAssertGreaterThan(workflowSummary.sampleCount, 0)
        XCTAssertGreaterThan(workflowSummary.expectedTransportMatchedCount, 0)
        XCTAssertEqual(workflowSummary.expectedTransportMismatchCount, 0)
        XCTAssertTrue(workflowSummary.actualTransportKinds.contains("gateway_agent"))

        let reportFilePath = try XCTUnwrap(completedReport.reportFilePath, "benchmark 报告未落盘。")
        XCTAssertTrue(FileManager.default.fileExists(atPath: reportFilePath))

        for summary in completedReport.summaries.sorted(by: { $0.transport.displayName < $1.transport.displayName }) {
            let observed = summary.actualTransportKinds.isEmpty ? "none" : summary.actualTransportKinds.joined(separator: ",")
            let avgCompletion = summary.averageCompletionLatencyMs.map { String(format: "%.1f", $0) } ?? "n/a"
            print(
                "LIVE_BENCHMARK transport=\(summary.transport.rawValue) matched=\(summary.expectedTransportMatchedCount)/\(summary.sampleCount) mismatch=\(summary.expectedTransportMismatchCount)/\(summary.sampleCount) avg_completion_ms=\(avgCompletion) observed=\(observed)"
            )
        }

        print("LIVE_BENCHMARK_REPORT \(reportFilePath)")
    }

    private func requireLiveBenchmarkEnabled() throws {
        let environment = ProcessInfo.processInfo.environment
        let enabledFromEnvironment = environment[LiveBenchmarkDefaultsKey.enabled] == "1"
        let enabledFromDefaults = UserDefaults.standard.bool(forKey: LiveBenchmarkDefaultsKey.enabled)
        let enabledFromAppSuite = UserDefaults(suiteName: "Roney.MultiAgentFlow")?
            .bool(forKey: LiveBenchmarkDefaultsKey.enabled) ?? false
        let enabledFromTestSuite = UserDefaults(suiteName: "Roney.MultiAgentFlowTests")?
            .bool(forKey: LiveBenchmarkDefaultsKey.enabled) ?? false
        guard enabledFromEnvironment || enabledFromDefaults || enabledFromAppSuite || enabledFromTestSuite else {
            throw XCTSkip("设置 OPENCLAW_BENCHMARK_LIVE=1 后才会执行真实 transport benchmark。")
        }
    }

    private func loadLiveBenchmarkConfig() throws -> OpenClawConfig {
        if let suiteDefaults = UserDefaults(suiteName: "Roney.MultiAgentFlow"),
           let data = suiteDefaults.data(forKey: OpenClawConfig.storageKey),
           let config = try? JSONDecoder().decode(OpenClawConfig.self, from: data) {
            return config
        }

        let fallback = OpenClawConfig.load()
        return fallback
    }

    private var liveBenchmarkIterations: Int {
        let environment = ProcessInfo.processInfo.environment
        let rawValue = environment[LiveBenchmarkDefaultsKey.iterations] ?? ""
        if let value = Int(rawValue) {
            return max(1, value)
        }

        let defaultValue = UserDefaults.standard.integer(forKey: LiveBenchmarkDefaultsKey.iterations)
        if defaultValue != 0 {
            return max(1, defaultValue)
        }

        let appSuiteValue = UserDefaults(suiteName: "Roney.MultiAgentFlow")?
            .integer(forKey: LiveBenchmarkDefaultsKey.iterations) ?? 0
        if appSuiteValue != 0 {
            return max(1, appSuiteValue)
        }

        let testSuiteValue = UserDefaults(suiteName: "Roney.MultiAgentFlowTests")?
            .integer(forKey: LiveBenchmarkDefaultsKey.iterations) ?? 0
        return max(1, testSuiteValue == 0 ? 1 : testSuiteValue)
    }

    private var liveBenchmarkTimeoutSeconds: TimeInterval {
        let environment = ProcessInfo.processInfo.environment
        let rawValue = environment[LiveBenchmarkDefaultsKey.timeout] ?? ""
        if let value = TimeInterval(rawValue) {
            return max(30, value)
        }

        let defaultValue = UserDefaults.standard.double(forKey: LiveBenchmarkDefaultsKey.timeout)
        if defaultValue != 0 {
            return max(30, defaultValue)
        }

        let appSuiteValue = UserDefaults(suiteName: "Roney.MultiAgentFlow")?
            .double(forKey: LiveBenchmarkDefaultsKey.timeout) ?? 0
        if appSuiteValue != 0 {
            return max(30, appSuiteValue)
        }

        let testSuiteValue = UserDefaults(suiteName: "Roney.MultiAgentFlowTests")?
            .double(forKey: LiveBenchmarkDefaultsKey.timeout) ?? 0
        return max(30, testSuiteValue == 0 ? 240 : testSuiteValue)
    }
}
