#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/Multi-Agent-Flow.xcodeproj"
SCHEME="Multi-Agent-Flow"
DERIVED_DATA_PATH="$ROOT_DIR/.build/DerivedDataOpenClawRuntimeValidation"
FIXTURE_PATH="$ROOT_DIR/packages/core/fixtures/compat/runtime-protocol.maoproj"

echo "Validating OpenClaw runtime protocol fixture..."
npm run validate:compat --workspace @multi-agent-flow/core -- "$FIXTURE_PATH"

echo
echo "Running OpenClaw runtime acceptance tests..."
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -destination "platform=macOS" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -only-testing:Multi-Agent-FlowTests/OpsAnalyticsQueryTests/testRefreshPersistsRuntimeProtocolMetadataForExecutionResults \
  -only-testing:Multi-Agent-FlowTests/OpsAnalyticsQueryTests/testProtocolOutcomeFeedbackPromotesRepeatedRepairsIntoAgentMemory \
  -only-testing:Multi-Agent-FlowTests/OpsAnalyticsQueryTests/testRefreshPublishesProtocolHealthGoalCards \
  -only-testing:Multi-Agent-FlowTests/OpsAnalyticsQueryTests/testTraceDetailFallsBackToEventsWhenPreviewAndOutputAreMissing \
  -only-testing:Multi-Agent-FlowTests/OpsAnalyticsQueryTests/testRefreshIngestsExternalSessionBackupIntoTraceDetail \
  test

echo
echo "OpenClaw runtime protocol validation passed."
