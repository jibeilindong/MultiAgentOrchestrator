//
//  TemplateWorkspaceView.swift
//  Multi-Agent-Flow
//
//  Created by Codex on 2026/3/22.
//

import SwiftUI

private enum TemplateWorkspaceTab: String, CaseIterable, Identifiable {
    case overview = "总览"
    case files = "文件"
    case validation = "校验"
    case versions = "版本"
    case transfer = "导入导出"

    var id: String { rawValue }
}

struct TemplateWorkspaceView: View {
    let template: AgentTemplate
    var onFeedback: (String) -> Void = { _ in }

    @ObservedObject private var templateLibrary = AgentTemplateLibraryStore.shared

    @State private var selectedTab: TemplateWorkspaceTab = .files
    @State private var selectedFilePath: String?
    @State private var editorText: String = ""
    @State private var loadedFilePath: String?
    @State private var isEditorDirty: Bool = false
    @State private var fileErrorMessage: String?

    private var draftSession: TemplateDraftSession? {
        templateLibrary.draftSession(for: template.id)
    }

    private var fileIndex: TemplateFileIndex? {
        templateLibrary.templateFileIndex(for: template.id, prefersDraft: true)
    }

    private var selectedNode: TemplateFileNode? {
        guard let selectedFilePath else { return nil }
        return fileIndex?.node(relativePath: selectedFilePath)
    }

    private var revisionNodes: [TemplateFileNode] {
        fileIndex?.node(relativePath: "revisions")?.children ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("模板文件工作区（草稿）")
                        .font(.headline)
                    Text("这里直接查看和编辑标准模板资产文件；所有修改先写入草稿目录，不会直接污染正式模板资产。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if let draftSession {
                    Text(draftStatusText(session: draftSession))
                        .font(.caption.weight(.semibold))
                        .foregroundColor(draftSession.hasUnsavedChanges ? .orange : .secondary)
                }
                Button("放弃草稿") {
                    discardDraftSession()
                }
                .buttonStyle(.bordered)
                .disabled(draftSession == nil)
            }

            Picker("", selection: $selectedTab) {
                ForEach(TemplateWorkspaceTab.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)

            Group {
                switch selectedTab {
                case .overview:
                    overviewPane
                case .files:
                    filesPane
                case .validation:
                    validationPane
                case .versions:
                    versionsPane
                case .transfer:
                    transferPane
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .onAppear {
            bootstrapWorkspace()
        }
        .onChange(of: template.id) { _, _ in
            resetWorkspaceState()
            bootstrapWorkspace()
        }
        .onChange(of: selectedFilePath) { _, newValue in
            guard let newValue else { return }
            templateLibrary.selectDraftFile(newValue, for: template.id)
            loadFile(relativePath: newValue)
        }
    }

    @ViewBuilder
    private var overviewPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            infoCard(
                title: "模板身份",
                rows: [
                    ("模板名称", template.name),
                    ("模板 ID", template.id),
                    ("identity", template.identity),
                    ("分类", template.taxonomyPath)
                ]
            )

            infoCard(
                title: "草稿状态",
                rows: [
                    ("草稿目录", draftSession?.draftRootURL.path ?? "尚未创建"),
                    ("正式目录", templateLibrary.templateAssetDirectoryURL(for: template.id)?.path ?? "当前模板没有本地目录"),
                    ("当前文件", draftSession?.selectedFilePath ?? "SOUL.md"),
                    ("脏文件数", "\(draftSession?.dirtyFilePaths.count ?? 0)")
                ]
            )

            if let fileIndex {
                let totalFiles = fileIndex.flattenedNodes.filter { $0.isDirectory == false }.count
                let missingFiles = fileIndex.flattenedNodes.filter { $0.isDirectory == false && $0.isPresent == false }.count
                let readonlyFiles = fileIndex.flattenedNodes.filter { $0.isDirectory == false && $0.isEditable == false }.count
                let dirtyFiles = fileIndex.flattenedNodes.filter(\.isDirty).count

                infoCard(
                    title: "标准文件完整性",
                    rows: [
                        ("标准文件总数", "\(totalFiles)"),
                        ("缺失文件", "\(missingFiles)"),
                        ("只读文件", "\(readonlyFiles)"),
                        ("草稿修改", "\(dirtyFiles)")
                    ]
                )
            }
        }
    }

    @ViewBuilder
    private var filesPane: some View {
        if let fileIndex {
            HStack(spacing: 0) {
                TemplateFileTreeView(
                    index: fileIndex,
                    selectedPath: selectedFilePath,
                    onSelect: { node in
                        selectedFilePath = node.relativePath
                    }
                )
                .frame(width: 300)

                Divider()

                fileEditorPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                inspectorPane
                    .frame(width: 260)
            }
            .frame(minHeight: 420)
            .background(Color.primary.opacity(0.02))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            emptyState(
                title: "模板文件索引尚未就绪",
                detail: "打开模板时会先创建草稿目录，然后根据标准模板结构生成文件树。"
            )
        }
    }

