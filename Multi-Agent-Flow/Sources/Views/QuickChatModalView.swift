import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct QuickChatModalView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var store: QuickChatStore

    @State private var draft: String = ""
    @State private var composerHeight: CGFloat = 92
    @State private var isDropTargeted = false
    @State private var lightboxItem: QuickChatImageLightboxItem?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            messagePane
            Divider()
            composer
        }
        .frame(minWidth: 860, idealWidth: 960, minHeight: 620, idealHeight: 760)
        .background(Color(.windowBackgroundColor))
        .sheet(item: $lightboxItem) { item in
            QuickChatImageLightboxView(item: item)
        }
        .onAppear {
            store.refreshContext(using: appState)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Image(systemName: "bolt.bubble.fill")
                            .foregroundColor(.accentColor)
                        Text("Quick Chat")
                            .font(.title3)
                            .fontWeight(.semibold)
                    }

                    Text("轻量弹窗会话，直连 Gateway chat，不进入 Workbench 主控制链路。")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer(minLength: 12)

                HStack(spacing: 8) {
                    Button("新会话") {
                        draft = ""
                        composerHeight = 92
                        store.startNewSession()
                    }
                    .disabled(store.isSending || store.context == nil)

                    if store.isSending {
                        Button(store.isStopping ? "停止中..." : "停止") {
                            store.stop(using: appState)
                        }
                        .disabled(store.isStopping)
                    }
                }
            }

            HStack(spacing: 8) {
                if let context = store.context {
                    quickChatContextPill(systemImage: "square.grid.2x2", text: context.workflowName)
                    quickChatContextPill(systemImage: "shippingbox", text: context.projectName)
                } else {
                    quickChatContextPill(systemImage: "exclamationmark.triangle", text: "当前没有可用快聊上下文")
                }

                gatewayStatusPill

                if !store.agentOptions.isEmpty {
                    agentPicker
                }
            }

            if let statusMessage = store.statusMessage, !statusMessage.isEmpty {
                quickChatStatusBanner(text: statusMessage, color: .accentColor)
            }

            if let lastError = store.lastError, !lastError.isEmpty {
                HStack(spacing: 10) {
                    quickChatStatusBanner(text: lastError, color: .red)
                    Button("关闭提示") {
                        store.clearError()
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                }
            }
        }
        .padding(20)
    }

    private var gatewayStatusPill: some View {
        let summary = gatewaySummary
        return HStack(spacing: 8) {
            Circle()
                .fill(summary.color)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.title)
                    .font(.caption)
                    .foregroundColor(.primary)
                if let detail = summary.detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            Capsule(style: .continuous)
                .fill(summary.color.opacity(0.12))
        )
    }

    private var agentPicker: some View {
        Menu {
            ForEach(store.agentOptions) { option in
                Button {
                    store.selectAgent(option.agentID, using: appState)
                } label: {
                    HStack {
                        Text(option.agentName)
                        if option.isEntryPreferred {
                            Text("入口")
                        }
                    }
                }
            }
        } label: {
            Label("@\(selectedAgentName)", systemImage: "at")
                .font(.caption)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
        }
        .menuStyle(.borderlessButton)
    }

    private var messagePane: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if store.messages.isEmpty {
                        quickChatEmptyState
                    } else {
                        ForEach(store.messages) { message in
                            QuickChatMessageBubbleView(
                                message: message,
                                onOpenImage: { item in
                                    lightboxItem = item
                                }
                            )
                            .id(message.id)
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .textBackgroundColor).opacity(0.55))
            .onAppear {
                scrollToBottom(with: proxy)
            }
            .onChange(of: store.messages) { _, _ in
                scrollToBottom(with: proxy)
            }
        }
    }

    private var quickChatEmptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("开始一个独立的快速会话")
                .font(.title3)
                .fontWeight(.semibold)

            if let context = store.context {
                Text("当前会话会直连 `\(context.entryAgentName)`，使用独立 session key，并优先保留速度与顺滑度。")
                    .foregroundColor(.secondary)
            } else {
                Text("请先在当前项目里准备一个带入口 Agent 的工作流，Quick Chat 才能直接启动。")
                    .foregroundColor(.secondary)
            }

            Text("支持文本、文件上传、拖拽、剪贴板导入，以及结构化消息渲染。")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.controlBackgroundColor))
        )
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !store.attachments.isEmpty {
                QuickChatComposerAttachmentRow(
                    attachments: store.attachments,
                    onRemove: { attachmentID in
                        store.removeAttachment(attachmentID)
                    },
                    onOpenImage: { item in
                        lightboxItem = item
                    }
                )
            }

            HStack(spacing: 8) {
                Button {
                    presentOpenPanel()
                } label: {
                    Label("上传", systemImage: "paperclip")
                }

                Button {
                    store.importFromPasteboard()
                } label: {
                    Label("粘贴", systemImage: "doc.on.clipboard")
                }

                Text("文件会先 stage，再通过 Gateway `chat.send.attachments` 发送。")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer(minLength: 12)

                Text(store.hasPendingAttachments ? "附件 stage 中" : "Enter 发送 · Shift+Enter 换行")
                    .font(.caption)
                    .foregroundColor(store.hasPendingAttachments ? .orange : .secondary)
            }

            HStack(alignment: .bottom, spacing: 12) {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))

                    if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && store.readyAttachmentCount == 0 {
                        Text("输入想快速聊的问题，或直接上传文件后发送。")
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                    }

                    QuickChatGrowingTextEditor(
                        text: $draft,
                        dynamicHeight: $composerHeight,
                        onSubmit: sendCurrentDraft
                    )
                    .frame(height: composerHeight)
                    .padding(.horizontal, 14)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(isDropTargeted ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: isDropTargeted ? 1.5 : 1)
                )
                .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: handleDrop(providers:))

                VStack(spacing: 10) {
                    Button {
                        sendCurrentDraft()
                    } label: {
                        Label(store.isSending ? "发送中" : "发送", systemImage: "paperplane.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSubmit)

                    Text(sendStatusText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                .frame(width: 136)
            }

            HStack {
                Text("Quick Chat 把观察和控制压到最轻，优先保证回复速度。")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer(minLength: 12)

                Text(store.readyAttachmentCount > 0 ? "已就绪附件 \(store.readyAttachmentCount) 个" : "建议长度：1-3 段")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(20)
        .onPasteCommand(of: [.fileURL, .png, .tiff]) { _ in
            store.importFromPasteboard()
        }
    }

    private var selectedAgentName: String {
        store.agentOptions.first(where: { $0.agentID == store.selectedAgentID })?.agentName
            ?? store.context?.entryAgentName
            ?? "选择 Agent"
    }

    private var canSubmit: Bool {
        let hasText = !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return store.canSend && !store.hasFailedAttachments && (hasText || store.readyAttachmentCount > 0)
    }

    private var sendStatusText: String {
        if store.isSending {
            return "正在流式接收..."
        }
        if store.hasPendingAttachments {
            return "等待文件 stage"
        }
        return "独立快聊会话"
    }

    private var gatewaySummary: (title: String, detail: String?, color: Color) {
        let state = appState.openClawManager.connectionState

        if state.canRunConversation && state.capabilities.gatewayChatAvailable {
            return (
                title: "Gateway 已就绪",
                detail: state.health.lastMessage,
                color: .green
            )
        }

        if state.capabilities.gatewayReachable && state.capabilities.gatewayAuthenticated {
            return (
                title: "Gateway 已连接",
                detail: state.health.degradationReason ?? "chat 通道能力未完全就绪",
                color: .orange
            )
        }

        return (
            title: "Gateway 未就绪",
            detail: state.health.lastMessage ?? state.phase.rawValue,
            color: .red
        )
    }

    private func sendCurrentDraft() {
        guard canSubmit else { return }
        let text = draft
        draft = ""
        composerHeight = 92
        store.send(text, using: appState)
    }

    private func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        if panel.runModal() == .OK {
            store.importFiles(panel.urls)
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        let matchingProviders = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }

        guard !matchingProviders.isEmpty else { return false }

        let lock = NSLock()
        var urls: [URL] = []
        let group = DispatchGroup()

        for provider in matchingProviders {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }

                let resolvedURL: URL?
                if let data = item as? Data {
                    resolvedURL = NSURL(
                        absoluteURLWithDataRepresentation: data,
                        relativeTo: nil
                    ) as URL?
                } else if let url = item as? URL {
                    resolvedURL = url
                } else if let string = item as? String {
                    resolvedURL = URL(string: string)
                } else {
                    resolvedURL = nil
                }

                if let resolvedURL {
                    lock.lock()
                    urls.append(resolvedURL)
                    lock.unlock()
                }
            }
        }

        group.notify(queue: .main) {
            store.importFiles(urls)
        }

        return true
    }

    private func scrollToBottom(with proxy: ScrollViewProxy) {
        guard let lastMessageID = store.messages.last?.id else { return }
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.18)) {
                proxy.scrollTo(lastMessageID, anchor: .bottom)
            }
        }
    }
}

private struct QuickChatImageLightboxView: View {
    let item: QuickChatImageLightboxItem

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(item.title)
                    .font(.headline)
                Spacer(minLength: 12)
            }

            ScrollView([.horizontal, .vertical]) {
                Image(nsImage: item.image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color.black.opacity(0.92))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .padding(20)
        .frame(minWidth: 720, minHeight: 520)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private func quickChatContextPill(systemImage: String, text: String) -> some View {
    Label(text, systemImage: systemImage)
        .font(.caption)
        .lineLimit(1)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(Color(.controlBackgroundColor))
        )
}

private func quickChatStatusBanner(text: String, color: Color) -> some View {
    HStack(spacing: 8) {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
        Text(text)
            .font(.caption)
            .foregroundColor(.primary)
            .lineLimit(2)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
    .background(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(color.opacity(0.08))
    )
}
