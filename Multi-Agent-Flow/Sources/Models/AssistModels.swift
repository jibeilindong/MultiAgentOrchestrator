import Foundation

enum AssistInvocationChannel: String, Codable, CaseIterable, Sendable {
    case system
    case workflow
}

enum AssistRequestSource: String, Codable, CaseIterable, Sendable {
    case workbenchAssist = "workbench_assist"
    case inlineEditor = "inline_editor"
    case workflowNode = "workflow_node"
    case diagnosticsPanel = "diagnostics_panel"
    case unknown
}

enum AssistIntent: String, Codable, CaseIterable, Sendable {
    case rewriteSelection = "rewrite_selection"
    case completeTemplate = "complete_template"
    case modifyManagedContent = "modify_managed_content"
    case reorganizeWorkflow = "reorganize_workflow"
    case inspectConfiguration = "inspect_configuration"
    case inspectPerformance = "inspect_performance"
    case explainIssue = "explain_issue"
    case custom
}

enum AssistScopeType: String, Codable, CaseIterable, Sendable {
    case textSelection = "text_selection"
    case file
    case node
    case workflow
    case project
}

enum AssistWorkspaceSurface: String, Codable, CaseIterable, Sendable {
    case draft
    case managedWorkspace = "managed_workspace"
    case mirror
    case runtimeReadonly = "runtime_readonly"
}

enum AssistRequestedAction: String, Codable, CaseIterable, Sendable {
    case proposalOnly = "proposal_only"
    case applyToDraft = "apply_to_draft"
    case applyToManagedWorkspace = "apply_to_managed_workspace"
    case applyToMirror = "apply_to_mirror"
}

enum AssistRequestStatus: String, Codable, CaseIterable, Sendable {
    case queued
    case resolvingContext = "resolving_context"
    case proposalReady = "proposal_ready"
    case awaitingConfirmation = "awaiting_confirmation"
    case applying
    case completed
    case failed
    case cancelled
}

enum AssistContextEntryKind: String, Codable, CaseIterable, Sendable {
    case userIntent = "user_intent"
    case selectedText = "selected_text"
    case fileContent = "file_content"
    case nodeMetadata = "node_metadata"
    case workflowLayout = "workflow_layout"
    case runtimeSnapshot = "runtime_snapshot"
    case systemHint = "system_hint"
}

enum AssistMutationTarget: String, Codable, CaseIterable, Sendable {
    case draftText = "draft_text"
    case managedFile = "managed_file"
    case mirror
    case configuration
    case workflowLayout = "workflow_layout"
    case diagnosticsReport = "diagnostics_report"
}

enum AssistChangeOperationKind: String, Codable, CaseIterable, Sendable {
    case replace
    case insert
    case delete
    case patch
    case annotate
    case suggest
}

enum AssistProposalStatus: String, Codable, CaseIterable, Sendable {
    case drafted
    case awaitingConfirmation = "awaiting_confirmation"
    case applied
    case rejected
    case failed
    case reverted
    case partiallyApplied = "partially_applied"
}

enum AssistDecisionDisposition: String, Codable, CaseIterable, Sendable {
    case accepted
    case rejected
    case partiallyAccepted = "partially_accepted"
    case expired
}

enum AssistExecutionReceiptStatus: String, Codable, CaseIterable, Sendable {
    case applied
    case partial
    case failed
    case reverted
}

enum AssistCapability: String, Codable, CaseIterable, Sendable {
    case invokeAssist = "invoke_assist"
    case generateProposal = "generate_proposal"
    case applyDraftMutation = "apply_draft_mutation"
    case applyManagedWorkspaceMutation = "apply_managed_workspace_mutation"
    case applyMirrorMutation = "apply_mirror_mutation"
    case exportAuditPackage = "export_audit_package"
    case readDiagnostics = "read_diagnostics"
}

enum AssistGrantSubjectKind: String, Codable, CaseIterable, Sendable {
    case systemPolicy = "system_policy"
    case featureFlag = "feature_flag"
    case userRole = "user_role"
    case internalUser = "internal_user"
    case workflowNode = "workflow_node"
}

enum AssistArtifactKind: String, Codable, CaseIterable, Sendable {
    case diff
    case preview
    case report
    case export
    case formDraft = "form_draft"
}

struct AssistScopeReference: Codable, Hashable, Sendable {
    var projectID: UUID?
    var workflowID: UUID?
    var nodeID: UUID?
    var threadID: String?
    var relativeFilePath: String?
    var selectionStart: Int?
    var selectionEnd: Int?
    var workspaceSurface: AssistWorkspaceSurface?
    var additionalMetadata: [String: String]

