import test from "node:test";
import assert from "node:assert/strict";
import { toSwiftDate } from "@multi-agent-flow/core";
import type { OpenClawRecoveryReportSnapshot, ProjectOpenClawSnapshot } from "@multi-agent-flow/domain";
import { buildOpenClawRetryPolicy } from "../src/openclaw-retry-policy";

function createRecoveryReport(overrides: Partial<OpenClawRecoveryReportSnapshot>): OpenClawRecoveryReportSnapshot {
  return {
    createdAt: toSwiftDate(Date.now() - 120_000),
    status: "completed",
    summary: "Recovery completed.",
    completedSteps: ["Reconnect OpenClaw"],
    manualSteps: [],
    findings: [],
    before: {
      label: "Blocked",
      summary: "before",
      layers: "transport=degraded, auth=degraded, session=degraded, inventory=ready"
    },
    after: {
      label: "Ready",
      summary: "after",
      layers: "transport=ready, auth=ready, session=ready, inventory=ready"
    },
    ...overrides
  };
}

function createOpenClawSnapshot(overrides: Partial<ProjectOpenClawSnapshot> = {}): ProjectOpenClawSnapshot {
  return {
    config: {
      deploymentKind: "local",
      runtimeOwnership: "appManaged",
      host: "127.0.0.1",
      port: 18789,
      useSSL: false,
      apiKey: "",
      defaultAgent: "default",
      timeout: 30,
      autoConnect: true,
      localBinaryPath: "",
      container: {
        engine: "docker",
        containerName: "openclaw-dev",
        workspaceMountPath: "/workspace"
      },
      cliQuietMode: true,
      cliLogLevel: "warning"
    },
    isConnected: false,
    availableAgents: [],
    activeAgents: [],
    detectedAgents: [],
    connectionState: {
      phase: "degraded",
      deploymentKind: "local",
      capabilities: {
        cliAvailable: true,
        gatewayReachable: false,
        gatewayAuthenticated: false,
        agentListingAvailable: true,
        sessionHistoryAvailable: false,
        gatewayAgentAvailable: false,
        gatewayChatAvailable: false,
        projectAttachmentSupported: true
      },
      health: {
        degradationReason: "Gateway probe failed."
      }
    },
    lastProbeReport: null,
    recoveryReports: [],
    sessionBackupPath: null,
    sessionMirrorPath: null,
    lastSyncedAt: toSwiftDate(Date.now()),
    ...overrides
  };
}

test("retry policy allows smart retry when there is no recovery history yet", () => {
  const policy = buildOpenClawRetryPolicy(createOpenClawSnapshot());

  assert.equal(policy.status, "allowed");
  assert.equal(policy.canAutoRetry, true);
  assert.equal(policy.immediate, true);
  assert.deepEqual(policy.plannedCommands, ["connect"]);
  assert.equal(policy.retryBudgetRemaining, 2);
});

test("retry policy blocks smart retry when manual follow-up is still required", () => {
  const policy = buildOpenClawRetryPolicy(
    createOpenClawSnapshot({
      recoveryReports: [
        createRecoveryReport({
          status: "manual_follow_up",
          summary: "Manual fix required.",
          manualSteps: ["Refresh remote credentials"],
          after: {
            label: "Blocked",
            summary: "still blocked",
            layers: "transport=ready, auth=degraded, session=degraded, inventory=unavailable"
          }
        })
      ]
    })
  );

  assert.equal(policy.status, "blocked");
  assert.equal(policy.canAutoRetry, false);
  assert.match(policy.title, /blocked/i);
  assert.ok(policy.rationale.length > 0);
});

