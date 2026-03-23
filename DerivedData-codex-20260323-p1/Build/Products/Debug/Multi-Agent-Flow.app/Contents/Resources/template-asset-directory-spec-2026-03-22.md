# Agent Template Asset Directory Specification

Last updated: 2026-03-22
Status: Proposed

## Purpose

This document defines the standard directory layout and file responsibilities for the new agent template asset system.

It is complementary to the template redesign documents:

- [template-filesystem-redesign-2026-03-21.md](/Users/chenrongze/Desktop/MultiAgentOrchestrator/MultiAgentOrchestrator/Multi-Agent-Flow/Documentation/template-filesystem-redesign-2026-03-21.md)
- [template-filesystem-redesign-zh-2026-03-22.md](/Users/chenrongze/Desktop/MultiAgentOrchestrator/MultiAgentOrchestrator/Multi-Agent-Flow/Documentation/template-filesystem-redesign-zh-2026-03-22.md)

This specification covers agent templates only. It does not define workflow templates.

## Design intent

Each template asset must be a complete, standard, filesystem-native agent package.

The editor should be able to copy a template asset and immediately obtain a standard agent that is directly usable if the user makes no edits.

Once copied into an agent:

- the resulting agent is independent
- the template no longer participates
- the template never becomes part of workflow persistence or runtime participation

## Root layout

Each template asset lives in its own root directory:

```text
<template-id>/
  template.json
  SOUL.md
  AGENTS.md
  IDENTITY.md
  USER.md
  TOOLS.md
  BOOTSTRAP.md
  HEARTBEAT.md
  MEMORY.md
  lineage.json
  revisions/
    <revision-id>.json
  extensions/
    README.md
    examples/
    tests/
    assets/
```

## File classes

Files are divided into three classes:

### 1. Core source files

- `template.json`
- `lineage.json`

These are the authoritative structured metadata and source-definition files.

### 2. Standard materialized companion files

- `SOUL.md`
- `AGENTS.md`
- `IDENTITY.md`
- `USER.md`
- `TOOLS.md`
- `BOOTSTRAP.md`
- `HEARTBEAT.md`
- `MEMORY.md`

These are the standard agent-facing documents produced from the template definition.

### 3. Extended development files

- `revisions/`
- `extensions/`

These support versioning, testing, examples, and secondary development.

## Required files

The following files are required for every non-draft template:

- `template.json`
- `SOUL.md`
- `AGENTS.md`
- `IDENTITY.md`
- `USER.md`
- `TOOLS.md`
- `BOOTSTRAP.md`
- `HEARTBEAT.md`
- `MEMORY.md`
- `lineage.json`

Draft-only exception:

- a draft template may temporarily contain incomplete content
- but the required file set must still exist
- drafts must be explicitly marked in `template.json`

## File definitions

## `template.json`

Purpose:

- canonical structured definition of the template asset

Minimum responsibilities:

- template ID
- revision
- display name
- category/family metadata
- structured SOUL source
- validation state
- draft/published status
- timestamps

Recommended fields:

```text
id
revision
displayName
meta
soulSpec
renderedSoulHash
validation
status
createdAt
updatedAt
```

Rules:

- this is the primary source file
- materialized markdown companions should be derivable from this file
- it must not contain workflow-binding information

## `lineage.json`

Purpose:

- record the origin and asset history of the template

Typical contents:

- source scope
- source template ID
- source revision
- import path
- import hash
- created reason

Rules:

- lineage belongs to the template asset, not to projects
- lineage must not point to workflow state

## `SOUL.md`

Purpose:

- the standard materialized SOUL document for the agent template

Expected content:

- role positioning
- mission
- core capabilities
- inputs
- responsibilities
- workflow
- outputs
- collaboration boundaries
- guardrails
- success criteria

Rules:

- it must be complete enough to serve as a directly usable agent SOUL
- it must not contain template-management leakage
- it should match the currently rendered result from `template.json`

## `AGENTS.md`

Purpose:

- top-level agent package summary and identity index

Recommended contents:

- template display name
- template ID
- revision
- agent package type
- brief summary of included documents

Rules:

- unlike project runtime `AGENTS.md`, this file should describe the template package rather than a workflow node binding
- it must not contain node IDs or workflow IDs

## `IDENTITY.md`

Purpose:

- concise statement of the agent's identity

Expected content:

- identity label
- role summary
- stable persona framing

Rules:

