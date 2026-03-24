import Foundation

extension AppState {
    struct QuickChatContext: Equatable {
        let projectID: UUID
        let projectName: String
        let workflowID: UUID
        let workflowName: String
        let entryAgentID: UUID
        let entryAgentName: String
        let agentIdentifier: String
    }

    func resolveQuickChatContext() -> QuickChatContext? {
        guard let project = currentProject else { return nil }
        guard let workflow = workflow(for: activeWorkflowID) ?? project.workflows.first else { return nil }

        let nodeByID = Dictionary(uniqueKeysWithValues: workflow.nodes.map { ($0.id, $0) })
        let sortedAgentNodes = workflow.nodes
            .filter { $0.type == .agent && $0.agentID != nil }
            .sorted(by: Self.quickChatNodeSort)
        let entryNode = workflow.nodes
            .filter { $0.type == .start }
            .sorted(by: Self.quickChatNodeSort)
            .first

        let connectedEntryAgent = entryNode
            .flatMap { entryNode in
                workflow.edges
                    .filter { $0.fromNodeID == entryNode.id }
                    .compactMap { nodeByID[$0.toNodeID] }
                    .filter { $0.type == .agent && $0.agentID != nil }
                    .sorted(by: Self.quickChatNodeSort)
                    .first
            }

        let resolvedNode = connectedEntryAgent ?? sortedAgentNodes.first
        guard let resolvedNode,
              let agent = getAgent(for: resolvedNode) else {
            return nil
        }

        return QuickChatContext(
            projectID: project.id,
            projectName: project.name,
            workflowID: workflow.id,
            workflowName: workflow.name,
            entryAgentID: agent.id,
            entryAgentName: agent.name,
            agentIdentifier: quickChatAgentIdentifier(for: agent)
        )
    }

    private func quickChatAgentIdentifier(for agent: Agent) -> String {
        let configuredIdentifier = agent.openClawDefinition.agentIdentifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !configuredIdentifier.isEmpty {
            return configuredIdentifier
        }

        let fallbackName = agent.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !fallbackName.isEmpty {
            return fallbackName
        }

        let defaultAgent = openClawManager.config.defaultAgent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return defaultAgent.isEmpty ? "default" : defaultAgent
    }

    nonisolated private static func quickChatNodeSort(_ lhs: WorkflowNode, _ rhs: WorkflowNode) -> Bool {
        if lhs.position.y != rhs.position.y {
            return lhs.position.y < rhs.position.y
        }
        if lhs.position.x != rhs.position.x {
            return lhs.position.x < rhs.position.x
        }
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }
}
