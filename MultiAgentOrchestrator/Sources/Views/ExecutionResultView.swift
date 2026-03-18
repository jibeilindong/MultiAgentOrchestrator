//
//  ExecutionResultView.swift
//  MultiAgentOrchestrator
//
//  Created by 陈荣泽 on 2026/3/18.
//

import SwiftUI

struct ExecutionResultView: View {
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
            
            Divider()
            
            Text(result.output)
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
        // 在实际应用中，这里应该通过AppState获取Agent
        return nil
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
}
