//
//  TemplateWorkspaceView.swift
//  Multi-Agent-Flow
//
//  Created by Codex on 2026/3/22.
//

import SwiftUI
import UniformTypeIdentifiers

private enum TemplateWorkspaceTab: String, CaseIterable, Identifiable {
    case overview = "总览"
    case files = "文件"
    case validation = "校验"
    case versions = "版本"
    case transfer = "导入导出"

    var id: String { rawValue }
}

private enum TemplateWorkspaceFileEditorMode: String, CaseIterable, Identifiable {
    case structured = "结构化"
    case raw = "原文"

    var id: String { rawValue }
}

struct TemplateWorkspaceView: View {
    let template: AgentTemplate
    var onFeedback: (String) -> Void = { _ in }
    var onPersisted: (AgentTemplate) -> Void = { _ in }
    var onDeleted: (String) -> Void = { _ in }

    @ObservedObject private var templateLibrary = AgentTemplateLibraryStore.shared

    @State private var selectedTab: TemplateWorkspaceTab = .files
    @State private var selectedFilePath: String?
    @State private var editorText: String = ""
    @State private var loadedFilePath: String?
    @State private var isEditorDirty: Bool = false
    @State private var fileErrorMessage: String?
    @State private var validationState: TemplateValidationState?
    @State private var revisionHistory: [TemplateAssetDocument] = []
    @State private var soulEditorMode: TemplateWorkspaceFileEditorMode = .structured
    @State private var documentEditorMode: TemplateWorkspaceFileEditorMode = .structured
    @State private var soulDraft: TemplateWorkspaceSoulDraft?
    @State private var documentDraft: TemplateWorkspaceDocumentDraft?
    @State private var isHydratingStructuredDraft = false
    @State private var importPreviewReport: TemplateAssetImportPreviewReport?
    @State private var soulStructuredErrorMessage: String?
    @State private var documentStructuredErrorMessage: String?
    @State private var showingDeleteTemplateAlert = false

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

    private var saveButtonDisabled: Bool {
        draftSession == nil || (draftSession?.hasUnsavedChanges == false && isEditorDirty == false) || hasBlockingPersistenceIssue
    }

    private var markdownContentType: UTType {
        UTType(filenameExtension: "md") ?? .plainText
    }

    private var currentStructuredErrorMessage: String? {
        switch selectedFilePath {
        case "SOUL.md":
            return soulStructuredErrorMessage
        case "template.json":
            return documentStructuredErrorMessage
        default:
            return nil
        }
    }

    private var currentEditorBlockingIssueMessage: String? {
        guard isEditorDirty, let selectedFilePath else { return nil }

        switch selectedFilePath {
        case "SOUL.md":
            do {
                _ = try AgentTemplateSoulMarkdownParser.parse(editorText)
                return nil
            } catch {
                return "SOUL.md 当前原文存在结构错误：\(error.localizedDescription)。保存前请先修复。"
            }
        case "template.json":
            do {
                _ = try TemplateWorkspaceDocumentDraft(json: editorText)
                return nil
            } catch {
                return "template.json 当前原文存在 JSON 错误：\(error.localizedDescription)。保存前请先修复。"
            }
        default:
            return nil
        }
    }

    private var hasBlockingPersistenceIssue: Bool {
        if currentStructuredErrorMessage != nil || currentEditorBlockingIssueMessage != nil {
            return true
        }

        let blockingFields = Set(["SOUL.md", "template.json"])
        return validationState?.issues.contains(where: { issue in
            issue.severity == .error && blockingFields.contains(issue.field)
        }) ?? false
    }

    private var saveGateMessage: String? {
        if let currentEditorBlockingIssueMessage {
            return currentEditorBlockingIssueMessage
        }

        if let currentStructuredErrorMessage {
            return currentStructuredErrorMessage
        }

        if let issue = validationState?.issues.first(where: { issue in
            issue.severity == .error && (issue.field == "SOUL.md" || issue.field == "template.json")
        }) {
            return issue.message
        }

        if let validationState, validationState.hasErrors {
            return "当前草稿仍有 \(validationState.issues.filter { $0.severity == .error }.count) 个错误；其中语义类错误允许保存为 draft 状态，但 `SOUL.md` / `template.json` 解析错误会阻断保存。"
        }

        return nil
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
                Button("保存到模板资产") {
                    persistWorkspaceDraft()
                }
                .buttonStyle(.borderedProminent)
                .disabled(saveButtonDisabled)
                Button("放弃草稿") {
                    discardDraftSession()
                }
                .buttonStyle(.bordered)
                .disabled(draftSession == nil)
            }