- should be short and stable
- should align with the identity information used in the template source

## `USER.md`

Purpose:

- record the human context for the agent instance or copied template package
- provide a standard place to learn about the person being helped over time

Expected content:

- a standard scaffold headed by `# USER.md - About Your Human`
- identity basics such as name, preferred form of address, pronouns, timezone, and notes
- an explicit `## Context` section for ongoing preferences, projects, friction points, humor, and collaboration cues

Rules:

- should describe the human, not the template itself
- should stay respectful and lightweight, never turning into a dossier
- for standard templates, the file should be present and contentful even before any real user data is filled in

## `TOOLS.md`

Purpose:

- define the capabilities/tool expectations of the standard agent package

Expected content:

- capability list
- expected tool profile
- environment assumptions if any

Rules:

- should not encode project-specific environment secrets
- should describe general capability requirements, not workflow-time bindings

## `BOOTSTRAP.md`

Purpose:

- define the startup context for the standard template package

Expected content:

- expected model profile or runtime profile if conceptually relevant
- initialization assumptions
- required preconditions before first use

Rules:

- should remain template-generic
- must not include machine-local or project-local absolute paths

## `HEARTBEAT.md`

Purpose:

- define stable operational status expectations for the template

Expected content:

- protocol or operating profile summary
- update semantics
- health/checking expectations

Rules:

- should describe steady-state operational characteristics
- should not act as a runtime log

## `MEMORY.md`

Purpose:

- define memory expectations and stable rules for the template package

Expected content:

- memory policy summary
- persistent principles
- stable operating rules

Rules:

- should contain reusable memory guidance
- should not embed project-specific historical memory

## Revision storage

## `revisions/<revision-id>.json`

Purpose:

- immutable snapshot of a previous template definition

Rules:

- revisions should be append-only
- current published state remains represented by `template.json`
- revision files should be machine-readable and deterministic

## Extensions directory

## `extensions/README.md`

Purpose:

- explain optional extended materials bundled with the template

## `extensions/examples/`

Purpose:

- sample prompts, sample outputs, or sample usage cases

## `extensions/tests/`

Purpose:

- validation fixtures or evaluation cases for template quality

## `extensions/assets/`

Purpose:

- non-core companion material needed for reuse or secondary development

Rules:

- `extensions/` is optional
- core usability must not depend on `extensions/`

## Path rules

All template asset paths must follow these rules:

- no workflow IDs
- no node IDs
- no project IDs inside the asset root itself
- no machine-local absolute paths in file content unless explicitly marked as placeholders for local resolution
- stable predictable filenames
- ASCII-first naming by default

## Content completeness rules

A standard template should be rejected or marked incomplete if:

- required files are missing
- `SOUL.md` is placeholder-only
- companion documents are empty or meaningless
- content is obviously under-specified for direct use

Recommended quality bar:

- a user should be able to copy the template into an agent and use it immediately
- edits should be optional refinement, not mandatory repair

## Relation to current project filesystem code

The current project filesystem already generates:

- `AGENTS.md`
- `IDENTITY.md`
- `USER.md`
- `TOOLS.md`
- `BOOTSTRAP.md`
- `HEARTBEAT.md`
- `MEMORY.md`
- `SOUL.md`

for node-local OpenClaw workspace materialization.

The new template asset specification should align with those document roles, but remove project/node-specific coupling:

- no node IDs
- no workflow IDs
- no runtime-only binding semantics

## Validation checklist

Minimum validation checklist for a standard template asset:

- required file set exists
- `template.json` parses successfully
- `lineage.json` parses successfully
- `SOUL.md` matches the rendered structured source
- companion files are non-empty
- no template-management leakage inside `SOUL.md`
- no project/workflow coupling appears in standard template files
- draft/published status is valid

## Editor behavior expectations

When a user applies a template:

1. Read the template asset root.
2. Load `template.json` as the structured source of truth.
3. Load or regenerate companion files as needed.
4. Copy the template into a standard agent draft.
5. Produce an independent agent.

When a user saves an agent as a template:

1. Extract the agent's standard state.
2. Generate a new template asset root.
3. Write the full standard file set.
4. Do not retain a live relation to the source agent.

## Out of scope

This specification does not define:

- workflow template packaging
- project persistence of template references
- runtime execution protocols
- marketplace metadata schema

Those may be added later, but they must not weaken the rule that template assets remain independent from workflows and projects.
