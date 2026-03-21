#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/Multi-Agent-Flow.xcodeproj"
SCHEME="Multi-Agent-Flow"
DERIVED_DATA_PATH="$ROOT_DIR/.build/DerivedDataLiveTransportBenchmark"
ITERATIONS="${BENCHMARK_ITERATIONS:-1}"
TIMEOUT="${BENCHMARK_TIMEOUT:-240}"
TEST_DEFAULTS_DOMAINS=("Roney.MultiAgentFlow" "Roney.MultiAgentFlowTests")

cleanup() {
  for domain in "${TEST_DEFAULTS_DOMAINS[@]}"; do
    defaults delete "$domain" OPENCLAW_BENCHMARK_LIVE >/dev/null 2>&1 || true
    defaults delete "$domain" OPENCLAW_BENCHMARK_ITERATIONS >/dev/null 2>&1 || true
    defaults delete "$domain" OPENCLAW_BENCHMARK_TIMEOUT >/dev/null 2>&1 || true
  done
}

trap cleanup EXIT

for domain in "${TEST_DEFAULTS_DOMAINS[@]}"; do
  defaults write "$domain" OPENCLAW_BENCHMARK_LIVE -bool YES
  defaults write "$domain" OPENCLAW_BENCHMARK_ITERATIONS -int "$ITERATIONS"
  defaults write "$domain" OPENCLAW_BENCHMARK_TIMEOUT -float "$TIMEOUT"
done

echo "Running live transport benchmark test..."
set +e
OPENCLAW_BENCHMARK_LIVE=1 \
OPENCLAW_BENCHMARK_ITERATIONS="$ITERATIONS" \
OPENCLAW_BENCHMARK_TIMEOUT="$TIMEOUT" \
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -destination "platform=macOS" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -only-testing:Multi-Agent-FlowTests/OpenClawTransportBenchmarkLiveTests/testWorkflowHotPathLiveBenchmarkReportPrefersGatewayAgent \
  test
XCODEBUILD_STATUS=$?
set -e

echo
echo "Inspecting latest benchmark report..."
node "$ROOT_DIR/scripts/inspect-transport-benchmark.mjs"

if [[ "$XCODEBUILD_STATUS" -ne 0 ]]; then
  echo
  echo "xcodebuild exited with status $XCODEBUILD_STATUS after benchmark execution." >&2
fi

exit "$XCODEBUILD_STATUS"
