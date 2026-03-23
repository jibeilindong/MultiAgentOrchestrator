#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_DIR="$ROOT_DIR/managed-runtime/openclaw"
TARGET_DIR="$ROOT_DIR/apps/desktop/resources/openclaw"

if [[ ! -f "$SOURCE_DIR/managed-runtime.json" ]]; then
  echo "Missing source manifest: $SOURCE_DIR/managed-runtime.json" >&2
  exit 1
fi

if [[ ! -f "$SOURCE_DIR/bin/openclaw" ]]; then
  echo "Missing source launcher: $SOURCE_DIR/bin/openclaw" >&2
  exit 1
fi

if ! command -v rsync >/dev/null 2>&1; then
  echo "rsync is required to synchronize the managed OpenClaw runtime payload." >&2
  exit 1
fi
mkdir -p "$TARGET_DIR"
rsync -a --delete --exclude='.DS_Store' "$SOURCE_DIR/" "$TARGET_DIR/"
chmod +x "$TARGET_DIR/bin/openclaw"
if [[ -f "$TARGET_DIR/libexec/openclaw" ]]; then
  chmod +x "$TARGET_DIR/libexec/openclaw"
fi
if [[ -f "$TARGET_DIR/openclaw.mjs" ]]; then
  chmod +x "$TARGET_DIR/openclaw.mjs"
fi
if [[ -f "$TARGET_DIR/runtime/node/bin/node" ]]; then
  chmod +x "$TARGET_DIR/runtime/node/bin/node"
fi
if [[ -f "$TARGET_DIR/node/bin/node" ]]; then
  chmod +x "$TARGET_DIR/node/bin/node"
fi

echo "Synchronized managed OpenClaw runtime payload:"
echo "  source: $SOURCE_DIR"
echo "  target: $TARGET_DIR"
