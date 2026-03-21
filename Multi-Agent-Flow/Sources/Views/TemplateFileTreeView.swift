//
//  TemplateFileTreeView.swift
//  Multi-Agent-Flow
//
//  Created by Codex on 2026/3/22.
//

import SwiftUI

struct TemplateFileTreeView: View {
    let index: TemplateFileIndex
    let selectedPath: String?
    let onSelect: (TemplateFileNode) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(index.nodes) { node in
                    TemplateFileTreeNodeRow(
                        node: node,
                        depth: 0,
                        selectedPath: selectedPath,
                        onSelect: onSelect
                    )
                }
            }
            .padding(10)
        }
        .background(Color(.controlBackgroundColor).opacity(0.45))
    }
}

private struct TemplateFileTreeNodeRow: View {
    let node: TemplateFileNode
    let depth: Int
    let selectedPath: String?
    let onSelect: (TemplateFileNode) -> Void

    private var isSelected: Bool {
        selectedPath == node.relativePath
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                guard node.isDirectory == false else { return }
                onSelect(node)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: iconName(for: node))
                        .foregroundColor(iconColor(for: node))
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(node.displayName)
                            .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                            .foregroundColor(.primary)
                        Text(node.relativePath)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    if node.isDirty {
                        badge("草稿")
                    }
                    if node.isPresent == false {
                        badge("缺失", color: .orange)
                    } else if node.isEditable == false && node.isDirectory == false {
                        badge("只读", color: .secondary)
                    }
                }
                .padding(.leading, CGFloat(depth) * 14)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
                )
            }
            .buttonStyle(.plain)
            .disabled(node.isDirectory)

            ForEach(node.children) { child in
                TemplateFileTreeNodeRow(
                    node: child,
                    depth: depth + 1,
                    selectedPath: selectedPath,
                    onSelect: onSelect
                )
            }
        }
    }

    private func iconName(for node: TemplateFileNode) -> String {
        if node.isDirectory {
            return "folder"
        }

        switch node.kind {
        case .markdown:
            return "doc.text"
        case .json:
            return "curlybraces"
        case .other:
            return "doc"
        case .directory:
            return "folder"
        }
    }

    private func iconColor(for node: TemplateFileNode) -> Color {
        if node.isPresent == false {
            return .orange
        }

        switch node.category {
        case .soul:
            return .blue
        case .systemManaged:
            return .secondary
        case .revision:
            return .purple
        case .extensionSupport:
            return .green
        case .support:
            return .teal
        case .structure:
            return .indigo
        }
    }

    @ViewBuilder
    private func badge(_ text: String, color: Color = .accentColor) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}
