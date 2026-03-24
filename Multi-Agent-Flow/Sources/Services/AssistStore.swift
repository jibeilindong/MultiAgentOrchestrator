import Foundation

enum AssistStoreRecordKind: String, Codable, CaseIterable, Sendable {
    case request
    case contextPack = "context_pack"
    case proposal
    case decision
    case receipt
    case undoCheckpoint = "undo_checkpoint"
    case capabilityGrant = "capability_grant"
    case artifact
    case thread
}

struct AssistStoreIndexEntry: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var recordKind: AssistStoreRecordKind
    var recordID: String
    var requestID: String?
    var proposalID: String?
    var receiptID: String?
    var threadID: String?
    var projectID: UUID?
    var workflowID: UUID?
    var nodeID: UUID?
    var relativeFilePath: String?
    var createdAt: Date
    var status: String?

    init(
        id: String? = nil,
        recordKind: AssistStoreRecordKind,
        recordID: String,
        requestID: String? = nil,
        proposalID: String? = nil,
        receiptID: String? = nil,
        threadID: String? = nil,
        projectID: UUID? = nil,
        workflowID: UUID? = nil,
        nodeID: UUID? = nil,
        relativeFilePath: String? = nil,
        createdAt: Date = Date(),
        status: String? = nil
    ) {
        self.id = id ?? "\(recordKind.rawValue)--\(recordID)"
        self.recordKind = recordKind
        self.recordID = recordID
        self.requestID = requestID
        self.proposalID = proposalID
        self.receiptID = receiptID
        self.threadID = threadID
        self.projectID = projectID
        self.workflowID = workflowID
        self.nodeID = nodeID
        self.relativeFilePath = relativeFilePath
        self.createdAt = createdAt
        self.status = status
    }
}

final class AssistStore {
    static let shared = AssistStore()

    private let queue = DispatchQueue(label: "MultiAgentFlow.AssistStore", qos: .utility)
    private let fileSystem: AssistFileSystem
    private let appSupportRootDirectory: URL

    init(
        fileSystem: AssistFileSystem = .shared,
        appSupportRootDirectory: URL = ProjectManager.shared.appSupportRootDirectory
    ) {
        self.fileSystem = fileSystem
        self.appSupportRootDirectory = appSupportRootDirectory
        try? fileSystem.ensureBaseDirectories(under: appSupportRootDirectory)
    }

    func saveRequest(_ request: AssistRequest) throws {
        try queue.sync {
            try fileSystem.ensureBaseDirectories(under: appSupportRootDirectory)
            try fileSystem.save(request, to: fileSystem.requestDocumentURL(for: request.id, under: appSupportRootDirectory))

            let indexEntry = AssistStoreIndexEntry(
                recordKind: .request,
                recordID: request.id,
                requestID: request.id,
                threadID: request.scopeRef.threadID,
                projectID: request.scopeRef.projectID,
                workflowID: request.scopeRef.workflowID,
                nodeID: request.scopeRef.nodeID,
                relativeFilePath: request.scopeRef.relativeFilePath,
                createdAt: request.createdAt,
                status: request.status.rawValue
            )

            try writeIndexEntry(
                indexEntry,
                to: fileSystem.requestDateDirectory(for: request.createdAt, under: appSupportRootDirectory)
            )
            try writeCommonIndexes(for: indexEntry)
        }
    }

    func saveContextPack(_ contextPack: AssistContextPack) throws {
        try queue.sync {
            try fileSystem.ensureBaseDirectories(under: appSupportRootDirectory)
            try fileSystem.save(
                contextPack,
                to: fileSystem.contextDocumentURL(for: contextPack.id, under: appSupportRootDirectory)
            )

            let indexEntry = AssistStoreIndexEntry(
                recordKind: .contextPack,
                recordID: contextPack.id,
                requestID: contextPack.requestID,
                threadID: contextPack.scopeRef.threadID,
                projectID: contextPack.scopeRef.projectID,
                workflowID: contextPack.scopeRef.workflowID,
                nodeID: contextPack.scopeRef.nodeID,
                relativeFilePath: contextPack.scopeRef.relativeFilePath,
                createdAt: contextPack.createdAt
            )

            try writeCommonIndexes(for: indexEntry)
        }
    }

    func saveProposal(_ proposal: AssistProposal, scopeRef: AssistScopeReference? = nil) throws {
        try queue.sync {
            try fileSystem.ensureBaseDirectories(under: appSupportRootDirectory)
            try fileSystem.save(
                proposal,
                to: fileSystem.proposalDocumentURL(for: proposal.id, under: appSupportRootDirectory)
            )

            let indexEntry = AssistStoreIndexEntry(
                recordKind: .proposal,
                recordID: proposal.id,
                requestID: proposal.requestID,
                proposalID: proposal.id,
                threadID: scopeRef?.threadID,
                projectID: scopeRef?.projectID,
                workflowID: scopeRef?.workflowID,
                nodeID: scopeRef?.nodeID,
                relativeFilePath: scopeRef?.relativeFilePath,
                createdAt: proposal.createdAt,
                status: proposal.status.rawValue
            )

            try writeIndexEntry(
                indexEntry,
                to: fileSystem.proposalStatusDirectory(for: proposal.status, under: appSupportRootDirectory)
            )
            try writeCommonIndexes(for: indexEntry)
        }
    }

