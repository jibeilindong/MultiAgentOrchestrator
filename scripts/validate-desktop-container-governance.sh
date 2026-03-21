#!/usr/bin/env bash
set -euo pipefail

IMAGE="${OPENCLAW_CONTAINER_IMAGE:-openclaw:local}"
WORKSPACE_MOUNT="${OPENCLAW_CONTAINER_WORKSPACE_MOUNT:-/workspace}"
CONTAINER_NAME="maf-governance-validate-$RANDOM"
HOST_TMPDIR="$(mktemp -d)"

cleanup() {
  docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
  rm -rf "$HOST_TMPDIR"
}
trap cleanup EXIT

echo "Checking Docker availability..."
docker ps >/dev/null

echo "Starting validation container from $IMAGE..."
docker run -d --rm \
  --name "$CONTAINER_NAME" \
  -v "$HOST_TMPDIR:$WORKSPACE_MOUNT" \
  -w "$WORKSPACE_MOUNT" \
  "$IMAGE" \
  sh -lc 'sleep 300' >/dev/null

echo "Resolving container OpenClaw config path..."
CONTAINER_HOME="$(docker exec "$CONTAINER_NAME" sh -lc 'printf %s "$HOME"')"
REPORTED_CONFIG_PATH="$(docker exec "$CONTAINER_NAME" sh -lc 'openclaw config file' | tail -n 1 | tr -d '\r')"
if [[ -z "$REPORTED_CONFIG_PATH" ]]; then
  echo "Failed to resolve OpenClaw config path from container CLI." >&2
  exit 1
fi

if [[ "$REPORTED_CONFIG_PATH" == "~/"* ]]; then
  RESOLVED_CONFIG_PATH="$CONTAINER_HOME/${REPORTED_CONFIG_PATH#\~/}"
else
  RESOLVED_CONFIG_PATH="$REPORTED_CONFIG_PATH"
fi
if [[ "$RESOLVED_CONFIG_PATH" == *"/~/"* ]]; then
  echo "Home expansion failed for config path: $RESOLVED_CONFIG_PATH" >&2
  exit 1
fi
ROOT_PATH="$(dirname "$RESOLVED_CONFIG_PATH")"
APPROVALS_PATH="$ROOT_PATH/exec-approvals.json"
BACKUP_DIR="$ROOT_PATH/backups/multi-agent-flow-governance"
BACKUP_CONFIG_PATH="$BACKUP_DIR/test-openclaw.json"
BACKUP_APPROVALS_PATH="$BACKUP_DIR/test-exec-approvals.json"
WORKSPACE_PATH="$WORKSPACE_MOUNT/workspace-alpha"

echo "Container home: $CONTAINER_HOME"
echo "CLI reported config path: $REPORTED_CONFIG_PATH"
echo "Resolved config path: $RESOLVED_CONFIG_PATH"

echo "Writing governance fixtures into container..."
docker exec "$CONTAINER_NAME" sh -lc "
set -e
mkdir -p $(printf '%q' "$ROOT_PATH")
cat > $(printf '%q' "$RESOLVED_CONFIG_PATH") <<'JSON'
{
  \"agents\": {
    \"list\": [
      {
        \"id\": \"alpha\",
        \"workspace\": \"$WORKSPACE_MOUNT/shared\",
        \"subagents\": { \"allowAgents\": [\"beta\"] }
      },
      {
        \"id\": \"beta\",
        \"workspace\": \"$WORKSPACE_MOUNT/shared\",
        \"subagents\": { \"allowAgents\": [\"alpha\"] }
      }
    ]
  },
  \"tools\": {
    \"elevated\": { \"enabled\": true },
    \"sandbox\": {
      \"tools\": {
        \"allow\": [\"subagents\", \"sessions_send\", \"sessions_spawn\", \"exec\", \"process\"]
      }
    }
  }
}
JSON
cat > $(printf '%q' "$APPROVALS_PATH") <<'JSON'
{
  \"version\": 1,
  \"defaults\": { \"exec\": true },
  \"agents\": { \"alpha\": { \"process\": true } }
}
JSON
mkdir -p $(printf '%q' "$WORKSPACE_MOUNT/shared")
"

