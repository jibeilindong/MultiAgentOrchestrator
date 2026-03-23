# Project Filesystem Rearchitecture Execution Plan

Last updated: 2026-03-21
Status: In progress

## Progress Update

Completed:

- managed project root, manifest, and snapshot bridge
- design-state split persistence and assembled-project loading
- node-local `agent.json`, `binding.json`, `SOUL.md`
- node-local OpenClaw workspace scaffold documents and state files
- remaining runtime/UI call sites no longer expose legacy workspace roots as the default path surface
- node-local OpenClaw `skills/` and `memory/` switched to full mirrored storage inside the managed project
- node/workbench read-side resolution now prefers node-local managed OpenClaw workspace artifacts
- runtime guardrails, path resolution, and dashboard file-root aggregation now consume project-managed/node-local workspaces first
- workflow editor collection snapshots and skills management now resolve agent files from the unified managed-workspace path surface
- workflow apply no longer back-propagates session mirror paths into project-owned agent state
- OpenClaw agent import now repoints imported `SOUL.md`, `skills/`, and workspace metadata to the managed project copy
- imported OpenClaw `private/` state is no longer polluted by copying the entire external agent root
- imported OpenClaw agents now establish `lastImportedSoul*` baselines from the managed project copy
- session mirror/backup resolution now prefers managed project session roots before persisted legacy path snapshots
- collaboration/runtime/execution split persistence
- tasks/workspace index consolidation under managed project root
- OpenClaw session root migration to managed project root
- analytics sqlite migration to managed project root
- analytics projection files under `analytics/projections`
- duplicate node-agent binding validation and regression coverage
- legacy workspace/OpenClaw/analytics path migration regression coverage
- workspace index hydration now resolves workspace roots from explicit project context

Remaining:

 - continue auditing the remaining import/export and session-sync flows for any residual external-path-first assumptions
 - decide whether the unused OpenClaw import loader should be repointed to the same workspace-resolution helper surface or removed entirely

## Goal

Reshape the project file system without changing existing product semantics.

The redesign must preserve:

- `.maoproj` compatibility
- existing Swift and TypeScript `MAProject` contract
- workflow editor behavior
- workbench conversation behavior
- dashboard analytics behavior
- current OpenClaw integration semantics

The new file system acts as an internal storage layer. The existing `.maoproj` file remains the external compatibility snapshot.

## Compatibility Rules

The following rules are non-negotiable during implementation:

1. `MAProject` remains the shared assembly model.
2. `.maoproj` remains readable and writable.
3. `node = agent = 1:1 execution unit`.
4. UI and workflow behavior are preserved.
5. OpenClaw backup, mirror, import, and analytics flows must keep working while storage is reshaped underneath.

## Current Cross-Feature Constraints

### Project management

- New/open/save/save-as/autosave/backup must continue to work.
- Existing document storage under `Documents/Multi-Agent-Flow` remains the visible project surface.

### Workflow editor

- Nodes, edges, boundaries, subflows, launch verification, and canvas editing semantics stay unchanged.
- Node display remains node-owned, not agent-owned.

### Node and agent identity

- A single node owns exactly one agent instance.
- Agent instances are not shared across nodes.
- Any future template reuse must happen through presets, not shared live agents.

### OpenClaw integration

- The project must continue to track OpenClaw workspace documents and binding paths.
- Existing backup and mirror flows remain operational during migration.

### Workbench and messaging

- User-visible workbench dialog and system/runtime messages continue to assemble into the current message experience.
- Approval flows remain intact.

### Runtime and monitoring

- Runtime dispatch state, execution results, execution logs, and analytics projections remain queryable.
- `analytics.sqlite` remains the dashboard query layer.

### Cross-platform migration

- The internal redesign must not block the Electron migration path.
- The storage layer should be able to reconstruct a valid `.maoproj` snapshot at any time.

## Target Internal Storage

Each project gets an internal managed root:

