export const OPENCLAW_RUNTIME_PROTOCOL_VERSION = "openclaw.runtime.v1" as const;
export type OpenClawRuntimeProtocolVersion = typeof OPENCLAW_RUNTIME_PROTOCOL_VERSION;

export const OPENCLAW_RUNTIME_EVENT_TYPES = [
  "task.dispatch",
  "task.accepted",
  "task.progress",
  "task.result",
  "task.route",
  "task.error",
  "task.approval_required",
  "task.approved",
  "session.sync"
] as const;
export type OpenClawRuntimeEventType = (typeof OPENCLAW_RUNTIME_EVENT_TYPES)[number];

export const OPENCLAW_RUNTIME_SOURCE_KINDS = ["agent", "orchestrator", "system", "user"] as const;
export type OpenClawRuntimeSourceKind = (typeof OPENCLAW_RUNTIME_SOURCE_KINDS)[number];

export const OPENCLAW_RUNTIME_TRANSPORT_KINDS = [
  "cli",
  "gateway_agent",
  "gateway_chat",
  "runtime_channel",
  "unknown"
] as const;
export type OpenClawRuntimeTransportKind = (typeof OPENCLAW_RUNTIME_TRANSPORT_KINDS)[number];

export const OPENCLAW_RUNTIME_REF_KINDS = [
  "artifact",
  "text",
  "json",
  "workspace_file",
  "state_file",
  "config_file",
  "session_mirror",
  "session_backup",
  "execution_result",
  "execution_log",
  "node_result",
  "context_snapshot"
] as const;
export type OpenClawRuntimeRefKind = (typeof OPENCLAW_RUNTIME_REF_KINDS)[number];

export const OPENCLAW_RUNTIME_TASK_INTENTS = [
  "analyze",
  "code",
  "review",
  "test",
  "route",
  "summarize",
  "respond",
  "sync",
  "unknown"
] as const;
export type OpenClawRuntimeTaskIntent = (typeof OPENCLAW_RUNTIME_TASK_INTENTS)[number];

export const OPENCLAW_RUNTIME_TASK_STATUSES = [
  "created",
  "dispatched",
  "accepted",
  "running",
  "waiting_approval",
  "waiting_dependency",
  "completed",
  "failed",
  "aborted",
  "expired",
  "partial"
] as const;
export type OpenClawRuntimeTaskStatus = (typeof OPENCLAW_RUNTIME_TASK_STATUSES)[number];

export const OPENCLAW_RUNTIME_RESULT_STATUSES = ["success", "partial", "fail"] as const;
export type OpenClawRuntimeResultStatus = (typeof OPENCLAW_RUNTIME_RESULT_STATUSES)[number];

export const OPENCLAW_RUNTIME_ROUTE_ACTIONS = ["stop", "selected", "all"] as const;
export type OpenClawRuntimeRouteAction = (typeof OPENCLAW_RUNTIME_ROUTE_ACTIONS)[number];

export const OPENCLAW_RUNTIME_PRIORITIES = ["low", "medium", "high", "critical"] as const;
export type OpenClawRuntimePriority = (typeof OPENCLAW_RUNTIME_PRIORITIES)[number];

export const OPENCLAW_RUNTIME_APPROVAL_SCOPES = ["edge", "agent", "tool", "artifact", "workflow"] as const;
export type OpenClawRuntimeApprovalScope = (typeof OPENCLAW_RUNTIME_APPROVAL_SCOPES)[number];

export interface OpenClawRuntimeActor {
  kind: OpenClawRuntimeSourceKind;
  agentId: string;
  agentName?: string | null;
}

export interface OpenClawRuntimeTransport {
  kind: OpenClawRuntimeTransportKind;
  deploymentKind?: string | null;
}

export interface OpenClawRuntimeRef {
  refId: string;
  kind: OpenClawRuntimeRefKind;
  locator: string;
  path?: string | null;
  contentType?: string | null;
  hash?: string | null;
}

export interface OpenClawRuntimeConstraints {
  timeoutSeconds?: number | null;
  maxInputTokens?: number | null;
  maxOutputTokens?: number | null;
  thinkingLevel?: string | null;
  writeScope?: string[];
  toolScope?: string[];
}

export interface OpenClawRuntimeControl {
  requiresApproval?: boolean;
  fallbackRoutingPolicy?: string | null;
  allowRetry?: boolean;
  maxRetries?: number | null;
  priority?: OpenClawRuntimePriority | null;
}

export interface OpenClawRuntimeIntegrity {
  hash?: string | null;
}

export interface OpenClawTaskDispatchPayload {
  intent: OpenClawRuntimeTaskIntent;
  summary: string;
  inputRefIds: string[];
  expectedOutput: string;
  visibleToUser?: boolean;
}

export interface OpenClawTaskAcceptedPayload {
  accepted: true;
  status: Extract<OpenClawRuntimeTaskStatus, "accepted">;
}

export interface OpenClawTaskProgressPayload {
  phase: string;
  progress?: number | null;
  status: Extract<OpenClawRuntimeTaskStatus, "running" | "waiting_dependency" | "waiting_approval">;
}

export interface OpenClawTaskResultPayload {
  status: OpenClawRuntimeResultStatus;
  outputType: string;
  summary: string;
  artifactRefIds: string[];
  routeRefId?: string | null;
}

export interface OpenClawTaskRoutePayload {
  action: OpenClawRuntimeRouteAction;
  targets: string[];
  reason?: string | null;
}

export interface OpenClawTaskErrorPayload {
  code: string;
  message: string;
  retryable: boolean;
  detailsRef?: string | null;
}

export interface OpenClawTaskApprovalRequiredPayload {
  approvalScope: OpenClawRuntimeApprovalScope;
  approvalKey: string;
  requestedAction: string;
  targetAgentId?: string | null;
  reason?: string | null;
}

export interface OpenClawTaskApprovedPayload {
  approvalScope: OpenClawRuntimeApprovalScope;
  approvalKey: string;
  approved: true;
}

export interface OpenClawSessionSyncPayload {
  action: "snapshot" | "mirror" | "restore";
  snapshotRef?: string | null;
}

export type OpenClawRuntimePayload =
  | OpenClawTaskDispatchPayload
  | OpenClawTaskAcceptedPayload
  | OpenClawTaskProgressPayload
  | OpenClawTaskResultPayload
  | OpenClawTaskRoutePayload
  | OpenClawTaskErrorPayload
  | OpenClawTaskApprovalRequiredPayload
  | OpenClawTaskApprovedPayload
  | OpenClawSessionSyncPayload
  | Record<string, unknown>;

export interface OpenClawRuntimeEvent {
  version: OpenClawRuntimeProtocolVersion;
  eventId: string;
  eventType: OpenClawRuntimeEventType;
  timestamp: string;
  projectId?: string | null;
  workflowId?: string | null;
  nodeId?: string | null;
  runId?: string | null;
  sessionKey?: string | null;
  parentEventId?: string | null;
  idempotencyKey?: string | null;
  attempt?: number | null;
  source: OpenClawRuntimeActor;
  target: OpenClawRuntimeActor;
  transport: OpenClawRuntimeTransport;
  payload: OpenClawRuntimePayload;
  refs: OpenClawRuntimeRef[];
  constraints: OpenClawRuntimeConstraints;
  control: OpenClawRuntimeControl;
  integrity?: OpenClawRuntimeIntegrity | null;
}
