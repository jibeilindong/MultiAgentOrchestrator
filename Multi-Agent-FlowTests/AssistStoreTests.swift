import XCTest
@testable import Multi_Agent_Flow

final class AssistStoreTests: XCTestCase {
    func testAssistFileSystemUsesLibrariesAssistNamespace() throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let fileSystem = AssistFileSystem()
        try fileSystem.ensureBaseDirectories(under: rootURL)

        let assistRoot = fileSystem.assistLibraryRootDirectory(under: rootURL)
        XCTAssertEqual(
            assistRoot,
            rootURL
                .appendingPathComponent("Libraries", isDirectory: true)
                .appendingPathComponent("Assist", isDirectory: true)
        )

        let expectedDirectories = [
            fileSystem.assistRequestsByIDRootDirectory(under: rootURL),
            fileSystem.assistProposalsByStatusRootDirectory(under: rootURL),
            fileSystem.assistReceiptsByTargetRootDirectory(under: rootURL),
            fileSystem.assistUndoSnapshotsRootDirectory(under: rootURL),
            fileSystem.assistIndexByProjectRootDirectory(under: rootURL),
            fileSystem.assistIndexByThreadRootDirectory(under: rootURL)
        ]

        for directory in expectedDirectories {
            XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path))
        }
    }

    func testAssistStorePersistsRequestProposalAndReceiptUnderSystemLibrary() throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let fileSystem = AssistFileSystem()
        let store = AssistStore(fileSystem: fileSystem, appSupportRootDirectory: rootURL)
        let projectID = UUID(uuidString: "50000000-0000-0000-0000-000000000005")!
        let workflowID = UUID(uuidString: "60000000-0000-0000-0000-000000000006")!
        let nodeID = UUID(uuidString: "70000000-0000-0000-0000-000000000007")!

        let scopeRef = AssistScopeReference(
            projectID: projectID,
            workflowID: workflowID,
            nodeID: nodeID,
            threadID: "assist-thread-1",
            relativeFilePath: "SOUL.md",
            selectionStart: 0,
            selectionEnd: 42,
            workspaceSurface: .draft
        )

        let request = AssistRequest(
            source: .workbenchAssist,
            invocationChannel: .system,
            intent: .rewriteSelection,
            scopeType: .textSelection,
            scopeRef: scopeRef,
            prompt: "Rewrite the selected content for clarity.",
            requestedAction: .proposalOnly,
            status: .proposalReady
        )
        try store.saveRequest(request)

        let contextPack = AssistContextPack(
            requestID: request.id,
            invocationChannel: .system,
            scopeType: .textSelection,
            scopeRef: scopeRef,
            entries: [
                AssistContextEntry(
                    kind: .selectedText,
                    title: "Selection",
                    value: "Original text"
                )
            ]
        )
        try store.saveContextPack(contextPack)

        let proposal = AssistProposal(
            requestID: request.id,
            contextPackID: contextPack.id,
            status: .awaitingConfirmation,
            summary: "Clarify the selected paragraph.",
            changeItems: [
                AssistChangeItem(
                    target: .draftText,
                    operation: .replace,
                    title: "Rewrite selection",
                    summary: "Replace the selected paragraph with a clearer version.",
                    relativeFilePath: "SOUL.md"
                )
            ]
        )
        try store.saveProposal(proposal, scopeRef: scopeRef)

        let targetRef = AssistMutationTargetRef(
            target: .draftText,
            projectID: projectID,
            workflowID: workflowID,
            nodeID: nodeID,
            relativeFilePath: "SOUL.md"
        )
        let receipt = AssistExecutionReceipt(
            requestID: request.id,
            proposalID: proposal.id,
            status: .applied,
            targetRefs: [targetRef],
            appliedChangeItemIDs: proposal.changeItems.map(\.id)
        )
        try store.saveReceipt(receipt)

        XCTAssertEqual(store.request(withID: request.id)?.prompt, request.prompt)
        XCTAssertEqual(store.proposal(withID: proposal.id)?.summary, proposal.summary)
        XCTAssertEqual(store.receipt(withID: receipt.id)?.status, .applied)

        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: fileSystem.requestDocumentURL(for: request.id, under: rootURL).path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: fileSystem.proposalDocumentURL(for: proposal.id, under: rootURL).path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: fileSystem.receiptDocumentURL(for: receipt.id, under: rootURL).path
            )
        )

        let projectIndexURL = fileSystem.indexDirectory(for: .project(projectID), under: rootURL)
            .appendingPathComponent("request--\(request.id).json", isDirectory: false)
        let threadIndexURL = fileSystem.indexDirectory(for: .thread("assist-thread-1"), under: rootURL)
            .appendingPathComponent("proposal--\(proposal.id).json", isDirectory: false)
        let receiptTargetIndexURL = fileSystem.receiptTargetDirectory(for: targetRef, under: rootURL)
            .appendingPathComponent("receipt--\(receipt.id).json", isDirectory: false)

        XCTAssertTrue(FileManager.default.fileExists(atPath: projectIndexURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: threadIndexURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: receiptTargetIndexURL.path))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AssistStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
