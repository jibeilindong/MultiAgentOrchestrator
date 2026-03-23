#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PAYLOAD_DIR="$ROOT_DIR/managed-runtime/openclaw"
ARTIFACT_SOURCE="${OPENCLAW_MANAGED_SOURCE_DIR:-}"
NODE_SOURCE="${OPENCLAW_MANAGED_NODE_SOURCE_DIR:-}"
SYNC_AFTER_HYDRATE=0

usage() {
  cat <<'EOF'
Usage:
  bash ./scripts/hydrate-openclaw-managed-runtime.sh \
    --source /path/to/openclaw-build \
    [--node-source /path/to/node-runtime] \
    [--sync]

Accepted OpenClaw source layouts:
  1. Standalone binary payload
     libexec/openclaw

  2. Native launcher payload
     libexec/openclaw
     openclaw.mjs
     dist/entry.js
     runtime/node/bin/node

  3. JavaScript CLI payload
     openclaw.mjs
     dist/entry.js
     and either:
       runtime/node/bin/node
       node/bin/node
       --node-source /path/to/node-runtime

Environment variables:
  OPENCLAW_MANAGED_SOURCE_DIR
  OPENCLAW_MANAGED_NODE_SOURCE_DIR
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source)
      ARTIFACT_SOURCE="${2:-}"
      shift 2
      ;;
    --node-source)
      NODE_SOURCE="${2:-}"
      shift 2
      ;;
    --sync)
      SYNC_AFTER_HYDRATE=1
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

if [[ -z "$ARTIFACT_SOURCE" ]]; then
  echo "Missing required OpenClaw source directory." >&2
  usage >&2
  exit 1
fi

if [[ ! -d "$ARTIFACT_SOURCE" ]]; then
  echo "OpenClaw source directory does not exist: $ARTIFACT_SOURCE" >&2
  exit 1
fi

ARTIFACT_SOURCE="$(cd "$ARTIFACT_SOURCE" && pwd)"
if [[ -n "$NODE_SOURCE" ]]; then
  if [[ ! -d "$NODE_SOURCE" ]]; then
    echo "Node runtime source directory does not exist: $NODE_SOURCE" >&2
    exit 1
  fi
  NODE_SOURCE="$(cd "$NODE_SOURCE" && pwd)"
fi

detect_mode() {
  if [[ -x "$ARTIFACT_SOURCE/libexec/openclaw" ]]; then
    printf '%s\n' "libexec"
    return 0
  fi

  if [[ -f "$ARTIFACT_SOURCE/openclaw.mjs" ]] && \
     { [[ -f "$ARTIFACT_SOURCE/dist/entry.js" ]] || [[ -f "$ARTIFACT_SOURCE/dist/entry.mjs" ]]; }; then
    printf '%s\n' "dist"
    return 0
  fi

  if [[ -f "$ARTIFACT_SOURCE/dist/cli.js" ]]; then
    printf '%s\n' "dist"
    return 0
  fi

  return 1
}

MODE="$(detect_mode || true)"
if [[ -z "$MODE" ]]; then
  cat >&2 <<EOF
Unable to detect a supported OpenClaw artifact layout in:
  $ARTIFACT_SOURCE

Expected one of:
  - libexec/openclaw
  - openclaw.mjs plus dist/entry.js
  - dist/cli.js
EOF
  exit 1
fi

