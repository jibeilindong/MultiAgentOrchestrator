//
//  WorkflowEditorInlineStatusView.swift
//  Multi-Agent-Flow
//

import SwiftUI

struct WorkflowEditorInlineStatusView: View {
    let message: String
    let isError: Bool
    let pendingApplyCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: isError ? "xmark.octagon.fill" : "checkmark.circle.fill")
                Text(message)
            }
            .foregroundColor(isError ? .red : .green)

            if !isError, pendingApplyCount > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "clock.badge.exclamationmark")
                    Text(LocalizedString.format("workflow_apply_pending_count", pendingApplyCount))
                }
                .foregroundColor(.orange)
            }
        }
        .font(.caption)
    }
}
