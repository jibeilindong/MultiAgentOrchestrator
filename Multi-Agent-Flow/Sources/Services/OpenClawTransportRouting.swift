import Foundation

enum OpenClawTransportRouting {
    static func prefersGatewayChatTransport(
        sessionID: String?,
        outputMode: AgentOutputMode
    ) -> Bool {
        let normalizedSessionID = sessionID?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        guard !normalizedSessionID.isEmpty else { return false }

        if normalizedSessionID.hasPrefix("agent:") {
            return true
        }

        if normalizedSessionID.hasPrefix("workbench-") || normalizedSessionID.hasPrefix("benchmark-") {
            return true
        }

        switch outputMode {
        case .plainStreaming:
            return false
        case .structuredJSON:
            return false
        }
    }

    static func runtimeTransportKind(
        deploymentKind: OpenClawDeploymentKind,
        outputMode: AgentOutputMode,
        sessionID: String?
    ) -> OpenClawRuntimeTransportKind {
        switch deploymentKind {
        case .remoteServer:
            return prefersGatewayChatTransport(sessionID: sessionID, outputMode: outputMode)
                ? .gatewayChat
                : .gatewayAgent
        case .local, .container:
            return .cli
        }
    }

    static func expectedBenchmarkTransportKind(
        for transport: TransportBenchmarkKind
    ) -> OpenClawRuntimeTransportKind? {
        switch transport {
        case .gatewayChat:
            return .gatewayChat
        case .gatewayAgent, .workflowHotPath:
            return .gatewayAgent
        case .cli:
            return .cli
        }
    }

    static func summarizeTransportBenchmarkSamples(
        _ samples: [TransportBenchmarkSample]
    ) -> [TransportBenchmarkSummary] {
        Dictionary(grouping: samples, by: \.transport)
            .map { transport, groupedSamples in
                let successCount = groupedSamples.filter(\.success).count
                let failureCount = groupedSamples.count - successCount
                let actualTransportKinds = Array(
                    Set(
                        groupedSamples.compactMap(\.actualTransportKind)
                            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    )
                ).sorted()
                let expectedTransportKind = expectedBenchmarkTransportKind(for: transport)
                let matchedCount = groupedSamples.reduce(into: 0) { partial, sample in
                    guard let expectedTransportKind else { return }
                    if sample.actualTransportKind == expectedTransportKind.rawValue {
                        partial += 1
                    }
                }
                let mismatchCount = groupedSamples.reduce(into: 0) { partial, sample in
                    guard let expectedTransportKind else { return }
                    guard let actualTransportKind = sample.actualTransportKind,
                          !actualTransportKind.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        return
                    }
                    if actualTransportKind != expectedTransportKind.rawValue {
                        partial += 1
                    }
                }
                let firstChunkValues = groupedSamples.compactMap(\.firstChunkLatencyMs).map(Double.init)
                let completionValues = groupedSamples.compactMap(\.completionLatencyMs).map(Double.init)

                return TransportBenchmarkSummary(
                    transport: transport,
                    sampleCount: groupedSamples.count,
                    successCount: successCount,
                    failureCount: failureCount,
                    actualTransportKinds: actualTransportKinds,
                    expectedTransportKind: expectedTransportKind?.rawValue,
                    expectedTransportMatchedCount: matchedCount,
                    expectedTransportMismatchCount: mismatchCount,
                    averageFirstChunkLatencyMs: firstChunkValues.isEmpty
                        ? nil
                        : firstChunkValues.reduce(0, +) / Double(firstChunkValues.count),
                    averageCompletionLatencyMs: completionValues.isEmpty
                        ? nil
                        : completionValues.reduce(0, +) / Double(completionValues.count),
                    fastestCompletionLatencyMs: groupedSamples.compactMap(\.completionLatencyMs).min(),
                    slowestCompletionLatencyMs: groupedSamples.compactMap(\.completionLatencyMs).max()
                )
            }
            .sorted { $0.transport.displayName < $1.transport.displayName }
    }
}
