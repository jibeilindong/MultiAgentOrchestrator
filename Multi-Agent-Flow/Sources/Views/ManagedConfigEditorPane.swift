//
//  ManagedConfigEditorPane.swift
//  Multi-Agent-Flow
//

import SwiftUI

struct ManagedConfigEditorPane<Header: View>: View {
    let files: [ManagedAgentWorkspaceDocumentReference]
    @Binding var selectedRelativePath: String
    let selectedFilePath: String?
    let text: Binding<String>
    let onSelectRelativePath: (String) -> Void
    let editorFont: Font
    let minEditorHeight: CGFloat?
    let idealEditorHeight: CGFloat?
    let maxEditorHeight: CGFloat?

    private let header: Header
    private let showsHeader: Bool

    init(
        files: [ManagedAgentWorkspaceDocumentReference],
        selectedRelativePath: Binding<String>,
        selectedFilePath: String?,
        text: Binding<String>,
        onSelectRelativePath: @escaping (String) -> Void,
        editorFont: Font = .system(.body, design: .monospaced),
        minEditorHeight: CGFloat? = nil,
        idealEditorHeight: CGFloat? = nil,
        maxEditorHeight: CGFloat? = nil,
        @ViewBuilder header: () -> Header
    ) {
        self.files = files
        self._selectedRelativePath = selectedRelativePath
        self.selectedFilePath = selectedFilePath
        self.text = text
        self.onSelectRelativePath = onSelectRelativePath
        self.editorFont = editorFont
        self.minEditorHeight = minEditorHeight
        self.idealEditorHeight = idealEditorHeight
        self.maxEditorHeight = maxEditorHeight
        self.header = header()
        self.showsHeader = true
    }

    init(
        files: [ManagedAgentWorkspaceDocumentReference],
        selectedRelativePath: Binding<String>,
        selectedFilePath: String?,
        text: Binding<String>,
        onSelectRelativePath: @escaping (String) -> Void,
        editorFont: Font = .system(.body, design: .monospaced),
        minEditorHeight: CGFloat? = nil,
        idealEditorHeight: CGFloat? = nil,
        maxEditorHeight: CGFloat? = nil
    ) where Header == EmptyView {
        self.files = files
        self._selectedRelativePath = selectedRelativePath
        self.selectedFilePath = selectedFilePath
        self.text = text
        self.onSelectRelativePath = onSelectRelativePath
        self.editorFont = editorFont
        self.minEditorHeight = minEditorHeight
        self.idealEditorHeight = idealEditorHeight
        self.maxEditorHeight = maxEditorHeight
        self.header = EmptyView()
        self.showsHeader = false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsHeader {
                header
            }

            if files.isEmpty {
                Text(LocalizedString.text("managed_config_unavailable_for_unbound_agent"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                HStack(spacing: 12) {
                    Picker(LocalizedString.text("managed_config_file_label"), selection: $selectedRelativePath) {
                        ForEach(files) { file in
                            Text(file.relativePath).tag(file.relativePath)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: selectedRelativePath) { _, newValue in
                        onSelectRelativePath(newValue)
                    }

                    Spacer()
                }

                quickAccessView()

                if let selectedFilePath {
                    Text(selectedFilePath)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                }

                if let selectedFileSemanticHint {
                    Text(selectedFileSemanticHint)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text(LocalizedString.text("managed_config_edit_hint"))
                    .font(.caption)
                    .foregroundColor(.secondary)

                TextEditor(text: text)
                    .font(editorFont)
                    .frame(
                        minHeight: minEditorHeight,
                        idealHeight: idealEditorHeight,
                        maxHeight: maxEditorHeight
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
            }
        }
    }

    private var selectedFileSemanticHint: String? {
        switch selectedRelativePath {
        case "SOUL.md":
            return "`SOUL.md` 定义这个 agent 的角色、使命、流程与边界。"
        case "USER.md":
            return "`USER.md` 用来记录当前用户本人及其上下文，不再用于介绍模板用途。"
        case "IDENTITY.md":
            return "`IDENTITY.md` 记录 agent 自身身份、角色摘要与能力签名。"
        case "TOOLS.md":
            return "`TOOLS.md` 描述工具能力、运行说明与自检规则。"
        case "AGENTS.md":
            return "`AGENTS.md` 是系统物化的资产摘要与打包清单。"
        default:
            return nil
        }
    }

    private var quickAccessManagedConfigFiles: [ManagedAgentWorkspaceDocumentReference] {
        let priority = [
            "SOUL.md",
            "AGENTS.md",
            "IDENTITY.md",
            "USER.md",
            "TOOLS.md",
            "HEARTBEAT.md"
        ]
        let prioritized = priority.compactMap { target in
            files.first(where: { $0.relativePath == target })
        }
        if prioritized.count >= min(4, files.count) {
            return Array(prioritized.prefix(4))
        }

        let remaining = files.filter { file in
            prioritized.contains(where: { $0.relativePath == file.relativePath }) == false
        }
        return Array((prioritized + remaining).prefix(4))
    }

    @ViewBuilder
    private func quickAccessView() -> some View {
        if !quickAccessManagedConfigFiles.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(quickAccessManagedConfigFiles) { file in
                        quickAccessButton(for: file)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func quickAccessButton(for file: ManagedAgentWorkspaceDocumentReference) -> some View {
        if selectedRelativePath == file.relativePath {
            Button(file.fileName) {
                guard selectedRelativePath != file.relativePath else { return }
                selectedRelativePath = file.relativePath
                onSelectRelativePath(file.relativePath)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        } else {
            Button(file.fileName) {
                guard selectedRelativePath != file.relativePath else { return }
                selectedRelativePath = file.relativePath
                onSelectRelativePath(file.relativePath)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}
