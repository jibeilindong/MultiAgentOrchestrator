#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_DIR="${OPENCLAW_UPSTREAM_SOURCE_DIR:-}"
OUTPUT_DIR="${OPENCLAW_NATIVE_PAYLOAD_OUTPUT_DIR:-$ROOT_DIR/.build/openclaw-managed-runtime-native-payload}"
NODE_EXECUTABLE="${OPENCLAW_MANAGED_NODE_EXECUTABLE:-}"
SWIFTC_EXECUTABLE="${SWIFTC_EXECUTABLE:-swiftc}"
INSTALL_NAME_TOOL_EXECUTABLE="${INSTALL_NAME_TOOL_EXECUTABLE:-install_name_tool}"
OTOOL_EXECUTABLE="${OTOOL_EXECUTABLE:-otool}"

usage() {
  cat <<'EOF'
Usage:
  bash ./scripts/build-openclaw-managed-runtime-native-payload.sh \
    --source /path/to/openclaw-source \
    [--output /path/to/output-payload] \
    [--node /path/to/node]

Expected upstream source tree contents:
  - openclaw.mjs
  - dist/entry.js or dist/entry.mjs

The script produces a native launcher payload:
  libexec/openclaw
  openclaw.mjs
  dist/
  runtime/node/bin/node
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source)
      SOURCE_DIR="${2:-}"
      shift 2
      ;;
    --output)
      OUTPUT_DIR="${2:-}"
      shift 2
      ;;
    --node)
      NODE_EXECUTABLE="${2:-}"
      shift 2
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

if [[ -z "$SOURCE_DIR" ]]; then
  echo "Missing required OpenClaw source directory." >&2
  usage >&2
  exit 1
fi

if [[ ! -d "$SOURCE_DIR" ]]; then
  echo "OpenClaw source directory does not exist: $SOURCE_DIR" >&2
  exit 1
fi

SOURCE_DIR="$(cd "$SOURCE_DIR" && pwd)"
mkdir -p "$(dirname "$OUTPUT_DIR")"
OUTPUT_DIR="$(mkdir -p "$OUTPUT_DIR" && cd "$OUTPUT_DIR" && pwd)"

if [[ -z "$NODE_EXECUTABLE" ]]; then
  NODE_EXECUTABLE="$(command -v node || true)"
fi

if [[ -z "$NODE_EXECUTABLE" ]] || [[ ! -x "$NODE_EXECUTABLE" ]]; then
  echo "Unable to find a usable node executable for bundling." >&2
  exit 1
fi

NODE_EXECUTABLE="$(python3 - "$NODE_EXECUTABLE" <<'EOF'
import os
import sys

print(os.path.realpath(sys.argv[1]))
EOF
)"
NODE_SOURCE_ROOT="$(cd "$(dirname "$NODE_EXECUTABLE")/.." && pwd -P)"

if [[ ! -f "$SOURCE_DIR/openclaw.mjs" ]]; then
  cat >&2 <<EOF
Upstream OpenClaw entrypoint is missing:
  $SOURCE_DIR/openclaw.mjs

Build the upstream source tree first with:
  pnpm install
  pnpm ui:build
  pnpm build
EOF
  exit 1
fi

if [[ ! -f "$SOURCE_DIR/dist/entry.js" ]] && [[ ! -f "$SOURCE_DIR/dist/entry.mjs" ]]; then
  cat >&2 <<EOF
Upstream OpenClaw build outputs are missing:
  $SOURCE_DIR/dist/entry.js
  $SOURCE_DIR/dist/entry.mjs

Build the upstream source tree first with:
  pnpm install
  pnpm ui:build
  pnpm build
EOF
  exit 1
fi

if ! command -v "$SWIFTC_EXECUTABLE" >/dev/null 2>&1; then
  echo "swiftc is required to build the native launcher payload." >&2
  exit 1
fi
if ! command -v "$INSTALL_NAME_TOOL_EXECUTABLE" >/dev/null 2>&1; then
  echo "install_name_tool is required to bundle the private Node runtime." >&2
  exit 1
fi
if ! command -v "$OTOOL_EXECUTABLE" >/dev/null 2>&1; then
  echo "otool is required to inspect Node runtime dependencies." >&2
  exit 1
fi

NODE_VERSION_RAW="$("$NODE_EXECUTABLE" --version | tr -d '\r')"
if ! "$NODE_EXECUTABLE" <<'EOF'
const version = process.versions.node.split('.').map((part) => Number(part || 0));
const [major = 0, minor = 0] = version;
process.exit(major > 22 || (major === 22 && minor >= 12) ? 0 : 1);
EOF
then
  cat >&2 <<EOF
Bundled node runtime is too old for OpenClaw:
  $NODE_EXECUTABLE ($NODE_VERSION_RAW)

