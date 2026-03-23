# Cross-Platform Status And Next Plan

Last updated: 2026-03-21
Status: Business parity in progress

## 1. Current objective

The project goal is no longer just "run on macOS and Windows".

The real target is:

1. Preserve `.maoproj` compatibility
2. Replace the legacy macOS Swift app with the Electron + React + TypeScript desktop app
3. Deliver a cross-platform product that can actually take over daily workflow editing, task orchestration, OpenClaw execution, and release packaging

At the current stage, the project has already moved past the infrastructure/scaffolding phase and is now in the business-parity phase.

## 2. Overall progress summary

### 2.1 Foundation migration

Completed:

- Shared npm workspace established
- `packages/domain` and `packages/core` established
- Swift date compatibility retained for `.maoproj`
- Cross-platform Electron shell established for macOS + Windows
- Renderer and preload/main bridge are in place

Meaning:

- The project is no longer blocked by the old Swift-only shell architecture
- Core model and persistence logic are already portable

### 2.2 Project file and persistence capability

Completed:

- `.maoproj` open/save/save-as flows
- Autosave
- Recent projects
- Compatibility regression fixtures
- Cross-check that old project files remain readable

Current validation state:

- `npm run typecheck` passed on 2026-03-21
- `npm run build` passed on 2026-03-21
- `npm run validate:compat` passed on 2026-03-21

Meaning:

- The cross-platform shell can already act as a real project container instead of only a preview shell

### 2.3 Workflow editor migration

Completed:

- Workflow/node/edge editing
- Node assignment and routing editing
- Zoom/pan/select
- Undo/redo
- Multi-select
- Batch align
- Batch distribute
- Tidy layout operations
- Snapping
- Reference guides

Meaning:

- The new canvas has moved beyond "basic rendering" and already supports real editing work
- This is one of the biggest structural migration risks, and it is largely under control now

### 2.4 Task and workbench capability

Completed:

- Task list and status flows
- Task generation from workflow
- Task data settings and workspace path configuration
- Workbench message panel and approval flow
- Runtime state persistence for tasks/messages/results/logs/memory/workspaces

Meaning:

- The new app can already host end-to-end workflow-driven workbench sessions

### 2.5 OpenClaw integration

Completed:

- OpenClaw config editing
- Detect/connect/disconnect/import flows
- Local CLI execution bridge
- Container execution bridge
- Real workbench entry-agent execution
- Real downstream routing execution for non-approval edges
- Approval checkpoint creation and continuation
- Agent-level OpenClaw definition editing in the desktop UI
  - agent identifier
  - model
  - runtime profile
  - memory backup path
  - SOUL source path
  - environment overrides
  - SOUL prompt

Partially completed:

- Remote server connectivity exists
- Remote server mode does not yet support equivalent direct execution flow like local/container mode

Meaning:

- The desktop shell is no longer using only synthetic workbench receipts
- Real execution has already entered the product path
- OpenClaw integration is usable, but not yet at old-app parity

### 2.6 Launch verification

Completed:

- Static launch verification
  - entry path detection
  - reachability analysis
  - missing-agent checks
  - fallback-policy and approval-edge warnings
- Runtime launch verification
  - execute launch cases against live workflow execution
  - collect observations
  - generate per-case reports
- Saved launch case management in desktop UI
  - add
  - edit
  - remove
- Report stale detection
  - workflow/report signature now includes launch case content

Meaning:

- Launch verification has evolved from a structural check into a usable release-readiness tool

### 2.7 Packaging and release path

Completed or mostly completed:

- Packaging scaffold established
- CI packaging workflow established
- macOS local packaging path available
- Windows packaging path established in workflow/desktop build pipeline

Still pending:

- Final collection and closure of real macOS/Windows distributable outputs as release-grade artifacts
- Signing/notarization/distribution-grade polish still needs final pass

Meaning:

- The project has packaging capability, but release closure is not yet the main completed outcome

## 3. Current project judgment

The cross-platform migration is in the following state:

- Architecture migration: basically complete
- Core persistence migration: complete enough for production iteration
- Workflow editor migration: strong and already practical
- Workbench execution migration: substantial breakthrough already achieved
- Business replacement of legacy app: not complete yet

In one sentence:

The project is no longer in "can it be ported?" mode. It is now in "which remaining legacy business capabilities must be closed before the new desktop app can replace the old one?" mode.

## 4. Major remaining gaps

The main gaps are no longer foundational. They are concentrated in replacement-level business capability.

### 4.1 OpenClaw management parity is not complete

Still lacking or needing strengthening:

- Richer OpenClaw agent management comparable to the old app
- Skills management and install/remove flow parity
- Better runtime configuration round-trip and sync behavior
- Remote server execution parity

Why it matters:

