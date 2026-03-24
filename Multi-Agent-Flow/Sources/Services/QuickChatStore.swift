import Foundation
import Combine

@MainActor
final class QuickChatStore: ObservableObject {
    enum MessageRole: String {
        case user
        case assistant
        case system
    }

    struct Message: Identifiable, Equatable {
        let id: UUID
        let role: MessageRole
        var text: String
        var createdAt: Date
        var isStreaming: Bool

        init(
            id: UUID = UUID(),
            role: MessageRole,
            text: String,
            createdAt: Date = Date(),
            isStreaming: Bool = false
        ) {
            self.id = id
            self.role = role
            self.text = text
            self.createdAt = createdAt
            self.isStreaming = isStreaming
        }
    }

    @Published var isPresented = false
    @Published private(set) var context: AppState.QuickChatContext?
    @Published private(set) var messages: [Message] = []
    @Published private(set) var sessionKey: String = ""
    @Published private(set) var activeRunID: String?
    @Published private(set) var isSending = false
    @Published private(set) var isStopping = false
    @Published private(set) var lastError: String?
    @Published private(set) var statusMessage: String?

    private var sendTask: _Concurrency.Task<Void, Never>?
    private var pendingAbortAfterRunStart = false

    var canSend: Bool {
        context != nil && !isSending
    }

    func present(using appState: AppState) {
        isPresented = true
        refreshContext(using: appState)
    }

    func handleDismiss(using appState: AppState) {
        isPresented = false
        if isSending {
            stop(using: appState)
        }
    }

    func refreshContext(using appState: AppState) {
        let previousContext = context
        context = appState.resolveQuickChatContext()

        guard let context else {
            if messages.isEmpty {
                statusMessage = nil
                sessionKey = ""
                lastError = "当前工作流没有可用于 Quick Chat 的 Agent。请先在工作流中连接一个入口 Agent。"
            }
            return
        }

        lastError = nil
        if sessionKey.isEmpty || previousContext?.workflowID != context.workflowID || previousContext?.entryAgentID != context.entryAgentID {
            resetConversation(statusMessage: "已切换到 \(context.workflowName) / \(context.entryAgentName) 的独立快聊会话。")
        }
    }

    func clearError() {
        lastError = nil
    }

    func startNewSession() {
        guard !isSending else { return }
        resetConversation(statusMessage: "已创建新的 Quick Chat 会话。")
    }

    func send(_ text: String, using appState: AppState) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        refreshContext(using: appState)
        guard let context else { return }

        let connectionConfig = appState.openClawManager.config
        guard let gatewayConfig = appState.openClawManager.preferredGatewayConfig(using: connectionConfig) else {
            lastError = "当前 OpenClaw 没有可用的 gateway chat 通道，Quick Chat 无法直接发送。"
            return
        }

        guard !isSending else { return }

        let userMessage = Message(role: .user, text: trimmedText)
        let assistantMessageID = UUID()
        messages.append(userMessage)
        messages.append(Message(id: assistantMessageID, role: .assistant, text: "", isStreaming: true))

        let resolvedSessionKey = sessionKey.isEmpty ? Self.makeSessionKey(for: context) : sessionKey
        sessionKey = resolvedSessionKey
        activeRunID = nil
        pendingAbortAfterRunStart = false
        lastError = nil
        statusMessage = nil
        isSending = true
        isStopping = false

