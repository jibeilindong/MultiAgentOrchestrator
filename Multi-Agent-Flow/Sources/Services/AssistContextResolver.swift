import Foundation

struct AssistContextResolver {
    struct Snapshot {
        var project: MAProject?
        var activeWorkflowID: UUID?
        var selectedNodeID: UUID?
        var messages: [Message]
        var tasks: [Task]

        init(
            project: MAProject?,
            activeWorkflowID: UUID?,
            selectedNodeID: UUID?,
            messages: [Message] = [],
            tasks: [Task] = []
        ) {
            self.project = project
            self.activeWorkflowID = activeWorkflowID
            self.selectedNodeID = selectedNodeID
            self.messages = messages
            self.tasks = tasks
        }
    }

    struct Input {
        var source: AssistRequestSource
        var intent: AssistIntent
        var scopeType: AssistScopeType
        var prompt: String
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
            intent: AssistIntent,
            scopeType: AssistScopeType,
            prompt: String,
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
            self.intent = intent
            self.scopeType = scopeType
            self.prompt = prompt
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

    struct Output {
        var scopeRef: AssistScopeReference
        var entries: [AssistContextEntry]
    }

    func resolve(
        input: Input,
        snapshot: Snapshot
    ) -> Output {
        let project = snapshot.project
        var workflow = resolveWorkflow(in: project, preferredWorkflowID: input.workflowID ?? snapshot.activeWorkflowID)
        let preferredNodeID = input.nodeID ?? snapshot.selectedNodeID
        let resolvedNode = resolveNode(
            in: project,
            preferredNodeID: preferredNodeID,
            preferredWorkflow: workflow
        )
        if workflow == nil {
            workflow = resolvedNode.workflow
        }

        let normalizedThreadID = normalizedValue(input.threadID)
        let normalizedRelativeFilePath = normalizedValue(input.relativeFilePath)
        let resolvedSelectionRange = normalizedSelectionRange(
            start: input.selectionStart,
            end: input.selectionEnd
        )
        let normalizedPrompt = normalizedValue(input.prompt) ?? input.prompt
        let normalizedSelectedText = normalizedValue(input.selectedText)
        let normalizedFileContent = normalizedValue(input.fileContent)

        var additionalMetadata = normalizedMetadata(input.additionalMetadata)
        additionalMetadata["assistSource"] = input.source.rawValue
        additionalMetadata["assistIntent"] = input.intent.rawValue
        additionalMetadata["assistScopeType"] = input.scopeType.rawValue
        if let workspaceSurface = input.workspaceSurface?.rawValue {
            additionalMetadata["workspaceSurface"] = workspaceSurface
        }
        if let project {
            additionalMetadata["projectName"] = project.name
        }
        if let workflow {
            additionalMetadata["workflowName"] = workflow.name
        }
        if let node = resolvedNode.node {
            additionalMetadata["nodeTitle"] = node.title
            additionalMetadata["nodeType"] = node.type.rawValue
        }
        if let normalizedThreadID {
            additionalMetadata["threadID"] = normalizedThreadID
        }
        if let normalizedRelativeFilePath {
            additionalMetadata["relativeFilePath"] = normalizedRelativeFilePath
        }

        let scopeRef = AssistScopeReference(
            projectID: project?.id,
            workflowID: workflow?.id,
            nodeID: resolvedNode.node?.id,
            threadID: normalizedThreadID,
            relativeFilePath: normalizedRelativeFilePath,
            selectionStart: resolvedSelectionRange?.0,
            selectionEnd: resolvedSelectionRange?.1,
            workspaceSurface: input.workspaceSurface,
            additionalMetadata: additionalMetadata
        )

        var entries: [AssistContextEntry] = []
        entries.append(
            AssistContextEntry(
                kind: .userIntent,
                title: "User Intent",
                value: userIntentSummary(
                    prompt: normalizedPrompt,
                    source: input.source,
                    intent: input.intent,
                    scopeType: input.scopeType
                ),
                metadata: [
                    "source": input.source.rawValue,
                    "intent": input.intent.rawValue,
                    "scopeType": input.scopeType.rawValue
                ]
            )
        )

        if let project {
            entries.append(
                AssistContextEntry(
                    kind: .systemHint,
                    title: "Project Snapshot",
                    value: projectSummary(project),
                    metadata: [
                        "projectID": project.id.uuidString
                    ]
                )
            )
        }

        if let workflow {
            var workflowMetadata: [String: String] = [
                "workflowID": workflow.id.uuidString
            ]
            if let layoutSnapshotJSON = encodedWorkflowLayoutSnapshot(workflow) {
                workflowMetadata["layoutSnapshotJSON"] = layoutSnapshotJSON
            }
            entries.append(
                AssistContextEntry(
                    kind: .workflowLayout,
                    title: "Workflow Layout",
                    value: workflowSummary(workflow, in: project),
                    metadata: workflowMetadata
                )
            )
        }

        if let node = resolvedNode.node {
            entries.append(
                AssistContextEntry(
                    kind: .nodeMetadata,
                    title: "Selected Node",
                    value: nodeSummary(node, workflow: resolvedNode.workflow ?? workflow, project: project),
                    metadata: [
                        "nodeID": node.id.uuidString
                    ]
                )
            )
        }

        if let normalizedSelectedText {
            entries.append(
                AssistContextEntry(
                    kind: .selectedText,
                    title: "Selected Text",
                    value: truncated(normalizedSelectedText, limit: 4_000)
                )
            )
        }

        if let normalizedFileContent {
            entries.append(
                AssistContextEntry(
                    kind: .fileContent,
                    title: normalizedRelativeFilePath.map { "File Content (\($0))" } ?? "File Content",
                    value: truncated(normalizedFileContent, limit: 8_000),
                    metadata: normalizedRelativeFilePath.map { ["relativeFilePath": $0] } ?? [:]
                )
            )
        }

        if let workflowID = workflow?.id,
           let normalizedThreadID,
           let threadSummary = threadHistorySummary(
                workflowID: workflowID,
                threadID: normalizedThreadID,
                snapshot: snapshot
           ) {
            entries.append(
                AssistContextEntry(
                    kind: .runtimeSnapshot,
                    title: "Workbench Thread Snapshot",
                    value: threadSummary,
                    metadata: [
                        "threadID": normalizedThreadID,
                        "workflowID": workflowID.uuidString
                    ]
                )
            )
        } else if shouldIncludeRuntimeSummary(for: input.intent),
                  let project {
            entries.append(
                AssistContextEntry(
                    kind: .runtimeSnapshot,
                    title: "Runtime Snapshot",
                    value: runtimeSummary(for: project.runtimeState)
                )
            )
        }

        entries.append(
            AssistContextEntry(
                kind: .systemHint,
                title: "Assist Guardrails",
                value: guardrailSummary(for: scopeRef),
                metadata: [
                    "principle": "gloved_hand"
                ]
            )
        )

        return Output(scopeRef: scopeRef, entries: entries)
    }