    func saveDecision(_ decision: AssistDecision, scopeRef: AssistScopeReference? = nil) throws {
        try queue.sync {
            try fileSystem.ensureBaseDirectories(under: appSupportRootDirectory)
            try fileSystem.save(
                decision,
                to: fileSystem.decisionDocumentURL(for: decision.id, under: appSupportRootDirectory)
            )

            let indexEntry = AssistStoreIndexEntry(
                recordKind: .decision,
                recordID: decision.id,
                requestID: decision.requestID,
                proposalID: decision.proposalID,
                threadID: scopeRef?.threadID,
                projectID: scopeRef?.projectID,
                workflowID: scopeRef?.workflowID,
                nodeID: scopeRef?.nodeID,
                relativeFilePath: scopeRef?.relativeFilePath,
                createdAt: decision.createdAt,
                status: decision.disposition.rawValue
            )

            try writeCommonIndexes(for: indexEntry)
        }
    }

    func saveReceipt(_ receipt: AssistExecutionReceipt) throws {
        try queue.sync {
            try fileSystem.ensureBaseDirectories(under: appSupportRootDirectory)
            try fileSystem.save(
                receipt,
                to: fileSystem.receiptDocumentURL(for: receipt.id, under: appSupportRootDirectory)
            )

            let primaryTarget = receipt.targetRefs.first
            let indexEntry = AssistStoreIndexEntry(
                recordKind: .receipt,
                recordID: receipt.id,
                requestID: receipt.requestID,
                proposalID: receipt.proposalID,
                receiptID: receipt.id,
                projectID: primaryTarget?.projectID,
                workflowID: primaryTarget?.workflowID,
                nodeID: primaryTarget?.nodeID,
                relativeFilePath: primaryTarget?.relativeFilePath,
                createdAt: receipt.createdAt,
                status: receipt.status.rawValue
            )

            for targetRef in receipt.targetRefs {
                try writeIndexEntry(
                    indexEntry,
                    to: fileSystem.receiptTargetDirectory(for: targetRef, under: appSupportRootDirectory)
                )
            }
            try writeCommonIndexes(for: indexEntry)
        }
    }

    func saveUndoCheckpoint(_ undoCheckpoint: AssistUndoCheckpoint) throws {
        try queue.sync {
            try fileSystem.ensureBaseDirectories(under: appSupportRootDirectory)
            try fileSystem.save(
                undoCheckpoint,
                to: fileSystem.undoDocumentURL(for: undoCheckpoint.id, under: appSupportRootDirectory)
            )

            let primaryTarget = undoCheckpoint.snapshotRefs.first?.targetRef
            let indexEntry = AssistStoreIndexEntry(
                recordKind: .undoCheckpoint,
                recordID: undoCheckpoint.id,
                requestID: undoCheckpoint.requestID,
                proposalID: undoCheckpoint.proposalID,
                receiptID: undoCheckpoint.receiptID,
                projectID: primaryTarget?.projectID,
                workflowID: primaryTarget?.workflowID,
                nodeID: primaryTarget?.nodeID,
                relativeFilePath: primaryTarget?.relativeFilePath,
                createdAt: undoCheckpoint.createdAt
            )

            try writeCommonIndexes(for: indexEntry)
        }
    }

    func saveCapabilityGrant(_ grant: AssistCapabilityGrant) throws {
        try queue.sync {
            try fileSystem.ensureBaseDirectories(under: appSupportRootDirectory)
            try fileSystem.save(
                grant,
                to: fileSystem.grantDocumentURL(for: grant.id, under: appSupportRootDirectory)
            )

            let indexEntry = AssistStoreIndexEntry(
                recordKind: .capabilityGrant,
                recordID: grant.id,
                createdAt: grant.createdAt,
                status: grant.subjectKind.rawValue
            )

            try writeIndexEntry(
                indexEntry,
                to: fileSystem.grantSubjectDirectory(
                    for: grant.subjectKind,
                    subjectID: grant.subjectID,
                    under: appSupportRootDirectory
                )
            )
            try writeIndexEntry(
                indexEntry,
                to: fileSystem.indexDirectory(
                    for: .time(AssistStoreDateFormatter.dayKey(from: grant.createdAt)),
                    under: appSupportRootDirectory
                )
            )
        }
    }

