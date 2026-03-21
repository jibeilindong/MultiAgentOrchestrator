#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/Multi-Agent-Flow.xcodeproj"
SCHEME="Multi-Agent-Flow"
CONFIGURATION="${CONFIGURATION:-Debug}"
DERIVED_DATA_PATH="$ROOT_DIR/.build/DerivedDataTransportBenchmark"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/Multi-Agent-Flow.app"
APP_BINARY="$APP_PATH/Contents/MacOS/Multi-Agent-Flow"
ITERATIONS="${BENCHMARK_ITERATIONS:-3}"
TIMEOUT="${BENCHMARK_TIMEOUT:-180}"
PROMPT="${BENCHMARK_PROMPT:-}"

echo "Building Multi-Agent-Flow benchmark runner..."
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "platform=macOS" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  build

if [[ ! -x "$APP_BINARY" ]]; then
  echo "App binary not found: $APP_BINARY" >&2
  exit 1
fi

echo
echo "Running transport benchmark..."
ARGS=(
  --run-transport-benchmark
  --benchmark-iterations "$ITERATIONS"
  --benchmark-timeout "$TIMEOUT"
)

if [[ -n "$PROMPT" ]]; then
  ARGS+=(--benchmark-prompt "$PROMPT")
fi

"$APP_BINARY" "${ARGS[@]}"

echo
echo "Inspecting latest benchmark report..."
node "$ROOT_DIR/scripts/inspect-transport-benchmark.mjs"
