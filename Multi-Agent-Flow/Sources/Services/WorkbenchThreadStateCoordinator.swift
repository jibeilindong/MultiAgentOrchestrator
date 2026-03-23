import Foundation

struct WorkbenchThreadContext: Sendable {
    let workflowID: UUID
    let projectSessionID: String
    let threadID: String
    let sessionID: String
    let gatewaySessionKey: String
    let interactionMode: WorkbenchInteractionMode
    let threadType: RuntimeSessionSemanticType
    let threadMode: WorkbenchThreadSemanticMode
    let executionIntent: OpenClawRuntimeExecutionIntent
    let origin: String
    let agentID: UUID
    let agentName: String
}

struct WorkbenchThreadContextSample: Sendable {
    let context: WorkbenchThreadContext
    let activityAt: Date
}

struct WorkbenchThreadSummaryDescriptor: Hashable, Sendable {
    let id: String
    let workflowID: UUID
    let title: String
    let subtitle: String
    let preview: String
    let lastActivityAt: Date
    let conversationState: WorkbenchConversationState
    let activeRunStatus: WorkbenchActiveRunStatus?
    let interactionMode: WorkbenchInteractionMode
    let threadType: RuntimeSessionSemanticType
    let threadMode: WorkbenchThreadSemanticMode
    let entryAgentName: String
    let messageCount: Int
    let taskCount: Int
}

struct WorkbenchThreadSummaryCollections {
    var threadContextSamples: [String: [WorkbenchThreadContextSample]] = [:]
    var threadMessages: [String: [Message]] = [:]
    var threadTasks: [String: [Task]] = [:]
}

struct WorkbenchThreadSummaryMessageRecord {
    let threadID: String
    let message: Message
    let contextSample: WorkbenchThreadContextSample?
}

struct WorkbenchThreadSummaryTaskRecord {
    let threadID: String
    let task: Task
    let contextSample: WorkbenchThreadContextSample?
}

final class WorkbenchThreadStateCoordinator {
    func collectSummaryCollections(
        messageRecords: [WorkbenchThreadSummaryMessageRecord],
        taskRecords: [WorkbenchThreadSummaryTaskRecord]
    ) -> WorkbenchThreadSummaryCollections {
        var collections = WorkbenchThreadSummaryCollections()

        for record in messageRecords {
            collections.threadMessages[record.threadID, default: []].append(record.message)
            if let contextSample = record.contextSample {
                collections.threadContextSamples[record.threadID, default: []].append(contextSample)
            }
        }

        for record in taskRecords {
            collections.threadTasks[record.threadID, default: []].append(record.task)
            if let contextSample = record.contextSample {
                collections.threadContextSamples[record.threadID, default: []].append(contextSample)
            }
        }

        return collections
    }

    func summarizeThreads(
        workflowID: UUID,
        summaryCollections: WorkbenchThreadSummaryCollections,
        activeRunRecords: [WorkbenchActiveRunRecord],
        threadStateRecords: [WorkbenchThreadStateRecord]
    ) -> [WorkbenchThreadSummaryDescriptor] {
        summarizeThreads(
            workflowID: workflowID,
            threadMessages: summaryCollections.threadMessages,
            threadTasks: summaryCollections.threadTasks,
            threadContextSamples: summaryCollections.threadContextSamples,
            activeRunsByThreadID: activeRunRecords.reduce(into: [String: WorkbenchActiveRunRecord]()) {
                $0[$1.threadID] = $1
            },
            threadStateRecordsByThreadID: threadStateRecords.reduce(into: [String: WorkbenchThreadStateRecord]()) {
                $0[$1.threadID] = $1
            }
        )
    }

    func summarizeThreads(
        workflowID: UUID,
        threadMessages: [String: [Message]],
        threadTasks: [String: [Task]],
        threadContextSamples: [String: [WorkbenchThreadContextSample]],
        activeRunsByThreadID: [String: WorkbenchActiveRunRecord],
        threadStateRecordsByThreadID: [String: WorkbenchThreadStateRecord]
    ) -> [WorkbenchThreadSummaryDescriptor] {
        let threadIDs = Set(threadMessages.keys)
            .union(threadTasks.keys)
            .union(threadContextSamples.keys)
            .union(threadStateRecordsByThreadID.keys)

        return threadIDs.compactMap { threadID in
            summarizeThread(
                workflowID: workflowID,
                threadID: threadID,
                messages: threadMessages[threadID] ?? [],
                tasks: threadTasks[threadID] ?? [],
                contextSamples: threadContextSamples[threadID] ?? [],
                activeRunRecord: activeRunsByThreadID[threadID],
                explicitStateRecord: threadStateRecordsByThreadID[threadID]
            )
        }
        .sorted { lhs, rhs in
            if lhs.lastActivityAt != rhs.lastActivityAt {
                return lhs.lastActivityAt > rhs.lastActivityAt
            }
            return lhs.id > rhs.id
        }
    }

