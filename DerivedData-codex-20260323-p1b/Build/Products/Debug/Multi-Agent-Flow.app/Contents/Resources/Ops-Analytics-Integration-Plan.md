# Ops Analytics Integration Plan

## Background

This project already has strong local project orchestration capabilities:

- project persistence
- workflow editing
- task management
- OpenClaw connection and agent import
- execution logs and execution results
- monitoring dashboard entry point

The external `oa-cli` project from `Agent_Exploration` focuses on a different but complementary layer:

- operational analytics for an AI agent team
- data collection from OpenClaw runtime artifacts
- lightweight tracing
- SQLite-backed metrics
- local dashboard views

The best long-term direction for `Multi-Agent-Flow` is not to embed the Python CLI as-is, but to build a native `Ops Analytics` subsystem inside the macOS app while keeping the design compatible with the useful parts of `oa-cli`.

## Design Goals

1. Build a native analytics layer inside the SwiftUI app.
2. Reuse existing project, execution, task, memory, and runtime state data.
3. Keep the architecture ready for future compatibility with `oa-cli` metrics and schema.
4. Upgrade the current monitoring dashboard from a runtime status page into an `Ops Center`.

## Integration Strategy

### Recommended approach

Use a hybrid integration model:

- native collection and presentation in Swift
- compatible metrics model inspired by `oa-cli`
- optional future import/export bridge to `oa-cli` data stores

### What we should not do first

- do not directly depend on the Python CLI for the main in-app experience
- do not require a local HTTP server as the primary dashboard
- do not tightly bind the product to `~/.openclaw` as the only source of truth

## Product Layers

### 1. Analytics domain layer

Introduce an `OpsAnalyticsService` that converts runtime state into structured analytics snapshots.

Primary data sources:

- `MAProject`
- `TaskManager`
- `OpenClawService.executionResults`
- `OpenClawService.executionLogs`
- `MAProject.runtimeState`
- `MAProject.memoryData`
- `OpenClawManager.activeAgents`

### 2. Metrics layer

Initial native metrics should cover:

- OpenClaw readiness
- workflow reliability
- agent engagement
- memory discipline
- error budget

### 3. Trace layer

Before introducing full OpenTelemetry-compatible persistence, expose a native trace summary view derived from execution results:

- recent execution attempts
- agent identity
- duration
- routing action
- output type
- preview text

### 4. Dashboard layer

Upgrade the current monitoring dashboard into an `Ops Center` with:

- overview cards
- goal health cards
- daily reliability trend
- per-agent health table
- recent trace summary

## Planned Compatibility With oa-cli

The current native implementation should conceptually align with the following `oa-cli` areas:

- `goal_metrics`
- `cron_runs`
- `daily_agent_activity`
- `spans`

We are not persisting these tables yet in phase 1, but the in-app models should map naturally to them later.

## Phase Plan

### Phase 1

Native in-app analytics, no external dependency:

- add `OpsAnalyticsService`
- compute structured ops metrics from current project state
- expose agent health and trace summaries
- enrich the monitoring dashboard
- document the compatibility direction

### Phase 2

Introduce persistent analytics storage:

- add SQLite-backed analytics store
- align tables with `oa-cli` schema where practical
- collect historical project metrics over time
- support analytics export

### Phase 3

Deep interoperability:

- import existing `oa-cli` projects
- merge OpenClaw external artifacts with in-app telemetry
- add richer span tree exploration
- add goal template system

## Phase 1 Scope Implemented In This Branch

This branch focuses on the first meaningful native step:

- project documentation for the integration direction
- a reusable `OpsAnalyticsService`
- goal-oriented operational metrics
- agent health summaries
- trace summaries
- upgraded monitoring dashboard sections

## Future Extension Ideas

- OpenClaw cron reliability parsing
- project/global scope switch
- workflow-level SLOs
- failure heatmaps by workflow node
- span waterfall view
- analytics export to SQLite in `oa-cli`-compatible shape
