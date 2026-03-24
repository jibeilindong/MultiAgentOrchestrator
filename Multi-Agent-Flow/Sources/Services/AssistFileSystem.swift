import Foundation

struct AssistFileSystem {
    static let shared = AssistFileSystem()

    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        self.decoder = decoder
    }

    func assistLibraryRootDirectory(under appSupportRootDirectory: URL) -> URL {
        appSupportRootDirectory
            .appendingPathComponent("Libraries", isDirectory: true)
            .appendingPathComponent("Assist", isDirectory: true)
    }

    func assistMetaRootDirectory(under appSupportRootDirectory: URL) -> URL {
        assistLibraryRootDirectory(under: appSupportRootDirectory)
            .appendingPathComponent("meta", isDirectory: true)
    }

    func assistTemplatesRootDirectory(under appSupportRootDirectory: URL) -> URL {
        assistLibraryRootDirectory(under: appSupportRootDirectory)
            .appendingPathComponent("templates", isDirectory: true)
    }

    func assistSystemTemplateURL(under appSupportRootDirectory: URL) -> URL {
        assistTemplatesRootDirectory(under: appSupportRootDirectory)
            .appendingPathComponent("assist-system-template.json", isDirectory: false)
    }

    func assistGrantsRootDirectory(under appSupportRootDirectory: URL) -> URL {
        assistLibraryRootDirectory(under: appSupportRootDirectory)
            .appendingPathComponent("grants", isDirectory: true)
    }

    func assistGrantByIDRootDirectory(under appSupportRootDirectory: URL) -> URL {
        assistGrantsRootDirectory(under: appSupportRootDirectory)
            .appendingPathComponent("by-id", isDirectory: true)
    }

    func assistGrantBySubjectRootDirectory(under appSupportRootDirectory: URL) -> URL {
        assistGrantsRootDirectory(under: appSupportRootDirectory)
            .appendingPathComponent("by-subject", isDirectory: true)
    }

    func assistRequestsRootDirectory(under appSupportRootDirectory: URL) -> URL {
        assistLibraryRootDirectory(under: appSupportRootDirectory)
            .appendingPathComponent("requests", isDirectory: true)
    }

    func assistRequestsByIDRootDirectory(under appSupportRootDirectory: URL) -> URL {
        assistRequestsRootDirectory(under: appSupportRootDirectory)
            .appendingPathComponent("by-id", isDirectory: true)
    }

    func assistRequestsByDateRootDirectory(under appSupportRootDirectory: URL) -> URL {
        assistRequestsRootDirectory(under: appSupportRootDirectory)
            .appendingPathComponent("by-date", isDirectory: true)
    }

    func assistContextsRootDirectory(under appSupportRootDirectory: URL) -> URL {
        assistLibraryRootDirectory(under: appSupportRootDirectory)
            .appendingPathComponent("contexts", isDirectory: true)
    }

    func assistContextsByIDRootDirectory(under appSupportRootDirectory: URL) -> URL {
        assistContextsRootDirectory(under: appSupportRootDirectory)
            .appendingPathComponent("by-id", isDirectory: true)
    }

    func assistProposalsRootDirectory(under appSupportRootDirectory: URL) -> URL {
        assistLibraryRootDirectory(under: appSupportRootDirectory)
            .appendingPathComponent("proposals", isDirectory: true)
    }

    func assistProposalsByIDRootDirectory(under appSupportRootDirectory: URL) -> URL {
        assistProposalsRootDirectory(under: appSupportRootDirectory)
            .appendingPathComponent("by-id", isDirectory: true)
    }

    func assistProposalsByStatusRootDirectory(under appSupportRootDirectory: URL) -> URL {
        assistProposalsRootDirectory(under: appSupportRootDirectory)
            .appendingPathComponent("by-status", isDirectory: true)
    }

    func assistDecisionsRootDirectory(under appSupportRootDirectory: URL) -> URL {
        assistLibraryRootDirectory(under: appSupportRootDirectory)
            .appendingPathComponent("decisions", isDirectory: true)
    }

    func assistDecisionsByIDRootDirectory(under appSupportRootDirectory: URL) -> URL {
        assistDecisionsRootDirectory(under: appSupportRootDirectory)
            .appendingPathComponent("by-id", isDirectory: true)
    }

    func assistReceiptsRootDirectory(under appSupportRootDirectory: URL) -> URL {
        assistLibraryRootDirectory(under: appSupportRootDirectory)
            .appendingPathComponent("receipts", isDirectory: true)
    }

    func assistReceiptsByIDRootDirectory(under appSupportRootDirectory: URL) -> URL {
        assistReceiptsRootDirectory(under: appSupportRootDirectory)
            .appendingPathComponent("by-id", isDirectory: true)
    }

    func assistReceiptsByTargetRootDirectory(under appSupportRootDirectory: URL) -> URL {
        assistReceiptsRootDirectory(under: appSupportRootDirectory)
            .appendingPathComponent("by-target", isDirectory: true)
    }

    func assistUndoRootDirectory(under appSupportRootDirectory: URL) -> URL {
        assistLibraryRootDirectory(under: appSupportRootDirectory)
            .appendingPathComponent("undo", isDirectory: true)
    }

    func assistUndoByReceiptRootDirectory(under appSupportRootDirectory: URL) -> URL {
        assistUndoRootDirectory(under: appSupportRootDirectory)
            .appendingPathComponent("by-receipt", isDirectory: true)
    }

    func assistUndoSnapshotsRootDirectory(under appSupportRootDirectory: URL) -> URL {
        assistUndoRootDirectory(under: appSupportRootDirectory)
            .appendingPathComponent("snapshots", isDirectory: true)
    }

    func assistArtifactsRootDirectory(under appSupportRootDirectory: URL) -> URL {
        assistLibraryRootDirectory(under: appSupportRootDirectory)
            .appendingPathComponent("artifacts", isDirectory: true)
    }

    func assistArtifactsByIDRootDirectory(under appSupportRootDirectory: URL) -> URL {
        assistArtifactsRootDirectory(under: appSupportRootDirectory)
            .appendingPathComponent("by-id", isDirectory: true)
    }

    func assistArtifactsExportsRootDirectory(under appSupportRootDirectory: URL) -> URL {
        assistArtifactsRootDirectory(under: appSupportRootDirectory)
            .appendingPathComponent("exports", isDirectory: true)
    }

    func assistThreadsRootDirectory(under appSupportRootDirectory: URL) -> URL {
        assistLibraryRootDirectory(under: appSupportRootDirectory)
            .appendingPathComponent("threads", isDirectory: true)
    }

    func assistThreadsByIDRootDirectory(under appSupportRootDirectory: URL) -> URL {
        assistThreadsRootDirectory(under: appSupportRootDirectory)
            .appendingPathComponent("by-id", isDirectory: true)
    }

    func assistThreadsLogsRootDirectory(under appSupportRootDirectory: URL) -> URL {
        assistThreadsRootDirectory(under: appSupportRootDirectory)
            .appendingPathComponent("logs", isDirectory: true)
    }

    func assistIndexesRootDirectory(under appSupportRootDirectory: URL) -> URL {
        assistLibraryRootDirectory(under: appSupportRootDirectory)
            .appendingPathComponent("indexes", isDirectory: true)
    }

    func assistIndexByProjectRootDirectory(under appSupportRootDirectory: URL) -> URL {
        assistIndexesRootDirectory(under: appSupportRootDirectory)
            .appendingPathComponent("by-project", isDirectory: true)
    }

    func assistIndexByWorkflowRootDirectory(under appSupportRootDirectory: URL) -> URL {
        assistIndexesRootDirectory(under: appSupportRootDirectory)
            .appendingPathComponent("by-workflow", isDirectory: true)
    }

    func assistIndexByNodeRootDirectory(under appSupportRootDirectory: URL) -> URL {
        assistIndexesRootDirectory(under: appSupportRootDirectory)
            .appendingPathComponent("by-node", isDirectory: true)
    }

    func assistIndexByFileRootDirectory(under appSupportRootDirectory: URL) -> URL {
        assistIndexesRootDirectory(under: appSupportRootDirectory)
            .appendingPathComponent("by-file", isDirectory: true)
    }

    func assistIndexByThreadRootDirectory(under appSupportRootDirectory: URL) -> URL {
        assistIndexesRootDirectory(under: appSupportRootDirectory)
            .appendingPathComponent("by-thread", isDirectory: true)
    }

    func assistIndexByTimeRootDirectory(under appSupportRootDirectory: URL) -> URL {
        assistIndexesRootDirectory(under: appSupportRootDirectory)
            .appendingPathComponent("by-time", isDirectory: true)
    }

    func requestDocumentURL(for requestID: String, under appSupportRootDirectory: URL) -> URL {
        assistRequestsByIDRootDirectory(under: appSupportRootDirectory)
            .appendingPathComponent("\(requestID).json", isDirectory: false)
    }

    func contextDocumentURL(for contextID: String, under appSupportRootDirectory: URL) -> URL {
        assistContextsByIDRootDirectory(under: appSupportRootDirectory)
            .appendingPathComponent("\(contextID).json", isDirectory: false)
    }

    func proposalDocumentURL(for proposalID: String, under appSupportRootDirectory: URL) -> URL {
        assistProposalsByIDRootDirectory(under: appSupportRootDirectory)
            .appendingPathComponent("\(proposalID).json", isDirectory: false)
    }

    func decisionDocumentURL(for decisionID: String, under appSupportRootDirectory: URL) -> URL {
        assistDecisionsByIDRootDirectory(under: appSupportRootDirectory)
            .appendingPathComponent("\(decisionID).json", isDirectory: false)
    }

    func receiptDocumentURL(for receiptID: String, under appSupportRootDirectory: URL) -> URL {
        assistReceiptsByIDRootDirectory(under: appSupportRootDirectory)
            .appendingPathComponent("\(receiptID).json", isDirectory: false)
    }

    func undoDocumentURL(for undoID: String, under appSupportRootDirectory: URL) -> URL {
        assistUndoByReceiptRootDirectory(under: appSupportRootDirectory)
            .appendingPathComponent("\(undoID).json", isDirectory: false)
    }

    func grantDocumentURL(for grantID: String, under appSupportRootDirectory: URL) -> URL {
        assistGrantByIDRootDirectory(under: appSupportRootDirectory)
            .appendingPathComponent("\(grantID).json", isDirectory: false)
    }

    func artifactDocumentURL(for artifactID: String, under appSupportRootDirectory: URL) -> URL {
        assistArtifactsByIDRootDirectory(under: appSupportRootDirectory)
            .appendingPathComponent("\(artifactID).json", isDirectory: false)
    }

    func threadDocumentURL(for threadID: String, under appSupportRootDirectory: URL) -> URL {
        assistThreadsByIDRootDirectory(under: appSupportRootDirectory)
            .appendingPathComponent("\(threadID).json", isDirectory: false)
    }

    func proposalStatusDirectory(
        for status: AssistProposalStatus,
        under appSupportRootDirectory: URL
    ) -> URL {
        assistProposalsByStatusRootDirectory(under: appSupportRootDirectory)
            .appendingPathComponent(status.rawValue, isDirectory: true)
    }

    func requestDateDirectory(for date: Date, under appSupportRootDirectory: URL) -> URL {
        assistRequestsByDateRootDirectory(under: appSupportRootDirectory)
            .appendingPathComponent(AssistStoreDateFormatter.dayKey(from: date), isDirectory: true)
    }

    func grantSubjectDirectory(
        for subjectKind: AssistGrantSubjectKind,
        subjectID: String,
        under appSupportRootDirectory: URL
    ) -> URL {
        let directoryName = "\(subjectKind.rawValue)--\(sanitizedIndexComponent(subjectID))"
        return assistGrantBySubjectRootDirectory(under: appSupportRootDirectory)
            .appendingPathComponent(directoryName, isDirectory: true)
    }

    func receiptTargetDirectory(
        for targetRef: AssistMutationTargetRef,
        under appSupportRootDirectory: URL
    ) -> URL {
        let descriptor = receiptTargetDescriptor(for: targetRef)
        return assistReceiptsByTargetRootDirectory(under: appSupportRootDirectory)
            .appendingPathComponent(sanitizedIndexComponent(descriptor), isDirectory: true)
    }

    func indexDirectory(
        for scope: AssistIndexScope,
        under appSupportRootDirectory: URL
    ) -> URL {
        switch scope {
        case let .project(projectID):
            return assistIndexByProjectRootDirectory(under: appSupportRootDirectory)
                .appendingPathComponent(projectID.uuidString, isDirectory: true)
        case let .workflow(workflowID):
            return assistIndexByWorkflowRootDirectory(under: appSupportRootDirectory)
                .appendingPathComponent(workflowID.uuidString, isDirectory: true)
        case let .node(nodeID):
            return assistIndexByNodeRootDirectory(under: appSupportRootDirectory)
                .appendingPathComponent(nodeID.uuidString, isDirectory: true)
        case let .file(relativePath):
            return assistIndexByFileRootDirectory(under: appSupportRootDirectory)
                .appendingPathComponent(sanitizedIndexComponent(relativePath), isDirectory: true)
        case let .thread(threadID):
            return assistIndexByThreadRootDirectory(under: appSupportRootDirectory)
                .appendingPathComponent(sanitizedIndexComponent(threadID), isDirectory: true)
        case let .time(dayKey):
            return assistIndexByTimeRootDirectory(under: appSupportRootDirectory)
                .appendingPathComponent(dayKey, isDirectory: true)
        }
    }

    func ensureBaseDirectories(under appSupportRootDirectory: URL) throws {
        let directories = [
            assistLibraryRootDirectory(under: appSupportRootDirectory),
            assistMetaRootDirectory(under: appSupportRootDirectory),
            assistTemplatesRootDirectory(under: appSupportRootDirectory),
            assistGrantByIDRootDirectory(under: appSupportRootDirectory),
            assistGrantBySubjectRootDirectory(under: appSupportRootDirectory),
            assistRequestsByIDRootDirectory(under: appSupportRootDirectory),
            assistRequestsByDateRootDirectory(under: appSupportRootDirectory),
            assistContextsByIDRootDirectory(under: appSupportRootDirectory),
            assistProposalsByIDRootDirectory(under: appSupportRootDirectory),
            assistProposalsByStatusRootDirectory(under: appSupportRootDirectory),
            assistDecisionsByIDRootDirectory(under: appSupportRootDirectory),
            assistReceiptsByIDRootDirectory(under: appSupportRootDirectory),
            assistReceiptsByTargetRootDirectory(under: appSupportRootDirectory),
            assistUndoByReceiptRootDirectory(under: appSupportRootDirectory),
            assistUndoSnapshotsRootDirectory(under: appSupportRootDirectory),
            assistArtifactsByIDRootDirectory(under: appSupportRootDirectory),
            assistArtifactsExportsRootDirectory(under: appSupportRootDirectory),
            assistThreadsByIDRootDirectory(under: appSupportRootDirectory),
            assistThreadsLogsRootDirectory(under: appSupportRootDirectory),
            assistIndexByProjectRootDirectory(under: appSupportRootDirectory),
            assistIndexByWorkflowRootDirectory(under: appSupportRootDirectory),
            assistIndexByNodeRootDirectory(under: appSupportRootDirectory),
            assistIndexByFileRootDirectory(under: appSupportRootDirectory),
            assistIndexByThreadRootDirectory(under: appSupportRootDirectory),
            assistIndexByTimeRootDirectory(under: appSupportRootDirectory)
        ]

        for directory in directories {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    func save<T: Encodable>(_ value: T, to url: URL) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    func receiptTargetDescriptor(for targetRef: AssistMutationTargetRef) -> String {
        if let projectID = targetRef.projectID {
            return "project-\(projectID.uuidString)-\(targetRef.target.rawValue)"
        }
        if let workflowID = targetRef.workflowID {
            return "workflow-\(workflowID.uuidString)-\(targetRef.target.rawValue)"
        }
        if let nodeID = targetRef.nodeID {
            return "node-\(nodeID.uuidString)-\(targetRef.target.rawValue)"
        }
        if let relativeFilePath = targetRef.relativeFilePath, !relativeFilePath.isEmpty {
            return "file-\(relativeFilePath)-\(targetRef.target.rawValue)"
        }
        return "target-\(targetRef.target.rawValue)"
    }

    func sanitizedIndexComponent(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "unknown" }

        let filtered = trimmed.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) {
                return Character(scalar)
            }
            if scalar == "-" || scalar == "_" || scalar == "." {
                return Character(scalar)
            }
            return "_"
        }

        let normalized = String(filtered)
            .replacingOccurrences(of: "__", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return normalized.isEmpty ? "unknown" : normalized
    }
}

enum AssistIndexScope: Hashable, Sendable {
    case project(UUID)
    case workflow(UUID)
    case node(UUID)
    case file(String)
    case thread(String)
    case time(String)
}

enum AssistStoreDateFormatter {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .autoupdatingCurrent
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func dayKey(from date: Date) -> String {
        formatter.string(from: date)
    }
}
