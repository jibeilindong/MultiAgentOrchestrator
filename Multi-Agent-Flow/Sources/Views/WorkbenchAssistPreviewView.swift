import SwiftUI

struct AssistProposalPreviewState: Identifiable {
    let result: AssistSubmissionResult

    var id: String { result.proposal.id }
}

struct AssistProposalPreviewSheet: View {
    let result: AssistSubmissionResult

    @Environment(\.dismiss) private var dismiss

    private var request: AssistRequest { result.request }
    private var proposal: AssistProposal { result.proposal }
    private var contextPack: AssistContextPack { result.contextPack }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    topBanner
                    summarySection

                    if !proposal.warnings.isEmpty {
                        warningsSection
                    }

                    changesSection
                    contextSection
                    auditSection
                }
                .padding(20)
            }
            .navigationTitle("Assist Proposal")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 720, minHeight: 680)
    }

    private var topBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "hand.raised.fill")
                .font(.title3)
                .foregroundColor(.teal)

            VStack(alignment: .leading, spacing: 4) {
                Text("Assist is wearing gloves. Nothing has been changed yet.")
                    .font(.headline)
                Text("This is a proposal-only preview. Any future apply step must still be explicitly confirmed and remain outside the live runtime.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            badge(title: proposalStatusTitle, color: .orange)
        }
        .padding(14)
        .background(Color.teal.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var summarySection: some View {
        proposalSection("Summary") {
            VStack(alignment: .leading, spacing: 10) {
                Text(proposal.summary)
                    .font(.title3.weight(.semibold))

                FlowLayout(spacing: 8) {
                    badge(title: "Intent: \(intentTitle(for: request.intent))", color: .blue)
                    badge(title: "Scope: \(scopeTitle)", color: .teal)
                    badge(title: "Surface: \(workspaceSurfaceTitle)", color: .purple)
                    if let threadID = request.scopeRef.threadID {
                        badge(title: "Thread: \(threadID)", color: .gray)
                    }
                }

                Text(scopeDetail)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                if let rationale = proposal.rationale, !rationale.isEmpty {
                    Divider()
                    Text(rationale)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var warningsSection: some View {
        proposalSection("Warnings") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(proposal.warnings.enumerated()), id: \.offset) { _, warning in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.caption)
                            .padding(.top, 2)
                        Text(warning)
                            .font(.subheadline)
                    }
                }
            }
        }
    }

    private var changesSection: some View {
        proposalSection("Change Preview") {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(proposal.changeItems) { item in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title)
                                    .font(.headline)
                                Text(item.summary)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }

                            Spacer(minLength: 12)

                            VStack(alignment: .trailing, spacing: 6) {
                                badge(title: targetTitle(for: item.target), color: .blue)
                                badge(title: operationTitle(for: item.operation), color: .secondary)
                            }
                        }

                        if let relativeFilePath = item.relativeFilePath {
                            Text(relativeFilePath)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        if let beforePreview = item.beforePreview, !beforePreview.isEmpty {
                            previewCard(title: "Before", text: beforePreview)
                        }

                        if let afterPreview = item.afterPreview, !afterPreview.isEmpty {
                            previewCard(title: "After", text: afterPreview)
                        }
                    }
                    .padding(14)
                    .background(Color(.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }

    private var contextSection: some View {
        proposalSection("Context Used") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(contextPreviewEntries.enumerated()), id: \.element.id) { index, entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(entry.title)
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Text(entry.kind.rawValue)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Text(entry.value)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                    }

                    if index < contextPreviewEntries.count - 1 {
                        Divider()
                    }
                }

                if contextPack.entries.count > contextPreviewEntries.count {
                    Text("+ \(contextPack.entries.count - contextPreviewEntries.count) more context entries")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var auditSection: some View {
        proposalSection("Audit") {
            VStack(alignment: .leading, spacing: 8) {
                auditRow(label: "Request ID", value: request.id)
                auditRow(label: "Proposal ID", value: proposal.id)
                auditRow(label: "Assist Thread", value: result.thread.id)
                auditRow(label: "Source", value: request.source.rawValue)
                auditRow(label: "Created At", value: request.createdAt.formatted(date: .abbreviated, time: .standard))
            }
        }
    }

    private var contextPreviewEntries: [AssistContextEntry] {
        Array(contextPack.entries.prefix(6)).map { entry in
            AssistContextEntry(
                id: entry.id,
                kind: entry.kind,
                title: entry.title,
                value: truncated(entry.value, limit: 280),
                metadata: entry.metadata
            )
        }
    }

    private var proposalStatusTitle: String {
        switch proposal.status {
        case .drafted:
            return "Drafted"
        case .awaitingConfirmation:
            return "Awaiting Confirmation"
        case .applied:
            return "Applied"
        case .rejected:
            return "Rejected"
        case .failed:
            return "Failed"
        case .reverted:
            return "Reverted"
        case .partiallyApplied:
            return "Partially Applied"
        }
    }

    private var scopeTitle: String {
        switch request.scopeType {
        case .textSelection:
            return "Text Selection"
        case .file:
            return "File"
        case .node:
            return "Node"
        case .workflow:
            return "Workflow"
        case .project:
            return "Project"
        }
    }

    private var scopeDetail: String {
        if let nodeTitle = request.scopeRef.additionalMetadata["nodeTitle"],
           let workflowName = request.scopeRef.additionalMetadata["workflowName"] {
            return "\(nodeTitle) in \(workflowName)"
        }
        if let workflowName = request.scopeRef.additionalMetadata["workflowName"] {
            return workflowName
        }
        if let relativeFilePath = request.scopeRef.relativeFilePath {
            return relativeFilePath
        }
        if let projectName = request.scopeRef.additionalMetadata["projectName"] {
            return projectName
        }
        return "Current scoped context"
    }

    private var workspaceSurfaceTitle: String {
        switch request.scopeRef.workspaceSurface {
        case .draft:
            return "Draft"
        case .managedWorkspace:
            return "Managed Workspace"
        case .mirror:
            return "Mirror"
        case .runtimeReadonly:
            return "Runtime Read-only"
        case nil:
            return "Unspecified"
        }
    }

    @ViewBuilder
    private func proposalSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private func previewCard(
        title: String,
        text: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
            Text(text)
                .font(.caption.monospaced())
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color(.textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func auditRow(
        label: String,
        value: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.caption.monospaced())
                .textSelection(.enabled)
        }
    }

    private func badge(
        title: String,
        color: Color
    ) -> some View {
        Text(title)
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .foregroundColor(color)
            .clipShape(Capsule())
    }

    private func intentTitle(
        for intent: AssistIntent
    ) -> String {
        switch intent {
        case .rewriteSelection:
            return "Rewrite Selection"
        case .completeTemplate:
            return "Complete Template"
        case .modifyManagedContent:
            return "Modify Managed Content"
        case .reorganizeWorkflow:
            return "Reorganize Workflow"
        case .inspectConfiguration:
            return "Inspect Configuration"
        case .inspectPerformance:
            return "Inspect Performance"
        case .explainIssue:
            return "Explain Issue"
        case .custom:
            return "Custom"
        }
    }

    private func targetTitle(
        for target: AssistMutationTarget
    ) -> String {
        switch target {
        case .draftText:
            return "Draft Text"
        case .managedFile:
            return "Managed File"
        case .mirror:
            return "Mirror"
        case .configuration:
            return "Configuration"
        case .workflowLayout:
            return "Workflow Layout"
        case .diagnosticsReport:
            return "Diagnostics Report"
        }
    }

    private func operationTitle(
        for operation: AssistChangeOperationKind
    ) -> String {
        switch operation {
        case .replace:
            return "Replace"
        case .insert:
            return "Insert"
        case .delete:
            return "Delete"
        case .patch:
            return "Patch"
        case .annotate:
            return "Annotate"
        case .suggest:
            return "Suggest"
        }
    }

    private func truncated(
        _ value: String,
        limit: Int
    ) -> String {
        guard value.count > limit else { return value }
        let endIndex = value.index(value.startIndex, offsetBy: limit)
        return "\(value[..<endIndex])..."
    }
}

struct WorkflowEditorAssistComposerSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let workflowID: UUID?
    let onPrepared: (AssistSubmissionResult) -> Void

    @State private var prompt: String
    @State private var errorText: String?
    @State private var isGeneratingProposal = false

    init(
        workflowID: UUID?,
        initialPrompt: String = "",
        onPrepared: @escaping (AssistSubmissionResult) -> Void
    ) {
        self.workflowID = workflowID
        self.onPrepared = onPrepared
        _prompt = State(initialValue: initialPrompt)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                headerCard
                scopeCard
                promptSection

                if let errorText, !errorText.isEmpty {
                    errorCard(text: errorText)
                }

                Spacer(minLength: 0)
            }
            .padding(20)
            .navigationTitle("Assist")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        prepareProposal()
                    } label: {
                        if isGeneratingProposal {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("生成建议")
                        }
                    }
                    .disabled(!canPrepareProposal)
                }
            }
        }
        .frame(minWidth: 680, minHeight: 520)
    }

    private var trimmedPrompt: String {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var scopeDescriptor: AppState.AssistScopeDescriptor {
        appState.resolveWorkbenchAssistScope(workflowID: workflowID)
    }

    private var draftPreview: AppState.AssistDraft {
        appState.makeWorkflowEditorAssistDraft(
            prompt: trimmedPrompt,
            workflowID: workflowID
        )
    }

    private var canPrepareProposal: Bool {
        appState.currentProject != nil
            && !trimmedPrompt.isEmpty
            && !isGeneratingProposal
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Assist 是戴着手套、受限权限、每一步可回退的手。", systemImage: "hand.raised.fill")
                .font(.headline)
                .foregroundColor(.teal)

            Text("这里先表达意图，Assist 只生成建议与预览，不会直接改 live runtime。真正变更仍然要经过确认。")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.teal.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var scopeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("当前作用域")
                .font(.headline)

            FlowLayout(spacing: 8) {
                chip(title: scopeDescriptor.title, color: .teal)
                chip(title: intentTitle(for: draftPreview.intent), color: .blue)
                chip(title: workspaceSurfaceTitle(for: draftPreview.workspaceSurface), color: .orange)
            }

            Text(scopeDescriptor.detail)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("本次建议默认遵循最小作用域与最小权限，只会围绕当前节点、当前 workflow 或当前项目上下文生成 proposal。")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("你想让 Assist 做什么")
                .font(.headline)

            TextEditor(text: $prompt)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(minHeight: 180)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                )
                .overlay(alignment: .topLeading) {
                    if trimmedPrompt.isEmpty {
                        Text("例如：整理当前节点附近布局，并说明为什么这么调整；或分析这个 workflow 的性能瓶颈。")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .allowsHitTesting(false)
                    }
                }

            FlowLayout(spacing: 8) {
                presetButton("整理当前布局") {
                    prompt = "请整理当前节点附近的布局，并给出调整理由。"
                }
                presetButton("解释当前阻塞") {
                    prompt = "请解释当前 workflow 可能存在的问题，并按优先级给出建议。"
                }
                presetButton("分析性能瓶颈") {
                    prompt = "请分析当前 workflow 的性能瓶颈，并给出只读诊断建议。"
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func prepareProposal() {
        guard canPrepareProposal else { return }

        isGeneratingProposal = true
        errorText = nil
        defer { isGeneratingProposal = false }

        do {
            let result = try appState.createAssistProposal(
                appState.makeWorkflowEditorAssistDraft(
                    prompt: trimmedPrompt,
                    workflowID: workflowID
                )
            )
            dismiss()
            DispatchQueue.main.async {
                onPrepared(result)
            }
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func errorCard(text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func presetButton(
        _ title: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            chip(title: title, color: .secondary)
        }
        .buttonStyle(.plain)
    }

    private func chip(
        title: String,
        color: Color
    ) -> some View {
        Text(title)
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.12))
            .foregroundColor(color)
            .clipShape(Capsule())
    }

    private func intentTitle(for intent: AssistIntent) -> String {
        switch intent {
        case .rewriteSelection:
            return "改写内容"
        case .completeTemplate:
            return "补全模板"
        case .modifyManagedContent:
            return "修改托管内容"
        case .reorganizeWorkflow:
            return "整理工作流"
        case .inspectConfiguration:
            return "检查配置"
        case .inspectPerformance:
            return "性能诊断"
        case .explainIssue:
            return "解释问题"
        case .custom:
            return "自定义建议"
        }
    }

    private func workspaceSurfaceTitle(for surface: AssistWorkspaceSurface?) -> String {
        switch surface {
        case .draft:
            return "Draft"
        case .managedWorkspace:
            return "Managed Workspace"
        case .mirror:
            return "Mirror"
        case .runtimeReadonly:
            return "运行态只读"
        case nil:
            return "未指定"
        }
    }
}