            if let saveGateMessage {
                Text(saveGateMessage)
                    .font(.caption)
                    .foregroundColor(hasBlockingPersistenceIssue ? .orange : .secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background((hasBlockingPersistenceIssue ? Color.orange : Color.primary).opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
        .sheet(item: $importPreviewReport) { report in
            TemplateWorkspaceImportPreviewSheet(
                report: report,
                onConfirm: {
                    performTemplateAssetImport(report)
                }
            )
        }
        .alert("删除模板资产", isPresented: $showingDeleteTemplateAlert) {
            Button("删除", role: .destructive) {
                deleteCurrentTemplate()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后会移除“\(template.name)”的模板资产目录、草稿目录和相关收藏/最近使用记录，此操作不可撤销。")
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
        .onChange(of: soulEditorMode) { _, newValue in
            guard newValue == .structured, selectedFilePath == "SOUL.md" else { return }
            hydrateStructuredDrafts(for: "SOUL.md", contents: editorText)
        }
        .onChange(of: documentEditorMode) { _, newValue in
            guard newValue == .structured, selectedFilePath == "template.json" else { return }
            hydrateStructuredDrafts(for: "template.json", contents: editorText)
        }
        .onChange(of: soulDraft) { _, newValue in
            guard let newValue, isHydratingStructuredDraft == false, selectedFilePath == "SOUL.md", soulEditorMode == .structured else {
                return
            }
            editorText = newValue.renderedMarkdown
            isEditorDirty = true
        }
        .onChange(of: documentDraft) { _, newValue in
            guard let newValue, isHydratingStructuredDraft == false, selectedFilePath == "template.json", documentEditorMode == .structured else {
                return
            }

            do {
                editorText = try newValue.renderedJSON
                isEditorDirty = true
                fileErrorMessage = nil
            } catch {
                fileErrorMessage = error.localizedDescription
            }
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

            infoCard(
                title: "当前校验摘要",
                rows: [
                    ("校验时间", validationState?.validatedAt.formatted(date: .abbreviated, time: .shortened) ?? "尚未执行"),
                    ("错误数", "\(validationState?.issues.filter { $0.severity == .error }.count ?? 0)"),
                    ("提醒数", "\(validationState?.issues.filter { $0.severity == .warning }.count ?? 0)"),
                    ("最新 revision", revisionHistory.first.map { "r\(String(format: "%04d", $0.revision))" } ?? "暂无")
                ]
            )
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
                        Text(fileSemanticDescription(for: node))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if supportsStructuredEditing(for: node) {
                        Picker("", selection: editorModeBinding(for: node)) {
                            ForEach(TemplateWorkspaceFileEditorMode.allCases) { item in
                                Text(item.rawValue).tag(item)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 150)
                    }
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

                if let currentStructuredErrorMessage {
                    Text(currentStructuredErrorMessage)
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
                    editableContent(for: node)
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
                    detail: "左侧会按照标准模板文件系统展示 `template.json`、`SOUL.md`、`USER.md` 等标准配套文件，以及扩展目录。"
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
                        ("职责", fileSemanticDescription(for: node)),
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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("草稿校验")
                        .font(.headline)
                    Text("以当前草稿目录为基准检查标准文件完整性、`template.json` 可读性、`SOUL.md` 结构，以及模板语义规范。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("重新校验") {
                    refreshValidationState()
                }
                .buttonStyle(.bordered)
            }

            if let validationState, validationState.issues.isEmpty {
                emptyState(
                    title: "当前草稿通过校验",
                    detail: "标准必需文件齐全，`SOUL.md` 可正确解析，当前模板语义也通过了已有规范检查。"
                )
            } else if let validationState {
                infoCard(
                    title: "校验结果",
                    rows: [
                        ("校验时间", validationState.validatedAt.formatted(date: .abbreviated, time: .shortened)),
                        ("错误数", "\(validationState.issues.filter { $0.severity == .error }.count)"),
                        ("提醒数", "\(validationState.issues.filter { $0.severity == .warning }.count)")
                    ]
                )

                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(validationState.issues) { issue in
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
            } else {
                emptyState(
                    title: "尚未执行草稿校验",
                    detail: "点击“重新校验”后，系统会基于当前草稿目录生成最新校验结果。"
                )
            }
        }
    }

    @ViewBuilder
    private var versionsPane: some View {
        if revisionHistory.isEmpty {
            emptyState(
                title: "当前还没有可展示的 revision",
                detail: "正式模板资产还没有可读取的历史快照。保存模板后，这里会显示 revision 时间线。"
            )
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(revisionHistory, id: \.revision) { revision in
                    HStack {
                        Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                            .foregroundColor(.purple)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("r\(String(format: "%04d", revision.revision)) · \(revision.displayName)")
                                .font(.subheadline.weight(.semibold))
                            Text(revision.updatedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(revision.status.rawValue) · \(revision.meta.identity)")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button("查看") {
                            selectedTab = .files
                            selectedFilePath = "revisions/r\(String(format: "%04d", revision.revision)).json"
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
                title: "当前模板资产",
                rows: [
                    ("模板名称", template.name),
                    ("模板 ID", template.id),
                    ("本地资产目录", templateLibrary.templateAssetDirectoryURL(for: template.id)?.path ?? "当前模板没有本地目录"),
                    ("当前 revision", revisionHistory.first.map { "r\(String(format: "%04d", $0.revision))" } ?? "暂无")
                ]
            )

            GroupBox("导出") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("从工作区直接导出当前模板资产或纯净的 `SOUL.md`。")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack {
                        Button("导出模板资产目录") {
                            exportCurrentTemplateAsset()
                        }
                        .buttonStyle(.borderedProminent)

                        Button("导出 SOUL.md") {
                            exportCurrentSoulDocument()
                        }
                        .buttonStyle(.bordered)

                        Button("打开资产目录") {
                            openCurrentTemplateAssetDirectory()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            GroupBox("导入") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("导入后都会生成新的独立模板资产，与当前模板或源目录都不保持关联。")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack {
                        Button("导入模板资产目录") {
                            importTemplateAssets()
                        }
                        .buttonStyle(.borderedProminent)

                        Button("导入 JSON 交换文件") {
                            importTemplatesFromJSON()
                        }
                        .buttonStyle(.bordered)

                        Button("从 SOUL.md 新建模板") {
                            importSoulAsTemplate()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            if templateLibrary.isBuiltInTemplate(template.id) == false {
                GroupBox("删除") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("删除会同时清理当前模板资产目录和工作区草稿目录，不影响系统模板。")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Button("删除当前模板资产", role: .destructive) {
                            showingDeleteTemplateAlert = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func editableContent(for node: TemplateFileNode) -> some View {
        switch node.relativePath {
        case "SOUL.md":
            soulEditorContent
        case "template.json":
            templateDocumentEditorContent
        default:
            rawTextEditor
        }
    }

    @ViewBuilder
    private var rawTextEditor: some View {
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
    }

    @ViewBuilder
    private var soulEditorContent: some View {
        if soulEditorMode == .structured, let soulDraft, soulStructuredErrorMessage == nil {
            VStack(alignment: .leading, spacing: 10) {
                Text("`SOUL.md` 是 agent 语义主源。这里的结构化修改会实时回写到原始 markdown 草稿。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TemplateWorkspaceSoulStructuredEditor(draft: soulDraftBinding(fallback: soulDraft))
            }
        } else {
            rawTextEditor
        }
    }

    @ViewBuilder
    private var templateDocumentEditorContent: some View {
        if documentEditorMode == .structured, let documentDraft, documentStructuredErrorMessage == nil {
            VStack(alignment: .leading, spacing: 10) {
                Text("`template.json` 主要承担模板资产索引职责。`SOUL.md` 标题与语义字段在正式保存时仍会作为主源覆盖对应语义字段。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TemplateWorkspaceMetadataStructuredEditor(draft: documentDraftBinding(fallback: documentDraft))
            }
        } else {
            rawTextEditor
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
            validationState = session.lastValidationState
            refreshValidationState()
            refreshRevisionHistory()
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
        validationState = nil
        revisionHistory = []
        soulDraft = nil
        documentDraft = nil
        soulStructuredErrorMessage = nil
        documentStructuredErrorMessage = nil
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

    private func supportsStructuredEditing(for node: TemplateFileNode) -> Bool {
        switch node.relativePath {
        case "SOUL.md", "template.json":
            return true
        default:
            return false
        }
    }

    private func editorModeBinding(for node: TemplateFileNode) -> Binding<TemplateWorkspaceFileEditorMode> {
        switch node.relativePath {
        case "SOUL.md":
            return $soulEditorMode
        case "template.json":
            return $documentEditorMode
        default:
            return .constant(.raw)
        }
    }

    private func hydrateStructuredDrafts(for relativePath: String, contents: String) {
        isHydratingStructuredDraft = true
        defer { isHydratingStructuredDraft = false }

        switch relativePath {
        case "SOUL.md":
            do {
                soulDraft = try TemplateWorkspaceSoulDraft(markdown: contents)
                soulStructuredErrorMessage = nil
            } catch {
                soulDraft = nil
                soulStructuredErrorMessage = "SOUL.md 当前无法切换到结构化视图：\(error.localizedDescription)。请先在原文中修复章节结构。"
            }
            documentDraft = nil
            documentStructuredErrorMessage = nil
        case "template.json":
            do {
                documentDraft = try TemplateWorkspaceDocumentDraft(json: contents)
                documentStructuredErrorMessage = nil
            } catch {
                documentDraft = nil
                documentStructuredErrorMessage = "template.json 当前无法切换到结构化视图：\(error.localizedDescription)。请先在原文中修复 JSON。"
            }
            soulDraft = nil
            soulStructuredErrorMessage = nil
        default:
            soulDraft = nil
            documentDraft = nil
            soulStructuredErrorMessage = nil
            documentStructuredErrorMessage = nil
        }
    }

    private func soulDraftBinding(fallback: TemplateWorkspaceSoulDraft) -> Binding<TemplateWorkspaceSoulDraft> {
        Binding(
            get: { soulDraft ?? fallback },
            set: { updated in
                soulDraft = updated
                guard !isHydratingStructuredDraft else { return }
                editorText = updated.renderedMarkdown
                isEditorDirty = true
            }
        )
    }

    private func documentDraftBinding(fallback: TemplateWorkspaceDocumentDraft) -> Binding<TemplateWorkspaceDocumentDraft> {
        Binding(
            get: { documentDraft ?? fallback },
            set: { updated in
                documentDraft = updated
                guard !isHydratingStructuredDraft else { return }
                if let renderedJSON = try? updated.renderedJSON {
                    editorText = renderedJSON
                }
                isEditorDirty = true
            }
        )
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
            hydrateStructuredDrafts(for: relativePath, contents: editorText)
        } catch {
            editorText = ""
            fileErrorMessage = error.localizedDescription
            soulDraft = nil
            documentDraft = nil
            soulStructuredErrorMessage = nil
            documentStructuredErrorMessage = nil
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
            refreshValidationState()
            onFeedback("已写入模板草稿文件：\(selectedNode.displayName)")
        } catch {
            fileErrorMessage = error.localizedDescription
            onFeedback("模板草稿写入失败：\(error.localizedDescription)")
        }
    }

    private func persistWorkspaceDraft() {
        if isEditorDirty {
            saveCurrentFile()
            if isEditorDirty {
                return
            }
        }

        do {
            let persisted = try templateLibrary.persistDraftSession(for: template.id)
            if persisted.id == template.id {
                resetWorkspaceState()
                bootstrapWorkspace()
            }
            onPersisted(persisted)
            let message: String
            if persisted.id != template.id {
                message = persisted.validationIssues.isEmpty
                    ? "模板草稿已分叉为新的独立模板资产。"
                    : "模板草稿已分叉为新的模板资产，但仍有 \(persisted.validationIssues.count) 个校验问题。"
            } else {
                message = persisted.validationIssues.isEmpty
                    ? "模板草稿已保存为正式模板资产。"
                    : "模板草稿已保存，但仍有 \(persisted.validationIssues.count) 个校验问题。"
            }
            onFeedback(message)
        } catch {
            fileErrorMessage = error.localizedDescription
            onFeedback("模板资产保存失败：\(error.localizedDescription)")
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
            refreshValidationState()
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
            refreshValidationState()
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

    private func fileSemanticDescription(for node: TemplateFileNode) -> String {
        switch node.relativePath {
        case "template.json":
            return "模板资产的结构化主定义文件。"
        case "SOUL.md":
            return "agent 的语义主源，定义角色、使命、流程与边界。"
        case "AGENTS.md":
            return "标准资产摘要与打包清单，由系统物化维护。"
        case "IDENTITY.md":
            return "agent 自身身份、角色摘要与能力签名。"
        case "USER.md":
            return "记录被帮助用户的人物上下文，不再用于描述模板用途。"
        case "TOOLS.md":
            return "描述工具能力、运行说明与完成前自检要点。"
        case "BOOTSTRAP.md":
            return "启动检查清单，说明读取哪些文件后再开始执行。"
        case "HEARTBEAT.md":
            return "执行中的自检节奏与质量回看规则。"
        case "MEMORY.md":
            return "记录连续性、稳定规则和记忆维护线索。"
        case "lineage.json":
            return "模板来源、导入链路与演化记录。"
        case "extensions":
            return "示例、测试与二次开发素材目录。"
        case "extensions/README.md":
            return "扩展开发总览与目录使用说明。"
        case "extensions/examples/README.md":
            return "模板示例扩展的说明入口。"
        case "extensions/examples/default-prompt.md":
            return "给模板使用者的默认调用示例。"
        case "extensions/tests/README.md":
            return "模板测试目录说明。"
        case "extensions/tests/acceptance-checklist.md":
            return "模板验收检查清单。"
        case "extensions/assets/README.md":
            return "模板附带资源目录说明。"
        case "extensions/assets/asset-manifest.md":
            return "模板附带资源清单。"
        default:
            if node.relativePath.hasPrefix("revisions/") {
                return "历史 revision 快照，只读查看。"
            }
            if node.relativePath == "revisions" {
                return "模板历史 revision 存储目录。"
            }
            return "标准模板文件。"
        }
    }

    private func refreshValidationState() {
        do {
            validationState = try templateLibrary.validateDraftSession(for: template.id)
        } catch {
            validationState = TemplateValidationState(
                issues: [
                    AgentTemplateValidationIssue(
                        severity: .error,
                        field: "workspace",
                        message: error.localizedDescription
                    )
                ]
            )
        }
    }

    private func refreshRevisionHistory() {
        revisionHistory = templateLibrary.templateRevisionHistory(for: template.id)
    }

    private func importTemplatesFromJSON() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]
        panel.begin { response in
            guard response == .OK,
                  let url = panel.url,
                  let data = try? Data(contentsOf: url) else { return }

            do {
                let imported = try templateLibrary.importTemplates(from: data)
                if let first = imported.first {
                    onPersisted(first)
                }
                onFeedback("已导入 \(imported.count) 个模板。")
            } catch {
                onFeedback("导入失败：\(error.localizedDescription)")
            }
        }
    }

    private func importTemplateAssets() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = "导入模板资产"
        panel.message = "选择一个或多个模板资产目录，或选择包含多个模板资产目录的上级目录。"
        panel.begin { response in
            guard response == .OK else { return }

            do {
                importPreviewReport = try templateLibrary.preflightImportTemplateAssets(from: panel.urls)
            } catch {
                onFeedback("模板资产导入失败：\(error.localizedDescription)")
            }
        }
    }

    private func performTemplateAssetImport(_ report: TemplateAssetImportPreviewReport) {
        do {
            let imported = try templateLibrary.importTemplateAssets(using: report)
            importPreviewReport = nil
            if let first = imported.first {
                onPersisted(first)
            }
            let warningSuffix = report.warningCount > 0 ? "，已根据预检结果自动避让冲突" : ""
            onFeedback("已导入 \(imported.count) 个模板资产\(warningSuffix)。")
        } catch {
            onFeedback("模板资产导入失败：\(error.localizedDescription)")
        }
    }

    private func importSoulAsTemplate() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [markdownContentType]
        panel.begin { response in
            guard response == .OK,
                  let url = panel.url,
                  let markdown = try? String(contentsOf: url, encoding: .utf8) else { return }

            do {
                let parsed = try AgentTemplateSoulMarkdownParser.parse(markdown)
                guard let duplicated = templateLibrary.duplicateTemplate(from: template.id) else {
                    onFeedback("无法基于当前模板创建导入副本。")
                    return
                }

                var imported = duplicated
                imported.meta.name = parsed.name
                imported.meta.summary = summaryText(from: parsed.spec.mission)
                imported.soulSpec = parsed.spec
                imported = imported.sanitizedForPersistence()

                let persisted = templateLibrary.upsert(imported)
                onPersisted(persisted)
                onFeedback("已从 SOUL.md 创建模板：\(persisted.name)")
            } catch {
                onFeedback("SOUL.md 导入失败：\(error.localizedDescription)")
            }
        }
    }

    private func exportCurrentTemplateAsset() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "选择导出目录"
        panel.message = "模板将以标准模板资产目录形式导出到所选目录。"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            do {
                let exportedURL = try templateLibrary.exportTemplateAsset(template.id, to: url)
                onFeedback("模板资产已导出到 \(exportedURL.lastPathComponent)。")
            } catch {
                onFeedback("模板资产导出失败：\(error.localizedDescription)")
            }
        }
    }

    private func exportCurrentSoulDocument() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [markdownContentType]
        panel.nameFieldStringValue = "\(exportFileBaseName(for: template))-SOUL.md"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            do {
                try template.soulMD.write(to: url, atomically: true, encoding: .utf8)
                onFeedback("SOUL.md 已导出到 \(url.lastPathComponent)。")
            } catch {
                onFeedback("导出 SOUL.md 失败：\(error.localizedDescription)")
            }
        }
    }

    private func openCurrentTemplateAssetDirectory() {
        guard let assetURL = templateLibrary.templateAssetDirectoryURL(for: template.id) else {
            onFeedback("该模板当前没有可直接打开的本地模板资产目录。")
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([assetURL])
        onFeedback("已打开模板资产目录：\(assetURL.lastPathComponent)。")
    }

    private func deleteCurrentTemplate() {
        guard templateLibrary.isBuiltInTemplate(template.id) == false else {
            onFeedback("系统模板不支持删除。")
            return
        }

        let deletedTemplateID = template.id
        let deletedTemplateName = template.name
        templateLibrary.deleteCustomTemplate(deletedTemplateID)
        onFeedback("已删除自定义模板：\(deletedTemplateName)")
        onDeleted(deletedTemplateID)
    }

    private func exportFileBaseName(for template: AgentTemplate) -> String {
        let preferredName = template.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = preferredName.isEmpty ? template.id : preferredName
        let invalidCharacters = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let cleaned = base
            .components(separatedBy: invalidCharacters)
            .joined(separator: "-")
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "--", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-. "))

        return cleaned.isEmpty ? template.id.replacingOccurrences(of: ".", with: "-") : cleaned
    }

    private func summaryText(from mission: String) -> String {
        let trimmed = mission.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "从 SOUL.md 导入的模板" }
        if trimmed.count <= 80 {
            return trimmed
        }
        return String(trimmed.prefix(80)) + "..."
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

private struct TemplateWorkspaceSoulDraft: Hashable {
    var name: String
    var role: String
    var mission: String
    var coreCapabilitiesText: String
    var responsibilitiesText: String
    var workflowText: String
    var inputsText: String
    var outputsText: String
    var collaborationText: String
    var guardrailsText: String
    var successCriteriaText: String

    init(template: AgentTemplate) {
        self.name = template.name
        self.role = template.soulSpec.role
        self.mission = template.soulSpec.mission
        self.coreCapabilitiesText = template.soulSpec.coreCapabilities.joined(separator: "\n")
        self.responsibilitiesText = template.soulSpec.responsibilities.joined(separator: "\n")
        self.workflowText = template.soulSpec.workflow.joined(separator: "\n")
        self.inputsText = template.soulSpec.inputs.joined(separator: "\n")
        self.outputsText = template.soulSpec.outputs.joined(separator: "\n")
        self.collaborationText = template.soulSpec.collaboration.joined(separator: "\n")
        self.guardrailsText = template.soulSpec.guardrails.joined(separator: "\n")
        self.successCriteriaText = template.soulSpec.successCriteria.joined(separator: "\n")
    }

    init(markdown: String) throws {
        let parsed = try AgentTemplateSoulMarkdownParser.parse(markdown)
        self.name = parsed.name
        self.role = parsed.spec.role
        self.mission = parsed.spec.mission
        self.coreCapabilitiesText = parsed.spec.coreCapabilities.joined(separator: "\n")
        self.responsibilitiesText = parsed.spec.responsibilities.joined(separator: "\n")
        self.workflowText = parsed.spec.workflow.joined(separator: "\n")
        self.inputsText = parsed.spec.inputs.joined(separator: "\n")
        self.outputsText = parsed.spec.outputs.joined(separator: "\n")
        self.collaborationText = parsed.spec.collaboration.joined(separator: "\n")
        self.guardrailsText = parsed.spec.guardrails.joined(separator: "\n")
        self.successCriteriaText = parsed.spec.successCriteria.joined(separator: "\n")
    }

    var renderedMarkdown: String {
        """
        # \(name.trimmingCharacters(in: .whitespacesAndNewlines))

        ## 角色定位
        \(role.trimmingCharacters(in: .whitespacesAndNewlines))

        ## 核心使命
        \(mission.trimmingCharacters(in: .whitespacesAndNewlines))

        ## 核心能力
        \(bulletList(from: coreCapabilitiesText))

        ## 输入要求
        \(bulletList(from: inputsText))

        ## 工作职责
        \(bulletList(from: responsibilitiesText))

        ## 工作流程
        \(numberedList(from: workflowText))

        ## 输出要求
        \(bulletList(from: outputsText))

        ## 协作边界
        \(bulletList(from: collaborationText))

        ## 行为边界
        \(bulletList(from: guardrailsText))

        ## 成功标准
        \(bulletList(from: successCriteriaText))
        """
    }

    private func normalizedLines(from text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func bulletList(from text: String) -> String {
        normalizedLines(from: text).map { "- \($0)" }.joined(separator: "\n")
    }

    private func numberedList(from text: String) -> String {
        normalizedLines(from: text)
            .enumerated()
            .map { "\($0.offset + 1). \($0.element)" }
            .joined(separator: "\n")
    }
}

private struct TemplateWorkspaceImportPreviewSheet: View {
    let report: TemplateAssetImportPreviewReport
    let onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("模板资产导入预检")
                        .font(.headline)
                    Text(summaryText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("关闭") {
                    dismiss()
                }
                .buttonStyle(.borderless)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("导入后所有条目都会变成新的独立模板资产，不会覆盖现有模板，也不会继续与源目录保持关联。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    ForEach(report.entries) { entry in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.sourceName)
                                        .font(.subheadline.weight(.semibold))
                                    Text(entry.sourceDirectoryURL.lastPathComponent)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    Text(entry.sourceDirectoryURL.path)
                                        .font(.caption2.monospaced())
                                        .foregroundColor(.secondary)
                                        .textSelection(.enabled)
                                        .lineLimit(2)
                                }
                                Spacer()
                                if entry.warningCount > 0 {
                                    Text("冲突 \(entry.warningCount)")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundColor(.orange)
                                } else {
                                    Text("可直接导入")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundColor(.green)
                                }
                            }

                            HStack(alignment: .top, spacing: 12) {
                                workspaceImportInfoColumn(
                                    title: "源模板信息",
                                    rows: [
                                        ("模板 ID", entry.sourceTemplateID),
                                        ("名称", entry.sourceName),
                                        ("identity", entry.sourceIdentity.isEmpty ? "(空)" : entry.sourceIdentity)
                                    ]
                                )
                                workspaceImportInfoColumn(
                                    title: "导入后",
                                    rows: [
                                        ("模板 ID", entry.importedTemplate.id),
                                        ("名称", entry.importedTemplate.name),
                                        ("identity", entry.importedTemplate.identity)
                                    ]
                                )
                            }

                            ForEach(entry.issues) { issue in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(issue.title)
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(issue.level == .warning ? .orange : .secondary)
                                    Text(issue.detail)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background((issue.level == .warning ? Color.orange.opacity(0.08) : Color.primary.opacity(0.04)))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                .padding()
            }

            Divider()

            HStack {
                Button("取消") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                Spacer()
                Button("确认导入 \(report.entries.count) 个模板资产") {
                    onConfirm()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(minWidth: 940, minHeight: 620)
    }

    private var summaryText: String {
        if report.warningCount > 0 {
            return "已扫描 \(report.entries.count) 个模板资产，发现 \(report.warningCount) 项需要提示的冲突或避让。"
        }
        return "已扫描 \(report.entries.count) 个模板资产，未发现需要避让的命名冲突。"
    }
}

@ViewBuilder
private func workspaceImportInfoColumn(title: String, rows: [(String, String)]) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        Text(title)
            .font(.caption.weight(.semibold))
        ForEach(Array(rows.enumerated()), id: \.offset) { item in
            let row = item.element
            VStack(alignment: .leading, spacing: 2) {
                Text(row.0)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(row.1)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.white.opacity(0.6))
    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
}

private struct TemplateWorkspaceDocumentDraft: Hashable {
    var id: String
    var displayName: String
    var category: AgentTemplateCategory
    var summary: String
    var applicableScenariosText: String
    var identity: String
    var capabilitiesText: String
    var tagsText: String
    var colorHex: String
    var sortOrder: Int
    var isRecommended: Bool
    var soulSpec: AgentTemplateSoulSpec
    var revision: Int
    var status: TemplateAssetStatus
    var createdAt: Date
    var updatedAt: Date

    init(template: AgentTemplate) {
        self.id = template.id
        self.displayName = template.name
        self.category = template.category
        self.summary = template.summary
        self.applicableScenariosText = template.applicableScenarios.joined(separator: "\n")
        self.identity = template.identity
        self.capabilitiesText = template.capabilities.joined(separator: "\n")
        self.tagsText = template.tags.joined(separator: "\n")
        self.colorHex = template.colorHex
        self.sortOrder = template.meta.sortOrder
        self.isRecommended = template.meta.isRecommended
        self.soulSpec = template.soulSpec
        self.revision = 1
        self.status = .draft
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    init(document: TemplateAssetDocument) {
        self.id = document.id
        self.displayName = document.displayName
        self.category = document.meta.category
        self.summary = document.meta.summary
        self.applicableScenariosText = document.meta.applicableScenarios.joined(separator: "\n")
        self.identity = document.meta.identity
        self.capabilitiesText = document.meta.capabilities.joined(separator: "\n")
        self.tagsText = document.meta.tags.joined(separator: "\n")
        self.colorHex = document.meta.colorHex
        self.sortOrder = document.meta.sortOrder
        self.isRecommended = document.meta.isRecommended
        self.soulSpec = document.soulSpec
        self.revision = document.revision
        self.status = document.status
        self.createdAt = document.createdAt
        self.updatedAt = document.updatedAt
    }

    init(json: String) throws {
        let decoder = JSONDecoder()
        let data = Data(json.utf8)
        let document = try decoder.decode(TemplateAssetDocument.self, from: data)
        self.init(document: document)
    }

    var renderedJSON: String {
        get throws {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

            let template = renderedTemplate
            let document = TemplateAssetDocument(
                template: template,
                revision: revision,
                status: status,
                createdAt: createdAt,
                updatedAt: Date()
            )
            let data = try encoder.encode(document)
            guard let json = String(data: data, encoding: .utf8) else {
                throw CocoaError(.fileWriteInapplicableStringEncoding)
            }
            return json
        }
    }

    private var renderedTemplate: AgentTemplate {
        let baseMeta = AgentTemplateMeta(
            id: id.trimmingCharacters(in: .whitespacesAndNewlines),
            category: category,
            name: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            summary: summary.trimmingCharacters(in: .whitespacesAndNewlines),
            applicableScenarios: splitLines(applicableScenariosText),
            identity: identity.trimmingCharacters(in: .whitespacesAndNewlines),
            capabilities: splitLines(capabilitiesText),
            tags: splitLines(tagsText),
            colorHex: colorHex.trimmingCharacters(in: .whitespacesAndNewlines),
            sortOrder: sortOrder,
            isRecommended: isRecommended
        )

        return AgentTemplate(
            meta: baseMeta,
            soulSpec: soulSpec
        ).sanitizedForPersistence()
    }

    private func splitLines(_ text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

private struct TemplateWorkspaceSoulStructuredEditor: View {
    @Binding var draft: TemplateWorkspaceSoulDraft

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                templateEditorField("模板名称（SOUL 标题）", text: $draft.name)
                templateMultilineField("角色定位", text: $draft.role, height: 80)
                templateMultilineField("核心使命", text: $draft.mission, height: 80)
                templateMultilineField("核心能力", text: $draft.coreCapabilitiesText, height: 90)
                templateMultilineField("输入要求", text: $draft.inputsText, height: 90)
                templateMultilineField("工作职责", text: $draft.responsibilitiesText, height: 100)
                templateMultilineField("工作流程", text: $draft.workflowText, height: 110)
                templateMultilineField("输出要求", text: $draft.outputsText, height: 90)
                templateMultilineField("协作边界", text: $draft.collaborationText, height: 90)
                templateMultilineField("行为边界", text: $draft.guardrailsText, height: 90)
                templateMultilineField("成功标准", text: $draft.successCriteriaText, height: 90)
            }
        }
    }
}

private struct TemplateWorkspaceMetadataStructuredEditor: View {
    @Binding var draft: TemplateWorkspaceDocumentDraft

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                templateEditorField("模板 ID", text: $draft.id)

                Picker("分类", selection: $draft.category) {
                    ForEach(AgentTemplateCatalog.categories, id: \.self) { category in
                        Text(category.rawValue).tag(category)
                    }
                }
                .pickerStyle(.menu)

                HStack(spacing: 8) {
                    Text(draft.category.rawValue)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(CanvasStylePalette.color(from: draft.category.defaultColorHex) ?? .secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background((CanvasStylePalette.color(from: draft.category.defaultColorHex) ?? .secondary).opacity(0.12))
                        .clipShape(Capsule())
                    Text("分类默认色 #\(draft.category.defaultColorHex)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                templateEditorField("identity", text: $draft.identity)
                templateEditorField("颜色 HEX", text: $draft.colorHex)
                templateMultilineField("摘要", text: $draft.summary, height: 80)
                templateMultilineField("适用场景", text: $draft.applicableScenariosText, height: 90)
                templateMultilineField("能力标签", text: $draft.capabilitiesText, height: 90)
                templateMultilineField("模板标签", text: $draft.tagsText, height: 90)
            }
        }
    }
}

@ViewBuilder
private func templateEditorField(_ title: String, text: Binding<String>) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        Text(title)
            .font(.caption)
            .foregroundColor(.secondary)
        TextField(title, text: text)
            .textFieldStyle(.roundedBorder)
    }
}

@ViewBuilder
private func templateMultilineField(_ title: String, text: Binding<String>, height: CGFloat) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        Text(title)
            .font(.caption)
            .foregroundColor(.secondary)
        TextEditor(text: text)
            .font(.system(.body, design: .monospaced))
            .frame(height: height)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.25), lineWidth: 1)
            )
    }
}
