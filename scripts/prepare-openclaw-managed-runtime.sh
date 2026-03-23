#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPSTREAM_SOURCE_DIR="${OPENCLAW_UPSTREAM_SOURCE_DIR:-}"
UPSTREAM_REPOSITORY="${OPENCLAW_UPSTREAM_REPOSITORY:-https://github.com/openclaw/openclaw.git}"
UPSTREAM_REF="${OPENCLAW_UPSTREAM_REF:-afb4b1173be157997d3cea9247b598c3d1d9a18a}"
PAYLOAD_OUTPUT_DIR="${OPENCLAW_NATIVE_PAYLOAD_OUTPUT_DIR:-$ROOT_DIR/.build/openclaw-managed-runtime-native-payload}"
KEEP_TEMP=0

usage() {
  cat <<'EOF'
Usage:
  bash ./scripts/prepare-openclaw-managed-runtime.sh \
    [--source /path/to/openclaw-source] \
    [--repository <git-url>] \
    [--ref <git-ref>] \
    [--output /path/to/native-payload] \
    [--keep-temp]

Defaults:
  repository: https://github.com/openclaw/openclaw.git
  ref:        afb4b1173be157997d3cea9247b598c3d1d9a18a

Behavior:
  1. Resolve or clone the pinned OpenClaw source tree.
  2. Build upstream artifacts when they are missing.
  3. Produce a native managed-runtime payload.
  4. Hydrate the Swift/Electron managed runtime directories.
  5. Validate the synchronized payload.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source)
      UPSTREAM_SOURCE_DIR="${2:-}"
      shift 2
      ;;
    --repository)
      UPSTREAM_REPOSITORY="${2:-}"
      shift 2
      ;;
    --ref)
      UPSTREAM_REF="${2:-}"
      shift 2
      ;;
    --output)
      PAYLOAD_OUTPUT_DIR="${2:-}"
      shift 2
      ;;
    --keep-temp)
      KEEP_TEMP=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if ! command -v git >/dev/null 2>&1; then
  echo "git is required to prepare the managed OpenClaw runtime." >&2
  exit 1
fi
if ! command -v pnpm >/dev/null 2>&1; then
  echo "pnpm is required to build the managed OpenClaw runtime." >&2
  echo "Install it first, for example: npm install -g pnpm" >&2
  exit 1
fi

TEMP_ROOT=""
cleanup() {
  if [[ "$KEEP_TEMP" == "1" ]]; then
    return 0
  fi
  if [[ -n "$TEMP_ROOT" ]] && [[ -d "$TEMP_ROOT" ]]; then
    rm -rf "$TEMP_ROOT"
  fi
}
trap cleanup EXIT

if [[ -n "$UPSTREAM_SOURCE_DIR" ]]; then
  if [[ ! -d "$UPSTREAM_SOURCE_DIR" ]]; then
    echo "OpenClaw source directory does not exist: $UPSTREAM_SOURCE_DIR" >&2
    exit 1
  fi
  UPSTREAM_SOURCE_DIR="$(cd "$UPSTREAM_SOURCE_DIR" && pwd)"
else
  TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/openclaw-upstream.prepare.XXXXXX")"
  UPSTREAM_SOURCE_DIR="$TEMP_ROOT/openclaw"
  git clone "$UPSTREAM_REPOSITORY" "$UPSTREAM_SOURCE_DIR"
  git -C "$UPSTREAM_SOURCE_DIR" checkout "$UPSTREAM_REF"
fi

needs_upstream_build=0
if [[ ! -f "$UPSTREAM_SOURCE_DIR/openclaw.mjs" ]]; then
  needs_upstream_build=1
fi
if [[ ! -f "$UPSTREAM_SOURCE_DIR/dist/entry.js" ]] && [[ ! -f "$UPSTREAM_SOURCE_DIR/dist/entry.mjs" ]]; then
  needs_upstream_build=1
fi
if [[ ! -d "$UPSTREAM_SOURCE_DIR/node_modules" ]]; then
  needs_upstream_build=1
fi

if [[ "$needs_upstream_build" == "1" ]]; then
  pnpm --dir "$UPSTREAM_SOURCE_DIR" install
  pnpm --dir "$UPSTREAM_SOURCE_DIR" ui:build
  pnpm --dir "$UPSTREAM_SOURCE_DIR" build
fi

bash "$ROOT_DIR/scripts/build-openclaw-managed-runtime-native-payload.sh" \
  --source "$UPSTREAM_SOURCE_DIR" \
  --output "$PAYLOAD_OUTPUT_DIR"

bash "$ROOT_DIR/scripts/hydrate-openclaw-managed-runtime.sh" \
  --source "$PAYLOAD_OUTPUT_DIR" \
  --sync

bash "$ROOT_DIR/scripts/validate-openclaw-managed-runtime.sh"

echo "Prepared managed OpenClaw runtime:"
echo "  upstream source: $UPSTREAM_SOURCE_DIR"
echo "  upstream ref: $UPSTREAM_REF"
echo "  payload output: $PAYLOAD_OUTPUT_DIR"
