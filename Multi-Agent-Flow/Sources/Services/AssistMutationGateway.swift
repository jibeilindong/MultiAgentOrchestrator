import Foundation
import CryptoKit
import CoreGraphics

enum AssistMutationGatewayError: LocalizedError {
    case confirmationRequired
    case outOfScope
    case denied
    case liveRuntimeMutationForbidden
    case unsupported
    case invalidPatch
    case workflowNotFound
    case missingTemplateContext

    var errorDescription: String? {
        switch self {
        case .confirmationRequired:
            return "Assist mutation requires explicit confirmation."
        case .outOfScope:
            return "Assist mutation attempted to write outside the approved scope."
        case .denied:
            return "Assist mutation was denied by the active grant policy."
        case .liveRuntimeMutationForbidden:
            return "Assist mutation cannot write directly to the live runtime."
        case .unsupported:
            return "Assist mutation is not supported for this proposal yet."
        case .invalidPatch:
            return "Assist mutation patch is invalid or missing."
        case .workflowNotFound:
            return "Assist mutation could not find the target workflow."
        case .missingTemplateContext:
            return "Assist mutation could not resolve the required template draft context."
        }
    }
}

struct AssistMutationApplyResult {
    var receipt: AssistExecutionReceipt
    var undoCheckpoint: AssistUndoCheckpoint?
    var artifacts: [AssistArtifact]
}

protocol AssistMutationGateway {
    func apply(
        proposal: AssistProposal,
        request: AssistRequest,
        contextPack: AssistContextPack
    ) throws -> AssistMutationApplyResult

    func revert(
        undoCheckpoint: AssistUndoCheckpoint
    ) throws -> AssistExecutionReceipt
}

struct NoopAssistMutationGateway: AssistMutationGateway {
    func apply(
        proposal: AssistProposal,
        request: AssistRequest,
        contextPack: AssistContextPack
    ) throws -> AssistMutationApplyResult {
        throw AssistMutationGatewayError.unsupported
    }

    func revert(
        undoCheckpoint: AssistUndoCheckpoint
    ) throws -> AssistExecutionReceipt {
        throw AssistMutationGatewayError.unsupported
    }
}

final class AppStateAssistMutationGateway: AssistMutationGateway {
    private let appState: AppState
    private let fileSystem: AssistFileSystem
    private let appSupportRootDirectory: URL
    private let templateLibrary: AgentTemplateLibraryStore

    init(
        appState: AppState,
        fileSystem: AssistFileSystem = .shared,
        appSupportRootDirectory: URL = ProjectManager.shared.appSupportRootDirectory,
        templateLibrary: AgentTemplateLibraryStore = .shared
    ) {
        self.appState = appState
        self.fileSystem = fileSystem
        self.appSupportRootDirectory = appSupportRootDirectory
        self.templateLibrary = templateLibrary
    }

    func apply(
        proposal: AssistProposal,
        request: AssistRequest,
        contextPack: AssistContextPack
    ) throws -> AssistMutationApplyResult {
        let receiptID = AssistRecordID.make(prefix: "receipt")
        var targetRefs: [AssistMutationTargetRef] = []
        var appliedChangeItemIDs: [String] = []
        var warningMessages: [String] = []
        var snapshotRefs: [AssistSnapshotRef] = []
        var artifacts: [AssistArtifact] = []

        for changeItem in proposal.changeItems {
            switch changeItem.target {
            case .workflowLayout:
                guard request.scopeRef.workspaceSurface != .runtimeReadonly else {
                    throw AssistMutationGatewayError.liveRuntimeMutationForbidden
                }

                let layoutResult = try applyWorkflowLayoutChange(
                    changeItem,
                    request: request,
                    receiptID: receiptID
                )
                targetRefs.append(layoutResult.targetRef)
                if let snapshotRef = layoutResult.snapshotRef {
                    snapshotRefs.append(snapshotRef)
                }
                warningMessages.append(contentsOf: layoutResult.warningMessages)
                appliedChangeItemIDs.append(changeItem.id)

            case .diagnosticsReport, .configuration:
                let diagnosticArtifact = try writeDiagnosticArtifact(
                    changeItem,
                    proposal: proposal,
                    request: request,
                    contextPack: contextPack
                )
                artifacts.append(diagnosticArtifact.artifact)
                targetRefs.append(diagnosticArtifact.targetRef)
                appliedChangeItemIDs.append(changeItem.id)

            case .draftText:
                let textResult = try applyDraftTextChange(
                    changeItem,
                    request: request,
                    receiptID: receiptID
                )
                targetRefs.append(textResult.targetRef)
                if let snapshotRef = textResult.snapshotRef {
                    snapshotRefs.append(snapshotRef)
                }
                warningMessages.append(contentsOf: textResult.warningMessages)
                appliedChangeItemIDs.append(changeItem.id)

            case .managedFile, .mirror:
                throw AssistMutationGatewayError.unsupported
            }
        }

        let undoCheckpointID = snapshotRefs.isEmpty ? nil : AssistRecordID.make(prefix: "undo")
        let undoCheckpoint = undoCheckpointID.map { checkpointID in
            AssistUndoCheckpoint(
                id: checkpointID,
                requestID: request.id,
                proposalID: proposal.id,
                receiptID: receiptID,
                snapshotRefs: snapshotRefs,
                note: "Assist execution snapshot for \(proposal.id)"
            )
        }

        let receipt = AssistExecutionReceipt(
            id: receiptID,
            requestID: request.id,
            proposalID: proposal.id,
            status: warningMessages.isEmpty ? .applied : .partial,
            targetRefs: targetRefs,
            appliedChangeItemIDs: appliedChangeItemIDs,
            warningMessages: warningMessages,
            undoCheckpointID: undoCheckpoint?.id
        )

        return AssistMutationApplyResult(
            receipt: receipt,
            undoCheckpoint: undoCheckpoint,
            artifacts: artifacts
        )
    }