    func saveArtifact(_ artifact: AssistArtifact, scopeRef: AssistScopeReference? = nil) throws {
        try queue.sync {
            try fileSystem.ensureBaseDirectories(under: appSupportRootDirectory)
            try fileSystem.save(
                artifact,
                to: fileSystem.artifactDocumentURL(for: artifact.id, under: appSupportRootDirectory)
            )

            let indexEntry = AssistStoreIndexEntry(
                recordKind: .artifact,
                recordID: artifact.id,
                requestID: artifact.requestID,
                proposalID: artifact.proposalID,
                threadID: scopeRef?.threadID,
                projectID: scopeRef?.projectID,
                workflowID: scopeRef?.workflowID,
                nodeID: scopeRef?.nodeID,
                relativeFilePath: scopeRef?.relativeFilePath,
                createdAt: artifact.createdAt,
                status: artifact.kind.rawValue
            )

            try writeCommonIndexes(for: indexEntry)
        }
    }

    func saveThread(_ thread: AssistThreadRecord) throws {
        try queue.sync {
            try fileSystem.ensureBaseDirectories(under: appSupportRootDirectory)
            try fileSystem.save(
                thread,
                to: fileSystem.threadDocumentURL(for: thread.id, under: appSupportRootDirectory)
            )

            let indexEntry = AssistStoreIndexEntry(
                recordKind: .thread,
                recordID: thread.id,
                requestID: thread.latestRequestID,
                proposalID: thread.latestProposalID,
                threadID: thread.linkedWorkbenchThreadID ?? thread.id,
                projectID: thread.projectID,
                workflowID: thread.workflowID,
                createdAt: thread.updatedAt,
                status: thread.invocationChannel.rawValue
            )

            try writeCommonIndexes(for: indexEntry)
        }
    }

    func request(withID requestID: String) -> AssistRequest? {
        queue.sync {
            fileSystem.load(
                AssistRequest.self,
                from: fileSystem.requestDocumentURL(for: requestID, under: appSupportRootDirectory)
            )
        }
    }

    func contextPack(withID contextPackID: String) -> AssistContextPack? {
        queue.sync {
            fileSystem.load(
                AssistContextPack.self,
                from: fileSystem.contextDocumentURL(for: contextPackID, under: appSupportRootDirectory)
            )
        }
    }

    func proposal(withID proposalID: String) -> AssistProposal? {
        queue.sync {
            fileSystem.load(
                AssistProposal.self,
                from: fileSystem.proposalDocumentURL(for: proposalID, under: appSupportRootDirectory)
            )
        }
    }

    func receipt(withID receiptID: String) -> AssistExecutionReceipt? {
        queue.sync {
            fileSystem.load(
                AssistExecutionReceipt.self,
                from: fileSystem.receiptDocumentURL(for: receiptID, under: appSupportRootDirectory)
            )
        }
    }

    func thread(withID threadID: String) -> AssistThreadRecord? {
        queue.sync {
            fileSystem.load(
                AssistThreadRecord.self,
                from: fileSystem.threadDocumentURL(for: threadID, under: appSupportRootDirectory)
            )
        }
    }

    private func writeCommonIndexes(for entry: AssistStoreIndexEntry) throws {
        if let projectID = entry.projectID {
            try writeIndexEntry(
                entry,
                to: fileSystem.indexDirectory(for: .project(projectID), under: appSupportRootDirectory)
            )
        }
        if let workflowID = entry.workflowID {
            try writeIndexEntry(
                entry,
                to: fileSystem.indexDirectory(for: .workflow(workflowID), under: appSupportRootDirectory)
            )
        }
        if let nodeID = entry.nodeID {
            try writeIndexEntry(
                entry,
                to: fileSystem.indexDirectory(for: .node(nodeID), under: appSupportRootDirectory)
            )
        }
        if let relativeFilePath = entry.relativeFilePath, !relativeFilePath.isEmpty {
            try writeIndexEntry(
                entry,
                to: fileSystem.indexDirectory(for: .file(relativeFilePath), under: appSupportRootDirectory)
            )
        }
        if let threadID = entry.threadID, !threadID.isEmpty {
            try writeIndexEntry(
                entry,
                to: fileSystem.indexDirectory(for: .thread(threadID), under: appSupportRootDirectory)
            )
        }
        try writeIndexEntry(
            entry,
            to: fileSystem.indexDirectory(
                for: .time(AssistStoreDateFormatter.dayKey(from: entry.createdAt)),
                under: appSupportRootDirectory
            )
        )
    }

    private func writeIndexEntry(
        _ entry: AssistStoreIndexEntry,
        to directory: URL
    ) throws {
        let fileName = "\(entry.recordKind.rawValue)--\(entry.recordID).json"
        let url = directory.appendingPathComponent(fileName, isDirectory: false)
        try fileSystem.save(entry, to: url)
    }
}
