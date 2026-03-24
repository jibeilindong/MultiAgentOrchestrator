import Foundation

struct AssistProposalBuilder {
    private let horizontalSpacing: Double = 240
    private let verticalSpacing: Double = 160
    private let gridSize: Double = 40

    func build(
        request: AssistRequest,
        contextPack: AssistContextPack,
        generatedContent: AssistGeneratedProposalContent? = nil
    ) -> AssistProposal {
        let textMutationPlan = generatedContent?.textMutationPlan
        let warnings = proposalWarnings(for: request, textMutationPlan: textMutationPlan)
        let layoutPlan = workflowLayoutPlan(for: request, contextPack: contextPack)
        let changeItem = AssistChangeItem(
            target: mutationTarget(for: request),
            operation: changeOperation(for: request, textMutationPlan: textMutationPlan),
            title: changeTitle(for: request),
            summary: changeSummary(for: request, layoutPlan: layoutPlan, textMutationPlan: textMutationPlan),
            relativeFilePath: request.scopeRef.relativeFilePath,
            beforePreview: beforePreview(from: contextPack, request: request, layoutPlan: layoutPlan, textMutationPlan: textMutationPlan),
            afterPreview: afterPreview(for: request, layoutPlan: layoutPlan, textMutationPlan: textMutationPlan),
            patch: patchPayload(for: request, layoutPlan: layoutPlan, textMutationPlan: textMutationPlan),
            warnings: warnings,
            scopeRef: request.scopeRef
        )

        return AssistProposal(
            requestID: request.id,
            contextPackID: contextPack.id,
            status: .awaitingConfirmation,
            summary: proposalSummary(for: request, layoutPlan: layoutPlan, textMutationPlan: textMutationPlan),
            rationale: proposalRationale(for: request, contextPack: contextPack, layoutPlan: layoutPlan, textMutationPlan: textMutationPlan),
            warnings: warnings,
            changeItems: [changeItem],
            artifactIDs: [],
            requiresConfirmation: true
        )
    }

