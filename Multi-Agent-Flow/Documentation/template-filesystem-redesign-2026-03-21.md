# Agent Template System Redesign Aligned With Filesystem Architecture

Last updated: 2026-03-22
Status: Proposed

## Purpose

This redesign updates the template system so it matches the software's filesystem architecture while following the following product principles:

1. Templates must be completely decoupled from projects. Projects must not contain template metadata, template bindings, template revisions, or embedded template snapshots.
2. Templates are standardized assets. They must be portable, exchangeable, forkable, extensible, and creatable from scratch.
3. Templates must obey the software's filesystem design instead of remaining a monolithic global JSON blob.
4. Templates here mean agent templates only, not workflow templates.
5. As standardized agent templates, required files, paths, and related contents must all exist and should be as complete, filled-out, and standardized as practical.
6. Templates must never participate in workflows. Only copied, materialized agents may participate in workflows.

This document replaces any earlier direction that treated templates as project-owned or project-bound entities.

## Problem statement

The current template system is useful, but its storage model is inconsistent with the rest of the architecture.

Today:

- project runtime and design state are being moved into managed project roots under `Application Support/Multi-Agent-Flow/Projects/<project-id>/...`
- template content is still stored in a single global snapshot file:
  - `Application Support/Multi-Agent-Flow/TemplateLibrary/agent-template-library.json`

This causes several issues:

1. Templates are not modeled as first-class filesystem assets.
2. Template content, user preferences, and import-helper state are mixed together.
3. Templates are hard to package, circulate, extend, and version cleanly.
4. The storage shape does not match the managed-storage conventions used elsewhere in the app.
5. Projects may appear to depend on whatever global template state exists on the current machine.
6. The current model does not enforce the idea that a template should be a complete standard agent package.

## Non-negotiable constraints

The redesign must preserve:

- `.maoproj` compatibility
- `MAProject` as the shared assembly model
- `node = agent = 1:1 execution unit`
- current node-local agent materialization behavior
- `SOUL.md` as the materialized execution-facing artifact

The key implication is:

- templates may influence agent creation
- templates must not become shared live runtime objects
- projects must continue to store only materialized agent state, not template state

## Core principles

## 1. Project-template decoupling

Projects must be fully decoupled from template assets.

A project should store:

- node-owned agent state
- workflow state
- runtime state
- OpenClaw state

A project must not store:

- template IDs
- template revisions
- template bindings
- template libraries
- embedded copies of template assets
- workflow-time participation of template files

Template application is therefore a strict one-way materialization step:

- select template
- copy template into an agent draft
- persist only the resulting node-owned agent state into the project

## 2. Templates are standardized agent assets

Templates are not editor-local presets or partial prompt fragments. They are reusable software assets for agents.

A template asset must support:

- creation from scratch
- import from `SOUL.md`
- import from OpenClaw-derived material
- export as a portable package
- forking and secondary development
- versioning and revision history
- validation and testing

## 3. Filesystem-native template design

Templates should follow the same filesystem philosophy already used by the app:

- explicit roots
- manifests
- split documents
- stable identifiers
- generated artifacts separated from source documents
- predictable paths

The template system should therefore move away from a single monolithic JSON snapshot and adopt a managed library layout.

## 4. Complete standard file set

Each template should represent a complete standard agent package rather than only a `template.json` plus one prompt body.

This means:

- required files should exist
- required paths should be stable
- companion files should be generated
- content should be as complete and standardized as practical

The editor should be able to copy a template and immediately produce a standard agent that is directly usable if the user makes no changes.

## 5. Copy, then sever all relation

Template usage must follow a strict copy-and-sever model.

When a user applies a template:

- the editor copies the template content into a new or existing agent draft
- the result becomes a normal node-owned agent
- if the user edits the agent afterward, the edits belong only to that agent
- the agent no longer has any relation to the source template

When a user saves an agent as a template:

- the editor creates a new template asset file set
- the new template does not retain a live relation to the source agent
- the source agent remains just an agent

This rule is absolute:

- templates do not track agents
- agents do not track templates

