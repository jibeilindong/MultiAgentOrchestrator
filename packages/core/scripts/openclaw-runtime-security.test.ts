import test from "node:test";
import assert from "node:assert/strict";
import {
  assessOpenClawSandboxSecurityFromText,
  parseOpenClawApprovalsSnapshotFromText
} from "../src/openclaw-runtime-security";

const unsafeSandboxPayload = JSON.stringify({
  docsUrl: "https://docs.openclaw.ai/sandbox",
  agentId: "taizi",
  sessionKey: "agent:taizi:main",
  mainSessionKey: "agent:taizi:main",
  sandbox: {
    mode: "off",
    scope: "agent",
    perSession: false,
    workspaceAccess: "none",
    workspaceRoot: "/Users/example/.openclaw/sandboxes",
    sessionIsSandboxed: false,
    tools: {
      allow: [
        "exec",
        "process",
        "read",
        "write",
        "edit",
        "apply_patch",
        "image",
        "sessions_list",
        "sessions_history",
        "sessions_send",
        "sessions_spawn",
        "sessions_yield",
        "subagents",
        "session_status"
      ],
      deny: ["browser"]
    }
  },
  elevated: {
    enabled: true,
    allowedByConfig: false,
    alwaysAllowedByConfig: false,
    allowFrom: {},
    failures: []
  }
});

const safeSandboxPayload = JSON.stringify({
  sandbox: {
    mode: "strict",
    sessionIsSandboxed: true,
    tools: {
      allow: ["read", "write", "edit"]
    }
  },
  elevated: {
    enabled: false,
    allowedByConfig: false,
    alwaysAllowedByConfig: false
  }
});

test("empty approvals snapshot is not treated as custom allow rules", () => {
  const snapshot = parseOpenClawApprovalsSnapshotFromText(
    JSON.stringify({
      file: {
        version: 1,
        defaults: {},
        agents: {}
      }
    })
  );

  assert.equal(snapshot.hasCustomEntries, false);
});

test("custom approvals snapshot is treated as elevated runtime risk", () => {
  const snapshot = parseOpenClawApprovalsSnapshotFromText(
    JSON.stringify({
      file: {
        version: 1,
        defaults: {
          exec: ["node"]
        },
        agents: {}
      }
    })
  );

  assert.equal(snapshot.hasCustomEntries, true);
});

test("unsafe sandbox payload blocks multi-agent execution when session tools are enabled", () => {
  const finding = assessOpenClawSandboxSecurityFromText(unsafeSandboxPayload, "taizi", false);

  assert.equal(finding.sandboxMode, "off");
  assert.equal(finding.sessionIsSandboxed, false);
  assert.deepEqual(finding.allowedDangerousTools, ["subagents", "sessions_send", "sessions_spawn"]);
  assert.equal(finding.blockingIssues.length, 2);
  assert.match(finding.blockingIssues.join(" "), /not running inside an enforced OpenClaw sandbox/i);
  assert.match(finding.blockingIssues.join(" "), /high-risk session tools/i);
});

test("custom exec approvals remain blocking when exec or process are still available", () => {
  const finding = assessOpenClawSandboxSecurityFromText(unsafeSandboxPayload, "taizi", true);

  assert.equal(finding.execToolAllowed, true);
  assert.equal(finding.processToolAllowed, true);
  assert.match(finding.blockingIssues.join(" "), /custom allow rules/i);
});

test("fake agent ids still parse as runtime policies and therefore do not fail closed by themselves", () => {
  const finding = assessOpenClawSandboxSecurityFromText(unsafeSandboxPayload, "definitely-not-real", false);

  assert.equal(finding.agentIdentifier, "definitely-not-real");
  assert.match(finding.blockingIssues.join(" "), /definitely-not-real/);
});

test("sandboxed payload with no dangerous tools or elevated mode does not block", () => {
  const finding = assessOpenClawSandboxSecurityFromText(safeSandboxPayload, "safe-agent", false);

  assert.equal(finding.blockingIssues.length, 0);
  assert.equal(finding.execToolAllowed, false);
  assert.equal(finding.processToolAllowed, false);
  assert.deepEqual(finding.allowedDangerousTools, []);
});
