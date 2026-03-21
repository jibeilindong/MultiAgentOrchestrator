#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/Multi-Agent-Flow.xcodeproj"
SCHEME="Multi-Agent-Flow"
DERIVED_DATA_PATH="$ROOT_DIR/.build/DerivedDataWorkflowHotPathValidation"

echo "Running workflow hot path routing regression tests..."
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -destination "platform=macOS" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -only-testing:Multi-Agent-FlowTests/OpenClawTransportRoutingTests \
  test

echo
echo "Workflow hot path routing validation passed."
