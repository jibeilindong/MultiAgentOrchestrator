# OpenClaw Agent Runtime Protocol

## Goal

Multi-Agent-Orchestrator now treats OpenClaw runtime events as the canonical machine-readable protocol for workflow-internal coordination.

The protocol exists to replace brittle agent-to-agent natural-language parsing with structured envelopes that can drive:

- dispatch
- acknowledgement
- progress
- result delivery
- routing
- failure handling
- approval checkpoints
- runtime replay and analytics

User-facing natural language still exists, but only on the UX plane. It is no longer the primary control surface for workflow coordination.

## Version

- protocol version: `openclaw.runtime.v1`

Primary definitions live in:

- `packages/domain/src/openclaw-runtime.ts`
- `packages/domain/src/openclaw-runtime-factory.ts`
- `Multi-Agent-Flow/Sources/Models/OpenClawRuntimeEvent.swift`

## Communication Planes

The current implementation is intentionally split into three planes.

### Data Plane

This is how work is actually executed.

- `gateway_agent` is the preferred hot-path transport for workflow runtime execution
- `cli` is the fallback transport
- `gateway_chat` is used for transcript/session-oriented execution paths

### Control Plane

This is the protocol described in this document.

- every machine-readable coordination step is represented as `OpenClawRuntimeEvent`
- runtime state, execution results, analytics, and trace views all consume the same event vocabulary

### Experience Plane

This is what users see.

- transcript text
- workbench messages
- dashboard summaries
- execution result views

The experience plane may be generated from runtime events, but it must not be treated as the source of truth for workflow coordination.

## Design Principles

- Structured first: coordination logic must read typed fields, not `Message.content`
- Compact payloads: payload values should stay short and stable
- Append-only traces: runtime behavior should be representable as event sequences
- Compatibility-friendly: legacy text fields remain available during migration
- Observable by default: the same protocol should power execution, persistence, and analytics
- Guardrail-aware: dispatch constraints and control metadata travel with the event

## Canonical Event Envelope

Every runtime event uses the following envelope shape:

- `eventId`
- `version`
- `eventType`
- `timestamp`
- `projectId`
- `workflowId`
- `nodeId`
- `runId`
- `sessionKey`
- `parentEventId`
- `idempotencyKey`
- `attempt`
- `source`
- `target`
- `transport`
- `payload`
- `refs`
- `constraints`
- `control`
- `integrity`

### Core Semantics

- `eventId` is the unique identity of the event itself
- `parentEventId` links acknowledgements, progress, results, and routes back to their parent event
- `idempotencyKey` is used to deduplicate retries and superseded dispatches
- `attempt` tracks retries for the same logical dispatch
- `source` identifies the producer
- `target` identifies the recipient or execution subject
- `transport` records how the event moved through OpenClaw
- `constraints` carries execution limits such as timeout, write scope, and tool scope
- `control` carries orchestration policy such as approval, retry, and fallback routing

## Supported Schema Values

The schema currently supports the following values.

### Event Types

- `task.dispatch`
- `task.accepted`
- `task.progress`
- `task.result`
- `task.route`
- `task.error`
- `task.approval_required`
- `task.approved`
- `session.sync`

### Actor Kinds

- `agent`
- `orchestrator`
- `system`
- `user`

### Transport Kinds

- `cli`
- `gateway_agent`
- `gateway_chat`
- `runtime_channel`
- `unknown`

### Ref Kinds

- `artifact`
- `text`
- `json`
- `workspace_file`
- `state_file`
- `config_file`
- `session_mirror`
- `session_backup`
- `execution_result`
- `execution_log`
- `node_result`
- `context_snapshot`

### Task Intents

- `analyze`
- `code`
- `review`
- `test`
- `route`
- `summarize`
- `respond`
- `sync`
- `unknown`

### Task Statuses

- `created`
- `dispatched`
- `accepted`
- `running`
- `waiting_approval`
- `waiting_dependency`
- `completed`
- `failed`
- `aborted`
- `expired`
- `partial`

