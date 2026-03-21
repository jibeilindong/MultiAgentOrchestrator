# OpenClaw Connection Layer Rearchitecture Plan

Last updated: 2026-03-22
Status: Execution started

## Current Execution Status

Completed:

- unified `connectionState`, `lastProbeReport`, and structured `layers`
- desktop runtime readiness, recovery plan, recovery report, and recovery audit
- upgraded `retry guidance` into a budgeted and cooldown-aware `controlled retry policy`
- exposed a guarded `smart retry` action in the desktop UI to avoid unbounded recovery loops
- reliable disconnect propagation from gateway drop events into published app state
- added a structured `session lifecycle` snapshot so project state can distinguish `prepared`, `pending_sync`, and `synced`
- started separating `connect` from `sync current session` in the Swift entry layer so a successful connect no longer implies runtime write-back
- reordered Swift `connect` so probing completes before session preparation begins; failed connections no longer pre-create a prepared session lifecycle or leave attach-side effects behind
- changed `workflow apply` to a local mirror-apply step only; live runtime write-back and allow-list sync now flow through explicit `sync current session`
- split the Workflow Editor toolbar into explicit `Apply Mirror` and `Sync Session` actions, with pending-sync status surfaced in the editor chrome
- upgraded the Swift container probe to the same CLI + gateway contract, and started reusing `openclaw.json` gateway parsing across local and container deployments
- upgraded the Electron container probe to the same CLI + gateway contract, and removed the special-case assumption that container mode can skip gateway handshake
- added a testable Electron `openclaw-discovery` helper so container mode now prefers in-container root discovery before falling back to explicit candidates, reducing reliance on `workspaceMountPath` guesswork
- Electron probe roots, inventory discovery, and governance path resolution now begin converging on one `resolveOpenClawDiscoveryPaths` entry point, reducing duplicated root/config parsing inside `main.ts`

In progress:

- pushing the canonical connection contract further down into the Electron/Swift discovery and probe entry points so local, container, and remote share one definition of "connected" and one inventory source of truth
- continuing to split read-only probe/attach from session preparation and runtime commit, while aligning the cleanup semantics for session-preparation failures
- continuing to unify container and remote inventory discovery around one source of truth and one runtime handshake path, with discovery helpers being pulled into reusable contracts

## Purpose

This document defines the next-generation OpenClaw connection layer for Multi-Agent-Flow.

The goal is not only to fix current connection bugs, but to turn OpenClaw into a formal runtime backend that can support:

- reliable connection semantics
- high-speed workflow execution
- workbench conversation flows
- offline-friendly workflow design
- consistent local, container, and remote behavior
- observable degradation and recovery

## Why This Redesign Is Needed

The current implementation mixes too many responsibilities inside the notion of "connect":

- deployment discovery
- health probing
- authentication
- agent inventory loading
- project mirror staging
- runtime session attachment
- execution transport selection
- UI status publication

This creates five structural failure classes already visible in the codebase:

1. connecting can mutate live OpenClaw state before health is verified
2. Swift and Electron disagree on what "connected" means
3. container discovery does not always use real container state
4. CLI probing can block or hang
5. gateway disconnects do not reliably flow back to published app state

## Product Goals

The redesigned connection layer should ensure that:

1. connection is a read-only action by default
2. project attachment and runtime sync are explicit lifecycle steps
3. workflow hot path continues to prefer `gateway_agent`
4. workbench conversation continues to prefer `gateway_chat`
5. CLI becomes a controlled fallback instead of an implicit default
6. offline workflow design remains possible even when runtime is unavailable
7. users can distinguish `ready`, `degraded`, `blocked`, and `detached` states

## Architectural Principles

### 1. One connection contract

All app surfaces must use the same probe semantics and the same source of truth.

### 2. Capability-first runtime state

The system should not rely on a single `isConnected` boolean. It should expose capability-oriented state:

- CLI available
- gateway reachable
- gateway authenticated
- agent listing available
- gateway agent transport available
- gateway chat transport available
- project attachment supported

### 3. Structured transport policy

Transport selection must be derived from runtime capabilities and task shape, not from UI-specific logic branches.

### 4. Read-only connect, explicit commit

Connecting to OpenClaw must not write to the live runtime. Runtime mutation should happen only through explicit attach/sync steps.

### 5. Design-time and runtime-time separation