    private func resolveWorkflow(
        in project: MAProject?,
        preferredWorkflowID: UUID?
    ) -> Workflow? {
        guard let project else { return nil }
        if let preferredWorkflowID,
           let workflow = project.workflows.first(where: { $0.id == preferredWorkflowID }) {
            return workflow
        }
        return project.workflows.first
    }

    private func resolveNode(
        in project: MAProject?,
        preferredNodeID: UUID?,
        preferredWorkflow: Workflow?
    ) -> (workflow: Workflow?, node: WorkflowNode?) {
        guard let project else {
            return (preferredWorkflow, nil)
        }

        guard let preferredNodeID else {
            return (preferredWorkflow, nil)
        }

        if let preferredWorkflow,
           let node = preferredWorkflow.nodes.first(where: { $0.id == preferredNodeID }) {
            return (preferredWorkflow, node)
        }

        for workflow in project.workflows {
            if let node = workflow.nodes.first(where: { $0.id == preferredNodeID }) {
                return (workflow, node)
            }
        }

        return (preferredWorkflow, nil)
    }

    private func normalizedSelectionRange(
        start: Int?,
        end: Int?
    ) -> (Int, Int)? {
        guard let start, let end else { return nil }
        guard start >= 0, end >= start else { return nil }
        return (start, end)
    }