- This is one of the core business differentiators of the old app
- Without it, the new shell is usable but not yet a full operational replacement

### 4.2 Ops analytics and dashboard parity is still behind

The legacy Swift app contains much deeper operational analytics capability, including:

- runtime/tool/cron anomaly aggregation
- trace detail views
- reliability and history panels
- OpenClaw backup/session-derived analytics

The cross-platform app already has dashboard/workbench foundations, but the old app's operations intelligence layer has not yet been fully ported.

Why it matters:

- This is likely one of the largest remaining business gaps
- It affects whether the new desktop app can replace the legacy app for daily monitoring and triage

### 4.3 Some advanced workflow/business authoring capability still needs confirmation or补齐

Needs focused review and likely additional implementation:

- subflow-related authoring parity
- workflow boundaries/grouping parity
- import/export and advanced project-ops parity
- detailed execution inspection and trace browsing parity

Why it matters:

- These are the kinds of features that usually block "full replacement" late in a migration

### 4.4 Packaging closure is still a release task, not a finished result

Still needs closure:

- macOS final distributable verification
- Windows real installer artifact verification
- signing/notarization/distribution checklist

Why it matters:

- Cross-platform development is only truly finished when usable release artifacts are continuously produced

## 5. Recommended next development plan

Recommended priority is:

1. Finish replacement-level business capability
2. Then close packaging/release
3. Then perform real-project acceptance validation

### Phase A: Close the highest-value legacy business gaps

Priority A1: OpenClaw management parity

Suggested scope:

- Port richer agent runtime management
- Add skill install/remove/search flows where practical
- Improve local/container/remote execution-mode consistency
- Close remote server execution gap or explicitly downgrade its product scope

Expected result:

- The new desktop app can manage agents and execution environments instead of only consuming them

Priority A2: Ops analytics/dashboard parity

Suggested scope:

- Port core analytics summaries first
- Port anomaly queue and trace entry list
- Port detail drill-down views for runtime/tool/cron/OpenClaw-derived signals
- Reuse persisted execution logs/results/runtime state wherever possible

Expected result:

- The new desktop app becomes viable for daily operation monitoring, not just editing and launching

Priority A3: Advanced workflow parity audit

Suggested scope:

- Audit subflow support end to end
- Audit boundaries/grouping support end to end
- Audit import/export paths
- Audit execution detail viewing parity

Expected result:

- Remaining hidden parity blockers become explicit and can be closed systematically

### Phase B: Package and distribute for real

Suggested scope:

- Validate real macOS distributables
- Validate real Windows distributables
- Finalize builder configuration, artifact paths, and signing/notarization checklist
- Ensure CI output is sufficient for repeatable distribution

Expected result:

- Cross-platform support becomes operationally deliverable, not just code-complete

### Phase C: Replacement validation with real scenarios

Suggested scope:

- Open real legacy `.maoproj` projects in the new shell
- Execute real OpenClaw workflows
- Run launch verification on real workflows
- Validate task/workbench/dashboard flows using real operator scenarios
- Build a short regression checklist for "can replace old app"

Expected result:

- Replacement readiness can be judged from real usage instead of feature intuition

## 6. Recommended execution order

The most reasonable order from here is:

1. OpenClaw management parity
2. Ops analytics/dashboard parity
3. Advanced workflow parity audit and closure
4. Packaging closure
5. Real-project acceptance validation

Reason:

- Packaging should not be the main focus until the replacement-level business gaps are reduced
- Otherwise we would polish distribution before the product can fully take over the legacy app's job

## 7. Immediate next-step recommendation

If development resumes, the recommended immediate workstream is:

### Option 1: OpenClaw parity first

Best when the priority is execution/business replacement.

Start with:

- desktop-side richer agent management
- skill/runtime config parity
- remote execution gap review

### Option 2: Ops analytics first

Best when the priority is operational visibility and monitoring parity.

Start with:

- summary cards
- anomaly queue
- trace list/detail
- cron/tool/runtime views

### Recommended default choice

Default recommendation:

- Do OpenClaw management parity first
- Then do Ops analytics/dashboard parity

Reason:

- The new app already has real execution wiring, so strengthening execution/agent management will compound the value of the current work immediately
- After that, the analytics/dashboard migration can reuse the now more complete runtime data path

## 8. Snapshot conclusion

Current conclusion:

- The cross-platform migration is successful at the architecture and execution-foundation level
- The new desktop app is already a real product shell, not a prototype
- The project is now in the final and more business-specific phase: replacing the legacy app's differentiated capability

The next milestone should therefore be defined as:

"Make the new desktop app capable enough to replace the legacy app in real daily use", not merely "make it run on macOS and Windows".

## 9. Pause note

This document is a status and planning snapshot only.

Per current instruction, no further feature development is being advanced in this step.