OpenClaw requires Node.js v22.12+.
EOF
  exit 1
fi

rm -rf "$OUTPUT_DIR"
mkdir -p \
  "$OUTPUT_DIR/libexec" \
  "$OUTPUT_DIR/runtime/node/bin" \
  "$OUTPUT_DIR/runtime/node/lib"

cp "$SOURCE_DIR/openclaw.mjs" "$OUTPUT_DIR/openclaw.mjs"
chmod +x "$OUTPUT_DIR/openclaw.mjs"

cp -R "$SOURCE_DIR/dist" "$OUTPUT_DIR/dist"

if [[ -f "$SOURCE_DIR/package.json" ]]; then
  cp "$SOURCE_DIR/package.json" "$OUTPUT_DIR/package.json"
fi
if [[ -f "$SOURCE_DIR/pnpm-lock.yaml" ]]; then
  cp "$SOURCE_DIR/pnpm-lock.yaml" "$OUTPUT_DIR/pnpm-lock.yaml"
fi
if [[ -f "$SOURCE_DIR/package-lock.json" ]]; then
  cp "$SOURCE_DIR/package-lock.json" "$OUTPUT_DIR/package-lock.json"
fi
if [[ -f "$SOURCE_DIR/npm-shrinkwrap.json" ]]; then
  cp "$SOURCE_DIR/npm-shrinkwrap.json" "$OUTPUT_DIR/npm-shrinkwrap.json"
fi

SWIFT_SOURCE="$(mktemp "${TMPDIR:-/tmp}/openclaw-native-launcher.XXXXXX.swift")"
PROCESSED_BINARIES="$(mktemp "${TMPDIR:-/tmp}/openclaw-node-runtime.XXXXXX.list")"
cleanup() {
  rm -f "$SWIFT_SOURCE"
  rm -f "$PROCESSED_BINARIES"
}
trap cleanup EXIT

NODE_RUNTIME_ROOT="$OUTPUT_DIR/runtime/node"
NODE_RUNTIME_BIN_DIR="$NODE_RUNTIME_ROOT/bin"
NODE_RUNTIME_LIB_DIR="$NODE_RUNTIME_ROOT/lib"
NODE_TARGET_EXECUTABLE="$NODE_RUNTIME_BIN_DIR/node"

