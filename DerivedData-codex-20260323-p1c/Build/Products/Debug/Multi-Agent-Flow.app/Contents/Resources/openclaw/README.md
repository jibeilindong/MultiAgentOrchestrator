This directory is the source-of-truth payload for the app-managed OpenClaw runtime.

It is copied into the macOS Swift app as `Contents/Resources/openclaw`
and synchronized into the Electron shell at `apps/desktop/resources/openclaw`.

Current payload shape:

- `managed-runtime.json`: managed runtime manifest and release metadata
- `bin/openclaw`: stable launcher shim for the managed runtime
- `libexec/openclaw`: preferred native launcher entrypoint
- `openclaw.mjs` plus `dist/entry.js`: upstream OpenClaw build outputs
- `node_modules/`: production runtime dependencies deployed from upstream lockfile
- `runtime/node/bin/node`: bundled private Node runtime for app-managed mode
- `hydration-receipt.json`: last import metadata written by the hydrate script

Release expectation:

1. Build a native launcher payload from an upstream OpenClaw source tree:
   `bash ./scripts/build-openclaw-managed-runtime-native-payload.sh --source /path/to/openclaw-source --output /tmp/openclaw-native-payload`
2. Import the payload into the managed runtime:
   `bash ./scripts/hydrate-openclaw-managed-runtime.sh --source /tmp/openclaw-native-payload --sync`
3. Validate:
   `bash ./scripts/validate-openclaw-managed-runtime.sh`
4. Build the Swift app or Electron desktop package.

Direct import from an already built JS payload also remains supported:
`bash ./scripts/hydrate-openclaw-managed-runtime.sh --source /path/to/openclaw-build --node-source /path/to/node-runtime --sync`

Hydration modes:

- Native launcher mode:
  requires `libexec/openclaw`, `openclaw.mjs`, `dist/`, `node_modules/`, and bundled Node
- Pure native binary mode:
  requires `libexec/openclaw`
- Bundled JS mode:
  requires `openclaw.mjs`, `dist/entry.js`, `node_modules/`, and `runtime/node/bin/node`

The launcher is intentionally conservative: it executes vendored artifacts that
live inside this payload first, and only falls back to explicitly provided
development overrides for diagnostics.
