# OpenClaw Agent Runtime Protocol

## Goal

OpenClaw agent-to-agent communication inside Multi-Agent-Orchestrator should use structured runtime events instead of natural-language messages.

This protocol is the canonical internal transport model for:

- agent dispatch
- execution progress
- result emission
- routing decisions
- execution failures
- approval checkpoints
- session synchronization

Natural-language `Message.content` remains available for user-facing UX and backward compatibility, but it is no longer the primary machine-readable carrier for agent coordination.

## Version

- protocol version: `openclaw.runtime.v1`

## Design Principles

- Structured first: machine communication must be parsed from typed event fields, not free-form text.
- Compact payloads: payload fields should carry normalized keys and short values.
- Event append-only: runtime traces should be accumulated as event sequences.
- Compatibility-friendly: legacy message metadata and output text remain readable during migration.
- Observability-ready: the same protocol should power execution, analytics, and UI summaries.

## Event Model

Canonical event model:

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

## Event Types

Supported event types in `openclaw.runtime.v1`:

- `task.dispatch`
- `task.accepted`
- `task.progress`
- `task.result`
- `task.route`
- `task.error`
- `task.approval_required`
- `task.approved`
- `session.sync`

## Actor Model

Actors are encoded as:

- `kind`: `agent | orchestrator | system | user`
- `agentId`
- `agentName`

Rules:

- `source` identifies who produced the event.
- `target` identifies the intended receiver or execution subject.
- User-originated workbench prompts should use `source.kind = user`.
- Agent execution outputs should usually use `source.kind = agent`.

## Transport Model

Transport kinds:

- `cli`
- `gateway_agent`
- `gateway_chat`
- `runtime_channel`
- `unknown`

The transport block records how a task moved through OpenClaw, not how it is rendered in the UI.

## Payload Conventions

Payload is a string map for compactness and compatibility.

Preferred keys:

- `summary`
- `reason`
- `action`
- `intent`
- `outputType`
- `expectedOutput`

Guidelines:

- `summary` should be the primary short machine-facing summary.
- `reason` should explain routing or failure decisions.
- `action` should encode route/control actions when relevant.
- `outputType` should align with execution result output typing.

## Refs

`refs` should be used when the event points at artifacts or externalized data instead of embedding large content.

Supported reference kinds include:

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

## Current Implementation Mapping

### TypeScript

Shared protocol types live in:

- `packages/domain/src/openclaw-runtime.ts`
- `packages/domain/src/openclaw-runtime-factory.ts`

Project and execution state models expose runtime events through:

- `packages/domain/src/execution.ts`
- `packages/domain/src/message.ts`
- `packages/domain/src/project.ts`

### Swift

Swift runtime protocol types live in:

- `Multi-Agent-Flow/Sources/Models/OpenClawRuntimeEvent.swift`

Execution and project state integration lives in:

- `Multi-Agent-Flow/Sources/Services/OpenClawService.swift`
- `Multi-Agent-Flow/Sources/Models/Message.swift`
- `Multi-Agent-Flow/Sources/Models/MAProject.swift`
- `Multi-Agent-Flow/Sources/Services/AppState.swift`

## Runtime Emission Rules

Current OpenClaw workflow execution emits a standard sequence:

1. `task.dispatch`
2. `task.result` or `task.error`
3. `task.route` when routing is produced

Workbench and transcript synchronization also generate protocol-compatible events so that UI state and execution state share one event vocabulary.

## Compatibility Strategy

The migration strategy is incremental:

- `Message.runtimeEvent` carries the canonical structured event.
- `Message.content` remains for display and compatibility.
- `metadata["role"]`, `metadata["kind"]`, `metadata["agentName"]`, and `metadata["outputType"]` remain as legacy fallbacks.
- `ExecutionResult.output` remains available, but protocol-derived summaries are preferred.

Priority order for new code:

1. `runtimeEvent` / `runtimeEvents`
2. derived helpers such as `summaryText`, `previewText`, `inferredRole`
3. legacy metadata or raw text

## UI / Analytics Consumption

Protocol-derived summaries are now used by:

- workbench message rendering
- message list role/kind inference
- execution result summary rendering
- task dashboard recent results
- analytics span persistence
- trace detail output and events fallback

Analytics persistence stores protocol-derived:

- `preview_text`
- `output_text`
- `events`

This allows old views to stay functional while gradually becoming event-first.

## Implementation Rules For Future Changes

- Do not introduce new machine-readable coordination logic by parsing `Message.content`.
- Prefer adding a new `payload` key or `ref` over embedding large free-form text.
- Keep event payload values concise and stable.
- When adding a new UI or analytics surface, consume `runtimeEvent`-derived helpers first.
- Only use legacy message metadata as a fallback.

## Migration Status

Current status:

- protocol types: landed
- execution emission: landed
- project/runtime state storage: landed
- analytics persistence: landed
- major UI read paths: landed
- compatibility bridge: active

Remaining follow-up work is mostly additive:

- richer event timeline browsing
- more explicit `refs` visualization
- optional export/import tooling around protocol traces