## 6. Templates never participate in workflows

Templates are completely independent from workflows.

They may be used by the editor as source material to create an agent, but:

- template files are not workflow nodes
- template files are not workflow resources
- template files are not runtime participants
- template files are not saved as part of workflow state

Only copied, materialized agents may participate in workflows.

## Recommended architecture

The new architecture has three layers:

- System catalog
  - immutable built-in templates shipped with the app
- User library
  - user-owned template assets and user preferences
- Exchange packages
  - portable template bundles for circulation, import, export, and secondary development

Notably absent:

- project template scope

Projects consume templates through copy/materialization only. Projects do not own or persist templates.

## Scope model

## System scope

System scope contains built-in templates provided by the application.

Properties:

- read-only
- versioned by app release
- cannot be edited in place
- can be forked into the user library

## User scope

User scope contains templates owned by the current user.

Properties:

- editable
- versioned
- importable and exportable
- forkable from built-ins or other user templates
- usable as the source for agent materialization

## Exchange scope

Exchange scope is not a runtime store but a packaging format.

It is used for:

- asset circulation
- sharing across machines
- review and collaboration
- secondary development
- future repository or marketplace integration

## Filesystem layout

## 1. Built-in catalog

Built-in templates should be represented as immutable assets in the application bundle or generated app-support cache.

Conceptual shape:

```text
System Templates/
  manifest.json
  templates/
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
```

The exact physical location can remain implementation-defined, but the structure should match the managed-asset pattern.

## 2. User template library

The user template library becomes the authoritative mutable library.

Recommended location:

```text
Application Support/Multi-Agent-Flow/
  Libraries/
    Templates/
      manifest.json
      preferences.json
      indexes/
        tags.json
        capabilities.json
        search.json
      templates/
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

### Why this layout

This layout treats each template as an independent asset root instead of a row inside a shared blob.

Benefits:

- each template has a stable directory
- revision history can be added incrementally
- extension material has a natural home
- exchange/import/export becomes simpler
- asset-level tooling becomes possible later
- each template can exist as a complete standard agent package

## 3. Portable exchange package

Templates should have a package format that can be zipped, copied, reviewed, and imported.

Recommended unpacked structure:

```text
template-package/
  package.json
  templates/
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
      extensions/
```

This makes templates portable without tying them to a specific project.

## What projects store after the redesign

Projects continue to store only materialized design/runtime state.

They keep:

- `agent.json`
- node-local OpenClaw workspace files
- materialized `SOUL.md`
- workflow state
- runtime state

They do not keep:

- template-binding files
- template revision references
- template lineage references
- project-owned template directories
- live links back to template assets

This is the strict interpretation of project-template decoupling.

## Template application model

## One-way materialization

Applying a template should work like this:

1. Resolve the selected template from system or user scope.
2. Copy the template into a standard agent draft in the editor.
3. Materialize template files and fields into the node-owned agent:
   - identity
   - description
   - capabilities
   - color
   - rendered `SOUL.md`
   - related standard companion documents as required by the editor/runtime surface
4. Persist only the resulting node-owned agent state into the project.
5. Regenerate node-local OpenClaw workspace documents from that materialized agent.

No template reference is stored in the project.

## After application

Once the node-owned agent has been created:

- it is independent
- later edits do not affect the source template
- template reapplication must be an explicit user action
- if the user makes no edits, the copied result should already be directly usable as a standard agent

This matches the intended rule: templates are source assets, not live dependencies.

## Provenance handling without project coupling

Since projects must not store template metadata, provenance should live outside the project.

Recommended approach:

- template lineage is stored inside the template asset itself
- optional editor-local recent-application history can be stored in user scope
- the project stores only the materialized result

If the product later needs provenance for audit or debugging, it should be implemented as optional user-side editor state, not as part of project persistence.

## Template document model

Each template asset should use a document like:

```text
TemplateAssetDocument
- id
- revision
- displayName
- meta
- soulSpec
- renderedSoulHash
- validation
- lineage
- createdAt
- updatedAt
```

Where:

- `meta` contains management metadata
- `soulSpec` contains the structured SOUL source
- `renderedSoulHash` captures the current materialized `SOUL.md` fingerprint
- `lineage` records template origin and fork history

This document is the structured index/spec entry. It does not replace the rest of the standard template file set.

## Standard template file set

Each template asset should contain a complete standard file set for an agent template package.

Minimum recommended file set:

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
```

