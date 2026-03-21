//
//  WorkflowEditorDirtyBadgeView.swift
//  Multi-Agent-Flow
//

import SwiftUI

struct WorkflowEditorDirtyBadgeView: View {
    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Color.orange)
                .frame(width: 6, height: 6)
            Text(LocalizedString.text("unsaved_changes_badge"))
                .font(.system(size: 11.5, weight: .medium))
        }
        .foregroundColor(.orange)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            Capsule(style: .continuous)
                .fill(Color.orange.opacity(0.12))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.orange.opacity(0.18), lineWidth: 1)
        )
    }
}
