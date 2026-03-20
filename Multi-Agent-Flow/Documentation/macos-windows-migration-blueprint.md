# macOS + Windows Cross-Platform Migration Blueprint

Last updated: 2026-03-20
Status: In progress

## Goal

Migrate `Multi-Agent-Flow` from a macOS-only SwiftUI/AppKit desktop application to a cross-platform desktop product that supports:

- macOS
- Windows

The migration will preserve the existing `.maoproj` project format while gradually replacing the native shell with a new Electron + React + TypeScript application.

## Why this route

The current app is strongly coupled to macOS-native APIs:

- `AppKit` menus and window actions in `MultiAgentFlowApp.swift`
- `NSOpenPanel` / `NSSavePanel` in `AppState.swift`
- `NSPasteboard` / `NSWorkspace`
- `NSViewRepresentable` and `NSEvent` based canvas interactions

This makes direct Windows support in the current Swift project expensive and brittle. The recommended strategy is:

1. Keep the data model and business rules
2. Rebuild the desktop shell with web-based UI technology
3. Preserve `.maoproj` compatibility during the transition

## Target architecture

```text
apps/
  desktop/
    electron/
      main.ts
      preload.ts
    src/
      App.tsx
      main.tsx

packages/
  domain/
    src/
  core/
    src/

legacy/
  Multi-Agent-Flow/
  Multi-Agent-Flow.xcodeproj/
```

### Responsibilities

`packages/domain`

- Persistent project types
- Workflow, task, message, permission, OpenClaw, execution models
- No UI code
- No operating-system APIs

`packages/core`

- `.maoproj` serialization and normalization
- Swift date compatibility helpers
- New project creation
- Import/export migration logic
- Future OpenClaw client orchestration

`apps/desktop`

- Electron shell
- React renderer
- System dialogs, clipboard, shell open, filesystem bridge
- Future workflow editor and settings UI

## Migration phases

### Phase 0: Freeze the data contract

Deliverables:

- Repository blueprint document
- TypeScript project model mirroring `.maoproj`
- Compatibility notes for Swift date encoding

Acceptance criteria:

- New code can represent the full persisted project shape
- Date serialization strategy is documented and implemented

### Phase 1: Extract platform-agnostic core

Deliverables:

- `packages/domain`
- `packages/core`
- New project factory
- Stable JSON serialization helpers

Acceptance criteria:

- Core code has no `SwiftUI`, `AppKit`, or OS-specific imports
- New project generation follows the existing `fileVersion` and workflow defaults

### Phase 2: Create the cross-platform desktop shell

Deliverables:

- Electron main process
- Preload bridge
- React renderer shell
- Shared npm workspace

Acceptance criteria:

- One codebase can target both macOS and Windows
- Renderer can consume `packages/core` and `packages/domain`

### Phase 3: Port project management flows

Deliverables:

- Open/save/save-as flows in Electron
- Recent projects support
- Autosave and backup strategy

Acceptance criteria:

- `.maoproj` files can be opened and saved from the new shell
- Existing projects remain readable by the legacy app

### Phase 4: Rebuild the workflow canvas

Deliverables:

- React-based workflow editor
- Node, edge, zoom, pan, selection, properties editing

Acceptance criteria:

- Existing workflows render correctly
- Basic editing and persistence are available

### Phase 5: Port OpenClaw integration

Delivery order:

1. Remote server mode
2. Local CLI mode
3. Container mode

Acceptance criteria:

- The new app can restore core execution and orchestration flows

### Phase 6: Packaging and release

Deliverables:

- macOS distributables
- Windows distributables
- CI workflow for packaging

Acceptance criteria:

- Signed distributables can be produced for both target platforms

## Execution order now

The first implementation batch starts with:

1. Create this migration blueprint file
2. Scaffold a shared npm workspace
3. Add `domain` and `core` packages
4. Add a minimal Electron + React app shell
5. Preserve Swift date compatibility in new serialization utilities

## Current status

- [x] Migration blueprint created
- [x] Shared workspace scaffold started
- [x] Initial platform-agnostic domain model started
- [x] Initial core serialization helpers started
- [x] Minimal desktop shell scaffold started
- [x] `.maoproj` open/save bridge
- [ ] Workflow canvas migration
- [x] Packaging scaffold started
- [x] CI packaging workflow started
- [x] `.maoproj` compatibility regression fixtures started
- [ ] OpenClaw migration
- [ ] macOS + Windows packaging

## Important compatibility rule

The legacy Swift app saves `Date` values using Swift `JSONEncoder` defaults for `.maoproj`. The new TypeScript core must preserve compatibility instead of writing JavaScript `Date.now()` values directly.

That compatibility is handled in `packages/core/src/swift-date.ts`.
