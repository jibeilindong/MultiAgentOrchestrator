#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_DIR="$ROOT_DIR/managed-runtime/openclaw"
TARGET_DIR="$ROOT_DIR/apps/desktop/resources/openclaw"

has_bundled_node() {
  local payload_dir="$1"
  [[ -x "$payload_dir/runtime/node/bin/node" ]] || [[ -x "$payload_dir/node/bin/node" ]]
}

has_supported_js_entrypoint() {
  local payload_dir="$1"

  if [[ -f "$payload_dir/openclaw.mjs" ]] && \
     { [[ -f "$payload_dir/dist/entry.js" ]] || [[ -f "$payload_dir/dist/entry.mjs" ]]; }; then
    return 0
  fi

  if [[ -f "$payload_dir/dist/cli.js" ]]; then
    return 0
  fi

  return 1
}

validate_payload() {
  local payload_dir="$1"

  for required in \
    "$payload_dir/managed-runtime.json" \
    "$payload_dir/bin/openclaw"; do
    if [[ ! -f "$required" ]]; then
      echo "Missing managed runtime file: $required" >&2
      return 1
    fi
  done

  if [[ -x "$payload_dir/libexec/openclaw" ]]; then
    if [[ -f "$payload_dir/openclaw.mjs" ]] || \
       [[ -d "$payload_dir/dist" ]] || \
       [[ -d "$payload_dir/runtime" ]] || \
       [[ -d "$payload_dir/node" ]]; then
      if has_supported_js_entrypoint "$payload_dir" && has_bundled_node "$payload_dir"; then
        return 0
      fi

      cat >&2 <<EOF
Managed runtime payload contains libexec/openclaw plus supplemental runtime files,
but the native launcher companion assets are incomplete:
  $payload_dir

Expected together:
  - libexec/openclaw
  - openclaw.mjs or dist/cli.js
  - dist/entry.js or dist/entry.mjs
  - runtime/node/bin/node or node/bin/node
EOF
      return 1
    fi

    return 0
  fi

  if has_supported_js_entrypoint "$payload_dir" && has_bundled_node "$payload_dir"; then
    return 0
  fi

  cat >&2 <<EOF
Managed runtime payload is not fully hydrated:
  $payload_dir

Expected one of:
  - libexec/openclaw
  - openclaw.mjs plus dist/entry.js and runtime/node/bin/node
  - dist/cli.js plus runtime/node/bin/node
EOF
  return 1
}

validate_payload "$SOURCE_DIR"
validate_payload "$TARGET_DIR"

if ! diff -qr "$SOURCE_DIR" "$TARGET_DIR" >/dev/null; then
  echo "Managed runtime payload drift detected between Swift and Electron resources." >&2
  diff -qr "$SOURCE_DIR" "$TARGET_DIR" || true
  exit 1
fi

echo "Managed OpenClaw runtime payload is hydrated and synchronized."
