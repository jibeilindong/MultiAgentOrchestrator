import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

@MainActor
final class QuickChatStore: ObservableObject {
    enum MessageRole: String {
        case user
        case assistant
        case toolResult = "tool_result"
        case system

        var title: String {
            switch self {
            case .user:
                return "你"
            case .assistant:
                return "Assistant"
            case .toolResult:
                return "Tool Result"
            case .system:
                return "System"
            }
        }
    }

    enum AttachmentStageState: Equatable {
        case staging
        case ready
        case failed(String)

        var isReady: Bool {
            if case .ready = self {
                return true
            }
            return false
        }
    }

    struct AttachmentSnapshot: Identifiable, Equatable {
        let id: UUID
        let fileName: String
        let mimeType: String
        let fileSize: Int64
        let stagedURL: URL
        let previewData: Data?

        var isImage: Bool {
            mimeType.lowercased().hasPrefix("image/")
        }
    }

    struct Attachment: Identifiable, Equatable {
        let id: UUID
        let originalURL: URL?
        var fileName: String
        var mimeType: String
        var fileSize: Int64
        var stagedURL: URL?
        var previewData: Data?
        var base64Content: String?
        var stageState: AttachmentStageState

        var isImage: Bool {
            mimeType.lowercased().hasPrefix("image/")
        }

        var isReady: Bool {
            stageState.isReady && stagedURL != nil && base64Content != nil
        }

        var stageStatusText: String {
            switch stageState {
            case .staging:
                return "Stage 中"
            case .ready:
                return "已就绪"
            case .failed:
                return "失败"
            }
        }

        var errorDescription: String? {
            if case .failed(let message) = stageState {
                return message
            }
            return nil
        }

        var snapshot: AttachmentSnapshot? {
            guard let stagedURL else { return nil }
            return AttachmentSnapshot(
                id: id,
                fileName: fileName,
                mimeType: mimeType,
                fileSize: fileSize,
                stagedURL: stagedURL,
                previewData: previewData
            )
        }

        var gatewayAttachment: OpenClawGatewayClient.ChatAttachment? {
            guard let base64Content, isReady else { return nil }
            return OpenClawGatewayClient.ChatAttachment(
                type: isImage ? "image" : "file",
                mimeType: mimeType,
                fileName: fileName,
                contentBase64: base64Content
            )
        }
    }

    struct MessageContentBlock: Identifiable, Equatable {
        enum Kind: String {
            case text
            case thinking
            case image
            case toolUse = "tool_use"
            case toolResult = "tool_result"
        }

        let id: UUID
        let kind: Kind
        var text: String?
        var language: String?
        var imageURL: URL?
        var imagePreviewData: Data?
        var imageMimeType: String?
        var imageByteCount: Int?
        var imageDataOmitted: Bool
        var toolName: String?
        var toolArguments: String?
        var toolOutput: String?

        init(
            id: UUID = UUID(),
            kind: Kind,
            text: String? = nil,
            language: String? = nil,
            imageURL: URL? = nil,
            imagePreviewData: Data? = nil,
            imageMimeType: String? = nil,
            imageByteCount: Int? = nil,
            imageDataOmitted: Bool = false,
            toolName: String? = nil,
            toolArguments: String? = nil,
            toolOutput: String? = nil
        ) {
            self.id = id
            self.kind = kind
            self.text = text
            self.language = language
            self.imageURL = imageURL
            self.imagePreviewData = imagePreviewData
            self.imageMimeType = imageMimeType
            self.imageByteCount = imageByteCount
            self.imageDataOmitted = imageDataOmitted
            self.toolName = toolName
            self.toolArguments = toolArguments
            self.toolOutput = toolOutput
        }
    }

    struct Message: Identifiable, Equatable {
        let id: UUID
        let role: MessageRole
        var blocks: [MessageContentBlock]
        var attachments: [AttachmentSnapshot]
        var createdAt: Date
        var isStreaming: Bool

        init(
            id: UUID = UUID(),
            role: MessageRole,
            blocks: [MessageContentBlock],
            attachments: [AttachmentSnapshot] = [],
            createdAt: Date = Date(),
            isStreaming: Bool = false
        ) {
            self.id = id
            self.role = role
            self.blocks = blocks
            self.attachments = attachments
            self.createdAt = createdAt
            self.isStreaming = isStreaming
        }

