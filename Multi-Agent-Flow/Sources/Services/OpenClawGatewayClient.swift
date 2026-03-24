import Foundation
import CryptoKit

actor OpenClawGatewayClient {
    nonisolated static let disconnectNotificationName = Notification.Name("OpenClawGatewayDidDisconnect")
    nonisolated static let disconnectMessageUserInfoKey = "message"

    private enum GatewayErrorUserInfoKey {
        static let connectDetailCode = "OpenClawGatewayClient.ConnectDetailCode"
    }

    private static let gatewayClientID = "gateway-client"
    private static let gatewayClientMode = "backend"
    private static let gatewayRole = "operator"
    private static let gatewayScopes = ["operator.admin"]
    private static let gatewayDeviceFamily = "desktop"

    struct RemoteAgentRecord: Hashable {
        let id: String
        let name: String
    }

    struct RemoteProbeResult {
        let agents: [RemoteAgentRecord]

        var agentNames: [String] {
            agents.map(\.name)
        }
    }

    struct AgentExecutionResult {
        let runID: String
        let status: String
        let assistantText: String
        let sessionKey: String?
        let errorMessage: String?
    }

    struct ChatAttachment: Hashable, Sendable {
        let type: String
        let mimeType: String
        let fileName: String
        let contentBase64: String

        fileprivate var rpcPayload: [String: Any] {
            [
                "type": type,
                "mimeType": mimeType,
                "fileName": fileName,
                "content": contentBase64,
                "source": [
                    "type": "base64",
                    "media_type": mimeType,
                    "data": contentBase64
                ]
            ]
        }
    }

    struct ChatSessionRecord: Hashable {
        let key: String
        let displayName: String?
        let updatedAt: Double?
    }

    struct ChatTranscriptMessage: Hashable, Sendable {
        struct ContentBlock: Hashable, Sendable {
            enum Kind: String, Hashable, Sendable {
                case text
                case thinking
                case image
                case toolUse = "tool_use"
                case toolResult = "tool_result"
                case unknown
            }

            let kind: Kind
            let rawType: String?
            let text: String?
            let language: String?
            let toolName: String?
            let toolArguments: String?
            let toolOutput: String?
            let imageURL: String?
            let imageMimeType: String?
            let imageByteCount: Int?
            let isImageDataOmitted: Bool
        }

        let role: String
        let text: String
        let timestamp: Double?
        let blocks: [ContentBlock]
    }

    private struct ChatRunState {
        var sessionKey: String?
        var state: String?
        var errorMessage: String?
        var assistantText: String = ""
        var lastUpdatedAt = Date()

        mutating func apply(payload: [String: Any]) {
            if let sessionKey = (payload["sessionKey"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !sessionKey.isEmpty
            {
                self.sessionKey = sessionKey
            }
            if let state = (payload["state"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !state.isEmpty
            {
                self.state = state.lowercased()
            }
            if let errorMessage = (payload["errorMessage"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !errorMessage.isEmpty
            {
                self.errorMessage = errorMessage
            }
            if let assistantText = OpenClawGatewayClient.assistantText(fromChatPayload: payload) {
                self.assistantText = OpenClawGatewayClient.mergedAssistantText(
                    previous: self.assistantText,
                    incoming: assistantText
                )
            }
            lastUpdatedAt = Date()
        }

        func observedRunState(fallback: AgentRunState?) -> AgentRunState {
            var runState = fallback ?? AgentRunState()
            if !assistantText.isEmpty {
                runState.assistantText = assistantText
            }
            if let sessionKey, !sessionKey.isEmpty {
                runState.sessionKey = sessionKey
            }
            if let errorMessage, !errorMessage.isEmpty {
                runState.errorMessage = errorMessage
            }

            switch state {
            case "final":
                runState.lifecyclePhase = "end"
            case "aborted":
                runState.lifecyclePhase = "aborted"
            case "error":
                runState.lifecyclePhase = "error"
            default:
                break
            }

            runState.lastUpdatedAt = lastUpdatedAt
            return runState
        }
    }

    private struct RuntimeConfiguration: Equatable {
        let webSocketURL: URL
        let token: String?
        let timeoutSeconds: Int
        let fingerprint: String
        let deviceIdentity: GatewayDeviceIdentity
    }

    private struct GatewayDeviceIdentity: Codable, Equatable {
        let version: Int
        let deviceID: String
        let privateKeyRawBase64: String
        let createdAtMilliseconds: Int64

        var privateKeyRawRepresentation: Data {
            Data(base64Encoded: privateKeyRawBase64) ?? Data()
        }
    }

    private struct GatewayResponseFrame {
        let id: String
        let ok: Bool
        let payload: Any?
        let error: [String: Any]?
    }

    private struct GatewayAgentEvent {
        let runID: String
        let stream: String
        let sessionKey: String?
        let data: [String: Any]
    }

    private struct AgentRunState {
        var assistantText: String = ""
        var sessionKey: String?
        var lifecyclePhase: String?
        var errorMessage: String?
        var lastUpdatedAt = Date()

        var isTerminal: Bool {
            guard let lifecyclePhase else { return false }
            return ["end", "abort", "aborted", "error"].contains(lifecyclePhase)
        }

        mutating func apply(_ event: GatewayAgentEvent) {
            if let sessionKey = event.sessionKey, !sessionKey.isEmpty {
                self.sessionKey = sessionKey
            }

            switch event.stream {
            case "assistant":
                if let text = event.data["text"] as? String {
                    assistantText = text
                }
            case "lifecycle":
                if let phase = event.data["phase"] as? String {
                    lifecyclePhase = phase
                }
                if let error = event.data["error"] as? String, !error.isEmpty {
                    errorMessage = error
                }
            default:
                break
            }

            lastUpdatedAt = Date()
        }
    }

    private struct ObserverRegistration {
        let id: UUID
        let handler: @Sendable (AgentRunState) -> Void
    }

    private let session: URLSession
    private let defaultTickIntervalSeconds = 30
    private let keepaliveIntervalSeconds = 15
    private var runtimeConfiguration: RuntimeConfiguration?
    private var socketTask: URLSessionWebSocketTask?
    private var receiveLoopTask: _Concurrency.Task<Void, Never>?
    private var keepaliveTask: _Concurrency.Task<Void, Never>?
    private var tickWatchdogTask: _Concurrency.Task<Void, Never>?
    private var pendingResponses: [String: CheckedContinuation<GatewayResponseFrame, Error>] = [:]
    private var runStates: [String: AgentRunState] = [:]
    private var chatRunStates: [String: ChatRunState] = [:]
    private var runObservers: [String: [ObserverRegistration]] = [:]
    private var isConnected = false
    private var lastTickAt = Date()
    private var tickIntervalSeconds = 30

    init(session: URLSession = .shared) {
        self.session = session
    }

    func disconnect() async {
        receiveLoopTask?.cancel()
        receiveLoopTask = nil
        keepaliveTask?.cancel()
        keepaliveTask = nil
        tickWatchdogTask?.cancel()
        tickWatchdogTask = nil

        socketTask?.cancel(with: .goingAway, reason: nil)
        socketTask = nil
        isConnected = false
        runtimeConfiguration = nil

        let error = gatewayError("Gateway connection closed.")
        let continuations = pendingResponses.values
        pendingResponses.removeAll()
        for continuation in continuations {
            continuation.resume(throwing: error)
        }
    }

    func probe(using config: OpenClawConfig) async throws -> RemoteProbeResult {
        _ = try await request(
            method: "health",
            params: [:],
            timeoutSeconds: max(config.timeout, 5),
            using: config
        )

        return RemoteProbeResult(agents: try await listAgents(using: config))
    }

    func listAgents(using config: OpenClawConfig) async throws -> [RemoteAgentRecord] {
        let response = try await request(
            method: "agents.list",
            params: [:],
            timeoutSeconds: max(config.timeout, 5),
            using: config
        )
        return parseRemoteAgents(from: response.payload)
    }

    func listSessions(using config: OpenClawConfig, limit: Int? = nil) async throws -> [ChatSessionRecord] {
        var params: [String: Any] = [
            "includeGlobal": true,
            "includeUnknown": false
        ]
        if let limit, limit > 0 {
            params["limit"] = limit
        }

        let response = try await request(
            method: "sessions.list",
            params: params,
            timeoutSeconds: max(config.timeout, 5),
            using: config
        )

        let payload = response.payload as? [String: Any]
        let sessions = payload?["sessions"] as? [[String: Any]] ?? []
        return sessions.compactMap { session in
            guard let key = normalizedNonEmptyString(session["key"]) else { return nil }
            let displayName = normalizedNonEmptyString(session["displayName"])
            let updatedAt = session["updatedAt"] as? Double ?? (session["updatedAt"] as? NSNumber)?.doubleValue
            return ChatSessionRecord(key: key, displayName: displayName, updatedAt: updatedAt)
        }
    }

    func executeAgent(
        using config: OpenClawConfig,
        message: String,
        agentIdentifier: String,
        sessionKey: String?,
        thinkingLevel: AgentThinkingLevel?,
        timeoutSeconds: Int,
        onAssistantTextUpdated: @escaping @Sendable (String) -> Void
    ) async throws -> AgentExecutionResult {
        let requestedSessionKey = sessionKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        var params: [String: Any] = [
            "message": message,
            "agentId": agentIdentifier,
            "idempotencyKey": UUID().uuidString
        ]

        if let requestedSessionKey, !requestedSessionKey.isEmpty {
            params["sessionKey"] = requestedSessionKey
        }
        if let thinkingLevel {
            params["thinking"] = thinkingLevel.rawValue
        }
        params["timeout"] = max(1, timeoutSeconds)

        let acceptedResponse = try await request(
            method: "agent",
            params: params,
            timeoutSeconds: max(timeoutSeconds + 5, 15),
            using: config
        )

        guard
            let payload = acceptedResponse.payload as? [String: Any],
            let runID = payload["runId"] as? String,
            !runID.isEmpty
        else {
            throw gatewayError("Gateway agent invocation did not return a runId.")
        }

        let observerID = UUID()
        registerObserver(id: observerID, for: runID, handler: onAssistantTextUpdated)
        defer { removeObserver(id: observerID, for: runID) }

        if let state = runStates[runID], !state.assistantText.isEmpty {
            onAssistantTextUpdated(state.assistantText)
        }

        let waitResponse = try await request(
            method: "agent.wait",
            params: [
                "runId": runID,
                "timeoutMs": max(1, timeoutSeconds) * 1000
            ],
            timeoutSeconds: max(timeoutSeconds + 5, 15),
            using: config
        )

        let waitPayload = waitResponse.payload as? [String: Any] ?? [:]
        let waitStatus = (waitPayload["status"] as? String) ?? "unknown"
        var state = runStates[runID] ?? AgentRunState()
        if let error = waitPayload["error"] as? String, !error.isEmpty {
            state.errorMessage = error
            runStates[runID] = state
        }

        if waitStatus == "ok" && state.assistantText.isEmpty {
            try? await _Concurrency.Task.sleep(nanoseconds: 150_000_000)
            state = runStates[runID] ?? state
        }

        return AgentExecutionResult(
            runID: runID,
            status: waitStatus,
            assistantText: state.assistantText,
            sessionKey: state.sessionKey ?? requestedSessionKey,
            errorMessage: state.errorMessage
        )
    }

    func executeChat(
        using config: OpenClawConfig,
        message: String,
        sessionKey: String,
        attachments: [ChatAttachment] = [],
        thinkingLevel: AgentThinkingLevel?,
        timeoutSeconds: Int,
        onRunStarted: (@Sendable (String, String) -> Void)? = nil,
        onAssistantTextUpdated: @escaping @Sendable (String) -> Void
    ) async throws -> AgentExecutionResult {
        let requestedSessionKey = sessionKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !requestedSessionKey.isEmpty else {
            throw gatewayError("Gateway chat invocation requires a session key.")
        }

        var params: [String: Any] = [
            "sessionKey": requestedSessionKey,
            "message": message,
            "timeoutMs": max(1, timeoutSeconds) * 1000,
            "idempotencyKey": UUID().uuidString
        ]
        if !attachments.isEmpty {
            params["attachments"] = attachments.map(\.rpcPayload)
        }
        if let thinkingLevel {
            params["thinking"] = thinkingLevel.rawValue
        }

        let acceptedResponse = try await request(
            method: "chat.send",
            params: params,
            timeoutSeconds: max(timeoutSeconds + 5, 15),
            using: config
        )

        guard
            let payload = acceptedResponse.payload as? [String: Any],
            let runID = payload["runId"] as? String,
            !runID.isEmpty
        else {
            throw gatewayError("Gateway chat invocation did not return a runId.")
        }
        let acceptedSessionKey = normalizedNonEmptyString(payload["sessionKey"]) ?? requestedSessionKey
        onRunStarted?(runID, acceptedSessionKey)

        let observerID = UUID()
        registerObserver(id: observerID, for: runID, handler: onAssistantTextUpdated)
        defer { removeObserver(id: observerID, for: runID) }

        if let state = runStates[runID], !state.assistantText.isEmpty {
            onAssistantTextUpdated(state.assistantText)
        }

        let waitResponse = try await request(
            method: "agent.wait",
            params: [
                "runId": runID,
                "timeoutMs": max(1, timeoutSeconds) * 1000
            ],
            timeoutSeconds: max(timeoutSeconds + 5, 15),
            using: config
        )

        let waitPayload = waitResponse.payload as? [String: Any] ?? [:]
        let waitStatus = normalizedNonEmptyString(waitPayload["status"]) ?? "unknown"
        var agentState = runStates[runID] ?? AgentRunState()
        let chatState = chatRunStates[runID]
        let resolvedSessionKey = chatState?.sessionKey ?? acceptedSessionKey

        if let errorMessage = normalizedNonEmptyString(waitPayload["error"]) {
            agentState.errorMessage = errorMessage
            runStates[runID] = agentState
        }

        if waitStatus == "ok"
            || chatState?.state == "final"
            || chatState?.state == "aborted"
            || chatState?.state == "error"
        {
            try? await _Concurrency.Task.sleep(nanoseconds: 150_000_000)
            if let historyText = try await latestAssistantText(
                using: config,
                sessionKey: resolvedSessionKey
            ), !historyText.isEmpty {
                agentState.assistantText = historyText
                runStates[runID] = agentState
                onAssistantTextUpdated(historyText)
            } else if let streamedText = chatState?.assistantText,
                      !streamedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                agentState.assistantText = streamedText
                runStates[runID] = agentState
                onAssistantTextUpdated(streamedText)
            } else {
                agentState = runStates[runID] ?? agentState
            }
        }

        let finalStatus: String
        switch chatState?.state {
        case "final":
            finalStatus = "ok"
        case "aborted":
            finalStatus = "aborted"
        case "error":
            finalStatus = "error"
        default:
            finalStatus = waitStatus
        }

        return AgentExecutionResult(
            runID: runID,
            status: finalStatus,
            assistantText: agentState.assistantText,
            sessionKey: resolvedSessionKey,
            errorMessage: chatState?.errorMessage ?? agentState.errorMessage
        )
    }

    func abortChatRun(
        using config: OpenClawConfig,
        sessionKey: String,
        runID: String
    ) async throws {
        _ = try await request(
            method: "chat.abort",
            params: [
                "sessionKey": sessionKey,
                "runId": runID
            ],
            timeoutSeconds: max(config.timeout, 5),
            using: config
        )
    }

    func chatHistory(
        using config: OpenClawConfig,
        sessionKey: String,
        limit: Int? = nil
    ) async throws -> [ChatTranscriptMessage] {
        let payload = try await requestChatHistoryPayload(using: config, sessionKey: sessionKey, limit: limit)
        return parseChatHistoryPayload(payload)
    }

    func parseChatHistoryPayload(_ payload: [String: Any]) -> [ChatTranscriptMessage] {
        let messages = payload["messages"] as? [Any] ?? []
        return messages.compactMap { transcriptMessage(fromHistoryEntry: $0) }
    }

    private func registerObserver(
        id: UUID,
        for runID: String,
        handler: @escaping @Sendable (String) -> Void
    ) {
        let registration = ObserverRegistration(id: id) { state in
            handler(state.assistantText)
        }
        runObservers[runID, default: []].append(registration)
    }

    private func removeObserver(id: UUID, for runID: String) {
        guard var registrations = runObservers[runID] else { return }
        registrations.removeAll { $0.id == id }
        if registrations.isEmpty {
            runObservers.removeValue(forKey: runID)
        } else {
            runObservers[runID] = registrations
        }
    }

    private func request(
        method: String,
        params: [String: Any],
        timeoutSeconds: Int,
        using config: OpenClawConfig
    ) async throws -> GatewayResponseFrame {
        _ = try await connectWithRecovery(using: config)

        let requestID = UUID().uuidString
        let frame: [String: Any] = [
            "type": "req",
            "id": requestID,
            "method": method,
            "params": params
        ]

        let data = try encodeJSONObject(frame)
        do {
            let response = try await withTimeout(seconds: timeoutSeconds) {
                try await self.awaitResponse(
                    withID: requestID,
                    message: .string(String(decoding: data, as: UTF8.self))
                )
            }
            return try validated(response: response, for: method)
        } catch {
            failPendingResponse(withID: requestID, error: error)
            throw error
        }
    }

    private func connectWithRecovery(using config: OpenClawConfig) async throws -> RuntimeConfiguration {
        var runtimeConfig = try runtimeConfiguration(for: config)

        do {
            try await ensureConnected(using: runtimeConfig)
            return runtimeConfig
        } catch {
            guard shouldRegenerateDeviceIdentity(after: error) else {
                throw error
            }

            try archiveCurrentDeviceIdentity(reason: "gateway-recovery")
            runtimeConfig = try runtimeConfiguration(for: config)
            try await ensureConnected(using: runtimeConfig)
            return runtimeConfig
        }
    }

    private func ensureConnected(using runtimeConfig: RuntimeConfiguration) async throws {
        if runtimeConfiguration != runtimeConfig {
            await disconnect()
            runtimeConfiguration = runtimeConfig
        }

        if isConnected, socketTask != nil {
            return
        }

        try await connect(using: runtimeConfig)
    }

    private func connect(using runtimeConfig: RuntimeConfiguration) async throws {
        let task = session.webSocketTask(with: runtimeConfig.webSocketURL)
        task.maximumMessageSize = 16 * 1024 * 1024
        task.resume()

        let challengeObject = try await receiveJSONObject(from: task, timeoutSeconds: 8)
        guard
            let frameType = challengeObject["type"] as? String,
            frameType == "event",
            let eventName = challengeObject["event"] as? String,
            eventName == "connect.challenge",
            let payload = challengeObject["payload"] as? [String: Any]
        else {
            task.cancel(with: .protocolError, reason: nil)
            throw gatewayError("Gateway handshake failed: missing connect.challenge.")
        }

        let requestID = UUID().uuidString
        let connectPayload = try buildConnectPayload(
            runtimeConfig: runtimeConfig,
            challengePayload: payload
        )
        let connectFrame: [String: Any] = [
            "type": "req",
            "id": requestID,
            "method": "connect",
            "params": connectPayload
        ]
        let connectData = try encodeJSONObject(connectFrame)
        try await task.send(.string(String(decoding: connectData, as: UTF8.self)))

        let responseObject = try await receiveJSONObject(from: task, timeoutSeconds: 12)
        guard
            let responseType = responseObject["type"] as? String,
            responseType == "res",
            let responseID = responseObject["id"] as? String,
            responseID == requestID
        else {
            task.cancel(with: .protocolError, reason: nil)
            throw gatewayError("Gateway handshake failed: invalid connect response.")
        }

        let ok = (responseObject["ok"] as? Bool) ?? false
        if !ok {
            let errorShape = responseObject["error"] as? [String: Any]
            let message = (errorShape?["message"] as? String) ?? "Gateway authentication failed."
            let detailCode = connectErrorDetailCode(from: errorShape)
            task.cancel(with: .policyViolation, reason: nil)
            throw gatewayError(message, connectDetailCode: detailCode)
        }

        if let payload = responseObject["payload"] as? [String: Any] {
            updateConnectionPolicy(from: payload)
        } else {
            tickIntervalSeconds = defaultTickIntervalSeconds
        }

        socketTask = task
        isConnected = true
        lastTickAt = Date()
        startReceiveLoop(for: task)
        startKeepaliveLoop(for: task)
        startTickWatchdogLoop()
    }

    private func buildConnectPayload(
        runtimeConfig: RuntimeConfiguration,
        challengePayload: [String: Any]
    ) throws -> [String: Any] {
        let signedAtMilliseconds = Int(Date().timeIntervalSince1970 * 1000)
        let platform = runtimePlatformIdentifier()
        let clientVersion = runtimeClientVersion()
        var payload: [String: Any] = [
            "minProtocol": 3,
            "maxProtocol": 3,
            "client": [
                "id": Self.gatewayClientID,
                "displayName": "Multi-Agent-Flow",
                "version": clientVersion,
                "platform": platform,
                "deviceFamily": Self.gatewayDeviceFamily,
                "mode": Self.gatewayClientMode
            ],
            "role": Self.gatewayRole,
            "scopes": Self.gatewayScopes,
            "caps": [],
            "commands": [],
            "permissions": [:],
            "locale": Locale.current.identifier,
            "userAgent": "Multi-Agent-Flow/\(clientVersion)"
        ]

        if let token = runtimeConfig.token, !token.isEmpty {
            payload["auth"] = ["token": token]
        }

        if let nonce = challengePayload["nonce"] as? String, !nonce.isEmpty {
            let signaturePayload = buildDeviceAuthPayloadV3(
                deviceID: runtimeConfig.deviceIdentity.deviceID,
                clientID: Self.gatewayClientID,
                clientMode: Self.gatewayClientMode,
                role: Self.gatewayRole,
                scopes: Self.gatewayScopes,
                signedAtMilliseconds: signedAtMilliseconds,
                token: runtimeConfig.token,
                nonce: nonce,
                platform: platform,
                deviceFamily: Self.gatewayDeviceFamily
            )
            payload["device"] = [
                "id": runtimeConfig.deviceIdentity.deviceID,
                "publicKey": try publicKeyRawBase64URL(for: runtimeConfig.deviceIdentity),
                "signature": try signDevicePayload(
                    signaturePayload,
                    with: runtimeConfig.deviceIdentity
                ),
                "signedAt": signedAtMilliseconds,
                "nonce": nonce
            ]
        }

        return payload
    }

    private func startReceiveLoop(for task: URLSessionWebSocketTask) {
        receiveLoopTask?.cancel()
        receiveLoopTask = _Concurrency.Task { [weak self] in
            guard let self else { return }
            do {
                while !_Concurrency.Task.isCancelled {
                    let object = try await self.receiveJSONObject(from: task, timeoutSeconds: max(runtimeConfiguration?.timeoutSeconds ?? 30, 15))
                    await self.handleReceivedObject(object)
                }
            } catch {
                await self.handleDisconnect(error)
            }
        }
    }

    private func startKeepaliveLoop(for task: URLSessionWebSocketTask) {
        keepaliveTask?.cancel()
        keepaliveTask = _Concurrency.Task { [weak self] in
            guard let self else { return }
            while !_Concurrency.Task.isCancelled {
                do {
                    try await _Concurrency.Task.sleep(nanoseconds: UInt64(keepaliveIntervalSeconds) * 1_000_000_000)
                } catch {
                    return
                }

                do {
                    try await self.sendPing(on: task)
                } catch {
                    await self.handleDisconnect(error)
                    return
                }
            }
        }
    }

    private func startTickWatchdogLoop() {
        tickWatchdogTask?.cancel()
        tickWatchdogTask = _Concurrency.Task { [weak self] in
            guard let self else { return }
            while !_Concurrency.Task.isCancelled {
                let toleranceSeconds = await self.heartbeatToleranceSeconds()
                do {
                    try await _Concurrency.Task.sleep(nanoseconds: UInt64(toleranceSeconds) * 1_000_000_000)
                } catch {
                    return
                }

                let elapsed = await self.secondsSinceLastTick()
                guard elapsed > TimeInterval(toleranceSeconds) else { continue }
                let timeoutError = await self.heartbeatTimeoutError()
                await self.handleDisconnect(timeoutError)
                return
            }
        }
    }

    private func handleDisconnect(_ error: Error) {
        guard isConnected || socketTask != nil || receiveLoopTask != nil else { return }

        isConnected = false
        socketTask = nil
        receiveLoopTask = nil
        keepaliveTask?.cancel()
        keepaliveTask = nil
        tickWatchdogTask?.cancel()
        tickWatchdogTask = nil

        let continuations = pendingResponses.values
        pendingResponses.removeAll()
        for continuation in continuations {
            continuation.resume(throwing: error)
        }

        NotificationCenter.default.post(
            name: Self.disconnectNotificationName,
            object: nil,
            userInfo: [Self.disconnectMessageUserInfoKey: error.localizedDescription]
        )
    }

    private func awaitResponse(
        withID requestID: String,
        message: URLSessionWebSocketTask.Message
    ) async throws -> GatewayResponseFrame {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<GatewayResponseFrame, Error>) in
            pendingResponses[requestID] = continuation
            _Concurrency.Task {
                do {
                    try await self.sendPreparedMessage(message)
                } catch {
                    self.failPendingResponse(withID: requestID, error: error)
                }
            }
        }
    }

    private func handleReceivedObject(_ object: [String: Any]) {
        guard let frameType = object["type"] as? String else { return }

        switch frameType {
        case "res":
            guard let response = responseFrame(from: object) else { return }
            if let continuation = pendingResponses.removeValue(forKey: response.id) {
                continuation.resume(returning: response)
            }
        case "event":
            handleEvent(object)
        default:
            break
        }
    }

    private func handleEvent(_ object: [String: Any]) {
        guard let eventName = object["event"] as? String else { return }

        switch eventName {
        case "tick":
            lastTickAt = Date()
        case "chat":
            guard let payload = object["payload"] as? [String: Any] else { return }
            if let runID = normalizedNonEmptyString(payload["runId"]) {
                var state = chatRunStates[runID] ?? ChatRunState()
                let previousText = state.assistantText
                state.apply(payload: payload)
                chatRunStates[runID] = state
                let observedState = state.observedRunState(fallback: runStates[runID])
                runStates[runID] = observedState

                if observedState.assistantText != previousText, let observers = runObservers[runID] {
                    for observer in observers {
                        observer.handler(observedState)
                    }
                }
            }
        case "agent":
            guard
                let payload = object["payload"] as? [String: Any],
                let runID = payload["runId"] as? String,
                let stream = payload["stream"] as? String
            else {
                return
            }

            let event = GatewayAgentEvent(
                runID: runID,
                stream: stream,
                sessionKey: payload["sessionKey"] as? String,
                data: payload["data"] as? [String: Any] ?? [:]
            )

            var state = runStates[runID] ?? AgentRunState()
            let previousText = state.assistantText
            state.apply(event)
            runStates[runID] = state

            if state.assistantText != previousText, let observers = runObservers[runID] {
                for observer in observers {
                    observer.handler(state)
                }
            }
        default:
            break
        }
    }

    private func responseFrame(from object: [String: Any]) -> GatewayResponseFrame? {
        guard let id = object["id"] as? String else { return nil }
        let ok = (object["ok"] as? Bool) ?? false
        let payload = object["payload"]
        let error = object["error"] as? [String: Any]
        return GatewayResponseFrame(id: id, ok: ok, payload: payload, error: error)
    }

    private func parseRemoteAgents(from payload: Any?) -> [RemoteAgentRecord] {
        let dictionaries: [[String: Any]]
        if let dict = payload as? [String: Any] {
            dictionaries = dict["agents"] as? [[String: Any]] ?? []
        } else if let array = payload as? [[String: Any]] {
            dictionaries = array
        } else {
            dictionaries = []
        }

        var seen = Set<String>()
        return dictionaries.compactMap { agent in
            guard let id = normalizedNonEmptyString(agent["id"]) else { return nil }

            let displayName = normalizedNonEmptyString(agent["name"])
                ?? normalizedNonEmptyString(agent["displayName"])
                ?? id

            guard seen.insert(id.lowercased()).inserted else { return nil }
            return RemoteAgentRecord(id: id, name: displayName)
        }
    }

    private func requestChatHistoryPayload(
        using config: OpenClawConfig,
        sessionKey: String,
        limit: Int? = nil
    ) async throws -> [String: Any] {
        var params: [String: Any] = [
            "sessionKey": sessionKey
        ]
        if let limit, limit > 0 {
            params["limit"] = limit
        }

        let response = try await request(
            method: "chat.history",
            params: params,
            timeoutSeconds: max(config.timeout, 5),
            using: config
        )

        return response.payload as? [String: Any] ?? [:]
    }

    private func latestAssistantText(
        using config: OpenClawConfig,
        sessionKey: String
    ) async throws -> String? {
        let payload = try await requestChatHistoryPayload(using: config, sessionKey: sessionKey)
        let messages = payload["messages"] as? [Any] ?? []
        for entry in messages.reversed() {
            if let text = extractAssistantText(fromHistoryEntry: entry), !text.isEmpty {
                return text
            }
        }
        return nil
    }

    private func extractAssistantText(fromHistoryEntry entry: Any) -> String? {
        guard let message = entry as? [String: Any] else { return nil }
        guard normalizedNonEmptyString(message["role"])?.lowercased() == "assistant" else { return nil }
        let blocks = transcriptBlocks(fromHistoryEntry: message, role: "assistant")
        return extractMessageText(fromHistoryEntry: message, role: "assistant", blocks: blocks)
    }

    private func transcriptMessage(fromHistoryEntry entry: Any) -> ChatTranscriptMessage? {
        guard let message = entry as? [String: Any] else { return nil }
        guard let role = normalizedNonEmptyString(message["role"])?.lowercased() else { return nil }
        let blocks = transcriptBlocks(fromHistoryEntry: message, role: role)
        let text = extractMessageText(fromHistoryEntry: message, role: role, blocks: blocks) ?? ""
        guard !text.isEmpty || !blocks.isEmpty else { return nil }

        let timestampValue = message["timestamp"]
            ?? message["createdAt"]
            ?? message["createdAtMs"]
            ?? message["updatedAt"]
            ?? message["updatedAtMs"]

        return ChatTranscriptMessage(
            role: role,
            text: text,
            timestamp: normalizedHistoryTimestamp(timestampValue),
            blocks: blocks
        )
    }

    private func extractMessageText(
        fromHistoryEntry message: [String: Any],
        role: String,
        blocks: [ChatTranscriptMessage.ContentBlock]
    ) -> String? {
        let preferredKinds: Set<ChatTranscriptMessage.ContentBlock.Kind> = role == "tool_result"
            ? [.toolResult, .text]
            : [.text]

        let preferred = blocks.compactMap { block -> String? in
            guard preferredKinds.contains(block.kind) else { return nil }
            return normalizedDisplayText(
                block.toolOutput
                    ?? block.text
                    ?? block.toolName
            )
        }
        let joinedPreferred = preferred.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if !joinedPreferred.isEmpty {
            return joinedPreferred
        }

        if role == "tool_result" {
            let fallback = normalizedNonEmptyString(message["content"])
                ?? normalizedNonEmptyString(message["text"])
            return fallback
        }

        let fallback = blocks.compactMap { block -> String? in
            switch block.kind {
            case .thinking:
                return normalizedDisplayText(block.text)
            case .toolUse:
                return normalizedDisplayText(block.toolName)
            case .toolResult:
                return normalizedDisplayText(block.toolOutput)
            case .image, .unknown, .text:
                return nil
            }
        }
        let joinedFallback = fallback.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return joinedFallback.isEmpty ? nil : joinedFallback
    }

    private func transcriptBlocks(
        fromHistoryEntry message: [String: Any],
        role: String
    ) -> [ChatTranscriptMessage.ContentBlock] {
        var blocks: [ChatTranscriptMessage.ContentBlock] = []

        if let contentItems = message["content"] as? [Any] {
            blocks.append(contentsOf: contentItems.compactMap { contentBlock(from: $0, role: role) })
        } else if let contentItem = message["content"] as? [String: Any],
                  let block = contentBlock(from: contentItem, role: role) {
            blocks.append(block)
        } else if let content = normalizedNonEmptyString(message["content"]) {
            let kind: ChatTranscriptMessage.ContentBlock.Kind = role == "tool_result" ? .toolResult : .text
            blocks.append(
                ChatTranscriptMessage.ContentBlock(
                    kind: kind,
                    rawType: kind.rawValue,
                    text: kind == .text ? content : nil,
                    language: nil,
                    toolName: nil,
                    toolArguments: nil,
                    toolOutput: kind == .toolResult ? content : nil,
                    imageURL: nil,
                    imageMimeType: nil,
                    imageByteCount: nil,
                    isImageDataOmitted: false
                )
            )
        }

        if let text = normalizedNonEmptyString(message["text"]),
           !blocks.contains(where: { $0.kind == .text && $0.text == text }) {
            blocks.insert(
                ChatTranscriptMessage.ContentBlock(
                    kind: .text,
                    rawType: "text",
                    text: text,
                    language: nil,
                    toolName: nil,
                    toolArguments: nil,
                    toolOutput: nil,
                    imageURL: nil,
                    imageMimeType: nil,
                    imageByteCount: nil,
                    isImageDataOmitted: false
                ),
                at: 0
            )
        }

        return blocks
    }

    private func contentBlock(
        from rawValue: Any,
        role: String
    ) -> ChatTranscriptMessage.ContentBlock? {
        guard let item = rawValue as? [String: Any] else { return nil }

        let rawType = normalizedNonEmptyString(item["type"])?.lowercased()
        let language = normalizedNonEmptyString(item["language"])
            ?? normalizedNonEmptyString(item["lang"])

        if let thinking = normalizedNonEmptyString(item["thinking"])
            ?? normalizedNonEmptyString(item["summary"]),
           rawType == "thinking" || rawType == "reasoning" || item["thinking"] != nil {
            return ChatTranscriptMessage.ContentBlock(
                kind: .thinking,
                rawType: rawType ?? "thinking",
                text: thinking,
                language: nil,
                toolName: nil,
                toolArguments: nil,
                toolOutput: nil,
                imageURL: nil,
                imageMimeType: nil,
                imageByteCount: nil,
                isImageDataOmitted: false
            )
        }

        if rawType == "function_call"
            || rawType == "tool_use"
            || (normalizedNonEmptyString(item["name"]) != nil && item["arguments"] != nil)
        {
            return ChatTranscriptMessage.ContentBlock(
                kind: .toolUse,
                rawType: rawType ?? "tool_use",
                text: normalizedNonEmptyString(item["partialJson"]),
                language: nil,
                toolName: normalizedNonEmptyString(item["name"]) ?? "tool",
                toolArguments: normalizedNonEmptyString(item["arguments"])
                    ?? normalizedNonEmptyString(item["partialJson"]),
                toolOutput: nil,
                imageURL: nil,
                imageMimeType: nil,
                imageByteCount: nil,
                isImageDataOmitted: false
            )
        }

        if rawType == "function_call_output"
            || rawType == "tool_result"
            || rawType == "tool_output"
            || item["output"] != nil
            || role == "tool_result"
        {
            return ChatTranscriptMessage.ContentBlock(
                kind: .toolResult,
                rawType: rawType ?? "tool_result",
                text: nil,
                language: language,
                toolName: normalizedNonEmptyString(item["name"])
                    ?? normalizedNonEmptyString(item["call_id"]),
                toolArguments: nil,
                toolOutput: normalizedNonEmptyString(item["output"])
                    ?? normalizedNonEmptyString(item["text"])
                    ?? normalizedNonEmptyString(item["content"]),
                imageURL: nil,
                imageMimeType: nil,
                imageByteCount: nil,
                isImageDataOmitted: false
            )
        }

        if rawType == "image"
            || rawType == "input_image"
            || item["image"] != nil
            || item["url"] != nil
            || item["src"] != nil
        {
            return ChatTranscriptMessage.ContentBlock(
                kind: .image,
                rawType: rawType ?? "image",
                text: normalizedNonEmptyString(item["alt"])
                    ?? normalizedNonEmptyString(item["text"])
                    ?? normalizedNonEmptyString(item["label"]),
                language: nil,
                toolName: nil,
                toolArguments: nil,
                toolOutput: nil,
                imageURL: normalizedNonEmptyString(item["url"])
                    ?? normalizedNonEmptyString(item["image"])
                    ?? normalizedNonEmptyString(item["src"])
                    ?? normalizedNonEmptyString(item["path"])
                    ?? normalizedNonEmptyString(item["filePath"])
                    ?? normalizedNonEmptyString(item["stagedPath"]),
                imageMimeType: normalizedNonEmptyString(item["mimeType"])
                    ?? normalizedNonEmptyString(item["media_type"]),
                imageByteCount: normalizedInteger(item["bytes"])
                    ?? normalizedInteger(item["size"])
                    ?? normalizedInteger(item["fileSize"]),
                isImageDataOmitted: normalizedBool(item["omitted"]) ?? false
            )
        }

        if let text = normalizedNonEmptyString(item["text"]) {
            return ChatTranscriptMessage.ContentBlock(
                kind: .text,
                rawType: rawType ?? "text",
                text: text,
                language: language,
                toolName: nil,
                toolArguments: nil,
                toolOutput: nil,
                imageURL: nil,
                imageMimeType: nil,
                imageByteCount: nil,
                isImageDataOmitted: false
            )
        }

        if let reasoning = normalizedNonEmptyString(item["content"]),
           rawType == "reasoning" {
            return ChatTranscriptMessage.ContentBlock(
                kind: .thinking,
                rawType: rawType,
                text: reasoning,
                language: nil,
                toolName: nil,
                toolArguments: nil,
                toolOutput: nil,
                imageURL: nil,
                imageMimeType: nil,
                imageByteCount: nil,
                isImageDataOmitted: false
            )
        }

        return nil
    }

    private func normalizedDisplayText(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    nonisolated static func assistantText(fromChatPayload payload: [String: Any]) -> String? {
        if let text = chatPayloadText(from: payload["message"]) {
            return text
        }
        if let text = chatPayloadText(from: payload["delta"]) {
            return text
        }
        if let text = chatPayloadText(from: payload["final"]) {
            return text
        }
        if let text = chatPayloadText(from: payload["assistant"]) {
            return text
        }
        if let text = chatPayloadText(from: payload["response"]) {
            return text
        }
        if let role = normalizedChatPayloadString(payload["role"])?.lowercased(),
           role == "assistant",
           let text = chatPayloadText(from: payload) {
            return text
        }
        if let text = normalizedChatPayloadString(payload["assistantText"]) {
            return text
        }
        if let text = normalizedChatPayloadString(payload["text"]) {
            return text
        }
        return nil
    }

    nonisolated static func mergedAssistantText(previous: String, incoming: String) -> String {
        guard !incoming.isEmpty else { return previous }
        guard !previous.isEmpty else { return incoming }

        if incoming == previous {
            return previous
        }
        if incoming.hasPrefix(previous) {
            return incoming
        }
        if previous.hasPrefix(incoming) {
            return previous
        }

        let previousCharacters = Array(previous)
        let incomingCharacters = Array(incoming)
        let maxOverlap = min(previousCharacters.count, incomingCharacters.count)

        if maxOverlap > 0 {
            for overlap in stride(from: maxOverlap, through: 1, by: -1) {
                let previousSuffix = previousCharacters.suffix(overlap)
                let incomingPrefix = incomingCharacters.prefix(overlap)
                if Array(previousSuffix) == Array(incomingPrefix) {
                    return previous + String(incomingCharacters.dropFirst(overlap))
                }
            }
        }

        return previous + incoming
    }

    private nonisolated static func chatPayloadText(from value: Any?) -> String? {
        switch value {
        case let text as String:
            return normalizedChatPayloadString(text)
        case let dict as [String: Any]:
            if let direct = normalizedChatPayloadString(dict["assistantText"])
                ?? normalizedChatPayloadString(dict["text"])
                ?? normalizedChatPayloadString(dict["deltaText"]) {
                return direct
            }

            if let content = dict["content"] {
                if let contentText = chatPayloadText(from: content) {
                    return contentText
                }
            }

            for key in ["message", "delta", "final", "assistant", "response", "entry"] {
                if let nestedText = chatPayloadText(from: dict[key]) {
                    return nestedText
                }
            }

            return nil
        case let array as [Any]:
            let parts = array.compactMap { chatPayloadText(from: $0) }
            guard !parts.isEmpty else { return nil }
            let joined = parts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            return joined.isEmpty ? nil : joined
        default:
            return nil
        }
    }

    private nonisolated static func normalizedChatPayloadString(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalizedHistoryTimestamp(_ rawValue: Any?) -> Double? {
        let rawNumber: Double?
        switch rawValue {
        case let number as Double:
            rawNumber = number
        case let number as NSNumber:
            rawNumber = number.doubleValue
        case let string as String:
            rawNumber = Double(string.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            rawNumber = nil
        }

        guard let rawNumber, rawNumber > 0 else { return nil }
        if rawNumber > 1_000_000_000_000 {
            return rawNumber / 1000.0
        }
        return rawNumber
    }

    private func runtimeConfiguration(for config: OpenClawConfig) throws -> RuntimeConfiguration {
        let host = config.host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else {
            throw gatewayError("远程网关主机地址为空。")
        }

        var components = URLComponents()
        components.scheme = config.useSSL ? "wss" : "ws"
        components.host = host
        components.port = config.port

        guard let url = components.url else {
            throw gatewayError("无法构建远程 Gateway WebSocket 地址。")
        }

        let token = config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let deviceIdentity = try loadOrCreateDeviceIdentity()
        return RuntimeConfiguration(
            webSocketURL: url,
            token: token.isEmpty ? nil : token,
            timeoutSeconds: max(config.timeout, 5),
            fingerprint: [
                config.useSSL ? "wss" : "ws",
                host.lowercased(),
                String(config.port),
                token,
                deviceIdentity.deviceID
            ].joined(separator: "|"),
            deviceIdentity: deviceIdentity
        )
    }

    private func receiveJSONObject(
        from task: URLSessionWebSocketTask,
        timeoutSeconds: Int
    ) async throws -> [String: Any] {
        let message = try await withTimeout(seconds: timeoutSeconds) {
            try await task.receive()
        }

        let data: Data
        switch message {
        case .data(let rawData):
            data = rawData
        case .string(let rawString):
            data = Data(rawString.utf8)
        @unknown default:
            throw gatewayError("Gateway returned an unsupported WebSocket frame.")
        }

        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any] else {
            throw gatewayError("Gateway returned a non-object JSON frame.")
        }
        return dictionary
    }

    private func sendPreparedMessage(_ message: URLSessionWebSocketTask.Message) async throws {
        guard let socketTask else {
            throw gatewayError("Gateway socket is not connected.")
        }
        try await socketTask.send(message)
    }

    private func heartbeatToleranceSeconds() -> Int {
        max(tickIntervalSeconds * 2, defaultTickIntervalSeconds)
    }

    private func secondsSinceLastTick() -> TimeInterval {
        Date().timeIntervalSince(lastTickAt)
    }

    private func heartbeatTimeoutError() -> Error {
        gatewayError("Gateway heartbeat timed out, reconnecting on next request.")
    }

    private func failPendingResponse(withID requestID: String, error: Error) {
        guard let continuation = pendingResponses.removeValue(forKey: requestID) else { return }
        continuation.resume(throwing: error)
    }

    private func validated(response: GatewayResponseFrame, for method: String) throws -> GatewayResponseFrame {
        guard response.ok else {
            let message = (response.error?["message"] as? String) ?? "Gateway request failed: \(method)"
            throw gatewayError(message)
        }
        return response
    }

    private func updateConnectionPolicy(from payload: [String: Any]) {
        let policy = payload["policy"] as? [String: Any]
        if let tickMs = policy?["tickIntervalMs"] as? Double {
            tickIntervalSeconds = max(Int(ceil(tickMs / 1000.0)), 15)
        } else if let tickMs = policy?["tickIntervalMs"] as? Int {
            tickIntervalSeconds = max(Int(ceil(Double(tickMs) / 1000.0)), 15)
        } else {
            tickIntervalSeconds = defaultTickIntervalSeconds
        }
    }

    private func sendPing(on task: URLSessionWebSocketTask) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            task.sendPing { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func normalizedNonEmptyString(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalizedInteger(_ value: Any?) -> Int? {
        switch value {
        case let number as Int:
            return number
        case let number as NSNumber:
            return number.intValue
        case let string as String:
            return Int(string.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            return nil
        }
    }

    private func normalizedBool(_ value: Any?) -> Bool? {
        switch value {
        case let bool as Bool:
            return bool
        case let number as NSNumber:
            return number.boolValue
        case let string as String:
            switch string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "1", "yes":
                return true
            case "false", "0", "no":
                return false
            default:
                return nil
            }
        default:
            return nil
        }
    }

    private func runtimePlatformIdentifier() -> String {
#if os(macOS)
        return "darwin"
#else
        return ProcessInfo.processInfo.operatingSystemVersionString
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
#endif
    }

    private func runtimeClientVersion() -> String {
        if let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
           let buildVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        {
            let short = shortVersion.trimmingCharacters(in: .whitespacesAndNewlines)
            let build = buildVersion.trimmingCharacters(in: .whitespacesAndNewlines)
            if !short.isEmpty, !build.isEmpty {
                return "\(short) (\(build))"
            }
            if !short.isEmpty {
                return short
            }
            if !build.isEmpty {
                return build
            }
        }
        return "0.1.0"
    }

    private func buildDeviceAuthPayloadV3(
        deviceID: String,
        clientID: String,
        clientMode: String,
        role: String,
        scopes: [String],
        signedAtMilliseconds: Int,
        token: String?,
        nonce: String,
        platform: String,
        deviceFamily: String
    ) -> String {
        [
            "v3",
            deviceID,
            clientID,
            clientMode,
            role,
            scopes.joined(separator: ","),
            String(signedAtMilliseconds),
            token ?? "",
            nonce,
            normalizedDeviceMetadataForAuth(platform),
            normalizedDeviceMetadataForAuth(deviceFamily)
        ].joined(separator: "|")
    }

    private func normalizedDeviceMetadataForAuth(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func loadOrCreateDeviceIdentity() throws -> GatewayDeviceIdentity {
        let fileURL = try gatewayDeviceIdentityFileURL()

        do {
            if let existing = try loadStoredDeviceIdentity(from: fileURL) {
                return existing
            }
        } catch {
            try archiveDeviceIdentityIfPresent(at: fileURL, reason: "corrupt")
        }

        let privateKey = Curve25519.Signing.PrivateKey()
        let publicKeyRaw = Data(privateKey.publicKey.rawRepresentation)
        let identity = GatewayDeviceIdentity(
            version: 1,
            deviceID: sha256Hex(publicKeyRaw),
            privateKeyRawBase64: Data(privateKey.rawRepresentation).base64EncodedString(),
            createdAtMilliseconds: Int64(Date().timeIntervalSince1970 * 1000)
        )

        try persistDeviceIdentity(identity, to: fileURL)
        return identity
    }

    private func gatewayDeviceIdentityFileURL() throws -> URL {
        guard let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw gatewayError("无法定位应用支持目录，无法创建 OpenClaw 设备身份。")
        }

        return appSupportURL
            .appendingPathComponent("Multi-Agent-Flow", isDirectory: true)
            .appendingPathComponent("OpenClaw", isDirectory: true)
            .appendingPathComponent("identity", isDirectory: true)
            .appendingPathComponent("device-identity.json", isDirectory: false)
    }

    private func loadStoredDeviceIdentity(from fileURL: URL) throws -> GatewayDeviceIdentity? {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: fileURL)
        let stored = try JSONDecoder().decode(GatewayDeviceIdentity.self, from: data)
        let privateKeyRaw = Data(base64Encoded: stored.privateKeyRawBase64) ?? Data()
        let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: privateKeyRaw)
        let derivedDeviceID = sha256Hex(Data(privateKey.publicKey.rawRepresentation))

        if derivedDeviceID == stored.deviceID {
            return stored
        }

        let repairedIdentity = GatewayDeviceIdentity(
            version: stored.version,
            deviceID: derivedDeviceID,
            privateKeyRawBase64: stored.privateKeyRawBase64,
            createdAtMilliseconds: stored.createdAtMilliseconds
        )
        try persistDeviceIdentity(repairedIdentity, to: fileURL)
        return repairedIdentity
    }

    private func archiveCurrentDeviceIdentity(reason: String) throws {
        let fileURL = try gatewayDeviceIdentityFileURL()
        try archiveDeviceIdentityIfPresent(at: fileURL, reason: reason)
    }

    private func archiveDeviceIdentityIfPresent(at fileURL: URL, reason: String) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: fileURL.path) else { return }

        let baseName = fileURL.deletingPathExtension().lastPathComponent
        let fileExtension = fileURL.pathExtension
        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let archivedURL = fileURL.deletingLastPathComponent()
            .appendingPathComponent("\(baseName).\(reason).\(timestamp)", isDirectory: false)
            .appendingPathExtension(fileExtension)

        if fileManager.fileExists(atPath: archivedURL.path) {
            try fileManager.removeItem(at: archivedURL)
        }

        try fileManager.moveItem(at: fileURL, to: archivedURL)
    }

    private func persistDeviceIdentity(_ identity: GatewayDeviceIdentity, to fileURL: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var data = try encoder.encode(identity)
        data.append(0x0A)
        try data.write(to: fileURL, options: .atomic)
        try? fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: fileURL.path
        )
    }

    private func publicKeyRawBase64URL(for identity: GatewayDeviceIdentity) throws -> String {
        guard let privateKey = try? Curve25519.Signing.PrivateKey(
            rawRepresentation: identity.privateKeyRawRepresentation
        ) else {
            throw gatewayError("本地设备身份无效，正在尝试重新生成。", connectDetailCode: "DEVICE_IDENTITY_CORRUPT")
        }
        return Data(privateKey.publicKey.rawRepresentation).base64URLEncodedString()
    }

    private func signDevicePayload(
        _ payload: String,
        with identity: GatewayDeviceIdentity
    ) throws -> String {
        guard let privateKey = try? Curve25519.Signing.PrivateKey(
            rawRepresentation: identity.privateKeyRawRepresentation
        ),
        let signature = try? privateKey.signature(for: Data(payload.utf8))
        else {
            throw gatewayError("本地设备身份签名失败，正在尝试重新生成。", connectDetailCode: "DEVICE_IDENTITY_CORRUPT")
        }

        return signature.base64URLEncodedString()
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func encodeJSONObject(_ object: [String: Any]) throws -> Data {
        guard JSONSerialization.isValidJSONObject(object) else {
            throw gatewayError("Gateway request contains non-JSON data.")
        }
        return try JSONSerialization.data(withJSONObject: object, options: [])
    }

    private func shouldRegenerateDeviceIdentity(after error: Error) -> Bool {
        let nsError = error as NSError
        let detailCode = nsError.userInfo[GatewayErrorUserInfoKey.connectDetailCode] as? String
        let recoverableCodes: Set<String> = [
            "DEVICE_IDENTITY_CORRUPT",
            "DEVICE_AUTH_INVALID",
            "DEVICE_AUTH_DEVICE_ID_MISMATCH",
            "DEVICE_AUTH_SIGNATURE_INVALID",
            "DEVICE_AUTH_PUBLIC_KEY_INVALID"
        ]

        if let detailCode, recoverableCodes.contains(detailCode) {
            return true
        }

        let message = nsError.localizedDescription.lowercased()
        return message.contains("invalid connect params")
            && (message.contains("publickey") || message.contains("signature") || message.contains("signedat"))
    }

    private func connectErrorDetailCode(from errorShape: [String: Any]?) -> String? {
        guard
            let errorShape,
            let details = errorShape["details"] as? [String: Any],
            let code = details["code"] as? String
        else {
            return nil
        }

        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func gatewayError(_ message: String, connectDetailCode: String? = nil) -> NSError {
        var userInfo: [String: Any] = [NSLocalizedDescriptionKey: message]
        if let connectDetailCode, !connectDetailCode.isEmpty {
            userInfo[GatewayErrorUserInfoKey.connectDetailCode] = connectDetailCode
        }
        return NSError(
            domain: "OpenClawGatewayClient",
            code: 1,
            userInfo: userInfo
        )
    }
}

private extension Data {
    nonisolated func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private func withTimeout<T>(
    seconds: Int,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }

        group.addTask {
            try await _Concurrency.Task.sleep(nanoseconds: UInt64(max(seconds, 1)) * 1_000_000_000)
            throw NSError(
                domain: "OpenClawGatewayClient",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Gateway request timed out."]
            )
        }

        guard let result = try await group.next() else {
            throw NSError(
                domain: "OpenClawGatewayClient",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Gateway request ended unexpectedly."]
            )
        }

        group.cancelAll()
        return result
    }
}