    func revert(
        undoCheckpoint: AssistUndoCheckpoint
    ) throws -> AssistExecutionReceipt {
        var targetRefs: [AssistMutationTargetRef] = []
        var didChangeWorkflowDraft = false

        for snapshotRef in undoCheckpoint.snapshotRefs {
            switch snapshotRef.targetRef.target {
            case .workflowLayout:
                try restoreWorkflowLayoutSnapshot(snapshotRef)
                targetRefs.append(snapshotRef.targetRef)
                didChangeWorkflowDraft = true
            case .draftText:
                try restoreDraftTextSnapshot(snapshotRef)
                targetRefs.append(snapshotRef.targetRef)
            default:
                throw AssistMutationGatewayError.unsupported
            }
        }

        if didChangeWorkflowDraft {
            appState.saveDraft()
        }

        return AssistExecutionReceipt(
            requestID: undoCheckpoint.requestID,
            proposalID: undoCheckpoint.proposalID,
            status: .reverted,
            targetRefs: targetRefs,
            warningMessages: []
        )
    }

    private func applyWorkflowLayoutChange(
        _ changeItem: AssistChangeItem,
        request: AssistRequest,
        receiptID: String
    ) throws -> (targetRef: AssistMutationTargetRef, snapshotRef: AssistSnapshotRef?, warningMessages: [String]) {
        guard let patch = changeItem.patch,
              let data = patch.data(using: .utf8),
              let layoutPlan = try? JSONDecoder().decode(AssistWorkflowLayoutPlan.self, from: data) else {
            throw AssistMutationGatewayError.invalidPatch
        }

        guard let workflow = appState.workflow(for: layoutPlan.workflowID) else {
            throw AssistMutationGatewayError.workflowNotFound
        }

        if let scopedWorkflowID = request.scopeRef.workflowID,
           scopedWorkflowID != layoutPlan.workflowID {
            throw AssistMutationGatewayError.outOfScope
        }

        let targetRef = AssistMutationTargetRef(
            target: .workflowLayout,
            projectID: request.scopeRef.projectID,
            workflowID: layoutPlan.workflowID,
            nodeID: request.scopeRef.nodeID
        )

        guard !layoutPlan.placements.isEmpty else {
            return (
                targetRef,
                nil,
                ["Layout proposal did not require any node movement, so no draft coordinates changed."]
            )
        }

        let snapshot = AssistWorkflowLayoutSnapshot(
            workflowID: workflow.id,
            workflowName: workflow.name,
            nodes: workflow.nodes
                .filter { node in layoutPlan.placements.contains(where: { $0.nodeID == node.id }) }
                .map { node in
                    AssistWorkflowLayoutSnapshotNode(
                        nodeID: node.id,
                        title: node.title,
                        nodeType: node.type.rawValue,
                        x: Double(node.position.x),
                        y: Double(node.position.y)
                    )
                },
            edges: []
        )

        let snapshotRelativePath = [
            undoSnapshotDirectoryName(for: receiptID),
            "workflow-layout-\(layoutPlan.workflowID.uuidString).json"
        ].joined(separator: "/")
        let snapshotURL = fileSystem.undoSnapshotURL(
            relativePath: snapshotRelativePath,
            under: appSupportRootDirectory
        )
        let snapshotEncoder = JSONEncoder()
        snapshotEncoder.outputFormatting = [.sortedKeys]
        let snapshotData = try snapshotEncoder.encode(snapshot)
        try fileSystem.saveData(snapshotData, to: snapshotURL)

        var updatedWorkflow = workflow
        for placement in layoutPlan.placements {
            guard let index = updatedWorkflow.nodes.firstIndex(where: { $0.id == placement.nodeID }) else {
                continue
            }
            let snappedPoint = appState.snapPointToGrid(
                CGPoint(x: placement.afterX, y: placement.afterY)
            )
            updatedWorkflow.nodes[index].position = snappedPoint
        }

        appState.updateWorkflow(updatedWorkflow)
        appState.saveDraft()

        let snapshotRef = AssistSnapshotRef(
            targetRef: targetRef,
            snapshotRelativePath: snapshotRelativePath,
            contentHash: sha256(snapshotData)
        )

        return (targetRef, snapshotRef, [])
    }

