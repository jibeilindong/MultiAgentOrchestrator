import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct QuickChatModalView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var store: QuickChatStore

    @State private var composerHeight: CGFloat = 92
    @State private var isDropTargeted = false
    @State private var lightboxItem: QuickChatImageLightboxItem?
    @State private var searchQuery: String = ""
    @State private var selectedSearchMatchIndex: Int = 0
    @State private var renamingSessionID: UUID?
    @State private var renamingSessionTitle: String = ""

    var body: some View {
        HStack(spacing: 0) {
            sessionSidebar
            Divider()
            VStack(spacing: 0) {
                header
                Divider()
                messagePane
                Divider()
                composer
            }
        }
        .frame(minWidth: 980, idealWidth: 1160, minHeight: 680, idealHeight: 820)
        .background(Color(.windowBackgroundColor))
        .padding(.top, 14)
        .sheet(item: $lightboxItem) { item in
            QuickChatImageLightboxView(item: item)
        }
        .onAppear {
            store.refreshContext(using: appState)
        }
        .onChange(of: store.selectedSessionID) { _, _ in
            composerHeight = 92
        }
        .onChange(of: searchQuery) { _, _ in
            selectedSearchMatchIndex = 0
        }
    }

    private var sessionSidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("会话")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text(sidebarSubtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Button {
                composerHeight = 92
                store.startNewSession()
            } label: {
                Label("新建会话", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(store.isSending || store.context == nil)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if store.availableSessions.isEmpty {
                        QuickChatSessionEmptyCard()
                    } else {
                        ForEach(store.availableSessions) { session in
                            QuickChatSessionRow(
                                session: session,
                                isSelected: session.id == store.selectedSessionID,
                                isRenaming: renamingSessionID == session.id,
                                draftTitle: renamingSessionTitle,
                                action: {
                                    cancelSessionRenaming()
                                    store.selectSession(session.id)
                                },
                                onRenameRequested: {
                                    beginSessionRenaming(session)
                                },
                                onRenameChanged: { renamingSessionTitle = $0 },
                                onRenameSubmitted: {
                                    commitSessionRename(for: session.id)
                                },
                                onRenameCancelled: {
                                    cancelSessionRenaming()
                                },
                                onDeleteRequested: {
                                    cancelSessionRenaming()
                                    store.deleteSession(session.id)
                                }
                            )
                        }
                    }
                }
                .padding(.vertical, 2)
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(width: 280, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
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

                VStack(alignment: .trailing, spacing: 10) {
                    messageSearchToolbar
                        .frame(width: 320)
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
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
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
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 22, height: 22)
                    Text("@")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.accentColor)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("目标 Agent")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(selectedAgentName)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: 178, alignment: .leading)
            .modifier(
                QuickChatComposerChipStyle(
                    fill: Color(nsColor: .controlBackgroundColor).opacity(0.9),
                    stroke: Color.primary.opacity(0.06),
                    isDisabled: store.isSending
                )
            )
        }
        .menuStyle(.borderlessButton)
        .disabled(store.isSending)
    }

    private var messagePane: some View {
        ScrollViewReader { proxy in
            messagePaneContent(proxy: proxy)
            .onAppear {
                scrollToRelevantMessage(with: proxy)
            }
            .onChange(of: store.messages) { _, _ in
                scrollToRelevantMessage(with: proxy)
            }
            .onChange(of: selectedSearchMatchIndex) { _, _ in
                scrollToRelevantMessage(with: proxy)
            }
            .onChange(of: normalizedSearchQuery) { _, _ in
                scrollToRelevantMessage(with: proxy)
            }
        }
    }

    private func messagePaneContent(
        proxy: ScrollViewProxy
    ) -> some View {
        messageScrollView(proxy: proxy)
    }

    private func messageScrollView(
        proxy: ScrollViewProxy
    ) -> some View {
        ScrollView {
            messageListContent
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.55))
    }

    private var messageListContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if store.messages.isEmpty {
                quickChatEmptyState
            } else {
                ForEach(store.messages) { message in
                    quickChatMessageRow(message)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func quickChatMessageRow(
        _ message: QuickChatStore.Message
    ) -> some View {
        let isSearchMatch = searchMatchIDs.contains(message.id)
        let isFocusedSearchMatch = focusedSearchMatchID == message.id

        return QuickChatMessageBubbleView(
            message: message,
            onOpenImage: { item in
                lightboxItem = item
            }
        )
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(searchMatchBackground(isSearchMatch: isSearchMatch, isFocused: isFocusedSearchMatch))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(
                    searchMatchBorderColor(isSearchMatch: isSearchMatch, isFocused: isFocusedSearchMatch),
                    lineWidth: isSearchMatch ? (isFocusedSearchMatch ? 2 : 1) : 0
                )
        )
        .animation(.easeOut(duration: 0.18), value: focusedSearchMatchID)
        .id(message.id)
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
            composerCard

            if let helperText = composerHelperText {
                HStack(spacing: 8) {
                    Image(systemName: helperIconName)
                        .font(.caption)
                        .foregroundColor(composerHelperColor)
                    Text(helperText)
                        .font(.caption)
                        .foregroundColor(composerHelperColor)
                        .lineLimit(2)
                }
                .padding(.horizontal, 4)
            }
        }
        .padding(24)
        .onPasteCommand(of: [.fileURL, .png, .tiff]) { _ in
            store.importFromPasteboard()
        }
    }

    private var composerCard: some View {
        VStack(alignment: .leading, spacing: 14) {
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

                Divider()
                    .overlay(Color.primary.opacity(0.06))
            }

            ZStack(alignment: .topLeading) {
                if draftIsEmpty && store.readyAttachmentCount == 0 {
                    Text("发一条快速消息，或直接拖入文件开始对话。")
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                }

                QuickChatGrowingTextEditor(
                    text: draftBinding,
                    dynamicHeight: $composerHeight,
                    onSubmit: sendCurrentDraft
                )
                .frame(height: composerHeight)
                .padding(.horizontal, 18)
            }
            .padding(.top, 2)

            HStack(alignment: .center, spacing: 10) {
                attachmentButton

                Spacer(minLength: 12)

                Text(sendHintText)
                    .font(.caption)
                    .foregroundColor(.secondary)

                composerSendButton
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(composerCardFillColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(
                    composerCardBorderColor,
                    lineWidth: isDropTargeted ? 1.6 : (store.isSending ? 1.2 : 1)
                )
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(composerCardOverlayColor)
                .opacity(isDropTargeted || store.isSending ? 1 : 0)
        }
        .shadow(color: composerCardShadowColor, radius: isDropTargeted ? 14 : 8, y: isDropTargeted ? 5 : 2)
        .scaleEffect(isDropTargeted ? 1.008 : 1)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: handleDrop(providers:))
        .animation(.spring(response: 0.24, dampingFraction: 0.82), value: isDropTargeted)
        .animation(.easeInOut(duration: 0.18), value: store.isSending)
    }

    private var selectedAgentName: String {
        store.agentOptions.first(where: { $0.agentID == store.selectedAgentID })?.agentName
            ?? store.context?.entryAgentName
            ?? "选择 Agent"
    }

    private var sidebarSubtitle: String {
        if let currentSessionTitle = store.availableSessions.first(where: { $0.id == store.selectedSessionID })?.title {
            return "当前：\(currentSessionTitle)"
        }
        if let agentName = store.context?.entryAgentName {
            return "为 \(agentName) 保留独立会话历史"
        }
        return "当前没有可恢复的快聊上下文"
    }

    private var draftBinding: Binding<String> {
        Binding(
            get: { store.draftText },
            set: { store.updateDraft($0) }
        )
    }

    private var canSubmit: Bool {
        let hasText = !store.draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return store.canSend && !store.hasFailedAttachments && (hasText || store.readyAttachmentCount > 0)
    }

    private var draftIsEmpty: Bool {
        store.draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var sendHintText: String {
        if store.isSending {
            return store.isStopping ? "正在停止..." : "点击停止当前输出"
        }
        if isDropTargeted {
            return "松手即可导入文件"
        }
        return "Enter 发送 · Shift+Enter 换行"
    }

    private var composerHelperText: String? {
        if let lastError = store.lastError, !lastError.isEmpty {
            return lastError
        }
        if isDropTargeted {
            return "支持拖拽本地文件到输入区，文件会先 stage 再经 Gateway 发送。"
        }
        if store.hasPendingAttachments {
            return "文件正在预上传到 Gateway，可继续编辑草稿。"
        }
        if store.readyAttachmentCount > 0 {
            return "附件已就绪，可直接发送到当前独立会话。"
        }
        return "Quick Chat 维持最轻观测与控制，优先保证回复速度与顺畅度。"
    }

    private var composerHelperColor: Color {
        if store.lastError != nil {
            return .red
        }
        if isDropTargeted {
            return .accentColor
        }
        if store.hasPendingAttachments {
            return .orange
        }
        return .secondary
    }

    private var helperIconName: String {
        if store.lastError != nil {
            return "exclamationmark.triangle.fill"
        }
        if isDropTargeted {
            return "tray.and.arrow.down.fill"
        }
        if store.hasPendingAttachments {
            return "arrow.triangle.2.circlepath"
        }
        return "bolt.fill"
    }

    private var messageSearchToolbar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                    .foregroundColor(.secondary)

                TextField("搜索当前会话消息", text: $searchQuery)
                    .textFieldStyle(.plain)

                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )

            if !normalizedSearchQuery.isEmpty {
                Text("\(searchMatchIDs.count)")
                    .font(.caption)
                    .foregroundColor(searchMatchIDs.isEmpty ? .secondary : .primary)

                HStack(spacing: 4) {
                    Button {
                        stepSearchMatch(delta: -1)
                    } label: {
                        Image(systemName: "chevron.up")
                    }
                    .buttonStyle(.borderless)
                    .disabled(searchMatchIDs.isEmpty)

                    Button {
                        stepSearchMatch(delta: 1)
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .buttonStyle(.borderless)
                    .disabled(searchMatchIDs.isEmpty)
                }
            }

            Spacer(minLength: 0)
        }
    }

    private var composerSendButton: some View {
        Button {
            if store.isSending {
                store.stop(using: appState)
            } else {
                sendCurrentDraft()
            }
        } label: {
            Image(systemName: store.isSending ? "stop.fill" : "paperplane.fill")
                .font(.headline)
                .foregroundColor(.white)
                .frame(width: 38, height: 38)
                .background(store.isSending ? Color.black : Color.accentColor)
                .overlay {
                    Circle()
                        .stroke((store.isSending ? Color.black : Color.accentColor).opacity(0.22), lineWidth: 5)
                        .scaleEffect(store.isSending ? 1.16 : 0.92)
                        .opacity(store.isSending ? 1 : 0)
                }
        }
        .buttonStyle(
            QuickChatSendButtonStyle(
                isDisabled: store.isSending ? store.isStopping : !canSubmit
            )
        )
        .clipShape(Circle())
        .disabled(store.isSending ? store.isStopping : !canSubmit)
        .animation(.spring(response: 0.24, dampingFraction: 0.72), value: store.isSending)
    }

    private var attachmentButton: some View {
        Button {
            presentOpenPanel()
        } label: {
            composerControlCircle(systemImage: "paperclip")
        }
        .buttonStyle(.plain)
        .help("导入附件")
    }

    private func composerControlCircle(systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.body.weight(.medium))
            .foregroundColor(.secondary)
            .frame(width: 30, height: 30)
            .background(
                Circle()
                    .fill(Color.primary.opacity(0.05))
            )
            .overlay(
                Circle()
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
    }

    private var composerCardFillColor: Color {
        if isDropTargeted {
            return Color.accentColor.opacity(0.045)
        }
        if store.isSending {
            return Color.accentColor.opacity(0.02)
        }
        return Color(nsColor: .textBackgroundColor)
    }

    private var composerCardBorderColor: Color {
        if isDropTargeted {
            return .accentColor
        }
        if store.isSending {
            return Color.accentColor.opacity(0.24)
        }
        return Color.primary.opacity(0.08)
    }

    private var composerCardOverlayColor: Color {
        if isDropTargeted {
            return Color.accentColor.opacity(0.04)
        }
        return Color.accentColor.opacity(0.015)
    }

    private var composerCardShadowColor: Color {
        if isDropTargeted {
            return Color.accentColor.opacity(0.14)
        }
        if store.isSending {
            return Color.accentColor.opacity(0.08)
        }
        return Color.black.opacity(0.04)
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

    private var normalizedSearchQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var searchMatchIDs: [UUID] {
        guard !normalizedSearchQuery.isEmpty else { return [] }
        return store.messages.compactMap { message in
            message.plainText.localizedCaseInsensitiveContains(normalizedSearchQuery) ? message.id : nil
        }
    }

    private var focusedSearchMatchID: UUID? {
        guard !searchMatchIDs.isEmpty else { return nil }
        let safeIndex = min(max(selectedSearchMatchIndex, 0), searchMatchIDs.count - 1)
        return searchMatchIDs[safeIndex]
    }

    private func searchMatchBackground(
        isSearchMatch: Bool,
        isFocused: Bool
    ) -> some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(searchMatchFillColor(isSearchMatch: isSearchMatch, isFocused: isFocused))
    }

    private func searchMatchFillColor(
        isSearchMatch: Bool,
        isFocused: Bool
    ) -> Color {
        guard isSearchMatch else {
            return .clear
        }
        return isFocused ? Color.accentColor.opacity(0.09) : Color.accentColor.opacity(0.04)
    }

    private func searchMatchBorderColor(
        isSearchMatch: Bool,
        isFocused: Bool
    ) -> Color {
        guard isSearchMatch else {
            return .clear
        }
        return isFocused ? Color.accentColor.opacity(0.7) : Color.accentColor.opacity(0.28)
    }

    private func sendCurrentDraft() {
        guard canSubmit else { return }
        let text = store.draftText
        store.updateDraft("")
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

    private func beginSessionRenaming(_ session: QuickChatStore.SessionSummary) {
        renamingSessionID = session.id
        renamingSessionTitle = session.isCustomTitle ? session.title : ""
    }

    private func cancelSessionRenaming() {
        renamingSessionID = nil
        renamingSessionTitle = ""
    }

    private func commitSessionRename(for sessionID: UUID) {
        let normalizedTitle = renamingSessionTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else {
            cancelSessionRenaming()
            return
        }
        store.renameSession(sessionID, title: normalizedTitle)
        cancelSessionRenaming()
    }

    private func stepSearchMatch(delta: Int) {
        guard !searchMatchIDs.isEmpty else { return }
        let nextIndex = (selectedSearchMatchIndex + delta + searchMatchIDs.count) % searchMatchIDs.count
        selectedSearchMatchIndex = nextIndex
    }

    private func scrollToRelevantMessage(with proxy: ScrollViewProxy) {
        if let focusedSearchMatchID {
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo(focusedSearchMatchID, anchor: .center)
                }
            }
            return
        }

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