    init(
        projectID: UUID? = nil,
        workflowID: UUID? = nil,
        nodeID: UUID? = nil,
        threadID: String? = nil,
        relativeFilePath: String? = nil,
        selectionStart: Int? = nil,
        selectionEnd: Int? = nil,
        workspaceSurface: AssistWorkspaceSurface? = nil,
        additionalMetadata: [String: String] = [:]
    ) {
        self.projectID = projectID
        self.workflowID = workflowID
        self.nodeID = nodeID
        self.threadID = threadID
        self.relativeFilePath = relativeFilePath
        self.selectionStart = selectionStart
        self.selectionEnd = selectionEnd
        self.workspaceSurface = workspaceSurface
        self.additionalMetadata = additionalMetadata
    }
}

struct AssistContextEntry: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var kind: AssistContextEntryKind
    var title: String
    var value: String
    var metadata: [String: String]

    init(
        id: String = AssistRecordID.make(prefix: "ctxentry"),
        kind: AssistContextEntryKind,
        title: String,
        value: String,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.value = value
        self.metadata = metadata
    }
}

struct AssistChangeItem: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var target: AssistMutationTarget
    var operation: AssistChangeOperationKind
    var title: String
    var summary: String
    var relativeFilePath: String?
    var beforePreview: String?
    var afterPreview: String?
    var patch: String?
    var warnings: [String]
    var scopeRef: AssistScopeReference?

    init(
        id: String = AssistRecordID.make(prefix: "change"),
        target: AssistMutationTarget,
        operation: AssistChangeOperationKind,
        title: String,
        summary: String,
        relativeFilePath: String? = nil,
        beforePreview: String? = nil,
        afterPreview: String? = nil,
        patch: String? = nil,
        warnings: [String] = [],
        scopeRef: AssistScopeReference? = nil
    ) {
        self.id = id
        self.target = target
        self.operation = operation
        self.title = title
        self.summary = summary
        self.relativeFilePath = relativeFilePath
        self.beforePreview = beforePreview
        self.afterPreview = afterPreview
        self.patch = patch
        self.warnings = warnings
        self.scopeRef = scopeRef
    }
}

struct AssistMutationTargetRef: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var target: AssistMutationTarget
    var projectID: UUID?
    var workflowID: UUID?
    var nodeID: UUID?
    var relativeFilePath: String?

    init(
        id: String = AssistRecordID.make(prefix: "target"),
        target: AssistMutationTarget,
        projectID: UUID? = nil,
        workflowID: UUID? = nil,
        nodeID: UUID? = nil,
        relativeFilePath: String? = nil
    ) {
        self.id = id
        self.target = target
        self.projectID = projectID
        self.workflowID = workflowID
        self.nodeID = nodeID
        self.relativeFilePath = relativeFilePath
    }
}

struct AssistWorkflowLayoutSnapshot: Codable, Hashable, Sendable {
    var workflowID: UUID
    var workflowName: String
    var nodes: [AssistWorkflowLayoutSnapshotNode]
    var edges: [AssistWorkflowLayoutSnapshotEdge]

    init(
        workflowID: UUID,
        workflowName: String,
        nodes: [AssistWorkflowLayoutSnapshotNode],
        edges: [AssistWorkflowLayoutSnapshotEdge]
    ) {
        self.workflowID = workflowID
        self.workflowName = workflowName
        self.nodes = nodes
        self.edges = edges
    }
}

struct AssistWorkflowLayoutSnapshotNode: Codable, Hashable, Sendable {
    var nodeID: UUID
    var title: String
    var nodeType: String
    var x: Double
    var y: Double

    init(
        nodeID: UUID,
        title: String,
        nodeType: String,
        x: Double,
        y: Double
    ) {
        self.nodeID = nodeID
        self.title = title
        self.nodeType = nodeType
        self.x = x
        self.y = y
    }
}

struct AssistWorkflowLayoutSnapshotEdge: Codable, Hashable, Sendable {
    var fromNodeID: UUID
    var toNodeID: UUID

    init(
        fromNodeID: UUID,
        toNodeID: UUID
    ) {
        self.fromNodeID = fromNodeID
        self.toNodeID = toNodeID
    }
}

struct AssistWorkflowLayoutPlan: Codable, Hashable, Sendable {
    var workflowID: UUID
    var workflowName: String
    var scopeType: AssistScopeType
    var scopedNodeID: UUID?
    var placements: [AssistWorkflowNodePlacement]
    var note: String?