    private func normalizedMetadata(
        _ metadata: [String: String]
    ) -> [String: String] {
        var normalized: [String: String] = [:]
        for (key, value) in metadata {
            let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedKey.isEmpty,
                  let trimmedValue = normalizedValue(value) else {
                continue
            }
            normalized[trimmedKey] = trimmedValue
        }
        return normalized
    }

    private func normalizedValue(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func userIntentSummary(
        prompt: String,
        source: AssistRequestSource,
        intent: AssistIntent,
        scopeType: AssistScopeType
    ) -> String {
        [
            "Prompt: \(truncated(prompt, limit: 600))",
            "Source: \(source.rawValue)",
            "Intent: \(intent.rawValue)",
            "Scope: \(scopeType.rawValue)"
        ].joined(separator: "\n")
    }

    private func projectSummary(_ project: MAProject) -> String {
        [
            "Project: \(project.name)",
            "Agents: \(project.agents.count)",
            "Workflows: \(project.workflows.count)",
            "Workspace Records: \(project.workspaceIndex.count)",
            "Runtime Session: \(project.runtimeState.sessionID)"
        ].joined(separator: "\n")
    }

    private func workflowSummary(
        _ workflow: Workflow,
        in project: MAProject?
    ) -> String {
        let connectedEntryAgents = entryConnectedAgentNames(for: workflow, in: project)
        var lines = [
            "Workflow: \(workflow.name)",
            "Nodes: \(workflow.nodes.count)",
            "Edges: \(workflow.edges.count)",
            "Boundaries: \(workflow.boundaries.count)",
            "Fallback Routing: \(workflow.fallbackRoutingPolicy.rawValue)"
        ]

        if !connectedEntryAgents.isEmpty {
            lines.append("Entry Agents: \(connectedEntryAgents.joined(separator: ", "))")
        }

        return lines.joined(separator: "\n")
    }

    private func encodedWorkflowLayoutSnapshot(
        _ workflow: Workflow
    ) -> String? {
        let snapshot = AssistWorkflowLayoutSnapshot(
            workflowID: workflow.id,
            workflowName: workflow.name,
            nodes: workflow.nodes.map { node in
                AssistWorkflowLayoutSnapshotNode(
                    nodeID: node.id,
                    title: node.title,
                    nodeType: node.type.rawValue,
                    x: Double(node.position.x),
                    y: Double(node.position.y)
                )
            },
            edges: workflow.edges.map { edge in
                AssistWorkflowLayoutSnapshotEdge(
                    fromNodeID: edge.fromNodeID,
                    toNodeID: edge.toNodeID
                )
            }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(snapshot) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func nodeSummary(
        _ node: WorkflowNode,
        workflow: Workflow?,
        project: MAProject?
    ) -> String {
        var lines = [
            "Node: \(node.title)",
            "Type: \(node.type.rawValue)",
            "Position: (\(Int(node.position.x)), \(Int(node.position.y)))"
        ]

        if let workflow {
            lines.append("Workflow: \(workflow.name)")
        }

        if let agentID = node.agentID,
           let agentName = project?.agents.first(where: { $0.id == agentID })?.name {
            lines.append("Assigned Agent: \(agentName)")
        }

        if !node.conditionExpression.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("Condition: \(node.conditionExpression)")
        }

        if node.loopEnabled {
            lines.append("Loop Enabled: true")
            lines.append("Max Iterations: \(node.maxIterations)")
        }

        return lines.joined(separator: "\n")
    }

    private func entryConnectedAgentNames(
        for workflow: Workflow,
        in project: MAProject?
    ) -> [String] {
        guard let project else { return [] }
        let nodeByID = Dictionary(uniqueKeysWithValues: workflow.nodes.map { ($0.id, $0) })
        let entryNodeIDs = Set(workflow.nodes.filter { $0.type == .start }.map(\.id))
        guard !entryNodeIDs.isEmpty else { return [] }

        let agentIDs = workflow.edges.compactMap { edge -> UUID? in
            guard entryNodeIDs.contains(edge.fromNodeID),
                  let node = nodeByID[edge.toNodeID],
                  node.type == .agent else {
                return nil
            }
            return node.agentID
        }

        return project.agents
            .filter { agentIDs.contains($0.id) }
            .map(\.name)
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func shouldIncludeRuntimeSummary(
        for intent: AssistIntent
    ) -> Bool {
        switch intent {
        case .inspectConfiguration, .inspectPerformance, .explainIssue:
            return true
        case .rewriteSelection, .completeTemplate, .modifyManagedContent, .reorganizeWorkflow, .custom:
            return false
        }
    }

    private func runtimeSummary(
        for runtimeState: RuntimeState
    ) -> String {
        [
            "Runtime Session: \(runtimeState.sessionID)",
            "Active Workbench Runs: \(runtimeState.activeWorkbenchRuns.count)",
            "Workbench Thread States: \(runtimeState.workbenchThreadStates.count)",
            "Dispatch Queue: \(runtimeState.dispatchQueue.count)",
            "Inflight Dispatches: \(runtimeState.inflightDispatches.count)",
            "Failed Dispatches: \(runtimeState.failedDispatches.count)",
            "Runtime Events: \(runtimeState.runtimeEvents.count)",
            "Workflow Revision: \(runtimeState.workflowConfigurationRevision)",
            "Mirror Revision: \(runtimeState.appliedToMirrorConfigurationRevision)",
            "Synced Runtime Revision: \(runtimeState.syncedToRuntimeConfigurationRevision)"
        ].joined(separator: "\n")
    }

    private func threadHistorySummary(
        workflowID: UUID,
        threadID: String,
        snapshot: Snapshot
    ) -> String? {
        let matchedMessages = snapshot.messages
            .filter { message in
                message.metadata[WorkbenchMetadataKey.channel] == "workbench"
                    && message.metadata[WorkbenchMetadataKey.workflowID] == workflowID.uuidString
                    && resolvedWorkbenchThreadID(from: message.metadata) == threadID
            }
            .sorted { $0.timestamp < $1.timestamp }

        let matchedTasks = snapshot.tasks
            .filter { task in
                task.metadata[WorkbenchMetadataKey.workflowID] == workflowID.uuidString
                    && resolvedWorkbenchThreadID(from: task.metadata) == threadID
            }
            .sorted { $0.createdAt < $1.createdAt }

        guard !matchedMessages.isEmpty || !matchedTasks.isEmpty else {
            return nil
        }

        let latestMetadata = matchedMessages.last?.metadata ?? matchedTasks.last?.metadata ?? [:]
        var lines = [
            "Thread ID: \(threadID)",
            "Messages: \(matchedMessages.count)",
            "Tasks: \(matchedTasks.count)"
        ]

        if let interactionMode = WorkbenchInteractionMode(normalizedRawValue: latestMetadata[WorkbenchMetadataKey.workbenchMode]) {
            lines.append("Mode: \(interactionMode.rawValue)")
        }
        if let threadType = resolvedWorkbenchThreadType(from: latestMetadata) {
            lines.append("Thread Type: \(threadType.rawValue)")
        }
        if let threadMode = resolvedWorkbenchThreadMode(from: latestMetadata) {
            lines.append("Thread Semantic Mode: \(threadMode.rawValue)")
        }

        let messagePreview = matchedMessages
            .suffix(3)
            .map { message in
                let role = message.inferredRole ?? "assistant"
                return "\(role): \(truncated(message.summaryText, limit: 180))"
            }
        if !messagePreview.isEmpty {
            lines.append("Recent Messages:")
            lines.append(contentsOf: messagePreview)
        }

        let taskPreview = matchedTasks
            .suffix(2)
            .map { task in
                "\(task.status.rawValue): \(truncated(task.title, limit: 180))"
            }
        if !taskPreview.isEmpty {
            lines.append("Recent Tasks:")
            lines.append(contentsOf: taskPreview)
        }

        return lines.joined(separator: "\n")
    }

    private func guardrailSummary(
        for scopeRef: AssistScopeReference
    ) -> String {
        let workspaceSurface = scopeRef.workspaceSurface?.rawValue ?? "unspecified"
        return [
            "Assist is a gloved, least-privilege, rollbackable hand.",
            "It prepares suggestions first and requires explicit confirmation before applying changes.",
            "Live runtime mutation is forbidden; work stays in draft, managed workspace, mirror, or read-only runtime scopes.",
            "Current workspace surface: \(workspaceSurface)"
        ].joined(separator: "\n")
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