private struct QuickChatSessionRow: View {
    let session: QuickChatStore.SessionSummary
    let isSelected: Bool
    let isRenaming: Bool
    let draftTitle: String
    let action: () -> Void
    let onRenameRequested: () -> Void
    let onRenameChanged: (String) -> Void
    let onRenameSubmitted: () -> Void
    let onRenameCancelled: () -> Void
    let onDeleteRequested: () -> Void

    @State private var isHovered = false
    @State private var isTrailingHover = false
    @FocusState private var isRenameFieldFocused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    if isRenaming {
                        TextField("会话名称", text: Binding(
                            get: { draftTitle },
                            set: onRenameChanged
                        ))
                        .textFieldStyle(.roundedBorder)
                        .font(.subheadline)
                        .onSubmit(onRenameSubmitted)
                        .focused($isRenameFieldFocused)
                        .onAppear {
                            DispatchQueue.main.async {
                                isRenameFieldFocused = true
                            }
                        }
                        .onChange(of: isRenameFieldFocused) { _, isFocused in
                            if !isFocused && isRenaming {
                                onRenameCancelled()
                            }
                        }
                    } else {
                        Text(session.title)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    if !isRenaming {
                        Text("\(session.messageCount)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                Text(session.preview)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.14) : Color(nsColor: .windowBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.08), lineWidth: 1)
            )

            if !isRenaming {
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 28, height: 32)
                    .contentShape(Rectangle())
                    .overlay {
                        if isTrailingHover {
                            Button(role: .destructive, action: onDeleteRequested) {
                                Image(systemName: "trash")
                                    .font(.caption)
                                    .foregroundColor(.red.opacity(0.88))
                                    .frame(width: 28, height: 28)
                                    .background(
                                        Circle()
                                            .fill(Color.red.opacity(0.1))
                                    )
                            }
                            .buttonStyle(.plain)
                            .transition(.opacity.combined(with: .scale(scale: 0.92)))
                        }
                    }
                    .onHover { hovered in
                        isTrailingHover = hovered
                    }
                    .animation(.easeInOut(duration: 0.14), value: isTrailingHover)
                    .opacity(isHovered || isTrailingHover ? 1 : 0.001)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isRenaming else { return }
            action()
        }
        .onTapGesture(count: 2) {
            guard !isRenaming else { return }
            onRenameRequested()
        }
        .onHover { isHovered = $0 }
    }
}

private struct QuickChatSessionEmptyCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("还没有历史会话")
                .font(.subheadline)
                .fontWeight(.semibold)
            Text("发送第一条消息后，这里会为当前 Agent 保留会话历史。")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
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

private struct QuickChatComposerChipStyle: ViewModifier {
    let fill: Color
    let stroke: Color
    let isDisabled: Bool

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(fill.opacity(isDisabled ? 0.55 : 1))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(stroke.opacity(isDisabled ? 0.55 : 1), lineWidth: 1)
            )
            .opacity(isDisabled ? 0.72 : 1)
    }
}

private struct QuickChatSendButtonStyle: ButtonStyle {
    let isDisabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .brightness(configuration.isPressed ? -0.04 : 0)
            .shadow(
                color: isDisabled ? .clear : Color.black.opacity(configuration.isPressed ? 0.06 : 0.12),
                radius: configuration.isPressed ? 4 : 8,
                y: configuration.isPressed ? 1 : 3
            )
            .opacity(isDisabled ? 0.55 : 1)
            .animation(.spring(response: 0.18, dampingFraction: 0.78), value: configuration.isPressed)
    }
}
