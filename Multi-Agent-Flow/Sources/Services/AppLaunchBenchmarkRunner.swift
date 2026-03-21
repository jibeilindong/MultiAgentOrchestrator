import Foundation
import AppKit
import Combine

struct AppLaunchBenchmarkOptions {
    let iterations: Int
    let prompt: String?
    let timeoutSeconds: TimeInterval

    static func parse(arguments: [String]) -> AppLaunchBenchmarkOptions? {
        guard arguments.contains("--run-transport-benchmark") else { return nil }

        func value(after flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
                return nil
            }
            return arguments[index + 1]
        }

        let iterations = max(1, Int(value(after: "--benchmark-iterations") ?? "") ?? 3)
        let prompt = value(after: "--benchmark-prompt")?.trimmingCharacters(in: .whitespacesAndNewlines)
        let timeoutSeconds = max(10, TimeInterval(value(after: "--benchmark-timeout") ?? "") ?? 180)

        return AppLaunchBenchmarkOptions(
            iterations: iterations,
            prompt: prompt?.isEmpty == true ? nil : prompt,
            timeoutSeconds: timeoutSeconds
        )
    }
}

@MainActor
final class AppLaunchBenchmarkRunner: ObservableObject {
    private var errorObserver: AnyCancellable?
    private var didFinish = false

    func runIfRequested(appState: AppState) {
        guard let options = AppLaunchBenchmarkOptions.parse(arguments: ProcessInfo.processInfo.arguments) else {
            return
        }

        print("Transport benchmark launch mode enabled.")
        print("Iterations: \(options.iterations)")
        if let prompt = options.prompt {
            print("Prompt: \(prompt)")
        }
        print("Timeout: \(Int(options.timeoutSeconds))s")

        errorObserver = appState.openClawService.$transportBenchmarkError
            .receive(on: RunLoop.main)
            .sink { [weak self] error in
                guard let self, let error, !error.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return
                }
                self.finish(status: 1, appState: appState, message: "Benchmark error: \(error)")
            }

        DispatchQueue.main.asyncAfter(deadline: .now() + options.timeoutSeconds) { [weak self] in
            guard let self, !self.didFinish else { return }
            self.finish(
                status: 2,
                appState: appState,
                message: "Benchmark timed out after \(Int(options.timeoutSeconds)) seconds."
            )
        }

        appState.openClawService.runTransportBenchmark(
            prompt: options.prompt,
            iterationsPerTransport: options.iterations
        ) { [weak self] report in
            guard let self else { return }
            self.finish(
                status: 0,
                appState: appState,
                message: self.reportSummaryText(report)
            )
        }
    }

    private func reportSummaryText(_ report: TransportBenchmarkReport) -> String {
        var lines: [String] = []
        lines.append("Transport benchmark completed.")
        if let reportFilePath = report.reportFilePath {
            lines.append("Report: \(reportFilePath)")
        }

        if let workflowSummary = report.summaries.first(where: { $0.transport == .workflowHotPath }) {
            let observed = workflowSummary.actualTransportKinds.isEmpty
                ? "none"
                : workflowSummary.actualTransportKinds.joined(separator: ", ")
            lines.append("Workflow Hot Path expected: \(workflowSummary.expectedTransportKind ?? "unknown")")
            lines.append("Workflow Hot Path observed: \(observed)")
            lines.append(
                "Workflow Hot Path matched: \(workflowSummary.expectedTransportMatchedCount)/\(workflowSummary.sampleCount)"
            )
            lines.append(
                "Workflow Hot Path mismatch: \(workflowSummary.expectedTransportMismatchCount)/\(workflowSummary.sampleCount)"
            )
            if let avg = workflowSummary.averageCompletionLatencyMs {
                lines.append("Workflow Hot Path avg completion: \(Int(avg.rounded()))ms")
            }
        }

        return lines.joined(separator: "\n")
    }

    private func finish(status: Int32, appState: AppState, message: String) {
        guard !didFinish else { return }
        didFinish = true
        errorObserver = nil
        print(message)
        fflush(stdout)
        fflush(stderr)
        appState.shutdown()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApplication.shared.terminate(nil)
            exit(status)
        }
    }
}