Workflow construction must remain available offline. Runtime validation should enrich the design experience instead of blocking it.

## Target Architecture

The new connection layer is split into four layers.

### 1. Discovery Layer

Responsibilities:

- locate OpenClaw deployment
- identify deployment kind
- discover runtime root and config path
- gather raw inventory candidates

This layer is read-only.

### 2. Probe Layer

Responsibilities:

- verify CLI usability
- verify gateway handshake
- verify auth
- verify agent listing
- verify session/history support
- publish a canonical capability report

Output:

- `OpenClawProbeReport`

### 3. Runtime Attachment Layer

Responsibilities:

- create attachment context for a project
- load baseline snapshot
- prepare mirror workspace
- compute safe diff
- gate commit into live runtime

This layer owns:

- attach
- sync
- detach
- restore

### 4. Execution Layer

Responsibilities:

- route workbench execution
- route workflow hot path
- reuse gateway sessions
- manage CLI fallback
- publish transport metrics

This layer consumes capability state, not raw config guesses.

## Canonical Connection State

The app should move from a boolean connection model to a structured runtime state:

```text
OpenClawConnectionState
  phase:
    idle | discovering | probed | ready | degraded | detached | failed
  deploymentKind:
    local | container | remoteServer
  capabilities:
    cliAvailable
    gatewayReachable
    gatewayAuthenticated
    agentListingAvailable
    sessionHistoryAvailable
    gatewayAgentAvailable
    gatewayChatAvailable
    projectAttachmentSupported
  health:
    lastProbeAt
    lastHeartbeatAt
    latencyMs
    degradationReason
  inventory:
    agents
    sourceOfTruth
```

## Canonical Probe Result

All deployment modes should converge on one report shape:

```text
OpenClawProbeReport
  success
  deploymentKind
  endpoint
  authMode
  capabilities
  health
  agents
  warnings
  errors
  sourceOfTruth
  observedDefaultTransports
```

This report becomes the only source used by:

- AppState
- workbench eligibility checks
- workflow publish eligibility checks
- benchmark transport availability
- UI connection badges
- Ops Center runtime diagnostics

## Transport Policy

The transport policy must be explicit and capability-driven.

### Preferred paths

- `workflow-*` sessions prefer `gateway_agent`
- `workbench-*` sessions prefer `gateway_chat`
- transcript-oriented sessions prefer `gateway_chat`
- CLI is a fallback only for local/container deployments

### Routing rules

1. If `gateway_agent` capability exists and the task is workflow hot path, use `gateway_agent`.
2. If `gateway_chat` capability exists and the task is conversation/session oriented, use `gateway_chat`.
3. If gateway transport fails in local/container mode and fallback is allowed, degrade to CLI.
4. If gateway transport fails in remote mode, do not silently remap the request to another contract.

## Workflow Design Feasibility

Workflow design must not require a live OpenClaw runtime.

The system should distinguish:

- structural validity
- runtime readiness
- deployment compatibility

Recommended workflow states:

- `draft`
- `structurally_valid`
- `runtime_ready`
- `runtime_degraded`
- `runtime_blocked`

The editor should remain usable offline, while runtime validation uses the latest probe report and inventory snapshot when available.

## Container and Remote Consistency

Deployment behavior should be implemented through adapters:

```text
OpenClawDeploymentAdapter
  discover()
  probe()
  fetchInventory()
  fetchRuntimeSnapshot()
  attachProject()
  commitMirror()
  executeGatewayAgent()
  executeGatewayChat()
  executeCLI()
```

Concrete adapters:

- `LocalOpenClawAdapter`
- `ContainerOpenClawAdapter`
- `RemoteGatewayAdapter`

This removes duplicated and conflicting connection logic between Swift and Electron.

## Observability Model

Connection state should emit structured runtime events, not only logs.

Recommended event types:

- `connection.discovery_started`
- `connection.discovery_completed`
- `connection.probe_started`
- `connection.probe_succeeded`
- `connection.probe_failed`
- `connection.degraded`
- `connection.recovered`
- `connection.attached`
- `connection.sync_started`
- `connection.sync_completed`
- `connection.sync_rejected`
- `connection.detached`

These events should feed:

- runtime state
- Ops Center
- transport benchmark reporting
- support diagnostics

## Execution Plan

### Phase 1. Stabilize connection truth