        var plainText: String {
            var parts = blocks.compactMap { block -> String? in
                switch block.kind {
                case .text, .thinking:
                    return block.text
                case .toolUse:
                    let name = block.toolName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "tool"
                    let arguments = block.toolArguments?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    return arguments.isEmpty ? name : "\(name)\n\(arguments)"
                case .toolResult:
                    return block.toolOutput ?? block.text
                case .image:
                    return block.text
                }
            }

            let attachmentNames = attachments.map(\.fileName)
            parts.append(contentsOf: attachmentNames)
            return parts
                .joined(separator: "\n\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    struct SessionSummary: Identifiable, Equatable {
        let id: UUID
        let title: String
        let preview: String
        let updatedAt: Date
        let messageCount: Int
        let isCustomTitle: Bool
    }

    private struct ContextKey: Hashable {
        let projectID: UUID
        let workflowID: UUID
        let agentID: UUID
    }

    private struct SessionRecord {
        let id: UUID
        let context: AppState.QuickChatContext
        let createdAt: Date
        var updatedAt: Date
        var customTitle: String?
        var sessionKey: String
        var messages: [Message]
        var attachments: [Attachment]
        var draftText: String
    }

    private struct PreparedAttachment {
        let stagedURL: URL
        let fileName: String
        let mimeType: String
        let fileSize: Int64
        let previewData: Data?
        let base64Content: String
    }

    private nonisolated static let maxAttachmentBytes = 5_000_000

    @Published var isPresented = false
    @Published private(set) var context: AppState.QuickChatContext?
    @Published private(set) var agentOptions: [AppState.QuickChatAgentOption] = []
    @Published private(set) var selectedAgentID: UUID?
    @Published private(set) var selectedSessionID: UUID?
    @Published private(set) var availableSessions: [SessionSummary] = []
    @Published private(set) var messages: [Message] = []
    @Published private(set) var attachments: [Attachment] = []
    @Published private(set) var draftText: String = ""
    @Published private(set) var sessionKey: String = ""
    @Published private(set) var activeRunID: String?
    @Published private(set) var isSending = false
    @Published private(set) var isStopping = false
    @Published private(set) var lastError: String?
    @Published private(set) var statusMessage: String?

    private var sendTask: _Concurrency.Task<Void, Never>?
    private var pendingAbortAfterRunStart = false
    private var attachmentTasks: [UUID: (sessionID: UUID, task: _Concurrency.Task<Void, Never>)] = [:]
    private var sessionsByContext: [ContextKey: [SessionRecord]] = [:]
    private var sessionContextByID: [UUID: ContextKey] = [:]
    private var activeSessionIDByContext: [ContextKey: UUID] = [:]

    var canSend: Bool {
        context != nil && !isSending && !hasPendingAttachments
    }

    var hasPendingAttachments: Bool {
        attachments.contains { attachment in
            if case .staging = attachment.stageState {
                return true
            }
            return false
        }
    }

    var hasFailedAttachments: Bool {
        attachments.contains { attachment in
            if case .failed = attachment.stageState {
                return true
            }
            return false
        }
    }

    var readyAttachmentCount: Int {
        attachments.filter(\.isReady).count
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
        saveCurrentSessionSnapshot()

        let previousContext = context
        let previousContextKey = previousContext.map(Self.contextKey(for:))

        agentOptions = appState.resolveQuickChatAgentOptions()

        guard !agentOptions.isEmpty else {
            clearPresentedSessionState()
            context = nil
            selectedAgentID = nil
            statusMessage = nil
            lastError = "当前工作流没有可用于 Quick Chat 的 Agent。请先在工作流中连接一个入口 Agent。"
            return
        }

        if let selectedAgentID,
           agentOptions.contains(where: { $0.agentID == selectedAgentID }) {
            self.selectedAgentID = selectedAgentID
        } else {
            self.selectedAgentID = agentOptions.first?.agentID
        }

        context = agentOptions.first(where: { $0.agentID == selectedAgentID })?.context
            ?? agentOptions.first?.context

        selectedSessionID = nil
        lastError = nil

        guard let context else { return }
        let currentContextKey = Self.contextKey(for: context)
        let sessionID = activeSessionIDByContext[currentContextKey]
            ?? sessionsByContext[currentContextKey]?.last?.id
            ?? createSession(for: context)
        bindSession(
            withID: sessionID,
            statusMessage: previousContextKey == currentContextKey
                ? nil
                : "已切换到 \(context.workflowName) / \(context.entryAgentName) 的独立快聊会话。"
        )
    }

    func selectAgent(_ agentID: UUID, using appState: AppState) {
        guard !isSending else { return }
        guard selectedAgentID != agentID else { return }
        selectedAgentID = agentID
        refreshContext(using: appState)
    }

    func selectSession(_ sessionID: UUID) {
        guard !isSending else { return }
        guard selectedSessionID != sessionID else { return }
        saveCurrentSessionSnapshot()
        bindSession(withID: sessionID, statusMessage: "已恢复该 Agent 的历史会话。")
    }

    func updateDraft(_ text: String) {
        draftText = text
        saveCurrentSessionSnapshot(touch: false)
    }

    func clearError() {
        lastError = nil
    }

    func startNewSession() {
        guard !isSending else { return }
        guard let context else { return }
        saveCurrentSessionSnapshot()
        let sessionID = createSession(for: context)
        bindSession(
            withID: sessionID,
            statusMessage: "已创建新的 Quick Chat 会话。"
        )
    }

    func renameSession(_ sessionID: UUID, title: String) {
        guard !isSending else { return }
        let normalizedTitle = Self.normalizedNonEmptyText(title)
        mutateSession(withID: sessionID, touch: true) { record in
            record.customTitle = normalizedTitle
        }
        if selectedSessionID == sessionID {
            statusMessage = normalizedTitle == nil ? "已恢复默认会话名称。" : "已更新会话名称。"
        }
    }

    func deleteSession(_ sessionID: UUID) {
        guard !isSending else { return }
        guard let contextKey = sessionContextByID[sessionID],
              var records = sessionsByContext[contextKey],
              let recordIndex = records.firstIndex(where: { $0.id == sessionID }) else {
            return
        }

        let removedRecord = records.remove(at: recordIndex)
        sessionContextByID.removeValue(forKey: sessionID)

        for attachmentID in attachmentTasks.compactMap({ key, value in
            value.sessionID == sessionID ? key : nil
        }) {
            attachmentTasks[attachmentID]?.task.cancel()
            attachmentTasks.removeValue(forKey: attachmentID)
        }

        if records.isEmpty {
            sessionsByContext[contextKey] = []
            activeSessionIDByContext.removeValue(forKey: contextKey)

            let replacementID = createSession(for: removedRecord.context)
            if context.map(Self.contextKey(for:)) == Self.contextKey(for: removedRecord.context) {
                bindSession(withID: replacementID, statusMessage: "已删除会话，并创建新的空白会话。")
            } else {
                refreshAvailableSessions()
            }
            return
        }

        sessionsByContext[contextKey] = records
        let fallbackSessionID = records
            .sorted { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return lhs.createdAt > rhs.createdAt
            }
            .first?
            .id

        if activeSessionIDByContext[contextKey] == sessionID {
            activeSessionIDByContext[contextKey] = fallbackSessionID
        }

        if selectedSessionID == sessionID, let fallbackSessionID {
            bindSession(withID: fallbackSessionID, statusMessage: "已删除当前会话。")
        } else {
            refreshAvailableSessions()
        }
    }

    func removeAttachment(_ attachmentID: UUID) {
        attachmentTasks[attachmentID]?.task.cancel()
        attachmentTasks.removeValue(forKey: attachmentID)
        attachments.removeAll { $0.id == attachmentID }
        saveCurrentSessionSnapshot()
    }

    func clearAttachments() {
        guard let sessionID = selectedSessionID else {
            attachments.removeAll()
            return
        }
        let attachmentIDs = attachments.map(\.id)
        for attachmentID in attachmentIDs {
            guard let taskRecord = attachmentTasks[attachmentID] else { continue }
            guard taskRecord.sessionID == sessionID else { continue }
            taskRecord.task.cancel()
            attachmentTasks.removeValue(forKey: attachmentID)
        }
        attachments.removeAll()
        saveCurrentSessionSnapshot()
    }

    func importFiles(_ urls: [URL]) {
        let fileURLs = urls.filter { $0.isFileURL }
        guard !fileURLs.isEmpty else { return }

        let existingOriginalPaths = Set(
            attachments.compactMap { attachment in
                attachment.originalURL?.standardizedFileURL.path
            }
        )

        for url in fileURLs {
            let standardizedURL = url.standardizedFileURL
            if existingOriginalPaths.contains(standardizedURL.path) {
                continue
            }
            stageAttachment(from: standardizedURL)
        }
    }

    func importImageData(
        _ data: Data,
        fileName: String,
        mimeType: String = "image/png"
    ) {
        stageBufferedAttachment(
            data,
            fileName: fileName,
            mimeType: mimeType
        )
    }

    func importFromPasteboard() {
        let pasteboard = NSPasteboard.general

        if let fileURLs = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL],
           !fileURLs.isEmpty
        {
            importFiles(fileURLs)
            return
        }

        if let pngData = pasteboard.data(forType: .png), !pngData.isEmpty {
            importImageData(
                pngData,
                fileName: "pasted-image-\(Self.timestampFileComponent()).png",
                mimeType: "image/png"
            )
            return
        }

        if let tiffData = pasteboard.data(forType: .tiff),
           let bitmap = NSBitmapImageRep(data: tiffData),
           let pngData = bitmap.representation(using: .png, properties: [:])
        {
            importImageData(
                pngData,
                fileName: "pasted-image-\(Self.timestampFileComponent()).png",
                mimeType: "image/png"
            )
            return
        }

        if let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let image = images.first,
           let tiffData = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let pngData = bitmap.representation(using: .png, properties: [:])
        {
            importImageData(
                pngData,
                fileName: "pasted-image-\(Self.timestampFileComponent()).png",
                mimeType: "image/png"
            )
            return
        }

        lastError = "剪贴板里没有可导入的文件或图片。"
    }

