# Template System Redesign Aligned With Project Filesystem

Last updated: 2026-03-21
Status: Proposed

## Why redesign

The current template system is functionally rich, but its storage model no longer matches the rest of the project architecture.

Today we have two different worlds:

- Project runtime and design state are already managed per project under `Application Support/Multi-Agent-Flow/Projects/<project-id>/...`.
- Template content is still stored as a global snapshot in `Application Support/Multi-Agent-Flow/TemplateLibrary/agent-template-library.json`.

This creates several problems:

1. Template assets are not project-owned.
2. A project cannot carry its own template history, revisions, or local presets.
3. Applied templates leave almost no provenance on node-local design files.
4. Global built-in overrides can silently change future behavior without becoming part of project storage.
5. Template content, user preference state, and import helper state are mixed into one store.
6. The current design does not align with the file-system rule that future reuse should happen through presets, not shared live agents.

This document redesigns the template system so it becomes a first-class part of the managed project filesystem while preserving the existing `node = agent = 1:1` model.

## Existing constraints we must preserve

From the current project filesystem plan and codebase:

- `.maoproj` compatibility must remain.
- `MAProject` remains the shared assembly model.
- `node = agent = 1:1 execution unit` remains true.
- Template reuse must happen through presets, not through shared live agents.
- Node-local `agent.json`, `binding.json`, and OpenClaw workspace files remain the execution-facing surface.
- `SOUL.md` remains the materialized runtime artifact for an agent.

The redesign therefore must not turn templates into shared mutable live objects.

## Core redesign principles

### 1. Split content from preference state

Template content and user preferences are different things and should not live in the same snapshot.

- Template content:
  - built-in templates
  - user custom templates
  - project templates
  - imported SOUL-derived templates
- Preference state:
  - favorites
  - recents
  - picker order
  - custom function-description suggestions

### 2. Split scope into system, user, and project

The new template architecture has three scopes:

- System scope:
  - read-only built-in catalog shipped with the app
- User scope:
  - reusable personal presets and picker preferences
- Project scope:
  - templates owned by one managed project and stored under that project root

### 3. Preserve materialization semantics

Applying a template should still materialize agent state into the node-owned agent instance.

- A node does not "share" a live template.
- A node stores a reference to the template revision it was created from.
- The materialized agent remains independently editable afterward.

This means templates become provenance-bearing presets, not runtime inheritance chains.

### 4. Make template lineage explicit

Every project-owned template and every node that applies one should carry lineage metadata:

- where the template came from
- which revision was applied
- whether the node has drifted away from that revision

### 5. Make project portability deterministic

A managed project must be reproducible from its own internal files.

- If a node was created from a template, the project should contain the template revision that was applied.
- Reopening the project on another machine must not require the original global user template library to reconstruct context.

## New storage topology

## User-level storage

User-level storage continues to live under Application Support, but it is narrowed to reusable presets and preferences.

```text
Application Support/Multi-Agent-Flow/
  Libraries/
    Templates/
      preferences.json
      library.json
      templates/
        <template-id>/
          template.json
          SOUL.md
```

### `preferences.json`

Stores non-project-specific UI state:

- favorite template IDs
- recent template IDs
- ordered template IDs for the picker
- custom function-description suggestions

### `library.json`

Stores lightweight library metadata:

- schema version
- template IDs
- last updated at

### `templates/<template-id>/template.json`

Stores the user-owned template document:

- full template content
- lineage
- revision
- validation summary

Built-in templates are not stored here. This directory only stores user-owned presets and compatibility-migrated global overrides.

## Project-level storage

Templates become a first-class design asset under the managed project root.

```text
Application Support/Multi-Agent-Flow/Projects/<project-id>/
  design/
    project.json
    templates/
      library.json
      templates/
        <project-template-id>/
          template.json
          SOUL.md
          lineage.json
    workflows/
      <workflow-id>/
        workflow.json
        nodes/
          <node-id>/
            node.json
            agent.json
            template-binding.json
            openclaw/
              binding.json
              workspace/
                SOUL.md
                AGENTS.md
                USER.md
                IDENTITY.md
                TOOLS.md
                HEARTBEAT.md
                BOOTSTRAP.md
                MEMORY.md
                memory/
                skills/
```

### Why `design/templates/`

This is design-time content, not runtime session state.

- It belongs next to `project.json`, `workflow.json`, `node.json`, and `agent.json`.
- It is part of the authored project, not just a UI convenience layer.
- It matches the current internal-storage direction where design assets are decomposed under `design/`.

## New domain model

## Template content document

Introduce a storage-facing template document with explicit provenance and revision metadata.

