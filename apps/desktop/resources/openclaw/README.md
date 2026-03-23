This directory is the source-of-truth payload for the app-managed OpenClaw runtime.

It is copied into the macOS Swift app as `Contents/Resources/openclaw`
and synchronized into the Electron shell at `apps/desktop/resources/openclaw`.

Current payload shape:

- `managed-runtime.json`: managed runtime manifest and release metadata
- `bin/openclaw`: stable launcher shim for the managed runtime
- future upstream build artifacts such as `dist/` or `libexec/`

Release expectation:

1. Hydrate this directory with the upstream OpenClaw packaged CLI artifacts.
2. Run `bash ./scripts/sync-openclaw-managed-runtime.sh`.
3. Run `bash ./scripts/validate-openclaw-managed-runtime.sh`.
4. Build the Swift app or Electron desktop package.

The current launcher is intentionally conservative: it only executes vendored
artifacts that live inside this payload unless an explicit environment override
is set for development diagnostics.
