This directory stores the source-of-truth placeholder for the app-managed
OpenClaw runtime.

What is committed to Git:

- `managed-runtime.json`: stable manifest with pinned upstream reference
- `bin/openclaw`: stable launcher shim for the managed runtime
- `README.md`: build-time hydration instructions

What is generated at build time and intentionally ignored by Git:

- `libexec/openclaw`
- `openclaw.mjs`
- `dist/`
- `node_modules/`
- `runtime/node/`
- `skills/`, `docs/`, `assets/`
- `hydration-receipt.json`

Build-time flow:

1. Prepare the pinned upstream OpenClaw runtime:
   `bash ./scripts/prepare-openclaw-managed-runtime.sh`
2. Or prepare from an existing upstream checkout:
   `bash ./scripts/prepare-openclaw-managed-runtime.sh --source /path/to/openclaw-source`
3. Build the Swift app or Electron desktop package.

The packaged application still ships with a fully vendored OpenClaw runtime.
The repository simply avoids storing the 700MB+ generated payload directly.
