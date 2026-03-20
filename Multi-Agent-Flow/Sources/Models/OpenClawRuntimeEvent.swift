import Foundation

enum OpenClawRuntimeEventType: String, Codable, CaseIterable, Hashable {
    case taskDispatch = "task.dispatch"
    case taskAccepted = "task.accepted"
    case taskProgress = "task.progress"
    case taskResult = "task.result"
    case taskRoute = "task.route"
    case taskError = "task.error"
    case taskApprovalRequired = "task.approval_required"
    case taskApproved = "task.approved"
    case sessionSync = "session.sync"
}

enum OpenClawRuntimeActorKind: String, Codable, Hashable {
    case agent
    case orchestrator
    case system
    case user
}

enum OpenClawRuntimeTransportKind: String, Codable, Hashable {
    case cli
    case gatewayAgent = "gateway_agent"
    case gatewayChat = "gateway_chat"
    case runtimeChannel = "runtime_channel"
    case unknown
}

enum OpenClawRuntimeRefKind: String, Codable, Hashable {
    case artifact
    case text
    case json
    case workspaceFile = "workspace_file"
    case stateFile = "state_file"
    case configFile = "config_file"
    case sessionMirror = "session_mirror"
    case sessionBackup = "session_backup"
    case executionResult = "execution_result"
    case executionLog = "execution_log"
    case nodeResult = "node_result"
    case contextSnapshot = "context_snapshot"
}

struct OpenClawRuntimeActor: Codable, Hashable {
    var kind: OpenClawRuntimeActorKind
    var agentId: String
    var agentName: String?
}

struct OpenClawRuntimeTransport: Codable, Hashable {
    var kind: OpenClawRuntimeTransportKind
    var deploymentKind: String?
}

struct OpenClawRuntimeRef: Codable, Hashable, Identifiable {
    var id: String { refId }
    var refId: String
    var kind: OpenClawRuntimeRefKind
    var locator: String
    var path: String?
    var contentType: String?
    var hash: String?
}

struct OpenClawRuntimeIntegrity: Codable, Hashable {
    var hash: String?
}

struct OpenClawRuntimeEvent: Codable, Hashable, Identifiable {
    let id: String
    var version: String
    var eventType: OpenClawRuntimeEventType
    var timestamp: Date
    var projectId: String?
    var workflowId: String?
    var nodeId: String?
    var runId: String?
    var sessionKey: String?
    var parentEventId: String?
    var idempotencyKey: String?
    var attempt: Int?
    var source: OpenClawRuntimeActor
    var target: OpenClawRuntimeActor
    var transport: OpenClawRuntimeTransport
    var payload: [String: String]
    var refs: [OpenClawRuntimeRef]
    var constraints: [String: String]
    var control: [String: String]
    var integrity: OpenClawRuntimeIntegrity?

    enum CodingKeys: String, CodingKey {
        case id = "eventId"
        case version
        case eventType
        case timestamp
        case projectId
        case workflowId
        case nodeId
        case runId
        case sessionKey
        case parentEventId
        case idempotencyKey
        case attempt
        case source
        case target
        case transport
        case payload
        case refs
        case constraints
        case control
        case integrity
    }

    init(
        id: String = UUID().uuidString,
        version: String = "openclaw.runtime.v1",
        eventType: OpenClawRuntimeEventType,
        timestamp: Date = Date(),
        projectId: String? = nil,
        workflowId: String? = nil,
        nodeId: String? = nil,
        runId: String? = nil,
        sessionKey: String? = nil,
        parentEventId: String? = nil,
        idempotencyKey: String? = nil,
        attempt: Int? = 1,
        source: OpenClawRuntimeActor,
        target: OpenClawRuntimeActor,
        transport: OpenClawRuntimeTransport,
        payload: [String: String] = [:],
        refs: [OpenClawRuntimeRef] = [],
        constraints: [String: String] = [:],
        control: [String: String] = [:],
        integrity: OpenClawRuntimeIntegrity? = nil
    ) {
        self.id = id
        self.version = version
        self.eventType = eventType
        self.timestamp = timestamp
        self.projectId = projectId
        self.workflowId = workflowId
        self.nodeId = nodeId
        self.runId = runId
        self.sessionKey = sessionKey
        self.parentEventId = parentEventId
        self.idempotencyKey = idempotencyKey
        self.attempt = attempt
        self.source = source
        self.target = target
        self.transport = transport
        self.payload = payload
        self.refs = refs
        self.constraints = constraints
        self.control = control
        self.integrity = integrity
    }
}

extension OpenClawRuntimeEvent {
    var summaryText: String {
        if let summary = payload["summary"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !summary.isEmpty {
            return summary
        }

        if let reason = payload["reason"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !reason.isEmpty {
            return reason
        }

        if let action = payload["action"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !action.isEmpty {
            return action
        }

        switch eventType {
        case .taskDispatch:
            return "Task dispatched"
        case .taskAccepted:
            return "Task accepted"
        case .taskProgress:
            return "Task in progress"
        case .taskResult:
            return "Task completed"
        case .taskRoute:
            return "Task routed"
        case .taskError:
            return "Task failed"
        case .taskApprovalRequired:
            return "Approval required"
        case .taskApproved:
            return "Task approved"
        case .sessionSync:
            return "Session synchronized"
        }
    }

    var summaryLine: String {
        let actorName = source.agentName ?? target.agentName ?? source.agentId
        return "\(eventType.rawValue) | \(actorName) | \(summaryText)"
    }
}