test("retry policy blocks when recent partial attempts consume the retry budget", () => {
  const now = Date.now();
  const policy = buildOpenClawRetryPolicy(
    createOpenClawSnapshot({
      recoveryReports: [
        createRecoveryReport({
          createdAt: toSwiftDate(now - 180_000),
          status: "partial",
          before: { label: "Blocked", summary: "before", layers: "x" },
          after: { label: "Blocked", summary: "after", layers: "x" }
        }),
        createRecoveryReport({
          createdAt: toSwiftDate(now - 360_000),
          status: "partial",
          before: { label: "Blocked", summary: "before", layers: "x" },
          after: { label: "Blocked", summary: "after", layers: "x" }
        })
      ]
    }),
    { now }
  );

  assert.equal(policy.status, "blocked");
  assert.equal(policy.canAutoRetry, false);
  assert.equal(policy.retryBudgetRemaining, 0);
  assert.match(policy.title, /budget/i);
});

test("retry policy allows a new smart retry when older history includes improvement", () => {
  const now = Date.now();
  const policy = buildOpenClawRetryPolicy(
    createOpenClawSnapshot({
      recoveryReports: [
        createRecoveryReport({
          createdAt: toSwiftDate(now - 180_000),
          status: "failed",
          before: { label: "Blocked", summary: "before", layers: "x" },
          after: { label: "Blocked", summary: "after", layers: "x" }
        }),
        createRecoveryReport({
          createdAt: toSwiftDate(now - 360_000),
          status: "completed",
          before: { label: "Blocked", summary: "before", layers: "x" },
          after: { label: "Ready", summary: "after", layers: "y" }
        })
      ]
    }),
    { now }
  );

  assert.equal(policy.status, "allowed");
  assert.equal(policy.canAutoRetry, true);
  assert.equal(policy.retryBudgetRemaining, 1);
});

test("retry policy enters cooldown after a fresh non-improving failure", () => {
  const now = Date.now();
  const policy = buildOpenClawRetryPolicy(
    createOpenClawSnapshot({
      recoveryReports: [
        createRecoveryReport({
          createdAt: toSwiftDate(now - 10_000),
          status: "failed",
          before: { label: "Blocked", summary: "before", layers: "x" },
          after: { label: "Blocked", summary: "after", layers: "x" }
        }),
        createRecoveryReport({
          createdAt: toSwiftDate(now - 180_000),
          status: "completed",
          before: { label: "Blocked", summary: "before", layers: "x" },
          after: { label: "Ready", summary: "after", layers: "y" }
        })
      ]
    }),
    { now, cooldownMs: 60_000 }
  );

  assert.equal(policy.status, "observe");
  assert.equal(policy.canAutoRetry, false);
  assert.equal(policy.immediate, false);
  assert.ok(policy.cooldownRemainingMs > 0);
});

test("retry policy reports no action when runtime is already ready", () => {
  const policy = buildOpenClawRetryPolicy(
    createOpenClawSnapshot({
      isConnected: true,
      connectionState: {
        phase: "ready",
        deploymentKind: "local",
        capabilities: {
          cliAvailable: true,
          gatewayReachable: true,
          gatewayAuthenticated: true,
          agentListingAvailable: true,
          sessionHistoryAvailable: true,
          gatewayAgentAvailable: true,
          gatewayChatAvailable: true,
          projectAttachmentSupported: true
        },
        health: {
          lastMessage: "Connected."
        }
      },
      lastProbeReport: {
        success: true,
        deploymentKind: "local",
        endpoint: "http://127.0.0.1:18789",
        layers: {
          transport: "ready",
          authentication: "ready",
          session: "ready",
          inventory: "ready"
        },
        capabilities: {
          cliAvailable: true,
          gatewayReachable: true,
          gatewayAuthenticated: true,
          agentListingAvailable: true,
          sessionHistoryAvailable: true,
          gatewayAgentAvailable: true,
          gatewayChatAvailable: true,
          projectAttachmentSupported: true
        },
        health: {
          lastMessage: "Connected."
        },
        availableAgents: ["planner"],
        message: "Connected.",
        warnings: [],
        sourceOfTruth: "test",
        observedDefaultTransports: ["cli", "ws"]
      }
    })
  );

  assert.equal(policy.status, "not_needed");
  assert.equal(policy.canAutoRetry, false);
  assert.deepEqual(policy.plannedCommands, []);
});
