This directory is the source-of-truth payload for the app-managed OpenClaw runtime.

It is copied into the macOS Swift app as `Contents/Resources/openclaw`
and synchronized into the Electron shell at `apps/desktop/resources/openclaw`.

Current payload shape:

- `managed-runtime.json`: managed runtime manifest and release metadata
- `bin/openclaw`: stable launcher shim for the managed runtime
- `libexec/openclaw`: preferred standalone upstream CLI binary
- or `dist/cli.js` plus `runtime/node/bin/node`: bundled JS CLI mode
- `hydration-receipt.json`: last import metadata written by the hydrate script

Release expectation:

1. Import the upstream OpenClaw packaged CLI artifacts:
   `bash ./scripts/hydrate-openclaw-managed-runtime.sh --source /path/to/openclaw-build --sync`
2. Validate:
   `bash ./scripts/validate-openclaw-managed-runtime.sh`
3. Build the Swift app or Electron desktop package.

Hydration modes:

- Native binary mode:
  requires `libexec/openclaw`
- Bundled JS mode:
  requires `dist/cli.js` and a bundled Node runtime at `runtime/node/bin/node`

The launcher is intentionally conservative: it executes vendored artifacts that
live inside this payload first, and only falls back to explicitly provided
development overrides for diagnostics.
