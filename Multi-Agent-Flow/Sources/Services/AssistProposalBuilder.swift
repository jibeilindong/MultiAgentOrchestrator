import Foundation

struct AssistProposalBuilder {
    func build(
        request: AssistRequest,
        contextPack: AssistContextPack
    ) -> AssistProposal {
        let warnings = proposalWarnings(for: request)
        let changeItem = AssistChangeItem(
            target: mutationTarget(for: request),
            operation: changeOperation(for: request),
            title: changeTitle(for: request),
            summary: changeSummary(for: request),
            relativeFilePath: request.scopeRef.relativeFilePath,
            beforePreview: beforePreview(from: contextPack),
            afterPreview: afterPreview(for: request),
            patch: nil,
            warnings: warnings,
            scopeRef: request.scopeRef
        )

        return AssistProposal(
            requestID: request.id,
            contextPackID: contextPack.id,
            status: .awaitingConfirmation,
            summary: proposalSummary(for: request),
            rationale: proposalRationale(for: request, contextPack: contextPack),
            warnings: warnings,
            changeItems: [changeItem],
            artifactIDs: [],
            requiresConfirmation: true
        )
    }

    private func proposalSummary(
        for request: AssistRequest
    ) -> String {
        let scopeLabel = scopeLabel(for: request.scopeRef, scopeType: request.scopeType)

        switch request.intent {
        case .rewriteSelection:
            return "Rewrite suggestion prepared for \(scopeLabel)."
        case .completeTemplate:
            return "Template completion suggestion prepared for \(scopeLabel)."
        case .modifyManagedContent:
            return "Managed content suggestion prepared for \(scopeLabel)."
        case .reorganizeWorkflow:
            return "Workflow reorganization suggestion prepared for \(scopeLabel)."
        case .inspectConfiguration:
            return "Configuration inspection report prepared for \(scopeLabel)."
        case .inspectPerformance:
            return "Performance inspection report prepared for \(scopeLabel)."
        case .explainIssue:
            return "Issue explanation prepared for \(scopeLabel)."
        case .custom:
            return "Assist suggestion prepared for \(scopeLabel)."
        }
    }

    private func proposalRationale(
        for request: AssistRequest,
        contextPack: AssistContextPack
    ) -> String {
        let contextTitles = contextPack.entries
            .map(\.title)
            .joined(separator: ", ")
        return [
            "Prompt: \(truncated(request.prompt, limit: 240))",
            "Resolved scope: \(scopeLabel(for: request.scopeRef, scopeType: request.scopeType))",
            "Context used: \(contextTitles.isEmpty ? "none" : contextTitles)",
            "Execution remains suggestion-first until explicit confirmation."
        ].joined(separator: "\n")
    }

    private func proposalWarnings(
        for request: AssistRequest
    ) -> [String] {
        var warnings = [
            "Assist is a gloved, least-privilege, rollbackable hand; confirmation is required before any change is applied.",
            "Assist never writes directly to the live runtime. Changes must stay in draft, managed workspace, mirror, or read-only diagnostic scopes."
        ]

        if request.requestedAction != .proposalOnly {
            warnings.append(
                "Requested action '\(request.requestedAction.rawValue)' is captured, but the current implementation remains in proposal-only mode until the mutation gateway is enabled."
            )
        }

        if request.scopeRef.workspaceSurface == .runtimeReadonly {
            warnings.append("Current scope is runtime read-only. This proposal cannot become a direct write operation.")
        }

        return warnings
    }

    private func mutationTarget(
        for request: AssistRequest
    ) -> AssistMutationTarget {
        switch request.intent {
        case .inspectConfiguration:
            return .configuration
        case .inspectPerformance, .explainIssue:
            return .diagnosticsReport
        case .reorganizeWorkflow:
            return .workflowLayout
        case .rewriteSelection, .completeTemplate, .modifyManagedContent, .custom:
            break
        }

        switch request.scopeRef.workspaceSurface {
        case .managedWorkspace:
            return .managedFile
        case .mirror:
            return .mirror
        case .runtimeReadonly:
            return .diagnosticsReport
        case .draft, nil:
            break
        }

        switch request.scopeType {
        case .node, .workflow:
            return .workflowLayout
        case .project:
            return .configuration
        case .textSelection, .file:
            return .draftText
        }
    }

