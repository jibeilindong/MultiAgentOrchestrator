#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_DIR="$ROOT_DIR/Multi-Agent-Flow/OpenClaw"
TARGET_DIR="$ROOT_DIR/apps/desktop/resources/openclaw"

if [[ ! -f "$SOURCE_DIR/managed-runtime.json" ]]; then
  echo "Missing source manifest: $SOURCE_DIR/managed-runtime.json" >&2
  exit 1
fi

if [[ ! -f "$SOURCE_DIR/bin/openclaw" ]]; then
  echo "Missing source launcher: $SOURCE_DIR/bin/openclaw" >&2
  exit 1
fi

rm -rf "$TARGET_DIR"
mkdir -p "$(dirname "$TARGET_DIR")"
cp -R "$SOURCE_DIR" "$TARGET_DIR"
chmod +x "$TARGET_DIR/bin/openclaw"

echo "Synchronized managed OpenClaw runtime payload:"
echo "  source: $SOURCE_DIR"
echo "  target: $TARGET_DIR"