    init(
        workflowID: UUID,
        workflowName: String,
        scopeType: AssistScopeType,
        scopedNodeID: UUID? = nil,
        placements: [AssistWorkflowNodePlacement],
        note: String? = nil
    ) {
        self.workflowID = workflowID
        self.workflowName = workflowName
        self.scopeType = scopeType
        self.scopedNodeID = scopedNodeID
        self.placements = placements
        self.note = note
    }
}

struct AssistWorkflowNodePlacement: Codable, Hashable, Sendable {
    var nodeID: UUID
    var title: String
    var beforeX: Double
    var beforeY: Double
    var afterX: Double
    var afterY: Double

    init(
        nodeID: UUID,
        title: String,
        beforeX: Double,
        beforeY: Double,
        afterX: Double,
        afterY: Double
    ) {
        self.nodeID = nodeID
        self.title = title
        self.beforeX = beforeX
        self.beforeY = beforeY
        self.afterX = afterX
        self.afterY = afterY
    }
}

enum AssistTextMutationKind: String, Codable, CaseIterable, Sendable {
    case replaceFile = "replace_file"
}

struct AssistTextMutationPlan: Codable, Hashable, Sendable {
    var kind: AssistTextMutationKind
    var relativeFilePath: String
    var workspaceSurface: AssistWorkspaceSurface
    var templateID: String?
    var templateName: String?
    var sourceDidExist: Bool
    var sourceContent: String?
    var resultingContent: String
    var summary: String?
    var rationale: String?
    var warnings: [String]

    init(
        kind: AssistTextMutationKind = .replaceFile,
        relativeFilePath: String,
        workspaceSurface: AssistWorkspaceSurface = .draft,
        templateID: String? = nil,
        templateName: String? = nil,
        sourceDidExist: Bool,
        sourceContent: String? = nil,
        resultingContent: String,
        summary: String? = nil,
        rationale: String? = nil,
        warnings: [String] = []
    ) {
        self.kind = kind
        self.relativeFilePath = relativeFilePath
        self.workspaceSurface = workspaceSurface
        self.templateID = templateID
        self.templateName = templateName
        self.sourceDidExist = sourceDidExist
        self.sourceContent = sourceContent
        self.resultingContent = resultingContent
        self.summary = summary
        self.rationale = rationale
        self.warnings = warnings
    }
}

struct AssistTemplateDraftFileSnapshot: Codable, Hashable, Sendable {
    var templateID: String
    var relativeFilePath: String
    var fileExisted: Bool
    var contents: String?

    init(
        templateID: String,
        relativeFilePath: String,
        fileExisted: Bool,
        contents: String? = nil
    ) {
        self.templateID = templateID
        self.relativeFilePath = relativeFilePath
        self.fileExisted = fileExisted
        self.contents = contents
    }
}

struct AssistSnapshotRef: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var targetRef: AssistMutationTargetRef
    var snapshotRelativePath: String?
    var contentHash: String?

    init(
        id: String = AssistRecordID.make(prefix: "snapshot"),
        targetRef: AssistMutationTargetRef,
        snapshotRelativePath: String? = nil,
        contentHash: String? = nil
    ) {
        self.id = id
        self.targetRef = targetRef
        self.snapshotRelativePath = snapshotRelativePath
        self.contentHash = contentHash
    }
}

struct AssistRequest: Identifiable, Codable, Hashable, Sendable {
    static let schemaVersion = "assist.request.v1"

    let id: String
    var schemaVersion: String
    var createdAt: Date
    var source: AssistRequestSource
    var invocationChannel: AssistInvocationChannel
    var intent: AssistIntent
    var scopeType: AssistScopeType
    var scopeRef: AssistScopeReference
    var prompt: String
    var constraints: [String]
    var requestedAction: AssistRequestedAction
    var status: AssistRequestStatus

    init(
        id: String = AssistRecordID.make(prefix: "req"),
        schemaVersion: String = AssistRequest.schemaVersion,
        createdAt: Date = Date(),
        source: AssistRequestSource,
        invocationChannel: AssistInvocationChannel,
        intent: AssistIntent,
        scopeType: AssistScopeType,
        scopeRef: AssistScopeReference,
        prompt: String,
        constraints: [String] = [],
        requestedAction: AssistRequestedAction = .proposalOnly,
        status: AssistRequestStatus = .queued
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.createdAt = createdAt
        self.source = source
        self.invocationChannel = invocationChannel
        self.intent = intent
        self.scopeType = scopeType
        self.scopeRef = scopeRef
        self.prompt = prompt
        self.constraints = constraints
        self.requestedAction = requestedAction
        self.status = status
    }
}

struct AssistContextPack: Identifiable, Codable, Hashable, Sendable {
    static let schemaVersion = "assist.context-pack.v1"

