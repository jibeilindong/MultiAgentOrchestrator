#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_DIR="$ROOT_DIR/Multi-Agent-Flow/OpenClaw"
TARGET_DIR="$ROOT_DIR/apps/desktop/resources/openclaw"

for required in \
  "$SOURCE_DIR/managed-runtime.json" \
  "$SOURCE_DIR/bin/openclaw" \
  "$TARGET_DIR/managed-runtime.json" \
  "$TARGET_DIR/bin/openclaw"; do
  if [[ ! -f "$required" ]]; then
    echo "Missing managed runtime file: $required" >&2
    exit 1
  fi
done

if ! cmp -s "$SOURCE_DIR/managed-runtime.json" "$TARGET_DIR/managed-runtime.json"; then
  echo "Managed runtime manifest drift detected between Swift and Electron payloads." >&2
  exit 1
fi

if ! cmp -s "$SOURCE_DIR/bin/openclaw" "$TARGET_DIR/bin/openclaw"; then
  echo "Managed runtime launcher drift detected between Swift and Electron payloads." >&2
  exit 1
fi

echo "Managed OpenClaw runtime payload is synchronized."
