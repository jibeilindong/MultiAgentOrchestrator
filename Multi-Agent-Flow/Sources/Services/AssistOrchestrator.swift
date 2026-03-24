import Foundation
import CryptoKit

enum AssistOrchestratorError: LocalizedError {
    case emptyPrompt

    var errorDescription: String? {
        switch self {
        case .emptyPrompt:
            return "Assist prompt cannot be empty."
        }
    }
}

struct AssistSubmissionInput {
    var source: AssistRequestSource
    var invocationChannel: AssistInvocationChannel
    var intent: AssistIntent
    var scopeType: AssistScopeType
    var prompt: String
    var constraints: [String]
    var requestedAction: AssistRequestedAction
    var workflowID: UUID?
    var nodeID: UUID?
    var threadID: String?
    var relativeFilePath: String?
    var selectionStart: Int?
    var selectionEnd: Int?
    var workspaceSurface: AssistWorkspaceSurface?
    var selectedText: String?
    var fileContent: String?
    var additionalMetadata: [String: String]

    init(
        source: AssistRequestSource,
        invocationChannel: AssistInvocationChannel = .system,
        intent: AssistIntent,
        scopeType: AssistScopeType,
        prompt: String,
        constraints: [String] = [],
        requestedAction: AssistRequestedAction = .proposalOnly,
        workflowID: UUID? = nil,
        nodeID: UUID? = nil,
        threadID: String? = nil,
        relativeFilePath: String? = nil,
        selectionStart: Int? = nil,
        selectionEnd: Int? = nil,
        workspaceSurface: AssistWorkspaceSurface? = nil,
        selectedText: String? = nil,
        fileContent: String? = nil,
        additionalMetadata: [String: String] = [:]
    ) {
        self.source = source
        self.invocationChannel = invocationChannel
        self.intent = intent
        self.scopeType = scopeType
        self.prompt = prompt
        self.constraints = constraints
        self.requestedAction = requestedAction
        self.workflowID = workflowID
        self.nodeID = nodeID
        self.threadID = threadID
        self.relativeFilePath = relativeFilePath
        self.selectionStart = selectionStart
        self.selectionEnd = selectionEnd
        self.workspaceSurface = workspaceSurface
        self.selectedText = selectedText
        self.fileContent = fileContent
        self.additionalMetadata = additionalMetadata
    }
}

struct AssistSubmissionResult {
    var thread: AssistThreadRecord
    var request: AssistRequest
    var contextPack: AssistContextPack
    var proposal: AssistProposal
}

final class AssistOrchestrator {
    private let contextResolver: AssistContextResolver
    private let proposalBuilder: AssistProposalBuilder
    private let store: AssistStore

    init(
        contextResolver: AssistContextResolver = AssistContextResolver(),
        proposalBuilder: AssistProposalBuilder = AssistProposalBuilder(),
        store: AssistStore = .shared
    ) {
        self.contextResolver = contextResolver
        self.proposalBuilder = proposalBuilder
        self.store = store
    }

    func submit(
        _ input: AssistSubmissionInput,
        snapshot: AssistContextResolver.Snapshot
    ) throws -> AssistSubmissionResult {
        let trimmedPrompt = input.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            throw AssistOrchestratorError.emptyPrompt
        }

        let resolvedThreadID = normalizedThreadID(
            rawThreadID: input.threadID
        ) ?? AssistRecordID.make(prefix: "thread")
        let linkedWorkbenchThreadID = input.source == .workbenchAssist ? resolvedThreadID : nil

        let contextResolution = contextResolver.resolve(
            input: AssistContextResolver.Input(
                source: input.source,
                intent: input.intent,
                scopeType: input.scopeType,
                prompt: trimmedPrompt,
                workflowID: input.workflowID,
                nodeID: input.nodeID,
                threadID: resolvedThreadID,
                relativeFilePath: input.relativeFilePath,
                selectionStart: input.selectionStart,
                selectionEnd: input.selectionEnd,
                workspaceSurface: input.workspaceSurface,
                selectedText: input.selectedText,
                fileContent: input.fileContent,
                additionalMetadata: input.additionalMetadata
            ),
            snapshot: snapshot
        )

        var request = AssistRequest(
            source: input.source,
            invocationChannel: input.invocationChannel,
            intent: input.intent,
            scopeType: input.scopeType,
            scopeRef: contextResolution.scopeRef,
            prompt: trimmedPrompt,
            constraints: input.constraints,
            requestedAction: input.requestedAction,
            status: .resolvingContext
        )
        try store.saveRequest(request)

        do {
            let contextPack = AssistContextPack(
                requestID: request.id,
                invocationChannel: input.invocationChannel,
                scopeType: input.scopeType,
                scopeRef: contextResolution.scopeRef,
                entries: contextResolution.entries,
                contentHash: hash(for: contextResolution.entries)
            )
            try store.saveContextPack(contextPack)

            let proposal = proposalBuilder.build(
                request: request,
                contextPack: contextPack
            )
            try store.saveProposal(proposal, scopeRef: contextResolution.scopeRef)

            request.status = proposal.requiresConfirmation ? .awaitingConfirmation : .proposalReady
            try store.saveRequest(request)

            let thread = AssistThreadRecord(
                id: resolvedThreadID,
                invocationChannel: input.invocationChannel,
                source: input.source,
                title: threadTitle(for: request, proposal: proposal),
                linkedWorkbenchThreadID: linkedWorkbenchThreadID,
                projectID: contextResolution.scopeRef.projectID,
                workflowID: contextResolution.scopeRef.workflowID,
                latestRequestID: request.id,
                latestProposalID: proposal.id
            )
            try store.saveThread(thread)

            return AssistSubmissionResult(
                thread: thread,
                request: request,
                contextPack: contextPack,
                proposal: proposal
            )
        } catch {
            request.status = .failed
            try? store.saveRequest(request)
            throw error
        }
    }

    private func normalizedThreadID(
        rawThreadID: String?
    ) -> String? {
        guard let rawThreadID else { return nil }
        let trimmed = rawThreadID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func hash(
        for entries: [AssistContextEntry]
    ) -> String? {
        guard !entries.isEmpty else { return nil }
        let seed = entries.map { entry in
            let metadataSeed = entry.metadata
                .sorted(by: { $0.key < $1.key })
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: "&")
            return "\(entry.kind.rawValue)|\(entry.title)|\(entry.value)|\(metadataSeed)"
        }
        .joined(separator: "\n---\n")
        let digest = SHA256.hash(data: Data(seed.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func threadTitle(
        for request: AssistRequest,
        proposal: AssistProposal
    ) -> String {
        if let workflowName = request.scopeRef.additionalMetadata["workflowName"] {
            return "Assist / \(workflowName)"
        }
        if let relativeFilePath = request.scopeRef.relativeFilePath {
            return "Assist / \(relativeFilePath)"
        }
        return proposal.summary
    }
}