- add a canonical connection state model
- propagate gateway disconnects back to published app state
- make probe semantics consistent across app surfaces
- remove blocking CLI probe patterns and enforce timeouts
- stop mutating live runtime during plain connection checks

### Phase 2. Unify transport policy

- move transport routing behind capability-based policy
- align benchmark, workbench, and workflow execution with the same routing contract
- make fallback policy explicit and observable

### Phase 3. Separate design-time and runtime-time

- add workflow runtime readiness reporting
- introduce inventory snapshots with freshness metadata
- keep the editor usable offline

### Phase 4. Introduce deployment adapters

- define local/container/remote adapters
- remove duplicated connection logic
- unify inventory and runtime snapshot loading

### Phase 5. Formalize runtime attachment lifecycle

- split probe, attach, sync, detach
- make baseline snapshots and mirror commits explicit
- add safe diff and conflict handling before sync

## Acceptance Criteria

The redesign is successful when:

1. the app no longer reports false connected state after gateway liveness is lost
2. connect does not mutate live OpenClaw runtime by default
3. local, container, and remote deployments produce one probe contract
4. workflow hot path remains on `gateway_agent` when capability is available
5. workbench remains session-friendly without forcing CLI fallback semantics
6. offline workflow editing remains possible
7. users can clearly tell whether runtime is ready, degraded, or blocked

## Implementation Status

Execution has started.

Initial implementation slice:

- document the target architecture
- begin Phase 1 by wiring gateway disconnect signals back into published app state
- change `connect`/`beginSession` into a read-only attach flow so project mirror staging no longer writes into live OpenClaw runtime by default
- add initial persisted `ConnectionState` / `ProbeReport` snapshots so probe outcomes, capabilities, and degraded states have a formal compatibility layer
- start converging desktop `connect` / `detect` onto one shared `probe` contract and carry `ConnectionState` / `ProbeReport` from the Electron main process into persisted project snapshots
- prefer container-side `openclaw config file` discovery for agent inventory so container mode no longer depends only on host mount-path guesses
- move the Swift probe / CLI and container snapshot archive hot paths onto a safe process executor with concurrent stdout/stderr draining and timeout-based termination to avoid pipe-buffer deadlocks
- upgrade desktop gateway probing from HTTP `fetch()` to websocket upgrade plus `connect.challenge`, `connect` RPC validation, and persisted device-identity signing so local and remote modes continue converging toward Swift gateway semantics
- extract a pure desktop `connection-state` helper and add regression coverage for `ready / degraded / detached / failed`, turning the probe state machine into a testable contract instead of hidden implementation detail
- extend the desktop `connection-state` helper with explicit `transport / authentication / session / inventory` layer assessment and cover local, container, remote, and total-failure regressions
- promote `transport / authentication / session / inventory` into a structured `ProbeReport.layers` field, reuse shared result builders for Electron `connect` / `detect`, and add backward-compatible `layers` decoding for persisted Swift snapshots
- add a desktop runtime-readiness helper that feeds those layers into the OpenClaw inspector, Operations dashboard, and live workflow preflight, so degraded `transport / authentication / session` now blocks high-speed execution while degraded inventory remains a recoverable advisory
- make launch verification and approval-driven downstream live continuation reuse the same readiness gating, so blocked runtime states no longer silently fall back to synthetic execution and instead surface explicit verification / workbench failures
- extend the readiness helper with structured recovery actions so the diagnostics panel can directly trigger `Connect` / `Detect agents` and explicitly point users at host, container, or credential fixes that still require manual intervention
- add a semi-automatic desktop recovery plan that safely chains `Connect -> Detect agents` when the runtime state allows it, then pauses with explicit hand-off guidance whenever the remaining fix still requires manual configuration changes
- record a before/after desktop recovery report so the UI can show whether the recovery plan actually improved readiness and probe-layer state instead of merely reporting that recovery steps were attempted
- persist recovery reports inside `ProjectOpenClawSnapshot` and surface a recent recovery list in the desktop UI, giving later cross-session recovery auditing and retry automation a durable state foundation
- upgrade that persisted history into a desktop recovery audit view with aggregate completed / partial / manual / failed / improved / reached-ready metrics plus a readable timeline of steps, manual follow-up, and findings
- start turning that audit plus current readiness into explicit retry guidance (`auto_retry / manual_first / observe / not_needed`), moving the connection layer from merely recoverable toward policy-driven recovery decisions