is_system_dependency() {
  local dependency="$1"
  case "$dependency" in
    /System/Library/*|/usr/lib/*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

resolve_dependency_path() {
  local dependency="$1"
  local origin_path="$2"
  local origin_dir

  origin_dir="$(dirname "$origin_path")"

  case "$dependency" in
    @rpath/*)
      local basename
      basename="${dependency#@rpath/}"
      for candidate in \
        "$NODE_SOURCE_ROOT/lib/$basename" \
        "$origin_dir/../lib/$basename" \
        "$origin_dir/$basename"; do
        if [[ -f "$candidate" ]]; then
          python3 - "$candidate" <<'EOF'
import os
import sys

print(os.path.realpath(sys.argv[1]))
EOF
          return 0
        fi
      done
      ;;
    @loader_path/*)
      local suffix
      suffix="${dependency#@loader_path/}"
      local candidate="$origin_dir/$suffix"
      if [[ -f "$candidate" ]]; then
        python3 - "$candidate" <<'EOF'
import os
import sys

print(os.path.realpath(sys.argv[1]))
EOF
        return 0
      fi
      ;;
    /*)
      if [[ -f "$dependency" ]]; then
        python3 - "$dependency" <<'EOF'
import os
import sys

print(os.path.realpath(sys.argv[1]))
EOF
        return 0
      fi
      ;;
  esac

  return 1
}

was_processed() {
  local source_path="$1"
  grep -Fqx "$source_path" "$PROCESSED_BINARIES" 2>/dev/null
}

mark_processed() {
  local source_path="$1"
  printf '%s\n' "$source_path" >>"$PROCESSED_BINARIES"
}

dependency_reference_for_target() {
  local target_path="$1"
  local dependency_basename="$2"

  if [[ "$target_path" == "$NODE_TARGET_EXECUTABLE" ]]; then
    printf '%s\n' "@loader_path/../lib/$dependency_basename"
    return 0
  fi

  printf '%s\n' "@loader_path/$dependency_basename"
}

bundle_macos_binary() {
  local source_path="$1"
  local target_path="$2"
  local binary_kind="$3"
  local dependency
  local resolved_dependency
  local dependency_basename
  local target_dependency
  local rewritten_reference

  if [[ ! -f "$target_path" ]]; then
    cp "$source_path" "$target_path"
  fi
  chmod u+w "$target_path"

  if [[ "$binary_kind" == "dylib" ]]; then
    "$INSTALL_NAME_TOOL_EXECUTABLE" -id "@loader_path/$(basename "$target_path")" "$target_path"
  fi

  if was_processed "$source_path"; then
    return 0
  fi
  mark_processed "$source_path"

  while IFS= read -r dependency; do
    [[ -z "$dependency" ]] && continue
    if is_system_dependency "$dependency"; then
      continue
    fi

    resolved_dependency="$(resolve_dependency_path "$dependency" "$source_path" || true)"
    if [[ -z "$resolved_dependency" ]]; then
      echo "Unable to resolve Node runtime dependency: $dependency (from $source_path)" >&2
      exit 1
    fi

    dependency_basename="$(basename "$resolved_dependency")"
    target_dependency="$NODE_RUNTIME_LIB_DIR/$dependency_basename"
    bundle_macos_binary "$resolved_dependency" "$target_dependency" "dylib"
    rewritten_reference="$(dependency_reference_for_target "$target_path" "$dependency_basename")"
    "$INSTALL_NAME_TOOL_EXECUTABLE" -change "$dependency" "$rewritten_reference" "$target_path"
  done < <("$OTOOL_EXECUTABLE" -L "$source_path" | tail -n +2 | awk '{print $1}')
}

bundle_macos_binary "$NODE_EXECUTABLE" "$NODE_TARGET_EXECUTABLE" "executable"
chmod +x "$NODE_TARGET_EXECUTABLE"

cat >"$SWIFT_SOURCE" <<'EOF'
import Foundation
import Darwin

@inline(__always)
func fail(_ message: String, code: Int32) -> Never {
    if let data = (message + "\n").data(using: .utf8) {
        FileHandle.standardError.write(data)
    }
    exit(code)
}

let fileManager = FileManager.default
let executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
let payloadRootURL = executableURL.deletingLastPathComponent().deletingLastPathComponent()

let nodeCandidates = [
    payloadRootURL.appendingPathComponent("runtime/node/bin/node", isDirectory: false),
    payloadRootURL.appendingPathComponent("node/bin/node", isDirectory: false)
]

guard let nodeURL = nodeCandidates.first(where: { fileManager.isExecutableFile(atPath: $0.path) }) else {
    fail(
        """
        openclaw managed runtime launcher: missing bundled node runtime.
        Expected one of:
        - \(payloadRootURL.appendingPathComponent("runtime/node/bin/node").path)
        - \(payloadRootURL.appendingPathComponent("node/bin/node").path)
        """,
        code: 71
    )
}

let entrypointURL = payloadRootURL.appendingPathComponent("openclaw.mjs", isDirectory: false)
guard fileManager.fileExists(atPath: entrypointURL.path) else {
    fail(
        "openclaw managed runtime launcher: missing upstream entrypoint at \(entrypointURL.path)",
        code: 72
    )
}

let entryCandidates = [
    payloadRootURL.appendingPathComponent("dist/entry.js", isDirectory: false),
    payloadRootURL.appendingPathComponent("dist/entry.mjs", isDirectory: false)
]

guard entryCandidates.contains(where: { fileManager.fileExists(atPath: $0.path) }) else {
    fail(
        """
        openclaw managed runtime launcher: missing upstream build output.
        Expected one of:
        - \(payloadRootURL.appendingPathComponent("dist/entry.js").path)
        - \(payloadRootURL.appendingPathComponent("dist/entry.mjs").path)
        """,
        code: 73
    )
}

var execArguments = [nodeURL.path, entrypointURL.path]
execArguments.append(contentsOf: CommandLine.arguments.dropFirst())

var cArguments = execArguments.map { strdup($0) } + [nil]
defer {
    for case let argument? in cArguments {
        free(argument)
    }
}

let execResult = cArguments.withUnsafeMutableBufferPointer { bufferPointer -> Int32 in
    guard let baseAddress = bufferPointer.baseAddress else {
        return -1
    }
    return execv(nodeURL.path, baseAddress)
}

let errnoValue = errno
if execResult == -1 {
    fail(
        "openclaw managed runtime launcher: execv failed for \(nodeURL.path) (\(String(cString: strerror(errnoValue))))",
        code: 74
    )
}

fail("openclaw managed runtime launcher: execv returned unexpectedly.", code: 75)
EOF

"$SWIFTC_EXECUTABLE" \
  -O \
  "$SWIFT_SOURCE" \
  -o "$OUTPUT_DIR/libexec/openclaw"
chmod +x "$OUTPUT_DIR/libexec/openclaw"

echo "Built native OpenClaw managed runtime payload:"
echo "  source: $SOURCE_DIR"
echo "  output: $OUTPUT_DIR"
echo "  bundled node: $NODE_EXECUTABLE"
echo "  node version: $NODE_VERSION_RAW"