### Result Statuses

- `success`
- `partial`
- `fail`

### Route Actions

- `stop`
- `selected`
- `all`

### Approval Scopes

- `edge`
- `agent`
- `tool`
- `artifact`
- `workflow`

## Payload, Constraints, Control, And Refs

### Payload

TypeScript defines typed payload variants for each event class. Swift currently stores payload as `[String: String]` for compatibility and simplicity.

In practice, current emitters mostly use short normalized keys such as:

- `summary`
- `reason`
- `action`
- `intent`
- `status`
- `outputType`
- `expectedOutput`
- `targets`
- `code`
- `message`
- `retryable`

Rules:

- `summary` is the preferred short machine-facing description
- `reason` explains routing or approval decisions
- `targets` is serialized as a comma-separated string in current Swift emitters
- long text should not be embedded in payload if a ref is sufficient

### Constraints

Current dispatch constraints commonly include:

- `timeoutSeconds`
- `thinkingLevel`
- `writeScope`
- `toolScope`

In Swift workflow execution, `writeScope` and `toolScope` are serialized as pipe-delimited strings inside the event.

### Control

Current control fields commonly include:

- `requiresApproval`
- `fallbackRoutingPolicy`
- `allowRetry`
- `maxRetries`
- `priority`

### Refs

Refs should be used for large or externalized outputs instead of embedding bulky text.

The current runtime protocol already supports linking artifacts, workspace files, session backups, execution logs, and context snapshots through `refs`.

## Current Emitters

The protocol schema supports more event types than every current runtime path emits. The distinction matters.

### 1. Swift Workflow Hot Path

The main workflow execution path in `OpenClawService` is the richest emitter today.

Files:

- `Multi-Agent-Flow/Sources/Services/OpenClawService.swift`
- `Multi-Agent-Flow/Sources/Services/AppState.swift`

Current emission sequence:

1. `task.dispatch`
2. `task.accepted`
3. optional `task.progress`
4. `task.result` or `task.error`
5. optional `task.route`
6. optional `task.approval_required`

Current details:

- `task.dispatch` carries prompt summary, expected output mode, visibility flag, timeout, write scope, tool scope, retry, and fallback routing policy
- `task.accepted` is synthesized when the runtime hands the dispatch to the agent execution path
- `task.progress` is emitted once on first meaningful stream chunk
- `task.result` stores `status`, `outputType`, and summary text
- `task.error` stores machine error code, message, and retryability
- `task.route` stores the agent-requested routing action, target list, and reason before final runtime sanitization
- `task.approval_required` is emitted when a requested route points to an approval-gated downstream target

### 2. Electron Desktop Shell Direct Execution

The Electron execution bridge emits a smaller but compatible envelope.

Files:

- `apps/desktop/electron/main.ts`
- `apps/desktop/electron/preload.ts`

Current emission sequence:

1. `task.dispatch`
2. `task.result` or `task.error`
3. optional `task.route`

Current details:

- this path does not currently emit `task.accepted` or `task.progress`
- `projectId`, `workflowId`, and `nodeId` are currently `null` in this direct execution bridge
- transport is derived from deployment mode and whether a session id is present

### 3. Workbench / Transcript Mirroring

Workbench and transcript synchronization generate protocol-compatible events so transcript state can be read using the same vocabulary.

Files:

- `Multi-Agent-Flow/Sources/Services/AppState.swift`
- `Multi-Agent-Flow/Sources/Models/Message.swift`

Current behavior:

- user turns are synthesized as `task.dispatch`
- assistant turns are synthesized as `task.result`
- these events use `gateway_chat` transport
- they are intended for UX/state continuity, not as the workflow hot path

### 4. Runtime Mailbox Timeout Synthesis

The runtime mailbox can synthesize timeout failures from stale dispatch records.

File:

- `Multi-Agent-Flow/Sources/Services/AppState.swift`

Current behavior:

- stale queued or inflight dispatches become `task.error`
- timeout code is `E_RUNTIME_DISPATCH_TIMEOUT`
- timed out records move into `failedDispatches`

### Not Widely Emitted Yet

The following are schema-level protocol values, but they are not yet primary emitters in the current workflow hot path:

- `task.approved`
- `session.sync`

They are still part of the protocol contract and compatibility fixtures, but should be treated as reserved or lightly used surfaces for now.

## Routing Contract Between Agent And Orchestrator

This is the most important runtime contract currently enforced at the execution layer.

File:

- `Multi-Agent-Flow/Sources/Services/OpenClawService.swift`

### Prompt Contract

When the workflow engine dispatches to an agent, it injects a routing instruction contract into the execution instruction.

Current rules include:

- downstream routing is opt-in
- the agent may only choose from the allowed downstream candidate list
- approval-required targets must not be contacted directly
- writes must stay within the resolved write scope
- tools must stay within the resolved tool scope
- the final non-empty line must be exactly one JSON routing object

Current required shape:

```json
{"workflow_route":{"action":"stop","targets":[],"reason":"short reason"}}
```

### Parser Behavior

Current parser behavior:

- routing JSON is extracted from stdout or visible plain response text
- accepted wrapper keys include `workflow_route`, `route`, and `routing`
- accepted action synonyms are normalized into `stop`, `selected`, or `all`
- the routing directive is stripped from the final visible answer after parsing

### Sanitization Behavior

The orchestrator does not trust requested routing blindly.

Current sanitization behavior:

- targets are matched only against allowed downstream descriptors
- approval-required targets are withheld from direct execution
- unsupported targets are rejected
- a selected route with no allowed targets is downgraded to `stop`
- sanitized routing is what gets persisted into `ExecutionResult.routingAction`, `routingTargets`, and `routingReason`

This means natural-language answers may describe intent, but only sanitized protocol output can actually drive downstream execution.

## Runtime Mailbox State

Project runtime state now includes a structured mailbox model.

Files:

- `Multi-Agent-Flow/Sources/Models/MAProject.swift`
- `packages/domain/src/project.ts`
- `Multi-Agent-Flow/Sources/Services/AppState.swift`

Current buckets:

- `dispatchQueue`
- `inflightDispatches`
- `completedDispatches`
- `failedDispatches`
- `runtimeEvents`

Compatibility field:

- `messageQueue` still exists, but it is legacy state and should not be used as the primary coordination model for new work

Current mailbox behavior:

- `task.dispatch` enqueues a `RuntimeDispatchRecord`
- `task.accepted` promotes the record to inflight
- `task.progress` marks inflight work as running
- `task.result` and `task.error` become terminal dispatch records
- stale dispatches are expired into timeout errors
- duplicate pending dispatches are removed by `idempotencyKey`
- superseded failed dispatches are removed when a newer retry succeeds or is re-accepted

## Storage Model

The protocol is now persisted across the main project model, not only in ephemeral runtime memory.

### TypeScript Domain

Files:

- `packages/domain/src/execution.ts`
- `packages/domain/src/message.ts`
- `packages/domain/src/project.ts`

Current storage:

- `ExecutionResult.runtimeEvents`
- `ExecutionResult.primaryRuntimeEvent`
- `Message.runtimeEvent`
- `RuntimeState.runtimeEvents`
- structured runtime dispatch records in `RuntimeState`

### Swift Domain

Files:

- `Multi-Agent-Flow/Sources/Services/OpenClawService.swift`
- `Multi-Agent-Flow/Sources/Models/Message.swift`
- `Multi-Agent-Flow/Sources/Models/MAProject.swift`

Current storage:

- `ExecutionResult.runtimeEvents`
- `ExecutionResult.primaryRuntimeEvent`
- `Message.runtimeEvent`
- `RuntimeState.runtimeEvents`
- `RuntimeState.dispatchQueue`
- `RuntimeState.inflightDispatches`
- `RuntimeState.completedDispatches`
- `RuntimeState.failedDispatches`