detect_node_runtime() {
  local candidate
  for candidate in \
    "$ARTIFACT_SOURCE/runtime/node/bin/node" \
    "$ARTIFACT_SOURCE/node/bin/node" \
    "$NODE_SOURCE/bin/node" \
    "$NODE_SOURCE/node/bin/node" \
    "$NODE_SOURCE/runtime/node/bin/node"; do
    if [[ -n "$candidate" && -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

NODE_EXECUTABLE=""
if [[ "$MODE" == "dist" ]]; then
  NODE_EXECUTABLE="$(detect_node_runtime || true)"
  if [[ -z "$NODE_EXECUTABLE" ]]; then
    cat >&2 <<EOF
JavaScript CLI payload detected, but no bundled Node runtime was found.

Provide one of:
  - $ARTIFACT_SOURCE/runtime/node/bin/node
  - $ARTIFACT_SOURCE/node/bin/node
  - --node-source /path/to/node-runtime
EOF
    exit 1
  fi

  if [[ ! -f "$ARTIFACT_SOURCE/openclaw.mjs" ]] && [[ ! -f "$ARTIFACT_SOURCE/dist/cli.js" ]]; then
    cat >&2 <<EOF
JavaScript CLI payload detected, but no supported entrypoint was found.

Expected one of:
  - $ARTIFACT_SOURCE/openclaw.mjs
  - $ARTIFACT_SOURCE/dist/cli.js
EOF
    exit 1
  fi

  if [[ ! -f "$ARTIFACT_SOURCE/dist/entry.js" ]] && \
     [[ ! -f "$ARTIFACT_SOURCE/dist/entry.mjs" ]] && \
     [[ ! -f "$ARTIFACT_SOURCE/dist/cli.js" ]]; then
    cat >&2 <<EOF
JavaScript CLI payload detected, but upstream build outputs are incomplete.

Expected one of:
  - $ARTIFACT_SOURCE/dist/entry.js
  - $ARTIFACT_SOURCE/dist/entry.mjs
  - $ARTIFACT_SOURCE/dist/cli.js

Provide one of:
  - $ARTIFACT_SOURCE/runtime/node/bin/node
  - $ARTIFACT_SOURCE/node/bin/node
  - --node-source /path/to/node-runtime
EOF
    exit 1
  fi
fi

mkdir -p "$PAYLOAD_DIR"

cleanup_hydrated_payload() {
  rm -rf \
    "$PAYLOAD_DIR/libexec" \
    "$PAYLOAD_DIR/openclaw.mjs" \
    "$PAYLOAD_DIR/dist" \
    "$PAYLOAD_DIR/runtime" \
    "$PAYLOAD_DIR/node" \
    "$PAYLOAD_DIR/package.json" \
    "$PAYLOAD_DIR/package-lock.json" \
    "$PAYLOAD_DIR/pnpm-lock.yaml" \
    "$PAYLOAD_DIR/npm-shrinkwrap.json" \
    "$PAYLOAD_DIR/hydration-receipt.json"
}

cleanup_hydrated_payload

if [[ "$MODE" == "libexec" ]]; then
  mkdir -p "$PAYLOAD_DIR/libexec"
  cp -R "$ARTIFACT_SOURCE/libexec/." "$PAYLOAD_DIR/libexec/"
  chmod +x "$PAYLOAD_DIR/libexec/openclaw"

  if [[ -f "$ARTIFACT_SOURCE/openclaw.mjs" ]]; then
    cp "$ARTIFACT_SOURCE/openclaw.mjs" "$PAYLOAD_DIR/openclaw.mjs"
    chmod +x "$PAYLOAD_DIR/openclaw.mjs"
  fi

  if [[ -d "$ARTIFACT_SOURCE/dist" ]]; then
    mkdir -p "$PAYLOAD_DIR/dist"
    cp -R "$ARTIFACT_SOURCE/dist/." "$PAYLOAD_DIR/dist/"
  fi

  if [[ -d "$ARTIFACT_SOURCE/runtime" ]]; then
    mkdir -p "$PAYLOAD_DIR/runtime"
    cp -R "$ARTIFACT_SOURCE/runtime/." "$PAYLOAD_DIR/runtime/"
  fi

  if [[ -d "$ARTIFACT_SOURCE/node" ]]; then
    mkdir -p "$PAYLOAD_DIR/node"
    cp -R "$ARTIFACT_SOURCE/node/." "$PAYLOAD_DIR/node/"
  fi

  if [[ -f "$ARTIFACT_SOURCE/package.json" ]]; then
    cp "$ARTIFACT_SOURCE/package.json" "$PAYLOAD_DIR/package.json"
  fi
  if [[ -f "$ARTIFACT_SOURCE/package-lock.json" ]]; then
    cp "$ARTIFACT_SOURCE/package-lock.json" "$PAYLOAD_DIR/package-lock.json"
  fi
  if [[ -f "$ARTIFACT_SOURCE/pnpm-lock.yaml" ]]; then
    cp "$ARTIFACT_SOURCE/pnpm-lock.yaml" "$PAYLOAD_DIR/pnpm-lock.yaml"
  fi
  if [[ -f "$ARTIFACT_SOURCE/npm-shrinkwrap.json" ]]; then
    cp "$ARTIFACT_SOURCE/npm-shrinkwrap.json" "$PAYLOAD_DIR/npm-shrinkwrap.json"
  fi

  if [[ -x "$PAYLOAD_DIR/runtime/node/bin/node" ]]; then
    chmod +x "$PAYLOAD_DIR/runtime/node/bin/node"
  fi
  if [[ -x "$PAYLOAD_DIR/node/bin/node" ]]; then
    chmod +x "$PAYLOAD_DIR/node/bin/node"
  fi
fi

if [[ "$MODE" == "dist" ]]; then
  if [[ -f "$ARTIFACT_SOURCE/openclaw.mjs" ]]; then
    cp "$ARTIFACT_SOURCE/openclaw.mjs" "$PAYLOAD_DIR/openclaw.mjs"
    chmod +x "$PAYLOAD_DIR/openclaw.mjs"
  fi

  mkdir -p "$PAYLOAD_DIR/dist"
  cp -R "$ARTIFACT_SOURCE/dist/." "$PAYLOAD_DIR/dist/"

  if [[ -f "$ARTIFACT_SOURCE/package.json" ]]; then
    cp "$ARTIFACT_SOURCE/package.json" "$PAYLOAD_DIR/package.json"
  fi
  if [[ -f "$ARTIFACT_SOURCE/package-lock.json" ]]; then
    cp "$ARTIFACT_SOURCE/package-lock.json" "$PAYLOAD_DIR/package-lock.json"
  fi
  if [[ -f "$ARTIFACT_SOURCE/pnpm-lock.yaml" ]]; then
    cp "$ARTIFACT_SOURCE/pnpm-lock.yaml" "$PAYLOAD_DIR/pnpm-lock.yaml"
  fi
  if [[ -f "$ARTIFACT_SOURCE/npm-shrinkwrap.json" ]]; then
    cp "$ARTIFACT_SOURCE/npm-shrinkwrap.json" "$PAYLOAD_DIR/npm-shrinkwrap.json"
  fi

  mkdir -p "$PAYLOAD_DIR/runtime/node/bin"
  cp "$NODE_EXECUTABLE" "$PAYLOAD_DIR/runtime/node/bin/node"
  chmod +x "$PAYLOAD_DIR/runtime/node/bin/node"
fi

SOURCE_VERSION=""
if [[ -f "$ARTIFACT_SOURCE/package.json" ]]; then
  SOURCE_VERSION="$(node -e "const fs=require('fs'); const path=process.argv[1]; const pkg=JSON.parse(fs.readFileSync(path,'utf8')); process.stdout.write(pkg.version || '');" "$ARTIFACT_SOURCE/package.json" 2>/dev/null || true)"
fi

if [[ -z "$SOURCE_VERSION" && "$MODE" == "libexec" ]]; then
  SOURCE_VERSION="$("$PAYLOAD_DIR/libexec/openclaw" --version 2>/dev/null | head -n 1 | tr -d '\r' || true)"
fi

DIST_KIND="managed-native-binary"
if [[ "$MODE" == "dist" ]]; then
  DIST_KIND="managed-node-runtime"
elif [[ -f "$PAYLOAD_DIR/openclaw.mjs" ]] && \
     [[ -d "$PAYLOAD_DIR/dist" ]] && \
     { [[ -x "$PAYLOAD_DIR/runtime/node/bin/node" ]] || [[ -x "$PAYLOAD_DIR/node/bin/node" ]]; }; then
  DIST_KIND="managed-native-launcher"
fi

node <<'EOF' "$PAYLOAD_DIR/managed-runtime.json" "$SOURCE_VERSION" "$DIST_KIND" "$ARTIFACT_SOURCE" "$NODE_EXECUTABLE" "$MODE"
const fs = require('fs');
const [manifestPath, runtimeVersion, distributionKind, sourcePath, nodeExecutable, mode] = process.argv.slice(2);
const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
if (runtimeVersion && runtimeVersion.trim()) {
  manifest.runtimeVersion = runtimeVersion.trim();
}
manifest.distributionKind = distributionKind;
manifest.hydration = {
  mode,
  sourcePath,
  nodeExecutable: nodeExecutable || null,
  hydratedAt: new Date().toISOString()
};
fs.writeFileSync(manifestPath, JSON.stringify(manifest, null, 2) + '\n');
EOF

node <<'EOF' "$PAYLOAD_DIR/hydration-receipt.json" "$ARTIFACT_SOURCE" "$NODE_EXECUTABLE" "$MODE" "$SOURCE_VERSION"
const fs = require('fs');
const [receiptPath, sourcePath, nodeExecutable, mode, runtimeVersion] = process.argv.slice(2);
const receipt = {
  hydratedAt: new Date().toISOString(),
  mode,
  sourcePath,
  nodeExecutable: nodeExecutable || null,
  runtimeVersion: runtimeVersion || null
};
fs.writeFileSync(receiptPath, JSON.stringify(receipt, null, 2) + '\n');
EOF

chmod +x "$PAYLOAD_DIR/bin/openclaw"

echo "Hydrated managed OpenClaw runtime payload:"
echo "  payload: $PAYLOAD_DIR"
echo "  mode: $MODE"
echo "  source: $ARTIFACT_SOURCE"
if [[ -n "$NODE_EXECUTABLE" ]]; then
  echo "  bundled node: $NODE_EXECUTABLE"
fi

if [[ "$SYNC_AFTER_HYDRATE" == "1" ]]; then
  bash "$ROOT_DIR/scripts/sync-openclaw-managed-runtime.sh"
fi
