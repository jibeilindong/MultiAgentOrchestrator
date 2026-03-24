import SwiftUI
import AppKit

struct QuickChatModalView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var store: QuickChatStore

    @State private var draft: String = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            messagePane
            Divider()
            composer
        }
        .frame(minWidth: 760, idealWidth: 860, minHeight: 560, idealHeight: 680)
        .background(Color(.windowBackgroundColor))
        .onAppear {
            store.refreshContext(using: appState)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "bolt.bubble.fill")
                            .foregroundColor(.accentColor)
                        Text("Quick Chat")
                            .font(.title3)
                            .fontWeight(.semibold)
                    }

                    Text("轻量弹窗会话，不进入 Workbench 主控制链路。")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer(minLength: 12)

                HStack(spacing: 8) {
                    Button("新会话") {
                        draft = ""
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

            if let context = store.context {
                HStack(spacing: 8) {
                    quickChatContextPill(systemImage: "square.grid.2x2", text: context.workflowName)
                    quickChatContextPill(systemImage: "person.crop.circle", text: context.entryAgentName)
                    quickChatContextPill(systemImage: "shippingbox", text: context.projectName)
                }
            } else {
                Text("当前没有可用的快聊上下文。")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
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

    private var messagePane: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if store.messages.isEmpty {
                        quickChatEmptyState
                    } else {
                        ForEach(store.messages) { message in
                            QuickChatMessageBubble(message: message)
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
                Text("当前会话会直连 `\(context.entryAgentName)`，并使用独立 session key，不写入 Workbench 主线程。")
                    .foregroundColor(.secondary)
            } else {
                Text("请先在当前项目里准备一个带入口 Agent 的工作流，Quick Chat 才能直接启动。")
                    .foregroundColor(.secondary)
            }

            Text("适合先问、先试、先拿建议；正式运行和深度观测仍然放在 Workbench。")
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
        VStack(spacing: 12) {
            HStack(alignment: .bottom, spacing: 12) {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))

                    if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("输入想快速聊的问题，发送会直接走轻量 chat 路径。")
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                    }

                    TextEditor(text: $draft)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .frame(minHeight: 96, maxHeight: 140)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )

                VStack(spacing: 10) {
                    Button {
                        sendCurrentDraft()
                    } label: {
                        Label(store.isSending ? "发送中" : "发送", systemImage: "paperplane.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!store.canSend || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Text(store.isSending ? "正在流式接收..." : "独立快聊会话")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }
                .frame(width: 128)
            }

            HStack {
                Text("Quick Chat 优先保证速度和顺滑度，不承担正式 run 控制。")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer(minLength: 12)

                Text("建议长度：1-3 段")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(20)
    }

    private func sendCurrentDraft() {
        let text = draft
        draft = ""
        store.send(text, using: appState)
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

private struct QuickChatMessageBubble: View {
    let message: QuickChatStore.Message

    private var isUser: Bool {
        message.role == .user
    }

    var body: some View {
        HStack {
            if isUser {
                Spacer(minLength: 56)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(isUser ? "你" : "Assistant")
                        .font(.caption)
                        .fontWeight(.semibold)
                    if message.isStreaming {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                Text(message.text.isEmpty && message.isStreaming ? "正在生成内容..." : message.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .background(bubbleBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.primary.opacity(isUser ? 0.0 : 0.08), lineWidth: 1)
            )

            if !isUser {
                Spacer(minLength: 56)
            }
        }
    }

    private var bubbleBackground: some ShapeStyle {
        if isUser {
            return AnyShapeStyle(Color.accentColor.opacity(0.16))
        }
        return AnyShapeStyle(Color(nsColor: .controlBackgroundColor))
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