    func transitionThread(
        in runtimeState: inout RuntimeState,
        workflowID: UUID,
        threadID: String,
        interactionMode: WorkbenchInteractionMode,
        threadMode: WorkbenchThreadSemanticMode,
        transition: WorkbenchThreadTransition,
        at timestamp: Date = Date()
    ) {
        let resolution = WorkbenchThreadTransitionResolver.resolve(
            transition,
            interactionMode: interactionMode,
            threadMode: threadMode
        )
        updateThreadState(
            in: &runtimeState,
            workflowID: workflowID,
            threadID: threadID,
            interactionMode: resolution.interactionMode,
            threadMode: resolution.threadMode,
            state: resolution.state,
            errorMessage: resolution.errorMessage,
            at: timestamp
        )
    }

    func updateThreadState(
        in runtimeState: inout RuntimeState,
        workflowID: UUID,
        threadID: String,
        interactionMode: WorkbenchInteractionMode,
        threadMode: WorkbenchThreadSemanticMode,
        state: WorkbenchConversationState,
        errorMessage: String? = nil,
        at timestamp: Date = Date()
    ) {
        let normalizedErrorMessage = errorMessage?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedErrorMessage = normalizedErrorMessage?.isEmpty == false ? normalizedErrorMessage : nil

        if let index = runtimeState.workbenchThreadStates.firstIndex(where: { $0.threadID == threadID }) {
            let previousRecord = runtimeState.workbenchThreadStates[index]
            let stateChanged = previousRecord.state != state
                || previousRecord.interactionMode != interactionMode.rawValue
                || previousRecord.threadMode != threadMode.rawValue
                || previousRecord.lastErrorMessage != resolvedErrorMessage
            runtimeState.workbenchThreadStates[index].workflowID = workflowID.uuidString
            runtimeState.workbenchThreadStates[index].interactionMode = interactionMode.rawValue
            runtimeState.workbenchThreadStates[index].threadMode = threadMode.rawValue
            runtimeState.workbenchThreadStates[index].state = state
            runtimeState.workbenchThreadStates[index].lastErrorMessage = resolvedErrorMessage
            runtimeState.workbenchThreadStates[index].updatedAt = timestamp
            if stateChanged {
                runtimeState.workbenchThreadStates[index].lastTransitionAt = timestamp
            }
        } else {
            runtimeState.workbenchThreadStates.append(
                WorkbenchThreadStateRecord(
                    threadID: threadID,
                    workflowID: workflowID.uuidString,
                    interactionMode: interactionMode,
                    threadMode: threadMode,
                    state: state,
                    lastErrorMessage: resolvedErrorMessage,
                    lastTransitionAt: timestamp,
                    updatedAt: timestamp
                )
            )
        }

        runtimeState.lastUpdated = timestamp
    }

    func markActiveThreadStatesFailed(
        in runtimeState: inout RuntimeState,
        reason: String,
        at timestamp: Date = Date()
    ) {
        let activeThreadIDs = Set(runtimeState.activeWorkbenchRuns.map(\.threadID))
        guard !activeThreadIDs.isEmpty else { return }

        for threadID in activeThreadIDs {
            let existingRecord = runtimeState.workbenchThreadStates.first(where: { $0.threadID == threadID })
            let activeRunRecord = runtimeState.activeWorkbenchRuns.first(where: { $0.threadID == threadID })
            let interactionMode: WorkbenchInteractionMode
            if let resolvedInteractionMode = existingRecord?.resolvedInteractionMode {
                interactionMode = resolvedInteractionMode
            } else if activeRunRecord?.executionIntent == OpenClawRuntimeExecutionIntent.workflowControlled.rawValue {
                interactionMode = .run
            } else {
                interactionMode = .chat
            }

            let threadMode = existingRecord?.resolvedThreadMode
                ?? (interactionMode == .run ? .controlledRun : .autonomousConversation)
            let workflowIDString = existingRecord?.workflowID ?? activeRunRecord?.workflowID ?? ""
            let workflowID = UUID(uuidString: workflowIDString) ?? UUID()

            transitionThread(
                in: &runtimeState,
                workflowID: workflowID,
                threadID: threadID,
                interactionMode: interactionMode,
                threadMode: threadMode,
                transition: .disconnected(reason: reason),
                at: timestamp
            )
        }
    }