    func send(_ text: String, using appState: AppState) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let readyAttachments = attachments.filter(\.isReady)
        guard let activeSessionID = selectedSessionID else { return }

        guard !trimmedText.isEmpty || !readyAttachments.isEmpty else { return }

        if hasPendingAttachments {
            lastError = "有附件仍在 stage，请稍候发送。"
            return
        }

        if hasFailedAttachments {
            lastError = "请先移除失败的附件，或重新导入后再发送。"
            return
        }

        refreshContext(using: appState)
        guard let context else { return }

        let connectionConfig = appState.openClawManager.config
        guard let gatewayConfig = appState.openClawManager.preferredGatewayConfig(using: connectionConfig) else {
            lastError = "当前 OpenClaw 没有可用的 gateway chat 通道，Quick Chat 无法直接发送。"
            return
        }

        guard !isSending else { return }

        let attachmentSnapshots = readyAttachments.compactMap(\.snapshot)
        let userMessage = Message(
            role: .user,
            blocks: messageBlocks(fromText: trimmedText),
            attachments: attachmentSnapshots
        )
        let assistantMessageID = UUID()
        messages.append(userMessage)
        messages.append(
            Message(
                id: assistantMessageID,
                role: .assistant,
                blocks: [],
                createdAt: Date(),
                isStreaming: true
            )
        )
        saveCurrentSessionSnapshot()