    private func applyDraftTextChange(
        _ changeItem: AssistChangeItem,
        request: AssistRequest,
        receiptID: String
    ) throws -> (targetRef: AssistMutationTargetRef, snapshotRef: AssistSnapshotRef?, warningMessages: [String]) {
        guard request.scopeRef.workspaceSurface == .draft else {
            throw AssistMutationGatewayError.outOfScope
        }

        guard let patch = changeItem.patch,
              let data = patch.data(using: .utf8),
              let plan = try? JSONDecoder().decode(AssistTextMutationPlan.self, from: data) else {
            throw AssistMutationGatewayError.invalidPatch
        }

        guard let templateID = plan.templateID ?? request.scopeRef.additionalMetadata["templateID"],
              !templateID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AssistMutationGatewayError.missingTemplateContext
        }

        if let scopedRelativeFilePath = request.scopeRef.relativeFilePath,
           scopedRelativeFilePath != plan.relativeFilePath {
            throw AssistMutationGatewayError.outOfScope
        }

        let targetRef = AssistMutationTargetRef(
            target: .draftText,
            projectID: request.scopeRef.projectID,
            workflowID: request.scopeRef.workflowID,
            nodeID: request.scopeRef.nodeID,
            relativeFilePath: plan.relativeFilePath
        )

        if plan.sourceDidExist,
           plan.sourceContent == plan.resultingContent {
            return (
                targetRef,
                nil,
                ["Generated content matches the current file text, so no draft file change was applied."]
            )
        }

        let snapshot = AssistTemplateDraftFileSnapshot(
            templateID: templateID,
            relativeFilePath: plan.relativeFilePath,
            fileExisted: plan.sourceDidExist,
            contents: plan.sourceContent
        )
        let snapshotRelativePath = [
            undoSnapshotDirectoryName(for: receiptID),
            "template-draft-\(fileSystem.sanitizedIndexComponent(plan.relativeFilePath)).json"
        ].joined(separator: "/")
        let snapshotURL = fileSystem.undoSnapshotURL(
            relativePath: snapshotRelativePath,
            under: appSupportRootDirectory
        )
        let snapshotEncoder = JSONEncoder()
        snapshotEncoder.outputFormatting = [.sortedKeys]
        let snapshotData = try snapshotEncoder.encode(snapshot)
        try fileSystem.saveData(snapshotData, to: snapshotURL)

        _ = try templateLibrary.updateDraftFile(
            for: templateID,
            relativePath: plan.relativeFilePath,
            contents: plan.resultingContent
        )

        let snapshotRef = AssistSnapshotRef(
            targetRef: targetRef,
            snapshotRelativePath: snapshotRelativePath,
            contentHash: sha256(snapshotData)
        )

