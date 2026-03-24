import Foundation

extension AppState {
    struct AssistScopeDescriptor: Equatable {
        var scopeType: AssistScopeType
        var workflowID: UUID?
        var workflowName: String?
        var nodeID: UUID?
        var nodeTitle: String?
        var title: String
        var detail: String
    }

    struct AssistDraft {
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

    func createAssistProposal(
        _ draft: AssistDraft,
        orchestrator: AssistOrchestrator = AssistOrchestrator()
    ) throws -> AssistSubmissionResult {
        try orchestrator.submit(
            AssistSubmissionInput(
                source: draft.source,
                invocationChannel: draft.invocationChannel,
                intent: draft.intent,
                scopeType: draft.scopeType,
                prompt: draft.prompt,
                constraints: draft.constraints,
                requestedAction: draft.requestedAction,
                workflowID: draft.workflowID,
                nodeID: draft.nodeID,
                threadID: draft.threadID,
                relativeFilePath: draft.relativeFilePath,
                selectionStart: draft.selectionStart,
                selectionEnd: draft.selectionEnd,
                workspaceSurface: draft.workspaceSurface,
                selectedText: draft.selectedText,
                fileContent: draft.fileContent,
                additionalMetadata: draft.additionalMetadata
            ),
            snapshot: assistSnapshot()
        )
    }

    func submitAssistRequest(
        _ draft: AssistDraft,
        orchestrator: AssistOrchestrator = AssistOrchestrator()
    ) throws -> AssistSubmissionResult {
        try createAssistProposal(draft, orchestrator: orchestrator)
    }

    func applyAssistProposal(
        _ submission: AssistSubmissionResult,
        actorID: String? = nil,
        note: String? = nil
    ) throws -> AssistExecutionResult {
        try AssistOrchestrator(
            mutationGateway: AppStateAssistMutationGateway(appState: self)
        ).apply(
            submission,
            actorID: actorID,
            note: note
        )
    }

    func rejectAssistProposal(
        _ submission: AssistSubmissionResult,
        actorID: String? = nil,
        note: String? = nil
    ) throws -> AssistExecutionResult {
        try AssistOrchestrator(
            mutationGateway: AppStateAssistMutationGateway(appState: self)
        ).reject(
            submission,
            actorID: actorID,
            note: note
        )
    }

    func revertAssistProposal(
        _ submission: AssistSubmissionResult
    ) throws -> AssistRevertResult {
        try AssistOrchestrator(
            mutationGateway: AppStateAssistMutationGateway(appState: self)
        ).revert(submission)
    }

    func resolveWorkbenchAssistScope(
        workflowID: UUID?
    ) -> AssistScopeDescriptor {
        let resolvedWorkflow = workflow(for: workflowID)

        if let resolvedWorkflow,
           let selectedNodeID,
           let node = resolvedWorkflow.nodes.first(where: { $0.id == selectedNodeID }) {
            return AssistScopeDescriptor(
                scopeType: .node,
                workflowID: resolvedWorkflow.id,
                workflowName: resolvedWorkflow.name,
                nodeID: node.id,
                nodeTitle: node.title,
                title: "Current Node",
                detail: "\(node.title) in \(resolvedWorkflow.name)"
            )
        }

        if let resolvedWorkflow {
            return AssistScopeDescriptor(
                scopeType: .workflow,
                workflowID: resolvedWorkflow.id,
                workflowName: resolvedWorkflow.name,
                nodeID: nil,
                nodeTitle: nil,
                title: "Current Workflow",
                detail: resolvedWorkflow.name
            )
        }

        if let project = currentProject {
            return AssistScopeDescriptor(
                scopeType: .project,
                workflowID: nil,
                workflowName: nil,
                nodeID: nil,
                nodeTitle: nil,
                title: "Current Project",
                detail: project.name
            )
        }

        return AssistScopeDescriptor(
            scopeType: .project,
            workflowID: nil,
            workflowName: nil,
            nodeID: nil,
            nodeTitle: nil,
            title: "Current Context",
            detail: "No active project"
        )
    }

    func inferredAssistIntent(
        for prompt: String,
        scopeType: AssistScopeType
    ) -> AssistIntent {
        let normalizedPrompt = prompt
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !normalizedPrompt.isEmpty else {
            return scopeType == .node || scopeType == .workflow ? .reorganizeWorkflow : .custom
        }

        if matchesAnyKeyword(
            in: normalizedPrompt,
            keywords: ["性能", "performance", "latency", "慢", "卡顿", "耗时", "benchmark", "吞吐", "瓶颈"]
        ) {
            return .inspectPerformance
        }

        if matchesAnyKeyword(
            in: normalizedPrompt,
            keywords: ["配置", "config", "参数", "绑定", "session", "runtime", "环境", "设定"]
        ) {
            return .inspectConfiguration
        }

        if matchesAnyKeyword(
            in: normalizedPrompt,
            keywords: ["解释", "原因", "报错", "错误", "异常", "issue", "problem", "why", "failed", "failure"]
        ) {
            return .explainIssue
        }

        if matchesAnyKeyword(
            in: normalizedPrompt,
            keywords: ["布局", "workflow", "节点", "整理", "重排", "reorganize", "layout", "node", "flow"]
        ) {
            return .reorganizeWorkflow
        }

        if matchesAnyKeyword(
            in: normalizedPrompt,
            keywords: ["补全", "模板", "template", "complete"]
        ) {
            return .completeTemplate
        }

        if matchesAnyKeyword(
            in: normalizedPrompt,
            keywords: ["改写", "润色", "rewrite", "文案", "copy", "text", "内容", "措辞"]
        ) {
            switch scopeType {
            case .textSelection:
                return .rewriteSelection
            case .file:
                return .modifyManagedContent
            case .node, .workflow, .project:
                return .custom
            }
        }

        if scopeType == .node || scopeType == .workflow {
            return .reorganizeWorkflow
        }

        return .custom
    }