        sendTask?.cancel()
        sendTask = _Concurrency.Task { [weak self] in
            guard let self else { return }
            let store = self

            do {
                let result = try await appState.openClawManager.executeGatewayChatCommand(
                    message: trimmedText,
                    sessionKey: resolvedSessionKey,
                    thinkingLevel: .off,
                    timeoutSeconds: 120,
                    using: gatewayConfig,
                    onRunStarted: { runID, acceptedSessionKey in
                        _Concurrency.Task { @MainActor in
                            store.activeRunID = runID
                            store.sessionKey = acceptedSessionKey
                            if store.pendingAbortAfterRunStart {
                                store.requestAbort(using: appState)
                            }
                        }
                    },
                    onAssistantTextUpdated: { text in
                        _Concurrency.Task { @MainActor in
                            store.updateAssistantMessage(
                                withID: assistantMessageID,
                                text: text,
                                isStreaming: true
                            )
                        }
                    }
                )

                await MainActor.run {
                    store.finishSend(
                        result: result,
                        assistantMessageID: assistantMessageID
                    )
                }
            } catch is CancellationError {
                await MainActor.run {
                    store.isSending = false
                    store.isStopping = false
                    store.pendingAbortAfterRunStart = false
                    store.activeRunID = nil
                    store.finalizeAssistantMessage(withID: assistantMessageID)
                }
            } catch {
                await MainActor.run {
                    store.lastError = error.localizedDescription
                    store.isSending = false
                    store.isStopping = false
                    store.pendingAbortAfterRunStart = false
                    store.activeRunID = nil
                    store.finalizeAssistantMessage(withID: assistantMessageID)
                    if store.text(for: assistantMessageID).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        store.updateAssistantMessage(
                            withID: assistantMessageID,
                            text: "请求失败：\(error.localizedDescription)",
                            isStreaming: false
                        )
                    }
                }
            }
        }
    }

    func stop(using appState: AppState) {
        guard isSending else { return }
        guard !isStopping else { return }

        pendingAbortAfterRunStart = true
        isStopping = true
        statusMessage = "正在请求停止当前输出..."
        requestAbort(using: appState)
    }

    private func requestAbort(using appState: AppState) {
        guard pendingAbortAfterRunStart else { return }
        guard let runID = activeRunID,
              !runID.isEmpty,
              !sessionKey.isEmpty else {
            return
        }

        let connectionConfig = appState.openClawManager.config
        guard let gatewayConfig = appState.openClawManager.preferredGatewayConfig(using: connectionConfig) else {
            lastError = "当前没有可用于 stop 的 gateway 通道。"
            isStopping = false
            return
        }

        _Concurrency.Task { [weak self] in
            guard let self else { return }
            do {
                try await appState.openClawManager.abortGatewayChatRun(
                    sessionKey: self.sessionKey,
                    runID: runID,
                    using: gatewayConfig
                )
            } catch {
                await MainActor.run {
                    self.lastError = error.localizedDescription
                    self.isStopping = false
                }
            }
        }
    }

    private func finishSend(
        result: OpenClawGatewayClient.AgentExecutionResult,
        assistantMessageID: UUID
    ) {
        isSending = false
        isStopping = false
        pendingAbortAfterRunStart = false
        activeRunID = nil
        sendTask = nil

        if let resolvedSessionKey = result.sessionKey,
           !resolvedSessionKey.isEmpty {
            sessionKey = resolvedSessionKey
        }

        let finalText = result.assistantText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !finalText.isEmpty {
            updateAssistantMessage(
                withID: assistantMessageID,
                text: finalText,
                isStreaming: false
            )
        } else {
            finalizeAssistantMessage(withID: assistantMessageID)
        }

        switch result.status {
        case "ok":
            statusMessage = nil
            if text(for: assistantMessageID).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                updateAssistantMessage(
                    withID: assistantMessageID,
                    text: "本次对话已完成，但没有返回可显示内容。",
                    isStreaming: false
                )
            }
        case "aborted":
            statusMessage = "当前输出已停止。"
            if text(for: assistantMessageID).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                updateAssistantMessage(
                    withID: assistantMessageID,
                    text: "已停止当前输出。",
                    isStreaming: false
                )
            }
        default:
            let message = result.errorMessage?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let message, !message.isEmpty {
                lastError = message
            } else {
                lastError = "Quick Chat 执行失败，状态：\(result.status)"
            }
        }
    }

    private func resetConversation(statusMessage: String?) {
        sendTask?.cancel()
        messages = []
        sessionKey = context.map(Self.makeSessionKey(for:)) ?? ""
        activeRunID = nil
        isSending = false
        isStopping = false
        pendingAbortAfterRunStart = false
        lastError = nil
        self.statusMessage = statusMessage
    }

    private func updateAssistantMessage(
        withID messageID: UUID,
        text: String,
        isStreaming: Bool
    ) {
        guard let index = messages.firstIndex(where: { $0.id == messageID }) else { return }
        messages[index].text = text
        messages[index].isStreaming = isStreaming
    }

    private func finalizeAssistantMessage(withID messageID: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == messageID }) else { return }
        messages[index].isStreaming = false
    }

    private func text(for messageID: UUID) -> String {
        messages.first(where: { $0.id == messageID })?.text ?? ""
    }

    private static func makeSessionKey(for context: AppState.QuickChatContext) -> String {
        let project = context.projectID.uuidString.lowercased()
        let workflow = context.workflowID.uuidString.lowercased()
        let session = UUID().uuidString.lowercased()
        return "quick-chat:\(project):\(workflow):\(session)"
    }
}