        let gatewayAttachments = readyAttachments.compactMap(\.gatewayAttachment)
        attachments = []
        draftText = ""

        let resolvedSessionKey = sessionKey.isEmpty ? Self.makeSessionKey(for: context) : sessionKey
        sessionKey = resolvedSessionKey
        activeRunID = nil
        pendingAbortAfterRunStart = false
        lastError = nil
        statusMessage = gatewayAttachments.isEmpty
            ? nil
            : "附件已完成 stage，准备经 Gateway 发送。"
        isSending = true
        isStopping = false
        saveCurrentSessionSnapshot()

        sendTask?.cancel()
        sendTask = _Concurrency.Task { [weak self] in
            guard let self else { return }

            do {
                let result = try await appState.openClawManager.executeGatewayChatCommand(
                    message: trimmedText,
                    sessionKey: resolvedSessionKey,
                    attachments: gatewayAttachments,
                    thinkingLevel: .off,
                    timeoutSeconds: 120,
                    using: gatewayConfig,
                    onRunStarted: { runID, acceptedSessionKey in
                        _Concurrency.Task { @MainActor in
                            guard self.selectedSessionID == activeSessionID else { return }
                            self.activeRunID = runID
                            self.sessionKey = acceptedSessionKey
                            self.saveCurrentSessionSnapshot()
                            if self.pendingAbortAfterRunStart {
                                self.requestAbort(using: appState)
                            }
                        }
                    },
                    onAssistantTextUpdated: { text in
                        _Concurrency.Task { @MainActor in
                            self.updateAssistantMessage(
                                in: activeSessionID,
                                withID: assistantMessageID,
                                text: text,
                                isStreaming: true
                            )
                        }
                    }
                )

                await MainActor.run {
                    self.finishSend(
                        in: activeSessionID,
                        result: result,
                        assistantMessageID: assistantMessageID
                    )
                }

                let refreshedSessionKey = result.sessionKey ?? resolvedSessionKey
                if result.status == "ok" || result.status == "aborted" {
                    do {
                        let transcript = try await appState.openClawManager.gatewayChatHistory(
                            sessionKey: refreshedSessionKey,
                            using: gatewayConfig,
                            limit: 80
                        )
                        await MainActor.run {
                            self.replaceLatestResponseCluster(
                                in: activeSessionID,
                                from: transcript,
                                placeholderID: assistantMessageID
                            )
                        }
                    } catch {
                        await MainActor.run {
                            if self.lastError == nil {
                                self.lastError = "已收到回答，但结构化历史刷新失败：\(error.localizedDescription)"
                            }
                        }
                    }
                }
            } catch is CancellationError {
                await MainActor.run {
                    self.isSending = false
                    self.isStopping = false
                    self.pendingAbortAfterRunStart = false
                    self.activeRunID = nil
                    self.sendTask = nil
                    self.finalizeAssistantMessage(
                        in: activeSessionID,
                        withID: assistantMessageID
                    )
                }
            } catch {
                await MainActor.run {
                    self.lastError = error.localizedDescription
                    self.isSending = false
                    self.isStopping = false
                    self.pendingAbortAfterRunStart = false
                    self.activeRunID = nil
                    self.sendTask = nil
                    self.finalizeAssistantMessage(
                        in: activeSessionID,
                        withID: assistantMessageID
                    )
                    if self.plainText(
                        in: activeSessionID,
                        for: assistantMessageID
                    ).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        self.updateAssistantMessage(
                            in: activeSessionID,
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
        in sessionID: UUID,
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
        saveCurrentSessionSnapshot()

        let finalText = result.assistantText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !finalText.isEmpty {
            updateAssistantMessage(
                in: sessionID,
                withID: assistantMessageID,
                text: finalText,
                isStreaming: false
            )
        } else {
            finalizeAssistantMessage(
                in: sessionID,
                withID: assistantMessageID
            )
        }

        switch result.status {
        case "ok":
            statusMessage = nil
            if plainText(
                in: sessionID,
                for: assistantMessageID
            ).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                updateAssistantMessage(
                    in: sessionID,
                    withID: assistantMessageID,
                    text: "本次对话已完成，但没有返回可显示内容。",
                    isStreaming: false
                )
            }
        case "aborted":
            statusMessage = "当前输出已停止。"
            if plainText(
                in: sessionID,
                for: assistantMessageID
            ).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                updateAssistantMessage(
                    in: sessionID,
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

    private func updateAssistantMessage(
        in sessionID: UUID,
        withID messageID: UUID,
        text: String,
        isStreaming: Bool
    ) {
        if sessionID == selectedSessionID,
           let index = messages.firstIndex(where: { $0.id == messageID }) {
            messages[index].blocks = messageBlocks(fromText: text)
            messages[index].isStreaming = isStreaming
            saveCurrentSessionSnapshot()
            return
        }

        mutateSession(withID: sessionID, touch: true) { record in
            guard let index = record.messages.firstIndex(where: { $0.id == messageID }) else { return }
            record.messages[index].blocks = messageBlocks(fromText: text)
            record.messages[index].isStreaming = isStreaming
        }
    }

    private func finalizeAssistantMessage(
        in sessionID: UUID,
        withID messageID: UUID
    ) {
        if sessionID == selectedSessionID,
           let index = messages.firstIndex(where: { $0.id == messageID }) {
            messages[index].isStreaming = false
            saveCurrentSessionSnapshot()
            return
        }

        mutateSession(withID: sessionID, touch: true) { record in
            guard let index = record.messages.firstIndex(where: { $0.id == messageID }) else { return }
            record.messages[index].isStreaming = false
        }
    }

    private func plainText(
        in sessionID: UUID,
        for messageID: UUID
    ) -> String {
        if sessionID == selectedSessionID {
            return messages.first(where: { $0.id == messageID })?.plainText ?? ""
        }
        return sessionRecord(withID: sessionID)?
            .messages
            .first(where: { $0.id == messageID })?
            .plainText ?? ""
    }

    private func replaceLatestResponseCluster(
        in sessionID: UUID,
        from transcript: [OpenClawGatewayClient.ChatTranscriptMessage],
        placeholderID: UUID
    ) {
        let cluster = latestResponseCluster(from: transcript)
        let mappedMessages = cluster.compactMap(message(from:))
        guard !mappedMessages.isEmpty else { return }

        if sessionID == selectedSessionID {
            if let placeholderIndex = messages.firstIndex(where: { $0.id == placeholderID }) {
                messages.removeSubrange(placeholderIndex..<messages.count)
                messages.append(contentsOf: mappedMessages)
            } else {
                messages.append(contentsOf: mappedMessages)
            }
            saveCurrentSessionSnapshot()
            return
        }

        mutateSession(withID: sessionID, touch: true) { record in
            if let placeholderIndex = record.messages.firstIndex(where: { $0.id == placeholderID }) {
                record.messages.removeSubrange(placeholderIndex..<record.messages.count)
                record.messages.append(contentsOf: mappedMessages)
            } else {
                record.messages.append(contentsOf: mappedMessages)
            }
        }
    }

    private func latestResponseCluster(
        from transcript: [OpenClawGatewayClient.ChatTranscriptMessage]
    ) -> [OpenClawGatewayClient.ChatTranscriptMessage] {
        guard let lastUserIndex = transcript.lastIndex(where: { message in
            message.role == "user"
        }) else {
            return transcript.filter { $0.role != "user" }
        }

        let slice = transcript.suffix(from: transcript.index(after: lastUserIndex))
        return slice.filter { message in
            message.role == "assistant" || message.role == "tool_result"
        }
    }

    private func message(
        from transcriptMessage: OpenClawGatewayClient.ChatTranscriptMessage
    ) -> Message? {
        let role: MessageRole
        switch transcriptMessage.role {
        case "user":
            role = .user
        case "tool_result":
            role = .toolResult
        case "system":
            role = .system
        default:
            role = .assistant
        }

        let blocks = messageBlocks(from: transcriptMessage, role: role)
        guard !blocks.isEmpty || !transcriptMessage.text.isEmpty else { return nil }

        return Message(
            role: role,
            blocks: blocks.isEmpty ? messageBlocks(fromText: transcriptMessage.text) : blocks,
            attachments: [],
            createdAt: Self.date(from: transcriptMessage.timestamp),
            isStreaming: false
        )
    }

    private func messageBlocks(
        from transcriptMessage: OpenClawGatewayClient.ChatTranscriptMessage,
        role: MessageRole
    ) -> [MessageContentBlock] {
        let blocks = transcriptMessage.blocks.compactMap { block -> MessageContentBlock? in
            switch block.kind {
            case .text:
                guard let text = Self.normalizedNonEmptyText(block.text) else { return nil }
                return MessageContentBlock(
                    kind: .text,
                    text: text,
                    language: block.language
                )

            case .thinking:
                guard let text = Self.normalizedNonEmptyText(block.text) else { return nil }
                return MessageContentBlock(
                    kind: .thinking,
                    text: text
                )

            case .image:
                return MessageContentBlock(
                    kind: .image,
                    text: Self.normalizedNonEmptyText(block.text),
                    imageURL: Self.url(from: block.imageURL),
                    imagePreviewData: nil,
                    imageMimeType: block.imageMimeType,
                    imageByteCount: block.imageByteCount,
                    imageDataOmitted: block.isImageDataOmitted
                )

            case .toolUse:
                return MessageContentBlock(
                    kind: .toolUse,
                    text: Self.normalizedNonEmptyText(block.text),
                    toolName: Self.normalizedNonEmptyText(block.toolName) ?? "tool",
                    toolArguments: Self.normalizedNonEmptyText(block.toolArguments)
                )

            case .toolResult:
                return MessageContentBlock(
                    kind: role == .toolResult ? .toolResult : .toolResult,
                    text: Self.normalizedNonEmptyText(block.text),
                    language: block.language,
                    toolName: Self.normalizedNonEmptyText(block.toolName),
                    toolOutput: Self.normalizedNonEmptyText(block.toolOutput)
                )

            case .unknown:
                return nil
            }
        }

        if !blocks.isEmpty {
            return blocks
        }

        return messageBlocks(fromText: transcriptMessage.text)
    }

    private func messageBlocks(fromText text: String) -> [MessageContentBlock] {
        guard let normalized = Self.normalizedNonEmptyText(text) else { return [] }
        return [
            MessageContentBlock(
                kind: .text,
                text: normalized
            )
        ]
    }

    private func clearPresentedSessionState() {
        selectedSessionID = nil
        availableSessions = []
        messages = []
        attachments = []
        draftText = ""
        sessionKey = ""
        activeRunID = nil
        isSending = false
        isStopping = false
        pendingAbortAfterRunStart = false
    }

    private func saveCurrentSessionSnapshot(touch: Bool = true) {
        guard let sessionID = selectedSessionID else { return }
        mutateSession(withID: sessionID, touch: touch) { record in
            record.messages = messages
            record.attachments = attachments
            record.draftText = draftText
            record.sessionKey = sessionKey
        }
    }

    private func sessionRecord(withID sessionID: UUID) -> SessionRecord? {
        guard let contextKey = sessionContextByID[sessionID],
              let record = sessionsByContext[contextKey]?.first(where: { $0.id == sessionID }) else {
            return nil
        }
        return record
    }

    private func bindSession(
        withID sessionID: UUID,
        statusMessage: String?
    ) {
        guard let record = sessionRecord(withID: sessionID) else { return }
        selectedSessionID = sessionID
        activeSessionIDByContext[Self.contextKey(for: record.context)] = sessionID
        messages = record.messages
        attachments = record.attachments
        draftText = record.draftText
        sessionKey = record.sessionKey
        refreshAvailableSessions()
        activeRunID = nil
        isSending = false
        isStopping = false
        pendingAbortAfterRunStart = false
        self.statusMessage = statusMessage
    }

    @discardableResult
    private func createSession(for context: AppState.QuickChatContext) -> UUID {
        let sessionID = UUID()
        let contextKey = Self.contextKey(for: context)
        let record = SessionRecord(
            id: sessionID,
            context: context,
            createdAt: Date(),
            updatedAt: Date(),
            customTitle: nil,
            sessionKey: Self.makeSessionKey(for: context),
            messages: [],
            attachments: [],
            draftText: ""
        )
        sessionsByContext[contextKey, default: []].append(record)
        sessionContextByID[sessionID] = contextKey
        activeSessionIDByContext[contextKey] = sessionID
        refreshAvailableSessions()
        return sessionID
    }

    private func mutateSession(
        withID sessionID: UUID,
        touch: Bool,
        _ mutate: (inout SessionRecord) -> Void
    ) {
        guard let contextKey = sessionContextByID[sessionID],
              var records = sessionsByContext[contextKey],
              let index = records.firstIndex(where: { $0.id == sessionID }) else {
            return
        }

        mutate(&records[index])
        if touch {
            records[index].updatedAt = Date()
        }
        sessionsByContext[contextKey] = records
        refreshAvailableSessions()
    }

    private func refreshAvailableSessions() {
        guard let context else {
            availableSessions = []
            return
        }

        let contextKey = Self.contextKey(for: context)
        let records = sessionsByContext[contextKey] ?? []
        availableSessions = records
            .sorted { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return lhs.createdAt > rhs.createdAt
            }
            .map { record in
                SessionSummary(
                    id: record.id,
                    title: sessionTitle(for: record, within: records),
                    preview: sessionPreview(for: record),
                    updatedAt: record.updatedAt,
                    messageCount: record.messages.count,
                    isCustomTitle: record.customTitle != nil
                )
            }
    }

    private func sessionTitle(
        for record: SessionRecord,
        within records: [SessionRecord]
    ) -> String {
        if let customTitle = Self.normalizedNonEmptyText(record.customTitle) {
            return customTitle
        }
        let ordinal = (records.firstIndex(where: { $0.id == record.id }) ?? 0) + 1
        return "会话 \(ordinal)"
    }

    private func sessionPreview(for record: SessionRecord) -> String {
        if let lastMessage = record.messages.last?.plainText,
           let preview = Self.normalizedNonEmptyText(lastMessage) {
            return preview
        }
        if let draftPreview = Self.normalizedNonEmptyText(record.draftText) {
            return "草稿：\(draftPreview)"
        }
        return "新会话"
    }

    private static func contextKey(for context: AppState.QuickChatContext) -> ContextKey {
        ContextKey(
            projectID: context.projectID,
            workflowID: context.workflowID,
            agentID: context.entryAgentID
        )
    }

    private func stageAttachment(from url: URL) {
        guard let sessionID = selectedSessionID else { return }
        let attachmentID = UUID()
        let placeholder = Attachment(
            id: attachmentID,
            originalURL: url,
            fileName: url.lastPathComponent,
            mimeType: Self.mimeType(for: url),
            fileSize: 0,
            stagedURL: nil,
            previewData: nil,
            base64Content: nil,
            stageState: .staging
        )
        attachments.append(placeholder)
        saveCurrentSessionSnapshot()

        let task = _Concurrency.Task { [weak self] in
            guard let self else { return }
            do {
                let prepared = try await Self.prepareAttachmentAsync(from: url)
                self.finishStagingAttachment(
                    sessionID: sessionID,
                    attachmentID: attachmentID,
                    prepared: prepared
                )
            } catch {
                self.failStagingAttachment(
                    sessionID: sessionID,
                    attachmentID: attachmentID,
                    message: error.localizedDescription
                )
            }
        }

        attachmentTasks[attachmentID] = (sessionID, task)
    }

    private func stageBufferedAttachment(
        _ data: Data,
        fileName: String,
        mimeType: String
    ) {
        guard let sessionID = selectedSessionID else { return }
        let attachmentID = UUID()
        let placeholder = Attachment(
            id: attachmentID,
            originalURL: nil,
            fileName: fileName,
            mimeType: mimeType,
            fileSize: Int64(data.count),
            stagedURL: nil,
            previewData: nil,
            base64Content: nil,
            stageState: .staging
        )
        attachments.append(placeholder)
        saveCurrentSessionSnapshot()

        let task = _Concurrency.Task { [weak self] in
            guard let self else { return }
            do {
                let prepared = try await Self.prepareBufferedAttachmentAsync(
                    data,
                    fileName: fileName,
                    mimeType: mimeType
                )
                self.finishStagingAttachment(
                    sessionID: sessionID,
                    attachmentID: attachmentID,
                    prepared: prepared
                )
            } catch {
                self.failStagingAttachment(
                    sessionID: sessionID,
                    attachmentID: attachmentID,
                    message: error.localizedDescription
                )
            }
        }

        attachmentTasks[attachmentID] = (sessionID, task)
    }

    private func finishStagingAttachment(
        sessionID: UUID,
        attachmentID: UUID,
        prepared: PreparedAttachment
    ) {
        attachmentTasks.removeValue(forKey: attachmentID)
        if sessionID == selectedSessionID,
           let index = attachments.firstIndex(where: { $0.id == attachmentID }) {
            attachments[index].fileName = prepared.fileName
            attachments[index].mimeType = prepared.mimeType
            attachments[index].fileSize = prepared.fileSize
            attachments[index].stagedURL = prepared.stagedURL
            attachments[index].previewData = prepared.previewData
            attachments[index].base64Content = prepared.base64Content
            attachments[index].stageState = .ready
            saveCurrentSessionSnapshot()
            return
        }

        mutateSession(withID: sessionID, touch: true) { record in
            guard let index = record.attachments.firstIndex(where: { $0.id == attachmentID }) else { return }
            record.attachments[index].fileName = prepared.fileName
            record.attachments[index].mimeType = prepared.mimeType
            record.attachments[index].fileSize = prepared.fileSize
            record.attachments[index].stagedURL = prepared.stagedURL
            record.attachments[index].previewData = prepared.previewData
            record.attachments[index].base64Content = prepared.base64Content
            record.attachments[index].stageState = .ready
        }
    }

    private func failStagingAttachment(
        sessionID: UUID,
        attachmentID: UUID,
        message: String
    ) {
        attachmentTasks.removeValue(forKey: attachmentID)
        if sessionID == selectedSessionID,
           let index = attachments.firstIndex(where: { $0.id == attachmentID }) {
            attachments[index].stageState = .failed(message)
            saveCurrentSessionSnapshot()
            return
        }

        mutateSession(withID: sessionID, touch: true) { record in
            guard let index = record.attachments.firstIndex(where: { $0.id == attachmentID }) else { return }
            record.attachments[index].stageState = .failed(message)
        }
    }

    private nonisolated static func prepareAttachment(from url: URL) throws -> PreparedAttachment {
        guard url.isFileURL else {
            throw NSError(
                domain: "QuickChat",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "只支持本地文件。"]
            )
        }

        let data = try Data(contentsOf: url)
        let fileName = url.lastPathComponent.isEmpty ? "file" : url.lastPathComponent
        let mimeType = mimeType(for: url)
        return try prepareBufferedAttachment(
            data,
            fileName: fileName,
            mimeType: mimeType
        )
    }

    private nonisolated static func prepareAttachmentAsync(from url: URL) async throws -> PreparedAttachment {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    continuation.resume(returning: try prepareAttachment(from: url))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private nonisolated static func prepareBufferedAttachment(
        _ data: Data,
        fileName: String,
        mimeType: String
    ) throws -> PreparedAttachment {
        guard data.count > 0 else {
            throw NSError(
                domain: "QuickChat",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "附件为空，无法发送。"]
            )
        }

        guard data.count <= maxAttachmentBytes else {
            throw NSError(
                domain: "QuickChat",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "附件超过 \(ByteCountFormatter.string(fromByteCount: Int64(maxAttachmentBytes), countStyle: .file)) 限制，当前轻量 chat 不支持更大文件。"]
            )
        }

        let stagedURL = try writeStagedData(data, fileName: fileName)
        let previewData = previewData(for: data, mimeType: mimeType)

        return PreparedAttachment(
            stagedURL: stagedURL,
            fileName: fileName,
            mimeType: mimeType,
            fileSize: Int64(data.count),
            previewData: previewData,
            base64Content: data.base64EncodedString()
        )
    }

    private nonisolated static func prepareBufferedAttachmentAsync(
        _ data: Data,
        fileName: String,
        mimeType: String
    ) async throws -> PreparedAttachment {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    continuation.resume(
                        returning: try prepareBufferedAttachment(
                            data,
                            fileName: fileName,
                            mimeType: mimeType
                        )
                    )
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private nonisolated static func writeStagedData(_ data: Data, fileName: String) throws -> URL {
        let directory = try stagingDirectory()
        let sanitizedName = sanitizeFileName(fileName)
        let targetURL = directory.appendingPathComponent(
            "\(UUID().uuidString)-\(sanitizedName)",
            isDirectory: false
        )
        try data.write(to: targetURL, options: .atomic)
        return targetURL
    }

    private nonisolated static func stagingDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("multi-agent-flow-quick-chat-stage", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    private nonisolated static func previewData(for data: Data, mimeType: String) -> Data? {
        guard mimeType.lowercased().hasPrefix("image/") else { return nil }
        return data
    }

    private nonisolated static func sanitizeFileName(_ rawFileName: String) -> String {
        let trimmed = rawFileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "attachment" }

        let invalidCharacters = CharacterSet(charactersIn: "/:\\")
        let sanitized = trimmed.unicodeScalars.map { scalar -> Character in
            invalidCharacters.contains(scalar) ? "-" : Character(scalar)
        }
        let candidate = String(sanitized)
        return candidate.isEmpty ? "attachment" : candidate
    }

    private nonisolated static func mimeType(for url: URL) -> String {
        if let type = UTType(filenameExtension: url.pathExtension),
           let mimeType = type.preferredMIMEType {
            return mimeType
        }
        return "application/octet-stream"
    }

    private static func makeSessionKey(for context: AppState.QuickChatContext) -> String {
        let project = context.projectID.uuidString.lowercased()
        let workflow = context.workflowID.uuidString.lowercased()
        let agent = context.entryAgentID.uuidString.lowercased()
        let session = UUID().uuidString.lowercased()
        return "quick-chat:\(project):\(workflow):\(agent):\(session)"
    }

    private static func date(from timestamp: Double?) -> Date {
        guard let timestamp else { return Date() }
        return Date(timeIntervalSince1970: timestamp)
    }

    private static func url(from rawValue: String?) -> URL? {
        guard let rawValue = normalizedNonEmptyText(rawValue) else { return nil }
        if rawValue.hasPrefix("/") {
            return URL(fileURLWithPath: rawValue)
        }
        return URL(string: rawValue)
    }

    private static func normalizedNonEmptyText(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func timestampFileComponent() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}
