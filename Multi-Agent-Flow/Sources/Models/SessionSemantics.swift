import Foundation

enum WorkbenchMetadataKey {
    static let channel = "channel"
    static let workflowID = "workflowID"
    static let workbenchMode = "workbenchMode"
    static let executionIntent = "executionIntent"
    static let workbenchSessionID = "workbenchSessionID"
    static let workbenchThreadID = "workbenchThreadID"
    static let workbenchThreadType = "workbenchThreadType"
    static let workbenchThreadMode = "workbenchThreadMode"
    static let workbenchThreadOrigin = "workbenchThreadOrigin"
    static let workbenchEntryAgentID = "workbenchEntryAgentID"
    static let workbenchProjectSessionID = "workbenchProjectSessionID"
    static let workbenchGatewaySessionKey = "workbenchGatewaySessionKey"
}

private func normalizedWorkbenchMetadataValue(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

func resolvedWorkbenchSessionID(from metadata: [String: String]) -> String? {
    normalizedWorkbenchMetadataValue(metadata[WorkbenchMetadataKey.workbenchSessionID])
}

func resolvedWorkbenchGatewaySessionKey(from metadata: [String: String]) -> String? {
    normalizedWorkbenchMetadataValue(metadata[WorkbenchMetadataKey.workbenchGatewaySessionKey])
}

func resolvedWorkbenchThreadType(from metadata: [String: String]) -> RuntimeSessionSemanticType? {
    RuntimeSessionSemanticType(normalizedRawValue: metadata[WorkbenchMetadataKey.workbenchThreadType])
}

func resolvedWorkbenchThreadMode(from metadata: [String: String]) -> WorkbenchThreadSemanticMode? {
    WorkbenchThreadSemanticMode(normalizedRawValue: metadata[WorkbenchMetadataKey.workbenchThreadMode])
}

func resolvedWorkbenchThreadID(from metadata: [String: String]) -> String? {
    if let explicitThreadID = normalizedWorkbenchMetadataValue(metadata[WorkbenchMetadataKey.workbenchThreadID]) {
        return explicitThreadID
    }

    guard let sessionID = resolvedWorkbenchSessionID(from: metadata) else { return nil }

    let workflowID = normalizedWorkbenchMetadataValue(metadata[WorkbenchMetadataKey.workflowID]) ?? "unknown-workflow"
    let threadType = resolvedWorkbenchThreadType(from: metadata)?.rawValue ?? "unknown-thread-type"
    let threadMode = resolvedWorkbenchThreadMode(from: metadata)?.rawValue ?? "unknown-thread-mode"
    return "legacy-\(workflowID)-\(threadType)-\(threadMode)-\(sessionID)"
}

enum RuntimeSessionSemanticType: String, Codable, CaseIterable, Sendable {
    case conversationAutonomous = "conversation.autonomous"
    case conversationAssisted = "conversation.assisted"
    case workflowControlled = "run.controlled"
    case inspectionReadonly = "inspection.readonly"
    case benchmark
    case unknown

    init?(normalizedRawValue: String?) {
        let normalized = normalizedRawValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        guard !normalized.isEmpty else { return nil }

        switch normalized {
        case Self.conversationAutonomous.rawValue,
             OpenClawRuntimeExecutionIntent.conversationAutonomous.rawValue:
            self = .conversationAutonomous
        case Self.conversationAssisted.rawValue:
            self = .conversationAssisted
        case Self.workflowControlled.rawValue,
             OpenClawRuntimeExecutionIntent.workflowControlled.rawValue:
            self = .workflowControlled
        case Self.inspectionReadonly.rawValue,
             OpenClawRuntimeExecutionIntent.inspectionReadonly.rawValue:
            self = .inspectionReadonly
        case Self.benchmark.rawValue,
             OpenClawRuntimeExecutionIntent.benchmark.rawValue:
            self = .benchmark
        case Self.unknown.rawValue:
            self = .unknown
        default:
            return nil
        }
    }

    var displayTitle: String { rawValue }

    static func preferredWorkbenchThreadType(from candidates: [RuntimeSessionSemanticType]) -> RuntimeSessionSemanticType? {
        let set = Set(candidates)
        if set.contains(.conversationAssisted) {
            return .conversationAssisted
        }
        if set.contains(.conversationAutonomous) {
            return .conversationAutonomous
        }
        if set.contains(.workflowControlled) {
            return .workflowControlled
        }
        if set.contains(.inspectionReadonly) {
            return .inspectionReadonly
        }
        if set.contains(.benchmark) {
            return .benchmark
        }
        if set.contains(.unknown) {
            return .unknown
        }
        return candidates.first
    }
}

enum WorkbenchThreadSemanticMode: String, Codable, CaseIterable, Sendable {
    case autonomousConversation = "autonomous_conversation"
    case controlledRun = "controlled_run"
    case conversationToRun = "conversation_to_run"

    init?(normalizedRawValue: String?) {
        let normalized = normalizedRawValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        guard !normalized.isEmpty else { return nil }

        switch normalized {
        case Self.autonomousConversation.rawValue, "chat":
            self = .autonomousConversation
        case Self.controlledRun.rawValue, "run":
            self = .controlledRun
        case Self.conversationToRun.rawValue, "chat->run":
            self = .conversationToRun
        default:
            return nil
        }
    }

    var displayTitle: String {
        switch self {
        case .autonomousConversation:
            return "chat"
        case .controlledRun:
            return "run"
        case .conversationToRun:
            return "chat->run"
        }
    }

    static func preferredMode(from candidates: [WorkbenchThreadSemanticMode]) -> WorkbenchThreadSemanticMode? {
        let set = Set(candidates)
        if set.contains(.conversationToRun)
            || (set.contains(.autonomousConversation) && set.contains(.controlledRun)) {
            return .conversationToRun
        }
        if set.contains(.controlledRun) {
            return .controlledRun
        }
        if set.contains(.autonomousConversation) {
            return .autonomousConversation
        }
        return candidates.first
    }

    static func inferred(from sessionTypes: [RuntimeSessionSemanticType]) -> WorkbenchThreadSemanticMode {
        let set = Set(sessionTypes)
        let hasConversation = set.contains(.conversationAutonomous) || set.contains(.conversationAssisted)
        let hasRun = set.contains(.workflowControlled)

        if hasConversation && hasRun {
            return .conversationToRun
        }
        if hasRun || set.contains(.conversationAssisted) {
            return .controlledRun
        }
        return .autonomousConversation
    }
}

enum WorkbenchConversationState: String, Codable, CaseIterable, Sendable {
    case idle
    case responding
    case readyToRun = "ready_to_run"
    case running
    case stopping
    case completed
    case failed

    var badgeTitle: String {
        switch self {
        case .idle:
            return "idle"
        case .responding:
            return "responding"
        case .readyToRun:
            return "ready"
        case .running:
            return "running"
        case .stopping:
            return "stopping"
        case .completed:
            return "completed"
        case .failed:
            return "failed"
        }
    }
}

enum WorkbenchThreadTransition: Sendable, Equatable {
    case chatSubmitted
    case runSubmitted
    case escalatedToBackgroundRun
    case readyToRun
    case completed(interactionMode: WorkbenchInteractionMode? = nil, threadMode: WorkbenchThreadSemanticMode? = nil)
    case failed(
        errorMessage: String? = nil,
        interactionMode: WorkbenchInteractionMode? = nil,
        threadMode: WorkbenchThreadSemanticMode? = nil
    )
    case stopRequested
    case disconnected(reason: String)
}

struct WorkbenchThreadTransitionResolution: Sendable {
    let interactionMode: WorkbenchInteractionMode
    let threadMode: WorkbenchThreadSemanticMode
    let state: WorkbenchConversationState
    let errorMessage: String?
}

enum WorkbenchThreadTransitionResolver {
    static func resolve(
        _ transition: WorkbenchThreadTransition,
        interactionMode: WorkbenchInteractionMode,
        threadMode: WorkbenchThreadSemanticMode
    ) -> WorkbenchThreadTransitionResolution {
        switch transition {
        case .chatSubmitted:
            return WorkbenchThreadTransitionResolution(
                interactionMode: .chat,
                threadMode: threadMode,
                state: .responding,
                errorMessage: nil
            )
        case .runSubmitted:
            return WorkbenchThreadTransitionResolution(
                interactionMode: .run,
                threadMode: threadMode,
                state: .running,
                errorMessage: nil
            )
        case .escalatedToBackgroundRun:
            return WorkbenchThreadTransitionResolution(
                interactionMode: .run,
                threadMode: .conversationToRun,
                state: .running,
                errorMessage: nil
            )
        case .readyToRun:
            return WorkbenchThreadTransitionResolution(
                interactionMode: interactionMode,
                threadMode: threadMode,
                state: .readyToRun,
                errorMessage: nil
            )
        case let .completed(interactionModeOverride, threadModeOverride):
            return WorkbenchThreadTransitionResolution(
                interactionMode: interactionModeOverride ?? interactionMode,
                threadMode: threadModeOverride ?? threadMode,
                state: .completed,
                errorMessage: nil
            )
        case let .failed(errorMessage, interactionModeOverride, threadModeOverride):
            return WorkbenchThreadTransitionResolution(
                interactionMode: interactionModeOverride ?? interactionMode,
                threadMode: threadModeOverride ?? threadMode,
                state: .failed,
                errorMessage: errorMessage
            )
        case .stopRequested:
            return WorkbenchThreadTransitionResolution(
                interactionMode: interactionMode,
                threadMode: threadMode,
                state: .stopping,
                errorMessage: nil
            )
        case let .disconnected(reason):
            return WorkbenchThreadTransitionResolution(
                interactionMode: interactionMode,
                threadMode: threadMode,
                state: .failed,
                errorMessage: reason
            )
        }
    }
}

struct WorkbenchConversationStateDerivationInput: Sendable {
    var interactionMode: WorkbenchInteractionMode
    var threadMode: WorkbenchThreadSemanticMode
    var latestTaskStatus: TaskStatus?
    var latestUserMessageAt: Date?
    var latestAssistantMessageAt: Date?
    var latestAssistantThinking: Bool
    var latestAssistantOutputType: String?
    var hasRunActivity: Bool
    var activeRunStatus: WorkbenchActiveRunStatus?
    var explicitState: WorkbenchConversationState?
}

enum WorkbenchConversationStateResolver {
    static func resolve(_ input: WorkbenchConversationStateDerivationInput) -> WorkbenchConversationState {
        if let activeRunStatus = input.activeRunStatus {
            switch activeRunStatus {
            case .running:
                return .running
            case .stopping:
                return .stopping
            }
        }

        if let explicitState = input.explicitState {
            return explicitState
        }

        let normalizedOutputType = input.latestAssistantOutputType?.trimmingCharacters(in: .whitespacesAndNewlines)

        if input.latestTaskStatus == .blocked || normalizedOutputType == ExecutionOutputType.errorSummary.rawValue {
            return .failed
        }

        if input.latestAssistantThinking {
            return input.interactionMode == .run ? .running : .responding
        }

        if let latestUserAt = input.latestUserMessageAt,
           latestUserAt > (input.latestAssistantMessageAt ?? .distantPast) {
            return input.interactionMode == .run ? .running : .responding
        }

        if input.hasRunActivity {
            if input.latestTaskStatus == .done {
                return .completed
            }
            if input.latestTaskStatus == .inProgress {
                return .running
            }
        }

        if input.latestAssistantMessageAt != nil {
            return .readyToRun
        }

        return .idle
    }
}

extension OpenClawRuntimeExecutionIntent {
    var semanticType: RuntimeSessionSemanticType {
        switch self {
        case .conversationAutonomous:
            return .conversationAutonomous
        case .workflowControlled:
            return .workflowControlled
        case .inspectionReadonly:
            return .inspectionReadonly
        case .benchmark:
            return .benchmark
        }
    }
}