    private func changeOperation(
        for request: AssistRequest
    ) -> AssistChangeOperationKind {
        switch request.intent {
        case .inspectConfiguration, .inspectPerformance, .explainIssue:
            return .suggest
        case .reorganizeWorkflow:
            return .patch
        case .completeTemplate:
            return .insert
        case .modifyManagedContent, .rewriteSelection, .custom:
            return .replace
        }
    }

    private func changeTitle(
        for request: AssistRequest
    ) -> String {
        switch request.intent {
        case .rewriteSelection:
            return "Rewrite selected text"
        case .completeTemplate:
            return "Complete template content"
        case .modifyManagedContent:
            return "Revise managed content"
        case .reorganizeWorkflow:
            return "Adjust workflow layout"
        case .inspectConfiguration:
            return "Inspect configuration"
        case .inspectPerformance:
            return "Inspect performance"
        case .explainIssue:
            return "Explain issue"
        case .custom:
            return "Apply Assist suggestion"
        }
    }

    private func changeSummary(
        for request: AssistRequest
    ) -> String {
        let scopeLabel = scopeLabel(for: request.scopeRef, scopeType: request.scopeType)
        switch request.intent {
        case .rewriteSelection:
            return "Prepare a structured rewrite suggestion for \(scopeLabel) based on the current prompt."
        case .completeTemplate:
            return "Prepare template completion guidance for \(scopeLabel) without mutating live content."
        case .modifyManagedContent:
            return "Prepare a managed-content update suggestion for \(scopeLabel) and hold it for confirmation."
        case .reorganizeWorkflow:
            return "Prepare a workflow layout adjustment plan for \(scopeLabel) with preview-first semantics."
        case .inspectConfiguration:
            return "Prepare a read-only configuration analysis for \(scopeLabel)."
        case .inspectPerformance:
            return "Prepare a read-only performance analysis for \(scopeLabel)."
        case .explainIssue:
            return "Prepare a diagnostic explanation for \(scopeLabel) with no direct mutation."
        case .custom:
            return "Prepare a structured Assist suggestion for \(scopeLabel)."
        }
    }

    private func beforePreview(
        from contextPack: AssistContextPack
    ) -> String? {
        if let selectedText = contextPack.entries.first(where: { $0.kind == .selectedText })?.value {
            return truncated(selectedText, limit: 280)
        }
        if let fileContent = contextPack.entries.first(where: { $0.kind == .fileContent })?.value {
            return truncated(fileContent, limit: 280)
        }
        return nil
    }

    private func afterPreview(
        for request: AssistRequest
    ) -> String {
        switch request.intent {
        case .inspectConfiguration, .inspectPerformance, .explainIssue:
            return "Read-only structured report is pending user confirmation."
        case .rewriteSelection, .completeTemplate, .modifyManagedContent, .reorganizeWorkflow, .custom:
            return "Structured preview is pending user confirmation: \(truncated(request.prompt, limit: 220))"
        }
    }

    private func scopeLabel(
        for scopeRef: AssistScopeReference,
        scopeType: AssistScopeType
    ) -> String {
        if let nodeTitle = scopeRef.additionalMetadata["nodeTitle"] {
            return "node '\(nodeTitle)'"
        }
        if let workflowName = scopeRef.additionalMetadata["workflowName"] {
            return "workflow '\(workflowName)'"
        }
        if let relativeFilePath = scopeRef.relativeFilePath {
            return "file '\(relativeFilePath)'"
        }
        return scopeType.rawValue.replacingOccurrences(of: "_", with: " ")
    }

    private func truncated(
        _ value: String,
        limit: Int
    ) -> String {
        guard value.count > limit else { return value }
        let endIndex = value.index(value.startIndex, offsetBy: limit)
        return "\(value[..<endIndex])..."
    }
}
