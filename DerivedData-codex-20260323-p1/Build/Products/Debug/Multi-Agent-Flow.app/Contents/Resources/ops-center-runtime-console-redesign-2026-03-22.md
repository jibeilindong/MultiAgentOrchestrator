# Ops Center Runtime Console Redesign

Last updated: 2026-03-22
Status: Execution started

## Purpose

This document captures the new dashboard direction for Multi-Agent-Flow and acts as the source reference for future README, implementation notes, and onboarding materials.

The redesign replaces the current long-scroll analytics dashboard with a workflow-oriented runtime console that is optimized for:

- immediate operational awareness
- workflow debugging
- cross-source investigation
- session-level traceability
- long-term historical diagnosis

## Product Goal

The dashboard should reflect workflow execution in a way that is:

- intuitive
- detailed
- comprehensive
- as close to real time as practical
- smooth to load and navigate
- useful for debugging, not just reporting

## Core Judgment

The current filesystem and runtime architecture already contain enough structured data for a much stronger dashboard:

- managed project root
- collaboration thread files
- runtime session files
- execution results and logs
- analytics SQLite
- projection JSON files
- workflow design and derived documents

The current dashboard underuses these assets because it is still organized primarily as an analytics page instead of an investigation console.

## New Information Architecture

The new Ops Center is rebuilt around four primary surfaces:

1. `Live Run`
   Shows what is running now, where flow is blocked, and which errors need attention first.

2. `Sessions`
   Elevates session as a first-class investigation object with dispatch, event, receipt, and linked context visibility.

3. `Workflow Map`
   Overlays runtime state back onto workflow structure so users can debug the workflow itself instead of only reading lists.

4. `History`
   Preserves trend, anomaly, and governance analysis as a supporting layer rather than the main entry path.

## Filesystem Alignment

The redesign intentionally builds on the current managed project filesystem instead of replacing it.

Primary storage surfaces already available:

```text
Projects/<project-id>/
  design/
  collaboration/
  runtime/
  tasks/
  execution/
  openclaw/
  analytics/
  indexes/
```

Important runtime-aligned assets:

- `collaboration/workbench/threads/<thread-id>/thread.json`
- `collaboration/workbench/threads/<thread-id>/dialog.ndjson`
- `runtime/sessions/<session-id>/session.json`
- `runtime/sessions/<session-id>/dispatches.ndjson`
- `runtime/sessions/<session-id>/events.ndjson`
- `runtime/sessions/<session-id>/receipts.ndjson`
- `execution/results.ndjson`
- `execution/logs.ndjson`
- `analytics/analytics.sqlite`
- `analytics/projections/*.json`
- `indexes/workflows.json`
- `indexes/nodes.json`
- `indexes/threads.json`
- `indexes/sessions.json`

## Dashboard Data Layers

The new dashboard uses three distinct read layers:

### 1. Live memory layer

Used for immediate rendering:

- `AppState`
- `RuntimeState`
- `OpenClawService`
- in-memory tasks, messages, execution results, and logs

### 2. Projection and index layer

Used for fast dashboard startup and quick list rendering:

- `indexes/*.json`
- `analytics/projections/*.json`

### 3. Historical analytics layer

Used for trend and long-range analysis:

- `analytics.sqlite`

## New Core Runtime Objects

The redesign promotes the following runtime objects to first-class dashboard concepts:

- workflow
- node
- edge
- session
- thread
- dispatch
- runtime event
- receipt
- anomaly
- tool
- cron run

The dashboard should no longer force the user to begin investigation from aggregated cards only.

## Required New Projections

The following projection files should be added to support the new console:

- `analytics/projections/live-run.json`
- `analytics/projections/workflow-health.json`
- `analytics/projections/sessions.json`
- `analytics/projections/nodes-runtime.json`

Recommended supporting summaries:

- `runtime/sessions/<session-id>/artifacts/index.json`
- `collaboration/workbench/threads/<thread-id>/investigation.json`

## UX Principles

1. The default page must answer "what is happening right now?"
2. Every red state must lead to a concrete cause within one or two interactions.
3. Workflow runtime state must be visible on workflow structure, not only in tables.
4. Session and thread must be linked, not treated as separate silos.
5. Historical analytics must remain available but should not dominate the default debugging experience.
6. Cold start should prefer projections and indexes over full NDJSON scanning.

## Execution Strategy

This redesign is intentionally not incremental in product shape.

Implementation strategy:

- freeze the old dashboard as legacy
- build a new `OpsCenter` module beside it
- switch navigation entry points to the new container
- keep the old analytics implementation available only as fallback reference during migration

## Execution Plan

### Phase 1. New shell and navigation

- create a new `OpsCenterDashboardView`
- add page model and runtime-focused dashboard models
- add `Live Run`, `Sessions`, `Workflow Map`, and `History` pages
- switch main app and workbench entry points to the new container

### Phase 2. Session-first investigation

- define unified investigation handles
- add session summaries and session timeline rendering
- link session to workflow, thread, tasks, and messages

### Phase 3. Workflow runtime map

- project node and edge runtime state onto workflow structure
- expose layers for state, latency, failures, routing, approvals, and file pressure

### Phase 4. Projection expansion

- generate new live-run and workflow-health projections
- generate session and node runtime projection summaries
- optimize startup and navigation around indexes and projections

### Phase 5. Unified investigation panel

- replace fragmented trace/anomaly/tool/cron detail entry points
- route all deep links through one investigation model and container

### Phase 6. History condensation

- keep historical metrics and trends
- add top-level insights and recommended investigation targets
- keep history as decision support, not as the primary landing surface

## Acceptance Criteria

The redesign is successful when:

1. Opening the dashboard immediately reveals current workflow health and live execution posture.
2. A user can identify blocked nodes and failing paths directly from the default page.
3. A failed execution can be traced back to a session, workflow area, and related context quickly.
4. Session, thread, anomaly, and workflow investigations no longer feel disconnected.
5. Workflow debugging becomes structure-first rather than list-first.
6. Historical analysis remains available without slowing the live console experience.

## Implementation Status

Execution has started with:

- documentation landing in the repository
- a new Ops Center container replacing the old entry path
- first-pass `Live Run`, `Sessions`, `Workflow Map`, and `History` page scaffolds

