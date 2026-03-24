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

struct AssistExecutionResult {
    var thread: AssistThreadRecord
    var request: AssistRequest
    var contextPack: AssistContextPack
    var proposal: AssistProposal
    var decision: AssistDecision
    var receipt: AssistExecutionReceipt?
    var undoCheckpoint: AssistUndoCheckpoint?
    var artifacts: [AssistArtifact]
}

struct AssistRevertResult {
    var thread: AssistThreadRecord
    var request: AssistRequest
    var contextPack: AssistContextPack
    var proposal: AssistProposal
    var receipt: AssistExecutionReceipt
    var undoCheckpoint: AssistUndoCheckpoint
}

final class AssistOrchestrator {
    private let contextResolver: AssistContextResolver
    private let proposalBuilder: AssistProposalBuilder
    private let store: AssistStore
    private let mutationGateway: AssistMutationGateway
    private let proposalContentGenerator: AssistProposalContentGenerator

    init(
        contextResolver: AssistContextResolver = AssistContextResolver(),
        proposalBuilder: AssistProposalBuilder = AssistProposalBuilder(),
        store: AssistStore = .shared,
        mutationGateway: AssistMutationGateway = NoopAssistMutationGateway(),
        proposalContentGenerator: AssistProposalContentGenerator = NoopAssistProposalContentGenerator()
    ) {
        self.contextResolver = contextResolver
        self.proposalBuilder = proposalBuilder
        self.store = store
        self.mutationGateway = mutationGateway
        self.proposalContentGenerator = proposalContentGenerator
    }

    func submit(
        _ input: AssistSubmissionInput,
        snapshot: AssistContextResolver.Snapshot
    ) throws -> AssistSubmissionResult {
        let prepared = try prepareSubmissionState(
            input: input,
            snapshot: snapshot
        )

        return try finalizeSubmission(
            prepared,
            generatedContent: nil
        )
    }

    func submit(
        _ input: AssistSubmissionInput,
        snapshot: AssistContextResolver.Snapshot
    ) async throws -> AssistSubmissionResult {
        let prepared = try prepareSubmissionState(
            input: input,
            snapshot: snapshot
        )

        do {
            let generatedContent = try await proposalContentGenerator.generate(
                input: input,
                request: prepared.request,
                contextPack: prepared.contextPack
            )
            return try finalizeSubmission(
                prepared,
                generatedContent: generatedContent
            )
        } catch {
            var failedRequest = prepared.request
            failedRequest.status = .failed
            try? store.saveRequest(failedRequest)
            throw error
        }
    }

    func apply(
        _ proposalID: String,
        actorID: String? = nil,
        note: String? = nil
    ) throws -> AssistExecutionResult {
        let resolved = try resolveStoredSubmission(proposalID: proposalID)
        return try apply(
            resolved,
            actorID: actorID,
            note: note
        )
    }

    func apply(
        _ submission: AssistSubmissionResult,
        actorID: String? = nil,
        note: String? = nil
    ) throws -> AssistExecutionResult {
        var request = submission.request
        var proposal = submission.proposal
        var thread = submission.thread

        let decision = AssistDecision(
            requestID: request.id,
            proposalID: proposal.id,
            disposition: .accepted,
            actorID: actorID,
            note: note,
            appliedChangeItemIDs: proposal.changeItems.map(\.id)
        )
        try store.saveDecision(decision, scopeRef: request.scopeRef)

        request.status = .applying
        try store.saveRequest(request)

        do {
            let applyResult = try mutationGateway.apply(
                proposal: proposal,
                request: request,
                contextPack: submission.contextPack
            )

            if let undoCheckpoint = applyResult.undoCheckpoint {
                try store.saveUndoCheckpoint(undoCheckpoint)
            }
            for artifact in applyResult.artifacts {
                try store.saveArtifact(artifact, scopeRef: request.scopeRef)
            }
            try store.saveReceipt(applyResult.receipt)

            proposal.artifactIDs = Array(
                Set(proposal.artifactIDs + applyResult.artifacts.map(\.id))
            ).sorted()
            proposal.latestReceiptID = applyResult.receipt.id
            proposal.latestUndoCheckpointID = applyResult.undoCheckpoint?.id
            proposal.status = proposalStatus(for: applyResult.receipt.status)
            request.status = requestStatus(for: applyResult.receipt.status)
            thread.updatedAt = Date()
            thread.latestRequestID = request.id
            thread.latestProposalID = proposal.id

            try store.saveProposal(proposal, scopeRef: request.scopeRef)
            try store.saveRequest(request)
            try store.saveThread(thread)

            return AssistExecutionResult(
                thread: thread,
                request: request,
                contextPack: submission.contextPack,
                proposal: proposal,
                decision: decision,
                receipt: applyResult.receipt,
                undoCheckpoint: applyResult.undoCheckpoint,
                artifacts: applyResult.artifacts
            )
        } catch {
            proposal.status = .failed
            request.status = .failed
            thread.updatedAt = Date()
            try? store.saveProposal(proposal, scopeRef: request.scopeRef)
            try? store.saveRequest(request)
            try? store.saveThread(thread)
            throw error
        }
    }