```text
Application Support/Multi-Agent-Flow/Projects/<project-id>/
  manifest.json
  snapshot/
    current.maoproj
    autosave.maoproj
  design/
    project.json
    workflows/
      <workflow-id>/
        workflow.json
        nodes/
          <node-id>/
            node.json
            agent.json
            openclaw/
              binding.json
              workspace/
                AGENTS.md
                SOUL.md
                USER.md
                IDENTITY.md
                TOOLS.md
                HEARTBEAT.md
                BOOTSTRAP.md
                MEMORY.md
                memory/
                  workspace/
                  backup/
                skills/
              mirror/
                source-map.json
                sync-baseline.json
              state/
                protocol-memory.json
                import-record.json
        edges/
          <edge-id>.json
        boundaries/
          <boundary-id>.json
        derived/
          communication-matrix.json
          file-scope-map.json
          launch-report.json
  collaboration/
    workbench/
      threads/
        <thread-id>/
          thread.json
          dialog.ndjson
          context.json
          attachments/
    communications/
      messages.ndjson
      approvals.ndjson
  runtime/
    sessions/
      <session-id>/
        session.json
        dispatches.ndjson
        events.ndjson
        receipts.ndjson
        artifacts/
    state/
      runtime-state.json
      queue.json
  tasks/
    tasks.json
    workspace-index.json
  execution/
    results.ndjson
    logs.ndjson
  openclaw/
    session/
      backup/
      mirror/
      agents/
  analytics/
    analytics.sqlite
    projections/
      overview.json
      traces.json
      anomalies.json
  indexes/
    workflows.json
    nodes.json
    threads.json
    sessions.json
```

## Phases

### Phase 1: Internal project root, manifest, and snapshot bridge

Deliverables:

- internal project root directory
- `manifest.json`
- `snapshot/current.maoproj`
- automatic synchronization on open/save
- automatic cleanup on delete

Rules:

- no UI semantics change
- no workflow semantics change
- no OpenClaw path migration yet
- `.maoproj` remains the public save format

### Phase 2: Design-state extraction

Deliverables:

- `design/project.json`
- workflow, node, edge, boundary split files
- node-local `agent.json`
- node-local OpenClaw workspace mirror
- mirrored `skills/`
- mirrored `memory/workspace/` and `memory/backup/`

Rules:

- design files become the primary stable source
- `.maoproj` becomes an assembled compatibility snapshot

### Phase 3: Collaboration-state and runtime-state extraction

Deliverables:

- workbench thread files
- communication message logs
- runtime session files
- execution results/log split persistence

Rules:

- no change to current assembled `messages`, `runtimeState`, and `executionResults` APIs

### Phase 4: Task, OpenClaw, and analytics consolidation

Deliverables:

- task/workspace files moved under managed project root
- OpenClaw session root unified under the managed project root
- analytics path unified under the managed project root

Rules:

- existing behavior preserved
- legacy paths migrated conservatively

## Execution Order

1. Add a managed project root under Application Support.
2. Add manifest and compatibility snapshot persistence.
3. Sync internal storage when saving or opening a `.maoproj`.
4. Add tests for scaffold creation and snapshot round-trip.
5. Move stable design data into split files.
6. Move collaboration and runtime data into append-friendly files.
7. Consolidate task/OpenClaw/analytics roots.

## Primary Risks

### Snapshot drift

Risk:

- internal files and `.maoproj` diverge

Mitigation:

- all save/open paths go through one storage bridge
- manifest tracks revision and snapshot timestamps

### OpenClaw path breakage

Risk:

- backup/mirror/import flows break during storage migration

Mitigation:

- keep current OpenClaw roots unchanged until consolidation phase
- only add managed project scaffolding first

### UI regression

Risk:

- existing Swift or Electron code expects the monolithic project shape

Mitigation:

- continue assembling `MAProject`
- do not change UI-facing APIs in phase 1

## Acceptance Criteria

1. Opening an existing `.maoproj` creates a managed internal project scaffold.
2. Saving a project updates both the visible `.maoproj` and the internal snapshot.
3. Deleting a project removes its managed internal root.
4. The managed root contains `manifest.json` and `snapshot/current.maoproj`.
5. Existing project open/save behavior remains unchanged from the user perspective.