```text
ProjectTemplateDocument
- id
- scope: system | user | project
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

### `lineage`

```text
TemplateLineage
- sourceScope: system | user | project | imported-soul | imported-openclaw
- sourceTemplateID
- sourceRevision
- sourceProjectID
- importedFromPath
- importedFromSoulHash
- createdReason: built-in-snapshot | fork | import | project-local | migrated-override
```

This gives us a durable answer to "where did this template come from?"

## Node template binding

Add a node-local template binding file instead of hiding provenance inside free-form agent fields.

```text
NodeTemplateBindingDocument
- nodeID
- agentID
- projectTemplateID
- projectTemplateRevision
- sourceScope
- sourceTemplateID
- appliedAt
- materializedSoulHash
- driftStatus: clean | modified | detached | missing-template
- lastCheckedAt
```

### Why a separate `template-binding.json`

This follows the current project filesystem style:

- `agent.json` stores the node-owned agent definition.
- `openclaw/binding.json` stores OpenClaw linkage.
- `template-binding.json` should store template linkage.

This keeps authored agent state, OpenClaw state, and preset lineage clearly separated.

## Agent document changes

`NodeAgentDesignDocument` should stay focused on the actual node-owned agent state:

- name
- identity
- description
- capabilities
- color
- timestamps
- OpenClaw definition

It should not become the primary storage for template catalog content.

Optional future addition:

- `lastTemplateApplicationAt`
- `lastTemplateMaterializedHash`

But even if those are added, the canonical linkage should still live in `template-binding.json`.

## Built-in catalog behavior

Built-in templates should become immutable from the storage perspective.

### Current problem

Today the store allows "built-in overrides" using the same template ID. That makes it hard to understand whether a project is using:

- the shipped built-in template
- a user override of that built-in template
- a forked custom template

### New behavior

Built-ins remain read-only in the system catalog.

When a user wants to modify a built-in template:

1. In user scope:
   - save as user preset fork
2. In project scope:
   - save as project template fork

For migration compatibility we can still ingest existing built-in overrides from the legacy snapshot, but after migration they should be treated as user-owned templates with lineage pointing back to the built-in source.

## Template application model

## Applying a template to a node

When the user applies a template to create or update a node-owned agent:

1. Resolve the selected template from system, user, or project scope.
2. Snapshot that template into the project template library if the exact revision is not already present there.
3. Materialize template fields into the node-owned agent:
   - identity
   - description
   - capabilities
   - color
   - rendered `SOUL.md`
4. Write `template-binding.json`.
5. Write node-local OpenClaw workspace files from the materialized agent.

This gives us both:

- reproducible project-owned template history
- independent node-owned execution state

## Editing a node after template application

After the node is created, the agent remains editable.

If the user edits:

- `identity`
- `description`
- `capabilities`
- `SOUL.md`

the node should not mutate the source template automatically.

Instead:

- the node remains materialized
- `template-binding.json` drift status becomes `modified`
- the UI can offer:
  - reapply template
  - save current node as project template
  - fork current node into user template

This is much safer than implicit two-way synchronization.

## Recommended drift logic

Compare the node’s current materialized fields against the bound template revision:

- if equal:
  - `clean`
- if only formatting-normalized SOUL changed:
  - still `clean`
- if semantic fields changed:
  - `modified`
- if bound project template no longer exists:
  - `missing-template`
- if user explicitly chooses "break link":
  - `detached`

## Project assembly behavior

## Internal managed project loading

`ProjectFileSystem.loadAssembledProject(...)` should continue to assemble a regular `MAProject`, but the template library should be loaded as a sibling design asset.

Assembly responsibilities become:

- `project.json`:
  - workflow IDs
  - optional template IDs
- `design/templates/...`:
  - project-owned template library
- `nodes/<node-id>/agent.json`:
  - node-owned materialized agent state
- `nodes/<node-id>/template-binding.json`:
  - provenance and drift metadata

The assembled `MAProject` can remain largely unchanged for compatibility. Template design assets do not need to be runtime-critical to reconstruct the existing behavior.

## `.maoproj` compatibility strategy

There are two acceptable rollout levels.

### Level 1: zero contract change

Keep `.maoproj` exactly as-is.

- Node-owned agents still carry fully materialized `identity`, `description`, `capabilities`, and `soulMD`.
- Project templates remain an internal managed-storage asset only.
- Export/import preserves behavior even if template provenance is lost outside managed storage.

This is the safest first migration.

### Level 2: additive contract extension

Add optional template metadata to the shared model later.

Possible additions:

- `projectTemplateData`
- `nodeTemplateBindings`

These must stay optional so older `.maoproj` files still load without issue.

Recommendation:

- implement Level 1 first
- only move to Level 2 if project-portable template authoring becomes a product requirement

## User library behavior

The user library should stop acting like the single source of truth for all template content.

Instead it becomes:

- a reusable personal preset library
- a source from which projects can import or snapshot templates
- the home of picker preferences

This means a project should never depend on a user-library template staying unchanged after the node has already been created.

## Import and export flows

## Import `SOUL.md` as template

Current behavior should split into two destinations:

- import to user library
- import to current project

Default recommendation:

- from the project UI, import into current project
- from a global template manager, import into user library

## Import OpenClaw agent

When importing an OpenClaw agent:

1. keep the materialized agent import behavior
2. parse `SOUL.md`
3. attempt template recommendation
4. if the user accepts a template match:
   - snapshot the matched template revision into project scope
   - write `template-binding.json`
5. if no acceptable match exists:
   - offer "save imported SOUL as project template"

This is better aligned with the current OpenClaw managed-copy flow because imported agents already become project-managed artifacts.

## Import/export JSON template packs

JSON export should become scope-aware.

- user template export:
  - exports user presets
- project template export:
  - exports project-owned templates

Project template export should come from `design/templates/`, not from the user library store.

## Validation redesign

Validation should also split by level.

### Template document validation

Checks the stored template itself:

- required SOUL sections
- management leak words
- item count warnings
- invalid lineage
- duplicate IDs or revision mismatch

### Template binding validation

Checks project-node linkage:

- missing project template
- bound revision missing
- drifted node state
- source template lineage broken

### Materialization validation

Checks execution-facing files:

- `openclaw/workspace/SOUL.md` matches node-owned agent materialization
- rendered SOUL hash matches binding metadata

## Service decomposition

The current `AgentTemplateLibraryStore` mixes too many responsibilities. Replace it with scoped services.

### `SystemTemplateCatalog`

Responsibilities:

- expose immutable built-in templates
- no persistence

### `UserTemplateLibraryStore`

Responsibilities:

- load/save user-owned templates
- load/save picker preferences
- manage favorites, recents, custom descriptions

### `ProjectTemplateStore`

Responsibilities:

- load/save `design/templates/`
- manage project template revisions
- create project-local snapshots when templates are applied
- provide template lineage lookup for nodes

### `TemplateMaterializationService`

Responsibilities:

- render `SOUL.md` from template documents
- apply template to node-owned agent state
- calculate hashes and drift

### `TemplateMigrationService`

Responsibilities:

- migrate legacy global snapshot
- split content and preferences
- convert built-in overrides into user-owned forks

## Proposed file additions in `ProjectFileSystem`

Add path helpers analogous to the existing workflow/node helpers:

```text
designTemplatesRootDirectory(for projectID:)
projectTemplateLibraryURL(for projectID:)
projectTemplateRootDirectory(for templateID:, projectID:)
projectTemplateDocumentURL(for templateID:, projectID:)
projectTemplateSoulURL(for templateID:, projectID:)
nodeTemplateBindingURL(for nodeID:, workflowID:, projectID:)
```

Recommended authoritative paths:

```text
Projects/<project-id>/design/templates/library.json
Projects/<project-id>/design/templates/templates/<template-id>/template.json
Projects/<project-id>/design/templates/templates/<template-id>/SOUL.md
Projects/<project-id>/design/workflows/<workflow-id>/nodes/<node-id>/template-binding.json
```

## Migration plan

## Phase 0: compatibility read

Keep reading the legacy file:

- `Application Support/Multi-Agent-Flow/TemplateLibrary/agent-template-library.json`

If present, migrate it once into:

- `Libraries/Templates/preferences.json`
- `Libraries/Templates/library.json`
- `Libraries/Templates/templates/<template-id>/...`

## Phase 1: service split

Replace `AgentTemplateLibraryStore` with:

- `SystemTemplateCatalog`
- `UserTemplateLibraryStore`

No project template storage yet.

## Phase 2: project template storage

Add:

- `design/templates/`
- `template-binding.json`
- snapshot-on-apply behavior

## Phase 3: drift-aware UI

Show node/template relationship in the editor:

- from built-in/user/project template
- clean or modified
- reapply
- fork to project template
- save node as template

## Phase 4: optional `.maoproj` additive metadata

Only if portability of project template assets becomes necessary outside managed storage.

## UI redesign implications

## Template picker

The picker should display source scope explicitly:

- System
- User
- Project

Recommended quick sections:

- recommended
- recent
- favorites
- current project templates
- user presets
- system templates

## Template manager

Split the current manager into two entry surfaces:

- User Template Library
- Project Template Library

Operations:

- fork built-in to user
- fork built-in to project
- import SOUL to user/project
- promote node to project template
- export project template pack

## Agent inspector

Show template provenance next to SOUL content:

- applied from which template
- which revision
- drift status

Actions:

- reapply template
- detach from template
- save current node as template

## Recommended implementation decisions

These are the choices recommended for this repo specifically:

1. Built-in templates remain immutable.
2. User preferences move out of the template content snapshot.
3. Project-owned templates live under `design/templates/`.
4. Applying a template snapshots it into project scope before materialization.
5. Nodes store provenance in `template-binding.json`.
6. Nodes remain independently editable after template application.
7. `.maoproj` remains unchanged in the first rollout.

## Benefits of this redesign

After this redesign:

- template storage matches the managed project filesystem architecture
- projects become reproducible without depending on a mutable global template library
- node-local design files can explain where an agent came from
- built-in, user, and project templates stop being conflated
- OpenClaw imports and SOUL imports can produce project-owned presets naturally
- future Electron migration gets a cleaner storage boundary

## Main tradeoff

The main tradeoff is duplication:

- a template may exist in system scope
- then be forked into user scope
- then be snapshotted into project scope

This duplication is intentional. It buys us:

- reproducibility
- provenance
- project isolation
- no hidden cross-project mutation

That tradeoff is worth it for this codebase because the current filesystem direction already favors explicit managed copies over implicit external references.