    let id: String
    var schemaVersion: String
    var requestID: String
    var createdAt: Date
    var invocationChannel: AssistInvocationChannel
    var scopeType: AssistScopeType
    var scopeRef: AssistScopeReference
    var entries: [AssistContextEntry]
    var contentHash: String?

    init(
        id: String = AssistRecordID.make(prefix: "ctx"),
        schemaVersion: String = AssistContextPack.schemaVersion,
        requestID: String,
        createdAt: Date = Date(),
        invocationChannel: AssistInvocationChannel,
        scopeType: AssistScopeType,
        scopeRef: AssistScopeReference,
        entries: [AssistContextEntry],
        contentHash: String? = nil
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.requestID = requestID
        self.createdAt = createdAt
        self.invocationChannel = invocationChannel
        self.scopeType = scopeType
        self.scopeRef = scopeRef
        self.entries = entries
        self.contentHash = contentHash
    }
}

struct AssistProposal: Identifiable, Codable, Hashable, Sendable {
    static let schemaVersion = "assist.proposal.v1"

    let id: String
    var schemaVersion: String
    var requestID: String
    var contextPackID: String
    var createdAt: Date
    var status: AssistProposalStatus
    var summary: String
    var rationale: String?
    var warnings: [String]
    var changeItems: [AssistChangeItem]
    var artifactIDs: [String]
    var latestReceiptID: String?
    var latestUndoCheckpointID: String?
    var requiresConfirmation: Bool

    init(
        id: String = AssistRecordID.make(prefix: "proposal"),
        schemaVersion: String = AssistProposal.schemaVersion,
        requestID: String,
        contextPackID: String,
        createdAt: Date = Date(),
        status: AssistProposalStatus = .drafted,
        summary: String,
        rationale: String? = nil,
        warnings: [String] = [],
        changeItems: [AssistChangeItem] = [],
        artifactIDs: [String] = [],
        latestReceiptID: String? = nil,
        latestUndoCheckpointID: String? = nil,
        requiresConfirmation: Bool = true
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.requestID = requestID
        self.contextPackID = contextPackID
        self.createdAt = createdAt
        self.status = status
        self.summary = summary
        self.rationale = rationale
        self.warnings = warnings
        self.changeItems = changeItems
        self.artifactIDs = artifactIDs
        self.latestReceiptID = latestReceiptID
        self.latestUndoCheckpointID = latestUndoCheckpointID
        self.requiresConfirmation = requiresConfirmation
    }
}

struct AssistDecision: Identifiable, Codable, Hashable, Sendable {
    static let schemaVersion = "assist.decision.v1"

    let id: String
    var schemaVersion: String
    var requestID: String
    var proposalID: String
    var createdAt: Date
    var disposition: AssistDecisionDisposition
    var actorID: String?
    var note: String?
    var appliedChangeItemIDs: [String]

    init(
        id: String = AssistRecordID.make(prefix: "decision"),
        schemaVersion: String = AssistDecision.schemaVersion,
        requestID: String,
        proposalID: String,
        createdAt: Date = Date(),
        disposition: AssistDecisionDisposition,
        actorID: String? = nil,
        note: String? = nil,
        appliedChangeItemIDs: [String] = []
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.requestID = requestID
        self.proposalID = proposalID
        self.createdAt = createdAt
        self.disposition = disposition
        self.actorID = actorID
        self.note = note
        self.appliedChangeItemIDs = appliedChangeItemIDs
    }
}

struct AssistExecutionReceipt: Identifiable, Codable, Hashable, Sendable {
    static let schemaVersion = "assist.receipt.v1"

    let id: String
    var schemaVersion: String
    var requestID: String
    var proposalID: String
    var createdAt: Date
    var status: AssistExecutionReceiptStatus
    var targetRefs: [AssistMutationTargetRef]
    var appliedChangeItemIDs: [String]
    var warningMessages: [String]
    var errorMessage: String?
    var undoCheckpointID: String?

    init(
        id: String = AssistRecordID.make(prefix: "receipt"),
        schemaVersion: String = AssistExecutionReceipt.schemaVersion,
        requestID: String,
        proposalID: String,
        createdAt: Date = Date(),
        status: AssistExecutionReceiptStatus,
        targetRefs: [AssistMutationTargetRef] = [],
        appliedChangeItemIDs: [String] = [],
        warningMessages: [String] = [],
        errorMessage: String? = nil,
        undoCheckpointID: String? = nil
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.requestID = requestID
        self.proposalID = proposalID
        self.createdAt = createdAt
        self.status = status
        self.targetRefs = targetRefs
        self.appliedChangeItemIDs = appliedChangeItemIDs
        self.warningMessages = warningMessages
        self.errorMessage = errorMessage
        self.undoCheckpointID = undoCheckpointID
    }
}

