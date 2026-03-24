import SwiftUI

struct TemplateWorkspaceAssistComposerSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let template: AgentTemplate
    let relativeFilePath: String
    let isFileMissing: Bool
    let fileContent: String?
    let onPrepared: (AssistSubmissionResult) -> Void

    @State private var prompt: String
    @State private var errorText: String?
    @State private var isGeneratingProposal = false

    init(
        template: AgentTemplate,
        relativeFilePath: String,
        isFileMissing: Bool,
        fileContent: String?,
        initialPrompt: String = "",
        onPrepared: @escaping (AssistSubmissionResult) -> Void
    ) {
        self.template = template
        self.relativeFilePath = relativeFilePath
        self.isFileMissing = isFileMissing
        self.fileContent = fileContent
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
        .frame(minWidth: 700, minHeight: 540)
    }

    private var trimmedPrompt: String {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var draftPreview: AppState.AssistDraft {
        appState.makeTemplateWorkspaceAssistDraft(
            prompt: trimmedPrompt,
            template: template,
            relativeFilePath: relativeFilePath,
            fileContent: fileContent,
            isFileMissing: isFileMissing
        )
    }

    private var canPrepareProposal: Bool {
        !trimmedPrompt.isEmpty && !isGeneratingProposal
    }

    private var fileScopeDetail: String {
        "\(template.name) / \(relativeFilePath)"
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Assist 是戴着手套、受限权限、每一步可回退的手。", systemImage: "hand.raised.fill")
                .font(.headline)
                .foregroundColor(.teal)

            Text("这里表达的是“我想怎么改当前模板文件”。Assist 会围绕当前草稿文件生成结构化建议与预览，不会直接碰正式模板资产。")
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
                chip(title: "模板文件", color: .teal)
                chip(title: intentTitle(for: draftPreview.intent), color: .blue)
                chip(title: "Draft", color: .orange)
                if isFileMissing {
                    chip(title: "缺失文件", color: .orange)
                }
            }

            Text(fileScopeDetail)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(
                isFileMissing
                    ? "当前文件在草稿中尚未存在。Assist 会基于模板身份和文件路径生成补全/修改建议，但仍保持 suggestion-first。"
                    : "本次建议只围绕当前文件展开，后续真正的文件改动仍需用户确认，并继续停留在 draft。"
            )
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
            Text("你想让 Assist 怎么处理这个文件")
                .font(.headline)

            TextEditor(text: $prompt)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(minHeight: 200)
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
                        Text(placeholderText)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .allowsHitTesting(false)
                    }
                }

            FlowLayout(spacing: 8) {
                if isFileMissing {
                    presetButton("补齐标准文件") {
                        prompt = "请为当前缺失的标准模板文件生成一份建议草案，并说明为什么这样补齐。"
                    }
                } else {
                    presetButton("润色当前文件") {
                        prompt = "请帮我润色当前模板文件，使语气更清晰、结构更易读，并说明调整重点。"
                    }
                    presetButton("补全模板说明") {
                        prompt = "请补全当前模板文件中缺少的说明部分，并给出建议预览。"
                    }
                }

                presetButton("检查表达问题") {
                    prompt = "请检查当前模板文件里是否有表达含糊、重复或不一致的地方，并按优先级给出建议。"
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var placeholderText: String {
        if isFileMissing {
            return "例如：请补齐这个缺失的标准模板文件，保持与当前模板身份一致，并给我一个预览。"
        }
        return "例如：请把当前模板说明改得更清晰，保留原意但减少重复；或补全这个文件缺少的说明段落。"
    }

    private func prepareProposal() {
        guard canPrepareProposal else { return }

        isGeneratingProposal = true
        errorText = nil
        defer { isGeneratingProposal = false }

        do {
            let result = try appState.createAssistProposal(draftPreview)
            dismiss()
            DispatchQueue.main.async {
                onPrepared(result)
            }
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func chip(title: String, color: Color) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundColor(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(color.opacity(0.12))
            )
    }

    private func presetButton(
        _ title: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(title, action: action)
            .buttonStyle(.bordered)
    }

    private func intentTitle(for intent: AssistIntent) -> String {
        switch intent {
        case .rewriteSelection:
            return "改写文本"
        case .completeTemplate:
            return "补全模板"
        case .modifyManagedContent:
            return "修改内容"
        case .reorganizeWorkflow:
            return "整理布局"
        case .inspectConfiguration:
            return "检查配置"
        case .inspectPerformance:
            return "分析性能"
        case .explainIssue:
            return "解释问题"
        case .custom:
            return "通用建议"
        }
    }

    private func errorCard(text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
