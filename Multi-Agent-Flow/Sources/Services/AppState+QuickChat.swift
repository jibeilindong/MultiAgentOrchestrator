import Foundation

extension AppState {
    struct QuickChatAgentOption: Identifiable, Equatable, Hashable {
        let projectID: UUID
        let projectName: String
        let workflowID: UUID
        let workflowName: String
        let agentID: UUID
        let agentName: String
        let agentIdentifier: String
        let isEntryPreferred: Bool

        var id: UUID { agentID }

        var context: QuickChatContext {
            QuickChatContext(
                projectID: projectID,
                projectName: projectName,
                workflowID: workflowID,
                workflowName: workflowName,
                entryAgentID: agentID,
                entryAgentName: agentName,
                agentIdentifier: agentIdentifier
            )
        }
    }

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
        resolveQuickChatAgentOptions().first?.context
    }

    func resolveQuickChatContext(for agentID: UUID?) -> QuickChatContext? {
        if let agentID,
           let option = resolveQuickChatAgentOptions().first(where: { $0.agentID == agentID }) {
            return option.context
        }
        return resolveQuickChatContext()
    }

    func resolveQuickChatAgentOptions() -> [QuickChatAgentOption] {
        guard let project = currentProject else { return [] }
        guard let workflow = workflow(for: activeWorkflowID) ?? project.workflows.first else { return [] }

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

        var orderedNodes: [WorkflowNode] = []
        if let connectedEntryAgent {
            orderedNodes.append(connectedEntryAgent)
        }
        orderedNodes.append(contentsOf: sortedAgentNodes.filter { node in
            node.id != connectedEntryAgent?.id
        })

        var seenAgentIDs = Set<UUID>()
        let options = orderedNodes.compactMap { node -> QuickChatAgentOption? in
            guard let agent = getAgent(for: node) else { return nil }
            guard seenAgentIDs.insert(agent.id).inserted else { return nil }

            return QuickChatAgentOption(
                projectID: project.id,
                projectName: project.name,
                workflowID: workflow.id,
                workflowName: workflow.name,
                agentID: agent.id,
                agentName: agent.name,
                agentIdentifier: quickChatAgentIdentifier(for: agent),
                isEntryPreferred: node.id == connectedEntryAgent?.id
            )
        }

        return options
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