struct AssistCapabilityGrant: Identifiable, Codable, Hashable, Sendable {
    static let schemaVersion = "assist.grant.v1"

    let id: String
    var schemaVersion: String
    var createdAt: Date
    var subjectKind: AssistGrantSubjectKind
    var subjectID: String
    var capabilities: [AssistCapability]
    var scopeTypes: [AssistScopeType]
    var allowsSystemMutation: Bool
    var note: String?

    init(
        id: String = AssistRecordID.make(prefix: "grant"),
        schemaVersion: String = AssistCapabilityGrant.schemaVersion,
        createdAt: Date = Date(),
        subjectKind: AssistGrantSubjectKind,
        subjectID: String,
        capabilities: [AssistCapability],
        scopeTypes: [AssistScopeType] = [],
        allowsSystemMutation: Bool = false,
        note: String? = nil
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.createdAt = createdAt
        self.subjectKind = subjectKind
        self.subjectID = subjectID
        self.capabilities = capabilities
        self.scopeTypes = scopeTypes
        self.allowsSystemMutation = allowsSystemMutation
        self.note = note
    }
}

struct AssistUndoCheckpoint: Identifiable, Codable, Hashable, Sendable {
    static let schemaVersion = "assist.undo.v1"

    let id: String
    var schemaVersion: String
    var requestID: String
    var proposalID: String
    var receiptID: String
    var createdAt: Date
    var snapshotRefs: [AssistSnapshotRef]
    var patchBundleRelativePath: String?
    var note: String?

    init(
        id: String = AssistRecordID.make(prefix: "undo"),
        schemaVersion: String = AssistUndoCheckpoint.schemaVersion,
        requestID: String,
        proposalID: String,
        receiptID: String,
        createdAt: Date = Date(),
        snapshotRefs: [AssistSnapshotRef] = [],
        patchBundleRelativePath: String? = nil,
        note: String? = nil
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.requestID = requestID
        self.proposalID = proposalID
        self.receiptID = receiptID
        self.createdAt = createdAt
        self.snapshotRefs = snapshotRefs
        self.patchBundleRelativePath = patchBundleRelativePath
        self.note = note
    }
}

struct AssistArtifact: Identifiable, Codable, Hashable, Sendable {
    static let schemaVersion = "assist.artifact.v1"

    let id: String
    var schemaVersion: String
    var requestID: String
    var proposalID: String?
    var createdAt: Date
    var kind: AssistArtifactKind
    var title: String
    var relativePath: String?
    var metadata: [String: String]

    init(
        id: String = AssistRecordID.make(prefix: "artifact"),
        schemaVersion: String = AssistArtifact.schemaVersion,
        requestID: String,
        proposalID: String? = nil,
        createdAt: Date = Date(),
        kind: AssistArtifactKind,
        title: String,
        relativePath: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.requestID = requestID
        self.proposalID = proposalID
        self.createdAt = createdAt
        self.kind = kind
        self.title = title
        self.relativePath = relativePath
        self.metadata = metadata
    }
}

struct AssistThreadRecord: Identifiable, Codable, Hashable, Sendable {
    static let schemaVersion = "assist.thread.v1"

    let id: String
    var schemaVersion: String
    var createdAt: Date
    var updatedAt: Date
    var invocationChannel: AssistInvocationChannel
    var source: AssistRequestSource
    var title: String?
    var linkedWorkbenchThreadID: String?
    var projectID: UUID?
    var workflowID: UUID?
    var latestRequestID: String?
    var latestProposalID: String?

    init(
        id: String = AssistRecordID.make(prefix: "thread"),
        schemaVersion: String = AssistThreadRecord.schemaVersion,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        invocationChannel: AssistInvocationChannel,
        source: AssistRequestSource,
        title: String? = nil,
        linkedWorkbenchThreadID: String? = nil,
        projectID: UUID? = nil,
        workflowID: UUID? = nil,
        latestRequestID: String? = nil,
        latestProposalID: String? = nil
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.invocationChannel = invocationChannel
        self.source = source
        self.title = title
        self.linkedWorkbenchThreadID = linkedWorkbenchThreadID
        self.projectID = projectID
        self.workflowID = workflowID
        self.latestRequestID = latestRequestID
        self.latestProposalID = latestProposalID
    }
}

enum AssistRecordID {
    static func make(prefix: String) -> String {
        let value = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        return "\(prefix)_\(value)"
    }
}