## Read Priority And Compatibility Strategy

The migration strategy is event-first with compatibility fallbacks.

Current priority order for new code:

1. `runtimeEvent` / `runtimeEvents`
2. derived helpers such as `summaryText`, `previewText`, `renderedOutputText`, `inferredRole`, `inferredKind`
3. legacy metadata and raw text fields

Compatibility fields that still exist:

- `Message.content`
- `Message.metadata["role"]`
- `Message.metadata["kind"]`
- `Message.metadata["agentName"]`
- `Message.metadata["outputType"]`
- `ExecutionResult.output`
- `RuntimeState.messageQueue`

### Current Derived Helpers

The protocol already drives derived helpers in Swift.

Examples:

- `OpenClawRuntimeEvent.summaryText`
- `OpenClawRuntimeEvent.summaryLine`
- `OpenClawRuntimeEvent.participantsText`
- `OpenClawRuntimeEvent.refsText`
- `ExecutionResult.summaryText`
- `ExecutionResult.previewText`
- `ExecutionResult.renderedOutputText`
- `ExecutionResult.runtimeEventsText`
- `Message.inferredRole`
- `Message.inferredKind`
- `Message.inferredAgentName`
- `Message.inferredOutputType`

## UI And Analytics Consumption

The protocol is no longer only an execution-layer detail. It now feeds UI and analytics directly.

### UI Surfaces

Current event-first UI reads include:

- execution result summary rendering
- execution result runtime event cards
- workbench message role/kind inference
- task dashboard trace summaries
- task dashboard trace detail event sections

### Analytics Persistence

File:

- `Multi-Agent-Flow/Sources/Services/OpsAnalyticsStore.swift`

Current persisted protocol-derived trace attributes:

- `preview_text`
- `output_text`
- `events`
- `protocol_event_count`
- `protocol_ref_count`
- `protocol_event_types`

Current behavior:

- root execution spans store protocol-derived preview/output/event summaries
- trace summary rows fall back to `events` when `preview_text` is absent
- trace detail falls back to `events` when `preview_text` and `output_text` are absent

This keeps legacy trace views functional while making protocol events the preferred observability source.

## Validation And Acceptance

Run the end-to-end acceptance command from the repository root:

```bash
npm run validate:openclaw-runtime
```

Current coverage includes:

- TypeScript `.maoproj` compatibility validation for runtime protocol fixtures
- Swift acceptance for runtime event persistence on `ExecutionResult`
- Swift acceptance for trace/detail fallback when only `events` are present
- Swift acceptance for external OpenClaw session backup ingestion into trace detail

Primary validation assets:

- `scripts/validate-openclaw-runtime.sh`
- `packages/core/fixtures/compat/runtime-protocol.maoproj`
- `packages/core/scripts/validate-maoproj-compat.ts`
- `Multi-Agent-FlowTests/OpsAnalyticsQueryTests.swift`

## Current Status

As of the current codebase, the protocol is already landed across the main runtime stack.

Landed:

- shared TS schema and event factory
- shared Swift runtime model
- workflow hot-path event emission
- Electron direct execution bridge emission
- project/runtime state storage
- runtime mailbox buckets and timeout synthesis
- event-first UI helpers
- analytics persistence and trace fallback
- end-to-end automated acceptance

Still additive or reserved:

- richer approval lifecycle handling around `task.approved`
- broader production use of `session.sync`
- more explicit protocol-violation enforcement metrics
- optional export/import tooling for full protocol traces

## Rules For Future Changes

- Do not add new machine-readable workflow logic by parsing `Message.content`
- Do not use transcript visibility or chat history polling as proof of hot-path delivery
- Prefer a new payload key or ref over embedding large free-form text
- Keep payload values compact, normalized, and stable
- When adding a new UI or analytics surface, consume runtime-event-derived helpers first
- Only use legacy text or metadata as a fallback
- Treat `gateway_agent` as the default hot-path transport unless the use case is explicitly transcript/session oriented
