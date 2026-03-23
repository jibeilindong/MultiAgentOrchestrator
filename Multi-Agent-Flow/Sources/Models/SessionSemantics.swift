import Foundation

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