    func makeWorkbenchAssistDraft(
        prompt: String,
        workflowID: UUID?,
        preferredThreadID: String?,
        isPreparingFreshThread: Bool,
        submitMode: WorkbenchInteractionMode
    ) -> AssistDraft {
        let scope = resolveWorkbenchAssistScope(workflowID: workflowID)
        let intent = inferredAssistIntent(for: prompt, scopeType: scope.scopeType)
        let normalizedThreadID = preferredThreadID?.trimmingCharacters(in: .whitespacesAndNewlines)

        var additionalMetadata: [String: String] = [
            "entrySurface": "workbench",
            "scopeTitle": scope.title,
            "scopeDetail": scope.detail,
            "workbenchMode": submitMode.rawValue,
            "proposalMode": "suggestion_only"
        ]

        if let workflowName = scope.workflowName {
            additionalMetadata["workflowName"] = workflowName
        }
        if let nodeTitle = scope.nodeTitle {
            additionalMetadata["nodeTitle"] = nodeTitle
        }
        if isPreparingFreshThread {
            additionalMetadata["threadLifecycle"] = "fresh_thread"
        }

        return AssistDraft(
            source: .workbenchAssist,
            invocationChannel: .system,
            intent: intent,
            scopeType: scope.scopeType,
            prompt: prompt,
            constraints: defaultAssistConstraints(),
            requestedAction: .proposalOnly,
            workflowID: scope.workflowID,
            nodeID: scope.nodeID,
            threadID: isPreparingFreshThread ? nil : normalizedThreadID,
            workspaceSurface: defaultWorkbenchAssistWorkspaceSurface(for: intent),
            additionalMetadata: additionalMetadata
        )
    }

    func makeWorkflowEditorAssistDraft(
        prompt: String,
        workflowID: UUID?
    ) -> AssistDraft {
        let scope = resolveWorkbenchAssistScope(workflowID: workflowID)
        let intent = inferredAssistIntent(for: prompt, scopeType: scope.scopeType)

        var additionalMetadata: [String: String] = [
            "entrySurface": "workflow_editor",
            "scopeTitle": scope.title,
            "scopeDetail": scope.detail,
            "proposalMode": "suggestion_only"
        ]

        if let workflowName = scope.workflowName {
            additionalMetadata["workflowName"] = workflowName
        }
        if let nodeTitle = scope.nodeTitle {
            additionalMetadata["nodeTitle"] = nodeTitle
        }

        return AssistDraft(
            source: .workflowNode,
            invocationChannel: .workflow,
            intent: intent,
            scopeType: scope.scopeType,
            prompt: prompt,
            constraints: defaultAssistConstraints(),
            requestedAction: .proposalOnly,
            workflowID: scope.workflowID,
            nodeID: scope.nodeID,
            threadID: nil,
            workspaceSurface: defaultWorkbenchAssistWorkspaceSurface(for: intent),
            additionalMetadata: additionalMetadata
        )
    }

    func makeTemplateWorkspaceAssistDraft(
        prompt: String,
        template: AgentTemplate,
        relativeFilePath: String,
        fileContent: String?,
        isFileMissing: Bool
    ) -> AssistDraft {
        let normalizedRelativePath = relativeFilePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let intent = inferredAssistIntent(for: prompt, scopeType: .file)

        var additionalMetadata: [String: String] = [
            "entrySurface": "template_workspace",
            "templateID": template.id,
            "templateName": template.name,
            "scopeTitle": "Current Template File",
            "scopeDetail": "\(template.name) / \(normalizedRelativePath)",
            "proposalMode": "suggestion_only",
            "filePresence": isFileMissing ? "missing" : "present"
        ]

        if !template.identity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            additionalMetadata["templateIdentity"] = template.identity
        }

        if !template.taxonomyPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            additionalMetadata["templateTaxonomy"] = template.taxonomyPath
        }

        return AssistDraft(
            source: .inlineEditor,
            invocationChannel: .system,
            intent: intent,
            scopeType: .file,
            prompt: prompt,
            constraints: defaultAssistConstraints(),
            requestedAction: .proposalOnly,
            relativeFilePath: normalizedRelativePath,
            workspaceSurface: .draft,
            fileContent: fileContent,
            additionalMetadata: additionalMetadata
        )
    }

    private func assistSnapshot() -> AssistContextResolver.Snapshot {
        AssistContextResolver.Snapshot(
            project: currentProject,
            activeWorkflowID: activeWorkflowID,
            selectedNodeID: selectedNodeID,
            messages: messageManager.messages,
            tasks: taskManager.tasks
        )
    }

    private func defaultWorkbenchAssistWorkspaceSurface(
        for intent: AssistIntent
    ) -> AssistWorkspaceSurface {
        switch intent {
        case .inspectConfiguration, .inspectPerformance, .explainIssue:
            return .runtimeReadonly
        case .rewriteSelection, .completeTemplate, .modifyManagedContent, .reorganizeWorkflow, .custom:
            return .draft
        }
    }

    private func defaultAssistConstraints() -> [String] {
        [
            "suggestion_first",
            "explicit_confirmation_required",
            "live_runtime_write_forbidden"
        ]
    }

    private func matchesAnyKeyword(
        in text: String,
        keywords: [String]
    ) -> Bool {
        keywords.contains { text.contains($0) }
    }
}
