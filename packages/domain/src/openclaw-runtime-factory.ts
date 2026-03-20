import {
  OPENCLAW_RUNTIME_PROTOCOL_VERSION,
  type OpenClawRuntimeActor,
  type OpenClawRuntimeConstraints,
  type OpenClawRuntimeControl,
  type OpenClawRuntimeEvent,
  type OpenClawRuntimeEventType,
  type OpenClawRuntimeIntegrity,
  type OpenClawRuntimePayload,
  type OpenClawRuntimeRef,
  type OpenClawRuntimeTransport
} from "./openclaw-runtime";

export interface CreateOpenClawRuntimeEventInput {
  eventId: string;
  eventType: OpenClawRuntimeEventType;
  timestamp: string;
  source: OpenClawRuntimeActor;
  target: OpenClawRuntimeActor;
  transport?: Partial<OpenClawRuntimeTransport>;
  payload?: OpenClawRuntimePayload;
  refs?: OpenClawRuntimeRef[];
  constraints?: OpenClawRuntimeConstraints;
  control?: OpenClawRuntimeControl;
  integrity?: OpenClawRuntimeIntegrity | null;
  projectId?: string | null;
  workflowId?: string | null;
  nodeId?: string | null;
  runId?: string | null;
  sessionKey?: string | null;
  parentEventId?: string | null;
  idempotencyKey?: string | null;
  attempt?: number | null;
}

export function createOpenClawRuntimeEvent(input: CreateOpenClawRuntimeEventInput): OpenClawRuntimeEvent {
  return {
    version: OPENCLAW_RUNTIME_PROTOCOL_VERSION,
    eventId: input.eventId,
    eventType: input.eventType,
    timestamp: input.timestamp,
    projectId: input.projectId ?? null,
    workflowId: input.workflowId ?? null,
    nodeId: input.nodeId ?? null,
    runId: input.runId ?? null,
    sessionKey: input.sessionKey ?? null,
    parentEventId: input.parentEventId ?? null,
    idempotencyKey: input.idempotencyKey ?? null,
    attempt: input.attempt ?? 1,
    source: input.source,
    target: input.target,
    transport: {
      kind: input.transport?.kind ?? "unknown",
      deploymentKind: input.transport?.deploymentKind ?? null
    },
    payload: input.payload ?? {},
    refs: input.refs ?? [],
    constraints: input.constraints ?? {},
    control: input.control ?? {},
    integrity: input.integrity ?? null
  };
}
