import test from "node:test";
import assert from "node:assert/strict";
import type { ProjectOpenClawSnapshot } from "@multi-agent-flow/domain";
import { buildOpenClawRecoveryReport } from "../src/openclaw-recovery-report";

function createOpenClawSnapshot(overrides: Partial<ProjectOpenClawSnapshot> = {}): ProjectOpenClawSnapshot {
  return {
    config: {
      deploymentKind: "local",
      runtimeOwnership: "externalLocal",
      host: "127.0.0.1",
      port: 18789,
      useSSL: false,
      apiKey: "",
      defaultAgent: "default",
      timeout: 30,
      autoConnect: true,
      localBinaryPath: "/usr/local/bin/openclaw",
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
      phase: "idle",
      deploymentKind: "local",
      capabilities: {
        cliAvailable: false,
        gatewayReachable: false,
        gatewayAuthenticated: false,
        agentListingAvailable: false,
        sessionHistoryAvailable: false,
        gatewayAgentAvailable: false,
        gatewayChatAvailable: false,
        projectAttachmentSupported: false
      },
      health: {
        lastProbeAt: null,
        lastHeartbeatAt: null,
        latencyMs: null,
        degradationReason: null,
        lastMessage: null
      }
    },
    lastProbeReport: null,
    sessionBackupPath: null,
    sessionMirrorPath: null,
    lastSyncedAt: 1_700_000_000,
    ...overrides
  };
}

test("recovery report captures readiness improvements", () => {
  const before = createOpenClawSnapshot();
  const after = createOpenClawSnapshot({
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
        lastMessage: "Connected to OpenClaw CLI and gateway."
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
        lastMessage: "Connected to OpenClaw CLI and gateway."
      },
      availableAgents: ["planner"],
      message: "Connected to OpenClaw CLI and gateway.",
      warnings: [],
      sourceOfTruth: "test",
      observedDefaultTransports: ["cli", "ws"]
    }
  });

  const report = buildOpenClawRecoveryReport({
    before,
    after,
    createdAt: 1_700_000_100,
    completedSteps: ["Reconnect OpenClaw", "Refresh agent inventory"]
  });

  assert.equal(report.status, "completed");
  assert.equal(report.createdAt, 1_700_000_100);
  assert.match(report.summary, /Reconnect OpenClaw -> Refresh agent inventory/);
  assert.match(report.findings.join(" "), /Readiness changed from Idle to Ready/);
});

test("recovery report preserves manual follow-up status", () => {
  const before = createOpenClawSnapshot();
  const after = createOpenClawSnapshot();

  const report = buildOpenClawRecoveryReport({
    before,
    after,
    createdAt: 1_700_000_101,
    completedSteps: [],
    manualSteps: ["Add a remote API key before retrying gateway authentication."]
  });

  assert.equal(report.status, "manual_follow_up");
  assert.match(report.summary, /manual follow-up/i);
  assert.equal(report.manualSteps.length, 1);
});

test("recovery report captures failure after partial progress", () => {
  const before = createOpenClawSnapshot();
  const after = createOpenClawSnapshot({
    isConnected: true,
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
    }
  });

  const report = buildOpenClawRecoveryReport({
    before,
    after,
    createdAt: 1_700_000_102,
    completedSteps: ["Reconnect OpenClaw"],
    errorMessage: "Gateway websocket closed unexpectedly."
  });

  assert.equal(report.status, "failed");
  assert.match(report.summary, /failed after Reconnect OpenClaw/i);
});