    func reject(
        _ proposalID: String,
        actorID: String? = nil,
        note: String? = nil
    ) throws -> AssistExecutionResult {
        let resolved = try resolveStoredSubmission(proposalID: proposalID)
        return try reject(
            resolved,
            actorID: actorID,
            note: note
        )
    }

    func reject(
        _ submission: AssistSubmissionResult,
        actorID: String? = nil,
        note: String? = nil
    ) throws -> AssistExecutionResult {
        var request = submission.request
        var proposal = submission.proposal
        var thread = submission.thread

        let decision = AssistDecision(
            requestID: request.id,
            proposalID: proposal.id,
            disposition: .rejected,
            actorID: actorID,
            note: note
        )
        try store.saveDecision(decision, scopeRef: request.scopeRef)

        proposal.status = .rejected
        request.status = .cancelled
        thread.updatedAt = Date()
        thread.latestRequestID = request.id
        thread.latestProposalID = proposal.id

        try store.saveProposal(proposal, scopeRef: request.scopeRef)
        try store.saveRequest(request)
        try store.saveThread(thread)

        return AssistExecutionResult(
            thread: thread,
            request: request,
            contextPack: submission.contextPack,
            proposal: proposal,
            decision: decision,
            receipt: nil,
            undoCheckpoint: nil,
            artifacts: []
        )
    }

    func revert(
        _ proposalID: String
    ) throws -> AssistRevertResult {
        let resolved = try resolveStoredSubmission(proposalID: proposalID)
        return try revert(resolved)
    }

    func revert(
        _ submission: AssistSubmissionResult
    ) throws -> AssistRevertResult {
        var request = submission.request
        var proposal = submission.proposal
        var thread = submission.thread

        guard let undoCheckpointID = proposal.latestUndoCheckpointID,
              let undoCheckpoint = store.undoCheckpoint(withID: undoCheckpointID) else {
            throw AssistMutationGatewayError.invalidPatch
        }

        let revertReceipt = try mutationGateway.revert(undoCheckpoint: undoCheckpoint)
        try store.saveReceipt(revertReceipt)

        proposal.latestReceiptID = revertReceipt.id
        proposal.status = .reverted
        request.status = .completed
        thread.updatedAt = Date()
        thread.latestRequestID = request.id
        thread.latestProposalID = proposal.id

        try store.saveProposal(proposal, scopeRef: request.scopeRef)
        try store.saveRequest(request)
        try store.saveThread(thread)

        return AssistRevertResult(
            thread: thread,
            request: request,
            contextPack: submission.contextPack,
            proposal: proposal,
            receipt: revertReceipt,
            undoCheckpoint: undoCheckpoint
        )
    }