echo "Verifying container CLI can read governance state before rewrite..."
APPROVALS_BEFORE="$(docker exec "$CONTAINER_NAME" sh -lc 'openclaw approvals get --json --timeout 1000')"
SANDBOX_BEFORE="$(docker exec "$CONTAINER_NAME" sh -lc 'openclaw sandbox explain --agent alpha --json')"
[[ "$APPROVALS_BEFORE" == *'"exists":true'* ]]
[[ "$APPROVALS_BEFORE" == *'"alpha"'* ]]
[[ "$SANDBOX_BEFORE" == *'"agentId":"alpha"'* || "$SANDBOX_BEFORE" == *'"agentId": "alpha"'* ]]
[[ "$SANDBOX_BEFORE" == *'"subagents"'* ]]
[[ "$SANDBOX_BEFORE" == *'"enabled": true'* ]]

echo "Exercising backup/write helpers against the live container filesystem..."
docker exec "$CONTAINER_NAME" sh -lc "
set -e
mkdir -p $(printf '%q' "$BACKUP_DIR")
cp $(printf '%q' "$RESOLVED_CONFIG_PATH") $(printf '%q' "$BACKUP_CONFIG_PATH")
cp $(printf '%q' "$APPROVALS_PATH") $(printf '%q' "$BACKUP_APPROVALS_PATH")
cat > $(printf '%q' "$RESOLVED_CONFIG_PATH") <<'JSON'
{
  \"agents\": {
    \"list\": [
      {
        \"id\": \"alpha\",
        \"workspace\": \"$WORKSPACE_PATH\",
        \"subagents\": { \"allowAgents\": [] }
      },
      {
        \"id\": \"beta\",
        \"workspace\": \"$WORKSPACE_MOUNT/workspace-beta\",
        \"subagents\": { \"allowAgents\": [] }
      }
    ]
  },
  \"tools\": {
    \"elevated\": { \"enabled\": false },
    \"sandbox\": {
      \"tools\": {
        \"allow\": [\"exec\", \"process\"],
        \"deny\": [\"subagents\", \"sessions_send\", \"sessions_spawn\"]
      }
    }
  }
}
JSON
cat > $(printf '%q' "$APPROVALS_PATH") <<'JSON'
{
  \"version\": 1,
  \"defaults\": {},
  \"agents\": {}
}
JSON
mkdir -p $(printf '%q' "$WORKSPACE_PATH")
"

echo "Verifying rewritten governance files..."
docker exec "$CONTAINER_NAME" sh -lc "
set -e
test -f $(printf '%q' "$BACKUP_CONFIG_PATH")
test -f $(printf '%q' "$BACKUP_APPROVALS_PATH")
test -d $(printf '%q' "$WORKSPACE_PATH")
grep -q '\"enabled\": false' $(printf '%q' "$RESOLVED_CONFIG_PATH")
grep -q '\"deny\": \\[\"subagents\", \"sessions_send\", \"sessions_spawn\"\\]' $(printf '%q' "$RESOLVED_CONFIG_PATH")
grep -q '\"allowAgents\": \\[\\]' $(printf '%q' "$RESOLVED_CONFIG_PATH")
grep -q '\"defaults\": {}' $(printf '%q' "$APPROVALS_PATH")
grep -q '\"agents\": {}' $(printf '%q' "$APPROVALS_PATH")
"

echo "Verifying container CLI sees rewritten governance state..."
APPROVALS_AFTER="$(docker exec "$CONTAINER_NAME" sh -lc 'openclaw approvals get --json --timeout 1000')"
SANDBOX_AFTER="$(docker exec "$CONTAINER_NAME" sh -lc 'openclaw sandbox explain --agent alpha --json')"
[[ "$APPROVALS_AFTER" == *'"exists":true'* ]]
[[ "$APPROVALS_AFTER" == *'"defaults":{}'* ]]
[[ "$APPROVALS_AFTER" == *'"agents":{}'* ]]
[[ "$SANDBOX_AFTER" == *'"enabled": false'* ]]
[[ "$SANDBOX_AFTER" == *'"deny"'* ]]
[[ "$SANDBOX_AFTER" == *'"sessions_send"'* ]]
[[ "$SANDBOX_AFTER" == *'"sessions_spawn"'* ]]
[[ "$SANDBOX_AFTER" == *'"subagents"'* ]]

echo "Checking whether 'openclaw agents list' is usable in this image..."
if docker exec "$CONTAINER_NAME" sh -lc 'openclaw agents list --json' >/tmp/maf_agents_list.out 2>/tmp/maf_agents_list.err; then
  echo "agents list returned successfully."
else
  echo "agents list is unavailable in this image; continuing because desktop governance already degrades when agent enumeration fails."
  sed -n '1,40p' /tmp/maf_agents_list.err
fi

echo "Container governance file-path and filesystem validation passed."