        return (targetRef, snapshotRef, [])
    }

    private func restoreWorkflowLayoutSnapshot(
        _ snapshotRef: AssistSnapshotRef
    ) throws {
        guard let snapshotRelativePath = snapshotRef.snapshotRelativePath else {
            throw AssistMutationGatewayError.invalidPatch
        }

        let snapshotURL = fileSystem.undoSnapshotURL(
            relativePath: snapshotRelativePath,
            under: appSupportRootDirectory
        )
        guard let snapshotData = fileSystem.loadData(from: snapshotURL),
              let snapshot = try? JSONDecoder().decode(AssistWorkflowLayoutSnapshot.self, from: snapshotData),
              let workflow = appState.workflow(for: snapshot.workflowID) else {
            throw AssistMutationGatewayError.invalidPatch
        }

        var updatedWorkflow = workflow
        for nodeSnapshot in snapshot.nodes {
            guard let index = updatedWorkflow.nodes.firstIndex(where: { $0.id == nodeSnapshot.nodeID }) else {
                continue
            }
            updatedWorkflow.nodes[index].position = CGPoint(
                x: nodeSnapshot.x,
                y: nodeSnapshot.y
            )
        }

        appState.updateWorkflow(updatedWorkflow)
    }

    private func restoreDraftTextSnapshot(
        _ snapshotRef: AssistSnapshotRef
    ) throws {
        guard let snapshotRelativePath = snapshotRef.snapshotRelativePath else {
            throw AssistMutationGatewayError.invalidPatch
        }

        let snapshotURL = fileSystem.undoSnapshotURL(
            relativePath: snapshotRelativePath,
            under: appSupportRootDirectory
        )
        guard let snapshotData = fileSystem.loadData(from: snapshotURL),
              let snapshot = try? JSONDecoder().decode(AssistTemplateDraftFileSnapshot.self, from: snapshotData) else {
            throw AssistMutationGatewayError.invalidPatch
        }

        if snapshot.fileExisted {
            _ = try templateLibrary.updateDraftFile(
                for: snapshot.templateID,
                relativePath: snapshot.relativeFilePath,
                contents: snapshot.contents ?? ""
            )
        } else {
            _ = try templateLibrary.removeDraftFile(
                for: snapshot.templateID,
                relativePath: snapshot.relativeFilePath
            )
        }
    }

    private func writeDiagnosticArtifact(
        _ changeItem: AssistChangeItem,
        proposal: AssistProposal,
        request: AssistRequest,
        contextPack: AssistContextPack
    ) throws -> (artifact: AssistArtifact, targetRef: AssistMutationTargetRef) {
        let targetRef = AssistMutationTargetRef(
            target: changeItem.target,
            projectID: request.scopeRef.projectID,
            workflowID: request.scopeRef.workflowID,
            nodeID: request.scopeRef.nodeID,
            relativeFilePath: request.scopeRef.relativeFilePath
        )

        let artifact = AssistArtifact(
            requestID: request.id,
            proposalID: proposal.id,
            kind: .report,
            title: changeItem.title,
            relativePath: "diagnostics/\(proposal.id)-\(changeItem.id).md",
            metadata: [
                "target": changeItem.target.rawValue,
                "scopeType": request.scopeType.rawValue
            ]
        )

        let exportURL = fileSystem.artifactExportURL(
            relativePath: artifact.relativePath ?? "\(artifact.id).md",
            under: appSupportRootDirectory
        )
        try fileSystem.saveText(
            diagnosticArtifactContent(
                artifact: artifact,
                proposal: proposal,
                request: request,
                contextPack: contextPack,
                changeItem: changeItem
            ),
            to: exportURL
        )

        return (artifact, targetRef)
    }

    private func diagnosticArtifactContent(
        artifact: AssistArtifact,
        proposal: AssistProposal,
        request: AssistRequest,
        contextPack: AssistContextPack,
        changeItem: AssistChangeItem
    ) -> String {
        var sections = [
            "# \(artifact.title)",
            "",
            "## Summary",
            proposal.summary,
            "",
            "## Request",
            request.prompt,
            "",
            "## Scope",
            request.scopeRef.additionalMetadata["scopeDetail"] ?? request.scopeType.rawValue
        ]

        if let rationale = proposal.rationale, !rationale.isEmpty {
            sections.append("")
            sections.append("## Rationale")
            sections.append(rationale)
        }

        if let preview = changeItem.afterPreview, !preview.isEmpty {
            sections.append("")
            sections.append("## Proposed Output")
            sections.append(preview)
        }

        let contextTitles = contextPack.entries.map(\.title)
        if !contextTitles.isEmpty {
            sections.append("")
            sections.append("## Context Entries")
            sections.append(contextTitles.joined(separator: ", "))
        }

        return sections.joined(separator: "\n")
    }

    private func undoSnapshotDirectoryName(
        for receiptID: String
    ) -> String {
        fileSystem.sanitizedIndexComponent(receiptID)
    }

    private func sha256(
        _ data: Data
    ) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