    private func summarizeThread(
        workflowID: UUID,
        threadID: String,
        messages: [Message],
        tasks: [Task],
        contextSamples: [WorkbenchThreadContextSample],
        activeRunRecord: WorkbenchActiveRunRecord?,
        explicitStateRecord: WorkbenchThreadStateRecord?
    ) -> WorkbenchThreadSummaryDescriptor? {
        let sortedMessages = messages.sorted { $0.timestamp < $1.timestamp }
        let sortedTasks = tasks.sorted { $0.createdAt < $1.createdAt }
        let activityDates = sortedMessages.map(\.timestamp)
            + sortedTasks.map { $0.completedAt ?? $0.startedAt ?? $0.createdAt }
        guard let lastActivityAt = activityDates.max() else { return nil }
        guard let latestContext = contextSamples.max(by: { lhs, rhs in
            if lhs.activityAt == rhs.activityAt {
                return lhs.context.threadID < rhs.context.threadID
            }
            return lhs.activityAt < rhs.activityAt
        })?.context else {
            return nil
        }

        let preferredThreadMode = WorkbenchThreadSemanticMode.preferredMode(
            from: contextSamples.map(\.context.threadMode)
        ) ?? latestContext.threadMode
        let derivedInteractionMode = explicitStateRecord?.resolvedInteractionMode ?? latestContext.interactionMode
        let derivedThreadMode = explicitStateRecord?.resolvedThreadMode ?? preferredThreadMode
        let derivedThreadType = RuntimeSessionSemanticType.preferredWorkbenchThreadType(
            from: contextSamples.map(\.context.threadType)
        ) ?? latestContext.threadType
        let conversationState = workbenchConversationState(
            interactionMode: derivedInteractionMode,
            threadMode: derivedThreadMode,
            messages: sortedMessages,
            tasks: sortedTasks,
            contextSamples: contextSamples,
            activeRunRecord: activeRunRecord,
            explicitStateRecord: explicitStateRecord
        )

        let latestUserPrompt = sortedMessages
            .last(where: { ($0.inferredRole ?? "").lowercased() == "user" })?
            .content
            .compactSingleLinePreview(limit: 52)
        let latestAssistantReply = sortedMessages
            .last(where: { ($0.inferredRole ?? "").lowercased() == "assistant" })?
            .summaryText
            .compactSingleLinePreview(limit: 72)
        let latestTaskTitle = sortedTasks.last?.title.compactSingleLinePreview(limit: 52)

        let title = latestUserPrompt
            ?? latestTaskTitle
            ?? latestAssistantReply
            ?? "\(derivedThreadMode.displayTitle) with \(latestContext.agentName)"
        let preview = latestAssistantReply
            ?? latestUserPrompt
            ?? sortedTasks.last?.description.compactSingleLinePreview(limit: 72)
            ?? latestContext.gatewaySessionKey.compactSingleLinePreview(limit: 72)

        return WorkbenchThreadSummaryDescriptor(
            id: threadID,
            workflowID: workflowID,
            title: title,
            subtitle: threadSubtitle(
                threadMode: derivedThreadMode,
                agentName: latestContext.agentName
            ),
            preview: preview,
            lastActivityAt: lastActivityAt,
            conversationState: conversationState,
            activeRunStatus: activeRunRecord?.status,
            interactionMode: derivedInteractionMode,
            threadType: derivedThreadType,
            threadMode: derivedThreadMode,
            entryAgentName: latestContext.agentName,
            messageCount: sortedMessages.count,
            taskCount: sortedTasks.count
        )
    }

    private func threadSubtitle(
        threadMode: WorkbenchThreadSemanticMode,
        agentName: String
    ) -> String {
        [threadMode.displayTitle, agentName].joined(separator: " · ")
    }

    private func workbenchConversationState(
        interactionMode: WorkbenchInteractionMode,
        threadMode: WorkbenchThreadSemanticMode,
        messages: [Message],
        tasks: [Task],
        contextSamples: [WorkbenchThreadContextSample],
        activeRunRecord: WorkbenchActiveRunRecord?,
        explicitStateRecord: WorkbenchThreadStateRecord?
    ) -> WorkbenchConversationState {
        let latestTask = tasks.last
        let latestUserMessage = messages.last(where: { ($0.inferredRole ?? "").lowercased() == "user" })
        let latestAssistantMessage = messages.last(where: { ($0.inferredRole ?? "").lowercased() == "assistant" })
        let hasRunActivity = interactionMode == .run
            || threadMode != .autonomousConversation
            || contextSamples.contains(where: { sample in
                sample.context.interactionMode == .run
                    || sample.context.threadMode != .autonomousConversation
                    || sample.context.threadType == .workflowControlled
            })

        return WorkbenchConversationStateResolver.resolve(
            WorkbenchConversationStateDerivationInput(
                interactionMode: interactionMode,
                threadMode: threadMode,
                latestTaskStatus: latestTask?.status,
                latestUserMessageAt: latestUserMessage?.timestamp,
                latestAssistantMessageAt: latestAssistantMessage?.timestamp,
                latestAssistantThinking: latestAssistantMessage?.metadata["thinking"]?.lowercased() == "true",
                latestAssistantOutputType: latestAssistantMessage?.inferredOutputType,
                hasRunActivity: hasRunActivity,
                activeRunStatus: activeRunRecord?.status,
                explicitState: explicitStateRecord?.state
            )
        )
    }
}