    @ViewBuilder
    private var fileEditorPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let node = selectedNode {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(node.displayName)
                            .font(.headline)
                        Text(node.relativePath)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if node.isDirty {
                        statusBadge("草稿中", color: .orange)
                    }
                    if node.isPresent == false {
                        statusBadge("缺失", color: .orange)
                    } else if node.isEditable == false {
                        statusBadge("只读", color: .secondary)
                    }
                }

                if let fileErrorMessage {
                    Text(fileErrorMessage)
                        .font(.caption)
                        .foregroundColor(.orange)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                if node.isPresent == false {
                    emptyState(
                        title: "文件当前缺失",
                        detail: node.isEditable
                            ? "可以从标准模板 scaffold 补齐这个文件，或者继续查看其他标准文件。"
                            : "这是系统维护或只读文件，当前草稿里尚不存在该文件。"
                    )
                } else if node.isEditable {
                    TextEditor(text: Binding(
                        get: { editorText },
                        set: {
                            editorText = $0
                            isEditorDirty = true
                        }
                    ))
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.gray.opacity(0.25), lineWidth: 1)
                    )
                } else {
                    ScrollView {
                        Text(editorText)
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .padding(10)
                    .background(Color(.textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                HStack {
                    Button("重新载入") {
                        loadSelectedFile()
                    }
                    .buttonStyle(.bordered)

                    if node.isEditable {
                        Button("从正式资产恢复") {
                            restoreCurrentFile()
                        }
                        .buttonStyle(.bordered)

                        Button("写入草稿") {
                            saveCurrentFile()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isEditorDirty == false || loadedFilePath != node.relativePath)
                    }

                    if node.isEditable && node.isPresent == false {
                        Button("补齐标准文件") {
                            scaffoldCurrentFile()
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    Spacer()

                    if node.isEditable && isEditorDirty {
                        Text("尚未写入草稿")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            } else {
                emptyState(
                    title: "请选择一个模板文件",
                    detail: "左侧会按照标准模板文件系统展示 `template.json`、`SOUL.md`、支持文件和扩展目录。"
                )
            }
        }
        .padding()
    }

    @ViewBuilder
    private var inspectorPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("文件检查器")
                .font(.headline)

            if let node = selectedNode {
                infoCard(
                    title: "当前文件",
                    rows: [
                        ("路径", node.relativePath),
                        ("分类", node.category.rawValue),
                        ("类型", node.kind.rawValue),
                        ("必需", node.isRequired ? "是" : "否"),
                        ("可编辑", node.isEditable ? "是" : "否"),
                        ("系统维护", node.isSystemManaged ? "是" : "否"),
                        ("存在", node.isPresent ? "是" : "否")
                    ]
                )
            } else {
                Text("选择文件后可查看其标准属性、可编辑状态和草稿状态。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let session = draftSession {
                infoCard(
                    title: "会话信息",
                    rows: [
                        ("打开时间", session.openedAt.formatted(date: .abbreviated, time: .shortened)),
                        ("草稿目录", session.draftRootURL.lastPathComponent),
                        ("脏文件", session.dirtyFilePaths.isEmpty ? "无" : session.dirtyFilePaths.joined(separator: "\n"))
                    ]
                )
            }

            Spacer()
        }
        .padding()
        .background(Color(.controlBackgroundColor).opacity(0.3))
    }

    @ViewBuilder
    private var validationPane: some View {
        if template.validationIssues.isEmpty {
            emptyState(
                title: "当前模板通过已有校验",
                detail: "这里展示的是模板对象级校验结果；后续阶段会把草稿文件级校验和 `SOUL.md` 解析错误并入这个页签。"
            )
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(template.validationIssues) { issue in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("[\(issue.severity.rawValue.uppercased())] \(issue.field)")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(issue.severity == .error ? .red : .orange)
                            Text(issue.message)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder
    private var versionsPane: some View {
        if revisionNodes.isEmpty {
            emptyState(
                title: "当前还没有可展示的 revision",
                detail: "后续发布流会把每次正式保存后的模板快照写入 `revisions/`。"
            )
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(revisionNodes) { node in
                    HStack {
                        Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                            .foregroundColor(.purple)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(node.displayName)
                                .font(.subheadline.weight(.semibold))
                            Text(node.relativePath)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button("查看") {
                            selectedTab = .files
                            selectedFilePath = node.relativePath
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
    }

    @ViewBuilder
    private var transferPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            infoCard(
                title: "当前接入状态",
                rows: [
                    ("模板资产导入预检", "已在模板库管理页接入"),
                    ("模板资产目录导出", "已在模板库管理页接入"),
                    ("JSON 交换导入导出", "已在模板库管理页接入"),
                    ("SOUL.md 导入导出", "已在模板库管理页接入")
                ]
            )

            Text("这一页签先承担状态说明，后续会把导入预检、冲突提示和目录级导出动作进一步迁入统一工作区。")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func bootstrapWorkspace() {
        do {
            let session = try templateLibrary.openDraftSession(for: template.id)
            let initialPath = session.selectedFilePath
                ?? selectedFilePath
                ?? preferredInitialFilePath(from: fileIndex)
            selectedFilePath = initialPath
            if let initialPath {
                loadFile(relativePath: initialPath)
            }
        } catch {
            fileErrorMessage = error.localizedDescription
            onFeedback("模板草稿工作区打开失败：\(error.localizedDescription)")
        }
    }

    private func resetWorkspaceState() {
        selectedFilePath = nil
        editorText = ""
        loadedFilePath = nil
        isEditorDirty = false
        fileErrorMessage = nil
    }

    private func preferredInitialFilePath(from index: TemplateFileIndex?) -> String? {
        if let sessionPath = draftSession?.selectedFilePath {
            return sessionPath
        }

        if index?.node(relativePath: "SOUL.md") != nil {
            return "SOUL.md"
        }

        return index?.flattenedNodes.first(where: { $0.isDirectory == false })?.relativePath
    }

    private func loadSelectedFile() {
        guard let selectedFilePath else { return }
        loadFile(relativePath: selectedFilePath)
    }

    private func loadFile(relativePath: String) {
        guard let node = fileIndex?.node(relativePath: relativePath) else { return }

        fileErrorMessage = nil
        loadedFilePath = relativePath
        isEditorDirty = false

        guard node.isDirectory == false else {
            editorText = ""
            return
        }

        guard node.isPresent else {
            editorText = ""
            return
        }

        do {
            editorText = try templateLibrary.templateFileContents(
                for: template.id,
                relativePath: relativePath,
                prefersDraft: true
            )
        } catch {
            editorText = ""
            fileErrorMessage = error.localizedDescription
        }
    }

    private func saveCurrentFile() {
        guard let selectedNode,
              let selectedFilePath,
              selectedNode.isEditable else { return }

        do {
            _ = try templateLibrary.updateDraftFile(
                for: template.id,
                relativePath: selectedFilePath,
                contents: editorText
            )
            loadedFilePath = selectedFilePath
            isEditorDirty = false
            onFeedback("已写入模板草稿文件：\(selectedNode.displayName)")
        } catch {
            fileErrorMessage = error.localizedDescription
            onFeedback("模板草稿写入失败：\(error.localizedDescription)")
        }
    }

    private func restoreCurrentFile() {
        guard let selectedFilePath else { return }

        do {
            _ = try templateLibrary.restoreDraftFile(
                for: template.id,
                relativePath: selectedFilePath
            )
            loadFile(relativePath: selectedFilePath)
            onFeedback("已从正式模板资产恢复：\(selectedFilePath)")
        } catch {
            fileErrorMessage = error.localizedDescription
            onFeedback("恢复模板文件失败：\(error.localizedDescription)")
        }
    }

    private func scaffoldCurrentFile() {
        guard let selectedFilePath else { return }

        do {
            _ = try templateLibrary.scaffoldDraftFile(
                for: template.id,
                relativePath: selectedFilePath
            )
            loadFile(relativePath: selectedFilePath)
            onFeedback("已补齐标准模板文件：\(selectedFilePath)")
        } catch {
            fileErrorMessage = error.localizedDescription
            onFeedback("补齐模板文件失败：\(error.localizedDescription)")
        }
    }

    private func discardDraftSession() {
        do {
            try templateLibrary.discardDraftSession(for: template.id)
            resetWorkspaceState()
            bootstrapWorkspace()
            onFeedback("已放弃当前模板草稿，并从正式资产重新创建工作副本。")
        } catch {
            fileErrorMessage = error.localizedDescription
            onFeedback("放弃模板草稿失败：\(error.localizedDescription)")
        }
    }

    private func draftStatusText(session: TemplateDraftSession) -> String {
        if session.hasUnsavedChanges {
            return "草稿中有 \(session.dirtyFilePaths.count) 个文件变更"
        }
        return "草稿目录已就绪"
    }

    @ViewBuilder
    private func infoCard(title: String, rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))

            ForEach(Array(rows.enumerated()), id: \.offset) { item in
                let row = item.element
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.0)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(row.1)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private func emptyState(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(detail)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private func statusBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}