    private func proposalSummary(
        for request: AssistRequest,
        layoutPlan: AssistWorkflowLayoutPlan?,
        textMutationPlan: AssistTextMutationPlan?
    ) -> String {
        let scopeLabel = scopeLabel(for: request.scopeRef, scopeType: request.scopeType)

        switch request.intent {
        case .rewriteSelection:
            if textMutationPlan != nil {
                return "Draft rewrite proposal prepared for \(scopeLabel)."
            }
            return "Rewrite suggestion prepared for \(scopeLabel)."
        case .completeTemplate:
            if textMutationPlan != nil {
                return "Template draft completion proposal prepared for \(scopeLabel)."
            }
            return "Template completion suggestion prepared for \(scopeLabel)."
        case .modifyManagedContent:
            if textMutationPlan != nil {
                return "Draft content revision proposal prepared for \(scopeLabel)."
            }
            return "Managed content suggestion prepared for \(scopeLabel)."
        case .reorganizeWorkflow:
            if let layoutPlan {
                return "Workflow layout proposal prepared for \(scopeLabel), covering \(layoutPlan.placements.count) node updates."
            }
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
        contextPack: AssistContextPack,
        layoutPlan: AssistWorkflowLayoutPlan?,
        textMutationPlan: AssistTextMutationPlan?
    ) -> String {
        let contextTitles = contextPack.entries
            .map(\.title)
            .joined(separator: ", ")

        var lines = [
            "Prompt: \(truncated(request.prompt, limit: 240))",
            "Resolved scope: \(scopeLabel(for: request.scopeRef, scopeType: request.scopeType))",
            "Context used: \(contextTitles.isEmpty ? "none" : contextTitles)",
            "Execution remains suggestion-first until explicit confirmation."
        ]

        if let note = layoutPlan?.note, !note.isEmpty {
            lines.append("Layout rationale: \(note)")
        }

        if let summary = textMutationPlan?.summary, !summary.isEmpty {
            lines.append("Generated summary: \(summary)")
        }

        if let rationale = textMutationPlan?.rationale, !rationale.isEmpty {
            lines.append("Generated rationale: \(rationale)")
        }

        return lines.joined(separator: "\n")
    }

    private func proposalWarnings(
        for request: AssistRequest,
        textMutationPlan: AssistTextMutationPlan?
    ) -> [String] {
        var warnings = [
            "Assist is a gloved, least-privilege, rollbackable hand; confirmation is required before any change is applied.",
            "Assist never writes directly to the live runtime. Changes must stay in draft, managed workspace, mirror, or read-only diagnostic scopes."
        ]

        if request.requestedAction != .proposalOnly,
           supportsApplyPath(for: request, textMutationPlan: textMutationPlan) == false {
            warnings.append(
                "Requested action '\(request.requestedAction.rawValue)' is captured, but the current implementation remains in proposal-only mode until the mutation gateway is enabled."
            )
        }

        if request.scopeRef.workspaceSurface == .runtimeReadonly {
            warnings.append("Current scope is runtime read-only. This proposal cannot become a direct write operation.")
        }

        warnings.append(contentsOf: textMutationPlan?.warnings ?? [])

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
        for request: AssistRequest,
        textMutationPlan: AssistTextMutationPlan?
    ) -> AssistChangeOperationKind {
        if textMutationPlan != nil {
            return .replace
        }

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
        for request: AssistRequest,
        layoutPlan: AssistWorkflowLayoutPlan?,
        textMutationPlan: AssistTextMutationPlan?
    ) -> String {
        let scopeLabel = scopeLabel(for: request.scopeRef, scopeType: request.scopeType)
        let generatedSummary = textMutationPlan?.summary

        switch request.intent {
        case .rewriteSelection:
            if let generatedSummary, !generatedSummary.isEmpty {
                return generatedSummary
            }
            return "Prepare a structured rewrite suggestion for \(scopeLabel) based on the current prompt."
        case .completeTemplate:
            if let generatedSummary, !generatedSummary.isEmpty {
                return generatedSummary
            }
            return "Prepare template completion guidance for \(scopeLabel) without mutating live content."
        case .modifyManagedContent:
            if let generatedSummary, !generatedSummary.isEmpty {
                return generatedSummary
            }
            return "Prepare a managed-content update suggestion for \(scopeLabel) and hold it for confirmation."
        case .reorganizeWorkflow:
            if let layoutPlan {
                return "Prepare a workflow layout adjustment plan for \(scopeLabel), covering \(layoutPlan.placements.count) proposed node position changes."
            }
            return "Prepare a workflow layout adjustment plan for \(scopeLabel) with preview-first semantics."
        case .inspectConfiguration:
            return "Prepare a read-only configuration analysis for \(scopeLabel)."
        case .inspectPerformance:
            return "Prepare a read-only performance analysis for \(scopeLabel)."
        case .explainIssue:
            return "Prepare a diagnostic explanation for \(scopeLabel) with no direct mutation."
        case .custom:
            if let generatedSummary, !generatedSummary.isEmpty {
                return generatedSummary
            }
            return "Prepare a structured Assist suggestion for \(scopeLabel)."
        }
    }

    private func beforePreview(
        from contextPack: AssistContextPack,
        request: AssistRequest,
        layoutPlan: AssistWorkflowLayoutPlan?,
        textMutationPlan: AssistTextMutationPlan?
    ) -> String? {
        if let layoutPlan {
            return workflowLayoutBeforePreview(for: layoutPlan)
        }
        if let sourceContent = textMutationPlan?.sourceContent {
            return truncated(sourceContent, limit: 600)
        }
        if let selectedText = contextPack.entries.first(where: { $0.kind == .selectedText })?.value {
            return truncated(selectedText, limit: 280)
        }
        if let fileContent = contextPack.entries.first(where: { $0.kind == .fileContent })?.value {
            return truncated(fileContent, limit: 280)
        }
        if request.intent == .reorganizeWorkflow {
            return contextPack.entries.first(where: { $0.kind == .workflowLayout })?.value
        }
        return nil
    }

    private func afterPreview(
        for request: AssistRequest,
        layoutPlan: AssistWorkflowLayoutPlan?,
        textMutationPlan: AssistTextMutationPlan?
    ) -> String {
        if let textMutationPlan {
            return truncated(textMutationPlan.resultingContent, limit: 600)
        }

        switch request.intent {
        case .inspectConfiguration, .inspectPerformance, .explainIssue:
            return "Read-only structured report is pending user confirmation."
        case .reorganizeWorkflow:
            if let layoutPlan {
                return workflowLayoutAfterPreview(for: layoutPlan)
            }
            return "Workflow layout proposal is pending user confirmation."
        case .rewriteSelection, .completeTemplate, .modifyManagedContent, .custom:
            return "Structured preview is pending user confirmation: \(truncated(request.prompt, limit: 220))"
        }
    }

    private func patchPayload(
        for request: AssistRequest,
        layoutPlan: AssistWorkflowLayoutPlan?,
        textMutationPlan: AssistTextMutationPlan?
    ) -> String? {
        if let textMutationPlan {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            guard let data = try? encoder.encode(textMutationPlan) else {
                return nil
            }
            return String(data: data, encoding: .utf8)
        }

        guard request.intent == .reorganizeWorkflow,
              let layoutPlan else {
            return nil
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(layoutPlan) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func supportsApplyPath(
        for request: AssistRequest,
        textMutationPlan: AssistTextMutationPlan?
    ) -> Bool {
        switch mutationTarget(for: request) {
        case .workflowLayout, .diagnosticsReport, .configuration:
            return true
        case .draftText:
            return request.scopeRef.workspaceSurface == .draft && textMutationPlan != nil
        case .managedFile, .mirror:
            return false
        }
    }

    private func workflowLayoutPlan(
        for request: AssistRequest,
        contextPack: AssistContextPack
    ) -> AssistWorkflowLayoutPlan? {
        guard request.intent == .reorganizeWorkflow,
              let snapshot = workflowLayoutSnapshot(from: contextPack) else {
            return nil
        }

        let targetNodeIDs = targetNodeIDs(in: snapshot, request: request)
        let candidateNodes = snapshot.nodes.filter { targetNodeIDs.contains($0.nodeID) }
        guard !candidateNodes.isEmpty else { return nil }

        let depths = depthMap(in: snapshot, request: request)
        let sortedDepths = Array(Set(candidateNodes.map { depths[$0.nodeID] ?? 0 })).sorted()
        let depthToColumn = Dictionary(uniqueKeysWithValues: sortedDepths.enumerated().map { ($1, $0) })

        let baseX = candidateNodes.map(\.x).min() ?? 0
        let baseY = candidateNodes.map(\.y).min() ?? 0

        var placements: [AssistWorkflowNodePlacement] = []
        for depth in sortedDepths {
            let group = candidateNodes
                .filter { (depths[$0.nodeID] ?? 0) == depth }
                .sorted(by: nodeSort)

            for (index, node) in group.enumerated() {
                let column = depthToColumn[depth] ?? 0
                let targetX = snappedCoordinate(baseX + Double(column) * horizontalSpacing)
                let targetY = snappedCoordinate(baseY + Double(index) * verticalSpacing)

                guard abs(node.x - targetX) > 0.5 || abs(node.y - targetY) > 0.5 else {
                    continue
                }

                placements.append(
                    AssistWorkflowNodePlacement(
                        nodeID: node.nodeID,
                        title: node.title,
                        beforeX: node.x,
                        beforeY: node.y,
                        afterX: targetX,
                        afterY: targetY
                    )
                )
            }
        }

        let note: String
        if placements.isEmpty {
            note = "The current workflow layout is already close to the proposed structured arrangement."
        } else if request.scopeType == .node, let nodeTitle = request.scopeRef.additionalMetadata["nodeTitle"] {
            note = "The proposal focuses on the selected node '\(nodeTitle)' and its directly connected neighborhood."
        } else {
            note = "The proposal reorganizes the current workflow by graph depth and vertical distribution to reduce overlap and improve readability."
        }

        return AssistWorkflowLayoutPlan(
            workflowID: snapshot.workflowID,
            workflowName: snapshot.workflowName,
            scopeType: request.scopeType,
            scopedNodeID: request.scopeRef.nodeID,
            placements: placements,
            note: note
        )
    }

    private func workflowLayoutSnapshot(
        from contextPack: AssistContextPack
    ) -> AssistWorkflowLayoutSnapshot? {
        guard let entry = contextPack.entries.first(where: { $0.kind == .workflowLayout }),
              let rawValue = entry.metadata["layoutSnapshotJSON"],
              let data = rawValue.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(AssistWorkflowLayoutSnapshot.self, from: data)
    }

    private func targetNodeIDs(
        in snapshot: AssistWorkflowLayoutSnapshot,
        request: AssistRequest
    ) -> Set<UUID> {
        if request.scopeType == .node,
           let scopedNodeID = request.scopeRef.nodeID {
            var scopedNodeIDs: Set<UUID> = [scopedNodeID]
            for edge in snapshot.edges {
                if edge.fromNodeID == scopedNodeID {
                    scopedNodeIDs.insert(edge.toNodeID)
                }
                if edge.toNodeID == scopedNodeID {
                    scopedNodeIDs.insert(edge.fromNodeID)
                }
            }
            return scopedNodeIDs
        }

        return Set(snapshot.nodes.map(\.nodeID))
    }

    private func depthMap(
        in snapshot: AssistWorkflowLayoutSnapshot,
        request: AssistRequest
    ) -> [UUID: Int] {
        let adjacency = Dictionary(grouping: snapshot.edges, by: \.fromNodeID)
        let startNodeIDs = preferredStartNodeIDs(in: snapshot, request: request)
        var queue = Array(startNodeIDs)
        var depths = Dictionary(uniqueKeysWithValues: startNodeIDs.map { ($0, 0) })
        var cursor = 0

        while cursor < queue.count {
            let nodeID = queue[cursor]
            cursor += 1

            for edge in adjacency[nodeID] ?? [] {
                let candidateDepth = (depths[nodeID] ?? 0) + 1
                if let existingDepth = depths[edge.toNodeID], existingDepth <= candidateDepth {
                    continue
                }
                depths[edge.toNodeID] = candidateDepth
                queue.append(edge.toNodeID)
            }
        }

        let fallbackDepthStart = (depths.values.max() ?? -1) + 1
        let unresolvedNodes = snapshot.nodes
            .filter { depths[$0.nodeID] == nil }
            .sorted(by: nodeSort)

        for (index, node) in unresolvedNodes.enumerated() {
            depths[node.nodeID] = fallbackDepthStart + index
        }

        return depths
    }

    private func preferredStartNodeIDs(
        in snapshot: AssistWorkflowLayoutSnapshot,
        request: AssistRequest
    ) -> [UUID] {
        let startNodes = snapshot.nodes
            .filter { $0.nodeType == "start" }
            .sorted(by: nodeSort)
            .map(\.nodeID)
        if !startNodes.isEmpty {
            return startNodes
        }

        if let scopedNodeID = request.scopeRef.nodeID {
            return [scopedNodeID]
        }

        return snapshot.nodes
            .sorted(by: nodeSort)
            .prefix(1)
            .map(\.nodeID)
    }

    private func workflowLayoutBeforePreview(
        for plan: AssistWorkflowLayoutPlan
    ) -> String {
        if plan.placements.isEmpty {
            return "No node positions need to change."
        }

        let lines = plan.placements.prefix(6).map { placement in
            "\(placement.title): (\(Int(placement.beforeX)), \(Int(placement.beforeY)))"
        }
        return lines.joined(separator: "\n")
    }

    private func workflowLayoutAfterPreview(
        for plan: AssistWorkflowLayoutPlan
    ) -> String {
        if plan.placements.isEmpty {
            return "Layout already appears organized. Confirming this proposal would result in no node movement."
        }

        var lines = [
            "Workflow: \(plan.workflowName)",
            "Moved Nodes: \(plan.placements.count)"
        ]
        lines.append(contentsOf: plan.placements.prefix(8).map { placement in
            "\(placement.title): (\(Int(placement.beforeX)), \(Int(placement.beforeY))) -> (\(Int(placement.afterX)), \(Int(placement.afterY)))"
        })

        if plan.placements.count > 8 {
            lines.append("+ \(plan.placements.count - 8) more nodes")
        }

        if let note = plan.note, !note.isEmpty {
            lines.append(note)
        }

        return lines.joined(separator: "\n")
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

    private func snappedCoordinate(
        _ value: Double
    ) -> Double {
        (value / gridSize).rounded() * gridSize
    }

    private func nodeSort(
        _ lhs: AssistWorkflowLayoutSnapshotNode,
        _ rhs: AssistWorkflowLayoutSnapshotNode
    ) -> Bool {
        if lhs.y != rhs.y {
            return lhs.y < rhs.y
        }
        if lhs.x != rhs.x {
            return lhs.x < rhs.x
        }
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
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