    private func normalizedThreadID(
        rawThreadID: String?
    ) -> String? {
        guard let rawThreadID else { return nil }
        let trimmed = rawThreadID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func prepareSubmissionState(
        input: AssistSubmissionInput,
        snapshot: AssistContextResolver.Snapshot
    ) throws -> PreparedSubmissionState {
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

        let request = AssistRequest(
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

        let contextPack = AssistContextPack(
            requestID: request.id,
            invocationChannel: input.invocationChannel,
            scopeType: input.scopeType,
            scopeRef: contextResolution.scopeRef,
            entries: contextResolution.entries,
            contentHash: hash(for: contextResolution.entries)
        )
        try store.saveContextPack(contextPack)

        let thread = AssistThreadRecord(
            id: resolvedThreadID,
            invocationChannel: input.invocationChannel,
            source: input.source,
            title: nil,
            linkedWorkbenchThreadID: linkedWorkbenchThreadID,
            projectID: contextResolution.scopeRef.projectID,
            workflowID: contextResolution.scopeRef.workflowID,
            latestRequestID: request.id,
            latestProposalID: nil
        )

        return PreparedSubmissionState(
            thread: thread,
            request: request,
            contextPack: contextPack,
            scopeRef: contextResolution.scopeRef
        )
    }

    private func finalizeSubmission(
        _ prepared: PreparedSubmissionState,
        generatedContent: AssistGeneratedProposalContent?
    ) throws -> AssistSubmissionResult {
        var request = prepared.request

        do {
            let proposal = proposalBuilder.build(
                request: request,
                contextPack: prepared.contextPack,
                generatedContent: generatedContent
            )
            try store.saveProposal(proposal, scopeRef: prepared.scopeRef)

            request.status = proposal.requiresConfirmation ? .awaitingConfirmation : .proposalReady
            try store.saveRequest(request)

            var thread = prepared.thread
            thread.title = threadTitle(for: request, proposal: proposal)
            thread.latestRequestID = request.id
            thread.latestProposalID = proposal.id
            thread.updatedAt = Date()
            try store.saveThread(thread)

            return AssistSubmissionResult(
                thread: thread,
                request: request,
                contextPack: prepared.contextPack,
                proposal: proposal
            )
        } catch {
            request.status = .failed
            try? store.saveRequest(request)
            throw error
        }
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

    private func proposalStatus(
        for receiptStatus: AssistExecutionReceiptStatus
    ) -> AssistProposalStatus {
        switch receiptStatus {
        case .applied:
            return .applied
        case .partial:
            return .partiallyApplied
        case .failed:
            return .failed
        case .reverted:
            return .reverted
        }
    }

    private func requestStatus(
        for receiptStatus: AssistExecutionReceiptStatus
    ) -> AssistRequestStatus {
        switch receiptStatus {
        case .applied, .partial, .reverted:
            return .completed
        case .failed:
            return .failed
        }
    }

    private func resolveStoredSubmission(
        proposalID: String
    ) throws -> AssistSubmissionResult {
        guard let proposal = store.proposal(withID: proposalID),
              let request = store.request(withID: proposal.requestID),
              let contextPack = store.contextPack(withID: proposal.contextPackID) else {
            throw AssistMutationGatewayError.invalidPatch
        }

        let existingThread: AssistThreadRecord?
        if let threadID = request.scopeRef.threadID, !threadID.isEmpty {
            existingThread = store.thread(withID: threadID)
        } else {
            existingThread = nil
        }

        let thread = existingThread
            ?? AssistThreadRecord(
                id: request.scopeRef.threadID ?? AssistRecordID.make(prefix: "thread"),
                invocationChannel: request.invocationChannel,
                source: request.source,
                title: proposal.summary,
                linkedWorkbenchThreadID: request.scopeRef.threadID,
                projectID: request.scopeRef.projectID,
                workflowID: request.scopeRef.workflowID,
                latestRequestID: request.id,
                latestProposalID: proposal.id
            )

        return AssistSubmissionResult(
            thread: thread,
            request: request,
            contextPack: contextPack,
            proposal: proposal
        )
    }
}

private struct PreparedSubmissionState {
    var thread: AssistThreadRecord
    var request: AssistRequest
    var contextPack: AssistContextPack
    var scopeRef: AssistScopeReference
}