Rules:

- all required files must exist
- paths must be stable and predictable
- content should be as complete and filled-out as practical
- placeholder-only templates should be avoided unless explicitly marked as draft

## Lineage model

Recommended lineage structure:

```text
TemplateLineage
- sourceScope: system | user | imported-soul | imported-openclaw | imported-package
- sourceTemplateID
- sourceRevision
- importedFromPath
- importedFromSoulHash
- createdReason: built-in-fork | new-from-scratch | soul-import | package-import | migrated-legacy
```

This supports circulation and secondary development without coupling templates to projects.

## Built-in template behavior

Built-ins should become truly immutable.

Allowed behavior:

- view built-in
- apply built-in
- fork built-in into user library

Disallowed behavior:

- editing built-in in place
- overriding built-in by reusing the same ID in the mutable store

Legacy built-in overrides from the old snapshot should be migrated into user-owned forked assets.

## Creation model

Templates should support three creation paths:

## 1. Create from scratch

The user can create a blank template asset directly in the user library.

Even when created from scratch, the result should still be expanded into the standard template file set, not left as a partial prompt stub.

## 2. Create from existing SOUL

Import a standalone `SOUL.md` and turn it into a template asset.

Recommended output:

- structured `template.json`
- rendered `SOUL.md`
- standard companion documents
- lineage marked as `imported-soul`

## 3. Create from existing template

Fork a built-in or user template into a new user-owned template asset.

Recommended output:

- new asset ID
- new revision
- full standard file set
- lineage pointing back to the source template and revision

## Save agent as template

The editor should also support saving an existing agent as a new template asset.

Rules:

- the system creates a new template asset file set
- the new template is independent from the source agent
- the source agent remains only an agent
- no reverse relation is retained

## Secondary development model

To support secondary development, each template asset directory should allow optional extension material:

- `README.md`
- examples
- tests
- assets

This lets a template evolve beyond a single prompt/spec document and become a standardized reusable capability package.

Secondary development must still preserve the rule that template assets remain outside workflows.

## Validation redesign

Validation should operate at the template-asset level.

Checks include:

- required SOUL sections
- required standard files exist
- required paths are valid
- companion documents are not missing
- management-leak phrases
- item count warnings
- invalid IDs or revision data
- lineage consistency
- optional extension-material integrity

Validation should no longer assume that templates are embedded in projects.

## Import and export flows

## Import `SOUL.md`

Import target:

- user template library

Not:

- current project

The project may still apply the resulting template afterward, but the imported template remains a library asset, not a project asset.

## Import OpenClaw-derived material

If an imported OpenClaw agent yields a valuable `SOUL.md`, the user may choose to:

- materialize it only into the project as an agent
- or save it into the user template library as a new template asset

If saved as a template, it should be normalized into the full standard template file set rather than stored as a loose SOUL-only artifact.

## Export template packs

Export should produce a portable template package from user-library assets.

This package should be suitable for:

- circulation
- review
- backup
- secondary development
- future repository or marketplace ingestion

## Service decomposition

The current `AgentTemplateLibraryStore` mixes too many concerns.

Recommended replacement:

## `SystemTemplateCatalog`

Responsibilities:

- expose immutable built-in templates
- no mutable persistence

## `UserTemplateLibraryStore`

Responsibilities:

- load/save user-owned template assets
- load/save preferences
- manage recents, favorites, picker order
- manage import/export of template packages

## `TemplateAssetService`

Responsibilities:

- create template from scratch
- fork template
- save agent as template
- parse and generate `SOUL.md`
- generate the complete standard file set
- maintain lineage and revisions
- run validation

## `TemplateMaterializationService`

Responsibilities:

- apply a template to an agent draft
- render materialized `SOUL.md`
- generate the standard companion documents expected by the editor/runtime surface
- return pure agent state without introducing project-side template metadata

## `TemplateMigrationService`

Responsibilities:

- migrate the old monolithic snapshot
- split content from preferences
- convert legacy built-in overrides into user-owned fork assets

## Filesystem helpers to add

The filesystem layer should gain template-library path helpers, but these helpers should be separate from `ProjectFileSystem`.

Recommended direction:

- keep `ProjectFileSystem` focused on project roots
- add a dedicated `TemplateFileSystem`

Suggested helpers:

```text
templateLibraryRootDirectory()
templateManifestURL()
templatePreferencesURL()
templateIndexesRootDirectory()
templateRootDirectory(for templateID:)
templateDocumentURL(for templateID:)
templateSoulURL(for templateID:)
templateAgentsURL(for templateID:)
templateIdentityURL(for templateID:)
templateUserURL(for templateID:)
templateToolsURL(for templateID:)
templateBootstrapURL(for templateID:)
templateHeartbeatURL(for templateID:)
templateMemoryURL(for templateID:)
templateLineageURL(for templateID:)
templateRevisionDirectory(for templateID:)
```

This keeps template assets aligned with the software filesystem design without polluting project storage.

## Migration plan

## Phase 0: compatibility read

Continue reading the old legacy file if present:

- `Application Support/Multi-Agent-Flow/TemplateLibrary/agent-template-library.json`

## Phase 1: split storage

Migrate legacy data into:

```text
Application Support/Multi-Agent-Flow/Libraries/Templates/
  manifest.json
  preferences.json
  templates/<template-id>/...
```

Migration rules:

- built-in overrides become user-owned forks
- custom templates become user-owned assets
- favorites, recents, and order move into `preferences.json`
- loose legacy templates are normalized into the standard file set

## Phase 2: switch services

Replace `AgentTemplateLibraryStore` with:

- `SystemTemplateCatalog`
- `UserTemplateLibraryStore`
- `TemplateAssetService`
- `TemplateMaterializationService`

## Phase 3: package import/export

Introduce portable template packages and asset-level import/export.

## Phase 4: secondary-development support

Allow optional `extensions/`, `examples/`, and `tests/` inside template asset roots.

## UI implications

## Template picker

The picker should show:

- built-in templates
- user templates
- favorites
- recents
- recommendations

It should not imply that templates belong to the current project.

## Template manager

The current manager should become a user-library manager.

Main actions:

- create from scratch
- fork from built-in or user template
- import `SOUL.md`
- import package
- save agent as template
- export package
- validate template asset

## Agent inspector

The inspector may still allow:

- choose template
- apply template
- reapply template manually

But it should not persist template references into project state.

Once applied, the result shown in the inspector is just a normal agent.

## Recommended decisions for this repository

Based on the current repository direction, the recommended concrete decisions are:

1. Remove project-owned template storage from the plan.
2. Keep projects fully free of template metadata.
3. Treat templates as standardized user and system assets.
4. Introduce a dedicated template filesystem separate from `ProjectFileSystem`.
5. Make built-ins immutable and fork-only.
6. Require every agent template asset to carry a complete standard file set, not only `template.json` plus `SOUL.md`.
7. Make template application a strict copy-and-sever materialization step.
8. Keep templates completely outside workflow persistence and runtime participation.
9. Keep `.maoproj` unchanged in the first rollout.

## Main benefits

After this redesign:

- templates are fully decoupled from projects
- templates become portable standardized assets
- the filesystem model becomes cleaner and more consistent
- projects remain simple and focused on materialized design/runtime state
- template circulation and secondary development become possible
- the editor can copy a template and directly yield a usable standard agent

## Main tradeoff

The main tradeoff is reduced project-side provenance.

Since projects must not store template metadata:

- a reopened project cannot reliably tell which template originally generated a node unless that information is re-inferred from agent content

This is an intentional consequence of strict decoupling. Under the new principles, portability and standardization of template assets take priority over project-side template lineage.
