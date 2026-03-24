#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/Multi-Agent-Flow.xcodeproj"
SCHEME="Multi-Agent-Flow"
DERIVED_DATA_PATH="$ROOT_DIR/.build/DerivedDataOpenClawRuntimeCoexistenceValidation"

echo "Validating managed runtime payload sync..."
bash "$ROOT_DIR/scripts/validate-openclaw-managed-runtime.sh"

echo
echo "Running desktop coexistence path-resolution checks..."
npx tsx --test \
  "$ROOT_DIR/apps/desktop/scripts/openclaw-host.test.ts" \
  "$ROOT_DIR/apps/desktop/scripts/openclaw-local-runtime.test.ts" \
  "$ROOT_DIR/apps/desktop/scripts/openclaw-discovery.test.ts"

echo
echo "Running macOS managed-runtime coexistence acceptance tests..."
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -destination "platform=macOS" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:Multi-Agent-FlowTests/OpenClawPathResolutionTests/testLocalBinaryPathCandidatesPreferManagedRuntimeRootsWhenAppManaged \
  -only-testing:Multi-Agent-FlowTests/OpenClawPathResolutionTests/testLocalBinaryPathCandidatesStayExplicitWhenRuntimeIsExternallyManaged \
  -only-testing:Multi-Agent-FlowTests/OpenClawManagedRuntimeSupervisorTests/testBuildLaunchCommandPlanUsesManagedRuntimeBinaryForAppManagedConfig \
  -only-testing:Multi-Agent-FlowTests/OpenClawManagedRuntimeSupervisorTests/testStartReassignsManagedRuntimePortWhenPreferredPortIsOccupied \
  -only-testing:Multi-Agent-FlowTests/OpenClawManagedRuntimeManagerTests/testManagedRuntimeDiagnosticSummaryIncludesCrashRecoveryAndPaths \
  -only-testing:Multi-Agent-FlowTests/OpenClawManagedRuntimeManagerTests/testManagerStartManagedRuntimeReassignsPortAndSyncsEffectivePort \
  test

echo
echo "OpenClaw local coexistence validation passed."
