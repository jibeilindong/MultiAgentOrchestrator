//
//  ExecutionResultView.swift
//  Multi-Agent-Flow
//
//  Created by 陈荣泽 on 2026/3/18.
//

import SwiftUI

struct ExecutionResultView: View {
    @EnvironmentObject var appState: AppState
    let result: ExecutionResult
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: statusIcon)
                    .foregroundColor(statusColor)
                Text(LocalizedString.nodeExecution)
                    .font(.headline)
                Spacer()
                Text(statusText)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(statusColor.opacity(0.2)))
                    .foregroundColor(statusColor)
            }
            
            if let agent = getAgent() {
                Text("Agent: \(agent.name)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if hasRoutingDetails {
                routingDetailsView
            }

            if hasTransportDetails {
                transportDetailsView
            }

            if !result.runtimeEvents.isEmpty {
                runtimeEventsView
            }
            
            Divider()
            
            Text(result.renderedOutputText.isEmpty ? LocalizedString.text("no_output") : result.renderedOutputText)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(8)
                .background(Color(.controlBackgroundColor))
                .cornerRadius(6)
            
            HStack {
                Text("Started: \(result.startedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                if let completedAt = result.completedAt {
                    Text("Completed: \(completedAt.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                if let duration = result.duration {
                    Spacer()
                    Text("Duration: \(formatDuration(duration))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.windowBackgroundColor))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    private var statusIcon: String {
        switch result.status {
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .running: return "arrow.triangle.2.circlepath"
        case .idle: return "clock"
        case .waiting: return "hourglass"
        }
    }
    
    private var statusColor: Color {
        switch result.status {
        case .completed: return .green
        case .failed: return .red
        case .running: return .blue
        case .idle: return .gray
        case .waiting: return .orange
        }
    }
    
    private var statusText: String {
        result.status.rawValue
    }
    
    private func getAgent() -> Agent? {
        appState.currentProject?.agents.first { $0.id == result.agentID }
    }

    private var hasRoutingDetails: Bool {
        result.routingAction != nil || !result.routingTargets.isEmpty || result.routingReason != nil
    }

    private var hasTransportDetails: Bool {
        result.transportKind != nil
            || result.sessionID != nil
            || result.firstChunkLatencyMs != nil
            || result.completionLatencyMs != nil
    }

    private var routingDetailsView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Routing")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.orange)
                if let action = result.routingAction {
                    Text(routingActionLabel(action))
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(routingActionColor(action).opacity(0.16))
                        .foregroundColor(routingActionColor(action))
                        .clipShape(Capsule())
                }
            }

            if !result.routingTargets.isEmpty {
                Text("Targets: \(result.routingTargets.joined(separator: ", "))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if let reason = result.routingReason,
               !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Reason: \(reason)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(8)
        .background(Color.orange.opacity(0.08))
        .cornerRadius(8)
    }

    private var transportDetailsView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Transport")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.blue)

                if let transportKind = result.transportKind,
                   !transportKind.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(transportKindLabel(transportKind))
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.blue.opacity(0.16))
                        .foregroundColor(.blue)
                        .clipShape(Capsule())
                }
            }

            if let sessionID = result.sessionID,
               !sessionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Session: \(sessionID)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }

            if let firstChunkLatencyMs = result.firstChunkLatencyMs {
                Text("First Response: \(formatLatency(milliseconds: firstChunkLatencyMs))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if let completionLatencyMs = result.completionLatencyMs {
                Text("Completion: \(formatLatency(milliseconds: completionLatencyMs))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(8)
        .background(Color.blue.opacity(0.08))
        .cornerRadius(8)
    }

    private var runtimeEventsView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Protocol")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.purple)
                Text("\(result.runtimeEvents.count) event(s)")
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.purple.opacity(0.16))
                    .foregroundColor(.purple)
                    .clipShape(Capsule())
            }

            ForEach(Array(result.runtimeEvents.prefix(3))) { event in
                Text("\(event.eventType.rawValue) · \(event.timestamp.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(8)
        .background(Color.purple.opacity(0.08))
        .cornerRadius(8)
    }

    private func routingActionLabel(_ action: String) -> String {
        switch action.lowercased() {
        case "stop": return "Stop"
        case "selected": return "Selected"
        case "all": return "All"
        default: return action
        }
    }

    private func routingActionColor(_ action: String) -> Color {
        switch action.lowercased() {
        case "stop": return .orange
        case "selected": return .blue
        case "all": return .purple
        default: return .secondary
        }
    }

    private func transportKindLabel(_ value: String) -> String {
        switch value.lowercased() {
        case "gateway_chat": return "Gateway Chat"
        case "gateway_agent": return "Gateway Agent"
        case "cli": return "CLI"
        default: return value
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        if duration < 1 {
            return String(format: "%.0fms", duration * 1000)
        } else if duration < 60 {
            return String(format: "%.1fs", duration)
        } else {
            let minutes = Int(duration / 60)
            let seconds = Int(duration.truncatingRemainder(dividingBy: 60))
            return "\(minutes)m \(seconds)s"
        }
    }

    private func formatLatency(milliseconds: Int) -> String {
        if milliseconds >= 1000 {
            return String(format: "%.1fs", Double(milliseconds) / 1000.0)
        }
        return "\(milliseconds)ms"
    }
}
