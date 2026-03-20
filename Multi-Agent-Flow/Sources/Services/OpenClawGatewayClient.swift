import Foundation

actor OpenClawGatewayClient {
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

    struct ChatSessionRecord: Hashable {
        let key: String
        let displayName: String?
        let updatedAt: Double?
    }

    struct ChatTranscriptMessage: Hashable, Sendable {
        let role: String
        let text: String
        let timestamp: Double?
    }

    private struct ChatRunState {
        var sessionKey: String?
        var state: String?
        var errorMessage: String?
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
            lastUpdatedAt = Date()
        }
    }

    private struct RuntimeConfiguration: Equatable {
        let webSocketURL: URL
        let token: String?
        let timeoutSeconds: Int
        let fingerprint: String
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

        if waitStatus == "ok" || chatState?.state == "final" {
            try? await _Concurrency.Task.sleep(nanoseconds: 150_000_000)
            if let historyText = try await latestAssistantText(
                using: config,
                sessionKey: resolvedSessionKey
            ), !historyText.isEmpty {
                agentState.assistantText = historyText
                runStates[runID] = agentState
                onAssistantTextUpdated(historyText)
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
        let runtimeConfig = try runtimeConfiguration(for: config)
        try await ensureConnected(using: runtimeConfig)

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
        let connectPayload = buildConnectPayload(
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
            task.cancel(with: .policyViolation, reason: nil)
            throw gatewayError(message)
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
    ) -> [String: Any] {
        var payload: [String: Any] = [
            "minProtocol": 3,
            "maxProtocol": 3,
            "client": [
                "id": "multi-agent-flow",
                "version": "0.1.0",
                "platform": "macos",
                "mode": "operator"
            ],
            "role": "operator",
            "scopes": [
                "operator.admin",
                "operator.read",
                "operator.write",
                "operator.approvals",
                "operator.pairing"
            ],
            "caps": [],
            "commands": [],
            "permissions": [:],
            "locale": Locale.current.identifier,
            "userAgent": "Multi-Agent-Flow/0.1.0"
        ]

        if let token = runtimeConfig.token, !token.isEmpty {
            payload["auth"] = ["token": token]
        }

        if let nonce = challengePayload["nonce"] as? String, !nonce.isEmpty {
            payload["device"] = [
                "id": "multi-agent-flow-operator",
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
                state.apply(payload: payload)
                chatRunStates[runID] = state
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
        return extractMessageText(fromHistoryEntry: message)
    }

    private func transcriptMessage(fromHistoryEntry entry: Any) -> ChatTranscriptMessage? {
        guard let message = entry as? [String: Any] else { return nil }
        guard let role = normalizedNonEmptyString(message["role"])?.lowercased() else { return nil }
        guard let text = extractMessageText(fromHistoryEntry: message), !text.isEmpty else { return nil }

        let timestampValue = message["timestamp"]
            ?? message["createdAt"]
            ?? message["createdAtMs"]
            ?? message["updatedAt"]
            ?? message["updatedAtMs"]

        return ChatTranscriptMessage(
            role: role,
            text: text,
            timestamp: normalizedHistoryTimestamp(timestampValue)
        )
    }

    private func extractMessageText(fromHistoryEntry message: [String: Any]) -> String? {
        if let contentItems = message["content"] as? [[String: Any]] {
            let parts = contentItems.compactMap { item -> String? in
                if let text = normalizedNonEmptyString(item["text"]) {
                    return text
                }
                if let thinking = normalizedNonEmptyString(item["thinking"]) {
                    return thinking
                }
                return nil
            }
            let joined = parts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            return joined.isEmpty ? nil : joined
        }

        if let contentItems = message["content"] as? [String: Any] {
            let text = normalizedNonEmptyString(contentItems["text"])
                ?? normalizedNonEmptyString(contentItems["thinking"])
            return text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? text : nil
        }

        if let content = normalizedNonEmptyString(message["content"]) {
            return content
        }

        return nil
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
        return RuntimeConfiguration(
            webSocketURL: url,
            token: token.isEmpty ? nil : token,
            timeoutSeconds: max(config.timeout, 5),
            fingerprint: [
                config.useSSL ? "wss" : "ws",
                host.lowercased(),
                String(config.port),
                token
            ].joined(separator: "|")
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

    private func encodeJSONObject(_ object: [String: Any]) throws -> Data {
        guard JSONSerialization.isValidJSONObject(object) else {
            throw gatewayError("Gateway request contains non-JSON data.")
        }
        return try JSONSerialization.data(withJSONObject: object, options: [])
    }

    private func gatewayError(_ message: String) -> NSError {
        NSError(
            domain: "OpenClawGatewayClient",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
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
